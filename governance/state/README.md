# governance/state/

> Operational committed state for the governance mechanism. **No machine data is
> committed yet** — these are placeholders; later phases populate them.

## Layout
- `manifest.jsonl` — the asset manifest (one JSON object per line). **Placeholder until
  P2** authors the manifest schema and first rows. Until then this directory carries
  only `.gitkeep`.
- `observations/` — drift observations, hive-partitioned
  `repo=<repo>/date=YYYY-MM-DD/run-<run_id>.jsonl` (produced from P3 onward).
- `ledger/` — reconciliation ledger: `proposals.jsonl` + `summary.md` (P8 onward).
- `reports/` — per-run reports: `<run_id>.json` + `.md` (P8 onward).

## Discipline
- Schema-on-read; each record carries a top-level `schema_version`.
- Disposable analysis (DuckDB) is **not** here and is git-ignored (ADR 0002).
- Caches under any `cache/` are git-ignored.
