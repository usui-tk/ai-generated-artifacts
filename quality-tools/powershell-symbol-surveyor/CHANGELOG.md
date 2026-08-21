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

### Changed

- **README / README.ja restructured, consumer surface first.** The pages led
  with the corpus/cache machinery while `survey`, `slice` and
  `--capabilities` appeared nowhere — an inversion of what the tool now is.
  Three new sections open the page (surveying, slicing with the D12 boundary
  stubs and the `PSS9005` refusal, the descriptor and self-checks; every
  usage line executed before being written down), the comparison section
  moves up with them, and the corpus/cache half is kept intact below —
  this README remains the corpus manager's authoritative document. The
  `Registration` section's stale `corpus.py` phrasing is corrected to the
  subcommand reality, and the deferral-cost note that existed only in the
  Japanese page is mirrored into the English one. Structural lock-step held
  by the gate on both pages.

## [0.4.0] - 2026-08-20 (`model_version` "3" -> "4"; the D12 arc)

`MODEL_VERSION` advances at this arc's first model-moving commit (ADR 0035 /
the D10 bundling discipline): every change below alters the model emitted for
a fixed input, the "3" caches are expired in one bundled event, and Appendix
B.8 is restamped once at the arc's end — B.7's pins verified **unmoved**, the
outcome §6.4's standing predicts for changes the comparator does not read.
The restamp's B.8 movements are exactly the arc's declared set: both shape
fingerprints, the new `unresolved_named_commands` name-set block, and the
`PSS9003`/`PSS9007` limitations counts. Battery after the restamp: **358**
with `pwsh` / **351** without / **163** without `git`, green at all three
degradation levels; the derived caches are regenerated under the new digest.

### Added

