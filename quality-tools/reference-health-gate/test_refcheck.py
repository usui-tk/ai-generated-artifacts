#!/usr/bin/env python3
"""Self-test for the reference-health gate (refcheck.py). Stdlib-only; synthetic
fixture trees per case (the D-fixture pattern used across the quality-tools suite)."""

import json
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import refcheck  # noqa: E402


def build_root(*, status_rows_claim=None, manifest_rows=3):
    """A minimal fixture: root README.md + .github/*.md + one workflow + STATUS +
    manifest. Content is injected per case via the returned paths."""
    root = tempfile.mkdtemp(prefix="refcheck_")
    os.makedirs(os.path.join(root, ".github", "workflows"))
    os.makedirs(os.path.join(root, "governance", "project-management"))
    os.makedirs(os.path.join(root, "governance", "state"))
    os.makedirs(os.path.join(root, "docs"))
    with open(os.path.join(root, ".github", "workflows", "good.yml"), "w") as fh:
        fh.write("name: good\n")
    with open(os.path.join(root, "docs", "target.md"), "w") as fh:
        fh.write("# target\n")
    with open(os.path.join(root, "governance", "state", "manifest.jsonl"), "w") as fh:
        for i in range(manifest_rows):
            fh.write(json.dumps({"unit_id": "u%d" % i}) + "\n")
    if status_rows_claim is not None:
        with open(os.path.join(root, refcheck.STATUS_REL), "w") as fh:
            fh.write("# STATUS\n\n| Field | Value |\n|:--|:--|\n"
                     "| Current phase | Manifest **%s rows** live. |\n\n"
                     "Gates green: validator over **%s manifest rows** ok; "
                     "58 helper rows untouched.\n\nHistoric: 42 rows once.\n"
                     % (status_rows_claim, status_rows_claim))
    return root


def write(root, rel, text):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path) or root, exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


_checks = []


def check(name, ok):
    _checks.append((name, ok))
    print("[%s] %s" % ("PASS" if ok else "FAIL", name))


# 1) clean tree -> 0 findings.
root = build_root()
write(root, "README.md", "[ok](./docs/target.md) and [dir](./docs/) plus "
                         "![badge](https://github.com/x/y/actions/workflows/good.yml/badge.svg)\n")
check("clean tree -> 0 findings", refcheck.run(root, quiet=True) == [])
shutil.rmtree(root)

# 2) R1: broken relative link caught (file + directory forms both resolve).
root = build_root()
write(root, "README.md", "[bad](./docs/missing.md)\n")
f = refcheck.run(root, quiet=True)
check("R1 broken relative link caught", len(f) == 1 and f[0].startswith("R1"))
shutil.rmtree(root)

# 3) R1: fragment stripped; absolute/mailto links out of scope.
root = build_root()
write(root, "README.md", "[frag](./docs/target.md#sec) "
                         "[abs](https://example.com/missing) [m](mailto:a@b)\n")
check("R1 fragment stripped + absolute/mailto ignored",
      refcheck.run(root, quiet=True) == [])
shutil.rmtree(root)

# 4) R2: dead workflow reference caught in a badge URL AND a repo path (deduped).
root = build_root()
write(root, "README.md",
      "![b](https://github.com/x/y/actions/workflows/dead.yml/badge.svg) "
      "and `.github/workflows/dead.yml` again\n")
f = refcheck.run(root, quiet=True)
check("R2 dead workflow ref caught once (deduped)",
      len(f) == 1 and f[0].startswith("R2") and "dead.yml" in f[0])
shutil.rmtree(root)

# 5) scope: .github/*.md is scanned; project-level md is NOT (D7).
root = build_root()
write(root, "README.md", "ok\n")
write(root, os.path.join(".github", "pull_request_template.md"),
      "[bad](../docs/missing.md)\n")
