#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   L1 unit: cross-script helper identity
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; hermetic (no network); shellcheck only for t002.
# ----- Usage examples -------------------------------------------------------
#   bash tests/t020_helperidentity.sh
#   bash tests/run-all.sh   # runs every tier
# ----- Known limitations ----------------------------------------------------
#   Asserts count failures and continue (harness scope, spec home A.5).
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/t020_helperidentity.sh - L1 unit: cross-script helper identity
#
# The install scripts are bind-mounted into containers WITHOUT lib/, so each
# carries its own copy of a few shared helpers. That is deliberate, but it means
# a fix applied to one copy can silently drift from the others. This tier pins
# the copies byte-for-byte identical across all three install scripts, so drift
# fails the suite instead of shipping. Pure text comparison; no execution.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"

SCRIPTS=(install-aws_awscli-v2.sh install-aws_ena-driver.sh install-aws_ssm-agent.sh)

# extract_fn FILE FN : print FN's body (from `FN() {` to the closing `}` line).
extract_fn() {
  awk -v fn="$2" '$0 ~ "^"fn"\\(\\) \\{"{p=1} p{print} p&&/^\}/{exit}' "$1"
}

for fn in entitlement_certs_present pm_neutralize_rhsm_if_anonymous run_pm os_major; do
  first_hash=""; identical=1; present=0
  for s in "${SCRIPTS[@]}"; do
    body="$(extract_fn "${PROJ}/${s}" "${fn}")"
    [ -n "${body}" ] || continue
    present=$((present + 1))
    h="$(printf '%s' "${body}" | md5sum | cut -d' ' -f1)"
    if [ -z "${first_hash}" ]; then first_hash="${h}"; elif [ "${h}" != "${first_hash}" ]; then identical=0; fi
  done
  assert_eq "3" "${present}" "helper ${fn}() is present in all 3 install scripts"
  assert_eq "1" "${identical}" "helper ${fn}() is byte-identical across the 3 install scripts (no drift)"
done

t_done
