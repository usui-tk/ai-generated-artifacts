#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# list-awscli-releases.sh  --  AWS CLI v2 release-list collector (matrix input)
# ----------------------------------------------------------------------------
# Self-contained by design (no shared library). The URL pre-check below is the
# reuse-by-copy block (ADR 0003) copied VERBATIM from tests/ssm/list-ssm-releases.sh
# -- the same generic existence/fetchability probe, here pointed at the AWS CLI v2
# bundle zip on S3 rather than the SSM RPM.
#
# WHAT IT DOES. Collect the AWS CLI v2 release list and emit it as a static JSON
# snapshot, each version's linux-x86_64 bundle zip pre-checked for fetchability.
# The snapshot is the INPUT to the AWS CLI install-test matrix (the
# {OS major x AWS CLI version x kernel} ledger consumes it).
#
# SOURCE [GROUND-TRUTH]. The authoritative version list is the set of 3-part git
# tags "2.<MINOR>.<PATCH>" in
#     https://github.com/aws/aws-cli
# read with `git ls-remote --tags` -- the git protocol, NOT the GitHub REST API
# (auth-free, rate-limit-free). A leading "v" is stripped; only strict v2 3-part
# numeric tags are kept (drops "^{}" peel lines, v1 tags, and any non-version tag).
# The per-version bundle URL is deterministic and matches install-awscli.sh:
#     https://awscli.amazonaws.com/awscli-exe-linux-x86_64-<ver>.zip
#
# ZIP PRE-CHECK. Each version's bundle URL is HEAD-probed (200/404), recorded per
# version (`zip_available`, `zip_http_status`). Set SKIP_ZIP_CHECK=1 for a fast
# list-only run.
#
# MIN GLIBC (the compatibility axis). AWS CLI v2 bundles its own Python built
# against a manylinux glibc, so the OS glibc gates install/run. The per-version
# minimum glibc is a DOCUMENTED heuristic (NOT a per-binary readelf -- the matrix
# ledger is the empirical truth): per AWS's "Linux Support Updates for AWS CLI v2"
# (2024-09-16), versions >= 2.17.50 are manylinux2014 (glibc 2.17), and <= 2.17.49
# the older manylinux1 floor (2.5). Computed locally (no per-version download) by
# awscli_min_glibc() below -- a REUSE-BY-COPY of the same helper in
# run-awscli-installtest-matrix.sh (kept identical; verified by t19_awscliverdict.sh).
#
# DETERMINISTIC OUTPUT. No timestamp embedded: re-running changes the file ONLY
# when the upstream tag set (or a zip's availability) changes, so `git diff` after
# a refresh shows exactly the newly released AWS CLI v2 versions.
#
# Usage:   bash tests/awscli/list-awscli-releases.sh [output.json]
#   default output: tests/awscli/awscli-releases.json (beside this script)
#   env:   AWSCLI_REPO_URL  (default https://github.com/aws/aws-cli.git)
#          AWSCLI_ZIP_BASEURL (default https://awscli.amazonaws.com)
#          SKIP_ZIP_CHECK   (default 0; 1 = list only, no per-zip probe)
#          INSECURE_TLS     (default 0; 1 = curl -k, for a MITM dev proxy)
#          URL_CHECK_TIMEOUT (default 25; per-probe timeout in seconds)
# Requires: git, curl, grep, sed, sort. Network reachable to github.com + S3.
# Exit:    0 = wrote the JSON; non-zero = fetch/parse error (no partial file).
# ----------------------------------------------------------------------------
set -euo pipefail

AWSCLI_REPO_URL="${AWSCLI_REPO_URL:-https://github.com/aws/aws-cli.git}"
SOURCE_REPO="https://github.com/aws/aws-cli"
ZIP_BASEURL="${AWSCLI_ZIP_BASEURL:-https://awscli.amazonaws.com}"
ZIP_NAME="awscli-exe-linux-x86_64"
ZIP_URL_TMPL="${ZIP_BASEURL}/${ZIP_NAME}-<ver>.zip"
SKIP_ZIP_CHECK="${SKIP_ZIP_CHECK:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-${SCRIPT_DIR}/awscli-releases.json}"

