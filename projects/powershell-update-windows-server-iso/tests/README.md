# Self-verification tools for `Update-WindowsServerIso.ps1`

This directory holds Python-based self-verification tools that exist
specifically to support **`Update-WindowsServerIso.ps1`**. They are
not generic test tools and are not part of the wider repository's
`quality-tools/` machinery - they belong with the PowerShell script
they verify and live in the same directory tree.

The tools exist because three of the bugs fixed in r04.3 (see
[`../CHANGELOG.md`](../CHANGELOG.md) and SPEC §D.19 / §D.20 / §D.21)
were caused by **silent Microsoft-side changes** that no static
analysis or pure unit test could have detected:

- Microsoft dropped a comma from Server 2022 update titles, so the
  TitleToken narrow filter started returning zero hits.
- Microsoft started attaching multiple `.msu` files to one .NET CU
  `UpdateId`, and the single-file picker silently dropped the
  second runtime.
- The `Get-PatchType` filename heuristic was always lossy; the
  Catalogue's authoritative Type bucket was being thrown away.

To catch the next variant of these classes of bug before they reach
production, this directory ships five tools, summarised below.

## Tool inventory

| Tool | What it does | When to run | Network? |
|---|---|---|:---:|
| `catalog_probe.py`        (T1) | Live Microsoft Update Catalog probe; asserts each known scrape pattern still yields > 0 hits, diffs against snapshot | Before / after editing any Catalogue-related helper; in CI monthly | Yes |
| `catalog_fixture_test.py` (T2) | Offline regression test against saved HTML fixtures under `fixtures/<patch-month>/`; deterministic | After every parser change; on every CI run | No  |
| `powershell_harness.py`   (T3) | Drives `Update-WindowsServerIso.ps1 -Action TestHarness` to unit-test PowerShell functions from Python | After every PS function change in the catalog / patch-selection layers | No  |
| `eval_iso_probe.py`       (T4) | HTTP Range-GET against each `data/config-Server<N>.json` Iso URL; reports size + Last-Modified | When the Microsoft Evaluation Center publishes a new snapshot; before release | Yes |
| `release_info_parser_test.py` (T6) | Offline regression test for the PowerShell `ConvertFrom-ReleaseInfoMarkdown` parser against the PoC fixture; asserts row counts and per-OS coverage | After every change to the release-info parser or its helpers; on every CI run | No  |
| `dotnet_cu_parser_test.py` (T7) | Offline regression test for `ConvertFrom-DotNetCuIndexMarkdown` and `ConvertFrom-DotNetCuMarkdown` against live-captured snapshots under `tests/snapshots/dotnet_cu/` (independent of the PoC fixtures); 16 assertions covering entry counts, date range, per-OS row counts, per-entry deep equality, typo handling, and OS-label mapping | After every change to the .NET CU parsers, the OS-label mapper, or the fetch/cache pipeline; on every CI run | No  |
| `canonical_json_test.py` (T11) | Offline byte-level parity test between `ConvertTo-CanonicalJson` / `Save-CanonicalJsonFile` (PowerShell, in `Update-WindowsServerIso.ps1`) and `canonical_json_dumps` / `save_canonical_json_file` (Python, in `tests/common/canonical_json.py`); 26 assertions covering primitives (12), collections (8), Unicode (3), real-world `data/*.json` shapes (2), and file-level save (1). Verifies the SPEC Part B.23 byte-level parity contract for `data/*.json` and `tests/fixtures/*.json` files. | After every change to `ConvertTo-CanonicalJson`, `Save-CanonicalJsonFile`, or `tests/common/canonical_json.py`; on every CI run | No  |
| `catalog_patchset_builder_test.py` (T27) | Offline b3 config-dataset builder: drives `ConvertTo-ConfigLines` through the TestHarness REPL against the committed layer-1 raw fixture (`fixtures/catalog_raw/resolve-2026-06.json`) to BUILD `PatchBaseline.Lines[]` without live Catalog I/O -- restores the pre-D2 offline construction path. 16 assertions: per-OS Kinds match the `PatchModel` allowed set, every Line carries a `Digest`, the uup-checkpoint OS builds a `SetupDU` Line at `ApplyOrder` 5. | After every change to `ConvertTo-ConfigLines`, the b3 transform, or the raw fixture; on every CI run | No  |
| `removed_live_wua_guard_test.py` (T20) | Offline static guard: the removed live-WUA functions/parameters stay absent and the P06 gate stays wired; 20 assertions | After every change to P06 or the WUA-adjacent surface | No |
| `config_required_ssu_downloadurl_test.py` (T23) | Offline data-contract guard on the committed configs: every `SSU` Line carries a non-empty `DownloadUrl`, `PatchModel` ⇔ SSU-line presence stays consistent per OS (since r11.52 a Kind `SSU` line implies `separate-ssu` ONLY -- the uup-checkpoint baseline is Kind `Checkpoint`), negative fixture (`fixtures/config-guard/`) rejected; 19 assertions | After every change to `data/config-Server*.json` | No |
| `dism_cleanup_args_test.py` (T24) | `Get-DismCleanupArgumentList` argument-vector unit test (ResetBase / ScratchDir variants); 6 assertions | After every change to the P07 cleanup path | No |
| `dism_export_args_test.py` (T25) | `Get-DismExportArgumentList` argument-vector unit test; 6 assertions | After every change to the P07 export path | No |
| `defender_exclusion_plan_test.py` (T26) | The three pure helpers behind `-UseDefenderExclusions` (managed set / plan / fail-closed decision); 13 assertions | After every change to the Defender-exclusion feature | No |
| `setup_du_forbid_test.py` (T28) | `Resolve-SetupDu` Forbid-branch guard for the non-uup-checkpoint OSes (2016/2019/2022); 12 assertions | After every change to the SetupDU resolver | No |
| `patch_integrity_digest_test.py` (T29) | Digest-format boundary: `ConvertTo-HexDigestString` base64↔hex vs an independent Python implementation, live-captured KB5095966 vector, static wiring guards; 11 assertions | After every change to the integrity layer | No |
| `setup_du_discriminator_test.py` (T30) | `Select-SetupDuCandidate` against verbatim live-Catalog rows (title discriminator; Products-filter resurrection guard); 8 assertions | After every change to the SetupDU discriminator | No |
| `lcu_target_verify_test.py` (T31) | `TargetBuildAfterUpdate` derived-field contract: per-OS evidence comparator (since r11.59: Server2016 KB-id/build fallback; RollupFix OSes by measured build, no-TBAU = INDETERMINATE Warn), committed-data consistency, single-writer wiring, P11 hard-Fail row; 26 assertions | After every change to the TBAU derivation, the comparator, or P11 | No |
| `checkpoint_placement_test.py` (T32) | Checkpoint placement + routing contract (r11.52 `checkpoint-model`): `Get-PatchLocalPath` lands LCU/Checkpoint in the `cu` discovery subfolder and every other Kind flat; `Build-PatchPlan` routes Kind=`Checkpoint` to NO WIM target (never applied standalone; DISM discovers checkpoints from the Add-WindowsPackage PackagePath folder per the MS checkpoint contract); `Test-PatchModelConsistency` requires Checkpoint / forbids SSU for `uup-checkpoint`; 11 assertions | After every change to the patch landing layout, `PatchTargetMap`, or the uup-checkpoint model rules | No |
| `bridge_lcu_contract_test.py` (T33) | Bridge-LCU contract (r11.53 `bridge-lcu`, axis-3 image-side servicing-stack floor): `ConvertTo-BridgeLcuResolvedPatch` shape (PatchType `BridgeLcu`, ApplyOrder 0, flat LocalPath outside `cu`, sha-1 from Digest); Install-only routing; `I0.BridgeLcu` FIRST in the install sequence; seed/config-Server2022 envelope identity + KB5030216 floor `20348.1960` + MS evidence URL + Digest/FileName SHA-1 cross-encoding; scope pin (no other OS carries a bridge); since r11.57 also Install+Boot routing and `B0.BridgeLcu`-first ordering (measured 0x800f0823 on the 2022 boot.wim); 19 assertions | After every change to the BridgeLcu envelope, `Build-InstallApplySequence`, `Build-BootApplySequence`, or the 2022 seed/config | No |
| `bootwim_policy_test.py` (T34) | BootWimLcuPolicy contract (r11.54 `bootwim-policy`): per-OS policy matrix in every config + seed (2016 enabled / 2019 disabled / 2022 tolerate / 2025 enabled) with the retired `EnableBootWimUpdate` absent; `Common.BootWimLcuPolicy` enum in both schemas; `Resolve-BootWimLcuPolicyValue` REPL behaviour (pass-through, case-fold, empty->disabled default, typed error on unknown); 16 assertions | After every change to the boot.wim policy model, the Common schema, or a per-OS policy value | No |
| `pca2023_default_auto_test.py` (T35) | PCA2023 default-auto parameter-surface contract (r11.55): retired `-EnablePca2023BootManager` token absent; `-SkipPca2023BootManager` + `-ForcePca2023OnServer2025` declared; P10 opt-out gate + Server 2025 force-gate present; script-scope default is falsy (P10 default-on); 7 assertions | After every change to the P10 gates or the PCA2023 parameter surface | No |
| `media_inspection_test.py` (T38) | Media-inspection engine contract (r11.59): `ConvertFrom-InspectionBuildValue` shape matrix; `Compare-MediaInspection` pure diff (build advance, package delta, 2024-4B prereq flip, boot `_EX` appearance, post-missing index, WIM SHA change); `Get-InspectionCrossChecks` observe-first matrix (disabled/enabled mismatches Warn; tolerate outcomes Info incl. flip-to-enabled evidence; bridge need confirmed vs redundant); structure pins (P06 pre / P11 SHA identity + post / P13 diff; the invalid `Get-WindowsPackage -ImagePath` path is gone); since r11.60 also the Catalog parent/child KB alias (`Get-KbAliasFromPatchPath` + the DotNet-only divergence audit over all four configs); 24 assertions | After every change to the inspection engine, the diff, the observe-first checks, or the Kb alias logic | No |
| `per_os_evidence_test.py` (T37) | Per-OS LCU evidence engine contract (r11.58): `ConvertTo-TwoPartBuild` normalisation; the four forked resolvers -- 2016 KB-named LCU (KbId + build), 2019/2022/2025 RollupFix-named (build only, KbId null), 2025 checkpoint highest-build-wins; MS-verified 2024-4B floor boundaries (14393.6897 / 17763.5696 / 20348.2402 / 26100.1); 3-source consensus (registry preferred; agreement needs >= 2 sources); dispatcher throws on unknown OsKey; 16 assertions | After every change to the evidence resolvers, their floors, or the dispatcher | No |
| `p08_plan_scope_test.py` (T36) | P08 plan-scope + WinRE has-work contract (r11.56): `Test-WimSequenceHasWork` null-hardening (null sequence / `@($null)` element -- the 2026-07-07 Server 2019 crash shape -- / cleanup-only / empty-Patches all False; real patch True); structure pins -- single `$plan = Get-OrInitPatchPlan` hoisted above the policy branch, has-work decision before the install.wim mount, inline crash-prone Where-Object gone; 10 assertions | After every change to P08's plan wiring or the WinRE section | No |
| `seed_contract_test.py` (seed contract gate) | `data/seed/seed-Server*.json` vs `schema/config-seed.schema.json` + structural seed rules; 17 assertions. No T number — gate convention. | After every change to seeds or the seed schema | No |
| `canonical_json_format_check.py` (canonical JSON format gate) | Re-serialises every `*.json` under `data/`, `tests/fixtures/`, `tests/snapshots/` and fails on byte divergence (24 files today); implements SPEC §C.3.4. No T number — format gate. | After every change that adds or modifies a JSON file in the scanned directories | No |
| `canonical_json_format_check.py` (Part C gate) | Offline format compliance check for every `*.json` file under `data/`, `tests/fixtures/`, and `tests/snapshots/`. Re-serialises each file through `canonical_json_dumps` and fails if the bytes diverge. Implements SPEC §C.3.4. | On every commit that adds or modifies a JSON file in the three scanned directories; on every CI run | No  |
| `config_schema_test.py` (config schema gate) | Offline schema-conformance check. A stdlib-only draft-07-subset validator that checks every `data/config-Server*.json` against `schema/config.schema.json` (Config Schema v3.0: requires `PatchBaseline.Lines`; the legacy `Patches` / `NeutralPatches` shapes are forbidden), with a targeted r10.4 regression guard against `Patches` reappearing. 14 assertions. No T number — schema gate, mirroring the format-gate convention. | On every commit that touches `data/config-Server*.json` or `schema/config.schema.json`; on every CI run | No  |
| `seed_contract_test.py` (seed contract gate) | Offline SEED/DERIVED-boundary gate (SPEC B.14.2). Mechanically coordinates the data pipeline with the schema: asserts every `schema/config.schema.json` field is classified as exactly one of SEED (admitted by `schema/config-seed.schema.json`) or DERIVED (a declared table grounded in what the refreshers generate), with no unclassified field, no overlap, and no seed-extra; checks the seed schema is a faithful projection (shared definitions byte-equal; `PatchBaselineSeed` = the `PatchBaseline` envelope); and validates every `data/seed/seed-Server*.json` against the seed schema (reusing the `config_schema_test` validator). 17 assertions. No T number — schema gate. Guards against a config-schema field being silently dropped from the seed. | On every commit that touches `schema/config*.json` or `data/seed/`; on every CI run | No  |

