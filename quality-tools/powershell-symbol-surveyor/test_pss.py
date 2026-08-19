#!/usr/bin/env python3
"""Baseline gate for the PowerShell Symbol Surveyor (SPEC 13.1, ADR 0034).

Re-derives every asserted figure in SPEC Appendix B from the pinned reference
generation and fails on divergence.

Three properties are deliberate.

**No expected values live here.** The single master is the ``pss-baseline``
block in SPEC Appendix B.8; this file reads it. A figure recorded in the
document and a figure checked by a gate cannot drift apart if there is only one
of them.

**The basis is a pinned blob, not a branch head.** The reference target is a
maintenance-stream artefact (ADR 0029) that advances on its own schedule. A gate
anchored to its head would turn ordinary maintenance work into a governance
failure, which is why ADR 0033 kept ``corpus.py check`` out of the standing
battery. Anchored to a blob, this gate has no such coupling and belongs in the
battery.

**Degradation is by capability, per SPEC 14.3.** With ``git`` the baseline and
the model-shape fingerprints are checked. With ``pwsh`` as well, the figures the
reference parser can reach are additionally checked against it, so the baseline
is confirmed against ground truth rather than against itself. With neither, the
synthetic fixtures still run - they cover the extractor rules that have bitten,
and they need no corpus.

**The baseline digest has one implementation, and it is this one.** A derived
model cache identifies its producing build by a digest over the acceptance block
(SPEC 14.4, ADR 0035). Computing that digest in a throwaway generation script
would rebuild the defect ADR 0033 retired - a measurement instrument living
outside the repository - and would let the cache and the gate disagree about
what was measured. ``--emit-baseline-digest`` therefore exposes the block this
gate already derives, and the gate checks that the two agree.

Usage:
    python3 test_pss.py [--pwsh <path-to-pwsh>]
    python3 test_pss.py --emit-baseline-digest      # SPEC 14.4 cache header

The version-decision check needs the parent commit, so it is skipped - and says
so - in a checkout that has none.
"""

import argparse
import collections
import gzip
import hashlib
import importlib.util
import json
import os
import re
import contextlib
import io
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = os.path.join(HERE, "SPEC.md")
PSS = os.path.join(HERE, "pss.py")

# SPEC 2.6. The list is the point: none of these can reach a subprocess, a
# socket or an HTTP client, so the tool has no means of reading a repository, a
# corpus or a network however its logic evolves. Widening this is a deliberate
# act, and one that should be argued for rather than noticed afterwards.
# SPEC 1.3. Words that state a conclusion rather than an observation. The list
# is a denylist, so it makes no completeness claim: it stops these words from
# coming back and says nothing about a judgement worded some other way. Each
# entry earned its place - `broken` from PSS8007, the rest by being the words a
# severity vocabulary reaches for first.
# SPEC 14.4's header table, transcribed here so the generator's declaration is
# compared with the specification rather than with another copy of itself.
SPEC_CACHE_HEADER = (
    "axes", "baseline_digest", "cache_kind", "corpus_count", "corpus_end_rev",
    "corpus_entry", "corpus_start_rev", "model_shape", "model_version",
    "pss_version", "script_path", "spec_contract",
)

JUDGEMENT_WORDS = (
    "audit", "bad", "broken", "critical", "dangerous", "harmful", "improper",
    "incorrect", "invalid", "risky", "severity", "should", "unsafe", "wrong",
)

PSS_ALLOWED_IMPORTS = (
    "argparse", "bisect", "hashlib", "json", "os", "re", "sys",
)
sys.path.insert(0, HERE)

import pss  # noqa: E402

ALL_AXES = ["closure-sets", "local-sites", "command-sites"]

_PASS = []
_FAIL = []


def check(ok, label, detail=""):
    (_PASS if ok else _FAIL).append(label)
    print("[%s] %s%s" % ("PASS" if ok else "FAIL", label,
                         ("" if ok else "  -- " + detail)))


def cchk(label, ok, detail=""):
    """Label-first adapter over ``check``, for the corpus self-test cases.

    The corpus cases were written against a label-first signature and are moved
    here verbatim, so that the move is auditable as a move. Two argument orders
    are worth less confusion than fifty silently re-ordered call sites; both
    names feed the one counter, so there is still a single tally.
    """
    check(ok, label, detail)


def eq(actual, expected, label):
    check(actual == expected, label,
          "expected %r, measured %r" % (expected, actual))


# ---------------------------------------------------------------- baseline I/O

def load_baseline():
    """Read the single master out of SPEC Appendix B.8.

    A missing or malformed block is a hard error, not a skip: the whole point of
    the block is that nothing may assert a figure that the document does not
    carry.
    """
    text = open(SPEC, encoding="utf-8").read()
    m = re.search(r"```json pss-baseline\n(.*?)\n```", text, re.S)
    if not m:
        raise SystemExit("SPEC.md carries no ```json pss-baseline``` block "
                         "(Appendix B.8) - nothing to assert against")
    return json.loads(m.group(1))


def repo_root():
    """The repository root, or ``None``.

    ``None`` covers both reasons - no git binary, and no repository - because
    every caller here treats them the same way. It has to catch the missing
    binary rather than let it raise: SPEC 14.3 promises that an absent `git`
    degrades this gate to fixtures, and until now it did not, because this
    function raised `FileNotFoundError` and took the whole run with it. The
    documented degradation path had never once been exercised.
    """
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=HERE,
                             capture_output=True)
    except OSError:
        return None
    return out.stdout.decode().strip() if out.returncode == 0 else None


def git_available():
    """Is the `git` binary runnable?

    Distinct from ``repo_root``, which answers a different question and returns
    ``None`` for two different reasons. The corpus self-test builds its own
    repositories in a temporary directory, so it needs the binary and does not
    need this checkout; conflating the two would skip it in a working tree that
    can run it perfectly well.
    """
    try:
        return subprocess.run(["git", "--version"],
                              capture_output=True).returncode == 0
    except OSError:
        return False


def read_blob(root, blob):
    """Retrieve a pinned generation by blob (SPEC 14.2).

    Resolution is by blob rather than ``<commit>:<path>`` because the path did
    not exist before the target's directory move; and an unresolvable pin raises
    rather than being skipped (ADR 0033).
    """
    out = subprocess.run(["git", "-C", root, "cat-file", "-p", blob],
                         capture_output=True)
    if out.returncode != 0:
        raise SystemExit("pinned blob %s does not resolve in %s - the basis of "
                         "SPEC Appendix B is unreachable" % (blob, root))
    return out.stdout.decode("utf-8-sig")


# ------------------------------------------------------------- model shape

def key_paths(obj, prefix="", out=None):
    if out is None:
        out = set()
    if isinstance(obj, dict):
        for k, v in obj.items():
            out.add(prefix + "/" + k)
            key_paths(v, prefix + "/" + k, out)
    elif isinstance(obj, list):
        for v in obj:
            key_paths(v, prefix + "[]", out)
    return out


def shape_fingerprint(model):
    joined = "\n".join(sorted(key_paths(model)))
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()[:16]


# ------------------------------------------------------------- measurements

def measure(model):
    """Derive every asserted figure from one model.

    Each derivation is stated once, here, so that a figure in the document has
    exactly one meaning. Under-specified derivations are what let an apparent
    34-edge discrepancy read as drift when it was the difference between
    function-to-function edges and the full edge collection.
    """
    facts = collections.Counter()
    for coll, records in model.items():
        if not isinstance(records, list):
            continue
        for r in records:
            if isinstance(r, dict):
                for f in (r.get("facts") or []):
                    facts["%s.%s" % (coll, f)] += 1

    def codes(coll):
        return collections.Counter(r.get("code")
                                   for r in model.get(coll, [])
                                   if isinstance(r, dict))

    symbols = model["symbols"]
    names = [s["name"].lower() for s in symbols]
    edges = model["edges"]
    closures = model["closures"]
    svq = collections.Counter(r.get("qualifier")
                              for r in model["script_variables"]
                              if r.get("code") == "PSS2004")
    lvc = codes("local_variables")

    # Appendix B.3's figures, each stated as a query rather than as a label.
    # A label does not determine a query: "$script:-qualified" reads equally as
    # the record count, the script-qualified subset, or the part of that subset
    # occurring inside a function, and the three differ (ADR 0036).
    script_refs = [r for r in model["script_variables"]
                   if r.get("record") == "reference"
                   and r.get("qualifier") == "script"]
    usage_map = [r for r in model["script_variables"]
                 if r.get("record") == "usage_map"]
    signature = lambda r: (tuple(sorted(r.get("writers") or [])),
                           tuple(sorted(r.get("readers") or [])))
    p9004 = [r for r in model["limitations"] if r.get("code") == "PSS9004"]
    p9004_names = set()
    for r in p9004:
        hit = re.search(r"'\$([^']+)'", r.get("detail") or "")
        if hit:
            p9004_names.add(hit.group(1))
    interp = model["string_interpolation_references"]
    callee = [len(c.get("transitive_callees") or []) for c in closures]
    caller = [len(c.get("transitive_callers") or []) for c in closures]

    return {
        "counters": dict(model["counters"]),
        "symbols": {
            "total": len(symbols),
            "nested": sum(1 for s in symbols if s.get("depth", 0) > 0),
            "duplicate_names": len(names) - len(set(names)),
        },
        "facts": {k: facts[k] for k in facts},
        "edges": {
            "records": len(edges),
            "from_script": sum(1 for e in edges if e["from"] == "<script>"),
            "function_to_function":
                sum(1 for e in edges if e["from"] != "<script>"),
        },
        "closures": {
            "callee_side_total": sum(callee),
            "caller_side_total": sum(caller),
            "widest_callee": max(callee) if callee else 0,
            "widest_caller": max(caller) if caller else 0,
        },
        "local_variables": {
            "PSS2002": lvc["PSS2002"],
            "PSS2003": lvc["PSS2003"],
            "PSS2005": lvc["PSS2005"],
            "aggregate_records": lvc[None],
        },
        "script_variables": {
            "PSS2004": codes("script_variables")["PSS2004"],
            "PSS2004_script": svq["script"],
            "PSS2004_env": svq["env"],
            "PSS2006": codes("script_variables")["PSS2006"],
            "PSS2008": codes("script_variables")["PSS2008"],
            "script_qualified_refs": len(script_refs),
            "script_qualified_refs_in_function":
                sum(1 for r in script_refs if r["owner"] != "<script>"),
            "script_qualified_refs_at_script_level":
                sum(1 for r in script_refs if r["owner"] == "<script>"),
            "script_qualified_names": len({r["name"] for r in script_refs}),
            "usage_signatures": len({signature(r) for r in usage_map}),
        },
        "soft_references": {
            "PSS3001": codes("soft_references")["PSS3001"],
            "PSS3002": codes("soft_references")["PSS3002"],
        },
        "string_interpolation_references": {
            "records": len(interp),
            "distinct_source_lines": len({r["line"] for r in interp}),
        },
        "limitations": {
            "PSS9002": codes("limitations")["PSS9002"],
            "PSS9004": codes("limitations")["PSS9004"],
            "PSS9004_functions": len({r.get("owner") for r in p9004}),
            "PSS9004_names": len(p9004_names),
        },
    }


# --------------------------------------------------------- baseline digest

def acceptance_block(model_def, model_all):
    """The block a derived cache's ``baseline_digest`` is taken over (14.4).

    It is Appendix B.8's block less its ``basis``: every value this build
    re-derives, and nothing the document merely states. ``basis`` is excluded
    because it is a pointer to what was measured, not a measurement - and the
    values move whenever the pin does, so the binding is not lost.
    """
    block = measure(model_all)
    block["model_shape"] = {
        "default": shape_fingerprint(model_def),
        "all-axes": shape_fingerprint(model_all),
    }
    block["references_outside_functions"] = {
        "default": refs_outside_functions(model_def),
        "all-axes": refs_outside_functions(model_all),
    }
    return block


def refs_outside_functions(model):
    """Every variable reference occurring outside any function, all scopes.

    Stated per materialisation because it is the one asserted figure that is
    not axis-invariant: ``local-sites`` retains each local reference site, so
    the script-level locals it contributes are absent from the default model.
    A count that moves with the axes is unfalsifiable unless the axes are part
    of its basis (ADR 0036). Its script-scope-only companion,
    ``script_qualified_refs_at_script_level``, is axis-invariant and lives in
    the block above; the two answer different questions and both are kept.
    """
    at_script = sum(1 for r in model["script_variables"]
                    if r.get("record") == "reference"
                    and r.get("owner") == "<script>")
    return at_script + sum(1 for r in (model.get("local_variables") or [])
                           if r.get("owner") == "<script>")


