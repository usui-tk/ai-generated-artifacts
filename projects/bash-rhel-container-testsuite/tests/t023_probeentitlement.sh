#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   L1: the unified probe's pure layer (lib/probe-common.sh + the collector
#   emitted by tests/probe-env.sh --facts): yum/dnf syntax absorption,
#   variable-tolerant repo-id matching, product-cert tag parsing (mocked
#   openssl), tsv shape, and the emitted collector's syntax.
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; hermetic (no network, no containers, openssl mocked).
# ----- Usage examples -------------------------------------------------------
#   bash tests/t023_probeentitlement.sh
#   bash tests/run-all.sh
# ----- Known limitations ----------------------------------------------------
#   Asserts count failures and continue (harness scope, spec home A.5). The
#   collector's live behavior is exercised by a real probe run, not here.
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-04 (r37 fact-probe; r39 probe unification)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/t023_probeentitlement.sh - unit tier for lib/probe-common.sh and the
# collector emitted by tests/probe-env.sh --facts. Pins exactly the
# observation mistakes that corrupted earlier investigations: yum's repolist
# subcommand form, EL6's -q suppressing the whole repolist table,
# literal-$basearch section ids, plugin-enabled repolist, and step exit codes
# piped away behind `| tail` (the r37 collector's s06/s12 defect).
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
# shellcheck source=../lib/probe-common.sh
. "${PROJ}/lib/probe-common.sh"
PE_SOURCED=1
# shellcheck source=probe-env.sh
. "${HERE}/probe-env.sh"

# --- pc_pm_for_major ----------------------------------------------------------
assert_eq dnf "$(pc_pm_for_major 10)" "major 10 -> dnf"
assert_eq dnf "$(pc_pm_for_major 8)"  "major 8 -> dnf"
assert_eq yum "$(pc_pm_for_major 7)"  "major 7 -> yum"
assert_eq yum "$(pc_pm_for_major 6)"  "major 6 -> yum"
pc_pm_for_major 5 >/dev/null 2>&1; assert_rc 1 "$?" "major 5 -> rc 1"

# --- pc_repolist_cmd: the yum pitfalls -----------------------------------------
assert_eq "yum -q repolist enabled" "$(pc_repolist_cmd 7 enabled)" \
  "EL7 uses the quiet SUBCOMMAND form"
assert_eq "yum repolist enabled" "$(pc_repolist_cmd 6 enabled)" \
  "EL6 drops -q (it suppresses the whole table; 2026-07-04 entitled run)"
case "$(pc_repolist_cmd 7 enabled)" in
  *--enabled*) t_fail "yum form must NOT carry --enabled" ;;
  *)           t_pass "yum form carries no --enabled flag" ;;
esac
assert_eq "dnf -q repolist --enabled" "$(pc_repolist_cmd 9 enabled)" "dnf uses --enabled"
pc_repolist_cmd 5 enabled >/dev/null 2>&1; assert_rc 1 "$?" "unknown major -> rc 1"

# --- pc_repoid_pattern: expanded id vs literal-$basearch section --------------
pat="$(pc_repoid_pattern 'ubi-10-for-x86_64-baseos-rpms')"
# shellcheck disable=SC2016  # the fixture line intentionally holds a literal $basearch
printf '[ubi-10-for-$basearch-baseos-rpms]\n' | grep -Eq "${pat}"
assert_rc 0 "$?" "expanded id matches the literal-\$basearch section"
printf '[ubi-10-for-x86_64-baseos-rpms]\n' | grep -Eq "${pat}"
assert_rc 0 "$?" "expanded id matches the expanded section"
printf '[ubi-9-for-x86_64-baseos-rpms]\n' | grep -Eq "${pat}"
assert_rc 1 "$?" "different repo id does not match"

# --- pc_step_verdict -----------------------------------------------------------
assert_eq ok      "$(pc_step_verdict 0)"   "rc 0 -> ok"
assert_eq timeout "$(pc_step_verdict 124)" "rc 124 -> timeout"
assert_eq fail    "$(pc_step_verdict 3)"   "rc 3 -> fail"

# --- pc_resolve_cmd (D-A2: deep = real --downloadonly fetch) -------------------
assert_match "$(pc_resolve_cmd dnf 1 kernel-devel)" 'downloadonly.*--destdir=/tmp/probe-dl' \
  "dnf deep resolve is a real downloadonly fetch"
assert_match "$(pc_resolve_cmd yum 1 kernel-devel)" 'downloadonly.*--downloaddir=/tmp/probe-dl' \
  "yum deep resolve uses --downloaddir"
assert_match "$(pc_resolve_cmd dnf 0 gawk)" 'assumeno' "shallow resolve is --assumeno"

# --- pc_tsv_row: 5 stable columns ---------------------------------------------
row="$(pc_tsv_row cert 9 auto k "$(printf 'a\tb\nc')")"
assert_eq 5 "$(printf '%s' "${row}" | awk -F'\t' '{print NF}')" \
  "tabs/newlines in VALUE are flattened to keep 5 columns"

# --- pc_product_tags / pc_product_id with a MOCKED openssl ---------------------
openssl() {
  cat <<'ASN1'
  991:d=5  hl=2 l=  12 prim: OBJECT            :1.3.6.1.4.1.2312.9.1.479.4
 1005:d=5  hl=2 l=  22 prim: OCTET STRING      [HEX DUMP]:0C147268656C2D392C7268656C2D392D7838365F3634
ASN1
}
assert_eq "rhel-9,rhel-9-x86_64" "$(pc_product_tags /dev/null)" \
  "tag extraction: OID .479.4 OCTET STRING -> utf8 tags"
