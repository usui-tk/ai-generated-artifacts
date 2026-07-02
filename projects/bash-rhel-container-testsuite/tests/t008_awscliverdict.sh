#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   L1 unit: AWS CLI v2 matrix pure logic (no run)
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; hermetic (no network); shellcheck only for t002.
# ----- Usage examples -------------------------------------------------------
#   bash tests/t008_awscliverdict.sh
#   bash tests/run-all.sh   # runs every tier
# ----- Known limitations ----------------------------------------------------
#   Asserts count failures and continue (harness scope, spec home A.5).
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/t008_awscliverdict.sh - L1 unit: AWS CLI v2 matrix pure logic (no run)
#
# tests/aws_awscli-v2/run-awscli-installtest-matrix.sh decides which AWS CLI v2
# versions install+run per RHEL major on the glibc axis. This tier loads ONLY the
# matrix's pure helpers (no container, no network) - each extracted from its
# column-0 definition to the first column-0 `}` - and asserts them across the
# shapes the matrix feeds them:
#   awscli_ge / awscli_min_glibc / awscli_in_scope / awscli_verdict / python_eol
#   rhel_glibc (measured per-major map) / awscli_band / awscli_expected (model)
# It also checks the reuse-by-copy invariant: list-awscli-releases.sh carries its
# own copies of awscli_ge + awscli_min_glibc, which must match the matrix's.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
MATRIX="${PROJ}/tests/aws_awscli-v2/run-awscli-installtest-matrix.sh"
LISTER="${PROJ}/tests/aws_awscli-v2/list-awscli-releases.sh"

for fn in awscli_ge awscli_min_glibc awscli_in_scope awscli_verdict python_eol rhel_glibc awscli_band awscli_expected; do
  # shellcheck disable=SC1090  # dynamic source of a single extracted function body
  . <(sed -n "/^${fn}()/,/^}/p" "${MATRIX}")
done

if ! declare -F awscli_ge >/dev/null 2>&1 || ! declare -F awscli_verdict >/dev/null 2>&1 \
   || ! declare -F rhel_glibc >/dev/null 2>&1 || ! declare -F awscli_expected >/dev/null 2>&1; then
  t_fail "could not load the pure helpers from run-awscli-installtest-matrix.sh"
  t_done; exit
fi

# --- awscli_ge: dotted numeric compare (versions AND glibc) ------------------
awscli_ge 2.17.50 2.17.49; assert_rc 0 "$?" "2.17.50 >= 2.17.49 (patch decides)"
awscli_ge 2.17.49 2.17.49; assert_rc 0 "$?" "equal -> ge true"
awscli_ge 2.17.49 2.17.50; assert_rc 1 "$?" "2.17.49 < 2.17.50"
awscli_ge 2.27.0 2.9.0;    assert_rc 0 "$?" "numeric (not lexical): 2.27 > 2.9"
awscli_ge 2.34 2.17;       assert_rc 0 "$?" "glibc: 2.34 >= 2.17"
awscli_ge 2.12 2.17;       assert_rc 1 "$?" "glibc: 2.12 < 2.17"

# --- awscli_min_glibc: manylinux floor (boundary 2.17.49/.50) ---------------
assert_eq "2.5"     "$(awscli_min_glibc 2.0.30)"  "2.0.30 -> 2.5 (manylinux1)"
assert_eq "2.5"     "$(awscli_min_glibc 2.17.49)" "2.17.49 -> 2.5 (last of the legacy band)"
assert_eq "2.17"    "$(awscli_min_glibc 2.17.50)" "2.17.50 -> 2.17 (manylinux2014 cutover)"
assert_eq "2.17"    "$(awscli_min_glibc 2.27.0)"  "2.27.0 -> 2.17"
assert_eq "unknown" "$(awscli_min_glibc '')"      "empty -> unknown"
assert_eq "unknown" "$(awscli_min_glibc 2.x)"     "non-numeric -> unknown"
assert_eq "unknown" "$(awscli_min_glibc 2.17.)"   "trailing dot -> unknown"

# --- awscli_in_scope: v2 filter (major == 2) --------------------------------
awscli_in_scope 2.17.49 0; assert_rc 0 "$?" "v2 in scope"
awscli_in_scope 1.40.0 0;  assert_rc 1 "$?" "v1 OUT of scope"

