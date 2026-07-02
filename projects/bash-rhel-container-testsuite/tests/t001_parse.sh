#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   L0 Parse (test pyramid layer L0, static)
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; hermetic (no network); shellcheck only for t002.
# ----- Usage examples -------------------------------------------------------
#   bash tests/t001_parse.sh
#   bash tests/run-all.sh   # runs every tier
# ----- Known limitations ----------------------------------------------------
#   Asserts count failures and continue (harness scope, spec home A.5).
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/t001_parse.sh - L0 Parse (test pyramid layer L0, static)
#
# (1) `bash -n` every .sh in the project (install scripts + lib/* + the test
#     harness itself, dogfooded).
# (2) Bash-specific: extract each *shell-bodied* heredoc that ships into a
#     container (provisioning snippets in the Phase 3-5 install/build matrices)
#     and `bash -n` the body, since the outer parse of the carrier script does
#     not cover literal heredoc text.
#
# The Phase-1 scaffold carries no shell-bodied heredocs yet, so the allowlist
# below is empty and step (2) is a no-op; entries are added alongside the
# install/build matrices. Non-shell heredocs (JSON ledgers, .repo bodies,
# env snippets) are intentionally excluded - they are validated by their own
# tiers, not by `bash -n`.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
# shellcheck source=lib/heredoc.sh
. "${HERE}/lib/heredoc.sh"

# (1) bash -n on every .sh in the project tree
while IFS= read -r f; do
  bash -n "${f}"
  rc=$?
  assert_rc 0 "${rc}" "bash -n ${f#"${PROJ}"/}"
done < <(find "${PROJ}" -name '*.sh' -type f | sort)

# (2) shell-bodied heredoc bodies (allowlist; empty in the Phase-1 scaffold).
# Each entry is "MARKER FILE_RELATIVE_TO_PROJ"; populated with the install /
# build matrices in Phase 3-5 (e.g. an in-container provisioning snippet).
HEREDOC_SHELL_BODIES=(
)

if [ "${#HEREDOC_SHELL_BODIES[@]}" -gt 0 ]; then
  for entry in "${HEREDOC_SHELL_BODIES[@]}"; do
    m="${entry%% *}"
    rel="${entry#* }"
    file="${PROJ}/${rel}"
    body="$(extract_heredoc "${m}" "${file}")"
    if [ -z "${body}" ]; then
      t_fail "heredoc ${m} present and non-empty in ${rel}"
      continue
    fi
    printf '%s\n' "${body}" | bash -n
    rc=$?
    assert_rc 0 "${rc}" "bash -n heredoc body ${m} (${rel})"
  done
fi

t_done
