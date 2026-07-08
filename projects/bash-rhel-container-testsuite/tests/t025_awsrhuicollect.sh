#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   L1 unit tier for tests/collect-aws-rhui-facts.sh: the pure helpers (pm/repolist/
#   b64url/major-url/leapp-target/major-detect) and the NON-DESTRUCTIVE safety
#   invariant (the collector must never invoke `leapp upgrade`).
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; hermetic (no network, no podman); shellcheck only for t002.
# ----- Usage examples -------------------------------------------------------
#   bash tests/t025_awsrhuicollect.sh
#   bash tests/run-all.sh   # runs every tier
# ----- Known limitations ----------------------------------------------------
#   Covers the pure layer only; the side-effecting collectors and the tar.gz
#   packing are exercised on a real RHUI EC2 host (operator E2E), not here.
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Opus 4.8), claude.ai sessions
#   Generation date: 2026-07-08 (RHUI entitlement investigation collector)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/t025_awsrhuicollect.sh - unit tier for collect-aws-rhui-facts.sh
#
# Loads the collector with RHUI_COLLECT_SOURCED=1 (its main() is guarded, so
# sourcing only defines functions) and asserts the pure helpers. The last
# block is a STATIC MUTATION GUARD: if a future edit ever wired an actual
# `leapp upgrade` into the collector, this tier fails - the dry-run promise is
# machine-enforced, not just documented.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"

COLLECT="${PROJ}/tests/collect-aws-rhui-facts.sh"

# Load the pure layer (main() is guarded behind RHUI_COLLECT_SOURCED).
# shellcheck source=collect-aws-rhui-facts.sh disable=SC1090
RHUI_COLLECT_SOURCED=1 . "${COLLECT}"

if ! declare -F rc_rhui_major_url >/dev/null 2>&1; then
  t_fail "could not source collect-aws-rhui-facts.sh (pure layer)"
  t_done; exit
fi

# --- rc_pm_for_major ----------------------------------------------------------
assert_eq "dnf" "$(rc_pm_for_major 10)" "pm: RHEL 10 -> dnf"
assert_eq "dnf" "$(rc_pm_for_major 8)"  "pm: RHEL 8 -> dnf"
assert_eq "yum" "$(rc_pm_for_major 7)"  "pm: RHEL 7 -> yum"
assert_eq "yum" "$(rc_pm_for_major 6)"  "pm: RHEL 6 -> yum"
rc_pm_for_major 99 >/dev/null 2>&1; assert_eq 1 "$?" "pm: unknown major -> rc 1"

# --- rc_repolist_cmd ----------------------------------------------------------
assert_eq "dnf -q repolist --enabled" "$(rc_repolist_cmd 9 enabled)" "repolist: 9/enabled -> dnf"
assert_eq "yum -q repolist all"       "$(rc_repolist_cmd 7 all)"     "repolist: 7/all -> yum -q"
assert_eq "yum repolist enabled"      "$(rc_repolist_cmd 6 enabled)" "repolist: 6/enabled -> yum (no -q)"
rc_repolist_cmd 5 all >/dev/null 2>&1; assert_eq 1 "$?" "repolist: unknown major -> rc 1"

# --- rc_leapp_target (the cross-major applicability decision) ------------------
assert_eq "10" "$(rc_leapp_target 9)" "leapp target: 9 -> 10"
assert_eq "9"  "$(rc_leapp_target 8)" "leapp target: 8 -> 9"
assert_eq "8"  "$(rc_leapp_target 7)" "leapp target: 7 -> 8"
rc_leapp_target 10 >/dev/null 2>&1; assert_eq 1 "$?" "leapp target: 10 has no N+1 -> rc 1"
rc_leapp_target 6  >/dev/null 2>&1; assert_eq 1 "$?" "leapp target: 6 has no leapp -> rc 1"

# --- rc_chain_list (the r74 downstream acquire-chain) -------------------------
assert_eq "9 10" "$(rc_chain_list 8)" "chain: 8 -> '9 10' (two hops)"
assert_eq "10"   "$(rc_chain_list 9)" "chain: 9 -> '10' (one hop)"
assert_eq ""     "$(rc_chain_list 10)" "chain: 10 -> '' (no downstream)"
assert_eq "8 9 10" "$(rc_chain_list 7)" "chain: 7 -> '8 9 10' (three hops)"

