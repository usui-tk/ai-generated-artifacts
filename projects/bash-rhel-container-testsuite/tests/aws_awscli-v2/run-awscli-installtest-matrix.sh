#!/usr/bin/env bash
#==============================================================================
# tests/aws_awscli-v2/run-awscli-installtest-matrix.sh
#   AWS CLI v2 install-test matrix (framework step (b)+(d)) for the RHEL family.
#
# Determines which AWS CLI v2 versions INSTALL and RUN on each RHEL major, on the
# single dominant axis for this tool: glibc. AWS CLI v2 ships a self-contained zip
# bundle with its own Python, built against a manylinux glibc, so the OS glibc -
# not any repo - gates install/run (the design plan sec 11.1). AWS policy
# ("Linux Support Updates for AWS CLI v2", 2024-09-16): versions >= 2.17.50 are
# manylinux2014 (glibc 2.17 floor); <= 2.17.49 the older manylinux1 floor (2.5).
#
# Two run surfaces:
#   * NO-ARG (DEFAULT): run the matrix (all majors x every in-scope version),
#     persist the ledger, then regenerate RESULTS-rhel<N>.md - one shot (mirrors
#     the OL model's one-script workflow).
#   * --run: run the matrix + persist the ledger only (needs podman/L3).
#   * --generate-results: (re)generate the reports only, hermetic (no container),
#     empirical columns read from the ledger if a live run has populated it.
#
# The pure helpers below (awscli_ge / awscli_min_glibc / awscli_in_scope /
# awscli_verdict / python_eol / rhel_glibc / awscli_band / awscli_expected) carry
# the unit coverage in tests/t008_awscliverdict.sh, which loads each by name -
# so each MUST stay defined at column 0 from `name()` to the first column-0 `}`.
#==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RELEASES="${SCRIPT_DIR}/awscli-releases.json"
LEDGER="${SCRIPT_DIR}/awscli-installtest-ledger.json"
RESULTS_DIR="${SCRIPT_DIR}"
INSTALL_SCRIPT="${PROJ_DIR}/install-aws_awscli-v2.sh"   # kicked by run_matrix (--run)

log() { printf '%s [awscli-matrix] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

# --- pure helpers (column-0; loaded by t008_awscliverdict.sh) -----------------

# awscli_ge <a> <b> : dotted-numeric compare, a >= b (versions AND glibc).
awscli_ge() {
  local a="$1" b="$2" hi
  [ "${a}" = "${b}" ] && return 0
  hi="$(printf '%s\n%s\n' "${a}" "${b}" | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1)"
  [ "${hi}" = "${a}" ]
}

# awscli_min_glibc <version> : documented manylinux floor (2.17 / 2.5 / unknown).
awscli_min_glibc() {
  local v="${1:-}"
  [ -n "${v}" ] || { printf 'unknown'; return 0; }
  case "${v}" in *[!0-9.]*|.*|*.) printf 'unknown'; return 0 ;; esac
  if awscli_ge "${v}" "2.17.50"; then printf '2.17'; else printf '2.5'; fi
}

# awscli_in_scope <version> <full> : v2 filter (major == 2). <full> is accepted
# for parity with the SSM/ENA matrices and ignored here.
awscli_in_scope() {
  local v="${1:-}" maj
  maj="${v%%.*}"
  [ "${maj}" = "2" ]
}

# awscli_verdict <os_glibc> <min_glibc> <ran> : per-(major,version) EMPIRICAL
# headline. runs (installed + ran) / glibc-too-old (no run, os<floor) /
# unexpected-fail (no run BUT os>=floor -> investigate, not glibc).
awscli_verdict() {
  local osg="${1:-}" ming="${2:-}" ran="${3:-false}"
  if [ "${ran}" = "true" ]; then printf 'runs'; return 0; fi
  if [ -n "${ming}" ] && [ "${ming}" != "unknown" ] && [ -n "${osg}" ] && ! awscli_ge "${osg}" "${ming}"; then
    printf 'glibc-too-old'
  else
    printf 'unexpected-fail'
  fi
}

# rhel_glibc <major> : the MEASURED per-major glibc (the design plan sec 3.2).
rhel_glibc() {
  case "${1:-}" in
    10) printf '2.39' ;;
    9)  printf '2.34' ;;
    8)  printf '2.28' ;;
    7)  printf '2.17' ;;
    6)  printf '2.12' ;;
    *)  printf 'unknown' ;;
  esac
}

