#!/usr/bin/env bash
#==============================================================================
# tests/t023_ol5ena.sh - OL5/el5uek ENA wiring + ledger merge mode (layer L0/L1)
#
# Pins the user-adjudicated OL5 integration (2026-07-18) against regressions:
#
#  (A) install-ena-driver.sh: the OL5 branch is opt-in, plain-make only, and
#      host-pre-provisioned (EL5 has no in-OS TLS 1.2 path); the el5uek shim
#      set is the EXACT transform set a 20/20 build sweep proved sufficient,
#      so every proven pattern string is pinned here -- if upstream-source or
#      shim drift changes one, this tier (not a live OL5 build) catches it.
#      EL5-guest safety is pinned too: no `sort -V` (coreutils 5.97 lacks it;
#      the first container FT caught exactly that).
#  (B) run-ena-buildtest-matrix.sh: OL5 never in the default OL set, floor
#      semantics uniform (the OL5 all-release evaluation is `--ol 5 --full`),
#      pin/channel-path/gate-normalization wiring, the frozen host-side
#      toolchain RPM closure, and the schema-1.2 `shims` ledger field.
#  (C) --merge-from: a hermetic functional check of the adjudicated conflict
#      policy (adopt new keys; same-status keeps the incumbent row; different
#      status is a hard error unless --merge-prefer resolves it).
#
# Host-runnable, self-contained: bash + grep + python3; no container, no
# network, no build.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
INST="${PROJ}/install-ena-driver.sh"
MATRIX="${PROJ}/tests/ena/run-ena-buildtest-matrix.sh"

inst="$(cat "${INST}")"
mtx="$(cat "${MATRIX}")"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# ---- (A) installer: OL5 branch + el5uek shim set ---------------------------
assert_match "${inst}" '^ENA_VERSION_OL5="\$\{ENA_VERSION_OL5:-2\.9\.1\}"$' \
  "installer: OL5 pin defaults to 2.9.1 (OL6 parity; top of the proven range)"
assert_match "${inst}" '^  5\)  ena_version="\$\{ENA_DRIVER_VERSION:-\$\{ENA_VERSION_OL5\}\}" ;;$' \
  "installer: osmajor case dispatches 5"
assert_match "${inst}" 'ol5_verify_preprovisioned\(\)' \
  "installer: OL5 pre-provision contract check exists"
assert_match "${inst}" 'OL5: DKMS is not used on EL5 by design' \
  "installer: OL5 is plain-make only (DKMS out of scope)"
assert_match "${inst}" 'OL5: source tarball not pre-staged at' \
  "installer: OL5 source pre-stage contract is enforced"
assert_match "${inst}" 'OL5: skipping initramfs regeneration' \
  "installer: OL5 skips initramfs (devel-only provision has no module tree)"

# EL5-guest safety: the OL5 helpers and shim function must never use sort -V
# (coreutils 5.97). Cut the two OL5 function bodies, drop comment lines (the
# rationale comments legitimately NAME sort -V), and scan the code.
ol5_funcs="$(sed -n '/^ol5_verify_preprovisioned()/,/^}/p; /^apply_el5uek_shims()/,/^  log "\[el5uek-shims\]/p' "${INST}" | grep -v '^\s*#')"
if printf '%s' "${ol5_funcs}" | grep -q 'sort -V'; then
  t_fail "installer: OL5 code paths avoid sort -V (absent from EL5 coreutils 5.97)"
else
  t_pass "installer: OL5 code paths avoid sort -V (absent from EL5 coreutils 5.97)"
fi

# The proven shim patterns (exact strings from the 20/20 sweep). Fixed grep -F:
# these are match-targets in kcompat.h/Makefile, pinned verbatim.
shim_pins=(
  'el5uek-shims S1'
  'typedef u32 netdev_features_t;'
  'echo el5-generic | grep uek'
  'only UEK3 with kernel version 3.8.13'
  '__el5uek_p1_ether_addr_equal'
  '__el5uek_p2_ethtool_rxfh_indir_default'
  'skb->l4_rxhash = (type == PKT_HASH_TYPE_L4);'
  '__el5uek_p4_netdev_rss_key_fill'
  '#define ENA_DMA_ATTR_SKIP_CPU_SYNC 0'
  '__EL5UEK_TAIL_SHIM__'
  '__el5uek_p7_dma_zalloc_coherent'
)
for pin in "${shim_pins[@]}"; do
  if grep -Fq -- "${pin}" "${INST}"; then
    t_pass "installer shim pin present: ${pin}"
  else
    t_fail "installer shim pin present: ${pin}"
  fi
done

assert_match "${inst}" '"shims":"%s"' \
  "installer: buildtest result JSON carries the shims field"

# ---- (B) matrix: OL5 opt-in wiring -----------------------------------------
assert_match "${mtx}" '^OL_LIST="6 7 8 9 10"$' \
  "matrix: the DEFAULT OL set stays 6-10 (OL5 is opt-in only)"
