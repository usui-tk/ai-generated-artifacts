#!/usr/bin/env bash
#==============================================================================
# tests/t006_initmodemap.sh - L1 unit: init-mode invocation mapping
#
# The init-mode axis (env_init_mode = none | systemd) is realized purely by how a
# single ubi-init image is invoked (the design plan sec 5b): 'none' runs an
# explicit command (systemd not PID 1; install/binary tests), 'systemd' boots the
# image detached (its Cmd is /sbin/init) for service/unit tests. This tier pins
# that mapping table-driven, so a regression in the arg vector is caught here.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
# shellcheck source=/dev/null
. "${PROJ}/lib/acquire-rootfs.sh"

REF="registry.access.redhat.com/ubi8/ubi-init:latest"

# none mode: explicit command (init-agnostic) - the AWS CLI / binary-smoke shape
assert_eq "run --rm ${REF} aws --version" \
  "$(acq_init_run_args none "${REF}" aws --version)" \
  "none: passes the binary command through verbatim"
assert_eq "run --rm ${REF} amazon-ssm-agent -version" \
  "$(acq_init_run_args none "${REF}" amazon-ssm-agent -version)" \
  "none: SSM version smoke in none mode"
assert_eq "run --rm ${REF} /bin/bash -lc true" \
  "$(acq_init_run_args none "${REF}")" \
  "none: default no-op when no command is given"

# systemd mode: detached boot (then a separate podman exec runs systemctl)
assert_eq "run -d ${REF}" \
  "$(acq_init_run_args systemd "${REF}")" \
  "systemd: detached boot, no explicit command (image Cmd = /sbin/init)"

# 'systemd' must NOT carry an explicit command even if one is passed (the boot
# form is fixed; service interaction happens via a follow-up exec, not here)
assert_eq "run -d ${REF}" \
  "$(acq_init_run_args systemd "${REF}" systemctl status)" \
  "systemd: extra args are ignored - boot form is fixed"

# invalid mode -> rc 1
acq_init_run_args '' "${REF}" >/dev/null; assert_rc 1 "$?" "empty mode -> rc 1"
acq_init_run_args bogus "${REF}" >/dev/null; assert_rc 1 "$?" "unknown mode -> rc 1"

t_done
