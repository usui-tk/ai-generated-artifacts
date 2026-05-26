# PoC: Online Patch Metadata via release-info (operational guide)

This is the operational guide for the `release_info` PoC tracked
as part of r06 Phase 2. The **findings and recommendations** are
in the sibling file
[`poc-release-info-report.md`](./poc-release-info-report.md);
this file is the "how to run it" guide.

## Purpose

Validate that Windows Server monthly patch metadata can be acquired
from authentication-free online sources, with the goal of reducing
the brittleness of the production Microsoft Update Catalog scrape.

See SPEC.md §B.21 ("Update Type Matrix per OS generation") for the
normative spec this PoC investigates, and SPEC.md §B.22.5 for the
research questions A through F that motivated the work.

## Hard constraints

The PoC obeys these rules, set by the project owner before work began:

- **No authentication.** No MSAL, no Entra ID, no API keys, no
  service-principal secrets.
- **No script (`.ps1`) changes** in Phase 2. The PoC consists of
  Python utilities that emit JSON / CSV reports.
- **No on-disk schema changes** in Phase 2. Any new
  `Config/<OsKey>.json` fields are deferred to Phase 3.

## File layout (per SPEC.md §B.22)

```
tests/
├── poc_release_info_01_fetch.py      # downloads the Markdown
├── poc_release_info_02_parse.py      # parses into JSON
├── poc_release_info_03_analyse.py    # writes CSV/JSON analyses
├── snapshots/poc_release_info/
│   ├── .gitattributes                # preserves Microsoft's CRLF line endings
│   ├── release-info-YYYY-MM-DD.md    # raw Markdown snapshot
│   └── release-info-YYYY-MM-DD.meta.json
└── fixtures/poc_release_info/
    ├── release-info.json             # parsed structured form
    ├── update-type-summary.csv       # YYYY-MM x OS x letter pivot
    ├── baseline-month-detection.json # Server 2025/2022 hotpatch calendar
    ├── letter-frequency.json         # A/B/C/D/E/OOB statistics
    └── coverage-summary.json         # date-range coverage + gaps

docs/poc/
├── poc-release-info-readme.md        # this file
└── poc-release-info-report.md        # findings and recommendations
```

The two-letter conventions (`tests/` for code and data, `docs/`
for prose; `poc_` for Python identifiers, `poc-` for Markdown
filenames) are defined normatively in SPEC.md §B.22.

## How to run

All three scripts are stdlib-only Python 3. No `pip install`
needed.

```bash
cd scripts/powershell/update-windows-server-iso/tests

# Step 1: fetch the latest Markdown snapshot from Microsoft Learn
python3 poc_release_info_01_fetch.py
#   -> writes snapshots/poc_release_info/release-info-YYYY-MM-DD.md
#   -> writes snapshots/poc_release_info/release-info-YYYY-MM-DD.meta.json

# Step 2: parse the latest snapshot into a structured JSON document
python3 poc_release_info_02_parse.py
#   -> writes fixtures/poc_release_info/release-info.json

# Step 3: analyse the parsed JSON against SPEC.md §B.21 claims
python3 poc_release_info_03_analyse.py
#   -> writes fixtures/poc_release_info/update-type-summary.csv
#   -> writes fixtures/poc_release_info/baseline-month-detection.json
#   -> writes fixtures/poc_release_info/letter-frequency.json
#   -> writes fixtures/poc_release_info/coverage-summary.json
```

Steps 2 and 3 are deterministic given the same snapshot, so
re-running them in isolation is safe. Step 1 hits the network.

## Offline / cached runs

If the network is unreachable, step 1 will fail with a clear error,
but steps 2 and 3 continue to work against the most recent snapshot
in `tests/snapshots/poc_release_info/`. The snapshot directory is
committed to the repo precisely so that runs are reproducible
without network access.

## What this PoC does NOT do

- It does **not** modify `Update-WindowsServerIso.ps1`.
- It does **not** download or process any .msu / .cab files.
- It does **not** replace `Resolve-PatchSetFromCatalog`.
- It does **not** assume the release-info page covers every patch
  Type. The report.md companion characterises which Types are
  absent from the page (.NET CU, Dynamic Update, Language Packs).

## Lifecycle

These files are **disposable** in the sense defined by SPEC.md
§B.22: when r06 Phase 3 concludes with a production design (or
the PoC is shelved), every `poc_release_info_*` file, every
`tests/snapshots/poc_release_info/` snapshot, every
`tests/fixtures/poc_release_info/` artefact, and every
`docs/poc/poc-release-info-*.md` document can be deleted as a
single atomic step. They live alongside the production T1-T5
regression suite only because the file-organisation rules favour
fewer top-level directories; they do not participate in T1-T5.

## Cross-references

- [SPEC.md §B.21](../../SPEC.md) -- Update Type Matrix per OS generation
- [SPEC.md §B.22](../../SPEC.md) -- File organisation rules (this file's authority)
- [SPEC.md §G adjunct](../../SPEC.md) -- PoC scripts under `tests/`
- [`poc-release-info-report.md`](./poc-release-info-report.md) -- PoC findings
- [Source page](https://learn.microsoft.com/en-us/windows/release-health/windows-server-release-info)
