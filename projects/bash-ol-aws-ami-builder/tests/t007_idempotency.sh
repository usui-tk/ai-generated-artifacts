#!/usr/bin/env bash
#==============================================================================
# tests/t007_idempotency.sh - B-T6 idempotency-guard presence (layer L2, structural)
#
# The wrapper patches upstream files by injecting marker-bracketed blocks
# ([ol-aws-ami-builder PATCH <id>]). Each such injection must be fronted by a
# `grep -Fq '[<marker>]'` idempotency guard so re-applying on a fresh clone is a
# no-op. This tier statically asserts that every distinct PATCH marker has a
# matching grep -Fq guard. It is STRUCTURAL: it does not execute the injection;
# full runtime idempotency (apply-twice) is covered by the L3/L4 tiers (B-T7/8).
#
# The expected marker count is pinned (fixed-count discipline): adding a new
# PATCH marker must be a conscious change that also lands its guard and bumps
# this number.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
MAIN="${PROJ}/build-ol-aws-ami.sh"

mapfile -t markers < <(grep -oE 'ol-aws-ami-builder PATCH [a-z0-9-]+' "${MAIN}" | sort -u)

assert_eq 8 "${#markers[@]}" "idempotency: expected number of distinct PATCH markers"

for m in "${markers[@]}"; do
  guards="$(grep -Fc "grep -Fq '[${m}]'" "${MAIN}" || true)"
  if [ "${guards}" -ge 1 ]; then
    t_pass "idempotency: '${m}' fronted by a grep -Fq guard (${guards}x)"
  else
    t_fail "idempotency: '${m}' has NO grep -Fq idempotency guard"
  fi
done

t_done
