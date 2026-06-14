#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# list-ssm-releases.sh  --  AWS SSM Agent release-list collector (matrix input)
# ----------------------------------------------------------------------------
# Self-contained by design (no shared library). The URL pre-check below is the
# reuse-by-copy block (ADR 0003) copied VERBATIM from tests/ena/list-ena-releases.sh
# -- the same generic existence/fetchability probe, here pointed at the SSM RPM
# on S3 rather than the ENA source tarball on GitHub.
#
# WHAT IT DOES. Collect the AWS SSM Agent release list and emit it as a static
# JSON snapshot, each version's linux_amd64 RPM pre-checked for fetchability. The
# snapshot is the INPUT to the SSM install-test matrix (the
# {OS major x SSM version x kernel} ledger consumes it).
#
# SOURCE [GROUND-TRUTH]. The authoritative version list is the set of 4-part git
# tags "<MAJOR>.<MINOR>.<PATCH>.<BUILD>" in
#     https://github.com/aws/amazon-ssm-agent
# read with `git ls-remote --tags` -- the git protocol, NOT the GitHub REST API
# (same auth-free, rate-limit-free rationale as the ENA collector). A leading "v"
# is stripped; non-4-part / noise tags (e.g. "help") are dropped by the strict
# regex. The per-version RPM URL is deterministic:
#     https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/<ver>/linux_amd64/amazon-ssm-agent.rpm
# which is exactly what install-ssm-agent.sh fetches (plus the /latest/ alias).
#
# RPM PRE-CHECK. Each version's RPM URL is HEAD-probed (200/404), recorded per
# version (`rpm_available`, `rpm_http_status`). Set SKIP_RPM_CHECK=1 for a fast
# list-only run.
#
# GO BUILD VERSION (kernel-axis proxy). The SSM Agent is a Go program; the Go
# toolchain version it is built with sets its MINIMUM Linux kernel (the container
# install-test is faithful on glibc but NOT on the kernel axis -- it runs on the
# runner's kernel). The reliable, recordable signal is the `go` directive in the
# release's go.mod, fetched per version from raw.githubusercontent.com (a tiny
# file -- no 25 MB source tarball). Each version records, mirroring the rpm fields:
#   go_version           the `go` directive (e.g. "1.24"), or null
#   go_version_available  true/false -- whether a go_version was found (false on
#                        pre-go-modules tags, which have no go.mod at all)
#   go_mod_http_status   the go.mod fetch status ("200", "404", ...): "404" is the
#                        pre-modules absence; a "200" with go_version=null would be
#                        a go.mod present but carrying no `go` directive
#   min_kernel           the kernel-axis proxy derived from go_version via
#                        go_min_kernel() ("3.2" / "2.6.32" / "2.6.23" / "unknown")
# (The spec file's `BuildRequires: golang` is STALE -- it reads "1.15.12" even on
# the latest, which go.mod shows is go 1.25 -- so go.mod is the source of truth.)
# Set SKIP_GO_VERSION=1 to skip the per-version go.mod fetch (the four fields are
# then null/unchecked/unknown).
#
# DETERMINISTIC OUTPUT. No timestamp embedded: re-running changes the file ONLY
# when the upstream tag set (or an RPM's availability) changes, so `git diff`
# after a refresh shows exactly the newly released SSM versions.
#
# Usage:   bash tests/ssm/list-ssm-releases.sh [output.json]
#   default output: tests/ssm/ssm-agent-releases.json (beside this script)
#   env:   SSM_REPO_URL    (default https://github.com/aws/amazon-ssm-agent.git)
#          SKIP_RPM_CHECK  (default 0; 1 = list only, no per-RPM probe)
#          SKIP_GO_VERSION (default 0; 1 = do not fetch per-version go.mod)
#          INSECURE_TLS    (default 0; 1 = curl -k, for a MITM dev proxy)
#          URL_CHECK_TIMEOUT (default 25; per-probe timeout in seconds)
# Requires: git, curl, grep, sed, sort. Network reachable to github.com + S3
#   (+ raw.githubusercontent.com unless SKIP_GO_VERSION=1).
# Exit:    0 = wrote the JSON; non-zero = fetch/parse error (no partial file).
# ----------------------------------------------------------------------------
set -euo pipefail

