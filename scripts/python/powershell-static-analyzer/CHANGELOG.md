# Changelog

All notable changes to `psa.py` (the PowerShell static analyzer in this
directory) are documented in this file.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning 2.0.0](https://semver.org/).
For the public-API scope governed by SemVer (the CLI surface, rule
code names, JSON / SARIF output schemas, configuration file schema),
see [SPEC.md §1.4 Versioning](./SPEC.md#14-versioning).

This CHANGELOG covers `psa.py` only. For higher-level repository-wide
changes (documentation policy, sister scripts, etc.), see the root
[`README.md`](../../../README.md) of `ai-generated-artifacts`.

## [Unreleased]

### Documentation — Compliance with `scripts/README.md` Required Sections + repository-wide `AGENTS.md` cross-references

A doc-only update that brings this subproject into compliance with
the repository-wide [`scripts/README.md`](../../README.md) Required
README Sections (`## ⚠️ Disclaimer` and `## License`, both MUST-level)
and adds cross-references to the newly-introduced repository-wide
[`AGENTS.md`](../../../AGENTS.md).

#### Why this update

Two parallel gaps were closed:

1. **Pre-existing Required Sections gap.** `scripts/README.md`
   L114–L127 mandates that every project-level `README.md` and its
   `README.ja.md` mirror include a `## ⚠️ Disclaimer` section and a
   `## License` section with a one-paragraph summary of permitted use
   and required attribution. This subproject historically carried only
   a four-line License pointer at the file end and no Disclaimer
   section at all — a violation that pre-dates the Step 6 governance
   cycle.
2. **Step 6 follow-up.** The Step 6 governance cycle introduced
   `AGENTS.md` at the repository root. This subproject's
   documentation did not yet reference it.

#### Changes

- **`README.md`**: New `## ⚠️ Disclaimer` and `## License` sections
  inserted near the top (immediately after the language switcher,
  one-line summary, and version-discovery block), as required by
  `scripts/README.md` L114–L127. The Disclaimer is tailored to
  `psa.py`'s nature as a **heuristic static analyzer**: false
  positives, false negatives, AI / LLM independent-verification
  obligation, guardrail-not-substitute principle, rule-judgement
  drift over versions, and inline-suppression rationale discipline.
  Cross-references to `AGENTS.md` §3 / §8 and to the root README
  "psa.py Versioning Policy" are included.
  The previous minimal `## License` section at the file end is
  removed (the new canonical License section near the top supersedes
  it).
- **`README.ja.md`**: The same Disclaimer and License content in
  lock-step Japanese (per `AGENTS.md` §5 Bilingual lock-step rule).
  The pre-existing minimal `## ライセンス` section at the file end
  is likewise removed.
- **`SPEC.md`**: New blockquote pointers in **Appendix C —
  Quality Gates & Validation Checklist** (linking to `AGENTS.md` §8
  Self-Check Gates) and **Appendix D — Known Pitfalls & Lessons
  Learned** (linking to `AGENTS.md` §9 Anti-Patterns). These
  surface that the project-specific entries below are complemented
  by a repository-wide catalogue that LLM agents must consult.
- **`CHANGELOG.md`**: This entry.

#### Not touched

- `psa.py` source. No rule behaviour, CLI surface, or output schema
  is affected. This remains an `Unreleased`-bucket doc-only entry;
  no version bump is required.
- `test_psa_rules.py`. No test fixtures or assertions are changed.
- `SPEC.md` numbered sections §1–§12. The numbered-section structure
  remains the authoritative API specification; only Appendix C and
  Appendix D gain repository-wide cross-references.

#### Rationale

The repository-wide governance hierarchy established in the Step 6
cycle (Layer 0 root files; Layer 1 `scripts/README.md`; Layer 3
subproject docs) treats `psa.py` as a Layer 3 subproject that must
honour the Layer 1 Required README Sections contract. This update
closes the long-standing compliance gap without altering the
numbered-section primary specification body (which `scripts/README.md`
L144–L146 explicitly permits for formal API specifications, provided
Appendix C and Appendix D exist — both already present here).

## [4.1.0] - 2026-05-26

### Added — Three new rules catching the latent-bug classes that escaped
gate enforcement during the r07.0 cycle of the `update-windows-server-iso`
PowerShell pipeline

The r07.0 cycle of the sister script
[`scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1`](../../powershell/update-windows-server-iso/Update-WindowsServerIso.ps1)
took 10 sequential bug-fix iterations (Steps 10-19) to reach
dry-run completion. Six of those iterations addressed bugs that
**passed every existing static-analysis gate** (`PS Parse`,
`psa.py`, `PSScriptAnalyzer`) but failed at runtime — and in
three of those cases the underlying defect class was sharp
enough that a dedicated static rule could have caught it before
the bug ever shipped. v4.1.0 productionises those three checks
as built-in rules.

**`PSA1004` — Bare `(if/switch/foreach/while/...)` used as
expression (error, default ON).** PowerShell distinguishes
statements from expressions. A bare `(if ($x) { 'a' } else
{ 'b' })` is parsed as a *command invocation* named `if` —
which fails at runtime with "The term 'if' is not recognized
as a name of a cmdlet, function, script file...". The parser
accepts it as valid syntax, so neither
`[System.Management.Automation.Language.Parser]::ParseFile`
nor PSScriptAnalyzer flagged it. The correct form is `$(if ...)`
(subexpression) or `@(if ...)` (array subexpression). This
was the proximate cause of the r07.0 Step 18 defect in
`Show-Pca2023ReadinessSnapshot`, where 5 lines used the bare
form and the function hung the script with a runtime "term
'if' not recognized" exception once the code path became
reachable.

**`PSA2012` — Positional call provides fewer args than the
target function has `[Parameter(Mandatory)]` parameters
(error, default ON).** A function declared with multiple
`[Parameter(Mandatory)]` parameters, called positionally with
fewer arguments, does not fail — PowerShell prompts the user
interactively for each missing value. In CI pipelines or
unattended sessions, the script hangs forever on stdin. The
trap is that the call site looks fine: `Write-PhaseHeader 'P12'`
is syntactically valid. This was the proximate cause of the
r07.0 Step 17 defect: `Show-Pca2023ReadinessSnapshot` called
`Write-PhaseHeader 'Pca2023 readiness (P12)'` with one
positional argument; the target function declared three
Mandatory parameters; the script hung on `Name:` prompt; the
user had to Ctrl-C.

Heuristic: build a function table of `{name: [mandatory_params, ...]}`
from in-file `function ... { param(...) }` blocks (>=2
Mandatory required to enter the candidate set), then for each
call site count `positional + named_matching_mandatory` and
fire when the count is below `len(mandatory)`. Argument
counting uses the original text (string literals occupy
positional slots) rather than the strings-stripped clean.
Excludes bare-name references, pipeline-arg calls, and LHS of
assignments.

**`PSA2013` — `$Script:Foo` is read but never assigned
anywhere in the file (error, default ON).** PowerShell
silently evaluates an unassigned `$Script:Foo` to `$null`,
hiding typo bugs in script-scope variable names. PSA2001
(generic undefined-variable) only checks within function
scopes; it does not see the cross-function flow of
`$Script:` globals. The defect manifests downstream as
bizarre null-related errors, usually far from the typo.
This was the proximate cause of the r07.0 Step 15 defect:
two typo'd globals (`$Script:ExtractedMediaPath`,
`$Script:WorkRootFull`) hid in plain sight across 8 call
sites; the correct names (`$Script:ExtractedDir`,
`$Script:WorkRoot`) existed; the reads silently returned
`$null` and downstream defensive checks misdiagnosed the
state as "P05 did not run".

Algorithm: two-pass on the cleaned text. Pass 1 collects every
`$Script:Name = ...` assignment site. Pass 2 walks every
`$Script:Name` read site and reports unless the name is
assigned somewhere in the file, OR appears as a top-level
script parameter (auto-populated by PowerShell from
`param(...)` declarations), OR is in the well-known auto-vars
allowlist (`MyInvocation`, `PSScriptRoot`, etc.). Reports cap
at 5 hits per distinct name to avoid flooding output on a
typo with many call sites.

### Test suite

- Added 21 new test cases (9 positive, 9 negative, 3 edge) in
  `test_psa_rules.py` covering all three new rules. The Step 15 / 17 / 18
  failure sites from the `update-windows-server-iso` pipeline are
  included verbatim as positive cases, so any future regression of
  these rule definitions will be caught immediately.
- Full suite: 245 → 266 tests, all passing. The `--self-check`
  guard (SPEC.md ↔ RULES synchronisation) is satisfied by the
  parallel SPEC.md update in this release.

### Specification

- Added `SPEC.md §4.3a` (PSA1004), `§4.9f` (PSA2012), `§4.9g`
  (PSA2013) with detection algorithm, rationale, real-world
  defect citation, suggested-fix examples, false-positive
  defenses, limitations, and inline-suppression syntax.
- Updated `SPEC.md` Appendix A rule severity matrix.

### Rule count

`RULES` registry: 46 → 49 entries (PSA1xxx ×4, PSA2xxx ×13,
PSA3xxx ×6, PSA4xxx ×4, PSA5xxx ×4, PSA6xxx ×8, PSA7xxx ×2,
PSA8xxx ×1, PSA9xxx ×2, PSAPxxxx ×5).

### Version policy

This is a **minor** version bump per SemVer: three new rules are
added as **default-on**, which is a behavioural change for
existing scans. Consumers who pin to v4.0.x will see no
behavioural shift; consumers who track the latest version will
see new error-severity findings on previously-passing files
that contain any of the three defect classes. If the new
findings are not actionable, individual rules can be disabled
via `.psa.config.json` (`{"disabled": ["PSA1004"]}`) or
inline suppression (`# psa-disable-line PSA2012 -- <reason>`).

### Documentation

- **Rule-count text alignment — hybrid update across stale
  forward-looking references.** The 3.8.0 / 3.9.0 / 4.0.0
  releases added `PSA2009`, `PSA2010`, `PSA2011`, and `PSAP0005`
  to the runtime `RULES` registry (now 46 entries: PSA1xxx ×3,
  PSA2xxx ×11, PSA3xxx ×6, PSA4xxx ×4, PSA5xxx ×4,
  PSA6xxx ×8, PSA7xxx ×2, PSA8xxx ×1, PSA9xxx ×2,
  PSAPxxxx ×5), but three in-tree text references continued to
  spell stale counts (`36` originally, partially uplifted to
  `42` / `45` in earlier passes, never refreshed during the
  4.0.0 / 4.0.2 cycles). This revision applies a **hybrid
  policy**: prose comments and test docstrings are parameterised
  against `RULES` directly (no embedded count), while the SARIF
  illustrative example — where the digit is informative to
  readers sizing their tooling — is updated to the current count.

  - **`psa.py`** — Pillar 1 comment block above the
    self-quality gates section. Dynamic phrasing:
    `"External: test_psa_rules.py covers all 42 rules with ..."`
    → `"External: test_psa_rules.py covers every rule in the
    RULES registry with ..."`.
  - **`test_psa_rules.py`** — module docstring header.
    Dynamic phrasing:
    `"Each of psa.py's 42 rules has, at minimum, ..."`
    → `"Each rule in psa.py's runtime RULES registry has, at
    minimum, ..."`.
  - **`SPEC.md`** §6.3 (SARIF 2.1.0 format example) — concrete
    count, kept as a numeric reader hint:
    `"rules": [ /* 45 rule descriptors */ ]`
    → `"rules": [ /* 46 rule descriptors */ ]`.

  Documentation-only revision: no behavioural change, no rule
  catalog change, no test count change. `__version__` is **not**
  bumped (the runtime `RULES` array and `psa.py --list-rules`
  output have been correct since each rule was added; only the
  human-readable prose references were stale). The canonical
  source of truth for the rule count remains the runtime
  `RULES` registry. `psa.py --self-check` validates `SPEC.md`
  §4 against `RULES` by rule ID rather than by count, which is
  why this drift was not surfaced by the existing self-quality
  gates. Future rule-count text references should follow the
  same hybrid rule: omit the digit in prose, keep it only where
  the example deliberately illustrates a concrete output size
  (such as SARIF samples).

## [4.0.2] — 2026-05-24 — `psap0005-relaxed-mode-coverage-uplift`

This patch release extends `PSAP0005`'s relaxed-mode exemption set
to cover established prose patterns observed in real-world consumer
pipeline scripts (specifically the
`usui-tk/Deploy-Drivers-For-WindowsServer` r76 baseline). It is
**backward-compatible** with `4.0.0` / `4.0.1`: no new rule is
added, no configuration key is introduced, no public-API change.
Only the **relaxed-mode** behaviour of `PSAP0005` is expanded; strict
mode (`psap0005_relaxed_mode: false`) is unchanged.

### Motivation

The original 4.0.0 release defined four relaxed-mode exemption
patterns (A SECTION header, B SPEC cross-reference, C Added-in-
release phrasing, D Earlier-revisions prose) based on the SPEC §D.31
conventions in Deploy-Drivers. When `psa.py 4.0.0` was applied to
the r76 baseline, the consumer reported **64 PSAP0005 detections**
across the four sister scripts that the original A/B/C/D set did not
catch. Analysis showed these were also established prose patterns,
just with surface forms the original regexes had missed.

Notable patterns that 4.0.0 missed but 4.0.2 now exempts in relaxed
mode:

- Semi-section headers: `# r71 Pre-check: ...`
- SPEC cross-reference with slash/dash separator: `(r66 / SPEC D.24)`, `(r75 - SPEC D.33)`
- SPEC cross-reference with reversed parens: `r68 (SPEC §D.26):`
- SPEC ref + rNN co-occurrence: `See SPEC SS D.31 ... r71 design contract`
- Added-in-release variants: `r71 adds ...`, `the /all addition in r74`, `documents the r72 follow-on`, `Until r39, Graphics shipped`
- Earlier-revisions variants: `prior to r65`, `predates r65`, `from an r65 run`
- Q-Reference patterns: `r69 (QI-6):`, `(Q-X1, r17)`, `QI-9 (r69, 2026-05-23):`
- Cross-port markers: `r40 (graphics):`, `r22 (bthpan):`
- Follow-up sentence: `r73: this declaration was missing in r71/r72`

### Added

- **Nine new relaxed-mode exemption patterns (E1-E9)** documented in
  `SPEC.md` §4.37. Each pattern is a separate compiled regex inside
  `psa.py` for clarity and individual testability.

- **Comment-block-level exempt heuristic**: In addition to line-level
  pattern matching, `PSAP0005` now checks the entire contiguous
  comment block (consecutive lines whose first non-whitespace
  character is `#`) for an exempt-trigger pattern. If any line of
  the block matches, the whole block is exempt. This handles the
  common case where a multi-line narrative comment block opens with
  an exempt phrase like `# WHQL co-signature analysis (added with the
  r71 release).` and continues for several lines that mention `rNN`
  without re-triggering on each line.

- **`test_psa_rules.py`**: 26 new test cases — 21 relaxed-mode
  exempt patterns (E1-E9 plus block-level exempt) and 5 strict-mode
  regression tests verifying the new patterns do NOT leak into
  strict mode. Total test count: `220 → 246` (all passing).

### Changed

- `SPEC.md` §4.37 (`PSAP0005`) expanded with the E1-E9 exemption
  table and the comment-block-level exempt description. The original
  A/B/C/D table is preserved verbatim as `4.0.0` baseline.

### Backward compatibility

- **Rules registry**: unchanged at **46 rules**. No new rule code.
- **Configuration schema**: unchanged. No new keys; no removed keys.
  `psap0005_relaxed_mode` remains the only PSAP0005 config flag.
- **CLI surface**: unchanged.
- **Strict mode**: unchanged. The 4.0.2 extensions affect only
  relaxed mode; any repository running `psap0005_relaxed_mode:
  false` (default) sees identical behaviour to 4.0.0 / 4.0.1.
- **Existing relaxed-mode behaviour**: strictly expanded, never
  narrowed. Any comment that 4.0.0 / 4.0.1 exempted under relaxed
  mode continues to be exempt under 4.0.2.
- **SemVer impact**: PATCH increment per SPEC.md §1.4
  (false-positive defence widening with no public-API change).

### Migration

No action required for any consumer. Repositories using
`psap0005_relaxed_mode: true` will see their PSAP0005 detection
count drop on upgrade from `4.0.0` / `4.0.1` to `4.0.2` if any of
the new exempt patterns are present in their script bodies. The
intent of relaxed mode (migration aid toward strict mode) is
unchanged; the new patterns simply better reflect the established
prose conventions in real consumer pipelines.

---

## [4.0.1] — 2026-05-25 — `psa2009-indirect-binding-defence`

This patch release adds a false-positive defence to `PSA2009`
(PSCustomObject property assigned without prior declaration). It is
**backward-compatible** with `4.0.0`: no existing behaviour changes,
no new rule is added, no configuration key is introduced. Only the
detection logic of `PSA2009` is widened to suppress an additional
class of false positives that surfaces in PowerShell scripts that
schedule parallel work via `RunspacePool` + `ArrayList`.

### Motivation

`PSA2009` performs file-level tracking of variables initialised with
`[pscustomobject]@{...}`. The same variable name can legitimately
host both a sealed pscustomobject and a hashtable across different
functions in the same script — Step 2c of the 3.8.0 detector
recognises this **only** for *direct* initialisations
(`$var = @{...}`). Indirect initialisations through collection-Add
+ foreach loop binding were not yet recognised, leading to false
positives like:

```powershell
$job = [pscustomobject]@{ Foo = 1 }    # unrelated sealed object
$jobs = New-Object System.Collections.ArrayList
[void]$jobs.Add(@{ Handle = $h })      # $jobs holds hashtables
$newlyDone = $jobs | Where-Object { $_.Handle.IsCompleted }
foreach ($job in $newlyDone) {
    $job.Collected = $true             # safe (hashtable add), but
                                       # PSA2009 v4.0.0 flagged this
                                       # as undeclared on the sealed $job
}
```

This pattern fires exactly twice on `Download-SpeakerDeck.ps1` in
the sister `usui-tk/ai-generated-artifacts` project (Phase 4 and
Phase 6 reaper loops). With 4.0.1, both warnings clear and the
script's `0 errors / 0 warnings / 0 info` baseline is restored.

### Changed

- **`PSA2009` Step 2c2 (new)** — recognises foreach loop-variables
  that are bound indirectly through `$Coll.Add(@{...})` + later
  `foreach (...) in $Coll` and treats them as hashtable elements,
  not as pscustomobject elements.

- **Pipeline / method derivation tracking** — when a hashtable-bearing
  collection is filtered or projected through a pipeline
  (`$X = $jobs | Where-Object {...}`) or LINQ-style method
  (`$X = $jobs.Where({...})`, `$X = $jobs.Clone()`), the derived
  collection is *also* labelled as hashtable-bearing. The
  propagation runs to a fixed point with a 16-iteration cap.

- **`SPEC.md` §4.9c (`PSA2009`)** — the rule walk now describes
  five passes instead of four. The new pass 4 ("Hashtable-form drop
  pass (indirect)") documents the v4.0.1 detector and gives three
  concrete idioms that are now correctly *not* flagged. The
  motivation paragraph names the `Download-SpeakerDeck.ps1`
  false-positive as the trigger for the addition.

### Added

- **`test_psa_rules.py`** — seven new test cases under "PSA2009 —
  hashtable-Add + foreach indirect binding (added in 4.0.1)":

  - Direct `$Coll.Add(@{...})` + foreach.
  - `[void]$Coll.Add(@{...})` with later foreach.
  - Pipeline-derived collection (`$newlyDone = $jobs | Where-Object`).
  - `.Where()` method-derived collection.
  - Two-hop derivation chain.
  - `$Coll.Add([hashtable]@{...})` explicit cast form.
  - Positive control: `$Coll.Add([pscustomobject]@{...})` does **not**
    trigger the new defence (the cast signals a sealed object, not a
    hashtable element).

  Total test count: `213 → 220` (all passing).

### Fixed

- **False positive on `Download-SpeakerDeck.ps1` lines 3267 and 4037**
  (the original motivating example). Verified manually after the
  Step 2c2 addition; the upstream consumer's CHANGELOG documents
  the corresponding script-side adoption as `r27 —
  psa-py-v4-llm-governance-baseline`.

### Backward compatibility

- **Rules registry**: unchanged at **46 rules**. No new rule code.
- **Configuration schema**: unchanged. No new keys; no removed keys.
- **CLI surface**: unchanged. No new flags.
- **SemVer impact**: PATCH increment per SPEC.md §1.4 (bug-fix /
  internal-defence-tightening with no public-API change).

### Migration

No action required for any consumer. Repositories that hit the
PSA2009 false positive will see their `0/0/0` baseline restored
automatically on upgrade from `4.0.0` to `4.0.1`. Repositories that
were *not* affected see no change.

---

## [4.0.0] — 2026-05-25 — `llm-governance-baseline`

This is the first major version since `psa.py` 2.0.0. It is a
**breaking** release: a new opt-in rule (`PSAP0005`) is added, the
configuration schema gains a new boolean key (`psap0005_relaxed_mode`),
and the `SPEC.md` introduces a new §1.5 ("Design philosophy — psa.py
as an LLM-assisted maintenance guardrail") that re-frames the role
of the project-convention rule family (`PSAPxxxx`) explicitly as the
LLM-governance gate for consumer repositories.

### Why MAJOR rather than MINOR

- The new rule `PSAP0005`, even though default-off, expands the
  detection surface materially. Repositories that adopt the rule on
  their previously-clean baseline may surface previously-tolerated
  revision-anchored prose at a much higher rate than PSAP0003 (which
  caught only structured tag forms).
- The `SPEC.md` formally codifies the LLM-governance philosophy in a
  new §1.5 and rewrites portions of §4.35 / §4.36 / §4.37 to make
  the scope of the inline-comment scanner explicit. This is a
  documentation-level breaking change for consumers that depended
  on the older (looser) interpretation.
- The `.psa.config.json` schema gains `psap0005_relaxed_mode` and its
  validator. Older configs without the key continue to work
  unchanged (the key defaults to `false`), so this is
  backward-compatible at the config-file level — but consumer SPECs
  that document their config now have a new field to surface.

### Added

- **`PSAP0005` — Revision reference in comment body (warning,
  default OFF, new).** The broader companion of `PSAP0003`. Where
  `PSAP0003` catches only the five structured tag forms (`# r42:`,
  `# r42+:`, `# r42-update3:`, `# ---- r42: ----`, `# (r42)`),
  `PSAP0005` catches ANY `rNN` reference inside a comment body. This
  closes the gap that allowed descriptive-prose anchors like "Added
  in the r71 release", "As of r74, …", "Before r74, …", and
  "Earlier revisions (before r74)" to evade `PSAP0003` while still
  encoding moving frame-of-reference into the script body. See
  `SPEC.md` §4.37 for the full specification.

- **`psap0005_relaxed_mode` configuration flag (boolean, default
  `false`).** When set to `true` in `.psa.config.json`, four prose
  exemption patterns are applied:
  - **A. SECTION header**: `# SECTION rNN: …`
  - **B. SPEC cross-reference**: `(rNN, SPEC §D.YY)` /
    `(rNN, SPEC D.YY)`
  - **C. Added-in-release phrasing**: `(added|introduced|landed|
    ported) (in|with) (the )? (<script_name> )? rNN`
  - **D. Earlier-revisions prose**: `(earlier|previous|prior)
    (revisions|releases) … rNN`

  Relaxed mode is the migration aid for repositories with significant
  pre-existing rNN-anchored prose under SPEC §D.31-style conventions
  (e.g., Deploy-Drivers-For-WindowsServer). The recommended steady-
  state is `false` (strict), with the migration plan documented in
  the consumer SPEC.

- **`SPEC.md` §1.5 — Design philosophy: psa.py as an LLM-assisted
  maintenance guardrail.** New normative section that codifies why
  the rule families exist, mapping each LLM failure-mode pattern
  (revision-anchored prose, EOF revision history blocks, silent
  cross-file helper drift, LF-only emission from Python script
  generators, invented cmdlets, locale-dependent constructs,
  PSCustomObject sealed-object semantics) to the rule that enforces
  it. Two policy corollaries follow: language-correctness rules
  (PSA1xxx–PSA9xxx) default on; project-convention rules (PSAPxxxx)
  default off but become contractual when opted in.

- **`SPEC.md` §4.35 / §4.37 — Detection scope clarification.** Both
  PSAP0003 and PSAP0005 now have explicit "Detection scope"
  subsections that document: (1) inline comments only, (2) string
  literals excluded, (3) block comments `<# ... #>` out of scope by
  design (a residual human-review responsibility), (4) word boundary
  including hyphen so that compound identifiers like
  `radeon-r9000-series` do not fire, (5) at most one report per
  matching line.

- **`SPEC.md` §5.3 Schema — full configuration field table.** The
  schema table now lists `psa8001_ignore_functions`,
  `psa2010_known_cmdlets`, and `psap0005_relaxed_mode` alongside the
  pre-existing four fields.

### Changed

- **Rule catalog count: 45 → 46.** The new `PSAP0005` brings the
  total to 46 (PSA1xxx ×3, PSA2xxx ×11, PSA3xxx ×6, PSA4xxx ×4,
  PSA5xxx ×4, PSA6xxx ×8, PSA7xxx ×2, PSA8xxx ×1, PSA9xxx ×2,
  PSAPxxxx ×5). `psa.py --list-rules` and `--self-check` reflect
  the new catalog.

- **Configuration validator (`--config-check`) gains a boolean-key
  registry.** A new `_CONFIG_BOOL_KEYS` frozenset enumerates all
  configuration keys that must be JSON booleans;
  `psap0005_relaxed_mode` is its first member. The validator emits
  an error if the key is present with a non-boolean value.

### Testing

- **`test_psa_rules.py` gains Section 2c (PSAP0005 relaxed-mode
  tests, 15 cases) and Section 2d (PSAP0003 + PSAP0005 dedupe, 1
  case).** Total test count: 212 → 213. The relaxed-mode harness
  drives `analyze_text` directly with `cfg.psap0005_relaxed_mode =
  True` to exercise each of the four exemption patterns plus the
  three negative cases (As of rNN, parenthesised tag, bare colon
  tag still fire) and the string-literal escape.

### Migration guide for existing consumers

Consumers can adopt 4.0.0 in three steps:

1. **No-op upgrade** (zero-effort): Bump the local `psa.py` to
   4.0.0. `PSAP0005` is off by default; no behavioural change.

2. **Opt-in relaxed**: Add `"PSAP0005"` to the `enable` list AND
   `"psap0005_relaxed_mode": true` to `.psa.config.json`. The
   rule fires for all `rNN` references in comments EXCEPT the four
   exemption patterns above. This is the recommended adoption path
   for repositories with significant SPEC §D.31-style prose
   (Deploy-Drivers-For-WindowsServer is the canonical example).

3. **Opt-in strict**: Add `"PSAP0005"` to the `enable` list with
   either `"psap0005_relaxed_mode": false` (explicit) or the field
   omitted (which defaults to `false`). The rule fires for every
   `rNN` reference in comments. This is the recommended steady-
   state once the legacy prose has been cleaned up.

The Deploy-Drivers-For-WindowsServer repository adopts option (2)
at its 4.0.0 baseline release (chipset r76 / graphics r42 / bthpan
r24 / npu r20), with a migration roadmap to option (3) documented
in its SPEC §A.13.

## [3.9.0] — 2026-05-25

### Added

- **`PSA2010` — Call to undefined function (error, default ON).**
  Cross-file rule that flags any Verb-Noun-style call whose target
  is not defined in any scanned file and is not in the
  `KNOWN_CMDLETS` whitelist (Microsoft.PowerShell.Core /
  Management / Security / Utility / Diagnostics, CimCmdlets, PKI,
  PnpDevice, Defender, BitLocker, NetTCPIP / NetAdapter,
  SecureBoot, ScheduledTasks, Storage, Archive, WindowsCapability,
  ConfigCI, International, WSMan). Designed to catch typos such as
  the historical `Find-Signtool` → `Find-KitTool 'signtool.exe'`
  reference defect documented in the consumer repository's r75
  release. The rule deliberately limits its reach to names whose
  verb segment is in `APPROVED_VERBS` (false-positive defense
  against hyphenated domain-specific tokens like `Phantom-OK`,
  `Multi-OS`, `Chipset-Driver-CodeSign`).

  Consumers can extend the cmdlet whitelist via the new
  `.psa.config.json` field:

  ```json
  {
    "psa2010_known_cmdlets": [
      "Get-MyModuleFoo",
      "Set-MyModuleBar",
      "MyModule\\Reset-Widget"
    ]
  }
  ```

  An optional `Module\Name` prefix is permitted for documentation
  and stripped before lookup.

  See SPEC.md §4.9d for the detection algorithm; the rule operates
  at the cross-file driver level (like `PSA8001`) and is dispatched
  from `main()` after every per-file analysis completes.

- **`PSA2011` — `Split-Path -LiteralPath ... -Parent` triggers
  AmbiguousParameterSet (error, default ON).** File-local rule
  that flags `Split-Path` invocations containing both
  `-LiteralPath` and `-Parent` (in either order). On Windows
  PowerShell 5.1 ja-JP this combination raises
  `AmbiguousParameterSet,
  Microsoft.PowerShell.Commands.SplitPathCommand` at runtime; the
  fix is to use `[System.IO.Path]::GetDirectoryName($path)` or
  `Split-Path -Path $path -Parent` (without `-LiteralPath`).
  Single-line and backtick-continuation forms are both handled.

  See SPEC.md §4.9e for the detection algorithm. This rule
  surfaced the proximate cause of the 2026-05-24 r75 release's
  WHQL co-sign analysis failure on a ja-JP Windows Server 2019
  bench host: `Get-InfDriverFileList` used this construct in the
  AmdChipsetDriver / AmdGraphicsDriver / MSBthPanInbox sister
  scripts, propagating a `ParameterBindingException` through the
  outer `try/catch` of `Test-WhqlCoSignature` and silently
  degrading every co-sign verdict to the conservative
  `'self-only'` fallback.

- **`KNOWN_CMDLETS` set (≈200 entries) and
  `KNOWN_CMDLETS_LOWER` derived set.** Comprehensive default
  whitelist for `PSA2010`. The set is module-organised in source
  comments for maintainability; consumers add to it via the new
  config field rather than editing the analyzer source.

### Changed

- **Rule registry now contains 45 rules** (was 43 in 3.8.0). The
  net change is two additions (`PSA2010`, `PSA2011`); no existing
  rules were removed or renamed. `Get-Command rules` and
  `--list-rules` both reflect the 45-rule catalog. `--self-check`
  exits 0 against the matching SPEC.md.

- **`.psa.config.json` schema gains `psa2010_known_cmdlets`** as
  an optional list-of-strings field. `--config-check` validates
  the field's type and rejects non-list values with exit 2.

### Documentation

- **`SPEC.md` §4.9d, §4.9e** (new sections): detailed
  specification for `PSA2010` and `PSA2011` including detection
  algorithm, motivation, suggested fix, inline suppression syntax,
  and differences from related rules (`PSA2001`, `PSA3005`,
  `PSA8001`).
- **`SPEC.md` Appendix A**: severity matrix extended with three
  previously-missing rows (`PSA2009`, `PSA7002`) and two new rows
  (`PSA2010`, `PSA2011`). Total now 45 entries matching the
  runtime `RULES` registry.
- **`README.md` / `README.ja.md`**: rule count text bumped from
  43 → 45 across the rule table and the introductory blurb.

### Testing

- **`test_psa_rules.py`**: new Section 2b adds 13 `PSA2010`
  cross-file test cases (positive: `Find-Signtool` typo,
  undefined helper; negative: `Find-KitTool` defined locally,
  `Get-Content` in cmdlet whitelist, `Get-PnpDevice` from
  PnpDevice module, external binary without hyphen, .NET class
  method call, third-party cmdlet via `psa2010_known_cmdlets`,
  function name appearing only in string literal or comment, bare
  verb-only token, parameter-like `-Verbose`, cross-file union
  satisfying same-file definition).
- **`test_psa_rules.py`**: new in Section 1, 10 `PSA2011`
  test cases (positive: classic form, reversed switch order,
  backtick continuation; negative: `-Path` with `-Parent` only,
  `-LiteralPath` with `-Leaf`, positional path, .NET
  `GetDirectoryName`, mention in a comment, mention in a
  here-string; inline suppression).

### Compatibility

- **Backward compatible.** No existing rule behaviour, severity,
  default-enabled flag, message format, output schema, exit code,
  or config schema key was changed. Consumers on `psa.py` 3.8.0
  can upgrade to 3.9.0 without code changes; the new rules will
  fire on any pre-existing `Find-Signtool`-style typos or
  `Split-Path -LiteralPath -Parent` calls, both of which are
  latent defects that should be fixed regardless.

---

## [3.8.0] — 2026-05-23 — `pscustomobject-sealed-object-detection`

### Added

- **PSA2009 (Warning) — PSCustomObject property assigned without
  prior declaration.** New file-level rule in the PSA2xxx (variable /
  scope) family. Fires when a `.` -style property assignment
  (`$Var.PropName = value`) targets a property that was not declared
  in any `$Var = [pscustomobject]@{...}` initialiser in the same file
  AND was not added later via `Add-Member -MemberType NoteProperty
  -Name PropName`. The rule models the PowerShell 5.1
  `[pscustomobject]` sealed-object semantic: such an assignment
  raises a terminating exception (`"<PropName>" の設定中に例外が
  発生しました: "このオブジェクトにプロパティ '<PropName>' が
  見つかりません。"` in Japanese locales) at runtime, on the first
  phase that attempts the assignment, which is too late for
  long-lived pipeline scripts where the assignment site can be
  hundreds or thousands of lines away from the initialiser. PSA2009
  closes the gap at static-analysis time.

  Detection runs in four passes:

  1. **Initialiser pass** — harvest declared property names from
     every `$VarName = [pscustomobject]@{...}` initialiser, with
     proper brace-balanced parsing that respects string literals
     and nested hashtables. Scope qualifiers (`$Script:`, `$Global:`,
     `$Local:`, `$Private:`) are stripped so `$Script:Ctx = [pscustomobject]@{...}`
     and a later `$Ctx.Foo = ...` correlate.
  2. **`Add-Member` pass** — recognise the two surface forms
     (`$Var | Add-Member ...` and `Add-Member -InputObject $Var ...`)
     and extend the declared set for the target variable.
  3. **Hashtable-form drop pass** — any variable name that is
     *also* assigned somewhere in the file with a plain hashtable
     literal (`@{...}` / `[hashtable]@{...}` / `[ordered]@{...}`)
     is conservatively dropped from tracking. This false-positive
     prevention is necessary because psa.py analysis is file-level
     rather than function-scope-aware, and the same local variable
     name (e.g., `$result`) can legitimately host both pscustomobject
     and hashtable shapes across different functions of the same
     file.
  4. **Assignment pass** — flag every surviving `$VarName.Property
     = ...` assignment whose target property is not in the declared
     set. Compound operators (`+=`, `-=`, `*=`, `/=`) and equality
     comparisons (`-eq`, `-ne`) are excluded. Well-known dynamic
     property bags (`$_`, `$Matches`, `$PSBoundParameters`, `$Host`,
     `$Error`, `$PSCmdlet`, `$MyInvocation`, `$args`, `$input`,
     `$this`) are exempt.

  Inline suppression via `# psa-disable-line PSA2009` works on the
  assignment line.

  **Motivation**: the rule was developed in response to a
  reproducible runtime failure on a clean-installed Japanese-locale
  Windows Server 2019 host where a downstream consumer
  (`Deploy-AMDChipsetDriverOnWindowsServer.ps1` at the `r72`
  baseline) hit `PHASE P05 -> FAILED` with the localised
  property-not-found exception. Both the happy-path assignment
  (`$Ctx.WhqlCoSignAnalysis = New-WhqlCoSignAnalysis ...`) and the
  `catch`-block fallback (`$Ctx.WhqlCoSignAnalysis = @()`) targeted
  a property that the `[pscustomobject]@{...}` `$Ctx` initialiser
  did not declare. Neither psa.py v3.7.0 nor PSScriptAnalyzer 1.x
  detected the defect statically. Adding PSA2009 to psa.py v3.8.0
  reproduces the defect at static-analysis time with two warnings
  on the affected file (the happy-path and `catch`-block assignment
  sites) and zero false positives across the four pipeline scripts
  in the consumer repository (`usui-tk/Deploy-Drivers-For-WindowsServer`).

### Test coverage

- **`test_psa_rules.py`** grows from 148 to 163 active test cases.
  PSA2009 contributes 15 cases covering: simple undeclared
  assignment (positive), `catch`-block double-fire (positive),
  `$Script:`-scoped pscustomobject (positive), declared property
  (negative), `Add-Member` pipe form (negative), `Add-Member
  -InputObject` form (negative), hashtable-form drop pass for
  `@{...}` and `[ordered]@{...}` (negative), `$PSBoundParameters`
  exemption (negative), compound `+=` non-flagging (negative),
  equality comparison non-flagging (negative), read-only property
  access non-flagging (negative), file without any pscustomobject
  initialiser (negative), inline-declared properties (negative),
  and inline `# psa-disable-line PSA2009` suppression (negative).

### Changed

- **`SPEC.md` §4.9c (PSA2009)** — new rule specification subsection
  inserted between §4.9b (PSA2008) and §4.10 (PSA3001). The §4.9c
  numbering follows the existing convention of alphabetic-letter
  suffixes for rules added between major numbering anchors (cf.
  §4.9a PSA2007, §4.9b PSA2008).
- **`psa.py --self-check`** — the RULES registry grows from 42 to 43
  entries with the addition of PSA2009. `SPEC.md` §4 grows in
  lock-step. The self-check report now reads
  `rules : 43 in RULES, 43 in SPEC.md §4`.
- **`psa.py --list-rules`** — output gains one row for PSA2009
  (warning, on by default).

### Notes

- **PSA2009 does NOT subsume PSA2001**. PSA2001 ("undefined variable
  reference") operates at the variable level: it flags a reference
  to `$Foo` when `$Foo` was never assigned. PSA2009 operates at the
  property level: it flags `.NewProp = value` when `NewProp` is not
  part of the variable's `[pscustomobject]` surface. The two rules
  are orthogonal — PSA2001 cannot detect the WhqlCoSignAnalysis-class
  bug because the variable itself is well-defined at every
  assignment site; only the property is missing.
- **PSA2009 does NOT subsume PSA8001**. PSA8001 ("function body hash
  drift") operates at the cross-file function-body level. PSA2009
  operates inside a single file. A producer-site missing in one
  script (the Graphics P05 case in
  `usui-tk/Deploy-Drivers-For-WindowsServer`) is structurally
  invisible to both PSA2009 (because there is no assignment to
  flag) and PSA8001 (because the function bodies legitimately
  diverge per the `psa8001_ignore_functions` exemption list). That
  class of "silently absent producer block" defect requires a
  runtime-level test case in the consumer repository's `TESTING.md`,
  not a new psa.py rule. See `usui-tk/Deploy-Drivers-For-WindowsServer`
  SPEC §D.31.16.5 for the canonical countermeasure.
- **Why "warning" severity, not "error"**. PSA2009 is a high-confidence
  defect indicator but has occasional legitimate exceptions
  (`Add-Member` patterns the rule cannot fully model, framework
  objects with opaque surface contracts). Warning severity allows
  the rule to be suppressed inline where genuinely needed while
  still failing CI gates that treat warnings as blockers (the
  default policy in `usui-tk/Deploy-Drivers-For-WindowsServer`'s
  `.psa.config.json`).

## [3.7.0] — 2026-05-22 — `ps1-line-ending-detection`

### Added

- **PSA7002 (Warning) — PowerShell script has LF-only or mixed line
  endings.** New file-level rule in the PSA7xxx (file format / encoding)
  family. Fires when a `.ps1` file contains at least one line
  terminated by LF without a preceding CR. The canonical Windows
  form is BOM + CRLF (per `.gitattributes`
  `*.ps1 text working-tree-encoding=UTF-8 eol=crlf` in any
  Windows-targeted repository); LF-only and mixed line endings are
  silently accepted by the PowerShell AST parser but rejected by
  some downstream consumers (signtool on certain catalog inspection
  paths, MSI authoring tools, older Windows ISE) and produce
  spurious "modified file" diffs at the next `git add` even when
  no content changed. Default: **enabled**.

  Two message variants distinguish the two ways the defect arises:

  - **All-LF** (`cr_count == 0`): every line in the file is
    LF-terminated. Usually means the file was authored on
    Linux / macOS without newline translation. Remediation is a
    single bulk conversion. Message:
    `"PowerShell script has LF-only line endings (N line(s));
    canonical form is CRLF"`.

  - **Mixed** (`cr_count > 0 AND lf_only_count > 0`): some lines
    are CRLF, others LF-only. Almost always indicates that a
    *programmatic content-generation step* inserted an LF-only
    block (Python triple-quoted strings, shell heredocs,
    AI-agent file-write actions) into a CRLF file. Strictly more
    dangerous than the all-LF case because the defect is invisible
    to PowerShell's AST parser, to visual diff tools, and to
    grep-based "line contains CR" counts. Only a byte-level
    CR-count vs. LF-count equality check reveals it. Message
    includes up to five 1-based line numbers of the LF-only lines
    so a reviewer can start inspection at the specific defective
    region. Real-world motivating occurrence is the
    `Deploy-Drivers-For-WindowsServer` repository's `SPEC.md §D.23`
    write-up (commit `587038e` → `0af5e70`).

  The rule operates on the post-BOM raw byte buffer and is exact
  (no false positives). Implementation comprises a new module-level
  helper `compute_line_ending_stats(raw_bytes)` invoked once in
  `main()` per file, a new rule function
  `check_line_endings(file_meta)` that reads
  `file_meta['line_ending_stats']`, and dispatch wiring in
  `analyze_text()` after the existing `check_utf8_bom_missing()`
  call. The two rules are orthogonal: BOM presence and line-ending
  policy are independent file-level properties.

### Tests

- 6 new rule-driver test cases for `PSA7002` (positive cases:
  all-LF, mixed; negative cases: all-CRLF, empty file; edge cases:
  `file_meta` without `line_ending_stats`, `file_meta=None`).
- 5 new helper-function test cases for `compute_line_ending_stats()`
  in a new Section 2.5 of `test_psa_rules.py` (synthetic byte
  buffers covering CRLF-only, LF-only, mixed, no-trailing-newline,
  and empty cases). Section 2.5 has its own dispatcher because the
  test-tuple shape differs from the Section 1 rule tests.
- Total test count: 137 → **148** (no existing tests changed).
- `--self-check` (SPEC ↔ RULES consistency) updated to reflect the
  new `4.28a PSA7002` section; passes.
- `--config-check` (against shipped `.psa.config.json.template`)
  passes.

### Documentation

- **`SPEC.md` §4.28a (PSA7002)** — full rule specification:
  rationale, detection algorithm, message-text variants, suppression
  mechanism, remediation in PowerShell / Bash / VS Code, and an
  explicit cross-reference to the motivating
  `Deploy-Drivers-For-WindowsServer` `SPEC.md §D.23` lessons-learned
  entry. The PSA7001 "Limitations" placeholder mentions of
  "future PSA7002" (UTF-16 BOM variants) and "future PSA7003"
  (UTF-8 validity) renumbered to PSA7003 and PSA7004 respectively,
  since PSA7002 is now claimed for line endings.
- **`.psa.config.json.template`** — new comment block documenting
  PSA7002 and when to disable it (Linux/macOS-only PowerShell 7.x
  projects with no Windows tooling in the consumption chain).
- **Header docstring of `psa.py`** — PSA7002 added to the
  "File format / encoding (PSA7xxx)" section of the rule list.

### Why this is a minor (not major) version bump

The rule is additive in the PSA7xxx family. Existing PSA7001
behavior, PSA8001 / PSA9xxx / PSAPxxxx behavior, CLI flags, JSON /
SARIF schemas, and configuration schema are all unchanged. The
only observable effect for existing consumers is that `.ps1`
files with LF-only or mixed line endings will produce one new
warning per file (suppressed normally via `disable: ["PSA7002"]`).
Consumers whose `.ps1` files already pass `.gitattributes`
normalisation see no behavior change. The CLI's `--list-rules`
output, the rule catalog in `psa.py --version --list-rules`, and
the SPEC TOC will list one new entry, all of which are documented
in this entry.

## [3.6.0] — 2026-05-20 — `psscriptanalyzer-rule-parity-uplift`

### Added

- **PSA2007 (Warning) — Parameter name shadows a PowerShell automatic
  variable.** New rule that inspects every `param(...)` block
  (top-level script param and per-function param blocks) and reports
  any parameter whose name collides with the risky auto-variable list.
  Mirrors PSScriptAnalyzer's `PSAvoidAssignmentToAutomaticVariable`
  rule. **This rule would have caught the v3.5.x miss of an `$Event`
  parameter that silently shadowed the engine's `$Event`
  auto-variable inside an event-subscriber action block.** Default:
  enabled.
- **PSA3006 (Warning) — Deprecated WMI cmdlet usage.** New rule that
  detects calls to `Get-WmiObject`, `Invoke-WmiMethod`,
  `Register-WmiEvent`, `Remove-WmiObject`, `Set-WmiInstance`, and the
  `gwmi` alias. CIM cmdlets (Get-CimInstance et al.) are the
  supported successors; PowerShell 6+ has removed the WMI cmdlets
  entirely. Mirrors PSScriptAnalyzer's `PSAvoidUsingWMICmdlet`.
  Intentional WMI usage in CIM-fallback paths should be silenced with
  the inline suppression marker
  `# psa-disable-line PSA3006 -- <rationale>`. Default: enabled.
- **PSA6007 (Info) — Advanced function returns a value but does not
  declare `[OutputType()]`.** Mirrors PSScriptAnalyzer's
  `PSUseOutputTypeCorrectly`. Fires when a function has
  `[CmdletBinding()]`, contains at least one `return <expr>`
  statement, and does NOT already declare `[OutputType(...)]`. The
  `[CmdletBinding()]` gate keeps the false-positive rate low: only
  advanced functions are checked. Default: enabled.
- **PSA6008 (Info) — Function with attributes has no explicit
  `param()` block.** Detects functions that have `[CmdletBinding()]`,
  `[OutputType(...)]`, `[Alias(...)]`, or
  `[Diagnostics.CodeAnalysis.SuppressMessageAttribute(...)]` but no
  explicit `param()` declaration. PowerShell silently accepts the
  omission, but the attributes then have no scope and tools
  (PSScriptAnalyzer, Get-Help) cannot find them. No direct
  PSScriptAnalyzer equivalent. Default: enabled.
- **PSA2008 (Info) — `$Script:Foo++` / `+=` / `-=` without prior
  initialization.** Detects in-place mutations of script-scoped
  variables that lack a preceding plain `$Script:Foo = ...`
  initialization. Coercion (`$null + 1 = 1`) is type-fragile; the
  rule encourages an explicit initial value. No direct
  PSScriptAnalyzer equivalent. Default: enabled.

### Changed

- **PSA2002 — significantly expanded `RISKY_SHADOW_VARS` set.** The
  v3.5.x list contained only 8 auto-variables; v3.6.0 expands it to
  match the PowerShell engine's actual automatic-variable inventory
  (38 entries), including the previously-missed `$Event`,
  `$EventArgs`, `$EventSubscriber`, `$Sender`, `$Error`,
  `$PSCmdlet`, `$PSBoundParameters`, `$MyInvocation`, `$Home`,
  `$Profile`, etc. The `$null` auto-variable is deliberately
  excluded because `$null = <expr>` is the canonical PowerShell
  "discard" idiom (`$null = $list.Add(1)` is the value-suppressing
  equivalent of `[void]$list.Add(1)`); PSScriptAnalyzer follows the
  same exemption.
- **Header docstring updated** to list all 8 new / refined rules
  with the `(new in v3.6.0)` annotation.
- **`__version__` bumped from `3.5.1` to `3.6.0`.** Per
  [SemVer 2.0.0](https://semver.org/), this is a **minor** release:
  new rules are added (additive), and the existing rule set retains
  its semantics. The `PSA2002` expansion of `RISKY_SHADOW_VARS` is
  a behavioural broadening — code that was previously silent may now
  emit PSA2002 warnings — but the rule's documented intent ("flag
  assignments to risky auto-variables") is unchanged, and the
  default-on / Warning level is preserved.
- **`VERSION` file updated to `3.6.0`.**

### Verification

- All 5 in-repository / sibling-repository scripts continue to pass
  the canonical 0/0/0 baseline:
  - `Download-SpeakerDeck.ps1` (ai-generated-artifacts): 0/0/0
    (after inline PSA3006 suppression for an intentional WMI
    fallback in `Show-PowerShellEnvironment` and the addition of
    `[OutputType([pscustomobject])]` to two helpers).
  - `Deploy-AMDChipsetDriverOnWindowsServer.ps1`,
    `Deploy-AMDGraphicsDriverOnWindowsServer.ps1`,
    `Deploy-AMDNpuDriverOnWindowsServer.ps1`,
    `Deploy-MSBthPanInboxOnWindowsServer.ps1`
    (Deploy-Drivers-For-WindowsServer): all 0/0/0
    after backporting the same fixes (renamed
    `$home` → `$winHomeLocation`, `$profile` → `$osProfile`,
    added `[OutputType([...])]` to all 23 functions that return
    a value, added PSA3006 inline suppression to 15 intentional
    WMI fallback lines).
- PSA8001 (cross-script function-body drift) regression: the 6
  shared helpers governed by PSA8001 in Deploy-Drivers retain
  byte-for-byte parity across all four scripts after the v3.6.0
  uplift. The known per-script helper
  `Get-OrEnsureSecureBootBaseline` continues to drift by design
  (already in `.psa.config.json` `psa8001_ignore_functions`).

### Also included in this release (carried over from the previous unreleased pool)

- **GitHub Actions CI workflow enforcing the three self-quality gates
  on every push and pull request.** New workflow:
  `.github/workflows/scripts__python__powershell-static-analyzer.yml`.
  - Pillar 1 (`pytest test_psa_rules.py`) — runs the full rule
    self-test suite that ships in this directory.
  - Pillar 2 (`python3 psa.py --config-check .psa.config.json.template`)
    — validates the shipped configuration template against the
    documented schema.
  - Pillar 3 (`python3 psa.py --self-check`) — verifies that
    `SPEC.md` §4 rule headings agree with the runtime RULES table.
  - Triggers: push / pull_request on `main` when `psa.py`, `VERSION`,
    `test_psa_rules.py`, `SPEC.md`, `.psa.config.json.template`, or
    the workflow file itself changes; plus `workflow_dispatch`.
  - Timeout tier: T1 (30 minutes) per repository-root `/SPEC.md`
    §4.1. Fork-PR `if`-guard per `/SPEC.md` §5.
- **`SPEC.md` §12.6 *Continuous Integration in this repository*.**
  A new subsection that records where the CI workflow lives and
  points to repository-root `/SPEC.md` for governance.
- **CI status badge** in `README.md` and `README.ja.md` immediately
  after the title.
- **Documentation: cross-link to consumer-side adoption.**
  `SPEC.md` §12 gained a new informative subsection §12.5
  *Consumer-side adoption* recording how `--config-check` (§12.2)
  and `--self-check` (§12.3) are wired into a downstream
  repository's workflow. `README.md` and `README.ja.md` *Verified
  consumers* table entry for `Deploy-Drivers-For-WindowsServer`
  now lists all four pipeline scripts.


  - Pillar 1 (`pytest test_psa_rules.py`) — runs the full rule
    self-test suite that ships in this directory.
  - Pillar 2 (`python3 psa.py --config-check .psa.config.json.template`)
    — validates the shipped configuration template against the
    documented schema.
  - Pillar 3 (`python3 psa.py --self-check`) — verifies that
    `SPEC.md` §4 rule headings agree with the runtime RULES table.
  - Triggers: push / pull_request on `main` when `psa.py`, `VERSION`,
    `test_psa_rules.py`, `SPEC.md`, `.psa.config.json.template`, or
    the workflow file itself changes; plus `workflow_dispatch`.
  - Timeout tier: T1 (30 minutes) per repository-root `/SPEC.md`
    §4.1. Fork-PR `if`-guard per `/SPEC.md` §5.
- **`SPEC.md` §12.6 *Continuous Integration in this repository*.**
  A new subsection that records where the CI workflow lives and
  points to repository-root `/SPEC.md` for governance. The four
  normative subsections §12.1–§12.4 and the informative §12.5 are
  unchanged.
- **CI status badge** in `README.md` and `README.ja.md` immediately
  after the title.

### Changed

- **Documentation: cross-link to consumer-side adoption of the
  self-quality gates.** Following the verified consumer
  [`usui-tk/Deploy-Drivers-For-WindowsServer`](https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer)
  publishing its own SPEC §A.11.6 *Self-quality gates for `psa.py`
  (consumer-side usage)*, the upstream documentation in this
  directory gained the reciprocal cross-references:
   - `SPEC.md` §12 gained a new (informative, non-normative)
     subsection §12.5 *Consumer-side adoption* that records how
     `--config-check` (§12.2) and `--self-check` (§12.3) are wired
     into a downstream repository's workflow, with a direct link
     to the verified consumer's §A.11.6. The four normative
     subsections §12.1–§12.4 are unchanged; §12.5 is purely a
     pointer to where to read the downstream half of the story.
   - `README.md` and `README.ja.md` *Verified consumers* table
     entry for `Deploy-Drivers-For-WindowsServer` now lists all
     four pipeline scripts (`Deploy-AMDChipsetDriverOnWindowsServer.ps1`,
     `Deploy-AMDGraphicsDriverOnWindowsServer.ps1`,
     `Deploy-AMDNpuDriverOnWindowsServer.ps1`,
     `Deploy-MSBthPanInboxOnWindowsServer.ps1`) — the BthPan script
     was previously omitted — and the Reference column now links
     both to SPEC §A.11 (analyzer setup, version policy, baseline)
     and to SPEC §A.11.6 (consumer-side `--config-check` /
     `--self-check` adoption), giving readers a single hop from
     the upstream consumer list to the downstream usage docs.
- `psa.py` itself, `test_psa_rules.py`, `VERSION`, and the
  `.psa.config.json.template` are unchanged. The three
  self-quality gates remain at the 3.5.1 baseline (104 test cases
  pass, `--self-check` green, `--config-check` clean against the
  shipped template).

## [3.5.1] — 2026-05-19

### Fixed

- **`PSA5004` (Hardcoded `ComputerName`) now actually fires.** The
  rule's regular expression matches the pattern `-ComputerName
  "literal"` (or single-quoted), but `analyze_text()` was passing
  it the output of `strip_strings_and_comments()` — where every
  string literal is collapsed to whitespace — so the rule could
  never observe its intended trigger. The function was changed to
  accept BOTH the raw `text` and the stripped `clean` form
  (matching the existing two-argument pattern used by
  `check_balance(text, clean, ...)` and other rules):

   - The regex now scans the raw `text`, so the string literal is
     visible and its host value can be reported.
   - The matched span is then validated against the same range in
     `clean`: the bareword `-ComputerName` survives the stripper
     when it appears as actual code, but is blanked when it
     appears inside a comment or another string literal. This
     position-based cross-check (sound because
     `strip_strings_and_comments()` preserves character positions
     one-to-one) correctly suppresses three classes of false
     positives:

      - `# Invoke-Command -ComputerName "server01"` (in comments)
      - `$cmd = "Invoke-Command -ComputerName \"server01\""` (in
        outer string literals)
      - `$msg = "Use -ComputerName 'foo' carefully"` (in any other
        string literal that happens to contain the keyword)

  The whitelisted hosts (`localhost`, `.`, `127.0.0.1`) and the
  variable-argument negative case (`-ComputerName $target`)
  continue to be silent. SPEC.md §4.21 already specified this
  behaviour; the implementation was lagging.

- `test_psa_rules.py` PSA5004 coverage was expanded from the
  3.5.0 baseline-locking pair (which pinned the buggy
  non-firing behaviour) to 10 cases that exercise positive
  detection, the three whitelist values, both quote styles,
  case-insensitive matching, and the three false-positive
  defences listed above.

### Notes — verification

- All four `Deploy-Drivers-For-WindowsServer` pipeline scripts
  (Chipset / Graphics / NPU / MSBthPan) remain at the 0 / 0 / 0
  baseline under `psa.py 3.5.1`, both with the
  repository-shipped `.psa.config.json` and under `--include
  PSA5004` (which forces PSA5004 even though it is on by
  default). Manually re-verified: none of the four scripts
  contains a hardcoded `-ComputerName` literal in code paths.

- The three self-quality gates (`test_psa_rules.py`,
  `--self-check`, `--config-check`) all exit `0` on the 3.5.1
  mainline tree. The Pillar 1 suite runs 104 test cases at this
  baseline (96 per-rule + 3 PSA8001 cross-file + 5 CLI
  self-quality, an increase of 8 from the 3.5.0 baseline of 96
  total — entirely the new PSA5004 positive / whitelist / edge
  fixtures).

## [3.5.0] — 2026-05-19

### Added

- **`--config-check PATH_OR_URL`**: validate the schema of a
  `.psa.config.json` (JSONC) file or http(s) URL and exit. The check
  reports unknown top-level keys, unknown rule IDs in `enable` /
  `disable`, `enable` ↔ `disable` conflicts, bad `severity` values,
  non-positive integers for `max_line_length` / `max_function_lines`,
  type errors throughout, and uncompilable regex patterns in
  `psa8001_ignore_functions`. Every problem is enumerated; the
  checker continues to the end rather than stopping at the first
  violation, so a single CI run sees the full picture. Exits `0` on
  a clean config, `2` on any error. (Pillar 2 of the self-quality
  gate design — see SPEC.md §12.2.)

- **`--self-check`**: verify that the sibling `SPEC.md`'s rule
  catalog (every `### 4.N PSAxxxx — Title` heading in §4) matches
  the `RULES` table compiled into the running `psa.py`. The check
  is symmetric — both "documented in SPEC.md but missing from
  RULES" and "in RULES but missing from SPEC.md" are reported. The
  `### 4.32 PSAPxxxx — Project / pipeline convention rules` overview
  heading (an ID-less grouping heading covering §4.33–§4.36) is
  explicitly skipped by the parser. Exits `0` on agreement, `2` on
  drift detected, or `2` if `SPEC.md` cannot be read. (Pillar 3 of
  the self-quality gate design — see SPEC.md §12.3.)

- **`test_psa_rules.py`**: full-catalog regression suite replacing
  `test_psap_3_4.py`. Ships fixtures for every rule in the `RULES`
  table (positive + negative + edge cases per rule), plus PSA8001
  cross-file fixtures driven through `collect_function_bodies()` /
  `check_function_sync()`, plus subprocess-driven CLI assertions
  for `--config-check` and `--self-check` (including dynamically
  created broken configs in a tempdir). 96 test cases at the 3.5.0
  baseline, no third-party dependencies (`python3
  test_psa_rules.py`). (Pillar 1 of the self-quality gate design —
  see SPEC.md §12.1.)

- **SPEC.md §12 "Self-quality gates"**: new normative section
  describing the three pillars (Pillar 1 / Pillar 2 / Pillar 3),
  the design principle that the implementation lives inside `psa.py`
  (not in the test suite) so consumers and CI exercise identical
  code paths, and the release-process checklist that all three
  commands (`test_psa_rules.py`, `--self-check`, `--config-check`)
  must exit `0` on the mainline before a version is tagged.

### Changed

- **`SPEC.md` §3 (Command-line interface)** updated:
   - §3.1 synopsis adds the two new short-form invocations.
   - §3.3 options table adds rows for `--config-check` and
     `--self-check`.
   - New §3.6 documents `--config-check` (categories reported,
     short-circuit semantics: it does NOT read the implicit
     `./.psa.config.json` and runs before `Config.load()` so a
     broken config can still be diagnosed).
   - New §3.7 documents `--self-check` (which §4 headings are
     scanned, which is skipped, and the exit-code contract).

- **`ANSI_GRN`** colour constant added to the small ANSI palette
  used by terminal output, so `--config-check` and `--self-check`
  can show a green "all good" line in addition to the existing red
  / yellow severity colours.

### Notes — known limitation not addressed in this release

- **`PSA5004` (Hardcoded `ComputerName`) is currently a no-op in
  the standard pipeline.** While auditing rule coverage for the
  new test suite, the maintainer observed that
  `check_hardcoded_computername()` matches against a quoted string
  literal, but `analyze_text()` passes it the output of
  `strip_strings_and_comments()` (where every string literal is
  collapsed to whitespace). The rule therefore never fires on its
  intended pattern. `test_psa_rules.py` pins the current (silent)
  behaviour with a baseline test so any future fix is flagged as
  an intentional behaviour change rather than a silent regression.
  This pre-existing gap has not affected the
  `Deploy-Drivers-For-WindowsServer` sister-repository scripts:
  none of the four pipeline scripts contains a hardcoded
  `-ComputerName` literal. Fixing the rule is tracked separately
  and will land in a future release. **(Update: fixed in 3.5.1 —
  see the entry above.)**

## [3.4.0] — 2026-05-19

### Added

- **`VERSION` file** alongside `psa.py` in the same directory. Contains
  a single ASCII line with the current SemVer (no leading `v`, no
  trailing whitespace beyond the terminating newline). This file is
  the **canonical bytes-only carrier** of the analyzer version,
  consumable without invoking Python:

  ```bash
  curl -sSL https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/VERSION
  # → 3.4.0
  ```

  This enables AI / LLM-driven and CI workflows to discover the
  current mainline version of `psa.py` cheaply (one HTTP GET,
  no git clone, no Python interpreter required) before deciding
  whether to refresh a locally-cached copy.

- **Startup self-check**: when `psa.py` runs and the `VERSION` file
  is present in the same directory, the analyzer verifies that the
  string in `VERSION` matches `__version__` inside `psa.py`. On
  mismatch it writes a structured warning to stderr containing
  explicit AI / LLM-facing action items (re-fetch the latest
  `psa.py` + `VERSION` pair, re-run the affected PowerShell test
  suites, re-evaluate `.psa.config.json` `enable` lists against
  the latest `SPEC.md`). Analysis still proceeds — results are
  flagged provisional in the warning text but the exit code is
  unchanged. The check is suppressed for `--list-rules` and
  `--check-env` (purely informational modes) and is a silent
  no-op when `VERSION` is absent (the supported single-file
  consumer pattern remains fully compatible).

### Changed

- Documentation throughout the `ai-generated-artifacts` repository
  no longer references a fixed `psa.py` version (e.g. "psa.py
  3.3.0"). Consumers are directed to fetch the latest mainline
  via the `VERSION` file and to re-evaluate their `.psa.config.json`
  whenever the version changes. See repository-root `README.md`
  "psa.py Versioning Policy" for the canonical workflow.

### Notes

- This is a **non-breaking** minor bump. All `3.3.0` rules,
  CLI flags, output formats, and configuration schemas are
  preserved unchanged. The `VERSION` file is additive; the
  startup self-check is additive and produces no behaviour
  change in the matching-version case. Existing consumers that
  copied `psa.py` as a single file without sibling metadata
  continue to work unchanged (no `VERSION` file → no warning).

## [3.3.0] — 2026-05-18

### Added

- **`PSAP0003`** (warning, default OFF, opt-in via `.psa.config.json`):
  inline revision-tag comments. Fires on `# rNN:`, `# rNN+:`,
  `# rNN-update:`, `# ---- rNN: ----`, and `# (rNN) ...` patterns
  inside comments. Tags inside string literals and uses of `rNN`
  inside legitimate variables (e.g. `$Script:ScriptVersion = '...-r60'`)
  are left alone.
- **`PSAP0004`** (warning, default OFF, opt-in via `.psa.config.json`):
  end-of-file `REVISION HISTORY` / `CHANGELOG` / `VERSION HISTORY`
  comment blocks. Fires once per matching header line.
- New `test_psap_3_4.py` self-test fixture (18 cases) verifying both
  rules against positive matches, negative cases (prose mentions,
  string-literal contents, here-strings), and edge combinations.

### Implementation

Both rules share a dedicated PowerShell tokeniser
(`_comment_start_positions`) that classifies every `#` in the input
as comment-start vs in-string vs in-here-string vs in-block-comment.
This is more precise than relying on `strip_strings_and_comments()`
alone because string contents and comment contents are both stripped
to spaces in the latter, making them indistinguishable by position.

### Rationale

Both rules enforce the **"revision history lives in CHANGELOG.md, not
in the script body"** discipline. They complement the existing
PSAP0001 / PSAP0002 family and codify the discipline described in
[Deploy-Drivers-For-WindowsServer `SPEC.md` §A.13](https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer/blob/main/SPEC.md)
("Where revision history lives").

### Notes

- No other rule semantics changed in 3.3.0. Repositories that do not
  enable `PSAP0003` / `PSAP0004` see no behaviour difference vs 3.2.0.

## [3.2.0] — 2026-05-17

### Added

- **`PSA8xxx` — Cross-file consistency** (new rule category)
  - **`PSA8001`** (warning, default ON, cross-file): function body
    hash drift across files in the same scan. When two or more files
    in the same `psa.py` invocation define a function with the same
    NAME but with different normalized bodies, every occurrence is
    flagged. The rule is silent on single-file invocations (no peers
    to compare against).
  - New tunable `psa8001_ignore_functions` (list of exact names and/or
    `regex:` patterns) to suppress drift reports for functions that
    are intentionally per-script.
- **`PSA9xxx` — Complexity metrics** (new rule category)
  - **`PSA9001`** (info, default OFF): function body exceeds
    `max_function_lines` (default 200). Opt-in; threshold is
    project-dependent.
  - **`PSA9002`** (warning, default OFF): external-process invocation
    (the `&` operator, `msiexec`, `signtool`, `inf2cat`, `pnputil`,
    `bcdedit`, `sc.exe`, `regsvr32`, `wevtutil`, `dism`, `gpupdate`,
    `certutil`, `reg.exe`, `cmd.exe`, `powershell`) without a
    `$LASTEXITCODE` / `$?` / `.ExitCode` / `-PassThru` reference
    within 5 lines after.
- **`PSAPxxxx` — Project / pipeline convention rules** (new rule
  family — **all disabled by default**; opt in via `.psa.config.json`)
  - **`PSAP0001`** (warning, default OFF): phase function naming
    convention `Invoke-(Prep|Verify|Inst)PhaseNN_DescriptiveName`.
  - **`PSAP0002`** (warning, default OFF): required script-identifier
    variables `$Script:ScriptVersion` / `$Script:ScriptHash` /
    `$Script:ScriptShortTag`.

  The `PSAPxxxx` family holds opinionated conventions tied to a
  specific pipeline style. The conventions shipped in 3.2.0 originated
  in the [Deploy-Drivers-For-WindowsServer](https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer)
  repository; other repositories can adopt them via the same opt-in
  mechanism.
- **`PSA3005`** (warning, default ON): `Start-Transcript -Path` should
  be `-LiteralPath`. `Start-Transcript -Path` performs wildcard
  expansion on its argument; paths containing PowerShell metacharacters
  (`[`, `]`, backtick) are misinterpreted. `-LiteralPath` disables
  expansion and is the safer default.
- New configuration tunables:
  - `max_function_lines` (int, default 200): threshold for PSA9001.
  - `psa8001_ignore_functions` (list, default `[]`): suppress PSA8001
    for the listed function names.

### Fixed

- **`PSA1001` (brace balance)**: the string tokenizer now correctly
  handles PowerShell's `""` (double-quote-doubling) escape AND the
  `` `` `` (double-backtick) escape. The previous implementation could
  mis-parse strings of the form `` "...`""..."` `` or
  `` "...``\"..."` ``, leaving the parser stuck in
  double-quoted-string state and consequently miscounting braces for
  the rest of the file.
- **`PSA2001` (undefined variable)**: the scope-qualifier set is
  extended to include `script`, `global`, `local`, and `private`.
  References of the form `$Script:Foo` are now treated as
  runtime-deferred (the author has explicitly declared a scope, so the
  analyzer respects that intent) and never produce false-positive
  "undefined variable" reports.
- **`PSA4001` (TODO/FIXME marker)**: the marker-matching now requires
  a colon or whitespace-then-letter after the marker, and ignores
  embedded string literals like `"XXX"` inside comments. Previously,
  comments mentioning marker words inside quoted strings produced
  spurious reports.

## [3.1.0] — Earlier

### Added

- **`PSA7xxx` — File format / encoding** (new rule category, for
  file-level checks that operate on raw bytes before UTF-8 decoding).
- **`PSA7001`** (warning, default ON): PowerShell script lacks UTF-8
  BOM. Windows PowerShell 5.1 falls back to the system Active Code
  Page (Shift-JIS / cp932 on ja-JP) when a `.ps1` file has no BOM and
  contains non-ASCII bytes, causing mojibake. Adding the three-byte
  UTF-8 BOM (`0xEF 0xBB 0xBF`) at the start of the file forces correct
  interpretation regardless of console code page.

### Changed

- **`analyze_text()` signature** extended with optional `file_meta`
  parameter (backward compatible — existing callers passing only
  `(text, cfg)` are unaffected; PSA7xxx rules become no-ops when
  `file_meta` is absent).
- **`main()` file reader** switched from `path.read_text()` to
  `path.read_bytes()` so the BOM can be inspected before decoding
  (`read_text` silently strips BOM, defeating any in-text inspection).

## [2.3.0] — Earlier

### Changed

The `--config <URL>` code path is now production-grade:

- **Browser-like User-Agent** (Chrome 131) plus `Sec-Ch-Ua` client
  hints, so CDN / WAF defaults that block obvious bot UAs (notably
  Cloudflare-fronted sites) do not interfere.
- **Explicit TLS 1.2 minimum**, maximum auto-negotiated to TLS 1.3
  against modern servers. Old TLS 1.0 / 1.1 are not offered
  (RFC 8996). Certificate verification is always on.
- **Exponential-backoff retries** on transient failures, modelled on
  the `Invoke-WebRequestWithRetry` pattern from the companion
  PowerShell project:
  - 5xx responses → retry, waiting `2^attempt × 3` seconds
    (6 s, 12 s, …)
  - Network / timeout errors → retry, waiting `2^attempt` seconds
    (2 s, 4 s, …)
  - 4xx responses → fail immediately (persistent client error)

### Added

- Env-var tuning for CI flexibility:
  - `PSA_CONFIG_TIMEOUT` — per-attempt timeout (default 30s)
  - `PSA_CONFIG_MAX_RETRIES` — total attempts (default 3)
  - `PSA_CONFIG_QUIET` — suppress retry-progress messages on stderr

See [SPEC §5.4](./SPEC.md#54-remote-configuration-http--https) for the
full contract.

## [2.2.0] — Earlier

### Changed

- **Configuration files are now JSONC.** Add `// line comments` and
  `/* block comments */` to `.psa.config.json` as freely as you would
  in JavaScript. Comment-like text inside string literals is preserved
  intact.

### Added

- **`--config` accepts URLs.** In addition to a local path, you can
  point `--config` at any http(s) URL — most commonly a GitHub raw URL
  for sharing a team-wide configuration:

  ```bash
  psa.py --config https://raw.githubusercontent.com/<owner>/<repo>/<branch>/.psa.config.json <script>.ps1
  ```
- **Template file shipped.** A new file `.psa.config.json.template`
  ships next to `psa.py` in this directory.

## [2.1.0] — Earlier

### Added

- Runtime probe (`--check-env` / `--show-env`) that reports whether
  PowerShell and PSScriptAnalyzer are available on the current host.
  The output is purely informational; it never affects exit codes or
  issue counts.

  ```
  ==== psa.py: Environment Detection ====
  psa.py           : 2.2.0
  Python           : 3.12.3 (Linux 6.18.5)
  PowerShell       : pwsh 7.4.6 at /usr/bin/pwsh
  PSScriptAnalyzer : 1.22.0 (available)

  Info:
    PSScriptAnalyzer is available in this environment. For
    comprehensive PowerShell static analysis, consider running
    Microsoft's analyzer in addition to psa.py:

      pwsh -Command "Invoke-ScriptAnalyzer -Path <script>.ps1"
  ```

### Notes

- The probe is particularly useful for AI agents (Claude, etc.) and CI
  sandboxes where the availability of PowerShell may vary per
  execution. It is fast, side-effect-free, and bypasses user profiles
  (`-NoProfile -NonInteractive`).

## [2.0.0] — Earlier

### Added

Major release inspired by Microsoft's [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer)
and Vidar Holen's [shellcheck](https://github.com/koalaman/shellcheck).
It expanded the rule set to **27 rules** and added JSON / SARIF output,
inline suppression, configuration files, and multi-file scanning —
while preserving the single-file, zero-dependency design.

The capability snapshot at the 2.0.0 release time covered:

| Area               | At 2.0.0                                     |
|:-------------------|:---------------------------------------------|
| Rule codes         | `PSA1001`–`PSA6006` (27 rules total)         |
| Output formats     | Text / JSON / SARIF 2.1.0                    |
| Suppression        | `# psa-disable-line`, `next-line`, `file`    |
| Configuration      | `.psa.config.json` + CLI                     |
| File handling      | Multiple files / directories / glob          |
| Color output       | TTY-aware ANSI (NO_COLOR honored)            |
| Heredoc / sub-expr | Full `@"…"@`, `@'…'@`, `$()`, `@()`          |

The rule taxonomy established here (PSA1xxx for structural,
PSA2xxx for variable, PSA3xxx for command, PSA4xxx for comment,
PSA5xxx for security, PSA6xxx for style) has remained stable since
2.0.0. The `PSA7xxx` (file format / encoding) category was added in
3.1.0, `PSA8xxx` (cross-file consistency) and `PSA9xxx` (complexity
metrics) in 3.2.0, and the `PSAPxxxx` family (project / pipeline
convention) was started in 3.2.0 (PSAP0001 / PSAP0002) and extended
in 3.3.0 (PSAP0003 / PSAP0004).

## [Pre-2.0.0]

Pre-2.0.0 history is not recorded in this file. The 2.0.0 release was
the first formal versioning milestone; earlier development was
single-author exploratory work without numbered releases.

---

[Unreleased]: https://github.com/usui-tk/ai-generated-artifacts/compare/main...HEAD
[3.4.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
[3.3.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
[3.2.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
[3.1.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
[2.3.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
[2.2.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
[2.1.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
[2.0.0]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer
