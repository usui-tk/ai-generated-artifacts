#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   Run the SSM Agent install (both init modes) test matrix per RHEL major; append
#   measured rows to the JSON ledger and regenerate RESULTS-rhel<N>.md.
# ----- Prerequisites --------------------------------------------------------
#   bash 4+, python3; report mode: none beyond the repo. --run: podman (or the
#   curl-only OCI fallback) + container egress; entitled host for rhel-* repos.
# ----- Usage examples -------------------------------------------------------
#   bash run-ssm-installtest-matrix.sh              # regenerate reports from the ledger
#   OSMAJORS="9 8" bash run-ssm-installtest-matrix.sh --run   # live matrix
# ----- Known limitations ----------------------------------------------------
#   --run is L3 (manual/CI); RESULTS files are generated - never hand-edited.
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
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
# Surfaces: NO-ARG (DEFAULT) runs the full E2E in one shot - sweep every in-scope
# version (min SSM_MIN -> latest) x major x init_mode, persist the ledger, then
# regenerate RESULTS-rhel<N>.md (mirrors the OL model's one-script workflow).
#   --run              : run the sweep + persist the ledger only (needs podman/L3)
#   --generate-results : (re)generate the reports only, hermetic (no containers)
# Knobs: OSMAJORS, INITMODES, SSM_VERSIONS, INSECURE_TLS.
#
# The column-0 pure helpers carry the unit coverage in tests/t009_ssmverdict.sh.
#==============================================================================
set -euo pipefail

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

# ssm_inscope_versions : the in-scope SSM versions (>= SSM_MIN) in ASCENDING order
# (min first, latest last) - the default sweep set for --run and the E2E table.
ssm_inscope_versions() {
  releases_versions 2>/dev/null | while IFS= read -r v; do
    [ -n "${v}" ] || continue
    ssm_ge "${v}" "${SSM_MIN}" && printf '%s\n' "${v}"
  done | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n
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
    printf '_Collected on (this run): %s_\n\n' "$(ledger_host_line)"

    printf '## Why this matters - AWS Systems Manager Run Command deprecation\n\n'
    # shellcheck disable=SC2016  # backticks are literal Markdown code spans in the single-quoted format
    printf 'Starting **2026-06-16**, SSM Run Command stops executing commands on managed instances that still use the legacy **ec2messages** (Amazon Message Delivery Service) endpoints - endpoints used only by SSM Agents too old to support the newer **ssmmessages** (Amazon Message Gateway Service) endpoints. The remediation is to update the SSM Agent to **%s or newer** and grant the instance role the ssmmessages channel permissions (`CreateControlChannel` / `CreateDataChannel` / `OpenControlChannel` / `OpenDataChannel`); affected instances are listed in the AWS Health Dashboard. This report characterizes, per RHEL major, which agent versions install+run - i.e. whether a RHEL %s image can be brought to a **compliant (>= %s)** agent.\n\n' "${SSM_MIN}" "${major}" "${SSM_MIN}"
    printf 'References (AWS docs): [Run Command](https://docs.aws.amazon.com/systems-manager/latest/userguide/run-command.html); [message service endpoints](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-setting-up-messageAPIs.html#message-services); [update SSM Agent](https://docs.aws.amazon.com/systems-manager/latest/userguide/run-command-tutorial-update-software.html); [ssmmessages IAM actions](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonmessagegatewayservice.html); [check agent version with Fleet Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/ssm-agent-get-version.html).\n\n'

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

    printf '## E2E sweep evidence (min %s -> latest)\n\n' "${SSM_MIN}"
    printf '%s\n\n' "On RHEL ${major}, the newest agent (${maxver:-unknown}) is **${compliance}**. \`none\` (install + \`-version\`) is swept for every in-scope version; \`systemd\` (service enable) is verified on the representative version (${maxver:-latest}) only - install/run do not depend on init_mode, so other systemd cells read \`n/a\`. \`pending\` = not yet run; agents below ${SSM_MIN} are out of scope (ec2messages-only)."
    printf '| version | >= min | none (ran/installed) | systemd (ran/installed) | verdict |\n|:--|:--|:--|:--|:--|\n'
    for v in $(ssm_inscope_versions); do
      [ -n "${v}" ] || continue
      ge=no; ssm_ge "${v}" "${SSM_MIN}" && ge=yes
      c_none="$(ledger_cell "${major}" "${v}" none)"
      c_sys="$(ledger_cell "${major}" "${v}" systemd)"
      if [ -n "${c_none}" ]; then ncell="${c_none##*|}/${c_none%%|*}"; else ncell="pending"; fi
      if [ -n "${c_sys}" ]; then
        s_inst="${c_sys%%|*}"; s_ran="${c_sys##*|}"; scell="${s_ran}/${s_inst}"
        vdt="$(ssm_verdict "${s_inst}" "${s_ran}" systemd)"
      elif [ "${v}" = "${maxver}" ]; then
        scell="pending"; vdt="pending"
      else
        scell="n/a"; vdt="n/a"
      fi
      printf '| %s | %s | %s | %s | %s |\n' "${v}" "${ge}" "${ncell}" "${scell}" "${vdt}"
    done
    # shellcheck disable=SC2016  # backticks are literal Markdown code spans in the single-quoted format
    printf '\n_Install is empirically gated by the RPM dep closure + glibc; %s versions in scope. Regenerate this evidence with a single run: `OSMAJORS=%s ./run-ssm-installtest-matrix.sh`._\n' \
      "$(ssm_inscope_versions | grep -c .)" "${major}"
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

# ensure_ledger : create the ledger skeleton if it is missing (e.g. right after
# `rm -rf *.json`), so a from-scratch `list -> run` still produces the baseline
# evidence file that the report reads. persist_ledger then folds rows into it.
ensure_ledger() {
  [ -f "${LEDGER}" ] && return 0
  cat > "${LEDGER}" <<'JSON'
{
  "tool": "aws_ssm-agent",
  "note": "Empirical install-test ledger. Created/appended by run-ssm-installtest-matrix.sh on a container-egress host (L3); never hand-edited.",
  "results": []
}
JSON
  log "created ledger skeleton: ${LEDGER}"
}

# persist_ledger <rows-file> : fold the swept JSONL rows into ${LEDGER}'s results[]
# (dedup by osmajor+ssm_version+init_mode; last write wins). Atomic tmp+replace.
# This is what turns a --run sweep into durable evidence the report reads.
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
def key(r): return (str(r.get("osmajor")), r.get("ssm_version"), r.get("init_mode"))
merged={}
for r in d.get("results",[]): merged[key(r)]=r
for r in rows: merged[key(r)]=r
d["results"]=[merged[k] for k in sorted(merged, key=lambda k:(int(k[0]) if str(k[0]).isdigit() else 0, k[1] or "", k[2] or ""))]
fd,tmp=tempfile.mkstemp(dir=os.path.dirname(led) or ".")
with os.fdopen(fd,"w") as fh: json.dump(d,fh,indent=2); fh.write("\n")
os.replace(tmp,led)
PY2
  log "ledger updated: ${LEDGER} ($(grep -c '"ssm_version"' "${rows}") rows swept)"
}

