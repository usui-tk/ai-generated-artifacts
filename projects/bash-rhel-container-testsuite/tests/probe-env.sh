#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   Unified environment probe. Default (--probe-env): classify the host and
#   every RHEL major's readiness (exec/pkgmgr/repos/egress/verdict) into
#   tests/ENV-PROBE.json. --facts: the deep entitlement fact collection
#   (F1-F7 raw logs + facts.tsv, analyzed by tools/analyze-entitlement.sh).
# ----- Prerequisites --------------------------------------------------------
#   bash 4+, curl. Readiness mode needs podman (L3). Facts mode: podman
#   preferred (required for the `mounts` condition and entitled hosts) or
#   root+chroot (sandbox fallback, anonymous facts only).
# ----- Usage examples -------------------------------------------------------
#   bash tests/probe-env.sh                     # readiness, majors 10 9 8 7 6
#   bash tests/probe-env.sh --majors "6"        # readiness, just RHEL 6
#   bash tests/probe-env.sh --facts             # entitlement fact collection
#   bash tests/probe-env.sh --facts --conds auto --outdir /tmp/probe
# ----- Known limitations ----------------------------------------------------
#   Network states are point-in-time; outputs are regenerated, not committed.
#   Facts mode is read-only by design: containers are --rm and the only host
#   writes land under the output directory.
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-04 (r39 probe unification; readiness logic from
#   the r01-r28 probe-env, fact collection from the r37 probe-entitlement)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/probe-env.sh - unified environment probe (readiness + entitlement facts)
#
# READINESS (default, --probe-env): one short-lived container per major with a
# common set of checks - does the image run at all (exec: pull, arch, old-
# userspace glibc/vsyscall), pkgmgr, whether repolist completes WITH the
# subscription-manager plugins ENABLED and NO manual mounts (the r37/r39
# correction: the pre-r39 probe disabled the very plugin that materializes
# entitled repos, and premised entitlement on manual host mounts - both wrong;
# repo access is auto-injected per container, see the Phase A probe runs),
# S3/EPEL egress, and the pure probe_verdict classifier. Output: a run-log
# banner, a readiness table, and ENV-PROBE.json. The per-major `entitlement`
# field is OBSERVED inside each container: auto-injected (/run/secrets/
# redhat.repo present) or anonymous.
#
# FACTS (--facts): the reproducible entitlement fact collection (formerly
# tests/probe-entitlement.sh, r37). Conditions per major: `auto` (plain run -
# what the runtime injects by itself) and `mounts` (the suite's legacy rhsm
# passthrough, kept ONLY as the A/B comparison arm; Phase A measured it
# harmful on every major). The in-container collector is EMITTED by
# pe_emit_collector() (unit-tested in t023) and never pipes a step's exit
# code away (the r37 collector masked s06/s12 rc behind `| tail`). Output:
# OUTDIR/{MANIFEST.txt,facts.tsv,raw/<major>/<cond>/...}.
#==============================================================================
# errexit deliberately omitted: a probe must keep going on individual failures
# and REPORT them (a failure is a fact, not an abort).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=../lib/acquire-rootfs.sh
. "${PROJ}/lib/acquire-rootfs.sh"
# shellcheck source=../lib/probe-common.sh
. "${PROJ}/lib/probe-common.sh"

OUT_JSON="${HERE}/ENV-PROBE.json"
MAJORS="${OSMAJORS:-10 9 8 7 6}"
CONDS="auto mounts"
OUTDIR=""
DEEP=1
RUN_TIMEOUT="${RUN_TIMEOUT:-900}"
PKG_TIMEOUT="${PKG_TIMEOUT:-300}"

log() { printf '%s [probe-env] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

# probe_verdict EXEC S3 EPEL REPOS : pure readiness classifier (unit-tested).
#   blocked  - the image will not even run here (exec != ok)
#   degraded - runs, but a common prerequisite a --run relies on is missing
#              (no S3 or EPEL egress, or yum still stalls)
#   ready    - runs and every common prerequisite holds
probe_verdict() {
  local exec_ok="$1" s3="$2" epel="$3" repos="$4"
  [ "${exec_ok}" = "ok" ] || { printf 'blocked'; return 0; }
  if [ "${s3}" != "ok" ] || [ "${epel}" != "ok" ] || [ "${repos}" = "no-access" ]; then
    printf 'degraded'; return 0
  fi
  printf 'ready'
}

# probe_field OUT KEY : pull KEY=... from the captured probe stdout.
probe_field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }

# probe_one MAJOR : run the common readiness probe in one short-lived
# container, print a JSON object for that major. Bounded by RUN_TIMEOUT; the
# in-container repolist is bounded by PKG_TIMEOUT. Plugins stay ENABLED and
# no mounts are added - the observed state is the auto-injected state.
probe_one() {
  local major="$1" ref out rc=0 rl exec_ok arch redhat pkgmgr repos s3 epel ent verdict
  ref="$(acq_ref_for_major "${major}")" || { printf '{"major":"%s","error":"no image ref"}' "${major}"; return 0; }
  rl="$(pc_repolist_cmd "${major}" enabled)"
  # shellcheck disable=SC2016  # $mgr/$m/$__u/$__n expand inside the container's /bin/sh, not here
  out="$(timeout "${RUN_TIMEOUT}" podman run --rm \
          -e "PKG_TIMEOUT=${PKG_TIMEOUT}" \
          "${ref}" /bin/sh -c '
            echo "EXEC=ok"
            echo "ARCH=$(uname -m 2>/dev/null)"
            echo "REDHAT=$(cat /etc/redhat-release 2>/dev/null | head -1)"
            mgr=""; for m in dnf yum; do command -v "$m" >/dev/null 2>&1 && { mgr="$m"; break; }; done
            echo "PKGMGR=${mgr:-none}"
            if [ -e /run/secrets/redhat.repo ]; then echo "ENT=auto-injected"; else echo "ENT=anonymous"; fi
            if [ -n "$mgr" ]; then
              if timeout "${PKG_TIMEOUT:-300}" '"${rl}"' >/dev/null 2>&1; then
                echo "REPOS=reachable"; else echo "REPOS=no-access"; fi
            else echo "REPOS=no-cmd"; fi
            # egress: retry the WHOLE request so a transient TLS/DNS/connection blip
            # does not flip a target to fail. curl --retry only re-tries what it
            # classifies as transient, and --retry-all-errors is curl 7.71+ (RHEL 6/7
            # ship 7.19/7.29), so we loop in the shell - version-agnostic, retrying
            # on ANY failure (max 3 tries, 1s apart).
            if command -v curl >/dev/null 2>&1; then
              egress() { __u="$1"; __n=0; while [ "$__n" -lt 3 ]; do curl -fsS --max-time 20 -o /dev/null "$__u" 2>/dev/null && return 0; __n=$((__n+1)); [ "$__n" -lt 3 ] && sleep 1; done; return 1; }
              egress https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm && echo "S3=ok" || echo "S3=fail"
              egress https://dl.fedoraproject.org/pub/epel/ && echo "EPEL=ok" || echo "EPEL=fail"
            else echo "S3=unknown"; echo "EPEL=unknown"; fi
          ' 2>/dev/null)" || rc=$?
  if [ "${rc}" = "124" ]; then
    printf '{"major":"%s","image":"%s","exec":"timeout","pkgmgr":"unknown","repos":"unknown","egress_s3":"unknown","egress_epel":"unknown","entitlement":"unknown","verdict":"blocked","reason":"probe timed out after %ss"}' \
      "${major}" "${ref}" "${RUN_TIMEOUT}"
    return 0
  fi
  exec_ok="$(probe_field "${out}" EXEC)"; [ -n "${exec_ok}" ] || exec_ok="fail"
  arch="$(probe_field "${out}" ARCH)"
  redhat="$(probe_field "${out}" REDHAT)"
  pkgmgr="$(probe_field "${out}" PKGMGR)"; [ -n "${pkgmgr}" ] || pkgmgr="unknown"
  repos="$(probe_field "${out}" REPOS)"; [ -n "${repos}" ] || repos="unknown"
  s3="$(probe_field "${out}" S3)"; [ -n "${s3}" ] || s3="unknown"
  epel="$(probe_field "${out}" EPEL)"; [ -n "${epel}" ] || epel="unknown"
  ent="$(probe_field "${out}" ENT)"; [ -n "${ent}" ] || ent="unknown"
  verdict="$(probe_verdict "${exec_ok}" "${s3}" "${epel}" "${repos}")"
  printf '{"major":"%s","image":"%s","arch":"%s","redhat_release":"%s","exec":"%s","pkgmgr":"%s","repos":"%s","egress_s3":"%s","egress_epel":"%s","entitlement":"%s","verdict":"%s"}' \
    "${major}" "${ref}" "${arch}" "$(jesc "${redhat}")" "${exec_ok}" "${pkgmgr}" "${repos}" "${s3}" "${epel}" "${ent}" "${verdict}"
}

probe_readiness() {
  command -v podman >/dev/null 2>&1 || { log "ERROR: --probe-env needs podman (L3)"; return 2; }
  host_banner
  log "probing majors: [${MAJORS}] (RUN_TIMEOUT=${RUN_TIMEOUT}s, PKG_TIMEOUT=${PKG_TIMEOUT}s)"
  local first=1 major j plat
  {
    plat="$(acq_platform)"
    log "platform: ${plat} | repolist runs plugins-ENABLED, no mounts (observed auto-injection)"
    printf '{\n  "host": %s,\n  "platform": "%s",\n  "probes": [\n' "$(host_json)" "${plat}"
    for major in ${MAJORS}; do
      j="$(probe_one "${major}")"
      [ "${first}" = 1 ] || printf ',\n'
      first=0
      printf '    %s' "${j}"
      log "RHEL${major}: $(printf '%s' "${j}" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    print("%s | exec=%s repos=%s s3=%s epel=%s ent=%s -> %s" % (d.get("image","?"),d.get("exec","?"),d.get("repos","?"),d.get("egress_s3","?"),d.get("egress_epel","?"),d.get("entitlement","?"),d.get("verdict","?")))
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
hdr=("major","pkgmgr","exec","repos","s3","epel","entitle","verdict")
print("%-6s %-8s %-8s %-10s %-6s %-6s %-13s %s" % hdr)
for p in d.get("probes",[]):
    print("%-6s %-8s %-8s %-10s %-6s %-6s %-13s %s" % (
        "RHEL"+str(p.get("major","?")), p.get("pkgmgr","?"), p.get("exec","?"),
        p.get("repos","?"), p.get("egress_s3","?"), p.get("egress_epel","?"),
        p.get("entitlement","?"), p.get("verdict","?")))
print("\nverdict: ready = all common prerequisites hold; degraded = runs but egress/repo gap; blocked = image will not run here.")
PY
}

# ---------------------------------------------------------------------------
# --facts mode: the reproducible entitlement fact collection (ex r37
# tests/probe-entitlement.sh; see TESTING.md "Entitlement fact-probe").
# ---------------------------------------------------------------------------

# pe_emit_collector MAJOR DEEP PKG_TIMEOUT - print the in-container collector
# script. Pure text emission (unit-tested): static parts are QUOTED heredocs
# (what you read is what runs - no emit-time expansion surprises); the per-
# major dynamic lines are printf-inserted. The dnf-only repoinfo step is
# resolved at EMIT time so a yum collector carries no dnf syntax at all.
# No step pipes its exit code away (r37 masked s06/s12 rc behind `| tail`).
pe_emit_collector() {
  local major="$1" deep="$2" ptmo="$3" pm
  pm="$(pc_pm_for_major "${major}")" || return 1
  printf '#!/bin/bash\n# emitted by probe-env.sh --facts - runs INSIDE the image; writes /probe-out only\nset -u\nO=/probe-out\nT=%s\n' "${ptmo}"
  cat <<'PART1'
r() { n="$1"; shift; printf '%s\n' "$*" > "$O/$n.cmd"
      timeout "$T" bash -c "$*" > "$O/$n.out" 2>&1; echo $? > "$O/$n.rc"; }
r s01-os        'cat /etc/redhat-release; uname -m; id -u'
r s02-files-pre 'ls -la /etc/yum.repos.d/ 2>&1; sha256sum /etc/yum.repos.d/*.repo 2>&1'
mkdir -p "$O/files-pre" "$O/files-post" "$O/certs"
cp -p /etc/yum.repos.d/*.repo "$O/files-pre/" 2>/dev/null
cp -p /etc/pki/product-default/*.pem /etc/pki/product/*.pem "$O/certs/" 2>/dev/null
r s03-secrets   'ls -laR /run/secrets/ 2>&1; sha256sum /run/secrets/redhat.repo 2>&1; ls -laR /etc/pki/rhui/ 2>&1'
PART1
  printf "r s04-repolist-enabled-pre '%s'\n" "$(pc_repolist_cmd "${major}" enabled)"
  printf "r s05-repolist-all         '%s'\n" "$(pc_repolist_cmd "${major}" all)"
  printf "r s06-trigger              '%s -q makecache'\n" "${pm}"
  cat <<'PART2'
cp -p /etc/yum.repos.d/*.repo "$O/files-post/" 2>/dev/null
r s07-files-post 'ls -la /etc/yum.repos.d/ 2>&1; sha256sum /etc/yum.repos.d/*.repo 2>&1'
PART2
  printf "r s08-repolist-enabled-post '%s'\n" "$(pc_repolist_cmd "${major}" enabled)"
  cat <<'PART2B'
r s13-sm-packages 'rpm -qa "subscription-manager*" "*rhsm*" "python*subscription*" 2>&1 | sort'
PART2B
  if [ "${pm}" = dnf ]; then
    cat <<'PART3'
r s09-repoinfo 'for i in $(dnf -q repolist --enabled 2>/dev/null | awk "NR>1{print \$1}"); do dnf -q repoinfo "$i" | grep -E "^Repo-(id|filename)"; done'
PART3
  fi
  printf "r s10-resolve-build   '%s'\n" "$(pc_resolve_cmd "${pm}" "${deep}" "$(pc_build_pkgset)")"
  printf "r s11-resolve-install '%s'\n" "$(pc_resolve_cmd "${pm}" "${deep}" "$(pc_install_pkgset)")"
  cat <<'PART4'
cand=$(grep -Eio '(codeready-builder-for-rhel-[0-9a-z_.-]+-rpms|rhel-[0-9]+-server-optional-rpms)' "$O/s05-repolist-all.out" 2>/dev/null | sort -u)
printf '%s\n' "$cand" > "$O/s12-crb-candidates.out"
PART4
  # shellcheck disable=SC2016  # $cand/$k/$c expand inside the EMITTED script, not here
  printf 'k=0; for c in $cand; do k=$((k+1))\n  r "s12-crb-enable-$k" "echo repo=$c; %s -q --enablerepo=$c makecache"\ndone\nexit 0\n' "${pm}"
}

# pe_record OUT MAJOR COND KEY VALUE - append one facts.tsv row.
pe_record() { pc_tsv_row "$2" "$3" "$4" "$5" "$6" >> "$1/facts.tsv"; }

# pe_docmount_args - the mount set from the user-provided AWS-RHUI article
# (2026-07-04): whole /etc/yum.repos.d + /etc/pki/rhui + the dnf/yum plugin
# CONFIG dirs, all :ro. Treated as a HYPOTHESIS to verify (the article claims
# this makes RHUI repos work in UBI containers; our r41/r42 runs saw literal
# REGION DNS failures and repomd 403 with a narrower set) - hence its own
# probe condition, `docmounts`, for the A/B/C comparison.
pe_docmount_args() {
  local d
  for d in /etc/yum.repos.d /etc/pki/rhui /etc/dnf/plugins /etc/yum/pluginconf.d; do
    [ -d "${d}" ] && printf -- '-v %s:%s:ro ' "${d}" "${d}"
  done
}

# pe_collect_podman MAJOR COND DIR MODE - one podman run executes the
# collector. MODE (rhsm | rhui:<provider> | oci-ol | none, from
# acq_repo_access) selects which legacy mount set the `mounts` A/B arm
# applies - rhsm on subscription-manager hosts, the RHUI file/cert set on
# AWS/Azure RHUI hosts (r40: RHUI is now a first-class probed environment).
# The `docmounts` arm (r44) applies pe_docmount_args instead.
pe_collect_podman() {
  local major="$1" cond="$2" dir="$3" mode="$4" ref margs=""
  ref="$(acq_ref_for_major "${major}")" || return 1
  case "${cond}" in
    mounts)    margs="$(acq_entitlement_mount_args "${mode}")" ;;
    docmounts) margs="$(pe_docmount_args)" ;;
  esac
  pe_emit_collector "${major}" "${DEEP}" "${PKG_TIMEOUT}" > "${dir}/collector.sh"
  # shellcheck disable=SC2086  # margs is an intentional argv fragment
  timeout "${RUN_TIMEOUT}" podman run --rm ${margs} \
    -v "${dir}:/probe-out:rw,Z" "${ref}" /bin/bash /probe-out/collector.sh
}

# pe_collect_chroot MAJOR COND DIR - sandbox fallback: curl-pull the rootfs,
# bind /proc,/dev + the out dir, run the collector via chroot. Root required.
pe_collect_chroot() {
  local major="$1" cond="$2" dir="$3" work rc
  if [ "${cond}" != auto ]; then return 90; fi
  work="$(mktemp -d /tmp/probe-ent.XXXXXX)"
  if ! acq_pull_curl "${major}" "${work}/root"; then rm -rf "${work}"; return 91; fi
  cp /etc/resolv.conf "${work}/root/etc/resolv.conf" 2>/dev/null
  mkdir -p "${work}/root/probe-out"
  pe_emit_collector "${major}" "${DEEP}" "${PKG_TIMEOUT}" > "${dir}/collector.sh"
  mount --bind "${dir}" "${work}/root/probe-out" && \
    mount -t proc proc "${work}/root/proc" && \
    mount --bind /dev "${work}/root/dev"
  timeout "${RUN_TIMEOUT}" chroot "${work}/root" /bin/bash /probe-out/collector.sh
  rc=$?
  umount "${work}/root/dev" "${work}/root/proc" "${work}/root/probe-out" 2>/dev/null
  rm -rf "${work}"
  return "${rc}"
}

# pe_host_inventory OUTDIR - host-side facts the container-side collection
# cannot see: the repo-access classification, the host's repo definition
# files, and CERTIFICATE METADATA ONLY (subject/issuer/dates via openssl;
# private keys and PEM bodies are deliberately NOT collected - the output
# directory travels between machines).
pe_host_inventory() {
  local h="$1/host" f
  mkdir -p "${h}/yum.repos.d"
  { uname -a; cat /etc/redhat-release 2>/dev/null; } > "${h}/host-os.txt" 2>&1
  acq_repo_access > "${h}/repo-access.txt" 2>/dev/null
  rpm -qa 'subscription-manager*' 'rh-amazon-rhui-client*' 'rhui-azure-rhel*' \
          'google-rhui-client*' 2>/dev/null | sort > "${h}/host-packages.txt"
  for f in /etc/yum.repos.d/*.repo; do
    [ -f "${f}" ] && cp -p "${f}" "${h}/yum.repos.d/" 2>/dev/null
  done
  : > "${h}/certs.txt"
  for f in /etc/pki/entitlement/*.pem /etc/pki/rhui/*.pem /etc/pki/rhui/*.crt \
           /etc/pki/rhui/product/*.pem /etc/pki/rhui/product/*.crt; do
    [ -e "${f}" ] || continue
    case "${f}" in *-key.pem|*key*) continue ;; esac
    {
      printf '== %s ==\n' "${f}"
      openssl x509 -in "${f}" -noout -subject -issuer -dates 2>&1
    } >> "${h}/certs.txt"
  done
  # r42: the AUTHORITATIVE authorization list lives inside the certificates
  # themselves - rct cat-cert (ships with subscription-manager) decodes the
  # content-set extension into readable paths. Text only; no key material.
  # (r43 finding: AWS RHUI client certs are content-set-LESS identity certs,
  # so authorization is server-side - see the client-implementation capture.)
  if command -v rct >/dev/null 2>&1; then
    : > "${h}/content-sets.txt"
    for f in /etc/pki/rhui/product/*.crt /etc/pki/rhui/product/*.pem \
             /etc/pki/entitlement/*.pem; do
      [ -e "${f}" ] || continue
      case "${f}" in *-key.pem|*key*) continue ;; esac
      {
        printf '== rct cat-cert %s ==\n' "${f}"
        rct cat-cert "${f}" 2>&1
      } >> "${h}/content-sets.txt"
    done
  fi
  # r43: capture the RHUI client IMPLEMENTATION (package file list, dnf
  # plugin/config sources, dnf vars). Motivation: with identity-only certs
  # AND repomd_http=403 even for the host's own major, whatever dnf sends
  # beyond the bare TLS client cert must live in this client machinery.
  # Code and config only - no secrets.
  local pkg
  for pkg in rh-amazon-rhui-client rhui-azure-rhel10 rhui-azure-rhel9 \
             rhui-azure-rhel8 google-rhui-client; do
    rpm -q "${pkg}" >/dev/null 2>&1 || continue
    rpm -ql "${pkg}" > "${h}/rhui-client-files-${pkg}.txt" 2>/dev/null
    mkdir -p "${h}/rhui-client-src"
    while IFS= read -r f; do
      case "${f}" in
        *.py|*.conf|*.repo|*/dnf/vars/*|*/yum/vars/*)
          [ -f "${f}" ] && cp -p "${f}" "${h}/rhui-client-src/" 2>/dev/null ;;
      esac
    done < "${h}/rhui-client-files-${pkg}.txt"
  done
  if [ -d /etc/dnf/vars ]; then
    { ls -la /etc/dnf/vars/; grep -r . /etc/dnf/vars/ 2>/dev/null; } \
      > "${h}/dnf-vars.txt" 2>&1
  fi
}

# pe_rhui_crossmajor_check OUTDIR - AWS-RHUI host-side fact: does THIS host's
# RHUI client certificate authorize OTHER majors' content paths? Read-only
# HTTPS status checks against per-major URLs synthesized from the host's own
# redhat-rhui.repo template (REGION resolved via IMDS); rhel99 is the
# calibration control (expected non-200). Certs/keys are used IN PLACE on the
# host and never copied. Answers the Phase A question that decides whether a
# per-major synthesized-repo design is viable on RHUI (Step 4 input).
pe_rhui_crossmajor_check() {
  local out="$1/host/rhui-crossmajor.txt" repo=/etc/yum.repos.d/redhat-rhui.repo
  local sec tmpl cert key ca tok region url m caarg=()
  [ -f "${repo}" ] || return 0
  sec="$(awk '/^\[rhel-[0-9]+-baseos-rhui-rpms\]/{f=1;next} /^\[/{f=0} f' "${repo}")"
  tmpl="$(printf '%s\n' "${sec}" | sed -n 's/^mirrorlist=//p' | head -1)"
  cert="$(printf '%s\n' "${sec}" | sed -n 's/^sslclientcert=//p' | head -1)"
  key="$(printf '%s\n' "${sec}" | sed -n 's/^sslclientkey=//p' | head -1)"
  ca="$(printf '%s\n' "${sec}" | sed -n 's/^sslcacert=//p' | head -1)"
  if [ -z "${tmpl}" ] || [ ! -f "${cert}" ] || [ ! -f "${key}" ]; then
    echo "skipped: baseos template or client cert/key unavailable" > "${out}"; return 0
  fi
  tok="$(curl -sS -m 5 -X PUT http://169.254.169.254/latest/api/token \
          -H 'X-aws-ec2-metadata-token-ttl-seconds: 120' 2>/dev/null)"
  region="$(curl -sS -m 5 -H "X-aws-ec2-metadata-token: ${tok}" \
          http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null)"
  [ -n "${region}" ] || region="$(curl -sS -m 5 \
          http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null)"
  {
    echo "region=${region:-unresolved}"; echo "template=${tmpl}"
    echo "cert=${cert}"; echo "key=(used in place, not recorded)"
  } > "${out}"
  [ -n "${region}" ] || { echo "skipped: region unresolved via IMDS" >> "${out}"; return 0; }
  [ -n "${ca}" ] && [ -f "${ca}" ] && caarg=(--cacert "${ca}")
  # r45: the amazon-id dnf plugin (captured r43, read from source) shows AWS
  # RHUI authorization = TLS client cert AND the SIGNED instance-identity
  # document, sent as X-RHUI-ID / X-RHUI-SIGNATURE (urlsafe base64) on every
  # request - which is why bare-cert curl got 403 even for the host's own
  # major. Replicate exactly that here.
  local id_doc id_sig hdrid=() hdrsig=()
  id_doc="$(curl -sS -m 5 -H "X-aws-ec2-metadata-token: ${tok}" \
            http://169.254.169.254/latest/dynamic/instance-identity/document 2>/dev/null)"
  id_sig="$(curl -sS -m 5 -H "X-aws-ec2-metadata-token: ${tok}" \
            http://169.254.169.254/latest/dynamic/instance-identity/signature 2>/dev/null)"
  if [ -n "${id_doc}" ] && [ -n "${id_sig}" ]; then
    hdrid=(-H "X-RHUI-ID: $(printf '%s' "${id_doc}" | pc_b64url)")
    hdrsig=(-H "X-RHUI-SIGNATURE: $(printf '%s' "${id_sig}" | pc_b64url)")
    echo "identity_headers=present" >> "${out}"
  else
    echo "identity_headers=UNAVAILABLE (expect 403s)" >> "${out}"
  fi
  # r42: the mirrorlist endpoint answers 200 regardless of path validity
  # (measured 2026-07-04: even the rhel99 control got 200), so authorization
  # must be probed one layer deeper - follow the mirrorlist BODY to the first
  # real mirror and GET its repodata/repomd.xml with the client cert.
  pe_rhui_check_one() {
    local label="$1" url="$2" body mlst first rstat
    body="$(curl -sS -m 20 --cert "${cert}" --key "${key}" "${caarg[@]}" \
             "${hdrid[@]}" "${hdrsig[@]}" \
             -w '\n__HTTP__%{http_code}' "${url}" 2>/dev/null)"
    mlst="${body##*__HTTP__}"
    first="$(printf '%s\n' "${body}" | grep -Eo 'https?://[^[:space:]]+' | grep -v '__HTTP__' | head -1)"
    if [ -n "${first}" ]; then
      rstat="$(curl -sS -m 20 -o /dev/null -w '%{http_code}' \
                --cert "${cert}" --key "${key}" "${caarg[@]}" \
                "${hdrid[@]}" "${hdrsig[@]}" \
                "${first%/}/repodata/repomd.xml" 2>/dev/null)"
    else
      rstat="no-mirror"
    fi
    printf '%s mirrorlist_http=%s repomd_http=%s first_mirror=%s\n' \
      "${label}" "${mlst:-000}" "${rstat}" "${first:-none}" >> "${out}"
  }
  for m in 10 9 8 99; do
    url="$(pc_rhui_major_url "${tmpl}" "${m}" | sed "s/REGION/${region}/")"
    pe_rhui_check_one "major=${m}" "${url}"
  done
  for m in 7 6; do
    url="https://rhui.${region}.aws.ce.redhat.com/pulp/mirror/content/dist/rhel/rhui/server/${m}/${m}Server/x86_64/os"
    pe_rhui_check_one "major=${m}(legacy)" "${url}"
  done
}

pe_facts() {
  local engine major cond dir rc pem tags pid ts mode=none
  if command -v podman >/dev/null 2>&1; then engine=podman
  elif [ "$(id -u)" = 0 ] && command -v chroot >/dev/null 2>&1; then engine=chroot
  else log "--facts needs podman, or root+chroot"; return 2; fi
  mode="$(acq_repo_access | cut -d'|' -f1)"
  # r44: on RHUI hosts, add the article-recipe arm to the DEFAULT condition
  # set (explicit --conds always wins).
  if [ "${CONDS}" = "auto mounts" ]; then
    case "${mode}" in rhui:*) CONDS="auto mounts docmounts" ;; esac
  fi
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  OUTDIR="${OUTDIR:-${HERE}/ENTITLEMENT-PROBE-${ts}}"
  mkdir -p "${OUTDIR}"
  {
    echo "engine=${engine}"; echo "date_utc=${ts}"; echo "majors=${MAJORS}"
    echo "conds=${CONDS}"; echo "deep=${DEEP}"; echo "repo_access=${mode}"
    echo "build_pkgs=$(pc_build_pkgset)"; echo "install_pkgs=$(pc_install_pkgset)"
    echo "host=$(uname -sr)"
  } > "${OUTDIR}/MANIFEST.txt"
  pe_host_inventory "${OUTDIR}"
  case "${mode}" in rhui:aws) pe_rhui_crossmajor_check "${OUTDIR}" ;; esac
  : > "${OUTDIR}/facts.tsv"
  for major in ${MAJORS}; do
    for cond in ${CONDS}; do
      dir="${OUTDIR}/raw/${major}/${cond}"; mkdir -p "${dir}"
      log "collect major=${major} cond=${cond} engine=${engine} mode=${mode}"
      if [ "${engine}" = podman ]; then pe_collect_podman "${major}" "${cond}" "${dir}" "${mode}"
      else pe_collect_chroot "${major}" "${cond}" "${dir}"; fi
      rc=$?
      pe_record "${OUTDIR}" meta "${major}" "${cond}" collect_rc "${rc}"
      case "${rc}" in
        0)  pe_record "${OUTDIR}" meta "${major}" "${cond}" status ok ;;
        90) pe_record "${OUTDIR}" meta "${major}" "${cond}" status requires-podman ;;
        91) pe_record "${OUTDIR}" meta "${major}" "${cond}" status pull-fail ;;
        *)  pe_record "${OUTDIR}" meta "${major}" "${cond}" status "$(pc_step_verdict "${rc}")" ;;
      esac
      for pem in "${dir}/certs/"*.pem; do
        [ -e "${pem}" ] || continue
        pid="$(pc_product_id "${pem}" 2>/dev/null)" || pid="?"
        tags="$(pc_product_tags "${pem}" 2>/dev/null)" || tags="?"
        pe_record "${OUTDIR}" cert "${major}" "${cond}" "product-$(basename "${pem}")" "id=${pid} tags=${tags}"
      done
    done
  done
  log "done -> ${OUTDIR}"
  if tar czf "${OUTDIR}.tar.gz" -C "$(dirname "${OUTDIR}")" "$(basename "${OUTDIR}")" 2>/dev/null; then
    log "packed -> ${OUTDIR}.tar.gz (attach this file for analysis)"
  fi
  log "analyze: bash tools/analyze-entitlement.sh ${OUTDIR}"
}

# ---------------------------------------------------------------------------
# --smoke mode (r47, user requirement): ONE command, EVERY major, ONE sample
# per tool - a quick suite-health signal without the full matrix sweeps.
# Reuses the tested pipeline as-is (provision_prepare_majors + the install
# scripts' test mode) and touches NO ledgers/RESULTS files.
# ---------------------------------------------------------------------------

# pe_smoke_latest RELEASES_JSON - the newest version in the tool's releases
# file (numeric-component sort; the matrices' in-scope filtering is not
# needed for a single-latest smoke sample).
pe_smoke_latest() {
  python3 - "$1" <<'PYEOF'
import json,re,sys
d=json.load(open(sys.argv[1]))
vs=[(x.get("version") if isinstance(x,dict) else x) for x in (d.get("versions") or [])]
vs=[v for v in vs if v]
key=lambda v:[int(x) for x in re.findall(r"\d+", str(v))]
print(sorted(vs,key=key)[-1] if vs else "")
PYEOF
}

# pe_result_field TEXT FIELD - pull FIELD out of the single-line
# "[...][result] {json}" an install script emits ("" if absent/unparsable).
pe_result_field() {
  PE_RESULT_TEXT="$1" python3 - "$2" <<'PYEOF'
import json,os,sys
field=sys.argv[1]
val=""
for line in os.environ.get("PE_RESULT_TEXT","").splitlines():
    i=line.find("[result] ")
    if i<0: continue
    try: val=str(json.loads(line[i+9:]).get(field,""))
    except Exception: pass
print(val)
PYEOF
}

# pe_smoke_expected STATUS - rc0 iff STATUS is a healthy/EXPECTED
# classification: ok, unsupported (measured platform incompatibility, e.g.
# EL6+latest agent), unavailable (artifact not published). ENA's anonymous
# needs-entitlement path reports status=ok with a reason, so it is covered.
pe_smoke_expected() {
  case "$1" in ok|unsupported|unavailable) return 0 ;; *) return 1 ;; esac
}

# pe_smoke_tool_spec TOOL ENA_ENT - set SMK_SCRIPT / SMK_VER / SMK_ENVS for a
# tool sample (latest released version, the install script's test mode).
pe_smoke_tool_spec() {
  local tool="$1" ena_ent="$2"
  case "${tool}" in
    awscli) SMK_SCRIPT="${PROJ}/install-aws_awscli-v2.sh"
            SMK_VER="$(pe_smoke_latest "${PROJ}/tests/aws_awscli-v2/awscli-releases.json")"
            SMK_ENVS=(AWSCLI_INSTALLTEST=1 "AWSCLI_VERSION=${SMK_VER}") ;;
    ssm)    SMK_SCRIPT="${PROJ}/install-aws_ssm-agent.sh"
            SMK_VER="$(pe_smoke_latest "${PROJ}/tests/aws_ssm-agent/ssm-releases.json")"
            SMK_ENVS=(SSM_INSTALLTEST=1 "SSM_VERSION=${SMK_VER}" SSM_INIT_MODE=none) ;;
    ena)    SMK_SCRIPT="${PROJ}/install-aws_ena-driver.sh"
            SMK_VER="$(pe_smoke_latest "${PROJ}/tests/aws_ena-driver/ena-driver-releases.json")"
            SMK_ENVS=(ENA_INSTALLTEST=1 "ENA_VERSION=${SMK_VER}" "ENA_ENTITLEMENT=${ena_ent}" ENA_BUILD_PLAN=make) ;;
    *) log "smoke: unknown tool '${tool}'"; return 1 ;;
  esac
}

# pe_smoke_record MAJOR TOOL VER STATUS REASON OUT RC - classify one cell,
# save the full container/chroot output for NON-expected cells (r48: the
# first smoke E2E could not diagnose its failures for lack of logs).
pe_smoke_record() {
  local major="$1" tool="$2" ver="$3" status="$4" reason="$5" out="$6" rc="$7"
  if [ -z "${status}" ]; then status="error"; reason="rc=${rc}, no [result] line"; fi
  if ! pe_smoke_expected "${status}"; then
    SMK_FAILS=$((SMK_FAILS+1))
    mkdir -p "${SMK_LOGDIR}"
    printf '%s\n' "${out}" > "${SMK_LOGDIR}/rhel${major}-${tool}.log"
  fi
  SMK_ROWS="${SMK_ROWS}$(printf '%-7s %-7s %-14s %-12s %s' "RHEL${major}" "${tool}" "${ver}" "${status}" "${reason:--}")
"
  log "RHEL${major} ${tool} ${ver}: ${status}${reason:+ (${reason})}"
}

# pe_smoke_umount_all - undo the chroot-engine mounts; trap-wired so failures
# and interrupts never leave /proc//dev bind mounts behind.
pe_smoke_umount_all() {
  local d
  for d in ${SMK_MOUNTED}; do
    umount "${d}/dev" 2>/dev/null || true
    umount "${d}/proc" 2>/dev/null || true
  done
  SMK_MOUNTED=""
}

# pe_smoke - one command, every major, one latest sample per tool. Engines:
# podman (provisioned image per major; images removed on exit per the r48
# cleanup requirement) or, on a rootless/podman-less ROOT sandbox, a chroot
# fallback (curl-pulled rootfs + best-effort anonymous provisioning) so the
# suite can self-verify smoke-level behavior before user evaluation.
pe_smoke() {
  local engine major ref tool out rc status reason mode ena_ent prep_map d mgr so eargs kv
  if command -v podman >/dev/null 2>&1; then engine=podman
  elif [ "$(id -u)" = 0 ] && command -v chroot >/dev/null 2>&1; then engine=chroot
  else log "--smoke needs podman, or root+chroot"; return 2; fi
  # shellcheck source=../lib/provision-test-env.sh
  . "${PROJ}/lib/provision-test-env.sh"
  host_banner
  mode="$(acq_repo_access | cut -d'|' -f1)"
  case "${mode}" in rhsm) ena_ent=entitled ;; *) ena_ent=anonymous ;; esac
  SMK_FAILS=0; SMK_ROWS=""; SMK_MOUNTED=""
  SMK_LOGDIR="${HERE}/SMOKE-LOGS-$(date -u +%Y%m%dT%H%M%SZ)"
  log "smoke: engine=${engine} majors [${MAJORS}] x tools [${SMOKE_TOOLS:-awscli ssm ena}] (mode=${mode}, latest version each)"
  if [ "${engine}" = podman ]; then
    # r48 (user requirement): provisioned test-env images are removed on
    # EVERY exit path; KEEP_TEST_IMAGES=1 opts out. Base images stay.
    trap provision_cleanup_images EXIT
    prep_map="$(mktemp)"
    provision_prepare_majors "${MAJORS}" "" "${prep_map}" || { rm -f "${prep_map}"; return 2; }
    while IFS=' ' read -r major ref; do
      [ -n "${major}" ] || continue
      for tool in ${SMOKE_TOOLS:-awscli ssm ena}; do
        pe_smoke_tool_spec "${tool}" "${ena_ent}" || continue
        eargs=(); for kv in "${SMK_ENVS[@]}"; do eargs+=(-e "${kv}"); done
        out="$(timeout "${RUN_TIMEOUT}" podman run --rm -v "${SMK_SCRIPT}:/smoke.sh:ro,z" \
                -e "INSECURE_TLS=${INSECURE_TLS:-0}" -e "PKG_TIMEOUT=${PKG_TIMEOUT}" "${eargs[@]}" \
                "${ref}" /bin/bash /smoke.sh 2>&1)"; rc=$?
        status="$(pe_result_field "${out}" status)"
        reason="$(pe_result_field "${out}" reason)"
        pe_smoke_record "${major}" "${tool}" "${SMK_VER}" "${status}" "${reason}" "${out}" "${rc}"
      done
    done < "${prep_map}"
    rm -f "${prep_map}"
  else
    trap pe_smoke_umount_all EXIT
    for major in ${MAJORS}; do
      d="${TMPDIR:-/tmp}/probe-smoke-$$/rhel${major}"
      rm -rf "${d}"; mkdir -p "${d}"
      if ! acq_pull_curl "${major}" "${d}" >/dev/null 2>&1; then
        pe_smoke_record "${major}" "-" "-" "error" "rootfs pull failed" "" 1
        rm -rf "${d}"; continue
      fi
      cp /etc/resolv.conf "${d}/etc/" 2>/dev/null || true
      mount -t proc proc "${d}/proc" 2>/dev/null || true
      mount --bind /dev "${d}/dev" 2>/dev/null || true
      SMK_MOUNTED="${SMK_MOUNTED} ${d}"
      mgr=dnf; chroot "${d}" /bin/sh -c 'command -v dnf' >/dev/null 2>&1 || mgr=yum
      so=""; [ "${INSECURE_TLS:-0}" = "1" ] && so="--setopt=sslverify=0"
      # shellcheck disable=SC2086  # so/PROVISION_PKGS word-split intentionally
      timeout "${PKG_TIMEOUT}" chroot "${d}" "${mgr}" -y -q ${so} install ${PROVISION_PKGS} >/dev/null 2>&1 \
        || log "RHEL${major}: chroot provisioning failed (anonymous rootfs; continuing best-effort)"
      for tool in ${SMOKE_TOOLS:-awscli ssm ena}; do
        pe_smoke_tool_spec "${tool}" "${ena_ent}" || continue
        cp "${SMK_SCRIPT}" "${d}/tmp/smoke.sh"
        out="$(timeout "${RUN_TIMEOUT}" chroot "${d}" /usr/bin/env "${SMK_ENVS[@]}" \
                "INSECURE_TLS=${INSECURE_TLS:-0}" "PKG_TIMEOUT=${PKG_TIMEOUT}" \
                bash /tmp/smoke.sh 2>&1)"; rc=$?
        status="$(pe_result_field "${out}" status)"
        reason="$(pe_result_field "${out}" reason)"
        pe_smoke_record "${major}" "${tool}" "${SMK_VER}" "${status}" "${reason}" "${out}" "${rc}"
      done
      umount "${d}/dev" 2>/dev/null || true
      umount "${d}/proc" 2>/dev/null || true
      SMK_MOUNTED="${SMK_MOUNTED/ ${d}/}"
      rm -rf "${d}"
    done
    rm -rf "${TMPDIR:-/tmp}/probe-smoke-$$"
  fi
  printf '\n== smoke (1 sample/tool, every major; engine=%s, mode=%s) ==\n' "${engine}" "${mode}"
  printf '%-7s %-7s %-14s %-12s %s\n' major tool version status note
  printf '%s' "${SMK_ROWS}"
  printf '\nexpected statuses: ok / unsupported / unavailable (needs-entitlement rides on ok)\n'
  [ -d "${SMK_LOGDIR}" ] && printf 'failure logs: %s\n' "${SMK_LOGDIR}"
  printf 'smoke: %s\n' "$( [ "${SMK_FAILS}" -eq 0 ] && echo 'ALL OK / EXPECTED' || echo "${SMK_FAILS} unexpected cell(s)" )"
  [ "${SMK_FAILS}" -eq 0 ]
}

pe_main() {
  local action=readiness
  while [ $# -gt 0 ]; do
    case "$1" in
      --probe-env) action=readiness; shift ;;
      --facts)     action=facts; shift ;;
      --smoke)     action=smoke; shift ;;
      --majors)    MAJORS="$2"; shift 2 ;;
      --conds)     CONDS="$2"; shift 2 ;;
      --outdir)    OUTDIR="$2"; shift 2 ;;
      --json)      OUT_JSON="$2"; shift 2 ;;
      --shallow)   DEEP=0; shift ;;
      -h|--help)   printf 'usage: probe-env.sh [--probe-env|--facts|--smoke] [--majors "10 9 8 7 6"]\n'
                   printf '       readiness: [--json PATH]\n'
                   printf '       facts:     [--conds "auto mounts"] [--outdir DIR] [--shallow]\n'; return 0 ;;
      *)           log "unknown arg: $1"; return 2 ;;
    esac
  done
  case "${action}" in
    facts) pe_facts ;;
    smoke) pe_smoke ;;
    *)     probe_readiness ;;
  esac
}

# t017/t023 source this file with PE_SOURCED=1 to unit-test the pure layer.
if [ "${PE_SOURCED:-0}" != 1 ]; then
  pe_main "$@"
fi