log() { printf '%s [list-awscli-releases] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

# --- reuse-by-copy block (ADR 0003): generic URL existence/fetchability probe --
# Copied verbatim from tests/ssm/list-ssm-releases.sh. Depends only on curl.
# Honors INSECURE_TLS=1 (-k) and URL_CHECK_TIMEOUT (default 25s). Echoes the
# final HTTP status after redirects (e.g. 200, 404), or 000 when unreachable.
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

# awscli_ge <a> <b> : dotted-numeric compare (REUSE-BY-COPY of the matrix helper;
# kept identical -- verified by tests/t19_awscliverdict.sh).
awscli_ge() {
  local a="$1" b="$2" hi
  [ "${a}" = "${b}" ] && return 0
  hi="$(printf '%s\n%s\n' "${a}" "${b}" | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1)"
  [ "${hi}" = "${a}" ]
}

# awscli_min_glibc <version> : documented manylinux floor (REUSE-BY-COPY of the
# matrix helper; kept identical -- verified by tests/t19_awscliverdict.sh).
awscli_min_glibc() {
  local v="${1:-}"
  [ -n "${v}" ] || { printf 'unknown'; return 0; }
  case "${v}" in *[!0-9.]*|.*|*.) printf 'unknown'; return 0 ;; esac
  if awscli_ge "${v}" "2.17.50"; then printf '2.17'; else printf '2.5'; fi
}

log "fetching AWS CLI v2 tags from ${AWSCLI_REPO_URL} (git ls-remote --tags)"
# refs/tags/<2.Y.Z> -> 2.Y.Z. Strip a leading "v"; keep ONLY strict v2 3-part
# numeric versions (drops "^{}" peel lines, v1 tags, and any non-version tag);
# sorted ascending + unique.
versions="$(
  git ls-remote --tags "${AWSCLI_REPO_URL}" 2>/dev/null \
    | sed -E 's#.*refs/tags/v?##; s/\^\{\}$//' \
    | grep -oE '^2\.[0-9]+\.[0-9]+$' \
    | sort -t. -k1,1n -k2,2n -k3,3n -u
)"

if [ -z "${versions}" ]; then
  log "ERROR: no v2 3-part version tags found (network down, or the tag scheme moved)"
  exit 1
fi

count="$(printf '%s\n' "${versions}" | grep -c .)"
log "found ${count} AWS CLI v2 versions (newest: $(printf '%s\n' "${versions}" | tail -1))"

if [ "${SKIP_ZIP_CHECK}" = "1" ]; then
  check_mode="skipped"
  log "SKIP_ZIP_CHECK=1 -> list only (no per-zip availability probe)"
else
  check_mode="performed"
  log "pre-checking ${count} bundle zip URLs for existence/fetchability (HEAD)..."
fi

# Emit deterministic JSON to a temp file, then move into place atomically.
tmp="$(mktemp)"
avail=0
unavail=0
{
  printf '{\n'
  printf '  "schema_version": "1.0",\n'
  printf '  "list_type": "awscli-releases",\n'
  printf '  "source_repo": "%s",\n' "${SOURCE_REPO}"
  printf '  "source_method": "git ls-remote --tags",\n'
  printf '  "zip_url_template": "%s",\n' "${ZIP_URL_TMPL}"
  printf '  "zip_check": "%s",\n' "${check_mode}"
  printf '  "min_glibc_method": "documented heuristic (>=2.17.50 -> 2.17 manylinux2014; <=2.17.49 -> 2.5)",\n'
  printf '  "generated_by": "tests/awscli/list-awscli-releases.sh",\n'
  printf '  "count": %s,\n' "${count}"
  i=0
  body=""
  while IFS= read -r v; do
    [ -n "${v}" ] || continue
    i=$((i + 1))
    url="${ZIP_BASEURL}/${ZIP_NAME}-${v}.zip"
    if [ "${SKIP_ZIP_CHECK}" = "1" ]; then
      av="null"; status="unchecked"
    else
      status="$(url_check_status "${url}")"
      case "${status}" in
        2??) av="true";  avail=$((avail + 1)) ;;
        *)   av="false"; unavail=$((unavail + 1)); log "  UNAVAILABLE ${v} (HTTP ${status})" ;;
      esac
      if [ $((i % 10)) -eq 0 ]; then log "  ...checked ${i}/${count}"; fi
    fi
    ming="$(awscli_min_glibc "${v}")"
    if [ "${i}" -eq "${count}" ]; then sep=""; else sep=","; fi
    body+="$(printf '    { "version": "%s", "zip_url": "%s", "zip_available": %s, "zip_http_status": "%s", "min_glibc": "%s" }%s\n' \
      "${v}" "${url}" "${av}" "${status}" "${ming}" "${sep}")"
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
