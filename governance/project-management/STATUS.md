# STATUS — Execution Truth & Handoff

> **Tier-M (in-repo PM layer, M7).** Single living current-truth view + session handoff.
> Bounded (R1): current state only — git history is the audit trail. Scrubbed (R2): no
> secrets/credentials/client data. References, does not restate (R3): the design substrate
> lives in the Tier-P handoff docs (baseline / plan / spine / register) and in `../adr/`.
> Decisions are durable in `../adr/`; this file tracks *status*, not decisions.

_Last updated: 2026-05-31 (UTC) — reflects **psa.py move (EXPAND)** complete._

---

## Current phase

| Field | Value |
|:---|:---|
| Just completed | **psa.py move — EXPAND** (psaMove.1 copy + psaMove.2 migrate/rename) — committed, gates green |
| Next phase | **P1 — Governance model, central-local** (unblocked: P1 needs only P0a, which is done) |
| Operating loop | per phase: fill per-step schema → dry-run §Y → sign-off §Z → execute (Path 2) |

## Phase progress

| Phase | Status | Notes |
|:--|:--|:--|
| **P0a — Foundation** | ✅ done | scaffold (`governance/ quality-tools/ reference-code/ projects/`), gates, `documents/` consolidation (#19), substrate ADRs, this tracker |
| **psaMove.1** (expand: copy) | ✅ done | byte-identical copy → `quality-tools/powershell-static-analyzer/`; old path coexists |
| **psaMove.2** (expand: migrate/rename) `[AUTH]` | ✅ done | 26 central refs → new path; path-encoding CI workflow renamed; `.ps1` BOM+CRLF preserved; only the 5 old-dir self-refs remain (deleted at psaMove.5, post-P7) |
| **P1 — Governance model** | ⬜ next | P1.1 verifies `CLAUDE.md @import AGENTS.md` behavior |

Stage-1 gates green at HEAD (psa.py 0/0/0 config-aware from the new path · `--self-check` in sync · suite 280/280 · ParseFile 0).

## Next action
Prepare **P1** under the per-phase loop (fill → §Y dry-run → §Z sign-off → execute).
Remediate the `$ks` deviation at **P6**.

## Open pointers
- `[WORKING]` psa.py move **CONTRACT** (psaMove.4/.5 — delete the old `scripts/python/powershell-static-analyzer/` path) is **after P7**, gated on a cross-repo zero-referrer grep + §9.3 checkpoint. Both paths coexist until then.
- `[WORKING]` `Deploy-Drivers` 8 references to the old psa path are migrated in **P7** (single PR).
- `[WORKING]` Subproject migration `scripts/<family>/<name>/ → projects/<lang>-<name>/` is **P5/P6**; `reference-code/<family>/` homes created lazily at **P2.6** (bash/python builds deferred — SPINE-2/5; policies decided).
- `[WORKING]` Governance docs for psa.py at its new home = **P4**; template finalization (TF) = before **P5**.
- Known gate deviation: `Update-WindowsServerIso.ps1` PSScriptAnalyzer `0/1/0` (`$ks`, line 8095) — user-dispositioned, remediate at **P6** (§8.3; not accepted-open).

## ADR index (`../adr/`)
- 0001 — tooling language = Python · 0002 — analysis layer = DuckDB (disposable, P8) · 0003 — standalone-tool principle · 0004 — outcome-based execution framework (M8).

## Design substrate (Tier-P handoff — referenced, not restated, R3)
- `HANDOFF-baseline-consolidated-design.md` — the living design baseline.
- `IMPLEMENTATION-PLAN-skeleton.md` — the living implementation plan (§0.1 disciplines, §Y dry-run incl. Y.1 P0a + Y.5 psaMove, §Z sign-off).
- `TRACEABILITY-SPINE.md` — outcome→deliverable→producer→dependency→gate spine (orphans = 0).
- `TEMPLATE-REQUIREMENTS-REGISTER.md` — Tier-P template/dotfile requirements register.

## Static-point index (recoverable points = commits; repo-external Zips per `../static-point-procedure.md`)
| Phase | Commit | Static-point |
|:--|:--|:--|
| P0a | `5490de3` (+ `de39ef9` cleanup) | per procedure (repo-external Zip) |
| psaMove.1 | `f289933` | per procedure |
| psaMove.2 | `f8b942b` | per procedure |
