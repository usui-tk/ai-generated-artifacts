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
"""

import argparse
import collections
import hashlib
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
        },
        "soft_references": {
            "PSS3001": codes("soft_references")["PSS3001"],
            "PSS3002": codes("soft_references")["PSS3002"],
        },
        "string_interpolation_references":
            len(model["string_interpolation_references"]),
        "limitations": {
            "PSS9002": codes("limitations")["PSS9002"],
            "PSS9004": codes("limitations")["PSS9004"],
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
    return block


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
