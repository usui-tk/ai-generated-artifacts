<!--
  powershell- README SUPPLEMENT template (English half; renders into the project README.md).
  Realizes the L1 doc-format readme items whose applicability.families includes
  powershell, as content_model = specific stubs: a canonical heading + a role /
  FILL guide. The actual content is project-specific and filled at L3. In L1 order:
     6  readme.action-reference    [powershell, bash]  conditional
     7  readme.phase-reference     [powershell, bash]  conditional
     8  readme.parameters          [powershell, bash]  required
    14  readme.risk-classification [powershell]         optional
    15  readme.hardware-os-scope   [powershell]         optional
  These interleave into the repo- README CORE (repo-readme-core.template.md) at
  its ASSEMBLE points, by L1 order:
    GROUP 1 (order 6-8)  -> after the CORE "CI status" section
    GROUP 2 (order 14-15) -> after the CORE "Troubleshooting" section
  Sharing note: action-reference / phase-reference / parameters are shared with
  bash (families = [powershell, bash]); the bash- supplement (d4) realizes the
  same three L1 items. L1 owns section identity, so these stubs carry no project
  content and remain coherent with L1 by construction (verified by TF (e)).
  Twin-file bilingual: this English half is strictly ASCII; the Japanese half is
  powershell-readme-supplement.ja.template.md, kept in lock-step.
-->

<!-- ===== ASSEMBLE GROUP 1: interleaves into the repo- README CORE after "CI status" (L1 order 6-8) ===== -->

## Action reference

<!-- readme.action-reference (L1 order 6; [powershell, bash]; conditional - include
     only if the artifact dispatches on an Action / subcommand parameter).
     FILL: list every Action, grouped by category (e.g. standard pipeline /
     specialty / admin). For each Action give a one-line purpose, whether it
     writes (mutates state), and any elevation requirement. -->

## Phase reference

<!-- readme.phase-reference (L1 order 7; [powershell, bash]; conditional).
     FILL: the internal phase / stage structure - phase IDs, what each phase does,
     execution order, and which phases are skipped in dry-run / evaluation mode. -->

## Parameters

<!-- readme.parameters (L1 order 8; [powershell, bash]; required).
     FILL: a complete parameter table (name | type | default | description),
     followed by a "Mutual exclusivity / parameter sets" subsection stating which
     parameters cannot be combined. -->

<!-- ===== ASSEMBLE GROUP 2: interleaves into the repo- README CORE after "Troubleshooting" (L1 order 14-15) ===== -->

## Risk classification

<!-- readme.risk-classification (L1 order 14; [powershell]; optional).
     FILL: classify Actions / modes by side-effect risk - read-only / evaluation
     vs mutating / destructive - and name the flag that gates mutation
     (e.g. -Execute). -->

## Supported OS and hardware

<!-- readme.hardware-os-scope (L1 order 15; [powershell]; optional).
     FILL: the supported target-OS and language matrix, plus host requirements
     (runtime version, privileges, required external tools). -->
