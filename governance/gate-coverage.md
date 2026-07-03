# Gate-Coverage Inventory — documented claim vs actual verification scope

> **Purpose (G3(b); absorbs the 2026-06-11 step-8 item).** Twice, a gate's *documented
> claim* and its *actual verification scope* diverged silently: the spec-region
> version-coupling hole (no gate coupled doc-region marker versions to the manifest —
> closed by ADR 0022/C9) and the Layer-0 root docs (no gate scanned them at all —
> closed by ADR 0026/refcheck). This inventory states, for EVERY gate, exactly what it
> verifies, how it is invoked, and its named limitations, so the next divergence is a
> documentation bug rather than a discovery. **Update rule:** any change to a gate's
> scope or check set updates this file in the same patch (Doc-Touching discipline).
> Unregistered governance doc (like STATUS/SPEC); English/ASCII per the label-language
> policy.

## The battery (governance grounding scope)

| # | Gate | Invocation | Verified claim (actual scope) |
|:--|:--|:--|:--|
| 1 | governance-state validator | `python3 quality-tools/governance-state-validator/validate_state.py` | Checks A–G over `governance/state/` + schemas: A manifest rows validate against `manifest.schema.json` (incl. the kind=project allOf branch); B observation rows validate (skipped when none); C every `canonical_location` exists (file OR directory); D manifest↔marker coherence **for `kind=powershell-helper` only**; E canon-file↔helper-row bijection (`reference-code/powershell/{Public,Private}` only); F canonical-JSONL format; G marker hash integrity (**powershell-helper only**) |
| 2 | validator self-test | `python3 .../test_validate_state.py` | 17 synthetic-fixture cases incl. project-row green + out-of-enum maturity caught |
| 3 | canon-hash-restamp | `python3 quality-tools/canon-hash-restamp/restamp.py --check` | The 58 canon marker hashes match the ADR 0015 normalized-hash contract (**reference-code/powershell only**; never markdown — ADR 0020 boundary) |
| 4 | psa.py | `python3 quality-tools/powershell-static-analyzer/psa.py -r --config reference-code/powershell/.psa.config.json reference-code/powershell` (+ `test_psa_rules.py`, `--self-check`) | PowerShell static analysis (27+ rules) over the canon; **config flag is mandatory** — without it the canon-specific exemptions are wrong. Self-test 281 cases; `--self-check` = SPEC↔RULES sync |
| 5 | canonical-drift-scanner | `python3 quality-tools/canonical-drift-scanner/scanner.py --root .` (+ `test_scanner.py` 16) | Body-hash drift for **region-kind units with populated `consumers[]`** + whole-tool null rows for tool kinds. `kind=project` / `governance-doc` are out of scope BY DESIGN (granularity None). Emits transient observation run-logs — **never stage them** |
| 6 | canon-manifest-tool self-test | `python3 quality-tools/canon-manifest-tool/test_tool.py` | 26 cases: transactional CRUD incl. rollback-on-finding, kind=project lifecycle rows, marker-coupled `update` writes REFUSED, and the **`promote` coupled op** (R-3.1, ADR 0022): doc-region-only scope, dry-run purity, non-advancing-version + marker-less-target refusals, and gate-failure -> byte-identical rollback of ALL touched files. **Per-op gate set of `promote`:** validator + doc_gate default + doc_gate `--path` over every consumers[] file (fail-safe REFUSE if either gate script is absent) |
| 7 | canon-drift-trigger self-test | `python3 quality-tools/canon-drift-trigger/test_trigger.py` | 33 cases: observation→change-request derivation + **the P7a decision gate** (ADR 0027): machine impact measurement (`impact` — consumers[] + both marker frames), kind→SemVer→tier mapping, **heavy-tier refusal** without enumerated consumers + migration + full-ADR, `propose` reconcile-back emission, drift requests carrying computed impact with kind pending. Emit-only (no state store; the ledger is P8's) |
| 8 | document-conformance gate | `python3 quality-tools/document-conformance-gate/doc_gate.py` (+ `--path <SPEC>`, `--reconstructed <files>`, `test_doc_gate.py` 45) | Default mode: **manifest-registered md units only** (`kind=template` + `spec-region` canonical_locations; 18 files) — front-matter, marker coherence, doc-region hashes (C-checks), **C9 version coupling** (ADR 0022: follow-latest marker `version=` == manifest `canonical_version`; pin may lag never lead), C6 ADR↔SPEC integrity (full-manifest mode only). `--path`: same per-file checks on named files (consumer SPECs). `--reconstructed`: L3 doc-set conformance on the NAMED files |
| 9 | **reference-health gate** | `python3 quality-tools/reference-health-gate/refcheck.py` (+ `test_refcheck.py` 10) | **Layer-0 root docs only** (repo-root `*.md` + `.github/*.md`): R1 relative link/image targets exist; R2 referenced workflow filenames exist (paths + badge URLs); R5 STATUS current-truth zones' row-count claims == actual manifest count (ADR 0026) |
| 10 | PSScriptAnalyzer + Pester canon suite | `Invoke-ScriptAnalyzer` (3-cell matrix, ADR 0013) + `reference-code/powershell/tests/Invoke-CanonTests.ps1` | Canon-scoped; **carry-over rule**: when `reference-code/powershell` is byte-identical (subtree hash) to the last fully-verified HEAD, results carry (P4 determinism fact) — re-run otherwise |
| 11 | syntax gates (per project) | `bash -n` / `Parser::ParseFile` / `py_compile` | Stream-owned; the only code gates a **sandbox**-stage project owes (ADR 0024) |

## Named limitations & footguns (the honest edges)

- **doc_gate `--reconstructed` with no FILE args scans 0 files and prints PASS.**
  Always pass explicit file lists. Current lists (hand-kept): ol-aws 4 files (TESTING
  intentionally out) / iso 5 / dsd 5 / rhel 5. **Follow-on:** derive these lists and
  the STATUS stream table from the manifest `kind=project` rows (incubating+) instead
  of hand-keeping them — G4 candidate.
- **refcheck R2 cannot distinguish hypothetical from dead workflow references** —
  prose-shape rule (ADR 0026 §5): never write a non-existent-by-design workflow as a
  contiguous `.github/workflows/<name>.yml` path. Bare filename tokens without a path
  prefix (e.g. a workflow name in backticks alone) are NOT matched — tables of
  workflow names are kept true by review + the badge URLs that R2 does catch.
- **refcheck does not verify prose path currency** (e.g. a retired directory named in
  running text) — forensic/history text legitimately cites retired paths; prose
  currency is review-owned. Anchors/fragments (`#section`) are not resolved.
- **Validator D/E/G are powershell-helper-scoped** (ADR 0020/0022 boundary): bash
  canon does not exist yet (`reference-code/bash/` deferred); doc-side coupling is
  doc_gate C9's job, not the validator's.
- **Scanner consumer scanning covers populated `consumers[]` only** — an inlined copy
  not registered as a consumer is invisible to drift scanning (registration ownership
  rule #9).
- **R5 probes exactly two STATUS zones** (`| Current phase |` row, `Gates green`
  paragraph). Other numeric claims (History, prose) are unprobed by design.
- **CI-side (GitHub Actions) coverage is a separate axis** from this local battery:
  the 8 workflows run the per-project stage suites + psa self-quality; the governance
  battery above is local/per-phase. The github-workflows template question (TF d2w)
  stays deferred; the reference-health gate now machine-checks workflow-name truth in
  Layer-0 docs, which was its main prerequisite.
- **Index==body beyond row counts** (phase labels, ADR indices, version strings in
  STATUS prose) is review-owned: sweep header + Current-phase table + Gates line +
  Next-action together on every STATUS touch (the 2026-07-03 rule).
