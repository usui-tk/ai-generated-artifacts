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
assert_eq "2.17.0" "${pin7}" "ena-report: pin reader resolves OL7 default (2.17.0) from the live installer"

t_done
