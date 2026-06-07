#!/usr/bin/env bash
#==============================================================================
# tests/t3_unit.sh - B-T3 pure-function unit (test pyramid layer L1, hermetic)
#
# Source the wrapper (its tail `main` is guarded, so sourcing has no side
# effects) and exercise pure functions in isolated subshells. Dependency classes
# touched (Axis 2): arguments only - no external commands, filesystem, or
# network - so these are hermetic and deterministic on any host.
#
# Covered: parse_ol_version_from_iso (table-driven, Axis 3) and the parse_args
# contract (exit codes + error messages). The load_env IMDS `v2.0` OL6 rejection
# is planned for a later increment (it lives inside the large load_env; testing
# it needs either a small behaviour-neutral extraction or a fixture-driven run).
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
MAIN="${PROJ}/build-ol-aws-ami.sh"

# --- parse_ol_version_from_iso : table-driven (Axis 3 data variation) ---------
# row: iso_ref | expect_rc | expect_major | expect_update
while IFS='|' read -r iso erc emaj eupd; do
  [ -z "${iso}" ] && continue
  result="$(
    # shellcheck source=/dev/null
    . "${MAIN}" >/dev/null 2>&1
    if parse_ol_version_from_iso "${iso}"; then rc=0; else rc=$?; fi
    printf '%s|%s|%s' "${rc}" "${OL_MAJOR_VERSION:-}" "${OL_UPDATE_VERSION:-}"
  )"
  arc="${result%%|*}"; tmp="${result#*|}"; amaj="${tmp%%|*}"; aupd="${tmp##*|}"
  assert_eq "${erc}" "${arc}" "parse_ol_version_from_iso rc :: ${iso}"
  if [ "${erc}" = "0" ]; then
    assert_eq "${emaj}" "${amaj}" "  -> major :: ${iso}"
    assert_eq "${eupd}" "${aupd}" "  -> update :: ${iso}"
  fi
done <<'TABLE'
OracleLinux-R10-U2-x86_64-dvd.iso|0|10|2
OracleLinux-R9-U6-x86_64-dvd.iso|0|9|6
OracleLinux-R8-U10-x86_64-dvd.iso|0|8|10
OracleLinux-R7-U9-Server-x86_64-dvd.iso|0|7|9
OracleLinux-R6-U10-x86_64-dvd.iso|0|6|10
https://example.com/path/OracleLinux-R9-U6-x86_64-dvd.iso|0|9|6
not-an-ol-image.iso|1||
TABLE

# --- parse_args : contract (exit codes + messages; Axis 2 arguments) ----------

# unknown flag -> usage(1)
err="$(
  (
    # shellcheck source=/dev/null
    . "${MAIN}" >/dev/null 2>&1
    parse_args --bogus-flag
  ) 2>&1 >/dev/null
)"; rc=$?
assert_eq 1 "${rc}" "parse_args: unknown flag exits 1"
assert_match "${err}" "Unknown option" "parse_args: unknown flag logs an error"

# missing --env -> die
err="$(
  (
    # shellcheck source=/dev/null
    . "${MAIN}" >/dev/null 2>&1
    parse_args
  ) 2>&1 >/dev/null
)"; rc=$?
assert_eq 1 "${rc}" "parse_args: missing --env exits 1"
assert_match "${err}" "env option is required" "parse_args: missing --env message"

# valid --env (existing file) -> rc 0, ENV_FILE set
fix="$(mktemp)"; printf '# fixture env\n' > "${fix}"
out="$(
  (
    # shellcheck source=/dev/null
    . "${MAIN}" >/dev/null 2>&1
    if parse_args --env "${fix}"; then printf 'ENV_FILE=%s' "${ENV_FILE:-}"; else exit "$?"; fi
  ) 2>/dev/null
)"; rc=$?
rm -f "${fix}"
assert_eq 0 "${rc}" "parse_args: valid --env returns 0"
assert_match "${out}" "ENV_FILE=/" "parse_args: sets ENV_FILE"

t_done
