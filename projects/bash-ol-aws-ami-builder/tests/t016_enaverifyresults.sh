#!/usr/bin/env bash
#==============================================================================
# tests/t016_enaverifyresults.sh - external build-result verifier verdicts
#                                  (pure unit; layer L4a/L4b logic)
#
# tests/ena/verify-ena-buildresults.sh is a standalone, READ-ONLY verifier: it
# reads the matrix ledger + a small bundle the build preserved and judges, after
# the fact, whether each ok build's module is actually load-ready -- WITHOUT
# touching the production build path. This tier loads ONLY its two pure verdict
# functions (no I/O, no kmod, no bundle) and asserts them across the shapes the
# verifier feeds them:
#   lc_vermagic_verdict <ko_vermagic> <expected_vermagic>   (L4a gate)
#   lc_symbols_verdict  <dump> <symvers>                    (L4b gate)
#
# Pure and host-runnable; no container, no kmod, no build. Self-contained.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
VERIFIER="${PROJ}/tests/ena/verify-ena-buildresults.sh"

# Load ONLY the pure verdict functions out of the verifier (do not execute the
# rest of the script). Each function body runs from its definition line to the
# first column-0 closing brace.
# shellcheck disable=SC1090
. <(sed -n '/^lc_vermagic_verdict()/,/^}/p' "${VERIFIER}")
# shellcheck disable=SC1090
. <(sed -n '/^lc_symbols_verdict()/,/^}/p' "${VERIFIER}")

if ! declare -F lc_vermagic_verdict >/dev/null 2>&1 || ! declare -F lc_symbols_verdict >/dev/null 2>&1; then
  t_fail "could not load the verdict functions from verify-ena-buildresults.sh"
  t_done
  exit
fi

# --- L4a vermagic-match -----------------------------------------------------
out="$(lc_vermagic_verdict "4.1.12-124.48.6.el6uek.x86_64 SMP mod_unload modversions" \
                           "4.1.12-124.48.6.el6uek.x86_64 SMP mod_unload modversions")"; rc=$?
assert_rc 0 "${rc}" "identical vermagic -> pass"
assert_eq "ok" "${out}" "identical vermagic -> 'ok'"

# Trailing whitespace differences are normalized (the .ko vermagic carries a trailing space).
out="$(lc_vermagic_verdict "4.1.12-uek SMP mod_unload modversions " \
                           "4.1.12-uek SMP mod_unload modversions")"; rc=$?
assert_rc 0 "${rc}" "trailing-space-only difference -> pass"

# A different kernel release (module built for the wrong kernel) -> would not insmod.
out="$(lc_vermagic_verdict "3.10.0-1160.el7.x86_64 SMP mod_unload modversions" \
                           "4.1.12-124.48.6.el6uek.x86_64 SMP mod_unload modversions")"; rc=$?
assert_rc 1 "${rc}" "wrong kernel release in vermagic -> FAIL"
assert_match "${out}" "!= expected" "vermagic mismatch -> reason states the mismatch"

out="$(lc_vermagic_verdict "" "4.1.12-uek")"; rc=$?
assert_rc 1 "${rc}" "empty module vermagic -> FAIL (cannot read the module)"
out="$(lc_vermagic_verdict "4.1.12-uek" "")"; rc=$?
assert_rc 1 "${rc}" "empty expected vermagic -> FAIL (no kernel reference)"

# --- L4b symbol-crc-kabi ----------------------------------------------------
SV=$'0x1111\tsym_a\tvmlinux\tEXPORT_SYMBOL\n0x2222\tsym_b\tvmlinux\tEXPORT_SYMBOL\n0x3333\tsym_c\tvmlinux\tEXPORT_SYMBOL_GPL'

out="$(lc_symbols_verdict $'0x1111 sym_a\n0x2222 sym_b' "${SV}")"; rc=$?
assert_rc 0 "${rc}" "all required symbols present with matching CRCs -> pass"
assert_match "${out}" "ok 2" "match -> 'ok <n>' with the matched count"

out="$(lc_symbols_verdict $'0xDEAD sym_a' "${SV}")"; rc=$?
assert_rc 1 "${rc}" "CRC mismatch on a required symbol -> FAIL (would fail at insmod)"
assert_match "${out}" "crc-mismatch" "CRC mismatch -> reason names it"

out="$(lc_symbols_verdict $'0x9999 sym_missing' "${SV}")"; rc=$?
assert_rc 1 "${rc}" "required symbol absent from Module.symvers -> FAIL"
assert_match "${out}" "missing" "missing symbol -> reason names it"

out="$(lc_symbols_verdict "" "${SV}")"; rc=$?
assert_rc 1 "${rc}" "no required-symbol dump -> FAIL (cannot judge)"
out="$(lc_symbols_verdict $'0x1111 sym_a' "")"; rc=$?
assert_rc 1 "${rc}" "no Module.symvers -> FAIL (cannot judge)"

# --- ledger reader (black-box regression pin) ---------------------------------
# The verifier's row extractor once read a top-level key ("results") the ledger
# schema never had ("entries" -- the key run-ena-buildtest-matrix.sh writes and
# merges on), so every standalone verification silently judged 0 rows and exited
# 0. Pin the schema key AND the loud-fail contract: a fixture `entries` ledger
# (one ok + one fail row) against an empty bundle must extract exactly the ok
# row, FAIL it loudly for the missing module, and exit non-zero -- never the
# "no OK rows" no-op. python3 only; kmod not needed (the missing-module fail
# fires before any modinfo/modprobe use).
FXD="$(mktemp -d)"
trap 'rm -rf "${FXD}"' EXIT
cat > "${FXD}/ledger.json" <<'JSON'
{
  "schema_version": "1.1",
  "ledger_type": "ena-buildtest-matrix",
  "dedup_key": ["osmajor", "ena_version", "kver"],
  "entries": [
    { "osmajor": "6", "ena_version": "2.9.1", "kver": "4.1.12-124.48.6.el6uek.x86_64", "status": "ok" },
    { "osmajor": "6", "ena_version": "2.10.0", "kver": "4.1.12-124.48.6.el6uek.x86_64", "status": "fail" }
  ]
}
JSON
mkdir -p "${FXD}/bundle"
vout="$(bash "${VERIFIER}" --ledger "${FXD}/ledger.json" --bundle "${FXD}/bundle" 2>&1)"; vrc=$?
assert_rc 1 "${vrc}" "entries-keyed ledger + empty bundle -> non-zero exit (ok row not load-ready)"
assert_match "${vout}" '"ok_rows":1' "row extractor reads the 'entries' schema key and filters status==ok (1 of 2 rows)"
assert_match "${vout}" 'module not in bundle' "missing bundle module for an ok row -> loud FAIL (no silent skip)"
if printf '%s' "${vout}" | grep -q 'no OK rows in the ledger'; then
  t_fail "verifier claimed 'no OK rows' against a ledger with an ok entry (schema-key regression)"
else
  t_pass "no 'no OK rows' no-op against a populated entries ledger"
fi

t_done
