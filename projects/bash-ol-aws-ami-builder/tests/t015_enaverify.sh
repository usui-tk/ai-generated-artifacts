#!/usr/bin/env bash
#==============================================================================
# tests/t015_enaverify.sh - ENA self-build verify verdict (layer L0/L1, pure unit)
#
# Guards the false-ok regression: `dkms build`/`dkms install` on the EL6 dkms
# (2.4.0) return exit 0 even when the in-guest compile FAILS, and kernel-uek
# ships a stock in-tree ena.ko, so the old verify ("is any ena.ko present?")
# reported status=ok for a build that never produced the requested version
# (e.g. ENA 2.12.0 -> compile error -> stock ena.ko 1.1.2 -> "ok"). The fix
# decides success from the installed MODULE VERSION via the pure function
# `ena_buildtest_verdict`. This tier loads ONLY that function (no full-script
# execution) and asserts the verdict across the real shapes the experiment saw.
#
# Pure and host-runnable; no container, no dkms, no build. Self-contained.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
INST="${PROJ}/install-ena-driver.sh"

# Load ONLY the pure verdict function out of the installer (do not execute the
# rest of the script). The function body runs from its definition line to the
# first column-0 closing brace.
# shellcheck disable=SC1090
. <(sed -n '/^ena_buildtest_verdict()/,/^}/p' "${INST}")

if ! declare -F ena_buildtest_verdict >/dev/null 2>&1; then
  t_fail "could not load ena_buildtest_verdict from install-ena-driver.sh"
  t_done
  exit
fi

# --- success: the requested version was actually built ----------------------
# Pin shape: both the stock in-tree (1.1.2) and the DKMS-built (2.9.1g) present.
out="$(ena_buildtest_verdict 2.9.1 1.1.2 2.9.1g)"; rc=$?
assert_rc 0 "${rc}" "pin built (stock + built both present) -> ok"
assert_eq "2.9.1g" "${out}" "pin built -> reports the BUILT version (2.9.1g), not the stock 1.1.2"

# Order independence (built listed before stock).
out="$(ena_buildtest_verdict 2.9.1 2.9.1g 1.1.2)"; rc=$?
assert_rc 0 "${rc}" "pin built (order-independent) -> ok"

# Exact (no 'g' suffix) match.
out="$(ena_buildtest_verdict 2.2.9 2.2.9)"; rc=$?
assert_rc 0 "${rc}" "exact version match -> ok"
assert_eq "2.2.9" "${out}" "exact match -> reports that version"

# A genuinely-built version ABOVE the historical window still passes: the verdict
# is version-based, not window-based (so a real future build is not rejected).
out="$(ena_buildtest_verdict 2.10.0 1.1.2 2.10.0)"; rc=$?
assert_rc 0 "${rc}" "genuine build above the window (real 2.10.0 present) -> ok"

# --- failure: the build did NOT produce the requested version ---------------
# The exact bug: compile failed, only the stock in-tree 1.1.2 remains.
out="$(ena_buildtest_verdict 2.12.0 1.1.2)"; rc=$?
assert_rc 1 "${rc}" "stock-only (compile failed) -> FAIL, not a false ok"
assert_match "${out}" "matches the requested ENA version 2\.12\.0" "stock-only -> reason names the requested version"
assert_match "${out}" "stock in-tree module remains" "stock-only -> reason explains the stock fallback"

# No ena.ko at all.
out="$(ena_buildtest_verdict 2.12.0)"; rc=$?
assert_rc 1 "${rc}" "no module found -> FAIL"
assert_match "${out}" "no ena.ko found" "no module -> reason says none found"

# A mismatched (but non-stock) version also fails.
out="$(ena_buildtest_verdict 2.9.1 2.8.6g)"; rc=$?
assert_rc 1 "${rc}" "wrong version built (2.8.6 for a 2.9.1 request) -> FAIL"

t_done
