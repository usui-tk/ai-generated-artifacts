#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   Run the AWS CLI v2 install test matrix per RHEL major; append
#   measured rows to the JSON ledger and regenerate RESULTS-rhel<N>.md.
# ----- Prerequisites --------------------------------------------------------
#   bash 4+, python3; report mode: none beyond the repo. --run: podman (or the
#   curl-only OCI fallback) + container egress; entitled host for rhel-* repos.
# ----- Usage examples -------------------------------------------------------
#   bash run-awscli-installtest-matrix.sh              # regenerate reports from the ledger
#   OSMAJORS="9 8" bash run-awscli-installtest-matrix.sh --run   # live matrix
# ----- Known limitations ----------------------------------------------------
#   --run is L3 (manual/CI); RESULTS files are generated - never hand-edited.
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
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
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RELEASES="${SCRIPT_DIR}/awscli-releases.json"
LEDGER="${SCRIPT_DIR}/awscli-installtest-ledger.json"
RESULTS_DIR="${SCRIPT_DIR}"
INSTALL_SCRIPT="${PROJ_DIR}/install-aws_awscli-v2.sh"   # kicked by run_matrix (--run)
FULL="${FULL:-0}"
FORCE="${FORCE:-0}"

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

generate_results() {
  [ -f "${LEDGER}" ] || { log "no ledger at ${LEDGER}; nothing to generate"; return 0; }
  python3 - "${LEDGER}" "${RESULTS_DIR}" <<'PYREPORT'
import json, os, sys

ledger_path, results_dir = sys.argv[1], sys.argv[2]

def vkey(s):
    p = (str(s).split('.') + ['0','0','0','0'])[:4]
    return tuple(int(x) if str(x).isdigit() else 0 for x in p)

def ge(a, b):
    return vkey(a) >= vkey(b)

def min_glibc_heuristic(v):
    if not v: return "unknown"
    return "2.17" if ge(v, "2.17.50") else "2.5"

def python_eol(v):
    if not v or v == "unknown": return "unknown"
    parts = str(v).split(".")
    mm = "%s.%s" % (parts[0], parts[1]) if len(parts) >= 2 else ""
    return {"3.6":"2021-12-23","3.7":"2023-06-27","3.8":"2024-10-07",
            "3.9":"2025-10-31","3.10":"2026-10-31","3.11":"2027-10-31",
            "3.12":"2028-10-31","3.13":"2029-10-31","3.14":"2030-10-31"}.get(mm, "unknown")

try:
    led = json.load(open(ledger_path))
except Exception:
    print("ERROR: cannot load ledger"); sys.exit(1)

host = led.get("host", {})
host_line = ("%s, kernel %s %s, SELinux: %s, %s" % (
    host.get("os","?"), host.get("kernel","?"), host.get("arch","?"),
    host.get("selinux","?"), host.get("runtime","?"))) if host else "(not yet run)"

results = led.get("results", [])
by_major = {}
for r in results:
    m = str(r.get("osmajor", ""))
    by_major.setdefault(m, []).append(r)

for major in sorted(by_major, key=lambda m: int(m) if m.isdigit() else 99):
    rows_raw = by_major[major]
    seen = {}
    for r in rows_raw:
        seen[r.get("awscli_version", "")] = r

    table_rows = []
    for ver in sorted(seen, key=vkey, reverse=True):
        r = seen[ver]
        status = r.get("status", "pending")
        ran = r.get("ran", False)
        bpy = r.get("bundled_python", "") or "?"
        peol = python_eol(bpy)
        mgl_measured = r.get("min_glibc_measured", "") or ""
        mgl_heuristic = min_glibc_heuristic(ver)
        mgl_display = "%s / %s" % (mgl_measured, mgl_heuristic) if mgl_measured else "? / %s" % mgl_heuristic
        reason = r.get("reason", "") or ""
        if status == "ok" and not reason:
            reason = "installed %s" % r.get("installed_version", ver)
        reason = reason.replace("|", "\\|")
        table_rows.append({
            "version": ver, "status": status, "ran": ran,
            "bundled_python": bpy, "python_eol": peol,
            "min_glibc": mgl_display, "note": reason,
        })

    ok_versions = [ver for ver, r in seen.items() if r.get("status") == "ok"]
    n_ok = len(ok_versions)
    n_total = len(table_rows)
    max_ok = max(ok_versions, key=vkey) if ok_versions else ""
    glibc = next((str(r.get("glibc","")) for r in rows_raw if r.get("glibc")), "?")

    if max_ok:
        latest_all = max(seen.keys(), key=vkey)
        if max_ok == latest_all:
            verdict_text = "**current** -- the newest tested v2 `%s` installs+runs" % max_ok
        else:
            verdict_text = "**capped** -- max install+run `%s` (newest tested `%s` does not run)" % (max_ok, latest_all)
    else:
        verdict_text = "**none** -- no v2 version installed+ran"

    lines = []
    lines.append("# AWS CLI v2 install+run matrix -- RHEL %s" % major)
    lines.append("")
    lines.append("Generated by `run-awscli-installtest-matrix.sh` from "
                 "`awscli-installtest-ledger.json` -- DO NOT hand-edit (regenerated each run).")
    lines.append("")
    lines.append("## Why this matters -- AWS CLI v2 glibc support")
    lines.append("")
    lines.append("AWS CLI v2 ships a self-contained zip bundle that BUNDLES its own Python, so it "
                 "does not use the OS Python -- but the bundled interpreter and its shared objects are "
                 "built against a **manylinux glibc**, so the OS **glibc** gates whether the bundle "
                 "installs and runs. Per AWS's *Linux Support Updates for AWS CLI v2* (2024-09-16), "
                 "current v2 is built on **manylinux2014 (glibc 2.17)** and supports glibc >= 2.17; "
                 "systems on glibc <= 2.16 should pin v2 **<= 2.17.49**. This report characterizes, "
                 "per RHEL major, which v2 versions install + run -- i.e. the newest AWS CLI v2 a "
                 "RHEL %s image can actually use." % major)
    lines.append("")
    lines.append("References (AWS): "
                 "[Linux support updates](https://aws.amazon.com/blogs/developer/linux-support-updates-for-aws-cli-v2/); "
                 "[install AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html); "
                 "[a specific version](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-version.html).")
    lines.append("")
    lines.append("**Fidelity.** `status=ok` means the v2 bundle installed AND `aws --version` + "
                 "`aws configure list` both ran locally (no AWS creds / no IMDS). The **glibc** axis "
                 "is FAITHFUL -- the container's real RHEL glibc is what the bundle links against. "
                 "`bundled_python` and `python_eol` track the frozen interpreter inside each bundle.")
    lines.append("")
    lines.append("## Bundled Python runtime support")
    lines.append("")
    lines.append("AWS CLI v2 BUNDLES its own CPython; that interpreter is **frozen** and not "
                 "independently patchable -- the only way to move to a newer (still-supported) Python "
                 "is to move to a newer AWS CLI v2 version. On a glibc-capped OS the AWS CLI version "
                 "is capped, so the bundled Python is capped too, and when it reaches end-of-life "
                 "there is no in-place remediation. The `bundled_python` / `python_eol` columns below "
                 "let you read each tested version's interpreter and its support horizon.")
    lines.append("")
    lines.append("Python end-of-life (security-support end) -- STATIC table, **verified 2026-06-17** "
                 "from endoflife.date/python, eosl.date/eol/product/python, eol.wiki/python:")
    lines.append("")
    lines.append("| Python | EOL (security-support end) |")
    lines.append("|---|---|")
    for py, eol in [("3.6","2021-12-23"),("3.7","2023-06-27"),("3.8","2024-10-07"),
                    ("3.9","2025-10-31"),("3.10","2026-10-31"),("3.11","2027-10-31"),
                    ("3.12","2028-10-31"),("3.13","2029-10-31"),("3.14","2030-10-31")]:
        lines.append("| %s | %s |" % (py, eol))
    lines.append("")
    lines.append("## Test environment: RHEL %s (glibc %s)" % (major, glibc))
    lines.append("")
    lines.append("- `env_glibc` : %s  (`rpm -q glibc`)" % glibc)
    lines.append("- `test_host` : %s" % host_line)
    lines.append("")
    lines.append("Verdict: %s." % verdict_text)
    lines.append("")
    lines.append("| awscli_version | status | ran | bundled_python | python_eol | compat_min_glibc (measured / heuristic) | note |")
    lines.append("|---|---|---|---|---|---|---|")
    for row in table_rows:
        lines.append("| %s | %s | %s | %s | %s | %s | %s |" % (
            row["version"], row["status"],
            "yes" if row["ran"] else "no",
            row["bundled_python"], row["python_eol"],
            row["min_glibc"], row["note"]))
    lines.append("")
    lines.append("_Sweep: %d version(s) tested, %d ok. "
                 "Regenerate: `OSMAJORS=%s ./run-awscli-installtest-matrix.sh`._" % (
                     n_total, n_ok, major))
    lines.append("")

    open(os.path.join(results_dir, "RESULTS-rhel%s.md" % major), 'w').write(
        "\n".join(lines).rstrip("\n") + "\n")
    print("wrote RESULTS-rhel%s.md (%d versions, %d ok, verdict: %s)" % (
        major, n_total, n_ok, verdict_text.split("**")[1] if "**" in verdict_text else "?"))
PYREPORT
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
# (dedup by osmajor+awscli_version; last write wins). OL-aligned: adds tested_at.
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
def key(r): return (str(r.get("osmajor")), r.get("awscli_version"))
merged={}
for r in d.get("results",[]): merged[key(r)]=r
for r in rows:
    r["tested_at"] = now
    merged[key(r)]=r
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
  local majors="${OSMAJORS:-10 9 8 7 6}" major ver ref rows_tmp prep_map prepared
  rows_tmp="$(mktemp)"
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
  # r59: build version list - descending (newest first), OL parity.
  local versions
  versions="$(releases_versions 2>/dev/null | sort -t. -k1,1n -k2,2n -k3,3n -r | tr '\n' ' ')"
  local total=0 _v; for _v in ${versions}; do total=$(( total + 1 )); done
  local g_ok=0 g_fail=0 g_skip=0
  log "sweep: prepared majors=[${prepared}] versions=${total} force=${FORCE}"
  for major in ${prepared}; do
    ref="$(grep -m1 "^${major} " "${prep_map}" | cut -d' ' -f2-)"
    local idx=0 ol_ok=0 ol_fail=0 ol_skip=0
    for ver in ${versions}; do
      [ -n "${ver}" ] || continue
      awscli_in_scope "${ver}" 0 || continue
      idx=$(( idx + 1 ))
      # ledger-based skip (OL parity): if (major, ver) already in ledger, skip
      if [ "${FORCE}" != "1" ] && [ -f "${LEDGER}" ]; then
        if python3 -c "
import json,sys,os
p=sys.argv[1]
if not os.path.exists(p): sys.exit(1)
d=json.load(open(p))
k=(sys.argv[2],sys.argv[3])
sys.exit(0 if any((str(e.get('osmajor')),e.get('awscli_version'))==k for e in d.get('results',[])) else 1)
" "${LEDGER}" "${major}" "${ver}" 2>/dev/null; then
          ol_skip=$(( ol_skip + 1 )); continue
        fi
      fi
      log "RHEL${major} [${idx}/${total}] AWS CLI ${ver}: install+run test..."
      awscli_kick "${major}" "${ver}" "${ref}" "${LOG_DIR}" "${rows_tmp}"
      local st; st="$(tail -1 "${rows_tmp}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || true)"
      if [ "${st}" = "ok" ]; then ol_ok=$(( ol_ok + 1 )); else ol_fail=$(( ol_fail + 1 )); fi
    done
    log "---- RHEL${major}: sweep done -- ${ol_ok} ok, ${ol_fail} fail, ${ol_skip} skipped (of ${total}) ----"
    g_ok=$(( g_ok + ol_ok )); g_fail=$(( g_fail + ol_fail )); g_skip=$(( g_skip + ol_skip ))
  done
  log "AWS CLI matrix complete -- ${g_ok} ok, ${g_fail} fail, ${g_skip} skipped"
  rm -f "${prep_map}"
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
  # shellcheck disable=SC2086  # ent_mounts is intentionally word-split into -v/--network args
  out="$(timeout "${RUN_TIMEOUT:-600}" podman run --rm \
          -v "${INSTALL_SCRIPT}:/install-aws_awscli-v2.sh:ro,z" \
          ${ent_mounts:-} \
          -e AWSCLI_INSTALLTEST=1 -e "AWSCLI_VERSION=${ver}" -e "INSECURE_TLS=${INSECURE_TLS:-0}" \
          "${ref}" /bin/bash /install-aws_awscli-v2.sh 2>"${err_tmp}")" || rc=$?
  line="$(printf '%s
' "${out}" | grep -F '[aws_awscli-v2][installtest][result]' | tail -1)" || true  # tolerated-empty probe: no result line = reasoned error row (A.5 asymmetry)
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
    --full)             FULL=1 ;;
    --force)            FORCE=1 ;;
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
