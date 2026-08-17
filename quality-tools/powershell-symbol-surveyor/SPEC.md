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
[ survey : pss.py ] -> [ modify : project / LLM ] -> [ survey + compare : pss.py ] -> [ adjudicate : the caller ]
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
pss.py compare  <before.json> <after.json> [--format text|json]
pss.py --list-facts
pss.py --self-check
pss.py --version
```

| Option | Applies to | Meaning |
|---|---|---|
| `--out PATH` | `survey`, `slice` | Write the model to PATH. Default: stdout. |
| `--format {text,json}` | `survey`, `slice`, `compare` | Output format. Default `text`. |
| `--axes LIST` | `survey`, `slice` | Comma-separated materialisation axes to restore (`survey`) or narrow to (`slice`), or `all`. Default: none (§5.6). An unrecognised name exits `2`. |
| `--scope ID` | `slice` | Keep only records concerning this symbol identifier, plus incident edges and all limitations (§5.7). An unmatched identifier exits `2`. |
| `--pretty` | `survey`, `slice` | Indent the JSON model. Default is compact (§2.4). |
| `--list-facts` | — | Print the fact catalogue and exit. |
| `--self-check` | — | Verify this SPEC's §4 catalogue, Appendix F provisional index and §5.6 axis vocabulary against the tool's compiled state, and exit (§13). |
| `--version` | — | Print version and exit. |

There is deliberately no `--severity`, no `--enable`, and no suppression
mechanism. Severity does not exist in this tool, and facts are not suppressed —
they are filtered by the caller when the caller has decided what it cares
about.

**Current build status.** `compare` exists as a subcommand and can be invoked,
but this build deliberately refuses to run it: it prints an explanatory
message and exits non-zero rather than emitting an empty or partial
comparison (§2.1; the comparator is Layer 3 and has not been built yet).
`--cost` and `--capabilities`, discussed at length in §3.1 below as normative
design intent, are **not present in this build's argument parser at all** —
passing either exits `2` with argparse's generic "unrecognized arguments"
message, not a designed error. §3.1 should be read as the specification these
two flags must satisfy once built, not as a description of current behaviour.

### 3.1 The caller is expected to be a language model

**Not yet implemented.** Everything below concerning `--cost` and
`--capabilities` is normative design intent, pinned so that a later build has
one target to satisfy rather than being designed at implementation time. It
does not describe this build (§3).

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

**Describing the command line is not enough.** A descriptor that documents how
to invoke the tool but not what comes back leaves a caller able to make a
request and unable to consume the reply. Six external reviewers, across two
model families, each reported the same gap and each recovered the record shapes
by reading sample output — which a caller without samples cannot do, and which
guarantees nothing across versions. The descriptor therefore also carries a
**schema for every machine output**: the record shape of each model collection,
the identifier conventions, the join key for each collection, the delta-record
shape emitted by `compare`, the cost-report shape, and the structured error
payload. Ordering and determinism (§5.4) are stated there too, since a caller
that intends to join or diff two models outside the tool depends on them.

Errors are machine-readable when machine output was requested: with `--format
json`, a usage error emits a JSON object on stderr carrying a stable category,
the rejected value and the valid vocabulary. The exit code stays `2` per §9;
the category distinguishes *correct the command* from *fix the environment*
from *report a defect*, which the exit code alone cannot.

**The caller must be able to price a request before making it.** `--cost`
reports exact byte sizes and record counts **per collection**, plus the
increment each axis would add, in a payload of a few hundred bytes. A single
total tells a caller whether it can afford the request; a per-collection
breakdown tells it what to do when it cannot, which is the decision actually
being made. The report states what it measured (`"format"`) and binds itself to
its input (`source.sha256`), because a size figure that names neither its
serialisation nor its subject is not a fact under §1.3.

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

---

## 4. Fact specifications

This section is normative. Facts are identified by `PSS` plus four digits,
blocked by first digit. Blocks 1-4 are single-state facts emitted by `survey`;
blocks 6-8 are delta facts emitted by `compare`; block 9 is the tool's
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

**`PSS2002` is now emitted, but only for one of its five recognised sources
(§12.2).** An assignment whose left-hand side is a bare local variable
(`role == "write"` in the underlying token scan) now gets a `code:
"PSS2002"` record under `local-sites`, split out from the `PSS2003`
("reference to" the same declaration) records it previously shared a code
with. Measured on the reference target: 4,393 `PSS2002` records, matching
`local_declared` exactly. **The other four §12.2 sources — a `param()` /
inline-function parameter, a `foreach` loop variable, a `Set-Variable` /
`New-Variable` `-Name`, and the `-OutVariable` family — are declarations
`pss.py` already resolves reads against (`_decl_add`), but their call sites
never retain a line/offset, so no `PSS2002` record exists for them yet.**
This is a real, open gap, not an oversight papered over: closing it needs
`_precompute_parameters`, `_record_foreach` and `_record_set_variable` to
each start keeping a site the way the assignment path already does, which is
untried and not scoped here. §13.2's "Emission coverage" row tracks it.

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
| `PSS2009` | A command invocation site whose command name is a literal in command position (§10.6) but does not resolve to any function defined in this file (SPEC 15.4 F2 / P23). Every such name is counted, not filtered — this tool has no structural basis for telling a deleted local function from a cmdlet or an external executable, and guessing from naming convention is exactly the threshold §1.3 forbids. The default record is a **per-name aggregate** (`name`, `sites`, `owners`); one **per-site** record (`name`, `owner`, `line`) is additionally emitted per invocation under the `command-sites` axis (§5.6). |

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

### 4.5 PSS6xxx — Presence transition

Emitted for both **functions** and **script-scope variables**. Every record
carries a `symbol_kind` of `function` or `script-variable`.

| Code | Fact |
|---|---|
| `PSS6001` | A name present in the before model is absent from the after model. |
| `PSS6002` | A name absent from the before model is present in the after model. |
| `PSS6003` | A name is present in both models. |

`PSS6003` alone carries no information about identity. A name present in both
may denote a different entity; §4.6 supplies the evidence that reveals this.

### 4.6 PSS7xxx — Attribute change

Several facts may report the same edit from different angles, and that is
normal rather than duplication. A parameter rename is genuinely both a text
change and a signature change, so `PSS7001` and `PSS7002` both fire; a consumer
that enters from either direction must not miss it.

Each is emitted for a name present in both models, and each states equality or
inequality **explicitly** rather than only reporting change. A silent absence
and an observed equality must be distinguishable by the caller.

| Code | Fact |
|---|---|
| `PSS7001` | Hash-triple classification, four values: `identical` / `comment-or-whitespace-only` / `string-literal-only` / `code-changed` (§10.5). |
| `PSS7002` | Parameter signature: equal / not equal, with the difference. |
| `PSS7003` | Callee set: equal / not equal, with the symmetric difference. |
| `PSS7004` | Caller set: equal / not equal, with the symmetric difference. |
| `PSS7005` | Dependency classification, four values from direct-callee-set change x transitive-callee-closure change (§11.3). |
| `PSS7006` | Combined classification, four values from `PSS7001` x `PSS7005`: `unchanged` / `local-change` / `dependency-only` / `change-and-propagation` (§11.4). The value names are deliberately neutral; no priority or severity is attached. |
| `PSS7007` | A script-scope variable's usage map changed: writer-set and reader-set equality plus symmetric differences, and both counts before and after. |

**The same-name/different-entity case.** `hash_body` is keyed independently of
name. Where a `hash_body` present on `B` in the before model appears on `D` in
the after model, while `B` in the after model carries a different `hash_body`,
`pss.py` emits both facts adjacently. The reader may conclude a rename plus a
name reuse; `pss.py` does not.

### 4.7 PSS8xxx — Graph, closure and rename-omission change

| Code | Fact |
|---|---|
| `PSS8001` | A call edge present in the after model and absent from the before model. |
| `PSS8002` | A call edge present in the before model and absent from the after model. |
| `PSS8003` | A function's transitive closure differs between models, with the set difference. |
| `PSS8004` | A soft reference's resolution state changed — most importantly, a string literal that matched a declared name before and matches none after. |
| `PSS8005` | **Incomplete-rename candidate.** A script-scope name is present in the after model and absent from the before model, while a name present in **both** models lost usage in the same transition. Carries both names, both usage maps, and the count deltas. Derivation and rationale: §12.7 rule (b). |
| `PSS8006` | **Producer/consumer desynchronisation candidate.** For a script-scope variable, at least one **writer** function's `PSS7001` is not `identical` while at least one **reader** function's `PSS7001` is `identical`. Carries the variable, the changed writers, and the unchanged readers. Derivation and rationale: §12.7 rule (a). |
| `PSS8007` | **Write-site loss.** A script-scope variable retains at least one reader in the after model but its writer set became empty. Emitted only as a transition; the single-state equivalent belongs to `psa.py` (§7). Derivation: §12.7 rule (c). |
| `PSS8008` | **Orphaning transition.** A function's `PSS4003` presence changed between the before and after model: gained (had a static caller before, has none after) or lost (had none before, has one after). Carries the function identifier, the direction, and both models' `named_by_literal` values (§4.4) for that identifier where the function is present in both. Carries **no commit identity** — `pss.py` is git-agnostic by design (§2.1) and knows only the two models it was given; a caller that wants per-commit resolution runs `compare` over adjacent generations, in which case a sequence of `PSS8008` facts — including a gain followed by a later loss — is the correct and unremarkable representation of a function whose reachability changed more than once (§15.4 F3). |

`PSS8004`, `PSS8005`, `PSS8006`, `PSS8007` and `PSS8008` are the direct detectors for the
failure modes that motivated the tool. None of them is a verdict: each names a
candidate together with the evidence that produced it.

### 4.8 PSS9xxx — Analysis limitations

| Code | Fact |
|---|---|
| `PSS9001` | A region could not be parsed. Carries location and extent. |
| `PSS9002` | A call site could not be statically resolved — invocation through `&` with a non-literal target, or an equivalent dynamic dispatch. |
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
```

