<!--
  bash- SPEC skeleton template (English only, strictly ASCII). Renders into the
  project SPEC.md. SPEC is English-only per the canonical doc-language-policy
  (there is NO SPEC.ja twin).
  Part A is NOT restated here: the rule-of-two triggered when the second Bash
  consumer appeared, so per the AGENTS.md par.6 Part A Inheritance Rule (ABSOLUTE)
  the 8 canonical Part A regions are vendored (L2 -> L3) from the spec home
  governance/spec/bash.md at L3 reconstruction (cross-L2 copy is forbidden).
  Parts B/C/D are the script-specific structural skeleton (canonical heading + role +
  FILL). The doc-region marker/hash contract is owned by ADR 0020 / doc_gate.
  Tokens: {{PROJECT_TITLE}} {{REPO_ROOT_RELPATH}}
-->
# Bash Script Specification (SPEC) — {{PROJECT_TITLE}}

> This SPEC documents `{{PROJECT_TITLE}}`. **Part A** is the repository-wide common
> specification, inherited by vendoring from the canonical spec home; **Parts B-D**
> are specific to this script. History lives in `CHANGELOG.md`; current and forward
> design lives here.

## Table of Contents

- Part A — Common Specification (vendored from the spec home)
- Part B — Script-Specific Specification
- Part C — Quality Gates & Validation Checklist
- Part D — Known Pitfalls & Lessons Learned

# Part A — Common Specification (vendored; reusable across all scripts)

> **Status: vendored from the spec home — do NOT restate or hand-edit.** Per the
> [`AGENTS.md` par.6 Part A Inheritance Rule (ABSOLUTE)]({{REPO_ROOT_RELPATH}}/AGENTS.md),
> this Part A is never free-hand copied into a script's SPEC. The canonical text is the
> spec home `governance/spec/bash.md`; this SPEC carries it as gate-managed vendored
> regions (marker + doc-region hash, verified by `doc_gate.py`). A project-specific
> extensions subsection (`A.x`) MAY follow the vendored regions, recording ONLY
> deviations or additions owned by this consumer.

<!-- ASSEMBLE: Part A = vendor the 8 canonical regions (L2 -> L3) from the spec home
     governance/spec/bash.md at reconstruction (doc_gate.py owns the doc-region
     marker/hash contract and the stamp/verify path). Region unit_ids, in canonical
     order:
       A.1  spec.bash.part-a.reference-assets
       A.2  spec.bash.part-a.source-file-format
       A.3  spec.bash.part-a.logging
       A.4  spec.bash.part-a.parameter-handling
       A.5  spec.bash.part-a.error-diagnostic
       A.6  spec.bash.part-a.static-analysis
       A.7  spec.bash.part-a.doc-language-policy
       A.8  spec.bash.part-a.development-workflow
     Conventions observed in only one consumer (phase/pipeline registries,
     env-property schemas, OS auto-detection, data-contract specifics) are NOT in the
     home; record them as A.x extensions or Part B sections owned by the consumer. -->

<!-- >>> CANONICAL unit_id=spec.bash.part-b.identity-io-phases version=0.1.0 hash=NONE policy=structural binding=follow-latest >>> -->
# Part B — Script-Specific Specification

<!-- The script's unique processing logic. B.1-B.4 are the canonical structural
     sections every script's Part B carries; add B.5+ for this script's specific
     algorithms, data structures, and per-phase detail. -->

## B.1 Identification

<!-- FILL: script name, one-line purpose, entry point, and supported invocations. -->

## B.2 Inputs

<!-- FILL: parameters/inputs consumed, env.properties / input files and formats, and
     preconditions. -->

## B.3 Outputs

<!-- FILL: output files/artifacts, their formats and locations, and exit codes. -->

## B.4 Phase Map

<!-- FILL: the ordered phase list (phase ID -> responsibility), consistent with the
     Part A phase-architecture conventions. -->

<!-- FILL (B.5+): one subsection per script-specific concern - algorithm, data
     structure, failure recovery, idempotency, and so on. -->

<!-- <<< CANONICAL unit_id=spec.bash.part-b.identity-io-phases <<< -->
<!-- >>> CANONICAL unit_id=spec.bash.part-c.quality-gates version=0.1.0 hash=NONE policy=structural binding=follow-latest >>> -->
# Part C — Quality Gates & Validation Checklist

<!-- The gate battery that must pass before any commit. Common categories are listed;
     fill specifics and include the conditional categories only where applicable. -->

### Static checks

<!-- Common: shellcheck reports no findings on the script(s); source is UTF-8 (LF) with
     the executable bit set and a correct shebang. FILL: any script-specific static
     rules or documented shellcheck suppressions. -->

### CI gates

<!-- Common: the CI workflow(s) pass (static-analysis stage, then any platform
     validation stage). FILL: the workflow file names for this script (or note "none
     yet" if the script has no CI workflow). -->

### Functional checks

<!-- FILL: the functional / offline tests that must pass (test IDs and what each
     asserts). -->

### Documentation checks

<!-- Common: README.md and README.ja.md updated in lock-step; SPEC / CHANGELOG reflect
     the change; this checklist re-checked. FILL: any script-specific documentation
     gates. -->

<!-- Conditional categories - include only if applicable:
       ### Cross-data checks   (if the script emits CSV / JSONL data contracts)
-->

<!-- <<< CANONICAL unit_id=spec.bash.part-c.quality-gates <<< -->
<!-- >>> CANONICAL unit_id=spec.bash.part-d.pitfalls version=0.1.0 hash=NONE policy=structural binding=follow-latest >>> -->
# Part D — Known Pitfalls & Lessons Learned

<!-- An append-only list of pitfalls discovered for THIS script (symptom -> cause ->
     resolution), each tagged with the revision where it was found.
     FILL: D.1, D.2, ... as they accumulate. -->

<!-- <<< CANONICAL unit_id=spec.bash.part-d.pitfalls <<< -->
## Appendix: How to seed a new script from this SPEC

<!-- FILL: the short procedure to start a new script from this template - vendor the
     8 Part A regions from governance/spec/bash.md (doc_gate stamp/verify), copy the
     Part B section headings, wire up the Part C gates, and record any deviations from
     the vendored Part A as consumer-owned A.x extensions (never edit a vendored
     region in place). -->
