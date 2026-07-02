#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   L0 ShellCheck (test pyramid layer L0, static)
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; hermetic (no network); shellcheck only for t002.
# ----- Usage examples -------------------------------------------------------
#   bash tests/t002_shellcheck.sh
#   bash tests/run-all.sh   # runs every tier
# ----- Known limitations ----------------------------------------------------
#   Asserts count failures and continue (harness scope, spec home A.5).
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/t002_shellcheck.sh - L0 ShellCheck (test pyramid layer L0, static)
#
# Deterministic lint gate: run ShellCheck at the CANONICAL severity `style`
# (the strictest level) over every .sh, honouring the checked-in .shellcheckrc
# and any documented inline exemptions, and assert ZERO findings per file. This
# is the thin driver that turns ShellCheck into a reproducible pass/fail summary
# (the bash analogue of psa.py reporting 0/0/0) - no per-run human judgement:
# each exemption is decided once, in the diff, with a rationale.
#
# SKIPs cleanly (exit 0) if shellcheck is not installed; the canonical gate
# REQUIRES the pinned shellcheck in CI (see TESTING.md "Environment & version").
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"

SEVERITY="style"

if ! command -v shellcheck >/dev/null 2>&1; then
  t_skip "shellcheck not installed (canonical gate: -S ${SEVERITY}); L0 ShellCheck skipped"
  t_done
  exit
fi

echo "shellcheck $(shellcheck --version 2>/dev/null | awk '/^version:/ {print $2}'), severity=${SEVERITY}"

while IFS= read -r f; do
  findings="$(shellcheck -S "${SEVERITY}" -P "${PROJ}" "${f}" 2>/dev/null | grep -c '^In ' || true)"
  assert_eq 0 "${findings}" "shellcheck -S ${SEVERITY} ${f#"${PROJ}"/} (0 findings)"
done < <(find "${PROJ}" -name '*.sh' -type f | sort)

t_done
