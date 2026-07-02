#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   L1 unit: package-availability classification (Phase 7)
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; hermetic (no network); shellcheck only for t002.
# ----- Usage examples -------------------------------------------------------
#   bash tests/t014_pkgavail.sh
#   bash tests/run-all.sh   # runs every tier
# ----- Known limitations ----------------------------------------------------
#   Asserts count failures and continue (harness scope, spec home A.5).
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/t014_pkgavail.sh - L1 unit: package-availability classification (Phase 7)
#
# Asserts lib/pkg-availability.sh - the design plan sec 12 taxonomy - and the
# per-tool acquisition-source classification that makes "is this installable
# anonymously?" a one-call question for any tool (including a future tool #2).
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
# shellcheck source=lib/pkg-availability.sh
. "${PROJ}/lib/pkg-availability.sh"

if ! declare -F pkgavail_class >/dev/null 2>&1 || ! declare -F pkgavail_needs_entitlement >/dev/null 2>&1; then
  t_fail "could not load lib/pkg-availability.sh"
  t_done; exit
fi

# --- pkgavail_class: source token -> class ----------------------------------
assert_eq "anonymous-ubi" "$(pkgavail_class ubi-baseos)"   "ubi-baseos -> anonymous-ubi"
assert_eq "anonymous-ubi" "$(pkgavail_class rhscl)"        "rhscl (RHEL 7 anon) -> anonymous-ubi"
assert_eq "entitled-only" "$(pkgavail_class kernel-devel)" "kernel-devel -> entitled-only"
assert_eq "epel"          "$(pkgavail_class dkms)"         "dkms -> epel"
assert_eq "vendor-hosted" "$(pkgavail_class awscli-bundle)" "awscli-bundle -> vendor-hosted"
assert_eq "vendor-hosted" "$(pkgavail_class ssm-s3-rpm)"   "ssm-s3-rpm -> vendor-hosted"
assert_eq "base-image"    "$(pkgavail_class glibc)"        "glibc -> base-image"
assert_eq "unknown"       "$(pkgavail_class nope)"         "unknown source -> unknown"

# --- pkgavail_known ---------------------------------------------------------
for c in anonymous-ubi entitled-only epel vendor-hosted base-image; do
  pkgavail_known "${c}"; assert_rc 0 "$?" "pkgavail_known ${c} -> rc 0"
done
pkgavail_known unknown; assert_rc 1 "$?" "pkgavail_known unknown -> rc 1"

# --- pkgavail_needs_entitlement: only entitled-only is true -----------------
pkgavail_needs_entitlement entitled-only; assert_rc 0 "$?" "entitled-only needs entitlement"
pkgavail_needs_entitlement anonymous-ubi; assert_rc 1 "$?" "anonymous-ubi does not"
pkgavail_needs_entitlement vendor-hosted; assert_rc 1 "$?" "vendor-hosted does not"
pkgavail_needs_entitlement epel;          assert_rc 1 "$?" "epel does not (opt-in, not entitlement)"
pkgavail_needs_entitlement bogus;         assert_rc 2 "$?" "unknown class -> rc 2"

# --- pkgavail_anonymous_status ----------------------------------------------
assert_eq "needs-entitlement" "$(pkgavail_anonymous_status entitled-only)" "entitled-only -> needs-entitlement"
assert_eq "epel-optional"     "$(pkgavail_anonymous_status epel)"          "epel -> epel-optional"
assert_eq "installable"       "$(pkgavail_anonymous_status anonymous-ubi)" "anonymous-ubi -> installable"
assert_eq "installable"       "$(pkgavail_anonymous_status vendor-hosted)" "vendor-hosted -> installable"
assert_eq "installable"       "$(pkgavail_anonymous_status base-image)"    "base-image -> installable"

# --- pkgavail_over_network --------------------------------------------------
assert_eq "registry.access.redhat.com" "$(pkgavail_over_network entitled-only)" "entitled-only over RH registry"
assert_eq "dl.fedoraproject.org"       "$(pkgavail_over_network epel)"          "epel over Fedora"
assert_eq "vendor-cdn"                 "$(pkgavail_over_network vendor-hosted)" "vendor-hosted over vendor CDN"
assert_eq "none"                       "$(pkgavail_over_network base-image)"    "base-image needs no network"

# --- pkgavail_tool_source: each shipped tool declares its source ------------
assert_eq "awscli-bundle" "$(pkgavail_tool_source aws_awscli-v2)" "AWS CLI -> bundle"
assert_eq "ssm-s3-rpm"    "$(pkgavail_tool_source aws_ssm-agent)" "SSM -> S3 RPM"
assert_eq "kernel-devel"  "$(pkgavail_tool_source aws_ena-driver)" "ENA -> kernel-devel"

# --- end-to-end: each tool's source resolves to its expected anonymous story --
assert_eq "installable" \
  "$(pkgavail_anonymous_status "$(pkgavail_class "$(pkgavail_tool_source aws_awscli-v2)")")" \
  "AWS CLI: vendor-hosted bundle is installable anonymously"
assert_eq "needs-entitlement" \
  "$(pkgavail_anonymous_status "$(pkgavail_class "$(pkgavail_tool_source aws_ena-driver)")")" \
  "ENA: kernel-devel build is needs-entitlement anonymously (matches ena_verdict)"

t_done
