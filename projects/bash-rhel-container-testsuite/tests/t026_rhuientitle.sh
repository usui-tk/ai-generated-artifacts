#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   L1 unit: lib/rhui-entitlement.sh - identity-header acquisition, injection
#   plugin writer, repo synthesis, bundle assembly (E1a).
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; hermetic (no network - IMDS curl is mocked); python3 for the
#   plugin syntax check.
# ----- Usage examples -------------------------------------------------------
#   bash tests/t026_rhuientitle.sh
#   bash tests/run-all.sh   # runs every tier
# ----- Known limitations ----------------------------------------------------
#   Asserts count failures and continue (harness scope, spec home A.5).
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-11 (r87 E1a: productionize the E0-proven B"
#   static-header injection; see CHANGELOG.md)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/t026_rhuientitle.sh - unit tier for lib/rhui-entitlement.sh
#
# Sources the library (side-effect-free) and asserts the E1a surface. The
# redhat-rhui.repo fixture reproduces the REAL el8 host file shape (archive
# aws-rhui-facts_ip-172-31-2-135_rhel8_20260711T072944Z, base/yum.repos.d/):
# literal REGION in the mirrorlist, $releasever/$basearch placeholders, ssl
# material under /etc/pki/rhui - genchi-genbutsu, not an invented shape. The
# IMDS surface is exercised through curl PATH-mocks (token PUT + document /
# signature / region GETs). Failure paths assert the assert-all-then-write
# contract: a failed acquisition leaves NO partial headers file / bundle.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
# shellcheck source=lib/mock.sh
. "${HERE}/lib/mock.sh"
LIB="${PROJ}/lib/rhui-entitlement.sh"
# shellcheck source=/dev/null
. "${LIB}"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# Fixture: the REAL el8 redhat-rhui.repo baseos section shape (see header).
write_fixture_repofile() {
  local f="$1" certdir="$2"
  cat > "${f}" <<EOF
[rhel-8-appstream-rhui-rpms]
name=Red Hat Enterprise Linux 8 for \$basearch - AppStream from RHUI (RPMs)
mirrorlist=https://rhui.REGION.aws.ce.redhat.com/pulp/mirror/content/dist/rhel8/rhui/\$releasever/\$basearch/appstream/os
enabled=1
gpgcheck=1
sslverify=1
sslclientkey=${certdir}/content-rhel8.key
sslclientcert=${certdir}/product/content-rhel8.crt
sslcacert=${certdir}/cdn.redhat.com-chain.crt

[rhel-8-baseos-rhui-rpms]
name=Red Hat Enterprise Linux 8 for \$basearch - BaseOS from RHUI (RPMs)
mirrorlist=https://rhui.REGION.aws.ce.redhat.com/pulp/mirror/content/dist/rhel8/rhui/\$releasever/\$basearch/baseos/os
enabled=1
gpgcheck=1
sslverify=1
sslclientkey=${certdir}/content-rhel8.key
sslclientcert=${certdir}/product/content-rhel8.crt
sslcacert=${certdir}/cdn.redhat.com-chain.crt
EOF
}

# The curl mock covering the whole IMDS surface (token + identity + region).
mock_imds_curl() {
  # shellcheck disable=SC2016  # the mock body expands inside the fake command
  mock_cmd curl 'for a in "$@"; do case "$a" in
    */api/token)                    printf "TESTTOKEN"; exit 0 ;;
    */instance-identity/document)   printf "{\"region\": \"ap-northeast-1\", \"instanceId\": \"i-test\"}"; exit 0 ;;
    */instance-identity/signature)  printf "RAWSIGBYTES"; exit 0 ;;
    */placement/region)             printf "ap-northeast-1"; exit 0 ;;
  esac; done; exit 0'
}

# --- b64url ------------------------------------------------------------------
# 0xfb 0xff encodes to "+/8=" in plain base64 -> "-_8=" urlsafe.
assert_eq "-_8=" "$(printf '\xfb\xff' | rhui_b64url)" "b64url: +/ translated to -_"
assert_eq "dGVzdA==" "$(printf 'test' | rhui_b64url)" "b64url: plain ascii passthrough"