# --- rhel_glibc: measured per-major map (sec 3.2) ---------------------------
assert_eq "2.39" "$(rhel_glibc 10)" "rhel_glibc 10 -> 2.39"
assert_eq "2.34" "$(rhel_glibc 9)"  "rhel_glibc 9 -> 2.34"
assert_eq "2.28" "$(rhel_glibc 8)"  "rhel_glibc 8 -> 2.28"
assert_eq "2.17" "$(rhel_glibc 7)"  "rhel_glibc 7 -> 2.17 (== current floor)"
assert_eq "2.12" "$(rhel_glibc 6)"  "rhel_glibc 6 -> 2.12 (below the current floor)"
assert_eq "unknown" "$(rhel_glibc 5)" "rhel_glibc unknown major -> unknown"

# --- awscli_band: which manylinux band a version ships in -------------------
assert_eq "manylinux1"     "$(awscli_band 2.17.49)" "band: 2.17.49 -> manylinux1"
assert_eq "manylinux2014"  "$(awscli_band 2.17.50)" "band: 2.17.50 -> manylinux2014"
assert_eq "unknown"        "$(awscli_band 2.x)"     "band: bad version -> unknown"

# --- awscli_expected: glibc-model prediction (no run) -----------------------
assert_eq "runs"          "$(awscli_expected 2.34 2.17)" "expected: RHEL9 (2.34) on current -> runs"
assert_eq "runs"          "$(awscli_expected 2.17 2.17)" "expected: RHEL7 at the floor -> runs"
assert_eq "glibc-too-old" "$(awscli_expected 2.12 2.17)" "expected: RHEL6 (2.12) on current -> glibc-too-old"
assert_eq "runs"          "$(awscli_expected 2.12 2.5)"  "expected: RHEL6 on the legacy band -> runs"
assert_eq "unknown"       "$(awscli_expected 2.12 unknown)" "expected: unknown floor -> unknown"

# --- awscli_verdict: EMPIRICAL headline -------------------------------------
assert_eq "runs"            "$(awscli_verdict 2.12 2.5 true)"   "ran=true -> runs"
assert_eq "glibc-too-old"   "$(awscli_verdict 2.12 2.17 false)" "RHEL6 2.12 < 2.17, no run -> glibc-too-old"
assert_eq "unexpected-fail" "$(awscli_verdict 2.34 2.17 false)" "glibc OK but no run -> unexpected-fail"
assert_eq "unexpected-fail" "$(awscli_verdict 2.12 unknown false)" "unknown floor, no run -> unexpected-fail"

# --- python_eol: bundled-CPython minor -> EOL date (static) -----------------
assert_eq "2025-10-31" "$(python_eol 3.9)"    "3.9 -> 2025-10-31"
assert_eq "2027-10-31" "$(python_eol 3.11.9)" "3.11.9 normalizes to 3.11"
assert_eq "unknown"    "$(python_eol '')"     "empty -> unknown"

# --- reuse-by-copy: list-awscli-releases.sh matches the matrix --------------
if [ -f "${LISTER}" ]; then
  # shellcheck disable=SC1090
  . <(sed -n '/^awscli_ge()/,/^}/p' "${LISTER}" | sed 's/^awscli_ge()/awscli_ge_list()/')
  # shellcheck disable=SC1090
  . <(sed -n '/^awscli_min_glibc()/,/^}/p' "${LISTER}" \
        | sed 's/^awscli_min_glibc()/awscli_min_glibc_list()/; s/awscli_ge /awscli_ge_list /')
  if declare -F awscli_min_glibc_list >/dev/null 2>&1; then
    for v in 2.0.0 2.0.30 2.17.49 2.17.50 2.22.0 2.27.0 "" 2.x 2.17.; do
      assert_eq "$(awscli_min_glibc "${v}")" "$(awscli_min_glibc_list "${v}")" \
        "lister awscli_min_glibc matches matrix for '${v}'"
    done
  else
    t_fail "could not load awscli_min_glibc from list-awscli-releases.sh"
  fi
fi

t_done
