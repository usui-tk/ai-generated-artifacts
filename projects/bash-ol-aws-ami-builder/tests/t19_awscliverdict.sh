#!/usr/bin/env bash
#==============================================================================
# tests/t19_awscliverdict.sh - AWS CLI v2 install-test matrix pure logic (no real run)
#
# tests/awscli/run-awscli-installtest-matrix.sh determines which AWS CLI v2
# versions install+run per OL and evaluates them on the glibc axis. This tier
# loads ONLY its four pure helper functions (no container, no network, no
# clean-core) and asserts them across the shapes the matrix feeds them:
#   awscli_ge <a> <b>                 dotted version compare (a >= b; versions & glibc)
#   awscli_min_glibc <version>        documented manylinux floor (2.17 / 2.5 / unknown)
#   awscli_in_scope <ver> <full>      v2 scope filter (major == 2)
#   awscli_verdict <osg> <ming> <ran> per-(OL,version) headline verdict
# It also checks the reuse-by-copy invariant: list-awscli-releases.sh carries its
# own copies of awscli_ge + awscli_min_glibc, which must match the matrix's.
# Pure and host-runnable; self-contained.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
MATRIX="${PROJ}/tests/awscli/run-awscli-installtest-matrix.sh"

# Load ONLY the pure helpers (each from its definition line to the first column-0 '}').
# shellcheck disable=SC1090
. <(sed -n '/^awscli_ge()/,/^}/p'        "${MATRIX}")
# shellcheck disable=SC1090
. <(sed -n '/^awscli_min_glibc()/,/^}/p' "${MATRIX}")
# shellcheck disable=SC1090
. <(sed -n '/^awscli_in_scope()/,/^}/p'  "${MATRIX}")
# shellcheck disable=SC1090
. <(sed -n '/^awscli_verdict()/,/^}/p'   "${MATRIX}")
# shellcheck disable=SC1090
. <(sed -n '/^python_eol()/,/^}/p'       "${MATRIX}")

if ! declare -F awscli_ge >/dev/null 2>&1 || ! declare -F awscli_min_glibc >/dev/null 2>&1 \
   || ! declare -F awscli_in_scope >/dev/null 2>&1 || ! declare -F awscli_verdict >/dev/null 2>&1 \
   || ! declare -F python_eol >/dev/null 2>&1; then
  t_fail "could not load the pure helpers from run-awscli-installtest-matrix.sh"
  t_done; exit
fi

# --- awscli_ge: dotted version compare (AWS CLI versions AND glibc) ----------
awscli_ge 2.17.50 2.17.49; assert_rc 0 "$?" "2.17.50 >= 2.17.49 (patch decides)"
awscli_ge 2.17.49 2.17.49; assert_rc 0 "$?" "equal versions -> ge true"
awscli_ge 2.17.49 2.17.50; assert_rc 1 "$?" "2.17.49 < 2.17.50 -> ge false"
awscli_ge 2.27.0 2.9.0;    assert_rc 0 "$?" "numeric (not lexical) compare: 2.27 > 2.9"
awscli_ge 2.9.0 2.27.0;    assert_rc 1 "$?" "2.9 < 2.27 (numeric)"
awscli_ge 2.17 2.12;       assert_rc 0 "$?" "glibc compare: 2.17 >= 2.12"
awscli_ge 2.12 2.17;       assert_rc 1 "$?" "glibc compare: 2.12 < 2.17"
awscli_ge 2.28 2.17;       assert_rc 0 "$?" "glibc compare: 2.28 >= 2.17"

# --- awscli_min_glibc: documented manylinux floor (boundary at 2.17.49/.50) --
assert_eq "2.5"     "$(awscli_min_glibc 2.0.30)"  "2.0.30 -> 2.5 (old manylinux floor)"
assert_eq "2.5"     "$(awscli_min_glibc 2.17.49)" "2.17.49 -> 2.5 (the documented last for glibc<=2.16)"
assert_eq "2.17"    "$(awscli_min_glibc 2.17.50)" "2.17.50 -> 2.17 (manylinux2014 cutover)"
assert_eq "2.17"    "$(awscli_min_glibc 2.27.0)"  "2.27.0 -> 2.17"
assert_eq "unknown" "$(awscli_min_glibc '')"      "empty -> unknown"
assert_eq "unknown" "$(awscli_min_glibc 2.x)"     "non-numeric -> unknown"
assert_eq "unknown" "$(awscli_min_glibc 2.17.)"   "trailing dot -> unknown"

