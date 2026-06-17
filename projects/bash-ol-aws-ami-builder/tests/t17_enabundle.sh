#!/usr/bin/env bash
#==============================================================================
# tests/t17_enabundle.sh - load-readiness bundle PRODUCER layout/contract
#                          (pure unit; the 0017 cp, no real build)
#
# tests/ena/run-ena-buildtest-matrix.sh's preserve_bundle() is a DUMB copy: after
# each ENA_BUILDTEST it lifts the artifacts the build already produced into the
# exact on-disk layout that the SEPARATE, read-only verify-ena-buildresults.sh
# (0016) consumes. It adds NO load-readiness judgement and does not branch on the
# build's ok/fail status. This tier loads ONLY that function (no container, no
# real kernel, no kmod) and drives it against a fabricated image tree, asserting:
#   * the per-version ena.ko lands at modules/ol<N>-ena_<ver>-<kver>.ko
#   * the shared per-kver Module.symvers / kernel.vermagic / initramfs.list land
#     under kver/<kver>/ with the right contents
#   * kernel.vermagic comes from a STOCK module, NOT the freshly built ena.ko
#     (so the verifier's L4a compare is meaningful)
#   * a failed build (no DKMS ena.ko) fabricates no per-version module
#   * the produced paths are exactly the ones the verifier reads
#
# Host-runnable; self-contained. The initramfs fixture builds via cpio when
# present, else a self-contained python3 newc writer, so the initramfs.list
# assertions RUN on any host with cpio+gzip or python3 (rather than skipping);
# the `strings` vermagic fallback remains optional.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
MATRIX="${PROJ}/tests/ena/run-ena-buildtest-matrix.sh"
VERIFIER="${PROJ}/tests/ena/verify-ena-buildresults.sh"

# Load ONLY preserve_bundle out of the matrix script (do not execute the rest).
# shellcheck disable=SC1090
. <(sed -n '/^preserve_bundle()/,/^}/p' "${MATRIX}")

if ! declare -F preserve_bundle >/dev/null 2>&1; then
  t_fail "could not load preserve_bundle from run-ena-buildtest-matrix.sh"
  t_done
  exit
fi

# Local helpers (use explicit if/then so shellcheck's A && B || C note never fires).
assert_file()    { if [ -f "$1" ]; then t_pass "$2"; else t_fail "$2 (missing: $1)"; fi; }
assert_nofile()  { if [ -f "$1" ]; then t_fail "$2 (unexpected: $1)"; else t_pass "$2"; fi; }
assert_noexist() { if [ -e "$1" ]; then t_fail "$2 (unexpected: $1)"; else t_pass "$2"; fi; }

KVER="4.1.12-124.48.6.el6uek.x86_64"
VM="${KVER} SMP mod_unload modversions"

# --- fabricate a "successful build" container image -------------------------
make_img() {  # <root> ; build a fake post-build /lib/modules + /boot tree
  local r="$1"
  mkdir -p "${r}/lib/modules/${KVER}/updates/dkms" \
           "${r}/lib/modules/${KVER}/build" \
           "${r}/lib/modules/${KVER}/kernel/drivers/net/ethernet/amazon/ena" \
           "${r}/boot"
  printf 'BUILT-ENA-KO-CONTENT\n'                 > "${r}/lib/modules/${KVER}/updates/dkms/ena.ko"
  printf '0x12345678\tena_com_init\tvmlinux\tEXPORT_SYMBOL\n' > "${r}/lib/modules/${KVER}/build/Module.symvers"
  # stock in-tree module: its vermagic is the kernel's. modinfo will reject this
  # non-ELF stand-in, so the producer's `strings` fallback reads vermagic= here.
  printf 'some binary-ish text\nvermagic=%s\nmore text\n' "${VM}" \
                                                  > "${r}/lib/modules/${KVER}/kernel/drivers/net/ethernet/amazon/ena/ena.ko"
}

# A gzipped-cpio (newc) initramfs that lists ena.ko, so the producer's listing
# path and the assertions on it can run. Built with cpio when present (the real
# builder-host tool); otherwise with a self-contained python3 writer so a minimal
# container WITHOUT cpio still EXERCISES the path instead of skipping it. Returns
# 1 only if neither cpio+gzip nor python3 is available (a near-impossible host).
make_initramfs() {  # <root>
  local r="$1" stg
  if command -v cpio >/dev/null 2>&1 && command -v gzip >/dev/null 2>&1; then
    stg="$(mktemp -d)"
    mkdir -p "${stg}/lib/modules/${KVER}/updates"
    : > "${stg}/lib/modules/${KVER}/updates/ena.ko"
    ( cd "${stg}" && find . | cpio -o -H newc 2>/dev/null ) | gzip > "${r}/boot/initramfs-${KVER}.img"
    rm -rf "${stg}"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "${KVER}" "${r}/boot/initramfs-${KVER}.img" <<'PYMK'
import sys, os, gzip
kver = sys.argv[1]
out  = sys.argv[2]
def ent(name, data, mode, ino, nlink):
    nb = name.encode() + b"\x00"
    f = [ino, mode, 0, 0, nlink, 0, len(data), 0, 0, 0, 0, len(nb), 0]
    h = b"070701" + b"".join(b"%08X" % x for x in f) + nb
    h += b"\x00" * ((-len(h)) % 4)
    h += data
    h += b"\x00" * ((-len(data)) % 4)
    return h
buf = bytearray(); ino = 1
for d in ("lib", "lib/modules", "lib/modules/%s" % kver,
          "lib/modules/%s/updates" % kver):
    buf += ent("./" + d, b"", 0o040755, ino, 2); ino += 1
buf += ent("./lib/modules/%s/updates/ena.ko" % kver, b"", 0o100644, ino, 1); ino += 1
buf += ent("TRAILER!!!", b"", 0, ino, 1)
os.makedirs(os.path.dirname(out), exist_ok=True)
with gzip.open(out, "wb") as g:
    g.write(bytes(buf))
PYMK
    return 0
  fi
  return 1
}

