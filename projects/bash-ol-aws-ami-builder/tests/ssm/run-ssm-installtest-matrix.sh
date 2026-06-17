#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# run-ssm-installtest-matrix.sh -- AWS SSM Agent install+run test matrix
# ----------------------------------------------------------------------------
# Structurally the SAME as tests/ena/run-ena-buildtest-matrix.sh. Self-contained
# (no shared library). For each OL major (6/7/8) it determines, in a disposable
# clean-core container, which SSM Agent versions INSTALL and RUN on this
# (kernel, glibc), and evaluates compatibility against the AWS requirement
#   SSM Agent >= 3.3.3598.0
# (from 2026-06-16 SSM Run Command drops the legacy ec2messages endpoint; agents
# >= 3.3.3598.0 use ssmmessages). It drives:
#   * tests/cleancore/build-cleancore.sh   (-> the clean-core rootfs per OL)
#   * install-ssm-agent.sh SSM_INSTALLTEST=1  (-> the per-version install+run test)
#
# WHAT IS / IS NOT FAITHFUL IN A CONTAINER (verified 2026-06-14):
#   * glibc axis  -- HIGH fidelity: the container's real OL glibc gates a DYNAMIC
#     version's install/run, so a too-new-glibc version fails for real.
#   * kernel axis -- NOT faithful in a container: the container shares the host
#     kernel, so the binary executes on the RUNNER's kernel (recorded as
#     `test_host_kernel`), not the OL's UEK, and the Go runtime's minimum-kernel
#     never trips on a modern runner. `kver` is the OL UEK, provisioned into the
#     container and read from the rpm db (`rpm -q kernel-uek`, the same install-
#     at-test-time path the ENA matrix uses) so the report records the kernel a
#     real OL instance runs; instead of pretending the run tested it, the matrix
#     surfaces a STATIC kernel-axis proxy from each release's go.mod `go` directive
#     (see go_min_kernel + the release list's go_version). The faithful kernel
#     verdict needs a kernel-matched runner or a real instance (the B-T8 analog).
#
# Modes (the version filter):
#   * default -- test only versions that MEET the AWS minimum (>= MIN_SSM_VERSION,
#     default 3.3.3598.0; the boundary itself IS tested). Below-minimum versions
#     (ec2messages-only / deprecated) are skipped: they cannot satisfy the
#     requirement, so the default run answers "is remediation possible here?".
#   * --full  -- test EVERY version. Use when the default run finds NOTHING that
#     installs+runs (all-NG): the full ladder shows where (kernel, glibc) caps out
#     (likely < the minimum -> ec2messages-only / non-remediable, a detailed ledger).
#
# Ledger dedup key (osmajor, ssm_version, kver), kver PRIMARY -- kver is the OL
# UEK (rpm -q kernel-uek), so a new OL UEK re-tests all versions, mirroring the
# ENA matrix; test_host_kernel + glibc + go_version recorded per entry.
#
# Usage:
#   bash tests/ssm/run-ssm-installtest-matrix.sh [options]
# Options:
#   --ol <list>            OL majors to test, comma/space (default: 6,7,8,9,10)
#   --ssm-versions <list>  SSM versions to test, comma/space (default: all in the
#                          release-list JSON, filtered by the mode below)
#   --full                 test EVERY version (default: only >= MIN_SSM_VERSION)
#   --min-version <ver>    the AWS-minimum threshold (default: 3.3.3598.0)
#   --ledger <path>        ledger JSON (default: tests/ssm/ssm-installtest-ledger.json)
#   --results-dir <dir>    where RESULTS-ol<N>.md are written (default: tests/ssm)
#   --cleancore-dir <dir>  holds/receives cleancore-ol<N>.tar.gz (default: ./cleancore-out)
#   --work-dir <dir>       clean-core BUILD scratch base; each OL builds under
#                          <dir>/cleancore-ol<N> and it is rm -rf'd on completion.
#                          Explicit + per-driver so concurrent ENA/SSM runs never
#                          collide (default: ${TMPDIR:-/tmp}/cleancore-work-ssm-installtest).
#   --releases <path>      release-list JSON (default: tests/ssm/ssm-agent-releases.json)
#   --rebuild-cleancore    rebuild the clean-core rootfs even if present
#   --preflight-retries <n>  QA-preflight retries on a transient failure (default: 2)
#   --strict               update-gate probe failure is fail-closed (skip the OL)
#   --force                bypass the update gate (run every OL) and the ledger dedup
#   -h | --help
# Env (passed through): INSECURE_TLS (default 1 here, for the sandbox; set 0 on a
#   trusted host). Requires: root, unshare, chroot, tar, curl, python3, and the
#   clean-core builder toolchain.
# Exit: 0 = the matrix ran and the ledger/reports were written (individual
#   install pass/fail is recorded as evidence, NOT a harness error); non-zero =
#   a harness / infrastructure failure.
# ----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ORCHESTRATOR="${SCRIPT_DIR}/../cleancore/build-cleancore.sh"
INSTALL_SCRIPT="${PROJ_DIR}/install-ssm-agent.sh"

