#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   Standalone AWS-RHUI fact collector. Runs ON a real AWS EC2 RHEL host
#   (majors 6-10) and gathers everything needed to answer "does AWS RHUI authorize by
#   OS major, or only by configuration/parameters?" - the pre-work for deciding
#   whether the suite's RHSM-entitled tests can run under RHUI instead. Output
#   is a SINGLE tar.gz for offline analysis by Claude.
#     Categories: (base) OS/repos/RHUI-client RPM/plugins/dnf-vars/repolist;
#     (certs) the FULL /etc/pki/rhui tree INCLUDING PRIVATE KEYS + openssl/rct
#     decodes; (crossmajor) host-cert HTTPS reachability of OTHER majors'
#     content paths; (eus) EUS/ELS/AUS/E4S repo enumeration; (leapp) a
#     NON-DESTRUCTIVE `leapp preupgrade --no-rhsm` dry-run that materializes the
#     N+1 major's repos (majors 7/8/9 only).
# ----- Prerequisites --------------------------------------------------------
#   bash 4+, run as root on the target RHEL EC2 instance, curl, tar, openssl.
#   Network egress to the region RHUI endpoint + IMDS. The instance is expected
#   to be DISPOSABLE: --leapp installs packages and writes /var/log/leapp.
# ----- Usage examples -------------------------------------------------------
#   sudo bash collect-rhui-facts.sh                 # auto-detect major, full run
#   sudo bash collect-aws-rhui-facts.sh --no-leapp      # skip the preupgrade dry-run
#   sudo bash collect-aws-rhui-facts.sh --chain         # r74: 8->9->10 cert-chain probe
#   sudo bash collect-rhui-facts.sh --major 8 --outdir /tmp/rhui
#   sudo bash collect-rhui-facts.sh --no-crossmajor --no-eus
# ----- Known limitations ----------------------------------------------------
#   * The output tar.gz CONTAINS PRIVATE KEYS (RHUI entitlement credential).
#     Treat it as a secret: never commit it, transfer over a secure channel.
#   * leapp preupgrade is dry-run only; this script NEVER runs `leapp upgrade`.
#     The EUS `--channel eus` preupgrade variant is out of scope here (base+eus
#     enumeration captures the EUS repo shape; a dedicated channel preupgrade is
#     a follow-up if the analysis needs it).
#   * Network states are point-in-time. Real-RHUI E2E is the operator's task
#     (this sandbox cannot reproduce RHUI responses).
#   * AWS-SPECIFIC: the RHUI endpoint shape, the IMDS-signed instance-identity
#     authorization (X-RHUI-ID / X-RHUI-SIGNATURE), and the leapp-rhui-aws
#     package are all AWS. Azure / GCP get their own sibling collectors
#     (collect-azure-rhui-facts.sh / collect-gcp-rhui-facts.sh) - do NOT
#     overload this one with other clouds.
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Opus 4.8), claude.ai sessions
#   Generation date: 2026-07-08 (RHUI entitlement investigation; helpers are
#   reuse-by-copy of tests/probe-env.sh pe_host_inventory / pe_rhui_crossmajor
#   and lib/probe-common.sh, per ADR 0003 self-contained user-runnable script)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/collect-aws-rhui-facts.sh - AWS RHUI: one host, one major, one tar.gz.
#
# Self-contained by ADR 0003: a user copies this ONE file to a disposable EC2
# instance and runs it; it sources no project library. The pure helpers below
# are reuse-by-copy of lib/probe-common.sh (pm/repolist/b64url/major-url) and
# the collection logic mirrors tests/probe-env.sh pe_host_inventory and
# pe_rhui_crossmajor_check - proven on 2026-07-04, here made key-inclusive and
# leapp-aware per the operator's explicit decision (full key material required
# for the design analysis; metadata-only would force partial judgements).
#
# errexit deliberately omitted: a collector must keep going on individual
# failures and RECORD them (a failure is a fact, not an abort). Every probed
# command is captured as a .cmd/.out/.rc triple so no exit code is ever hidden
# behind a pipe (STARTUP-CORE execution discipline 4.1).
#==============================================================================
set -uo pipefail

RC_TOOL_VERSION="1.1.0"
RC_CLOUD="aws"   # this collector is AWS-specific; other clouds get sibling scripts
RC_CMD_TIMEOUT="${RC_CMD_TIMEOUT:-120}"

rc_log() { printf '%s [collect-rhui] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

#------------------------------------------------------------------------------
# Pure helpers (unit-tested by tests/t025_rhuicollect.sh) - reuse-by-copy of
# lib/probe-common.sh. Kept byte-faithful to the proven originals.
#------------------------------------------------------------------------------

# rc_pm_for_major MAJOR - the package manager binary for a RHEL major.
rc_pm_for_major() {
  case "$1" in
    10|9|8) printf 'dnf\n' ;;
    7|6)    printf 'yum\n' ;;
    *)      return 1 ;;
  esac
}

# rc_repolist_cmd MAJOR SCOPE(enabled|all) - the repolist command per major.
rc_repolist_cmd() {
  case "$1:$2" in
    10:enabled|9:enabled|8:enabled) printf '%s\n' 'dnf -q repolist --enabled' ;;
    10:all|9:all|8:all)             printf '%s\n' 'dnf -q repolist --all' ;;
    7:enabled)                      printf '%s\n' 'yum -q repolist enabled' ;;
    7:all)                          printf '%s\n' 'yum -q repolist all' ;;
    6:enabled)                      printf '%s\n' 'yum repolist enabled' ;;
    6:all)                          printf '%s\n' 'yum repolist all' ;;
    *)                              return 1 ;;
  esac
}

