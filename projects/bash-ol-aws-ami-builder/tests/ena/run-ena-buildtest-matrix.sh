#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# run-ena-buildtest-matrix.sh  --  ENA self-build test matrix (OS x ENA x kernel)
# ----------------------------------------------------------------------------
# Self-contained by design: inline helpers, no shared library / no sourced module
# (the repository's standard policy for user-runnable scripts). It orchestrates
# the existing pieces as separate executables -- it does NOT source them:
#   * tests/cleancore/build-cleancore.sh  (-> the clean-core rootfs per OL)
#   * install-ena-driver.sh ENA_BUILDTEST=1  (-> the per-version compile-test)
#
# WHAT IT DOES [SPEC B.9]. For each target OL major and each target ENA driver
# version, it builds the ENA kernel module inside a disposable clean-core
# container (install-ena-driver.sh's ENA_BUILDTEST mode) and records the outcome
# in a machine-readable LEDGER keyed on (osmajor, ena_version, kver). The ledger
# is BOTH the evidence store AND the dedup state, so committing it persists what
# has been tested. A human-readable per-OS Markdown report (RESULTS-ol<N>.md) is
# regenerated from the ledger, newest kernel first.
#
# DEDUP [kernel-primary]. The dedup key is (osmajor, ena_version, kver); kver is
# the primary discriminator. Within a run the live kver for an OL is constant, so
# already-recorded (osmajor, ena_version, kver) combos -- whether they passed OR
# failed -- are SKIPPED. A NEW kernel (kver changes) shares no key with the old
# rows, so everything is re-tested; a NEW ENA release is the only missing key, so
# only the diff is tested. The live kver is taken from the build RESULT (the
# first build of a run for an OL establishes it; the pinned version is tried
# first as that per-run canary).
#
# INPUT. The ENA version set comes from tests/ena/ena-driver-releases.json
# (produced by list-ena-releases.sh) unless narrowed with --ena-versions /
# --pinned-only. Narrowing to a few versions is the supported way to run "a few
# cases" locally; the FULL matrix is meant for the user's environment / CI.
#
# Usage:
#   bash tests/ena/run-ena-buildtest-matrix.sh [options]
# Options:
#   --ol <list>            OL majors to test, comma/space (default: 6,7,8)
#   --ena-versions <list>  ENA versions to test, comma/space (default: all in the
#                          release-list JSON) -- the "few cases" knob
#   --pinned-only          test only each OL's pinned ENA version
#   --ledger <path>        ledger JSON (default: tests/ena/buildtest-ledger.json)
#   --results-dir <dir>    where RESULTS-ol<N>.md are written (default: tests/ena)
#   --cleancore-dir <dir>  holds/receives cleancore-ol<N>.tar.gz (default: ./cleancore-out)
#   --releases <path>      release-list JSON (default: tests/ena/ena-driver-releases.json)
#   --rebuild-cleancore    rebuild the clean-core rootfs even if present
#   --force                ignore the ledger; (re)test every requested combo
#   -h | --help
# Env (passed through): INSECURE_TLS (default 1 here, for the sandbox; set 0 on a
#   trusted host). Requires: root, unshare, chroot, tar, curl, python3, and the
#   clean-core builder toolchain. ENA_BUILDTEST is wired for OL6/OL7/OL8 only.
# Exit: 0 = the matrix ran and the ledger/reports were written (individual build
#   pass/fail is recorded as evidence, NOT a harness error); non-zero = a harness
#   / infrastructure failure (missing tool, clean-core build failed, etc.).
# ----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ORCHESTRATOR="${SCRIPT_DIR}/../cleancore/build-cleancore.sh"
INSTALL_SCRIPT="${PROJ_DIR}/install-ena-driver.sh"

OL_LIST="6 7 8"
ENA_VERSIONS=""
PINNED_ONLY=0
LEDGER="${SCRIPT_DIR}/buildtest-ledger.json"
RESULTS_DIR="${SCRIPT_DIR}"
CLEANCORE_DIR="./cleancore-out"
RELEASES="${SCRIPT_DIR}/ena-driver-releases.json"
REBUILD_CLEANCORE=0
FORCE=0
INSECURE_TLS="${INSECURE_TLS:-1}"