# awscli_band <version> : which manylinux band a version ships in (documents the
# min glibc). manylinux2014 (>=2.17.50) / manylinux1 (<=2.17.49) / unknown.
awscli_band() {
  case "$(awscli_min_glibc "$1")" in
    2.17) printf 'manylinux2014' ;;
    2.5)  printf 'manylinux1' ;;
    *)    printf 'unknown' ;;
  esac
}

# awscli_expected <os_glibc> <min_glibc> : the glibc-MODEL prediction (no run).
# runs (os>=floor) / glibc-too-old (os<floor) / unknown (floor unknown). This is
# what RESULTS shows before a live run; awscli_verdict is the empirical truth.
awscli_expected() {
  local osg="${1:-}" ming="${2:-}"
  { [ -n "${ming}" ] && [ "${ming}" != "unknown" ]; } || { printf 'unknown'; return 0; }
  if awscli_ge "${osg}" "${ming}"; then printf 'runs'; else printf 'glibc-too-old'; fi
}

# python_eol <X.Y[.Z]> : bundled-CPython minor -> documented EOL date (static).
python_eol() {
  local v="${1:-}" maj min mm
  maj="${v%%.*}"; min="${v#*.}"; min="${min%%.*}"
  case "${maj}" in ''|*[!0-9]*) printf 'unknown'; return 0 ;; esac
  case "${min}" in ''|*[!0-9]*) printf 'unknown'; return 0 ;; esac
  mm="${maj}.${min}"
  case "${mm}" in
    3.6)  printf '2021-12-23' ;;
    3.7)  printf '2023-06-27' ;;
    3.8)  printf '2024-10-07' ;;
    3.9)  printf '2025-10-31' ;;
    3.10) printf '2026-10-31' ;;
    3.11) printf '2027-10-31' ;;
    3.12) printf '2028-10-31' ;;
    3.13) printf '2029-10-31' ;;
    3.14) printf '2030-10-31' ;;
    *)    printf 'unknown' ;;
  esac
}

# --- releases.json readers (stdlib python3; the file is small + static) -------

# releases_versions : print in-scope v2 versions (ascending) from RELEASES.
releases_versions() {
  [ -f "${RELEASES}" ] || return 1
  python3 - "${RELEASES}" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
for x in d.get("versions",[]):
    v=x.get("version","")
    if v.split(".")[0:1]==["2"]:
        print(v)
PY
}

