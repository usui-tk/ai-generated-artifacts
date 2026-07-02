---
id: 0022
title: doc-region-version-coupling-gate
status: accepted
date: 2026-07-03
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §machinery"]
---

<!-- AI read-contract: authoritative for the C9 doc-region version-coupling rule - a
     binding=follow-latest HASH-model doc-region marker's version= must equal the manifest
     canonical_version of its (longest-dotted-prefix) manifest doc-region unit; a binding=pin
     marker may lag but never lead. The check is owned by the document-conformance gate
     (doc_gate), NOT the governance-state validator. Read SPEC §machinery for the
     current-truth view. Do not re-decide; supersede via a new ADR if reversing. -->

# 0022 — Doc-region version-coupling gate (closes the proven spec-region promotion hole)

## Context

A 2026-06-11 clarification session **found and proved a governance hole**: for the
`spec-region` kind, **no gate coupled a doc-region marker's `version=` field to the
manifest `canonical_version`**. Throwaway-clone experiment: `canon-manifest-tool update
--unit-id spec.powershell.part-a --version 1.0.0` returned **OK (not refused)**, leaving
the manifest at 1.0.0 against 42 markers at 0.1.0 (14 spec-home + 14 x 2 consumer vendored
doc-regions), while the governance-state validator reported **0 findings (A-G)** and the
document-conformance gate **PASSED**. The P3a.1 write-path boundary's premise ("a
marker-coupled change is REFUSED because validator D/E/G catch the resulting marker
drift") therefore held **only for `powershell-helper` units**; for spec-regions the
refusal never fired.

The cause is structural, not a bug: `doc_gate check_file` validated hash / policy /
L1-membership only (`version=` was parsed but never checked), and validator checks D/G are
deliberately reference-code-scoped by the **ADR 0020 tool boundary** (the validator and
`canon-hash-restamp` are never extended to markdown; doc_gate owns all doc-region
inspection). No tool owned the doc-side version coupling.

Until this ADR landed, the interim operational rule was: **never promote a spec-region via
a manifest-only write.** That rule was human-enforced only and lived in the out-of-repo
Tier-P handoff, not in-repo (see ADR 0023).

## Decision

The **document-conformance gate owns a new check, C9 (doc-region version coupling)**,
extending the TR-TPLCANON-3 check set:

1. **Scope.** Every parsed doc-region whose L1 `content_model` is a **HASH model**
   (`common-fixed`, `vendored`) and whose marker `unit_id` resolves - by **longest
   dotted-prefix match** - to a manifest unit of a doc-region kind (`spec-region` today;
   e.g. `spec.powershell.part-a.logging` resolves to the row `spec.powershell.part-a`).
   Markers with no registered manifest prefix (template-internal L1 markers such as
   `readme.disclaimer`) and structural-model regions are out of scope.
2. **Rule.** `binding=follow-latest`: the marker `version=` **MUST equal** the manifest
   row's `canonical_version`. `binding=pin`: the marker version **may lag but must never
   exceed** the manifest `canonical_version` (SemVer comparison). The pin branch is encoded
   even though no doc-region uses `pin` today.
3. **Modes.** C9 runs in the **default (manifest) mode and in `--path` mode** (consumer
   SPECs carry the vendored copies and are checked via `--path` in the gate battery). When
   no manifest is present at the root (fixture / non-repo runs), C9 degrades to a no-op.
4. **Demonstrated closure.** The 2026-06-11 experiment was re-run on a throwaway copy with
   C9 in place: the manifest-only promotion is now caught - the spec home fails with 14
   C9 findings and each consumer SPEC fails with 14 - while the governance-state validator
   correctly remains at 0 findings (the ADR 0020 boundary is preserved; the coupling lives
   on the doc side). doc_gate self-test extended 39 -> 45.

## Consequences

- A manifest-only spec-region version write can no longer pass the gate battery silently;
  the refuse-by-gate semantics are restored for spec-regions at **battery/grounding time**.
- **Write-time refusal is not yet wired**: `canon-manifest-tool` runs only the
  governance-state validator as its transactional subprocess gate, so the tool itself still
  returns OK on a manifest-only spec-region write and leaves a state that the next doc_gate
  run rejects. Wiring doc_gate (including C9) as a subprocess gate of the coupled write is
  the deferred **`unit-record coupled write`** (the gate-then-write sequence R-3.1/R-3.2:
  build the coupled op, then promote `spec.powershell.part-a` 0.1.0 -> 1.0.0 across the
  manifest row + 42 markers). That work is re-placed into the revised program's bucket G4;
  until it lands, the operational rule "promote spec-regions only via the coupled op (once
  built); never via a manifest-only write" stands - now machine-detectable instead of
  human-enforced.
- Any future doc-region promotion mechanism must update the manifest row and every marker
  `version=` together, or C9 fails.

## Considered options

- **(a) Extend the governance-state validator (a new check H).** Rejected: violates the
  ADR 0020 tool boundary (validator D/G stay reference-code-scoped; doc_gate owns all
  doc-region inspection). This mirrors the earlier F5/D-gamma decision that placed the
  ADR<->SPEC integrity gate (C6) in doc_gate for the same reason.
- **(b) doc_gate C9 (chosen).** The check lives where every other doc-region rule lives;
  both verify modes (default + `--path`) already cover exactly the marker-bearing files.
- **(c) Only wire doc_gate into the CRUD tool now.** Rejected as the *first* step: without
  the gate-side check, a coupled write could not self-validate (a half-applied state would
  be undetectable) - gate-then-write, the mirror of the F5/D-gamma fix-then-gate precedent.
