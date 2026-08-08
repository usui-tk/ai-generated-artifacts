#!/usr/bin/env python3
"""T55: psa.py adjudicated-debt baseline gate (offline).

Mechanises the governance TESTING.md section 0 declares in prose: this
project does not run the analyzer at strict zero. It runs it at a
declared baseline of adjudicated debt, and what must hold is that the
measured counts equal the declaration -- no new or increased findings,
and no silently stale declaration either.

Why this contract exists. CI ran psa.py and let the process exit code
decide, which is a strict-zero gate by construction: any adjudicated
finding fails it. That contradicted the governance the project actually
operates under and would have failed every run once the analyzer
reported the declared debt. Reading a declared surface instead of
hardcoding counts follows the same D-first rule the contract set uses
elsewhere: the expected values live in
``.psa-baseline.json`` and are read from it, never duplicated here.

Class: D (declaration-derived) over ``.psa-baseline.json``, with the
measurement supplied by the authoritative analyzer. No count is
hardcoded in this file.

What this asserts:

  1. **Declaration shape.** ``.psa-baseline.json`` exists, carries the
     expected ``SchemaVersion``, and every target row declares a path
     and integer Error/Warning/Info counts.
  2. **Target coverage.** Every declared target file exists.
  3. **Count agreement.** For each target, the analyzer's measured
     summary equals the declared row exactly. An increase is a
     regression; a decrease means the declaration is stale and must be
     lowered in the same change set.

Direction note: exact agreement is deliberately stricter than a
one-sided non-regression check. A one-sided check lets a drained
finding leave a permanently inflated number behind, which is how the
strict-zero declaration this contract replaces became untrue in the
first place.

Run:  python3 tests/psa_debt_baseline_test.py
Deps: none beyond the repository (invokes the sibling analyzer with the
      project's own .psa.config.json, exactly as the gate battery does).
"""
from __future__ import annotations

import json
import pathlib
import subprocess
import sys

SUBPROJECT_ROOT = pathlib.Path(__file__).resolve().parent.parent
REPO_ROOT = SUBPROJECT_ROOT.parent.parent
ANALYZER = REPO_ROOT / "quality-tools" / "powershell-static-analyzer" / "psa.py"
BASELINE_PATH = SUBPROJECT_ROOT / ".psa-baseline.json"
EXPECTED_SCHEMA = "psa-debt-baseline/1.0"
SEVERITIES = (("Error", "errors"), ("Warning", "warnings"), ("Info", "info"))


def check(name, cond, detail, passed, failed):
    if cond:
        print(f"  PASS  {name}")
        return passed + 1, failed
    print(f"  FAIL  {name}: {detail}")
    return passed, failed + 1


def measure(target_name: str):
    """Return (summary_dict, error_detail). Runs the analyzer from the
    project directory so its implicit .psa.config.json is picked up --
    the same invocation contract the gate battery uses."""
    proc = subprocess.run(
        [sys.executable, str(ANALYZER), "--format", "json", target_name],
        cwd=str(SUBPROJECT_ROOT), capture_output=True, text=True, timeout=600)
    # The analyzer exits non-zero when it reports findings; that is the
    # expected state here, so the exit code is not the signal. Only an
    # unparseable payload is a failure of the measurement itself.
    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None, (f"analyzer produced non-JSON output "
                      f"(rc={proc.returncode}): "
                      f"{proc.stdout.strip()[:200]!r} "
                      f"stderr={proc.stderr.strip()[:200]!r}")
    summary = payload.get("summary")
    if not isinstance(summary, dict):
        return None, f"analyzer payload has no summary object: {payload!r}"
    return summary, ""


def main() -> int:
    passed = failed = 0

    print("=" * 72)
    print("T55 psa.py adjudicated-debt baseline gate")
    print("=" * 72)

    passed, failed = check(
        "the declared baseline file is present",
        BASELINE_PATH.is_file(), f"not found: {BASELINE_PATH}",
        passed, failed)
    if not BASELINE_PATH.is_file():
        print(f"\n  Summary: {passed} passed, {failed} failed, "
              f"{passed + failed} total")
        return 1

    passed, failed = check(
        "the analyzer is reachable at its repository path",
        ANALYZER.is_file(), f"not found: {ANALYZER}", passed, failed)

    try:
        declaration = json.loads(BASELINE_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        passed, failed = check("the baseline file parses as JSON", False,
                               str(exc), passed, failed)
        print(f"\n  Summary: {passed} passed, {failed} failed, "
              f"{passed + failed} total")
        return 1

    passed, failed = check(
        f"the baseline declares SchemaVersion {EXPECTED_SCHEMA}",
        declaration.get("SchemaVersion") == EXPECTED_SCHEMA,
        f"declared {declaration.get('SchemaVersion')!r}", passed, failed)

    targets = declaration.get("Targets")
    passed, failed = check(
        "the baseline declares a non-empty Targets list",
        isinstance(targets, list) and len(targets) > 0,
        f"Targets is {type(targets).__name__}", passed, failed)
    if not isinstance(targets, list) or not targets:
        print(f"\n  Summary: {passed} passed, {failed} failed, "
              f"{passed + failed} total")
        return 1

    for row in targets:
        name = row.get("Path", "<unnamed>")
        print(f"\n-- {name}")

        shape_ok = all(isinstance(row.get(k), int) for k, _ in SEVERITIES)
        passed, failed = check(
            f"{name}: declares integer Error/Warning/Info counts",
            shape_ok,
            f"got { {k: row.get(k) for k, _ in SEVERITIES} }",
            passed, failed)

        passed, failed = check(
            f"{name}: carries a written adjudication",
            bool(str(row.get("Adjudication", "")).strip()),
            "Adjudication is empty -- declared debt requires a cause",
            passed, failed)

        target_path = SUBPROJECT_ROOT / name
        exists = target_path.is_file()
        passed, failed = check(
            f"{name}: the declared target exists",
            exists, f"not found: {target_path}", passed, failed)
        if not exists or not shape_ok:
            continue

        summary, err = measure(name)
        if summary is None:
            passed, failed = check(f"{name}: analyzer measurement", False,
                                   err, passed, failed)
            continue

        for declared_key, measured_key in SEVERITIES:
            declared = int(row[declared_key])
            measured = int(summary.get(measured_key, -1))
            if measured > declared:
                detail = (f"measured {measured} > declared {declared} "
                          f"-- REGRESSION: new or increased findings")
            elif measured < declared:
                detail = (f"measured {measured} < declared {declared} "
                          f"-- STALE DECLARATION: lower the baseline row "
                          f"in this change set")
            else:
                detail = ""
            passed, failed = check(
                f"{name}: {declared_key.lower()} count agrees with the "
                f"declaration ({declared})",
                measured == declared, detail, passed, failed)

    print(f"\n  Summary: {passed} passed, {failed} failed, "
          f"{passed + failed} total")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