log()  { printf '%s [ena-matrix] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
warn() { log "WARNING: $*" >&2; }
die()  { log "ERROR: $*" >&2; exit 1; }

# pinned ENA version per OL major (mirrors install-ena-driver.sh's defaults).
pin_for() { case "$1" in 6) echo 2.9.1 ;; 7) echo 2.17.0 ;; 8) echo 2.17.0 ;; *) echo "" ;; esac; }

# ---- args ------------------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ol)               OL_LIST="${2:-}"; shift ;;
    --ena-versions)     ENA_VERSIONS="${2:-}"; shift ;;
    --pinned-only)      PINNED_ONLY=1 ;;
    --ledger)           LEDGER="${2:-}"; shift ;;
    --results-dir)      RESULTS_DIR="${2:-}"; shift ;;
    --cleancore-dir)    CLEANCORE_DIR="${2:-}"; shift ;;
    --releases)         RELEASES="${2:-}"; shift ;;
    --rebuild-cleancore) REBUILD_CLEANCORE=1 ;;
    --force)            FORCE=1 ;;
    -h|--help)          sed -n '2,/^# ---.*$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)                  die "unknown argument: $1 (-h for help)" ;;
  esac
  shift
done
OL_LIST="${OL_LIST//,/ }"
ENA_VERSIONS="${ENA_VERSIONS//,/ }"

# ---- pre-flight ------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "must run as root (clean-core build + unshare/chroot need it)."
for t in unshare chroot tar curl python3; do
  command -v "${t}" >/dev/null 2>&1 || die "missing required host tool: ${t}"
done
[ -f "${ORCHESTRATOR}" ]   || die "orchestrator not found: ${ORCHESTRATOR}"
[ -f "${INSTALL_SCRIPT}" ] || die "install-ena-driver.sh not found: ${INSTALL_SCRIPT}"
mkdir -p "${CLEANCORE_DIR}"; CLEANCORE_DIR="$(cd "${CLEANCORE_DIR}" && pwd)"
mkdir -p "${RESULTS_DIR}";   RESULTS_DIR="$(cd "${RESULTS_DIR}" && pwd)"

# Resolve the ENA version set for an OL (echo space-separated, ascending).
versions_for_ol() {
  local ol="$1"
  if [ "${PINNED_ONLY}" = "1" ]; then pin_for "${ol}"; return 0; fi
  if [ -n "${ENA_VERSIONS}" ]; then printf '%s' "${ENA_VERSIONS}"; return 0; fi
  [ -f "${RELEASES}" ] || die "release list not found: ${RELEASES} (run list-ena-releases.sh, or pass --ena-versions)"
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(' '.join(v['version'] for v in d['versions']))" "${RELEASES}"
}

# Run ONE ENA_BUILDTEST for (ol, version) against a clean-core tarball; echo the
# raw [result] JSON object (or empty if the build emitted none).
run_one_buildtest() {
  local ol="$1" ver="$2" tarball="$3" outlog="$4" img
  img="$(mktemp -d)"
  tar -C "${img}" -xzf "${tarball}"
  cp /etc/resolv.conf "${img}/etc/resolv.conf" 2>/dev/null || true
  cp "${INSTALL_SCRIPT}" "${img}/install-ena-driver.sh"
  unshare --fork --pid --mount --uts --ipc -- bash -c "
    mount --bind /dev '${img}/dev'
    mount -t proc proc '${img}/proc'
    mount -t sysfs sys '${img}/sys'
    chroot '${img}' env ENA_BUILDTEST=1 ENA_DRIVER_VERSION='${ver}' INSECURE_TLS='${INSECURE_TLS}' bash /install-ena-driver.sh
  " > "${outlog}" 2>&1 || true
  rm -rf "${img}"
  # No [result] line is a valid outcome (the install script died before its
  # die-handler, or unshare/chroot failed): emit empty, never fail the pipeline
  # (pipefail + set -e in the caller would otherwise abort the whole matrix).
  { grep -E '\[ena-driver\]\[buildtest\]\[result\]' "${outlog}" || true; } | tail -1 | sed 's/^.*\[result\] //'
}

# ---- run the matrix --------------------------------------------------------
RESULTS_TSV="$(mktemp)"   # one row per attempted build: ol \t version \t result-json
trap 'rm -f "${RESULTS_TSV}"' EXIT

