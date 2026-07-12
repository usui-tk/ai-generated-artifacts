# ----- Purpose --------------------------------------------------------------
#   Test-harness library: fixture heredoc helpers for hermetic tiers.
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; sourced by tests/tNNN_*.sh tiers (no side effects at source).
# ----- Usage examples -------------------------------------------------------
#   source tests/lib/heredoc.sh
# ----- Known limitations ----------------------------------------------------
#   Harness scope: counts failures and continues (errexit-free, spec home A.5).
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
# shellcheck shell=bash
#==============================================================================
# tests/lib/heredoc.sh - extract a single-quoted heredoc body from a script
#
# Some install/matrix scripts may ship shell-bodied heredocs that are written
# verbatim into a container (provisioning snippets). An outer `bash -n` of the
# carrier script does NOT parse that literal heredoc text, so L0 (t001) slices
# each shell-bodied body out and parse-checks it on its own. The Phase-1 carrier
# set has no such bodies yet, so t001's allowlist is currently empty; this helper
# is in place for the Phase 3-5 install/build matrices.
#
# Only the <<'MARKER' (single-quoted, non-dash) form is supported; for that form
# the closing MARKER sits in column 0.
#
# Ported verbatim from projects/bash-ol-aws-ami-builder/tests/lib/heredoc.sh
# (harness reuse, the design plan sec 15); only this header was adapted.
#==============================================================================

# extract_heredoc MARKER FILE -> prints the heredoc body on stdout (exclusive of
# the opener and the closing delimiter line). Empty output => marker not found.
extract_heredoc() {
  local marker="$1" file="$2"
  awk -v m="${marker}" '
    !inb && index($0, "<<\x27" m "\x27") { inb = 1; next }
    inb && $0 == m { inb = 0; exit }
    inb { print }
  ' "${file}"
}
