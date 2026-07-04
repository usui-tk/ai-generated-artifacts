# ----- Purpose --------------------------------------------------------------
#   Provision a per-OS "test-ready" container image: take the vendor base image
#   (UBI / rhel6-rhel) and install a COMMON package manifest onto it, committing
#   the result once per OS major. This mirrors the Oracle-Linux sibling's
#   clean-core approach (build a curated image first, then run tests on it)
#   instead of assuming the vendor image already carries everything a test needs.
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; podman; sourced library (no side effects at source time).
# ----- Usage examples -------------------------------------------------------
#   source lib/provision-test-env.sh   # from a matrix runner / test tier
#   ref="$(provision_test_image 6 "${base_ref}" "${ent_mounts}")" || skip
# ----- Known limitations ----------------------------------------------------
#   Not a standalone executable; the caller handles logging + error policy
#   (spec home A.5). Installing the manifest needs a reachable repo for any
#   package the base image lacks (public UBI repos for RHEL 7-10; the entitled
#   rhel-6 repos, via the entitlement passthrough, for RHEL 6).
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Opus 4.8), claude.ai sessions
#   Generation date: 2026-07-03 (r33: test-env provisioning step)
# ---------------------------------------------------------------------------
# shellcheck shell=bash
# shellcheck disable=SC2034  # PROVISION_LAST_ERR is a public contract var read by callers
#==============================================================================
# lib/provision-test-env.sh - build a per-OS "test-ready" image (base + common
# package manifest), the RHEL analogue of the OL clean-core builder.
#
# WHY. The vendor base images are deliberately minimal. Notably the RHEL 6
# base (registry.access.redhat.com/rhel6/rhel) and other slim images ship
# WITHOUT awk (gawk); the amazon-ssm-agent rpm's %pretrans kernel-version guard
# calls awk, so on a base image lacking it the guard dies and the whole install
# fails - a test-ENVIRONMENT gap, not a defect in the production installer. The
# fix belongs in the harness, not in install-aws_*.sh: prepare the environment
# BEFORE the test, exactly like the OL clean-core pipeline.
#
# WHAT. One COMMON image per OS major (not one per test): base + PROVISION_PKGS,
# committed to a local tag. Every matrix (SSM / ENA / awscli) resolves its base
# ref, then swaps in the provisioned ref and runs its sweep against that. Built
# once and reused (idempotent by a tag that embeds the manifest fingerprint, so
# changing PROVISION_PKGS rebuilds automatically).
#==============================================================================

# COMMON per-OS test-env package manifest - the shared "clean-core essentials"
# the vendor base images may lack and that the test cases assume are present.
# Kept COMMON across all tests: we build ONE provisioned image per OS, not one
# per test. Extend this list (space-separated) as tests reveal new needs.
#   gawk : provides `awk`, required by the amazon-ssm-agent rpm %pretrans kernel
#          guard; absent from the minimal RHEL 6 (rhel6/rhel) base image.
# r48: unzip + tar joined the manifest after the 2026-07-04 smoke E2E - the
# awscli install needs unzip (its failure on every major traced to exactly
# this gap; the image tag embeds the manifest fingerprint, so this change
# auto-rebuilds stale images), and tar defensively covers source unpacking.
PROVISION_PKGS="${PROVISION_PKGS:-gawk unzip tar}"

# Majors whose provisioning failure is TOLERATED (skipped, not fatal) in the
# pre-flight (provision_prepare_majors). RHEL 6 (rhel6/rhel) is non-UBI and has
# no public repos; the host's redhat.repo cannot supply rhel-6 content, so EL6
# needs its own rhel-6 entitlement path (tracked separately). Every OTHER major
# that cannot be prepared is a missing test prerequisite -> the run aborts.
PROVISION_OPTIONAL_MAJORS="${PROVISION_OPTIONAL_MAJORS:-6}"

# Local image namespace for the committed test-ready images.
PROVISION_IMG_PREFIX="${PROVISION_IMG_PREFIX:-localhost/rhel-testsuite-provisioned}"

# Set by provision_test_image on failure: the last ~200 chars of the provisioning
# package-manager stderr, for the caller to include in its skip reason.
PROVISION_LAST_ERR=""