# ledger_ran <major> <version> : print 'true'/'false' if the ledger has a row for
# (major,version), else empty (no live run yet).
ledger_ran() {
  local major="$1" ver="$2"
  [ -f "${LEDGER}" ] || return 0
  python3 - "${LEDGER}" "${major}" "${ver}" <<'PY' 2>/dev/null || true
import json,sys
try:
    d=json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
maj,ver=sys.argv[2],sys.argv[3]
for r in d.get("results",[]):
    if str(r.get("osmajor"))==maj and r.get("awscli_version")==ver:
        print("true" if r.get("ran") else "false"); break
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
  local major="$1" osg img out v ming exp ran verdict n_current n_legacy
  osg="$(rhel_glibc "${major}")"
  case "${major}" in
    10) img="ubi10/ubi-init (10.2)" ;; 9) img="ubi9/ubi-init (9.8)" ;;
    8)  img="ubi8/ubi-init (8.10)" ;;  7) img="ubi7/ubi-init (7.9)" ;;
    6)  img="rhel6/rhel (6.10)" ;;     *) img="(unknown)" ;;
  esac
  out="${RESULTS_DIR}/RESULTS-rhel${major}.md"

  n_current=0; n_legacy=0
  while IFS= read -r v; do
    [ -n "${v}" ] || continue
    case "$(awscli_band "${v}")" in
      manylinux2014) n_current=$(( n_current + 1 )) ;;
      manylinux1)    n_legacy=$(( n_legacy + 1 )) ;;
    esac
  done < <(releases_versions || true)

  {
    printf '# AWS CLI v2 - RHEL %s install/run results\n\n' "${major}"
    printf '> GENERATED by run-awscli-installtest-matrix.sh - do not hand-edit.\n'
    printf '> The "expected" column is the glibc model; the "empirical" column is\n'
    printf '> filled by the L3 \140--run\140 matrix on a container-egress host.\n\n'
    printf '| Field | Value |\n|:--|:--|\n'
    printf '| OS major | RHEL %s |\n' "${major}"
    printf '| Image (measured) | \140%s\140 |\n' "${img}"
    printf '| OS glibc (measured) | **%s** |\n' "${osg}"
    printf '| AWS CLI v2 axis | glibc only (self-contained bundle) |\n'
    printf '| In-scope v2 versions | %s |\n\n' "$(releases_versions 2>/dev/null | grep -c . || printf '0')"

    printf '_Collected on (this run): %s_\n\n' "$(ledger_host_line)"
    printf '## Why this matters - AWS CLI v2 glibc support\n\n'
    printf 'AWS CLI v2 ships a self-contained zip bundle that BUNDLES its own Python, so it does not use the OS Python - but the bundled interpreter and its shared objects are built against a **manylinux glibc**, so the OS **glibc** gates whether the bundle installs and runs. Per AWS *Linux Support Updates for AWS CLI v2* (2024-09-16), current v2 is built on **manylinux2014 (glibc 2.17)** and supports glibc >= 2.17; systems on glibc <= 2.16 should pin v2 **<= 2.17.49**. This report characterizes, per RHEL %s environment, which v2 versions install + run - i.e. the newest AWS CLI v2 a RHEL %s image can actually use.\n\n' "${major}" "${major}"
    printf 'References (AWS): [Linux support updates](https://aws.amazon.com/blogs/developer/linux-support-updates-for-aws-cli-v2/); [install AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html); [a specific version](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-version.html).\n\n'

    printf '## glibc model (AWS policy 2024-09-16)\n\n'
    printf -- '- \140>= 2.17.50\140 -> manylinux2014, needs glibc **2.17**\n'
    printf -- '- \140<= 2.17.49\140 -> manylinux1, needs glibc **2.5**\n\n'
    printf 'On RHEL %s (glibc %s): current versions (>= 2.17.50) are **%s**; ' "${major}" "${osg}" "$(awscli_expected "${osg}" 2.17)"
    printf 'the legacy band (<= 2.17.49) **runs** (floor 2.5).\n\n'
    printf '| Band | min glibc | expected on RHEL %s | in-scope count |\n' "${major}"
    printf '|:--|:--|:--|--:|\n'
    printf '| current \140>=2.17.50\140 | 2.17 | %s | %s |\n' "$(awscli_expected "${osg}" 2.17)" "${n_current}"
    printf '| legacy \140<=2.17.49\140 | 2.5 | %s | %s |\n\n' "$(awscli_expected "${osg}" 2.5)" "${n_legacy}"

    printf '## boundary versions (empirical = filled by L3)\n\n'
    printf '| version | band | min glibc | os glibc | expected | empirical | verdict |\n'
    printf '|:--|:--|:--|:--|:--|:--|:--|\n'
    for v in 2.0.0 2.17.49 2.17.50 2.27.0; do
      ming="$(awscli_min_glibc "${v}")"
      exp="$(awscli_expected "${osg}" "${ming}")"
      ran="$(ledger_ran "${major}" "${v}")"
      if [ -n "${ran}" ]; then verdict="$(awscli_verdict "${osg}" "${ming}" "${ran}")"; else ran="pending"; verdict="pending"; fi
      printf '| %s | %s | %s | %s | %s | %s | %s |\n' \
        "${v}" "$(awscli_band "${v}")" "${ming}" "${osg}" "${exp}" "${ran}" "${verdict}"
    done
    printf '\n_Boundary set is illustrative; the L3 run records every in-scope version into the ledger._\n\n'

    printf '## Bundled Python runtime support\n\n'
    printf 'AWS CLI v2 BUNDLES its own CPython; that interpreter is **frozen** and not independently patchable - the only way to move to a newer (still-supported) Python is to move to a newer AWS CLI v2 version. On a glibc-capped OS the AWS CLI version is capped, so the bundled Python is capped too, and at its end-of-life there is no in-place remediation. The r09 installer records each tested bundle as \140bundled_python\140 (with the empirical \140min_glibc_measured\140); the L3 run fills them per version.\n\n'
    printf 'Python end-of-life (security-support end) - STATIC table, **verified 2026-06-17** from endoflife.date/python, eosl.date, eol.wiki/python. Compare against today to read supported vs EOL:\n\n'
    printf '| Python | EOL (security-support end) |\n|---|---|\n'
    printf '| 3.6 | 2021-12-23 |\n| 3.7 | 2023-06-27 |\n| 3.8 | 2024-10-07 |\n| 3.9 | 2025-10-31 |\n| 3.10 | 2026-10-31 |\n| 3.11 | 2027-10-31 |\n| 3.12 | 2028-10-31 |\n| 3.13 | 2029-10-31 |\n| 3.14 | 2030-10-31 |\n'

    printf '\n## RHEL %s support (the OS itself)\n\n' "${major}"
    printf 'STATIC, **verified 2026-07-01** from the Red Hat Customer Portal RHEL Life Cycle / errata-policy pages. The OS may itself be past regular support, which is independent of whether AWS CLI v2 installs/runs:\n\n'
    case "${major}" in
      6)  printf -- '- Maintenance Support ended **2020-11-30**; the ELS Add-On ended **2024-06-30** - now in the Extended Life Phase (no security/bug fixes).\n' ;;
      7)  printf -- '- Maintenance Support ended **2024-06-30**; ELS Add-On available through **2029-05-31** (last minor 7.9).\n' ;;
      8)  printf -- '- Full Support ended **2024-05-31**; Maintenance Support through **2029-05-31** (last minor 8.10).\n' ;;
      9)  printf -- '- Full Support through **2027-05-31**; Maintenance Support through **2032-05-31**.\n' ;;
      10) printf -- '- GA **2025-05-20**; Full Support through ~**2030-05-31**; Maintenance Support through ~**2035-05-31**.\n' ;;
      *)  printf -- '- (lifecycle unknown)\n' ;;
    esac
    printf '\n_Lifecycle is independent of AWS CLI compatibility: a supported OS can still cap the AWS CLI via glibc, and an out-of-support OS may still run a pinned bundle._\n'
  } > "${out}"
  log "wrote ${out}"
}

