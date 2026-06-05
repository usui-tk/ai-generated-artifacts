<!--
  powershell- SPEC skeleton template (English only, strictly ASCII). Renders into the
  project SPEC.md. SPEC is English-only per the canonical doc-language-policy
  (spec home A.12) - there is NO SPEC.ja twin.
  Part A is NOT restated here: per decision B1 and the AGENTS.md §6 Part A Inheritance
  Rule (ABSOLUTE), the 14 canonical Part A regions are vendored (L2 -> L3) from the spec
  home governance/spec/powershell.md at L3 reconstruction (cross-L2 copy is forbidden).
  Parts B/C/D are the script-specific skeleton (canonical heading + role + FILL). The
  doc-region marker/hash contract is owned by TF (e).
  Tokens: {{PROJECT_TITLE}} {{REPO_ROOT_RELPATH}}
-->
# PowerShell Script Specification (SPEC) — {{PROJECT_TITLE}}

> This SPEC documents `{{PROJECT_TITLE}}`. **Part A** is the repository-wide common
> specification, inherited by reference from the canonical spec home; **Parts B-D**
> are specific to this script. History lives in `CHANGELOG.md`; current and forward
> design lives here.

## Table of Contents

- Part A — Common Specification (inherited by reference; see the spec home)
- Part B — Script-Specific Specification
- Part C — Quality Gates & Validation Checklist
- Part D — Known Pitfalls & Lessons Learned

# Part A — Common Specification (inherited; reusable across all scripts)

> **Status: inherited by reference — do NOT restate.** Per the
> [`AGENTS.md` §6 Part A Inheritance Rule (ABSOLUTE)]({{REPO_ROOT_RELPATH}}/AGENTS.md),
> this Part A is never copied into a script's SPEC by hand. The canonical text is the
> spec home; this SPEC inherits it.

<!-- ASSEMBLE: Part A = vendor the 14 canonical regions (L2 -> L3) from the spec home
     governance/spec/powershell.md at reconstruction (TF (e) defines and applies the
     doc-region marker/hash contract). Region unit_ids, in canonical order:
       A.1  spec.powershell.part-a.reference-assets
       A.2  spec.powershell.part-a.source-file-format
       A.3  spec.powershell.part-a.banner-version
       A.4  spec.powershell.part-a.phase-architecture
       A.5  spec.powershell.part-a.logging
       A.6  spec.powershell.part-a.path-handling
       A.7  spec.powershell.part-a.parameter-handling
       A.8  spec.powershell.part-a.error-diagnostic
       A.9  spec.powershell.part-a.csv-conventions
       A.9  spec.powershell.part-a.jsonl-conventions
       A.10 spec.powershell.part-a.environment-eval
       A.11 spec.powershell.part-a.static-analysis
       A.12 spec.powershell.part-a.doc-language-policy
       A.13 spec.powershell.part-a.development-workflow
     Until reconstruction, consult the spec home for the authoritative Part A text. -->

# Part B — Script-Specific Specification

<!-- The script's unique processing logic. B.1-B.4 are the canonical structural
     sections every script's Part B carries; add B.5+ for this script's specific
     algorithms, data structures, and per-phase detail. -->

## B.1 Identification

<!-- FILL: script name, one-line purpose, entry point, and supported invocations. -->

## B.2 Inputs

<!-- FILL: parameters/inputs consumed, input files and formats, and preconditions. -->

## B.3 Outputs

<!-- FILL: output files/artifacts, their formats and locations, and exit codes. -->

## B.4 Phase Map

<!-- FILL: the ordered phase list (phase ID -> responsibility), consistent with the
     Part A phase-architecture conventions. -->

<!-- FILL (B.5+): one subsection per script-specific concern - algorithm, data
     structure, failure recovery, idempotency, and so on. -->

# Part C — Quality Gates & Validation Checklist

<!-- The gate battery that must pass before any commit. Common categories are listed;
     fill specifics and include the conditional categories only where applicable. -->

### Static checks

<!-- Common: psa.py reports 0 errors / 0 warnings / 0 info; .ps1/.psm1/.psd1 source is
     UTF-8 with BOM + CRLF. FILL: any script-specific static rules or suppressions. -->

### CI gates

<!-- Common: the multi-stage CI workflows pass (static-analysis stage, then platform
     validation stage(s)). FILL: the workflow file names for this script. -->

### Functional checks

<!-- FILL: the functional / offline tests that must pass (test IDs and what each
     asserts). -->

### Documentation checks

<!-- Common: README.md and README.ja.md updated in lock-step; SPEC / TESTING /
     CHANGELOG reflect the change; this checklist re-checked. FILL: any script-specific
     documentation gates. -->

<!-- Conditional categories - include only if applicable:
       ### Cross-data checks            (if the script emits CSV / JSONL data contracts)
       ### Debug Trace Facility checks  (if the Part A debug-trace facility is present)
-->

# Part D — Known Pitfalls & Lessons Learned

<!-- An append-only list of pitfalls discovered for THIS script (symptom -> cause ->
     resolution), each tagged with the revision where it was found.
     FILL: D.1, D.2, ... as they accumulate. -->

## Appendix: How to seed a new script from this SPEC

<!-- FILL: the short procedure to start a new script from this template - inherit
     Part A by reference, copy the Part B section headings, and wire up the Part C
     gates. -->
