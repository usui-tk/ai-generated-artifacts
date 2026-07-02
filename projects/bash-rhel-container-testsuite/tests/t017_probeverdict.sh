#!/usr/bin/env bash
#==============================================================================
# tests/t014_probeverdict.sh - L1 unit: probe-env.sh readiness classifier
#
# Loads ONLY the pure helper probe_verdict (extracted from its column-0 body) and
# checks the ready/degraded/blocked classification. No podman, no network.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
PROBE="${PROJ}/tests/probe-env.sh"

# shellcheck disable=SC1090
. <(sed -n "/^probe_verdict()/,/^}/p" "${PROBE}")

if ! declare -F probe_verdict >/dev/null 2>&1; then
  t_fail "could not load probe_verdict from probe-env.sh"
  t_done; exit
fi

# blocked: the image does not run here (exec != ok), regardless of the rest.
assert_eq "blocked"  "$(probe_verdict fail ok ok reachable)"        "exec fail -> blocked"
assert_eq "blocked"  "$(probe_verdict timeout ok ok reachable)"     "exec timeout -> blocked"

# ready: runs + both egress ok + yum not stalling.
assert_eq "ready"    "$(probe_verdict ok ok ok reachable)"    "all ok -> ready"
assert_eq "ready"    "$(probe_verdict ok ok ok unknown)"      "repos unknown (not no-access) still ready"
assert_eq "ready"    "$(probe_verdict ok ok ok no-cmd)"       "repos no-cmd (no pkgmgr) still ready"

# degraded: runs, but a common prerequisite is missing.
assert_eq "degraded" "$(probe_verdict ok fail ok reachable)"  "no S3 egress -> degraded"
assert_eq "degraded" "$(probe_verdict ok ok fail reachable)"  "no EPEL egress -> degraded"
assert_eq "degraded" "$(probe_verdict ok ok ok no-access)"    "repos no-access -> degraded"

t_done
