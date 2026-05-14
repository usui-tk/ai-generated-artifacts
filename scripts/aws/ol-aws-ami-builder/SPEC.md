# Developer Specification (SPEC)

> **Purpose of this document**
>
> This file is the authoritative specification for maintaining and extending
> the `build-ol-aws-ami.sh` wrapper script and its companion env templates
> in this directory. It is written to be picked up directly by a human
> contributor or an LLM (Claude) at the start of a new feature or bug-fix
> iteration so that conventions do not have to be re-derived from scratch.
>
> **The single most important rule**: when a piece of behavior is described
> here (phase contract, log markers, env property keys, validation order),
> any new feature MUST reuse the existing implementation. Do not redesign
> the phase numbering, log marker set, or the env property auto-detection
> rules — they have been hardened through many revisions documented in
> Part C, and rewriting them invites regressions.
>
> The repository-wide ⚠️ AI generation policy (see
> [`../../README.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/scripts/README.md))
> still applies; this SPEC supplements it with implementation-level detail
> specific to the Oracle Linux AWS AMI builder.

🇯🇵 **日本語版仕様書は [SPEC.ja.md](./SPEC.ja.md) を参照してください。**

---

## Table of Contents

- [Part A — Common Specification](#part-a--common-specification)
  - [A.1 Reference Assets](#a1-reference-assets)
  - [A.2 Source File Format](#a2-source-file-format)
  - [A.3 Pipeline Architecture (9 phases)](#a3-pipeline-architecture-9-phases)
  - [A.4 Logging Conventions](#a4-logging-conventions)
  - [A.5 Shell Options and Defensive Coding](#a5-shell-options-and-defensive-coding)
  - [A.6 Parameter Conventions](#a6-parameter-conventions)
  - [A.7 Env Property File Conventions](#a7-env-property-file-conventions)
  - [A.8 Oracle Linux Version Auto-detection](#a8-oracle-linux-version-auto-detection)
  - [A.9 Error & Diagnostic Conventions](#a9-error--diagnostic-conventions)
  - [A.10 Bilingual Documentation](#a10-bilingual-documentation)
  - [A.11 Development Workflow](#a11-development-workflow)
- [Part B — Script-specific Specifications](#part-b--script-specific-specifications)
  - [B.1 build-ol-aws-ami.sh](#b1-build-ol-aws-amish)
  - [B.2 setup-vmimport-role.sh](#b2-setup-vmimport-rolesh)
  - [B.3 env.properties.aws-ol{7,8,9,10}](#b3-envpropertiesaws-ol78910)
- [Part C — Known Pitfalls & Lessons Learned](#part-c--known-pitfalls--lessons-learned)

---

# Part A — Common Specification

## A.1 Reference Assets

These are the canonical sources of truth. **Pull from these directly; do not re-implement.**

### A.1.1 Canonical scripts

```
build-ol-aws-ami.sh         the main orchestrator; all 9 phases
setup-vmimport-role.sh      one-time AWS IAM role bootstrap
```

These scripts are the canonical source for:

- `log_step` / `log_info` / `log_warn` / `log_error` / `die` (output helpers)
- `detect_ec2_environment` / `guide_ec2_kvm_issue` (EC2 self-diagnosis)
- `detect_qemu_user` / `phase2_grant_qemu_access` (libvirt ACL bootstrap)
- `parse_ol_version_from_iso` / `detect_os_variant` (OL version inference)
- `derive_oracle_checksum_url` (ISO checksum URL fallback chain)

### A.1.2 Upstream dependency

The script is a wrapper around Oracle's official tool:

```
https://github.com/oracle/oracle-linux/tree/main/oracle-linux-image-tools
```

Specifically, Phase 5 invokes `bin/build-image.sh` from a clone of that
repository. Behavior changes upstream (e.g. supported `BOOT_MODE` values,
distribution slug naming, environment variable keys) must be tracked here
and reflected in `load_env` validation.

### A.1.3 Companion files

```
env.properties.aws-ol10     Oracle Linux 10 Update 1 template
env.properties.aws-ol9      Oracle Linux 9  Update 7 template
env.properties.aws-ol8      Oracle Linux 8  Update 10 template
env.properties.aws-ol7      Oracle Linux 7  Update 9 template (experimental — see B.3, C.10)
README.md / README.ja.md    end-user documentation (bilingual)
SPEC.md  / SPEC.ja.md       this developer specification (bilingual)
```

### A.1.4 Workspace path convention

`WORKSPACE` defaults to `/tmp/ol{N}-build-ws` (where `{N}` is the OL major
version). The path is chosen specifically because `/tmp` is world-traversable
by FHS convention, which avoids libvirt's qemu user (uid 107) being unable
to reach files placed under `/root` or other restricted parents. See A.7
and C.3 for the full rationale.

---

## A.2 Source File Format

### File structure (top-to-bottom)

```
1. Shebang                            #!/usr/bin/env bash
2. Header banner (BoxArt block)       Purpose / Prerequisites / Usage / Limitations / AI info
3. set -euo pipefail                  Mandatory; see A.5
4. Constants (readonly)               OL_REPO_URL, OL_TOOLS_SUBDIR, DEFAULT_ISO_URL
5. Execution mode globals             SKIP_PREREQ, SKIP_AWS_IMPORT, BUILD_ONLY, ENV_FILE
6. Logging helpers                    log_step, log_info, log_warn, log_error, die
7. Argument parsing                   usage, parse_args
8. Environment loading                parse_ol_version_from_iso, load_env
9. EC2 helpers                        detect_ec2_environment, guide_ec2_kvm_issue
10. Phase 0–8 functions               phase0_preflight_checks ... phase8_register_ami
11. Helper functions interleaved      detect_qemu_user, derive_oracle_checksum_url, detect_os_variant
12. main()                            Calls phase0..phase8 with skip/build-only branching
13. Bottom-of-file invocation         main "$@"
```

The header banner MUST contain the five sections required by the
repository-level `scripts/README.md` policy:

| Section | Required content |
|---------|------------------|
| Purpose | One paragraph; what the script does and why |
| Prerequisites | Runtime, permissions, required CLIs |
| Usage examples | At least two invocations |
| Known limitations | aarch64, BOOT_MODE constraints, concurrency limits |
| AI generation info | Tool name, generation date |

---

## A.3 Pipeline Architecture (9 phases)

### Numbering rules

- Phases are numbered **0 through 8 with no gaps** (no `Phase 1.5`).
- Phase function names follow `phase{N}_<verb>_<noun>()` (snake_case).
- Phase 0 is preflight; subsequent phases assume Phase 0 passed.

### Phase registry

| ID | Function | Group | Responsibility |
|---:|----------|-------|----------------|
| 0 | `phase0_preflight_checks` | Validation | KVM exposure, required commands, free disk, tmpfs/noexec checks |
| 1 | `phase1_install_prerequisites` | Provisioning | Install KVM/libvirt/virt-install/libguestfs/osinfo-db/acl |
| 2 | `phase2_grant_qemu_access` | Provisioning | setfacl `u:qemu:x` on WORKSPACE parent chain |
| 3 | `phase3_clone_repository` | Build | `git clone --depth 1` of oracle/oracle-linux. **For OL7 only**: rewrites the OL7-blocking line in `cloud/aws/image-scripts.sh` to a no-op (`.ol7-patch.bak` backup left in place). See C.10. |
| 4 | `phase4_prepare_env_properties` | Build | Resolve ISO checksum, OS_VARIANT, generate `env.properties.local` |
| 5 | `phase5_run_build` | Build | Invoke `bin/build-image.sh`; produce VMDK |
| 6 | `phase6_upload_to_s3` | AWS | `aws s3 cp` the VMDK |
| 7 | `phase7_import_snapshot` | AWS | `import-snapshot` + polling loop |
| 8 | `phase8_register_ami` | AWS | `register-image` with conditional `--tpm-support` |

### Phase groups (semantic)

- **Validation** (0): Read-only diagnostics; never mutates state.
- **Provisioning** (1, 2): Requires sudo; idempotent (skip if already done).
- **Build** (3, 4, 5): Operates inside `WORKSPACE`; produces a VMDK.
- **AWS** (6, 7, 8): Network operations against the configured `AWS_REGION`.

### Phase entry/exit contract

Every phase MUST:

1. Call `log_step "Phase {N}: <one-line summary>"` on entry.
2. On failure, call `die "<actionable error message>"` (which exits 1).
3. On success, return naturally (do NOT call `exit 0`); `set -e` will catch
   any unhandled non-zero exit before this point.
4. Export any state needed by later phases as plain shell variables
   (e.g. `VMDK_PATH`, `S3_KEY`, `SNAPSHOT_ID`).

### Skip / partial-execution semantics

- `--skip-prereq` → Skip Phase 1 only (Phase 2 still runs, since ACLs may
  need refreshing even when packages are installed).
- `--build-only` → Run through Phase 5, then exit 0.
- `--skip-aws-import` → Synonym for `--build-only`.

---

## A.4 Logging Conventions

### Markers (color-coded)

| Marker | Helper | ANSI Color | Semantic |
|--------|--------|------------|----------|
| `[STEP]` | `log_step` | Bold green | Phase header banner |
| `[INFO]` | `log_info` | Bold blue | Informational; progress |
| `[WARN]` | `log_warn` | Bold yellow | Degraded but non-fatal |
| `[ERROR]` | `log_error` | Bold red | Failure; usually followed by `die` |

### Line format

```
[MARKER] YYYY-MM-DD HH:MM:SS <message>
```

- The timestamp is local wall-clock time (`date '+%Y-%m-%d %H:%M:%S'`).
- The marker / color combination is the only acceptable styling. Do not
  invent new markers (`[DEBUG]`, `[OK]`, `[!]`); they break the visual
  scan pattern that operators rely on across many runs.
- All ERROR output goes to `>&2`; INFO/WARN/STEP go to stdout.

### Banner blocks

Phase headers use `log_step`, which prepends a 60-character `=` rule:

```
========== Phase 5: Running oracle-linux-image-tools to build the VMDK ==========
```

This is the only acceptable phase banner format. Do not add box-drawing
characters or vary the width; many users grep on `^==========` to navigate
long logs.

---

## A.5 Shell Options and Defensive Coding

### Mandatory `set -euo pipefail`

Every script in this directory MUST use `set -euo pipefail`. The options
catch the three most common bash failure modes:

- `-e` (`errexit`): abort on any non-zero exit.
- `-u` (`nounset`): abort on undefined variable reference.
- `-o pipefail`: propagate failures through pipelines.

### Defensive coding rules

1. **Every `${VAR:?...}` or `${VAR:=...}` assignment** must be paired with
   a `log_info` line confirming the resolved value, so operators can
   verify config in the log.
2. **Use `${VAR:-}` form** for any variable that may legitimately be
   unset (env-file optionals); never bare `${VAR}` under `-u`.
3. **Functions whose last statement is `[[ ... ]] && die`** must end
   with an explicit `return 0` to avoid leaking exit 1 to the caller.
   See C.1 for the historical bug.
4. **Trailing `|| true`** is acceptable only when the failure path is
   genuinely informational (e.g. `curl ... | head -1 || true`) and
   followed by an empty-result check.

### `&& die` pattern

Pattern:

```bash
[[ -f "${REQUIRED_FILE}" ]] || die "Missing required file: ${REQUIRED_FILE}"
```

This is fine **when it is not the final statement of a function** under
`set -e`. When used as the final statement, the function returns 1 on the
success branch (because `[[ ]]` returned 0, but the `||` expression
returned the right-hand-side's exit code... actually returned 0, but bash's
treatment of `&& die` final-statement is well-documented as a footgun).
See C.1 for the real-world incident.

### Caller pattern for libguestfs

Phase 5 sets `LIBGUESTFS_BACKEND=direct` before invoking
`bin/build-image.sh` to bypass libvirt's qemu user permission model. This
is **non-negotiable**; see C.6.

---

## A.6 Parameter Conventions

### Command-line switches

| Switch | Type | Required | Description |
|--------|------|----------|-------------|
| `--env <file>` | path | ✓ | Path to env.properties file |
| `--skip-prereq` | flag | | Skip Phase 1 (package installation) |
| `--skip-aws-import` | flag | | Skip Phases 6–8 (build VMDK only) |
| `--build-only` | flag | | Synonym for `--skip-aws-import` |
| `-h`, `--help` | flag | | Show help and exit 0 |

### Mutual exclusion

- `--skip-aws-import` and `--build-only` are synonyms; either may be
  passed but combining them is redundant (no error, but log a notice).
- `--skip-prereq` is independent and may combine with the others.

### Unknown switches

`parse_args` MUST `die "Unknown option: $1"` on any unrecognized switch.
Do NOT silently ignore unknown options; this is how typos slip into CI
configurations and silently disable safety checks.

---

## A.7 Env Property File Conventions

### File format

```
KEY="value"     # bash assignment, quoted to allow spaces
# Comments start with # at column 0
```

The file is `source`'d into the script's environment, so it must be valid
bash. Avoid command substitutions in env files (security and reproducibility).

### Required keys

| Key | Required | Default | Notes |
|-----|----------|---------|-------|
| `WORKSPACE` | ✓ | (none) | Must be world-traversable; see C.3 |
| `S3_BUCKET` | ✓\* | (none) | Required unless `--build-only` |
| `AWS_REGION` | ✓\* | (none) | Required unless `--build-only` |
| `ISO_URL` | | OL10 default | OL version auto-detected from this URL |

\* Required only when AWS-import phases will run.

### Optional / auto-derived keys

| Key | Auto-default |
|-----|--------------|
| `DISTR` | `ol${OL_MAJOR_VERSION}-slim` |
| `CLOUD` | `aws` |
| `AMI_NAME` | `OracleLinux-${MAJOR}-U${UPDATE}-x86_64-$(date +%Y%m%d-%H%M)` |
| `AMI_DESCRIPTION` | `Oracle Linux ${MAJOR} Update ${UPDATE} (x86_64) custom AMI built via oracle-linux-image-tools` |
| `BOOT_MODE_BUILD` | `bios` (Oracle tool restricts AWS to bios) |
| `BOOT_MODE` | `legacy-bios` (must match `BOOT_MODE_BUILD`) |
| `OS_VARIANT` | Auto-detected via `detect_os_variant` |
| `ISO_CHECKSUM` | Auto-resolved via `derive_oracle_checksum_url` |

### Pass-through keys (consumed by `oracle-linux-image-tools`)

These keys are not interpreted by `build-ol-aws-ami.sh` itself; they are
written through to the upstream `env.properties.local` that the
`oracle-linux-image-tools` `bin/build-image.sh` reads. They appear in
the shipped `env.properties.aws-ol{7,8,9,10}` templates with sane defaults
and should usually be left alone.

| Key | Typical value | Purpose |
|-----|--------------|---------|
| `BUILD_NUMBER` | `0` | Suffix in upstream output filenames |
| `SETUP_SWAP` | `No` | Skip swap configuration on cloud VMs |
| `SELINUX` | `enforcing` | SELinux mode of the resulting AMI |
| `ROOT_FS` | `xfs` | Root filesystem of the resulting AMI |
| `DISK_SIZE_GB` | `10` | Root volume size of the AMI |
| `SERIAL_CONSOLE_RUNTIME` | `Yes` | Required for EC2 Serial Console |
| `CLOUD_INIT` | `Yes` | Enable cloud-init in the AMI |
| `CLOUD_USER` | `ec2-user` | AWS-convention first-login user |
| `KERNEL` | `uek` (OL7) / unset (OL8+) | OL7 requires UEK; see C.10 |
| `UEK_RELEASE` | `6` (OL7 only) | UEK major release; only meaningful for OL7 |
| `S3_KEY_PREFIX` | `ol${MAJOR}-ami-import` | Key prefix inside `S3_BUCKET` |
| `VMIMPORT_ROLE_NAME` | `vmimport` | Must match `setup-vmimport-role.sh` |

If `oracle-linux-image-tools` adds, renames, or drops keys upstream,
update the templates and this table in lockstep.

Note on `UEK_RELEASE`: this key is only consumed by the upstream tool
when `KERNEL=uek`. It is meaningful for OL7 (UEK6 is the only viable
release for OL7) and harmless to set (or omit) on OL8/9/10 where the
upstream distr-level default is preferred.

### File naming convention

```
env.properties.aws-ol{N}   where N = 7, 8, 9, or 10
```

Four companion files are committed to the repository, one per major OL
release. Users `cp env.properties.aws-olN env.properties.local` before
editing. `*.local` is git-ignored. The OL7 template is experimental;
see B.3 and C.10 for the patch mechanism that allows it to function.

---

## A.8 Oracle Linux Version Auto-detection

`load_env` calls `parse_ol_version_from_iso` to extract `OL_MAJOR_VERSION`
and `OL_UPDATE_VERSION` from the `ISO_URL`. The regex is:

```bash
OracleLinux-R([0-9]+)-U([0-9]+)
```

This matches Oracle's published ISO naming convention for OL7 through OL10
(OL7's `Server-` infix is naturally accommodated because the regex is
prefix-anchored and not full-match). Detected values propagate to:

- `DISTR` (e.g. `ol10-slim`, `ol7-slim`)
- `AMI_NAME` default
- `AMI_DESCRIPTION` default
- AMI tag `OS=OracleLinux${MAJOR}U${UPDATE}`
- `detect_os_variant` priority list
- The OL7-specific warning banner emitted by `load_env`
- The OL7 patch trigger in `phase3_clone_repository`

If the regex fails (custom ISO URL, mirror site, etc.), the user MUST set
`OL_MAJOR_VERSION` and `OL_UPDATE_VERSION` explicitly in their env file.

### `detect_os_variant` priority list

Generated dynamically from `OL_MAJOR_VERSION` / `OL_UPDATE_VERSION`:

1. `oraclelinux${MAJOR}.${UPDATE}` (exact)
2. `oraclelinux${MAJOR}.${UPDATE-1}`, …, `oraclelinux${MAJOR}.0`
3. `oraclelinux${MAJOR}-unknown`, `oraclelinux${MAJOR}`
4. `rhel${MAJOR}.${UPDATE}`, …, `rhel${MAJOR}.0`, `rhel${MAJOR}-unknown`, `rhel${MAJOR}` (binary-compatible)
5. `centos-stream${MAJOR}`, `centos-stream-${MAJOR}` (plus `centos7.0`, `centos7` when `MAJOR == 7`)
6. `oraclelinux${MAJOR-1}.10`, …, `oraclelinux${MAJOR-1}.0`, `oraclelinux${MAJOR-1}` (gracefully degrade — applies only when `MAJOR > 8`)
7. `linux2024`, `linux2023`, `linux2022`, `linux2020`, `linux2018`, `linux2016`, `linux2014` (generic fallbacks)

First match wins. The script `log_info`s which variant was selected and
classifies it (Native / Compatible / Older / Generic) to set operator
expectations. For OL7 the most realistic match on RHEL-family build hosts
is `rhel7.9` (or `centos7` on older osinfo-db packages).

---

## A.9 Error & Diagnostic Conventions

### Three-tier output

1. **Fatal**: `die "message"` → `log_error` + `exit 1`. Used for any
   condition that prevents pipeline progress.
2. **Degraded**: `log_warn "message"` → continues execution. Used when
   a fallback is being applied (e.g. `rhel10.1` selected because no
   `oraclelinux10` entry exists in osinfo-db).
3. **Informational**: `log_info "message"` → routine progress.

### Required actionable error format

When `die`'ing on a recoverable misconfiguration, the message MUST include:

1. **What** went wrong (one sentence).
2. **Why** it matters (one sentence; cause if non-obvious).
3. **How** to fix (one or more concrete commands or env keys).

Example (good):

```
[ERROR] BOOT_MODE_BUILD='uefi' is not supported for CLOUD=aws.
[ERROR]   oracle-linux-image-tools only accepts BOOT_MODE=bios for AWS targets.
[ERROR]   Set BOOT_MODE_BUILD="bios" in env.properties.local (or remove the line
[ERROR]   to use the default).
```

Example (bad):

```
[ERROR] Invalid BOOT_MODE_BUILD
```

### Diagnostic categories

| Category | Phase typically affected | Recovery hint |
|----------|--------------------------|---------------|
| KVM/virt unsupported | 0 | Switch instance type or enable nested-virt |
| Missing command | 0/1 | Run `--skip-prereq=0` (default) |
| qemu permission | 2/5 | Auto-handled; manual fallback to `/var/tmp` |
| ISO checksum 404 | 4 | Manual `ISO_CHECKSUM` override |
| OS_VARIANT undetected | 4 | Update osinfo-db or set `OS_VARIANT` |
| BOOT_MODE mismatch | 4/8 | Reset to defaults |
| `virt-sparsify` permission | 5 | `LIBGUESTFS_BACKEND=direct` (auto-set) |
| `import-snapshot` quota | 7 | Wait or request quota increase |

---

## A.10 Bilingual Documentation

### File set

| English | Japanese | Content |
|---------|----------|---------|
| `README.md` | `README.ja.md` | End-user documentation |
| `SPEC.md` | `SPEC.ja.md` | Developer specification (this document) |

### Synchronization rule

Whenever the English version is updated, the Japanese version must be
updated in the same commit (or in an immediate follow-up commit
referencing the English commit hash). Maintain parity of:

- Section structure (same H2 / H3 headings)
- Tables (same columns)
- Code blocks (same content; Japanese files may use bilingual comments)
- Examples (same commands; localize the prose around them)

### Style for Japanese files

- Technical terms in English are preserved in their English form (do not
  translate "phase", "qemu user", "libvirt", "WORKSPACE", "BOOT_MODE",
  "osinfo-db", "VMDK", etc.).
- Punctuation: 「、」 「。」「・」 (full-width); not "," "."
- Brackets: 「」 for emphasized terms, ` `` ` for code spans.

### Mandatory header and footer sections

Each README must include:

1. Top-of-file banner: language switcher, repository link, AI-content warning.
2. Bottom-of-file "Provenance and License" section: AI tool, generation
   date, AS-IS disclaimer, issue tracker link.

Each SPEC must include:

1. Top-of-file purpose block referencing the "single most important rule".
2. Cross-link to the other-language SPEC file.

---

## A.11 Development Workflow

### Iteration cycle

```
1. Reproduce the issue against a real AWS build, or write a unit test
   for the relevant function (parse_ol_version_from_iso, detect_os_variant)
2. Modify code in build-ol-aws-ami.sh
3. bash -n build-ol-aws-ami.sh                  ← syntax gate: must pass
4. shellcheck --severity=warning ...            ← lint gate: must have 0 warnings
5. Re-run the affected phase against AWS        ← functional gate
6. Update README (en + ja) and SPEC (en + ja) if behavior or contract changed
7. Commit
```

### Revision discipline

Unlike (\*2)'s `r47`-style numbering, this script does not embed a
revision number in the source. Instead, the commit hash in the
`ai-generated-artifacts` repository is the canonical revision identifier.

Bump the AI-generation date stamp in the script header on any commit that
changes:

- Phase semantics (any of the 9 phases)
- Output format (log markers, banner layout)
- Parameter set (added / removed / renamed switches)

Cosmetic-only changes (typo fixes in messages, README rewording) do not
require a header date bump.

### Reuse before invention

Before writing any new helper function:

1. Search the existing script for an equivalent
   (`grep -n '^[a-z_]*()' build-ol-aws-ami.sh`).
2. If found, extend the existing one rather than adding a parallel helper.
3. If genuinely new, place it near related helpers (output / detection /
   AWS) rather than at the bottom of the file.

---

# Part B — Script-specific Specifications

## B.1 `build-ol-aws-ami.sh`

### Identification

- Header banner contains the eight-section box (Purpose, Prerequisites,
  Usage examples, Pipeline phases, Options, Known limitations,
  AI generation info).
- The `usage()` helper extracts the header banner via `sed` and prints it
  on `--help`. The terminator pattern is `^#==============`.

### Inputs

| Input | Source |
|-------|--------|
| Build configuration | `--env <file>` argument |
| ISO download | `ISO_URL` in env file |
| ISO checksum | Auto-resolved from `linux.oracle.com/security/gpg/checksum/` |
| Build tool source | `git clone https://github.com/oracle/oracle-linux.git --depth 1` |
| AWS credentials | Standard `aws-cli` resolution chain |

### Outputs

| Output | Location |
|--------|----------|
| VMDK | `${WORKSPACE}/OL${MAJOR}U${UPDATE}_x86_64-aws-b0/*.vmdk` |
| S3 object | `s3://${S3_BUCKET}/${S3_KEY}` (S3_KEY = `ol-ami-import/<timestamp>-<basename>`) |
| EBS snapshot | `${SNAPSHOT_ID}` in `${AWS_REGION}` |
| AMI | `${AMI_ID}` registered in `${AWS_REGION}` |

### Phase quirks (this script specifically)

- **Phase 0** has 3-case EC2 self-diagnosis (`guide_ec2_kvm_issue`):
  - Case A: family supports nested-virt but not enabled
  - Case B: family does not support nested-virt
  - Case C: bare-metal instance, kvm module not loaded
- **Phase 2** ACL walk must terminate at `/`, not at `${HOME}`; otherwise
  builds under `/root` fail because `/root` has no `o+x`.
- **Phase 4** generates `env.properties.local` for the upstream tool by
  string interpolation, not by `envsubst`. Optional values use the
  `${KEY:+KEY=${KEY}}` form to emit-or-omit cleanly.
- **Phase 5** explicitly exports `LIBGUESTFS_BACKEND=direct` before
  invoking `bin/build-image.sh`. See C.6.
- **Phase 7** polling loop has a 90-minute hard timeout (90 iterations
  of 60s) and treats describe-import-snapshot-tasks API failures as
  transient (retry, don't abort).
- **Phase 8** conditionally adds `--tpm-support v2.0` only when
  `BOOT_MODE` is `uefi` or `uefi-preferred`. NitroTPM with `legacy-bios`
  AMIs is invalid.

### Known constraints

See Part C for the historical context behind each.

- x86_64 only; aarch64 AMI builds are not implementable today (`oracle-linux-image-tools` AWS target is x86_64-only).
- AWS `BOOT_MODE=bios` is the only working combination; `legacy-bios`
  AMIs cannot use NitroTPM or UEFI Secure Boot, but boot fine on all
  Nitro instance types.
- `import-snapshot` is rate-limited per AWS account (default 5 concurrent).

---

## B.2 `setup-vmimport-role.sh`

### Identification

A small (one-time) helper that creates the `vmimport` IAM service role
required by AWS VM Import/Export. **It is not part of the 9-phase
pipeline**; users run it once per AWS account before the first build.

### Inputs

```
./setup-vmimport-role.sh <S3_BUCKET> [ROLE_NAME]
```

| Positional | Required | Default |
|------------|----------|---------|
| `S3_BUCKET` | ✓ | (none) |
| `ROLE_NAME` | | `vmimport` |

### Outputs

- IAM role created with the standard `vmimport` trust policy.
- Inline IAM policy `vmimport-${S3_BUCKET}` attached, scoped to the
  given bucket.

### Idempotency

The script `die`s if a role with the same name already exists, rather
than silently overwriting. Operators wanting to scope the role to a
different bucket should use a custom `ROLE_NAME` or manually edit the
attached policy.

### Known constraints

- The trust policy uses the literal SID `vmimport` and assumes the
  service principal `vmie.amazonaws.com` is present in the partition.
  This works for commercial AWS regions; GovCloud and China users will
  need to edit the trust policy.

---

## B.3 `env.properties.aws-ol{7,8,9,10}`

### Identification

Four companion templates, one per major Oracle Linux release supported.
They are committed in this directory and should be copied to
`env.properties.local` before editing.

The OL7 template is experimental — see C.10 for the rationale behind the
runtime patch that makes it work against the upstream AWS cloud target.

### Per-template differences

| Key | OL10 template | OL9 template | OL8 template | OL7 template |
|-----|--------------|--------------|--------------|--------------|
| `WORKSPACE` | `/tmp/ol10-build-ws` | `/tmp/ol9-build-ws` | `/tmp/ol8-build-ws` | `/tmp/ol7-build-ws` |
| `DISTR` | `ol10-slim` | `ol9-slim` | `ol8-slim` | `ol7-slim` |
| `ISO_URL` | OL10 U1 | OL9 U7 | OL8 U10 | OL7 U9 (with `Server-` infix) |
| `# OS_VARIANT` example | `rhel10.1` | `rhel9.7` | `rhel8.10` | `rhel7.9` |
| `# AMI_NAME` example | `OracleLinux-10-U1-...` | `OracleLinux-9-U7-...` | `OracleLinux-8-U10-...` | `OracleLinux-7-U9-...` |
| `KERNEL` | unset (use distr default) | unset | unset | `uek` (required — see C.10) |
| `UEK_RELEASE` | unset | unset | unset | `6` (the only viable UEK for OL7) |
| Top-of-file warning banner | none | none | none | EOL / patch / production-prohibited notice |

### Maintenance rule

When a new Oracle Linux update release ships (e.g. OL10 U2):

1. Update the OL10 template's `ISO_URL` to the new release.
2. Update the example values in `# OS_VARIANT` and `# AMI_NAME` comments.
3. No script changes required — `parse_ol_version_from_iso` and
   `detect_os_variant` adapt automatically.

When a new Oracle Linux major release ships (e.g. OL11):

1. Add `env.properties.aws-ol11` (copy from OL10 and replace 10→11).
2. Add corresponding row to README and SPEC tables.
3. No script changes required, assuming Oracle keeps the
   `OracleLinux-R{N}-U{M}` ISO naming convention.

When the upstream rewrites the OL7 cloud=aws check:

1. Re-evaluate the `sed` pattern in `phase3_clone_repository`. The current
   pattern is anchored on the exact string `AWS images builder only supports OL8 and above`.
2. If the upstream removes the OL7 block entirely, the `grep -Fq` guard
   makes the patch a no-op and a `log_warn` notifies the operator. No
   action is forced.
3. If the upstream replaces the check with something semantically
   different (e.g. allowlist-style validation), the OL7 patch may need
   to be redesigned — update the section here and the comments in
   `phase3_clone_repository` together.

---

# Part C — Known Pitfalls & Lessons Learned

These are documented so that future revisions do not regress on
already-fixed issues.

## C.1 `parse_args` final `&& die` leaking exit 1

**Symptom**: The script silently exited with code 1 immediately after
`parse_args` returned, with no log line indicating why.

**Root cause**: The final statement of `parse_args` was
`[[ ! -f "${ENV_FILE}" ]] && die "..."`. When the file existed,
`[[ ]]` returned 1 (false), and `die` was correctly skipped — but the
entire `&&` expression's exit code (1) became the function's return
value. Combined with `set -e` in the caller, this aborted the script.

**Fix**: Append an explicit `return 0` to `parse_args`. The defensive
coding rule in A.5 #3 was added in response to this incident.

## C.2 Oracle moved ISO checksums to a new URL

**Symptom**: `curl ${ISO_URL}.sha256sum` returned HTTP 404 for OL10.

**Root cause**: Starting with OL9, Oracle publishes checksum files at
`https://linux.oracle.com/security/gpg/checksum/OracleLinux-R{N}-U{M}-Server-{arch}.checksum`
(GPG-signed, multi-file format) rather than per-ISO `.sha256sum` files.

**Fix**: `derive_oracle_checksum_url` builds a fallback chain (user-supplied → legacy
`.sha256sum` → modern Oracle URL). The extracted hash is `grep`'d by ISO
filename and validated against a 64-char hex regex.

## C.3 qemu user (uid 107) cannot traverse `/root`

**Symptom**: Phase 5 (`virt-install`) failed with
`Cannot access storage file '...' (as uid:107, gid:107): Permission denied`
when `WORKSPACE` was placed under `/root`.

**Root cause**: libvirt in system mode (`qemu:///system`) launches qemu
as a non-root user (`qemu` on RHEL, `libvirt-qemu` on Debian). `/root` is
typically mode 0700, blocking traversal.

**Fix**: Phase 2 was added to walk the parent directory chain of
`WORKSPACE` up to `/`, applying `setfacl -m u:qemu:x` where the qemu user
cannot already traverse. ACL extension package (`acl`) added to Phase 1.

Additionally, the default `WORKSPACE` was moved to `/tmp/ol{N}-build-ws`,
which is world-traversable (mode 1777) and avoids the issue entirely on
fresh hosts.

## C.4 Oracle's `build-image.sh` restricts AWS to `BOOT_MODE=bios`

**Symptom**: Phase 5 aborted with
`AWS images only supports bios BOOT_MODE`.

**Root cause**: Oracle's upstream `cloud/aws/image-scripts.sh` enforces
`BOOT_MODE=bios` (case-sensitive) for AWS targets. The script's earlier
default of `hybrid` was rejected.

**Fix**: Defaults are now `BOOT_MODE_BUILD=bios` and `BOOT_MODE=legacy-bios`.
`load_env` validates the AWS combination and fails early with an
actionable message if a user sets `uefi` or `hybrid`.

Consequence: NitroTPM and UEFI Secure Boot cannot be enabled on the
resulting AMIs. The AMIs still boot on every Nitro instance type.

## C.5 osinfo-db on RHEL 10 has no `oraclelinux10` entries

**Symptom**: Phase 5 aborted with
`can't determine OS_VARIANT; you must define it in your environment file`
when running on a RHEL 10 build host.

**Root cause**: Red Hat's osinfo-db package does not ship Oracle Linux
entries. The `osinfo-query` lookup for `oraclelinux10*` returned empty.

**Fix**: `detect_os_variant` was made dynamic, generating a candidate
list from `OL_MAJOR_VERSION` and falling back to RHEL of the same major
(binary-compatible), then to CentOS Stream, then to generic
`linuxYYYY`. On RHEL 10 hosts, this selects `rhel10.1` — an excellent
stand-in.

The classification message distinguishes "Native" (oraclelinux{N}),
"Compatible" (rhel{N} / centos-stream{N}), "Older" (oraclelinux{N-1}),
and "Generic" so operators can interpret the choice.

## C.6 `virt-sparsify` fails with mkdtemp(3) 0700 permission

**Symptom**: At the end of Phase 5 (after the OS install and
`virt-customize` succeeded), `virt-sparsify` failed:

```
Cannot access storage file '.../tmp.XXXXX/sparsifyXXX.qcow2'
(as uid:107, gid:107): Permission denied
```

**Root cause**: `virt-sparsify` creates a temporary overlay subdirectory
via `mkdtemp(3)`, which always sets mode 0700. The libvirt qemu user
(uid 107) cannot traverse a 0700 directory it does not own, and POSIX
default ACLs cannot override the umask-derived effective mask for
mkdtemp.

**Fix**: Phase 5 exports `LIBGUESTFS_BACKEND=direct` before invoking
`bin/build-image.sh`. The "direct" backend runs qemu as the calling user
(root), bypassing libvirt entirely. This only affects libguestfs-based
tools (virt-customize, virt-sysprep, virt-sparsify); `virt-install` in
the same phase still goes through libvirt, which is why Phase 2's ACL
fix is still required.

## C.7 RHEL 10's modular libvirt (`virtqemud`)

**Symptom**: `systemctl enable --now libvirtd` failed on RHEL 10
because the unit does not exist.

**Root cause**: RHEL 9+ / Fedora 35+ / Debian 12+ ship modular libvirt
daemons (`virtqemud`, `virtnetworkd`, `virtstoraged`) instead of the
monolithic `libvirtd`.

**Fix**: Phase 1 now probes both unit names and enables whichever exists.
The check uses `systemctl list-unit-files` rather than blind `enable`
because failure should be a `log_warn`, not a `die` (some hosts may have
the daemon running via a different mechanism).

## C.8 `.metal` instance pattern matched the wrong case branch

**Symptom**: `guide_ec2_kvm_issue` on a `c5n.metal` host emitted the
"family does not support nested virtualization" message (Case B),
which was confusing because the operator was already on a bare-metal
instance.

**Root cause**: `family=$(echo ${instance_type} | sed -E 's/\.[^.]+$//')`
strips the `.metal` suffix before the `case` statement runs, so
`c5n.metal` becomes `c5n`, and the metal-detection pattern (`*.metal`)
never matched.

**Fix**: Test the full `instance_type` against `*.metal` and
`*.metal-*` before reducing to the family. The check ordering is now:

1. If full type matches metal pattern → Case C (kvm module not loaded)
2. Else if family is in the nested-virt-capable list → Case A (enable nested-virt)
3. Else → Case B (switch instance family)

## C.9 Phase polling loop empty-status infinite loop

**Symptom**: Phase 7 could hang indefinitely if
`describe-import-snapshot-tasks` returned an empty `Status` field
(transient AWS API issue).

**Root cause**: The original loop had no handling for empty status,
nor a hard timeout. `case "${status}"` with empty input matched no
branch and looped back to `sleep 60`.

**Fix**: Added explicit empty-string detection (treats as transient,
retries) and a 90-minute hard timeout (90 iterations × 60s). API
failures are caught with `|| true` and retried.

## C.10 Upstream rejects OL7 for the AWS cloud target

**Symptom**: A Phase 5 invocation with `DISTR=ol7-slim` and `CLOUD=aws`
aborts immediately with:

```
ERROR: AWS images builder only supports OL8 and above
```

**Root cause**: `oracle-linux-image-tools/cloud/aws/image-scripts.sh`
defines `cloud::validate()` which contains a hard guard:

```bash
[[ ${ORACLE_RELEASE} -lt 8 ]] && common::error "AWS images builder only supports OL8 and above"
```

This guard was introduced together with the initial AWS support (upstream
CHANGELOG, March 2026) and post-dates the OL7 Premier Support EOL
(2024-12-31). The rejection is a policy decision, not a technical
incompatibility: OL7's UEK6 includes the Amazon ENA driver, `cloud-init`
is available, and `kernel-uek-modules` resolves correctly during
`cloud::install_aws_packages`.

**Fix**: `phase3_clone_repository` detects `OL_MAJOR_VERSION -eq 7`
after the clone and rewrites the offending line in the working-copy
`cloud/aws/image-scripts.sh` to a no-op:

```bash
  : # [ol-aws-ami-builder OL7 PATCH] upstream OL7 block removed (see build-ol-aws-ami.sh phase3)
```

The substitution is performed by `sed -i.ol7-patch.bak …` with `|` as
the delimiter (avoiding the `#` character that is significant in shell
comments). The original line is preserved in
`cloud/aws/image-scripts.sh.ol7-patch.bak`.

**Guard rails**:

1. A `grep -Fq 'AWS images builder only supports OL8 and above'` test runs
   before the substitution. If the line is absent (upstream removed or
   reworded it), the patch is skipped and a `log_warn` informs the
   operator that the build will rely on whatever the new upstream
   validation enforces.
2. A second `grep -Fq '[ol-aws-ami-builder OL7 PATCH]'` test runs after
   the substitution. If the marker is missing, the script `die`s rather
   than letting Phase 5 hit an unclear failure later.
3. The patched line is a literal `:` no-op so bash syntax remains valid
   even if `cloud::validate()` is later refactored to reference the
   surrounding code.

**Caveats deliberately not addressed**:

- The patch only removes the AWS-specific OL7 block. The OL7 distro
  itself still enforces `BOOT_MODE=bios` (`bin/build-image.sh`: `OL7 only supports bios BOOT_MODE`),
  which happens to align with the AWS requirement.
- `KERNEL=rhck` is theoretically reachable on OL7 but
  `cloud::install_aws_packages` requires the `kernel-modules` package
  that OL7's RHCK does not split out. The OL7 env template hardcodes
  `KERNEL=uek` with `UEK_RELEASE=6` to avoid this trap.
- aarch64 is not addressed: the OL7 `distr/` has no `_aarch64` variant,
  and the upstream AWS validator also rejects `*_aarch64`. Both
  blockers remain in place for OL7.

**Future-proofing**: If a future upstream commit moves the OL7 check
elsewhere (e.g. into `bin/build-image.sh` itself), the existing patch
becomes a no-op and a new patch site must be added. The marker
`[ol-aws-ami-builder OL7 PATCH]` in the rewritten line is intentionally
distinctive so that `grep -r` can find all wrapper-applied patches in
the cloned tree.

---

## Appendix: How to add support for a new OL major release

When Oracle ships OL11:

1. **Add the env template**:
   ```bash
   cp env.properties.aws-ol10 env.properties.aws-ol11
   sed -i 's/ol10/ol11/g; s/OL10/OL11/g; s/R10-U1/R11-U1/g; ...' env.properties.aws-ol11
   ```
2. **Update tables in README** (English and Japanese): add row to
   "Repository Layout", "Folder layout", and the env-template comparison.
3. **Update SPEC.md B.3 table** with the new template's column.
4. **Sanity check**:
   ```bash
   bash -n build-ol-aws-ami.sh
   shellcheck --severity=warning build-ol-aws-ami.sh
   ./build-ol-aws-ami.sh --env env.properties.aws-ol11 --build-only
   ```

No script changes should be required, because
`parse_ol_version_from_iso` and `detect_os_variant` adapt automatically
to the new major version.

If Oracle changes the ISO naming convention or moves the checksum URL
again, update Part C with a new entry and add the new pattern to
`parse_ol_version_from_iso` / `derive_oracle_checksum_url` respectively.
