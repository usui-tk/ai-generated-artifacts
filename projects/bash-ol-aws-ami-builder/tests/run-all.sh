#!/usr/bin/env bash
#==============================================================================
# tests/run-all.sh - single entry runner for the bash-ol-aws-ami-builder suite
#
# The bash-idiom analogue of the PowerShell canon's tests/Invoke-CanonTests.ps1:
# one entry point that runs every host-runnable tier (tests/tN_*.sh), aggregates
# pass/fail/skip, prints a single summary, and exits non-zero if any tier failed.
# Wire this into the project's static/dynamic gate battery.
#
# Each tier is run as its own `bash` subprocess (isolation: a crashing or
# `set -e`-aborting tier cannot take down the runner) and is expected to print a
# trailing "## RESULT pass=.. fail=.. skip=.." line (see tests/lib/assert.sh).
#
# Environment / version dependencies are recorded here at run time (see
# TESTING.md "Environment & version dependencies").
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== bash-ol-aws-ami-builder test suite =="
echo "  bash:       $(bash --version | head -1)"
if command -v shellcheck >/dev/null 2>&1; then
  echo "  shellcheck: $(shellcheck --version 2>/dev/null | awk '/^version:/ {print $2}')"
else
  echo "  shellcheck: (not installed - the B-T2 ShellCheck tier will SKIP)"
fi
if command -v ksvalidator >/dev/null 2>&1; then
  echo "  ksvalidator: present (B-T4 kickstart conformance will run)"
else
  echo "  ksvalidator: (not installed - B-T4 kickstart conformance will SKIP)"
fi
echo

total_pass=0
total_fail=0
total_skip=0
tiers=0
tier_failures=0

for tier in "${HERE}"/t[0-9]*.sh; do
  [ -e "${tier}" ] || continue
  tiers=$((tiers + 1))
  name="$(basename "${tier}")"
  echo "---- ${name} ----"
  out="$(bash "${tier}" 2>&1)"
  rc=$?
  printf '%s\n' "${out}"

  res="$(printf '%s\n' "${out}" | grep '^## RESULT ' | tail -1)"
  p="$(printf '%s' "${res}" | sed -n 's/.*pass=\([0-9][0-9]*\).*/\1/p')"; p="${p:-0}"
  f="$(printf '%s' "${res}" | sed -n 's/.*fail=\([0-9][0-9]*\).*/\1/p')"; f="${f:-0}"
  s="$(printf '%s' "${res}" | sed -n 's/.*skip=\([0-9][0-9]*\).*/\1/p')"; s="${s:-0}"

  total_pass=$((total_pass + p))
  total_fail=$((total_fail + f))
  total_skip=$((total_skip + s))
  if [ "${rc}" -ne 0 ] || [ "${f}" -gt 0 ] || [ -z "${res}" ]; then
    tier_failures=$((tier_failures + 1))
    [ -z "${res}" ] && echo "  (tier produced no RESULT line - treated as failure)"
  fi
  echo
done

echo "======================================="
printf 'SUITE: %d passed, %d skipped, %d failed  (%d tiers, %d tier-failure(s))\n' \
  "${total_pass}" "${total_skip}" "${total_fail}" "${tiers}" "${tier_failures}"
echo "======================================="

if [ "${total_fail}" -eq 0 ] && [ "${tier_failures}" -eq 0 ] && [ "${tiers}" -gt 0 ]; then
  exit 0
fi
exit 1
