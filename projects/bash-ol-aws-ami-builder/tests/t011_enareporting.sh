#!/usr/bin/env bash
#==============================================================================
# tests/t011_enareporting.sh - ENA reporting / AMI identification / pin-log
#                             accuracy (layer L1/L2, structural + behavioural)
#
# Guards the OL7/OL8 E2E-feedback changes:
#   (1) Phase 6 prints aligned, fixed-width ENA labels and an explicit in-tree
#       no-version fallback instead of a bare "none".
#   (2) install-ena-driver.sh logs the in-box ENA identity before the self-build.
#   (3) self-build AMIs are marked in AMI_NAME/AMI_DESCRIPTION and the final
#       summary prints the description + an ENA driver line.
#   (4) the [OLAWS-ENA01] hook log no longer hardcodes the (stale) OL6 pin; it
#       and the AMI name/description read the pin from install-ena-driver.sh.
#
# Host-runnable and self-contained; the actual AMI naming/boot is the build-host
# E2E (B-T7/B-T8). Presence checks grep the FILE directly (not a cached "$(cat)"
# string piped to grep -q): on a large file, grep -q exits on the first match
# before printf finishes writing, and `set -o pipefail` would then surface the
# writer's SIGPIPE as a spurious assertion failure.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
WRAP="${PROJ}/build-ol-aws-ami.sh"
INST="${PROJ}/install-ena-driver.sh"

# grep the file directly; see header note on the printf|grep -q + pipefail race.
assert_in() {      # FILE EXTENDED_REGEX MSG
  if grep -Eq -- "$2" "$1"; then t_pass "$3"
  else t_fail "$3 (no match for /$2/ in $(basename "$1"))"; fi
}
assert_not_in() {  # FILE EXTENDED_REGEX MSG
  if grep -Eq -- "$2" "$1"; then t_fail "$3 (unexpected match for /$2/ in $(basename "$1"))"
  else t_pass "$3"; fi
}

# ---- (1)(4) Phase 6 labels + pin reader (wrapper) --------------------------
assert_in "${WRAP}" '_ena_pin_for_major\(\) \{' \
  "ena-report: _ena_pin_for_major() pin reader defined"
assert_in "${WRAP}" 'ENA Driver \(Kernel in-box\) -' \
  "ena-report: aligned in-box label present"
assert_in "${WRAP}" 'ENA Driver \(Self-Build\) +-' \
  "ena-report: aligned self-build label present"
assert_in "${WRAP}" 'no version field \(kernel-bundled\)' \
  "ena-report: in-box no-version fallback (not bare 'none')"

# ---- (3) AMI identification (wrapper) --------------------------------------
assert_in "${WRAP}" '\-ena\$\{ENA_BUILD_VERSION' \
  "ena-report: AMI_NAME gains -ena<ver> suffix on self-build"
assert_in "${WRAP}" 'self-built Amazon ENA' \
  "ena-report: AMI_DESCRIPTION carries the self-built clause"
assert_in "${WRAP}" 'AMI Description: ' \
  "ena-report: final summary prints AMI Description"
assert_in "${WRAP}" 'ENA driver: +\$\{ena_summary\}' \
  "ena-report: final summary prints an ENA driver line"

# ---- (4) pin-log drift fixed (wrapper) -------------------------------------
assert_not_in "${WRAP}" 'OL6 2\.5\.0' \
  "ena-report: stale hardcoded 'OL6 2.5.0' removed from the hook log"
assert_in "${WRAP}" 'OLAWS-ENA01.*_ena_pin_for_major' \
  "ena-report: [OLAWS-ENA01] hook log derives the pin from install-ena-driver.sh"
assert_in "${WRAP}" 'ENA_VERSION_OL\$\{major\}' \
  "ena-report: pin reader greps ENA_VERSION_OL<major> from the installer"

# ---- (2) in-box pre-build report (installer) -------------------------------
assert_in "${INST}" 'report_inbox_ena\(\) \{' \
  "ena-report: report_inbox_ena() defined in installer"
assert_in "${INST}" '^[[:space:]]*report_inbox_ena[[:space:]]*$' \
  "ena-report: report_inbox_ena invoked (before the build dispatch)"

# ---- behavioural: the pin reader resolves the installer's real pins --------
pin6="$(grep -E "^ENA_VERSION_OL6=" "${INST}" | sed -E 's/.*:-([^}"]+)\}.*/\1/' | head -1)"
pin7="$(grep -E "^ENA_VERSION_OL7=" "${INST}" | sed -E 's/.*:-([^}"]+)\}.*/\1/' | head -1)"
assert_eq "2.9.1"  "${pin6}" "ena-report: pin reader resolves OL6 default (2.9.1) from the live installer"
assert_eq "2.17.2" "${pin7}" "ena-report: pin reader resolves OL7 default (2.17.2) from the live installer"