run_matrix() {
  ensure_ledger
  command -v podman >/dev/null 2>&1 || { log "ERROR: --run needs podman (L3)"; return 2; }
  [ -f "${INSTALL_SCRIPT}" ] || { log "ERROR: install script missing: ${INSTALL_SCRIPT}"; return 2; }
  # shellcheck source=../../lib/acquire-rootfs.sh
  . "${PROJ_DIR}/lib/acquire-rootfs.sh"
  # shellcheck source=../../lib/provision-test-env.sh
  . "${PROJ_DIR}/lib/provision-test-env.sh"
  host_banner
  local ent_mounts; ent_mounts="$(acq_entitlement_mount_args "")"
  [ -n "${ent_mounts}" ] && log "entitlement passthrough: ${ent_mounts% }"
  record_host_meta "${LEDGER}"
  acq_preflight "${INSTALL_SCRIPT}" || { log "aborting --run (preflight failed; no rows written)"; return 2; }
  local LOG_DIR="${SCRIPT_DIR}/logs"
  local majors="${OSMAJORS:-10 9 8 7 6}"
  # Case A: install/ran do NOT depend on init_mode, only service_enabled does.
  # So sweep every in-scope version in 'none' (install/run evidence per version),
  # and test 'systemd' (service enablement) only on a representative version per
  # major. Override the none set with SSM_VERSIONS, the systemd set with
  # SSM_SYSTEMD_VERSIONS (default = the latest in-scope version).
  local versions="${SSM_VERSIONS:-$(ssm_inscope_versions | tr '
' ' ')}"
  local systemd_versions="${SSM_SYSTEMD_VERSIONS:-$(releases_max)}"
  local major ref ver rows_tmp
  rows_tmp="$(mktemp)"
  log "sweep (Case A): majors=[${majors}] none=[${versions}] systemd-rep=[${systemd_versions}]"
  for major in ${majors}; do
    ref="$(acq_ref_for_major "${major}")" || { log "skip RHEL${major}"; continue; }
    # Prepare the test environment: base image + the common package manifest,
    # committed once per OS (mirrors the OL clean-core approach; e.g. gawk, which
    # the minimal RHEL 6 base lacks and the ssm rpm %pretrans guard needs).
    ref="$(provision_test_image "${major}" "${ref}" "${ent_mounts}")" \
      || { log "skip RHEL${major}: test-env provisioning failed${PROVISION_LAST_ERR:+ - ${PROVISION_LAST_ERR}}"; continue; }
    log "RHEL${major}: test-ready image ${ref}"
    for ver in ${versions}; do ssm_kick "${major}" "${ver}" none "${ref}" "${LOG_DIR}" "${rows_tmp}"; done
    for ver in ${systemd_versions}; do ssm_kick "${major}" "${ver}" systemd "${ref}" "${LOG_DIR}" "${rows_tmp}"; done
  done
  persist_ledger "${rows_tmp}"
  rm -f "${rows_tmp}"
}