if [ "${PINNED_ONLY}" = "1" ]; then ena_desc="pinned-only"; elif [ -n "${ENA_VERSIONS}" ]; then ena_desc="${ENA_VERSIONS}"; else ena_desc="all (from release list)"; fi
log "matrix: OL [${OL_LIST}] x ENA [${ena_desc}]  (INSECURE_TLS=${INSECURE_TLS}, force=${FORCE})"

for ol in ${OL_LIST}; do
  case "${ol}" in 6|7|8) : ;; *) warn "OL${ol}: ENA_BUILDTEST is wired for OL6/7/8 only; skipping."; continue ;; esac

  tarball="${CLEANCORE_DIR}/cleancore-ol${ol}.tar.gz"
  if [ ! -f "${tarball}" ] || [ "${REBUILD_CLEANCORE}" = "1" ]; then
    log "OL${ol}: building clean-core rootfs via the orchestrator -> ${tarball}"
    INSECURE_TLS="${INSECURE_TLS}" bash "${ORCHESTRATOR}" --ol "${ol}" --out-dir "${CLEANCORE_DIR}" \
      || die "OL${ol}: clean-core build failed (cannot run the ENA matrix for this OL)"
  else
    log "OL${ol}: reusing existing clean-core rootfs ${tarball}"
  fi

  # Order: pinned version first (the per-run kver canary), then the rest ascending.
  pin="$(pin_for "${ol}")"
  mapfile -t want < <(versions_for_ol "${ol}" | tr ' ' '\n' | grep -v '^$' | sort -t. -k1,1n -k2,2n -k3,3n -u)
  ordered=()
  for v in "${pin}" "${want[@]}"; do
    case " ${ordered[*]} " in *" ${v} "*) : ;; *) [ -n "${v}" ] && ordered+=("${v}") ;; esac
  done

  live_kver=""
  for ver in "${ordered[@]}"; do
    # case it was requested? (pin may not be in --ena-versions) -- only test requested ones + the canary pin.
    if [ -n "${ENA_VERSIONS}" ] || [ "${PINNED_ONLY}" = "1" ]; then
      case " $(versions_for_ol "${ol}") ${pin} " in *" ${ver} "*) : ;; *) continue ;; esac
    fi
    if [ "${FORCE}" != "1" ] && [ -n "${live_kver}" ]; then
      if python3 -c "
import json,sys,os
p=sys.argv[1]
if not os.path.exists(p): sys.exit(1)
d=json.load(open(p))
k=(sys.argv[2],sys.argv[3],sys.argv[4])
sys.exit(0 if any((e['osmajor'],e['ena_version'],e['kver'])==k for e in d.get('entries',[])) else 1)
" "${LEDGER}" "${ol}" "${ver}" "${live_kver}"; then
        log "OL${ol} ENA ${ver}: SKIP (already in ledger for kver ${live_kver})"
        continue
      fi
    fi
    log "OL${ol} ENA ${ver}: building (ENA_BUILDTEST)..."
    blog="$(mktemp)"
    rjson="$(run_one_buildtest "${ol}" "${ver}" "${tarball}" "${blog}" || true)"
    if [ -z "${rjson}" ]; then
      rjson="{\"status\":\"fail\",\"osmajor\":\"${ol}\",\"ena_version\":\"${ver}\",\"kver\":\"${live_kver}\",\"reason\":\"no result line (infrastructure error)\"}"
    fi
    st="$(printf '%s' "${rjson}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || true)"
    if [ "${st}" != "ok" ]; then
      keep="${CLEANCORE_DIR}/buildtest-ol${ol}-ena${ver}.log"
      cp -f "${blog}" "${keep}" 2>/dev/null || true
      warn "OL${ol} ENA ${ver}: ${st:-no-result} -- build log preserved at ${keep}"
    fi
    rm -f "${blog}"
    printf '%s\t%s\t%s\n' "${ol}" "${ver}" "${rjson}" >> "${RESULTS_TSV}"
    kv="$(printf '%s' "${rjson}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('kver',''))" 2>/dev/null || true)"
    [ -n "${kv}" ] && live_kver="${kv}"
    log "OL${ol} ENA ${ver}: ${st:-?} (kver ${live_kver:-?})"
  done
done

# ---- merge into the ledger + regenerate the per-OS Markdown -----------------
log "updating ledger ${LEDGER} and per-OS reports in ${RESULTS_DIR}"
python3 - "${LEDGER}" "${RESULTS_TSV}" "${RESULTS_DIR}" <<'PY'
import json, os, sys, datetime

