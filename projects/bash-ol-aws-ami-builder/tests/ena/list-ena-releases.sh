#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# list-ena-releases.sh  --  ENA driver release-list collector (test matrix input)
# ----------------------------------------------------------------------------
# Self-contained by design: this script carries its own helper functions inline
# (no shared library / no sourced module), the repository's standard policy for
# user-runnable scripts. The URL pre-check below is a reuse-by-copy block
# (ADR 0003): copy the `url_check_status` function verbatim into other tests
# that must verify a download before depending on it (e.g. the AWS SSM Agent
# RPM on S3) rather than sourcing a shared lib.
#
# WHAT IT DOES. Collect the Amazon ENA Linux driver release list from the
# amzn-drivers GitHub repository and emit it as a static JSON snapshot, with each
# version's source tarball pre-checked for existence/fetchability. The snapshot
# is the INPUT to the ENA self-build test matrix (the {OS major x ENA version x
# kernel} ledger consumes it): "test every ENA version" reads the versions[]
# array, and `tarball_available` lets the matrix skip / flag a version whose
# source archive cannot be fetched before it ever spins up a container.
#
# SOURCE [GROUND-TRUTH]. The authoritative ENA version list is the set of git
# tags "ena_linux_<MAJOR>.<MINOR>.<PATCH>" in
#     https://github.com/amzn/amzn-drivers
# read with `git ls-remote --tags` -- the git protocol, NOT the GitHub REST API.
# ls-remote needs no auth and is not subject to the REST API's 60-request/hour
# unauthenticated rate limit, which is shared-IP-exhausted on CI runners and the
# sandbox (the REST /tags endpoint returns 403 "rate limit exceeded" there). Each
# version's source tarball URL is deterministic:
#     https://github.com/amzn/amzn-drivers/archive/refs/tags/ena_linux_<ver>.tar.gz
# which is exactly what install-ena-driver.sh fetches.
#
# TARBALL PRE-CHECK. For each version the tarball URL is HEAD-probed (following
# the GitHub -> codeload 302 redirect to a real 200/404), and the result is
# recorded per version (`tarball_available`, `tarball_http_status`). This is the
# reusable existence/fetchability gate. Set SKIP_TARBALL_CHECK=1 for a fast
# list-only run (no network probes; availability emitted as null/"unchecked").
#
# DETERMINISTIC OUTPUT. The JSON embeds no timestamp: re-running changes the file
# ONLY when the upstream tag set (or a tarball's availability) changes, so
# `git diff` after a refresh shows exactly the newly released ENA versions -- the
# "test the diff on a new ENA release" signal the matrix is built around.
#
# ENA EXPRESS SCOPE + READINESS (schema 1.2, mirrors the RHEL sibling's lister).
# The snapshot carries `min_version` (default 2.8.0 -- the ENA Express
# express-ready floor: ena_srd_* metrics require driver >= 2.8.0 per AWS
# ena-express.html) and each version entry carries `ge_min` (in the matrix's
# DEFAULT sweep scope) plus `express_verdict` (ena_express_verdict() below:
# < 2.2.9 not-ready, >= 2.2.9 bandwidth-only, >= 2.8.0 express-ready). The
# matrix reads `min_version` as its default floor; `--full` sweeps everything.
#
# Usage:   bash tests/ena/list-ena-releases.sh [output.json]
#   default output: tests/ena/ena-driver-releases.json (beside this script)
#   env:   ENA_REPO_URL        (default https://github.com/amzn/amzn-drivers.git)
#          ENA_MIN_VERSION     (default 2.8.0; the recorded min_version floor)
#          SKIP_TARBALL_CHECK  (default 0; 1 = list only, no per-tarball probe)
#          INSECURE_TLS        (default 0; 1 = curl -k, for a MITM dev proxy)
#          URL_CHECK_TIMEOUT   (default 25; per-probe timeout in seconds)
# Requires: git, curl, grep, sed, sort (coreutils). Network reachable to github.com.
# Exit:    0 = wrote the JSON; non-zero = fetch/parse error (no partial file).
# ----------------------------------------------------------------------------
set -euo pipefail

ENA_REPO_URL="${ENA_REPO_URL:-https://github.com/amzn/amzn-drivers.git}"
SOURCE_REPO="https://github.com/amzn/amzn-drivers"
TAG_PREFIX="ena_linux_"
TARBALL_TMPL="${SOURCE_REPO}/archive/refs/tags/${TAG_PREFIX}<ver>.tar.gz"
SKIP_TARBALL_CHECK="${SKIP_TARBALL_CHECK:-0}"
ENA_MIN="${ENA_MIN_VERSION:-2.8.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-${SCRIPT_DIR}/ena-driver-releases.json}"

