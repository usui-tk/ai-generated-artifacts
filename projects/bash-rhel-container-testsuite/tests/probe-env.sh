#!/usr/bin/env bash
#==============================================================================
# tests/probe-env.sh - opt-in environment probe (--probe-env)
#
# Probes ALL FIVE RHEL majors with a common set of checks and reports whether
# the host + container runtime can actually exercise each target, BEFORE a full
# --run. This exists because the assumed execution environment differs per major
# (notably RHEL 6, which is a bare non-UBI image on an EOL/ELS-ended distro), and
# a stalled or unrunnable target is far cheaper to discover here than mid-sweep.
#
# Common checks (identical across majors - no per-major special items):
#   exec         - does the image run at all here? (/bin/true; covers pull, arch,
#                  and the glibc/vsyscall compatibility of old userspace)
#   pkgmgr       - dnf|yum|none detected inside the image
#   yum_ok       - does `<mgr> --disableplugin=subscription-manager,product-id
#                  repolist` complete promptly (bounded by PKG_TIMEOUT)? i.e. the
#                  RHSM plugin stall is not present
#   egress_s3    - reach the SSM RPM host (s3.amazonaws.com)
#   egress_epel  - reach the EPEL host (dl.fedoraproject.org)
#   entitlement  - anonymous|entitled, from host-side entitlement-cert presence
#   verdict      - ready | degraded | blocked (pure classifier: probe_verdict)
#
# Output: a run-log banner, a readiness table, and ENV-PROBE.json (host + probes).
# L3 (needs podman + egress). The host is NEVER modified. Timeouts:
#   RUN_TIMEOUT (whole probe container, default 600s), PKG_TIMEOUT (in-container
#   yum/dnf, default 300s) - both overridable.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=../lib/acquire-rootfs.sh
. "${PROJ}/lib/acquire-rootfs.sh"

OUT_JSON="${HERE}/ENV-PROBE.json"
MAJORS="${OSMAJORS:-10 9 8 7 6}"

log() { printf '%s [probe-env] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

# probe_verdict EXEC S3 EPEL YUMOK : pure readiness classifier (unit-tested).
#   blocked  - the image will not even run here (exec != ok)
#   degraded - runs, but a common prerequisite a --run relies on is missing
#              (no S3 or EPEL egress, or yum still stalls)
#   ready    - runs and every common prerequisite holds
probe_verdict() {
  local exec_ok="$1" s3="$2" epel="$3" yumok="$4"
  [ "${exec_ok}" = "ok" ] || { printf 'blocked'; return 0; }
  if [ "${s3}" != "ok" ] || [ "${epel}" != "ok" ] || [ "${yumok}" = "no" ]; then
    printf 'degraded'; return 0
  fi
  printf 'ready'
}

# probe_field OUT KEY : pull KEY=... from the captured probe stdout.
probe_field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }

# probe_one MAJOR : run the common probe in one short-lived container, print a
# JSON object for that major. Bounded by RUN_TIMEOUT; the in-container yum step is
# bounded by PKG_TIMEOUT (passed in as an env var).
probe_one() {
  local major="$1" host_mode="${2:-none}" ref out rc=0 exec_ok arch redhat pkgmgr yumok s3 epel ent verdict
  ref="$(acq_ref_for_major "${major}")" || { printf '{"major":"%s","error":"no image ref"}' "${major}"; return 0; }
  # shellcheck disable=SC2016  # $mgr/$m expand inside the container's /bin/sh, not here
  out="$(timeout "${RUN_TIMEOUT:-600}" podman run --rm \
          -e "PKG_TIMEOUT=${PKG_TIMEOUT:-300}" \
          "${ref}" /bin/sh -c '
            echo "EXEC=ok"
            echo "ARCH=$(uname -m 2>/dev/null)"
            echo "REDHAT=$(cat /etc/redhat-release 2>/dev/null | head -1)"
            mgr=""; for m in dnf yum; do command -v "$m" >/dev/null 2>&1 && { mgr="$m"; break; }; done
            echo "PKGMGR=${mgr:-none}"
            if [ -n "$mgr" ]; then
              if timeout "${PKG_TIMEOUT:-300}" "$mgr" --disableplugin=subscription-manager,product-id repolist >/dev/null 2>&1; then
                echo "YUMOK=yes"; else echo "YUMOK=no"; fi
            else echo "YUMOK=na"; fi
            # NOTE: --retry/--retry-delay only. --retry-connrefused needs curl
            # >= 7.52; RHEL 6/7 ship curl 7.19/7.29 and would abort on it.
            if command -v curl >/dev/null 2>&1; then
              curl -fsS --retry 2 --retry-delay 1 --max-time 20 -o /dev/null https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm 2>/dev/null && echo "S3=ok" || echo "S3=fail"
              curl -fsS --retry 2 --retry-delay 1 --max-time 20 -o /dev/null https://dl.fedoraproject.org/pub/epel/ 2>/dev/null && echo "EPEL=ok" || echo "EPEL=fail"
            else echo "S3=unknown"; echo "EPEL=unknown"; fi
          ' 2>/dev/null)" || rc=$?
  ent="${host_mode}"
  if [ "${rc}" = "124" ]; then
    printf '{"major":"%s","image":"%s","exec":"timeout","pkgmgr":"unknown","yum_ok":"unknown","egress_s3":"unknown","egress_epel":"unknown","entitlement":"%s","verdict":"blocked","reason":"probe timed out after %ss"}' \
      "${major}" "${ref}" "${ent}" "${RUN_TIMEOUT:-600}"
    return 0
  fi
  exec_ok="$(probe_field "${out}" EXEC)"; [ -n "${exec_ok}" ] || exec_ok="fail"
  arch="$(probe_field "${out}" ARCH)"
  redhat="$(probe_field "${out}" REDHAT)"
  pkgmgr="$(probe_field "${out}" PKGMGR)"; [ -n "${pkgmgr}" ] || pkgmgr="unknown"
  yumok="$(probe_field "${out}" YUMOK)"; [ -n "${yumok}" ] || yumok="unknown"
  s3="$(probe_field "${out}" S3)"; [ -n "${s3}" ] || s3="unknown"
  epel="$(probe_field "${out}" EPEL)"; [ -n "${epel}" ] || epel="unknown"
  verdict="$(probe_verdict "${exec_ok}" "${s3}" "${epel}" "${yumok}")"
  printf '{"major":"%s","image":"%s","arch":"%s","redhat_release":"%s","exec":"%s","pkgmgr":"%s","yum_ok":"%s","egress_s3":"%s","egress_epel":"%s","entitlement":"%s","verdict":"%s"}' \
    "${major}" "${ref}" "${arch}" "$(jesc "${redhat}")" "${exec_ok}" "${pkgmgr}" "${yumok}" "${s3}" "${epel}" "${ent}" "${verdict}"
}