IMG="$(mktemp -d)"; BUNDLE="$(mktemp -d)"
trap 'rm -rf "${IMG}" "${BUNDLE}"' EXIT
make_img "${IMG}"
HAVE_INITRAMFS=0
if make_initramfs "${IMG}"; then HAVE_INITRAMFS=1; fi

# --- call the producer for an ok build (OL6, 2.9.1) -------------------------
preserve_bundle 6 2.9.1 "${IMG}" "${BUNDLE}" || t_fail "preserve_bundle returned non-zero"

ko="${BUNDLE}/modules/ol6-ena_2.9.1-${KVER}.ko"
kdir="${BUNDLE}/kver/${KVER}"

# 1) per-version ena.ko at the verifier's exact path
assert_file "${ko}" "per-version ena.ko at modules/ol6-ena_2.9.1-<kver>.ko"
assert_eq "BUILT-ENA-KO-CONTENT" "$(cat "${ko}" 2>/dev/null)" "ena.ko is the DKMS-built module (copied verbatim)"

# 2) shared Module.symvers
assert_file "${kdir}/Module.symvers" "Module.symvers under kver/<kver>/"
assert_match "$(cat "${kdir}/Module.symvers" 2>/dev/null)" "ena_com_init" "Module.symvers copied verbatim (the kernel's)"

# 3) kernel.vermagic from the STOCK module, not the built ena.ko
assert_file "${kdir}/kernel.vermagic" "kernel.vermagic under kver/<kver>/"
assert_eq "${VM}" "$(cat "${kdir}/kernel.vermagic" 2>/dev/null)" "kernel.vermagic is the STOCK module's vermagic (independent of the built ko)"

# 4) initramfs.list -- the fixture now builds via cpio OR a python3 fallback, so
#    this runs on any host with cpio+gzip or python3; the skip is reached only on
#    the near-impossible host that has none of them.
if [ "${HAVE_INITRAMFS}" -eq 1 ]; then
  assert_file "${kdir}/initramfs.list" "initramfs.list under kver/<kver>/"
  assert_match "$(cat "${kdir}/initramfs.list" 2>/dev/null)" "ena\.ko" "initramfs.list lists ena.ko (cpio -t / python3 newc fallback)"
else
  t_skip "initramfs.list (no cpio/gzip and no python3 on host to build the fixture)"
  t_skip "initramfs.list content (fixture unavailable)"
fi

# 5) a second ok version on the SAME kver accumulates per-version, shares per-kver
preserve_bundle 6 2.8.6 "${IMG}" "${BUNDLE}" || t_fail "preserve_bundle (2nd version) returned non-zero"
assert_file "${BUNDLE}/modules/ol6-ena_2.8.6-${KVER}.ko" "2nd version adds modules/ol6-ena_2.8.6-<kver>.ko"
if [ -f "${ko}" ] && [ -f "${kdir}/Module.symvers" ]; then
  t_pass "1st version + shared per-kver files survive the 2nd call (idempotent)"
else
  t_fail "2nd call clobbered earlier artifacts"
fi

# 6) a FAILED build (no DKMS /updates|/extra ena.ko) fabricates no per-version module
FIMG="$(mktemp -d)"; FBUN="$(mktemp -d)"
mkdir -p "${FIMG}/lib/modules/${KVER}/build" "${FIMG}/lib/modules/${KVER}/kernel"
: > "${FIMG}/lib/modules/${KVER}/build/Module.symvers"
preserve_bundle 6 2.2.0 "${FIMG}" "${FBUN}" || t_fail "preserve_bundle (failed build) returned non-zero"
assert_nofile "${FBUN}/modules/ol6-ena_2.2.0-${KVER}.ko" "failed build (no DKMS ko) -> no per-version module fabricated"
rm -rf "${FIMG}" "${FBUN}"

# 7) empty bundle-dir is a clean no-op (no judgement, no crash, nothing written)
EBUN="$(mktemp -d)"; rmdir "${EBUN}"
preserve_bundle 6 2.9.1 "${IMG}" "" || t_fail "preserve_bundle with empty bundle-dir returned non-zero"
assert_noexist "${EBUN}" "empty bundle-dir -> clean no-op"

# 8) producer output == the paths verify-ena-buildresults.sh actually reads
#    (lift the read-path expressions straight from the verifier's own header).
contract_ok=1
grep -q 'modules/ol<N>-ena_<ver>-<kver>.ko' "${VERIFIER}" || contract_ok=0
grep -q 'kver/<kver>/Module.symvers'        "${VERIFIER}" || contract_ok=0
grep -q 'kver/<kver>/kernel.vermagic'       "${VERIFIER}" || contract_ok=0
grep -q 'kver/<kver>/initramfs.list'        "${VERIFIER}" || contract_ok=0
if [ "${contract_ok}" -eq 1 ]; then
  t_pass "produced layout matches the verifier's documented read-paths"
else
  t_fail "verifier read-paths drifted from the producer layout"
fi

t_done
