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

### Planned (M4)
- Server 2025 real `LCUExpandViaMum=true` code path. LCU on 2025 ships
  as a MUM/CAB bundle that must be expanded with `expand.exe -F:*`
  before `Add-WindowsPackage` is invoked.

### Planned (M5)
- Stage 4 CI workflow (`catalog-health`): monthly scheduled run of
  `Resolve-PatchSetFromCatalog` that opens a PR with the resulting
  `Config/<OsKey>.json` diff for human review. Catches Microsoft
  Update Catalogue HTML structure changes within 30 days.

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

The P05 worker honours the I7.RequiresRemount = $true flag by
dismounting after I1-I6, then re-mounting the now-serviced
install.wim for the I7 sub-phase, then dismounting again.

### Added - Full WinRE servicing worker

P06's WinRE block now reads the WinReSequence (W1.SSU -> W2.LP ->
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

### Changed - P05 / P06 worker control flow

Both phase workers now consume sub-phase sequences instead of a
flat patch list. The legacy `Get-PatchListForInstall|Boot|WinReWim`
helpers (introduced in r04) remain in place for backwards
compatibility with diagnostic consumers; the workers themselves
no longer iterate them. CSV inventory rows now include the new
`SubPhase` column.

P05's install.wim block iterates the install sequence in order;
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
summary at the end of the phase. P05 and P06 retain their legacy
`Get-PatchListForInstall|Boot|WinReWim` helpers; these now delegate
to the cached plan so existing call sites stay unchanged.

### Added - Pre-apply dependency closure check

A new helper, `Test-PatchDependencyClosureOnMount`, runs inside the
P05 install.wim and P06 boot.wim apply loops immediately after the
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

- LCU twice-apply sequence in P05 around language-pack injection.
- WinRE.wim mount / service / dismount worker in P06.
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
   per-WIM AppliesTo metadata; Language Pack injection in P05).
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

### Fixed - Stage 2 Smoke 3 (Synthetic+DryRun) failed at P04

`New-SyntheticTestIso` produces a structurally-degenerate ISO9660
image (4-byte placeholder boot files wrapped by oscdimg.exe) that
`Mount-DiskImage` in P04 rejects as "file or directory is corrupted".
Stage 3 (Synthetic+Execute) already bypassed P04 by going straight
to P05; this aligns Stage 2 Smoke 3 with that flow by removing
`P04` and `P04.5` from `PrepareBuildVerify` / `All` when
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
  P02.5 DONE (skip) -> P03 DONE (synthetic ISO) -> P05 ... (P04 /
  P04.5 are correctly absent from the phase list on Windows).
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

r02 introduced Microsoft Update Catalogue scraping (P02.5) with three
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
and could falsely report "missing SSU" in P04.5 validation. Added
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
  consumed by P03/P04.5/P05.
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
  (`Invoke-BuildPhase05_PatchInstallWim`'s `Add-WindowsPackage` catch,
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
new phase P02.5. Root cause: when `Start-DebugTrace` was called from the
two new phase workers I introduced in r02, the wrong parameter name
`-PhaseName` was used. The correct name (used by every other phase in
this script) is `-Context`. PowerShell 5.1's partial-match logic
reported the failure as "A parameter cannot be found that matches
parameter name 'Phase'." because `-PhaseId` and `-PhaseName` collide
on the same prefix.

- `Invoke-SetupPhase02_5_RefreshPatchBaseline`:
  `Start-DebugTrace -PhaseName 'P02.5_RefreshPatchBaseline' -PhaseId 'P02.5'`
  becomes
  `Start-DebugTrace -Context 'Invoke-SetupPhase02_5_RefreshPatchBaseline' -PhaseId 'P02.5'`
  (mirrors the call shape used by P01 through P09).
- `Invoke-PlanPhase04_5_ValidatePatchSet`:
  `Start-DebugTrace -PhaseName 'P04.5_ValidatePatchSet' -PhaseId 'P04.5'`
  becomes
  `Start-DebugTrace -Context 'Invoke-PlanPhase04_5_ValidatePatchSet' -PhaseId 'P04.5'`.

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
- New parameter `-SkipDynamicPatchRefresh` to bypass P02.5 even when
  the baseline is stale (offline / air-gapped runs).
- New parameter `-UseBaselineOnly` to forbid all Catalogue access
  and use `PatchBaseline.Patches` strictly as-is.
- New phase **P02.5 RefreshPatchBaseline**: when
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
- New parameter `-IgnorePatchValidation` to demote P04.5 failure
  from abort to warning (NOT recommended for production).
- New phase **P04.5 ValidatePatchSet**: after the install.wim is
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
  is set, in which case P02.5 will populate it).
- Phase registry: 11 entries (was 9). Action mappings updated to
  include P02.5 before P03 and P04.5 between P04 and P05.
- `Action GenerateManifest` now runs P01, P02, P02.5 (real Catalogue
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
  time, P02.5 will create it on first scrape).
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
- Nine-phase pipeline (P01..P09) driven by a registry of
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
