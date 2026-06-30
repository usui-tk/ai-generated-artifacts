#!/usr/bin/env bash
#==============================================================================
# tests/t015_installpins.sh - L1 unit: per-OS-major version pins in the root
# install scripts (r08).
#
# Each install-aws_<tool>.sh pins the version the test matrix validated for each
# RHEL major, used as the production default (an explicit <TOOL>_VERSION, which
# the matrix passes in test mode, overrides it). This tier sources each script
# with <TOOL>_LIB_ONLY=1 (defines the helpers + pins, installs nothing), overrides
# os_major per major, and asserts resolve_version picks the right pin - so a
# dropped or wrong pin fails the suite.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"

# resolve_pin <script> <lib_only_var> <version_var> <major> [explicit]
# Sources the install script lib-only in a subshell, fakes os_major=<major>,
# optionally pre-sets the explicit version, runs resolve_version, echoes the
# resolved version. Subshell isolates each tool's globals/functions.
resolve_pin() {
  # shellcheck disable=SC2034  # explicit + major are consumed via eval / the
  # overridden os_major, which ShellCheck cannot see
  local script="$1" libvar="$2" vervar="$3" major="$4" explicit="${5:-}"
  ( export "${libvar}=1"
    # shellcheck disable=SC1090
    . "${script}"
    eval "${vervar}=\"\${explicit}\""
    # shellcheck disable=SC2317  # called indirectly by resolve_version
    os_major() { printf '%s' "${major}"; }
    resolve_version
    eval "printf '%s' \"\${${vervar}}\""
  )
}

AWSCLI="${PROJ}/install-aws_awscli-v2.sh"
SSM="${PROJ}/install-aws_ssm-agent.sh"
ENA="${PROJ}/install-aws_ena-driver.sh"

for s in "${AWSCLI}" "${SSM}" "${ENA}"; do
  [ -f "${s}" ] || { t_fail "missing install script: ${s}"; t_done; exit; }
done

# --- AWS CLI v2: RHEL 6 below the glibc-2.17 floor; 7-10 latest --------------
assert_eq "2.17.49" "$(resolve_pin "${AWSCLI}" AWSCLI_LIB_ONLY AWSCLI_VERSION 6)"  "awscli RHEL6 -> 2.17.49 (glibc 2.12 < 2.17 floor)"
assert_eq "latest"  "$(resolve_pin "${AWSCLI}" AWSCLI_LIB_ONLY AWSCLI_VERSION 7)"  "awscli RHEL7 -> latest"
assert_eq "latest"  "$(resolve_pin "${AWSCLI}" AWSCLI_LIB_ONLY AWSCLI_VERSION 8)"  "awscli RHEL8 -> latest"
assert_eq "latest"  "$(resolve_pin "${AWSCLI}" AWSCLI_LIB_ONLY AWSCLI_VERSION 9)"  "awscli RHEL9 -> latest"
assert_eq "latest"  "$(resolve_pin "${AWSCLI}" AWSCLI_LIB_ONLY AWSCLI_VERSION 10)" "awscli RHEL10 -> latest"
assert_eq "2.20.0"  "$(resolve_pin "${AWSCLI}" AWSCLI_LIB_ONLY AWSCLI_VERSION 6 2.20.0)" "awscli explicit version overrides the pin"

# --- SSM: RHEL 6 pinned to the compliance floor; 7-10 latest ----------------
assert_eq "3.3.3598.0" "$(resolve_pin "${SSM}" SSM_LIB_ONLY SSM_VERSION 6)"  "ssm RHEL6 -> 3.3.3598.0 (compliance floor)"
assert_eq "latest"     "$(resolve_pin "${SSM}" SSM_LIB_ONLY SSM_VERSION 8)"  "ssm RHEL8 -> latest"
assert_eq "latest"     "$(resolve_pin "${SSM}" SSM_LIB_ONLY SSM_VERSION 10)" "ssm RHEL10 -> latest"
assert_eq "3.3.4001.0" "$(resolve_pin "${SSM}" SSM_LIB_ONLY SSM_VERSION 6 3.3.4001.0)" "ssm explicit version overrides the pin"

# --- ENA: RHEL 6 older buildable driver; 7-10 current 2.17.0 ----------------
assert_eq "2.9.1"  "$(resolve_pin "${ENA}" ENA_LIB_ONLY ENA_VERSION 6)"  "ena RHEL6 -> 2.9.1 (old EL6 kernel/toolchain)"
assert_eq "2.17.0" "$(resolve_pin "${ENA}" ENA_LIB_ONLY ENA_VERSION 7)"  "ena RHEL7 -> 2.17.0"
assert_eq "2.17.0" "$(resolve_pin "${ENA}" ENA_LIB_ONLY ENA_VERSION 8)"  "ena RHEL8 -> 2.17.0"
assert_eq "2.17.0" "$(resolve_pin "${ENA}" ENA_LIB_ONLY ENA_VERSION 9)"  "ena RHEL9 -> 2.17.0"
assert_eq "2.17.0" "$(resolve_pin "${ENA}" ENA_LIB_ONLY ENA_VERSION 10)" "ena RHEL10 -> 2.17.0"
assert_eq "2.13.0" "$(resolve_pin "${ENA}" ENA_LIB_ONLY ENA_VERSION 6 2.13.0)" "ena explicit version overrides the pin"

# --- the AWS CLI RHEL6 pin is the last build below the v2 glibc-2.17 floor ----
# (2.17.50+ require glibc 2.17 > RHEL6's 2.12; 2.17.49 needs only 2.5)
# shellcheck disable=SC1090
v6="$( ( export AWSCLI_LIB_ONLY=1; . "${AWSCLI}"; printf '%s' "${AWSCLI_VERSION_RHEL6}" ) )"
assert_eq "2.17.49" "${v6}" "awscli RHEL6 pin is 2.17.49 (last build below the v2 glibc-2.17 floor)"

t_done
