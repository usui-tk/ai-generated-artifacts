---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.1.0
  rendered: 2026-07-02
---
# Bash Script Specification (SPEC) — bash-rhel-container-testsuite

> This SPEC documents `bash-rhel-container-testsuite`. **Part A** is the
> repository-wide common specification, inherited by vendoring from the
> canonical spec home; **Parts B-D** are specific to this suite. History lives
> in `CHANGELOG.md`; current and forward design lives here. End-user
> instructions live in [`README.md`](./README.md) / [`README.ja.md`](./README.ja.md).

## Table of Contents

- Part A — Common Specification (vendored from the spec home; extensions A.9-A.10)
- Part B — Script-Specific Specification (B.1 identification · B.2 inputs · B.3 outputs · B.4 phase map · B.5 locked decisions · B.6 acquisition · B.7 axes · B.8 tiers · B.9 architecture · B.10 framework · B.11 packages/EPEL · B.12 naming · B.13 adding a tool)
- Part C — Quality Gates & Validation Checklist (+ open items R5-R8, Q1-Q3)
- Part D — Known Pitfalls & Lessons Learned (D.1-D.8)

# Part A — Common Specification (vendored from the spec home)

> **Status: inherited — vendored from the spec home.** Per the
> [`AGENTS.md` §6 Part A Inheritance Rule (ABSOLUTE)](https://github.com/usui-tk/ai-generated-artifacts/blob/main/AGENTS.md#6-part-a-inheritance-rule-absolute),
> the 8 canonical Part A regions below are vendored from
> [`governance/spec/bash.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/governance/spec/bash.md)
> as marker+hash regions verified against the spec home by the
> document-conformance gate; they are never hand-edited. **A.9-A.10** are this
> consumer's project-specific extensions (not vendored).

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

<!-- Consumer extensions: project-owned additions to the vendored common regions
     (AGENTS.md par.6: extensions record ONLY deviations or additions). -->
### A.9 Result-JSON machine channel (project)

Every installer emits exactly one single-line
`[<vendor>_<tool>][installtest][result] {json}` record on **stdout** per run —
including on every failure path (`die` emits a structured
`{"status":"fail",...}` record) — so the matrix always ingests a parseable,
reasoned row. Because stdout is this machine channel, ALL human-facing log lines
route to stderr (common A.3 role scoping). Field names are per-tool raw facts
(e.g. `osmajor`, `glibc`, `entitlement`, `init_mode`); verdicts are derived by
the matrix, never by the installer.

### A.10 Duplicated-helper identity discipline (project)

The installers are deliberately self-contained (no sourced library at run time),
so four helpers are maintained as byte-identical copies across all three
(`entitlement_certs_present`, `pm_neutralize_rhsm_if_anonymous`, `run_pm`,
`os_major`). Tier `t020` pins the copies byte-identical, so a fix applied to one
copy that drifts from the others fails the suite instead of shipping. The
per-script `log()` helper intentionally differs only in its source tag and is
not pinned.

---

# Part B — Script-Specific Specification

## B.1 Identification

**Project:** `bash-rhel-container-testsuite` — a container-based compatibility
test suite for the RHEL family (v10/v9/v8/v7/v6). Entry points: the suite runner
`tests/run-all.sh` (L0–L2), the three root installers `install-aws_*.sh`
(production + `*_INSTALLTEST=1` test mode, single-line result-JSON channel per
Part A A.9), the three matrix runners `tests/aws_*/run-*-matrix.sh` (report mode
by default, `--run` for the live L3 matrix), and the utilities
`tests/probe-env.sh`, `tests/conformance/check-tool-contract.sh`,
`tests/os-coverage/generate-os-coverage.sh`,
`tests/aws_ena-driver/verify-ena-buildresults.sh`.

A **container-based compatibility test suite for the RHEL family**. For each RHEL
major (**v10 / v9 / v8 / v7 / v6**) it evaluates which versions of a tool
**install** and **run** on Red Hat's container images, and emits a per-OS report.
It is the tool-centric, RHEL-family-centric generalization of the AWS CLI v2 /
SSM Agent / ENA matrices proven in the sibling project
`projects/bash-ol-aws-ami-builder`.

**Initial tool scope:** AWS CLI v2, AWS SSM Agent, AWS ENA Driver. Further tools
are added under the naming taxonomy in B.12.

**Out of scope (deferred):** authenticated `registry.redhat.io`; for any
kernel-module tool, the in-container module **load** test (impossible in a
container that shares the host kernel - that is always an L4 concern).

---

## B.2 Inputs

Per-script environment knobs (each script's header banner documents its own set):
`OSMAJORS`, `ENTITLEMENTS`, `INSECURE_TLS`, `RUN_TIMEOUT`, the per-tool
`*_INSTALLTEST` / `*_VERSION` / `SSM_INIT_MODE` / `ENA_BUILDTEST` variables, and
the per-major version pins in the installers. Data inputs: the committed
`*-releases.json` sets (refreshed by the `list-*-releases.sh` scripts, L3),
`lib/os-profile.sh` (the per-major canon), and — live mode only — the container
registry / vendor endpoints per B.6.

## B.3 Outputs

The append/dedup JSON ledgers (`*-ledger.json`), the generated
`RESULTS-rhel<N>.md` reports (never hand-edited), the coverage matrix
`tests/os-coverage/RESULTS-coverage.md`, the opt-in probe output
`tests/ENV-PROBE.json` (gitignored), per-run failure logs under
`tests/aws_*/logs/` (gitignored), and the per-script single-line result-JSON
machine channel (Part A A.9). Exit codes: 0 on success; installers `die` with a
structured failure record; the suite runner exits non-zero on any tier failure.

## B.4 Phase Map (implementation contract)

| Phase | Deliverable | Exit criterion | Status |
|:--|:--|:--|:--|
| 0 - Feasibility | measured base facts, anon pull, entitled access, signatures, EPEL endpoints | findings measured in Phase 0 | **done** (tail: one real `ena.ko` plain-make build, R1) |
| 1 - Scaffolding | dir skeleton, ported `tests/lib/*`, `run-all.sh`, `.shellcheckrc`, L0 green, bilingual README | L0 passes; fixed count recorded | **done (r01)** |
| 2 - Acquisition | `lib/acquire-rootfs.sh` (+`t003`), `lib/ubi-pkgmgr.sh` (+`t004`), `t005_entitlementdetect`, `t006_initmodemap`, `lib/epel.sh` (+`t007`) | unit tiers green; live pull both paths; classify unit-tested | **done (r02)** (tail: live pull is L3/CI) |
| 3 - AWS CLI | `tests/aws_awscli-v2/*`, glibc ledger, RESULTS, verdict tier | matrix runs (Tier A); reports generated | **done (r03)** (tail: live install is L3/CI) |
| 4 - SSM | `tests/aws_ssm-agent/*`, glibc + init_mode, S3 RPM, RESULTS | both init modes exercised; reports generated | **done (r04)** (tail: live install is L3/CI) |
| 5 - ENA (E2') | `tests/aws_ena-driver/*`, UEK-removed installer, entitlement-gated build | build on entitled host; anon -> `needs-entitlement`; load -> L4 | **done (r05)** (tail: live build L3, load L4) |
| 6 - EOL/constrained | RHEL 7 (frozen, yum, fixed-tag) + RHEL 6 (no anon repo; entitled `rhel-6-server`; EPEL archive-only) | reports generated or formally deferred | **done (r06)** (canon `lib/os-profile.sh` + coverage matrix) |
| 7 - Generalization | tool-agnostic contract (B.10) + classification (B.11) ready for tool #2 | SPEC/TESTING coverage complete; docs bilingual | **done (r07)** (contract checker + pkg-availability canon + the adding-a-tool guide, now the README "Adding a tool" section) |

## B.5 Locked decisions (contract)

| # | Decision | Resolution |
|:--|:--|:--|
| A1 | Project name | `bash-rhel-container-testsuite` |
| A2 | Install-script placement & test-folder naming | install scripts at **project root**; test folders carry a **`<vendor>_`** prefix (`aws_…`) from day one (B.12). |
| A3 | Image variant | **`ubi-init` is the single baseline.** Init-dependence is an invocation axis (`env_init_mode`), not a second image (B.7b). Standard `ubi` is not carried. |
| A4/A5 | Initial tool scope | AWS CLI v2 + SSM Agent + ENA Driver. |
| ACQ | Acquisition premise | **Anonymous UBI by default + auto-detected `entitled` mode** when the harness runs on a subscription-registered RHEL host. |
| ENA | Kernel-module range | **E2'**: run the ENA **build** test when entitled (kernel-devel available); record `needs-entitlement` when anonymous. Module **load** is always L4. |
| EPEL | Community repo handling | **Pin to `dl.fedoraproject.org`** (no metalink/mirrorlist); default = transient baseurl-pinned repo; EPEL 10 minor-versioned; RHEL 6 archive-only special case (B.11). |

These decisions are settled. Changing one is a SPEC revision, not an
implementation detail.

---

## B.6 Acquisition & environment contract

1. Acquisition source = `registry.access.redhat.com`, **anonymous by default**.
   Package set = the UBI subset unless the host passes entitlement through.
2. **Baseline image = `ubi-init`** for RHEL 7/8/9/10; RHEL 6 = legacy
   `rhel6/rhel` (non-UBI). The init variant is an invocation axis, not a second
   image.
3. Acquisition engine = **podman preferred**, with a **curl-only OCI v2 anonymous
   pull as the fallback** (manifest `GET` returns HTTP 200 with no token step;
   blobs `302 -> cdn01.quay.io -> 200`). RHEL 7 `ubi-init` must be pulled by a
   **fixed tag/digest** (`:7.9-88` proven; the floating `latest` is rejected by
   the host signature policy).
4. The harness is **host-distro-agnostic**, self-contained, stdlib-only, with no
   `bats`/`shunit2`; it reuses `tests/lib/*` + `tests/run-all.sh`.
5. Tool-centric and multi-tool; the initial set is the three AWS tools.

#### 3.1 Per-major base facts (measured Phase 0, anonymous)

| RHEL | Baseline image | Release | glibc | pkg mgr | Anonymous repos | Anon fetch |
|:--|:--|:--|:--|:--|:--|:--|
| 10 | `ubi10/ubi-init` | 10.2 | 2.39 | dnf | `ubi-10-{baseos,appstream,codeready-builder}` | yes |
| 9 | `ubi9/ubi-init` | 9.8 | 2.34 | dnf | `ubi-9-{baseos,appstream,codeready-builder}` | yes |
| 8 | `ubi8/ubi-init` | 8.10 | 2.28 | dnf | `ubi-8-{baseos,appstream,codeready-builder}` | yes |
| 7 | `ubi7/ubi-init` (fixed tag) | 7.9 | 2.17 | yum | `ubi-7`, `-optional`, `-extras`, `ubi-server-rhscl-7` | yes (GPG-verified) |
| 6 | `rhel6/rhel` | 6.10 | 2.12 | yum | none anonymously; `rhel-6-server-rpms` via auto-injection on entitled hosts | no (subscription required) |

The TLS-interception caveat (`INSECURE_TLS=1` -> `--setopt=sslverify=0`) is
**sandbox-specific** and unnecessary on a real host; the helpers expose it as a
switch (sandbox = 1, trusted host = 0).

#### B.6.1 Test-environment provisioning (acquisition -> provision -> test, r33/r36)

Acquisition yields a *base* image; it is **not assumed test-ready**. The minimal
vendor images are curated but not complete for every major - notably RHEL 6
(`rhel6/rhel`) ships without `awk`, which the amazon-ssm-agent rpm's `%pretrans`
kernel guard calls, so a bare EL6 install dies before it starts. The harness
therefore inserts a **provisioning step between acquisition and test**:

```
acquire base image (L1) -> provision a "test-ready" image (L2) -> run tests (L3)
```

`lib/provision-test-env.sh` installs a **common package manifest**
(`PROVISION_PKGS`, default `gawk unzip tar` - unzip is required by the AWS CLI
bundle, r48) onto the base and commits ONE "test-ready" image per OS major
(`localhost/rhel-testsuite-provisioned:rhel<N>-YYYYMMDDhhmmss`; one timestamp
per run, r53). The manifest is **COMMON across all tools** - one image per OS,
not one per test - so every matrix (SSM / AWS CLI v2 / ENA) resolves its base
ref, then swaps in the provisioned ref before its sweep. **The images are
run-scoped** (r48, user requirement): a `trap ... EXIT` in every matrix and in
`--smoke` removes all `rhel-testsuite-provisioned:*` images on normal
completion, failure and interrupt alike (`KEEP_TEST_IMAGES=1` opts out for
debugging; base UBI/RHEL images are untouched).

The manifest install runs in a **PLAIN container** (r46; see B.7): on
subscription-registered hosts podman's auto-injection supplies the per-major
entitled repos, and on anonymous hosts the UBI repos suffice (measured: the
whole manifest resolves from UBI on 7-10). The subscription-manager /
product-id plugins are neutralized ONLY when no entitlement certs are visible -
a DEFENSIVE measure (D-S4): the historically reported RHSM-contact hang did
not reproduce in the 2026-07-04 probe runs (EL6 included), but disabling the
plugins in a certless container is harmless and guards unknown environments.
With certs present the plugins stay ON - they are what generates the
per-major entitled `redhat.repo`. `skip_if_unavailable` is GONE (D-S3): it
papered over the harmful host-file mounts removed by D-S1 and would now only
hide real repo failures (`t021` pins its absence). On failure the caller sees
the real package-manager error (`PROVISION_LAST_ERR`), never a masked one.

**Pre-flight, and provisioning as a test prerequisite (r36).** Each matrix
prepares the test-ready image for EVERY requested major *before* running any test
(`provision_prepare_majors`). A test-env image that cannot be created means the
test **prerequisite is not met**: the run **fails fast** - it aborts (non-zero)
WITHOUT executing any test, so a broken environment is never silently
half-tested. The one exception is `PROVISION_OPTIONAL_MAJORS` (**RHEL 6** by
default): EL6 is non-UBI (`rhel6/rhel`, a subscription-gated registry image);
on an entitled host the auto-injection provides its `rhel-6-server-rpms`, but
an anonymous host has no EL6 repos at all - an EL6 that cannot be prepared is **skipped**
(no tests for EL6) and the run continues for the rest.

This is the RHEL analogue of the OL sibling's clean-core builder (see B.9), and
the common manifest is the extension point for future tests (B.13). Covered by
`tests/t021_provisionenv.sh`.

---

## B.7 The two first-class axes

#### 4a. Entitlement axis - `env_entitlement = anonymous | entitled`

| Mode | Condition | Repos in container | kernel-devel / ENA build | AWS CLI / SSM |
|:--|:--|:--|:--|:--|
| `anonymous` | non-RH host / unregistered RHEL / RHUI host (pending) | `ubi-N-*` only (EL6: none) | no -> `needs-entitlement` | yes (both; EL6 per its own gates) |
| `entitled` | subscription-registered RHEL host, **rootful podman, NO mounts** | per-major `rhel-*` repos via **auto-injection** (+ `ubi-N-*`) | yes (measured, all majors 6-10) | yes (both) |

**Measured mechanism (2026-07-04 probe runs; the ground truth this SPEC is
rebuilt on).** On a subscription-registered RHEL host, rootful podman
auto-injects `/run/secrets` (a `redhat.repo` template, the rhsm config and the
entitlement certs) into EVERY container - no mounts, no flags. The first
`makecache`/repoquery makes the subscription-manager plugin generate a correct
**per-major** `redhat.repo` from the CONTAINER's own product cert: an EL8
container gets `rhel-8-*`, an EL9 container `rhel-9-*`, on the same host. The
EL6 image participates through its shipped `-host` symlinks
(`/etc/rhsm-host`, `/etc/pki/entitlement-host`) into `/run/secrets`. This was
verified for all majors 6-10, both build and install package sets.

**The former host-file mounts (r15..r45 era) were measured actively harmful
and are REMOVED (r46, D-S1)**: the host `redhat.repo` is the HOST major's -
wrong-major inside 8/9 containers, `sslclientcert` Permission denied even
same-major, the read-only mount blocked the per-container generation, and EL7
lost the entitled repo it gets automatically when run plain.
`acq_entitlement_mount_args` returns nothing for every mode and is kept only
as the single landing point for the pending RHUI implementation (D-S2).

**Detection is three steps** (the suite handles no secrets itself):

1. **Secrets check** - is `/run/secrets/etc-pki-entitlement/*.pem` present?
2. **Trigger** - run one `dnf/yum makecache` (or any repoquery) so the
   subscription-manager plugin generates `redhat.repo`. `redhat.repo` is
   generated **lazily** and is empty until then; never judge by a bare `grep`
   before this trigger.
3. **Classify** - is any **`rhel-*`** repo now enabled, and does
   `dnf list --available kernel-devel` / `repoquery --latest-limit=1` resolve?
   Match entitled repos by the **`rhel-*` prefix** (IDs differ by generation:
   `rhel-7-server-rpms` vs `rhel-9-for-x86_64-appstream-rpms`); never hard-code
   the owning repo per major. RHEL 6 `repolist` formatting differs - judge by the
   repoquery result, not a repolist string match.

The auto-injection mechanism is **identical across all five majors and both
image variants**; it does not depend on the init variant.

#### RHUI hosts (AWS/Azure) - measured facts, implementation PENDING

There is **no auto-injection on RHUI hosts** (measured on AWS EC2 RHEL 10,
2026-07-04): plain containers are anonymous (UBI-only). The legacy host-file
mounts are non-functional there for two independent reasons: the repo files
carry a literal `REGION` hostname token that only the host-side `amazon-id`
dnf plugin resolves (from the EC2 instance-identity document), and
authorization requires MORE than the TLS client certificate - every request
must carry the SIGNED instance-identity document
(`X-RHUI-ID` / `X-RHUI-SIGNATURE`, urlsafe base64; the client certs are
content-set-less identity certs, authorization is server-side). Authorization
is **host-major scoped**: the RHEL 10 host's credentials reach only
`rhel10/...` content paths (own major HTTP 200; 9/8/7/6 and the `rhel99`
control all 403). A published mount-the-host-files recipe was probed as its
own A/B arm and does not work as written. Consequence: RHUI hosts run
containers PLAIN (anonymous / `needs-entitlement`) until the entitled RHUI
container path is designed - the working model is one instance per major,
pending verification on a non-RHEL-10 host. Azure RHUI: untested (no host
available). `tests/probe-env.sh --facts` re-collects all of this
reproducibly.

#### Support declaration

Verified support: **rootful podman** on subscription-registered RHEL
(SELinux enforcing) and anonymous hosts. Rootless podman: untested.
RHUI hosts: supported in anonymous mode only (entitled path pending, above). `dkms` is **EPEL-only** in
every major (anonymous and entitled). The AWS packages
(`awscli`/`awscli2`/`amazon-ssm-agent`) are absent from every repo, which is why
bundle / S3-RPM acquisition is the correct path.

#### 4b. Init-mode axis - `env_init_mode = none | systemd`

`ubi-init` is a **strict superset** of standard `ubi`: run it with an explicit
command and systemd is not PID 1 (equivalent to `ubi` for install/binary tests);
run it as `/sbin/init` (booted, `podman run -d`) and systemd is PID 1 for
service/unit tests. A single `ubi-init` image therefore covers both modes by
invocation:

| `env_init_mode` | How | What it tests |
|:--|:--|:--|
| `none` | `podman run ubi-init <cmd>` | install + run a binary (init-agnostic) |
| `systemd` | `podman run -d ubi-init` (boots `/sbin/init`) then `podman exec` | `systemctl enable`/`start`, unit activation, boot order |

---

## B.8 OS / image coverage tiers

| RHEL | Baseline image | Tier | Anonymous | Entitled |
|:--|:--|:--|:--|:--|
| 10 / 9 / 8 | `ubiN/ubi-init` | A - current | `ubi-N-*`; pull is ready-made | `rhel-N-for-x86_64-*`; kernel-devel yes |
| 7 | `ubi7/ubi-init` (fixed tag/digest) | B - settled | `yum`; anon fetch yes (incl. RHSCL) | `rhel-7-server-rpms`; kernel-devel yes |
| 6 | `rhel6/rhel` (non-UBI) | C - constrained | no anon repo (base image only) | `rhel-6-server-rpms`; kernel-devel yes |

RHEL 6 is Tier C because it has **no anonymous repo**, not because it is
unbuildable when entitled. EPEL on RHEL 6 is archive-only and special-cased
(B.11).

---

## B.9 Layered architecture & test tiers

```
L1  RHEL-family base image (baseline: ubi-init)   <- podman (preferred) /
        (Red Hat maintained)                          curl-only OCI v2 anon (fallback)
        |                                              Tier A: ready-made; L1 is a pull
L2  Common test platform                          <- toolchain via the image's pkg mgr
        (tools + runtime + libs)                      (UBI subset) or rhel-* (entitled)
        |
L3  Tool under test                               <- AWS CLI v2 / SSM Agent / ENA
        |                                              per (OS major, version[, init_mode])
    Compatibility matrix runner                   <- ledger (JSON) + RESULTS-rhel<N>.md
```

Red Hat ships a curated base, so **L1 is a pull, not a build**
(`lib/acquire-rootfs.sh` replaces the model project's from-scratch
`tests/cleancore/` builder). The base is **not assumed complete**, however: as of
r33 **L2 adds a minimal provisioning step** (`lib/provision-test-env.sh`) that
installs a common package manifest onto the pulled base and commits a per-OS
"test-ready" image - a targeted port of the clean-core idea ("prepare the image
before testing", e.g. `gawk` for the EL6 ssm `%pretrans` guard) rather than a
whole-rootfs build. See B.6.1.

| Tier | Checks | Where | Run by |
|:--|:--|:--|:--|
| **L0 Static** | `bash -n`, ShellCheck `-S style` | any host / CI | `run-all.sh` |
| **L1 Unit (hermetic)** | pure verdict helpers (glibc compare, version scope, EOL, entitlement classify, init-mode map) | any host / CI | `run-all.sh` |
| **L2 Component** | ledger guards, RESULTS generator on fixtures, env parity | any host / CI | `run-all.sh` |
| **L3 Integration** | real pull + install/run (podman or curl-only+chroot), both init modes where relevant | host/CI with `*.quay.io` reachable | `tests/aws_*/run-*-matrix.sh` (manual/CI) |
| **L4 E2E** | genuine RHEL instance: kernel-module **load**, real ENA, real SSM register | real RHEL host | deferred |

`tests/run-all.sh` aggregates **L0-L2** plus each tool's host-runnable verdict
units and prints one `## RESULT pass/fail/skip` summary. **L3 is manual / CI.**

---

## B.10 Tool-compatibility matrix framework (generalized, a-e)

Each tool folder `tests/<vendor>_<tool>/` implements the same five-part contract:

* **(0)** a project-root `install-<vendor>_<tool>.sh` - real-host-usable installer
  with a test mode (`<TOOL>_INSTALLTEST=1`) that installs/builds in a disposable
  rootfs, smoke-checks, and emits one `[<vendor>_<tool>][installtest][result] {json}`
  line of raw facts. The matrix **kicks this script with parameters**; install
  logic is never inlined in the matrix. (Name matches the test folder.) It also
  carries **per-RHEL-major version pins** - the version validated for each major,
  used as the production default and resolved in `resolve_version` (an explicit
  `<TOOL>_VERSION` wins; the matrix passes one in test mode). Initial pins: AWS CLI
  RHEL 6 `2.17.49` (below the v2 glibc-2.17 floor) else latest; SSM RHEL 6
  `3.3.3598.0` (compliance floor) else latest; ENA RHEL 6 `2.9.1` else `2.17.0`.
  Every failure path emits a structured `{"status":"fail",...,"reason":...}` result
  (`die`), so the matrix always records a parseable, reasoned row; the AWS CLI
  installer additionally records the bundle's empirical `min_glibc_measured` +
  `bundled_python` and verifies the landed version, and the ENA installer verifies
  the built `ena.ko`'s modinfo version (`ko_version`) as a false-success guard.
* **(a)** `list-<tool>-releases.sh` -> `<tool>-releases.json`.
* **(b)** `run-<tool>-{install,build}test-matrix.sh` - per `(OS major, version[, init_mode])`
  acquire/reuse, **kick the install script** in its test mode, parse the `[result]`,
  apply the verdict, record.
* **(c)** `<tool>-…-ledger.json` - append/dedup; `env_*` measured fields (glibc,
  kernel, **entitlement**, **init_mode**) kept separate from `compat_*` derived
  fields.
* **(d)** `RESULTS-rhel<N>.md` per OS - regenerated each run, never hand-edited.
* **(e)** pure verdict helpers + table-driven unit tests (no I/O), `tNNN`-style.

**Dominant axis per tool:** AWS CLI -> glibc; SSM -> glibc (+ init_mode);
ENA -> kernel + entitlement.

**Contract enforcement (Phase 7).** The five-part contract is machine-checked:
`tests/conformance/check-tool-contract.sh` walks every `tests/<vendor>_<tool>/`
and verifies (0)-(e) are present (the **root `install-<vendor>_<tool>.sh` exists,
is executable, and is kicked by the matrix**; lister + `*-releases.json`; a matrix
with `--generate-results` and a `*_verdict()` helper; a `"results"` ledger; the
five `RESULTS-rhel<N>.md`; and a tier that sources the matrix).
`tests/t013_toolcontract.sh` fails the suite if any tool is non-conformant. Adding
a non-AWS tool #2 is then a fill-in-the-blanks exercise - see
the README section [Adding a tool](./README.md#adding-a-tool).

#### 7.1 Per-tool notes (initial three)

* **`aws_awscli-v2`** - self-contained bundle, not repo-installed, so the only
  gate is **glibc**. AWS rule (2024-09-16): glibc <= 2.16 pins v2 <= 2.17.49;
  else current. `env_init_mode=none`. Works in both entitlement modes; fine on
  Tier C (no repo needed).
* **`aws_ssm-agent`** - acquired from the AWS **S3 RPM**. Axis = glibc +
  init_mode: `none` installs and runs `amazon-ssm-agent -version`; `systemd`
  boots `ubi-init` and verifies the unit activates (real registration needs
  creds -> L4).
* **`aws_ena-driver`** - **E2'**, entitlement-gated **build** test (compile
  `ena.ko`), never a load test. Build needs `kernel-devel` (obtainable in every
  major when entitled). Default is the plain-`make` fallback
  (`make -C /usr/src/kernels/<kver> M=$PWD modules`); DKMS is an optional EPEL
  path. All Oracle **UEK** detection is removed; target is the stock RHEL kernel.
  Anonymous -> `needs-entitlement`; load/runtime -> L4. **ENA Express readiness**
  (r31, `ena_express_verdict`) additionally classifies `ena_version` against
  AWS's documented driver-version floors (`ena-express.html`: `>= 2.2.9` full
  bandwidth, `>= 2.8.0` `ena_srd_*` metrics) - a pure, entitlement-independent
  driver-capability signal carried on the ledger row, the RESULTS report, and
  the installer's `[result]` JSON. It is **not** an eligibility check: ENA
  Express is enabled per network-interface attachment via the AWS API
  `EnaSrdEnabled` attribute (outside this repository's scope) and gated by
  instance type, and "meets the floor" does not guarantee the driver compiles
  against an untested kernel (see the OL sibling project's UEKR8 findings).

---

## B.11 Package-availability classification & EPEL handling

Every repo-installed input is classified:

* **Anonymous UBI repos** (`ubi-N-*`; RHEL 7 also `optional`/`extras`/RHSCL) -> installable anywhere.
* **Entitled-only** (`rhel-N-*`, e.g. `kernel`, `kernel-devel`) -> entitled mode only; else `needs-entitlement`.
* **EPEL** (e.g. `dkms`) -> out of base; pinned, transient, OFF by default.
* **Vendor-hosted** (AWS CLI bundle, SSM S3 RPM) -> outside repos; over `*.amazonaws.com`.

**Classification canon (Phase 7).** `lib/pkg-availability.sh` encodes this taxonomy
as pure helpers (`pkgavail_class`, `pkgavail_needs_entitlement`,
`pkgavail_anonymous_status`, `pkgavail_over_network`, `pkgavail_tool_source`), so a
tool declares its acquisition source and the suite derives its anonymous story in
one call - e.g. `aws_ena-driver` -> `kernel-devel` -> `entitled-only` ->
`needs-entitlement` (matching `ena_verdict`); `aws_awscli-v2` -> `awscli-bundle`
-> `vendor-hosted` -> `installable`. Covered by `tests/t014_pkgavail.sh`.

**Unpublished vendor artifacts (r34).** A vendor-hosted artifact can be *listed*
yet *undistributed*: some SSM Agent versions carry a git tag but their S3 rpm
returns HTTP 403/404 (never published). The matrix HEAD-checks each in-scope
version once (the rpm is version-global) and records a 403/404 as a distinct
`unavailable` status/verdict in the ledger and RESULTS - a correct terminal
state, **not `install-fail`** (000/5xx stay transient errors to surface). This
mirrors the OL sibling's undistributed-version handling. Covered by
`tests/t022_ssmunavailable.sh`.

**EPEL (`lib/epel.sh`).** RHEL has no vendor EPEL, and Fedora's default metalink
is non-deterministic (returns off-allow-list mirrors). Therefore pin to
`dl.fedoraproject.org` with an explicit `baseurl`, metalink/mirrorlist disabled,
and use a transient pinned repo (method B), not the `epel-release` package
(method A). Per-major baseurls (measured): 8/9 current
(`/pub/epel/<N>/Everything/x86_64/`); 10 minor-versioned with a rolling fallback;
7 and 6 archive (`/pub/archive/epel/<N>/x86_64/`). GPG keys for all majors live
under `/pub/epel/RPM-GPG-KEY-EPEL-<N>` (live tree) even where content is
archived. RHEL 6 EPEL is archive-only and OL6-style special-cased; practically
moot since ENA defaults to plain-make.

---

## B.12 Naming taxonomy (`<vendor>_<tool>`)

* Vendor boundary = underscore `_`; within-tool words = hyphen `-`.
* Initial: `aws_awscli-v2`, `aws_ssm-agent`, `aws_ena-driver` (mild redundancy
  accepted for an explicit prefix from day one).
* Future: `azure_az-cli`, `gcp_gcloud-cli`, `hashicorp_terraform`, …; non-vendor
  utilities use a category prefix in the same grammar (`util_jq`, `k8s_kubectl`).
* Root install scripts keep the model's short names (`install-<tool>.sh`).
* Vocabulary is recorded here and extended per addition.

---

## B.13 Adding a tool

The fill-in-the-blanks procedure for tool #2 lives in the README section
[Adding a tool](./README.md#adding-a-tool) (Japanese mirror in
[README.ja.md](./README.ja.md)); the machine-enforced contract it fills is B.10
(checked by `tests/conformance/check-tool-contract.sh`, tier `t013`).

A tool that needs a base package the vendor image lacks extends the **common
`PROVISION_PKGS` manifest** (B.6.1) rather than touching a production installer:
the per-OS "test-ready" image is shared, so the package is provisioned once for
every tool. This is the intended growth path as the tool set expands.

---

# Part C — Quality Gates & Validation Checklist

### Static checks

- `bash -n` over every `.sh` (tier `t001`); ShellCheck **clean at default
  severity and `-S style`** with the checked-in `.shellcheckrc` (tier `t002`,
  CWD-independent via `-P` since r29); UTF-8, LF-only, no BOM.

### CI gates

- None wired yet (parity with the sibling Bash project); the suite runner is the
  CI candidate stage.

### Functional checks

- `tests/run-all.sh` green — currently **20 tiers / 478 assertions, 0 failures**
  — from ANY working directory; the report-mode entry paths (3 matrices,
  contract checker, coverage generator, verifier) run green; RESULTS
  regeneration is byte-stable.

### Documentation checks

- `README.md` / `README.ja.md` in bilingual lock-step (matching `##`/`###`
  counts); SPEC / TESTING / CHANGELOG English-only; doc-provenance pins present
  on every doc-set member; generated reports never hand-edited.

### Cross-data checks

- Tool-contract conformance (`t013` + `check-tool-contract.sh`: B.10 (0)-(e)
  per tool); ledger guards and per-tool verdict tiers (`t008`-`t011`);
  installer pin/introspection tiers (`t015`/`t016`).

### Open items

| # | Item | Disposition |
|:--|:--|:--|
| R5 | Live pull both paths (podman + curl-only OCI) on a container-egress host | L3/CI; the hermetic sequence is unit-tested in `t003` (Phase 2 tail) |
| R6 | Live AWS CLI v2 install-test matrix (`--run`) -> empirical RESULTS column | L3/CI; the glibc model + report generation are hermetic (Phase 3 tail) |
| R7 | Live SSM install-test matrix (`--run`, both init modes) -> empirical RESULTS | L3/CI; the init-mode grid + compliance model are hermetic (Phase 4 tail) |
| R8 | Live ENA build on an entitled host (`--run`) -> empirical RESULTS; module load | L3 build / L4 load; the E2' grid + verifier gates are hermetic (Phase 5 tail); doubles as the r28 errexit field check |
| Q1 | ~~Hermetic coverage of the rhsm/RHUI mount sets~~ **OBSOLETE (r46)**: the mount sets are gone (D-S1/D-S2); the function is an empty landing point for the pending RHUI work | Closed by the 2026-07-04 remediation |
| Q2 | Hermetic coverage of `acq_platform` / `acq_repo_access` (host DMI/rpm/repo detection) | Quality pass; enabled by the same `ACQ_ROOT` refactor as Q1 |
| Q3 | Defensive hardening of bare function calls under the ERR trap | **Superseded at r28**: `set -e` on the production scripts makes a silently-reintroduced non-zero return abort loudly (see D.2) |

---

# Part D — Known Pitfalls & Lessons Learned

### D.1 Host-kernel-versioned kernel-devel tie (r22, regressed r24)

**Symptom**: the ENA build-dep step installed `kernel-devel-$(uname -r)` — tying
the container build to the HOST kernel, which the container repos do not carry.
**Cause**: conflating "build against a kernel-devel tree" with "the running
kernel". **Resolution**: install plain `kernel-devel` and build against the
container's own tree (through the driver's vendored build system since r52:
`make -C <src> KERNEL_BUILD_DIR=/usr/src/kernels/<kver> BUILD_KERNEL=<kver>`);
guarded by `t019`, which fails if the bug is re-injected.

### D.2 ERR-trap masking of a designed non-zero return (r23)

**Symptom**: `ensure_build_deps` returning rc 3 (kernel-devel unavailable) fired
the installer's ERR trap and died as "unexpected error" instead of recording
`needs-entitlement`. **Cause**: a bare call of a function that returns non-zero
by design, under a `trap die ERR`. **Resolution**: `edc=0; ensure_build_deps ||
edc=$?` at the call site (r23) + `t019` rc pins; **r28's `set -euo pipefail`**
now makes any future bare-call regression abort loudly at the call site instead
of being masked (Q3 superseded).

### D.3 RHEL 6 RHSM plugin hang on the bare image (r18; unreproduced since)

**Symptom (historical, r18)**: `yum` was observed hanging inside `rhel6/rhel`
containers, attributed to the subscription-manager/product-id plugins reaching
out to RHSM. **Status (2026-07-04, D-S4)**: the hang did NOT reproduce in the
probe runs (sandbox and AWS, EL6 included; anonymous EL6 completes with rc=0).
The plugin gating (`pm_neutralize_rhsm_if_anonymous`) is KEPT as a defensive
measure - disabling the plugins in a certless container is harmless and guards
unknown environments - but the "hangs indefinitely" claim is demoted to a
historical observation. Helper pinned identical across installers (`t020`).

### D.4 Old-curl option traps on EOL majors (r20, r26)

**Symptom**: probe egress checks failed or under-retried on RHEL 6/7.
**Cause**: `--retry-connrefused` (7.52+) and `--retry-all-errors` (7.71+) do not
exist on curl 7.19/7.29. **Resolution**: version-agnostic in-shell retry loop
around the whole request (r26); treat curl options as per-major capabilities.

### D.5 Mock argv-spy count flakiness (r25)

**Symptom**: intermittent wrong spy counts in mock-heavy tiers.
**Cause**: non-atomic appends to the spy log. **Resolution**: atomic append in
`tests/lib/mock.sh`; suite proven 30/30 consecutive after the fix.

### D.6 `repoquery` prints nothing for an existing package

**Symptom**: dnf-bundled `repoquery` with a bare query returned empty even when
the package existed (mis-read as "kernel-devel absent" on 8/9/10).
**Cause**: repoquery output-selection artifact. **Resolution**: availability
queries use `dnf list --available <pkg>` or `repoquery --latest-limit=1`
(`lib/ubi-pkgmgr.sh`).

### D.7 RHEL 7 `ubi-init` floating-tag signature rejection

**Symptom**: `podman pull ubi7/ubi-init:latest` rejected by the host signature
policy on a registered RHEL host. **Cause**: floating-tag signature not accepted
by the default policy. **Resolution**: pull RHEL 7 `ubi-init` by fixed tag or
digest (B.6); other majors may float.

### D.8 CWD-dependent SC1091 masquerading as a suite flake (r29)

**Symptom**: `run-all.sh` failed 476/2 when invoked from the repository root and
passed from the project directory — observed twice as an apparent
"unreproducible flake" during the B2 fresh-clone verifications.
**Cause**: ShellCheck resolves `# shellcheck source=` against the CWD/file dir;
the only two directives pointing at the project `lib/` (t012, t014) raised
SC1091 (info, counted at `-S style`) from any other CWD. **Resolution**: `t002`
passes `-P "${PROJ}"` (r29); the gate is now CWD-independent (Part C). Lesson:
before recording a flake, difference the *invocation*, not just the tree.
