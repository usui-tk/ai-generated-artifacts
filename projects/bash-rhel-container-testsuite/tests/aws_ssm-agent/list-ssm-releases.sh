#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   Refresh ssm-releases.json: enumerate upstream releases into the pinned
#   in-scope version set the install/build-test matrix consumes.
# ----- Prerequisites --------------------------------------------------------
#   bash 4+, curl; network to the vendor endpoint (GitHub/AWS).
# ----- Usage examples -------------------------------------------------------
#   bash tests/aws_ssm-agent/list-ssm-releases.sh
#   bash tests/aws_ssm-agent/list-ssm-releases.sh --help
# ----- Known limitations ----------------------------------------------------
#   Network-dependent (L3); the committed JSON is the reproducible input.
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
#------------------------------------------------------------------------------
# list-ssm-releases.sh - AWS SSM Agent release-list collector (matrix input (a))
#
# Self-contained (no shared library). Collects the SSM Agent release list and
# emits a deterministic JSON snapshot that run-ssm-installtest-matrix.sh consumes.
#
# GROUND TRUTH: the 4-part git tags "<MAJOR>.<MINOR>.<BUILD>.<REV>" in
#   https://github.com/aws/amazon-ssm-agent
# read with `git ls-remote --tags` (auth-free). The per-version RPM URL is
# deterministic and matches install-ssm-agent.sh:
#   https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/<ver>/linux_amd64/amazon-ssm-agent.rpm
#
# AXES (RHEL containers): the SSM agent gates are **glibc** (the RPM's libc deps)
# and **init_mode** (systemd present -> the unit can be enabled/started; none ->
# install + `-version` only). The go.mod -> min-kernel proxy used for the OL VM
# matrix is intentionally DROPPED here: a container shares the host kernel, so the
# image kernel is not a gate. A documented MINIMUM VERSION (>= 3.3.3598.0, the AWS
# floor for full Systems Manager features; older agents are ec2messages-only) is
# recorded per version via ssm_ge() - a REUSE-BY-COPY of the matrix helper, kept
# identical and verified by tests/t009_ssmverdict.sh.
#
# DETERMINISTIC OUTPUT: no timestamp embedded.
#
# Usage:   bash tests/aws_ssm-agent/list-ssm-releases.sh [output.json]
#   env:   SSM_REPO_URL (default https://github.com/aws/amazon-ssm-agent.git)
#          SSM_RPM_BASEURL (default https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent)
#          SKIP_RPM_CHECK (default 1; 0 = HEAD-probe each RPM)
#          INSECURE_TLS (default 0; 1 = curl -k)
# Requires: git, curl, grep, sed, sort. Network: github.com (+ S3 if probing).
# Exit:    0 = wrote the JSON; non-zero = fetch/parse error (no partial file).
#------------------------------------------------------------------------------
set -euo pipefail

SSM_REPO_URL="${SSM_REPO_URL:-https://github.com/aws/amazon-ssm-agent.git}"
SOURCE_REPO="https://github.com/aws/amazon-ssm-agent"
RPM_BASEURL="${SSM_RPM_BASEURL:-https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent}"
SKIP_RPM_CHECK="${SKIP_RPM_CHECK:-1}"
SSM_MIN="3.3.3598.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-${SCRIPT_DIR}/ssm-releases.json}"

log() { printf '%s [list-ssm-releases] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

# ssm_ge <a> <b> : 4-part dotted-numeric compare (REUSE-BY-COPY of the matrix
# helper; kept identical - verified by tests/t009_ssmverdict.sh).
ssm_ge() {
  local a="$1" b="$2" hi
  [ "${a}" = "${b}" ] && return 0
  hi="$(printf '%s\n%s\n' "${a}" "${b}" | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1)"
  [ "${hi}" = "${a}" ]
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

log "fetching SSM Agent tags from ${SSM_REPO_URL} (git ls-remote --tags)"
versions="$(
  git ls-remote --tags "${SSM_REPO_URL}" 2>/dev/null \
    | sed -E 's#.*refs/tags/v?##; s/\^\{\}$//' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n -u
)"
[ -n "${versions}" ] || { log "ERROR: no 4-part SSM tags found (network down or tag scheme moved)"; exit 1; }
count="$(printf '%s\n' "${versions}" | grep -c .)"
log "found ${count} SSM versions; SKIP_RPM_CHECK=${SKIP_RPM_CHECK}"

TMP="$(mktemp)"; trap 'rm -f "${TMP}"' EXIT
{
  printf '{\n'
  printf '  "tool": "aws_ssm-agent",\n'
  printf '  "source": "%s",\n' "${SOURCE_REPO}"
  printf '  "rpm_url_template": "%s/<ver>/linux_amd64/amazon-ssm-agent.rpm",\n' "${RPM_BASEURL}"
  printf '  "min_version": "%s",\n' "${SSM_MIN}"
  printf '  "min_version_note": "AWS floor for full Systems Manager features; below it agents are ec2messages-only",\n'
  printf '  "axes": "glibc (install) + init_mode (service); container kernel is the host kernel, so no kernel gate",\n'
  printf '  "rpm_checked": %s,\n' "$( [ "${SKIP_RPM_CHECK}" = "1" ] && printf 'false' || printf 'true' )"
  printf '  "count": %s,\n' "${count}"
  printf '  "versions": [\n'
  first=1
  while IFS= read -r v; do
    [ -n "${v}" ] || continue
    url="${RPM_BASEURL}/${v}/linux_amd64/amazon-ssm-agent.rpm"
    if ssm_ge "${v}" "${SSM_MIN}"; then ge='true'; else ge='false'; fi
    if [ "${SKIP_RPM_CHECK}" = "1" ]; then
      ra='null'; rs='null'
    else
      st="$(url_check_status "${url}")"; rs="\"${st}\""
      [ "${st}" = "200" ] && ra='true' || ra='false'
    fi
    [ "${first}" = "1" ] || printf ',\n'
    first=0
    printf '    {"version": "%s", "rpm_url": "%s", "ge_min": %s, "rpm_available": %s, "rpm_http_status": %s}' \
      "${v}" "${url}" "${ge}" "${ra}" "${rs}"
  done <<< "${versions}"
  printf '\n  ]\n}\n'
} > "${TMP}"

mv "${TMP}" "${OUT}"; trap - EXIT
log "wrote ${OUT} (${count} versions)"
