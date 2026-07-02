#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   Refresh ena-driver-releases.json: enumerate upstream releases into the pinned
#   in-scope version set the install/build-test matrix consumes.
# ----- Prerequisites --------------------------------------------------------
#   bash 4+, curl; network to the vendor endpoint (GitHub/AWS).
# ----- Usage examples -------------------------------------------------------
#   bash tests/aws_ena-driver/list-ena-releases.sh
#   bash tests/aws_ena-driver/list-ena-releases.sh --help
# ----- Known limitations ----------------------------------------------------
#   Network-dependent (L3); the committed JSON is the reproducible input.
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
#------------------------------------------------------------------------------
# list-ena-releases.sh - AWS ENA driver release-list collector (matrix input (a))
#
# Self-contained (no shared library). Collects the ENA Linux driver release list
# and emits a deterministic JSON snapshot that run-ena-buildtest-matrix.sh
# consumes.
#
# GROUND TRUTH: the tags "ena_linux_<X.Y.Z>" in
#   https://github.com/amzn/amzn-drivers
# read with `git ls-remote --tags` (auth-free). The driver source for a version
# lives at kernel/linux/ena/ in that repo at the matching tag; the buildtest
# compiles ena.ko out-of-tree against the installed kernel-devel headers
# (make -C /usr/src/kernels/<kver> M=<src> modules) - independent of the running
# host kernel, with all Oracle UEK handling removed (stock RHEL kernel only).
#
# AXIS: the ENA buildtest is gated by **entitlement** (kernel-devel + gcc + make
# come from the entitled repos; anonymous has no kernel-devel -> needs-entitlement)
# rather than glibc. A convenience MINIMUM VERSION marks the default in-scope
# window; --full (in the matrix) covers all. Computed locally by ena_ge() - a
# REUSE-BY-COPY of the matrix helper, kept identical, verified by t010_enaverdict.sh.
#
# DETERMINISTIC OUTPUT: no timestamp embedded.
#
# Usage:   bash tests/aws_ena-driver/list-ena-releases.sh [output.json]
#   env:   ENA_REPO_URL (default https://github.com/amzn/amzn-drivers.git)
#          ENA_MIN_VERSION (default 2.8.0; default in-scope window floor)
# Requires: git, grep, sed, sort. Network: github.com.
# Exit:    0 = wrote the JSON; non-zero = fetch/parse error (no partial file).
#------------------------------------------------------------------------------
set -euo pipefail

ENA_REPO_URL="${ENA_REPO_URL:-https://github.com/amzn/amzn-drivers.git}"
SOURCE_REPO="https://github.com/amzn/amzn-drivers"
ENA_MIN="${ENA_MIN_VERSION:-2.8.0}"
ENA_SRC_SUBDIR="kernel/linux/ena"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-${SCRIPT_DIR}/ena-driver-releases.json}"

log() { printf '%s [list-ena-releases] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

# ena_ge <a> <b> : 3-part dotted-numeric compare (REUSE-BY-COPY of the matrix
# helper; kept identical - verified by tests/t010_enaverdict.sh).
ena_ge() {
  local a="$1" b="$2" hi
  [ "${a}" = "${b}" ] && return 0
  hi="$(printf '%s\n%s\n' "${a}" "${b}" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
  [ "${hi}" = "${a}" ]
}

log "fetching ENA driver tags from ${ENA_REPO_URL} (git ls-remote --tags)"
versions="$(
  git ls-remote --tags "${ENA_REPO_URL}" 2>/dev/null \
    | sed -E 's#.*refs/tags/##; s/\^\{\}$//' \
    | grep -E '^ena_linux_[0-9]+\.[0-9]+\.[0-9]+$' \
    | sed -E 's/^ena_linux_//' \
    | sort -t. -k1,1n -k2,2n -k3,3n -u
)"
[ -n "${versions}" ] || { log "ERROR: no ena_linux_* version tags found (network down or scheme moved)"; exit 1; }
count="$(printf '%s\n' "${versions}" | grep -c .)"
log "found ${count} ENA versions; default in-scope floor ${ENA_MIN}"

TMP="$(mktemp)"; trap 'rm -f "${TMP}"' EXIT
{
  printf '{\n'
  printf '  "tool": "aws_ena-driver",\n'
  printf '  "source": "%s",\n' "${SOURCE_REPO}"
  printf '  "src_subdir": "%s",\n' "${ENA_SRC_SUBDIR}"
  printf '  "tag_template": "ena_linux_<ver>",\n'
  printf '  "min_version": "%s",\n' "${ENA_MIN}"
  printf '  "axis": "entitlement (kernel-devel + gcc + make); build is glibc-agnostic; load is always L4",\n'
  printf '  "count": %s,\n' "${count}"
  printf '  "versions": [\n'
  first=1
  while IFS= read -r v; do
    [ -n "${v}" ] || continue
    if ena_ge "${v}" "${ENA_MIN}"; then ge='true'; else ge='false'; fi
    [ "${first}" = "1" ] || printf ',\n'
    first=0
    printf '    {"version": "%s", "tag": "ena_linux_%s", "ge_min": %s}' "${v}" "${v}" "${ge}"
  done <<< "${versions}"
  printf '\n  ]\n}\n'
} > "${TMP}"

mv "${TMP}" "${OUT}"; trap - EXIT
log "wrote ${OUT} (${count} versions)"
