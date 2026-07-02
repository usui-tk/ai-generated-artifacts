#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   L1 unit: package-manager detection + queries
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; hermetic (no network); shellcheck only for t002.
# ----- Usage examples -------------------------------------------------------
#   bash tests/t004_pkgmgrdetect.sh
#   bash tests/run-all.sh   # runs every tier
# ----- Known limitations ----------------------------------------------------
#   Asserts count failures and continue (harness scope, spec home A.5).
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/t004_pkgmgrdetect.sh - L1 unit: package-manager detection + queries
#
# Sources lib/ubi-pkgmgr.sh (side-effect-free) and exercises it hermetically.
# Detection is made deterministic by running pkgmgr_detect with PATH restricted
# to the shadow mock bin, so only the managers the test installs are visible -
# independent of whatever the host actually has. The command-string builders are
# pure; pkgmgr_is_available / pkgmgr_enabled_repos are driven with PATH-shadow
# mocks and spying.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
# shellcheck source=lib/mock.sh
. "${HERE}/lib/mock.sh"
LIB="${PROJ}/lib/ubi-pkgmgr.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# --- pkgmgr_detect: preference ladder (PATH restricted to the shadow bin) -----
# row: present_managers (comma-sep) | expect
detect_with() {
  # detect_with "dnf,yum" -> echoes what pkgmgr_detect returns with only those
  # managers present and PATH limited to the mock bin.
  local present="$1" td m
  td="${WORK}/$(printf '%s' "${present}" | tr ',' '_')"
  mkdir -p "${td}"
  (
    # shellcheck source=/dev/null
    . "${LIB}"
    mock_setup "${td}"
    IFS=','
    for m in ${present}; do mock_cmd "${m}"; done
    unset IFS
    PATH="${MOCK_BIN}"
    pkgmgr_detect || true
  )
}

assert_eq "dnf"      "$(detect_with 'dnf,microdnf,yum')" "detect: all present -> dnf (top of ladder)"
assert_eq "dnf"      "$(detect_with 'dnf,yum')"          "detect: dnf+yum -> dnf"
assert_eq "microdnf" "$(detect_with 'microdnf,yum')"     "detect: microdnf+yum -> microdnf"
assert_eq "yum"      "$(detect_with 'yum')"              "detect: only yum -> yum"
assert_eq "none"     "$(detect_with 'tar')"              "detect: no manager present -> none"

# pkgmgr_detect rc: non-zero when none found
rc_none="$(
  (
    # shellcheck source=/dev/null
    . "${LIB}"; mock_setup "${WORK}/rc"; PATH="${MOCK_BIN}"
    pkgmgr_detect >/dev/null; printf '%s' "$?"
  )
)"
assert_eq "1" "${rc_none}" "detect: rc 1 when no manager present"

# --- pure command-string builders --------------------------------------------
# shellcheck source=/dev/null
. "${LIB}"

assert_eq "dnf -y makecache"      "$(pkgmgr_makecache_cmd dnf)"      "makecache cmd: dnf"
assert_eq "yum -y makecache"      "$(pkgmgr_makecache_cmd yum)"      "makecache cmd: yum"
pkgmgr_makecache_cmd bogus >/dev/null; assert_rc 1 "$?" "makecache cmd: unknown -> rc 1"

assert_eq "dnf repolist --enabled" "$(pkgmgr_repolist_cmd dnf)" "repolist cmd: dnf"
assert_eq "yum repolist"           "$(pkgmgr_repolist_cmd yum)" "repolist cmd: yum"

assert_eq "dnf list --available kernel-devel"      "$(pkgmgr_avail_cmd dnf kernel-devel)"      "avail cmd: dnf native list"
assert_eq "yum list available kernel-devel"        "$(pkgmgr_avail_cmd yum kernel-devel)"      "avail cmd: yum native list"
assert_eq "repoquery --latest-limit=1 kernel-devel" "$(pkgmgr_avail_cmd microdnf kernel-devel)" "avail cmd: microdnf -> repoquery fallback"

# --- pkgmgr_is_available: dnf present vs absent (mocked) ----------------------
td="${WORK}/avail_dnf_ok"; mkdir -p "${td}"
rc_ok="$(
  (
    # shellcheck source=/dev/null
    . "${LIB}"; mock_setup "${td}"
    # shellcheck disable=SC2016  # behaviour is literal; $1 expands at the fake's runtime
    mock_cmd dnf 'case "$*" in *kernel-devel*) printf "kernel-devel.x86_64 4.18.0 @rhel-8\n"; exit 0;; *) exit 0;; esac'
    pkgmgr_is_available dnf kernel-devel; printf '%s' "$?"
  )
)"
assert_eq "0" "${rc_ok}" "is_available: dnf names the pkg -> rc 0 (available)"
assert_match "$(cat "${td}/calls")" "^dnf list --available kernel-devel$" "is_available: spy - dnf list --available used (not bare repoquery)"

td="${WORK}/avail_dnf_no"; mkdir -p "${td}"
rc_no="$(
  (
    # shellcheck source=/dev/null
    . "${LIB}"; mock_setup "${td}"
    mock_cmd dnf 'exit 1'   # query fails / prints nothing
    pkgmgr_is_available dnf kernel-devel; printf '%s' "$?"
  )
)"
assert_eq "1" "${rc_no}" "is_available: empty/failed query -> rc 1 (not available)"

# unknown manager -> rc 2
rc_unk="$(
  (
    # shellcheck source=/dev/null
    . "${LIB}"
    pkgmgr_is_available bogus kernel-devel; printf '%s' "$?"
  )
)"
assert_eq "2" "${rc_unk}" "is_available: unknown manager -> rc 2"

# --- pkgmgr_enabled_repos: yum (mocked) --------------------------------------
td="${WORK}/repos_yum"; mkdir -p "${td}"
repos="$(
  (
    # shellcheck source=/dev/null
    . "${LIB}"; mock_setup "${td}"
    # shellcheck disable=SC2016
    mock_cmd yum 'printf "repo id        repo name\nrhel-7-server-rpms  Red Hat\n"'
    pkgmgr_enabled_repos yum
  )
)"
assert_match "${repos}" "rhel-7-server-rpms" "enabled_repos: yum output passed through"

t_done
