<!--
  bash- SPEC skeleton template (English only, strictly ASCII). Renders into the
  project SPEC.md. SPEC is English-only per the canonical doc-language-policy
  (there is NO SPEC.ja twin).
  STRUCTURAL-ONLY (no vendored Part A): bash currently has a single consumer, so
  per the rule-of-two (AGENTS.md §2) NO bash spec home is extracted and NO Part A
  regions are vendored. Part A is authored INLINE in the consumer SPEC and is
  "canonical-in-principle" - canonical-quality common content that is simply not yet
  hoisted to a Layer-1 home. When a 2nd bash consumer appears, rule-of-two triggers:
  extract Part A to governance/spec/bash.md and switch this template's Part A to a
  vendored (L2 -> L3) region set, exactly as the powershell- SPEC template does.
  Parts B/C/D are the script-specific structural skeleton (canonical heading + role +
  FILL). The doc-region marker/policy contract is owned by ADR 0020 / doc_gate.
  Tokens: {{PROJECT_TITLE}} {{REPO_ROOT_RELPATH}}
-->
# Bash Script Specification (SPEC) — {{PROJECT_TITLE}}

> This SPEC documents `{{PROJECT_TITLE}}`. **Part A** is the repository-wide common
> specification, authored inline below (canonical-in-principle: there is no shared bash
> spec home yet, per the rule-of-two); **Parts B-D** are specific to this script.
> History lives in `CHANGELOG.md`; current and forward design lives here.

## Table of Contents

- Part A — Common Specification (authored inline; canonical-in-principle)
- Part B — Script-Specific Specification
- Part C — Quality Gates & Validation Checklist
- Part D — Known Pitfalls & Lessons Learned

# Part A — Common Specification (authored inline; canonical-in-principle)

> **Status: authored inline — NOT vendored, NOT inherited by reference.** Bash has a
> single consumer today, so per the [`AGENTS.md` rule-of-two]({{REPO_ROOT_RELPATH}}/AGENTS.md)
> no bash spec home exists and Part A is not a vendored region. The common conventions
> below are written directly in this SPEC and are canonical-in-principle; when a second
> bash subproject appears they are hoisted to `governance/spec/bash.md` and vendored.

<!-- AUTHOR Part A INLINE: write the repository-wide common conventions that apply to
     this (and any future) bash script, in canonical order. Until a bash spec home is
     extracted these sections carry NO doc-region marker (they are not a vendored
     region). Suggested canonical sections (include those that apply):
       A.1  Reference assets (canonical scripts, companion files, workspace paths)
       A.2  Source file format (shebang, set -euo pipefail, encoding/LF, layout)
       A.3  Banner / version convention
       A.4  Pipeline / phase architecture (numbering, registry, entry/exit, skip)
       A.5  Logging conventions (markers, line format, banners)
       A.6  Path handling
       A.7  Parameter / environment-property handling
       A.8  Error / diagnostic conventions and exit codes
       A.9  CSV / JSONL data conventions (if the script emits data contracts)
       A.10 Environment evaluation
       A.11 Static analysis (shellcheck clean; any documented suppressions)
       A.12 Documentation language policy (README bilingual; SPEC English-only)
       A.13 Development workflow -->

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

<!-- FILL: the short procedure to start a new script from this template - author Part A
     inline (canonical-in-principle), copy the Part B section headings, and wire up the
     Part C gates. When a second bash subproject appears, hoist Part A to a bash spec
     home and switch to vendoring (rule-of-two). -->
