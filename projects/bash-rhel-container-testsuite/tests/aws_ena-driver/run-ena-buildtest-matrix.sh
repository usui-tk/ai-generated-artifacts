#!/usr/bin/env bash
#==============================================================================
# tests/aws_ena-driver/run-ena-buildtest-matrix.sh
#   AWS ENA driver BUILD-test matrix (framework (b)+(d)) for the RHEL family.
#
# ENA is the E2' entitlement-gated tool (the design plan sec 11.3). Unlike AWS CLI
# (glibc) and SSM (glibc + init_mode), the ENA gate is **entitlement**: building
# ena.ko needs kernel-devel + gcc + make, which come only from the entitled repos
# (confirmed obtainable in every major when entitled, sec 3.3). The driver is
# compiled OUT OF TREE against the installed kernel-devel headers
#   make -C /usr/src/kernels/<kver> M=<src> modules
# independent of the running host kernel. All Oracle UEK handling is removed
# (stock RHEL kernel: `rpm -q kernel`). env_init_mode = none (build is init-agnostic).
#
# E2' behaviour:
#   entitled  -> build ena.ko (plain-make; DKMS if EPEL) -> ok | build-fail
#   anonymous -> skip (no kernel-devel)                  -> needs-entitlement
#   any       -> load / runtime                          -> L4 (impossible in a container)
#
# Surfaces: --generate-results (DEFAULT, hermetic) writes RESULTS-rhel<N>.md from
# ena-driver-releases.json + the per-major kernel-devel repo + the entitlement
# grid; --run (L3, entitled container egress) acquires an entitled rootfs,
# installs kernel-devel/gcc/make, fetches the ENA source, builds, and records.
#
# The column-0 pure helpers carry the unit coverage in tests/t010_enaverdict.sh.
#==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RELEASES="${SCRIPT_DIR}/ena-driver-releases.json"
LEDGER="${SCRIPT_DIR}/buildtest-ledger.json"
RESULTS_DIR="${SCRIPT_DIR}"
INSTALL_SCRIPT="${PROJ_DIR}/install-aws_ena-driver.sh"   # kicked by run_matrix (--run)
ENA_MIN="3.3.0"   # overridden below from releases.json min_version if present

log() { printf '%s [ena-matrix] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

# --- pure helpers (column-0; loaded by t010_enaverdict.sh) -------------------

# ena_ge <a> <b> : 3-part dotted-numeric compare, a >= b.
ena_ge() {
  local a="$1" b="$2" hi
  [ "${a}" = "${b}" ] && return 0
  hi="$(printf '%s\n%s\n' "${a}" "${b}" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
  [ "${hi}" = "${a}" ]
}

# ena_kdevel_repo <major> : the repo that provides kernel-devel WHEN ENTITLED
# (the design plan sec 3.3). 7/6 -> server, 8 -> baseos, 9/10 -> appstream.
ena_kdevel_repo() {
  case "${1:-}" in
    10|9) printf 'appstream' ;;
    8)    printf 'baseos' ;;
    7|6)  printf 'server' ;;
    *)    printf 'unknown' ;;
  esac
}

# ena_in_scope <version> <min> <full> : default (>=min) vs --full (all) filter.
ena_in_scope() {
  local v="${1:-}" min="${2:-}" full="${3:-0}"
  [ "${full}" = "1" ] && return 0
  ena_ge "${v}" "${min}"
}

# ena_build_plan <entitlement> <epel> : how the build is attempted.
#   anonymous       -> skip   (no kernel-devel)
#   entitled + epel -> dkms   (optional DKMS path; dkms is EPEL-only)
#   entitled        -> make   (the default plain-make fallback)
ena_build_plan() {
  local ent="${1:-}" epel="${2:-0}"
  case "${ent}" in
    anonymous) printf 'skip' ;;
    entitled)  [ "${epel}" = "1" ] && printf 'dkms' || printf 'make' ;;
    *)         printf 'unknown' ;;
  esac
}