- **A `--scope` slice re-introduces boundary references as stubs** (SPEC
  §5.7) — the one stated exception to whole-records-only, closing round 3's
  finding of 33 edge endpoints resolving to nothing inside a function slice
  (re-measured before implementation: 172 absent identifiers at the same
  scope, 47 from `edges`/`closures` alone). A stub is `record: "stub"` plus
  the four identify-and-locate keys, copied verbatim from the input —
  including from an input's own stubs, so slice-of-slice cannot dangle what
  the first slice resolved. The reference set is **declaration-driven** off
  `COLLECTION_KEYS.symbol_refs` (§5.8): the first hand-rolled field list
  collected variable-record `id`s — identifiers that never resolve into
  `symbols` — on its very first measurement, and the declaration already
  separated the two. The `symbols` variant declaration is re-cut so the
  common set **is** the stub set (four keys; the analysis payload moves to
  the full variants' carries), `/symbols[]/record` is the fourth `optional`
  path (slice-only by construction), and `slice` now refuses a model from
  another `model_version` (`PSS9005`) for the same reason `compare` does.
  Held by a resolution gate, a verbatim-copy gate, and fixtures including
  slice-of-slice and the version refusal.
- **Site records carry `arguments` and `span`** (SPEC §4.2, under the
  `command-sites` axis) — the facts a round-3 destructive-invocation audit
  (`Remove-Item -LiteralPath … -Force`) had to return to the source for.
  `arguments` is **itemisation, not binding** (each token `{kind, text}`
  verbatim, in order; kinds `parameter`/`variable`/`splat`/`string`/
  `expandable_string`/`number`/`bareword`/`expression`/`scriptblock`;
  which value binds to which parameter is the consumer's judgement, §1.2);
  variable and bareword items extend over byte-adjacent tails (`$p.FullName`
  is one item), and balanced captures walk **tokens**, so a paren inside a
  string cannot derail them. `span` is the [start, end) byte extent — a
  backtick continuation lives inside a `bt` token, so a multi-line
  invocation is one element and its span says so, and two same-line
  invocations of one name carry two disjoint spans, the disambiguation a
  line number cannot give. Measured at the pin: **+379,027 bytes, +6.2% of
  the all-axes model**, all of it on the opt-in axis; the default model is
  byte-unmoved by this entry.
- **`PSS9002` records carry `target`** (SPEC §4.8) — the invoked name
  expression, verbatim, extended over byte-adjacent member/index/call tails
  only (the §10.6 adjacency discipline applied to the expression side:
  `& $x.Path` records `$x.Path`, `& $x .Path` records `$x`; a parenthesised
  target is captured balanced over tokens, so a paren inside a string cannot
  derail it). **The §13.2 row's premise was corrected by measurement before
  implementation**: it claimed the 26 dynamic sites were itemised nowhere
  and `limitations` was silent — false since the tool's first commit, which
  carried per-site `PSS9002` records with `owner` and `line` on the default
  model. What was missing was the expression; with it, the round-3 rename
  pre-flight becomes a model join instead of a grep, and the adjudicated
  axis-shaped itemisation is withdrawn with the premise (a second copy of
  26 records already on the default model). At the pin the 26 sites resolve
  to nine distinct expressions, including one member chain
  (`$robocopy.Source`) that proves the adjacency extension on real data.
- **`limitations` enters the §13.3 variant declaration** — four variants
  discriminated on `code` (`PSS9002` carrying `target`; `PSS9003`/`PSS9004`/
  `PSS9007` common-keys only), because one code carrying a key three others
  do not is not uniform. The exercised-variant gate widens from pin-only to
  **every checked model**, and a sixth model joins the checked set: the
  variant-demonstration fixture, which produces the two limitations codes
  the reference target never does (`Set-Variable -Scope`, a duplicate
  function name). A prose observed-column cell now marks a variant the pin
  cannot produce; `--self-check`'s row parser accepts it and the gate's
  numeric comparison skips it, so the two surfaces stay consistent.

### Fixed

- **`PSS9003` no longer depends on parameter order** (SPEC §4.8). The
  `Set-Variable` scan returned at `-Name`, so the common order
  `-Name X -Value 1 -Scope 1` was silently missed — and the pinned blob
  itself carries exactly that order (`Set-Variable -Name OutputEncoding
  -Scope Global`, line 561), meaning the §4.8 claim had never once held on
  the reference target. The scan now continues past `-Name`; the pin gains
  its first `PSS9003` record, and `measure()` gains all four limitations
  code counts so the digest sees this class of movement. Demonstrated
  red-first with both orders. The D10 `-OutVariable` lesson in miniature:
  the SPEC claimed, the implementation partially delivered, and the gap
  surfaced only when a fixture exercised the claim.
- **`/symbols[]/ordinal` was emitted and declared nowhere** — a
  duplicate-name source emits it (§5.2, `PSS9007`) and it is absent at the
  pin and on **all 230** corpus generations, which is exactly why no
  pin-anchored check had ever seen it. The variant-demonstration fixture put
  the first duplicate-name model in front of the presence gate and the
  exactly-one/key-set check caught the undeclared key. Declared: the third
  `optional` path in `MODEL_SCHEMA`/§13.3, and a conditional key on both
  `symbols` variants.

### Removed

- **`edges[].line` is retired** (SPEC §5.9). It was normatively `lines[0]` —
  a duplicate by construction, kept one version for the `"2"` consumers that
  read it, with the retirement recorded as a question for the next
  model-moving arc. Decided in that arc: a consumer reading `line` was
  reading a copy, and a copy of a fact is the shape §13.2 spends its rows
  fighting. The declared path set falls 125 -> 124 (`all-axes`) / 115 -> 114
  (default); the comparator and the delta document read `lines` only and are
  unmoved; the §5.5 version gate on `compare`/`trace` keeps the `"3"` and
  `"4"` edge shapes from being read as one.

### Changed

- **Dotted command names join** (SPEC §10.6). `dism.exe` lexes as word `.`
  word and the command-word iterator yielded the first word alone, so the
  `PSS2009` record named `dism` — a name that exists in no source line. In
  command position an adjacent word (`.` word-or-number)\* run is now one
  name; adjacency is byte-offset-decided (`dism . exe` stays the command
  `dism` with two arguments), the exclusion look-ahead sees past the joined
  tail, and the lexer's leading-digit limit (`7z.exe` is a number token) is
  stated rather than silently inherited. At the pinned blob exactly one
  record moves (`dism` -> `dism.exe`, line 7690, the real `& dism.exe
  @Arguments` invocation); `counters.commands_named` is unchanged at the
  reference parser's 5,048. Full-corpus regression over all 230 generations:
  five joins and nothing else (`dism`/`expand`/`reg`/`reagentc`/`robocopy`
  gaining `.exe`), site and name counts unmoved everywhere.

### Fixed

- **The §14.4 digest was blind to a name change, and the blindness was
  measured before it was closed**: the join above moves a record *value* on
  all 230 generations and moved **no** figure in the acceptance block — the
  digest still read `4619cc9c…`, identifying two builds that emit different
  models as one. A count cannot see a rename (93 aggregates == 93
  aggregates), so `measure()` now asserts the *identity* of the `PSS2009`
  name set (a 16-hex digest over the sorted lower-cased aggregate names)
  alongside its count. ADR 0035's founding measurement was content-only
  blindness on the fact-code side; this is the same lesson arriving on the
  value side, closed in the commit that demonstrated it.

## [0.3.0] - 2026-08-20 (the D10 and D11 arcs)

*(Header corrected at the D12 arc: these entries shipped as `pss_version`
`0.3.0` — the bump is recorded inside the declaration-sources entry below —
but the section kept the `[Unreleased]` heading, which no gate reads. The
heading now states what happened.)*

### Added

- **SPEC §3.2 records survey round 3** (42/42 quantitative claims verified;
  the presence-contract adjudication with the candidate-A self-violation as
  decisive evidence; the two-state and slice findings; the delivery
  contamination with its root cause on the packaging side and the two
  method rules adopted from it). **SPEC §13.2** closes the per-record
  presence row and opens the D12 inventory: dynamic command sites,
  command-site arguments + extents, and slice boundary stubs
  (design-coupled to the §13.3 variant declaration).

- **`PSS8007`, `PSS8006` and `PSS7007` transcribe both usage states**
  (SPEC §12.7; round-3 B4). `detail.baseline_state` / `detail.successor_state`
  carry each model's writer and reader identities **with the site lines that
  model's own reference records retain** — the join both round-3 reviewers
  performed by hand before they could act on a record, and the evidence one
  of them needed to prove that a trace's empty-writer `PSS8007` state
  predated the change rather than being introduced by it. Pre-existing vs
  introduced is now decidable from the delta alone; which of the two it
  amounts to remains the consumer's reading. On `PSS8007`, `baseline_state`
  is `null` when the variable is absent from the before model. Delta-shape
  change under §6.4's newly stated standing: B.7 pins (counts, tallies,
  subjects) verified unmoved, no restamp needed, `model_version` untouched.
  New gate fixture fires all three codes in one pair and cross-derives every
  transcribed line from the raw models; demonstrated red against the D10
  build.

- **The slice projection contract is declared** (SPEC §5.7; round-3 B2).
  `pss.SLICE_PROJECTION` states what `slice_model` has always done and
  nothing stated: membership-filtering by one rule over seven identifying
  fields, whole records kept or dropped and **never rewritten** (a kept
  unresolved-command aggregate still states source-wide figures),
  `limitations`/`counters`/`source` kept in full, `cost`/`materialization`
  recomputed. Serialised by `--capabilities` (`slice_projection`); the gate
  holds the declaration against behaviour (kept-in-full byte-equality, the
  no-rewrite rule on kept aggregates, the scoped set == the implemented
  tuple). A round-3 reviewer had to reverse-engineer these rules from
  slice/parent output pairs.
- **The delta document's shape declares its conditional key and its own
  standing** (SPEC §6.4; round-3 B3). `source_path_differs` — found by a
  round-3 reviewer in a real document and absent from the declared shape —
  now lives under `top_level_conditional`, and the gate holds both
  directions (a same-path pair must not carry it; an unequal-path pair
  must). §6.4 additionally states three norms that were practised and
  unwritten: the default `examined_subjects` counts are the per-kind
  compression of exactly the `--all` enumeration; the pseudo-subject
  `<script>` can be a delta subject and is never an examined subject; and
  the delta document is a reader of models outside the §14.4 cache, so a
  delta **shape** change restamps B.7 and neither expires a cache nor
  advances `model_version` — the norm whose absence made a clean round-3
  reviewer misclassify a delta-field ask as a version-arc item.

- **The per-record presence contract is declared, serialised and gated**
  (SPEC §13.3 "Per-record presence"; round-3 adjudication B1). Kind
  `always` was a per-model claim being read as a per-record one —
  `/symbols[]/parent` is `always` and sits on 1 of 480 records at the pin.
  `pss.RECORD_VARIANTS` now declares, for every non-uniform collection, the
  record variants: machine-evaluable predicates (`equals`/`gte`, never on
  the absence being explained — `depth` discriminates `symbols`
  non-circularly), exact key sets, first-class conditional keys whose
  presence is the value (§4.4 omit-for-false, promoted at reviewer
  request), and axis keys composing with the variant. Exactly-one matching;
  undeclared collections claim uniformity and the gate holds that too.
  `--capabilities` serialises the declaration verbatim plus a derived
  per-path index, serving both consumer moments the reviewers split across.
  Six collections declared, not the adjudicated five: measurement added
  `string_interpolation_references` (conditional `qualifier`, 5 of 118).
  Declaration-only — `model_version` stays `"3"`, no cache expires. New
  gate checks (exactly-one + key sets over five models, exercised variants,
  uniformity of undeclared collections, SPEC observed column re-derived,
  descriptor verbatim + index derivation), demonstrated red as an actual
  run against the shipped parent build; `--self-check` gains the
  bidirectional table comparison, demonstrated red against the
  section-less SPEC.

### Changed

- **Appendix B.7/B.8 restamped once, closing the D10 arc's intermediate red**
  — every pinned figure re-derived by the shipped build and stamped with its
  basis unchanged: `trace` pair 189 -> 173 records (`PSS8007` 17 -> 1,
  naming `ErrorsJsonlPath`), independent pair 25 -> 24 (the deliberate [F4]
  instance became its edge), `commands_named` 5,048, `PSS2002` 5,534, usage
  signatures 120, both shape fingerprints (+`/edges[]/lines`). **The derived
  caches taken under `model_version` `"2"` (digest `e32e86ec…`) are expired
  by this arc and regenerated under `"3"`** via `test_pss.py cache
  0001`/`0002`, header digest verified against `--emit-baseline-digest`.
  Gate 13 grows 280 -> 315 with `pwsh` (274 -> 308 without; 105 -> 139
  without `git`). B.7's "expected to move when [F4] is adjudicated" is
  rewritten as the observation it became.

### Added

- **The classification vocabularies are serialised** (SPEC §11.3;
  adjudication A4, premise corrected by measurement: the §11.3/§11.4 truth
  tables already existed and matched the implementation — what the round-2
  reviewer lacked was any copy reachable from the shipped surface, since the
  intended caller holds no SPEC (§2.6). `PSS7005_CLASSIFICATIONS` /
  `PSS7006_CLASSIFICATIONS` are one-copy constants, each in its own table's
  row order — the two tables order their rows differently, found in the act
  of unifying them — the comparator's cell lookups derive from them, and
  `--capabilities` publishes them as `classification_values`. Model
  unchanged. Two new gate checks, red-run against the parent build.)
- **§3.2 records the second consumer-review round**: convergences, the
  verified new finding (a kind-`always` path omitted per record), and the
  three documentation defects reported as forced guesses — each closed in
  this arc: the `axis_increment` baseline is stated (§3.1: this model's own
  materialisation; `0` = already carried, `null` = sliced), `edges[].line`'s
  meaning is §5.9's, and `PSS8004`'s `resolves_a`/`resolves_b` presence rule
  is explicit.
- **§13.2 gains the per-record presence contract as owed** (the round-2
  finding, verified: `/symbols[]/parent` kind `always`, absent on 384/385
  records at the pin) and closes the `Call-site locations` row ([F2]).

- **The delta document states what it did not evaluate and shrinks what it
  never used** (SPEC §6.4; consumer-adjudicated A3; part of the
  `model_version` `"3"` arc — the document shape moves, the record
  populations do not). Three changes, all proposed or requested by both
  round-2 reviewers independently: `not_evaluated` maps every catalogued
  comparison code absent from `surveyed` to its reason (`{}` under `trace`,
  emitted rather than omitted); `examined_subjects` is per-kind counts by
  default with the full enumeration restored under `--all` (both reviewers
  completed every task without reading the enumeration while it dominated
  the document's bytes; the counts cross-check against the presence tally
  and, by kind, against the `--all` enumeration); and the position a
  reviewer had to rebuild by joining raw models is copied onto the records —
  `PSS8001`/`PSS8002` carry the edge's `lines` (§5.9) from the model that
  has the edge, `PSS8004` carries the first site's `owner`/`line` from the
  model whose record the resolution was read from. `PSS8004` equality stays
  over the resolution only: a moved site is not a resolution difference.
  Seven new comparator gate checks, each demonstrated red as an actual run
  against the parent build.

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
