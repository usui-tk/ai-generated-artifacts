#!/usr/bin/env bash
#==============================================================================
# tests/t005_entitlementdetect.sh - L1 unit: 3-step entitlement detection
#
# Drives acq_detect_entitlement end-to-end with PATH-shadow mocks for the package
# manager, covering the three steps (secrets present -> trigger redhat.repo ->
# classify by the rhel-* prefix + kernel-devel resolution) and the decisive
# "lazy redhat.repo" gotcha: detection must trigger a metadata pass first, never
# judge by a bare grep before that (the design plan sec 3.4).
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
# shellcheck source=lib/mock.sh
. "${HERE}/lib/mock.sh"
LIB="${PROJ}/lib/acquire-rootfs.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# --- step 1 short-circuit: no secrets -> anonymous, no manager calls ----------
td="${WORK}/anon_nosecrets"; mkdir -p "${td}"
sd="${WORK}/anon_nosecrets_secrets"; mkdir -p "${sd}"   # exists but empty (no .pem)
out="$(
  (
    # shellcheck source=/dev/null
    . "${LIB}"
    mock_setup "${td}"
    mock_cmd dnf 'exit 0'   # would record if called
    acq_detect_entitlement dnf "${sd}"
  )
)"
assert_eq "anonymous" "${out}" "no secrets -> anonymous (step-1 short-circuit)"
assert_eq "" "$(cat "${td}/calls")" "no secrets -> manager never invoked (no premature trigger)"

# --- entitled host: secrets + rhel-* repos after trigger + kernel-devel -------
td="${WORK}/ent"; mkdir -p "${td}"
sd="${WORK}/ent_secrets"; mkdir -p "${sd}"; : > "${sd}/entitlement.pem"
out="$(
  (
    # shellcheck source=/dev/null
    . "${LIB}"
    mock_setup "${td}"
    # makecache trigger (records the metadata pass)
    mock_cmd dnf 'case "$*" in
        *makecache*) exit 0 ;;
        *repolist*)  printf "rhel-9-for-x86_64-baseos-rpms\nrhel-9-for-x86_64-appstream-rpms\n" ;;
        *"list --available kernel-devel"*) printf "kernel-devel.x86_64 5.14.0 @rhel-9-...-appstream\n"; exit 0 ;;
        *) exit 0 ;;
      esac'
    acq_detect_entitlement dnf "${sd}"
  )
)"
assert_eq "entitled" "${out}" "secrets + rhel-* repos + kernel-devel -> entitled"
calls="$(cat "${td}/calls")"
assert_match "${calls}" "^dnf -y makecache$" "entitled: step-2 trigger ran BEFORE classification"
assert_match "${calls}" "dnf repolist --enabled" "entitled: enabled-repo list queried"
assert_match "${calls}" "dnf list --available kernel-devel" "entitled: kernel-devel resolved via list --available"

# --- unregistered host: secrets bind-mounted but repos stay ubi-* -------------
# (e.g. a non-RHEL host that mounts the path but cannot actually entitle)
td="${WORK}/anon_ubi"; mkdir -p "${td}"
sd="${WORK}/anon_ubi_secrets"; mkdir -p "${sd}"; : > "${sd}/key.pem"
out="$(
  (
    # shellcheck source=/dev/null
    . "${LIB}"
    mock_setup "${td}"
    mock_cmd dnf 'case "$*" in
        *makecache*) exit 0 ;;
        *repolist*)  printf "ubi-9-baseos-rpms\nubi-9-appstream-rpms\n" ;;
        *"list --available kernel-devel"*) exit 1 ;;   # not resolvable anonymously
        *) exit 0 ;;
      esac'
    acq_detect_entitlement dnf "${sd}"
  )
)"
assert_eq "anonymous" "${out}" "secrets present but only ubi-* repos + no kernel-devel -> anonymous"

# --- yum host (RHEL 6/7 path): entitled via rhel-N-server-rpms ----------------
td="${WORK}/ent_yum"; mkdir -p "${td}"
sd="${WORK}/ent_yum_secrets"; mkdir -p "${sd}"; : > "${sd}/entitlement.pem"
out="$(
  (
    # shellcheck source=/dev/null
    . "${LIB}"
    mock_setup "${td}"
    mock_cmd yum 'case "$*" in
        *makecache*) exit 0 ;;
        *repolist*)  printf "repo id            status\nrhel-7-server-rpms   12,345\n" ;;
        *"list available kernel-devel"*) printf "kernel-devel.x86_64 3.10.0 rhel-7-server-rpms\n"; exit 0 ;;
        *) exit 0 ;;
      esac'
    acq_detect_entitlement yum "${sd}"
  )
)"
assert_eq "entitled" "${out}" "yum host: rhel-7-server-rpms + kernel-devel -> entitled"

t_done
