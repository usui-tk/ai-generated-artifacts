# PowerShell Symbol Surveyor

> 🇺🇸 English / 🇯🇵 [日本語](./README.ja.md)

Two tools live here.

| File | Role |
|:--|:--|
| `pss.py` | The surveyor itself. Extracts a symbol model from one PowerShell script. Contract: [`SPEC.md`](./SPEC.md). |
| `test_pss.py` | The baseline gate (§13.1), and the two pieces of apparatus it exercises the surveyor with: the **corpus manager** (`test_pss.py corpus <subcommand>`, §14.2) and the **derived cache producer** (`test_pss.py cache <entry>`, §14.4). |

`SPEC.md` is authoritative for `pss.py` and for the §14.4 cache contract.
This README is authoritative for the corpus manager; the corpus governance
rules are durable in
[ADR 0033](../../governance/adr/0033-pss-test-corpus-governance.md).

---

## Surveying a script

The surveyor reads one script and emits one JSON document — the model. It
reports facts and draws no conclusions (SPEC §1.2): counts, symbols, call
edges, references, and the analysis limits it hit (§4.8) — never a verdict
about any of them. Whether something is a defect, a risk or fine is the
consumer's judgement, made on facts the model must therefore actually carry.

```
# the default model - compact JSON, written to the given path
python3 pss.py survey Script.ps1 --format json --out model.json

# restore opt-in material: closure-sets, command-sites, local-sites, or 'all'
python3 pss.py survey Script.ps1 --axes all --out model.json

# price a request without keeping it: the model is computed and discarded
python3 pss.py survey Script.ps1 --axes all --cost
```

The default model is deliberately not everything. Four **materialisation
axes** (SPEC §5.6) hold the bulk material — transitive closure sets, one
record per unresolved command-invocation site (carrying the invocation's
argument itemisation and byte span), per-site records on each resolved
call edge (the same itemisation, attached to the `edges[]` rows), one
record per local-variable
reference — and every model states which axes it carries in its
`materialization` block, so a narrower model can never pass as a full one.
Every model also carries `model_version`, which advances whenever the model
emitted for a fixed input can differ (§5.5); it is what decides whether two
models are comparable at all.

---

## Slicing a model

`slice` narrows an existing model deterministically. It never re-surveys and
never adds material a survey did not capture — an axis on `slice` only
restores what the input already carries.

```
# every record concerning one symbol, plus incident edges and all limitations
python3 pss.py slice model.json --scope function/Set-DebugStep --out slice.json

# narrow to an axis subset; 'all' keeps every axis the input has
python3 pss.py slice model.json --axes closure-sets
```

A `--scope` slice keeps or drops **whole records** by one membership rule and
never rewrites a kept record (SPEC §5.7) — with one stated exception: every
symbol identifier the kept records still reference is re-introduced as a
**boundary stub** (`record: "stub"` plus the four identify-and-locate keys,
copied verbatim from the input), so no identifier the **scoped collections**
reference dangles. One stated exception, found by a round-4 reviewer reading
the unqualified claim that used to sit here: `limitations` is kept in full,
because it describes what the survey could *not* determine and filtering it
would misrepresent the slice's own coverage — so a limitation's `owner` may
name a function the slice carries no record for, by design (SPEC §5.7). A model from another `model_version` is **refused** (`PSS9005`)
rather than sliced into a document whose stated version and actual shape
disagree.

---

## Comparing two models

`compare A B` states the differences and claims no relation between the inputs.
`trace before after` carries the caller's assertion that the second is a later
state of the first — an assertion the tool cannot verify and can only require
to be made, which is why it is a verb and not a defaulted flag.

```
python3 pss.py compare a.json b.json --format json
python3 pss.py trace before.json after.json --format json --out delta.json
python3 pss.py compare a.json b.json --all      # equality stated per subject
```

The output carries `delta_records` (differences only), `surveyed` (a per-code
tally) and `examined_subjects` (the compared population by identifier). All
three are needed: a code missing from `surveyed` **did not run**, which is not
the same as running and finding nothing, and a name missing from
`examined_subjects` was never compared, which is not the same as being
unchanged. `compare` evaluates the fifteen codes that hold without a claim of
succession; `trace` evaluates those and the three rules of §12.7, which
presuppose the assertion `trace` exists to carry. Each produces a candidate
with its evidence, never a conclusion.

A `model_version`, axis-set or scope mismatch **refuses** rather than comparing
partially, because a partial delta reads as a complete one.

## The descriptor and the self-checks

```
python3 pss.py --capabilities   # machine-readable interface descriptor (JSON)
python3 pss.py --self-check     # SPEC tables and compiled constants, held both ways
python3 pss.py --list-facts     # the fact catalogue, one line per code
```