# rc_b64url - stdin -> urlsafe base64 (RHUI X-RHUI-ID/SIGNATURE encoding).
rc_b64url() { base64 -w0 | tr '+/' '-_'; }

# rc_rhui_major_url TEMPLATE MAJOR - synthesize another major's RHUI content
# URL from a host repo template (retarget /rhelN/, $releasever, $basearch).
# Pure; REGION substitution is the caller's job.
rc_rhui_major_url() {
  printf '%s\n' "$1" | sed -E \
    -e "s#/rhel[0-9]+/#/rhel$2/#" \
    -e "s#\\\$releasever#$2#g" \
    -e "s#\\\$basearch#x86_64#g"
}

# rc_leapp_target MAJOR - the in-place upgrade target major (empty if none:
# RHEL 6 has no leapp path; RHEL 10 has no released N+1). Decides whether the
# cross-major leapp dry-run applies.
rc_leapp_target() {
  case "$1" in
    9) printf '10\n' ;;
    8) printf '9\n' ;;
    7) printf '8\n' ;;
    *) return 1 ;;
  esac
}

# rc_chain_list MAJOR - the downstream majors reachable by REPEATED leapp hops,
# in order (pure). This is the "materialize N+1's cert, then use N+1 to reach
# N+2's cert" chain: 8 -> "9 10", 9 -> "10", else empty. It only lists what is
# ACQUIRABLE cert-wise; whether the server then authorizes non-adjacent content
# is exactly the open question the chain probe measures.
rc_chain_list() {
  local m="$1" out="" t
  while t="$(rc_leapp_target "${m}")"; do
    out="${out:+${out} }${t}"
    m="${t}"
  done
  [ -n "${out}" ] && printf '%s\n' "${out}"
  return 0
}

# rc_detect_major - best-effort RHEL major from the release file (path via
# RC_RELEASE_FILE so the parse is unit-testable against a fixture).
rc_detect_major() {
  local rel="${RC_RELEASE_FILE:-/etc/redhat-release}" line
  [ -f "${rel}" ] || return 1
  line="$(cat "${rel}" 2>/dev/null)"
  printf '%s\n' "${line}" | grep -oE 'release [0-9]+' | grep -oE '[0-9]+' | head -1
}

#------------------------------------------------------------------------------
# Command recorder: NAME.cmd / NAME.out / NAME.rc under a section dir. Never
# pipes a command's exit code away.
#------------------------------------------------------------------------------
# rc_run DIR NAME CMD... - run CMD (joined), record the triple.
rc_run() {
  local dir="$1" name="$2"; shift 2
  local cmd="$*"
  mkdir -p "${dir}"
  printf '%s\n' "${cmd}" > "${dir}/${name}.cmd"
  timeout "${RC_CMD_TIMEOUT}" bash -c "${cmd}" > "${dir}/${name}.out" 2>&1
  printf '%s\n' "$?" > "${dir}/${name}.rc"
}

#------------------------------------------------------------------------------
# IMDS (region + signed instance identity for RHUI authorization headers).
#------------------------------------------------------------------------------
RC_IMDS_TOKEN=""
rc_imds_token() {
  RC_IMDS_TOKEN="$(curl -sS -m 5 -X PUT http://169.254.169.254/latest/api/token \
    -H 'X-aws-ec2-metadata-token-ttl-seconds: 120' 2>/dev/null)"
}
rc_imds_get() {
  local path="$1" v
  v="$(curl -sS -m 5 -H "X-aws-ec2-metadata-token: ${RC_IMDS_TOKEN}" \
    "http://169.254.169.254/latest/${path}" 2>/dev/null)"
  [ -n "${v}" ] && { printf '%s' "${v}"; return 0; }
  curl -sS -m 5 "http://169.254.169.254/latest/${path}" 2>/dev/null
}

#------------------------------------------------------------------------------
# Collectors (side-effecting; run on the host).
#------------------------------------------------------------------------------

