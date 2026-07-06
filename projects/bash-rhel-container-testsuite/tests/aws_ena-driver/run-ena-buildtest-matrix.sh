#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   Run the ENA driver build (per entitlement) test matrix per RHEL major; append
#   measured rows to the JSON ledger and regenerate RESULTS-rhel<N>.md.
# ----- Prerequisites --------------------------------------------------------
#   bash 4+, python3; report mode: none beyond the repo. --run: podman (or the
#   curl-only OCI fallback) + container egress; entitled host for rhel-* repos.
# ----- Usage examples -------------------------------------------------------
#   bash run-ena-buildtest-matrix.sh              # regenerate reports from the ledger
#   OSMAJORS="9 8" bash run-ena-buildtest-matrix.sh --run   # live matrix
# ----- Known limitations ----------------------------------------------------
#   --run is L3 (manual/CI); RESULTS files are generated - never hand-edited.
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
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
#   entitled  -> build ena.ko (DKMS-first since r66 - images ship EPEL+dkms
#                per r65 provisioning; plain-make fallback) -> ok | build-fail
#   anonymous -> skip (no kernel-devel)                  -> needs-entitlement
#   any       -> load / runtime                          -> L4 (impossible in a container)
#
# ENA EXPRESS READINESS (driver-version floor only). Each ledger row and the
# RESULTS-rhel<N>.md report additionally carry ena_express, the AWS-documented
# driver-version floor classification (ena_express_verdict; ena-express.html:
# >= 2.2.9 full bandwidth, >= 2.8.0 ena_srd_* metrics -> "express-ready"). This
# is a pure function of ena_version, independent of the entitlement/build
# axis - it is NOT an eligibility check. ENA Express is enabled per
# network-interface attachment via the AWS API EnaSrdEnabled attribute
# (unrelated to the guest OS) and gated by instance type; "meets the floor" is
# necessary, not sufficient for a given kernel to actually compile against it
# (see the OL sibling project's UEKR8 findings in its SPEC.md).
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
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RELEASES="${SCRIPT_DIR}/ena-driver-releases.json"
LEDGER="${SCRIPT_DIR}/buildtest-ledger.json"
RESULTS_DIR="${SCRIPT_DIR}"
INSTALL_SCRIPT="${PROJ_DIR}/install-aws_ena-driver.sh"   # kicked by run_matrix (--run)
ENA_MIN="3.3.0"   # overridden below from releases.json min_version if present
FULL="${FULL:-0}"
FORCE="${FORCE:-0}"

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

# ena_express_verdict <version> : classify a driver version against AWS's
# documented ENA Express driver-version floors (ena-express.html): full
# bandwidth potential at driver >= 2.2.9; ena_srd_* metrics reporting at
# driver >= 2.8.0. Self-contained (no ena_ge dependency) so the unit
# extracts and REUSE-BY-COPIES cleanly across this matrix, the lister, and
# the installer - kept identical, verified by tests/t010_enaverdict.sh.
# Pure function of the version only - NOT an eligibility check: ENA
# Express itself is enabled via the AWS API EnaSrdEnabled ENI-attachment
# attribute and gated by instance type (SPEC.md); a driver meeting the
# floor is necessary, not sufficient (same caveat as ena_verdict's "ok").
ena_express_verdict() {
  local v="${1:-}" hi
  [ -n "${v}" ] || { printf 'unknown'; return 0; }
  hi="$(printf '%s\n2.8.0\n' "${v}" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
  if [ "${v}" = "2.8.0" ] || [ "${hi}" = "${v}" ]; then printf 'express-ready'; return 0; fi
  hi="$(printf '%s\n2.2.9\n' "${v}" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
  if [ "${v}" = "2.2.9" ] || [ "${hi}" = "${v}" ]; then printf 'bandwidth-only'; return 0; fi
  printf 'not-ready'
}

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

