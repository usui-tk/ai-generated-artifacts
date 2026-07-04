#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   L1 unit: AWS SSM Agent matrix pure logic (no run)
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; hermetic (no network); shellcheck only for t002.
# ----- Usage examples -------------------------------------------------------
#   bash tests/t009_ssmverdict.sh
#   bash tests/run-all.sh   # runs every tier
# ----- Known limitations ----------------------------------------------------
#   Asserts count failures and continue (harness scope, spec home A.5).
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/t009_ssmverdict.sh - L1 unit: AWS SSM Agent matrix pure logic (no run)
#
# Loads ONLY the matrix's pure helpers (each extracted from its column-0
# definition to the first column-0 `}`) and asserts them across the shapes the
# matrix feeds them:
#   ssm_ge / rhel_glibc / ssm_in_scope / ssm_compliance / ssm_init_outcome /
#   ssm_verdict
# Plus the reuse-by-copy invariant: list-ssm-releases.sh carries its own ssm_ge,
# which must match the matrix's.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
MATRIX="${PROJ}/tests/aws_ssm-agent/run-ssm-installtest-matrix.sh"
LISTER="${PROJ}/tests/aws_ssm-agent/list-ssm-releases.sh"

for fn in ssm_ge rhel_glibc ssm_in_scope ssm_compliance ssm_init_outcome ssm_verdict; do
  # shellcheck disable=SC1090
  . <(sed -n "/^${fn}()/,/^}/p" "${MATRIX}")
done

if ! declare -F ssm_ge >/dev/null 2>&1 || ! declare -F ssm_verdict >/dev/null 2>&1 \
   || ! declare -F ssm_init_outcome >/dev/null 2>&1 || ! declare -F ssm_compliance >/dev/null 2>&1; then
  t_fail "could not load the pure helpers from run-ssm-installtest-matrix.sh"
  t_done; exit
fi

MIN="3.3.3598.0"

# --- ssm_ge: 4-part dotted compare ------------------------------------------
ssm_ge 3.3.4624.0 3.3.3598.0; assert_rc 0 "$?" "4624 >= 3598"
ssm_ge 3.3.3598.0 3.3.3598.0; assert_rc 0 "$?" "equal -> ge true"
ssm_ge 3.0.1479.0 3.3.3598.0; assert_rc 1 "$?" "1479 < 3598"
ssm_ge 3.10.0.0 3.9.9999.0;   assert_rc 0 "$?" "numeric: 3.10 > 3.9"
ssm_ge 3.3.3598.0 3.3.3598.1; assert_rc 1 "$?" "4th part decides: .0 < .1"

# --- rhel_glibc: measured per-major map -------------------------------------
assert_eq "2.34" "$(rhel_glibc 9)" "rhel_glibc 9 -> 2.34"
assert_eq "2.12" "$(rhel_glibc 6)" "rhel_glibc 6 -> 2.12"
assert_eq "unknown" "$(rhel_glibc 5)" "rhel_glibc 5 -> unknown"

# --- ssm_in_scope: default (>=min) vs --full --------------------------------
ssm_in_scope 3.3.4624.0 "${MIN}" 0; assert_rc 0 "$?" "default: >=min in scope"
ssm_in_scope 3.3.3598.0 "${MIN}" 0; assert_rc 0 "$?" "default: boundary in scope (>=)"
ssm_in_scope 3.0.1479.0 "${MIN}" 0; assert_rc 1 "$?" "default: below-min out of scope"
ssm_in_scope 3.0.1479.0 "${MIN}" 1; assert_rc 0 "$?" "--full: below-min in scope"

# --- ssm_compliance: feature headline ---------------------------------------
assert_eq "compliant-capable" "$(ssm_compliance 3.3.4793.0 "${MIN}")" "newest >= min -> compliant-capable"
assert_eq "compliant-capable" "$(ssm_compliance 3.3.3598.0 "${MIN}")" "== min -> compliant-capable"
assert_eq "ec2messages-only"  "$(ssm_compliance 3.0.1479.0 "${MIN}")" "< min -> ec2messages-only"
assert_eq "none"              "$(ssm_compliance '' "${MIN}")"         "nothing -> none"

# --- ssm_init_outcome: the init axis ----------------------------------------
assert_eq "version-only"    "$(ssm_init_outcome none)"    "none -> version-only"
assert_eq "service-capable" "$(ssm_init_outcome systemd)" "systemd -> service-capable"
assert_eq "unknown"         "$(ssm_init_outcome bogus)"   "unknown mode -> unknown"

# --- ssm_verdict: EMPIRICAL per-cell headline -------------------------------
assert_eq "install-fail"     "$(ssm_verdict false false none)"   "not installed -> install-fail"
assert_eq "installed-no-run" "$(ssm_verdict true false none)"    "installed, no run -> installed-no-run"
assert_eq "runs-no-init"     "$(ssm_verdict true true none)"     "ran in none mode -> runs-no-init"
assert_eq "runs-service"     "$(ssm_verdict true true systemd)"  "ran in systemd mode -> runs-service"

# --- reuse-by-copy: list-ssm-releases.sh ssm_ge matches the matrix ----------
if [ -f "${LISTER}" ]; then
  # shellcheck disable=SC1090
  . <(sed -n '/^ssm_ge()/,/^}/p' "${LISTER}" | sed 's/^ssm_ge()/ssm_ge_list()/')
  if declare -F ssm_ge_list >/dev/null 2>&1; then
    for pair in "3.3.4624.0 3.3.3598.0" "3.0.1479.0 3.3.3598.0" "3.3.3598.0 3.3.3598.0" "3.10.0.0 3.9.9999.0"; do
      read -r a b <<<"${pair}"
      a_rc=0; ssm_ge "${a}" "${b}" || a_rc=$?
      b_rc=0; ssm_ge_list "${a}" "${b}" || b_rc=$?
      assert_eq "${a_rc}" "${b_rc}" "lister ssm_ge matches matrix for '${a} >= ${b}'"
    done
  else
    t_fail "could not load ssm_ge from list-ssm-releases.sh"
  fi
fi

# --- r51: per-major sweep set + per-major init ---------------------------------
# shellcheck disable=SC1090  # sed-extracted functions from the matrix under test
. <(sed -n '/^SSM_LEGACY_VERSIONS_EL6=/p; /^rhel_init()/,/^}/p; /^ssm_major_versions()/,/^}/p' "${MATRIX}")
assert_eq "3.3.9 3.3.8 3.0.1479.0" "$(ssm_major_versions 6 3.3.9 3.3.8)" \
  "EL6 sweep set = base + legacy track-record versions"
assert_eq "3.3.9 3.3.8" "$(ssm_major_versions 9 3.3.9 3.3.8)" "other majors unchanged"
assert_eq "upstart" "$(rhel_init 6)" "EL6 init = upstart (legitimate, not an exception)"
assert_eq "systemd" "$(rhel_init 10)" "EL10 init = systemd"

t_done