def canonical_json(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"))


def baseline_digest(block):
    return hashlib.sha256(canonical_json(block).encode("utf-8")).hexdigest()


def identity_document(root, baseline):
    """The SPEC 14.4 cache-header identity for this build.

    One implementation, two consumers: ``--emit-baseline-digest`` prints it and
    the cache producer copies it into a header. 14.4 says a generation script
    computes nothing itself, and the reason survives the move into this file:
    a second derivation would let a cache and the gate that reads it disagree
    about what was measured. What used to enforce that structurally - `hashlib`
    being absent from a separate `build_cache.py` - is now enforced by the gate
    reading this file's own syntax tree (`check_cache_generator`).
    """
    text = read_blob(root, baseline["basis"]["blob"])
    model_all = pss.Survey("reference.ps1", text, axes=ALL_AXES).run().model()
    model_def = pss.Survey("reference.ps1", text).run().model()
    block = acceptance_block(model_def, model_all)
    return {
        "baseline_digest": baseline_digest(block),
        "pss_version": pss.__version__,
        "model_version": pss.MODEL_VERSION,
        "model_shape": block["model_shape"],
        "basis": baseline["basis"],
    }


def emit_baseline_digest(baseline):
    """Print the SPEC 14.4 cache-header identity for this build, or fail."""
    root = repo_root()
    if not root:
        print(json.dumps({"error": "git-unavailable"}), file=sys.stderr)
        return 2
    print(canonical_json(identity_document(root, baseline)))
    return 0


def previous_build(root, text):
    """Survey the pinned blob with the ``pss.py`` of the parent commit.

    Returns ``(model_def, model_all, MODEL_VERSION)`` or ``None`` when the
    comparison cannot be made — no parent, no ``pss.py`` there, or an older
    signature that does not accept ``axes``. Those degrade to a reported skip
    per SPEC 14.3 rather than to a silent pass.

    The old model is measured with **this** build's ``measure()`` and
    ``shape_fingerprint`` deliberately. Measuring it with the old gate would
    fold every change to the gate into the comparison — this very appendix
    gained ten rows at ADR 0036 with ``pss.py`` untouched — and the question
    asked here is whether the *model* moved.
    """
    rel = os.path.relpath(os.path.join(HERE, "pss.py"), root)
    src = subprocess.run(["git", "-C", root, "show", "HEAD~1:%s" % rel],
                         capture_output=True)
    if src.returncode != 0:
        return None
    handle, path = tempfile.mkstemp(suffix="_pss_prev.py")
    os.close(handle)
    try:
        with open(path, "wb") as fh:
            fh.write(src.stdout)
        spec = importlib.util.spec_from_file_location("pss_previous", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        model_all = module.Survey("reference.ps1", text,
                                  axes=ALL_AXES).run().model()
        model_def = module.Survey("reference.ps1", text).run().model()
        return model_def, model_all, module.MODEL_VERSION
    except Exception:
        return None
    finally:
        os.unlink(path)
        sys.modules.pop("pss_previous", None)


def check_version_decision(root, text, model_def, model_all):
    """A model that moved without its version advancing is a failure (ADR 0035).

    Nothing recorded this before. The baseline gate reddens when a figure or a
    shape moves, but clearing it means re-stamping B.8 — and re-stamping while
    holding ``MODEL_VERSION`` passes every check in the battery, which is how
    six mutually incompatible builds came to declare ``"1"``.

    No ledger of past versions is kept, because a ledger is a second copy that
    goes stale exactly the way the figures in B.3 did (ADR 0036). The previous
    state is *derived*: the parent commit's ``pss.py``, re-run against the same
    pinned blob. Measured against real history this is not a check that cannot
    fail — it reddens at `44b97d1` (shape moved, version held) and at `bc69c27`
    (shape identical, measured values moved, version held), which is why the
    condition is shape **or** content and not shape alone.
    """
    previous = previous_build(root, text)
    if previous is None:
        print("-- no comparable parent build: version-decision check skipped "
              "(SPEC 14.3) --")
        return
    prev_def, prev_all, prev_version = previous
    moved = []
    if shape_fingerprint(prev_def) != shape_fingerprint(model_def):
        moved.append("shape/default")
    if shape_fingerprint(prev_all) != shape_fingerprint(model_all):
        moved.append("shape/all-axes")
    if measure(prev_all) != measure(model_all):
        moved.append("measured values")
    check(not moved or prev_version != pss.MODEL_VERSION,
          "version decision: a moved model advanced MODEL_VERSION",
          "the emitted model differs from the parent commit's in %s, and "
          "MODEL_VERSION is %r on both sides. SPEC 5.5 advances the version "
          "whenever the model emitted for a fixed input can differ - shape "
          "OR content - and ADR 0035 records that leaving it unadvanced is "
          "what let one version name six incompatible builds"
          % (" and ".join(moved), pss.MODEL_VERSION))


TEXT_CHANNEL_DERIVATIONS = {
    "functions": lambda m: len(m["symbols"]),
    "nested definitions": lambda m: sum(1 for r in m["symbols"]
                                        if "PSS1004" in r["facts"]),
    "duplicate names": lambda m: sum(1 for r in m["symbols"]
                                     if "PSS1005" in r["facts"]),
    "named commands": lambda m: m["counters"]["commands_named"],
    "call edges": lambda m: len(m["edges"]),
    "from a function": lambda m: sum(1 for r in m["edges"]
                                     if r["from"] != "<script>"),
    "variable references": lambda m: m["counters"]["variable_refs"],
    "scope-qualified refs": lambda m: sum(1 for r in m["script_variables"]
                                          if r["record"] == "reference"),
    "interpolated refs": lambda m: len(m["string_interpolation_references"]),
    "usage-map population": lambda m: sum(1 for r in m["script_variables"]
                                          if r["record"] == "usage_map"),
    "unresolved reads": lambda m: sum(1 for r in m["limitations"]
                                      if r["code"] == "PSS9004"),
    "no static caller": lambda m: sum(1 for r in m["closures"]
                                      if r.get("code") == "PSS4003"),
    "recursion groups": lambda m: sum(1 for r in m["closures"]
                                      if r.get("code") == "PSS4004"),
    # Not len(closures): the row counts reachability *entries*, the closure
    # sets summed, not the records that carry them. Writing the obvious
    # derivation first and being reddened by it is the reason this check
    # derives from the SPEC rather than from the renderer.
    "closure entries": lambda m: sum(r.get("transitive_callee_count", 0)
                                     for r in m["closures"]),
}


def check_channel_agreement(model):
    """Every figure the text channel prints is reproduced from the JSON channel.

    The two channels are one measurement rendered twice, and a caller reading
    the text one has no way to notice when they stop agreeing. The derivations
    here are written from the SPEC's definitions and applied to the model, not
    lifted from ``render_text`` - a check that re-ran the renderer's own
    expression would compare a restatement rather than a measurement, which is
    the failure this tool has now recorded four times.

    Rows the renderer prints that carry no derivation here are reported, so
    that adding a figure to the text channel without a derivation is visible
    rather than silently uncovered.
    """
    rendered = {}
    for line in pss.render_text(model).splitlines():
        if ":" not in line:
            continue
        label, _, value = line.partition(":")
        label = label.strip(" -")
        head = value.strip().split()[0] if value.strip() else ""
        if head.isdigit():
            rendered[label] = int(head)

    missing = sorted(set(TEXT_CHANNEL_DERIVATIONS) - set(rendered))
    eq(missing, [],
       "channel agreement: every derivation has a row in the text channel")

    disagreeing = {label: (rendered[label], derive(model))
                   for label, derive in sorted(TEXT_CHANNEL_DERIVATIONS.items())
                   if label in rendered and rendered[label] != derive(model)}
    eq(disagreeing, {},
       "channel agreement: text figures reproduce from the JSON channel")

    # Rows without a derivation here are listed rather than ignored, so that a
    # figure added to the text channel without one becomes visible. `lines` is
    # a source attribute rather than a measurement; the three soft-reference
    # rows print a split whose parts this check does not yet decompose.
    eq(sorted(label for label in rendered
              if label not in TEXT_CHANNEL_DERIVATIONS
              and not label.startswith("PSS")),
       ["function-name lits", "lines", "script-var lits", "string constants"],
       "channel agreement: the uncovered rows are the ones recorded as uncovered")


def check_projection_invariance(text, model_all):
    """Dropping an axis must remove records and fields, never change them (5.6).

    The rule is stated over the records two models *both* carry, so the check
    is a containment and not an equality: a wider model legitimately carries
    records the narrower one does not, and fields on shared records that only
    the axis materialises. What it may not do is disagree about anything the
    narrower model says.

    The narrower model's key vocabulary per collection is what defines "both
    carry" here, and it is derived from the models rather than declared,
    because SPEC 13.3 marks a path as `axis` without naming which axis
    contributes it. Deriving it keeps this check independent of that
    declaration instead of inheriting its errors.

    `cost` is excluded and named rather than silently skipped: it is a
    description *of* the model, so a narrower model's block correctly reports
    different byte counts. Comparing it would assert that a smaller model is
    the same size as a larger one.
    """
    for axis in sorted(pss.AXES):
        narrow = pss.Survey("reference.ps1", text,
                            axes=set(ALL_AXES) - {axis}).run().model()
        unreproduced = []
        for coll, narrow_records in sorted(narrow.items()):
            if not isinstance(narrow_records, list) or coll == pss.COST_KEY:
                continue
            vocabulary = set()
            for record in narrow_records:
                vocabulary |= set(record)
            wide = collections.Counter(
                json.dumps({k: v for k, v in record.items() if k in vocabulary},
                           sort_keys=True)
                for record in model_all.get(coll, ()))
            for serialised, count in collections.Counter(
                    json.dumps(record, sort_keys=True)
                    for record in narrow_records).items():
                if count > wide.get(serialised, 0):
                    unreproduced.append(coll)
                    break
        eq(sorted(set(unreproduced)), [],
           "projection invariance: dropping %s removes without changing" % axis)


def check_determinism(text):
    """Repeated runs over identical input produce byte-identical models (5.4).

    Compared as serialised bytes rather than as parsed objects, because that is
    what a consumer stores, hashes and diffs; two dicts can compare equal and
    serialise differently if key order moves, and key order is part of what
    5.4 promises.

    Worth re-checking now rather than when 5.4 was written: --cost re-runs the
    survey internally to price an absent axis (SPEC 3.1), so a model at the
    default materialisation is now produced by four extractions rather than
    one, and any order-dependence among them would surface here.
    """
    for label, axes in (("default", None), ("all-axes", ALL_AXES)):
        runs = []
        for _ in range(2):
            survey = (pss.Survey("reference.ps1", text) if axes is None
                      else pss.Survey("reference.ps1", text, axes=axes))
            runs.append(json.dumps(survey.run().model(), separators=(",", ":"),
                                   ensure_ascii=False).encode("utf-8"))
        check(runs[0] == runs[1],
              "determinism: repeated runs are byte-identical (%s)" % label,
              "two extractions of the same input serialised to %d and %d bytes; "
              "SPEC 5.4 promises byte-identity, which is what a consumer that "
              "diffs or hashes two models depends on"
              % (len(runs[0]), len(runs[1])))


def check_declared_schema(model_def, model_all):
    """Hold the declared path set against what the pinned blob emits, both ways.

    One direction alone is not a schema check. Emitted-but-undeclared catches a
    field that appeared without anyone saying so; declared-but-unemitted catches
    a declaration that has outlived the field it describes. The §13.1
    fingerprint catches neither, because it is taken over the paths a given
    model happens to carry.

    ``optional`` is the only exemption, and it is narrow on purpose: a declared
    path that the pin does not emit passes only if it is marked data-dependent,
    which SPEC 13.3 requires to carry its corpus evidence.
    """
    declared = pss.MODEL_SCHEMA
    emitted_all = set(key_paths(model_all))
    emitted_def = set(key_paths(model_def))

    eq(sorted(emitted_all - set(declared)), [],
       "declared schema: nothing emitted is undeclared (all-axes)")
    eq(sorted(emitted_def - set(declared)), [],
       "declared schema: nothing emitted is undeclared (default)")

    unemitted = sorted(p for p in declared
                       if p not in emitted_all and declared[p] != "optional")
    eq(unemitted, [],
       "declared schema: every non-optional path is emitted at the pin")

    axis_only = sorted(p for p in declared if declared[p] == "axis")
    eq(sorted(p for p in axis_only if p in emitted_def), [],
       "declared schema: axis paths are absent without their axis")
    eq(sorted(p for p in axis_only if p not in emitted_all), [],
       "declared schema: axis paths are present with their axis")

    eq(sorted(set(declared.values())), sorted(set(pss.MODEL_SCHEMA_KINDS)
                                              & set(declared.values())),
       "declared schema: every kind is in the declared vocabulary")


def _field_values(rows, field):
    """Every value of ``field`` across ``rows``, flattening list-valued fields.

    Returns (present, values): ``present`` counts the records carrying the
    field at all, which is what distinguishes "declared and never populated"
    from "declared and empty".
    """
    present = 0
    values = []
    for r in rows:
        if field not in r:
            continue
        present += 1
        v = r[field]
        values.extend(v if isinstance(v, list) else [v])
    return present, values


def check_collection_keys(model_all):
    """Hold SPEC 5.8 against the pin: forms, joins, uniqueness, exercise.

    The declaration is the one thing ``--capabilities`` publishes that a caller
    will act on structurally — it decides which field it joins on. Checking
    only that the code and the document agree would repeat the failure SPEC
    13.2 records twice: a name compared with a name while the behaviour goes
    unexamined. Every claim here is therefore measured against the model.

    ``model_all`` rather than the default materialisation, because several of
    the declared fields exist only under an axis; a field checked at the
    default would read as unpopulated for a reason that is not a defect.
    """
    declared = pss.COLLECTION_KEYS
    collections_in_model = sorted(k for k, v in model_all.items()
                                  if isinstance(v, list))

    eq(sorted(set(collections_in_model) - set(declared)), [],
       "join keys: every list collection in the model is declared")
    eq(sorted(set(declared) - set(collections_in_model)), [],
       "join keys: every declared collection exists in the model")

    symbol_ids = {r["id"] for r in model_all["symbols"]}
    joinable = symbol_ids | {pss.SCRIPT_OWNER}
    forms = {name: re.compile(pat) for name, pat in pss.IDENTIFIER_FORMS.items()}
    exercised = set()

    unpopulated = []
    unresolved = {}
    unmatched = {}
    ambiguous = {}
    non_unique = []

    for coll in sorted(set(declared) & set(collections_in_model)):
        rows = model_all[coll]
        spec = declared[coll]
        for field in tuple(spec["symbol_refs"]) + tuple(spec["identifier_refs"]):
            present, values = _field_values(rows, field)
            if present == 0:
                unpopulated.append("%s.%s" % (coll, field))
                continue
            if field in spec["symbol_refs"]:
                bad = sorted({v for v in values if v not in joinable})
                if bad:
                    unresolved["%s.%s" % (coll, field)] = bad[:3]
            for v in {x for x in values}:
                if v == pss.SCRIPT_OWNER:
                    continue
                hit = [n for n, rx in forms.items() if rx.fullmatch(v)]
                if not hit:
                    # Bounded: an unmatched form is usually unmatched for
                    # thousands of values, and a failure nobody can read is a
                    # failure nobody acts on.
                    seen_bad = unmatched.setdefault("%s.%s" % (coll, field), [])
                    if len(seen_bad) < 3:
                        seen_bad.append(v)
                elif len(hit) > 1:
                    ambiguous.setdefault(v, hit)
                else:
                    exercised.add(hit[0])

        uniq = spec["unique"]
        if uniq:
            seen = {tuple(r.get(f) for f in uniq) for r in rows}
            if len(seen) != len(rows):
                non_unique.append("%s on %s (%d records, %d distinct)"
                                  % (coll, "+".join(uniq), len(rows), len(seen)))

    eq(unpopulated, [],
       "join keys: every declared field is populated at the pin")
    eq(sorted(unresolved.items()), [],
       "join keys: every join value resolves into symbols or <script>")
    eq(sorted(unmatched.items()), [],
       "join keys: every other identifier matches a declared form")
    eq(sorted(ambiguous.items()), [],
       "join keys: the identifier forms are disjoint")
    eq(non_unique, [],
       "join keys: every declared unique key is unique")

    # The reachability question, asked of the form set itself: a form no
    # identifier at the pin belongs to is an enumeration nothing drives, which
    # is the shape of failure SPEC 13.2's last row generalises.
    eq(sorted(set(pss.IDENTIFIER_FORMS) - exercised), [],
       "join keys: every declared identifier form is exercised at the pin")


def _run_pss(args, text=None):
    """Invoke pss.py as a subprocess. The descriptor is checked as shipped."""
    with tempfile.TemporaryDirectory() as d:
        argv = list(args)
        if text is not None:
            p = os.path.join(d, "sample.ps1")
            with open(p, "w", encoding="utf-8") as fh:
                fh.write(text)
            argv = [a.replace("@SCRIPT@", p) for a in argv]
        return subprocess.run(
            [sys.executable, os.path.join(HERE, "pss.py")] + argv,
            capture_output=True, cwd=d)


def _first_difference(a, b):
    """Locate a byte divergence without printing two whole models.

    A failure nobody can read is a failure nobody acts on, and these documents
    run to megabytes on a real script.
    """
    if a == b:
        return ""
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            lo = max(0, i - 40)
            return ("first differs at byte %d of %d/%d: ...%s... vs ...%s..."
                    % (i, len(a), len(b),
                       a[lo:i + 40].decode("utf-8", "replace"),
                       b[lo:i + 40].decode("utf-8", "replace")))
    return "identical prefix, lengths %d vs %d" % (len(a), len(b))


def check_operating_context():
    """Hold SPEC 2.6: two files and nothing else.

    The corpus is reference data for these gates. The tool must not acquire a
    dependency on it, on this repository, or on anything else the originating
    caller does not have - a language model holding two files that are in no
    repository at all. Both legs below exist because "it happens to work off
    repo today" is an observation, and the invariant needs to be a property
    that reddens when it stops holding.

    Structural leg: the module-level imports are read from the source and held
    against an allowlist. A tool that cannot import `subprocess`, `socket` or
    `urllib` has no means of reaching a repository or a network, whatever its
    logic does. Adding an import is then a deliberate act that must move the
    allowlist rather than something that slips in.

    Behavioural leg: the subcommands are run in an empty non-repository
    directory with an environment carrying no executable search path, and the
    output is compared **byte for byte** with the same run made from inside
    this repository. Equality is the check; a bare exit code would pass even if
    the working directory had quietly changed the answer.
    """
    import ast
    with open(PSS, encoding="utf-8") as fh:
        tree = ast.parse(fh.read())
    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(a.name.split(".")[0] for a in node.names)
        elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
            imported.add(node.module.split(".")[0])
    eq(sorted(imported), sorted(PSS_ALLOWED_IMPORTS),
       "operating context: pss.py imports exactly the declared allowlist")

    src = "function Get-Thing { param($Name) $script:Cache = $Name }\n" \
          "function Use-Thing { $x = Get-Thing -Name 'a'; Invoke-Unknown $x }\n"

    # "Inside this repository" has to mean a working directory that actually
    # contains `.git`. `HERE` does not - the tool's own directory is several
    # levels below the root - so a mutation keyed on the working directory
    # would pass unnoticed if the comparison ran from there. Walk up for the
    # root; without one, this leg has nothing to compare against and degrades
    # (SPEC 14.3) rather than passing vacuously.
    root = HERE
    while not os.path.isdir(os.path.join(root, ".git")):
        parent = os.path.dirname(root)
        if parent == root:
            root = None
            break
        root = parent

    def run(cwd, script, argv, env=None):
        return subprocess.run([sys.executable, PSS] + argv + [script],
                              capture_output=True, cwd=cwd, env=env)

    with tempfile.TemporaryDirectory() as bare:
        # Not a repository, and an environment with no executable search path:
        # `git` and `pwsh` are unreachable by name even if installed.
        eq(os.path.isdir(os.path.join(bare, ".git")), False,
           "operating context: the scratch directory is not a repository")
        env = {"PATH": "", "HOME": bare,
               "LC_ALL": os.environ.get("LC_ALL", "C.UTF-8")}

        # The SAME relative filename in both places, so `source.path` is
        # identical and the comparison covers the whole document including the
        # cost block, rather than needing a field carved out of it.
        name = "_ctx_sample.ps1"
        script = os.path.join(bare, name)
        with open(script, "w", encoding="utf-8") as fh:
            fh.write(src)
        in_repo = os.path.join(root, name) if root else None
        if in_repo:
            with open(in_repo, "w", encoding="utf-8") as fh:
                fh.write(src)
        try:
            for label, argv in (("survey", ["survey", "--format", "json"]),
                                ("survey --axes all",
                                 ["survey", "--format", "json", "--axes", "all"])):
                bare_run = run(bare, name, argv, env)
                bare_out = bare_run.stdout
                eq(bare_run.returncode, 0,
                   "operating context: %s succeeds off-repository" % label)
                if not root:
                    continue
                repo_out = run(root, name, argv).stdout
                check(bare_out == repo_out,
                      "operating context: %s is byte-identical off-repository"
                      % label,
                      _first_difference(bare_out, repo_out))

            model = os.path.join(bare, "m.json")
            with open(model, "wb") as fh:
                fh.write(run(bare, name,
                             ["survey", "--format", "json", "--axes", "all"],
                             env).stdout)
            sliced = subprocess.run(
                [sys.executable, PSS, "slice", model, "--axes", "local-sites",
                 "--format", "json"], capture_output=True, cwd=bare, env=env)
            eq(sliced.returncode, 0, "operating context: slice succeeds off-repository")

            caps = subprocess.run([sys.executable, PSS, "--capabilities"],
                                  capture_output=True, cwd=bare, env=env)
            eq(caps.returncode, 0,
               "operating context: --capabilities succeeds off-repository")
            if root:
                from_root = subprocess.run(
                    [sys.executable, PSS, "--capabilities"],
                    capture_output=True, cwd=root).stdout
                check(caps.stdout == from_root,
                      "operating context: --capabilities is byte-identical "
                      "off-repository",
                      _first_difference(caps.stdout, from_root))
        finally:
            if in_repo and os.path.exists(in_repo):
                os.remove(in_repo)


# The producer's own functions. Named rather than discovered, because the
# subtree check below is only as good as its scope: a function that computes a
# digest and is not on this list would not be looked at.
CACHE_PRODUCER_FUNCTIONS = ("build", "cache_main", "cache_git_show",
                            "cache_resolve_entry", "cache_canonical")


def check_cache_generator():
    """Hold SPEC 14.4's producer: it copies identity, it does not compute it.

    The specification had no implementation for long enough that the procedure
    was reconstructed from prose each session, and a shipped cache carried
    `gen_index: null` on all 230 records as a result. So the two properties
    that failed are the two checked here.

    Structurally: the producer must compute no digest of its own. SPEC 14.4
    gives the digest ONE implementation and says a generation script calls it
    and copies the result; a second implementation would let a cache and this
    gate disagree about what was measured. While the producer was a separate
    `build_cache.py` this was `hashlib` being absent from that file's imports.
    In one file that form is unavailable - `hashlib` is legitimately imported
    here, twice over, for the shape fingerprint and for the digest itself - so
    the same requirement is checked over this file's syntax tree instead,
    scoped to the producer's own functions: none of them may name `hashlib`,
    and the digest must have exactly one definition for them to call.

    The scope is the weak point and is stated rather than glossed: a producer
    function omitted from `CACHE_PRODUCER_FUNCTIONS` is not examined. That is
    why the list is checked against the module first - every name on it must
    resolve to a function that exists here.

    Behaviourally: a real two-generation cache is produced and its header
    compared with SPEC 14.4's field set in both directions, and its records
    checked to carry `rev` and `blob` and nothing derivable from position.
    """
    import ast
    with open(os.path.abspath(__file__), encoding="utf-8") as fh:
        tree = ast.parse(fh.read())
    defined = {n.name: n for n in tree.body
               if isinstance(n, ast.FunctionDef)}

    missing = sorted(set(CACHE_PRODUCER_FUNCTIONS) - set(defined))
    eq(missing, [], "cache: the SPEC 14.4 producer exists")
    if missing:
        return

    naming_hashlib = sorted(
        name for name in CACHE_PRODUCER_FUNCTIONS
        for node in ast.walk(defined[name])
        if (isinstance(node, ast.Name) and node.id == "hashlib")
        or (isinstance(node, ast.Attribute)
            and isinstance(node.value, ast.Name)
            and node.value.id == "hashlib"))
    digest_defs = sum(1 for n in tree.body
                      if isinstance(n, ast.FunctionDef)
                      and n.name == "baseline_digest")
    eq([naming_hashlib, digest_defs], [[], 1],
       "cache: the generator computes no digest of its own")

    eq(sorted(HEADER_FIELDS), sorted(SPEC_CACHE_HEADER),
       "cache: the declared header matches the SPEC 14.4 field set")

    # Everything above reads this file and needs nothing else. Everything below
    # produces a real cache, which reads pinned blobs out of git - so it
    # degrades rather than failing where git is absent (SPEC 14.3). This was
    # wrong until now: the behavioural leg ran unguarded and turned the whole
    # gate red on a machine with no git, which is a gate defect and not a
    # finding about the build.
    if not git_available():
        print("-- git unavailable: cache generator run skipped (SPEC 14.3) --")
        return

    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "c.jsonl.gz")
        rc = subprocess.run(
            [sys.executable, os.path.abspath(__file__), "cache", "0001",
             "--limit", "2", "-o", out, "--quiet"],
            capture_output=True, cwd=d)
        eq(rc.returncode, 0, "cache: the generator runs")
        if rc.returncode != 0:
            return
        with gzip.open(out, "rt", encoding="utf-8") as fh:
            lines = [l for l in fh.read().split("\n") if l]
        eq(len(lines), 3, "cache: one header line and one line per generation")
        header = json.loads(lines[0])
        eq(sorted(header), sorted(SPEC_CACHE_HEADER),
           "cache: the emitted header matches the SPEC 14.4 field set")
        eq(header["axes"], sorted(pss.AXES),
           "cache: every axis is materialised, so two caches stay comparable")
        eq(header["model_version"], pss.MODEL_VERSION,
           "cache: the header carries the producing build's model_version")

        records = [json.loads(l) for l in lines[1:]]
        eq(sorted({k for r in records for k in r}), ["blob", "model", "rev"],
           "cache: a generation is identified by rev and blob, not by position")
        eq(sorted({r["model"]["materialization"]["axes"][0] for r in records}),
           [sorted(pss.AXES)[0]],
           "cache: the records carry the materialisation the header declares")

        # The digest is copied, not recomputed: it must equal what the one
        # implementation emits. Still taken from the shipped entry point as a
        # subprocess, because that is what a caller runs.
        emitted = json.loads(subprocess.run(
            [sys.executable, os.path.abspath(__file__),
             "--emit-baseline-digest"], capture_output=True,
            cwd=HERE).stdout.decode("utf-8"))
        eq(header["baseline_digest"], emitted["baseline_digest"],
           "cache: the header's digest is the one --emit-baseline-digest gives")
        eq(header["model_shape"], emitted["model_shape"],
           "cache: the header's shape is the one --emit-baseline-digest gives")


SURVEYOR_FILES = ("CHANGELOG.md", "README.ja.md", "README.md", "SPEC.md",
                  "VERSION", "pss.py", "test_pss.py")


def check_comparator():
    """Hold SPEC 4.9, 5.5 and 6.4 against what the comparator actually does.

    Properties, not a transcription. A gate that recomputed the deltas would
    be a second implementation and would agree with the first by construction;
    what is checked here is what the specification promises a caller.

    The population is built from real fixtures rather than the corpus, so the
    check runs wherever `pss.py` does. Identity of a model with itself is the
    one case whose answer is knowable without reimplementing anything: every
    code must examine its population and find all of it equal.
    """
    with tempfile.TemporaryDirectory() as d:
        script = ("$script:Shared = 1\n"
                  "function Alpha { param([string]$Name) $script:Shared }\n"
                  "function Beta { Alpha -Name 'x' }\n"
                  "Beta\n")
        changed = ("$script:Shared = 1\n"
                   "function Alpha { param([string]$Name, [int]$Extra) "
                   "$script:Shared }\n"
                   "function Gamma { Alpha -Name 'y' }\n"
                   "Gamma\n")
        paths = {}
        for name, text in (("a", script), ("b", changed)):
            out = _run_pss(["survey", "@SCRIPT@", "--format", "json"],
                           text=text)
            paths[name] = os.path.join(d, name + ".json")
            with open(paths[name], "wb") as fh:
                fh.write(out.stdout)

        def run(verb, x, y, *extra):
            r = subprocess.run(
                [sys.executable, os.path.join(HERE, "pss.py"), verb,
                 paths[x], paths[y], "--format", "json"] + list(extra),
                capture_output=True, cwd=d)
            try:
                return r.returncode, json.loads(r.stdout.decode("utf-8"))
            except Exception:
                return r.returncode, None

        rc, same = run("compare", "a", "a")
        eq(rc, 0, "comparator: a model compares against itself")
        if same is None:
            check(False, "comparator: a model compares against itself",
                  "no JSON document")
            return
        eq(same["delta_records"], [],
           "comparator: identity produces no difference record")
        eq(sorted(k for k, v in same["surveyed"].items()
                  if v["examined"] != v["equal"] or v["emitted"]), [],
           "comparator: identity finds every examined subject equal")
        check(any(v["examined"] for v in same["surveyed"].values()),
              "comparator: identity examines a non-empty population",
              "every code examined nothing, so equality is vacuous")

        rc, delta = run("compare", "a", "b")
        eq(rc, 0, "comparator: two models compare")

        # SPEC 6.4: `surveyed` is stated for every evaluated code even when
        # nothing differs, and `examined_subjects` names the population. The
        # two answer different questions and neither substitutes.
        eq(sorted(delta["surveyed"]), sorted(pss.COMPARATOR_CODES),
           "comparator: the tally covers every code this build evaluates")
        check(len(delta["examined_subjects"]) == len(set(delta["examined_subjects"])),
              "comparator: the examined population lists each subject once")
        emitted_subjects = set(r["subject"] for r in delta["delta_records"])
        eq(sorted(s for s in emitted_subjects
                  if s not in set(delta["examined_subjects"])
                  and s != "<script>"), [],
           "comparator: every record's subject is in the examined population")

        # SPEC 4.9: three codes require the caller's assertion of succession
        # and must never appear under `compare`.
        eq(sorted(set(r["code"] for r in delta["delta_records"])
                  & {"PSS8005", "PSS8006", "PSS8007"}), [],
           "comparator: compare emits no succession-only code")

        # SPEC 5.5: cost is excluded, and the exclusion is stated rather than
        # applied silently.
        eq(delta.get("excluded"), ["cost"],
           "comparator: the cost exclusion is stated in the output")

        # SPEC 6.4: provenance. A delta that cannot name its inputs is not a
        # fact about anything.
        check(delta["source_a"]["source"] != delta["source_b"]["source"],
              "comparator: the delta names both models it came from")
        eq(delta["direction"], "unrelated",
           "comparator: compare claims no relation between its inputs")
        rc, traced = run("trace", "a", "b")
        eq([rc, traced["direction"]], [0, "caller-asserted-succession"],
           "comparator: trace carries the caller's succession assertion")

        # SPEC 6.4: --all restores the enumeration without changing the tally,
        # because omitting equal subjects is a choice about size and never
        # about what was measured.
        rc, full = run("compare", "a", "b", "--all")
        eq(full["surveyed"], delta["surveyed"],
           "comparator: --all changes the records, never the tally")
        check(len(full["delta_records"]) > len(delta["delta_records"]),
              "comparator: --all states more than the default does")
        eq(sorted(set(r["code"] for r in delta["delta_records"])
                  - set(r["code"] for r in full["delta_records"])), [],
           "comparator: --all states everything the default did")

        # SPEC 4.7 / 3.2: PSS8008 exists because consumer review found the
        # most review-worthy fact in a real change - a function had stopped
        # being called - carried by no candidate shape. The caller-set
        # difference cannot state it: PSS7004 says which callers moved, not
        # whether any remain.
        uncalled = ("$script:Shared = 1\n"
                    "function Target { $script:Shared }\n"
                    "function Caller { Target }\n"
                    "$table = @{ k = 'Target' }\n"
                    "Caller\n")
        dropped = ("$script:Shared = 1\n"
                   "function Target { $script:Shared }\n"
                   "function Caller { 'inlined' }\n"
                   "$table = @{ k = 'Target' }\n"
                   "Caller\n")
        for name, text in (("u", uncalled), ("v", dropped)):
            out = _run_pss(["survey", "@SCRIPT@", "--format", "json"],
                           text=text)
            paths[name] = os.path.join(d, name + ".json")
            with open(paths[name], "wb") as fh:
                fh.write(out.stdout)

        rc, reach = run("compare", "u", "v")
        eight = [r for r in reach["delta_records"] if r["code"] == "PSS8008"]
        eq([r["subject"] for r in eight], ["function/Target"],
           "comparator: PSS8008 names the function whose PSS4003 presence moved")
        eq([r["detail"]["direction"] for r in eight], ["gained"],
           "comparator: PSS8008 states which way the presence moved")
        # The literal is what separates "no longer called" from "no longer
        # called and no longer named anywhere", and those license different
        # decisions - so both models' values travel with the fact (SPEC 4.4).
        check(eight and eight[0]["detail"].get("named_by_literal_b") is True,
              "comparator: PSS8008 carries the literal-surface evidence",
              "detail was %r" % (eight[0]["detail"] if eight else None))
        check("commit" not in json.dumps(eight),
              "comparator: PSS8008 carries no commit identity",
              "pss.py knows two models and not where they came from (SPEC 2.1)")
        rc, back = run("compare", "v", "u")
        eq([r["detail"]["direction"] for r in back["delta_records"]
            if r["code"] == "PSS8008"], ["lost"],
           "comparator: PSS8008's direction follows the argument order")

        # SPEC 11.3 / 11.4: the load-bearing cells. `downstream-changed` and
        # `dependency-only` name a function whose own text and own call list
        # are untouched and whose reachable set moved - invisible to any
        # textual diff of it, which is the whole reason the codes exist. A
        # three-function chain where the innermost gains a callee produces
        # exactly that for the outermost.
        chain_a = ("function Leaf { 'a' }\n"
                   "function Extra { 'x' }\n"
                   "function Middle { Leaf }\n"
                   "function Outer { Middle }\n"
                   "Outer\n")
        chain_b = ("function Leaf { 'a' }\n"
                   "function Extra { 'x' }\n"
                   "function Middle { Leaf; Extra }\n"
                   "function Outer { Middle }\n"
                   "Outer\n")
        for name, text in (("p", chain_a), ("q", chain_b)):
            out = _run_pss(["survey", "@SCRIPT@", "--format", "json"],
                           text=text)
            paths[name] = os.path.join(d, name + ".json")
            with open(paths[name], "wb") as fh:
                fh.write(out.stdout)

        rc, chain = run("compare", "p", "q")
        by_code = {}
        for r in chain["delta_records"]:
            by_code.setdefault(r["code"], {})[r["subject"]] = r
        eq(by_code.get("PSS7005", {}).get("function/Outer", {})
           .get("detail", {}).get("classification"), "downstream-changed",
           "comparator: PSS7005 names a moved closure behind an unchanged "
           "call list")
        eq(by_code.get("PSS7006", {}).get("function/Outer", {})
           .get("detail", {}).get("classification"), "dependency-only",
           "comparator: PSS7006 names a function no diff of it would show")
        eq(sorted(by_code.get("PSS8003", {}).get("function/Outer", {})
                  .get("detail", {}).get("added", [])), ["function/Extra"],
           "comparator: PSS8003 states which member entered the closure")
        # The closure is derived from `edges`, not read from the axis, so it
        # must answer for a default model - which is what these fixtures are.
        eq(sorted(chain["surveyed"]), sorted(pss.COMPARATOR_CODES),
           "comparator: every code answers for a model with no axis restored")

        # SPEC 4.7: PSS8004 is the half-finished-rename shape - a literal that
        # resolves in one model and matches nothing in the other.
        lit_a = ("function Handler { 'a' }\n"
                 "$route = @{ k = 'Handler' }\n")
        lit_b = ("function Renamed { 'a' }\n"
                 "$route = @{ k = 'Handler' }\n")
        for name, text in (("r", lit_a), ("s", lit_b)):
            out = _run_pss(["survey", "@SCRIPT@", "--format", "json"],
                           text=text)
            paths[name] = os.path.join(d, name + ".json")
            with open(paths[name], "wb") as fh:
                fh.write(out.stdout)
        rc, lit = run("compare", "r", "s")
        stale = [r for r in lit["delta_records"] if r["code"] == "PSS8004"]
        eq([r["subject"] for r in stale], ["Handler"],
           "comparator: PSS8004 names the literal whose resolution moved")
        check(stale and stale[0]["detail"].get("resolves_a")
              == "function/Handler"
              and "resolves_b" not in stale[0]["detail"],
              "comparator: PSS8004 states what it resolved to and that it "
              "no longer does",
              "detail was %r" % (stale[0]["detail"] if stale else None))

        # SPEC 5.5: a precondition failure refuses; it does not compare
        # partially, because a partial delta reads as a complete one.
        with open(paths["a"], encoding="utf-8") as fh:
            model = json.load(fh)
        model["model_version"] = str(int(pss.MODEL_VERSION) + 1)
        other = os.path.join(d, "other.json")
        with open(other, "w", encoding="utf-8") as fh:
            json.dump(model, fh)
        r = subprocess.run(
            [sys.executable, os.path.join(HERE, "pss.py"), "compare",
             paths["a"], other, "--format", "json"],
            capture_output=True, cwd=d)
        check(r.returncode != 0 and not r.stdout.strip(),
              "comparator: a model_version mismatch refuses and emits nothing",
              "exit %d, %d bytes on stdout" % (r.returncode, len(r.stdout)))
        check(b"PSS9005" in r.stderr,
              "comparator: the refusal names PSS9005")


def check_file_inventory():
    """Hold SPEC 14.1's two-file rule, which was normative and ungated.

    This is the check whose absence let the tool reach five `.py` files. §14.1
    said "two `.py` files, matching its siblings" in the first commit; three
    files were added over three days and no patch that added one read the
    sentence, because nothing could fail. The baseline gate grew from 68 checks
    to 156 over the same period and none of them looked at the directory - they
    measure the model, and a file count is not in the model.

    So the inventory is enumerated rather than counted. A count says "three
    where two were expected" and leaves which one open; a list says which file
    is unaccounted for, and it also fails on a file that quietly *disappeared*,
    which a count of the wrong thing can hide.

    Two sources, because they catch different mistakes. `git ls-files` is the
    committed inventory - what the tool *is* to anyone who clones it - and it
    is what a patch about to be sent for review contains. The working directory
    is read as well, for `.py` only, because a third module that has not been
    staged yet is exactly the state a developer is in when the rule matters
    most; `__pycache__` is ignored as a build artefact, not a file of the tool.

    `corpus/` is matched by pattern rather than enumerated. Entries are meant
    to accumulate - that is the point of §14.2 - so listing them would turn
    every registration into a gate edit, and a gate that must be edited to pass
    stops being read. What is held there is that nothing which is *not* an
    entry appears.
    """
    if not git_available():
        print("-- git unavailable: file inventory skipped (SPEC 14.3) --")
        return

    listing = subprocess.run(["git", "ls-files", "."], cwd=HERE,
                             capture_output=True)
    tracked = sorted(p for p in listing.stdout.decode("utf-8").split("\n") if p)

    top = sorted(p for p in tracked if "/" not in p)
    eq(top, sorted(SURVEYOR_FILES), "inventory: the tool's committed files")

    eq(sorted(p for p in top if p.endswith(".py")), ["pss.py", "test_pss.py"],
       "inventory: SPEC 14.1's two `.py` files, and no third")

    stray = sorted(p for p in tracked
                   if "/" in p
                   and not (p.startswith(CORPUS_DIRNAME + "/")
                            and ENTRY_RE.match(p.split("/", 1)[1])))
    eq(stray, [], "inventory: nothing under corpus/ that is not an entry")

    on_disk = sorted(n for n in os.listdir(HERE)
                     if n.endswith(".py") and n != "__pycache__")
    eq(on_disk, ["pss.py", "test_pss.py"],
       "inventory: no unstaged third module in the working directory")


def check_documents():
    """Hold SPEC 13.2's `Docs` row: the document set exists and stays coupled.

    Presence is the least of it. Two couplings are what actually rot: a
    `VERSION` file that stops agreeing with the code it names, and a bilingual
    pair where one side gains a section and the other does not. Both are
    mechanical, so both are checked.

    Lock-step is checked **structurally** - heading levels in order, fenced
    block count - and the limit is stated rather than glossed: this catches a
    section present on one side and absent on the other, and says nothing about
    whether the prose under a matching heading still agrees. A translation
    cannot be gated; a shape can.
    """
    for name in ("README.md", "README.ja.md", "SPEC.md", "CHANGELOG.md",
                 "VERSION"):
        check(os.path.isfile(os.path.join(HERE, name)),
              "docs: %s exists" % name)

    version_file = os.path.join(HERE, "VERSION")
    if os.path.isfile(version_file):
        with open(version_file, encoding="utf-8") as fh:
            eq(fh.read().strip(), pss.__version__,
               "docs: VERSION agrees with pss.__version__")

    pair = {}
    for name in ("README.md", "README.ja.md"):
        path = os.path.join(HERE, name)
        if not os.path.isfile(path):
            return
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        pair[name] = ([len(m.group(1)) for m in
                       re.finditer(r"^(#{1,6}) \S", text, re.M)],
                      text.count("```"))
    eq(pair["README.ja.md"][0], pair["README.md"][0],
       "docs: the bilingual pair carries the same heading structure")
    eq(pair["README.ja.md"][1], pair["README.md"][1],
       "docs: the bilingual pair carries the same fenced-block count")


def check_neutral_naming():
    """Hold the bounded part of SPEC 1.3's naming rule.

    A name on the interface states what was observed, not what the caller
    should conclude. Most of that rule is a matter of judgement and cannot be
    mechanised; what CAN be mechanised is that a specific set of words does not
    come back. So this is a denylist over exactly two surfaces - the fact-code
    descriptions and the subcommand help strings - and its limit is stated
    rather than glossed: it stops known words from returning and detects
    nothing expressed in a word nobody has listed.

    SPEC prose is deliberately out of scope. It discusses judgement legitimately
    - the rule above has to be able to say the word "broken" in order to explain
    why a code must not.
    """
    surfaces = {}
    for code, text in pss.FACTS.items():
        surfaces["FACTS[%s]" % code] = text
    parser = pss.build_parser()
    sub = [a for a in parser._subparsers._group_actions
           if isinstance(a, argparse._SubParsersAction)][0]
    for choice in sorted(sub.choices):
        help_text = next((c.help for c in sub._choices_actions
                          if c.dest == choice), "") or ""
        surfaces["help[%s]" % choice] = help_text

    found = sorted(
        "%s: %s" % (where, word)
        for where, text in surfaces.items()
        for word in JUDGEMENT_WORDS
        if re.search(r"\b%s\b" % word, text, re.I))
    eq(found, [], "neutral naming: no judgement word on the fact or verb surface")

    # The denylist is only meaningful if it is actually applied to something.
    check(len(surfaces) >= len(pss.FACTS) + 3,
          "neutral naming: the denylist covers every code and every subcommand",
          "%d surfaces for %d codes" % (len(surfaces), len(pss.FACTS)))


def check_capability_descriptor():
    """Hold the SPEC 3.1 descriptor against the declarations and the build.

    Two different failures are possible and both are checked.

    The descriptor may *restate* rather than serialise. Every enumerated block
    is compared with the constant it is supposed to be reading, so a literal
    copied into the descriptor diverges the moment the constant moves - which
    is the entire reason SPEC 13.3 put the schema in the code.

    The descriptor may be *optimistic*. Two of the four machine outputs SPEC
    3.1 requires it to describe do not exist in this build, and they are
    published with ``status: not-implemented``. That mark is a claim about
    behaviour, so it is checked against behaviour: ``compare`` must actually
    refuse, and a usage error under ``--format json`` must actually not be
    JSON. Implementing either without moving its mark reddens this gate, which
    is what makes the mark unable to drift into a lie.
    """
    out = _run_pss(["--capabilities"])
    eq(out.returncode, 0, "descriptor: --capabilities exits 0")
    try:
        doc = json.loads(out.stdout.decode("utf-8"))
    except Exception as exc:
        check(False, "descriptor: --capabilities emits JSON", str(exc))
        return

    eq(doc.get("pss_version"), pss.__version__, "descriptor: pss_version")
    eq(doc.get("model_version"), pss.MODEL_VERSION, "descriptor: model_version")

    # Serialised, not restated: each block against the constant it reads.
    eq(doc.get("facts"), dict(pss.FACTS), "descriptor: fact catalogue")
    eq(doc.get("axes"), dict(pss.AXES), "descriptor: axis vocabulary")
    eq(doc.get("exit_codes"), dict(pss.EXIT_CODES), "descriptor: exit codes")
    eq(doc.get("model_schema"), dict(pss.MODEL_SCHEMA),
       "descriptor: declared model schema")
    eq(doc.get("identifier_forms"), dict(pss.IDENTIFIER_FORMS),
       "descriptor: identifier forms")
    eq(doc.get("script_owner"), pss.SCRIPT_OWNER, "descriptor: script owner")
    eq(doc.get("collection_keys"),
       {c: {f: (list(v[f]) if v[f] else (None if f == "unique" else []))
            for f in pss.COLLECTION_KEY_FIELDS}
        for c, v in pss.COLLECTION_KEYS.items()},
       "descriptor: collection join keys")

    # The subcommand set against the SPEC 3 synopsis, in both directions - the
    # one block the descriptor cannot read from a constant.
    spec_text = open(SPEC, encoding="utf-8").read()
    syn = spec_text[spec_text.find("## 3. Command-line interface"):
                    spec_text.find("### 3.1 ")]
    spec_subs = set(re.findall(r'^pss\.py (\w+) ', syn, re.M))
    eq(sorted(doc.get("subcommands", {})), sorted(spec_subs),
       "descriptor: subcommands agree with the SPEC 3 synopsis")

    eq(doc.get("machine_formats"), list(pss.MACHINE_FORMATS),
       "descriptor: machine formats")
    eq(sorted(set(doc.get("machine_formats", [])) - set(doc.get("formats", []))),
       [], "descriptor: every machine format is an accepted --format value")

    outputs = doc.get("machine_outputs", {})
    eq(sorted(outputs), sorted(pss.MACHINE_OUTPUTS),
       "descriptor: the machine-output inventory")
    eq(sorted(k for k, v in outputs.items()
              if v.get("status") not in pss.MACHINE_OUTPUT_STATUSES), [],
       "descriptor: every output carries a declared status")
    eq(sorted(k for k, v in outputs.items()
              if v.get("status") == "not-implemented" and not v.get("reason")),
       [], "descriptor: every not-implemented output states why")
    eq(sorted(k for k, v in outputs.items()
              if v.get("status") == "implemented" and v.get("reason")),
       [], "descriptor: an implemented output carries no excuse")

    # --- the marks, checked against the build rather than against themselves

    # Both verbs share one comparator, so one mark covers both - and now that
    # the mark reads `implemented`, it is only true while BOTH actually run and
    # emit the shape the descriptor declares. The mark was checked against
    # refusal before the comparator existed; it is checked against production
    # now, which is the same rule applied to the opposite state.
    with tempfile.TemporaryDirectory() as d:
        model = os.path.join(d, "m.json")
        out = _run_pss(["survey", "@SCRIPT@", "--format", "json"],
                       text="function F { $script:v = 1 }\nF\n")
        with open(model, "wb") as fh:
            fh.write(out.stdout)
        produced = {}
        for verb in ("compare", "trace"):
            run = subprocess.run(
                [sys.executable, os.path.join(HERE, "pss.py"), verb,
                 model, model, "--format", "json"],
                capture_output=True, cwd=d)
            try:
                doc_v = json.loads(run.stdout.decode("utf-8"))
            except Exception:
                doc_v = None
            produced[verb] = (run.returncode, doc_v)

    declared = outputs.get("delta_records", {})
    top = tuple(declared.get("shape", {}).get("top_level", ()))
    check(declared.get("status") == "implemented"
          and all(rc == 0 and doc_v is not None
                  for rc, doc_v in produced.values())
          and all(sorted(doc_v) == sorted(top)
                  for _, doc_v in produced.values()),
          "descriptor: the delta mark matches what compare and trace do",
          "declared %r, results %r"
          % (declared.get("status"),
             dict((k, (rc, sorted(dv) if dv else None))
                  for k, (rc, dv) in produced.items())))

    # SPEC 6.4: `surveyed` is the per-code half of 4.6, so a code this build
    # evaluates must appear in every run's tally and a code it does not must
    # be absent. Absence is the signal, and a tally that quietly listed
    # everything would destroy it.
    tallied = produced["compare"][1].get("surveyed", {}) \
        if produced["compare"][1] else {}
    eq(sorted(tallied), sorted(pss.COMPARATOR_CODES),
       "delta: surveyed tallies exactly the codes this build evaluates")
    eq(sorted(k for k, v in tallied.items()
              if sorted(v) != ["emitted", "equal", "examined"]), [],
       "delta: every tally states examined, equal and emitted")

    err_out = _run_pss(["survey", "@SCRIPT@", "--format", "json",
                        "--axes", "no-such-axis"], text="function F { }")
    stderr_is_json = True
    try:
        json.loads(err_out.stderr.decode("utf-8"))
    except Exception:
        stderr_is_json = False
    check(outputs.get("error_payload", {}).get("status") == "not-implemented"
          and err_out.returncode == 2 and not stderr_is_json,
          "descriptor: the error mark matches what a usage error does",
          "declared %r, exit %d, stderr parses as JSON: %s"
          % (outputs.get("error_payload", {}).get("status"),
             err_out.returncode, stderr_is_json))

    ok_out = _run_pss(["survey", "@SCRIPT@", "--format", "json"],
                      text="function F { $x = 1 }")
    model_ok = ok_out.returncode == 0
    try:
        emitted = json.loads(ok_out.stdout.decode("utf-8"))
    except Exception:
        emitted = None
        model_ok = False
    check(outputs.get("model", {}).get("status") == "implemented" and model_ok,
          "descriptor: the model mark matches what survey does")
    check(outputs.get("cost_report", {}).get("status") == "implemented"
          and isinstance(emitted, dict) and pss.COST_KEY in emitted,
          "descriptor: the cost mark matches what a model carries")


def check_cost_report(label, model):
    """Re-derive the cost decomposition; do not re-check the block's own sums.

    The first form of this check compared ``sum(by_collection) + envelope``
    against ``model_bytes`` and nothing else. That identity is satisfied by
    construction — ``envelope`` is computed as the remainder, so it absorbs
    whatever the breakdown omits. Dropping a whole collection from the
    breakdown left the check green, which was demonstrated before landing.
    A report that governs itself by reproducibility must be reconciled against
    an independent derivation, not against its own arithmetic; this is the
    fourth instance in this tool of a check that compared a restatement rather
    than a measurement (SPEC 13.2, ADR 0036).
    """
    cost = model.get(pss.COST_KEY)
    if not cost:
        check(False, "cost report: %s carries a block" % label,
              "SPEC 3.1 embeds the block in every model")
        return

    bare = {k: v for k, v in model.items() if k != pss.COST_KEY}
    expected = {k: (len(v), pss.compact_bytes(v))
                for k, v in bare.items() if isinstance(v, list)}
    reported = {row["collection"]: (row["records"], row["bytes"])
                for row in cost["by_collection"]}
    eq(reported, expected,
       "cost report: every collection priced, by value (%s)" % label)

    total = pss.compact_bytes(bare)
    eq(cost["model_bytes"], total,
       "cost report: model_bytes is the model less the block (%s)" % label)
    eq(cost["envelope"]["bytes"],
       total - sum(size for _, size in expected.values()),
       "cost report: envelope is the stated remainder (%s)" % label)
    eq(cost["source_sha256"], model["source"]["sha256"],
       "cost report: bound to its input (%s)" % label)
    eq(cost["format"], pss.COST_FORMAT,
       "cost report: names its serialisation (%s)" % label)
    eq(sorted(row["axis"] for row in cost["axis_increment"]), sorted(pss.AXES),
       "cost report: prices every axis in the vocabulary (%s)" % label)


def compare_section(measured, expected, section):
    exp = expected[section]
    got = measured[section]
    if not isinstance(exp, dict):
        eq(got, exp, "baseline %s" % section)
        return
    for key in sorted(exp):
        eq(got.get(key), exp[key], "baseline %s.%s" % (section, key))
    extra = sorted(set(got) - set(exp))
    check(not extra, "baseline %s: no unrecorded key" % section,
          "the model emits %s, which Appendix B.8 does not record - an "
          "unrecorded figure is one nothing re-derives" % extra)


# ------------------------------------------------------- synthetic fixtures

FIXTURES = [
    # (source, description, expected (code, role) multiset over the named var)
    ("$score -= 10000", "compound `-=` is a write, not a reference",
     "score", "PSS2002", "write"),
    ("$a /= 2", "compound `/=` is a write", "a", "PSS2002", "write"),
    ("$a ??= 1", "compound `??=` is a write", "a", "PSS2002", "write"),
    ("$a += 1", "compound `+=` is a write", "a", "PSS2002", "write"),
    ("$a = 1", "plain `=` is a write", "a", "PSS2002", "write"),
    ("[int]$a = 1", "type-conversion left-hand side is a write",
     "a", "PSS2002", "write"),
]


def run_fixtures():
    """Rules that have actually bitten, kept runnable without a corpus."""
    for src, label, name, code, role in FIXTURES:
        body = "function Test-Fixture {\n    %s\n}\n" % src
        model = pss.Survey("fixture.ps1", body, axes=["local-sites"]).run().model()
        hits = [r for r in model["local_variables"]
                if r.get("record") == "reference"
                and r.get("name", "").lower() == name]
        check(any(r.get("code") == code and r.get("role") == role
                  for r in hits),
              "fixture: %s" % label,
              "records for $%s: %r" % (name, [(r.get("code"), r.get("role"))
                                              for r in hits]))

    # The member-name exclusions, including the dynamic form that reaches the
    # same corruption without matching either static exclusion (SPEC 12.2).
    # The subject is declared first: an undeclared variable resolves to PSS9004
    # and never reaches `local_variables`, so the fixture would pass vacuously.
    # Exactly one write is therefore expected - the declaration - and the
    # left-hand-side occurrence must not add a second.
    for tail, label, name in (
            ("$obj.$field = 1", "dynamic member name is read, not declared",
             "field"),
            ("$obj::$field = 1", "dynamic static-member name is read, not "
             "declared", "field"),
            ("$obj.Prop = 1", "static member left-hand side is a reference",
             "obj"),
            ("$obj[0] = 1", "index left-hand side is a reference", "obj"),
    ):
        body = ("function Test-Fixture {\n"
                "    $obj = @{}\n"
                "    $field = 'a'\n"
                "    %s\n"
                "}\n" % tail)
        model = pss.Survey("fixture.ps1", body, axes=["local-sites"]).run().model()
        hits = [r for r in model["local_variables"]
                if r.get("record") == "reference"
                and r.get("name", "").lower() == name.lower()]
        writes = [r for r in hits if r.get("role") == "write"]
        check(len(writes) == 1,
              "fixture: %s" % label,
              "expected exactly the declaration to be a write; records for "
              "$%s: %r" % (name, [(r.get("code"), r.get("role"))
                                  for r in hits]))

    # Tokenizer regressions: the compound-operator rule runs ahead of the word
    # rule, so the word forms that begin with `-` and `/` must be unaffected.
    for src, want in (("Get-Item -Path C:/x", "word"),
                      ("if ($a -eq 1) { }", "word")):
        kinds = {t.kind for t in pss.tokenize(src)
                 if t.text in ("-Path", "-eq", "C:/x", "Get-Item")}
        check(kinds == {want}, "fixture: `%s` still tokenizes as words" % src,
              "kinds: %r" % kinds)


# -------------------------------------------------------- differential (pwsh)

PWSH_PROBE = r"""
$ErrorActionPreference = 'Stop'
$errs = $null; $toks = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($env:PSS_TARGET, [ref]$toks, [ref]$errs)
$auto = @(__AUTO__)
$vars = $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst]}, $true)
$auto_hits = @($vars | Where-Object { $auto -contains $_.VariablePath.UserPath.ToLower() })
$asg = $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst]}, $true)
$var_lhs = @($asg | Where-Object { $_.Left -is [System.Management.Automation.Language.VariableExpressionAst] })
$cvt_lhs = @($asg | Where-Object { $_.Left -is [System.Management.Automation.Language.ConvertExpressionAst] })
$params = $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.ParameterAst]}, $true)
$defaults = @($params | Where-Object { $null -ne $_.DefaultValue })
$funcs = $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]}, $true)
[pscustomobject]@{
  parse_errors  = $errs.Count
  variable_refs = $vars.Count
  automatic     = $auto_hits.Count
  functions     = $funcs.Count
  assign_total  = $asg.Count
  assign_var    = $var_lhs.Count
  assign_cvt    = $cvt_lhs.Count
  param_default = $defaults.Count
} | ConvertTo-Json -Compress
"""


def run_differential(pwsh, text, measured):
    """Confirm the baseline against the reference parser, not against itself.

    Only figures the parser can reach are compared (SPEC 2.3): the counterpart
    of B-II existing at all is that B-I must be reachable by both sides.
    """
    auto = ",".join("'%s'" % n for n in sorted(pss.AUTOMATIC_VARIABLES))
    script = PWSH_PROBE.replace("__AUTO__", auto)
    with tempfile.TemporaryDirectory() as td:
        target = os.path.join(td, "target.ps1")
        with open(target, "w", encoding="utf-8") as fh:
            fh.write(text)
        probe = os.path.join(td, "probe.ps1")
        with open(probe, "w", encoding="utf-8") as fh:
            fh.write(script)
        env = dict(os.environ, PSS_TARGET=target)
        out = subprocess.run([pwsh, "-NoProfile", "-File", probe],
                             capture_output=True, env=env)
    if out.returncode != 0:
        check(False, "differential: reference parser ran",
              out.stderr.decode()[-400:])
        return
    ast = json.loads(out.stdout.decode())

    eq(ast["parse_errors"], 0, "differential: target parses clean")
    eq(measured["counters"]["variable_refs"], ast["variable_refs"],
       "differential: variable references == VariableExpressionAst")
    eq(measured["local_variables"]["PSS2005"], ast["automatic"],
       "differential: PSS2005 == automatic-named VariableExpressionAst")
    eq(measured["symbols"]["total"], ast["functions"],
       "differential: functions == FunctionDefinitionAst")
    # counters.assignments is NOT AssignmentStatementAst (that is B.4, B-II);
    # it is the population the token scanner can see - variable and
    # type-conversion left-hand sides plus parameter defaults. Stating the
    # identity here is what stops the two being compared again.
    eq(measured["counters"]["assignments"],
       ast["assign_var"] + ast["assign_cvt"] + ast["param_default"],
       "differential: counters.assignments == var LHS + convert LHS + "
       "param defaults")
    check(measured["counters"]["assignments"] != ast["assign_total"]
          or ast["assign_total"] == ast["assign_var"] + ast["assign_cvt"]
          + ast["param_default"],
          "differential: counters.assignments is not B.4 'Assignment statements'",
          "the two coincided; the distinction B-II draws would be untestable")


# ------------------------------------------------------------------- main

# ==========================================================================
# derived model cache producer (SPEC 14.4)
#
# The last of the three moves back to the two `.py` files SPEC 14.1 specifies.
# Moved from `build_cache.py`, which existed because 14.4 specified a generator
# that did not exist and the procedure lived in prose in a session handoff.
#
# Two properties are normative rather than incidental, and the move changed how
# one of them is enforced without changing what it enforces. The producer
# computes no identity of its own: it calls `identity_document`, the same one
# `--emit-baseline-digest` prints, so a cache and this gate cannot disagree
# about what was measured. That used to be structural - `hashlib` was absent
# from a separate file and the gate checked it stayed absent - and in one file
# it is checked over this file's own syntax tree instead, on the producer's
# subtree rather than the whole module (`check_cache_generator`).
#
# The other is unchanged: a generation is written as `rev` and `blob`, never a
# position, because ADR 0033 puts identity in the blob and a stored position is
# the copy that can silently disagree with the list it came from.
# ==========================================================================


# SPEC 14.4: the header fields a derived cache must carry. Named here so the
# gate can compare an emitted header against the specification rather than
# against another copy of this list.
HEADER_FIELDS = (
    "axes",
    "baseline_digest",
    "cache_kind",
    "corpus_count",
    "corpus_end_rev",
    "corpus_entry",
    "corpus_start_rev",
    "model_shape",
    "model_version",
    "pss_version",
    "script_path",
    "spec_contract",
)

CACHE_KIND = "pss-raw-cache"
SPEC_CONTRACT = "SPEC 14.4"


def cache_canonical(obj):
    """The cache file's serialisation. NOT `canonical_json`: that one escapes
    non-ASCII and this one does not, so the two produce different bytes for the
    same object. Both are load-bearing - one is the cache format, the other is
    part of what the digest is taken over - so they stay separate."""
    return json.dumps(obj, sort_keys=True, separators=(',', ':'),
                      ensure_ascii=False)


def cache_git_show(root, blob):
    """Read one pinned blob. Decoded as utf-8-sig: the corpus holds PowerShell
    scripts, which carry a BOM by the repository's encoding contract, and a BOM
    left in the text would appear in the model as a character of the source."""
    out = subprocess.run(["git", "-C", root, "cat-file", "-p", blob],
                         capture_output=True)
    if out.returncode != 0:
        raise RuntimeError("git cat-file failed for %s: %s"
                           % (blob, out.stderr.decode("utf-8", "replace").strip()))
    return out.stdout.decode("utf-8-sig")


def cache_resolve_entry(name):
    """Accept an entry number, a filename, or a path. Entry identity is the
    leading four digits (corpus.py's rule); everything after is descriptive."""
    if os.path.isfile(name):
        return name
    stem = os.path.basename(name)
    match = re.match(r"^(\d{4})", stem)
    if not match:
        raise RuntimeError("not an entry number, filename or path: %s" % name)
    number = match.group(1)
    directory = corpus_dir(HERE)
    for candidate in sorted(os.listdir(directory)):
        if candidate.startswith(number) and candidate.endswith(".json"):
            return os.path.join(directory, candidate)
    raise RuntimeError("no corpus entry numbered %s" % number)


def build(entry_path, out_path, limit, root, progress, baseline):
    with open(entry_path, encoding="utf-8") as fh:
        entry = json.load(fh)

    generations = entry["generations"]
    if limit:
        generations = generations[:limit]
    if not generations:
        raise RuntimeError("entry has no generations to survey")

    script_path = entry["script_path"]
    # SPEC 14.4: the producer computes no identity of its own; it calls the
    # one implementation and copies the result.
    identity = identity_document(root, baseline)

    header = {
        "axes": sorted(pss.AXES),
        "baseline_digest": identity["baseline_digest"],
        "cache_kind": CACHE_KIND,
        "corpus_count": len(generations),
        "corpus_end_rev": generations[-1]["rev"],
        "corpus_entry": os.path.basename(entry_path),
        "corpus_start_rev": generations[0]["rev"],
        "model_shape": identity["model_shape"],
        "model_version": identity["model_version"],
        "pss_version": identity["pss_version"],
        "script_path": script_path,
        "spec_contract": SPEC_CONTRACT,
    }
    missing = sorted(set(HEADER_FIELDS) - set(header))
    extra = sorted(set(header) - set(HEADER_FIELDS))
    if missing or extra:
        raise RuntimeError("header does not match SPEC 14.4: missing %s, extra %s"
                           % (missing, extra))

    with gzip.open(out_path, "wt", encoding="utf-8", newline="\n") as out:
        out.write(cache_canonical(header) + "\n")
        for n, gen in enumerate(generations, 1):
            text = cache_git_show(root, gen["blob"])
            model = pss.Survey(script_path, text,
                               axes=sorted(pss.AXES)).run().model()
            # rev and blob only. A position is derivable from this file's own
            # order, and ADR 0033 puts identity in the blob.
            out.write(cache_canonical({"blob": gen["blob"], "rev": gen["rev"],
                                 "model": model}) + "\n")
            if progress and n % 10 == 0:
                sys.stderr.write("  %d/%d\n" % (n, len(generations)))
                sys.stderr.flush()

    return header, len(generations)


def cache_main(argv=None):
    p = argparse.ArgumentParser(
        prog="test_pss.py cache",
        description="produce a derived model cache for one corpus entry "
                    "(SPEC 14.4); the cache is derived data and is never "
                    "committed")
    p.add_argument("entry", help="corpus entry number, filename or path")
    p.add_argument("-o", "--output",
                   help="output path; defaults to "
                        "pss-raw-cache-<number>.jsonl.gz in the "
                        "working directory")
    p.add_argument("--limit", type=int, default=0,
                   help="survey only the first N generations (for exercising "
                        "the generator; not a usable cache)")
    p.add_argument("--quiet", action="store_true", help="no progress on stderr")
    args = p.parse_args(argv)

    root = repo_root()
    if root is None:
        sys.stderr.write("cache: not inside a git repository; the "
                         "corpus is read from git history\n")
        return RC_ERROR

    try:
        entry_path = cache_resolve_entry(args.entry)
        number = re.match(r"^(\d{4})", os.path.basename(entry_path)).group(1)
        out_path = args.output or ("pss-raw-cache-%s.jsonl.gz" % number)
        header, count = build(entry_path, out_path, args.limit, root,
                              not args.quiet, load_baseline())
    except (RuntimeError, KeyError, OSError, ValueError) as exc:
        sys.stderr.write("cache: %s\n" % exc)
        return RC_ERROR

    if not args.quiet:
        sys.stderr.write(
            "wrote %s\n  %d generation(s), model_version %s, "
            "baseline_digest %s\n"
            % (out_path, count, header["model_version"],
               header["baseline_digest"][:16]))
    return RC_OK


# ==========================================================================
# corpus manager (SPEC 14.2, ADR 0033)
#
# Moved here from a separate `corpus.py`, the second of the three moves that
# take this tool back to the two `.py` files SPEC 14.1 specifies. The code is
# unchanged apart from three things, each recorded rather than incidental:
# `main` is `corpus_main`, since this file already has one; `survey_generation`
# calls `pss.Survey` directly instead of re-launching `pss.py`, because the
# surveyor is now importable from the same file and the two paths were measured
# to produce identical models over four generations of entry 0001; and
# `pss_path`/`PSS_RELATIVE`, which existed only to locate the script for that
# subprocess, have no callers left.
#
# `GENERATED_BY` is deliberately NOT re-pointed. Its value is written into the
# committed entry files, which are byte-stable by construction (ADR 0033) -
# byte-stability is what makes growth detection possible at all - so moving the
# name would rewrite two committed artefacts to record a fact about this file
# rather than about the entries.
# ==========================================================================

TOOL_VERSION = "1.0.0"
SCHEMA_VERSION = "1.0"
LIST_TYPE = "pss-corpus-entry"
GENERATED_BY = "quality-tools/powershell-symbol-surveyor/corpus.py"

CORPUS_DIRNAME = "corpus"

# Identity is the leading four digits. A non-digit must follow, otherwise
# "00012-x.json" would silently read as entry 0001 with the descriptive part
# "2-x". The descriptive middle is never interpreted.
ENTRY_RE = re.compile(r"^(\d{4})(?!\d).*\.json$")

GLOB_CHARS = set("*?[]")

HEADER_ORDER = [
    "schema_version",
    "list_type",
    "generated_by",
    "repo",
    "script_path",
    "start_rev",
    "end_rev",
    "count",
]
RECORD_ORDER = ["rev", "date", "blob", "subject"]

RC_OK = 0
RC_FINDINGS = 1
RC_ERROR = 2


class CorpusError(Exception):
    """A refusal. Raised instead of returning a degraded result."""


# --------------------------------------------------------------------------
# git plumbing
# --------------------------------------------------------------------------

def git(repo, *args):
    return subprocess.run(("git",) + args, cwd=repo,
                          capture_output=True, text=True)


def git_ok(repo, *args):
    r = git(repo, *args)
    if r.returncode != 0:
        raise CorpusError("git %s failed: %s"
                          % (" ".join(args), r.stderr.strip()))
    return r.stdout


def repo_name(repo):
    """Best-effort remote-derived name; falls back to the directory name."""
    r = git(repo, "config", "--get", "remote.origin.url")
    url = r.stdout.strip() if r.returncode == 0 else ""
    if url:
        base = url.rstrip("/").rsplit("/", 1)[-1]
        if base.endswith(".git"):
            base = base[:-4]
        if base:
            return base
    return os.path.basename(os.path.abspath(repo))


def blob_at(repo, rev, path):
    """Blob sha for path at rev, or None when the path is absent there."""
    r = git(repo, "rev-parse", "--verify", "--quiet", "%s:%s" % (rev, path))
    sha = r.stdout.strip()
    return sha if r.returncode == 0 and sha else None


def path_at_head(repo, path):
    return blob_at(repo, "HEAD", path) is not None


def enumerate_generations(repo, path, start_rev=None):
    """Chronological generations of path, plus the boundary revs excluded.

    `git log -- <path>` reports the commit that deletes the path as well.  A
    deletion carries no blob, so it is not a generation; it is returned
    separately so the caller can report it instead of dropping it in silence.

    No --follow: the path is fixed for the life of an entry.
    """
    out = git_ok(repo, "log", "--format=%H%x1f%ad%x1f%s", "--date=short",
                 "--", path)
    rows = []
    for line in out.splitlines():
        if not line.strip():
            continue
        parts = line.split("\x1f")
        if len(parts) != 3:
            raise CorpusError("unparsable git log row: %r" % line)
        rows.append(parts)
    rows.reverse()  # git log is newest-first; entries store oldest-first.

    if start_rev:
        full = git_ok(repo, "rev-parse", "--verify", "%s^{commit}"
                      % start_rev).strip()
        idx = next((i for i, r in enumerate(rows) if r[0] == full), None)
        if idx is None:
            raise CorpusError(
                "start-rev %s does not touch %s" % (start_rev, path))
        rows = rows[idx:]

    gens, excluded = [], []
    for rev, date, subject in rows:
        blob = blob_at(repo, rev, path)
        if blob is None:
            excluded.append(rev)
            continue
        gens.append({"rev": rev, "date": date, "blob": blob,
                     "subject": subject})
    return gens, excluded


# --------------------------------------------------------------------------
# entry serialisation
# --------------------------------------------------------------------------

def serialize(doc):
    """Deterministic ena-shaped text: indented header, one record per line.

    Fixed key order, ensure_ascii, LF endings, no timestamp. Regenerating an
    unchanged entry must reproduce the file byte for byte.
    """
    lines = ["{"]
    for key in HEADER_ORDER:
        lines.append("  %s: %s,"
                     % (json.dumps(key), json.dumps(doc[key],
                                                    ensure_ascii=True)))
    lines.append('  "generations": [')
    gens = doc["generations"]
    for i, rec in enumerate(gens):
        body = ", ".join(
            "%s: %s" % (json.dumps(k), json.dumps(rec[k], ensure_ascii=True))
            for k in RECORD_ORDER)
        lines.append("    { %s }%s" % (body, "" if i == len(gens) - 1 else ","))
    lines.append("  ]")
    lines.append("}")
    return "\n".join(lines) + "\n"


def build_doc(repo, script_path, gens, repo_label):
    return {
        "schema_version": SCHEMA_VERSION,
        "list_type": LIST_TYPE,
        "generated_by": GENERATED_BY,
        "repo": repo_label,
        "script_path": script_path,
        "start_rev": gens[0]["rev"],
        "end_rev": gens[-1]["rev"],
        "count": len(gens),
        "generations": gens,
    }


def write_entry(path, doc):
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(serialize(doc))


def load_entry(path):
    with open(path, encoding="utf-8") as fh:
        doc = json.load(fh)
    for key in HEADER_ORDER + ["generations"]:
        if key not in doc:
            raise CorpusError("%s: missing field %r" % (path, key))
    if doc["list_type"] != LIST_TYPE:
        raise CorpusError("%s: list_type is %r, expected %r"
                          % (path, doc["list_type"], LIST_TYPE))
    gens = doc["generations"]
    if not gens:
        raise CorpusError("%s: entry has no generations" % path)
    # end_rev / count duplicate what the records already state. The duplication
    # is deliberate (the header alone shows the range) and is therefore checked
    # rather than trusted.
    if doc["start_rev"] != gens[0]["rev"]:
        raise CorpusError("%s: start_rev does not match the first generation"
                          % path)
    if doc["end_rev"] != gens[-1]["rev"]:
        raise CorpusError("%s: end_rev does not match the last generation"
                          % path)
    if doc["count"] != len(gens):
        raise CorpusError("%s: count says %d, %d generations present"
                          % (path, doc["count"], len(gens)))
    return doc


# --------------------------------------------------------------------------
# entry discovery
# --------------------------------------------------------------------------

def corpus_dir(root):
    return os.path.join(root, CORPUS_DIRNAME)


def discover(root):
    """Return ({number: filepath}, [ignored filenames]).

    A duplicate number is refused: picking one of two entries with the same
    identity would be a silent selection, which is the failure class this tool
    exists to avoid.  Non-conforming files are ignored but reported.
    """
    cdir = corpus_dir(root)
    entries, ignored = {}, []
    if not os.path.isdir(cdir):
        return entries, ignored
    for name in sorted(os.listdir(cdir)):
        full = os.path.join(cdir, name)
        if not os.path.isfile(full):
            ignored.append(name)
            continue
        m = ENTRY_RE.match(name)
        if not m:
            ignored.append(name)
            continue
        num = int(m.group(1))
        if num in entries:
            raise CorpusError(
                "duplicate entry number %04d: %s and %s"
                % (num, os.path.basename(entries[num]), name))
        entries[num] = full
    return entries, ignored


def resolve_entry(root, ident):
    entries, _ = discover(root)
    try:
        num = int(ident)
    except ValueError:
        raise CorpusError("entry id must be a number, got %r" % ident)
    if num not in entries:
        raise CorpusError("no entry %04d" % num)
    return num, entries[num]


def slugify(script_path):
    stem = os.path.splitext(script_path)[0]
    slug = re.sub(r"[^a-z0-9]+", "-", stem.lower()).strip("-")
    return slug or "entry"


def validate_script_path(repo, script_path):
    if os.path.isabs(script_path):
        raise CorpusError("script path must be repository-relative")
    if any(c in GLOB_CHARS for c in script_path):
        raise CorpusError(
            "globs are not accepted: a corpus entry pins exactly one script")
    if not script_path.lower().endswith(".ps1"):
        raise CorpusError("not a PowerShell script: %s" % script_path)
    if os.path.isdir(os.path.join(repo, script_path)):
        raise CorpusError(
            "directories are not accepted: a corpus entry pins one script")


# --------------------------------------------------------------------------
# pss invocation
# --------------------------------------------------------------------------

def survey_generation(repo, root, rec, script_path, tmpdir):
    """Materialise one generation and survey it. A miss is an error.

    Every recorded generation was proven to carry a blob when the entry was
    written, so a failure here means the pin no longer resolves - which must
    surface, never be skipped.
    """
    blob = git(repo, "cat-file", "-p", rec["blob"])
    if blob.returncode != 0:
        raise CorpusError("blob %s unreachable (generation %s)"
                          % (rec["blob"][:8], rec["rev"][:8]))
    src = os.path.join(tmpdir, "s.ps1")
    with open(src, "w", encoding="utf-8", newline="") as fh:
        fh.write(blob.stdout)
    try:
        return pss.Survey(src, pss.read_source(src)).run().model()
    except Exception as exc:                       # noqa: BLE001 - reported, not swallowed
        raise CorpusError("pss survey failed at %s: %s"
                          % (rec["rev"][:8], str(exc)[:200]))


def iter_models(repo, root, doc, limit=0):
    gens = doc["generations"]
    if limit:
        gens = gens[-limit:]
    tmp = tempfile.mkdtemp()
    for rec in gens:
        yield rec, survey_generation(repo, root, rec, doc["script_path"], tmp)


# --------------------------------------------------------------------------
# commands
# --------------------------------------------------------------------------

def cmd_add(args, root):
    repo = os.path.abspath(args.repo)
    validate_script_path(repo, args.script_path)
    gens, excluded = enumerate_generations(repo, args.script_path,
                                           args.start_rev)
    if not gens:
        raise CorpusError("no committed generation of %s" % args.script_path)

    entries, ignored = discover(root)
    num = (max(entries) + 1) if entries else 1
    slug = args.slug or slugify(args.script_path)
    name = "%04d-%s.json" % (num, slug)
    cdir = corpus_dir(root)
    os.makedirs(cdir, exist_ok=True)
    target = os.path.join(cdir, name)
    if os.path.exists(target):
        raise CorpusError("%s already exists" % name)

    doc = build_doc(repo, args.script_path, gens, args.repo_label
                    or repo_name(repo))
    write_entry(target, doc)

    print("added   : %s" % name)
    print("script  : %s" % doc["script_path"])
    print("repo    : %s" % doc["repo"])
    print("range   : %s .. %s" % (doc["start_rev"][:8], doc["end_rev"][:8]))
    print("count   : %d generation(s)" % doc["count"])
    if excluded:
        print("boundary: %d rev(s) touched the path without a blob "
              "(deletion commits, not generations): %s"
              % (len(excluded), ", ".join(r[:8] for r in excluded)))
    if ignored:
        print("ignored : %d non-conforming file(s) in %s/"
              % (len(ignored), CORPUS_DIRNAME))
    print("sealed  : %s" % ("no" if path_at_head(repo, doc["script_path"])
                            else "yes (path absent at HEAD)"))
    return RC_OK


def compare_entry(repo, doc):
    """Compare a stored entry against git now. Returns (findings, fresh)."""
    fresh, _ = enumerate_generations(repo, doc["script_path"],
                                     doc["start_rev"])
    stored = doc["generations"]
    findings = []
    if len(fresh) < len(stored):
        findings.append("history shorter than the entry (%d < %d): rewritten "
                        "or truncated" % (len(fresh), len(stored)))
    n = min(len(stored), len(fresh))
    for i in range(n):
        if stored[i]["rev"] != fresh[i]["rev"]:
            findings.append("generation %d diverges: stored %s, git %s"
                            % (i + 1, stored[i]["rev"][:8],
                               fresh[i]["rev"][:8]))
            break
        if stored[i]["blob"] != fresh[i]["blob"]:
            findings.append("generation %d content differs at %s: stored blob "
                            "%s, git %s" % (i + 1, stored[i]["rev"][:8],
                                            stored[i]["blob"][:8],
                                            fresh[i]["blob"][:8]))
            break
    grown = len(fresh) - len(stored)
    return findings, fresh, grown


def cmd_update(args, root):
    repo = os.path.abspath(args.repo)
    num, path = resolve_entry(root, args.id)
    doc = load_entry(path)
    findings, fresh, grown = compare_entry(repo, doc)
    if findings:
        for f in findings:
            print("REFUSED: %s" % f)
        print("An entry is append-only. Register a new entry instead of "
              "rewriting this one.")
        return RC_ERROR
    if grown <= 0:
        print("%04d: already current (%d generation(s)); nothing to do"
              % (num, doc["count"]))
        return RC_OK
    new_doc = build_doc(repo, doc["script_path"], fresh, doc["repo"])
    write_entry(path, new_doc)
    print("updated : %s" % os.path.basename(path))
    print("appended: %d generation(s) (%d -> %d)"
          % (grown, doc["count"], new_doc["count"]))
    print("end_rev : %s -> %s" % (doc["end_rev"][:8], new_doc["end_rev"][:8]))
    return RC_OK


def cmd_check(args, root):
    repo = os.path.abspath(args.repo)
    entries, ignored = discover(root)
    if not entries:
        print("corpus check: no entries")
        return RC_OK
    total = 0
    for num in sorted(entries):
        path = entries[num]
        doc = load_entry(path)
        findings, _, grown = compare_entry(repo, doc)
        name = os.path.basename(path)
        if findings:
            total += len(findings)
            for f in findings:
                print("FINDING %04d %s: %s" % (num, name, f))
        elif grown > 0:
            total += 1
            print("FINDING %04d %s: %d new generation(s) since the pin "
                  "(run `update %04d` to re-pin)" % (num, name, grown, num))
        else:
            print("ok      %04d %s: %d generation(s), pinned"
                  % (num, name, doc["count"]))
    if ignored:
        print("ignored : %d non-conforming file(s): %s"
              % (len(ignored), ", ".join(ignored)))
    print()
    if total:
        print("corpus check: %d finding(s)" % total)
        return RC_FINDINGS
    print("corpus check: PASS - every entry matches its pin")
    return RC_OK


def cmd_list(args, root):
    repo = os.path.abspath(args.repo)
    entries, ignored = discover(root)
    if not entries:
        print("no corpus entries")
        return RC_OK
    for num in sorted(entries):
        path = entries[num]
        doc = load_entry(path)
        sealed = not path_at_head(repo, doc["script_path"])
        print("%04d  %-6s  %4d gen  %s..%s  repo=%s"
              % (num, "sealed" if sealed else "open", doc["count"],
                 doc["start_rev"][:8], doc["end_rev"][:8], doc["repo"]))
        print("      script : %s" % doc["script_path"])
        print("      file   : %s" % os.path.basename(path))
    if ignored:
        print()
        print("ignored: %d non-conforming file(s): %s"
              % (len(ignored), ", ".join(ignored)))
    return RC_OK


def refs_to(model, fid):
    """Every place the model still mentions this function id or its name."""
    name = fid.split("/", 1)[1] if "/" in fid else fid
    hits = {"edge": 0, "soft": 0, "interp": 0}
    for e in model.get("edges", []):
        if e.get("to") == fid:
            hits["edge"] += e.get("sites", 1)
    for s in model.get("soft_references", []):
        if s.get("matches") == fid or s.get("literal") == name:
            hits["soft"] += 1
    for s in model.get("string_interpolation_references", []):
        if s.get("name") == name:
            hits["interp"] += 1
    return hits


def cmd_deletions(args, root):
    """When a function disappeared, did the model still reference it?

    A residual reference after a deletion is a break the model can see. No
    residual means the deletion was either safe or invisible, and the
    limitations count bounds which. No verdict is produced; counts only.
    """
    repo = os.path.abspath(args.repo)
    num, path = resolve_entry(root, args.id)
    doc = load_entry(path)
    print("entry       : %04d %s" % (num, os.path.basename(path)))
    print("script      : %s" % doc["script_path"])
    print("generations : %d" % doc["count"])
    print()

    prev = prev_rec = None
    stats = {"pairs": 0, "deletions": 0, "dangling": 0, "clean": 0,
             "gen_with_del": 0, "del_with_blindspot": 0}
    findings = []
    for rec, cur in iter_models(repo, root, doc, args.limit):
        if prev is not None:
            stats["pairs"] += 1
            before = {s["id"] for s in prev["symbols"]}
            after = {s["id"] for s in cur["symbols"]}
            removed = sorted(before - after)
            if removed:
                stats["gen_with_del"] += 1
            for fid in removed:
                stats["deletions"] += 1
                h = refs_to(cur, fid)
                if h["edge"] + h["soft"] + h["interp"]:
                    stats["dangling"] += 1
                    findings.append((prev_rec["rev"][:8], rec["rev"][:8], fid,
                                     h, len(prev.get("limitations") or [])))
                else:
                    stats["clean"] += 1
                if prev.get("limitations"):
                    stats["del_with_blindspot"] += 1
        prev, prev_rec = cur, rec

    print("pairs compared            : %d" % stats["pairs"])
    print("generations with deletion : %d" % stats["gen_with_del"])
    print("functions removed         : %d" % stats["deletions"])
    print("  left a visible residual : %d" % stats["dangling"])
    print("  no residual in model    : %d" % stats["clean"])
    print("  removed while the pre-state carried unresolved call sites : %d"
          % stats["del_with_blindspot"])
    if findings:
        print()
        for a, b, fid, h, lim in findings[:25]:
            print("  %s->%s  %-48s edge=%d soft=%d interp=%d  "
                  "(limitations before: %d)"
                  % (a, b, fid.replace("function/", ""), h["edge"], h["soft"],
                     h["interp"], lim))
        if len(findings) > 25:
            print("  ... %d more" % (len(findings) - 25))
    return RC_OK


def cmd_transitions(args, root):
    """Track caller counts for named functions and report the transitions."""
    repo = os.path.abspath(args.repo)
    num, path = resolve_entry(root, args.id)
    doc = load_entry(path)
    targets = [t.lower() for t in args.targets]
    print("entry       : %04d %s" % (num, os.path.basename(path)))
    print("targets     : %d" % len(targets))
    print("generations : %d" % doc["count"])
    print()

    prev = {}
    for rec, model in iter_models(repo, root, doc, args.limit):
        by_name = {}
        for s in model["symbols"]:
            by_name.setdefault(s["name"].lower(), s["id"])
        callers = {}
        for t in targets:
            fid = by_name.get(t)
            callers[t] = (sum(1 for e in model.get("edges", [])
                              if e.get("to") == fid) if fid else -1)
        for t in targets:
            was, now = prev.get(t), callers[t]
            if was is None:
                continue
            if was > 0 and now == 0:
                print("LOST CALLERS    %-30s %s %s  %d -> 0"
                      % (t, rec["rev"][:8], rec["date"], was))
                print("                %s" % rec["subject"][:92])
            elif was >= 0 and now == -1:
                print("DEFINITION GONE %-30s %s %s"
                      % (t, rec["rev"][:8], rec["date"]))
            elif was == -1 and now >= 0:
                print("DEFINED         %-30s %s %s  callers=%d"
                      % (t, rec["rev"][:8], rec["date"], now))
        prev = callers
    print()
    print("final caller counts (-1 = not defined):")
    for t in targets:
        print("  %-32s %d" % (t, prev.get(t, -1)))
    return RC_OK


def cmd_ever_defined(args, root):
    """Names ever defined across the entry, against those present at the end."""
    repo = os.path.abspath(args.repo)
    num, path = resolve_entry(root, args.id)
    doc = load_entry(path)
    ever, head = {}, set()
    for rec, model in iter_models(repo, root, doc, args.limit):
        names = {s["name"] for s in model["symbols"]}
        for n in names:
            ever.setdefault(n.lower(), rec["rev"][:8])
        head = names
    head_lower = {h.lower() for h in head}
    gone = sorted(n for n in ever if n not in head_lower)
    print("entry                     : %04d %s"
          % (num, os.path.basename(path)))
    print("generations               : %d" % doc["count"])
    print("names ever defined        : %d" % len(ever))
    print("names defined at last gen : %d" % len(head))
    print("defined earlier, not last : %d" % len(gone))
    if gone and args.show:
        print()
        for n in gone[:args.show]:
            print("  %-44s first seen %s" % (n, ever[n]))
        if len(gone) > args.show:
            print("  ... %d more" % (len(gone) - args.show))
    return RC_OK


# --------------------------------------------------------------------------
# entry point
# --------------------------------------------------------------------------

def build_parser():
    p = argparse.ArgumentParser(
        prog="test_pss.py corpus",
        description="Corpus manager for the PowerShell Symbol Surveyor.")
    p.add_argument("--version", action="version",
                   version="corpus manager %s" % TOOL_VERSION)
    p.add_argument("--root", default=os.path.dirname(os.path.abspath(__file__)),
                   help="tool directory holding corpus/ (default: alongside "
                        "this script)")
    p.add_argument("--repo", default=".",
                   help="repository whose history supplies the generations")
    sub = p.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("add", help="register a new corpus entry")
    a.add_argument("script_path", help="repository-relative path to one .ps1")
    a.add_argument("--slug", help="descriptive filename part (never read back)")
    a.add_argument("--start-rev", help="begin the entry at this revision")
    a.add_argument("--repo-label", help="override the recorded repo name")
    a.set_defaults(func=cmd_add)

    u = sub.add_parser("update", help="append newly committed generations")
    u.add_argument("id")
    u.set_defaults(func=cmd_update)

    c = sub.add_parser("check", help="compare every entry against git now")
    c.set_defaults(func=cmd_check)

    l = sub.add_parser("list", help="derived view of the registered entries")
    l.set_defaults(func=cmd_list)

    d = sub.add_parser("deletions",
                       help="per-generation function removals and residuals")
    d.add_argument("id")
    d.add_argument("--limit", type=int, default=0,
                   help="survey only the last N generations")
    d.set_defaults(func=cmd_deletions)

    t = sub.add_parser("transitions",
                       help="caller-count transitions for named functions")
    t.add_argument("id")
    t.add_argument("--targets", nargs="+", required=True)
    t.add_argument("--limit", type=int, default=0)
    t.set_defaults(func=cmd_transitions)

    e = sub.add_parser("ever-defined",
                       help="names ever defined vs present at the last "
                            "generation")
    e.add_argument("id")
    e.add_argument("--limit", type=int, default=0)
    e.add_argument("--show", type=int, default=0,
                   help="list up to N names that are no longer defined")
    e.set_defaults(func=cmd_ever_defined)
    return p


def corpus_main(argv=None):
    args = build_parser().parse_args(argv)
    root = os.path.abspath(args.root)
    try:
        return args.func(args, root)
    except CorpusError as exc:
        print("corpus: %s" % exc, file=sys.stderr)
        return RC_ERROR


# ==========================================================================
# corpus self-test (SPEC 14.2, ADR 0033)
#
# Moved here from a separate `test_corpus.py` so that this tool is two `.py`
# files, as SPEC 14.1 has said since the tool was written. The cases are
# unchanged; only the names that collided with this file were renamed
# (`check` -> `cchk`, `git` -> `fixture_git`, `run` -> `corpus_run`).
#
# Fixtures are real git repositories built in a temporary directory, because
# the behaviour under test is git behaviour: renames, deletions, appended
# history and rewritten history. A mock would reproduce the assumptions rather
# than the facts, and the traps this tool exists to avoid were all assumption
# failures. Needing the `git` binary, this section degrades per SPEC 14.3.
# ==========================================================================

def fixture_git(repo, *args, **kw):
    r = subprocess.run(("git",) + args, cwd=repo, capture_output=True,
                       text=True, **kw)
    if r.returncode != 0 and not kw.get("allow_fail"):
        raise RuntimeError("git %s: %s" % (" ".join(args), r.stderr))
    return r


def commit(repo, path, body, message):
    full = os.path.join(repo, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(body)
    fixture_git(repo, "add", "-A")
    fixture_git(repo, "-c", "user.name=T", "-c", "user.email=t@e", "commit",
        "-m", message, "--date=2026-01-01T00:00:00")


_REPO_SEQ = [0]


def make_repo(tmp):
    """A fresh repository per test: shared state would couple the cases."""
    _REPO_SEQ[0] += 1
    repo = os.path.join(tmp, "repo%02d" % _REPO_SEQ[0])
    os.makedirs(repo)
    fixture_git(repo, "init", "-q", "-b", "main")
    return repo


def fn(name, calls=()):
    body = "\n".join("    %s" % c for c in calls)
    return "function %s {\n%s\n}\n" % (name, body or "    $null = 1")


def script(*names):
    return "\n".join(fn(n) for n in names)


def corpus_run(argv):
    """Invoke main() and capture stdout, returning (rc, text)."""
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
        rc = corpus_main(argv)
    return rc, buf.getvalue()


def new_root(tmp, name):
    root = os.path.join(tmp, name)
    os.makedirs(os.path.join(root, "corpus"), exist_ok=True)
    shutil.copy(os.path.join(HERE, "pss.py"), os.path.join(root, "pss.py"))
    return root


# --------------------------------------------------------------------------
# filename identity
# --------------------------------------------------------------------------

def test_filename_rules():
    m = ENTRY_RE.match("0001-anything-at-all.json")
    cchk("filename: leading four digits are the identity",
          m is not None and m.group(1) == "0001")

    cchk("filename: descriptive middle is free-form",
          ENTRY_RE.match("0002-\u00e4-x_Y.z.json") is not None)

    # The digit-boundary trap: without it, 00012 reads as 0001 + "2".
    cchk("filename: a fifth digit is refused, not misread as 0001",
          ENTRY_RE.match("00012-foo.json") is None)

    cchk("filename: fewer than four digits is not an entry",
          ENTRY_RE.match("001-foo.json") is None)
    cchk("filename: non-json is not an entry",
          ENTRY_RE.match("0001-foo.md") is None)
    cchk("filename: bare number with suffix is an entry",
          ENTRY_RE.match("0007.json") is not None)


def test_discovery(tmp):
    root = os.path.join(tmp, "disc")
    cdir = os.path.join(root, "corpus")
    os.makedirs(cdir)
    for n in ["0001-a.json", "0003-b.json", "README.md", "0002-c.json~",
              ".hidden"]:
        open(os.path.join(cdir, n), "w").close()
    entries, ignored = discover(root)
    cchk("discovery: conforming files are entries, keyed by number",
          sorted(entries) == [1, 3], str(sorted(entries)))
    cchk("discovery: non-conforming files are ignored but reported",
          sorted(ignored) == sorted(["README.md", "0002-c.json~", ".hidden"]),
          str(ignored))

    open(os.path.join(cdir, "0001-duplicate.json"), "w").close()
    try:
        discover(root)
        cchk("discovery: duplicate number is refused", False,
              "no error raised")
    except CorpusError as exc:
        cchk("discovery: duplicate number is refused, never silently chosen",
              "duplicate entry number 0001" in str(exc), str(exc))


# --------------------------------------------------------------------------
# refusals
# --------------------------------------------------------------------------

def test_refusals(tmp):
    repo = make_repo(tmp)
    commit(repo, "a/S.ps1", script("Get-A"), "add S")
    os.makedirs(os.path.join(repo, "dir.ps1"), exist_ok=True)
    root = new_root(tmp, "ref")

    rc, out = corpus_run(["--root", root, "--repo", repo, "add", "a/*.ps1"])
    cchk("refuse: a glob is not a corpus entry",
          rc == RC_ERROR and "globs are not accepted" in out, out)

    rc, out = corpus_run(["--root", root, "--repo", repo, "add", "a"])
    cchk("refuse: a non-.ps1 path", rc == RC_ERROR, out)

    rc, out = corpus_run(["--root", root, "--repo", repo, "add", "dir.ps1"])
    cchk("refuse: a directory, even one named like a script",
          rc == RC_ERROR and "one script" in out, out)

    rc, out = corpus_run(["--root", root, "--repo", repo, "add", "/abs/S.ps1"])
    cchk("refuse: an absolute path", rc == RC_ERROR, out)

    rc, out = corpus_run(["--root", root, "--repo", repo, "add", "a/absent.ps1"])
    cchk("refuse: a path with no committed generation",
          rc == RC_ERROR, out)


# --------------------------------------------------------------------------
# add / determinism / rename boundary
# --------------------------------------------------------------------------

def test_add_and_determinism(tmp):
    repo = make_repo(tmp)
    commit(repo, "a/S.ps1", script("Get-A"), "gen 1")
    commit(repo, "a/S.ps1", script("Get-A", "Get-B"), "gen 2")
    commit(repo, "a/S.ps1", script("Get-A", "Get-B", "Get-C"), "gen 3")
    root = new_root(tmp, "add")

    rc, out = corpus_run(["--root", root, "--repo", repo, "add", "a/S.ps1"])
    cchk("add: first entry is numbered 0001",
          rc == 0 and "0001-a-s.json" in out, out)

    path = os.path.join(root, "corpus", "0001-a-s.json")
    doc = load_entry(path)
    cchk("add: every generation is recorded", doc["count"] == 3,
          str(doc["count"]))
    cchk("add: generations are stored oldest-first",
          doc["generations"][0]["date"] <= doc["generations"][-1]["date"])
    cchk("add: header pins agree with the records (checked, not trusted)",
          doc["start_rev"] == doc["generations"][0]["rev"]
          and doc["end_rev"] == doc["generations"][-1]["rev"])
    cchk("add: each record carries an independent blob hash",
          all(len(g["blob"]) == 40 for g in doc["generations"]))

    first = open(path, encoding="utf-8").read()
    rebuilt = serialize(load_entry(path))
    cchk("determinism: re-serialising reproduces the file byte for byte",
          rebuilt == first)
    cchk("determinism: no timestamp or environment stamp is written",
          "generated_at" not in first and "timestamp" not in first)
    cchk("determinism: generated_by names the writer (ena convention)",
          doc["generated_by"] == GENERATED_BY)

    rc, out = corpus_run(["--root", root, "--repo", repo, "add", "a/S.ps1",
                   "--slug", "second-take"])
    cchk("add: the next entry takes the next number",
          rc == 0 and "0002-second-take.json" in out, out)


def test_rename_boundary(tmp):
    """A rename seals the old entry; the deletion commit is not a generation."""
    repo = make_repo(tmp)
    commit(repo, "old/S.ps1", script("Get-A"), "gen 1")
    commit(repo, "old/S.ps1", script("Get-A", "Get-B"), "gen 2")
    os.makedirs(os.path.join(repo, "new"), exist_ok=True)
    fixture_git(repo, "mv", "old/S.ps1", "new/S.ps1")
    fixture_git(repo, "-c", "user.name=T", "-c", "user.email=t@e", "commit",
        "-m", "move S", "--date=2026-01-01T00:00:00")
    commit(repo, "new/S.ps1", script("Get-A", "Get-B", "Get-C"), "gen 4")

    root = new_root(tmp, "ren")
    rc, out = corpus_run(["--root", root, "--repo", repo, "add", "old/S.ps1",
                   "--slug", "old-path"])
    doc_old = load_entry(os.path.join(root, "corpus",
                                             "0001-old-path.json"))
    cchk("rename: the deletion commit is excluded from the generations",
          doc_old["count"] == 2, str(doc_old["count"]))
    cchk("rename: the excluded boundary rev is reported, not dropped silently",
          "boundary" in out, out)
    cchk("rename: the old entry is sealed (path absent at HEAD)",
          "sealed  : yes" in out, out)

    rc, out = corpus_run(["--root", root, "--repo", repo, "add", "new/S.ps1",
                   "--slug", "new-path"])
    doc_new = load_entry(os.path.join(root, "corpus",
                                             "0002-new-path.json"))
    cchk("rename: the new path becomes a separate, open entry",
          doc_new["count"] == 2 and "sealed  : no" in out,
          "%d / %s" % (doc_new["count"], out))
    cchk("rename: no generation is shared between the two entries",
          not ({g["rev"] for g in doc_old["generations"]}
               & {g["rev"] for g in doc_new["generations"]}))
    cchk("rename: every recorded generation resolves at its pinned path",
          all(blob_at(repo, g["rev"], doc_old["script_path"])
              == g["blob"] for g in doc_old["generations"]))


# --------------------------------------------------------------------------
# growth, rewrite, monotonicity
# --------------------------------------------------------------------------

def test_growth_and_rewrite(tmp):
    repo = make_repo(tmp)
    commit(repo, "a/S.ps1", script("Get-A"), "gen 1")
    commit(repo, "a/S.ps1", script("Get-A", "Get-B"), "gen 2")
    root = new_root(tmp, "grow")
    corpus_run(["--root", root, "--repo", repo, "add", "a/S.ps1", "--slug", "s"])
    path = os.path.join(root, "corpus", "0001-s.json")

    rc, out = corpus_run(["--root", root, "--repo", repo, "check"])
    cchk("check: a pinned entry matching git is clean",
          rc == RC_OK and "PASS" in out, out)

    before = open(path, encoding="utf-8").read()
    rc, out = corpus_run(["--root", root, "--repo", repo, "update", "1"])
    cchk("update: an already-current entry is a no-op",
          rc == 0 and open(path, encoding="utf-8").read() == before, out)

    commit(repo, "a/S.ps1", script("Get-A", "Get-B", "Get-C"), "gen 3")
    rc, out = corpus_run(["--root", root, "--repo", repo, "check"])
    cchk("check: growth is reported as a finding, never applied silently",
          rc == RC_FINDINGS and "1 new generation" in out, out)
    cchk("check: the finding names the command that re-pins it",
          "update 0001" in out, out)

    pre = load_entry(path)["generations"]
    rc, out = corpus_run(["--root", root, "--repo", repo, "update", "1"])
    doc = load_entry(path)
    cchk("update: growth appends and advances end_rev",
          rc == 0 and doc["count"] == 3 and doc["end_rev"]
          == doc["generations"][-1]["rev"], out)
    cchk("update: the stored generations are a strict prefix afterwards "
          "(no earlier measurement is disturbed)",
          doc["generations"][:len(pre)] == pre)

    rc, out = corpus_run(["--root", root, "--repo", repo, "check"])
    cchk("check: clean again after re-pinning", rc == RC_OK, out)

    # Rewrite the history under the entry: amend the tip.
    commit(repo, "a/S.ps1", script("Get-A", "Get-B", "Get-C", "Get-D"),
           "gen 4")
    fixture_git(repo, "-c", "user.name=T", "-c", "user.email=t@e", "commit",
        "--amend", "-m", "gen 4 amended", "--date=2026-01-01T00:00:00")
    fixture_git(repo, "reset", "--hard", "HEAD~2")
    commit(repo, "a/S.ps1", script("Get-A", "Get-Z"), "divergent gen 3")

    rc, out = corpus_run(["--root", root, "--repo", repo, "check"])
    cchk("check: a rewritten history is a finding",
          rc == RC_FINDINGS and "FINDING" in out, out)

    rc, out = corpus_run(["--root", root, "--repo", repo, "update", "1"])
    cchk("update: refuses to absorb a rewritten history",
          rc == RC_ERROR and "append-only" in out, out)
    cchk("update: the refusal points at registering a new entry",
          "new entry" in out, out)


def test_load_integrity(tmp):
    repo = make_repo(tmp)
    commit(repo, "a/S.ps1", script("Get-A"), "gen 1")
    commit(repo, "a/S.ps1", script("Get-A", "Get-B"), "gen 2")
    root = new_root(tmp, "integ")
    corpus_run(["--root", root, "--repo", repo, "add", "a/S.ps1", "--slug", "s"])
    path = os.path.join(root, "corpus", "0001-s.json")

    doc = load_entry(path)
    doc["count"] = 99
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(serialize(doc))
    try:
        load_entry(path)
        cchk("integrity: a count contradicting the records is refused", False)
    except CorpusError as exc:
        cchk("integrity: a count contradicting the records is refused",
              "count says 99" in str(exc), str(exc))

    doc["count"] = 2
    doc["end_rev"] = "0" * 40
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(serialize(doc))
    try:
        load_entry(path)
        cchk("integrity: an end_rev contradicting the records is refused",
              False)
    except CorpusError as exc:
        cchk("integrity: an end_rev contradicting the records is refused",
              "end_rev" in str(exc), str(exc))


# --------------------------------------------------------------------------
# derived views and analysis
# --------------------------------------------------------------------------

def test_list_view(tmp):
    repo = make_repo(tmp)
    commit(repo, "old/S.ps1", script("Get-A"), "gen 1")
    os.makedirs(os.path.join(repo, "new"), exist_ok=True)
    fixture_git(repo, "mv", "old/S.ps1", "new/S.ps1")
    fixture_git(repo, "-c", "user.name=T", "-c", "user.email=t@e", "commit",
        "-m", "move", "--date=2026-01-01T00:00:00")
    root = new_root(tmp, "lst")
    corpus_run(["--root", root, "--repo", repo, "add", "old/S.ps1", "--slug", "old"])
    corpus_run(["--root", root, "--repo", repo, "add", "new/S.ps1", "--slug", "new"])
    open(os.path.join(root, "corpus", "NOTES.md"), "w").close()

    rc, out = corpus_run(["--root", root, "--repo", repo, "list"])
    cchk("list: sealed state is derived, never stored",
          "seal" in out and "open" in out, out)
    cchk("list: no entry file declares its own sealed state",
          all("sealed" not in open(os.path.join(root, "corpus", f),
                                   encoding="utf-8").read()
              for f in os.listdir(os.path.join(root, "corpus"))
              if f.endswith(".json")))
    cchk("list: ignored files are surfaced in the derived view",
          "NOTES.md" in out, out)
    cchk("list: entry identity is not stored inside the entry",
          "\"id\"" not in open(os.path.join(root, "corpus", "0001-old.json"),
                               encoding="utf-8").read())


def test_analysis(tmp):
    repo = make_repo(tmp)
    commit(repo, "a/S.ps1", script("Get-A", "Get-B"), "gen 1")
    commit(repo, "a/S.ps1", script("Get-A"), "gen 2 drops Get-B")
    root = new_root(tmp, "ana")
    corpus_run(["--root", root, "--repo", repo, "add", "a/S.ps1", "--slug", "s"])

    rc, out = corpus_run(["--root", root, "--repo", repo, "deletions", "1"])
    cchk("deletions: a removed function is counted",
          rc == 0 and "functions removed         : 1" in out, out)
    cchk("deletions: counts only, no verdict",
          "verdict" not in out.lower() and "recommend" not in out.lower())

    rc, out = corpus_run(["--root", root, "--repo", repo, "transitions", "1",
                   "--targets", "Get-B"])
    cchk("transitions: a definition disappearing is reported",
          rc == 0 and "DEFINITION GONE" in out, out)

    rc, out = corpus_run(["--root", root, "--repo", repo, "ever-defined", "1"])
    cchk("ever-defined: a name present earlier but not at the end is counted",
          rc == 0 and "defined earlier, not last : 1" in out, out)


def test_unreachable_pin(tmp):
    """A pin that no longer resolves is an error, never a silent skip."""
    repo = make_repo(tmp)
    commit(repo, "a/S.ps1", script("Get-A"), "gen 1")
    root = new_root(tmp, "pin")
    corpus_run(["--root", root, "--repo", repo, "add", "a/S.ps1", "--slug", "s"])
    path = os.path.join(root, "corpus", "0001-s.json")
    doc = load_entry(path)
    doc["generations"][0]["blob"] = "0" * 40
    try:
        for _ in iter_models(repo, root, doc):
            pass
        cchk("pins: an unresolvable blob raises rather than skipping", False)
    except CorpusError as exc:
        cchk("pins: an unresolvable blob raises rather than skipping",
              "unreachable" in str(exc), str(exc))


def run_corpus_selftest():
    tmp = tempfile.mkdtemp(prefix="corpus-selftest-")
    try:
        test_filename_rules()
        test_discovery(tmp)
        test_refusals(tmp)
        test_add_and_determinism(tmp)
        test_rename_boundary(tmp)
        test_growth_and_rewrite(tmp)
        test_load_integrity(tmp)
        test_list_view(tmp)
        test_analysis(tmp)
        test_unreachable_pin(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    # The corpus manager is dispatched before the gate's own parser sees the
    # argument vector, rather than as an argparse subparser. Bare invocation
    # has to keep meaning "run the gate" - that is how the standing battery
    # calls this file (gate-coverage 13) - and an optional subparser sitting
    # beside two optional flags is a subtle thing to get right for no gain.
    if len(sys.argv) > 1 and sys.argv[1] == "corpus":
        return corpus_main(sys.argv[2:])
    if len(sys.argv) > 1 and sys.argv[1] == "cache":
        return cache_main(sys.argv[2:])

    ap = argparse.ArgumentParser(
        description=__doc__,
        epilog="`test_pss.py corpus <subcommand>` runs the corpus manager "
               "(SPEC 14.2) and `test_pss.py cache <entry>` produces a derived "
               "model cache (SPEC 14.4); each takes `--help`. With no "
               "arguments this file runs the gate.")
    ap.add_argument("--pwsh", default=os.environ.get("PSS_PWSH"),
                    help="path to a pwsh binary; enables the differential test")
    ap.add_argument("--emit-baseline-digest", action="store_true",
                    help="print this build's SPEC 14.4 cache-header identity "
                         "and exit; no gate is run")
    args = ap.parse_args()

    baseline = load_baseline()
    if args.emit_baseline_digest:
        return emit_baseline_digest(baseline)

    print("== pss baseline gate ==")
    print("basis: entry %s gen %s blob %s"
          % (baseline["basis"]["corpus_entry"], baseline["basis"]["gen_index"],
             baseline["basis"]["blob"][:12]))

    run_fixtures()

    # Builds its own repositories, so it needs the `git` binary and not this
    # checkout (SPEC 14.3: a missing runtime degrades the gate, never the tool).
    if git_available():
        run_corpus_selftest()
    else:
        print("-- git unavailable: corpus self-test skipped (SPEC 14.3) --")

    # Needs neither git nor pwsh: the descriptor is a property of the build,
    # so it stays checked at every degradation level (SPEC 14.3).
    check_cache_generator()
    check_comparator()
    check_file_inventory()
    check_documents()
    check_neutral_naming()
    check_capability_descriptor()

    # SPEC 2.6, and deliberately alongside the descriptor: both describe the
    # tool as shipped, and neither needs git or pwsh.
    check_operating_context()

    root = repo_root()
    if not root:
        print("\n-- git unavailable: fixtures only (SPEC 14.3) --")
    else:
        text = read_blob(root, baseline["basis"]["blob"])
        model_all = pss.Survey("reference.ps1", text,
                               axes=ALL_AXES).run().model()
        model_def = pss.Survey("reference.ps1", text).run().model()

        measured = measure(model_all)
        for section in ("counters", "symbols", "facts", "edges", "closures",
                        "local_variables", "script_variables",
                        "soft_references", "limitations"):
            compare_section(measured, baseline, section)
        eq(measured["string_interpolation_references"],
           baseline["string_interpolation_references"],
           "baseline string_interpolation_references")

        eq(shape_fingerprint(model_def), baseline["model_shape"]["default"],
           "model shape: default materialisation")
        eq(shape_fingerprint(model_all), baseline["model_shape"]["all-axes"],
           "model shape: all axes")

        block = acceptance_block(model_def, model_all)
        recorded = {k: v for k, v in baseline.items() if k != "basis"}
        check(block == recorded,
              "baseline digest: block equals Appendix B.8 less its basis",
              "the digest a derived cache carries must be taken over exactly "
              "what the document records, or the cache and the document stop "
              "describing the same measurement (SPEC 14.4). Compared by "
              "value, not by key name: a key-set comparison passes while a "
              "wrong figure inside the block goes through. Differing: %s"
              % sorted(k for k in set(block) | set(recorded)
                       if block.get(k) != recorded.get(k)))

        emitted = subprocess.run(
            [sys.executable, os.path.abspath(__file__),
             "--emit-baseline-digest"],
            capture_output=True, cwd=HERE)
        try:
            payload = json.loads(emitted.stdout.decode("utf-8"))
        except Exception:
            payload = {}
        eq(payload.get("baseline_digest"), baseline_digest(block),
           "baseline digest: --emit-baseline-digest agrees with the gate")

        check_version_decision(root, text, model_def, model_all)

        for label, model in (("default", model_def), ("all-axes", model_all)):
            check_cost_report(label, model)

        check_declared_schema(model_def, model_all)

        check_collection_keys(model_all)

        check_determinism(text)

        check_projection_invariance(text, model_all)

        check_channel_agreement(model_all)

        if args.pwsh and os.path.exists(args.pwsh):
            run_differential(args.pwsh, text, measured)
        else:
            print("-- pwsh unavailable: frozen regression only (SPEC 14.3) --")

    total = len(_PASS) + len(_FAIL)
    print("\n%d/%d checks passed" % (len(_PASS), total))
    if _FAIL:
        print("FAILED: %s" % ", ".join(_FAIL))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
