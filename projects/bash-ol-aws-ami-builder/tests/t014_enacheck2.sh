#!/usr/bin/env bash
#==============================================================================
# tests/t014_enacheck2.sh - Phase 6 CHECK 2 self-build provenance verdict
#                          (layer L0/L1, pure unit; defense-in-depth Layer 3)
#
# CHECK 2 (offline image inspection, B-T7) passed on mere ENA module presence,
# so a build that requested the self-built pin but ended up with only the stock
# in-tree ena.ko (e.g. a masked DKMS failure) would still PASS -- the AMI would
# silently carry the stock driver. The fix gates the PASS on provenance via the
# pure `_ena_check2_ok`: when a self-build was performed (ENA_BUILD_VERSION set,
# i.e. OL6/OL7 default), the module must be the self-built one (/updates|/extra);
# the stock /kernel copy alone is a FAIL. When no self-build was requested
# (--skip-ena-driver, OL8+ in-distro, OL9+) any present module is acceptable.
#
# This tier loads ONLY that function out of build-ol-aws-ami.sh (the wrapper's
# tail main is guarded) and asserts the verdict. Host-runnable, self-contained.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
WRAP="${PROJ}/build-ol-aws-ami.sh"

# shellcheck disable=SC1090
. <(sed -n '/^_ena_check2_ok()/,/^}/p' "${WRAP}")

if ! declare -F _ena_check2_ok >/dev/null 2>&1; then
  t_fail "could not load _ena_check2_ok from build-ol-aws-ami.sh"
  t_done
  exit
fi

K="/lib/modules/4.1.12-124.48.6.el6uek.x86_64/kernel/drivers/net/ethernet/amazon/ena/ena.ko"
X="/lib/modules/4.1.12-124.48.6.el6uek.x86_64/extra/ena.ko"
U="/lib/modules/4.1.12-124.48.6.el6uek.x86_64/updates/ena.ko"

# --- no self-build requested (ENA_BUILD_VERSION empty) -> any module is fine ---
_ena_check2_ok "" "${K}"; assert_rc 0 "$?" "no self-build (--skip / OL8+ / pure): stock /kernel module -> ok"
_ena_check2_ok "" "${X}"; assert_rc 0 "$?" "no self-build: a self-built module present -> ok"

# --- self-build requested (pin set) -> must be the self-built module ----------
_ena_check2_ok "2.9.1" "${X}"; assert_rc 0 "$?" "self-build pin: module in /extra -> ok"
_ena_check2_ok "2.9.1" "${U}"; assert_rc 0 "$?" "self-build pin: module in /updates -> ok"
_ena_check2_ok "2.9.1" "${K}"; assert_rc 1 "$?" "self-build pin but only the stock /kernel module -> FAIL"
# xz-compressed stock module (OL7/OL8 ship ena.ko.xz) still classifies as stock.
_ena_check2_ok "2.17.0" "${K}.xz"; assert_rc 1 "$?" "self-build pin but only stock /kernel ena.ko.xz -> FAIL"

t_done
