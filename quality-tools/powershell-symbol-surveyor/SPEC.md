# pss.py Specification

> _Maintained in English only per the repository-wide documentation language policy. Japanese readers should refer to the English source-of-truth together with `README.ja.md` where available._

This is the formal specification for `pss.py`, the PowerShell symbol
surveyor maintained in this directory.

**Document version**: see [`VERSION`](./VERSION) (the canonical source of truth, kept in sync with `pss.py`'s `__version__`)
**Applies to**: `pss.py` (latest mainline)
**Status**: **Normative — adjudicated 2026-08-15. Implementation pending.**

For a user-facing overview, see [`README.md`](./README.md). This document
covers the contract between `pss.py` and its callers: CLI, fact catalogue,
model format, normalisation rules, exit codes, and the jurisdiction boundary
with `psa.py`. Anything not specified here may change between patch releases
without notice.

Every quantity cited in Appendix B was measured against a live checkout and is
reproducible; see §14.

---

## Table of contents

1. [Scope](#1-scope)
2. [Architecture](#2-architecture)
3. [Command-line interface](#3-command-line-interface)
4. [Fact specifications](#4-fact-specifications)
5. [Model format](#5-model-format)
6. [Output formats](#6-output-formats)
7. [Jurisdiction boundary with psa.py](#7-jurisdiction-boundary-with-psapy)
8. [Environment requirements](#8-environment-requirements)
9. [Exit codes](#9-exit-codes)
10. [Hashing and normalisation](#10-hashing-and-normalisation)
11. [The dependency graph model](#11-the-dependency-graph-model)
12. [The variable model](#12-the-variable-model)
13. [Self-quality gates](#13-self-quality-gates)
14. [Test-data acquisition](#14-test-data-acquisition)
15. [Requirements derived from observed failure](#15-requirements-derived-from-observed-failure)

Appendices:

- [Appendix A — Fact catalogue index](#appendix-a--fact-catalogue-index)
- [Appendix B — Acceptance baselines](#appendix-b--acceptance-baselines)
- [Appendix C — Adjudicated decision record](#appendix-c--adjudicated-decision-record)
- [Appendix D — Known pitfalls and lessons learned](#appendix-d--known-pitfalls-and-lessons-learned)
- [Appendix E — Open items](#appendix-e--open-items)
- [Appendix F — Provisional revisions pending review](#appendix-f--provisional-revisions-pending-review)

---

## 1. Scope

### 1.1 Purpose

`pss.py` surveys a single PowerShell script and emits **facts** about its
symbols — functions, variables, the references between them, and the regions
the tool could not analyse. Given two such surveys of the same script, it emits
facts about the differences.

It exists to make refactoring auditable. The intended workflow is:

```
[ survey : pss.py ] -> [ modify : project / LLM ] -> [ survey + trace : pss.py ] -> [ adjudicate : the caller ]
```

The separation is load-bearing. Every surveyed refactoring tool struggles
because it must *prove a transformation safe before performing it* — a problem
Opdyke framed in 1992 and which is undecidable in general. By observing after
the fact instead of predicting before it, `pss.py` avoids the undecidable step
entirely. It does not need to know whether a change is safe; it reports what
moved.

### 1.2 Non-goals

`pss.py` **does not**:

- modify source files, or emit patches, edits, or rename instructions;
- assign severity to anything it reports;
- return a pass/fail verdict, in its exit code or anywhere else;
- assert that a change is correct, safe, intended, or complete;
- conclude that one symbol is a rename of another;
- interpret governance markers, manifests, or any other repository-governance
  construct (see §1.5).

### 1.3 The fact test

**A derivation is a fact if its rule is stated in this document and the same
input yields the same value in every conforming implementation.**

The moment a threshold, weight, or similarity score would be needed to reach a
conclusion, the conclusion belongs to the caller and `pss.py` stops at the
evidence. Concretely: the symmetric difference of two callee sets is a fact;
"therefore these are different functions" is not.

Where `pss.py` cannot resolve something, it reports the unresolved item
together with whatever surrounding facts *are* mechanically derivable, and
stops there. Example: for a variable read with no local declaration, `pss.py`
cannot determine which declaration it binds to at runtime, but it can
enumerate the enclosing function's static callers and state which of them
declare that name. The enumeration is a fact; the conclusion is not drawn.

**The rule extends to names, not only to values (normative).** A name on the
interface states what was observed; it does not state what the caller should
conclude. This governs subcommand names, fact-code names and classification
values alike. `PSS7006` already applies it — its four values are deliberately
neutral and carry no priority or severity — and it applies equally one level
up: the workflow of §1.1 gives *adjudicate* to the caller, so no subcommand may
name that stage. `pss.py` makes a refactoring auditable; it does not audit.

Two consequences already realised: the verb for relation-asserted comparison is
`trace`, not `audit` (§4.9); and `PSS8007` names an empty writer set rather
than declaring the variable broken. That second was not merely a wording
preference — "broken" is a claim about run time, and it depends on
`Set-StrictMode`, which the tool does not observe, and on writes the model
cannot carry: §12.2's five declaration sources are all retained as of
`model_version` 3, but a non-literal `Set-Variable -Name`, a `[ref]` write or
a `-Scope` write (§12.1) still leaves no site. A judgement whose premises
the tool cannot see is not a stronger statement than the fact; it is a weaker
one wearing a stronger word.

Only a bounded part of this is mechanically checkable, and §13.1 says which
part: a denylist over the fact-code descriptions and the subcommand help
strings. A denylist stops known words from returning. It does not, and is not
claimed to, detect a judgement expressed in words nobody has listed yet.

### 1.4 Language and file scope

**One PowerShell script per survey. The accepted extension is `.ps1` only.**
`.psm1` and `.psd1` are out of scope. Cross-file resolution is out of scope.

This is not a limitation adopted for convenience. PowerShell resolves variable
reads through dynamic scoping (§12.1), so binding depends on the runtime call
chain. The official implementation of LSP rename for PowerShell reached the
same boundary and scoped itself to a single document
(`PowerShellEditorServices` PR #2152).

`pss.py` is **not** specific to any one project. It is designed to survey any
single `.ps1`, and the properties of the codebase under survey are themselves
reported as facts rather than assumed (§12.6).

### 1.5 Governance neutrality (normative)

`pss.py` **does not recognise, parse, or special-case managed-region markers**
or any other governance construct. Markers are comments, and comments are
removed by every normalisation this document defines (§10), so vendored
regions require no special handling and receive none.

Consequence: `pss.py` remains correct and useful irrespective of the state of
the repository's canon-governance model, and a future change to that model
requires no change to `pss.py`.

Observed corollary, stated as a fact and **not** as a contract: because the
current vendoring convention places exactly one function between a marker
pair, the §10.2 `hash_full` of a vendored function coincides with the region
hash computed by the governance tooling. This was measured over 58 regions
with zero mismatches. Conforming implementations must not *depend* on this
coincidence, and must not break if it ceases to hold.

---

## 2. Architecture

### 2.1 Layers

```
Layer 1  extractor     .ps1  ->  symbol model
Layer 2  model         JSON, the stable interface and the committed artifact
Layer 3  comparator    model x model  ->  delta facts     (no parser involved)
```

The comparator reads only Layer 2. It never parses PowerShell. Consequently
the governance-critical half of the tool has no parsing dependency at all and
runs anywhere the model can be carried.

### 2.2 Parser ownership

The extractor is implemented in Python and owned in-tree. External PowerShell
grammars were evaluated and rejected: `tree-sitter-powershell` reaches 99.6%
agreement with the reference parser on call-graph extraction, but its shipped
artifact is a 128,484-line generated `parser.c`, unreviewable under this
repository's review model and requiring a Node.js toolchain to regenerate. Two
concrete grammar defects were found during evaluation and could not have been
fixed in-tree.

### 2.3 The reference parser is a test oracle, not a runtime backend

PowerShell's own `System.Management.Automation.Language.Parser` defines ground
truth. It is used at **test time only**, to verify the Python extractor by
differential testing. It is never invoked during a normal survey, so `pss.py`
has no PowerShell runtime dependency at run time.

Where `pwsh` is unavailable, the differential test degrades per §14.3. The
suite narrows; it does not break.

### 2.4 The model as a context artifact

The model is a first-class deliverable, not an implementation detail. A
27,229-line, 1.41 MB script does not fit in a language model's context window;
its symbol model does. This constrains the format: readable JSON, flat records
in preference to deep nesting, self-describing keys, and stable human-readable
symbol identifiers rather than opaque ones — the design correction SCIP made
over LSIF.

This requirement is **quantitative, not aspirational**. Emitting one record per
variable reference would produce approximately 4.87 MB for the reference target
— larger than the 1.41 MB source, inverting the tool's purpose. §5.3 therefore
tiers the model by blast radius.

The default survey of the reference target measures approximately **0.9 MB**
compact against a 1.41 MB source. The per-site script-variable records required
by §5.3 account for roughly 40 per cent of that and are not reducible without
losing the tool's primary function: they are what answers *where do I edit*.
Dropping that collection would leave approximately 0.55 MB, but `pss.py` does
not offer it as a choice: `script_variables` is a master collection and §5.6
forbids a master collection from becoming an axis. A consumer that wants only
structure filters the emitted model itself.

A caller that must decide what it can afford before it receives anything is
served by a cost report rather than by a guess (§3). Because the axis payloads
are built during the survey regardless, measuring all of them and emitting only
the measurements costs approximately three per cent over a default survey — so
the report states exact sizes and no estimate is involved.

Serialisation is **compact by default**. The readability this section requires
is a property of self-describing keys and flat records, not of indentation,
which cost 600 KB on the reference target; `--pretty` remains available.

### 2.5 Reuse-by-copy

Per the repository's standalone-tool principle, `pss.py` imports no sibling
tool. Shared logic travels as a verified copy, not an import.

Two copies are made, both from the canonical normalized-hash implementation:

- the **string/comment tokenizer**, copied verbatim and used unchanged for
  `hash_full` (§10.2);
- the **same tokenizer with one policy flag changed**, used for `hash_body`
  (§10.3). The lexical rules are identical; only the disposition of string
  *contents* differs.

Conformance of the first copy is pinned by the shared golden vectors
(§13). Conformance of the second is pinned by `pss.py`'s own golden vectors,
because it deliberately diverges from the shared contract (§10.3).

### 2.6 The operating context: two files, and nothing else (normative)

The originating use is a language model holding **two files that are not in any
repository** — an edit in progress, a generated candidate, a scratch copy — and
asking what changed. The corpus of §14 exists to derive and pin the detection
logic; it is **reference data for the gates, never a runtime input**. Conflating
the two would make the tool useless exactly where it is meant to be used.

Therefore, normatively:

- **`survey` reads one file. `compare` and `trace` read two model documents each.
  `slice` reads
  one.** Nothing else is read: no repository, no corpus, no configuration file,
  no network.
- **Neither `git` nor `pwsh` is required to run any subcommand.** They are
  required by `test_pss.py`, which is a development gate, and their absence
  degrades that gate (§14.3) rather than the tool.
- **The working directory has no influence.** The same inputs produce
  byte-identical output whether the process runs inside this repository or in an
  empty directory on a machine that has never seen it.
- **`source.path` is a label, not a location.** It is carried into the model so
  that a caller can tell two models apart (§5.5), and is never resolved a second
  time.

This is gated two ways rather than assumed (§13.1). Structurally: `pss.py`'s
module imports are held against a declared allowlist, so it has no means of
reaching a subprocess, a socket or an HTTP client — a new import is a deliberate
act that must move the allowlist. Behaviourally: the subcommands are run in an
empty directory that is not a repository, with an environment carrying no
executable search path, and their output must be byte-identical to the same run
made inside this repository.

---

## 3. Command-line interface

This section describes what this build of `pss.py` actually accepts. Design
material that has not landed in code yet lives in §3.1 and is marked there;
it is not repeated here as if it were live syntax.

```
pss.py survey   <script.ps1> [--out <model.json>] [--format text|json]
                             [--axes <axis>[,<axis>...]] [--pretty]
pss.py slice    <model.json> [--scope <id>] [--axes <axis>[,<axis>...]]
                             [--out <model.json>] [--format text|json] [--pretty]
pss.py compare  <a.json> <b.json> [--format text|json]
pss.py trace    <before.json> <after.json> [--format text|json]
pss.py --list-facts
pss.py --self-check
pss.py --capabilities
pss.py --version
```

| Option | Applies to | Meaning |
|---|---|---|
| `--out PATH` | `survey`, `slice` | Write the model to PATH. Default: stdout. |
| `--format {text,json}` | `survey`, `slice`, `compare`, `trace` | Output format. Default `text`. |
| `--axes LIST` | `survey`, `slice` | Comma-separated materialisation axes to restore (`survey`) or narrow to (`slice`), or `all`. Default: none (§5.6). An unrecognised name exits `2`. |
| `--scope ID` | `slice` | Keep only records concerning this symbol identifier, plus incident edges and all limitations (§5.7). An unmatched identifier exits `2`. |
| `--pretty` | `survey`, `slice` | Indent the JSON model. Default is compact (§2.4). |
| `--list-facts` | — | Print the fact catalogue and exit. |
| `--self-check` | — | Verify this SPEC's §4 catalogue, Appendix F provisional index and §5.6 axis vocabulary against the tool's compiled state, and exit (§13). |
| `--capabilities` | — | Print the machine-readable interface descriptor as JSON and exit (§3.1). |
| `--version` | — | Print version and exit. |

There is deliberately no `--severity`, no `--enable`, and no suppression
mechanism. Severity does not exist in this tool, and facts are not suppressed —
they are filtered by the caller when the caller has decided what it cares
about.

**Current build status.** `compare` and `trace` exist as subcommands and can be
invoked, but this build deliberately refuses to run either: each prints an
explanatory message and exits non-zero rather than emitting an empty or partial
comparison (§2.1; the comparator is Layer 3 and has not been built yet).
`--cost` **is implemented** in this build, as `survey --cost`: the model is
computed and discarded, and the report it prints is the block every model now
carries under a single top-level key. `--capabilities` **is implemented**, and
declares the two machine outputs this build does not produce — the delta
records of `compare` / `trace` and the structured error payload — as
`"status": "not-implemented"` with a reason, rather than omitting them or
describing shapes that do not exist (§3.1).

### 3.1 The caller is expected to be a language model

**Implemented.** `--cost`, the embedded cost block and `--capabilities` all
describe this build. Two of the machine outputs the descriptor is required to
carry do not exist yet, and the descriptor says so rather than inventing them;
the mechanism for saying so is specified below and gated in §13.

The model's consumer is the process that performs the refactoring, and in the
originating use that process is another language model (§1.1). Two consequences
are normative.

**The interface must be discoverable without prose.** `--capabilities` emits a
structured document — subcommands, the axis vocabulary of §5.6, the fact
catalogue, exit-code meanings, available output formats and the current
`model_version` — so that a caller can determine what it may ask for without
parsing help text. A descriptor that has drifted from the tool is worse than no
descriptor, because it produces confident wrong requests; §13 therefore gates
the descriptor against this document.

**The descriptor serialises; it does not restate.** Every enumeration it
publishes is read from the constant that already holds it — `FACTS`, `AXES`,
`MODEL_SCHEMA`, `IDENTIFIER_FORMS`, `COLLECTION_KEYS`, `EXIT_CODES` — and the
subcommand list is read from the argument parser, so a subcommand that is
added, removed or renamed cannot go missing from the descriptor. A descriptor
that restated any of these would be the second copy of a fact, and two copies
of one fact drift (ADR 0036, §13.3). §13 checks each block against the constant
it is supposed to be reading, so a literal copied in is caught the moment the
constant moves.

**An output this build does not produce is declared, not omitted.** The
descriptor carries an entry for every machine output listed below, each with a
`status` of `implemented` or `not-implemented` and, in the latter case, the
reason. Omission would be indistinguishable from an oversight, and describing a
shape the tool does not emit is precisely the confident wrong request this
section exists to prevent. The mark is a claim about behaviour and is gated as
one: §13 runs `compare` and `trace` and requires each to refuse, and provokes a usage error
under `--format json` and requires the diagnostic not to be JSON. Implementing
either without moving its mark turns the gate red, so the mark cannot drift
into a lie and cannot be quietly left behind.

**Describing the command line is not enough.** A descriptor that documents how
to invoke the tool but not what comes back leaves a caller able to make a
request and unable to consume the reply. Six external reviewers, across two
model families, each reported the same gap and each recovered the record shapes
by reading sample output — which a caller without samples cannot do, and which
guarantees nothing across versions. The descriptor therefore also carries a
**schema for every machine output**: the record shape of each model collection,
the identifier conventions, the join key for each collection, the delta-record
shape emitted by `compare` and `trace`, the cost-report shape, and the structured error
payload. Ordering and determinism (§5.4) are stated there too, since a caller
that intends to join or diff two models outside the tool depends on them.

Four of those six are carried by the declarations this SPEC already holds:
record shapes and the cost-report shape by §13.3's key-path set, and the
identifier conventions and join keys by §5.8. The remaining two — the delta
record and the error payload — are the two outputs that do not exist in this
build, and are declared `not-implemented` per the rule above.

Errors are machine-readable when machine output was requested: with `--format
json`, a usage error emits a JSON object on stderr carrying a stable category,
the rejected value and the valid vocabulary. The exit code stays `2` per §9;
the category distinguishes *correct the command* from *fix the environment*
from *report a defect*, which the exit code alone cannot. **Not built.** Every
diagnostic in this build is plain text, at all eleven sites; the descriptor
carries `error_payload` as `not-implemented` and §13 holds that mark against
the behaviour.

**The caller must be able to price a request before making it.** `--cost`
reports exact byte sizes and record counts **per collection**, plus the
increment each axis would add, in a payload of a few hundred bytes. A single
total tells a caller whether it can afford the request; a per-collection
breakdown tells it what to do when it cannot, which is the decision actually
being made. The report states what it measured (`"format"`) and binds itself to
its input (`source.sha256`), because a size figure that names neither its
serialisation nor its subject is not a fact under §1.3.

**The baseline of an `axis_increment` is this model's own materialisation.**
An entry's `bytes` is the additional compact-serialised size the model would
gain if that axis were added to the axes it already carries, measured by
re-surveying — an axis's contribution is decided during extraction and is not
recoverable from a model that lacks it. An axis the model already materialises
therefore reports **`0`**: nothing further to add, not nothing measured. On a
slice (§5.7) the entry is **`null`** — the increment cannot be priced from a
model whose collections were cut after extraction, and a carried-over figure
would describe a different artefact (§13.3 nullability). This paragraph
exists because a round-2 reviewer recovered the baseline correctly and only
by comparing a default model against its all-axes twin; an inference that
must be reverse-engineered from two documents is not stated by either.

**The parts must sum to the whole, and the rule that makes them sum must be
written down.** A per-collection figure is the byte length of that
collection's compact-serialised array alone, excluding its key name, colon
and separator; the remainder — the top-level scalars and objects, the key
names and the structural punctuation — is reported as an `envelope` entry.
The identity

```
sum(by_collection[*].bytes) + envelope.bytes == default_model.bytes
```

holds exactly for every model and is checkable by a consumer from the model
file alone. `envelope` is emitted even when it would be zero, so that the
reconciliation is testable rather than inferable. Three external reviewers,
in both model families, independently found a 614-byte discrepancy in a
draft report and could not account for it: a report that governs itself by
reproducibility and cannot reconcile its own arithmetic fails its own rule.

The same block is embedded in every model under a single top-level key, so that
a stored model is self-describing and a caller can strip it in one operation.
The embedded block is **fixed in size** — it must not grow with the model it
describes — and the measurement it reports is defined as the compact model
**excluding the block itself**, so that the value is well-defined rather than
self-referential. `--cost` is then the same computation with the model
discarded, which keeps one derivation rather than two that can drift.

The cost report carries **no recommendation, threshold or warning**. It says how
large a thing is; whether that is too large is the caller's judgement and falls
under §1.2 exactly as severity does.

### 3.2 Consumer review (record)

Twice now the interface has been settled by asking the intended consumer rather
than by reasoning about it here, and both times the answer contradicted what
this document would otherwise have said. The practice is recorded because the
results are cited elsewhere in the specification as evidence, and a citation to
an unrecorded process is not checkable.

**2026-08 (first round).** Six reviewers across two model families each
reported the same gap — the invocation is discoverable and the shape of what
comes back is not — and each recovered the record shapes by reading sample
output. `--capabilities` (§3.1) exists because of that.

**2026-08 (second round).** Two reviewers, given real models and two competing
delta shapes with no context beyond the kit, were asked to perform tasks rather
than to give an opinion. Four results are load-bearing here.

- §4.6's equality requirement has **two axes**, and each candidate shape
  satisfied one and failed the other. One reviewer was actively misled by the
  shape lacking a tally, reading an unimplemented code's silence as a clean
  result. §6.4 exists because of that.
- The per-subject enumeration has **named uses** — certifying a named unit as
  examined-and-unchanged without holding the models, and catching a caller's
  own misspelling, which silence reads as "unchanged".
- **`PSS8008` was identified as the most review-worthy fact in the specimen
  change and was carried by neither candidate**, a function having become
  uncalled. It is implemented ahead of codes that were already prototyped.
- A **specification gap** was found that this repository's own gates could not
  have found: a command in a `foreach` condition was not in command position
  under §10.6's inclusion list as it then stood, so a real call produced no
  edge and its target was reported `PSS4003` (closed at the D10 arc — §10.6).
  The reviewer reached the truth through
  `named_by_literal` and `PSS3001` — the honest-degradation design of §4.4
  working as intended — but the boundary itself was undocumented.

The asking is deliberately narrow. Reviewers are given tasks with answers the
kit can support, told that being encouraging is not useful, and asked for where
they got stuck, what they guessed, and what they got wrong. An opinion on the
design is not solicited and has not been useful when volunteered.

**2026-08-20 (second round).** Two reviewers, one per model family, each given
a kit built from the shipped CLI (models, deltas, `--capabilities`, the two
[F2] candidate shapes as live specimens, and a real `trace`/`compare` pair)
with no repository and no SPEC — the §2.6 operating context, exactly. The
round-1 material defects did not recur, and every quantitative claim in both
responses was verified against the kit before any of it was adjudicated on.
What the round decided or found:

- **[F2] converged on the `lines` array** (§5.9): both reviewers rejected the
  per-site-record candidate for the same two reasons (a forced join on the
  plainest task; the same fact represented twice). The only disagreement —
  default versus axis — was adjudicated to default on the archive argument.
- **[F4] converged on emitting the edge** (§10.6): both ranked it first; one
  demonstrated that the honest-degradation alternative had turned `PSS3001`'s
  own classification claim false for the token in question.
- **Nullability converged on present-but-null** (§13.3): the recorded
  key-omission alternative was put to both and rejected by both; the
  alternative is withdrawn, not deferred.
- **`not_evaluated` was proposed independently by both** and adopted (§6.4),
  as was the position transcription onto `PSS8001`/`PSS8002`/`PSS8004`; the
  `examined_subjects` enumeration both reviewers never used was cut to
  counts by default (§6.4).
- **A declaration-contract gap was found that no gate here had found**: a
  kind-`always` path can be omitted per record (`/symbols[]/parent`, absent
  on 384 of 385 records at the pin) — §13.3's `always` is a per-model claim
  read as a per-record one. Recorded as owed (§13.2), not fixed here.
- **Three documentation defects were reported as guesses forced by the
  shipped surface** and each is closed in this arc: the `axis_increment`
  baseline (§3.1), the meaning of `edges[].line` (§5.9), and the
  `PSS7005`/`PSS7006` value vocabularies (§11.3, now serialised).
- The **in-band provenance** added after round 1 (§6.4) was used by both
  without prompting; one correctly limited it — the delta names its models,
  and only an out-of-band document ties a model to a repository tree, which
  is the design rather than a gap.

**2026-08-20 (third round).** Two reviewers, one per model family, given a
kit built from the shipped `"3"` CLI: models at three materialisations
(default, all-axes, a scope slice), a real generation-pair `trace`/`compare`
with the `--all` twin and an unrelated-pair `compare`, two hand-built
per-record presence-contract candidates with an observed-presence file, and
`--capabilities` — no repository, no SPEC. Every quantitative claim in both
responses — forty-two — was verified against the kit and held. What the
round decided or found:

- **The presence contract converged on a hybrid** (§13.3 Per-record
  presence): variant enumeration with machine-evaluable predicates and
  non-circular discriminators (one reviewer pointed at `depth`, already on
  every symbol record), first-class conditional keys, and a per-path index
  derived from the variants. The decisive evidence against the
  exceptions-only candidate was supplied by the survey's own specimen,
  which violated its own complement rule (`/closures[]/code`, 29 of 509,
  undeclared) — the quiet-failure mode, demonstrated rather than argued.
  The same reviewer extended the scope beyond the round-2 finding to five
  collections; measurement made it six.
- **The two-state transcription on the usage-map family** (§12.7): both
  asked; one proved on the kit's own generation pair that a trace's
  `PSS8007` misreads as introduced-by-B until the raw models are joined —
  the empty-writer state predated the change. `baseline_state` /
  `successor_state` exist because of that.
- **The slice's projection rules were recoverable only by comparing
  outputs**: one reviewer reverse-engineered kept-in-full `limitations` and
  source-global aggregate figures from slice/parent pairs; the other hit
  the cut symbol records of every edge endpoint (33 of 33 at the kit's
  slice). The contract is declared (§5.7, `slice_projection`); the boundary
  stubs are a model change, inventoried (§13.2) to be adjudicated together
  with the variant declaration they would extend.
- **Two declaration holes no gate here had found**: `source_path_differs`
  present in a real document and absent from the declared shape (now
  `top_level_conditional`, both directions gated), and the never-stated
  rules that `<script>` is a delta subject but no examined subject and that
  the default counts compress exactly the `--all` enumeration (§6.4). A
  reviewer misclassifying a delta-field ask as a version-arc item exposed
  that the delta document's own standing was unwritten (§6.4).
- **Method**: one kit was contaminated in delivery — the orchestrator-side
  answer key travelled in the same package as the reviewer archive. The
  root cause was the packaging, not the reviewer, who disclosed before
  answering, re-derived every figure, and correctly partitioned what the
  exposure voided (the decidability measurements) from what it could not
  touch (the walked workflows, which had no key). Two rules are adopted
  from the round: the delivery to a reviewer contains exactly the startup
  message and the kit archive, verified by listing; and hand-built
  specimens declare their own coverage status, so a deliberately partial
  candidate cannot be mistaken for a defective complete one.

---

## 4. Fact specifications

This section is normative. Facts are identified by `PSS` plus four digits,
blocked by first digit. Blocks 1-4 are single-state facts emitted by `survey`;
blocks 6-8 are delta facts emitted by `compare` and `trace` (§4.9); block 9 is the tool's
declarations about its own limits and is emitted by both.

Block 9 sharing the identifier space with ordinary facts is deliberate,
following the .NET ApiCompat convention where `CP1001`-`CP1003` ("could not
analyse") sit alongside the difference codes so they cannot be silently
dropped.

### 4.1 PSS1xxx — Definition inventory

| Code | Fact |
|---|---|
| `PSS1001` | A function is defined. Carries name, start and end location, and nesting depth. |
| `PSS1002` | A function's parameter signature: ordered parameter names, declared types where present, and whether each is mandatory. Both `param()` blocks and the inline `function f($a)` form are recognised (§10.1). |
| `PSS1003` | A function's hash triple: `hash_full`, `hash_body`, `hash_raw` (§10). |
| `PSS1004` | A function is defined inside another function's body. Carries the enclosing function's identifier. |
| `PSS1005` | A function name is defined more than once in the file. Carries every definition's location and ordinal. Emitted alongside `PSS9007`. |

### 4.2 PSS2xxx — Reference and binding

**`PSS2005` is now emitted** (resolved after the note below was first
written): every automatic-variable reference gets a `local_variables[]`
`"reference"` record tagged `"code": "PSS2005"` under the `local-sites` axis,
alongside the pre-existing `automatic_refs` aggregate count (`--self-check`'s
codes gate now has a corresponding emission fact to point to; the "Emission
coverage" row at §13.2 tracks this). **The count itself is unresolved and
should not be trusted yet.** Three different measurements of "automatic
variable references on the reference target" now exist and do not agree:
Appendix B.3's `2,004` (source and method not re-derivable from this
document alone), `pss.py`'s own emitted count `2,075`, and a fourth-session
spot-check against real `pwsh` AST (`VariableExpressionAst` nodes whose
unqualified name is in the automatic set) giving `1,336` — a gap too large to
be rounding or a qualifier edge case (re-run with no qualifier filter at all:
still `1,336`). None of the three has been established as correct here; this
needs a dedicated investigation into where `pss.py`'s token scan and the AST
diverge, not a guess. Do not cite any of the three numbers as settled.

**`PSS2002` is emitted for all five of its recognised sources (§12.2) as of
`model_version` 3.** An assignment whose left-hand side is a bare local
variable was the first source to get a `code: "PSS2002"` record under
`local-sites`, split out from the `PSS2003` ("reference to" the same
declaration) records it previously shared a code with. The D10 arc closed the
other four: a `param()` / inline-function parameter and a `foreach` loop
variable are var tokens whose site was always in the stream and is now
classified as the declaration it is; a `Set-Variable` / `New-Variable`
`-Name` and the `-OutVariable` family name their variable in a string
literal, so their site is **synthesised at the name literal's own position**
(§12.2). Measured at the pinned blob: 5,534 `PSS2002` records against the
4,402 the assignment forms alone produced, with `PSS2003` smaller by exactly
the flipped difference — the four sources added sites, not references, and
`counters.variable_refs` is unchanged because a synthesised site is not a
variable token. At script scope the same flip moves a `param()` entry from
`PSS2004` (read) to `PSS2006` (write), which is what lets a script
parameter's declaration reach the usage map as a writer (§12.3, §12.7).

The `PSS4001`/`PSS4002` gap noted at §4.4 is resolved in full — see there.

| Code | Fact |
|---|---|
| `PSS2001` | A static call edge from one caller to a defined function. The caller is a defined function, or the reserved owner `<script>` for a call made at script level. Emitted only where the command name is a literal string in command position (§10.6). |

| `PSS2002` | A variable declaration site. Recognised sources per §12.2. |
| `PSS2003` | A variable reference resolved to a declaration within the same function. |
| `PSS2004` | A scope-qualified variable reference. Carries the qualifier (`script`, `global`, `local`, `private`, or a drive such as `env`). Detected via `VariablePath.IsScript` / `IsGlobal` / `IsLocal` / `IsPrivate` and `DriveName` — see Appendix D.1. |
| `PSS2005` | A reference to a PowerShell automatic variable. The set is closed and enumerated below. The automatic test is applied **before** the declaration test. |

The automatic-variable set (53 names, lower-cased):

```
_ psitem true false null args input error matches myinvocation pscmdlet
psboundparameters pscommandpath psscriptroot pwd host home profile lastexitcode
pid psversiontable stacktrace this ofs shellid executioncontext consolefilename
nestedpromptlevel psculture psuiculture psdebugcontext psemailserver pshome
psedition islinux ismacos iswindows iscoreclr foreach switch sender eventargs
event eventsubscriber verbosepreference erroractionpreference warningpreference
debugpreference informationpreference progresspreference confirmpreference
whatifpreference outputencoding
```

**Check order is normative.** A reference whose name is in this set is automatic
even when the enclosing function appears to declare it. `$null = Get-Thing` is
the output-discard idiom, not a declaration, and `$ProgressPreference = 'X'`
writes a preference variable rather than declaring a local. Applying the
declaration test first misclassifies 254 references on the reference target.

| `PSS2006` | A script-scope declaration made at script level. At script level an unqualified assignment declares a script-scoped variable, so `$Foo = 1` at top level and `$script:Foo` inside a function name the same entity. |
| `PSS2007` | A variable reference occurring inside an expandable (double-quoted) string or here-string. Carries the containing string's location. These are real references and are the principal mechanism by which a text-substitution rename silently fails (§12.4). |
| `PSS2008` | A script-scope variable's usage map: the set of functions that **write** it and the set that **read** it, with per-set counts (§12.3). One record per name in the usage-map population (§12.3). |
| `PSS2009` | A command invocation site whose command name is a literal in command position (§10.6) but does not resolve to any function defined in this file (SPEC 15.4 F2 / P23). Every such name is counted, not filtered — this tool has no structural basis for telling a deleted local function from a cmdlet or an external executable, and guessing from naming convention is exactly the threshold §1.3 forbids. The default record is a **per-name aggregate** (`name`, `sites`, `owners`); one **per-site** record is additionally emitted per invocation under the `command-sites` axis (§5.6): `name`, `owner`, `line`, and — D12 — `span` ([start, end) byte offsets over the whole invocation; a line cannot disambiguate a multi-line or a repeated same-line invocation, a span can) and `arguments` (the argument tokens in order, each `{kind, text}` verbatim; kinds: `parameter`, `variable`, `splat`, `string`, `expandable_string`, `number`, `bareword`, `expression`, `scriptblock`). **Itemisation, not binding**: PowerShell binds positionally and by name against cmdlet metadata this tool does not hold, so which value binds to which parameter — and whether the invocation is risky — is the consumer's judgement (§1.2). Separator and redirection operators are covered by the span and not itemised; variable and bareword items extend over byte-adjacent tails (the §10.6 adjacency discipline), so `$p.FullName` is one item. |

The usage-map population is **not** the same as the `PSS2006` declaration
population. It is the union of:

1. every name referenced with the `script:` qualifier anywhere; and
2. every name declared at script level that is referenced **without** a
   qualifier from a function that does not declare the name locally — that is,
   exactly the `PSS9004` condition.

### 4.3 PSS3xxx — Soft reference

A *soft reference* is a string literal whose value matches a declared symbol
name but which is not a syntactic reference to it. These are invisible to
name-keyed analysis and are a principal mechanism by which a rename silently
breaks a script.

| Code | Fact |
|---|---|
| `PSS3001` | A string literal matches a declared function name and is not in command position. |
| `PSS3002` | A string literal matches a **script-scope** variable name. Scoped deliberately: matching against all variable names produces 8,821 hits on the reference target versus 146 when restricted to script scope (§12.5). |

**String-literal population.** Both codes match against every string constant,
**including barewords**. In PowerShell a bareword argument and a hashtable key
are string constants, and 89 of the reference target's 104 `PSS3002` hits are
barewords — dropping them would hide precisely the output-field-name cases a
rename has to consider.

**Member names are excluded.** The reference parser represents a member access
`$proc.ExitCode` with a string constant for `ExitCode`. That names a .NET
member, not a symbol in this script: renaming `$script:ExitCode` requires no
edit to `$proc.ExitCode`. A literal is in member position when its parent is a
member expression and it is the member being named; the token-level equivalent
is that the preceding significant token is `.` or `::`. On the reference target
9,614 of 27,626 string constants are member names, and excluding them removes
42 of 146 raw `PSS3002` hits — 29 per cent were false positives that demand no
action. `PSS3001` is unaffected, because function names are not used as
property names (measured: 0).

Also excluded, none of which are string constants: the name token of a function
definition, parameter names (`-Path`), keywords, and tokens inside brackets
(type literals and attributes).

Every `PSS3001` / `PSS3002` record carries **`literal_kind`**, valued `quoted`
or `bareword`, so a caller may filter without the tool narrowing the population
on its behalf.

**Command position for `PSS3001`** is determined by the reference parser's own
predicate: a literal is in command position exactly when its parent is a command
and it is that command's first element. Reconstructing this from token adjacency
under-reports (25 against 49 on the reference target).



No surveyed tool in any ecosystem treats soft references as reportable. Visual
Studio and IntelliJ offer to rewrite comments and strings during rename,
implemented as plain global string replacement, opt-in, with a human preview
step. `pss.py` reports; it never rewrites.

### 4.4 PSS4xxx — Impact closure

**`PSS4001` and `PSS4002` are now emitted.** Every `closure` record (§11.1)
carries `"facts": ["PSS4001", "PSS4002"]` alongside its two counts — both
codes together, because one `closure` record states both facts at once and
there is no useful way to split it into two records without duplicating
`id`. This is **not axis-gated**: unlike `closure-sets`, `local-sites` and
`command-sites`, the `facts` tag costs nothing per-record to compute and
adds a small, fixed amount of text to a collection that is already present
in the default model, so it was added unconditionally rather than folded
into an axis. Measured effect on the reference target: the default
(no-axis) model grows from 1,034,458 to 1,048,858 bytes, +1.4%, entirely
from this one field across all 480 `closure` records — small enough that
gating it behind an axis would only have added a second thing for a caller
to remember to ask for, for a fact every record already states via its two
existing count fields.

| Code | Fact |
|---|---|
| `PSS4001` | The transitive caller closure of a function: the set of functions that can reach it through static call edges. |
| `PSS4002` | The transitive callee closure of a function. |
| `PSS4003` | A defined function with no static caller and no top-level invocation. Carries **`named_by_literal`** when a `PSS3001` soft reference elsewhere in the file matches the function's name exactly; the key is **absent** (never `false`) when it does not, following the model's existing size-driven convention of omitting null/false-valued keys rather than emitting them. This is a fact about the string-literal surface only — a comment mentioning the name does not set it, because a comment is not code and is not evidence of a call path (§15.4 F1). The code does **not** mean unreachable either way — a `named_by_literal` record commonly means dispatch through a data table (see `PSS9002`); its absence is the narrower claim the tool can support (§15.5). |
| `PSS4004` | A mutual-recursion group: a strongly-connected component of the call graph with more than one member. Carries every member. The call graph is not acyclic (§11.2). |

### 4.5 PSS6xxx — Presence difference

Emitted for both **functions** and **script-scope variables**. Every record
carries a `symbol_kind` of `function` or `script-variable`.

| Code | Fact |
|---|---|
| `PSS6001` | A name present in model A is absent from model B. |
| `PSS6002` | A name absent from model A is present in model B. |
| `PSS6003` | A name is present in both models. |

`PSS6003` alone carries no information about identity. A name present in both
may denote a different entity; §4.6 supplies the evidence that reveals this.

### 4.6 PSS7xxx — Attribute difference

Several facts may report the same edit from different angles, and that is
normal rather than duplication. A parameter rename is genuinely both a text
change and a signature change, so `PSS7001` and `PSS7002` both fire; a consumer
that enters from either direction must not miss it.

Each is emitted for a name present in both models, and each states equality or
inequality **explicitly** rather than only reporting change. A silent absence
and an observed equality must be distinguishable by the caller.

**That requirement has two axes, and a shape can satisfy one and fail the
other.** The distinction was recovered from consumer review (§3.2) rather than
reasoned out here, and both halves earned their place by a reviewer being
misled without them:

- **Per subject.** For a named symbol, "examined and equal" must be
  distinguishable from "outside the compared population" — a name absent from
  every record is otherwise ambiguous between the two, and a caller querying a
  misspelled name reads silence as "unchanged".
- **Per code.** For a fact code, "ran and found everything equal" must be
  distinguishable from "did not run". A build that has not implemented a code
  emits nothing for it, which is indistinguishable from a clean result unless
  the output says which codes were evaluated.

§6.4 gives the shape that satisfies both. Neither an enumeration of every
subject nor a per-code tally does so alone: the first is silent per code, the
second is silent per subject.

| Code | Fact |
|---|---|
| `PSS7001` | Hash-triple classification, four values: `identical` / `comment-or-whitespace-only` / `string-literal-only` / `code-changed` (§10.5). |
| `PSS7002` | Parameter signature: equal / not equal, with the difference. |
| `PSS7003` | Callee set: equal / not equal, with the symmetric difference. |
| `PSS7004` | Caller set: equal / not equal, with the symmetric difference. |
| `PSS7005` | Dependency classification, four values from direct-callee-set change x transitive-callee-closure change (§11.3). |
| `PSS7006` | Combined classification, four values from `PSS7001` x `PSS7005`: `unchanged` / `local-change` / `dependency-only` / `change-and-propagation` (§11.4). The value names are deliberately neutral; no priority or severity is attached. |
| `PSS7007` | A script-scope variable's usage map differs between the models: writer-set and reader-set equality plus symmetric differences, and both counts in each model. |

**The same-name/different-entity case.** `hash_body` is keyed independently of
name. Where a `hash_body` present on `B` in the before model appears on `D` in
the after model, while `B` in the after model carries a different `hash_body`,
`pss.py` emits both facts adjacently. The reader may conclude a rename plus a
name reuse; `pss.py` does not.

### 4.7 PSS8xxx — Graph, closure and rename-omission

| Code | Fact |
|---|---|
| `PSS8001` | A call edge present in model B and absent from model A. `detail` carries the callee and the edge's call-site `lines`, copied from model B (§5.9, D10 A3). |
| `PSS8002` | A call edge present in model A and absent from model B. `detail` carries the callee and the edge's call-site `lines`, copied from model A (§5.9, D10 A3). |
| `PSS8003` | A function's transitive closure differs between models, with the set difference. |
| `PSS8004` | A soft reference's resolution state differs between the models — most importantly, a string literal that matches a declared name in one and matches none in the other. `detail` carries the first site's `owner` and `line`, copied from the model whose record the resolution was read from (model B where it has one); further sites are derivable from that model's own `soft_references` (D10 A3). `resolves_a`/`resolves_b` are each present **only** where the literal resolved on that side — an absent key means it matched nothing there, following the model's own omit-rather-than-emit convention. Equality is over the resolution only — a moved site is not a resolution difference. |
| `PSS8005` | **Incomplete-rename candidate.** A script-scope name is present in the after model and absent from the before model, while a name present in **both** models lost usage in the same transition. Carries both names, both usage maps, and the count deltas. Derivation and rationale: §12.7 rule (b). |
| `PSS8006` | **Producer/consumer desynchronisation candidate.** For a script-scope variable, at least one **writer** function's `PSS7001` is not `identical` while at least one **reader** function's `PSS7001` is `identical`. Carries the variable, the changed writers, and the unchanged readers. Derivation and rationale: §12.7 rule (a). |
| `PSS8007` | **No write site retained.** A script-scope variable has at least one reader in model B and an empty writer set there. What that means at run time depends on `Set-StrictMode`, which the tool does not observe, and on write forms no static site can carry — §12.2's five declaration sources are all retained, and a non-literal `Set-Variable -Name`, a `[ref]` write or a `-Scope` write (§12.1) still leaves none; the fact is the empty writer set, and the reading of it belongs to the caller (§1.1). `trace` only; the single-state equivalent belongs to `psa.py` (§7). Derivation: §12.7 rule (c). |
| `PSS8008` | **`PSS4003` presence differs.** A function's `PSS4003` presence differs between the models: present in B and not in A, or present in A and not in B. Carries the function identifier, the direction, and both models' `named_by_literal` values (§4.4) for that identifier where the function is present in both. Carries **no commit identity** — `pss.py` is git-agnostic by design (§2.1) and knows only the two models it was given; a caller that wants per-commit resolution runs `trace` over adjacent generations, in which case a sequence of `PSS8008` facts — including a gain followed by a later loss — is the correct and unremarkable representation of a function whose reachability changed more than once (§15.4 F3). |

`PSS8004`, `PSS8005`, `PSS8006`, `PSS8007` and `PSS8008` are the direct detectors for the
failure modes that motivated the tool. None of them is a verdict: each names a
candidate together with the evidence that produced it.

### 4.8 PSS9xxx — Analysis limitations

| Code | Fact |
|---|---|
| `PSS9001` | A region could not be parsed. Carries location and extent. |
| `PSS9002` | A call site could not be statically resolved — invocation through `&` with a non-literal target, or an equivalent dynamic dispatch. Carries `target` (D12): the name expression, **verbatim**, extended over byte-adjacent member/index/call tails only — the §10.6 adjacency discipline applied to the expression side — so a consumer can join it against the variable collections instead of returning to the source. |
| `PSS9003` | A parent-scope write that cannot be tracked: `Set-Variable` / `New-Variable` with `-Scope`, or `[ref]` passing. |
| `PSS9004` | A variable read with no resolvable declaration in the enclosing function and no scope qualifier — a dynamic-scope inheritance candidate. Carries the enclosing function's static callers and, for each, whether it declares that name. Where there are none, "zero static callers" is itself the reported fact. |
| `PSS9005` | The comparison could not be performed for a named unit — for example a model produced under a different `model_version`. |
| `PSS9006` | **Self-diagnostic.** A hash-triple combination outside the four reachable states of §10.5 was observed. This indicates a defect in `pss.py`, not in the surveyed script. |
| `PSS9007` | A symbol identifier required an ordinal disambiguator (§5.2). Ordinals are position-dependent and therefore unstable across edits; a caller must not treat an ordinal-bearing identifier as a durable key. |

**On `PSS9004` as a corpus measure.** In the reference target this fires 11
times across 24,317 variable references, because that codebase qualifies
cross-function state explicitly with `$script:` rather than relying on implicit
inheritance. A codebase without that discipline would produce far more. The
count is therefore a usable indicator of whether a given script is statically
analysable at all — reported as a number, with no threshold and no judgement.

---

### 4.9 Which verb may emit which code (normative)

Two verbs read two models. They share one comparator; they differ in what the
caller is claiming, and therefore in what may be said.

- **`compare A B`** states the differences between two models and **claims no
  relation between them**. It is the honest verb when the inputs are two files
  whose relationship the tool cannot know (§2.6) — a candidate and an original,
  two implementations of one routine, or two files that merely happen to be
  compared.
- **`trace before after`** carries the caller's assertion that `after` is a
  **later state of** `before`. The tool cannot verify that assertion; it can
  only require it to be made, which is why it is a verb and not a defaulted
  flag. Nothing in a model records where it came from.

Fifteen of the eighteen comparison codes hold without any relation between the
inputs and are emitted by **both** verbs. Three require the assertion, and are
emitted by **`trace` only**: `PSS8005`, `PSS8006` and `PSS8007` — precisely the
three rules of §12.7. "An incomplete rename" is not a fact about two unrelated
files; it presupposes that one was derived from the other. Emitting it for an
arbitrary pair would not be a caveated fact but noise.

The neutral fifteen are worded neutrally in §4.5–§4.7: **model A and model B**,
and *differs* rather than *changed*. Under `trace` the same facts may be
presented in before/after terms, because there the ordering is what the caller
asserted. The wording is not cosmetic — a code that says "changed" has already
assumed the relation the verb exists to declare.

---

## 5. Model format

JSON. Top-level shape:

```json
{
  "pss_version": "...",
  "model_version": "1",
  "source": { "path": "...", "sha256": "...", "line_count": 0, "byte_count": 0 },
  "materialization":    { "axes": [] },
  "counters":           { /* whole-file counts, incl. unresolved_named_command_sites */ },
  "symbols":            [ /* PSS1001-PSS1005 */ ],
  "edges":              [ /* PSS2001 */ ],
  "closures":           [ /* PSS4001-PSS4004 */ ],
  "script_variables":   [ /* PSS2004, PSS2006, PSS2008 */ ],
  "string_interpolation_references": [ /* PSS2007 */ ],
  "local_variables":    [ /* per-function aggregates, see 5.3 */ ],
  "soft_references":    [ /* PSS3001-PSS3002 */ ],
  "unresolved_named_commands": [ /* PSS2009 */ ],
  "limitations":        [ /* PSS9xxx */ ]
}
```

### 5.1 Flat records, not trees

All collections are flat record lists. Nested-tree representations are
prohibited for the call graph and the variable usage model, for three reasons:

1. **Duplication.** Shared helpers have wide fan-in; materialising a tree per
   root duplicates the same subtree many times over.
2. **Cycles.** The call graph contains strongly-connected components
   (§11.2), so a tree expansion does not terminate.
3. **Determinism.** A flat list with a defined sort order serialises
   byte-identically; a tree built by traversal does not, without additional
   constraints.

Trees are a *view*. A caller that wants one derives it from the edge list.

### 5.2 Symbol identifiers

Symbol identifiers must be **stable, human-readable, and independently
reconstructible from the source**. Opaque or ordinal identifiers are
prohibited: LSIF's opaque global IDs are the documented reason SCIP replaced
them, and an unreadable identifier also defeats §2.4.

Grammar:

```
function/<Name>                        a top-level function
function/<Outer>/<Inner>               a nested function
variable:script/<name>                 a script-scope variable
variable:local/<Function>#<name>       a function-local variable
variable:env/<name>                    an environment variable
variable:automatic/<name>              an automatic variable
variable:unqualified/<name>            a name whose scope is not determinable
```

Names are emitted in their source casing. Identity comparison is
case-insensitive (§10.7).

The **unqualified** form is emitted where a reference carries no scope
qualifier and the two-pass analysis does not resolve one — inside an expandable
string, most commonly. It was omitted from this grammar until §5.8 forced every
identifier the tool emits to be matched by a declared form, at which point 113
occurrences at the pinned generation had no form to belong to. It is named here
rather than silently admitted: an identifier space a caller cannot enumerate is
one it cannot dispatch on.

Where a function name is defined more than once, the identifier takes the form
`function/<Name>#<ordinal>` where `<ordinal>` is the 1-based definition order.
The tool emits `PSS1005` and `PSS9007` in that case. Ordinals are position
dependent and therefore unstable across edits; this instability is declared
rather than concealed.

### 5.3 Tiering by blast radius (normative)

The model is tiered so that per-site detail is carried exactly where a symbol's
influence crosses a function boundary.

| Class | Reference count (reference target) | Blast radius | Representation |
|---|---:|---|---|
| Function-local variables | 20,353 | The declaring function | **Per-function aggregate** counts by category. Per-site records are added alongside the aggregates under the `local-sites` axis (§5.6). |
| `$script:`-scope variables | 1,381 across 155 names | Crosses function boundaries | **One record per reference site**, plus the `PSS2008` usage map. |
| `$env:` variables | 14 | Process / OS contract | One record per reference site. |
| Automatic variables | 2,014 | Language-defined | Aggregate count only; not renameable. |
| Unresolved reads | 11 | Undeterminable | One record each, with `PSS9004` evidence. |

The rule is: **omit per-site detail only where an omission cannot hide a
defect.** A function-local rename that is incomplete necessarily changes the
declaring function's `hash_body`, so the aggregate loses no detectable
information. A `$script:` rename that is incomplete may leave the declaring
function *unchanged*, so per-site detail is mandatory there.

**Explicit exception: `PSS2007`.** References inside expandable strings are
emitted one record per site **regardless of scope**, in the top-level
`string_interpolation_references` collection.

### 5.4 Determinism

Two runs of the same `pss.py` version over byte-identical input must produce
byte-identical model output. All collections are emitted in a defined sort
order. This is a hard requirement: without it the comparator reports tool noise
as source change.

### 5.5 Version compatibility

`compare` requires both models to carry the same `model_version`. A mismatch is
reported as `PSS9005` and does not produce a partial comparison. Comparing
models produced under different `model_version` values is the most likely way
to manufacture false deltas.

**`compare` excludes the `cost` block from the delta, and says so (normative).**
`cost` describes the model, not the script: its `source_sha256` differs by
construction whenever the two inputs are different files, which in the
originating use of §2.6 is always. Two models can also be **byte-identical in
every record and differ only in `cost`** — measured: slicing a wider model down
to an axis set reproduces a directly surveyed model exactly, while its
`axis_increment` carries `null` for the dropped axes rather than the measured
figures, and both models pass the precondition above. Including `cost` would
therefore report a delta for a pair that says exactly the same thing about the
script. The exclusion is stated in the output rather than applied silently, so a
caller does not read the delta as covering everything the models contain. The
projection-invariance gate (§13.2) already excludes `cost` by name on the same
reasoning.

If the two models' `source.path` values differ, `compare` still runs but emits
that difference as a fact, so that a caller comparing two different scripts
(rather than two states of one script) cannot mistake the result for a
before/after delta.

**When `model_version` advances (normative, ADR 0035).** It advances whenever
the model emitted for a fixed input can differ. Shape and content are both in
scope: adding or removing a key path advances it, and so does a change to which
records, codes, roles or counts the extractor produces for input it already
handled. The test is stated against the emitted artefact rather than the size of
the code change, because the artefact is what a consumer of this section
compares. A change of shape alone is therefore a sufficient but not a necessary
condition — the two extractor fixes of ADR 0034 moved records between fact codes
and moved no key path at all, and two models straddling them would otherwise
have satisfied the equality condition above while differing by 2,302 records.

**`"1"` does not identify a model contract.** Six committed revisions of this
tool emit `model_version = "1"` across four changes of shape and two changes of
extractor behaviour. Versions already emitted are not renumbered; the fact is
recorded instead, and it is normative: **two models both carrying `"1"` are not
evidence that they are comparable**, and a caller holding such a pair should
treat `PSS9005`'s absence as uninformative rather than as a clearance. The first
advance is made by the first change that alters what the model emits.

`model_version` and `pss_version` answer different questions — which model
contract, and which build — and neither substitutes for the other. `pss_version`
advances under SemVer on every landed change, like this repository's other
tools.

### 5.6 Materialisation axes (normative)

Some information is produced by the survey but withheld from the default model
— either because §11.1 holds it to be derivable from a master collection, or
because §5.3 folded it into an aggregate. A **materialisation axis** is the unit
by which a caller asks for one such omission to be restored.

| Axis | Restores | Withheld because |
|---|---|---|
| `closure-sets` | `transitive_callees` and `transitive_callers` on each closure record, alongside the counts | Derivable from the `edges` master (§11.1) |
| `local-sites` | One record per function-local variable reference, alongside the retained per-function aggregates | Folded into an aggregate (§5.3) |
| `command-sites` | One record per unresolved command-invocation site — carrying the argument itemisation and source span — alongside the retained per-name aggregates | Folded into a per-name aggregate (§4.2 PSS2009 / §15.4 F2) |

Neither axis adds or removes a collection: `closures`, `local_variables` and
`unresolved_named_commands` are present in every model, and an axis only
changes what a record in them carries or how many records the collection
holds — never which collections exist.

**`command-sites`, resolved (§15.4 F2 / P23).** The population is not
withheld the way `local-sites` is folded into a per-function aggregate — it
is folded into a per-**name** aggregate, because an unresolved command's
identity is the invoked name, not an enclosing function. The default
`unresolved_named_commands` record carries `name`, `sites` (the count) and
`owners` (the sorted set of enclosing functions or `<script>`) — enough to
answer "is there a call to this name, and from roughly where" without the
per-site cost. `command-sites` restores one additional record per site,
carrying `owner` and `line`. Measured on the reference target: the aggregate
form costs 5.3% of the base model (93 names); the full site form costs 31.5%
(2,796 sites) — the same order of magnitude that motivated `local-sites`
originally, which is why this collection now follows the identical pattern
rather than being emitted unconditionally in full or gated as an
all-or-nothing collection. (Both figures are the compact-JSON byte length of
the collection alone, divided by the compact default-model byte length,
re-measured against this version of the reference target; an earlier draft of
this section carried 22.3% for the site form, which was not reproduced on
re-measurement and is superseded here.)

**Why the axes exist at all.** A caller that can write the model to a file and
query it with code does not need them; it optimises *selectivity*, not total
size, and §5.7 serves it instead. The axes exist for a caller that must receive
the model whole — one without an execution environment, for which total size is
the binding constraint. **No such caller has been observed.** Six external
reviewers, across two model families, all had code execution and all described
the same disk-and-query workflow; the axes are retained on the strength of the
creation rule below rather than on observed demand, and Appendix E records the
question as open.

**The vocabulary is closed.** `--axes` accepts these names and the literal
`all`. An unrecognised name is a usage error: `pss.py` exits `2` and prints the
valid vocabulary. It is not ignored and not treated as a no-op, because a
caller that misspells an axis would otherwise receive a smaller model than it
asked for and no indication that it had.

**Axis-creation rule.** A collection may become an axis only where §5.3's
tiering or §11.1's master/derived rule has already withheld it. **A master
collection never becomes an axis.** `symbols`, `edges`, `closures`,
`script_variables`, `string_interpolation_references`, `local_variables`,
`soft_references`, `unresolved_named_commands`, `counters` and `limitations`
are emitted unconditionally — every top-level collection the model has. An
axis restores *withheld content within* a collection, never the collection
itself. The vocabulary is therefore bounded
by the number of places this document deliberately withholds something — not by
the number of things a caller might wish to filter. Filtering is the caller's
operation on a model it already holds; an axis is a decision about what is
produced.

**An axis changes coverage, never value.** Two models of the same input under
different axis sets must agree exactly on every record they both carry. This
follows from §1.3: were an axis able to alter a derivation, "the same input
yields the same value" would hold only within an axis set, and the fact test
would no longer be a property of the tool.

The distinction between coverage and presentation is load-bearing and was
sharpened by external review. **Presentation does not change modelled values;
materialisation changes coverage and must declare it.** An axis is
materialisation: it adds withheld records and fields, which is why
`materialization.axes` exists and why `compare` refuses an asymmetric pair.
Calling that "presentation" made the invariant read as though an axis were a
formatting choice, which it is not.

It follows that **an analysis parameter is not an axis**. A closure truncated at
depth *n* is a different fact, not a coarser view of the same one. Were such a
thing ever wanted it would be specified as a new `PSS` code, whose presence in
the default model is then an ordinary tiering question under §5.3.

**A model declares its own projection.** Every model carries

```json
"materialization": {"axes": ["closure-sets"]}
```

holding the resolved axis set in sorted order (`all` resolves to the full
vocabulary; no axes resolves to an empty list). `compare` requires the two
models' `materialization.axes` to be **equal** and exits `2` when they are not.
Comparing a model that carries closure sets against one that does not would
otherwise report the absent collection as a change — tool noise of precisely the
kind §5.4 exists to prevent, and undetectable from the delta records alone.

**The same requirement applies to `materialization.scope`, for the same
reason.** A scope-narrowed model (§5.7) carries the same axes as the model it
came from, so an axis-only precondition admits the pair — and every symbol
outside the scope is then reported as removed. The argument that decides the
axis case decides this one identically: a comparison whose coverage varies
silently with its inputs no longer means one fixed thing. `compare` therefore
requires the two models' `materialization.scope` to be equal, where a scope-less
model has no `scope` key at all and is equal only to another scope-less model.

**Refusal on an asymmetric axis set is retained, and it is the narrower of two
defensible readings.** Because an axis never changes a shared record's value,
the comparison restricted to what both models carry is well defined, and two
reviewers argued from that invariant that refusing it is the tool declining an
operation its own specification guarantees. The counter-argument decides it:
a `compare` result whose coverage varies silently with its inputs no longer
means one fixed thing, and a caller is most likely to misread an absent closure
diff as an unchanged one. Uniform meaning is worth more than the saved
re-survey. The refusal message names which axes differed, so the caller knows
which survey to re-run.

**P21, resolved (§5.7).** Axis-set normalisation is not its own top-level
operation and not a flag on `compare` — it is folded into the `slice`
subcommand alongside the §5.7 symbol-scoped projection, because both are the
same kind of thing: a deterministic reduction of an *existing* model, self-
declared in the output's own `materialization` block. `slice --axes` narrows
to a subset of the axes the input model already carries; requesting an axis
the input never materialised is refused (an axis only ever adds material, so
there is nothing to narrow *from*), naming which axis was unavailable and
which the input has. See §5.7.

Named presets (`minimal`, `full`) are deliberately absent. A preset is a remedy
for a caller that cannot tell which axes it needs; `--cost` (§3.1) removes that
difficulty by pricing each axis exactly. No reviewer asked for one.

### 5.7 Symbol-scoped projection

An axis chooses **how much of a collection** is emitted. A projection chooses
**which records across all collections** concern one symbol. They are different
operations and the second is not expressible as an axis, because it cuts across
collections rather than selecting whole ones.

**The projection contract is declared, not inferred** (D11, round-3 B2). A
`--scope` slice keeps or drops **whole records** by one membership rule — the
scope identifier appearing in any of `id`, `from`, `to`, `owner`, `matches`,
`members`, `owners` — and **never rewrites a kept record**, so counts and
lists inside a kept record remain facts about the whole source: an
unresolved-command aggregate kept because its `owners` include the scope
still states source-wide `sites` and `owners`. Eight collections are
membership-filtered; `limitations`, `counters` and `source` are kept in full
(filtering `limitations` would misrepresent the projection's own coverage);
`cost` and `materialization` are recomputed to describe the slice itself.
`pss.SLICE_PROJECTION` states all of this, `--capabilities` serialises it
(`slice_projection`), and the gate holds the declaration against what
`slice_model` actually does — a round-3 reviewer had to reverse-engineer
these rules from slice/parent pairs, and a rule recoverable only by
comparing two outputs is stated by neither.

**Boundary stubs (D12) — the one stated exception to whole-records-only.**
Round 3 measured the cost of a pure filter: a function slice kept 33 edge
endpoints that resolved to nothing inside the slice, and re-measured at the
current build the same scope references **172** symbol identifiers with no
symbols record — 47 from `edges` and `closures` alone. After scoping,
every symbol identifier the kept records reference and the slice does not
contain is re-introduced as a **stub**: `record: "stub"` plus the four
common keys (`id`, `kind`, `start_line`, `end_line`), copied verbatim from
the input model — including from an input's own stubs, so slicing a slice
cannot dangle what the first slice resolved. Additive only: no kept record
is rewritten, a stub carries no analysis payload, and an identifier with no
symbols record in the input (`<script>`; every `variable:` form) is not
stubbed. The reference set is **declaration-driven**: the same
`COLLECTION_KEYS[...].symbol_refs` fields §5.8 declares as the joins into
`symbols[].id` — a hand-rolled field list here collected variable-record
`id`s on its first measurement, identifiers of a different form (§5.2) that
never resolve into `symbols`, and the declaration already separates the
two. `limitations` stays outside the rule for the same reason it is kept in
full: it is whole-file context, not the slice's references.
`slice` refuses a model carrying another `model_version` (`PSS9005`, §5.5):
the stubs are a version-4 shape, and a document whose stated version and
actual shape disagree is the false-delta problem in one file.

The distinction is not theoretical. On the reference target the axes control
0.40 MB and 3.86 MB of material that is **already absent by default**, while
`script_variables` — 42 per cent of the default model — is a master collection
and cannot be reduced at all. A caller asking *what does renaming this function
touch* therefore has no lever: the only reduction large enough to matter is the
one that removes the `$script:` evidence the question depends on.

A projection supplies that lever. Measured against a 552,948-byte all-axis
model, the records concerning one mid-sized function total 23,729 bytes — **4.3
per cent**.

The selection rule must be a fact under §1.3: no threshold, no score, no
similarity. Every record whose identifying field equals the given symbol
identifier, plus the edges incident to it on either side, plus `limitations` in
its entirety — unconditionally, because limitations describe what is *not*
known and filtering them would misrepresent the projection's own coverage.

**P20, resolved.** Shape: `slice <model.json>` — a subcommand over an
*existing* model, not a `survey --scope` flag. The projection is required to
work when the earlier source no longer exists and the model cannot be
regenerated (§5.6's P21 motivation is the same fact applied to axes), which
only a stored-artefact operation can guarantee; and P21 resolved axis-set
normalisation into the same subcommand, so a single mechanism serves both
narrowings of an existing model rather than two independent ones.

`slice` takes `--scope <id>` (this projection), `--axes <subset>` (§5.6's
normalisation), or both together — "this symbol, and only these axes" is one
call, not two.

**Identifying fields (settled).** A record participates when it carries the
scope identifier as `id`, `from`, `to`, `owner`, or `matches`, or the
identifier appears in its `members` or `owners` list. This is one mechanical
rule applied uniformly across every collection, not a per-collection special
case: `id` matches a symbol's own record and a `PSS4003` orphan record;
`from`/`to` match an edge on either side; `owner` matches every reference or
aggregate recorded against the enclosing function; `matches` matches a soft
reference (`PSS3001`/`PSS3002`) that names the symbol; `members` matches a
`PSS4004` mutual-recursion group; `owners` matches a `PSS2009` per-name
aggregate (§5.6) against every function it was invoked from, without needing
the `command-sites` axis to know that much. `counters` and `source` are
whole-survey metadata, not per-symbol, and pass through unchanged. A scoped
`script_variables` usage-map record (`PSS2008`) is a name-level summary of
writers and readers, not itself attributable to one function via any of these
fields, so it is not pulled into a *function*-scoped projection; a
variable-scoped projection (`--scope variable:script/<n>`) reaches it directly
through `id`.

**Incidence boundary (settled).** One hop only, matching §4.4's edge-level
facts (`PSS2001`/`PSS4003`/`PSS4004`): an edge is included when the scope is
either endpoint, not when the scope is reachable through it. A caller wanting
the transitive closure has `closures` (`PSS4001`-`PSS4002`, or the counts
already unconditional in every model, §4.4) and can slice by each member of it
in turn.

**A projected model declares its own coverage.** `slice --scope <id>` sets
`materialization.scope` to the identifier used, alongside the usual
`materialization.axes`. A scope-less model has no `scope` key at all — absence
means "whole model", not "matched everything" — so a consumer can tell a
projection from a full survey without inspecting record counts. An unmatched
scope is refused (exit `2`) rather than silently returning an all-empty model,
for the same reason an unrecognised axis name is refused: a typo would
otherwise read as "this symbol has no facts" (§1.3) instead of as the usage
error it is.

### 5.8 Identifier forms and collection join keys (normative)

§13.3 declares which key paths a model carries. It does not say which of those
paths carry an **identifier**, which identifier space that identifier belongs
to, or which of them a caller may **join** against another collection. A
consumer holding the schema and not these three facts can read every record and
cannot relate one collection to another — which is the gap §3.1 names as "the
join key for each collection", and which six external reviewers recovered by
reading sample output.

The declaration lives here and in `pss.py` (`IDENTIFIER_FORMS`,
`COLLECTION_KEYS`), held together by `--self-check` on name **and** value, for
the reason §13.3 gives: `--capabilities` serialises it rather than restating
it, so there is one copy of the fact (ADR 0036).

#### Identifier forms

Every identifier the model emits matches **exactly one** row. The patterns are
disjoint, so a caller dispatches on form without needing an ordering rule, and
they are applied as full matches — a form is the whole identifier or it is not
that form. `<script>` (§10.6) is the one reserved value that is not an
identifier: it names a source position, not a definition, and is legal wherever
a symbol identifier is expected.

| Form | Pattern |
|---|---|
| `function` | `function/[^/#]+(?:/[^/#]+)*(?:#[0-9]+)?` |
| `variable:automatic` | `variable:automatic/[^/]+` |
| `variable:env` | `variable:env/[^/]+` |
| `variable:local` | `variable:local/[^/#]+(?:/[^/#]+)*#[^/#]+` |
| `variable:script` | `variable:script/[^/]+` |
| `variable:unqualified` | `variable:unqualified/[^/]+` |

#### Collection join keys

`symbols[].id` is the join target, and `symbols` carries **function
definitions only** — there is no row for a variable. A field is therefore
listed under *joins* only where every one of its values is a member of
`symbols[].id` or is `<script>`; a field carrying an identifier that does not
resolve there is listed separately, because joining on it against `symbols`
returns an empty result and raises no error. `soft_references.matches` is the
case that makes the distinction load-bearing: it resolves to a function **or**
to a script variable (§4.3), and most of its values are the former.

A **unique key** of `—` is a statement, not an omission. A collection carrying
several record shapes (§11.1) has no single identifying key, and a caller must
not invent one from the fields that happen to be present.

| Collection | Unique key | Joins to `symbols[].id` | Other identifier fields |
|---|---|---|---|
| `closures` | — | `id`, `members`, `transitive_callees`, `transitive_callers` | — |
| `edges` | `from`, `to` | `from`, `to` | — |
| `limitations` | — | `owner` | — |
| `local_variables` | — | `owner` | `id` |
| `script_variables` | — | `owner`, `readers`, `writers` | `id` |
| `soft_references` | — | `owner` | `matches` |
| `string_interpolation_references` | — | `owner` | `id` |
| `symbols` | `id` | `parent` | — |
| `unresolved_named_commands` | — | `owner`, `owners` | — |

`edges` is unique on `(from, to)` **structurally**, not by observation: the
edge store is keyed by that pair and `sites` counts the occurrences folded into
one record (§11.1).

`test_pss.py` holds this table against the pinned blob: every listed field must
appear on at least one record, every value under *joins* must resolve into
`symbols` or be `<script>`, every value under *other identifier fields* must
match a declared form, and every declared unique key must actually be unique.
A field listed and never populated is an enumerated capability nothing
exercises — the failure mode §13.2 records twice.

### 5.9 Call-site locations on the edge record (normative)

A `PSS2001` edge carries **every** call site:

- `lines` — the line of each site, **ascending**, one entry per site, so
  `len(lines) == sites` always. Two sites on one line are two entries: the
  array counts sites, not distinct lines.

**`line` is retired (D12 arc, `model_version` 4).** It was normatively
`lines[0]` — a duplicate by construction, kept one version for the `"2"`
consumers that read it, with the retirement question recorded here rather
than decided. Decided now, in the arc that advances the version anyway: a
consumer reading `line` was reading a copy of `lines[0]`, and a copy of a
fact is the shape §13.2 spends its rows fighting. The `"3"` models carry
both fields; a `"4"` model carries `lines` only, and the version gate on
`compare`/`trace` (§5.5) is what keeps the two shapes from being read as
one.

This is the [F2] resolution (§13.2 `Call-site locations`, closed at the D10
arc). The shape was **consumer-adjudicated before it was built**: both round-2
reviews, given a live candidate pair, chose the array over per-site records —
the per-site shape forces a join to answer the plainest question ("list every
place that breaks if this function is deleted") and represents the same fact
twice. The array is carried on the **default** model rather than behind an
axis because the models this project archives are the blob-derived caches
(§14.4), and a location a cache did not materialise is a location the archive
does not have; measured at the pinned blob, the array adds 29,347 bytes —
**+2.6%** of the default model and **+0.4%** of the all-axes one (the arc
plan's ~1.4% was taken on a different base and is superseded by these two
basis-stated figures). An
opt-in axis carrying the same field remains possible without a version
advance if a narrow-model demand appears (the `closure-sets` precedent);
recorded, not built.

Sites inside a `$( ... )` subexpression are collected after the top-level
scan, so the ascending order is **established at emission, not assumed from
scan order** — an edge whose only early site is inside an expandable string
would otherwise carry a misordered array.

---

## 6. Output formats and consumer layers

### 6.1 The three layers (normative)

The tool serves consumers with incompatible requirements, and a single output
shape cannot serve them all. Three layers are recognised, each optimising a
different variable.

| Layer | Consumer | Surface | Optimises |
|---|---|---|---|
| **Human** | a person reading a result | `--format text` | legibility |
| **Machine** | the process consuming the model | the JSON model, `--pretty`, §5.7 projection, `--cost`, `--capabilities` | selectivity |
| **Completeness** | storage, and a consumer whose needs are unknown | the axes of §5.6 | total coverage |

The human layer is **not** the axes. An axis emits a larger machine artefact —
on the reference target `local-sites` adds 20,352 records — and nobody reads
that. `--format text` is the human surface, and it is a summary report rather
than a serialisation of the model.

**`--pretty` is machine-layer, not human-layer.** Three external reviewers, in
both model families, named the same misassignment. Indentation looks like a
human concern, but `--pretty` is the one option that changes the **bytes of the
model file**, and the model file is the machine artefact: a pretty model and a
compact one parse to the same object and are different files, with different
sizes, different hashes and different textual diffs. Every size figure a model
states about itself, and every hash this tool computes over a model, refers to
the **compact** serialisation regardless of how the file was written; each model
carries a top-level `serialisation` field with value `compact` or `pretty` so
that a consumer can tell which it holds.

The human layer is retained deliberately and against the only evidence
available: every external reviewer proposed dropping `--format text` from
`survey`. All of them were language models. A population of machine consumers
is not evidence about whether a human surface earns its place, and their
agreement is not read as such.

### 6.2 Channels must not disagree (normative)

Two output channels are a projection, not a double standard — **provided they
cannot diverge**. Three rules make that hold.

**The text channel is generated from the model, not computed alongside it.** A
second derivation path is a second opportunity to be wrong, and the divergence
surfaces as a confident inconsistency rather than as an error.

**Every value the text channel prints must be reproducible from the JSON model
by a rule stated in this document.** A summary figure whose derivation is not
written down is not a fact under §1.3, however correct its arithmetic. The
closure summary is the worked example: it reports the **closure membership
total**, the sum of `transitive_callee_count` over the closure records, which is
5,071 on the reference target. It is not the number of closure records (480),
and it is not the edge count (1,281). On a small corpus the membership total and
the edge count may coincide — they do at 65 on the secondary corpus — so a label
that does not name its derivation is not merely unclear but actively
misleading. The label states the quantity; §13 gates the derivation.

**A layer changes presentation, never a value.** This is §5.6's projection rule
raised from the axes to the layers, and it has the same basis in §1.3: were a
layer able to alter a derivation, "the same input yields the same value" would
hold only within a layer.

**Stubbed slices (D12).** A §5.7 boundary stub is a reference marker, not a
function definition, so on the text channel the `functions` row counts
**full records only**, the fact-derived rows (`nested definitions`,
`duplicate names`) read full records only (a stub carries no `facts`), and a
`boundary stubs` row states the stub count — printed only on a model that
carries stubs, so an unsliced model's text output is byte-unchanged. This
rule exists because its absence was measured: the renderer crashed on the
first stubbed slice, and the `functions` row counted stubs as functions —
the rule the paragraph above demands had simply never been stated for the
shape §5.7 introduced.

### 6.3 Formats

**`text`** — human-oriented, one fact per line, grouped by block. A summary,
not a serialisation.

**`json`** — machine-oriented. For `survey`, this is the model itself (§5). For
`compare` and `trace`, the delta document of §6.4.

There is no SARIF output. SARIF encodes findings with severities and is a poor
fit for a tool that issues neither.

The set of machine formats is **`json` only**, and the capability descriptor
(§3.1) carries it as a list so that an addition is an extension rather than a
schema change. Adding YAML is not a small change and is not deferred silently:
the Python standard library has no YAML emitter, so it would mean either
hand-writing one — quoting, folding and escaping are where such emitters fail —
or taking a package dependency that §8 forbids. Any future request for YAML is
adjudicated against that cost, not against convenience.

### 6.4 The delta document (normative)

`compare` and `trace` emit one JSON object with three top-level keys. The shape
was chosen from consumer review of two competing candidates (§3.2); what
follows records the decision and the reason, because the reason is what a later
change has to argue against.

```json
{
  "delta_records":     [ ... ],
  "surveyed":          { "PSS7001": {"examined": 365, "equal": 359, "emitted": 6}, ... },
  "examined_subjects": { "function": 365, "script-variable": 141 },
  "not_evaluated":     { "PSS8005": "succession-only: ...", ... }
}
```

(`compare` shown; under `--all` the third key carries the full identifier
enumeration instead of the counts, and under `trace` the fourth is `{}`.)

**`delta_records` carries differences only, as a flat list.** Not one array per
kind of change: a collection per code would add eighteen keys to the public
contract, force a choice between emitting empty arrays and omitting keys — and
an omitted key is exactly the silence §4.6 forbids — and oblige a consumer to
learn a second vocabulary alongside the fact codes it already knows. Flat also
keeps the eighteen codes level with one another; grouping them would put a
claim about which distinction matters into the structure, which §1.2 reserves
for the caller.

Every record carries `code` and `subject`; `subject` is an identifier in one of
the §5.8 forms, or the reserved `<script>`, and the delta introduces no
identifier space of its own. Records for codes that state equality carry
`equality`, whose values are `equal` and `differs`. Code-specific evidence
lives under `detail`. Where a fact concerns a pair — a call edge, or the two
names of a rename candidate — `subject` names the side the fact is about and
`detail` names the other; a delta record has one subject.

**`surveyed` is mandatory, in every shape and every build.** It is the per-code
axis of §4.6: for each code the comparator evaluated, how many subjects were
examined, how many were equal, how many produced a record. A code this build
does not implement is **absent from `surveyed`**, and that absence is the
signal — it is how a consumer distinguishes "did not run" from "ran clean",
which is the distinction a reviewer got wrong when reading a specimen that
omitted the tally. `--capabilities` (§3.1) states the same fact statically;
`surveyed` states it for the run in hand, and the two must agree.

**`not_evaluated` makes the absence self-describing** (D10, A3; both round-2
reviewers proposed it independently). It maps every catalogued comparison code
absent from `surveyed` to the reason: under `compare` that is exactly the
three succession-only codes with the §4.9 reason, and under `trace` — which
evaluates all eighteen — it is `{}`, emitted rather than omitted, because an
omitted key is the silence §4.6 forbids. The map costs tens of bytes and
closes the one question the tally's absence-signal left the reader to infer.

**`examined_subjects` states the compared population — per-kind counts by
default, the full identifier enumeration under `--all`** (D10, A3). The
enumeration was the default until this arc, on the argument that a tally
cannot answer "was `function/X` examined?"; measured against practice, both
round-2 reviewers completed every task without reading it while it dominated
the document's bytes. The per-subject question keeps its answer — `--all`
restores the enumeration, identifiers only, once each — and the default
counts cross-check against the presence tally (`PSS6001` + `PSS6002` +
`PSS6003` examined sum to them) and, by kind, against the `--all` enumeration
(a subject's kind is decidable from its §5.8 form alone). **That relationship
is normative, not incidental**: the default counts are the per-kind
compression of exactly the `--all` enumeration, and the enumeration is the
union of both models' symbol identifiers plus both models' script-variable
identifiers, once each. The pseudo-subject **`<script>` can appear as a
delta-record subject and is never an examined subject** — it names the top
level, which is not a symbol either model declares (a round-3 reviewer
confirmed both rules empirically; a rule recoverable only by counting is
stated by neither document).

**`source_path_differs` is the one conditional top-level key.** It appears —
`true` — exactly when the two models' `source.path` values differ, because a
path difference is a fact about the comparison's inputs a caller may need
(§5.5), and it is absent otherwise rather than `false`, following the
model's own omit-rather-than-emit convention. The shape declaration carries
it under `top_level_conditional` (D11; a round-3 reviewer found it in a real
document and absent from the declared shape — an undeclared top-level key is
exactly the class of gap the declaration exists to close, and the gate now
holds both directions: a same-path pair must not carry it, an unequal-path
pair must).

**The delta document is a reader of models, not a model** (D11, round-3 B3,
normatively stating what the D10 arc practised). It is **not** covered by
the §14.4 cache — the cache stores survey models, and a delta is recomputed
from them on demand — so a change to the delta document's **shape** expires
no cache and does not advance `model_version`: it re-derives Appendix B.7
(whose pins are counts, tallies and named subjects) and restamps it, exactly
as B.7's separation from B.8 was built to allow. `model_version` gates the
**inputs** — a version mismatch between the two models refuses (§4.6) — and
advances only when the emitted **survey model** can differ for a fixed
input (§13.1). A consumer that needs to know which delta shape it holds
reads the shape declaration in `--capabilities`, which travels with the
build that emitted the document.

**Why not simply emit every record.** The alternative — one record per code per
subject, equality included — satisfies §4.6 per subject and fails it per code,
because with no tally an unimplemented code is silent. It is also, measured on
two adjacent generations of the reference target, 2,211 records against 144.
The intended caller is a language model holding two files (§2.6), so the
difference decides whether the delta fits beside the models it describes or
displaces them. `--all` restores the full enumeration for callers that need the
delta to stand alone as a durable record with the models discarded.

**The delta states its own provenance.** `source_a` and `source_b` carry each
model's `source` block and `model_version`, and `direction` states whether the
caller asserted succession (`trace`) or not (`compare`). A delta that cannot
say which two models produced it is not a fact about anything, and both
reviewers of the pre-implementation specimens raised its absence
independently (§3.2).

---

## 7. Jurisdiction boundary with psa.py

`psa.py` and `pss.py` both read PowerShell, and must not both judge the same
thing.

> **`psa.py` judges the quality of a single state. `pss.py` describes structure
> and change.**

The following are carried in the PSS model as facts but **must never be emitted
by `pss.py` as single-state findings**, because each is already a `psa.py` rule:

| Concern | psa.py rule |
|---|---|
| `$Script:Foo` read but never assigned | `PSA2013` |
| Undefined variable reference | `PSA2001` |
| Automatic-variable shadowing | `PSA2002` |
| Parameter shadows an automatic variable | `PSA2007` |
| Call to an undefined function | `PSA2010` |

This table is normative and must be kept in step with `psa.py`'s catalogue.

**The transition carve-out.** `PSS8007` (write-site loss) overlaps the concern
of `PSA2013` but does not collide with it, because `pss.py` emits it **only as
a before/after transition** — "this variable had two writers and now has none".
The single-state judgement "this variable is read but never assigned" remains
`psa.py`'s exclusively. A conforming implementation must not emit `PSS8007`
from `survey`.

---

## 8. Environment requirements

| Requirement | Value |
|---|---|
| Python | **3.12 or later**, verified at startup; exit per §9 if unmet |
| Python packages | **standard library only** — no `pip` dependency, at run time or test time |
| PowerShell | not required at run time. Required at test time for differential testing; absent, the suite degrades per §14.3 |
| PowerShell modules | **none.** The oracle uses only in-box `System.Management.Automation.Language`. PSGallery access is not required and must not be introduced |
| Network | not required for any operation |

The 3.12 floor is fixed from the measured execution environment (CPython
3.12.3). It is a higher floor than `psa.py`, which declares none. The
divergence is deliberate: `pss.py` states and enforces its floor so that a
version mismatch fails loudly rather than subtly.

---

## 9. Exit codes

| Code | Meaning |
|---|---|
| `0` | The requested operation completed. |
| `2` | Usage error, unreadable input, unmet environment requirement, or internal error. |

**The exit code never encodes a verdict.** A survey emitting one thousand facts
and a survey emitting none both exit `0`. This is a deliberate divergence from
`psa.py`, whose exit code carries a pass/fail meaning and which the project
gates on at PSA 0/0/0. Overloading the PSS exit code would make that bar
unsatisfiable or would quietly weaken it.

---

## 10. Hashing and normalisation

### 10.1 Recognised definition forms

Both `function f { param(...) }` and `function f(...) { }` declare parameters.
Nested function definitions are recognised and reported (`PSS1004`).

### 10.2 `hash_full` — the state hash

**Text hashed**: the function's full extent, `function <Name> { ... }`
inclusive.

**Normalisation**: strip comments and string literals to whitespace, collapse
whitespace runs to a single space, strip ends. `sha256`, truncated to 16 hex
characters.

This is the repository's canonical normalized-hash contract, **copied
verbatim** and used unchanged. Encoding-neutral: BOM and CRLF differences
cancel.

`hash_full` answers: *is this function in the same state as some reference
copy?* It is name-sensitive by construction, so it changes on rename.

### 10.3 `hash_body` — the identity hash

**Text hashed**: the function's extent **minus the `function` keyword and the
name** — from the first character after the name to the end of the extent.
Parameter names are retained in both definition forms, because a parameter
rename is a signature change and must remain visible via `PSS7002`.

**Normalisation**: strip comments to whitespace, **retain string literal
contents**, collapse whitespace runs to a single space, strip ends. `sha256`,
truncated to 16 hex characters.

`hash_body` answers: *is this the same function under a different name?*

**Why string contents are retained (normative rationale).** The shared contract
strips string literals, which is correct for its own purpose — detecting drift
between a canonical body and a vendored copy, where wording differences must
not raise false positives. Applied here it is catastrophic. Measured over the
reference target's 480 functions:

| Variant | Distinct hashes | Colliding groups | Functions involved |
|---|---:|---:|---:|
| Name included, strings stripped | 480 / 480 | 0 | 0 |
| Name excluded, strings stripped | **471 / 480** | **3** | **12** |
| Name excluded, strings retained | 480 / 480 | 0 | 0 |

The three collision groups are families of near-identical functions
distinguished *only* by a string constant — five logging wrappers differing by
marker glyph and colour, five path getters differing by filename, two evidence
resolvers differing by OS generation. These are precisely the constructs a
consolidation refactoring targets, so the collisions concentrate exactly where
the tool is needed. A collision produces the false evidence "these five
functions are the same", which is the conclusion `pss.py` exists to prevent.

`hash_body` is therefore **deliberately not** the shared contract's value, and
a conforming implementation must not claim conformance to the shared golden
vectors for it. It carries its own vectors (§13).

### 10.4 `hash_raw` — the forensic hash

**Text hashed**: the function's full extent, verbatim bytes, no normalisation.
`sha256`, truncated to 16 hex characters.

`hash_raw` answers: *did anything at all change?* It is the only value that
detects a comment-only or whitespace-only edit.

### 10.5 The hash-triple classification (normative)

The three values are not independent. `hash_raw` equality implies equality of
the other two. For a symbol compared under the same name, `hash_full` differs
only when non-string code differs, and `hash_body` differs when non-string code
or string contents differ; therefore `hash_full` changed with `hash_body`
unchanged cannot occur.

Exactly **four** combinations are reachable. `PSS7001` emits one of:

| `hash_full` | `hash_body` | `hash_raw` | `PSS7001` value |
|---|---|---|---|
| same | same | same | `identical` |
| same | same | differs | `comment-or-whitespace-only` |
| same | differs | differs | `string-literal-only` |
| differs | differs | differs | `code-changed` |

The remaining four combinations are unreachable. Observing one is a defect in
`pss.py`; the tool emits `PSS9006` rather than an out-of-enum value.

This was verified over 2,607 same-name function comparisons across 12
consecutive historical states of the reference target: all four reachable
states occurred (2,395 / 13 / 9 / 190) and no unreachable state occurred.

Note that `string-literal-only` is invisible to the shared drift contract by
design, and is invisible to `hash_full` alone. It is reportable only because
`hash_body` retains string contents.

### 10.6 Command position

A call edge (`PSS2001`) is emitted only where a literal command name appears in
command position.

**Inclusion.** Command position is: statement start; after `|`, `;`, `&`, `&&`,
`||`, an opening `(` or `{`, or an assignment operator; after one of the
statement keywords `begin default do else end exit finally process return throw
try`; after the closing `)` of a keyword-introduced parenthesis group; and
after the keyword `in` inside a `foreach` condition group.

`&&` and `||` are the PowerShell 7 pipeline chain operators. They do not occur
in the reference target, so no Appendix B value depends on them; they are
stated because a codebase that uses them would otherwise lose edges silently,
and §1.4 requires this tool to work on any single `.ps1`.

`catch` and `elseif` are deliberately absent from the statement-keyword list:
each takes a parenthesis or a block rather than a command.

The `in` rule is scoped to the **innermost** parenthesis group having been
opened after `foreach`, so a bareword `in` used as an ordinary argument opens
nothing. It is the only statement-condition rule needed: a command at the head
of an `if`/`while`/`until`/`switch` condition, or anywhere after `|` or inside
a nested `(`, was already covered by the list above — measured against the
reference parser at the pinned blob, the token scan's only misses were the two
`foreach`-condition calls, and with the rule the populations are equal
(5,048 = 5,048), held by the Appendix B differential from here on.

**Exclusion.** A word in an otherwise-command position is *not* a command name
when it is a PowerShell keyword; when an assignment operator follows it (a
hashtable key or assignment target); when it starts with `-` (an operator or a
parameter name); or when it is inside brackets (an attribute or type-literal
context).

**Dotted command names (closed at the D12 arc, `model_version` 4).** A name
like `dism.exe` lexes as word `.` word, and the pre-D12 command-word iterator
yielded the first word alone — the `PSS2009` record named `dism`, a name that
exists in no source line, so a consumer joining the record back to the source
(or pre-flighting a rename against it) matched nothing. In command position an
**adjacent** run of word (`.` word-or-number)\* is one command name. Adjacency
is decided on byte offsets, never on significant-token order: `dism . exe` —
the command `dism` with two arguments — does not join, and the exclusion rules
above apply to the token after the joined run (the assignment look-ahead sees
past the tail). The join repeats over every tail (`robocopy.exe.bak`) and a
numeric tail joins (`python3.12`). **Stated limit:** a name whose *first*
segment leads with a digit (`7z.exe`) lexes as a number token and is not a
command word at all; that is a limit of the lexer's word rule, is unchanged by
this join, and a codebase invoking such names loses those `PSS2009` records —
recorded here so the absence reads as a stated limit rather than an unstated
one.

**Closed gap: `foreach ($x in <command>)` (recorded §3.2 2026-08; closed at
the D10 arc, `model_version` 3).** The inclusion list used to cover the
position after the opening `(` — which is `$x` — and nothing after `in`, so a
command in a `foreach` condition — a genuine pipeline at run time — yielded
**no edge**, and a function invoked only that way was reported `PSS4003` with
`transitive_callee_count` understated for its caller. It was recorded rather
than fixed on discovery because closing it changes the emitted model for a
fixed input (§5.5, ADR 0035), and it waited for the version arc so cache
expiry happened once. Both round-2 consumer reviews independently ranked
"emit the edge" first among the remedies — one demonstrated the alternative's
cost by showing `PSS3001`'s classification claim ("not in command position")
had become **false** for the token in question — and the implementability
probe against the reference parser confirmed the token scan could carry the
rule before it was adjudicated in.

The degradation was honest while it lasted, and that is what made the gap
findable: the target still carried `PSS3001` with `matches` resolving to the
callee, and its `PSS4003` carried `named_by_literal: true` (§4.4). A consumer
reading those two reached the truth; a consumer reading only the edges did
not, which is why this paragraph exists rather than only a changelog entry.



### 10.7 Case sensitivity

PowerShell function and variable names are **case-insensitive**. Identity
comparison — presence transition, rename matching, usage-map keying — is
performed on the lower-cased name.

A change that alters only the casing of a name is therefore **not** a rename.
It does change `hash_body` and `hash_raw`, so `PSS7001` will report
`code-changed`; the accompanying `PSS6003` shows the symbol present in both
models under the same identity. A conforming implementation must emit both,
and must not report a `PSS6001`/`PSS6002` pair for a casing-only change.

The reference target contains 2,635 distinct variable names with **zero**
mixed-casing occurrences. The rule is stated because the property is a
codebase's discipline, not the language's guarantee.

### 10.8 Nested-scope conventions (normative, and deliberately asymmetric)

Two different conventions apply, because the two questions differ:

- **Hashing.** A nested function's text **is included** in the enclosing
  function's `hash_full`, `hash_body` and `hash_raw`. Excluding it would make a
  change confined to the nested function invisible in the enclosing function,
  which is false.
- **Reference attribution.** A nested function's variable references belong to
  the **nested function only**. They are not additionally attributed to the
  enclosing function.

The asymmetry is intentional and must be stated in any conforming
implementation's documentation. Under the second convention the reference
population sums to the count of unique variable-expression nodes. Attributing
nested references to both functions inflates the total by exactly the nested
bodies' reference count — 11 in the reference target, whose single nested
function is `Add-VRow`.

---

## 11. The dependency graph model

### 11.1 Representation

**No data in the model may be derivable from another part of the model.** The
sole exception is a human-readable identifier carried for legibility. An
earlier build materialised each function's direct callee and caller sets inside
the closure records, republishing all 1,281 edges a second time, and
materialised both transitive sets for all 480 functions — 601 KB, the largest
collection in the model, to answer a question a consumer asks about a handful
of functions at a time. Closure records therefore carry **counts**, which are
actionable on their own; the sets themselves are available under the
`closure-sets` axis (§5.6). The two withholdings are separately addressable:
the closure sets cost 0.40 MB on the reference target, against 3.86 MB for the
per-site local-variable records, and a caller reasoning about call structure has
no use for the latter.

The call graph is stored as a flat edge list (`PSS2001`). Closures — the
counts this section discusses — are **derived** from it and emitted in the
default survey, because the model's consumer should not have to compute
transitive reachability itself (§2.4). Every `closure` record carries
`"facts": ["PSS4001", "PSS4002"]` (§4.4).

The edge list is the master; the closures are a derived view. Measured on the
reference target: 1,247 edges expand to 5,071 closure membership entries, a
factor of 4.1. That total — the sum of `transitive_callee_count` over the
closure records — is the quantity the human layer reports as closure membership
(§6.2).

**The callee-side and caller-side totals are not the same number, and this is
not a defect.** The sum of `transitive_caller_count` over the same closure
records is 5,252, not 5,071. The reserved owner `<script>` (§10.6) is a
source-only pseudo-node in this graph: it can appear as an entry in a
function's `transitive_callers` set, but it can never appear in anyone's
`transitive_callees` set, because `<script>` is never itself a call target and
is never itself the subject of a closure computation (it is not one of the
480 functions `self.funcs` iterates). Every function transitively reachable
from `<script>` therefore carries one extra caller-side membership entry with
no callee-side counterpart. Measured on the reference target: 181 functions
are transitively reachable from `<script>`, and 5,252 − 5,071 = 181 exactly.
A caller comparing the two totals, or the two widest-closure figures in
Appendix B.2, should expect this gap and should not read it as a symmetry
violation in the traversal.

**The `closures` collection is not homogeneous, and a caller must not size it
from the function count.** It carries three record shapes, distinguished by
their keys:

| Shape | Discriminator | Meaning | Reference target |
|---|---|---|---:|
| closure | `record: "closure"`, keyed by `id` | one per function: the two transitive counts, and the sets under the `closure-sets` axis | 480 |
| orphan | `code: "PSS4003"`, keyed by `id` | a function with no static caller, plus `named_by_literal` (§4.4) | 26 |
| recursion group | `code: "PSS4004"`, keyed by `members` | a strongly connected component of two or more functions | 3 |

509 records against 480 functions on the reference target; 46 against 46 on the
secondary corpus, which has neither an orphan nor a recursion group and so does
not reveal the heterogeneity at all. A consumer filtering the collection must
discriminate on the keys above rather than assume a uniform shape.

### 11.2 The graph is not acyclic

Measured on the reference target: zero self-recursive functions, and **three
strongly-connected components** with more than one member — two recursive
descent parser/writer families and one diagnostic pair. Closure computation
must therefore carry a visited set and terminate on revisit; a naive tree
expansion does not terminate.

Each such component is emitted as `PSS4004`, because a caller planning a
refactoring needs to know which functions cannot be separated.

### 11.3 The dependency classification

`PSS7005` crosses the direct callee set with the transitive callee closure:

| direct callee set | transitive closure | `PSS7005` value |
|---|---|---|
| same | same | `dependencies-unchanged` |
| same | differs | `downstream-changed` |
| differs | same | `direct-only-change` |
| differs | differs | `dependencies-changed` |

`downstream-changed` is the load-bearing cell. It identifies a function whose
own call list did not change but whose reachable set did — that is, a function
affected by a change it does not itself contain. Measured across 12 historical
state pairs: 1,156 / 12 / 0 / 45. The `direct-only-change` cell was not
observed in that sample but is reachable (adding a direct call to a function
already reachable indirectly) and is therefore retained in the enum.

**The vocabulary is serialised, not only documented** (D10, A4). This table
and §11.4's live in `pss.py` (`PSS7005_CLASSIFICATIONS` /
`PSS7006_CLASSIFICATIONS`, each in its own table's row order — the two
tables order their rows differently, so the row-key sequences are stated per
table) and `--capabilities` publishes them under
`delta_records.shape.classification_values`, because the intended caller
holds no SPEC (§2.6) and a round-2 reviewer had to infer the enum from the
value names alone. The comparator's cell lookups are derived from the same
constants, so the descriptor and the behaviour cannot disagree; the gate
holds every emitted classification against the declared vocabulary.

### 11.4 The combined classification

`PSS7006` crosses `PSS7001` (did the text change) with `PSS7005` (did the
dependency context change), collapsing each to a binary:

| text | dependencies | `PSS7006` value |
|---|---|---|
| unchanged | unchanged | `unchanged` |
| changed | unchanged | `local-change` |
| unchanged | changed | `dependency-only` |
| changed | changed | `change-and-propagation` |

`dependency-only` names a function that was **not edited** yet may behave
differently. It appears in no textual diff and in no hash. Measured across 12
historical state pairs: 1,142 / 14 / 12 / 45 — that is, of 1,213 comparisons,
71 warranted attention and 12 of those were invisible to any text-based review.

The value names are deliberately neutral. `pss.py` does not assign review
priority; that is a judgement and belongs to the caller.

---

## 12. The variable model

### 12.1 The scoping model

Confirmed by execution against the reference PowerShell runtime:

1. **Reads inherit dynamically.** A callee reads a caller's variable. Which
   declaration a reference binds to depends on the runtime call chain and is
   undecidable in general. This is the mechanism behind `PSS9004`.
2. **Writes are local by default.** A callee's assignment creates a new local
   and does not propagate to the caller. This bounds the blast radius and is
   why `PSS9004` is read-side only.
3. **Explicit parent-scope writes exist.** `Set-Variable -Scope N` does
   propagate and cannot be tracked statically — hence `PSS9003`.

### 12.2 Declaration sites (normative)

`PSS2002` is emitted for:

- a `param()` block parameter, or an inline `function f($a)` parameter;
- a `foreach` loop variable;
- an assignment whose left-hand side is a **variable expression**;
- an assignment whose left-hand side is a **type-conversion wrapping a variable
  expression** (`[int]$x = 1`);
  
  Both forms count under **every** assignment operator: `=`, `+=`, `-=`, `*=`,
  `/=`, `%=` and `??=`. An implementation that recognises a subset of these
  records a compound assignment as a reference. Three of the seven were
  unreachable in this tool until they were tokenized ahead of the word rule —
  `-` and `/` lead legal words (parameter names, paths) so `-=` and `/=` were
  split, and `??=` was split by the two-character operator rule. An enumerated
  operator that the tokenizer cannot emit is dead text; §13.1's baseline gate
  is what makes such a gap visible rather than plausible.
- `Set-Variable` / `New-Variable` with a literal `-Name`;
- an `-OutVariable` / `-ErrorVariable` / `-WarningVariable` /
  `-InformationVariable` / `-PipelineVariable` common parameter.

**Implementation status: all five sources retain a site** (as of
`model_version` 3). Every recognised declaration is a record, and every
record has a line:

- a `param()` entry, an inline signature parameter and a `foreach` loop
  variable are **var tokens** — their site was always in the stream, and it
  is now classified as the declaration it is (role `write`) whether or not a
  default value's assignment operator follows. `counters.assignments` is
  unmoved by this: its definition stays *assignment operators plus parameter
  defaults*, held by the Appendix B differential.
- a `Set-Variable` / `New-Variable` `-Name` and an `-OutVariable`-family
  value name their variable in a **string literal**, not a var token, so the
  declaration site is **synthesised at the name literal's own position** and
  flows through the same classification as every var token. A synthesised
  site does not touch `counters.variable_refs`, which counts variable tokens
  and this is not one. The name must be a **literal**: a bareword, a
  single-quoted string, or an expandable string that carries no variable and
  no subexpression — a computed name names nothing this tool can resolve
  statically, and no site is synthesised for it. The `-OutVariable` append
  form (`+name`) declares the same name; the sign is stripped.

Before this arc only the two assignment forms produced a record; a read
against the other four resolved for `param()`/`foreach`/`Set-Variable` but
the `-OutVariable` family was not recognised at all, so its reads reported
`PSS9004` while this section claimed otherwise. Both the gap and the
misstatement closed together, red-first (§13.1).

`PSS2002` is **not** emitted for:

- an assignment whose left-hand side is a **member expression**
  (`$x.Property = 1`) — this is a *reference* to `$x`, not a declaration of
  anything;
- an assignment whose left-hand side is an **index expression** (`$x[0] = 1`) —
  likewise a reference.
- a variable standing in **member-name position** on an assignment's left-hand
  side (`$obj.$name = 1`, `$type::$name = 1`) — `$name` is *read* to supply the
  member's name, and the assignment targets the member. Recognising this needs
  a look-behind for `.` or `::`, not only the look-ahead for `=`: the dynamic
  form otherwise reaches the same corruption the two static exclusions above
  are written to prevent, and reaches it without matching either of them.

The exclusion is load-bearing rather than pedantic. Measured on the reference
target: 5,114 assignment statements decompose into 4,578 variable left-hand
sides, 41 type-conversion left-hand sides, **407 member left-hand sides** and
**88 index left-hand sides**. Treating the latter 495 as declarations would
corrupt every downstream usage map.

Measured frequencies of the other forms on the reference target, recorded so
that a conforming implementation knows which paths the reference data
exercises: `foreach` 356, `param` 948, `Set-Variable`/`New-Variable` family 3,
`-OutVariable` family **0**, splatted references 14, brace-quoted names
`${...}` 4, `$using:` expressions **0**.

### 12.3 The usage map

For every script-scope variable name, `PSS2008` carries:

```json
{
  "id": "variable:script/OsProfile",
  "writers": ["function/Invoke-SetupPhase02_ResolveInputs", "..."],
  "readers": ["function/Resolve-InstallWimTargetIndexes", "..."],
  "writer_count": 2,
  "reader_count": 12
}
```

A function appears in `writers` if it contains a declaration site (§12.2) for
that name at script scope, and in `readers` if it contains any reference to it.
The script level itself is represented by the reserved owner `<script>`.

**Membership and contribution are order-independent (normative).** Which
names carry a usage map, and which owners sit in each set, must not depend on
where in the file a site happens to sit. Script-owner unqualified
contributions are therefore applied against the **complete** classified
population: a top-level write is a writer whether the file's functions are
defined above it or below it. The admission rule itself is unchanged — an
unqualified name joins the population only through a `$script:` qualifier
somewhere or a cross-boundary read; a name no function touches gets no map.
Before this arc the contribution was applied site-by-site in document order,
which dropped every script-side write classified while the map was still
empty — a script whose `param()` block and top-level assignments precede its
functions lost exactly its writers, and §12.7's rule (c) then fired on
declaration order rather than on the code.

The usage map is the variable-side analogue of a function's callee set: it is
the structural signature that survives a rename. Measured on the reference
target at the pinned blob, the 156 names carrying a usage map produce 120
distinct usage signatures; the collisions fall among narrowly-used variables,
whose blast radius is correspondingly small. The previously recorded pair,
155 names and 115 signatures, is reproduced by no generation jointly: 115 is
reproduced at generations 104-110 of entry `0002` and by none thereafter, and
155 by none at all. They were separate measurements of separate states, which
is why they never agreed with each other (ADR 0036). This inverse relationship between collision risk and
consequence is a property to be reported, not a defect to be hidden.

### 12.4 References inside expandable strings

A variable referenced inside a double-quoted string or here-string is a real
reference and is emitted as `PSS2007` in addition to its ordinary reference
fact. Measured on the reference target at the pinned blob: 118 such references
on **84 distinct source lines**. The line is the unit because the model carries
no identifier for the containing string; two expandable strings on one line are
therefore counted once, and the figure is named for what it counts rather than
for what it approximates. A previously recorded 83 is reproduced at generations
88-111 of entry `0002` and not at the pin.

These matter disproportionately because the surrounding syntax defeats naive
text substitution: `"${Foo}bar"` uses brace delimiting, and in `"$Foo.Property"`
the reference ends at `Foo` while `.Property` is literal text. A rename
performed by search-and-replace will corrupt or skip these sites.

### 12.5 Soft-reference scoping

`PSS3002` matches string literals against **script-scope variable names only**
— specifically the `script:`-qualified names (198 at the pinned blob), not
the wider `PSS2006` declaration population. Measured on the reference target:
27,626 string literals produce 8,821 matches against the full variable-name
population and 146 against the script-scope population — a factor of 60. The
unrestricted variant is not actionable and is not offered.

**Matching rule (normative).** Whole-literal equality, case-insensitive; the
`$` sigil is not part of the compared text; no leading or trailing trim;
literals that are empty or whitespace-only are skipped (671 on the reference
target). The name side must have its **scope prefix removed** before comparison
— see Appendix D.5.

### 12.6 The population partition

Every variable reference falls into exactly one class, and each class has a
defined detection route. The partition is stated so that no class is silently
uncovered:

| Class | Reference count | How a rename defect surfaces |
|---|---:|---|
| Function-local | 20,363 | `hash_body` of the declaring function (blast radius is the function) |
| `$script:` scope (inside a function) | 1,381 | §12.7 rules (a), (b), (c) |
| Automatic | 2,004 | Not applicable — not renameable |
| `$env:` | 14 | Not applicable — an external contract, reported but not rename-tracked |
| Outside any function | 555 | Script level; see §12.3 for the reserved owner |

Classes are exclusive and, under the §10.8 attribution convention, sum exactly
to the total (24,317). **`PSS9004` is not a class**: it is an annotation on the
function-local class marking reads that carry no local declaration (11 on the
reference target, across 5 functions and 4 names).

### 12.7 Rename-omission detection (normative)

Three rules operate on the usage map. Each produces a **candidate with its
evidence**, never a conclusion.

**Rule (a) — producer/consumer desynchronisation → `PSS8006`.**
For a script-scope variable present in both models: if at least one writer
function's `PSS7001` is not `identical`, and at least one reader function's
`PSS7001` is `identical`, emit the variable, the changed writers, and the
unchanged readers.

Rationale: if the writer renamed the variable and a reader was not touched,
that reader still references the old name. The rule does not distinguish this
from an ordinary value-semantics change, which is why it names a candidate.

Measured noise on real history: over six consecutive state pairs of the
reference target, spanning transitions that changed up to 42 functions, the
rule produced 2, 0, 0, 0, 0 and 1 candidates respectively.

**Rule (b) — incomplete-rename candidate → `PSS8005`.**
Compare the script-scope name sets. A completed rename yields one name removed
and one added. An **incomplete** rename yields a name added while the old name
*persists* with reduced usage. Emit the added name, the persisting name, and
both usage-count deltas.

Where a removed name and an added name carry equal writer and reader counts,
emit that correspondence as part of the evidence. On a real historical
twelve-for-twelve renaming wave this paired every variable correctly.

**Rule (c) — no write site retained → `PSS8007`.**
A script-scope variable whose reader set is non-empty in the after model while
its writer set is empty there. Unlike (a) and (b), this rule is **decidable
within the model**: it reports a set that is empty, not a resemblance.

It is **not decidable outside the model**, and the distinction matters. The
model's writer set is not a complete account of writing — §12.2's five
declaration sources are all retained now, and a write can still take a form
no static site can carry: a non-literal `Set-Variable -Name`, a `[ref]`
write, a `-Scope` write (§12.1) — and what an unwritten read
does at run time depends on `Set-StrictMode`, which the tool does not observe.
So the fact is the empty writer set in a model that carries readers. Calling
the variable broken would assert both premises the tool cannot see (§1.3).
Emitted only as a difference between two models; the single-state equivalent
belongs to `psa.py` (§7).

**The two-state transcription (D11, round-3 B4, normative).** `PSS8006`,
`PSS8007` and — in both verbs — `PSS7007` carry `baseline_state` and
`successor_state` in `detail`: for the subject variable, each model's writer
and reader **identities with the site lines that model's own reference
records retain** (`{"writer_count": n, "writers": [{"id", "lines"}],
"readers": [{"id", "lines"}]}`, identities sorted, lines ascending). This is
the join both round-3 reviewers performed by hand against the raw models
before they could act on a record — one of them proved on real data that a
trace's `PSS8007` reads as "introduced by B" until the baseline shows the
empty-writer state predates the change — and the delta writer holds both
models at emission time, so the state is transcribed, not reconstructed.
`writer_count` counts identities with retained reference sites in that
model; on `PSS8007`, `baseline_state` is `null` when the variable does not
exist in the before model (a state for a subject a model does not carry).
Facts only: which of pre-existing debt or introduced condition the pair
amounts to remains the consumer's reading, now decidable from the delta
alone. Delta-shape change under §6.4's standing: B.7 restamped, no
`model_version` interaction.

**Verification.** The three rules were validated by injecting a realistic
defect: in a historical state, `$script:OsProfile` — referenced by 12 functions
— was renamed throughout except in one function, reproducing a single-site
omission. Rule (b) reported the new name added while the old name persisted
with readers 12 -> 1 and writers 2 -> 0; rule (c) reported the absent write site;
rule (a) named `Resolve-InstallWimTargetIndexes`, the function deliberately
left behind. The three detectors are independent and mutually redundant by
design.

---

## 13. Self-quality gates

This section lists two different things and does not blur them: gates this
build actually runs today, and gates this SPEC requires of a *complete*
`pss.py` but which have no implementation yet (mostly owed to S4, the
`test_pss.py` differential-test suite, which has not been started).

### 13.1 Implemented today (verified by running `pss.py --self-check`)

| Gate | Requirement |
|---|---|
| Syntax | `py_compile` clean |
| Self-check | `--self-check` confirms this SPEC's §4 catalogue and the codes compiled into `pss.py`'s `FACTS` dict agree as **sets of code strings**, exiting non-zero on drift. **This does not confirm any code is ever attached to an emitted record** — see the "Emission coverage" row in §13.2. `PSS2005`, `PSS4001` and `PSS4002` are confirmed emitted by manual audit (§4.2, §4.4); `PSS2002` is emitted for all five §12.2 sources, each held red-first by a §13.1 fixture |
| Provisional index | `--self-check` confirms every `[PROVISIONAL Pnn]` marker in this SPEC has a row in Appendix F and vice versa. A **pending** revision is normal work in progress: reported, exit code unchanged. A **mismatch** between markers and index is a defect in the tool or the document: exit code 2, as for SPEC/catalogue drift. Appendix F must be empty before manifest registration |
| Axis vocabulary | `--self-check` confirms the axis names compiled into `pss.py` and the §5.6 table agree in both directions, exiting non-zero on drift |
| Golden vectors — shared | `hash_full` reproduces the repository's shared normalized-hash golden vectors exactly (checked by `--self-check`) |
| Golden vectors — own | `hash_body` reproduces `pss.py`'s own vectors, which include the collision cases of §10.3 as explicit non-collision assertions (checked by `--self-check`) |
| Baseline | `test_pss.py` re-derives every figure in Appendix B.8 from the **pinned blob** (§14.2, ADR 0034) and exits non-zero on divergence. The B.8 block is the single master: the gate carries no expected values, so the document and the check cannot drift apart. A model key path that B.8 does not record is itself a finding — an unrecorded figure is one nothing re-derives. Anchoring to a blob rather than a branch head is what keeps ordinary maintenance-stream work from turning this gate red (ADR 0029) |
| Baseline digest | `test_pss.py` derives the acceptance block (B.8 less its `basis`), checks it against the document **by value**, and checks that `--emit-baseline-digest` — the single implementation a derived cache calls (§14.4) — reproduces the gate's own digest. A cache and this gate therefore cannot disagree about what was measured |
| Model shape | `test_pss.py` fingerprints the emitted model's key-path set for the default and full-axis materialisations and compares both against B.8. A change of shape is a failure, not a silent event; the failure is the point at which whether `model_version` advances or is held is decided and recorded |
| Channel agreement | a derivation per numeric text-channel row, applied to the model and compared with what the renderer printed |
| Projection invariance | per axis, a survey with and without it, compared by containment on the narrower key vocabulary (§5.6) |
| Determinism | two extractions of the pinned blob per materialisation, compared as bytes (§5.4) |
| Operating context | `test_pss.py` holds §2.6 two ways. Structurally, `pss.py`'s module-level imports are parsed and compared with a declared allowlist, so the tool has no means of reaching a subprocess, a socket or an HTTP client, and a new import must move the allowlist deliberately. Behaviourally, `survey`, `slice` and `--capabilities` are run in an empty directory that is not a repository, with an environment carrying no executable search path, and their output must be **byte-identical** to the same run made inside this repository. The check exists because the corpus is reference data for the gates and the tool must not acquire a dependency on it |
| Cache generator | `test_pss.py` holds the SPEC §14.4 producer two ways. Structurally, this file's own syntax tree is parsed: no producer function may name `hashlib` and `baseline_digest` must have exactly one definition — the digest has one implementation, and a second would let a cache and this gate disagree about what was measured. The scope is the producer's named functions, and a function omitted from that list is not examined, so the list is checked against the module first. Behaviourally, a real two-generation cache is produced and its header compared with §14.4's field set **in both directions**, its axis set required to be complete, and its records required to carry `rev` and `blob` and nothing derivable from position. The digest and shape in the header must equal what `--emit-baseline-digest` gives |
| File inventory | `test_pss.py` enumerates the tool's file set and requires an exact match, holding §14.1's two-file rule. Enumerated rather than counted: a list names the unaccounted file and also catches one that disappeared. Read from the committed inventory and, for `.py` only, from the working directory, so an unstaged third module fails too. `corpus/` is matched by pattern, since entries are meant to accumulate — what is held is that nothing which is not an entry appears. Adding a file means editing §14.1 and this list together, which is the intended cost |
| Neutral naming | `test_pss.py` applies a denylist of judgement words to the fact-code descriptions and the subcommand help strings (§1.3), and checks the denylist actually covers every code and every subcommand rather than an empty set. **A denylist makes no completeness claim**: it stops listed words from returning and detects nothing worded some other way. SPEC prose is out of scope, because the rule itself has to be able to say the word in order to explain why a code may not |
| Capability descriptor | `test_pss.py` compares every enumerated block of `--capabilities` with the constant it is supposed to be **reading** — a literal copied into the descriptor diverges the moment the constant moves — and the subcommand set against the §3 synopsis in both directions. The `implemented` / `not-implemented` marks are then checked **against the build**: `compare` must refuse, a usage error under `--format json` must not emit JSON, `survey --format json` must emit a model, and that model must carry the cost block. A mark cannot drift into a lie, and a feature cannot land while leaving its mark behind. Needs neither `git` nor `pwsh`, so it survives every degradation level of §14.3 |
| Identifier forms and join keys | `--self-check` compares `pss.IDENTIFIER_FORMS` and `pss.COLLECTION_KEYS` with §5.8 on name **and** value — a form that agrees on its name while disagreeing on what it matches is exactly the drift a published descriptor makes dangerous. `test_pss.py` holds the declaration against the pinned blob: every listed field populated, every join value resolving into `symbols` or `<script>`, every other identifier matching exactly one declared form, and every declared unique key unique. The form set is checked for **exercise**, not only for agreement — a form no identifier at the pin belongs to is an enumeration nothing drives (§13.2) |
| Declared schema | `--self-check` compares `pss.MODEL_SCHEMA` with §13.3 on path and kind; `test_pss.py` compares the declaration with what the pinned blob emits in both directions — emitted-but-undeclared and declared-but-unemitted are separate failures, and `optional` is the only exemption |
| Cost report | `test_pss.py` **re-derives** the decomposition from the model — every list collection priced, `model_bytes` measured on the model less the block, `envelope` as the stated remainder — and compares by value. It does **not** re-check the block's own sum: `envelope` is computed as a remainder, so `sum + envelope == model_bytes` holds even when a whole collection is missing from the breakdown, which was demonstrated before landing |
| Version decision | `test_pss.py` re-runs the parent commit's `pss.py` against the same pinned blob and fails when the emitted model moved — shape **or** measured values — while `MODEL_VERSION` did not (§5.5, ADR 0035). No ledger of past versions is kept: the previous state is derived, so there is no second copy to go stale (ADR 0036). Skipped, and reported as skipped, where there is no comparable parent |
| Materialisation-stated figures | a figure that is not axis-invariant is asserted **per materialisation** and both values are re-derived — today `references_outside_functions` (485 default / 556 with `local-sites`). A single number for such a figure is unfalsifiable, the projection-side form of the basis rule (ADR 0036) |
| Fixtures | `test_pss.py` runs synthetic cases for the extractor rules that have actually failed — every assignment operator including the three that were unreachable, the member-name exclusions of §12.2 including the dynamic form, and the tokenizer regressions those fixes risked. These need no corpus and run even when `git` is absent (§14.3) |
| Delta baselines | Appendix B.7 pins comparator outputs and the gate re-derives them three ways: `trace` and `compare` over an adjudicated pair of committed generations (retrieved by blob, never by branch head — the ADR 0034 anchoring, so maintenance work cannot redden it), and `compare` over two independent fixture scripts embedded in the gate — the pair corpus history cannot supply, because every pair drawn from an entry stands in the relation `trace` asserts (§4.9). Fixture identity is held by the emitted document's own `source.sha256` against the recorded basis, so the embedded text cannot drift from what the block claims was measured. The corpus legs need `git` and degrade by name without it; the fixture leg runs at every degradation level (§14.3). The `Publish-ReleaseArtifacts` fixture deliberately carries the §10.6 [F4] instance, and adjudicating [F4] at the D10 arc reddened these figures rather than moving them silently — the red-then-restamp path the pin was built for, observed |
| Value nullability | `--self-check` compares `pss.NULLABLE_PATHS` with the §13.3 nullability table in both directions and requires each entry to be a declared key path; `test_pss.py` holds the declaration against reality on the pinned blob and a slice of it — every observed null path is declared, and every declared path actually carries a null somewhere the gate exercises, so the mark can neither lag reality nor outrun it. `--capabilities` serialises the declaration (`nullable_paths`), checked as serialised, not restated |

A non-zero exit on mismatch does not conflict with §9. §9 forbids the exit code
from carrying a verdict **about the surveyed script**; an inconsistency between
this document and the tool is an internal defect, the same class of condition as
SPEC/catalogue drift.

### 13.2 Specified, not yet built

None of the rows below are checked by `--self-check` or any other automation
in this build. They are the gates this SPEC will hold `pss.py` to once the
corresponding feature or suite exists; listing them here now, rather than
inventing them when the feature lands, is deliberate — the same reasoning as
Appendix F. A caller (including an LLM caller reading this SPEC per §3.1)
should not assume any of these are currently enforced.

| Gate | Requirement | Blocked on |
|---|---|---|
| Capability descriptor | **RESOLVED.** `--capabilities` is built and `test_pss.py` gates it two ways. Each enumerated block is compared with the constant it serialises, so the descriptor cannot become a second copy of a fact (§13.3, ADR 0036); and the `not-implemented` marks the descriptor carries for the delta record and the error payload are checked against behaviour — `compare` is run and must refuse, a usage error is provoked under `--format json` and must not emit JSON. Implementing either output without moving its mark reddens the gate, so the two outstanding items are visible in the published interface rather than absent from it | closed |
| Projection invariance | **RESOLVED.** For each axis, `test_pss.py` surveys the pinned blob with and without it and checks **containment**, not equality: everything the narrower model says must also be said by the wider one, on the narrower model's own key vocabulary. The vocabulary is derived from the two models rather than read from §13.3, which marks a path `axis` without naming which axis contributes it — so this check does not inherit that declaration's errors. `cost` is excluded by name, because it describes the model and a smaller model is correctly a different size | closed |
| Channel agreement | **RESOLVED, in full (post-D12 independent-remainder close).** `test_pss.py` carries a derivation per text-channel figure, written from this document's definitions and applied to the model rather than lifted from `render_text` — re-running the renderer's own expression would compare a restatement, not a measurement. The check reads **every figure on a row** — the head and each standalone number inside parentheses (a code like `PSS2007` contributes nothing: no word boundary splits an alphanumeric token) — and a derivation may return a tuple to cover the printed split. The four previously-uncovered rows (`lines`; the three soft-reference rows) now carry derivations, and the split coverage was demonstrated red-first: with head-only extraction, swapping `quoted 48 / bareword 1` to `quoted 1 / bareword 48` in the rendered text **passed the gate untouched**; the widened extraction reddens on exactly that swap. Three directions still redden it: a text figure the JSON does not support, a new numeric row with no derivation, and a derivation whose row has vanished. The conditional `boundary stubs` row (D12, §6.2) prints only on a stubbed slice — absent from every pin-model text the derivation table reads — and is held by fixture instead, together with the stub-aware `functions` derivation | closed |
| Determinism | **RESOLVED.** `test_pss.py` extracts the pinned blob twice at each materialisation and compares the **serialised bytes**, not the parsed objects: key order is part of what §5.4 promises, and two dicts can compare equal while serialising differently. Re-checked now rather than left as written, because `--cost` re-runs the survey internally to price an absent axis (§3.1), so a default-materialisation model is produced by four extractions rather than one | closed |
| Reachability | no §10.5 unreachable combination is producible over the regression corpus (`PSS9006` count is zero) | S4 |
| Derivation owed | **RESOLVED (ADR 0036).** Every B.3 figure is re-derived by `test_pss.py` from the pinned blob, withdrawn as an orphan, or re-stamped with the state that reproduces it; a figure with no executable derivation is no longer permitted to exist | closed |
| Call-site locations | **RESOLVED at the D10 arc.** `edges[].lines` carries every site, ascending, on the default model; `line` is normatively `lines[0]` (§5.9). The shape was consumer-adjudicated across two rounds before it was built, and the gate holds it by fixture (ascending order established at emission — a `$( ... )` site is scanned after the top-level stream) and by the B.8 shape fingerprints | closed |
| Per-record presence contract | **RESOLVED at the D11 arc.** The declaration shape was consumer-adjudicated across two candidate specimens (round 3, §3.2): variant enumeration with machine-evaluable predicates and non-circular discriminators, first-class conditional keys, and a per-path index derived from the variants at serialisation time. Six collections declared — measurement corrected the round's five-collection estimate — and the survey's own candidate-A specimen demonstrated the quiet failure of the exceptions-only alternative by violating its own complement rule. `pss.RECORD_VARIANTS`, serialised by `--capabilities`, held by `--self-check` both ways and by the gate over both pin materialisations, a slice and the fixtures (§13.3 Per-record presence) | closed |
| Dynamic command sites | **RESOLVED at the D12 arc, with its premise corrected by measurement.** The row as written claimed no collection itemises dynamic invocations and `limitations` is silent — measured false before implementation: the 26 sites had carried per-site `PSS9002` records with `owner` and `line` since the tool's first commit, on the default model. What was missing was the **name expression**: a record locating a dynamic invocation still sends a rename pre-flight back to the source, because nothing states *which* expression is invoked. `PSS9002` records now carry `target` — the expression verbatim, extended over byte-adjacent tails only (§4.8; the §10.6 adjacency discipline) — so the pre-flight becomes a model join against the variable collections. The adjudicated axis-shaped itemisation was withdrawn together with the premise: duplicating records already on the default model into an axis is the two-copies shape this SPEC spends its rows fighting. `limitations` entered the §13.3 variant declaration in the same commit (four code-discriminated variants), because one code carrying a key three others do not is not uniform | closed |
| Command-site arguments | **RESOLVED at the D12 arc.** A site record carries `arguments` — the invocation's argument tokens in order, each `{kind, text}` verbatim, itemisation-not-binding (§4.2, §1.2) — and `span`, the [start, end) byte extent that disambiguates what a line number cannot: a backtick-continued invocation is one element and its span says so, and two same-line invocations of one name carry two spans. Variable and bareword items extend over byte-adjacent tails (§10.6 discipline), a parenthesised or scriptblock argument is captured balanced **over tokens** so a paren inside a string cannot derail it, and separators/redirections are covered by the span rather than itemised. Held by the variant key-set gate over every checked model and by behavioural fixtures for each kind | closed |
| Slice boundary stubs | **RESOLVED at the D12 arc.** Round 3 measured a function slice keeping 33 edge endpoints that resolved to nothing inside the slice; re-measured before implementation the same scope references 172 absent identifiers (47 from `edges`/`closures` alone). A `--scope` slice now re-introduces every referenced-but-absent symbol as a stub — `record: "stub"` plus the four common keys, copied verbatim from the input, additive only, declaration-driven off `COLLECTION_KEYS.symbol_refs` (§5.7) — and the `symbols` variant declaration was re-cut so the common set IS the stub set (§13.3). `slice` refuses a foreign `model_version` (`PSS9005`), for the same reason `compare` does. Held by a resolution gate (every referenced identifier resolves inside the slice), a verbatim-copy gate, and behavioural fixtures including slice-of-slice | closed |
| Static analysis | **RESOLVED (post-D12 independent-remainder close).** Wired into a `pss.py`-specific CI run on the analyzer's precedent (`.github/workflows/quality-tools__powershell-symbol-surveyor.yml`): `py_compile` over both files as the fail-fast static-analysis step, then `--self-check`, then the full §13.1 battery with `pwsh` (preinstalled on the runner), per push/PR touching this directory. `fetch-depth: 0` is a **measured** requirement, not a default: on a depth-1 clone the battery fails — the B.7 corpus pair and the §14.4 generator read committed-generation blobs that exist only in history — while the pin itself survives shallowness only by the coincidence that the reference script's HEAD content still equals it | closed |
| Docs | **RESOLVED.** `README.md`, `README.ja.md`, `SPEC.md`, `CHANGELOG.md` and `VERSION` all exist, and `test_pss.py` holds them rather than leaving their presence to inspection: each file must exist, `VERSION` must equal `pss.__version__` (one version, two places, so the file cannot go stale against the code), and the bilingual pair must be in **lock-step on structure** — the same heading text ordering by level, the same number of fenced blocks. Lock-step is checked structurally rather than by translation, and that limit is stated: it catches a section added to one and not the other, and says nothing about whether a paragraph's content still agrees | closed |
| Emission coverage | every code in §4 blocks 1-4 (survey-emittable) appears as a `code` or `facts` value on at least one record somewhere in the regression corpus's models, or is documented as data-dependent-absent (e.g. `PSS1005` legitimately does not fire on a corpus with zero duplicate names) | `PSS2005`, `PSS4001`, `PSS4002` closed by manual audit. `PSS2002` closed for all five §12.2 sources at the D10 arc — each source is held red-first by a §13.1 fixture, which is stronger than corpus presence. No automated corpus-wide gate yet for the rest; S4 |
| Declared model schema | **RESOLVED (ADR 0036).** §13.3 declares the path set (counts stated there, per materialisation) and `pss.MODEL_SCHEMA` carries it; `--self-check` holds the two together on path *and* kind, and `test_pss.py` holds the declaration against the pin in both directions. The pairing with the §3.1 descriptor is satisfied by the declaration living in the code, so `--capabilities` can serialise it rather than restate it | closed |
| Version-decision enforcement | **RESOLVED (ADR 0036).** The parent commit's build is re-derived and compared; a model that moved without the version advancing is a failure. Measured against real history the check reddens at `44b97d1` (shape moved) and at `bc69c27` (shape identical, values moved) | closed |
| Enumerated-constant reachability | **the generalisation of the row above.** Every constant this tool enumerates — fact codes, the assignment-operator set, the automatic-variable set, the axis vocabulary — is demonstrably reachable: some input drives it, or it is documented as data-dependent-absent. Enumerating a capability the machinery cannot exercise has now failed twice in the same shape — four fact codes defined and never emitted, and three assignment operators the tokenizer could not produce (§12.2) — and both times every gate stayed green because the check compared *names* rather than *behaviour*. `test_pss.py`'s fixtures cover the operator set; the fact catalogue and the automatic-variable set are not yet covered | S4 |

Registration as a whole-tool unit sets `tested = true` on the basis of the
§13.1 self-test being green, not on the canon behavioural suite — and not on
§13.2, which is why §13.2's rows are listed as owed rather than as blocking
registration. **Registered (post-D12):** `tool.powershell-symbol-surveyor` @
0.4.0, kind `tool`, whole-directory unit on the analyzer's precedent, via the
manifest CRUD (ADR 0011); Appendix F had been empty since 2026-08-16, so the
condition above was already met.

---

### 13.3 The declared model schema

The §13.1 fingerprint is a check over the paths a **given** model happens to
carry. An optional field that the pinned generation never populates can appear
or vanish without moving it — which is not hypothetical: two such fields exist,
and they are why corpus entry `0001` carries two fingerprints across its 73
generations. A fingerprint over observed paths is not a schema, so the path set
is **declared** here and in `pss.MODEL_SCHEMA`, and checked in both directions.

`--self-check` holds the constant against this table, the way it already does
for the fact catalogue (§4) and the axis vocabulary (§5.6). `test_pss.py` holds
the declaration against what the pinned blob actually emits: every emitted path
must be declared, and every declared path must be emitted at the pin or be
marked `optional`. The declaration lives in the code rather than only here so
that §3.1's `--capabilities` can serialise it rather than restate it — the
descriptor and the declaration are the same fact, and two copies of a fact
drift (ADR 0036).

| Kind | Meaning |
|---|---|
| `always` | present in every model, at every materialisation |
| `axis` | present only when its axis is materialised (§5.6) |
| `optional` | data-dependent; present when the source populates it |

**The two `optional` paths, with their basis.** Measured over all 230 committed
generations of both corpus entries at the `all-axes` materialisation:
`/script_variables[]/in_expandable_string` and
`/string_interpolation_references[]/qualifier` each appear in **204 of 230**
generations. They are absent from the smaller early scripts, which is exactly
the data dependence the fingerprint cannot police, and marking them is
therefore a recorded measurement rather than a licence to be absent.
`/limitations[]/target` (D12) is `always` on the same per-model reading as
`/symbols[]/parent`: measured over all 230 generations, `commands_dynamic`
is never zero on this corpus, so every generation emits the path.
`/symbols[]/ordinal` (D12) is the third `optional` path: emitted only when a
definition name is duplicated (§5.2, `PSS9007`), absent at the pin and on
**all 230** corpus generations — which is exactly why no pin-anchored check
had ever seen it. It surfaced when the variant-demonstration fixture put the
first duplicate-name model in front of the presence gate; an emitted key no
declaration covered was the finding, and declaring it is the close.
`/symbols[]/record` (D12) is the fourth: it marks a §5.7 boundary stub and
can therefore appear only on a `--scope` slice — a surveyed model never
emits it, so it is absent at the pin and on every corpus generation by
construction, and the presence gate reads it on the pin slice instead.

Counts at the pinned blob: **129** paths at `all-axes`, **115** at the default
materialisation, the difference being the ten `axis` paths.

| Key path | Kind |
|---|---|
| `/closures` | always |
| `/closures[]/code` | always |
| `/closures[]/facts` | always |
| `/closures[]/id` | always |
| `/closures[]/members` | always |
| `/closures[]/named_by_literal` | always |
| `/closures[]/record` | always |
| `/closures[]/transitive_callee_count` | always |
| `/closures[]/transitive_callees` | axis |
| `/closures[]/transitive_caller_count` | always |
| `/closures[]/transitive_callers` | axis |
| `/cost` | always |
| `/cost/axis_increment` | always |
| `/cost/axis_increment[]/axis` | always |
| `/cost/axis_increment[]/bytes` | always |
| `/cost/by_collection` | always |
| `/cost/by_collection[]/bytes` | always |
| `/cost/by_collection[]/collection` | always |
| `/cost/by_collection[]/records` | always |
| `/cost/envelope` | always |
| `/cost/envelope/bytes` | always |
| `/cost/format` | always |
| `/cost/measured` | always |
| `/cost/model_bytes` | always |
| `/cost/source_sha256` | always |
| `/counters` | always |
| `/counters/assignments` | always |
| `/counters/commands_dynamic` | always |
| `/counters/commands_named` | always |
| `/counters/expandable_strings` | always |
| `/counters/interpolation_refs` | always |
| `/counters/string_literals_bareword` | always |
| `/counters/string_literals_quoted` | always |
| `/counters/unresolved_named_command_sites` | always |
| `/counters/variable_refs` | always |
| `/edges` | always |
| `/edges[]/code` | always |
| `/edges[]/from` | always |
| `/edges[]/lines` | always |
| `/edges[]/sites` | always |
| `/edges[]/to` | always |
| `/limitations` | always |
| `/limitations[]/code` | always |
| `/limitations[]/detail` | always |
| `/limitations[]/line` | always |
| `/limitations[]/owner` | always |
| `/limitations[]/target` | always |
| `/local_variables` | always |
| `/local_variables[]/automatic_refs` | always |
| `/local_variables[]/code` | axis |
| `/local_variables[]/id` | axis |
| `/local_variables[]/in_expandable_string` | axis |
| `/local_variables[]/line` | axis |
| `/local_variables[]/local_declared` | always |
| `/local_variables[]/local_refs` | always |
| `/local_variables[]/name` | axis |
| `/local_variables[]/owner` | always |
| `/local_variables[]/record` | always |
| `/local_variables[]/role` | axis |
| `/local_variables[]/unresolved_refs` | always |
| `/materialization` | always |
| `/materialization/axes` | always |
| `/model_version` | always |
| `/pss_version` | always |
| `/script_variables` | always |
| `/script_variables[]/code` | always |
| `/script_variables[]/id` | always |
| `/script_variables[]/in_expandable_string` | optional |
| `/script_variables[]/line` | always |
| `/script_variables[]/name` | always |
| `/script_variables[]/owner` | always |
| `/script_variables[]/qualifier` | always |
| `/script_variables[]/reader_count` | always |
| `/script_variables[]/readers` | always |
| `/script_variables[]/record` | always |
| `/script_variables[]/role` | always |
| `/script_variables[]/writer_count` | always |
| `/script_variables[]/writers` | always |
| `/soft_references` | always |
| `/soft_references[]/code` | always |
| `/soft_references[]/line` | always |
| `/soft_references[]/literal` | always |
| `/soft_references[]/literal_kind` | always |
| `/soft_references[]/matches` | always |
| `/soft_references[]/owner` | always |
| `/source` | always |
| `/source/byte_count` | always |
| `/source/line_count` | always |
| `/source/path` | always |
| `/source/sha256` | always |
| `/string_interpolation_references` | always |
| `/string_interpolation_references[]/code` | always |
| `/string_interpolation_references[]/id` | always |
| `/string_interpolation_references[]/in_expandable_string` | always |
| `/string_interpolation_references[]/line` | always |
| `/string_interpolation_references[]/name` | always |
| `/string_interpolation_references[]/owner` | always |
| `/string_interpolation_references[]/qualifier` | optional |
| `/string_interpolation_references[]/record` | always |
| `/string_interpolation_references[]/role` | always |
| `/symbols` | always |
| `/symbols[]/depth` | always |
| `/symbols[]/end_line` | always |
| `/symbols[]/facts` | always |
| `/symbols[]/hash_body` | always |
| `/symbols[]/hash_full` | always |
| `/symbols[]/hash_raw` | always |
| `/symbols[]/id` | always |
| `/symbols[]/kind` | always |
| `/symbols[]/name` | always |
| `/symbols[]/ordinal` | optional |
| `/symbols[]/parameters` | always |
| `/symbols[]/parameters[]/mandatory` | always |
| `/symbols[]/parameters[]/name` | always |
| `/symbols[]/parameters[]/position` | always |
| `/symbols[]/parameters[]/qualifier` | always |
| `/symbols[]/parameters[]/type` | always |
| `/symbols[]/parent` | always |
| `/symbols[]/record` | optional |
| `/symbols[]/start_line` | always |
| `/unresolved_named_commands` | always |
| `/unresolved_named_commands[]/arguments` | axis |
| `/unresolved_named_commands[]/arguments[]/kind` | axis |
| `/unresolved_named_commands[]/arguments[]/text` | axis |
| `/unresolved_named_commands[]/code` | always |
| `/unresolved_named_commands[]/line` | axis |
| `/unresolved_named_commands[]/name` | always |
| `/unresolved_named_commands[]/owner` | axis |
| `/unresolved_named_commands[]/owners` | always |
| `/unresolved_named_commands[]/record` | always |
| `/unresolved_named_commands[]/sites` | always |
| `/unresolved_named_commands[]/span` | axis |

#### Value nullability

The table above declares **presence**, not values. **Exactly the paths below
may carry JSON `null`; every other path's value is never null.** Absence is
expressed by omitting the key (kind `optional`) — the model's existing
size-driven convention (§4.4, `named_by_literal`: absent, never `false`).
Null is reserved for the three facts below, where the key must stay so the
record shape is uniform and the value's unavailability is itself the fact.

`--capabilities` serialises the declaration (`nullable_paths`);
`--self-check` holds this table against `pss.NULLABLE_PATHS` in both
directions and requires every row to be a declared key path. `test_pss.py`
holds the declaration against reality on the pinned blob and a slice of it:
every observed null is declared, and **every declared path is exercised** — a
nullable mark nothing drives is an enumeration nothing checks (the §13.2
rule, applied to values).

#### Per-record presence

Kind `always` above is a **per-model** claim: the path occurs in every model
this build emits. It has never been a per-record claim — `/symbols[]/parent`
is `always` and sits on 1 of 480 symbol records at the pinned basis — but
until the third consumer review (§3.2) nothing said so, and a reader holding
one record could not tell a missing key from a different record variant. Both
round-3 reviewers converged on the remedy adopted here: for every collection
whose records are not uniform, `pss.RECORD_VARIANTS` declares the **record
variants** — a machine-evaluable predicate (`equals`/`gte` on one key, never
on the absence of the key being explained: both reviewers flagged that as
circular, and `depth` exists on every symbol record precisely to carry this
weight), the exact key set each variant carries, **conditional keys** whose
presence is the value (§4.4's omit-rather-than-emit for negative booleans,
promoted to a first-class slot), and **axis keys** present only when the
axis is materialised. A record matches **exactly one** variant; a collection
absent from the declaration is uniform, and the gate holds that claim too.

| Collection | Variant | When | Carries (beyond common) | Conditional | Observed at the pin |
|---|---|---|---|---|---:|
| `symbols` | `top-level` | `depth == 0` | `depth` `facts` `hash_body` `hash_full` `hash_raw` `name` `parameters` | `ordinal` | 479 |
| `symbols` | `nested` | `depth >= 1` | `depth` `facts` `hash_body` `hash_full` `hash_raw` `name` `parameters` `parent` | `ordinal` | 1 |
| `symbols` | `stub` | `record == stub` | `record` | — | slice-only (§5.7); exercised on the pin slice |
| `closures` | `closure-row` | `record == closure` | `facts` `id` `record` `transitive_callee_count` `transitive_caller_count` | — | 480 |
| `closures` | `uncalled-fact` | `code == PSS4003` | `code` `id` | `named_by_literal` | 26 |
| `closures` | `cycle-fact` | `code == PSS4004` | `code` `members` | — | 3 |
| `local_variables` | `reference` | `record == reference` | `code` `id` `line` `name` `owner` `record` `role` | `in_expandable_string` | 22427 |
| `local_variables` | `aggregate` | `record == aggregate` | `automatic_refs` `local_declared` `local_refs` `owner` `record` `unresolved_refs` | — | 465 |
| `script_variables` | `reference` | `record == reference` | `code` `id` `line` `name` `owner` `qualifier` `record` `role` | `in_expandable_string` | 1879 |
| `script_variables` | `usage-map` | `record == usage_map` | `code` `id` `name` `reader_count` `readers` `record` `writer_count` `writers` | — | 156 |
| `string_interpolation_references` | `reference` | `record == reference` | `code` `id` `in_expandable_string` `line` `name` `owner` `record` `role` | `qualifier` | 118 |
| `unresolved_named_commands` | `site` | `record == site` | `arguments` `code` `line` `name` `owner` `record` `span` | — | 2798 |
| `unresolved_named_commands` | `aggregate` | `record == aggregate` | `code` `name` `owners` `record` `sites` | — | 93 |
| `limitations` | `unresolved-call-site` | `code == PSS9002` | `target` | — | 26 |
| `limitations` | `untrackable-scope-write` | `code == PSS9003` | (common only) | — | 1 |
| `limitations` | `unresolvable-read` | `code == PSS9004` | (common only) | — | 11 |
| `limitations` | `ordinal-identifier` | `code == PSS9007` | (common only) | — | absent at the pin; exercised on the variants fixture |

The `symbols` and `limitations` rows use `common_keys` (the keys every
record of that collection carries — for `symbols`, since D12, the four
identify-and-locate keys a boundary stub shares with a full record); every
other collection declares its full key set per variant. The
`closures` `closure-row` variant additionally carries `transitive_callees`
and `transitive_callers` **under the `closure-sets` axis** — the axis kind
composes with the variant rather than replacing it. Seven collections are
declared: the six of the D11 adjudication (measurement corrected the round's
five-collection estimate by adding `string_interpolation_references`, whose
`qualifier` is conditional — 5 of 118 at the pin), plus `limitations`, which
joined at the D12 arc the moment `PSS9002` records gained `target` — one code
carrying a key three others do not is a variant, and its discriminator is
`code`, which every limitations record carries exactly once. An observed
column that is prose rather than a number marks a variant the pinned blob
cannot produce (two limitations codes; the slice-only boundary stub): the
gate's observed-column comparison reads numeric cells only, and the
exercised check — widened from pin-only to every checked model at the same
arc — is what holds those variants instead. `edges` and `soft_references`
are uniform and therefore undeclared — and the gate holds the uniformity
claim rather than assuming it.

`--capabilities` serialises the declaration verbatim (`record_variants`)
**and a derived per-path index** (`record_variant_path_index`: for each
path, the variants it is present on, conditional in, and any governing
axis). The two consumer moments the reviewers split their preference across
— one record in hand, and planning a query over a collection — are each
served by a machine surface, and because the index is derived from the
variants at serialisation time, the two cannot disagree. `--self-check`
holds this table against `pss.RECORD_VARIANTS` in both directions on the
signature columns; the observed column is data-dependent, so the gate — not
`--self-check`, which runs without input — re-derives it against the pinned
blob, holds exactly-one matching and the declared key sets over both pin
materialisations, a scope slice and the embedded fixtures, and requires
every declared variant to be exercised at the pin.

| Path | Null states |
|---|---|
| `/symbols[]/parameters[]/qualifier` | the parameter is declared without a scope qualifier |
| `/symbols[]/parameters[]/type` | the parameter is declared without a type constraint |
| `/cost/axis_increment[]/bytes` | the model is a slice (§5.7) that no longer carries the axis; the increment cannot be priced from this model (§5.6), and a carried-over figure would describe a different artefact |


## 14. Test-data acquisition

### 14.1 Principle

**The test corpus is not stored; the procedure for obtaining it is.** The
repository's own commit history is the corpus. This keeps the tool at two `.py`
files, matching its siblings, and lets the corpus grow as the surveyed projects
are maintained, rather than freezing and going stale.

**Two files is a rule, not an observation (normative).** `pss.py` is the tool;
`test_pss.py` is the gate and the apparatus the gate needs — the corpus manager
(§14.2) and the cache producer (§14.4) — reached as its `corpus` and `cache`
subcommands. The line between them is the one §2.6 already draws: `pss.py`
reads the files it is given and nothing else, and its imports are held against
an allowlist so it *cannot* reach a repository; everything that must reach one
lives in the gate. A third file was added three times in three days without
this sentence being read, which is how the count reached five; a new one is a
decision to record here, not a side effect of adding a feature.

**The rule is gated (§13.1, `inventory:`).** Writing "normative" in a
specification did not stop the count reaching five, because nothing could fail:
the rule was stated for three days and read by nobody, and the baseline gate
grew from 68 checks to 156 over the same period while looking only at the
model, where a file count does not appear. So the file set is **enumerated**
rather than counted — a count reports "three where two were expected" and
leaves which one open, while a list names the unaccounted file and also fails
on one that quietly disappeared. Two sources are read: the committed inventory,
which is what a patch under review contains and what a clone receives, and the
working directory for `.py` only, because an unstaged third module is the state
a developer is in when the rule matters most. `corpus/` is matched by pattern
instead, since entries are meant to accumulate (§14.2) and a gate that must be
edited to pass stops being read; what is held there is that nothing which is
not an entry appears. Adding a file to this tool therefore means editing this
section and the gate's list together — which is the intended cost.

### 14.2 Obtaining a corpus state

A corpus state is one generation recorded in a corpus entry under `corpus/`
(ADR 0033). An entry pins one path and does not follow renames; the reference
target's directory move is represented as two entries (`0001` before, `0002`
after), not as one `--follow` walk. Retrieval is **by blob**:

```
python3 test_pss.py corpus list              # entries and their generation counts
git show <blob> > <workdir>/<rev>.ps1        # blob taken from the entry's generations[]
```

Resolving by blob rather than by `<commit>:<path>` is required, and both halves
of that requirement come from recorded defects. `git log --follow --reverse`
does not compose, so a `--follow` walk silently mis-orders; and
`git show <commit>:<current-path>` fails for any generation older than the move,
because the path did not exist yet. A blob hash is stable under both. Where an
entry's blob no longer resolves, the tooling raises — it does not skip the
generation.

Appendix B's measurement basis is one such pinned generation, named in that
appendix's preamble (ADR 0034).

The reference corpus at the time of writing spans 230 commits over
approximately ten weeks, during which the target grew from 79 functions and
4,093 lines to 480 functions and 27,229 lines. 116 of those commits changed the
function-name set; 15 changed it in both directions and therefore contain
rename, split, merge or replacement events with the author's stated intent
recorded in the commit message. **`TESTING.md` does not exist yet for this
tool** (tracked in §13.2). `test_pss.py` now exists and covers the pinned
generation; `TESTING.md` is where the labelled multi-state regression cases and
the property each one exercises are enumerated once the differential suite spans
state *pairs* (S4) — the same role `TESTING.md` plays for this repository's
other tools and projects.

### 14.3 Degradation

| `pwsh` | `git` | Suite behaviour |
|---|---|---|
| present | present | Full differential test: extraction is compared against the reference parser over corpus states |
| absent | present | Aggregate regression: extraction is compared against committed expected **aggregate values** (Appendix B), not full models |
| either | absent | Synthetic fixtures only: the unit suite runs against small in-file PowerShell samples |

Committing expected **aggregates** rather than expected **models** is
deliberate: an aggregate expectation is a few kilobytes, a full model for the
reference target is on the order of half a megabyte, and the aggregate is
sufficient to detect an extraction regression.

### 14.4 Derived model caches (normative, ADR 0035)

Surveying every generation of the reference target is expensive enough that the
resulting models are cached outside the repository and carried between sessions.
Such a cache is **derived data**: it is not committed, it is not a baseline, and
it is only usable while it is known which build produced it. That last property
is the one that has to be engineered, because it is the one that was lost.

A derived cache carries, in its header:

| Field | Requirement |
|---|---|
| `pss_version`, `model_version` | the constants of the producing build, as emitted |
| `model_shape` | the §13.1 fingerprints, per materialisation, as emitted |
| `baseline_digest` | `sha256` over the canonical-JSON serialisation of the acceptance block this build re-derives from the pinned blob (B.8, the values — not the document text) |
| `axes`, `corpus_entry`, `corpus_start_rev`, `corpus_end_rev`, `corpus_count` | what was surveyed and over which generations |

The digest has **one implementation**: `test_pss.py --emit-baseline-digest`
prints it, taking it over exactly the block the baseline gate already derives —
Appendix B.8's block less its `basis`, serialised with sorted keys and compact
separators. A generation script computes nothing itself; it calls this and
copies the result. Computing it separately would put a measurement instrument
back outside the repository, which is the defect ADR 0033 retired, and would
let the cache and the gate disagree about what was measured. §13.1's gate
checks that the emitted digest and the gate's own agree, and that the block
equals B.8 by **value** — a key-set comparison would pass while a wrong figure
inside the block went through.

`baseline_digest` is what identifies the build. `model_version` cannot do it
while two builds may legitimately share one (§5.5, and the six that shared
`"1"`), and a shape fingerprint cannot do it at all: the ADR 0034 extractor
fixes changed 2,302 records across the corpus without moving a key path, so the
before and after caches carry identical fingerprints. A digest over the measured
values moves whenever any measured value moves, which is the property the job
needs.

**Identification must not rest on prose.** A free-text note describing how a
cache differs from its predecessor is not a discriminator: it cannot be
compared, and it is written by whoever already knows the answer. Two caches are
the same cache if and only if their headers agree on the fields above.

**The producer is `test_pss.py cache`.** For a long time this section specified a
generator that did not exist, and the procedure lived in prose in a session
handoff and was reconstructed from that prose each time. That is a description
of a procedure, not a procedure, and it was paid for: a shipped cache carried
`gen_index: null` on all 230 of its records, because the reconstruction read a
key the corpus does not have and nothing checked the result. The generator is
now an artifact, so it can be gated (§13.1).

Two of its properties are normative rather than incidental. It obtains
`baseline_digest` and `model_shape` from the one function that derives them -
the same one `--emit-baseline-digest` prints - and copies them, per the
paragraph above. While the producer was a separate `build_cache.py` the
mechanical form of "one implementation" was `hashlib` being absent from that
file; in the merged file `hashlib` is legitimately present, so the gate reads
the syntax tree instead and requires that no producer function names it and
that the digest has exactly one definition (§13.1). And a generation is written with `rev`
and `blob` only: ADR 0033 puts identity in the blob, a position is derivable
from the file's own order, and a stored position is the copy that can disagree
with the list it came from.

The axis set is **fixed at all axes** and is not an option. A cache is only
useful against another cache, and two caches materialised differently are not
comparable (§5.7); an option would make an incomparable pair easy to produce
and hard to notice. Fixing it is also the faster choice, since a model that
already carries every axis measures no axis increments (§3.1).

A cache is invalidated by any change to what the model emits — which, by §5.5,
is exactly the condition that advances `model_version`. The first such advance
is the one that landed `--cost`: every model gained a top-level block, the
shape moved, and `model_version` became `"2"`. Caches produced under `"1"` are
invalid as data from that point, not merely differently identified. Regeneration is
therefore batched with the change that causes it rather than performed per
change, and the header is what proves which side of the change a given file is
on.

**A digest mismatch identifies a different build; it does not by itself
invalidate a cache.** The digest is taken over the acceptance block, and that
block gains rows whenever a figure acquires an executable derivation — as it
did at ADR 0036, with `pss.py` untouched. A cache whose digest no longer equals
the current build's is stale as an *identification* and still sound as *data*
while `model_version` and `model_shape` agree. The pairing is deliberate: the
digest is the finer instrument and answers "which build", `model_version`
answers "is this comparable", and reading the first as though it answered the
second would retire caches that nothing had changed.

---

## 15. Requirements derived from observed failure

### 15.1 Why this section exists

The requirements elsewhere in this document were settled by reasoning about
what a caller would need, and by asking callers. Both methods share a limit:
**a caller cannot report the failure it did not notice.** If it had noticed, the
failure would not have happened. Asking produces the complement of the failure
set, however well the question is put.

This section is derived the other way. Each requirement below is traced to a
defect measured in the reference target's committed history — a change that a
language model made, believed correct, and left in place. The measurements are
reproducible from the repository with this tool.

That method is also the tool's own: §1.1 declines to establish safety before a
change and reports what moved afterwards. Deriving the tool's requirements from
observed damage rather than from a prediction of it applies the same rule to
the specification.

### 15.2 The measured defects

Across 230 committed states of the reference target, nine functions are defined
at head, have no static caller, and are named by no string literal anywhere in
the file — unreachable as far as this model can see. Four of them were reached
at an earlier state and lost their last caller in an identifiable commit; **two
of those four were defined and orphaned within two days, one of them on the
same day** (`Set-WimImageCreationTimeXml`, 0-day gap; `Restore-BootWimFromSourceIso`,
1-day gap). The other two flipped much later — 39 and 73 days after
definition (`Get-PatchKbId`, `Install-WindowsAdkFallback`) — so proximity in
time is not a property of all four, only of these two. The commit that orphaned
a recovery-path function announces "verified checkpointed resume transactions"
in its subject.

*(This paragraph was corrected on 2026-08-16 against a full 230-generation
re-survey run with `pss.py` itself (via the ADR 0033 corpus manager),
replacing an earlier figure of "three... within two days" that had been
measured with the throwaway instruments retired at ADR 0033 — one of which
carried a hard-coded absolute path and one of which silently dropped
unreadable generations. The corrected count is two, not three; the
`Restore-BootWimFromSourceIso` recovery-path finding and its commit subject are
unaffected and reproduce exactly.)*

Five more are vendored canonical helpers. One of them is vendored into six
consumers and called by none of them, while its paired opposite is called by
five: the pair is half-wired everywhere it exists.

### 15.3 What the tool could and could not show

| | |
|---|---|
| Identifying the nine | **Derivable today** from the default model, by joining `closures`, `soft_references` and `string_interpolation_references`. |
| Separating them from benign orphans | **Not shown.** Head carries 26 orphans; 17 are dispatched by name through a phase table and are correct. All 26 are emitted under one code, so four defects sit inside a population of seventeen non-defects. |
| Saying when the orphaning happened | **Not available.** The signal is a transition, and the standing count is dominated by the benign majority. |
| Detecting a call to a function that no longer exists | **Structurally impossible.** An edge is recorded only where the invoked name resolves to a defined function; a name that resolves to nothing is counted and discarded, so the model has no place to put it. |
| Asserting unreachability | **Out of reach, and must stay so.** Head carries 38 unresolved sites, and that count has risen monotonically. The strongest available statement is *unreachable within what was resolved, against this many unresolved sites*. |

### 15.4 The requirements

**F1 — an orphan's kind is a fact, not an inference (RESOLVED, P22).** A
function with no static caller that is named by a string literal, and one that
is named nowhere, are different observations and must be distinguishable
without the consumer joining collections. Resolved into the record rather than
a new code: every `PSS4003` record carries `named_by_literal` (§4.4), set from
the existing `PSS3001` soft-reference population and nothing else. **A
comment-only mention does not count.** `pss.py`'s tokenizer strips comments
before any fact is derived (§2), so a name that appears only in a comment was
never eligible to produce a `PSS3001` record and therefore does not set
`named_by_literal`. This was checked against the reference target directly:
three of the nine measured unreachable functions (`Get-SevenZipPath`,
`Install-SevenZipFallback`, `Invoke-CleanupDirectories`) have their name
appear in a comment elsewhere in the file despite having no live reference of
any kind, and each correctly carries no `named_by_literal` key. A comment
documents intent; it is not evidence of a call path, and treating it as one
would make `named_by_literal` an inference rather than a fact under §1.3.

**F2 — an invoked name that resolves to nothing must be emitted (RESOLVED,
P23).** The count of named commands is kept and the names are not by default.
Resolved as `PSS2009` (§4.2): a per-name aggregate (`name`, `sites`, `owners`)
is always present — whole collection, not filtered by any naming-convention
guess, because this tool has no structural basis for telling a deleted local
function from a cmdlet or an external executable (§1.3 forbids guessing that
from a threshold). Restoring per-site positions, which is what makes a call to
a deleted function locatable rather than merely countable, is the
`command-sites` axis (§5.6): measured at 31.5% of the base model against the
aggregate's 5.3%, the same cost class that motivated `local-sites` originally,
so the two axes now follow one pattern rather than each being decided
separately. Measured against the full 230-generation reference corpus at the
time of resolution: 93 distinct names over 2,796 sites (corrects an earlier
estimate of 2,798, carried in this section's own provisional note without a
fresh measurement).

**F3 — orphaning is a transition and belongs in `compare` (RESOLVED, P24).**
*Had callers, now has none* is the fact that would have caught all four
measured defects at the moment they were introduced. A standing orphan count
would not have. Resolved as `PSS8008` (§4.7): a `PSS4003` presence change
between two models, carrying direction (gained/lost) and both models'
`named_by_literal` values, but **no commit identity** — `pss.py` stays
git-agnostic (§2.1) and reports only what the two given models show. A caller
that wants per-commit resolution runs `compare` across adjacent generations; a
function whose reachability flips more than once then simply produces more
than one `PSS8008` fact, in sequence, which is not a special case. This was
checked against all 230 committed generations of the reference target: of the
nine measured unreachable functions, two never had a static caller in the
observed history, two flip more than once (gain a caller shortly after
definition, then lose it again later), and four flip exactly once and stay
orphaned — each of those four is one `PSS8008` fact away from being caught the
moment it happened.

**F4 — a reachability statement carries its own bound (RESOLVED, P25).** Any
fact asserting that nothing reaches a symbol is emitted together with the count
of unresolved sites in the same survey, so that a consumer cannot read
*unreachable* where the model can only support *not reached by anything
resolved*. Resolved as **once per model**: a new top-level `counters` entry,
`unresolved_named_command_sites`, alongside the existing entries such as
`commands_named` (§2.4). It is not repeated on every `PSS4003` record, because
the bound is a property of the survey as a whole and not of any one function —
a caller reading a `PSS4003` record already has the same model's `counters`
alongside it. Carrying it per record would restate the same number up to 26
times on the reference target for no additional information.

### 15.5 What this method cannot establish

The defects above are **damage that was found**, not damage that was reported.
No test failure is attached to any of them; they are unreachable code, and
unreachable code does not fail. A defect that broke behaviour rather than
leaving a remnant would not appear by this measurement, and none of the four is
evidence that any test ever failed.

The corpus is also one script by one line of authorship. Four defects in 230
states is a rate for this corpus and not for PowerShell refactoring in general.

---

## Appendix A — Fact catalogue index

| Block | Category | Mode |
|---|---|---|
| `PSS1xxx` | Definition inventory | survey |
| `PSS2xxx` | Reference and binding | survey |
| `PSS3xxx` | Soft reference | survey |
| `PSS4xxx` | Impact closure and recursion groups | survey |
| `PSS5xxx` | *(reserved)* | — |
| `PSS6xxx` | Presence transition (functions and script variables) | compare |
| `PSS7xxx` | Attribute change and classification | compare |
| `PSS8xxx` | Graph, closure and rename-omission change | compare |
| `PSS9xxx` | Analysis limitation and self-diagnostic | both |

---

## Appendix B — Acceptance baselines and corpus statistics

**Measurement basis (pinned, ADR 0034).** Every figure below is measured
against one immutable generation of the reference target, retrieved by blob
rather than by path:

| Field | Value |
|---|---|
| Corpus entry | `corpus/0002-projects-powershell-update-windows-server-iso.json` |
| Generation index | `156` (the entry's last generation) |
| Commit | `aade522845fa351cf4bb0f7f81fe72d79eb9bee4` |
| Blob | `f2b5e6a59b4d7fde688958a19bbfcdb6ce247c01` |
| Path at that commit | `projects/powershell-update-windows-server-iso/Update-WindowsServerIso.ps1` |

The basis is **not** "the head of `main`". The reference target is a
maintenance-stream artefact (ADR 0029) that advances independently of this
tool; a figure measured against a branch head describes a state that stops
existing without notice, and a gate anchored to one would turn ordinary
maintenance work into a governance failure. A pinned blob has neither problem,
which is what allows §13.1's baseline gate to run in the standing battery at
all. Retrieve per §14.2; ground truth is the in-box PowerShell parser.

Re-pinning to a newer generation is an explicit adjudicated act with
re-measurement attached, never an incidental edit.

**This appendix holds two kinds of number and they must not be confused.**

| Part | Contents | Role |
|---|---|---|
| **B-I** | Values `pss.py` must reproduce | Asserted by the §13.1 baseline gate |
| **B-II** | Values that characterise the corpus | Re-measured, never asserted against `pss.py` |

**Every figure carries one of these two labels.** An unclassified figure is
compared against by whoever reads it with no rule saying whether the comparison
is meaningful — which is exactly how the declaration-form table (B.4) came to
be measured against a counter that was never its definition.

The distinction exists because some figures are defined by an **AST predicate**
and a conforming implementation cannot reach them. `Command invocations
(statically named) 5,048` is `CommandAst` whose first element is a
`StringConstantExpressionAst`; §2.3 confines `pwsh` to test time, so `pss.py`
has no AST at run time and derives 5,046 from tokens. Asserting an
unreachable value would break §1.3 in the opposite direction — the fact test
requires that every conforming implementation *can* produce the value.

**B-I (acceptance).** Functions, nested definitions, duplicate names, call
edges, closure membership, functions with no static caller, mutual-recursion
groups, variable references, `PSS2002`, `PSS2003`, `PSS2004`, `PSS2005`,
`PSS2006`, `PSS2007`, `PSS2008`, `PSS9004`, `PSS3001`, `PSS3002`, dynamic call
sites, and the `counters` block. Every asserted figure is carried in machine
form in **B.8**, which is the single master the gate reads.

`PSS2002` and `PSS2003` are B-I as of ADR 0034. They were previously absent
from both lists, and that absence was load-bearing: two extractor defects
confined to function scope — the unreachable compound-assignment operators and
the dynamic-member-name left-hand side (both §12.2) — misclassified thirteen
sites while every gate stayed green, because no acceptance figure covered the
declaration side at all.

**B-II (corpus statistics).** Statically named command invocations; the
string-constant population with its breakdown; and the **declaration-form
table (B.4) in its entirety**. B.4's rows are defined by AST predicates —
`AssignmentStatementAst` and its left-hand-side types, `ForEachStatementAst`,
`ParameterAst` — which §2.3 puts out of `pss.py`'s reach at run time. They
characterise the corpus and are re-measured with `pwsh`; they are never
asserted against `pss.py`. In particular `counters.assignments` is **not** B.4's
"Assignment statements" row and must not be compared against it (see B.6).

The string-constant total of 27,626 includes 9,614 member names, which §4.3
excludes from soft-reference matching; the population `pss.py` reconstructs
from tokens is therefore about 18,000 and is not asserted.

The §13.1 baseline gate asserts **B-I only**.

### B.1 Structural inventory

| Quantity | Reference value |
|---|---:|
| Parse errors | 0 |
| Function definitions | 480 |
| Nested function definitions | 1 |
| Duplicate function names | 0 |
| Command invocations | 5,074 |
| — statically named | 5,048 |
| — dynamic | 26 |
| `Invoke-Expression` occurrences | 0 |
| Variable references (unique AST nodes) | 24,317 |
| Distinct variable names (case-insensitive) | 2,635 |
| Names with mixed casing | 0 |
| String literals | 27,626 |

### B.2 Call graph

| Quantity | Reference value |
|---|---:|
| Intra-script call edges | 1,247 (function-to-function only; the `edges` collection holds 1,281 records, of which 34 originate at the `<script>` pseudo-node — see §11.1) |
| Closure membership entries (callee-side total) | 5,071 |
| Closure membership entries (caller-side total) | 5,252 (see §11.1: the `<script>` pseudo-node gap, not a symmetry defect) |
| Self-recursive functions | 0 |
| Mutual-recursion groups (`PSS4004`) | 3 |
| Widest transitive callee closure | 175 |
| Widest transitive caller closure | 140 |
| Functions with no static caller (`PSS4003`) | 26 |

### B.3 Variables

| Quantity | Reference value |
|---|---:|
| Local references, total | 20,352 |
| — read, resolved in function (`PSS2003`) | 15,950 |
| — write, declaration site (`PSS2002`) | 4,402 |
| Automatic (`PSS2005`) | 2,075 |
| `$env:`-qualified (`PSS2004`) | 14 |
| Unresolved (`PSS9004`) | 11 |
| References inside expandable strings (`PSS2007`) | 118 |

The local-reference rows are split because `PSS2002` and `PSS2003` are separate
codes as of the declaration-site work; a single "resolved in function" figure
no longer names one quantity. The previous single figure was 20,353 against a
total that measures 20,352 — a discrepancy that had no owner while nothing
re-derived it.

**`PSS2005` was recorded as 2,004 and is 2,075.** The correction is not a
tuning: the reference parser, given the same 53-name automatic set, reports
2,075 with an identical per-name distribution and an identical total variable
reference count. 2,004 is reproducible by no committed revision of this tool
against any of the 230 committed generations of the target — it is an orphan
from an uncommitted instrument (ADR 0034). A third figure, 1,336, produced by a
second throwaway measurement, is short by exactly the number of `$_`
references.

**The `[DERIVATION OWED]` figures are resolved (ADR 0036).** Each was recorded
under a label that did not determine a query, against a state that was not
recorded. Both halves were measured before this text was written: every one of
the six committed revisions of `pss.py`, run against the pinned blob, returns
the same values, so no figure below moved because the tool moved. What moved
was the question being asked and the file it was asked about.

| Recorded | Disposition | Derivation now stated |
|---|---|---|
| `$script:`-qualified (`PSS2004`) 1,381 | **re-derived exactly** | script-qualified reference records whose owner is a function — `script_qualified_refs_in_function`. The label admitted three readings (1,865 records, 1,812 `PSS2004`, 1,381 inside functions) and the recorded figure was the third |
| usage-map population 156 | **re-derived exactly** | `PSS2008` record count, already asserted in B.8 |
| `PSS9004` sub-counts, 5 functions / 4 names | **re-derived exactly** | distinct owners of the `PSS9004` records, and distinct variable names named in their `detail` |
| distinct usage signatures 115 | **re-stamped to 123** (a disposition record of the ADR 0036 event; the figure moves with the model — 120 as of `model_version` 3, held by B.8, after the D10 usage-map order-independence fix) | distinct (writer set, reader set) pairs over the usage map. 115 is reproduced at generations 104-110 of entry `0002` — a different state, not a different derivation |
| `PSS2007` 83 strings | **re-stamped to 84** | distinct source lines carrying an interpolated reference (§12.4). 83 is reproduced at generations 88-111 of entry `0002` |
| distinct script names 155, and its correction to 197 | **withdrawn** | reproduced by no generation and no revision. Both are orphans of instruments that no longer exist, in the manner of `PSS2005`'s 2,004 (ADR 0034). The measured figure is 198, asserted as `script_qualified_names` |
| references outside any function 555 | **withdrawn; replaced by two figures** | the label covers two questions with different answers. `script_qualified_refs_at_script_level` (484, axis-invariant) is the script-scope share; `references_outside_functions` (485 default / 556 with `local-sites`) is the all-scopes total, and is the one asserted figure that is **not** axis-invariant, so it states its materialisation. 555 is reproduced by neither, at any generation |

That the recorded figures point at generations 88-111, 104-110 and 132-156 is
the finding, not an aside: they were never a snapshot of one artefact. This is
the moving-target defect ADR 0034 named for acceptance figures, surviving in
B.3 because the rule reached the basis and not the derivation.

### B.4 Declaration forms

| Form | Reference value |
|---|---:|
| Assignment statements | 5,114 |
| — left-hand side is a variable | 4,578 |
| — left-hand side is a type conversion | 41 |
| — left-hand side is a member expression (**excluded**) | 407 |
| — left-hand side is an index expression (**excluded**) | 88 |
| `foreach` statements | 356 |
| Parameters | 948 |
| `Set-Variable` / `New-Variable` family | 3 |
| `-OutVariable` family | 0 |
| Splatted references | 14 |
| Brace-quoted names `${...}` | 4 |
| `$using:` expressions | 0 |

### B.5 Soft references

| Quantity | Reference value |
|---|---:|
| Function-name literals, non-invocation (`PSS3001`) | 49, across 28 functions |
| Literals matching any variable name (**not** the rule) | 8,821 |
| Literals matching a script-scope name (`PSS3002`) | **104** (quoted 15 / bareword 89); 146 before member names are excluded per §4.3 |

### B.6 Hash behaviour

| Quantity | Reference value |
|---|---:|
| Distinct `hash_full` over 480 functions | 480 |
| Distinct `hash_body` over 480 functions | 480 |
| Distinct name-excluded string-stripped hashes (**rejected variant**) | 471 |

### B.7 Delta baselines (B-I)

**The previous content of this appendix is withdrawn, not restamped (ADR
0036).** It recorded ten aggregate figures under the title "Delta behaviour
over 12 consecutive historical states" — 2,607 same-name comparisons splitting
2,395 / 13 / 9 / 190, a `PSS7005` population of 1,213 and twelve
`dependency-only` functions — with no record of which twelve states. Measured
with the shipped comparator over every consecutive pair of committed
generations (229 pairs, both corpus entries), no window of 8 to 16 pairs
reproduces the population: the closest reaches 2,603, and every near window
carries **zero** `comment-or-whitespace-only` and **zero**
`string-literal-only` classifications where the table claimed 13 and 9. The
figures are outputs of an uncommitted instrument over an unrecorded window —
the defect ADR 0036 withdrew three B.3 figures for, met on the comparator's
side.

What replaces them is pinned the way every other acceptance figure is pinned
(ADR 0034): to named blobs, re-derived by the §13.1 gate, with the basis
recorded beside the values in the machine block below.

**The adjudicated pair** is generations 93 → 94 of entry `0002`. It is the
pair consumer review was performed on (§3.2), and it exercises the comparator
rather than sampling it: all eighteen codes examine a non-empty population,
sixteen emit, and `PSS8008` emits exactly one record naming
`function/Restore-BootWimFromSourceIso` — the fact a reviewer identified as
the most review-worthy in the change and found carried by neither candidate
shape. The same pair is measured under both verbs, so the fifteen shared
tallies state as re-derived values what §12.7 states as structure: `trace` is
`compare` plus the rule layer, and nothing else.

**The independent pair** is the one corpus history cannot supply: every pair
drawn from an entry stands in exactly the relation `trace` asserts (§4.9), so
the `compare`-without-succession case needs two scripts with no shared
history. The two fixture scripts written for consumer review serve, embedded
in `test_pss.py` (the gate, not the tool — §2.6). The block records the sha256
of each script exactly as the emitted document's own `source.sha256` states
it, so the embedded text cannot drift from what the block claims was measured.
`Publish-ReleaseArtifacts` deliberately carries a §10.6 [F4] instance
(`foreach ($pkg in Get-StagedArtifact)` — a real call in a position the
pre-D10 §10.6 did not treat as command position), and its figures **did move
when [F4] was adjudicated**: the pin reddened at the [F4] commit (25 -> 24
records, the deliberate instance becoming its edge) and was restamped at the
arc's end — the red-then-restamp path that pinning before the extractor arc
existed to produce, observed rather than predicted.

Materialisation is `default` throughout. The tallies measured equal over
default and all-axes inputs on the adjudicated pair; the pinned figure states
the materialisation it was measured at rather than claiming that invariance,
per the rule §13.2 records for figures that could depend on it.

```json pss-delta-baseline
{
  "compare_pair": {
    "records": 170,
    "surveyed": {
      "PSS6001": {
        "emitted": 1,
        "equal": 0,
        "examined": 1
      },
      "PSS6002": {
        "emitted": 21,
        "equal": 0,
        "examined": 21
      },
      "PSS6003": {
        "emitted": 0,
        "equal": 505,
        "examined": 505
      },
      "PSS7001": {
        "emitted": 6,
        "equal": 359,
        "examined": 365
      },
      "PSS7002": {
        "emitted": 2,
        "equal": 363,
        "examined": 365
      },
      "PSS7003": {
        "emitted": 6,
        "equal": 359,
        "examined": 365
      },
      "PSS7004": {
        "emitted": 10,
        "equal": 355,
        "examined": 365
      },
      "PSS7005": {
        "emitted": 8,
        "equal": 357,
        "examined": 365
      },
      "PSS7006": {
        "emitted": 8,
        "equal": 357,
        "examined": 365
      },
      "PSS7007": {
        "emitted": 14,
        "equal": 126,
        "examined": 140
      },
      "PSS8001": {
        "emitted": 83,
        "equal": 0,
        "examined": 83
      },
      "PSS8002": {
        "emitted": 1,
        "equal": 0,
        "examined": 1
      },
      "PSS8003": {
        "emitted": 8,
        "equal": 357,
        "examined": 365
      },
      "PSS8004": {
        "emitted": 1,
        "equal": 33,
        "examined": 34
      },
      "PSS8008": {
        "emitted": 1,
        "equal": 384,
        "examined": 385
      }
    }
  },
  "independent_pair": {
    "basis": {
      "a_sha256": "533763a4d68284cf9769df6811f706fe89eec6641e70dc7dea2d48583d84af36",
      "b_sha256": "a71f74e32f46ba3dcdea94c014b7da8ea6afc4fed06b063df6f1b6074170efad",
      "materialisation": "default"
    },
    "records": 24,
    "source_path_differs": true,
    "surveyed": {
      "PSS6001": {
        "emitted": 7,
        "equal": 0,
        "examined": 7
      },
      "PSS6002": {
        "emitted": 7,
        "equal": 0,
        "examined": 7
      },
      "PSS6003": {
        "emitted": 0,
        "equal": 0,
        "examined": 0
      },
      "PSS7001": {
        "emitted": 0,
        "equal": 0,
        "examined": 0
      },
      "PSS7002": {
        "emitted": 0,
        "equal": 0,
        "examined": 0
      },
      "PSS7003": {
        "emitted": 0,
        "equal": 0,
        "examined": 0
      },
      "PSS7004": {
        "emitted": 0,
        "equal": 0,
        "examined": 0
      },
      "PSS7005": {
        "emitted": 0,
        "equal": 0,
        "examined": 0
      },
      "PSS7006": {
        "emitted": 0,
        "equal": 0,
        "examined": 0
      },
      "PSS7007": {
        "emitted": 0,
        "equal": 0,
        "examined": 0
      },
      "PSS8001": {
        "emitted": 5,
        "equal": 0,
        "examined": 5
      },
      "PSS8002": {
        "emitted": 5,
        "equal": 0,
        "examined": 5
      },
      "PSS8003": {
        "emitted": 0,
        "equal": 0,
        "examined": 0
      },
      "PSS8004": {
        "emitted": 0,
        "equal": 0,
        "examined": 0
      },
      "PSS8008": {
        "emitted": 0,
        "equal": 9,
        "examined": 9
      }
    }
  },
  "trace_pair": {
    "basis": {
      "a": {
        "blob": "12c86874159ba0641c90d67bcc0a4c19037bf27c",
        "gen_index": 93,
        "rev": "f32a761015dbd200ffca785390bfbb107f6594e8"
      },
      "b": {
        "blob": "63782697691f607bb0d0d1e58451afe08464e6e5",
        "gen_index": 94,
        "rev": "e1113e5e36b7b08cfab75061022cb7a55d288bc5"
      },
      "corpus_entry": "0002-projects-powershell-update-windows-server-iso.json",
      "materialisation": "default"
    },
    "pss7001_classifications": {
      "code-changed": 6
    },
    "pss8008_subjects": [
      "function/Restore-BootWimFromSourceIso"
    ],
    "records": 173,
    "surveyed": {
      "PSS6001": {
        "emitted": 1,
        "equal": 0,
        "examined": 1
      },
      "PSS6002": {
        "emitted": 21,
        "equal": 0,
        "examined": 21
      },
      "PSS6003": {
        "emitted": 0,
        "equal": 505,
        "examined": 505
      },
      "PSS7001": {
        "emitted": 6,
        "equal": 359,
        "examined": 365
      },
      "PSS7002": {
        "emitted": 2,
        "equal": 363,
        "examined": 365
      },
      "PSS7003": {
        "emitted": 6,
        "equal": 359,
        "examined": 365
      },
      "PSS7004": {
        "emitted": 10,
        "equal": 355,
        "examined": 365
      },
      "PSS7005": {
        "emitted": 8,
        "equal": 357,
        "examined": 365
      },
      "PSS7006": {
        "emitted": 8,
        "equal": 357,
        "examined": 365
      },
      "PSS7007": {
        "emitted": 14,
        "equal": 126,
        "examined": 140
      },
      "PSS8001": {
        "emitted": 83,
        "equal": 0,
        "examined": 83
      },
      "PSS8002": {
        "emitted": 1,
        "equal": 0,
        "examined": 1
      },
      "PSS8003": {
        "emitted": 8,
        "equal": 357,
        "examined": 365
      },
      "PSS8004": {
        "emitted": 1,
        "equal": 33,
        "examined": 34
      },
      "PSS8005": {
        "emitted": 0,
        "equal": 1,
        "examined": 1
      },
      "PSS8006": {
        "emitted": 2,
        "equal": 138,
        "examined": 140
      },
      "PSS8007": {
        "emitted": 1,
        "equal": 140,
        "examined": 141
      },
      "PSS8008": {
        "emitted": 1,
        "equal": 384,
        "examined": 385
      }
    }
  }
}
```

### B.8 Machine baseline (B-I)

The block below is **the single master** of every asserted figure. `test_pss.py`
reads it from this document and re-derives each value from the pinned blob; it
holds no expected numbers of its own. There is therefore no second copy to
drift, and a figure cannot be edited here without the gate re-deriving it on the
next run (ADR 0034).

`model_shape` is the fingerprint of the emitted model's key-path set — every
path that occurs, arrays collapsed to `[]`, sorted, newline-joined, `sha256`
truncated to 16 hex (the ADR 0015 width). It is taken from the pinned reference
target rather than from a synthetic fixture, because a fixture fingerprints only
the fields it happens to reach. Its purpose is not to fix the shape but to make
a change of shape a gate failure: when it moves, `model_version` advances per
§5.5 and the advance is recorded at that moment. It had not been — the version
stayed `"1"` across four shape changes, and nothing surfaced that until the
shapes were compared by hand.

A shape figure states its basis, exactly as an acceptance figure does (ADR
0035). Measured against the pinned blob, the destructive step of those four
removes **eleven** key paths, of which two are restored later under the
`closure-sets` axis, leaving **nine** unrecoverable under any axis; the same
code change measured against an early generation (entry `0001`, blob
`7783700a`) removes **thirteen**, because two of the paths are optional fields a
smaller script never populates. A previously recorded figure of ten is
reproduced by neither basis and is withdrawn. This is not a detail about one
number: a key-path count is data-dependent in the same way an acceptance figure
is, so a bare count is unfalsifiable in the same way.

```json pss-baseline
{
 "basis": {
  "blob": "f2b5e6a59b4d7fde688958a19bbfcdb6ce247c01",
  "corpus_entry": "0002-projects-powershell-update-windows-server-iso.json",
  "gen_index": 156,
  "rev": "aade522845fa351cf4bb0f7f81fe72d79eb9bee4"
 },
 "closures": {
  "callee_side_total": 5071,
  "caller_side_total": 5252,
  "widest_callee": 175,
  "widest_caller": 140
 },
 "counters": {
  "assignments": 4757,
  "commands_dynamic": 26,
  "commands_named": 5048,
  "expandable_strings": 172,
  "interpolation_refs": 118,
  "string_literals_bareword": 10027,
  "string_literals_quoted": 8010,
  "unresolved_named_command_sites": 2798,
  "variable_refs": 24317
 },
 "edges": {
  "from_script": 34,
  "function_to_function": 1247,
  "records": 1281
 },
 "facts": {
  "closures.PSS4001": 480,
  "closures.PSS4002": 480,
  "symbols.PSS1001": 480,
  "symbols.PSS1002": 480,
  "symbols.PSS1003": 480,
  "symbols.PSS1004": 1
 },
 "limitations": {
  "PSS9002": 26,
  "PSS9003": 1,
  "PSS9004": 11,
  "PSS9004_functions": 5,
  "PSS9004_names": 4,
  "PSS9007": 0
 },
 "local_variables": {
  "PSS2002": 5534,
  "PSS2003": 14818,
  "PSS2005": 2075,
  "aggregate_records": 465
 },
 "model_shape": {
  "all-axes": "4c8c4ccaeb6824a4",
  "default": "3a513c698491cbe3"
 },
 "references_outside_functions": {
  "all-axes": 556,
  "default": 485
 },
 "script_variables": {
  "PSS2004": 1792,
  "PSS2004_env": 14,
  "PSS2004_script": 1778,
  "PSS2006": 87,
  "PSS2008": 156,
  "script_qualified_names": 198,
  "script_qualified_refs": 1865,
  "script_qualified_refs_at_script_level": 484,
  "script_qualified_refs_in_function": 1381,
  "usage_signatures": 120
 },
 "soft_references": {
  "PSS3001": 49,
  "PSS3002": 104
 },
 "string_interpolation_references": {
  "distinct_source_lines": 84,
  "records": 118
 },
 "symbols": {
  "duplicate_names": 0,
  "nested": 1,
  "total": 480
 },
 "unresolved_named_commands": {
  "aggregate_records": 93,
  "names_sha256_16": "f9837b486282c11e"
 }
}
```

---

## Appendix C — Adjudicated decision record

Decisions taken by the repository owner during the design session of
2026-08-15. Each is normative; reopening one requires an explicit decision, not
a reinterpretation.

| Ref | Decision |
|---|---|
| D1 | `pss.py` is governance-neutral (§1.5). It does not interpret markers, and a change to the governance model requires no change to the tool. |
| D3 | Accepted extension is `.ps1` only. |
| D4 | Exit codes are `0` and `2`; the exit code never encodes a verdict (§9). |
| D5 | Three hashes: `hash_full` (shared contract, verbatim copy), `hash_body` (name excluded, **string contents retained**), `hash_raw` (§10). |
| D6 | Nested scope uses asymmetric conventions: hashing includes the nested body, reference attribution does not (§10.8). |
| D7 | `survey` enumerates impact sites with locations but emits no work list and no instruction. |
| D8 | Initial `canonical_version` is `0.1.0`, promoted after the tool has been exercised on a real refactoring. |
| D9 | Symbol identifier grammar per §5.2; ordinal disambiguation only on duplicate definition, with `PSS9007` declaring its instability. |
| D10 | `compare` does not refuse models from different scripts; it emits the `source.path` difference as a fact (§5.5). |
| D11 | Test data is obtained from the repository's commit history; the acquisition procedure is documented rather than the data being stored (§14). |
| D11a | Degradation is three-tiered; expected **aggregates** are committed, not expected models (§14.3). |
| D12 | Development is anchored on the reference target first; extension to further single-script projects follows. |
| D13 | The graph is a flat edge list; closures are derived; mutual-recursion groups are emitted (§11). |
| D14 | Set comparisons carry the symmetric difference and state equality explicitly (§4.6). |
| D15 | The combined classification is emitted as a fact with neutral value names; review priority is not assigned (§11.4). |
| D16 | The model is tiered by blast radius; per-site detail exactly where influence crosses a function boundary (§5.3). |
| D18 | Assignment left-hand sides are classified four ways; member and index left-hand sides are references, not declarations (§12.2). |
| D19 | References inside expandable strings are an explicit fact class (§12.4). |
| D20 | Variable soft references are scoped to script-scope names (§12.5). |
| D21 | Identity comparison is case-insensitive; a casing-only change is not a rename (§10.7). |
| D22 | The variable identity anchor is the usage map — writer set, reader set and counts (§12.3). |
| — | Rename-omission detection is the three rules of §12.7, adjudicated as the primary requirement of the tool. |

---

## Appendix D — Known pitfalls and lessons learned

### D.1 Scope modifiers are not exposed by `DriveName`

Scope modifiers are exposed by `VariablePath.IsScript` / `IsGlobal` / `IsLocal`
/ `IsPrivate`. They are **not** exposed by `DriveName`, which is populated only
for drive-qualified paths such as `$env:`. Testing `DriveName` alone silently
reports zero scope-qualified variables in a script that has 1,381 of them. This
error was made and corrected during the design investigation and is recorded so
that a conforming implementation does not repeat it.

### D.2 Regular expressions cannot enumerate function definitions

A line-anchored regular expression for `function <name>` counts 482 definitions
in the reference target, where the true figure is 480. The two extra matches are
prose inside comment blocks that happen to begin a line with the word
`function`:

```
        function therefore treats KbId + OS + package role as the stable key.
        function so they cannot diverge.
```

Both appear in the corpus as spurious rename events — one as a function named
`therefore` being deleted, one as a function named `so` being added. The
regression suite carries both as explicit trap cases.

### D.3 A hash is not sufficient to identify a rename

Renames performed in practice rarely change only a name. In the reference
corpus, a rename of a logging helper simultaneously changed the parameter name
and dropped a type annotation, and a twelve-function renaming wave also
rewrote the callee references inside the renamed functions' bodies, so only six
of the twelve matched by `hash_body`. Substituting the six learned pairs
resolved two more; the remaining four had further body changes.

The lesson is structural, not incidental: `hash_body` identifies the
*body-untouched* rename exhaustively, and the callee-set and caller-set facts
supply the evidence for the rest. Emitting them side by side is the design;
concluding from either alone is the defect.

### D.4 A one-to-many split is not decidable from a hash

A helper split into two functions produces one removal and two additions with
no matching `hash_body`. The corpus contains such a case. `pss.py` emits the
presence transitions and the callee-set facts and draws no conclusion.

---

### D.5 `VariablePath.UserPath` retains the scope prefix

`VariablePath.UserPath` is **not** the bare variable name. For `$Script:Foo` it
returns `Script:Foo`, prefix included. Any comparison against a string literal,
a usage-map key, or another name list must lower-case **and strip a leading
scope prefix** first.

Omitting the strip is silent: it produces zero matches rather than an error. The
S1 session hit this while checking `PSS3002` and concluded from the empty result
that the baseline of 146 was unreproducible — the baseline was correct and the
measurement was wrong. This is the same failure shape as D.1: an AST property
that looks like the value you want and is not.

---

## Appendix E — Open items

| Ref | Item |
|---|---|
| §3 | Whether a fact-code filter is warranted, given that JSON output is trivially filtered downstream. Note that `--include` is **not** available as a name for it: a fact-code filter selects among facts already produced, whereas `--axes` (§5.6) decides what is produced at all, and one flag must not read as the other |
| §7 | Whether `--self-check` should mechanically verify the `psa.py` boundary against that tool's compiled rule list, rather than relying on the table staying current by hand |
| §11.3 | Whether the unobserved `direct-only-change` cell occurs in a wider corpus |
| §12.3 | Whether the usage map's discriminating power should be raised by including per-function read/write counts in the signature |
| §14 | Whether the design investigation's oracle harness may itself become a survey target once the tool is mature; circular while the tool depends on that harness for its own correctness |
| §5.6 | Whether a caller without an execution environment exists among this tool's consumers. The axes optimise total size, which binds only on such a caller; every consumer observed so far writes the model to a file and queries it. External review cannot settle this, because a respondent that could answer it is by definition one that could not have completed the review |
| §6.1 | Whether the human layer earns its place. No human consumer has been asked, and the machine consumers who were asked are the wrong population to ask |

---

## Appendix F — Provisional revisions pending review

Revisions made by the implementation session and not yet confirmed. Each has an
inline `[PROVISIONAL Pnn]` block at the point of change; `--self-check` verifies
that this index and those markers agree in both directions, exiting non-zero on
a mismatch and merely reporting a pending count.

**Basis** is one of **measured** (settled against the reference parser),
**design-choice** (a judgement), or **open** (undecided).

| ID | Section | Basis | Review question |
|---|---|---|---|

No provisional revisions are outstanding. All were resolved on 2026-08-16
(P22, P24, P25) and 2026-08-17 (P20, P21, P23); see the paragraphs below and
the inline resolution notes at each point of change.

**P22, P24 and P25 were resolved on 2026-08-16**, against a full 230-generation
re-survey of the reference target (both corpus entries, `pss.py` run directly —
not the throwaway instruments retired at ADR 0033), and their markers removed.

- **P22** — the distinction lands **in the record**, not a new code: `PSS4003`
  gains `named_by_literal` (§4.4), sourced from the existing `PSS3001`
  population. A comment-only mention does **not** count, because `pss.py`
  strips comments before any fact is derived and a comment is not evidence of
  a call path. Checked directly: three of the nine measured unreachable
  functions are named in a comment elsewhere in the file and are correctly
  carrying no `named_by_literal` key under this rule.
- **P24** — resolved as `PSS8008` (§4.7), carrying direction (gained/lost) and
  no commit identity — `pss.py` stays git-agnostic (§2.1); a caller wanting
  commit resolution runs `compare` across adjacent generations, and a function
  that flips more than once simply produces more than one `PSS8008` fact. The
  same re-survey found flapping in the reference target itself: two of the
  nine measured functions gain and lose their last caller more than once
  before settling.
- **P25** — resolved as **once per model**: a new `counters` entry,
  `unresolved_named_command_sites`, alongside the existing entries (§2.4), not
  repeated on every `PSS4003` record.

The same re-survey also corrected §15.2's "three... within two days" figure to
two (§15.2 carries the detail and the provenance note).

**P20, P21 and P23 were resolved on 2026-08-17**, against the same
230-generation reference corpus, and their markers removed.

- **P20** — shape is `slice <model.json>` (§5.7): a subcommand over an
  existing model, not a `survey --scope` flag, because the model must remain
  sliceable after the source no longer exists — the same fact P21 required of
  axis normalisation. `slice` takes `--scope` and/or `--axes`.
- **P21** — folded into the same `slice` subcommand as P20, not a `compare`
  flag and not a separate operation: both are deterministic reductions of an
  existing model, self-declared via `materialization`. `slice --axes` narrows
  to a subset of what the input already carries; requesting more is refused
  by name.
- **P23** — resolved as `PSS2009` (§4.2), folded into the same
  aggregate/axis-restored-site pattern as `local-sites` (§5.6), once the
  per-site form measured at 31.5% of the base model against the aggregate
  form's 5.3% (revised from an earlier 22.3% draft figure, not reproduced on
  re-measurement) — the same cost class that motivated `local-sites` in the first
  place. Measured against the reference corpus: 93 distinct names over 2,796
  sites (this section's own prior estimate of 2,798 was not re-measured before
  being written down; corrected here per this document's own measurement
  discipline, §15.1).

**P15 through P19 were resolved on 2026-08-16 by external review** and their
markers removed. Six respondents across two model families, all with code
execution, answered a structured pack; the reading rule agreed before the pack
was sent was that agreement within one family is weak because the respondents'
errors correlate, and that cross-family agreement and unanticipated single
objections carry the weight.

- **P15** — the unit is bytes and the constraint was confirmed unanimously
  across families: a token count is consumer-specific and cannot be a fact
  under §1.3. The row closes **amended**, because every respondent asked for the
  same missing thing — per-collection bytes and records rather than a single
  total (§3.1).
- **P16** — both forms, unanimously across families. The separate mode is the
  only one that can inform the request it prices; the embedded block makes a
  stored model self-describing and prices the axes not taken. The
  self-reference in measuring a block that is inside what it measures is closed
  by definition in §3.1.
- **P17** — the command-line half of the descriptor was found sufficient; the
  output half was found absent by every respondent. Closed by requiring a
  schema for every machine output (§3.1).
- **P18** — closed by being answered differently than asked. The question was
  whether a two-name axis vocabulary is too coarse; the finding was that the
  axis is not the unit these callers want at all. Superseded by §5.7 and P20.
- **P19** — no respondent asked for a preset. Closed as specified: none.

Two findings from that review are recorded outside this appendix because they
are defects rather than open questions: §5.6's master-collection list omitted
two collections, and the `closures` collection's three record shapes were
undocumented (§11.1). Both were reported by respondents in both families.

**The population was uniform in a way that bounds every conclusion above.** All
six respondents had an execution environment and all six described the same
workflow: write the model to a file, query it with code, load only matching
records. The finding that selectivity matters more than total size is therefore
established for that kind of caller and for no other. Appendix E carries the
residue.

P14 was resolved on 2026-08-16 and its marker removed. The question — whether
`--detail` was the right switch for closure sets — was answered by replacing the
switch with the axis contract of §5.6, which also supplies the rule that bounds
how many such switches can ever exist.

P01–P13 were reviewed and confirmed on 2026-08-16 and their markers removed.
Three carried amendments, which are folded into the body text: `PSS3001` /
`PSS3002` now exclude member names (§4.3), command position now includes `&&`
and `||` (§10.6), and `--self-check` now distinguishes a pending revision from
an index mismatch (§13).

### F.1 Open items requiring adjudication

None outstanding. §15.5 states what the
observed-failure method does not establish. O1, O2 and O3 were adjudicated on
2026-08-16:

- **O1** — Appendix B is split into B-I (acceptance) and B-II (corpus
  statistics); the §13 differential test asserts B-I only. `commands_named`
  moves to B-II because an AST-predicate value is unreachable for a conforming
  implementation.
- **O2** — §2.4's 0.5 MB estimate was made before §5.3 was settled and never
  re-derived; it is corrected to 0.9 MB compact. Closure records carry counts
  rather than materialised sets, which also repairs a violation of §11.1's
  master/derived rule. Per-site script-variable records are retained: they are
  what answers *where do I edit*.
- **O3** — the `PSS3002` residual is resolved by the member-name exclusion; the
  two occurrences at the same site were both member names and left the
  population entirely. The string-constant and command-invocation residuals are
  B-II statistics and are no longer asserted.