OL_LIST="6 7 8 9 10"
SSM_VERSIONS=""
FULL=0
MIN_SSM_VERSION="3.3.3598.0"
LEDGER="${SCRIPT_DIR}/ssm-installtest-ledger.json"
RESULTS_DIR="${SCRIPT_DIR}"
CLEANCORE_DIR="./cleancore-out"
WORK_BASE=""
RELEASES="${SCRIPT_DIR}/ssm-agent-releases.json"
REBUILD_CLEANCORE=0
FORCE=0
STRICT=0
PREFLIGHT_RETRIES=2
INSECURE_TLS="${INSECURE_TLS:-1}"
SSM_REPO_URL="${SSM_REPO_URL:-https://github.com/aws/amazon-ssm-agent.git}"

log()  { printf '%s [ssm-matrix] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
warn() { log "WARNING: $*" >&2; }
die()  { log "ERROR: $*" >&2; exit 1; }
hr()   { log "================================================================"; }

# pinned QA-preflight version per OL major (a known-good smoke version).
pin_for() { case "$1" in 6) echo 3.0.1479.0 ;; 7|8|9|10) echo 3.3.3598.0 ;; *) echo "" ;; esac; }

# ===========================================================================
# Pure helpers (no I/O) -- unit-tested by tests/t018_ssmverdict.sh. Keep each a
# column-0 function from its definition line to the first column-0 '}'.
# ===========================================================================

# ssm_ge <a> <b> : exit 0 iff dotted-numeric version a >= b (up to 4 parts).
ssm_ge() {
  local a="$1" b="$2" hi
  [ "${a}" = "${b}" ] && return 0
  hi="$(printf '%s\n%s\n' "${a}" "${b}" | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1)"
  [ "${hi}" = "${a}" ]
}

# go_min_kernel <go_version> : map a go.mod 'go' directive (e.g. 1.24) to the Go
# toolchain's published MINIMUM Linux kernel (the kernel-axis proxy). Approximate
# by design; empty -> "unknown". OL6 UEK4 (4.1.12) satisfies every value here.
go_min_kernel() {
  local gov="${1:-}" maj min
  [ -n "${gov}" ] || { printf 'unknown'; return 0; }
  maj="${gov%%.*}"; min="${gov#*.}"; min="${min%%.*}"
  case "${maj}" in ''|*[!0-9]*) printf 'unknown'; return 0 ;; esac
  case "${min}" in ''|*[!0-9]*) min=0 ;; esac
  if [ "${maj}" -gt 1 ]; then printf '3.2'; return 0; fi
  if   [ "${min}" -ge 21 ]; then printf '3.2'
  elif [ "${min}" -ge 18 ]; then printf '2.6.32'
  else printf '2.6.23'; fi
}

# ssm_in_scope <ver> <min> <full> : exit 0 iff this version is tested in this mode
# (full=1 -> always; else only ver >= min).
ssm_in_scope() {
  [ "${3:-0}" = "1" ] && return 0
  ssm_ge "${1}" "${2}"
}

# ssm_compliance <max_install_run_ver> <min> : the headline verdict.
#   none              -> nothing installed+ran
#   compliant-capable -> max install+run version >= min (remediation possible)
#   ec2messages-only  -> max install+run version <  min (cannot meet the requirement)
ssm_compliance() {
  if [ -z "${1:-}" ]; then printf 'none'; return 0; fi
  if ssm_ge "${1}" "${2}"; then printf 'compliant-capable'; else printf 'ec2messages-only'; fi
}