generate_results() {
  [ -f "${LEDGER}" ] || { log "no ledger at ${LEDGER}; nothing to generate"; return 0; }
  local mn; mn="$(releases_min)"
  python3 - "${LEDGER}" "${RESULTS_DIR}" "${mn}" <<'PYREPORT'
import json, os, sys

ledger_path, results_dir, min_ver = sys.argv[1], sys.argv[2], sys.argv[3]

def vkey(s):
    out = []
    for part in str(s).replace("-", ".").split("."):
        out.append((1, int(part)) if part.isdigit() else (0, part))
    return out

def ge(a, b):
    return vkey(a) >= vkey(b)

def express_verdict(v):
    if not v: return "unknown"
    if ge(v, "2.8.0"): return "express-ready"
    if ge(v, "2.2.9"): return "bandwidth-only"
    return "not-ready"

try:
    led = json.load(open(ledger_path))
except Exception:
    print("ERROR: cannot load ledger"); sys.exit(1)

# host metadata
host = led.get("host", {})
if host:
    host_line = "%s, kernel %s %s, SELinux: %s, %s" % (
        host.get("os","?"), host.get("kernel","?"), host.get("arch","?"),
        host.get("selinux","?"), host.get("runtime","?"))
else:
    host_line = "(not yet run)"

results = led.get("results", [])
by_major = {}
for r in results:
    m = str(r.get("osmajor", ""))
    by_major.setdefault(m, []).append(r)

for major in sorted(by_major, key=lambda m: int(m) if m.isdigit() else 99):
    rows_raw = by_major[major]

    # deduplicate: prefer entitled rows; key = (version, entitlement)
    seen = {}
    for r in rows_raw:
        k = (r.get("ena_version",""), r.get("entitlement","entitled"))
        seen[k] = r

    # build table from entitled rows (primary); note anonymous if present
    ver_data = {}
    for (ver, ent), r in seen.items():
        if ver not in ver_data:
            ver_data[ver] = {"entitled": None, "anonymous": None}
        ver_data[ver][ent] = r

    # table rows: entitled results, sorted descending
    table_rows = []
    for ver in sorted(ver_data, key=vkey, reverse=True):
        d = ver_data[ver]
        primary = d.get("entitled") or d.get("anonymous") or {}
        status = primary.get("status", "pending")
        built = primary.get("built", False)
        ko_version = primary.get("ko_version", "") or "-"
        dkms = primary.get("dkms")
        dkms_str = {True: "yes", False: "no"}.get(dkms, "-")
        tested_at = primary.get("tested_at", "")
        reason = primary.get("reason", "") or ""
        if status == "ok" and not reason:
            reason = ""
        reason = reason.replace("|", "\\|")
        table_rows.append({
            "version": ver,
            "status": status,
            "ko_version": ko_version,
            "dkms": dkms_str,
            "tested_at": tested_at,
            "note": reason,
        })

    # verdict: count ok/total
    ok_versions = [ver for ver, d in ver_data.items()
                   if (d.get("entitled") or {}).get("status") == "ok"]
    n_ok = len(ok_versions)
    n_total = len(table_rows)
    max_ok = max(ok_versions, key=vkey) if ok_versions else ""
    ok_list = ", ".join(sorted(ok_versions, key=vkey, reverse=True)) if ok_versions else "(none)"

    lines = []
    lines.append("# ENA self-build test results - RHEL %s" % major)
    lines.append("")
    lines.append("Generated by `run-ena-buildtest-matrix.sh` from "
                 "`buildtest-ledger.json`. Dedup key `(osmajor, ena_version, entitlement)`; "
                 "newest version first. A `fail` row is recorded evidence (e.g. an ENA "
                 "release too old for that kernel), not a harness error. An `ok` means "
                 "the requested version compiled out of tree on the container's kernel-devel "
                 "(necessary, not sufficient); real module load and device attach are "
                 "proven separately on real Nitro.")
    lines.append("")
    lines.append("- `test_host` : %s" % host_line)
    lines.append("")

    # summary
    lines.append("## Verdict: %d/%d ok" % (n_ok, n_total))
    lines.append("")
    if ok_versions:
        lines.append("Buildable ENA versions: %s." % ok_list)
    else:
        lines.append("No ENA version builds in this environment yet.")
    lines.append("")
    lines.append("_ENA Express readiness (driver-version floor only): "
                 ">= 2.2.9 full bandwidth, >= 2.8.0 express-ready (ena_srd_* metrics). "
                 "ENA Express itself is an ENI attribute (AWS API), not a guest OS setting._")
    lines.append("")

    lines.append("| ENA version | status | ko_version | dkms | tested (UTC) | notes |")
    lines.append("|:--|:--|:--|:--|:--|:--|")
    for row in table_rows:
        lines.append("| %s | %s | %s | %s | %s | %s |" % (
            row["version"], row["status"], row["ko_version"],
            row["dkms"], row["tested_at"], row["note"]))
    lines.append("")

    # r61: fail pattern analysis - group consecutive fail versions by error
    fail_rows = [(r["version"], r["note"]) for r in table_rows if r["status"] == "fail"]
    if fail_rows:
        lines.append("## Fail pattern analysis")
        lines.append("")
        def extract_api_error(reason):
            if not reason: return "(unknown)"
            if reason.startswith("build failed (") and reason.endswith(")"):
                inner = reason[len("build failed ("):-1]
                if inner and inner != "make returned non-zero or produced no ena.ko":
                    return inner
            return reason

        groups = []
        for ver, note in fail_rows:
            err = extract_api_error(note)
            if groups and groups[-1]["error"] == err:
                groups[-1]["versions"].append(ver)
            else:
                groups.append({"error": err, "versions": [ver]})

        kver = next((str(r.get("kver","")) for r in rows_raw if r.get("kver")), "?")
        lines.append("The container's kernel-devel (`%s`) determines which "
                     "ENA releases can compile. Older ENA releases lack kcompat.h "
                     "coverage for newer kernel APIs; newer ENA releases drop "
                     "support for older kernels. Each group below shares the same "
                     "root cause." % kver)
        lines.append("")
        lines.append("| ENA versions | root cause |")
        lines.append("|:--|:--|")
        for g in groups:
            vs = g["versions"]
            if len(vs) == 1:
                vrange = vs[0]
            else:
                vrange = "%s -- %s (%d versions)" % (vs[0], vs[-1], len(vs))
            lines.append("| %s | %s |" % (vrange, g["error"]))
        lines.append("")
    lines.append("_Sweep: %d version(s) tested, %d ok. "
                 "Regenerate: `OSMAJORS=%s ./run-ena-buildtest-matrix.sh`._" % (
                     n_total, n_ok, major))
    lines.append("")

    open(os.path.join(results_dir, "RESULTS-rhel%s.md" % major), 'w').write(
        "\n".join(lines).rstrip("\n") + "\n")
    print("wrote RESULTS-rhel%s.md (%d versions, %d ok)" % (major, n_total, n_ok))
PYREPORT
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
# (dedup by osmajor+ena_version+entitlement; last write wins). OL-aligned: adds
# tested_at timestamp, ko_version/dkms fields, and defense-in-depth false-ok guard
# (ko_version mismatch → downgrade to fail). Atomic tmp+replace.
persist_ledger() {
  local rows="$1"
  [ -f "${LEDGER}" ] || { log "no ledger at ${LEDGER}; skipping persist"; return 0; }
  python3 - "${LEDGER}" "${rows}" <<'PY2' 2>/dev/null || { log "WARNING: ledger persist failed"; return 0; }
import json,sys,os,tempfile,datetime
led,rowsfile=sys.argv[1],sys.argv[2]
try: d=json.load(open(led))
except Exception: sys.exit(1)
now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
rows=[]
for ln in open(rowsfile):
    ln=ln.strip()
    if not ln: continue
    try: rows.append(json.loads(ln))
    except Exception: pass
def key(r): return (str(r.get("osmajor")), r.get("ena_version"), r.get("entitlement"))
merged={}
for r in d.get("results",[]): merged[key(r)]=r
for r in rows:
    e = {
        "osmajor": str(r.get("osmajor","")),
        "ena_version": str(r.get("ena_version","")),
        "entitlement": str(r.get("entitlement","entitled")),
        "status": r.get("status","fail"),
        "built": r.get("built", False),
        "ko_version": r.get("ko_version", None),
        "dkms": r.get("dkms", None),
        "kver": r.get("kver", ""),
        "build_plan": r.get("build_plan", ""),
        "ena_express": r.get("ena_express", ""),
        "reason": r.get("reason", ""),
        "tested_at": now,
    }
    # Defense-in-depth (OL parity): an "ok" whose ko_version does not match the
    # requested ena_version means the build never produced the requested module.
    kov = str(e.get("ko_version") or "")
    if e["status"] == "ok" and kov and not kov.startswith(e["ena_version"]):
        e["reason"] = "ko_version %s does not match requested %s -- recorded as fail" % (kov, e["ena_version"])
        e["status"] = "fail"
    merged[key(e)]=e
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
  # shellcheck source=../../lib/provision-test-env.sh
  . "${PROJ_DIR}/lib/provision-test-env.sh"
  host_banner
  # r48 (user requirement): the provisioned test-env images are removed on
  # EVERY exit path - normal completion, failure, or interrupt. Base images
  # (UBI/RHEL) are untouched; KEEP_TEST_IMAGES=1 opts out.
  trap provision_cleanup_images EXIT
  # r46 (D-S1/D-S2): containers run PLAIN. RHSM hosts auto-inject entitled
  # repos per container; the entitled RHUI container path is pending.
  local repo_mode; repo_mode="$(acq_repo_access | cut -d'|' -f1)"
  log "repo access mode: ${repo_mode} (containers run plain; RHSM auto-injection provides entitled repos; RHUI entitled path pending)"
  local ent_mounts=""
  record_host_meta "${LEDGER}"
  acq_preflight "${INSTALL_SCRIPT}" || { log "aborting --run (preflight failed; no rows written)"; return 2; }
  local LOG_DIR="${SCRIPT_DIR}/logs"
  local majors="${OSMAJORS:-10 9 8 7 6}" ents="${ENTITLEMENTS:-entitled anonymous}" major ent ver repo plan ref rows_tmp prep_map prepared
  local versions idx total g_ok=0 g_fail=0 g_skip=0 g_builds=0 ol_ok ol_fail ol_skip
  rows_tmp="$(mktemp)"
  # r58: sweep ALL in-scope versions (not just latest) - OL parity.
  # --full: all versions in releases JSON (not just >= min_version).
  if [ -n "${ENA_VERSIONS:-}" ]; then
    versions="${ENA_VERSIONS}"
  elif [ "${FULL}" = "1" ]; then
    versions="$(releases_versions 2>/dev/null | sort -t. -k1,1n -k2,2n -k3,3n -r | tr '\n' ' ')"
  else
    local mn; mn="$(releases_min)"
    versions="$(releases_versions 2>/dev/null | while IFS= read -r v; do
      [ -n "${v}" ] || continue; ena_ge "${v}" "${mn}" && printf '%s\n' "${v}"
    done | sort -t. -k1,1n -k2,2n -k3,3n -r | tr '\n' ' ')"
  fi
  # PRE-FLIGHT: create a test-ready image for every requested major BEFORE any
  # test runs. A non-optional major that cannot be prepared is a missing test
  # prerequisite -> abort the whole run (no tests). EL6 (PROVISION_OPTIONAL_MAJORS)
  # may be unprovisionable and is then skipped, not fatal.
  prep_map="$(mktemp)"
  provision_prepare_majors "${majors}" "${ent_mounts}" "${prep_map}" || {
    log "aborting --run: test-env prerequisite not met (no tests run)"
    rm -f "${prep_map}" "${rows_tmp}"; return 2
  }
  prepared="$(cut -d' ' -f1 "${prep_map}" | tr '\n' ' ')"
  total=0; for _v in ${versions}; do total=$(( total + 1 )); done
  log "sweep: prepared majors=[${prepared}] versions=${total} entitlements=[${ents}] full=${FULL} force=${FORCE}"
  for major in ${prepared}; do
    ref="$(grep -m1 "^${major} " "${prep_map}" | cut -d' ' -f2-)"
    repo="$(ena_kdevel_repo "${major}")"
    idx=0; ol_ok=0; ol_fail=0; ol_skip=0
    for ver in ${versions}; do
      idx=$(( idx + 1 ))
      for ent in ${ents}; do
        # ledger-based skip: if (major, ver, ent) already in ledger and not --force
        if [ "${FORCE}" != "1" ] && [ -f "${LEDGER}" ]; then
          if python3 -c "
import json,sys,os
p=sys.argv[1]
if not os.path.exists(p): sys.exit(1)
d=json.load(open(p))
k=(sys.argv[2],sys.argv[3],sys.argv[4])
sys.exit(0 if any((str(e.get('osmajor')),e.get('ena_version'),e.get('entitlement'))==k for e in d.get('results',[])) else 1)
" "${LEDGER}" "${major}" "${ver}" "${ent}" 2>/dev/null; then
            log "RHEL${major} [${idx}/${total}] ENA ${ver}/${ent}: SKIP (already in ledger)"
            ol_skip=$(( ol_skip + 1 )); continue
          fi
        fi
        # r66: epel=1 - the r65 image provisioning bakes EPEL + dkms into every
        # test image, but this call site still passed epel=0, so the sweep
        # forced ENA_BUILD_PLAN=make and the r65 DKMS-first path (C3) was
        # never exercised (ledger: build_plan=make on all 145 entitled rows).
        plan="$(ena_build_plan "${ent}" 1)"
        log "RHEL${major} [${idx}/${total}] ENA ${ver}/${ent}: build test..."
        ena_kick "${major}" "${ver}" "${ent}" "${repo}" "${plan}" "${ref}" "${LOG_DIR}" "${rows_tmp}"
        local st; st="$(tail -1 "${rows_tmp}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || true)"
        if [ "${st}" = "ok" ]; then ol_ok=$(( ol_ok + 1 )); else ol_fail=$(( ol_fail + 1 )); fi
      done
    done
    log "---- RHEL${major}: sweep done -- ${ol_ok} ok, ${ol_fail} fail, ${ol_skip} skipped (of ${total} versions x $(echo "${ents}" | wc -w) ents) ----"
    g_ok=$(( g_ok + ol_ok )); g_fail=$(( g_fail + ol_fail )); g_skip=$(( g_skip + ol_skip ))
  done
  g_builds=$(( g_ok + g_fail ))
  log "ENA matrix complete -- ${g_ok} ok, ${g_fail} fail, ${g_skip} skipped across ${g_builds} build(s)"
  persist_ledger "${rows_tmp}"
  rm -f "${rows_tmp}"
}