# --- rhui_major_url ------------------------------------------------------------
# shellcheck disable=SC2016  # literal $releasever/$basearch placeholders
TMPL='https://rhui.REGION.aws.ce.redhat.com/pulp/mirror/content/dist/rhel8/rhui/$releasever/$basearch/baseos/os'
assert_eq "https://rhui.REGION.aws.ce.redhat.com/pulp/mirror/content/dist/rhel8/rhui/8/x86_64/baseos/os" \
  "$(rhui_major_url "${TMPL}" 8)" "major_url: self-major substitutes releasever/basearch"
assert_eq "https://rhui.REGION.aws.ce.redhat.com/pulp/mirror/content/dist/rhel9/rhui/9/x86_64/baseos/os" \
  "$(rhui_major_url "${TMPL}" 9)" "major_url: /rhelN/ retarget (pure helper property)"

# --- rhui_headers_write (mocked IMDS) -----------------------------------------
# The mocked action runs in an isolated subshell echoing a sentinel; every
# assert runs in the PARENT (the t003 pattern - subshell counter bumps are lost).
td="${WORK}/m1"; mkdir -p "${td}"
out="$(
  (
    # shellcheck source=/dev/null
    . "${LIB}"
    mock_setup "${td}"
    mock_imds_curl
    RHUI_IMDS_TOKEN=""
    if rhui_headers_write "${WORK}/headers"; then printf 'OK'; else printf 'FAIL(%s)' "$?"; fi
  )
)"
assert_eq "OK" "${out}" "headers_write: rc 0 with a healthy IMDS"
assert_eq 2 "$(wc -l < "${WORK}/headers")" "headers_write: exactly two header lines"
expect_id="$(printf '%s' '{"region": "ap-northeast-1", "instanceId": "i-test"}' | rhui_b64url)"
expect_sig="$(printf '%s' 'RAWSIGBYTES' | rhui_b64url)"
assert_eq "X-RHUI-ID: ${expect_id}" "$(sed -n 1p "${WORK}/headers")" \
  "headers_write: line 1 is the b64url identity document"
assert_eq "X-RHUI-SIGNATURE: ${expect_sig}" "$(sed -n 2p "${WORK}/headers")" \
  "headers_write: line 2 is the b64url signature"
if grep -q '[+/]' "${WORK}/headers"; then
  t_fail "headers_write: values are NOT urlsafe (raw +/ present)"
else
  t_pass "headers_write: urlsafe charset only"
fi

td="${WORK}/m2"; mkdir -p "${td}"
out="$(
  (
    # shellcheck source=/dev/null
    . "${LIB}"
    mock_setup "${td}"
    mock_cmd curl 'exit 0'   # every IMDS answer empty
    RHUI_IMDS_TOKEN=""
    if rhui_headers_write "${WORK}/headers-fail"; then printf 'OK'; else printf 'FAIL(%s)' "$?"; fi
  )
)"
assert_eq "FAIL(1)" "${out}" "headers_write: rc 1 when IMDS yields nothing"
if [ -e "${WORK}/headers-fail" ]; then
  t_fail "headers_write: partial file written on failure (assert-all-then-write violated)"
else
  t_pass "headers_write: no file on failure (assert-all-then-write)"
fi

# --- rhui_write_inject_plugin ---------------------------------------------------
rhui_write_inject_plugin "${WORK}/rhuisuite.py"
python3 -c "import ast; ast.parse(open('${WORK}/rhuisuite.py').read())" 2>/dev/null
assert_rc 0 "$?" "plugin: generated dnf plugin is valid python"
grep -q 'HEADERS_PATH = "/run/rhui-suite/headers"' "${WORK}/rhuisuite.py"
assert_rc 0 "$?" "plugin: reads the fixed mounted headers path (file-read variant)"
grep -q 'startswith(REPO_PREFIX)' "${WORK}/rhuisuite.py" \
  && grep -q 'REPO_PREFIX = "rhui-suite-"' "${WORK}/rhuisuite.py"
assert_rc 0 "$?" "plugin: injection scoped to the rhui-suite- repo prefix"
grep -q 'setHttpHeaders OK for' "${WORK}/rhuisuite.py"
assert_rc 0 "$?" "plugin: load-bearing OK marker present (plugin_fired detection)"
grep -q 'headers file unreadable' "${WORK}/rhuisuite.py"
assert_rc 0 "$?" "plugin: unreadable-headers failure is voiced, not silent"
rhui_write_inject_plugin "${WORK}/custom.py" "my-prefix-" "/custom/headers"
grep -q 'REPO_PREFIX = "my-prefix-"' "${WORK}/custom.py" \
  && grep -q 'HEADERS_PATH = "/custom/headers"' "${WORK}/custom.py"
