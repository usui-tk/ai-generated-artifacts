# STATUS — Execution Truth & Handoff

> **Tier-M (in-repo PM layer, M7).** Single living current-truth view + session handoff.
> Bounded (R1): current state only — git history is the audit trail. Scrubbed (R2): no
> secrets/credentials/client data. References, does not restate (R3): the design substrate
> lives in the Tier-P handoff docs (baseline / plan / spine / register) and in `../adr/`.
> Decisions are durable in `../adr/`; this file tracks *status*, not decisions.
> **Session entry point** — read first per the AGENTS.md startup contract. Handoff rule:
> **ADR 0005**. Tier-P design docs stay **unmanaged** (out of repo) and ship as one bundle
> + MANIFEST at each static-point (never piecemeal).

_Last updated: 2026-05-31 (UTC) — **P1 complete** (P1.1–P1.6): governance auto-load model + ADR 0006 + `governance/SPEC.md` authored; next phase **P2**._

---

## Current phase

| Field | Value |
|:---|:---|
| Just completed | **P1 — Governance model** (P1.1–P1.6): startup contract (AGENTS.md), thin `CLAUDE.md` `@import`, prompt templates, ADR 0006, `governance/SPEC.md` + ADR↔SPEC closure — committed, gates green |
| Current phase | **P2 — Analyze + reference model + baseline** — **next: P2.1** (inventory shared units across consumers) |
| Operating loop | per phase: fill per-step schema → dry-run §Y → sign-off §Z → execute (Path 2) |

## Phase progress

| Phase | Status | Notes |
|:--|:--|:--|
| **P0a — Foundation** | ✅ done | scaffold (`governance/ quality-tools/ reference-code/ projects/`), gates, `documents/` consolidation (#19), substrate ADRs, this tracker |
| **psaMove.1** (expand: copy) | ✅ done | byte-identical copy → `quality-tools/powershell-static-analyzer/`; old path coexists |
| **psaMove.2** (expand: migrate/rename) `[AUTH]` | ✅ done | 26 central refs → new path; path-encoding CI workflow renamed; `.ps1` BOM+CRLF preserved; only the 5 old-dir self-refs remain (deleted at psaMove.5, post-P7) |
| **P1.1** — A-4 `@import` gate | ✅ verified | thin `CLAUDE.md` can `@import AGENTS.md` (official Claude Code memory docs); supported as assumed, no deviation; caveats: import is inline (no token saving) + advisory (P1 ships no contract-CI — ADR 0006; wiring stays advisory). See plan P1.1 [VERIFIED] |
| **P1.2–P1.6** — governance model | ✅ done | P1.2 AGENTS.md startup contract (§3) `[AUTH]` · P1.3 thin `CLAUDE.md` `@import` · P1.4 prompt templates (`governance/templates/`) · P1.5 **ADR 0006** (single AGENTS.md source; **no contract-CI at P1**, M2 amends P1 exit) · P1.6 **`governance/SPEC.md`** authored + ADR 0001–0004↔SPEC back-refs closed |

Stage-1 gates green at HEAD (psa.py 0/0/0 config-aware from the new path · `--self-check` in sync · suite 280/280 · ParseFile 0). P1 governance docs: `.md` LF + ADR↔SPEC bidirectional integrity green (no PowerShell touched in P1).

## Next action
Begin **P2 — Analyze + reference model + baseline** at **P2.1** (inventory shared units
across all consumers) under the per-phase loop (fill per-step schema → §Y dry-run → §Z
sign-off → execute). Remediate the `$ks` deviation at **P6**.

## Open pointers
- `[WORKING]` psa.py move **CONTRACT** (psaMove.4/.5 — delete the old `scripts/python/powershell-static-analyzer/` path) is **after P7**, gated on a cross-repo zero-referrer grep + §9.3 checkpoint. Both paths coexist until then.
- `[WORKING]` `Deploy-Drivers` 8 references to the old psa path are migrated in **P7** (single PR).
- `[WORKING]` Subproject migration `scripts/<family>/<name>/ → projects/<lang>-<name>/` is **P5/P6**; `reference-code/<family>/` homes created lazily at **P2.6** (bash/python builds deferred — SPINE-2/5; policies decided).
- `[WORKING]` Governance docs for psa.py at its new home = **P4**; template finalization (TF) = before **P5**.
- Known gate deviation: `Update-WindowsServerIso.ps1` PSScriptAnalyzer `0/1/0` (`$ks`, line 8095) — user-dispositioned, remediate at **P6** (§8.3; not accepted-open).
- **ADR 0006:** P1 ships **no contract-CI** (governance-loading wiring is advisory, not CI-enforced). Revisit at **P5/P6** when file moves raise the regression risk — add the contract check then via a new ADR if warranted.

## ADR index (`../adr/`)
- 0001 — tooling language = Python · 0002 — analysis layer = DuckDB (disposable, P8) · 0003 — standalone-tool principle · 0004 — outcome-based execution framework (M8) · 0005 — session-handoff protocol · 0006 — AI-agent config coverage & contract-CI scope.
- Cross-cutting current-truth view: **`../SPEC.md`** — §tooling/§analysis-layer/§machinery/§execution-framework ← ADR 0001–0004 (bidirectional `governs`↔back-ref).

## Design substrate (Tier-P handoff — referenced, not restated, R3)
- `HANDOFF-baseline-consolidated-design.md` — the living design baseline.
- `IMPLEMENTATION-PLAN-skeleton.md` — the living implementation plan (§0.1 disciplines, §Y dry-run incl. Y.1 P0a + Y.5 psaMove, §Z sign-off).
- `TRACEABILITY-SPINE.md` — outcome→deliverable→producer→dependency→gate spine (orphans = 0).
- `TEMPLATE-REQUIREMENTS-REGISTER.md` — Tier-P template/dotfile requirements register.

_Per **ADR 0005**: the four Tier-P docs stay **unmanaged** (out of repo) and are delivered as **one bundle (zip) + MANIFEST** at each static-point — never piecemeal, never assume a current local copy._

## Static-point index (recoverable points = commits; repo-external Zips per `../static-point-procedure.md`)
| Phase | Commit | Static-point |
|:--|:--|:--|
| P0a | `5490de3` (+ `de39ef9` cleanup) | per procedure (repo-external Zip) |
| psaMove.1 | `f289933` | per procedure |
| psaMove.2 | `f8b942b` | per procedure |
| P1 (governance model) | `1097309`·`dd8f9f3`·`cab8375`·`9a05635`·`9be1056` | per procedure (repo-external Zip at P1 phase-end) |
