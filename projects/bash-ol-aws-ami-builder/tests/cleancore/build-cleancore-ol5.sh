#!/usr/bin/env bash
#
# build-cleancore-ol5.sh
# ----------------------------------------------------------------------------
# Naming convention: build-cleancore-ol<MAJOR>.sh  (the OS version is the
# trailing token). Family: build-cleancore-ol5.sh / -ol6.sh / -ol7.sh /
# -ol8.sh / -ol9.sh / -ol10.sh
#
# Build a *clean-core* Oracle Linux 5 (= OL5.11) container rootfs. Dedicated,
# self-contained OL5 script (no shared library, no config externalization -- by
# design). OL5 is the deepest EOL member: its rpm stays 4.4 / BerkeleyDB-4.3
# FOREVER, and its in-OS openssl 0.9.8e tops out at TLS 1.0, so the OL5 stack can
# no longer fetch from modern (TLS-1.2-only) yum.oracle.com directly. A faithful
# OL5 clean-core is the quasi-validation environment for the legacy OL5 systems
# still running in the Japanese market.
#
# WORK-ENVIRONMENT MODEL (keeps the build HOST pristine -- no host package installs):
# the repository-mirror processing runs inside the LATEST distributed Oracle Linux
# container image, oraclelinux:10 (floating :10), pulled at build time. OL10 is the
# newest EL: it has modern TLS 1.2/1.3, dnf, createrepo_c and rpm2cpio. The host
# only PULLS + extracts that image (curl + tar) and later runs a single-level chroot
# -- it installs nothing. The two OL5 blockers -- (i) no in-OS TLS 1.2, (ii) the
# deliverable rpmdb must be EL5-native db4.3 -- are solved this way: the OL10 work
# env does all TLS-1.2 fetching, dependency resolution, mirror creation and the EL5
# builder bootstrap; the EL5-native rpm/yum (bootstrapped from the OL5 RPMs) then
# writes the deliverable from a file:// mirror (no in-OS TLS). The OL10 rpm is NEVER
# used to write the deliverable's rpmdb (a modern rpm yields a db the in-guest OL5
# rpm 4.4 reads as 0 packages -- the same EL-native constraint the OL6 builder proves).
#
# Three+1 execution environments are involved; each block below is tagged:
#   [A] HOST       - pulls + extracts the OL10 work-env image and drives chroots.
#                    Installs NOTHING (curl/tar/xz/gzip/unshare/chroot/mknod only).
#   [W] WORK-ENV   - the throwaway oraclelinux:10 rootfs (floating :10). Does all
#                    TLS-1.2 work: fetch OL5 metadata + RPMs, resolve the closure
#                    (dnf first; an embedded python resolver as fallback), build the
#                    file:// mirror (createrepo_c), and bootstrap the EL5 builder.
#   [B] BUILDER    - a THROWAWAY EL5-native rootfs bootstrapped (rpm2cpio|cpio) from
#                    the OL5 RPMs, carrying a WORKING EL5 yum + rpm. It reads ONLY a
#                    build-dedicated file:// repo; its contents never ship.
#   [C] CLEAN-CORE - the DELIVERABLE rootfs from the EL5 `yum --installroot`
#                    transaction against the file:// mirror (rpm 4.4 / rpmdb db4.3).
#
# ----------------------------------------------------------------------------
# PRIMARY SOURCES (verify upstream)
#   - Work-env image: the latest distributed Oracle Linux 10 container image,
#     pulled anonymously from the Oracle registry (floating :10, OCI v2 API):
#       https://container-registry.oracle.com/  (repository os/oraclelinux, tag 10)
#   - OL5/latest repo (TLS 1.2; the authoritative SOURCE the work env mirrors),
#     Oracle official -- repodata href is the PLAIN primary.xml.gz (no sha-prefix):
#       https://yum.oracle.com/repo/OracleLinux/OL5/latest/x86_64/
#   - Package set = a slim-aligned curated trim (mirrors clean-core OL6 in EL5
#     names). OL5-specific deltas: versionlock plugin is `yum-versionlock` (not
#     yum-plugin-versionlock); release pkg is `oraclelinux-release` (no -el5 sub);
#     `procps` (not procps-ng), `nc` (not nmap-ncat), net-tools provides hostname;
#     git is OMITTED (EPEL-only on EL5, pulls a perl chain) and jq is OMITTED (no
#     jq exists for EL5, not even in the EPEL-5 archive); ca-certificates is not a
#     separate pkg (CAs ship with openssl).
#   - EPEL: the image CARRIES the archived-EPEL-5 repo configuration
#     (user requirement 2026-07-18, OL6-flow parity: the OL6 path gets the
#     archived EPEL 6 at test time from install-ena-driver.sh). epel-release-5-4
#     is installed at build time; its repo files are rewired to the canonical
#     Fedora ARCHIVE (https://dl.fedoraproject.org/pub/archive/epel/5/) and the
#     dead mirrorlist service is commented out. Service model (measured
#     2026-07-18): the archive hosts 302-force plain http to https, and EL5
#     openssl 0.9.8e tops out at TLS 1.0 -- so the GUEST can never fetch the
#     archive directly, exactly like the OL5 base channel. The sections ship
#     enabled=0: a canonical, gpg-keyed reference config that a harness enables
#     against a modern-host mirror / host-side staging (the same doctrine as
#     the base-channel skip note in the self-test). gpgcheck stays on (the rpm
#     ships RPM-GPG-KEY-EPEL). The base install itself pulls NOTHING from EPEL.
# ----------------------------------------------------------------------------
# Usage:   bash build-cleancore-ol5.sh [output.tar.gz]
#   env :  WORK=<scratch dir>   INSECURE_TLS=1  (the OL10 work env fetches with
#          curl -k for the Claude sandbox MITM egress proxy; set 0 on a trusted host).
#          OL10_IMAGE=os/oraclelinux  OL10_TAG=10  (override the work-env image/tag).
# Requires (HOST): root (unshare/chroot/mknod), curl, tar, xz, gzip, gunzip, python3
#          (tiny JSON parse for the image pull), unshare, truncate, find. NO rpm,
#          NO bsdtar, NO createrepo on the host -- those live in the OL10 work env.
# Exit:    0 = built and self-test passed; non-zero = build error or test failure.
# ----------------------------------------------------------------------------
set -euo pipefail

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [A] HOST — configuration (inline by design; not externalized)            ║
# ╚════════════════════════════════════════════════════════════════════════╝
OSMAJOR=5
REPO_BASE="https://yum.oracle.com/repo/OracleLinux/OL${OSMAJOR}/latest/x86_64"

