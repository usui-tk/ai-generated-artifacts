#!/usr/bin/env bash
#==============================================================================
# tests/aws_ssm-agent/run-ssm-installtest-matrix.sh
#   AWS SSM Agent install-test matrix (framework (b)+(d)) for the RHEL family.
#
# SSM is the init-sensitive tool. Acquired from the AWS S3 RPM
#   https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/<ver>/linux_amd64/amazon-ssm-agent.rpm
# its two axes (the design plan sec 11.2) are:
#   * glibc    - the RPM's libc dependency closure gates install (recorded per
#                major; install success is empirical, no fabricated floor).
#   * init_mode- env_init_mode=none -> install + `amazon-ssm-agent -version`
#                (a `systemctl enable` may warn without PID 1 systemd);
#                env_init_mode=systemd -> boot ubi-init as PID 1, then
#                `systemctl enable`/`start` and verify the unit activates.
# The container shares the HOST kernel, so the go.mod->min-kernel proxy used for
# the OL VM matrix is intentionally dropped. A documented minimum VERSION
# (>= 3.3.3598.0) separates full-feature agents from ec2messages-only ones.
#
# Surfaces: --generate-results (DEFAULT, hermetic) writes RESULTS-rhel<N>.md from
# ssm-releases.json + the measured per-major glibc + the init-mode grid; --run
# (L3, container egress) acquires init-mode-aware refs via lib/acquire-rootfs.sh,
# installs the RPM, smokes -version, and (systemd) enables/starts the unit.
#
# The column-0 pure helpers carry the unit coverage in tests/t009_ssmverdict.sh.
#==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RELEASES="${SCRIPT_DIR}/ssm-releases.json"
LEDGER="${SCRIPT_DIR}/ssm-installtest-ledger.json"
RESULTS_DIR="${SCRIPT_DIR}"
INSTALL_SCRIPT="${PROJ_DIR}/install-aws_ssm-agent.sh"   # kicked by run_matrix (--run)
SSM_MIN="3.3.3598.0"

log() { printf '%s [ssm-matrix] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

# --- pure helpers (column-0; loaded by t009_ssmverdict.sh) -------------------

# ssm_ge <a> <b> : 4-part dotted-numeric compare, a >= b.
ssm_ge() {
  local a="$1" b="$2" hi
  [ "${a}" = "${b}" ] && return 0
  hi="$(printf '%s\n%s\n' "${a}" "${b}" | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1)"
  [ "${hi}" = "${a}" ]
}

# rhel_glibc <major> : the MEASURED per-major glibc (the design plan sec 3.2).
rhel_glibc() {
  case "${1:-}" in
    10) printf '2.39' ;; 9) printf '2.34' ;; 8) printf '2.28' ;;
    7)  printf '2.17' ;; 6) printf '2.12' ;; *) printf 'unknown' ;;
  esac
}

# ssm_in_scope <version> <min> <full> : default (>=min) vs --full (all) filter.
ssm_in_scope() {
  local v="${1:-}" min="${2:-}" full="${3:-0}"
  [ "${full}" = "1" ] && return 0
  ssm_ge "${v}" "${min}"
}

# ssm_compliance <maxver> <min> : headline feature verdict for a major.
#   compliant-capable -> the newest installable agent is >= min (full SSM)
#   ec2messages-only  -> newest installable < min (no full Systems Manager)
#   none              -> nothing installed+ran
ssm_compliance() {
  local maxver="${1:-}" min="${2:-}"
  [ -n "${maxver}" ] || { printf 'none'; return 0; }
  if ssm_ge "${maxver}" "${min}"; then printf 'compliant-capable'; else printf 'ec2messages-only'; fi
}

# ssm_init_outcome <init_mode> : what a successful install can demonstrate.
#   none    -> version-only  (binary smoke; service not PID-1 manageable)
#   systemd -> service-capable (enable/start + unit activation)
ssm_init_outcome() {
  case "${1:-}" in
    none)    printf 'version-only' ;;
    systemd) printf 'service-capable' ;;
    *)       printf 'unknown' ;;
  esac
}

# ssm_verdict <installed> <ran> <init_mode> : the EMPIRICAL per-cell headline.
ssm_verdict() {
  local installed="${1:-false}" ran="${2:-false}" mode="${3:-none}"
  [ "${installed}" = "true" ] || { printf 'install-fail'; return 0; }
  [ "${ran}" = "true" ] || { printf 'installed-no-run'; return 0; }
  case "${mode}" in
    systemd) printf 'runs-service' ;;
    none)    printf 'runs-no-init' ;;
    *)       printf 'runs' ;;
  esac
}

# --- releases.json + ledger readers ------------------------------------------