assert_rc 0 "$?" "plugin: prefix and headers path are parameterizable"
rhui_write_plugin_conf "${WORK}/rhuisuite.conf"
assert_eq "$(printf '[main]\nenabled=1')" "$(cat "${WORK}/rhuisuite.conf")" \
  "plugin conf: [main] enabled=1"

# --- rhui_repo_template_from_host ----------------------------------------------
CERTDIR="${WORK}/pki"
mkdir -p "${CERTDIR}/product"
printf 'CERT' > "${CERTDIR}/product/content-rhel8.crt"
printf 'KEY'  > "${CERTDIR}/content-rhel8.key"
printf 'CA'   > "${CERTDIR}/cdn.redhat.com-chain.crt"
write_fixture_repofile "${WORK}/redhat-rhui.repo" "${CERTDIR}"
FIELDS="$(rhui_repo_template_from_host "${WORK}/redhat-rhui.repo")"
assert_rc 0 "$?" "template: extraction succeeds on the real-shaped fixture"
# shellcheck disable=SC2016  # literal $releasever/$basearch placeholders
assert_eq 'https://rhui.REGION.aws.ce.redhat.com/pulp/mirror/content/dist/rhel8/rhui/$releasever/$basearch/baseos/os|'"${CERTDIR}/product/content-rhel8.crt|${CERTDIR}/content-rhel8.key|${CERTDIR}/cdn.redhat.com-chain.crt" \
  "${FIELDS}" "template: TEMPLATE|CERT|KEY|CA from the BASEOS section"
rhui_repo_template_from_host "${WORK}/absent.repo" >/dev/null
assert_rc 1 "$?" "template: rc 1 when the repo file is absent"
if [ -n "${RHUI_LAST_ERR}" ]; then
  t_pass "template: RHUI_LAST_ERR names the absent file"
else
  t_fail "template: RHUI_LAST_ERR empty on failure"
fi
printf '[rhel-8-baseos-rhui-rpms]\nname=x\nenabled=1\n' > "${WORK}/incomplete.repo"
rhui_repo_template_from_host "${WORK}/incomplete.repo" >/dev/null
assert_rc 1 "$?" "template: rc 1 when the section lacks mirrorlist/ssl fields"

# --- rhui_write_repo -------------------------------------------------------------
rhui_write_repo "${WORK}/suite.repo" 8 ap-northeast-1 "${TMPL}"
grep -q '^\[rhui-suite-rhel8-baseos\]' "${WORK}/suite.repo" \
  && grep -q '^\[rhui-suite-rhel8-appstream\]' "${WORK}/suite.repo"
assert_rc 0 "$?" "write_repo: baseos + appstream sections with the injection prefix"
grep -q 'mirrorlist=https://rhui.ap-northeast-1.aws.ce.redhat.com/pulp/mirror/content/dist/rhel8/rhui/8/x86_64/baseos/os' "${WORK}/suite.repo"
assert_rc 0 "$?" "write_repo: REGION + releasever + basearch substituted (baseos)"
grep -q 'mirrorlist=https://rhui.ap-northeast-1.aws.ce.redhat.com/pulp/mirror/content/dist/rhel8/rhui/8/x86_64/appstream/os' "${WORK}/suite.repo"
assert_rc 0 "$?" "write_repo: appstream mirrorlist derived from the baseos one"
# shellcheck disable=SC2016  # literal placeholder patterns
if grep -qE 'REGION|\$releasever|\$basearch' "${WORK}/suite.repo"; then
  t_fail "write_repo: unsubstituted placeholder left in the synthesized repo"
else
  t_pass "write_repo: no unsubstituted placeholders remain"
fi
assert_eq 2 "$(grep -c 'sslclientcert=/run/rhui-suite/CERT.crt' "${WORK}/suite.repo")" \
  "write_repo: ssl cert pinned to the fixed container mount (both sections)"
assert_eq 2 "$(grep -c 'sslcacert=/run/rhui-suite/ca.crt' "${WORK}/suite.repo")" \
  "write_repo: CA pinned to the fixed container mount (both sections)"