# ena_verdict <entitlement> <built> : the E2' headline verdict.
#   anonymous            -> needs-entitlement
#   entitled + built     -> ok
#   entitled + not-built -> build-fail
ena_verdict() {
  local ent="${1:-}" built="${2:-false}"
  case "${ent}" in
    anonymous) printf 'needs-entitlement' ;;
    entitled)  [ "${built}" = "true" ] && printf 'ok' || printf 'build-fail' ;;
    *)         printf 'unknown' ;;
  esac
}

# ena_load_tier : module load is impossible in a container -> always L4.
ena_load_tier() { printf 'L4'; }

# --- releases.json + ledger readers ------------------------------------------

releases_min() {
  [ -f "${RELEASES}" ] || { printf '%s' "${ENA_MIN}"; return 0; }
  python3 - "${RELEASES}" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
print(d.get("min_version","3.3.0"))
PY
}

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
    p=(v.split(".")+["0","0","0"])[:3]
    try: return tuple(int(x) for x in p)
    except ValueError: return (0,0,0)
print(max(vs,key=key) if vs else "")
PY
}

ledger_built() { # <major> <version> <entitlement> -> 'true'/'false' or empty
  local major="$1" ver="$2" ent="$3"
  [ -f "${LEDGER}" ] || return 0
  python3 - "${LEDGER}" "${major}" "${ver}" "${ent}" <<'PY' 2>/dev/null || true
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
maj,ver,ent=sys.argv[2],sys.argv[3],sys.argv[4]
for r in d.get("results",[]):
    if str(r.get("osmajor"))==maj and r.get("ena_version")==ver and r.get("entitlement")==ent:
        print("true" if r.get("built") else "false"); break
PY
}

# --- (d) RESULTS generation (hermetic) ---------------------------------------

generate_results_for() {
  local major="$1" repo img out maxver mn ent plan built verdict cell v
  repo="$(ena_kdevel_repo "${major}")"
  mn="$(releases_min)"
  maxver="$(releases_max 2>/dev/null || true)"
  case "${major}" in
    10) img="ubi10/ubi-init (10.2)" ;; 9) img="ubi9/ubi-init (9.8)" ;;
    8)  img="ubi8/ubi-init (8.10)" ;;  7) img="ubi7/ubi-init (7.9)" ;;
    6)  img="rhel6/rhel (6.10)" ;;     *) img="(unknown)" ;;
  esac
  out="${RESULTS_DIR}/RESULTS-rhel${major}.md"

  {
    printf '# AWS ENA driver - RHEL %s build results\n\n' "${major}"
    printf '> GENERATED by run-ena-buildtest-matrix.sh - do not hand-edit.\n'
    printf '> %sexpected%s is the E2%s model; %sempirical%s is filled by the L3 build on an\n' '`' '`' "'" '`' '`'
    printf '> entitled container-egress host. Module LOAD is always L4 (not a container).\n\n'
    printf '| Field | Value |\n|:--|:--|\n'
    printf '| OS major | RHEL %s |\n' "${major}"
    printf '| Image (measured) | %s%s%s |\n' '`' "${img}" '`'
    printf '| Axis | entitlement (kernel-devel + gcc + make) |\n'
    printf '| kernel-devel repo (entitled) | %s%s%s |\n' '`' "${repo}" '`'
    printf '| Build | %smake -C /usr/src/kernels/<kver> M=<src> modules%s (UEK removed) |\n' '`' '`'
    printf '| Newest ENA version | %s |\n' "${maxver:-unknown}"
    printf '| In-scope versions (>= %s) | %s |\n\n' "${mn}" "$(releases_versions 2>/dev/null | while read -r v; do ena_ge "${v}" "${mn}" && echo x; done | grep -c x || printf '0')"

    printf '## E2%s entitlement grid (the ENA axis)\n\n' "'"
    printf '| entitlement | build plan | expected | empirical | verdict |\n'
    printf '|:--|:--|:--|:--|:--|\n'
    for ent in entitled anonymous; do
      plan="$(ena_build_plan "${ent}" 0)"
      cell="$(ledger_built "${major}" "${maxver}" "${ent}")"
      if [ -n "${cell}" ]; then
        verdict="$(ena_verdict "${ent}" "${cell}")"; built="${cell}"
      else
        built="pending"; verdict="$( [ "${ent}" = "anonymous" ] && printf 'needs-entitlement' || printf 'pending' )"
      fi
      case "${ent}" in
        entitled)  printf '| entitled | %s (plain-make; dkms if EPEL) | ok / build-fail | %s | %s |\n' "${plan}" "${built}" "${verdict}" ;;
        anonymous) printf '| anonymous | %s (no kernel-devel) | needs-entitlement | n/a | %s |\n' "${plan}" "${verdict}" ;;
      esac
    done
    printf '\n_Module load + device attach is always **%s** (impossible in a container).' "$(ena_load_tier)"
    printf ' A build verdict of **ok** means the requested version compiled out of tree (necessary, not sufficient); real module load + device attach are proven separately on real Nitro. The optional DKMS path is EPEL-only (lib/epel.sh)._\n\n'

    printf '## per-version expectation (entitled; empirical filled by L3)\n\n'
    printf '| version | >= min | build plan (entitled) | expected verdict |\n|:--|:--|:--|:--|\n'
    for v in "${maxver:-2.17.0}" "${mn}"; do
      [ -n "${v}" ] || continue
      if ena_ge "${v}" "${mn}"; then printf '| %s | yes | make | ok (if compiles) |\n' "${v}"; else printf '| %s | no | make | ok (if compiles) |\n' "${v}"; fi
    done
    printf '\n_The entitled build target is the installed kernel-devel tree, not the host kernel._\n'
  } > "${out}"
  log "wrote ${out}"
}

