#!/usr/bin/env python3
"""T: ConvertFrom-CatalogSupersedenceSection (SPEC B.12).

The Catalog ScopedView 'supersedesInfo' section lists the full chain as
<div>TITLE (KBxxxx)</div> entries and reorders them per request. The parser
must therefore return:
  * All    -- the full, deduplicated, ORDINAL-SORTED KB list (order-stable
              regardless of the Catalog's per-request ordering), and
  * Latest -- the immediate predecessor: the entry with the highest yyyy-MM
              title prefix, ties broken on the highest KB number, falling
              back to the highest KB number when no entry carries a yyyy-MM.
These properties are what make the regenerated baseline deterministic.
"""
import os
import sys
import pathlib

sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from common.ps_invoke import PSSession  # noqa: E402

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "Update-WindowsServerIso.ps1"

def _entry(ym, kb):
    label = f"{ym} Cumulative Update for Windows Server 2019 for x64-based Systems ({kb})" if ym \
            else f"Servicing Stack Update for Windows Server 2019 for x64-based Systems ({kb})"
    return f'<div style="padding-bottom: 0.3em;">\n  {label}\n</div>'

def _section(entries):
    return "".join(entries)

CASES = []

# 1) Same set, two different orders -> identical All (sorted) and Latest.
order_a = _section([_entry("2026-01", "KB5073723"),
                    _entry("2025-11", "KB5068791"),
                    _entry("2026-05", "KB5087538")])
order_b = _section([_entry("2026-05", "KB5087538"),
                    _entry("2026-01", "KB5073723"),
                    _entry("2025-11", "KB5068791")])
EXPECT_ALL = ["KB5068791", "KB5073723", "KB5087538"]
CASES.append(("ordered",  order_a, EXPECT_ALL, "KB5087538"))
CASES.append(("shuffled", order_b, EXPECT_ALL, "KB5087538"))

# 2) No yyyy-MM anywhere -> Latest falls back to the highest KB number.
no_ym = _section([_entry("", "KB5005112"), _entry("", "KB5012170"), _entry("", "KB5009999")])
CASES.append(("no-year-month", no_ym, ["KB5005112", "KB5009999", "KB5012170"], "KB5012170"))

# 3) Empty section -> empty All, empty Latest.
CASES.append(("empty", "", [], ""))

# 4) Mixed widths sort ordinally and dedupe.
mixed = _section([_entry("2026-03", "KB5099999"), _entry("2026-03", "KB5099999"),
                  _entry("2026-04", "KB5100000")])
CASES.append(("dedupe+tie", mixed, ["KB5099999", "KB5100000"], "KB5100000"))


def main():
    passed = failed = 0
    with PSSession(SCRIPT) as ps:
        for name, html, exp_all, exp_latest in CASES:
            r = ps.invoke("ConvertFrom-CatalogSupersedenceSection", Html=html)
            if r is None:
                r = {}
            got_all = list(r.get("All") or [])
            got_latest = r.get("Latest") or ""
            ok_all = got_all == exp_all
            ok_latest = got_latest == exp_latest
            if ok_all and ok_latest:
                passed += 1
                print(f"[PASS] {name}: All={got_all} Latest={got_latest}")
            else:
                failed += 1
                print(f"[FAIL] {name}: All={got_all} (exp {exp_all}) Latest={got_latest} (exp {exp_latest})")

    # Determinism assertion: the two orderings must agree.
    print(f"\nSummary: {passed} passed, {failed} failed, {passed + failed} total")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
