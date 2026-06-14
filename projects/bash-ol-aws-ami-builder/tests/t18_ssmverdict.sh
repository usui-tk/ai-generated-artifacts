#!/usr/bin/env bash
#==============================================================================
# tests/t18_ssmverdict.sh - SSM install-test matrix pure logic (no real run)
#
# tests/ssm/run-ssm-installtest-matrix.sh determines which SSM Agent versions
# install+run per OL and evaluates them against the AWS minimum (>= 3.3.3598.0).
# This tier loads ONLY its four pure helper functions (no container, no network,
# no clean-core) and asserts them across the shapes the matrix feeds them:
#   ssm_ge <a> <b>                 dotted 4-part version compare (a >= b)
#   go_min_kernel <go_version>     go.mod 'go' directive -> min-kernel proxy
#   ssm_in_scope <ver> <min> <full> default (>=min) vs --full version filter
#   ssm_compliance <maxver> <min>  headline verdict
# Pure and host-runnable; self-contained.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
MATRIX="${PROJ}/tests/ssm/run-ssm-installtest-matrix.sh"

# Load ONLY the pure helpers (each from its definition line to the first column-0 '}').
# shellcheck disable=SC1090
. <(sed -n '/^ssm_ge()/,/^}/p'        "${MATRIX}")
# shellcheck disable=SC1090
. <(sed -n '/^go_min_kernel()/,/^}/p' "${MATRIX}")
# shellcheck disable=SC1090
. <(sed -n '/^ssm_in_scope()/,/^}/p'  "${MATRIX}")
# shellcheck disable=SC1090
. <(sed -n '/^ssm_compliance()/,/^}/p' "${MATRIX}")

if ! declare -F ssm_ge >/dev/null 2>&1 || ! declare -F go_min_kernel >/dev/null 2>&1 \
   || ! declare -F ssm_in_scope >/dev/null 2>&1 || ! declare -F ssm_compliance >/dev/null 2>&1; then
  t_fail "could not load the pure helpers from run-ssm-installtest-matrix.sh"
  t_done; exit
fi

MIN="3.3.3598.0"

# --- ssm_ge: 4-part dotted version compare ----------------------------------
ssm_ge 3.3.4624.0 3.3.3598.0; assert_rc 0 "$?" "4624 >= 3598 (same major.minor, higher patch)"
ssm_ge 3.3.3598.0 3.3.3598.0; assert_rc 0 "$?" "equal versions -> ge true"
ssm_ge 3.0.1479.0 3.3.3598.0; assert_rc 1 "$?" "1479 < 3598 -> ge false"
ssm_ge 3.3.3598.0 3.0.1479.0; assert_rc 0 "$?" "3598 >= 1479"
ssm_ge 3.10.0.0 3.9.9999.0;   assert_rc 0 "$?" "numeric (not lexical) compare: 3.10 > 3.9"
ssm_ge 3.3.3598.0 3.3.3598.1; assert_rc 1 "$?" "4th-part decides: .0 < .1"

# --- go_min_kernel: go.mod 'go' directive -> min-kernel proxy ----------------
assert_eq "2.6.23"  "$(go_min_kernel 1.15)" "go 1.15 -> 2.6.23 (3.0.x era)"
assert_eq "2.6.32"  "$(go_min_kernel 1.18)" "go 1.18 -> 2.6.32"
assert_eq "2.6.32"  "$(go_min_kernel 1.20)" "go 1.20 -> 2.6.32 (last 2.6.32)"
assert_eq "3.2"     "$(go_min_kernel 1.21)" "go 1.21 -> 3.2 (the raise)"
assert_eq "3.2"     "$(go_min_kernel 1.24)" "go 1.24 -> 3.2 (3.3.x era)"
assert_eq "3.2"     "$(go_min_kernel 1.25)" "go 1.25 -> 3.2"
assert_eq "unknown" "$(go_min_kernel '')"   "empty go_version -> unknown"
assert_eq "unknown" "$(go_min_kernel abc)"  "non-numeric -> unknown"
# OL6 UEK4 = 4.1.12 satisfies every proxy value -> kernel axis is not the OL6 blocker.

# --- ssm_in_scope: default (>=min) vs --full --------------------------------
ssm_in_scope 3.3.4624.0 "${MIN}" 0; assert_rc 0 "$?" "default: >=min version is in scope"
ssm_in_scope 3.3.3598.0 "${MIN}" 0; assert_rc 0 "$?" "default: the boundary itself IS in scope (>=)"
ssm_in_scope 3.0.1479.0 "${MIN}" 0; assert_rc 1 "$?" "default: below-min version is OUT of scope"
ssm_in_scope 3.0.1479.0 "${MIN}" 1; assert_rc 0 "$?" "--full: below-min version IS in scope"
ssm_in_scope 1.1.145.0  "${MIN}" 1; assert_rc 0 "$?" "--full: oldest version in scope"

# --- ssm_compliance: headline verdict ---------------------------------------
assert_eq "compliant-capable" "$(ssm_compliance 3.3.4624.0 "${MIN}")" "max >= min -> compliant-capable"
assert_eq "compliant-capable" "$(ssm_compliance 3.3.3598.0 "${MIN}")" "max == min -> compliant-capable"
assert_eq "ec2messages-only"  "$(ssm_compliance 3.0.1479.0 "${MIN}")" "max < min -> ec2messages-only (non-remediable)"
assert_eq "none"              "$(ssm_compliance '' "${MIN}")"         "nothing install+ran -> none"

# --- reuse-by-copy consistency: list-ssm-releases.sh carries its own go_min_kernel
# copy (for the release list's min_kernel column); assert it matches this matrix's.
LISTER="${PROJ}/tests/ssm/list-ssm-releases.sh"
if [ -f "${LISTER}" ]; then
  # shellcheck disable=SC1090
  . <(sed -n '/^go_min_kernel()/,/^}/p' "${LISTER}" | sed 's/^go_min_kernel()/go_min_kernel_list()/')
  if declare -F go_min_kernel_list >/dev/null 2>&1; then
    for g in 1.15 1.18 1.20 1.21 1.24 1.25 "" abc 2.0; do
      assert_eq "$(go_min_kernel "${g}")" "$(go_min_kernel_list "${g}")" \
        "list-ssm-releases.sh go_min_kernel matches matrix for go '${g}'"
    done
  else
    t_fail "could not load go_min_kernel from list-ssm-releases.sh"
  fi
fi

t_done
