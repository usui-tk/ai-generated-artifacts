#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   L1 unit: EPEL pinned-repo resolution
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; hermetic (no network); shellcheck only for t002.
# ----- Usage examples -------------------------------------------------------
#   bash tests/t007_epelresolve.sh
#   bash tests/run-all.sh   # runs every tier
# ----- Known limitations ----------------------------------------------------
#   Asserts count failures and continue (harness scope, spec home A.5).
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/t007_epelresolve.sh - L1 unit: EPEL pinned-repo resolution
#
# Exercises the pure resolvers in lib/epel.sh (baseurl / gpgkey / archive flag /
# repo body) across all majors, the EPEL 10 minor resolution (minor tree present
# vs absent -> rolling fallback), the RHEL 6 archive special-case, and the minor
# parser against an os-release fixture. The single I/O point (the HEAD probe) is
# stubbed by redefining epel_head_ok in the subshell - no network.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
# shellcheck source=/dev/null
. "${PROJ}/lib/epel.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

H="https://dl.fedoraproject.org"

# --- supported / archive flags -----------------------------------------------
for n in 6 7 8 9 10; do epel_supported "${n}"; assert_rc 0 "$?" "supported: ${n}"; done
epel_supported 5 >/dev/null; assert_rc 1 "$?" "supported: 5 -> rc 1"
epel_is_archive 6; assert_rc 0 "$?" "archive: 6 -> yes"
epel_is_archive 7; assert_rc 0 "$?" "archive: 7 -> yes"
epel_is_archive 8; assert_rc 1 "$?" "archive: 8 -> no (live)"
epel_is_archive 10; assert_rc 1 "$?" "archive: 10 -> no (live)"

# --- gpg key url/file (live tree for every major, even archived content) ------
assert_eq "${H}/pub/epel/RPM-GPG-KEY-EPEL-9"  "$(epel_gpgkey_url 9)"  "gpgkey url: 9 (live tree)"
assert_eq "${H}/pub/epel/RPM-GPG-KEY-EPEL-6"  "$(epel_gpgkey_url 6)"  "gpgkey url: 6 (live tree even though content archived)"
assert_eq "/etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-9" "$(epel_gpgkey_file 9)" "gpgkey file: 9"

# --- baseurl per major (pure) ------------------------------------------------
assert_eq "${H}/pub/epel/9/Everything/x86_64/" "$(epel_baseurl 9)" "baseurl: 9 current"
assert_eq "${H}/pub/epel/8/Everything/x86_64/" "$(epel_baseurl 8)" "baseurl: 8 current"
assert_eq "${H}/pub/epel/10/Everything/x86_64/" "$(epel_baseurl 10)" "baseurl: 10 rolling (no minor)"
assert_eq "${H}/pub/epel/10.2/Everything/x86_64/" "$(epel_baseurl 10 2)" "baseurl: 10.2 minor-versioned"
assert_eq "${H}/pub/archive/epel/7/x86_64/" "$(epel_baseurl 7)" "baseurl: 7 archive"
assert_eq "${H}/pub/archive/epel/6/x86_64/" "$(epel_baseurl 6)" "baseurl: 6 archive (OL6-style special case)"
epel_baseurl 5 >/dev/null; assert_rc 1 "$?" "baseurl: unsupported -> rc 1"

assert_eq "${H}/pub/epel/10/Everything/x86_64/" "$(epel_baseurl_fallback 10)" "fallback: 10 -> rolling"
epel_baseurl_fallback 9 >/dev/null; assert_rc 1 "$?" "fallback: 9 -> rc 1 (none)"

# --- minor parser against an os-release fixture ------------------------------
osr="${WORK}/os-release"
printf 'NAME="Red Hat Enterprise Linux"\nVERSION_ID="10.2"\n' > "${osr}"
assert_eq "2" "$(epel_detect_minor "${osr}")" "detect_minor: VERSION_ID 10.2 -> 2"
printf 'VERSION_ID="9"\n' > "${osr}"
assert_eq "" "$(epel_detect_minor "${osr}")" "detect_minor: VERSION_ID 9 (no dot) -> empty"
assert_eq "" "$(epel_detect_minor "${WORK}/missing")" "detect_minor: missing file -> empty"

# --- EPEL 10 minor resolution (HEAD stubbed) ---------------------------------
# minor tree present -> use 10.<minor>
out="$(
  # shellcheck source=/dev/null
  . "${PROJ}/lib/epel.sh"
  # epel_head_ok is invoked indirectly by epel_resolve_baseurl; SC2317's
  # reachability heuristic can't see that, so suppress it for this test stub.
  # shellcheck disable=SC2317
  epel_head_ok() { return 0; }   # pretend the minor repomd.xml exists
  epel_resolve_baseurl 10 2
)"
assert_eq "${H}/pub/epel/10.2/Everything/x86_64/" "${out}" "resolve: 10.2 present -> minor tree"

# minor tree absent -> rolling fallback
out="$(
  # shellcheck source=/dev/null
  . "${PROJ}/lib/epel.sh"
  # indirectly invoked (see note above); suppress SC2317 for the stub.
  # shellcheck disable=SC2317
  epel_head_ok() { return 1; }   # minor repomd.xml absent
  epel_resolve_baseurl 10 2
)"
assert_eq "${H}/pub/epel/10/Everything/x86_64/" "${out}" "resolve: 10.2 absent -> rolling fallback"

# non-10 majors: resolve == pure baseurl (no probe)
assert_eq "${H}/pub/epel/9/Everything/x86_64/" "$(epel_resolve_baseurl 9)" "resolve: 9 -> pure baseurl"

# --- repo body (pure INI) ----------------------------------------------------
body="$(epel_repo_body 9 "${H}/pub/epel/9/Everything/x86_64/")"
assert_match "${body}" "^\[epel-pinned\]$"                                   "repo body: section header"
assert_match "${body}" "^baseurl=${H}/pub/epel/9/Everything/x86_64/$"        "repo body: baseurl line"
assert_match "${body}" "^enabled=0$"                                         "repo body: OFF by default"
assert_match "${body}" "^gpgcheck=1$"                                        "repo body: gpgcheck on"
assert_match "${body}" "^gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-9$" "repo body: local gpgkey file"
assert_match "${body}" "metalink / mirrorlist intentionally omitted"         "repo body: documents the metalink omission"

t_done