## Quick start

```bash
# Offline tests - safe to run anywhere
cd tests/
python3 catalog_fixture_test.py            # T2: 13 assertions on saved HTML
python3 powershell_harness.py              # T3: 7 PS function-level assertions
python3 canonical_json_test.py             # T11: 26 PS/Python byte-level parity assertions
python3 removed_live_wua_guard_test.py     # T20: 20 removed-live-WUA static-guard assertions

# ...or run the whole offline suite (every *_test.py is offline-deterministic):
for t in *_test.py canonical_json_format_check.py; do python3 "$t" || break; done
python3 canonical_json_format_check.py     # Part C: every JSON file in canonical format
python3 config_schema_test.py              # config schema gate: data/config-Server*.json vs v2.1 schema
python3 seed_contract_test.py              # seed contract gate: SEED/DERIVED boundary coordinated with the schema

# Live tests - require network access to Microsoft endpoints
python3 catalog_probe.py --check all       # T1: hits live Catalog (~7 checks)
python3 catalog_probe.py --snapshot        # T1: saves snapshots/last_probe.json
python3 eval_iso_probe.py                  # T4: hits 4 OS Iso CDN URLs
```

## What Claude (or a human operator) should do, when

### "I want to change a parser regex in `Update-WindowsServerIso.ps1`"

