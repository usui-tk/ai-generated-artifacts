#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   L1 unit: the canonical OS profile (Phase 6)
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; hermetic (no network); shellcheck only for t002.
# ----- Usage examples -------------------------------------------------------
#   bash tests/t012_osprofile.sh
#   bash tests/run-all.sh   # runs every tier
# ----- Known limitations ----------------------------------------------------
#   Asserts count failures and continue (harness scope, spec home A.5).
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/t012_osprofile.sh - L1 unit: the canonical OS profile (Phase 6)
#
# Asserts every lib/os-profile.sh helper across all five majors, AND the
# cross-consistency invariants that make it a single source of truth: the
# scattered per-fact maps in the acquisition libraries and the ENA matrix MUST
# agree with this canon. Pure and host-runnable.
#   osp_image      == acq_image_for_major      (lib/acquire-rootfs.sh)
#   osp_pull_tag   == acq_tag_for_major        (lib/acquire-rootfs.sh)
#   osp_epel_is_live inverse of epel_is_archive(lib/epel.sh)
#   osp_kdevel_repo== ena_kdevel_repo          (aws_ena-driver matrix)
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
# shellcheck source=lib/os-profile.sh
. "${PROJ}/lib/os-profile.sh"

if ! declare -F osp_tier >/dev/null 2>&1 || ! declare -F osp_epel_status >/dev/null 2>&1; then
  t_fail "could not load lib/os-profile.sh"
  t_done; exit
fi

# --- osp_known --------------------------------------------------------------
for m in 6 7 8 9 10; do osp_known "${m}"; assert_rc 0 "$?" "osp_known ${m} -> rc 0"; done
osp_known 5; assert_rc 1 "$?" "osp_known 5 -> rc 1"
osp_known "";  assert_rc 1 "$?" "osp_known '' -> rc 1"

# --- osp_tier ---------------------------------------------------------------
assert_eq "A" "$(osp_tier 10)" "tier 10 -> A"
assert_eq "A" "$(osp_tier 8)"  "tier 8 -> A"
assert_eq "B" "$(osp_tier 7)"  "tier 7 -> B"
assert_eq "C" "$(osp_tier 6)"  "tier 6 -> C"
assert_eq "unknown" "$(osp_tier 5)" "tier 5 -> unknown"

# --- osp_pkgmgr -------------------------------------------------------------
assert_eq "dnf" "$(osp_pkgmgr 9)" "pkgmgr 9 -> dnf"
assert_eq "yum" "$(osp_pkgmgr 7)" "pkgmgr 7 -> yum"
assert_eq "yum" "$(osp_pkgmgr 6)" "pkgmgr 6 -> yum"

# --- osp_pull_constraint ----------------------------------------------------
assert_eq "fixed-tag"   "$(osp_pull_constraint 7)" "pull 7 -> fixed-tag (signature)"
assert_eq "floating-ok" "$(osp_pull_constraint 9)" "pull 9 -> floating-ok"
assert_eq "floating-ok" "$(osp_pull_constraint 6)" "pull 6 -> floating-ok"

# --- osp_anon_repos / osp_has_anon_repo (the Tier-C property) ----------------
assert_eq "ubi"      "$(osp_anon_repos 8)" "anon 8 -> ubi"
assert_eq "yum-anon" "$(osp_anon_repos 7)" "anon 7 -> yum-anon"
assert_eq "none"     "$(osp_anon_repos 6)" "anon 6 -> none"
osp_has_anon_repo 8; assert_rc 0 "$?" "has_anon 8 -> rc 0"
osp_has_anon_repo 7; assert_rc 0 "$?" "has_anon 7 -> rc 0"
osp_has_anon_repo 6; assert_rc 1 "$?" "has_anon 6 -> rc 1 (Tier C: no anon repo)"
osp_has_anon_repo 5; assert_rc 2 "$?" "has_anon 5 -> rc 2 (unknown)"

