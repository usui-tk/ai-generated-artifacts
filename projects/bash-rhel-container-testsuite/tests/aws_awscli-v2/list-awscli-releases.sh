#!/usr/bin/env bash
#------------------------------------------------------------------------------
# list-awscli-releases.sh - AWS CLI v2 release-list collector (matrix input (a))
#
# Self-contained by design (no shared library). Collects the AWS CLI v2 release
# list and emits it as a deterministic JSON snapshot that the install-test matrix
# (run-awscli-installtest-matrix.sh) consumes.
#
# GROUND TRUTH: the 3-part git tags "2.<MINOR>.<PATCH>" in
#   https://github.com/aws/aws-cli
# read with `git ls-remote --tags` (git protocol; auth-free, rate-limit-free). A
# leading "v" is stripped; only strict v2 3-part numeric tags are kept.
#
# MIN GLIBC (the compatibility axis): AWS CLI v2 bundles its own Python built
# against a manylinux glibc, so the OS glibc gates install/run. Per AWS's "Linux
# Support Updates for AWS CLI v2" (2024-09-16), versions >= 2.17.50 are
# manylinux2014 (glibc 2.17) and <= 2.17.49 the older manylinux1 floor (2.5).
# Computed locally by awscli_min_glibc() below - a REUSE-BY-COPY of the matrix's
# helper, kept identical and verified by tests/t008_awscliverdict.sh.
#
# ZIP PRE-CHECK: each version's deterministic bundle URL
#   https://awscli.amazonaws.com/awscli-exe-linux-x86_64-<ver>.zip
# is HEAD-probed (200/404) unless SKIP_ZIP_CHECK=1 (the default here: a fast,
# deterministic list-only snapshot; flip to 0 to record per-zip availability).
#
# DETERMINISTIC OUTPUT: no timestamp embedded, so `git diff` after a refresh
# shows exactly the newly released v2 versions.
#
# Usage:   bash tests/aws_awscli-v2/list-awscli-releases.sh [output.json]
#   env:   AWSCLI_REPO_URL (default https://github.com/aws/aws-cli.git)
#          AWSCLI_ZIP_BASEURL (default https://awscli.amazonaws.com)
#          SKIP_ZIP_CHECK (default 1; 0 = HEAD-probe each bundle zip)
#          INSECURE_TLS (default 0; 1 = curl -k for a MITM dev proxy)
# Requires: git, curl, grep, sed, sort. Network: github.com (+ S3 if probing).
# Exit:    0 = wrote the JSON; non-zero = fetch/parse error (no partial file).
#------------------------------------------------------------------------------
set -euo pipefail

AWSCLI_REPO_URL="${AWSCLI_REPO_URL:-https://github.com/aws/aws-cli.git}"
SOURCE_REPO="https://github.com/aws/aws-cli"
ZIP_BASEURL="${AWSCLI_ZIP_BASEURL:-https://awscli.amazonaws.com}"
ZIP_NAME="awscli-exe-linux-x86_64"
SKIP_ZIP_CHECK="${SKIP_ZIP_CHECK:-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-${SCRIPT_DIR}/awscli-releases.json}"

log() { printf '%s [list-awscli-releases] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

# awscli_ge <a> <b> : dotted-numeric compare (REUSE-BY-COPY of the matrix helper;
# kept identical - verified by tests/t008_awscliverdict.sh).
awscli_ge() {
  local a="$1" b="$2" hi
  [ "${a}" = "${b}" ] && return 0
  hi="$(printf '%s\n%s\n' "${a}" "${b}" | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1)"
  [ "${hi}" = "${a}" ]
}

# awscli_min_glibc <version> : documented manylinux floor (REUSE-BY-COPY; kept
# identical - verified by tests/t008_awscliverdict.sh).
awscli_min_glibc() {
  local v="${1:-}"
  [ -n "${v}" ] || { printf 'unknown'; return 0; }
  case "${v}" in *[!0-9.]*|.*|*.) printf 'unknown'; return 0 ;; esac
  if awscli_ge "${v}" "2.17.50"; then printf '2.17'; else printf '2.5'; fi
}

# url_check_status <url> : final HTTP status after redirects (200/404/000).
url_check_status() {
  local url="$1" code
  local -a opts=(-sS -I -L -o /dev/null -w '%{http_code}' --max-time "${URL_CHECK_TIMEOUT:-25}")
  [ "${INSECURE_TLS:-0}" = "1" ] && opts+=(-k)
  code="$(curl "${opts[@]}" "${url}" 2>/dev/null || true)"
  [ -n "${code}" ] || code="000"
  printf '%s' "${code}"
}

log "fetching AWS CLI v2 tags from ${AWSCLI_REPO_URL} (git ls-remote --tags)"
versions="$(
  git ls-remote --tags "${AWSCLI_REPO_URL}" 2>/dev/null \
    | sed -E 's#.*refs/tags/v?##; s/\^\{\}$//' \
    | grep -oE '^2\.[0-9]+\.[0-9]+$' \
    | sort -t. -k1,1n -k2,2n -k3,3n -u
)"
[ -n "${versions}" ] || { log "ERROR: no v2 3-part tags found (network down or tag scheme moved)"; exit 1; }
count="$(printf '%s\n' "${versions}" | grep -c .)"
log "found ${count} v2 versions; SKIP_ZIP_CHECK=${SKIP_ZIP_CHECK}"

TMP="$(mktemp)"; trap 'rm -f "${TMP}"' EXIT
{
  printf '{\n'
  printf '  "tool": "aws_awscli-v2",\n'
  printf '  "source": "%s",\n' "${SOURCE_REPO}"
  printf '  "zip_url_template": "%s/%s-<ver>.zip",\n' "${ZIP_BASEURL}" "${ZIP_NAME}"
  printf '  "min_glibc_policy": "AWS Linux Support Updates 2024-09-16: >=2.17.50 needs glibc 2.17 (manylinux2014); <=2.17.49 needs glibc 2.5 (manylinux1)",\n'
  printf '  "zip_checked": %s,\n' "$( [ "${SKIP_ZIP_CHECK}" = "1" ] && printf 'false' || printf 'true' )"
  printf '  "count": %s,\n' "${count}"
  printf '  "versions": [\n'
  first=1
  while IFS= read -r v; do
    [ -n "${v}" ] || continue
    mg="$(awscli_min_glibc "${v}")"
    url="${ZIP_BASEURL}/${ZIP_NAME}-${v}.zip"
    if [ "${SKIP_ZIP_CHECK}" = "1" ]; then
      za='null'; zs='null'
    else
      st="$(url_check_status "${url}")"
      zs="\"${st}\""
      [ "${st}" = "200" ] && za='true' || za='false'
    fi
    [ "${first}" = "1" ] || printf ',\n'
    first=0
    printf '    {"version": "%s", "min_glibc": "%s", "zip_url": "%s", "zip_available": %s, "zip_http_status": %s}' \
      "${v}" "${mg}" "${url}" "${za}" "${zs}"
  done <<< "${versions}"
  printf '\n  ]\n}\n'
} > "${TMP}"

mv "${TMP}" "${OUT}"; trap - EXIT
log "wrote ${OUT} (${count} versions)"
