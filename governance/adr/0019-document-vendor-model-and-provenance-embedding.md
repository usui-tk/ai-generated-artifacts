---
id: 0019
title: document-vendor-model-and-provenance-embedding
status: accepted
date: 2026-06-04
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §machinery"]
---

<!-- AI read-contract: authoritative for the document vendor model and provenance embedding -
     the three-layer model (L1 language-independent format / L2 language template = common +
     specific / L3 rendered doc-set); the rule that L2-common content is VENDORED into L3 via
     a managed region (marker + hash + tool-sync), NOT referenced; the two-level provenance
     embedding (doc-level YAML front-matter pin + region-level markers) and the two-level
     staleness trigger; language-independence with variance as explicit applicability metadata
     (no conditional fold-in); and the localization of heavy machinery to L2-common vendored
     regions. Refines ADR 0014; relates ADR 0011 / ADR 0015 / ADR 0018. Evolves AGENTS.md
     section 6 (Part A Inheritance Rule) and the M5 register TR-SPEC-2; the actual section-6
     text edit is a separate [AUTH] AGENTS.md change recorded against this ADR. Read
     on-demand. If reversing a point, supersede via a new ADR (one decision = one ADR). -->

# 0019 - Document vendor model + provenance embedding

Refines **[ADR 0014](./0014-document-governance-model.md)** (document governance model).
Relates [ADR 0011](./0011-canon-change-management-governance.md) (change management),
[ADR 0015](./0015-canonical-normalized-hash-contract.md) (marker + normalized-hash contract),
and [ADR 0018](./0018-template-canon-version-model.md) (template-canon version model).
Evolves `AGENTS.md` section 6 (Part A Inheritance Rule, ABSOLUTE) and register TR-SPEC-2.

## Status

Accepted. The `AGENTS.md` section-6 text edit is a separate `[AUTH]` change recorded against
this ADR (it is the highest-scrutiny edit per the plan: explicit authorization + ADR rationale
+ a checkpoint that every clause section 6 guaranteed is preserved or consciously superseded,
never silently weakened).

## Context

ADR 0014 established the document governance model (classes A / B / C; the document-template
canon; a conformance gate *lighter* than the code drift gate; the class-(B) reconstruction
procedure). `AGENTS.md` section 6 (Part A Inheritance Rule, ABSOLUTE), register TR-SPEC-2, and
anti-pattern AP-1 require a subproject SPEC's Part A to be a **reference declaration** to the
neutral common spec, never restated inline - a rule added after the `c40755c` regression, where
hand-copied Part A text silently drifted.

Two forces were not weighed when those rules were written:

- **Cross-repo + LLM resolvability.** A separate repository (Deploy-Drivers, the P7 target)
  whose docs only *reference* the central common spec forces an LLM working in that repo to
  fetch and resolve a cross-repo pointer it may not have in context. Inline content is
  self-contained.
- **Human readability.** A reader wants the content present, not "see central repo section X."

Crucially, the marker + normalized-hash machinery (ADR 0015) and the consumer-pin / canon-version
model (ADR 0018) **did not exist** when section 6 was written. With them, *managed* duplication
(marker-delimited, hash-verified, tool-synced) is drift-safe in a way that hand-restating is
not: the very drift section 6 feared is now mechanically detected.

The document model resolves into **three layers**:

- **L1 - document format.** Language-independent, item-level definitions (the item set,
  structure, roles, applicability). Light / structural.
- **L2 - language template** (e.g. PowerShell). Item-level content, split into a **common
  part** (sourced by copy from the code-governance canon, e.g. `governance/spec/<family>.md`)
  and a **subproject-specific part**.
- **L3 - the project's actual doc-set**, rendered from L2, conforming to L1.

## Decision

1. **Three-layer model.** L1 (language-independent format), L2 (language template = common +
   specific), L3 (rendered doc-set). The format (L1) is **one**, shared across all projects and
   languages; per-language differences (descriptive examples, etc.) are *content* at L2/L3, not
   structural forks.

2. **L2-common is VENDORED into L3 by managed region, not referenced.** The common part of a
   language template is copied into each L3 doc inside a marker-delimited managed region
   (ADR 0015), hash-verified, tool-synced. This is the document analog of code vendoring:
   consumers are self-contained; drift is *detected*, not prevented by forbidding the copy.

3. **`AGENTS.md` section 6 evolves.** The Part A Inheritance Rule changes from "Part A is a
   reference declaration, never restated" to "**Part A common content is vendored via a managed
   region (marker + hash + tool-sync); *hand*-restating (unmanaged duplication) remains
   prohibited (AP-1)**." The no-drift guarantee section 6 provided is preserved by the
   marker/hash drift mechanism rather than by forbidding the copy. This revises TR-SPEC-2. The
   section-6 text edit is a separate `[AUTH]` change recorded against this ADR.

