#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   L1 unit: kdevel_kver() rpm stdout-pollution regression guard
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; hermetic (no network, no real rpm/find); shellcheck only for t002.
# ----- Usage examples -------------------------------------------------------
#   bash tests/t024_kdevelkver.sh
#   bash tests/run-all.sh   # runs every tier
# ----- Known limitations ----------------------------------------------------
#   The "rpm NVR has a matching /usr/src/kernels tree" happy path cannot be
#   asserted hermetically (it would require creating directories under the
#   real /usr/src/kernels) - it is covered by the podman FT instead. Fake
#   NVRs below use a -t024 marker so the [ -d ] ground-truth check is
#   deterministically false on any host.
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-06 (r67)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/t024_kdevelkver.sh - L1 unit: kdevel_kver() regression guard
#
# Loads ONLY kdevel_kver (extracted from install-aws_ena-driver.sh) with rpm
# and find stubbed as shell functions. Pins the r67 hardening:
#   - `rpm -q <missing>` prints "package ... is not installed" on STDOUT with
#     rc != 0; the pre-r67 pipeline captured that message as the kver, so the
#     directory fallback never ran and garbage leaked into the [result] kver
#     field (observed in the 2026-07-06 E2E FT).
#   - the rpmdb answer is validated against /usr/src/kernels/<kver> (the tree
#     the build actually uses); on mismatch the directory scan wins - robust
#     however kernel-devel arrived (RHSM repo, RHUI repo, pre-baked image).
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
ENA="${PROJ}/install-aws_ena-driver.sh"

# Load just the function under test.
# shellcheck disable=SC1090
. <(awk '/^kdevel_kver\(\)/{p=1} p{print} p&&/^\}/{exit}' "${ENA}")

if ! declare -F kdevel_kver >/dev/null 2>&1; then
  t_fail "could not load kdevel_kver from install-aws_ena-driver.sh"
  t_done; exit
fi

# --- stubs -------------------------------------------------------------------
# Shell functions shadow the real binaries inside this test shell only.
RPM_MODE="missing"   # missing | present | multi | absent
FIND_OUT=""          # what the fake directory scan reports
rpm() {
  case "${RPM_MODE}" in
    missing) printf 'package kernel-devel is not installed\n'; return 1 ;;
    present) printf '9.9.9-r67a.t024.x86_64\n'; return 0 ;;
    multi)   printf '9.9.1-r67b.t024.x86_64\n9.9.10-r67c.t024.x86_64\n'; return 0 ;;
    absent)  return 127 ;;
  esac
}
find() {
  if [ -n "${FIND_OUT}" ]; then printf '%s\n' "${FIND_OUT}"; fi
  return 0
}

# --- REGRESSION GUARD (r67): "not installed" stdout must NOT become the kver -
RPM_MODE="missing"; FIND_OUT=""
out="$(kdevel_kver)"
assert_eq "" "${out}" "rpm 'not installed' message + no trees -> empty kver (pre-r67: garbage text)"

# --- pollution + directory fallback -------------------------------------------
RPM_MODE="missing"; FIND_OUT="4.18.0-r67d.t024.x86_64"
out="$(kdevel_kver)"
assert_eq "4.18.0-r67d.t024.x86_64" "${out}" "rpm 'not installed' -> directory scan fallback wins"

# --- rpm missing entirely (rc 127) --------------------------------------------
RPM_MODE="absent"; FIND_OUT="5.14.0-r67e.t024.x86_64"
out="$(kdevel_kver)"
assert_eq "5.14.0-r67e.t024.x86_64" "${out}" "no rpm binary -> directory scan fallback wins"

# --- rpmdb NVR without a matching build tree -> ground-truth fallback ----------
# The fake NVR is guaranteed absent from the real /usr/src/kernels, so the
# [ -d ] validation deterministically rejects it on any host.
RPM_MODE="present"; FIND_OUT="5.14.0-r67f.t024.x86_64"
out="$(kdevel_kver)"
assert_eq "5.14.0-r67f.t024.x86_64" "${out}" "rpmdb NVR without /usr/src/kernels tree -> directory scan wins"

# --- multi-version rpmdb: newest NVR is the validation candidate ---------------
# sort -V must pick 9.9.10 over 9.9.1 (string sort would pick 9.9.1); both
# lack a real tree, so the observable outcome is still the fallback - the
# case pins that a multi-line rpmdb answer does not break the helper.
RPM_MODE="multi"; FIND_OUT="6.12.0-r67g.t024.x86_64"
out="$(kdevel_kver)"
assert_eq "6.12.0-r67g.t024.x86_64" "${out}" "multi-version rpmdb answer -> helper stays well-formed, fallback wins"

# --- nothing anywhere -----------------------------------------------------------
RPM_MODE="absent"; FIND_OUT=""
out="$(kdevel_kver)"
assert_eq "" "${out}" "no rpm, no trees -> empty kver (caller's return-2 guard fires)"

t_done