# ---- args ------------------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ol)                OL_LIST="${2:-}"; shift ;;
    --ssm-versions)      SSM_VERSIONS="${2:-}"; shift ;;
    --full)              FULL=1 ;;
    --min-version)       MIN_SSM_VERSION="${2:-}"; shift ;;
    --ledger)            LEDGER="${2:-}"; shift ;;
    --results-dir)       RESULTS_DIR="${2:-}"; shift ;;
    --cleancore-dir)     CLEANCORE_DIR="${2:-}"; shift ;;
    --work-dir)          WORK_BASE="${2:-}"; shift ;;
    --releases)          RELEASES="${2:-}"; shift ;;
    --rebuild-cleancore) REBUILD_CLEANCORE=1 ;;
    --preflight-retries) PREFLIGHT_RETRIES="${2:-}"; shift ;;
    --strict)            STRICT=1 ;;
    --force)             FORCE=1 ;;
    -h|--help)           sed -n '2,/^# ---.*$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)                   die "unknown argument: $1 (-h for help)" ;;
  esac
  shift
done
OL_LIST="${OL_LIST//,/ }"
SSM_VERSIONS="${SSM_VERSIONS//,/ }"

# ---- pre-flight ------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "must run as root (clean-core build + unshare/chroot need it)."
# Irregular-placement guard: a script resolving to '/' (or empty) would make the
# clean-core build scratch root-level, and the builder does `rm -rf` on it -- refuse.
case "${SCRIPT_DIR}" in
  ""|/) die "refusing to run: matrix script resolves to '${SCRIPT_DIR:-<empty>}' (irregular placement; destructive clean-core cleanup could hit the OS root)." ;;
esac
for t in unshare chroot tar curl python3; do
  command -v "${t}" >/dev/null 2>&1 || die "missing required host tool: ${t}"
done
[ -f "${ORCHESTRATOR}" ]   || die "orchestrator not found: ${ORCHESTRATOR}"
[ -f "${INSTALL_SCRIPT}" ] || die "install-ssm-agent.sh not found: ${INSTALL_SCRIPT}"
# Explicit, per-driver clean-core BUILD scratch base (NOT the source tree, NOT the
# shared /tmp/cleancore-ol<N>): so concurrent ENA/SSM runs never collide. The
# builder rm -rf's <base>/cleancore-ol<N>, so refuse any root-level resolution.
WORK_BASE="${WORK_BASE:-${TMPDIR:-/tmp}/cleancore-work-ssm-installtest}"
case "${WORK_BASE}" in ""|/|//) die "refusing to run: --work-dir resolves to '${WORK_BASE:-<empty>}' (would risk destructive cleanup)." ;; esac
mkdir -p "${WORK_BASE}"; WORK_BASE="$(cd "${WORK_BASE}" && pwd)"
[ "${WORK_BASE}" = "/" ] && die "refusing to run: --work-dir resolved to '/'."

# ---- the version list for an OL (from --ssm-versions, else the releases JSON),
# filtered by the mode (default >= MIN_SSM_VERSION; --full = all). -------------
versions_for_ol() {
  local raw=""
  if [ -n "${SSM_VERSIONS}" ]; then
    raw="${SSM_VERSIONS}"
  elif [ -f "${RELEASES}" ]; then
    raw="$(python3 -c "import json,sys
d=json.load(open(sys.argv[1]))
print(' '.join(v['version'] for v in d.get('versions',[])))" "${RELEASES}" 2>/dev/null || true)"
  fi
  local v out=""
  for v in ${raw}; do
    if ssm_in_scope "${v}" "${MIN_SSM_VERSION}" "${FULL}"; then out="${out} ${v}"; fi
  done
  printf '%s' "${out# }"
}

# go_version for a version, read from the releases JSON (empty if absent/unknown).
go_version_of() {
  [ -f "${RELEASES}" ] || { printf ''; return 0; }
  python3 -c "import json,sys
d=json.load(open(sys.argv[1]))
g={v['version']:(v.get('go_version') or '') for v in d.get('versions',[])}
print(g.get(sys.argv[2],''))" "${RELEASES}" "$1" 2>/dev/null || true
}

