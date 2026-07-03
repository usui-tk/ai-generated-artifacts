#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   L1/L2: the SSM 'unavailable' status (unpublished-at-S3 rpm) in
#   run-ssm-installtest-matrix.sh - classification, ledger row shape, and the
#   hermetic report rendering.
# ----- Prerequisites --------------------------------------------------------
#   bash 4+, python3; hermetic (no network, no containers - fixtures + the
#   script's --generate-results path).
# ----- Usage examples -------------------------------------------------------
#   bash tests/t022_ssmunavailable.sh
#   bash tests/run-all.sh
# ----- Known limitations ----------------------------------------------------
#   Asserts count failures and continue (harness scope, spec home A.5). The
#   network HEAD (ssm_rpm_http_status) is exercised on a real --run, not here.
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Opus 4.8), claude.ai sessions
#   Generation date: 2026-07-03 (r34: S3-unavailable status)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/t022_ssmunavailable.sh - a version whose agent rpm is UNPUBLISHED at S3
# (403/404) is recorded as a distinct 'unavailable' status, not install-fail.
# Covers the pure classifier (ssm_rpm_unavailable), the rpm URL builder, the
# ledger row shape (ssm_unavail_row), and end-to-end report rendering via the
# hermetic --generate-results path (which transitively exercises ledger_verdict
# and the report's unavailable cells).
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
MATRIX="${PROJ}/tests/aws_ssm-agent/run-ssm-installtest-matrix.sh"

# Load the helpers under test out of the matrix without running its main:
# single-line functions via an anchored grep+eval, multi-line ones via a sed
# range. rhel_glibc is a dependency of ssm_unavail_row; log is stubbed.
eval "$(grep -E '^ssm_rpm_url\(\) ' "${MATRIX}")"
eval "$(grep -E '^ssm_rpm_unavailable\(\) ' "${MATRIX}")"
# shellcheck disable=SC1090
. <(sed -n '/^ssm_unavail_row()/,/^}/p' "${MATRIX}")
# shellcheck disable=SC1090
. <(sed -n '/^rhel_glibc()/,/^}/p' "${MATRIX}")
log() { :; }
# shellcheck disable=SC2034  # read by the eval-loaded ssm_rpm_url
RPM_BASEURL="https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent"

if ! declare -F ssm_rpm_unavailable >/dev/null 2>&1 || ! declare -F ssm_unavail_row >/dev/null 2>&1; then
  t_fail "could not load the unavailable helpers from run-ssm-installtest-matrix.sh"; t_done; exit
fi

# --- ssm_rpm_unavailable: only 403/404 are the terminal 'unpublished' status --
ssm_rpm_unavailable 403; assert_rc 0 "$?" "HTTP 403 -> unavailable (unpublished)"
ssm_rpm_unavailable 404; assert_rc 0 "$?" "HTTP 404 -> unavailable (unpublished)"
ssm_rpm_unavailable 200; assert_rc 1 "$?" "HTTP 200 -> available (not unavailable)"
ssm_rpm_unavailable 000; assert_rc 1 "$?" "HTTP 000 -> transient, not unavailable"
ssm_rpm_unavailable 500; assert_rc 1 "$?" "HTTP 500 -> transient, not unavailable"
ssm_rpm_unavailable "";  assert_rc 1 "$?" "empty status -> not unavailable"

# --- ssm_rpm_url: version-global S3 path -------------------------------------
assert_eq "https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/3.3.3883.0/linux_amd64/amazon-ssm-agent.rpm" \
  "$(ssm_rpm_url 3.3.3883.0)" "ssm_rpm_url builds the per-version S3 rpm URL"

# --- ssm_unavail_row: the ledger row shape -----------------------------------
rowf="$(mktemp)"
ssm_unavail_row 6 3.3.4364.0 none 403 "${rowf}"
row="$(cat "${rowf}")"; rm -f "${rowf}"
assert_match "${row}" '"status":"unavailable"'  "row carries status=unavailable"
assert_match "${row}" '"verdict":"unavailable"' "row carries verdict=unavailable"
assert_match "${row}" '"installed":false'       "row is installed=false"
assert_match "${row}" '"ran":false'             "row is ran=false"
assert_match "${row}" '"ssm_version":"3.3.4364.0"' "row carries the version"
assert_match "${row}" 'HTTP 403'                "row reason records the HTTP status"
# the row must be valid JSON
printf '%s' "${row}" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null
assert_rc 0 "$?" "ssm_unavail_row emits valid JSON"

# --- report rendering (hermetic --generate-results) --------------------------
wd="$(mktemp -d)"
cat > "${wd}/rel.json" <<'JSON'
{"versions":[{"version":"3.3.3598.0"},{"version":"3.3.3883.0"},{"version":"3.3.4108.0"}]}
JSON
cat > "${wd}/led.json" <<'JSON'
{"host":{"os":"RHEL 10.2","kernel":"6.12.0","arch":"x86_64","selinux":"enforcing","runtime":"podman"},"results":[
 {"status":"ok","osmajor":"10","ssm_version":"3.3.3598.0","init_mode":"none","installed":true,"ran":true,"service_enabled":false,"verdict":"runs-no-init","reason":""},
 {"status":"unavailable","osmajor":"10","ssm_version":"3.3.3883.0","init_mode":"none","installed":false,"ran":false,"service_enabled":false,"verdict":"unavailable","reason":"rpm not published at s3 (HTTP 403)"},
 {"status":"ok","osmajor":"10","ssm_version":"3.3.4108.0","init_mode":"none","installed":true,"ran":true,"service_enabled":false,"verdict":"runs-no-init","reason":""}
]}
JSON
OSMAJORS=10 bash "${MATRIX}" --generate-results --releases "${wd}/rel.json" --ledger "${wd}/led.json" --results-dir "${wd}" >/dev/null 2>&1
rc=$?
assert_rc 0 "${rc}" "--generate-results runs hermetically over the fixtures"
if [ -f "${wd}/RESULTS-rhel10.md" ]; then
  row3883="$(grep -E '^\| 3\.3\.3883\.0 ' "${wd}/RESULTS-rhel10.md" || true)"
  assert_match "${row3883}" 'unavailable' "report renders the unpublished version as unavailable"
  avail_row="$(grep -E '^\| 3\.3\.4108\.0 ' "${wd}/RESULTS-rhel10.md" || true)"
  case "${avail_row}" in
    *unavailable*) t_fail "an available version must not be marked unavailable" ;;
    *) t_pass "an available version is not marked unavailable" ;;
  esac
else
  t_fail "report RESULTS-rhel10.md was not generated"
fi
rm -rf "${wd}"

t_done