Names are emitted in their source casing. Identity comparison is
case-insensitive (§10.7).

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

If the two models' `source.path` values differ, `compare` still runs but emits
that difference as a fact, so that a caller comparing two different scripts
(rather than two states of one script) cannot mistake the result for a
before/after delta.

### 5.6 Materialisation axes (normative)

Some information is produced by the survey but withheld from the default model
— either because §11.1 holds it to be derivable from a master collection, or
because §5.3 folded it into an aggregate. A **materialisation axis** is the unit
by which a caller asks for one such omission to be restored.

| Axis | Restores | Withheld because |
|---|---|---|
| `closure-sets` | `transitive_callees` and `transitive_callers` on each closure record, alongside the counts | Derivable from the `edges` master (§11.1) |
| `local-sites` | One record per function-local variable reference, alongside the retained per-function aggregates | Folded into an aggregate (§5.3) |
| `command-sites` | One record per unresolved command-invocation site, alongside the retained per-name aggregates | Folded into a per-name aggregate (§4.2 PSS2009 / §15.4 F2) |

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

### 6.3 Formats

**`text`** — human-oriented, one fact per line, grouped by block. A summary,
not a serialisation.

**`json`** — machine-oriented. For `survey`, this is the model itself (§5). For
`compare`, a list of delta fact records.