# --- awscli_in_scope: v2 filter (major == 2) --------------------------------
awscli_in_scope 2.17.49 0; assert_rc 0 "$?" "v2 release is in scope"
awscli_in_scope 2.0.0 0;   assert_rc 0 "$?" "earliest v2 is in scope"
awscli_in_scope 1.40.0 0;  assert_rc 1 "$?" "v1 release is OUT of scope (the package we block)"
awscli_in_scope 2.17.49 1; assert_rc 0 "$?" "--full: v2 still in scope"

# --- awscli_verdict: per-(OL,version) headline ------------------------------
assert_eq "runs"            "$(awscli_verdict 2.12 2.5 true)"   "ran=true -> runs (e.g. OL6 glibc 2.12 on an old build)"
assert_eq "runs"            "$(awscli_verdict 2.28 2.17 true)"  "ran=true -> runs (OL8 on current)"
assert_eq "glibc-too-old"   "$(awscli_verdict 2.12 2.17 false)" "OL6 glibc 2.12 < 2.17 floor, no run -> glibc-too-old"
assert_eq "unexpected-fail" "$(awscli_verdict 2.28 2.17 false)" "glibc OK (2.28>=2.17) but no run -> unexpected-fail"
assert_eq "unexpected-fail" "$(awscli_verdict 2.17 2.17 false)" "glibc at floor (2.17>=2.17) but no run -> unexpected-fail"
assert_eq "unexpected-fail" "$(awscli_verdict 2.12 unknown false)" "unknown floor, no run -> unexpected-fail (not attributable to glibc)"

# --- python_eol: bundled CPython minor -> documented EOL date (static table) --
assert_eq "2023-06-27" "$(python_eol 3.7)"    "3.7 -> 2023-06-27"
assert_eq "2025-10-31" "$(python_eol 3.9)"    "3.9 -> 2025-10-31 (EOL as of 2026)"
assert_eq "2027-10-31" "$(python_eol 3.11)"   "3.11 -> 2027-10-31 (the OL6 cap's Python horizon)"
assert_eq "2027-10-31" "$(python_eol 3.11.9)" "full patch 3.11.9 normalizes to the 3.11 minor"
assert_eq "2030-10-31" "$(python_eol 3.14)"   "3.14 -> 2030-10-31 (latest)"
assert_eq "2030-10-31" "$(python_eol 3.14.5)" "full patch 3.14.5 normalizes to 3.14"
assert_eq "unknown"    "$(python_eol 3.99)"   "unmapped minor -> unknown"
assert_eq "unknown"    "$(python_eol '')"     "empty -> unknown"
assert_eq "unknown"    "$(python_eol abc)"    "non-numeric -> unknown"

# --- reuse-by-copy consistency: list-awscli-releases.sh carries its own copies
# of awscli_ge + awscli_min_glibc (for the release list's min_glibc column);
# assert they match this matrix's across a range of versions.
LISTER="${PROJ}/tests/awscli/list-awscli-releases.sh"
if [ -f "${LISTER}" ]; then
  # shellcheck disable=SC1090
  . <(sed -n '/^awscli_ge()/,/^}/p' "${LISTER}" | sed 's/^awscli_ge()/awscli_ge_list()/')
  # shellcheck disable=SC1090
  . <(sed -n '/^awscli_min_glibc()/,/^}/p' "${LISTER}" \
        | sed 's/^awscli_min_glibc()/awscli_min_glibc_list()/; s/awscli_ge /awscli_ge_list /')
  if declare -F awscli_min_glibc_list >/dev/null 2>&1; then
    for v in 2.0.0 2.0.30 2.17.49 2.17.50 2.22.0 2.27.0 "" 2.x 2.17.; do
      assert_eq "$(awscli_min_glibc "${v}")" "$(awscli_min_glibc_list "${v}")" \
        "list-awscli-releases.sh awscli_min_glibc matches matrix for '${v}'"
    done
  else
    t_fail "could not load awscli_min_glibc from list-awscli-releases.sh"
  fi
fi

t_done
