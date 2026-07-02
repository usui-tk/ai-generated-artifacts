<!-- AI read-contract: this is the Layer-2 COMMON spec home for the Bash family -
     the canonical source of SPEC "Part A" common conventions that consumer SPECs VENDOR
     (managed-region copy, ADR 0019) rather than restate. Each region is delimited by an
     ADR 0015 canonical marker (Markdown comment leader). Regions conform to the Layer-1
     item canon (governance/doc-format/doc-format.jsonl; the spec.part-a.* items with
     content_model=vendored) and are registered as the kind=spec-region row
     spec.bash.part-a in the manifest.
     PROVENANCE: extracted at rule-of-two trigger (AGENTS.md par.2) when the second Bash
     consumer (bash-rhel-container-testsuite) joined bash-ol-aws-ami-builder. Every region
     below is DISTILLED from conventions observed in those two consumers (ground truth,
     AGENTS.md par.4), not invented here. Where the observed ground truth contradicted the
     first consumer's inline Part A text, the ground truth won and the correction is noted
     in the region (see A.5 shell-option scope).
     SCOPE: common convention text ONLY - consumer-specific values are tokenised ({{...}})
     or deferred to the consumer's own SPEC (Part B / project sections). Conventions
     observed in only ONE consumer (e.g. the 9-phase pipeline registry, env.properties
     file schema, OS-version auto-detection) stay in that consumer's SPEC as project
     extensions (A.x) and are NOT hoisted here until a second observer exists.
     HASH STATUS: marker hash= values are stamped by the document-conformance gate
     (doc_gate.py --stamp); never hand-edit a hash. -->

# Bash family - common specification (Part A) - canonical source

This is the **Layer-2 common** home for the Bash scripting family. Consumer SPECs
inherit "Part A" by **vendoring** the regions below (ADR 0019); they do not hand-restate
them (AGENTS.md par.6). Per-consumer specifics - the concrete switch set, phase map,
env-variable inventory, machine-output schemas - live in each consumer's **Part B** /
project sections, not here. Version: see `governance/doc-format/VERSION` (Layer-1 format)
and this home's region markers (`version=`).

## Part A - common conventions

<!-- >>> CANONICAL unit_id=spec.bash.part-a.reference-assets version=0.1.0 hash=f3c69969142a70bd policy=canonical binding=follow-latest >>> -->
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

<!-- >>> CANONICAL unit_id=spec.bash.part-a.source-file-format version=0.1.0 hash=5d0d2c65bbb3c52b policy=canonical binding=follow-latest >>> -->
### A.2 Source file format

Script source files are encoded **UTF-8 without BOM** and use **LF** line endings
(repository File Format Policy). Every executable script starts with the shebang
`#!/usr/bin/env bash` and follows the canonical top-to-bottom layout: shebang; header
comment banner; shell options (A.5); constants; execution-mode globals; logging helpers
(A.3); argument/environment parsing (A.4); domain functions; `main()`; and a
bottom-of-file `main "$@"` invocation (single-purpose helper scripts may omit `main()`
but keep the remaining order). The header banner MUST carry the five sections required
by the Layer-1 `scripts/README.md` header convention: **Purpose**, **Prerequisites**,
**Usage examples**, **Known limitations**, and **AI generation info** (tool and
generation date). Non-ASCII characters are confined to intentional data/string literals;
identifiers and code are ASCII.
<!-- <<< CANONICAL unit_id=spec.bash.part-a.source-file-format <<< -->

<!-- >>> CANONICAL unit_id=spec.bash.part-a.logging version=0.1.0 hash=4f85ed77ecdf29dd policy=canonical binding=follow-latest >>> -->
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
<!-- <<< CANONICAL unit_id=spec.bash.part-a.logging <<< -->

<!-- >>> CANONICAL unit_id=spec.bash.part-a.parameter-handling version=0.1.0 hash=88917cb6d61bc732 policy=canonical binding=follow-latest >>> -->
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

<!-- >>> CANONICAL unit_id=spec.bash.part-a.error-diagnostic version=0.1.0 hash=e395575128fdec10 policy=canonical binding=follow-latest >>> -->
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

<!-- >>> CANONICAL unit_id=spec.bash.part-a.static-analysis version=0.1.0 hash=034f640d941dedee policy=canonical binding=follow-latest >>> -->
### A.6 Static analysis

Two static gates apply to every `.sh` file and run as the self-test suite's L0 tiers:
(1) `bash -n` syntax validation, and (2) **ShellCheck**, clean at **default severity
and at `-S style`** (the canonical gate severity). Project-sanctioned suppressions live
in the per-project `.shellcheckrc`; an inline `# shellcheck disable=SCnnnn` requires an
adjacent justifying comment stating why the finding is intentional. A change is not
gate-clean unless the whole suite (`tests/run-all.sh`) reports zero failures with the
static tiers green.
<!-- <<< CANONICAL unit_id=spec.bash.part-a.static-analysis <<< -->

<!-- >>> CANONICAL unit_id=spec.bash.part-a.doc-language-policy version=0.1.0 hash=ae89cf1a97795729 policy=canonical binding=follow-latest >>> -->
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

<!-- >>> CANONICAL unit_id=spec.bash.part-a.development-workflow version=0.1.0 hash=e4be8f1484f5d2f4 policy=canonical binding=follow-latest >>> -->
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