# ---- run ONE install+run test for (ol, version) against a clean-core tarball;
# echo the raw [result] JSON object (or empty if the test emitted none). ------
run_one_installtest() {
  local ol="$1" ver="$2" tarball="$3" outlog="$4" img
  img="$(mktemp -d)"
  tar -C "${img}" -xzf "${tarball}"
  cp /etc/resolv.conf "${img}/etc/resolv.conf" 2>/dev/null || true
  cp "${INSTALL_SCRIPT}" "${img}/install-ssm-agent.sh"
  unshare --fork --pid --mount --uts --ipc -- bash -c "
    export PATH=/usr/sbin:/usr/bin:/sbin:/bin
    mount --bind /dev '${img}/dev'
    mount -t proc proc '${img}/proc'
    mount -t sysfs sys '${img}/sys'
    export SSM_INSTALLTEST=1 SSM_AGENT_VERSION='${ver}' INSECURE_TLS='${INSECURE_TLS}'
    chroot '${img}' /bin/bash /install-ssm-agent.sh
  " > "${outlog}" 2>&1 || true
  rm -rf "${img}"
  { grep -E '\[ssm-agent\]\[installtest\]\[result\]' "${outlog}" || true; } | tail -1 | sed 's/^.*\[result\] //'
}

# ---- QA preflight: install+run ONLY the pinned version as a smoke test that the
# clean-core rootfs + install-ssm-agent.sh are healthy, before the full sweep.
# QA-only (NOT recorded in the ledger); a clear failure early-exits this OL. -----
preflight_reason_is_transient() {
  printf '%s' "${1:-}" | grep -qiE 'RPM fetch failed|could not resolve|timed out|connection (refused|reset)|temporar|mirror'
}

preflight_qa() {
  local ol="$1" tarball="$2" pin attempt=1 max rjson st reason
  pin="$(pin_for "${ol}")"
  [ -n "${pin}" ] || { warn "OL${ol}: no QA pin; skipping preflight"; return 0; }
  max=$(( PREFLIGHT_RETRIES + 1 ))
  while [ "${attempt}" -le "${max}" ]; do
    log "OL${ol} QA preflight [${attempt}/${max}]: install+run pinned SSM ${pin}"
    local blog; blog="$(mktemp)"
    rjson="$(run_one_installtest "${ol}" "${pin}" "${tarball}" "${blog}" || true)"
    st="$(printf '%s' "${rjson}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || true)"
    reason="$(printf '%s' "${rjson}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('reason',''))" 2>/dev/null || true)"
    if [ "${st}" = "ok" ]; then rm -f "${blog}"; log "OL${ol} QA preflight OK (pinned ${pin})"; return 0; fi
    local keep="${CLEANCORE_DIR}/preflight-ol${ol}-FAILED.log"; cp -f "${blog}" "${keep}" 2>/dev/null || true; rm -f "${blog}"
    if preflight_reason_is_transient "${reason}" && [ "${attempt}" -lt "${max}" ]; then
      warn "OL${ol} QA preflight transient (${reason:-no-result}); retrying"; attempt=$(( attempt + 1 )); continue
    fi
    warn "OL${ol} QA preflight FAILED (pinned ${pin}: ${reason:-no-result}) -- log at ${keep}"
    return 1
  done
  return 1
}

# ---- update gate -----------------------------------------------------------
# UNLIKE the ENA matrix, SSM is NOT a kernel module: in a container the SSM agent
# runs on the host kernel (recorded as test_host_kernel), so its runnability does
# not depend on the OL UEK and a UEK-version gate would be misleading. The SSM
# gate is therefore the SSM-VERSION probe: run the OL if the latest upstream SSM
# version is newer than the highest the ledger has tested for it (or the OL has no
# ledger entry). A new OL UEK is still handled by the kver-PRIMARY ledger dedup
# (kver = rpm -q kernel-uek; a new UEK re-tests every version).
probe_latest_ssm() {
  git ls-remote --tags "${SSM_REPO_URL}" 2>/dev/null \
    | sed -E 's#.*refs/tags/v?##; s/\^\{\}$//' \
    | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1
}