write(root, os.path.join("projects", "x", "README.md"), "[bad](./missing.md)\n")
f = refcheck.run(root, quiet=True)
check("scope: .github/*.md scanned, projects/** ignored",
      len(f) == 1 and ".github/pull_request_template.md" in f[0].replace(os.sep, "/"))
shutil.rmtree(root)

# 6) R5: matching row-count claims in both current-truth zones -> green
#    (the historic '42 rows' prose line is deliberately outside the zones).
root = build_root(status_rows_claim=3, manifest_rows=3)
write(root, "README.md", "ok\n")
check("R5 matching claims green (historic prose not probed)",
      refcheck.run(root, quiet=True) == [])
shutil.rmtree(root)

# 7) R5: stale claim caught in BOTH zones (the 2026-07-02 index==body class).
root = build_root(status_rows_claim=83, manifest_rows=84)
write(root, "README.md", "ok\n")
f = refcheck.run(root, quiet=True)
check("R5 stale claim caught per zone",
      len(f) == 2 and all(x.startswith("R5") and "83" in x and "84" in x for x in f))
shutil.rmtree(root)

# 8) R5: '<N> helper rows' style claims are NOT probed (no false positive).
root = build_root(manifest_rows=5)
write(root, refcheck.STATUS_REL,
      "| Current phase | 58 helper rows <-> 58 canon files |\n\n"
      "Gates green: nothing numeric here.\n")
write(root, "README.md", "ok\n")
check("R5 'helper rows' phrasing not probed", refcheck.run(root, quiet=True) == [])
shutil.rmtree(root)

# 9) no STATUS / no manifest (fixture roots) -> R5 degrades to a no-op.
root = build_root()
os.remove(os.path.join(root, "governance", "state", "manifest.jsonl"))
write(root, "README.md", "ok\n")
check("R5 no-op without manifest", refcheck.run(root, quiet=True) == [])
shutil.rmtree(root)

# 9b) R6 (ADR 0031): matching kind-breakdown + project-maturity claims -> green.
root = build_root()
write(root, os.path.join("governance", "state", "manifest.jsonl"),
      json.dumps({"unit_id": "t1", "kind": "tool"}) + "\n"
      + json.dumps({"unit_id": "t2", "kind": "tool"}) + "\n"
      + json.dumps({"unit_id": "p1", "kind": "project",
                    "maturity": "governed"}) + "\n")
write(root, refcheck.STATUS_REL,
      "| Current phase | Manifest **3 rows** = 2 `tool` + 1 `project` "
      "[governed]. |\n\nGates green: 3 manifest rows ok.\n")
write(root, "README.md", "ok\n")
check("R6 matching kind-breakdown + maturity claims green",
      refcheck.run(root, quiet=True) == [])

# 9c) R6: stale kind count AND stale maturity claim -> one finding each
#     (the 2026-07-03 stale-breakdown class, now machine-probed).
write(root, refcheck.STATUS_REL,
      "| Current phase | Manifest **3 rows** = 3 `tool` + 1 `project` "
      "[sandbox]. |\n\nGates green: 3 manifest rows ok.\n")
f = refcheck.run(root, quiet=True)
check("R6 stale kind count + stale maturity claim caught",
      len(f) == 2 and any("`tool`" in x and x.startswith("R6") for x in f)
      and any("[sandbox]" in x and x.startswith("R6") for x in f))
shutil.rmtree(root)

# 10) exit-code contract: main() returns 1 on findings, 0 when clean.
root = build_root()
write(root, "README.md", "[bad](./docs/missing.md)\n")
rc_bad = refcheck.main(["--root", root])
write(root, "README.md", "ok\n")
rc_ok = refcheck.main(["--root", root])
check("exit codes: 1 on findings / 0 clean", rc_bad == 1 and rc_ok == 0)
shutil.rmtree(root)

passed = sum(1 for _, ok in _checks if ok)
print("\n%d/%d checks passed" % (passed, len(_checks)))
sys.exit(0 if passed == len(_checks) else 1)
