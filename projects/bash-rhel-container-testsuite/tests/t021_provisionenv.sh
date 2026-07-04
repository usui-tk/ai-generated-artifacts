#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   L1 unit: lib/provision-test-env.sh (test-env provisioning helper)
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; hermetic (no network, no real podman - a PATH-mock stands in).
# ----- Usage examples -------------------------------------------------------
#   bash tests/t021_provisionenv.sh
#   bash tests/run-all.sh   # runs every tier
# ----- Known limitations ----------------------------------------------------
#   Asserts count failures and continue (harness scope, spec home A.5). Exercises
#   the helper's control flow via a mock podman; the real podman commit flow is
#   covered by the L3 matrices on an entitled host.
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Opus 4.8), claude.ai sessions
#   Generation date: 2026-07-03 (r33: test-env provisioning step)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/t021_provisionenv.sh - L1 unit: the per-OS test-env provisioning helper
# lib/provision-test-env.sh. A PATH-mock `podman` stands in for the real runtime
# so the tier is hermetic: it asserts the manifest-tag logic, the idempotent
# reuse of an existing image, a successful build+commit, and that a provisioning
# failure surfaces the real package-manager stderr (never a masked/guessed one).
#==============================================================================
# shellcheck disable=SC1090  # the lib under test is sourced via a runtime path (validated by t002)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"

LIB="${PROJ}/lib/provision-test-env.sh"
[ -f "${LIB}" ] || { t_fail "missing lib: ${LIB}"; t_done; exit; }

# --- the common manifest + tag logic (pure) ---------------------------------
def="$(. "${LIB}"; printf '%s' "${PROVISION_PKGS}")"
assert_eq "gawk" "${def}" "PROVISION_PKGS defaults to gawk (common per-OS manifest)"

tag_a="$(. "${LIB}"; PROVISION_PKGS='gawk'       provision_manifest_tag 6)"
tag_b="$(. "${LIB}"; PROVISION_PKGS='gawk'       provision_manifest_tag 6)"
tag_c="$(. "${LIB}"; PROVISION_PKGS='gawk unzip' provision_manifest_tag 6)"
tag_9="$(. "${LIB}"; PROVISION_PKGS='gawk'       provision_manifest_tag 9)"
assert_eq "${tag_a}" "${tag_b}" "provision_manifest_tag is deterministic for a given (major, manifest)"
assert_match "${tag_a}" 'rhel6-' "provision_manifest_tag embeds the OS major"
if [ "${tag_a}" != "${tag_c}" ]; then t_pass "manifest fingerprint changes when PROVISION_PKGS changes (auto-rebuild)"
else t_fail "manifest fingerprint changes when PROVISION_PKGS changes (auto-rebuild)"; fi
if [ "${tag_a}" != "${tag_9}" ]; then t_pass "tag differs per OS major"
else t_fail "tag differs per OS major"; fi

# --- build/idempotency/failure via a PATH-mock podman -----------------------
# The mock records its argv (MOCK_PODMAN_LOG) and is steered by env:
#   MOCK_IMG_EXISTS=1  -> `podman image exists` succeeds (image already built)
#   MOCK_RUN_RC=N      -> `podman run` exit code   MOCK_RUN_STDERR=... -> its stderr
#   MOCK_COMMIT_RC=N   -> `podman commit` exit code
#   MOCK_FAIL_MAJOR=N  -> fail the `podman run` for RHEL N's provisioning container
mockdir="$(mktemp -d)"
cat > "${mockdir}/podman" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "${MOCK_PODMAN_LOG:-/dev/null}"
case "$1" in
  image)  [ "${MOCK_IMG_EXISTS:-0}" = "1" ] && exit 0 || exit 1 ;;
  run)
    if [ -n "${MOCK_FAIL_MAJOR:-}" ] && printf '%s' "$*" | grep -q "provision-rhel${MOCK_FAIL_MAJOR}-"; then
      printf 'simulated repo failure\n' >&2; exit 1
    fi
    [ -n "${MOCK_RUN_STDERR:-}" ] && printf '%s\n' "${MOCK_RUN_STDERR}" >&2; exit "${MOCK_RUN_RC:-0}" ;;
  commit) exit "${MOCK_COMMIT_RC:-0}" ;;
  *)      exit 0 ;;
esac
MOCK
chmod +x "${mockdir}/podman"

# (1) build success: not-exists -> run ok -> commit ok -> echoes the tag
out="$(PATH="${mockdir}:${PATH}" MOCK_IMG_EXISTS=0 MOCK_RUN_RC=0 MOCK_COMMIT_RC=0 \
       bash -c '. "$1"; provision_test_image 6 base:img ""' _ "${LIB}")"; rc=$?
assert_eq 0 "${rc}" "provision_test_image returns 0 when run+commit succeed"
assert_match "${out}" 'rhel6-' "provision_test_image echoes the provisioned tag on success"

