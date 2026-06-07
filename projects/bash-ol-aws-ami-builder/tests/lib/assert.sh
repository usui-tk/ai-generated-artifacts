# shellcheck shell=bash
#==============================================================================
# tests/lib/assert.sh - self-contained assertion + counter helpers
#
# Deliberately framework-free (no bats/shunit2/ShellSpec): this repository's
# tooling is single-file, stdlib-only, self-contained, so the bash test harness
# follows the same policy. This is the bash-idiom analogue of the assertion
# surface a framework would provide; each tier file sources this, runs asserts,
# and ends with t_done. See TESTING.md "Test model (top-down baseline)".
#
# Counters live in the sourcing process; run-all.sh aggregates across tiers by
# parsing each tier's machine-readable "## RESULT pass=.. fail=.. skip=.." line.
#==============================================================================

T_PASS=0
T_FAIL=0
T_SKIP=0

# Colour only on an interactive stdout; off when captured by the runner so the
# "## RESULT" line and the per-assert lines parse cleanly.
_T_RED=''; _T_GRN=''; _T_YLW=''; _T_RST=''
if [ -t 1 ]; then
  _T_RED=$'\033[1;31m'; _T_GRN=$'\033[1;32m'; _T_YLW=$'\033[1;33m'; _T_RST=$'\033[0m'
fi

t_pass() { T_PASS=$((T_PASS + 1)); printf '%s  PASS%s %s\n' "${_T_GRN}" "${_T_RST}" "$1"; }
t_fail() { T_FAIL=$((T_FAIL + 1)); printf '%s  FAIL%s %s\n' "${_T_RED}" "${_T_RST}" "$1"; }
t_skip() { T_SKIP=$((T_SKIP + 1)); printf '%s  SKIP%s %s\n' "${_T_YLW}" "${_T_RST}" "$1"; }

# assert_rc EXPECTED_RC ACTUAL_RC MESSAGE
assert_rc() {
  if [ "$1" -eq "$2" ]; then
    t_pass "$3 (rc=$2)"
  else
    t_fail "$3 (expected rc=$1, got rc=$2)"
  fi
}

# assert_eq EXPECTED ACTUAL MESSAGE
assert_eq() {
  if [ "$1" = "$2" ]; then
    t_pass "$3"
  else
    t_fail "$3 (expected '$1', got '$2')"
  fi
}

# assert_match STRING EXTENDED_REGEX MESSAGE
assert_match() {
  if printf '%s' "$1" | grep -Eq -- "$2"; then
    t_pass "$3"
  else
    t_fail "$3 (no match for /$2/)"
  fi
}

# t_done - print the machine-readable result line and return non-zero on any fail.
# A tier script's last statement should be t_done so its exit status reflects it.
t_done() {
  printf '## RESULT pass=%d fail=%d skip=%d\n' "${T_PASS}" "${T_FAIL}" "${T_SKIP}"
  [ "${T_FAIL}" -eq 0 ]
}
