#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   L1 unit: AWS ENA build-test matrix pure logic
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; hermetic (no network); shellcheck only for t002.
# ----- Usage examples -------------------------------------------------------
#   bash tests/t010_enaverdict.sh
#   bash tests/run-all.sh   # runs every tier
# ----- Known limitations ----------------------------------------------------
#   Asserts count failures and continue (harness scope, spec home A.5).
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/t010_enaverdict.sh - L1 unit: AWS ENA build-test matrix pure logic
#
# Loads ONLY the matrix's pure helpers (each extracted from its column-0
# definition to the first column-0 `}`) and asserts the E2' logic:
#   ena_ge / ena_kdevel_repo / ena_in_scope / ena_build_plan / ena_verdict /
#   ena_load_tier / ena_express_verdict
# Plus the reuse-by-copy invariant: list-ena-releases.sh and
# install-aws_ena-driver.sh each carry their own ena_ge / ena_express_verdict,
# which must match the matrix's.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
MATRIX="${PROJ}/tests/aws_ena-driver/run-ena-buildtest-matrix.sh"
LISTER="${PROJ}/tests/aws_ena-driver/list-ena-releases.sh"
INSTALLER="${PROJ}/install-aws_ena-driver.sh"

for fn in ena_ge ena_kdevel_repo ena_in_scope ena_build_plan ena_verdict ena_load_tier ena_express_verdict; do
  # shellcheck disable=SC1090
  . <(sed -n "/^${fn}()/,/^}/p" "${MATRIX}")
done

if ! declare -F ena_ge >/dev/null 2>&1 || ! declare -F ena_verdict >/dev/null 2>&1 \
   || ! declare -F ena_build_plan >/dev/null 2>&1 || ! declare -F ena_kdevel_repo >/dev/null 2>&1 \
   || ! declare -F ena_express_verdict >/dev/null 2>&1; then
  t_fail "could not load the pure helpers from run-ena-buildtest-matrix.sh"
  t_done; exit
fi

# --- ena_ge: 3-part dotted compare ------------------------------------------
ena_ge 2.13.0 2.8.0; assert_rc 0 "$?" "2.13.0 >= 2.8.0"
ena_ge 2.8.0 2.8.0;  assert_rc 0 "$?" "equal -> ge true"
ena_ge 2.7.1 2.8.0;  assert_rc 1 "$?" "2.7.1 < 2.8.0"
ena_ge 2.10.0 2.9.9; assert_rc 0 "$?" "numeric: 2.10 > 2.9"

# --- ena_kdevel_repo: kernel-devel repo when entitled (sec 3.3) --------------
assert_eq "appstream" "$(ena_kdevel_repo 10)" "10 -> appstream"
assert_eq "appstream" "$(ena_kdevel_repo 9)"  "9 -> appstream"
assert_eq "baseos"    "$(ena_kdevel_repo 8)"  "8 -> baseos"
assert_eq "server"    "$(ena_kdevel_repo 7)"  "7 -> server"
assert_eq "server"    "$(ena_kdevel_repo 6)"  "6 -> server"
assert_eq "unknown"   "$(ena_kdevel_repo 5)"  "5 -> unknown"

# --- ena_in_scope: default (>=min) vs --full --------------------------------
ena_in_scope 2.13.0 2.8.0 0; assert_rc 0 "$?" "default: >=min in scope"
ena_in_scope 2.8.0 2.8.0 0;  assert_rc 0 "$?" "default: boundary in scope (>=)"
ena_in_scope 2.7.0 2.8.0 0;  assert_rc 1 "$?" "default: below-min out of scope"
ena_in_scope 2.7.0 2.8.0 1;  assert_rc 0 "$?" "--full: below-min in scope"

# --- ena_build_plan: how the build is attempted -----------------------------
assert_eq "skip" "$(ena_build_plan anonymous 0)" "anonymous -> skip"
assert_eq "make" "$(ena_build_plan entitled 0)"  "entitled, no EPEL -> make"
assert_eq "dkms" "$(ena_build_plan entitled 1)"  "entitled + EPEL -> dkms"
assert_eq "unknown" "$(ena_build_plan bogus 0)"  "bogus -> unknown"

