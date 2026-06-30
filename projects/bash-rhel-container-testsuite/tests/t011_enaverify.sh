#!/usr/bin/env bash
#==============================================================================
# tests/t011_enaverify.sh - L1 unit: ENA build-result verifier pure logic
#
# Sources verify-ena-buildresults.sh with ENA_LIB_ONLY=1 so ONLY its pure
# load-readiness helpers load (no ledger, no bundle, no kmod):
#   ena_vermagic_verdict <ko_vermagic> <expected>   GATE L4a
#   ena_symbols_verdict  <dump> <symvers>           GATE L4b
# Both are the gates that decide whether a built ena.ko could actually insmod on
# the target kernel - asserted here without building anything.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
VERIFY="${PROJ}/tests/aws_ena-driver/verify-ena-buildresults.sh"

# shellcheck source=/dev/null
ENA_LIB_ONLY=1 . "${VERIFY}"

if ! declare -F ena_vermagic_verdict >/dev/null 2>&1 || ! declare -F ena_symbols_verdict >/dev/null 2>&1; then
  t_fail "could not load the pure helpers from verify-ena-buildresults.sh"
  t_done; exit
fi

# --- ena_vermagic_verdict: L4a gate -----------------------------------------
VM="5.14.0-427.el9.x86_64 SMP mod_unload modversions"
out="$(ena_vermagic_verdict "${VM}" "${VM}")"; rc=$?
assert_rc 0 "${rc}" "identical vermagic -> rc 0"
assert_eq "ok" "${out}" "identical vermagic -> ok"

out="$(ena_vermagic_verdict "${VM}  " "${VM}")"; rc=$?
assert_rc 0 "${rc}" "trailing whitespace ignored -> rc 0"

out="$(ena_vermagic_verdict "${VM}" "5.14.0-70.el9.x86_64 SMP mod_unload modversions")"; rc=$?
assert_rc 1 "${rc}" "different vermagic -> rc 1"
assert_eq 1 "$(printf '%s' "${out}" | grep -c 'vermagic')" "mismatch reason mentions vermagic"

out="$(ena_vermagic_verdict "" "${VM}")"; rc=$?
assert_rc 1 "${rc}" "empty module vermagic -> rc 1"
assert_eq "no module vermagic" "${out}" "empty module vermagic -> reason"

out="$(ena_vermagic_verdict "${VM}" "")"; rc=$?
assert_rc 1 "${rc}" "empty expected vermagic -> rc 1"
assert_eq "no expected vermagic" "${out}" "empty expected vermagic -> reason"

# --- ena_symbols_verdict: L4b gate ------------------------------------------
SYMVERS="$(printf '%s\n' \
  "0x12345678	module_layout	vmlinux	EXPORT_SYMBOL" \
  "0xabcdef01	__register_netdev	vmlinux	EXPORT_SYMBOL" \
  "0x0badf00d	dma_map_page	vmlinux	EXPORT_SYMBOL_GPL")"

DUMP_OK="$(printf '%s\n' \
  "0x12345678 module_layout" \
  "0xabcdef01 __register_netdev")"
out="$(ena_symbols_verdict "${DUMP_OK}" "${SYMVERS}")"; rc=$?
assert_rc 0 "${rc}" "all required symbols present + CRC match -> rc 0"
assert_eq "ok 2" "${out}" "ok count is 2"

DUMP_CRC="$(printf '%s\n' \
  "0x12345678 module_layout" \
  "0xDEADBEEF __register_netdev")"
out="$(ena_symbols_verdict "${DUMP_CRC}" "${SYMVERS}")"; rc=$?
assert_rc 1 "${rc}" "a CRC mismatch -> rc 1"

DUMP_MISS="$(printf '%s\n' \
  "0x12345678 module_layout" \
  "0x99999999 not_a_kernel_symbol")"
out="$(ena_symbols_verdict "${DUMP_MISS}" "${SYMVERS}")"; rc=$?
assert_rc 1 "${rc}" "a missing symbol -> rc 1"

out="$(ena_symbols_verdict "" "${SYMVERS}")"; rc=$?
assert_rc 1 "${rc}" "empty required-symbol list -> rc 1"
assert_eq "no required-symbol list" "${out}" "empty dump -> reason"

out="$(ena_symbols_verdict "${DUMP_OK}" "")"; rc=$?
assert_rc 1 "${rc}" "empty Module.symvers -> rc 1"
assert_eq "no Module.symvers" "${out}" "empty symvers -> reason"

t_done