# rc_collect_base OUTDIR MAJOR
rc_collect_base() {
  local out="$1/base" major="$2" pm
  pm="$(rc_pm_for_major "${major}")" || pm=dnf
  mkdir -p "${out}/yum.repos.d"
  rc_run "${out}" s01-os        'cat /etc/redhat-release; uname -a; id -u'
  rc_run "${out}" s02-repos-pre 'ls -la /etc/yum.repos.d/ 2>&1; sha256sum /etc/yum.repos.d/*.repo 2>&1'
  cp -p /etc/yum.repos.d/*.repo "${out}/yum.repos.d/" 2>/dev/null

  # RHUI client + subscription packages, deeply (rpm -qi/-ql/--scripts).
  rc_run "${out}" s03-rhui-packages \
    'rpm -qa "rh-amazon-rhui-client*" "rhui-azure-rhel*" "google-rhui-client*" "leapp-rhui-*" "subscription-manager*" "*rhsm*" 2>&1 | sort'
  local pkg
  for pkg in rh-amazon-rhui-client rh-amazon-rhui-client-ha leapp-rhui-aws \
             amazon-libdnf-plugin subscription-manager; do
    rpm -q "${pkg}" >/dev/null 2>&1 || continue
    rc_run "${out}" "s04-rpm-qi-${pkg}"      "rpm -qi ${pkg}"
    rc_run "${out}" "s05-rpm-ql-${pkg}"      "rpm -ql ${pkg}"
    rc_run "${out}" "s06-rpm-scripts-${pkg}" "rpm -q --scripts ${pkg}"
  done

  # repolist (enabled + all) and per-repo info.
  local rl_en rl_all
  rl_en="$(rc_repolist_cmd "${major}" enabled)" || rl_en='dnf -q repolist --enabled'
  rl_all="$(rc_repolist_cmd "${major}" all)"    || rl_all='dnf -q repolist --all'
  rc_run "${out}" s07-repolist-enabled "${rl_en}"
  rc_run "${out}" s08-repolist-all     "${rl_all}"
  if [ "${pm}" = dnf ]; then
    rc_run "${out}" s09-repoinfo-all 'dnf -q repoinfo --all 2>&1'
  else
    rc_run "${out}" s09-repoinfo-all 'yum-config-manager 2>&1 || cat /etc/yum.repos.d/*.repo 2>&1'
  fi

  # RHUI/dnf plugin machinery + dnf/yum vars (config-driven authorization surface).
  rc_run "${out}" s10-dnf-vars 'ls -laR /etc/dnf/vars/ /etc/yum/vars/ 2>&1; grep -rH . /etc/dnf/vars/ /etc/yum/vars/ 2>/dev/null'
  rc_run "${out}" s11-plugins  'ls -laR /etc/dnf/plugins/ /etc/yum/pluginconf.d/ 2>&1; grep -rH . /etc/dnf/plugins/ /etc/yum/pluginconf.d/ 2>/dev/null'
  # Copy the RHUI client implementation sources (py/conf/repo/vars) for analysis.
  mkdir -p "${out}/rhui-client-src"
  for pkg in rh-amazon-rhui-client rh-amazon-rhui-client-ha leapp-rhui-aws amazon-libdnf-plugin; do
    rpm -q "${pkg}" >/dev/null 2>&1 || continue
    local f
    while IFS= read -r f; do
      case "${f}" in
        *.py|*.conf|*.repo|*/dnf/vars/*|*/yum/vars/*)
          [ -f "${f}" ] && cp -p --parents "${f}" "${out}/rhui-client-src/" 2>/dev/null ;;
      esac
    done < <(rpm -ql "${pkg}" 2>/dev/null)
  done

  # IMDS region/identity presence (identity used in place for crossmajor).
  {
    printf 'region=%s\n' "$(rc_imds_get meta-data/placement/region)"
    printf 'instance-id=%s\n' "$(rc_imds_get meta-data/instance-id)"
    printf 'ami-id=%s\n' "$(rc_imds_get meta-data/ami-id)"
  } > "${out}/s12-imds.txt" 2>&1
}

# rc_collect_certs OUTDIR - FULL /etc/pki/rhui tree INCLUDING PRIVATE KEYS
# (operator decision) plus openssl x509 / rct decodes. The archive is a secret.
rc_collect_certs() {
  local out="$1/certs" d f
  mkdir -p "${out}/pki"
  # Verbatim copy (keys included). --parents keeps the /etc/pki/... layout.
  for d in /etc/pki/rhui /etc/pki/entitlement /etc/pki/product \
           /etc/pki/product-default; do
    [ -d "${d}" ] || continue
    cp -rp --parents "${d}" "${out}/pki/" 2>/dev/null
  done
  # x509 decode (full -text: subject/issuer/serial/validity/SAN/keyusage/EKU).
  : > "${out}/x509-decode.txt"
  for f in /etc/pki/rhui/*.pem /etc/pki/rhui/*.crt \
           /etc/pki/rhui/product/*.pem /etc/pki/rhui/product/*.crt \
           /etc/pki/entitlement/*.pem; do
    [ -e "${f}" ] || continue
    case "${f}" in *-key.pem|*key*) continue ;; esac
    {
      printf '== %s ==\n' "${f}"
      openssl x509 -in "${f}" -noout -text 2>&1
      printf -- '-- fingerprint --\n'
      openssl x509 -in "${f}" -noout -fingerprint -sha256 2>&1
    } >> "${out}/x509-decode.txt"
  done
  # Private-key decode (operator wants full material captured, not metadata).
  : > "${out}/key-decode.txt"
  for f in /etc/pki/rhui/*-key.pem /etc/pki/rhui/*.key \
           /etc/pki/entitlement/*-key.pem; do
    [ -e "${f}" ] || continue
    {
      printf '== %s ==\n' "${f}"
      openssl pkey -in "${f}" -noout -text 2>&1
    } >> "${out}/key-decode.txt"
  done
  # rct cat-cert decodes the content-set extension into readable repo paths.
  if command -v rct >/dev/null 2>&1; then
    : > "${out}/content-sets.txt"
    for f in /etc/pki/rhui/product/*.pem /etc/pki/rhui/product/*.crt \
             /etc/pki/entitlement/*.pem; do
      [ -e "${f}" ] || continue
      case "${f}" in *-key.pem|*key*) continue ;; esac
      {
        printf '== rct cat-cert %s ==\n' "${f}"
        rct cat-cert "${f}" 2>&1
      } >> "${out}/content-sets.txt"
    done
  fi
}

# rc_crossmajor_probe_one OUT CERT KEY LABEL URL CAARG HDR... - follow the
# mirrorlist body to the first mirror and GET repomd.xml with the client cert.
rc_crossmajor_probe_one() {
  local out="$1" cert="$2" key="$3" label="$4" url="$5"; shift 5
  local body mlst first rstat
  body="$(curl -sS -m 20 --cert "${cert}" --key "${key}" "$@" \
    -w '\n__HTTP__%{http_code}' "${url}" 2>/dev/null)"
  mlst="${body##*__HTTP__}"
  first="$(printf '%s\n' "${body}" | grep -Eo 'https?://[^[:space:]]+' | grep -v '__HTTP__' | head -1)"
  if [ -n "${first}" ]; then
    rstat="$(curl -sS -m 20 -o /dev/null -w '%{http_code}' \
      --cert "${cert}" --key "${key}" "$@" \
      "${first%/}/repodata/repomd.xml" 2>/dev/null)"
  else
    rstat="no-mirror"
  fi
  printf '%s mirrorlist_http=%s repomd_http=%s first_mirror=%s\n' \
    "${label}" "${mlst:-000}" "${rstat}" "${first:-none}" >> "${out}"
}

# rc_collect_crossmajor OUTDIR - does THIS host's RHUI client cert reach OTHER
# majors' content? Reuse-by-copy of pe_rhui_crossmajor_check. Keys used in
# place. rhel99 is the calibration control (expected non-200).
rc_collect_crossmajor() {
  local out="$1/crossmajor/rhui-crossmajor.txt" repo=/etc/yum.repos.d/redhat-rhui.repo
  local sec tmpl cert key ca region url m caarg=() m_list
  mkdir -p "$1/crossmajor"
  [ -f "${repo}" ] || { echo "skipped: ${repo} absent (not an AWS RHUI host?)" > "${out}"; return 0; }
  sec="$(awk '/^\[rhel-[0-9]+-baseos-rhui-rpms\]/{f=1;next} /^\[/{f=0} f' "${repo}")"
  tmpl="$(printf '%s\n' "${sec}" | sed -n 's/^mirrorlist=//p' | head -1)"
  cert="$(printf '%s\n' "${sec}" | sed -n 's/^sslclientcert=//p' | head -1)"
  key="$(printf '%s\n' "${sec}" | sed -n 's/^sslclientkey=//p' | head -1)"
  ca="$(printf '%s\n' "${sec}" | sed -n 's/^sslcacert=//p' | head -1)"
  if [ -z "${tmpl}" ] || [ ! -f "${cert}" ] || [ ! -f "${key}" ]; then
    echo "skipped: baseos mirrorlist template or client cert/key unavailable" > "${out}"; return 0
  fi
  region="$(rc_imds_get meta-data/placement/region)"
  {
    printf 'region=%s\n' "${region:-unresolved}"
    printf 'template=%s\n' "${tmpl}"
    printf 'cert=%s\n' "${cert}"
    printf 'key=%s (used in place, full copy is under certs/)\n' "${key}"
  } > "${out}"
  [ -n "${region}" ] || { echo "skipped: region unresolved via IMDS" >> "${out}"; return 0; }
  [ -n "${ca}" ] && [ -f "${ca}" ] && caarg=(--cacert "${ca}")
  # AWS RHUI authorization = TLS client cert AND the SIGNED instance-identity
  # document, sent as X-RHUI-ID / X-RHUI-SIGNATURE (urlsafe base64).
  local id_doc id_sig hdr=()
  id_doc="$(rc_imds_get dynamic/instance-identity/document)"
  id_sig="$(rc_imds_get dynamic/instance-identity/signature)"
  if [ -n "${id_doc}" ] && [ -n "${id_sig}" ]; then
    hdr=(-H "X-RHUI-ID: $(printf '%s' "${id_doc}" | rc_b64url)"
         -H "X-RHUI-SIGNATURE: $(printf '%s' "${id_sig}" | rc_b64url)")
    echo "identity_headers=present" >> "${out}"
  else
    echo "identity_headers=UNAVAILABLE (expect 403s)" >> "${out}"
  fi
  for m in 10 9 8 99; do
    url="$(rc_rhui_major_url "${tmpl}" "${m}" | sed "s/REGION/${region}/")"
    rc_crossmajor_probe_one "${out}" "${cert}" "${key}" "major=${m}" "${url}" "${caarg[@]}" "${hdr[@]}"
  done
  for m in 7 6; do
    url="https://rhui.${region}.aws.ce.redhat.com/pulp/mirror/content/dist/rhel/rhui/server/${m}/${m}Server/x86_64/os"
    rc_crossmajor_probe_one "${out}" "${cert}" "${key}" "major=${m}(legacy)" "${url}" "${caarg[@]}" "${hdr[@]}"
  done
  : "${m_list:=}"  # silence unused-in-some-paths; documents intent
}

# rc_collect_eus OUTDIR MAJOR - enumerate + inspect EUS/ELS/AUS/E4S repos. The
# extended-lifecycle content is the other axis of the config-driven hypothesis
# (and the only cross-version data for RHEL 6, which has no leapp).
rc_collect_eus() {
  local out="$1/eus" major="$2" pm rl_all
  pm="$(rc_pm_for_major "${major}")" || pm=dnf
  mkdir -p "${out}"
  rl_all="$(rc_repolist_cmd "${major}" all)" || rl_all='dnf -q repolist --all'
  # The eus/els/aus/e4s repo IDs present in the full repolist.
  rc_run "${out}" e01-eus-repo-ids \
    "${rl_all} 2>&1 | grep -iE 'eus|els|aus|e4s' || echo '(no extended-lifecycle repo ids found)'"
  if [ "${pm}" = dnf ]; then
    # shellcheck disable=SC2016  # $(...)/$i/\$1 expand inside rc_run's bash -c, not here
    rc_run "${out}" e02-eus-repoinfo \
      'for i in $(dnf -q repolist --all 2>/dev/null | awk "NR>1{print \$1}" | grep -iE "eus|els|aus|e4s"); do echo "== $i =="; dnf -q repoinfo "$i" 2>&1; done'
    rc_run "${out}" e03-eus-config \
      'dnf config-manager --dump 2>&1 | grep -iE "eus|els|aus|e4s" || echo "(none)"'
  else
    rc_run "${out}" e02-eus-repoinfo \
      "grep -iE 'eus|els|aus|e4s' /etc/yum.repos.d/*.repo 2>&1 || echo '(none in repo files)'"
  fi
}

# rc_collect_leapp OUTDIR MAJOR - NON-DESTRUCTIVE cross-major straddle capture.
# Installs leapp-rhui-aws (+ deps, which materialize the N+1 major's repos) and
# runs `leapp preupgrade --no-rhsm`. NEVER runs `leapp upgrade`. Majors 7/8/9.
rc_collect_leapp() {
  local out="$1/leapp" major="$2" target
  target="$(rc_leapp_target "${major}")" || {
    mkdir -p "${out}"; echo "skipped: no leapp target for RHEL ${major}" > "${out}/SKIPPED.txt"; return 0
  }
  mkdir -p "${out}"
  printf 'source_major=%s target_major=%s\n' "${major}" "${target}" > "${out}/target.txt"

  # dnf vars BEFORE (releasever pinning is central to the straddle question).
  rc_run "${out}" l01-vars-before 'ls -laR /etc/dnf/vars/ /etc/yum/vars/ 2>&1; grep -rH . /etc/dnf/vars/ /etc/yum/vars/ 2>/dev/null'

  # Enable the RHUI client-config repo + install the leapp engine. The engine
  # package leapp-upgrade-el<N>toel<N+1> pulls leapp itself AND leapp-rhui-aws
  # (r73 installed only leapp-rhui-aws, so `leapp` was absent -> preupgrade rc127).
  if [ "${major}" = 7 ]; then
    rc_run "${out}" l02-enable-rhui 'yum-config-manager --enable rhui-client-config-server-7 rhel-7-server-rhui-extras-rpms 2>&1'
    rc_run "${out}" l03-install-leapp "yum -y install leapp-upgrade-el7toel${target} 2>&1"
  else
    rc_run "${out}" l02-enable-rhui "dnf config-manager --set-enabled rhui-client-config-server-${major} 2>&1"
    rc_run "${out}" l03-install-leapp "dnf -y install leapp-upgrade-el${major}toel${target} 2>&1"
  fi

  # The dry run. --no-rhsm because RHUI (not subscription-manager) is the source.
  # This is where leapp pulls the TARGET major's repos - the straddle we want.
  rc_run "${out}" l04-preupgrade 'leapp preupgrade --no-rhsm 2>&1'

  # dnf vars AFTER + the repo/cert state leapp materialized for the target.
  rc_run "${out}" l05-vars-after 'ls -laR /etc/dnf/vars/ /etc/yum/vars/ 2>&1; grep -rH . /etc/dnf/vars/ /etc/yum/vars/ 2>/dev/null'
  rc_run "${out}" l06-repos-after 'ls -la /etc/yum.repos.d/ 2>&1; sha256sum /etc/yum.repos.d/*.repo 2>&1'
  mkdir -p "${out}/yum.repos.d-after" "${out}/var-log-leapp"
  cp -p /etc/yum.repos.d/*.repo "${out}/yum.repos.d-after/" 2>/dev/null
  # leapp's own reports/logs (leapp-report.txt/.json, leapp-preupgrade.log).
  cp -rp /var/log/leapp/. "${out}/var-log-leapp/" 2>/dev/null
  # Any target-major RHUI cert leapp dropped in (leapp-rhui-aws ships them).
  rc_run "${out}" l07-leapp-rhui-files 'rpm -ql leapp-rhui-aws 2>&1; find /etc/pki/rhui /etc/leapp -type f 2>/dev/null'
}

# rc_run_long DIR NAME CMD... - like rc_run but with a long timeout, for heavy
# installs / --downloadonly fetches (leapp engine pulls, build-dep downloads).
rc_run_long() {
  local dir="$1" name="$2"; shift 2
  local cmd="$*"
  mkdir -p "${dir}"
  printf '%s\n' "${cmd}" > "${dir}/${name}.cmd"
  timeout "${RC_CHAIN_TIMEOUT:-900}" bash -c "${cmd}" > "${dir}/${name}.out" 2>&1
  printf '%s\n' "$?" > "${dir}/${name}.rc"
}

# rc_count_packages FILE - decompress a primary.xml.* metadata file and count
# <package entries. The "file list" built purely from curl + local tools.
rc_count_packages() {
  local f="$1"
  case "${f}" in
    *.gz)  gzip -dc "${f}" 2>/dev/null | grep -c '<package ' ;;
    *.xz)  xz -dc "${f}" 2>/dev/null | grep -c '<package ' ;;
    *.bz2) bzip2 -dc "${f}" 2>/dev/null | grep -c '<package ' ;;
    *.zck) if command -v unzck >/dev/null 2>&1; then unzck -c "${f}" 2>/dev/null | grep -c '<package '; else echo 'zck-unsupported'; fi ;;
    *)     grep -c '<package ' "${f}" 2>/dev/null ;;
  esac
}

# rc_curl_repo_enum DIR TAG CERT KEY MLURL EXTRA... - drive an RHUI repo with
# curl + the client cert ONLY (no dnf): follow mirrorlist -> repomd.xml ->
# primary metadata -> build the package file list. EXTRA... are extra curl args
# (--cacert, -H X-RHUI-ID, -H X-RHUI-SIGNATURE). Records status at each layer;
# the repomd_http field is the authorization verdict.
rc_curl_repo_enum() {
  local dir="$1" tag="$2" cert="$3" key="$4" mlurl="$5"; shift 5
  local sum="${dir}/${tag}-curl-enum.txt"
  local ml mlrc first repomd rmrc href prim prc pkgs
  mkdir -p "${dir}"
  ml="$(curl -sS -m 20 --cert "${cert}" --key "${key}" "$@" -w '\n__HTTP__%{http_code}' "${mlurl}" 2>/dev/null)"
  mlrc="${ml##*__HTTP__}"
  first="$(printf '%s\n' "${ml}" | grep -Eo 'https?://[^[:space:]]+' | grep -v '__HTTP__' | head -1)"
  {
    printf 'tag=%s\n' "${tag}"
    printf 'mirrorlist_url=%s\n' "${mlurl}"
    printf 'mirrorlist_http=%s\n' "${mlrc:-000}"
    printf 'first_mirror=%s\n' "${first:-none}"
  } > "${sum}"
  [ -n "${first}" ] || { printf 'result=no-mirror\n' >> "${sum}"; return 0; }
  repomd="${dir}/${tag}-repomd.xml"
  rmrc="$(curl -sS -m 30 --cert "${cert}" --key "${key}" "$@" -o "${repomd}" -w '%{http_code}' "${first%/}/repodata/repomd.xml" 2>/dev/null)"
  printf 'repomd_http=%s\n' "${rmrc}" >> "${sum}"
  [ "${rmrc}" = 200 ] || { printf 'result=repomd-denied(%s)\n' "${rmrc}" >> "${sum}"; return 0; }
  href="$(grep -oE 'href="[^"]*primary[^"]*"' "${repomd}" 2>/dev/null | head -1 | sed 's/^href="//; s/"$//')"
  printf 'primary_href=%s\n' "${href:-none}" >> "${sum}"
  [ -n "${href}" ] || { printf 'result=no-primary-href\n' >> "${sum}"; return 0; }
  prim="${dir}/${tag}-$(basename "${href}")"
  prc="$(curl -sS -m 60 --cert "${cert}" --key "${key}" "$@" -o "${prim}" -w '%{http_code}' "${first%/}/${href}" 2>/dev/null)"
  printf 'primary_http=%s\n' "${prc}" >> "${sum}"
  [ "${prc}" = 200 ] || { printf 'result=primary-denied(%s)\n' "${prc}" >> "${sum}"; return 0; }
  pkgs="$(rc_count_packages "${prim}")"
  printf 'package_count=%s\n' "${pkgs:-unknown}" >> "${sum}"
  printf 'result=OK-curl-only-file-list-built\n' >> "${sum}"
}

# rc_collect_chain OUTDIR MAJOR - the r74 experiment. Walk the leapp acquire-
# chain (8 -> 9 -> 10) using ONLY internal resources (the leapp packages the
# host's own repos serve), materializing each next major's cert WITHOUT any
# self-managed key material, and at every hop test whether that major's content
# is actually authorized from THIS (billing-<MAJOR>) host - both via curl (cert
# only) and via dnf --downloadonly of the build deps. NEVER runs `leapp upgrade`
# (only installs/extracts packages and reads their bundled certs/repos).
#
# The decisive datum is the NON-ADJACENT hop (e.g. billing-8 host reaching
# rhel10): if its curl repomd is 200, one host can serve every major's build
# material; if 403, RHUI authorization is bound to the instance's own major and
# the chain only yields dead certs past N+1.
rc_collect_chain() {
  local out="$1/chain" major="$2"
  local repo=/etc/yum.repos.d/redhat-rhui.repo
  local chain sec tmpl ca region caarg=() hdr=() id_doc id_sig
  local bdir_default=/usr/share/leapp-repository/repositories/system_upgrade/common/files/rhui/aws
  local src t hop=0 hd bdir certT keyT url_base url_app rf adjacent verdict _chain=()
  mkdir -p "${out}"
  chain="$(rc_chain_list "${major}")"
  if [ -z "${chain}" ]; then
    echo "skipped: no downstream chain for RHEL ${major}" > "${out}/SKIPPED.txt"; return 0
  fi
  printf 'source_major=%s acquire_chain=%s\n' "${major}" "${chain}" > "${out}/chain.txt"
  [ -f "${repo}" ] || { echo "skipped: ${repo} absent" >> "${out}/chain.txt"; return 0; }
  sec="$(awk '/^\[rhel-[0-9]+-baseos-rhui-rpms\]/{f=1;next} /^\[/{f=0} f' "${repo}")"
  tmpl="$(printf '%s\n' "${sec}" | sed -n 's/^mirrorlist=//p' | head -1)"
  ca="$(printf '%s\n' "${sec}" | sed -n 's/^sslcacert=//p' | head -1)"
  region="$(rc_imds_get meta-data/placement/region)"
  if [ -z "${tmpl}" ] || [ -z "${region}" ]; then
    echo "skipped: baseos template or region unresolved" >> "${out}/chain.txt"; return 0
  fi
  [ -n "${ca}" ] && [ -f "${ca}" ] && caarg=(--cacert "${ca}")
  id_doc="$(rc_imds_get dynamic/instance-identity/document)"
  id_sig="$(rc_imds_get dynamic/instance-identity/signature)"
  [ -n "${id_doc}" ] && [ -n "${id_sig}" ] && hdr=(
    -H "X-RHUI-ID: $(printf '%s' "${id_doc}" | rc_b64url)"
    -H "X-RHUI-SIGNATURE: $(printf '%s' "${id_sig}" | rc_b64url)")

  src="${major}"
  read -ra _chain <<< "${chain}"
  for t in "${_chain[@]}"; do
    hop=$((hop + 1))
    hd="${out}/hop${hop}-src${src}-to${t}"; mkdir -p "${hd}"
    [ "${t}" = "$(rc_leapp_target "${src}")" ] && adjacent=yes || adjacent=no
    printf 'hop=%s source_major=%s target_major=%s adjacent=%s\n' "${hop}" "${src}" "${t}" "${adjacent}" > "${hd}/hop.txt"

    # --- ACQUIRE content-rhel<t> cert (internal resource only) -----------------
    bdir="${bdir_default}"
    if [ "${hop}" = 1 ]; then
      # host's own repos serve the leapp engine, which bundles content-rhel<t>.
      rc_run_long "${hd}" a01-install-leapp "dnf -y install leapp-upgrade-el${src}toel${t} 2>&1"
    else
      # CHAIN: use the previous (verified-reachable) target repos to fetch that
      # major's leapp-rhui-aws, extract it, and read the NEXT major's cert out.
      rc_run_long "${hd}" a01-fetch-next-bundle \
        "dnf -y --releasever ${src} --disablerepo='*' --enablerepo='chain-${src}-*' install --downloadonly --destdir='${hd}/dl' leapp-rhui-aws 2>&1; for r in '${hd}'/dl/*.rpm; do rpm2cpio \"\${r}\" | (cd '${hd}' && cpio -idmu); done 2>&1"
      bdir="${hd}${bdir_default}"
    fi
    rc_run "${hd}" a02-cert-range "ls -la '${bdir}' 2>&1; echo '--- content certs present ---'; ls '${bdir}'/content-rhel*.crt 2>&1"
    certT="${bdir}/content-rhel${t}.crt"; keyT="${bdir}/content-rhel${t}.key"
    if [ ! -f "${certT}" ] || [ ! -f "${keyT}" ]; then
      printf 'STOP: content-rhel%s cert was not acquired here (chain cannot proceed)\n' "${t}" > "${hd}/RESULT.txt"; break
    fi

    url_base="$(rc_rhui_major_url "${tmpl}" "${t}" | sed "s/REGION/${region}/")"
    url_app="$(printf '%s' "${url_base}" | sed 's#/baseos/#/appstream/#')"

    # --- (1) NON-DNF verification: curl + cert only ----------------------------
    rc_curl_repo_enum "${hd}" "curl-rhel${t}-baseos" "${certT}" "${keyT}" "${url_base}" "${caarg[@]}" "${hdr[@]}"
    rc_curl_repo_enum "${hd}" "curl-rhel${t}-appstream" "${certT}" "${keyT}" "${url_app}" "${caarg[@]}" "${hdr[@]}"

    # --- (2) DNF verification: build-material downloadability -------------------
    rf="/etc/yum.repos.d/chain-${t}.repo"
    {
      printf '[chain-%s-baseos]\nname=chain rhel%s baseos\nmirrorlist=%s\nenabled=0\ngpgcheck=0\nsslverify=1\nsslclientcert=%s\nsslclientkey=%s\n' \
        "${t}" "${t}" "$(printf '%s' "${tmpl}" | sed -e "s#/rhel[0-9]*/#/rhel${t}/#" -e "s/REGION/${region}/")" "${certT}" "${keyT}"
      [ -n "${ca}" ] && printf 'sslcacert=%s\n' "${ca}"
      printf '\n[chain-%s-appstream]\nname=chain rhel%s appstream\nmirrorlist=%s\nenabled=0\ngpgcheck=0\nsslverify=1\nsslclientcert=%s\nsslclientkey=%s\n' \
        "${t}" "${t}" "$(printf '%s' "${tmpl}" | sed -e "s#/rhel[0-9]*/#/rhel${t}/#" -e 's#/baseos/#/appstream/#' -e "s/REGION/${region}/")" "${certT}" "${keyT}"
      [ -n "${ca}" ] && printf 'sslcacert=%s\n' "${ca}"
    } > "${rf}" 2>/dev/null
    cp -p "${rf}" "${hd}/chain-${t}.repo" 2>/dev/null
    rc_run_long "${hd}" d01-dnf-downloadonly \
      "dnf -y --releasever ${t} --disablerepo='*' --enablerepo='chain-${t}-*' install --downloadonly --destdir='${hd}/builddeps' kernel-devel gcc make elfutils-libelf-devel 2>&1; ls -la '${hd}/builddeps' 2>&1"

    verdict="$(sed -n 's/^repomd_http=//p' "${hd}/curl-rhel${t}-baseos-curl-enum.txt" 2>/dev/null | head -1)"
    printf 'target=%s adjacent=%s curl_baseos_repomd_http=%s\n' "${t}" "${adjacent}" "${verdict:-none}" > "${hd}/RESULT.txt"
    if [ "${verdict}" != 200 ]; then
      printf 'STOP: rhel%s content NOT authorized from billing-%s host; cannot source the next hop.\n' "${t}" "${major}" >> "${hd}/RESULT.txt"
      break
    fi
    src="${t}"
  done
}

