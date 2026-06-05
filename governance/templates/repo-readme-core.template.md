<!--
  repo- README CORE template (English half; renders into the project README.md).
  Realizes the L1 doc-format readme items whose applicability.families = all
  (the language-independent CORE), in L1 order:
    0 readme.disclaimer        (common-fixed)
    1 readme.license           (common-fixed)
    2 readme.why-exists        (common-parameterized)
    3 readme.folder-layout     (common-parameterized)
    4 readme.quick-start       (common-parameterized)
    5 readme.ci-status-table   (common-parameterized)
   11 readme.configuration     (conditional, specific)
   12 readme.self-verification (optional-feature, specific)
   13 readme.troubleshooting   (optional-feature, specific)
  Twin-file bilingual: this English half stays strictly ASCII; the Japanese
  half lives in repo-readme-core.ja.template.md and is kept in lock-step.
  Per-language / per-feature SUPPLEMENT sections (L1 order 6-10, 14-15) are
  authored in the powershell-/bash-/python- README supplement templates and
  interleave by L1 order at the ASSEMBLE points below. At L3
  reconstruction each section becomes a vendored region (L2 -> L3); the
  doc-region marker/hash contract is defined and applied by TF (e).
  Tokens: {{PROJECT_TITLE}} {{REPO_SLUG}} {{REPO_ROOT_RELPATH}}
-->
# {{PROJECT_TITLE}}

> Read this in [Japanese](./README.ja.md).

<!-- >>> CANONICAL unit_id=readme.disclaimer version=0.1.0 hash=108f4d4d82931e3e policy=canonical binding=follow-latest >>> -->
## ⚠️ Disclaimer

**USE AT YOUR OWN RISK.** This artifact is provided "AS IS" without warranty
of any kind, express or implied. The authors and contributors are not liable
for any damages, data loss, account suspension, network issues, disk space
exhaustion, or any other problems — direct or indirect — that may arise from
using, modifying, or distributing it.

By using this artifact, you acknowledge that:

* You are solely responsible for verifying that your use complies with the
  Terms of Service of any target service or site, and with all applicable
  laws and regulations.
* You are responsible for any consequences of your use (bandwidth costs,
  storage costs, rate-limiting, account or IP blocks, and similar).
* You should respect the rights of original authors — any retrieved material
  remains the intellectual property of its respective owners.
* You will review the source code and understand its behavior before running
  it in any environment.

Operate this artifact considerately. Respect any rate limits and do not bypass
built-in throttling. Avoid acting faster or more often than necessary.

<!-- FILL (optional): project-specific operational-risk notes, if any. -->

For the full disclaimer and self-responsibility terms that apply to all
artifacts in this repository, see the
[root README]({{REPO_ROOT_RELPATH}}/README.md)
([Japanese]({{REPO_ROOT_RELPATH}}/README.ja.md)).

<!-- <<< CANONICAL unit_id=readme.disclaimer <<< -->
<!-- >>> CANONICAL unit_id=readme.license version=0.1.0 hash=e44d509badd86ef1 policy=canonical binding=follow-latest >>> -->
## License

This project is part of the `{{REPO_SLUG}}` repository, which is licensed
under the **MIT License**. See the [`LICENSE`]({{REPO_ROOT_RELPATH}}/LICENSE)
file at the repository root for the full license text.

In short: you are free to use, modify, and distribute this software for any
purpose, provided that the original copyright and license notices are
preserved. The software is provided without warranty, as detailed in the
Disclaimer above and in the LICENSE file.

<!-- <<< CANONICAL unit_id=readme.license <<< -->
<!-- >>> CANONICAL unit_id=readme.why-exists version=0.1.0 hash=NONE policy=structural binding=follow-latest >>> -->
## Why this exists

<!-- FILL: 1-2 paragraphs. What manual or unmet need this artifact addresses,
     who it is for, and what it automates or provides end to end. -->

### Suitable for

