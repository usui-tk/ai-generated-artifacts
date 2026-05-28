# Changelog

All notable changes to `Update-WindowsServerIso.ps1` (and its
companion files in this project directory) are documented in this
file. Per the repository-wide policy documented in the root
[`SPEC.md`](../../../SPEC.md), CI workflow changes are recorded here
too — not inside `.github/workflows/` — because this project is the
CI target.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The script version is held in `$Script:ScriptVersion` near the top of
the script and follows the
`update-wsi-<YYYY.MM.DD>-r<NN>` pattern.

## [Unreleased]

### r11.1 - cross-repo canon encoding/TLS helper rename

Renames two host-configuration helpers to their Deploy-AMD canon names so that functions performing the same work carry the same names across repositories. Function behaviour is unchanged; this is a pure rename plus the script-identity bump.

- **`Set-ConsoleUtf8` renamed to `Set-Utf8PipelineEncoding`** (1 definition + 1 call site). The body sets all three encodings — `[Console]::OutputEncoding`, `[Console]::InputEncoding`, and the pipeline-global `$OutputEncoding` — so the canon name (which captures the broader pipeline-encoding scope) is more accurate than the old console-only name.
- **`Set-Tls12` renamed to `Set-TlsSecurityProtocol`** (1 definition + 1 call site). The body assigns the `[Net.ServicePointManager]::SecurityProtocol` bitmask; the pre-rename name understated this (the bitmask is broader than TLS 1.2).
- The two bodies are intentionally left unchanged (they are simpler than, and divergent from, the Deploy-AMD canon implementations) and are classified as carve-outs — same name, divergent body — in the sibling repository's SPEC §A.11.7 partial-participant list.
- Corrected a stale copy/paste comment in the `Set-TlsSecurityProtocol` body: the `.DESCRIPTION` previously cited Speaker Deck / `files.speakerdeck.com` (inherited from the sister `Download-SpeakerDeck.ps1` script it was seeded from). It now names this script's actual TLS 1.2+ download endpoints — the Microsoft Update Catalog (`catalog.update.microsoft.com`), the Windows Update CDN (`catalog.s.download.windowsupdate.com`, which serves `wsusscn2.cab`), and the GitHub release endpoints (`api.github.com` / `github.com`) used for the 7-Zip fallback. Comment-only change; no code or behaviour change.
- `$Script:ScriptVersion` bumped `update-wsi-2026.05.29-r11.0` → `update-wsi-2026.05.29-r11.1`; `$Script:ScriptTag` set to `cross-repo-canon-iso-encoding-tls-rename`.

### r11.0 - cross-repo canon port alignment

Aligns this script's ported logging / DebugTrace helpers to the
Deploy-AMD shared-helper canon so that functions performing the same
work carry the same names across repositories, and registers this
script in the sibling repository's SPEC §A.11.7 as a *partial port
participant*. Function behaviour is unchanged; this is a naming and
body-alignment release plus the script-identity bump.

- **`Write-Warn` renamed to `Write-Caution`** script-wide (120
  occurrences: 1 definition + 119 call sites), matching the canon name
  adopted in the sibling repo's
  `cross-repo-shared-utility-canon-write-caution` release. The
  word-boundary rename leaves the unrelated built-in `Write-Warning`
  (5 call sites) untouched.
- **Canonical `Write-Detail` helper added.** The three info lines in
  `Install-SevenZipFallback` (`Version` / `Source` / `URL`) that the
  original port had mapped onto `Write-Step` now call `Write-Detail`,
  matching the Deploy-AMD source and removing the last logger-naming
  divergence previously noted as "deferred" in SPEC §B.19.4.4.
- **Seven helpers aligned to the canon body** (parameter-name and
  type-annotation differences only): `Write-Caution`, `Write-Step`,
  `Write-Ok`, `Write-Fail`, `Write-Skip`, `_DebugTrace_RetireFrame`,
  and `Enable-AutoExportOnPhaseFailure`. As a side effect of the
  `Write-Caution` rename, `Write-DebugFailureReport` also became
  byte-identical to canon.
- **Cross-repo byte-identity grew from 10 to 19** of the tracked canon
  helpers. The remaining same-name helpers (`Write-PhaseHeader`,
  `Write-PhaseFooter`, `_DebugTrace_WriteJsonlLine`, `Start-DebugTrace`,
  `Stop-DebugTrace`, `Enable-DebugTraceFileOutput`,
  `Show-PowerShellEnvironment`) stay as documented carve-outs because
  this script's phase / DebugTrace model and the
  `Show-PowerShellEnvironment` driver-context differ structurally.
  `Set-TlsSecurityProtocol`, `Set-Utf8PipelineEncoding`, and
  `Assert-Admin` are not present in this script.
- **SPEC §B.19.4.4 updated** from the "renamed loggers / deferred"
  wording to the aligned state; the only residual per-script
  differences in the ported 7-Zip helpers are the GitHub API
  `User-Agent` string and a `psa-disable` justification comment, both
  of which correctly encode this script's own identity.
- The sibling repository records the reciprocal classification under a
  new SPEC §A.11.7 *partial port participant* tier under the shared
  `cross-repo-canon-iso-port-alignment` tag.
- `$Script:ScriptVersion`: `update-wsi-2026.05.28-r10.4` ->
  `update-wsi-2026.05.29-r11.0`. `$Script:ScriptTag`:
  `cross-repo-canon-iso-port-alignment`.
- `psa.py` (4.2.0) remains 0 / 0 / 0 on this script.

### r09.0 Step 2b3 - real-data-driven parser correction

This change corrects the Phase 2b1 parser and the Phase 2b2 Layer 1
writeback after the **first end-to-end run against a live
`wsusscn2.cab`** (2026-05-12 fetch, 641,849,140 bytes, 136,102
`<Update>` rows) on the Linux verification host. Phase 2b1 had been
authored and unit-tested against an *assumed* wsusscn2 structure that
diverged from reality in several material ways; every assumption is now
replaced with the empirically verified structure (SPEC §B.19.9.6) and
the whole pipeline is validated against the real cab.

This entry **supersedes** the structural claims in the Step 2b2 entry
below (per the AP-9 metadata-correction rule: corrections are recorded
as a new entry, not by rewriting the prior one). Stage chaining, the
A01→A04 soft-fail chain, and DryRun semantics from Step 2b2 are
unchanged and remain accurate.

#### Root cause

Phase 2b1's parser, fixtures, and tests were written without ever
parsing a real `wsusscn2.cab`. The synthetic fixture encoded a guessed
structure, so T12/T13 passed green while the parser produced
**zero usable data** against the real cab (0 file-locations, 0 payload
URLs, 0 KB-bearing in-scope updates). The AGENTS.md §4
ground-truth-extraction rule had not been applied to the external data
format.

#### Corrections (all verified against the live cab)

**Stage 3 (`ConvertFrom-WsusScnPackageXml`)** — rewritten to the real
structure:

| Assumed (Phase 2b1) | Real (verified) |
|---|---|
| `<KBArticleID>` element holds a KB number | No KB number exists anywhere in the Master XML; KB lives in the Catalog |
| Payload is `<Files><File Digest="…" />` | `<PayloadFiles><File Id="<digest>" />` (digest in `Id`) |
| `<BundledBy><RevisionId Id="…" />` | `<BundledBy><Revision Id="…" />` |
| `<SupersededBy><UpdateId Id="…" />` | `<SupersededBy><Revision Id="…" />` |
| `<FileLocation FileDigest="…"><Url>…</Url>` | `<FileLocation Id="<digest>" Url="…" />` |
| In-scope Product+Classification update carries the payload | The in-scope row is a *bundle* with no payload; payloads live on *leaf* rows that point up via `BundledBy` |

The corrected parser does one streaming pass that (a) collects in-scope
bundles, (b) builds a `bundleRevisionId → [payloadDigests]` roll-up by
walking every leaf's `BundledBy` + `PayloadFiles`, and (c) builds a
`digest → URL` map; a post-pass resolves each bundle's `payloadUrls`
from the leaves bundled under it. The positive child-element allowlist
(SPEC §B.19.8) is now `Categories, Category, Prerequisites, UpdateId,
SupersededBy, BundledBy, Revision, PayloadFiles, File`.

**Server 2025 Product GUID correction** (SPEC §B.19.9.7): the Server
2025 Product Category GUID was `ca006cfb-49eb-439b-880a-1312e1fc9713`,
whose newest SecurityUpdate bundle silently stalled at 2025-09-08. The
verified GUID carrying the current Server 2025 LCU (KB5087539,
2026-05-11) is `b256987d-4693-4c87-955d-dbb9341205eb`. It carries the
Server LCU but not the Windows 11 24H2 client LCU (KB5089549), so it is
server-specific. With the fix, all four OS families resolve their
2026-05-11 LCU (Server 2016 KB5087537, 2019 KB5087538, 2022 KB5087545,
2025 KB5087539).

**Stage 4 (`New-WsusScnDependencyDatabase`)** — `kbArticleIds` removed
(no KB in wsusscn2); `supersededByUpdateIds`/`bundledByRevisionIds`
replaced by `supersededByRevisionIds`; `payloadUrls` now come
pre-resolved from Stage 3; `_meta.stats` gains `leafUpdatesWithPayload`
and `payloadDigestsOrphaned`.

**`Get-WsusScnCabIfNeeded` call-site fix (A04 Stage 1)** — the Step 2b2
A04 wrapper called this with non-existent parameters
(`-CabPath`/`-StaleAfterDays`/`-ForceRefetch`). Corrected to the real
signature (`-WsusScnCabMeta`/`-WorkRoot`/`-LatestPatchTuesday`/
`-OverridePath`), mirroring the P06 ValidatePatchSet acquisition
pattern. A04 params are now `-OverridePath`/`-OutputPath`/
`-SkipLayer1Update`.

**Layer 1 (`Update-Layer1DependencyVerification`)** — KB-based fields
replaced with identity fields, since wsusscn2 has no KB:
`_DependencyVerifiedUpdateId`, `_DependencyVerifiedRevisionId`,
`_DependencyVerifiedCreationDate`, `_DependencyVerifiedAt`.

**Tests** — the T12 fixture builder was rewritten to the real
bundle/leaf structure (`PayloadFiles`, `BundledBy/Revision`,
`FileLocation Id/Url`, two-tier bundle↔leaf linkage). T12 reworked to
22 assertions on the new schema; T13 reworked to 15 assertions on the
UpdateId/RevisionId identity fields.

#### End-to-end verification (live cab, Linux host)

- Stage 1: 612 MB download OK (`downloadedNow=True`).
- Stage 2: 7-Zip two-step extraction OK (package.xml 113,842,356 bytes).
- Stage 3: 136,102 observed → 138 in-scope bundles → 110,749 leaves
  with payload → 97,051 file-locations → **0 orphaned digests**,
  **every in-scope bundle's payloadUrls resolved**. ≈ 4.5 min parse.
- Stage 4: Layer 2 JSON written (~198 KB).
- A04 whole-wrapper run: `A04 RefreshDependencyDatabase: completed
  successfully` (`returned: True`).
- Gates: psa 0/0/0, PSScriptAnalyzer 0, T2–T13 175→176 assertions all
  green, canonical-JSON format 26/26.

#### Files changed

- `Update-WindowsServerIso.ps1`: Stage 3 rewrite, Stage 4 reshape,
  Layer 1 rewrite, A04 Stage 1 call-site fix, Server 2025 GUID table +
  name-map correction, `$Script:ScriptTag` → `step2b3-real-data-parser-correction`.
- `tests/common/wsusscn2_fixture_builder.py`: full rewrite to real structure.
- `tests/wsusscn2_parser_test.py`, `tests/wsusscn2_layer1_test.py`: reworked assertions.
- `tests/fixtures/wsusscn2/{package.xml,expected-output.json}`: regenerated.
- `SPEC.md`: added §B.19.9.6 (verified structure) and §B.19.9.7 (Server 2025 GUID correction).

### r09.0 Step 2b2 - A04 wrapper implementation and Layer 1 integration

This change implements the Phase 2b2 lifecycle glue that turns the
parser pipeline (landed in Step 2b1) into a full Action: `-Action
RefreshDependencyDatabase` now chains Stages 1-4 end-to-end and
propagates the latest LCU KB and CreationDate per Server OS family
into the data/config-Server*.json baselines. `-Action
RefreshAllBaselines` automatically chains A04 as a soft-fail
downstream step, so the monthly refresh workflow gains
dependency-database freshness without any operator-facing change.

### What is in this commit

**Production code (`Update-WindowsServerIso.ps1`, +244 net lines)**:

| Site | Lines | Purpose |
|---|---:|---|
| L538-539 | 1 changed | `$Script:ScriptTag` bumped from `step2b1-parser-pipeline-and-fixture-tooling` to `step2b2-a04-wrapper-implementation-and-layer1-integration`. `$Script:ScriptVersion` unchanged. |
| L13012-13182 | replaced | `Invoke-AdminPhaseA04_RefreshDependencyDatabase` body, replacing the Step 2a `NotImplementedException` stub. New body executes Stage 1 (`Get-WsusScnCabIfNeeded`) → Stage 2 (`Invoke-WsusScnPackageXmlExtract`) → Stage 3 (`ConvertFrom-WsusScnPackageXml`) → Stage 4 (`New-WsusScnDependencyDatabase`) → Layer 1 writeback (`Update-Layer1DependencyVerification`). Caller-overridable `-CabPath`, `-OutputPath`, `-StaleAfterDays`, `-ForceRefetch`, `-SkipLayer1Update`. DryRun mode parses but skips the JSON and Layer 1 writebacks. Staging directory beneath `$Script:TempDir`; cleaned on success, preserved on failure for inspection. Soft-fail return: `$false` on any pipeline error, `$true` on success or DryRun completion. |
| L13184-13283 | +100 | `Update-Layer1DependencyVerification` (new helper). For each Server OS family in `$Script:WsusScnOsCategoryGuids`, finds the most-recent LCU-bearing in-scope Update and writes three advisory fields to `data/config-<OsKey>.json`: `_DependencyVerifiedKb`, `_DependencyVerifiedCreationDate`, `_DependencyVerifiedAt`. Idempotent (re-runs report `UnchangedCount` instead of `UpdatedCount` when values match). Uses `Save-ConfigWithBaseline` for atomic LF/UTF-8 writes. |
| L12602-12624 | +23 | `Invoke-AdminPhaseA01_RefreshAllBaselines` soft-fail chain into A04 immediately after `Show-RefreshAllBaselinesSummary`. A04 failure is reported via `Write-Warn` but does NOT mark A01 as failed (the per-OS config baselines are the primary A01 deliverable; the dependency database is downstream advisory data). |

**Design choices**:

- *A01 -> A04 is a chain, not a dependency*. A01 still completes
  successfully even if A04 fails. This protects the monthly refresh
  workflow against transient wsusscn2.cab CDN failures.
- *Layer 1 writeback writes only three advisory fields* per config.
  No structural keys are added; no existing keys are renamed.
  Downstream consumers that do not know about these fields ignore them
  (forward-compatible JSON).
- *DryRun is partial-execute, not full-skip*. A04 still acquires the
  cab and parses package.xml in DryRun so the run is informative; only
  the Layer 2 JSON write and Layer 1 config writeback are skipped.
  This matches the established convention for A01 / A02 / A03.
- *Staging is workspace-local*. The cab extraction stages into
  `$Script:TempDir`-relative paths rather than `[Path]::GetTempPath()`
  so the workspace policy (LogsDir / TempDir siblings) is preserved.
  On failure the staging is left in place for the operator to inspect.

**What is intentionally NOT yet wired up** (Phase 2c scope):

- The SSU/LCU pre-flight gate that *consumes* the `_DependencyVerified*`
  fields (SPEC §B.19.5) is not yet implemented. The fields are now
  written but no Phase reads them yet.
- The dependency-closure graph walk (SPEC §B.19.14, Phase 2c) that
  expands the Layer 2 JSON into a topologically-sorted patch order is
  out of scope here.

**New offline test (`tests/wsusscn2_layer1_test.py`, T13, ~190 lines)**:

14 assertions exercising:

- Stub-config setup pre-flight: 4 minimal `config-Server*.json` files
  created in a temp `data/` directory
- Run 1 (first invocation): `UpdatedCount=2` (Server 2022 + Server 2025),
  `UnchangedCount=0`, `MissingCount=2` (Server 2016 + Server 2019,
  which have no in-scope LCU in the T12 fixture)
- Field-level correctness on Server 2022: `_DependencyVerifiedKb=KB5099001`,
  `_DependencyVerifiedCreationDate=2026-04-15T10:00:00Z`,
  `_DependencyVerifiedAt` present and ISO-8601 formatted
- Field-level correctness on Server 2025: `_DependencyVerifiedKb=KB5099003`,
  `_DependencyVerifiedCreationDate=2026-05-10T10:00:00Z`
- Missing-OS hygiene: Server 2016 config has no `_DependencyVerifiedKb`
  field added (no spurious writeback)
- Existing-field preservation: the pre-existing `OsKey` field survives
  the writeback intact
- Run 2 (idempotent re-invocation): `UpdatedCount=0`, `UnchangedCount=2`,
  `MissingCount=2`

The test runs against a tempdir-cloned `data/` so the repository's real
configs are never touched. Stage 1 (`Get-WsusScnCabIfNeeded`) is
*not* exercised here; it is covered by the live monthly refresh CI
and the synthetic-test-mode end-to-end run.

**Documentation updates**:

- `SPEC.md` §B.19.9.5 *A04 wrapper lifecycle (Phase 2b2 binding)*
  added covering the function signature, parameter semantics, A01
  chaining model, and Layer 1 writeback contract.
- `SPEC.md` §B.19.15.3 updated to reflect that A04 is now implemented
  (was: pointer to Step 2b stub).
- `tests/README.md`: Tool inventory + Quick start + File layout updated
  with T13 row.
- `README.md` / `README.ja.md`: T12 -> T13 in the Self-verification
  tools count, bilingual lock-step preserved.
- `TESTING.md` §0 status table updated with T13 row and A04 status
  changed from "stub" to "implemented".

### Quality gate

| Gate | Result |
|---|---|
| `psa.py` (PSA full rule set) | 0 errors, 0 warnings, 0 info |
| `PSScriptAnalyzer` (Settings.psd1) | 0 findings |
| Unit tests T2-T12 (no regression) | 160/160 passed (138+22) |
| **T13 (new)** | **14/14 passed** |
| Canonical JSON format gate | 26/26 passed (no JSON additions) |
| Bilingual lock-step (README.md / .ja.md / TESTING.md) | preserved |

### r09.0 Step 2b1 - wsusscn2 parser pipeline and fixture tooling

This change implements the Phase 2b1 parser pipeline (Stages 2-4 of the
wsusscn2.cab dependency-database production line) inside
`Update-WindowsServerIso.ps1`, plus the offline T12 self-verification
suite that exercises the pipeline against a small committed fixture.
The implementation builds on the GUID inventory and analyzer tooling
landed in the preceding Step 2b1 preparation commit (648880e).

**Prior-commit metadata correction (AP-9 follow-up)**: the
preparation-step CHANGELOG entry (commit 648880e) recorded
`tests/common/wsusscn2_analyzer.py` as `~370 lines`. The actual file
is 504 lines (verified by `wc -l`). The discrepancy was a CHANGELOG
self-reported value drift, not a code defect (md5 of the file matched
between the staged zip and the committed file). This commit does not
edit 648880e's CHANGELOG entry retroactively but records the
correction here, per AGENTS.md §4 ground-truth-extraction policy.

### What is in this commit

**Production code (`Update-WindowsServerIso.ps1`, +669 lines)**:

| Site | Lines | Purpose |
|---|---:|---|
| L538-539 | 1 changed | `$Script:ScriptTag` bumped from `step2a-followup-canonical-json-migration` to `step2b1-parser-pipeline-and-fixture-tooling`. `$Script:ScriptVersion` unchanged. |
| L569-630 | +62 | Three `$Script:WsusScn*` lookup tables: `WsusScnOsCategoryGuids` (4 Server LTSC Product GUIDs), `WsusScnCategoryGuidNameMap` (GUID -> human label for diagnostic output), `WsusScnUpdateClassificationGuids` (5 WSUS Classification GUIDs). Provenance documented inline pointing at research §5.7 / §6.4. |
| L7021-7117 | +97 | `Invoke-WsusScnPackageXmlExtract` (Stage 2). Two-step 7-Zip extraction (wsusscn2.cab -> package.cab -> package.xml). Uses existing `Get-SevenZipPath` / `Install-SevenZipFallback` from Step 2a. Caller owns the staging directory lifecycle. |
| L7118-7454 | +337 | `ConvertFrom-WsusScnPackageXml` (Stage 3). Streaming `XmlReader`-based parser with a positive child-element allowlist (`KBArticleID`, `Categories`, `Category`, `Prerequisites`, `UpdateId`, `RevisionId`, `SupersededBy`, `BundledBy`, `Files`, `File`) that physically excludes Microsoft prose (`<Title>`/`<Description>`/`<MoreInfoUrl>` are never read; SPEC §B.19.8 hard rule enforcement). Applies the scope filter (Product GUID AND Classification GUID AND 24-month recency, all caller-overridable). Returns `[pscustomobject]` with `Updates` / `FileLocations` / `Stats`. |
| L7455-7587 | +133 | `New-WsusScnDependencyDatabase` (Stage 4). Joins payload URLs from `FileLocations` into each Update's record, attaches provenance metadata (script version/tag, source-cab SHA-256 and size, scope inputs, observation stats), writes via `Save-CanonicalJsonFile` at SPEC §B.23 canonical JSON (depth=32). |

What is intentionally NOT yet wired up: the `Invoke-AdminPhaseA04_RefreshDependencyDatabase`
wrapper still throws `NotImplementedException` (its Phase 2b2 lifecycle
glue would chain Stage 1 → 2 → 3 → 4 with cache-management policy). The
A01.0 `RefreshAllBaselines` action does not yet call the parser
either. Both of those are Phase 2b2 scope.

**New offline test (`tests/wsusscn2_parser_test.py`, T12, ~220 lines)**:

22 assertions exercising:

- Fixture pre-flight: package.xml exists, contains zero Microsoft-prose tags (`<Title`, `<Description`, `<MoreInfoUrl`, `<Summary`, `<DefaultPropertiesLanguage`); expected-output.json structurally valid
- Stage 3 + Stage 4 happy-path: invokes pwsh, dot-sources the script, runs the pipeline against the fixture, parses the produced JSON
- Stats parity: `updatesObserved=6 / updatesInScope=3 / bundlesObserved=2 / categoryUpdates=1 / fileLocationsRetained=2 / payloadUrlsMissing=1`
- Scope-filter admit/reject: Server 2022 LTSC bundle + child admitted, Server 2025 LTSC bundle admitted, Office out-of-scope rejected (Product mismatch), 2022-vintage Server 2019 update rejected (recency cutoff), Category-Update record rejected (no Product/Classification refs in its own Categories block)
- Field-level correctness: `isBundle`, `kbArticleIds`, `productGuids` on the Server 2022 bundle
- Payload-URL join: child update's `payloadUrls` resolved via the FileLocations table; orphan digest (in `<Files>` but not in `<FileLocations>`) correctly omitted from the output
- Microsoft-prose absence in parser output (case-insensitive search for `"title"`, `"description"`, `"moreinfourl"` fields)
- Full structural compare against `expected-output.json` (env-stripped: `scriptVersion`, `scriptTag`, `generatedAt`, `sourceCab`)

Runs offline; no network access; no 7-Zip invocation; no real
wsusscn2.cab download. Stage 2 (`Invoke-WsusScnPackageXmlExtract`) is
platform-coupled (needs 7-Zip and Windows file layout) so it is
exercised only by the live monthly refresh CI workflow, not by T12.

**New fixture builder (`tests/common/wsusscn2_fixture_builder.py`, ~365 lines)**:

CLI + library Python helper that emits both `package.xml` and
`expected-output.json` into `tests/fixtures/wsusscn2/`. The fixture is
deliberately constructed (not derived from any real wsusscn2.cab) so
each Update tests a specific control-flow path in the parser; the GUID
namespace `f0000001-...` is reserved so the fixture cannot collide
with real wsusscn2 records.

**New committed fixtures (`tests/fixtures/wsusscn2/`)**:

| File | Size | Role |
|---|---:|---|
| `package.xml` | 3,312 bytes | Minimal Master XML covering 6 Updates (2 bundles, 1 child, 1 Category, 1 out-of-scope, 1 old in-scope) and 2 FileLocations |
| `expected-output.json` | 3,347 bytes | Canonical-JSON serialization of the expected parser output, env-stripped fields are placeholders |

Both files are deterministically regenerated by
`python3 -m tests.common.wsusscn2_fixture_builder` and `format gate`
verifies the JSON is canonical.

**Documentation updates**:

- `tests/README.md`: added T12 row to the Tool inventory table and a
  T12 row to the Quick start block. File layout updated to list
  `fixtures/wsusscn2/` and `wsusscn2_parser_test.py`.
- `README.md` / `README.ja.md`: T11 -> T12 in the Self-verification
  tools count, bilingual lock-step preserved.
- `TESTING.md`: §0 status table updated with T12 row.

**SPEC.md updates**:

- §B.19.9.4 *Implementation notes for the parser pipeline* added with:
  function signatures of Stages 2-4, the in-memory schema returned by
  Stage 3, the Layer 2 JSON schema written by Stage 4, the
  scope-filter rule, the allowlist enforcement of SPEC §B.19.8, and
  pointers to research §2.4.1 / §5.7 / §6.4.

### Quality gate

| Gate | Result |
|---|---|
| `psa.py` (PSA full rule set) | 0 errors, 0 warnings, 0 info |
| `PSScriptAnalyzer` (Settings.psd1) | 0 findings |
| Unit tests T2-T11 (no regression) | 138/138 passed (13+10+13+16+20+18+22+26) |
| **T12 (new)** | **22/22 passed** |
| Canonical JSON format gate | 26 passed (25 prior + 1 new `expected-output.json`) |
| Bilingual lock-step (README.md / .ja.md / TESTING.md) | preserved |

### r09.0 Step 2b1 preparation - WSUS Product Category GUID investigation and research documentation

This change is a **preparation step** for the Phase 2b1 parser pipeline
implementation. It does not modify `Update-WindowsServerIso.ps1` itself
(no production code change); instead it finalises the **WSUS Product
Category GUID inventory** that the upcoming Phase 2b1 scope filter
(`$Script:WsusScnOsCategoryGuids` and `$Script:WsusScnUpdateClassificationGuids`,
SPEC §B.19.7) will rely on. The investigation and its findings are
captured in the `research/` portable-knowledge tree so the GUID
inventory is auditable independently of the script body.

The motivation: SPEC §B.19.7 declares that the scope filter admits only
"SSU, LCU, .NET CU, or Dynamic Update" updates targeting Windows Server
2016 / 2019 / 2022 / 2025, judged by `Categories.Product` and
`Categories.UpdateClassification` GUID matching. Microsoft does not
publish a complete official table of Product GUIDs for the Server LTSC
family (the Classification side does have one). Phase 2b1 cannot be
authored safely without those values, so this step closes the gap with
a documented reverse-lookup methodology and a finalised reference table.

### What is in this commit

**Research documentation (bilingual, `research/windows-servicing/`)**:

Three new subsections added to the existing `windows-server-iso-update-mechanics.{ja,en}.md`
(675 → 824 lines on each side, bilingual lock-step preserved):

| § | Title (ja) | Role |
|:---|:---|:---|
| 2.4.1 | Category 階層の package.xml 内表現 | Methodology: how the WSUS Product hierarchy is implicitly embedded in `wsusscn2.cab`'s Master XML as `<Update>` elements with `DeploymentAction="Evaluate"` AND `IsSoftware="false"` markers; observed counts (4,199 Category Updates total, 154 directly under Windows ProductFamily) |
| 5.7 | scope filter の根拠となる Product GUID 一覧 | Canonical reference table: 4 Server LTSC Product GUIDs + 5 UpdateClassification GUIDs observed in the wsusscn2 fetched 2026-05-12; mapping of SSU / LCU / .NET CU / Dynamic Update to Classification |
| 6.4 | WSUS Product Category GUIDs と Server LTSC 系列の対応 | The naming-vs-GUID duality: display-name renames (§6.1, "Microsoft server operating system-21H2/24H2") do not affect GUIDs; canonical resolution paths (live WSUS, WUA API, wsusscn2 reverse-lookup, OSS cross-reference, Microsoft Learn) |

The same three subsections are added to the `.en.md` mirror with
matching structure and line numbers (824 lines, 0% line-count diff
between the bilingual pair).

**New test-infrastructure helper (`tests/common/`)**:

| File | Lines | Role |
|:---|---:|:---|
| `tests/common/wsusscn2_analyzer.py` | ~370 | Schema-discovery helper for `wsusscn2.cab`'s `package.xml`. Provides two-step 7-Zip extraction (subprocess-based, mirrors but does not couple to the production Stage 2 helper), tag-count census (parity with Phase 5 v4 observations), Category GUID frequency by Type, streaming `<Update>` / `<FileLocation>` iterators via `ElementTree.iterparse` (memory-safe on the 108 MB Master XML), Microsoft-prose absence check (SPEC §B.19.8 hard rule), and a CLI for manual exploration (`extract` / `summary` / `guids` / `prose` subcommands). Standard-library-only, pip-install-free, matches the existing `tests/common/` convention. Not yet wired to a test entry point — that lands in Phase 2b1 (T12). |

**Documentation updates (`tests/README.md`)**:

- File layout updated to include `common/canonical_json.py` (which
  Phase B1 introduced but never recorded in the layout block) and
  `common/wsusscn2_analyzer.py` (this commit). The Tool inventory
  table is unchanged because `wsusscn2_analyzer.py` is investigation
  infrastructure, not a T-numbered self-verification tool.

**Finalised GUID inventory (the central deliverable, recorded in `research/.../windows-server-iso-update-mechanics.ja.md` §5.7 as canonical)**:

Server LTSC Product GUIDs (scope filter targets):

| Server version | WSUS display name | Product GUID |
|:---|:---|:---|
| Server 2016 | Windows Server 2016 | `569e8e8f-c6cd-42c8-92a3-efbb20a0f6f5` |
| Server 2019 | Windows Server 2019 | `f702a48c-919b-45d6-9aef-ca4248d50397` |
| Server 2022 LTSC | Microsoft server operating system-21H2 | `71718f13-7324-4b0f-8f9e-2ca9dc978e53` |
| Server 2025 LTSC | Microsoft Server Operating System-24H2 | `ca006cfb-49eb-439b-880a-1312e1fc9713` |

> **Note (corrected later):** the Server 2025 GUID recorded here
> (`ca006cfb-...`) was found in Step 2b3 to be a stale 24H2-era
> category. The verified value is `b256987d-4693-4c87-955d-dbb9341205eb`.
> See the "Step 2b3" entry above and SPEC §B.19.9.7.

Server 2022 / 2025 GUIDs were finalised in this session via the
Category-hierarchy reverse-lookup methodology described in §2.4.1
(Category Update `CreationDate` matched with payload-URL build numbers:
build 26100 SSU → Server 2025 LTSC, ndp481 marker → Server 2022 LTSC).
Server 2016 / 2019 GUIDs are additionally cross-referenced against
`ansible/ansible` Issue 60785, `dsccommunity/UpdateServicesDsc` Issue
65, and the WSUSOffline forum.

### What is NOT in this commit (preserved for Phase 2b1 proper)

The production code (`Update-WindowsServerIso.ps1`) is **unchanged**:

- `$Script:WsusScnOsCategoryGuids` / `$Script:WsusScnCategoryGuidNameMap` / `$Script:WsusScnUpdateClassificationGuids` script-scope tables: not yet added (Phase 2b1 §1.3)
- `Invoke-WsusScnPackageXmlExtract` (Stage 2): not yet added (Phase 2b1 §1.4.1)
- `ConvertFrom-WsusScnPackageXml` (Stage 3): not yet added (Phase 2b1 §1.4.2)
- `New-WsusScnDependencyDatabase` (Stage 4): not yet added (Phase 2b1 §1.4.3)
- `tests/common/wsusscn2_fixture_builder.py`: not yet added (Phase 2b1 §1.2.2)
- `tests/wsusscn2_parser_test.py` (T12): not yet added (Phase 2b1 §1.5)
- `SPEC.md` §B.19.9.4 Implementation Notes: not yet added (Phase 2b1 §1.6.1)
- `ScriptVersion` / `ScriptTag`: unchanged (`update-wsi-2026.05.28-r09.0` /
  `step2a-followup-canonical-json-migration`); the next Phase 2b1
  commit will bump `ScriptTag` to `step2b1-parser-pipeline-and-fixture-tooling`.

The A04 wrapper (`Invoke-AdminPhaseA04_RefreshDependencyDatabase`)
keeps its `NotImplementedException` stub from Step 2a — its implementation
is scope of Phase 2b2, not Phase 2b1.

### Quality gate

This commit does not change PowerShell code, so the post-flight gates
that apply are:

| Gate | Result |
|:---|:---|
| `psa.py` (no PS change → no re-run needed; verified clean at baseline) | 0 / 0 / 0 |
| `PSScriptAnalyzer` (same as above) | 0 findings |
| Unit tests T2-T11 (no PS change) | unchanged from baseline (13/10/13/16/20/18/22/26) |
| Canonical JSON format gate (`tests/canonical_json_format_check.py`) | 25 passed (no new committed JSON files in this commit) |
| `tests/common/wsusscn2_analyzer.py` import smoke (Python) | PASS (`python3 -c "from tests.common import wsusscn2_analyzer"` clean) |
| Bilingual lock-step (`research/.../windows-server-iso-update-mechanics.{ja,en}.md`) | H2=13, H3=35, H4=4, 824 lines on each side (0.0% diff) |

### r09.0 Step 2a followup (Phase B2) - JSON canonical migration and format gate

This change applies the canonical JSON format declared in Phase B1
(SPEC Part B.23) to all 25 pre-existing JSON files in this subproject
and adds the Part C quality gate (§C.3.4) that prevents regression.
The change is large in line count but mechanical: no semantic content
is changed, only the formatter.

### What is in this commit

**File reformatting (25 files, byte-level mechanical change)**:

| Directory | File count | Source format | Net size delta |
|---|---:|---|---:|
| `data/` | 10 | PS 5.1 4-space, `":  "` separator, variable-width value alignment | **-414 KB** (-49% on average; the wins come from removing 53-space leading whitespace per array element) |
| `tests/fixtures/` | 10 | Python 2-space already (mostly canonical-compatible) | +537 bytes (one hand-formatted file `release_info_resolver/scenarios.json` had single-line short objects that canonicalise to multi-line) |
| `tests/snapshots/` | 5 | Python 2-space already | 0 bytes (already canonical-compatible) |

The `data/` size delta is the most visible: `cache-dotnet-cu.json`
267 KB → 110 KB, `cache-release-info.json` 402 KB → 216 KB. The
deletion is whitespace, not data; the JSON parse output of each file
before and after is structurally identical (verified by parse-then-compare
during the migration run).

**Source code changes (`Update-WindowsServerIso.ps1`, 12 sites)**:

The 12 `ConvertTo-Json` call sites that wrote to disk were replaced
with `Save-CanonicalJsonFile` (the SPEC §B.23.3 reference writer):

| Site | Previous pattern | Function |
|---|---|---|
| L3236 | `($x \| ConvertTo-Json -Depth 32) -replace ... + manual newline + WriteAllBytes` | `Save-OsConfig` |
| L3535 | same pattern, -Depth 8 | `Invoke-ReleaseInfoFetch` (raw meta) |
| L3860 | same pattern, -Depth 32 | `Update-ReleaseInfoCache` |
| L4366 | same pattern, -Depth 12 | `Invoke-DotNetCuFetch` (raw aggregate) |
| L4433 | same pattern, -Depth 32 | `Update-DotNetCuCache` |
| L4589 | same pattern, -Depth 12 | `Set-DynamicUpdateCachePersistFunc` |
| L10095 | `WriteAllText` + `-replace` + manual `+ "\n"` | `Save-ValidationSummary` |
| L10136 | same | `Save-WsusScnScanRaw` |
| L10172 | same | `Save-DependencyGraph` |
| L11225 | `ConvertTo-Json \| Set-Content -Encoding UTF8 -Force` | `Pca2023OnlyMode` (pcaDir) |
| L12006 | `Set-Content -NoNewline + Add-Content "\n"` | `Invoke-AdminPhaseA02_DumpFieldClassification` |
| L12879 | `ConvertTo-Json \| Set-Content -Encoding UTF8 -Force` | `Pca2023OnlyMode` (scratch) |

The 8 `-Compress` call sites (debug trace, HTTP body, TestHarness
protocol, before/after diff logging) and the 1 clone-idiom site
(`ConvertTo-Json \| ConvertFrom-Json` for deep copy) were left as
raw `ConvertTo-Json` because they intentionally produce single-line
or non-canonical output that the SPEC Part B.23 rules do not cover.
The debug trace Export at L1540 also writes UTF-8 **with BOM** by
design (so a Japanese ConsoleHost can read it back); this is
incompatible with canonical (no-BOM) and is correctly left alone.

ScriptVersion stays `update-wsi-2026.05.28-r09.0`; ScriptTag changes
from `step2a-followup-canonical-json-helpers` to
`step2a-followup-canonical-json-migration`.

**New Part C quality gate**:

- `tests/canonical_json_format_check.py` (~140 lines, new): walks
  `data/`, `tests/fixtures/`, and `tests/snapshots/`; re-serialises
  every `*.json` through `canonical_json_dumps`; fails the gate if any
  file's bytes diverge. Useful diagnostic on failure: shows first
  differing byte offset with surrounding context, plus the remediation
  hint pointing at `Save-CanonicalJsonFile` / `save_canonical_json_file`.

**SPEC.md updates**:

- §B.23.6 rewritten: removed the "migration window" framing; the
  invariants now read as steady-state rules. The explicit out-of-scope
  list (`Workspace_UpdateWsi/`, `-Compress` debug traces,
  `.psa.config.json`) is recorded normatively so future LLM agents and
  human reviewers do not accidentally widen the scope.
- §C.3.4 added: format-compliance gate that consumes the new
  `tests/canonical_json_format_check.py`.

**`tests/README.md`**: T11 entry already present; added a row for the
new format check script in the Tool inventory table and a line in the
Quick start block.

### Quality gate

- `psa.py`: 0 errors / 0 warnings / 0 info (12,987 lines analysed)
- `psa.py --include PSA1004,PSA2012,PSA2013`: 0 / 0 / 0
- `PSScriptAnalyzer` with project settings: 0 findings
- `pwsh -ParseFile`: Parse OK
- T2 (catalog_fixture_test): 13 passed / 0 failed
- T3 (powershell_harness): 10 passed / 0 failed
- T6 (release_info_parser_test): 13 passed / 0 failed
- T7 (dotnet_cu_parser_test): 16 passed / 0 failed
- T8 (dynamic_update_cache_test): 20 passed / 0 failed
- T9 (catalog_title_tokens_test): 18 passed / 0 failed
- T10 (release_info_resolver_test): 22 passed / 0 failed
- T11 (canonical_json_test): 26 passed / 0 failed
- **canonical_json_format_check (Part C gate, NEW): 25 passed / 0 failed**

### Verification of the structural equivalence

Each of the 25 reformatted files was parsed before and after the
conversion and the resulting Python object tree was compared. All 25
files parsed equal-after-equal-before, confirming the change is
formatter-only (no semantic shift).

### Cross-references

- SPEC.md §B.23 (the canonical format, declared in Phase B1; no
  rule changes in this commit, only the §B.23.6 migration text)
- SPEC.md §C.3.4 (the new format gate)
- AGENTS.md §2 sibling-isolation policy: this change is still scoped
  strictly to `scripts/powershell/update-windows-server-iso/`. No file
  in any other subproject is touched.
- AGENTS.md §9 AP-8 (downstream propagation): the gate, the SPEC
  amendments, the test README row, the source code replacements, and
  the file reformatting all ship in this single commit.

### r09.0 Step 2a followup - JSON Canonical Serialization helpers and SPEC Part B.23

This change adds two PowerShell helpers, a Python reference module, a
SPEC Part B.23 normative section, and a new offline regression test
(T11) that together establish a byte-level parity contract between
Linux PowerShell 7.x and Linux Python 3.10+ for every JSON file under
`data/` and `tests/fixtures/`. **No existing JSON files are migrated
in this commit**; the format check itself ships now, and the
mechanical migration of the 25 existing JSON files is the next step
(see "What is NOT in this commit" below).

The motivation is the format drift discovered during r09.0 Step 2a:
the `data/config-Server*.json` files are in a PowerShell 5.1
`ConvertTo-Json` format (4-space indent, `":  "` key/value separator,
variable-width value alignment) that PowerShell 7.x on Linux cannot
reproduce. Any edit to a `data/*.json` file from a Linux runtime
therefore generates a whole-file reformat in the git diff, drowning
the semantic change in noise. The new helpers fix this by declaring
a single canonical format that PS 7 and Python 3 can both emit
byte-for-byte.

### What is in this commit

- **`SPEC.md` Part B.23** (~200 lines, new):
  - §B.23.1 Motivation (format drift identification)
  - §B.23.2 The 10 normative format rules
  - §B.23.3 PowerShell reference implementation (function signatures
    and caller obligations)
  - §B.23.4 Python reference implementation (function signatures and
    caller obligations)
  - §B.23.5 Byte-level parity contract (the normative cross-runtime
    guarantee)
  - §B.23.6 Migration policy from legacy formats

- **`Update-WindowsServerIso.ps1`** (+130 lines, new section
  immediately after the 7-Zip helper block):
  - `ConvertTo-CanonicalJson` — pipeline-friendly wrapper over
    `ConvertTo-Json -Depth $Depth` with three corrections for byte
    parity with Python: CRLF→LF normalisation, scientific-notation
    `E`→`e` lowering, and a trailing-newline policy switch
  - `Save-CanonicalJsonFile` — atomic-ish file writer that uses
    `[System.IO.File]::WriteAllBytes` with a no-BOM UTF-8 encoder so
    LFs survive without platform translation
  - ScriptVersion remains `r09.0`; ScriptTag changes from
    `step2a-sevenzip-port-and-a04-stub` to
    `step2a-followup-canonical-json-helpers`

- **`tests/common/canonical_json.py`** (~170 lines, new):
  - `canonical_json_dumps` — Python reference implementation
  - `save_canonical_json_file` — Python file writer
  - `_assert_depth` — pre-serialisation depth check to give the same
    error class as the PowerShell `-Depth` over-limit case

- **`tests/canonical_json_test.py`** (T11, ~220 lines, new):
  - 26 assertions covering primitives (12), collections (8), Unicode
    (3), real-world `data/*.json` shapes (2), and file-level save (1)
  - Drives the PowerShell side through the existing `PSSession`
    TestHarness REPL (no new test infrastructure)

- **`tests/README.md`** (+2 lines):
  - T11 row in the Tool Inventory table
  - T11 line in the Quick Start example block

### What is NOT in this commit

The following are scoped to the next change cycle (a Phase B2
follow-up), explicitly NOT shipped here so the format and helpers
can be reviewed in isolation:

- The 27 existing `ConvertTo-Json` call sites in
  `Update-WindowsServerIso.ps1` are not yet migrated to
  `ConvertTo-CanonicalJson`.
- The 25 existing JSON files under `data/` and `tests/fixtures/`
  are not yet reformatted to canonical. Their current formats
  (PS 5.1 4-space for `data/*.json`, Python 2-space for
  `tests/fixtures/*.json`) are documented in §B.23.6 as the
  "migration window" baseline.
- The Part C quality-gate format check
  (`tests/canonical_json_format_check.py`) that walks both
  directories and fails on any non-canonical file is described in
  §B.23.6 but not yet implemented; it lands in the same change
  cycle as the mechanical migration.

### Rationale for the split

Phase B1 (this commit) ships the contract and the tools so reviewers
can examine the format rules, the helper signatures, and the byte
parity test in isolation. Phase B2 (next) applies the contract
mechanically to the 25 existing files in one large but
straightforward diff. Bundling the two together would have produced
~1,500 lines of mixed contract change + mechanical reformat, defeating
reviewer focus.

### Quality gate

- `psa.py`: 0 errors / 0 warnings / 0 info (13,009 lines analysed)
- `psa.py --include PSA1004,PSA2012,PSA2013`: 0 / 0 / 0
- `PSScriptAnalyzer` with project settings: 0 findings
- `pwsh -ParseFile`: Parse OK
- T2 (catalog_fixture_test): 13 passed / 0 failed (unchanged baseline)
- T3 (powershell_harness): 10 passed / 0 failed (unchanged baseline)
- T6 (release_info_parser_test): 13 passed / 0 failed (unchanged baseline)
- **T11 (canonical_json_test, NEW): 26 passed / 0 failed**
- TestHarness smoke test: `ConvertTo-CanonicalJson` returns the
  expected JSON via the harness REPL

### Cross-references

- SPEC.md §B.23 (normative format rules and parity contract; new in
  this commit)
- AGENTS.md §2 (sibling-isolation policy: this change is scoped to
  the `update-windows-server-iso` subproject; promotion to a
  Layer 0/1 rule or to the canonical PowerShell SPEC for other
  PowerShell subprojects is intentionally NOT in scope here and
  will be proposed separately under operator approval)
- AGENTS.md §9 AP-3 (inheritance via copy-paste: future ports to
  other subprojects, if approved, should be tracked as verbatim
  copies of these two functions, not as independent rewrites)
- AGENTS.md §9 AP-7 (out-of-scope sibling modification: no files
  under `scripts/powershell/download-speakerdeck-oracle4engineer/`
  or any other sibling are touched by this commit)
- AGENTS.md §9 AP-8 (documentation-only updates without downstream
  propagation: SPEC §B.23 ships together with the helpers, T11, and
  tests/README.md row in this single commit)

### r09.0 Step 2a - 7-Zip helper port, A04 stub, and Server 2016 SSU dependency config fix

This Step 2a ships a **scope-limited code change** that lays the
foundation for the full Servicing Dependency Database parser shipping
in r09.0 Step 2b. Three concrete deliverables ride in this commit:

1. The three 7-Zip helper functions (`Get-SevenZipPath`,
   `Get-LatestSevenZipUrl`, `Install-SevenZipFallback`) are ported
   from the sister project Deploy-AMDChipsetDriverOnWindowsServer.ps1
   with the two unavoidable logger renames documented in SPEC
   §B.19.4.4. These are the CAB-extraction prerequisites for the
   Stage 2 parser function that lands in Step 2b.
2. A new `-Action RefreshDependencyDatabase` Action is registered:
   `param()` ValidateSet entry, `$Script:PhaseRegistry` A04 entry,
   `Get-PhaseListByAction` switch case, `$osLessActions` membership,
   and a wrapper function `Invoke-AdminPhaseA04_RefreshDependencyDatabase`
   that throws `NotImplementedException` with an operator-actionable
   message pointing at SPEC §B.19.15.3. The registration ships in
   Step 2a so the public API contract (param surface, phase listing)
   is atomic with respect to the parser implementation; Step 2b
   replaces the wrapper body without changing any of the public
   integration points.
3. `data/config-Server2016.json` is corrected for the r08.0 Step 4d
   finding (the diagnosis that closes the r08.0 cycle on this OS):
   - `KB5088064` (2026-05 SSU) added as a new NeutralPatches entry
     with `ApplyOrder=1` (placed before the LCU's ApplyOrder=3) and
     the new `_DependencyVerifiedSource: "manual-r09-step2a"` field
     to mark its provenance per SPEC §B.19.12.1.
   - `KB5087537` LCU's `IsCombined: true` is corrected to `false`
     (r08.0 Step 4d evidence: `addpkg.log` confirms standalone LCU,
     not Combined LCU+SSU as the field had stated).
   - `KB5087537` LCU's `RequiresKbIds: []` is populated with
     `["KB5088064"]`, declaring the SSU prerequisite that previously
     caused the HRESULT `0x800f0823` failure on Server 2016 Build runs.

The change set explicitly does **not** ship the parser pipeline
(SPEC §B.19.9), the Layer 2 JSON schema (SPEC §B.19.10), the
`Test-PatchDependencyClosureFromGraph` verifier (SPEC §B.19.13),
nor the P06 Stage 2 split (SPEC §B.19.14). Those four deliverables
are intentionally bundled into r09.0 Step 2b so the parser and its
consumer land together; shipping them piecewise would leave the
script in an "API present but does nothing" state.

### Rationale

Splitting r09.0 Step 2 into Step 2a (this commit) and Step 2b (next)
follows the implementation-size guidance derived during planning:
the full Step 2 scope (~1,300-1,900 lines of additions across parser,
tests, A04 implementation, P06 Stage 2 split) is too large for one
revision to land cleanly with the Self-Check Gates AGENTS.md §8
demands. Step 2a's 78-line + 50-line additions are individually
small, but each is a fully-tested, atomic deliverable that improves
the script's behaviour on Server 2016 immediately — even before
the parser arrives.

The Server 2016 config correction (item 3 above) closes the r08.0
Step 4d investigation on this OS: an operator running r08.0 had to
manually understand the 0x800f0823 error, read addpkg.log, and
hand-edit the config to add KB5088064. After Step 2a, the same
config arrives shipped-correct, and the LCU's IsCombined / RequiresKbIds
fields document the dependency for the next operator. The remaining
gap (auto-discovery of dependencies for newly-released LCUs) is what
Step 2b's parser closes.

### Changed files

- `Update-WindowsServerIso.ps1` (+128 lines)
  - L538-539: ScriptVersion `r08.0` → `r09.0`; ScriptTag
    `fix-subphase-patch-classification` → `step2a-sevenzip-port-and-a04-stub`
  - L243: `param()` ValidateSet adds `RefreshDependencyDatabase`
  - L392: `$osLessActions` adds `RefreshDependencyDatabase`
  - L588 (new): `$Script:PhaseRegistry` adds A04 entry
  - L6737-6816 (new): 7-Zip helpers section (3 functions + section banner)
  - L12247-12297 (new): `Invoke-AdminPhaseA04_RefreshDependencyDatabase` stub
  - L12274 (new): `Get-PhaseListByAction` switch adds `RefreshDependencyDatabase` case
  - L12293: `Show-PhaseList` Actions list adds `RefreshDependencyDatabase`
- `data/config-Server2016.json` (+22 lines)
  - NeutralPatches[0] (new): KB5088064 SSU entry
  - NeutralPatches[1] (existing, fields updated): KB5087537 IsCombined corrected,
    RequiresKbIds populated, `_DependencyVerifiedDate` / `_DependencyVerifiedSource`
    / `_Notes` fields added per SPEC §B.19.12.1
- `SPEC.md` (+27 lines)
  - §B.19.4.4 (new): Implementation notes for the Deploy-AMD port

### Quality gate

- `psa.py`: 0 errors / 0 warnings / 0 info (12,879 lines analysed)
- `psa.py --include PSA1004,PSA2012,PSA2013`: 0 errors / 0 warnings / 0 info
- `PSScriptAnalyzer` with project settings: 0 findings
- T2 (catalog_fixture_test): 13 passed / 0 failed
- T3 (powershell_harness): 10 passed / 0 failed
- T6 (release_info_parser_test): 13 passed / 0 failed
- `pwsh -ParseFile`: Parse OK
- `-Action ListPhases` smoke test: A04 / RefreshDependencyDatabase entry visible in phase registry and Actions list
- `-Action RefreshDependencyDatabase` smoke test: NotImplementedException raised with operator-actionable message naming SPEC §B.19.15.3 and listing pending Step 2b work

### Cross-references

- SPEC.md §B.19.4 (7-Zip strategy, including new §B.19.4.4 Implementation notes)
- SPEC.md §B.19.12.1 (NeutralPatches `_DependencyVerified*` fields)
- SPEC.md §B.19.15.3 (A04 RefreshDependencyDatabase action)
- AGENTS.md §9 AP-2 (registered-but-not-implemented avoidance: stub raises a
  clear NotImplementedException rather than silently no-op)
- AGENTS.md §9 AP-3 (inheritance via copy-paste: the Deploy-AMD port
  is documented as a verbatim copy with two unavoidable logger renames,
  not as new code disguised as a sibling pattern)
- AGENTS.md §9 AP-5 (no inline revision tags: the new function bodies
  carry no `r09:` / `r09.0+` markers; revision context lives in this
  CHANGELOG entry only)
- `research/windows-servicing/windows-server-iso-update-mechanics.{en,ja}.md`
  §5.3 (SSU-LCU pairing problem, the failure mode this config fix
  prevents) and §7.2 (expand.exe self-overwrite, the reason 7-Zip
  is required)

### r09.0 Step 10 (docs-only) - docs/ retirement and knowledge promotion to `research/windows-servicing/`

This Step 10 ships a **docs-only** change: the entire contents of
`scripts/powershell/update-windows-server-iso/docs/` are promoted out
of the subproject and into the repository's top-level `research/`
category as a single bilingual reference article. **No code is
changed in this or the follow-up commit**. The technical knowledge
accumulated across r06.0 / r07.0 / r08.0 / r09.0 investigation
cycles — release-info Markdown source semantics, .NET CU release
notes, Microsoft Update Catalog naming quirks, `wsusscn2.cab` Master
XML structure, PCA2023 Secure Boot migration mechanics, install.wim
cross-version asymmetry, Servicing Stack dependency model, and
operational hazards (mojibake, expand.exe self-overwrite, signtool
exit-code-1, `List[object]+@()`) — has been synthesized into a
single research article suitable for any practitioner building
similar tooling, independent of this subproject's specific
implementation.

### Restructure summary

- **New article (this commit)**: `research/windows-servicing/`
  - `windows-server-iso-update-mechanics.en.md` (675 lines)
  - `windows-server-iso-update-mechanics.ja.md` (675 lines)
  - Bilingual lock-step: H2=13, H3=33 in both languages.
  - Body is fully generic: no references to `Update-WindowsServerIso.ps1`,
    phase numbers (P05–P13), revision tags (r07.0/r08.0/r09.0), or
    SPEC section identifiers. Provenance to this subproject is
    confined to Appendix C.
- **Follow-up commit will delete** the entire
  `scripts/powershell/update-windows-server-iso/docs/` directory
  (12 files, 4561 lines total: `README.md` + `history/` containing
  `dotnet-cu-report.md`, `dynamic-update-report.md`,
  `mojibake-investigation-note.md`, `r07.0-followups.md`,
  `r08.0-step1-server2016-pca2023-finding.md`,
  `r08.0-step2-installwim-symmetry-check.md`,
  `r08.0-step3-output-verification-and-build.md`,
  `r08.0-step4-findings-and-dependency-investigation.md`,
  `r09.0-step1-phase5-summary.md`, `release-info-readme.md`,
  `release-info-report.md`).

### Rationale

The `docs/` subdirectory had grown to mix two distinct kinds of
content: (a) revision-specific work logs ("what did we find in
r08.0 Step 2?") and (b) durable technical knowledge ("how does
Microsoft serve patch metadata via release-info Markdown?"). The
former has decreasing value over time and is better recovered via
git history; the latter is broadly useful to any Windows servicing
practitioner and was buried inside this subproject where external
readers could not find it. The promotion to `research/` makes the
durable knowledge discoverable to the wider reader base while
acknowledging that revision-specific debugging notes are not the
right artifact to maintain forever.

The choice of `research/` over `documents/` follows the top-level
category policy (`research/README.md`): the article is a "reading
notes synthesized from multiple sources" investigation, not a
specific recommendation/plan/design for a particular scenario.

### Cross-references

- New article: `research/windows-servicing/windows-server-iso-update-mechanics.{en,ja}.md`
- Top-level category guidance: `research/README.md`
- Subproject retains its own `SPEC.md` and `README.md` as the
  source-of-truth for tool-specific behaviour; the research article
  is a cross-cutting concern map, not a user manual.

### r09.0 Step 1 (Phase 6, SPEC-only) - SPEC.md restructure to Part A/B/C/D standard form + Servicing Dependency Database normative specification

This Step 1 Phase 6 ships a **SPEC-only** change: a comprehensive
rewrite of `SPEC.md` that restructures the previous nine-Part layout
(A through I) into the repository-standard four-Part layout (A, B, C,
D) with three appendices (E, F, G). **No code is changed in this
commit**. The implementation work (parser, layer 2 schema, P06
Stage 2 wiring) follows in subsequent r09.0 Steps per the rollout
plan in §B.19.19.1.

### Restructure summary

- **Part E (Roadmap) deprecated**: replaced by CHANGELOG +
  per-cycle followup files; remaining roadmap content moved to
  Appendix G.2.
- **Part F (Function Reuse Map) → Appendix E**: same content,
  Appendix scope.
- **Part G (Self-verification tools) → Part C.9**: merged into
  the Quality Gates Part where the suite conceptually belongs.
- **Part H (Reference Projects) → Appendix F**: slimmed and
  cross-referenced from README.
- **Part I (Servicing Dependency Database, r09.0+) → Part B.19**:
  integrated as a Script-Specific subsection per the Part B/Part I
  Q2 design decision; the layer-2 schema, parser pipeline, and
  P06 integration are now in their natural location alongside the
  other phase-related contracts.
- **B.14b (out-of-sequence) absorbed into §B.4.3**: the
  PatchBaseline schema fields are now part of the OS profile
  schema section.
- **B.23 (Phase 3 Architecture, 24-subsection narrative)
  condensed**: replaced by §B.22 in decision-record form
  (B.22.1–B.22.21). The historical narrative is preserved in
  CHANGELOG.

### New normative content (Part B.19)

§B.19 (Servicing Dependency Database) is fully rewritten to reflect
the Phase 5 PoC findings:

- **B.19.4 7-Zip strategy** (Phase 5 D1): explicit choice of 7-Zip
  over in-box `expand.exe` / `Shell.Application`, with three-helper
  function trio reused from `Deploy-AMDChipsetDriverOnWindowsServer.ps1`.
- **B.19.5 Dual-source structure** (Phase 5): explicit
  acknowledgement that update-relationship metadata is split between
  the Master XML and individual `package*.cab` fragments; r09.0
  consumes Master XML only, with the per-cab parse explicitly
  out of scope.
- **B.19.6 Master XML schema as observed** (Phase 5 v3/v4): the
  full observed schema with Bundle / Standalone / SupersededBy
  shapes, including the empirically-confirmed 14,059 SupersededBy
  occurrences and zero forward-direction tags.
- **B.19.7 / B.19.8 Scope filter + Microsoft-prose exclusion**:
  hard rules that bound layer 2 to ~2–5 MB and keep it free of
  Microsoft creative content.
- **B.19.9 Parser pipeline** (4-stage with XmlReader streaming,
  Phase 5 D3): peak working set < 50 MB vs. +536 MB for
  XmlDocument.Load.
- **B.19.10 Layer 2 JSON schema** (Phase 5 final): the canonical
  shape including `Variants[]` + `RevisionIndex` (for resolving
  `<SupersededBy>` references that use RevisionId integers, not
  UpdateId GUIDs).
- **B.19.13 Verification API**: `Test-PatchDependencyClosureFromGraph`
  signature and its complementary relationship to the existing
  mount-time `Test-PatchDependencyClosureOnMount`.
- **B.19.14 P06 ValidatePatchSet integration**: two-stage P06 with
  independent skip conditions for catalog freshness (Stage 1) and
  dependency closure (Stage 2).
- **B.19.15 Lifecycle**: new Action A04 `RefreshDependencyDatabase`
  plus a new A01.0 sub-phase inside RefreshAllBaselines.
- **B.19.16 Air-gapped operation**: `-OfflineCabPath` parameter
  for environments without CDN access.
- **B.19.18 Maintainer operations guide**: monthly refresh
  procedure and PR review checklist.

### New Lessons Learned (Part D.24-D.30)

Seven new entries codify meta-lessons from the r07.0/r08.0/r09.0
cycles:

- **D.24 Cognitive bias patterns** — Hypothesis lock-in, sampling
  treated as comprehensive, solution attraction. Four mitigations
  pre-committed as the Engineering Hygiene Quartet.
- **D.25 DISM mount-cache poisoning** — Root cause of the
  r07.0 Step 16/17 mojibake; mitigation is fresh WorkRoot per OS
  family.
- **D.26 `List[object]` of pscustomobject argument-type mismatch**
  — Root cause of the r08.0 Step 2 `Argument types do not match`
  failure; `.ToArray()` is the safe alternative.
- **D.27 Microsoft OS tool dependency avoidance** —
  `expand.exe -F:` brittleness; `Make2023BootableMedia.ps1` precedent
  for inheriting Microsoft logic without inheriting the
  implementation; 7-Zip choice for r09.0 wsusscn2 parser.
- **D.28 Sampling versus comprehensive search** — 2-3 element
  exemplar walks are not representative for low-base-rate
  phenomena. Exhaustive `Select-String` on a 108 MB file is
  always cheaper than being wrong.
- **D.29 Code bug versus configuration problem triage** — A
  one-question filter to apply at the top of every failure
  investigation, prompted by the r08.0 Step 4d near-miss.
- **D.30 Helper function unification** — `Get-PatchEntryType` as
  the response to the dual-field-name drift; sweeps are fragile,
  helpers are forever.

### New stable identifier conventions

- **Policy IDs** of the form `SPEC-WSI-NNN` parallel the
  `SPEC-CI-NNN` IDs in the repository-level SPEC. The Policy Index
  table at the top of SPEC.md maps each Policy ID to the section
  that defines it.
- **Section IDs** `B.N.M` and `D.NN` are formally declared
  stable: once assigned, never reused.
- **Normative / informative tagging**: every section is tagged
  explicitly so an LLM agent reading the SPEC knows which rules
  carry contractual obligation and which are background.

### Document scope and language

- This SPEC continues to be English-only per the repository
  Language Policy (root `README.md` "Language Policy").
- The file format remains UTF-8 / LF / no BOM per the Markdown
  contract in the root `README.md` "File Format Policy".
- File line count: 5,074 (old) → 3,935 (new); a 22% reduction
  achieved while adding ~1,000 lines of new normative content
  in §B.19 and ~700 lines of new D.24-D.30 lessons. The net
  reduction comes from condensing the legacy Part B.23 24-
  subsection narrative into decision-records and from removing
  the redundancy between Part F/G/H and other Parts.

### No code change

`Update-WindowsServerIso.ps1` is **unchanged** in this commit.
`$Script:ScriptVersion` and `$Script:ScriptTag` are unchanged. CI
quality gates (psa.py / PSScriptAnalyzer / T2/T3/T6) are unaffected
by this commit because the source file is not touched. The next
r09.0 Step will begin implementing the §B.19 specification; that
Step ships with the corresponding code changes and a fresh
ScriptVersion bump.


### r08.0 Step 4 series - cumulative code bug fixes + SPEC Part I (Servicing Dependency Database) specification

This Step 4 series spans three connected modes:

1. **Step 4a/4b/4c — Code bug fixes**: cumulative bug-fix work
   uncovered while running the first real `Build -Execute` against
   Server 2016 ja-jp EVAL ISO post r08.0 Step 3. Four distinct bugs
   were found across the PatchType handling, ReadOnly attribute,
   Transcript lifecycle, and Export-DebugTraceJson invocation paths.
   These fixes have been validated on Windows PowerShell 5.1 Desktop
   on Server 2025 and pass all quality gates, and have been
   committed separately as `84d840e` (Step 4a) and `df89c6f`
   (Step 4b/4c combined). Server 2016 Build -Execute itself
   remains blocked on the SSU prerequisite uncovered in Step 4d
   (see below).

2. **Step 4d — Servicing Stack dependency investigation**: after
   Step 4c, `Add-WindowsPackage` failed with
   `0x800f0823 CBS_E_NEW_SERVICING_STACK_REQUIRED`. Investigation
   established this is a configuration problem (missing KB5088064 SSU
   entry in `config-Server2016.json`), not a code bug. The investigation
   record is captured in
   `docs/history/r08.0-step4-findings-and-dependency-investigation.md`.

3. **SPEC Part I (Servicing Dependency Database)** — the design
   specification for resolving the class of failures uncovered in
   Step 4d. This commit ships the Part I spec only; implementation
   is deferred to r09.0.

`ScriptVersion`: `update-wsi-2026.05.27-r08.0` (unchanged, same day; spec-only revision)

**SPEC.md additions**.

- New **Part I — Servicing Dependency Database (r09.0+, normative)**
  added at the end of SPEC.md (~960 lines). Defines:
    - I.1: Goals — eliminate the "discover prerequisite failure at
      P07 mid-mount" anti-pattern; pull failure detection forward
      to P06 with Microsoft-authoritative data.
    - I.2: Three-layer architecture:
      - Layer 1 = `data/config-Server*.json` (per-OS summary embedded
        into `PatchBaseline.NeutralPatches[*]`, git-tracked).
      - Layer 2 = `data/wsusscn2-database.json` (aggregated facts-only
        extract from wsusscn2.cab, ~2-5 MB, git-tracked, NO Microsoft
        prose).
      - Layer 3 = `<WorkRoot>/cache/wsusscn2/` (raw ~1 GB
        `wsusscn2.cab`, gitignored).
    - I.3: Data source — CDN URL, monthly cadence, package.xml
      schema observations.
    - I.4: Lifecycle — `RefreshAllBaselines` extension + new
      `-Action RefreshDependencyDatabase` (touches only layer 3).
    - I.5: File layout, gitignore additions, audit-archive
      retention policy (rolling 6 months), layer 2 size monitoring
      target.
    - I.6: Extraction logic — L2c implementation tier, scope filter
      (Server 2016/2019/2022/2025 + SSU/LCU/.NET CU/DU, 24-month
      window), the strict Microsoft-prose exclusion rule, full JSON
      schema for `wsusscn2-database.json`.
    - I.7: Layer 1 integration — `RequiresKbIds`, `Supersedes`,
      `RequiresMinimumOsBuild`, `IsCombined` (auto-overwrite by
      tool), semi-automatic policy on KB add/remove.
    - I.8: New `Test-PatchDependencyClosureFromGraph` function spec
      (the P06-side complement to the existing P07-side
      `Test-PatchDependencyClosureOnMount` from B.13).
    - I.9: P06 ValidatePatchSet redesign — split into Stage 1
      (catalogue freshness, skippable via `-UseBaselineOnly` as
      today) and Stage 2 (dependency closure verification, runs even
      under `-UseBaselineOnly`, new `-SkipDependencyCheck` flag for
      explicit opt-out).
    - I.10: Air-gapped operation — committed layer 2 enables
      verification without network access; new `-OfflineCabPath`
      parameter for manually-supplied wsusscn2.cab regeneration.
    - I.11: New `_DependencyVerifiedDate` /
      `_DependencyVerifiedSource` fields (parallel to existing
      `_VerifiedDate` / `_VerifiedBy`; tool-managed vs human-managed
      provenance tracked as independent dimensions).
    - I.12: Maintainer monthly-refresh procedure, PR review
      checklist.
    - I.13: Rollout / backward compatibility — strict superset of
      r08.0 behaviour; missing layer 2 falls back gracefully to
      existing B.13 logic with WARN.
- Table of Contents updated to include the new Part I entry.
- Part E milestone M3's "Done (r02)" claim is now formally
  superseded by Part I; the Part I header explicitly notes the
  M3 entry was a placeholder claim that was never implemented
  beyond the schema slot. Part E itself remains as the roadmap
  table; M3 status is corrected in spirit by the new Part I,
  but no edit to the Part E table is made in this commit (Part E
  is retained as-is for historical traceability).

**Documentation additions**.

- New `docs/history/r08.0-step4-findings-and-dependency-investigation.md`
  (~435 lines). Captures:
    - The four code bugs found and fixed in Step 4a-c (ReadOnly
      attribute, PatchType field-name drift across 6 call sites,
      Export-DebugTraceJson parameter name, Transcript lifecycle).
    - The Step 4d investigation: addpkg.log analysis pinpointing
      `Package_for_RollupFix~31bf3856ad364e35~amd64~~14393.9140.1.19
      requires Servicing Stack v10.0.14393.7692 but current is
      v10.0.14393.693`; cross-reference against Microsoft Update
      Catalog establishing KB5088064 as the canonical SSU
      prerequisite for KB5087537; identification of the
      `IsCombined: true` misclaim in `config-Server2016.json` as
      a manual-config integrity failure.
    - The Part I design discussion record: all nine design
      decisions (lifecycle, three-layer structure, scope,
      placement, phase integration, plus six sub-decisions) and
      the reasoning behind each.
    - Lessons-learned section: "code bug vs configuration
      problem" early triage, helper-function unification to
      prevent logic drift, spec-first approach for compound
      problems.

**What this commit does NOT change**.

- `Update-WindowsServerIso.ps1` is unchanged in this specific
  commit. The Step 4a/4b/4c code fixes were committed
  independently to `main` as `84d840e` and `df89c6f` prior to
  this spec-only revision.
- `config-Server*.json` files are unchanged. The `IsCombined:
  true` misclaim on KB5087537 is documented in the findings doc
  but not yet corrected, pending the decision above.
- No tests changed (Part I is spec-only; tests will be added
  during r09.0 implementation).

**Quality gates** (SPEC.md / docs only changes).

- Markdown files validate cleanly.
- No PowerShell file changes in this revision; psa.py / PSScript­
  Analyzer / T2/T3/T6 status carries forward unchanged from
  r08.0 Step 3.

---

### r08.0 Step 3 - Test-OutputIsoPca2023Readiness function and P10/P12/P13 integration

This release adds the output-side post-build verification function
that was designed during r08.0 Step 2 but deferred when a PowerShell
type-inference issue could not be resolved within the prior session
budget. Step 3 root-causes the issue (a `List[object]` of
`pscustomobject` elements cannot be materialised with the `@()`
operator under PowerShell 7.4.x; `.ToArray()` is the safe
alternative) and ships the function with full integration into
the existing PCA2023 readiness phases. This closes the highest
priority item raised in SPEC.md §B.24.6.

`ScriptVersion`: `update-wsi-2026.05.27-r08.0` (unchanged, same day)
`ScriptTag`    : `promote-enable-flags-for-build-phases` -> `add-output-iso-pca2023-verification`

**New function**.

- `Test-OutputIsoPca2023Readiness` (~290 lines) verifies an extracted
  OUTPUT-ISO directory against the five conversion targets documented
  in §B.18 (the Microsoft `Make2023BootableMedia.ps1` v1.4
  `Copy-2023BootBins` table):
    - Target #1 (`\efi\boot\bootx64.efi` or `bootaa64.efi`):
      PCA2023 -> Pass; PCA2011 or missing -> Fail
    - Target #2 (`\bootmgr.efi`): any signer or missing -> PassWithNotes
      (encodes the Microsoft-design PCA2011 status from L876-L884)
    - Target #3 (`\efi\microsoft\boot\efisys_ex.bin`):
      present -> Pass; missing -> Fail
    - Target #4 (`\efi\microsoft\boot\fonts\*.ttf`):
      present -> Pass; missing or empty -> Warning
    - Target #5 (`\EFI\Microsoft\Boot\boot.stl`):
      present -> Pass; missing -> PassWithNotes
- OverallStatus aggregation: Fail > Warning > PassWithNotes > Pass.
- The `Reasons[]` array always appends a SCOPE clarifier identifying
  that the in-tree check verifies file presence + signer chain only,
  and that an actual boot test on PCA2011-revoked firmware (hardware
  or Hyper-V Gen2 VM with custom Secure Boot template) is required
  before production deployment.
- The function is strictly READ-ONLY: no DISM mounts, no registry
  hive loads, no signtool invocations. Only `Test-Path` and
  `Get-AuthenticodeSignature` against the extracted media tree.

**Existing function extensions**.

- `Get-Pca2023ReadinessSnapshot`: added `OutputCheck = $null` to both
  return-path `[pscustomobject]@{...}` initialisers. Downstream code
  populates this field via direct assignment after running the new
  verification function.
- `Show-Pca2023ReadinessSnapshot`: new optional `-OutputCheck`
  parameter. In Compact mode adds a single one-line indicator
  ("Output ISO check : overall=Pass     targets=5 (Pass=3 ...)").
  In detail mode adds a new block listing each target's Status,
  expected/actual signer, and Notes.
- `Format-Pca2023ReadinessForReport`: new optional `-OutputCheck`
  parameter. Appends a plain-text "Output ISO PCA2023 readiness
  (post-conversion, file-based)" section consumed by both the P13
  FinalReport and the standalone `pca2023_readiness.md` file.

**Phase integration**.

- **P10 post-flight** (`Invoke-BuildPhase10_ConvertPca2023BootManager`):
  after the conversion completes and the snapshot is force-refreshed,
  invoke `Test-OutputIsoPca2023Readiness` against the extracted media,
  stash the result on `$post.OutputCheck`, and render a Compact line
  via `Show-Pca2023ReadinessSnapshot -Compact -OutputCheck $outputCheck`.
- **P12** (`Invoke-VerifyPhase12_VerifyPca2023Readiness`): always run
  the verification function regardless of whether P10 executed (the
  `-Force` snapshot refresh resets `OutputCheck` to `$null`, so the
  P12 path is idempotent). Render full detail via
  `Show-Pca2023ReadinessSnapshot -OutputCheck $outputCheck`. Emit the
  result into `pca2023_readiness.json` (via the standard
  `ConvertTo-Json -Depth 10` on the snapshot, which now includes
  `OutputCheck`) and `pca2023_readiness.md` (a new Markdown table
  with the 5-target results and a Reasons bullet list).
- **P13 FinalReport** (`Invoke-ReportPhase13_FinalReport`): when the
  snapshot's `OutputCheck` is populated, pass it through to
  `Show-Pca2023ReadinessSnapshot -Compact` so the operator sees the
  output-check status alongside the existing Compact summary. Uses
  a `PSObject.Properties['OutputCheck']` guard for defensive access
  in cases where the snapshot was built from a code path that does
  not populate the field.

**Implementation note: root cause of the Step 2 type-inference issue**.

The earlier r08.0 Step 2 implementation attempt of this function was
reverted because of a `System.ArgumentException: Argument types do
not match` exception that could not be resolved within the session
budget. Step 3 isolated the trigger with a minimal repro:

```powershell
$list = New-Object System.Collections.Generic.List[object]
$list.Add([pscustomobject]@{Label='test1'; Status='Pass'}) | Out-Null
$list.Add([pscustomobject]@{Label='test2'; Status='Fail'}) | Out-Null
@($list)             # FAILS: Argument types do not match
[object[]]@($list)   # FAILS: same
$list.ToArray()      # OK
```

The `@()` array subexpression operator fails on
`System.Collections.Generic.List[object]` whose elements are
`pscustomobject`. `.ToArray()` is the safe materialisation path. The
existing `Test-Pca2023AuthenticodeChain` and `Get-IsoBootCertReadiness`
escape this trap because their list is `List[string]` (where `@()`
works). The new function uses `.ToArray()` for its `TargetChecks`
(pscustomobject collection) but `@()` for its `Reasons` (string
collection), and documents the distinction in an inline comment so
future maintainers do not regress.

**Documentation changes**.

- New: `docs/history/r08.0-step3-output-verification-and-build.md`
  - Full implementation record including the Step 2 issue root-cause
    analysis, 4-case local test results on Linux pwsh 7.4.6, and the
    design rationale for the per-target Status mapping.
- Updated: `SPEC.md` §B.18 scope-and-limits paragraph
  - Replaced "(planned for addition in a follow-up step)" with the
    final description: the function is implemented, invoked from P10
    post-flight and P12, integrated into JSON / Markdown reports and
    the P13 FinalReport.
- Updated: `SPEC.md` §B.24.6
  - First item (`Test-OutputIsoPca2023Readiness`): CLOSED in Step 3.
  - Second item (Issue #346 defense): kept STILL OPEN with
    disposition note that closure depends on Phase 6 Build -Execute
    real run results.
  - Third item (Server 2025 `SecureBootRecovery.efi`): unchanged
    (informational only).
- Updated: `docs/history/r07.0-followups.md`
  - r08.0 Step 3 P0 #1 (`Test-OutputIsoPca2023Readiness` function +
    P10/P12 integration): CLOSED.
  - r08.0 Step 3 P0 #2 (Phase 6 Build -Execute on Server 2016 EVAL
    ja-jp): STILL OPEN, requires Windows host.
  - New P1 entry: Server 2019 / 2022 / 2025 Build -Execute fleet
    rollout (post-Server-2016 acceptance).

**Out-of-scope for this release (deferred to r08.0 Step 4+)**.

- Phase 6 `-Action Build -Execute` real run on Server 2016 EVAL
  ja-jp (the operational acceptance test for the entire r07.0+r08.0
  work). Requires the Windows host with `D:\UpdateWsi_2016\` workspace.
- Microsoft Issue #346-class defensive handling (`etfsboot.com` and
  similar boot.wim-content gaps): the P10 defensive logic is only
  added if Phase 6 reproduces the issue; otherwise no code change.
- Server 2019/2022/2025 Build -Execute horizontal validation.
- Physical-hardware Secure-Boot boot test on PCA2011-revoked DBX
  firmware (the ultimate validation outside the pipeline's scope).

**Quality gates**. All pass: psa.py (0/0/0), psa.py v4.1.0
PSA1004/2012/2013 (0/0/0), PSScriptAnalyzer (0 findings), PowerShell
parser (Parse OK), T2 (13/13), T3 (10/10), T6 (13/13). Encoding
preserved (BOM + CRLF + ASCII). Line count: 12224 -> 12652 (+428).

**Local test verification** (Linux pwsh 7.4.6, synthetic fake-media
trees under `/tmp/foi-*`):

```
Case 1: empty tree (all 5 targets missing)
  Available=True OverallStatus=Fail TargetChecks=5
    [Fail         ] Target #1  actual=missing
    [PassWithNotes] Target #2  actual=missing
    [Fail         ] Target #3  actual=missing
    [Warning      ] Target #4  actual=missing or empty
    [PassWithNotes] Target #5  actual=missing

Case 2: bootmgr.efi only -> OverallStatus=Fail (Target #1 still missing)
Case 3: 5-target full tree (dummy unsigned files) -> Fail (Linux pwsh
        cannot read Authenticode on dummies; on Windows with real
        PCA2023 bootx64.efi, expected: PassWithNotes)
Case 4: nonexistent path -> Available=False, OverallStatus=Fail,
        ErrorMessage populated
```

### r08.0 Step 2 - install.wim symmetry verification, Microsoft official spec cross-check, P07/P08 dead code path fix

This release closes two open follow-up items from r08.0 Step 1
(install.wim EFI_EX presence symmetry check across the 4 supported
OS families, Server 2025 `EFI_EX\bootmgfw_EX.efi` signature analysis)
and uncovers + fixes a long-standing dead code path that was
silently disabling P07 (install.wim updates) and P08 (boot.wim
updates) throughout the r07.0 cycle. The release also performs an
authoritative cross-check against Microsoft's
`Make2023BootableMedia.ps1` v1.4 to confirm that the in-repository
PCA2023 conversion design is aligned with Microsoft's upstream
specification.

`ScriptVersion`: `update-wsi-2026.05.26-r07.0` -> `update-wsi-2026.05.27-r08.0`
`ScriptTag`    : `kbid-from-filename-and-rich-refresh-summary` -> `promote-enable-flags-for-build-phases`

**Pre-flight investigation (read-only)**.

- **Step 5e — install.wim EFI_EX presence symmetry check.** Direct
  mount of Server 2016/2019/2022 EVAL `install.wim` Index 4 confirmed
  that `\Windows\Boot\EFI_EX\` is **absent** in all three out-of-box
  ISOs, matching the r08.0 Step 1 hypothesis. `bootmgfw.efi` in EFI
  is PCA2011 in all three. Closes the first item in SPEC.md §B.24.5.
- **Step 5f / 5g — Server 2025 EFI_EX signature analysis.** Initial
  `Get-AuthenticodeSignature` read returned `Issuer = Windows UEFI
  CA 2023` on `EFI_EX\bootmgfw_EX.efi`, which was briefly misread as
  a possible dual-signature. `signtool /verify /pa /all /v` plus
  `/ds 0`, `/ds 1`, `/ds 2`, `/ds 3` probe disambiguated the case
  decisively: there is **exactly one embedded signature** per file,
  and:
    - `EFI_EX\bootmgfw_EX.efi` is **PCA2023 single-sign**
      (leaf signer "Microsoft Windows", chain root via
      "Windows UEFI CA 2023")
    - `EFI_EX\bootmgr_EX.efi` is **PCA2011 single-sign**
      (leaf signer "Microsoft Windows", chain root via
      "Windows Production PCA 2011")
- **Step 5h — 4-OS exhaustive `*.efi` survey.** Data-driven
  cross-survey under `\Windows\Boot\` in all four install.wim Index 4
  trees. Totals: Server 2016/2019/2022 = 3 `*.efi` each (all PCA2011),
  Server 2025 = 6 `*.efi` (5 PCA2011, 1 PCA2023). No dual-signed
  files in any OS. Closes the second item in SPEC.md §B.24.5.
- **Microsoft official spec cross-check.** `microsoft/secureboot_objects`
  `scripts/windows/Make2023BootableMedia.ps1` v1.4 (dated 2026-03-13)
  was `git clone`'d and read in full. The `Copy-2023BootBins` function
  (L829-L941) writes five target locations onto the extracted media;
  see SPEC.md §B.18 for the full table. **The Microsoft upstream
  comment at L876-L884** explicitly states that `bootmgr_EX.efi`
  remaining PCA2011 is by design ("Note that this file technically
  is not signed with the 'Windows UEFI CA 2023' certificate, but if
  present in the update, it should be copied"). This validates the
  empirical step 5h finding. The Microsoft upstream contains no
  signature verification logic (zero `Get-AuthenticodeSignature` /
  `signtool` references in the 1141-line script); in-tree
  verification by this pipeline is therefore an upstream-compatible
  quality extension.

**Code changes**.

- **(Fix) `Get-ConfigProfile` now promotes phase-enable flags.**
  Three flags were referenced by P07, P08, and WinRE phases as
  `$Script:OsProfile.EnableInstallWimUpdate` /
  `.EnableBootWimUpdate` / `.EnableWinREUpdate` but were never
  promoted from `Common` to the top-level merged profile in
  `Get-ConfigProfile`. As a result, the property access returned
  `$null` regardless of profile content, and the build phases were
  silently skipped throughout the r07.0 cycle. This is the root cause
  of the previously-unexplained "P07/P08 always skip" behaviour.
  Fix promotes the three flags explicitly with an inline comment
  documenting the rationale.
- **(Config) `Common.EnableInstallWimUpdate` set explicitly per OS.**
    - Server 2016 / 2019 / 2022: `true` (Option A route requires
      install.wim LCU application to materialise EFI_EX assets)
    - Server 2025: `false` (out-of-box install.wim ships EFI_EX
      pre-populated; LCU application is optional for PCA2023)
- **(Version) `ScriptVersion` bumped** from `update-wsi-2026.05.26-r07.0`
  to `update-wsi-2026.05.27-r08.0`. `ScriptTag` set to
  `promote-enable-flags-for-build-phases`.

**Documentation changes**.

- New: `docs/history/r08.0-step2-installwim-symmetry-check.md` (407 lines)
  — full session record covering the three step 5 investigation runs,
  the Microsoft official spec cross-check, and the Phase 1-3
  implementation details. Includes the verbatim Microsoft L876-L884
  comment for traceability.
- Updated: `SPEC.md` §B.18 — added the authoritative Microsoft source
  citation, the 5-target conversion table, the L876-L884 PCA2011
  design quote, and the scope-and-limits paragraph clarifying what
  in-tree verification can and cannot establish.
- Updated: `SPEC.md` §B.24.5 — marked two items CLOSED (install.wim
  EFI_EX symmetry and Server 2025 `bootmgfw_EX.efi` signature), kept
  one STILL OPEN (Server 2016 EVAL end-to-end Build -Execute).
- New: `SPEC.md` §B.24.6 — three new open items raised in Step 2
  (Test-OutputIsoPca2023Readiness implementation, Phase 6 readiness
  for Microsoft Issue #346-class problems, Server 2025
  SecureBootRecovery.efi documentation).

**Out-of-scope for this release (deferred to r08.0 Step 3+)**.

- `Test-OutputIsoPca2023Readiness` function — file-by-file post-build
  verification against the five Microsoft conversion targets. Designed
  during this session but implementation deferred after a PowerShell
  type-inference issue in nested `[pscustomobject]` construction was
  not resolvable within the session budget. The design is captured
  in `docs/history/r08.0-step2-installwim-symmetry-check.md` §5.1.
- P10 / P12 integration of the above verification function.
- Phase 6 — Server 2016 EVAL ja-jp `-Action Build -Execute` real run
  on Windows. Microsoft Issue #346 (2026-02-14) reports analogous
  errors on Windows 11 25H2 + latest LCU, so defensive handling for
  missing `etfsboot.com` and similar boot.wim-content gaps may be
  required during the Phase 6 work.

**Quality gates**. All pass: psa.py (0/0/0), psa.py v4.1.0
PSA1004/2012/2013 (0/0/0), PSScriptAnalyzer (0 findings), PowerShell
parser (Parse OK), T2 (13/13), T3 (10/10), T6 (13/13). Encoding
preserved (BOM + CRLF + ASCII).

**Live verification** (Linux pwsh, post-fix profile merge):

```
Server2016   EnableInstallWimUpdate = True   P07 will skip? False
Server2019   EnableInstallWimUpdate = True   P07 will skip? False
Server2022   EnableInstallWimUpdate = True   P07 will skip? False
Server2025   EnableInstallWimUpdate = False  P07 will skip? True
```

### r08.0 Step 1 - Server 2016/2019/2022/2025 PCA2023 readiness investigation

This is a **documentation / investigation** release with no
code changes to `Update-WindowsServerIso.ps1`. The r08.0 cycle
opens with a P0 investigation task carried over from
`docs/history/r07.0-followups.md#P0`: determine the correct
workflow for producing a PCA2023-bootable Server 2016 EVAL
ISO, given that the r07.0 dry-run completion left this question
unanswered.

**Outcome**: the prior "Server 2016 EVAL is not viable for the
PCA2023 use case" interpretation was **incorrect**. All four
supported OS families (Server 2016 / 2019 / 2022 / 2025) can
produce a Healthy PCA2023 ISO via the **Option A** route from
`r07.0-followups.md#P0`:

1. Enable `EnableInstallWimUpdate=true` in
   `config-Server<2016|2019|2022>.json`.
2. Include a 2024-4B-or-later LCU in `PatchBaseline.NeutralPatches`.
3. P10 `ConvertPca2023BootManager` then converts the boot manager
   from PCA2011 to PCA2023 using the EFI_EX staging assets that
   the LCU shipped into install.wim.

Server 2025 is a special case: Microsoft ships the EFI_EX staging
directories pre-populated inside the **out-of-the-box** install.wim,
so the LCU does not (and need not) carry `*_EX.efi` binaries. The
P10 conversion still applies; it just does not depend on LCU
application as a prerequisite.

**Evidence base**. The conclusion is supported by three independent
sources verified during this session:

| Source | Evidence |
|---|---|
| **Microsoft official code** | `microsoft/secureboot_objects` `Make2023BootableMedia.ps1` v1.4 / 2026-03-13: 1141 lines, zero OS-version literals, OS-agnostic by design |
| **Microsoft Support KB5053484** | "Applies To" section explicitly enumerates Server 2016, 2019, 2022 (Server 2025 was not yet released when the KB was published 2025-02-04) |
| **Physical MSU expansion (4 OS)** | Server 2016 KB5087537, Server 2019 KB5087538, Server 2022 KB5087545 all carry the identical 6-binary `*_EX.efi` composition (`bootmgfw_ex.efi`×3 + `wdsmgfw_ex.efi`×2 + `bootmgr_ex.efi`×1) plus matching `bootmgfw_EX*` MUI tree. Server 2025 KB5087539 has none of these, but Server 2025 EVAL install.wim's `\Windows\Boot\` already contains `EFI_EX\` (72 files), `Fonts_EX\` (16 files), `DVD_EX\` (2 files) |

**Methodological side-finding**. Server 2025 MSU packaging crossed
a generational boundary: starting with Server 2025 / Windows 11 24H2,
MSU files are `MSWIM` (Windows Imaging Format) wrappers carrying a
`*.wim` manifests file plus a `*.psf` Patch Storage Stream v2
(`PSTREAM` magic) binary-delta file, instead of the legacy `MSCF`
(CAB) structure used by Server 2016/2019/2022. Future operator-side
manual MSU inspection on Server 2025 requires `DISM /Apply-Image`
instead of `expand.exe`. The pipeline itself is unaffected because
DISM handles both formats transparently when applying packages to a
mounted image.

**Files added**:

- `docs/history/r08.0-step1-server2016-pca2023-finding.md`
  (24,949 bytes) — full investigation report including 4-OS MSU
  structure maps, EFI_EX assessment per OS, install.wim direct
  inspection results, certificate-chain analysis, and the §9
  open-question list for r08.0 Step 2.

**Files updated**:

- `SPEC.md` — new `B.24 LCU package format generation matrix and
  EFI_EX provenance (r08.0+, informative)` summarising the
  investigation results for future readers (e.g. what packaging
  format each OS uses, where EFI_EX comes from per OS, what
  config-Server*.json values follow from this).
- `docs/history/r07.0-followups.md` — `P0 Server 2016 EVAL secure
  boot and PCA2023 readiness` moved to **Closed items** with a
  pointer to the finding; new follow-up items added for the
  r08.0 Step 2 implementation work.

**Files NOT changed** (intentional):

- `Update-WindowsServerIso.ps1` — no behavioural changes are
  required. The existing P10 design (skip-with-warn on Critical
  health, run on Healthy) is correct for all four OS families.
- `data/config-Server*.json` — the config updates are tracked as
  r08.0 Step 2 tasks (see `r07.0-followups.md` § new P0
  entry), not part of this Step 1 documentation-only release.

**Static analysis**: not re-run for Step 1 because no `.ps1` file
was touched. The r07.0 Step 19 clean scan (0/0/0) remains
valid as of this release.

### r07.0 Step 19 - Eliminate duplicate Phase Timing Summary via idempotent Show-PhaseSummary

The Step 18 verification produced the first **fully-clean
end-to-end PrepareBuildVerify run** in r07.0 - and arguably
in this script's lifetime to date - against a real Server 2016
EVAL ja-jp source media. The 13-phase pipeline ran in 4m44s
with exit 0 and no interactive prompts:

```
P01   DONE     elapsed: 0.14s
P02   DONE     elapsed: 0.11s
P03   DONE     elapsed: 0.02s  (skipped, -UseBaselineOnly)
P04   DONE     elapsed: 17.43s (ISO + 2 patches all cached)
P05   DONE     elapsed: 35.82s (robocopy 6.68 GB + WIM enum)
P06   DONE     elapsed: 0.02s  (skipped, -UseBaselineOnly)
P07   DONE     elapsed: 0.02s  (EnableInstallWimUpdate=false)
P08   DONE     elapsed: 0.02s  (EnableBootWimUpdate=false)
P09   DONE     elapsed: 0.02s  (Sandbox mode)
P10   DONE     elapsed: 1m54s  (Critical health -> skip-with-warn)
P11   DONE     elapsed: 0.03s  ("Output ISO missing" recorded)
P12   DONE     elapsed: 1m56s  (full non-compact rendering OK)
P13   DONE     elapsed: 0.05s  (FinalReport with PCA2023 summary)
```

All 14 progress lines in P10 and P12 rendered cleanly,
including the EFI_EX / FONTS_EX / DVD_EX detail lines that
the Step 18 `$(if ...)` fix unblocked. The Step 17 fix kept
the non-compact rendering path from hanging on the broken
Write-PhaseHeader call. The Step 16 progress logging made
the WIM mount/dismount cycles visible in real time. The
mojibake from Step 16 did not recur (fresh WorkRoot).

This is the **dry-run completion milestone**.

**Remaining cosmetic defect surfaced by the milestone run.**
The "Phase Timing Summary" table appeared twice in the
console output - once as part of P13's body (per SPEC.md
Part B.5 P13 Step 1), and once again from the script-tail
`finally` block. Both call sites are by design: P13 prints
the table because SPEC says it does; the `finally` block
prints it as a safety net so an aborted run still gets the
timing table. The duplication on a happy-path run was a
coordination gap.

**Fix**. Make `Show-PhaseSummary` itself idempotent rather
than coordinate between callers. A new
`$Script:PhaseSummaryShown` flag (initialised to `$false`
alongside `$Script:PhaseTimings`) is flipped to `$true` on
the first invocation. The `finally` call after P13 sees the
flag is already true and short-circuits without printing.
The safety-net behaviour is preserved: if P13 does NOT run
(early failure, or an `-Action` that excludes P13), the
flag is still `$false` when the `finally` block fires and
the table prints as before.

A new `-Force` switch on `Show-PhaseSummary` bypasses the
guard for ad-hoc / test scenarios. Production callers never
use it.

`Show-PhaseSummary` is also promoted from a one-line
wrapper to a properly-documented advanced function with
`[CmdletBinding()]`, `[OutputType([void])]`, and a
multi-paragraph `.SYNOPSIS` / `.DESCRIPTION` block
explaining the two callers and the idempotency contract.

**Verification**. A short pwsh smoke-test AST-extracted
`Show-PhaseSummary` and `Format-Elapsed` from the script,
built a fake `$Script:PhaseTimings` list, and called the
function three times:

```
Call #1 (no -Force):  prints table   - OK
Call #2 (no -Force):  silent         - OK (idempotency works)
Call #3 (with -Force): prints again  - OK
```

**Quality gates**. All five gates pass: BOM + CRLF + ASCII
OK (12,213 lines, no LF-only lines), PS Parse OK, `psa.py`
0/0/0, PSScriptAnalyzer 0 issues, T2-T10 all 6 tests PASS,
runtime idempotency smoke-test passes.

A meta-defect was caught and fixed during this release: the
initial `str_replace` insertion of the new
`$Script:PhaseSummaryShown` initialiser produced six
LF-only lines (the editing tool's default newline) into a
CRLF file. psa.py's PSA7002 rule caught it at gate time;
the lines were normalised to CRLF before the second gate
run.

**Files changed**.

- `scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1`
  - `Show-PhaseSummary` rewritten with idempotency guard,
    `-Force` switch, full doc comment, and `[OutputType([void])]`.
  - `$Script:PhaseSummaryShown = $false` initialiser added
    immediately after `$Script:PhaseTimings = ...`.
- `scripts/powershell/update-windows-server-iso/SPEC.md`
  - Added section B.23.24 and the matching matrix row.

**What comes next.**

PrepareBuildVerify is now production-ready as a dry-run
inspection tool. The remaining work falls into three
categories:

1. **Server 2019 / 2022 / 2025 verification**. Repeat the
   end-to-end PrepareBuildVerify run on the other three
   OS families to confirm no OS-specific surprises.
   Server 2025 in particular should skip P10 cleanly
   (per the existing Server2025 gate) and Server 2022's
   PCA2023 path will exercise the conversion code that
   Server 2016 cannot reach.
2. **`-Execute` mode**. Switch from `PrepareBuildVerify`
   (dry-run) to `Build` or `All` with `-Execute` to
   actually call `oscdimg` and produce the output ISO.
   For Server 2016 EVAL with `EnableInstallWimUpdate=false`,
   the output ISO will be byte-identical to the source
   (no patching done) which is mostly useful as a smoke
   test for the assembly pipeline.
3. **Mojibake DISM-cache investigation** (deferred).
   The notes are in `docs/history/mojibake-investigation-note.md`.
   Pick up when there is time; the workaround (fresh
   WorkRoot per OS family) is already known.

### r07.0 Step 18 - Fix `(if ...)` mis-spelled subexpressions in Show-Pca2023ReadinessSnapshot

Step 17's `Write-PhaseHeader -> Write-SubSection` fix unblocked
the non-compact rendering branch in `Show-Pca2023ReadinessSnapshot`,
and the Step 17 verification run reached and ran it cleanly
all the way through P10 + P11 + P12 snapshot computation +
the new `-- PCA2023 readiness detail --` sub-section header
... at which point it failed with:

```
[X] Phase P12 (VerifyPca2023Readiness) failed: 用語 'if' は、コマンドレット、
    関数、スクリプト ファイル、または操作可能なプログラムの名前として
    認識されません。
[~]     Show-Pca2023ReadinessSnapshot, line 8184
[~]     Invoke-VerifyPhase12_VerifyPca2023Readiness, line 10478
```

Root cause: a second latent bug in the same
`Show-Pca2023ReadinessSnapshot` function. Five lines (L8184-8188)
used the wrong subexpression syntax:

```powershell
# BROKEN - PowerShell parses (if ...) as a command invocation named 'if'
'EFI_EX staging directory : {0}' -f (if ($null -eq $emb.HasEfiExDir) { 'n/a' } elseif ... )

# CORRECT - $(...) is the subexpression operator that wraps a statement as a value
'EFI_EX staging directory : {0}' -f $(if ($null -eq $emb.HasEfiExDir) { 'n/a' } elseif ... )
```

The same function had this idiom written **correctly** six lines
below ($Signer subject line) and at four other sites
in the SecureBoot/LCU blocks. The bug was a local copy-paste
mistake on the five EFI_EX/FONTS_EX/DVD_EX-family lines,
not a systemic misunderstanding.

**Why this slipped through static analysis**. `(if ...)` is a
syntactically valid command-invocation form in PowerShell's
grammar - the parser accepts it and treats `if` as a command
name to be resolved at runtime. PS Parse passed, psa.py
passed (0/0/0), PSScriptAnalyzer passed (0 issues). The
function was unreachable in earlier verification runs (the
Write-PhaseHeader bug blocked it), and the compact branch -
which is what every other call site uses - skips the broken
lines entirely.

The first runtime invocation through the unblocked non-compact
path immediately surfaced the bug.

**Fixes applied**.

1. Five `(if ...)` -> `$(if ...)` replacements at L8184-L8188.
2. An 8-line in-source comment explaining the trap, the
   correct `$(if ...)` form, and the fact that `@(if ...)`
   (array subexpression) is also valid. Placed immediately
   before the first formerly-broken line.
3. Defensive Python grep over the entire script for any
   other bare `(if ...)`, `(switch ...)`, `(foreach ...)`,
   or `(while ...)` patterns. Zero further hits.
4. Smoke-test runtime verification: a short pwsh script that
   AST-extracts `Show-Pca2023ReadinessSnapshot` and its
   `Write-Step` / `Write-SubSection` / `_LogLine`
   dependencies, builds a fake snapshot pscustomobject,
   and calls the function in non-compact mode. The test
   now passes; before the fix it threw the same "term 'if'
   is not recognized" error.

**Discipline note**. The B.23.22 ASCII-only rule was very
nearly violated in the first iteration of this fix - I had
quoted the localised Japanese error message in the in-source
comment for diagnostic clarity. The quality-gate ASCII check
caught it before commit. The final comment uses an English
paraphrase ("term 'if' is not recognized as a name of a
cmdlet, function, script file...") and keeps the file
ASCII-only.

**Quality gates**. All five pass: BOM + CRLF + ASCII OK
(12,171 lines), PS Parse OK, `psa.py` 0/0/0, PSScriptAnalyzer
0 issues, T2-T10 all 6 tests PASS, runtime smoke-test of
`Show-Pca2023ReadinessSnapshot` in non-compact mode RUNS OK
with all expected output lines.

**Files changed**.

- `scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1`
  - `Show-Pca2023ReadinessSnapshot` ISO-boot-environment block:
    five `(if ...)` -> `$(if ...)` rewrites, plus an
    8-line explanatory comment.
- `scripts/powershell/update-windows-server-iso/SPEC.md`
  - Added section B.23.23 and the matching matrix row.

**Expected next run**.

With Steps 16-18 stacked, the PrepareBuildVerify command should
now reach P13 FinalReport for the first time and exit cleanly:

1. P01-P09: cached / skipped quickly (P05 robocopy re-runs
   against the existing extracted tree).
2. P10: skip-with-warn (Critical health), DONE.
3. P11: "Output ISO missing", DONE.
4. P12: snapshot computation + full non-compact rendering
   (now working), then DONE.
5. P13: FinalReport with all collected state.
6. Total elapsed ~5 minutes, exit 0, no interactive prompts.

### r07.0 Step 17 - Fix Write-PhaseHeader positional call that hung P12 in non-compact rendering mode

The Step 16 live verification got further than ever before:

- P01 - P09 ran cleanly (0.1 - 35 seconds each).
- P10 entered its new step-by-step progress logging path,
  ran the boot.wim + install.wim readiness snapshot in 1m55s
  with all 14 progress lines visible, classified the health
  as 'Critical' (Server 2016 EVAL install.wim still at
  KB3211320), wrote the new `Write-Warn` block explaining
  the prereq, dropped the `P10.skipped` marker, and DONE.
- P11 StaticVerify ran in 40 ms and correctly recorded
  "Output ISO missing" (expected in PrepareBuildVerify
  dry-run mode).
- P12 VerifyPca2023Readiness ran the snapshot computation
  in 1m55s with the same progress lines, then ...

... PowerShell prompted for interactive input:

```
コマンド パイプライン位置 1 のコマンドレット Write-PhaseHeader
次のパラメーターに値を指定してください:
Name:
```

The user had to Ctrl-C. P13 never ran.

Root cause: `Show-Pca2023ReadinessSnapshot` (the function that
P12 calls at the very end to render the readiness snapshot to
the console) has two rendering modes - compact (a single
one-line summary) and non-compact (a full multi-section dump).
The non-compact branch began with this line:

```powershell
Write-PhaseHeader 'Pca2023 readiness (P12)'
```

`Write-PhaseHeader`'s signature is:

```powershell
param(
    [Parameter(Mandatory)] [string]$Id,
    [Parameter(Mandatory)] [string]$Name,
    [Parameter(Mandatory)] [string]$Group
)
```

Positional binding fills only `-Id`. PowerShell then prompts
the user for `-Name`. The four `Show-Pca2023ReadinessSnapshot`
call sites are:

- P10 post-flight: passes `-Compact` -> compact branch -> safe
- **P12 verify body: no `-Compact` flag -> hit the broken line**
- P13 summary: passes `-Compact` -> compact branch -> safe
- Standalone analysis helper: no `-Compact` -> would also hit
  the broken line, but this code path is not normally exercised

The fix is one line: replace `Write-PhaseHeader` with
`Write-SubSection`. Semantically this was the right idiom
all along - the function is called *during* a phase (P12 has
already emitted its own phase banner at entry), so a second
phase banner inside the body would be visual noise even if
the call had worked.

A defensive audit was added to confirm no other Mandatory-param
function in the script is called positionally elsewhere. A
small Python pass found 28 functions with >=2 Mandatory
parameters and zero positional-call sites among them, so this
was the only such trap remaining.

**Files changed**.

- `scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1`
  - `Show-Pca2023ReadinessSnapshot` non-compact branch:
    `Write-PhaseHeader 'Pca2023 readiness (P12)'` -> `Write-SubSection 'PCA2023 readiness detail'`
    plus a 10-line comment explaining why
    `Write-SubSection` is the right choice here.
- `scripts/powershell/update-windows-server-iso/SPEC.md`
  - Added section B.23.22 and the matching matrix row.

**Additional observation - mojibake no longer reproduces**.

The Step 16 run had reported a console-rendering artifact:
install.wim idx 2's Japanese edition name appeared with each
character doubled (`デデススククトトッッププ` instead of
`デスクトップ`). The Step 17 run had **identical mojibake-side
conditions** (same PS 5.1.26100.32860, same ja-JP culture,
same `Console OutputEnc utf-8 (cp65001)`, same source ISO),
but the only externally-visible difference - the `-WorkRoot`
path was changed from `D:\UpdateWsi` to `D:\UpdateWsi_2016` -
caused the mojibake to disappear entirely. idx 2 now renders
correctly.

The investigation note at
`docs/history/mojibake-investigation-note.md` has been updated
with this new finding. The working hypothesis has shifted from
"PS 5.1 console UTF-16 surrogate handling" to "DISM mount-cache
state corruption from prior aborted P10 runs". The original
WorkRoot had been used through Steps 11-16 with several
aborted P10 mount/dismount cycles; the new tree was fresh.
This remains a deferred low-priority investigation; the
working workaround in the meantime is "use a fresh WorkRoot
per OS family", which is what Takayuki's run was already
doing.

**Quality gates**. All five pass: BOM + CRLF + ASCII OK
(12,164 lines), PS Parse OK, `psa.py` 0/0/0, PSScriptAnalyzer
0 issues, T2-T10 all 6 tests PASS.

**Expected next run**.

With both Step 16 (P10 skip-with-warn + progress logging,
Invoke-DownloadWithProgress utility) and Step 17 (P12
non-compact rendering fix) applied, the next
`PrepareBuildVerify` run is expected to:

1. P01-P09: run quickly with cached assets (P05 robocopy
   re-runs against the existing extracted tree - robocopy
   skip-already-copied makes this near-instant).
2. P10: skip-with-warn cleanly (`Health = Critical`,
   `P10.skipped` marker, no throw).
3. P11: record "Output ISO missing".
4. P12: complete the second snapshot run (~115 seconds for
   the WIM mount/enum/dismount cycle), then render the
   full readiness detail via the now-fixed `Write-SubSection`
   path and continue to P13.
5. P13: emit the FinalReport with all collected state.
6. Script exits 0 cleanly. No interactive prompt.

### r07.0 Step 16 - P10 progress logging, Critical-Health skip-with-warn, and `Invoke-DownloadWithProgress` utility

Three UX improvements bundled under one release because they
share the same theme - making long-running phases emit visible
progress instead of silent multi-minute pauses.

**Observed regression that motivated the changes.** The Step 15
run got all the way through P01 - P09 cleanly, then P10 ran for
1m54.9s with no on-screen output before throwing
`P10 pre-flight failed: snapshot Health is 'Critical'`. The user
correctly observed three problems:

1. The throw was wrong UX for `-Action PrepareBuildVerify` - the
   action is a dry-run inspection, and the prereq mismatch is
   *information*, not a hard failure that should abort before
   P11/P12/P13 even run.
2. P10 was emitting one `Write-SubSection` header at entry and
   then nothing for the entire 1m54s. The silent block was two
   `Mount-WindowsImage` + `Get-WindowsPackage` enumerations
   inside `Get-IsoBootCertReadiness` - which takes 30-90s per
   WIM on commodity NVMe.
3. The original ISO download (when the cache was empty) had the
   same issue, just on a longer timescale - a 6 GB ISO would
   download silently for 10-15 minutes with only "Downloading..."
   and "Downloaded: {path}".

**Fix 1: P10 Critical-Health throw -> skip-with-warn**.

The P10 Critical branch now writes a structured `Write-Warn`
with the snapshot reasons, prints two follow-up `Write-Warn`
lines explaining how to enable PCA2023 conversion (profile
`EnableInstallWimUpdate = true` + patch baseline must include
2024-4B LCU `KB5036899` or later), drops the `P10.skipped`
marker file that matches the existing skip-condition pattern,
and returns cleanly so P11-P13 still run. The throw for missing
`$Script:ExtractedDir` (workflow ordering violation) is preserved
because P11-P13 would also fail without the extracted tree.

**Fix 2: P10 step-by-step progress logging**.

P10 is now restructured into four named steps with
`Write-SubSection` headers matching the pattern P01-P09
already use:

- `Step 1: Pre-flight gates` (EnablePca2023BootManager check,
  Server2025 advisory, ExtractedDir presence)
- `Step 2: Boot manager readiness snapshot (pre-conversion)` -
  the long block, now with start/end timings
- `Step 3: Convert boot manager to PCA2023 signing` - external
  or internal converter, with per-call elapsed-seconds
- `Step 4: Re-assemble ISO and post-flight verification`

Each step records its start time and prints
`... completed in {0}s` so the user gets concrete progress
even before the snapshot itself emits anything.

The bigger win is propagating progress logging *into*
`Get-IsoBootCertReadiness` - the function that was silent for
the 1m54s. It now emits seven `Write-Step` lines as it runs:

```
  [1/4] Mounting boot.wim idx 1 read-only ...
         boot.wim mounted (12s); inspecting EFI_EX / FONTS_EX / DVD_EX ...
         enumerating boot.wim installed packages (Get-WindowsPackage) ...
         boot.wim LCU level resolved (8s): highest KB = KB3211320
  [2/4] Dismounting boot.wim (discard) ...
         boot.wim dismounted (5s)
         Inspecting bootx64.efi Authenticode signer chain ...
         bootx64.efi signer: Microsoft Windows Production PCA 2011
  [3/4] Mounting install.wim idx 1 read-only ...
         install.wim mounted (28s); enumerating installed packages ...
         install.wim LCU level resolved (35s): highest KB = KB3211320
         reading SYSTEM hive SecureBoot servicing keys ...
  [4/4] Dismounting install.wim (discard) ...
         install.wim dismounted (16s)
```

Now the user sees exactly where time is going in real time.

**Fix 3: `Invoke-DownloadWithProgress` utility**.

The existing `Invoke-WebRequestWithRetry` correctly sets
`$ProgressPreference = 'SilentlyContinue'` to dodge PS 5.1's
O(N^2) progress-bar slowdown on multi-GB downloads, but the
trade-off is total silence for the duration of the download. A
new utility function recovers visibility *without* re-enabling
the slow built-in progress bar.

The technique is borrowed in spirit from
`Deploy-AMDChipsetDriverOnWindowsServer.ps1` in the
[usui-tk/Deploy-Drivers-For-WindowsServer](https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer)
repository (see its `Invoke-PrepPhase03_FetchInstaller` around
L7808 - `Write-Step` before, `Write-Ok` after, post-download
size validation against a minimum threshold), but extended with
a background-job + main-thread-polling mechanism that the
reference does not have. The reference can get away with
just start/end markers because its payloads are 50-150 MB
chipset installers; this script downloads multi-GB ISOs where
the lack of mid-stream feedback is much more painful.

Steps performed by the new function:

1. HEAD request to learn expected `Content-Length` (~1 second;
   optional - some CDNs reject HEAD with 405).
2. Spawn a `Start-Job` worker that runs the actual
   `Invoke-WebRequest` with `ProgressPreference = 'SilentlyContinue'`
   in its own runspace.
3. From the main thread, poll the destination file's size via
   `Get-Item -LiteralPath ... | Length` every 5 seconds.
4. Print one progress line per poll:
   `  ... 1,234.5 MB / 6,852.3 MB (18.0%) at 12.3 MB/s ETA 8m 12s`
5. On completion, print a final `Write-Ok` summary:
   `[+] Downloaded: 6,852.3 MB in 9m 17s (12.3 MB/s avg)`
6. Optional `-MinSizeBytes` post-download check; if the file is
   smaller than the threshold, deletes it and throws an
   actionable error message (the
   "CDN returned an error page" defense).

`Invoke-WebRequestWithRetry` is refactored so the `-OutFile`
branch delegates to `Invoke-DownloadWithProgress`. The in-memory
fetch path (HTML/JSON scraping for Microsoft Learn release-info,
.NET CU index, MSU Catalog) keeps the original direct call - those
responses are small and don't benefit from the background-job
overhead. All existing call sites (the ISO download in P04 Step
1, the MSU patch downloads in P04 Step 2, the wsusscn2.cab
download for offline scanning) keep working unchanged; they
now get progress output automatically.

**Quality gates**. All five gates pass: BOM + CRLF + ASCII OK
(12,154 lines), PS Parse OK, `psa.py` 0/0/0, PSScriptAnalyzer
0 issues, T2-T10 all 6 tests PASS. No data files, workflows,
or tests are touched - this is a pure PS1 + docs change.

**Files changed**.

- `scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1`
  - Added `Format-MegabyteCount` helper (~16 lines).
  - Added `Invoke-DownloadWithProgress` utility (~240 lines)
    with `[OutputType([void])]` on its CmdletBinding.
  - Refactored `Invoke-WebRequestWithRetry` `-OutFile` branch
    to delegate (~30 lines net change).
  - Restructured `Invoke-BuildPhase10_ConvertPca2023BootManager`
    into four named steps with `Write-SubSection` headers,
    per-step timings, and the Critical-Health skip-with-warn
    branch (~90 lines net change).
  - Added 14 progress `Write-Step` calls inside
    `Get-IsoBootCertReadiness` (boot.wim mount/enum/dismount,
    install.wim mount/enum/SYSTEM-hive/dismount).
- `scripts/powershell/update-windows-server-iso/SPEC.md`
  - Added section B.23.21 and the matching matrix row.

**Next**. Run the same `PrepareBuildVerify` command again and
expect:

1. P04 ISO/patches step now logs progress (or "cached" lines
   if the local cache is hit, which it should be).
2. P10 prints the four `Step 1-4` sub-section headers, then
   the seven `Write-Step` lines from inside the snapshot.
3. P10 ends with `Write-Warn` + skip-with-marker (no throw)
   because the Server 2016 EVAL install.wim still has the 2017
   highest KB; P11-P13 then continue normally.

### r07.0 Step 15 - Fix `$Script:ExtractedMediaPath` and `$Script:WorkRootFull` typos in P10/P12

Triggered by a failure observed on the freshly-pushed Step 14
commit. With the P05 ExpandIso robocopy fix, the script
finally reached and completed P05 through P09, then hit a
guard at the entry to P10:

```
PHASE P05  - ExpandIso  (Plan) start: 18:11:52
 [+] robocopy exit=1 (0-7 = success)
 [+] Extracted ISO contents to: D:\UpdateWsi\source\extracted
 [*]   install.wim idx 1-4: Server 2016 Standard / Datacenter, Core / Desktop
 [*]   boot.wim idx 1-2: Windows PE / Windows Setup
P05  DONE     elapsed: 33.24s
P06  DONE (skipped, -UseBaselineOnly)
P07  DONE (skipped, EnableInstallWimUpdate=false)
P08  DONE (skipped, EnableBootWimUpdate=false)
P09  DONE (sandbox mode, oscdimg run skipped)
PHASE P10  - ConvertPca2023BootManager (Build) start: 18:12:26
P10  FAILED   elapsed: 0.01s
 [X] P10 requires P05 ExpandIso to have produced an extracted
     media tree. Run -Action All or -Action Build.
```

The error message was misleading: P05 had in fact run and
produced the extracted tree at `D:\UpdateWsi\source\extracted`
(P05 spent 33 seconds copying ~6 GB via robocopy and then
~1 second enumerating the four install.wim editions and two
boot.wim indexes). The guard at line 9822 was reading
`$Script:ExtractedMediaPath`, which is a variable that is
never assigned anywhere in the script. The actual script-
scope global that holds the extracted-ISO directory is
`$Script:ExtractedDir`, initialised at L496 alongside the
other working-directory globals. Because `$Script:
ExtractedMediaPath` evaluated to `$null`, the
`-not $extractedPath` branch in the guard fired
unconditionally and threw the misleading 'P05 did not run'
exception.

A defensive audit of the surrounding code surfaced a second
typo of the same family: `$Script:WorkRootFull` was being
read at six sites under P10 and P12 but is also never set.
The correct global is `$Script:WorkRoot`, initialised at
L486 via `Resolve-RelativeToScript $WorkRoot` (which
already returns an absolute path, so the `Full` suffix
that the consumer sites expected was always redundant).
Both typos likely originate from the same earlier rename
that updated the definition sites but missed the consumer
sites.

**Fixes applied**.

Site set 1: `$Script:ExtractedMediaPath` -> `$Script:ExtractedDir`
at the two reader sites in P10 (`Invoke-BuildPhase10_ConvertPca2023BootManager`)
and P12 (`Invoke-VerifyPhase12_VerifyPca2023Readiness`). A
clarifying comment was added above the P10 site noting that
the script-scope global keeps the `ExtractedDir` name while
the PCA2023 helper API surface uses `$ExtractedMediaPath`
as a function-parameter name (the two are not the same
scope).

Site set 2: `$Script:WorkRootFull` -> `$Script:WorkRoot` at
all six reader sites (L9836, L9882, L9917, L10121, L10128,
L10213) under P10 and P12. No assignment site existed for
`WorkRootFull`, so the rename is purely consumer-side and
has no behavioural side effect beyond the fix itself.

The broader global-variable audit also surfaced 24 other
"read but never defined" globals; on inspection these are
all PowerShell `param()` bindings (script parameters
auto-populate `$Script:`-scoped variables), one
defensively-guarded read with a `IsNullOrEmpty` check and
`$PSCommandPath` fallback (`$Script:ScriptPath`), and one
comment-only reference (`$Script:ErrorsJsonlPath`). No
further code change was required for those.

Live verification awaits the operator's re-run. With the
extracted media tree still on disk from the previous run,
P05 will re-run robocopy against the same destination
(robocopy mirroring keeps re-runs incremental and fast),
then P06-P09 skip or run quickly, and P10 should now
proceed past the guard. P10 then calls
`Get-OrEnsurePca2023Snapshot` against the extracted tree
to compute the PCA2023 readiness snapshot; the outcome
depends on the source ISO's boot manager signer chain
(Server 2016 ja-jp EVAL is signed under the PCA2011
root, so the snapshot Health is expected to be
something other than Healthy, which is what makes
the PCA2023 conversion necessary on Server 2016/2019/
2022 in the first place).

Files changed:

- `scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1`
  - `Invoke-BuildPhase10_ConvertPca2023BootManager`:
    replaced one `$Script:ExtractedMediaPath` read and three
    `$Script:WorkRootFull` reads with the correct globals.
  - `Invoke-VerifyPhase12_VerifyPca2023Readiness`: replaced
    one `$Script:ExtractedMediaPath` read and three
    `$Script:WorkRootFull` reads with the correct globals.
- `scripts/powershell/update-windows-server-iso/SPEC.md`
  - Added section B.23.20 and the matching matrix row.

No data files, workflows, or tests are touched.

### r07.0 Step 14 - Switch P05 ExpandIso to robocopy; fix P09 overlay `-LiteralPath` + wildcard contradiction

Triggered by a failure observed on the freshly-pushed Step 13
commit. With the `Split-Path -LiteralPath -Leaf` parameter-set
bugs fixed, P04 finally completed both patch downloads in just
over 3 minutes, and the script reached P05 ExpandIso for the
first time in this verification cycle. P05 then hit a
different `Copy-Item` failure inside `Expand-SourceIso`:

```
P04   DONE     elapsed: 3m16.1s
PHASE P05  - ExpandIso  (Plan) start: 18:00:31
 -- Step 1: Expand source ISO ---
 [*] Copying from E:\ to D:\UpdateWsi\source\extracted ...
PHASE P05  -> FAILED   elapsed: 2.10s
 [X] Phase P05 (ExpandIso) failed:
     2 番目のパス フラグメントを ドライブ名または UNC 名にすることは
     できません。パラメーター名:path2
 [~]    Expand-SourceIso, line 8909
```

The failing statement was

```powershell
Copy-Item -LiteralPath $src -Destination $DestRoot -Recurse -Force
```

with `$src = 'E:\'` (the mounted ISO's drive root). PowerShell's
`Copy-Item` rejects a drive root as `-LiteralPath` when
combined with `-Recurse -Destination` because internally it
calls `System.IO.Path.Combine` to construct the destination
subpath, and Path.Combine refuses to accept a rooted path
('E:\') as its second argument - it cannot decide whether the
user wants the drive's contents copied INTO `$DestRoot` or the
drive itself created AS `$DestRoot\E:\`, and chooses to raise
rather than guess. The behaviour is identical on PowerShell
5.1 and 7.

While investigating, a second latent `Copy-Item` defect was
discovered at the Dynamic Update overlay site in
`Invoke-BuildPhase09_AssembleIso`:

```powershell
Copy-Item -LiteralPath (Join-Path $tmpExtract '*') ...
```

`-LiteralPath` defeats wildcard expansion by definition, so
the cmdlet would search for a file literally named `*` in
`$tmpExtract` and fail with 'Cannot find path' the first time
a Dynamic Update overlay was actually applied. This site has
not been hit in regression yet because the verification
ladder has been blocked upstream of P09, but it is the same
class of bug and is cheaper to fix now alongside the P05
correction.

**Fixes applied**.

Site 1: P05 `Expand-SourceIso` drive-root copy
(now at the same line, behaviour changed). Replaced the
single `Copy-Item -LiteralPath $src -Destination $DestRoot
-Recurse -Force` with a `robocopy.exe` invocation:

```powershell
$rcArgs = @(
    $src, $DestRoot,
    '/E',           # Subdirectories including empty
    '/COPY:DAT',    # Data, Attributes, Timestamps (no NTFS ACLs)
    '/R:1', '/W:1', # 1 retry, 1-sec wait
    '/NP', '/NDL', '/NFL', '/NJH', '/NJS',  # quiet console
    ('/LOG:' + $rcLog)
)
& robocopy.exe @rcArgs | Out-Null
if ($LASTEXITCODE -ge 8) {
    throw ('robocopy failed (exit {0}): see {1}' -f $LASTEXITCODE, $rcLog)
}
Write-Ok ('robocopy exit={0} (0-7 = success), log: {1}' -f $LASTEXITCODE, $rcLog)
```

`robocopy.exe` ships with Windows since Vista, handles drive
roots as sources correctly, and is 5-10x faster than
`Copy-Item -Recurse` for ISO content (typically ~6 GB across
thousands of small files). The earlier in-source comment that
preferred Copy-Item to 'avoid external tools' was reverted -
robocopy is a Windows built-in, not an external dependency on
this target. Robocopy exit codes 0-7 are documented as success
or informational (0 = no changes, 1 = files copied, etc.); 8
or higher signals at least one fatal error and is converted
to a thrown exception with the log path attached for triage.

Site 2: P09 overlay `Copy-Item -LiteralPath ... '*'`
contradiction. Changed `-LiteralPath` to `-Path` so the
wildcard actually expands:

```powershell
Copy-Item -Path (Join-Path $tmpExtract '*') `
    -Destination (Join-Path $Script:ExtractedDir 'sources') -Recurse -Force
```

The other six `Copy-Item -LiteralPath ...` sites in the
script all copy single-file paths with no wildcards and are
correct as written.

Live verification awaits the operator's re-run. With ISO,
patches, and the seeding fix all known-good from previous
Step 12 / Step 13 runs, the next iteration is expected to
reach the patches as before in ~10 seconds (cached ISO) plus
patch DL (~3 min on a warm cache - likely much faster since
patches are now also on disk), then enter P05 with robocopy
moving ~6 GB from `E:\` to `D:\UpdateWsi\source\extracted` in
roughly 1-3 minutes depending on the host's I/O. After P05
the WIM enumeration runs (`install.wim` and `boot.wim`), then
P06 ValidatePatchSet, then the P07-P13 plan/sandbox phases.

Files changed:

- `scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1`
  - `Expand-SourceIso`: replaced `Copy-Item -LiteralPath
    $src -Destination $DestRoot -Recurse -Force` with a
    `robocopy.exe` invocation that handles drive-root
    sources and emits a log file under `$Script:LogsDir`.
  - `Invoke-BuildPhase09_AssembleIso`: changed
    `Copy-Item -LiteralPath (Join-Path $tmpExtract '*') ...`
    to `Copy-Item -Path ...` so the wildcard expands.
- `scripts/powershell/update-windows-server-iso/SPEC.md`
  - Added section B.23.19 and the matching matrix row.

No data files, workflows, or tests are touched.

### r07.0 Step 13 - Fix latent `Split-Path -LiteralPath -Leaf` parameter-set conflict at 7 sites

Triggered by a failure observed on the freshly-pushed Step 12
commit. With the empty-LocalPath bug fixed, P04 finally
reached Step 2 'Patches' and the very first per-patch
statement hit a different runtime error:

```
[+] Existing ISO found (6.68 GB); skipping download.
[*] Recorded ISO SHA-256: ceb4e1f786148782bd684853bda9c6177891da231eb0ca2b5a17130ec938b142
 -- Step 2: Patches ---------------------------------------------
 PHASE P04  -> FAILED   elapsed: 10.56s
 [X] Phase P04 (FetchAssets) failed:
     指定された名前のパラメーターを使用してパラメーター
     セットを解決できません。
 [~]     Invoke-FetchPhase04_FetchAssets, Update-WindowsServerIso.ps1: line 8827
```

Line 8827 contained
`$leaf = Split-Path -LiteralPath $p.LocalPath -Leaf`.
PowerShell rejects this combination at runtime on both
5.1 and 7: `-LiteralPath` and `-Leaf` belong to mutually
exclusive parameter sets. `-LiteralPath` only combines
with `-Resolve` and `-Credential`; `-Leaf` only combines
with the positional `-Path` form. The cmdlet docs do not
emphasise this collision, PSScriptAnalyzer does not flag
it as a static-analysis issue, and the `-LocalPath ...
-Leaf` shape is so syntactically natural that it has
slipped past review for multiple revisions of this
script.

The same parameter-set conflict was actually noticed
earlier for the `-LiteralPath ... -Parent` pair (see the
inline comment above the L1519 `[System.IO.Path]::
GetDirectoryName` call, which already documents the
`AmbiguousParameterSet at runtime` failure mode). The
`-Leaf` and `-LeafBase` variants of the same bug
continued to lurk in seven other places because their
code paths were unreachable in the regression suite
(P04 Step 2 only ran after Step 12; the DISM apply
helpers ran only live; the side-car LeafBase site
required a specific patch-directory layout).

Step 13 replaces all seven sites with
`[System.IO.Path]::GetFileName(...)` (or
`GetFileNameWithoutExtension(...)` for the LeafBase
case), matching the precedent set by the existing
`GetDirectoryName` migration:

```
L2478:  $name = Split-Path -LiteralPath $IsoPath -Leaf
     -> $name = [System.IO.Path]::GetFileName($IsoPath)

L5770:  Set-DebugStep -Step ('add-pkg-' +
            (Split-Path -LiteralPath $PackagePath -Leaf))
     -> Set-DebugStep -Step ('add-pkg-' +
            [System.IO.Path]::GetFileName($PackagePath))

L5783:  Write-Warn (... -f
            (Split-Path -LiteralPath $PackagePath -Leaf))
     -> Write-Warn (... -f
            [System.IO.Path]::GetFileName($PackagePath))

L7008:  ... -f $type, $kb,
            (Split-Path -LiteralPath $pkgPath -Leaf
                                  -ErrorAction SilentlyContinue)
     -> ... -f $type, $kb,
            [System.IO.Path]::GetFileName($pkgPath)

L7040:  ... -f $type, $kb,
            (Split-Path -LiteralPath $pkgPath -Leaf)
     -> ... -f $type, $kb,
            [System.IO.Path]::GetFileName($pkgPath)

L8392:  $sideCar = Join-Path $f.DirectoryName
            ((Split-Path -LiteralPath $f.FullName -LeafBase)
             + '.meta4')
     -> $sideCar = Join-Path $f.DirectoryName
            ([System.IO.Path]::GetFileNameWithoutExtension(
             $f.FullName) + '.meta4')

L8827:  $leaf = Split-Path -LiteralPath $p.LocalPath -Leaf
     -> $leaf = [System.IO.Path]::GetFileName($p.LocalPath)
```

The L7008 call dropped its
`-ErrorAction SilentlyContinue` parameter; that
suppression was silently swallowing the parameter-set
error all this time, leaving an empty `({2})` placeholder
in the DryRun log without surfacing the bug. The .NET
API does not throw on empty input (it returns an empty
string), so future regressions on the input value will
now become visible rather than hidden.

Live verification awaits the operator's re-run. With the
ISO cached at `D:\UpdateWsi\source\iso\WS2016_ja-jp.iso`
and the SHA-256 already recorded, P04 Step 1 will skip
the download within ~10 seconds and Step 2 should reach
the actual patch downloads:

```
[1/2] windows10.0-kb5087537-x64_1a68955...msu
    [~1.5 GB LCU download from catalog.s.download.windowsupdate.com]
[2/2] windows10.0-kb5087065-x64-ndp48_631ce425...msu
    [~70 MB .NET CU download]
```

Files changed:

- `scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1`
  - Seven `Split-Path -LiteralPath ... -Leaf` /
    `-LeafBase` sites replaced with `[System.IO.Path]
    ::GetFileName` / `::GetFileNameWithoutExtension`.
  - One `-ErrorAction SilentlyContinue` dropped (L7008)
    because the underlying call no longer throws.
- `scripts/powershell/update-windows-server-iso/SPEC.md`
  - Added section B.23.18 documenting the parameter-set
    collision and the migration policy. Added the
    matching matrix row.

No data files, workflows, or tests are touched. Three
in-source comments still mention `Split-Path
-LiteralPath` (one is the original L1519 documentation
that motivated this migration; the other two are
`Step 12` rationale strings added in the previous
revision and intentionally kept as historical context).

### r07.0 Step 12 - Fix P02/P03 baseline seeding `LocalPath = ''` regression

Triggered by a failure observed on the freshly-pushed Step 11
commit, immediately after the ~13-minute Server 2016 ja-jp
Eval ISO download succeeded:

```
[+] ISO downloaded: D:\UpdateWsi\source\iso\WS2016_ja-jp.iso
[*] Recorded ISO SHA-256: ceb4e1f786148782bd684853bda9c6177891da231eb0ca2b5a17130ec938b142
 -- Step 2: Patches ---------------------------------------------
 PHASE P04  -> FAILED   elapsed: 13m5.9s
 [X] Phase P04 (FetchAssets) failed:
     引数が空の文字列であるため、パラメーター 'LiteralPath'
     にバインドできません。
 [~]     Invoke-FetchPhase04_FetchAssets, Update-WindowsServerIso.ps1: line 8782
```

Line 8782 of P04 reads `$leaf = Split-Path -LiteralPath
$p.LocalPath -Leaf`, and the `$p.LocalPath` field of the first
patch entry was an empty string. The regression was introduced
in Step 9 when this CHANGELOG noted that P02's NeutralPatches
lookup had been fixed - the lookup itself was fixed, but the
*seeding* loop that converts `PatchBaseline.NeutralPatches[]`
into `$Script:ResolvedPatches` was carried over with
`LocalPath = ''` hard-coded, the very bug it should have
replaced. The empty value propagated through the baseline
into the first iteration of the P04 download loop, where the
`Split-Path -LiteralPath` call rejected it.

The bug only surfaces with `-UseBaselineOnly` because the
other patch-source paths (`-PatchUrls`, `-PatchDirectory`,
`-ManifestPath`) each compute LocalPath inline before adding
the entry to `$resolved`. With `-UseBaselineOnly` on, the
NeutralPatches-seeding path is the *only* place LocalPath
gets set, and the bug had no escape valve.

Two seeding sites carried the same defect: the P02 baseline
seeding at L8438-8447 and the P03 RefreshPatchBaseline
re-derive at L8704-8716. Step 12 fixes both with the same
helper shape so they stay in lockstep through any future
refactoring:

- `LocalPath` is derived from `$p.FileName` when present
  (the NeutralPatches schema since v3.x always emits
  FileName), falls back to
  `[System.IO.Path]::GetFileName(([Uri]$p.DownloadUrl).AbsolutePath)`
  for legacy entries that omit FileName, and finally falls
  back to `'<KbId>.msu'` if both are missing. The full path
  becomes `Join-Path $Script:PatchesDir (Join-Path
  $Script:OsVersion $pFileName)`, matching the other seeding
  paths in the same function (L8362 and L8375 see the same
  Join-Path shape).
- `ExpectedHashes` is built incrementally - it starts as
  `@{}` and only gets a `sha-256` key when `$p.Sha256` is
  non-empty. The previous code wrote
  `@{ 'sha-256' = $p.Sha256 }` unconditionally, so an empty
  baseline hash produced a hashtable with `.Count = 1` that
  forced P04's cache-validation branch to call
  `Test-PatchIntegrity` against the empty string instead of
  taking the 'no hash to verify; skipping download' fast
  path. That dormant bug would have surfaced on the second
  invocation after a cache existed.

Live verification awaits the operator's re-run of the same
PrepareBuildVerify command. P04 Step 1 (ISO download) is
already cached from the previous 13-minute fetch, so the
next run should reach Step 2 (Patches) within seconds. The
expected behaviour: `[1/2] windows10.0-kb5087537-x64_...msu`
shown by Write-Step, then a ~1.5 GB LCU download for KB5087537
followed by a ~70 MB .NET CU download for KB5087065, after
which P05 ExpandIso takes over and starts unpacking the ISO.

Files changed:

- `scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1`
  - Two patch-seeding sites updated to compute LocalPath
    from FileName and to build ExpectedHashes only when
    Sha256 is non-empty. Surrounding code unchanged.
- `scripts/powershell/update-windows-server-iso/SPEC.md`
  - Added section B.23.17 (P02/P03 LocalPath derivation +
    ExpectedHashes guard) and the matching matrix row.

No data files, workflows, or tests are touched.

### r07.0 Step 11 - Replace flaky `microsoft/psscriptanalyzer-action` with inline PSScriptAnalyzer+ConvertToSARIF (CI hardening)

Triggered by a stage2 Windows-checks workflow failure observed on
the freshly-pushed Step 10 commit:

```
[PSSA-pwsh51] Run microsoft/psscriptanalyzer-action
  Install-Package: No match was found for the specified search criteria
                   and module name 'ConvertToSARIF'.
                   Try Get-PSRepository to see all available registered
                   module repositories.
Error: Process completed with exit code 1.
```

The PowerShell script under analysis was untouched in Step 10 (the
commit was a data-only refresh of `Iso.Url` + `Iso.FwlinkUrl`), so
the failure was unrelated to the Step 10 content. Investigation
showed the failure mode is in the `microsoft/psscriptanalyzer-action`
Marketplace action itself, which has been observed failing
intermittently against PowerShell Gallery, including on Microsoft's
own CI of that action (workflow run 21604137629 on 2026-02-02).
The repository's README is also unmodified from the GitHub
template, which is a strong signal that the action is in a
semi-maintained state.

The root cause of the install failure is well-understood:
`Install-Module -Name ConvertToSARIF -Force` on a windows-latest
runner sometimes hits a NuGet provider or PSGallery registration
state that returns "no match" rather than a clear connectivity
error. Re-running the same workflow shortly after typically
succeeds, but that fragility is not acceptable for a release-
gating CI step.

This step replaces the action call in BOTH the stage1 (Linux
pwsh 7) and stage2 (Windows PS 5.1) workflows with an inline
two-step pipeline:

1. **Install step** - explicit TLS 1.2 enforcement, NuGet provider
   preflight (install `2.8.5.201+` if missing), PSGallery registration
   + trust, and a small `Install-ModuleWithRetry` helper that
   retries each `Install-Module` up to 3 times with exponential
   backoff. The helper skips installation entirely when
   `Get-Module -ListAvailable` already finds the module, which
   keeps re-runs fast.

2. **Run step** - `Import-Module ConvertToSARIF -Force`, then
   `Invoke-ScriptAnalyzer -Path ... -Settings ... | ConvertTo-SARIF
   -FilePath pssa.sarif`. Identical output shape to what the
   removed action produced, so the downstream
   `github/codeql-action/upload-sarif@v4` step and the SARIF text
   log generator both continue to work without changes.

Why inline instead of pinning to a maintained alternative
(`PSModule/Invoke-ScriptAnalyzer@v4` etc.): the analysis is four
real PowerShell commands (install + import + analyze + convert).
Inlining them is cheaper than depending on any third-party action
for that surface area, and lets us add the TLS / NuGet / retry
guards that the original action lacked. The Linux stage1 was not
yet exhibiting the failure but is updated to the same pattern for
defense in depth - the same PSGallery flake could hit any runner
at any time.

Files changed:

- `.github/workflows/scripts__powershell__update-windows-server-iso__stage1__linux.yml`
  - Replaced the `microsoft/psscriptanalyzer-action@v1.1` step
    with two inline steps (install with retry, then analyze).
    The `if:` scope guard
    (`scope == 'all' || scope == 'pssa-only' || ...`)
    is preserved on both new steps.
- `.github/workflows/scripts__powershell__update-windows-server-iso__stage2__windows.yml`
  - Same replacement applied to the Windows-checks stage.

No PowerShell script, SPEC, README, data, or test files are
touched in this step. CI workflow changes are policy-recorded
here in CHANGELOG.md per the repository-wide invariant noted at
the top of this file (CI changes do not get their own commit
message in `.github/workflows/*` history alone).

Live verification awaits the operator's commit + push: the
stage1 run should complete with the new inline install logs
visible, and the chained stage2 should run to completion
without the `ConvertToSARIF not found` failure.

### r07.0 Step 10 - Refresh Eval ISO URLs for all 4 supported Server OSes; record fwlink (metalink) alongside direct CDN URL

Pure data refresh triggered by an HTTP 400 Bad Request from
P04 FetchAssets when downloading the Server 2016 ja-jp ISO:

```
PHASE P04 (FetchAssets) failed:
  リモート サーバーがエラーを返しました: (400) 要求が不適切です
  at Invoke-WebRequestWithRetry, line 1944
  Source URL: https://software-download.microsoft.com/download/sg/14393.0.161119-1705.RS1_REFRESH_SERVER_EVAL_X64FRE_JA-JP.ISO
```

The Microsoft Evaluation Center had retired the
`software-download.microsoft.com/download/sg/` host; live
verification with `software-static.download.prss.microsoft.com`
and `download.microsoft.com/download/E/0/9/...` (Server 2016
ja-jp specifically uses the legacy Download Center GUID path)
confirmed the new canonical URLs. Step 9's fixes to
`Invoke-WebRequestWithRetry` and the P02 NeutralPatches lookup
both proven correct - the function reached Microsoft and got a
clean HTTP 400 with three retry attempts in the expected
backoff cadence (2 s, 4 s, then bail), which is exactly the
behaviour intended by the retry wrapper.

This step refreshes the URL pool. For each of the 4 OSes
(Server2016, 2019, 2022, 2025) and 2 languages (en-us, ja-jp),
the `LanguageSpecific.<lang>.Iso` block now carries:

- `Url` - the **current** direct CDN URL (what the script
  actually downloads). Hosts vary per OS:
  - Server 2016 en-us:  `software-static.download.prss.microsoft.com/pr/download/`
  - Server 2016 ja-jp:  `download.microsoft.com/download/E/0/9/`
  - Server 2019 (both): `software-static.download.prss.microsoft.com/dbazure/988969d5-.../17763.3650.221105-1748...`
  - Server 2022 (both): `software-static.download.prss.microsoft.com/sg/download/888969d5-...`
  - Server 2025 (both): `software-static.download.prss.microsoft.com/dbazure/998969d5-.../26100.32230.260111-0550...`
- `FwlinkUrl` (NEW) - the canonical Microsoft fwlink metalink.
  For Server 2016 / 2019 / 2022, a single linkid serves both
  languages and the `clcid` query parameter selects the locale.
  For Server 2025 each language has its own linkid (2345730 for
  en-us, 2345828 for ja-jp). Recorded for documentation and as
  a recoverable starting point when the direct URL rotates
  again.
- `FileName` - updated to match the direct URL's basename. Two
  OSes saw a build refresh: Server 2019 from
  `17763.737.190906-2324.rs5_release_svc_refresh` to
  `17763.3650.221105-1748.rs5_release_svc_refresh`, and Server
  2025 from `26100.1742.240906-0331.ge_release_svc_refresh` to
  `26100.32230.260111-0550.lt_release_svc_refresh`. The codename
  suffix change for Server 2025 (`ge_release` to `lt_release`)
  reflects the underlying Windows codename rotation.
- `_VerifiedDate` and `_VerifiedBy` - set to `2026-05-26` and
  `manual:r07.0-Step10-IsoUrl-refresh` respectively, so the
  next stage5 / RefreshAllBaselines audit knows when and by
  whom each URL was last sighted live.

No script logic changes in this step. `Resolve-IsoSourceUrl`
still reads `Iso.Url` verbatim. A future opt-in
`-PreferFwlinkUrl` switch could let the script try the fwlink
first and fall back to `Url` on failure - the data shape
already supports it - but that path is deferred until live
URL rotations make it worth the extra HTTPS round trip per
download. The recorded fwlink remains useful immediately: when
a direct URL rotates, the operator can paste the fwlink into a
browser, follow the 302 redirect to the new direct URL, and
patch the config in one paste.

Files changed:

- `scripts/powershell/update-windows-server-iso/data/config-Server2016.json`
- `scripts/powershell/update-windows-server-iso/data/config-Server2019.json`
- `scripts/powershell/update-windows-server-iso/data/config-Server2022.json`
- `scripts/powershell/update-windows-server-iso/data/config-Server2025.json`
  - Updated `LanguageSpecific.{en-us,ja-jp}.Iso.{FileName,Url}`;
    inserted new `Iso.FwlinkUrl` field; bumped
    `_VerifiedDate` / `_VerifiedBy`.
- `scripts/powershell/update-windows-server-iso/SPEC.md`
  - Added section B.23.16 (dual-URL design + locale-mismatched
    clcid analysis + build-refresh notes) plus a matching row
    in the §B.23 cross-reference matrix.

Live verification awaits the operator's re-run of the same
PrepareBuildVerify command that hit the HTTP 400 - it should
now reach the ISO download successfully and continue through
P04 to P05 ExpandIso.

### r07.0 Step 9 - Fix P02 NeutralPatches lookup, fix P04 ISO/patch download path, polish ADK auto-install

Live regression-test of `-Action PrepareBuildVerify -EvalIsoMode
-UseBaselineOnly -AutoInstallAdk` against a freshly-provisioned
Windows Server 2025 host surfaced three issues. Step 8's
`-AutoInstallAdk` switch worked perfectly (oscdimg.exe was
downloaded + installed in ~30 seconds and P01 / P02 / P03 all ran
to completion). But the test then exposed two pre-existing latent
bugs in the script + one cosmetic redundancy that Step 8
introduced. All three are fixed together in this step.

**Fix 1 - P02 reads `PatchBaseline.NeutralPatches[]` (was `.Patches`)**.

`Invoke-SetupPhase02_ResolveInputs` was still looking at
`$Script:OsProfile.PatchBaseline.Patches` for the
`-UseBaselineOnly` code path, but the field name was migrated to
`NeutralPatches` as part of the r07.0 data layout (committed via
`-Action RefreshAllBaselines` / stage5). The result was that
`-UseBaselineOnly` consistently produced `Patch list resolved: 0
entries` on every config that had ever been refreshed, silently
forcing P02 into an empty patch plan and making the eventual
ISO build skip every patch entirely. The fix prefers
`.NeutralPatches[]` (the SPEC B.23.5 source of truth) and falls
back to legacy `.Patches[]` for backward compatibility with any
config not yet migrated.

**Fix 2 - `Invoke-WebRequestWithRetry` now accepts `-OutFile`,
`-Headers`, and the `-MaxAttempts` alias**.

The wrapper function declared only `-Uri / -MaxRetries /
-TimeoutSec`, but every one of its three call sites (P04 source
ISO download, P04 patch download, P06 wsusscn2.cab download)
called it with `-OutFile`, and two of them with the alias
`-MaxAttempts`. The mismatch had been latent because none of those
download paths had ever been taken to completion against a real
host with a populated baseline. Step 7's `-UseBaselineOnly` plus
Step 8's `-AutoInstallAdk` together made it the first real
end-to-end run, and `Invoke-WebRequestWithRetry` threw immediately
on first use:

```
PHASE P04 (FetchAssets) failed: パラメーター名 'OutFile' に一致するパラメーターが見つかりません。
```

The fix extends `Invoke-WebRequestWithRetry` with proper
`-OutFile` support (streaming to disk with the canonical
`$ProgressPreference = 'SilentlyContinue'` workaround for PS 5.1's
multi-GB Invoke-WebRequest progress-bar slowdown), `-Headers`
support (used by the wsusscn2.cab path for a custom User-Agent),
and a `-MaxAttempts` alias for `-MaxRetries`. The function also
no longer references undefined `$Script:UserAgent` and
`$Script:RequestHeaders`, which would have caused an Invoke-
WebRequest argument-binding error in the in-memory mode if it had
ever been called.

**Fix 3 - polish `Install-WindowsAdkFallback` to avoid double
SHA-256 advisory**.

The Step 8 implementation called `Resolve-OscdimgExe` twice in
the auto-install path: once inside `Install-WindowsAdkFallback`
for the tool-presence verify, and once again in the P01 Step 3
`catch` block for the canonical Write-Ok log line. Each call
emits the Microsoft reference-hash SHA-256 advisory when the
local oscdimg.exe doesn't match the v1.4 reference value, so the
warning block was logged twice for the same binary. The fix:
`Install-WindowsAdkFallback` now returns the discovered
`oscdimg.exe` path, and P01 Step 3 uses the returned value
directly with a single Write-Ok rather than re-resolving.

Files changed:

- `scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1`
  - P02 patch-resolution block: read `NeutralPatches[]` (preferred)
    or `Patches[]` (legacy fallback); update log message and
    error message accordingly.
  - `Invoke-WebRequestWithRetry`: add `-OutFile`, `-Headers`,
    `-MaxAttempts` alias; drop dead `$Script:UserAgent /
    $Script:RequestHeaders` references; declare `[OutputType()]`.
  - `Install-WindowsAdkFallback`: return `[string]` (resolved
    path) instead of `[void]`; declare `[OutputType([string])]`.
  - P01 Step 3 auto-install branch: consume the return value;
    remove the now-redundant second `Resolve-OscdimgExe` call.

Regression coverage. T2-T10 all pass (their PowerShell-from-Python
harness does not exercise P02 / P04 / Install-WindowsAdkFallback,
so the data-format and PoC-replacement assertions are unaffected).
psa.py reports 0/0/0; PSScriptAnalyzer reports 0 errors and 0
warnings. End-to-end verification awaits the operator's re-run on
the Windows Server 2025 host.

### r07.0 Step 8 - `-AutoInstallAdk` switch for hands-free Windows ADK Deployment Tools install

Pure environment-provisioning addition triggered by a live P01 abort
on a freshly-provisioned Windows Server 2025 host that lacked the
Windows ADK Deployment Tools (`oscdimg.exe`). The previous P01 Step 3
behaviour was correct (fail fast before the 5-6 GB Evaluation ISO
download in P04) but required an out-of-band install before any
real ISO build attempt. Step 8 makes the install optional and
automatic via a new opt-in switch.

The implementation mirrors the SDK/WDK fallback pattern in the
sibling [`Deploy-AMDChipsetDriverOnWindowsServer.ps1`](https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer/blob/main/Deploy-AMDChipsetDriverOnWindowsServer.ps1)
script — `Install-WindowsSdkFallback` /
`Install-WindowsWdkFallback` at ~L5408-5449 of that script.
Specifically:

1. Download a pinned `adksetup.exe` (Microsoft Learn fwlink
   `linkid=2289980`, ADK `10.1.26100.2454` December 2024) to a
   cache directory.
2. Run with `/features OptionId.DeploymentTools /quiet /norestart
   /ceip off /log <log>` to install only the Deployment Tools
   feature (~50-80 MB) — never the full ADK (~3+ GB).
3. Verify by tool presence rather than trusting the exit code,
   because installer EXEs in this family return non-zero when the
   kit is already on the machine. "Tool present + non-zero exit"
   is logged as warn-only "already installed"; only "tool still
   absent" is a hard failure.

The Decemnber-2024 ADK is the right pin for any Server x64 build
host: Microsoft Learn documents it as supporting Server 2025,
Server 2022, and every earlier supported Windows 10/11 release,
and the Deployment Tools binary is forward-compatible — oscdimg
from this ADK assembles ISOs targeting Server 2016 / 2019 / 2022 /
2025 without per-target-OS variants. The newer ADK
`10.1.28000.1` (November 2025) is Windows 11 26H1 Arm64 only and
explicitly NOT appropriate for Server work.

**Default off, opt-in only**. Without `-AutoInstallAdk`, P01 still
throws — but the error message now includes the canonical download
URL, the silent-install command line, and the expected oscdimg.exe
path, so operators in locked-down or air-gapped environments have
everything they need on screen to install the ADK out-of-band.

The existing `Resolve-OscdimgExe` (with its
`Make2023BootableMedia.ps1` v1.4 hash-verification block) is
unchanged and continues to apply to the auto-installed binary.
A hash mismatch remains advisory because ADK servicing patches
can legitimately change the SHA-256 of `oscdimg.exe`.

Files changed:

- `scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1`
  — Added `$Script:AdkInstallerUrl`/`Version`/`OptionId` constants,
  the `-AutoInstallAdk` switch + Script-scope propagation, the new
  `Install-WindowsAdkFallback` function (~120 LOC), and P01 Step 3
  catch-block branching to honour the switch + emit the improved
  error message when not set.
- `scripts/powershell/update-windows-server-iso/SPEC.md`
  — Added §B.23.15 (design notes: pinning rationale, opt-in by
  default, feature-restricted install, verify-by-tool-presence,
  cache placement) and a matching row in the §B.23 cross-reference
  matrix.
- `scripts/powershell/update-windows-server-iso/README.md`
  and `README.ja.md` — Added a Troubleshooting subsection
  documenting the `-AutoInstallAdk` switch alongside the existing
  PowerShell 5.1 / Administrator / DISM prerequisites.

Existing T2-T10 regression tests are unchanged: all 6 test files
(`catalog_fixture_test.py`, `catalog_title_tokens_test.py`,
`dotnet_cu_parser_test.py`, `dynamic_update_cache_test.py`,
`release_info_parser_test.py`, `release_info_resolver_test.py`)
still pass, because Step 8 lives entirely in the P01 prerequisite
layer and does not touch any release-info / dotnet-cu / DU code
paths. psa.py reports 0/0/0; PSScriptAnalyzer reports 0 errors
and 0 warnings.

### r07.0 Step 7 - Server 2016 LCU vs .NET CU same-KB dedup in the discovery layer

Bug-fix and SPEC-formalisation commit triggered by live verification
of Step 6's RefreshSnapshots -> RefreshAllBaselines pipeline against
the 2026-05 Patch Tuesday data on a clean Windows host. The pipeline
populated `data/cache-release-info.json` + `data/cache-dotnet-cu.json`
correctly and produced the expected per-OS NeutralPatches[] counts
for Server 2019 / 2022 / 2025, but Server 2016 emitted three entries
where SPEC §B.23.5 expects two: a Type=LCU record for KB5087537 plus
two Type=DotNet.Runtime records (KB5087537 again, KB5087065). Forensic
inspection showed the duplicate KB5087537 .NET CU record pointed at
the **same .msu file** as the LCU record -- same FileName, same
DownloadUrl, same SHA256, same UpdateId, same Supersedes list -- with
only the `Type` value differing.

**Root cause**. Microsoft Learn's `.NET Framework release-notes`
page for 2026-05 contains the row pair

```
| **Windows 10 1607 and Windows Server 2016** |  |
| .NET Framework 3.5, 4.6.2, 4.7, 4.7.1, 4.7.2 | [5087537](.../kb/5087537) |
| .NET Framework 4.8 | [5087065](.../kb/5087065) |
```

where `KB5087537` is the same KB as the Server 2016 monthly LCU in
`windows-server-release-info`. This is not a Microsoft-side mistake:
the Windows 10 1607 / Server 2016 era LCU follows a "sliced
cumulative update" design where the LCU literally embeds the
.NET 3.5 / 4.6.2 / 4.7.x cumulative-update payload as OS components,
and only .NET 4.8 is shipped as a separate `KB5087065` .msu. The .NET
release-notes faithfully reflects this design. Server 2019 / 2022 /
2025 split the .NET CU into independent KBs and do not exhibit this
overlap (verified live: zero KB overlap across LCU + .NET CU rows for
those three OSes in 2026-05).

**Fix**. Single insertion in
`Get-PatchSetFromReleaseInfoDiscovery` (the pure-cache discovery
half of `Resolve-PatchSetFromReleaseInfo`): immediately before the
`.NET CU from dotnet-cu cache` section, build a
case-insensitive `HashSet[string]` of the LCU `KbId` values already
appended to the discovery record list; inside the per-row .NET CU
loop, skip any row whose `KbId` is present in that set, emitting a
`Write-Verbose` log line citing SPEC §B.23.5 B-3 for forensic
visibility. The skipped row remains verbatim in
`data/cache-dotnet-cu.json` -- the cache is the authoritative
Microsoft snapshot; the dedup is a policy decision applied at
read time, not a destructive cache filter, so a future SPEC
revision can revisit the policy without re-fetching.

Total PS1 change: ~30 lines (1 HashSet construction block + 1
per-row guard + verbose log). No new function. No schema change.

**Resulting behaviour, live verified against the 2026-05 cache**:

```
Server2016   Discovery before fix : 3 records  (LCU + 2 DotNet.Runtime)
Server2016   Discovery after fix  : 2 records  (LCU + 1 DotNet.Runtime)
             KB5087537 appears once (Type=LCU); KB5087065 appears once (Type=DotNet.Runtime)
Server2019   Discovery (unchanged): 3 records  (LCU + 2 DotNet.Runtime)
Server2022   Discovery (unchanged): 4 records  (LCU + 2 DotNet.Runtime + DU.SafeOs)
Server2025   Discovery (unchanged): 3 records  (LCU + 1 DotNet.Runtime + DU.SafeOs)
```

The Server 2016 NeutralPatches[] count now matches the SPEC §B.21.2
per-OS expected count table: 2 entries (1 LCU + 1 .NET CU), not 3.

**SPEC update**. A new sub-decision **B-3 (LCU vs .NET CU same-KB
dedup)** has been added to SPEC §B.23.5 between B-2 and the
existing Consequences block. The new sub-decision documents:

- Context: the Microsoft Learn release-notes row pair that triggers
  the overlap, with the canonical 2026-05 Server 2016 example
  inline.
- Decision: LCU is the authoritative source for any KB it carries,
  with the rationale that (a) LCU's Catalog row exposes the canonical
  two-.msu resolution that the resolver relies on for SPEC B.23.5
  B-1 combined-LCU detection, and (b) the .NET re-listing carries
  no information the LCU does not already provide.
- Implementation: location, mechanism, forensic visibility via
  `Write-Verbose`, and the non-destructive cache property.

The "Consequences" heading at the end of §B.23.5 has been updated
to reference B-1, B-2, and B-3 together.

**T10 regression coverage**. `tests/release_info_resolver_test.py`
gains a new scenario in `tests/fixtures/release_info_resolver/
scenarios.json`:

- `release_info_cache.MonthlyReleases[]` gets a Server 2016 row
  (KB5087537, 2026-05 B).
- `dotnet_cu_cache.Months[2026-05].Entries[]` gets the
  `OsNormalised=Server2016` block with the duplicate-KB row pair
  exactly as captured live (KB5087537 for .NET 3.5/4.6.2/4.7.x,
  KB5087065 for .NET 4.8).
- `du_entries_by_os.Server2016 = []` for symmetry with Server 2019.
- A new `queries[]` entry expects `record count = 2`,
  `Types = [LCU, DotNet.Runtime]` (KB5087537 once as LCU,
  KB5087065 once as DotNet.Runtime).

T10 assertion total: 18 -> 22 (+4 from the new scenario). The
T10 inventory row in SPEC's "Part G test inventory" has been
updated accordingly.

**No breaking change**. The existing `data/config-Server2016.json`
committed at HEAD is not modified by this commit (the Refresher
writes it on next run). `$Script:ScriptVersion` stays at
`update-wsi-2026.05.26-r07.0`; this is a Step 7 follow-on under
the same release rather than a new release. `data/raw-*.*` and
`data/cache-*.json` are unaffected -- the dedup is applied at
read time, not at cache-write time, so re-running A03
RefreshSnapshots is **not required** to take advantage of the fix.

**Quality-gate status**: psa.py 0/0/0, PSScriptAnalyzer 0
findings, PowerShell parse OK, T2 13/13, T3 10/10, T6 13/13,
T7 16/16, T8 20/20, T9 18/18, **T10 22/22 (+4)**. Cumulative
112/112 PASS (up from 108/108 in r07.0 Step 6).

### r07.0 Step 6 - Implement `-Action RefreshSnapshots` (A03) and document the two-stage refresh workflow

Implementation gap closure for SPEC §B.23.7 / §B.23.14. The
previous r07.0 commits ported the parser / resolver logic into
the PowerShell main script and migrated the discovery layer to
cache-driven (`Get-PatchSetFromReleaseInfoDiscovery`,
`Resolve-PatchSetFromReleaseInfo`), but never wired the
cache-populating helpers (`Invoke-ReleaseInfoFetch`,
`Update-ReleaseInfoCache`, `Invoke-DotNetCuFetch`,
`Update-DotNetCuCache`, `Add-DynamicUpdateCacheEntry`) into a
user-facing Action. Live verification on a clean Windows host
exposed the gap: running `-Action RefreshAllBaselines` with no
caches present emitted "Discovery returned zero records" for
every OS, and the resulting `data/config-Server*.json` files
had empty `PatchBaseline.NeutralPatches[]`. This commit closes
the gap with the SPEC-blessed name (`RefreshSnapshots`).

**New functions in `Update-WindowsServerIso.ps1` (3)**:

- `Get-DynamicUpdateProbePlan` (helper) -- returns the per-OS
  DU probe target table. Restricted to Server 2022 + Server
  2025 (each with Setup + SafeOs) per SPEC §B.23.6; Server 2019
  has no DU rows in release-info and Server 2016 predates the
  modern "Dynamic Update" naming.
- `Invoke-AdminPhaseA03_RefreshSnapshots` (~290 lines) -- the
  A03 phase body. Three fault-tolerant sub-steps:
  1. release-info: `Invoke-ReleaseInfoFetch` ->
     `Update-ReleaseInfoCache`. Writes
     `data/raw-release-info.md` (+ `.meta.json`) and
     `data/cache-release-info.json`.
  2. .NET CU: `Invoke-DotNetCuFetch` ->
     `Update-DotNetCuCache`. Writes `data/raw-dotnet-cu.json`
     and `data/cache-dotnet-cu.json`.
  3. Dynamic Update probes: iterates the
     `Get-DynamicUpdateProbePlan` table; for each (OS, DuType),
     builds a Catalog Search.aspx query of the form
     `"<patchMonth> <DuLabel> for <OsToken>"`, calls
     `Get-UpdateIdFromCatalog`, narrows results via
     `Test-CatalogTitleMatch`, deduplicates with
     `Select-LatestPatchBySupersedence` when multiple hits
     survive, and persists each result (success or
     `IsEmptyMarker`) via `Add-DynamicUpdateCacheEntry`.
  Honours `-DryRun` (skips all HTTP fetches), honours
  `-PatchMonth` override for parity with A01. Emits an
  A01-style end-of-run summary with per-cache status, per-probe
  result, and a "next step" hint pointing at
  `RefreshAllBaselines`. Failure of one sub-step is logged but
  does not abort the remaining sub-steps. Returns `$true` iff
  every sub-step reported OK or Skipped.
- `Show-RefreshSnapshotsSummary` (helper) -- renders the rich
  end-of-run summary table block for A03, modelled on
  `Show-RefreshAllBaselinesSummary`.

**Wiring changes (5 single-line edits)**:

- Parameter `[ValidateSet]` on `$Action` -- added
  `'RefreshSnapshots'` between `'GenerateManifest'` and
  `'RefreshAllBaselines'`.
- `$osLessActions` array -- added `'RefreshSnapshots'` (A03
  operates on `data/` files, not on a specific OS x language
  ISO).
- `$Script:PhaseRegistry` -- added the A03 row mapping
  `Id='A03' / Name='RefreshSnapshots' / Group='Admin' /
  Func='Invoke-AdminPhaseA03_RefreshSnapshots'` immediately
  after A02.
- `Get-PhaseListByAction` switch -- added the
  `'RefreshSnapshots' -> [string[]]@('A03')` case.
- `Show-PhaseList` hardcoded action enumeration -- inserted
  `'RefreshSnapshots'` between `'GenerateManifest'` and
  `'RefreshAllBaselines'` so the `-Action ListPhases` output
  shows it.

**Pre-existing bug fix (drive-by, 3 occurrences)**:

- `Get-UpdateIdFromCatalog`,
  `Get-DownloadLinkFromCatalog`,
  `Get-SupersedenceFromCatalog` each had a retry path that
  called `Wait-WithJitter -BaseSeconds 2 -MaxSeconds 5`. The
  helper's actual parameter is `-JitterRange`, not
  `-MaxSeconds`; the typo silently bound `-MaxSeconds 5` to no
  parameter, leaving `$JitterRange` at its `[double]` default
  of 0, which made `Get-Random -Minimum 0 -Maximum 0` throw
  "The Minimum value (0) cannot be greater than or equal to
  the Maximum value (0)". The bug only fired on a retry path,
  so live operation seldom hit it; A03's DU probe loop
  reliably reproduced it because successive rapid Catalog hits
  triggered rate-limit retries. Fixed by replacing
  `-MaxSeconds 5` with `-JitterRange 1` (about 2s +/- 1s of
  jitter) at all three call sites.

**SPEC.md updates (3 sections)**:

- §B.23.7 -- the tentative "(`-Action RefreshSnapshots` or an
  equivalent name decided at implementation time)" phrasing
  has been replaced with the implemented form
  "(`-Action RefreshSnapshots`, implemented as the A03 Admin
  phase)".
- §B.23.14 -- the cross-reference matrix row for B.23.7 now
  reads `-Action RefreshSnapshots (A03, implemented r07.0
  Step 6)`. A new "A03 RefreshSnapshots implementation
  (completed in r07.0 Step 6)" subsection was added
  immediately before the existing PoC retirement subsection,
  summarising the sub-step composition, the DU probe target
  table rationale (Server 2022 + 2025 only per §B.23.6), and
  noting that the companion `stage5__data-snapshot.yml`
  workflow remains a small follow-up (modelled on
  `stage4__monthly-refresh.yml` with `RefreshAllBaselines`
  swapped for `RefreshSnapshots`) that requires no further
  PowerShell change.
- The runtime-flow numbered list in §B.23.14 step 1 now points
  at the implemented A03 phase rather than at a placeholder
  implementation name.

**README.md / README.ja.md updates**:

- The "Admin actions" section in both README files was
  rewritten to document the two-stage refresh as the canonical
  workflow: Stage 1 = `RefreshSnapshots`, Stage 2 =
  `RefreshAllBaselines`. The list of cache files Stage 1
  produces is enumerated, the new exit-code semantics for A03
  are explained, and a troubleshooting note tells operators
  who see "Discovery returned zero records" to run Stage 1
  first. The new CSV report path
  (`<WorkRoot>/logs/A03_RefreshSnapshots_report.csv`) is added
  alongside the existing A01 report path.

**Live verification on a clean working tree reproduced what
should now be the canonical workflow**:

1. `-Action RefreshSnapshots` populated all three cache
   families. release-info captured 471 monthly + 62 hotpatch
   rows (~68 KB raw, ~216 KB cache); .NET CU captured 29
   monthly pages with 254 entries total (~294 KB raw, ~110 KB
   cache); DU probes for 2026-05 returned KB5087595 (Server
   2022 / SafeOs) and KB5087588 (Server 2025 / SafeOs), with
   the (Server2022, Server2025) x Setup probes correctly
   recorded as `IsEmptyMarker` because Microsoft has not
   published Setup DU for 2026-05.
2. The subsequent `-Action RefreshAllBaselines` then produced
   non-empty `PatchBaseline.NeutralPatches[]` for every OS:
   Server2016 = 2 KBs, Server2019 = 3 KBs, Server2022 = 4 KBs
   (including the SafeOs DU), Server2025 = 4 KBs (including
   the SafeOs DU). This matches the per-OS expected count
   table in SPEC §B.21.2.

**No schema change. No breaking-config change**. Schema
versions are unchanged. `$Script:ScriptVersion` stays at
`update-wsi-2026.05.26-r07.0`; this is a Step 6 follow-on
under the same release rather than a new release. The
existing `data/config-Server*.json` files committed at HEAD
are not modified by this commit.

**Quality-gate status**: psa.py 0/0/0, PSScriptAnalyzer 0
findings, PowerShell parse OK, T2 13/13, T3 10/10, T6 13/13,
T7 16/16, T8 20/20, T9 18/18, T10 18/18. Cumulative 108/108
PASS, unchanged from r07.0 Step 5.

### r07.0 Step 5 - CI workflow: catch-up rename from `Config/` to `data/` (this release)

Mechanical follow-up to r07.0 Step 1 (commit `b34241f`,
"Rename Config/ -> data/ and update references"). The Step 1
commit updated `Update-WindowsServerIso.ps1`,
`data/config-Server*.json`, SPEC.md, and several Markdown docs to
the new `data/` + three-prefix naming scheme, but missed three
stale path references inside two CI workflow files. The
`Validate Config JSON files` check in stage1 has been failing on
every PR since b34241f as a result; the failure surfaced visibly
on the workflow run for commit `7f7d400` ("Bump script to
r07.0"). This commit closes the gap.

**Files modified (2)**:

- `.github/workflows/scripts__powershell__update-windows-server-iso__stage1__linux.yml`
  - `[Format] Validate Config JSON files` step:
    - `Path('.../update-windows-server-iso/Config')` ->
      `Path('.../update-windows-server-iso/data')`
    - required set `{'Server2016.json', ..., 'Server2025.json'}`
      -> `{'config-Server2016.json', ..., 'config-Server2025.json'}`
    - both `glob('*.json')` calls narrowed to
      `glob('config-Server*.json')` (so non-config JSON files
      under `data/` such as future `cache-*.json` or `raw-*.json`
      do not get force-validated as OS configs)
    - error message text updated from "missing Config files"
      to "missing OS config files under data/"
- `.github/workflows/scripts__powershell__update-windows-server-iso__stage4__monthly-refresh.yml`
  - `Detect Config diffs` step (line 198):
    `$configRel = '.../Config'` -> `$configRel = '.../data'`
  - `Show full diff (for log archival)` step (line 225): same
    one-line update
  - The existing `add-paths: scripts/.../data/config-*.json`
    argument to `peter-evans/create-pull-request@v8` was already
    on the new path and is unchanged

**Downstream consequences resolved**. The same workflow run that
hit the Config-JSON validation failure also reported two
`Path does not exist` errors when the `[psa.py] Upload SARIF to
Code Scanning` and `[PSSA-pwsh7] Upload SARIF to Code Scanning`
steps tried to upload `psa.sarif` and `pssa.sarif`. These were
not independent failures: the `Validate Config JSON files`
failure short-circuited the SARIF generation steps (which run
under a `success()`-implying conditional), and the upload steps
(which carry `if: always()`) then ran against absent paths. With
the validation step passing again, both SARIF generation steps
run and produce their files, and the uploads succeed.

**Local verification**.

- `python3` extraction of the updated `Validate Config JSON
  files` block executed against
  `scripts/powershell/update-windows-server-iso/data/` returns
  `OK` for all four `config-Server*.json` files (Schema=2.1,
  Build values 14393 / 17763 / 20348 / 26100, both `en-us` and
  `ja-jp` language nodes present).
- `python3 -c "import yaml; yaml.safe_load(open('<file>'))"`
  passes for both modified workflow files.
- Repository-wide grep for stale `Config/` or `/Config[^a-z]`
  references inside `.github/workflows/*.yml` returns zero hits
  after the change.

**No production-code change**. `Update-WindowsServerIso.ps1` is
not modified by this commit; it has had zero references to the
old `Config/` path since r07.0 Step 1. Schema versions are
unchanged. `$Script:ScriptVersion` stays at
`update-wsi-2026.05.26-r07.0` (this is a CI hygiene fix, not a
functional change, so SemVer is not affected).

**Quality-gate status**: psa.py 0/0/0, PSScriptAnalyzer 0
findings, PowerShell parse OK, T2 13/13, T3 10/10, T6 13/13,
T7 16/16, T8 20/20, T9 18/18, T10 18/18. Cumulative 108/108
PASS, unchanged from r07.0 Step 4.



Mechanical cleanup commit scheduled by SPEC §B.23.14. With the
parser / resolver logic now living in `Update-WindowsServerIso.ps1`
and regression coverage owned by T6-T10, the `poc_<topic>_*`
scripts and their disposable fixtures / snapshots have served
their purpose. This commit removes them as a single atomic step.

**Deleted from the repository**:

- `tests/poc_release_info_01_fetch.py`,
  `tests/poc_release_info_02_parse.py`,
  `tests/poc_release_info_03_analyse.py`,
  `tests/poc_release_info_04_resolve.py`
- `tests/poc_dotnet_cu_01_fetch.py`,
  `tests/poc_dotnet_cu_02_parse.py`
- `tests/poc_dynamic_update_01_probe.py`
- `tests/fixtures/poc_release_info/` (5 disposable derived
  files: `baseline-month-detection.json`,
  `coverage-summary.json`, `letter-frequency.json`,
  `resolve-sample.json`, `update-type-summary.csv`)
- `tests/fixtures/poc_dotnet_cu/` (2 files:
  `release-notes-index.json`, `sample-month.json`)
- `tests/fixtures/poc_dynamic_update/` (1 file:
  `probe-results.json`; T8 already owns its own
  `tests/fixtures/dynamic_update_cache/probe-results.json`
  derived from the 2026-05-26 live captures)
- `tests/snapshots/poc_dotnet_cu/` (4 files; T7 already owns
  `tests/snapshots/dotnet_cu/` with the same shape sourced from
  fresh live captures)
- `docs/poc/` (the entire directory; contents survive under
  `docs/history/` after the rename described below)

**Moved (kept under a new permanent name)**:

- `tests/fixtures/poc_release_info/release-info.json`
  -> `tests/fixtures/release_info/release-info.json`
- `tests/snapshots/poc_release_info/release-info-2026-05-25.md`
  -> `tests/snapshots/release_info/release-info-2026-05-25.md`
- `tests/snapshots/poc_release_info/release-info-2026-05-25.meta.json`
  -> `tests/snapshots/release_info/release-info-2026-05-25.meta.json`
- `tests/snapshots/poc_release_info/.gitattributes`
  -> `tests/snapshots/release_info/.gitattributes` (preserves
  the `*.md -text` rule that keeps Microsoft Learn snapshots
  bit-perfect)
- `docs/poc/poc-release-info-readme.md`
  -> `docs/history/release-info-readme.md`
- `docs/poc/poc-release-info-report.md`
  -> `docs/history/release-info-report.md`
- `docs/poc/poc-dotnet-cu-report.md`
  -> `docs/history/dotnet-cu-report.md`
- `docs/poc/poc-dynamic-update-report.md`
  -> `docs/history/dynamic-update-report.md`

**Code updates**:

- `tests/release_info_parser_test.py` (T6): two path constants
  retargeted from `tests/{fixtures,snapshots}/poc_release_info/`
  to `tests/{fixtures,snapshots}/release_info/`; docstring
  updated to point at the new permanent location and the
  historical record under `docs/history/`. No behavioural
  change; T6 still asserts the same 13 invariants.
- `tests/dotnet_cu_parser_test.py` (T7): docstring comment that
  referenced the now-deleted `tests/snapshots/poc_dotnet_cu/`
  was rewritten to point at `docs/history/dotnet-cu-report.md`
  instead.

**Documentation updates** (SPEC.md / tests/README.md):

- SPEC.md §B.22 (file organisation): directory tree updated to
  show `docs/history/` instead of `docs/poc/`; key-points list
  rewritten to describe the post-cleanup state; §B.22.2 prefix
  table marks `poc_` as a reserved pattern for future PoC use
  (not currently present in the repo) and adds a row for
  `docs/history/`; §B.22.3 worked-examples table replaces the
  deleted PoC files with current production examples
  (`release_info_parser_test.py`,
  `release_info_resolver_test.py`,
  `docs/history/release-info-report.md`).
- SPEC.md §B.23.12: stale reference to
  `poc_release_info_03_analyse.py` rewritten as a historical
  note pointing at `docs/history/release-info-report.md`.
- SPEC.md §B.23.14: "PoC promotion to T6-T8" section rewritten
  as "PoC retirement (completed in r07.0)" describing the
  achieved state (scripts deleted, fixtures/snapshots renamed
  or deleted as appropriate, reports moved to `docs/history/`).
- SPEC.md Part G: T6 and T7 row descriptions updated to point
  at the new paths and at `docs/history/` for the historical
  record. The "Adjunct: PoC scripts under `tests/`" section was
  rewritten as "Adjunct: retired r06 Phase 2 PoC" summarising
  the migration.
- SPEC.md §B.21.2 / §B.21.5 / others: scattered
  `docs/poc/poc-*-report.md` URLs updated to the new
  `docs/history/*-report.md` paths.
- `tests/README.md`: the "PoC scripts (r06.0+, time-bounded)"
  section was replaced by a short "Retired r06 Phase 2 PoC"
  paragraph that records the migration outcome.

**No production-code change**. `Update-WindowsServerIso.ps1` is
not modified by this commit; it has had zero references to the
PoC paths since r07.0 Step 2b. Schema versions are unchanged.
`$Script:ScriptVersion` stays at `update-wsi-2026.05.26-r07.0`
(this is a documentation / repository-hygiene commit, not a
functional change, so SemVer is not affected).

**Sanity guarantees**:

- Zero `poc_` or `poc-` prefixed file or directory remains
  anywhere under `tests/` or `docs/`.
- `tests/snapshots/release_info/.gitattributes` was carried
  forward, so the snapshot's bit-perfect CRLF endings remain
  protected against Git's default end-of-line normalisation.
- T6 still finds its snapshot under the new
  `tests/snapshots/release_info/` location and still asserts
  the same 13 invariants from the same `release-info.json`
  reference fixture.

**Quality-gate status**: psa.py 0 / 0 / 0, PSScriptAnalyzer 0
findings, PowerShell parse OK, T2 13/13, T3 10/10, T6 13/13,
T7 16/16, T8 20/20, T9 18/18, T10 18/18. Cumulative 108/108
PASS unchanged from r07.0 Step 3.

### r09.0 Step 1 follow-up (doc-renewal) - README/SPEC/TESTING reconstruction with implementation ground truth

This follow-up to the Step 1 Phase 6 SPEC rewrite is a **doc-only**
change that addresses regressions discovered when the post-rewrite
SPEC was compared against the actual script implementation
(`$Script:ScriptVersion = 'update-wsi-2026.05.27-r08.0'`). It also
addresses two longer-standing concerns raised on review of the
existing README/TESTING:

1. **The documents underspecified the script's purpose** — they
   described "what it does" without addressing "why this script exists",
   making it harder for both human readers and downstream LLM/AI
   consumers to anchor their work in the operational scenarios that
   motivated the script.
2. **The documents had accumulated drift relative to the script body**
   (Action list, Phase count, test inventory, data/ layout). Most of
   this drift originated when AI-tool-assisted edits updated only
   the CHANGELOG and not the surrounding documentation when the
   script changed.

### Regressions corrected in `SPEC.md`

The Phase 6 SPEC rewrite (commit c40755c) introduced four regressions
relative to the implementation, all corrected here:

1. **Part A bloated to 365 lines (governance violation)**. Per
   [`scripts/README.md`](../../README.md) "Standard SPEC Structure",
   Part A is the cross-project inherited layer maintained by the
   sibling SPEC ([`../download-speakerdeck-oracle4engineer/SPEC.md`](../download-speakerdeck-oracle4engineer/SPEC.md)
   sections A.1-A.14). The Phase 6 rewrite restated A.1-A.7 content
   verbatim instead of inheriting via reference. This introduced
   - drift risk (two copies of the same contract)
   - incomplete coverage (the bloated Part A did not include the
     sibling's A.6 Path Handling, A.9 CSV conventions, A.10
     Environment Evaluation, or A.14 Debug Trace Facility).

   **Fix**: Part A reduced to 53 lines, restated as an inheritance
   declaration pointing to the sibling SPEC sections A.1-A.14.

2. **§B.6 Action map omitted three implemented Actions**. The Phase 6
   rewrite listed 11 Actions while the script's `param() ValidateSet`
   (script L242-L243) declares 13. Missing: `BootTest`, `All`,
   `GenerateManifest`.

   **Fix**: §B.6 expanded to all 13 Actions in three groups (Standard
   pipeline / Specialty / Admin), each linked back to its
   implementation site (script line range).

3. **§C.9 Self-verification suite listed T1-T7 (T7 = planned)**. The
   actual `tests/` directory contains T1-T10, all implemented. The
   canonical T-numbering lives in
   [`tests/README.md`](./tests/README.md).

   **Fix**: §C.9 corrected to T1-T10 with the right assertion counts
   (T3 = 7 — not 10, T7 = `dotnet_cu_parser_test.py` = 16, T8 = 20,
   T9 = 18, T10 = 18). The previously-planned
   `wsusscn2_parser_test.py` is re-designated as planned T11
   (post-r09.0 Step 2 work).

4. **§B.20.1 `data/` layout described as `raw-<topic>/` directories**.
   The actual layout is flat: individual `raw-release-info.md`,
   `raw-dotnet-cu.json`, `cache-release-info.json`, etc.

   **Fix**: §B.20.1 corrected to flat layout; §B.20.2 prefix rules
   updated to add the `cache-` prefix family alongside `config-` and
   `raw-`.

### README/TESTING reconstruction (rationale)

The existing `README.md` / `README.ja.md` / `TESTING.md` were rewritten
zero-base rather than incrementally edited, because:

- The level of drift across all three documents (40-60% of content
  needing correction) made incremental editing slower and more
  error-prone than a fresh rewrite.
- The rewrite is anchored to a freshly-extracted **implementation
  ground truth**, derived directly from `param() ValidateSet`, the
  `Invoke-*Phase*` function inventory (script L8973-L11086), the
  `tests/README.md` canonical T-numbering, and the actual `data/`
  directory listing — not from older documentation.
- The README gained a new top-level **"Why this script exists"**
  section addressing the four operational scenarios (lab/test
  bring-up at scale, PCA2011 boot-manager cert expiry,
  air-gapped/offline labs, reproducible patch baselines) that the
  previous README only implied. A **"Reader's roadmap"** subsection
  adds motivation-based routing rules between
  README / SPEC / TESTING / CHANGELOG / root-level governance, mirroring
  the sibling project's structure.
- `TESTING.md` was restructured to match the sibling-project canonical
  §0-§8 pattern (status summary → static analysis → smoke tests →
  live probes → operator-pending → tool suite → CI → discovered bugs)
  rather than carrying ad-hoc subsections.

### Files changed

| File | Before | After | Note |
|:---|--:|--:|---|
| `SPEC.md` | 3,935 | 3,855 | Part A -312 / §B.6, §B.20, §C.9 expanded |
| `README.md` | 532 | 562 | full rewrite |
| `README.ja.md` | 508 | 551 | full rewrite, lock-step with `README.md` (H2=16/16, H3=11/11) |
| `TESTING.md` | 420 | 456 | full rewrite per sibling §0-§8 canonical |

### Self-check applied during the renewal

To prevent recurrence of the regression pattern from Phase 6, the
following guards were applied at execution time:

1. **Implementation ground truth was extracted first**, before any
   document was touched. The extraction artifact is preserved as
   reference during the renewal session.
2. **Each new section was tagged with the rule and the implementation
   site it corresponds to** (sibling SPEC section / `scripts/README.md`
   subsection / script line range / `tests/README.md` entry).
3. **Redundancy check**: every Part A item that the sibling already
   covers was inherited via reference, never restated. This is the
   anti-Phase-6-regression rule.
4. **Bilingual lock-step**: `README.md` and `README.ja.md` updated
   together, structurally aligned at H2 and H3 level.

### Not touched in this commit

The script body (`Update-WindowsServerIso.ps1`) carries documentation
that has also drifted from the current revision: the header `<#...#>`
comment block lists only nine phases, claims "baseline revision r01",
and omits Actions `BootTest` / `All` / `GenerateManifest` from its
`.PARAMETER Action` description. These are intentionally **out of
scope** for this doc-only commit; they will be corrected during the
r09.0 Step 2+ implementation cycles when the script body is otherwise
touched.

### r09.0 Step 1 follow-up 2 (governance cross-reference) - subproject docs reference repository-wide AGENTS.md

A small follow-up to the prior `r09.0 Step 1 follow-up (doc-renewal)`
entry above. The repository-wide [`AGENTS.md`](../../../AGENTS.md) — the
LLM-assisted contributor operating guide, introduced at the
repository root in the same Step 6 governance cycle — is now
referenced from this subproject's documentation:

- `README.md`: the "Reader's roadmap" section gains a bullet pointing
  to `../../../AGENTS.md` for LLM-agent operating guidance (governance
  hierarchy, ground-truth extraction, Doc-Touching Matrix, Part A
  inheritance rule, anti-patterns).
- `README.ja.md`: the same bullet in lock-step (Japanese mirror).
- `SPEC.md`: Part A gains a new subsection `A.x.0 — Rationale and
  forensic record (inheritance rule)` that points to
  `../../../AGENTS.md` §6 (the Part A Inheritance Rule) and §9 (the
  Anti-Pattern catalogue, including AP-1 which documents the
  `c40755c` Part A bloat regression that this SPEC's Part A
  correction in `8df9ff4` resolved). LLM agents extending or revising
  Part A MUST consult both references before touching it.

### Files changed

| File | Before | After |
|:---|--:|--:|
| `README.md` | 562 | 563 |
| `README.ja.md` | 551 | 552 |
| `SPEC.md` | 3855 | 3870 |

### Rationale

The Step 6 cycle introduced `AGENTS.md` at the repository root. Its
forensic value (in particular the §9 AP-1 / AP-9 entries) is highest
when LLM agents working in a Layer 3 SPEC can discover it via a
natural navigation path from the document they are currently editing.
Adding the references in `README.md` (operator-facing navigation) and
`SPEC.md` Part A (agent-facing rule rationale) closes that loop
without restating content (the canonical text lives in `AGENTS.md`,
not duplicated here).

### Not touched

- `TESTING.md` is unchanged. It already references SPEC.md Part C and
  Part D; the `AGENTS.md` link is reachable transitively through
  SPEC.md.
- The script body (`Update-WindowsServerIso.ps1`) is unchanged; this
  remains a doc-only commit.

## [update-wsi-2026.05.26-r07.0] - 2026-05-26

**r07.0 — Phase 3 implementation (release-info-driven refresher; breaking change).**

This is the consolidated r07.0 release that ships the SPEC.md Phase 3
architecture defined in section B.23. Per SPEC B.23.10 the directory
rename, schema bump and refresher rewrite are mutually dependent and
ship as one atomic release; reviewers should treat the whole r07.0
section below as a single coherent change. The release was assembled
incrementally across six commits, each individually quality-gated;
those commits are listed top-down below for traceability.

The minor-version jump from r05 to r07 (skipping r06 as a code release)
follows SemVer for breaking changes: `Resolve-PatchSetFromCatalog` and
`Get-CatalogQueryTemplate` have been deleted, three new cache file
types under `data/` have appeared, and the Config schema field set has
gained the `Common.CatalogTitleTokens` extension. r06.0 stays
exclusively a documentation release (the SPEC + PoC effort committed in
`2935dbd` and `36f4d65`).

The Patch-Tuesday-driven cache refresh automation (SPEC B.23.7 step 1-4
automated) is **NOT** included in r07.0 per SPEC B.23.10; r07.0 ships
manual-trigger only and the automation is deferred to r07.x.

Cumulative quality-gate status at release: psa.py 0 / 0 / 0,
PSScriptAnalyzer 0 findings, PowerShell parse OK, T2 13 / T3 10 /
T6 13 / T7 16 / T8 20 / T9 18 / T10 18 = **108 / 108 assertions pass**.

### r07.0 Step 3 - Version bump and r07.0 finalisation (this release)

Mechanical release-finalisation commit. No behavioural change; the
preceding Step 1 + 2a + 2b set is what r07.0 actually ships.

- `$Script:ScriptVersion` bumped from `update-wsi-2026.05.25-r05.1`
  to `update-wsi-2026.05.26-r07.0`. The script's identity string
  now reflects the SemVer minor-jump documented in SPEC B.23.10.
- `SPEC.md` section B.23.10's "(current)" marker moved from r05.1
  to r07.0. Other r05.1 references in SPEC remain because they
  document historical behaviour or comparisons that motivate the
  r07.0 design; they are not "current version" claims.
- `CHANGELOG.md` `[Unreleased]` block sealed into
  `[update-wsi-2026.05.26-r07.0] - 2026-05-26` with this release
  header. A fresh empty `[Unreleased]` block is added on top for
  future r07.x work.

Quality-gate status: psa.py 0 / 0 / 0, PSScriptAnalyzer 0 findings,
PowerShell parse OK, T2 13/13, T3 10/10, T6 13/13, T7 16/16,
T8 20/20, T9 18/18, T10 18/18. Cumulative 108/108 PASS unchanged
from Step 2b Commit 4.

### r07.0 Step 2b (Refresher main-path migration part) - Cache-driven Resolve-PatchSetFromReleaseInfo replaces Title-scrape discovery (this release)

This commit lands the **second half** of the Step 2b work scheduled
in SPEC.md section B.23.1. The r05.1-era `Resolve-PatchSetFromCatalog`
function and its `Get-CatalogQueryTemplate` helper are **deleted**;
a new cache-driven `Resolve-PatchSetFromReleaseInfo` takes over,
backed by an offline-testable `Get-PatchSetFromReleaseInfoDiscovery`
helper. This is the atomic completion of SPEC B.23.1's "complete
migration" decision: KB discovery is no longer a Title-string
heuristic against the Microsoft Update Catalog; the Catalog now
serves as a **URL resolver only** (KB → download URL plus
supersedence). DU discovery continues via the Step 2a 36-month
cache (now consumed by the new function); LCU discovery comes from
the Step 2a release-info parser; .NET CU discovery comes from the
Step 2a .NET CU parser. URL-resolver narrowing uses the Step 2b
Commit 3 Config-driven `Test-CatalogTitleMatch` helper.

**Important: the discovery layer was validated against synthetic
caches whose shapes were lifted verbatim from the fresh
2026-05-26 captures** under `tests/snapshots/dotnet_cu/` and
`tests/fixtures/dynamic_update_cache/probe-results.json`. No PoC
fixture was consulted. Live observations grounded three
implementation choices:

1. **Server 2022 / Server 2019 .NET CU multi-row** per SPEC B.23.5
   B-2: the live monthly pages list two `.NET Framework` rows
   under "Windows Server 2022" (one for 4.8, one for 4.8.1) and
   under "Windows 10 1809 and Windows Server 2019" (one for 4.7.2,
   one for 4.8). `Get-PatchSetFromReleaseInfoDiscovery` emits ONE
   discovery record per row, so each becomes its own PatchBaseline
   entry. T10 asserts this against a synthetic cache that mirrors
   the live shape.
2. **Server 2025 Setup DU suspended since 2025-12** per SPEC
   B.23.6: the discovery function does NOT emit a DynamicUpdate.Setup
   record when the per-OS DU cache has no in-window entry. The
   test scenario for 2025-12 (no matching caches) returns zero
   records, confirming the defensive path.
3. **Combined LCU + bundled SSU** per SPEC B.23.5 B-1: the new
   orchestrator passes the LCU's full Catalog file list through
   `Select-AllCanonicalPatchFiles` rather than the
   single-file picker, so an LCU UpdateId carrying both an
   LCU.msu and an SSU.msu emits two PatchBaseline entries (one
   with Type=LCU and IsCombined=$true, one with Type=SSU as
   classified by filename heuristic in
   `Convert-CatalogPatchToBaselineEntry`).

**Deleted PowerShell functions**:

- `Resolve-PatchSetFromCatalog` -- 311 lines. The r05.1 Title-string
  scraper. Its responsibility moves to
  `Resolve-PatchSetFromReleaseInfo`.
- `Get-CatalogQueryTemplate` -- 84 lines. The hardcoded per-OS
  query-template + title-token table. SSU/LCU/DU/.NET query
  templates are no longer needed (discovery moved to caches); the
  TitleTokens portion was already moved to Config + helpers in
  Step 2b Commit 3, so the entire function is now dead code.

**New PowerShell functions** (added before
`Resolve-LanguageSpecificPatchesFromCatalog` to keep the catalog
scrapers grouped, with the new release-info path immediately
above):

- `Get-PatchSetFromReleaseInfoDiscovery` -- pure-cache lookup,
  reads `data/cache-release-info.json` (LCU),
  `data/cache-dotnet-cu.json` (.NET CU), and
  `data/cache-du-<OsVersion>.json` (DU) via the existing
  Step 2a path helpers. Performs no network I/O. Accepts
  `-DataDir` for tests so T10 can exercise it against a temp
  directory. Validates `-PatchMonth` against
  `Test-DynamicUpdatePatchMonth` (the YYYY-MM regex helper from
  Step 2a). Returns `pscustomobject[]` with fields
  `Type` / `KbId` / `UpdateId` / `SourceCache` / `SourceRow` /
  `DiscoveryNote`.
- `Resolve-PatchSetFromReleaseInfo` -- orchestrator. Same signature
  as the deleted `Resolve-PatchSetFromCatalog` (OsVersion,
  OsLanguage, PatchMonth, MaxRetries), plus the new optional
  `-DataDir` for test isolation. Returns the same PatchBaseline
  entry shape as the deleted function. SSU emerges from the
  LCU's Catalog bundle via filename heuristic; standalone-SSU
  discovery is intentionally omitted (Microsoft has embedded
  SSU in LCU for current monthly releases per SPEC B.23.5 B-1).

**Caller migration** (three sites, single-line rename each):

- Refresher dispatch table (the
  `PatchBaseline.NeutralPatches.Refresher` registry near the top
  of the script): `'Resolve-PatchSetFromCatalog'` ->
  `'Resolve-PatchSetFromReleaseInfo'`.
- P03 RefreshPatchBaseline phase: the
  `Invoke-SetupPhase03_RefreshPatchBaseline` worker that runs
  during `-Action PrepareSet` now calls
  `Resolve-PatchSetFromReleaseInfo`.
- A01 RefreshAllBaselines admin phase: the
  `Invoke-AdminPhaseA01_RefreshAllBaselines` worker that runs
  during `-Action RefreshAllBaselines` now dispatches to
  `Resolve-PatchSetFromReleaseInfo` for OSes whose field-group
  Refresher matches.

The new function's parameter list is a strict superset of the old
(adds `-DataDir`); existing call sites need no parameter changes.
Net effect on the call graph is a single function-name swap.

**Test surface** changes:

- T3 (`tests/powershell_harness.py`) removed three test cases
  that targeted `Get-CatalogQueryTemplate` (Server2022 dual
  TitleTokens, per-OS Type coverage, Server2022 QueryTemplate
  no-comma form). The function no longer exists. TitleTokens
  coverage is taken over by T9 against the new
  `Get-CatalogTitleTokenList` helper. T3 now reports 10 assertions
  (down from 13); no other T3 case changed.
- T10 (`tests/release_info_resolver_test.py`) new. 18 assertions
  across four discovery scenarios (Server 2025 / 2022 / 2019 for
  2026-05, plus Server 2025 for 2025-12 with no matching caches)
  plus defensive cases (empty data dir, invalid PatchMonth).
  Fixture file is
  `tests/fixtures/release_info_resolver/scenarios.json`,
  shape-matched to the live 2026-05-26 captures.

**No PoC code or fixtures consulted**. T10's fixture KBs, OS
labels and DU UpdateIds were taken from the live captures used
by T7 (`tests/snapshots/dotnet_cu/`) and T8
(`tests/fixtures/dynamic_update_cache/probe-results.json`). The
historical PoC scripts and `tests/snapshots/poc_*/`,
`tests/fixtures/poc_*/` directories were not touched.

**Refresher main path NOW switched**. The migration that SPEC
B.23.1 schedules is complete: KB discovery is cache-driven (LCU
from release-info, .NET CU from .NET CU parser, DU from per-OS
36-month cache), and the Microsoft Update Catalog is consulted
only as a URL resolver. The combined Step 2a + Step 2b set is now
ready for `-Action RefreshAllBaselines` end-to-end runs against
the new path; the only remaining r07.0 schedulable item is the
Patch-Tuesday-triggered cache refresh automation (SPEC B.23.7
step 1-4), which is deferred to r07.x per SPEC B.23.10.

**Net code delta**: -395 lines (deleted 311 + 84) + 395 lines
(added 200 for Resolve-PatchSetFromReleaseInfo + 195 for the
discovery helper). The deletion and addition are intentionally
proportional so the diff is reviewable as one atomic migration.

**Quality-gate status**: psa.py 0 / 0 / 0, PSScriptAnalyzer 0
findings, PowerShell parse OK, T2 13/13, T3 **10/10** (down from
13), T6 13/13, T7 16/16, T8 20/20, T9 18/18, T10 **18/18**.
Cumulative: 108/108 assertions.

### r07.0 Step 2b (URL-resolver narrowing part) - Config-driven Catalog title token disambiguation (previous release)

This commit lands the **first half** of the Step 2b work scheduled
in SPEC.md section B.23.1. New PowerShell helpers move the per-OS
Microsoft Update Catalog `TitleTokens` list out of hardcoded
PowerShell tables and into the OS Config (`data/config-Server*.json`,
field `Common.CatalogTitleTokens`), and add a single narrow-filter
predicate that combines those positive tokens with a hardcoded
negative exclusion list. The next commit (Step 2b part 2) will
replace `Resolve-PatchSetFromCatalog` with
`Resolve-PatchSetFromReleaseInfo` and delete the bulk of the
Catalog Title-string discovery code; this commit prepares the
ground by formalising the URL-resolver narrowing surface that
the new caller will consume.

**Important: the design and the tokens themselves were validated
against fresh live Microsoft Update Catalog data captured on
2026-05-26**, not lifted from any PoC fixture. Two specific live
observations grounded the implementation:

1. **Same-KB client-variant fan-out for Server 2016 / 2019**. A
   bare KB query for Server 2019's .NET CU (KB5087066) returns
   three hits: one for `Windows Server 2019` and two for
   `Windows 10 Version 1809` (the matching client-OS kernel).
   Server 2016 / Windows 10 1607 shows the same fan-out. The
   `Common.CatalogTitleTokens = ["Windows Server 2019"]` for
   Server 2019 (and the analogous Server 2016 entry) correctly
   rejects the Windows 10 client variants without needing a
   negative token.
2. **ARM64 contamination on Server 2025 .NET CU**. The live
   Catalog returns both `for x64` and `for arm64` variants of
   the same KB; the hardcoded
   `$Script:CatalogTitleNegativeTokens = @('Windows 11', 'arm64')`
   list rejects the ARM64 variant case-insensitively.

**New PowerShell functions** (added to
`Update-WindowsServerIso.ps1` immediately before the existing
`Get-CatalogQueryTemplate`, inside the Microsoft Update Catalog
scraper section):

- `Get-CatalogTitleTokenList -OsVersion <name>` -- reads the OS
  Config and returns the `Common.CatalogTitleTokens` array.
  Returns an empty array when the field is absent (the SPEC
  default; the URL resolver then accepts the first matching hit).
  Tolerant of missing Config files (returns empty rather than
  throwing) so the function is safe to call from defensive paths.
- `Test-CatalogTitleMatch -OsVersion <name> -Title <title>` --
  predicate. Returns `$true` when the title matches the OS, i.e.
  contains ANY of the OS's positive tokens AND contains NONE of
  the `$Script:CatalogTitleNegativeTokens` negative tokens.
  Case-insensitive substring matching throughout. When the
  positive list is empty the predicate is permissive (still
  honours the negative list).

**New Script-level variable**:

- `$Script:CatalogTitleNegativeTokens = @('Windows 11', 'arm64')`
  -- the OS-uniform negative exclusion list. Hardcoded
  intentionally per SPEC B.23.2 because these exclusions are
  uniform across all in-scope OSes (every Server build rejects
  the Windows 11 client OS and the ARM64 architecture variant).

**Refactor of `Get-CatalogQueryTemplate`**: the per-OS
`TitleTokens` array literals were replaced with
`@(Get-CatalogTitleTokenList -OsVersion '<name>')` calls. The
function's return shape is unchanged -- `TitleTokens` is still a
`[string[]]` -- so all existing callers (Resolve-PatchSetFromCatalog
in particular) continue to work without changes. The Server2022
in-line comment was updated to point at SPEC B.23.2 and the
Config field as the source of truth.

**Behavioural delta from hardcoded -> Config-driven**:

- Server 2025: hardcoded list had 1 token; Config has 2.
  Permissive expansion -- old matches still match.
- Server 2022: hardcoded list had 2 tokens (both comma forms);
  Config has 3 (adds `Windows Server 2022`). Permissive expansion.
- Server 2019 / 2016: identical content in hardcoded and Config
  (single-token lists). No behavioural change.

In every case the refactor STRICTLY EXPANDS coverage and never
narrows it, so no existing successful Catalog scrape can become
a failure on the new path. (Future Microsoft naming changes can
now be absorbed by editing the Config file, not by shipping a
new PowerShell release.)

**Refresher main path NOT changed**. `Resolve-PatchSetFromCatalog`
and its callers (P03 RefreshPatchBaseline phase and A01
RefreshAllBaselines admin phase) continue to drive
-Action RefreshAllBaselines unchanged. Step 2b part 2 will
introduce `Resolve-PatchSetFromReleaseInfo` and delete the
Catalog Title-string discovery code in a single atomic commit.

**OS Configs NOT changed by this commit**. The
`Common.CatalogTitleTokens` field was already present in all
four `data/config-Server*.json` files (apparently pre-populated
during SPEC B.23.2 authoring). The values match what live data
2026-05-26 validates as correct, so no Config edits were needed.
T9 protects the values against future drift.

**New regression test**: `tests/catalog_title_tokens_test.py`
(T9). Covers 18 assertions across: per-OS token sourcing from
all four `data/config-Server*.json` (4 assertions), missing-Config
defensive empty-list default (1 assertion), and 13 live-captured
narrow-filter cases including positive matches for all four
OSes, same-KB client-variant rejection (Windows 10 1607 / 1809),
negative-token exclusion (arm64, Windows 11), and Server 2022's
both comma forms. **All 18 assertions pass** under PowerShell
7.4 on Ubuntu 24.

**New files committed to the repo**:

- `tests/fixtures/catalog_title_tokens/expected-tokens.json` --
  the per-OS expected token lists (the assertion ground truth
  for `Get-CatalogTitleTokenList`).
- `tests/fixtures/catalog_title_tokens/narrow-filter-cases.json`
  -- 13 live-captured Catalog hit titles with the expected
  match decision per OS. Each case is annotated with a
  description explaining which token or negative exclusion
  drives the decision.

**Quality-gate status**: psa.py 0 / 0 / 0, PSScriptAnalyzer 0
findings, PowerShell parse OK, T2 13/13, T3 13/13, T6 13/13,
T7 16/16, T8 20/20, T9 18/18. Cumulative: 93/93 assertions.

### r07.0 Step 2a (DU 36-month cache part) - Per-OS Dynamic Update cache and 36-month window selection (previous release)

This commit lands the **third half** of the Step 2a work scheduled
in SPEC.md section B.23.1. New PowerShell functions maintain a
per-OS Dynamic Update cache file (`data/cache-du-Server<NNNN>.json`)
that records Microsoft Update Catalog probe results across a
36-month rolling window, and select the latest in-window
successful publish at ISO-build time. The cache decouples
ISO-build runs from live Catalog scraping for DU discovery; an
out-of-band, Patch-Tuesday-triggered refresh action will
populate the cache in a later commit. The existing Refresher
main path (`Resolve-PatchSetFromCatalog`) is **untouched** and
continues to drive `-Action RefreshAllBaselines`. The Catalog
URL-resolver narrowing remains scheduled for Step 2b.

**Important: the design was validated against live Microsoft
Update Catalog probes captured on 2026-05-26**, not against the
single-month PoC fixture under
`tests/fixtures/poc_dynamic_update/probe-results.json`. Twelve
`(OS, DU type, patch month)` combinations were probed across
2026-05 / 2026-04 / 2026-03. The live results confirmed SPEC
§B.23.6:

- **Server 2025 Setup DU**: 0 hits for all three months, with
  the canonical `id="ctl00_catalogBody_noResultText"` marker
  present in the HTML. This matches "Suspended since 2025-12,
  5+ months" in the §B.23.6 cadence table.
- **Server 2025 SafeOs DU**: published monthly
  (KB5087588 / KB5082237 / KB5078794).
- **Server 2022 DU**: published monthly (KB5087595 / KB5082243;
  the 2026-03 probe failed with a transient SSL error and was
  retried via the fixture's synthetic entries).
- **Server 2019 Setup DU**: 0 hits for all three months,
  confirming the "feature-update windows only" annotation in
  §B.23.6.

**New PowerShell functions** (added to `Update-WindowsServerIso.ps1`
between `Get-DotNetCuCache` and the Microsoft Update Catalog
scraper section):

- `Get-DynamicUpdateCachePath` — path resolver per OS; accepts
  an optional `-DataDir` for tests.
- `New-EmptyDynamicUpdateCache` — fresh empty cache object for
  an OS with no persisted file yet.
- `Get-DynamicUpdateCache` — read the per-OS cache; **does not**
  throw on missing-file (returns an empty cache instead). This
  matches the "latest known good" stance from §B.23.6: an ISO
  build never aborts because a Patch-Tuesday refresh has not
  yet run for a given OS.
- `Save-DynamicUpdateCache` — persist with UTF-8 + LF + no-BOM,
  same conventions as the other r07.0 caches.
- `Test-DynamicUpdatePatchMonth` — validate `YYYY-MM` format.
- `Add-DynamicUpdateCacheEntry` — append-or-upsert one probe
  result. Same `(PatchMonth, DuType)` replaces in place
  (verified by the `upsert_same_key_latest_wins` T8 scenario);
  arrays use `@(...)` and Add-Member -Force pattern to avoid
  ConvertTo-Json single-element flattening.
- `ConvertTo-DynamicUpdatePatchMonthSortKey` — convert
  `YYYY-MM` to integer (yyyy*100+mm) for fast comparisons.
- `Get-DynamicUpdateWindowEarliestPatchMonth` — compute the
  earliest in-window month relative to a reference date;
  inclusive 36-month range (for `Now=2026-05` the earliest
  in-window month is 2023-06).
- `Get-LatestDynamicUpdate` — select the latest in-window
  successful entry for a given `(OsVersion, DuType)`; returns
  `$null` when no in-window entry has `Success=$true`. Window
  is anchored by `-Now` (default UTC now); tests pass a fixed
  `-Now` for reproducible assertions.
- `Remove-DynamicUpdateOutsideWindow` — drop entries earlier
  than the window; renamed from the proposed
  `Remove-DynamicUpdateOlderThan36Months` to satisfy
  PSScriptAnalyzer PSA6003's singular-noun rule (the "36" is
  baked into `Get-DynamicUpdateWindowEarliestPatchMonth`'s
  default).

**New Script-level variables**:

- `$Script:DynamicUpdateCacheWindowMonths = 36`
- `$Script:DynamicUpdateCacheSchema = '1.0'`

**Refresher main path NOT changed**. The existing Catalog scrape
in `Resolve-PatchSetFromCatalog` is unaffected. The DU cache is
populated and consumed by a separate code path that this commit
adds the data primitives for, but does not yet wire into a
production action; that wiring is scheduled for Step 2b.

**Testability hooks**. Every cache function accepts an optional
`-DataDir` parameter (default `''`) so T8 can route writes to a
temp directory without polluting `data/`. `Get-LatestDynamicUpdate`
and `Remove-DynamicUpdateOutsideWindow` accept an optional
`-Now` parameter (default `[datetime]::UtcNow`) so window
assertions are reproducible regardless of the wall clock. The
production path passes neither parameter and the defaults
restore the production behaviour exactly.

**Idempotent upsert**. `Add-DynamicUpdateCacheEntry` overwrites
any existing entry with the same `(PatchMonth, DuType)`. This
matters because the Patch-Tuesday refresh may probe the same
month multiple times during a single refresh cycle; only the
most recent probe should survive.

**Cross-OS isolation**. The per-OS cache file separation means
writes to `cache-du-Server2025.json` never affect
`cache-du-Server2022.json` and vice versa. Verified by the
`cross-OS isolation` scenario in T8.

**New files committed to the repo**:

- `tests/fixtures/dynamic_update_cache/probe-results.json` —
  the live Microsoft Update Catalog probe output from
  2026-05-26 (12 probe attempts, 8 successful, 1 SSL-error
  transient, 3 expected-empty confirmations per §B.23.6).
- `tests/fixtures/dynamic_update_cache/scenarios.json` —
  Python-generated reference scenarios combining the live probe
  entries with synthetic older months, plus the expected
  outcomes that PowerShell must reproduce.

**New regression test**: `tests/dynamic_update_cache_test.py`
(T8). Covers 20 assertions across three fixture scenarios
(server2025_live_then_setup_empty, server2022_with_old_synthetic,
upsert_same_key_latest_wins) plus three ad-hoc scenarios
(cross-OS isolation, missing-file empty cache, PatchMonth
validation rejection). Each scenario uses an isolated temp
directory via the `-DataDir` parameter and anchors the window
at `Now=2026-05-26T00:00:00Z`. **All 20 assertions pass** under
PowerShell 7.4 on Ubuntu 24.

**Quality-gate status**: psa.py 0 / 0 / 0, PSScriptAnalyzer 0
findings, PowerShell parse OK, T2 13/13, T3 13/13, T6 13/13,
T7 16/16, T8 20/20.

### r07.0 Step 2a (.NET CU part) - PowerShell parser and aggregated raw/cache for the .NET Framework release-notes (previous release)

This commit lands the **second half** of the Step 2a work
scheduled in SPEC.md section B.23.1. New PowerShell functions
fetch and parse the Microsoft Learn `.NET Framework release
information` index plus every monthly cumulative-update
release-notes page it references, writing an aggregated raw JSON
and a parsed cache JSON under `data/`. The existing Refresher
main path (`Resolve-PatchSetFromCatalog`) is **untouched** and
continues to drive `-Action RefreshAllBaselines`. The Dynamic
Update 36-month cache (per-OS `cache-du-Server<NNNN>.json`) and
the Catalog URL-resolver narrowing are scheduled for subsequent
r07.0 commits.

**Important: the data captured for the new parser was fetched
live from learn.microsoft.com on 2026-05-26**, not lifted from
the PoC snapshots under `tests/snapshots/poc_dotnet_cu/`. Doing
so surfaced two PoC-era assumptions that no longer hold against
current Microsoft Learn pages:

1. The index page now formats each entry as
   `- <DATE> - [<KIND>](<URL>)` (the date is **outside** the
   bracket pair and only the kind text is linked). The original
   PoC regex expected `- [<DATE> - <KIND>](<URL>)` and would
   match zero entries on the current page.
2. The monthly pages now place `## Summary tables` AFTER
   `## Known issues in this release`. The original PoC parser
   used `## Known issues` as the stop-marker for the
   tables-region walk, which on the current page would close the
   region before it ever opened. The new parser starts at
   `## Summary tables` and walks to the next `## ` heading or
   end-of-document.

The parser also tolerates the `**New Release**` badge that the
most-recent entry on the index carries, and preserves entries
whose strict %B date parse fails (the live index contains a
2024-10 entry typed "Octber 22, 2024" upstream).

**New PowerShell functions** (added to `Update-WindowsServerIso.ps1`
between `Get-ReleaseInfoCache` and the Microsoft Update Catalog
scraper section):

- `Get-DotNetCuRawPath` / `Get-DotNetCuCachePath` — path resolvers
  for the two new files under `data/`.
- `ConvertFrom-DotNetCuOsLabel` — maps the raw OS label printed
  in the release-notes table to a normalised short name (e.g.
  "Microsoft server operating system, version 24H2" -> `Server2025`).
  Order-sensitive substring matching: longer joint labels
  ("Windows 10 1607 and Windows Server 2016") win against the
  shorter pattern they contain.
- `Split-DotNetCuMarkdownFrontMatter` — strips the leading YAML
  block from a `?accept=text/markdown` response.
- `ConvertFrom-DotNetCuIndexMarkdown` — parses the index page;
  returns `EntryCount` / `Kinds` / `EarliestDate` / `LatestDate`
  / `Entries[]` with per-entry `DateText` / `Date` / `Kind` /
  `RelativeUrl` / `AbsoluteUrl`.
- `ConvertFrom-DotNetCuMarkdown` — parses a monthly page; emits
  `EntryCountTotal` / `EntryCountRecognised` / `RowsPerOs`
  (ordered hashtable) / `Entries[]` with per-OS-block `OsLabel`
  / `OsNormalised` / `OsOfferingKb` / `Rows[]`. Multiple
  sub-tables under the same `## Summary tables` heading are
  handled (current 2026-05 pages list three: Cumulative update,
  Security and quality rollup, .NET Framework 3.5 product
  update).
- `Invoke-DotNetCuFetch` — HTTPS fetch of the index URL plus
  every monthly URL it lists. Aggregates the bodies + HTTP
  headers + fetch timestamps into `data/raw-dotnet-cu.json`
  (UTF-8, LF, no-BOM). Per-month fetch failures are recorded as
  `Ok=false` entries with the error message so a single broken
  month does not lose the whole refresh.
- `Update-DotNetCuCache` — reads `raw-dotnet-cu.json`, runs both
  parsers, writes `data/cache-dotnet-cu.json`. Returns the cache
  path.
- `Get-DotNetCuCache` — reads `cache-dotnet-cu.json` for
  Refresher consumers. Throws if the file is missing.

**New Script-level variables**:

- `$Script:DotNetCuIndexUrl` — the index URL with the
  `?accept=text/markdown` query.
- `$Script:DotNetCuUrlBase` — used by the index parser to
  reconstruct absolute URLs from relative paths.
- `$Script:DotNetCuUserAgent` — a descriptive User-Agent string
  identifying this subproject.
- `$Script:DotNetCuOsLongToShort` — an ordered hashtable mapping
  the long OS label substrings to the short names.

**Refresher main path NOT changed**. The existing path
(`Resolve-PatchSetFromCatalog`, `Get-CatalogQueryTemplate`,
`Get-UpdateIdFromCatalog`, the Refresher action workers) is
unaffected by this commit. Switching the Refresher to consume
`cache-dotnet-cu.json` instead of live-scraping is scheduled for
a later r07.0 commit (Step 2b).

**New files committed to the repo**:

- `data/` — no production cache file is committed in this
  commit; production runs that invoke `Invoke-DotNetCuFetch` will
  write `raw-dotnet-cu.json` and `cache-dotnet-cu.json` on demand
  under the Patch-Tuesday-triggered model (SPEC.md §B.23.7).
- `tests/snapshots/dotnet_cu/index.md` — live capture of the
  Microsoft Learn `.NET Framework release information` index
  page (`?accept=text/markdown`) on 2026-05-26.
- `tests/snapshots/dotnet_cu/2026-05-12-may-cumulative-update.md`
  — live capture of the May 2026 monthly CU page.
- `tests/snapshots/dotnet_cu/2026-04-14-april-cumulative-update.md`
  — live capture of the April 2026 monthly CU page.
- The three `.meta.json` siblings carrying `captured_at`,
  `source_url`, `user_agent`, and `byte_count`.
- `tests/fixtures/dotnet_cu/index.json`,
  `tests/fixtures/dotnet_cu/month-2026-05.json`,
  `tests/fixtures/dotnet_cu/month-2026-04.json` — the Python
  reference parser output that defines what the PowerShell
  parsers must reproduce.

**New regression test**: `tests/dotnet_cu_parser_test.py` (T7).
Covers 16 assertions across the index parser (EntryCount,
EarliestDate, LatestDate, Kinds, per-entry deep equality across
all 29 entries, typo-entry preservation), the monthly parser
(EntryCountTotal, EntryCountRecognised, RowsPerOs, Server2022
block deep check, cross-month regression on 2026-04), and the
OS-label mapper (two production-scope labels plus an
unrecognised one). Runs against the fresh snapshots/fixtures
described above and is intentionally independent of the PoC
fixtures under `tests/snapshots/poc_dotnet_cu/`. **All 16
assertions pass** under PowerShell 7.4 on Ubuntu 24.

**Quality-gate status**: psa.py 0 / 0 / 0, PSScriptAnalyzer 0
findings, PowerShell parse OK, T2 13/13, T3 13/13, T6 13/13, T7
16/16. The PoC scripts and PoC snapshot/fixture directories are
unchanged.

### r07.0 Step 2a (release-info part) - PowerShell port of the release-info parser (previous release)

This commit lands the **first half** of the Step 2 work scheduled
in SPEC.md section B.23.1. New PowerShell functions parse the
Microsoft Learn Windows Server release-info Markdown into
structured cache data; the existing Refresher main path
(`Resolve-PatchSetFromCatalog`) is **untouched** and continues
to drive `-Action RefreshAllBaselines`. The .NET CU parser, the
Dynamic Update 36-month cache, and the Catalog URL-resolver
narrowing are scheduled for subsequent r07.0 commits.

**New PowerShell functions** (added to `Update-WindowsServerIso.ps1`
between `Get-OsConfigPath` and the Catalog scraper section):

- `Get-DataDirectoryPath` / `Get-ReleaseInfoRawPath`
  / `Get-ReleaseInfoRawMetaPath` / `Get-ReleaseInfoCachePath` —
  path resolvers for the three new files under `data/`.
- `Invoke-ReleaseInfoFetch` — HTTPS fetch of
  `https://learn.microsoft.com/.../windows-server-release-info?accept=text/markdown`
  using `Invoke-WebRequest -UseBasicParsing` with a descriptive
  User-Agent. Writes the Markdown body to
  `data/raw-release-info.md` (UTF-8, LF, no-BOM) and the HTTP
  headers + fetch timestamp to `data/raw-release-info.meta.json`.
- `Split-ReleaseInfoTableRow` / `Test-ReleaseInfoTableSeparator`
  / `ConvertFrom-ReleaseInfoUpdateType` /
  `ConvertFrom-ReleaseInfoKbCell` — small parser helpers that
  mirror the PoC Python implementations in
  `tests/poc_release_info_02_parse.py`.
- `ConvertFrom-ReleaseInfoMarkdown` — main parser. Returns a
  `pscustomobject` with two properties (`MonthlyReleases`,
  `HotpatchCalendar`) containing per-OS rows. Header text and
  column counts are checked strictly; any drift in Microsoft's
  table layout is reported via `Write-Warn` and the offending
  row is skipped (the offline regression test will then surface
  the count delta).
- `Update-ReleaseInfoCache` — reads `data/raw-release-info.md`,
  parses it, derives per-OS row counts, and writes
  `data/cache-release-info.json` (UTF-8, LF, no-BOM, JSON
  Depth 32).
- `Get-ReleaseInfoCache` — reads
  `data/cache-release-info.json` and returns the deserialised
  object. Refresher consumers in a later commit will use this
  to avoid re-parsing on every build.

**Schema of `data/cache-release-info.json`** (Schema 1.0):

```jsonc
{
  "Schema":            "1.0",
  "GeneratedAt":       "<ISO 8601 UTC>",
  "SourceUrl":         "https://learn.microsoft.com/...",
  "RawMarkdownPath":   "raw-release-info.md",
  "MonthlyRowCount":   471,
  "HotpatchRowCount":  62,
  "PerOsMonthlyCounts":  { "Server2016": 187, "Server2019": 165, "Server2022": 89,  "Server2025": 30 },
  "PerOsHotpatchCounts": { "Server2025": 26, "Server2022": 36 },
  "MonthlyReleases":   [ { "OsShortName": "Server2025", ... }, ... ],
  "HotpatchCalendar":  [ { "OsShortName": "Server2025", "CalendarYear": 2026, ... }, ... ]
}
```

**Constants and tables** added at script scope:

- `$Script:ReleaseInfoUrl`
- `$Script:ReleaseInfoUserAgent`
- `$Script:ReleaseInfoLongToShort`     (Markdown OS header → OsShortName)
- `$Script:ReleaseInfoMonthNameToNumber`
- `$Script:ReleaseInfoMonthlyHeaders`  (expected column names for the monthly release tables)
- `$Script:ReleaseInfoHotpatchHeaders` (expected column names for the Hotpatch calendar tables)

**Tests**

- New T6 `tests/release_info_parser_test.py`: invokes
  `ConvertFrom-ReleaseInfoMarkdown` via the existing TestHarness
  protocol against the PoC snapshot
  `tests/snapshots/poc_release_info/release-info-2026-05-25.md`
  and compares the output against the PoC fixture
  `tests/fixtures/poc_release_info/release-info.json`. The PoC
  fixture was generated by `tests/poc_release_info_02_parse.py`
  during r06.0 Phase 2 and is the reference truth for this
  port. T6 verifies: total monthly row count (471), total
  Hotpatch row count (62), per-OS monthly counts (Server2016=187,
  Server2019=165, Server2022=89, Server2025=30), per-OS Hotpatch
  counts (Server2025=26, Server2022=36), KbId-parse coverage
  per OS, and IsBaseline detection in the Hotpatch table.

**Not in this commit** (deferred to subsequent r07.0 steps):

- `Resolve-PatchSetFromReleaseInfo` (the new Refresher main
  path that consumes `cache-release-info.json`) — Step 2b.
- `.NET CU` parser and `data/cache-dotnet-cu.json` — Step 2a-2
  (next r07.0 commit).
- `Dynamic Update` 36-month cache (`data/cache-du-Server*.json`)
  — Step 2a-2 or Step 2a-3.
- `Get-DownloadUrlForKb` (Catalog URL resolver narrowed to
  KB-only lookup) — Step 2b.
- Deletion of the old `Resolve-PatchSetFromCatalog` KB-discovery
  logic — Step 2b.
- New `RefreshSnapshots` / `InspectBaseline` Actions, the
  `stage5__data-snapshot.yml` workflow, and the ScriptVersion
  bump to `r07.0` — Step 3.

**Quality gates verified for this commit**

- `psa.py Update-WindowsServerIso.ps1`: 0 errors / 0 warnings / 0 info
- PSScriptAnalyzer (pwsh 7 Linux): 0 errors / 0 warnings / 0 info
- T2 `catalog_fixture_test.py`: 13/13 PASS
- T3 `powershell_harness.py`: 13/13 PASS
- **T6 `release_info_parser_test.py`: 13/13 PASS** (new)
- `.ps1`: UTF-8 BOM + CRLF + ASCII-only (verified)
- `.md` / `.json`: UTF-8 + LF + no-BOM (verified)

### r07.0 Step 1 - data/ migration and DotNet type breaking change (this release)

This is the **first commit of the r07.0 implementation** of the
Phase 3 architecture decisions captured in SPEC.md §B.23. Two
mechanical changes ship in this step; the production code paths
(release-info parser, .NET CU parser, DU cache, URL resolver, new
Actions) come in the following r07.0 commits.

**Changes**

- **Directory rename: `Config/` → `data/` with `config-` filename
  prefix.** All four `Config/Server<N>.json` files are moved to
  `data/config-Server<N>.json`. This is the layout codified in
  SPEC.md §B.23.3 and is the foundation for the upcoming
  `cache-*` and `raw-*` sibling files. The `Config/` directory
  itself is removed.

- **New optional config field: `Common.CatalogTitleTokens`.** Each
  `data/config-Server<N>.json` gains an array of strings used by
  the future Catalog URL resolver to disambiguate KB-only Search.aspx
  responses. Values are sourced from PoC-B evidence in r06.0:

  | OS          | Tokens                                                                                              |
  | ----------- | --------------------------------------------------------------------------------------------------- |
  | Server 2016 | `["Windows Server 2016"]`                                                                           |
  | Server 2019 | `["Windows Server 2019"]`                                                                           |
  | Server 2022 | `["Microsoft server operating system version 21H2", "Microsoft server operating system, version 21H2", "Windows Server 2022"]` |
  | Server 2025 | `["Microsoft server operating system version 24H2", "Windows Server 2025"]`                         |

  The field is additive within Schema 2.1; consumers that do not
  recognise it ignore it (no Schema bump). See SPEC.md §B.23.2
  for the rationale and §B.23.4 for the schema-version stance.

- **Breaking change: `Type=DotNet` split into `DotNet.Runtime`
  + `DotNet.OsLevel`.** The PatchBaseline `Type` enumeration now
  distinguishes the per-runtime KB (applied to install.wim) from
  the OS-offering KB (recorded for traceability but not applied
  to any WIM). All in-tree code paths that referenced `'DotNet'`
  now reference `'DotNet.Runtime'`. The `Get-PatchType` classifier
  routes `.NET`-bearing filenames to `DotNet.Runtime` because the
  OS-offering KB never has an on-disk payload. The `PatchTargetMap`
  declares `DotNet.OsLevel` with an empty target array, so an
  OS-offering KB recorded in a future baseline cleanly skips
  WIM application. See SPEC.md §B.23.8 for the design rationale
  and §B.14b for the updated Type enumeration.

- **`Get-ConfigProfile` rejects legacy baselines.** A config-load
  attempt that finds `Type='DotNet'` entries in `PatchBaseline.Patches[]`
  now fails fast with a precise error pointing at SPEC.md §B.23.8
  and instructing the operator to re-run `-Action RefreshAllBaselines`.
  No automatic migration shim ships; r07.0 is a breaking change
  by design.

**Documentation updates**

- `SPEC.md §B.22.1` directory layout: rewritten in current-state
  voice with a historical note for the pre-r07.0 `Config/`
  layout.
- `SPEC.md §B.22.2` filename prefix rules: collapsed the r06.x /
  r07.0+ split rows into the post-r07.0 layout; the historical
  Phase 3 design narrative remains in §B.23.3.
- `SPEC.md §B.10` JSON example: example `Type` values updated
  to show both `DotNet.Runtime` and `DotNet.OsLevel` rows.
- `SPEC.md §B.14b` Type enumeration: the comment that lists all
  legal Type values now reads `... | DotNet.Runtime | DotNet.OsLevel
  | DotNet.LangPack | ...`.
- `SPEC.md §B.12` (P07 Install target table): added a row for
  `DotNet.OsLevel` showing `(none)` targets.
- `README.md` / `README.ja.md` / `TESTING.md` / `tests/README.md`
  / `tests/eval_iso_probe.py`: all references to `Config/...`
  paths updated to `data/config-...` paths.
- `.github/workflows/stage1__linux.yml` /
  `stage4__monthly-refresh.yml`: path-filter and PR-creation
  patterns updated to `data/**` and `data/config-*.json`.

**Tests**

- `tests/powershell_harness.py` (T3): the
  `Get-CatalogQueryTemplate per-OS Type coverage` and
  `Select-AllCanonicalPatchFiles dual-link case` tests are
  updated to expect `'DotNet.Runtime'` rather than `'DotNet'`.

**Baseline lint cleanup (PSScriptAnalyzer)**

Three pre-existing PSScriptAnalyzer findings were carried over
from earlier commits and resolved as part of Step 1 so the
project's stated "0 errors / 0 warnings / 0 information findings"
quality gate is actually enforced going forward:

- `PSAvoidAssignmentToAutomaticVariable`:
  `foreach ($pid in $installedIds)` renamed to
  `foreach ($packageId in $installedIds)` to avoid shadowing
  the read-only `$pid` automatic variable.
- `PSReviewUnusedParameter`: `Select-AllCanonicalPatchFiles`
  now honours its `$PatchType` parameter by mirroring the
  `DotNet.Runtime`-specific ndp scoring boost that
  `Select-CanonicalPatchFile` already had, making the
  multi-file picker behave consistently with the single-file
  picker when umbrella .NET CU KBs return multiple siblings.
- `PSUseDeclaredVarsMoreThanAssignments`: the unused
  `$regOut` capture from `reg.exe load` was changed to
  `$null = & reg.exe load ...` since success is determined
  by `$LASTEXITCODE` alone.

**Quality gates verified for this commit**

- `psa.py Update-WindowsServerIso.ps1`: 0 errors / 0 warnings / 0 info
- T2 `catalog_fixture_test.py`: 13/13 PASS
- T3 `powershell_harness.py`: 13/13 PASS
- `.ps1`: UTF-8 BOM + CRLF + ASCII-only (verified)
- `.md`: UTF-8 + LF + no-BOM (verified)
- `.json`: UTF-8 + LF + no-BOM (verified)

**Not in this Step 1**

- Script version is still `update-wsi-2026.05.25-r05.1`. The
  `r07.0` version bump happens in the final r07.0 commit.
- `Resolve-PatchSetFromReleaseInfo`, `Get-DownloadUrlForKb`, the
  release-info / .NET CU / DU caches, the `RefreshSnapshots` and
  `InspectBaseline` Actions, and the `stage5__data-snapshot.yml`
  workflow all arrive in subsequent r07.0 commits per the §B.23
  design.

### r06.0 Phase 2 - PoC: online patch metadata acquisition (this release)

This Phase 2 deliverable is **PoC scripts and a written report**,
plus a new normative SPEC.md §B.22 ("File organisation and naming
conventions") that codifies how PoC artefacts coexist with the
production code and the T1-T5 regression suite under the subproject
directory. As with Phase 1, this release contains **no script
(`.ps1`) changes and no on-disk Config schema changes**.

**Driver**. r06.0 Phase 1 left open the empirical question:
*does the Microsoft Learn Windows Server release-info page provide
enough authentication-free metadata to drive the Refresher,
replacing the brittle Microsoft Update Catalog title-string
heuristics catalogued in SPEC.md §D.19 / §D.20 / §D.21?* Phase 2's
PoC answers that question with measured data from 471 monthly
release rows and 62 hotpatch calendar entries.

**SPEC changes**:

- `SPEC.md` §B.22 ("File organisation and naming conventions")
  added. Five subsections:
  - **B.22.1** Directory layout (`Config/`, `tests/`, `docs/` as
    the only first-class children).
  - **B.22.2** Filename prefix rules (`poc_<topic>_<step>_<verb>.py`
    for PoC Python; `poc-<topic>-<purpose>.md` for PoC Markdown).
  - **B.22.3** Worked examples mapping filenames to classes.
  - **B.22.4** Out-of-scope clarifications.
- `SPEC.md` Part G adjunct ("PoC scripts under `tests/`") added,
  cross-referencing the new conventions and listing the current
  PoC inventory.

**PoC artefacts added** (all disposable per B.22):

```
tests/
├── poc_release_info_01_fetch.py    fetch the Markdown
├── poc_release_info_02_parse.py    parse into JSON
├── poc_release_info_03_analyse.py  write CSV + JSON analyses
├── snapshots/poc_release_info/
│   ├── .gitattributes
│   ├── release-info-2026-05-25.md       (68 KB raw Markdown)
│   └── release-info-2026-05-25.meta.json
└── fixtures/poc_release_info/
    ├── release-info.json                (parsed structured form)
    ├── update-type-summary.csv          (YYYY-MM x OS x letter pivot)
    ├── baseline-month-detection.json    (Server 2025/2022 hotpatch calendar)
    ├── letter-frequency.json
    └── coverage-summary.json
docs/
├── README.md                            (docs/ directory guide)
└── poc/
    ├── poc-release-info-readme.md       (how to run the PoC)
    └── poc-release-info-report.md       (findings + Phase 3 recommendations)
```

**PoC findings (summary)**:

- The `?accept=text/markdown` content-negotiation switch returns
  the source Markdown verbatim, 68 KB, no authentication. The page
  is GitHub-backed (`MicrosoftDocs/windows-release-pr`), so its
  format stability is reviewable.
- Monthly release coverage is comprehensive: 117 months for
  Server 2016, 92 for Server 2019, 58 for Server 2022, 20 for
  Server 2025, with zero gaps for the latter three.
- The previously-uncatalogued **"Windows Server hotpatch calendar"**
  section provides authoritative Baseline-vs-Hotpatch month
  labelling for Server 2022 and Server 2025, including
  forward-looking unreleased months. This single discovery answers
  the "how do we know which Server 2025 LCUs are baseline months"
  question without scraping technical blogs.
- The release-info page does NOT cover .NET Framework CU,
  Dynamic Update.Setup, Dynamic Update.SafeOs, or language packs.
  Those Types stay on the Catalog scrape path for Phase 3, but the
  Catalog query can be keyed by KB number (from release-info)
  rather than by Title-string heuristics, removing most of
  SPEC.md §D.19 / §D.20 from the surface area.

The full report including five Phase 3 recommendations and four
open questions is in
[`docs/poc/poc-release-info-report.md`](./docs/poc/poc-release-info-report.md).

**Not in this Phase 2**:

- No `Update-WindowsServerIso.ps1` changes. `$Script:ScriptVersion`
  stays at `update-wsi-2026.05.25-r05.1`.
- No `Config/<OsKey>.json` schema changes.
- No T1-T5 changes. The PoC scripts share the `tests/` directory
  by file-organisation convention but do not participate in the
  T-numbered regression suite.
- No Phase 3 code or design. Phase 3 is driven by the report's
  recommendations and is a separate work item.

#### r06.0 Phase 2 Part 2 — full Phase 2 coverage (this release)

The first cut of Phase 2 above shipped the `release_info` PoC
with three scripts but deferred three of the original PoC
questions (B, E, F) to Phase 3 as "open questions". Part 2
closes those gaps within Phase 2 so that the deliverable matches
the original Phase 2 scope.

**New PoC artefacts**:

- `tests/poc_release_info_04_resolve.py` — answers PoC-B by
  resolving 8 representative (OS, KB) pairs from the parsed
  release-info data through the Microsoft Update Catalog
  (Search.aspx → DownloadDialog.aspx). Verdict: 8/8 succeed
  with KB-only input; OS-naming requires both the
  `Windows Server NNNN` and `Microsoft server operating system
  version NNHN` tokens to disambiguate hits.
- `tests/poc_dotnet_cu_*.py` (new topic) — answers PoC-E by
  fetching and parsing the Microsoft Learn
  `.NET Framework cumulative update` release-notes pages.
  Verdict: the pages are served as Markdown via
  `?accept=text/markdown` and provide an authoritative per-OS x
  per-.NET-version KB table.
- `tests/poc_dynamic_update_01_probe.py` (new topic) — answers
  PoC-F by probing the Catalog with the same query templates as
  `Get-CatalogQueryTemplate`. Verdict: Server 2022 DU.SafeOs and
  Server 2025 DU.SafeOs are reliably discoverable; Server 2025
  DU.Setup has been absent from the Catalog for 5+ consecutive
  months (2025-12 through 2026-04), which the Phase 3 Refresher
  must treat as a soft signal rather than an error.

**New PoC documentation**:

- `docs/poc/poc-dotnet-cu-report.md` (full findings for PoC-E)
- `docs/poc/poc-dynamic-update-report.md` (full findings for PoC-F)
- `docs/poc/poc-release-info-report.md` updated with three
  `(revisited)` subsections that close PoC-B / E / F by linking
  to the new reports.

**SPEC changes**:

- `SPEC.md` §B.21.2 (.NET CU multiplicity by OS) amended to
  record the upstream-source per-OS file counts alongside the
  existing production-telemetry counts, and to explain the
  Server 2016 discrepancy (production sees 1 file; upstream
  release-notes lists 2 KBs).
- `SPEC.md` Part G adjunct updated to reflect the three current
  PoC topics (`release_info`, `dotnet_cu`, `dynamic_update`)
  instead of just one.

**Key empirical findings beyond the original Phase 2 questions**:

- Microsoft Update Catalog publishes Server 2022/2025 LCUs under
  the name "Microsoft server operating system version NNHN"
  (not "Windows Server NNNN"); the Phase 3 resolver must accept
  both token forms.
- Every Server 2025 LCU resolution returns 2 download URLs: the
  LCU itself plus `KB5043080` (the Servicing Stack baseline).
  This empirically validates the "no standalone SSU" claim in
  SPEC.md §B.21.1 for the Server 2025 row.
- SPEC.md §B.21.2 had a Server 2016 .NET CU file count of 1
  derived from r05.1 telemetry; the upstream
  `.NET Framework cumulative update` release-notes table for
  2026-04 lists 2 distinct KBs for Server 2016. The Phase 3
  Refresher should consume from release-notes (not the umbrella
  KB scrape) to surface the missing sibling.

**Still not in this Phase 2**:

- No `Update-WindowsServerIso.ps1` changes (still r05.1).
- No `Config/<OsKey>.json` schema changes.
- No T1-T5 changes.

### r06.0 Phase 3 Architecture — SPEC-only: r07.0 design baseline (this release)

This Phase 3 deliverable is the **SPEC consolidation** of the
eleven architecture decisions taken during a 2026-05-25 design
session, building on the Phase 2 PoC findings. As with Phase 1
and Phase 2 Part 2, this release contains **no script (`.ps1`)
changes and no on-disk Config schema changes**.

**Driver**. Phase 2 (especially Part 2's PoC-B/E/F follow-up)
turned up enough hard data to answer the open questions that
§B.21.5 "Future work" had deliberately deferred. Rather than
go straight to implementation, this phase records *what r07.0
will look like* as a normative SPEC section so the implementation
PR can be reviewed against a written design, not against the
chat history of a design call.

**New SPEC section**: **§B.23 Phase 3 Architecture (r07.0+,
normative)** documents the eleven decisions as MADR-style
Decision Records:

| Subsection | Topic                                          | Decision                                                |
| ---------- | ---------------------------------------------- | ------------------------------------------------------- |
| §B.23.1    | Refresher architecture                         | Complete migration to release-info / .NET release-notes |
| §B.23.2    | Catalog Title token matching                   | Config-driven via `CatalogTitleTokens` field            |
| §B.23.3    | Data directory layout                          | `data/` flat with `config-` / `cache-` / `raw-` prefix  |
| §B.23.4    | Schema versioning                              | Stay at 2.1; no Schema 2.2                              |
| §B.23.5    | SSU separation and .NET CU multiplicity        | Filename-based SSU detection; both .NET siblings always |
| §B.23.6    | DU lookback                                    | 36-month rolling cache; latest publish wins             |
| §B.23.7    | Update lifecycle                               | Patch-Tuesday-triggered; Git-tracked                    |
| §B.23.8    | PatchBaseline Type subdivision                 | `DotNet` → `DotNet.Runtime` + new `DotNet.OsLevel`; breaking |
| §B.23.9    | release-info vs Catalog conflicts              | release-info is the absolute truth source               |
| §B.23.10   | r07.0 release granularity                      | Single r07.0 release; r06.x is docs-only                |
| §B.23.11   | `-PreferBaselineMonthLcu`                      | Deferred to Phase 4+                                    |

**Existing SPEC sections amended for cross-reference**:

- §B.21.5 (Future work) now states that the Schema 2.2 sketch is
  **NOT adopted**; per-OS knowledge moves into Config-driven or
  cache-driven mechanisms instead. Cross-references §B.23.
- §B.22.1 (Directory layout) adds an r07.0 migration note: the
  `Config/` directory will be renamed to `data/` per §B.23.3.
- §B.22.2 (Filename prefix rules) adds three new rows for the
  r07.0+ `config-` / `cache-` / `raw-` prefixes.

**Headline architecture points**:

1. **Catalog becomes a URL resolver, not a discovery source.**
   KB numbers harvested from release-info are passed to the
   Catalog to obtain `.msu` URLs; Title-string heuristics for
   discovery are deleted.
2. **`Config/` directory becomes `data/` with three filename
   prefixes** (`config-`, `cache-`, `raw-`). All upstream snapshot
   data is committed to the repository alongside the human-edited
   configs, with Git as the history mechanism (no date in
   filenames).
3. **Schema 2.1 is preserved.** The optional `CatalogTitleTokens`
   field is an additive Schema 2.1 extension; no Schema 2.2 is
   cut.
4. **`Type=DotNet` is deprecated and removed** in favour of
   `DotNet.Runtime` (per-runtime KB, applied to WIM) and
   `DotNet.OsLevel` (OS-offering KB, recorded only). r07.0 is a
   breaking change for any baseline carrying the legacy value;
   no migration shim ships.
5. **DU sources from a 36-month rolling Catalog probe cache.**
   The latest publish within the window wins; absence is logged
   as a warning, not an error. This absorbs PoC-F's finding
   that Server 2025 DU.Setup has been suspended since 2025-12.
6. **release-info is the absolute truth source.** Catalog
   contradictions either (a) stop the build (release-info has a
   KB the Catalog can't resolve) or (b) are ignored (Catalog has
   a KB release-info doesn't list).

**Release plan**:

- r06.0 (this release): SPEC-only documentation, no code changes.
- r07.0 (future release): full Phase 3 implementation per §B.23.
  Breaking change for any baseline carrying `Type=DotNet`.

**Open questions deferred to a third design round** (operations
specifics, not architecture):

- ~~Automated Patch-Tuesday-triggered snapshot refresh in CI~~
  → Resolved: stage5 + stage4 two-stage automation per §B.23.14
- ~~`-PatchMonth` argument for past-month refresh~~
  → Resolved: read-only `-Action InspectBaseline -PatchMonth`
  per §B.23.13
- ~~Server 2022 dynamic baseline-month detection (CY2024 August
  anomaly)~~ → Resolved: parser records baseline-months verbatim
  including anomalies per §B.23.12
- ~~PoC scripts CI promotion to T6-T8~~ → Resolved: PoCs promoted
  to T6-T8 as part of §B.23.14

All third-round questions resolved in this release. The Phase 3
SPEC is now complete; r07.0 implementation work can proceed.

**Third-round additions to §B.23** (this release adds):

| Subsection | Topic                                              | Decision                                                |
| ---------- | -------------------------------------------------- | ------------------------------------------------------- |
| §B.23.12   | Server 2022 baseline-month detection                | Strictly data-driven; authoritative source wins        |
| §B.23.13   | Past-month inspection                               | Read-only `-Action InspectBaseline -PatchMonth YYYY-MM` |
| §B.23.14   | CI structure                                        | Two-stage automation; stage5 (snapshot) + stage4 (baseline regenerate); PoC → T6-T8 |

Additionally, §B.6 (Action → Phase Mapping) gains a new
`InspectBaseline` row, and §B.23.7's "out of scope" disclaimer
on CI automation is upgraded to "in scope per §B.23.14".

**Still not in this Phase 3**:

- No `Update-WindowsServerIso.ps1` changes (still r05.1).
- No `Config/<OsKey>.json` schema changes.
- No T1-T5 changes.
- No `data/` directory yet (rename happens in r07.0).
- No `stage5__data-snapshot.yml` yet (added in r07.0).

### r06.0 Phase 1 - Spec-only: OS Update Type Matrix

This Phase 1 deliverable is SPEC-only and intentionally contains
**no script (.ps1) changes and no on-disk Config schema changes**.
It exists to make the until-now implicit per-OS update Type
assumptions normative, which is a prerequisite for the upcoming
PoC that will validate whether Microsoft's online metadata
sources can replace the Catalogue Title-string heuristics.

**Driver**. Production telemetry from the 2026-05 Patch Tuesday
refresh (r05.1) and a design review highlighted that Server
2016/2019/2022/2025 do not actually share a uniform set of
patch Types: SSU is standalone for 2016/2019 but folded into
the LCU for 2022/2025; .NET CU file multiplicity varies per
OS; Hotpatch exists only as an online-runtime mechanism on
Server 2025 and has no offline-image equivalent. None of this
was written down anywhere normative; the Refresher's behaviour
was a side effect of "Catalogue happened to return zero results
for SSU on Server 2025".

**Changes**:

- `SPEC.md` §B.21 ("Update Type Matrix per OS generation") added
  with five subsections:
  - **B.21.1** The matrix itself: a 4-OS x 8-Type table with
    cell values of `Required` / `Optional` / `N/A` / `Possible`.
  - **B.21.2** .NET CU multiplicity per OS, with the exact
    file counts observed in 2026-05 telemetry (1, 2, 2, 1 for
    Server 2016/2019/2022/2025 respectively).
  - **B.21.3** Combined LCU package detection: the two
    independent signals (Catalogue-side: SSU query returns 0
    hits; Title-side: "combined SSU and LCU" wording) and how
    `IsCombined` is annotated on PatchBaseline entries.
  - **B.21.4** Hotpatch declared out of scope for offline
    image servicing (it is an online-runtime mechanism via
    Azure Arc; no `Add-WindowsPackage` equivalent exists).
    Includes informational note that a future
    `-PreferBaselineMonthLcu` switch could help Server 2025
    machines that want to enroll in Hotpatch.
  - **B.21.5** Future work: candidate `Common.UpdateTypePolicy`
    sub-block for a hypothetical Schema 2.2, explicitly marked
    "NOT YET ADOPTED -- contingent on PoC".
- `SPEC.md` §D.2 ("SSU before LCU") amended with an
  OS-generation note pointing to §B.21.
- `SPEC.md` §D.21 ("Umbrella KBs") amended with a reference to
  §B.21.2 for the expected per-OS file count.

**Not in this Phase 1**:

- No `Update-WindowsServerIso.ps1` changes. `$Script:ScriptVersion`
  stays at `update-wsi-2026.05.25-r05.1`. The script's runtime
  behaviour is unchanged; only the documentation now states
  explicitly what the script was already doing implicitly.
- No `Config/<OsKey>.json` schema changes. Schema stays at
  v2.0 / v2.1 as accepted by r05.0.
- No PoC code yet. Phase 2 will introduce a separate PoC
  directory to validate the online-metadata sources
  (release-info Markdown, Hotpatch baseline-month detection,
  alternative sources for .NET / Dynamic Update).

### Planned (r06 Phase 2)

- PoC for online patch metadata acquisition without
  authentication. Targets: Microsoft Learn
  `windows-server-release-info` (Markdown rendering),
  Hotpatch baseline-month detection, alternative sources for
  .NET / Dynamic Update.
- Outcome: a written report (under `scripts/poc/` or a similar
  location) recommending which sources can replace which parts
  of `Resolve-PatchSetFromCatalog`'s Title-string heuristics.

### Planned (r06 Phase 3, PoC-driven)

- Config Schema v2.2 design (only if Phase 2 demonstrates
  feasibility): a `Common.UpdateTypePolicy` sub-block that
  codifies §B.21.1 per-OS, plus per-Type metadata such as
  `ExpectedFileCount`.
- Patch Manifest Engine: an interface that lets the Refresher
  prefer online-metadata sources for KB-number resolution and
  fall back to Catalogue scraping only for MSU/CAB URL
  resolution.

### Planned (M4 - carryover from earlier roadmap)
- Server 2025 real `LCUExpandViaMum=true` code path. LCU on 2025 ships
  as a MUM/CAB bundle that must be expanded with `expand.exe -F:*`
  before `Add-WindowsPackage` is invoked.

### Planned (M5 - carryover from earlier roadmap)
- Stage 4 CI workflow (`catalog-health`): monthly scheduled run of
  `Resolve-PatchSetFromCatalog` that opens a PR with the resulting
  `Config/<OsKey>.json` diff for human review. Catches Microsoft
  Update Catalogue HTML structure changes within 30 days.

## [update-wsi-2026.05.25-r05.1] - 2026-05-25

Two production-fix changes surfaced by the first real r05.0
`-Action RefreshAllBaselines` run against the 2026-05 Patch Tuesday
release:

### Fixed - KbId/FileName mismatch in PatchBaseline.NeutralPatches

When Microsoft publishes a single "umbrella" CU whose `UpdateId`
attaches multiple `.msu` files (typical for .NET cumulative updates
and for some LCUs that bundle a checkpoint CU's payload), the
previous patch-resolution loop reused the umbrella Title-derived
KbId for every attached file. That produced PatchBaseline entries
where the recorded `KbId` did not match the actual `FileName`:

```json
// Server2019.json, May 2026 baseline (BEFORE this fix)
{ "KbId": "KB5088864", "FileName": "windows10.0-kb5087066-x64-ndp48_...msu" },
{ "KbId": "KB5088864", "FileName": "windows10.0-kb5087061-x64_...msu" }
//        ^^^^^^^^^^                              ^^^^^^^^^^
//        umbrella Title KB     actual payload KB encoded in file name
```

Three symptoms were observed in the 2026-05 production output:

- **Server2019 / Server2022 .NET CU**: two identical-KbId entries
  attached to two distinct .msu files (4.8 + 4.8.1 runtimes).
- **Server2025 LCU**: `KbId=KB5087539` (umbrella Title) with
  `FileName=windows11.0-kb5043080-x64_...msu` (checkpoint CU payload).
- **Server2022 Dynamic Update**: `Setup` and `SafeOs` queries
  resolved to the same `UpdateId` because the OS-title narrowing
  step did not separate them by intent.

This release adds two fixes:

1. **New helper `Get-KbIdFromPatchFileName`** that parses
   `kb#######` out of the standard Microsoft file-name patterns
   (`windows10.0-kb5087537-x64_...`, `windows11.0-kb5087588-x64_...`,
   `...-ndp48_...`, `...-ndp481_...`, etc.). Returns the KB id in
   canonical upper-case form; returns `''` for file names that do
   not contain a `kb` token so the caller can fall back to the
   umbrella Title.
2. **`Resolve-PatchSetFromCatalog` per-file KbId**: the
   `foreach ($primary in $primaries)` loop now derives the
   per-file KbId via `Get-KbIdFromPatchFileName` (falling back to
   the Title-derived KbId if the file name has no kb token). Each
   entry now reflects its actual payload KB.
3. **Setup/SafeOs disambiguation post-filter**: for the 21H2/24H2
   Dynamic Update queries whose `QueryTemplate` is shared, an
   additional title-keyword filter ("Setup Dynamic Update" vs
   "Safe OS Dynamic Update" / "SafeOS") is applied after the
   OS-title narrowing so the two queries no longer collide on
   the same UpdateId.

The fix is fully backward compatible: existing PatchBaseline.json
files keep loading, and the FileName + DownloadUrl fields (which
P04 FetchAssets actually uses for download) were already correct;
only the KbId label is updated.

### Added - Rich `-Action RefreshAllBaselines` console summary

`Show-RefreshAllBaselinesSummary` now renders a seven-section
end-of-run summary block that consolidates everything an operator
needs to file a baseline-refresh ticket without re-reading the full
progress log. The block is console-only (no extra files written),
which keeps CI log capture trivial. Sections:

  1. **Field-group decisions** - same counts as before
     (Skip / Manual / Monthly / InitialFill).
  2. **Per-OS patch composition** - one row per OS showing the
     final NeutralPatches count, file count, and a `Type=N` map
     across SSU/LCU/DotNet/DynamicUpdate.* buckets.
  3. **KB delta vs previous PatchBaseline** - per-OS
     `+ added (n)`, `- removed (n)`, `= unchanged (n)` lines with
     the actual KB ids, computed against the BeforePatches
     snapshot captured at the start of the OS loop.
  4. **Manual fill required** - the operator follow-up list,
     grouped by OS so each ticket / diff can be scoped per-OS.
  5. **Pca2023 readiness** - per-OS RequiredByDefault flag and
     RequiredUpdateLevelKb (Schema 2.1 only; Schema 2.0 configs
     are flagged with "(no Pca2023 block)").
  6. **Patch Tuesday timeline** - this run's baseline plus the
     next two upcoming Patch Tuesdays so the next refresh window
     is visible at a glance.
  7. **Run outcome** - explicit Status + Exit code statement
     (`OK` / exit 0, `PARTIAL` / exit 2, `FAILED` / exit 1) so
     CI dashboards do not need to parse return values to know
     whether a run was clean.

Implementation notes:

- The OS loop now captures a deep-clone `BeforePatches` snapshot
  via `ConvertTo-Json -Depth 10 -Compress | ConvertFrom-Json` so
  later in-place mutations to `$raw` cannot retroactively poison
  the "before" set.
- The new collector hashtable (`$osSummaries`) is keyed by OsKey
  and aggregates BeforePatches / AfterPatches / Changed /
  ErrorCount / ManualGroups / Pca2023 reference / PreviousVerified
  for every OS processed in the run, even those skipped due to
  Schema mismatch (skipped OSes appear with `(Schema 2.0)` in
  section 5).
- `Manual` decisions add the affected group path to
  `osSummaries[$osKey].ManualGroups`, which section 4 then walks.
- `Refresher failed` exceptions increment
  `osSummaries[$osKey].ErrorCount`. Section 7 inspects the
  overall `$okOverall` aggregate to decide between PARTIAL and
  FAILED status.

## [update-wsi-2026.05.25-r05.0] - 2026-05-25

Major version bump for two distinct (but coordinated) changes:
**(1)** complete integer renumbering of all phase IDs (removing the
historical 0.5-step inserts), **(2)** Secure Boot / PCA2023 boot
manager support per Microsoft KB 5053484 (`Make2023BootableMedia.ps1`).
Both are breaking changes for operators who reference Phase IDs by
name or who have wired specific Phase-IDs into their own runbooks.

### Breaking changes

- **Phase ID renumbering** (no aliases, no deprecation warnings).
  Old IDs (`P02.5`, `P04.5`, `P03`, `P04`, `P05`, `P06`, `P07`, `P08`,
  `P09`) are now invalid - the dispatcher will reject `-PhaseIds
  'P02.5'` style invocations. The new mapping:

  | Old ID | New ID | Phase name |
  |:---:|:---:|---|
  | P01    | **P01** | Initialize (unchanged) |
  | P02    | **P02** | ResolveInputs (unchanged) |
  | P02.5  | **P03** | RefreshPatchBaseline |
  | P03    | **P04** | FetchAssets |
  | P04    | **P05** | ExpandIso |
  | P04.5  | **P06** | ValidatePatchSet |
  | P05    | **P07** | PatchInstallWim |
  | P06    | **P08** | PatchBootWim |
  | P07    | **P09** | AssembleIso |
  | (new)  | **P10** | ConvertPca2023BootManager (Build, default-skip) |
  | P08    | **P11** | StaticVerify |
  | (new)  | **P12** | VerifyPca2023Readiness (Verify, always-runs) |
  | P09    | **P13** | FinalReport |
  | A01    | **A01** | RefreshAllBaselines (unchanged) |
  | A02    | **A02** | DumpFieldClassification (unchanged) |

- **Action mapping internal updates** (Action names unchanged):
  - `Prepare` -> `P01, P02, P03, P04, P05, P06`
  - `Build`   -> `P07, P08, P09, P10`
  - `Verify`  -> `P11, P12, P13`
  - `All` / `PrepareBuildVerify` -> all phases above
  - `GenerateManifest` -> `P01, P02, P03`

- **Function name renames** (script-internal; affects any caller
  that referenced these by reflection or `Get-Command`):
  - `Invoke-SetupPhase02_5_RefreshPatchBaseline` -> `Invoke-SetupPhase03_RefreshPatchBaseline`
  - `Invoke-FetchPhase03_FetchAssets` -> `Invoke-FetchPhase04_FetchAssets`
  - `Invoke-PlanPhase04_ExpandIso` -> `Invoke-PlanPhase05_ExpandIso`
  - `Invoke-PlanPhase04_5_ValidatePatchSet` -> `Invoke-PlanPhase06_ValidatePatchSet`
  - `Invoke-BuildPhase05_PatchInstallWim` -> `Invoke-BuildPhase07_PatchInstallWim`
  - `Invoke-BuildPhase06_PatchBootWim` -> `Invoke-BuildPhase08_PatchBootWim`
  - `Invoke-BuildPhase07_AssembleIso` -> `Invoke-BuildPhase09_AssembleIso`
  - `Invoke-VerifyPhase08_StaticVerify` -> `Invoke-VerifyPhase11_StaticVerify`
  - `Invoke-ReportPhase09_FinalReport` -> `Invoke-ReportPhase13_FinalReport`

- **Config schema bump 2.0 -> 2.1**. All four `Config/<OsKey>.json`
  files gain a new top-level `Pca2023` block. Existing readers that
  hard-code the field set will need a one-line tolerance update.

- **CSV filename change**: P11 StaticVerify now writes
  `logs/P11_verification.csv` instead of the legacy
  `logs/P08_verification.csv`.

### Added

- **P10 ConvertPca2023BootManager phase** (Build group, optional).
  Rewrites the output ISO's boot manager to be signed via the
  "Windows UEFI CA 2023" certificate chain instead of the legacy
  "Windows Production PCA 2011" chain. Required for booting under
  Secure Boot firmware that has revoked PCA2011 trust (post 2026-06
  expiry, BlackLotus CVE-2023-24932 mitigation rollout).

  - **Internal implementation**: `Convert-WimBootToPca2023Signed`
    is a PSA-clean re-implementation of Microsoft's
    `Make2023BootableMedia.ps1#Copy-2023BootBins` logic from
    `microsoft/secureboot_objects` (Version 1.4, 2026-03-13).
    Differences from upstream: Context-bag state instead of
    `$global:WIM_*`, structured logging via `Write-Step`, `throw`
    instead of `exit`, `[Parameter(Mandatory)]` shorthand,
    Verb-Noun PSA compliance.

  - **External script option**: `-Pca2023ScriptPath <path>` invokes
    a user-supplied `Make2023BootableMedia.ps1` instead of the
    internal helper, for operators who need to track Microsoft's
    upstream script version directly.

  - **Multi-layered opt-in**: requires `-EnablePca2023BootManager`
    at minimum; Server 2025 additionally requires
    `-ForcePca2023OnServer2025` because certified Server 2025
    server platforms include the 2023 certificates in firmware
    (KB 5053484 does not list Server 2025 in its supported-OS
    set).

  - **Pre-flight gates**:
    - silent skip if `-EnablePca2023BootManager` not set
    - silent skip if OsKey=Server2025 without `-ForcePca2023OnServer2025`
    - silent skip if pre-flight readiness Health = 'Healthy' (already PCA2023)
    - throw if Health = 'Critical' (source media < 2024-04-09 LCU)

- **P12 VerifyPca2023Readiness phase** (Verify group, always-runs).
  Read-only inspection of the produced ISO; emits JSON + Markdown
  reports under `<WorkRoot>/pca2023/`. Three-tier diagnostic:
  - Tier 1: File-existence checks on `boot.wim:\Windows\Boot\EFI_EX\`
    staging directories (the 2024-4B presence signal)
  - Tier 2: `Get-WindowsPackage` LCU month detection on install.wim
    and boot.wim (the 2024-4B integration level)
  - Tier 3: `Get-AuthenticodeSignature` chain walk on
    `efi\boot\bootx64.efi` (the actual firmware-visible signer
    identity)

- **9 new SecureBoot helper functions** in the script:
  - `Get-LcuVersionFromInstallWim` (DISM `Get-WindowsPackage` wrapper)
  - `Get-WimSystemHiveValue` (offline SYSTEM hive read via `reg.exe load`)
  - `Test-Pca2023AuthenticodeChain` (X509Chain walk for cert classification)
  - `Get-IsoBootCertReadiness` (per-ISO inventory assembler)
  - `Get-Pca2023ReadinessSnapshot` (top-level snapshot with Health 4-value)
  - `Show-Pca2023ReadinessSnapshot` (`-Compact` + full console renderer)
  - `Format-Pca2023ReadinessForReport` (StringBuilder text formatter)
  - `Get-OrEnsurePca2023Snapshot` (idempotent cache accessor)
  - `Convert-WimBootToPca2023Signed` (Microsoft `Copy-2023BootBins` reimpl)

- **`-Pca2023OnlyMode` short-circuit**: takes an existing ISO via
  `-IsoPath` and runs ONLY P12 against it. No download, no patching,
  no ISO re-assembly. For forensic inspection of pre-built ISOs.
  Output JSON goes to `$env:TEMP\updwsi_pca2023only_<pid>\`.

- **3 new T3 smoke tests** in `tests/powershell_harness.py` covering
  the SecureBoot helpers' error paths
  (`Test-Pca2023AuthenticodeChain` missing-file,
  `Get-LcuVersionFromInstallWim` missing-mount,
  `Format-Pca2023ReadinessForReport` null-snapshot safety).

- **SPEC.md sections**:
  - B.18 (PCA2023 boot manager support)
  - B.19 (`-Pca2023OnlyMode` standalone inspection)
  - B.20 (Build-group optional phase exception)
  - D.22 (Secure Boot baseline considerations / lessons learned)

### Changed

- **All 9 phase function definitions renumbered** to integer Phase
  IDs (the renumbering side of this major bump). Function bodies
  unchanged; only the names + the `Start-DebugTrace -PhaseId 'PNN'`
  arguments + the `$Script:PhaseRegistry` rows update.

- **381 Phase ID literals renamed** across the script body (215),
  CHANGELOG/README/SPEC/TESTING (163), and tests/ (3). All `'P02.5'`,
  `'P04.5'`, `'P03'`...`'P09'` quote-wrapped string literals are
  rewritten to their new integer IDs. Markdown body text mentions
  of `P02.5`, `P04.5`, `P03`...`P09` are also rewritten.

- **`$Script:PhaseRegistry`** gains P10 (`ConvertPca2023BootManager`,
  Build) and P12 (`VerifyPca2023Readiness`, Verify) entries.

- **`Resolve-PhasesForAction`** internal mapping updated to reflect
  new integer phase IDs and added P10 / P12 placement (Build / Verify
  groups respectively).

- **P13 FinalReport** now includes a Compact-form PCA2023 readiness
  summary inline (after Log locations, before the `.markers/P13.ok`
  marker write). The detail JSON + Markdown remain in
  `<WorkRoot>/pca2023/` for machine consumers.

- **Per-OS PCA2023 defaults** baked into
  `Config/<OsKey>.json#/Pca2023`:
  - Server2016/2019: `RequiredByDefault=true`, MinDate=`2024-04-09`
  - Server2022: `RequiredByDefault=true`, MinDate=`2025-02-11`
    (per Lenovo lp2353.pdf 20348.2227 baseline requirement)
  - Server2025: `RequiredByDefault=false` (firmware-provided 2023 certs)

### Internal

- Stage A / Stage B internal work organisation:
  - Stage A = pure phase ID renumbering. The script was renamed in
    bulk and ran clean (psa.py 0/0/0, PSScriptAnalyzer 0, T2
    13/13 PASS, T3 7/7 PASS) before any new code was written.
  - Stage B = SecureBoot feature implementation on top of the
    renumbered Stage A baseline.
  - The final r05.0 release ZIP is a single artifact even though
    the internal work was two-staged.

- Custom Python tool `stage_a_renumber_v2.py` for the bulk Phase ID
  rewrite. Uses an opaque-token two-pass strategy to safely handle
  chained renames (where old `'P03'` -> new `'P04'` and old `'P04'`
  -> new `'P05'` would otherwise collide). The token form is
  `XOPAQUEXX<two-digit>XX` which by construction never matches a
  `\bP\d\d\b` regex.

- `read_bytes` / `write_bytes` are used throughout the rewrite tool
  to preserve CRLF line endings on `.ps1` files (Python's `read_text`
  / `write_text` normalise CR/LF, which would have violated the
  `.gitattributes` `*.ps1 text eol=crlf` policy).

### Added (post-Stage-B integration from microsoft/secureboot_objects)

The following six improvements were folded into the r05.0 release
after a second-pass audit of the upstream Microsoft repository
(microsoft/secureboot_objects @ main). They are NOT bug fixes;
they are quality / documentation upgrades surfaced by the audit.

- **oscdimg.exe SHA-256 supply-chain integrity check** (`Resolve-OscdimgExe`).
  After locating `oscdimg.exe`, the function now compares the binary's
  SHA-256 against Microsoft's reference hash for the current
  architecture (AMD64 / ARM64 / x86), lifted verbatim from
  `Make2023BootableMedia.ps1#$global:oscdimg_known_hashes` Version 1.4.
  Mismatch is ADVISORY (warning only), because ADK-installed binaries
  may legitimately differ across ADK versions. The check still detects
  the high-impact failure mode: a malicious binary swap on the host
  running the script.

- **NTFS filesystem check in workspace preflight** (`Assert-WorkspacePreflight`).
  Adds a "Check 3" after the disk-space check: confirms the drive
  hosting `-WorkRoot` is formatted as NTFS. WIM mount and DISM
  operations rely on NTFS-only reparse-point / per-stream-metadata
  semantics; ReFS or FAT32 produce silent corruption. Mirrors
  Microsoft's own
  `Make2023BootableMedia.ps1#Initialize-StagingDirectory` enforcement.
  Skipped under `-DryRun` and on non-Windows pwsh hosts (synthetic CI).

- **SPEC.md D.23 — UEFI Secure Boot defaults templates (informational)**.
  New section documenting the five reference templates from
  `microsoft/secureboot_objects/Templates/` (`MicrosoftOnly`,
  `MicrosoftAndOptionRoms`, `MicrosoftAndThirdParty`,
  `MostCompatible`, `LegacyFirmwareDefaults`) and how target firmware
  template choice affects whether to run P10. These templates describe
  firmware-layer Secure Boot variables and are out of scope for direct
  consumption, but operators need to understand them to interpret P12
  output correctly. Includes a per-template "PCA2023 media required?"
  decision matrix.

- **SPEC.md D.22 — KB 5053484 official scope + `-MediaPath` form
  details**. Promoted from a fuzzy "Microsoft KB documentation" link
  to an explicit "Applies To" enumeration (Server 2012/R2/2016/2019/2022
  + Windows 10/11 client SKUs; Server 2025 deliberately not listed)
  and a documented narrowing rationale (upstream `-MediaPath` accepts
  ISO / directory / network share; this project's pipeline operates on
  the extracted-tree form only for repeatability and auditability).
  README.md and README.ja.md gain a one-paragraph summary of the same.

- **T3 schema-validation tests** (`tests/powershell_harness.py`).
  Three new tests modelled on
  `microsoft/secureboot_objects/scripts/test_validate_dbx_references.py`
  7-axis pattern (absent / empty / invalid JSON / missing field /
  ...). Coverage added:
  1. `Get-IsoBootCertReadiness` non-existent media → `.Available=$false`
     + `.ErrorMessage` mentions boot.wim
  2. `Get-IsoBootCertReadiness` schema completeness — the error-path
     inventory must still carry every documented snapshot field so
     P12 JSON serialization / P13 summary never AttributeError
  3. `Get-Pca2023ReadinessSnapshot` Health enum constraint — must be
     one of `{Healthy, Warning, Critical, Unknown}` even on the
     error path; never `$null` or free-form string

- **`.markdownlint.yaml` configuration file**. New project-root
  markdown lint config adapted from
  `microsoft/secureboot_objects/.markdownlint.yaml`. Adjusted for
  this project's conventions: line_length=120, code_blocks=false,
  tables=false; MD024 (duplicate headings) and MD041 (must-open-
  with-heading) disabled per Keep a Changelog and tests/README
  conventions. The file is opt-in for contributors who run
  markdownlint locally; CI is not yet wired to enforce it.

### Fixed (Schema v2.1 loader, post-publication regression)

The Stage A renumber and Stage B Pca2023 feature work bumped the
Config schema from v2.0 to v2.1 in all four `Config/Server*.json`
files, but **did not** update the `Get-ConfigProfile` loader's
schema-acceptance check, which remained `-eq '2.0'` and rejected
all four r05.0 Configs at runtime. The first `-Action
PrepareBuildVerify` smoke test (Stage 2 Smoke3) failed at P02
ResolveInputs with:

```
[X] Phase P02 (ResolveInputs) failed: Config Server2019.json has
    Schema="2.1"; expected "2.0". Legacy schemas are not supported.
```

Two loaders are now updated to accept both schemas:

- **`Get-ConfigProfile`** (the main per-OS loader called from P02
  ResolveInputs and from every Action that needs OS data) now
  accepts `Schema ∈ {'2.0', '2.1'}`. When `Schema == '2.1'`, the
  `Pca2023` block is also required (per SPEC.md B.10); when
  `Schema == '2.0'`, no Pca2023 block is required — preserving
  full backward compatibility with Configs predating r05.0.

- **`Invoke-AdminAction_RefreshAllBaselines`'s loader** (used by
  Action A01 to walk all four Configs for baseline refresh) is
  updated symmetrically. It also accepts both schemas but does
  not require `Pca2023` (the action only touches `PatchBaseline`
  fields, so the Pca2023 block is orthogonal).

The error message now lists all accepted schemas explicitly
(`expected one of: 2.0, 2.1`), so future schema bumps will produce
a self-documenting error indicating exactly which versions the
running script supports.

### Fixed (CI workflow remediation, r04.x carryover)

Audit of the most recent CI run on `main` (`1aa96df`, STAGE 1
Linux checks #12) surfaced two pre-existing problems that were
about to make the next push fail; both are fixed in r05.0:

- **STAGE 1 Config JSON validator was still using Schema v1 keys**
  (`OsName`, `OsShortName`, `Build`, `Architecture`, `Languages`
  at top level). Schema v2.0 (introduced in r03) restructured these
  under `Common/PatchBaseline/LanguageSpecific`, and Schema v2.1
  (r05.0) added the `Pca2023` block. The validator therefore failed
  with `FAIL: Server2016.json missing top-level "OsName"` and
  exited 1, which cascaded into "psa.sarif not produced" and
  "pssa.sarif not produced" errors in downstream steps. The
  validator has been rewritten to accept Schema 2.0 (warned) and
  2.1 (required), to verify the `Common.*` fields, and to enforce
  the `Pca2023` block presence when `Schema == 2.1`.

- **Embedded em dash (U+2014) in `Assert-WorkspacePreflight`** broke
  the BOM + CRLF + ASCII-only validator at line 2195. The character
  was introduced during Stage B Step 3 (NTFS check) and is now
  replaced with two ASCII hyphens. The validator now passes again
  (416,708 bytes, ASCII-only).

### Changed (CI infrastructure modernisation, r05.0)

Coordinated bump of all GitHub Actions to Node 24-compatible
versions ahead of the 2026-09-16 Node 20 removal deadline and the
December 2026 CodeQL Action v3 deprecation. Affects all 8 workflow
files (update-windows-server-iso STAGE 1-4, download-speakerdeck
STAGE 1-3, psa.py CI):

| Action | Was | Now |
|---|:---:|:---:|
| `actions/checkout` | `@v4` | `@v5` |
| `actions/setup-python` | `@v5` | `@v6` |
| `actions/upload-artifact` | `@v4` | `@v5` |
| `github/codeql-action/upload-sarif` | `@v3` | `@v4` |
| `peter-evans/create-pull-request` | `@v7` | `@v8` |
| `actions/cache` | `@v4` | `@v4` (unchanged - current) |
| `microsoft/psscriptanalyzer-action` | `@v1.1` | `@v1.1` (no v2 released) |

Additionally, `setup-python` now pins to **`python-version: '3.12'`**
instead of the previous `'3.x'`. The latter was resolving to
CPython 3.14.x on the GitHub-hosted Ubuntu 24.04 runner, which
has not been validated against psa.py + the T1-T5 self-
verification tool suite. Pinning to 3.12 (the version the project
has run its full test matrix on) restores deterministic behaviour
and forms an explicit upgrade point — bumping it requires running
the test matrix locally on the target Python version first.

Workflow comments referencing old phase IDs (`P02.5`, `P04.5`,
`P02/P03/P04`, `P08 verify`, "P01 through P09") are also updated
to the r05.0 phase numbering (`P03`, `P06`, `P02/P04/P05`,
`P11 verify`, "P01 through P13").

### Added (CI runner diagnostic pre-flight, r05.0)

Following review of the failed Stage 1 run from commit `1aa96df`,
each CI workflow gains a `[Diag] Runner environment snapshot` step
at the start of the job. The goal is to make triage tractable when
scheduled (Stage 4 cron) or flaky failures occur — every failed run
should carry enough information to diagnose runner-side drift
without re-running the job.

The diagnostic step captures (per stage):

| Stage | Diagnostic information |
|---|---|
| **Stage 1 / psa.py CI (Linux)** | `uname -a`, Python version, `pwsh` presence, CWD, key env vars, repo layout |
| **Stage 2 (Windows)** | `$PSVersionTable`, `Get-ExecutionPolicy -List`, console encoding, identity + admin check, env vars, oscdimg.exe presence at canonical ADK paths |
| **Stage 3 (Windows)** | Same as Stage 2 + free disk space on `C:` |
| **Stage 4 (Windows)** | PSVersion, ExecutionPolicy, identity, env vars |

Each diagnostic step uses `$ErrorActionPreference = 'Continue'`
(or `set +e` for bash) so a missing tool does not tank the
diagnostic step — the goal is to record what IS available.

Additionally, **all** non-diagnostic Windows PowerShell steps
across Stages 2, 3, and 4 are uniformly hardened with:

- `$ErrorActionPreference = 'Stop'` — prevents silent error
  swallowing (PS 5.1's default is `Continue`).
- `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8` —
  prevents PS 5.1's legacy ANSI code-page default from mangling
  non-ASCII characters in log streams or `$GITHUB_*` files.
- `defaults.run.working-directory: ${{ github.workspace }}` at the
  job level — anchors relative paths to the checkout root rather
  than to a surprising platform-default location.

Background reference material is captured in
`documents/ci-engineering/github-actions-windows-powershell-guide.md`
(new file in this release). SPEC.md gains a new §C.5c documenting
the diagnostic-step contract.

## [update-wsi-2026.05.25-r04.4] - 2026-05-25

### Added - Self-verification tool suite (`tests/`)

A new `tests/` subdirectory ships alongside `Update-WindowsServerIso.ps1`
holding five Python-based self-verification tools. They exist because
the three live-test bugs fixed in r04.3 had a common root cause -
silent Microsoft-side change in the Catalog HTML / data that no
purely-static analysis could catch - and the project needed a way
for both Claude and human operators to confirm the script's
Microsoft-side assumptions still hold before AND after any change.

The tool suite:

| Tool | Purpose | Network? |
|---|---|:---:|
| `catalog_probe.py`        (T1) | Live Microsoft Update Catalog probe (search, supersedence panel, title-format per OS); diffs vs `snapshots/last_probe.json` | Yes |
| `catalog_fixture_test.py` (T2) | Offline regression test against saved HTML fixtures (`fixtures/2026-05/`); 13 assertions including bug-2 and bug-3 regressions | No |
| `powershell_harness.py`   (T3) | Python-side driver that invokes PowerShell functions via the new `-Action TestHarness` REPL; 7 assertions on Get-CatalogQueryTemplate, Select-AllCanonicalPatchFiles, etc. | No |
| `eval_iso_probe.py`       (T4) | HTTP Range-GET against each `Config/Server<N>.json#/.../Iso/Url`; reports MB + Last-Modified per OS | Yes |
| `wsusscn2_probe.py`       (T5) | HTTP probe of `wsusscn2.cab`; warns when the cab is older than 60 days | Yes |

All tools use **standard-library Python only** (no `pip install`
required), matching the dependency policy already set by
`scripts/python/powershell-static-analyzer/psa.py`.

The directory layout:

```
tests/
  README.md                    -- per-tool usage + when-to-run guide
  catalog_probe.py             -- T1
  catalog_fixture_test.py      -- T2
  powershell_harness.py        -- T3
  eval_iso_probe.py            -- T4
  wsusscn2_probe.py            -- T5
  common/
    catalog_client.py          -- urllib HTTP fetcher with retry-with-jitter
    html_parsers.py            -- Catalog HTML extractors (intentionally
                                  mirrors the PS regexes)
    ps_invoke.py               -- PSSession context manager driving the
                                  -Action TestHarness REPL
    snapshot.py                -- JSON snapshot read/write + diff_dict()
  fixtures/2026-05/            -- 6 HTML files (~331 KB) + expected.json
  snapshots/                   -- T1 output (last_probe.json) lives here
```

### Added - `-Action TestHarness` (script REPL hook)

The PowerShell script gains a new dispatcher branch `-Action TestHarness`,
placed before `Show-EntryBanner` so no banner contaminates stdout.
It loads all function definitions in the current session, then drains
stdin one JSON line at a time, parsing requests of the form
`{"fn":"<FunctionName>","args":{ ... }}` and emitting JSON responses
of the form `{"ok":true,"fn":"...","result": ...}` or
`{"ok":false,"error":"<message>","fn":"..."}`. The REPL exits on
EOF.

This is the entry point for T3 (`tests/powershell_harness.py`).
It is not intended for human invocation; the `-Action` help text
explicitly says so.

`-Action TestHarness` is added to the `osLessActions` set
(no `-OsVersion` required) and to the workspace-preflight skip list
(no Config / 100 GB requirement).

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (7,695 lines).
- PSScriptAnalyzer 1.25.0: 0 findings.
- All 5 self-verification tools pass live + offline runs:
  - T1: 7/7 checks, snapshot persisted
  - T2: 13/13 fixture assertions
  - T3: 7/7 PowerShell function assertions
  - T4: 8/8 Iso endpoints (Server2016 endpoint host rejects Range/HEAD;
    treated as "unprobable, not broken")
  - T5: detects `host_not_allowed` egress in restricted environments
    and reports exit 3 (NOT 2), so the operator can tell apart
    "Microsoft outage" from "execution environment blocks the host"

### Compatibility

- `ScriptVersion` bumped to `update-wsi-2026.05.25-r04.4`;
  `ScriptTag` is `self-verification-tools-and-test-harness`.
- No behaviour change for any production Action (Prepare / Build /
  Verify / PrepareBuildVerify / RefreshAllBaselines / Cleanup etc.).
  The TestHarness branch is reached only by an explicit
  `-Action TestHarness` invocation.

## [update-wsi-2026.05.25-r04.3] - 2026-05-25

### Fixed - `NeutralPatches[].Type` mis-classification

Live first-pass test of `-Action RefreshAllBaselines` (2026-05 cycle)
exposed that the `Type` field on every Catalogue-derived
`NeutralPatches` entry was being computed by file-name heuristics in
`Get-PatchType`, even though the calling code in
`Resolve-PatchSetFromCatalog` already knew the authoritative Type
from the Catalogue search query (`SSU` / `LCU` / `DotNet` /
`DynamicUpdate.SafeOs` / `DynamicUpdate.Setup`). The heuristic
broke whenever the file name lacked the expected token (e.g. SSU
file names containing only `kb<N>` with no `servicingstack`
substring; SafeOS DU file names with `kb<N>` but no `safeos`;
.NET CU sub-files without `ndp<N>` or `.net`). Affected real
2026-05 entries were:

| OS | KbId | Title type | Wrong `Type` | Correct `Type` |
|---|---|---|---|---|
| Server2016 | KB5088064 | Servicing Stack Update | `LCU` | `SSU` |
| Server2019 | KB5088864 | Cumulative Update for .NET Framework | `LCU` | `DotNet` |
| Server2025 | KB5087588 | Safe OS Dynamic Update | `LCU` | `DynamicUpdate.SafeOs` |

The Type-routing in `$Script:PatchTargetMap` (SPEC §B.12) depends on
this field to send each patch to the right WIM-target sub-phase
(SPEC §B.14), so the mis-classification would have made install.wim
patching ineffective on a live ISO build.

**Fix**: added `-KnownType` parameter to
`Convert-CatalogPatchToBaselineEntry`. When the caller passes a
non-empty string (which `Resolve-PatchSetFromCatalog` now does
unconditionally via `-KnownType $q.Type`), the function uses that
value verbatim instead of running the file-name heuristic. The
heuristic remains as the fallback path for the empty-`KnownType`
case (preserving backwards compatibility for ad-hoc or test
callers). `Resolve-LanguageSpecificPatchesFromCatalog` was reviewed
and already constructed its entries with `Type = $q.Type` directly,
so no change was needed on the LSP side.

### Fixed - Server2022 Catalogue narrow filter returned zero results

Live first-pass test also exposed that **every** Server 2022 query
fell through `Resolve-PatchSetFromCatalog`'s narrow filter with
zero hits, producing an empty `PatchBaseline.NeutralPatches`
array for `Config/Server2022.json`. Microsoft Update Catalogue has
since dropped the comma in Server 2022 update titles
("Microsoft server operating system, version 21H2" →
"Microsoft server operating system version 21H2", matching the
Server 2025 / 24H2 format). The hard-coded TitleToken used
`[regex]::Escape($titleToken)` (literal match including the
comma), so the new comma-less titles failed to narrow.

**Fix**: `Get-CatalogQueryTemplate` Server2022 branch and
`Get-LanguagePackQueryTemplate` `osTitleTokens` now accept BOTH the
comma-less and the historical comma form via an OR-matched
`TitleTokens` array. The actual `Search.aspx` query strings were
also updated to the current (comma-less) form because that is
what the live Catalogue listings display. The new structure is
robust against any future Microsoft re-edit that flips the format
back.

Verification: live `-Action RefreshAllBaselines -DryRun -OnlyOs
Server2022` now resolves 5 patch entries (LCU + 2 .NET files +
supersedence-dedup of 3 stale .NET candidates), versus 0 before
the fix.

### Fixed - umbrella .NET CU lost N-1 sub-files

Live first-pass test exposed that umbrella .NET Cumulative Update
KBs (e.g. Server 2019 KB5088864 which bundles 4.7.2 and 4.8) lost
all but one MSU when `Select-CanonicalPatchFile` was called: the
function is designed to return a single best file, and there is no
genuine ranking between two ndp-runtime variants of the same
umbrella KB, so the second .msu was silently dropped. Effect: on
an install.wim that contains the dropped runtime, the .NET CU
would have been a no-op and the corresponding CVEs would have
remained unpatched.

**Fix**: added `Select-AllCanonicalPatchFiles` (companion to the
existing single-file picker). It applies the same scoring rules
(so Express / Delta / PSF / metadata are still rejected) but
returns every link that scored > 0. `Resolve-PatchSetFromCatalog`
now routes `Type='DotNet'` queries through the multi-file picker
and emits one `NeutralPatches` entry per surviving file, all
keyed off the same umbrella KB / UpdateId / Title. SSU / LCU /
SafeOS / Setup DU queries continue to use the single-file picker
since Microsoft publishes a single canonical file per UpdateId
for those types.

Verification: live `-Action RefreshAllBaselines -DryRun -OnlyOs
Server2022` for 2026-05 now keeps two .NET .msu files
(`...-x64-ndp481_...msu` and `...-x64-ndp48_...msu`) on the
KB5088862 umbrella entry, where r04.2 would have kept only one.

### Added - `Assert-WorkspacePreflight` (preflight check)

New mandatory preflight that runs before the Action dispatcher.
Two checks, both fatal:

1. **Config presence**. The four canonical
   `Config/Server<N>.json` files (Server2016, Server2019,
   Server2022, Server2025) must exist alongside the script. The
   check fails fast with a list of any missing files, so the run
   does not proceed into the Catalogue scrape only to throw a
   less-helpful "config not found" error in P02 / A01.
2. **Drive free space**. The drive backing `-WorkRoot` must have
   at least **100 GB** free. This is the documented minimum for
   an end-to-end `PrepareBuildVerify` run for one OS (input ISO
   ~7 GB + extracted source ~7 GB + mounted WIM scratch ~15 GB +
   patches ~10 GB + output ISO ~7 GB + DISM headroom). The disk
   check is skipped under `-DryRun` because dry runs do not
   actually write large files.

Preflight is placed **before** the Action dispatcher (rather than
inside P01) so that Admin actions like `-Action RefreshAllBaselines`
and `-Action DumpFieldClassification` (which never run P01) are
also protected. It is intentionally skipped for `-Action ListPhases`
(quick branch that exits without any workspace contact),
`-Action Cleanup` (whose entire purpose is to remove a
partially-built workspace), `-EnvironmentInfoOnly` (the user
explicitly asked for the env dump only), and `-SkipEnvCheck`
(operator override).

The existing P01 Step 4 disk-space check is retained as
informational only; the authoritative 100 GB enforcement happens
in the preflight, and Step 4 now only emits a warning when free
space is below 100 GB (which can only occur if `-SkipEnvCheck`
bypassed the preflight).

### Changed - `-WorkRoot` default is now script-relative

The default value of `-WorkRoot` has changed from the absolute
`C:\Temp\Workspace_UpdateWsi` to the script-relative
`Workspace_UpdateWsi`. The existing `Resolve-RelativeToScript`
helper resolves the relative path against `$Script:ScriptRoot`
(i.e. the directory containing `Update-WindowsServerIso.ps1`),
producing a workspace that lives next to the script tree by
default. Operators who relied on the old `C:\Temp\...` default
should pass `-WorkRoot 'C:\Temp\Workspace_UpdateWsi'` explicitly
or update their automation; the absolute-path override is
unchanged and still works.

The new default plays well with the preflight Config-presence
check above: when the workspace is script-relative, the
`Config/` directory checked by preflight is the same `Config/`
directory shipped with the script.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (7,627 lines).
- PSScriptAnalyzer 1.25.0: 0 findings.
- Live smoke `RefreshAllBaselines -DryRun -OnlyOs Server2025`:
  exit 2 (Manual fill expected), preflight passes, all 5 patch
  Types resolve correctly, supersedence dedup excludes one
  .NET 3.5+4.8.1 false-positive (unchanged from r04.2 behaviour).
- Live smoke `RefreshAllBaselines -DryRun -OnlyOs Server2022`:
  preflight passes, **5 patch entries resolve** (vs 0 in r04.2
  due to bug 2), the umbrella .NET CU keeps both ndp-runtime
  MSUs (vs 1 in r04.2 due to bug 3).

### Compatibility

- Existing `Config/Server<N>.json` files are unchanged in
  structure (Schema v2.0). r04.3 just produces correct `Type`
  fields and an extra .NET entry for umbrella KBs on the next
  `-Action RefreshAllBaselines` run.
- Operators who depended on the old `-WorkRoot` default need to
  either accept the new script-relative location or pass
  `-WorkRoot` explicitly.
- `ScriptVersion` is bumped to `update-wsi-2026.05.25-r04.3`;
  `ScriptTag` is `live-test-fixes-and-preflight-checks`.

## Documentation maintenance - 2026-05-24

### Added - `TESTING.md`

Created `TESTING.md` for this sub-project to align with the
repository-wide governance documented in the root [`README.md`](../../../README.md)
"Language Policy" section, which lists `TESTING.md` among the
sub-project documents that are maintained in English only. The
sister project `download-speakerdeck-oracle4engineer/` has carried
a `TESTING.md` from the start; adding one here brings this project
to parity.

Contents:

- **Section 0** — Verification status summary table
- **Section 1** — Static analysis gate (psa.py + PSScriptAnalyzer
  invocation and expected output)
- **Section 2** — Unit tests for the deterministic helpers
  (PatchPlan engine, sub-phase sequence builders,
  supersedence-aware deduplication; 14 test cases total)
- **Section 3** — Synthetic smoke tests 1 through 7 with command
  lines and acceptance criteria
- **Section 4** — Live Microsoft Update Catalogue verification
  (read-only network calls)
- **Section 5** — Operator-pending: real ISO integration. This
  section is intentionally a placeholder because the maintainer
  has no suitable Windows host with DISM access. The acceptance
  criteria are documented; the results table is empty until an
  operator runs the procedure end-to-end and submits results via PR.
- **Section 6** — Continuous integration coverage including the
  Stage 4 monthly-refresh workflow's role as a continuous
  verification of the Catalogue scrape paths
- **Section 7** — Discovered bugs and fix history (cross-references
  to the per-release CHANGELOG entries)

### Changed - sub-project `README.md` and `README.ja.md`

Both READMEs now list `TESTING.md` in the "Folder layout" /
「フォルダ構成」block and end with a paragraph pointing readers
to it ("If you want to know what has been verified and what is
still operator-pending, read TESTING.md").

### Changed - root `README.md` and `README.ja.md` (CI section)

The Continuous Integration section in both root READMEs was
updated to reflect the four `update-windows-server-iso` workflows
introduced in r03 and r03.1:

- The intro line changed from "four GitHub Actions workflows" to
  "eight GitHub Actions workflows" (the Japanese equivalent
  changed from "4 本" to "8 本").
- Four new rows were added to the badge table:
  Update-WindowsServerIso STAGE 1 (Linux), STAGE 2 (Windows),
  STAGE 3 (Synthetic full pipeline), STAGE 4 (Monthly baseline
  refresh).
- A new paragraph immediately after the badge table explains the
  Stage 4 workflow's distinctive `cron`-on-the-15th schedule, its
  PR-creation behaviour when `Config/Server*.json` baselines drift
  from the live Microsoft Update Catalogue state, and its
  classification as an operations workflow (not a quality gate;
  failures do not block other workflows).

These updates close a documentation gap that opened when the
Update-WindowsServerIso project was first added to the repository:
the per-sub-project STAGE 4 workflow existed in `.github/workflows/`
and was already documented in this project's CHANGELOG, but the
root READMEs had not been refreshed to reflect the new total
workflow count.

### Quality

- `psa.py` and PSScriptAnalyzer baselines are unchanged from
  r04.2 because no source code was modified. This is a
  documentation-only maintenance pass.
- `ScriptVersion` is **not** bumped; this entry follows the
  same precedent as the sister project's r21 cleanup commit
  (documentation-only changes do not require a script version
  change).

## [update-wsi-2026.05.24-r04.2] - 2026-05-24

### Added - Supersedence-aware Catalogue patch selection

`Resolve-PatchSetFromCatalog` (in `.build_part08c_catalog_scraper.ps1`)
now resolves the case where the OS-aware Catalogue search returns
multiple candidates for a single patch Type. Previously this case
silently picked `narrowed[0]` (sort-stable but with no real-world
meaning), which could let a wrong KB through when:

- The same monthly slot has both a preview and a final entry
- A neighbouring KB (e.g. a ".NET Framework 3.5 and 4.8.1 Cumulative
  Update") matches the OS Title token used in the LCU query
- Catalogue HTML structure changes confuse the narrowing predicate

The new logic invokes `Get-SupersedenceFromCatalog` for each
non-Preview narrowed candidate, then calls the new
`Select-LatestPatchBySupersedence` helper to keep only the latest
survivor. Excluded candidates are recorded in
`$Script:LastSupersedenceExclusions` for the caller's diagnostic CSV.

Supersedence lookup is only triggered when the narrowed candidate
count exceeds 1; the single-candidate case bypasses the extra HTTP
calls.

### Added - `Select-LatestPatchBySupersedence` helper

New module `.build_part09d_supersedence.ps1` (~200 lines) implements
the deduplication logic:

| Input cardinality | Behaviour |
|-------------------|-----------|
| 0 candidates | Returns `Best=$null`, `Excluded=@()` |
| 1 candidate  | Returns that candidate as Best |
| 2+ candidates | Exclusion pass: any candidate whose KbId or UpdateId appears in another candidate's `Supersedes` array is dropped; if exactly one survivor remains, it is the Best; if multiple survivors remain, sort descending by Title (Catalogue titles start with `YYYY-MM` so lexicographic desc = newest) and pick the first, marking the rest as `Ambiguous; chose newest by title` |
| Edge case (all candidates excluded each other) | Fall back to the first input candidate with a warning |

Each excluded entry carries `Type`, `ExcludedKbId`, `ExcludedTitle`,
`SupersededByKbId`, `SupersededByTitle`, `MatchedToken`, and a
human-readable `Reason` suitable for CSV emission.

### Added - `Get-KbIdFromUpdateTitle` helper

Small utility that extracts the `KB######` substring from a
Catalogue update title using the canonical `(KB\d{6,7})` pattern.
Returns an empty string when no KB id is present.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (7,368 lines).
- PSScriptAnalyzer 1.25.0: 0 findings.
- Unit tests for `Select-LatestPatchBySupersedence` (5/5 PASS):
    * Two candidates with cand2 superseding cand1 -> cand1 excluded
    * Single candidate -> passthrough, no exclusion
    * Two candidates without supersedence relation -> ambiguous, title-desc tiebreak
    * Supersedes contains UpdateId (not KbId) -> substring match still works
    * Empty input -> Best=$null
- Unit tests for `Get-KbIdFromUpdateTitle`: extracts from canonical titles, returns empty for non-matches.
- Live Smoke 5 (`-Action RefreshAllBaselines -DryRun -OnlyOs Server2025`)
  exercises the supersedence path on real Microsoft Update Catalogue
  data and correctly excludes a stray .NET 3.5+4.8.1 candidate that
  the LCU OS-aware query had picked up as a false positive.

### Changed - Documentation cleanup

References to the deferred ".NET 3.5 Feature on Demand" item have
been removed from CHANGELOG and SPEC. The feature is no longer in
scope: Microsoft's recommended deployment path for .NET 3.5 is to
enable it after image deployment via `Install-WindowsFeature
NET-Framework-Core` (or `Add-WindowsCapability -Online`), not to
embed it in the image.

### Compatibility

- No schema change. Config files (`Config/Server*.json`) and the
  PatchPlan hashtable shape are unchanged from r04.1.
- `ScriptVersion` is bumped to `update-wsi-2026.05.24-r04.2`;
  `ScriptTag` is `supersedence-aware-patch-selection`.
- Existing single-candidate Catalogue queries see no behaviour
  change (the extra `Get-SupersedenceFromCatalog` calls only fire
  when narrowing leaves 2 or more candidates).

### Out of scope (deferred to a future release)

- Setup binaries servicing via pending.xml (Setup DU). Microsoft
  Server LTSC editions rarely publish Setup DU, and verification
  requires a Windows host running setup.exe, so this is not
  high-leverage for our use case.
- Per-language Optional Components for WinRE.
- ISO release detection refresher for `LanguageSpecific.<lang>.Iso`.
- Python JSON Schema validator that consumes the
  `DumpFieldClassification` output.

## [update-wsi-2026.05.24-r04.1] - 2026-05-24

### Added - Microsoft media-dynamic-update servicing sub-phase engine

The PatchPlan engine introduced in r04 now emits ordered sub-phase
sequences (per-WIM-target) that reproduce Microsoft's official
servicing sequence end-to-end:

**install.wim sequence** (with twice-apply when language packs are
present):

| Sub-phase                    | Patches              | Notes |
|------------------------------|----------------------|-------|
| I1.SSU                       | SSU                  | servicing stack first |
| I2.LanguagePack              | LP / LXP / DotNet LP | must precede LCU |
| I3.LCU.FirstPass             | LCU                  | after LP per Microsoft |
| I4.DotNet                    | .NET CU              | |
| I5.DynamicUpdate.Component   | DU.Component         | |
| I6.CleanupAndExport          | (marker)             | DISM cleanup hook |
| I7.LCU.SecondPass            | LCU (re-applied)     | only when LP injected; requires remount |

**boot.wim sequence** (no twice-apply needed):

| Sub-phase | Patches | Notes |
|---|---|---|
| B1.SSU              | SSU         | |
| B2.LanguagePack     | LP          | recovery UI language |
| B3.LCU              | LCU         | |
| B4.CleanupAndExport | (marker)    | |

**WinRE.wim sequence** (Safe OS DU replaces LCU per Microsoft):

| Sub-phase | Patches | Notes |
|---|---|---|
| W1.SSU              | SSU                  | (combined LCU acts as SSU surrogate) |
| W2.LanguagePack     | LP                   | recovery UI |
| W3.SafeOsDU         | DynamicUpdate.SafeOs | WinRE-only LCU substitute |
| W4.CleanupAndExport | (marker)             | Export /Compress:Recovery |

### Added - LCU twice-apply (I7.LCU.SecondPass)

Per Microsoft's documented rationale: when a language pack is
injected into install.wim, the LP can shadow files that the LCU
delivered on its first pass, leaving the LCU partially un-applied.
The fix is to re-apply the LCU AFTER the WIM has been
dismounted+committed+exported. The engine emits I7 only when
language packs are actually present in the plan; otherwise the
single-pass flow is preserved (no wasted remount).

The P07 worker honours the I7.RequiresRemount = $true flag by
dismounting after I1-I6, then re-mounting the now-serviced
install.wim for the I7 sub-phase, then dismounting again.

### Added - Full WinRE servicing worker

P08's WinRE block now reads the WinReSequence (W1.SSU -> W2.LP ->
W3.SafeOsDU -> W4.CleanupAndExport) from the cached PatchPlan and
applies each sub-phase against the WinRE.wim it extracted from
install.wim. The serviced WinRE is then copied back into the
install.wim mount so the surrounding install.wim dismount commits
the change. Skips the WinRE mount entirely when the sequence is
empty.

### Added - Invoke-PatchSubPhase common helper

A single helper drives the per-sub-phase apply loop for all three
sequences (Install / Boot / WinRE). It handles DryRun, missing
LocalPath, and Add-WindowsPackage failures uniformly, emits per-
patch result rows for the CSV inventory, and writes structured
error records via Add-ErrorJsonlEntry on failure.

### Added - Build-{Install,Boot,WinRe}ApplySequence builders

These three helpers (in .build_part09c_patchplan.ps1) bucket the
flat patch list per Type and emit the ordered sub-phase array. The
mapping logic (which Type belongs to which sub-phase, when to emit
I7, etc.) is centralised here so future tweaks (e.g. adding a new
SafeOS DU lane to install.wim) only touch one place.

### Changed - P07 / P08 worker control flow

Both phase workers now consume sub-phase sequences instead of a
flat patch list. The legacy `Get-PatchListForInstall|Boot|WinReWim`
helpers (introduced in r04) remain in place for backwards
compatibility with diagnostic consumers; the workers themselves
no longer iterate them. CSV inventory rows now include the new
`SubPhase` column.

P07's install.wim block iterates the install sequence in order;
when a sub-phase has RequiresRemount = $true it is deferred into
a second-pass buffer that runs after the first dismount completes.
This produces a 1-mount or 2-mount pattern depending on whether
language packs are present, matching the Microsoft sequence
exactly.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (7,112 lines).
- PSScriptAnalyzer 1.25.0: 0 findings.
- Sub-phase engine unit tests (5/5 PASS):
    * I7 NOT emitted when no LP in plan
    * I7 emitted with RequiresRemount=$true when LP present
    * boot.wim sequence: B1.SSU -> B2.LP -> B3.LCU -> B4.cleanup
    * WinRE sequence: W1.SSU -> W2.LP -> W3.SafeOsDU -> W4.cleanup (LCU is NOT in WinRE)
    * Empty input -> skeleton sub-phases all present, all empty
- Smoke 3 (Synthetic+DryRun): PatchPlan summary now shows all three
  sub-phase sequences end-to-end.

### Compatibility

- No schema change. PatchTargetMap and PatchDependencyPolicy from
  r04 are unchanged.
- The PatchPlan hashtable gains three new keys (InstallSequence,
  BootSequence, WinReSequence) but the legacy lane keys
  (Install / Boot / WinRE / Setup) are still present and still
  hold the flat sorted lists.
- `ScriptVersion` is bumped to `update-wsi-2026.05.24-r04.1`;
  `ScriptTag` is `lcu-twice-winre-and-lp-injection`.

### Out of scope (deferred to a future release)

- Setup binaries servicing via pending.xml (Setup DU).
- Per-language Optional Components for WinRE.

## [update-wsi-2026.05.24-r04] - 2026-05-24

### Added - WIM-target-aware patch plan engine

A new module (`.build_part09c_patchplan.ps1`) introduces the
`Build-PatchPlan` function that converts the flat
`$Script:ResolvedPatches` array into a target-aware plan with four
lanes:

| Target | Receives |
|--------|----------|
| Install | every patch whose Type maps to "Install" |
| Boot    | every patch whose Type maps to "Boot"    |
| WinRE   | every patch whose Type maps to "WinRE"   |
| Setup   | every patch whose Type maps to "Setup"   |

The mapping is centralised in the new `$Script:PatchTargetMap`
constant in `.build_part03_helpers.ps1`. Following Microsoft's
media-dynamic-update guidance:

| Patch Type              | Targets                  |
|-------------------------|--------------------------|
| SSU                     | Install + Boot + WinRE   |
| LCU                     | Install + Boot           |
| DotNet                  | Install                  |
| DynamicUpdate.Component | Install                  |
| DynamicUpdate.SafeOs    | WinRE                    |
| DynamicUpdate.Setup     | Setup                    |
| LanguagePack            | Install + WinRE          |
| LXP                     | Install                  |
| DotNet.LangPack         | Install                  |

Unknown Types fall back to `[Install]` with a one-time warning per
unique unknown Type.

P02 (`ResolveInputs`) now builds the plan and prints a per-target
summary at the end of the phase. P07 and P08 retain their legacy
`Get-PatchListForInstall|Boot|WinReWim` helpers; these now delegate
to the cached plan so existing call sites stay unchanged.

### Added - Pre-apply dependency closure check

A new helper, `Test-PatchDependencyClosureOnMount`, runs inside the
P07 install.wim and P08 boot.wim apply loops immediately after the
WIM mount and just before the first `Add-WindowsPackage` call. For
each patch whose `RequiresKbIds` is non-empty, it enumerates the
mounted image via `Get-WindowsPackage` and verifies that every
required KB is already present (`PackageIdentity` substring match
against the recorded KB ID).

The check is governed by `$Script:PatchDependencyPolicy`, default
`'Strict'`. Strict mode throws on the first unsatisfied
prerequisite, aborting the run before DISM emits the cryptic
0x800f0823 servicing-stack precondition error. The alternate
`'Warn'` mode logs a warning and continues; there is no CLI flag
yet, but the variable can be set from a wrapper script.

`-DryRun` short-circuits the check with a notice (no real mount to
enumerate against).

### Changed - Patch selection helpers delegate to PatchPlan

The legacy `Get-PatchListForInstallWim` / `Get-PatchListForBootWim`
helpers in `.build_part12_phase05_06_07.ps1` are now thin wrappers
that read from the cached `$Script:PatchPlan`. A new
`Get-PatchListForWinReWim` helper is added for completeness; the
WinRE worker itself is delivered in a follow-up release together
with the LCU twice-apply pattern and language-pack injection.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (6,700 lines).
- PSScriptAnalyzer 1.25.0: 0 findings.
- Unit tests for `Build-PatchPlan`:
    * Typical monthly patch set (SSU/LCU/.NET/SafeOS/Setup) routes
      to the expected lanes
    * LP/LXP correctly differentiated (LP -> Install+WinRE; LXP ->
      Install only)
    * Unknown Type falls back to Install with warning
    * Empty input handled gracefully
- All existing smoke tests still pass; Smoke 5 (live Catalogue
  scrape against Server2025 / 2026-05) resolves 3 patches and the
  combined-LCU detection still fires.

### Compatibility

- Schema v2.0 is unchanged. The new mapping lives in script code
  rather than in the Config files, so adding a new patch Type only
  requires editing `$Script:PatchTargetMap`.
- Existing PatchBaseline entries continue to work; the engine
  reads `.Type`, `.KbId`, `.ApplyOrder`, `.RequiresKbIds` and
  ignores everything else.
- `ScriptVersion` is bumped to `update-wsi-2026.05.24-r04`;
  `ScriptTag` is `wim-target-aware-patch-plan`.

### Out of scope (deferred to the next release in the r04 line)

- LCU twice-apply sequence in P07 around language-pack injection.
- WinRE.wim mount / service / dismount worker in P08.
- Language Pack injection on install.wim and WinRE.wim.

## [update-wsi-2026.05.24-r03.1] - 2026-05-24

### Added - Stage 4 CI workflow: monthly baseline refresh

A new GitHub Actions workflow,
`.github/workflows/scripts__powershell__update-windows-server-iso__stage4__monthly-refresh.yml`,
runs `-Action RefreshAllBaselines` on a schedule and opens an
automated pull request whenever the `Config/Server*.json` baselines
change. This completes the runtime story for r03's admin action:
baseline maintenance now happens without any human invocation.

Schedule: 02:00 UTC on the 15th of every month. Patch Tuesday is the
second Tuesday (8th-14th of the month); waiting until the 15th gives
Microsoft a 1-7 day window for late re-publications and Catalogue
indexing to settle.

Manual invocation: `workflow_dispatch` with four inputs:
- `mode`         : Monthly / Initial / Force (default: Monthly)
- `onlyOs`       : Server2016 / 2019 / 2022 / 2025 or blank for all
- `onlyLanguage` : en-us / ja-jp or blank for all
- `dryRun`       : true / false (default: false)

The workflow accepts the PowerShell exit code semantics established
in r03: 0 (clean) and 2 (some Manual fields remain) are treated as
success; 1 (orchestrator failure) and anything else fails the run.

PR contents:
- Title: `chore(uwsi): monthly baseline refresh (run #<id>)`
- Branch: `auto/uwsi-baseline-refresh-<id>` (deleted after merge)
- Files: only `scripts/powershell/update-windows-server-iso/Config/*.json`
- Labels: `automated`, `update-windows-server-iso`, `baseline-refresh`
- Body includes the run parameters, exit code, modified-file list,
  and a reviewer checklist for verifying combined-LCU flags and
  PatchTuesdayOfBaseline correctness.

Artefacts:
- `A01_RefreshAllBaselines_report.csv` (per-group decision matrix)
- `debugtrace.jsonl` (script-side trace)

both uploaded to the workflow run with 30-day retention.

A GitHub Actions step summary (`$env:GITHUB_STEP_SUMMARY`) is
always written, even on failure, so the maintainer can see at a
glance what happened without diving into logs.

### Notes

- The PowerShell script body itself is unchanged from r03; r03.1 is
  purely an operations release. `ScriptVersion` is bumped to
  `update-wsi-2026.05.24-r03.1` so workflow runs and PR commit
  messages identify the operations level distinctly from r03.
- `ScriptTag` is `stage4-monthly-refresh-ci`.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info.
- PSScriptAnalyzer 1.25.0: 0 findings.
- All existing smoke tests still pass.
- YAML syntax validated via PyYAML (8 steps).

### Compatibility

- Pure additive change: a new file under `.github/workflows/`. The
  three existing workflows (Stage 1 Linux / Stage 2 Windows / Stage 3
  synthetic-pipeline) are untouched.

### Out of scope (deferred to r04 onward)

Per the "未実装機能の全体マップ" review, the next deliverables are:
- r04: Microsoft-official servicing sequence compliance
  (WIM-target-aware patch plan; LCU twice-apply; pre-apply
   Get-WindowsPackage dependency closure check; WinRE servicing;
   per-WIM AppliesTo metadata; Language Pack injection in P07).
- r05: Supersedes-based superseded KB auto-removal; ISO-release
  refresher; Python JSON Schema validator.

## [update-wsi-2026.05.24-r03] - 2026-05-24

### BREAKING - Config Schema v2.0 (no migration path)

The Config/Server*.json data model has been redesigned with a 3-tier
hierarchy. There is NO migration sidecar; r02.x configs are rejected
by Get-ConfigProfile with a clear error message. Configs must be
either authored manually as v2.0 or generated by RefreshAllBaselines.

The new layout separates three concerns:
- `Common`           : OS-wide constants (build, edition, WIM index)
- `PatchBaseline`    : neutral patches (SSU/LCU/.NET CU/DU.*) shared
                       across all languages
- `LanguageSpecific` : per-language ISO source + LP / LXP / .NET LP

Adding a new language now requires only one node under
`LanguageSpecific` plus listing it in `Common.SupportedLanguages`.

Each field group carries a verification marker:
- `Common._VerifiedDate` / `Common._VerifiedBy`
- `PatchBaseline.LastVerifiedDate` / `LastVerifiedBy`
- `LanguageSpecific.<lang>.Iso._VerifiedDate` / `_VerifiedBy`
- `LanguageSpecific.<lang>.LanguageSpecificPatches.LastVerifiedDate`
   / `LastVerifiedBy` / `PatchTuesdayOfBaseline`

An empty `_VerifiedDate` flags the group as "unresolved" for the
RefreshAllBaselines decision matrix.

### Added - `Action.RefreshAllBaselines` (Admin phase A01)

```
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -DryRun
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -Mode Initial
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -Mode Force
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -OnlyOs Server2025
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -OnlyLanguage ja-jp
```

Three operating modes:

| Mode    | What gets refreshed |
|---------|---------------------|
| Initial | Every field group whose `_VerifiedDate` is empty |
| Monthly | Field groups whose Cadence is `PatchTuesday` AND whose recorded `PatchTuesdayOfBaseline` is older than the latest Patch Tuesday (default) |
| Force   | Every field group, regardless of verification state or cadence |

For each field group the decision is one of: `Skip` (verified and
current), `InitialFill` (auto-fill an empty group, requires
Refresher), `Monthly` (auto-refresh due to new Patch Tuesday), or
`Manual` (no Refresher available, group must be populated by hand).

A CSV report is emitted to
`<WorkRoot>/logs/A01_RefreshAllBaselines_report.csv` with the
per-group decision; the on-screen summary groups counts by decision
type. Exit codes: 0 (all OK), 1 (one or more Refresher calls failed),
2 (some fields require manual fill).

### Added - `Action.DumpFieldClassification` (Admin phase A02)

Emits `<WorkRoot>/logs/A02_FieldClassification.json` containing the
`$Script:OsConfigFieldGroups` constant, intended for downstream
Python tooling (a future JSON Schema validator). No Catalogue
network access is required.

### Added - Field classification constant

`$Script:OsConfigFieldGroups` is a top-level constant declared in
`.build_part03_helpers.ps1` that maps each logical field group to a
Cadence (Stable / PatchTuesday / IsoRelease) and an optional
Refresher function name. Adding a new field group is a one-line
addition followed by either implementing a new Refresher or leaving
it Manual.

### Added - Per-language patch scraper

New helper `Resolve-LanguageSpecificPatchesFromCatalog` queries
Microsoft Update Catalog for Language Pack, LXP, and .NET Framework
Language Pack matching `OsVersion` + `OsLanguage` + `PatchMonth`.
Best-effort: empty results are treated as "verified absence" rather
than failures, because Microsoft does not publish LP / LXP for every
OS x month combo. Reuses `Select-CanonicalPatchFile` from r02.5 for
file picking.

### Fixed - Stage 2 Smoke 3 (Synthetic+DryRun) failed at P05

`New-SyntheticTestIso` produces a structurally-degenerate ISO9660
image (4-byte placeholder boot files wrapped by oscdimg.exe) that
`Mount-DiskImage` in P05 rejects as "file or directory is corrupted".
Stage 3 (Synthetic+Execute) already bypassed P05 by going straight
to P07; this aligns Stage 2 Smoke 3 with that flow by removing
`P05` and `P06` from `PrepareBuildVerify` / `All` when
`$Script:SyntheticTestMode -eq $true`. No behaviour change for
non-synthetic runs.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (6,344 lines).
- PSScriptAnalyzer 1.25.0: 0 findings.
- Smoke 1 (`-Action ListPhases`): exit 0; A01 / A02 registered;
  Actions section lists `RefreshAllBaselines : A01` and
  `DumpFieldClassification : A02`.
- Smoke 2 (`-EnvironmentInfoOnly`): exit 0; P01 only.
- Smoke 3 (`-SyntheticTestMode -DryRun`): P01 SKIPPED -> P02 DONE ->
  P03 DONE (skip) -> P04 DONE (synthetic ISO) -> P07 ... (P05 /
  P06 are correctly absent from the phase list on Windows).
- Smoke 4 (`-Action DumpFieldClassification`): exit 0; JSON written.
- Smoke 5 (`-Action RefreshAllBaselines -DryRun -OnlyOs Server2025`):
  exit 2 (DryRun + unresolved Iso fields); all 4 field groups
  produce the expected decision (Common=Skip, PatchBaseline=Monthly,
  Iso=Manual x2, LangSpecificPatches=Monthly x2).
- Smoke 6 (`-Mode Force -OnlyLanguage ja-jp`): Force overrides Skip
  for verified Common (-> Manual); OnlyLanguage filters out en-us.
- Smoke 7 (`-Mode Initial`): same decisions as Monthly for this
  baseline (PatchTuesdayOfBaseline empty -> Monthly).

### Compatibility

- This is a destructive schema change. r02.x Configs will be
  rejected. Authoring new Configs by hand is supported; the easiest
  path is to start from a v2.0 Config in this repo and adjust the
  `Common.Build` / `LanguageSpecific.<lang>.Iso.Url` fields.
- `ScriptVersion` is `update-wsi-2026.05.24-r03`;
  `ScriptTag` is `schema-v2-and-refresh-all-baselines`.

### Out of scope (deferred to r04 Option Z)

- WIM-target-aware patch plan (install/boot/winre per-target patch
  lists per Microsoft media-dynamic-update sequence).
- LCU twice-apply pattern around language-pack injection.
- Pre-apply Get-WindowsPackage dependency closure check.

## [update-wsi-2026.05.24-r02.5] - 2026-05-24

### Fixed - Catalogue search precision + multi-file disambiguation (Option X)

r02 introduced Microsoft Update Catalogue scraping (P03) with three
quality issues that this release fixes. The fixes are based on
Microsoft's official media-dynamic-update guidance plus a review of
WIM Witch, WimWizard, and WIM-Tools reference implementations.

**Problem A - OS-version-aware Catalogue query templates.**
Previously, queries used a loose token like `"servicing stack update
Windows Server 2022"`. Microsoft's actual Catalogue Title pattern for
Server 2022 is `"... Servicing Stack Update for Microsoft server
operating system, version 21H2"` (with a literal comma) and requires
a `Product` / `Description` disambiguator to separate Setup-DU from
SafeOS-DU. The previous loose match could conflate multiple OS
versions in results. Replaced with `Get-CatalogQueryTemplate` which
returns the exact Title patterns documented in
https://learn.microsoft.com/windows/deployment/update/media-dynamic-update,
per OS version (2016 / 2019 / 2022 / 2025).

**Problem B - Combined LCU detection.**
Since 2021 Microsoft embeds the SSU into the LCU and publishes
standalone SSUs only "in rare cases of a breaking change"
(Microsoft Learn quote). The previous code's
`RequiresKbIds = $ssuKbs` assignment treated SSU as always-present
and could falsely report "missing SSU" in P06 validation. Added
`Test-IsCombinedLcuTitle` (explicit marker check) and a structural
detector inside `Resolve-PatchSetFromCatalog` that treats
"SSU search returned zero AND LCU search returned non-zero" as a
combined-LCU month. In combined months, the LCU entry is annotated
with `IsCombined=$true` and its `RequiresKbIds` is left empty.

**Problem C - Multi-file Catalogue selection.**
The previous code did `$primary = $links[0]`, which for .NET
Cumulative Updates and other multi-file packages was a coin toss
between Full, Express, and Delta variants. Picking Express / Delta
breaks `Add-WindowsPackage` because differential packages require a
base. Replaced with `Select-CanonicalPatchFile`, a scoring-based
picker that rejects `express`, `delta`, `psf`, and metadata text
files outright, and prefers `.msu > .cab`, matching architecture,
and (for .NET) matching `ndp<version>` markers.

### Added

- `Get-CatalogQueryTemplate` (~150 lines): OS-specific Catalogue
  Title templates + optional Product / Description filters.
- `Get-CatalogQueryUrl` (~30 lines): builds a Search.aspx URL with
  quoted Product / Description filter tokens.
- `Test-IsCombinedLcuTitle` (~15 lines): title-level combined marker.
- `Select-CanonicalPatchFile` (~80 lines): scoring-based file picker.
- LCU entries now carry an `IsCombined` boolean property in
  PatchBaseline; all patch entries carry a `Variant = 'Full'` string
  (placeholder for r03's `Variants[]` array).

### Changed

- `Resolve-PatchSetFromCatalog` reworked as a two-pass orchestrator:
  pass 1 runs all per-type Catalogue searches and records narrowed
  candidates; the combined-LCU detector runs on the aggregate; pass 2
  resolves the single canonical download file per surviving candidate
  via `Select-CanonicalPatchFile`. Eliminates `$primary = $links[0]`.
- Server 2019 / 2016 queries no longer include `DynamicUpdate.Setup`
  or `DynamicUpdate.SafeOs` (Microsoft does not publish those monthly
  for the older Server LTSC SKUs; they only appear during feature-
  update windows). `Test-PatchBaselineUsable` continues to accept
  partial sets so this is not a regression.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (5,611 lines).
- PSScriptAnalyzer 1.25.0: 0 findings.
- Unit tests for `Select-CanonicalPatchFile` and
  `Get-CatalogQueryTemplate` pass:
    * full + express -> selects full
    * delta only -> returns null
    * Server 2022 template contains comma form
    * .NET CU with ndp48 prefers the ndp48 variant

### Compatibility

- PatchBaseline schema remains at "1.0". The new `IsCombined` and
  `Variant` fields are added via `Add-Member -Force` so existing
  `Save-ConfigWithBaseline` rewrites them as ordinary JSON properties.
- Existing r02.4 Configs are read transparently; missing
  `IsCombined`/`Variant` fields default to `$false`/`'Full'` when
  consumed by P04/P06/P07.
- `ScriptVersion` is bumped to `update-wsi-2026.05.24-r02.5`;
  `ScriptTag` is `catalog-multifile-and-combined-lcu`.

### Out of scope (deferred to r03 Option Y / Z)

- WIM-target-aware patch plan (install/boot/winre per-target
  patch lists per Microsoft media-dynamic-update sequence).
- LCU twice-apply pattern around language-pack injection.
- Language Pack acquisition per `OsLanguage`.
- Pre-apply `Get-WindowsPackage` dependency closure check.

## [update-wsi-2026.05.24-r02.4] - 2026-05-24

### Fixed - `-EnvironmentInfoOnly` smoke test failed on Windows runner

The `-EnvironmentInfoOnly` switch is intended to be a CI-friendly
"dump PowerShell environment info and exit 0" smoke flag. It was
working in spirit (the Step 0 environment dump did print, with a
message `EnvironmentInfoOnly requested; exiting after env dump.`)
but it was NOT actually exiting the script. The reason: P01's check
issued a bare `return`, which only leaves the phase function. The
phase runner then proceeded to P02 (`ResolveInputs`), which throws
`-OsVersion is required for P02 (...)` because the smoke caller
deliberately omits `-OsVersion`. Stage 2 reported exit code 1.

This was a latent bug present since r01. It was hidden in early
Stage 2 runs because the run-level summary did not surface P02's
internal throw clearly; the recent Stage 2 logs in r02.3 made the
P02 failure visible, which is how it was caught.

Fix: add an `EnvironmentInfoOnly` early branch in the main entry
point that pins `$phaseList = @('P01')` before dispatching. P02+
are simply not in the dispatch list, so the post-P01 flow runs the
normal phase-summary tail and the script exits 0. The pre-existing
`return` inside `Invoke-SetupPhase01_Initialize` still works as a
graceful exit point for Step 0; nothing else in P01 fires.

This complements (rather than replaces) the existing
`Action -eq 'ListPhases'` and `Action -eq 'Cleanup'` early-exit
branches, matching the same idiom.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info.
- PSScriptAnalyzer 1.25.0: 0 findings at Severity Error / Warning /
  Information.

### Compatibility

- Surface behaviour change is localised to `-EnvironmentInfoOnly`:
  it now exits 0 cleanly after P01 instead of erroring out in P02.
  No other code path is affected.
- `ScriptVersion` bumped to `update-wsi-2026.05.24-r02.4`;
  `ScriptTag` is `environment-info-only-early-exit`.

## [update-wsi-2026.05.24-r02.3] - 2026-05-24

### Fixed - legacy error-helper cleanup (inherited from r01)

`Update-WindowsServerIso.ps1` carried three latent API signature
mismatches inherited from r01 that did not show up in the smoke tests
because they only surface on a failure path under specific conditions.
Fixing them now so the next genuine failure produces a readable error
message instead of a misleading "parameter not found" secondary error.

- `Add-ErrorJsonlEntry`: the function body was a verbatim copy from
  the SpeakerDeck downloader project that produced this script's
  scaffold. It took a single `-Item` parameter and serialised
  SpeakerDeck-specific fields (`DeckUrl`, `PublishDate`, etc.).
  Both call sites in this script
  (`Invoke-BuildPhase07_PatchInstallWim`'s `Add-WindowsPackage` catch,
  and `Invoke-PhaseRunner`'s top-level phase catch) instead pass
  `-Phase / -Kind / -Properties` for a generic phase-failure record.
  The two surfaces had been silently incompatible since r01.
  Rewrote `Add-ErrorJsonlEntry` to the actual contract the callers
  use: `-Phase <PNN> -Kind <label> -Properties <hashtable>`, merging
  the hashtable into a fixed-schema JSON object with reserved-key
  protection.
- `Enable-DebugTraceFileOutput`: the function declares `-Directory`
  but was called with `-LogsDir`. Fixed at the call site in the
  top-level script body.
- `Enable-AutoExportOnPhaseFailure`: declares `-OutputDirectory`
  but was called with `-DiagDir`. Fixed at the call site.

### Removed - SpeakerDeck-downloader dead code

The following functions were inherited verbatim from the SpeakerDeck
downloader scaffold and were never referenced by any ISO Updater code
path. Removed to eliminate confusion and reduce surface area:

- `Get-FailureCategory` (HTTP / IO / WebException categorisation
  tailored for SpeakerDeck failures).
- `Write-FailureDiagnostic` (per-deck plain-text dump under
  `$Script:FailedDir`, a variable that this script never sets).

A stale reference to `Write-FailureDiagnostic` in a comment inside
`.build_part04_debugtrace.ps1` was also cleaned up.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info.
- PSScriptAnalyzer 1.25.0: 0 findings at Severity Error / Warning /
  Information.
- Line count: 5,452 -> 5,310 (-142, all dead-code removal).
- All 11 `Start-DebugTrace` call sites use `-Context <fn> -PhaseId <PNN>`.
- All 2 `Add-ErrorJsonlEntry` call sites use `-Phase / -Kind / -Properties`.
- All `Enable-*` debug-trace setup calls use the correct parameter names.

### Compatibility

- Pure cleanup release: behaviour is identical for the successful
  pipeline (no `Add-ErrorJsonlEntry` calls occur on the happy path).
- The first observed change will be in the on-disk format of
  `<WorkRoot>/logs/<...>_errors.jsonl` when a phase actually fails:
  it now contains the intended `phase` / `kind` / caller-supplied
  diagnostic properties instead of the previous (never-reached)
  SpeakerDeck-shaped record.
- `ScriptVersion` bumped to `update-wsi-2026.05.24-r02.3`;
  `ScriptTag` is `legacy-error-helper-cleanup`.

## [update-wsi-2026.05.24-r02.2] - 2026-05-24

### Fixed — Stage 2 smoke-test failure introduced by r02

r02.1 cleared the PSScriptAnalyzer findings, but the Stage 2 job still
exited 1 because Smoke test 3 (`-Action PrepareBuildVerify
-SyntheticTestMode -DryRun -SkipEnvCheck`) hit a fatal error inside the
new phase P03. Root cause: when `Start-DebugTrace` was called from the
two new phase workers I introduced in r02, the wrong parameter name
`-PhaseName` was used. The correct name (used by every other phase in
this script) is `-Context`. PowerShell 5.1's partial-match logic
reported the failure as "A parameter cannot be found that matches
parameter name 'Phase'." because `-PhaseId` and `-PhaseName` collide
on the same prefix.

- `Invoke-SetupPhase03_RefreshPatchBaseline`:
  `Start-DebugTrace -PhaseName 'P02.5_RefreshPatchBaseline' -PhaseId 'P03'`
  becomes
  `Start-DebugTrace -Context 'Invoke-SetupPhase03_RefreshPatchBaseline' -PhaseId 'P03'`
  (mirrors the call shape used by P01 through P13).
- `Invoke-PlanPhase06_ValidatePatchSet`:
  `Start-DebugTrace -PhaseName 'P04.5_ValidatePatchSet' -PhaseId 'P06'`
  becomes
  `Start-DebugTrace -Context 'Invoke-PlanPhase06_ValidatePatchSet' -PhaseId 'P06'`.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (5,452 lines).
- PSScriptAnalyzer 1.25.0: 0 findings at Severity Error / Warning /
  Information.
- All 11 `Start-DebugTrace` call sites now use the canonical
  `-Context <function-name> -PhaseId <PNN>` shape.

### Compatibility

- Pure parameter-name fix in two new functions; no behavioural or
  schema change. r02.1 callers see no surface-level difference.
- `ScriptVersion` is bumped from `update-wsi-2026.05.24-r02.1` to
  `update-wsi-2026.05.24-r02.2`. The `r02.2` suffix communicates a
  second fix-up release of the r02 line.

## [update-wsi-2026.05.24-r02.1] - 2026-05-24

### Fixed — Stage 2 PSScriptAnalyzer (Windows PS 5.1) findings

r02 (`50fdb0f`) passed Stage 1 (Linux pwsh 7 + psa.py 0/0/0) but
failed Stage 2 (Windows PS 5.1 + microsoft/psscriptanalyzer-action)
on three rule categories that psa.py does not enforce. r02.1 addresses
all of them while keeping psa.py at 0/0/0.

- **`PSAvoidUsingBrokenHashAlgorithms`** (Severity = Error; the actual
  cause of the Stage 2 exit-code-1 failure) at `Test-PatchIntegrity`'s
  L2a/L2b SHA-1 checks. The function intentionally uses SHA-1 to
  sanity-check the SHA-1 hashes Microsoft Update Catalogue publishes
  alongside its patches, with SHA-256 (L2c) and Authenticode signatures
  (L3) as the real trust anchors. The previous `# psa-disable-line
  PSA5003 -- MS Catalog SHA-1` comments are a psa.py-specific
  suppression and do not affect the upstream `PSAvoidUsing*` rule.
  Replaced with a function-level
  `[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
       'PSAvoidUsingBrokenHashAlgorithms', '', Justification = '...')]`
  which is the canonical PSScriptAnalyzer suppression mechanism.
- **`PSUseDeclaredVarsMoreThanAssignments`** (Severity = Warning) at
  `Invoke-HyperVBootTest`'s `$vm = New-VM ...` assignment. The local
  `$vm` was never read again (subsequent operations use the VM name).
  Replaced with `New-VM ... | Out-Null` to match the surrounding
  Hyper-V calls' style.
- **`PSUseOutputTypeCorrectly`** (Severity = Information; x9 instances)
  at `Get-PhaseListByAction`'s nine `return @(...)` arms. PSSA
  cannot infer that an unannotated `@('a','b')` collection literal
  conforms to the declared `[OutputType([string[]])]`. Each `return`
  is now cast explicitly: `return [string[]]@('P01', 'P02', ...)`.

### Fixed — preventive (not yet observed on CI)

Local PSScriptAnalyzer 1.25.0 also surfaces one `PSReviewUnusedParameter`
warning (`$OsLanguage` declared but unused) inside
`Resolve-PatchSetFromCatalog`. CI's psscriptanalyzer-action@v1.1
appears to ship an earlier PSSA build that does not include this rule,
but to avoid future surprises the parameter is now used by an
informational `Write-Step` call at the head of the function.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (5,452 lines).
- PSScriptAnalyzer 1.25.0: 0 findings at Severity Error / Warning / Information.

### Compatibility

- Pure additive / mechanical changes: no behavioural difference from
  r02 at runtime.
- `ScriptVersion` is bumped from `update-wsi-2026.06.10-r02` to
  `update-wsi-2026.05.24-r02.1`; the `r02.1` suffix communicates a
  fix-up release of the r02 line.

## [update-wsi-2026.06.10-r02] - 2026-06-10

### Added — dynamic baseline (M2)

- New parameter `-PatchMonth yyyy-MM` to scope the Catalogue search
  (default: current month's Patch Tuesday).
- New parameter `-SkipDynamicPatchRefresh` to bypass P03 even when
  the baseline is stale (offline / air-gapped runs).
- New parameter `-UseBaselineOnly` to forbid all Catalogue access
  and use `PatchBaseline.Patches` strictly as-is.
- New phase **P03 RefreshPatchBaseline**: when
  `PatchTuesdayOfBaseline < Get-LatestPatchTuesday()`, scrape the
  Microsoft Update Catalogue for the target month (SSU + LCU +
  DynamicUpdate.Setup + DynamicUpdate.Component + DynamicUpdate.SafeOs
  + .NET CU), populate `PatchBaseline.Patches`, and write back to
  `Config/<OsKey>.json` atomically.
- Three scraper helpers (`Get-UpdateIdFromCatalog`,
  `Get-DownloadLinkFromCatalog`, `Get-SupersedenceFromCatalog`) that
  use `-UseBasicParsing` for Windows PowerShell 5.1 compatibility,
  set a polite User-Agent, and apply up to `ScrapeRetries` retries
  with jitter on transient HTTP failures.
- `Resolve-PatchSetFromCatalog` orchestrator that issues per-patch-type
  Catalogue queries, filters by OS title token + `x64` architecture,
  and auto-links each LCU's `RequiresKbIds` to the SSU(s) found in
  the same pass.
- Patch Tuesday calculator (`Get-PatchTuesdayForMonth`,
  `Get-LatestPatchTuesday`) with a 1-day buffer to avoid same-day
  edge cases (SPEC §D.15).

### Added — dependency validation (M3)

- New parameter `-WsusScnCabPath` to point at a pre-staged
  `wsusscn2.cab` instead of triggering an automatic download.
- New parameter `-IgnorePatchValidation` to demote P06 failure
  from abort to warning (NOT recommended for production).
- New phase **P06 ValidatePatchSet**: after the install.wim is
  extracted, optionally download (initial run OR cache older than
  current Patch Tuesday) and run a Windows Update Agent COM API
  offline scan with `Microsoft.Update.Session` against the supplied
  patch set. On any missing required patch: ABORT.
- Four diagnostic files emitted under `<WorkRoot>/diag/<timestamp>/`
  on validation failure:
    - `validation_summary.json` (top-level result + missing list)
    - `validation_detail.csv` (one row per patch with Provided / RequiredByWUA / DownloadHint)
    - `wsusscn2_scan_raw.json` (full raw WUA output)
    - `dependency_graph.json` (KB Requires / Supersedes adjacency)
- Diagnostic files are always emitted on detected-missing, regardless
  of `-IgnorePatchValidation`.

### Changed

- ScriptVersion: `update-wsi-2026.06.10-r02`,
  ScriptTag: `dynamic-baseline-and-wsusscn2-validation`.
- Banner unchanged: "Windows Server ISO Updater".
- P02 ResolveInputs: the patch-source resolution chain now also accepts
  "PatchBaseline-driven" when no explicit source (`-PatchUrls` /
  `-PatchDirectory` / `-ManifestPath`) is supplied AND
  `PatchBaseline.Patches` is non-empty (or `-AutoDetectLatestPatches`
  is set, in which case P03 will populate it).
- Phase registry: 11 entries (was 9). Action mappings updated to
  include P03 before P04 and P06 between P05 and P07.
- `Action GenerateManifest` now runs P01, P02, P03 (real Catalogue
  scrape that writes back to Config) instead of the r01 placeholder.

### Configuration

- `Config/Server201[6/9].json`, `Config/Server202[2/5].json` extended:
  - Added `PatchBaseline` node (Schema 1.0) with `TargetBuildAfterUpdate`,
    `PatchTuesdayOfBaseline`, `LastVerifiedDate`, `LastVerifiedBy`,
    `VerificationMethod`, `VerifiedOsLanguages`, `ChecksumAlgorithm`,
    `Patches`, `ExcludeKbList`, and `WsusScnCab`.
  - Added `AutoRefreshPolicy` node with `Mode`, `WritebackToConfig`,
    `FallbackOnScrapeFailure`, `ScrapeRetries`.
  - `AutoDetectKnownGood` marked deprecated (kept for r01 compatibility).
  - Server 2025 `ExcludeKbList` populated with KB5043080 (Checkpoint
    Cumulative Update; not required for OS install).

### Quality

- **psa.py**: 0 errors / 0 warnings / 0 info on the
  combined 5,447-line script (was 4,093 lines in r01).
- All r02 helpers have `[OutputType()]` declarations.
- All `r02`-anchored revision tags removed from script body comments
  (PSAP0003 / PSAP0005 compliant — revision history is here in the
  CHANGELOG, not in source comments).
- New `$matches` auto-variable usage in the Catalogue scraper replaced
  with explicit `[regex]::Match(...).Groups[N].Value` to satisfy
  PSA2002 (SPEC §D.17).

### Compatibility

- r01-format `Config/<OsKey>.json` files load unchanged (the `PatchBaseline`
  node is optional from the loader's perspective; if absent at load
  time, P03 will create it on first scrape).
- All r01 command lines (`-Action`, `-IsoPath`, `-PatchDirectory`,
  `-ManifestPath`, `-SyntheticTestMode -DryRun`, etc.) continue to
  work identically.

### Known limitations

- The Catalogue scraper depends on the current HTML structure of
  catalog.update.microsoft.com. A Microsoft-side change will break
  the scraper; the `AutoRefreshPolicy.FallbackOnScrapeFailure`
  setting controls the recovery behaviour.
- `Invoke-WuaOfflineScan` scans the local Windows host's installed
  image against the offline catalog; it is NOT a true WIM-level
  scan (SPEC §D.18). The validator's findings remain a strong signal
  for dependency completeness in practice.
- M5 (monthly Stage 4 catalog-health workflow) is not yet implemented.
- M4 (Server 2025 MUM/CAB LCU expand) is still a placeholder.

## [update-wsi-2026.05.24-r01] - 2026-05-24

### Added — script

- Initial MVP (M1 milestone) of `Update-WindowsServerIso.ps1`.
- 4,093-line single-file PowerShell script. UTF-8 with BOM, CRLF
  line endings, ASCII-only source bytes.
- Nine-phase pipeline (P01..P13) driven by a registry of
  `pscustomobject` entries and dispatched by `Invoke-PhaseRunner`.
- Sandbox-by-default semantics; destructive operations require
  `-Execute`.
- Synthetic test mode (`-SyntheticTestMode`) for CI: builds a tiny
  non-bootable ISO without downloading any Microsoft asset.
- Hyper-V Gen2 boot smoke test (`-Action BootTest`).
- Four OS configuration profiles under `Config/`:
  `Server2016.json`, `Server2019.json`, `Server2022.json`,
  `Server2025.json`. Per-language entries for en-us and ja-jp.
- Three-layer patch integrity check (filename SHA-1, content SHA-256,
  Authenticode signature) in `Test-PatchIntegrity`.
- DISM mount lifecycle hardened with OSDBuilder-style cleanup and
  10 s + 30 s retry in `Invoke-WimMountSafe` /
  `Invoke-WimDismountSafe` (see SPEC §D.1).
- `0x800f081e` and `0x800f0a13` suppression as Warning per
  documented heuristics in `Add-WindowsPackageWithRetry`
  (SPEC §D.8, §D.9).
- Three-tier boot file fallback chain (`etfsboot.com`, `efisys.bin`)
  in `Resolve-EtfsbootCom` / `Resolve-EfisysBin` (SPEC §D.4).
- Debug Trace Facility with JSONL output on failure, reused verbatim
  from the companion in-house script
  [`Download-SpeakerDeck.ps1`](../download-speakerdeck-oracle4engineer/Download-SpeakerDeck.ps1).

### Added — configuration files

- `.psa.config.json` — psa.py project configuration. Enables all
  PSAP00xx opt-in rules. Lists every Microsoft in-box cmdlet used by
  this script in `psa2010_known_cmdlets` so that the undefined-call
  rule stays silent.
- `PSScriptAnalyzerSettings.psd1` — PSScriptAnalyzer settings.
  Excludes `PSAvoidUsingWriteHost` (operator-facing UX uses the
  Write-Step / Write-Ok wrappers), `PSUseShouldProcessForStateChangingFunctions`
  (script is invoked via `.\` not as a module), and
  `PSUseCmdletBinding` (top-level CmdletBinding already in place).

### Added — documentation

- `README.md` — English primary user documentation, including
  required `## ⚠️ Disclaimer` and `## License` sections.
- `README.ja.md` — Japanese mirror of `README.md`.
- `SPEC.md` — authoritative developer / LLM specification.
  Inherits Part A from the
  [Download-SpeakerDeck SPEC](../download-speakerdeck-oracle4engineer/SPEC.md);
  Part B contains this script's unique contract (workspace layout,
  output naming, OS profile schema, per-phase contracts,
  action→phase mapping, ISO filename patterns, integrity check,
  synthetic mode); Part C is the quality-gate checklist;
  Part D is the catalogue of known pitfalls.
- `CHANGELOG.md` — this file.

### Added — CI workflows (at repo root `.github/workflows/`)

- `scripts__powershell__update-windows-server-iso__stage1__linux.yml`
  — Stage 1, Linux: `psa.py` + PSScriptAnalyzer in pwsh 7, BOM /
  CRLF / ASCII guard, Config JSON parse check.
- `scripts__powershell__update-windows-server-iso__stage2__windows.yml`
  — Stage 2, Windows: PSScriptAnalyzer in PS 5.1, parse-only check,
  read-only smoke modes (`ListPhases`, `EnvironmentInfoOnly`,
  `-SyntheticTestMode -DryRun`).
- `scripts__powershell__update-windows-server-iso__stage3__synthetic.yml`
  — Stage 3, Windows: ADK install (cached), full
  `-SyntheticTestMode` pipeline with `-Execute`. **No ISO artifact is
  ever uploaded**; only logs and diag are persisted as 14-day
  artifacts.

### Quality

- **psa.py**: 0 errors, 0 warnings, 0 info on
  `Update-WindowsServerIso.ps1`.
- All 13 advanced helper functions declare `[OutputType()]`.
- All top-level `param()` variables are accessed via `$Script:`
  from nested functions (PSA2001 compliance).
- No `Split-Path -LiteralPath ... -Parent` (PowerShell 5.1 ja-JP
  AmbiguousParameterSet workaround applied via
  `[System.IO.Path]::GetDirectoryName`).
- No `$args` shadowing (renamed to `$dismArgs` in
  `Invoke-DismCleanup`).
- All inline `# psa-disable-line` annotations carry an explicit
  justification.

### Compatibility

- Windows PowerShell 5.1: required base.
- PowerShell 7.x: also supported.
- Server 2016 / 2019 / 2022 / 2025: all supported.
- en-us and ja-jp ISOs: all supported.

### Known limitations

- `-AutoDetectLatestPatches` is a placeholder; populate Config
  `AutoDetectKnownGood` manually for now. Real implementation lands
  in M2.
- Server 2025 `LCUExpandViaMum=true` is configured but the actual
  expand-via-MUM code path is a future work item (M3).
- x86 and ARM64 are out of scope.
- BootTest requires a local Windows 11 host with Hyper-V; CI cannot
  exercise nested virtualisation.
- The Microsoft Update Catalogue scraper is local-only and not run
  in CI.
