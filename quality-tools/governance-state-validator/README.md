# governance-state-validator

A standalone validation gate for the committed governance state. It is the
machine-checkable counterpart, for the data tier, of what `psa.py` is for
PowerShell: a gate that must be **run-and-green** before the governance state is
considered consistent.

## What it checks

| Check | Description |
|-------|-------------|
| **A** | Every `governance/state/manifest.jsonl` record validates against `governance/schema/manifest.schema.json` (JSON Schema draft-07). |
| **B** | Every `governance/state/observations/**/*.jsonl` record validates against `observation.schema.json`. Skipped while no observation files exist (before P3). |
| **C** | Every manifest record's `canonical_location` exists on disk. |
| **D** | For `kind = powershell-helper`, the `canonical_location` file carries a canonical marker whose `unit_id` and `version` match the manifest record. The manifest is the single source of truth; the marker claims sync against it. |
| **E** | The canon unit files in the unit home (`reference-code/<family>/{Public,Private}`) are in bijection with the powershell-helper manifest records (no orphan unit-home file, no dangling record). Manifest-master (ADR 0011 §1): non-unit areas (`tests/`, `.psm1`/`.psd1` scaffolding) are not managed units and are not enumerated. |
| **F** | Every state record is canonical JSON: key-sorted, compact separators, one record per line (diff-stable). |

Field-ownership separation (manifest vs marker vs observation) is enforced by
each schema's `additionalProperties: false`, so a cross-tier field is rejected
by check A/B.

## Usage

```
python3 validate_state.py [--root <repo-root>] [--quiet]
```

Exit code `0` when all checks pass, `1` otherwise. Run from the repo root, or
pass `--root`.

## Runtime

`python3` + `jsonschema` (the sanctioned artifact-gate runtime; governance
`SPEC.md` machinery, baseline section 8.2). Install per the baseline:
`pip install --break-system-packages jsonschema` (latest; record the resolved
version per run, as for PSScriptAnalyzer).

## Self-test

```
python3 test_validate_state.py
```

The test builds synthetic repo trees (real schemas + crafted state) and asserts
that each check fires on the corresponding violation and that the happy path is
green - a gate that cannot fail is worthless.
