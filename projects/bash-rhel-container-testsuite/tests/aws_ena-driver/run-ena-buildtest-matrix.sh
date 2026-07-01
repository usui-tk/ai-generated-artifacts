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
# Surfaces: NO-ARG (DEFAULT) runs the build matrix (all majors x entitlement),
# persists the ledger, then regenerates RESULTS-rhel<N>.md (mirrors the OL model's
# one-script workflow). Module load-readiness is a SEPARATE verify pass.
#   --run              : run the build matrix + persist the ledger only (podman/L3)
#   --generate-results : (re)generate the reports only, hermetic (no containers)
# Knobs: OSMAJORS, ENTITLEMENTS, INSECURE_TLS. Then: ./verify-ena-buildresults.sh
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

# ledger_host_line : format the ledger's 'host' meta as a one-line summary for
# the RESULTS header (or a placeholder if a live run has not populated it yet).
ledger_host_line() {
  [ -f "${LEDGER}" ] || { printf '(not yet run)'; return 0; }
  python3 - "${LEDGER}" <<'PY2' 2>/dev/null || printf '(not yet run)'
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: print("(not yet run)"); sys.exit(0)
h=d.get("host")
if not h: print("(not yet run)"); sys.exit(0)
print("%s, kernel %s %s, SELinux: %s, %s" % (h.get("os","?"),h.get("kernel","?"),h.get("arch","?"),h.get("selinux","?"),h.get("runtime","?")))
PY2
}

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

    printf '_Collected on (this run): %s_\n\n' "$(ledger_host_line)"
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

# ensure_ledger : create the ledger skeleton if missing (e.g. after `rm -rf *.json`),
# so a from-scratch `list -> run` produces the baseline evidence file.
ensure_ledger() {
  [ -f "${LEDGER}" ] && return 0
  cat > "${LEDGER}" <<'JSON'
{
  "tool": "aws_ena-driver",
  "note": "Empirical build-test ledger. Created/appended by run-ena-buildtest-matrix.sh on an ENTITLED container-egress host (L3); never hand-edited.",
  "results": []
}
JSON
  log "created ledger skeleton: ${LEDGER}"
}

# persist_ledger <rows-file> : fold the swept JSONL rows into ${LEDGER}'s results[]
# (dedup by osmajor+ena_version+entitlement; last write wins). Atomic tmp+replace.
persist_ledger() {
  local rows="$1"
  [ -f "${LEDGER}" ] || { log "no ledger at ${LEDGER}; skipping persist"; return 0; }
  python3 - "${LEDGER}" "${rows}" <<'PY2' 2>/dev/null || { log "WARNING: ledger persist failed"; return 0; }
import json,sys,os,tempfile
led,rowsfile=sys.argv[1],sys.argv[2]
try: d=json.load(open(led))
except Exception: sys.exit(1)
rows=[]
for ln in open(rowsfile):
    ln=ln.strip()
    if not ln: continue
    try: rows.append(json.loads(ln))
    except Exception: pass
def key(r): return (str(r.get("osmajor")), r.get("ena_version"), r.get("entitlement"))
merged={}
for r in d.get("results",[]): merged[key(r)]=r
for r in rows: merged[key(r)]=r
d["results"]=[merged[k] for k in sorted(merged, key=lambda k:(int(k[0]) if str(k[0]).isdigit() else 0, k[1] or "", k[2] or ""))]
fd,tmp=tempfile.mkstemp(dir=os.path.dirname(led) or ".")
with os.fdopen(fd,"w") as fh: json.dump(d,fh,indent=2); fh.write("\n")
os.replace(tmp,led)
PY2
  log "ledger updated: ${LEDGER} ($(grep -c '"ena_version"' "${rows}") rows)"
}

run_matrix() {
  ensure_ledger
  command -v podman >/dev/null 2>&1 || { log "ERROR: --run needs podman (L3)"; return 2; }
  [ -f "${INSTALL_SCRIPT}" ] || { log "ERROR: install script missing: ${INSTALL_SCRIPT}"; return 2; }
  # shellcheck source=../../lib/acquire-rootfs.sh
  . "${PROJ_DIR}/lib/acquire-rootfs.sh"
  host_banner
  record_host_meta "${LEDGER}"
  acq_preflight "${INSTALL_SCRIPT}" || { log "aborting --run (preflight failed; no rows written)"; return 2; }
  local LOG_DIR="${SCRIPT_DIR}/logs"
  local majors="${OSMAJORS:-10 9 8 7 6}" ents="${ENTITLEMENTS:-entitled anonymous}" major ent ver repo plan ref rows_tmp
  rows_tmp="$(mktemp)"
  for major in ${majors}; do
    ver="$(releases_max)"
    repo="$(ena_kdevel_repo "${major}")"
    ref="$(acq_ref_for_major "${major}")" || { log "skip RHEL${major}: no ref"; continue; }
    for ent in ${ents}; do
      plan="$(ena_build_plan "${ent}" 0)"
      ena_kick "${major}" "${ver}" "${ent}" "${repo}" "${plan}" "${ref}" "${LOG_DIR}" "${rows_tmp}"
    done
  done
  persist_ledger "${rows_tmp}"
  rm -f "${rows_tmp}"
}

