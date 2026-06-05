<!--
Thank you for opening a PR. Please follow the checklist below.
This repository is a personal AI-assisted knowledge base; PRs are reviewed on a
best-effort basis with no SLA. See CONTRIBUTING.md for the full guidelines.
-->

## What this PR changes

<!-- 1-3 sentence summary. -->

## Artifact path(s) touched

<!--
e.g.
- {{EXAMPLE_ARTIFACT_PATH}}/SPEC.md (Part A.7)
- {{EXAMPLE_ARTIFACT_PATH}}/README.md (cross-reference update)
-->

## Why

<!-- The motivation behind the change. Skip if the title already says it. -->

## Checklist

- [ ] **Documentation language policy**: bilingual documents carry their Japanese content per their member's mode - `README.md` has a `README.ja.md` twin (English is the master), and `CODE_OF_CONDUCT.md` / `CONTRIBUTING.md` / `SECURITY.md` carry an in-file Japanese-language section. `SPEC.md`, `TESTING.md`, `CHANGELOG.md`, and `LICENSE` are English only. If a bilingual document is touched, its Japanese counterpart/section is updated in the same PR.
- [ ] If a project-level `SPEC.md` is touched, the corresponding `Part C - Quality Gates & Validation Checklist` has been re-checked.
- [ ] If a PowerShell script is touched, `python3 quality-tools/powershell-static-analyzer/psa.py <script>.ps1` reports `0 errors / 0 warnings / 0 info`.
- [ ] No real secrets, internal hostnames, account IDs, ARNs, or other private data are included in this PR (including in commit messages and log excerpts).
- [ ] Cross-references (e.g. `Part B.5`, `D.10`, links to other files) are still valid after the change.
- [ ] If a script's behaviour changed, any line-count field in the README has been updated to match.

## Downstream impact

<!--
If this changes a SPEC convention, list the other files that may need follow-up
updates in a future PR. If nothing else is affected, write "None."
-->