ledger_path, tsv_path, results_dir = sys.argv[1], sys.argv[2], sys.argv[3]

def load_ledger(p):
    if os.path.exists(p):
        try: return json.load(open(p))
        except Exception: pass
    return {"schema_version": "1.0", "ledger_type": "ena-buildtest-matrix",
            "generated_by": "tests/ena/run-ena-buildtest-matrix.sh",
            "dedup_key": ["osmajor", "ena_version", "kver"], "entries": []}

led = load_ledger(ledger_path)
idx = {(e["osmajor"], e["ena_version"], e["kver"]): e for e in led.get("entries", [])}
now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

if os.path.exists(tsv_path):
    for line in open(tsv_path):
        line = line.rstrip("\n")
        if not line: continue
        ol, ver, rjson = line.split("\t", 2)
        try: r = json.loads(rjson)
        except Exception: r = {"status": "fail", "osmajor": ol, "ena_version": ver, "kver": "", "reason": "unparseable result"}
        e = {"osmajor": str(r.get("osmajor") or ol),
             "ena_version": str(r.get("ena_version") or ver),
             "kver": str(r.get("kver") or ""),
             "status": r.get("status", "fail"),
             "dkms": r.get("dkms", None),
             "ko": r.get("ko", None),
             "ko_version": r.get("ko_version", None),
             "reason": r.get("reason", None),
             "tested_at": now}
        idx[(e["osmajor"], e["ena_version"], e["kver"])] = e

def vkey(s):
    out = []
    for part in str(s).replace("-", ".").split("."):
        out.append((1, int(part)) if part.isdigit() else (0, part))
    return out

entries = sorted(idx.values(), key=lambda e: (int(e["osmajor"]) if e["osmajor"].isdigit() else 0,
                                              vkey(e["kver"]), vkey(e["ena_version"])))
led["entries"] = entries
json.dump(led, open(ledger_path, "w"), indent=2)
open(ledger_path, "a").write("\n")

# Per-OS Markdown, newest kernel first, newest ENA first within a kernel.
by_ol = {}
for e in entries:
    by_ol.setdefault(e["osmajor"], []).append(e)

for ol, es in sorted(by_ol.items(), key=lambda kv: int(kv[0]) if kv[0].isdigit() else 0):
    kvers = sorted({e["kver"] for e in es}, key=vkey, reverse=True)
    lines = [f"# ENA self-build test results - Oracle Linux {ol}", "",
             "Generated by `tests/ena/run-ena-buildtest-matrix.sh` from "
             "`buildtest-ledger.json`. Dedup key `(osmajor, ena_version, kver)`; "
             "newest kernel first. A `fail` row is recorded evidence (e.g. an ENA "
             "release too old for that kernel), not a harness error.", ""]
    for kv in kvers:
        rows = sorted([e for e in es if e["kver"] == kv], key=lambda e: vkey(e["ena_version"]), reverse=True)
        n_ok = sum(1 for e in rows if e["status"] == "ok")
        lines += [f"## kernel `{kv or '(unknown)'}`  -  {n_ok}/{len(rows)} ok", "",
                  "| ENA version | status | ko_version | dkms | tested (UTC) | notes |",
                  "|:--|:--|:--|:--|:--|:--|"]
        for e in rows:
            dkms = {True: "yes", False: "no", None: "-"}.get(e.get("dkms"), str(e.get("dkms")))
            note = e.get("reason") or ""
            lines.append(f"| {e['ena_version']} | {e['status']} | {e.get('ko_version') or '-'} | "
                         f"{dkms} | {e.get('tested_at','')} | {note} |")
        lines.append("")
    open(os.path.join(results_dir, f"RESULTS-ol{ol}.md"), "w").write("\n".join(lines).rstrip("\n") + "\n")

print(f"ledger entries: {len(entries)}; reports for OL: {','.join(sorted(by_ol))}")
PY

# ---- summary ---------------------------------------------------------------
if [ -s "${RESULTS_TSV}" ]; then
  n_total="$(wc -l < "${RESULTS_TSV}")"
  n_ok="$(grep -c '"status":"ok"' "${RESULTS_TSV}" || true)"
  log "summary: ${n_total} build(s) attempted this run, ${n_ok} ok; ledger + RESULTS-ol*.md updated"
else
  log "summary: nothing built this run (all requested combos already in the ledger); reports regenerated"
fi