assert_eq 2 "$(grep -c 'gpgcheck=1' "${WORK}/suite.repo")" "write_repo: gpgcheck stays ON"

# --- rhui_host_major -------------------------------------------------------------
printf 'NAME="Red Hat Enterprise Linux"\nVERSION_ID="8.10"\n' > "${WORK}/os-release"
assert_eq 8 "$(rhui_host_major "${WORK}/os-release" "${WORK}/nope")" \
  "host_major: os-release VERSION_ID major"
printf 'Red Hat Enterprise Linux release 9.4 (Plow)\n' > "${WORK}/redhat-release"
assert_eq 9 "$(rhui_host_major "${WORK}/no-osrel" "${WORK}/redhat-release")" \
  "host_major: redhat-release fallback"
rhui_host_major "${WORK}/no-osrel" "${WORK}/nope" >/dev/null
assert_rc 1 "$?" "host_major: rc 1 when neither source is readable"

# --- rhui_bundle_prepare (mocked IMDS + fixture host) ------------------------------
BUNDLE="${WORK}/bundle"
td="${WORK}/m3"; mkdir -p "${td}"
out="$(
  (
    # shellcheck source=/dev/null
    . "${LIB}"
    mock_setup "${td}"
    mock_imds_curl
    RHUI_IMDS_TOKEN=""
    if rhui_bundle_prepare "${BUNDLE}" 8 "${WORK}/redhat-rhui.repo"; then
      printf 'OK'
    else
      printf 'FAIL(%s|%s)' "$?" "${RHUI_LAST_ERR}"
    fi
  )
)"
assert_eq "OK" "${out}" "bundle: prepare rc 0 with healthy inputs"
ok=1
for f in headers CERT.crt CERT.key ca.crt rhui-suite.repo rhuisuite.py rhuisuite.conf; do
  [ -f "${BUNDLE}/${f}" ] || { ok=0; t_fail "bundle: ${f} missing"; }
done
[ "${ok}" = 1 ] && t_pass "bundle: all 7 artifacts present"
assert_eq "CERT" "$(cat "${BUNDLE}/CERT.crt")" "bundle: cert copied verbatim (self-major)"
assert_eq "KEY"  "$(cat "${BUNDLE}/CERT.key")" "bundle: key copied verbatim"
assert_eq "CA"   "$(cat "${BUNDLE}/ca.crt")"   "bundle: CA copied verbatim"
grep -q '^\[rhui-suite-rhel8-baseos\]' "${BUNDLE}/rhui-suite.repo"
assert_rc 0 "$?" "bundle: synthesized repo targets the requested self-major"
grep -q 'rhui.ap-northeast-1.aws.ce.redhat.com' "${BUNDLE}/rhui-suite.repo"
assert_rc 0 "$?" "bundle: region from IMDS substituted into the mirrorlist"

td="${WORK}/m4"; mkdir -p "${td}"
rm -f "${CERTDIR}/content-rhel8.key"
out="$(
  (
    # shellcheck source=/dev/null
    . "${LIB}"
    mock_setup "${td}"
    mock_imds_curl
    # shellcheck disable=SC2034  # consumed by the sourced lib
    RHUI_IMDS_TOKEN=""
    if rhui_bundle_prepare "${WORK}/bundle-fail" 8 "${WORK}/redhat-rhui.repo"; then
      printf 'OK'
    else
      printf 'FAIL(%s|%s)' "$?" "${RHUI_LAST_ERR}"
    fi
  )
)"
case "${out}" in
  "FAIL(1|"*) t_pass "bundle: rc 1 when a credential file is absent" ;;
  *)          t_fail "bundle: expected rc 1 on a missing credential (got: ${out})" ;;
esac
case "${out}" in
  *content-rhel8.key*) t_pass "bundle: RHUI_LAST_ERR names the missing credential" ;;
  *) t_fail "bundle: RHUI_LAST_ERR does not name the missing credential (${out})" ;;
esac
if [ -e "${WORK}/bundle-fail" ]; then
  t_fail "bundle: half-bundle left behind on failure (assert-all-then-acquire violated)"
else
  t_pass "bundle: no half-bundle on failure (assert-all-then-acquire)"
fi

t_done
