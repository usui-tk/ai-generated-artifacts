---
id: 0020
title: doc-region-normalized-hash-contract
status: proposed
date: 2026-06-05
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §machinery"]
---

<!-- AI read-contract: authoritative for the DOC-region normalized-hash contract and the
     document-conformance gate boundary - (1) a doc-region normalized hash defined for
     common-fixed regions ONLY; (2) common-parameterized and specific regions are NOT
     hash-pinned but verified structurally; (3) the document-conformance gate owns all
     doc-region inspection and stamps PENDING -> real/structural; (4) the governance-state
     validator and canon-hash-restamp stay code/reference-code-scoped and are NOT extended
     to markdown. Complements ADR 0015 (code normalized-hash) and ADR 0019 (document vendor
     model). Proposed: the document-conformance gate implementation, the governance/SPEC.md
     machinery text, and the marker roll-out across the spec home + doc-set templates are
     follow-on work recorded against this ADR. If reversing a point, supersede via a new
     ADR (one decision = one ADR). -->

# 0020 — Doc-region normalized-hash contract + document-conformance gate boundary

Complements **[ADR 0015](./0015-canonical-normalized-hash-contract.md)** (the code
normalized-hash + marker contract) and **[ADR 0019](./0019-document-vendor-model-and-provenance-embedding.md)**
(document vendor model + provenance embedding). Relates
**[ADR 0014](./0014-document-governance-model.md)** (document governance model).

## Status

Proposed. This ADR fixes the contract that the document-conformance gate (TF e) is built
against; the gate implementation, the `governance/SPEC.md §machinery` text for the doc-region
contract, and the marker roll-out (spec home + all doc-set templates) are follow-on changes
recorded against this ADR.

## Context

ADR 0015 defines the canonical *normalized hash* for **code** (strip comments and string
literals, collapse whitespace, SHA-256, first 16 hex), and is enforced over `.ps1` /
reference-code by `psa.py` (PSA8001) and `canon-hash-restamp`. ADR 0019 establishes that
L2 canonical content is **vendored** into L3 through a managed region (marker + hash +
tool-sync), not referenced.

The document side now has real regions to govern: the powershell **spec home**
(`governance/spec/powershell.md`, TF c) and the **doc-set templates** (README CORE +
language supplements, SPEC / TESTING skeletons, CHANGELOG; TF d3 / d4). Their markers
currently carry `hash=PENDING`, and **no tool stamps or verifies a doc-region hash** - the
governance-state validator skips spec-region rows for gates D / G, and `canon-hash-restamp`
is code-only. The doc-region hash contract was deliberately left undefined until the gate
was designed.

The central difficulty is that doc content is **heterogeneous by `content_model`**:

- **common-fixed** - verbatim canonical prose, identical at every L3 site (e.g. the README
  disclaimer / license, the CHANGELOG header, the spec home Part A regions).
- **common-parameterized** - a common skeleton plus `{{TOKEN}}` / `<!-- FILL -->` regions
  whose resolved text differs per project (e.g. README why-exists, quick-start).
- **specific** - a canonical heading + role + FILL; the body is authored per project.

A verbatim section-level content hash is meaningful **only** for common-fixed regions. For
parameterized / specific regions a content hash would legitimately differ at every L3 site
(tokens and FILL are resolved per project), so it cannot be pinned.

## Decision

1. **Doc-region normalized hash is defined for `common-fixed` regions only.** The
   normalization, applied to the region body delimited by its markers, is: (a) remove HTML
   comments (`<!-- ... -->`) - these carry authoring notes, `FILL`, and `ASSEMBLE` directives,
   not rendered content; (b) normalize line endings to `LF`; (c) strip trailing whitespace on
   each line; (d) collapse runs of blank lines to a single blank line and strip leading /
   trailing blank lines; (e) UTF-8 encode; (f) SHA-256; (g) take the first 16 hex characters
   (same output width as ADR 0015, but computed over normalized prose, not code tokens).

2. **`common-parameterized` and `specific` regions are NOT hash-pinned.** Their marker carries
   a structural sentinel (`policy=structural`, no content hash) and they are verified by
   **structural conformance**: the region is present; its `unit_id` resolves to a real L1
   doc-format item; it appears in correct L1 order relative to its siblings; its heading
   matches the L1 item role; and the required `{{TOKEN}}` / `<!-- FILL -->` markers are
   present. The resolved body is project-owned at L3 and intentionally not pinned.

3. **The document-conformance gate (TF e) owns ALL doc-region inspection:** marker coherence
   (open/close pairing, `unit_id` agreement), common-fixed region hash stamp + verify,
   structural conformance for parameterized / specific regions, the doc-level YAML
   front-matter provenance pin (ADR 0019), and L1 item-membership (every region maps to a
   real L1 item; every required L1 item is present for the doc's applicability). The gate
   stamps the spec home and doc-set template markers from `hash=PENDING` to a real hash
   (common-fixed) or to the structural sentinel (parameterized / specific).

4. **Tool boundary (records the standing separation).** The governance-state validator stays
   code / state-focused: gates D (marker coherence) and G (hash integrity) remain scoped to
   `kind == powershell-helper` / reference-code, and `canon-hash-restamp` stays `.ps1` +
   reference-code only. **Neither is extended to markdown.** Doc-region inspection is the
   document-conformance gate's exclusive responsibility.

## Consequences

- Code hashing (ADR 0015) and document hashing (this ADR) are distinct contracts owned by
  distinct tools; neither leaks into the other's scope.
- The `content_model` value already carried by each L1 item directly decides hash-pinning
  (common-fixed) versus structural checking (parameterized / specific) - no new metadata is
  introduced.
- This resolves the TF d3 / d4 deferral: the templates intentionally carry no markers yet;
  the gate adds them - common-fixed regions get a canonical marker + real hash, parameterized
  / specific regions get a structural marker.
- Parameterized / specific regions are not cryptographically pinned; drift in their *skeleton*
  relative to L1 is caught structurally (heading, order, identity, required FILL markers),
  not by hash. This is acceptable because their body is project-owned by design.
- Follow-on (recorded against this ADR): implement the document-conformance gate
  (stamp / verify + structural + front-matter + L1-membership), add the doc-region contract
  text to `governance/SPEC.md §machinery`, and roll markers out across the spec home and all
  doc-set templates.