ledger_max_ssm_for_ol() {
  [ -f "${LEDGER}" ] || { printf ''; return 0; }
  python3 -c "import json,sys
d=json.load(open(sys.argv[1])); ol=sys.argv[2]
vs=[e['ssm_version'] for e in d.get('entries',[]) if e.get('osmajor')==ol]
def key(s):
  p=(s.split('.')+['0','0','0','0'])[:4]
  return tuple(int(x) if x.isdigit() else 0 for x in p)
print(sorted(vs,key=key)[-1] if vs else '')" "${LEDGER}" "$1" 2>/dev/null || true
}

gate_should_run_ol() {
  local ol="$1" latest maxled
  [ "${FORCE}" = "1" ] && { log "OL${ol}: --force -> running (gate bypassed)"; return 0; }
  latest="$(probe_latest_ssm || true)"
  if [ -z "${latest}" ]; then
    if [ "${STRICT}" = "1" ]; then warn "OL${ol}: SSM-version probe failed; --strict -> SKIP"; return 1; fi
    warn "OL${ol}: SSM-version probe failed; fail-open -> running"; return 0
  fi
  maxled="$(ledger_max_ssm_for_ol "${ol}")"
  if [ -z "${maxled}" ]; then log "OL${ol}: no ledger entry -> running"; return 0; fi
  if ssm_ge "${maxled}" "${latest}"; then
    log "OL${ol}: ledger covers latest SSM ${latest} (max tested ${maxled}) -> SKIP"; return 1
  fi
  log "OL${ol}: newer SSM available (${latest} > ledger max ${maxled}) -> running"; return 0
}

# ---- run the matrix --------------------------------------------------------
RESULTS_TSV="$(mktemp)"   # one row per attempted test: ol \t version \t result-json
trap 'rm -f "${RESULTS_TSV}"' EXIT

mkdir -p "${CLEANCORE_DIR}"
ol_total=0; g_ol_ran=0; g_ol_skipped=0; g_ok=0; g_fail=0; g_skip=0; g_tests=0
for ol in ${OL_LIST}; do ol_total=$(( ol_total + 1 )); done

for ol in ${OL_LIST}; do
  case "${ol}" in 6|7|8|9|10) : ;; *) warn "OL${ol}: wired for OL6/7/8/9/10 only; skipping."; g_ol_skipped=$(( g_ol_skipped + 1 )); continue ;; esac

  if ! gate_should_run_ol "${ol}"; then g_ol_skipped=$(( g_ol_skipped + 1 )); continue; fi

  tarball="${CLEANCORE_DIR}/cleancore-ol${ol}.tar.gz"
  if [ "${REBUILD_CLEANCORE}" = "1" ] || [ ! -f "${tarball}" ]; then
    log "OL${ol}: building clean-core rootfs -> ${tarball}"
    INSECURE_TLS="${INSECURE_TLS}" bash "${ORCHESTRATOR}" --ol "${ol}" --out-dir "${CLEANCORE_DIR}" --work-dir "${WORK_BASE}" \
      || die "OL${ol}: clean-core build failed"
  fi
  [ -f "${tarball}" ] || die "OL${ol}: clean-core tarball missing after build: ${tarball}"

  if ! preflight_qa "${ol}" "${tarball}"; then
    warn "OL${ol}: QA preflight failed -> skipping the OL (ledger untouched)"; g_ol_skipped=$(( g_ol_skipped + 1 )); continue
  fi
  g_ol_ran=$(( g_ol_ran + 1 ))

  vlist="$(versions_for_ol)"
  if [ -z "${vlist}" ]; then
    warn "OL${ol}: no in-scope versions (mode: $( [ "${FULL}" = 1 ] && echo full || echo ">=${MIN_SSM_VERSION}" )); nothing to test"
    continue
  fi
  total=0; for _v in ${vlist}; do total=$(( total + 1 )); done
  log "OL${ol}: testing ${total} version(s) (mode: $( [ "${FULL}" = 1 ] && echo full || echo ">=${MIN_SSM_VERSION}" ))"

  live_kver=""; idx=0; ol_ok=0; ol_fail=0; ol_skip=0
  for ver in ${vlist}; do
    idx=$(( idx + 1 ))
    if [ "${FORCE}" != "1" ] && [ -n "${live_kver}" ] && [ -f "${LEDGER}" ]; then
      if python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
