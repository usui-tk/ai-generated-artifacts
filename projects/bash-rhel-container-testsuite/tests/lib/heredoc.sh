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