generate_results() {
  local m
  for m in 6 7 8 9 10; do generate_results_for "${m}"; done
}

# --- (b) L3 install-test loop (container egress required) ---------------------
# One disposable container per (major,version): acquire rootfs, install the AWS
# CLI v2 bundle, smoke `aws --version`, emit a [result] JSON, append to LEDGER.
# Deferred to CI / a podman+egress host (no podman or bundle CDN in the sandbox).
# result_field <result-json-line> <key> : extract a value from an install
# script's single-line [installtest][result] JSON (string, bool, or number).
# Pure, jq-free; the matrix uses it to read the raw facts the install script
# emits, then applies the verdict helper. Reuse-by-copy across the tool matrices.
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
  "tool": "aws_awscli-v2",
  "note": "Empirical install-test ledger. Created/appended by run-awscli-installtest-matrix.sh on a container-egress host (L3); never hand-edited.",
  "results": []
}
JSON
  log "created ledger skeleton: ${LEDGER}"
}

# persist_ledger <rows-file> : fold the swept JSONL rows into ${LEDGER}'s results[]
# (dedup by osmajor+awscli_version; last write wins). Atomic tmp+replace.
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
def key(r): return (str(r.get("osmajor")), r.get("awscli_version"))
merged={}
for r in d.get("results",[]): merged[key(r)]=r
for r in rows: merged[key(r)]=r
d["results"]=[merged[k] for k in sorted(merged, key=lambda k:(int(k[0]) if str(k[0]).isdigit() else 0, k[1] or ""))]
fd,tmp=tempfile.mkstemp(dir=os.path.dirname(led) or ".")
with os.fdopen(fd,"w") as fh: json.dump(d,fh,indent=2); fh.write("\n")
os.replace(tmp,led)
PY2
  log "ledger updated: ${LEDGER} ($(grep -c '"awscli_version"' "${rows}") rows)"
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
  local majors="${OSMAJORS:-10 9 8 7 6}" major ver ref rows_tmp
  rows_tmp="$(mktemp)"
  for major in ${majors}; do
    ref="$(acq_ref_for_major "${major}")" || { log "skip RHEL${major}: no ref"; continue; }
    while IFS= read -r ver; do
      [ -n "${ver}" ] || continue
      awscli_in_scope "${ver}" 0 || continue
      awscli_kick "${major}" "${ver}" "${ref}" "${LOG_DIR}" "${rows_tmp}"
    done < <(releases_versions || true)
  done
  persist_ledger "${rows_tmp}"
  rm -f "${rows_tmp}"
}