# (1a) r46 (D-S3) regression pin: the provisioning install must NOT hide repo
# failures behind *.skip_if_unavailable=1 (that setopt papered over the
# wrong-major host-file mounts removed by D-S1).
rlog="$(mktemp)"
PATH="${mockdir}:${PATH}" MOCK_PODMAN_LOG="${rlog}" MOCK_IMG_EXISTS=0 MOCK_RUN_RC=0 MOCK_COMMIT_RC=0 \
  bash -c '. "$1"; provision_test_image 8 base:img "" >/dev/null' _ "${LIB}"
case "$(cat "${rlog}")" in
  *skip_if_unavailable*) t_fail "provisioning must not mask repo failures (skip_if_unavailable found)" ;;
  *)                     t_pass "provisioning does not mask repo failures (no skip_if_unavailable)" ;;
esac
rm -f "${rlog}"

# (2) idempotent: image exists -> echoes tag, never runs/commits a container
ilog="$(mktemp)"
out2="$(PATH="${mockdir}:${PATH}" MOCK_PODMAN_LOG="${ilog}" MOCK_IMG_EXISTS=1 \
        bash -c '. "$1"; provision_test_image 6 base:img ""' _ "${LIB}")"
assert_match "${out2}" 'rhel6-' "provision_test_image reuses an existing image (idempotent)"
assert_eq 0 "$(grep -c '^run ' "${ilog}")" "idempotent path does not build a container (no podman run)"
assert_eq 0 "$(grep -c '^commit ' "${ilog}")" "idempotent path does not commit"
rm -f "${ilog}"

# (3) failure: run fails -> non-zero + PROVISION_LAST_ERR carries the real stderr
res="$(PATH="${mockdir}:${PATH}" MOCK_IMG_EXISTS=0 MOCK_RUN_RC=3 MOCK_RUN_STDERR='REPO_METADATA_BOOM' \
       bash -c '. "$1"; provision_test_image 6 base:img "" || printf "RC=%s ERR=%s" "$?" "${PROVISION_LAST_ERR}"' _ "${LIB}")"
assert_match "${res}" 'RC=1' "provision_test_image returns non-zero when provisioning fails"
assert_match "${res}" 'REPO_METADATA_BOOM' "provision failure surfaces the real pm stderr via PROVISION_LAST_ERR"

# --- Part B: provision_prepare_majors (PRE-FLIGHT; fail-fast; EL6 exception) --
# acq_ref_for_major is stubbed; the mock builds every image unless MOCK_FAIL_MAJOR.
# shellcheck disable=SC2016  # $1 must stay literal here; it expands in the inner bash -c
PREP='acq_ref_for_major() { printf "base:rhel%s" "$1"; }; . "$1";'

# (B1) all majors prepare -> rc 0, every major recorded in the map
m1="$(mktemp)"
PATH="${mockdir}:${PATH}" MOCK_IMG_EXISTS=0 MOCK_RUN_RC=0 MOCK_COMMIT_RC=0 \
  bash -c "${PREP} provision_prepare_majors '10 9 8 7 6' '' '${m1}'" _ "${LIB}"; rcb=$?
assert_eq 0 "${rcb}" "provision_prepare_majors returns 0 when all majors prepare"
assert_eq 5 "$(grep -c . "${m1}")" "all 5 majors recorded in the prep map"
rm -f "${m1}"

# (B2) a NON-optional major (8) cannot be prepared -> FAIL-FAST (abort the run)
m2="$(mktemp)"
PATH="${mockdir}:${PATH}" MOCK_IMG_EXISTS=0 MOCK_FAIL_MAJOR=8 \
  bash -c "${PREP} provision_prepare_majors '10 9 8 7 6' '' '${m2}'" _ "${LIB}"; rcb=$?
assert_eq 2 "${rcb}" "a non-optional major that cannot be prepared aborts (fail-fast)"
rm -f "${m2}"

# (B3) EL6 (optional) cannot be prepared -> NOT fatal: rc 0, run continues, 6 absent
m3="$(mktemp)"
PATH="${mockdir}:${PATH}" MOCK_IMG_EXISTS=0 MOCK_FAIL_MAJOR=6 \
  bash -c "${PREP} provision_prepare_majors '10 9 8 7 6' '' '${m3}'" _ "${LIB}"; rcb=$?
assert_eq 0 "${rcb}" "EL6 failing to prepare is tolerated (run continues to testing)"
assert_eq 4 "$(grep -c . "${m3}")" "the 4 non-EL6 majors are prepared without EL6"
assert_eq 0 "$(grep -c '^6 ' "${m3}")" "EL6 is absent from the prep map (no tests run for it)"
rm -f "${m3}"

rm -rf "${mockdir}"

t_done