<!-- FILL: bullet list of intended users / use cases (subject to the
     Disclaimer's TOS / IP-rights obligations above). -->

### Out of scope

<!-- FILL: bullet list of what this artifact deliberately does NOT do. -->

### Reader's roadmap

- For a **first-time operator**, read the Disclaimer above and skim the
  *Quick start* section below.
- For **internal behaviour and design**, see [`SPEC.md`](./SPEC.md).
- For the **test matrix and self-verification procedure**, see
  [`TESTING.md`](./TESTING.md).
- For **per-revision change history**, see [`CHANGELOG.md`](./CHANGELOG.md).
- For the **repository-wide LLM-agent operating guide**, see
  [`AGENTS.md`]({{REPO_ROOT_RELPATH}}/AGENTS.md) at the repository root.

<!-- <<< CANONICAL unit_id=readme.why-exists <<< -->
<!-- >>> CANONICAL unit_id=readme.folder-layout version=0.1.0 hash=NONE policy=structural binding=follow-latest >>> -->
## Folder layout

```
<!-- FILL: the artifact's directory tree, annotated. Always include the
     bilingual README pair and the English-only developer docs, e.g.: -->
{{PROJECT_TITLE}}
  README.md / README.ja.md     # End-user documentation (bilingual)
  SPEC.md                      # Developer / LLM specification (English only)
  TESTING.md                   # Verification procedure and results (English only)
  CHANGELOG.md                 # Per-revision history (English only)
```

If you only want to **use** the artifact, read this README. If you want to
**extend it or build a similar one**, also read `SPEC.md`.

<!-- <<< CANONICAL unit_id=readme.folder-layout <<< -->
<!-- >>> CANONICAL unit_id=readme.quick-start version=0.1.0 hash=NONE policy=structural binding=follow-latest >>> -->
## Quick start

<!-- FILL: minimal copy-pasteable steps to a first safe (dry-run / evaluation)
     invocation, then a real run. Use a fenced code block in the artifact's
     native language. -->

<!-- <<< CANONICAL unit_id=readme.quick-start <<< -->
<!-- >>> CANONICAL unit_id=readme.ci-status-table version=0.1.0 hash=NONE policy=structural binding=follow-latest >>> -->
## CI status

| Stage | Workflow | Status |
|:---|:---|:---|
<!-- FILL: one row per CI workflow. Workflow file names are project-specific
     (per SPEC Part A static-analysis / CI model); add a status badge per row. -->

This repository runs a multi-stage CI model (static analysis first, then
platform validation). See [`SPEC.md`](./SPEC.md) for the canonical CI model
and the per-stage definitions.

<!-- <<< CANONICAL unit_id=readme.ci-status-table <<< -->
<!-- ASSEMBLE: per-language / per-feature SUPPLEMENT sections (L1 order 6-10)
     interleave here, in L1 order, per applicability:
       6  readme.action-reference  [powershell, bash]  (conditional)
       7  readme.phase-reference   [powershell, bash]  (conditional)
       8  readme.parameters        [powershell, bash]  (required)
       9  readme.rule-catalog      [python]            (conditional)
       10 readme.output-format     [python]            (conditional)
-->

<!-- >>> CANONICAL unit_id=readme.configuration version=0.1.0 hash=NONE policy=structural binding=follow-latest >>> -->
## Configuration

<!-- Present only if the artifact reads external configuration (conditional).
     FILL: configuration files / environment variables / precedence and an
     example. Omit this section entirely if not applicable. -->

<!-- <<< CANONICAL unit_id=readme.configuration <<< -->
<!-- >>> CANONICAL unit_id=readme.self-verification version=0.1.0 hash=NONE policy=structural binding=follow-latest >>> -->
## Self-verification

<!-- Present only if the artifact ships a self-check / self-test (optional).
     FILL: how to run the artifact's own verification and what a pass looks
     like. Omit if not applicable. -->

<!-- <<< CANONICAL unit_id=readme.self-verification <<< -->
<!-- >>> CANONICAL unit_id=readme.troubleshooting version=0.1.0 hash=NONE policy=structural binding=follow-latest >>> -->
## Troubleshooting

<!-- Present only if there are known failure modes worth documenting (optional).
     FILL: symptom -> cause -> resolution entries. Omit if not applicable. -->

<!-- <<< CANONICAL unit_id=readme.troubleshooting <<< -->
<!-- ASSEMBLE: per-language / per-feature SUPPLEMENT sections (L1 order 14-15)
     interleave here, in L1 order, per applicability:
       14 readme.risk-classification [powershell] (optional)
       15 readme.hardware-os-scope   [powershell] (optional)
-->