k=(sys.argv[2],sys.argv[3],sys.argv[4])
sys.exit(0 if any((e['osmajor'],e['ssm_version'],e['kver'])==k for e in d.get('entries',[])) else 1)
" "${LEDGER}" "${ol}" "${ver}" "${live_kver}"; then
        log "OL${ol} [${idx}/${total}] SSM ${ver}: SKIP (already in ledger for kver ${live_kver})"
        ol_skip=$(( ol_skip + 1 )); continue
      fi
    fi
    log "OL${ol} [${idx}/${total}] SSM ${ver}: install+run test..."
    tlog="$(mktemp)"
    rjson="$(run_one_installtest "${ol}" "${ver}" "${tarball}" "${tlog}" || true)"
    if [ -z "${rjson}" ]; then
      rjson="{\"status\":\"fail\",\"osmajor\":\"${ol}\",\"ssm_version\":\"${ver}\",\"kver\":\"${live_kver}\",\"test_host_kernel\":\"\",\"glibc\":\"\",\"installed_version\":\"\",\"ran\":false,\"run_method\":\"\",\"reason\":\"no result line (infrastructure error)\"}"
    fi
    st="$(printf '%s' "${rjson}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || true)"
    if [ "${st}" != "ok" ]; then
      keep="${CLEANCORE_DIR}/installtest-ol${ol}-ssm_${ver}.log"; cp -f "${tlog}" "${keep}" 2>/dev/null || true
      warn "OL${ol} [${idx}/${total}] SSM ${ver}: ${st:-no-result} -- log preserved at ${keep}"
      ol_fail=$(( ol_fail + 1 ))
    else
      ol_ok=$(( ol_ok + 1 ))
    fi
    rm -f "${tlog}"
    printf '%s\t%s\t%s\n' "${ol}" "${ver}" "${rjson}" >> "${RESULTS_TSV}"
    kv="$(printf '%s' "${rjson}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('kver',''))" 2>/dev/null || true)"
    [ -n "${kv}" ] && live_kver="${kv}"
    log "OL${ol} [${idx}/${total}] SSM ${ver}: ${st:-?} (kver ${live_kver:-?})"
  done
  log "---- OL${ol}: matrix done -- ${ol_ok} ok, ${ol_fail} fail, ${ol_skip} skipped (of ${total}) ----"
  g_ok=$(( g_ok + ol_ok )); g_fail=$(( g_fail + ol_fail )); g_skip=$(( g_skip + ol_skip )); g_tests=$(( g_tests + ol_ok + ol_fail ))
done

hr
log "SSM matrix complete -- ${g_ok} ok, ${g_fail} fail, ${g_skip} skipped across ${g_tests} test(s); OL ran ${g_ol_ran}, skipped ${g_ol_skipped} (of ${ol_total})"
hr

# ---- enrich each result row with go_version (from the release list) ---------
ENRICHED_TSV="$(mktemp)"
trap 'rm -f "${RESULTS_TSV}" "${ENRICHED_TSV}"' EXIT
if [ -s "${RESULTS_TSV}" ]; then
  while IFS=$'\t' read -r ol ver rjson; do
    gv="$(go_version_of "${ver}")"
    printf '%s\t%s\t%s\t%s\n' "${ol}" "${ver}" "${gv}" "${rjson}" >> "${ENRICHED_TSV}"
  done < "${RESULTS_TSV}"
fi

# ---- merge into the ledger + regenerate the per-OS Markdown -----------------
python3 - "${LEDGER}" "${ENRICHED_TSV}" "${RESULTS_DIR}" "${MIN_SSM_VERSION}" <<'PY'
import json, os, sys

ledger_path, tsv_path, results_dir, min_ver = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

def vkey(s):
    p = (str(s).split('.') + ['0','0','0','0'])[:4]
    return tuple(int(x) if str(x).isdigit() else 0 for x in p)

def ge(a, b):
    return vkey(a) >= vkey(b)

