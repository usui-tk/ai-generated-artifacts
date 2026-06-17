#!/usr/bin/env bash
#==============================================================================
# tests/t009_logformat.sh - log line-format / field-order regression guard (L1)
#
# Source the wrapper (its tail `main` is guarded, so sourcing has no side
# effects) and drive each timestamped log helper, asserting the emitted line is
# date-first: the `YYYY-MM-DD HH:MM:SS` timestamp leads, the `[SEVERITY]` /
# source tag follows. This guards against a regression back to the old
# tag-first order (SPEC E.1 "Line format"). ANSI colour is stripped before the
# match so the assertion is colour-independent. The only host dependency is
# `date` (shape only, deterministic), so this is hermetic in practice.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
MAIN="${PROJ}/build-ol-aws-ami.sh"

# A line is "date-first" when, after ANSI stripping, it begins with the unified
# timestamp immediately followed by the channel's bracket tag.
TS_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} \[%s\]'

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

# --- single-line severity / source channels ---------------------------------
# row: helper | tag | capture_fd (1=stdout, 2=stderr-merged)
while IFS='|' read -r helper tag fd; do
  [ -z "${helper}" ] && continue
  if [ "${fd}" = "2" ]; then
    line="$(
      # shellcheck source=/dev/null
      . "${MAIN}" >/dev/null 2>&1
      "${helper}" "sample message" 2>&1 >/dev/null
    )"
  else
    line="$(
      # shellcheck source=/dev/null
      . "${MAIN}" >/dev/null 2>&1
      "${helper}" "sample message" 2>/dev/null
    )"
  fi
  clean="$(printf '%s' "${line}" | strip_ansi)"
  # shellcheck disable=SC2059  # TS_RE is a trusted internal template, not user input
  re="$(printf "${TS_RE}" "${tag}")"
  assert_match "${clean}" "${re}" "${helper}: date-first (timestamp leads [${tag}])"
  assert_match "${clean}" "[[:space:]]\[${tag}\][[:space:]]" "${helper}: [${tag}] tag present after timestamp"
done <<'TABLE'
log_info|INFO|1
log_warn|WARN|2
log_error|ERROR|2
log_progress|BUILD|1
TABLE

# --- [DEBUG] (prints to stdout when DEBUG=1) --------------------------------
dbg="$(
  # shellcheck source=/dev/null
  . "${MAIN}" >/dev/null 2>&1
  DEBUG=1 log_debug "sample message" 2>/dev/null
)"
dbg_clean="$(printf '%s' "${dbg}" | strip_ansi)"
# shellcheck disable=SC2059  # trusted internal template
assert_match "${dbg_clean}" "$(printf "${TS_RE}" 'DEBUG')" "log_debug: date-first (timestamp leads [DEBUG])"

# --- [EXTERNAL] (re-emits stdin, attributed to the script) ------------------
ext="$(
  # shellcheck source=/dev/null
  . "${MAIN}" >/dev/null 2>&1
  printf '%s\n' "upstream output line" | log_external "build-image.sh" 2>/dev/null
)"
ext_clean="$(printf '%s' "${ext}" | strip_ansi)"
# shellcheck disable=SC2059  # trusted internal template
assert_match "${ext_clean}" "$(printf "${TS_RE}" 'EXTERNAL')" "log_external: date-first (timestamp leads [EXTERNAL])"
assert_match "${ext_clean}" "\[EXTERNAL\] \[build-image.sh\] upstream output line" "log_external: attributes the source script after the tag"

# --- negative guard: no channel may start with the bracket tag (old order) --
firstchar_ok=1
for helper in log_info log_progress; do
  l="$(
    # shellcheck source=/dev/null
    . "${MAIN}" >/dev/null 2>&1
    "${helper}" "x" 2>/dev/null
  )"
  c="$(printf '%s' "${l}" | strip_ansi)"
  case "${c}" in
    \[*) firstchar_ok=0 ;;
  esac
done
assert_eq 1 "${firstchar_ok}" "no timestamped channel starts with the [TAG] (old tag-first order is gone)"

t_done
