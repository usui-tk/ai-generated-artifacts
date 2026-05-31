---
id: 0003
title: standalone-tool-principle
status: accepted
date: 2026-05-31
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §machinery"]
---

<!-- AI read-contract: authoritative for the machinery packaging constraint. -->

# 0003 — Standalone-tool principle for verification machinery

## Context
Verification machinery is called by both the hot-path gate (P6/P7) and the cold loop
(P8). It must be trivially runnable, copy-deployable, and free of import-time coupling.

## Decision
Each verification tool is **single-file, stdlib-only, and no-cross-reference**: it does
not import sibling project code, and it follows-latest (whole-tool granularity, no
region-vendoring). Tools live on the `quality-tools/` machinery shelf, one tool per
folder, and never graduate.

## Consequences
- A tool can be run from any checkout with only Python present.
- Machinery is excluded from region-drift governance (it is not a governed asset).
- Avoids the circularity of the verifier being filed inside the governance hub.

## Alternatives considered
- A shared machinery library: reintroduces cross-reference and import-time coupling.
- Packaging as installable distributions: contribution/run friction for little gain.
