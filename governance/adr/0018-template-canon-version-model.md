---
id: 0018
title: template-canon-version-model
status: accepted
date: 2026-06-04
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §machinery"]
---

<!-- AI read-contract: authoritative for the template-canon version model - the two version
     axes (Axis 1 = a per-template body version for provenance; Axis 2 = a single
     template-canon version that is the reconstructability gate and the consumer pin target),
     the rule that the gate axis follows the unit of delivery (per-unit for vendored code,
     per-set for reconstructed doc-sets), and the two write paths. Refines ADR 0014 §2: each
     template still carries a SemVer canonical_version (Axis 1), but the reconstructability
     release gate is keyed on the canon version (Axis 2), NOT the per-template version. Read
     on-demand. If reversing a point, supersede via a new ADR (one decision = one ADR). -->

# 0018 - Template-canon version model (two-axis)

Refines **[ADR 0014](./0014-document-governance-model.md)** (document governance model) §2.
Complements [ADR 0008](./0008-canon-release-model.md) (code canon release model) and
[ADR 0011](./0011-canon-change-management-governance.md) (change-management governance).

## Status

Accepted.

## Context

ADR 0014 §2 elevated `governance/templates/` to a document-template canon "at code parity":
each template carries a SemVer `canonical_version` with an ADR-0008-style release gate
(`< 1.0.0` = not reconstructable; `>= 1.0.0` = reconstructable), and the version-gate
**granularity** (module-wide vs per-template) was deferred to Template Finalization (TF.1).

Pinning that granularity surfaced two distinct needs:

1. **Per-template body provenance.** Template bodies evolve at different cadences; a
   reconstructed doc-set wants to record which template body produced each file.
2. **A single reconstructability signal for a doc-SET.** Class-(B) docs are RECONSTRUCTED as
   a set (not vendored per file), so a consumer pins "reconstructed from template-canon vX" -
   a scalar, set-level coordinate.

Folding both into ONE per-template version field (the literal reading of ADR 0014 §2) makes
reconstructability a multi-version AND-predicate over the target's templates, makes
consumer-staleness a vector comparison, and forces a "which templates get promoted" rule on a
set-level conformance pass. Notably, the code canon already carries two version coordinates -
a per-unit `canonical_version` in the manifest AND a module `ModuleVersion` in the `.psd1` -
but for CODE the release/vendoring gate is the per-unit version (ADR 0008 §4), because code is
vendored per unit. For TEMPLATES the unit of delivery is the doc-set (reconstruction), so the
gate axis should follow the unit of delivery rather than copy code's per-unit gate verbatim.

## Decision

The template canon carries **two version axes**.

1. **Axis 1 - per-template body version.** Each `kind=template` manifest row carries its own
   SemVer `canonical_version`, tracking that template body's evolution (provenance).
   Per-template versions MAY diverge; the bilingual `README`/`README.ja` pair is
   **version-locked**. Axis 1 is **NOT** the reconstructability gate.
2. **Axis 2 - template-canon version.** A single SemVer at **`governance/templates/VERSION`**
   (the document analog of the code canon's `.psd1` `ModuleVersion`) is the
   **reconstructability gate coordinate and the consumer pin target**: `< 1.0.0` = the
   template canon is NOT reconstructable into any target; `>= 1.0.0` = reconstructable. A
   reconstructed doc-set records provenance as `reconstructed from template-canon vX` (a
   scalar, not a per-template vector).
3. **The gate axis follows the unit of delivery.** Code is vendored per unit, so ADR 0008's
   per-unit version is the vendoring gate; templates are reconstructed per doc-SET (class-(B)),
   so the canon version (Axis 2) is the reconstructability gate. This is an intentional,
   bounded divergence from ADR 0008's per-unit model, justified by the class-(A) vendor /
   class-(B) reconstruct distinction (ADR 0014 §1).
4. **Write paths.** Axis 1 is a manifest field, so it is written **only through the
   `canon-manifest-tool` CRUD tool** (ADR 0011 §2; self-validated, transactional). Axis 2
   (`governance/templates/VERSION`) is **NOT a manifest row**, so it is a **release-commit
   artifact** edited at each template-canon release and verified by the document-conformance
   gate - exactly as the code canon's `.psd1` `ModuleVersion` sits outside the manifest. The
   ADR 0011 manifest-row write-path boundary (built at P3a.1) is therefore **unaffected**.
5. **Initial state.** Both axes ship at `1.0.0` at the TF freeze (TF.3); Axis 2 is bumped at
   each subsequent template-canon release / sync.

This **refines ADR 0014 §2**: "each template carries a SemVer `canonical_version`" stays true
(Axis 1), but the reconstructability release gate is keyed on **Axis 2** (the canon version),
not on the per-template version.

## Consequences

- Reconstructability and consumer-staleness become **scalar** comparisons against Axis 2 (not
  multi-version predicates), and a set-level conformance pass promotes the canon version (Axis
  2) while per-template versions (Axis 1) track body edits independently - the operational
  simplifications that motivated the split.
- Per-template **provenance** and independent cadence are preserved (Axis 1).
- The document-conformance gate (built at TF.2) reads `governance/templates/VERSION` for the
  reconstructability check (the C5 check; see the M5 template-requirements register
  TR-TPLCANON-3/8).
- Divergence from ADR 0008's per-unit gate is intentional and **bounded to the
  document/reconstruction case**; the code canon's per-unit vendoring gate is unchanged.
- A `kind=template` row, like a whole-tool row, fills the region-helper `required` fields with
  sentinels (the manifest schema is flat, no `allOf` branch); whether to promote that
  sentinel convention to an ADR remains the separate `[P4.4]` decision, unchanged by this ADR.
- **Cost / negative:** a new datum (`governance/templates/VERSION`) plus the discipline of
  bumping it at each template-canon release, and the bilingual-pair version-lock on Axis 1.
- **No new phase / no renumbering:** TF (per ADR 0014 §5) freezes the version/release gate;
  this ADR is the durable record of the granularity TF.1 pinned.

## Alternatives considered

- **Module-wide single axis** (all per-template versions kept in lockstep = one module
  version). Rejected as the sole model: it discards per-template provenance and independent
  cadence. The two-axis model keeps the set-level gate simplicity AND per-template provenance.
- **Per-template single axis as the gate** (the literal ADR 0014 §2). Rejected: reconstructability
  becomes a multi-version AND-predicate, consumer-staleness a vector, and a set-level
  conformance pass needs a per-template promotion rule - operationally heavy, with no machine
  safety net (templates are out of the drift scanner's scope, ADR 0016 F3 / ADR 0014 §2).
- **Carry the canon version inside the manifest** (a special module row or a new manifest
  field). Rejected: keeping Axis 2 OUTSIDE the per-row manifest (a `VERSION` file, mirroring
  `.psd1`) needs no manifest-schema change and stays outside the ADR 0011 CRUD write-path
  boundary.
