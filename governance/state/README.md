# governance/state/

> Operational committed state for the governance mechanism. `manifest.jsonl` is
> populated from **P2.7** (the canonical-set rows); the other tiers remain
> placeholders until their phases populate them.

## Layout
- `manifest.jsonl` — the asset manifest (one canonical-JSON object per line).
  Authored at **P2.7**: 58 canonical PowerShell-helper units (39 Public + 19
  Private). The single source of truth for each unit's canonical location,
  version, default policies, and consumers.
- `observations/` — drift observations, hive-partitioned
  `repo=<repo>/date=YYYY-MM-DD/run-<run_id>.jsonl` (produced from P3 onward).
- `ledger/` — reconciliation ledger: `proposals.jsonl` + `summary.md` (P8 onward).
- `reports/` — per-run reports: `<run_id>.json` + `.md` (P8 onward).

## Discipline
- Schema-on-read; each record carries a top-level `schema_version`.
- Validated by the **governance-state-validator** gate
  ([`quality-tools/governance-state-validator/`](../../quality-tools/governance-state-validator/)):
  `python3 quality-tools/governance-state-validator/validate_state.py` from the
  repo root must report **0 findings** (schema validation, canonical_location
  existence, manifest/marker coherence, canon coverage, canonical-JSON format)
  before the state is considered consistent.
- Disposable analysis (DuckDB) is **not** here and is git-ignored (ADR 0002).
- Caches under any `cache/` are git-ignored.