#------------------------------------------------------------------------------
# Orchestration + packaging.
#------------------------------------------------------------------------------
rc_write_manifest() {
  local out="$1" major="$2" host="$3" ts="$4"
  {
    printf 'tool: collect-aws-rhui-facts.sh v%s\n' "${RC_TOOL_VERSION}"
    printf 'cloud: %s\n' "${RC_CLOUD}"
    printf 'collected_at: %s\n' "${ts}"
    printf 'host: %s\n' "${host}"
    printf 'rhel_major: %s\n' "${major}"
    printf 'uname: %s\n' "$(uname -a 2>/dev/null)"
    printf '\n*** SECURITY: this archive contains PRIVATE KEYS (RHUI entitlement\n'
    printf '    credential). Treat as a secret - do NOT commit; transfer securely. ***\n\n'
    printf 'sections:\n'
    printf '  base/       OS, repos, RHUI-client RPM (-qi/-ql/--scripts), plugins, dnf vars, IMDS\n'
    printf '  certs/      FULL /etc/pki/rhui incl. keys + openssl/rct decodes\n'
    printf '  crossmajor/ host-cert HTTPS reachability of other majors (rhel99=control)\n'
    printf '  eus/        EUS/ELS/AUS/E4S repo enumeration\n'
    printf '  leapp/      non-destructive "leapp preupgrade --no-rhsm" straddle (7/8/9)\n'
    printf '  chain/      leapp cert-chain probe (8->9->10): curl+dnf reachability per hop (--chain)\n'
  } > "${out}/MANIFEST.txt"
}