# awscli_kick <major> <ver> <ref> <log_dir> <rows_file> : install-test one
# (major, version) in a container, record the row (+reason), and on non-ok
# preserve the container output to <log_dir> (fail/error only).
awscli_kick() {
  local major="$1" ver="$2" ref="$3" log_dir="$4" rows="$5"
  local err_tmp out line ran iv status bpy mgl reason row logf rc=0
  err_tmp="$(mktemp)"
  out="$(timeout "${RUN_TIMEOUT:-600}" podman run --rm \
          -v "${INSTALL_SCRIPT}:/install-aws_awscli-v2.sh:ro,z" \
          -e AWSCLI_INSTALLTEST=1 -e "AWSCLI_VERSION=${ver}" -e "INSECURE_TLS=${INSECURE_TLS:-0}" \
          "${ref}" /bin/bash /install-aws_awscli-v2.sh 2>"${err_tmp}")" || rc=$?
  line="$(printf '%s
' "${out}" | grep -F '[aws_awscli-v2][installtest][result]' | tail -1)"
  logf="${log_dir}/installtest-rhel${major}-awscli_${ver}.log"
  if [ "${rc}" = "124" ]; then
    reason="timed out after ${RUN_TIMEOUT:-600}s (container stalled; possible repo/network wait)"
    status=error
    log "RHEL${major} ${ver}: TIMEOUT -> ${reason}"
    row="$(printf '{"status":"error","osmajor":"%s","awscli_version":"%s","glibc":"%s","ran":false,"installed_version":"","bundled_python":"","min_glibc_measured":"","verdict":"harness-error","reason":"%s"}' \
      "${major}" "${ver}" "$(rhel_glibc "${major}")" "$(jesc "${reason}")")"
  elif [ -z "${line}" ]; then
    reason="$(python3 -c 'import sys,json; print(json.dumps(" ".join(open(sys.argv[1]).read().split()))[1:-1][:300])' "${err_tmp}" 2>/dev/null || true)"
    [ -n "${reason}" ] || reason="container produced no [result] and no stderr"
    status=error
    log "RHEL${major} ${ver}: harness-error -> ${reason}"
    row="$(printf '{"status":"error","osmajor":"%s","awscli_version":"%s","glibc":"%s","ran":false,"installed_version":"","bundled_python":"","min_glibc_measured":"","verdict":"harness-error","reason":"%s"}' \
      "${major}" "${ver}" "$(rhel_glibc "${major}")" "${reason}")"
  else
    ran="$(result_field "${line}" ran)"; [ "${ran}" = "true" ] || ran=false
    iv="$(result_field "${line}" installed_version)"
    status="$(result_field "${line}" status)"; [ -n "${status}" ] || status=unknown
    bpy="$(result_field "${line}" bundled_python)"
    mgl="$(result_field "${line}" min_glibc_measured)"
    reason="$(jesc "$(result_field "${line}" reason)")"
    row="$(printf '{"status":"%s","osmajor":"%s","awscli_version":"%s","glibc":"%s","ran":%s,"installed_version":"%s","bundled_python":"%s","min_glibc_measured":"%s","verdict":"%s","reason":"%s"}' \
      "${status}" "${major}" "${ver}" "$(rhel_glibc "${major}")" "${ran}" "${iv}" "${bpy}" "${mgl}" \
      "$(awscli_verdict "$(rhel_glibc "${major}")" "$(awscli_min_glibc "${ver}")" "${ran}")" "${reason}")"
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
# No-arg default = the full install-test: run the matrix (all majors x every
# in-scope version), persist the ledger, then regenerate RESULTS. Mirrors the OL
# model's one-script workflow.
#   --run              : run the matrix + persist the ledger only (needs podman/L3)
#   --generate-results : (re)generate the reports only, hermetic (no containers)
ACTION="all"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --run)              ACTION="run" ;;
    --generate-results) ACTION="generate-results" ;;
    --releases)         RELEASES="${2:-}"; shift ;;
    --ledger)           LEDGER="${2:-}"; shift ;;
    --results-dir)      RESULTS_DIR="${2:-}"; shift ;;
    -h|--help)          sed -n '2,40p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) log "unknown option: $1"; exit 2 ;;
  esac
  shift
done

case "${ACTION}" in
  all)              run_matrix || log "run step did not complete (see above); writing reports from the current ledger"; generate_results ;;
  run)              run_matrix ;;
  generate-results) generate_results ;;
esac
