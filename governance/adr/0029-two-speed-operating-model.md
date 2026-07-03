---
id: 0029
title: two-speed-operating-model
status: accepted
date: 2026-07-03
supersedes: []
superseded_by: null
governs: ["AGENTS.md §11"]
---

<!-- AI read-contract: authoritative for the TWO-SPEED operating model of this
     repository - one `main`, two commit streams at different speeds: the
     MAINTENANCE stream (project/product work, advances anytime) and the GOVERNANCE
     stream (arc-shaped patch series: design-first, [AUTH]-gated, battery-verified).
     Load-bearing rules: rebase + full-battery re-verify when maintenance advanced
     main; stream ownership (project doc-sets are maintenance-owned, Layer-0/ADR/
     machinery are governance-owned + [AUTH]); the AI author never pushes (user
     pushes, AI re-clones + re-verifies); hot observations transient vs cold
     observations committed (ADR 0028). AGENTS §11 is the thin agent-facing summary.
     Do not re-decide; supersede via a new ADR if reversing. -->

# 0029 — The two-speed operating model (maintenance stream vs governance stream)

## Context

Since the G-program began, this repository has in practice been operated at two
speeds on a single `main`: day-to-day **maintenance** work (project revisions,
CHANGELOG entries, CI fixes) advancing whenever needed, and **governance** work
(canon, manifest, gates, ADRs) advancing as verified, arc-shaped patch series.
The norm was practiced and recorded piecemeal — the STATUS operating-loop row,
session-startup discipline kept outside the repository (Tier-P), and fragments in
several ADRs — but never formalized in-repo. ADR 0023 requires durable operating
decisions to land in the repository; with the G-program's machinery complete
(ADRs 0022–0028), the model itself is the last undocumented decision.

## Decision

One branch, two streams, five rules:

1. **Two streams on one `main`.** The **maintenance stream** is project/product
   work (anything under a project's own doc-set and code, its CI, its CHANGELOG);
   it advances at any time, in ordinary commits or PRs. The **governance stream**
   is Layer-0 / canon / manifest / gates / ADR work; it advances only as
   **arc-shaped patch series**: grounding → design presented for adjudication →
   `[AUTH]` → implementation → the full gate battery → `format-patch` →
   fresh-clone `git am` + tree-hash equality → hand-off. Streams are speeds, not
   branches.
2. **Rebase + re-verify.** A governance series is authored on a verified HEAD. If
   the maintenance stream (or the cold loop's auto-commits, ADR 0028) advanced
   `main` first, the series is rebased and the **full battery re-run** before
   hand-off; a stale-parent series is never handed off.
3. **Stream ownership.** Project doc-sets and code are **maintenance-owned**: the
   governance stream touches them only for mechanical, explicitly-flagged fixes
   (e.g. retired-path rewiring), never for content decisions. Layer-0 documents,
   `governance/`, `quality-tools/`, `reference-code/` and the ADR series are
   **governance-owned**: edits require `[AUTH]` in-session, and `[DECIDED]` items
   are never silently overridden (re-open explicitly instead).
4. **Push discipline.** The AI author never pushes. The human pushes each verified
   series, and the AI re-clones and re-verifies (tree hash + battery) before the
   next arc. Commit authorship stays `Claude <claude@anthropic.com>` for
   AI-authored series (AGENTS §5 commit-author rule).
5. **Hot/cold observation split** (ADR 0028, restated as part of the model): the
   hot path (per-phase/per-PR batteries) treats scanner output as transient and
   never stages it; only the **cold** scheduled loop commits observations, the
   proposals ledger, and regenerated reports — with `[skip ci]` and
   schedule-only triggers so the two speeds cannot ratchet each other.

## Consequences

- The operating model survives session loss: any future agent can reconstruct the
  working rhythm from this ADR + AGENTS §11 alone (Tier-P remains a convenience,
  not a dependency).
- Cold-loop auto-commits interleaving with governance series are expected, not
  interference: rule 2 absorbs them.
- The cost is ceremony on the governance stream (design-first + battery + verify
  round-trips); accepted deliberately — governance mistakes are expensive and the
  ceremony has repeatedly caught real slips before hand-off.

## Considered options

- **AGENTS section only** (rejected): AGENTS is an operating manual, not a
  decision record — no status/supersede machinery; would also violate ADR 0023.
- **ADR only, no AGENTS touch** (rejected): the model IS session discipline;
  agents ground AGENTS every session, so discoverability belongs there.
- **Branch-separated streams** (rejected long ago in practice): one `main` keeps
  the satellite and CI story simple; verified patch series + rebase-and-re-verify
  provide the isolation that branches would, without divergence risk.