rc_usage() {
  cat <<'EOF'
Usage: sudo bash collect-aws-rhui-facts.sh [options]
  --major N        RHEL major (6-10); default: auto-detect from /etc/redhat-release
  --outdir DIR     working directory; default: a mktemp dir
  --no-leapp       skip the leapp preupgrade dry-run (majors 7/8/9)
  --chain          run the leapp cert-chain probe (8->9->10) measuring whether
                   non-adjacent majors are authorized from this host, via curl
                   (cert only) AND dnf --downloadonly. Heavy; implies --no-leapp.
  --no-crossmajor  skip the cross-major HTTPS reachability probe
  --no-eus         skip EUS/ELS repo enumeration
  --keep-outdir    do not delete the working dir after packing
  -h, --help       this help
Output: ./aws-rhui-facts_<host>_rhel<major>_<ts>.tar.gz  (CONTAINS PRIVATE KEYS)
EOF
}

rc_main() {
  local major="" outdir="" do_leapp=1 do_cross=1 do_eus=1 do_chain=0 keep=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --major)        major="$2"; shift 2 ;;
      --outdir)       outdir="$2"; shift 2 ;;
      --no-leapp)     do_leapp=0; shift ;;
      --chain)        do_chain=1; do_leapp=0; shift ;;
      --no-crossmajor) do_cross=0; shift ;;
      --no-eus)       do_eus=0; shift ;;
      --keep-outdir)  keep=1; shift ;;
      -h|--help)      rc_usage; return 0 ;;
      *)              rc_log "unknown option: $1"; rc_usage; return 2 ;;
    esac
  done

  if [ "$(id -u)" != 0 ]; then
    rc_log "WARNING: not root - cert/key copy and leapp install will be incomplete"
  fi
  if [ -z "${major}" ]; then
    major="$(rc_detect_major)" || { rc_log "ERROR: cannot detect RHEL major; pass --major"; return 2; }
  fi
  case "${major}" in 6|7|8|9|10) ;; *) rc_log "ERROR: unsupported major '${major}'"; return 2 ;; esac

  local ts host
  ts="$(date -u '+%Y%m%dT%H%M%SZ')"
  host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
  [ -n "${outdir}" ] || outdir="$(mktemp -d "/tmp/aws-rhui-facts.XXXXXX")"
  mkdir -p "${outdir}"

  rc_log "collecting: major=${major} host=${host} outdir=${outdir}"
  rc_imds_token
  rc_write_manifest "${outdir}" "${major}" "${host}" "${ts}"
  { rc_collect_base "${outdir}" "${major}"; } 2>> "${outdir}/collect.log"
  { rc_collect_certs "${outdir}"; } 2>> "${outdir}/collect.log"
  [ "${do_cross}" = 1 ] && { rc_collect_crossmajor "${outdir}" "${major}"; } 2>> "${outdir}/collect.log"
  [ "${do_eus}" = 1 ]   && { rc_collect_eus "${outdir}" "${major}"; } 2>> "${outdir}/collect.log"
  [ "${do_leapp}" = 1 ] && { rc_collect_leapp "${outdir}" "${major}"; } 2>> "${outdir}/collect.log"
  [ "${do_chain}" = 1 ] && { rc_collect_chain "${outdir}" "${major}"; } 2>> "${outdir}/collect.log"

  local archive
  archive="./aws-rhui-facts_${host}_rhel${major}_${ts}.tar.gz"
  tar -czf "${archive}" -C "$(dirname "${outdir}")" "$(basename "${outdir}")" 2>>"${outdir}/collect.log" \
    || { rc_log "ERROR: tar failed"; return 1; }
  [ "${keep}" = 1 ] || rm -rf "${outdir}"
  rc_log "done: ${archive}"
  printf '%s\n' "${archive}"
}

# t025 sources this file with RHUI_COLLECT_SOURCED=1 to unit-test the pure layer.
if [ "${RHUI_COLLECT_SOURCED:-0}" != 1 ]; then
  rc_main "$@"
fi
