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
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = os.path.join(HERE, "SPEC.md")
sys.path.insert(0, HERE)

import pss  # noqa: E402

ALL_AXES = ["closure-sets", "local-sites", "command-sites"]

_PASS = []
_FAIL = []


def check(ok, label, detail=""):
    (_PASS if ok else _FAIL).append(label)
    print("[%s] %s%s" % ("PASS" if ok else "FAIL", label,
                         ("" if ok else "  -- " + detail)))


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
    out = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=HERE,
                         capture_output=True)
    return out.stdout.decode().strip() if out.returncode == 0 else None


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


def emit_baseline_digest(baseline):
    """Print the SPEC 14.4 cache-header identity for this build, or fail."""
    root = repo_root()
    if not root:
        print(json.dumps({"error": "git-unavailable"}), file=sys.stderr)
        return 2
    text = read_blob(root, baseline["basis"]["blob"])
    model_all = pss.Survey("reference.ps1", text, axes=ALL_AXES).run().model()
    model_def = pss.Survey("reference.ps1", text).run().model()
    block = acceptance_block(model_def, model_all)
    print(canonical_json({
        "baseline_digest": baseline_digest(block),
        "pss_version": pss.__version__,
        "model_version": pss.MODEL_VERSION,
        "model_shape": block["model_shape"],
        "basis": baseline["basis"],
    }))
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

def main():
    ap = argparse.ArgumentParser(description=__doc__)
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
