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
PROVISION_PKGS="${PROVISION_PKGS:-gawk}"

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
  # Install the common manifest onto the base image. Packages already present
  # are a fast no-op; missing ones come from the image's native repos (public
  # UBI for 7-10) or the entitled repos (rhel-6 via the passthrough).
  # shellcheck disable=SC2086,SC2016  # ent word-split is intentional; the -c body expands in-container
  if timeout "${PROVISION_TIMEOUT:-600}" podman run --name "${cname}" ${ent} \
       -e "PROVISION_PKGS=${PROVISION_PKGS}" -e "PROVISION_SETOPT=${setopt}" \
       "${base_ref}" /bin/bash -c '
         set -e
         mgr=""
         for m in dnf yum; do command -v "${m}" >/dev/null 2>&1 && { mgr="${m}"; break; }; done
         [ -n "${mgr}" ] || { echo "provision: no dnf/yum in base image" >&2; exit 3; }
         # shellcheck disable=SC2086
         "${mgr}" -y ${PROVISION_SETOPT} install ${PROVISION_PKGS}
       ' >/dev/null 2>"${errf}"; then
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