# --- osp_entitled_repo / osp_lifecycle --------------------------------------
assert_eq "rhel-9-for-x86_64"  "$(osp_entitled_repo 9)" "entitled repo 9"
assert_eq "rhel-7-server-rpms" "$(osp_entitled_repo 7)" "entitled repo 7"
assert_eq "rhel-6-server-rpms" "$(osp_entitled_repo 6)" "entitled repo 6"
assert_eq "current"         "$(osp_lifecycle 8)" "lifecycle 8 -> current"
assert_eq "frozen"          "$(osp_lifecycle 7)" "lifecycle 7 -> frozen"
assert_eq "eol-constrained" "$(osp_lifecycle 6)" "lifecycle 6 -> eol-constrained"

# --- osp_epel_status / osp_epel_is_live -------------------------------------
assert_eq "current"       "$(osp_epel_status 9)"  "epel 9 -> current"
assert_eq "current-minor" "$(osp_epel_status 10)" "epel 10 -> current-minor"
assert_eq "archive"       "$(osp_epel_status 7)"  "epel 7 -> archive"
assert_eq "archive-only"  "$(osp_epel_status 6)"  "epel 6 -> archive-only"
osp_epel_is_live 8; assert_rc 0 "$?" "epel_is_live 8 -> rc 0"
osp_epel_is_live 7; assert_rc 1 "$?" "epel_is_live 7 -> rc 1 (archive)"
osp_epel_is_live 6; assert_rc 1 "$?" "epel_is_live 6 -> rc 1 (archive-only)"

# --- cross-consistency: osp_image == acq_image_for_major --------------------
ACQ="${PROJ}/lib/acquire-rootfs.sh"
# shellcheck disable=SC1090
. <(sed -n '/^acq_image_for_major()/,/^}/p' "${ACQ}")
# shellcheck disable=SC1090
. <(sed -n '/^acq_tag_for_major()/,/^}/p' "${ACQ}")
if declare -F acq_image_for_major >/dev/null 2>&1; then
  for m in 6 7 8 9 10; do
    assert_eq "$(osp_image "${m}")" "$(acq_image_for_major "${m}")" "osp_image ${m} == acq_image_for_major"
    assert_eq "$(osp_pull_tag "${m}")" "$(acq_tag_for_major "${m}")" "osp_pull_tag ${m} == acq_tag_for_major"
  done
else
  t_fail "could not load acq_image_for_major from lib/acquire-rootfs.sh"
fi

# --- cross-consistency: osp_epel_is_live is the inverse of epel_is_archive ---
EPEL="${PROJ}/lib/epel.sh"
# shellcheck disable=SC1090
. <(sed -n '/^epel_is_archive()/,/^}/p' "${EPEL}")
if declare -F epel_is_archive >/dev/null 2>&1; then
  for m in 6 7 8 9 10; do
    arc=0; epel_is_archive "${m}" || arc=$?     # 0 = archive, 1 = live
    live=0; osp_epel_is_live "${m}" || live=$?  # 0 = live,    1 = archive
    # archive(0) <-> live(1) and archive(1) <-> live(0): rc sum must be 1
    assert_eq "1" "$(( arc + live ))" "epel_is_archive/osp_epel_is_live agree for ${m}"
  done
else
  t_fail "could not load epel_is_archive from lib/epel.sh"
fi

# --- cross-consistency: osp_kdevel_repo == ena_kdevel_repo -------------------
ENAM="${PROJ}/tests/aws_ena-driver/run-ena-buildtest-matrix.sh"
if [ -f "${ENAM}" ]; then
  # shellcheck disable=SC1090
  . <(sed -n '/^ena_kdevel_repo()/,/^}/p' "${ENAM}")
  if declare -F ena_kdevel_repo >/dev/null 2>&1; then
    for m in 6 7 8 9 10; do
      assert_eq "$(osp_kdevel_repo "${m}")" "$(ena_kdevel_repo "${m}")" "osp_kdevel_repo ${m} == ena_kdevel_repo"
    done
  else
    t_fail "could not load ena_kdevel_repo from the ENA matrix"
  fi
fi

t_done
