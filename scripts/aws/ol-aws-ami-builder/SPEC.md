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
> Part D, and rewriting them invites regressions.
>
> The repository-wide ⚠️ AI generation policy (see
> [`../../README.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/scripts/README.md))
> still applies; this SPEC supplements it with implementation-level detail
> specific to the Oracle Linux AWS AMI builder.

> **Documentation language policy**: This SPEC is maintained in English only. Japanese readers should refer to the English SPEC together with `README.ja.md` for an orientation. See the repository root `README.md` "Language Policy" section for the repository-wide policy.

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
  - [A.10 Documentation Language Policy](#a10-documentation-language-policy)
  - [A.11 Development Workflow](#a11-development-workflow)
- [Part B — Script-specific Specifications](#part-b--script-specific-specifications)
  - [B.1 build-ol-aws-ami.sh](#b1-build-ol-aws-amish)
  - [B.2 setup-vmimport-role.sh](#b2-setup-vmimport-rolesh)
  - [B.3 env.properties.aws-ol{6,7,8,9,10}](#b3-envpropertiesaws-ol6789-10)
  - [B.4 OL6 runtime synthesis (distr/ol6-slim/ + cloud/aws/ patches)](#b4-ol6-runtime-synthesis-distrol6-slim--cloudaws-patches)
  - [B.5 OL6 Overall Architecture](#b5-ol6-overall-architecture)
- [Part C — Quality Gates & Validation Checklist](#part-c--quality-gates--validation-checklist)
- [Part D — Known Pitfalls & Lessons Learned](#part-d--known-pitfalls--lessons-learned)
- [Appendix: How to add support for a new OL major release](#appendix-how-to-add-support-for-a-new-ol-major-release)

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
- `detect_ec2_environment` / `resolve_aws_region` / `guide_ec2_kvm_issue` (EC2 self-diagnosis and region resolution)
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
env.properties.aws-ol7      Oracle Linux 7  Update 9 template (experimental — see B.3, D.10)
env.properties.aws-ol6      Oracle Linux 6  Update 10 template (experimental — see B.4, B.5, D.11–D.16)
README.md / README.ja.md    end-user documentation (bilingual)
SPEC.md                     this developer specification (English only)
```

### A.1.4 Workspace path convention

`WORKSPACE` defaults to `/tmp/ol{N}-build-ws` (where `{N}` is the OL major
version). The path is chosen specifically because `/tmp` is world-traversable
by FHS convention, which avoids libvirt's qemu user (uid 107) being unable
to reach files placed under `/root` or other restricted parents. See A.7
and D.3 for the full rationale.

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
9. EC2 helpers                        detect_ec2_environment, resolve_aws_region, guide_ec2_kvm_issue
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
| 3 | `phase3_clone_repository` | Build | `git clone --depth 1` of oracle/oracle-linux. **For OL7 only**: rewrites the OL7-blocking line in `cloud/aws/image-scripts.sh` to a no-op (`.ol7-patch.bak` backup left in place). See D.10. |
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
   See D.1 for the historical bug.
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
See D.1 for the real-world incident.

### Caller pattern for libguestfs

Phase 5 sets `LIBGUESTFS_BACKEND=direct` before invoking
`bin/build-image.sh` to bypass libvirt's qemu user permission model. This
is **non-negotiable**; see D.6.

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
| `WORKSPACE` | ✓ | (none) | Must be world-traversable; see D.3 |
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
| `KERNEL` | `uek` (OL7) / unset (OL8+) | OL7 requires UEK; see D.10 |
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
env.properties.aws-ol{N}   where N = 6, 7, 8, 9, or 10
```

Five companion files are committed to the repository, one per major OL
release supported. Users `cp env.properties.aws-olN env.properties.local`
before editing. `*.local` is git-ignored. The OL7 and OL6 templates are
experimental; see B.3 for the per-template details, B.4 for the OL6
runtime-synthesis mechanism, D.10 for the OL7 patch, and D.11–D.16 for
the OL6-specific pitfalls.

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

## A.10 Documentation Language Policy

This project follows the repository-wide documentation language policy
documented in the `ai-generated-artifacts` root [`README.md`](../../../README.md)
"Language Policy" section.

### File set

| File | Languages maintained | Notes |
|------|----------------------|-------|
| `README.md` | English **and** Japanese (`README.ja.md`) | English is the master. `README.ja.md` is its translation, kept in sync. |
| `SPEC.md` (this document) | **English only** | |
| Other repository-policy files (CONTRIBUTING.md, etc.) | **English only** | Maintained at the repository root, not per-project. |

**Policy rationale**: Only `README.md` is duplicated into Japanese because it is the primary entry point for new readers. Specifications are maintained in English only to avoid drift — a problem that LLM-assisted maintenance is especially vulnerable to. Japanese readers should use `README.ja.md` for orientation and then refer to the English source-of-truth documents for technical detail.

### Synchronization rule (README only)

Whenever `README.md` is updated, `README.ja.md` must be updated in the
same commit (or in an immediate follow-up commit referencing the
English commit hash). Maintain parity of:

- Section structure (same H2 / H3 headings)
- Tables (same columns)
- Code blocks (same content; Japanese files may use bilingual comments)
- Examples (same commands; localize the prose around them)

### Style for `README.ja.md`

- Technical terms in English are preserved in their English form (do not
  translate "phase", "qemu user", "libvirt", "WORKSPACE", "BOOT_MODE",
  "osinfo-db", "VMDK", etc.).
- Punctuation: 「、」 「。」「・」 (full-width); not "," "."
- Brackets: 「」 for emphasized terms, ` `` ` for code spans.

### Mandatory header and footer sections

Each README must include:

1. Top-of-file banner: language switcher (`README.md` ↔ `README.ja.md`), repository link, AI-content warning.
2. Bottom-of-file "Provenance and License" section: AI tool, generation
   date, AS-IS disclaimer, issue tracker link.

This SPEC must include:

1. Top-of-file purpose block referencing the "single most important rule".
2. Documentation language policy notice (this section).

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
6. Update README.md + README.ja.md if behavior or contract changed
   (per A.10, only the README is bilingual; SPEC.md is English only).
7. Commit
```

### Revision discipline

This project follows the repository-wide
[Revision History Policy](../../../README.md#revision-history-policy)
documented at the root of `ai-generated-artifacts`.

#### Version identifier

Unlike `Deploy-Drivers-For-WindowsServer`'s `r47`-style numbering, this
script does not embed a revision number in the source. Instead, the
commit hash in the `ai-generated-artifacts` repository is the canonical
revision identifier.

Bump the AI-generation date stamp in the script header on any commit
that changes:

- Phase semantics (any of the 9 phases)
- Output format (log markers, banner layout)
- Parameter set (added / removed / renamed switches)

Cosmetic-only changes (typo fixes in messages, README rewording) do not
require a header date bump.

#### Where revision history lives

Per-version release notes for this script — when this project starts
producing numbered releases — belong **exclusively** in a `CHANGELOG.md`
file alongside `build-ol-aws-ami.sh` in this directory (not yet
created; will be added when the first formal release is cut). Such
release notes do NOT belong in:

- `build-ol-aws-ami.sh` source comments (no inline revision tags, no
  end-of-file `# REVISION HISTORY` block)
- `README.md` (other than a brief pointer to `CHANGELOG.md` when one
  exists)
- This `SPEC.md` (which describes *current* behaviour)

Architectural rationale (root-cause analyses of past pitfalls) belongs
in **Part D — Known Pitfalls** of this SPEC. When a `CHANGELOG.md`
exists, it cross-references back to Part D where applicable.

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
  invoking `bin/build-image.sh`. See D.6.
- **Phase 7** polling loop has a 90-minute hard timeout (90 iterations
  of 60s) and treats describe-import-snapshot-tasks API failures as
  transient (retry, don't abort).
- **Phase 8** conditionally adds `--tpm-support v2.0` only when
  `BOOT_MODE` is `uefi` or `uefi-preferred`. NitroTPM with `legacy-bios`
  AMIs is invalid.

### Known constraints

See Part D for the historical context behind each.

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

## B.3 `env.properties.aws-ol{6,7,8,9,10}`

### Identification

Five companion templates, one per major Oracle Linux release supported.
They are committed in this directory and should be copied to
`env.properties.local` before editing.

The OL7 template is experimental — see D.10 for the rationale behind the
runtime patch that makes it work against the upstream AWS cloud target.

The OL6 template is even more experimental: the upstream does not ship a
`distr/ol6-slim/` directory at all, so the wrapper synthesizes it at
runtime in addition to two runtime `sed` patches. See B.4 and D.11–D.15
for design rationale, and B.5 for the overall OL6 architecture.

### Per-template differences

| Key | OL10 | OL9 | OL8 | OL7 | OL6 |
|-----|------|-----|-----|-----|-----|
| `WORKSPACE` | `/tmp/ol10-build-ws` | `/tmp/ol9-build-ws` | `/tmp/ol8-build-ws` | `/tmp/ol7-build-ws` | `/tmp/ol6-build-ws` |
| `DISTR` | `ol10-slim` | `ol9-slim` | `ol8-slim` | `ol7-slim` | `ol6-slim` (synthesized) |
| `ISO_URL` | OL10 U1 | OL9 U7 | OL8 U10 | OL7 U9 (with `Server-` infix) | OL6 U10 (with `Server-` infix) |
| `# OS_VARIANT` example | `rhel10.1` | `rhel9.7` | `rhel8.10` | `rhel7.9` | `ol6.10` |
| `# AMI_NAME` example | `OracleLinux-10-U1-...` | `OracleLinux-9-U7-...` | `OracleLinux-8-U10-...` | `OracleLinux-7-U9-...` | `OracleLinux-6-U10-...` |
| `KERNEL` | unset (use distr default) | unset | unset | `uek` (required — see D.10) | `uek` (required — see D.12) |
| `UEK_RELEASE` | unset | unset | unset | `6` (the only viable UEK for OL7) | `4` (the only viable UEK for OL6) |
| `ROOT_FS` | unset (xfs default) | unset | unset | `xfs` (only xfs/btrfs/lvm valid in upstream OL7+) | `xfs` (xfs or ext4; /boot kept on ext4 — see B.4 / D.16) |
| `BOOT_MODE_BUILD` | unset | unset | unset | `bios` | `bios` |
| Top-of-file warning banner | none | none | none | EOL / patch / production-prohibited notice | EOL / **2 patches** / runtime-synthesized `distr/` / production-prohibited notice |

### Cross-version uniform fields

The following keys are intentionally identical across all five templates so
that operators can copy any of them to `env.properties.local` and only need
to change the `# AMI_NAME` line and (optionally) `WORKSPACE`:

| Key | Uniform value | Rationale |
|-----|---------------|-----------|
| `S3_BUCKET` | `my-oracle-linux-ami-import-bucket` | One IAM role (`vmimport`) and one S3 bucket cover every version. Per-version isolation comes from `S3_KEY_PREFIX`. See B.3.1 below. |
| `AWS_REGION` | `""` (empty) | Resolved dynamically at runtime via IMDSv2 → IMDSv1 → `ap-northeast-1` fallback. See B.3.2 below and §B.1's `resolve_aws_region()` description. |
| `UPDATE_TO_LATEST` | `"yes"` | Run `dnf/yum update -y` inside the guest after install, addressing kernel and userspace CVEs published after the ISO date. See B.3.3 below. |

### B.3.1 Shared `S3_BUCKET` and the `vmimport` IAM role

Pre-refactor, every env template carried a per-version bucket name
(`my-ol10-ami-import-bucket`, `my-ol9-ami-import-bucket`, …) which forced
operators to either:

- run `setup-vmimport-role.sh` five times (once per bucket), each call
  replacing the previous IAM trust policy; or
- manually edit the `Resource` array in the `vmimport-policy` JSON to
  enumerate all five buckets.

The unified `my-oracle-linux-ami-import-bucket` approach eliminates both
operational burdens. `setup-vmimport-role.sh` is run **once per AWS
account** with that single bucket name, and every `build-ol-aws-ami.sh`
invocation reuses the resulting role policy unchanged. Per-version VMDK
isolation is preserved by `S3_KEY_PREFIX="ol{N}-ami-import"` in each env
template, which causes the staged objects to land under
`s3://my-oracle-linux-ami-import-bucket/ol{N}-ami-import/...`.

The bucket itself is created lazily by `phase6_upload_to_s3` if missing
(public access blocked), so the operator does not need to pre-create it.

### B.3.2 Dynamic `AWS_REGION` resolution

`resolve_aws_region()` (in `build-ol-aws-ami.sh`, called from `load_env`)
implements a 3-step resolution chain:

| Step | Source | Method | Cost |
|------|--------|--------|------|
| 1 | Env file (explicit) | Non-empty `AWS_REGION` value short-circuits the chain. | 0 |
| 2a | IMDSv2 | `curl PUT /latest/api/token` then `GET /latest/meta-data/placement/region` with the token. | ~2 × max-2s |
| 2b | IMDSv1 | `curl GET /latest/meta-data/placement/region` (token-less). Only attempted if step 2a returns no token. | ~1 × max-2s |
| 3 | Fallback constant | `AWS_REGION="ap-northeast-1"` | 0 |

The function sets `AWS_REGION_SOURCE` to `env` / `imdsv2` / `imdsv1` /
`fallback` so the choice is visible in the load-env banner:

```
[INFO] AWS_REGION         = us-east-1 (source: imdsv2)
```

**Why both v2 and v1?** AWS recommends v2 for security (token mitigates
SSRF), but EC2 instances launched before mid-2024 may still have
`HttpTokens=optional` (where v1 also works). On instances with
`HttpTokens=disabled` (a rare but valid configuration), the PUT call
fails and v1 succeeds. On instances with `HttpTokens=required` (the
modern hardened default), v1 returns 401 and the wrapper falls through
to the fallback constant. The 2-second `--max-time` cap on every curl
call keeps the latency budget under ~4 seconds even when both IMDS calls
fail (i.e., on on-premises hosts where there is no metadata service at
all).

**Why `ap-northeast-1` as the fallback?** It matches the historical
default in the per-version templates pre-refactor, and matches the
build-host region used during the wrapper's own end-to-end verification.
Operators in other regions should set `AWS_REGION` explicitly in
`env.properties.local`.

### B.3.3 `UPDATE_TO_LATEST` wrapper-level passthrough

The upstream `distr/ol{N}-slim/env.properties` files all default
`UPDATE_TO_LATEST="yes"`, which means `dnf update -y` (OL8/9/10) or
`yum update -y` (OL6/7) runs during `distr::configure` regardless of
whether the wrapper specifies anything. Pre-refactor, the wrapper relied
on this implicit default and emitted no log line about it; operators had
no way to tell from the wrapper-level env file whether the update would
happen.

Post-refactor:

1. Every wrapper-level env template declares `UPDATE_TO_LATEST="yes"`
   explicitly, with a comment block summarizing the three accepted
   values (`yes` / `security` / `no`).
2. `phase4_prepare_env_properties` emits a `${UPDATE_TO_LATEST:+...}`
   line into the generated `env.properties.local`, so when the operator
   sets the value to something other than `yes` (e.g. `no` for byte-for-
   byte reproducibility builds) the override actually reaches the
   upstream layer instead of being silently dropped.
3. The OL6 runtime-generated `distr/ol6-slim/env.properties` template
   (emitted from a heredoc in `phase3_clone_repository`) carries the
   same `UPDATE_TO_LATEST="yes"` default, and its synthesized
   `distr::common_cfg` honours the wrapper-supplied value through the
   same env-layer override mechanism.

This change is documentation-and-logging-focused; the runtime behaviour
of an unchanged env file is identical to pre-refactor (the implicit
upstream default of `yes` produces the same `dnf update -y` execution).

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

## B.4 OL6 runtime synthesis (`distr/ol6-slim/` + `cloud/aws/` patches)

### Identification

OL6 is supported through a different mechanism than OL7. Where OL7
requires one runtime `sed` patch against an otherwise-complete
distribution, OL6 requires **two** runtime `sed` patches **plus** the
runtime synthesis of an entire `distr/ol6-slim/` directory that does not
exist upstream. All four artifacts live inside `phase3_clone_repository`
in `build-ol-aws-ami.sh` and are gated behind `OL_MAJOR_VERSION == 6`
(except for patch #1, which is shared with OL7 via `-le 7`).

### Wrapper-patch marker convention

All wrapper-applied modifications to the upstream working copy must be
discoverable by `grep -r '\[ol-aws-ami-builder' "${WORK_REPO_DIR}"`. The
canonical marker format is:

```
[ol-aws-ami-builder OL{N} PATCH {short-tag}]
```

where `{N}` is the OL major version (6, 7, ...) and `{short-tag}` is a
descriptive identifier (omitted when only one patch exists per OL major).
Current markers:

| Marker | File patched | Purpose |
|--------|--------------|---------|
| `[ol-aws-ami-builder OL6 PATCH]` | `cloud/aws/image-scripts.sh` | Remove OL8+ guard (OL6 mode) |
| `[ol-aws-ami-builder OL7 PATCH]` | `cloud/aws/image-scripts.sh` | Remove OL8+ guard (OL7 mode) |
| `[ol-aws-ami-builder OL6 PATCH kernel-uek-modules]` | `cloud/aws/provision.sh` | Skip `kernel-uek-modules` install on OL6 |

Each patch leaves a `.bak` backup file next to the modified one and
includes a `grep -Fq` idempotency guard so re-runs against an existing
clone do not double-apply.

### `sed` invocation conventions

1. **Delimiter**: prefer `|` (pipe) over `/` to avoid clashing with shell
   path separators or comment `#` characters in the replacement text.
2. **Anchor**: use a literal-string anchor that uniquely identifies the
   line (`AWS images builder only supports OL8 and above` for patch #1,
   `yum install -y "${YUM_VERBOSE}" kernel-uek-modules` for patch #2).
3. **Idempotency**: precede the substitution with
   `grep -Fq '[ol-aws-ami-builder OL{N} PATCH ...]'`; skip with an info
   log when already applied.
4. **Verification**: follow the substitution with a second `grep -Fq`
   on the marker. `die` if missing (rather than letting Phase 5 fail
   with an obscure error later).
5. **Capture-group preservation for indentation**: when the upstream
   line is whitespace-prefixed (e.g. `    yum install ...`), use
   `\(\s*\)` and reference `\1` so the patched output retains the
   original indentation.
6. **GNU sed extensions are permitted**: the wrapper expects to run on
   builder hosts with GNU sed (Amazon Linux 2/2023, Oracle Linux 8/9/10,
   RHEL 9/10), so `\n` in the replacement is fine. BSD/macOS sed is not
   supported.

### `distr/ol6-slim/` runtime generation

The four files are written by a sequence of `cat > {path} <<'EOF_OL6_*'`
heredoc blocks. The single-quoted delimiter is mandatory:

```bash
cat > "${ol6_slim_dir}/provision.sh" <<'EOF_OL6_PROV'
...
EOF_OL6_PROV
```

Single-quoting prevents `${VARIABLE}` expansion **at wrapper time**, so
references like `${YUM_VERBOSE}`, `${ROOT_FS,,}`, and `${KERNEL^^}` are
preserved literally and expand later at `oracle-linux-image-tools`
runtime (which is the intent).

For embedded inner heredocs (e.g. `cat > /etc/dracut.conf.d/...
<<EOF`), the wrapper uses **plain `<<EOF` without leading whitespace**
rather than the tab-stripped `<<-EOF` form. This avoids any dependency
on tab-vs-space handling in editors or tooling that might process the
wrapper later.

### Synchronization with `distr/ol7-slim/`

If `distr/ol7-slim/` upstream changes structurally (function signatures
in `image-scripts.sh`, kickstart section ordering, provision phase
contracts), the OL6 heredoc templates must be reviewed and updated to
match. The wrapper does NOT attempt to inherit anything from
`distr/ol7-slim/` at runtime — the OL6 templates are completely
self-contained for traceability.

### Maintenance rule (OL6)

When `oracle-linux-image-tools` is refactored:

1. If `cloud::validate()` in `cloud/aws/image-scripts.sh` no longer
   contains the OL8+ guard, patch #1 silently no-ops (the `grep -Fq`
   guard reports a `log_warn`); no action forced unless the build
   subsequently fails.
2. If the `kernel-uek-modules` install line in
   `cloud/aws/provision.sh` is removed or renamed, patch #2 silently
   no-ops; OL6 is then expected to still work because the absent
   package would no longer be installed.
3. If `distr/ol7-slim/` structure changes (function signatures, common
   helper names like `common::distr_cleanup`, `common::latest_kernel`,
   etc.), the OL6 heredoc templates in `phase3_clone_repository` must
   be updated by hand. This is the highest-risk surface for upstream
   drift.

---

## B.5 OL6 Overall Architecture

### B.5.1 Why OL6 needs a different architecture than OL7

OL7 support in this wrapper is achieved by **modifying** the upstream's
existing OL7 distribution (`distr/ol7-slim/` is complete) — a single
`sed` patch removes the AWS-specific guard, and the rest of the
upstream pipeline runs untouched.

OL6 support requires **synthesizing** what upstream omits. There is no
`distr/ol6-slim/` at all, and `cloud/aws/provision.sh` contains a line
that fails outright on OL6 because of an OL6-specific package layout.
Three runtime modifications are therefore needed:

| # | Type | Target | Purpose |
|---|------|--------|---------|
| 1 | `sed` patch | `cloud/aws/image-scripts.sh` | Remove OL8+ guard (shared with OL7) |
| 2 | `sed` patch | `cloud/aws/provision.sh` | Skip `kernel-uek-modules` install on OL6 (D.11) |
| 3 | Directory synthesis | `distr/ol6-slim/` (4 files) | Provide kickstart + image-scripts + provision logic |

All three live inside `phase3_clone_repository` so they are
re-established on every clone. The wrapper itself contains the
authoritative templates for the four `distr/ol6-slim/` files as quoted
heredocs.

### B.5.2 Phase A + B verification summary

OL6 support was added after a structured two-phase pre-implementation
verification. All checks below were performed against `oracle-linux`
main branch as of 2026-05 and against `osinfo-db-20250606-1.el10` on
RHEL 10.0 with libvirt 11.5.0-2.el10, qemu-kvm 10.0.0-13.el10.

**Phase A — Static checks (9 items, all PASS):**

1. osinfo-db has `ol6.0` ... `ol6.10` (11 entries) and `rhel6.0` ...
   `rhel6.10` (11 entries) — `detect_os_variant()` will resolve to
   either family.
2. Upstream `oracle-linux-image-tools` has `distr/ol7-slim/`,
   `distr/ol8-slim/`, `distr/ol8-aarch64/`, `distr/ol9-slim/`,
   `distr/ol9-aarch64/`, `distr/ol10-slim/`, `distr/ol10-aarch64/` —
   but NO `distr/ol6-slim/`. The synthesis approach is required.
3. `bin/build-image.sh` regex for valid `DISTR_NAME` is
   `^OL(6|7|8|9|(10))U` — OL6 is accepted by the upstream entry point.
4. `cloud/aws/image-scripts.sh` line 33 contains the OL8+ guard
   verbatim, identical to the OL7 case. Patch #1 reuses the OL7
   sed pattern.
5. `cloud/aws/provision.sh` contains
   `yum install -y "${YUM_VERBOSE}" kernel-uek-modules` at line 58.
   Patch #2's sed pattern matches.
6. ISO URL
   `https://yum.oracle.com/ISOS/OracleLinux/OL6/u10/x86_64/OracleLinux-R6-U10-Server-x86_64-dvd.iso`
   resolves (HTTP 200, 4,072,669,184 bytes, Last-Modified 2018-06-25).
7. Checksum URL
   `https://linux.oracle.com/security/gpg/checksum/OracleLinux-R6-U10-Server-x86_64.checksum`
   resolves and matches the ISO SHA256
   `625044388ee60a031965a42a32f4c1de0c029268975edcd542fd14160e0dadcb`.
8. OL6 UEKR4 repo (`https://yum.oracle.com/repo/OracleLinux/OL6/UEKR4/x86_64/`)
   responds HTTP 200; `primary.xml.gz` confirms `kernel-uek-4.1.12-*`
   present and `kernel-uek-modules-*` absent.
9. OL6 cloud-init availability:
   `cloud-init-18.4-2.0.9.el6.x86_64` and
   `cloud-utils-growpart-0.27-9.el6.x86_64` confirmed in the
   `ol6_addons` repo.

**Phase B — Dynamic checks (2 items, all PASS):**

1. ISO boot test: `virt-install --name=ol6-boot-test --memory=2048
   --vcpus=2 --disk size=20 --location=${ISO_PATH} --os-variant=ol6.10
   --network=default --graphics=none --console pty,target_type=serial`
   succeeds; isolinux loads; Anaconda 13.21.263 TUI appears at the
   kickstart prompt and accepts text input. Domain was destroyed
   immediately afterwards (no actual install).
2. `osinfo-query os | grep ^ol6` returns 11 rows on the builder; the
   `ol6.10` short-id is selectable by `virt-install --os-variant`.

**Phase C (NOT executed):** kickstart completion, provision.sh on OL6,
cloud-init ec2-user on a Nitro instance, end-to-end AMI launch. These
are reserved for the next iteration when an OL6 build is attempted on
a real builder host.

### B.5.3 Comparison to OL7 support

| Aspect | OL7 | OL6 |
|--------|-----|-----|
| Upstream `distr/` | Present (`ol7-slim`) | **Absent** — synthesized at runtime |
| `sed` patches needed | 1 (`image-scripts.sh` guard) | 2 (`image-scripts.sh` + `provision.sh`) |
| Kernel | UEK6 (4.14) | UEK4 (4.1.12) — only ENA-capable kernel for OL6 |
| Filesystem options | xfs, btrfs | ext4, xfs (no lvm/btrfs at this layer) |
| Init system | systemd | Upstart (`service` / `chkconfig`) |
| Bootloader | GRUB2 | GRUB Legacy |
| Kickstart syntax | Anaconda 19.x (`inst.` prefix) | Anaconda 13.x (no `inst.` prefix) |
| NTP daemon | chronyd | ntpd |
| `linux-firmware` | optional | hard dependency of `kernel-uek` |
| `kernel-uek-modules` package | present (UEK6) | absent (UEK4) |
| AWS VM Import support | EOL (2024-12-31) | EOL (with ELS ended 2024) |
| End-to-end validated | No (patch verified, build not run) | No (Phase A+B done, Phase C not run) |

The asymmetry in the table is the rationale for why OL6 needed its own
overall-architecture section (B.5) and OL7 did not: OL7 is a thin patch
on top of an otherwise-functional upstream pipeline, whereas OL6
essentially rebuilds the OL-specific glue layer from scratch inside the
wrapper.

---

---

# Part C — Quality Gates & Validation Checklist

Before any commit to this directory, all of the following must pass.

### Static checks

- [ ] `bash -n build-ol-aws-ami.sh` → 0 errors (parse-only check)
- [ ] `bash -n setup-vmimport-role.sh` → 0 errors
- [ ] `shellcheck --severity=error build-ol-aws-ami.sh setup-vmimport-role.sh` → clean (warnings audited case-by-case)
- [ ] The script starts with `#!/usr/bin/env bash` followed by the header banner with all five required sections (Purpose / Prerequisites / Usage / Limitations / AI info — see A.2)
- [ ] `set -euo pipefail` appears at the top of every shell script in this directory
- [ ] Every new `${VAR:?...}` / `${VAR:=...}` assignment is paired with a `log_info` line confirming the resolved value (per A.5)

### Functional checks

- [ ] `./build-ol-aws-ami.sh --help` exits 0 and lists every supported switch
- [ ] `./build-ol-aws-ami.sh --env env.properties.aws-ol10 --build-only` (or another supported template) completes through Phase 5 on a properly-prepared builder host, or the reason it cannot be exercised is documented
- [ ] Phase banners `========== Phase N: ...` appear in stdout for every executed phase
- [ ] Phase 0 self-diagnosis (`detect_ec2_environment` / `guide_ec2_kvm_issue`) emits the appropriate Case A/B/C message on a non-KVM host (per B.1)
- [ ] When `ISO_URL` references OL7, the OL7 warning banner appears in `load_env` output
- [ ] When `ISO_URL` references OL6, the OL6 warning banner appears in `load_env` output and the three runtime modifications (Patch #1, Patch #2, synthesized `distr/ol6-slim/`) are applied in Phase 3

### Documentation checks

- [ ] `README.md` mentions every new env-property key, command-line switch, and output artifact
- [ ] `README.ja.md` is line-for-line equivalent in structure (table layout and section order match)
- [ ] `README.md` carries the **Disclaimer** section near the top (per A.10)
- [ ] `README.md` carries the **License** section near the top (per A.10)
- [ ] `README.ja.md` carries equivalent **免責事項** and **ライセンス** sections
- [ ] `SPEC.md` reflects the change in the relevant Part A / Part B section
- [ ] If a new pitfall was discovered during development, it is added as a new `D.NN` entry in Part D
- [ ] A `LICENSE` file exists at the repository root and the script header banner names the AI tool used in the generation (per A.2)

### Cross-template checks

- [ ] All five `env.properties.aws-ol{6,7,8,9,10}` templates share the same key set (no orphan keys; documented optional keys are explicitly absent only when intentional — see B.3)
- [ ] `S3_BUCKET` matches across every template (`my-oracle-linux-ami-import-bucket` — single bucket / single `vmimport` IAM role across all OL versions, per B.3 §3 and §9.4a)
- [ ] `AWS_REGION=""` is consistent across templates (resolution chain documented in A.7 / B.3)
- [ ] `UPDATE_TO_LATEST="yes"` is consistent across templates (CVE-coverage default per B.3)
- [ ] Every template's `ISO_CHECKSUM` value matches `https://linux.oracle.com/security/gpg/checksum/` for the corresponding ISO

---

# Part D — Known Pitfalls & Lessons Learned

These are documented so that future revisions do not regress on
already-fixed issues.

## D.1 `parse_args` final `&& die` leaking exit 1

**Symptom**: The script silently exited with code 1 immediately after
`parse_args` returned, with no log line indicating why.

**Root cause**: The final statement of `parse_args` was
`[[ ! -f "${ENV_FILE}" ]] && die "..."`. When the file existed,
`[[ ]]` returned 1 (false), and `die` was correctly skipped — but the
entire `&&` expression's exit code (1) became the function's return
value. Combined with `set -e` in the caller, this aborted the script.

**Fix**: Append an explicit `return 0` to `parse_args`. The defensive
coding rule in A.5 #3 was added in response to this incident.

## D.2 Oracle moved ISO checksums to a new URL

**Symptom**: `curl ${ISO_URL}.sha256sum` returned HTTP 404 for OL10.

**Root cause**: Starting with OL9, Oracle publishes checksum files at
`https://linux.oracle.com/security/gpg/checksum/OracleLinux-R{N}-U{M}-Server-{arch}.checksum`
(GPG-signed, multi-file format) rather than per-ISO `.sha256sum` files.

**Fix**: `derive_oracle_checksum_url` builds a fallback chain (user-supplied → legacy
`.sha256sum` → modern Oracle URL). The extracted hash is `grep`'d by ISO
filename and validated against a 64-char hex regex.

## D.3 qemu user (uid 107) cannot traverse `/root`

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

## D.4 Oracle's `build-image.sh` restricts AWS to `BOOT_MODE=bios`

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

## D.5 osinfo-db on RHEL 10 has no `oraclelinux10` entries

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

## D.6 `virt-sparsify` fails with mkdtemp(3) 0700 permission

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

## D.7 RHEL 10's modular libvirt (`virtqemud`)

**Symptom**: `systemctl enable --now libvirtd` failed on RHEL 10
because the unit does not exist.

**Root cause**: RHEL 9+ / Fedora 35+ / Debian 12+ ship modular libvirt
daemons (`virtqemud`, `virtnetworkd`, `virtstoraged`) instead of the
monolithic `libvirtd`.

**Fix**: Phase 1 now probes both unit names and enables whichever exists.
The check uses `systemctl list-unit-files` rather than blind `enable`
because failure should be a `log_warn`, not a `die` (some hosts may have
the daemon running via a different mechanism).

## D.8 `.metal` instance pattern matched the wrong case branch

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

## D.9 Phase polling loop empty-status infinite loop

**Symptom**: Phase 7 could hang indefinitely if
`describe-import-snapshot-tasks` returned an empty `Status` field
(transient AWS API issue).

**Root cause**: The original loop had no handling for empty status,
nor a hard timeout. `case "${status}"` with empty input matched no
branch and looped back to `sleep 60`.

**Fix**: Added explicit empty-string detection (treats as transient,
retries) and a 90-minute hard timeout (90 iterations × 60s). API
failures are caught with `|| true` and retried.

## D.10 Upstream rejects OL7 for the AWS cloud target

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

## D.11 OL6/UEKR4 has no `kernel-uek-modules` package

**Symptom**: When the upstream `cloud/aws/provision.sh`'s
`cloud::install_aws_packages()` is executed on OL6, the line
`yum install -y "${YUM_VERBOSE}" kernel-uek-modules` fails with
`No package kernel-uek-modules available`.

**Root cause**: The `kernel-uek-modules` package is a *split-out modules
package* introduced in OL7 / UEK6 to keep the main `kernel-uek` RPM
smaller. On OL6's UEKR4 (`4.1.12-124.x`), no such split exists — all
driver `.ko` files (including `ena.ko`, `nvme.ko`, `nvme-core.ko`,
`virtio*.ko`, `xen-*.ko`, `hv_*.ko`) are bundled directly inside the
`kernel-uek` RPM itself. Verified against
`https://yum.oracle.com/repo/OracleLinux/OL6/UEKR4/x86_64/repodata/primary.xml.gz`:
no `kernel-uek-modules-*` entries exist.

**Fix**: `phase3_clone_repository` applies a second runtime patch on top
of the OL7-shared `image-scripts.sh` patch, rewriting the offending line
to be conditional on `ORACLE_RELEASE >= 7`:

```bash
# [ol-aws-ami-builder OL6 PATCH kernel-uek-modules] OL6/UEKR4 has no separate kernel-uek-modules package (modules bundled in kernel-uek)
[[ "${ORACLE_RELEASE}" -ge 7 ]] && yum install -y "${YUM_VERBOSE}" kernel-uek-modules
```

The `&&` short-circuit makes the line a no-op on OL6 while preserving
the original semantics for OL7+.

**Guard rails**:

1. A `grep -Fq '[ol-aws-ami-builder OL6 PATCH kernel-uek-modules]'`
   precedes the substitution for idempotency.
2. A `grep -Fq 'yum install -y "${YUM_VERBOSE}" kernel-uek-modules'`
   verifies the original line is still present (if upstream removes it,
   the patch is skipped with a `log_warn`).
3. Post-substitution, the marker grep `die`s the script if the patch
   silently failed to apply.

**Verification**: ENA / NVMe driver availability on the produced AMI is
confirmed by `lsmod | grep -E '^(ena|nvme)'` after first boot, plus
`modinfo ena nvme nvme_core` to inspect the kernel module metadata. This
check is in Phase C-4 of the verification plan (not yet executed by the
author).

---

## D.12 OL6 + UEK4 is the only viable combination for AWS Nitro

**Symptom**: Building an OL6 AMI with `KERNEL=uek` and `UEK_RELEASE=2`
or `UEK_RELEASE=3` produces an AMI that fails to boot on Nitro
instances with `kernel panic: no driver for 0000:00:05.0` (the ENA
device).

**Root cause**: The Amazon ENA driver was added to UEK starting with
UEK4 (4.1.12-124.x for OL6, 4.14.35-1818.x for OL7). UEK2 (2.6.39) and
UEK3 (3.8.13) predate AWS Nitro entirely. RHCK on OL6 (2.6.32-754.x)
also lacks the ENA driver — Red Hat backported ENA only as far as
RHEL 7.4. UEK5 (4.14) and later are not built for OL6.

**Fix**: The OL6 env template hard-codes `KERNEL=uek` and
`UEK_RELEASE=4`. The synthesized `distr/ol6-slim/image-scripts.sh`'s
`distr::validate()` enforces `UEK_RELEASE=4` explicitly:

```bash
[[ "${UEK_RELEASE}" =~ ^4$ ]] || common::error "UEK_RELEASE must be 4 (OL6 + AWS Nitro requires UEK4; UEK2/3 lack ENA, UEK5+ not available)"
```

This is more restrictive than OL7's `^(6)$` pattern but follows the
same template.

**Caveat**: If Oracle ever publishes a new UEK release backported to
OL6 (extremely unlikely — UEK is tightly coupled to glibc and
toolchain versions), this validator would need to be relaxed.

---

## D.13 OL6 `kernel-uek` has a hard install dependency on `linux-firmware`

**Symptom**: Setting `LINUX_FIRMWARE="No"` in the env file successfully
removes `linux-firmware` during provisioning, but a later
`yum install kernel-uek` (or any kernel update) re-installs it.

**Root cause**: The OL6 `kernel-uek` RPM declares
`Requires: linux-firmware`. On OL7+, this requirement was relaxed to
`Recommends:` (or removed entirely as the firmware was vendored into
the kernel package). The OL6 dependency is a hard one, so `yum` will
always pull `linux-firmware` back in to satisfy it.

**Fix**: None — this is documented as a known limitation. The OL6 env
template's `LINUX_FIRMWARE` comment notes the stickiness. The
synthesized `distr/ol6-slim/provision.sh` still honors
`LINUX_FIRMWARE="No"` by issuing `yum remove -y linux-firmware`, but
the user is informed via the comment that any subsequent kernel
operation will undo it.

**Future-proofing**: If shrinking the AMI to omit firmware is critical,
the recommended approach is to use `rpm -e --nodeps linux-firmware`
after all `kernel-uek` operations complete (e.g. very late in the
provisioning), and to avoid running `yum update` post-image-build.
This is out of scope for the current wrapper.

---

## D.14 OL6 ISO's `.treeinfo` does not declare `images/boot.iso`

**Symptom**: `virt-install --location ${ISO}` against the OL6 U10 ISO
on libvirt 11.5 / qemu 10.0 succeeds (TUI text installer appears), but
older `virt-install` versions (libvirt ≤ 8.x) abort with
`Error: cannot find boot.iso in installation tree`.

**Root cause**: Anaconda's `.treeinfo` schema changed across major OL
versions. OL6's `/.treeinfo` declares only `[images-x86_64]` with
`kernel = images/pxeboot/vmlinuz` and `initrd = images/pxeboot/initrd.img`,
without the `boot.iso` key that some `virt-install` versions expect.

**Fix**: The wrapper relies on libvirt 11.5+'s relaxed handling of
`.treeinfo` (kernel/initrd suffice; `boot.iso` is no longer required).
Phase A.4 verified this on the canonical RHEL 10 builder (libvirt
11.5.0-2.el10, qemu-kvm 10.0.0-13.el10). The OL6 env template's comment
flags this behavior. No code change is needed unless the builder host
is on an older libvirt; in that case, the operator would need to pass
`--location ${ISO},kernel=images/pxeboot/vmlinuz,initrd=images/pxeboot/initrd.img`
explicitly. The wrapper does not currently expose that knob.

**Verification**: Phase B-1 boot test launched a libvirt domain from
the OL6 U10 ISO and confirmed: ISO mounts, isolinux loads, Anaconda
13.21.263 TUI appears at the kickstart prompt. No further phase has
been executed by the author.

---

## D.15 `detect_os_variant()` fallback for OL6 (osinfo-db `ol6.X` naming)

**Symptom**: On builders with `osinfo-db-20250606+` (RHEL 10 default),
`virt-install --os-variant oraclelinux6.10` succeeds, but on older
builders (`osinfo-db-20230101`), the same call fails with
`Unknown OS variant 'oraclelinux6.10'`.

**Root cause**: osinfo-db went through a naming transition for OL
entries: older builds shipped `oraclelinux{N}.{U}` short-ids; newer
builds ship `ol{N}.{U}` (e.g. `ol6.10`, `ol7.9`). Some builders have
both, some have only one.

**Fix**: `detect_os_variant()` was extended to prepend the modern
`ol{N}.{U}` family at the top of its candidate chain:

```bash
# 0. Modern osinfo-db 'ol{N}.{U}' short-id
candidates+=("ol${major}.${update}")
for ((u = update - 1; u >= 0; u--)); do
  candidates+=("ol${major}.${u}")
done
candidates+=("ol${major}-unknown" "ol${major}")
```

The legacy `oraclelinux{N}.{U}` family remains in the chain
immediately below. On OL6 builders that have neither, the chain
continues to `rhel6.{U}` which is binary-compatible with OL6 and is
universally present.

**Caveat**: Both `osinfo-query` invocations the wrapper performs are
read-only and have no side effects. If `osinfo-query` itself is
unavailable (uncommon in 2026 but possible on stripped-down builder
images), `detect_os_variant()` returns 1 and the operator must set
`OS_VARIANT` manually in the env file.

---

## D.16 OL6 `ROOT_FS=xfs` must keep `/boot` on ext4

**Symptom**: When the OL6 env template defaults shifted from
`ROOT_FS="ext4"` to `ROOT_FS="xfs"` (to align with OL7/8/9/10), the
initial `distr::kickstart` implementation in the wrapper-synthesized
`distr/ol6-slim/image-scripts.sh` performed a global substitution:

```bash
sed -i -e 's!--fstype="ext4"!--fstype="xfs"!g' "${ks_file}"
```

This rewrote **both** `/boot` and `/` partitions to xfs:

```
part /boot    --fstype="xfs" --ondisk=sda --size=500  --label=/boot
part /        --fstype="xfs" --ondisk=sda --size=4096 --label=root  --grow
```

**Root cause**: OL6 ships GRUB Legacy 0.97 as the bootloader. While
grub-0.97 *does* include XFS read support in OL6's patched build, the
combination has been less battle-tested than XFS on grub2 (OL7+). The
industry-standard practice on OL6 systems running an XFS root is to keep
`/boot` on a smaller ext4 partition; this is also what RHEL 6 / OL 6
anaconda's automatic partitioning chooses when the user opts for XFS as
the root filesystem.

**Fix**: The substitution was changed to a line-anchored, partition-
specific pattern that targets only the root partition:

```bash
sed -i -e 's!^\(part /        --fstype=\)"ext4"!\1"xfs"!' "${ks_file}"
```

The pattern relies on the four-space alignment between `part /` and
`--fstype=` in the kickstart template embedded in
`phase3_clone_repository`. If that template is ever reformatted, this
substitution must be updated together with it (the kickstart template
and the sed pattern are co-located in `build-ol-aws-ami.sh` precisely so
this co-evolution is easy to spot).

**Verification**: A static check confirmed:

1. The pattern matches the `part /        --fstype="ext4"` line in the
   embedded kickstart template byte-for-byte.
2. The pattern does NOT match the `part /boot    --fstype="ext4"` line
   (different number of spaces; the anchor `part /        ` requires
   eight characters between `/` and `--fstype=`, which `/boot    ` does
   not satisfy).
3. The pattern is idempotent: re-running it on an already-substituted
   line is a no-op because `"xfs"` no longer matches the literal
   `"ext4"` source string.

**Caveat**: End-to-end (Phase C) validation of OL6 with `ROOT_FS=xfs`
has not yet been performed by the author (the OL6 build pipeline as a
whole remains Phase A/B verified only). The fix is structurally
correct based on the OL7 reference kickstart and GRUB Legacy XFS
documentation, but operators running OL6+XFS in anger should expect to
debug if anaconda or grub2 misbehaves on first boot.

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
again, update Part D with a new entry and add the new pattern to
`parse_ol_version_from_iso` / `derive_oracle_checksum_url` respectively.