assert_eq 479 "$(pc_product_id /dev/null)" "product id extraction -> 479"
unset -f openssl

# --- pc_b64url: python urlsafe_b64encode compatibility (r45) -------------------
assert_eq 'YWI_fg==' "$(printf 'ab?~' | pc_b64url)" \
  "urlsafe base64: / -> _ with padding kept"
assert_eq 'Pz8-Pg==' "$(printf '??>>' | pc_b64url)" \
  "urlsafe base64: + -> -"

# --- pc_rhui_major_url: per-major RHUI URL synthesis (r41) ---------------------
# shellcheck disable=SC2016  # the template intentionally holds literal yum variables
tmpl='https://rhui.REGION.aws.ce.redhat.com/pulp/mirror/content/dist/rhel10/rhui/$releasever/$basearch/baseos/os'
assert_eq 'https://rhui.REGION.aws.ce.redhat.com/pulp/mirror/content/dist/rhel8/rhui/8/x86_64/baseos/os' \
  "$(pc_rhui_major_url "${tmpl}" 8)" "rhel10 template -> rhel8 URL (path + releasever + basearch)"
assert_eq 'https://rhui.REGION.aws.ce.redhat.com/pulp/mirror/content/dist/rhel9/rhui/9/x86_64/baseos/os' \
  "$(pc_rhui_major_url "${tmpl}" 9)" "rhel10 template -> rhel9 URL"

# --- pe_emit_collector: emitted syntax per major --------------------------------
c_el7="$(pe_emit_collector 7 1 300)"
c_el6="$(pe_emit_collector 6 1 300)"
c_dnf="$(pe_emit_collector 10 1 300)"
assert_match "${c_el7}" 'yum -q repolist enabled'  "collector(7) uses quiet subcommand repolist"
assert_match "${c_el6}" "r s04-repolist-enabled-pre 'yum repolist enabled'" \
  "collector(6) drops -q from repolist"
case "${c_el7}" in
  *'repolist --enabled'*) t_fail "collector(yum) leaked a dnf-only flag" ;;
  *)                      t_pass "collector(yum) carries no dnf-only repolist flag" ;;
esac
assert_match "${c_dnf}" 'dnf -q repolist --enabled' "collector(dnf) uses --enabled"
assert_match "${c_dnf}" 'downloadonly'              "collector(dnf) performs the deep fetch"
assert_match "${c_dnf}" 'makecache'                 "collector triggers metadata generation"
case "${c_dnf}" in
  *disableplugin*) t_fail "collector must keep subscription-manager plugins ENABLED" ;;
  *)               t_pass "collector keeps plugins enabled" ;;
esac
case "${c_dnf}${c_el7}${c_el6}" in
  *'| tail'*) t_fail "collector steps must not pipe their exit code into tail (r37 s06/s12 defect)" ;;
  *)          t_pass "no collector step masks its rc behind a pipe" ;;
esac
assert_match "${c_dnf}" '/probe-out' "collector writes only under /probe-out"
assert_match "${c_dnf}" '/etc/pki/rhui' "collector records in-container RHUI cert visibility (r40)"
case "$(declare -f pe_host_inventory)" in
  *'-key.pem'*) t_pass "host inventory skips private keys (metadata only)" ;;
  *)            t_fail "host inventory must skip private keys" ;;
esac
# shellcheck disable=SC2016  # asserting the literal $c inside the EMITTED script
assert_match "${c_dnf}" 'echo repo=\$c; dnf -q --enablerepo=\$c makecache' \
  "s12 records the candidate AND keeps makecache as the rc source"

# --- emitted collectors must be valid bash (bash -n) ---------------------------
printf '%s\n' "${c_el7}" | bash -n 2>/dev/null
assert_rc 0 "$?" "collector(7) passes bash -n"
printf '%s\n' "${c_el6}" | bash -n 2>/dev/null
assert_rc 0 "$?" "collector(6) passes bash -n"
printf '%s\n' "${c_dnf}" | bash -n 2>/dev/null
assert_rc 0 "$?" "collector(10) passes bash -n"

# --- --smoke helpers (r47): latest-version pick + [result] field parse ---------
smoketmp="$(mktemp)"
cat > "${smoketmp}" <<'JSONEOF'
{"versions": [{"version": "2.9.1"}, {"version": "2.10.0"}, {"version": "2.2.3"}]}
JSONEOF
assert_eq "2.10.0" "$(pe_smoke_latest "${smoketmp}")" \
  "smoke picks the numerically newest version (2.10.0 > 2.9.1)"
printf '{"versions": ["1.2", "1.10"]}\n' > "${smoketmp}"
assert_eq "1.10" "$(pe_smoke_latest "${smoketmp}")" "string-list versions also work"
rm -f "${smoketmp}"
res='[aws_ssm-agent][installtest][result] {"status":"ok","reason":"r1"}'
assert_eq ok "$(pe_result_field "${res}" status)" "result field: status"
assert_eq r1 "$(pe_result_field "${res}" reason)" "result field: reason"
assert_eq "" "$(pe_result_field "no result line" status)" "missing [result] -> empty"

# --- probe_verdict still loads and classifies (integration guard) --------------
assert_eq blocked "$(probe_verdict fail ok ok reachable)" "verdict: exec fail -> blocked"
assert_eq ready   "$(probe_verdict ok ok ok reachable)"   "verdict: all ok -> ready"

t_done