`--capabilities` **serialises the constants the tool actually runs on** — the
declared model schema, identifier forms and collection join keys, record
variants, value nullability, the slice projection, the axis vocabulary —
and marks what is not implemented *with a reason*, gated against behaviour
so a feature cannot land while leaving its mark behind (SPEC §3.1). A
consumer can therefore learn the interface from the tool instead of from a
copy of the documentation. `--self-check` holds the SPEC's tables and the
compiled catalogue against each other in both directions; what it cannot
see — values at a real input — the baseline gate holds against the pinned
corpus blob (§13.1).

---

## Why a corpus

The surveyor's requirements are derived from measured damage rather than from
asking what is needed: a failure nobody noticed cannot be reported by the people
who missed it. Deriving requirements that way needs real material, and this
repository's own git history is exactly that — the owner controls it, and a
committed generation never changes.

A corpus entry is the unit of that material: one script, one path, one
contiguous run of generations.

---

## The two rules that shape an entry

**An entry never follows a rename.** `git log --follow` is a rename-detection
heuristic, not a recorded fact, and `git show <rev>:<current path>` fails for
every generation from before a move — silently, if the caller treats the failure
as "skip". Pinning one path removes both failure modes by construction: every
generation an entry records is one where the blob provably exists at that exact
path. When a script moves, the old entry seals itself and a new entry is
registered for the new path.

Nothing is lost by refusing to follow. The script currently at
`projects/powershell-update-windows-server-iso/` moved once, and the two entries
covering it hold 73 and 157 generations — the same 230 that `--follow` reports,
split at the move.

**An entry is append-only.** `update` re-derives the generation list and refuses
unless the stored list is a strict prefix of what git reports now. Growth is
additive, so no previously measured generation changes. A rewritten or truncated
history is refused rather than absorbed, and the refusal points at registering a
new entry.

---

## Entry files

Entries live in `corpus/`. Identity is the **leading four-digit number** in the
filename. Everything between the number and `.json` is descriptive and is never
read back, so renaming an entry file cannot break a reference and cannot go
stale. A fifth consecutive digit is refused rather than misread as a shorter
number (`00012` would otherwise read as `0001` plus a stray `2`), a duplicate
number is refused rather than silently resolved, and non-conforming files
are ignored but reported.

The format follows the in-repo precedent set by
`projects/bash-ol-aws-ami-builder/tests/ena/ena-driver-releases.json`: a header
of metadata, then one record per line, so adding a generation is a one-line
diff.

```json
{
  "schema_version": "1.0",
  "list_type": "pss-corpus-entry",
  "generated_by": "quality-tools/powershell-symbol-surveyor/corpus.py",
  "repo": "ai-generated-artifacts",
  "script_path": "projects/powershell-update-windows-server-iso/Update-WindowsServerIso.ps1",
  "start_rev": "7566d22cf5f09a74523418a23a7c5001502c8633",
  "end_rev": "aade522845fa351cf4bb0f7f81fe72d79eb9bee4",
  "count": 157,
  "generations": [
    { "rev": "...", "date": "2026-06-08", "blob": "...", "subject": "..." }
  ]
}
```

`blob` is the content hash of the script at that generation. It is an
integrity check independent of `rev`: when a history is rewritten, commit
hashes always change, while a blob hash changes only if the content did — so
holding both distinguishes a rewritten history from an altered one.

`start_rev`, `end_rev` and `count` restate what the records already say. The
restatement is deliberate (the header alone shows the range) and is therefore
verified on load rather than trusted.

### Written by the tool, never by hand

Entries are written only through the corpus manager, in the same way the
manifest is written only through `canon-manifest-tool` (ADR 0011). The
`generated_by` field records that. Its value still names `corpus.py`, the
file the manager lived in when the two committed entries were written — the
manager has since moved into `test_pss.py` as the `corpus` subcommand: an entry is
byte-stable by construction, which is what makes growth detection possible at
all, so re-pointing the string would rewrite two committed artefacts to record
a fact about the tool rather than about the entries.

### No timestamps

A written entry contains no timestamp, no environment stamp, and no other
run-dependent value. Regenerating an unchanged entry reproduces it byte for
byte, which is what makes growth detection work at all: detection is
regeneration plus comparison, and a file that differs on every regeneration
cannot support it.

### Sealed state is derived

Whether an entry is sealed (its path no longer exists at `HEAD`) is computed on
demand, never stored. A stored flag would be one more hand-held value able to go
stale — the failure mode ADR 0031 removed elsewhere in this repository.

---

## Corpus usage

```
# register an entry (one .ps1; directories and globs are refused)
python3 test_pss.py corpus --repo <repo> add <path/to/Script.ps1> [--slug <text>]

# derived view: identity, sealed state, range, ignored files
python3 test_pss.py corpus --repo <repo> list

# compare every entry against git now; findings only, nothing is applied
python3 test_pss.py corpus --repo <repo> check

# append newly committed generations to one entry
python3 test_pss.py corpus --repo <repo> update <NNNN>
```

