<!--
Thank you for opening a PR. Please follow the checklist below.
This repository is a personal AI-assisted knowledge base; PRs are
reviewed on a best-effort basis with no SLA. See CONTRIBUTING.md
for the full guidelines.
-->

## What this PR changes

<!-- 1–3 sentence summary. -->

## Artifact path(s) touched

<!--
e.g.
- scripts/aws/ol-aws-ami-builder/SPEC.md §A.7
- scripts/aws/ol-aws-ami-builder/SPEC.md §A.7
- scripts/aws/ol-aws-ami-builder/README.md  (cross-reference update)
-->

## Why

<!-- The motivation behind the change. Skip if the title already says it. -->

## Checklist

- [ ] **README sync**: if `README.md` is touched, `README.ja.md` is updated in the same PR (English is the master). Per the repository-wide documentation language policy (root `README.md` "Language Policy"), only `README.md` has a Japanese counterpart; `SPEC.md`, `TESTING.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md` are English only.
- [ ] If a project-level `SPEC.md` is touched, the corresponding `Part C — Quality Gates & Validation Checklist` has been re-checked.
- [ ] If a PowerShell script is touched, `python3 scripts/python/powershell-static-analyzer/psa.py <script>.ps1` reports `0 errors / 0 warnings / 0 info`.
- [ ] No real secrets, internal hostnames, account IDs, ARNs, or other private data are included in this PR (including in commit messages and log excerpts).
- [ ] Cross-references (e.g. `§B.5`, `D.10`, links to other files) are still valid after the change.
- [ ] If a script's behaviour changed, the `Lines : NNNN` field in the README (if present) has been updated to match the new script line count.

## Downstream impact

<!--
If this changes a SPEC convention, list the other files that may need
follow-up updates in a future PR. If nothing else is affected, write "None."
-->