releases_versions() {
  [ -f "${RELEASES}" ] || return 1
  python3 - "${RELEASES}" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
for x in d.get("versions",[]):
    print(x.get("version",""))
PY
}

releases_max() {
  [ -f "${RELEASES}" ] || return 1
  python3 - "${RELEASES}" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
vs=[x.get("version","") for x in d.get("versions",[])]
def key(v):
    p=(v.split(".")+["0","0","0","0"])[:4]
    try: return tuple(int(x) for x in p)
    except ValueError: return (0,0,0,0)
print(max(vs,key=key) if vs else "")
PY
}

ledger_cell() { # <major> <version> <init_mode> -> "installed|ran" or empty
  local major="$1" ver="$2" mode="$3"
  [ -f "${LEDGER}" ] || return 0
  python3 - "${LEDGER}" "${major}" "${ver}" "${mode}" <<'PY' 2>/dev/null || true
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
maj,ver,mode=sys.argv[2],sys.argv[3],sys.argv[4]
for r in d.get("results",[]):
    if str(r.get("osmajor"))==maj and r.get("ssm_version")==ver and r.get("init_mode")==mode:
        print("%s|%s"%(str(r.get("installed")).lower(),str(r.get("ran")).lower())); break
PY
}

# --- (d) RESULTS generation (hermetic) ---------------------------------------

generate_results_for() {
  local major="$1" osg img out maxver compliance mode v cell installed ran verdict exp
  osg="$(rhel_glibc "${major}")"
  case "${major}" in
    10) img="ubi10/ubi-init (10.2)" ;; 9) img="ubi9/ubi-init (9.8)" ;;
    8)  img="ubi8/ubi-init (8.10)" ;;  7) img="ubi7/ubi-init (7.9)" ;;
    6)  img="rhel6/rhel (6.10)" ;;     *) img="(unknown)" ;;
  esac
  out="${RESULTS_DIR}/RESULTS-rhel${major}.md"
  maxver="$(releases_max 2>/dev/null || true)"
  compliance="$(ssm_compliance "${maxver}" "${SSM_MIN}")"

  {
    printf '# AWS SSM Agent - RHEL %s install/run results\n\n' "${major}"
    printf '> GENERATED by run-ssm-installtest-matrix.sh - do not hand-edit.\n'
    printf '> The "expected" cells are the model; "empirical" is filled by the L3\n'
    printf '> %s--run%s matrix on a container-egress host.\n\n' '`' '`'
    printf '| Field | Value |\n|:--|:--|\n'
    printf '| OS major | RHEL %s |\n' "${major}"
    printf '| Image (measured) | %s%s%s |\n' '`' "${img}" '`'
    printf '| OS glibc (measured) | **%s** |\n' "${osg}"
    printf '| Axes | glibc (install) + init_mode (service) |\n'
    printf '| In-scope versions (>= %s) | %s |\n' "${SSM_MIN}" "$(releases_versions 2>/dev/null | while read -r v; do ssm_ge "${v}" "${SSM_MIN}" && echo x; done | grep -c x || printf '0')"
    printf '| Newest version | %s |\n' "${maxver:-unknown}"
    printf '| Feature compliance | **%s** (min %s) |\n\n' "${compliance}" "${SSM_MIN}"

    printf '## init_mode grid (the SSM-specific axis)\n\n'
    printf '| init_mode | acquire form | demonstrates | expected | empirical | verdict |\n'
    printf '|:--|:--|:--|:--|:--|:--|\n'
    for mode in none systemd; do
      exp="$(ssm_init_outcome "${mode}")"
      cell="$(ledger_cell "${major}" "${maxver}" "${mode}")"
      if [ -n "${cell}" ]; then
        installed="${cell%%|*}"; ran="${cell##*|}"
        verdict="$(ssm_verdict "${installed}" "${ran}" "${mode}")"
        ran="${ran}/${installed}"
      else
        ran="pending"; verdict="pending"
      fi
      case "${mode}" in
        none)    printf '| none | run --rm REF -version | binary smoke | %s | %s | %s |\n' "${exp}" "${ran}" "${verdict}" ;;
        systemd) printf '| systemd | run -d REF (/sbin/init) | enable/start unit | %s | %s | %s |\n' "${exp}" "${ran}" "${verdict}" ;;
      esac
    done
    printf '\n_The acquire forms come from lib/acquire-rootfs.sh acq_init_run_args (Phase 2)._\n\n'

    printf '## version compliance (informational)\n\n'
    printf '%s\n\n' "On RHEL ${major}, the newest agent (${maxver:-unknown}) is **${compliance}**. Agents below ${SSM_MIN} install but are ec2messages-only (no full Systems Manager)."
    printf '| version | >= min | glibc (os) | install (empirical) |\n|:--|:--|:--|:--|\n'
    for v in "${maxver:-3.3.4624.0}" "${SSM_MIN}" 3.0.1479.0; do
      [ -n "${v}" ] || continue
      if ssm_ge "${v}" "${SSM_MIN}"; then printf '| %s | yes | %s | pending |\n' "${v}" "${osg}"; else printf '| %s | no | %s | pending |\n' "${v}" "${osg}"; fi
    done
    printf '\n_Install is empirically gated by the RPM dep closure + glibc; the L3 run records it._\n'
  } > "${out}"
  log "wrote ${out}"
}

