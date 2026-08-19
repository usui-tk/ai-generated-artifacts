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
| 5 | canonical-drift-scanner | `python3 quality-tools/canonical-drift-scanner/scanner.py --root .` (+ `--satellite NAME=PATH` / `--satellite-commit NAME=SHA` for cross-repo consumers, ADR 0030; `test_scanner.py` 19) | Body-hash drift for **region-kind units with populated `consumers[]`** + whole-tool null rows for tool kinds. **Cross-repo consumers (`consumers[].repo`, ADR 0030): scanned only under a `--satellite` mapping (cold loop); an UNMAPPED instance is SKIPPED and reported — never drift/unknown — so hot runs stay satellite-blind by design.** Output partitions per observation `repo=<name>`. `kind=project` / `governance-doc` are out of scope BY DESIGN (granularity None). Emits transient observation run-logs — **never stage them** |
| 6 | canon-manifest-tool self-test | `python3 quality-tools/canon-manifest-tool/test_tool.py` | 28 cases: transactional CRUD incl. rollback-on-finding, kind=project lifecycle rows, marker-coupled `update` writes REFUSED, **cross-repo `consumers[].repo` via `--add-consumer ...,repo=<name>` (ADR 0030; unknown keys now REFUSED, not silently dropped)**, and the **`promote` coupled op** (R-3.1, ADR 0022): doc-region-only scope, dry-run purity, non-advancing-version + marker-less-target refusals, and gate-failure -> byte-identical rollback of ALL touched files. **Per-op gate set of `promote`:** validator + doc_gate default + doc_gate `--path` over every consumers[] file (fail-safe REFUSE if either gate script is absent) |
| 7 | canon-drift-trigger self-test | `python3 quality-tools/canon-drift-trigger/test_trigger.py` | 33 cases: observation→change-request derivation + **the P7a decision gate** (ADR 0027): machine impact measurement (`impact` — consumers[] + both marker frames), kind→SemVer→tier mapping, **heavy-tier refusal** without enumerated consumers + migration + full-ADR, `propose` reconcile-back emission, drift requests carrying computed impact with kind pending. Emit-only (no state store; the ledger is P8's) |
| 8 | document-conformance gate | `python3 quality-tools/document-conformance-gate/doc_gate.py` (+ `--path <SPEC>`, `--reconstructed <files>`, `test_doc_gate.py` 45) | Default mode: **manifest-registered md units only** (`kind=template` + `spec-region` canonical_locations; 18 files) — front-matter, marker coherence, doc-region hashes (C-checks), **C9 version coupling** (ADR 0022: follow-latest marker `version=` == manifest `canonical_version`; pin may lag never lead), C6 ADR↔SPEC integrity (full-manifest mode only). `--path`: same per-file checks on named files (consumer SPECs). `--reconstructed`: L3 doc-set conformance - with NO file args = **derived mode (ADR 0031)**: the set derives from the manifest `kind=project` rows (maturity incubating+): every doc-provenance-pinned `*.md` under each `canonical_location`; a covered project with zero pinned docs is a FINDING. Explicit FILE args = spot-check on the named files |
| 9 | **reference-health gate** | `python3 quality-tools/reference-health-gate/refcheck.py` (+ `test_refcheck.py` 12) | **Layer-0 root docs only** (repo-root `*.md` + `.github/*.md`): R1 relative link/image targets exist; R2 referenced workflow filenames exist (paths + badge URLs); R5 STATUS current-truth zones' row-count claims == actual manifest count (ADR 0026); **R6 kind-breakdown + project-maturity claims in the same zones == the actual manifest (ADR 0031)** — probe what is written, do not dictate what must be written |
| 10 | PSScriptAnalyzer + Pester canon suite | `Invoke-ScriptAnalyzer` (3-cell matrix, ADR 0013) + `reference-code/powershell/tests/Invoke-CanonTests.ps1` | Canon-scoped; **carry-over rule**: when `reference-code/powershell` is byte-identical (subtree hash) to the last fully-verified HEAD, results carry (P4 determinism fact) — re-run otherwise |
| 11 | syntax gates (per project) | `bash -n` / `Parser::ParseFile` / `py_compile` | Stream-owned; the only code gates a **sandbox**-stage project owes (ADR 0024) |
| 13 | **pss baseline gate** | `python3 quality-tools/powershell-symbol-surveyor/test_pss.py` (+ `--pwsh <path>` for the differential leg; `--emit-baseline-digest` for the SPEC §14.4 cache identity; `pss.py --self-check`; `pss.py --capabilities` for the SPEC §3.1 descriptor) | Re-derives every figure in the surveyor SPEC's Appendix **B.8** machine-baseline block from the **pinned corpus blob** (ADR 0034) and fails on divergence, plus the model **shape fingerprints** (default + all-axes key-path sets) and synthetic fixtures for the extractor rules that have failed. Every asserted figure carries an **executable derivation** here rather than a label in the document (ADR 0036), and a figure that is not axis-invariant is asserted **per materialisation** (`references_outside_functions`, 485 default / 556 with `local-sites`). **A model that moved without `MODEL_VERSION` advancing is now a failure** (SPEC 13.1 Version decision): the parent commit's `pss.py` is re-run against the same pinned blob, so no ledger of past versions is kept to go stale. The **cost report** (SPEC 3.1) is checked by re-deriving the decomposition from the model, not by re-checking the block's own sum. The **declared model schema** (SPEC 13.3) is held against the code constant on path and kind, and against the pinned blob in both directions. The **identifier forms and collection join keys** (SPEC 5.8) are held the same way, and additionally by behaviour rather than by name: every declared field must be populated at the pin, every join value must resolve into `symbols` or the reserved `<script>`, every other identifier must match exactly one declared form, and every declared unique key must be unique — a form dropped from both copies stays green under `--self-check` and reddens here. The **operating context** (SPEC 2.6) is held two ways, because the corpus is reference data for these gates and the tool must not acquire a dependency on it: `pss.py`'s module imports are parsed and compared with a declared allowlist (nothing that can reach a subprocess, a socket or an HTTP client), and the subcommands are run in an empty non-repository directory with no executable search path, their output required to be **byte-identical** to the same run made from the repository root. The **SPEC 14.4 cache generator** is held structurally (no producer function may name `hashlib` and the digest must have exactly one definition, checked over the gate file's own syntax tree: the digest has one implementation and it is copied, not recomputed) and behaviourally (a real two-generation cache is produced; its header must match the §14.4 field set in both directions, materialise every axis, and identify a generation by `rev` and `blob` rather than by position). **Neutral naming** (SPEC 1.3) applies a denylist of judgement words to the fact-code descriptions and the subcommand help strings, and checks the denylist covers a non-empty surface; a denylist makes no completeness claim and the SPEC says so. The **capability descriptor** (SPEC 3.1) is checked block by block against the constant each block serialises — a literal copied in is caught the moment the constant moves — and its `implemented` / `not-implemented` marks are checked against the build itself: `compare` is run and must refuse, a usage error under `--format json` must not emit JSON. A feature cannot land while leaving its mark behind. **Determinism**, **projection invariance** and **channel agreement** (SPEC 13.2) are automated: byte-identity across repeated extractions, containment across each axis, and a per-row derivation for the text channel. **The gate holds no expected values** - B.8 is the single master it reads, so the document and the check cannot drift apart. **Anchored to a blob, not to a branch head**, so maintenance-stream edits to the reference script never turn it red (the coupling that kept `corpus.py check` out of this battery, ADR 0033). The **corpus self-test** is part of this gate rather than a separate invocation, as is the **corpus manager** itself (`test_pss.py corpus <subcommand>`): filename identity, discovery, refusals, rename boundary, append-only growth, load integrity, derived views and analysis reductions, over fixtures that are **real git repositories** built in a temporary directory (ADR 0033). It needs the `git` binary and not this checkout, so it is skipped by name where the binary is absent. The **comparator** (SPEC 4.9, 5.5, 6.4) is held by property rather than by transcription — a gate that recomputed the deltas would agree with the implementation by construction. What is checked is what the specification promises: a model compared against itself produces no record and finds a non-empty population equal; `surveyed` covers exactly the codes this build evaluates, so an unevaluated code is visibly absent rather than silently clean; every record's subject is in the examined population; `compare` emits no succession-only code; the cost exclusion is stated in the output; `--all` changes the records and never the tally; and a `model_version` mismatch refuses with **nothing** on stdout, because a partial delta reads as a complete one. The **file inventory** is held rather than assumed: SPEC §14.1's two-`.py` rule was normative and ungated for three days, and the count reached five while gate 13 grew 68 -> 156 checks looking only at the model. The gate now enumerates the tool's committed files and requires an exact match, reads the working directory too so an unstaged third module fails, and matches `corpus/` by pattern because entries accumulate by design. The **document set** (SPEC 13.2 `Docs`) is held rather than inspected: `README.md`, `README.ja.md`, `SPEC.md`, `CHANGELOG.md` and `VERSION` must exist, `VERSION` must equal `pss.__version__`, and the bilingual pair must match on heading structure and fenced-block count — structural lock-step, which catches a section added to one side only and makes no claim about whether the prose still agrees. Degrades per SPEC 14.3, and the degradation is now real rather than declared: no `pwsh` -> frozen regression (**243/243**); no `git` -> the legs that read this file only (**86/86**), with the corpus self-test and the cache-generator run each skipped by name. Until 2026-08-18 the no-`git` path raised instead of degrading, so the documented fallback had never been exercised |
| 12 | reconciliation-loop self-test | `python3 quality-tools/reconciliation-loop/test_coldloop.py` | 12 cases (needs `pip install duckdb`): DuckDB aggregation (schema-probe for absent columns), proposals wrap the pinned request contract 1.0.0, **skip-key dedup** (unchanged re-observed drift not re-proposed; changed evidence = new proposal), **append-only ledger byte-verified** (decide = appended decision record; double/unknown refused), write surface limited to `governance/state/reconciliation/`, zero-observation path. Cold path only - the hot battery stays stdlib-only |

## Named limitations & footguns (the honest edges)

- **doc_gate `--reconstructed` no-arg derived mode replaced the former footgun
  (ADR 0031).** Zero FILE args used to scan 0 files and print PASS; it now derives
  the set from the manifest `kind=project` rows, and a covered project with zero
  pinned docs FAILS. The hand-kept per-project lists are retired — they had already
  drifted (the list said "ol-aws 4 files" while `TESTING.md` gained its pin at B1;
  the live set is 4 projects / 20 files). The STATUS-side companion is refcheck R6
  (manifest-breakdown claims machine-checked; no stream table is created).
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
- **The pss baseline gate asserts B-I only, and not all of it.** Appendix B figures whose
  derivation from the model has not been re-established are marked `[DERIVATION OWED]` in
  B.3 and are deliberately NOT asserted - marking them is how ADR 0034's "no unchecked
  baseline may exist" is satisfied without restamping a guess. B-II figures (AST predicates:
  the declaration-form table, statically-named commands, the string-constant population) are
  re-measured with `pwsh`, never asserted against `pss.py` - `counters.assignments` in
  particular is NOT B.4's "Assignment statements" row.
- **The model-shape fingerprint is over OBSERVED key paths, not a declared schema**
  (ADR 0035). It records the shape the pinned generation happens to reach, so an optional
  field that generation never populates can be added or removed without moving it. The
  same code change measures **eleven** removed paths against the pinned blob and
  **thirteen** against an early generation, which is this dependence made visible. A
  declared key-path schema, checked in both directions, is the remedy and is recorded as
  owed in the surveyor SPEC §13.2 — not built.
- **A shape fingerprint does not detect a content-only change and must not be used as an
  identity** (ADR 0035). The ADR 0034 extractor fixes moved 2,302 records between fact
  codes across the corpus and moved no key path at all. Derived model caches therefore
  identify their producing build by a **baseline digest** over the measured acceptance
  values (surveyor SPEC §14.4), never by `model_version` or a fingerprint.
- **The baseline digest is checked by value, after a key-only check was demonstrated
  useless.** The first form of this check compared the digest block's key set to Appendix
  B.8's; a deliberately wrong fingerprint inside the block passed it. The landed check
  compares by value. Recorded because it is the third instance of the same shape - a check
  that compares names while the failure lives in behaviour (surveyor SPEC §13.2,
  enumerated-constant reachability).
- **A label is not a derivation, and this gate is where the derivation lives.** Appendix
  B.3's figures were recorded as English noun phrases; measured, all six committed
  revisions of `pss.py` returned identical values for them, so nothing had drifted except
  the question being asked. `$script:`-qualified admitted three readings differing by
  hundreds. Figures now exist only as queries in `test_pss.py`, and three that no
  generation and no revision reproduces were withdrawn rather than restamped (ADR 0036).
- **The renderer is not a derivation.** The channel-agreement gate writes each text-row
  derivation from the SPEC and applies it to the model, rather than re-running
  `render_text`'s expression, which would compare a restatement. Writing them caught two
  of the gate author's own derivations: `closure entries` is the closure sets summed, not
  the record count, and the two PSS4xxx rows carry `PSS4003`/`PSS4004`, not
  `PSS4001`/`PSS4002`. Four rows remain uncovered and are listed by name, so an
  underived figure is visible rather than silently outside the gate.
- **A fingerprint over observed paths is not a schema.** §13.1's fingerprint is taken
  over the paths a given model happens to carry, so a data-dependent field can appear or
  vanish without moving it. Measured over all 230 committed generations, exactly two such
  fields exist and each is present in 204 of them — which is why one corpus entry carries
  two fingerprints. SPEC 13.3 now declares the 125-path set with those two marked
  `optional` and the evidence recorded; the fingerprint remains, and answers a different
  question.
- **A remainder cannot audit the breakdown it completes.** The cost report's stated
  identity is `sum(by_collection) + envelope == model_bytes`, and `envelope` is
  *computed* as the remainder — so the identity holds even when a whole collection is
  dropped from the breakdown. The first form of this gate checked exactly that identity
  and stayed green through the mutation; the landed gate re-derives every figure from the
  model and compares by value. Fourth instance of a check comparing a restatement rather
  than a measurement.
- **The version-decision hole is closed (ADR 0036).** It used to read: a shape or B.8
  change reddens the baseline gate, and clearing it requires re-stamping B.8 — which is
  where §5.5's advance should be decided, and nothing checked that it was. The check now
  derives the previous state from the parent commit rather than from a record, and it is
  demonstrably able to go red: it reddens at `44b97d1` (shape moved, version held) and at
  `bc69c27` (shape identical, measured values moved, version held). It cannot see a
  version skipped several commits back — per ADR 0035 versions are not renumbered
  retroactively, so per-commit is the granularity the rule actually has.