# provision_manifest_tag <major> : the deterministic tag for this OS major and
# manifest. Embeds a short fingerprint of PROVISION_PKGS so that changing the
# manifest yields a new tag (auto-rebuild) rather than reusing a stale image.
provision_manifest_tag() {
  local major="$1" fp
  fp="$(printf '%s' "${PROVISION_PKGS}" | cksum | cut -d' ' -f1)"
  printf '%s:rhel%s-%s' "${PROVISION_IMG_PREFIX}" "${major}" "${fp}"
}

# provision_cleanup_images : remove every provisioned test-env image
# (${PROVISION_IMG_PREFIX}:*), keeping base images (UBI/RHEL) untouched.
# r48, user requirement: wired via `trap ... EXIT` in the matrix sweeps and
# --smoke so normal completion, failures and interrupts ALL clean up.
# KEEP_TEST_IMAGES=1 opts out (debugging / faster reruns).
provision_cleanup_images() {
  [ "${KEEP_TEST_IMAGES:-0}" = "1" ] && { provision_log "KEEP_TEST_IMAGES=1 - provisioned test-env images kept"; return 0; }
  command -v podman >/dev/null 2>&1 || return 0
  local imgs
  imgs="$(podman images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep "^${PROVISION_IMG_PREFIX}:" || true)"
  [ -n "${imgs}" ] || return 0
  provision_log "cleanup: removing provisioned test-env images (KEEP_TEST_IMAGES=1 keeps them)"
  # shellcheck disable=SC2086  # one image ref per word by construction
  podman rmi -f ${imgs} >/dev/null 2>&1 || true
}