# --- r74 collectors/helpers are wired ----------------------------------------
for fn in rc_collect_chain rc_curl_repo_enum rc_count_packages rc_run_long rc_curl_fetch_pkg rc_decompress rc_builddep_scan rc_rhui_config_url; do
  if declare -F "${fn}" >/dev/null 2>&1; then t_pass "defined: ${fn}"; else t_fail "missing: ${fn}"; fi
done

# --- rc_rhui_major_url (cross-major URL synthesis) ----------------------------
# shellcheck disable=SC2016  # $releasever/$basearch are literal template tokens the helper rewrites
TMPL='https://rhui.REGION.aws.ce.redhat.com/pulp/mirror/content/dist/rhel10/rhui/$releasever/$basearch/os'
assert_match "$(rc_rhui_major_url "${TMPL}" 8)" 'rhel8/rhui/8/x86_64/os' "url synth: rhel10 template -> major 8 path"
assert_match "$(rc_rhui_major_url "${TMPL}" 9)" 'rhel9/rhui/9/x86_64/os' "url synth: rhel10 template -> major 9 path"
# $releasever must be replaced, not left literal.
out="$(rc_rhui_major_url "${TMPL}" 8)"
# shellcheck disable=SC2016  # literal '$releasever' is the token we assert is absent
case "${out}" in *'$releasever'*) t_fail "url synth: \$releasever left unexpanded" ;; *) t_pass "url synth: \$releasever expanded" ;; esac

# --- rc_b64url (urlsafe alphabet) ---------------------------------------------
assert_eq "-_8=" "$(printf '\xfb\xff' | rc_b64url)" "b64url: +/ mapped to -_ (0xfbff -> -_8=)"

# --- rc_detect_major (fixture via RC_RELEASE_FILE seam) -----------------------
fix="$(mktemp)"
printf 'Red Hat Enterprise Linux release 8.10 (Ootpa)\n' > "${fix}"
assert_eq "8" "$(RC_RELEASE_FILE="${fix}" rc_detect_major)" "detect: 'release 8.10' -> 8"
printf 'Red Hat Enterprise Linux Server release 7.9 (Maipo)\n' > "${fix}"
assert_eq "7" "$(RC_RELEASE_FILE="${fix}" rc_detect_major)" "detect: 'Server release 7.9' -> 7"
printf 'Red Hat Enterprise Linux release 10.0 (Coughlan)\n' > "${fix}"
assert_eq "10" "$(RC_RELEASE_FILE="${fix}" rc_detect_major)" "detect: 'release 10.0' -> 10"
rm -f "${fix}"
RC_RELEASE_FILE="/nonexistent/redhat-release" rc_detect_major >/dev/null 2>&1
assert_eq 1 "$?" "detect: missing release file -> rc 1"

# --- STATIC SAFETY GUARD: the collector must never run `leapp upgrade` ---------
# Strip comments, then search for an actual `leapp upgrade` invocation. Only
# `leapp preupgrade` is permitted. This makes the dry-run promise executable.
hits="$(sed 's/#.*//' "${COLLECT}" | grep -Eqc 'leapp[[:space:]]+upgrade' && echo bad || echo ok)"
assert_eq "ok" "${hits}" "safety: no 'leapp upgrade' invocation in the collector (dry-run only)"
# And the dry-run call is present.
grep -Eq 'leapp preupgrade' "${COLLECT}"; assert_eq 0 "$?" "safety: 'leapp preupgrade' dry-run is present"

# --- REGRESSION GUARD (r78): the chain probe is curl-native (no dnf) ----------
# The chain must acquire/measure via curl only. If a future edit reintroduces a
# dnf-driven chain step, cross-major breaks again (dnf failed three ways: 403,
# already-installed, modular platform). Assert the chain's acquisition uses the
# curl fetch helper and writes no /etc/yum.repos.d chain repo file.
grep -q '"leapp-rhui-aws"' "${COLLECT}"; assert_eq 0 "$?" "r79: chain fetches leapp-rhui-aws via curl (rc_curl_fetch_pkg)"
grep -q 'rc_rhui_config_url' "${COLLECT}"; assert_eq 0 "$?" "r79: chain reaches the client-config repo (config-cert path, non-circular)"
if grep -Eq '/etc/yum\.repos\.d/chain-' "${COLLECT}"; then t_fail "r79: chain must not write dnf repo files (curl-native)"; else t_pass "r79: chain writes no dnf repo files (curl-native)"; fi

t_done