SSM_REPO_URL="${SSM_REPO_URL:-https://github.com/aws/amazon-ssm-agent.git}"
SOURCE_REPO="https://github.com/aws/amazon-ssm-agent"
RPM_BASEURL="https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent"
RPM_ARCH="linux_amd64"
RPM_URL_TMPL="${RPM_BASEURL}/<ver>/${RPM_ARCH}/amazon-ssm-agent.rpm"
GOMOD_URL_TMPL="https://raw.githubusercontent.com/aws/amazon-ssm-agent/<ver>/go.mod"
SKIP_RPM_CHECK="${SKIP_RPM_CHECK:-0}"
SKIP_GO_VERSION="${SKIP_GO_VERSION:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-${SCRIPT_DIR}/ssm-agent-releases.json}"

log() { printf '%s [list-ssm-releases] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

# --- reuse-by-copy block (ADR 0003): generic URL existence/fetchability probe --
# Copied verbatim from tests/ena/list-ena-releases.sh. Depends only on curl.
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

# Fetch the `go` directive from a release's go.mod (the kernel-axis build signal),
# via raw.githubusercontent.com (a tiny file -- not the 25 MB source tarball).
# Echoes e.g. "1.24", or "" if unavailable. Honors INSECURE_TLS / URL_CHECK_TIMEOUT.
# Probe a release's go.mod (the kernel-axis build signal) via raw.githubusercontent
# (a tiny file -- not the 25 MB source tarball). Echoes "<http_status>\t<go_ver>"
# (go_ver empty when the file is absent or carries no `go` directive). Does NOT use
# curl -f, so a 404 yields the status (404) + empty version rather than an error.
probe_gomod() {
  local ver="$1" url to resp status body
  url="${GOMOD_URL_TMPL//<ver>/${ver}}"
  to="${URL_CHECK_TIMEOUT:-25}"
  local -a opts=(-sS --max-time "${to}" -w '\n%{http_code}')
  if [ "${INSECURE_TLS:-0}" = "1" ]; then opts+=(-k); fi
  resp="$(curl "${opts[@]}" "${url}" 2>/dev/null || true)"
  status="$(printf '%s' "${resp}" | tail -n1)"
  body="$(printf '%s' "${resp}" | sed '$d')"
  printf '%s\t%s\n' "${status:-000}" \
    "$(printf '%s\n' "${body}" | grep -oE '^go [0-9]+\.[0-9]+' | head -1 | awk '{print $2}' || true)"
}

# Map a go.mod `go` directive (e.g. 1.24) to the Go toolchain's published MINIMUM
# Linux kernel (the kernel-axis proxy). REUSE-BY-COPY of go_min_kernel() in
# tests/ssm/run-ssm-installtest-matrix.sh -- keep the two identical (the shared
# logic is exercised by tests/t18_ssmverdict.sh). Empty -> "unknown".
go_min_kernel() {
  local gov="${1:-}" maj min
  [ -n "${gov}" ] || { printf 'unknown'; return 0; }
  maj="${gov%%.*}"; min="${gov#*.}"; min="${min%%.*}"
  case "${maj}" in ''|*[!0-9]*) printf 'unknown'; return 0 ;; esac
  case "${min}" in ''|*[!0-9]*) min=0 ;; esac
  if [ "${maj}" -gt 1 ]; then printf '3.2'; return 0; fi
  if   [ "${min}" -ge 21 ]; then printf '3.2'
  elif [ "${min}" -ge 18 ]; then printf '2.6.32'
  else printf '2.6.23'; fi
}