# ssm_kick <major> <ver> <mode> <ref> <log_dir> <rows_file> : run one install-test
# in a container, parse the [result], record the row (+reason), and on non-ok
# preserve the container output to <log_dir> (fail/error only).
ssm_kick() {
  local major="$1" ver="$2" mode="$3" ref="$4" log_dir="$5" rows="$6"
  local err_tmp out line installed ran svc status verdict reason row logf rc=0
  err_tmp="$(mktemp)"
  # shellcheck disable=SC2086  # ent_mounts is intentionally word-split into -v/--network args
  out="$(timeout "${RUN_TIMEOUT:-600}" podman run --rm \
          -v "${INSTALL_SCRIPT}:/install-aws_ssm-agent.sh:ro,z" \
          ${ent_mounts:-} \
          -e SSM_INSTALLTEST=1 -e "SSM_VERSION=${ver}" -e "SSM_INIT_MODE=${mode}" -e "INSECURE_TLS=${INSECURE_TLS:-0}" \
          "${ref}" /bin/bash /install-aws_ssm-agent.sh 2>"${err_tmp}")" || rc=$?
  line="$(printf '%s
' "${out}" | grep -F '[aws_ssm-agent][installtest][result]' | tail -1)" || true  # tolerated-empty probe: no result line = reasoned error row (A.5 asymmetry)
  logf="${log_dir}/installtest-rhel${major}-ssm_${ver}_${mode}.log"
  if [ "${rc}" = "124" ]; then
    reason="timed out after ${RUN_TIMEOUT:-600}s (container stalled; possible repo/network wait)"
    status=error; verdict=harness-error
    log "RHEL${major} ${ver}/${mode}: TIMEOUT -> ${reason}"
    row="$(printf '{"status":"error","osmajor":"%s","ssm_version":"%s","init_mode":"%s","glibc":"%s","installed":false,"ran":false,"service_enabled":false,"verdict":"harness-error","reason":"%s"}' \
      "${major}" "${ver}" "${mode}" "$(rhel_glibc "${major}")" "$(jesc "${reason}")")"
  elif [ -z "${line}" ]; then
    reason="$(python3 -c 'import sys,json; print(json.dumps(" ".join(open(sys.argv[1]).read().split()))[1:-1][:300])' "${err_tmp}" 2>/dev/null || true)"
    [ -n "${reason}" ] || reason="container produced no [result] and no stderr"
    status=error; verdict=harness-error
    log "RHEL${major} ${ver}/${mode}: harness-error -> ${reason}"
    row="$(printf '{"status":"error","osmajor":"%s","ssm_version":"%s","init_mode":"%s","glibc":"%s","installed":false,"ran":false,"service_enabled":false,"verdict":"harness-error","reason":"%s"}' \
      "${major}" "${ver}" "${mode}" "$(rhel_glibc "${major}")" "${reason}")"
  else
    installed="$(result_field "${line}" installed)"; [ "${installed}" = "true" ] || installed=false
    ran="$(result_field "${line}" ran)";             [ "${ran}" = "true" ] || ran=false
    svc="$(result_field "${line}" service_enabled)"; [ "${svc}" = "true" ] || svc=false
    status="$(result_field "${line}" status)"; [ -n "${status}" ] || status=unknown
    verdict="$(ssm_verdict "${installed}" "${ran}" "${mode}")"
    reason="$(jesc "$(result_field "${line}" reason)")"
    row="$(printf '{"status":"%s","osmajor":"%s","ssm_version":"%s","init_mode":"%s","glibc":"%s","installed":%s,"ran":%s,"service_enabled":%s,"verdict":"%s","reason":"%s"}' \
      "${status}" "${major}" "${ver}" "${mode}" "$(rhel_glibc "${major}")" "${installed}" "${ran}" "${svc}" "${verdict}" "${reason}")"
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
# No-arg default = the full E2E: run the sweep (all in-scope versions x majors x
# init modes), persist the ledger, then regenerate the RESULTS. This mirrors the
# Oracle Linux model project (`./run-...-matrix.sh` does everything in one shot).
#   --run               : run the sweep + persist the ledger only (no report)
#   --generate-results  : (re)generate the reports only, hermetic (no containers)
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
