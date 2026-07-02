---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.0.0
  rendered: 2026-06-08
---
# Update-WindowsServerIso.ps1 — Developer Specification (SPEC)

> **Status**: r09.0 baseline (rewritten 2026-05-27). This document is the
> authoritative developer / LLM specification for
> `Update-WindowsServerIso.ps1`. It is structured so that an LLM agent
> can be dropped into the project mid-stream without having to re-derive
> the design from the source code.
>
> **Language**: English only, per the repository-wide
> [Language Policy](https://github.com/usui-tk/ai-generated-artifacts/blob/main/README.md#language-policy). Bilingual
> entry-point documentation lives in
> [`README.md`](./README.md) / [`README.ja.md`](./README.ja.md).
>
> **Relationship to the repository-level SPEC**: cross-project rules
> (CI workflow design, naming conventions, timeout policy, supply-chain
> security) live in the [repository-level SPEC](https://github.com/usui-tk/ai-generated-artifacts/blob/main/SPEC.md). This
> document inherits those rules and restates only what is specific to
> this script.
>
> **Relationship to other documents**: end-user "how to run" lives in
> [`README.md`](./README.md); verification procedures and verified
> findings live in [`TESTING.md`](./TESTING.md); per-revision change
> history lives in [`CHANGELOG.md`](./CHANGELOG.md); long-form
> investigation reports live in [`docs/history/`](./docs/history/).

---

## Conventions (RFC 2119)

This document uses the keywords **MUST**, **MUST NOT**, **SHOULD**,
**SHOULD NOT**, and **MAY** as defined in
[RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and
[RFC 8174](https://www.rfc-editor.org/rfc/rfc8174). When the keywords
appear in lowercase or in plain English, they carry the same normative
meaning.

Every section is tagged as either **normative** or **informative**:

- **Normative** sections define behaviour that the script and its
  callers MUST follow. Any change requires a corresponding code change
  and a CHANGELOG entry in the same revision.
- **Informative** sections explain background, rationale, or
  measurement results. They do not impose contractual obligations and
  may evolve independently of the code.

## Stable Identifiers

This document uses three classes of stable identifier so that other
documents, code comments, and finding reports can cite specific points
without breaking on cosmetic edits:

| Class | Form | Used for |
|:---|:---|:---|
| **Section reference** | `B.N`, `B.N.M`, `D.NN` | Cross-references inside this document |
| **Policy identifier** | `SPEC-WSI-NNN` | Repository-wide policy IDs (parallel to `SPEC-CI-NNN` in the repository-level SPEC) |
| **Phase identifier** | `P01`–`P13`, `A00`–`A03` | Pipeline phases (see §B.5) and stand-alone actions (see §B.6) |

A section's identifier is stable across revisions. If a section is
deleted, its identifier is **never reused** for a different purpose;
it is marked "RESERVED / removed in rNN" so that historical references
remain unambiguous.

## Policy Index (Quick reference for AI agents)

| Policy ID | Title | Section |
|:---:|:---|:---|
| SPEC-WSI-001 | Source file format (UTF-8 BOM, CRLF, ASCII-only body) | §A.1 |
| SPEC-WSI-002 | Phase / pipeline architecture | §A.2 |
| SPEC-WSI-003 | Log marker conventions | §A.3 |
| SPEC-WSI-004 | Parameter naming and validation | §A.4 |
| SPEC-WSI-005 | Error & diagnostic emission format | §A.5 |
| SPEC-WSI-006 | Documentation language policy | §A.6 |
| SPEC-WSI-010 | Synthetic test mode contract | §B.9 |
| SPEC-WSI-011 | Patch integrity (three-layer) | §B.8 |
| SPEC-WSI-012 | Pre-apply dependency closure check | §B.13 |
| SPEC-WSI-013 | PatchPlan engine WIM-target mapping | §B.10 |
| SPEC-WSI-014 | Media-dynamic-update sub-phase sequences | §B.11 |
| SPEC-WSI-015 | Catalogue scrape and supersedence selection | §B.12 |
| SPEC-WSI-016 | Refresh policy decision matrix | §B.14 |
| SPEC-WSI-017 | Update type matrix per OS generation | §B.15 |
| SPEC-WSI-018 | PCA2023 boot manager support | §B.17 |
| SPEC-WSI-019 | Output ISO verification (post-conversion) | §B.18 |
| SPEC-WSI-020 | Servicing model consistency check (P06) | §B.19 |
| SPEC-WSI-030 | Static analysis gate (psa.py + PSScriptAnalyzer) | §C.1 |
| SPEC-WSI-031 | Source file format gate | §C.2 |
| SPEC-WSI-032 | Documentation cross-checks | §C.8 |
| SPEC-WSI-033 | Self-verification tool suite (T1–T13 + gates) | §C.9 |

---

## Table of Contents

- [Conventions (RFC 2119)](#conventions-rfc-2119)
- [Stable Identifiers](#stable-identifiers)
- [Policy Index](#policy-index-quick-reference-for-ai-agents)
- [**Part A — Common Specification (inherited; vendored from the spec home)**](#part-a---common-specification-inherited-vendored-from-the-spec-home)
  - A.1–A.13 vendored from the spec home; A.14 Debug Trace Facility (cross-script feature)
  - [A.x — Project-specific extensions](#ax--project-specific-extensions)
- [**Part B — Script-Specific Specification**](#part-b--script-specific-specification)
  - [B.1 Script identity and entry point](#b1-script-identity-and-entry-point)
  - [B.2 Inputs and outputs](#b2-inputs-and-outputs)
  - [B.3 Workspace layout](#b3-workspace-layout)
  - [B.4 OS profile (Config Schema v2.1)](#b4-os-profile-config-schema-v21)
  - [B.5 Phase contracts (P01–P13)](#b5-phase-contracts-p01p13)
  - [B.6 Action → Phase mapping](#b6-action--phase-mapping)
  - [B.7 ISO filename detection patterns](#b7-iso-filename-detection-patterns)
  - [B.8 Patch integrity check (three-layer)](#b8-patch-integrity-check-three-layer)
  - [B.9 Synthetic test mode](#b9-synthetic-test-mode)
  - [B.10 PatchPlan engine and WIM-target mapping](#b10-patchplan-engine-and-wim-target-mapping)
  - [B.11 Media-dynamic-update sub-phase sequences](#b11-media-dynamic-update-sub-phase-sequences)
  - [B.12 Catalogue scrape and candidate selection](#b12-catalogue-scrape-and-candidate-selection)
  - [B.13 Pre-apply dependency closure check](#b13-pre-apply-dependency-closure-check)
  - [B.14 Data pipeline and refresh policy](#b14-data-pipeline-and-refresh-policy)
  - [B.15 Update type matrix per OS generation](#b15-update-type-matrix-per-os-generation)
  - [B.16 LCU package format per OS](#b16-lcu-package-format-per-os)
  - [B.17 PCA2023 boot manager support](#b17-pca2023-boot-manager-support)
  - [B.18 Output ISO verification](#b18-output-iso-verification)
  - [B.19 Servicing model consistency check (P06)](#b19-servicing-model-consistency-check-p06)
  - [B.20 File organisation and naming conventions](#b20-file-organisation-and-naming-conventions)
  - [B.21 Workspace preflight](#b21-workspace-preflight)
  - [B.22 Phase 3 architecture decisions](#b22-phase-3-architecture-decisions)
- [**Part C — Quality Gates and Validation**](#part-c--quality-gates-and-validation)
  - [C.1 Static analysis](#c1-static-analysis)
  - [C.2 Source file format gates](#c2-source-file-format-gates)
  - [C.3 Configuration files validation](#c3-configuration-files-validation)
  - [C.4 Functional smoke tests](#c4-functional-smoke-tests)
  - [C.5 Synthetic full pipeline](#c5-synthetic-full-pipeline)
  - [C.6 Monthly baseline refresh](#c6-monthly-baseline-refresh)
  - [C.7 CI runner diagnostic pre-flight](#c7-ci-runner-diagnostic-pre-flight)
  - [C.8 Documentation cross-checks](#c8-documentation-cross-checks)
  - [C.9 Self-verification tool suite](#c9-self-verification-tool-suite)
- [**Part D — Known Pitfalls and Lessons Learned**](#part-d--known-pitfalls-and-lessons-learned)
  - [D.1–D.23 (inherited from r02–r08.0 cycles)](#d1d23-inherited-from-r02r080-cycles)
  - [D.24 Cognitive bias patterns](#d24-cognitive-bias-patterns)
  - [D.25 DISM mount-cache poisoning](#d25-dism-mount-cache-poisoning)
  - [D.26 `List[object]` of pscustomobject argument-type mismatch](#d26-listobject-of-pscustomobject-argument-type-mismatch)
  - [D.27 Microsoft OS tool dependency avoidance](#d27-microsoft-os-tool-dependency-avoidance)
  - [D.28 Sampling versus comprehensive search](#d28-sampling-versus-comprehensive-search)
  - [D.29 Code bug versus configuration problem triage](#d29-code-bug-versus-configuration-problem-triage)
  - [D.30 Helper function unification](#d30-helper-function-unification)
- [**Appendices**](#appendices)
  - [Appendix E — Function reuse map](#appendix-e--function-reuse-map)
  - [Appendix F — Reference projects](#appendix-f--reference-projects)
  - [Appendix G — Historical revision matrix](#appendix-g--historical-revision-matrix)

---

# Part A - Common Specification (inherited; vendored from the spec home)

> **Status: inherited - vendored from the spec home.** Per the
> [`AGENTS.md` Section 6 Part A Inheritance Rule (ABSOLUTE)](https://github.com/usui-tk/ai-generated-artifacts/blob/main/AGENTS.md), the 14
> canonical Part A regions below are vendored from
> [`governance/spec/powershell.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/governance/spec/powershell.md) as marker+hash
> regions and are verified against the spec home by the document-conformance gate /
> drift scanner; they are never hand-edited. The A.14 slot below is this consumer's
> project-specific cross-script feature (not vendored).

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.reference-assets version=1.0.0 hash=d1f03d5c548d4f3f policy=canonical binding=follow-latest >>> -->
### A.1 Reference assets

Every PowerShell script in the canon draws on a shared set of reference assets: (1) the
static-analysis configuration and gate (see A.11); (2) the companion specification documents
that make up the doc-set (README + README.ja, SPEC, and where applicable TESTING and
CHANGELOG); (3) the in-house canonical reference script `{{REFERENCE_SCRIPT}}`, the worked
example of these conventions; and (4) the shared helper units vendored from the code canon
(`reference-code/powershell/`). The specific reference script and helper set a consumer uses
are recorded in that consumer's own SPEC; this region only fixes that the assets exist and
where their conventions are defined.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.reference-assets <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.source-file-format version=1.0.0 hash=f7105ebfe3d202ff policy=canonical binding=follow-latest >>> -->
### A.2 Source file format

Script source files are encoded **UTF-8 with BOM** and use **CRLF** line endings. Non-ASCII
characters are confined to intentional data/string literals; identifiers, keywords, and code
are ASCII (the documentation-language policy is A.12). Encoding and line-ending conformance is
enforced by the static-analysis gate (A.11); files that are not BOM+CRLF, or that carry stray
non-ASCII outside sanctioned literals, fail the gate.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.source-file-format <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.banner-version version=1.0.0 hash=9821c85a0e065145 policy=canonical binding=follow-latest >>> -->
### A.3 Banner and version

Each script carries a single canonical **version string** and emits a **startup banner** that
prints the script identity, the version, and a **SHA256 self-fingerprint** of the running
file. The version string is the one source of truth for the script's revision and is the value
recorded in CHANGELOG. The banner format and the fingerprint computation are common; the
concrete version value is per-consumer.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.banner-version <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.phase-architecture version=1.0.0 hash=9af42a0010ff6f52 policy=canonical binding=follow-latest >>> -->
### A.4 Phase architecture

Scripts are organised into **numbered phases**. The numbering convention (monotonic integer
phases, optional phase *groups*, and a uniform per-phase header/footer log line carrying the
phase number, title, and elapsed tag) is common. The **phase count and the phase map**
(which work each phase does) are consumer-specific and are defined in the consumer's **Part
B**, not here.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.phase-architecture <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.logging version=1.0.0 hash=8e1353694d8216fa policy=canonical binding=follow-latest >>> -->
### A.5 Logging conventions

Logging goes through the shared logging helper family (vendored from the code canon). Messages
carry a **severity marker** from the canonical set (informational / detail / caution / error
and the phase markers); console output uses the canonical colour discipline for each severity;
network operations use TLS. Scripts do not write ad-hoc colour or bypass the helpers. The
helper set is fixed by the code canon; this region fixes the *conventions* for using it.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.logging <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.path-handling version=1.0.0 hash=1526d2dbb85bb58f policy=canonical binding=follow-latest >>> -->
### A.6 Path handling

Paths are handled defensively: prefer **`-LiteralPath`** over wildcard-expanding parameters;
never expand wildcards on externally supplied input; build paths with validated joins (not
string concatenation); and confine scratch files to a controlled work root rather than the
current directory or a shared temp location. These rules are common; the specific work-root
location is per-consumer.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.path-handling <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.parameter-handling version=1.0.0 hash=9969ad954a28fc39 policy=canonical binding=follow-latest >>> -->
### A.7 Parameter conventions

Scripts expose the canonical **standard parameter set** (the shared switches every consumer
provides) plus consumer-specific parameters. Mutually exclusive options are validated at
entry; invalid combinations fail fast with a diagnostic. Help/usage shows the startup banner.
The standard switch set and the validation discipline are common; the consumer-specific
parameter list is defined in the consumer's SPEC.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.parameter-handling <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.error-diagnostic version=1.0.0 hash=0d472879675b224b policy=canonical binding=follow-latest >>> -->
### A.8 Error and diagnostic model

Diagnostics are **three-layered**: (1) human-readable console output; (2) a per-run detail log
file; (3) structured per-failure records. Failures are **classified** (e.g. transient vs
fatal vs configuration) so callers can react. Each failure is recorded as a structured entry
following the canonical record shape (A.9 JSONL conventions). If a consumer additionally
provides an **operation-level trace facility** (an optional feature - see the consumer's Part
A.14 / project section), the per-failure records and the operation-level trace coexist; this
region does not require such a facility.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.error-diagnostic <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.csv-conventions version=1.0.0 hash=38cb631efd9af8a9 policy=canonical binding=follow-latest >>> -->
### A.9 CSV conventions

Tabular outputs and state files share common **column-naming** and **file-naming** conventions:
stable snake/Pascal column names, a per-phase output-file naming scheme, and a designated state
file for resumable runs. CSV is the baseline tabular format every consumer supports.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.csv-conventions <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.jsonl-conventions version=1.0.0 hash=3d605116d9e9b33c policy=canonical binding=follow-latest >>> -->
### A.9 (cont.) JSONL conventions - optional feature

A consumer **may** additionally emit JSONL (one JSON object per line) for machine consumption -
notably the per-failure records of A.8. When present, JSONL files follow the canonical naming
(per-phase, purpose-suffixed), use **camelCase** keys, and are LF-terminated. This region is an
**optional feature**: a consumer that emits only CSV omits it.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.jsonl-conventions <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.environment-eval version=1.0.0 hash=669c9ba612d6f35b policy=canonical binding=follow-latest >>> -->
### A.10 Environment evaluation

The **environment-evaluation phase (the first phase of the run)** assesses the host before any
work: it gathers platform/runtime facts in tiers (a baseline probe, then progressively
deeper checks) and **asserts compatibility** (runtime version, privileges, required tooling),
failing fast with a clear diagnostic when a prerequisite is unmet. The tiered model and the
fail-fast compatibility assertion are common; the specific phase number/name and the exact
checks are consumer-specific (Part B).
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.environment-eval <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.static-analysis version=1.0.0 hash=a9e9c8d44b702ac2 policy=canonical binding=follow-latest >>> -->
### A.11 Static analysis

`psa.py` (the canon's PowerShell static analyzer; canonical home in the tool canon) is the
**mandatory static-analysis gate**. Every consumer runs it with a project-local
`.psa.config.json` and MUST be **clean (0 errors / 0 warnings / 0 info)** before each commit.
The `.psa.config.json` **follows-latest** from the analyzer's canonical home (ADR 0009); it is
tool-owned, not part of this doc canon. Which rules a consumer suppresses (with justification)
and any project-specific false-positive dispositions are recorded in the consumer's own SPEC,
not here. CI runs a **three-stage model**: Stage 1 - lint / static analysis (psa.py +
PSScriptAnalyzer), cross-platform; Stage 2 - functional / parse validation (Windows where
required); Stage 3 - release / packaging. The three-stage model is common; the concrete
workflow filenames are path-encoded per consumer (A.13 / the dotfile conventions).
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.static-analysis <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.doc-language-policy version=1.0.0 hash=8e392c54780c4a7f policy=canonical binding=follow-latest >>> -->
### A.12 Documentation language policy

Code, configuration, and the SPEC/TESTING/CHANGELOG doc-set are authored in **English / ASCII**.
Intentional Japanese appears only in (a) the **bilingual README pair** (`README.md` +
`README.ja.md`, twin-file), (b) the **bilingual community-health files**
(`CODE_OF_CONDUCT` / `CONTRIBUTING` / `SECURITY`, in-file English + Japanese sections),
and (c) sanctioned data/string literals. The bilingual *mode* is fixed by document member -
twin-file for README, in-file dual-language for community-health. The doc-set file-set and each document's role follow the
canonical structure (README + README.ja, SPEC, and where applicable TESTING and CHANGELOG):
**history lives in CHANGELOG, current/forward design in SPEC**. `README.md` and `README.ja.md`
are maintained in **lock-step** (AGENTS.md §5). The mandatory README disclaimer and license
sections are defined by the canonical README format (the `readme.disclaimer` / `readme.license`
items) and are **not restated here**.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.doc-language-policy <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.development-workflow version=1.0.0 hash=fdadacb9bf023186 policy=canonical binding=follow-latest >>> -->
### A.13 Development workflow

Changes follow an **iterate-to-green** cycle: edit; run the static-analysis gate (A.11) to
**0/0/0**; run the consumer's verification/tests where present; then commit. Revision history
is recorded in **CHANGELOG** (Keep a Changelog format); the SPEC records the current design,
not a change log. Doc-touching changes keep the doc-set in sync (AGENTS.md §5): a SPEC change
that alters behaviour updates README / README.ja / TESTING in the same change. CI workflow
files are named with a per-consumer path-encoded prefix.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.development-workflow <<< -->

### A.14 Debug Trace Facility (cross-script feature)

The Debug Trace Facility is a reusable operation-level diagnostic
mechanism vendored into `Update-WindowsServerIso.ps1` from the shared
canon helper set. It complements the per-record diagnostics of A.8:
where A.8 answers "which record failed", the Debug Trace Facility
answers "which named step inside this function was in progress when
the exception was raised".

It is generic - it makes no assumption about phases, records, or any
script-specific concept - which is why it occupies the Part A
cross-script feature slot. The public API, module-level state, and
output formats below are canonical (shared verbatim by every consumer
of the facility); only the activation sites are script-specific.

### A.14.1 Three subsystems

| Subsystem | Public API |
|---|---|
| Trace primitives | `Start-DebugTrace` / `Set-DebugStep` / `Stop-DebugTrace` / `Format-DebugFailure` / `Write-DebugFailureReport` |
| JSONL file output (real-time stream) | `Enable-DebugTraceFileOutput` / `Disable-DebugTraceFileOutput` / `Get-DebugTraceFileOutputStatus` |
| JSON point-in-time export + auto-export-on-failure | `Export-DebugTraceJson` / `Enable-AutoExportOnPhaseFailure` |

### A.14.2 Module-level state

The facility maintains the following script-scope variables, declared
at script-load time so they exist before any function body references
them:

```powershell
$Script:DebugTraceStack             = New-Object 'System.Collections.Generic.Stack[object]'
$Script:DebugTraceCompletedFrames   = New-Object 'System.Collections.Generic.List[object]'
$Script:DebugTraceCompletedCap      = 1024
$Script:DebugTraceHistoryCap        = 256
$Script:DebugTraceJsonlLineCap      = 8192
$Script:DebugTraceJsonDepth         = 100
$Script:DebugTraceJsonlEnabled      = $false
$Script:DebugTraceJsonlPath         = $null
$Script:DebugTraceJsonlBuffer       = New-Object 'System.Collections.Generic.List[string]'
$Script:DebugTraceJsonlBufferCap    = 4096
$Script:DebugTraceJsonlWriteCount   = 0
$Script:DebugTraceJsonlErrorCount   = 0
$Script:DebugTraceJsonlLastError    = $null
$Script:DebugTraceAutoExportEnabled = $false
$Script:DebugTraceAutoExportDir     = $null
$Script:DebugTracePhaseRegistry     = @{}
$Script:DebugTraceEventSeq          = 0
```

### A.14.3 Standard usage pattern

Every function that should participate in tracing follows this
entry / body / catch / finally template:

```powershell
function Invoke-Something {
    Start-DebugTrace -Context 'Invoke-Something' -PhaseId 'PNN'
    try {
        Set-DebugStep 'validate inputs'
        # ...
        return $result
    } catch {
        Write-DebugFailureReport $_ -IncludeStepHistory -AutoExport
        throw
    } finally {
        Stop-DebugTrace
    }
}
```

Rules:

1. `Start-DebugTrace -PhaseId 'PNN'` is used for phase-level frames
   only; inner helpers called from a phase body may use
   `Start-DebugTrace` without `-PhaseId` to nest a sub-frame.
2. `Set-DebugStep` is a no-op when no frame is active, so library-style
   helpers can use it opportunistically without forcing callers to set
   up tracing.
3. `Write-DebugFailureReport -AutoExport` triggers a JSON snapshot only
   when `Enable-AutoExportOnPhaseFailure` has been called previously
   (this script enables it during startup, after
   `Initialize-RuntimeDirectories`).
4. The `finally` block must always call `Stop-DebugTrace` to keep the
   stack balanced. An early-return branch that bypasses the natural
   flow MUST call `Stop-DebugTrace` itself, and the `finally` block then
   guards against a double-pop via `$Script:DebugTraceStack.Count`.

### A.14.4 Activation order

```powershell
# After any cleanup and Initialize-RuntimeDirectories.
Enable-DebugTraceFileOutput -Directory $Script:LogsDir
Enable-AutoExportOnPhaseFailure -OutputDirectory $Script:DiagDir
```

Both functions are best-effort: if activation fails (e.g. permission
denied on the logs directory), the script continues without the
diagnostic feature and the failure surfaces as a `Write-Warning`. The
in-memory pre-activation buffer accumulates up to its cap, so a
successful late activation still flushes whatever trace events occurred
during startup.

### A.14.5 Output format

The JSONL stream is one JSON object per line, append-only. Event kinds:

| `kind` | Emitted by | Key fields |
|---|---|---|
| `frame.open` | `Start-DebugTrace` | `ctx`, `depth`, `phase` |
| `step` | `Set-DebugStep` | `ctx`, `step`, `detail` |
| `frame.close` | `Stop-DebugTrace` | `ctx`, `outcome`, `durMs`, `steps`, `phase` |
| `failure` | `Write-DebugFailureReport` | `ctx`, `step`, `exType`, `msg`, `stack`, `stepHistory[]` |
| `file.open` / `file.disable` / `file.close` | Lifecycle markers | `procId`, `scriptVer`, `scriptSha` |

The point-in-time export is a single self-contained object with the
top-level keys `schemaVersion`, `exportedAtUtc`, `hostInfo`, `script`,
`fileOutput`, `phases[]`, `activeFrames[]`, `completedFrames[]`,
`events[]` (only when `-IncludeEvents` is passed; otherwise `[]`), and
`eventCount`.

### A.14.6 Coexistence with A.8 and field-name note

The Debug Trace Facility (A.14) and the per-record error pipeline (A.8)
log independently, never share files, and never mutate each other's
state: A.8 records *which input record failed*; A.14 records *which
named step inside a function was in progress*. When a record failed and
the in-function step also matters, consult both files - they were
designed to coexist on a single phase body without overlap.

Field-name note: the export and JSONL lines use `procId`, `hostName`,
and `hostInfo` rather than `pid` / `host`, because PowerShell 5.1 has
been observed to treat `host` as the `$Host` automatic variable in
certain parser contexts.

---

# Part B — Script-Specific Specification

> **Scope of this Part**: the specific contract of
> `Update-WindowsServerIso.ps1`. Sub-sections are organised by concern:
> identity / I/O / workspace / configuration in B.1–B.4; the phase
> pipeline contract in B.5–B.6; per-phase algorithms in B.7–B.18; the
> servicing model consistency check in B.19; cross-cutting file
> organisation, preflight, and architecture decisions in B.20–B.22.

## B.1 Script identity and entry point

**Status**: normative.

The script is a single-file PowerShell artefact named
`Update-WindowsServerIso.ps1` located at
`projects/powershell-update-windows-server-iso/`. It targets
Windows PowerShell 5.1 as the primary host with PowerShell 7+ as a
secondary supported host on Linux for static analysis only.

The script header declares:

```powershell
[CmdletBinding()]
param(
    [ValidateSet('Build', 'Verify', 'Prepare', 'PrepareBuildVerify',
                 'Cleanup', 'ListPhases', 'TestHarness',
                 'RefreshAllBaselines', 'RefreshSnapshots',
                 'RebuildDataset', 'DumpFieldClassification')]
    [string]$Action = 'Build',

    [Parameter()] [switch]$Execute,
    [Parameter()] [string]$WorkRoot,
    # ... (see script header for the full inventory)
)
```

The complete parameter inventory and its semantics are documented
inline in the script's comment-based help block. `Get-Help
.\Update-WindowsServerIso.ps1 -Detailed` renders the same.

`$Script:ScriptVersion` near the script head records the release
identifier in the form `update-wsi-<YYYY.MM.DD>-r<NN>[.<MM>]`.
`$Script:ScriptTag` records a one-line semantic tag for the
release. Both MUST be bumped in the same commit as any operational
change.

## B.2 Inputs and outputs

**Status**: normative.

### B.2.1 Inputs

| Input | Source | Required for |
|:---|:---|:---|
| Microsoft Windows Server evaluation ISO | Microsoft Evaluation Center | Build, Verify |
| Per-OS configuration profile | `data/config-Server{2016,2019,2022,2025}.json` | All actions |
| Microsoft Update Catalogue | live HTTPS | RefreshAllBaselines, RebuildDataset, Build (P03/P04) |

### B.2.2 Outputs

| Output | Path | Conditions |
|:---|:---|:---|
| Updated ISO | `<WorkRoot>/output/<input-basename>_Updated_<yyyy-MM>.iso` | `-Action Build -Execute` |
| Per-phase log | `<WorkRoot>/logs/P{NN}_<phase>.log` | every phase |
| Transcript log | `<WorkRoot>/logs/transcript_<yyyy-MM-dd_HH-mm-ss>.log` | every run |
| Diagnostic JSON | `<WorkRoot>/diag/<yyyy-MM-dd_HH-mm-ss>/*.json` | on failure or `-Verbose` |
| Final report | `<WorkRoot>/P13_final_report.json` and `.md` | always |
| PCA2023 readiness | `<WorkRoot>/pca2023_readiness.json` and `.md` | P12 |

The final report's `Health` field is one of `Healthy`, `Warning`,
`Critical`, `Unknown`. Healthy means every required phase succeeded
and `Test-OutputIsoPca2023Readiness` (see §B.18) reported
`OverallStatus` of `Pass` or `PassWithNotes`.

## B.3 Workspace layout

**Status**: normative.

A "workspace" is a directory tree under a `-WorkRoot` argument
(defaulting to `<script-dir>/Workspace_UpdateWsi`) that holds all
per-run state:

```
<WorkRoot>/
├── source/
│   └── iso/<input-iso>.iso        (operator-staged input)
├── extracted/                      (P05 robocopy expansion target)
├── work/
│   ├── install-wim-mount/          (P07 mount target)
│   ├── boot-wim-mount/             (P08 mount target)
│   └── winre-wim-mount/            (P08 inner mount target)
├── patches/Server<N>/              (P04 download cache)
├── cache/
│   └── catalog/                    (HTML / JSON Catalogue cache)
├── output/<final-iso>.iso          (P09/P10 destination)
├── logs/                           (per-phase + transcript)
└── diag/<timestamp>/               (forensic JSON on failure / verbose)
```

The recommended pattern for multi-OS use is **one WorkRoot per OS
family** (e.g. `D:\UpdateWsi_2016`, `D:\UpdateWsi_2019`, …). This
side-steps the DISM mount-cache poisoning class of failure
documented in §D.25.

## B.4 OS profile (Config Schema v3.0)

**Status**: normative. **Policy ID**: SPEC-WSI-011 (Patch integrity
three-layer is built on this schema).

Each `data/config-Server<OsKey>.json` file is a per-OS configuration
profile that the script reads at P02 (ResolveInputs). Schema 3.0 is
the current shape; older revisions are documented in §B.22 for
historical reference.

### B.4.1 Top-level structure

```jsonc
{
  "Schema":     "3.0",
  "OsKey":      "Server2025",
  "PatchModel": "uup-checkpoint",   /* discriminated-union tag; see B.4.3 / B.19 */

  "Common":  { /* OS-wide constants, see B.4.2 */ },
  "PatchBaseline": { /* Patch Tuesday cadence, see B.4.3 */ },
  "Pca2023":  { /* Secure Boot conversion defaults, see B.4.4 */ },
  "AutoRefreshPolicy": { /* see B.14 */ },
  "LanguageSpecific": { /* per-language ISO + lang-specific patches */ }
}
```

### B.4.2 `Common` block

OS-wide constants that change only when Microsoft re-releases the
base ISO:

| Field | Example | Meaning |
|:---|:---|:---|
| `Build` | `26100` | Base OS build (pre-LCU) |
| `OsShortName` | `WS2025` | Filename token |
| `Edition` | `Datacenter` | Default edition for output ISO |
| `Architecture` | `x64` | Always x64 today; reserved for future arm64 |
| `WimEdition` | `Windows Server 2025 Datacenter (Desktop Experience)` | DISM target name |
| `InstallWimIndex` | `4` | Index inside install.wim |
| `BootWimIndexes` | `[1, 2]` | Indexes inside boot.wim |
| `WinReWimPath` | `Windows\System32\Recovery\Winre.wim` | Path inside install.wim |
| `SupportedLanguages` | `["en-us", "ja-jp"]` | Languages configured for this OS |
| `DefaultLanguage` | `en-us` | Used when `-OsLang` is not specified |
| `LCUExpandViaMum` | `true` | Use `update.mum`-based LCU expansion (true for r02+) |
| `EnableInstallWimUpdate` | `true` | Whether P07 applies LCU to install.wim (r11.37: Server 2025 placeholder `false` corrected to `true`) |
| `EnableBootWimUpdate` | `true` | Whether P08 applies LCU to boot.wim |
| `EnableWinREUpdate` | `true` | Whether P08 applies Safe OS DU to WinRE.wim |
| `_VerifiedDate` / `_VerifiedBy` | `2026-05-24T00:00:00+09:00` / `manual:initial-r03` | Human verification record |

The three `Enable*Update` flags MUST be promoted from `Common` to
top-level by `Get-ConfigProfile`. An earlier dead-code path defect
(the flags were read but never promoted) has since been corrected, so
the promotion is enforced.

### B.4.3 `PatchBaseline` block

Cadence: refreshed monthly per the AutoRefreshPolicy (§B.14).

```jsonc
"PatchBaseline": {
  "Schema":                  "3.0",
  "TargetBuildAfterUpdate":  "26100.32995",  // DERIVED (r11.46): the LCU Line's InScope.build
  "PatchTuesdayOfBaseline":  "2026-05-12",
  "LastVerifiedDate":        "2026-05-24T00:00:00+09:00",
  "LastVerifiedBy":          "auto-scrape:Catalog",
  "ChecksumAlgorithm":       "SHA256",
  "Lines": [
    {
      "Kind":                "LCU",
      "KbId":                "KB5087539",
      "UpdateId":            "...",
      "Title":               "...",
      "FileName":            "...",
      "DownloadUrl":         "...",
      "Digest":              "8v6Qwu...",     // SHA-1, base64: Catalog primary key
      "Sha256":              "...",           // recorded for reference (R5 verify target)
      "SizeBytes":           null,            // HEAD Content-Length (fill pending)
      "ApplyOrder":          2,
      "InScope":             { /* media-payload applicability annotation */ }
    },
    /* one Line per Kind: LCU, SSU, DotNet, SafeOSDU (and SetupDU for uup-checkpoint) */
  ]
}
```

**Field retirement + derivation [r11.46].** `TargetBuildAfterUpdate`
moved SEED -> DERIVED: the refresh writeback sets it from the LCU Line's
Catalog-captured `InScope.build` (the seed-era hand-maintained value had
gone stale on all four OSes), and its consumer is the P11 StaticVerify
hard check `LcuTargetApplied` (pure comparator `Test-LcuTargetApplied`,
offline gate T31): the applied LCU package is the build-attainment
marker, and a missing baseline LCU is a hard verification FAILURE
[DECIDED 2026-07-02, user]. `VerificationMethod` (written, never read)
and `ExcludeKbList` (never read; the 2025 entry mis-described the
checkpoint SSU KB5043080 as unnecessary while `Lines[]` applies it at
ApplyOrder 1) were retired from the schemas, seeds, and configs in the
same pass; the seed `PatchBaseline` envelope is now `Schema` +
`ChecksumAlgorithm` only.

Patch `Kind` values are `LCU`, `SSU`, `DotNet`, `SafeOSDU`, and
`SetupDU`; which Kinds are required or forbidden for each `PatchModel`
is the discriminated-union contract in §B.19. Field cadence and who is
allowed to mutate each field is the §B.14 decision matrix.

**Resolved patches live in `PatchBaseline.Lines[]`** (Config Schema
v3.0, the data-source migration from `wsusscn2.cab` to the Microsoft
Update Catalog). Each Line carries a `Kind` and is keyed by its `Digest`
(SHA-1, base64 - the Catalog DownloadDialog primary key). **Digest
format rule [r11.44]**: `Digest` and `Sha256` are stored BASE64 exactly
as the Catalog DownloadDialog serves them (never re-encoded at rest);
`Get-FileHash` yields hex, so `Test-PatchIntegrity` normalizes the
expected values through the single conversion boundary
`ConvertTo-HexDigestString` at comparison time (offline gate: T29
`patch_integrity_digest_test.py`, incl. a live-captured KB5095966
vector). Both fields are wired into P04 verification: `Digest` as the
`sha-1` expectation (the primary key), `Sha256` as `sha-256`. The legacy
field names `PatchBaseline.Patches` and `PatchBaseline.NeutralPatches`
are **both forbidden** in current configs: `schema/config.schema.json`
forbids them via `not.anyOf` and requires `Lines`, and the CI gate in
§C.3.2a fails that class of drift in CI rather than on a real machine.

### B.4.4 `Pca2023` block (Schema 2.1+)

Per-OS Secure Boot conversion defaults consumed by P10 / P12:

| OsKey | RequiredByDefault | RequiredUpdateLevelMinDate | KbLabel |
|:---|:---:|:---:|:---|
| Server2016 | `true`  | `2024-04-09` | "2024-4B (April 2024 LCU) or later" |
| Server2019 | `true`  | `2024-04-09` | "2024-4B (April 2024 LCU) or later" |
| Server2022 | `true`  | `2025-02-11` | "2025-2B (February 2025 LCU, 20348.2227 baseline) or later" |
| Server2025 | `false` | `""`         | "n/a (firmware-provided 2023 certs)" |

Server 2022 has a later baseline date because the `EFI_EX` staging
directories appeared in cumulative updates only from the 2025-2B LCU
forward. Server 2025 ships PCA2023 staging assets pre-populated in
its install.wim (see r08.0 Step 1 / Step 2 finding documents) and
therefore does not require a P10 conversion to reach PCA2023
readiness.

### B.4.5 `LanguageSpecific` block

Per-language ISO snapshot URLs, SHA-256 hashes, and language-specific
patches (LXPs, Language Packs, .NET Language Packs). Adding a new
language is a one-node addition under `LanguageSpecific` plus an
entry in `Common.SupportedLanguages`; no changes are required in
`PatchBaseline` or `Pca2023` (both are language-neutral).

## B.5 Phase contracts (P01–P13)

**Status**: normative.

The pipeline consists of 13 phases organised into 5 groups:

| Phase | Group | Purpose |
|:---:|:---:|:---|
| P01 | Setup | Initialize: env check, ADK, transcript start |
| P02 | Setup | ResolveInputs: load config, plan patch set |
| P03 | Setup | RefreshPatchBaseline: catalogue scrape (skippable) |
| P04 | Fetch | FetchAssets: download ISO + patches |
| P05 | Plan | ExpandIso: robocopy expand into workspace |
| P06 | Plan | ValidatePatchServicing: pass-through (Catalog-model consistency check pending; see B.19) |
| P07 | Build | PatchInstallWim: apply LCU / .NET / DU to install.wim |
| P08 | Build | PatchBootWim: apply SSU / LP / LCU to boot.wim + WinRE.wim |
| P09 | Build | AssembleIso: oscdimg re-emit |
| P10 | Build | ConvertPca2023BootManager (optional, see §B.17) |
| P11 | Verify | StaticVerify: hash, size, structure |
| P12 | Verify | VerifyPca2023Readiness: input + output snapshot |
| P13 | Report | FinalReport: aggregate Health verdict |

Each phase function carries one of the following skip conditions
which MUST be checked at the top of the function before any side
effect:

```
P03:  -UseBaselineOnly        OR  -SyntheticTestMode
P04:  -SyntheticTestMode      (uses New-SyntheticTestIso)
P06:  -UseBaselineOnly  OR  -SyntheticTestMode
P07:  -not Common.EnableInstallWimUpdate
P08:  -not Common.EnableBootWimUpdate (per-target sub-checks)
P10:  opt-in; runs only when -EnablePca2023BootManager is set (default OFF)
P12:  none (always runs)
P13:  none (always runs)
```

Phase **outputs** are persisted as JSON under `<WorkRoot>/diag/`
when `-Verbose` is set or on failure. Each phase reports an
elapsed-time tuple to the `$Script:PhaseTimingSummary` collection
that `Show-PhaseSummary` (idempotent since r07.0 Step 19) renders at
script exit.

## B.6 Action → Phase mapping

**Status**: normative.

The `param()` `ValidateSet` on `-Action` declares fourteen Actions.
The default is `PrepareBuildVerify`. The full list, grouped by purpose:

### B.6.1 Standard pipeline Actions

| Action | Phases run | Description |
|:---|:---|:---|
| `Prepare` | P01-P06 | Stage only (no patching, no DISM mount) |
| `Build` | P07-P10 | Patch and assemble; presumes Prepare already staged the workspace |
| `Verify` | P11-P13 | Verify an existing output ISO (presumes a prior Build -Execute produced it) |
| `PrepareBuildVerify` (default) | P01-P13 | Combined full pipeline (the standardFull sequence in `Get-PhaseListByAction`) |
| `All` | P01-P13 + post-pipeline extras | StandardFull plus the additional steps gated by `if ($Action -in @('BootTest','All'))` |

### B.6.2 Specialty Actions

| Action | Phases run | Description |
|:---|:---|:---|
| `BootTest` | (empty Phase array; Hyper-V smoke test) | Stand-alone Hyper-V Gen2 boot smoke test against the output ISO. Mutually exclusive with `-SyntheticTestMode` (parameter-exclusivity guard block) |
| `GenerateManifest` | P01-P03 | Compute a manifest of resolved patches without proceeding to Fetch / Build / Verify |
| `Cleanup` | (custom; `Invoke-CleanupAction`) | Clean up workspace and stale DISM mounts |
| `ListPhases` | (none) | Dump phase + action registry as JSON to stdout |
| `TestHarness` | (JSON-over-stdin REPL hook, the `TestHarness` short-circuit before phase dispatch) | Eval-PS-function mode used by `tests/powershell_harness.py` (T3); not for human invocation |

### B.6.3 Admin Actions (A00 - A01 - A03 - A02)

| Action | Admin Phase | Phases run | Description |
|:---|:-:|:---|:---|
| `RebuildDataset` | A00 | (`Invoke-AdminPhaseA00_RebuildDataset`) | Rebuild every `data/config-Server*.json` from `data/seed/seed-Server*.json` + caches (validate seeds, A03 snapshots, build skeletons, A01 Force fill, verify); runnable from empty |
| `RefreshAllBaselines` | A01 | (`Invoke-AdminPhaseA01_RefreshAllBaselines`) | Refresh `data/config-Server*.json` baselines from upstream caches |
| `DumpFieldClassification` | A02 | (`Invoke-AdminPhaseA02_DumpFieldClassification`) | Emit the field-cadence decision matrix as JSON |
| `RefreshSnapshots` | A03 | (`Invoke-AdminPhaseA03_RefreshSnapshots`) | Refresh `data/raw-*` and `data/cache-*` from Microsoft Learn + Catalogue |

### B.6.4 Action semantics

- The `$osLessActions` set — `ListPhases`, `Cleanup`,
  `RefreshSnapshots`, `RefreshAllBaselines`, `RebuildDataset`,
  `DumpFieldClassification`, `TestHarness` — does not require `-OsVersion`. All other Actions
  REQUIRE `-OsVersion` (the `$osLessActions` gate before workspace init).
- `Verify` running standalone presumes the output ISO was produced by
  a prior `Build -Execute`; if missing, P11 reports `Critical`.
- `Prepare` produces a workspace ready for a later `Build` invocation;
  it MAY be used as a dry-run for staging correctness without the cost
  of DISM mount.
- `-OnlyPhases <phase[]>` overrides the Action's phase set — useful
  for forensic re-runs of a single phase.

## B.7 Source-ISO resolution

**Status**: normative.

P02 ResolveInputs resolves the source ISO through exactly three
mutually exclusive branches (no directory scanning or filename-pattern
auto-detection exists):

| Branch | Condition | Resulting `IsoLocalPath` |
|:---:|:---|:---|
| 1 | `-SyntheticTestMode` | `<WorkRoot>/source/iso/synthetic.iso`, generated in P04 |
| 2 | `-IsoPath <file>` | The given local file (must exist; resolved relative to the script) |
| 3 | otherwise | `<WorkRoot>/source/iso/<OsShortName>_<lang>.iso`, downloaded in P04 from `Resolve-IsoSourceUrl` (`-IsoUrl` if given, else the config's `LanguageSpecific.<lang>.Iso.Url`) |

P04 verifies the staged ISO against the config's
`LanguageSpecific.<lang>.Iso.Sha256` when present. To use a
pre-downloaded ISO (for example a Microsoft Evaluation Center image),
pass it via `-IsoPath`; to point at a different download source, pass
`-IsoUrl`.

## B.8 Patch integrity check (three-layer)

**Status**: normative. **Policy ID**: SPEC-WSI-011.

P04 verifies each patch download against **three independent
sources of truth**:

| Layer | Source | Field |
|:---:|:---|:---|
| 1 | The Microsoft Update Catalogue download link | server-reported `Content-Length` |
| 2 | The config-Server*.json `Lines[]` entry | recorded `Sha256` |
| 3 | The downloaded file on disk | freshly-computed SHA-256 |

A patch passes integrity check when all three layers agree. Layer 2's
hash MUST have been recorded by a prior `RefreshAllBaselines` (or by
manual entry that survived `_VerifiedBy` review).

`Test-PatchIntegrity` uses SHA-1 for the legacy `MetaLink` source
where Microsoft has not migrated to SHA-256; this is intentional and
documented in §D.5.

## B.9 Synthetic test mode

**Status**: normative. **Policy ID**: SPEC-WSI-010.

`-SyntheticTestMode` causes the script to run the orchestration
without contacting Microsoft endpoints or executing DISM mount
operations. Specifically:

- P03 (RefreshPatchBaseline) is skipped.
- P04 (FetchAssets) calls `New-SyntheticTestIso` to fabricate a
  synthetic ISO file with the correct shape but minimal contents.
- P06 (ValidatePatchServicing) is skipped (no real patches to validate).
- P07, P08, P10 are guarded by `if (-not $SyntheticTestMode) { ... }`
  blocks that emit `Write-Skip` lines.
- P11, P12, P13 run on the synthetic output and produce reports.

CI Stage 3 (`...__stage3__synthetic.yml`) exercises this mode end to
end. It MUST NOT upload any artefact containing Microsoft binary
content; this is enforced by the workflow file's explicit
`actions/upload-artifact` `path:` enumeration per the repository
[Artifact Content Minimization](https://github.com/usui-tk/ai-generated-artifacts/blob/main/SPEC.md#12-spec-ci-081-artifact-content-minimization)
policy.

---


## B.10 PatchPlan engine and WIM-target mapping

**Status**: normative. **Policy ID**: SPEC-WSI-013.

`Build-PatchPlan` converts a flat patch list into a target-aware plan
with four lanes: `Install`, `Boot`, `WinRE`, `Setup`. The mapping
from patch `Type` to target lanes lives in `$Script:PatchTargetMap`.

The default mapping follows Microsoft's media-dynamic-update
guidance:

| Patch Type (Config Schema v3.0 `Kind`) | Target lanes | Microsoft rationale |
|:---|:---|:---|
| `SSU`             | Install + Boot + WinRE | Every serviced WIM needs the latest servicing stack |
| `LCU`             | Install + Boot         | WinRE uses the SafeOS DU instead |
| `DotNet`          | Install                | .NET 4.x runtime KB lives in install.wim |
| `SafeOSDU`        | WinRE                  | WinRE is the "Safe OS" |
| `SetupDU`         | Setup                  | Setup binaries; P09 expands the CAB with `expand.exe` and overlays the files onto the extracted ISO `sources\` tree (never WIM-mounted) |
| `LanguagePack`    | Install + WinRE        | User-facing UI + recovery UI |
| `LXP`             | Install                | LXPs are Store apps; no WinRE |
| `DotNet.LangPack` | Install                | .NET satellite assemblies |

Within each lane, patches are ordered by ascending `ApplyOrder`
(secondary key: `KbId`). Phase workers iterate the lane that matches
the WIM they have mounted; the Install lane worker also runs the
pre-apply dependency closure check (§B.13) before the first
`Add-WindowsPackage` call.

The plan object carries diagnostic fields: `_GeneratedAt`,
`_PatchCount`, `_TargetCounts`, `_UnknownTypes`. Unknown Types fall
back to `[Install]` with a one-time warning per unique Type per run.

**Resolved patch entry shape**. Build-PatchPlan reads
`$Script:ResolvedPatches`, each entry of which carries (in
addition to the fields in §B.4.3):

```
PatchType : 'SSU' | 'LCU' | 'DotNet' | 'SafeOSDU' | 'SetupDU'
            | 'LanguagePack' | 'LXP' | 'DotNet.LangPack'   ← authoritative
ApplyOrder: 1..N
KbId      : 'KB...'
```

The field name `PatchType` (NOT `Type`) is normative; a
`Get-PatchEntryType` helper exists to read it back through a
dual-field fallback path. The historical incident where six
functions read `$_.Type` instead of `$_.PatchType` is documented in
§D.30.

## B.11 Media-dynamic-update sub-phase sequences

**Status**: normative. **Policy ID**: SPEC-WSI-014.

For each WIM target, `Build-PatchPlan` emits an ordered array of
sub-phase descriptors (named after Microsoft documentation: I =
install, B = boot, W = winre). Each sub-phase carries:

| Field | Meaning |
|:---|:---|
| `Name` | symbolic identifier (e.g. `I3.LCU.FirstPass`) |
| `Description` | one-line human-readable purpose |
| `Patches` | array of patches that belong to this sub-phase |
| `RequiresRemount` | if `$true`, the worker dismounts the WIM, lets DISM commit and export, then re-mounts a fresh copy |
| `IsCleanupMarker` | if `$true`, the worker runs DISM /Cleanup-Image and skips Add-WindowsPackage |

### B.11.1 install.wim (P07)

| # | Name | Microsoft rationale |
|:-:|:---|:---|
| 1 | `I1.SSU`                     | Servicing stack first |
| 2 | `I2.LanguagePack`            | UI before LCU's resource files |
| 3 | `I3.LCU.FirstPass`           | LCU after LP per Microsoft doc |
| 4 | `I4.DotNet`                  | .NET 4.x cumulative (Kind `DotNet` only) |
| 5 | `I5.DynamicUpdate.Component` | Reserved slot mirroring Microsoft's documented sequence; the baseline Kind vocabulary does not currently produce this type, so it is normally empty |
| 6 | `I6.CleanupAndExport`        | DISM /Cleanup + Export |
| 7 | `I7.LCU.SecondPass`          | Emitted ONLY when LP was injected; `RequiresRemount = $true`; the LP injected in I2 can shadow files delivered by the I3 LCU, so the LCU is re-applied on a freshly-exported image |

### B.11.2 boot.wim (P08)

`B1.SSU` → `B2.LanguagePack` → `B3.LCU` → `B4.CleanupAndExport`. No
twice-apply needed.

### B.11.3 WinRE.wim (P08 inner block)

`W1.SSU` → `W2.LanguagePack` → `W3.SafeOsDU` →
`W4.CleanupAndExport`. The WinRE image is NOT serviced with LCU;
Microsoft delivers a Safe OS Dynamic Update that plays the LCU role
for the recovery environment.

`Invoke-PatchSubPhase` is the single helper that drives the apply
loop for any sub-phase. Phase workers iterate the sequence, calling
`Invoke-PatchSubPhase` for content-bearing sub-phases and running
`Invoke-DismCleanup` for `IsCleanupMarker` sub-phases.

**Cleanup / export policy (r11.25).** The per-image cleanup is
`/Cleanup-Image /StartComponentCleanup /ResetBase` by default.
`/ResetBase` resets the component-store base (smaller image, applied
updates no longer removable) -- the correct default for a patched
golden ISO that ships the latest updates already applied (uninstalling
them is not a use case), and empirically the faster cleanup on
heavily-agented hosts (bulk base reset vs granular per-component
scavenging). `-SkipResetBaseOnCleanup` opts out (keeps updates
removable). All heavy DISM operations write scratch to a
workspace-local `$Script:ScratchDir` (`<WorkRoot>\work\scratch`):
`Add-WindowsPackage` via `-ScratchDirectory`; `/Cleanup-Image` and
`/Export-Image` via a `/ScratchDir:` token. The
"Export" half of `I6.CleanupAndExport` is realised as a single
post-loop pass: after every install.wim index has been serviced and
dismounted, `Export-InstallWimCompressed` runs one
`dism.exe /Export-Image ... /Compress:max` over all indexes (in index
order, preserving every edition) into a fresh WIM and replaces
install.wim, recompressing and single-instancing files shared across
editions. The exported WIM is index-count-verified before the swap;
on failure the original is left untouched. Default ON; `-SkipExportCompress`
opts out.

**Defender exclusion option (r11.26).** `-UseDefenderExclusions` (opt-in,
default off, security-affecting) temporarily excludes the `WorkRoot` tree and
the servicing processes (`dism.exe`, `DismHost.exe`, `TiWorker.exe`,
`TrustedInstaller.exe`, by file name) from Windows Defender real-time scanning
for the duration of a run, then removes them. A controlled A/B probe measured
~35% faster LCU apply with the exclusion; the cleanup is storage-bound and
unaffected. It is **fail-closed** (`Get-DefenderExclusionDecision`): applied
only when Defender is present, `WinDefend` is running, real-time protection is
on, Tamper Protection is off and `AMRunningMode` is `Normal`; any unmet or
unknown state skips the feature (the build continues unexcluded). Additions are
recorded to `<WorkRoot>\state\defender-exclusions.json`; only recorded entries
are removed (in the top-level `finally` and via a startup self-heal of a
crashed run), never pre-existing user exclusions.

## B.12 Catalogue scrape and candidate selection

**Status**: normative (r11.34+). **Policy ID**: SPEC-WSI-015.

Layer 1 of the b3 resolver (the producer, B.19) acquires each `Kind`'s
files from the Microsoft Update Catalog from an OS *seed* alone, with no
local applicability graph:

1. the authoritative LCU KB is read from the Microsoft Learn
   `windows-server-release-info` markdown (`Get-LearnLcuKbs`, keyed by
   the OS build-major), so the *latest* LCU is fixed by Microsoft's
   published servicing calendar rather than inferred locally;
2. that KB (for the LCU) or a per-`Kind` Title query (SSU / .NET / DU)
   is run through `Search-Catalog` (Search.aspx);
3. `Get-ServerRow` narrows the result rows to the OS `Products` token
   and x64;
4. `Resolve-CatalogDownload` (DownloadDialog.aspx) returns the file set
   - each file as a SHA-1 base64 `Digest` + URL, with no download.

Because the LCU is pinned by the Learn release-info, candidate
selection collapses to "the row whose `Products` token matches the OS";
there is no supersedence-chain walk. The acquired set is then reconciled
against the release-info expected KB + post-update build by Layer 2
(B.19), and shaped into `PatchBaseline.Lines[]` by `ConvertTo-ConfigLines`.

> **Removed in the data-source migration.** The pre-v3.0 model resolved
> the latest patch by enriching each narrowed candidate with
> `Supersedes`/`SupersededBy` from `Get-SupersedenceFromCatalog` and
> running `Select-LatestPatchBySupersedence` over a per-candidate
> ScopedView supersedence walk. That selection mechanism is no longer
> used: the Learn release-info fixes the latest LCU directly, and the
> `Lines[]` shape carries no `Supersedes` field
> (`schema/config.schema.json` sets `additionalProperties: false`). The
> r04.2 umbrella-KB incident that motivated the old walk is preserved in
> §D for historical reference.

## B.13 Pre-apply dependency closure check

**Status**: normative. **Policy ID**: SPEC-WSI-012.

`Test-PatchServicingReadinessOnMount` runs inside the per-WIM apply
loop just after `Mount-WindowsImage` and before the first
`Add-WindowsPackage`. For each patch whose `RequiresKbIds` is
non-empty, it enumerates installed packages via `Get-WindowsPackage`
and verifies that every required KB is already present
(`PackageIdentity` substring match against the recorded KB ID).

The check is governed by `$Script:PatchDependencyPolicy`, a
script-scope constant:

| Value | Behaviour |
|:---|:---|
| `Strict` | **Default.** Throw on the first unsatisfied prerequisite; the run aborts before DISM emits the cryptic `0x800f0823` hex code |
| `Warn`   | Write a warning and continue |

There is currently no CLI flag for this policy; a wrapper script can
set `$Script:PatchDependencyPolicy = 'Warn'` before invocation if
needed.

`-DryRun` short-circuits the check with a notice (no real mount).

**Relationship to §B.19 (Servicing Dependency Database)**: §B.13's
check operates on a **mounted** WIM and reads the actual installed
package list. It is runtime-accurate. The earlier pre-mount graph
readiness check (`Test-PatchServicingReadinessFromGraph`) that read the
wsusscn2 layer 2 database was removed in the data-source migration (see
§B.19); §B.13's on-mount check (`Test-PatchServicingReadinessOnMount`) is
now the sole servicing-readiness check, running during the build in
P07/P08.

## B.14 Data pipeline and refresh policy

**Status**: normative. **Policy ID**: SPEC-WSI-016.

The `data/` dataset is a pure function of a committed **SEED** plus a set
of **DERIVED** fields regenerated from authoritative upstream sources.
This section defines the single rebuild entry point (B.14.1), the
SEED/DERIVED boundary that makes a from-empty build possible (B.14.2), and
the field-cadence matrix that governs an incremental in-place refresh
(B.14.3).

### B.14.1 Execution entry point — `A00 RebuildDataset`

The dataset has exactly one canonical rebuild entry point. It regenerates
`data/` from the committed seed and upstream sources and is runnable from
empty (no pre-existing `data/config-Server*.json` required):

```
update-windows-server-iso.ps1 -Action RebuildDataset -PatchMonth <yyyy-MM> [-OnlyOs <key>] [-SkipEnvCheck]
```

Stages, in order:

1. **Seed validation** — validate `data/seed/seed-Server*.json` against
   `schema/config-seed.schema.json`; an absent or invalid seed is a hard
   failure (the dataset cannot be built without it).
2. **Snapshots** — `RefreshSnapshots` (A03): acquire `data/raw-*` /
   `data/cache-*` from upstream.
3. **Config build** — for each seed, assemble the full
   `data/config-Server*.json` = seed + DERIVED (B.14.2) + generated
   `_meta`.
4. **Verification** — validate each built config against
   `schema/config.schema.json` and run the currency gates.

Because stage 2 performs network acquisition, the whole action is
long-running / hang-prone and MUST be run detached + polled, never
synchronous-foreground (data-generation hazard policy, handoff B.2.9). A00
carries no `-OsVersion` (a member of `$osLessActions`).

**Evidence**: [WORKING] implemented at P2 (`Invoke-AdminPhaseA00_RebuildDataset` + `Build-ConfigSkeletonFromSeed`). A00 formalizes a sequence
that today exists ONLY as the manual A03→A01 procedure in TESTING.md §8.
The absence of an explicit, gate-checked entry point — the orchestration
living only in prose — is the documented root cause this section corrects.
A00 is now the live entry point (B.6.3); it runs the A03→A01 order
internally, so the rebuild no longer depends on a hand-run procedure.

### B.14.2 SEED vs DERIVED boundary

The SEED is the only hand-maintained input; everything DERIVED is
reproducible from {seed, `-PatchMonth`, caches/Catalogue} with no
dependency on a prior config.

| Config region | Class | Source |
|:---|:---|:---|
| `Schema` / `OsKey` / `PatchModel` | SEED | committed (static identity) |
| `Common` (B.4.2) | SEED | committed; ISO-structural, optionally discovered via `Get-WimIndexInventory` |
| `Pca2023` / `AutoRefreshPolicy` | SEED | committed (policy) |
| `LanguageSpecific.<lang>` (`DisplayName` / `Iso` / `VolumeLabelPrefix`) | SEED | committed (per-language label + ISO source) |
| `PatchBaseline` envelope (`Schema` / `ChecksumAlgorithm`) | SEED | committed (static servicing policy; `VerificationMethod` / `ExcludeKbList` retired r11.46) |
| `PatchBaseline.TargetBuildAfterUpdate` | DERIVED | refresh writeback: the LCU Line's `InScope.build` (r11.46; consumed by P11 `LcuTargetApplied`) |
| `PatchBaseline.Lines` (B.4.3) | DERIVED | `Invoke-CatalogPatchSetRefresh` ← `data/cache-*` |
| `LanguageSpecific.<lang>.LanguageSpecificPatches` | DERIVED | `Resolve-LanguageSpecificPatchesFromCatalog` ← Catalogue |
| `_meta` | DERIVED | generated (provenance) |

Both DERIVED Refreshers take only `-OsVersion` / `-PatchMonth` and read the
caches; they do NOT read the existing config (`Invoke-CatalogPatchSetRefresh`
resolves `OsKey`/`PatchModel` from internal maps and reads
`Get-ReleaseInfoCache`). This is precisely what makes a
from-empty build possible: the SEED supplies everything the Refreshers
cannot derive, and the Refreshers supply everything the SEED omits. The
per-group refresh stamps (`LastVerifiedDate` / `LastVerifiedBy` /
`PatchTuesdayOfBaseline`, on `PatchBaseline` and each
`LanguageSpecificPatches`) and `_meta` are likewise generated at rebuild
time, not carried in the seed.

This SEED/DERIVED boundary is enforced mechanically, not by prose: the
`seed_contract_test` gate asserts that every field in
`schema/config.schema.json` is classified as exactly one of SEED (admitted
by `schema/config-seed.schema.json`) or DERIVED, so a config-schema field
can never be silently dropped from the seed (the defect class that the
coarse `PatchBaseline`-as-one-unit reading first produced).

**Evidence**: script-body ground truth — `$Script:OsConfigFieldGroups`
(field-classification constant) and `Invoke-CatalogPatchSetRefresh` (L5283).
The seed contract is realized by `schema/config-seed.schema.json` and
`data/seed/seed-Server*.json` — a projection of `schema/config.schema.json`
that carries every SEED region and forbids the DERIVED ones (`PatchBaseline`,
`LanguageSpecific.<lang>.LanguageSpecificPatches`, `_meta`). The `A00`
builder that assembles a full config from them is `Build-ConfigSkeletonFromSeed`
(lays the seed into the config shape with empty DERIVED placeholders), with
`Invoke-AdminPhaseA00_RebuildDataset` orchestrating the rebuild (B.14.1).

### B.14.3 Field-cadence decision matrix

The `$Script:OsConfigFieldGroups` constant maps each logical field group to
a Cadence and an optional Refresher. It drives the incremental
`-Action RefreshAllBaselines` (A01) refresh of an EXISTING config:

| Group Path | Cadence | Refresher |
|:---|:---|:---|
| `Common` | Stable | (none) |
| `PatchBaseline` | PatchTuesday | `Invoke-CatalogPatchSetRefresh` |
| `LanguageSpecific.<lang>.Iso` | IsoRelease | (none) |
| `LanguageSpecific.<lang>.LanguageSpecificPatches` | PatchTuesday | `Resolve-LanguageSpecificPatchesFromCatalog` |

Cadence semantics:

- **Stable**: once verified, never auto-refresh (SEED; B.14.2).
- **PatchTuesday**: refresh when recorded `PatchTuesdayOfBaseline` is
  older than the latest Patch Tuesday.
- **IsoRelease**: only refresh when Microsoft re-releases the ISO;
  not auto-refreshed in the current implementation (manual; SEED).

Decision matrix (returned by `Get-RefreshDecision`):

| Cadence \\ State | `_VerifiedDate` empty | recorded < latest PT | up-to-date |
|:---|:---|:---|:---|
| Stable | InitialFill or Manual | (N/A) | Skip |
| PatchTuesday | Monthly (or Manual if no Refresher) | Monthly | Skip |
| IsoRelease | InitialFill or Manual | (N/A) | Skip |

`-Mode Force` overrides: never returns Skip; collapses to Monthly /
InitialFill / Manual depending on Refresher availability.

The full JSON shape of `$Script:OsConfigFieldGroups` is exposed via
`-Action DumpFieldClassification` (A02) so external tooling (e.g. a
Python JSON Schema validator) can consume it without parsing
PowerShell.

> **Relationship between A00 and A01.** A01 refreshes the DERIVED groups of
> an EXISTING config in place (this matrix). A00 (B.14.1) builds the whole
> config from the SEED, so it depends on no prior config and is the
> from-empty entry point. Once A00 lands (P2), A01 is the incremental
> monthly refresh and A00 the canonical full rebuild.

## B.15 Update type matrix per OS generation

**Status**: normative. **Policy ID**: SPEC-WSI-017.

### B.15.1 The matrix

Microsoft ships different update product mixes across the OS
generations supported by this script. The matrix below records the
per-OS / per-Type stance the script enforces during baseline
resolution.

| Kind | Server 2016 (`separate-ssu`) | Server 2019 (`embedded-ssu`) | Server 2022 (`embedded-ssu-du`) | Server 2025 (`uup-checkpoint`) |
|:---|:---:|:---:|:---:|:---:|
| `SSU`          | required line (standalone) | in-model forbidden as a line (embedded in the combined LCU since 2024-4B) | in-model forbidden as a line (embedded in the combined LCU) | required line (UUP checkpoint SSU) |
| `LCU`          | required line | required line (combined LCU+SSU) | required line (combined LCU+SSU) | required line (WIM-format MSU) |
| `DotNet`       | in-model forbidden as a line | required line | required line | required line |
| `SafeOSDU`     | in-model forbidden as a line | in-model forbidden as a line | required line | required line |
| `SetupDU`      | in-model forbidden as a line | in-model forbidden as a line | in-model forbidden as a line | optional line (the only model that carries it) |
| `LanguagePack` | bundled in the source ISO | bundled in the source ISO | bundled in the source ISO | bundled in the source ISO |
| `LXP`          | n/a (no LXP for Server SKU) | n/a | n/a | n/a |

"Required / forbidden line" refers to the in-model Require / Forbid
contract enforced by `ConvertTo-ConfigLines` per `PatchModel` (B.19);
it is a statement about the committed baseline `Lines[]`, not about
what Microsoft ships in general.

Whether an OS ships its servicing stack as a standalone SSU or folds it
into the combined LCU is, in Config Schema v3.0, declared by the
top-level `PatchModel` (B.4.1 / B.19), not by a per-entry flag:
`separate-ssu` (Server 2016) carries a standalone `SSU` line beside the
`LCU`; `embedded-ssu` / `embedded-ssu-du` (Server 2019 / 2022) fold the
SSU into the combined LCU; `uup-checkpoint` (Server 2025) carries the
checkpoint SSU from the co-served baseline. The v3.0 `Lines[]` shape has
no `IsCombined` field; the pre-v3.0 flag and the r08.0 mis-record defect
on `config-Server2016.json` are referenced from §D.

### B.15.2 .NET CU multiplicity per OS

The .NET Framework Cumulative Update is delivered as an **umbrella
KB** that bundles N "ndp" runtime variants (e.g. `ndp48`, `ndp481`)
in separate `.msu` files but under one Catalogue UpdateId. The
resolver retains all surviving `.msu` files, so the `Lines[]` entries
share `KbId` / `Title` / `UpdateId` from the umbrella KB but each
carries its own `FileName` / `Digest` / `Sha256`.

| OS family | Expected .NET CU sub-file count |
|:---|:---:|
| Server 2016 | 1 (ndp48 only; older runtimes are out of support) |
| Server 2019 | 2 (ndp48 + ndp481) |
| Server 2022 | 2 (ndp48 + ndp481) |
| Server 2025 | 2 (ndp481 + ndp482, depending on month) |

The Server 2016 entry is intentionally a single MSU because earlier
.NET versions reached end-of-support before this script's baseline.
The umbrella-KB pattern, the historical r04.2 regression where
N-1 sub-files were dropped, and the r04.3 fix via
`Select-AllCanonicalPatchFiles` are recorded in §D.21.

### B.15.3 Combined LCU package detection

In Config Schema v3.0 the standalone-vs-combined SSU question is
answered by the declared `PatchModel` (B.19), not by title heuristics:
`separate-ssu` requires a standalone `SSU` line, while the `embedded-*`
models forbid one (`Test-PatchModelConsistency` enforces this at P06).
The pre-v3.0 `Test-IsCombinedLcuTitle` Title-matching helper that set a
per-entry `IsCombined` flag is legacy and no longer drives
`Build-PatchPlan`.

### B.15.4 Hotpatch is out of scope

Hotpatch (in-memory binary patching) is shipped only for specific
Azure Edition SKUs and produces a different patch flow. This script
targets the standard Datacenter / Standard SKUs and does not
integrate hotpatch into the offline image.

`tests/release_info_parser_test.py` includes assertions that the
release-info parser correctly classifies hotpatch rows so the
distinction is enforced at baseline-resolution time.

## B.16 LCU package format per OS

**Status**: informative.

### B.16.1 MSU format generation

The MSU file format evolved across the four supported OS families.
The r08.0 Step 1 investigation enumerated the structures by
physical expansion of each LCU:

| OS | LCU KB (2026-05) | MSU size | Magic | Stages to extract | Format generation |
|:---|:---|:---|:---:|:---:|:---|
| Server 2016 | KB5087537 | 1,776 MB | MSCF (CAB) | 3 | Legacy standalone LCU |
| Server 2019 | KB5087538 | 821 MB | MSCF (CAB) | 4 | UUP + PSFX v1 (combined LCU+SSU) |
| Server 2022 | KB5087545 | 539 MB | MSCF (CAB) | 4 | UUP + PSFX v1 / ForwardOnly |
| Server 2025 | KB5087539 | 1,929 MB | **MSWIM (WIM)** | 2 (WIM nesting) | **WIM + PSF v2 (PSTREAM)** |

Server 2025's WIM-format MSU is a genuine generation change:
expansion requires `DISM /Apply-Image` rather than `expand.exe`. The
payload is split into a small manifest WIM (~184 MB) and a large PSF
(PSTREAM) v2 blob containing the actual binaries.

### B.16.2 EFI_EX provenance — LCU-delivered vs install.wim-resident

Where does the `\Windows\Boot\EFI_EX\` staging directory come from?
The r08.0 Step 1 / Step 2 investigation established this is
**OS-dependent**:

| OS | install.wim ships EFI_EX? | LCU delivers EFI_EX? | Acquisition path |
|:---|:---:|:---:|:---|
| Server 2016 | No (verified via direct mount) | Yes (6 unique binaries) | Apply LCU → EFI_EX is deposited into the serviced install.wim's `\Windows\Boot\EFI_EX\` (signtool `/all`-verified: `bootmgfw_EX.efi` = "Windows UEFI CA 2023"); the conversion sources it from there (path under verification, §B.16.4) |
| Server 2019 | No (verified) | Yes (6 unique binaries) | Same as Server 2016 |
| Server 2022 | No (verified) | Yes (6 unique binaries) | Same |
| Server 2025 | **Yes** (72 files pre-populated) | No (0 `*_EX.efi` binaries in LCU) | install.wim contains assets natively; P10 can run without LCU |

This is the technical justification for §B.4.4's `Pca2023.RequiredByDefault`
being `false` only for Server 2025.

### B.16.3 EFI_EX file-by-file signature inventory (Server 2025)

Direct inspection of Server 2025 install.wim's `EFI_EX/` showed:

| File | Signer chain | Notes |
|:---|:---|:---|
| `EFI_EX\bootmgfw_EX.efi` | **PCA2023** (single-sign) | The critical PCA2023 asset for P10 |
| `EFI_EX\bootmgr_EX.efi` | **PCA2011** (single-sign) | Intentionally PCA2011 per Microsoft `Make2023BootableMedia.ps1` (`v1.6.4-signed`, commit `bd7abe3`; function `Copy-2023BootBins`) |

Neither file is dual-signed. The "PCA2011 + PCA2023 dual-sign"
hypothesis briefly entertained during r08.0 Step 2 was disproved by
`signtool /verify /pa /all /ds 0..3`; only one embedded signature
exists per file. Both files share PE-body bytes with their EFI/
counterparts (Authenticode hash matches because Authenticode hash
excludes the signature region).

### B.16.4 Pipeline implications

- P07 applies the LCU to install.wim before P09 / P10 (when
  `EnableInstallWimUpdate=true`).
- The PCA2023 boot manager (`bootmgfw_EX.efi`, "Windows UEFI CA 2023")
  is LCU-delivered into the **serviced install.wim's**
  `\Windows\Boot\EFI_EX\`, NOT into boot.wim (signtool `/all` ground
  truth; the unpatched install.wim has no `EFI_EX\`). The earlier
  "P08 surfaces EFI_EX from install.wim's WinSxS into boot.wim" step
  is **disproven and was never implemented**: the OS LCU does not
  service WinPE/boot.wim (Microsoft Learn "Add an Update to a Windows
  PE Image"; empirically `0x80070032` for the combined `.msu` and
  `0x8007371b` for the extracted `.cab` — missing WinPE
  `BootEnvironment-*-PXE.Resources` members), so boot.wim is not made
  current by the OS LCU and the staging assets never reach it.
- P10 therefore sources EFI_EX from the serviced install.wim. The
  exact conversion path (pre-seed the install.wim EFI_EX into the
  media + delegate to Microsoft `Make2023BootableMedia.ps1` + ADK) is
  **under real-environment verification** (see the Secure-Boot
  campaign; the final mechanism text lands once verified).
- For Server 2025, P10 can short-circuit via the
  `RequiredByDefault=false` policy, since the install.wim already
  contains the assets natively.

## B.17 PCA2023 boot manager support

**Status**: normative. **Policy ID**: SPEC-WSI-018.

### B.17.1 Conversion target inventory (Microsoft 5-target spec)

The Microsoft authoritative reference is
`scripts/windows/Make2023BootableMedia.ps1` (`v1.6.4-signed`, commit
`bd7abe3` in the `microsoft/secureboot_objects` repository; `main` is
byte-identical to that tag — the script's internal version string still
reads "1.4", so the tag/commit identifies it, not the internal string),
function `Copy-2023BootBins`. Five targets are written into the
output media:

| # | Source (in boot.wim) | Destination (in ISO root) | Required | Expected signer |
|:-:|:---|:---|:---:|:---|
| 1 | `Windows\Boot\EFI_EX\bootmgfw_EX.efi` | `\efi\boot\bootx64.efi` (or `bootaa64.efi`) | required | **PCA2023** |
| 2 | `Windows\Boot\EFI_EX\bootmgr_EX.efi` (if present) | `\bootmgr.efi` | optional | **PCA2011 by Microsoft design** (see B.16.3) |
| 3 | `Windows\Boot\DVD_EX\EFI\en-US\efisys_EX.bin` | `\efi\microsoft\boot\efisys_ex.bin` | required | n/a (binary) |
| 4 | `Windows\Boot\FONTS_EX\*_EX.ttf` (rename) | `\efi\microsoft\boot\fonts\*.ttf` | required | n/a (fonts) |
| 5 | `Windows\Boot\EFI\boot.stl` (best-effort) | `\EFI\Microsoft\Boot\boot.stl` | optional | n/a (cert trust list) |

`Convert-WimBootToPca2023Signed` (this project's `Make2023BootableMedia.ps1`
re-implementation) follows the same 5-target contract. The function
is PSA-clean and does not call out to the external script.

### B.17.2 In-tree readiness functions

Two functions cooperate to gate P10:

- `Get-IsoBootCertReadiness` — reads boot.wim's `\Windows\Boot\`
  contents, classifies the presence of `EFI_EX` / `Fonts_EX` /
  `DVD_EX`, and emits per-target presence flags. INPUT side.
- `Get-Pca2023ReadinessSnapshot` — combines `Get-IsoBootCertReadiness`
  output with the install.wim's `Get-AuthenticodeSignature` chain on
  `bootmgfw.efi` and emits a four-level health verdict:
  `Healthy` / `Warning` / `Critical` / `Unknown`.

P10 runs unless `Get-Pca2023ReadinessSnapshot` returns `Critical`
(skip-with-warn); for Server 2025 it also requires `-ForcePca2023OnServer2025`.

Both readiness paths classify a UEFI boot file's signer through the
shared `Test-Pca2023AuthenticodeChain` helper, which prefers the EMBEDDED
signature read by signtool `/v /all /pa` and falls back to
`Get-AuthenticodeSignature` + X509Chain when signtool is unavailable. The
embedded read is required because `Get-AuthenticodeSignature` follows the
catalog / cross-cert path and under-reports the LCU-materialized PCA2023
boot manager (§B.16.3) — most visibly on the converted OUTPUT `bootx64.efi`,
where the catalog read would otherwise mis-report a successful conversion
as still-PCA2011. signtool.exe is acquired on first use (§B.22.22); the
helper's `.Method` field records which path set the verdict.

### B.17.3 Per-OS readiness defaults

Per the matrix in §B.4.4:

- Server 2016/2019/2022: `RequiredByDefault=true`. P10 runs whenever
  `EnableInstallWimUpdate=true` and the LCU is at the configured
  minimum date.
- Server 2025: `RequiredByDefault=false`. P10 short-circuits with
  rationale "firmware already includes 2023 certs" unless
  `-ForcePca2023OnServer2025` is set.

### B.17.4 Microsoft Support reference

KB5053484 ("Updating Windows bootable media to use the PCA2023-
signed boot manager", 2025-02-04) lists Server 2012, 2012 R2,
**2016, 2019, 2022**, Windows 10, and Windows 11 as "Applies To".
Server 2025 is omitted because the article predates Server 2025
GA; Server 2025 ships with PCA2023 staging assets in install.wim
natively (§B.16.2).

## B.18 Output ISO verification

**Status**: normative. **Policy ID**: SPEC-WSI-019.

### B.18.1 Function: `Test-OutputIsoPca2023Readiness`

The function consumes an `ExtractedMediaPath` (the extracted output
ISO tree, not the boot.wim) and returns a structured verdict that
the §B.17 five-target contract was actually written to disk after
P10. Target signer classification (Targets #1 / #2) uses the shared
`Test-Pca2023AuthenticodeChain` helper, so the converted OUTPUT critical
path is judged by its EMBEDDED signature (signtool `/v /all /pa`), not the
catalog path — see §B.17.2 / §B.22.22.

```
Test-OutputIsoPca2023Readiness
    -ExtractedMediaPath <string>
    → returns:
        @{
            Generated      = <DateTime>
            Available      = $true | $false
            ErrorMessage   = <string when Available=$false>
            ExtractedMediaPath = <string>
            OverallStatus  = 'Pass' | 'PassWithNotes' | 'Warning' | 'Fail' | 'Unknown'
            TargetChecks   = @(<5 items: see B.18.2>)
            Reasons        = @(<string>...)  # includes SCOPE clarifier
        }
```

### B.18.2 TargetCheck status mapping

Each of the 5 targets is checked as follows. The
`OverallStatus` aggregator is `Fail > Warning > PassWithNotes >
Pass`.

| Target | Pass | PassWithNotes | Warning | Fail |
|:---|:---|:---|:---|:---|
| #1 `\efi\boot\bootx64.efi` | PCA2023 | — | — | PCA2011 / unknown / missing |
| #2 `\bootmgr.efi` | — | any signer or missing (L876-L884) | — | — |
| #3 `\efi\microsoft\boot\efisys_ex.bin` | present | — | — | missing |
| #4 `\efi\microsoft\boot\fonts\*.ttf` | present | — | missing or empty | — |
| #5 `\EFI\Microsoft\Boot\boot.stl` | present | missing (L909-L911) | — | — |

ARM64 variant: when `bootx64.efi` is absent, Target #1 falls back to
`bootaa64.efi` on the same path. The Status mapping is otherwise
identical.

### B.18.3 SCOPE clarifier (mandatory in Reasons)

Every invocation MUST append the following SCOPE statement to
`Reasons[]`, regardless of `OverallStatus`:

> "SCOPE: file presence + signer-chain only. Actual boot behaviour
> on firmware with PCA2011 revoked from DBX is NOT verified here.
> Manual boot test on hardware or a Hyper-V Gen2 VM with a PCA2023
> Secure Boot template is required before production deployment."

This makes it impossible for an operator to read a `Pass` verdict
and infer that the ISO will boot on PCA2011-revoked firmware
without an external test. Microsoft's own `Make2023BootableMedia.ps1`
performs zero signature verification; this script adds the
verification as an upstream-compatible quality extension.

### B.18.4 Phase integration

P10 post-flight: `Test-OutputIsoPca2023Readiness` runs immediately
after the file copies and the result is rendered via
`Show-Pca2023ReadinessSnapshot -OutputCheck $check -Compact`.

P12 (`Invoke-VerifyPhase12_VerifyPca2023Readiness`): always runs the
check; integrates `OutputCheck` into `pca2023_readiness.json` and
into `pca2023_readiness.md`'s 5-target Markdown table.

P13 FinalReport: rolls the per-target verdict into the aggregate
`Health` calculation. Any Target #1 `Fail` propagates to overall
`Health = Critical`.

### B.18.5 Implementation notes

The function uses `System.Collections.Generic.List[object]` for the
`TargetChecks` internal accumulator. When converting to the output
array shape, `.ToArray()` MUST be used; the array sub-expression
operator `@($list)` fails on `List[object]` of `pscustomobject`
under PowerShell 7.4.x with `Argument types do not match`. The full
root-cause analysis is in §D.26.

`Get-Pca2023ReadinessSnapshot` carries the result on a new
`OutputCheck` field, declared `$null` in both return paths so
property assignment downstream does not trigger
`PSA2009` (undeclared property). Inner-function declarations are
forbidden inside `Test-OutputIsoPca2023Readiness`; helpers MUST be
hoisted to top level next to `Test-Pca2023AuthenticodeChain`.

---


## B.19 Servicing model consistency check (P06)

**Status**: normative (r11.34+). **Policy ID**: SPEC-WSI-020.

The wsusscn2-derived Servicing Dependency Database documented in this
section through r11.x was removed in the data-source migration from
`wsusscn2.cab` to the Microsoft Update Catalog: the Layer 2
`data/servicing-dependency-database.json` database, its four-stage parser
pipeline, the `A04 RefreshDependencyDatabase` action, the scope-filter
GUID tables, and the graph readiness check
`Test-PatchServicingReadinessFromGraph` are no longer built or
maintained. Its replacement is a per-`PatchModel` consistency check over
the resolved Catalog patch set, implemented as `Test-PatchModelConsistency`
and run by P06 `ValidatePatchServicing` (B.5). It is the runtime mirror
of the discriminated union encoded in `schema/config.schema.json`.

### B.19.1 The discriminated union

Every config declares a top-level `PatchModel` (B.4.1). Each model fixes
which line `Kind`s are required and which are forbidden:

| `PatchModel` | OS | Required Kinds | Forbidden Kinds |
|:---|:---|:---|:---|
| `separate-ssu` | Server 2016 | `SSU`, `LCU` | `DotNet`, `SafeOSDU`, `SetupDU` |
| `embedded-ssu` | Server 2019 | `LCU`, `DotNet` | `SSU`, `SafeOSDU`, `SetupDU` |
| `embedded-ssu-du` | Server 2022 | `LCU`, `DotNet`, `SafeOSDU` | `SSU`, `SetupDU` |
| `uup-checkpoint` | Server 2025 | `LCU`, `SSU`, `DotNet`, `SafeOSDU` | (none; `SetupDU` allowed) |

Rationale: 2016 ships its servicing stack as a standalone SSU paired
with a standalone LCU; 2019 and 2022 embed the SSU in the combined LCU
(2022 additionally carries a Safe OS DU for WinRE); 2025 is the UUP
checkpoint model whose co-served GA baseline carries the checkpoint SSU.

### B.19.2 The check

`Test-PatchModelConsistency` enforces, over the resolved
`PatchBaseline.Lines[]`:

1. every Required Kind for the model is present at least once;
2. no Forbidden Kind appears;
3. every line carries a non-empty `Digest` (the Catalog primary key);
4. an unknown `PatchModel` raises a typed error.

P06 throws on any violation - the build stops before any WIM is mounted
- and on success logs the model and line count. This is a static shape
contract over the resolved set. (Note: the pre-v3.0 on-mount
dependency-closure check `Test-PatchServicingReadinessOnMount` (B.13)
keys on a `RequiresKbIds` field that the v3.0 `Lines[]` no longer carry,
so it is inert for Catalog-resolved sets; a real servicing-stack
precondition failure now surfaces from DISM during P07/P08.)

---

## B.20 File organisation and naming conventions

**Status**: normative (r06.0+).

### B.20.1 Directory layout

```
projects/powershell-update-windows-server-iso/
├── Update-WindowsServerIso.ps1     # Main script
├── README.md / README.ja.md         # End-user documentation (bilingual, lock-step)
├── SPEC.md                           # This file (English only)
├── TESTING.md                        # Verification procedures (English only)
├── CHANGELOG.md                      # Per-revision history (English only)
├── .psa.config.json                  # psa.py project configuration
├── PSScriptAnalyzerSettings.psd1     # PSScriptAnalyzer project configuration
│
├── data/                             # All persistent inputs (committed, flat layout)
│   ├── config-Server2016.json        # Per-OS config (4 files)
│   ├── config-Server2019.json
│   ├── config-Server2022.json
│   ├── config-Server2025.json
│   ├── raw-release-info.md           # Microsoft Learn release-info Markdown mirror
│   ├── raw-release-info.meta.json    # Metadata (etag, last-modified) for the above
│   ├── raw-dotnet-cu.json            # Aggregated .NET CU index mirror
│   ├── cache-release-info.json       # Parsed release-info cache
│   ├── cache-dotnet-cu.json          # Parsed .NET CU cache
│
├── tests/                            # Python self-verification suite (offline + live; see tests/README.md)
│   ├── README.md                     # Canonical T-numbering and quick-start
│   ├── catalog_probe.py              # T1 (live)
│   ├── catalog_fixture_test.py       # T2 (offline)
│   ├── powershell_harness.py         # T3 (offline; 7 PS assertions)
│   ├── eval_iso_probe.py             # T4 (live)
│   ├── release_info_parser_test.py   # T6 (offline; 13 assertions)
│   ├── dotnet_cu_parser_test.py      # T7 (offline; 16 assertions)
│   ├── common/                       # Shared Python utilities
│   │   ├── catalog_client.py
│   │   ├── html_parsers.py
│   │   ├── ps_invoke.py
│   │   └── snapshot.py
│   ├── fixtures/<patch-month>/       # Captured HTML for T2 offline regression
│   └── snapshots/                    # Probe outputs (last_probe.json + per-tool snapshots)
│
└── docs/
    ├── README.md                     # Documentation directory index
    └── history/                      # Long-form investigation reports (per cycle)
        ├── r07.0-followups.md
        ├── r08.0-step1-server2016-pca2023-finding.md
        ├── r08.0-step2-installwim-symmetry-check.md
        ├── r08.0-step3-output-verification-and-build.md
        ├── r08.0-step4-findings-and-dependency-investigation.md
        ├── r09.0-step1-phase5-summary.md
        ├── mojibake-investigation-note.md
        ├── dotnet-cu-report.md
        ├── dynamic-update-report.md
        ├── release-info-report.md
        └── release-info-readme.md
```

**Notable layout invariants**:

- `data/` is **flat** (no sub-directories). Per-month or per-OS data
  is encoded into the filename (`cache-dotnet-cu.json` and the per-OS
  `config-Server2025.json`, not nested `cache-du/Server2025.json`).
- `tests/common/` is the shared-utility location; it is NOT a tool
  itself.
- The `r08.0-step4-findings-and-dependency-investigation.md` cycle
  report (added 2026-05-27) contains the KB5087537 SSU-prerequisite
  incident detail that §B.19 codifies as the motivating scenario.

### B.20.2 Filename prefix rules

Three filename prefix patterns are used in this project; each
carries semantic meaning that operators and reviewers rely on:

| Prefix | Subdirectory | Meaning |
|:---|:---|:---|
| `config-` | `data/` | Operator-edited configuration (the `data/config-Server*.json` family). One per OS. |
| `raw-` | `data/` | Mirrored upstream content (Microsoft release-notes Markdown, .NET CU index JSON, etc.). Refresh-only via `-Action RefreshSnapshots`; no operator edit expected. |
| `cache-` | `data/` | Parsed cache derived from the corresponding `raw-` source, in machine-friendly JSON form. Re-generated whenever the `raw-` source is refreshed. |
| `r<NN>.<MM>-` | `docs/history/` | Per-revision investigation reports. Filename also carries the topic in kebab-case. |

The current `data/` layout uses individual files for each upstream
source (`raw-release-info.md`, `raw-dotnet-cu.json`) rather than
sub-directories. The `*.meta.json` companion file (e.g.
`raw-release-info.meta.json`) records the etag / Last-Modified header
of the upstream HTTP fetch so re-runs can skip unchanged content.

### B.20.3 Worked examples

| Filename | Convention | Comment |
|:---|:---|:---|
| `data/config-Server2025.json` | Operator config | One per OS |
| `data/raw-release-info.md` | Mirrored upstream | Refreshed by RefreshSnapshots |
| `docs/history/r08.0-step2-installwim-symmetry-check.md` | Per-revision investigation | Cycle (r08.0), step (step2), topic kebab-case |
| `tests/fixtures/2026-05/server2025-lcu.html` | Test fixture | Per-month, per-OS HTML captures |

### B.20.4 What this section does NOT cover

- Naming of internal PowerShell functions inside the .ps1 file. Those
  follow Pascal-case verb-noun per PowerShell convention and are
  enforced by PSScriptAnalyzer's `PSUseApprovedVerbs` rule.
- Naming of CI workflow files. Those follow the repository-wide
  convention documented in the
  [repository-level SPEC](https://github.com/usui-tk/ai-generated-artifacts/blob/main/SPEC.md) §3.1, which uses
  double-underscore (`__`) as a path-segment separator.

## B.21 Workspace preflight

**Status**: normative (r04.3+).

### B.21.1 Purpose

`Assert-WorkspacePreflight` runs at the top of the dispatcher
(before any action / phase logic) and verifies that the workspace
is structurally ready. The function is placed before action
dispatch deliberately so misconfigurations are caught with a clear
"workspace not ready" message rather than a cryptic mid-phase
failure.

### B.21.2 Checks performed

| Check | Behaviour on failure |
|:---|:---|
| `-WorkRoot` resolves to an existing directory or can be created | Throw |
| The resolved `WorkRoot` is on a volume with at least 100 GB free | Throw |
| All four `data/config-Server<N>.json` files are readable | Throw |
| The script's own directory has `tests/` and `data/` subdirectories | Throw (catches script-relocated-without-data) |

The 100 GB free-space requirement was determined empirically: an
end-to-end `-Action PrepareBuildVerify -Execute` for one OS family
peaks at ~80 GB of intermediate state. The 100 GB threshold
provides a 20 % margin and protects against the operator-pending
class of failure where DISM mount fails halfway through.

### B.21.3 Skip conditions

`Assert-WorkspacePreflight` is skipped for the following actions
where the checks are not relevant:

- `-Action ListPhases`
- `-Action Cleanup` (which is what the operator runs to clean up
  a corrupted workspace)
- `-EnvironmentInfoOnly` (P01-only smoke test)
- `-SkipEnvCheck` (operator escape hatch)

For `RefreshAllBaselines` / `DumpFieldClassification`
(which never run P01), the preflight
DOES run, because these actions touch `data/config-Server*.json`
and the config-presence check is exactly what protects against the
script-relocated-without-data class of misconfiguration.

## B.22 Phase 3 architecture decisions

**Status**: normative (r07.0+). Detailed historical context is
preserved in the per-revision CHANGELOG; this section records only
the **decisions that survived into r09.0** and the rationale a
maintainer needs at the use-site.

### B.22.1 Refresher architecture: release-info as canonical source

The b3 refresher (`Invoke-CatalogPatchSetRefresh` → `Resolve-Os`)
resolves the patch set directly from a live Microsoft Update Catalog
scrape; `Resolve-CatalogPatchSetForOs` then reconciles the resolved
LCU against the Learn release-info oracle and enforces per-`PatchModel`
consistency (B.19). Release-info is the **verifier** that confirms the
Catalog LCU matches the month's published KB — not a separate
"which KBs?" membership source.

**Decision**: the Catalog scrape resolves KB membership and the
URL / file metadata in one pass; release-info reconciliation is a
confirmation gate, not a separate membership source. (The pre-v3.0
release-info-as-canonical-source model and its `Resolve-PatchSetFromReleaseInfo`
producer were removed in the data-source migration.)

**Why**: r06.0 PoC showed the release-info Markdown is parseable,
versioned, and stable. Title-scrape against the Catalogue is fragile
(comma-form drift in 2026-04 dropped Server 2022 to zero results;
see §D.19).

### B.22.2 Catalog OS-scoping: Products column

The b3 producer scopes Catalog hits to an OS by the Catalog **Products**
column (`Get-ServerRow` keeps rows whose Products field contains the
per-OS token in `$script:CatOsDef`, e.g. `Windows Server 2016`,
`Microsoft Server operating system-21H2`), not by parsing the update
Title string.

**Why**: the Products column is structured metadata, immune to the Title
punctuation drift that broke the pre-b3 Title-token scrape (r04.2 dropped
Server 2022 to zero results when Microsoft removed a comma from one OS
title). The earlier config-driven Title-token mechanism
(`Common.CatalogTitleTokens` + `Get-CatalogTitleTokenList` /
`Test-CatalogTitleMatch`) was removed with the legacy resolution path.

### B.22.3 Data directory: flat with 3-prefix naming

All persistent inputs go under `data/` (not under sub-directories
by Type). Files are distinguished by the §B.20.2 three-prefix rule
(`config-`, `raw-`, `cache-`). Per-month raw caches live under
`data/raw-<topic>/<yyyy-MM>/`.

**Why**: A single `data/` directory mirrors operator mental model
("the data the script reads"). Type-named sub-directories would
have proliferated as new data classes were added; the flat layout
absorbs new data classes without surprise.

### B.22.4 Schema version: stay at 2.1

`config-Server*.json` Schema field stayed at "2.1" across r07.0 and
r08.0. r09.0's additions do not
constitute a breaking change.

**Why**: The new fields are optional and the loader treats absent
fields as `$null`. Forward-compatibility through optional-field
addition is the lighter migration path.

### B.22.5 SSU separation and .NET CU multiplicity

SSU and LCU are separate `Lines` entries even when shipped
combined; the loader treats them as independently-trackable units.
.NET CU umbrella KBs that bundle multiple `.msu` files keep all
sub-files as independent `Lines` entries (the b3 `Resolve-Net`
resolver retains every sub-file of the umbrella KB).

**Why**: Independent tracking of SSU and LCU enables P06 servicing-readiness
(§B.19) to surface SSU-prerequisite failures cleanly; without
separation, the prerequisite chain would not be representable in
layer 1.

**Discovery (b3, r11.34+)**: for the `separate-ssu` model, layer 1
(`Resolve-Ssu2016`) finds the standalone SSU by a same-month Catalog
title search for the OS's `<yyyy-MM> Servicing Stack Update`, keeping the
non-preview hit matching `(?i)servicing stack update` (2026-05 returns
one SSU for Server 2016, KB5088064). The `embedded-ssu` /
`embedded-ssu-du` models resolve no standalone SSU line (it is folded
into the combined LCU); `uup-checkpoint` derives its SSU line from the
co-served GA baseline. The search needs no layer 2 / `-DataDir` input,
so it works on the `RefreshAllBaselines` call path.

**.NET CU latest-applicable selection**: .NET Framework CUs are
cumulative and OS-lifecycle-applicable, so the b3 `Resolve-Net` resolver
takes the latest applicable .NET CU for the OS -- the newest Catalog row
matching the OS Products token, chosen by month prefix and runtime count
(`Get-RuntimeCount`). The latest-applicable build is the correct content
for a fully-patched ISO. (The pre-b3 release-info publication-gap
carry-forward, which bounded the search by the Dynamic Update 36-month
window, was removed with the legacy resolution path.)

### B.22.6 Dynamic Update: always-latest resolution

Setup and Safe OS Dynamic Updates are resolved live at build time by
`Resolve-SetupDu` / `Resolve-SafeOsDu` (a same-month Catalog search via
`Get-Newest` / `Search-Catalog`), always taking the latest applicable
package. There is no Dynamic Update cache or lookback window.

**Setup-DU discriminator correction [r11.45, live-Catalog-verified
2026-07-02].** Unlike the SafeOS DU, a Setup DU row has NO dedicated
Products category: its Products column is only `Windows 10 and later
Dynamic Update` (only the SafeOS DU carries `Windows Safe OS Dynamic
Update`) -- per the reference architecture memo's resolution recipes.
The r11.38 filter `products.Contains('Setup Dynamic Update')` assumed
SafeOS/Setup symmetry, could never match a live row, and silently
starved the 2025 SetupDU line (rule (1) of `ConvertTo-ConfigLines`
dropped the empty line) while every gate stayed green -- the T27
fixture had fabricated the assumed Products string. Selection is now by
TITLE via the pure `Select-SetupDuCandidate` (offline gate T30 against
verbatim-captured rows), and rule (1) now **hard-fails** when a Kind
inside the PatchModel's apply map resolves to 0 files (silent drops are
reserved for by-design absences: 2016 .NET/SafeOSDU, 2019/2022 SSU;
if a month legitimately lacks an in-model Kind, an explicit skip
decision + flag is required first).

**Why**: the build only needs the current applicable DU, and the live
resolvers return it directly. The pre-b3 36-month per-OS DU cache
(`cache-dynamicupdate-Server*.json`, populated by an A03 probe) had no
build-time consumer after the migration and was removed.

### B.22.7 Update lifecycle: Patch-Tuesday-triggered, Git-tracked

The §B.14 RefreshAllBaselines decision matrix is triggered by
calendar Patch Tuesday transitions. Resulting `data/config-*.json`
diffs are committed to git and surface as the maintainer's monthly
review unit.

**Why**: A monthly cadence aligns with Microsoft's servicing rhythm;
git tracking gives auditability and rollback at the file boundary.

### B.22.8 Subdivided DotNet types (superseded by the v3.0 migration)

**Status**: superseded. An earlier revision subdivided the flat
`DotNet` type of the pre-v3.0 `PatchBaseline.NeutralPatches[]`
structure into runtime / OS-offering / language-pack subtypes so the
OS-offering KB stayed visible in the baseline without entering the
apply lane. The v3.0 `Lines[]` migration retired both the structure
and the subdivision: the neutral baseline carries a single `DotNet`
Kind (the runtime CU with an on-disk payload), the OS-offering KB is
not recorded, and the language axis lives in
`LanguageSpecific.<lang>.LanguageSpecificPatches` (`DotNet.LangPack`).
Kept for the rationale trail only.

### B.22.9 release-info vs Catalog: release-info is the truth source

Codified in §B.22.1. Catalog is the resolver, release-info is the
truth source. Disagreements between the two are resolved in favour
of release-info (with a warning logged).

### B.22.10 r07.0 release granularity

Each numbered Step within r07.0 (Step 1 through Step 19) shipped as
a separate commit on `main` with its own CHANGELOG entry. r08.0 and
r09.0 continue this granularity. The Step number is the unit at which
a change is reviewable; the revision letter is the unit at which a
feature is shipped.

### B.22.11 Past-month inspection: read-only `-PatchMonth`

`-PatchMonth <yyyy-MM>` has two distinct roles. In the **build path**
it is read-only: it points Stage 1 catalog comparison at a past
baseline state for inspection and does not mutate `data/config-*.json`.
In **RefreshAllBaselines** (§B.14) the same flag instead pins which
month is generated -- the resolver fetches that month's patch set and
(r11.20+) `PatchTuesdayOfBaseline` is derived from that month's Patch
Tuesday via `Get-PatchTuesdayForMonth`, not the wall-clock latest one.

**Why**: Historical reproducibility for inspection; and, for a pinned
RefreshAllBaselines regeneration, correctness and byte-reproducibility
of the generated month -- e.g. regenerating the 2026-05 baseline on the
2026-06 Patch Tuesday stamps `2026-05-12`, not `2026-06-09`.

### B.22.12 CI structure: stage4 monthly refresh

CI Stage 4 (`...__stage4__monthly-refresh.yml`) runs
RefreshAllBaselines monthly on the 15th and opens a PR if
`data/config-Server*.json` changed.

### B.22.13 Windows ADK auto-install

When `oscdimg.exe` is not found, P01 Initialize automatically downloads
and silently installs only the Deployment Tools feature of the Windows
ADK (~50-80 MB) via `Install-WindowsAdkFallback` (no switch), matching
the 7-Zip auto-acquire strategy and the signtool acquisition
(§B.22.22). `Install-WindowsAdkFallback` throws an actionable error if
the install fails or `oscdimg.exe` is still absent. Actions that do not
need `oscdimg.exe` (`ListPhases`, `GenerateManifest`, `Cleanup`,
`Prepare`) and `-SyntheticTestMode` continue without it.

### B.22.14 Eval ISO URL: record both fwlink and direct CDN URL

`config-Server*.json#/LanguageSpecific/<lang>/Iso/{Fwlink,DirectUrl}`
records both the Microsoft fwlink metalink URL (which redirects to
the current CDN) and the resolved direct CDN URL (with embedded
snapshot id). The fwlink is the stable handle; the direct URL
shortens the download path.

**Why**: Microsoft rotates snapshot URLs. Recording both lets the
script try the direct URL first (faster) and fall back to the
fwlink (durable).

### B.22.15 Path-leaf extraction: prefer `[IO.Path]::GetFileName`

`Split-Path -LiteralPath -Leaf` is documented as ambiguous on
PowerShell 5.1 with mixed slash styles (§D.6). The script standardised
on `[System.IO.Path]::GetFileName($p)` after the r07.0 Step 13
incident at seven sites.

### B.22.16 P05 ExpandIso drive-root copy via robocopy

Switched from `Copy-Item -Recurse` to `robocopy` after r07.0 Step 14.
robocopy preserves NTFS metadata correctly when copying from a
read-only ISO mount and handles the long-path edge cases that
`Copy-Item` mis-handles on PowerShell 5.1.

The Dynamic Update overlay also uses `-Path` (not `-LiteralPath`)
on the wildcard expansion side, because `-LiteralPath` with
wildcards is a parameter-set conflict.

### B.22.17 Critical script-global typo prevention: PSA2013

The r07.0 Step 15 incident (`$Script:ExtractedMediaPath` written
in one site, `$Script:ExtractedMedia` read in another) was the
motivating example for psa.py rule `PSA2013` (assignment-vs-read
mismatch for `$Script:`-scoped variables).

### B.22.18 `Write-PhaseHeader` positional Mandatory

The r07.0 Step 17 incident (`Write-PhaseHeader 'P12'` hung on
Mandatory prompt) motivated psa.py rule `PSA2012` (positional
call to a `Mandatory` parameter).

### B.22.19 `(if ...)` mis-spelled subexpression

The r07.0 Step 18 incident (`(if $x { 1 } else { 0 })` parses as a
command invocation named `if`) motivated psa.py rule `PSA1004`.
The correct form is `$(if (...) { ... } else { ... })`.

### B.22.20 `Show-PhaseSummary` idempotent

The r07.0 Step 19 incident (Phase Timing Summary printed twice)
was fixed by making `Show-PhaseSummary` idempotent via a
`$Script:PhaseSummaryShown` flag.

### B.22.21 Cross-reference matrix

| Decision | Section | Captured in psa.py rule? | Surfaced from |
|:---|:---:|:---:|:---|
| Type field naming → `PatchType` | §B.10 | — | §D.30 |
| .NET CU multi-MSU | §B.15.2 | — | §D.21 |
| Catalogue Title comma-form drift | §B.22.2 | — | §D.19 |
| `$Script:` typo class | §B.22.17 | PSA2013 | §B.22.17 |
| `Write-PhaseHeader` positional | §B.22.18 | PSA2012 | §B.22.18 |
| `(if …)` subexpression | §B.22.19 | PSA1004 | §B.22.19 |
| Idempotent renderers | §B.22.20 | — | §B.22.20 |
| `List[object]` `@()` failure | §B.18.5 | — | §D.26 |
| DISM mount-cache poisoning | §B.3 (one-WR-per-OS) | — | §D.25 |
| Sampling-vs-comprehensive search | — (removed) | — | §D.28 |
| Microsoft tool dependency avoidance | — (removed) | — | §D.27 |
| Helper function unification | §B.10 | — | §D.30 |

### B.22.22 Windows SDK Signing Tools auto-install (signtool.exe)

`signtool.exe` (Windows SDK Signing Tools) is acquired with the same
install-if-missing idiom this script uses for 7-Zip and the
ADK Deployment Tools (§B.22.13): a resolver locates the tool, and a
fallback installer fetches it when absent.

- `Resolve-SignToolExe` returns the absolute path to signtool.exe,
  preferring the x64 build of the newest installed SDK. It checks PATH
  first (`Get-Command`), then walks `Windows Kits\10\bin` under both
  Program Files (x86) and Program Files, recursing for signtool.exe and
  preferring an `\x64\` hit. It returns `$null` (does not throw) when
  signtool.exe is not found, so the caller can choose to install or
  degrade. Unlike `oscdimg.exe` (§D.4), signtool.exe carries no fixed
  reference SHA-256 — it varies per SDK build — so there is no integrity
  hash check; acquisition trust rests on the Microsoft fwlink plus
  presence verification.
- `Install-WindowsSdkFallback` downloads `winsdksetup.exe` from the
  pinned Microsoft fwlink (`$Script:SdkInstallerUrl`, linkid=2338977,
  SDK 10.0.26100.6584) to `<WorkRoot>\cache\sdk\`, then runs it with
  `/features OptionId.SigningTools /quiet /norestart` so only the Signing
  Tools feature is installed, never the full SDK. It verifies by tool
  presence (a non-zero installer exit with signtool.exe present is
  treated as "already installed"), mirroring `Install-WindowsAdkFallback`.

Acquisition is automatic and requires no switch, matching the 7-Zip
strategy. The pinned constants live in one place in the
global-constants block alongside the ADK pins. The machinery is provided
for signature-verification consumers (the PCA2023 readiness classifier,
§B.17.2 / §B.18.1).

## B.23 JSON Canonical Serialization

**Status**: normative. **Scope**: every `data/*.json` and every
`tests/fixtures/*.json` file in this subproject.

### B.23.1 Motivation

This subproject's `data/` directory and `tests/fixtures/` directory
both contain JSON files. Historically the two directories used two
different formats:

- `data/*.json` was written by PowerShell 5.1 `ConvertTo-Json`, whose
  output has 4-space indentation, a `":  "` (colon + two spaces)
  key/value separator, and a peculiar variable-width indentation that
  visually aligns the values of an object to the same column.
- `tests/fixtures/*.json` was written by Python `json.dumps(indent=2)`,
  which has 2-space indentation and a `": "` (colon + one space)
  key/value separator.

The PowerShell 5.1 format is **not reproducible on a Linux host**
running PowerShell 7.x: PS 7's `ConvertTo-Json` emits 2-space
indentation with `": "` separator, matching Python rather than PS 5.1.
Operators editing a `data/*.json` file from a Linux runtime therefore
introduced a whole-file reformat with every commit, drowning the
semantic change in noise and making review impractical.

The fix is to declare a single canonical format that both Linux
PowerShell 7 and Linux Python 3.10+ can emit byte-for-byte. The
canonical format chosen is the natural intersection of the two
runtimes' defaults, with two compatibility tweaks on the PowerShell
side to close the small remaining gaps (CRLF normalisation and
scientific-notation case).

### B.23.2 The 10 format rules (normative)

Every JSON file under `data/` and `tests/fixtures/` MUST satisfy all
ten rules:

| # | Rule | Rationale |
|:-:|---|---|
| 1 | **Encoding**: UTF-8 without BOM | Matches root README §File Format Policy for non-`.ps1` files |
| 2 | **Line endings**: LF only (no CRLF) | Same as rule 1 |
| 3 | **Indentation**: 2 spaces, no tabs | PS 7 / Python `indent=2` natural default |
| 4 | **Key-value separator**: `": "` (colon + 1 space) | PS 7 / Python natural default |
| 5 | **Array item separator**: `",\n<indent>"` (comma + newline + indent) | PS 7 / Python natural default |
| 6 | **Non-ASCII characters**: literal (no `\uXXXX` escape) | Japanese / emoji readability; round-trippable through Python `ensure_ascii=False` and PS 7's default |
| 7 | **Key order**: insertion order preserved (no sort) | Operator-meaningful field ordering (e.g. `KbId` before `Title` in `Lines`) |
| 8 | **Trailing newline**: exactly one LF at end of file | POSIX convention; `cat`, `git diff`, and most editors expect it |
| 9 | **Null values**: emitted as `"key": null` (no field omission) | Schema explicitness; absence of a key means "field not declared", not "field is null" |
| 10 | **Depth limit**: caller-controlled, default 20 | Prevents accidental infinite recursion; 20 is well above the deepest known schema (currently 6) |

A file that violates any of rules 1–10 is **not** in canonical format,
even if it parses as valid JSON.

### B.23.3 PowerShell reference implementation

Three helpers live in `Update-WindowsServerIso.ps1`, immediately after
the 7-Zip helper block:

| Function | Purpose |
|:---|:---|
| `ConvertTo-CanonicalJson`   | Serialize an object to a canonical JSON string. |
| `Save-CanonicalJsonFile`    | Serialize and atomically write the result to a file. |
| `ConvertFrom-CanonicalJson` | Parse canonical JSON text back into PowerShell objects. |

**Version-independence requirement.** The serializer and parser are
hand-rolled and do **not** call the built-in `ConvertTo-Json` /
`ConvertFrom-Json` cmdlets, because those cmdlets are not
byte-stable across PowerShell versions:

- `ConvertTo-Json` indentation differs between Windows PowerShell 5.1
  (deep, verbose indent; two spaces after the colon) and PowerShell
  7.x (two-space indent; `": "` separator). The same object therefore
  serialised to different bytes on different hosts, breaking the
  cross-runtime (PS 5.1 / 7.x / Python) byte-match.
- `ConvertFrom-Json` auto-converts ISO-8601-looking strings to
  `[datetime]` on PowerShell 7.x (5.1 keeps them as strings), losing
  the original textual form (e.g. a `+09:00` offset) and corrupting
  values on round-trip.

`ConvertTo-CanonicalJson` walks the object graph directly and emits
each value per the 10 rules: 2-space indent, `": "` separator,
`",\n<indent>"` array separator, literal non-ASCII, insertion-order
keys, `\uXXXX` only for control characters below `0x20` (with the
short escapes `\b \t \n \f \r \" \\`), integers verbatim,
Python-compatible floats (integer-valued floats gain a trailing `.0`;
scientific notation uses lowercase `e`), and exactly one trailing LF
unless `-NoTrailingNewline` is set. As a safety net, any stray
`[datetime]` / `[datetimeoffset]` is emitted as
`ToUniversalTime().ToString('o')` (matching the pipeline's own date
formatting); the data pipeline itself always stores dates as strings.

`ConvertFrom-CanonicalJson` is a recursive-descent parser that returns
order-preserving `[pscustomobject]` for objects, `[object[]]` for
arrays, `[string]` for strings (dates stay strings — no `[datetime]`
coercion), `[long]`/`[double]` for numbers, `[bool]`, and `$null`. Its
output shape matches what `ConvertFrom-Json` returned previously
(dot-access and `.PSObject.Properties` both work), so it is a
drop-in replacement on every canonical data read path
(`config-*.json`, `cache-*.json`). Internal
JSONL logs and object-clone idioms still use the built-in cmdlets.

`Save-CanonicalJsonFile` wraps the serializer and writes raw bytes
through `[System.IO.File]::WriteAllBytes` with a `UTF8Encoding(false)`
(no-BOM) encoder. The write is staged as `<Path>.tmp` then renamed
over `<Path>` via `Move-Item -Force`, for atomic-ish replacement.

**Caller obligations**:

- Pass `[ordered]` hashtables or `[pscustomobject]` instances, **not**
  plain `[hashtable]`. The plain hashtable enumerates in unspecified
  order, defeating rule 7.
- Pick an explicit `-Depth` that bounds the deepest expected nesting
  in the input. The default of 20 is safe for every known schema in
  this subproject. PowerShell's own default of 2 is **never**
  acceptable for `data/*.json`.
- Prefer `Save-CanonicalJsonFile` over a `Set-Content` /
  `Out-File` pipeline; the latter does platform newline translation
  and may add a BOM.

### B.23.4 Python reference implementation

Two helpers live in `tests/common/canonical_json.py`:

| Function | Purpose |
|:---|:---|
| `canonical_json_dumps`     | Serialize an object to a canonical JSON string. |
| `save_canonical_json_file` | Serialize and write the result to a file. |

`canonical_json_dumps` is a thin wrapper over `json.dumps` with:

- `indent=2` (rule 3)
- `ensure_ascii=False` (rule 6)
- `separators=(',', ': ')` (rules 4, 5)
- `sort_keys=False` is the default; Python `dict` preserves
  insertion order since 3.7 (rule 7)

plus an explicit depth check (`_assert_depth`) before serialisation
because `json.dumps` itself does not enforce one, and an optional
trailing-newline append (rule 8).

`save_canonical_json_file` opens the file in binary mode, writes the
UTF-8 bytes, and uses `os.replace` for an atomic rename from the
`.tmp` staging path.

**Caller obligations**:

- Pass an `OrderedDict` (or equivalent) when the input is constructed
  from a source that does not naturally preserve order (e.g. a YAML
  load with the default loader).
- Pick an explicit `depth` that bounds the deepest expected nesting.

### B.23.5 Byte-level parity contract

The two implementations together provide a normative byte-level
parity contract:

> For any logical input that round-trips through both runtimes (a
> Python `dict`/`list`/scalar tree, marshalled through JSON into a
> PowerShell `PSCustomObject`/`Array`/scalar tree), the byte sequence
> produced by `canonical_json_dumps` and `ConvertTo-CanonicalJson`
> for the same logical input MUST be identical.

The parity is verified by the **T11** test
(`tests/canonical_json_test.py`), which compares the two
implementations across a matrix of primitives, collections, Unicode
strings, and real-world `data/*.json` shapes. T11 is in the offline
quality-gate group and runs on every commit alongside T2 / T3 / T6 /
T7 / T8 / T9 / T10.

Any future change to either implementation that breaks T11 is a
contract violation and MUST be reverted or its parity restored
before the change can land.

### B.23.6 Migration from legacy formats

The initial migration of the 25 pre-existing `*.json` files in this
subproject from their legacy formats (PowerShell 5.1 4-space format
under `data/`, Python 2-space format under `tests/fixtures/` and
`tests/snapshots/`) to canonical was completed in the same change
cycle that added §C.3.4. After that point the canonical format is
mandatory for every JSON file in the three scanned directories.

The post-migration invariants are:

- Every `*.json` file under `data/`, `tests/fixtures/`, and
  `tests/snapshots/` MUST be in canonical format. The gate is
  automated by `tests/canonical_json_format_check.py` (SPEC §C.3.4);
  any commit that introduces a non-canonical file fails the gate.
- Any new JSON file in the three scanned directories MUST be written
  through `ConvertTo-CanonicalJson` / `Save-CanonicalJsonFile`
  (PowerShell) or `canonical_json_dumps` / `save_canonical_json_file`
  (Python). Using raw `ConvertTo-Json` for a file under these paths
  is a contract violation.
- Any commit that modifies an existing canonical JSON file MAY
  modify only the semantically-meaningful regions; the canonical
  format makes such diffs minimal and easy to review.

Files outside the three scanned directories are not subject to this
rule. Notable exceptions intentionally left out of scope:

- `Workspace_UpdateWsi/**/*.json` (operator-local workspace; per-run
  artefact, not version-controlled).
- Debug trace output that is emitted with `-Compress` for JSON-Lines
  consumption (one event per line, no human-readable indentation).
- `.psa.config.json` (psa.py configuration; managed by the
  cross-script convention rather than this subproject's contract).

---

# Part C — Quality Gates and Validation

> **Scope of this Part**: the pre-commit / pre-merge / pre-release
> checklist that every change to this sub-project MUST pass. Each gate
> has a clear pass criterion and a single owner (the developer who
> proposes the change). CI mirrors the local gates so that a clean
> local run is sufficient evidence that CI will pass.

## C.1 Static analysis

**Status**: normative. **Policy ID**: SPEC-WSI-030.

Two static analysers MUST report zero findings before commit:

### C.1.1 psa.py (the project's primary analyser)

```bash
cd projects/powershell-update-windows-server-iso
python3 ../../python/powershell-static-analyzer/psa.py Update-WindowsServerIso.ps1
```

Expected output:

```
==== psa.py: PowerShell Static Analyzer ====
File   : Update-WindowsServerIso.ps1
Lines  : N
Issues : 0 errors, 0 warnings, 0 info

  (no issues found)
```

The local `.psa.config.json` opts the script into the strict-mode
options `PSAP0003`, `PSAP0004`, `PSAP0005` (with relaxed mode
intentionally NOT set; this project was authored from scratch under
the strict discipline and has no migration backlog).

`.psa.config.json` populates `psa2010_known_cmdlets` with the DISM,
Storage, and Hyper-V cmdlet families used by this script. No
`PSAxxxx` rule is disabled at project level; all findings are
addressed at the source via either a fix or a line-local
`# psa-disable-line` comment with an inline justification.

### C.1.2 PSScriptAnalyzer (the upstream analyser, secondary gate)

```powershell
Invoke-ScriptAnalyzer `
  -Path Update-WindowsServerIso.ps1 `
  -Settings PSScriptAnalyzerSettings.psd1 `
  -Recurse
```

Expected: zero findings under the project `PSScriptAnalyzerSettings.psd1`.
The settings file matches the strict baseline; rule suppressions
require justification per the §C.1 inline-suppression policy.

Both analysers run in CI Stage 1 (Linux pwsh 7.4.6) and Stage 2
(Windows PowerShell 5.1). The same source file MUST pass both hosts;
psa.py is host-agnostic, but PSScriptAnalyzer surfaces a small set
of host-specific findings that only appear on one of the two hosts.

## C.2 Source file format gates

**Status**: normative. **Policy ID**: SPEC-WSI-031.

The script's source file MUST satisfy the §A.1 format contract.
The gate is automated by psa.py rules `PSA7001` (BOM) and `PSA7002`
(CRLF) and by `.gitattributes` enforcement at `git add` time.

A manual byte-level spot check is performed before any commit that
touches the .ps1 file:

```bash
xxd Update-WindowsServerIso.ps1 | head -1
# Expected: 00000000: efbb bfff ... (UTF-8 BOM "EF BB BF" + valid content)

file Update-WindowsServerIso.ps1
# Expected: "with CRLF line terminators"

# Check no mixed line endings (rare but possible after programmatic edit)
grep -P '\x0d' Update-WindowsServerIso.ps1 | wc -l
# Expected: equals the total line count of the file
```

A file emitted by a Linux-hosted code generator without
CRLF translation will fail `PSA7002` and is rejected. Mixed
line endings are forensically documented in the sister repository's
SPEC §D.23 as a higher-severity class of defect (PowerShell AST
accepts it silently, visual diff tools miss it). When such a file
is detected, the fix is to re-emit the entire file via the documented
patterns in
[`quality-tools/powershell-static-analyzer/SPEC.md` §4.28a](https://github.com/usui-tk/ai-generated-artifacts/blob/main/quality-tools/powershell-static-analyzer/SPEC.md#428a-psa7002--lf-only-or-mixed-line-endings).

## C.3 Configuration files validation

**Status**: normative.

For every `data/config-Server*.json` file, the following gates run
on every commit that modifies them:

### C.3.1 JSON well-formedness

```bash
for f in data/config-Server*.json; do
  python3 -c "import json,sys; json.load(open('$f'))" || echo "FAIL: $f"
done
```

### C.3.2 Schema 2.1 conformance

The internal `Test-OsConfigSchema` helper validates that every
required top-level key (`Schema`, `OsKey`, `Common`, `PatchBaseline`,
`Pca2023`, `AutoRefreshPolicy`, `LanguageSpecific`) is present and
has the expected type. Invoked via:

```powershell
.\Update-WindowsServerIso.ps1 -Action DumpFieldClassification | Out-Null
# Loads all 4 configs; failure to load any of them surfaces here
```

### C.3.2a JSON Schema conformance (machine-readable contract)

**Status**: normative. **Tool**: `tests/config_schema_test.py` 
(standard-library only, run in CI stage1).

`schema/config.schema.json` is the machine-readable single source 
of truth that mirrors this section (B.4). Every 
`data/config-Server*.json` is validated against it. Unlike the positive 
key-presence check in C.3.2, the schema gate also rejects:

- **unknown / mistyped properties**, via `additionalProperties: false` 
  plus an `^_`-prefix allowance for machine-written provenance fields 
  (machine-written fields like `_VerifiedDate`, etc.);
- the **forbidden legacy `PatchBaseline.Patches` field** (the r10.3 
  defect), via `not.required: [Patches]`;
- **wrong value types** for declared fields.

```bash
python3 tests/config_schema_test.py   # 0 = all configs conform
```

When SPEC B.4 changes, `schema/config.schema.json` MUST be updated 
in the same commit; the two are a matched pair.

### C.3.3 Cross-field consistency

The config baseline's cross-field consistency is the per-`PatchModel`
check in B.19 (`Test-PatchModelConsistency`, run at P06): for the
declared `PatchModel`, every required `Kind` is present, no forbidden
`Kind` appears, and every `Lines[]` entry carries a non-empty `Digest`.

(The pre-v3.0 `RequiresKbIds` "dependency must be in the baseline" check
was removed with the `wsusscn2` dependency graph; the v3.0 `Lines[]`
shape carries no `RequiresKbIds` field - `schema/config.schema.json`
sets `additionalProperties: false`.)

### C.3.4 JSON canonical format compliance

**Status**: normative. **Scope**: every `*.json` file under `data/`,
`tests/fixtures/`, and `tests/snapshots/` (the same scope as SPEC
Part B.23).

The gate is automated by `tests/canonical_json_format_check.py`,
which walks the three directories and, for each JSON file,
re-serialises it through `canonical_json_dumps` and compares the
result byte-for-byte against the on-disk file. Any divergence fails
the gate.

```bash
python3 tests/canonical_json_format_check.py
# Expected exit code: 0
# Expected last line: "Summary: 25 passed, 0 failed, 25 total"
# (the file count grows as new JSON files are added; the pass/fail
#  invariant is "failed == 0")
```

The check runs on every commit that adds or modifies a JSON file in
the scope above. A new JSON file that is not byte-for-byte canonical
fails the gate immediately; the remediation is to re-write the file
through `Save-CanonicalJsonFile` (PowerShell) or
`save_canonical_json_file` (Python), both of which produce identical
output per the SPEC Part B.23 parity contract.

The gate also rejects unparseable JSON, so it doubles as a JSON
well-formedness check for the same set of files (a superset of the
narrower §C.3.1 check).

## C.4 Functional smoke tests

**Status**: normative.

Runs on Linux pwsh 7.4.6 (CI Stage 1) and Windows PowerShell 5.1
(CI Stage 2). The smoke set:

| # | Command | Expected outcome |
|:---:|:---|:---|
| 1 | `.\Update-WindowsServerIso.ps1 -Action ListPhases` | exit 0; 13 phases + 11 actions printed |
| 2 | `.\Update-WindowsServerIso.ps1 -EnvironmentInfoOnly` | exit 0; environment dump |
| 3 | `.\Update-WindowsServerIso.ps1 -Action PrepareBuildVerify -SyntheticTestMode -DryRun -OsKey Server2019` | exit 0; P01–P03 complete, P04 reaches `New-SyntheticTestIso` |
| 4 | `.\Update-WindowsServerIso.ps1 -Action DumpFieldClassification` | exit 0; JSON written to stdout |
| 5 | `.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -DryRun -OnlyOs Server2025` | exit 2 (Manual fields remain by design); supersedence dedup exercised |
| 6 | `.\Update-WindowsServerIso.ps1 -Mode Force -OnlyLanguage ja-jp -SyntheticTestMode -DryRun` | exit 0; Force overrides Skip; OnlyLanguage filter applied |
| 7 | `.\Update-WindowsServerIso.ps1 -Mode Initial -SyntheticTestMode -DryRun -OsKey Server2025` | exit 0; same decisions as Monthly for the baseline state |

The Windows Server 2025 / PowerShell 5.1.26100 manual smoke runs
documented in r07.0 followups all reach exit 0 (see TESTING.md §0).
Smoke 5 returning exit 2 is by design: in dry-run mode the
RefreshAllBaselines reports that Manual-cadence fields could not be
auto-resolved, which is the expected outcome.

## C.5 Synthetic full pipeline

**Status**: normative.

`-SyntheticTestMode` (§B.9) runs the full pipeline against a fabricated
synthetic ISO. CI Stage 3 runs this end to end on a Windows runner with
the Windows ADK pre-installed:

```powershell
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify -Execute `
    -OsKey Server2019 -OsLang ja-jp `
    -SyntheticTestMode `
    -WorkRoot 'D:\synth-ws'
```

Expected outcome: exit 0, output ISO at
`D:\synth-ws\output\WS2019_ja-jp_Updated_2026-MM.iso`, P13 reports
`Health=Healthy` (or `Warning` because the synthetic patch set has
no real authenticode signatures).

**Important**: Stage 3 MUST NOT upload any artefact containing
Microsoft binary content. The output ISO is created and verified
on the runner, but only logs are uploaded. This is enforced by the
workflow's explicit `actions/upload-artifact` `path:` enumeration
per the repository-level
[Artifact Content Minimization](https://github.com/usui-tk/ai-generated-artifacts/blob/main/SPEC.md#12-spec-ci-081-artifact-content-minimization)
policy.

## C.6 Monthly baseline refresh

**Status**: normative.

CI Stage 4 (`...__stage4__monthly-refresh.yml`) runs on the 15th of
each month and after manual `workflow_dispatch`. It:

1. Checks out `main`.
2. Runs `.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines`.
3. If any `data/config-Server*.json` changed, opens an auto-PR.
4. The PR is restricted via `add-paths` to `data/config-*.json`.

Stage 4 supports `workflow_dispatch` with four inputs (`mode`,
`onlyOs`, `onlyLanguage`, `dryRun`) so a maintainer can trigger an
ad-hoc refresh or limit scope.

## C.7 CI runner diagnostic pre-flight

**Status**: normative.

Every Windows CI stage (Stage 2, Stage 3, Stage 4) runs a
diagnostic pre-flight inside the workflow file that captures:

- PowerShell version (`$PSVersionTable | ConvertTo-Json -Compress`)
- Available drives (`Get-PSDrive -PSProvider FileSystem`)
- `psa.py` analyser version
- Effective `OutputEncoding` / `[Console]::OutputEncoding`

The pre-flight output goes to `pillar1.log` (or `pillar2.log`,
`pillar3.log` for the per-tool subdivision) and is uploaded as a
workflow artefact. This pre-flight is what lets a maintainer
distinguish "the script bug surfaces only on a particular runner
image" from "the script bug is real" when triaging a CI failure.

## C.8 Documentation cross-checks

**Status**: normative.

Before commit, the following cross-document consistency rules MUST
hold:

| Rule | Owner |
|:---|:---|
| Any new section in SPEC.md MUST appear in §Table of Contents | Author |
| Any new `D.NN` Lessons-Learned entry MUST be cross-referenced from at least one §B.* section | Author |
| Any new Policy ID `SPEC-WSI-NNN` MUST appear in §Policy Index | Author |
| CHANGELOG.md entry MUST exist for any change visible to operators | Author |
| README.md / README.ja.md MUST be kept in lock-step on operator-visible changes | Author |

Mechanical verification of the SPEC TOC ↔ section headings is a
candidate Future enhancement. Today, the gate is a manual review.

## C.9 Self-verification tool suite

**Status**: normative. **Policy ID**: SPEC-WSI-033.

The `tests/` subdirectory ships a Python-based self-verification
suite of **seventeen numbered tools (sparse T-numbering, T1 through
T31; numbers of retired tools are never reused)** plus three
unnumbered gates (the canonical JSON format gate, the config schema
gate and the seed contract gate). They probe the script's
external dependencies and unit-test its PowerShell functions. They
use only the Python standard library — no `pip install` required.
The canonical T-numbering is maintained in
[`tests/README.md`](./tests/README.md) "Tool inventory"; this section
mirrors that authoritative table.

### C.9.1 Tool inventory (T1 – T31, sparse + format / schema / seed gates)

| Tool | Type | Assertions | Network | Run when |
|:---|:---|:---|:---:|:---|
| **T1** `catalog_probe.py` | Live Microsoft Update Catalog probe (search + per-OS title formats + supersedence panel) | ~7 live checks | Yes | Before/after Catalogue-related code change; monthly CI |
| **T2** `catalog_fixture_test.py` | Offline HTML fixture regression against `fixtures/<patch-month>/` | 13 | No  | Every commit that touches parsers or TitleTokens |
| **T3** `powershell_harness.py` | PS function unit tests via `-Action TestHarness` | **7** | No  | Every commit that touches a PS scrape helper |
| **T4** `eval_iso_probe.py` | Evaluation ISO endpoint check (HTTP Range-GET; 4 OS × 2 lang) | live (4 OS) | Yes | Before release; on Microsoft Evaluation Center snapshot rotation |
| **T6** `release_info_parser_test.py` | Offline regression for `ConvertFrom-ReleaseInfoMarkdown` against the PoC fixture | 13 | No | Every commit that touches the release-info parser |
| **T7** `dotnet_cu_parser_test.py` | Offline regression for `ConvertFrom-DotNetCuIndexMarkdown` / `ConvertFrom-DotNetCuMarkdown` against `snapshots/dotnet_cu/` | 16 | No | Every commit touching the .NET CU parsers or the fetch/cache pipeline |
| **T11** `canonical_json_test.py` | Offline byte-level parity test between `ConvertTo-CanonicalJson` / `Save-CanonicalJsonFile` (PowerShell) and `canonical_json_dumps` / `save_canonical_json_file` (Python) per SPEC Part B.23 | 26 | No | Every commit touching the canonical JSON helpers (PS or Python) |
| **T20** `removed_live_wua_guard_test.py` | Offline static guard: the removed live-WUA functions / parameters stay absent and the P06 gate stays wired | 20 | No | Every commit touching P06 or the WUA-adjacent surface |
| **T23** `config_required_ssu_downloadurl_test.py` | Offline data-contract guard on the committed configs: SSU `DownloadUrl` non-empty, `PatchModel` ⇔ SSU-line consistency, negative fixture rejected | 20 | No | Every commit touching `data/config-Server*.json` |
| **T24** `dism_cleanup_args_test.py` | `Get-DismCleanupArgumentList` argument-vector unit test (ResetBase / ScratchDir variants) | 6 | No | Every commit touching the P07 cleanup path |
| **T25** `dism_export_args_test.py` | `Get-DismExportArgumentList` argument-vector unit test | 6 | No | Every commit touching the P07 export path |
| **T26** `defender_exclusion_plan_test.py` | The three pure helpers behind `-UseDefenderExclusions` (managed set / plan / fail-closed decision) | 13 | No | Every commit touching the Defender-exclusion feature |
| **T27** `catalog_patchset_builder_test.py` | Offline b3 dataset builder: `ConvertTo-ConfigLines` from the committed raw capture to `PatchBaseline.Lines[]`, incl. the SetupDU line and the in-model starvation hard-fail | 16 | No | Every commit touching `ConvertTo-ConfigLines` or the raw fixture |
| **T28** `setup_du_forbid_test.py` | `Resolve-SetupDu` Forbid-branch guard for the non-uup-checkpoint OSes | 12 | No | Every commit touching the SetupDU resolver |
| **T29** `patch_integrity_digest_test.py` | Digest-format boundary: `ConvertTo-HexDigestString` base64↔hex vs an independent Python implementation + static wiring guards | 11 | No | Every commit touching the integrity layer |
| **T30** `setup_du_discriminator_test.py` | `Select-SetupDuCandidate` against verbatim live-Catalog rows (title discriminator; Products-filter resurrection guard) | 8 | No | Every commit touching the SetupDU discriminator |
| **T31** `lcu_target_verify_test.py` | `TargetBuildAfterUpdate` derived-field contract: comparator behavior, committed-data consistency, single-writer wiring, P11 hard-Fail row | 24 | No | Every commit touching the TBAU derivation or P11 |
| **seed contract gate** `seed_contract_test.py` | `data/seed/seed-Server*.json` vs `schema/config-seed.schema.json` + structural seed rules (the SEED contract for the offline dataset rebuild). (No T number; gate convention.) | 17 | No | Every commit touching seeds or the seed schema |
| **canonical JSON format gate** `canonical_json_format_check.py` | Offline format-compliance check: re-serialises every `*.json` under `data/`, `tests/fixtures/`, `tests/snapshots/` and fails on byte divergence. Implements SPEC §C.3.4. (No T number; format gate.) | 29 files | No | Every commit that adds or modifies a JSON file in the three scanned directories |
| **config schema gate** `config_schema_test.py` | Offline schema-conformance check: a stdlib-only draft-07-subset validator that checks every `data/config-Server*.json` against `schema/config.schema.json`, with a targeted regression guard against the legacy `Patches` property (r10.4). (No T number; schema gate, mirrors the format-gate convention.) | 14 | No | Every commit touching `data/config-Server*.json` or `schema/config.schema.json` |

**Determinism categories**:

- **Offline-deterministic** (the local gate battery for every change; CI Stage 1 runs the config schema gate): T2, T3, T6, T7, T11, T20, T23, T24, T25, T26, T27, T28, T29, T30, T31, plus the canonical JSON format gate, the config schema gate and the seed contract gate.
- **Live-network** (monthly CI + ad-hoc): T1, T4.

### C.9.2 Adjunct: retired r06 Phase 2 PoCs

The original Phase 2 PoC scripts (`poc_release_info_*.py`,
`poc_dotnet_cu_*.py`, `poc_dynamic_update_*.py`) shipped with r06.0
Phase 2 and were retired in r07.0 Step 5 once their findings were
integrated into the production parsers. Their reports remain under
`docs/history/` for archaeological reference (see Appendix F).

### C.9.3 Refreshing fixtures

The `tests/fixtures/<patch-month>/` HTML files are captured per
patch month. To refresh for a new month:

```bash
# 1. Confirm Catalog is queryable for the new month
python3 catalog_probe.py --check all --patch-month 2026-06

# 2. Re-collect the HTML files via the bundled helper
#    (see tests/README.md "Refreshing fixtures")
#    The collector hits Search.aspx for each OS / Type combination
#    and writes one .html file per query plus an expected.json with
#    the parsed results that T2 then asserts against.

# 3. Commit both the HTML and expected.json together
git add tests/fixtures/2026-06/
git commit -m "tests: refresh fixtures for 2026-06"
```

### C.9.4 Dependency policy

The Python self-verification suite uses **only the Python standard
library**. Adding a `requirements.txt` or third-party Python
dependencies requires SPEC-level justification because:

- Standard-library-only keeps the suite runnable in any CI
  environment without dependency caching.
- Third-party dependencies introduce supply-chain attack surface
  (see repository-level SPEC §8.1.D).
- Operator-side runs (`python3 tests/catalog_probe.py`) MUST work
  without `pip install`.

Shared utilities used by multiple tools live under
[`tests/common/`](./tests/common/) (`catalog_client.py`,
`html_parsers.py`, `ps_invoke.py`, `snapshot.py`); these are
implementation details of the suite, not tools themselves.

### C.9.5 How these tools relate to CI

| Tool | CI Stage | Cadence |
|:---|:---|:---|
| T1 | Stage 4 monthly | monthly (live network) |
| T2 | Stage 1 (Linux) | every commit |
| T3 | Stage 1 (Linux) | every commit |
| T4 | Stage 4 monthly | monthly |
| T5 | Stage 4 monthly + manual before P06 | monthly + ad-hoc |
| T6 | Stage 1 (Linux) | every commit |
| T7 | Stage 1 (Linux) | every commit |
| T8 | Stage 1 (Linux) | every commit |
| T9 | Stage 1 (Linux) | every commit |
| T10 | Stage 1 (Linux) | every commit |

The Stage 4 schedule runs T1, T4, T5 monthly so silent Microsoft-side
changes surface within 30 days even if no PR touches the relevant
code.

### C.9.6 Planned T11 (r09.0+)

T11 is **not yet implemented** and is listed for forward traceability
only. The current canonical T-set ends at T10.

---

# Part D — Known Pitfalls and Lessons Learned

> **Scope of this Part**: every entry records a defect that was either
> shipped at one point or that almost shipped, plus the root cause and
> the inheritable mitigation. Entries are tagged with **stable IDs
> `D.NN`** so other documents, code comments, and finding reports can
> cite them without breaking on cosmetic edits. Once assigned, a
> `D.NN` identifier is never reused for a different purpose.
>
> Entries are organised in two layers:
>
> - **D.1 – D.23**: inherited from the r02 – r08.0 cycles. Each entry
>   has a stable ID and a compact recall of root cause + mitigation;
>   the full forensic record is preserved in CHANGELOG.md and the
>   relevant `docs/history/` finding reports.
> - **D.24 – D.30**: added in this r09.0 SPEC rewrite. These entries
>   distil meta-lessons about engineering and design judgement that the
>   r07.0 / r08.0 / r09.0 cycles surfaced. They are by nature less
>   tactical and more about how to think about the next ambiguous
>   situation.

## D.1 – D.23 (inherited from r02 – r08.0 cycles)

### D.1 DISM mount cleanup (OSDBuilder pattern)

**Symptom**: a previous run's WIM mount blocks the new run's
`Mount-WindowsImage` with `0xC1420127 — image is already mounted`.

**Root cause**: a crashed or `Ctrl-C`ed previous run leaves a mount
in the DISM database that the kernel still tracks even after the
PowerShell process exits.

**Fix / mitigation**: every mount site uses a `finally` block that
calls `Dismount-InstallwimOS` from the OSDBuilder-derived helper
with a 10-s retry loop, then a 30-s retry loop after `dism
/Cleanup-MountPoints`. The helper's logic is replicated verbatim in
`Dismount-WimSafely`.

### D.2 SSU before LCU

**Symptom**: a 2026-05 LCU rejected with `0x800f0823 —
CBS_E_NEW_SERVICING_STACK_REQUIRED` from inside P07.

**Root cause**: install.wim's resident servicing-stack version
predates what the LCU expects. Microsoft requires the SSU to be
applied first.

**Fix / mitigation**: the `Build-PatchPlan` sequence places SSU at
`I1.SSU` and `B1.SSU` so it always precedes LCU. The §B.13 mount-time
check and the §B.19 graph-based check both catch missing SSU
prerequisites at distinct latencies (mount-time: 30 s; graph: < 5 s).

### D.3 `winre.wim` is inside install.wim

**Symptom**: a search for `winre.wim` next to `boot.wim` came up
empty.

**Root cause**: `WinRE.wim` is **embedded inside install.wim**, at
the path `Windows\System32\Recovery\WinRE.wim`. It is extracted at
P08 inner-mount time and serviced separately.

**Fix / mitigation**: P08 mounts install.wim first, copies out
WinRE.wim, services it independently, then writes it back. The
`Common.WinReWimPath` config field records the inner path.

### D.4 oscdimg etfsboot / efisys 3-tier fallback

**Symptom**: `oscdimg` failed on Windows Server 2025 hosts with
"required boot file not found".

**Root cause**: the locations of `etfsboot.com` and `efisys.bin`
have moved across ADK versions. The script needs to find them in
three different layouts.

**Fix / mitigation**: `Get-OscdimgBootFiles` tries the following
locations in order: (1) ADK installation root, (2) `boot/` inside
extracted media, (3) deeply embedded `boot.wim`-derived paths.
Pattern borrowed from `Win_ISO_Patching_Scripts_zhCN`.

### D.5 SHA-1 is intentional in `Test-PatchIntegrity`

**Symptom**: a code review questioned `Test-PatchIntegrity` for
using `Get-FileHash -Algorithm SHA1`.

**Root cause**: not a bug. Microsoft's MetaLink XML for some
legacy patches still publishes only SHA-1. The integrity check
falls back to SHA-1 when SHA-256 is unavailable in the source-of-
truth.

**Fix / mitigation**: an inline comment at the call site documents
this. Layer 2 (§B.4.3) uses SHA-256 for the patch entries since
all Catalogue-resolved entries publish it.

### D.6 `Split-Path -LiteralPath -Parent` ambiguity on PS 5.1 ja-JP

**Symptom**: paths containing both forward and back slashes returned
unexpected results from `Split-Path` on Japanese-locale PS 5.1
hosts.

**Root cause**: PowerShell 5.1's `Split-Path` on Japanese culture
mishandles mixed slash styles in a way that PS 7 does not.

**Fix / mitigation**: standardised on
`[System.IO.Path]::GetFileName($p)` and
`[System.IO.Path]::GetDirectoryName($p)`. See §B.22.15.

### D.7 Top-level `param()` variables in nested functions

**Symptom**: a nested helper unexpectedly saw the top-level
`-WorkRoot` value even when called with no arguments.

**Root cause**: PowerShell's dynamic scoping. `param()` variables
defined at the script level are visible to all nested functions
unless explicitly shadowed.

**Fix / mitigation**: nested helpers MUST explicitly receive
`-WorkRoot` (or other top-level params) as a parameter; reliance
on dynamic scoping is forbidden.

### D.8 `0x800f081e` is benign per OSDBuilder

**Symptom**: DISM warnings of the form
`Warning ... 0x800f081e` after applying a cross-SKU LCU.

**Root cause**: the patch was not applicable to the specific edition
in install.wim. This is expected for cross-SKU patch sets (e.g.
Server 2016 LCU contains files for multiple editions).

**Fix / mitigation**: `Test-DismWarningIsBenign` filters these out
of the surfaced warnings list, citing OSDBuilder precedent. P11
reports the count separately.

### D.9 `0x800f0a13` is a transient

**Symptom**: DISM intermittently returned `0x800f0a13` and a retry
succeeded.

**Root cause**: a known race condition in CBS package installation
that the OSDBuilder community classified as transient.

**Fix / mitigation**: `Invoke-DismRetry` performs one retry
(10-s gap) when this specific code appears.

### D.10 `$args` is an automatic variable

**Symptom**: `Resolve-PatchSetFromCatalog` mis-routed when a caller
passed an extra positional argument.

**Root cause**: a typo had introduced a function parameter named
`$args`, which shadows the PowerShell automatic variable.

**Fix / mitigation**: `$args` (and other automatic variables) MUST
NOT be used as parameter names. The list of forbidden names is in
the script-comment header. PSScriptAnalyzer rule
`PSReservedCmdletChar` and psa.py's reserved-name check both fire
on this.

### D.11 Microsoft Eval ISO snapshot URLs rotate

**Symptom**: a direct CDN URL recorded in `config-Server*.json`
returned 404 a few weeks after recording.

**Root cause**: Microsoft Evaluation Center rotates snapshot URLs.
The fwlink redirector points at the current snapshot.

**Fix / mitigation**: per §B.22.14, every ISO entry records both
the fwlink and the direct CDN URL. P04 tries the direct URL first
(faster); on 404 it falls back to the fwlink.

### D.12 Sandbox-by-default

**Symptom**: an operator unfamiliar with the script triggered a
full DISM mount + LCU apply by running with default args.

**Root cause**: previously `Build` was the default and `-DryRun`
the opt-in.

**Fix / mitigation**: `-Execute` is required for any side effect.
Default behaviour is dry-run. The change is documented in r04.x
CHANGELOG and surfaced in README's Quick Start.

### D.13 `Start-Transcript` has no `-LiteralPath`

**Symptom**: a workspace path containing brackets caused the
transcript file to land in an unexpected location.

**Root cause**: `Start-Transcript` only accepts `-Path` and
wildcard-interprets the argument.

**Fix / mitigation**: the script computes the transcript path
ahead of time and validates it contains no wildcard characters
before passing to `Start-Transcript`.

### D.14 PowerShell 5.1 has no ternary operator

**Symptom**: a port from PS 7 to PS 5.1 broke on `(condition ? a : b)`.

**Root cause**: PowerShell's ternary `? :` operator was added in
7.0. The script targets 5.1 as primary host.

**Fix / mitigation**: use `if ($cond) { $a } else { $b }` (with
parenthesisation when the result is assigned). psa.py rule
`PSA1005` catches the ternary form.

### D.15 Patch Tuesday boundary buffer

**Symptom**: `Get-LatestPatchTuesday` occasionally returned the
previous month's Patch Tuesday on the morning after.

**Root cause**: time-zone confusion. Microsoft publishes on Pacific
time; a JST-based date arithmetic saw the new Patch Tuesday a day
before the patches appeared on Catalogue.

**Fix / mitigation**: a 24-hour buffer is applied — the calculated
Patch Tuesday is treated as "live" only after PT 06:00.

### D.16 Microsoft Update Catalogue has no API

**Symptom**: an attempt to use a Catalog REST API.

**Root cause**: Microsoft Update Catalog does not expose a stable
API. The only access is HTML scraping of `Search.aspx`.

**Fix / mitigation**: `Resolve-PatchSetFromCatalog` scrapes HTML
with explicit fragility budget: T1 (`catalog_probe.py`) runs
monthly to detect Microsoft-side HTML drift.

### D.17 Auto-variable `$matches` cannot be reassigned

**Symptom**: a helper function reset `$matches = @{}` to clear
prior state; this raised a runtime error.

**Root cause**: `$matches` is one of PowerShell's automatic
variables and is read-only outside the engine.

**Fix / mitigation**: use `[System.Collections.Hashtable]::new()`
or rely on `$matches`'s built-in clearing behaviour after each
regex operation.

### D.18 `wsusscn2.cab` scans the local host's image, not the WIM

**Symptom**: an early prototype of the wsusscn2-driven scan
returned the host's installed packages, not the offline WIM's.

**Root cause**: `IUpdateSession.CreateUpdateSearcher` uses the
**currently-running OS** as its target by default, even when
`ServerSelection = ssOthers` points at an alternate metadata
source.

**Fix / mitigation**: the COM-API offline scan was removed (r11.19).
Servicing readiness is now validated on the mounted WIM by
`Test-PatchServicingReadinessOnMount` (§B.13), which reads the actual
installed package list and is therefore inherently WIM-relative,
avoiding the host-relative COM API entirely.

### D.19 Catalogue Title comma-form drift (Server 2022)

**Symptom**: Server 2022 baseline refresh returned **zero** entries
in 2026-04. Every narrow filter dropped every hit.

**Root cause**: Microsoft removed a comma from the Server 2022
update title:
"...operating system, version 21H2" → "...operating system
version 21H2". The TitleToken was a `[regex]::Escape` literal
match.

**Fix / mitigation**: OS-scoping moved off the update Title entirely to
the Catalog Products column (§B.22.2), which is structured metadata and
immune to Title punctuation drift. The interim config-driven multi-form
`TitleTokens` array (the original mitigation) was removed with the legacy
resolution path.

### D.20 `Get-PatchType` filename heuristic is not authoritative

**Symptom**: Catalogue-derived `NeutralPatches` entries had wrong
`Type` fields. SSU / Safe-OS DU / umbrella-.NET-CU sub-files were
mis-classified as `LCU`.

**Root cause**: `Get-PatchType` derived Type by file-name pattern
matching. The Catalogue search context already knew the
authoritative Type via `$q.Type`, but `Convert-CatalogPatchToBaselineEntry`
did not use it.

**Fix / mitigation**: r04.3 added `-KnownType` to
`Convert-CatalogPatchToBaselineEntry`; the heuristic is bypassed
when the caller has context.

### D.21 Umbrella KBs attach multiple files to one UpdateId

**Symptom**: Server 2019 `.NET CU` baseline entries silently lost
`ndp48` or `ndp481` sub-files.

**Root cause**: `Select-CanonicalPatchFile` returns one result.
Without a `-DotNetVersion` hint, it cannot break the tie between
two ndp-runtime variants of the same umbrella KB.

**Fix / mitigation**: r04.3 added `Select-AllCanonicalPatchFiles`
and routed `Type='DotNet'` queries through it. Each surviving
MSU gets its own `Lines` entry sharing
`KbId / Title / UpdateId / Supersedes` from the umbrella KB. See
§B.15.2.

### D.22 Secure Boot baseline considerations (r05.0+)

**Symptom**: a "Will this ISO boot on a hardware machine with
PCA2011 revoked from DBX?" question could not be answered from the
script's pre-r07.0 output.

**Root cause**: input-side readiness (boot.wim has EFI_EX assets)
and output-side readiness (the assets were copied into the ISO
correctly) were not distinguished.

**Fix / mitigation**: §B.17 (PCA2023 boot manager support) and
§B.18 (Output ISO verification) cover the two perspectives
explicitly; P12 runs both.

### D.23 UEFI Secure Boot defaults templates (r05.0+, informational)

**Symptom**: an operator's machine with non-default DB / DBX
contents was misclassified as "Healthy" by an early P12.

**Root cause**: the initial readiness check did not consult the
Microsoft-published Secure Boot defaults templates (DBs / KEKs /
DBXs) bundled in `microsoft/secureboot_objects`.

**Fix / mitigation**: r05.0 added a check that cross-references
the running machine's DBX against the upstream-published "factory
default" templates. A divergence is reported as informational
context rather than blocking, since operators legitimately
customise these.

---

## D.24 – D.30 (new in this r09.0 SPEC rewrite)

### D.24 Cognitive bias patterns

**Symptom (recurring across r07.0 / r08.0 / r09.0 cycles)**: an
investigator arrives at the wrong conclusion despite having the
right data in hand. Three specific patterns have surfaced often
enough to be worth naming.

**Pattern 1 — Hypothesis lock-in**. The investigator forms a
hypothesis early and continues to interpret subsequent evidence as
confirming it, even when the evidence is at best neutral and at
worst falsifying. Example: r08.0 Step 2 saw a brief lock-in on
"`bootmgr_EX.efi` is dual-signed PCA2011+PCA2023" after misreading
the `Get-AuthenticodeSignature` Issuer field. The lock-in held even
after `signtool /verify /pa /all /ds 0..3` returned exactly one
embedded signature — the result was initially explained away. The
lock-in broke only on a deliberate re-read of the upstream Microsoft
comment at `Make2023BootableMedia.ps1` L876-L884.

**Pattern 2 — Sampling treated as comprehensive**. The
investigator samples 2 to 3 instances of a phenomenon and concludes
about the whole. Example: r09.0 Step 1 Phase 5 v3 looked at the
first 2-3 `<Update>` elements in the Master XML, observed no
`<SupersededBy>` element, and tentatively concluded
"`<SupersededBy>` is not present in the Master XML". An exhaustive
case-insensitive search later (Phase 5 v4) found **14,059
occurrences** — present in ~10.3 % of all `<Update>` elements. The
sampling-based conclusion was off by 14,059 hits. See §D.28 for
the engineering response.

**Pattern 3 — Solution attraction**. The investigator commits to
fixing a problem at the code level when the problem is actually at
the configuration level (or vice versa). Example: r08.0 Step 4d
saw a tentative reach for a code patch to handle the
`0x800f0823 — CBS_E_NEW_SERVICING_STACK_REQUIRED` failure. The
failure was a real Microsoft-side requirement (LCU's prerequisite
SSU was absent from the baseline); the correct fix was a
configuration change. The code-fix path would have shipped the bug
as a feature. See §D.29.

**Root cause (shared across patterns)**: the investigator's mental
model is constructed from incomplete evidence, and adding evidence
that contradicts the model is cognitively more expensive than
extending the model to absorb the contradiction. The cost gradient
favours staying with the existing hypothesis.

**Mitigation**:

1. **Pre-commit a falsifiability test**. Before believing a
   hypothesis, write down what would have to be true to disprove
   it. r08.0 Step 2's dual-sign hypothesis was disproved by
   "exactly 1 embedded signature per `/ds <N>`" — but no falsifier
   was pre-committed, so when the evidence came in, it was read
   against rather than disqualifying.
2. **Re-read upstream sources when surprised**. Microsoft's own
   comments and READMEs are the ground truth more often than the
   investigator's intuition. The L876-L884 comment in
   `Make2023BootableMedia.ps1` is a perfect example of an
   authoritative one-paragraph answer that, once read, made the
   dual-sign hypothesis untenable.
3. **Promote exhaustive search over sampling whenever cheap**.
   `Select-String` on a 108 MB file is a few seconds; a sample of
   3 elements out of 136,102 is structurally unsound regardless of
   how busy the investigator is. See §D.28.
4. **Distinguish code-bug from config-bug explicitly**. Before
   reaching for `str_replace`, ask: "is the failure originating in
   logic this script controls, or in a fact the script reads?" If
   reading, the fix is a config / data change. See §D.29.

The four mitigations above are also recorded as the **Engineering
Hygiene Quartet** in the r09.0 Step 1 retrospective.

### D.25 DISM mount-cache poisoning

**Symptom (r07.0 Step 16/17)**: the WIM-index enumeration banner
of `install.wim Index 2` rendered each Japanese character doubled
("デデススククトトッッププ"), while `Index 4` of the same WIM rendered
correctly on the same console host in the same run. Switching the
`-WorkRoot` from `D:\UpdateWsi` to `D:\UpdateWsi_2016` (no other
changes) made the mojibake stop reproducing.

**Root cause**: not console-rendering. The original WorkRoot had
been used for many prior runs with mounted, dismounted, and
partially-cleaned-up WIMs in nested directories. A stale entry in
the DISM mount database (or in a per-WIM scratch cache under
`%TEMP%` / `%WINDIR%\Logs\DISM`) mapped the same WIM-mount path to
a corrupted state on subsequent enumerations. The byte-identical
source ISO and the same console host both rule out the originally
suspected layers.

**Mitigation**: **one fresh WorkRoot per OS family**. This is the
project-wide recommended pattern (`D:\UpdateWsi_2016`,
`D:\UpdateWsi_2019`, `D:\UpdateWsi_2022`, `D:\UpdateWsi_2025`) and
is documented at §B.3. The pattern also helps with disk-space
isolation per OS and with parallel multi-OS work.

**Forensic notes**: the full investigation log is in
`docs/history/mojibake-investigation-note.md`. The investigation
was deliberately deferred to focus on shipping milestones; the
workaround is empirically sufficient. The root-cause hypothesis is
"DISM mount-cache state corruption from prior aborted P10 runs" but
this has not been independently reproduced under controlled
conditions. The investigation may be resumed when a maintainer has
the bandwidth.

**Related**: §B.3 (workspace layout) and §B.4.2 records the
recommendation.

### D.26 `List[object]` of pscustomobject argument-type mismatch

**Symptom (r08.0 Step 2 → Step 3)**: a function that collected
pscustomobjects into `System.Collections.Generic.List[object]` and
returned the list via `@($list)` threw `System.ArgumentException:
Argument types do not match` at function return time. The error
persisted across multiple attempts and was not root-caused within
the Step 2 session; the function was reverted.

**Root cause** (identified in Step 3 minimal reproduction): the
`@(...)` array-subexpression operator fails on
`System.Collections.Generic.List[object]` when its elements are
`pscustomobject`. The same operator works fine on `List[string]`.
The behaviour is specific to PowerShell 7.4.x but is consistent
across hosts (Linux pwsh 7.4.6 reproduces).

**Minimal reproduction**:

```powershell
$list = New-Object System.Collections.Generic.List[object]
$list.Add([pscustomobject]@{Label='test1'}) | Out-Null
$list.Add([pscustomobject]@{Label='test2'}) | Out-Null

@($list)              # FAILS: Argument types do not match
[object[]]@($list)    # FAILS: Argument types do not match
$list.ToArray()       # OK
foreach ($x in $list) { $arr += $x }  # OK (slow path)
```

**Mitigation**: convert at function exit via `$list.ToArray()`.
This is the only "different" line vs the existing
`Get-IsoBootCertReadiness` pattern (which uses `List[string]` and
`@(...)`), so the function template is otherwise unchanged. The
distinction is recorded inline in
`Test-OutputIsoPca2023Readiness`'s comments at the relevant lines.

**Engineering lesson**: when a known-working template fails in a
new place, the difference between the templates is the first thing
to inspect. The Step 2 investigation looked for differences in
parameter binding, scope, and PSScriptAnalyzer suppression
attributes before getting to the element-type difference. A
minimal reproduction (4 lines, two cases) would have identified the
root cause in 5 minutes; the investigation took most of a session.

**Related**: §B.18.5 records the use-site mitigation.

### D.27 Microsoft OS tool dependency avoidance

**Symptom (r09.0 Step 1 Phase 5 v1 / v2)**: `expand.exe -F:` for
extracting a named file from a CAB rejected the operation with
"Cannot expand a file onto itself", even though the destination
filename differed from the source. A `Shell.Application` COM
fallback in v2 then placed the wrong content in the destination
(writing the CAB itself under the requested filter's name). Both
failures occurred on a current Windows 11 Build 26100 host.

**Root cause**: in-box Microsoft OS tools have brittle edge cases
that surface specifically when interacting with archive formats
whose internal name conflicts with the destination basename, or
that contain a single nested archive. The bugs are not in this
script.

**Mitigation**: **prefer well-maintained, independent
third-party tools for archive extraction**. The same
philosophy underlies:

- `oscdimg` (from Windows ADK Deployment Tools, distinct from
  in-box `bcdedit`) for ISO assembly.
- `robocopy` (in-box but stable since Windows 2000) for
  high-fidelity copy operations, replacing `Copy-Item -Recurse`
  per §B.22.16.
- Eventual move toward third-party SHA tools if `Get-FileHash` ever
  produces inconsistent hashes across hosts (no incident yet).

**Generalisation**: a Microsoft in-box tool that has not been
substantially maintained since Windows 7 is at higher risk of
edge-case failure on modern Windows builds than a focused
third-party tool actively maintained by an upstream community. The
generalisation is not "avoid Microsoft tools"; it is "evaluate
maintenance posture per-tool".

**Related**: §B.22.16
(robocopy preference).

### D.28 Sampling versus comprehensive search

**Symptom (r09.0 Step 1 Phase 5 v3)**: the parser PoC ran an
"exemplar walk" over the first 2-3 `<Update>` elements in the
108 MB Master XML, observed no `<SupersededBy>` element, and
recorded the conclusion "Master XML lacks `<SupersededBy>`". Phase
5 v4 then ran an exhaustive `Select-String -CaseSensitive:$false`
over the file and found **14,059 occurrences**.

**Root cause**: in a 136,102-element dataset, sampling 2-3 is not
representative for a phenomenon with ~10 % base rate. The
investigator implicitly relied on "the first few are typical",
which holds for homogeneous datasets but not for the bimodal
"Bundle vs Standalone" mix in the Master XML.

**Mitigation**: when probing a structured file for a feature's
presence, prefer **exhaustive case-insensitive grep**:

```powershell
Select-String -Path $masterXml -Pattern '<SupersededBy' `
              -CaseSensitive:$false | Measure-Object -Line
```

On a 108 MB file, this completes in seconds. The cost of running
the exhaustive search is always lower than the cost of being wrong
about whether the feature is present. The only exception is when
the exhaustive search would be combinatorial (e.g. checking every
pair of elements for a relationship); in that case, sampling is
unavoidable and the conclusion must be stated as a sample with
confidence bounds.

**Generalisation**: "I looked at a few of them" is acceptable for
exploratory inspection; it is not acceptable for design decisions.
The transition from "I looked" to "It is absent" requires
exhaustive evidence or a statistical statement.

### D.29 Code bug versus configuration problem triage

**Symptom (r08.0 Step 4d, narrowly avoided)**: a P07 `0x800f0823`
failure on Server 2016 was nearly addressed by patching
`Invoke-PatchSubPhase` to retry-with-different-args, on the theory
that DISM was being called incorrectly. Triage revealed the
prerequisite SSU was absent from the baseline; the code was
correct, the config was incomplete.

**Root cause**: failures from the runtime layer are easy to
misread as code defects. The investigator's instinct is to fix the
caller (closer to home, easier to edit). When the failure originates
in Microsoft-side requirements that the script reads via config,
the fix belongs in the data, not the code.

**Mitigation**: a one-question triage at the top of every failure
investigation:

> **"Is the failure originating in logic this script controls, or
> in a fact the script reads?"**

If the failure references Microsoft KB IDs, build numbers, file
formats, or update relationships, the burden is on the config /
data path until proven otherwise. Reach for code edits only after
the config / data path has been verified complete.

The §B.19 servicing-consistency check is in part the systemic
mitigation: it makes a config-side prerequisite gap detectable before
the code-side runtime failure surfaces.

**Related**: §B.19 (graph-based dependency closure); §D.24 Pattern 3.

### D.30 Helper function unification

**Symptom (r08.0 Step 4c)**: six functions across the script read
`$_.Type` from a `ResolvedPatch` object, but the authoritative
field name was `$_.PatchType`. The mismatch was not caught by
PSScriptAnalyzer (both names are syntactically valid; the
type-mismatch surfaced only at runtime when `$_.Type` returned
`$null` and the downstream conditional silently skipped the
patch).

**Root cause**: parallel evolution. Different cycles introduced
different conventions in different functions without a unifying
accessor. The defect was silent because the script's logic treats
"unrecognised type" as "skip", which produces no error trace.

**Mitigation (new in r09.0 Step 1)**: introduce a single helper
`Get-PatchEntryType` that:

```powershell
function Get-PatchEntryType {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] $PatchEntry)
    # Read with dual-field fallback to absorb historical field-name drift
    if ($PatchEntry.PSObject.Properties['PatchType']) { return $PatchEntry.PatchType }
    if ($PatchEntry.PSObject.Properties['Type'])      { return $PatchEntry.Type      }
    return $null
}
```

All call sites that previously read `$_.Type` or `$_.PatchType`
directly now route through `Get-PatchEntryType`. The function is
the **single point of truth** for the field-name question.
Adding a third name in the future is a one-line change in this
helper plus a one-line CHANGELOG entry; no call-site sweep is
needed.

**Generalisation**: when a piece of data is read from N call sites
and two or more sites disagree about how to read it, the fix is a
helper that absorbs the disagreement, **not** a sweep that
"corrects" all sites to one convention. The sweep is fragile
against future drift; the helper is forever.

**Related**: §B.10 (PatchPlan engine, normative field name);
§B.22.21 cross-reference matrix.

---

# Appendices

> Appendices carry non-normative material that supports navigation
> and traceability of this SPEC. They are intentionally separated
> from Parts A–D so that an LLM agent reading only the normative
> content has a clean cutoff.

## Appendix E — Function reuse map

> **Status**: informative. **Source**: hand-curated inventory of
> function provenance as of r09.0.

The script reuses several helpers from sibling repositories. The
provenance is recorded so a future maintainer knows where to look
when the original needs an upstream fix.

### E.1 Reused verbatim from `Download-SpeakerDeck.ps1`

| Helper | Role |
|:---|:---|
| Debug Trace Facility (`Start-DebugTrace`, `Set-DebugStep`, `Stop-DebugTrace`, `Export-DebugTraceJson`) | Per-phase forensic state capture |
| `Write-Step`, `Write-Ok`, `Write-Caution`, `Write-Fail`, `Write-Skip`, `Write-PhaseHeader`, `Write-PhaseFooter` | Log helpers with severity prefixes (§A.3) |
| `Get-EnvironmentInfo` | Five-pillar environment dump (OS, PS, locale, network, ADK) |
| `Add-ErrorJsonlEntry` | Per-error JSONL append |
| `Invoke-DownloadWithProgress` | Progress-aware HTTP download with retry |
| `Assert-IsAdministrator` | Elevation check |
| `Set-Utf8PipelineEncoding` | Console encoding setup |

### E.2 Reused from `Deploy-AMDChipsetDriverOnWindowsServer.ps1` (Appendix F)

| Helper | Role | Note |
|:---|:---|:---|
| `Get-SevenZipPath` | Probe 7-Zip in standard install locations | r09.0+ |
| `Get-LatestSevenZipUrl` | Three-tier fallback to obtain MSI download URL | r09.0+ |
| `Install-SevenZipFallback` | Silent MSI install of 7-Zip | r09.0+ |

### E.3 New for `Update-WindowsServerIso.ps1`

| Helper | First shipped | Role |
|:---|:---|:---|
| `Build-PatchPlan` | r03 | Target-aware PatchPlan engine (§B.10) |
| `Test-PatchServicingReadinessOnMount` | r04 | Mount-time prerequisite check (§B.13); renamed from `Test-PatchDependencyClosureOnMount` in r11.12 |
| `Get-Pca2023ReadinessSnapshot`, `Show-Pca2023ReadinessSnapshot`, `Format-Pca2023ReadinessForReport` | r05.0 | Health verdict for PCA2023 readiness (§B.17) |
| `Convert-WimBootToPca2023Signed` | r05.0 | PSA-clean reimplementation of `Make2023BootableMedia.ps1` (§B.17) |
| `Get-IsoBootCertReadiness` | r05.0 | INPUT-side boot.wim readiness inspection (§B.17.2) |
| `Test-OutputIsoPca2023Readiness` | r08.0 Step 3 | OUTPUT-side ISO 5-target check (§B.18) |
| `Assert-WorkspacePreflight` | r04.3 | Workspace structural readiness (§B.21) |

### E.4 Helper unification (r09.0)

| Helper | Replaces |
|:---|:---|
| `Get-PatchEntryType` (§D.30) | Six direct reads of `$_.Type` / `$_.PatchType` across the script |
| `Get-OrEnsurePca2023Snapshot` | Repeated snapshot construction blocks in P10 / P12 |
| `Show-PhaseSummary` (idempotent since r07.0 Step 19) | Duplicated phase-timing renderers |

## Appendix F — Reference projects

> **Status**: informative.

The script depends on or borrows patterns from the following
projects. Pinned references help a future maintainer follow the
upstream fix path.

### F.1 Microsoft

| Project | URL | Role |
|:---|:---|:---|
| `microsoft/secureboot_objects` | https://github.com/microsoft/secureboot_objects | Source of `Make2023BootableMedia.ps1` v1.4 (the upstream PSA-clean reimplementation target, §B.17) and the EFI_EX asset bundle |
| Microsoft Support article KB5053484 | https://support.microsoft.com/en-us/topic/updating-windows-bootable-media-to-use-the-pca2023-signed-boot-manager-d4064779-0e4e-43ac-b2ce-24f434fcfa0f | The "Applies To" list that establishes Server 2016/2019/2022 are in scope for PCA2023 boot-manager updates (§B.17.4) |
| Windows ADK (Deployment Tools) | https://go.microsoft.com/fwlink/?linkid=2289980 | Provides `oscdimg.exe` (§B.21.2 / D.4) |

### F.2 Independent maintainers

| Project | URL | Role |
|:---|:---|:---|
| OSDBuilder | https://github.com/OSDeploy/OSDBuilder | DISM mount + dismount retry pattern (D.1); 0x800f081e suppression heuristic (D.8) |
| Win_ISO_Patching_Scripts_zhCN | https://github.com/adavak/Win_ISO_Patching_Scripts_zhCN | Three-tier `etfsboot.com` / `efisys.bin` fallback chain (D.4) |
| windows-evaluation-isos-scraper | https://github.com/rgl/windows-evaluation-isos-scraper | Canonical Server 2022 SHA-256 hash sourced from this project |
| 7-Zip (`ip7z/7zip`) | https://www.7-zip.org/ + https://github.com/ip7z/7zip | Archive extraction helper for tool acquisition (r09.0+) |

### F.3 Companion in-house scripts

| Project | Relationship |
|:---|:---|
| `Download-SpeakerDeck.ps1` (sister sub-project under `scripts/powershell/download-speakerdeck-oracle4engineer/`) | Source of the §A inherited common spec body (debug trace, log helpers, env probe, retry primitives). Its SPEC.md is the authoritative copy of the inherited rules. |
| `Deploy-AMDChipsetDriverOnWindowsServer.ps1` | Source of the 7-Zip helper trio (Appendix E.2) |

## Appendix G — Historical revision matrix

> **Status**: informative. **Source**: derived from
> [`CHANGELOG.md`](./CHANGELOG.md). See CHANGELOG for the per-cycle
> detail.

### G.1 Cycle overview

| Cycle | Released | Theme |
|:---|:---:|:---|
| r02.x | 2026-05-24 | Initial baseline, debug trace facility, dynamic patch resolution |
| r03 | 2026-05-24 | PatchPlan engine, RefreshAllBaselines |
| r04.0 – r04.4 | 2026-05-24 → 2026-05-25 | Sub-phase sequences, supersedence-aware Catalogue, workspace preflight, self-verification suite (T1-T5) |
| r05.0 – r05.1 | 2026-05-25 | PCA2023 boot manager support; Schema v2.1; KbId/FileName remediation |
| r06.0 (Phase 1 / 2 / 3) | 2026-05-25 → 2026-05-26 | Update Type Matrix; PoC: release-info, .NET CU, Dynamic Update; Phase 3 architectural baseline |
| r07.0 Step 1 – Step 19 | 2026-05-25 → 2026-05-26 | Release-info migration; config-driven token matching; data/ flat layout; numerous polish steps and parser hardening |
| r08.0 Step 1 – Step 4 | 2026-05-27 | Server 2016 EVAL PCA2023 viability confirmed; install.wim symmetry; `Test-OutputIsoPca2023Readiness`; KB5087537 SSU-prerequisite incident |
| r09.0 Step 1 (this SPEC) | 2026-05-27 (planned implementation) | Servicing Dependency Database (§B.19); new D.24-D.30 lessons; SPEC restructure to Part A/B/C/D standard form |
| r10.x | 2026-05-28 → 2026-05-29 | Schema hardening (legacy `Patches` forbidden + regression guard); canonical JSON parity (T11) |
| r11.1 – r11.33 | 2026-05-29 → 2026-06-27 | Cross-repo canon vendoring; live-WUA removal (on-mount readiness, T20); P07 cleanup/export hardening (T24/T25); Defender exclusions (T26); wsusscn2 Servicing Dependency Database retired (D1) |
| r11.34 – r11.43 | 2026-06-27 → 2026-06-28 | Data-source migration to the Microsoft Update Catalog (D2): Config Schema v3.0 `Lines[]`/`Kind`/`PatchModel`, b3 builder (T27/T28), A00 `RebuildDataset`, seed contract (seed gate) |
| r11.44 – r11.51 | 2026-07-02 | Audit-remediation arc: digest-format boundary (T29); SetupDU discriminator hard-fail (T30); TBAU SEED→DERIVED + P11 hard check (T31); legacy input paths + `-EvalIsoMode` retired; post-refresh re-derivation defects fixed; SPEC vocabulary reconciled to v3.0 Kinds |

### G.2 Roadmap (next cycles)

This section deliberately stays short. Per
[`docs/history/r07.0-followups.md`](./docs/history/r07.0-followups.md)
and the per-cycle finding documents, the active follow-up tasks are
tracked there with P0/P1/P2 priority tags. Roadmap-level
forward-looking content lives in those documents, not in this SPEC.

Open at r09.0 inception (Steps 1-3 SUPERSEDED -- see below):

- r09.0 Steps 1-3 (the §B.19 Servicing Dependency Database + its parser /
  layer-2 schema / P06 Stage 2 wiring / `RefreshDependencyDatabase` action, and
  the `-EnableDependencyCheck` opt-in) were **superseded by the data-source
  migration** from `wsusscn2.cab` to the Microsoft Update Catalog. That whole
  `wsusscn2`-derived approach was removed and replaced by the per-`PatchModel`
  consistency check `Test-PatchModelConsistency` (run by P06
  `ValidatePatchServicing`); see §B.19 for the authoritative record. These steps
  are retained here for historical context only and will not be implemented.
- The KB5087537 SSU-prerequisite incident (originally tracked under Step 4) is
  **resolved on the config side as of r11.20**: the standalone Server 2016 SSU
  (KB5088064) is now auto-discovered by `Resolve-Ssu2016` (§B.22.5) instead of
  being hand-patched into `config-Server2016.json`.

### G.3 Deprecation list (kept for context)

| Item | Deprecated in | Replacement |
|:---|:---|:---|
| Part E "Roadmap" (top-level) | r09.0 SPEC rewrite | CHANGELOG + per-cycle followups (now Appendix G.2) |
| Part F "Function Reuse Map" (top-level) | r09.0 SPEC rewrite | Appendix E |
| Part G "Self-verification tools" (top-level) | r09.0 SPEC rewrite | Part C.9 |
| Part H "Reference Projects" (top-level) | r09.0 SPEC rewrite | Appendix F |
| Part I "Servicing Dependency Database" (top-level) | r09.0 SPEC rewrite | Part B.19 |
| `B.14b` (out-of-sequence) | r09.0 SPEC rewrite | Absorbed into §B.4.3 |
| `B.23` (24-subsection narrative) | r09.0 SPEC rewrite | §B.22 (decision-record form) |
| `Type` field on resolved patches | r09.0 Step 1 | `PatchType` (canonical); `Get-PatchEntryType` shim at read sites |

---

**End of SPEC.md**

> This SPEC will be updated in lock-step with code changes. The
> revision letter in `$Script:ScriptVersion` matches the revision
> letter under which a given normative section was introduced or
> last revised. See `CHANGELOG.md` for the per-revision detail.

