# shellcheck shell=bash
#==============================================================================
# lib/ubi-pkgmgr.sh - package-manager detection + availability queries
#
# Sourceable library (no shebang, no top-level execution): sourcing only defines
# functions, so the L1 unit tier can source it and exercise each function in an
# isolated subshell, driving the external commands with PATH-shadow mocks.
#
# Detection order is dnf -> microdnf -> yum -> none (the design plan sec
# 3.4 / 8): dnf on RHEL 8/9/10, microdnf as the minimal UBI manager, yum on
# RHEL 6/7. Availability is queried with `dnf list --available` /
# `repoquery --latest-limit=1` / `yum list available` rather than a bare
# `repoquery`, because a bare query can print nothing even when the package
# exists (the sec 3.4 "kernel-devel empty" artifact).
#==============================================================================

# pkgmgr_detect - echo the first available package manager in preference order.
# Depends only on PATH (mockable). Echoes 'none' and returns 1 if none found.
pkgmgr_detect() {
  local m
  for m in dnf microdnf yum; do
    if command -v "${m}" >/dev/null 2>&1; then
      printf '%s\n' "${m}"
      return 0
    fi
  done
  printf 'none\n'
  return 1
}

# pkgmgr_makecache_cmd MGR - print the metadata-refresh command for MGR. Used as
# the entitlement-detection trigger: one pass makes the subscription-manager
# plugin generate redhat.repo (sec 3.4). Returns 1 for an unknown/none manager.
pkgmgr_makecache_cmd() {
  case "$1" in
    dnf)      printf 'dnf -y makecache\n' ;;
    microdnf) printf 'microdnf -y makecache\n' ;;
    yum)      printf 'yum -y makecache\n' ;;
    *)        return 1 ;;
  esac
}

# pkgmgr_repolist_cmd MGR - print the "list enabled repos" command for MGR.
pkgmgr_repolist_cmd() {
  case "$1" in
    dnf)      printf 'dnf repolist --enabled\n' ;;
    microdnf) printf 'microdnf repolist --enabled\n' ;;
    yum)      printf 'yum repolist\n' ;;
    *)        return 1 ;;
  esac
}

# pkgmgr_avail_cmd MGR PKG - print the "is PKG available?" query command for MGR.
# microdnf has no robust availability subcommand, so its row maps to the
# documented repoquery fallback (repoquery from dnf-utils/yum-utils).
pkgmgr_avail_cmd() {
  local mgr="$1" pkg="$2"
  case "${mgr}" in
    dnf)      printf 'dnf list --available %s\n' "${pkg}" ;;
    microdnf) printf 'repoquery --latest-limit=1 %s\n' "${pkg}" ;;
    yum)      printf 'yum list available %s\n' "${pkg}" ;;
    *)        return 1 ;;
  esac
}

# pkgmgr_enabled_repos MGR - run the repolist command and print enabled repo IDs.
# I/O (mockable). Best-effort: a non-zero manager exit yields empty output.
pkgmgr_enabled_repos() {
  case "$1" in
    dnf)      dnf repolist --enabled 2>/dev/null ;;
    microdnf) microdnf repolist --enabled 2>/dev/null ;;
    yum)      yum repolist 2>/dev/null ;;
    *)        return 1 ;;
  esac
}

# pkgmgr_is_available MGR PKG - rc 0 iff the availability query both succeeds and
# names PKG. I/O (mockable). rc 2 for an unknown manager.
pkgmgr_is_available() {
  local mgr="$1" pkg="$2" out
  case "${mgr}" in
    dnf)      out="$(dnf list --available "${pkg}" 2>/dev/null)" ;;
    microdnf) out="$(repoquery --latest-limit=1 "${pkg}" 2>/dev/null)" ;;
    yum)      out="$(yum list available "${pkg}" 2>/dev/null)" ;;
    *)        return 2 ;;
  esac
  grep -Fq -- "${pkg}" <<<"${out}"
}