# ---- (5) OL6-10 production wiring (ENA Express generation) ------------------
# The self-build hook, the AMI identity, and the final summary all follow the
# plain ENA_DRIVER_BUILD knob for every major (the former OL6/OL7-only gates
# are retired); OL8/9/10 resolve amzn-drivers latest HOST-SIDE and pass the
# concrete version into the guest so the AMI name and artifact cannot drift.
assert_in "${WRAP}" '_ena_resolve_latest_host\(\) \{' \
  "ena-wiring: host-side amzn-drivers latest resolver defined"
assert_in "${WRAP}" '_ena_fallback_pin\(\) \{' \
  "ena-wiring: installer ENA_LATEST_FALLBACK_PIN reader defined"
assert_in "${WRAP}" 'OLAWS-ENA02' \
  "ena-wiring: [OLAWS-ENA02] load_env resolution log marker present"
assert_in "${WRAP}" 'ENA_DRIVER_VERSION=\$\{ENA_BUILD_VERSION\} /usr/local/sbin/ol-aws-install-ena-driver\.sh' \
  "ena-wiring: latest-resolving majors pass the host-resolved version into the guest hook"
assert_not_in "${WRAP}" 'ENA driver self-build hook not injected for OL' \
  "ena-wiring: the OL6/OL7-only hook gate is retired (hook injects on OL6-10)"
if grep -Eq 'ENA_DRIVER_BUILD.*-eq 1 && \( .OL_MAJOR_VERSION.*== .6.*\|\|.*== .7. \)' "${WRAP}"; then
  t_fail "ena-wiring: a residual OL6/OL7-only ENA_DRIVER_BUILD gate remains in the wrapper"
else
  t_pass "ena-wiring: no residual OL6/OL7-only ENA_DRIVER_BUILD gate remains"
fi

# --- buildtest UEK track pins (matrix fidelity) --------------------------------
# The container matrix must provision the LATEST UEK track each OL major ships
# (verified against yum.oracle.com repomd.xml, 2026-07-11) -- the track real
# AMIs from this pipeline actually run. BUG HISTORY: OL8 was hardcoded to
# ol8_UEKR6 while real OL8 AMIs run UEKR7 (5.15), so 145 matrix cells validated
# a kernel the AMIs do not ship; the divergence surfaced when the first real
# OL8 build targeted 5.15 (2026-07-11). These pins make any track change a
# conscious, test-visible decision (update them together with the installer
# and the SPEC B.9 track table when Oracle ships a new UEK track).
INST_ENA="${PROJ}/install-ena-driver.sh"
# The single-quoted '${BT_UEK_REPO_OVERRIDE:-...}' entries are deliberate:
# we are literally matching the installer's own source text, not expanding.
# shellcheck disable=SC2016
for want in 'bt_uek_repo="ol6_UEKR4"' \
            'bt_uek_repo="ol7_UEKR6"' \
            'bt_uek_repo="${BT_UEK_REPO_OVERRIDE:-ol8_UEKR7}"' \
            'bt_uek_repo="${BT_UEK_REPO_OVERRIDE:-ol9_UEKR8}"' \
            'bt_uek_repo="ol10_UEKR8"'; do
  if grep -Fq "${want}" "${INST_ENA}"; then
    t_pass "ena-track: installer pins ${want}"
  else
    t_fail "ena-track: installer pins ${want}"
  fi
done

# The update-gate probe's uekr_for() map must agree with the installer pins
# above (BUG HISTORY: OL8 diverged in BOTH places at once -- pin both).
MATRIX_RUNNER="${PROJ}/tests/ena/run-ena-buildtest-matrix.sh"
if grep -Fq '6) echo UEKR4 ;; 7) echo UEKR6 ;; 8) echo UEKR7 ;; 9|10) echo UEKR8' "${MATRIX_RUNNER}"; then
  t_pass "ena-track: update-gate uekr_for() map matches the installer tracks (OL8=UEKR7)"
else
  t_fail "ena-track: update-gate uekr_for() map matches the installer tracks (OL8=UEKR7)"
fi

# --- user pin (ENA_DRIVER_VERSION) wiring --------------------------------------
# The env-file user pin is the HIGHEST-priority identity source and must be
# passed into the guest on EVERY major (pinned-installer majors included), or
# the AMI name and the built module would drift.
assert_in "${WRAP}" 'ENA_USER_PIN=1' \
  "ena-userpin: load_env records an accepted user pin (ENA_USER_PIN=1)"
assert_in "${WRAP}" 'ENA_DRIVER_VERSION must be a concrete x\.y\.z version' \
  "ena-userpin: a non-x.y.z user pin dies with a pointed message"
assert_in "${WRAP}" '\[OLAWS-ENA02\] user pin ENA_DRIVER_VERSION=' \
  "ena-userpin: accepted user pin is logged under the [OLAWS-ENA02] marker"
assert_in "${WRAP}" '"\$\{ENA_USER_PIN\}" -eq 1 \|\|' \
  "ena-userpin: the guest hook passes the pinned version on every major when user-pinned"

t_done
