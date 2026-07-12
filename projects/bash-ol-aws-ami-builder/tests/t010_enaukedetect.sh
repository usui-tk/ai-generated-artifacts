#!/usr/bin/env bash
#==============================================================================
# tests/t010_enaukedetect.sh - ENA Makefile UEK-detection retarget (layer L1/L2)
#
# install-ena-driver.sh patches the amzn-drivers ENA Makefile (OL6 and OL8) so
# its IS_UEK / ENA_KERNEL_SUBVERSION_* detection reads the DKMS target kernel
# (BUILD_KERNEL) instead of `uname -r`. Under the libguestfs provisioning
# appliance (and the container matrix's chroot) `uname -r` is the non-UEK
# host/appliance kernel, which mis-fires UEK-gated kcompat.h guards:
# OL6/UEK4 page_ref_count (redefinition, >= 124.43.1 backport) and OL8/UEKR7
# bpf_warn_invalid_xdp_action (1-arg collapse vs the 3-arg 5.15 backport;
# upstream's IS_UEK >= 5.15.0-100.96.32 exclusion can only fire when IS_UEK
# is set). Container FT 2026-07-12: with the retarget (+ gcc-toolset-11), ENA
# 2.17.2 builds as 2.17.2g on 5.15.0-322.203.3.3.el8uek.
#
# This tier is host-runnable and self-contained:
#   (structural)  the patch is present, OL6|OL8-gated, idempotency-guarded, and
#                 pipe-anchored so the `BUILD_KERNEL ?= $(shell uname -r)`
#                 default line is NOT rewritten;
#   (behavioural) applies the same retarget to a fixture carrying the three
#                 canonical Makefile lines and asserts the two detection sites
#                 move to $(BUILD_KERNEL) while the default line stays put and
#                 no `uname -r |` pipe remains.
# The actual module compile + Nitro boot are the build-host tiers (B-T7/B-T8).
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
INST="${PROJ}/install-ena-driver.sh"

inst="$(cat "${INST}")"

# ---- structural: the patch exists and is correctly scoped ------------------
assert_match "${inst}" 'patch_ena_uek_detection\(\) \{' \
  "ena-uek-detect: patch_ena_uek_detection() is defined"
assert_match "${inst}" '"\$\{osmajor\}" == "6" \|\| "\$\{osmajor\}" == "8"' \
  "ena-uek-detect: invocation is OL6|OL8-gated (per-OS isolation)"
assert_match "${inst}" 'uname -r \| grep uek#.*BUILD_KERNEL' \
  "ena-uek-detect: IS_UEK detection retargeted to BUILD_KERNEL"
assert_match "${inst}" 'uname -r \| sed#.*BUILD_KERNEL' \
  "ena-uek-detect: subversion detection retargeted to BUILD_KERNEL"
assert_match "${inst}" 'grep -Fq' \
  "ena-uek-detect: fronted by a grep -Fq idempotency guard"

# ---- behavioural: apply the retarget to a fixture Makefile -----------------
fix="$(mktemp)"
cat > "${fix}" <<'EOF_MK'
BUILD_KERNEL ?= $(shell uname -r)
  subversions_array_tmp=(`uname -r | sed 's/[^0-9]\+/ /g ; s/\s$$//'`) && \
  IS_UEK=$(shell uname -r | grep uek)
EOF_MK

S='$'
sed -i \
  -e "s#uname -r | grep uek#echo \"${S}(BUILD_KERNEL)\" | grep uek#" \
  -e "s#uname -r | sed#echo \"${S}(BUILD_KERNEL)\" | sed#" \
  "${fix}"

is_uek_line="$(grep 'IS_UEK=' "${fix}")"
subv_line="$(grep 'subversions_array_tmp=' "${fix}")"
default_line="$(grep 'BUILD_KERNEL ?=' "${fix}")"
residual="$(grep -c 'uname -r |' "${fix}" || true)"

