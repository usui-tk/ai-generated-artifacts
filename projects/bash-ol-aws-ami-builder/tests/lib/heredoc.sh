# shellcheck shell=bash
#==============================================================================
# tests/lib/heredoc.sh - extract a single-quoted heredoc body from a script
#
# The wrapper ships several shell-bodied heredocs that are written verbatim into
# the guest (hook scripts) or synthesized into distr/ol6-slim/. The outer
# `bash -n` of the wrapper does NOT parse that literal heredoc text, so B-T1
# slices each shell-bodied body out and parse-checks it on its own.
#
# Only the <<'MARKER' (single-quoted, non-dash) form is supported, which is what
# the wrapper uses; for that form the closing MARKER sits in column 0.
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