log "fetching SSM Agent tags from ${SSM_REPO_URL} (git ls-remote --tags)"
# refs/tags/<X.Y.Z.B> -> X.Y.Z.B. Strip a leading "v"; keep ONLY strict 4-part
# numeric versions (drops "^{}" peel lines, "help", and any non-version tag);
# sorted ascending + unique.
versions="$(
  git ls-remote --tags "${SSM_REPO_URL}" 2>/dev/null \
    | sed -E 's#.*refs/tags/v?##; s/\^\{\}$//' \
    | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n -u
)"

if [ -z "${versions}" ]; then
  log "ERROR: no 4-part version tags found (network down, or the tag scheme moved)"
  exit 1
fi

count="$(printf '%s\n' "${versions}" | grep -c .)"
log "found ${count} SSM Agent versions (newest: $(printf '%s\n' "${versions}" | tail -1))"

if [ "${SKIP_RPM_CHECK}" = "1" ]; then
  check_mode="skipped"
  log "SKIP_RPM_CHECK=1 -> list only (no per-RPM availability probe)"
else
  check_mode="performed"
  log "pre-checking ${count} RPM URLs for existence/fetchability (HEAD)..."
fi

if [ "${SKIP_GO_VERSION}" = "1" ]; then
  govmode="skipped"
  log "SKIP_GO_VERSION=1 -> not fetching per-version go.mod"
else
  govmode="performed"
  log "fetching per-version go.mod 'go' directive (kernel-axis build signal)..."
fi

# Emit deterministic JSON to a temp file, then move into place atomically.
tmp="$(mktemp)"
avail=0
unavail=0
{
  printf '{\n'
  printf '  "schema_version": "1.0",\n'
  printf '  "list_type": "ssm-agent-releases",\n'
  printf '  "source_repo": "%s",\n' "${SOURCE_REPO}"
  printf '  "source_method": "git ls-remote --tags",\n'
  printf '  "rpm_url_template": "%s",\n' "${RPM_URL_TMPL}"
  printf '  "rpm_check": "%s",\n' "${check_mode}"
  printf '  "go_version_check": "%s",\n' "${govmode}"
  printf '  "generated_by": "tests/ssm/list-ssm-releases.sh",\n'
  printf '  "count": %s,\n' "${count}"
  i=0
  body=""
  while IFS= read -r v; do
    [ -n "${v}" ] || continue
    i=$((i + 1))
    url="${RPM_BASEURL}/${v}/${RPM_ARCH}/amazon-ssm-agent.rpm"
    if [ "${SKIP_RPM_CHECK}" = "1" ]; then
      av="null"; status="unchecked"
    else
      status="$(url_check_status "${url}")"
      case "${status}" in
        2??) av="true";  avail=$((avail + 1)) ;;
        *)   av="false"; unavail=$((unavail + 1)); log "  UNAVAILABLE ${v} (HTTP ${status})" ;;
      esac
      if [ $((i % 10)) -eq 0 ]; then log "  ...checked ${i}/${count}"; fi
    fi
    if [ "${SKIP_GO_VERSION}" = "1" ]; then
      gov="null"; gv_avail="null"; gomod_status="unchecked"; mink="unknown"
    else
      gv="$(probe_gomod "${v}")"
      gomod_status="${gv%%$'\t'*}"; gv="${gv#*$'\t'}"
      if [ -n "${gv}" ]; then gov="\"${gv}\""; gv_avail="true"; else gov="null"; gv_avail="false"; fi
      mink="$(go_min_kernel "${gv}")"
    fi
    if [ "${i}" -eq "${count}" ]; then sep=""; else sep=","; fi
    body+="$(printf '    { "version": "%s", "rpm_url": "%s", "rpm_available": %s, "rpm_http_status": "%s", "go_version": %s, "go_version_available": %s, "go_mod_http_status": "%s", "min_kernel": "%s" }%s\n' \
      "${v}" "${url}" "${av}" "${status}" "${gov}" "${gv_avail}" "${gomod_status}" "${mink}" "${sep}")"
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