# ena_kick <major> <ver> <ent> <repo> <plan> <ref> <log_dir> <rows_file> : build-test
# one (major, entitlement) in a container, record the row (+reason), and on non-ok
# preserve the container output to <log_dir> (fail/error only).
ena_kick() {
  local major="$1" ver="$2" ent="$3" repo="$4" plan="$5" ref="$6" log_dir="$7" rows="$8"
  local err_tmp out line built status kov reason row logf rc=0
  err_tmp="$(mktemp)"
  # shellcheck disable=SC2086  # ent_mounts is intentionally word-split into -v/--network args
  out="$(timeout "${RUN_TIMEOUT:-600}" podman run --rm \
          -v "${INSTALL_SCRIPT}:/install-aws_ena-driver.sh:ro,z" \
          ${ent_mounts:-} \
          -e ENA_INSTALLTEST=1 -e "ENA_VERSION=${ver}" -e "ENA_ENTITLEMENT=${ent}" \
          -e "ENA_BUILD_PLAN=${plan}" -e "INSECURE_TLS=${INSECURE_TLS:-0}" \
          "${ref}" /bin/bash /install-aws_ena-driver.sh 2>"${err_tmp}")" || rc=$?
  line="$(printf '%s
' "${out}" | grep -F '[aws_ena-driver][installtest][result]' | tail -1)" || true  # tolerated-empty probe: no result line = reasoned error row (A.5 asymmetry)
  logf="${log_dir}/buildtest-rhel${major}-ena_${ver}_${ent}.log"
  if [ "${rc}" = "124" ]; then
    reason="timed out after ${RUN_TIMEOUT:-600}s (container stalled; possible repo/network wait)"
    status=error
    log "RHEL${major} ${ver}/${ent}: TIMEOUT -> ${reason}"
    row="$(printf '{"status":"error","osmajor":"%s","ena_version":"%s","entitlement":"%s","kdevel_repo":"%s","build_plan":"%s","built":false,"ko_version":"","verdict":"harness-error","load_tier":"%s","ena_express":"%s","reason":"%s"}' \
      "${major}" "${ver}" "${ent}" "${repo}" "${plan}" "$(ena_load_tier)" "$(ena_express_verdict "${ver}")" "$(jesc "${reason}")")"
  elif [ -z "${line}" ]; then
    reason="$(python3 -c 'import sys,json; print(json.dumps(" ".join(open(sys.argv[1]).read().split()))[1:-1][:300])' "${err_tmp}" 2>/dev/null || true)"
    [ -n "${reason}" ] || reason="container produced no [result] and no stderr"
    status=error
    log "RHEL${major} ${ver}/${ent}: harness-error -> ${reason}"
    row="$(printf '{"status":"error","osmajor":"%s","ena_version":"%s","entitlement":"%s","kdevel_repo":"%s","build_plan":"%s","built":false,"ko_version":"","verdict":"harness-error","load_tier":"%s","ena_express":"%s","reason":"%s"}' \
      "${major}" "${ver}" "${ent}" "${repo}" "${plan}" "$(ena_load_tier)" "$(ena_express_verdict "${ver}")" "${reason}")"
  else
    built="$(result_field "${line}" built)"; [ "${built}" = "true" ] || built=false
    status="$(result_field "${line}" status)"; [ -n "${status}" ] || status=unknown
    kov="$(result_field "${line}" ko_version)"
    local kver_got; kver_got="$(result_field "${line}" kver)"
    local dkms_got; dkms_got="$(result_field "${line}" dkms)"
    reason="$(jesc "$(result_field "${line}" reason)")"
    row="$(printf '{"status":"%s","osmajor":"%s","ena_version":"%s","entitlement":"%s","kdevel_repo":"%s","build_plan":"%s","built":%s,"ko_version":"%s","kver":"%s","dkms":%s,"verdict":"%s","load_tier":"%s","ena_express":"%s","reason":"%s"}' \
      "${status}" "${major}" "${ver}" "${ent}" "${repo}" "${plan}" "${built}" "${kov}" "${kver_got}" \
      "${dkms_got:-null}" "$(ena_verdict "${ent}" "${built}")" "$(ena_load_tier)" "$(ena_express_verdict "${ver}")" "${reason}")"
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
    --full)             FULL=1 ;;
    --force)            FORCE=1 ;;
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