def go_min_kernel(gov):
    if not gov: return 'unknown'
    parts = str(gov).split('.')
    try:
        maj = int(parts[0]); minr = int(parts[1]) if len(parts) > 1 else 0
    except ValueError:
        return 'unknown'
    if maj > 1: return '3.2'
    if minr >= 21: return '3.2'
    if minr >= 18: return '2.6.32'
    return '2.6.23'

# load / init ledger
if os.path.exists(ledger_path):
    led = json.load(open(ledger_path))
else:
    led = {"schema_version": "1.0", "ledger_type": "ssm-installtest", "min_ssm_version": min_ver, "entries": []}
led.setdefault("entries", [])
led["min_ssm_version"] = min_ver

# index existing by (osmajor, ssm_version, kver) -- kver PRIMARY dedup
idx = {(e.get('osmajor'), e.get('ssm_version'), e.get('kver')): e for e in led["entries"]}

new_rows = 0
if os.path.exists(tsv_path):
    for line in open(tsv_path):
        line = line.rstrip('\n')
        if not line: continue
        ol, ver, gv, rjson = line.split('\t', 3)
        try:
            r = json.loads(rjson)
        except Exception:
            continue
        entry = {
            "osmajor": str(r.get('osmajor', ol)),
            "ssm_version": str(r.get('ssm_version', ver)),
            "kver": str(r.get('kver', '')),
            "test_host_kernel": str(r.get('test_host_kernel', '')),
            "glibc": str(r.get('glibc', '')),
            "go_version": gv or '',
            "min_kernel": go_min_kernel(gv or ''),
            "status": str(r.get('status', '')),
            "ran": bool(r.get('ran', False)),
            "installed_version": str(r.get('installed_version', '')),
            "run_method": str(r.get('run_method', '')),
            "reason": str(r.get('reason', '')),
        }
        idx[(entry['osmajor'], entry['ssm_version'], entry['kver'])] = entry
        new_rows += 1

led["entries"] = sorted(
    idx.values(),
    key=lambda e: (int(e['osmajor']) if str(e['osmajor']).isdigit() else 99, e.get('kver', ''), vkey(e['ssm_version']))
)
json.dump(led, open(ledger_path, 'w'), indent=2)
open(ledger_path, 'a').write('\n')

# per-OS RESULTS
by_ol = {}
for e in led["entries"]:
    by_ol.setdefault(e['osmajor'], []).append(e)

