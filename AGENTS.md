# AGENTS.md — Operating Guide for LLM-Assisted Contributors

> This document is the **LLM workflow guide** for the
> `ai-generated-artifacts` repository. It complements (does not
> replace) the human-oriented [`CONTRIBUTING.md`](./CONTRIBUTING.md)
> and the per-project `SPEC.md` files. English only, per the
> repository-wide [Language Policy](./README.md#language-policy).

---

## 1. Purpose and Scope

### Who this is for

- LLM / AI agents (Anthropic Claude, OpenAI GPT, etc.) acting as contributors
- Human contributors who want to understand the "LLM rules of engagement" in this repository

### What this is NOT

- It is NOT a replacement for [`CONTRIBUTING.md`](./CONTRIBUTING.md)
  (the contribution requirements; the WHAT MUST layer)
- It is NOT a replacement for per-project `SPEC.md` files
  (the project-specific contract)
- It is NOT a generic LLM coding tutorial

### What this IS

- A "how to work in **this** repository safely" guide for LLM agents
- A central navigation hub pointing to the existing LLM-relevant
  rules that are dispersed across the root [`README.md`](./README.md),
  [`CONTRIBUTING.md`](./CONTRIBUTING.md), and per-project SPECs
- A consolidation of typical LLM failure patterns observed in this
  repository and the recovery / prevention strategies

The relationship to `CONTRIBUTING.md` is clean: `CONTRIBUTING.md`
states the rules (WHAT MUST); `AGENTS.md` describes the procedure for
following them (HOW TO).

---

## 2. Hierarchical Governance Model

The repository uses a four-layer hierarchical governance model.
LLM agents MUST recognise and respect this structure.

### Layers

| Layer | Location | Role | Examples |
|:-:|---|---|---|
| **Layer 0** | Repository root | Cross-cutting policies | `README.md`, `SPEC.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, this `AGENTS.md` |
| **Layer 1** | Top-level category directories | Category-wide rules | `scripts/README.md`, `documents/research/README.md`, etc. |
| **Layer 2** | Subcategory directories | Subcategory conventions (currently sparse) | `scripts/powershell/`, `scripts/python/` |
| **Layer 3** | Subproject directories | Project-specific files | `scripts/powershell/<project>/{README.md,SPEC.md,TESTING.md,CHANGELOG.md}` |

### Inheritance flow

Rules flow downward only:

```
Layer 0  →  Layer 1  →  Layer 2  →  Layer 3
```

Lower layers MAY extend or specialise upper-layer rules; they MUST NOT
contradict them. When a Layer 3 SPEC has a Part A "Common
Specification" section, that Part A is VENDORED from the canonical
family **spec home** (`governance/spec/<family>.md`) as gate-verified
marker+hash regions (ADR 0019 / 0020), NOT free-hand restated. See §6.

### Sibling-isolation policy

Subprojects at the same level (e.g. `scripts/powershell/A/` and
`scripts/powershell/B/`) MUST NOT modify each other's files. If a
useful pattern observed in one subproject should apply to another,
the agent MUST propose the change at Layer 0 or Layer 1 so all
siblings benefit equally — DO NOT silently fork the convention into
one sibling.

This applies particularly to LLM agents working on subproject A who
notice a useful pattern in subproject B: DO NOT copy it into A's
SPEC.md as a "project-specific convention". Raise it for Layer 0/1
inclusion so the canonical text exists in exactly one place.

### Common-canon extraction timing (rule of two)

A family **spec home** (the canonical Part A common-conventions source, e.g.
`governance/spec/powershell.md`) exists to factor out content that **two or more**
real consumers vendor identically (ADR 0019). Do NOT create a family spec home, or its
doc-set templates, ahead of a grounded second consumer: with a single project in a
family the "common" content is just that one project's content, and extracting it is
premature abstraction — the hashed `vendored` regions would only pin placeholder text.
Extract a spec home when **≥2** family members share *observed* common conventions
(distilled from them, not guessed); scaffold a doc-set template when a new consumer is
imminent or ≥2 consumers need structural standardisation. L1 `doc-format` already
declares each member's intended family applicability, so deferring the L2 realisation
loses no design intent.

---

## 3. Required Pre-Flight Checklist (Before Any Change)

### Session Start Contract (read first, every session)

At the **start of any session or task** — before the per-change checklist
below — read these first; they are the single entry point to current state:

1. **This `AGENTS.md`** — the operating guide (governance model, pre-flight,
   the ABSOLUTE rules of §6).
2. **[`governance/project-management/STATUS.md`](./governance/project-management/STATUS.md)**
   — the **session entry point**: current repo HEAD, phase, next action (step
   granularity), open `[AUTH]`/`[WORKING]` items, the ADR index, and the
   static-point index. It is bounded current-truth — history lives in git,
   decisions live in [`governance/adr/`](./governance/adr/).

When a change touches a *managed unit*, also read the relevant machine-generated
operational state under [`governance/state/`](./governance/state/) (manifest /
observations / ledger / reports). Session-to-session handoff follows
**[ADR 0005](./governance/adr/0005-session-handoff-protocol.md)**: the Tier-P
design docs stay unmanaged (out of repo), `STATUS.md` is the entry, and each
static-point ships as one bundle — never piecemeal.

Before authoring ANY change, an LLM agent MUST:

```
[ ] 1. Read the relevant Layer 0 governance (root README.md, CONTRIBUTING.md, AGENTS.md)
[ ] 2. Read the relevant Layer 1 README (e.g., scripts/README.md)
[ ] 3. Read the immediately target Layer 3 README + SPEC + TESTING
[ ] 4. If touching PowerShell code: stand up the gate runtime (pwsh 7 +
       PSScriptAnalyzer, baseline §8.2) and verify psa.py is at latest mainline
       (see root README.md §psa.py Versioning Policy; full gate = Post-flight §9)
[ ] 5. If touching implementation-describing docs (SPEC / README / TESTING):
       extract implementation ground truth FIRST — see §4
[ ] 6. Identify which Layer the planned change belongs to;
       prefer the highest applicable layer (DRY)
```

The pre-flight is NOT optional. Skipping any step is the most common
root cause of LLM-introduced regressions in this repository.

---

## 4. Implementation Ground Truth Extraction

When updating `SPEC.md`, `README.md`, or `TESTING.md` of any
PowerShell or Python script subproject, the agent MUST extract the
implementation ground truth from the script body and `tests/`
directory **before** authoring any document content.

### What to extract (PowerShell scripts, the common case)

| Source | What it tells you | Where it matters in docs |
|---|---|---|
| `param()` block (`ValidateSet`, defaults, mutual exclusivity) | Canonical parameter list and constraints | README Parameters table; SPEC §B Action map |
| `Invoke-*Phase*` / `Invoke-*Action*` function inventory | Canonical Phase / Action list | README Phase reference; SPEC §B Phase architecture |
| `$Script:ScriptVersion`, `$Script:ScriptTag` | Current revision identifier | CHANGELOG entry; all version references |
| Script header `<#...#>` comment block | Author-stated Purpose, Prerequisites, Known limitations | README "Why this script exists" — **but verify against implementation; the header itself may be stale** |
| `tests/` directory listing + `tests/README.md` | Canonical test suite (T-numbering, assertion counts) | SPEC §C Quality gates; TESTING.md §0 status table |
| `data/` directory listing | Canonical persistent-data layout | SPEC §B File organisation |

### What to extract (Python scripts, e.g. `psa.py`)

| Source | What it tells you |
|---|---|
| `__version__` constant + sibling `VERSION` file | Canonical version |
| Top-level module docstring | Stated purpose |
| Rule / class definitions | API contract |

### How to extract

Use **deterministic tools** (`grep`, `awk`, `sed`, `python3 -c`),
not inference from older documentation. Save the extraction result
to a working file (suggested name: `ground-truth.md`) and reference
it during writing.

Example extraction recipe for a PowerShell script:

```bash
# 1. param() ValidateSet and default
awk '/^param\s*\(/,/^\)\s*$/' <script>.ps1 | head -200

# 2. Phase function inventory
grep -nE "^function Invoke-.*Phase[0-9]+_" <script>.ps1

# 3. Action function inventory
grep -nE "^function Invoke-.*Action" <script>.ps1

# 4. Current version identifier
grep -nE '^\$Script:Script(Version|Tag)' <script>.ps1

# 5. Tests inventory + canonical T-numbering
ls tests/*.py
cat tests/README.md   # for canonical T-numbering and assertion counts

# 6. data/ directory layout (flat vs nested)
find data -maxdepth 2 -type f | sort
```

### Ground truth vs documentation

When ground truth and existing documentation disagree, **trust the
ground truth**. Existing documentation may be:

- **Stale** — an earlier revision's accurate description, never updated
- **LLM-fabricated** — an earlier LLM's confident guess that was never verified
- **Anchored to a deprecated plan** — e.g. "we will add T11..." when T7-T10 already shipped

Update the documentation to match the ground truth. Record the
correction in the relevant `CHANGELOG.md` entry, explicitly naming
the field(s) that were drifted (e.g. "Action ValidateSet had 13
items; README listed 10; corrected to 13").

### Fixture provenance (external-system truth)

A committed test fixture that stands in for an external system's
output (Microsoft Update Catalog HTML / JSON rows, Microsoft Learn
pages, DownloadDialog responses, registry snapshots, and the like)
MUST be a **verbatim capture** of that system's real output — never
hand-authored from the implementation's own assumptions. A fixture
composed to match what the code expects is circular evidence: the
test then confirms the assumption instead of the reality, and every
gate stays green while both are wrong (forensic instance: AP-10).

- **Capture, don't compose.** Produce the fixture from the live
  system (probe tool, collector script, saved response) and commit
  it unedited apart from documented redactions.
- **Record provenance with the fixture.** The fixture itself, its
  side-car (`expected.json` or a fixture note), or the owning
  `tests/README.md` row MUST state the source (system + query), the
  capture date, and the capture method. The established phrasing is
  "VERBATIM <date> live capture, never authored".
- **Authored fixtures are the labelled exception.** Negative /
  malformed-input fixtures MAY be hand-authored and MUST be labelled
  as authored, so nobody mistakes them for captured truth.
- **Re-capture on contradiction, never patch.** When a
  fixture-backed test contradicts observed live behaviour,
  re-capture from the live system first; editing the fixture until
  the test passes is the anti-pattern this rule exists to prevent.

---

## 5. SPEC ↔ README ↔ TESTING Doc-Touching Matrix

When any of `SPEC.md`, `README.md`, `README.ja.md`, or `TESTING.md`
is touched, the corresponding downstream files listed below MUST be
touched together — or the PR description MUST explicitly justify
skipping each one.

### Forward dependencies (SPEC → downstream)

| Change in SPEC | Required downstream updates |
|---|---|
| Part A (vendored common regions) | **Source is the family spec home, not here**: a Part A change MUST be made at `governance/spec/<family>.md` (see §6); each consumer's vendored copies are re-synced (ADR 0019) and the document-conformance gate verifies the doc-region hashes (§8) |
| §B Action map / parameter list | `README.md` "Action reference" + `README.ja.md` mirror + `TESTING.md` §2 smoke checklist |
| §B Phase architecture (phase add / remove / rename) | `README.md` "Phase reference" + `README.ja.md` mirror + `TESTING.md` §0 status table |
| §C.9 Self-verification suite (T-numbering / assertion counts) | `README.md` "Self-verification tools" + `README.ja.md` mirror + `TESTING.md` §0 + `TESTING.md` §5 |
| §B.20 File organisation (data/, tests/, docs/ layout) | `README.md` "Folder layout" + `README.ja.md` mirror |
| Part D new pitfall entry (`D.NN`) | `TESTING.md` §7 cross-reference + Troubleshooting table in `README.md` if operator-facing |

### Backward dependencies (README → SPEC)

| Change in README | Required SPEC updates |
|---|---|
| New parameter / Action mentioned | Must already exist in SPEC §B; if not, update SPEC first |
| New troubleshooting entry | SHOULD cross-reference SPEC Part D; if no `D.NN` exists, add one |

### Backward dependencies (TESTING → SPEC)

| Change in TESTING | Required SPEC updates |
|---|---|
| New test tool added (T11+) | SPEC §C.9 inventory updated |
| Operator-confirmed real-run results | Optional `CHANGELOG.md` entry; SPEC unchanged |

### CI workflow dependencies (workflows → docs)

`.github/workflows/` files are code with no version number of their
own; their only change record is the owning project's `CHANGELOG.md`.
When a workflow file is touched:

| Change in `.github/workflows/` | Required downstream updates |
|---|---|
| Any change to a `projects__<project>__*.yml` workflow | The owning project's `CHANGELOG.md` entry (mandatory — the workflow has no other change record) |
| Any change to a `quality-tools__*.yml` workflow | The owning tool's `CHANGELOG.md` entry (e.g. the psa.py workflow records in `quality-tools/powershell-static-analyzer/CHANGELOG.md`) |
| The set of checks a stage runs changes (step added / removed / re-scoped) | The project's `TESTING.md` CI / stage status rows reconciled in the same commit |
| The local-vs-CI gate split changes | Any doc that enumerates the gate battery (PR checklist under `.github/`, `TESTING.md` §0) reconciled |

Forensic grounding (2026-07-02, iso project): `TESTING.md`'s Stage 1
row claimed the offline T-suite ran in CI long after the workflow
only ran the format check, the config schema gate, psa.py and
PSScriptAnalyzer — drift that persisted precisely because this
matrix had no CI row requiring workflow ↔ TESTING reconciliation.

### Bilingual lock-step (always)

`README.md` and `README.ja.md` MUST be updated in the same commit.

- Section count and order MUST match — verify via `grep -c '^## '`
- Subsection count MUST match — verify via `grep -c '^### '`
- Code blocks, file paths, parameter names: keep in ASCII verbatim
- Headers and table column labels in the Japanese README use the full-width
  colon (`U+FF1A`), not the ASCII `:`
- Per the sibling SPEC `A.12.4`, when both files carry a
  `Lines : NNNN` field, the field values MUST match

### Authoring language and labels (always)

Conversation with the contributor may be in Japanese; **artifacts and labels follow
the rules below regardless of the conversation language.** This complements the
file-by-file [Language Policy](./README.md#language-policy) (which fixes *which files*
are English-only vs bilingual); the rules here fix *which characters* may appear and
*how options are labelled*.

- **In-repo governance and machinery artifacts are English / ASCII only.** This covers
  ADRs, `governance/SPEC.md`, `STATUS.md`, this `AGENTS.md`, manifests and schemas,
  templates, canon code, and tool docs **other than** the bilingual `README` pair. No
  CJK ideographs and no kana in these files. (`§` and the em-dash `—` are allowed
  punctuation, not a violation.)
- **Explicit exception — intentional Japanese.** The bilingual `README.md` / `README.ja.md`
  pair (and `<slug>.en.md` / `<slug>.ja.md` content docs) carry Japanese **by design**,
  as does Japanese held as *data* (e.g. locale error-message detection strings in
  `psa.py`, non-ASCII canonical-JSON test fixtures, a documented mojibake example). These
  are not leaks and are not to be "cleaned".
- **Navigational labels in English-only artifacts are English.** A cross-link to a `.ja`
  companion inside an English-only file (SPEC, TESTING, CHANGELOG, governance docs) is
  labelled "Japanese", never with CJK text: the label is navigation, not quoted data, so
  the intentional-Japanese exception does not cover it. Inside the bilingual `README`
  pair itself, the top-of-file language switcher may carry the native-language label —
  that pair is bilingual by design.
- **Selection / option labels are English letters or numerals** — `(A)` / `(B)` / `(C)`
  or `1` / `2` / `3` — in conversation **and** in artifacts. **Never** kana labels
  (parenthesized hiragana, e.g. a Japanese "i"/"ro"/"ha" sequence) and never katakana
  labels. An option label is structural, not prose, so it is held to the artifact rule
  even mid-Japanese-sentence.
- **Where Japanese is used, kanji MUST be Japanese kanji only.** Chinese characters —
  **Simplified and Traditional non-Japanese forms** — are excluded everywhere (artifacts
  and conversation). Use the Japanese form (e.g. the kanji at `U+8AD6`, never its
  Simplified variant `U+8BBA`); when in doubt for an English artifact, write the English
  word instead.

Rationale (forensic): Japanese option labels once leaked into ADR 0017 / SPEC / STATUS and
had to be corrected metadata-only (commit `90117ca`); a later session leaked a
Simplified-Chinese character (`U+8BBA`) into a handoff document. Both are AI-authoring
slips that this rule exists to prevent. A pre-flight/post-flight CJK sweep (§8) over the
English-only set should return zero; any hit outside the intentional-Japanese exception
is a leak to fix before commit.

### Commit-author identity (always)

Patches are authored by Claude and applied (`git am`) + pushed by the human contributor.
Keep the commit **author** stable and recognizable so the history stays readable across
sessions:

- When Claude authors a commit for a patch, set `git config user.name` to **`Claude`**
  (optionally with a phase note, e.g. `Claude (TF.2 author)`) and `user.email` to
  **`claude@anthropic.com`**. The fixed, recognizable identity is the name `Claude` plus
  the `claude@anthropic.com` email.
- The contributor's `git am` / push supplies the **committer** (the human pusher), so a
  pushed commit reads *author = Claude, committer = the contributor* — the form of commit
  `eb34339`.
- **Never** use ad-hoc or per-session identities (`AI Agent`, `session`, `session@local`,
  `TF2 authoring session`, and the like). Phase / scope context belongs in the commit
  **subject** (and optionally the author parenthetical), never in a drifting name or email.

Rationale (forensic): across sessions the author drifted (`AI Agent <ai@example.com>`,
`session <session@local>`, `TF2 authoring session <session@local>`), lowering commit-log
visibility; the good reference form is `eb34339` (author `Claude … <claude@anthropic.com>`,
committer = the pusher). A stable author keeps "what did Claude author" greppable.

---

## 6. Part A Inheritance Rule (ABSOLUTE)

This is the rule LLM agents most commonly break, including the
agent that authored this document during the SPEC rewrite of
2026-05-27 (commit `c40755c`, corrected in the doc-renewal commit
`8df9ff4`). Memorise it.

### The rule

Per [`scripts/README.md`](./scripts/README.md) "Standard SPEC
Structure":

> Part A — Common Specification: Cross-project conventions inherited
> by every script in this style.

Part A of a Layer 3 SPEC is the **inherited** common-conventions
layer. Its canonical text lives in **exactly one place - the family
*spec home*** (`governance/spec/<family>.md`), registered as a
`spec-region` unit in the manifest. A consumer does not own or
restate this text; it **vendors** it.

**The inheritance mechanism is vendoring (ADR 0019), not a pointer.**
Each Part A region is copied into the consumer's SPEC as a managed
region delimited by `<!-- >>> CANONICAL ... >>> -->` / `<!-- <<< ... -->`
markers carrying a doc-region `hash=` (ADR 0020). The
**document-conformance gate** (`quality-tools/document-conformance-gate/doc_gate.py`)
recomputes each vendored region's hash and compares it to the spec
home, so a drifted or hand-edited copy is caught mechanically (§8).
This **supersedes** the earlier "by-reference inheritance
declaration" model: the inherited text now travels as a gate-managed
copy, not a reference to another project's SPEC. What remains
absolutely forbidden is **free-hand restating** - un-managed prose
duplication outside the marker / hash machinery (the `c40755c`
regression below).

**Per-family state (rule-of-two, §2).** A family gets a spec home only
once **>=2** consumers share observed common content:

- **PowerShell**: spec home `governance/spec/powershell.md` exists
  (Part A regions A.1-A.14, unit `spec.powershell.part-a`). New
  PowerShell consumers vendor from it.
- **Bash**: spec home `governance/spec/bash.md` exists (Part A regions
  A.1-A.8, unit `spec.bash.part-a`), extracted at the rule-of-two
  trigger when the second Bash consumer
  (`projects/bash-rhel-container-testsuite`) joined
  `projects/bash-ol-aws-ami-builder`. Regions are distilled from
  conventions **observed in both consumers**; single-observer
  conventions (phase registries, env-property schemas, OS
  auto-detection) stay in the owning consumer's SPEC as `A.x`
  extensions. New Bash consumers vendor from the home.

A consumer's Part A MAY still carry a project-specific extensions
subsection (`A.x`) recording ONLY deviations or additions; this is
`specific` content, authored by the consumer, never vendored.

**Existing consumers predate this model.** The current Layer 3
consumers (e.g. `download-speakerdeck-oracle4engineer`,
`update-windows-server-iso`) were authored under the prior
by-reference model; their conversion to gate-managed vendored Part A
is performed at **migration**, not assumed retroactively here.

### The anti-pattern (what the c40755c regression did)

The SPEC rewrite at commit `c40755c` "consolidated" Part A from 29
lines (an inheritance declaration) to 365 lines of restated content.
This introduced four problems simultaneously:

1. **Drift risk** — two copies of the same contract that will eventually diverge
2. **Incomplete coverage** — the bloated Part A still did not cover
   the sibling's A.6 (Path Handling), A.9 (CSV conventions), A.10
   (Environment Evaluation), or A.14 (Debug Trace Facility)
3. **Authority confusion** — which copy is canonical when they disagree?
4. **Maintenance burden** — every future sibling Part A change requires
   N+1 file updates instead of 1

Under the vendor model the distinction is sharp: the sanctioned
mechanism **is** a copy — but a *managed* one (marker + doc-region
hash + gate). The anti-pattern is the **un-managed** free-hand copy,
which carries no hash and has no gate to catch divergence.

### Why LLM agents break this rule

LLM agents reading a Layer 3 SPEC may not realise Part A is inherited
because:

- The vendored regions are wrapped in HTML-comment markers (invisible
  when the Markdown renders), so an agent may not realise they are
  managed and edits them in place — silently breaking the doc-region
  hash (the gate, §8, will catch it)
- LLMs trained on generic software-engineering corpora associate
  "comprehensive Part A" with quality
- The spec home is a separate file, not always reachable from the
  Layer 3 SPEC alone

To prevent recurrence:

- BEFORE touching Part A of any Layer 3 SPEC, read the family **spec
  home** Part A in full
- BEFORE "improving" Part A by adding content, classify it: if it is
  generic, propose it to the **spec home** (and re-sync the vendored
  copies); if it is project-specific, record it under `A.x` (extensions)
- NEVER free-hand restate the canonical text inline; the only permitted
  copy is a gate-managed vendored region (marker + hash), verified by
  `doc_gate.py` (§8)

---

## 7. Cross-References (Existing LLM-Relevant Rules)

The following sections of existing files already address LLM-specific
concerns. This guide collects them for navigation; the canonical
text lives in the files listed.

### In root [`README.md`](./README.md)

- [§Language Policy](./README.md#language-policy) — file-by-file
  bilingual vs English-only rule. The rationale specifically names
  LLM-assisted maintenance as the failure mode being prevented
- [§File Format Policy](./README.md#file-format-policy) — UTF-8 BOM
  + CRLF for `.ps1`; UTF-8 + LF for everything else. LLM agents are
  named explicitly as parties subject to the contract; the "mandatory
  tooling rules" subsection contains the binary-mode-write pattern
  that LLM agents MUST use when emitting `.ps1` bytes
- [§Revision History Policy](./README.md#revision-history-policy) —
  CHANGELOG-only for per-version history. LLM-assisted maintenance
  is called out as the specific failure mode this policy prevents
  (LLM agents inserting `# r42:` comments into script bodies)
- [§psa.py Versioning Policy](./README.md#psapy-versioning-policy) —
  the "latest mainline only" rule and the LLM-machine-actionable
  fetch / compare / replace / re-test workflow. This is required reading
  before any PowerShell change

### In [`CONTRIBUTING.md`](./CONTRIBUTING.md)

- "Before opening a PR" checklist — PR-time requirements including
  bilingual lock-step, file format, psa.py latest mainline check,
  Part C quality gate verification, and the ground truth verification
  rule (the latter added in the same cycle as this `AGENTS.md`)

### Part A canonical source and reference SPECs

The canonical Part A common conventions are **vendored from the family
spec home** (§6): for **PowerShell**, `governance/spec/powershell.md`
(unit `spec.powershell.part-a`, gate-verified); for **Bash**,
`governance/spec/bash.md` (unit `spec.bash.part-a`, gate-verified;
extracted at the rule-of-two trigger). The Layer 3 SPECs below remain
useful **worked examples** (concrete idioms), not the canonical Part A
source for their family.

**PowerShell reference** — [`scripts/powershell/download-speakerdeck-oracle4engineer/SPEC.md`](./scripts/powershell/download-speakerdeck-oracle4engineer/SPEC.md):

- §A.13 Development Workflow — iteration cycle, revision discipline,
  and the "reuse before invention" principle
- §A.12 Documentation Language Policy — README bilingual lock-step
  detail with the `Lines : NNNN` match rule
- §A.14 Debug Trace Facility — operation-level diagnostic facility,
  designed to be reused verbatim across PowerShell scripts in this style

**Bash reference** — [`projects/bash-ol-aws-ami-builder/SPEC.md`](./projects/bash-ol-aws-ami-builder/SPEC.md)
(worked example; the canonical Part A source is the spec home `governance/spec/bash.md`,
and this consumer's A.9-A.17 extensions show how project-only conventions sit beside
the vendored regions):

- §A.11 Pipeline architecture (9 phases) — phase registry / entry-exit
  contract pattern for variant-based Bash builders
- §A.13 Env property file conventions — `env.properties.<context>-<variant>`
  schema for variant-based Bash builders (one file per release target)
- §A.14 Oracle Linux version auto-detection — runtime detection pattern
  that other variant-based Bash builders can reuse

---

## 8. Self-Check Gates

LLM agents SHOULD apply three self-check gates during any non-trivial
change.

### Pre-flight (before writing the first character)

1. Did I read the Layer 0 governance for the file I am about to touch?
2. Did I read the Layer 1 README for the directory I am in?
3. If touching implementation-describing docs, did I extract the
   ground truth (§4) and is it accessible during writing?
4. Is the change I am planning at the right Layer? (Could it apply
   to siblings? If yes, propose at the higher layer instead.)
5. Will the commit be authored as **`Claude <claude@anthropic.com>`** (§5
   "Commit-author identity")? Set `git config user.name`/`user.email` before
   committing — never an ad-hoc or per-session name.

> **Metadata guardrail (ADR 0015 §6) — SUPERSEDED FOR MANIFEST-ROW EDITS at P3a.1.**
> `governance/state/manifest.jsonl` rows are now mutated ONLY through the
> self-validating `quality-tools/canon-manifest-tool/` (ADR 0011 §2): it runs the
> governance-state-validator after every op and rolls back on any finding, so a
> manifest-row change can never be committed in an invalid state — direct manifest
> edits stop. The guardrail still governs **canonical-marker edits** (a region unit's
> `version`/`policy`/`binding`/`hash` in `reference-code/.../*.ps1`), which the manifest
> tool does NOT write: those stay verification-before-patch — the governance-state
> validator (incl. check G) MUST be green on the working tree **at the dry-run, before
> `git format-patch`** — and marker `hash=` edits go through `canon-hash-restamp`
> (§14 item 15), never by hand, until the coupled manifest-row+marker write path
> (the deferred `unit-record coupled write`) is built at P6/P7.

> **whole-tool registration convention (`kind=tool`) — governed by [ADR 0021](./governance/adr/0021-whole-tool-registration-convention.md):**
> the manifest's region-helper `required` fields carry **sentinel values** on a whole-tool
> machinery row, since they have no region meaning (the whole-tool null
> convention lives on the OBSERVATION side, baseline §4.4): `change_policy=canonical`,
> `binding_mode=follow-latest`, `platform_scope=cross-platform`, `canonical_version`
> = the tool's own SemVer, and **`tested` = the tool's self-test passes** (re-defined
> for whole-tool: self-test green, not the ADR 0007 canon-test suite). A whole-tool's
> `canonical_version` is NOT a release-gate signal — the ADR 0008 vendoring gate
> (`version >= 1.0.0`) does not apply to whole-tool units (run-as-is / follow-latest, never
> vendored). First applied to `tool.canonical-drift-scanner` at P3.6; the discriminating
> SemVer-heterogeneous second instance is **`psa.py`** (`tool.powershell-static-analyzer`, own
> SemVer `4.3.0`), registered `kind=tool` at **P4**. **[P4.4 RESOLVED]** with rule-of-two met,
> the convention is promoted to **ADR 0021** (current-truth view in `governance/SPEC.md`
> §machinery). `platform_scope` remains `cross-platform` for every whole-tool to date;
> `windows-enhanced`/`windows-only` stay defined for honest future classification (ADR 0013
> parity), to be exercised by a future Windows-bound tool.

### Mid-flight (during writing)

5. Does each section I write correspond to a specific rule in the
   Layer 0 / Layer 1 governance? (Tag mentally or in a working note.)
6. Does each implementation claim correspond to a specific line range
   in the script body or `tests/README.md`?
7. Am I about to restate text that already exists at a higher Layer?
   (If yes, replace with a reference.)
8. When touching `README.md`, am I updating `README.ja.md` in
   lock-step?

### Post-flight (before declaring done)

9. **PowerShell gate (when PowerShell code was touched) — all four,
   config-aware, run-and-green.** `psa.py` alone is NOT the gate.
   a. **Stand up the runtime first** (baseline §8.2): PowerShell 7
      (tar.gz from GitHub Releases → `/home/claude/pwsh`) + PSScriptAnalyzer
      (PSGallery, latest); record the resolved versions. Declaring a gate
      un-runnable without standing up its runtime is a deviation (M4(A)),
      not a pass.
   b. **`psa.py` 0 / 0 / 0**, run **config-aware** — use the target's
      `.psa.config.json`; a new code home MUST carry its own. Default-rule /
      config-less runs are NOT the gate.
   c. **PSScriptAnalyzer 0 / 0 / 0** —
      `Invoke-ScriptAnalyzer -Settings <target>/PSScriptAnalyzerSettings.psd1`;
      a new code home MUST carry its own settings.
   d. **`pwsh` ParseFile 0 errors** + module **Import / offline tests** green.
   "I didn't run it" / "no pwsh" is a deviation (M4(A); escalate per §8.3),
   never a pass.
10. Run `wc -l` on bilingual pairs. The counts should differ by at
    most ~5%. Larger differences suggest a missing section.
11. Run `grep -c '^## '` and `grep -c '^### '` on bilingual pairs.
    Counts MUST match exactly.
11a. **CJK / kana sweep over the English-only set** (§5 authoring rule). Any
    governance or machinery artifact I touched (ADR, `SPEC.md`, `STATUS.md`,
    `AGENTS.md`, manifest/schema, template, canon code, tool doc that is not the
    bilingual `README` pair) MUST contain **no kana and no CJK ideographs** — and
    nowhere may a **Chinese (Simplified/Traditional non-Japanese) character** appear.
    Selection/option labels are English/numeric, never kana. Intentional Japanese
    (the `README.ja.md` pair, `<slug>.ja.md` docs, Japanese *data* strings) is exempt.
12. Did I update `CHANGELOG.md` with the change?
13. Did the change touch a `SPEC.md` or a `.github/workflows/` file?
    Did I check the Doc-Touching Matrix (§5) for downstream impact
    (for workflows: owning `CHANGELOG.md` + `TESTING.md` CI rows)?
13a. If `tests/fixtures/` content was added or modified: does every
    external-truth fixture carry capture provenance (source, date,
    method) per §4, and is every hand-authored fixture labelled as
    authored?
14. If `governance/state/*.jsonl` or `governance/schema/*` was touched,
    OR a **canonical marker** (a `# >>> CANONICAL …` line in a
    `reference-code/<family>/` unit) was touched:
    run the **governance-state-validator** gate —
    `python3 quality-tools/governance-state-validator/validate_state.py` →
    **0 findings (A–G)**: schema validation, canonical_location existence,
    manifest/marker coherence **incl. marker `policy`/`binding` vs manifest
    (D)**, canon coverage, canonical-JSON format, and **marker-hash integrity
    (G)** — each marker's `hash=` MUST equal the ADR 0015 normalized hash
    recomputed from its region body. "I didn't run it" is a deviation
    (M4(A)), not a pass.
14a. **Document-conformance gate (when a doc-set template, the spec
    home `governance/spec/<family>.md`, or any doc-region
    `<!-- >>> CANONICAL … -->` marker under `governance/` was touched).**
    Run the gate —
    `python3 quality-tools/document-conformance-gate/doc_gate.py --check`
    → **PASS, 0 findings**: marker coherence, the doc-region hash for the
    verbatim-canonical regions (`common-fixed` / `vendored`) and
    structural conformance for the rest (`common-parameterized` /
    `specific` / `mixed`), L1 item-membership, and the front-matter
    provenance pin (ADR 0020). This is the **doc-side parallel of check
    G**: the validator's checks D / G and `canon-hash-restamp` (items
    14-15) stay scoped to `reference-code` / `powershell-helper` and are
    **NOT** extended to Markdown (ADR 0020 tool boundary). The write side
    is `doc_gate.py --stamp` (PENDING → real hash / structural sentinel);
    never hand-edit a doc-region `hash=`.
15. **Marker hashes are never hand-edited.** To (re)compute or correct a
    canonical marker `hash=`, use the write-side tool —
    `python3 quality-tools/canon-hash-restamp/restamp.py --check` (report) /
    `--write` (fix in place; metadata-only, never a code change). Hand-editing
    a `hash=` value is a deviation; check G (above) will catch a stale or
    hand-stamped hash regardless. This is the tool-mediated write path for
    marker hashes. (The ADR 0011 CRUD tool — `quality-tools/canon-manifest-tool/` —
    subsumes the **manifest-row** write path at P3a.1; the **marker-hash** write path
    stays here until the coupled manifest-row+marker write — the deferred `unit-record
    coupled write` — is built at P6/P7.)

---

## 9. Anti-Patterns (Forensically Documented)

The following anti-patterns have actually occurred in this repository
and should be actively guarded against by LLM agents.

### AP-1. Part A bloat (c40755c regression)

See §6. **Symptom**: a Layer 3 SPEC's Part A is **free-hand restated**
(un-managed prose duplication) instead of carried as gate-managed
vendored regions - it grows from a small vendored set to hundreds of
lines of hand-copied content. **Root cause**: LLM mistaking inherited
Part A for content to author and copying it outside the marker / hash
machinery. **Prevention**: §6 vendor model - vendor Part A regions
from the family spec home (marker + doc-region hash) and let the
**document-conformance gate** (`doc_gate.py`, §8) verify them; the gate
now **catches** this drift mechanically, which it could not under the
old by-reference model. Free-hand restating remains forbidden.

### AP-2. Action / Phase list drift

**Symptom**: README or SPEC lists N Actions; the script's `param()
ValidateSet` declares N±k. **Root cause**: LLM derives the list from
older documentation rather than from the script body. **Prevention**:
§4 ground truth extraction.

### AP-3. Test-suite number drift

**Symptom**: SPEC §C.9 lists T1-T7 with T7 planned; `tests/README.md`
lists T1-T10 with all implemented. **Root cause**: same as AP-2.
**Prevention**: §4 ground truth extraction; `tests/README.md` is
canonical for T-numbering.

### AP-4. Mixed line endings in programmatic `.ps1` generation

Forensically documented in the sister repository's
[`Deploy-Drivers-For-WindowsServer/SPEC.md` §D.23](https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer/blob/main/SPEC.md#d23-mixed-line-endings-in-programmatically-emitted-ps1-content-python-script-defect).
**Symptom**: a `.ps1` file has some CRLF lines and some LF-only lines;
`pwsh -ParseFile` passes silently; visual diff tools render them
identically; `git diff` is silent until `.gitattributes` rewrites
on `git add`. **Root cause**: Python's `open(path, 'w')` writes
`\n` literally on Linux/macOS, regardless of the destination file's
contract. **Prevention**: root README [§File Format Policy
"Mandatory tooling rules"](./README.md#mandatory-tooling-rules).

### AP-5. Inline revision tags in script bodies

**Symptom**: comments like `# r42: fixed X`, `# r56+: now does Y`
accumulate inside script bodies as revisions stack up. **Root cause**:
LLM treating script comments as a changelog. **Prevention**: root
README [§Revision History Policy](./README.md#revision-history-policy);
`psa.py` opt-in rules `PSAP0003` / `PSAP0004` / `PSAP0005` detect
this anti-pattern in strict mode.

### AP-6. Bilingual divergence (`README.md` vs `README.ja.md`)

**Symptom**: structural divergence between English and Japanese
READMEs after a one-sided edit. **Root cause**: LLM edits English
README in response to a user request without realising the bilingual
companion exists. **Prevention**: §5 bilingual lock-step rule;
[`CONTRIBUTING.md`](./CONTRIBUTING.md) "Before opening a PR"
bilingual-policy item.

### AP-7. Out-of-scope sibling modification

**Symptom**: an LLM agent working on subproject A modifies subproject
B's SPEC.md ("I noticed something better there"). **Root cause**:
LLM recognising a useful pattern but not respecting the
sibling-isolation policy. **Prevention**: §2 sibling-isolation
policy; raise the pattern for Layer 0/1 inclusion instead of forking.

### AP-8. Documentation-only updates without downstream propagation

**Symptom**: a SPEC.md change is committed; the corresponding
`README.md` / `README.ja.md` / `TESTING.md` sections still describe
the previous behaviour. **Root cause**: LLM completing the requested
SPEC edit without consulting the Doc-Touching Matrix. **Prevention**:
§5 Doc-Touching Matrix; CONTRIBUTING.md PR description rule "note
on whether downstream artifacts need follow-up updates".

### AP-9. Self-referential governance non-application

**Symptom**: an LLM agent writes new governance content (e.g., the
Doc-Touching Matrix in §5, the Bilingual lock-step rule in §5, the
Pre-Flight Checklist in §3) and **simultaneously fails to apply that
content to the change it is currently authoring**. Specifically:
introducing a new Layer 0 file (this `AGENTS.md`) without touching
the TOP `README.md` and `README.ja.md` to add the new file to the
repository structure tree, the convention-file list, and the Language
Policy table.

**Root cause**: the LLM treats "writing the rules" and "following the
rules" as separate cognitive phases. When the same change set
introduces the rules AND is itself subject to them, the application
step is silently skipped. This is a structural blind spot — the LLM
has not yet conceptualised the just-written rules as binding on the
current task.

**Prevention**: when authoring §3 / §5 / §6 of this `AGENTS.md`, the
agent MUST re-evaluate every prior file in the current change set
against the newly-stated rules before declaring the change complete.
The Self-Check Gates (§8) MUST be applied to the `AGENTS.md` change
itself, not only to changes the `AGENTS.md` describes. In particular,
the Post-flight gate 13 ("Did the change touch a SPEC.md? Did I
check the Doc-Touching Matrix (§5) for downstream impact?") MUST
be generalised: substitute "any governance file" for "SPEC.md" when
this `AGENTS.md` itself is being modified.

**Forensic occurrence**: detected by the user during review of the
initial Step 6 deliverable (zip dated 2026-05-27). The user observed
that `AGENTS.md` was added to the repository without TOP `README.md`
/ `README.ja.md` being updated in lock-step. The fix added three
references in each of the bilingual TOP README files (repository
structure tree, convention-file list, Language Policy table). This
AP-9 entry itself is part of the corrective commit, preserving the
incident as a permanent lesson.

### AP-10. Fabricated fixture confirming a wrong implementation

Forensically documented in the iso project's 2026-07-02 audit arc
(project `CHANGELOG.md`, tag `setupdu-discriminator-hardfail`; audit
finding F1). **Symptom**: a resolver passes its offline fixture test
yet can never match on the live system — a Setup-DU filter keyed on a
`Products` value (`'Setup Dynamic Update'`) that real Microsoft
Update Catalog rows never carry; the resolved line came back empty,
was silently dropped, and the committed config shipped without its
SetupDU line **while every gate stayed green**, because the fixture
had FABRICATED the assumed `Products` string. **Root cause**: the
fixture was composed from the same assumption the code encoded, so
test and code confirmed each other (circular evidence); compounded
by a silent-drop path with no starvation guard. **Prevention**: the
§4 fixture-provenance rule (external-truth fixtures are verbatim
live captures with recorded provenance; the replacement fixture is
labelled "VERBATIM 2026-07-02 live-Catalog capture, never
authored"), a pinned discriminator regression test against verbatim
rows, and an in-model empty-resolution HARD-FAIL so starvation can
never again be silent.

---

## 10. New Project Bootstrap (Lifecycle Maturity Model)

Every project under `projects/` carries a lifecycle stage — `sandbox` →
`incubating` → `governed` (+ terminal `archived`) — with stage-scoped
governance obligations. The normative model is
[ADR 0024](./governance/adr/0024-project-lifecycle-maturity-model.md)
(stage × obligation table, promotion triggers) and
[ADR 0025](./governance/adr/0025-exploration-mode.md) (the sandbox
default working discipline); `governance/SPEC.md §Execution framework`
is the current-truth view. This section is the operating procedure —
reference, don't restate.

### Birth (sandbox — day one, every new project)

1. Render the doc-set from the template canon
   (`governance/templates/`, provenance pins included): `README.md` +
   `README.ja.md` + `SPEC.md` + `CHANGELOG.md` (+ `TESTING.md` once
   tests exist). Use
   `governance/templates/scaffold-project-bootstrap-prompt.template.md`
   to start the session.
2. Always-on obligations from r01: AI disclaimer + language policy
   (English/ASCII code and commits; bilingual README pair), the
   encoding contract, and syntax gates (`bash -n` /
   `Parser::ParseFile` / `py_compile`).
3. Everything else is EXEMPT at sandbox: no manifest row, no STATUS
   tracking, no full static-analysis gate, no vendoring, no per-phase
   loop. Default working discipline is **exploration mode** (ADR
   0025) — stream-style commits, light gates, and the HARD boundary:
   canon bodies, vendored regions, `governance/`, and Layer-0 root
   docs are untouchable from inside the mode.

### Promotion

- **sandbox → incubating** (at the user's continue/publish decision):
  register the lifecycle record via the CRUD tool —
  `python3 quality-tools/canon-manifest-tool/tool.py register
  --unit-id project.<dir> --kind project --location projects/<dir>
  --maturity incubating` — add the project to STATUS tracking and the
  doc_gate `--reconstructed` battery list, and turn on full static
  analysis + bilingual lock-step enforcement.
- **incubating → governed** (by a conformance pass — one
  reconciliation turning every governed-column obligation green at
  once; the rhel-testsuite B2 pass is the precedent): vendored Part A
  where a family spec home exists, `consumers[]`, offline tests + CI
  workflows, per-phase loop for governance-relevant changes.
  Stage changes are one-flag updates:
  `... update --unit-id project.<dir> --maturity governed`.
- **Graduation (separate-repo spin-out) is NOT a stage** — it is a
  distinct physical event with `maturity=governed` as its
  prerequisite.

### Spikes inside existing projects

A time-boxed exploration inside an incubating/governed project is
declared as an `[EXPLORATION]` entry in the project `CHANGELOG.md`
(scope, goal, timebox), quarantines its working artifacts, and exits
by folding keepers through the project's full gates (ADR 0025 §5).
By-products: knowledge → `documents/research/<topic>/`; runnable
tools/scripts → a new `projects/` entry at sandbox stage.

---

## When this guide should be updated

Update `AGENTS.md` when:

- A new LLM-typical failure pattern is observed in this repository — add to §9
- A new repository-wide rule that LLM agents must follow is added at
  Layer 0 — cross-reference in §7
- The hierarchical model evolves — §2
- The Doc-Touching Matrix (§5) needs new rows for added document categories
- The lifecycle maturity model (stages, obligations, triggers) evolves
  via a superseding ADR — §10 cross-references only

DO NOT update `AGENTS.md` to restate rules that already live in their
canonical locations (root `README.md`, `CONTRIBUTING.md`, per-project
`SPEC.md`). Always cross-reference instead.
