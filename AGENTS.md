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
Specification" section, that Part A is INHERITED from a canonical
sibling SPEC, NOT restated. See §6.

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

---

## 5. SPEC ↔ README ↔ TESTING Doc-Touching Matrix

When any of `SPEC.md`, `README.md`, `README.ja.md`, or `TESTING.md`
is touched, the corresponding downstream files listed below MUST be
touched together — or the PR description MUST explicitly justify
skipping each one.

### Forward dependencies (SPEC → downstream)

| Change in SPEC | Required downstream updates |
|---|---|
| Part A inheritance declaration | **No downstream**: Part A change MUST be made at the canonical sibling SPEC (see §6), not here |
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

### Bilingual lock-step (always)

`README.md` and `README.ja.md` MUST be updated in the same commit.

- Section count and order MUST match — verify via `grep -c '^## '`
- Subsection count MUST match — verify via `grep -c '^### '`
- Code blocks, file paths, parameter names: keep in ASCII verbatim
- Headers and table column labels: use 「全角コロン (：)」 in Japanese
- Per the sibling SPEC `A.12.4`, when both files carry a
  `Lines : NNNN` field, the field values MUST match

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

Part A of a Layer 3 SPEC is the **inherited** layer. The canonical
text lives in the **in-house reference SPEC for each scripting
family** — the repository currently maintains **two** canonical
sibling SPECs, organised by language / target environment:

- **PowerShell scripts**: [`scripts/powershell/download-speakerdeck-oracle4engineer/SPEC.md`](./scripts/powershell/download-speakerdeck-oracle4engineer/SPEC.md), sections A.1–A.14
- **Bash / AWS scripts**: [`scripts/aws/ol-aws-ami-builder/SPEC.md`](./scripts/aws/ol-aws-ami-builder/SPEC.md), sections A.1–A.11

The two canonicals overlap conceptually (reference assets, logging,
error handling, dev workflow) but diverge in concrete form (Bash
idioms vs PowerShell idioms, `env.properties` files vs `param()`
blocks, `shellcheck` vs `psa.py`). A new script's Part A:

- MUST consist of an inheritance declaration (~50 lines)
- MUST reference the canonical sibling SPEC sections **of the same
  scripting family** (do NOT inherit a PowerShell canonical from a
  Bash script, or vice versa)
- MUST NOT restate the canonical text
- MAY have a project-specific extensions subsection (`A.x`) recording
  ONLY deviations or additions

If a new scripting family emerges in the future (e.g., Python pure
scripts beyond `psa.py`, or other shell variants), declare a new
canonical sibling SPEC for that family and update this section
accordingly — do NOT shoehorn a new family into one of the existing
canonicals.

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

### Why LLM agents break this rule

LLM agents reading a Layer 3 SPEC may not realise Part A is inherited
because:

- The inheritance declaration is short and easy to mistake for "stub content"
- LLMs trained on generic software-engineering corpora associate
  "comprehensive Part A" with quality
- The canonical sibling is not always reachable from the Layer 3 SPEC alone

To prevent recurrence:

- BEFORE touching Part A of any Layer 3 SPEC, read the canonical
  sibling SPEC's Part A in full
- BEFORE "improving" Part A by adding content, classify the content:
  if it is generic, propose to the canonical sibling SPEC; if it is
  project-specific, record under `A.x` (extensions)
- NEVER restate the canonical text inline as a "convenience" for readers

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

### In canonical sibling SPECs

The repository maintains two canonical sibling SPECs (one per
scripting family); both are useful references for LLM agents
working in this repository.

**PowerShell canonical** — [`scripts/powershell/download-speakerdeck-oracle4engineer/SPEC.md`](./scripts/powershell/download-speakerdeck-oracle4engineer/SPEC.md):

- §A.13 Development Workflow — iteration cycle, revision discipline,
  and the "reuse before invention" principle
- §A.12 Documentation Language Policy — README bilingual lock-step
  detail with the `Lines : NNNN` match rule
- §A.14 Debug Trace Facility — operation-level diagnostic facility,
  designed to be reused verbatim across PowerShell scripts in this style

**Bash / AWS canonical** — [`scripts/aws/ol-aws-ami-builder/SPEC.md`](./scripts/aws/ol-aws-ami-builder/SPEC.md):

- §A.5 Shell Options and Defensive Coding — the `set -euo pipefail`
  discipline and equivalent Bash idioms for safe error propagation
- §A.7 Env Property File Conventions — `env.properties.<context>-<variant>`
  schema for variant-based Bash builders (one file per release target)
- §A.8 Oracle Linux Version Auto-detection — runtime detection pattern
  that other variant-based Bash builders can reuse
- §A.11 Development Workflow — Bash-idiom iteration cycle (the
  parallel of §A.13 in the PowerShell canonical)

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

> **Metadata guardrail (ADR 0015 §6, interim until the ADR 0011 CRUD tool /
> P3a):** if the change will touch `governance/state/manifest.jsonl` or a
> canonical marker, the governance-state-validator (incl. check G) MUST be green
> on the working tree **at the dry-run, before `git format-patch`** —
> verification-before-patch, not only in the post-`git am` battery. Marker
> `hash=` edits go through `canon-hash-restamp` (§14 item 15), never by hand.

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
12. Did I update `CHANGELOG.md` with the change?
13. Did the change touch a `SPEC.md`? Did I check the Doc-Touching
    Matrix (§5) for downstream impact?
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
15. **Marker hashes are never hand-edited.** To (re)compute or correct a
    canonical marker `hash=`, use the write-side tool —
    `python3 quality-tools/canon-hash-restamp/restamp.py --check` (report) /
    `--write` (fix in place; metadata-only, never a code change). Hand-editing
    a `hash=` value is a deviation; check G (above) will catch a stale or
    hand-stamped hash regardless. This is the tool-mediated write path for
    marker hashes until the ADR 0011 manifest CRUD tool (P3a) subsumes it.

---

## 9. Anti-Patterns (Forensically Documented)

The following anti-patterns have actually occurred in this repository
and should be actively guarded against by LLM agents.

### AP-1. Part A bloat (c40755c regression)

See §6. **Symptom**: Layer 3 SPEC's Part A grows from ~50 lines
(inheritance declaration) to hundreds of lines (restated content).
**Root cause**: LLM mistaking the inheritance declaration for stub
content. **Prevention**: §6 rule; read the canonical sibling Part A
before touching any Layer 3 Part A.

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

---

## When this guide should be updated

Update `AGENTS.md` when:

- A new LLM-typical failure pattern is observed in this repository — add to §9
- A new repository-wide rule that LLM agents must follow is added at
  Layer 0 — cross-reference in §7
- The hierarchical model evolves — §2
- The Doc-Touching Matrix (§5) needs new rows for added document categories

DO NOT update `AGENTS.md` to restate rules that already live in their
canonical locations (root `README.md`, `CONTRIBUTING.md`, per-project
`SPEC.md`). Always cross-reference instead.