for ol, entries in by_ol.items():
    kvers = sorted({e.get('kver', '') for e in entries}, reverse=True)
    lines = []
    lines.append(f"# SSM Agent install+run matrix -- OL{ol}")
    lines.append("")
    lines.append("Generated by `tests/ssm/run-ssm-installtest-matrix.sh` from "
                 "`ssm-installtest-ledger.json` -- DO NOT hand-edit (regenerated each run).")
    lines.append("")
    lines.append("## Why this matters -- AWS Systems Manager Run Command deprecation")
    lines.append("")
    lines.append("Starting **2026-06-16**, SSM Run Command stops executing commands on managed instances that "
                 "still use the legacy **ec2messages** (Amazon Message Delivery Service) endpoints -- endpoints "
                 "used only by SSM Agents too old to support the newer **ssmmessages** (Amazon Message Gateway "
                 "Service) endpoints. AWS's remediation is to update the SSM Agent to "
                 f"**{min_ver} or newer** and grant the instance role the ssmmessages channel permissions "
                 "(`CreateControlChannel` / `CreateDataChannel` / `OpenControlChannel` / `OpenDataChannel`); "
                 "affected instances are listed in the AWS Health Dashboard. This report characterizes, per OL "
                 f"major, which agent versions install+run -- i.e. whether an OL{ol} image can be brought to a "
                 f"**compliant (>= {min_ver})** agent.")
    lines.append("")
    lines.append("References (AWS docs): "
                 "[Run Command](https://docs.aws.amazon.com/systems-manager/latest/userguide/run-command.html); "
                 "[message service endpoints](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-setting-up-messageAPIs.html#message-services); "
                 "[update SSM Agent](https://docs.aws.amazon.com/systems-manager/latest/userguide/run-command-tutorial-update-software.html); "
                 "[ssmmessages IAM actions](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonmessagegatewayservice.html); "
                 "[check agent version with Fleet Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/ssm-agent-get-version.html).")
    lines.append("")
    lines.append("**Fidelity.** `status=ok` means the RPM installed AND the agent binary ran locally. Columns are "
                 "grouped by category: **env_** = the OL test environment (read from the rpm db), **agent_** = the "
                 "agent's own build attribute, **compat_** = a compatibility requirement derived from it. The "
                 "**env_glibc** axis is faithful -- the container's real OL glibc gates a dynamic version's "
                 "install/run. **env_kernel** (`rpm -q kernel-uek`) is the OL UEK a real instance runs, provisioned "
                 "into the container only to record it; the binary itself actually executed on the "
                 "**test_host_kernel** (the runner's kernel, since a container shares the host kernel), so the run "
                 "does NOT exercise the OL kernel axis. The static kernel-axis signal is **compat_min_kernel** (the "
                 "Go toolchain's minimum kernel from the release's go.mod). A faithful kernel run needs a "
                 "kernel-matched runner or a real instance.")
    lines.append("")
    for kv in kvers:
        rows = [e for e in entries if e.get('kver', '') == kv]
        rows.sort(key=lambda e: vkey(e['ssm_version']))
        glibc = next((e.get('glibc', '') for e in rows if e.get('glibc')), '')
        thk = next((e.get('test_host_kernel', '') for e in rows if e.get('test_host_kernel')), '')
        oks = [e for e in rows if e.get('status') == 'ok']
        max_ok = sorted((e['ssm_version'] for e in oks), key=vkey)[-1] if oks else ''
        if not max_ok:
            verdict = "**none** -- nothing installed+ran in this OL environment"
        elif ge(max_ok, min_ver):
            verdict = f"**compliant-capable** -- max install+run `{max_ok}` >= `{min_ver}` (remediation possible)"
        else:
            verdict = (f"**ec2messages-only** -- max install+run `{max_ok}` < `{min_ver}`: the required version will "
                       "not install/run in this OL environment, so it CANNOT be remediated by an agent update and is "
                       "affected by the 2026-06-16 Run Command ec2messages deprecation")
        lines.append(f"## Test environment: OL{ol} kernel {kv}")
        lines.append("")
        lines.append(f"- `env_kernel` : {kv}  (`rpm -q kernel-uek` -- the OL UEK a real instance runs)")
        lines.append(f"- `env_glibc` : {glibc or '?'}  (`rpm -q glibc`)")
        lines.append(f"- `test_host_kernel` : {thk or '?'}  (the agent binary actually executed on the runner's "
                     "kernel; a container shares the host kernel, so the OL kernel axis is not exercised by the run)")
        lines.append("")
        lines.append(f"Verdict: {verdict}.")
        lines.append("")
        lines.append("| ssm_version | status | ran | agent_go_version | compat_min_kernel | note |")
        lines.append("|---|---|---|---|---|---|")
        for e in sorted(rows, key=lambda e: vkey(e['ssm_version']), reverse=True):
            note = e.get('reason', '') or ('installed ' + e.get('installed_version', '') if e.get('status') == 'ok' else '')
            note = note.replace('|', '\\|')
            lines.append(f"| {e['ssm_version']} | {e.get('status','')} | {'yes' if e.get('ran') else 'no'} | "
                         f"{e.get('go_version','') or '?'} | "
                         f"{e.get('min_kernel') or go_min_kernel(e.get('go_version',''))} | {note} |")
        lines.append("")
    open(os.path.join(results_dir, f"RESULTS-ol{ol}.md"), 'w').write("\n".join(lines).rstrip("\n") + "\n")

print(f"ledger entries: {len(led['entries'])} (+{new_rows} this run); reports for OL: {','.join(sorted(by_ol))}")
PY

# ---- summary ---------------------------------------------------------------
if [ -s "${RESULTS_TSV}" ]; then
  n_total="$(wc -l < "${RESULTS_TSV}")"
  n_ok="$(grep -c '"status":"ok"' "${RESULTS_TSV}" || true)"
  log "summary: ${n_total} install+run test(s) this run, ${n_ok} ok; ledger + RESULTS-ol*.md updated"
else
  log "summary: nothing tested this run (all requested combos already in the ledger, or none in scope); reports regenerated"
fi