1. Run `python3 catalog_fixture_test.py` first - confirm the existing
   fixtures still parse 100% with the current code (baseline).
2. Edit the regex (in `common/html_parsers.py` AND in the matching PS
   function - they are intentionally duplicated for redundancy).
3. Re-run `python3 catalog_fixture_test.py` - assert nothing broke.
4. Run `python3 catalog_probe.py --check all` - confirm the new
   regex still works against live Microsoft HTML.
5. If steps 3 and 4 both pass, the change is safe.

### "I want to verify the Server 2025 evaluation ISO is still hosted"

```bash
python3 eval_iso_probe.py --os Server2025
```

The probe reports each URL's HTTP status, total size in MB, and
`Last-Modified`. If the size drops dramatically (~< 100 MB), the CDN
likely de-listed the snapshot and `data/config-Server2025.json#/.../Iso/Url`
needs to be refreshed by hand against the Microsoft Evaluation Center
[https://www.microsoft.com/evalcenter/](https://www.microsoft.com/evalcenter/).

### "I want to verify Microsoft has not changed Catalogue HTML structure
this month"

```bash
python3 catalog_probe.py --check all --patch-month 2026-05 --snapshot
```

The probe writes `snapshots/last_probe.json`. Compare with the prior
snapshot in `git diff` to see what changed. If meaningful drift is
reported, follow SPEC §D.19 / §D.20 to update the affected
PS function.

### "I am writing a brand-new Catalogue-related helper and want to test
it from Python"

1. Add the function to `Update-WindowsServerIso.ps1`.
2. Run `python3 -c "from common.ps_invoke import PSSession;
   with PSSession('../Update-WindowsServerIso.ps1') as ps: print(ps.invoke('YourNewFunction', YourArg='value'))"`
   for a manual smoke test.
3. Add a `test_*` function in `powershell_harness.py` for permanent coverage.

## Refreshing fixtures (`fixtures/<patch-month>/`)

Fixtures are snapshots of the live Microsoft Update Catalog HTML at a
specific point in time. They are checked into Git so the offline
regression test (T2) is deterministic. To refresh them for a new
patch month:

```bash
# 1. Run T1 with the new month to confirm Catalog is queryable
python3 catalog_probe.py --check all --patch-month 2026-06

# 2. Re-collect fixtures with the bundled helper (see fixtures/README.md)
#    The collector hits Search.aspx for each OS / Type combination
#    and writes one .html file per query + an expected.json with the
#    parsed results that T2 will then assert against.
```

The `fixtures/2026-05/` set was generated this way during r04.4
implementation and serves as both the regression baseline AND the
documented "this is what 2026-05 Catalogue listings looked like"
historical record.

## Dependency policy

These tools use **only the Python standard library**. No
`pip install` is required - they run on every system that has
Python 3.10 or newer. This matches the dependency policy of
[`../../python/powershell-static-analyzer/psa.py`](../../python/powershell-static-analyzer/psa.py),
which sets the precedent for "standard-library-only Python tooling
in this repository".

PowerShell-side: the tools require either `pwsh` (PowerShell 7+) or
Windows `powershell`. `pwsh` is preferred and the only one tested
on Linux; `powershell` (Windows 5.1) works on Windows hosts.

## File layout

```
tests/
  README.md                  this file
  catalog_probe.py           T1  (live Catalog probe)
  catalog_fixture_test.py    T2  (offline HTML fixture regression, 13)
  powershell_harness.py      T3  (PS function unit tests via TestHarness, 7)
  eval_iso_probe.py          T4  (live ISO endpoint Range-GET probe)
  release_info_parser_test.py            T6  (release-info parser, 13)
  dotnet_cu_parser_test.py               T7  (.NET CU parsers, 16)
  canonical_json_test.py                 T11 (PS/Python canonical-JSON parity, 26)
  removed_live_wua_guard_test.py         T20 (removed-live-WUA static guard, 20)
  config_required_ssu_downloadurl_test.py T23 (config SSU data contract, 19)
  dism_cleanup_args_test.py              T24 (DISM cleanup argument vector, 6)
  dism_export_args_test.py               T25 (DISM export argument vector, 6)
  defender_exclusion_plan_test.py        T26 (Defender-exclusion pure helpers, 13)
  catalog_patchset_builder_test.py       T27 (offline b3 dataset builder incl. SetupDU @ ApplyOrder 5 + starvation hard-fail, 16)
  setup_du_forbid_test.py                T28 (SetupDU Forbid-branch guard, 12)
  patch_integrity_digest_test.py         T29 (digest-format boundary, 11)
  setup_du_discriminator_test.py         T30 (SetupDU title discriminator, 8)
  lcu_target_verify_test.py              T31 (TargetBuildAfterUpdate contract, 26)
  checkpoint_placement_test.py           T32 (Checkpoint placement + routing, 11)
  bridge_lcu_contract_test.py            T33 (Bridge-LCU contract, 19)
  bootwim_policy_test.py                 T34 (BootWimLcuPolicy contract, 16)
  pca2023_default_auto_test.py           T35 (PCA2023 default-auto surface, 7)
  p08_plan_scope_test.py                 T36 (P08 plan-scope + WinRE has-work, 10)
  per_os_evidence_test.py                T37 (per-OS LCU evidence engine, 16)
  media_inspection_test.py               T38 (media-inspection engine, 24)
  config_schema_test.py                  config schema gate (14)
  seed_contract_test.py                  seed contract gate (17)
  canonical_json_format_check.py         canonical JSON format gate (24 files)
  common/
    __init__.py              package marker
    catalog_client.py        urllib HTTP fetcher with retry-jitter
    html_parsers.py          Catalog HTML regex extractors (mirror of PS)
    ps_invoke.py             PSSession context manager for TestHarness REPL
    snapshot.py              JSON snapshot read/write + diff
    canonical_json.py        Python reference for SPEC Part B.23 canonical JSON (used by T11)
  fixtures/
    2026-05/
      server2016_lcu_search.html
      server2019_lcu_search.html
      server2019_dotnet_search.html  # umbrella .NET CU regression input
      server2022_lcu_search.html     # comma-less title regression input
      server2025_lcu_search.html
      sample_scopedview.html         # supersedence parse input
      expected.json                  # parsed expectations for T2
    config-guard/
      bad-config-ssu-empty-url.json  # Type=SSU with empty DownloadUrl: the T23 negative fixture
    catalog_raw/
      resolve-2026-06.json           # captured layer-1 { os; lines[] } incl. a SetupDU line: T27 offline-build input.
                                     # Catalog-truth fields (files/urls/digests/titles) VERBATIM from the 2026-07-02
                                     # live capture; the 2025 anchor's INTERNAL kind label was mechanically migrated
                                     # SSU->Checkpoint with the r11.52 checkpoint-model (a resolver-owned label, not
                                     # external truth -- no captured Catalog byte was altered)
    dotnet_cu/                       # .NET CU parser fixtures (T7 adjunct)
    release_info/                    # release-info parser fixture (T6)
  snapshots/
    .gitkeep
    last_probe.json          (written by T1 --snapshot)
    dotnet_cu/               live-captured .NET CU snapshots (T7 input)
    release_info/            live-captured release-info snapshot
```

## How these tools relate to CI

CI Stage 1 currently runs the BOM/CRLF/ASCII format check, the
config schema gate, psa.py (text + SARIF) and PSScriptAnalyzer; the
rest of the offline suite (every `*_test.py` here, all
offline-deterministic and stdlib-only) is run as the local gate
battery on every change and is a natural candidate for a future
Stage 1 extension. T1 and T4 are live probes and belong to the
monthly workflow (`stage4__monthly-refresh.yml`), where they catch
Microsoft-side drift early.

## Retired r06 Phase 2 PoC (r07.0)

Earlier releases hosted a `poc_<topic>_<step>_<verb>.py` family
here that drove the Phase 2 investigation behind the §B.23
architecture. As of r07.0 those scripts have been retired: their
parser / resolver logic was promoted into
`Update-WindowsServerIso.ps1` (`ConvertFrom-ReleaseInfoMarkdown`,
`ConvertFrom-DotNetCuMarkdown`; the release-info discovery/resolver
pair was later removed in the data-source migration), regression
coverage moved to T6/T7 above, and the historical reports were moved to
`docs/history/`. The `poc_<topic>_*` naming convention itself is
preserved in SPEC.md §B.22.2 as a reserved pattern for any future
PoC investigation.

