---
id: 0001
title: tooling-language-python
status: accepted
date: 2026-05-31
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §tooling"]
---

<!-- AI read-contract: authoritative for the verification-tooling language choice. -->

# 0001 — Tooling language is Python

## Context
The governance mechanism needs verification machinery (the PowerShell static
analyzer `psa.py`, and the P3 canonical-drift scanner). A single, portable,
dependency-light language is required so the machinery runs on Linux CI and on
ja-JP Windows hosts without a heavy toolchain.

## Decision
Verification machinery is written in **Python 3** (stdlib-first). `psa.py` and the
drift scanner are Python. Gate-only third-party deps (e.g. `jsonschema`) are allowed
where a stdlib equivalent is impractical, and are stamped per run, not pinned.

## Consequences
- One runtime for all machinery; trivial to run in CI and locally.
- The machinery is itself testable in Python (`test_psa_rules.py`, 280 tests).
- PowerShell remains the language of the *governed* scripts; Python governs them.

## Alternatives considered
- PowerShell-native analyzers: ties machinery to the analyzed language and to a
  heavier module ecosystem (PSScriptAnalyzer is used as a *gate*, not the engine).
- Compiled tooling: portability and contribution cost outweigh the benefit.
