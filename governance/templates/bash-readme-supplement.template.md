<!--
  bash- README SUPPLEMENT template (English half; renders into the project README.md).
  Realizes the L1 doc-format readme items whose applicability.families includes bash,
  as content_model = specific stubs (canonical heading + role / FILL guide). In L1 order:
     6  readme.action-reference  [powershell, bash]  conditional
     7  readme.phase-reference   [powershell, bash]  conditional
     8  readme.parameters        [powershell, bash]  required
  All three are shared with powershell (families = [powershell, bash]); the powershell-
  supplement realizes the same three L1 items. L1 owns section identity, so these stubs
  carry no project content and remain coherent with L1 by construction (verified by TF (e)).
  These interleave into the repo- README CORE at its ASSEMBLE GROUP 1 point (after the
  CORE "CI status" section), by L1 order. bash has no items in L1 order 14-15, so there
  is no GROUP 2 here.
  Twin-file bilingual: this English half is strictly ASCII; the Japanese half is
  bash-readme-supplement.ja.template.md, kept in lock-step.
-->

<!-- ===== ASSEMBLE GROUP 1: interleaves into the repo- README CORE after "CI status" (L1 order 6-8) ===== -->

## Action reference

<!-- readme.action-reference (L1 order 6; [powershell, bash]; conditional - include
     only if the artifact dispatches on an action / subcommand argument).
     FILL: list every action, grouped by category. For each action give a one-line
     purpose, whether it writes (mutates state), and any privilege requirement. -->

## Phase reference

<!-- readme.phase-reference (L1 order 7; [powershell, bash]; conditional).
     FILL: the internal phase / stage structure - phase IDs, what each phase does,
     execution order, and which phases are skipped in dry-run / evaluation mode. -->

## Parameters

<!-- readme.parameters (L1 order 8; [powershell, bash]; required).
     FILL: a complete option / argument table (name | type | default | description),
     followed by a "Mutual exclusivity / option groups" subsection stating which
     options cannot be combined. -->