# provision_test_image <major> <base_ref> [ent_mounts] : ensure a per-OS
# test-ready image (base + PROVISION_PKGS) exists and echo its tag. Built ONCE
# via `podman run <base> + install + podman commit`; idempotent (reuse the tag if
# present). On failure echo nothing, set PROVISION_LAST_ERR, and return non-zero
# so the caller can skip the major with a reason. INSECURE_TLS=1 disables the pm
# TLS verification (dev proxy). ent_mounts is the acq_entitlement_mount_args
# string (word-split into podman -v/--network args).
provision_test_image() {
  local major="$1" base_ref="$2" ent="${3:-}" tag cname setopt errf rc=0
  PROVISION_LAST_ERR=""
  tag="$(provision_manifest_tag "${major}")"
  if podman image exists "${tag}" 2>/dev/null; then
    printf '%s' "${tag}"; return 0
  fi
  setopt=""
  [ "${INSECURE_TLS:-0}" = "1" ] && setopt="--setopt=sslverify=0"
  cname="provision-rhel${major}-$$"
  podman rm -f "${cname}" >/dev/null 2>&1 || true
  errf="$(mktemp)"
  # Install the common manifest onto the base image, ROBUST to the repo-access
  # mode (anonymous UBI / RHSM-entitled). One measure, mirroring the install
  # scripts' convention:
  #  1. neutralize the subscription-manager/product-id plugins when NO
  #     entitlement certs are present (anonymous) - a DEFENSIVE measure kept
  #     by decision D-S4: the historically observed RHSM-contact hang did NOT
  #     reproduce in the 2026-07-04 probe runs (sandbox and AWS, EL6 included),
  #     but disabling the plugins in a certless container is harmless and
  #     guards unknown environments. With certs present (RHSM auto-injection)
  #     the plugins stay ON - they generate the per-major entitled redhat.repo.
  #  (r36's *.skip_if_unavailable=1 was removed in r46, D-S3: it papered over
  #   the wrong-major HOST-file mounts removed by D-S1, and would now only
  #   hide real repo failures.)
  #  Combined stdout+stderr is captured so a real failure surfaces the pm error.
  # shellcheck disable=SC2086,SC2016  # ent word-split is intentional; the -c body expands in-container
  if timeout "${PROVISION_TIMEOUT:-600}" podman run --name "${cname}" ${ent} \
       -e "PROVISION_PKGS=${PROVISION_PKGS}" -e "PROVISION_SETOPT=${setopt}" \
       "${base_ref}" /bin/bash -c '
         set -e
         entitlement_certs_present() {
           ls /etc/pki/entitlement/*.pem >/dev/null 2>&1 \
             || ls /run/secrets/etc-pki-entitlement/*.pem >/dev/null 2>&1
         }
         if ! entitlement_certs_present; then
           for d in /etc/yum/pluginconf.d /etc/dnf/plugins; do
             [ -d "$d" ] || continue
             for p in subscription-manager product-id; do
               printf "[main]\nenabled=0\n" > "$d/$p.conf" 2>/dev/null || true
             done
           done
         fi
         mgr=""
         for m in dnf yum; do command -v "$m" >/dev/null 2>&1 && { mgr="$m"; break; }; done
         [ -n "$mgr" ] || { echo "provision: no dnf/yum in base image" >&2; exit 3; }
         # shellcheck disable=SC2086
         "$mgr" -y $PROVISION_SETOPT install $PROVISION_PKGS
       ' >"${errf}" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  if [ "${rc}" -ne 0 ]; then
    PROVISION_LAST_ERR="$(tr '\n' ' ' < "${errf}" | sed 's/  */ /g; s/^ *//; s/ *$//' | tail -c 200)"
    rm -f "${errf}"; podman rm -f "${cname}" >/dev/null 2>&1 || true
    return 1
  fi
  rm -f "${errf}"
  if ! podman commit "${cname}" "${tag}" >/dev/null 2>&1; then
    PROVISION_LAST_ERR="podman commit failed for ${tag}"
    podman rm -f "${cname}" >/dev/null 2>&1 || true
    return 1
  fi
  podman rm -f "${cname}" >/dev/null 2>&1 || true
  printf '%s' "${tag}"
  return 0
}

# provision_log <msg...> : log via the caller's log() when present (matrix banner),
# else a plain stderr line (keeps this lib usable stand-alone / in hermetic tests).
provision_log() {
  if declare -F log >/dev/null 2>&1; then log "$@"; else printf '%s\n' "$*" >&2; fi
}

# provision_prepare_majors <majors> <ent_mounts> <out_map> : PRE-FLIGHT. Prepare a
# test-ready image for EVERY requested major BEFORE any test runs, and write
# "<major> <ref>" lines for the successfully prepared majors to <out_map>.
#
# Policy: a test-env image that cannot be created means the test PREREQUISITE is
# not met. For such a major the function FAILS FAST (returns non-zero) so the
# caller aborts the whole run WITHOUT executing any test - EXCEPT majors listed
# in PROVISION_OPTIONAL_MAJORS (RHEL 6 by default), which are permitted to be
# unprovisionable: they are skipped (no map entry, hence no tests) and the run
# continues for the rest. Relies on acq_ref_for_major + provision_test_image
# being in scope (both sourced by the matrices alongside this lib).
provision_prepare_majors() {
  local majors="$1" ent="${2:-}" out_map="$3" major ref optional
  : > "${out_map}"
  for major in ${majors}; do
    optional=no
    case " ${PROVISION_OPTIONAL_MAJORS} " in *" ${major} "*) optional=yes ;; esac
    if ! ref="$(acq_ref_for_major "${major}")"; then
      if [ "${optional}" = "yes" ]; then
        provision_log "skip RHEL${major}: base image unavailable (optional major) - continuing without it"
        continue
      fi
      provision_log "ABORT: RHEL${major} base image unavailable - test prerequisite not met"
      return 2
    fi
    if ! ref="$(provision_test_image "${major}" "${ref}" "${ent}")"; then
      if [ "${optional}" = "yes" ]; then
        provision_log "skip RHEL${major}: test-env image not created${PROVISION_LAST_ERR:+ (${PROVISION_LAST_ERR})} - optional major; continuing without it (no tests run for RHEL${major})"
        continue
      fi
      provision_log "ABORT: RHEL${major} test-env image could not be created - test prerequisite not met${PROVISION_LAST_ERR:+: ${PROVISION_LAST_ERR}}"
      return 2
    fi
    printf '%s %s\n' "${major}" "${ref}" >> "${out_map}"
    provision_log "RHEL${major}: test-ready image ${ref}"
  done
  return 0
}