`check` reports growth and rewrite as findings and re-pins nothing. Re-pinning
is a deliberate `update` — an adjudicated change that goes through the ordinary
patch flow, in keeping with the machine-proposes / human-decides split of
ADR 0011 and ADR 0027.

`check` is **not** part of the standing gate battery. The scripts it watches are
maintenance-stream property and advance at maintenance speed, so wiring it into
the governance battery would turn ordinary project work into a governance-stream
red. Run it when the corpus is the subject.

### Analysis

Three reductions run over an entry's generations. Each reports counts and
observations and produces no verdict, matching the surveyor's own contract
(`SPEC.md` §1.2).

```
# per-generation function removals, and whether the model still referenced them
python3 test_pss.py corpus --repo <repo> deletions <NNNN>

# caller-count transitions for named functions
python3 test_pss.py corpus --repo <repo> transitions <NNNN> --targets Get-Foo Set-Bar

# names ever defined, against those present at the last generation
python3 test_pss.py corpus --repo <repo> ever-defined <NNNN>
```

Surveying every generation of a large script takes minutes; `--limit N`
restricts a run to the last N generations. Analysis writes no files — its output
is transient by design, in the same spirit as the hot/cold observation split of
ADR 0028.

A pin that no longer resolves raises an error. It is never skipped: an entry's
records were proven to resolve when it was written, so a miss means the corpus
is broken and must say so.

---

## Derived model caches

Surveying every generation of an entry costs minutes, so the models are cached
outside the repository and carried between sessions. `test_pss.py cache` is
the producer SPEC §14.4 specifies.

```
# one entry, every generation, all axes
python3 test_pss.py cache 0002

# exercise the generator without paying for a full run
python3 test_pss.py cache 0001 --limit 2 -o /tmp/sample.jsonl.gz
```

A cache is **derived data**: never committed, never a baseline, and usable only
while it is known which build produced it. That last property is what the
header carries — `pss_version`, `model_version`, `model_shape`,
`baseline_digest`, and what was surveyed over which generations.

Three choices in the generator are worth knowing before reading its output.

**It computes no identity of its own.** `baseline_digest` and `model_shape`
come from the same function `--emit-baseline-digest` prints, and are copied. A
second implementation would let a cache and the gate that reads it disagree
about what was measured, which is the defect ADR 0033 retired. While the
producer was its own file this was enforced by `hashlib` being absent from it;
now it is enforced over the producer's own functions in the syntax tree, which
is the same requirement in the form the merged file allows.

**A generation is `rev` and `blob`, never a position.** Identity lives in the
blob (ADR 0033). An index is derivable from the file's own order, so storing it
would create a second source of truth for one fact — and it is the copy that
can silently disagree. This is not hypothetical: an earlier cache, produced
from a procedure that lived in prose rather than in a file, carried
`gen_index: null` on all 230 of its records.

**Every axis is materialised, and that is not an option.** A cache is only
useful against another cache, and two caches materialised differently are not
comparable. Fixing the axis set is also faster, because a model that already
carries every axis measures no axis increments.

A cache survives everything except a change to what the model emits. A digest
that no longer matches the current build says the cache came from a *different*
build; it does not say the data is wrong. `model_version` is what answers
whether the data is still comparable.

---

## Self-test

```
python3 test_pss.py        # the whole gate, corpus cases included
```

The corpus cases live in `test_pss.py` alongside the surveyor's own, because
SPEC §14.1 keeps this tool at two `.py` files and a third one for the corpus
was a third one. **That rule is now gated**: the gate enumerates the tool's
file set and requires an exact match, so a third module fails whether or not it
has been staged. It was normative and ungated for three days, which is exactly
how the count reached five — adding a file now means editing §14.1 and the
gate's list together. Their fixtures are real git repositories built in a temporary
directory, because the behaviour under test is git behaviour — renames,
deletions, appended history, rewritten history. A mock would reproduce the
assumptions rather than the facts, and every trap this tool is built around was
an assumption failure. Needing the `git` binary rather than this checkout, they
are skipped — and say so — where it is absent (§14.3).

---

## Registration

The tool is registered: `tool.powershell-symbol-surveyor` @ 0.5.0, kind
`tool`, a whole-directory unit on the analyzer's precedent. The corpus
manager and the cache producer are subcommands of `test_pss.py` and are
covered by the same unit. The SPEC's own condition — Appendix F empty of
provisional items — had been met since 2026-08-16; registration sets
`tested = true` on the §13.1 self-test being green.

> **Note (2026-08-18, resolved post-D12):** deferring registration had a
> cost worth recording. The derived battery target lists start from the
> manifest (ADR 0031), so deferring registration **also deferred every
> structural gate over this directory**. In fact the file count grew from
> two to five in three days against a SPEC that says "two `.py` files",
> and no gate could see it — the baseline gate reads the model, not the
> directory tree. Registering first was proposed, and the registration
> above is that proposal carried out.
