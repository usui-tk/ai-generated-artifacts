---
id: 0009
title: psa-canonical-lifecycle
status: accepted
date: 2026-06-01
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §machinery"]
---

<!-- AI read-contract: authoritative for the lifecycle of the psa.py tool across its two
     on-disk locations during the scripts/ -> projects/ migration era - which copy is the
     canonical, continuously-updated source, which copy is frozen, when the byte-identical
     invariant from psaMove.1 lapses, and what consumers must do at migration time. Relates
     to the psaMove plan (expand at psaMove.1/.2, contract at psaMove.4/.5 after P7). Read
     on-demand. If reversing a point, supersede via a new ADR (one decision = one ADR). -->

# 0009 - psa.py canonical lifecycle (Canon-side leads; Script-side frozen until contract)

## Status

Accepted.

## Context

psa.py exists at two on-disk locations within `ai-generated-artifacts`:

- **Canon side** - `quality-tools/powershell-static-analyzer/` - created by the psaMove
  *expand* step (psaMove.1) as a byte-identical copy of the original, and adopted as the
  single canonical home (the machinery shelf, one tool per folder, follows-latest).
- **Script side** - `scripts/python/powershell-static-analyzer/` - the original
  pre-move location. Per the psaMove plan it is **not deleted at expand time**; it
  coexists with the canonical copy and is removed only by the *contract* step
  (psaMove.5), which runs **after P7**, once a cross-repo zero-referrer grep proves no
  remaining referrers in either repository.

psaMove.1's acceptance asserted the new path is **byte-identical (hash-equal)** to the
old path. That held at the instant of the copy, but implicitly assumed both copies stay
frozen-equal until the old one is deleted. We now need to update psa.py as the canonical
tool (the v4.3.0 `psa2013_known_script_vars` key, required so the
`reference-code/powershell` canon reaches psa.py `0/0/0`), and further updates are
expected. This forces an explicit decision about which copy evolves, which stays frozen,
and what becomes of the hash-equal invariant.

## Decision

1. **The Canon-side copy (`quality-tools/powershell-static-analyzer/`) is the canonical
   source of truth for psa.py and is updated going forward.** All tool changes (rules,
   config keys, version bumps, docs) land here. It is the reference origin from which
   consumers obtain psa.py.
2. **The Script-side copy (`scripts/python/powershell-static-analyzer/`) is frozen.** It
   is not edited and its `VERSION` is left as-is. It exists only to keep external links
   live until the psaMove *contract* (psaMove.5, after P7) deletes it.
3. **The psaMove.1 byte-identical / hash-equal invariant is a one-time copy-time condition,
   now lapsed.** It held at psaMove.1 and is not a standing invariant. After that point the
   Canon-side copy evolves independently; the two copies are expected to diverge in version
   and content (e.g. Canon `4.3.0` vs Script `4.2.0`). This divergence is intentional, not
   drift to reconcile in place.
4. **Consumers migrate to the canonical psa.py during the `scripts/` -> `projects/`
   migration (P7 era), not before.** At that migration each consumer (a) repoints its
   psa.py references - `.psa.config.json` schema/acquisition URLs, docs - at the Canon-side
   home, and (b) **updates its own code as needed to remain green under the then-current
   psa.py** (adopting new config keys, clearing newly-introduced findings). This
   spec-following code change is an explicit, planned P7 deliverable, not an incidental edit.
5. **The Script-side delete (psaMove.5) remains gated on the cross-repo zero-referrer grep
   after P7** (unchanged). Until then both paths remain on disk; only the Canon side is
   authoritative.
6. **psa.py governance documentation (P4)** documents the Canon-side copy at its
   then-current version. A tool change made ahead of P4 (such as v4.3.0) is recorded in the
   Canon-side `CHANGELOG.md` and its own ADR, and is acknowledged - not re-derived - at P4.

## Consequences

- A temporary, intentional version skew exists between the two copies (Canon `4.3.0`,
  Script `4.2.0`), a recorded expected state resolved by the eventual Script-side delete
  (psaMove.5) rather than by re-synchronising the frozen copy.
- The plan's psaMove.1 hash-equal language is downgraded to a copy-time condition; the
  spine's psa.py producer reads as "psaMove.1 copy, then Canon-side independent evolution";
  the register's `.psa.config.json` schema/version requirement resolves "canonical VERSION"
  to the Canon-side `quality-tools/` `VERSION`. (Reflected in Tier-P baseline/plan/spine/
  register.)
- P7's consumer-migration scope explicitly includes spec-following code changes, not only
  path-string repointing, making the previously-implicit "follow the latest psa.py"
  obligation a concrete, gated deliverable.
- The PSAP0005 default-on roadmap (a future psa.py rule-default change) rides the same
  Canon-leads / consumers-follow lane established here.
- The v4.3.0 key is a positive external-scope **contract declaration**, not a rule disable:
  because each `.ps1` is a separate script scope, the file-local PSA2013/PSA2008 model stays
  correct for self-contained consumer scripts; only declared external-scope names (shared
  canon helpers, established by per-unit inspection) are exempt, so first-party typo
  detection is unweakened.