# Work-env image: the latest distributed Oracle Linux 10 image (floating :10).
OL10_REGISTRY="${OL10_REGISTRY:-https://container-registry.oracle.com}"
OL10_IMAGE="${OL10_IMAGE:-os/oraclelinux}"
OL10_TAG="${OL10_TAG:-10}"
# Archived EPEL 5 (terminal/immutable). The release RPM is fetched HOST-side.
# The baked-in baseurl is the CANONICAL https archive: plain http is 302-forced
# to https by the Fedora hosts (measured 2026-07-18), so an http baseurl buys
# nothing -- the EL5 guest cannot complete either scheme (TLS 1.0 max) and the
# config is served host-mediated (mirror / staging), like the base channel.
EPEL5_RELEASE_RPM_URL="${EPEL5_RELEASE_RPM_URL:-https://dl.fedoraproject.org/pub/archive/epel/5/x86_64/epel-release-5-4.noarch.rpm}"
EPEL5_ARCHIVE_BASEURL_PREFIX="${EPEL5_ARCHIVE_BASEURL_PREFIX:-https://dl.fedoraproject.org/pub/archive/epel/5/}"

WORK="${WORK:-/tmp/cleancore-ol5}"
OUT_TARBALL="${1:-${WORK}/cleancore-ol5-rootfs.tar.gz}"

# The OL10 work env fetches OL5 over TLS 1.2. INSECURE_TLS=1 adds curl -k for the
# Claude sandbox egress proxy (intercepting MITM cert). On a real trusted host use
# INSECURE_TLS=0. The EL5 BUILDER/INSTALL path never does TLS (file:// only).
INSECURE_TLS="${INSECURE_TLS:-1}"

# Package manifest (slim-aligned, @core dropped) translated to EL5 names. Mirrors
# clean-core OL6's INCLUDE minus the two EL5 unavailables (git, jq), with the EL5
# versionlock/release names. Every name is verified present in OL5/latest.
INCLUDE=( yum oraclelinux-release yum-utils yum-versionlock
  curl wget bzip2 unzip zip
  sudo which tar diffutils less findutils procps psmisc net-tools vim-minimal
  iproute iputils bind-utils traceroute nc tcpdump )

# Builder bootstrap seed: enough OL5 RPMs to give the THROWAWAY EL5 builder a
# WORKING yum + rpm + createrepo. EL5's own createrepo 0.4.11 is REQUIRED: it emits
# sha1/gzip repodata that EL5 yum 3.2.22 can read (OL10's createrepo_c only emits
# sha256, which EL5 yum cannot checksum). Its full closure is resolved in the work
# env and rpm2cpio|cpio-extracted into the builder.
BOOTSTRAP=( yum rpm createrepo )

EXCLUDE="*firmware*,kernel*"

# Layout: WENV (the OL10 work env) and SHARED (mirror/builder/meta -- written by the
# work env, consumed by the host) are SIBLINGS, so bind-mounting SHARED into WENV
# never recurses.
WENV="${WORK}/wenv"            # [W] throwaway oraclelinux:10 work-env rootfs
SHARED="${WORK}/shared"        # host<->work-env handoff dir (bind-mounted into WENV)
MIRROR="${SHARED}/mirror"      # file:// mirror of the resolved closure (+ repodata)
META="${SHARED}/meta"          # repo metadata + closure list files
BUILDER="${SHARED}/builder"    # [B] throwaway EL5-native builder rootfs
MIRROR_IN="/mirror"            # mirror path as bind-mounted INSIDE the EL5 builder
OUT="/cleancore"               # [C] installroot path INSIDE the builder
DELIV="${BUILDER}${OUT}"       # [C] deliverable rootfs as seen from [A]