# ena_kick <major> <ver> <ent> <repo> <plan> <ref> <log_dir> <rows_file> : build-test
# one (major, entitlement) in a container, record the row (+reason), and on non-ok
# preserve the container output to <log_dir> (fail/error only).
ena_kick() {
  local major="$1" ver="$2" ent="$3" repo="$4" plan="$5" ref="$6" log_dir="$7" rows="$8"
  local err_tmp out line built status kov reason row logf
  err_tmp="$(mktemp)"
  out="$(podman run --rm \
          -v "${INSTALL_SCRIPT}:/install-aws_ena-driver.sh:ro,z" \
          -e ENA_INSTALLTEST=1 -e "ENA_VERSION=${ver}" -e "ENA_ENTITLEMENT=${ent}" \
          -e "ENA_BUILD_PLAN=${plan}" -e "INSECURE_TLS=${INSECURE_TLS:-0}" \
          "${ref}" /bin/bash /install-aws_ena-driver.sh 2>"${err_tmp}" || true)"
  line="$(printf '%s
' "${out}" | grep -F '[aws_ena-driver][installtest][result]' | tail -1)"
  logf="${log_dir}/buildtest-rhel${major}-ena_${ver}_${ent}.log"
  if [ -z "${line}" ]; then
    reason="$(python3 -c 'import sys,json; print(json.dumps(" ".join(open(sys.argv[1]).read().split()))[1:-1][:300])' "${err_tmp}" 2>/dev/null || true)"
    [ -n "${reason}" ] || reason="container produced no [result] and no stderr"
    status=error
    log "RHEL${major} ${ver}/${ent}: harness-error -> ${reason}"
    row="$(printf '{"status":"error","osmajor":"%s","ena_version":"%s","entitlement":"%s","kdevel_repo":"%s","build_plan":"%s","built":false,"ko_version":"","verdict":"harness-error","load_tier":"%s","reason":"%s"}' \
      "${major}" "${ver}" "${ent}" "${repo}" "${plan}" "$(ena_load_tier)" "${reason}")"
  else
    built="$(result_field "${line}" built)"; [ "${built}" = "true" ] || built=false
    status="$(result_field "${line}" status)"; [ -n "${status}" ] || status=unknown
    kov="$(result_field "${line}" ko_version)"
    reason="$(jesc "$(result_field "${line}" reason)")"
    row="$(printf '{"status":"%s","osmajor":"%s","ena_version":"%s","entitlement":"%s","kdevel_repo":"%s","build_plan":"%s","built":%s,"ko_version":"%s","verdict":"%s","load_tier":"%s","reason":"%s"}' \
      "${status}" "${major}" "${ver}" "${ent}" "${repo}" "${plan}" "${built}" "${kov}" \
      "$(ena_verdict "${ent}" "${built}")" "$(ena_load_tier)" "${reason}")"
  fi
  if [ "${status}" != "ok" ]; then
    mkdir -p "${log_dir}"
    { printf '=== podman stdout ===
%s
=== podman stderr ===
' "${out}"; cat "${err_tmp}" 2>/dev/null; } > "${logf}" 2>/dev/null || true
    log "  log preserved: ${logf}"
  else
    rm -f "${logf}" 2>/dev/null || true
  fi
  rm -f "${err_tmp}"
  printf '%s
' "${row}"
  printf '%s
' "${row}" >> "${rows}"
}

# --- arg parsing -------------------------------------------------------------
# No-arg default = the full build-test: run the matrix (all majors x entitlement),
# persist the ledger, then regenerate RESULTS. Mirrors the OL model's one-script
# workflow. Module LOAD is L4 (Nitro); load-readiness is a SEPARATE verify pass
# (./verify-ena-buildresults.sh).
#   --run              : run the build matrix + persist the ledger only (needs podman/L3)
#   --generate-results : (re)generate the reports only, hermetic (no containers)
ACTION="all"
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
  all)              run_matrix || log "run step did not complete (see above); writing reports from the current ledger"; generate_results ;;
  run)              run_matrix ;;
  generate-results) generate_results ;;
esac
