#!/usr/bin/env bash
#==============================================================================
# tests/t4_cmdmock.sh - command-mock unit tier (test pyramid layer L1, hermetic)
#
# Demonstrates dependency class "external commands" (Axis 2): functions that
# branch on an external command are driven with PATH-shadow mocks, and the
# recorded invocations are verified (spying). Targets:
#   - detect_qemu_user  -> mocks `id`          (user-probe branch + spy)
#   - detect_os_variant -> mocks `osinfo-query` (short-id resolution + spy)
# Hermetic: every external dependency is mocked, so results are host-independent
# (the one exception, the "osinfo-query absent" branch, SKIPs if the host
# happens to have a real osinfo-query, to stay deterministic).
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
# shellcheck source=lib/mock.sh
. "${HERE}/lib/mock.sh"
MAIN="${PROJ}/build-ol-aws-ami.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# --- detect_qemu_user (mocks `id`) -------------------------------------------

# 'qemu' exists -> echoes qemu
td="${WORK}/q1"; mkdir -p "${td}"
out="$(
  (
    # shellcheck source=/dev/null
    . "${MAIN}" >/dev/null 2>&1
    mock_setup "${td}"
    # The behaviour string is intentionally literal ($1 expands at the fake's
    # runtime, not here); SC2016 is a false positive for mock behaviours.
    # shellcheck disable=SC2016
    mock_cmd id 'case "$1" in qemu) exit 0;; *) exit 1;; esac'
    if u="$(detect_qemu_user)"; then printf '0|%s' "${u}"; else printf '1|'; fi
  ) 2>/dev/null
)"
assert_eq "0|qemu" "${out}" "detect_qemu_user: returns 'qemu' when id qemu succeeds"
assert_match "$(cat "${td}/calls")" "^id qemu$" "detect_qemu_user: spy - id called with qemu"

# 'qemu' missing, 'libvirt-qemu' present -> echoes libvirt-qemu, probes both
td="${WORK}/q2"; mkdir -p "${td}"
out="$(
  (
    # shellcheck source=/dev/null
    . "${MAIN}" >/dev/null 2>&1
    mock_setup "${td}"
    # Literal behaviour string (see note above); SC2016 false positive.
    # shellcheck disable=SC2016
    mock_cmd id 'case "$1" in libvirt-qemu) exit 0;; *) exit 1;; esac'
    if u="$(detect_qemu_user)"; then printf '0|%s' "${u}"; else printf '1|'; fi
  ) 2>/dev/null
)"
assert_eq "0|libvirt-qemu" "${out}" "detect_qemu_user: falls back to 'libvirt-qemu'"
assert_match "$(cat "${td}/calls")" "^id libvirt-qemu$" "detect_qemu_user: spy - probed libvirt-qemu"

# neither exists -> rc 1, no output
td="${WORK}/q3"; mkdir -p "${td}"
out="$(
  (
    # shellcheck source=/dev/null
    . "${MAIN}" >/dev/null 2>&1
    mock_setup "${td}"
    mock_cmd id 'exit 1'
    if u="$(detect_qemu_user)"; then printf '0|%s' "${u}"; else printf '1|'; fi
  ) 2>/dev/null
)"
assert_eq "1|" "${out}" "detect_qemu_user: rc 1 when no candidate user exists"

# --- detect_os_variant (mocks `osinfo-query`) --------------------------------

# exact ol{major}.{update} short-id present -> chosen
td="${WORK}/o1"; mkdir -p "${td}"
out="$(
  (
    # shellcheck source=/dev/null
    . "${MAIN}" >/dev/null 2>&1
    mock_setup "${td}"
    mock_cmd osinfo-query 'printf "Short ID\n--------\nol9.6\nrhel9.0\n"'
    if v="$(OL_MAJOR_VERSION=9 OL_UPDATE_VERSION=6 detect_os_variant)"; then printf '0|%s' "${v}"; else printf '1|'; fi
  ) 2>/dev/null
)"
assert_eq "0|ol9.6" "${out}" "detect_os_variant: picks exact ol9.6 short-id"
assert_match "$(cat "${td}/calls")" "^osinfo-query os --fields=short-id$" "detect_os_variant: spy - queried short-id list"

# only rhel{major}.0 present -> graceful degradation to the rhel candidate
td="${WORK}/o2"; mkdir -p "${td}"
out="$(
  (
    # shellcheck source=/dev/null
    . "${MAIN}" >/dev/null 2>&1
    mock_setup "${td}"
    mock_cmd osinfo-query 'printf "Short ID\n--------\nrhel9.0\nlinux2022\n"'
    if v="$(OL_MAJOR_VERSION=9 OL_UPDATE_VERSION=6 detect_os_variant)"; then printf '0|%s' "${v}"; else printf '1|'; fi
  ) 2>/dev/null
)"
assert_eq "0|rhel9.0" "${out}" "detect_os_variant: degrades to rhel9.0 when no ol/oraclelinux match"

# osinfo-query absent -> rc 1 (hermetic only when the host truly lacks it)
if command -v osinfo-query >/dev/null 2>&1; then
  t_skip "detect_os_variant absent-branch: host has a real osinfo-query; skipped"
else
  out="$(
    (
      # shellcheck source=/dev/null
      . "${MAIN}" >/dev/null 2>&1
      if v="$(OL_MAJOR_VERSION=9 OL_UPDATE_VERSION=6 detect_os_variant)"; then printf '0|%s' "${v}"; else printf '1|'; fi
    ) 2>/dev/null
  )"
  assert_eq "1|" "${out}" "detect_os_variant: rc 1 when osinfo-query is absent"
fi

t_done
