---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.0.0
  rendered: 2026-08-07
---
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
production, this directory ships the repository-native offline and
targeted regression suite summarised below (see TESTING.md §0 for
the authoritative per-contract inventory).

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
| `removed_live_wua_guard_test.py` (T20) | Offline static guard: the removed live-WUA functions/parameters stay absent and the P06 gate stays wired; 20 assertions | After every change to P06 or the WUA-adjacent surface | No |
| `dism_cleanup_args_test.py` (T24) | `Get-DismCleanupArgumentList` argument-vector unit test (ResetBase / ScratchDir variants); 6 assertions | After every change to the P07 cleanup path | No |
| `dism_export_args_test.py` (T25) | `Get-DismExportArgumentList` argument-vector unit test; 6 assertions | After every change to the P07 export path | No |
| `defender_exclusion_plan_test.py` (T26) | The three pure helpers behind `-UseDefenderExclusions` (managed set / plan / fail-closed decision); 13 assertions | After every change to the Defender-exclusion feature | No |
| `patch_integrity_digest_test.py` (T29) | Digest-format boundary: `ConvertTo-HexDigestString` base64↔hex vs an independent Python implementation, live-captured KB5095966 vector; since r12.00 the wiring guard pins the single accessor `Get-BaselineHashValue` (canonical `Integrity.<Alg>.Value` node + retained-legacy flat `Digest`/`Sha256` path; no direct field seeding may resurface -- the data-side declaration is T43); 14 assertions | After every change to the integrity layer | No |
| `setup_du_discriminator_test.py` (T30) | **RETIRED 2026-08-08** at the consolidation fold (user adjudication); record in SPEC §B.15.4; successors T46 + T50 | — | — |
| `checkpoint_placement_test.py` (T32) | Checkpoint placement + routing contract: `Get-PatchLocalPath` lands LCU/Checkpoint in the `cu` discovery subfolder and every other Kind flat; `Build-PatchPlan` routes Kind=`Checkpoint` to NO WIM target (never applied standalone; DISM discovers checkpoints from the Add-WindowsPackage PackagePath folder per the MS checkpoint contract); since r12.00 the `PatchModel` Forbid axis is retired (SPEC B.15.4) -- the test guards its ABSENCE and pins the State-driven integrity rule (`Frozen`+ needs SHA-256; `LegacyResolved` needs an integrity key); 15 assertions | After every change to the patch landing layout, `PatchTargetMap`, or the consistency rules | No |
| `pca2023_default_auto_test.py` (T35) | PCA2023 default-auto parameter-surface contract: retired `-EnablePca2023BootManager` token absent; `-SkipPca2023BootManager` + `-ForcePca2023OnServer2025` declared; P10 opt-out gate present; script-scope default is falsy (P10 default-on); since the r12.57 default-enable reshape the Server 2025 force-gate is gone by design and the force switch survives only as a deprecated compatibility slot with a wired caution (pin revised T39-style at that merge); 9 assertions | After every change to the P10 gates or the PCA2023 parameter surface | Yes (pwsh REPL) |
| `media_inspection_test.py` (T38) | Media-inspection engine contract (r11.59): `ConvertFrom-InspectionBuildValue` shape matrix; `Compare-MediaInspection` pure diff (build advance, package delta, 2024-4B prereq flip, boot `_EX` appearance, post-missing index, WIM SHA change); `Get-InspectionCrossChecks` observe-first matrix (disabled/enabled mismatches Warn; tolerate outcomes Info incl. flip-to-enabled evidence; bridge need confirmed vs redundant); structure pins (P06 pre / P11 SHA identity + post / P13 diff; the invalid `Get-WindowsPackage -ImagePath` path is gone); since r11.60 also the Catalog parent/child KB alias (`Get-KbAliasFromPatchPath` + the DotNet-only divergence audit over all four configs); since r11.61 the `_EX` census runs on BOTH kinds (install.wim = the fallback conversion source when boot.wim is unserviceable) with diff appearance on both slots and the readiness-inventory wiring pin; since r11.62 the conversion source fallback pins (boot.wim primary, install.wim fallback, `SourceWim` recorded); since r11.64 the skip-aware output-check pins; since r11.65 per-Kind verification (`Get-DotNetRollupEvidence` census incl. the `_481` suffix shape, `KindVerificationScope` row, Kb_ rows behind the Server2016 guard only, alias extractor fully removed); 31 assertions | After every change to the inspection engine, the diff, the observe-first checks, or the Kb alias logic | No |
| `boot_verification_tools_test.py` (T39) | boot-verification tool-set contract: every tool `.ps1` parses clean; pure-function REPL matrix (`Convert-Rgb565ToBmpByte` deterministic BMP incl. bottom-up rows, `ConvertFrom-EfiSignatureList` synthetic list + garbage degradation, subject presence, adjudicated cell map T1-T12, ledger semantics incl. unknown-cell throw); autounattend template well-formed + tokens + explicit disk-0 wipe; structure pins (MicrosoftWindows template everywhere, `State=Running` documented as a non-verdict, README T9-first rule + KB5025885 values); 17 assertions | After every change to tools/boot-verification or the BootTest action | No |
| `setup_binaries_sync_test.py` (T40) | Setup-binary sync contract (P08S + P11): plan build gates (setuphost.exe joins at 26100+ only; unknown build degrades to setup.exe with a stated reason; since r12.72 sync plans carry setup.exe + setuphost.exe when present, build-independent), `Get-SetupBinaryFileEvidence` exact size/SHA-256/ISO-8601-UTC measurement + missing-path shape, closed record vocabulary, and structure pins -- SHA-verified copy (hard fail), ReadOnly clearing, CSV/JSON evidence artifacts, console before/after lines, boot.wim-side stash + P09 post-overlay reapply, P11 `SetupBinarySync_*` Fail grading, the ScriptVersion release pin, and the option-B P08S wiring guard: a structural invariant (every quoted phase-ID list of three or more elements containing both P08 and P09 must wire P08S strictly between them) plus per-site pins naming the five known pipeline lists, replacing the fragile global token-count proxy; 21 assertions | After every change to P08S, the Setup-binary plan/evidence helpers, the P09 overlay, the P11 SetupBinarySync rows, or any pipeline phase list | Yes (pwsh REPL) |
| `apply_plan_conformance_test.py` (T41) | Declaration-derived (r12.00): the config's `ServicingModel.ApplyPlans` is well-formed and every `Lines[]` entry conforms to it -- roles resolve to declared plan steps, `TargetsByRole` stays within the plan's targets, ordering follows the declared sequence; expected values are read from the config under test, never hardcoded. Supersedes T27 / T32-routing / T33-ordering; 143 assertions at r12.00 | After every change to `data/config-Server*.json` or the apply-plan model | No |
| `servicing_model_declaration_test.py` (T42) | Declaration-derived (r12.00): `PatchBaseline.SourcePrerequisites[]` shape + `Condition.Mode` discriminators, `Common.BootWimUpdateModel`, and the `ValidationPolicy` flag set are declared consistently across configs. Supersedes T31 / T34 / T37 / T33-envelope; 30 assertions at r12.00 (grows with the declaration, e.g. r12.37) | After every change to the declared servicing model | No |
| `line_integrity_declaration_test.py` (T43) | Declaration-derived (r12.00): every `Lines[]` entry carries `Integrity` with valid algorithm nodes, `Roles` are declared, and an SSU-role asset is resolvable either by its own `DownloadUrl` or through `ParentKbId`. Supersedes T23 / T29-wiring; 158 assertions at r12.00 (tracks the baseline Line count) | After every change to `data/config-Server*.json` | No |
| `compatibility_declaration_test.py` (T44) | Declaration-derived meta-contract (r12.00): `Compatibility.LegacyFieldsRetained` / `.CanonicalV4Fields` are present, disjoint and truthful -- retained fields exist, canonical successors exist, and no test may assert a retained field as the model (the mechanical detector for the superseded-model failure pattern); 64 assertions | After every change to the `Compatibility` block or the migration map | No |
| `servicing_contract_baseline_test.py` (T45) | Declaration-derived series instrument: validates `data/servicing-contract-baselines.json` (per-OS contract revisions + SHA-256 pins), plus the campaign extension's script-computed component-hash cross-check -- the canonical-JSON contract constructors are extracted from the script's own AST under the pinned pwsh and each of the eight component digests per OS must equal the declared baseline value. The anchor file exists on the branch since the r12.44 merge (the NOT-YET path is dormant); the extension section requires pwsh, the declaration-shape sections remain pure Python; 26 assertions | After every change to `data/servicing-contract-baselines.json` or the servicing-contract definitions in the script; on every CI run | Yes (pwsh, extension section) |
| `discovery_policy_declaration_test.py` (T46) | Declaration-derived (r12.00): `DiscoveryPolicy.CatalogAliases` + per-Kind `SearchProfiles` are well-formed and internally consistent (query strategies, title accept/reject constraints, classification requirements). Supersedes T28; the T30 supersession disposition is a consolidation-stream adjudication; 112 assertions | After every change to `DiscoveryPolicy` | No |
| `collector_artifact_test.py` (T47) | The Collector's identity and artifact contract (test re-implementation campaign, phase A): supported deliverable filename present and the retired project-context filename absent; the exact CollectorVersion/SchemaVersion pair pinned (advanced deliberately per Collector release); project-neutral evidence contract (error schema, artifact prefix, OS-tokenized naming); pre-r9 retirement guards with cross-version baseline comparison disabled; collection posture (ESP/MSInfo32 default-on, C:\Temp output contract, mountvol-based read-only ESP access, the eight-function evidence inventory); the no-network invariant; and a Collector parse gate extending the battery beyond the main script; 29 assertions | After every change to `Collect-WindowsServerPostInstallEvidence.ps1` | Yes (pwsh, parse gate) |
| `collector_semantics_test.py` (T48) | The Collector's behavioral contract over the r10-r12 hardening arc, exercised via AST-extracted functions against fixtures carrying measured four-OS post-install facts: PFRO Advisory/Blocking classification with CBS / Windows Update overrides; Secure Boot event-field parsing; the restart-preflight decision matrix (fail-closed on Advisory/Blocking/Unknown startup states; boot history corroborates but never decides); and the r12 Secure Boot evidence semantics (WinCS parsing, `UEFICA2023Status` as the status authority, stale-1808 rejection, the measured 2019 monitoring divergence held conservative); 42 assertions | After every change to the Collector's classification, preflight, or Secure Boot evidence functions | Yes (pwsh) |
| `oscdimg_reference_test.py` (T49) | Protection for the declared tool-reference file adopted at r12.63. D-half over `data/tool-references/oscdimg-reference.json`: internal coherence and formats only -- the declared file stays the value authority, concrete values are deliberately not duplicated into the test. B-half: host non-modification of the legacy ADK fallback, qualification-required wiring for `New-BootableIso`, resolver-failure evidence preservation, and the Microsoft-script reference parser exercised behaviorally on a synthetic fixture; 44 assertions | After every change to `data/tool-references/oscdimg-reference.json`, the oscdimg resolvers, or the ADK fallback | Yes (pwsh, AST/behavior half) |
| `catalog_semantics_test.py` (T50) | The Catalog boundary and collection-shape contract over the r12.52-r12.67 hardening arc: the 48-function catalog/collection inventory (each defined exactly once), horizontal static invariants, typed semantic validator wiring (`CATALOG_VALIDATOR_EXECUTION_FAILED` excluded from transient retries), legacy-helper containment, Setup-DU scalar identity pins, and the runtime groups -- semantic retry, typed endpoint semantics (the exact-KB row filter pinned on a single-anchor page: the measured filter is a +/-1800-char context-window heuristic), cache identity tags, scalar boundaries, and flat collection shapes from the measured Server 2016 four-row query; 104 assertions | After every change to the Catalog client, validators, cache, or collection-shape helpers | Yes (pwsh) |
| `generic_list_binder_test.py` (T51) | The PowerShell 7.4+ Generic.List binder and collection-materialization guard over the r12.17/r12.64 incident class: no New-Object Generic.List construction in the active script; P11 evidence RowCount taken from the List Count property directly; the oscdimg resolvers use constructor-created typed lists with explicit ToArray() materialization; behavioral pins under the pinned pwsh confirm the exact incident shapes materialize correctly; 17 assertions | After every change that introduces or touches Generic.List construction or collection materialization | Yes (pwsh) |
| `media_authority_test.py` (T52) | The P09/P10/P11 final-writer authority model, exercised via AST-extracted functions with the DISM boundary mocked: the retained r12.62 media-sync surface and WinPE media-sync runtime (the standard boot-manager target set pinned in platform-invariant normalized form), the r12.72 P10 write-set authority binding, P11 final-identity evidence gating (tampered-ISO and stale-evidence states rejected), the measured Server 2022 reviewed-pinned Catalog identity shape, the measured Server 2019 final Setup-binary authority, and the Setup-DU final manifest validation guards; 50 assertions | After every change to P09/P10/P11 media sync, authority binding, or final-identity evidence | Yes (pwsh) |
| `source_format_test.py` (T54) | The SPEC section A.2 source-file format contract for both deliverables: UTF-8 BOM, CRLF with no bare LF and no stray CR (exact byte counts), a clean parse under the pinned pwsh, and every character above U+007F classified by the PowerShell tokenizer as lying inside a string-literal token. Supersedes the CI step that rejected any byte above 0x7F -- stricter than SPEC, and incompatible with the ja-jp Catalog display-name aliases the script carries. PSA7003 is not a substitute: it reports one finding anchored at a file's first non-ASCII occurrence, so a suppression there silences all later ones; 16 assertions | After any edit that touches encoding, line endings, or adds a non-ASCII character; on every CI run | No |
| `psa_debt_baseline_test.py` (T55) | The analyzer adjudicated-debt gate. Reads the declared per-deliverable counts from `.psa-baseline.json` and asserts the measured `psa.py` summary equals them exactly -- an increase is a regression, a decrease means the declaration is stale. Expected values are read from the declared file, never hardcoded, so changing the debt is always a reviewed diff; 16 assertions | Before every commit, and after any change that could alter analyzer findings; on every CI run | No |
| `research_reference_drift_test.py` (T56) | The research-reference drift guard, v2 after the 2026-08-09 re-audit. Scans the current normative files (SPEC, README/README.ja, TESTING, this file, and the main script including comments) as NORMALIZED LOGICAL BLOCKS -- Markdown paragraphs and PowerShell comment blocks are joined, code markup stripped and whitespace collapsed before matching, because the measured v1 miss was a stale norm whose phrase wrapped across a line break with backticks between the words. Rejects eight retired statement families: Server 2016 Setup-DU non-existence; per-OS-generation Kind-absence and the retired Forbidden-Kind-axis phrasing (English and Japanese); stale research-report paths missing the `documents/` prefix; Digest-as-universal-key; universal boot.wim LCU-impossibility (bare impossibility phrasing counts only with boot.wim in the block); PCA2023 boot-manager claims using the retired signing verb (English and Japanese); universal WinRE no-LCU phrasing (armed only with WinRE in the block, so release-specific routing statements stay expressible); and universal digest-mandatory phrasing superseded by the state-driven B.19.2 table. A retired-CLI-alias check additionally rejects the two retired invocation aliases of the public OsVersion/OsLanguage parameters in the Markdown normative files (the script's internal helpers legitimately keep those private names). CHANGELOG is out of scope; Historical/Superseded regions (heading, Status marker, or paragraph label) are excluded. Machinery is proven against built-in synthetic samples first, including wrapped-phrase and markup-split positives reproducing the measured v1 miss. Also pins the STAGE 3 trigger surfaces to each other (workflow `on:` exactly `workflow_dispatch`; TESTING Current-trigger paragraph states dispatch-only). Guards reintroduction only -- it does not turn the research report into policy; 46 assertions | On every change to the normative documents, the main script's comments, or the STAGE 3 workflow triggers; on every CI run | No |
| `p08_plan_scope_test.py` (T36) | P08 plan-scope + WinRE has-work contract (r11.56): `Test-WimSequenceHasWork` null-hardening (null sequence / `@($null)` element -- the 2026-07-07 Server 2019 crash shape -- / cleanup-only / empty-Patches all False; real patch True); structure pins -- single `$plan = Get-OrInitPatchPlan` hoisted above the policy branch, has-work decision before the install.wim mount, inline crash-prone Where-Object gone; 10 assertions | After every change to P08's plan wiring or the WinRE section | No |
| `seed_contract_test.py` (seed contract gate) | `data/seed/seed-Server*.json` vs `schema/config-seed.schema.json` + structural seed rules; 17 assertions. No T number — gate convention. | After every change to seeds or the seed schema | No |
| `canonical_json_format_check.py` (canonical JSON format gate) | Re-serialises every `*.json` under `data/`, `tests/fixtures/`, `tests/snapshots/` and fails on byte divergence (28 files at r12.75); implements SPEC §C.3.4. No T number — format gate. | After every change that adds or modifies a JSON file in the scanned directories | No |
| `canonical_json_format_check.py` (Part C gate) | Offline format compliance check for every `*.json` file under `data/`, `tests/fixtures/`, and `tests/snapshots/`. Re-serialises each file through `canonical_json_dumps` and fails if the bytes diverge. Implements SPEC §C.3.4. | On every commit that adds or modifies a JSON file in the three scanned directories; on every CI run | No  |
| `config_schema_test.py` (config schema gate) | Offline schema-conformance check with **declaration-based selection** (r12.00): each config's top-level `Schema` field selects `schema/config.schema.json` (`"3.0"`) or `schema/config.schema.v4.json` (`"4.0"`); unknown values fail loudly. The stdlib-only validator covers the draft-07 subset plus the five 2020-12 keywords the v4 schema uses (`#/$defs/...` refs, `oneOf`, `pattern`, `minItems`, `minimum`), each self-tested in both directions; the r10.4 regression guard against `Patches` reappearing stands. 20 assertions. No T number — schema gate, mirroring the format-gate convention. | On every commit that touches `data/config-Server*.json` or `schema/config.schema*.json`; on every CI run | No  |
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
python3 config_schema_test.py              # config schema gate: data/config-Server*.json vs the schema declared by the current repository contract
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
[`../../../quality-tools/powershell-static-analyzer/psa.py`](../../../quality-tools/powershell-static-analyzer/psa.py),
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
  dism_cleanup_args_test.py              T24 (DISM cleanup argument vector, 6)
  dism_export_args_test.py               T25 (DISM export argument vector, 6)
  defender_exclusion_plan_test.py        T26 (Defender-exclusion pure helpers, 13)
  patch_integrity_digest_test.py         T29 (digest-format boundary + single-accessor wiring, 14)
  checkpoint_placement_test.py           T32 (Checkpoint placement + routing + State-integrity, 15)
  pca2023_default_auto_test.py           T35 (PCA2023 default-auto surface, 9)
  p08_plan_scope_test.py                 T36 (P08 plan-scope + WinRE has-work, 10)
  media_inspection_test.py               T38 (media-inspection engine, 31)
  boot_verification_tools_test.py        T39 (boot-verification tool set, 17)
  setup_binaries_sync_test.py            T40 (P08S setup-binary sync; structural invariant + per-site pins, 21)
  apply_plan_conformance_test.py         T41 (declared ApplyPlans conformance, 139 @ r12.75)
  servicing_model_declaration_test.py    T42 (SourcePrerequisites/ValidationPolicy declaration, 37 @ r12.75)
  line_integrity_declaration_test.py     T43 (Lines[].Integrity + Roles declaration, 128 @ r12.75)
  compatibility_declaration_test.py      T44 (legacy/canonical meta-contract, 64)
  servicing_contract_baseline_test.py    T45 (servicing-contract baselines + component-hash cross-check, 26)
  discovery_policy_declaration_test.py   T46 (DiscoveryPolicy/SearchProfiles declaration, 112)
  collector_artifact_test.py             T47 (Collector identity/artifact + parse gate, 29)
  collector_semantics_test.py            T48 (Collector PFRO/preflight/Secure Boot behavior, 42)
  oscdimg_reference_test.py              T49 (declared oscdimg reference + qualification wiring, 44)
  catalog_semantics_test.py              T50 (Catalog boundary + collection shapes, 104)
  generic_list_binder_test.py            T51 (Generic.List binder + materialization guard, 17)
  media_authority_test.py                T52 (P09/P10/P11 final-writer authority model, 50)
  source_format_test.py                  T54 (SPEC A.2 source-file format, both deliverables, 16)
  psa_debt_baseline_test.py              T55 (analyzer adjudicated-debt baseline gate, 16)
  research_reference_drift_test.py       T56 (research-reference drift guard v2 + alias check + STAGE 3 trigger pin, 46)
  config_schema_test.py                  config schema gate (20; declaration-based v3/v4 selection)
  seed_contract_test.py                  seed contract gate (17)
  canonical_json_format_check.py         canonical JSON format gate (28 files @ r12.75)
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
offline-deterministic; most contracts additionally require the pinned
pwsh on PATH for the TestHarness REPL or AST-extraction drivers) is
run as the local gate battery on every change and is a natural
candidate for a future Stage 1 extension. T1 and T4 are live probes and belong to the
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
the development archive (outside the repository tree). The `poc_<topic>_*` naming convention itself is
preserved in SPEC.md §B.22.2 as a reserved pattern for any future
PoC investigation.