There is no SARIF output. SARIF encodes findings with severities and is a poor
fit for a tool that issues neither.

The set of machine formats is **`json` only**, and the capability descriptor
(§3.1) carries it as a list so that an addition is an extension rather than a
schema change. Adding YAML is not a small change and is not deferred silently:
the Python standard library has no YAML emitter, so it would mean either
hand-writing one — quoting, folding and escaping are where such emitters fail —
or taking a package dependency that §8 forbids. Any future request for YAML is
adjudicated against that cost, not against convenience.

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
try`; and after the closing `)` of a keyword-introduced parenthesis group.

`&&` and `||` are the PowerShell 7 pipeline chain operators. They do not occur
in the reference target, so no Appendix B value depends on them; they are
stated because a codebase that uses them would otherwise lose edges silently,
and §1.4 requires this tool to work on any single `.ps1`.

`catch` and `elseif` are deliberately absent from the statement-keyword list:
each takes a parenthesis or a block rather than a command.

**Exclusion.** A word in an otherwise-command position is *not* a command name
when it is a PowerShell keyword; when an assignment operator follows it (a
hashtable key or assignment target); when it starts with `-` (an operator or a
parameter name); or when it is inside brackets (an attribute or type-literal
context).



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

**Current implementation status:** only the two assignment forms (the
first two bullets after "an assignment whose left-hand side...") actually
produce a `PSS2002` record today. The other four sources are resolved for
reads (a read against a `param()`/`foreach`/`Set-Variable`/`-OutVariable`
declaration does not misreport as `PSS9004`) but do not yet produce a
`PSS2002` record of their own, because the code paths that register them
(`_precompute_parameters`, `_record_foreach`, `_record_set_variable`) keep
only the name, not a site. This is a known, tracked gap (§4.2, §13.2), not
a silent omission.

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

The usage map is the variable-side analogue of a function's callee set: it is
the structural signature that survives a rename. Measured on the reference
target, 155 script-scope names produce 115 distinct usage signatures; the
collisions fall among narrowly-used variables, whose blast radius is
correspondingly small. This inverse relationship between collision risk and
consequence is a property to be reported, not a defect to be hidden.

### 12.4 References inside expandable strings

A variable referenced inside a double-quoted string or here-string is a real
reference and is emitted as `PSS2007` in addition to its ordinary reference
fact. Measured on the reference target: 118 such references across 83 strings.

These matter disproportionately because the surrounding syntax defeats naive
text substitution: `"${Foo}bar"` uses brace delimiting, and in `"$Foo.Property"`
the reference ends at `Foo` while `.Property` is literal text. A rename
performed by search-and-replace will corrupt or skip these sites.

### 12.5 Soft-reference scoping

`PSS3002` matches string literals against **script-scope variable names only**
— specifically the `script:`-qualified names (155 on the reference target), not
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

**Rule (c) — write-site loss → `PSS8007`.**
A script-scope variable whose reader set is non-empty in the after model while
its writer set became empty. Unlike (a) and (b) this is not probabilistic: a
variable that is read and never written is broken. Emitted only as a transition
(§7).

**Verification.** The three rules were validated by injecting a realistic
defect: in a historical state, `$script:OsProfile` — referenced by 12 functions
— was renamed throughout except in one function, reproducing a single-site
omission. Rule (b) reported the new name added while the old name persisted
with readers 12 -> 1 and writers 2 -> 0; rule (c) reported the write-site loss;
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
| Self-check | `--self-check` confirms this SPEC's §4 catalogue and the codes compiled into `pss.py`'s `FACTS` dict agree as **sets of code strings**, exiting non-zero on drift. **This does not confirm any code is ever attached to an emitted record** — see the "Emission coverage" row in §13.2. `PSS2005`, `PSS4001` and `PSS4002` are now confirmed emitted by manual audit (§4.2, §4.4); `PSS2002` is confirmed emitted for one of its five §12.2 sources and not yet for the other four |
| Provisional index | `--self-check` confirms every `[PROVISIONAL Pnn]` marker in this SPEC has a row in Appendix F and vice versa. A **pending** revision is normal work in progress: reported, exit code unchanged. A **mismatch** between markers and index is a defect in the tool or the document: exit code 2, as for SPEC/catalogue drift. Appendix F must be empty before manifest registration |
| Axis vocabulary | `--self-check` confirms the axis names compiled into `pss.py` and the §5.6 table agree in both directions, exiting non-zero on drift |
| Golden vectors — shared | `hash_full` reproduces the repository's shared normalized-hash golden vectors exactly (checked by `--self-check`) |
| Golden vectors — own | `hash_body` reproduces `pss.py`'s own vectors, which include the collision cases of §10.3 as explicit non-collision assertions (checked by `--self-check`) |

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
| Capability descriptor | `--capabilities` document agrees with this SPEC on the subcommand set, the axis vocabulary, the fact catalogue, the exit-code meanings and the output-format list, exiting non-zero on drift (§3.1) | `--capabilities` does not exist yet (§3) |
| Projection invariance | for every axis, a model emitted with the axis and a model emitted without it agree on every record both carry (§5.6) | no automation written |
| Channel agreement | for a common corpus, every value printed by the text channel is reproduced by applying this SPEC's stated derivation to the JSON model of the same input; a mismatch, or a printed value with no stated derivation, exits non-zero (§6.2) | no automation written |
| Determinism | repeated runs over identical input produce byte-identical models (§5.4) | no automation written |
| Reachability | no §10.5 unreachable combination is producible over the regression corpus (`PSS9006` count is zero) | S4 |
| Differential test | where `pwsh` is available, extraction agrees with the reference parser on the Appendix B baselines | S4 (`test_pss.py`, not started) |
| Frozen regression | where `pwsh` is absent, extraction agrees with the committed aggregate expectations (§14.3) | S4 |
| Static analysis | clean under the repository's Python gates | not yet wired into a `pss.py`-specific run |
| Docs | bilingual README pair in lock-step; SPEC, CHANGELOG, VERSION present | `README.ja.md`, `CHANGELOG.md` and `VERSION` do not exist yet for this tool (only `README.md` and this file do) |
| Emission coverage | every code in §4 blocks 1-4 (survey-emittable) appears as a `code` or `facts` value on at least one record somewhere in the regression corpus's models, or is documented as data-dependent-absent (e.g. `PSS1005` legitimately does not fire on a corpus with zero duplicate names) | `PSS2005`, `PSS4001`, `PSS4002` closed by manual audit. `PSS2002` open for 4 of 5 §12.2 sources (`param()`/inline-function parameters, `foreach` loop variables, `Set-Variable`/`New-Variable`, `-OutVariable` family) — `_decl_add`'s callers do not retain a site to tag (§4.2, §12.2). No automated gate yet either way; S4 |

Registration as a whole-tool unit sets `tested = true` on the basis of the
§13.1 self-test being green, not on the canon behavioural suite — and not on
§13.2, which is why §13.2's rows are listed as owed rather than as blocking
registration.

---

## 14. Test-data acquisition

### 14.1 Principle

**The test corpus is not stored; the procedure for obtaining it is.** The
repository's own commit history is the corpus. This keeps the tool at two `.py`
files, matching its siblings, and lets the corpus grow as the surveyed projects
are maintained, rather than freezing and going stale.

### 14.2 Obtaining a corpus state

A corpus state is one generation recorded in a corpus entry under `corpus/`
(ADR 0033). An entry pins one path and does not follow renames; the reference
target's directory move is represented as two entries (`0001` before, `0002`
after), not as one `--follow` walk. Retrieval is **by blob**:

```
python3 corpus.py list                       # entries and their generation counts
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
tool** (S4, tracked in §13.2); once `test_pss.py` is built, `TESTING.md` is
where it enumerates the specific state pairs used as labelled regression
cases and the property each one exercises — the same role `TESTING.md` plays
for this repository's other tools and projects.

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
re-survey run with `pss.py` itself (via the ADR 0033 `corpus.py` cache),
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
sites, and the `counters` block (B.6).

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
| Intra-script call edges | 1,247 |
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
| Resolved in function (`PSS2003`) | 20,353 |
| Automatic (`PSS2005`) | 2,004 |
| `$script:`-qualified (`PSS2004`) | 1,381 |
| — across distinct names | 155 (usage-map population: **156**, see §12.3) |
| Outside any function | 555 |
| `$env:`-qualified (`PSS2004`) | 14 |
| Unresolved (`PSS9004`) | 11, across 5 functions and 4 names |
| References inside expandable strings (`PSS2007`) | 118, across 83 strings |
| Distinct usage signatures over 155 script names | 115 |

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

### B.7 Delta behaviour over 12 consecutive historical states

| Quantity | Reference value |
|---|---:|
| Same-name function comparisons | 2,607 |
| `PSS7001 = identical` | 2,395 |
| `PSS7001 = comment-or-whitespace-only` | 13 |
| `PSS7001 = string-literal-only` | 9 |
| `PSS7001 = code-changed` | 190 |
| Unreachable hash-triple combinations observed | 0 |
| `PSS7005 = dependencies-unchanged` | 1,156 |
| `PSS7005 = downstream-changed` | 12 |
| `PSS7005 = dependencies-changed` | 45 |
| `PSS7006 = dependency-only` | 12 |

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
