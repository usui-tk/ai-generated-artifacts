---
id: 0002
title: analysis-layer-duckdb-disposable
status: accepted
date: 2026-05-31
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §analysis-layer"]
---

<!-- AI read-contract: authoritative for the analysis-layer technology + lifecycle. -->

# 0002 — Analysis layer is DuckDB, disposable, introduced at P8

## Context
The cold reconciliation loop needs ad-hoc analytical queries over observation
streams (JSONL). The committed source of truth is the JSONL/manifest under
`governance/state/`; analytical convenience must not become a second source of truth.

## Decision
The analysis layer is **DuckDB**, treated as **disposable** (rebuilt from committed
JSONL, never the authority), and is **introduced only at P8** (the cold loop). It is
not part of the hot-path scanner (P3) and its files are git-ignored (`*.duckdb`).

## Consequences
- Schema-on-read analytics without a server; rebuildable from committed facts.
- No new committed authority; the JSONL/manifest remain canonical.
- Earlier phases (P0a–P7) carry no DuckDB dependency.

## Alternatives considered
- A committed database file: creates a divergent authority and binary churn.
- SQLite: viable, but DuckDB's columnar/analytical fit and JSONL ingestion are better.