log() { printf '%s [cleancore-ol5] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

for t in curl tar xz gzip gunzip unshare chroot mknod truncate find python3; do
  command -v "$t" >/dev/null 2>&1 || { log "[A] ERROR: required host tool '$t' not found"; exit 1; }
done

rm -rf "${WORK}"
mkdir -p "${WENV}" "${MIRROR}" "${META}" "${BUILDER}"

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [A] HOST — pull the latest distributed oraclelinux:10 image (floating :10) ║
# ║     anonymously over the OCI registry v2 API (curl only; no runtime, no    ║
# ║     host installs) and extract its layers into the [W] work-env rootfs.    ║
# ║     If a container runtime is present it is used as a fast path instead.    ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[A] acquiring the oraclelinux:${OL10_TAG} work-env rootfs (distributed image, floating)"
CURL_K=""; [ "${INSECURE_TLS}" = "1" ] && CURL_K="-k"
RT=""
for c in podman docker; do command -v "$c" >/dev/null 2>&1 && { RT="$c"; break; }; done
if [ -n "${RT}" ]; then
  log "[A] using ${RT} to export oraclelinux:${OL10_TAG}"
  IMG_REF="container-registry.oracle.com/${OL10_IMAGE}:${OL10_TAG}"
  "${RT}" pull "${IMG_REF}" >/dev/null
  CID="$("${RT}" create "${IMG_REF}" /bin/true)"
  "${RT}" export "${CID}" | tar -C "${WENV}" -xf -
  "${RT}" rm -f "${CID}" >/dev/null 2>&1 || true
else
  log "[A] no container runtime; pulling oraclelinux:${OL10_TAG} via the OCI registry v2 API (curl)"
  REG="${OL10_REGISTRY}"; REPO="${OL10_IMAGE}"
  TOKEN="$(curl -fsS ${CURL_K} --get "${REG}/auth" \
            --data-urlencode "service=Oracle Registry" \
            --data-urlencode "scope=repository:${REPO}:pull" \
          | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')"
  curl -fsSL ${CURL_K} -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/vnd.oci.image.index.v1+json" \
    -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
    -H "Accept: application/vnd.oci.image.manifest.v1+json" \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    "${REG}/v2/${REPO}/manifests/${OL10_TAG}" -o "${META}/index.json"
  # Resolve the amd64 image manifest (follow a multi-arch index if present).
  AMD_DIGEST="$(python3 -c '
import sys,json
d=json.load(open(sys.argv[1]))
if "manifests" in d:
    for m in d["manifests"]:
        p=m.get("platform",{})
        if p.get("architecture")=="amd64" and p.get("os")=="linux":
            print(m["digest"]); break
else:
    print("")' "${META}/index.json")"
  if [ -n "${AMD_DIGEST}" ]; then
    curl -fsSL ${CURL_K} -H "Authorization: Bearer ${TOKEN}" \
      -H "Accept: application/vnd.oci.image.manifest.v1+json" \
      -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
      "${REG}/v2/${REPO}/manifests/${AMD_DIGEST}" -o "${META}/manifest.json"
  else
    cp -f "${META}/index.json" "${META}/manifest.json"
  fi
  # Fetch + extract each layer blob in order (gzip'd tar; blob URLs 307-redirect).
  python3 -c '
import sys,json
d=json.load(open(sys.argv[1]))
for l in d.get("layers",[]): print(l["digest"])' "${META}/manifest.json" > "${META}/layers.txt"
  while IFS= read -r dig; do
    [ -n "${dig}" ] || continue
    log "[A] layer ${dig%%:*}:$(echo "${dig}" | cut -c8-19) -> extract"
    curl -fsSL ${CURL_K} -H "Authorization: Bearer ${TOKEN}" \
      "${REG}/v2/${REPO}/blobs/${dig}" | tar -C "${WENV}" -xz
  done < "${META}/layers.txt"
fi
[ -x "${WENV}/usr/bin/curl" ] || [ -x "${WENV}/bin/curl" ] || log "[A] WARN: work env has no curl in the expected path"
cp -f /etc/resolv.conf "${WENV}/etc/resolv.conf" 2>/dev/null || true
mkdir -p "${WENV}/shared" "${WENV}/dev" "${WENV}/proc"
# Sandbox-only: the Claude egress proxy presents an intercepting (MITM) cert. Seed
# its CA into the work env's trust store so the OL10 dnf/curl verify TLS. On a real
# build host these files do not exist, so this is a no-op (normal CA verification).
mkdir -p "${WENV}/etc/pki/ca-trust/source/anchors"
for _ca in /usr/local/share/ca-certificates/egress-gateway-ca-*.crt; do
  if [ -e "${_ca}" ]; then cp -f "${_ca}" "${WENV}/etc/pki/ca-trust/source/anchors/"; fi
done

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [A->W] write the in-work-env build step script. It runs ONCE inside the    ║
# ║        oraclelinux:10 chroot and produces, on the shared host FS: the       ║
# ║        file:// mirror (RPMs + repodata) and the bootstrapped EL5 builder.   ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[A->W] generating the work-env build step"
WCURL_K=""; [ "${INSECURE_TLS}" = "1" ] && WCURL_K="-k"
WSSLVERIFY=1; [ "${INSECURE_TLS}" = "1" ] && WSSLVERIFY=0
cat > "${SHARED}/wenv-build.sh" <<WENVEOF
#!/usr/bin/env bash
# Runs INSIDE the oraclelinux:10 work env. Inputs via the baked vars below; all
# outputs land under /shared (bind-mounted to the host's SHARED dir).
set -euo pipefail
REPO_BASE="${REPO_BASE}"
OSMAJOR="${OSMAJOR}"
CURL_K="${WCURL_K}"
EXCLUDE="${EXCLUDE}"
INCLUDE=( ${INCLUDE[*]} )
BOOTSTRAP=( ${BOOTSTRAP[*]} )
MIRROR="/shared/mirror"
META="/shared/meta"
BUILDER="/shared/builder"
wlog() { printf '%s [wenv-ol10] %s\n' "\$(date '+%H:%M:%S')" "\$*"; }

# (W1) provision: ensure cpio + python3 are present (the base image has dnf or
# microdnf + rpm/rpm2cpio). createrepo is NOT needed here -- the EL5-native
# createrepo (from the bootstrap closure) emits the EL5-readable sha1/gz repodata.
# Allow sha1 EL5 metadata (LEGACY). First activate any seeded CA (sandbox proxy).
update-ca-trust 2>/dev/null || true
PKMGR=dnf; command -v dnf >/dev/null 2>&1 || PKMGR=microdnf
wlog "(W1) provisioning work env via \${PKMGR} (cpio, python3)"
if [ "\${PKMGR}" = "microdnf" ]; then
  microdnf -y install dnf cpio python3 >/dev/null 2>&1 || microdnf -y install cpio python3 >/dev/null 2>&1 || true
  command -v dnf >/dev/null 2>&1 && PKMGR=dnf
else
  dnf -y install cpio python3 >/dev/null 2>&1 || true
fi
command -v update-crypto-policies >/dev/null 2>&1 && update-crypto-policies --set LEGACY >/dev/null 2>&1 || true
command -v rpm2cpio   >/dev/null 2>&1 || { wlog "ERROR: rpm2cpio unavailable in work env";   exit 2; }
command -v cpio       >/dev/null 2>&1 || { wlog "ERROR: cpio unavailable in work env";        exit 2; }

# (W2) resolve the closures of BOOTSTRAP and INCLUDE. dnf FIRST (native), against
# ONLY the OL5 repo with an empty installroot + --releasever=5 so the FULL EL5
# closure is pulled (nothing is considered pre-satisfied). PYTHON FALLBACK parses
# the repo metadata directly (checksum-agnostic) if dnf cannot use EL5 metadata.
DNF_OK=0
if command -v dnf >/dev/null 2>&1; then
  wlog "(W2) trying dnf foreign-release resolution (--releasever=\${OSMAJOR}, empty installroot)"
  EMPTY=/tmp/ol5root; rm -rf "\${EMPTY}"; mkdir -p "\${EMPTY}"
  DNF_COMMON=( -y --installroot="\${EMPTY}" --releasever="\${OSMAJOR}"
    --repofrompath="ol5,\${REPO_BASE}" --repoid=ol5 --setopt=ol5.gpgcheck=0
    --setopt=ol5.sslverify=${WSSLVERIFY} --nogpgcheck )
  if dnf "\${DNF_COMMON[@]}" download --resolve --alldeps --destdir="\${MIRROR}" "\${BOOTSTRAP[@]}" >/tmp/dnf-boot.log 2>&1; then
    ls -1 "\${MIRROR}"/*.rpm 2>/dev/null | xargs -r -n1 basename > "\${META}/bootstrap-closure.txt"
    if dnf "\${DNF_COMMON[@]}" download --resolve --alldeps --destdir="\${MIRROR}" "\${INCLUDE[@]}" >/tmp/dnf-inc.log 2>&1; then
      ls -1 "\${MIRROR}"/*.rpm 2>/dev/null | xargs -r -n1 basename > "\${META}/include-closure.txt"
      DNF_OK=1; wlog "(W2) dnf resolution OK"
    fi
  fi
  [ "\${DNF_OK}" = "1" ] || wlog "(W2) dnf path failed (see /tmp/dnf-*.log); falling back to the python resolver"
fi
if [ "\${DNF_OK}" != "1" ]; then
  wlog "(W2) python resolver: fetching OL5 repo metadata (plain primary/filelists.xml.gz)"
  curl -fsSL \${CURL_K} -o "\${META}/primary.xml.gz"   "\${REPO_BASE}/repodata/primary.xml.gz"
  curl -fsSL \${CURL_K} -o "\${META}/filelists.xml.gz" "\${REPO_BASE}/repodata/filelists.xml.gz"
  gunzip -f "\${META}/primary.xml.gz" "\${META}/filelists.xml.gz"
  resolve_py() { python3 "\${META}/resolve.py" "\${META}/primary.xml" "\${META}/filelists.xml" "\$@"; }
  cat > "\${META}/resolve.py" <<'PYRESOLVE'
import sys, re
PRIMARY, FILELISTS = sys.argv[1], sys.argv[2]
SEEDS = sys.argv[3:]
def _split(s):
    out, cur = [], ''
    for ch in s:
        if ch.isdigit():
            if cur and not cur[-1].isdigit(): out.append(cur); cur=''
            cur += ch
        elif ch.isalpha():
            if cur and not cur[-1].isalpha(): out.append(cur); cur=''
            cur += ch
        else:
            if cur: out.append(cur); cur=''
    if cur: out.append(cur)
    return out
def _cmp_seg(a,b):
    if a.isdigit() and b.isdigit():
        a,b=a.lstrip('0') or '0', b.lstrip('0') or '0'
        if len(a)!=len(b): return -1 if len(a)<len(b) else 1
        return -1 if a<b else (1 if a>b else 0)
    if a.isdigit(): return 1
    if b.isdigit(): return -1
    return -1 if a<b else (1 if a>b else 0)
def evr_cmp(e1,e2):
    (ep1,v1,r1),(ep2,v2,r2)=e1,e2
    if int(ep1 or 0)!=int(ep2 or 0): return -1 if int(ep1 or 0)<int(ep2 or 0) else 1
    for x,y in ((v1,v2),(r1,r2)):
        sx,sy=_split(x),_split(y)
        for a,b in zip(sx,sy):
            c=_cmp_seg(a,b)
            if c: return c
        if len(sx)!=len(sy): return -1 if len(sx)<len(sy) else 1
    return 0
ARCH_RANK={'x86_64':3,'noarch':2,'i686':1,'i386':1}
prim=open(PRIMARY,encoding='utf-8',errors='replace').read()
pkgs=re.findall(r'<package type="rpm">(.*?)</package>', prim, re.S)
by_name={}; prov_index={}; allrecs=[]
for blk in pkgs:
    n=re.search(r'<name>(.*?)</name>',blk); a=re.search(r'<arch>(.*?)</arch>',blk)
    ver=re.search(r'<version epoch="(\d+)" ver="([^"]+)" rel="([^"]+)"',blk)
    loc=re.search(r'<location href="([^"]+)"',blk)
    if not (n and a and ver and loc): continue
    name=n.group(1); arch=a.group(1)
    if arch not in ARCH_RANK: continue
    evr=(ver.group(1),ver.group(2),ver.group(3))
    pm=re.search(r'<rpm:provides>(.*?)</rpm:provides>',blk,re.S)
    provides=re.findall(r'<rpm:entry name="([^"]+)"', pm.group(1)) if pm else []
    rm=re.search(r'<rpm:requires>(.*?)</rpm:requires>',blk,re.S)
    requires=re.findall(r'<rpm:entry name="([^"]+)"', rm.group(1)) if rm else []
    rec=dict(name=name,arch=arch,evr=evr,href=loc.group(1),provides=provides,requires=requires)
    allrecs.append(rec)
    cur=by_name.get(name)
    if cur is None:
        by_name[name]=rec
    else:
        c=evr_cmp(evr,cur['evr'])
        if c>0 or (c==0 and ARCH_RANK[arch]>ARCH_RANK[cur['arch']]):
            by_name[name]=rec
for rec in by_name.values():
    prov_index.setdefault(rec['name'],set()).add(rec['name'])
    for p in rec['provides']:
        prov_index.setdefault(p,set()).add(rec['name'])
needed_files=set()
for rec in allrecs:
    for req in rec['requires']:
        if req.startswith('/'): needed_files.add(req)
file_index={}
with open(FILELISTS,encoding='utf-8',errors='replace') as fh:
    for line in fh:
        if '<package ' not in line: continue
        pm=re.search(r'<package pkgid="[^"]*" name="([^"]+)" arch="([^"]+)"',line)
        if not pm: continue
        pname=pm.group(1)
        if pname not in by_name: continue
        for fm in re.findall(r'<file(?: type="[^"]+")?>([^<]+)</file>',line):
            if fm in needed_files and fm not in file_index:
                file_index[fm]=pname
def provider_for(req):
    if req.startswith('rpmlib(') or req.startswith('config('): return []
    if req.startswith('/'):
        owner=file_index.get(req); return [owner] if owner else []
    owners=prov_index.get(req)
    return list(owners) if owners else []
closure=set(); queue=list(SEEDS); missing=set()
while queue:
    name=queue.pop()
    if name in closure: continue
    rec=by_name.get(name)
    if rec is None: missing.add(name); continue
    closure.add(name)
    for req in rec['requires']:
        owners=provider_for(req)
        if not owners:
            if not (req.startswith('rpmlib(') or req.startswith('config(')): missing.add(req)
            continue
        pick = name if name in owners else owners[0]
        if pick not in closure: queue.append(pick)
for name in sorted(closure):
    print(by_name[name]['href'])
sys.stderr.write('[resolver] closure=%d seeds=%d\n' % (len(closure), len(SEEDS)))
if missing:
    sys.stderr.write('[resolver] UNRESOLVED(%d): %s\n' % (len(missing), ', '.join(sorted(missing)[:40])))
    sys.exit(3)
PYRESOLVE
  resolve_py "\${BOOTSTRAP[@]}" > "\${META}/bootstrap-href.txt"
  resolve_py "\${INCLUDE[@]}"   > "\${META}/include-href.txt"
  sort -u "\${META}/bootstrap-href.txt" "\${META}/include-href.txt" > "\${META}/mirror-href.txt"
  wlog "(W2) fetching \$(wc -l < "\${META}/mirror-href.txt") RPMs into the mirror"
  while IFS= read -r href; do
    [ -n "\${href}" ] || continue
    curl -fsSL \${CURL_K} -o "\${MIRROR}/\$(basename "\${href}")" "\${REPO_BASE}/\${href}"
  done < "\${META}/mirror-href.txt"
  xargs -r -n1 basename < "\${META}/bootstrap-href.txt" > "\${META}/bootstrap-closure.txt"
  xargs -r -n1 basename < "\${META}/include-href.txt"   > "\${META}/include-closure.txt"
fi
wlog "(W2) closures: bootstrap=\$(wc -l < "\${META}/bootstrap-closure.txt"), include=\$(wc -l < "\${META}/include-closure.txt"), mirror=\$(find "\${MIRROR}" -name '*.rpm' | wc -l)"

# (W3) the mirror is left as a plain RPM dir. Its EL5-readable repodata (sha1/gz)
# is generated host-side by the EL5-native createrepo just before the install
# (OL10's createrepo_c only emits sha256, which EL5 yum 3.2.22 cannot verify).
wlog "(W3) mirror staged (\$(find "\${MIRROR}" -name '*.rpm' | wc -l) RPMs); EL5 createrepo runs at install time"

# (W4) bootstrap the EL5 builder rootfs by rpm2cpio|cpio-extracting the bootstrap
# closure RPM payloads (no rpm/GHCR; the work env's rpm2cpio reads the OL5 RPMs).
wlog "(W4) bootstrapping the EL5 builder rootfs (rpm2cpio|cpio, \$(wc -l < "\${META}/bootstrap-closure.txt") RPMs)"
while IFS= read -r rpmf; do
  [ -n "\${rpmf}" ] || continue
  ( cd "\${BUILDER}" && rpm2cpio "\${MIRROR}/\${rpmf}" | cpio -idmu --quiet )
done < "\${META}/bootstrap-closure.txt"
mkdir -p "\${BUILDER}/etc" "\${BUILDER}/dev" "\${BUILDER}/proc" "\${BUILDER}/tmp" "\${BUILDER}/var/lib/rpm" "\${BUILDER}\${MIRROR_IN:=/mirror}"
[ -f "\${BUILDER}/etc/passwd" ] || printf 'root:x:0:0:root:/root:/bin/bash\n' > "\${BUILDER}/etc/passwd"
[ -f "\${BUILDER}/etc/group" ]  || printf 'root:x:0:\n' > "\${BUILDER}/etc/group"
# EL5 yum 3.2.22 has no --setopt; carry tsflags=nodocs via the builder's yum.conf.
if [ -f "\${BUILDER}/etc/yum.conf" ] && ! grep -q '^tsflags' "\${BUILDER}/etc/yum.conf"; then
  sed -i '/^\[main\]/a tsflags=nodocs' "\${BUILDER}/etc/yum.conf"
fi
# Write the build-dedicated file:// repo as the builder's ONLY repo.
rm -f "\${BUILDER}/etc/yum.repos.d/"*.repo 2>/dev/null || true
mkdir -p "\${BUILDER}/etc/yum.repos.d"
cat > "\${BUILDER}/etc/yum.repos.d/cleancore.repo" <<REPOEOF
[cc_ol5]
name=OL\${OSMAJOR} clean-core local mirror
baseurl=file:///mirror/
gpgcheck=0
enabled=1
REPOEOF
wlog "(W4) EL5 builder bootstrapped"
WENVEOF
chmod +x "${SHARED}/wenv-build.sh"

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [W] WORK-ENV — run the build step inside the oraclelinux:10 chroot. SHARED  ║
# ║     is bind-mounted to /shared so the mirror + EL5 builder land on the host ║
# ║     FS for the EL5 install transaction below (no chroot nesting).           ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[W] running the work-env build step inside oraclelinux:${OL10_TAG}"
unshare --fork --pid --mount --uts --ipc bash -c "
  mount --bind /dev '${WENV}/dev'   2>/dev/null || true
  mount -t proc proc '${WENV}/proc'  2>/dev/null || true
  mount --bind '${SHARED}' '${WENV}/shared'
  cp -f /etc/resolv.conf '${WENV}/etc/resolv.conf' 2>/dev/null || true
  chroot '${WENV}' /bin/bash /shared/wenv-build.sh
  umount '${WENV}/shared' 2>/dev/null || true
"
[ -n "$(find "${MIRROR}" -name '*.rpm' -print -quit 2>/dev/null)" ] || { log "[A] ERROR: work env produced no mirror RPMs"; exit 1; }
[ -e "${BUILDER}/bin/rpm" ] || [ -e "${BUILDER}/usr/bin/rpm" ] || { log "[A] ERROR: EL5 builder has no rpm"; exit 1; }
[ -e "${BUILDER}/usr/bin/createrepo" ] || { log "[A] ERROR: EL5 builder has no createrepo"; exit 1; }

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [B->C] HOST — the EL5 install transaction (single-level chroot into the     ║
# ║        bootstrapped EL5 builder). EL5 yum --installroot writes the [C]       ║
# ║        clean-core from the file:// mirror -- no in-OS TLS, rpmdb db4.3.      ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[B->C] building clean-core into ${DELIV} via EL5 yum --installroot (file://)"
rm -rf "${DELIV}"
# NOTE: EL5 yum 3.2.22 frequently exits non-zero (scriptlet warnings under chroot)
# even on a successful "Complete!" transaction, so the install is NOT gated by its
# exit code (no set -e here). Success is verified by the rpmdb package count below.
unshare --fork --pid --mount --uts --ipc bash -c "
  mount --bind /dev '${BUILDER}/dev'   2>/dev/null || true
  mount -t proc proc '${BUILDER}/proc'  2>/dev/null || true
  mount --bind '${MIRROR}' '${BUILDER}${MIRROR_IN}'
  chroot '${BUILDER}' /sbin/ldconfig 2>/dev/null || true
  rm -rf '${BUILDER}${MIRROR_IN}/repodata'
  chroot '${BUILDER}' /usr/bin/createrepo --quiet '${MIRROR_IN}'
  chroot '${BUILDER}' /usr/bin/yum -y --installroot='${OUT}' \
    --disablerepo='*' --enablerepo=cc_ol5 --nogpgcheck \
    --exclude='${EXCLUDE}' \
    install ${INCLUDE[*]} || true
  chroot '${BUILDER}' /usr/bin/yum --installroot='${OUT}' clean all >/dev/null 2>&1 || true
  umount '${BUILDER}${MIRROR_IN}' 2>/dev/null || true
"
INSTALLED="$(chroot "${BUILDER}" /bin/rpm --root="${OUT}" -qa 2>/dev/null | wc -l)"
log "[B->C] clean-core install transaction complete: ${INSTALLED} packages"
[ "${INSTALLED}" -gt 0 ] || { log "[A] ERROR: clean-core install produced 0 packages (transaction failed)"; exit 1; }

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [C] CLEAN-CORE — finalize from [A] (host): device nodes, drop the build-    ║
# ║     time repo, force any remaining repo to https (Oracle hosts only),       ║
# ║     wire the archived EPEL 5 (3b), and clear machine identity / logs.       ║
# ║     No NSS dynamic-CA dance (curl is openssl-linked; install was file://).  ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[A->C] (3) device nodes, repo hygiene, drop build-time repo"
for n in "null c 1 3" "zero c 1 5" "random c 1 8" "urandom c 1 9" \
         "full c 1 7" "console c 5 1" "ptmx c 5 2" "tty c 5 0"; do
  # shellcheck disable=SC2086  # intentional word-split of the "name type maj min" node spec
  set -- $n
  rm -f "${DELIV}/dev/$1"
  mknod -m 666 "${DELIV}/dev/$1" "$2" "$3" "$4" 2>/dev/null || true
done
rm -f "${DELIV}/etc/yum.repos.d/cleancore.repo"
find "${DELIV}/etc/yum.repos.d" -type f -name '*.repo*' -print0 2>/dev/null \
  | xargs -0 -r sed -i -e 's|http://yum.oracle.com|https://yum.oracle.com|g' \
                       -e 's|http://public-yum.oracle.com|https://yum.oracle.com|g' || true

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [A->C] (3b) EPEL 5 archive repo (user requirement 2026-07-18; OL6-flow      ║
# ║     parity). Fetch epel-release-5-4 host-side, install via the EL5         ║
# ║     builder rpm against the deliverable root (db4.3 rpmdb), rewire the     ║
# ║     repo files to the CANONICAL https archive (plain http is 302-forced    ║
# ║     to https by the Fedora hosts -- measured), comment the dead            ║
# ║     mirrorlist, and ship every section enabled=0 (host-mediated service    ║
# ║     model; a lone unreachable enabled repo would break EVERY in-guest      ║
# ║     yum operation since the image carries no other repo files).            ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[A->C] (3b) EPEL 5 archive repo (epel-release + canonical archive baseurl)"
EPEL5_RPM_LOCAL="${BUILDER}/tmp/epel-release-5-4.noarch.rpm"
# shellcheck disable=SC2086  # CURL_K is intentionally word-split ("" or "-k")
curl -fsSL ${CURL_K} --max-time 120 "${EPEL5_RELEASE_RPM_URL}" -o "${EPEL5_RPM_LOCAL}" \
  || { log "[A->C] ERROR: epel-release fetch failed (${EPEL5_RELEASE_RPM_URL})"; exit 1; }
[ "$(head -c4 "${EPEL5_RPM_LOCAL}" | od -An -tx1 | tr -d ' \n')" = "edabeedb" ] \
  || { log "[A->C] ERROR: epel-release download is not an RPM"; exit 1; }
chroot "${BUILDER}" /usr/bin/env TMPDIR=/tmp /bin/rpm --root="${OUT}" -Uvh --nosignature /tmp/epel-release-5-4.noarch.rpm \
  || { log "[A->C] ERROR: epel-release install failed"; exit 1; }
rm -f "${EPEL5_RPM_LOCAL}"
# Rewire: live-mirror baseurls -> the archive (http), dead mirrorlist -> comment.
# The shipped #baseurl lines carry the full per-section tails ($basearch, debug,
# SRPMS), so a prefix substitution keeps every section correct.
find "${DELIV}/etc/yum.repos.d" -type f -name 'epel*.repo' -print0 2>/dev/null \
  | xargs -0 -r sed -i \
      -e "s|^#baseurl=http://download.fedoraproject.org/pub/epel/5/|baseurl=${EPEL5_ARCHIVE_BASEURL_PREFIX}|" \
      -e 's|^mirrorlist=|#mirrorlist=|' \
      -e 's|^enabled=1|enabled=0|' || true
grep -q '^baseurl=https://dl.fedoraproject.org/pub/archive/epel/5/' "${DELIV}/etc/yum.repos.d/epel.repo" \
  || { log "[A->C] ERROR: epel.repo rewire did not produce the archive baseurl"; exit 1; }

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [C] CLEAN-CORE — (2-cleanup) logs / transient data. OL5 is SysV-init        ║
# ║     (no systemd journal) -- the rpmdb and directory structure are kept.     ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[A->C] (2-cleanup) zero-filling logs / transient files"
ZERO_FILL=( /etc/machine-id /etc/hostname /var/lib/dbus/machine-id /root/.bash_history )
for rel in "${ZERO_FILL[@]}"; do
  if [ -f "${DELIV}${rel}" ]; then : > "${DELIV}${rel}"; fi
done
for f in "${DELIV}/root/.ssh/authorized_keys" "${DELIV}"/home/*/.ssh/authorized_keys \
         "${DELIV}"/var/lib/dhclient/* "${DELIV}"/home/*/.bash_history; do
  if [ -f "$f" ]; then : > "$f"; fi
done
find "${DELIV}/var/log" -type f -exec truncate -s 0 {} + 2>/dev/null || true
rm -f  "${DELIV}"/etc/ssh/ssh_host_* 2>/dev/null || true
rm -rf "${DELIV}"/var/lib/cloud/* "${DELIV}"/var/cache/yum/* \
       "${DELIV}"/tmp/* "${DELIV}"/var/tmp/* 2>/dev/null || true

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [A] HOST — package the [C] clean-core as tar.gz                            ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[A] packing -> ${OUT_TARBALL}"
mkdir -p "$(dirname "${OUT_TARBALL}")"
tar --numeric-owner -C "${DELIV}" -czf "${OUT_TARBALL}" .

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [C] CLEAN-CORE — unpack the deliverable (runtime-style) and self-test       ║
# ╚════════════════════════════════════════════════════════════════════════╝
IMG="${WORK}/unpacked"
log "[A->C] unpacking the deliverable tar.gz (runtime-style) -> ${IMG}"
rm -rf "${IMG}"; mkdir -p "${IMG}"
tar -C "${IMG}" -xzf "${OUT_TARBALL}"
SIZE="$(du -sh "${IMG}" | cut -f1)"

# Self-test chroot with the HOST /dev (+ /proc) bind-mounted -- the matrix
# execution model. Rationale (2026-07-19 field failure, OL5 first hit): a
# plain chroot inherits the unpack volume's mount flags, so on a `nodev`
# work volume the image's own device nodes are inert and the package-manager
# probe dies on /dev/null -- a false negative about the HOST mount, not the
# image. The binds are explicitly torn down BEFORE the image tree is removed
# (an `rm -rf` descending into a live /dev bind would delete host devices).
mount --bind /dev "${IMG}/dev" 2>/dev/null || true
mount -t proc proc "${IMG}/proc" 2>/dev/null || true
# TMPDIR=/tmp inside the guest: a leaked host TMPDIR points at a path that
# does not exist in the image (2026-07-19 field failure class).
t_run() { chroot "${IMG}" /usr/bin/env TMPDIR=/tmp "$@"; }

log "[A->C] (self-test) evaluating the unpacked clean-core image"
# The self-test does its own pass/fail accounting via st()/skip(); relax errexit
# and pipefail here so a non-zero probe (EL5 rpm/find/yum exit quirks under chroot)
# records a FAIL or 0 count instead of aborting the whole harness mid-evaluation.
set +e +o pipefail
ST_PASS=0; ST_FAIL=0; ST_SKIP=0
st() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  PASS  %s\n' "${label}"; ST_PASS=$((ST_PASS + 1))
  else
    printf '  FAIL  %s\n' "${label}"; ST_FAIL=$((ST_FAIL + 1))
  fi
}
skip() { printf '  SKIP  %s\n' "$1"; ST_SKIP=$((ST_SKIP + 1)); }

# Section 1 — UNCONDITIONAL tests (no external prerequisites; ALWAYS run).
PKGS="$(t_run /bin/rpm -qa 2>/dev/null | wc -l)"
FW="$( { t_run /bin/rpm -qa 2>/dev/null || true; } | grep -ci firmware || true)"
MID_SIZE="$(stat -c%s "${IMG}/etc/machine-id" 2>/dev/null || echo 0)"
SSH_KEYS="$(find "${IMG}/etc/ssh" -name 'ssh_host_*' 2>/dev/null | wc -l)"
NONEMPTY_LOGS="$(find "${IMG}/var/log" -type f -size +0c 2>/dev/null | wc -l)"
if [ -f "${IMG}/etc/yum.repos.d/cleancore.repo" ]; then CC_REPO=1; else CC_REPO=0; fi
REL_OK=0
for _relf in oracle-release enterprise-release redhat-release; do
  if grep -qsE 'release 5' "${IMG}/etc/${_relf}" 2>/dev/null; then REL_OK=1; fi
done
VLOCK=0
if t_run /bin/rpm -q yum-versionlock >/dev/null 2>&1; then VLOCK=1; fi
if [ -n "$(find "${IMG}/usr/lib/yum-plugins" -name 'versionlock.py*' 2>/dev/null)" ]; then VLOCK=1; fi

st "userland executes (/bin/bash runs in chroot)"   t_run /bin/bash -c true
st "rpmdb readable, >0 packages (${PKGS})"          test "${PKGS}" -gt 0
st "package manager runs (yum --version)"            t_run /usr/bin/yum --version
st "rpm is EL5-native (db4.3 rpmdb readable)"        t_run /bin/rpm -q rpm
st "jq intentionally absent (no jq for EL5)"         test ! -e "${IMG}/usr/bin/jq"
st "git intentionally absent (EPEL-only on EL5)"     test ! -e "${IMG}/usr/bin/git"
st "ssh daemon absent (no @core / no sshd)"          test ! -e "${IMG}/usr/sbin/sshd"
st "OS is Oracle Linux 5 (release 5)"                test "${REL_OK}" -eq 1
st "versionlock plugin installed (yum-versionlock)"  test "${VLOCK}" -eq 1
st "firmware excluded (0 packages)"                  test "${FW}" -eq 0
st "machine-id blanked (0 bytes)"                    test "${MID_SIZE}" -eq 0
st "ssh host keys absent (regenerate on boot)"       test "${SSH_KEYS}" -eq 0
st "logs zero-filled (no non-empty log files)"       test "${NONEMPTY_LOGS}" -eq 0
st "build-time repo dropped"                          test "${CC_REPO}" -eq 0
EPEL_ML="$(grep -c '^mirrorlist=' "${IMG}/etc/yum.repos.d/epel.repo" 2>/dev/null || true)"
EPEL_BU="$(grep -c '^baseurl=https://dl.fedoraproject.org/pub/archive/epel/5/' "${IMG}/etc/yum.repos.d/epel.repo" 2>/dev/null || true)"
EPEL_EN="$(cat "${IMG}"/etc/yum.repos.d/epel*.repo 2>/dev/null | grep -c '^enabled=1' || true)"
st "epel-release installed (EPEL 5 archive wired)"    t_run /bin/rpm -q epel-release
st "epel baseurl -> canonical Fedora archive (https)" test "${EPEL_BU}" -gt 0
st "epel mirrorlist neutralized (service dead)"       test "${EPEL_ML}" -eq 0
st "epel sections all enabled=0 (host-mediated model)" test "${EPEL_EN}" -eq 0
st "tar.gz is a valid gzip archive"                  gzip -t "${OUT_TARBALL}"

# Section 2 — readiness note. OL5's openssl 0.9.8e cannot TLS-1.2 to yum.oracle.com,
# so a live in-OS repo search is NOT meaningful on OL5 (unlike OL6-OL10). The
# faithful service model is a modern-host mirror over file:// / LAN -- which the
# BUILD path itself exercised (the OL10 work env mirrored + served the closure).
skip "in-OS live repo search -- N/A on OL5 (openssl 0.9.8e is TLS-1.0; serve via a modern-host mirror, as the build did)"

log "[A] clean-core OL5: ${PKGS} packages, ${SIZE} (unpacked)"
log "  tar.gz : ${OUT_TARBALL}"
umount "${IMG}/proc" 2>/dev/null || true
umount "${IMG}/dev" 2>/dev/null || true
rm -rf "${IMG}"
log "[A->C] self-test: ${ST_PASS} passed, ${ST_FAIL} failed, ${ST_SKIP} skipped"
if [ "${ST_FAIL}" -ne 0 ]; then
  log "[A->C] SELF-TEST FAILED"
  exit 1
fi
log "[A->C] self-test PASSED"
