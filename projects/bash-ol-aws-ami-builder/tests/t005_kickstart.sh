#!/usr/bin/env bash
#==============================================================================
# tests/t005_kickstart.sh - B-T4 kickstart conformance, wired into the runner
# (test pyramid layer L2). Thin wrapper around tests/validate-kickstart.sh so
# the single runner aggregates it; SKIPs cleanly when ksvalidator is absent.
#
# (Tier files are named tN_ by execution order, not by B-T number; the B-T each
# implements is in the TESTING.md coverage ledger.)
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"

KS="${HERE}/validate-kickstart.sh"
out="$(bash "${KS}" 2>&1)"; rc=$?

if printf '%s\n' "${out}" | grep -q '^SKIP:'; then
  t_skip "kickstart conformance: ksvalidator (pykickstart) not installed"
elif [ "${rc}" -eq 0 ] && printf '%s\n' "${out}" | grep -q '^RESULT: PASS'; then
  t_pass "kickstart conformance (validate-kickstart.sh: RESULT PASS)"
else
  t_fail "kickstart conformance failed (rc=${rc}): $(printf '%s' "${out}" | tail -1)"
fi

t_done
