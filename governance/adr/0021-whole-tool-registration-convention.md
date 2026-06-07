---
id: 0021
title: whole-tool-registration-convention
status: accepted
date: 2026-06-07
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §machinery"]
---

<!-- AI read-contract: authoritative for how a whole-tool (kind=tool) machinery unit is
     registered in governance/state/manifest.jsonl - the sentinel values its region-helper
     required fields carry, the whole-tool re-definition of `tested` (self-test green, not the
     ADR 0007 canon-test suite), and the fact that the ADR 0008 vendoring gate does not apply
     to whole-tool units (they are run-as-is / follow-latest and never vendored). Read SPEC
     §machinery for the current-truth view. Do not re-decide; supersede via a new ADR if
     reversing. -->

# 0021 — Whole-tool registration convention

## Context

`manifest.schema.json` lists the region-helper fields (`canonical_version`, `change_policy`,
`binding_mode`, `platform_scope`, `tested`) as `required` on **every** row, including a
`kind=tool` whole-tool machinery row, with no `allOf` branch differentiating whole-tool from
region units. But whole-tool machinery (psa.py, the canonical-drift-scanner, the
canon-manifest-tool, the canon-drift-trigger, the document-conformance-gate) carries **no
markers and no region body**: the whole-tool null convention for the region/hash fields lives
on the **observation** side (ADR 0016 / `observation.schema.json`, which permits null for those
fields when `granularity=whole-tool`), not on the manifest. The manifest's required fields must
therefore carry *some* value on a tool row.

A convention (option A: sentinel values) was first applied when the scanner was registered as a
whole-tool unit at P3.6 and recorded in `AGENTS.md` §8 - but deliberately **not** promoted to an
ADR, because one instance is too few (rule-of-two). The canon-manifest-tool and canon-drift-trigger
registered at P3a.3 are homogeneous whole-tool rows (same shape as the scanner) and do not stress
the convention. The discriminating **second** instance is **`psa.py`**, registered `kind=tool` at
P4: it is the first whole-tool whose `canonical_version` is its **own real, non-trivial SemVer**
(`4.3.0`, not `1.0.0`/`0.1.0`), so it exercises the "version = the tool's own SemVer" axis that the
homogeneous rows did not. With at least two instances now present, the rule-of-two threshold is met
and the convention is promoted from an `AGENTS.md` §8 note to this ADR.

## Decision

We will register a whole-tool machinery unit (`kind=tool`) by filling the manifest's
region-helper `required` fields with **sentinel values** that carry no region meaning:

- `change_policy` = `canonical`
- `binding_mode` = `follow-latest`
- `platform_scope` = `cross-platform` (see the note below)
- `canonical_version` = **the tool's own SemVer** (e.g. the scanner / CRUD tool / trigger /
  document-conformance-gate at `1.0.0`; `psa.py` at `4.3.0`)
- `tested` = `true` once the tool's **own self-test passes** - re-defined for whole-tool to mean
  self-test green, **not** the ADR 0007 canon behavioral test suite (which is region-unit-oriented).

The region/hash fields (`region_locator`, the `*_hash_*` fields, `hash_what`) are **not** manifest
fields; the whole-tool null convention for them is an **observation**-side concern (ADR 0016), so
no manifest null allowance is needed.

**Note on `platform_scope`.** Every whole-tool row to date is `cross-platform` (the tools are
pure-Python, stdlib-only, and run on any OS). The `windows-enhanced` / `windows-only` values remain
defined for **honest future classification**, mirroring the code-side per-unit `platform_scope`
(ADR 0013), where `windows-only` exists with 0 units for the same reason. A future Windows-bound
tool would be the first whole-tool to take a non-`cross-platform` value; until then the
`platform_scope` sentinel is effectively single-valued. This is **recorded, not deferred** - the
convention stands; only the `platform_scope` value-spread awaits a genuinely platform-heterogeneous
instance.

## Consequences

- Whole-tool rows satisfy the governance-state validator's required-field checks **without** a
  schema `allOf` branch - no schema change is needed.
- The validator's **check E** (the `kind=powershell-helper` bijection, 58 canon files <-> 58 rows)
  is unaffected: it is scoped to `powershell-helper`, so tool rows never perturb it.
- A whole-tool's `canonical_version` tracks the tool's own SemVer; it is **not** a release-gate
  signal. The ADR 0008 vendoring gate (`version >= 1.0.0`) does **not** apply to whole-tool units -
  they are run-as-is / follow-latest and are **never vendored** into a consumer (only the
  `reference-code/` region canon is vendored). A whole-tool below `1.0.0` is therefore not a
  "not-vendorable" state, it is simply that tool's own pre-release version.
- `tested = self-test green` for whole-tool is a deliberate re-definition; a reader must not expect
  an ADR 0007 canon behavioral suite behind a tool row's `tested=true`.
- The convention is now ADR-anchored and SPEC-viewable (current-truth view in SPEC §machinery), so a
  future session **follows** it rather than re-inventing it - applying this project's own
  "append-only decision log + curated current-truth view" pattern to the convention itself.

## Alternatives considered

- **A manifest-schema `allOf` branch** (region rows require the helper fields; whole-tool rows do
  not). Rejected for now: it adds schema complexity for a small, well-understood set, whereas the
  flat required-set + sentinel convention is already proven across five whole-tool instances. It can
  be revisited if whole-tool rows multiply or their shapes diverge.
- **Leave the convention as an `AGENTS.md` §8 note only** (no ADR). Rejected now that rule-of-two is
  met: an un-anchored convention risks silent re-invention, and the project's own ADR<->SPEC model
  (ADR-as-log + SPEC-as-current-truth) is exactly how such a settled, reused convention should be
  recorded.