generate_results() {
  local m
  for m in 6 7 8 9 10; do generate_results_for "${m}"; done
}

# --- (b) L3 build loop (entitled container egress required) ------------------
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
  local majors="${OSMAJORS:-10 9 8 7 6}" ents="${ENTITLEMENTS:-entitled anonymous}" major ent ver repo plan ref out line built status kov
  for major in ${majors}; do
    ver="$(releases_max)"
    repo="$(ena_kdevel_repo "${major}")"
    ref="$(acq_ref_for_major "${major}")" || { log "skip RHEL${major}: no ref"; continue; }
    for ent in ${ents}; do
      plan="$(ena_build_plan "${ent}" 0)"
      # KICK install-aws_ena-driver.sh in ENA_INSTALLTEST mode. anonymous -> the
      # script does not build and emits built=false (verdict needs-entitlement);
      # entitled -> it installs kernel-devel from "${repo}", fetches ena_linux_<ver>,
      # builds ena.ko out of tree, and verifies its modinfo version. Load is L4.
      out="$(podman run --rm \
              -v "${INSTALL_SCRIPT}:/install-aws_ena-driver.sh:ro" \
              -e ENA_INSTALLTEST=1 -e "ENA_VERSION=${ver}" -e "ENA_ENTITLEMENT=${ent}" \
              -e "ENA_BUILD_PLAN=${plan}" -e "INSECURE_TLS=${INSECURE_TLS:-0}" \
              "${ref}" /bin/bash /install-aws_ena-driver.sh 2>/dev/null || true)"
      line="$(printf '%s
' "${out}" | grep -F '[aws_ena-driver][installtest][result]' | tail -1)"
      built="$(result_field "${line}" built)"; [ "${built}" = "true" ] || built=false
      status="$(result_field "${line}" status)"; [ -n "${status}" ] || status=unknown
      kov="$(result_field "${line}" ko_version)"
      printf '{"status":"%s","osmajor":"%s","ena_version":"%s","entitlement":"%s","kdevel_repo":"%s","build_plan":"%s","built":%s,"ko_version":"%s","verdict":"%s","load_tier":"%s"}
' \
        "${status}" "${major}" "${ver}" "${ent}" "${repo}" "${plan}" "${built}" "${kov}" \
        "$(ena_verdict "${ent}" "${built}")" "$(ena_load_tier)"
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
