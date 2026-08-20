# Changelog

All notable changes to the PowerShell Symbol Surveyor (`pss.py` and the gate
beside it) are documented here.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/).
`pss_version` follows [Semantic Versioning 2.0.0](https://semver.org/) and is
the version this file tracks.

**Two versions, two questions.** `pss_version` says which build; `model_version`
says which model contract, and it advances whenever the model emitted for a
fixed input can differ — shape **or** content (SPEC §5.5, ADR 0035). Neither
substitutes for the other, so both are recorded on every entry that moves
either. An entry that moves `model_version` also expires every derived cache
taken under the old one (§14.4).

This file starts at `0.2.0`. Entries before it are reconstructed from the
commit history and the SPEC's own decision records rather than written at the
time, and are marked as such.

## [Unreleased]

### Added

- **[F2] closed: the edge record carries every call site** (SPEC §5.9 new,
  §13.2 `Call-site locations` closed; consumer-adjudicated A2; part of the
  `model_version` `"3"` arc). `edges[].lines` is every site's line,
  ascending, `len(lines) == sites`; `line` is normatively `lines[0]`,
  re-derived from the array so the two cannot disagree — which also fixed an
  unnoticed defect: a site inside `$( ... )` is scanned after the top-level
  stream, so `line` was the first-*scanned* site, not the first in the file.
  Shape moves (+1 path, declared in `MODEL_SCHEMA` and §13.3 together).
  Measured at the pinned blob: +29,347 bytes, +2.6% of the default model,
  +0.4% of all-axes — the arc plan's ~1.4% was taken on a different base and
  is superseded by these basis-stated figures.

### Changed

- **[F4] closed: a command in a `foreach` condition is in command position**
  (SPEC §10.6, consumer-adjudicated A1; part of the `model_version` `"3"`
  arc). `foreach ($x in Get-Thing)` now yields the `PSS2001` edge, an
  unresolved name there is `PSS2009`, and the callee stops reporting
  `PSS4003` / matching `PSS3001` — the honest-degradation path §4.4 carried
  reverses into the primary fact. The rule is scoped to the keyword `in`
  inside a `foreach` condition group; an implementability probe against the
  reference parser preceded the adjudication (the token scan's only misses
  at the pinned blob were the two `foreach`-condition calls) and the
  populations are now equal, held by a **new differential check**
  (`counters.commands_named` == bare-word-named `CommandAst`, demonstrated
  red at 5,046 vs 5,048 against the parent build). The `Publish-ReleaseArtifacts`
  independent-pair pin reddened at this entry — the movement B.7 was pinned
  ahead of the arc to make visible.

- **All five SPEC §12.2 declaration sources retain a site** (`pss_version`
  `0.3.0`, **`model_version` `"2"` -> `"3"`** — the emitted model differs for
  a fixed input, so every derived cache taken under `"2"` is expired by this
  entry and regenerated inside the same arc, §14.4). A `param()` entry, an
  inline signature parameter and a `foreach` loop variable are var tokens and
  classify as the declarations they are (`PSS2002`/`PSS2006`, role `write`);
  a `Set-Variable`/`New-Variable` literal `-Name` and the `-OutVariable`
  family synthesise their site at the name literal. The `-OutVariable`
  family was previously not recognised at all — its reads reported `PSS9004`
  while §12.2 claimed they resolved; both the gap and the misstatement are
  closed, red-first. `counters.assignments` and `counters.variable_refs` are
  unmoved by definition and by measurement at the pinned blob.
- **The usage map is order-independent** (SPEC §12.3): script-owner
  contributions are applied against the complete classified population, so a
  script whose `param()` block and top-level writes precede its functions no
  longer loses exactly its writers. Membership rules are unchanged. Measured
  effect on the adjudicated pair (entry `0002`, gens 93 -> 94): `trace` falls
  189 -> 173 records and `PSS8007` falls **17 -> 1**, the surviving record
  naming `variable:script/ErrorsJsonlPath` — seventeen perfectly-declared
  parameters stop reading as missing writes, and the one genuine empty
  writer set remains. Corpus regression over all 230 generations: only
  `local_variables` and `script_variables` move; every other collection is
  byte-identical.
- Appendix **B.7/B.8 figures redden at this entry by design** and are
  restamped at the end of the arc, together with the remaining D10 items, so
  cache expiry happens exactly once (ADR 0035, D10).

- **The tool is two `.py` files again**, which SPEC §14.1 has specified since
  the first commit and which had not been true since the second. `corpus.py`,
  `build_cache.py` and `test_corpus.py` are folded into `test_pss.py`; the
  corpus manager and the derived-cache producer are reached as
  `test_pss.py corpus <subcommand>` and `test_pss.py cache <entry>`.
  `pss.py` is untouched, so `model_version` stays `"2"` and derived caches
  taken under it remain valid.
- §14.1 states the two-file rule **normatively**, with the line it follows:
  `pss.py` reads only the files it is given and its imports are held against an
  allowlist so it cannot reach a repository (§2.6); everything that must reach
  one lives in the gate.
- SPEC §14.4's "one implementation" of the cache identity is enforced over the
  gate file's own syntax tree — no producer function may name `hashlib`, and
  `baseline_digest` must have exactly one definition — replacing the check that
  `hashlib` was absent from a separate `build_cache.py`. The scope is the
  producer's named functions and its weakness is stated in §13.1: a function
  omitted from that list is not examined, so the list is checked against the
  module first.

### Known gaps recorded

- **`foreach ($x in <command>)` is not command position (§10.6).** A real call
  yields no edge and its target is reported `PSS4003`. This matches what §10.6
  says, so it is a gap in the specification rather than an implementation
  defect. Not fixed here: closing it advances `model_version` and expires every
  derived cache, so it is adjudicated with the other extractor work to expire
  them once. Found by consumer review; the `PSS3001` / `named_by_literal`
  fallback made it recoverable, which is how it was found.
- **Call-site locations for multi-site edges (§13.2).** A `PSS2001` edge
  carries one `line` and a `sites` count; the remaining locations are in no
  shipped shape. Both reviewers failed the same task on it.

### Fixed

- **SPEC §14.3's `git` degradation had never run.** `repo_root` raised
  `FileNotFoundError` rather than returning `None` when the binary is absent,
  so the documented "no `git` -> fixtures only" fallback took the whole gate
  with it instead of degrading. The cache-generator leg was also unguarded.
  Three levels now work and name every skip: **206/206** with `pwsh`,
  **200/200** without, **47/47** without `git`.

### Added

- **Value nullability is declared, serialised and gated (§13.3).** The
  schema's kinds (`always` / `axis` / `optional`) state presence and never
  said what a value may be. Grounding found exactly three paths that carry
  JSON `null` in real output — `/symbols[]/parameters[]/qualifier` (903 on
  the pinned blob), `/symbols[]/parameters[]/type` (26), and
  `/cost/axis_increment[]/bytes` on sliced models (§5.6) — the first two
  previously unrecorded. `pss.NULLABLE_PATHS` declares them once with the
  fact each null states; `--capabilities` serialises it (`nullable_paths`),
  `--self-check` holds it against the new §13.3 subsection in both
  directions, and the gate holds it against reality: every observed null is
  declared and **every declared path is exercised**, so the mark can neither
  lag reality nor outrun it. The complement is now a stated contract: every
  other path's value is never null — absence is key omission (`optional`),
  the model's existing convention. Descriptor-only; the emitted model is
  unchanged, `model_version` stays `"2"`, caches remain valid. The gate
  grows 274 → 280 (274 without `pwsh`, 105 without `git`). Whether the two
  parameter nulls should instead become key omissions is a model change and
  is deferred to the version-advancement arc as a consumer question.
- **Appendix B.7 is pinned and gated (delta baselines).** The former table
  ("Delta behaviour over 12 consecutive historical states") is withdrawn, not
  restamped: measured with the shipped comparator over all 229 consecutive
  committed-generation pairs, no window of 8–16 pairs reproduces it — the
  output of an uncommitted instrument over an unrecorded window (ADR 0036,
  the B.3 defect met on the comparator's side). Replacing it, a
  `pss-delta-baseline` machine block pins `trace` and `compare` over the
  adjudicated pair (entry `0002`, generations 93 → 94, retrieved by blob) and
  `compare` over two independent fixture scripts embedded in the gate — the
  pair corpus history cannot supply (§4.9). Record counts, per-code tallies,
  the `PSS7001` classification split and the `PSS8008` subject are re-derived
  through the shipped CLI surface; fixture identity is held by the emitted
  document's own `source.sha256` against the recorded basis. The
  `Publish-ReleaseArtifacts` fixture deliberately carries the §10.6 [F4]
  instance, so adjudicating [F4] reddens these figures instead of moving them
  silently. B.7 is a separate block from B.8 on purpose: pinning a reader of
  models moves no cache-identity digest, so `model_version` stays `"2"` and
  every derived cache remains valid. The gate grows 259 → 274 checks
  (268 without `pwsh`, 103 without `git`).
- **`compare` and `trace` work.** Both verbs ran as refusals for the whole life
  of the tool; they now emit the §6.4 delta document. One comparator serves
  both, differing only in the assertion the caller makes, and `--capabilities`
  moves `delta_records` off `not-implemented` — enforced by the descriptor
  gate, so the mark cannot move without the behaviour.
  **All eighteen comparison codes are evaluated.** `compare` runs the fifteen
  that hold without a claim of succession; `trace` runs those and the three
  rules of §12.7 (`PSS8005`–`PSS8007`), which presuppose that the caller has
  asserted one model is a later state of the other. Under `compare` those
  three are absent from `surveyed`, which is how a caller tells "did not run"
  from "ran clean".
- **The delta document has a specified shape (§6.4).** `compare` and `trace`
  emit `delta_records` (differences only, flat, one subject each), `surveyed`
  (a per-code tally, mandatory in every build) and `examined_subjects` (the
  compared population by identifier), plus the provenance of both models.
  `--all` restores the full per-code enumeration. Chosen by consumer review of
  two competing candidates rather than decided here (§3.2).
- **§3.2 records the consumer-review practice** and the results other sections
  cite as evidence.
- **§4.6's equality requirement is stated as two axes** — per subject and per
  code — because a shape can satisfy one and fail the other, and a reviewer was
  misled by one that did.
- **The file inventory is gated (§14.1, §13.1).** The two-`.py` rule was
  normative from the first commit and enforced by nothing, which is how the
  directory reached five files in three days. The gate enumerates the file set
  and requires an exact match — enumerated rather than counted, so it names the
  unaccounted file and also catches one that disappeared — reading the
  committed inventory and, for `.py`, the working directory, so an unstaged
  third module fails too. `corpus/` is matched by pattern, because entries
  accumulate by design.
- This file, `README.ja.md` and `VERSION`, closing SPEC §13.2's `Docs` row.

## [0.2.0] - 2026-08-17

*(Reconstructed from the commit history; `model_version` `"1"` -> `"2"`.)*

### Added

- `--cost`: a fixed-size block in every model giving per-collection bytes and
  record counts, the remainder as `envelope`, and the bytes each axis would
  add. **First `model_version` advance since the constant existed**, which
  expired every derived cache taken under `"1"`.
- `--capabilities`: the SPEC §3.1 machine-readable interface descriptor. It
  **serialises** the constants it publishes rather than restating them, and an
  output this build does not produce is declared `not-implemented` with a
  reason rather than omitted — currently the delta record and the structured
  error payload.
- `slice`: symbol-scoped projection and axis-set narrowing over a stored model.
- `compare` and `trace` registered as two verbs. `compare A B` claims no
  relation between its inputs; `trace before after` carries the caller's
  assertion that the second is a later state of the first — an assertion the
  tool cannot verify and can only require to be made, which is why it is a verb
  and not a defaultable flag. **Both refuse in this build**: the comparator is
  Layer 3 and is not written, and refusing is preferred to emitting an empty
  comparison that would read as "no change".
- SPEC §13.3, the declared 125-path model schema, held in `pss.MODEL_SCHEMA`
  and checked against the document on path and kind.
- SPEC §5.8, the identifier forms and collection join keys — which surfaced a
  sixth identifier form the SPEC had never named.
- SPEC §2.6, the operating context, gated two ways: the module imports against
  an allowlist, and byte-identical output between a run inside this repository
  and one in an empty non-repository directory.
- SPEC §14.4's cache producer, which the specification had required without
  anything implementing it.

### Fixed

- Three of the seven compound assignment operators were unreachable and a
  dynamic member-name assignment declared the member name — 13 sites, all
  function-local (ADR 0034).

## [0.1.0] - 2026-08-16

*(Reconstructed. Six committed revisions emitted `model_version = "1"` across
four changes of shape and two of extractor behaviour; per ADR 0035 those are
not renumbered, and `"1"` is normatively **not** evidence that two models
carrying it are comparable.)*

### Added

- The Layer 1 extractor and the Layer 2 model: functions, variables, the
  references between them, and the regions the tool could not analyse.
- The corpus (ADR 0033): entries pin one script at one path, never follow a
  rename, and are append-only.
- The baseline gate (ADR 0034): every asserted figure re-derived from a pinned
  corpus **blob**, with no expected values in the gate itself.
