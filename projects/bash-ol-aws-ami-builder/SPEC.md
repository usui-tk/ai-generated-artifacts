---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.0.0
  rendered: 2026-06-06
---
# Bash Script Specification (SPEC) — build-ol-aws-ami.sh

> This SPEC documents `build-ol-aws-ami.sh` and its companion env templates.
> **Part A** is the repository-wide common specification, authored inline below
> (canonical-in-principle: bash has a single consumer today, so per the rule-of-two
> there is no shared bash spec home yet); **Parts B-D** are specific to this script.
> History lives in `CHANGELOG.md`; current and forward design lives here. This SPEC
> is reconstructed from the repository template canon and inherits the repository
> governance model rather than asserting its own.
>
> **The single most important rule**: when a piece of behavior is described
> here (phase contract, log markers, env property keys, validation order),
> any new feature MUST reuse the existing implementation. Do not redesign
> the phase numbering, log marker set, or the env property auto-detection
> rules — they have been hardened through many revisions documented in
> Part D, and rewriting them invites regressions.
>
> The repository-wide AI-generation policy and contributor rules apply; see
> [`AGENTS.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/AGENTS.md)
> and the repository root `README.md`.

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
  - [B.6 Build host package matrix](#b6-build-host-package-matrix)
  - [B.7 Guest OS package-manager matrix](#b7-guest-os-package-manager-matrix)
- [Part C — Quality Gates & Validation Checklist](#part-c--quality-gates--validation-checklist)
- [Part D — Known Pitfalls & Lessons Learned](#part-d--known-pitfalls--lessons-learned)
- [Appendix: How to add support for a new OL major release](#appendix-how-to-add-support-for-a-new-ol-major-release)

---

# Part A — Common Specification

> **Status: Canonical inheritance source (Bash / AWS scripts).**
> This Part A is the repository's canonical Part A for the
> **Bash / AWS scripting family** — the source of truth for any
> future Bash / shell-based AWS build pipeline SPEC authored in
> this style. It is the parallel of the PowerShell canonical SPEC
> at
> [`scripts/powershell/download-speakerdeck-oracle4engineer/SPEC.md`](../../powershell/download-speakerdeck-oracle4engineer/SPEC.md);
> the two canonicals overlap conceptually (reference assets,
> logging, error handling, dev workflow) but diverge in concrete
> form (Bash idioms vs PowerShell idioms, `env.properties` files
> vs `param()` blocks, `shellcheck` vs `psa.py`).
>
> Modifications to this Part A propagate to any future sibling
> Bash / AWS SPEC that inherits it; review cross-script impact
> before committing changes. The Part A inheritance rule, its
> rationale, and the forensic record of past inheritance violations
> (notably the `c40755c` Part A bloat regression in a sibling
> PowerShell SPEC) are recorded in the repository-wide
> [`AGENTS.md` §6 Part A Inheritance Rule (ABSOLUTE)](https://github.com/usui-tk/ai-generated-artifacts/blob/main/AGENTS.md#6-part-a-inheritance-rule-absolute)
> and
> [`AGENTS.md` §9 AP-1](https://github.com/usui-tk/ai-generated-artifacts/blob/main/AGENTS.md#9-anti-patterns-forensically-documented).
> LLM agents authoring or revising any Layer 3 Part A MUST consult
> both references before touching the inherited surface.

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
10. Phase 0–9 functions               phase0_preflight_checks ... phase9_register_ami
11. Helper functions interleaved      detect_qemu_user, derive_oracle_checksum_url, detect_os_variant
12. main()                            Calls phase0..phase9 with skip/build-only branching
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

- Phases are numbered **0 through 9 with no gaps** (no `Phase 5.5`).
- Phase function names follow `phase{N}_<verb>_<noun>()` (snake_case).
- Phase 0 is preflight; subsequent phases assume Phase 0 passed.

### Phase registry

| ID | Function | Group | Responsibility |
|---:|----------|-------|----------------|
| 0 | `phase0_preflight_checks` | Validation | KVM exposure, required commands, free disk, tmpfs/noexec checks |
| 1 | `phase1_install_prerequisites` | Provisioning | Install KVM/libvirt/virt-install/libguestfs/osinfo-db/acl |
| 2 | `phase2_grant_qemu_access` | Provisioning | setfacl `u:qemu:x` on WORKSPACE parent chain |
| 3 | `phase3_clone_repository` | Build | `git clone --depth 1` of oracle/oracle-linux. **For OL6 and OL7** (`OL_MAJOR_VERSION <= 7`): rewrites the OL8+-guard line in `cloud/aws/image-scripts.sh` to a no-op (an `.ol${N}-patch.bak` backup — e.g. `.ol6-patch.bak` / `.ol7-patch.bak` — left in place). OL6 additionally gets a second patch (`provision.sh` `kernel-uek-modules` skip) and a runtime-synthesized `distr/ol6-slim/` (see B.5). See D.10. |
| 4 | `phase4_prepare_env_properties` | Build | Resolve ISO checksum, OS_VARIANT, generate `env.properties.local` |
| 5 | `phase5_run_build` | Build | Invoke `bin/build-image.sh`; produce VMDK |
| 6 | `phase6_nitro_readiness_check` | Validation | Offline Nitro boot-readiness gate (NVMe host / ENA / fstab / bootloader) + instance-assurance report |
| 7 | `phase7_upload_to_s3` | AWS | `aws s3 cp` the VMDK |
| 8 | `phase8_import_snapshot` | AWS | `import-snapshot` + polling loop |
| 9 | `phase9_register_ami` | AWS | `register-image` with conditional `--tpm-support` |

### Phase groups (semantic)

- **Validation** (0, 6): Read-only diagnostics / offline image inspection; never mutates state.
- **Provisioning** (1, 2): Requires sudo; idempotent (skip if already done).
- **Build** (3, 4, 5): Operates inside `WORKSPACE`; produces a VMDK.
- **AWS** (7, 8, 9): Network operations against the configured `AWS_REGION`.

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
- `--build-only` → Run through Phase 6 (VMDK build + Nitro readiness check), then exit 0.
- `--skip-aws-import` → Synonym for `--build-only`.

---

## A.4 Logging Conventions

### Markers (color-coded)

| Marker | Helper | ANSI Color | Destination | Semantic |
|--------|--------|------------|-------------|----------|
| (banner) | `log_step` | Bold green | stdout | Phase header banner (`==========`; carries no literal `[STEP]` tag) |
| `[INFO]` | `log_info` | Bold blue | stdout | Informational; progress |
| `[WARN]` | `log_warn` | Bold yellow | **stderr** | Degraded but non-fatal advisory |
| `[ERROR]` | `log_error` | Bold red | **stderr** | Failure; usually followed by `die` |
| `[BUILD]` | `log_progress` | Bold cyan | stdout | Wrapper build-phase heartbeat |
| `[DEBUG]` | `log_debug` | (none) | **file always**; console only with `--debug` | Verbose diagnostics |
| `[EXTERNAL]` | `log_external` | Grey | stdout | A line re-emitted from an invoked external tool, attributed to its script |

This table is the Part A summary; **Part E is the authoritative, fuller
description** of the three logging axes (severity / source / logic-code) and the
file-logging behaviour. Do not duplicate Part E here — extend Part E when the
logging model changes.

### Line format

```
YYYY-MM-DD HH:MM:SS  [SEVERITY]  [OLAWS-CODE]  <message>
```

- The timestamp is local wall-clock time (`date '+%Y-%m-%d %H:%M:%S'`), **unified
  to this `YYYY-MM-DD HH:MM:SS` form on every timestamped channel** (including the
  `[BUILD]` heartbeat and the `[EXTERNAL]` re-emission). The phase banner
  (`log_step`) is the one channel with no timestamp.
- The `[OLAWS-<AREA><NN>]` logic-code tag is **optional**: it appears only on
  curated decision points and the Phase-6 assurance checks, never on every line
  (catalogue in Part E.4).
- Markers are a **curated, append-only** set (Part E): add a new marker only for a
  genuine new severity or source, never an ad-hoc one-off (`[OK]`, `[!]`), so the
  visual scan pattern operators rely on across many runs stays stable.
- `[WARN]` and `[ERROR]` go to `>&2` (stderr); `[INFO]`, the phase banner, and
  `[BUILD]` go to stdout; `[DEBUG]` goes to the log file always and to the console
  only with `--debug`.

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
| `AMI_NAME` | `OracleLinux-${MAJOR}-U${UPDATE}-x86_64-$(date +%Y%m%d-%H%M)`; when the ENA self-build is enabled (default), the auto-default also appends `-ena${ENA_BUILD_VERSION}` (the installer's pin) so a self-built-ENA AMI is distinguishable pre-launch. An explicitly set `AMI_NAME` is left untouched. |
| `AMI_DESCRIPTION` | `Oracle Linux ${MAJOR} Update ${UPDATE} (x86_64) custom AMI built via oracle-linux-image-tools`; the auto-default appends ` with self-built Amazon ENA ${ENA_BUILD_VERSION} (DKMS, AWS-optimized for Nitro)` when self-build is on, or ` (pure OL; ENA self-build skipped)` for `--skip-ena-driver`. `ENA_BUILD_VERSION` is read from `install-ena-driver.sh`'s `ENA_VERSION_OL<major>` pin (single source of truth). |
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
| `SERIAL_CONSOLE` | `no` | Install-time anaconda console; **debug opt-in** (`yes` can hang the build at install-VM end) — see note + D.18 |
| `CLOUD_INIT` | `Yes` | Enable cloud-init in the AMI |
| `CLOUD_USER` | `ec2-user` | AWS-convention first-login user |
| `KERNEL` | `uek` (OL7) / unset (OL8+) | OL7 requires UEK; see D.10 |
| `UEK_RELEASE` | `6` (OL7 only) | UEK major release; only meaningful for OL7 |
| `S3_KEY_PREFIX` | `ol${MAJOR}-ami-import` | Key prefix inside `S3_BUCKET` |
| `VMIMPORT_ROLE_NAME` | `vmimport` | Must match `setup-vmimport-role.sh` |

If `oracle-linux-image-tools` adds, renames, or drops keys upstream,
update the templates and this table in lockstep.

**EC2 login user (authority and precedence).** Every AMI this builder produces
(OL6-OL10) uses **`ec2-user`** as the first-boot SSH login account (key-only;
root/password login disabled). The name is cloud-init's
`system_info.default_user.name`, resolved at first boot from three layers,
lowest to highest precedence: (1) the Oracle Linux `cloud-init` **package
default** in `/etc/cloud/cloud.cfg` (`cloud-user`); (2) the **upstream
`oracle-linux-image-tools`** `cloud/aws` drop-in
`/etc/cloud/cloud.cfg.d/90_ol.cfg` (`name: ${CLOUD_USER}`), which wins because
cloud-init merges `cloud.cfg.d` over `cloud.cfg`; (3) **this builder**, whose env
templates set `CLOUD_USER="ec2-user"`. The deciding entity for the effective
login name is therefore this project's env templates, and the default login user
is **unified to `ec2-user` across all OL versions** — `cloud-user` is never the
operative account. On OL6 the `[ol-aws-ami-builder PATCH ol6-cloud-user]` hook
additionally drops the `systemd-journal` group (absent on OL6, so cloud-init's
`useradd` would otherwise fail and create no account) and rewrites the
otherwise-inert `cloud-user` string in `cloud.cfg` to `ec2-user` for legibility
(see D.26).

Note on the two serial-console keys (they are independent):
`SERIAL_CONSOLE` (install-time) controls whether the anaconda *installer*
streams to the serial console. The wrapper defaults it to **`no` (headless)**:
upstream then detects install completion via the domain lifecycle and applies
its own install timeout — the historically reliable path. Setting it to `yes`
makes upstream wait on `virsh console`, which does **not** cleanly return when
the install VM ends (reboot/poweroff/teardown) and was observed to **hang
`build-image.sh` until `BUILD_TIMEOUT_MIN`** even on otherwise-successful
builds; it also only streams useful output on old anaconda (OL6/7), not on OL8+
(tmux-based). Treat `yes` as a **debug-only opt-in** for watching the OL6/7
install phase (be ready to kill the VM). `SERIAL_CONSOLE_RUNTIME` independently
configures the *generated image's* console (EC2 Serial Console). The
wrapper-level `BUILD_TIMEOUT_MIN` (minutes, default `120` — a wrapper key,
*not* passed through to upstream) is an outer safety bound on the Phase-5 build
and reaps the transient build VM if it expires. A second wrapper key,
`HEARTBEAT_INTERVAL_SEC` (seconds, default `10`; `0` disables), logs a Phase-5
progress line every interval — elapsed time plus the build disk's *actual*
on-disk growth (`du`, i.e. real clusters written, not the preallocated apparent
size), best-effort domain state, and a `stage:` field — so a headless build's
liveness is visible regardless of anaconda generation (OL6 streams to the serial
console; OL8+ runs anaconda in tmux and is near-silent there). The `stage:` field
is the latest *live* `build-image.sh` orchestrator line, recorded by `log_external`
to a `BUILD_STAGE_FILE` (`${WORKSPACE}/.build-stage`, reset at Phase-5 start and
removed after the build) and read by the heartbeat; during a long, quiet in-guest
ENA compile it holds the last orchestrator line (e.g. the customize step), so an
elapsed-time-growing / disk-`+0MB` heartbeat reads as "alive but quiet", not a
hang. (The in-guest `install-ena-driver.sh` output — its `[ena-driver][stage]`
breadcrumbs — is *not* a live signal: virt-customize swallows guest provisioning
output unless the script fails; those breadcrumbs surface on the failure path and
in the make.log preserved at `/var/log/ol-aws-ami-builder-ena-make.log`.) The default is short because this
script is usually run interactively; it does not affect completion detection.

A third wrapper key, `NITRO_PRECHECK` (`enforce` | `warn` | `off`, default
`enforce`; *not* passed through to upstream), gates a **Phase 6 Nitro
readiness pre-check**: an offline, read-only inspection of the freshly built
VMDK (via libguestfs, `LIBGUESTFS_BACKEND=direct`, targeting the UEK kernel)
that adapts the logic of AWS's NitroInstanceChecks to the built image rather
than a running instance. It verifies the Nitro boot essentials: (1) the NVMe
**host** driver `nvme.ko` is built into the kernel or present in the kernel's
initramfs (else Nitro cannot mount the EBS/NVMe root); (2) the ENA driver is
present (built-in or module); (3) `/etc/fstab` uses `UUID=`/`LABEL=` rather than
`/dev/sd*`|`/dev/xvd*` (Nitro renames disks to `/dev/nvme*`); and (4) the
bootloader `root=` is likewise UUID/LABEL/LVM based (GRUB2 `linux*` lines and
OL6 GRUB-legacy `kernel` lines in `grub.conf`/`menu.lst`, **and** the BLS
`options` line in `/boot/loader/entries/*.conf` on OL8+, where the cmdline does
not live in `grub.cfg` — and where that line is commonly `options $kernelopts`,
so the check also resolves `kernelopts` from `/boot/grub2/grubenv`, falling back
to the `set kernelopts=` default in `grub.cfg`; "no `root=` found anywhere" is
reported INDETERMINATE, not a vacuous PASS). It runs after the
VMDK is produced and before the upload/snapshot/register phases, so a
non-bootable image is caught before those wasted steps. `enforce` `die`s on a
blocking finding; `warn` reports without dying; `off` skips it. Results that
cannot be determined (inspection tools absent, initramfs not readable) are
**fail-open** — the check warns and continues, so a missing tool never aborts an
otherwise-good build. The NVMe check (CHECK 1) inspects the initramfs with
several methods (`unmkinitramfs`, then `lsinitrd`/`lsinitramfs`, then a manual
decompress + `cpio -t`) because dracut images vary by compression
(gzip/xz/zstd/lz4) and may carry a leading microcode cpio; when the module is on
disk but **no** method can read the initramfs on the build host, CHECK 1 reports
`INDETERMINATE` rather than `FAIL` (a hard `FAIL` is reserved for nvme.ko being
genuinely absent from both the kernel and an inspectable initramfs). Detection
only; the wrapper performs no remediation. The inspection tools
(`libguestfs-tools`, and `unmkinitramfs` from `initramfs-tools-core` or
`lsinitrd`) are the same family already required for the upstream
`virt-sparsify` step.

After the four boot checks, Phase 6 also prints an **advisory Nitro instance
assurance report**: it classifies each Nitro generation (v2–v6) as `ASSURED`,
`SUPPORTED` (works, ENAv2 mode), `DEGRADED`, or `NOT-ASSURED` and lists
representative **x86-64** instance families per generation (this builder produces
x86-64 AMIs, so ARM/Graviton and Trainium/Inferentia types are intentionally
excluded — an x86-64 AMI cannot launch on them). The signal is ENA **ENAv3**
support — ENAv3 is the device generation on the majority of Nitro v4+ instance
types, while Nitro v2/v3 use ENAv1/ENAv2 and are unaffected by the ENAv3
thresholds. Per the amzn ENA driver docs, when the standalone driver's
`MODULE_VERSION` is present (`modinfo`): a driver `< 1.2.0` **fails to attach an
ENAv3 ENI** (Nitro v4+ → `NOT-ASSURED`, the one fatal-under-`enforce` case);
`1.2.0 ≤ driver < 2.2.9` works but with ENAv3 **performance degradation**
(Nitro v4+ → `DEGRADED`, a warning, *not* a failure); `≥ 2.2.9` is full ENAv3
support. The driver supports kernels `>= 3.10`, so ENAv1/v2 (Nitro v2/v3) work
regardless. UEK ships ENA **in-tree with no `MODULE_VERSION`**, so the report
falls back to the **kernel version** against the kernel where ENAv3 support was
introduced for OL/RHEL (RHEL 8.3, `4.18.0-240`). That kernel check is a
deliberately conservative proxy — UEK may backport ENAv3 below it, and the
in-tree driver still attaches in ENAv2 mode — so a sub-proxy kernel is reported
`SUPPORTED` (with an `ethtool -i` verification hint), never as a failure. The
assurance report is **purely advisory and never aborts the build** — only the
four boot-readiness checks (CHECK 1–4) feed the gate verdict. A driver `< 1.2.0`
(e.g. OL6's default ENA `1.1.2`) is reported as a Nitro v4+ ENAv3 attach risk
but does **not** fail the build, so the AMI can still be registered; refresh the
ENA driver in the guest for Nitro v4+ targets. Source: amzn/amzn-drivers ENA
Linux driver (`ENA_Linux_Best_Practices.rst`, `RELEASENOTES.md`). The
per-generation family lists are representative, not exhaustive.

Ahead of the advisory tiers the report prints two aligned, fixed-width lines —
**`ENA Driver (Kernel in-box)`** (stock in-tree `/kernel`, or `built into the
kernel (=y)`) and **`ENA Driver (Self-Build)`** (the DKMS `/extra`|`/updates`
module, or `not present` for a `--skip-ena-driver` / pure-OL build) — each with
its `modinfo` version. When the in-tree module carries no `modinfo` version
field (common for OL7/OL8 in-tree ENA), the in-box line shows an explicit
`in-tree, no version field (kernel-bundled)` note rather than a bare `none`. The
labels are width-aligned so the in-box vs self-built version delta is legible at
a glance. `install-ena-driver.sh` additionally logs the in-box module identity
(`version`/`srcversion`/`file`) for the target kernel BEFORE the self-build, so
the before/after delta is on record even though successful guest provisioning is
otherwise silent (libguestfs echoes a provisioning script's output to the host
only on failure). The
ENAv3-tier `signal` line continues to reflect the **effective** module (depmod
precedence `updates` > `extra` > `kernel`).

### Nitro initramfs drivers (nvme/ena)

Independently of the ENA driver *version*, the **initramfs must contain `nvme`
(and `ena`)** — on Nitro the root filesystem is NVMe-backed, so without nvme in
the initramfs the instance cannot mount root and fails to boot. The image is
built in a VM whose disk is virtio (`/dev/sda`), so dracut's **hostonly** mode
omits nvme from the initramfs (observed on OL7 UEK R6: `nvme.ko` was on disk but
absent from the initramfs, and Phase 6 CHECK 1 correctly FAILed). This is a boot
requirement, so Phase 3 **always** (even with `--skip-ena-driver`) appends a hook
to `cloud/aws/provision.sh` that writes `/etc/dracut.conf.d/02-ol-aws-nitro.conf`
(`add_drivers+=" nvme nvme-core ena "`, which also persists across in-instance
kernel updates) and regenerates the initramfs for the installed kernel
(`dracut -f`). It targets the highest UEK under `/lib/modules` (the appliance's
`uname -r` is not the guest's) and is best-effort — it never aborts the build;
CHECK 1 verifies the result. OL6 already shipped nvme in its UEK4 initramfs, so
the step is a harmless refresh there.

### ENA driver self-build (`--skip-ena-driver`)

**Rationale — baseline in-distro ENA drivers (measured).** The default OL images
ship an ENA driver bundled in `kernel-uek` that is too old for ENAv3 (Nitro
v4+). The Phase 6 assurance report measured the following on freshly built
images, which is the concrete justification for self-building a newer ENA driver
when producing an AWS-optimized AMI:

| OL | Kernel package (UEK) | In-distro ENA (`modinfo`) | ENAv3 status (amzn-drivers) | Self-build pin |
|----|----------------------|---------------------------|-----------------------------|----------------|
| OL6 U10 | `kernel-uek-4.1.12-124.48.6.el6uek.x86_64` | `1.1.2` | `< 1.2.0` → ENAv3 ENI attach **fails** on Nitro v4+ | `ena_linux_2.9.1` |
| OL7 U9  | `kernel-uek-5.4.17-2136.338.4.2.el7uek.x86_64` | `2.1.0K` | `1.2.0`–`< 2.2.9` → ENAv3 **performance degradation** | `ena_linux_2.17.0` |

Both bundled drivers are below the `2.2.9` full-ENAv3 threshold, so on Nitro v4+
instances the stock images either fail to attach an ENAv3 ENI (OL6) or run
degraded (OL7). The pinned self-build versions (`2.9.1` / `2.17.0`) are both
`>= 2.2.9`, restoring full ENAv3 support. (Versions/kernels above are the
measured baseline as of 2026-06 and will shift as the OL ISOs receive errata;
the installer always reports the before/after `modinfo` version.)

By default the wrapper produces an **AWS-optimized AMI**: Phase 3 appends a hook
to the upstream `cloud/aws/provision.sh` that builds and installs a pinned
Amazon ENA driver inside the guest during provisioning. The CLI switch
`--skip-ena-driver` removes the hook, producing a **pure, unmodified OL AMI** —
the two distinct build purposes. The hook embeds `install-ena-driver.sh`
(shipped alongside the wrapper) verbatim via a single-quoted heredoc and runs it.

The installer is the remedy for OL's old in-distro ENA driver (e.g. OL6 ships
ENA `1.1.2`, below the ENAv3 floor — see the assurance report above). It:

- **Self-gates by OS major**: builds for **OL6** (pinned `ena_linux_2.9.1`) and
  **OL7** (pinned `ena_linux_2.17.0`, the newest release confirmed to support
  RHEL7 as of 2026-06); on **OL8+** it is a no-op because those ship a current
  in-distro driver. Pins are chosen as the newest release that **builds** on each
  target OS (the ENA driver is a kernel module; newer releases assume newer
  kernels/toolchains). Override per run with `ENA_DRIVER_VERSION`.
  - **OL6/UEK4 buildable window (`ena_linux` ≈ `[2.8.6, 2.9.1]`).** Validated on a
    real Nitro OL6.10 instance (kernel `4.1.12-124.48.6.el6uek`, gcc 4.4.7).
    *Floor:* below ~`2.8.6` the driver's `kcompat.h` redefines `page_ref_count`,
    which Oracle backported into UEK4 `>= 124.43.1`, so the build fails with a
    redefinition error (amzn/amzn-drivers issue #210; resolved driver-side at
    `2.8.6`). **That driver-side fix is conditional on the build detecting UEK**
    (`IS_UEK` + `ENA_KERNEL_SUBVERSION_*`), which the amzn Makefile derives from
    `uname -r`; under the libguestfs appliance `uname -r` is the non-UEK appliance
    kernel, so even `2.9.1` redefines `page_ref_count` on a backported UEK4 target
    unless the detection is retargeted to the build target — see "UEK detection
    (cross-kernel build)" below. *Ceiling:* `2.10.0` introduced the ECC (ENA Compatibility Check)
    build-time API autodetect, which **false-positives on this old kernel + EL6
    toolchain** and emits calls to newer-kernel symbols that are absent here
    (`pci_dev_id`, `irq_update_affinity_hint`, `ethtool_puts`,
    `netif_napi_add_config`), so `2.10.0`+ fail to compile. `2.9.1` is the last
    pre-ECC release and is the pinned ceiling; `2.8.6` is a proven fallback. Both
    are `>= 2.2.9` (full ENAv3). Re-evaluate when the OL6 UEK4 errata kernel or
    the driver's ECC changes.
- **Self-contained**: it installs everything it needs itself — the EPEL repo,
  `gcc`/`make`, `dkms`, and the matching `kernel-uek-devel` headers — so it can
  be run directly on a stock OL6/OL7 instance (see "Standalone validation"
  below) as well as from provisioning.
- **Dual-mode target kernel**: standalone on a running instance it targets the
  **live** kernel (its `/lib/modules` dir exists); under the libguestfs
  appliance (provisioning) `uname -r` is the appliance's, so it falls back to the
  highest UEK under `/lib/modules`. It always builds against a specific kernel
  (`dkms ... -k <kver>`).
- **Resolves missing `kernel-uek-devel`**: the stock OL ISO ships an older
  `kernel-uek` whose `-devel` may be pruned from the repos (`No package
  kernel-uek-devel-<ver> available`); since `yum` does not fail on a missing
  package, DKMS would otherwise abort with "kernel headers ... cannot be found".
  The installer enables the UEK repo (`*UEKR4*`/`*UEKR6*`), tries the exact
  `-devel`, and if the headers are still absent installs the **latest**
  `kernel-uek` + matching `-devel` and **retargets** to it (a guaranteed
  buildable pair).
- **UEK detection (cross-kernel build, OL6).** The amzn-drivers Makefile derives
  `IS_UEK` and `ENA_KERNEL_SUBVERSION_*` from `uname -r` (the *running* kernel),
  and those gate the `kcompat.h` `page_ref_count` UEK-backport guard. Under the
  libguestfs provisioning appliance `uname -r` is the non-UEK appliance kernel,
  so the macros are unset and the guard redefines `page_ref_count` against a
  backported UEK4 target (`>= 4.1.12-124.43.1`, e.g. `-124.48.6`) — a
  build-breaking redefinition that the version pin alone does not avoid. Because
  the build already passes the target kernel as `BUILD_KERNEL`, the installer
  patches that detection (OL6 only) to read `BUILD_KERNEL`, so the guard
  evaluates against the DKMS target rather than the appliance. OL7/UEKR6 is a
  `>= 4.6` kernel, so the `page_ref_count` block is compiled out regardless and
  its Makefile is left untouched (per-OS isolation). Standalone runs on a live
  instance are unaffected (`uname -r` is the real UEK kernel there).
- **Builds via DKMS** (`REMAKE_INITRD`/`AUTOINSTALL`), so the module is rebuilt
  automatically across in-instance kernel upgrades. DKMS comes from EPEL —
  Oracle-provided `ol7_developer_EPEL` on OL7, and the Fedora **EPEL 6 archive**
  on OL6 (Oracle does not provide EPEL 6). If DKMS is unavailable it falls back
  to a plain `make` build plus `depmod`.
- **Regenerates the initramfs** for the target kernel (`dracut -f`) so the new
  driver is present at boot, and removes any stale
  `/etc/udev/rules.d/70-persistent-net.rules` for AMI hygiene.
- **Surfaces build diagnostics on failure.** If the module build fails (DKMS or
  the plain-`make` fallback) the script dumps `dkms status` and every `make.log`
  under `/var/lib/dkms/amzn-drivers/<version>/` to stderr (prefixed
  `[ena-driver][ERROR]`) before aborting. Because `oracle-linux-image-tools`
  (libguestfs `virt-customize`) echoes a guest provisioning script's output to
  the host build log **only on failure**, this is what makes the actual
  compiler error visible there — without it a forwarded build log shows only the
  opaque "Bad return status for module build" and an in-guest `make.log` path.

**Standalone validation.** `install-ena-driver.sh` can be copied to a freshly
launched **stock** OL6/OL7 instance and run directly (`sudo ./install-ena-driver.sh`)
to iterate on the driver build in isolation before any end-to-end image build.
It targets the live kernel; if that kernel's `-devel` is unavailable it installs
and retargets to the latest `kernel-uek` (verify with `modinfo ena` after a
reboot into the new kernel). This makes the build a repeatable, independently
verifiable step.

Provisioning (and a launched instance) has outbound access to the Oracle Linux
yum servers and EPEL, so it also reaches GitHub to fetch the pinned
`amzn-drivers` release tarball. Source: amzn/amzn-drivers ENA Linux driver
(`RELEASENOTES.md`, `ENA_Linux_Best_Practices.rst`) and the
supported-distributions list.

Note on `UEK_RELEASE`: this key is only consumed by the upstream tool
when `KERNEL=uek`. It is meaningful for OL7 (UEK6 is the only viable
release for OL7) and harmless to set (or omit) on OL8/9/10 where the
upstream distr-level default is preferred.

### Container compile-test (`ENA_BUILDTEST`)

`ENA_BUILDTEST=1` runs `install-ena-driver.sh` as a self-checking compile-test
inside a disposable, kernel-less clean-core container (see TESTING, "ENA driver
container compile-test"), so the pinned driver can be proven to build per OL
major / UEK kernel without a full image build or a live Nitro instance. It is a
test-only switch: with `ENA_BUILDTEST` unset or `0` (the default) the script is
the production path byte-for-byte — the environment-tagged logging, the
container kernel provisioning, the TLS relaxation, and the result line below are
all inert.

- **Kernel provisioning.** A container has no running kernel and no
  `/lib/modules` tree, so before the production kernel-detection step the test
  mode installs a full `kernel-uek` + `kernel-uek-devel` (the container is
  throwaway, so the kernel footprint is irrelevant). This creates
  `/lib/modules/<kver>/` and the `build` symlink, after which the production path
  — kernel detection, `kernel-uek-devel` resolution, the OL6 Makefile UEK
  retarget, DKMS `build`+`install`, initramfs regeneration, and `ena.ko`
  verification — runs unchanged. The provisioning step is per-OS (literal
  commands, by detected `OL_MAJOR`): OL6 enables the shipped Fedora-archive EPEL
  + `ol6_UEKR4`; OL7 enables `ol7_developer_EPEL` + `ol7_UEKR6`; OL8 (whose slim
  base ships `dnf` only) bootstraps the `yum` compat via `dnf`, then enables
  `ol8_developer_EPEL` + `ol8_UEKR6`. The shipped (disabled) EPEL is enabled
  persistently so the production `setup_epel` finds it already enabled and does
  not create a second repo.
- **`INSECURE_TLS`.** `INSECURE_TLS=1` (default `0`) drops TLS peer verification
  for the test-mode network commands only — `yum --setopt=sslverify=false` and
  `curl -k` — for environments where the container cannot verify the peer chain
  (a MITM dev proxy, or EL6 NSS trust gaps that otherwise fail the GitHub fetch
  with curl error 77). It is read only inside the `ENA_BUILDTEST` branches;
  production never consults it beyond the default.
- **Result contract.** Beyond the exit code (`0` = ok, non-zero = fail), the run
  prints one machine-parseable JSON line tagged
  `[ena-driver][buildtest][result]`, so a harness can judge pass/fail and record
  the `{OS x ena_linux x kernel}` facts without scraping logs:
  - ok: `{"status":"ok","osmajor","ena_version","kver","dkms","ko","ko_version"}`
  - fail: `{"status":"fail","osmajor","ena_version","kver","reason"}` (emitted by
    `die`; `reason` is JSON-escaped). The exit code always agrees with `status`.

Validated end-to-end (the driver actually compiles, installs, and verifies) on
OL6 (`ena.ko` 2.9.1g, UEK4 `4.1.12-124.48.6.el6uek`), OL7 (`ena.ko.xz` 2.17.0g,
UEK6 `5.4.17-2136.338.4.2.el7uek`), and OL8 (`ena.ko.xz` 2.17.0g, UEK6
`5.4.17-2136.356.4.2.el8uek`). OL8 self-build is **standalone-only**: the AMI
pipeline keeps OL8 on its in-distro ENA driver — `build-ol-aws-ami.sh` gates the
provision.sh self-build hook (and the `-ena<ver>` AMI naming) to OL6/OL7, so OL8+
AMIs are produced unmodified. OL9+ remain a no-op in the installer.

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
2026-06-08 07:32:35 [ERROR] BOOT_MODE_BUILD='uefi' is not supported for CLOUD=aws.
2026-06-08 07:32:35 [ERROR]   oracle-linux-image-tools only accepts BOOT_MODE=bios for AWS targets.
2026-06-08 07:32:35 [ERROR]   Set BOOT_MODE_BUILD="bios" in env.properties.local (or remove the line
2026-06-08 07:32:35 [ERROR]   to use the default).
```

Example (bad):

```
2026-06-08 07:32:35 [ERROR] Invalid BOOT_MODE_BUILD
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
4. bash tests/run-all.sh                        ← static+test gate: B-T1 parse,
                                                   B-T2 shellcheck -S style, ...; 0 failures
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
- **Phase 8** polling loop has a 90-minute hard timeout (90 iterations
  of 60s) and treats describe-import-snapshot-tasks API failures as
  transient (retry, don't abort).
- **Phase 9** conditionally adds `--tpm-support v2.0` only when
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
| `ROOT_FS` | unset (xfs default) | unset | unset | `xfs` (only xfs/btrfs/lvm valid in upstream OL7+) | `ext4` (required; anaconda-13 refuses an xfs/lvm/btrfs root — see D.16) |
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

The bucket itself is created lazily by `phase7_upload_to_s3` if missing
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
2026-06-08 07:32:35 [INFO]  AWS_REGION         = us-east-1 (source: imdsv2)
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
discoverable by `grep -r '\[ol-aws-ami-builder' "${WORK_REPO_DIR}"`. Markers
take one of two shapes:

```
[ol-aws-ami-builder OL{N} PATCH]          # version-specific (the OL8+-guard removal)
[ol-aws-ami-builder PATCH {short-tag}]    # feature-specific, version-independent
```

where `{N}` is the OL major version (6 or 7) and `{short-tag}` is a descriptive
identifier. All are applied inside `phase3_clone_repository`. Current markers:

| Marker | File patched | Trigger | Purpose |
|--------|--------------|---------|---------|
| `[ol-aws-ami-builder OL6 PATCH]` | `cloud/aws/image-scripts.sh` | `OL_MAJOR_VERSION == 6` | Remove the OL8+ guard (OL6 mode) |
| `[ol-aws-ami-builder OL7 PATCH]` | `cloud/aws/image-scripts.sh` | `OL_MAJOR_VERSION == 7` | Remove the OL8+ guard (OL7 mode) |
| `[ol-aws-ami-builder PATCH kernel-uek-modules]` | `cloud/aws/provision.sh` | `OL_MAJOR_VERSION <= 7` | Skip the `kernel-uek-modules` install on OL6/OL7 (UEK < R7; bundled in `kernel-uek`) |
| `[ol-aws-ami-builder PATCH declare-g-ol6]` | `env.properties.defaults` | `OL_MAJOR_VERSION == 6` | Guard `declare -gA REPO` with a `\|\| declare -A` fallback (bash 4.1 in the OL6 guest has no `declare -g`) |
| `[ol-aws-ami-builder PATCH ol6-cloud-user]` | `cloud/aws/provision.sh` | `OL_MAJOR_VERSION == 6` | Wrap `cloud::cloud_init` so the OL6 cloud-init default user becomes `ec2-user` (strips the absent `systemd-journal` group; runs after the configs are written) — see D.26 |
| `[ol-aws-ami-builder PATCH nitro-initramfs]` | `cloud/aws/provision.sh` | always (AWS cloud path) | Drop an `/etc/dracut.conf.d` `add_drivers` file forcing `nvme`/`ena` into the initramfs and regenerate it (Nitro boot requirement; Phase 6 CHECK 1 verifies the result) |
| `[ol-aws-ami-builder PATCH serial-console]` | `cloud/aws/provision.sh` | GRUB2 systems (OL7+; hook self-skips on OL6 GRUB Legacy) | AWS-recommended serial console in 3 layers: (1) `console=tty0 console=ttyS0,115200n8` on all entries via `grubby --update-kernel=ALL` (BLS-aware) + `GRUB_CMDLINE_LINUX`; (2) `GRUB_TERMINAL`/`GRUB_SERIAL_COMMAND` + `grub2-mkconfig`; (3) `serial-getty@ttyS0` enabled — see D.25 |
| `[ol-aws-ami-builder PATCH ena-driver-build]` | `cloud/aws/provision.sh` | `ENA_DRIVER_BUILD == 1` (default; `--skip-ena-driver` disables) | Inject the in-guest Amazon ENA driver self-build hook (DKMS; installer is a no-op on OL8+) — logged as `[OLAWS-ENA01]`, see A.7 |
| `[ol-aws-ami-builder PATCH selinux-relabel-fallback]` | `bin/build-image.sh` | host libguestfs lacks the `selinuxrelabel` optgroup | Schedule a first-boot `/.autorelabel` instead of the offline relabel when the build host's libguestfs cannot relabel — see D.17 |

The `sed`-based substitutions (the OL6/OL7 guard removals, `kernel-uek-modules`,
`declare-g-ol6`) leave a `.bak` backup next to the modified file; the
marker-bracketed hook injections (`ol6-cloud-user`, `nitro-initramfs`,
`serial-console`, `ena-driver-build`) are `>>`-appended blocks. Every patch is
idempotent: it is fronted by a `grep -Fq` marker check so a re-run against an
existing clone re-detects its marker and skips.

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
   no-ops; OL6/OL7 are then expected to still work because the absent
   package would no longer be installed.
3. If `distr/ol7-slim/` structure changes (function signatures, common
   helper names like `common::distr_cleanup`, `common::latest_kernel`,
   etc.), the OL6 heredoc templates in `phase3_clone_repository` must
   be updated by hand. This is the highest-risk surface for upstream
   drift.
4. The OL6 kickstart (`EOF_OL6_KS`) is a *mirror* of OL7's `ol7-ks.cfg`,
   but OL6 ships **anaconda-13** with an older kickstart command set.
   After any edit to that heredoc — and especially after re-syncing it
   from a newer `ol7-ks.cfg` — run `tests/validate-kickstart.sh`
   (`ksvalidator -v RHEL6`) to catch OL7-syntax leakage before it halts
   the install (see D.18 for the failure mode and `TESTING.md` for the
   procedure and its syntax-only limitation).

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
| 2 | `sed` patch | `cloud/aws/provision.sh` | Skip `kernel-uek-modules` install on OL6/OL7 (D.11) |
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
9. OL6 cloud-init: the **operative** version is the stock base-repo
   `cloud-init-0.7.5` — every OL6 cloud-init hook in this wrapper targets it,
   and the `ec2-user` fix (D.26) was verified against
   `cloud-init-0.7.5-8.el6_9.2`. (The `ol6_addons` repo additionally offers a
   newer `cloud-init-18.4-2.0.9.el6.x86_64`, but the OL6 path does not rely on
   it — the handling is written against 0.7.5's `cloud.cfg.d` merge semantics
   and IMDSv1-only metadata; see A.7 / D.27.) `cloud-utils-growpart-0.27-9.el6.x86_64`
   confirmed in `ol6_addons`.

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
| `sed` patches needed | 2 (`image-scripts.sh` + `provision.sh`) | 2 (`image-scripts.sh` + `provision.sh`) |
| Kernel | UEK6 (5.4.17) | UEK4 (4.1.12) — only ENA-capable kernel for OL6 |
| Filesystem options | xfs, btrfs | ext4, xfs (no lvm/btrfs at this layer) |
| Init system | systemd | Upstart (`service` / `chkconfig`) |
| Bootloader | GRUB2 | GRUB Legacy |
| Kickstart syntax | Anaconda 19.x (`inst.` prefix) | Anaconda 13.x (no `inst.` prefix) |
| NTP daemon | chronyd | ntpd |
| `linux-firmware` | optional | hard dependency of `kernel-uek` |
| `kernel-uek-modules` package | absent (UEK6; bundled in `kernel-uek`) | absent (UEK4; bundled in `kernel-uek`) |
| AWS VM Import support | EOL (2024-12-31) | EOL (with ELS ended 2024) |
| End-to-end validated | No (patch verified, build not run) | No (Phase A+B done, Phase C not run) |

The asymmetry in the table is the rationale for why OL6 needed its own
overall-architecture section (B.5) and OL7 did not: OL7 is a thin patch
on top of an otherwise-functional upstream pipeline, whereas OL6
essentially rebuilds the OL-specific glue layer from scratch inside the
wrapper.

## B.6 Build host package matrix

`phase1_install_prerequisites` provisions the build host. Detection reads
`ID` / `VERSION_ID` from `/etc/os-release` (`ID_LIKE` is only a fallback used
to produce a clearer refusal message for unlisted derivatives). The builder
installs the **KVM + libguestfs superset** the whole pipeline needs — not just
the minimal "install KVM" set — and supports only the **latest two
generations** of each build host OS. Older releases are reference-only and
refused with a `die` (they are not branched).

**Supported (dnf family)** — OL / RHEL / Rocky / AlmaLinux / CentOS Stream
**10, 9**; Fedora **44, 43**:

```
qemu-kvm libvirt libvirt-client libvirt-daemon-config-network \
libvirt-daemon-driver-qemu virt-install libguestfs guestfs-tools \
edk2-ovmf libosinfo osinfo-db osinfo-db-tools acl
```

**Supported (apt family)** — Ubuntu **26.04, 24.04**; Debian **13, 12**:

```
<qemu> libvirt-daemon-system libvirt-daemon libvirt-clients virtinst \
libguestfs-tools ovmf libosinfo-bin osinfo-db osinfo-db-tools acl
```

where `<qemu>` is **`qemu-system`** on Ubuntu 26.04 (the `qemu-kvm`
transitional package was dropped) and **`qemu-kvm`** on Ubuntu 24.04 /
Debian 13 / 12. `bridge-utils` is intentionally **not** installed: the builder
relies on the libvirt default NAT network (`virbr0`).

| family | OS / versions | pkg mgr | qemu package | guestfs | OVMF | osinfo |
|--------|---------------|---------|--------------|---------|------|--------|
| dnf | OL/RHEL/Rocky/Alma/CentOS Stream 10, 9; Fedora 44, 43 | `dnf` | `qemu-kvm` | `libguestfs` + `guestfs-tools` | `edk2-ovmf` | `libosinfo` `osinfo-db` `osinfo-db-tools` |
| apt | Ubuntu 26.04 | `apt` | `qemu-system` | `libguestfs-tools` | `ovmf` | `libosinfo-bin` `osinfo-db` `osinfo-db-tools` |
| apt | Ubuntu 24.04, Debian 13, 12 | `apt` | `qemu-kvm` | `libguestfs-tools` | `ovmf` | `libosinfo-bin` `osinfo-db` `osinfo-db-tools` |

**Reference-only (refused with `die`)**: Ubuntu 22.04, Debian 11 / 10,
Fedora <= 42, CentOS Stream <= 8, OL / RHEL / Rocky / Alma <= 8.

> The Ubuntu 26.04 row is taken verbatim from the upstream server-world KVM
> page (`qemu-system libvirt-daemon-system libvirt-daemon virtinst
> bridge-utils libosinfo-bin`); `bridge-utils` is then dropped and the
> libguestfs / OVMF / osinfo / acl superset this pipeline requires is added.
> The remaining rows are organized from cross-referenced install recipes; the
> only version-dependent difference is the qemu package name.

**SELinux relabel caveat (apt family)**: the Debian / Ubuntu `libguestfs`
build omits the `selinuxrelabel` optgroup — it is compiled out of `guestfsd`
at libguestfs build time, so **no host package enables it** (installing
`policycoreutils` / `selinux-utils` to provide `setfiles` does not help; see
Part D D.17). Consequently the host-side per-filesystem relabel in upstream
`bin/build-image.sh` cannot run on apt-family hosts. The wrapper patches
upstream in Phase 3 to fall back to a guest first-boot relabel
(`touch /.autorelabel`); the resulting AMI is still `SELINUX=enforcing`. On
dnf-family hosts the optgroup is present and the host-side relabel runs
unchanged, so the patch is a no-op there.

## B.7 Guest OS package-manager matrix

The package operations that run **inside the guest** during the image build
(the kickstart `%post` and the `distr/<rel>-slim/provision.sh` functions) use
the OL guest's own package manager, which differs by major release. All of
OL 6-10 remain supported; the manager is organized as follows:

| OL | pkg mgr | config-manager | security update | kernel | provision source |
|----|---------|----------------|-----------------|--------|------------------|
| 6 | `yum` | `yum-config-manager` (yum-utils) | `yum-plugin-security` -> `yum update --security` | `kernel-uek` (UEKR4; modules bundled, no `kernel-uek-modules`) | synthesized by this wrapper (B.4) |
| 7 | `yum` | `yum-config-manager` (yum-utils) | `yum-plugin-security` | `kernel-uek` (UEKR6; modules bundled, no `kernel-uek-modules`) | upstream `distr/ol7-slim/` + OL7 patches |
| 8 | `dnf` | `dnf config-manager` (dnf-plugins-core) | `dnf upgrade --security` (built in) | `kernel-uek(-modules)` | upstream `distr/ol8-slim/` |
| 9 | `dnf` | `dnf config-manager` (dnf-plugins-core) | `dnf upgrade --security` | `kernel-uek(-modules)` | upstream `distr/ol9-slim/` |
| 10 | `dnf` | `dnf config-manager` (dnf-plugins-core) | `dnf upgrade --security` | `kernel-uek(-modules)` | upstream `distr/ol10-slim/` |

Notes:

- **OL6/7 use `yum`; OL8/9/10 use `dnf`.** On OL8+ `yum` is a `dnf` shim, but
  the synthesized (OL6) / patched (OL7) logic targets the native tool for each
  generation.
- The OL6 kickstart `%packages` already includes **`yum-utils`** (provides
  `yum-config-manager`) and **`yum-plugin-security`**, so the OL6 provision can
  rely on them without an extra install step.
- `kernel-uek-modules` does **not** exist on OL6 / UEKR4 or OL7 / UEKR6 (the
  modules, including `amazon/ena`, are bundled inside `kernel-uek`); the
  separate package exists only from **UEK R7 (OL8+)**. See the `provision.sh`
  patch in B.4 and **D.11**.
- This matrix governs only the **guest** package operations; the **build
  host** package matrix is B.6.

---

## B.8 Container clean-core test base (`tests/cleancore/`)

`tests/cleancore/` holds five self-contained builders —
`build-cleancore-ol6.sh` / `-ol7.sh` / `-ol8.sh` / `-ol9.sh` / `-ol10.sh`
(naming convention: `build-cleancore-ol<MAJOR>.sh`) — each producing a
**clean-core Oracle Linux container rootfs** for one OL major. They are a
reusable, general-purpose **test base** for the project's container-level checks
(repo-availability, guest provisioning shell logic, ENA driver compile-tests,
upstream-drift structural checks). This is **developer / CI-side tooling**: it is
**not part of the AMI build pipeline** (`build-ol-aws-ami.sh`) and is **not run
by `tests/run-all.sh`** (a run needs root, network, and a multi-hundred-MB
build). The builders live in the project blast-radius; operational run notes are
in `TESTING.md` ("Container clean-core test base").

A self-contained orchestrator `tests/cleancore/build-cleancore.sh` wraps the
per-OL builders: `--ol <N>` builds one, `--all` builds every OL that has a
builder (ascending; `--continue` to keep going past a failure), writing
`<out-dir>/cleancore-ol<N>.tar.gz`. It **invokes each builder as a separate
executable** (never sources it), so a builder remains the single source of truth
for its own OL. It recognises the B.6 build-host matrix (the AMI pipeline's
supported execution environments, including the `ubuntu-latest` CI target) and
only **warns** outside it — a clean-core build is userland-only and host-agnostic
— while it **hard-fails** on a missing prerequisite (root + the
`unshare`/`chroot`/`mknod`/`curl`/`tar`/`xz`/`gzip`/`truncate`/`find` toolchain).
Like the builders it is self-contained (inline helpers, no shared library) and
not a `run-all.sh` tier.

A container shares the host kernel and has no `/dev/kvm`, so this base covers the
**guest userland** only — it is **not** a substitute for the VM image build /
Nitro boot (those stay on the Fedora KVM host; see B-T7 / B-T8 in `TESTING.md`).

### Three execution environments

Each builder tags every block with the environment it runs in:

- **[A] HOST** — the machine running the script (Claude sandbox / CI = Ubuntu
  24.04 / end-user = RHEL 10|9, Fedora 44). Orchestrates only: download, extract,
  edit, pack, self-test. No container runtime is required.
- **[B] BUILDER** — a **throwaway** Oracle-distributed image driven via
  `unshare`+`chroot`, **build-use only** (its contents never enter the
  deliverable). It must be **EL-native** so the in-guest rpm can read the rpmdb
  it writes. It reads **only** a build-dedicated `cleancore.repo` pointing at
  verified `yum.oracle.com` URLs; its own bundled repo configs are removed.
- **[C] CLEAN-CORE** — the deliverable rootfs from the `yum`/`dnf
  --installroot` transaction, finalized from [A] (device nodes; OCI yum-variable
  rewrite to `yum.oracle.com` + `https`; OL6 UEK enable-vars disabled;
  build-time repo dropped; logs zero-filled; `machine-id` / ssh host keys
  cleared) and packed as a `.tar.gz`. The self-test runs against a **fresh
  unpack** of that tarball (what a container runtime would see), not the build
  tree.

### Per-OL specifics

| OL | builder (build-use only) | pkg mgr | enabled repos | package-set source |
|----|--------------------------|---------|----------------|--------------------|
| 6 | OL6.6 public-yum docker image (rpm 4.8 / db4); **TLS-modernized first** | `yum` | `latest` | **slim-aligned curated essentials** (`@core` dropped; no upstream `ol6-slim`; see "Package set" below) |
| 7 | `7-slim` rootfs (ships `yum`) | `yum` | `latest` + `UEKR6` | **slim-aligned curated essentials** (`@core` dropped; see "Package set" below) |
| 8 | `8-slim` rootfs + `microdnf install dnf` | `dnf` | `baseos` + `appstream` | **slim-aligned curated essentials** (`@core` dropped; see "Package set" below) |
| 9 | `9-slim` rootfs + `microdnf install dnf` | `dnf` | `baseos` + `appstream` | **slim-aligned curated essentials** (`@core` dropped; see "Package set" below) |
| 10 | `10-slim` rootfs + `microdnf install dnf` | `dnf` | `baseos` + `appstream` | **slim-aligned curated essentials** (`@core` dropped; see "Package set" below) |

- **EL-native builder is mandatory.** rpm / BerkeleyDB versions must match the
  target so the in-guest rpm reads the rpmdb. **OL6 stays rpm 4.8 / db4 forever**
  (EOL), and an EL7 rpm 4.11 / db5 builder writes a db an EL6 rpm reads as **0
  packages** — so OL6 uses an EL6-native builder, giving permanent rpmdb
  compatibility.
- **OL6 builder modernization.** The 2014-era OL6.6 image's NSS/curl cannot
  TLS-handshake modern `yum.oracle.com`; the builder's own rpm 4.8 first installs
  host-fetched `el6_10` NSS/curl/ca-certs RPMs, then `yum` updates the package
  managers, after which `https` works.
- **Package set: per-OL, slim-aligned.** **OL6 through OL10 have all been
  trimmed** to a container-appropriate, slim-aligned set: `@core` is dropped (so no
  kernel/boot/firewall/cron/syslog), a minimal userland plus explicit test-base
  essentials are installed, `git-core` replaces `git` (avoiding ~60 `perl-*`
  packages), `net-tools` is omitted, and the Oracle EPEL repo is wired in but
  **shipped disabled** (the ENA/SSM harnesses enable it on demand for e.g.
  `dkms`). **`jq`** (a curated test-base essential) is installed on every
  clean-core: from the **standard OL repo** on OL7–OL10 (where it is part of the
  enabled `latest`/`appstream` set, so it is simply an `INCLUDE` member), and on
  **OL6** — where `jq` is not in the base repo but is an EPEL package — from the
  **EPEL archive**, by enabling EPEL **transiently for that one install** in
  finalize (after the EPEL repo is configured); the shipped EPEL repo stays
  `enabled=0`. `systemd` is present (a hard dependency of full `dnf` on EL8/EL10, with
  `pam`/`sudo`; pulled transitively by `iputils`/`procps-ng` on EL7) but in
  container/chroot use it is never PID 1. **EL8 specific:** a raw `dnf` with no
  langpack selection defaults to `glibc-all-langpacks` (~416 MB of world locales),
  which the official `ol8-slim` does not ship — so the OL8 builder pins
  `glibc-minimal-langpack` and excludes `glibc-all-langpacks` to match the slim
  reference (EL9/EL10 default to the minimal langpack, so they need no pin).
  **EL7 specific:** EL7 has no `git-core` split (so OL7 carries plain `git`, which
  pulls ~30 `perl-*` packages); `git-lfs` and the `zstd` CLI are EPEL-only/absent
  in the EL7 base repos, so they are not in the OL7 clean-core (installable on
  demand from the shipped-disabled EPEL repo); EL7 has no `glibc` langpack split;
  and the base `oraclelinux-release` (which provides `/etc/oracle-release`) is
  listed explicitly because the EL7 `oraclelinux-release-el7` does not pull it in.
  **EL6 specific:** OL6 (EOL; rpm 4.8 / db4) is built by an EL6-native builder
  (the OL6.6 image) doing a fresh curated `yum --installroot` install — not a trim
  of an upstream slim, which does not exist for EL6. Like EL7 it carries plain
  `git` (no `git-core` split) plus `procps` (not `procps-ng`) and `nc` (not
  `nmap-ncat`); unlike the other clean-cores it **includes `net-tools`**, because
  EL6 has no standalone `hostname` package (the command ships in `net-tools`).
  EPEL 6 is EOL and Oracle hosts none, so in finalize (C) **conditionally**
  enables the clean-core's NSS dynamic CA trust — it is a workaround for the
  Claude build **sandbox**, whose egress proxy presents an intercepting (MITM)
  certificate, so it runs **only in the sandbox** (auto-detected via `IS_SANDBOX`
  or the egress-gateway CA on the build host; override `CLEANCORE_CATRUST=on|off`)
  and is **skipped on a real host** (physical / VM), where the clean-core's
  shipped `ca-certificates` bundle already verifies standard public CAs (EPEL or
  the OL6 base on `yum.oracle.com`). The matching self-test row asserts in the
  sandbox and SKIPs off it. Then (B) fetches the EPEL 6 release RPM from the
  Fedora community archive with its own `curl` and
  installs it with its own `rpm` (EL6 `yum` cannot fetch a direct https package
  URL), and the repo is repointed to the archive and shipped `enabled=0`. EL6 is
  upstart, so `systemd` does not apply.
- **Reference + SBOM artifacts.** The official slim image each clean-core derives
  from is documented (sources, pinned commit, name+version manifest) in
  `tests/cleancore/REFERENCE-oracle-official-images.md`. Each finalized
  clean-core's own package set is recorded names-only, as a reusable JSON SBOM,
  in `tests/cleancore/cleancore-ol<MAJOR>.sbom.json`. Both are **static
  snapshots** (not `.sh`, so outside B-T1/B-T2; not drift-checked gates),
  refreshed by hand when the package set changes.

### Test integration

- **Not a `run-all.sh` tier.** `tests/run-all.sh` discovers tiers via
  `t[0-9]*.sh`; the clean-core builders do not match and are never executed by
  the runner.
- **Covered by B-T1 / B-T2.** Both tiers walk **every** `.sh` in the project, so
  each builder is parse-checked (`bash -n`) and lint-checked (`shellcheck -S
  style`) like any other script. Each builder carries the usual single-code,
  single-statement inline exemptions with a rationale (`SC2086` on the `mknod`
  word-split; `SC2016` on literal `yum`-variable text).
- **Self-test.** Each builder runs an unconditional self-test section (userland
  executes, rpmdb readable, firmware excluded, machine-id / host keys cleared,
  OCI variables rewritten, valid `.tar.gz`, ...) plus a network-gated readiness
  probe that **SKIPs** (never fails the build) when offline.

---

---

## B.9 ENA self-build test matrix (`tests/ena/`)

`tests/ena/` holds the ENA driver **self-build test matrix** — a developer / CI
tool that proves the pinned-or-arbitrary ENA driver actually compiles across an
**OS major × ENA version × kernel** grid, and records the evidence so re-runs
skip what is already known. Like the clean-core base (B.8) it is **developer /
CI-side tooling**, **not** part of the AMI pipeline, and **not** run by
`tests/run-all.sh`. Two self-contained scripts (inline helpers, no shared
library — the user-run-script policy):

`list-ena-releases.sh` collects the upstream ENA version list (the
`ena_linux_<ver>` git tags read via `git ls-remote --tags`, not the rate-limited
REST API) into the deterministic snapshot `ena-driver-releases.json`, each
version pre-checked for tarball fetchability (`tarball_available` +
`tarball_http_status`, via the inline reuse-by-copy `url_check_status`). This is
the matrix **input**.

`run-ena-buildtest-matrix.sh` drives, for each target OL major (6/7/8 — where
`ENA_BUILDTEST` is wired) and each target ENA version, the existing pieces **as
separate executables**: `tests/cleancore/build-cleancore.sh` (B.8) for the
per-OL clean-core rootfs, then `install-ena-driver.sh ENA_BUILDTEST=1` (A.7) for
the per-version compile-test. The ENA version set defaults to the full release
list and is narrowable (`--ena-versions`, `--pinned-only`) so a few cases can run
locally while the **full** matrix is meant for the user's environment / CI.

### Dedup ledger + per-OS reports

Evidence is two layers, **both committed** so the state persists (a commit *is*
the dedup state):

- **`buildtest-ledger.json`** — one entry per `(osmajor, ena_version, kver)`
  carrying `status` (`ok`/`fail`), `dkms`, `ko`, `ko_version`, `reason`,
  `tested_at`. The triple is the **dedup key**, with **kver primary**: a combo
  already present (pass **or** fail) is skipped; a **new kernel** (kver changes)
  shares no key with the old rows so the whole set re-tests; a **new ENA
  release** is the only missing key so only the diff tests. The live kver per OL
  is taken from the build **result** — the first build of a run establishes it,
  so the pinned version is tried first as the per-run canary (one build per OL
  per run re-confirms the live kver rather than trusting a possibly-stale probe).
- **`RESULTS-ol<N>.md`** — a per-OS human report regenerated from the ledger,
  **newest kernel first**; each kernel is a section with an `ok`/total headline
  and a per-version table. A `fail` is recorded evidence (e.g. an ENA release too
  old for that kernel's kcompat), **not** a harness error, so the run exits 0;
  the harness fails non-zero only on an infrastructure error (missing tool, a
  clean-core build that will not produce a rootfs, ...).

A container is kernel-less, so `ENA_BUILDTEST` provisions a full `kernel-uek` +
headers up front (A.7); the matrix inherits that and the B.8 host requirements
(root + `unshare`/`chroot` + network). The committed ledger / `RESULTS-ol6.md`
are an in-environment **sample** (OL6: `2.9.1` ok, `2.2.0` fail on UEK4
`4.1.12-124.48.6.el6uek`); a full run grows the ledger as a clean append.

---

# Part C — Quality Gates & Validation Checklist

Before any commit to this directory, all of the following must pass.

### Static checks

- [ ] `bash -n build-ol-aws-ami.sh` → 0 errors (parse-only check)
- [ ] `bash -n setup-vmimport-role.sh` → 0 errors
- [ ] `bash tests/run-all.sh` → all tiers pass. Includes **B-T2 ShellCheck at the canonical `-S style`** (the strictest level) over every `.sh`, via the checked-in `.shellcheckrc`; the only exemptions are three documented inline `# shellcheck disable=`/`source=` directives (no rule is disabled globally). See TESTING.md.
- [ ] The `tests/cleancore/` clean-core builders (B.8) parse (`bash -n`) and lint (`shellcheck -S style`) cleanly — they are covered by B-T1/B-T2 (every `.sh`), though not executed by `run-all.sh`
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
- [ ] Phase 6 Nitro readiness pre-check (`NITRO_PRECHECK`, default `enforce`) runs after the VMDK is produced: it `die`s on a blocking finding (NVMe host / ENA / fstab / bootloader) before the upload phases, is fail-open when inspection tools are absent, and is suppressible via `warn`/`off` (see A.7). Verified against a known-good image (e.g. OL10 PASS)

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

**Symptom**: Phase 8 could hang indefinitely if
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

## D.11 OL6/UEKR4 and OL7/UEKR6 have no `kernel-uek-modules` package

**Symptom**: When the upstream `cloud/aws/provision.sh`'s
`cloud::install_aws_packages()` runs on OL6 or OL7 with `KERNEL=uek`, the
line `yum install -y "${YUM_VERBOSE}" kernel-uek-modules` fails — on OL6 with
`No package kernel-uek-modules available`, and on OL7 with `Error: Nothing to
do` — which aborts `provision.sh` and therefore the whole Phase 5 build.

**Root cause**: The separate `kernel-uek-modules` *split-out modules package*
was introduced in **UEK R7 (OL8+)**, not earlier. UEK before R7 — OL6's UEKR4
(`4.1.12-124.x`) and OL7's UEKR6 (`5.4.17-...el7uek`) — ships a single
`kernel-uek` RPM with all driver `.ko` files (including `ena.ko`, `nvme.ko`,
`nvme-core.ko`, `virtio*.ko`, `xen-*.ko`, `hv_*.ko`) bundled directly inside
it; no `kernel-uek-modules` package exists in those repos. Verified: the
`ol6_UEKR4` repodata has no `kernel-uek-modules-*` entries, and the
`ol7_UEKR6` `kernel-uek-5.4.17-...el7uek` RPM contains
`lib/modules/<ver>/kernel/drivers/net/ethernet/amazon/ena/` directly. So the
install both *fails* (no such package) and is *unnecessary* (ena.ko is already
present from `kernel-uek`).

> An earlier version of this fix guarded the line on `ORACLE_RELEASE >= 7`,
> on the mistaken belief that the split landed in OL7/UEK6. OL7 then hit the
> same failure. The correct boundary is **>= 8** (UEK R7 / OL8+).

**Fix**: `phase3_clone_repository` applies, for OL6 **and** OL7, a runtime
patch on top of the shared `image-scripts.sh` patch, rewriting the offending
line to be conditional on `ORACLE_RELEASE >= 8`:

```bash
# [ol-aws-ami-builder PATCH kernel-uek-modules] separate kernel-uek-modules exists only from UEK R7 (OL8+); UEKR4/UEKR6 (OL6/OL7) bundle modules (incl. amazon/ena) in kernel-uek
[[ "${ORACLE_RELEASE}" -ge 8 ]] && yum install -y "${YUM_VERBOSE}" kernel-uek-modules
```

The `&&` short-circuit makes the line a no-op on OL6/OL7 while preserving the
original semantics for OL8+. The patch is applied only for OL6/OL7 builds; the
OL8+ build path is left untouched (upstream installs `kernel-uek-modules`
there as before).

**Guard rails**:

1. A `grep -Fq '[ol-aws-ami-builder PATCH kernel-uek-modules]'` precedes the
   substitution for idempotency.
2. A `grep -Fq 'yum install -y "${YUM_VERBOSE}" kernel-uek-modules'` verifies
   the original line is still present (if upstream removes it, the patch is
   skipped with a `log_warn`).
3. Post-substitution, the marker grep `die`s the script if the patch silently
   failed to apply.

**Verification**: ENA / NVMe driver availability on the produced AMI is
confirmed by `lsmod | grep -E '^(ena|nvme)'` after first boot, plus
`modinfo ena nvme nvme_core` to inspect the kernel module metadata. The OL7
`ena.ko`-in-`kernel-uek` presence was confirmed directly from the `ol7_UEKR6`
RPM contents.

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

## D.16 OL6 root filesystem must be ext4 (anaconda-13 refuses an XFS root)

**Symptom**: With the OL6 env template set to `ROOT_FS="xfs"` (to align
with OL7/8/9/10), the build reached Phase 5, the VM booted the installer,
ran for ~28 seconds, then powered off with **zero** bytes written to the
target disk and no AMI produced. Under the headless default the serial
console was blank, so the failure looked like an early hang.

**Root cause**: The OL6.10 installer (**anaconda-13.21**) categorically
refuses to place the **root** partition on XFS. Captured on the serial
console of a bare `virt-install` reproduction (text mode), the installer
prints, at the partitioning step, a message to the effect that placing the
root partition on an XFS filesystem is not supported on Oracle Linux
Server, then reboots. This is an **installer policy** decision, not a
missing package and not a kernel limitation: UEK4 (kernel 4.1.12) mounts
XFS fine at runtime; anaconda-13 simply will not *create* an XFS root
during installation. (Newer anaconda on OL7+ does support it, which is why
the OL7/8/9/10 templates keep `xfs`.)

**Why static checks missed it**: `part / --fstype=xfs` is *syntactically*
valid for RHEL6, so `ksvalidator -v RHEL6` passes it (see D.18). Only a
live install surfaces the policy refusal.

**Fix**: OL6 root is **ext4-only**.

1. `env.properties.aws-ol6` sets `ROOT_FS="ext4"` (with the rationale
   inline).
2. `distr::validate()` rejects anything other than `ext4` for OL6 during
   **preflight** (before any ISO download), with a clear error pointing
   here.
3. The previous `distr::kickstart` step that rewrote the root partition
   `ext4`→`xfs` when `ROOT_FS=xfs` has been **removed**: it only ever
   produced an install-failing config. The embedded kickstart template
   already declares both `/boot` and `/` as ext4, so no rewrite is needed.

**Verification (live)**: A bare `virt-install` against the OL6.10 DVD with
the wrapper-synthesized kickstart was run twice on the build host:

1. Root = **xfs** → installer refuses at partitioning ("root on XFS not
   supported") and reboots; no disk writes. **Reproduces the failure.**
2. Root = **ext4** → installer creates ext4 filesystems on `/dev/sda1`
   (`/boot`) and `/dev/sda2` (`/`), resolves the OL Server + UEK4 repos,
   and proceeds through the full 217-package set (including
   `linux-firmware` per D.13, `iptables` per D.18, and
   `kernel-uek-4.1.12-124.16.4.el6uek` per D.12). **Confirms ext4 is the
   only viable OL6 root.**

---

## D.17 Phase 5 SELinux relabel fails on a non-SELinux build host

**Symptom**: On a Debian / Ubuntu build host (observed on Ubuntu 26.04,
`DISTR=ol10-slim`, `SELINUX=enforcing`), Phase 5 aborts inside upstream
`bin/build-image.sh` at the non-root filesystem relabel step:

```
build-ol-aws-ami.sh: SELinux relabel non-root filesystems
    relabelling /boot
libguestfs: error: selinux_relabel: feature 'selinuxrelabel' is not available in this build of libguestfs
2026-06-08 07:36:38 [ERROR] build-image.sh failed
```

Upstream relabels each non-root mount with
`guestfish --remote selinux-relabel <file_contexts> <mount>`, which needs
the host `libguestfs` to provide the `selinuxrelabel` optgroup.

**Root cause**: The `selinuxrelabel` optgroup is a **build-time** capability of
the libguestfs daemon (`guestfsd`), gated by `HAVE_LIBSELINUX` when libguestfs
itself is compiled. The Debian / Ubuntu libguestfs packages are built **without
it**, so the optgroup is permanently unavailable in the appliance regardless of
what is installed on the host. It is **not** a runtime probe for `setfiles`.

This was confirmed empirically: installing `policycoreutils` + `selinux-utils`
(so `/usr/sbin/setfiles` exists) and rebuilding the supermin appliance
(`libguestfs-test-tool` finishing OK) did **not** enable it —

```
$ command -v setfiles          # -> /usr/sbin/setfiles  (present)
$ LIBGUESTFS_BACKEND=direct guestfish -a /dev/null run : available selinuxrelabel
libguestfs: error: selinuxrelabel: group not available   # exit 1, still
```

So adding host SELinux packages is a dead end; the only fix is to avoid the
host-side relabel when the optgroup is absent.

**Fix**: `phase3_clone_repository` patches upstream `bin/build-image.sh` (the
same clone-local, re-applied-every-clone discipline as the OL6/7 patches in
D.10/D.11, but host-OS- and OL-version-**independent**). It probes the optgroup
with a **standalone** `guestfish` (no `--selinux`, no `--listen`); when the
optgroup is unavailable it touches `/.autorelabel` with **another standalone**
`guestfish` session and skips the entire upstream relabel block — the
`eval ... --selinux --listen` **and** the per-filesystem loop:

```bash
common::echo_message "SELinux relabel non-root filesystems"
if ! guestfish -a /dev/null run : available selinuxrelabel >/dev/null 2>&1; then
  common::echo_message "    [ol-aws-ami-builder PATCH selinux-relabel-fallback] ..."
  guestfish --rw -a "${WORKSPACE}/${VM_NAME}/${VM_NAME}.qcow2" -i touch /.autorelabel
else
  eval "$(guestfish -a ... --selinux --listen)"   # original block, unchanged
  # ... mountpoints loop ...
  guestfish --remote quit
fi
```

A `SELINUX!=disabled` guest carrying `/.autorelabel` relabels every filesystem
on first boot (systemd `selinux-autorelabel` on OL7/8/9/10; `rc.sysinit` on
OL6) using the guest's own `setfiles` / targeted policy, then reboots once —
yielding a correctly-labelled `enforcing` image. This is the
libguestfs-recommended fallback (the same one `virt-customize` / `virt-sysprep`
`--selinux-relabel` use internally; virt-sysprep's earlier `[ x.x ] SELinux
relabelling` step takes the same fallback, so `/.autorelabel` is typically
already present — the explicit touch makes it certain). On SELinux-capable
hosts (RHEL / OL / Fedora) the optgroup **is** available, the probe passes, and
the original host-side relabel runs unchanged — so the patch is applied
unconditionally and is a no-op there. See A.5 "Caller pattern for libguestfs"
and B.6.

> **Why standalone sessions (lesson from the first attempt)**: the initial fix
> reused upstream's `--selinux --listen` daemon — it probed with `guestfish
> --remote available selinuxrelabel` and touched `/.autorelabel` over the same
> `--remote` session. On an optgroup-less host that **fails**: the
> `--selinux --listen` daemon is torn down as soon as the missing group is
> exercised, so the socket disappears and the follow-up `guestfish --remote
> touch /.autorelabel` dies with `looks like the server is not running`, which
> `set -e` turns into a build abort. The corrected fix never enters the
> `--selinux --listen` path on such hosts: it probes and writes with
> self-contained `guestfish -a ...` invocations only. The probe form
> `guestfish -a /dev/null run : available selinuxrelabel` is the exact one-shot
> used to diagnose the root cause (it returns a clean non-zero, "group not
> available", without disturbing any session).

**Verification**: A static + behavioral check confirmed:

1. The two `sed` edits, replayed on a fresh upstream `bin/build-image.sh`,
   produce the expected clean `if/else` and pass `bash -n`; `shellcheck
   --severity=style` on the wrapper is clean.
2. The probe sits in an `if !` position, so the upstream script's
   `set -euo pipefail` does not abort on the (expected) non-zero exit. A
   stubbed-`guestfish` harness verified both branches under `set -e`:
   optgroup-absent -> no abort, the `--selinux --listen` daemon is **never
   started**, `/.autorelabel` is touched via a standalone session, host relabel
   skipped; optgroup-present -> behaviour unchanged, `--listen` started, host
   relabel runs, no `/.autorelabel`.
3. The patch is idempotent (grep-guarded by the
   `[ol-aws-ami-builder PATCH selinux-relabel-fallback]` marker) and degrades
   to a logged no-op if upstream refactors the relabel block.

**Caveat**: The autorelabel fallback adds one relabel pass plus a single reboot
to the guest's **first** boot (a one-time cost; subsequent boots are normal).
The guest must contain its own `setfiles` / `fixfiles` and targeted policy —
true for the OL base in every supported OL6-10 target. This path is exercised
when building on apt-family hosts; full end-to-end (Phase C) confirmation that
the first-boot relabel completes and the AMI comes up `enforcing` should be
performed by operators building on Debian / Ubuntu.

## D.18 OL7-syntax directives leaking into the OL6 (anaconda-13) kickstart

**Symptom.** An OL6 build hangs in Phase 5 at "Install Oracle Linux": the
domain runs but makes no progress (`virsh domstats` shows idle vCPUs and
`block.*.wr.bytes=0` — *zero* writes to the target disk), and `virsh console`
is blank. The installer booted (the ISO stage2 is read) but never partitions or
writes anything, then the 30-minute headless wait elapses.

**Root cause.** The OL6 kickstart is *synthesized* by this wrapper as a mirror
of upstream's `ol7-ks.cfg` (upstream ships no `distr/ol6-slim`; see B.4). OL7
ships anaconda-19+, but OL6 ships **anaconda-13**, whose kickstart command set
is older. Directives that are valid only on the newer anaconda are a
**parse-time error** on anaconda-13 — and anaconda fails *before* any
partitioning/write. Under the default headless install (`SERIAL_CONSOLE=no`)
that error is rendered on tty1, not visible over the serial line, so the only
observable effect is the silent wait. This is a *class* of bug: any
"OL7-ism" that survives the mirror can reappear.

**Authoritative evidence.** Validate the synthesized kickstart with
[`pykickstart`](https://pykickstart.readthedocs.io/)'s RHEL6 command set
(`ksvalidator -v RHEL6`). On the pre-fix kickstart it reports exactly two
syntax errors:

| Directive (pre-fix) | RHEL6 / anaconda-13 verdict | Fix |
|---|---|---|
| `bootloader … --boot-drive=sda` | **invalid** — `--boot-drive` is RHEL7+/anaconda-19+ ("unrecognized arguments") | drop `--boot-drive` (the disk is already pinned by `ignoredisk --only-use=sda`) |
| `rootpw --lock` (bare) | **invalid** — RHEL6 requires a password argument ("a single argument is expected") | `rootpw --lock --iscrypted '*'` (locked, no valid password) |

A third defect is **not** a syntax error and is therefore *not* caught by
`ksvalidator` — it is a runtime package-selection failure:

| Item | OL6 reality | Fix |
|---|---|---|
| `iptables-services` in `%packages` | RHEL7+ package; **absent on OL6** (only `iptables` ships, e.g. `iptables-1.4.7-19.0.1.el6`, which itself provides the service) | remove the line; keep `iptables` |

**Hypotheses the tool cleared (recorded so they are not "re-fixed").** An
initial web-based reading suspected `timezone … --isUtc`, `part … --label=…`,
and `cmdline`. `ksvalidator -v RHEL6` accepts **all three** — they are valid on
anaconda-13 and were left unchanged. Lesson: validate against the target
release's actual command set, not against examples from a newer release.

**The `xfs` root caveat (separate, runtime) — now confirmed unsupported.**
`part / --fstype=xfs` is *syntactically* valid on RHEL6, so `ksvalidator`
passes it, but whether anaconda-13 can actually *create* an xfs root is a
runtime question this tool cannot answer. A live `virt-install` settled it:
anaconda-13 **refuses** an XFS root on OL6 and aborts at partitioning. OL6 is
therefore pinned to `ROOT_FS=ext4`, enforced at preflight (cross-ref D.16 for
the evidence and the fix). This entry stays as the canonical example of a
runtime failure that syntax validation cannot catch.

**Prevention.**
1. `tests/validate-kickstart.sh` runs `ksvalidator -v RHEL6` on the synthesized
   OL6 kickstart (see `TESTING.md`); it catches the *syntax* class above. This
   is the primary safeguard — a parse error is caught statically, before a
   build is ever launched.
2. For a *runtime* failure that syntax validation cannot see, reproduce the
   install in isolation with a bare `virt-install` (text mode, explicit
   `console=ttyS0`) where the installer output is fully visible — this is how
   the xfs-root refusal above was pinned. `SERIAL_CONSOLE=yes` can also stream
   the OL6/7 install live, but it is a **debug-only opt-in**: it makes upstream
   wait on `virsh console`, which may not return when the install VM ends and
   can hang `build-image.sh` until the watchdog (default reverted to `no` — see
   A.7).
3. The Phase-5 `BUILD_TIMEOUT_MIN` watchdog is an outer safety bound on the
   build (in addition to upstream's own install timeout, which applies under the
   default `SERIAL_CONSOLE=no`); on expiry it reaps the transient build VM.

Runtime issues that syntax validation cannot see (xfs-root support, package
availability) are still confirmed only by a live build.

---

## D.19 OL6 (bash 4.1) chokes on `declare -g` in upstream `env.properties.defaults`

**Symptom.** On OL6 the install completes, then Phase 5 fails during the
provisioning step with:

```
=== Load environment ===
/tmp/provision.d/env.properties: line 69: declare: -g: invalid option
declare: usage: declare [-aAfFilrtux] [-p] [name[=value] ...]
virt-customize: error: /bin/bash /tmp/provision.d/provision.sh: command exited with an error
```

`build-image.sh` then exits 1. OL7/OL8/OL9/OL10 are unaffected.

**Cause.** Upstream `env.properties.defaults` ends with `declare -gA REPO`. The
`-g` (declare-as-global) flag was introduced in **bash 4.2**. That file is
`ENV_FILE_DEFAULTS`, the head of `build-image.sh`'s `ENV_FILES`, so `stage_files`
concatenates it **first** into the in-guest `provision.d/env.properties`, which
`provision.sh` sources **inside the guest**. OL6 ships **bash 4.1**, which does
not understand `-g`. The newer guests do (OL7 = 4.2, OL8 = 4.4, OL10 = 5.x), so
the defect is OL6-specific. The install itself is fine; only the guest-side env
sourcing aborts.

**Fix.** A Phase-3 patch (OL6 only, same discipline as D.11) rewrites the line to:

```
declare -gA REPO 2>/dev/null || declare -A REPO
```

On the host (bash 5.x, where the file is sourced inside a `build-image.sh`
function) the first form succeeds and `REPO` remains a global associative array
exactly as upstream intends. In the OL6 guest the first form fails quietly and
the `declare -A` fallback runs; `REPO` is not consumed by guest provisioning, so
its scope there is immaterial — the only goal is that sourcing no longer aborts.
`A || B` does not trip `set -e`. The patch is grep-guarded for idempotency and
keeps a `.declare-g-guard.bak` backup.

**Prevention.** This is a host-bash-version vs guest-bash-version skew that
static checks on the wrapper cannot see (the offending line lives in upstream
content fetched at build time). The guard is re-applied on every clone; if a
future upstream refactor drops or moves `declare -gA REPO`, the patch becomes a
logged no-op rather than a hard failure. Subsequent OL6 provisioning steps may
surface further bash-4.1 incompatibilities, which are addressed as they appear.

---

## D.20 OL6 Cleanup fails: `virt-sysprep --truncate /etc/machine-id` (no systemd)

**Symptom.** With the D.19 fix in place an OL6 build now installs and provisions
successfully (SELinux relabel, "Finishing off"), then aborts in the upstream
**Cleanup** stage:

```
[   2.9] Performing "customize" ...
[   2.9] Truncating: /etc/machine-id
virt-sysprep: error: libguestfs error: truncate: open: /etc/machine-id: No such file or directory
-> build-image.sh failed (exit 1)
```

**Cause.** Upstream `build-image.sh::image_cleanup()` runs, unconditionally:

```
virt-sysprep --delete "${BUILD_INFO}" \
  --truncate /etc/machine-id \
  --truncate /etc/resolv.conf \
  -a .../VM.qcow2 "${virt_sysprep_args[@]}"
```

`/etc/machine-id` is a **systemd** artifact. OL6 uses Upstart and has no
`/etc/machine-id`, so `--truncate` (which opens the file) fails and aborts the
build. OL7+ ship systemd, so the file exists and the truncate succeeds — the
defect is OL6-specific. The `cloud::sysprep_args` hook only *appends* arguments,
so the hardcoded `--truncate` cannot be removed without patching `build-image.sh`
itself. (The fact that OL7+ succeed also proves virt-sysprep's built-in
`machine-id` operation *empties* the file rather than removing it — otherwise the
subsequent `--truncate` would fail there too.)

**Fix.** Create an empty `/etc/machine-id` in the OL6 guest in the synthesized
`distr/ol6-slim/ol6-ks.cfg` `%post` (`: > /etc/machine-id`), so OL6 reaches the
same on-disk state OL7+ are already in when `virt-sysprep` runs. This is
upstream-agnostic (no patch to `build-image.sh`) and harmless: an empty
`/etc/machine-id` is the standard "regenerate on first boot" marker. `%post` also
creates `/etc/resolv.conf` if absent (the next `--truncate` target) as a
defensive measure.

**Prevention.** This is another systemd-vs-Upstart skew (cf. D.19) that wrapper
static checks cannot see, because the failing command lives in upstream content
run at build time. The `%post` lines are part of the wrapper-synthesized OL6
kickstart, so they travel with every build.

---

## D.21 OL7 Phase 6 CHECK 1 false `FAIL` when the dracut initramfs is unreadable on the host

**Symptom.** An OL7 build produces a good VMDK, but the Phase 6 NVMe check fails
even though nvme.ko is present, aborting before the upload phases:

```
[CHECK 1] NVMe host driver: FAIL (not built-in and not in the initramfs ...)
```

while the equivalent OL6 build passes CHECK 1 with "module present in the
initramfs".

**Cause.** CHECK 1 confirms nvme.ko is in the kernel's initramfs by extracting
it on the **build host** (Ubuntu) with `unmkinitramfs`. dracut initramfs images
differ by compression (gzip/xz/zstd/lz4) and may prepend an uncompressed
microcode cpio; the OL6 image happened to be readable by the host's
`unmkinitramfs` while the OL7 (UEK R6, 5.4) image was not. The original logic
treated "initramfs file found but yielded no nvme.ko" as a hard `FAIL`, so an
inability to *read* the archive on the host was indistinguishable from the
driver being genuinely absent — a false negative, since a cloud (generic)
initramfs does include nvme.

**Fix.** CHECK 1 now tries several listing methods (`unmkinitramfs`, then
`lsinitrd`/`lsinitramfs`, then a manual decompress + `cpio -t`) and tracks
whether *any* of them could read the archive. When nvme.ko exists in the on-disk
module tree but no method can read the initramfs on the host, CHECK 1 reports
`INDETERMINATE` (fail-open: warn + continue) instead of `FAIL`. A hard `FAIL` is
reserved for nvme.ko being absent from both the kernel and an inspectable
initramfs. See A.7.

**Prevention.** Detection robustness only; it does not change the produced image.
If CHECK 1 is `INDETERMINATE`, confirm the AMI boots on a Nitro instance (the
generic cloud initramfs normally includes nvme); the ENA self-build's `dracut -f`
also regenerates the initramfs for the target kernel.

---

## D.22 OL7 initramfs omits nvme (hostonly dracut) -> not bootable on Nitro

**Symptom.** A clean OL7 build (even a `--skip-ena-driver` "pure" build) produces
a good VMDK but Phase 6 CHECK 1 FAILs:

```
[CHECK 1] NVMe host driver: FAIL (not built-in and not in an inspectable initramfs ...)
```

and a host-side inspection confirms `nvme.ko` is present on disk
(`/lib/modules/<kver>/kernel/drivers/nvme/host/nvme.ko.xz`) but **absent from the
initramfs** (e.g. `unmkinitramfs` extracts ~110 modules, none of them nvme).

**Cause.** Unlike D.21 (a host-side *inspection* gap), this is a genuine
omission. The image is installed in a VM whose root disk is virtio
(`/dev/sda`), and dracut runs in **hostonly** mode, so it only includes drivers
for devices present at build time — nvme is not among them. On a real Nitro
instance the root is NVMe-backed, so the initramfs cannot find root and the
instance fails to boot. (OL6's UEK4 initramfs happened to include nvme, so OL6
passed; OL7's UEK R6 hostonly initramfs did not.) CHECK 1's FAIL is therefore a
true positive, not a false negative.

**Fix.** Phase 3 appends an always-on hook to `cloud/aws/provision.sh` (it runs
even with `--skip-ena-driver`, because booting on Nitro is not optional) that
writes `/etc/dracut.conf.d/02-ol-aws-nitro.conf` with
`add_drivers+=" nvme nvme-core ena "` and regenerates the initramfs for the
installed kernel with `dracut -f`. The drop-in also makes future in-instance
kernel updates keep nvme/ena. See A.7 ("Nitro initramfs drivers").

**Prevention.** The hook targets the highest UEK under `/lib/modules` (not the
appliance `uname -r`) and is idempotent and best-effort; CHECK 1 then verifies
that nvme is in the regenerated initramfs.

---

## D.23 Phase 6 CHECK 2 false `FAIL` when the ENA self-build moves `ena.ko` out of `/kernel`

**Symptom.** A default OL7 build (ENA self-build ON) produces a good VMDK whose
guest carries a freshly built ENA driver, yet Phase 6 reports:

```
[CHECK 2] ENA driver: FAIL (no ENA driver -- Nitro requires ENA for networking)
```

A host-side inspection then shows `ena.ko` **is** present on disk, but under
`/lib/modules/<kver>/extra/` rather than the stock
`/lib/modules/<kver>/kernel/drivers/net/ethernet/amazon/ena/`.

**Cause.** The Phase 6 module inventory listed only the `/kernel` subtree
(`virt-ls -R /lib/modules/<kver>/kernel`). DKMS — which the in-guest ENA
self-build (D + A.7) uses — installs the built module into `/extra` (or
`/updates/dkms`) and depmod ranks those **above** `/kernel`, so the self-built
driver is exactly the one the running kernel loads. Because the scan stopped at
`/kernel`, CHECK 2's `ena.ko` match (and the assurance report's `modinfo`
copy-out, which hardcoded a `/kernel` path prefix) missed it entirely. The
earlier `--skip-ena-driver` builds passed only because the stock `ena.ko`
stayed in `/kernel`. CHECK 1 was unaffected because `nvme.ko` is never
relocated by DKMS.

**Fix.** Phase 6 now scans the **full** `/lib/modules/<kver>` tree
(`/kernel` + `/extra` + `/updates`) and selects the *effective* `ena.ko` by
depmod precedence (`updates` > `extra` > `kernel`). The assurance report's
`modinfo` copy-out prepends `/lib/modules/<kver>` (the real base of the matched
relative path) instead of a fixed `/kernel`. The check is **feature-aware and
OL-version-independent**: it finds the driver whether it is stock in-tree or
DKMS-built, on any OL. The report also annotates the driver **provenance**
(`stock in-tree /kernel` vs `self-built, DKMS /extra|/updates`) so an operator
can confirm the self-build took effect and that CHECK 1-4 still pass (no
boot-readiness regression). See A.7 ("Nitro initramfs drivers" / ENA self-build).

---

## D.24 OL6 `sshd` refuses to start: `PermitRootLogin prohibit-password` invalid on OpenSSH 5.3

**Symptom.** A freshly built OL6 AMI boots, gets a network address and answers
ping, but every SSH attempt is met with `Connection refused`. The instance
console shows host keys being generated normally and then:

```
Starting sshd: [FAILED]
```

i.e. nothing is listening on port 22. It is **not** a key-pair, security-group,
or IMDS problem — sshd itself never started.

**Cause.** The wrapper applies a root-login policy to `sshd_config` from the
upstream `PERMIT_ROOT_LOGIN` env property, whose modern default is
`prohibit-password`. That token was introduced in **OpenSSH 6.7**. OL6 ships
**OpenSSH 5.3**, whose config parser accepts only
`yes | no | without-password | forced-commands-only` and treats any other value
as a **fatal** parse error, so sshd exits at startup. `prohibit-password` is in
fact just the modern alias for `without-password` (identical behavior: key-based
root login allowed, password root login denied), so OL6 was being handed a
semantically-correct policy in syntax its sshd could not parse. OL7+ are
unaffected (OpenSSH 7.4p1 accepts the modern token).

**Fix.** In the OL6-only synthesized `provision.sh` (`distr::common_cfg`), the
policy value is lowercased and `prohibit-password` is mapped back to
`without-password` before the `sshd_config` substitution, giving OL6 the
identical policy in 5.3-valid syntax. OL7+ keep the modern value via their own
upstream path (per-OS isolation — an OL6 fix cannot regress OL7-10).

**Prevention (build-time gate + audit).** After editing `sshd_config`, the OL6
provision step now runs `sshd -t -f /etc/ssh/sshd_config` (with an ephemeral
`-h` host key so the test is independent of whether real host keys exist yet)
and **aborts the build** on any parse error. This converts the entire class of
"a modern directive/value leaked into OL6's OpenSSH 5.3 config" from a silent
first-boot `Connection refused` into a loud, deterministic build-time failure.
This is one instance of the broader **OL6-vs-modern compatibility audit**: any
config synthesized by the wrapper and consumed by an OL6 (bash 4.1 / anaconda-13
/ OpenSSH 5.3 / Upstart) toolchain must be validated against the *older*
tool's accepted syntax, not the build host's modern tool (cf. D.18, D.19, D.20).

---

## D.25 AWS `Get System Log` is empty: serial console (`ttyS0`) missing from the kernel cmdline

**Symptom.** A built AMI boots and is reachable, but the EC2 console
(`Get System Log` / `get-console-output`) shows nothing — no kernel ring buffer,
no boot messages. This is what made the OL6 SSH failure (D.24) so painful to
diagnose: with no console output there was no way to see *why* the instance was
unhealthy.

**Cause.** AWS captures only what the guest writes to the serial port `ttyS0`,
and the interactive EC2 Serial Console additionally needs GRUB and a login getty
on that port. Three historical gaps:
- **OL6** — the synthesized kickstart set the kernel cmdline to `console=tty0`
  only, and a `%post` line then actively **stripped** any `console=ttyS0` from
  `/boot/grub/grub.conf`. Net: VGA console only.
- **OL7** — the upstream `GRUB_CMDLINE_LINUX` carries `console=tty0` but not
  `console=ttyS0`, and the wrapper never added it.
- **OL8/9/10 (BLS)** — *discovered in the OL6–OL10 E2E run.* OL8+ enable the GRUB
  BootLoaderSpec (`GRUB_ENABLE_BLSCFG=true`): the kernel cmdline lives in
  `/boot/loader/entries/*.conf` (`options` line), **not** in `grub.cfg`
  menuentries. A plain `grub2-mkconfig` does **not** rewrite existing BLS
  entries' `options` from `GRUB_CMDLINE_LINUX`, so the OL7-era hook (which only
  edited `GRUB_CMDLINE_LINUX` + ran `grub2-mkconfig`) left OL8/9/10 booting
  without `ttyS0` — CHECK 5 reported ADVISORY on all three. AWS's own RHEL
  guidance confirms the trap: it uses `grub2-mkconfig … --update-bls-cmdline` on
  8.x/9.0–9.1 but plain `grub2-mkconfig` on 9.2+ (a version-dependent flag).

**Fix — AWS-recommended serial console, three layers, per-OS isolated.** The
wrapper now applies the full AWS-recommended serial-console config in three
layers, each via its OS-appropriate mechanism so one tier cannot regress another:

1. **Kernel cmdline** `console=tty0 console=ttyS0,115200n8` on *every* boot entry
   (`ttyS0` last → it becomes the effective `/dev/console`, driving both
   `Get System Log` and the serial getty).
   - **OL6 (GRUB Legacy)** — idempotent kickstart `%post` append in
     `/boot/grub/grub.conf` (unchanged; already green).
   - **OL7–10 (GRUB2)** — `grubby --update-kernel=ALL --args="console=tty0
     console=ttyS0,115200n8"` updates **existing** entries directly: BLS-aware
     (rewrites `/boot/loader/entries/*.conf` on OL8+) and version-stable across
     OL7–10, so the `--update-bls-cmdline` version matrix is avoided entirely.
     `GRUB_CMDLINE_LINUX` is also set so **future** kernel installs inherit it.
2. **GRUB-over-serial** (so the interactive EC2 Serial Console reaches the GRUB
   menu/prompt):
   - **OL6** — `serial --unit=0 --speed=115200` + `terminal --timeout=10 serial
     console` in `grub.conf`'s global section. (The `terminal` timeout adds a
     small menu-selection wait on a headless boot — acceptable for OL6, which is
     verification/legacy only.)
   - **OL7–10** — `GRUB_TERMINAL="console serial"` + `GRUB_SERIAL_COMMAND="serial
     --speed=115200"` in `/etc/default/grub` (dropping any `GRUB_TERMINAL_OUTPUT`),
     then `grub2-mkconfig`.
3. **Serial getty** (login prompt on `ttyS0`):
   - **OL7–10** — `systemctl enable serial-getty@ttyS0.service` (with a symlink
     fallback for the offline virt-customize context). systemd auto-spawns it from
     `console=ttyS0`, but it is enabled explicitly for determinism.
   - **OL6 (Upstart)** — out of scope (no `serial-getty@` unit); boot-output via
     the cmdline is unaffected.

The OL7–10 layers live in the Phase-3 hook
(`[ol-aws-ami-builder PATCH serial-console]`) injected into
`cloud/aws/provision.sh`, **guarded on `/etc/default/grub`** (GRUB2-only), so it
is a clean no-op on OL6 — the two paths never overlap (per-OS isolation).

**Verification (CHECK 5, advisory) — BLS-aware.** Phase 6 inspects the located
bootloader menuentries (OL6 `grub.conf` `kernel`, OL7 `grub.cfg` `linux16`), the
BLS entries (`/boot/loader/entries/*.conf` `options`), **and** — because on OL8
that `options` line is commonly `$kernelopts` rather than the expanded cmdline —
the `kernelopts` value in `/boot/grub2/grubenv` (falling back to the `grub.cfg`
`set kernelopts=` default). It PASSes if `console=ttyS0` is on the cmdline in any
of these. It remains **advisory** (warn only, never fails the gate): a missing
serial console costs observability, not bootability (one `fail=1` from fatal if
ever wanted). On a launched instance, confirm with: `cat /proc/cmdline`; `sudo
grubby --info=ALL | grep args` (OL7–10); `sudo grub2-editenv list | grep
kernelopts` or `cat /boot/loader/entries/*.conf | grep ^options` (OL8–10); `sudo
grep -E 'serial|terminal' /boot/grub2/grub.cfg`
(OL7–10) or `/boot/grub/grub.conf` (OL6); and `systemctl is-enabled
serial-getty@ttyS0.service` (OL7–10).

---

## D.26 OL6 cloud-init fails to create `ec2-user` (`systemd-journal` group absent) — no SSH

**Symptom.** A launched OL6 AMI is unreachable over SSH (reproducible across
instances). The boot console shows cloud-init 0.7.5 failing:
`Failed to create user ec2-user` → `Running users-groups (cc_users_groups)
failed` → `Applying ssh credentials failed!` (and later
`ssh-authkey-fingerprints failed`). OL7+ are unaffected.

**Cause.** The upstream `cloud/aws` provisioning (`cloud::cloud_init`) writes
`/etc/cloud/cloud.cfg.d/90_ol.cfg` with `system_info.default_user.groups:
[adm, systemd-journal]` and `name: <CLOUD_USER>` (`ec2-user`) for **every** OL
version. cloud-init 0.7.5 merges `cloud.cfg.d` over the main `cloud.cfg` with
the drop-in winning (`read_conf_with_confd` → `mergemanydict([confd, cfg])`,
dict merger `no_replace`, filenames reverse-sorted), so `90_ol.cfg` is the
**effective** `default_user` on OL6 — the name is already `ec2-user`. The defect
is the group: **OL6 has no systemd, so the `systemd-journal` group does not
exist.** At first boot `cc_users_groups` calls `useradd ec2-user --groups
adm,systemd-journal …`, which aborts (`group 'systemd-journal' does not exist`);
the default user is never created, so `cc_ssh` (`setup_user_keys` →
`pwd.getpwnam('ec2-user')`) cannot apply the EC2 metadata key — all three log
failures share this single root cause. OL7-10 ship systemd (the group exists),
which is why the failure surfaced only on OL6's first real launch (Phase C,
B.5.3). *Verified against the `cloud-init-0.7.5-8.el6_9.2` RPM: the stock
`cloud.cfg` `default_user` has only `name: cloud-user` (no `groups`); the group
comes solely from the provision-written `90_ol.cfg`; the merge, `useradd
--groups`, and `cc_ssh` paths are byte-identical to upstream 0.7.5; the RPM
scriptlets create no users.*

> The earlier diagnosis ("logs in as `cloud-user`; name not rewritten on OL6")
> was an **unverified inference** (Phase C had never been run): the effective
> name was always `ec2-user` (`90_ol.cfg` wins the merge), and user creation was
> failing all along.

**Fix (OL6 only).** The Phase-3 hook
(`[ol-aws-ami-builder PATCH ol6-cloud-user]`), injected into
`cloud/aws/provision.sh` **only for OL6 builds** (self-guarded on
`/etc/oracle-release`, idempotent), does two things to `/etc/cloud/cloud.cfg` and
`/etc/cloud/cloud.cfg.d/90_ol.cfg`:

1. **Fix (functional):** strips `systemd-journal` from the `default_user.groups`
   list (scoped to the `groups:` line, any position). The effective `groups`
   becomes `[adm]` (`adm` is a base EL6 group), so `useradd` succeeds and
   `ec2-user` — with the SSH key — is created.
2. **Clarity (no functional effect):** aligns `default_user.name` to
   `CLOUD_USER` (`ec2-user`) in the stock `cloud.cfg` as well. `90_ol.cfg`
   already sets the name and wins the merge (so the account is `ec2-user`
   regardless and `cloud-user` is never instantiated), but the stock `cloud.cfg`
   otherwise still literally reads `name: cloud-user`, which would mislead an
   operator inspecting the built image. This is a verified no-op kept purely for
   config legibility.

**Wiring (timing).** The hook must run *after* `cloud::cloud_init` has installed
cloud-init and written `90_ol.cfg`. `bin/provision.sh` **sources**
`cloud/aws/provision.sh` (executing any top-level statements) during `load_env`,
*before* it calls `cloud::provision` → `cloud::cloud_init`. The hook is therefore
wired by **wrapping** `cloud::cloud_init`: it captures the original definition
(`declare -f`) and redefines the function to call the original and then run the
hook, so the edits fire immediately after the config files are created (late
binding makes `cloud::provision` reach the wrapped function). An earlier revision
appended a top-level `sh …` invocation instead; that executed at *source* time —
before cloud-init was installed and the configs existed — and silently skipped
(`[ol6-cloud-user] no cloud-init config found; skipping`), so neither edit ever
applied. This was confirmed on a launched OL6 instance: `90_ol.cfg` still carried
`groups: [adm, systemd-journal]`, the stock `cloud.cfg` still read
`name: cloud-user`, and `ec2-user` did not exist (`id: ec2-user: No such user`).
Verified locally that the wrapped `cloud_init` runs the original then the hook,
and the hook applies both edits against real-shaped `cloud.cfg`/`90_ol.cfg`
(idempotent). A host-runnable regression tier (B-T9, `tests/t8_hooktiming.sh`)
guards this: it asserts the injection wraps `cloud::cloud_init` and emits no
top-level `sh <hook>`, and behaviourally that the hook fires after `cloud_init`.

OL7+ are untouched (their `systemd-journal` group exists — per-OS isolation).

---

## D.27 `register-image` hardcoded `--imds-support v2.0` — broke OL6 metadata/SSH-key injection

**Symptom.** OL6 instances launched from the built AMI with no explicit IMDS
options never received their SSH key and could not be logged into; cloud-init
appeared to run but fetched no metadata.

**Cause.** Phase 9 registered *every* AMI with `--imds-support v2.0`
unconditionally. That bakes `HttpTokens=required` (IMDSv2-only) as the AMI's
default, so a launch that does not override it forces IMDSv2. OL6's cloud-init
is **0.7.5**, which has no IMDSv2 (token) support, so it cannot read the
instance metadata at all — no SSH key, no user-data. (The OL6 test instance
worked only because it was launched with an explicit `HttpTokens=optional`
override; the AMI's own default was wrong.)

**Fix (F1).** `--imds-support` is now conditional, controlled by `IMDS_SUPPORT`
(env or `--imds-support` flag):
- **`default`** (the new default) — `--imds-support` is **omitted**, so the AMI
  imposes no IMDS preference and instances allow IMDSv1+IMDSv2
  (`HttpTokens=optional`). Compatible with every OL generation.
- **`v2.0`** — registers `--imds-support v2.0` (IMDSv2-required). **OL7+ only.**
- **OL6 + `v2.0` is rejected** at env validation (it cannot work).

**Operator note.** If your AWS account/Organization enforces "IMDSv2 required"
(IMDSv1 disabled account-wide), OL6 AMIs cannot be used — OL6's cloud-init
cannot satisfy IMDSv2. That is an OL6/cloud-init limitation, not a wrapper one;
it is the operator's responsibility to keep IMDSv1 available where OL6 is
required, or to not target OL6 under such a policy.

---

# Part E — Logging & Diagnostics

The wrapper emits a single, uniform log stream to the console and (by default)
to a persistent file. Three orthogonal axes describe every line.

## E.1 Line format

```
YYYY-MM-DD HH:MM:SS  [SEVERITY]  [OLAWS-CODE]  <message>
```

- The **timestamp leads the line** on every timestamped channel; the
  `[SEVERITY]` / source tag (`[BUILD]` / `[EXTERNAL]`) follows it, then the
  optional `[OLAWS-CODE]`, then the message. (Earlier versions placed the
  `[SEVERITY]` tag first; the timestamp is now the first field so a `sort` or a
  visual time-scan lines up by column.)
- The **timestamp is unified** to `YYYY-MM-DD HH:MM:SS` on every channel,
  including the `[BUILD]` heartbeat and the `[EXTERNAL]` re-emission (N2). Prior
  versions used a bare `HH:MM:SS` on those two channels.
- The **`[OLAWS-CODE]` tag is optional**: it appears only on curated logic
  points (the wrapper's own decisions and the Phase-6 assurance checks), never
  on every line.

## E.2 Axis 1 — SEVERITY

| Tag | Meaning | Destination |
|:--|:--|:--|
| `[INFO]` | normal progress | console + file |
| `[WARN]` | non-fatal anomaly / advisory | console + file (stderr) |
| `[ERROR]` | fatal; precedes `die` | console + file (stderr) |
| `[DEBUG]` | verbose diagnostics | **file always**; console only with `--debug` |

`[DEBUG]` (F4) is written to the log file unconditionally and mirrored to the
console only when `--debug` (`DEBUG=1`) is set, so the default console stays
readable while the file retains full detail.

## E.3 Axis 2 — SOURCE

| Tag | Source |
|:--|:--|
| (none / severity only) | this wrapper's own logic |
| `[BUILD]` | wrapper build-phase heartbeat |
| `[EXTERNAL] … [<script>]` | output re-emitted from an invoked external tool (and its children), attributed to the originating script |

## E.4 Axis 3 — LOGIC-CODE (`[OLAWS-<AREA><NN>]`)

Stable identifiers for the wrapper's own decision/diagnostic points, so a log
can be grepped by concern. An **OS suffix** (`/OL6`, `/OL7`, …) is appended when
the line is specific to one generation (e.g. `[OLAWS-USR01/OL6]`).

| Code | Meaning |
|:--|:--|
| `OLAWS-LOG01` | build-log location (and whether `--debug` console output is on) |
| `OLAWS-CFG01` | resolved feature knobs (`[DEBUG]`: ENA/IMDS/skip flags) |
| `OLAWS-NVM01` | Nitro initramfs-drivers hook injected (nvme/ena into initramfs) |
| `OLAWS-ENA01` | in-guest ENA driver self-build hook injected |
| `OLAWS-CON01` | serial-console (`ttyS0`) hook injected (GRUB2 / OL7+) |
| `OLAWS-USR01` | OL6 cloud-init default-user alignment hook injected (→ `ec2-user`) |
| `OLAWS-IMD01` | AMI IMDS support mode chosen at `register-image` |
| `OLAWS-CHK01` | Phase-6 assurance CHECK 1 — NVMe host driver |
| `OLAWS-CHK02` | Phase-6 assurance CHECK 2 — ENA driver |
| `OLAWS-CHK03` | Phase-6 assurance CHECK 3 — fstab device-name mounts |
| `OLAWS-CHK04` | Phase-6 assurance CHECK 4 — bootloader `root=` form |
| `OLAWS-CHK05` | Phase-6 assurance CHECK 5 — serial console (advisory) |

The catalogue is **append-only and curated**: new codes are added for genuine
decision points, not for routine output. Codes are intentionally absent from
ordinary `[INFO]`/`[BUILD]`/`[EXTERNAL]` lines.

## E.5 File logging (N3)

The full run is mirrored to a file while the console is preserved:

- **Default path:** `${WORKSPACE}/build-ol-aws-ami-YYYYMMDD-hhmmss.log`
  (the timestamp is the build start time).
- **Override:** `--log-file <path>` (env `LOG_FILE`).
- The console keeps ANSI colour; the **file is ANSI-stripped** so it stays
  grep-friendly. `[DEBUG]` lines reach the file via a direct handle even when
  they are suppressed on the console.

---


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
   shellcheck -S style build-ol-aws-ami.sh
   ./build-ol-aws-ami.sh --env env.properties.aws-ol11 --build-only
   ```

No script changes should be required, because
`parse_ol_version_from_iso` and `detect_os_variant` adapt automatically
to the new major version.

If Oracle changes the ISO naming convention or moves the checksum URL
again, update Part D with a new entry and add the new pattern to
`parse_ol_version_from_iso` / `derive_oracle_checksum_url` respectively.
