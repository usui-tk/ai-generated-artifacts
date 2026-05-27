# Update-WindowsServerIso.ps1 — Developer Specification (SPEC)

> **Status**: r09.0 baseline (rewritten 2026-05-27). This document is the
> authoritative developer / LLM specification for
> `Update-WindowsServerIso.ps1`. It is structured so that an LLM agent
> can be dropped into the project mid-stream without having to re-derive
> the design from the source code.
>
> **Language**: English only, per the repository-wide
> [Language Policy](../../../README.md#language-policy). Bilingual
> entry-point documentation lives in
> [`README.md`](./README.md) / [`README.ja.md`](./README.ja.md).
>
> **Relationship to the repository-level SPEC**: cross-project rules
> (CI workflow design, naming conventions, timeout policy, supply-chain
> security) live in the [repository-level SPEC](../../../SPEC.md). This
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
| SPEC-WSI-033 | Self-verification tool suite (T1–T6) | §C.9 |

---

## Table of Contents

- [Conventions (RFC 2119)](#conventions-rfc-2119)
- [Stable Identifiers](#stable-identifiers)
- [Policy Index](#policy-index-quick-reference-for-ai-agents)
- [**Part A — Inherited Common Specification**](#part-a--inherited-common-specification)
  - [A.1 – A.14 — Inherited verbatim from the sibling SPEC](#a1--a14--inherited-verbatim-from-the-sibling-spec)
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

# Part A — Inherited Common Specification

> **Inheritance declaration**. This Part inherits the
> **Common Specification (reusable across all scripts)** maintained at
> the companion in-house reference:
>
> [`scripts/powershell/download-speakerdeck-oracle4engineer/SPEC.md`](../download-speakerdeck-oracle4engineer/SPEC.md)
> sections **A.1 through A.14**.
>
> Per the repository-wide governance in
> [`scripts/README.md`](../../README.md) "Standard SPEC Structure",
> Part A is the cross-project layer. Restating its text in this file
> would duplicate the canonical source and create drift risk. Readers
> should consult the sibling SPEC for the authoritative text of every
> section listed below.

## A.1 – A.14 — Inherited verbatim from the sibling SPEC

| Section | Title | Scope |
|:-:|---|---|
| A.1 | Reference Assets | `psa.py` canonical location; companion specifications; companion in-house script identification; target-specific folder naming |
| A.2 | Source File Format | UTF-8 BOM, CRLF, ASCII-only outside literals, `.gitattributes` enforcement |
| A.3 | Banner & Version Identification | `$Script:ScriptVersion` / `$Script:ScriptTag` conventions; self-fingerprint via SHA256; banner block layout |
| A.4 | Phase Architecture | numbering rules; phase groups; phase header / footer; Phase Timing Summary |
| A.5 | Logging Conventions | `Write-Step` / `Write-Ok` / `Write-Warn` / `Write-Fail` / `Write-Skip` markers; color discipline; console encoding; TLS hardening |
| A.6 | Path Handling (`-LiteralPath` rules) | wildcard-interpretation hazard; canonical safe-temp pattern; sanitization of derived filenames |
| A.7 | Parameter Conventions | standard switches; mutual exclusion patterns; banner display |
| A.8 | Error & Diagnostic Conventions | three-tier diagnostic output; failure category classification; diagnostic `.txt` dump; JSONL schema |
| A.9 | CSV / JSONL Column Conventions | shared columns across per-phase CSVs; filename pattern; persistent state files |
| A.10 | Environment Evaluation (Phase 1) | PowerShell host check; registry probe; real-world filesystem tests; tier classification |
| A.11 | Static Analysis with `psa.py` | setup; required gate; rule coverage; project-local suppression policy; CI integration |
| A.12 | Documentation Language Policy | file set (README bilingual; SPEC / TESTING / CHANGELOG English-only); README synchronization rule (Lines field match); README.ja.md style; mandatory Disclaimer and License sections (A.12.5) |
| A.13 | Development Workflow | iteration cycle; revision discipline; reuse-before-invention principle |
| A.14 | Debug Trace Facility | three subsystems; module-level state; standard usage pattern; activation order; output format; coexistence with A.8; runtime overhead; common pitfalls |

## A.x — Project-specific extensions

Reserved for any extensions or deviations from the inherited Part A
that are unique to `Update-WindowsServerIso.ps1`. As of this revision
there are **no project-specific extensions**; the inherited contract
is followed verbatim. Project-specific elaboration of Phase architecture
(P01–P13), parameters, error formats, and so on, is recorded in
**Part B** below.

If a future revision needs a project-specific deviation (e.g., a
different console-encoding strategy, an additional logging marker, or
a parameter convention not yet adopted by the sibling), record it as
`A.x.N` here with rationale. The default disposition is to first
propose the change to the sibling SPEC so the convention can be
inherited rather than forked.

### A.x.0 — Rationale and forensic record (inheritance rule)

The Part A inheritance rule above is normative for this SPEC and for
every Layer 3 SPEC in this repository style. The rationale, the
canonical anti-pattern (the bloated 365-line Part A in commit
`c40755c`, which this SPEC corrected in commit `8df9ff4`), and the
LLM-agent operating guidance for preserving the rule are recorded
permanently in the repository-wide [`AGENTS.md` §6 Part A Inheritance
Rule (ABSOLUTE)](../../../AGENTS.md#6-part-a-inheritance-rule-absolute)
and in [`AGENTS.md` §9 Anti-Patterns (AP-1)](../../../AGENTS.md#9-anti-patterns-forensically-documented).
LLM agents extending or revising this SPEC MUST consult both
references before touching Part A.

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
`scripts/powershell/update-windows-server-iso/`. It targets
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
    [Parameter()] [string]$WsusScnCabPath,
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
| `wsusscn2.cab` (offline-scan metadata) | Microsoft CDN | P06 dependency validation, RefreshDependencyDatabase |
| `data/wsusscn2-database.json` (layer 2) | committed in repo | P06 stage 2, when present |

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
  "PatchTuesdayOfBaseline":  "2026-05-13",
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
  "WsusScnCab": {
    "SourceUrl":                "https://catalog.s.download.windowsupdate.com/.../wsusscn2.cab",
    "LocalCachePath":           "Workspace_UpdateWsi/cache/wsusscn2/wsusscn2.cab",
    "LastDownloadedDate":       "2026-05-27T10:25:00+09:00",
    "LastDownloadedSha256":     "...",
    "LastDownloadedSizeBytes":  1073741824,
    "DependencyDatabasePath":   "data/wsusscn2-database.json",
    "DependencyDatabaseSha256": "..."
  }
}
```

Patch `Type` values follow the inventory in §B.15. Field cadence and
who is allowed to mutate each field is the §B.14 decision matrix.

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
| P06 | Plan | ValidatePatchSet: dependency closure check (r09.0: two stages) |
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
P06:  Stage 1: -UseBaselineOnly OR Action ∉ Setup
      Stage 2: -SkipDependencyCheck  (r09.0+, see §B.19)
P07:  -not Common.EnableInstallWimUpdate
P08:  -not Common.EnableBootWimUpdate (per-target sub-checks)
P10:  Critical health OR Pca2023.RequiredByDefault=false OR -DisablePca2023BootManager
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
| `Prepare` | P01-P05 | Stage only (no patching, no DISM mount) |
| `Build` | P01-P02 + P04-P10 | Patch and assemble; presumes Prepare already happened or runs it in-line |
| `Verify` | P01-P02 + P11-P13 | Verify an existing output ISO (presumes a prior Build -Execute produced it) |
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
| `RefreshDependencyDatabase` *(planned, r09.0)* | A04 | (not yet implemented; specified in §B.19.15.3) | Refresh `data/wsusscn2-database.json` (layer 2) from `wsusscn2.cab` (layer 3) |

A04 is **specified but not implemented** in the current revision
(`$Script:ScriptVersion = 'update-wsi-2026.05.27-r08.0'`). It is
listed for forward traceability; the param() ValidateSet does NOT yet
admit it. See §B.19.19 "Rollout and backward compatibility" for the
implementation phasing.

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
- P06 (ValidatePatchSet) is skipped (no real patches to validate).
- P07, P08, P10 are guarded by `if (-not $SyntheticTestMode) { ... }`
  blocks that emit `Write-Skip` lines.
- P11, P12, P13 run on the synthetic output and produce reports.

CI Stage 3 (`...__stage3__synthetic.yml`) exercises this mode end to
end. It MUST NOT upload any artefact containing Microsoft binary
content; this is enforced by the workflow file's explicit
`actions/upload-artifact` `path:` enumeration per the repository
[Artifact Content Minimization](../../../SPEC.md#12-spec-ci-081-artifact-content-minimization)
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

`Test-PatchDependencyClosureOnMount` runs inside the per-WIM apply
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
`Test-PatchDependencyClosureFromGraph` (§B.19.10) runs **before**
the mount in P06 Stage 2, using `Get-WindowsImage` metadata only,
and uses the layer 2 database as its source of truth. The two are
complementary; both stay enabled in r09.0+.

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
(skip-with-warn) or `-DisablePca2023BootManager` is set explicitly.

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

**Status**: normative (specification); implementation status: planned
for r09.0. **Policy ID**: SPEC-WSI-020.

> **Scope of B.19**: this section defines a Microsoft-authoritative,
> offline, file-based dependency-resolution facility built on top of
> the `wsusscn2.cab` package that Microsoft publishes on the Windows
> Update CDN. It supersedes the placeholder dependency-graph claim
> that appeared in earlier roadmap milestones and provides the
> mechanism by which Pre-Patch-Tuesday baselines can be authoritatively
> validated against Microsoft's own metadata before any DISM mount is
> performed.
>
> The contract spans nineteen sub-sections (B.19.1 – B.19.19). It is
> deliberately long because the design choices that produced it are
> non-obvious and have all been validated by physical experiments
> recorded in `docs/history/r09.0-step1-phase5-summary.md`.

### B.19.1 Goals and motivation (informative)

#### B.19.1.1 The anti-pattern this section eliminates

Without `wsusscn2.cab` integration, a missing prerequisite KB (most
commonly a Servicing Stack Update required by a recent Latest
Cumulative Update) is discovered only when DISM `Add-WindowsPackage`
returns `0x800f0823 — CBS_E_NEW_SERVICING_STACK_REQUIRED` from inside
P07. By that point the operator has paid:

1. Full P04 ISO download (~6 GB).
2. Full P05 robocopy expand (~30 s).
3. Full WIM mount (~38 s per index).
4. Several minutes per `Add-WindowsPackage` attempt before CBS
   rejects.

…only to learn that the patch set was incomplete from the start.

The canonical example is **KB5087537** (2026-05 LCU for Server 2016,
OS Build 14393.9140.1.19): it requires servicing-stack version
`v10.0.14393.7692` but install.wim from the Server 2016 GA
evaluation ISO ships with `v10.0.14393.693`. The fix is to apply
**KB5088064** (2026-05 SSU) first. This dependency is **not**
declared anywhere inside the `.msu` file; it lives only in
`wsusscn2.cab`'s embedded `package.xml` under the `<Prerequisites>`
section. The §B.13 mount-time check can detect the missing
prerequisite once a WIM is mounted, but it cannot **predict** it
before the I/O budget is spent.

#### B.19.1.2 What this section adds

A monthly, offline, Microsoft-authoritative dependency-resolution
layer that:

- Tells the operator **before P07 starts** that the configured
  patch set is incomplete, and which KB IDs are missing.
- Auto-populates `RequiresKbIds` / `Supersedes` /
  `RequiresMinimumOsBuild` on each
  `PatchBaseline.NeutralPatches[*]` entry, with provenance recorded
  back to a specific `wsusscn2.cab` SHA-256.
- Keeps working in fully air-gapped environments, given that the
  parsed dependency database is committed to `data/` and travels
  with the repository.

#### B.19.1.3 Cost / benefit assessment

| Cost | Quantum |
|:---|:---|
| Initial `wsusscn2.cab` download | ~600 MB once, ~100–200 MB monthly diff thereafter |
| Workspace cache footprint | ~1.1 GB peak (cab + extracted files) |
| Implementation effort | ~2–3 weeks at the L2c tier (B.19.1.4) |
| Maintainer time per Patch Tuesday | ~10–20 minutes (refresh + commit) |
| Per-user ongoing cost | 0 (uses committed `wsusscn2-database.json`) |

| Benefit | Quantum |
|:---|:---|
| Failure-detection latency | Move from ~10 min (mid-P07) to <5 s (mid-P06) |
| Recovery cost per detection | Drop from ~10 min (P05 re-extract + remount) to 0 |
| Auto-recommendation of missing KBs | None today → fully automated |
| Air-gapped operability | Currently impossible → fully supported |
| Audit trail | DISM logs only → reproducible from a specific `wsusscn2.cab` SHA-256 |

One avoided P07 failure already pays back the maintainer's
month-on-month effort. The r08.0 Step 4 series contains one such
failure (the KB5087537 SSU-prerequisite incident); the break-even
is empirically validated.

#### B.19.1.4 Implementation tier

This section targets the **L2c** tier: self-parse `wsusscn2.cab`'s
embedded `package.xml` (the "Master XML") into a fact-only JSON,
then cross-reference at runtime against the resolved patch set and
the install.wim's static metadata.

Lower tiers (MSU manifest only) miss the SSU-prerequisite class of
failure. Higher tiers (calling the Microsoft `IUpdateSession` COM
API, or full DISM simulation) are not ROI-justified: the COM API
cannot be aimed at a **mounted offline image** (it operates on the
currently-running OS or on `wsusscn2.cab` as a data source), and
full DISM simulation requires mounting the WIM — exactly what this
check is meant to avoid.

### B.19.2 Three-layer architecture (normative)

The dependency facility is structured into three layers with
sharply different governance rules. **Confusing the layers — for
example committing layer 3 to git, or deriving layer 1 directly
from layer 3 at runtime — is a specification violation.**

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer 1: OS-specific dependency attributes                     │
│  Location: data/config-Server{2016,2019,2022,2025}.json          │
│  Git:      committed                                             │
│  Owner:    maintainer-edited, tool-assisted (semi-automatic)     │
│  Contents: per-KB summary embedded in PatchBaseline.             │
│            NeutralPatches[*] — RequiresKbIds, Supersedes,        │
│            RequiresMinimumOsBuild, plus _DependencyVerifiedDate  │
│            and _DependencyVerifiedSource fields                  │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              │ summary derived from
                              │
┌─────────────────────────────────────────────────────────────────┐
│  Layer 2: WSUS-derived aggregated dependency database           │
│  Location: data/wsusscn2-database.json                           │
│  Git:      committed                                             │
│  Owner:    maintainer-only (regular contributors do not touch)   │
│  Contents: facts-only extract from wsusscn2.cab — KB IDs,        │
│            UpdateIds, RevisionIds, package relationships.        │
│            NO Microsoft-authored prose (no KB titles,            │
│            no descriptions). Size target: ~2–5 MB                │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              │ parsed and aggregated from
                              │
┌─────────────────────────────────────────────────────────────────┐
│  Layer 3: Raw wsusscn2.cab                                       │
│  Location: <WorkRoot>/cache/wsusscn2/wsusscn2.cab                │
│  Git:      NOT committed (gitignored)                            │
│  Owner:    each user fetches their own copy                      │
│  Contents: Microsoft-published binary, ~600 MB, monthly cadence │
└─────────────────────────────────────────────────────────────────┘
```

#### B.19.2.1 Why layer 3 is git-excluded

Three independent reasons, any one of which is sufficient on its
own:

1. **Licence**. `wsusscn2.cab` is a verbatim Microsoft binary
   distributed under Microsoft Software Licence Terms. Mirroring it
   on a public GitHub repository constitutes redistribution in a
   form Microsoft has not authorised.
2. **Size**. 600 MB × monthly cadence = ~14 GB of `.git` history
   over a 24-month window. This breaks clone times, GitHub upload
   limits, and contributor onboarding.
3. **Audit-via-hash**. Any judgement made by the dependency
   resolver references the SHA-256 of the `wsusscn2.cab` it
   consumed. That hash is recorded in layer 1 and layer 2. Anyone
   wanting to reproduce the judgement can re-download the exact
   `wsusscn2.cab` from Microsoft using the hash to verify; the
   project does not need to ship the bytes.

#### B.19.2.2 Why layer 2 IS committed

Layer 2 is a structured factual extract — KB IDs, UpdateId GUIDs,
RevisionId numbers, prerequisite relationships, supersedence
relationships. These are facts, not Microsoft's creative
expression, and are outside the scope of the wsusscn2.cab licence.
Committing layer 2 lets the repository:

- Be cloned and used immediately, with no 600 MB download on first
  use.
- Function in fully air-gapped environments — only layer 2 needs
  to travel with the repo.
- Provide a single canonical source of truth that all contributors
  see at the same revision.

The expected layer 2 size after the §B.19.8 text-exclusion rule is
**2–5 MB**, so committing it is feasible. See §B.19.11 for the
size-evolution monitoring rule.

#### B.19.2.3 Why layer 1 contains only a summary

Layer 1 (`config-Server*.json`) is the file operators read, edit,
and review pull requests against. Embedding the full dependency
graph into it would bloat each OS config to tens of MB and obscure
the operator-visible decisions (which KBs to include in this
month's baseline).

The summary embedded into layer 1 is just enough that the
**runtime code path** can answer "does this set of KBs satisfy
their declared prerequisites?" without needing to open layer 2.
Layer 2 exists for the **build-time / refresh-time** code path,
which has to compute the summary in the first place.

### B.19.3 Data source: `wsusscn2.cab` (informative)

#### B.19.3.1 What it is

`wsusscn2.cab` is the offline-scan metadata package Microsoft
publishes for the Windows Update Agent (WUA) COM API method
`IUpdateSession::CreateUpdateSearcher` with
`ServerSelection = ssOthers`. It contains the full applicability
metadata for every update Microsoft has ever shipped for currently-
supported product families.

#### B.19.3.2 CDN source URL (normative)

```
https://catalog.s.download.windowsupdate.com/microsoftupdate/v6/wsusscan/wsusscn2.cab
```

This URL is already present in `config-Server*.json` under
`PatchBaseline.WsusScnCab.SourceUrl` for all four OS families.
B.19 formalises the lifecycle around it.

#### B.19.3.3 Update cadence

Microsoft refreshes `wsusscn2.cab` monthly, typically within 24–48
hours after Patch Tuesday (the second Tuesday of each month). The
refresh policy defined in §B.19.13 aligns to that cadence.

#### B.19.3.4 Cab internal structure (observed, informative)

After CAB expansion, `wsusscn2.cab` contains 75 inner files,
including a single multi-GB index XML — referred to in this section
as the **Master XML** — plus 74 individual `package*.cab` fragments
that contain per-update detailed metadata.

| Inner file | Size (observed 2026-05) | Role |
|:---|:---|:---|
| `package.cab` (outer wrapper) | 14.96 MB | Contains the Master XML |
| `package.xml` (Master XML) | 108.57 MB | Index of all 136,102 updates |
| `package2.cab` … `package74.cab` | 1–34 MB each, ~650 MB total | Per-update fragments with `<Relationships>`, `<ApplicabilityRules>`, etc. |

This section's parser (§B.19.9) consumes the Master XML only.
Individual `package*.cab` fragments are deliberately out of scope
for r09.0 (§B.19.5.2).

### B.19.4 Dependencies: 7-Zip strategy (normative)

#### B.19.4.1 Why 7-Zip

CAB extraction is performed via **7-Zip**, not via the in-box
`expand.exe` or `Shell.Application` COM. The decision is normative
and based on three concrete failures of the in-box tools:

1. **`expand.exe -F:` bug** (Windows 11 build 26100 / PowerShell
   5.1.26100.32860). When extracting a named file from a CAB and
   the destination directory contains a file with the same basename
   as the source CAB, `expand.exe` rejects the operation with
   "Cannot expand a file onto itself" — even though the *target*
   file is differently named. Documented experimentally in Phase 5
   v1 (`docs/history/r09.0-step1-phase5-summary.md`).
2. **`expand.exe -F:filter` selects the wrong file**. In Phase 5
   v2, the same flag was observed to write a CAB into the
   destination under the source CAB's filename instead of the
   filter-named file. Shell.Application via COM was used as a
   fallback in v2; both behaviours are evidence of Microsoft in-box
   tool fragility.
3. **`Microsoft.Deployment.Compression.Cab.dll`** (the .NET
   wrapper used by `kbupdate-library`) requires a fully-qualified
   destination path and is not bundled with PowerShell. Adding the
   dependency to this script would expand its install surface.

7-Zip has been continuously maintained since 2000 by an independent
maintainer (Igor Pavlov, then `ip7z` org). It is downloadable as a
standalone MSI from `https://www.7-zip.org/` and from
`https://github.com/ip7z/7zip/releases`. It is also distributable
via `winget install 7zip.7zip`.

This decision aligns with a project-wide convention recorded in
§D.27 (Microsoft OS tool dependency avoidance).

#### B.19.4.2 7-Zip discovery and bootstrap

Three helper functions cooperate. They are ported verbatim from the
sister project `Deploy-AMDChipsetDriverOnWindowsServer.ps1` (which
established this pattern; see Appendix F):

| Function | Role |
|:---|:---|
| `Get-SevenZipPath` | Probe `%ProgramFiles%\7-Zip\7z.exe`, `%ProgramFiles(x86)%\7-Zip\7z.exe`, then `7z.exe` on `PATH`. Return path or `$null`. |
| `Get-LatestSevenZipUrl` | Three-tier fallback: (1) scrape `https://www.7-zip.org/download.html`; (2) GitHub Releases API for `ip7z/7zip`; (3) pinned URL `https://github.com/ip7z/7zip/releases/download/26.01/7z2601-x64.msi`. Returns `{Version, MsiUrl, Source}`. |
| `Install-SevenZipFallback` | Download the MSI and run `msiexec.exe /i <msi> /qn /norestart`. Throws on non-zero exit. |

The functions are wired into a single discovery flow: `Get-SevenZipPath`
first; if `$null`, run `Install-SevenZipFallback` and retry once.

#### B.19.4.3 7-Zip invocation pattern (normative)

```powershell
& $sevenZip x $archive ('-o' + $dest) -y -bsp0 -bso0
# Exit codes: 0=ok, 1=warning (non-fatal), >=2=fatal
```

- `x` (lowercase) preserves the original path inside the archive.
- The `-o<dir>` form requires no space between flag and value; using
  `('-o' + $dest)` keeps the call free of injection edge cases.
- `-y` answers all prompts with Yes (necessary for non-interactive
  runs).
- `-bsp0 -bso0` suppress progress and standard output so the call
  site can capture stderr cleanly.

The exit-code mapping (0/1/>=2) matches the official 7-Zip
documentation. Treat exit 1 as a warning (e.g. file timestamp
collision), exit ≥2 as fatal.

#### B.19.4.4 Implementation notes (port from Deploy-AMDChipsetDriverOnWindowsServer.ps1)

The three helpers `Get-SevenZipPath`, `Get-LatestSevenZipUrl`, and
`Install-SevenZipFallback` are ported verbatim from the sister
project, with two unavoidable adjustments:

| Aspect | Deploy-AMD source | This script | Reason |
|:---|:---|:---|:---|
| Yellow-warning logger | `Write-Caution` | `Write-Warn` | The two scripts have independently-grown logger naming. The role and ANSI colour are identical. |
| Informational logger | `Write-Detail` | `Write-Step` | Same as above. |
| HTTP wrapper | raw `Invoke-WebRequest` | raw `Invoke-WebRequest` (unchanged) | This script's local `Invoke-WebRequestWithRetry` wrapper has different retry semantics (exponential backoff, multi-attempt) than the three-tier short-circuit fallback Deploy-AMD uses. Aligning them is deferred to a future revision. |

These adjustments are minimum-viable for the port to compile and
run in this script's environment. They are explicitly *not* a
"redesign while porting" — function bodies, parameter signatures,
and pipeline ordering remain byte-identical to Deploy-AMD modulo
the four lines that invoke the renamed loggers.

The three helpers are inserted as a single block immediately after
`Get-WsusScnCabIfNeeded` (the Stage 1 cab acquisition helper).
The placement keeps all `wsusscn2.cab`-adjacent infrastructure
co-located within a single section of the script body.

### B.19.5 Data sources: dual-source structure (informative)

Phase 5 of the r09.0 Step 1 PoC established that update-relationship
metadata is split across two distinct file populations inside
`wsusscn2.cab`. Both are needed for a complete dependency graph in
principle, but only the Master XML is needed for the §B.19.1.1 use
case.

#### B.19.5.1 The dual-source table

| Information | Master XML | Individual `package*.cab` |
|:---|:---:|:---:|
| `<Prerequisites>` (flat GUIDs) | ✓ summary form | ✓ detailed form with `<AtLeastOne>` |
| `<SupersededUpdates>` (forward direction) | ✗ | ✓ |
| `<SupersededBy>` (inverse direction) | ✓ (14,059 occurrences) | ✗ |
| `<BundledUpdates>` (children) | ✗ | ✓ |
| `<BundledBy>` (parent) | ✓ | ✗ |
| `<PayloadFiles>` & `<FileLocations>` | ✓ | ✗ |
| `<KBArticleID>` element | ✗ | ✓ (inside `<Metadata>`) |
| `<Categories>` (OS family GUID) | ✓ | ✗ |
| `<ApplicabilityRules>` | ✗ | ✓ |

The KB ID itself is **never** present as a dedicated element or
attribute in the Master XML. It is embedded in
`<FileLocation Url="…">` URLs in the form
`windows10.0-kb<digits>-<arch>_<hash>.cab` and extracted via the
regex `kb(\d+)` (case-insensitive). This was confirmed by
exhaustive case-insensitive search of the 108.57 MB Master XML for
`<KBArticleID`, `KBArticleID=`, and the literal `kb5087537` /
`kb5088064` strings; the only hits were inside `<FileLocation Url=…>`.

#### B.19.5.2 Why r09.0 uses Master XML only

The 0x800f0823 problem requires only `<Prerequisites>` and
(optionally) `<SupersededBy>`, both of which the Master XML
provides directly. Parsing the 74 individual `package*.cab`
fragments would yield richer information (the `<AtLeastOne>`
disjunctive form of prerequisites, full forward-direction
supersedence, the `<KBArticleID>` element inside `<Metadata>`,
applicability rules) but the cost is prohibitive:

| Resource | Per-cab cost (observed, package30.cab as exemplar) | All-74 estimate |
|:---|:---:|:---:|
| Time | 6.7 s extract + 127.9 s scan | ~2.5 hours |
| Disk peak | 214 MB extracted | 15–20 GB |
| Files | 12,500 per cab | ~800,000 total |

For the §B.19.1.1 use case (catch SSU-prereq misconfiguration
before P07), the Master XML's information is sufficient. The
richer per-cab parse is reserved for a future revision (r10.x or
later) and is explicitly **out of scope for r09.0**. The
out-of-scope items are enumerated in §B.19.5.3.

#### B.19.5.3 Out of scope for r09.0 (kept here for traceability)

The following are deliberately not implemented in r09.0:

| Item | Reason for deferral |
|:---|:---|
| `<SupersededUpdates>` forward direction | Requires per-cab parse; not needed for 0x800f0823 detection |
| `<Prerequisites>` detailed form (`<AtLeastOne>`) | Same |
| `<ApplicabilityRules>` (`<IsInstallable>` evaluator) | Same; also requires implementing a small expression evaluator |
| Category GUID → product family name mapping | Same; r09.0 stores raw GUIDs and resolves at use-site |
| Element-level `<KBArticleID>` from `<Metadata>` | Master XML's URL-based extraction is sufficient |

### B.19.6 Master XML schema as observed (informative)

Phase 5 v3 / v4 of the PoC captured complete `OuterXml` dumps of
representative `<Update>` elements. The schema is **not publicly
documented by Microsoft**, but it has been stable for over a decade
(verified by the parser implementations in `OSDBuilder`,
`PSWindowsUpdate`, and `kbupdate-library`, all of which agree on
the shapes below).

#### B.19.6.1 File-level shape

```xml
<?xml version="1.0" encoding="utf-8"?>
<OfflineSyncPackage xmlns="http://schemas.microsoft.com/msus/2004/02/OfflineSync"
                    SourceId="..." PackageId="..." PackageVersion="1.1"
                    ProtocolVersion="1.0" CreationDate="2026-05-12T08:51:08Z"
                    MinimumClientVersion="5.8.0.2678">
  <Updates>
    <Update ... />
    <!-- 136,102 occurrences, mixed Bundle / Standalone -->
  </Updates>
  <FileLocations>
    <FileLocation Id="..." Url="..." />
    <!-- 97,051 occurrences -->
  </FileLocations>
</OfflineSyncPackage>
```

#### B.19.6.2 Bundle `<Update>` (e.g. an LCU offered to WSUS)

```xml
<Update CreationDate="2025-05-12T20:45:23Z"
        DefaultLanguage="en"
        UpdateId="631fdcea-ff50-4993-bf5c-27c5ce211c9a"
        RevisionNumber="201"
        RevisionId="43268251"
        IsLeaf="true"
        IsBundle="true">
  <Prerequisites>
    <UpdateId Id="13c46d99-e6e6-4b68-b83d-33d73910d025" />
    <UpdateId Id="8622846b-ec83-489b-af09-6545433c942e" />
    <!-- … typically 5–10 entries … -->
  </Prerequisites>
  <Categories>
    <Category Type="UpdateClassification" Id="0fa1201d-4330-4fa8-8ae9-b877473b6441" />
    <Category Type="Company"              Id="56309036-4c77-4dd9-951a-99ee9c246a94" />
    <Category Type="ProductFamily"        Id="6964aab4-c5b5-43bd-a17d-ffb4346a8e1d" />
    <Category Type="Product"              Id="ba0ae9cc-5f01-40b4-ac3f-50192b5d6aaf" />
  </Categories>
</Update>
```

#### B.19.6.3 Standalone `<Update>` (per-arch `.cab` payload)

```xml
<Update CreationDate="2017-06-27T01:53:00Z"
        DefaultLanguage="en"
        UpdateId="f87dda5a-3bc0-47a1-9a13-63dd15c7b06b"
        RevisionNumber="202"
        RevisionId="21221682"
        IsLeaf="true"
        DeploymentAction="Bundle">
  <PayloadFiles>
    <File Id="bl63nhPgDOgxEUi4i9v+eHBtXXA=" />   <!-- @Id only; no @FileName -->
  </PayloadFiles>
  <Prerequisites>
    <UpdateId Id="23b28b6a-2629-424b-92ae-1b0bda447d2f" />
  </Prerequisites>
  <BundledBy>
    <Revision Id="21221683" />   <!-- back-link to the Bundle parent -->
  </BundledBy>
</Update>
```

#### B.19.6.4 `<SupersededBy>` (when present; ~10.3% of `<Update>`s)

```xml
<Update ... RevisionId="43239444" IsLeaf="true" IsBundle="true">
  <Prerequisites>...</Prerequisites>
  <SupersededBy>
    <Revision Id="44174230" />
    <Revision Id="43527426" />
    <Revision Id="44008739" />
    <Revision Id="44337998" />
  </SupersededBy>
  <Categories>...</Categories>
</Update>
```

Important characteristics:

- The reference form is `<Revision Id="<integer>" />`, **not**
  `<UpdateId Id="<GUID>" />`. The integer is the `RevisionId`
  attribute of the target `<Update>`, which is also unique within
  the Master XML.
- The direction is **inverse only**: "this Update has been replaced
  by X". The forward form "this Update replaced Y" lives in the
  individual `package*.cab` fragments, not the Master XML.

Phase 5 v4 confirmed by exhaustive case-insensitive string search
that the Master XML contains **14,059 `<SupersededBy>` occurrences**
(roughly 10.3 % of all `<Update>` entries). It contains **0**
occurrences of `<SupersededUpdates>`, `<Supersedes>`, `<Replaces>`,
or any of the other plausible variant tags.

### B.19.7 Scope filter (normative)

The parser ingests `package.xml` and emits to
`wsusscn2-database.json` only entries matching **all** of:

1. **OS family**: package targets one of Windows Server 2016, 2019,
   2022, or 2025 (matched via the `<Categories>` block's
   `Product` / `ProductFamily` GUIDs; the working set lives in
   `$Script:WsusScnOsCategoryGuids`).
2. **Update type**: SSU, LCU, .NET CU, or Dynamic Update. Client
   SKUs (Windows 10 / 11 consumer), Office, Defender, drivers,
   and Features-On-Demand are excluded.
3. **Recency**: released within the last **24 months** as of the
   parser invocation date. The `CreationDate` attribute of the
   `<Update>` element is the cut-off. Older entries are pruned to
   bound layer 2 size. The 24-month window is justified by the
   longest realistic "old baseline still in use" case: operators
   occasionally retain a baseline for legal-hold purposes that
   long.

### B.19.8 Microsoft-prose exclusion rule (normative)

This is a **hard rule, not a target**. Layer 2 (the
`wsusscn2-database.json` that ships in the public git repo)
**MUST NOT** contain any of:

- KB titles (e.g. _"2026-05 Cumulative Update for Windows Server
  2016 …"_).
- KB descriptions, severity prose, or release-notes excerpts.
- Any human-readable text authored by Microsoft.

It **MAY** contain:

- KB IDs (e.g. `"5087537"` — numeric form, no `KB` prefix; see
  §B.19.10.2 for the key convention).
- UpdateId GUIDs and RevisionId integers.
- Architecture identifiers (`"x64"`, `"x86"`, `"arm64"`).
- Release dates as ISO-8601 strings.
- Prerequisite / supersedence / applicability **relationships**
  between KB IDs and RevisionIds.
- Product family GUIDs.
- The SHA-256 of the source `wsusscn2.cab` (as a provenance
  anchor).

The rationale combines two distinct concerns:

1. **Licence posture**. Facts are not the licensed creative
   expression. Stripping the prose keeps the legal posture clean.
2. **Size control**. The Microsoft-authored title and description
   strings would, by themselves, balloon layer 2 from the ~2–5 MB
   target to 50–100 MB. Stripping them is independently necessary
   for size containment per §B.19.11.

Enforcement: the parser MUST whitelist every field it emits. A
post-parse sanity grep that the committed JSON contains no
"Cumulative Update" / "Servicing Stack" / "Security Update" /
"applies to" / similar phrases is part of the §B.19.18 PR review
checklist.

### B.19.9 Parser pipeline (normative)

The parser is a four-stage pipeline. Each stage has a clearly
defined input and output so failures can be diagnosed by inspecting
the boundary artefact.

```
Stage 1: Acquire wsusscn2.cab
  Input  : configured CDN URL + cache freshness state
  Output : <WorkRoot>/cache/wsusscn2/wsusscn2.cab + .meta.json
  Helper : Get-WsusScnCabIfNeeded (existing)

Stage 2: Extract package.xml from the cab
  Input  : <WorkRoot>/cache/wsusscn2/wsusscn2.cab
  Output : <WorkRoot>/cache/wsusscn2/package.xml (~108 MB)
  Helper : Invoke-WsusScnPackageXmlExtract (new, two-step 7-Zip)

Stage 3: Stream-parse the Master XML into structured form
  Input  : <WorkRoot>/cache/wsusscn2/package.xml
  Output : in-memory hashtable of packages (~10,000 entries post-filter)
  Helper : ConvertFrom-WsusScnPackageXml (new, XmlReader-based)

Stage 4: Render the hashtable to layer 2 JSON
  Input  : in-memory hashtable + _meta provenance
  Output : data/wsusscn2-database.json
  Helper : New-WsusScnDependencyDatabase (new)
```

#### B.19.9.1 Stage 2 details

The cab contains the Master XML wrapped one level deep: the outer
`wsusscn2.cab` contains an inner `package.cab` (~15 MB), which in
turn contains `package.xml`. A single `7z x` invocation extracts
all 75 inner files, but for performance we extract only the two
needed:

```powershell
& $sevenZip x $cab    ('-o' + $stage1) -ir!package.cab -y -bsp0 -bso0
& $sevenZip x $innerCab ('-o' + $stage2) -ir!package.xml -y -bsp0 -bso0
```

`-ir!<file>` selects by inclusive regex on the basename. Stage
separation (stage1 ≠ stage2 directory) avoids the `expand.exe`
self-overwrite class of failure documented in §B.19.4.1.

#### B.19.9.2 Stage 3 details — XmlReader streaming

The Master XML at 108.57 MB cannot be loaded as
`[xml]` / `XmlDocument` in low-memory CI environments. Phase 5 v3
measured **peak memory +536 MB** when using
`XmlDocument.Load($path)` on this file. `XmlReader` streaming
keeps peak working set under 50 MB.

The parser performs a two-pass walk:

- **Pass 1**: visit every `<Update>`. For each, decide whether the
  scope filter (§B.19.7) admits it. If admitted, record:
  - `UpdateId` (GUID), `RevisionId` (integer), `RevisionNumber`
  - `IsBundle`, `IsLeaf`, `DeploymentAction`
  - `Prerequisites/UpdateId` (collect into `Requires`)
  - `SupersededBy/Revision` (collect into `SupersededByRevisions`)
  - `BundledBy/Revision` (collect into `BundledIn`)
  - `Categories/Category` (collect into a hashtable keyed by Type)
  - `PayloadFiles/File@Id` (collect for the second pass)
  Build the `RevisionIndex` table (`RevisionId → UpdateId`) along
  the way.
- **Pass 2**: visit every `<FileLocation>`. For each:
  - Extract the file-id (the `Id` attribute, matching the
    `PayloadFile/File@Id` recorded in pass 1).
  - Extract `kb(\d+)` from the `Url` attribute (case-insensitive).
  - Extract architecture token from the URL filename pattern.
  - Resolve back to the owning `<Update>` via the file-id index
    built in pass 1 and attach `KbId`, `Arch`, and `Url` to the
    correct `Variant`.

Pass 2 is necessary because the KB number lives in the
`<FileLocation>` URL, not on the `<Update>` itself, and several
`<Update>` rows (different architectures of the same KB) share the
same KB number. The parser groups by KB number at the end of pass 2
to form the `Variants[]` array.

#### B.19.9.3 Stage 4 details

Stage 4 walks the in-memory hashtable, applies the whitelist from
§B.19.8, and emits the JSON with `-Depth 10` so nested arrays
render correctly. The `_meta` block (B.19.10.1) is computed
separately from script-scope state and inserted at the top of the
file.

### B.19.10 Layer 2 JSON schema (normative)

This is the canonical shape of `data/wsusscn2-database.json`. The
schema is **versioned** via `_meta.ParserVersion`. The parser MUST
refuse to consume a JSON file whose `ParserVersion` is newer than
its own; older versions MAY be consumed with a one-time warning.

#### B.19.10.1 Top-level structure

```jsonc
{
  "_meta": {
    "GeneratedAt": "2026-05-27T10:30:00+09:00",
    "GeneratedBy": "RefreshAllBaselines:r09.0",
    "ParserVersion": "1.0",
    "WsusScnCab": {
      "SourceUrl":              "https://catalog.s.download.windowsupdate.com/.../wsusscn2.cab",
      "FetchedAt":              "2026-05-27T10:25:00+09:00",
      "LastModifiedHeader":     "Tue, 12 May 2026 14:00:00 GMT",
      "SizeBytes":              612345678,
      "Sha256":                 "abc123def456..."
    },
    "Scope": {
      "OsFamilies":   ["WindowsServer2016","WindowsServer2019","WindowsServer2022","WindowsServer2025"],
      "UpdateTypes":  ["SSU","LCU","DotNetCU","DynamicUpdate"],
      "WindowMonths": 24
    },
    "Counts": {
      "TotalPackages": 0,
      "ByOsFamily":  { "WindowsServer2016": 0, "WindowsServer2019": 0,
                       "WindowsServer2022": 0, "WindowsServer2025": 0 }
    }
  },
  "Packages": { /* see B.19.10.2 */ },
  "RevisionIndex": { /* see B.19.10.3 */ }
}
```

#### B.19.10.2 `Packages` — keyed by KB ID (numeric)

```jsonc
"Packages": {
  "5087537": {
    "Variants": [
      {
        "Arch":                  "x64",
        "UpdateId":              "631fdcea-ff50-4993-bf5c-27c5ce211c9a",
        "RevisionId":            43268251,
        "RevisionNumber":        201,
        "Url":                   "http://download.windowsupdate.com/.../windows10.0-kb5087537-x64.cab",
        "Requires":              ["5088064"],
        "RequiresRevisions":     [43268250],
        "SupersededByRevisions": [44174230, 43527426, 44008739, 44337998],
        "BundledIn":             21221683,
        "Categories": {
          "UpdateClassification": "0fa1201d-4330-4fa8-8ae9-b877473b6441",
          "Product":              "ba0ae9cc-5f01-40b4-ac3f-50192b5d6aaf"
        },
        "IsBundle":              false,
        "IsLeaf":                true
      },
      {
        "Arch":                  "x86",
        "UpdateId":              "...",
        "RevisionId":            43268252,
        "...":                   "..."
      }
    ]
  },
  "5088064": {
    "Variants": [ /* SSU entry for the same month */ ]
  }
}
```

Key convention: **numeric KB ID without the `KB` prefix**, as a
JSON string (so e.g. KB5087537 keys as `"5087537"`). This matches
how KB IDs appear in the `<FileLocation>` URLs (lower-case `kb`
followed by digits) and avoids the case-insensitivity ambiguity
that string-keyed JSON would otherwise introduce.

#### B.19.10.3 `RevisionIndex` — RevisionId → UpdateId GUID

```jsonc
"RevisionIndex": {
  "43268251": "631fdcea-ff50-4993-bf5c-27c5ce211c9a",
  "44174230": "<guid of the successor Update>",
  /* … */
}
```

Why this exists: `<SupersededBy>` references its targets by
`RevisionId` (integer), not by `UpdateId` (GUID). The runtime
resolver, given a `SupersededByRevisions: [44174230]` array,
needs to translate each RevisionId back to a KB ID. The
`RevisionIndex` provides the first hop (RevisionId → UpdateId);
the resolver then scans `Packages` to find which KB owns that
UpdateId.

A naive design without `RevisionIndex` would require scanning
all `Variants[]` of all `Packages[]` to resolve a single
`SupersededByRevisions` entry — quadratic in the number of
variants. The index is small (~10,000 entries × 50 bytes ≈
500 KB) and makes the lookup O(1) per supersedence edge.

#### B.19.10.4 Field semantics

| Field | Meaning |
|:---|:---|
| `Variants` | Per-architecture realisations of the same KB. Most KBs have one or two; the .NET umbrella KBs may have 4+. |
| `Requires` | KB IDs that MUST already be installed before this Variant can apply. Maps to `wsusscn2`'s `<Prerequisites>` after resolving each prereq's `UpdateId` to a KB ID via the file-location pass. |
| `RequiresRevisions` | The raw `<Prerequisites><UpdateId>` GUIDs from the Master XML. Kept alongside `Requires` for audit and for cases where the prereq is a category GUID rather than a KB. |
| `SupersededByRevisions` | RevisionId integers from `<SupersededBy><Revision>`. Use `RevisionIndex` to resolve to UpdateId, then `Packages` to resolve to KB. |
| `BundledIn` | The RevisionId of the Bundle that contains this Standalone. From `<BundledBy><Revision>`. |
| `Categories` | Per-Type GUID values from `<Categories>`. The GUID values resolve to OS-family / product names through `$Script:WsusScnCategoryGuidNameMap`. |
| `IsBundle`, `IsLeaf` | Direct copies of the `<Update>` attributes; used by §B.19.13.3 verification. |

The `IsCombined` flag from earlier B.4 schema is **not** stored in
layer 2; it is a derived attribute computed by
`Test-IsCombinedLcuTitle` against the Catalogue Title (§B.15.3),
which is not available in layer 2 by §B.19.8.

---

### B.19.11 Performance targets and measured values (informative)

| Metric | Phase 5 measured (PoC) | Target for r09.0 production | Action on regression |
|:---|:---:|:---:|:---|
| Stage 1 (cab download, cold) | 30–90 s | < 180 s | Inspect CDN reachability |
| Stage 2 (7-Zip extract, single core) | 6–8 s | < 15 s | Check workspace disk IOPS |
| Stage 3 (XmlReader parse, single core) | 8–12 s | < 30 s | Profile with `Measure-Command` |
| Stage 4 (JSON render + write) | < 1 s | < 3 s | — |
| **Total wall clock (warm cache)** | **~10 s** | **< 60 s** | Investigate per-stage |
| Peak working set (Stage 3 path) | < 50 MB | < 100 MB | Verify XmlReader streaming, not `[xml]` |
| Peak workspace disk use | 1.1 GB | < 2 GB | Audit retained intermediate files |
| Layer 2 JSON size | 2.6 MB (post-filter) | 2–5 MB | If > 5 MB, audit emitted fields against §B.19.8 |

`Microsoft.Update.Session` COM API (the WUA scanner that drives
`wsusscn2.cab` for online detection) is approximately **8–12 minutes**
on the same hardware. The file-based parser is therefore ~50–100× faster
because it does not perform per-update applicability evaluation.

If layer 2 JSON size crosses **8 MB**, the parser MUST emit a warning
at refresh time and the maintainer MUST audit the diff to confirm no
prose fields slipped through. A 10 MB hard ceiling is enforced by
`RefreshAllBaselines`: if the new layer 2 would exceed it, the write
is refused and a diff report is emitted to `<WorkRoot>/diag/`.

### B.19.12 Layer 1 (`config-Server*.json`) integration (normative)

#### B.19.12.1 New fields on `PatchBaseline.NeutralPatches[*]`

The §B.4.3 entries gain three optional fields, populated by
RefreshAllBaselines from the layer 2 summary:

| Field | Type | Source |
|:---|:---|:---|
| `RequiresKbIds` | string[] | Layer 2 `Packages[<this KB>].Variants[<x64>].Requires` |
| `Supersedes` | string[] | (existing, from Catalogue scrape) |
| `RequiresMinimumOsBuild` | string | Computed from Layer 2 prereq chain |
| `_DependencyVerifiedDate` | ISO-8601 | Set by RefreshAllBaselines |
| `_DependencyVerifiedSource` | string | `wsusscn2.cab@sha256:<hash>` |

`RequiresKbIds` was previously present as a manual-entry field; it
becomes auto-populated and the manual-entry path is reserved for
emergencies (with `_DependencyVerifiedBy: "manual:<reason>"`).

`RequiresMinimumOsBuild` is a new field. It is computed by walking
the layer 2 `Requires` chain (typically just the immediate SSU
prerequisite) and recording the OS build number that the SSU's KB
delivers. The build number itself comes from the Catalogue scrape
(`Title` parsing), not from layer 2 — layer 2 contains relationships,
not build numbers (which would be Microsoft prose per §B.19.8).

#### B.19.12.2 New fields on `PatchBaseline.WsusScnCab`

The §B.4.3 `WsusScnCab` block gains two additional fields:

| Field | Type | Source |
|:---|:---|:---|
| `DependencyDatabasePath` | string | Always `"data/wsusscn2-database.json"` |
| `DependencyDatabaseSha256` | string | SHA-256 of the layer 2 file recorded into layer 1 |

`DependencyDatabaseSha256` lets P06 verify that the layer 2 file on
disk has not been tampered with since the last RefreshAllBaselines.
A mismatch downgrades P06 Stage 2 to a warning (B.19.14.4).

#### B.19.12.3 Automation level: semi-automatic (normative)

The Layer 1 ↔ Layer 2 cross-reference is **semi-automatic**:

- **Automatic on write**: `RefreshAllBaselines` (A01) and
  `RefreshDependencyDatabase` (A04) populate the new fields without
  operator input.
- **Manual at review time**: any PR that proposes a change to layer
  1's `RequiresKbIds` or `RequiresMinimumOsBuild` MUST include the
  corresponding layer 2 change in the same commit. The `_*` fields
  serve as a paper trail for the reviewer.

The semi-automatic stance is intentional. A fully automatic system
(layer 2 read at every Build invocation) would couple every operator
run to network reachability; a fully manual system (operator fills
in `RequiresKbIds` by hand) was the r07.0 state and is what caused
the r08.0 Step 4 KB5087537 SSU-prerequisite incident.

### B.19.13 Verification API (normative)

#### B.19.13.1 `Test-PatchDependencyClosureFromGraph`

Signature:

```powershell
function Test-PatchDependencyClosureFromGraph {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [pscustomobject[]] $ResolvedPatches,
        [Parameter(Mandatory)] [pscustomobject]   $WimMountState,
        [Parameter()]          [string]           $DatabasePath = "$PSScriptRoot/data/wsusscn2-database.json",
        [Parameter()]          [hashtable]        $PolicyOverride
    )
}
```

Returns:

```
@{
    Available           = $true | $false   # was layer 2 readable?
    OverallStatus       = 'Pass' | 'Warning' | 'Fail' | 'Unknown'
    DatabaseSha256      = '<hex>'
    DatabaseGeneratedAt = '<iso-8601>'
    PatchVerdicts       = @(
        @{
            KbId           = 'KB5087537'
            UpdateId       = '...'
            Verdict        = 'Pass' | 'MissingPrereq' | 'NotInDatabase' | 'Skipped'
            Requires       = @('KB5088064')
            MissingFromSet = @('KB5088064')
            ResolvedFrom   = 'graph' | 'manual' | 'wim'
            Notes          = '...'
        }, ...
    )
    Reasons             = @('...')
}
```

The function MUST NOT mount the WIM. It consumes the **static**
WIM metadata (build number, installed packages list) captured by
`Get-WindowsImage` and provided via the `$WimMountState` parameter.

#### B.19.13.2 Relationship to `Test-PatchDependencyClosureOnMount` (§B.13)

Both functions stay enabled in r09.0+. They are complementary:

| Aspect | `…FromGraph` (NEW) | `…OnMount` (EXISTING, §B.13) |
|:---|:---|:---|
| Runs at | P06 Stage 2 (before mount) | Inside P07 / P08 (after mount) |
| Cost | < 5 s | Per `Get-WindowsPackage` call, ~10–20 s |
| Source of truth | Layer 2 (wsusscn2-derived) + static WIM metadata | Live `Get-WindowsPackage` against mounted WIM |
| Detects | Configured-set incompleteness (declarative) | Runtime installed-set drift (empirical) |
| Failure latency | < 5 s from P06 start | Mid-P07, after WIM mount |

The graph-based check is the **predictive** layer; the mount-based
check is the **runtime safety net**. Removing the mount-based check
in a future revision is conceivable only after layer 2 has proven
its accuracy across multiple OS / patch combinations.

#### B.19.13.3 `WimMountState` capture (informative)

`Get-Pca2023ReadinessSnapshot` already captures install.wim metadata
via `Get-WindowsImage -ImagePath ... -Index <N>`. The same call
returns `Version` (the post-LCU build number reported by the WIM
header), `InstalledPackages` (via `Get-WindowsPackage -Path
<mount>`), and edition names. The new caller path bypasses the
mount by reading `Version` directly from `Get-WindowsImage`'s
returned object — which works without mounting — and treats
`InstalledPackages` as empty when the WIM is unmounted.

This is sufficient because the empty `InstalledPackages` case
collapses the `OnMount` check's value to zero, leaving the graph
check (which doesn't need installed-packages knowledge) as the
sole judge at P06 time.

### B.19.14 P06 ValidatePatchSet integration (normative)

#### B.19.14.1 Phase-skip condition redesign

The existing P06 skip condition is `-UseBaselineOnly`. r09.0 splits
P06 into two stages with independent skip conditions:

```
P06 ValidatePatchSet
├── Stage 1: Catalog freshness comparison (existing)
│   Skip if : -UseBaselineOnly
└── Stage 2: Dependency closure check (NEW, r09.0+)
    Skip if : -SkipDependencyCheck OR layer 2 unavailable AND -OfflineCabPath not given
```

Stage 1 and Stage 2 are independent: stage 1 may skip while stage 2
runs (the typical air-gapped case), and vice versa.

#### B.19.14.2 Stage 2 algorithm

```
1. Try to load layer 2 from data/wsusscn2-database.json
   - If absent and -OfflineCabPath given: invoke RefreshDependencyDatabase synchronously
   - If absent and online: download wsusscn2.cab, parse, write layer 2
   - If absent and air-gapped: skip stage 2 with warning, set OverallStatus=Unknown
2. Verify layer 2's _meta.WsusScnCab.Sha256 matches
   PatchBaseline.WsusScnCab.DependencyDatabaseSha256 (if recorded)
   - On mismatch: emit warning, continue
3. Call Test-PatchDependencyClosureFromGraph with $ResolvedPatches
4. Render verdict via Show-DependencyClosureFromGraph
5. On OverallStatus = Fail and -IgnorePatchValidation not set: throw
6. On OverallStatus = Fail and -IgnorePatchValidation set: write
   the same diag/ JSONL set as the existing P06 stage 1 fail path
7. Emit one line summary to phase log
```

#### B.19.14.3 Operator-visible output (informative)

On `Fail`, P06 emits four files under `<WorkRoot>/diag/<timestamp>/`:

| File | Content |
|:---|:---|
| `validation_summary.json` | Top-level result, missing-KB list, recommendations |
| `validation_detail.csv` | One row per patch with Verdict, Requires, MissingFromSet |
| `wsusscn2_scan_raw.json` | (Stage 1 only; legacy from r08.0) |
| `dependency_graph.json` | Adjacency list: Requires + Supersedes edges over the KB nodes in the resolved set |

`dependency_graph.json` is new in r09.0 and is what an LLM-assisted
operator can paste into Claude/Copilot to get a recommendation on
which KB to add to the configuration. The graph format is two
arrays of edges (`Requires`, `Supersedes`) plus a `nodes` array
with `KbId`, `Title` (from §B.15.3 helpers), and `IsInBaseline`
flags.

#### B.19.14.4 Behaviour when layer 2 is absent

| Scenario | Behaviour | OverallStatus |
|:---|:---|:---|
| Layer 2 absent, online | Auto-download `wsusscn2.cab` → parse → write layer 2; resume | (downstream) |
| Layer 2 absent, `-OfflineCabPath <path>` given | Synchronously invoke `RefreshDependencyDatabase` on the given cab; resume | (downstream) |
| Layer 2 absent, air-gapped, no cab | Skip Stage 2 with one warning per run; rely on Stage 1 (catalog) only | `Unknown` |
| Layer 2 SHA-256 mismatch from layer 1 | Warning; continue with on-disk layer 2 | (continues to verdict) |
| Layer 2 has `ParserVersion` newer than running parser | Hard refuse; emit operator action | (no verdict) |
| `-SkipDependencyCheck` set | Skip Stage 2; emit one notice per run | `Skipped` |

### B.19.15 Lifecycle (normative)

#### B.19.15.1 Two trigger paths

| Trigger | Action | Frequency | Effect |
|:---|:---|:---|:---|
| Monthly maintainer refresh | `RefreshAllBaselines` (A01) | ~monthly | Full refresh of layer 1 + layer 2 |
| Ad-hoc layer 2 only | `RefreshDependencyDatabase` (A04, NEW) | as needed | Refresh layer 2 only; useful pre-PR or after cab CDN update mid-month |
| Self-trigger from P06 Stage 2 | (internal) | on demand | When stage 2 detects layer 2 absent and operator is online |

#### B.19.15.2 `RefreshAllBaselines` integration (normative)

The existing A01 action gains a new sub-phase **A01.0
RefreshDependencyDatabase**, executed **before** any per-OS
catalogue scraping:

```
A01 RefreshAllBaselines
├── A01.0 RefreshDependencyDatabase (NEW, r09.0+, fast-skip when fresh)
├── A01.1 Refresh per-OS PatchBaseline (existing, calls catalogue)
└── A01.2 Refresh per-OS LanguageSpecific (existing)
```

A01.0 logic:

1. Compute `expectedSha = ` SHA-256 of the on-disk
   `data/wsusscn2-database.json`.
2. If layer 2 absent, force a refresh.
3. If layer 2 present and `_meta.GeneratedAt` < latest Patch
   Tuesday: refresh.
4. If layer 2 present and current: skip with notice.
5. Refresh = download cab → parse → write layer 2 → cross-update
   each `PatchBaseline.WsusScnCab.DependencyDatabaseSha256`.

A01.0 emits its own JSON to `<WorkRoot>/diag/refresh-deps/` on
both skip and execute paths, for audit.

#### B.19.15.3 `RefreshDependencyDatabase` (A04, normative, new)

A standalone action for cases where the maintainer wants to refresh
only layer 2 (e.g. ad-hoc validation before a PR review, or after a
mid-month cab CDN update). Signature:

```powershell
.\Update-WindowsServerIso.ps1 -Action RefreshDependencyDatabase [-WorkRoot <path>] [-OfflineCabPath <path>]
```

Effects: same as A01.0 in isolation; does NOT touch
`config-Server*.json`. Layer 1's `DependencyDatabaseSha256`
fields are cross-updated as a courtesy so the next P06 Stage 2 sees
consistent state.

#### B.19.15.4 Cache-invalidation conditions

`<WorkRoot>/cache/wsusscn2/wsusscn2.cab` is considered stale when
any of:

- File absent.
- `wsusscn2.cab.meta.json`'s `FetchedAt` predates the latest
  Patch Tuesday by more than 2 calendar days.
- HEAD probe of the configured `SourceUrl` returns a
  `Last-Modified` newer than the recorded one.
- `Sha256` mismatches the file.

A stale cache triggers re-download. The previous file is moved to
`audit/<yyyy-MM-dd_HH-mm-ss>/wsusscn2.cab` and retained for the
window in §B.19.15.5.

#### B.19.15.5 Audit-archive retention

`<WorkRoot>/cache/wsusscn2/audit/` retains the **previous 6 monthly
cabs** with their `.meta.json`. Older entries are purged on the
next download to bound the workspace footprint at ~3.6 GB of
historical cab. 6 months covers one full quarterly servicing
window with margin for verification.

### B.19.16 Air-gapped environment operation (normative)

A fully air-gapped build host MUST be able to run P06 Stage 2 with
no network. Three operating modes are supported:

| Mode | Setup | Stage 2 behaviour |
|:---|:---|:---|
| Online (typical) | `wsusscn2.cab` auto-fetched as needed | Full validation |
| Air-gapped with cached layer 2 | `data/wsusscn2-database.json` present (committed via git, or copied in) | Full validation using cached layer 2 |
| Air-gapped with raw cab only | `wsusscn2.cab` placed manually + `-OfflineCabPath <path>` | Parse-and-validate inline |
| Air-gapped, no cab | (no setup) | Stage 2 skipped with `Unknown`; Stage 1 only |

The `-OfflineCabPath <path>` parameter (new in r09.0) is the only
way to use a manually-staged cab. The script MUST NOT silently
fall through to "skip stage 2"; the operator's intent must be
explicit via either `-OfflineCabPath` or `-SkipDependencyCheck`.

### B.19.17 Parser stability and version pinning (informative)

The Master XML schema has been stable since at least 2012 (verified
by `OSDBuilder` and `PSWindowsUpdate` parser histories), but
Microsoft has not published a formal schema. The risk of silent
schema drift is non-zero.

Mitigations:

1. `_meta.ParserVersion` in layer 2. Bumped on every breaking
   change to the parser's emit shape (B.19.10 schema). Consumers
   refuse newer versions.
2. T6 (`tests/release_info_parser_test.py`) has 13 assertions that
   cover the parser's emit shape; a schema-incompatible Master XML
   change would surface there before merging.
3. A new test `tests/wsusscn2_parser_test.py` (T7) is planned for
   r09.0: it consumes a committed `tests/fixtures/wsusscn2/` set of
   miniature Master XML snippets and asserts the parser's behaviour
   on representative `<Update>` shapes. T7 is OFFLINE (uses
   fixtures) so it can run on every PR.
4. Live `wsusscn2.cab` is probed monthly by T5
   (`wsusscn2_probe.py`, existing) which probes only the cab's
   reachability and size; T5 is supplemented by T8 (planned) that
   does a deep schema probe by parsing the live Master XML and
   confirming every required attribute is present in at least one
   `<Update>`.

### B.19.18 Maintainer operations guide (informative)

#### B.19.18.1 Monthly Patch-Tuesday refresh procedure

```powershell
# 1. Run RefreshAllBaselines as usual (covers layer 2 via A01.0)
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -Mode Monthly

# 2. Inspect the layer 2 diff
git diff data/wsusscn2-database.json | head -80

# 3. Sanity-check layer 2 size
wc -c data/wsusscn2-database.json

# 4. Run the synthetic CI locally
python3 tests/wsusscn2_parser_test.py        # T7 (new)
python3 tests/catalog_fixture_test.py        # T2 (existing)

# 5. Inspect the layer 1 diff
git diff data/config-Server*.json

# 6. Commit both layer 1 and layer 2 in the same commit
git add data/config-Server*.json data/wsusscn2-database.json
git commit -m "data: r09.0 layer-1+2 monthly refresh (2026-MM)"
```

#### B.19.18.2 PR review checklist

When reviewing a PR that touches `data/wsusscn2-database.json`:

- [ ] `_meta.WsusScnCab.Sha256` is present and is a 64-char hex
      string.
- [ ] `_meta.GeneratedAt` is recent (within 7 days of the PR
      submission).
- [ ] `_meta.Counts.TotalPackages` is in the 200–600 range
      (typical post-scope-filter count).
- [ ] No KB Title strings, descriptions, or release-notes prose are
      present. Quick grep:
      `grep -c "Cumulative Update" data/wsusscn2-database.json` →
      MUST be 0.
- [ ] Layer 2 file size is between 1 MB and 8 MB. (`wc -c`)
- [ ] Layer 1 `DependencyDatabaseSha256` in every
      `config-Server*.json` matches the actual SHA-256 of the
      committed layer 2 file.
- [ ] T2, T7 (when implemented) pass locally.
- [ ] The corresponding `wsusscn2.cab` is downloadable from
      Microsoft and produces the same SHA-256.

#### B.19.18.3 Future: GitHub Actions automation (out of scope for r09.0)

A monthly scheduled workflow analogous to Stage 4 (monthly baseline
refresh) could run RefreshAllBaselines + commit the diff
automatically. This is **not implemented in r09.0** because:

- The 600 MB `wsusscn2.cab` download is on the slow side of what a
  free GitHub Actions runner has time for; the runner would need
  to cache aggressively.
- The diff often crosses the §B.19.8 prose-exclusion line at the
  margins (a new field type appears that the parser does not yet
  classify), and a human should triage it.

Reserved as future work.

### B.19.19 Rollout and backward compatibility (normative)

#### B.19.19.1 Phasing

| r09.0 Step | Scope | Outcome |
|:---|:---|:---|
| Step 1 | Parser + layer 2 schema | The parser ships; layer 2 is generated on demand but P06 Stage 2 does not yet run |
| Step 2 | P06 Stage 2 wired (off by default) | `-EnableDependencyCheck` opts in for verification; default OFF until field-tested |
| Step 3 | P06 Stage 2 ON by default | Existing operators opt out via `-SkipDependencyCheck` if needed |
| Step 4+ | Cross-OS validation | Server 2019/2022/2025 +Execute Build with stage 2 verifying correctly |

Each Step ships as a separate commit on `main` with its own
CHANGELOG entry.

#### B.19.19.2 Behaviour when layer 2 is absent at runtime

Already specified in §B.19.14.4. Summary: r09.0 Step 1+2 is fully
backward-compatible — the absence of `data/wsusscn2-database.json`
behaves as "Stage 2 unknown, Stage 1 still works". Step 3 retains
that behaviour for the `-OfflineCabPath` flow but warns louder.

#### B.19.19.3 Behaviour when `-SkipDependencyCheck` is set

Stage 2 is skipped silently after one notice line per run. This is
the operator's explicit escape hatch and is documented in
`README.md` troubleshooting. It does NOT suppress §B.13
mount-time checking, which remains the runtime safety net.

#### B.19.19.4 Migration path for existing operators

Existing operators upgrade as follows:

1. Pull the new `Update-WindowsServerIso.ps1` and the new
   `data/wsusscn2-database.json` (both ship together).
2. No config changes needed — existing
   `config-Server*.json` files are forward-compatible; the new
   optional fields will be populated on the next
   RefreshAllBaselines.
3. On first run after upgrade, P06 Stage 2 reports `Unknown` if
   `RequiresKbIds` is empty for any `NeutralPatches[*]` entry; the
   operator either runs `-Action RefreshAllBaselines` or
   `-Action RefreshDependencyDatabase` once to populate.

Operators on air-gapped hosts who do not pull layer 2 will see
Stage 2 = `Unknown` indefinitely; this matches the §B.19.16
expectation and is not a regression.

---

## B.20 File organisation and naming conventions

**Status**: normative (r06.0+).

### B.20.1 Directory layout

```
scripts/powershell/update-windows-server-iso/
├── Update-WindowsServerIso.ps1     # Main script (r08.0; r09.0 implementation pending)
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
│   ├── cache-du-Server2022.json      # Parsed Dynamic Update cache (Server 2022)
│   └── cache-du-Server2025.json      # Parsed Dynamic Update cache (Server 2025)
│   # Planned (r09.0 Step 2+):
│   # └── wsusscn2-database.json     # Layer 2, ~2-5 MB (per §B.19)
│
├── tests/                            # Python self-verification suite (T1-T10)
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
  is encoded into the filename (`cache-du-Server2025.json`, not
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
| `data/wsusscn2-database.json` | Tool-generated data | r09.0+, single file |
| `data/raw-release-info.md` | Mirrored upstream | Refreshed by RefreshSnapshots |
| `docs/history/r08.0-step2-installwim-symmetry-check.md` | Per-revision investigation | Cycle (r08.0), step (step2), topic kebab-case |
| `tests/fixtures/2026-05/server2025-lcu.html` | Test fixture | Per-month, per-OS HTML captures |

### B.20.4 What this section does NOT cover

- Naming of internal PowerShell functions inside the .ps1 file. Those
  follow Pascal-case verb-noun per PowerShell convention and are
  enforced by PSScriptAnalyzer's `PSUseApprovedVerbs` rule.
- Naming of CI workflow files. Those follow the repository-wide
  convention documented in the
  [repository-level SPEC](../../../SPEC.md) §3.1, which uses
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
absorbs the new wsusscn2-database.json in r09.0 without surprise.

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

**Why**: Independent tracking of SSU and LCU enables P06 Stage 2
(§B.19) to surface SSU-prerequisite failures cleanly; without
separation, the prerequisite chain would not be representable in
layer 1.

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

`-PatchMonth <yyyy-MM>` allows the script to be pointed at a past
baseline state for inspection. The flag is read-only: it changes how
Stage 1 catalog comparison works but does not enable mutation of
`data/config-*.json`.

**Why**: Historical reproducibility — an operator can replay a past
month's baseline against a current `wsusscn2.cab` without polluting
the committed state.

### B.22.12 CI structure: stage4 monthly refresh

CI Stage 4 (`...__stage4__monthly-refresh.yml`) runs
RefreshAllBaselines monthly on the 15th and opens a PR if
`data/config-Server*.json` changed. r09.0 extends this to also
include `data/wsusscn2-database.json` in the auto-PR.

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

Two helpers live in `Update-WindowsServerIso.ps1`, immediately after
the 7-Zip helper block (§B.19.4):

| Function | Purpose |
|:---|:---|
| `ConvertTo-CanonicalJson` | Serialize an object to a canonical JSON string. |
| `Save-CanonicalJsonFile`  | Serialize and atomically write the result to a file. |

`ConvertTo-CanonicalJson` is a thin wrapper over `ConvertTo-Json
-Depth $Depth`. PowerShell 7's `ConvertTo-Json` default output already
satisfies rules 3, 4, 6, 7, and 9. The wrapper adds three corrections:

1. **CRLF → LF normalisation** (rule 2). PowerShell 7's
   `ConvertTo-Json` line endings are platform-dependent; the wrapper
   replaces `\r\n` with `\n` unconditionally so output is identical on
   Windows and Linux.
2. **Scientific notation E → e** (parity with Python). PowerShell
   emits `1E+100`; Python emits `1e+100`. JSON RFC 8259 permits both,
   but byte parity requires one. The canonical choice is lowercase
   `e`, matching Python's default; the wrapper post-processes the
   PowerShell output with the regex `(?<=\d)E(?=[+\-]?\d)`.
3. **Trailing newline policy** (rule 8). PowerShell adds none; the
   wrapper adds exactly one LF unless `-NoTrailingNewline` is set.

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

Existing files in `data/` may still be in the PS 5.1 legacy format
or a mix of the two; existing files in `tests/fixtures/` may already
be in the Python 2-space format. Both populations are **not yet**
guaranteed to be in canonical format; the migration to canonical is
a separate, scope-controlled effort tracked in the CHANGELOG.

During the migration window, the following invariants apply:

- Any newly created `data/*.json` or `tests/fixtures/*.json` file
  MUST be written through `ConvertTo-CanonicalJson` /
  `Save-CanonicalJsonFile` (PowerShell) or `canonical_json_dumps` /
  `save_canonical_json_file` (Python).
- Any commit that modifies an existing `data/*.json` file SHOULD
  convert the file to canonical format in the same commit. The
  conversion produces a large mechanical diff; it is acceptable to
  isolate the conversion in a dedicated commit immediately preceding
  the semantic change so reviewers can read the two diffs separately.
- A commit that converts a file to canonical format MUST note the
  conversion in the CHANGELOG entry, including the source format
  identification (PS 5.1, Python 2-space, hand-written, etc.).

After the migration is complete, the format check becomes a
Part C quality gate (a `python3 tests/canonical_json_format_check.py`
script that walks both directories and fails on any file that does
not match its own canonical re-serialisation).

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
cd scripts/powershell/update-windows-server-iso
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
[`scripts/python/powershell-static-analyzer/SPEC.md` §4.28a](../../python/powershell-static-analyzer/SPEC.md#428a-psa7002--lf-only-or-mixed-line-endings).

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

### C.3.3 Cross-field consistency

After r09.0 the layer 1 / layer 2 cross-reference (§B.19.12) adds
two consistency checks:

- `PatchBaseline.WsusScnCab.DependencyDatabaseSha256` MUST equal
  the SHA-256 of `data/wsusscn2-database.json` (when both are
  present).
- Every `NeutralPatches[*].RequiresKbIds` entry MUST be either
  empty or refer to KB IDs present in the same `NeutralPatches[]`
  array (i.e. the dependency must be **in the baseline**, not
  dangling).

`Test-OsConfigConsistency` is the planned implementation; for r09.0
Step 1 the check is manual at PR review per §B.19.18.

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
[Artifact Content Minimization](../../../SPEC.md#12-spec-ci-081-artifact-content-minimization)
policy.

## C.6 Monthly baseline refresh

**Status**: normative.

CI Stage 4 (`...__stage4__monthly-refresh.yml`) runs on the 15th of
each month and after manual `workflow_dispatch`. It:

1. Checks out `main`.
2. Runs `.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines`.
3. (r09.0+) The action's A01.0 sub-phase (§B.19.15.2) refreshes
   `data/wsusscn2-database.json` first.
4. If any `data/config-Server*.json` or
   `data/wsusscn2-database.json` changed, opens an auto-PR.
5. The PR is restricted via `add-paths` to `data/config-*.json` and
   (r09.0+) `data/wsusscn2-database.json`.

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
suite of **ten tools (T1 through T10)**. They probe the script's
external dependencies and unit-test its PowerShell functions. They
use only the Python standard library — no `pip install` required.
The canonical T-numbering is maintained in
[`tests/README.md`](./tests/README.md) "Tool inventory"; this section
mirrors that authoritative table.

### C.9.1 Tool inventory (T1 – T10)

| Tool | Type | Assertions | Network | Run when |
|:---|:---|:---|:---:|:---|
| **T1** `catalog_probe.py` | Live Microsoft Update Catalog probe (search + per-OS title formats + supersedence panel) | ~7 live checks | Yes | Before/after Catalogue-related code change; monthly CI |
| **T2** `catalog_fixture_test.py` | Offline HTML fixture regression against `fixtures/<patch-month>/` | 13 | No  | Every commit that touches parsers or TitleTokens |
| **T3** `powershell_harness.py` | PS function unit tests via `-Action TestHarness` | **7** | No  | Every commit that touches a PS scrape helper |
| **T4** `eval_iso_probe.py` | Evaluation ISO endpoint check (HTTP Range-GET; 4 OS × 2 lang) | live (4 OS) | Yes | Before release; on Microsoft Evaluation Center snapshot rotation |
| **T5** `wsusscn2_probe.py` | `wsusscn2.cab` freshness check (existence + size + Last-Modified; 60-day warn threshold) | live | Yes | Before running P06; monthly CI |
| **T6** `release_info_parser_test.py` | Offline regression for `ConvertFrom-ReleaseInfoMarkdown` against the PoC fixture | 13 | No | Every commit that touches the release-info parser |
| **T7** `dotnet_cu_parser_test.py` | Offline regression for `ConvertFrom-DotNetCuIndexMarkdown` / `ConvertFrom-DotNetCuMarkdown` against `snapshots/dotnet_cu/` | 16 | No | Every commit touching the .NET CU parsers or the fetch/cache pipeline |
| **T8** `dynamic_update_cache_test.py` | Offline regression for the Dynamic Update 36-month cache subsystem (`Add-/Get-/Remove-DynamicUpdateCacheEntry`); 3 fixture scenarios + 3 defensive cases | 20 | No | Every commit touching the DU cache functions or the 36-month window logic |
| **T9** `catalog_title_tokens_test.py` | Offline regression for `Get-CatalogTitleTokenList` against all four OS configs + `Test-CatalogTitleMatch` through 13 live-captured Catalog title cases | 18 | No | Every commit touching `Common.CatalogTitleTokens` in any OS config, or the narrow-filter helpers |
| **T10** `release_info_resolver_test.py` | Offline regression for `Get-PatchSetFromReleaseInfoDiscovery` (Refresher main-path migration); 4 scenarios + defensive cases | 18 | No | Every commit touching `Resolve-PatchSetFromReleaseInfo`, the discovery helper, or its three caches |

**Determinism categories**:

- **Offline-deterministic** (run on every PR): T2, T3, T6, T7, T8, T9, T10.
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

A new tool — provisionally **T11 `wsusscn2_parser_test.py`** — is
planned for r09.0 Step 2+ to provide offline regression coverage for
the §B.19 Master XML parser (`ConvertFrom-WsusScnPackageXml`,
`New-WsusScnDependencyDatabase`). It will assert the parser's emit
shape against committed mini-XML fixtures under
`tests/fixtures/wsusscn2/`. Implementation tracks the §B.19.17 parser
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
| `Write-Step`, `Write-Ok`, `Write-Warn`, `Write-Fail`, `Write-Skip`, `Write-PhaseHeader`, `Write-PhaseFooter` | Log helpers with severity prefixes (§A.3) |
| `Get-EnvironmentInfo` | Five-pillar environment dump (OS, PS, locale, network, ADK) |
| `Add-ErrorJsonlEntry` | Per-error JSONL append |
| `Invoke-DownloadWithProgress` | Progress-aware HTTP download with retry |
| `Assert-IsAdministrator` | Elevation check |
| `Set-ConsoleUtf8` | Console encoding setup |

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
| `Test-PatchDependencyClosureOnMount` | r04 | Mount-time prerequisite check (§B.13) |
| `Get-Pca2023ReadinessSnapshot`, `Show-Pca2023ReadinessSnapshot`, `Format-Pca2023ReadinessForReport` | r05.0 | Health verdict for PCA2023 readiness (§B.17) |
| `Convert-WimBootToPca2023Signed` | r05.0 | PSA-clean reimplementation of `Make2023BootableMedia.ps1` (§B.17) |
| `Get-IsoBootCertReadiness` | r05.0 | INPUT-side boot.wim readiness inspection (§B.17.2) |
| `Test-OutputIsoPca2023Readiness` | r08.0 Step 3 | OUTPUT-side ISO 5-target check (§B.18) |
| `Assert-WorkspacePreflight` | r04.3 | Workspace structural readiness (§B.21) |
| `Test-PatchDependencyClosureFromGraph` | r09.0 (planned) | Pre-mount graph-based dependency check (§B.19.13) |
| `ConvertFrom-WsusScnPackageXml` | r09.0 (planned) | XmlReader-based Master XML parser (§B.19.9) |
| `New-WsusScnDependencyDatabase` | r09.0 (planned) | Layer 2 JSON renderer (§B.19.9, §B.19.10) |
| `Invoke-WsusScnPackageXmlExtract` | r09.0 (planned) | Two-stage 7-Zip extract of package.xml (§B.19.9.1) |
| `Get-WsusScnCabIfNeeded` | r05.0 → extended r09.0 | Conditional wsusscn2.cab download with cache invalidation (§B.19.15.4) |

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
  Build -Execute` with stage 2 verifying); deal with the residual
  KB5087537 SSU-prerequisite incident (currently a config-side
  pending action).

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

