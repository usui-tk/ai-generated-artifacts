# ----- Purpose --------------------------------------------------------------
#   Deterministic EPEL access: dl.fedoraproject.org pinned baseurl (method B,
#   metalink disabled), EPEL 10 minor resolution, RHEL 6 archive special case.
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; sourced library (no side effects at source time).
# ----- Usage examples -------------------------------------------------------
#   source lib/epel.sh   # from a matrix runner / probe / test tier
# ----- Known limitations ----------------------------------------------------
#   Not a standalone executable; functions assume the caller handles logging
#   and error policy (spec home A.5).
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
# shellcheck shell=bash
#==============================================================================
# lib/epel.sh - EPEL pinned-repo handling (the design plan sec 12.1)
#
# Sourceable library (no shebang, no top-level execution). RHEL has no vendor
# EPEL and Fedora's default metalink is non-deterministic (returns off-allow-list
# mirrors), so this pins to dl.fedoraproject.org with an explicit baseurl,
# metalink/mirrorlist disabled, via a transient pinned repo (method B) rather
# than the epel-release package (method A).
#
# Per-major baseurls (measured Phase 0): 8/9 current; 10 minor-versioned with a
# rolling fallback; 7/6 archive-only. GPG keys for ALL majors live under the live
# tree (/pub/epel/RPM-GPG-KEY-EPEL-<N>) even where content is archived. RHEL 6 is
# archive-only and OL6-style special-cased (practically moot: ENA defaults to
# plain-make, so EPEL/DKMS is optional).
#
# Pure resolvers (baseurl / gpgkey / repo body) carry the unit coverage in
# tests/t007_epelresolve.sh; the I/O steps (key import, repo write, install,
# cleanup) wrap them and are mockable.
#==============================================================================

EPEL_DL_HOST="https://dl.fedoraproject.org"
EPEL_REPO_PATH="/etc/yum.repos.d/epel-pinned.repo"

# epel_supported MAJOR - rc 0 for 6..10, rc 1 otherwise.
epel_supported() {
  case "$1" in 6|7|8|9|10) return 0 ;; *) return 1 ;; esac
}

# epel_is_archive MAJOR - rc 0 for the archive-only majors (6, 7), rc 1 for the
# live majors (8, 9, 10), rc 2 for anything else.
epel_is_archive() {
  case "$1" in 6|7) return 0 ;; 8|9|10) return 1 ;; *) return 2 ;; esac
}

# epel_gpgkey_url MAJOR - the live-tree GPG key URL (valid for every major).
epel_gpgkey_url() {
  epel_supported "$1" || return 1
  printf '%s/pub/epel/RPM-GPG-KEY-EPEL-%s\n' "${EPEL_DL_HOST}" "$1"
}

# epel_gpgkey_file MAJOR - the local path the key is imported to (used by the
# repo body's gpgkey= line after epel_import_key).
epel_gpgkey_file() {
  epel_supported "$1" || return 1
  printf '/etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-%s\n' "$1"
}

# epel_baseurl MAJOR [MINOR] - the PRIMARY content baseurl (pure). For EPEL 10
# with a MINOR, the minor-versioned tree; without it, the rolling tree.
epel_baseurl() {
  local n="$1" minor="${2:-}"
  case "${n}" in
    8|9) printf '%s/pub/epel/%s/Everything/x86_64/\n' "${EPEL_DL_HOST}" "${n}" ;;
    10)
      if [ -n "${minor}" ]; then
        printf '%s/pub/epel/10.%s/Everything/x86_64/\n' "${EPEL_DL_HOST}" "${minor}"
      else
        printf '%s/pub/epel/10/Everything/x86_64/\n' "${EPEL_DL_HOST}"
      fi
      ;;
    7|6) printf '%s/pub/archive/epel/%s/x86_64/\n' "${EPEL_DL_HOST}" "${n}" ;;
    *)   return 1 ;;
  esac
}

# epel_baseurl_fallback MAJOR - the rolling fallback baseurl for EPEL 10 minor
# resolution; rc 1 (no fallback) for every other major.
epel_baseurl_fallback() {
  case "$1" in
    10) printf '%s/pub/epel/10/Everything/x86_64/\n' "${EPEL_DL_HOST}" ;;
    *)  return 1 ;;
  esac
}

# epel_detect_minor [OS_RELEASE_FILE] - print the minor component of VERSION_ID
# (e.g. "10.2" -> "2"); empty if there is no dotted minor. Parametrised path so
# the unit tier can feed a fixture.
epel_detect_minor() {
  local osr="${1:-/etc/os-release}" vid=""
  [ -r "${osr}" ] || return 0
  # shellcheck disable=SC1090  # fixture path is provided by the caller/test
  vid="$(. "${osr}" >/dev/null 2>&1; printf '%s' "${VERSION_ID:-}")"
  case "${vid}" in
    *.*) printf '%s\n' "${vid#*.}" ;;
    *)   : ;;  # no dotted minor -> empty
  esac
}

# epel_repo_body MAJOR BASEURL - emit the pinned .repo INI text (pure). BASEURL
# is passed in (already resolved) so the body is deterministic for the unit tier.
epel_repo_body() {
  local n="$1" baseurl="$2" keyfile
  keyfile="$(epel_gpgkey_file "${n}")" || return 1
  cat <<EOF
[epel-pinned]
name=EPEL ${n} (pinned, dl.fedoraproject.org)
baseurl=${baseurl}
enabled=0
gpgcheck=1
gpgkey=file://${keyfile}
# metalink / mirrorlist intentionally omitted (avoid non-deterministic mirrors)
EOF
}

# --- I/O wrappers (mockable) -------------------------------------------------

# epel_head_ok URL - rc 0 iff a HEAD request to URL succeeds (HTTP 2xx). Honours
# INSECURE_TLS=1 (sandbox TLS interception). Used by epel_resolve_baseurl.
epel_head_ok() {
  local url="$1" insecure=()
  [ "${INSECURE_TLS:-0}" = "1" ] && insecure=(-k)
  curl -sfI "${insecure[@]}" -o /dev/null "${url}"
}

# epel_resolve_baseurl MAJOR [MINOR] - print the baseurl to actually use. For
# EPEL 10 with a minor, HEAD the minor tree's repomd.xml and fall back to the
# rolling tree if absent; for every other major, the pure baseurl. I/O for the
# 10-minor probe only (mockable via epel_head_ok).
epel_resolve_baseurl() {
  local n="$1" minor="${2:-}" primary fallback
  if [ "${n}" = "10" ] && [ -n "${minor}" ]; then
    primary="$(epel_baseurl 10 "${minor}")"
    if epel_head_ok "${primary}repodata/repomd.xml"; then
      printf '%s\n' "${primary}"
      return 0
    fi
    fallback="$(epel_baseurl_fallback 10)"
    printf '%s\n' "${fallback}"
    return 0
  fi
  epel_baseurl "${n}" "${minor}"
}

# epel_import_key MAJOR - rpm --import the live-tree key (mockable). Honours
# INSECURE_TLS for the fetch.
epel_import_key() {
  local n="$1" url
  url="$(epel_gpgkey_url "${n}")" || return 1
  rpm --import "${url}"
}

# epel_write_repo MAJOR BASEURL [PATH] - write the pinned repo file (mockable).
epel_write_repo() {
  local n="$1" baseurl="$2" path="${3:-${EPEL_REPO_PATH}}"
  epel_repo_body "${n}" "${baseurl}" > "${path}"
}

# epel_cleanup [PATH] - remove the transient pinned repo file.
epel_cleanup() {
  rm -f "${1:-${EPEL_REPO_PATH}}"
}
