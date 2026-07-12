# ----- Purpose --------------------------------------------------------------
#   AWS-RHUI entitled-container material: IMDS identity-header acquisition,
#   the static-header dnf injection plugin (B" method), per-major synthesized
#   repo files, and the runtime bundle assembly the E1 wiring mounts.
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; sourced library (no side effects at source time); curl on the
#   host for IMDS; an AWS RHUI host (rh-amazon-rhui-client) for the bundle.
# ----- Usage examples -------------------------------------------------------
#   source lib/rhui-entitlement.sh   # from a matrix runner / probe / test tier
# ----- Known limitations ----------------------------------------------------
#   Not a standalone executable; functions assume the caller handles logging
#   and error policy (spec home A.5). Self-major only: the bundle carries the
#   HOST's own /etc/pki/rhui credential (no forward-chain acquisition; E1
#   topology decision).
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-11 (r87 E1a: productionize the E0-proven B"
#   static-header injection; see CHANGELOG.md)
# ---------------------------------------------------------------------------
# shellcheck shell=bash
# shellcheck disable=SC2034  # RHUI_LAST_ERR is a public contract var read by callers
#==============================================================================
# lib/rhui-entitlement.sh - AWS-RHUI entitled-container material (E1a)
#
# Sourceable library (no shebang, no top-level execution). Productionizes the
# B" injection method proven by the E0 investigation (r80-r86, real EC2 +
# real UBI containers, all of rhel8/9/10):
#
#   RHUI authorization = TLS client cert AND signed instance-identity headers
#   (X-RHUI-ID / X-RHUI-SIGNATURE, urlsafe base64), enforced at the
#   repomd/RPM layer (the mirrorlist itself answers 200 to anyone). A
#   container cannot reach IMDS (hop-limit), so the HOST fetches the identity
#   document + signature once per container start and passes them in as a
#   static file; a tiny python dnf.Plugin inside the container reads that
#   file and injects the headers into the synthesized rhui-suite-* repos via
#   repo._repo.setHttpHeaders(). Verified end-to-end on el8/el9/el10
#   (makecache rc=0 + ENA build deps "Complete!"), archive
#   aws-rhui-facts_ip-172-31-2-135_rhel8_20260711T072944Z.
#
# E1a delta from the E0 collector helpers (rc_write_e0_plugin family):
#   * the plugin READS the headers from a fixed mounted path instead of
#     embedding them - the plugin is baked into the provisioned image ONCE
#     (its install needs an in-container glob of the per-major
#     python*/site-packages/dnf-plugins dir, impossible to bind-mount), while
#     the signature is regenerated per container start (adjudicated design:
#     re-fetch beats TTL bookkeeping) and mounted as a file;
#   * repo ids use the production prefix rhui-suite- (E0 used rhui-e0-);
#   * self-major only - certs come verbatim from the host's own
#     /etc/pki/rhui paths as named by redhat-rhui.repo (no forward chain).
#
# Container-facing path contract (the E1b wiring mounts the bundle here):
#   /run/rhui-suite/headers    identity headers, one "Name: value" per line
#   /run/rhui-suite/CERT.crt   host self-major RHUI content cert
#   /run/rhui-suite/CERT.key   its key
#   /run/rhui-suite/ca.crt     the RHUI CDN CA chain
# The synthesized repo file and the plugin reference these fixed paths.
#
# UBI8 lesson (r86, load-bearing): never resolve the dnf plugin dir with a
# `python3` command (UBI8 has none - dnf runs on platform-python3.6); glob
# /usr/lib/python*/site-packages/dnf-plugins instead. That glob is the
# in-container installer's job (E1b provisioning step); this library only
# WRITES the plugin. The plugin's "setHttpHeaders OK" print is load-bearing:
# it is how the harness confirms the plugin actually fired.
#==============================================================================

# Fixed container-side mount point + file names (single source of truth).
RHUI_SUITE_MNT="/run/rhui-suite"
RHUI_SUITE_PREFIX="rhui-suite-"
RHUI_LAST_ERR=""

# rhui_b64url - stdin -> urlsafe base64 (the RHUI X-RHUI-ID/SIGNATURE
# encoding). Copied from the E0 collector's rc_b64url (reuse-by-copy).
rhui_b64url() { base64 -w0 | tr '+/' '-_'; }

# rhui_imds_token / rhui_imds_get PATH - IMDSv2-preferred metadata access
# (token PUT, then GET with the token header; IMDSv1 fallback when the token
# is empty). Copied from the E0 collector (reuse-by-copy).
RHUI_IMDS_TOKEN=""
rhui_imds_token() {
  RHUI_IMDS_TOKEN="$(curl -sS -m 5 -X PUT http://169.254.169.254/latest/api/token \
    -H 'X-aws-ec2-metadata-token-ttl-seconds: 120' 2>/dev/null)"
}
rhui_imds_get() {
  local path="$1" v
  v="$(curl -sS -m 5 -H "X-aws-ec2-metadata-token: ${RHUI_IMDS_TOKEN}" \
    "http://169.254.169.254/latest/${path}" 2>/dev/null)"
  [ -n "${v}" ] && { printf '%s' "${v}"; return 0; }
  curl -sS -m 5 "http://169.254.169.254/latest/${path}" 2>/dev/null
}

# rhui_headers_write FILE - fetch the instance-identity document + signature
# from IMDS and write the two identity headers to FILE, one "Name: value" per
# line (the exact format the injection plugin reads):
#   X-RHUI-ID: <urlsafe-b64 of the identity document>
#   X-RHUI-SIGNATURE: <urlsafe-b64 of the signature>
# assert-all-then-write: BOTH values must be non-empty before anything is
# written (a half-written headers file would turn an IMDS blip into a
# confusing 403); on failure FILE is left untouched and rc=1 with
# RHUI_LAST_ERR set. Call this per container start (adjudicated design:
# re-fetching per start makes the >=60min acceptance window irrelevant).
rhui_headers_write() {
  local file="$1" id_doc id_sig
  RHUI_LAST_ERR=""
  [ -n "${RHUI_IMDS_TOKEN}" ] || rhui_imds_token
  id_doc="$(rhui_imds_get dynamic/instance-identity/document)"
  id_sig="$(rhui_imds_get dynamic/instance-identity/signature)"
  if [ -z "${id_doc}" ] || [ -z "${id_sig}" ]; then
    RHUI_LAST_ERR="IMDS instance-identity unavailable (document or signature empty)"
    return 1
  fi
  {
    printf 'X-RHUI-ID: %s\n' "$(printf '%s' "${id_doc}" | rhui_b64url)"
    printf 'X-RHUI-SIGNATURE: %s\n' "$(printf '%s' "${id_sig}" | rhui_b64url)"
  } > "${file}"
}

# rhui_write_inject_plugin FILE [PREFIX] [HEADERS_PATH] - write the ONE
# static-header dnf injection plugin. Single definition for every consumer
# (r86: two divergent copies made plugin_fired detection lie). File-read
# variant: the headers come from HEADERS_PATH at dnf runtime, so the plugin
# itself is static and can be baked into the provisioned image while the
# signature stays per-container-start. python3.6-compatible (UBI8
# platform-python). The OK/FAILED prints are load-bearing (harness markers).
rhui_write_inject_plugin() {
  local file="$1" prefix="${2:-${RHUI_SUITE_PREFIX}}" hpath="${3:-${RHUI_SUITE_MNT}/headers}"
  cat > "${file}" <<PYEOF
import dnf

HEADERS_PATH = "${hpath}"
REPO_PREFIX = "${prefix}"

class RhuiSuiteInject(dnf.Plugin):
    name = "rhuisuite"

    def config(self):
        try:
            with open(HEADERS_PATH) as f:
                hdrs = [line.strip() for line in f if line.strip()]
        except Exception as e:
            print("rhuisuite: headers file unreadable at %s: %r" % (HEADERS_PATH, e))
            return
        if not hdrs:
            print("rhuisuite: headers file empty at %s" % HEADERS_PATH)
            return
        for name, repo in self.base.repos.items():
            if name.startswith(REPO_PREFIX):
                try:
                    repo._repo.setHttpHeaders(hdrs)
                    print("rhuisuite: setHttpHeaders OK for %s" % name)
                except Exception as e:
                    print("rhuisuite: setHttpHeaders FAILED for %s: %r" % (name, e))
PYEOF
}

# rhui_write_plugin_conf FILE - the enabling conf that sits next to the
# plugin as /etc/dnf/plugins/rhuisuite.conf.
rhui_write_plugin_conf() { printf '[main]\nenabled=1\n' > "$1"; }

# rhui_repo_template_from_host [REPOFILE] - read the host's own RHUI repo
# file (default /etc/yum.repos.d/redhat-rhui.repo) and echo
#   "MIRRORLIST_TEMPLATE|SSLCLIENTCERT|SSLCLIENTKEY|SSLCACERT"
# extracted from the [rhel-N-baseos-rhui-rpms] section - the same section the
# E0 collector keyed on. The template keeps its literal REGION and
# $releasever/$basearch placeholders (rhui_write_repo substitutes them).
# rc=1 with RHUI_LAST_ERR when the file or any of the four fields is missing.
rhui_repo_template_from_host() {
  local repofile="${1:-/etc/yum.repos.d/redhat-rhui.repo}" sec tmpl cert key ca
  RHUI_LAST_ERR=""
  if [ ! -f "${repofile}" ]; then
    RHUI_LAST_ERR="RHUI repo file absent: ${repofile}"
    return 1
  fi
  sec="$(awk '/^\[rhel-[0-9]+-baseos-rhui-rpms\]/{f=1;next} /^\[/{f=0} f' "${repofile}")"
  tmpl="$(printf '%s\n' "${sec}" | sed -n 's/^mirrorlist=//p' | head -1)"
  cert="$(printf '%s\n' "${sec}" | sed -n 's/^sslclientcert=//p' | head -1)"
  key="$(printf '%s\n' "${sec}"  | sed -n 's/^sslclientkey=//p'  | head -1)"
  ca="$(printf '%s\n' "${sec}"   | sed -n 's/^sslcacert=//p'     | head -1)"
  if [ -z "${tmpl}" ] || [ -z "${cert}" ] || [ -z "${key}" ] || [ -z "${ca}" ]; then
    RHUI_LAST_ERR="incomplete [rhel-N-baseos-rhui-rpms] section in ${repofile} (mirrorlist/sslclientcert/sslclientkey/sslcacert required)"
    return 1
  fi
  printf '%s|%s|%s|%s' "${tmpl}" "${cert}" "${key}" "${ca}"
}

# rhui_major_url TEMPLATE MAJOR - substitute the $releasever/$basearch
# placeholders (and retarget /rhelN/, an identity operation for the
# self-major E1 topology). Copied from the E0 collector's rc_rhui_major_url
# (reuse-by-copy). Pure; REGION substitution is rhui_write_repo's job.
rhui_major_url() {
  printf '%s\n' "$1" | sed -E \
    -e "s#/rhel[0-9]+/#/rhel$2/#" \
    -e "s#\\\$releasever#$2#g" \
    -e "s#\\\$basearch#x86_64#g"
}

# rhui_write_repo FILE MAJOR REGION TEMPLATE - synthesize the entitled repo
# file the container consumes: baseos + appstream sections (together they
# cover kernel-devel on every RHUI major - baseos on 8, appstream on 9/10),
# mirrorlist per the E0-proven B path (what the real RHUI client uses), ssl
# material at the fixed container mount paths, gpgcheck ON against the Red
# Hat release key the UBI images ship. Repo ids carry the injection prefix.
rhui_write_repo() {
  local file="$1" major="$2" region="$3" tmpl="$4" base_ml app_ml
  base_ml="$(rhui_major_url "${tmpl}" "${major}" | sed "s/REGION/${region}/")"
  app_ml="$(printf '%s' "${base_ml}" | sed 's#/baseos/#/appstream/#')"
  cat > "${file}" <<EOF
[${RHUI_SUITE_PREFIX}rhel${major}-baseos]
name=RHEL ${major} BaseOS from RHUI (suite-synthesized)
mirrorlist=${base_ml}
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
sslverify=1
sslclientcert=${RHUI_SUITE_MNT}/CERT.crt
sslclientkey=${RHUI_SUITE_MNT}/CERT.key
sslcacert=${RHUI_SUITE_MNT}/ca.crt

[${RHUI_SUITE_PREFIX}rhel${major}-appstream]
name=RHEL ${major} AppStream from RHUI (suite-synthesized)
mirrorlist=${app_ml}
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
sslverify=1
sslclientcert=${RHUI_SUITE_MNT}/CERT.crt
sslclientkey=${RHUI_SUITE_MNT}/CERT.key
sslcacert=${RHUI_SUITE_MNT}/ca.crt
EOF
}

# rhui_host_major [OSREL] [RHREL] - the host's own RHEL major (os-release
# VERSION_ID first, redhat-release fallback; both paths overridable for
# hermetic tests). Echoes the major or nothing (rc=1).
# shellcheck disable=SC2120  # args exist only for hermetic tests; prod callers use the defaults
rhui_host_major() {
  local osrel="${1:-/etc/os-release}" rhrel="${2:-/etc/redhat-release}" m=""
  if [ -r "${osrel}" ]; then
    # shellcheck disable=SC1090  # sourcing the runtime-selected os-release
    m="$(. "${osrel}"; v="${VERSION_ID:-}"; printf '%s' "${v%%.*}")"
  fi
  if [ -z "${m}" ] && [ -r "${rhrel}" ]; then
    m="$(sed -n 's/.*release \([0-9]\+\).*/\1/p' "${rhrel}" | head -1)"
  fi
  [ -n "${m}" ] || return 1
  printf '%s' "${m}"
}

# rhui_bundle_prepare DIR [MAJOR] [REPOFILE] - assemble the complete runtime
# bundle the E1b wiring mounts at ${RHUI_SUITE_MNT}:
#   CERT.crt CERT.key ca.crt   host self-major credential (verbatim copies)
#   rhui-suite.repo            synthesized entitled repos (fixed ssl paths)
#   rhuisuite.py rhuisuite.conf  the injection plugin + its enabling conf
#   headers                    identity headers (regenerate per container
#                              start by calling rhui_headers_write again)
# assert-all-then-acquire: every input (repo template fields, cert/key/CA
# files, region, IMDS identity) is verified BEFORE the first byte lands in
# DIR, so a failed prepare never leaves a half-bundle for the wiring to
# mount. rc=1 with RHUI_LAST_ERR naming the missing piece.
rhui_bundle_prepare() {
  local dir="$1" major="${2:-}" repofile="${3:-/etc/yum.repos.d/redhat-rhui.repo}"
  local fields tmpl cert key ca region
  RHUI_LAST_ERR=""
  if [ -z "${major}" ]; then
    # shellcheck disable=SC2119  # default paths intended here (test-only args)
    major="$(rhui_host_major)" || { RHUI_LAST_ERR="host RHEL major undetectable"; return 1; }
  fi
  fields="$(rhui_repo_template_from_host "${repofile}")" || return 1
  tmpl="${fields%%|*}"; fields="${fields#*|}"
  cert="${fields%%|*}"; fields="${fields#*|}"
  key="${fields%%|*}";  ca="${fields#*|}"
  local f
  for f in "${cert}" "${key}" "${ca}"; do
    [ -f "${f}" ] || { RHUI_LAST_ERR="credential file absent: ${f}"; return 1; }
  done
  [ -n "${RHUI_IMDS_TOKEN}" ] || rhui_imds_token
  region="$(rhui_imds_get meta-data/placement/region)"
  [ -n "${region}" ] || { RHUI_LAST_ERR="IMDS region unavailable"; return 1; }
  mkdir -p "${dir}" || { RHUI_LAST_ERR="cannot create bundle dir: ${dir}"; return 1; }
  rhui_headers_write "${dir}/headers" || return 1
  cp -p "${cert}" "${dir}/CERT.crt" || { RHUI_LAST_ERR="cert copy failed: ${cert}"; return 1; }
  cp -p "${key}"  "${dir}/CERT.key" || { RHUI_LAST_ERR="key copy failed: ${key}"; return 1; }
  cp -p "${ca}"   "${dir}/ca.crt"   || { RHUI_LAST_ERR="CA copy failed: ${ca}"; return 1; }
  rhui_write_repo "${dir}/rhui-suite.repo" "${major}" "${region}" "${tmpl}"
  rhui_write_inject_plugin "${dir}/rhuisuite.py"
  rhui_write_plugin_conf "${dir}/rhuisuite.conf"
}
