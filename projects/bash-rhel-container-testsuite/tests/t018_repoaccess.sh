#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   L1 unit: repo-access classifier + feasibility
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; hermetic (no network); shellcheck only for t002.
# ----- Usage examples -------------------------------------------------------
#   bash tests/t018_repoaccess.sh
#   bash tests/run-all.sh   # runs every tier
# ----- Known limitations ----------------------------------------------------
#   Asserts count failures and continue (harness scope, spec home A.5).
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/t018_repoaccess.sh - L1 unit: repo-access classifier + feasibility
#
# Loads ONLY the pure helpers (extracted from their column-0 bodies) and checks
# the rhsm/rhui/oci-ol/none classification and the entitled-passthrough
# feasibility mapping. No host probing, no podman, no network.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
LIB="${PROJ}/lib/acquire-rootfs.sh"

# shellcheck disable=SC1090
. <(sed -n "/^acq_classify_repo_access()/,/^}/p" "${LIB}")
# shellcheck disable=SC1090
. <(sed -n "/^acq_entitlement_feasible()/,/^}/p" "${LIB}")

if ! declare -F acq_classify_repo_access >/dev/null 2>&1 \
   || ! declare -F acq_entitlement_feasible >/dev/null 2>&1; then
  t_fail "could not load classifier/feasibility from acquire-rootfs.sh"
  t_done; exit
fi

# --- acq_classify_repo_access HAS_RHSM RHUI_PROVIDER IS_OCI_OL ---------------
# rhsm wins over everything (BYOS/registered is authoritative).
assert_eq "rhsm"       "$(acq_classify_repo_access yes aws  no)"  "rhsm beats rhui"
assert_eq "rhsm"       "$(acq_classify_repo_access yes ''   yes)" "rhsm beats oci-ol"
# rhui:<provider> when no rhsm.
assert_eq "rhui:aws"   "$(acq_classify_repo_access no  aws   no)" "aws rhui"
assert_eq "rhui:azure" "$(acq_classify_repo_access no  azure no)" "azure rhui"
assert_eq "rhui:gcp"   "$(acq_classify_repo_access no  gcp   no)" "gcp rhui"
assert_eq "rhui:other" "$(acq_classify_repo_access no  other no)" "generic rhui"
# oci-ol only when no rhsm and no rhui provider.
assert_eq "oci-ol"     "$(acq_classify_repo_access no  ''    yes)" "oci oracle-linux yum"
assert_eq "rhui:aws"   "$(acq_classify_repo_access no  aws   yes)" "rhui beats oci-ol"
# none when nothing detected.
assert_eq "none"       "$(acq_classify_repo_access no  ''    no)"  "anonymous"

# --- acq_entitlement_feasible MODE ------------------------------------------
assert_eq "feasible"    "$(acq_entitlement_feasible rhsm)"       "rhsm feasible"
assert_eq "conditional" "$(acq_entitlement_feasible rhui:aws)"   "rhui aws conditional"
assert_eq "conditional" "$(acq_entitlement_feasible rhui:other)" "rhui other conditional"
assert_eq "na"          "$(acq_entitlement_feasible oci-ol)"     "oci-ol na"
assert_eq "na"          "$(acq_entitlement_feasible none)"       "none na"

t_done