main() {
  command -v podman >/dev/null 2>&1 || { log "ERROR: --probe-env needs podman (L3)"; return 2; }
  host_banner
  log "probing majors: [${MAJORS}] (RUN_TIMEOUT=${RUN_TIMEOUT:-600}s, PKG_TIMEOUT=${PKG_TIMEOUT:-300}s)"
  local first=1 major j
  {
    local plat ra mode conf sig feas mounts
    plat="$(acq_platform)"; ra="$(acq_repo_access)"
    mode="${ra%%|*}"; conf="$(printf '%s' "${ra}" | cut -d'|' -f2)"; sig="${ra##*|}"
    feas="$(acq_entitlement_feasible "${mode}")"; mounts="$(acq_entitlement_mount_args "${mode}")"
    log "platform: ${plat} | repo_access: ${mode} (confidence=${conf}; ${sig}) | entitled_passthrough: ${feas}"
    printf '{\n  "host": %s,\n  "platform": "%s",\n  "repo_access": {"mode":"%s","confidence":"%s","signals":"%s","entitled_passthrough":"%s","mount_args":"%s"},\n  "probes": [\n' \
      "$(host_json)" "${plat}" "${mode}" "${conf}" "$(jesc "${sig}")" "${feas}" "$(jesc "$(printf '%s' "${mounts}" | sed 's/ *$//')")"
    for major in ${MAJORS}; do
      j="$(probe_one "${major}" "${mode}")"
      [ "${first}" = 1 ] || printf ',\n'
      first=0
      printf '    %s' "${j}"
      log "RHEL${major}: $(printf '%s' "${j}" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    print("%s | exec=%s yum=%s s3=%s epel=%s ent=%s -> %s" % (d.get("image","?"),d.get("exec","?"),d.get("yum_ok","?"),d.get("egress_s3","?"),d.get("egress_epel","?"),d.get("entitlement","?"),d.get("verdict","?")))
except Exception:
    print("(unparseable)")' 2>/dev/null || printf '(row)')"
    done
    printf '\n  ]\n}\n'
  } > "${OUT_JSON}"
  log "wrote ${OUT_JSON}"
  printf '\n== environment readiness (probe) ==\n'
  python3 - "${OUT_JSON}" <<'PY' 2>/dev/null || cat "${OUT_JSON}"
import json,sys
d=json.load(open(sys.argv[1]))
hdr=("major","pkgmgr","exec","yum","s3","epel","entitle","verdict")
print("%-6s %-8s %-8s %-6s %-6s %-6s %-10s %s" % hdr)
for p in d.get("probes",[]):
    print("%-6s %-8s %-8s %-6s %-6s %-6s %-10s %s" % (
        "RHEL"+str(p.get("major","?")), p.get("pkgmgr","?"), p.get("exec","?"),
        p.get("yum_ok","?"), p.get("egress_s3","?"), p.get("egress_epel","?"),
        p.get("entitlement","?"), p.get("verdict","?")))
print("\nverdict: ready = all common prerequisites hold; degraded = runs but egress/yum gap; blocked = image will not run here.")
PY
}

ACTION=probe
while [ "$#" -gt 0 ]; do
  case "$1" in
    --probe-env)  ACTION=probe ;;
    --json)       OUT_JSON="${2:-}"; shift ;;
    --majors)     MAJORS="${2:-}"; shift ;;
    -h|--help)    printf 'usage: probe-env.sh [--probe-env] [--json PATH] [--majors "10 9 8 7 6"]\n'; exit 0 ;;
    *)            log "unknown arg: $1" ;;
  esac
  shift
done
[ "${ACTION}" = "probe" ] && main