4. **Provenance is embedded at two levels.**
   - **Doc-level (coarse).** Every L3 doc carries a YAML front-matter `doc-provenance` block - a
     **visible** governance badge (GitHub renders front-matter as a table) and the coarse
     staleness pin. The layer is named in the keys so the rendered table is human-meaningful;
     `#` comments add raw-source detail (stripped from the rendered table):

     ```
     ---
     doc-provenance:
       layer-1-format: <semver>     # L1: language-independent document format
       layer-2-template: <semver>   # L2: language template canon (ADR 0018 Axis-2)
       rendered: <date>
     ---
     ```

     `README.md` and `README.ja.md` carry **identical** front-matter (language-neutral;
     bilingual-lock-step-safe).
   - **Region-level (fine).** Each vendored common region carries a managed-region marker per the
     ADR 0015 contract; the comment leader adapts per language (`#` in code, `<!-- ... -->` in
     Markdown) while the token grammar (`unit_id` / `version` / `hash` / `policy` / `binding`)
     is fixed.

5. **Two-level mechanical trigger.** The conformance gate + drift scanner compute staleness: a
   doc-level pin behind the current L1-format or L2-template-canon version -> the doc needs
   **re-reconstruction** (coarse); a region hash not matching the current canon hash -> that
   region needs **re-sync** (fine). Cross-repo consumers are evaluated by fetching the central
   canon (the P7 gate model).

6. **Language-independence; no conditional fold-in.** L1 item definitions are language-neutral.
   Variance across families / topologies / consumers (e.g. a `CHANGELOG` present for PowerShell
   but not Bash; a feature present in only one consumer) is represented as **explicit per-item
   applicability metadata**, never as conditional template assembly ("fold-in"). Per-language
   content lives at L2/L3 as instance data. This keeps the item model MECE and the impact
   analysis mechanical.

7. **Governance weight is localized.** The heavy machinery (marker + normalized hash) applies
   **only** to L2-common vendored regions, inherited from the code canon. L1 (format) and L3
   (structure) are governed by **light structural conformance** (item-set membership, bilingual
   lock-step, encoding, links, provenance presence). This reaffirms ADR 0014's "conformance gate
   lighter than the code drift gate," localizing the heavy part to where byte-fidelity matters.

8. **Propagation model.** A change to the code-governance canon propagates to L2-common regions
   (re-vendor) and thence to L3 (marker/hash sync). A change to the L1 format propagates to the
   L2 templates and thence to L3 (re-reconstruction). This realizes the **single project ->
   governance -> all projects** path: a doc item that proves useful in one project is promoted
   to the governance baseline (L1 format and/or L2-common) and propagated to all *applicable*
   projects, the applicable set being a mechanical manifest query.

## Consequences

- L3 docs are **self-contained**: an LLM or a human in any repo (including the separate
  Deploy-Drivers repo) reads the content inline, with no cross-repo fetch required to understand
  it.
- Duplication of the common part is **managed** (marker + hash + tool-sync), so it does not
  reintroduce the AP-1 hand-restate drift; drift is mechanically detected at the region level.
- The visible front-matter table is a **governance badge**: a human sees at a glance that a doc
  is under governance and at which L1/L2 versions.
- **Mechanical traceability of baseline changes** - the project's core value - now extends to
  documents, at two granularities (doc-level pin, region-level hash).
- The document and code models share **one mental model** (vendoring + markers + hash + consumer
  pin), reducing cognitive load.
- **Cost / negative:** section 6 (ABSOLUTE) and TR-SPEC-2 must be revised (a high-scrutiny
  `[AUTH]` edit); the conformance gate and drift scanner must learn the Markdown region-marker
  leader (`<!-- ... -->`) and the front-matter pin; every L3 doc gains a front-matter block (a
  small, deliberate, visible addition).
- **No new phase:** this refines ADR 0014 (the document analog of ADR 0007 + ADR 0008) by
  specifying the L2->L3 mechanism (vendor, not reference) and provenance embedding; TF + the
  P5-P7 migration exits absorb it.

## Alternatives considered

- **Reference-only** (the original TR-SPEC-2 / section 6). Rejected: fragile for cross-repo LLM
  resolution and poor for human readability; its original motivation (drift avoidance) is now
  met by the marker/hash machinery instead.
- **Invisible doc-level provenance** (HTML comment). Considered and rejected in favor of visible
  YAML front-matter, on the explicit ground that a human should be able to *see* that a doc is
  under governance; the front-matter table is that badge. (Region-level markers remain comments,
  since they sit mid-body and must not clutter the prose.)
- **Code-grade hashing of all document content.** Rejected: documents legitimately differ in
  descriptive examples by language and implementation, so byte-identity hashing of whole docs is
  wrong; the hash applies only to L2-common vendored regions, where the content *is* copied
  verbatim from the canon.
- **Family-stratified templates assembled by conditional fold-in.** Rejected: conditional
  assembly breaks MECE completeness and mechanical impact analysis; variance is carried as
  explicit applicability metadata instead.
