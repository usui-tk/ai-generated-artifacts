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
| **Phase identifier** | `P01`–`P13`, `A01`–`A04` | Pipeline phases (see §B.5) and stand-alone actions (see §B.6) |

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
| SPEC-WSI-020 | Servicing Dependency Database (wsusscn2-derived) | §B.19 |
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
  - [B.12 Catalogue scrape and supersedence selection](#b12-catalogue-scrape-and-supersedence-selection)
  - [B.13 Pre-apply dependency closure check](#b13-pre-apply-dependency-closure-check)
  - [B.14 Refresh policy and RefreshAllBaselines](#b14-refresh-policy-and-refreshallbaselines)
  - [B.15 Update type matrix per OS generation](#b15-update-type-matrix-per-os-generation)
  - [B.16 LCU package format per OS](#b16-lcu-package-format-per-os)
  - [B.17 PCA2023 boot manager support](#b17-pca2023-boot-manager-support)
  - [B.18 Output ISO verification](#b18-output-iso-verification)
  - [**B.19 Servicing Dependency Database** (r09.0+)](#b19-servicing-dependency-database)
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

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.reference-assets version=0.1.0 hash=d1f03d5c548d4f3f policy=canonical binding=follow-latest >>> -->
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

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.source-file-format version=0.1.0 hash=f7105ebfe3d202ff policy=canonical binding=follow-latest >>> -->
### A.2 Source file format

Script source files are encoded **UTF-8 with BOM** and use **CRLF** line endings. Non-ASCII
characters are confined to intentional data/string literals; identifiers, keywords, and code
are ASCII (the documentation-language policy is A.12). Encoding and line-ending conformance is
enforced by the static-analysis gate (A.11); files that are not BOM+CRLF, or that carry stray
non-ASCII outside sanctioned literals, fail the gate.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.source-file-format <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.banner-version version=0.1.0 hash=9821c85a0e065145 policy=canonical binding=follow-latest >>> -->
### A.3 Banner and version

Each script carries a single canonical **version string** and emits a **startup banner** that
prints the script identity, the version, and a **SHA256 self-fingerprint** of the running
file. The version string is the one source of truth for the script's revision and is the value
recorded in CHANGELOG. The banner format and the fingerprint computation are common; the
concrete version value is per-consumer.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.banner-version <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.phase-architecture version=0.1.0 hash=9af42a0010ff6f52 policy=canonical binding=follow-latest >>> -->
### A.4 Phase architecture

Scripts are organised into **numbered phases**. The numbering convention (monotonic integer
phases, optional phase *groups*, and a uniform per-phase header/footer log line carrying the
phase number, title, and elapsed tag) is common. The **phase count and the phase map**
(which work each phase does) are consumer-specific and are defined in the consumer's **Part
B**, not here.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.phase-architecture <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.logging version=0.1.0 hash=8e1353694d8216fa policy=canonical binding=follow-latest >>> -->
### A.5 Logging conventions

Logging goes through the shared logging helper family (vendored from the code canon). Messages
carry a **severity marker** from the canonical set (informational / detail / caution / error
and the phase markers); console output uses the canonical colour discipline for each severity;
network operations use TLS. Scripts do not write ad-hoc colour or bypass the helpers. The
helper set is fixed by the code canon; this region fixes the *conventions* for using it.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.logging <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.path-handling version=0.1.0 hash=1526d2dbb85bb58f policy=canonical binding=follow-latest >>> -->
### A.6 Path handling

Paths are handled defensively: prefer **`-LiteralPath`** over wildcard-expanding parameters;
never expand wildcards on externally supplied input; build paths with validated joins (not
string concatenation); and confine scratch files to a controlled work root rather than the
current directory or a shared temp location. These rules are common; the specific work-root
location is per-consumer.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.path-handling <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.parameter-handling version=0.1.0 hash=9969ad954a28fc39 policy=canonical binding=follow-latest >>> -->
### A.7 Parameter conventions

Scripts expose the canonical **standard parameter set** (the shared switches every consumer
provides) plus consumer-specific parameters. Mutually exclusive options are validated at
entry; invalid combinations fail fast with a diagnostic. Help/usage shows the startup banner.
The standard switch set and the validation discipline are common; the consumer-specific
parameter list is defined in the consumer's SPEC.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.parameter-handling <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.error-diagnostic version=0.1.0 hash=0d472879675b224b policy=canonical binding=follow-latest >>> -->
### A.8 Error and diagnostic model

Diagnostics are **three-layered**: (1) human-readable console output; (2) a per-run detail log
file; (3) structured per-failure records. Failures are **classified** (e.g. transient vs
fatal vs configuration) so callers can react. Each failure is recorded as a structured entry
following the canonical record shape (A.9 JSONL conventions). If a consumer additionally
provides an **operation-level trace facility** (an optional feature - see the consumer's Part
A.14 / project section), the per-failure records and the operation-level trace coexist; this
region does not require such a facility.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.error-diagnostic <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.csv-conventions version=0.1.0 hash=38cb631efd9af8a9 policy=canonical binding=follow-latest >>> -->
### A.9 CSV conventions

Tabular outputs and state files share common **column-naming** and **file-naming** conventions:
stable snake/Pascal column names, a per-phase output-file naming scheme, and a designated state
file for resumable runs. CSV is the baseline tabular format every consumer supports.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.csv-conventions <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.jsonl-conventions version=0.1.0 hash=3d605116d9e9b33c policy=canonical binding=follow-latest >>> -->
### A.9 (cont.) JSONL conventions - optional feature

A consumer **may** additionally emit JSONL (one JSON object per line) for machine consumption -
notably the per-failure records of A.8. When present, JSONL files follow the canonical naming
(per-phase, purpose-suffixed), use **camelCase** keys, and are LF-terminated. This region is an
**optional feature**: a consumer that emits only CSV omits it.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.jsonl-conventions <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.environment-eval version=0.1.0 hash=669c9ba612d6f35b policy=canonical binding=follow-latest >>> -->
### A.10 Environment evaluation

The **environment-evaluation phase (the first phase of the run)** assesses the host before any
work: it gathers platform/runtime facts in tiers (a baseline probe, then progressively
deeper checks) and **asserts compatibility** (runtime version, privileges, required tooling),
failing fast with a clear diagnostic when a prerequisite is unmet. The tiered model and the
fail-fast compatibility assertion are common; the specific phase number/name and the exact
checks are consumer-specific (Part B).
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.environment-eval <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.static-analysis version=0.1.0 hash=a9e9c8d44b702ac2 policy=canonical binding=follow-latest >>> -->
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

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.doc-language-policy version=0.1.0 hash=8e392c54780c4a7f policy=canonical binding=follow-latest >>> -->
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

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.development-workflow version=0.1.0 hash=fdadacb9bf023186 policy=canonical binding=follow-latest >>> -->
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
> r09.0+ Servicing Dependency Database in B.19; cross-cutting file
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
                 'DumpFieldClassification',
                 'RefreshDependencyDatabase')]
    [string]$Action = 'Build',

    [Parameter()] [switch]$Execute,
    [Parameter()] [string]$WorkRoot,
    [Parameter()] [string]$OfflineSyncPackagePath,
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
| Microsoft Update Catalogue | live HTTPS | RefreshAllBaselines, Build (P03/P04) |
| `wsusscn2.cab` (offline-scan metadata) | Microsoft CDN | RefreshDependencyDatabase (builds Layer 2) |
| `data/servicing-dependency-database.json` (layer 2) | committed in repo | P06 servicing-readiness gate (required) |

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
│   ├── catalog/                    (HTML / JSON Catalogue cache)
│   └── wsusscn2/                   (layer 3 raw cab + extracts, NEW r09.0)
│       ├── wsusscn2.cab
│       ├── wsusscn2.cab.meta.json
│       ├── package.xml             (extracted from cab, may be deleted)
│       └── audit/                  (rolling 6-month archive)
├── output/<final-iso>.iso          (P09/P10 destination)
├── logs/                           (per-phase + transcript)
└── diag/<timestamp>/               (forensic JSON on failure / verbose)
```

The recommended pattern for multi-OS use is **one WorkRoot per OS
family** (e.g. `D:\UpdateWsi_2016`, `D:\UpdateWsi_2019`, …). This
side-steps the DISM mount-cache poisoning class of failure
documented in §D.25.

## B.4 OS profile (Config Schema v2.1)

**Status**: normative. **Policy ID**: SPEC-WSI-011 (Patch integrity
three-layer is built on this schema).

Each `data/config-Server<OsKey>.json` file is a per-OS configuration
profile that the script reads at P02 (ResolveInputs). Schema 2.1 is
the current shape; older revisions are documented in §B.22 for
historical reference.

### B.4.1 Top-level structure

```jsonc
{
  "Schema":  "2.1",
  "OsKey":   "Server2025",

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
| `EnableInstallWimUpdate` | `true` (2016/2019/2022) / `false` (2025) | Whether P07 applies LCU to install.wim |
| `EnableBootWimUpdate` | `true` | Whether P08 applies LCU to boot.wim |
| `EnableWinREUpdate` | `true` | Whether P08 applies Safe OS DU to WinRE.wim |
| `_VerifiedDate` / `_VerifiedBy` | `2026-05-24T00:00:00+09:00` / `manual:initial-r03` | Human verification record |

The three `Enable*Update` flags MUST be promoted from `Common` to
top-level by `Get-ConfigProfile`. The r08.0 Step 2 dead-code path
defect (flags read but not promoted) is documented in §D.NN.

### B.4.3 `PatchBaseline` block

Cadence: refreshed monthly per the AutoRefreshPolicy (§B.14).

```jsonc
"PatchBaseline": {
  "Schema":                  "2.0",
  "TargetBuildAfterUpdate":  "26100.32522",
  "PatchTuesdayOfBaseline":  "2026-05-12",
  "LastVerifiedDate":        "2026-05-24T00:00:00+09:00",
  "LastVerifiedBy":          "auto-scrape:Catalog",
  "VerificationMethod":      "auto-scrape+wsusscn2",
  "ChecksumAlgorithm":       "SHA256",
  "NeutralPatches": [
    {
      "Type":                "LCU",
      "KbId":                "KB5087539",
      "UpdateId":            "...",
      "Title":               "...",
      "ApplyOrder":          2,
      "IsCombined":          false,
      "FileName":            "...",
      "DownloadUrl":         "...",
      "LocalPath":           "patches/Server2025/...",
      "Sha256":              "...",
      "RequiresKbIds":       ["KB5088064"],         // populated by RefreshAllBaselines
      "Supersedes":          ["KB5082077"],          // populated by RefreshAllBaselines
      "RequiresMinimumOsBuild": "26100.32000",       // populated by RefreshAllBaselines (r09.0+)
      "_DependencyVerifiedDate":   "2026-05-27T10:30:00+09:00",
      "_DependencyVerifiedSource": "wsusscn2.cab@sha256:abc123..."
    },
    /* ... SSU, .NET CU, DynamicUpdate.Setup, DynamicUpdate.SafeOs ... */
  ],
  "ExcludeKbList": [],
  "OfflineSyncPackage": {
    "SourceUrl":                "https://catalog.s.download.windowsupdate.com/.../wsusscn2.cab",
    "LocalCachePath":           "Workspace_UpdateWsi/cache/wsusscn2/wsusscn2.cab",
    "LastDownloadedDate":       "2026-05-27T10:25:00+09:00",
    "LastDownloadedSha256":     "...",
    "LastDownloadedSizeBytes":  1073741824,
    "DependencyDatabasePath":   "data/servicing-dependency-database.json",
    "DependencyDatabaseSha256": "..."
  }
}
```

Patch `Type` values follow the inventory in §B.15. Field cadence and
who is allowed to mutate each field is the §B.14 decision matrix.

**Resolved patches live in `NeutralPatches[]`.** The field name 
`PatchBaseline.Patches` is a **legacy (pre-v2.1) name and is forbidden** 
in current configs. Code that resolves a patch set (e.g. P03 
RefreshPatchBaseline) MUST write to `NeutralPatches`, never to `Patches`. 
This is enforced mechanically by the machine-readable schema 
`schema/config.schema.json` (which declares `not.required: 
[Patches]` on `PatchBaseline`) and the CI gate in §C.3.2a. Background: 
the r10.3 P03 defect wrote scrape results to a non-schema `Patches` 
property; the schema gate exists so that class of drift fails in CI 
rather than on a real machine.

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
| P06 | Plan | ValidatePatchServicing: /data Layer 2 servicing-readiness gate (default-ON, blocking) |
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

The `param() ValidateSet` (script L242-L243) declares thirteen Actions.
The default is `PrepareBuildVerify`. The full list, grouped by purpose:

### B.6.1 Standard pipeline Actions

| Action | Phases run | Description |
|:---|:---|:---|
| `Prepare` | P01-P06 | Stage only (no patching, no DISM mount) |
| `Build` | P07-P10 | Patch and assemble; presumes Prepare already staged the workspace |
| `Verify` | P11-P13 | Verify an existing output ISO (presumes a prior Build -Execute produced it) |
| `PrepareBuildVerify` (default) | P01-P13 | Combined full pipeline (the standardFull sequence per script L12262) |
| `All` | P01-P13 + post-pipeline extras | StandardFull plus the additional steps gated by `if ($Action -in @('BootTest','All'))` (script L9088 / L12707) |

### B.6.2 Specialty Actions

| Action | Phases run | Description |
|:---|:---|:---|
| `BootTest` | (empty Phase array; Hyper-V smoke test) | Stand-alone Hyper-V Gen2 boot smoke test against the output ISO. Mutually exclusive with `-SyntheticTestMode` (script L358) |
| `GenerateManifest` | P01-P03 | Compute a manifest of resolved patches without proceeding to Fetch / Build / Verify (script L12271) |
| `Cleanup` | (custom; `Invoke-CleanupAction` at script L12361) | Clean up workspace and stale DISM mounts |
| `ListPhases` | (none) | Dump phase + action registry as JSON to stdout |
| `TestHarness` | (REPL hook at script L12525) | Eval-PS-function mode used by `tests/powershell_harness.py` (T3); not for human invocation |

### B.6.3 Admin Actions (A01 - A03 - A02 - planned A04)

| Action | Admin Phase | Phases run | Description |
|:---|:-:|:---|:---|
| `RefreshAllBaselines` | A01 | (`Invoke-AdminPhaseA01_RefreshAllBaselines` at script L586) | Refresh `data/config-Server*.json` baselines from upstream caches |
| `DumpFieldClassification` | A02 | (`Invoke-AdminPhaseA02_DumpFieldClassification` at script L587) | Emit the field-cadence decision matrix as JSON |
| `RefreshSnapshots` | A03 | (`Invoke-AdminPhaseA03_RefreshSnapshots` at script L588) | Refresh `data/raw-*` and `data/cache-*` from Microsoft Learn + Catalogue |
| `RefreshDependencyDatabase` | A04 | implemented; see §B.19.7 (parser pipeline) and §B.19.14 (lifecycle) | Refresh `data/servicing-dependency-database.json` (layer 2) from `wsusscn2.cab` (layer 3) |

A04 (`RefreshDependencyDatabase`) is implemented and admitted by the
`param()` ValidateSet. It runs the four-stage parser pipeline (§B.19.7)
and stamps the Layer 1 summary writeback (§B.19.11). See §B.19 for the
full servicing-dependency facility.

### B.6.4 Action semantics

- The `osLessActions` set (script L392) — `ListPhases`, `Cleanup`,
  `RefreshSnapshots`, `RefreshAllBaselines`, `DumpFieldClassification`,
  `TestHarness` — does not require `-OsVersion`. All other Actions
  REQUIRE `-OsVersion` (script L398-L400).
- `Verify` running standalone presumes the output ISO was produced by
  a prior `Build -Execute`; if missing, P11 reports `Critical`.
- `Prepare` produces a workspace ready for a later `Build` invocation;
  it MAY be used as a dry-run for staging correctness without the cost
  of DISM mount.
- `-OnlyPhases <phase[]>` overrides the Action's phase set (script
  L246) — useful for forensic re-runs of a single phase.

## B.7 ISO filename detection patterns

**Status**: normative.

P02 ResolveInputs picks the input ISO from `<WorkRoot>/source/iso/`
by trying the following filename patterns in order:

| Order | Pattern | Origin |
|:---:|:---|:---|
| 1 | `WS<OS>_<lang>.iso` | This script's recommended name |
| 2 | `<EvalIsoBaseName from config>.iso` | Per-config explicit name |
| 3 | `*server*evaluation*<lang>*.iso` (case-insensitive) | Microsoft Evaluation Center default |
| 4 | first `*.iso` in the directory | Last-resort fallback |

For multilingual workspaces, the per-language sub-pattern uses the
config's `LanguageSpecific.<lang>.Iso.FileName` value directly. The
fallback path emits a warning so the operator can tell whether
auto-detect succeeded.

## B.8 Patch integrity check (three-layer)

**Status**: normative. **Policy ID**: SPEC-WSI-011.

P04 verifies each patch download against **three independent
sources of truth**:

| Layer | Source | Field |
|:---:|:---|:---|
| 1 | The Microsoft Update Catalogue download link | server-reported `Content-Length` |
| 2 | The config-Server*.json `NeutralPatches[]` entry | recorded `Sha256` |
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

| Patch Type | Target lanes | Microsoft rationale |
|:---|:---|:---|
| `SSU`                     | Install + Boot + WinRE   | Every serviced WIM needs the latest servicing stack |
| `LCU`                     | Install + Boot           | WinRE uses Safe OS DU instead |
| `DotNet.Runtime`          | Install                  | .NET 4.x runtime KB lives in install.wim |
| `DotNet.OsLevel`          | (none)                   | OS-offering KB; recorded for traceability, not applied to WIM |
| `DynamicUpdate.Component` | Install                  | Component-store updates |
| `DynamicUpdate.SafeOs`    | WinRE                    | WinRE is the "Safe OS" |
| `DynamicUpdate.Setup`     | Setup                    | Setup binaries (pending.xml) |
| `LanguagePack`            | Install + WinRE          | User-facing UI + recovery UI |
| `LXP`                     | Install                  | LXPs are Store apps; no WinRE |
| `DotNet.LangPack`         | Install                  | .NET satellite assemblies |

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
PatchType : 'SSU' | 'LCU' | 'DotNet.Runtime' | ...   ← authoritative
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
| 4 | `I4.DotNet`                  | .NET 4.x cumulative (DotNet.Runtime only) |
| 5 | `I5.DynamicUpdate.Component` | Component-store DU |
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

## B.12 Catalogue scrape and supersedence selection

**Status**: normative. **Policy ID**: SPEC-WSI-015.

When the OS-aware Catalogue query for a single patch Type leaves
2 or more narrowed candidates after the Title-token / x64 filter,
the resolver enriches each candidate with the `Supersedes` and
`SupersededBy` arrays from `Get-SupersedenceFromCatalog`, then calls
`Select-LatestPatchBySupersedence` to keep only the latest.

**Match rule**: candidate `C` is "superseded by" candidate `D` when
`C.KbId` OR `C.UpdateId` is found (as a substring, case-insensitive)
anywhere in `D.Supersedes`. Substring match is used because
Catalogue Supersedes entries are inconsistent: some contain only the
KB number, some the full UpdateId GUID, some a free-form
`Package_for_KBnnnn~...` package identifier.

| Input | Outcome |
|:---|:---|
| 0 candidates | `Best = $null`, `Excluded = @()` |
| 1 candidate  | `Best = that one`, `Excluded = @()` |
| 2+ with clear supersedence | `Best = single survivor`, `Excluded = (the rest)` with `Reason = "Superseded by <title>"` |
| 2+ with no supersedence relation | `Best = first by Title desc`, `Excluded = (the rest)` with `Reason = "Ambiguous; chose newest by title"` |
| Pathological (all candidates supersede each other) | `Best = first input`, warning logged |

Supersedence lookup is a per-candidate HTTP call, so it only fires
when the narrowed count exceeds 1; the single-candidate path keeps
the HTTP cost at zero.

This protects the WIM-target-aware sequence against neighbouring KBs
that match the OS Title token by accident, e.g. a ".NET Framework
3.5 and 4.8.1 Cumulative Update" appearing in a search for the OS
LCU. Without supersedence-aware selection, the wrong KB could enter
the I3.LCU.FirstPass sub-phase and produce a botched install.wim.
The original r04.2 incident that motivated this section is
documented in §D.NN (umbrella KBs and supersedence drift).

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
package list. It is runtime-accurate but expensive. The new
`Test-PatchServicingReadinessFromGraph` (§B.19.10) runs **before**
the mount in P06, using `Get-WindowsImage` metadata only,
and uses the layer 2 database as its source of truth. The two are
complementary; both stay enabled.

## B.14 Refresh policy and RefreshAllBaselines decision matrix

**Status**: normative. **Policy ID**: SPEC-WSI-016.

The `$Script:OsConfigFieldGroups` constant maps each logical field
group to a Cadence and an optional Refresher function. The constant
drives the `-Action RefreshAllBaselines` (A01) decision matrix.

| Group Path | Cadence | Refresher |
|:---|:---|:---|
| `Common` | Stable | (none) |
| `PatchBaseline` | PatchTuesday | `Resolve-PatchSetFromCatalog` |
| `LanguageSpecific.<lang>.Iso` | IsoRelease | (none) |
| `LanguageSpecific.<lang>.LanguageSpecificPatches` | PatchTuesday | `Resolve-LanguageSpecificPatchesFromCatalog` |

Cadence semantics:

- **Stable**: once verified, never auto-refresh.
- **PatchTuesday**: refresh when recorded `PatchTuesdayOfBaseline` is
  older than the latest Patch Tuesday.
- **IsoRelease**: only refresh when Microsoft re-releases the ISO;
  not auto-refreshed in the current implementation (manual).

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

**Cross-reference**: r09.0+ extends RefreshAllBaselines with the
layer 2 sub-phase from §B.19.13 (lifecycle step 1). The Decision
Matrix above is unchanged; the new sub-phase runs before per-OS
Catalogue scraping.

## B.15 Update type matrix per OS generation

**Status**: normative. **Policy ID**: SPEC-WSI-017.

### B.15.1 The matrix

Microsoft ships different update product mixes across the OS
generations supported by this script. The matrix below records the
per-OS / per-Type stance the script enforces during baseline
resolution.

| Type | Server 2016 | Server 2019 | Server 2022 | Server 2025 |
|:---|:---:|:---:|:---:|:---:|
| `SSU`                     | required (standalone) | required (combined LCU+SSU since 2024-4B) | required (combined LCU+SSU) | required (combined LCU+SSU) |
| `LCU`                     | required (standalone) | required (combined LCU+SSU since 2024-4B) | required (combined LCU+SSU) | required (combined LCU+SSU, WIM-format MSU) |
| `DotNet.Runtime`          | applicable | applicable | applicable | applicable |
| `DotNet.OsLevel`          | applicable (recorded only) | applicable (recorded only) | applicable (recorded only) | applicable (recorded only) |
| `DynamicUpdate.Component` | not shipped | not shipped | applicable | applicable |
| `DynamicUpdate.SafeOs`    | not shipped | not shipped | applicable | applicable |
| `DynamicUpdate.Setup`     | not shipped | not shipped | applicable | applicable |
| `LanguagePack`            | bundled in eval ISO | bundled in eval ISO | bundled in eval ISO | bundled in eval ISO |
| `LXP`                     | n/a (no LXP for Server SKU) | n/a | n/a | n/a |

The `IsCombined` flag on each LCU entry distinguishes the standalone
form (KB5087537 for Server 2016, 2026-05) from the combined SSU+LCU
form. The flag MUST be set by `RefreshAllBaselines` based on
authoritative metadata; manual entries should default to `false`
unless explicitly verified. The historical defect on
`config-Server2016.json` where `IsCombined: true` was mis-recorded
and later corrected by r08.0 Step 4 is referenced from §D.NN.

### B.15.2 .NET CU multiplicity per OS

The .NET Framework Cumulative Update is delivered as an **umbrella
KB** that bundles N "ndp" runtime variants (e.g. `ndp48`, `ndp481`)
in separate `.msu` files but under one Catalogue UpdateId. The
resolver retains all surviving `.msu` files via
`Select-AllCanonicalPatchFiles`, so the `NeutralPatches[]` entries
share `KbId` / `Title` / `UpdateId` / `Supersedes` from the umbrella
KB but each carries its own `FileName` / `Sha256` / `LocalPath`.

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
`Select-AllCanonicalPatchFiles` are recorded in §D.NN.

### B.15.3 Combined LCU package detection

For Server 2019+, `Test-IsCombinedLcuTitle` identifies a combined
SSU+LCU MSU by matching the Catalogue Title against:

```
'cumulative update.*servicing stack'
'cumulative.*combined'
'rollup.*servicing stack'
```

A combined package's `IsCombined` field is set to `true`, which
informs `Build-PatchPlan` to skip the standalone SSU lookup for that
month.

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
| Server 2016 | No (verified via direct mount) | Yes (6 unique binaries) | Apply LCU → WinSxS deposits assets → P10 reads from boot.wim |
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
| `EFI_EX\bootmgr_EX.efi` | **PCA2011** (single-sign) | Intentionally PCA2011 per Microsoft `Make2023BootableMedia.ps1` v1.4 L876-L884 |

Neither file is dual-signed. The "PCA2011 + PCA2023 dual-sign"
hypothesis briefly entertained during r08.0 Step 2 was disproved by
`signtool /verify /pa /all /ds 0..3`; only one embedded signature
exists per file. Both files share PE-body bytes with their EFI/
counterparts (Authenticode hash matches because Authenticode hash
excludes the signature region).

### B.16.4 Pipeline implications

- P07 applies the LCU to install.wim before P09 / P10 (when
  `EnableInstallWimUpdate=true`).
- P10 reads from boot.wim, which P08 must have patched to bring the
  Microsoft-shipped EFI_EX staging assets out of install.wim's
  WinSxS into boot.wim's `\Windows\Boot\`.
- For Server 2025, P10 can short-circuit via the
  `RequiredByDefault=false` policy, since the install.wim already
  contains the assets natively.

## B.17 PCA2023 boot manager support

**Status**: normative. **Policy ID**: SPEC-WSI-018.

### B.17.1 Conversion target inventory (Microsoft 5-target spec)

The Microsoft authoritative reference is
`scripts/windows/Make2023BootableMedia.ps1` v1.4 (2026-03-13) in the
`microsoft/secureboot_objects` repository, function
`Copy-2023BootBins` L829-L941. Five targets are written into the
output media:

| # | Source (in boot.wim) | Destination (in ISO root) | Required | Expected signer |
|:-:|:---|:---|:---:|:---|
| 1 | `Windows\Boot\EFI_EX\bootmgfw_EX.efi` | `\efi\boot\bootx64.efi` (or `bootaa64.efi`) | required | **PCA2023** |
| 2 | `Windows\Boot\EFI_EX\bootmgr_EX.efi` (if present) | `\bootmgr.efi` | optional | **PCA2011 by Microsoft design** (see L876-L884) |
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
P10.

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


## B.19 Servicing Dependency Database

**Status**: normative (specification); implementation status: implemented.
**Policy ID**: SPEC-WSI-020.

The Servicing Dependency Database is a fact-only, machine-readable model
of the servicing relationships between Windows Server updates, derived
from Microsoft's offline-scan catalog (`wsusscn2.cab`). Its purpose is to
let the script answer, **before mounting any image**, whether a resolved
patch set will satisfy the servicing-stack prerequisite that CBS enforces
at install time — the class of failure that otherwise surfaces only as
`0x800f0823` deep inside an offline servicing run.

### B.19.1 Goals and architecture

The facility predicts one specific, high-cost failure: an LCU that
requires a newer servicing stack (SSU) than the image carries. On the
SSU-separate OSes (Server 2016 / 2019) the SSU ships as its own package,
so a patch set can be assembled that contains an LCU but not the matching
SSU; CBS then rejects the LCU with `0x800f0823`. The database makes the
required servicing-stack version visible up front so the check is a cheap
metadata comparison rather than a late mount-time failure.

The facility is structured into three layers:

| Layer | Artifact | Committed? | Role |
|:-:|---|:-:|---|
| **Layer 3** | `wsusscn2.cab` under `<WorkRoot>/cache/wsusscn2/` | No (git-excluded) | Raw Microsoft source; large, volatile, re-downloadable |
| **Layer 2** | `data/servicing-dependency-database.json` (+ `schema/servicing-dependency-database.schema.json`) | Yes | Distilled fact-only model; the runtime source of truth |
| **Layer 1** | `data/config-Server*.json` `PatchBaseline.OfflineSyncPackage` + per-patch `_DependencyVerified*` fields | Yes | Per-OS summary stamped back into the baseline |

- **Layer 3 is git-excluded** because the cab is hundreds of MB, changes
  monthly, and is freely re-downloadable from the CDN; committing it would
  bloat the repository with no traceability benefit.
- **Layer 2 is committed** because it is small, diffable, and is what the
  runtime check and the offline CI read; committing it makes each monthly
  refresh an auditable diff and lets air-gapped hosts run the check with
  no network.
- **Layer 1 carries only a summary** (the latest in-scope LCU identity
  and the servicing-stack facts per configured patch) so the baseline
  stays self-contained without duplicating the whole Layer 2 document.

### B.19.2 Data source and extraction dependency

#### B.19.2.1 `wsusscn2.cab`

`wsusscn2.cab` is the offline-scan catalog the Windows Update Agent uses
to evaluate update applicability without contacting Windows Update. It
contains a "Master XML" (`package.xml`) describing every update Microsoft
has ever offered to WSUS, plus per-package CABs holding the CBS metadata
for each revision.

- **CDN source URL** (normative):
  `https://catalog.s.download.windowsupdate.com/microsoftupdate/v6/wsusscan/wsusscn2.cab`
  (the legacy `http://download.windowsupdate.com/...` host remains a
  fallback). The literal filename `wsusscn2.cab` is Microsoft's, and is
  retained verbatim wherever the physical file or its URL is named.
- **Update cadence**: Microsoft refreshes the cab roughly monthly, around
  Patch Tuesday. Freshness is judged by age; a cab older than the
  configured threshold is treated as stale and re-downloaded.
- **Cab internal structure** (observed): a top-level cab whose
  `index.xml` `<CABLIST>` enumerates per-package cabs, each with a
  `RANGESTART` (the lowest revision id it stores). `package.xml` is the
  Master XML; each per-package cab holds `c/<revisionId>` CBS metadata
  entries.

#### B.19.2.2 7-Zip extraction (normative)

The cab is extracted with 7-Zip rather than the Windows-only shell COM or
`expand.exe`, so the same path works on the Linux CI. The invocation
pattern is:

```powershell
& $sevenZip x $archive ('-o' + $dest) -y -bsp0 -bso0
# Exit codes: 0 = ok, 1 = warning (non-fatal), >= 2 = fatal
```

- `x` preserves the archive's internal paths.
- The `-o<dir>` flag takes no space between flag and value; building it as
  `('-o' + $dest)` avoids quoting edge cases.
- `-y` answers prompts non-interactively; `-bsp0 -bso0` suppress progress
  and stdout so the call site can capture stderr cleanly.
- Exit 1 is a non-fatal warning (e.g. timestamp collision); exit ≥ 2 is
  fatal.

`Get-SevenZipPath` resolves the Windows `7z.exe` and the Linux `7z` / `7za`
binaries, so the extraction helpers run on both platforms. Extraction is
two-step: the outer cab yields `package.xml` (and `index.xml`); a targeted
second extraction of one per-package cab yields a single leaf's
`c/<revisionId>` CBS metadata when servicing-stack facts are needed.

### B.19.3 Master XML schema (observed, normative)

The parser targets the Master XML shape as observed empirically in real
cabs. Two `<Update>` element kinds matter:

**Bundle `<Update>`** (e.g. an LCU as offered to WSUS) carries
`IsBundle="true"`, a `<Prerequisites>` list of `<UpdateId>` GUIDs, and a
`<Categories>` block:

```xml
<Update CreationDate="2025-05-12T20:45:23Z" UpdateId="..." RevisionNumber="201"
        RevisionId="43268251" IsLeaf="true" IsBundle="true">
  <Prerequisites>
    <UpdateId Id="..." />   <!-- typically 5-10 entries -->
  </Prerequisites>
  <Categories>
    <Category Type="UpdateClassification" Id="0fa1201d-..." />
    <Category Type="Company"              Id="56309036-..." />
    <Category Type="ProductFamily"        Id="6964aab4-..." />
    <Category Type="Product"              Id="569e8e8f-..." />
  </Categories>
</Update>
```

**Standalone `<Update>`** is the per-architecture payload carrier; its
`<FileLocation Id="<digest>" Url="http://..." />` joins a payload digest
to a download URL, and `<BundledBy><Revision>` points back to the bundle
that contains it.

`<Prerequisites><UpdateId>` entries are **applicability / detectoid
GUIDs, not install-order KB dependencies** — there is no LCU→SSU
KB-prerequisite edge in the Master XML. `<SupersededBy><Revision>`
(present on roughly a tenth of updates) references successors by integer
`RevisionId`, not by `UpdateId`.

### B.19.4 Scope filter (normative)

The parser admits only updates that are in scope for the four supported
Server OSes within a recency window, using GUID tables held in the script
(`$Script:OfflineSyncOsCategoryGuids`,
`$Script:OfflineSyncUpdateClassificationGuids`,
`$Script:OfflineSyncCategoryGuidNameMap`,
`$Script:OfflineSyncEosEsuDenyProductGuids`). Scope is an **allow-list**
of Product and Classification GUIDs plus a recency window
(`recencyMonths`, default 24); the applied values are recorded in Layer 2
`_meta.scope`.

The four supported Product GUIDs are:

| OS | Product GUID |
|:---|:---|
| Server 2016 | `569e8e8f-c6cd-42c8-92a3-efbb20a0f6f5` |
| Server 2019 | `f702a48c-919b-45d6-9aef-ca4248d50397` |
| Server 2022 | `71718f13-7324-4b0f-8f9e-2ca9dc978e53` |
| Server 2025 | `b256987d-4693-4c87-955d-dbb9341205eb` |

The Server 2025 GUID is server-specific: it carries the Server 2025 LCU
(KB5087539 in the 2026-05 cab) but not the Windows 11 24H2 *client* LCU,
so client updates do not leak into scope. The superseded value
`ca006cfb-49eb-439b-880a-1312e1fc9713` is a different 24H2-era category
that stalls at an older month and must not be used. Server 2025 shares OS
build 26100 with Windows 11 24H2, so its payload URLs use the
`windows11.0` filename stem; this is expected and is not a scope leak.

#### B.19.4.1 EOS / ESU deny-list (normative)

End-of-support (EOS) and ESU-only Server OS categories are **not**
removed from the cab when the OS leaves support; they persist with live,
payload-bearing updates. Exclusion is therefore explicit, via a deny-list
of four Product GUIDs:

| Server version | Product GUID | State |
|:---|:---|:---|
| Server 2008 | `ba0ae9cc-5f01-40b4-ac3f-50192b5d6aaf` | EOS |
| Server 2008 R2 | `fdfe8200-9d98-44ba-a12a-772282bf60ef` | EOS |
| Server 2012 | `a105a108-7c9b-4518-bbbe-73f0fe30012b` | ESU |
| Server 2012 R2 | `d31bd4c3-d872-41c9-a2e7-231f372588cb` | ESU |

Exclusion semantics are **allow-overrides**: an update is excluded **iff
it carries a deny-list Product GUID AND carries no allow-list Product
GUID**. ESU-only rollups (which carry only a 2012 / 2012 R2 GUID) are
excluded; multi-OS overlap updates such as KB890830 (which also carry an
allow-list GUID) are admitted. A naive deny-overrides rule would wrongly
drop the overlap updates.

When the parser drops EOS/ESU bundles it counts them into
`_meta.stats.eosEsuBundlesExcluded` and records the distinct families into
`eosEsuFamiliesExcluded`, and emits a single operator caution naming the
count and families — a warned exclusion, not a silent prune.

### B.19.5 Microsoft-prose exclusion rule (normative)

Layer 2 is **fact-only**: it MUST NOT contain Microsoft's
human-readable prose (update titles, descriptions, KB article text,
`moreInfoUrl`, etc.). Only structural facts — GUIDs, revision ids,
payload URLs, digests, category GUIDs, servicing-stack versions — are
retained. This keeps the committed artifact free of copyrightable text
and makes its provenance a pure transformation of the cab's structural
data. The Layer 2 schema gate asserts the absence of prose markers
(`"title"`, `"description"`, `"moreInfoUrl"`, and similar) in the
committed file.

### B.19.6 Data-processing strategy (normative)

The source data is large and adversarial to naive processing: a
~600 MB cab whose Master XML is ~108 MB and indexes ~136,000 updates,
wrapped one level deep, plus ~73 per-package cabs holding CBS metadata.
The pipeline is built around the following processing constraints, each
of which is a normative implementation requirement, not an optimisation.

#### B.19.6.0 Testability-driven design (normative rationale)

The script body MUST be PowerShell because its ultimate targets — DISM,
Hyper-V, and the offline servicing of `install.wim` — are Windows-only
and have no cross-platform equivalent. That same constraint, however,
makes the PowerShell logic expensive to verify: a faithful end-to-end
test needs a Windows host, a mounted image, and a multi-hundred-MB live
cab, none of which exist in the development or CI environment where the
code is authored and reviewed.

The facility is therefore deliberately structured so that the **pure,
deterministic logic is separable from the Windows-only I/O**, and is
exercised offline from Python:

- The transform-heavy, side-effect-free units — Master XML parsing
  (`ConvertFrom-OfflineSyncPackage`), scope classification, the
  servicing-stack model derivation (`Get-OfflineSyncServicingStackInfo`,
  `Select-OfflineSyncLcuLeafRevision`, `Update-ServicingStackFromMeta`),
  the readiness verdict (`Test-PatchServicingReadinessFromGraph`), the
  data-contract gate, and canonical-JSON serialisation — take text or
  in-memory input and return values, with no cab download, 7-Zip call, or
  WIM mount inside them.
- The unavoidable I/O is quarantined into thin wrappers
  (`Get-OfflineSyncPackageIfNeeded`, `Invoke-OfflineSyncPackageExtract`,
  `Invoke-OfflineSyncLeafServicingStackExtract`) that are the only parts
  needing a real cab or Windows host.
- The Python test suite drives the pure units through committed fixtures
  and the script's `TestHarness` action, asserting their behaviour
  byte-for-byte (the canonical-JSON parity test) and structurally (the
  parser, scope-invariant, schema, and verdict gates). The Python
  reference implementations (e.g. `tests/common/canonical_json.py`) pin
  the PowerShell behaviour from the other side of the language boundary.

The two-language split (PowerShell body + Python verification) and the
CI's two-stage shape (a Linux stage that runs the offline gates plus a
Windows stage for the parts that genuinely need Windows) are consequences
of this principle: they maximise the share of the system that can be
designed, implemented, and regression-tested without a Windows host or a
live cab. A useful side effect is that the resulting I/O separation,
streaming discipline, and canonical-output contract — the rest of this
section — are not merely good practice but are *forced* by the
requirement that the logic be exercisable in isolation.

This testability-driven two-language pattern is not specific to this
subproject; it applies to the PowerShell-body / Python-verification
scripts in this repository generally, and is a candidate for promotion to
a shared (Layer 1) convention in a future revision. It is recorded here
because §B.19 is where its constraints (large binary input, no live cab in
CI) bite hardest.

#### B.19.6.1 Cab internal structure and size budget

| Member | Size (observed) | Role |
|:---|:---|:---|
| `package.cab` (inner wrapper) | ~15 MB | Wraps the Master XML |
| `package.xml` (Master XML) | ~108 MB | Index of ~136,102 updates |
| `package2.cab` … `packageNN.cab` | 1–34 MB each, ~650 MB total | Per-package CBS metadata fragments |

The Master XML is wrapped one level deep: `wsusscn2.cab` → `package.cab`
→ `package.xml`. The per-package cabs are addressed individually (never
all expanded at once). Peak working set is held under ~50 MB and peak
disk under a few hundred MB; the full cab is never expanded in one shot.

#### B.19.6.2 CAB extraction: 7-Zip only (normative)

CAB extraction MUST use 7-Zip, never the in-box `expand.exe` or
`Shell.Application` COM. This is a normative decision grounded in
concrete in-box-tool failures:

- **`expand.exe` self-overwrite.** When the destination directory holds
  a file whose basename matches the source cab, `expand.exe` rejects the
  operation ("Cannot expand a file onto itself") even though the target
  filename differs.
- **`expand.exe -F:filter` mis-selection.** The filter flag has been
  observed writing the cab into the destination under the source cab's
  name instead of the filtered member.
- **`Microsoft.Deployment.Compression.Cab.dll`** (the .NET wrapper) needs
  a fully-qualified destination and is not bundled with PowerShell, so it
  would expand the install surface.

7-Zip is resolved by `Get-SevenZipPath` across Windows (`7z.exe`) and
Linux (`7z` / `7za`); the invocation pattern is the §B.19.2.2 form.

#### B.19.6.3 Two-step targeted extraction

A single `7z x` would expand all ~75 inner files. Instead the cab is
opened in two targeted steps, each selecting only the needed member by
inclusive basename regex (`-ir!<file>`), into **separate** stage
directories so the §B.19.6.2 self-overwrite class of failure cannot
arise:

```powershell
& $sevenZip x $cab      ('-o' + $stage1) -ir!package.cab -y -bsp0 -bso0
& $sevenZip x $innerCab ('-o' + $stage2) -ir!package.xml -y -bsp0 -bso0
```

CBS metadata for a leaf is fetched the same way: rather than expanding
all per-package cabs, `Resolve-OfflineSyncRevisionToCab` locates the one
cab whose `index.xml` `<CABLIST>` `RANGESTART` is the greatest ≤ the
target revision id, and only that cab's single `c/<revisionId>` entry is
extracted (§B.19.9).

#### B.19.6.4 Large-XML parsing: streaming only (normative)

The ~108 MB Master XML MUST be parsed with a streaming `XmlReader`, never
loaded as `[xml]` / `XmlDocument`: a DOM load of this file was measured at
**peak memory +536 MB**, which fails in low-memory CI, whereas the
streaming walk keeps peak working set under ~50 MB. The streaming parse
(`ConvertFrom-OfflineSyncPackage`) applies the §B.19.4 scope filter inline
so only the ~138 in-scope updates are ever materialised in memory, out of
the ~136,000 observed.

The KB number is not on the `<Update>` element; it is recovered from the
`kb(\d+)` token (case-insensitive) in the `<FileLocation>` URL during the
streaming walk, joined back to its update via the payload digest, and
persisted into `kbIds`. Bundles record their leaf revision ids during the
walk so the LCU leaf can later be located without re-reading the XML.

#### B.19.6.5 Encoding and output integrity

External tool output is captured under a forced UTF-8 console encoding so
that a non-UTF-8 host code page (e.g. cp932 on a Japanese host) does not
mojibake captured bytes. The Layer 2 document is written by
`Save-CanonicalJsonFile` at `-Depth 32` in byte-canonical form (§B.23):
stable key order, fixed indentation, single trailing LF, UTF-8 without
BOM, and an atomic `.tmp` + `Move-Item` replace so a crash mid-write
never leaves a truncated database.

### B.19.7 Parser pipeline (normative)

The cab is converted to Layer 2 by a four-stage pipeline, driven as one
Action by `Invoke-AdminPhaseA04_RefreshDependencyDatabase` (the
`RefreshDependencyDatabase` Action, A04):

| Stage | Function | Role |
|:-:|---|---|
| 1 | `Get-OfflineSyncPackageIfNeeded` | Acquire the cab into `<WorkRoot>/cache/wsusscn2/`, or reuse a fresh cached copy; honours an operator-supplied cab via `-OfflineSyncPackagePath` |
| 2 | `Invoke-OfflineSyncPackageExtract` | Two-step 7-Zip extraction of `package.xml` from the cab (§B.19.6.3) |
| 3 | `ConvertFrom-OfflineSyncPackage` | XmlReader streaming parse of `package.xml` with the §B.19.4 scope filter applied (§B.19.6.4) |
| 4 | `New-ServicingDependencyDatabase` | Serialise the in-scope updates to `data/servicing-dependency-database.json` via `Save-CanonicalJsonFile` (§B.19.6.5) |

After Stage 4, the A04 wrapper performs the Layer 1 writeback
(`Update-Layer1DependencyVerification`, §B.19.11). Stage 4 also attaches
the servicing-stack facts (§B.19.9) to each in-scope LCU leaf. The
processing constraints each stage must observe — targeted extraction,
streaming parse, memory budget, encoding, canonical output — are
specified in §B.19.6.

### B.19.8 Layer 2 JSON schema (normative)

The authoritative shape is the JSON Schema
`schema/servicing-dependency-database.schema.json` (Draft-07), parallel
to the Layer 1 `schema/config.schema.json`. The committed
`data/servicing-dependency-database.json` is validated against it by the
Layer 2 schema gate (`tests/servicing_dependency_layer2_schema_test.py`),
and the scope/contract semantics are additionally pinned by
`tests/servicing_dependency_scope_invariants_test.py`. The document is a
flat **`_meta` + `updates`** structure, camelCase throughout.

#### B.19.8.1 Top-level structure

```jsonc
{
  "_meta": {
    "dataContractId":      "<family GUID>",
    "dataContractVersion": 1,
    "generator":           "Update-WindowsServerIso.ps1 ...",
    "scriptVersion":       "update-wsi-<date>-r<NN>",
    "scriptTag":           "...",
    "generatedAt":         "<iso-8601>",
    "sourceCab":  { "sourceUrl": "https://.../wsusscn2.cab", "size": 641849140, "sha256": "..." },
    "scope":      { "productGuids": [ ... ], "classificationGuids": [ ... ], "recencyMonths": 24, "evaluatedAt": "<iso-8601>" },
    "stats":      { "updatesObserved": 136102, "updatesInScope": 138, "bundlesObserved": 21149,
                    "categoryUpdates": 4204, "leafUpdatesWithPayload": 110749,
                    "fileLocationsObserved": 97051, "fileLocationsRetained": 97051,
                    "payloadDigestsOrphaned": 0, "eosEsuBundlesExcluded": 4910, "eosEsuFamiliesExcluded": 0 }
  },
  "updates": [ /* see B.19.7.2 */ ]
}
```

`updates` is a flat array, not a KB-keyed dictionary. `_meta.sourceCab`
carries a portable `sourceUrl` (the canonical CDN URL) and never a local
filesystem path; the recency-evaluation timestamp is
`_meta.scope.evaluatedAt`.

#### B.19.8.2 `updates[]` element

```jsonc
{
  "updateId": "...", "revisionId": "42949062", "revisionNumber": "200",
  "creationDate": "2025-03-10T16:05:49Z",
  "isBundle": true, "isLeaf": true, "deploymentAction": null,
  "productGuids": [ "569e8e8f-..." ], "classificationGuids": [ "0fa1201d-..." ],
  "companyGuids": [ "56309036-..." ], "productFamilyGuids": [ "6964aab4-..." ],
  "prerequisiteUpdateIds": [ "...", "..." ],
  "supersededByRevisionIds": [ "44174230", "..." ],
  "payloadFileDigests": [ "..." ],
  "payloadUrls": [ "http://download.windowsupdate.com/.../windows10.0-kb5053594-x64.cab" ],
  "kbIds": [ "5053594" ],
  "requiredServicingStackVersion": "10.0.14393.7692",
  "providedServicingStackVersion": null,
  "servicingStackModel": "separate"
}
```

| Field | Meaning |
|:---|:---|
| `updateId` / `revisionId` / `revisionNumber` | `<Update>` identity triple (revision values as JSON strings) |
| `creationDate` | `<Update>` creation timestamp, ISO-8601, verbatim |
| `isBundle` / `isLeaf` / `deploymentAction` | `<Update>` attributes; `deploymentAction` is `null` when absent |
| `productGuids` / `classificationGuids` / `companyGuids` / `productFamilyGuids` | `<Categories>` GUID sets; resolve to names via `$Script:OfflineSyncCategoryGuidNameMap` |
| `prerequisiteUpdateIds` | Raw `<Prerequisites><UpdateId>` GUIDs — applicability/detectoid, not KB install-order deps |
| `supersededByRevisionIds` | `<SupersededBy><Revision>` integers (JSON strings); a successor counts only when itself in scope |
| `payloadFileDigests` / `payloadUrls` | `<FileLocation>` digest → URL join |
| `kbIds` | KB numbers (bare numeric, no `KB` prefix) recovered from `payloadUrls` |
| `requiredServicingStackVersion` / `providedServicingStackVersion` | SS-version floor from the LCU's CBS metadata, and SS the configured SSU supplies (nullable; `provided` resolved at check time, so the committed file leaves it `null`) |
| `servicingStackModel` | `separate` (2016/2019) / `combined` (2022/2025) / `checkpoint` (baseline) |

There is no per-update KB key and no `Requires` field: the KB lives in
`kbIds`, and the SSU dependency is the servicing-stack version, not a KB
list.

### B.19.9 Servicing-stack extraction (normative)

The servicing-stack facts feeding the §B.19.10 SS-version check are
extracted by helpers kept free of file/7-Zip I/O so they are unit-testable
offline:

- **`Resolve-OfflineSyncRevisionToCab`** maps a revision id to the
  per-package cab holding its `c/<revisionId>` CBS metadata: the revision
  `R` lives in the cab with the greatest `index.xml` `<CABLIST>`
  `RANGESTART` ≤ `R`, locating one revision with a single targeted
  extraction instead of expanding all per-package cabs.
- **`Get-OfflineSyncServicingStackInfo`** reads a leaf's CBS metadata and
  derives `requiredServicingStackVersion` and `servicingStackModel`:
  - **separate** — `installerAssembly` carries a real servicing-stack
    build (e.g. Server 2016 `10.0.14393.7692`); that value is the
    `requiredServicingStackVersion`.
  - **combined** — `installerAssembly` shows the nominal placeholder
    `6.0.0.0` with an inline `Package_for_ServicingStack_<nnnn>` (Server
    2022); the SSU travels inside the LCU, so `requiredSs` is null and the
    SS check is N/A.
  - **checkpoint** — no CBS rollup/servicing-stack metadata (Server 2025
    `.msu` baseline leaves); `requiredSs` is null.

The live populate keeps cab/7-Zip I/O isolated:
`Select-OfflineSyncLcuLeafRevision` (pure) picks the LCU leaf from a
bundle's leaf revision ids; `Invoke-OfflineSyncLeafServicingStackExtract`
(the only I/O part) extracts each leaf's `c/<rev>` CBS text;
`Update-ServicingStackFromMeta` (pure) writes the SS fields onto the
matching updates, leaving updates with no leaf metadata unchanged. The
pure halves are covered offline (T15, T18) with committed CBS fixtures;
only the I/O wrapper needs a real cab.

### B.19.10 Verification API (normative)

Phase 2c verification is `Test-PatchServicingReadinessFromGraph`, a
pre-mount check over Layer 2 built on **three independent checks**, none
of which is a KB-prerequisite closure (there is no LCU→SSU KB edge,
§B.19.3). The real SSU dependency is the minimum servicing-stack version
in the LCU's CBS metadata, which CBS enforces as a numeric comparison
(failure = `0x800f0823`).

Signature:

```powershell
function Test-PatchServicingReadinessFromGraph {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [pscustomobject[]] $ResolvedPatches,
        [Parameter(Mandatory)] [pscustomobject]   $WimMountState,
        [Parameter()]          [string]           $DatabasePath = "$PSScriptRoot/data/servicing-dependency-database.json",
        [Parameter()]          [hashtable]        $PolicyOverride
    )
}
```

The function MUST NOT mount the WIM; it consumes the static WIM metadata
(build number, installed packages) captured by `Get-WindowsImage` and
passed via `$WimMountState`. It indexes Layer 2 updates by KB (`kbIds`,
else the `kb(\d+)` token from `payloadUrls`) and by `revisionId`, then
scores each resolved patch:

1. **Presence** — no KB match → `NotInDatabase`.
2. **SS version comparison** — `separate` only. Provided SS is taken from
   `$PolicyOverride[OsKey]`, else `$WimMountState.ProvidedServicingStackVersion`,
   else the matched update's `providedServicingStackVersion`. Provided <
   required → `SsTooOld` (the `0x800f0823` predictor). `combined` /
   `checkpoint` skip the check (N/A). If the SS fields are absent, the
   check is reported as skipped in `Notes` and never fails the patch.
3. **Supersession** — `Superseded` only when a `supersededByRevisionIds`
   entry is itself an in-scope update in Layer 2.

Verdict precedence: `NotInDatabase` > `SsTooOld` > `Superseded` > `Pass`.
`OverallStatus` is `Fail` if any `NotInDatabase` / `SsTooOld`, else
`Warning` if any `Superseded`, else `Pass`; a missing or unreadable Layer 2
yields `Available = $false` / `OverallStatus = 'Unknown'`. Layer 2 is read
with `ConvertFrom-CanonicalJson` so `_meta.generatedAt` survives as its
canonical ISO-8601 string. T16 and T17 are the executable contracts.

This graph-based check is complementary to the mount-time
`Test-PatchServicingReadinessOnMount` (§B.13): the graph check is the
predictive layer (runs before mount, cheap, reads Layer 2 + static WIM
metadata); the mount check is the runtime safety net (runs after mount,
reads the live installed-package list).

### B.19.11 Layer 1 integration (normative)

The A04 wrapper stamps a per-OS summary back into `data/config-Server*.json`:

- **`PatchBaseline.OfflineSyncPackage`** records the cab provenance:
  `SourceUrl`, `LocalCachePath`, `LastDownloadedDate`,
  `LastDownloadedSha256`, `LastDownloadedSizeBytes`.
- **`Update-Layer1DependencyVerification`** propagates the latest in-scope
  LCU identity onto the relevant `PatchBaseline.NeutralPatches[*]` entries
  as `_DependencyVerifiedUpdateId`, `_DependencyVerifiedRevisionId`,
  `_DependencyVerifiedCreationDate`, and `_DependencyVerifiedAt`. Entries
  with no matching in-scope LCU are left unchanged; the writeback is
  idempotent (a second run with unchanged data writes nothing). T13 is the
  executable contract.

Automation level is semi-automatic: the writeback runs as part of A04 /
RefreshAllBaselines, but the operator reviews the resulting Layer 1 / Layer 2
diff before committing.

### B.19.12 P06 ValidatePatchServicing integration (normative)

P06 is a single, default-ON, blocking servicing-readiness gate. It
validates the resolved patch set (`$Script:ResolvedPatches`) against the
pre-generated wsusscn2 Layer 2 dependency database via
`Test-PatchServicingReadinessFromGraph` (§B.19.10), and:

- **Default-ON** — it runs on every Setup-group run; there is no opt-in
  switch. It is skipped only under `-UseBaselineOnly` (trust the
  pre-verified baseline as-is) or `-SyntheticTestMode` (no real patches).
- **Blocking** — it throws (aborts the build) when the overall status is
  `Fail`: `SsTooOld` (predicts install error `0x800f0823`) or
  `NotInDatabase` (an uncovered patch). `Superseded` is logged as a
  warning and does not block; `Pass` proceeds.
- **Strict on absence** — when Layer 2 is absent or unreadable it reports
  `Available = $false` / `OverallStatus = Unknown`, and P06 **blocks**
  (run `-Action RefreshDependencyDatabase` to build Layer 2, or pass
  `-UseBaselineOnly` to bypass P06).

P06 only reads whatever Layer 2 is already on disk; it does not acquire
the cab. Acquiring/refreshing Layer 2 is the separate `RefreshDependencyDatabase`
(A04) operation, optionally fed a manually-staged cab via
`-OfflineSyncPackagePath`.

The former Stage 1 — a live Windows Update Agent COM offline scan against
`wsusscn2.cab` — was removed. WUA evaluates applicability against the
local host's OS image rather than the mounted target WIM, so it was
host-relative and returned false negatives on cross-OS-family builds
(e.g. a Server 2025 host building a Server 2016 image). The removal also
retired `-IgnorePatchValidation`, `-EnableDependencyCheck`,
`Invoke-WuaOfflineScan`, `Compare-PatchSetVsWuaScan`,
`Export-PatchValidationReport`, and the `diag/<timestamp>/`
patch-validation report set.

### B.19.13 Data contract and versioning (normative)

Versioning is governed by a **shared data-contract identity**, not a
per-model schema version. The script holds `$Script:DataContractId` (a
stable family GUID) and `$Script:DataContractVersion` (an integer epoch),
and stamps both into every data artifact's `_meta`.
`Test-DataContractConsistency` (T19) classifies each artifact against the
script's values into one of five verdicts:

| Verdict | Condition |
|:---|:---|
| `Current` | `dataContractId` matches and `dataContractVersion` equals the script's |
| `Stale` | matching id, but `dataContractVersion` older than the script's (regenerate) |
| `Refuse` | matching id, but `dataContractVersion` newer than the script's (the script must not consume a future artifact) |
| `Foreign` | `dataContractId` belongs to a different contract family |
| `Unknown` | no `_meta` contract stamp present |

Both Layer 1 (`config-Server*.json`) and Layer 2 carry the stamp, so both
classify as `Current`. The directory-level roll-up takes the worst
verdict, with `Unknown` never worsening the result (a stampless artifact
is valid, just unclassified).

The epoch is bumped only on a **breaking shape change** to a data model —
a change that adds, removes, retypes, or re-nests a field such that an
existing consumer could misread it. An atomic relabel (renaming a field
across the script, schema, and all committed data in one commit) is not a
breaking change and does not bump the epoch. The current epoch is `1`.

#### B.19.13.1 Validation gates

Three offline gates enforce the Layer 2 contract on every commit and CI
run, independent of any live cab:

| Gate | Asserts |
|:---|:---|
| `servicing_dependency_layer2_schema_test.py` | The committed Layer 2 validates against `schema/servicing-dependency-database.schema.json` (Draft-07), carries the data-contract stamp, uses portable provenance, and contains no Microsoft prose (§B.19.5) |
| `servicing_dependency_scope_invariants_test.py` | The scope model holds over the committed Layer 2: allow-list / deny-list disjoint and canonical, allow-overrides classification, no in-scope update is deny-only, the per-OS recency floor (§B.19.4) |
| `canonical_json_format_check.py` | Every `*.json` under `data/` and `tests/` (Layer 2 included) is in byte-canonical form (§B.23) |

### B.19.14 Lifecycle and operations

#### B.19.14.1 Refresh triggers

Layer 2 is refreshed by two paths: as part of `RefreshAllBaselines`
(which chains A04 so a monthly baseline refresh also refreshes the
dependency database), or directly via `-Action RefreshDependencyDatabase`
(A04) for an ad-hoc refresh. A04 does not modify `config-Server*.json`
beyond the §B.19.11 summary writeback.

#### B.19.14.2 Cache invalidation

`<WorkRoot>/cache/wsusscn2/wsusscn2.cab` is stale when any of: the file is
absent; its `.meta.json` `FetchedAt` predates the latest Patch Tuesday by
more than two days; a HEAD probe of `SourceUrl` returns a newer
`Last-Modified`; or the recorded `Sha256` mismatches. A stale cache
triggers re-download, and the previous cab is moved to a timestamped
`audit/` subdirectory and retained per the audit-retention window.

#### B.19.14.3 Air-gapped operation

A fully air-gapped host runs the check with no network in one of two
modes: with a committed/copied `data/servicing-dependency-database.json`
present (full check using the cached Layer 2), or by staging a cab
manually and running `-Action RefreshDependencyDatabase`
`-OfflineSyncPackagePath <path>` to parse it to Layer 2. With neither,
P06 has no Layer 2 to read and blocks (run `-Action RefreshDependencyDatabase`, or pass `-UseBaselineOnly`).

#### B.19.14.4 Monthly refresh procedure

```powershell
# 1. Refresh baselines (chains A04 to refresh Layer 2)
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -Mode Monthly
# 2. Review the Layer 2 and Layer 1 diffs
git diff data/servicing-dependency-database.json data/config-Server*.json
# 3. Run the offline gates
python3 tests/servicing_dependency_parser_test.py   # T12
python3 tests/servicing_dependency_layer2_schema_test.py
# 4. Commit Layer 1 and Layer 2 together
git add data/config-Server*.json data/servicing-dependency-database.json
git commit -m "data: monthly servicing-dependency refresh (<yyyy-MM>)"
```

#### B.19.14.5 Current status and future work

In the current revision the servicing-readiness gate is on-by-default
and blocking; `-UseBaselineOnly` is the bypass. Planned future work: a
deeper live-cab schema probe and CI automation for the monthly refresh. Cross-OS `-Execute` validation on real
hardware (Server 2016/2019/2022/2025) is the remaining field-test step
before the default-on flip.

---

## B.20 File organisation and naming conventions

**Status**: normative (r06.0+).

### B.20.1 Directory layout

```
projects/powershell-update-windows-server-iso/
├── Update-WindowsServerIso.ps1     # Main script (§B.19 servicing-dependency facility implemented)
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
│   ├── cache-dynamicupdate-Server2022.json      # Parsed Dynamic Update cache (Server 2022)
│   └── cache-dynamicupdate-Server2025.json      # Parsed Dynamic Update cache (Server 2025)
│   # Planned (r09.0 Step 2+):
│   # └── servicing-dependency-database.json     # Layer 2, ~2-5 MB (per §B.19)
│
├── tests/                            # Python self-verification suite (T1-T13 + gates)
│   ├── README.md                     # Canonical T-numbering and quick-start
│   ├── catalog_probe.py              # T1 (live)
│   ├── catalog_fixture_test.py       # T2 (offline)
│   ├── powershell_harness.py         # T3 (offline; 7 PS assertions)
│   ├── eval_iso_probe.py             # T4 (live)
│   ├── wsusscn2_probe.py             # T5 (live)
│   ├── release_info_parser_test.py   # T6 (offline; 13 assertions)
│   ├── dotnet_cu_parser_test.py      # T7 (offline; 16 assertions)
│   ├── dynamic_update_cache_test.py  # T8 (offline; 20 assertions)
│   ├── catalog_title_tokens_test.py  # T9 (offline; 18 assertions)
│   ├── release_info_resolver_test.py # T10 (offline; 18 assertions)
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
  is encoded into the filename (`cache-dynamicupdate-Server2025.json`, not
  `cache-du/Server2025.json`).
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
| `data/servicing-dependency-database.json` | Tool-generated data | r09.0+, single file |
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

For `RefreshAllBaselines` / `DumpFieldClassification` /
`RefreshDependencyDatabase` (which never run P01), the preflight
DOES run, because these actions touch `data/config-Server*.json`
and the config-presence check is exactly what protects against the
script-relocated-without-data class of misconfiguration.

## B.22 Phase 3 architecture decisions

**Status**: normative (r07.0+). Detailed historical context is
preserved in the per-revision CHANGELOG; this section records only
the **decisions that survived into r09.0** and the rationale a
maintainer needs at the use-site.

### B.22.1 Refresher architecture: release-info as canonical source

The release-info parser
(`Resolve-PatchSetFromReleaseInfo`) is the canonical source for
which KBs were offered on a given Patch Tuesday. The Microsoft Update
Catalogue scrape is retained as a **resolver** for KB ID → UpdateId
→ DownloadUrl, but no longer as the canonical "which KBs?" source.

**Decision**: release-info Markdown is the single source of truth
for KB membership in a baseline; Catalogue is the resolver for the
URL / file metadata of each KB.

**Why**: r06.0 PoC showed the release-info Markdown is parseable,
versioned, and stable. Title-scrape against the Catalogue is fragile
(comma-form drift in 2026-04 dropped Server 2022 to zero results;
see §D.NN).

### B.22.2 Catalog Title token matching: config-driven

`Get-CatalogQueryTemplate` reads OS-specific Title-token arrays
from `data/config-Server*.json` rather than hard-coding them in
.ps1. Multi-form arrays accommodate Microsoft's punctuation drift
(comma vs comma-less).

**Why**: r04.2 dropped Server 2022 to zero results after Microsoft
removed a comma from one OS title; the hard-coded TitleToken did a
`[regex]::Escape` literal match and no longer matched. A
config-driven multi-form array isolates the cosmetic-drift class of
failure to a config file edit, not a code change.

### B.22.3 Data directory: flat with 3-prefix naming

All persistent inputs go under `data/` (not under sub-directories
by Type). Files are distinguished by the §B.20.2 three-prefix rule
(`config-`, `raw-`, `wsusscn2-`). Per-month raw caches live under
`data/raw-<topic>/<yyyy-MM>/`.

**Why**: A single `data/` directory mirrors operator mental model
("the data the script reads"). Type-named sub-directories would
have proliferated as new data classes were added; the flat layout
absorbs the new servicing-dependency-database.json in r09.0 without surprise.

### B.22.4 Schema version: stay at 2.1

`config-Server*.json` Schema field stayed at "2.1" across r07.0 and
r08.0. r09.0's additions (new optional fields per §B.19.12) do not
constitute a breaking change.

**Why**: The new fields are optional and the loader treats absent
fields as `$null`. Forward-compatibility through optional-field
addition is the lighter migration path.

### B.22.5 SSU separation and .NET CU multiplicity

SSU and LCU are separate `NeutralPatches` entries even when shipped
combined; the loader treats them as independently-trackable units.
.NET CU umbrella KBs that bundle multiple `.msu` files keep all
sub-files via §B.15.2 `Select-AllCanonicalPatchFiles`.

**Why**: Independent tracking of SSU and LCU enables P06 servicing-readiness
(§B.19) to surface SSU-prerequisite failures cleanly; without
separation, the prerequisite chain would not be representable in
layer 1.

**Discovery (r11.20+)**: `Resolve-PatchSetFromReleaseInfo` finds the
standalone SSU by a same-month Catalog title search -- for each resolved
LCU it queries the Microsoft Update Catalog for the OS's `<yyyy-MM>
Servicing Stack Update` and keeps the non-preview hit matching
`(?i)servicing stack update`. The search result is itself the
SSU-separate-vs-combined discriminator: 2026-05 returned one SSU for
Server 2016 (KB5088064, Catalog UpdateId
`d0f1761f-c762-4764-8443-8c567f6929a2`) and none for Server 2019 / 2022 /
2025, so the 2016 LCU is emitted with `IsCombined=false` alongside the
SSU while the others stay `IsCombined=true`. The search needs no layer 2
/ `-DataDir` input, so it works on the `RefreshAllBaselines` call path.

### B.22.6 Dynamic Update lookback: 36-month cache

Per-OS Dynamic Update caches under `data/raw-dynamic-update/` keep a
36-month lookback window (~3 years of monthly snapshots). Older
entries are pruned by the next RefreshSnapshots.

**Why**: 36 months covers the longest "operator retains old
baseline" case (legal-hold scenarios); see §B.19.7 scope-filter
rationale.

### B.22.7 Update lifecycle: Patch-Tuesday-triggered, Git-tracked

The §B.14 RefreshAllBaselines decision matrix is triggered by
calendar Patch Tuesday transitions. Resulting `data/config-*.json`
diffs are committed to git and surface as the maintainer's monthly
review unit.

**Why**: A monthly cadence aligns with Microsoft's servicing rhythm;
git tracking gives auditability and rollback at the file boundary.

### B.22.8 `PatchBaseline.NeutralPatches[].Type`: subdivided DotNet

`Type='DotNet'` was subdivided into `DotNet.Runtime`, `DotNet.OsLevel`,
`DotNet.LangPack` in r07.0 Step 1. The OS-level "offering" KB is
recorded for traceability but not applied to any WIM target.

**Why**: The original flat `DotNet` lost the OS-level KB through
the I4.DotNet sub-phase filter. Subdivision keeps the OS-level KB
visible in the baseline for human review while preventing it from
entering the apply lane.

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
`data/config-Server*.json` changed. r09.0 extends this to also
include `data/servicing-dependency-database.json` in the auto-PR.

### B.22.13 Windows ADK auto-install

`-AutoInstallAdk` downloads and silently installs only the
Deployment Tools feature of the Windows ADK (~50–80 MB). The flag
is opt-in to avoid surprise on CI runners.

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
| `$Script:` typo class | §B.22.17 | PSA2013 | §D.NN |
| `Write-PhaseHeader` positional | §B.22.18 | PSA2012 | §D.NN |
| `(if …)` subexpression | §B.22.19 | PSA1004 | §D.NN |
| Idempotent renderers | §B.22.20 | — | §D.NN |
| `List[object]` `@()` failure | §B.18.5 | — | §D.26 |
| DISM mount-cache poisoning | §B.3 (one-WR-per-OS) | — | §D.25 |
| Sampling-vs-comprehensive search | §B.19.5 / §B.19.6 | — | §D.28 |
| Microsoft tool dependency avoidance | §B.19.4 | — | §D.27 |
| Helper function unification | §B.10 | — | §D.30 |

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
| 7 | **Key order**: insertion order preserved (no sort) | Operator-meaningful field ordering (e.g. `KbId` before `Title` in `NeutralPatches`) |
| 8 | **Trailing newline**: exactly one LF at end of file | POSIX convention; `cat`, `git diff`, and most editors expect it |
| 9 | **Null values**: emitted as `"key": null` (no field omission) | Schema explicitness; absence of a key means "field not declared", not "field is null" |
| 10 | **Depth limit**: caller-controlled, default 20 | Prevents accidental infinite recursion; 20 is well above the deepest known schema (currently 6) |

A file that violates any of rules 1–10 is **not** in canonical format,
even if it parses as valid JSON.

### B.23.3 PowerShell reference implementation

Three helpers live in `Update-WindowsServerIso.ps1`, immediately after
the 7-Zip helper block (§B.19.4):

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
(`config-*.json`, `servicing-dependency-database.json`, `cache-*.json`). Internal
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
  (Layer 1 `_DependencyVerified*`, `_VerifiedDate`, etc.);
- the **forbidden legacy `PatchBaseline.Patches` field** (the r10.3 
  defect), via `not.required: [Patches]`;
- **wrong value types** for declared fields.

```bash
python3 tests/config_schema_test.py   # 0 = all configs conform
```

When SPEC B.4 changes, `schema/config.schema.json` MUST be updated 
in the same commit; the two are a matched pair.

### C.3.3 Cross-field consistency

After r09.0 the layer 1 / layer 2 cross-reference (§B.19.12) adds
two consistency checks:

- `PatchBaseline.OfflineSyncPackage.DependencyDatabaseSha256` MUST equal
  the SHA-256 of `data/servicing-dependency-database.json` (when both are
  present).
- Every `NeutralPatches[*].RequiresKbIds` entry MUST be either
  empty or refer to KB IDs present in the same `NeutralPatches[]`
  array (i.e. the dependency must be **in the baseline**, not
  dangling).

`Test-OsConfigConsistency` is the planned implementation; for r09.0
Step 1 the check is manual at PR review per §B.19.14.

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
    -SyntheticTestMode -AutoInstallAdk `
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
3. (r09.0+) The action's A01.0 sub-phase (§B.19.14.1) refreshes
   `data/servicing-dependency-database.json` first.
4. If any `data/config-Server*.json` or
   `data/servicing-dependency-database.json` changed, opens an auto-PR.
5. The PR is restricted via `add-paths` to `data/config-*.json` and
   (r09.0+) `data/servicing-dependency-database.json`.

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
suite of **thirteen numbered tools (T1 through T13)** plus two
unnumbered format / schema gates (the canonical JSON format gate and
the config schema gate). They probe the script's
external dependencies and unit-test its PowerShell functions. They
use only the Python standard library — no `pip install` required.
The canonical T-numbering is maintained in
[`tests/README.md`](./tests/README.md) "Tool inventory"; this section
mirrors that authoritative table.

### C.9.1 Tool inventory (T1 – T13 + format / schema gates)

| Tool | Type | Assertions | Network | Run when |
|:---|:---|:---|:---:|:---|
| **T1** `catalog_probe.py` | Live Microsoft Update Catalog probe (search + per-OS title formats + supersedence panel) | ~7 live checks | Yes | Before/after Catalogue-related code change; monthly CI |
| **T2** `catalog_fixture_test.py` | Offline HTML fixture regression against `fixtures/<patch-month>/` | 13 | No  | Every commit that touches parsers or TitleTokens |
| **T3** `powershell_harness.py` | PS function unit tests via `-Action TestHarness` | **7** | No  | Every commit that touches a PS scrape helper |
| **T4** `eval_iso_probe.py` | Evaluation ISO endpoint check (HTTP Range-GET; 4 OS × 2 lang) | live (4 OS) | Yes | Before release; on Microsoft Evaluation Center snapshot rotation |
| **T5** `wsusscn2_probe.py` | `wsusscn2.cab` freshness check (existence + size + Last-Modified; 60-day warn threshold) | live | Yes | Before RefreshDependencyDatabase; monthly CI |
| **T6** `release_info_parser_test.py` | Offline regression for `ConvertFrom-ReleaseInfoMarkdown` against the PoC fixture | 13 | No | Every commit that touches the release-info parser |
| **T7** `dotnet_cu_parser_test.py` | Offline regression for `ConvertFrom-DotNetCuIndexMarkdown` / `ConvertFrom-DotNetCuMarkdown` against `snapshots/dotnet_cu/` | 16 | No | Every commit touching the .NET CU parsers or the fetch/cache pipeline |
| **T8** `dynamic_update_cache_test.py` | Offline regression for the Dynamic Update 36-month cache subsystem (`Add-/Get-/Remove-DynamicUpdateCacheEntry`); 3 fixture scenarios + 3 defensive cases | 20 | No | Every commit touching the DU cache functions or the 36-month window logic |
| **T9** `catalog_title_tokens_test.py` | Offline regression for `Get-CatalogTitleTokenList` against all four OS configs + `Test-CatalogTitleMatch` through 13 live-captured Catalog title cases | 18 | No | Every commit touching `Common.CatalogTitleTokens` in any OS config, or the narrow-filter helpers |
| **T10** `release_info_resolver_test.py` | Offline regression for `Get-PatchSetFromReleaseInfoDiscovery` (Refresher main-path migration); 4 scenarios + defensive cases | 18 | No | Every commit touching `Resolve-PatchSetFromReleaseInfo`, the discovery helper, or its three caches |
| **T11** `canonical_json_test.py` | Offline byte-level parity test between `ConvertTo-CanonicalJson` / `Save-CanonicalJsonFile` (PowerShell) and `canonical_json_dumps` / `save_canonical_json_file` (Python) per SPEC Part B.23 | 26 | No | Every commit touching the canonical JSON helpers (PS or Python) |
| **T12** `servicing_dependency_parser_test.py` | Offline self-verification of wsusscn2 parser pipeline Stages 3 and 4 against the committed fixture `fixtures/servicing-dependency/package.xml`; structural compare against `expected-output.json` per SPEC §B.19.9.4 | 22 | No | Every commit touching Stage 3 / Stage 4 of the wsusscn2 parser or the scope-filter GUID tables |
| **T13** `servicing_dependency_layer1_test.py` | Offline self-verification of the Layer 1 writeback helper `Update-Layer1DependencyVerification` (Phase 2b2/2b3) per SPEC §B.19.9.5 | 15 | No | Every commit touching `Update-Layer1DependencyVerification`, the OS-category GUID table, or the A04 Layer 1 callout |
| **canonical JSON format gate** `canonical_json_format_check.py` | Offline format-compliance check: re-serialises every `*.json` under `data/`, `tests/fixtures/`, `tests/snapshots/` and fails on byte divergence. Implements SPEC §C.3.4. (No T number; format gate.) | 27 files | No | Every commit that adds or modifies a JSON file in the three scanned directories |
| **config schema gate** `config_schema_test.py` | Offline schema-conformance check: a stdlib-only draft-07-subset validator that checks every `data/config-Server*.json` against `schema/config.schema.json`, with a targeted regression guard against the legacy `Patches` property (r10.4). (No T number; schema gate, mirrors the format-gate convention.) | 14 | No | Every commit touching `data/config-Server*.json` or `schema/config.schema.json` |

**Determinism categories**:

- **Offline-deterministic** (run on every PR): T2, T3, T6, T7, T8, T9, T10, T11, T12, T13, plus the canonical JSON format gate and the config schema gate.
- **Live-network** (monthly CI + ad-hoc): T1, T4, T5.

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

A new tool — provisionally **T11 `servicing_dependency_parser_test.py`** — is
planned for r09.0 Step 2+ to provide offline regression coverage for
the §B.19 Master XML parser (`ConvertFrom-OfflineSyncPackage`,
`New-ServicingDependencyDatabase`). It will assert the parser's emit
shape against committed mini-XML fixtures under
`tests/fixtures/servicing-dependency/`. Implementation tracks the §B.19.7 parser
stability guarantees.

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

**Fix / mitigation**: the r09.0 graph-based check (§B.19) reads
the file-based layer 2 directly, avoiding the COM API entirely.
This is what makes the offline-WIM use case possible.

### D.19 Catalogue Title comma-form drift (Server 2022)

**Symptom**: Server 2022 baseline refresh returned **zero** entries
in 2026-04. Every narrow filter dropped every hit.

**Root cause**: Microsoft removed a comma from the Server 2022
update title:
"...operating system, version 21H2" → "...operating system
version 21H2". The TitleToken was a `[regex]::Escape` literal
match.

**Fix / mitigation**: per §B.22.2, `TitleTokens` is a multi-form
array accommodating both the comma and comma-less variants. The
live `Search.aspx` query strings were updated to the current form.

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
MSU gets its own `NeutralPatches` entry sharing
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
third-party tools for archive extraction**. The §B.19.4 7-Zip
strategy codifies this for the wsusscn2.cab parser. The same
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

**Related**: §B.19.4 (7-Zip dependency strategy); §B.22.16
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

**Related**: §B.19.5.2 cites this lesson explicitly when explaining
why r09.0 limits scope to the Master XML.

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

The §B.19 Servicing Dependency Database is in part the systemic
mitigation: when the failure is "missing prerequisite KB", layer 2
makes the config-side gap detectable before the code-side runtime
failure surfaces.

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
| `Get-SevenZipPath` | Probe 7-Zip in standard install locations | r09.0+, §B.19.4.2 |
| `Get-LatestSevenZipUrl` | Three-tier fallback to obtain MSI download URL | r09.0+, §B.19.4.2 |
| `Install-SevenZipFallback` | Silent MSI install of 7-Zip | r09.0+, §B.19.4.2 |

### E.3 New for `Update-WindowsServerIso.ps1`

| Helper | First shipped | Role |
|:---|:---|:---|
| `Build-PatchPlan` | r03 | Target-aware PatchPlan engine (§B.10) |
| `Resolve-PatchSetFromCatalog` | r03 → rewritten r07.0 Step 2 | Catalogue scrape and supersedence-aware selection |
| `Resolve-PatchSetFromReleaseInfo` | r07.0 Step 2b | Release-info Markdown-driven baseline membership (§B.22.1) |
| `Select-LatestPatchBySupersedence` | r04.2 | Multi-candidate supersedence dedup (§B.12) |
| `Select-AllCanonicalPatchFiles` | r04.3 | Umbrella-KB multi-MSU retention (§B.15.2) |
| `Test-IsCombinedLcuTitle` | r04.3 | LCU+SSU combined detection (§B.15.3) |
| `Get-CatalogQueryTemplate` | r04.3 | OS-specific Title-token template loader (§B.22.2) |
| `Test-PatchServicingReadinessOnMount` | r04 | Mount-time prerequisite check (§B.13); renamed from `Test-PatchDependencyClosureOnMount` in r11.12 |
| `Get-Pca2023ReadinessSnapshot`, `Show-Pca2023ReadinessSnapshot`, `Format-Pca2023ReadinessForReport` | r05.0 | Health verdict for PCA2023 readiness (§B.17) |
| `Convert-WimBootToPca2023Signed` | r05.0 | PSA-clean reimplementation of `Make2023BootableMedia.ps1` (§B.17) |
| `Get-IsoBootCertReadiness` | r05.0 | INPUT-side boot.wim readiness inspection (§B.17.2) |
| `Test-OutputIsoPca2023Readiness` | r08.0 Step 3 | OUTPUT-side ISO 5-target check (§B.18) |
| `Assert-WorkspacePreflight` | r04.3 | Workspace structural readiness (§B.21) |
| `Test-PatchServicingReadinessFromGraph` | r09.0 | Pre-mount servicing-readiness check over Layer 2 (§B.19.10) |
| `ConvertFrom-OfflineSyncPackage` | r09.0 | XmlReader-based Master XML parser (§B.19.7) |
| `New-ServicingDependencyDatabase` | r09.0 | Layer 2 JSON renderer (§B.19.7, §B.19.8) |
| `Invoke-OfflineSyncPackageExtract` | r09.0 | Two-step 7-Zip extract of package.xml (§B.19.6.3) |
| `Get-OfflineSyncPackageIfNeeded` | r05.0 → extended r09.0 | Conditional wsusscn2.cab download with cache invalidation (§B.19.14.2) |

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
| 7-Zip (`ip7z/7zip`) | https://www.7-zip.org/ + https://github.com/ip7z/7zip | The CAB extraction backbone (r09.0+, §B.19.4) |

### F.3 Companion in-house scripts

| Project | Relationship |
|:---|:---|
| `Download-SpeakerDeck.ps1` (sister sub-project under `scripts/powershell/download-speakerdeck-oracle4engineer/`) | Source of the §A inherited common spec body (debug trace, log helpers, env probe, retry primitives). Its SPEC.md is the authoritative copy of the inherited rules. |
| `Deploy-AMDChipsetDriverOnWindowsServer.ps1` | Source of the 7-Zip helper trio (§B.19.4.2 / Appendix E.2) |

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

### G.2 Roadmap (next cycles)

This section deliberately stays short. Per
[`docs/history/r07.0-followups.md`](./docs/history/r07.0-followups.md)
and the per-cycle finding documents, the active follow-up tasks are
tracked there with P0/P1/P2 priority tags. Roadmap-level
forward-looking content lives in those documents, not in this SPEC.

Open at r09.0 inception:

- r09.0 Step 1: Implement the §B.19 Servicing Dependency Database
  (parser, layer 2 schema, P06 Stage 2 wiring, `RefreshDependencyDatabase`
  action). Currently SPEC-only; implementation begins in a subsequent
  session.
- r09.0 Step 2: Wire `-EnableDependencyCheck` opt-in; default OFF.
- r09.0 Step 3: Default-ON for `-EnableDependencyCheck`.
- r09.0 Step 4+: Fleet roll-out (Server 2019 / 2022 / 2025 `-Action
  Build -Execute` with stage 2 verifying). The residual KB5087537
  SSU-prerequisite incident is **resolved on the config side as of
  r11.20**: the standalone Server 2016 SSU (KB5088064) is now
  auto-discovered by `Resolve-PatchSetFromReleaseInfo` (§B.22.5)
  instead of being hand-patched into `config-Server2016.json`. The
  runtime dependency-check fleet roll-out itself remains future work.

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

