#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   L1: the entitlement fact-probe's pure layer - yum/dnf syntax absorption,
#   variable-tolerant repo-id matching, product-cert tag parsing (mocked
#   openssl), tsv shape, and the emitted in-container collector's syntax.
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
#   Generation date: 2026-07-04 (r37: reproducible entitlement fact-probe)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/t023_probeentitlement.sh - unit tier for lib/probe-common.sh and the
# collector emitted by tests/probe-entitlement.sh. Pins exactly the syntax
# mistakes that corrupted the prior ad-hoc investigation: yum's repolist
# subcommand form, literal-$basearch section ids, and plugin-enabled repolist.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
# shellcheck source=../lib/probe-common.sh
. "${PROJ}/lib/probe-common.sh"
PE_SOURCED=1
# shellcheck source=probe-entitlement.sh
. "${HERE}/probe-entitlement.sh"

# --- pc_pm_for_major ----------------------------------------------------------
assert_eq dnf "$(pc_pm_for_major 10)" "major 10 -> dnf"
assert_eq dnf "$(pc_pm_for_major 8)"  "major 8 -> dnf"
assert_eq yum "$(pc_pm_for_major 7)"  "major 7 -> yum"
assert_eq yum "$(pc_pm_for_major 6)"  "major 6 -> yum"
pc_pm_for_major 5 >/dev/null 2>&1; assert_rc 1 "$?" "major 5 -> rc 1"

# --- pc_repolist_cmd: the yum pitfall ----------------------------------------
assert_eq "yum -q repolist enabled" "$(pc_repolist_cmd yum enabled)" \
  "yum uses the SUBCOMMAND form"
case "$(pc_repolist_cmd yum enabled)" in
  *--enabled*) t_fail "yum form must NOT carry --enabled" ;;
  *)           t_pass "yum form carries no --enabled flag" ;;
esac
assert_eq "dnf -q repolist --enabled" "$(pc_repolist_cmd dnf enabled)" "dnf uses --enabled"
pc_repolist_cmd rpm enabled >/dev/null 2>&1; assert_rc 1 "$?" "unknown mgr -> rc 1"

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

# --- pe_emit_collector: emitted syntax per manager ------------------------------
c_yum="$(pe_emit_collector yum 1 300)"
c_dnf="$(pe_emit_collector dnf 1 300)"
assert_match "${c_yum}" 'yum -q repolist enabled'  "collector(yum) uses subcommand repolist"
case "${c_yum}" in
  *'repolist --enabled'*) t_fail "collector(yum) leaked a dnf-only flag" ;;
  *)                      t_pass "collector(yum) carries no dnf-only repolist flag" ;;
esac
assert_match "${c_dnf}" 'dnf -q repolist --enabled' "collector(dnf) uses --enabled"
assert_match "${c_dnf}" 'downloadonly'              "collector(dnf) performs the deep fetch"
assert_match "${c_dnf}" 'makecache'                 "collector triggers metadata generation"
case "${c_dnf}" in
  *disableplugin*) t_fail "collector must keep subscription-manager plugins ENABLED" ;;
  *)               t_pass "collector keeps plugins enabled (unlike probe-env repolist)" ;;
esac
assert_match "${c_dnf}" '/probe-out' "collector writes only under /probe-out"

# --- emitted collectors must be valid bash (bash -n) ---------------------------
printf '%s\n' "${c_yum}" | bash -n 2>/dev/null
assert_rc 0 "$?" "collector(yum) passes bash -n"
printf '%s\n' "${c_dnf}" | bash -n 2>/dev/null
assert_rc 0 "$?" "collector(dnf) passes bash -n"

t_done