assert_match "${is_uek_line}" 'echo "\$\(BUILD_KERNEL\)" \| grep uek' \
  "ena-uek-detect: fixture IS_UEK line now reads BUILD_KERNEL"
assert_match "${subv_line}" 'echo "\$\(BUILD_KERNEL\)" \| sed' \
  "ena-uek-detect: fixture subversion line now reads BUILD_KERNEL"
assert_eq "BUILD_KERNEL ?= ${S}(shell uname -r)" "${default_line}" \
  "ena-uek-detect: BUILD_KERNEL default line left untouched (pipe-anchored sed)"
assert_eq "0" "${residual}" \
  "ena-uek-detect: no 'uname -r |' pipe remains after retarget"

rm -f "${fix}"

# --- gcc-toolset PATH blocks: match the kernel's build-time gcc --------------
# OL9/UEKR8 needs gcc-toolset-14 (kernel built with gcc 14.2.1); OL8/UEKR7
# needs gcc-toolset-11 (kernel built with gcc 11.5.0 -- 2026-07-11 preflight:
# base gcc 8.5 dies on -ftrivial-auto-var-init=zero). Both toolsets arrive as
# declared RPM dependencies of the matching kernel-uek-devel; the installer
# only PATH-prepends, never touching /usr/bin/gcc. Structural pins so a
# refactor cannot silently drop either block.
assert_match "${inst}" '"\$\{osmajor\}" == "9" && "\$\{kver\}" == 6\.\*uek\*' \
  "gcc-toolset: OL9/UEKR8 block gated on osmajor=9 + 6.x uek kver"
assert_match "${inst}" 'gcc-toolset-14/root/usr/bin:\$\{PATH\}' \
  "gcc-toolset: OL9 block PATH-prepends gcc-toolset-14"
assert_match "${inst}" '"\$\{osmajor\}" == "8" && "\$\{kver\}" == 5\.15\.\*uek\*' \
  "gcc-toolset: OL8/UEKR7 block gated on osmajor=8 + 5.15.x uek kver"
assert_match "${inst}" 'gcc-toolset-11/root/usr/bin:\$\{PATH\}' \
  "gcc-toolset: OL8 block PATH-prepends gcc-toolset-11"

# --- report_inbox_ena : must NEVER abort the install (errexit/pipefail safe) --
# BUG HISTORY (2026-07-11, first real OL8 AMI build): on a guest kernel with NO
# in-box ena module, the unguarded 'modinfo | head' substitutions failed under
# the installer's set -euo pipefail and killed the whole provisioning silently,
# between the "Building & installing" log line and 'dkms add' (/usr/src staged,
# /var/lib/dkms untouched). The container matrix never caught it because
# clean-core lacks modinfo, so the function's guard took the skip branch.
# This test extracts the SHIPPED function text and runs it under the same shell
# options with modinfo present and the module ABSENT (the real-guest condition).
if ! command -v modinfo >/dev/null 2>&1; then
  t_skip "inbox-report: modinfo (kmod) not installed on this host"
else
  fnbody="$(mktemp)"
  awk '/^report_inbox_ena\(\) \{/,/^\}/' "${INST}" > "${fnbody}"
  if ! grep -q 'report_inbox_ena()' "${fnbody}"; then
    t_fail "inbox-report: could not extract report_inbox_ena from the installer"
  else
    out="$(
      bash -c '
        set -euo pipefail
        kver="0.0.0-nonexistent.kver.x86_64"
        log() { printf "%s\n" "$*"; }
        . "'"${fnbody}"'"
        report_inbox_ena
        printf "SURVIVED\n"
      ' 2>/dev/null
    )"; rc=$?
    assert_eq 0 "${rc}" "inbox-report: absent in-box module does NOT kill the installer (rc 0 under set -euo pipefail)"
    assert_match "${out}" 'SURVIVED' "inbox-report: execution continues past the report"
    assert_match "${out}" 'in-box ENA.*<not found>' "inbox-report: the informational line itself is still emitted"
  fi
  rm -f "${fnbody}"
fi

t_done
