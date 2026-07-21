---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.1.0
  rendered: 2026-07-02
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

- [Part A — Common Specification](#part-a--common-specification-vendored-from-the-spec-home)
  - [A.1–A.8 vendored from the spec home](#a1-reference-assets) — reference assets, source file format, logging, parameter handling, error/diagnostics & shell options, static analysis, documentation language policy, development workflow
  - [A.9 Reference assets (project)](#a9-reference-assets-project)
  - [A.10 Script layout (project)](#a10-script-layout-project)
  - [A.11 Pipeline architecture (9 phases)](#a11-pipeline-architecture-9-phases)
  - [A.12 Extended log markers (project)](#a12-extended-log-markers-project)
  - [A.13 Env property file conventions (project)](#a13-env-property-file-conventions-project)
  - [A.14 Oracle Linux version auto-detection (project)](#a14-oracle-linux-version-auto-detection-project)
  - [A.15 libguestfs caller pattern and project diagnostics](#a15-libguestfs-caller-pattern-and-project-diagnostics)
  - [A.16 Documentation and revision specifics (project)](#a16-documentation-and-revision-specifics-project)
  - [A.17 Parameter inventory (project)](#a17-parameter-inventory-project)
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
- [Part E — Logging & Diagnostics](#part-e--logging--diagnostics)
- [Appendix: How to add support for a new OL major release](#appendix-how-to-add-support-for-a-new-ol-major-release)

---

# Part A — Common Specification (vendored from the spec home)

> **Status: inherited — vendored from the spec home.** Per the
> [`AGENTS.md` §6 Part A Inheritance Rule (ABSOLUTE)](https://github.com/usui-tk/ai-generated-artifacts/blob/main/AGENTS.md#6-part-a-inheritance-rule-absolute),
> the 8 canonical Part A regions below (A.1–A.8) are vendored from
> [`governance/spec/bash.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/governance/spec/bash.md)
> as marker+hash regions verified against the spec home by the document-conformance
> gate; they are never hand-edited. Sections **A.9–A.17** are this consumer's
> project-specific extensions (not vendored): conventions observed only in this
> project, kept out of the family home per the rule-of-two. Before B0 this Part A
> carried the family common text inline as the pre-extraction de-facto reference;
> that text now lives in the spec home and is inherited from it.

<!-- >>> CANONICAL unit_id=spec.bash.part-a.reference-assets version=1.0.1 hash=f3c69969142a70bd policy=canonical binding=follow-latest >>> -->
### A.1 Reference assets

Every Bash script in the canon draws on a shared set of reference assets: (1) the
static-analysis configuration and gate (see A.6); (2) the companion specification
documents that make up the doc-set (README + README.ja, SPEC, and where applicable
TESTING and CHANGELOG); (3) the family's worked-example consumer
(`{{REFERENCE_PROJECT}}`), the concrete demonstration of these conventions; and (4) the
self-test harness (`tests/run-all.sh` plus the `tests/lib/` assertion/mock/heredoc
helpers), reused by porting rather than re-invention. The specific reference assets a
consumer uses are recorded in that consumer's own SPEC; this region only fixes that the
assets exist and where their conventions are defined.
<!-- <<< CANONICAL unit_id=spec.bash.part-a.reference-assets <<< -->

<!-- >>> CANONICAL unit_id=spec.bash.part-a.source-file-format version=1.0.1 hash=06308f39d34cdc95 policy=canonical binding=follow-latest >>> -->
### A.2 Source file format

Script source files are encoded **UTF-8 without BOM** and use **LF** line endings
(repository File Format Policy). Every executable script starts with the shebang
`#!/usr/bin/env bash` and follows the canonical top-to-bottom layout: shebang; header
comment banner; shell options (A.5); constants; execution-mode globals; logging helpers
(A.3); argument/environment parsing (A.4); domain functions; `main()`; and a
bottom-of-file `main "$@"` invocation (single-purpose helper scripts may omit `main()`
but keep the remaining order). The header banner MUST carry the five sections required
by the repository README header convention (canonical home: the `governance/templates/` README template canon): **Purpose**, **Prerequisites**,
**Usage examples**, **Known limitations**, and **AI generation info** (tool and
generation date). Non-ASCII characters are confined to intentional data/string literals;
identifiers and code are ASCII.
<!-- <<< CANONICAL unit_id=spec.bash.part-a.source-file-format <<< -->

<!-- >>> CANONICAL unit_id=spec.bash.part-a.logging version=1.0.1 hash=9e85866ab961f01a policy=canonical binding=follow-latest >>> -->
### A.3 Logging conventions

Operator-facing logging uses a **curated, append-only marker set**: a phase/step banner
helper (no literal severity tag, the one channel with no timestamp), `[INFO]` to stdout
for routine progress, `[WARN]` to **stderr** for degraded-but-continuing advisories, and
`[ERROR]` to **stderr** for failures (usually followed by `die`, A.5). Extended markers
(for example `[BUILD]`, `[DEBUG]`, `[EXTERNAL]`) are consumer-defined additions for a
genuine new severity or source - never ad-hoc one-offs such as `[OK]` - and are catalogued
in the consumer's SPEC. Timestamped lines use the unified form
`YYYY-MM-DD HH:MM:SS  [SEVERITY]  [{{PROJECT_CODE}}-<AREA><NN>]  <message>` where the
logic-code tag is **optional** and appears only on curated decision points. Colour is
enabled only on an interactive stdout so captured output parses cleanly.
**Machine-consumed output channels** (for example a single-line result-JSON contract
parsed by a harness) are a separate per-consumer contract defined in Part B; log markers
MUST NOT interleave into a machine channel, and machine lines MUST NOT depend on log
formatting.
**Role scoping (observed).** The full marker set is realized by a family's primary
operator-facing pipeline script(s). Auxiliary scripts - self-contained installers,
matrix runners, generators, checkers - MAY instead use a minimal `log()` helper
(timestamped for long-running scripts, carrying a `[<script>]` source tag, single
stream) plus `die` (A.5) for the fatal path. When a script's stdout is itself a
machine channel, ALL human-facing log lines are routed to **stderr** so the machine
channel stays clean.
<!-- <<< CANONICAL unit_id=spec.bash.part-a.logging <<< -->

<!-- >>> CANONICAL unit_id=spec.bash.part-a.parameter-handling version=1.0.1 hash=88917cb6d61bc732 policy=canonical binding=follow-latest >>> -->
### A.4 Parameter handling

Command-line switches use long-form kebab-case (`--skip-prereq`, `--env <file>`); `-h` /
`--help` prints usage and exits 0. The argument parser MUST `die "Unknown option: $1"`
on any unrecognised switch - silently ignored options are how typos slip into CI
configurations and disable safety checks. Mutually exclusive or synonymous switches are
documented in the consumer's SPEC and enforced in the parser (synonym duplication logs a
notice, contradictions die). Environment-variable configuration follows the
`${VAR:-default}` override pattern; any `${VAR:?...}` / `${VAR:=...}` resolution MUST be
paired with an `[INFO]` line confirming the resolved value so operators can verify
configuration from the log. The concrete switch and environment-variable inventory is
per-consumer (Part B).
<!-- <<< CANONICAL unit_id=spec.bash.part-a.parameter-handling <<< -->

<!-- >>> CANONICAL unit_id=spec.bash.part-a.error-diagnostic version=1.0.1 hash=e395575128fdec10 policy=canonical binding=follow-latest >>> -->
### A.5 Error, diagnostics, and shell options

Output is three-tier: **fatal** `die "message"` (emits `[ERROR]`, exits 1; where a
machine channel exists, `die` also emits the structured failure record so every failure
stays parseable); **degraded** `log_warn` (continues, used when a fallback applies);
**informational** `log_info`. A `die` on a recoverable misconfiguration MUST be
actionable: what went wrong, why it matters, and how to fix it (concrete commands or
keys) - never a bare `Invalid X`.

Shell options are scoped by script role, a distinction observed in both consumers and
canonical here (it corrects the first consumer's earlier blanket "every script" text):

* **Production and operational scripts** - installers, builders, matrix runners,
  generators, checkers - MUST use `set -euo pipefail`.
* **The self-test harness** - the suite runner, `tNNN_*` tiers, and read-only verifiers -
  uses `set -uo pipefail` **deliberately**: assertion helpers count failures and must
  continue to the suite summary, so `errexit` is omitted there and failure propagation is
  explicit.

Defensive rules under these options: use `${VAR:-}` for any variable that may
legitimately be unset; trailing `|| true` is acceptable only when the failure is
genuinely tolerated (an optional probe) and is followed by an empty-result check; a
function whose final statement is a `[[ ... ]] && ...` list MUST end with an explicit
`return 0` so the success branch does not leak exit 1 to an `errexit` caller. Know the
**substitution-inheritance asymmetry**: `pipefail` IS inherited into command
substitutions while `errexit` is NOT (default Bash, `inherit_errexit` unset) - therefore
`x="$(probe | filter)"` inside a bare-called function is the recurring abort hazard
under `-e`, and every tolerated-empty probe of that shape MUST carry `|| true` on the
assignment. Do not enable `shopt -s inherit_errexit` casually: it re-arms every probe
that the asymmetry currently leaves inert.
<!-- <<< CANONICAL unit_id=spec.bash.part-a.error-diagnostic <<< -->

<!-- >>> CANONICAL unit_id=spec.bash.part-a.static-analysis version=1.0.1 hash=034f640d941dedee policy=canonical binding=follow-latest >>> -->
### A.6 Static analysis

Two static gates apply to every `.sh` file and run as the self-test suite's L0 tiers:
(1) `bash -n` syntax validation, and (2) **ShellCheck**, clean at **default severity
and at `-S style`** (the canonical gate severity). Project-sanctioned suppressions live
in the per-project `.shellcheckrc`; an inline `# shellcheck disable=SCnnnn` requires an
adjacent justifying comment stating why the finding is intentional. A change is not
gate-clean unless the whole suite (`tests/run-all.sh`) reports zero failures with the
static tiers green.
<!-- <<< CANONICAL unit_id=spec.bash.part-a.static-analysis <<< -->

<!-- >>> CANONICAL unit_id=spec.bash.part-a.doc-language-policy version=1.0.1 hash=ae89cf1a97795729 policy=canonical binding=follow-latest >>> -->
### A.7 Documentation language policy

The repository-wide root `README.md` Language Policy applies: the project `README.md`
(English master) and `README.ja.md` (Japanese translation) are maintained in
**bilingual lock-step** - same commit, matching section structure, tables, and code
blocks; `SPEC.md`, `TESTING.md`, and `CHANGELOG.md` are **English only**. In
English-only artifacts, Japanese may appear **only as quoted data** (for example a
documented Japanese section title or punctuation rule); navigational labels - including
the cross-link to a `.ja` companion - are written in English ("Japanese"), per the
AGENTS.md authoring-language rules. `README.ja.md` style: preserve technical terms in
English, use full-width Japanese punctuation, and keep code spans verbatim. Each README
carries the language-switcher banner at the top and a Provenance section (AI tool,
generation date, AS-IS disclaimer) at the bottom.
<!-- <<< CANONICAL unit_id=spec.bash.part-a.doc-language-policy <<< -->

<!-- >>> CANONICAL unit_id=spec.bash.part-a.development-workflow version=1.0.1 hash=e4be8f1484f5d2f4 policy=canonical binding=follow-latest >>> -->
### A.8 Development workflow

The iteration cycle is: reproduce the issue (or write the unit tier first); modify the
code; `bash -n` (syntax gate); `tests/run-all.sh` with **zero failures** (static +
hermetic gate); exercise the affected functional path; update `README.md` +
`README.ja.md` in lock-step if behaviour or contract changed; commit. **Revision
discipline** follows the root Revision History Policy: per-revision release notes live
**exclusively** in the project `CHANGELOG.md` (revision tags such as `rNN`, or the commit
hash where a consumer records that choice in Part B) - never as inline revision comments
in script bodies, never in the README beyond a pointer, and never in the SPEC, which
describes *current* behaviour only. Root-cause analyses of closed defects belong in the
SPEC's **Part D - Known Pitfalls**, cross-referenced from CHANGELOG entries.
**Reuse before invention**: before adding a helper, search the existing script and the
family reference assets (A.1) for an equivalent, extend it if found, and place genuinely
new helpers near their functional relatives rather than at file end.
<!-- <<< CANONICAL unit_id=spec.bash.part-a.development-workflow <<< -->

---

### A.9 Reference assets (project)

These are the canonical sources of truth. **Pull from these directly; do not re-implement.**

#### A.9.1 Canonical scripts

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

#### A.9.2 Upstream dependency

The script is a wrapper around Oracle's official tool:

```
https://github.com/oracle/oracle-linux/tree/main/oracle-linux-image-tools
```

Specifically, Phase 5 invokes `bin/build-image.sh` from a clone of that
repository. Behavior changes upstream (e.g. supported `BOOT_MODE` values,
distribution slug naming, environment variable keys) must be tracked here
and reflected in `load_env` validation.

#### A.9.3 Companion files

```
env.properties.aws-ol10     Oracle Linux 10 template (update release pinned by ISO_URL)
env.properties.aws-ol9      Oracle Linux 9  template (update release pinned by ISO_URL)
env.properties.aws-ol8      Oracle Linux 8  Update 10 template
env.properties.aws-ol7      Oracle Linux 7  Update 9 template (experimental — see B.3, D.10)
env.properties.aws-ol6      Oracle Linux 6  Update 10 template (experimental — see B.4, B.5, D.11–D.16)
README.md / README.ja.md    end-user documentation (bilingual)
SPEC.md                     this developer specification (English only)
```

#### A.9.4 Workspace path convention

`WORKSPACE` defaults to `/tmp/ol{N}-build-ws` (where `{N}` is the OL major
version). The path is chosen specifically because `/tmp` is world-traversable
by FHS convention, which avoids libvirt's qemu user (uid 107) being unable
to reach files placed under `/root` or other restricted parents. See A.13
and D.3 for the full rationale.

---

---

### A.10 Script layout (project)

#### File structure (top-to-bottom)

```
1. Shebang                            #!/usr/bin/env bash
2. Header banner (BoxArt block)       Purpose / Prerequisites / Usage / Limitations / AI info
3. set -euo pipefail                  Mandatory; see A.5
4. Constants (readonly)               OL_REPO_URL, OL_TOOLS_SUBDIR
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

The five header-banner sections required by the common A.2 are realized with the
following project-specific required content:

| Section | Required content |
|---------|------------------|
| Purpose | One paragraph; what the script does and why |
| Prerequisites | Runtime, permissions, required CLIs |
| Usage examples | At least two invocations |
| Known limitations | aarch64, BOOT_MODE constraints, concurrency limits |
| AI generation info | Tool name, generation date |

---

---

### A.11 Pipeline architecture (9 phases)

#### Numbering rules

- Phases are numbered **0 through 9 with no gaps** (no `Phase 5.5`).
- Phase function names follow `phase{N}_<verb>_<noun>()` (snake_case).
- Phase 0 is preflight; subsequent phases assume Phase 0 passed.

#### Phase registry

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
| 9 | `phase9_register_ami` | AWS | `register-image` (name/description pre-validated; `--dry-run` pre-flight gates the real call) with conditional `--tpm-support` |

#### Phase groups (semantic)

- **Validation** (0, 6): Read-only diagnostics / offline image inspection; never mutates state.
- **Provisioning** (1, 2): Requires sudo; idempotent (skip if already done).
- **Build** (3, 4, 5): Operates inside `WORKSPACE`; produces a VMDK.
- **AWS** (7, 8, 9): Network operations against the configured `AWS_REGION`.

#### Phase entry/exit contract

Every phase MUST:

1. Call `log_step "Phase {N}: <one-line summary>"` on entry.
2. On failure, call `die "<actionable error message>"` (which exits 1).
3. On success, return naturally (do NOT call `exit 0`); `set -e` will catch
   any unhandled non-zero exit before this point.
4. Export any state needed by later phases as plain shell variables
   (e.g. `VMDK_PATH`, `S3_KEY`, `SNAPSHOT_ID`).

#### Skip / partial-execution semantics

- `--skip-prereq` → Skip Phase 1 only (Phase 2 still runs, since ACLs may
  need refreshing even when packages are installed).
- `--build-only` → Run through Phase 6 (VMDK build + Nitro readiness check), then exit 0.
- `--skip-aws-import` → Synonym for `--build-only`.

---

---

### A.12 Extended log markers (project)

The common A.3 marker set is realized in this script with the following concrete
helpers, colours, and extended markers (`[BUILD]`, `[DEBUG]`, `[EXTERNAL]`):

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

Timestamped lines take the concrete form (common A.3):

```
YYYY-MM-DD HH:MM:SS  [SEVERITY]  [OLAWS-CODE]  <message>
```

- The `[OLAWS-<AREA><NN>]` logic-code tag is **optional**: it appears only on
  curated decision points and the Phase-6 assurance checks, never on every line
  (catalogue in Part E.4).

---

### A.13 Env property file conventions (project)

#### File format

```
KEY="value"     # bash assignment, quoted to allow spaces
# Comments start with # at column 0
```

The file is `source`'d into the script's environment, so it must be valid
bash. Avoid command substitutions in env files (security and reproducibility).

#### Required keys

| Key | Required | Default | Notes |
|-----|----------|---------|-------|
| `WORKSPACE` | ✓ | (none) | Must be world-traversable; see D.3 |
| `S3_BUCKET` | ✓\* | (none) | Required unless `--build-only` |
| `AWS_REGION` | ✓\* | (none) | Required unless `--build-only` |
| `ISO_URL` | ✓ | (none) | Required; OL version auto-detected from this URL. No built-in default (a hard-coded release URL would go stale; the env templates are the single maintenance point) |

\* Required only when AWS-import phases will run.

#### Optional / auto-derived keys

| Key | Auto-default |
|-----|--------------|
| `DISTR` | `ol${OL_MAJOR_VERSION}-slim` |
| `CLOUD` | `aws` |
| `AMI_NAME` | `OracleLinux-${MAJOR}-U${UPDATE}-x86_64-$(date +%Y%m%d-%H%M)`; when the ENA self-build is enabled (default), the auto-default also appends `-ena${ENA_BUILD_VERSION}` (the installer's pin); when the SSM Agent install is enabled (default), it further appends `-ssm${version}`; and when the AWS CLI v2 install is enabled (default, OL6/OL7/OL8), it further appends `-awscli${version}` — a **concrete** `x.y.z` (the OL6 pin, or the resolved OL7/OL8 `latest`), so an ENA-self-built / SSM-managed / AWS-CLI-bearing AMI is distinguishable pre-launch. The ssm and awscli markers carry a concrete version only and are **omitted** rather than ever printing `latest` (resolution failure → no marker; awscli additionally: OL9/OL10 → no marker). An explicitly set `AMI_NAME` is left untouched. |
| `AMI_DESCRIPTION` | `Oracle Linux ${MAJOR} Update ${UPDATE} (x86_64) custom AMI built via oracle-linux-image-tools`; the auto-default appends ` with self-built Amazon ENA ${ENA_BUILD_VERSION} (DKMS, AWS-optimized for Nitro)` when self-build is on, or ` (pure OL; ENA self-build skipped)` for `--skip-ena-driver`, further appends `, Amazon SSM Agent ${version}` when the SSM install is on (omitted for `--skip-ssm-agent`), and further appends `, AWS CLI v2 ${version}` (a concrete `x.y.z`) when the AWS CLI v2 install is on (OL6/OL7/OL8; omitted for `--skip-awscli`, OL9/OL10, or an unresolved version). `ENA_BUILD_VERSION` is read from `install-ena-driver.sh`'s `ENA_VERSION_OL<major>` pin, the SSM version from `install-ssm-agent.sh`'s `SSM_AGENT_VERSION_OL<major>` pin, and the AWS CLI version from `install-awscli.sh`'s `AWSCLI_VERSION_OL<major>` pin (single source of truth). |
| `BOOT_MODE_BUILD` | `bios` (Oracle tool restricts AWS to bios) |
| `BOOT_MODE` | `legacy-bios` (must match `BOOT_MODE_BUILD`) |
| `OS_VARIANT` | Auto-detected via `detect_os_variant` |
| `ISO_CHECKSUM` | Auto-resolved via `derive_oracle_checksum_url` |

#### Pass-through keys (consumed by `oracle-linux-image-tools`)

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
| `DISK_SIZE_GB` | `7` | Root volume size of the AMI; uniform 7 GB across OL6-10 — see B.3.4 "Disk sizing" |
| `LINUX_FIRMWARE` | `no` (OL8 only) | Remove the bulk `linux-firmware` package **before the in-guest update** (upstream distr knob) so the `UPDATE_TO_LATEST` transaction fits the 7 GB root — EL8's firmware is uniquely uncompressed (~1.9 GB installed) and otherwise overflows it. This is a **build-time headroom knob**: the booted 2026-07-13 images were observed to carry `linux-firmware` again (re-entering via the later provisioning flow), which is functionally benign. `linux-firmware-core` (kernel-uek-core's small dependency) is untouched — see B.3.4 |
| `AMAZON_TIME_SYNC` | `no` | OPT-IN. `yes` (or `--enable-amazon-time-sync`) makes guest provisioning add the link-local Amazon Time Sync Service (169.254.169.123) as the preferred time source — see B.14 |
| `ENA_DRIVER_VERSION` | (unset) | OPTIONAL user pin (emergency lever). A concrete `x.y.z` becomes the highest-priority self-built ENA version on every major: it enters the AMI identity AND the guest hook (no drift). Non-`x.y.z` values die in `load_env`. Unset = installer pin → latest → fallback chain |
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

#### Nitro initramfs drivers (nvme/ena)

Independently of the ENA driver *version*, the **initramfs must contain `nvme`
(and `ena`)** — on Nitro the root filesystem is NVMe-backed, so without nvme in
the initramfs the instance cannot mount root and fails to boot. The image is
built in a VM whose disk is virtio (`/dev/sda`), so dracut's **hostonly** mode
omits nvme from the initramfs (observed on OL7 UEK R6: `nvme.ko` was on disk but
absent from the initramfs, and Phase 6 CHECK 1 correctly FAILed). This is a boot
requirement, so Phase 3 **always** (even with `--skip-ena-driver`) appends a hook
to `cloud/aws/provision.sh` that writes `/etc/dracut.conf.d/02-ol-aws-nitro.conf`
and regenerates the initramfs for the installed kernel (`dracut -f`). The
drop-in is **presence-aware** (D.28): it lists only the drivers whose `.ko`
exists for the target kernel at the hook's (source-time, pre-DKMS) stage — on
the slim OL8/9/10 builds the in-box `ena` is not on disk at that stage
(observed directly in the 2026-07-13 build logs; the in-box `ena` ships in
`kernel-uek-modules`, which is not staged at that point), so `ena` is
*deferred*: the ENA hook appends `ena` to the same drop-in right
before invoking the installer, whose own `dracut -f` then bakes it in (and the
drop-in persists across in-instance kernel updates). The hook targets the
highest UEK under `/lib/modules` (the appliance's `uname -r` is not the
guest's) and is best-effort — it never aborts the build; CHECK 1 verifies the
result. OL6/OL7 carry an in-box `ena`, so all three drivers enter the drop-in
at the first stage there.

#### ENA driver self-build (`--skip-ena-driver`)

**Rationale — baseline in-distro ENA drivers (measured).** The default OL images
ship an ENA driver bundled in `kernel-uek` that is too old for ENAv3 (Nitro
v4+). The Phase 6 assurance report measured the following on freshly built
images, which is the concrete justification for self-building a newer ENA driver
when producing an AWS-optimized AMI:

| OL | Kernel package (UEK) | In-distro ENA (`modinfo`) | ENAv3 status (amzn-drivers) | Self-build pin |
|----|----------------------|---------------------------|-----------------------------|----------------|
| OL6 U10 | `kernel-uek-4.1.12-124.48.6.el6uek.x86_64` | `1.1.2` | `< 1.2.0` → ENAv3 ENI attach **fails** on Nitro v4+ | `ena_linux_2.9.1` |
| OL7 U9  | `kernel-uek-5.4.17-2136.338.4.2.el7uek.x86_64` | `2.1.0K` | `1.2.0`–`< 2.2.9` → ENAv3 **performance degradation** | `ena_linux_2.17.2` |

Both bundled drivers are below the `2.2.9` full-ENAv3 threshold, so on Nitro v4+
instances the stock images either fail to attach an ENAv3 ENI (OL6) or run
degraded (OL7). The pinned self-build versions (`2.9.1` / `2.17.2`) are both
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
  **OL7** (pinned `ena_linux_2.17.2`, the newest release confirmed to support
  RHEL7 — built ok on UEK6 `5.4.17-2136.338.4.2.el7uek` in the 2026-07-11
  matrix run). On **OL8/OL9/OL10** it resolves
  `ena_linux` **latest** at runtime via `_ena_resolve_latest()` (`git
  ls-remote --tags` against `amzn/amzn-drivers`, HEAD-verifies the tarball,
  falls back to `ENA_LATEST_FALLBACK_PIN` — default `2.17.2` — on failure),
  overridable via `ENA_DRIVER_VERSION` or the per-OS `ENA_VERSION_OL8/9/10`
  variables. This is **production** (ENA Express generation: the produced AMI
  must ship an express-capable driver): `build-ol-aws-ami.sh` injects the
  self-build hook on **OL6–OL10 by default**. The wrapper-side version chain
  is: **env-file user pin `ENA_DRIVER_VERSION`** (highest priority; must be a
  concrete `x.y.z`, else `load_env` dies; logged under `[OLAWS-ENA02]` and
  passed into the guest hook on EVERY major — pinned-installer majors
  included — so the AMI name and the built module cannot drift) → installer
  pin (OL6/7) → amzn-drivers **latest** resolved **host-side**
  (`[OLAWS-ENA02]`, mirroring the AWS CLI resolver) → fallback pin. The
  resolved concrete version is passed into the guest via
  `ENA_DRIVER_VERSION` on the latest-resolving
  majors, so the AMI identity and the built module always agree (the in-guest
  runtime resolution is the standalone / container-test path). The pin
  extractors (`_ena_pin_for_major` / `_ena_fallback_pin`) are **shape-guarded**
  (only a concrete `x.y.z` is ever emitted; the empty defaults of the
  latest-resolving majors and any unrecognized pin form both yield `""`,
  which callers treat as "resolve latest / use fallback"). Bug history: the
  original sed (`[^}"]+`, one-or-more) did not match the empty default
  `NAME="${NAME:-}"`, so the raw assignment line leaked into `AMI_NAME` and
  the `[OLAWS-ENA02]` branch never ran — caught by the first real OL8-10
  build (2026-07-11), fixed with `[^}"]*` + the x.y.z guard, and pinned by
  t003 (fixture + real-file shape regression). A second first-real-build catch
  (same day): `report_inbox_ena()` -- the purely informational pre-build
  in-box-module report -- lacked the `|| true` guard every sibling pipeline in
  the installer carries, so on a guest kernel with no in-box ena module its
  `modinfo | head` substitutions killed provisioning silently under
  `set -euo pipefail`, before `dkms add`. Fixed (guarded) and pinned by a t010
  behavioural regression that runs the shipped function text under the
  real-guest condition (the container matrix never hits it: clean-core lacks
  modinfo, so the guard branch skips). Real AMI boot
  with an OL8/9/10 self-built driver is **not yet E2E-verified** (container
  compile + DKMS-install proof only — the same caveat model as the SSM Agent
  integration). On **OL9/UEKR8 and OL10/UEKR8**, `latest` is confirmed to build
  (B.9's 2026-07-03 evaluation findings); the ENA Express metrics floor
  `2.8.0` is confirmed to **fail** on both (an upstream XDP symbol rename
  `2.8.0`'s `kcompat.h` predates) — see B.9 for the full findings and the
  kernel-matching compiler requirements (`gcc-toolset-14` on OL9/UEKR8,
  `gcc-toolset-11` on OL8/UEKR7). Pins are chosen as the
  newest release that **builds** on each target OS (the ENA driver is a
  kernel module; newer releases assume newer kernels/toolchains).
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
  The installer enables the UEK repo (`*UEKR4*`/`*UEKR6*`; on OL8 also
  `*UEKR7*`, the track real OL8.10 AMIs run — the UEKR6-only glob was a
  leftover of the pre-UEKR7 default), tries the exact
  `-devel`, and if the headers are still absent installs the **latest**
  `kernel-uek` + matching `-devel` and **retargets** to it (a guaranteed
  buildable pair).
- **UEK detection (cross-kernel build, OL6/OL8).** The amzn-drivers Makefile
  derives `IS_UEK` and `ENA_KERNEL_SUBVERSION_*` from `uname -r` (the *running*
  kernel), and those gate the UEK-backport guards in `kcompat.h`. Under the
  libguestfs provisioning appliance — and in the container matrix's chroot —
  `uname -r` is the non-UEK host/appliance kernel, so the macros are unset and
  two guards are known to break the build: on **OL6/UEK4** the
  `page_ref_count` guard redefines a symbol the backported kernel
  (`>= 4.1.12-124.43.1`, e.g. `-124.48.6`) already provides; on **OL8/UEKR7**
  the `bpf_warn_invalid_xdp_action` guard collapses the call to the pre-5.17
  1-arg form against a kernel that backports the 3-arg mainline signature —
  upstream `kcompat.h` explicitly excludes that macro for
  `IS_UEK >= 5.15.0-100.96.32`, an exclusion that can only fire when `IS_UEK`
  is set (reproduced and fix-verified in a container FT, 2026-07-12). Because
  the build already passes the target kernel as `BUILD_KERNEL`, the installer
  patches that detection (OL6 and OL8) to read `BUILD_KERNEL`, so the guards
  evaluate against the DKMS target rather than the appliance. OL7/UEK6 builds
  `2.17.2` fine with `IS_UEK` unset (2026-07-11 matrix run: the
  `page_ref_count` block is compiled out on `>= 4.6` kernels and the bpf
  guard's 1-arg collapse matches UEK6's un-backported 5.4 signature);
  OL9/OL10 UEKR8 (`6.12 >= 5.17`) version-exclude the bpf guard regardless of
  `IS_UEK` — their Makefiles are left untouched (per-OS isolation).
  Standalone runs on a live instance are unaffected (`uname -r` is the real
  UEK kernel there).
- **Builds via DKMS** (`REMAKE_INITRD`/`AUTOINSTALL`), so the module is rebuilt
  automatically across in-instance kernel upgrades. DKMS comes from EPEL —
  Oracle-provided `ol7_developer_EPEL` on OL7, `ol8_developer_EPEL` /
  `ol9_developer_EPEL` on OL8/OL9 (unversioned repo paths; fixed section
  names), and the Fedora **EPEL 6 archive** on OL6 (Oracle does not provide
  EPEL 6). **OL10 is different**: its developer-EPEL repo is versioned per
  update release (baseurl `…/OL10/<N>/developer/EPEL/…`, section
  `[ol10_u<N>_developer_EPEL]`) and the section name churns on every OL10
  point release, so a fixed name breaks silently. The installer therefore
  runs a live discover → verify → finalize pass on OL10 only
  (`setup_epel_ol10`): it collects candidates from BOTH the shipped
  `oracle-epel-ol10.repo` sections AND a constructed URL for the running
  minor (from `/etc/oracle-release` / `os-release`), verifies each against
  the live yum server through core dnf (`--repofrompath`,
  `skip_if_unavailable=0`) requiring that the repo is reachable **and
  actually offers `dkms`**, then selects the running minor's own repo first,
  else the highest verified `u<N>`. A live shipped section is enabled in
  place and dead shipped sections are explicitly disabled; a
  constructed-only winner is materialized as a **disposable** repo file
  (provenance marker header, `gpgcheck=1` with the Oracle key) that is
  removed right after the dkms provisioning step. Every candidate verdict is
  logged. The enabled-only early return in `setup_epel` is bypassed on OL10
  (an enabled shipped section can still be dead there). Scope assumption:
  the Oracle repo-file variables expand as `$ociregion=""` /
  `$ocidomain="oracle.com"` (the public yum server) — OCI-internal mirror
  regions are outside this AWS pipeline's scope. Known residual limitation:
  if Oracle publishes an OL10 image whose shipped section leads (or lags)
  the published repo paths on their side, the discovery follows whatever is
  actually live; a window in which **no** OL10 developer-EPEL path is
  published at all is an Oracle-side outage the client cannot bridge — the
  installer then logs the per-candidate diagnostics and falls back to a
  plain `make` build. If DKMS is unavailable it falls back
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

#### Container compile-test (`ENA_BUILDTEST`)

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
  `ol8_developer_EPEL` + `ol8_UEKR7` (default; `BT_UEK_REPO_OVERRIDE=ol8_UEKR6`
  runs a UEKR6-specific regression check instead); OL9 bootstraps `yum` the
  same way, then enables `ol9_developer_EPEL` + `ol9_UEKR8`
  (`BT_UEK_REPO_OVERRIDE=ol9_UEKR7` for a UEKR7-specific check); OL10
  bootstraps `yum`, then routes through the same live-verified
  `setup_epel_ol10` discovery as production (see the DKMS bullet above —
  OL10's developer-EPEL section name churns per update release, so there is
  no fixed name to enable) and **dies** on a verification miss (the
  container tier must be strict where production degrades), then
  `ol10_UEKR8`. The shipped (disabled) EPEL is enabled
  persistently so the production `setup_epel` finds it already enabled and does
  not create a second repo (on OL10 the production pass re-runs the
  idempotent discovery instead — an enabled section is not proof of a live
  one there).
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
- **`status:ok` certifies the REQUESTED version was built — not mere presence.**
  The verify trusts the installed module *version*, not the `dkms` exit code or
  file presence: EL6 `dkms` (2.4.0) returns `0` even when the in-guest compile
  fails (so `set -e` does not catch it), and `kernel-uek` ships a stock in-tree
  `ena.ko` (e.g. `1.1.2`). The verify walks every `ena.ko` under the tree and
  requires one whose `modinfo` version matches the requested `ena_version` (a
  prefix match — the pin installs as e.g. `2.9.1g`); if none matches (the build
  failed and only the stock module remains) it is a **fatal `status:fail`**, not
  a false `ok`. This applies in production too: a non-building pin aborts the AMI
  build rather than silently shipping the stock driver. (Pure verdict logic:
  `ena_buildtest_verdict`, unit-tested by `tests/t015_enaverify.sh`.)

Validated end-to-end (the driver actually compiles, installs, and verifies) on
OL6 (`ena.ko` 2.9.1g, UEK4 `4.1.12-124.48.6.el6uek`), OL7 (`ena.ko.xz` 2.17.0g,
UEK6 `5.4.17-2136.338.4.2.el7uek`), and OL8 (`ena.ko.xz` 2.17.0g, UEK6
`5.4.17-2136.356.4.2.el8uek`); OL9/OL10 (UEKR8) build latest in the container
matrix (B.9, 2026-07-03). The AMI pipeline now self-builds ENA on **OL6–OL10
by default** (ENA Express generation): `build-ol-aws-ami.sh` injects the
provision.sh hook — and the `-ena<ver>` AMI naming — for every major, with the
OL8/9/10 target resolved host-side (`[OLAWS-ENA02]`) and passed into the guest.
Real AMI boot with an OL8/9/10 self-built driver remains to be E2E-verified
(the standing `[C]3` follow-up).

#### File naming convention

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

---

### A.14 Oracle Linux version auto-detection (project)

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

#### `detect_os_variant` priority list

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

---

### A.15 libguestfs caller pattern and project diagnostics

#### Caller pattern for libguestfs

Phase 5 sets `LIBGUESTFS_BACKEND=direct` before invoking
`bin/build-image.sh` to bypass libvirt's qemu user permission model. This
is **non-negotiable**; see D.6.

#### Actionable-error examples (common A.5, concrete)

Example (good):

```

Example (bad):

```

#### Diagnostic categories

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

### A.16 Documentation and revision specifics (project)

The common A.7 documentation-language policy and the common A.8 revision
discipline apply; this section records only the project-owned specifics.

#### Style for `README.ja.md`

- Technical terms in English are preserved in their English form (do not
  translate "phase", "qemu user", "libvirt", "WORKSPACE", "BOOT_MODE",
  "osinfo-db", "VMDK", etc.).
- Punctuation: 「、」 「。」「・」 (full-width); not "," "."
- Brackets: 「」 for emphasized terms, ` `` ` for code spans.

#### Mandatory header and footer sections

Each README must include:

1. Top-of-file banner: language switcher (`README.md` ↔ `README.ja.md`), repository link, AI-content warning.
2. Bottom-of-file "Provenance and License" section: AI tool, generation
   date, AS-IS disclaimer, issue tracker link.

This SPEC must include:

1. Top-of-file purpose block referencing the "single most important rule".
2. Documentation language policy notice (this section).

#### Version identifier

This script does not embed a revision number in the source: the repository
commit hash is the canonical revision identifier, and per-release notes are
recorded in `CHANGELOG.md` (present in this directory; tracking under
`[Unreleased]` until the first numbered release is cut).

Bump the AI-generation date stamp in the script header on any commit
that changes:

- Phase semantics (any of the 9 phases)
- Output format (log markers, banner layout)
- Parameter set (added / removed / renamed switches)

Cosmetic-only changes (typo fixes in messages, README rewording) do not
require a header date bump.

---

### A.17 Parameter inventory (project)

The common A.4 parameter-handling rules apply (long-form switches, help exit 0,
die on unknown options); the concrete inventory is:

#### Command-line switches

| Switch | Type | Required | Description |
|--------|------|----------|-------------|
| `--env <file>` | path | ✓ | Path to env.properties file |
| `--skip-prereq` | flag | | Skip Phase 1 (package installation) |
| `--skip-aws-import` | flag | | Skip Phases 6–8 (build VMDK only) |
| `--build-only` | flag | | Synonym for `--skip-aws-import` |
| `--skip-ena-driver` | flag | | Do NOT self-build the Amazon ENA driver (default ON for OL6/OL7); produces a pure OL AMI — see B.4 / the ENA self-build section |
| `--skip-ssm-agent` | flag | | Do NOT install the Amazon SSM Agent (default ON for OL6-OL10); produces an AMI with no SSM Agent — see B.11 |
| `--skip-awscli` | flag | | Do NOT install AWS CLI v2 (default ON for OL6/OL7/OL8; OL9/OL10 out of scope — use their default package manager); produces an AMI without the wrapper-installed AWS CLI v2 — see B.13 |
| `--enable-amazon-time-sync` | flag | | OPT-IN (default OFF). Configure the link-local Amazon Time Sync Service (169.254.169.123) as the preferred guest time source (chrony on OL7-OL10, ntpd on OL6), keeping the distribution pool as fallback. Equivalent to `AMAZON_TIME_SYNC="yes"` — see B.14 |
| `-h`, `--help` | flag | | Show help and exit 0 |

### Mutual exclusion

- `--skip-aws-import` and `--build-only` are synonyms; either may be
  passed but combining them is redundant (no error, but log a notice).
- `--skip-prereq` is independent and may combine with the others.


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
  AMIs is invalid. Before the real `register-image` it runs the same
  argument set with `--dry-run` as a pre-flight: per the AWS API a dry run
  that *would* succeed returns the error `DryRunOperation` (non-zero exit),
  so Phase 9 gates the real call on seeing `DryRunOperation` in the output
  and aborts (without creating an AMI) on anything else — e.g.
  `UnauthorizedOperation` (missing IAM permission) or a parameter error. The
  AMI `--name` and `--description` are additionally validated against the AWS
  register-image limits up front, in `load_env`, so a bad value fails fast
  before the build rather than at Phase 9 (see below).
- **`register-image` input validation.** Two pure validators enforce the AWS
  EC2 `register-image` string constraints
  ([reference](https://docs.aws.amazon.com/cli/latest/reference/ec2/register-image.html)):
  `validate_ami_name` requires `--name` to be **3-128** characters drawn only
  from alphanumerics and the literals `()[]` space `. / - ' @ _`;
  `validate_ami_description` requires `--description` to be **0-255**
  characters (any character; empty allowed). Both are argument-only (no env,
  fs, or network) and return a reason + non-zero on violation without exiting,
  so `load_env` calls them right after the AMI name/description are resolved
  and turns a violation into a fast `die` — catching a too-long or
  mis-charactered override (or an unexpectedly long auto name) before Phases
  1-8. Unit-tested by `tests/t020_register.sh`; the live `--dry-run` pre-flight
  is E2E (B-T8).

### Known constraints

See Part D for the historical context behind each.

- x86_64 only; aarch64 AMI builds are not implementable today (`oracle-linux-image-tools` AWS target is x86_64-only).
- AWS `BOOT_MODE=bios` is the only working combination; `legacy-bios`
  AMIs cannot use NitroTPM or UEFI Secure Boot, but boot fine on all
  Nitro instance types **for OL7-OL10** (proven through current-generation
  `c8a` on 2026-07-18).
- **OL6 instance-generation boundary (measured 2026-07-18)**: the frozen
  OL6/UEK4 kernel (`4.1.12`) panics at early boot on modern AMD instance
  generations — `kernel BUG at arch/x86/kernel/alternative.c:708`
  (jump-label `text_poke` verification) before any module loads, so no
  artifact of this pipeline is in the failure path. Measured: Intel
  generations through `r8i-flex` and AMD ≤ Zen2 (`c5a`) boot; AMD Zen3+
  (`c6a`/`c7a`/`c8a`) do not. Terminal kernel, no fix possible;
  documentation-only. See the TESTING.md 2026-07-18 evidence note and
  README section 10 item 8.
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
| `ISO_URL` | OL10 latest `u<N>` (single-touch maintenance point) | OL9 latest `u<N>` (single-touch maintenance point) | OL8 U10 (final OL8 release; frozen) | OL7 U9 (final; with `Server-` infix) | OL6 U10 (final; with `Server-` infix) |
| `# OS_VARIANT` example | `rhel10.<N>` | `rhel9.<N>` | `rhel8.10` | `rhel7.9` | `ol6.10` |
| `# AMI_NAME` example | `OracleLinux-10-U<N>-...` | `OracleLinux-9-U<N>-...` | `OracleLinux-8-U10-...` | `OracleLinux-7-U9-...` | `OracleLinux-6-U10-...` |
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

When a new Oracle Linux update release ships (e.g. a new OL9 or OL10
`u<N>`):

1. Update the target template's `ISO_URL` to the new release (the line is
   marked `>>> SINGLE-TOUCH MAINTENANCE POINT <<<` in the template).
2. That is the only change. All surrounding comments, the documentation,
   and the runtime (version detection, `OS_VARIANT`, AMI naming, checksum
   resolution via `parse_ol_version_from_iso` / `detect_os_variant` /
   `derive_oracle_checksum_url`) are written release-agnostically and
   adapt automatically.

OL6 / OL7 / OL8 templates are frozen at their terminal update releases
(U10 / U9 / U10 respectively) and never require this maintenance.

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

### B.3.4 Disk sizing (`DISK_SIZE_GB` = 7, uniform)

`DISK_SIZE_GB` is a uniform **7 GB** across OL6-10 (user decision 2026-07-11,
aligned with Oracle’s own AWS AMIs), down from the previous 10 GB. Why this is
safe and what bounds it:

- **The value is a floor, not a ceiling.** Every distr kickstart creates the
  root partition with `--grow` (boot partitions are kickstart-fixed: 500 MB on
  OL6/OL7, 1 MB BIOS-boot + 1 GB `/boot` on OL8-10; no swap — `SETUP_SWAP=no`
  makes the upstream framework strip the OL6 template’s swap line), and
  `cloud-utils-growpart` is baked into every image, so an instance launched
  with a larger EBS volume expands its root filesystem automatically on first
  boot. AWS does not allow launching with a volume *smaller* than the AMI’s
  registered size, so a smaller `DISK_SIZE_GB` strictly widens the launch
  envelope (and shrinks the build image / S3 upload).
- **The hard limit is build-time**: the anaconda install plus the in-guest
  `UPDATE_TO_LATEST` transaction peak must fit. Measured post-build root usage
  from the 2026-06-16 E2E generation (sosreports, 2026-07-11): OL6 1.4 G /
  OL7 3.4 G / OL8 3.6 G / OL9 2.3 G / OL10 2.0 G — 7 GB leaves ≥ 2.4 G of
  root headroom on the heaviest major (OL8).
- **No runtime floor guard** (same philosophy as the rejected ENA installer
  floor guard): the true floor depends on the `%packages` set and the update
  stream at build time, so the knowledge lives here and in the parity test
  (`t006` pins every template to `DISK_SIZE_GB="7"`), not in wrapper logic.
  If a build does outgrow the disk, anaconda / the in-guest update fails fast
  and visibly in the build log.
- **Validation status**: empirically confirmed by the 2026-07-13 real AMI build
  generation. OL6/OL7/OL9/OL10 built and registered at 7 GB. **OL8 was the
  build-time-peak counterexample**: its `UPDATE_TO_LATEST` transaction failed
  ("installing package linux-firmware-… needs 631MB on the / filesystem") —
  root-caused below and fixed via `LINUX_FIRMWARE="no"`, keeping 7 GB uniform.
  The OL8 rebuild then completed at 7 GB, and **all five 7 GB AMIs were
  boot-verified on real EC2** (2026-07-13, sosreports — see TESTING.md
  "Boot-E2E evidence note (2026-07-13)").

**The OL8 linux-firmware exception (measured, 2026-07-13).** EL8 is the only
major whose `linux-firmware` ships uncompressed firmware files — repodata
measurement: OL8 latest ≈ 695 MB package / **≈ 1.88 GB installed**, vs OL9/OL10
≈ 0.93 GB installed (xz-compressed). During `UPDATE_TO_LATEST` the upgrade
transaction transiently needs the new payload alongside the old one plus the
download cache, and on OL8 that peak alone (~2.5 GB) blew the 7 GB root's
remaining headroom ("needs 631MB more on /"), while the EL9/EL10 peaks are
roughly half and fit. The fix sets `LINUX_FIRMWARE="no"` in
`env.properties.aws-ol8` (upstream-native knob, wrapper passthrough
pre-existing): the removal runs in `distr::kernel_config` *before* the update,
freeing the GA firmware footprint so the transaction fits — **empirically
confirmed**: the 2026-07-13 OL8 rebuild with this knob completed at 7 GB and
registered. **Scope of the effect (observed)**: this is a *build-time
transaction-headroom* knob, not a final-content guarantee — the booted
2026-07-13 images (sosreports, all five majors) carry `linux-firmware` and
`kernel-uek-modules` for the target kernel, i.e. the packages re-enter through
the later provisioning flow. The re-entry mechanism was deliberately left
uninvestigated (user adjudication 2026-07-13; the build host had been
terminated) — it is functionally benign (real-boot E2E verified boot, ENA and
SSM on all five majors) and errs on the general-purpose side. The RPM-payload
facts stand regardless: `nvme`/`nvme-core` ship in `kernel-uek-core`, the
in-box `ena` ships in `kernel-uek-modules`, and the driving ENA is the DKMS
self-build either way (boot-verified: `ethtool -i` = `2.17.2g`). Re-open
trigger: if a future OL8 build overflows again even
without firmware, revisit `DISK_SIZE_GB` for OL8 as the fallback lever.

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
| `[ol-aws-ami-builder PATCH nitro-initramfs]` | `cloud/aws/provision.sh` | always (AWS cloud path) | Drop a presence-aware `/etc/dracut.conf.d` `add_drivers` file (only drivers whose `.ko` exists at this stage; `ena` is deferred to the ENA hook on slim OL8/9/10 — D.28) and regenerate the initramfs (Nitro boot requirement; Phase 6 CHECK 1 verifies the result) |
| `[ol-aws-ami-builder PATCH serial-console]` | `cloud/aws/provision.sh` | GRUB2 systems (OL7+; hook self-skips on OL6 GRUB Legacy) | AWS-recommended serial console in 3 layers: (1) `console=tty0 console=ttyS0,115200n8` on all entries via `grubby --update-kernel=ALL` (BLS-aware) + `GRUB_CMDLINE_LINUX`; (2) `GRUB_TERMINAL`/`GRUB_SERIAL_COMMAND` + `grub2-mkconfig`; (3) `serial-getty@ttyS0` enabled — see D.25 |
| `[ol-aws-ami-builder PATCH ena-driver-build]` | `cloud/aws/provision.sh` | `ENA_DRIVER_BUILD == 1` (default, OL6-OL10; `--skip-ena-driver` disables) | Inject the in-guest Amazon ENA driver self-build hook (DKMS; OL8/9/10 receive the host-resolved target via `ENA_DRIVER_VERSION`) — logged as `[OLAWS-ENA01]`, see A.13 |
| `[ol-aws-ami-builder PATCH ssm-agent-install]` | `cloud/aws/provision.sh` | `SSM_AGENT_INSTALL == 1` (default; `--skip-ssm-agent` disables) | Inject the in-guest Amazon SSM Agent install+boot-enable hook (OL6-OL10; all majors `latest`; non-fatal) — logged as `[OLAWS-SSM01]`, see B.11 |
| `[ol-aws-ami-builder PATCH awscli-install]` | `cloud/aws/provision.sh` | `AWSCLI_INSTALL == 1` (default) **and** `OL_MAJOR_VERSION` in `6/7/8` (`--skip-awscli` disables; OL9/OL10 out of scope) | Inject the in-guest AWS CLI v2 install hook (OL6 pinned `2.17.51`, OL7/OL8 `latest`; v1 excluded via versionlock; non-fatal) — logged as `[OLAWS-AWSCLI01]`, see B.13 |
| `[ol-aws-ami-builder PATCH sos-package]` | `distr/ol${N}-slim/ol${N}-ks.cfg` | `OL_MAJOR_VERSION >= 7` (always on; OL6 lists `sos` directly in its synthesized kickstart) | `_ks_add_sos_package`: insert `sos` (sosreport tooling) directly under the first `%packages` line, so every AMI can produce a sosreport out of the box — logged as `[OLAWS-SOS01]`; dies when the kickstart has no `%packages` section (assert-then-write) |
| `[ol-aws-ami-builder PATCH amazon-time-sync]` | `cloud/aws/provision.sh` | `AMAZON_TIME_SYNC == "yes"` (OPT-IN; default OFF — env key or `--enable-amazon-time-sync`) | Append a guest-side block that adds 169.254.169.123 as the preferred time source (`/etc/chrony.conf` on OL7-OL10, `/etc/ntp.conf` on OL6; the guest block detects which file exists and re-checks before appending) — logged as `[OLAWS-TIMESYNC01]`, see B.14 |
| `[ol-aws-ami-builder PATCH selinux-relabel-fallback]` | `bin/build-image.sh` | host libguestfs lacks the `selinuxrelabel` optgroup | Schedule a first-boot `/.autorelabel` instead of the offline relabel when the build host's libguestfs cannot relabel — see D.17 |

Phase 3 ends with two compensating controls for the tracked-at-HEAD upstream
(user decision 2026-07-11: always latest, never pinned): the
`[OLAWS-UPSTREAM01]` provenance record and the `[OLAWS-P3GATE01]` exit gate --
see the OLAWS code registry for their full contracts. Commissioned from the
OL7 2026-07-11 failure, where a build died ~30 minutes in with an opaque
"no operating systems were found" and left NO record of which upstream state
or patched-artifact bytes it had built from.

The `sed`-based substitutions (the OL6/OL7 guard removals, `kernel-uek-modules`,
`declare-g-ol6`) leave a `.bak` backup next to the modified file; the
marker-bracketed hook injections (`ol6-cloud-user`, `nitro-initramfs`,
`serial-console`, `ena-driver-build`, `ssm-agent-install`) are `>>`-appended blocks. Every patch is
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
   and IMDSv1-only metadata; see A.13 / D.27.) `cloud-utils-growpart-0.27-9.el6.x86_64`
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

`tests/cleancore/` holds six self-contained builders —
`build-cleancore-ol5.sh` / `-ol6.sh` / `-ol7.sh` / `-ol8.sh` / `-ol9.sh` / `-ol10.sh`
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
| 5 | **`oraclelinux:10` work-env** (floating `:10`, OCI v2 `curl` pull; no host installs) bootstraps an **EL5-native builder** (`rpm2cpio\|cpio` from the OL5 RPMs); rpm 4.4 / db4.3 | EL5 `yum` 3.2.22 + EL5 `createrepo` 0.4.11 | `file://` mirror (OL5/latest) | **slim-aligned curated essentials** (`@core` dropped; no `git`/`jq`; see "Package set" below) |
| 6 | floating **`6-slim` tag** (registry, latest 6.x = OL6.10, ships `yum`) -> **fallback** pinned `6-slim` git-raw rootfs -> **last** OL6.6 public-yum docker (rpm 4.8 / db4, TLS-modernized first) | `yum` | `latest` | **slim-aligned curated essentials** (`@core` dropped; see "Package set" below) |
| 7 | floating **`7-slim` tag** (registry, latest 7.x) -> **fallback** pinned `7-slim` git-raw rootfs; ships `yum` | `yum` | `latest` + `UEKR6` | **slim-aligned curated essentials** (`@core` dropped; see "Package set" below) |
| 8 | floating **`8-slim` tag** (registry, latest 8.x) -> **fallback** pinned `8-slim` git-raw rootfs; + `microdnf install dnf` | `dnf` | `baseos` + `appstream` | **slim-aligned curated essentials** (`@core` dropped; see "Package set" below) |
| 9 | floating **`9-slim` tag** (registry, latest 9.x) -> **fallback** pinned `9-slim` git-raw rootfs; + `microdnf install dnf` | `dnf` | `baseos` + `appstream` | **slim-aligned curated essentials** (`@core` dropped; see "Package set" below) |
| 10 | floating **`10-slim` tag** (registry, latest 10.x) -> **fallback** pinned `10-slim` git-raw rootfs; + `microdnf install dnf` | `dnf` | `baseos` + `appstream` | **slim-aligned curated essentials** (`@core` dropped; see "Package set" below) |

- **EL-native builder is mandatory.** rpm / BerkeleyDB versions must match the
  target so the in-guest rpm reads the rpmdb. **OL6 stays rpm 4.8 / db4 forever**
  (EOL), and an EL7 rpm 4.11 / db5 builder writes a db an EL6 rpm reads as **0
  packages** — so OL6 uses an EL6-native builder, giving permanent rpmdb
  compatibility. **OL5 is the deepest case** (rpm 4.4 / db4.3, `openssl` 0.9.8e =
  TLS-1.0): no distributed OL5 image carries a usable EL5 rpm over the normal
  channel, so OL5 instead bootstraps its EL5-native builder inside the OL10
  work-env (see the **EL5 specific** note below) — the OL10 rpm never writes the
  deliverable rpmdb (a modern rpm yields a db the in-guest OL5 rpm reads as 0).
- **Builder image acquisition (OL6-OL10): floating tag primary, pinned fallback.**
  Each OL6-OL10 builder first pulls its `N-slim` image by its **floating tag** from
  the Oracle container registry (`container-registry.oracle.com/os/oraclelinux:N-slim`)
  over the **OCI registry v2 API** — `curl`-only (anonymous token -> manifest/index
  -> amd64 sub-manifest if multi-arch -> gzip layer blobs), or a container runtime
  (`podman`/`docker` `pull` + `export`) as a fast path if one is present. This tracks
  the **latest N.x slim** with no commit bump. If the registry is unreachable the
  builder **falls back** to the byte-stable **pinned `N-slim` git-raw rootfs**
  (`oracle/container-images` at `CI_COMMIT`); OL6 then has a third fallback (the OL6.6
  public-yum image). The tag and the pinned rootfs are the same slim content stream,
  so the fallback is a faithful substitute. This mirrors the OL5 builder's OCI pull
  (shared, self-contained `oci_pull_rootfs()` in each builder; host `curl` uses `-k`
  only under `INSECURE_TLS=1`). The acquisition is **build-use only** and does not
  change the deliverable, which is the curated `--installroot` set against
  `yum.oracle.com/latest` regardless of the builder image's exact version.
- **OL6 builder source (6-slim primary, 6.6 fallback).** The builder is acquired
  in preference order: (1) the Oracle **`6-slim` rootfs (OL6.10)** pinned in
  `oracle/container-images` at the **same commit `0218ab4` the OL7/OL8 builders
  use** — a plain `FROM scratch + ADD rootfs.tar.xz` image (the same OL6.10 content
  as `ghcr.io/oracle/oraclelinux:6-slim`, fetched via the git-raw channel to match
  OL7/OL8 and avoid the OCI token/manifest dance); (2) **fallback** the legacy
  OL6.6 public-yum docker image. Both remain published (verified 2026-06-17); the
  git-raw rootfs is permanent at the pinned commit even though OL6 was dropped from
  the repo's `main`. See `tests/cleancore/REFERENCE-oracle-official-images.md` for
  the digests and the availability investigation.
- **OL6 builder modernization (fallback only).** The 2014-era OL6.6 image's
  NSS/curl cannot TLS-handshake modern `yum.oracle.com`, so on the **fallback** path
  the builder's own rpm 4.8 first installs host-fetched `el6_10`
  NSS/curl/ca-certs/openssl RPMs, then `yum` updates the package managers, after
  which `https` works. The **6.10-slim primary already ships that stack** (OpenSSL
  1.0.1e, NSS 3.36 line, `libcurl.so.4`), so the whole `el6_10` fetch +
  modernization is **skipped** on the primary path — its single most fragile step.
- **Package set: per-OL, slim-aligned.** **OL5 through OL10** all converge on a
  container-appropriate, slim-aligned set: `@core` is dropped (so no
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
  `enabled=0` (**OL5 omits `jq`** entirely — no EL5 `jq` build exists anywhere,
  not even in the EPEL 5 archive). **Package-locking is likewise a default:** the
  versionlock plugin
  (`yum-versionlock` on OL5, `yum-plugin-versionlock` on OL6/OL7,
  `python3-dnf-plugin-versionlock` on
  OL8–OL10) is an `INCLUDE` member on every clean-core, present in each OS's
  **standard** repo (OL6/OL7 `latest`, OL8–OL10 `baseos`) — so it is a plain
  `INCLUDE` add (no extra repo, unlike OL6 `jq`), and the base can hold/exclude
  packages out of the box, parallel to the install-test/production versionlock
  usage (e.g. `install-awscli.sh`'s v1 block). Its only named dependency is already
  in the base set (`yum` on OL6/OL7; `python3-dnf-plugins-core` on OL8–OL10), so it
  is a clean `+1` to each clean-core SBOM (the authoritative count is re-confirmed
  on the next clean-core rebuild). `systemd` is present (a hard dependency of full `dnf` on EL8/EL10, with
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
  (the `6-slim` OL6.10 rootfs primary, or the OL6.6 image fallback) doing a fresh
  curated `yum --installroot` install — not a trim of the builder image. (An
  `ol6-slim` *does* exist after all — OL6.10, at the pinned `0218ab4` — so the
  builder uses it as the primary base; see the OL6 builder bullets above.) Like EL7
  it carries plain `git` (no `git-core` split) plus `procps` (not `procps-ng`) and
  `nc` (not `nmap-ncat`); unlike the other clean-cores it **includes `net-tools`**,
  because EL6 has no standalone `hostname` package (the command ships in
  `net-tools`).
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
- **EL5 specific (OL10 work-env model).** OL5 cannot fetch its own packages
  (`openssl` 0.9.8e = TLS-1.0 vs. the TLS-1.2-only `yum.oracle.com`) and cannot be
  built by a modern rpm (its rpmdb must stay db4.3). So `build-cleancore-ol5.sh`
  uses **four** tagged environments rather than three: **[A] HOST** installs
  nothing and only pulls the latest distributed `oraclelinux:10` image (floating
  `:10`) over the **OCI registry v2 API with `curl`** (anonymous token → image
  index → amd64 manifest → single ~94 MB layer; no container runtime) into a
  throwaway **[W] OL10 work-env**; [W] does all TLS-1.2 work — fetch the OL5
  metadata + RPMs, resolve the closure (**dnf first**, against an empty installroot
  with `--releasever=5`; an embedded checksum-agnostic **Python resolver** is the
  fallback, which EL5's directory-`provide` semantics force in practice, e.g.
  `libxml2-python` requiring `/usr/lib64/python2.4`), and bootstrap the **[B]
  EL5-native builder** (`rpm2cpio | cpio` from the OL5 RPMs). The HOST then does a
  **single-level** EL5 `chroot` (no nesting) in which the EL5-native **`createrepo`
  0.4.11** writes the sha1/gzip repodata EL5 `yum` 3.2.22 can read (OL10's
  `createrepo_c` emits only sha256, which EL5 yum cannot checksum), and `yum
  --installroot` installs the **[C] clean-core** from the `file://` mirror. EL5
  `yum` has neither `--releasever` nor `--setopt`, so `tsflags=nodocs` is carried
  in the builder's `yum.conf`; and because EL5 yum exits non-zero on a successful
  `Complete!` under chroot, install success is gated on the rpmdb **package count**,
  not the exit code. The sandbox egress-proxy CA is seeded into the OL10 work-env
  trust store (a no-op on a real host). EL5 deltas vs. the others: **`git` and `jq`
  are omitted** (no EL5 build of either — `git` is EPEL-only and pulls a `perl`
  chain; `jq` has no EL5 build even in the EPEL 5 archive), versionlock is
  `yum-versionlock`, the release package is `oraclelinux-release`, and `procps` /
  `nc` (not `procps-ng` / `nmap-ncat`) plus `net-tools` (for `hostname`) mirror
  OL6. The image **carries the archived-EPEL-5 repo configuration**
  (user-required 2026-07-18, OL6-flow parity): `epel-release-5-4` is installed
  at build time (via the EL5 builder rpm against the deliverable root) and its
  repo files are rewired to the canonical Fedora archive
  (`https://dl.fedoraproject.org/pub/archive/epel/5/`) with the dead mirrorlist
  commented out and **every section `enabled=0`**. The service model is
  measured and permanent: the Fedora archive hosts 302-force plain http to
  https and EL5 openssl 0.9.8e tops out at TLS 1.0, so the guest can never
  fetch the archive directly — the config is a canonical, gpg-keyed reference
  that a harness enables against a modern-host mirror / host-side staging, the
  same doctrine as the OL5 base channel (and the reason for `enabled=0`: the
  epel files are the image's ONLY repo files, and a lone unreachable enabled
  repo would break every in-guest yum operation). No NSS CA dance is needed
  (the install path is `file://` only). EL5 is SysV-init, so `systemd` does
  not apply.
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
REST API) into the deterministic snapshot `ena-driver-releases.json` (schema
**1.2**), each version pre-checked for tarball fetchability (`tarball_available`
+ `tarball_http_status`, via the inline reuse-by-copy `url_check_status`). The
snapshot additionally carries the **ENA Express scope**: a top-level
`min_version` (default `2.8.0` — the express-ready floor, overridable via
`ENA_MIN_VERSION`) and, per version, `ge_min` (in the matrix's default sweep
scope) and `express_verdict` (`ena_express_verdict()`: `< 2.2.9` →
`not-ready`, `>= 2.2.9` → `bandwidth-only`, `>= 2.8.0` → `express-ready`; a
reuse-by-copy of the installer's source-of-truth helper, kept in agreement by
`tests/t021_enaexpress.sh`). This is the matrix **input**.

`run-ena-buildtest-matrix.sh` drives, for each target OL major (**6–10, all
first-class** and recorded in the ledger; the default `--ol` set — matching
the RHEL sibling project's five-major coverage — plus the **opt-in OL5**, see
the OL5 paragraph below) and each target ENA version,
the existing pieces **as separate executables**: `tests/cleancore/build-cleancore.sh`
(B.8) for the per-OL clean-core rootfs, then `install-ena-driver.sh
ENA_BUILDTEST=1` (A.13) for the per-version compile-test. The **default sweep
scope is the ENA Express era**: the release list's `min_version` (`2.8.0`, the
express-ready floor — ~29 of 70 releases) is applied as a hard floor
regardless of version source, because the AWS ENA generation update makes ENA
Express support a hard requirement for the produced AMIs. `--full` lifts the
floor (all releases), `--ena-min-version <x.y.z>` overrides it explicitly, and
the set stays narrowable (`--ena-versions`, `--pinned-only`) so a few cases
can run locally while the full in-scope sweep is meant for the user's
environment / CI. `--report-only` regenerates the reports (and the ledger's
derived fields) from the existing ledger with **no builds** — python3 only, no
root / containers / network.

**Ledger operating model (user-adjudicated 2026-07-18).** Three explicit modes
cover the evidence lifecycle: (1) **zero-base rebuild** — wipe the ledger and
reports in a scratch checkout, regenerate the release list, and re-sweep on
the then-latest kernels (with no ledger, every key is untested); (2)
**incremental append** — run without wiping: the kernel-primary dedup builds
only the diff (a new kernel re-tests everything for that OL; a new ENA release
tests only itself); (3) **merge** — `--merge-from <ledger.json>` (python3
only, like `--report-only`) unions an externally produced ledger (e.g. a
zero-base sweep from the user's environment) into the committed one on the
dedup key, then regenerates every report. Merge conflict policy: a key only in
the other ledger is adopted; a key in both with the **same** status keeps the
existing row unchanged (verdicts are deterministic; the fail-note first-error
capture is known to wobble benignly under parallel `make`, so the incumbent
note wins); a key in both with a **different** status is a **hard error**
naming every conflicting key (a determinism violation must be investigated),
unless `--merge-prefer ours|theirs` resolves it explicitly — on the error path
the base ledger is untouched. (Tested by `tests/t023_ol5ena.sh`.)

**OL5 (opt-in; build-test / PoC scope).** OL5 (OL5.11, UEK R2 `el5uek`) is an
additional matrix target that is **never in the default `--ol` set** — it runs
only via an explicit `--ol 5`. The floor semantics stay **uniform** across
OSes (no per-OS exception): the OL5 all-release evaluation is the separate run
`--ol 5 --full` (cardinality: ≤ 1 OS × the full release list × 1 frozen
kernel ≈ 71 cells; UEK R2 is the terminal `el5uek` line). OL5 differs from
OL6–10 in execution model only, not in evidence model: EL5 has **no in-guest
TLS 1.2 path** (openssl 0.9.8e tops out at TLS 1.0 — a protocol-level failure
`sslverify=false` cannot bypass), so `ol5_host_provision()` provisions the
container from the **host** (a fixed, frozen OL5/latest toolchain RPM closure
— exact NVRs proven by the 2026-07-18 20/20 sweep; `kernel-uek-devel` resolved
live via the update-gate probe with a pinned fallback; guest-side
`rpm -Uvh`; `/lib/modules/<kver>/build` wiring; the driver source staged per
the installer's OL5 pre-stage contract). Builds are **plain `make` only** (no
DKMS on OL5 by design) and every build applies the installer's `el5uek` shim
set (D.29), recorded per row in the ledger's `shims` field. Load-readiness
attestation is **not claimable** on OL5 (a devel-only provision has no
stock-module vermagic and no initrd), so `verify-ena-buildresults.sh` reports
OL5 rows as not load-ready (L4a) by design — real load proof is a future
real-Nitro workstream.

### Dedup ledger + per-OS reports

Evidence is two layers, **both committed** so the state persists (a commit *is*
the dedup state):

- **`buildtest-ledger.json`** (schema **1.2**) — one entry per
  `(osmajor, ena_version, kver)`
  carrying `status` (`ok`/`fail`), `dkms`, `ko`, `ko_version`, `ena_express`
  (the ENA Express readiness classification — a derived pure function of
  `ena_version`, back-filled across the whole ledger on every write incl.
  `--report-only`), `shims` (schema 1.2: the `el5uek` transform list the
  installer applied — D.29; `null` on OL6–10 and back-filled `null` on
  pre-1.2 rows), `reason`, `tested_at`. The triple is the **dedup key**,
  with **kver primary**: a combo
  already present (pass **or** fail) is skipped; a **new kernel** (kver changes)
  shares no key with the old rows so the whole set re-tests; a **new ENA
  release** is the only missing key so only the diff tests. The live kver per OL
  is taken from the build **result** — the first build of a run establishes it,
  so the pinned version is tried first as the per-run canary (one build per OL
  per run re-confirms the live kver rather than trusting a possibly-stale probe).
  As a defense-in-depth guard (independent of `install-ena-driver.sh`), the
  writer downgrades a recorded `ok` to `fail` whenever its `ko_version` does not
  match the requested `ena_version` (the build did not produce the requested
  module — e.g. an older installer that fell back to the stock in-tree `ena.ko`),
  so a masked build failure cannot enter the ledger as `ok` and silence the
  dedup gate. (Tested by `tests/t013_enaledgerguard.sh`.) **ENA Express era
  reset (2026-07)**: the working-tree ledger was reset to an empty schema-1.1
  skeleton — the retired pre-express all-release evidence (210 rows = 70
  versions × OL6/7/8) lives in git history only, since express-incapable
  releases no longer inform the product.
- **`RESULTS-ol<N>.md`** — a per-OS human report regenerated from the ledger,
  **newest kernel first** and opening with a `## Latest kernel <kver>` summary of
  the ENA versions that build on the newest kernel tested (so the latest result
  stays visible as kernels accumulate), followed by a standing ENA Express
  readiness note (the driver-version floors and the "ENI attribute, not a
  guest OS setting" caveat); each kernel is a section with an
  `ok`/total headline, a per-version table, and — when the kernel has any
  `fail` rows — a **Fail pattern analysis** subsection (RHEL-sibling r61 port)
  that groups consecutive fail versions sharing the same recorded reason into
  version-range rows, so a kernel-API breakpoint reads as one root cause
  instead of N identical table notes (the installer embeds the make.log first
  compiler error in the reason, giving each group a specific cause). A `fail` is recorded evidence (e.g. an ENA release too
  old for that kernel's kcompat), **not** a harness error, so the run exits 0;
  the harness fails non-zero only on an infrastructure error (missing tool, a
  clean-core build that will not produce a rootfs, ...). A build that emits no
  `[result]` line (its `install-ena-driver.sh` died before the result, or
  `unshare`/`chroot` failed) is recorded as a synthetic `fail` and the run
  continues — a single build never aborts the matrix — and any non-`ok` build's
  full log is preserved to `<cleancore-dir>/buildtest-ol<N>-ena_<ver>.log`.

### Update gate (default on; `--force` bypasses)

Before building anything for an OL, the matrix gates on whether the live upstream
has something the ledger has not covered, so a no-change OL costs only the probes
(no clean-core build). Two probes, compared to the ledger with the same `vkey`
version order used elsewhere:

- **kernel-uek** — the latest `kernel-uek` (x86_64) for the OL is read from
  `yum.oracle.com` (`repomd.xml` → `primary.xml.gz`, parsed with the python3
  standard library only — `gzip` + `xml.etree`, no extra package) under the
  fixed `OL → UEKR` map (`uekr_for()`: OL5 → `UEK/latest` — the OL5 channel
  predates the `UEKR<N>` naming (live-probed 2026-07-18) — OL6 → `UEKR4`,
  OL7 → `UEKR6`, OL8 → `UEKR7`, OL9/OL10 → `UEKR8`; source RPMs are ignored).
  The OL5 probe result is normalized (the trailing `.x86_64` is stripped)
  because EL5's modules-dir / devel-tree name carries no arch suffix — without
  this the extra component compared as a perpetually "new" kernel and the OL5
  gate could never skip (caught by container FT). UEK R2 is terminal, so the
  OL5 gate is in practice driven by new ENA releases only. The map pins
  the LATEST track each major ships (verified against `yum.oracle.com`
  repomd.xml, 2026-07-11: OL6=UEKR4 only, OL7=UEKR5/6, OL8=UEKR6/7,
  OL9=UEKR7/8, OL10=UEKR8 only) and must stay in lock-step with
  `install-ena-driver.sh`'s `bt_uek_repo` defaults — both are pinned by t011,
  so a track change is always a conscious, test-visible decision.
  **Maintenance rule**: when Oracle ships a new UEK track for a major, verify
  it on `yum.oracle.com`, then update the installer default, this map, the
  t011 pins, and this section together (the kernel-primary ledger makes every
  key on the new track a fresh, untested combination). **Bug history
  (2026-07-11)**: OL8 said `UEKR6` here AND in the installer while real OL8
  AMIs run UEKR7 (5.15) — the update gate watched, and 145 matrix cells
  tested, a track the AMIs do not ship; the divergence surfaced when the
  first real OL8 build targeted 5.15 and the "matrix ok / E2E path differs"
  contradiction was investigated. Prior OL8 ledger rows (UEK6-era kvers)
  remain as history. OL9 ships two UEK tracks in its default
  repo config — `UEKR7` (5.15, enabled by default) and `UEKR8` (6.12, present
  but disabled) — and this project targets `UEKR8` (see the evaluation
  findings below); `BT_UEK_REPO_OVERRIDE=ol9_UEKR7` (passed through to
  `install-ena-driver.sh`) runs a UEKR7-specific check instead. A kver greater
  than the ledger's max for that OL is a **new kernel**.
- **ENA** — the highest upstream `ena_linux` tag (`git ls-remote`, rate-limit-
  immune; falls back to the release-list JSON if the remote is unreachable). ENA
  is judged on the **latest version only** (releases are incremental); a latest
  not yet in the ledger for that OL is a **new ENA**.

A **new kernel or a new ENA** (or no ledger entry for the OL) runs the OL;
otherwise it is **skipped** with no build and the ledger untouched. A probe that
cannot determine the latest (DNS / timeout / TLS / 404 / parse) is **fail-open**
(the OL runs, to avoid missing data) by default, or **fail-closed** (skipped)
under `--strict`. `--force` bypasses the gate entirely (every requested OL runs)
and the per-combo dedup (every version re-tests); the QA preflight is **not**
affected (it runs in every mode). The dynamic "follow the latest UEKR" refinement
is deferred to a whole-project cleanup (D.11/D.12 fix the map for now).

### QA preflight (mandatory, every mode)

Before the version matrix, each OL builds **only its pinned ENA version** as a
smoke test that the clean-core rootfs and `install-ena-driver.sh` are healthy.
The preflight is **QA-only**: its result is **not recorded** in the ledger and
lives in a separate debug namespace. A clear failure **early-exits that OL** —
the matrix is not run and the ledger is left untouched — and a self-contained
diagnostic bundle `<cleancore-dir>/preflight-ol<N>-FAILED.log` (a header with
OL / pin / kver / reason / host context, then the full `install-ena-driver.sh`
output) is written for human or LLM analysis. Transient-looking failures (mirror
/ `kernel-uek` provision / network hiccups) are retried up to
`--preflight-retries` (default 2); a clear build/compile failure is treated as
real and not retried. The gate is mandatory in **every** mode (it guards data
quality, so it is never skipped); the matrix then re-builds the pin as the
recorded per-run canary, so the pin is built twice by design — the un-recorded
QA build, then the recorded run.

A container is kernel-less, so `ENA_BUILDTEST` provisions a full `kernel-uek` +
headers up front (A.13); the matrix inherits that and the B.8 host requirements
(root + `unshare`/`chroot` + network). The committed ledger and
`RESULTS-ol{6,7,8,9,10}.md` are the **first express-scoped five-major sweep** on
the maintainer's host (2026-07-05; 145 rows = 29 in-scope versions x OL6-OL10,
zero cells below the floor, zero `ko_version` mismatches): **OL6** UEK4
`4.1.12-124.48.6.el6uek` builds **6/29** — exactly the known `[2.8.6, 2.9.1]`
window (`2.8.0`–`2.8.5` fail on the UEK-detect patch site, D.11/D.12); **OL7**
UEK6 `5.4.17-2136.338.4.2.el7uek` builds **12/29** (`[2.12.2, 2.17.0]`) —
byte-reproducing the retired all-release run's `>= 2.8.0` subset on the same
kernel (UEK6 has a `2.8.0`–`2.12.1` kcompat gap); **OL8** UEK6
`5.4.17-2136.356.4.3.el8uek` (kernel advanced from the retired run's `.4.2` —
the kver-primary dedup re-tested the whole set as designed) builds **12/29**,
the same window as OL7; **OL9/OL10** UEKR8 `6.12.0-203.76.7.6.el{9,10}uek`
build **8/29** each (`[2.13.2, 2.17.0]`) — consistent with the 2026-07-03
evaluation on the same kernel (`latest` ok, `2.8.0` fail) and now precise: the
UEKR8 buildable floor is `2.13.2`. Fail reasons carry the make.log first
compiler error (the r61 port working in production). The retired pre-express
evidence (210 rows = 70 versions x OL6/7/8) lives in git history. An `ok` row
means the requested version compiled and DKMS-installed on that kernel —
**necessary, not sufficient**: real module load and device attach are proven
separately on real Nitro (B-T7/B-T8), and the read-only load-readiness verifier
below adds the vermagic / KABI gates. A later run grows the ledger as a clean
append (kver-primary dedup).

### OL9/OL10 evaluation findings (2026-07-03, ENA Express readiness)

A narrowed (`--ena-min-version`-scoped) run against fresh clean-core OL9/OL10
containers, done in support of an ENA Express readiness investigation,
established the following (not yet a full-release-list run — that is
follow-up work for the maintainer's environment):

- **OL9 and OL10 both build amzn-drivers latest successfully against UEKR8**
  (`2.17.0` on `6.12.0-203.76.7.6.el{9,10}uek.x86_64`, 2026-07-03; `2.17.2` on
  `6.12.0-204.92.4.2.el{9,10}uek.x86_64`, 2026-07-11 — that run also built
  `2.17.2` ok on OL7/UEK6 and confirmed it still failing on OL6/UEK4; its
  ledger refresh is deferred to the post-fix E2E re-run). `pin_for()`
  therefore pins the QA-preflight canary to `2.17.2` on OL7–10 (the
  confirmed-working newest release), not the ENA Express metrics floor
  `2.8.0`; OL6 stays at its `2.9.1` ceiling.
- **`2.8.0` fails to compile against UEKR8 on both OSes**, with an identical
  error: `ena_netdev.c` calls `xdp_do_flush_map()`, which upstream Linux
  renamed to `xdp_do_flush()` before the 6.12 baseline, and `2.8.0`'s
  `kcompat.h` predates the rename. The lesson: on UEKR8, "the minimum version
  that meets ENA Express's stated driver-version floor" is not a safe
  strategy — kcompat coverage for a *newer* kernel generally requires a
  *newer* driver release, the opposite of the naive "smaller is safer"
  intuition. `latest` is the correct default for OL9/OL10.
- **OL9/UEKR8 additionally needs a newer build-time gcc.** OL9's base-OS gcc
  (`11.5.0`) cannot compile against UEKR8's `kernel-uek-devel` (built with gcc
  `14.2.1`): DKMS aborts on an unrecognized flag
  (`-fmin-function-alignment=16`) before any driver-code issue is reached.
  Oracle's `kernel-uek-devel` for UEKR8 already declares an RPM dependency on
  `gcc-toolset-14` (confirmed via a real `yum install` transaction log), so
  `install-ena-driver.sh` prepends `/opt/rh/gcc-toolset-14/root/usr/bin` to
  `PATH` whenever `osmajor=9` and the target kernel is `6.x` — no separate
  package install, and OL9/UEKR7, OL10, and OL6/7 are untouched (their base
  gcc already matches).
- **OL8/UEKR7 needs the same treatment, one toolset generation earlier**
  (found by the first UEKR7 QA preflight, 2026-07-11, after the matrix moved
  from the UEKR6 default): UEKR7's `5.15.0-322.203.3.3.el8uek` is built with
  gcc `11.5.0` while OL8's base gcc is `8.5.0`, and the DKMS build dies on
  unrecognized flags (`-ftrivial-auto-var-init=zero`,
  `-fzero-call-used-regs=used-gpr`) before any driver code compiles.
  `kernel-uek-devel` for UEKR7 declares `Requires: gcc-toolset-11` (verified
  with `rpm -qR` in a container FT, 2026-07-12), so the installer prepends
  `/opt/rh/gcc-toolset-11/root/usr/bin` to `PATH` whenever `osmajor=8` and
  the target kernel is `5.15.x` — OL8/UEKR6 (5.4, built with the base gcc)
  is untouched. The toolchain fix alone is not sufficient on OL8/UEKR7: the
  build then hits the `IS_UEK`-gated `bpf_warn_invalid_xdp_action` kcompat
  guard, so the B.9 UEK-detection retarget now also applies on OL8 (see
  above). With both fixes, `2.17.2` builds and DKMS-installs as `2.17.2g`
  against `5.15.0-322.203.3.3.el8uek` (container FT, 2026-07-12; the
  harness-recorded proof lands with the post-fix E2E re-run).
- **OL10's developer-EPEL section name CHURNS per update release** (superseding
  the earlier finding that it "is `ol10_u1_developer_EPEL`" — true for 10.1 but
  not stable): measured 2026-07-16 from the `oracle-epel-release-el10` package
  history and the live yum server, revision 1.0-2 shipped
  `[ol10_u0_developer_EPEL]` → `.../OL10/0/...`, revisions 1.0-5..1.0-6
  (latest) ship `[ol10_u1_developer_EPEL]` → `.../OL10/1/...`, and — with
  OL10.2 released — `.../OL10/2/developer/EPEL/` was still HTTP 404 (a 10.2
  system runs on the 10.1 EPEL; old-minor paths like `/OL10/0/` stay
  published). Any fixed section name therefore breaks SILENTLY at the next
  rename — the exact failure mode of the original unversioned-name guess
  ("No match for argument: dkms"). The fixed-u1 wiring is replaced by the
  live discover → verify → finalize mechanism (`setup_epel_ol10`; see the
  ENA self-build DKMS bullet for the full contract), FT-validated 2026-07-16
  in an OL10 chroot against the live server across four scenarios: shipped-u1
  alive/constructed-u2 dead (today's lag), dead shipped file → constructed
  self-minor → disposable repo → real `dkms 3.4.1-1.el10_1` install →
  cleanup, forced-dead shipped section explicitly disabled, and all-dead →
  loud rc 1. OL10's platform dnf is 4.20 (dnf4; measured from repo metadata
  and the bootstrapped chroot), so the probe's core-dnf4 syntax is stable
  for this OS-gated path.

These findings are now **wired into the production pipeline**:
`build-ol-aws-ami.sh` injects the self-build hook on OL6–OL10 by default
(host-side latest resolution `[OLAWS-ENA02]`, `ENA_DRIVER_VERSION`
pass-through, `-ena<x.y.z>` AMI naming — see B.1/B.4 and A.13). Remaining
follow-up: the first express-scoped five-major matrix sweep (the ledger was
reset for the ENA Express era), and a real AMI build/boot E2E with an
OL8/9/10 self-built driver (`[C]3`).

### Load-readiness verification (external, read-only)

`ENA_BUILDTEST` answers "did the requested version compile + DKMS-install?". A
separate, **read-only** tool answers the deeper question "would that module
actually load on its target kernel?" without touching the build path:
`tests/ena/verify-ena-buildresults.sh` reads the matrix ledger plus a small
**verification bundle** the build side preserved, and emits its own report.
It composes as a distinct pass — build → verify → build — so that no condition
or judgement lives inside the build script; module integration stays delegated
to DKMS, and a reader cannot perturb the build.

The bundle is small (the data needed is already in the artifacts): per built
version only the `ena.ko` varies; `Module.symvers` + the kernel `vermagic` +
the `initramfs` listing are shared per kver. Per ok ledger row the verifier
runs, against that kver:

- **L4a vermagic-match** (gate) — the module's `vermagic` equals the kernel's
  (read from the `.ko` via `modinfo`, or `strings` where kmod is absent); a
  mismatch would fail at `insmod`.
- **L4b symbol-crc-kabi** (gate) — every symbol the module requires is present
  in `Module.symvers` with a matching CRC (needs kmod to dump the module's
  required symbols; skips loudly where kmod is unavailable).
- **L3 initramfs-inclusion** (info, non-gating) — whether `ena.ko` is in the
  initramfs the build produced. `ena` absent is expected and not a defect:
  initramfs composition is DKMS/dracut territory, root is on nvme, and ena loads
  post-pivot. Reported, never acted on.
- **L5 module-load+device** (skip) — a real `modprobe` + device check needs the
  UEK kernel running on real Nitro (B-T8); not containerizable.

`load_ready` is decided by the gates only; a **missing bundle artifact for an ok
row is a fail** (load_ready unknown), never a silent skip — the same no-false-ok
discipline as the install-time verify. The verdict logic is pure and unit-tested
(`tests/t016_enaverifyresults.sh`).

The build side emits this bundle. `run-ena-buildtest-matrix.sh` preserves, after
each build (a dumb `cp` — no load-readiness judgement, no branch on the build's
ok/fail status), the DKMS-built `ena.ko` to
`<bundle>/modules/ol<N>-ena_<ver>-<kver>.ko` and the shared per-kver
`Module.symvers` + `kernel.vermagic` (a **stock** in-tree module's vermagic, so
the L4a compare stays independent of the freshly built module) + an
`initramfs.list` (`lsinitrd`, else `cpio -t`) to `<bundle>/kver/<kver>/`. The
bundle dir defaults to `<cleancore-dir>/verify-bundle` (`--bundle-dir` overrides)
and accumulates exactly like the ledger: per-version `ena.ko` added, shared
per-kver files overwritten idempotently. A failed build leaves no DKMS module to
copy, so the producer never fabricates one — the verifier flags the gap itself.
The `cp` layout is contract-tested against the verifier's read-paths by
`tests/t017_enabundle.sh` (no real build needed).

---

## B.10 SSM Agent install+run test matrix (`tests/ssm/`)

A dev/CI harness, structurally the same as the ENA matrix (B.9), that determines
per OL major (6/7/8/9/10) which AWS SSM Agent versions **install AND run** in a
disposable clean-core container, and evaluates them against the AWS requirement
**SSM Agent `>= 3.3.3598.0`** (from 2026-06-16 SSM Run Command drops the legacy
`ec2messages` endpoint; agents at/above this use `ssmmessages`). **OL5 is a
MEASURED EXCLUSION** — unlike ENA (B.9) and AWS CLI v2 (B.12), OL5 is
deliberately NOT wired into this matrix: the entire AWS-supported band is
triple-walled against the terminal `el5uek` line at the package-install layer
and the kernel layer alike (adjudicated 2026-07-18; the full evidence record
is D.31). It reuses
`tests/cleancore/build-cleancore.sh` for the rootfs and drives
`install-ssm-agent.sh SSM_INSTALLTEST=1` per version. Manual / on-demand (NOT a
`run-all.sh` tier); production integration into the AMI pipeline is deferred
(decided from the report) — `build-ol-aws-ami.sh` does not install SSM today.

**The compatibility surface is `(kernel, glibc) x ssm_version`.** The agent is a
Go program: the latest RPM is statically linked (no glibc dependency) so its
runnability is gated by the kernel (the Go runtime's minimum kernel rises per
toolchain); older versions are dynamically linked (Requires glibc) so the OS
glibc gates install/run. The ledger dedup key is `(osmajor, ssm_version, kver)`
with **kver PRIMARY**, where `kver` is the **OL UEK** read from the rpm db
(`rpm -q kernel-uek`, provisioned into the container the same install-at-test-time
way the ENA matrix provisions it) — so a new OL UEK re-tests every version,
mirroring ENA. `test_host_kernel` (the runner kernel the binary actually ran on),
`glibc`, `go_version`, and the derived `min_kernel` (kernel-axis proxy) are
per-entry fields, measured/recorded empirically.

**Test depth.** `install-ssm-agent.sh` (a) installs the RPM with `rpm -Uvh` —
the local file, no repository, so the agent's only real dependency (glibc) is
enforced against the rpm DB and the EL6 yum-over-HTTPS NSS quirk never arises;
the unsigned-to-us NOKEY warning and the container's missing init system (the
%post upstart/systemd start) are benign — then (b) runs the binary locally
(`amazon-ssm-agent -version`, no AWS/IMDS) to prove the Go runtime + linked libs
load. `status=ok` requires install AND run (and the installed version to match
the request). The ec2messages-vs-ssmmessages endpoint behaviour is real-instance
runtime, not container-testable; the running VERSION vs `3.3.3598.0` is the
in-container proxy (as the ENA compile-test proxies boot/`ethtool`, B-T7/B-T8).

**Fidelity (verified 2026-06-14).** The **glibc axis is faithful** — the
container's real OL glibc fails-to-install/run a version needing newer glibc. The
**kernel axis is NOT** faithful in a container: the container shares the host
kernel, so the binary executes on the runner's kernel (recorded as
`test_host_kernel`), not the OL's UEK, and the Go minimum-kernel never trips on a
modern runner. `kver` is the **OL UEK**, provisioned into the container and read
from the rpm db (`rpm -q kernel-uek`, the same install-at-test-time path as ENA)
so the report records the kernel a real OL instance runs; rather than pretend the
run tested it, the matrix surfaces a **static kernel-axis proxy** from each
release's go.mod `go` directive. The
release list records, mirroring its rpm fields, `go_version` plus
`go_version_available` (a `go` directive was found) and `go_mod_http_status` (the
go.mod fetch status -- `404` is a pre-go-modules tag with no go.mod, distinct from
a `200` carrying no `go` line), and the `min_kernel` proxy; the ledger likewise
stores `min_kernel` per entry. The proxy mapping (`go_min_kernel`) is one logic,
reuse-by-copy in `list-ssm-releases.sh` and the matrix, kept in lock-step by
`tests/t018_ssmverdict.sh`. go.mod is the source of truth (the spec's
`BuildRequires: golang` is stale). A faithful kernel verdict needs a
kernel-matched runner or a
real instance. (Empirically, even the latest's `go 1.25` floor of Linux 3.2 is
met by OL6 UEK4 `4.1.12`, so the kernel is not the OL6 blocker; glibc + packaging
are.)

**Modes.** Default tests only versions meeting the minimum (`>= MIN_SSM_VERSION`,
default `3.3.3598.0`, the boundary included) — the question "is remediation
possible here?". `--full` tests every version, for the all-NG case, to show where
`(kernel, glibc)` caps out (a detailed ledger). `--min-version` overrides the
threshold.

**Update gate.** Unlike ENA (a kernel module, gated on the UEK probe), the SSM
agent runs on the host kernel in a container (so its runnability does not depend
on the OL UEK), so the gate is the SSM-VERSION probe (`git ls-remote`): run the OL
if upstream's latest is newer than the ledger's max for it; a new OL UEK is still
handled by the kver-PRIMARY dedup (`kver = rpm -q kernel-uek`). Fail-open by
default, `--strict` fail-closed, `--force` bypasses.

**Headline output.** Per OL/kver, `RESULTS-ol<N>.md` opens with a summary of the
AWS Run Command ec2messages deprecation (paraphrased, with doc links), then a
**test-environment** block (`env_kernel` = `rpm -q kernel-uek`, `env_glibc` =
`rpm -q glibc`, `test_host_kernel` = the runner kernel the binary ran on), and a
per-version table with category-prefixed columns (`agent_go_version`,
`compat_min_kernel`). It gives the max install+run version and the verdict vs
`3.3.3598.0`: `compliant-capable` (max `>=` min, remediation possible),
`ec2messages-only` (max `<` min — cannot be remediated by an agent update,
affected by the 2026-06-16 deprecation), or `none`.

**Scripts + tests.** `install-ssm-agent.sh` (`SSM_INSTALLTEST` mode, mirroring
`install-ena-driver.sh`'s `ENA_BUILDTEST`); `tests/ssm/list-ssm-releases.sh` (the
version list + per-version RPM availability + the go.mod fields `go_version`,
`go_version_available`, `go_mod_http_status`, and the `min_kernel` proxy);
`tests/ssm/run-ssm-installtest-matrix.sh` (the matrix). The pure verdict/proxy/
filter logic (`ssm_ge`, `go_min_kernel`, `ssm_in_scope`, `ssm_compliance`) is
unit-tested by `tests/t018_ssmverdict.sh` (no container/network). The release list
(`ssm-agent-releases.json`, the deterministic matrix INPUT) and the ledger
(`ssm-installtest-ledger.json`) + `RESULTS-ol{6,7,8,9,10}.md` ARE committed: the
release list is the full upstream snapshot (207 versions, RPM availability, go.mod
`go_version`); the committed ledger and reports are a **real** default-mode
(`>= 3.3.3598.0`) run (55 rows = 11 versions x OL6/OL7/OL8/OL9/OL10; the
2026-07-13 five-major sweep), OL6 UEK4 `4.1.12-124.48.6.el6uek` / OL7 UEK6
`5.4.17-2136.338.4.2.el7uek` / OL8 UEK6 `5.4.17-2136.357.3.2.el8uek` / OL9 UEK7
`5.15.0-322.203.3.3.el9uek` (glibc 2.34) / OL10 UEK8
`6.12.0-204.92.4.2.el10uek` (glibc 2.39). All five majors were run on
the maintainer's host (uniform `test_host_kernel` `6.12.0-211.28.1.el10_2`); since
the agent runs on the host kernel in a container the run does not exercise the OL
kernel axis, but each install+run is real and the recorded `kver` is the
provisioned OL UEK in each case. Each OL is **9/11 ok**: `3.3.3883.0`
and `3.3.4364.0` are the only fails — their RPMs are not published at the S3 URL
(HTTP 403), an upstream availability gap, not an install/run incompatibility — so
every OL's verdict is **compliant-capable** (max install+run `3.3.4793.0` >=
`3.3.3598.0`). A later run in the maintainer's env / CI (and a kernel-matched
runner for a faithful kernel axis) grows the ledger via the kver-PRIMARY dedup
append.

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
- [ ] Every new `${VAR:?...}` / `${VAR:=...}` assignment is paired with a `log_info` line confirming the resolved value (per A.4)

### Functional checks

- [ ] `./build-ol-aws-ami.sh --help` exits 0 and lists every supported switch
- [ ] `./build-ol-aws-ami.sh --env env.properties.aws-ol10 --build-only` (or another supported template) completes through Phase 5 on a properly-prepared builder host, or the reason it cannot be exercised is documented
- [ ] Phase banners `========== Phase N: ...` appear in stdout for every executed phase
- [ ] Phase 0 self-diagnosis (`detect_ec2_environment` / `guide_ec2_kvm_issue`) emits the appropriate Case A/B/C message on a non-KVM host (per B.1)
- [ ] When `ISO_URL` references OL7, the OL7 warning banner appears in `load_env` output
- [ ] When `ISO_URL` references OL6, the OL6 warning banner appears in `load_env` output and the three runtime modifications (Patch #1, Patch #2, synthesized `distr/ol6-slim/`) are applied in Phase 3
- [ ] Phase 6 Nitro readiness pre-check (`NITRO_PRECHECK`, default `enforce`) runs after the VMDK is produced: it `die`s on a blocking finding (NVMe host / ENA / fstab / bootloader) before the upload phases, is fail-open when inspection tools are absent, and is suppressible via `warn`/`off` (see A.13). Verified against a known-good image (e.g. OL10 PASS)

### Documentation checks

- [ ] `README.md` mentions every new env-property key, command-line switch, and output artifact
- [ ] `README.ja.md` is line-for-line equivalent in structure (table layout and section order match)
- [ ] `README.md` carries the **Disclaimer** section near the top (per A.16)
- [ ] `README.md` carries the **License** section near the top (per A.16)
- [ ] `README.ja.md` carries equivalent **免責事項** and **ライセンス** sections
- [ ] `SPEC.md` reflects the change in the relevant Part A / Part B section
- [ ] If a new pitfall was discovered during development, it is added as a new `D.NN` entry in Part D
- [ ] A `LICENSE` file exists at the repository root and the script header banner names the AI tool used in the generation (per A.2)

### Cross-template checks

- [ ] All five `env.properties.aws-ol{6,7,8,9,10}` templates share the same key set (no orphan keys; documented optional keys are explicitly absent only when intentional — see B.3)
- [ ] `S3_BUCKET` matches across every template (`my-oracle-linux-ami-import-bucket` — single bucket / single `vmimport` IAM role across all OL versions, per B.3 §3 and §9.4a)
- [ ] `AWS_REGION=""` is consistent across templates (resolution chain documented in A.13 / B.3)
- [ ] `UPDATE_TO_LATEST="yes"` is consistent across templates (CVE-coverage default per B.3)
- [ ] Every template's `ISO_CHECKSUM` value matches `https://linux.oracle.com/security/gpg/checksum/` for the corresponding ISO

---

## B.11 SSM Agent production install (`--skip-ssm-agent`)

By default (`SSM_AGENT_INSTALL=1`) the wrapper produces an **SSM-managed AMI**:
Phase 3 appends a marker-bracketed hook (`[ol-aws-ami-builder PATCH
ssm-agent-install]`) to `cloud/aws/provision.sh` that writes `install-ssm-agent.sh`
verbatim into the guest and runs it during provisioning, so the AMI boots with an
installed, enabled Amazon SSM Agent. `--skip-ssm-agent` (`SSM_AGENT_INSTALL=0`)
leaves the hook out, producing an AMI with no SSM Agent — the two distinct build
purposes, exactly parallel to `--skip-ena-driver`.

**Why this is on by default.** AWS Systems Manager Run Command stops serving the
legacy `ec2messages` endpoints from **2026-06-16**; only agents **>= 3.3.3598.0**
speak the newer `ssmmessages` channel (see B.10 for the full deprecation note and
the per-OL install+run evidence). Shipping a compliant agent by default means a
freshly built AMI is SSM-manageable out of the box.

**Per-OL version.** `install-ssm-agent.sh` holds the source-of-truth map
`SSM_AGENT_VERSION_OL<major>`: **every OL major (OL6-OL10) follows the
`/latest/` S3 alias**. OL6 was pinned to a fixed, install+run-verified build
through 2026-07-13 (the EL6 NSS/glibc combination was judged the fragile one, so
a moving target was considered riskier there), but the B.10 install+run sweeps
have shown 11 consecutive releases ok on OL6 glibc 2.12 with no fragility
materializing, so the pin was lifted (user adjudication, 2026-07-13). **Re-pin
policy**: if an OL6 breakage ever materializes, OL6 reverts to a pin on the
newest install+run-verified version from the B.10 ledger. An explicit
`SSM_AGENT_VERSION` overrides the map. The wrapper's
`_ssm_pin_for_major()` reads the same map for the AMI name/description marker
(single source of truth, mirroring `_ena_pin_for_major()`).

**Install mechanism.** The in-guest installer fetches the per-OL RPM with a plain
`curl -fsSL` (normal TLS trust — the same fetch model as the ENA hook; `-k` is a
test-mode-only switch via `INSECURE_TLS`, never used in production) and installs
the LOCAL file with `rpm -Uvh` (the agent's only real dependency is glibc, already
present, so no repo metadata is needed — this also sidesteps the EL6
yum-over-HTTPS NSS quirk). It then enables the service for boot per init system:
`systemctl enable amazon-ssm-agent` on OL7/OL8/OL9/OL10, and `chkconfig` (SysV) or
the shipped upstart job on OL6. The boot-enable runs **only on the production
path** (`SSM_INSTALLTEST != 1`), so the B.10 install+run test matrix and its
committed ledger are untouched.

**Non-fatal by design.** Unlike the ENA driver — which is Nitro network-critical
(no driver, no `eth0`, the instance is unreachable) — the SSM Agent is management
tooling: an instance with no agent still boots and is reachable. A transient fetch
failure should therefore not abort an otherwise-good AMI, so the injected hook
traps the installer's failure to a warning and provisioning continues. (The ENA
hook, by contrast, is fatal.)

**AMI naming + version resolution.** When enabled, the AUTO-default `AMI_NAME`
appends `-ssm${version}` and the description appends `, Amazon SSM Agent
${version}`, so an SSM-managed AMI is distinguishable pre-launch. Because
"latest" is unsuitable for a persistent artifact, the AMI identity carries a
**concrete version only, or no ssm marker at all** (parity with the awscli
marker — never the word `latest`). The wrapper resolves the `/latest/` alias in
`_ssm_resolve_latest()`, layered: **layer 1 (primary) reads the S3 release
channel's own `latest/VERSION` file** — the exact content of the alias the
guest installs, which by construction can neither lead nor lag the install —
and **layer 2 (fallback)** reads GitHub's `amazon-ssm-agent` `releases/latest`
tag and VERIFIES that version's RPM on S3 with a HEAD (tags can lead S3
publication — e.g. `3.3.3883.0` / `3.3.4364.0` / `3.3.4851.0` were tagged
while 403 on S3), logging the outcome as `[OLAWS-SSM02]`. On total failure the
marker is **omitted** (`SSM_AGENT_RESOLVED` stays empty; the final report says
so explicitly instead of printing a bare `latest`). Regression record
(2026-07-18): the original GitHub-first strategy failed closed exactly when
the tag led S3 — the OL9.8/OL10.2 real E2E registered `-ssmlatest` AMI names
(GitHub said `3.3.4851.0`, its RPM was 403, while `latest/VERSION` answered
`3.3.4793.0`) — which is what motivated the layer-1-primary redesign and the
omit-on-failure contract; pinned by t004 mocked-curl scenarios and t020
identity-invariant asserts. This is **display/identity only**: the in-guest
install path is unchanged (the hook still installs the per-OL target, i.e. the
`/latest/` S3 alias for OL6-OL10), so install behaviour does not depend on the
build host's network. The final report prints a `SSM Agent:` line with the
resolved version (or `not installed` for `--skip-ssm-agent`). An explicitly
set `AMI_NAME`/`AMI_DESCRIPTION` is left untouched (`:=`).

**Validation status.** OL6-OL10 install+run is matrix-verified (B.10), and the
SSM-enabled AMI is **boot-validated end to end on real EC2 for all five
majors**: 2026-07-13 (baked `3.3.4793.0` installed AND running on every
major — upstart on OL6, systemd active on OL7-10) and again 2026-07-18
(first-load log line = the AMI-name version on OL7-10; OL7-10 on
current-generation `c8a`). Runtime caveat, measured 2026-07-18: an
account-level SSM agent auto-update can replace the baked agent minutes
after boot (observed `3.3.4793.0` → `3.3.4851.0` via the agent's own
updater, from a channel other than the one the image installs from), so
any name=artifact verification MUST compare the **first-load version**
(the agent's initial log line, or the package manager's "Upgraded (old)"
entry) — never the `rpm -qa` state at collection time. The remaining open
item is the SSM Run Command round-trip.

## B.12 AWS CLI v2 install+run test matrix (`tests/awscli/`)

A dev/CI harness, structurally the same as the SSM matrix (B.10), that determines
per OL major (**6/7/8**, plus the **opt-in OL5** — see the OL5 paragraph below)
which AWS CLI **v2** versions **install AND run** in a
disposable clean-core container. It reuses `tests/cleancore/build-cleancore.sh`
for the rootfs and drives `install-awscli.sh AWSCLI_INSTALLTEST=1` per version.
Manual / on-demand (NOT a `run-all.sh` tier); production integration into
`build-ol-aws-ami.sh` is deferred (install-test tooling only, mirroring SSM's B.10
→ B.11 staging). The v1 OL-repo `awscli` package is **out of scope** for the
matrix; the production path blocks it via versionlock so a later `yum`/`dnf` cannot
shadow the v2 bundle.

**The compatibility surface is `glibc x awscli_version`, and the glibc axis is
FAITHFUL.** AWS CLI v2 ships a self-contained zip bundle that **bundles its own
Python**, so it does not use the OS Python — but the bundled interpreter and its
C-extension `.so`s are built against a **manylinux glibc**, so the OS glibc gates
whether the bundle installs/runs. Per AWS's *Linux Support Updates for AWS CLI v2*
(2024-09-16), current v2 is **manylinux2014 (glibc 2.17)** and supports glibc
≥ 2.17; glibc ≤ 2.16 must pin v2 **≤ 2.17.49**. AWS documents that as the boundary,
but the install+run matrix settled OL6 empirically: OL6 (glibc 2.12) installs/runs
through **2.17.51** (the last build whose bundled `.so`s need only `GLIBC_2.5`;
2.17.52 is the first to require `GLIBC_2.17`); OL7 (2.17, the floor) and OL8 (2.28)
run current. Because the
container's real OL glibc (`rpm -q glibc`) is exactly what the bundle links
against, this install-test is **conclusive for glibc** — unlike the SSM/ENA kernel
axis. The ledger dedup key is `(osmajor, awscli_version, kver)` with **kver
PRIMARY** (`kver` = the OL UEK from `rpm -q kernel-uek`, provisioned the same
install-at-test-time way as SSM, so a new OL UEK re-tests every version);
`test_host_kernel` is the runner kernel the binary actually ran on.

**OL5 (opt-in; install-test / PoC scope; 2026-07-18).** OL5 (glibc **2.5**) is
an additional matrix target that is **never in the default `--ol` set** — it
runs only via an explicit `--ol 5`. A 12-version boundary sweep on the OL5.11
clean-core measured **7/7 "runs" for the ≤ 2.17.51 band** and a hard
glibc-too-old wall from 2.17.52 — so the OL5 ceiling pin is **2.17.51, the
same pin as OL6, for the now-measured same reason**: the 2.17.52 Python
3.11 → 3.12 rebase jumps the bundle's empirical `.so` floor 2.5 → 2.17 (the
launcher additionally demands `GLIBC_2.7`/`2.14`; loader errors captured
verbatim). This measurement empirically settles WHY the OL6 pin sits at
2.17.51 (the pre-existing empirical boundary above is the same event seen
from the OL6 side). OL5 differs in execution model only: EL5 has **no
in-guest TLS 1.2 path**, so the matrix stages the requested bundle zip into
the container from the host (`ol5_stage_zip`, cached and `unzip -t`-verified;
the installer's `/usr/src/<zip>-<ver>.zip` pre-stage contract) — nothing else
needs provisioning (unzip 5.52 ships in the OL5 clean-core). The `kver`
record is the live-probed terminal `OL5/UEK/latest` NVR passed via the
`AWSCLI_OL5_KVER` contract (**probed, not provisioned** — the kernel is not
this matrix's compat axis and the EL5 kernel RPM's `%post` initrd scriptlets
are unsafe in a chroot; pinned fallback `2.6.39-400.297.3.el5uek.x86_64`). A
chroot `runs` does **not** prove the real UEK R2 kernel runtime (the bundled
CPython may impose a minimum-kernel constraint — a future real-instance
stage), and no W1 launch wrapper ships (D.30). The existing report generator
needed zero changes: it derives the "capped at `2.17.51`" verdict for the
glibc-2.5 rows by itself.

**Ledger operating model.** Identical to the ENA matrix (B.9): zero-base
rebuild and incremental append are native, and `--merge-from <ledger.json>`
(+ `--merge-prefer ours|theirs`; python3-only) unions an externally produced
ledger on the dedup key with the same adjudicated conflict policy (adopt new
keys; same-status keeps the incumbent row; different-status is a hard error
naming every conflicting key, base ledger untouched, unless `--merge-prefer`
resolves). (Tested by `tests/t024_ol5awscli.sh`.)

**Bundled Python + empirical glibc (per-entry, free).** The install-test already
unzips each bundle, so two facts are recorded for free and survive the
glibc-too-old case (no need to execute the binary): `bundled_python` — the bundled
CPython, read offline from `aws/dist/libpython3.X.so*` and refined to the full
patch from `aws --version`'s `Python/X.Y.Z` when it runs; and `min_glibc_measured`
— the bundle's **empirical** glibc floor, the max `GLIBC_x.y` symbol version
required across its `.so`s, read with a dependency-free `grep` of the version
strings embedded in the binaries (no `readelf`/binutils in the clean-core; it
matches `readelf` exactly). The documented heuristic `min_glibc` (≥ 2.17.50 →
2.17, else 2.5) is recorded alongside as a cross-check, and `python_eol` records
the bundled Python's documented end-of-life. Empirically: v2 2.0.x–2.17.51 require
`GLIBC_2.4`–`2.5` (so OL6 runs them), while v2 ≥ 2.17.52 requires `GLIBC_2.17` — the
glibc floor tracks AWS's manylinux build base, not the Python version per se.

**Test depth.** `install-awscli.sh` (a) installs with `aws/install` (the bundled
interpreter runs; a too-old glibc fails the loader here — the faithful "won't
install on this glibc" signal), then (b) runs **`aws --version` + `aws configure
list`** locally (no AWS creds / no IMDS) to prove the bundled Python + glibc-linked
`.so`s load and a CLI session + botocore import succeed. `status=ok` requires
install AND both run checks (and the installed version to match the request;
`latest` may resolve to any version). `aws sts get-caller-identity` needs creds +
network and is the real-instance confirmation, not container-testable.

**Lifecycle (the bundled Python is frozen).** The bundled CPython is not
independently patchable; the only way to a newer (still-supported) Python is a
newer v2 — and a glibc-capped OS caps the v2 version, hence the bundled Python,
hence its support horizon. The headline forward risk: OL6 caps at v2 `2.17.51` =
Python `3.11.9` (security-support end **2027-10-31**); after that OL6 has no
in-place remediation (newer v2 needs glibc 2.17 the OS lacks). `RESULTS-ol<N>.md`
therefore opens with the glibc rationale, then a **static**, provenance-stamped
(verified date + source sites; Q2 option b) **Python-EOL table** and the **OS's own
EOL/EOS**, then per kver a verdict (`current` / `capped at <ver>` / `none`) and a
per-version table carrying `bundled_python`, `python_eol`, and `compat_min_glibc
(measured / heuristic)`. The pure verdict/lifecycle logic (`awscli_ge`,
`awscli_min_glibc`, `awscli_in_scope`, `awscli_verdict`, `python_eol`) is
unit-tested host-only by `tests/t019_awscliverdict.sh`, which also locks the
reuse-by-copy `awscli_min_glibc` in `list-awscli-releases.sh` to the matrix. The
release list (`awscli-releases.json`), ledger (`awscli-installtest-ledger.json`)
and `RESULTS-ol{6,7,8}.md` are produced by a real maintainer-env matrix run /
network probe (a long-running clean-core + network task) and are not generated in
this authoring environment.

## B.13 AWS CLI v2 production install (`--skip-awscli`)

By default (`AWSCLI_INSTALL=1`) the wrapper installs **AWS CLI v2** into the guest
on **OL6 / OL7 / OL8**: Phase 3 appends a marker-bracketed hook
(`[ol-aws-ami-builder PATCH awscli-install]`) to `cloud/aws/provision.sh` that
writes `install-awscli.sh` verbatim into the guest and runs it during
provisioning, so the AMI boots with AWS CLI v2 as the standard CLI.
`--skip-awscli` (`AWSCLI_INSTALL=0`) leaves the hook out — the two distinct build
purposes, parallel to `--skip-ssm-agent`.

**Scope: OL6/OL7/OL8 only.** OL9 and OL10 install AWS CLI v2 from their **default
package manager** (`dnf`), so the wrapper leaves them out of scope — the hook is
not injected on OL9/OL10 (an info line is logged) and `--skip-awscli` has no
effect there. This is narrower than the SSM hook (OL6-OL10) and matches
`install-awscli.sh`'s own OL6/OL7/OL8 test/pin scope.

**Why this is on by default.** AWS CLI **v1** is increasingly unsupported (it is in
maintenance and AWS steers users to v2); the OL repos still ship a v1 `awscli`
package. Shipping v2 by default — and excluding the v1 package via versionlock so
a later `yum`/`dnf` cannot shadow it — means a freshly built AMI has a current,
supported AWS CLI out of the box.

**Per-OL version.** `install-awscli.sh` holds the source-of-truth map
`AWSCLI_VERSION_OL<major>`: **OL6 is pinned to `2.17.51`** (the empirically highest
install+run build on OL6 glibc 2.12 — the last `GLIBC_2.5` / Python-3.11.9 build;
see B.12), and **OL7/OL8 follow the moving `latest` bundle**. An explicit
`AWSCLI_VERSION` overrides the map. The wrapper's `_awscli_pin_for_major()` reads
the same map for the AMI name/description marker (single source of truth,
mirroring `_ssm_pin_for_major()`).

**Install mechanism.** The in-guest installer fetches the per-OL bundle zip with a
plain `curl -fsSL` (normal TLS trust — the same fetch model as the ENA/SSM hooks;
`-k` is a test-mode-only switch via `INSECURE_TLS`, never used in production),
installs it with the bundle's own `aws/install`, runs `aws --version` +
`aws configure list` locally to confirm it loads, and then excludes the OL-repo
`awscli` (v1) via versionlock (`yum`/`dnf` plugin). AWS CLI v2 is a self-contained
binary bundle (no service), so unlike SSM there is **no boot-enable** step.

**Non-fatal by design.** Like the SSM Agent (and unlike the Nitro-network-critical
ENA driver), AWS CLI v2 is utility tooling: an instance with no CLI still boots and
is reachable. A transient install failure should therefore not abort an
otherwise-good AMI, so the injected hook traps the installer's failure to a warning
and provisioning continues.

**AMI naming + version resolution.** When enabled (OL6/OL7/OL8), the AUTO-default
`AMI_NAME` appends `-awscli${version}` and the description appends
`, AWS CLI v2 ${version}`, so an AWS-CLI-bearing AMI is distinguishable pre-launch.
The marker always carries a **concrete `x.y.z`**: for OL6 it is the pin
(`2.17.51`); for OL7/OL8 the wrapper **resolves the `latest` bundle to a concrete
version** via `_awscli_resolve_latest()` — it enumerates the v2 tags with
`git ls-remote --tags` (the same auth-free method as `list-awscli-releases.sh`,
since aws-cli does not publish GitHub "releases"), walks them newest-first, and
returns the highest whose bundle zip is actually published on the CDN (a HEAD; the
newest tag can lead CDN publication). This is **display/identity only**: the
in-guest install path is unchanged (the OL7/OL8 hook still installs the `latest`
bundle), so install behaviour does not depend on the build host's network. If
resolution fails (offline, e.g. a `--build-only` run with no network), the AMI
identity **omits the awscli marker entirely** rather than printing the
non-concrete word `latest`; the final report then shows `version unresolved`. The
final report prints an `AWS CLI:` line (`v2 ${version} (installed)`,
`not installed (--skip-awscli)`, or `not installed (out of scope; OL9/OL10 use the
default package manager)`). An explicitly set `AMI_NAME`/`AMI_DESCRIPTION` is left
untouched (`:=`).

**Validation status.** OL6/OL7/OL8 install+run is matrix-verified (B.12). The
production hook injection + the AMI name/description identifier are host-gate
verified (parse / shellcheck / `tests/t007_idempotency.sh` marker count); a real
AMI build + boot with AWS CLI v2 present is the natural [C]3 follow-up (B-T8).

---

## B.14 Amazon Time Sync opt-in (`--enable-amazon-time-sync`)

DEFAULT OFF. Time configuration belongs to the end user of the AMI, so the
builder ships the distribution defaults (`pool 2.pool.ntp.org` via chrony on
OL7-10, ntpd on OL6) untouched unless explicitly asked.

When enabled — `AMAZON_TIME_SYNC="yes"` in the env file or the
`--enable-amazon-time-sync` switch (the switch wins; it forces `yes` after
`load_env`) — Phase 3 appends a marker-bracketed guest block
(`[ol-aws-ami-builder PATCH amazon-time-sync]`, logged as
`[OLAWS-TIMESYNC01]`) to `cloud/aws/provision.sh` that adds the link-local
**Amazon Time Sync Service (169.254.169.123)** as the *preferred* time
source: `server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4` in
`/etc/chrony.conf` (OL7-10) or `server 169.254.169.123 prefer iburst` in
`/etc/ntp.conf` (OL6). The guest block detects which config file exists (no
per-OL branching in the wrapper) and re-checks for `169.254.169.123` before
appending, so it is idempotent on both the wrapper side and the guest side.
The distribution pool lines are deliberately kept as fallback (minimal diff);
the AMI name/description are NOT affected (this is a config toggle, not an
identity-bearing component).

Origin: the 2026-06-16 E2E generation’s sosreports showed the public NTP pool
as the only time source; AWS best practice on EC2 is the link-local service.
Kept opt-in per user decision (2026-07-11).

---

## B.15 OL5 build target (`distr/ol5-slim/` synthesis + full host-supply)

**Status: implemented 2026-07-19; gate-checked (t025 + P3GATE OL5 branch); real
EL5 anaconda contact and real EC2 boot E2E are PENDING.** Treat every
first-contact surface (kickstart acceptance, the virt-customize rpm
transaction, Nitro boot) as unproven until that evidence lands (the
gate-maturity lesson: new gates/shapes are untested until first real-world
contact with each major).

### B.15.1 Model

OL5 extends the OL6 runtime-synthesis precedent (B.4) with a **full
host-supply pipeline**, because EL5's openssl 0.9.8e tops out at TLS 1.0 and
the guest can reach no current repository at any stage:

1. **Synthesis.** Phase 3 writes `distr/ol5-slim/` (`env.properties`,
   `image-scripts.sh`, `ol5-ks.cfg`, `provision.sh`) from embedded heredocs
   (`EOF_OL5_ENV` / `EOF_OL5_IMG` / `EOF_OL5_KS` / `EOF_OL5_PROV`).
2. **Host staging.** Phase 3 downloads and magic-verifies every guest
   artifact into `distr/ol5-slim/files/{rpms,src}/` (cache:
   `${WORKSPACE}/ol5-stage`): the frozen 11-RPM ENA build-toolchain closure
   (MUST stay byte-identical to the matrix's `OL5_TOOLCHAIN_RPMS` — t025
   enforces this), `kernel-uek`/`-devel`/`-firmware` (UEK R2; newest NVRs
   live-resolved from the frozen `OL5/UEK/latest` channel, pinned fallback
   `2.6.39-400.297.3.el5uek`), the 9-RPM EPEL5 cloud-init 0.6.3 closure +
   `gdisk` (frozen NVRs; the EPEL5 archive is immutable), the ENA source
   tarball (`ena_linux_<pin>.tar.gz`) and the AWS CLI v2 bundle zip.
   Upstream's standard files channel carries the tree into the guest
   (`stage_provisioning_files` → `provision.d/distr/` →
   `virt-customize --copy-in` → `/tmp/provision.d/`). No upstream changes.
3. **Guest execution (`[OLAWS-OL5S1]`).** A source-time executor appended to
   `cloud/aws/provision.sh` (BEFORE the ENA/awscli hooks, so their
   prerequisites exist when they run) installs in load-bearing order:
   `/etc/modprobe.conf` aliases first (`scsi_hostadapter nvme`,
   `scsi_hostadapter1 xen-blkfront`, `eth0 ena` — the kernel RPM's own
   `%post`→`new-kernel-pkg`→`mkinitrd` reads the scsi_hostadapter aliases,
   so nvme is baked into the initrd by the package install itself) →
   `DEFAULTKERNEL=kernel-uek` → ONE `rpm -Uvh --replacepkgs` transaction over
   the staged set → `/usr/src` staging (ENA tarball + awscli zip; an empty
   src/ is legitimate under `--skip-ena-driver` + `--skip-awscli`) → hard
   asserts: el5uek kernel present; `/boot/initrd-<kv>.img` contains
   `nvme.ko` (one `mkinitrd --with=nvme --with=xen-blkfront` remediation
   retry, then FATAL); the grub.conf `default=` entry boots el5uek;
   cloud-init installed.
4. **Overrides (`[OLAWS-OL5S2]`).** Appended redefinitions (bash
   last-definition-wins) replace the upstream yum/dracut-based
   `cloud::install_aws_packages` / `cloud::cloud_init` with verify-only
   EL5-safe bodies. The upstream definitions become dead parse-only code
   (their bash-4 expansions are harmless unexecuted).

### B.15.2 Hard constraints (all enforced)

| Constraint | Enforcement |
|---|---|
| x86_64 / BIOS / MBR / GRUB Legacy | env template + EL5 reality |
| `ROOT_FS=ext3` | `distr::validate` (ext4 = 5.6 tech preview behind a boot flag; xfs/lvm/btrfs roots unsupported by anaconda-11.1) |
| `UEK_RELEASE=2` | `distr::validate` (the only UEK line for OL5; in-box nvme — the Nitro precondition, measured from the kernel payload) |
| `UPDATE_TO_LATEST=no` | `distr::validate` (no reachable in-guest repository) |
| `CLOUD_USER=ec2-user` | `load_env` forces it (cloud-init 0.6.3 `setup_user_keys` is getpwnam-only; the kickstart pre-creates exactly ec2-user) |
| IMDSv2-only rejected | `normalize_imds_support` (0.6.3 DataSourceEc2 = plain IMDSv1; D.27 class) |
| SSM Agent forced OFF | `load_env` (measured triple-walled exclusion; B.10/B.11 context + D.31) |
| SHA256 `ISO_CHECKSUM` required | `load_env` fails fast when empty (upstream accepts SHA1/SHA256 only; the kernel.org mirror publishes MD5SUMS — the mirror MD5 `8af2121088c7e6f5ebdb6d5900403240` is recorded in the env template as the operator cross-check) |
| Guest-side code bash-3.2/POSIX | t025 mechanical scan of every guest block (non-comment lines) |
| Disk bus `virtio` (not virtio-scsi) | Phase 3 marker patch on `bin/build-image.sh` (the EL5 installer kernel has no virtio-scsi; both the 5.11 installer kernel and UEK R2 carry plain virtio) |

### B.15.3 Kickstart shape (EL5 / anaconda-11.1)

Zero `%end` (anaconda-11.1 would consume a literal `%end` inside `%packages`
as a package name); exactly two section openers (`%packages` + `%post`);
`install` + `cdrom` + `text` + `key --skip`; `rootpw --iscrypted *` (no
`--lock`); `firewall --enabled --ssh`; no `services`/`cmdline`/`ignoredisk
--only-use`/`--ondisk`/`bootloader --timeout`; LABEL-based ext3 partitions
(`/boot`, swap — removed by `SETUP_SWAP=no` — and a `--grow` root);
`%post` logging via an exec redirect into `/root/ks-post.log` (the
`common::ks_log` path; the redirect is the chosen single mechanism and also
captures `set -x` -- the real 0.43 parser does accept `--log`, see the D.32
grammar record). `%post` pre-creates `ec2-user` (locked password +
direct sudoers line — EL5 sudo predates a stock `#includedir`), bakes the
GRUB-Legacy serial-console layers (D.25 pattern), the `ol-aws-growroot`
one-shot, and the virt-sysprep stubs (D.20 pattern). The P3GATE
`_p3_validate_ks` has an explicit OL5 branch for this shape (the
balanced-`%end` rule keeps guarding OL6-10 unchanged).

### B.15.4 Root growth without growpart (`ol-aws-growroot`)

EL5 has no `cloud-utils-growpart`. A baked SysV one-shot (`chkconfig:
2345 08 92` — before cloud-init) implements the **growpart decision model**
(adjudicated 2026-07-19; grounded in the real cloud-utils `growpart`
implementation):

- **PRIMARY execution criterion = the actual disk/partition state, every
  boot.** sysfs geometry (disk size; the root partition's start/size; a
  name-independent walk proving root is the LAST partition) decides whether
  growth is needed AND possible. A free tail at or below the growpart-style
  fudge (2048 sectors = 1 MiB) is `NOCHANGE`. Guards read the on-disk table
  (`sfdisk -d`): only a plain Linux entry (`Id=83`) is ever grown (`ee`
  would mean GPT), and any extended partition (`5`/`f`/`85`) is refused —
  neither is a builder layout.
- **SECONDARY criterion = the attempt marker
  (`/var/lib/ol-aws-growroot.attempt`), a reboot-loop breaker only.** It is
  consulted AFTER the geometry decision: growth-needed + marker means the
  previous attempt failed → log loudly, never reboot again (the operator
  removes the marker to re-arm). On the success path the next boot's
  `NOCHANGE` **self-heals** the marker away, so a LATER EBS enlargement
  grows again — real growpart semantics.
- **Write mechanism = the growpart model, adapted to EL5 util-linux 2.13:**
  `sfdisk -d` dump → a single size-field edit of the root entry → apply with
  `sfdisk --no-reread --force` (the busy-disk kernel re-read is deferred to
  the reboot), with the old dump saved as the restore vehicle
  (`/var/lib/ol-aws-growroot.sfdisk-backup`) and a **post-write verify**
  re-dump (restore on mismatch). The entry is addressed by its **start
  sector**, never by device name — util-linux 2.13's sfdisk composes NVMe
  partition names without the `p` separator, so name-matching would break
  exactly on Nitro.
- **One reboot is REQUIRED on this kernel line** (not a style choice):
  online resize of a mounted root partition needs `BLKPG_RESIZE_PARTITION`
  (kernel 3.6+); UEK R2 is 3.0.36 — the same wall that made the RHEL6 era
  use initramfs-time growroot. After the single reboot, cloud-init's
  `resizefs` grows ext3 online.
- `gdisk` is STAGED as a diagnostic tool but never used against the MBR
  disk — writing GPT there would break GRUB Legacy. (The fdisk-keystroke
  pipeline of the first implementation was superseded by this adjudication;
  the dump-edit-apply model preserves every other table field byte-exactly
  and is verifiable.)

The decision logic is behaviorally tested (t025): a fake-sysfs +
mocked-sfdisk harness drives the real extracted script through the grow,
post-grow self-heal, marker-secondary, sub-fudge `NOCHANGE`, and Id-guard
paths.

### B.15.5 E2E protocol (operator side)

First contact: `SERIAL_CONSOLE="yes"` + `--build-only` to watch anaconda
live (the OL7-diagnosis protocol). Boot targets: Nitro c5/m5-class first
(nvme root + self-built ENA), Xen-generation instances as the measured
fallback (xen-blkfront/xen-netfront are in-box and alias-wired). Expected
first-boot behavior includes one automatic growroot reboot when the EBS
volume exceeds the image size.

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
coding rule in A.5 (explicit `return 0` after a final `[[ ... ]] &&` list) was added in response to this incident.

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
(Scoping note, 2026-07-18: measured exception for OL6 only — the frozen
UEK4 kernel panics on AMD Zen3+ instance generations regardless of boot
mode; see the B.1 constraints and the TESTING.md 2026-07-18 evidence
note. OL7-OL10 hold as stated, proven through `c8a`.)

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
unconditionally and is a no-op there. See A.15 "Caller pattern for libguestfs"
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
   A.13).
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
initramfs. See A.13.

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
writes `/etc/dracut.conf.d/02-ol-aws-nitro.conf` and regenerates the initramfs
for the installed kernel with `dracut -f`. Since D.28 the drop-in is
**presence-aware** (only drivers whose `.ko` exists at the hook's stage; `ena`
is appended later by the ENA hook on the slim majors). The drop-in also makes
future in-instance kernel updates keep the forced drivers. See A.13 ("Nitro
initramfs drivers").

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
self-build (D + A.13) uses — installs the built module into `/extra` (or
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
boot-readiness regression). See A.13 ("Nitro initramfs drivers" / ENA self-build).

**Provenance is now also enforced (defense-in-depth).** CHECK 2 no longer passes
on mere presence when a self-build was performed: if `ENA_BUILD_VERSION` is set
(an in-guest self-build ran -- OL6/OL7 with the default on) but the effective
`ena.ko` is the stock in-tree `/kernel` copy rather than the DKMS `/updates|
/extra` module, the self-build did not take effect and the AMI would ship the
stock driver instead of the requested pin -- a **`FAIL`**. When no self-build was
requested (`--skip-ena-driver`, OL8+ in-distro, OL9+) the stock module is the
expected outcome and still passes. The verdict is the pure `_ena_check2_ok`
(unit-tested by `tests/t014_enacheck2.sh`). With `install-ena-driver.sh` now
aborting on a failed build (it requires the installed module version to match the
request), this image check is a guard for manual builds / other installers /
future regressions rather than the primary gate.

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
(idempotent). A host-runnable regression tier (B-T9, `tests/t008_hooktiming.sh`)
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

## D.28 nitro-initramfs hook `dracut` FAILs on slim OL8/9/10 — forced an `ena` that cannot exist at its stage

**Symptom.** Every OL8/9/10 build log carries, from the nitro-initramfs hook:

```
dracut-install: Failed to find module 'ena'
dracut: FAILED:  /usr/lib/dracut/dracut-install ... -m nvme nvme_core ena
[nitro-initramfs] WARNING: dracut -f failed for <kver>
```

The build continues (the hook is best-effort), and default builds still end
with a correct initramfs — but the message is a false alarm, and the defect is
real underneath (observed in the 2026-07-13 OL8 real-build log).

**Root cause — a staging impossibility, not a transient.** The hook is
appended to `cloud/aws/provision.sh` as top-level statements, so it executes
at **source time** (the same mechanism as D.26), before the ENA hook's DKMS
build. On the slim OL8/9/10 builds the in-box `ena` is not on disk at that
stage — observed directly in the 2026-07-13 OL8 build log (`[in-box ENA] …
file=<not found>`); the RPM-payload split explains it (verified at
`5.15.0-322.203.3.3.el8uek`: `nvme`/`nvme-core` live in `kernel-uek-core`,
`ena` lives in `kernel-uek-modules`, which is not staged at the hook's point
in the flow). So at the hook's
stage there is **no `ena` on disk to force** — the unconditional
`add_drivers+=" nvme nvme-core ena "` drop-in made the hook's own `dracut -f`
fail, leaving the initramfs *without the forced nvme* at that stage. Default
builds were rescued by the ENA hook's later regen (post-DKMS, `ena` present,
drop-in resolves). But on **`--skip-ena-driver` builds of OL8/9/10** there is
no later regen: the initramfs never gets the forced `nvme`, and the persistent
drop-in still names the absent `ena` — so **every future in-instance `dracut`
run (e.g. a kernel update) fails too**. That is the latent defect.

**Fix.** Two-stage, presence-aware staging: (1) the nitro hook probes each
candidate (`nvme`, `nvme-core`, `ena`) with `find /lib/modules/<kver> -name
'<drv>.ko*'` and writes only the present ones into the drop-in, logging absent
ones as *deferred* — its `dracut -f` now always succeeds; (2) the ENA hook
appends `ena` to the same drop-in (idempotent `grep -qsw` gate) **before**
invoking the installer, whose own `dracut -f` (which runs after the DKMS
install) bakes `ena` into the initramfs. Final image: drop-in and initramfs
carry nvme+ena on default builds, nvme-only on `--skip-ena-driver` builds
(where no `ena` exists at all), and OL6/OL7 (in-box `ena`) are unchanged.

**Prevention.** `t008` (the hook execution-timing tier) pins both stages:
statically (presence probe present, unconditional 3-driver literal absent, the
emitted ena append precedes the installer invoke) and behaviourally (extracted
hook body against a mock `/lib/modules` with and without `ena`; the emitted
append line applied twice stays single).

---

# Part E — Logging & Diagnostics

The wrapper emits a single, uniform log stream to the console and (by default)
to a persistent file. Three orthogonal axes describe every line.

## D.29 OL5/UEK R2 (`el5uek`) needs a source shim set — kcompat has no UEK R2 knowledge

**Symptom.** Every amzn-drivers release fails to compile against
`kernel-uek-devel` 2.6.39-400/el5uek out of the box (a 2026-07-18
investigation measured **vanilla 0/20** across 1.1.2–2.9.1), with three
distinct first errors: a missing `linux/kconfig.h`, redefinitions of symbols
the kernel already provides, and (1.5.2/1.5.3) a Makefile `$(error)` rejecting
any UEK that is not UEK3 3.8.13.

**Root cause (single, unifying).** UEK R2 reports `2.6.39` but is a Linux
3.0.36-base kernel carrying Oracle backports of 3.1–3.5-era APIs
(`netdev_features_t`, `ether_addr_equal`, `ethtool_rxfh_indir_default`, …).
`kcompat.h` gates purely on `LINUX_VERSION_CODE` with RHEL/SLE/Ubuntu
exceptions and knows nothing about UEK R2 — `el5uek` headers define no
`RHEL_RELEASE_CODE` (measured: every `!(RHEL_RELEASE_CODE)` guard fired), so
every failure is either (a) a backport colliding with kcompat's own compat
definition, or (b) kcompat assuming an API a mainline 2.6.39 lacks, where
RHEL6 is rescued by an explicit `RHEL_RELEASE_CODE` branch and UEK R2 is not.
RHEL6 also *ships* `linux/kconfig.h` (a Red Hat backport), which is why the
existing el6 evidence never hit the missing-header class.

**Fix.** `apply_el5uek_shims()` in `install-ena-driver.sh` (OL5 branch only;
OS-separation) applies the **exact transform set the investigation proved
sufficient — 20/20 sampled releases build with plain gcc 4.1.2**: S1 installs
an upstream-equivalent `kconfig.h` stub into the devel tree (RHEL6-parity,
sentinel-marked); S2 suppresses kcompat's `netdev_features_t` typedef; S3a
pins the proven `IS_UEK`-unset kcompat configuration deterministically (the
OL6/OL8 retarget-to-`BUILD_KERNEL` patch of D-history would set `IS_UEK` for
`el5uek` — the opposite of the proven configuration); S3b neutralizes the
UEK3-only `$(error)`; P1/P2 rename kcompat's colliding copies (call sites then
use the kernel's identical implementations); P3 degrades the `l4_rxhash` line
(perf-hint flag only); P4 renames the intra-kcompat `netdev_rss_key_fill`
duplicate (an upstream blind spot on the pure-old-mainline path); P5a–c
degrade the DMA `SKIP_CPU_SYNC` attr path to plain `dma_unmap_page`
(perf hint; semantics-safe on x86 coherent DMA); P6/P7 append a self-guarded
tail block (the raw `DMA_ATTR_SKIP_CPU_SYNC` fallback and an exact
`dma_zalloc_coherent` re-implementation). Every transform is exact-string,
grep-before-edit, applied only when present, EL5-guest-safe (bash 3.2 + GNU
sed 4.1; **no `sort -V`** — EL5 coreutils 5.97 lacks it, caught by container
FT), and the applied list is emitted in the result JSON (`shims`) into the
schema-1.2 ledger.

**Degradation disclosure.** P3/P5/P6 drop performance hints (the RSS L4-hash
flag; the DMA skip-cpu-sync attr), never correctness; the rest are
exact-semantics collision removals or upstream re-implementations. An `ok` is
a compile proof only — Nitro load/traffic for OL5 is unproven.

**Prevention.** `tests/t023_ol5ena.sh` pins every proven pattern string, the
EL5-safety rule, the matrix wiring (pin/channel/gate/closure), and the merge
policy.

## D.30 OL5 AWS CLI v2: the /proc-resolution false lead, and the measured 2.17.52 glibc wall

**Symptom (investigation, 2026-07-18).** In the first OL5 feasibility sweep,
the 2.1.x–2.7.x band (bundled Python 3.8/3.9) failed via the `aws/install`
symlink with `Error loading Python lib '<bindir>/libpython3.N.so.1.0'` while
2.0.30 and 2.13.0+ ran — initially (mis)read as an EL5 symlink-resolution
defect needing a launch wrapper ("W1"), and a wrapper fallback was adjudicated
on that basis.

**Correction (measured, same day).** An A/B on the **identical installed
binary** nailed the real cause: the ad-hoc investigation harness ran a plain
`chroot` **without `/proc` mounted**. That bootloader generation self-resolves
via `/proc/self/exe` and falls back to the symlink directory only when `/proc`
is absent; with `/proc` mounted the same symlink runs perfectly. The matrix
execution model (`unshare` + `/proc`, identical to OL6-8) and any real
instance always mount `/proc`, so the entire ≤ 2.17.51 band runs via the
standard symlink and a wrapper could never fire. **W1 was re-adjudicated OUT**
(a mechanism that cannot fire in the target environment is not shipped);
`tests/t024_ol5awscli.sh` pins its absence. Lessons: (1) an ad-hoc harness is
itself part of the measurement — reproduce failures under the REAL execution
model before designing around them; (2) `/proc` is load-bearing for
PyInstaller-frozen binaries of that generation.

**What stands (measured).** The 2.17.51 → 2.17.52 boundary is a genuine,
permanent glibc wall (Python 3.12 rebase; `.so` floor 2.5 → 2.17; launcher
`GLIBC_2.7`/`2.14`) that explains the OL6 pin and sets the identical OL5
ceiling. Shared-code EL5 hazards found and fixed on the way (behaviour
identical on OL6-8): `sed -E` in `detect_bundled_python` (EL5 sed 4.1.5 has
only `-r`; the usage error killed the whole install under `set -e` — now
pure-bash) and the kver read's `sort -V` stderr noise (EL5 coreutils 5.97 —
now silenced; value path untouched).

## D.31 OL5 SSM Agent: a measured, triple-walled exclusion (no `--ol 5` wiring)

**Question (2026-07-18).** After the OL5 opt-in integrations of ENA (D.29) and
AWS CLI v2 (D.30), does the SSM Agent earn the same wiring? Scope was
user-adjudicated to the AWS-supported band only (`>= 3.3.3598.0`, the
matrix's `MIN_SSM_VERSION`): **11 versions, 9 with fetchable RPMs**
(3.3.3883.0 / 3.3.4364.0 are upstream-unavailable per the committed release
list) — small enough that the investigation covered the FULL population, not
a sample.

**Answer: no — the band is closed at two independent layers (adjudication:
do not wire; record the measurement).**

1. **Package-install layer (measured, verbatim).** Every band RPM uses an
   xz payload with sha256 file digests; EL5's rpm 4.4 refuses the
   transaction outright:
   `rpmlib(FileDigests) <= 4.6.0-1 is needed` and
   `rpmlib(PayloadIsXz) <= 5.2-1 is needed`. There is no in-family install
   path; a workaround would be host-side payload extraction, which BYPASSES
   the vendor's own `%pretrans` kernel guard (below) — actively subverting
   the package contract.
2. **Kernel layer (three independent attestations, all measured).** The
   band's kernel floor is **3.2**: (a) every binary carries the ELF note
   `for GNU/Linux 3.2.0` (Go 1.24/1.25 toolchain floor); (b) the RPM
   `%pretrans` scriptlet explicitly verifies kernel `>= 3.2` and refuses
   otherwise; (c) the committed `ssm-agent-releases.json` already records
   `min_kernel: "3.2"` for every band version. UEK R2 reports 2.6.39 on a
   Linux **3.0.36** base — below the floor on both counts, and the line is
   terminal, so the gap is permanent.
3. **What DOES hold (and why it changes nothing).** The band binaries are
   `static-pie` with **zero `GLIBC_` references** — the glibc axis that
   decided the AWS CLI v2 case is vacuous here, and all 9 fetchable versions
   answered `amazon-ssm-agent -version` inside an OL5.11 clean-core chroot
   (matrix execution model, unshare + /proc). That result rides the modern
   HOST kernel and proves only the never-in-doubt userland axis.

**Contrast that drove the adjudication.** ENA and AWS CLI v2 each have a
genuinely usable OL5 band (20/20 with the D.29 shims; 7/7 up to the 2.17.51
glibc wall) — a matrix row records something real. The SSM supported band has
**no usable version**: a ledger row could only ever record a chroot-userland
artifact for software that the real target kernel can never run and the real
target rpm can never install. Under the evidence discipline ("AMI name =
reality"), that row would mislead; the measured exclusion is the honest
asset.

**Prevention / traceability.** This entry and the B.10 pointer are the
record; the raw evidence (per-version payload/linkage table, the verbatim
rpm refusal, the `%pretrans` excerpt, the 9/9 chroot run log) lives in the
2026-07-18 session artifacts. If AWS ever ships a legacy-kernel agent line
or the supported floor drops below the 3.2-era toolchains (neither is
expected), the question can be reopened with the same three-layer probe.

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
| `OLAWS-UPSTREAM01` | upstream oracle-linux provenance on every build: full HEAD SHA + commit date/subject on the console, and `${WORKSPACE}/upstream-provenance.txt` with the applied wrapper patch markers + sha256 of every patched artifact (upstream is tracked at HEAD by design, so a failing build must always leave behind exactly what it built from) |
| `OLAWS-P3GATE01` | Phase-3 exit gate over the ACTUALLY patched artifacts on the real build host, before any install work: structural kickstart conformance (single `%packages`, single in-section `sos`, marker uniqueness, `%end` balance over ALL pykickstart sections incl. `%addon`, bootloader shape, partitioning presence — static `part` lines OR the EL8-family dynamic pair of a `%include` line whose target is generated inside a `%pre` body), hook-bracket pairing + heredoc termination + `bash -n` on `cloud/aws/provision.sh` and `image-scripts.sh`. Any finding dies in seconds (with the provenance file cited) instead of ~30 opaque minutes in anaconda. ksvalidator, when installed, runs ADVISORY-only (it exits 1 even on the pristine upstream kickstart -- the pre-existing `--nobase` deprecation is counted -- so its rc cannot gate) |
| `OLAWS-CFG01` | resolved feature knobs (`[DEBUG]`: ENA/IMDS/skip flags) |
| `OLAWS-NVM01` | Nitro initramfs-drivers hook injected (presence-aware add_drivers; ena deferred to the ENA hook when not in-box — D.28) |
| `OLAWS-ENA01` | in-guest ENA driver self-build hook injected |
| `OLAWS-ENA02` | ENA self-build target resolved for the AMI identity + guest hook (installer pin, or host-resolved amzn-drivers latest / concrete fallback pin on OL8-10) |
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
   # (R10-U<N> below stands for whatever update release the OL10 template's
   #  ISO_URL pins at copy time — the only release-bound text in the template.)
   sed -i 's/ol10/ol11/g; s/OL10/OL11/g; s/R10-U<N>/R11-U<M>/g; ...' env.properties.aws-ol11
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

---

## D.32 OL5 build-target design record — evidence, adjudications, first-contact surfaces

**Date:** 2026-07-19. The OL5 AMI build target (B.15) was designed from
scripted, machine-grounded probes; this entry freezes the evidence and the
binding adjudications so future revisions do not re-litigate or regress them.

**Evidence (scripted probes over the real artifacts):**
- **In-box nvme in UEK R2 (the Nitro precondition).** Full-payload scan of
  `kernel-uek-2.6.39-400.297.3.el5uek` (all 2,075 modules): `nvme.ko` is
  present (the v0.9-era driver) with a **class-match PCI alias**
  (`pci:v*d*sv*sd*bc01sc08i02*`) that covers Amazon EBS NVMe (1d0f:8061);
  `depends` is empty; the io_timeout module param is byte-typed (max 255 s).
  ENA is NOT in-box (self-build; B.9/D.29). xen-blkfront/xen-netfront and
  the virtio set are in-box (fallback + build-VM paths).
- **cloud-init 0.6.3 (EPEL5) closure.** BFS dependency resolution against
  the OL5 base repo: 99 packages total, only 9 from EPEL5 (frozen NVRs:
  cloud-init-0.6.3-0.12.bzr532, python26 2.6.8-2 + libs, PyYAML 3.08-4,
  boto 2.27.0-1, cheetah 2.4.4-3, configobj 4.7.2-5, libffi 3.0.5-1,
  libyaml 0.1.2-8), zero unresolved. Defaults: `user: ec2-user`,
  `disable_root: 1`, `ssh_pwauth: 0`; DataSourceEc2 = plain IMDSv1 with
  built-in retry. **`setup_user_keys` is getpwnam-only** (no users-groups
  module in 0.6.x) → the target account MUST pre-exist → kickstart `%post`
  creates ec2-user. No growpart equivalent exists.
- **Historical grounding.** RHEL5-era AMIs used rc.local/SysV
  `ec2-get-credentials` + IMDSv1 → `/root` (AWS building-shared-amis
  documentation; 2010-era operator records); cloud-init entered RHEL at
  6.4 together with the root→ec2-user switch (AWS official blog). Choosing
  0.6.3 + pre-created ec2-user gives OL5 the modern login contract on
  period-correct plumbing.
- **Upstream transport mechanics (from the real `oracle/oracle-linux`
  tree).** `distr/<DISTR>/files/` → `provision.d/` →
  `virt-customize --copy-in` → guest `/tmp/provision.d/` is a standard,
  generic channel — binary RPM host-supply needs NO upstream change.
  Appended hook blocks execute at SOURCE time in file order, and bash
  function redefinition is last-wins → the OL5S1 executor (earlier append)
  and the OL5S2 overrides need no sed surgery on upstream bodies.
  `virt-install` pins the build disk to virtio-scsi (absent from the EL5
  installer kernel) → the OL5 disk-bus patch; `ISO_CHECKSUM` is hard-typed
  SHA1/SHA256 upstream → the operator-computed SHA256 contract.
- **Guest bash is 3.2.** `${var,,}`/`${var^^}`/`mapfile` in executed guest
  paths die at runtime on EL5. Executed-path analysis: the upstream
  bash-4 sites live in bodies the OL5 flow never runs
  (`common::distr_cleanup`, `common::remove_kernels`, the overridden
  cloud:: bodies); everything OL5 executes is bash-3.2/POSIX clean and
  t025 enforces this mechanically on the synthesized blocks.

**Binding adjudications (user decisions, 2026-07-19):**
1. **F3 runtime model:** OL6-style wrapper synthesis of `distr/ol5-slim/`
   (not an upstream fork, not a vendored tree).
2. **cloud-init:** EPEL5 0.6.3 with the frozen 9-RPM closure (not the
   no-cloud-init/SysV-key-script alternative).
3. **Growroot:** grow the root partition in-place with one reboot. **Both**
   fdisk and gdisk ship in the AMI, but gdisk is a diagnostic tool only —
   MBR→GPT conversion would break GRUB Legacy. *(Refined by the 2026-07-19
   follow-up adjudication below: the execution criterion is the disk state,
   and the write mechanism is the growpart dump-edit model, superseding the
   initial fdisk-keystroke implementation.)*
4. **ENA toolchain host-injection:** the frozen 11-RPM closure, kept
   byte-identical to the matrix's `OL5_TOOLCHAIN_RPMS` (t025-enforced).
5. **Pins:** ENA OL5 = 2.12.3 (the swept build boundary; 2.13.0+ all fail
   against UEK R2), awscli OL5 = 2.17.51 ceiling (D.30). SSM = measured
   exclusion, forced off (D.31).
6. **ec2-user fixed; ext3 root; UPDATE_TO_LATEST=no; SELinux permissive;
   DISK_SIZE_GB=10; E2E first target Nitro c5/m5 with Xen-generation
   fallback.**

**First-contact surfaces (UNPROVEN until the operator E2E):** EL5
anaconda-11.1 accepting the synthesized kickstart exactly as researched
(`%end`-free shape, `key --skip`, `cdrom`, LABEL/ext3 partitions); the
`rpm -Uvh` transaction (incl. kernel `%post` → `new-kernel-pkg` → `mkinitrd`)
inside the virt-customize appliance chroot; grub.conf default resolution on
the freshly installed tree; the growroot fdisk pipeline against a real EBS
geometry; and Nitro boot of a 3.0.36-base kernel on current hardware. The
P3GATE OL5 branch and t025 encode the researched shapes; per the
gate-maturity lesson, first-contact adjustments are expected and must be
recorded here when they land.

**Follow-up adjudication + growpart implementation research (2026-07-19,
same session):** the user adjudicated that the growroot **execution
criterion must be the actual disk/partition state (growth needed AND
possible), with the flag file demoted to a secondary condition**. The real
cloud-utils `growpart` source was fetched and read to ground the refinement;
findings frozen here:

- growpart itself is **markerless and geometry-primary**: `pt_end ==
  max_end` → `NOCHANGE`, and a growable delta at or below `FUDGE`
  (default 1 MiB) → `NOCHANGE` — the state IS the criterion, re-evaluated
  on every invocation. The OL5 script adopts this exactly; the attempt
  marker survives only as a reboot-loop breaker (growpart never reboots, so
  it needs none; our one-reboot model does), consulted after the geometry
  decision and self-healed on success.
- growpart's MBR write path is `sfdisk --dump` → edit ONLY the target
  entry's size field → apply with `--no-reread --force`, with a sector
  backup (`-O`) + `RESTORE_FUNC` on failure and an explicit tolerance for
  "wrote the table but BLKRRPART said busy". The OL5 script mirrors this
  (dump-file backup/restore + post-write verify re-dump) — byte-preserving
  for every other field, verifiable, and strictly more robust than fdisk
  keystrokes.
- **EL5 adaptation discovered during the port:** util-linux 2.13's sfdisk
  composes NVMe partition NAMES without the `p` separator
  (`/dev/nvme0n1` + `2` → `/dev/nvme0n12`), so any name-based match would
  break precisely on Nitro. The script therefore addresses the table entry
  by its **start sector** (unique, name-independent; sysfs is the
  authoritative geometry source).
- **Why one reboot stays:** `BLKPG_RESIZE_PARTITION` (the online resize of
  a mounted partition) is kernel 3.6+; UEK R2 is 3.0.36. This is the same
  wall that made the RHEL6 era ship *initramfs-time* growroot
  (cloud-initramfs-growroot) rather than online growpart of the root disk.
- The refined decision logic is behaviorally proven in-sandbox (and pinned
  in t025) with a fake-sysfs + mocked-sfdisk harness driving the REAL
  script: grow/apply/verify/reboot; post-grow `NOCHANGE` + marker
  self-heal (re-armed for future EBS enlargements — a capability the
  marker-primary first implementation did not have); marker-as-secondary
  loud no-retry; sub-fudge `NOCHANGE`; and the `Id=83` guard refusal.

**Kickstart-grammar verification record (2026-07-19, user-requested
re-investigation):** the operator questioned whether constructs like
`firewall --enabled --ssh` are genuinely valid EL5 kickstart. The
authoritative parser -- **pykickstart-0.43.9-1.el5** (what anaconda-11.1
loads), fetched from the OL5 repository -- was extracted and its
per-command option tables were machine-derived from `parser.py`; every
option on every directive line of the synthesized OL5 kickstart was then
checked against those tables. **Result: zero invalid options.** Specific
findings frozen here:

- `firewall --enabled --ssh` **IS valid**: 0.43 declares
  `--ftp/--http/--smtp/--ssh/--telnet` as port-map options
  (`ssh -> 22:tcp`), plus the RHEL5 `--no-ssh`. (An initial extraction
  regex mis-paired the option tuple and briefly suggested otherwise --
  corrected against the raw `add_option` source.)
- `part --label`, `key --skip` (special-cased: exactly one argument,
  `--skip` recognized in the handler body), bare `zerombr` (arguments
  draw a deprecation warning; bare is canonical), `rootpw --iscrypted`,
  `timezone --utc`, `clearpart --all --initlabel`,
  `bootloader --location/--append`, `selinux --permissive`, and
  `network --bootproto/--device/--onboot/--hostname` are all present in
  the 0.43 tables. `auth` is a raw pass-through (the whole line is handed
  to authconfig), so `--enableshadow --enablemd5` cannot be a parse error.
- `%packages --nobase` **is valid in 0.43**
  (`add_option("--nobase", ...)` in the packages-header parser) but
  **modern pykickstart's RHEL5 profile falsely rejects it** (nobase was
  dropped from the shared section parser upstream). This is the SINGLE
  modern-tool divergence found: B-T4 (`tests/validate-kickstart.sh`)
  validates the OL5 heredoc with exactly that construct normalized away
  and everything else verbatim -- the normalized file passes
  `ksvalidator -v RHEL5` with zero findings.
- **Correction to an earlier note:** `%post --log` IS parseable in 0.43
  (`add_option("--log", "--logfile")` in the script-header parser); the
  earlier "no --log on EL5" claim was wrong. The exec-redirect mechanism
  is retained by choice (single mechanism, also captures `set -x`), so no
  behavior changes.
- Static tooling status: `ksvalidator -v RHEL5` (modern pykickstart) is
  wired as the OL5 advisory both in P3GATE and in B-T4 (with the
  documented normalization); the exhaustive real-0.43 option sweep above
  is the stronger, grammar-level evidence. What static tools cannot prove
  remains the D.32 first-contact list (package-name existence, anaconda
  runtime behavior).

**First-contact record #1 (2026-07-20, real KVM host, `--build-only`):**
the first real run reached and PASSED, in order: the SHA256/ISO path, the
host-supply staging (24 RPMs + 2 source artifacts), P3GATE, os-variant
auto-detection (`ol5.11`), the virtio disk-bus patch, and — the largest
unknown — **EL5 anaconda ACCEPTED the synthesized kickstart verbatim and
completed the install** (domain shut down cleanly ~70 s after boot). The
run then died at provisioning source time:

```
/tmp/provision.d/env.properties: line 69: declare: -g: invalid option
```

Root cause: upstream `env.properties.defaults` line 69 is
`declare -gA REPO` (bash 4.2+, global + associative). build-image.sh
concatenates the env files VERBATIM into `provision.d/env.properties`,
which the guest's bash 3.2 sources before anything else. The per-script
bash-3.2 discipline covered our templates and the executed upstream
functions — but not this **env-concat channel** (host-authored text
traveling to the guest as data-become-code). `REPO` is used host-side
only (verified: no reference in `bin/provision*.sh` or
`cloud/aws/provision.sh`), and a full hostility scan of every concat
member found this single line.

Fix (same day): (1) an OL5 Phase-3 marker patch guards the declaration —
`[ "${BASH_VERSINFO[0]}" -ge 4 ] && declare -gA REPO || true` — keeping
host-side semantics byte-equivalent (modern bash still declares the
associative array) while the EL5 guest skips it, `|| true` keeping the
AND-list `set -e`-safe; (2) the CHANNEL is now gated: P3GATE scans every
guest-bound env member (defaults + distr + cloud) for bash-4-only
constructs on non-comment lines, and Phase 4 scans the wrapper-generated
`env.properties.local` right after writing it — so any future upstream
reintroduction dies in seconds, pre-install. Gate-maturity lesson applied:
first contact exposed a new CLASS (guest-bound concatenation channels);
the gate now owns the class, not just the instance.

**First-contact record #2 (2026-07-20, real KVM host, second `--build-only`
run):** the record-#1 fix itself was inconsistent — P3GATE's channel scan
flagged the very guard line the env-defaults patch writes
(`[ "${BASH_VERSINFO[0]}" -ge 4 ] && declare -gA REPO || true` contains the
`declare -gA` token), so the build failed at the gate. The gate design
worked exactly as intended (seconds, pre-install); the failure was a
process gap: **the patch and the gate were unit-pinned separately but never
executed TOGETHER** before shipping. Fix: both sides were refactored into
extractable functions (`_ol5_patch_env_defaults`,
`_ol5_scan_bash32_hostile`); the scan gained a PRINCIPLED exemption — a
line is exempt iff it has the version-guard safe shape
`[ "${BASH_VERSINFO[0]}" -ge 4 ] && … || true`, which is safe by
construction on bash 3.2 (guard false → RHS never executes; `|| true` is
`set -e`-safe) — an incomplete guard (missing `|| true`) or any other
hostile line still fails. The composition was reproduced and then proven
fixed in-sandbox against the real upstream defaults (patch→scan = 0
findings; raw `declare -gA` still caught; shape-strict; host-bash source
keeps `REPO` associative; idempotent), and the integration is permanently
pinned in t025 as behavioral cases so a patch×gate inconsistency of this
class cannot ship again.

**First-contact record #3 (2026-07-20, real KVM host, third `--build-only`
run, `SERIAL_CONSOLE="yes"`):** all patched paths held (env-defaults guard +
channel gate green; P3GATE PASS) and EL5 anaconda completed the install
again in ~1 minute (disk 21M→1.5G; clean domain shutdown). The build then
sat for 75+ minutes with the heartbeat showing `vm (no domain)`: upstream
adds `--wait ${INSTALL_WAIT_TIME} --noautoconsole` ONLY in the
`SERIAL_CONSOLE=no` branch — with `yes` it ATTACHES the console (designed
for a human at a TTY pressing Ctrl+]); under this wrapper stdio is piped
for logging, so the attached console client never exits after the domain
shuts down and `virt-install` blocks until the outer watchdog fires. Fix:
the `serial-noninteractive` marker patch (all majors; behavior changes only
when `SERIAL_CONSOLE=yes`) makes the yes branch non-interactive — serial
boot args kept, `--wait`/`--noautoconsole` added (returns on shutdown like
the no branch), and ttyS0 backed by a FILE
(`${WORKSPACE}/<vm>-install-serial.log`), so the complete anaconda serial
output is captured persistently (strictly better for diagnosis than an
interactive attach the wrapper cannot offer). Phase 5 prints the capture
path and a `tail -f` hint when `SERIAL_CONSOLE=yes`. Note: `virsh console`
no longer attaches to the install VM (the serial device is file-backed) —
the file IS the diagnostic channel. `SERIAL_CONSOLE_RUNTIME` (the AMI's
runtime serial config) is unrelated and unaffected.

**First-contact record #4 (2026-07-20, fourth run):** the v1 (record #3)
serial fix failed at domain creation: `--serial file,path=${WORKSPACE}/…`
makes QEMU itself (the `qemu` user) open/create the file, and under
`qemu:///system` neither QEMU nor the confined libvirt daemon may create
files in a root-owned arbitrary directory (DAC: no `w` on the dir;
SELinux: custom paths like `/data` carry `default_t`). virt-install
rolled back instantly ("Allocating disk" → "Removing disk"), and even the
rollback deletion of the never-created file was denied — the visible
`Unable to delete file …-install-serial.log: Permission denied`. Disks
never hit this class because they are storage-pool volumes (libvirt owns
their labels/ownership); chardev files sit OUTSIDE that machinery. Fix
(v2): use libvirt's native chardev logging — the serial device stays
`pty` (upstream-equivalent; `virsh console` from a second terminal works
again) and a `<log file=… append='on'/>` element makes **virtlogd** (the
root daemon whose policy-native directory is `/var/log/libvirt/qemu`,
`virt_log_t`) write the complete output to
`/var/log/libvirt/qemu/<vm>-install-serial.log`. Verified pre-landing
with the real toolchain in-sandbox: virt-install 4.1 `--print-xml`
produces `<serial type="pty"><log file=… append="on"/>`; the v1 DAC
composition was reproduced (non-root create into a root-owned 0755 dir →
EACCES); and the REAL apply block was executed against the real upstream
anchor in all three states (fresh → one v2 line; v1-patched → stale lines
removed, exactly one v2 line; v2 → idempotent, no duplication), now
permanently pinned as t025 behaviorals. Residual (operator side): actual
virtlogd write + SELinux behavior on the RHEL 10 host is the remaining
first-contact surface for this feature.

**First-contact record #5 (2026-07-20, fifth run — the provisioning rpm
transaction's first contact):** serial v2 held (virtlogd capture live) and
the run reached the `[OLAWS-OL5S1]` guest rpm transaction, which failed on
exactly four dependency lines: `libicuio.so.36`/`libicuuc.so.36` needed by
gdisk-0.8.4 (EPEL5 gdisk links ICU; libicu was not staged) and
`glibc = 2.5-123.0.2.el5_11.3` needed by the staged glibc-devel/-headers —
the ISO guest's base glibc is the **U11 GA `2.5-123.0.1`** (machine-derived
from the U11 base repodata), so the latest-errata devel/headers carry an
unsatisfiable exact-NVR require. The matrix container never exposed this
because its base IS the latest errata — the exact-`glibc =` class must
match the RUNTIME TARGET, not the toolchain-proving container. Fixes:
(1) glibc-devel/-headers swapped to the GA NVR (present in OL5/latest
getPackage; single URL base retained) — the ENA 2.12.3 build boundary is
insensitive to this errata step; the manifest's matrix-identity contract is
now "9 byte-identical + exactly the documented 3-entry divergence"
(t025-enforced with comm-based set equality). (2) `libicu-3.6-5.16.1`
staged (provides both required caps; self-contained; its own external
requires are guest-satisfied — proven by the same run, which resolved
everything except the four lines). (3) A **staged-set dependency-closure
gate** (`_ol5_stage_closure_gate` + the measured `OL5_GUEST_BASE_CAPS`
table, 101 caps) now runs on the build host right after staging: every
requirement of the exact staged set must resolve within (staged provides ∪
the measured guest-base table), and any `glibc = X` must equal the pinned
guest NVR — gaps die in seconds pre-install with the full list. The table
is the empirically proven external surface (`rpm -qp` over the real
artifacts; satisfied by the real guest transaction). Verified pre-landing
in-sandbox against the real corrected 25-RPM set: closure PASS; removing
libicu fails listing exactly the two ICU caps; reintroducing the old
123.0.2 devel fails on the exact-NVR rule — all three permanently pinned as
t025 behaviorals (real gate fn + real caps table, rpm stubbed). A future
UEK live-resolution bump that introduces new caps dies loudly at this gate
by design (verify, then extend the table deliberately).

**First-contact record #6 (2026-07-20, sixth run — the post-provision
packaging contract):** the run failed at
`mv: cannot stat '${VM_DIR}/.build-info/*': No such file or directory`.
Upstream build-image.sh unconditionally `virt-copy-out`s `/.build-info`
and then `mv`s its contents into `${VM_DIR}` — on OL6+ those files
(repolist/pkglist/pkglist.csv/kernel.txt) are written by
`common::distr_cleanup`, which the OL5 distr deliberately does not call
(EL5-unsafe: systemctl, /etc/yum/vars, `${EXCLUDE_DOCS^^}`) — but no
EL5-safe replacement wrote them, so `/.build-info` was always going to be
empty and the mv fails **even when provisioning fully succeeds**. Fix:
`distr::write_build_info` (invoked from `distr::cleanup`) writes the same
four files EL5-safely — static repolist note (host-supply model), `rpm
-qa` pkglist, `%{EPOCH}`-based csv (EL5 rpm 4.4 has no `%{EPOCHNUM}`),
and kernel.txt from grub.conf's `default=` entry with a newest-el5uek
modules-dir fallback and a loud FATAL when neither yields a value. The
fixture-path variables (`OL5_GRUB_CONF`/`OL5_MODULES_DIR`) exist ONLY as
a conformance-tier seam; guests always use the defaults. Verified
pre-landing by executing the real template function on fixtures —
including the exact upstream `mv`+`rmdir` sequence — and permanently
pinned as t025 behaviorals (four-files/mv-contract/fallback/FATAL).
**Open item carried to the next run:** the same log shows provisioning
completing in ~16 s with no visible qcow2 growth, which is too fast for
the in-guest ENA build; whether the OL5S1/ENA/awscli chain actually
executed is determined by `${VM_DIR}/builder.log` (upstream copies the
guest's `/tmp/builder.log` out BEFORE the failed mv, so
`/data/ol5-build-ws/OL5U11_x86_64-aws-b2/builder.log` exists on the
operator host) — to be read before the next conclusion is drawn.

**First-contact record #7 (2026-07-20, `builder.log` analysis of the sixth
run — the record-#6 open item CLOSED):** upstream's copied-out guest log
proves provisioning ran END-TO-END: the OL5S1 executor installed all 25
staged RPMs and passed every hard assert (UEK R2 in place, initrd carries
nvme.ko, grub default boots el5uek, cloud-init 0.6.3 verified), the
serial-console hook correctly skipped (GRUB Legacy), and — the milestone —
**the ENA 2.12.3 driver was actually BUILT AND INSTALLED on the real
guest**: all 12 el5uek shims applied, gcc 4.1.2 compiled the module, and
`/lib/modules/2.6.39-400.297.3.el5uek/updates/ena.ko (2.12.3g)` landed.
The earlier "~16 s is too fast" concern was WRONG — EL5-era RPMs and a
9-object module compile genuinely fit in seconds on modern hardware; the
dispatch is sound. Known-benign noise recorded: `grubby fatal error:
unable to find a suitable template` (kernel rpm %post inside the
appliance; the grub contract is owned and asserted by OL5S1, which
passed) and kdump/rsyslog `service stop [FAILED]` chatter. Two REAL
defects found and fixed: (1) **the awscli hook died at
`unzip: command not found`** — the installer's "unzip ships in the OL5
clean-core" note was a CONTAINER observation that does not transfer to
the ISO minimal guest (the record-#5 container≠guest asymmetry class
again); fixed by adding `unzip` to the kickstart `%packages` (U11 media
carries unzip-5.52) plus a loud pre-assert in the installer that names
the supplying contract. (2) **the glibc floor gate read a corrupt value**
(`glibc 2.52.5` in the log): `rpm -q --qf '%{VERSION}' glibc` without a
newline concatenates the multilib pair (glibc.x86_64 + glibc.i686 →
"2.5"+"2.5"); fixed with a newline qf + `sort -u | head -1` (the mangled
and corrected parses were both reproduced in-sandbox against a multilib
rpm stub; the pinned 2.17.51 remains correct — per the installer's own
measured record it is the last v2 build whose bundled .so's need only
GLIBC_2.5). Cosmetic, accepted as-is: the awscli log's `kver` shows the
appliance kernel under virt-customize (informational only; glibc gates).

**First-contact record #8 (2026-07-20, seventh run — the boot path
itself; found by the operator's skip-scrutiny request + `kernel.txt`):**
the run "succeeded" end-to-end, but `build-info written (kernel
2.6.39-400.215.10.el5uek)` exposed a boot-critical defect: the U11 media
ALSO installs kernel-uek **400.215.10** at anaconda time, the staged
297.3 kernel's `%post` grubby fails in the appliance ("unable to find a
suitable template"), and the old OL5S1 assert only checked the `el5uek`
SUBSTRING of the default entry — so grub's `default=` kept pointing at
the media kernel. Consequences had it shipped: the default entry's
initrd was built inside the virtio install VM (no nvme → Nitro boot
dead) and the self-built ena.ko lives only under the 297.3 module tree
(no network even on Xen). Phase 6 passed because CHECK 1/2 validated the
TARGET-named artifacts, not the boot path — the validator blind spot.
Fixes: (1) OL5S1 derives the target kver from the STAGED rpm filename
(authoritative; the newest-modules-dir heuristic is gone); (2) every
other installed kernel (RHCK + media UEK) is REMOVED (OL-parity;
`rpm -e` with a `--noscripts` fallback for the expected %preun grubby
noise); (3) grub.conf is owned EXPLICITLY: an entry for the staged kver
is guaranteed (cloned from the current default entry, args/layout
preserved, when the %post failed to add one), title blocks whose vmlinuz
no longer exists are pruned, `default=` is re-pointed at the staged
entry, and the assert now requires EXACT kver equality plus a matching
initrd line; (4) Phase 6 gains **CHECK 6** (OL5, HARD FAIL): the DEFAULT
grub entry's kernel must equal the target kver — validating the boot
path, not the intended artifacts. All four grub-ownership behaviors were
executed on fixtures pre-landing and are pinned permanently in t025.
Message truthfulness fixed in the same change: the ENA installer's OL5
initramfs-skip line states the real reason (ena is a network driver, not
an initrd module; the nvme initrd is owned by OL5S1), and the awscli
v1-versionlock step short-circuits informatively on OL5 (no reachable
repositories — v1 cannot install). Env adjudications (2026-07-20)
recorded: `DISK_SIZE_GB=7` (OL6-10 aligned; measured usage ~1.7 GB;
growroot floor) and `SELINUX=enforcing` (plan B: measure real denials on
the next build + boot; permissive is the measured fallback).

**Record #8 follow-up (2026-07-20 — CHECK 6 extended to OL6 after a
same-class audit):** the operator asked whether OL6 (the other
non-upstream, runtime-synthesized major) carries the same bug. Audit
result: the PRECONDITION is shared (anaconda installs the RHCK; the
kickstart `%post` switches the default to UEK4 via the kernel rpm's own
%post grubby) but the bug is NOT active, for a decisive environmental
reason: on OL6 that switch runs inside the anaconda %post (real target,
grub.conf already populated with the RHCK entry, so grubby's template
resolution succeeds), whereas OL5 performed it inside the virt-customize
appliance where grubby fails — and OL6's synthesized provision.sh keeps
the upstream parity `common::remove_kernels` calls, so non-target
kernels are removed. Two generations of real Nitro E2E (ethtool ena
matching the AMI-name pin) prove the OL6 boot path empirically. The
BLIND SPOT is shared, however: `yum install -y` returns 0 even when the
kernel %post grubby scriptlet fails, and the appliance-side %preun on
RHCK removal could leave a default entry pointing at a removed kernel —
either failure would ship undetected. Adjudicated fix (plan 1): CHECK 6
now covers both GRUB Legacy majors (`OL_MAJOR_VERSION -le 6`) — a pure
validator extension; the proven production path is untouched. OL7-10
(GRUB2/BLS, two E2E generations) are recorded as a separate future
scope for boot-path validation.