log() { printf '%s [list-ena-releases] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

# --- reuse-by-copy block (ADR 0003): generic URL existence/fetchability probe --
# Copy verbatim into other tests (e.g. an AWS SSM Agent RPM pre-check). Depends
# only on curl. Honors INSECURE_TLS=1 (-k) and URL_CHECK_TIMEOUT (default 25s).
# Echoes the final HTTP status after redirects (e.g. 200, 404), or 000 when the
# host is unreachable / curl errored (DNS, refused, blocked egress, timeout).
# HEAD (no body); falls back to a 1-byte range GET if the server rejects HEAD.
url_check_status() {
  local url="$1" code to
  to="${URL_CHECK_TIMEOUT:-25}"
  local -a head_opts=(-sS -I -L -o /dev/null -w '%{http_code}' --max-time "${to}")
  if [ "${INSECURE_TLS:-0}" = "1" ]; then head_opts+=(-k); fi
  code="$(curl "${head_opts[@]}" "${url}" 2>/dev/null || true)"
  [ -n "${code}" ] || code="000"
  if [ "${code}" = "405" ]; then
    local -a range_opts=(-sS -L -r 0-0 -o /dev/null -w '%{http_code}' --max-time "${to}")
    if [ "${INSECURE_TLS:-0}" = "1" ]; then range_opts+=(-k); fi
    code="$(curl "${range_opts[@]}" "${url}" 2>/dev/null || true)"
    [ -n "${code}" ] || code="000"
  fi
  printf '%s' "${code}"
}
# --- end reuse-by-copy block -------------------------------------------------

# ver_ge <a> <b> : dotted version compare (a >= b). REUSE-BY-COPY of the matrix
# helper (tests/t021_enaexpress.sh guards the copies against drift).
ver_ge() {
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
}

# ena_express_verdict <version> : AWS ENA Express driver-version floor
# (ena-express.html: >= 2.2.9 full bandwidth, >= 2.8.0 ena_srd_* metrics).
# REUSE-BY-COPY of the install-ena-driver.sh helper (the source of truth);
# kept identical -- verified by tests/t021_enaexpress.sh. Pure function of the
# version only -- NOT an eligibility check: ENA Express itself is enabled via
# the AWS API EnaSrdEnabled ENI-attachment attribute and gated by instance
# type; meeting the floor is necessary, not sufficient.
ena_express_verdict() {
  local v="${1:-}"
  [ -n "${v}" ] || { printf 'unknown'; return 0; }
  if ver_ge "${v}" "2.8.0"; then printf 'express-ready'; return 0; fi
  if ver_ge "${v}" "2.2.9"; then printf 'bandwidth-only'; return 0; fi
  printf 'not-ready'
}

log "fetching ENA driver tags from ${ENA_REPO_URL} (git ls-remote --tags)"
# refs/tags/ena_linux_X.Y.Z -> X.Y.Z. The `^{}` annotated-tag peel lines and any
# non-semver tags are dropped by the strict regex; sorted ascending + unique.
versions="$(
  git ls-remote --tags "${ENA_REPO_URL}" 2>/dev/null \
    | grep -oE "${TAG_PREFIX}[0-9]+\.[0-9]+\.[0-9]+" \
    | sed "s/^${TAG_PREFIX}//" \
    | sort -t. -k1,1n -k2,2n -k3,3n -u
)"

if [ -z "${versions}" ]; then
  log "ERROR: no ${TAG_PREFIX}* tags found (network down, or the repo/tag scheme moved)"
  exit 1
fi

count="$(printf '%s\n' "${versions}" | grep -c .)"
log "found ${count} ENA driver versions (newest: $(printf '%s\n' "${versions}" | tail -1))"

if [ "${SKIP_TARBALL_CHECK}" = "1" ]; then
  check_mode="skipped"
  log "SKIP_TARBALL_CHECK=1 -> list only (no per-tarball availability probe)"
else
  check_mode="performed"
  log "pre-checking ${count} tarball URLs for existence/fetchability (HEAD)..."
fi

# Emit deterministic JSON to a temp file, then move into place so a failed run
# never leaves a half-written snapshot. Versions ascending; 2-space indent.
tmp="$(mktemp)"
avail=0
unavail=0
{
  printf '{\n'
  printf '  "schema_version": "1.2",\n'
  printf '  "min_version": "%s",\n' "${ENA_MIN}"
  printf '  "list_type": "ena-driver-releases",\n'
  printf '  "source_repo": "%s",\n' "${SOURCE_REPO}"
  printf '  "source_method": "git ls-remote --tags",\n'
  printf '  "tag_prefix": "%s",\n' "${TAG_PREFIX}"
  printf '  "tarball_url_template": "%s",\n' "${TARBALL_TMPL}"
  printf '  "tarball_check": "%s",\n' "${check_mode}"
  printf '  "generated_by": "tests/ena/list-ena-releases.sh",\n'
  printf '  "count": %s,\n' "${count}"
  i=0
  body=""
  while IFS= read -r v; do
    [ -n "${v}" ] || continue
    i=$((i + 1))
    url="${SOURCE_REPO}/archive/refs/tags/${TAG_PREFIX}${v}.tar.gz"
    if [ "${SKIP_TARBALL_CHECK}" = "1" ]; then
      av="null"; status="unchecked"
    else
      status="$(url_check_status "${url}")"
      case "${status}" in
        2??) av="true";  avail=$((avail + 1)) ;;
        *)   av="false"; unavail=$((unavail + 1)); log "  UNAVAILABLE ${TAG_PREFIX}${v} (HTTP ${status})" ;;
      esac
      if [ $((i % 10)) -eq 0 ]; then log "  ...checked ${i}/${count}"; fi
    fi
    if [ "${i}" -eq "${count}" ]; then sep=""; else sep=","; fi
    if ver_ge "${v}" "${ENA_MIN}"; then ge="true"; else ge="false"; fi
    body+="$(printf '    { "version": "%s", "tag": "%s%s", "tarball_url": "%s", "tarball_available": %s, "tarball_http_status": "%s", "ge_min": %s, "express_verdict": "%s" }%s\n' \
      "${v}" "${TAG_PREFIX}" "${v}" "${url}" "${av}" "${status}" "${ge}" "$(ena_express_verdict "${v}")" "${sep}")"
    body+=$'\n'
  done <<< "${versions}"
  printf '  "available_count": %s,\n' "${avail}"
  printf '  "unavailable_count": %s,\n' "${unavail}"
  printf '  "versions": [\n'
  printf '%s' "${body}"
  printf '  ]\n'
  printf '}\n'
} > "${tmp}"

mv -f "${tmp}" "${OUT}"
log "wrote ${OUT} (${count} versions; check=${check_mode}, available=${avail}, unavailable=${unavail})"