# --- ena_verdict: the E2' headline ------------------------------------------
assert_eq "needs-entitlement" "$(ena_verdict anonymous false)" "anonymous -> needs-entitlement"
assert_eq "needs-entitlement" "$(ena_verdict anonymous true)"  "anonymous ignores built -> needs-entitlement"
assert_eq "ok"                "$(ena_verdict entitled true)"   "entitled + built -> ok"
assert_eq "build-fail"        "$(ena_verdict entitled false)"  "entitled + not built -> build-fail"

# --- ena_load_tier: load is always L4 ---------------------------------------
assert_eq "L4" "$(ena_load_tier)" "module load -> always L4"

# --- ena_express_verdict: AWS ENA Express driver-version floors -------------
# (ena-express.html: >= 2.2.9 full bandwidth, >= 2.8.0 ena_srd_* metrics)
assert_eq "not-ready"      "$(ena_express_verdict 2.2.8)"  "express: 2.2.8 -> not-ready"
assert_eq "bandwidth-only" "$(ena_express_verdict 2.2.9)"  "express: 2.2.9 -> bandwidth-only (boundary)"
assert_eq "bandwidth-only" "$(ena_express_verdict 2.7.9)"  "express: 2.7.9 -> bandwidth-only"
assert_eq "express-ready"  "$(ena_express_verdict 2.8.0)"  "express: 2.8.0 -> express-ready (boundary)"
assert_eq "express-ready"  "$(ena_express_verdict 2.17.0)" "express: 2.17.0 -> express-ready"
assert_eq "not-ready"      "$(ena_express_verdict 1.6.0)"  "express: 1.6.0 -> not-ready"
assert_eq "unknown"        "$(ena_express_verdict '')"     "express: empty -> unknown"

# --- reuse-by-copy: list-ena-releases.sh ena_ge / ena_express_verdict ------
if [ -f "${LISTER}" ]; then
  # shellcheck disable=SC1090
  . <(sed -n '/^ena_ge()/,/^}/p' "${LISTER}" | sed 's/^ena_ge()/ena_ge_list()/')
  if declare -F ena_ge_list >/dev/null 2>&1; then
    for pair in "2.13.0 2.8.0" "2.7.1 2.8.0" "2.8.0 2.8.0" "2.10.0 2.9.9"; do
      read -r a b <<<"${pair}"
      a_rc=0; ena_ge "${a}" "${b}" || a_rc=$?
      b_rc=0; ena_ge_list "${a}" "${b}" || b_rc=$?
      assert_eq "${a_rc}" "${b_rc}" "lister ena_ge matches matrix for '${a} >= ${b}'"
    done
  else
    t_fail "could not load ena_ge from list-ena-releases.sh"
  fi
  # shellcheck disable=SC1090
  . <(sed -n '/^ena_express_verdict()/,/^}/p' "${LISTER}" | sed 's/^ena_express_verdict()/ena_express_verdict_list()/')
  if declare -F ena_express_verdict_list >/dev/null 2>&1; then
    for v in 2.2.8 2.2.9 2.7.9 2.8.0 2.17.0 1.6.0 ""; do
      assert_eq "$(ena_express_verdict "${v}")" "$(ena_express_verdict_list "${v}")" "lister ena_express_verdict matches matrix for '${v}'"
    done
  else
    t_fail "could not load ena_express_verdict from list-ena-releases.sh"
  fi
fi

# --- reuse-by-copy: install-aws_ena-driver.sh ena_express_verdict ----------
if [ -f "${INSTALLER}" ]; then
  # shellcheck disable=SC1090
  . <(sed -n '/^ena_express_verdict()/,/^}/p' "${INSTALLER}" | sed 's/^ena_express_verdict()/ena_express_verdict_install()/')
  if declare -F ena_express_verdict_install >/dev/null 2>&1; then
    for v in 2.2.8 2.2.9 2.7.9 2.8.0 2.17.0 1.6.0 ""; do
      assert_eq "$(ena_express_verdict "${v}")" "$(ena_express_verdict_install "${v}")" "installer ena_express_verdict matches matrix for '${v}'"
    done
  else
    t_fail "could not load ena_express_verdict from install-aws_ena-driver.sh"
  fi
fi

t_done