assert_match "${mtx}" '5\) echo 2\.9\.1 ;;' \
  "matrix: pin_for(5) = 2.9.1"
assert_match "${mtx}" '5\) echo UEK/latest ;;' \
  "matrix: uekr_for(5) = UEK/latest (pre-UEKR channel naming)"
assert_match "${mtx}" 'case "\$\{ol\}" in 5\|6\|7\|8\|9\|10\)' \
  "matrix: the build loop accepts --ol 5"
assert_match "${mtx}" '^OL5_UEK_FALLBACK_KVER="2\.6\.39-400\.297\.3\.el5uek\.x86_64"$' \
  "matrix: OL5 kernel-uek-devel fallback pin"
rpm_count="$(sed -n '/^OL5_TOOLCHAIN_RPMS="/,/^[a-z].*"$/p' "${MATRIX}" | grep -c '\.rpm')"
assert_eq "12" "${rpm_count}" \
  "matrix: the frozen OL5 toolchain closure is exactly the 12 proven RPMs"
assert_match "${mtx}" 'gcc-4\.1\.2-55\.el5\.x86_64\.rpm' \
  "matrix: the proven gcc 4.1.2 NVR is in the closure"
assert_match "${mtx}" 'latest_kver="\$\{latest_kver%\.x86_64\}"' \
  "matrix: the OL5 gate probe strips .x86_64 (EL5 modules dir has no arch suffix)"
assert_match "${mtx}" '"schema_version": "1\.2"' \
  "matrix: ledger schema is 1.2"
assert_match "${mtx}" '"shims": \(r\.get\("shims"\) or None\)' \
  "matrix: ledger rows record the shims field"
assert_match "${mtx}" 'OL5 is a build-test / PoC scoped, opt-in target' \
  "matrix: RESULTS-ol5.md carries the OL5 scope paragraph"
assert_match "${mtx}" '--merge-from <path>' \
  "matrix: usage documents --merge-from"

# ---- (C) merge mode: hermetic functional check -----------------------------
mk_row() { # ver status
  printf '{"osmajor":"5","ena_version":"%s","kver":"k1","status":"%s","dkms":0,"ko":null,"ko_version":null,"ena_express":null,"shims":null,"reason":null,"tested_at":"t"}' "$1" "$2"
}
printf '{"schema_version":"1.2","entries":[%s]}\n' "$(mk_row 2.9.1 ok)" > "${WORK}/base.json"
printf '{"schema_version":"1.2","entries":[%s,%s]}\n' "$(mk_row 2.9.0 ok)" "$(mk_row 2.9.1 ok)" > "${WORK}/theirs_a.json"
printf '{"schema_version":"1.2","entries":[%s]}\n' "$(mk_row 2.9.1 fail)" > "${WORK}/theirs_b.json"

# C1: adopt the new key; the same-status incumbent stays.
cp "${WORK}/base.json" "${WORK}/led.json"
out="$(bash "${MATRIX}" --ledger "${WORK}/led.json" --results-dir "${WORK}/r1" --merge-from "${WORK}/theirs_a.json" 2>&1)"
rc=$?
assert_rc 0 "${rc}" "merge C1: adopt + same-status merge succeeds"
assert_match "${out}" 'MERGED adopted=1 same-status-kept=1' \
  "merge C1: one key adopted, one same-status kept"
n_rows="$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['entries']))" "${WORK}/led.json")"
assert_eq "2" "${n_rows}" "merge C1: merged ledger has 2 rows"

# C2: different status for the same key is a hard error; the ledger is untouched.
cp "${WORK}/base.json" "${WORK}/led.json"
out="$(bash "${MATRIX}" --ledger "${WORK}/led.json" --results-dir "${WORK}/r2" --merge-from "${WORK}/theirs_b.json" 2>&1)"
rc=$?
if [ "${rc}" -ne 0 ]; then
  t_pass "merge C2: same-key different-status is a hard error (rc=${rc})"
else
  t_fail "merge C2: same-key different-status is a hard error (got rc=0)"
fi
assert_match "${out}" 'merge conflict: OL5 ena 2\.9\.1' \
  "merge C2: the conflicting key is named"
st="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['entries'][0]['status'])" "${WORK}/led.json")"
assert_eq "ok" "${st}" "merge C2: the base ledger is left untouched on the error path"

# C3: --merge-prefer theirs resolves the conflict.
cp "${WORK}/base.json" "${WORK}/led.json"
out="$(bash "${MATRIX}" --ledger "${WORK}/led.json" --results-dir "${WORK}/r3" --merge-from "${WORK}/theirs_b.json" --merge-prefer theirs 2>&1)"
rc=$?
assert_rc 0 "${rc}" "merge C3: --merge-prefer theirs resolves the conflict"
st="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['entries'][0]['status'])" "${WORK}/led.json")"
assert_eq "fail" "${st}" "merge C3: theirs status replaces ours"

t_done