generate_results() {
  local m
  for m in 6 7 8 9 10; do generate_results_for "${m}"; done
}

# --- (b) L3 install-test loop (container egress required) ---------------------
# result_field <result-json-line> <key> : extract a value from an install
# script's single-line [installtest][result] JSON (string, bool, or number).
# Pure, jq-free. Reuse-by-copy across the tool matrices.
result_field() {
  local line="$1" key="$2" v
  v="$(printf '%s' "${line}" | grep -oE "\"${key}\":\"[^\"]*\"" | head -1 | sed 's/^[^:]*://; s/\"//g')"
  if [ -z "${v}" ]; then
    v="$(printf '%s' "${line}" | grep -oE "\"${key}\":(true|false|[0-9]+)" | head -1 | sed 's/^[^:]*://')"
  fi
  printf '%s' "${v}"
}

run_matrix() {
  command -v podman >/dev/null 2>&1 || { log "ERROR: --run needs podman (L3)"; return 2; }
  [ -f "${INSTALL_SCRIPT}" ] || { log "ERROR: install script missing: ${INSTALL_SCRIPT}"; return 2; }
  # shellcheck source=../../lib/acquire-rootfs.sh
  . "${PROJ_DIR}/lib/acquire-rootfs.sh"
  local majors="${OSMAJORS:-10 9 8 7 6}" modes="${INITMODES:-none systemd}" major mode ref ver out line installed ran svc status
  for major in ${majors}; do
    ref="$(acq_ref_for_major "${major}")" || { log "skip RHEL${major}"; continue; }
    ver="$(releases_max)"
    for mode in ${modes}; do
      # KICK install-aws_ssm-agent.sh in SSM_INSTALLTEST mode. For systemd the
      # container must boot /sbin/init first; acq_init_run_args (Phase 2) builds
      # that invocation. The install script installs the RPM, runs
      # `amazon-ssm-agent -version`, and (systemd) enables for boot.
      out="$(podman run --rm \
              -v "${INSTALL_SCRIPT}:/install-aws_ssm-agent.sh:ro" \
              -e SSM_INSTALLTEST=1 -e "SSM_VERSION=${ver}" -e "SSM_INIT_MODE=${mode}" -e "INSECURE_TLS=${INSECURE_TLS:-0}" \
              "${ref}" /bin/bash /install-aws_ssm-agent.sh 2>/dev/null || true)"
      line="$(printf '%s
' "${out}" | grep -F '[aws_ssm-agent][installtest][result]' | tail -1)"
      installed="$(result_field "${line}" installed)"; [ "${installed}" = "true" ] || installed=false
      ran="$(result_field "${line}" ran)";             [ "${ran}" = "true" ] || ran=false
      svc="$(result_field "${line}" service_enabled)"; [ "${svc}" = "true" ] || svc=false
      status="$(result_field "${line}" status)"; [ -n "${status}" ] || status=unknown
      printf '{"status":"%s","osmajor":"%s","ssm_version":"%s","init_mode":"%s","glibc":"%s","installed":%s,"ran":%s,"service_enabled":%s,"verdict":"%s"}
' \
        "${status}" "${major}" "${ver}" "${mode}" "$(rhel_glibc "${major}")" "${installed}" "${ran}" "${svc}" \
        "$(ssm_verdict "${installed}" "${ran}" "${mode}")"
    done
  done
}

# --- arg parsing -------------------------------------------------------------
ACTION="generate-results"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --run)              ACTION="run" ;;
    --generate-results) ACTION="generate-results" ;;
    --releases)         RELEASES="${2:-}"; shift ;;
    --ledger)           LEDGER="${2:-}"; shift ;;
    --results-dir)      RESULTS_DIR="${2:-}"; shift ;;
    -h|--help)          sed -n '2,30p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) log "unknown option: $1"; exit 2 ;;
  esac
  shift
done

case "${ACTION}" in
  generate-results) generate_results ;;
  run)              run_matrix ;;
esac
