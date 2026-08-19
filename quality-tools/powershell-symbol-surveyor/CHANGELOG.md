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

### Fixed

- **SPEC §14.3's `git` degradation had never run.** `repo_root` raised
  `FileNotFoundError` rather than returning `None` when the binary is absent,
  so the documented "no `git` -> fixtures only" fallback took the whole gate
  with it instead of degrading. The cache-generator leg was also unguarded.
  Three levels now work and name every skip: **206/206** with `pwsh`,
  **200/200** without, **47/47** without `git`.

### Added

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
