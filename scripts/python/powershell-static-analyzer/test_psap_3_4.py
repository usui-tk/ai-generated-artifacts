#!/usr/bin/env python3
"""Self-test fixtures for PSAP0003 / PSAP0004.

Each fixture is a small PowerShell snippet plus the expected number of
PSAP0003 and PSAP0004 hits. We import psa.py as a module and call
analyze_text directly.
"""
import sys
import importlib.util
import tempfile
import os
from pathlib import Path

# Import psa.py as a module
PSA_PATH = Path(__file__).parent / "psa.py"
spec = importlib.util.spec_from_file_location("psa", PSA_PATH)
psa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(psa)


def run_test(name, source, expect_psap0003, expect_psap0004):
    """Run analyze_text with PSAP0003 and PSAP0004 enabled, return (pass, msg)."""
    # Build config that enables only PSAP0003 + PSAP0004 and disables all
    # other defaults that might pollute the output (we want to isolate PSAP).
    cfg = psa.Config()
    cfg.enabled = {k: False for k in cfg.enabled}
    cfg.enabled['PSAP0003'] = True
    cfg.enabled['PSAP0004'] = True
    cfg.min_severity = 'info'

    results = psa.analyze_text(source, cfg)
    psap3 = [r for r in results if r['code'] == 'PSAP0003']
    psap4 = [r for r in results if r['code'] == 'PSAP0004']

    ok = len(psap3) == expect_psap0003 and len(psap4) == expect_psap0004
    status = "PASS" if ok else "FAIL"
    msg = f"  PSAP0003: {len(psap3)}/{expect_psap0003}, PSAP0004: {len(psap4)}/{expect_psap0004}"
    if not ok:
        msg += "\n    Details:"
        for r in psap3 + psap4:
            msg += f"\n      L{r['line']} [{r['code']}] {r['message']}"
    return ok, f"[{status}] {name}\n{msg}"


tests = []

# ---------------------------------------------------------------------------
# PSAP0003 — inline revision-tag comments
# ---------------------------------------------------------------------------

tests.append((
    "PSAP0003: bare colon form",
    "# r42: fixed timezone bug\n$x = 1\n",
    1, 0
))

tests.append((
    "PSAP0003: inclusive-onwards form",
    "# r56+: new behaviour for chipset r56 onwards\n",
    1, 0
))

tests.append((
    "PSAP0003: composite revision form",
    "# r8-update3: refined the heuristic\n",
    1, 0
))

tests.append((
    "PSAP0003: dash-decorated section header",
    "# ---- r42: PHASE INIT SECTION ----\nfunction Init {}\n",
    1, 0
))

tests.append((
    "PSAP0003: parenthesised inline tag",
    "# This was added (r42) for compatibility with v3.5\n",
    1, 0
))

tests.append((
    "PSAP0003: multiple tags across file",
    "# r12: fix A\n$x = 1\n# r15+: fix B\n# (r20) and another\n",
    3, 0
))

tests.append((
    "PSAP0003: prose mention should NOT match",
    "# Before r13, this did X instead of Y\n# In r06 and earlier we used Z\n",
    0, 0
))

tests.append((
    "PSAP0003: rNN in string literal should NOT match",
    "$Script:ScriptVersion = 'chipset-2026.05.18-r60'\n"
    "$model = 'radeon-ai-pro-r9000-series'\n",
    0, 0
))

tests.append((
    "PSAP0003: rNN in here-string should NOT match",
    "$banner = @'\n# r42: this is inside a here-string\n'@\n",
    0, 0
))

# ---------------------------------------------------------------------------
# PSAP0004 — REVISION HISTORY / CHANGELOG comment blocks
# ---------------------------------------------------------------------------

tests.append((
    "PSAP0004: bare REVISION HISTORY",
    "# REVISION HISTORY\n# r1: initial\n# r2: fix\n",
    # PSAP0003 also fires on the inline tags below — that's correct
    2, 1
))

tests.append((
    "PSAP0004: equals-decorated header",
    "# ======== REVISION HISTORY ========\n",
    0, 1
))

tests.append((
    "PSAP0004: CHANGELOG variant",
    "# CHANGELOG\n",
    0, 1
))

tests.append((
    "PSAP0004: VERSION HISTORY with colon",
    "# VERSION HISTORY:\n",
    0, 1
))

tests.append((
    "PSAP0004: dash-decorated CHANGELOG",
    "# ---- CHANGELOG ----\n",
    0, 1
))

tests.append((
    "PSAP0004: case insensitive",
    "# Revision History\n# changelog\n# version history\n",
    0, 3
))

tests.append((
    "PSAP0004: NOT in string literal",
    "$x = '# REVISION HISTORY'\n",
    0, 0
))

# ---------------------------------------------------------------------------
# Combined / interaction tests
# ---------------------------------------------------------------------------

tests.append((
    "Both rules silent on clean code",
    "# This is a clean script header\n"
    "$Script:ScriptVersion = '1.0'\n"
    "function Get-Foo { 'bar' }\n",
    0, 0
))

tests.append((
    "End-of-file REVISION HISTORY block with multiple tags",
    """function Do-Something { 'work' }

# ============================================================
# REVISION HISTORY
# ============================================================
# r1: initial implementation
# r2: bugfix for timezone
# r3+: new feature X
# ---- r4: refactored section ----
""",
    # 4 inline tags + 1 history-block header
    4, 1
))

# ---------------------------------------------------------------------------
# Run all
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("=" * 70)
    print(f"PSAP0003 / PSAP0004 self-test ({len(tests)} cases)")
    print("=" * 70)
    pass_count = 0
    fail_count = 0
    for name, source, e3, e4 in tests:
        ok, msg = run_test(name, source, e3, e4)
        print(msg)
        if ok:
            pass_count += 1
        else:
            fail_count += 1
    print("=" * 70)
    print(f"Result: {pass_count} passed, {fail_count} failed")
    sys.exit(0 if fail_count == 0 else 1)
