#!/usr/bin/env bash
#
# build-cleancore-ol6.sh
# ----------------------------------------------------------------------------
# Naming convention: build-cleancore-ol<MAJOR>.sh  (the OS version is the
# trailing token). Family: build-cleancore-ol6.sh / -ol7.sh / -ol8.sh /
# -ol9.sh / -ol10.sh
#
# Build a *clean-core* Oracle Linux 6 container rootfs. Dedicated, self-contained
# OL6 script (no shared library, no config externalization -- by design).
#
# OL6 is the YUM-family + NEEDS-VERIFICATION member: it is EOL, so its rpm stays
# 4.8 / BerkeleyDB-4 FOREVER. Only an EL6-native rpm can write an rpmdb that the
# in-guest EL6 rpm can read (an EL7 rpm 4.11 / db5 builder yields a db an EL6 rpm
# reads as 0 packages -- proven). Hence the builder MUST be an EL6 image, and the
# package set comes from the PROJECT'S OWN OL6 kickstart (there is no upstream
# ol6-slim), not from a ks under oracle-linux-image-tools.
#
# Three execution environments are involved; each block below is tagged:
#   [A] HOST       - orchestrates only (download, extract, fetch RPMs, edit, pack, test).
#   [B] BUILDER    - a THROWAWAY OL6.6 public-yum docker image (rpm 4.8 / db4),
#                    driven via unshare+chroot. Its 2014-era NSS/curl cannot TLS
#                    -handshake modern yum.oracle.com, so it is FIRST modernized:
#                    (a) host-fetched el6_10 TLS RPMs are rpm-installed by the
#                    builder's own rpm 4.8; (b) yum + rpm are updated. Then it can
#                    resolve current packages. Contents are NOT shipped.
#   [C] CLEAN-CORE - the DELIVERABLE rootfs from the yum --installroot transaction.
#
# ----------------------------------------------------------------------------
# PRIMARY SOURCES (verify upstream)
#   - Builder image (OL6.6 public-yum docker image; rpm 4.8 / db4), Oracle official:
#       https://public-yum.oracle.com/docker-images/OracleLinux/OL6/oraclelinux-6.6.tar.xz
#   - Package set = the PROJECT'S OWN OL6 kickstart %packages (no upstream ol6-slim):
#       build-ol-aws-ami.sh  ->  EOF_OL6_KS heredoc  (%packages ~L1795)
#   - Package repositories + el6_10 TLS RPMs, Oracle official:
#       https://yum.oracle.com/repo/OracleLinux/OL6/latest/x86_64/
#   - Cleanup guidance (VM-oriented; container-applicable subset adopted), AWS:
#       https://docs.aws.amazon.com/imagebuilder/latest/userguide/security-best-practices.html
# ----------------------------------------------------------------------------
# Usage:   bash build-cleancore-ol6.sh [output.tar.gz]
#   env :  WORK=<scratch dir>   INSECURE_TLS=0  (drop sslverify=0 on a trusted host)
# Requires: root (unshare/chroot/mknod), curl, tar, xz, gzip, unshare, truncate, find.
# Exit:    0 = built and self-test passed; non-zero = build error or test failure.
# ----------------------------------------------------------------------------
set -euo pipefail

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [A] HOST — configuration (inline by design; not externalized)            ║
# ╚════════════════════════════════════════════════════════════════════════╝
OSMAJOR=6
BUILDER_URL="https://public-yum.oracle.com/docker-images/OracleLinux/OL6/oraclelinux-6.6.tar.xz"

WORK="${WORK:-/tmp/cleancore-ol6}"
OUT_TARBALL="${1:-${WORK}/cleancore-ol6-rootfs.tar.gz}"

# Sandbox without a usable NSS trust store -> sslverify=0 for the BUILD only,
# written into the build-time cleancore.repo (dropped before delivery).
INSECURE_TLS="${INSECURE_TLS:-1}"
SSL=1; [ "${INSECURE_TLS}" = "1" ] && SSL=0

REPO_BASE="https://yum.oracle.com/repo/OracleLinux/OL${OSMAJOR}/latest/x86_64"

# TLS stack to host-fetch (modern host TLS) and install with the builder's rpm
# 4.8 so the builder's NSS 3.16 -> 3.44 and modern https becomes possible.
TLS_PKGS=( nspr nss nss-util nss-softokn nss-softokn-freebl nss-sysinit
           nss-tools curl libcurl ca-certificates openssl )

# Package manifest = the PROJECT'S OWN OL6 kickstart %packages (@core implicit
# base). NOTE the OL6-specific names vs newer OLs: iptables (not
# iptables-services), ntp (not chrony), grub (legacy GRUB), yum (not dnf).
INCLUDE=( @core
  yum initscripts passwd rsyslog vim-minimal openssh-server openssh-clients
  dhclient chkconfig rootfiles policycoreutils checkpolicy selinux-policy
  selinux-policy-targeted libselinux oraclelinux-release oraclelinux-release-notes
  yum-rhn-plugin yum-plugin-security yum-utils device-mapper-libs device-mapper
  kpartx net-tools iptables ntp acpid cronie cronie-anacron crontabs grub )

# OL6 kickstart removals. Firmware (option A) via the *-firmware glob (catches
# kernel-firmware = EL6's linux-firmware, plus iwl*/ql*/bfa/...). Raw-yum hard
# deps that Anaconda would soft-drop are intentionally NOT excluded so the
# transaction resolves: plymouth (initscripts), cyrus-sasl (sendmail = EL6 @core
# MTA), acl, lzo, elfutils-libs. EL6 has no group_package_types=mandatory step
# (this faithfully reproduces the project's own OL6 image, unlike OL7-10).
EXCLUDE="NetworkManager,iprutils,biosdevname,wireless-tools,\
system-config-securitylevel-tui,postfix,mysql-libs,kexec-tools,efibootmgr,\
bc,busybox,mdadm,pciutils-libs,snappy,attr,audit,*-firmware,b43-openfwwf"

BUILDER="${WORK}/builder"      # [B] throwaway EL6-native builder rootfs
OUT="/cleancore"               # [C] installroot path INSIDE the builder
DELIV="${BUILDER}${OUT}"       # [C] deliverable rootfs as seen from [A]

log() { printf '%s [cleancore-ol6] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }


# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [A] HOST — acquire the builder rootfs from a docker-save tarball.          ║
# ║     The public-yum docker image is `manifest.json` + per-layer `layer.tar` ║
# ║     (OL6.6 is a single layer); extract each layer in order into [B].       ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[A] downloading OL6.6 public-yum docker image (builder)"
rm -rf "${WORK}"
mkdir -p "${BUILDER}"
curl -fsSL -o "${WORK}/builder.tar.xz" "${BUILDER_URL}"
STAGE="${WORK}/stage"
mkdir -p "${STAGE}"
tar -C "${STAGE}" -xJf "${WORK}/builder.tar.xz"
rm -f "${WORK}/builder.tar.xz"
log "[A] unpacking docker layer(s) into the builder rootfs"
if [ -f "${STAGE}/manifest.json" ]; then
  # ordered layer list from the docker manifest
  grep -oE '"[^"]*layer\.tar"' "${STAGE}/manifest.json" | tr -d '"' | while read -r layer; do
    [ -n "${layer}" ] && tar -C "${BUILDER}" -xf "${STAGE}/${layer}"
  done
else
  find "${STAGE}" -name 'layer.tar' -exec tar -C "${BUILDER}" -xf {} \;
fi
rm -rf "${STAGE}"
[ -x "${BUILDER}/bin/rpm" ] || { log "[A] ERROR: builder has no /bin/rpm"; exit 1; }
cp -f /etc/resolv.conf "${BUILDER}/etc/resolv.conf" 2>/dev/null || true

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [A] HOST — fetch the el6_10 TLS RPMs (newest x86_64/noarch each), using     ║
# ║     the host's modern TLS, by parsing the OL6 repo primary.xml.            ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[A] fetching el6_10 TLS bootstrap RPMs from ${REPO_BASE}"
TLSDIR="${WORK}/tls"
mkdir -p "${TLSDIR}"
curl -fsSL "${REPO_BASE}/repodata/repomd.xml" -o "${WORK}/repomd.xml"
PRIMARY_REL="$(grep -oE 'repodata/[a-f0-9]+-primary\.xml\.gz' "${WORK}/repomd.xml" | head -1)"
[ -n "${PRIMARY_REL}" ] || { log "[A] ERROR: primary.xml.gz not found in repomd"; exit 1; }
curl -fsSL "${REPO_BASE}/${PRIMARY_REL}" -o "${WORK}/primary.xml.gz"
gunzip -f "${WORK}/primary.xml.gz"   # -> ${WORK}/primary.xml
for name in "${TLS_PKGS[@]}"; do
  # newest (version-sorted) x86_64/noarch href for exactly this package name
  href="$(grep -oE "getPackage/${name}-[0-9][^\"]*\.rpm" "${WORK}/primary.xml" \
            | grep -vE '\.i686\.rpm$' | sort -V | tail -1)"
  [ -n "${href}" ] || { log "[A] ERROR: no RPM found for TLS package '${name}'"; exit 1; }
  curl -fsSL "${REPO_BASE}/${href}" -o "${TLSDIR}/$(basename "${href}")"
done
log "[A] fetched $(find "${TLSDIR}" -name '*.rpm' | wc -l) TLS RPMs"

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [A->B] stage the TLS RPMs inside [B] and install the builder-dedicated     ║
# ║        clean-core yum.repo as the ONLY repo (builder's own repos removed). ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[A->B] (1) staging TLS RPMs + writing builder clean-core yum.repo"
mkdir -p "${BUILDER}/tmp/tls"
cp -f "${TLSDIR}"/*.rpm "${BUILDER}/tmp/tls/"
rm -f "${BUILDER}/etc/yum.repos.d/"*.repo
cat > "${BUILDER}/etc/yum.repos.d/cleancore.repo" <<EOF
[cc_ol6_latest]
name=OL${OSMAJOR} latest
baseurl=${REPO_BASE}/
gpgcheck=0
sslverify=${SSL}
enabled=1
EOF

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [B] BUILDER — modernize (runs INSIDE the builder via chroot):              ║
# ║   (TLS) builder rpm 4.8 installs the el6_10 NSS/curl/ca-certs stack         ║
# ║   (4A)  yum updates the package managers (yum, rpm)                         ║
# ║   oraclelinux-release is intentionally NOT updated here (the builder reads  ║
# ║   only cleancore.repo; the deliverable's release comes from the install).   ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[B] (TLS) installing el6_10 TLS stack via the builder's rpm 4.8"
unshare --fork --pid --mount --uts --ipc bash -c "
  mount --bind /dev '${BUILDER}/dev'  2>/dev/null || true
  mount -t proc proc '${BUILDER}/proc' 2>/dev/null || true
  chroot '${BUILDER}' /bin/rpm -Uvh --replacepkgs --replacefiles /tmp/tls/*.rpm
"
log "[B] (4A) updating builder package managers (yum, rpm)"
unshare --fork --pid --mount --uts --ipc bash -c "
  mount --bind /dev '${BUILDER}/dev'  2>/dev/null || true
  mount -t proc proc '${BUILDER}/proc' 2>/dev/null || true
  chroot '${BUILDER}' /usr/bin/yum -y --setopt=sslverify=${SSL} --nogpgcheck \
    --disablerepo='*' --enablerepo=cc_ol6_latest update yum rpm
"

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [B->C] the install transaction; writes the [C] clean-core rootfs via       ║
# ║        yum --installroot (OUT lives inside the builder fs).                 ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[B->C] building clean-core into ${DELIV}"
rm -rf "${DELIV}"
unshare --fork --pid --mount --uts --ipc bash -c "
  mount --bind /dev '${BUILDER}/dev'  2>/dev/null || true
  mount -t proc proc '${BUILDER}/proc' 2>/dev/null || true
  chroot '${BUILDER}' /usr/bin/yum -y --installroot='${OUT}' --releasever=${OSMAJOR} \
    --disablerepo='*' --enablerepo=cc_ol6_latest --nogpgcheck \
    --setopt=tsflags=nodocs --setopt=sslverify=${SSL} \
    --exclude='${EXCLUDE}' \
    install ${INCLUDE[*]}
  chroot '${BUILDER}' /usr/bin/yum --installroot='${OUT}' clean all >/dev/null 2>&1 || true
"

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [C] CLEAN-CORE — finalized from [A] (host).                                ║
# ║     (3) device nodes + OCI-variable rewrite + OL6 UEK enable-var disable +  ║
# ║         drop the build-time repo.                                          ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[A->C] (3) device nodes, OCI + UEK rewrite, drop build-time repo"
for n in "null c 1 3" "zero c 1 5" "random c 1 8" "urandom c 1 9" \
         "full c 1 7" "console c 5 1" "ptmx c 5 2" "tty c 5 0"; do
  # shellcheck disable=SC2086  # intentional word-split of the "name type maj min" node spec
  set -- $n
  rm -f "${DELIV}/dev/$1"
  mknod -m 666 "${DELIV}/dev/$1" "$2" "$3" "$4" 2>/dev/null || true
done
rm -f "${DELIV}/etc/yum.repos.d/cleancore.repo"
# keep the rpm-provided repo files as source of truth; rewrite ONLY the
# unresolvable OCI variables + force https, and (OL6 uek repo) hard-disable the
# UEK enable-vars $uekr4/$uekr3/$uek. $basearch is a real yum var -- preserved.
# shellcheck disable=SC2016  # $ociregion/$ocidomain/$uek* are literal yum-variable text in the repo files, not shell expansions
find "${DELIV}/etc/yum.repos.d" -type f -name '*.repo*' -print0 \
  | xargs -0 -r sed -i \
      -e 's|yum$ociregion.$ocidomain|yum.oracle.com|g' \
      -e 's|yum$ociregion.oracle.com|yum.oracle.com|g' \
      -e 's|http://yum.oracle.com|https://yum.oracle.com|g' \
      -e "s|enabled[ ]*=[ ]*'\?\$uekr4'\?|enabled=0|g" \
      -e "s|enabled[ ]*=[ ]*'\?\$uekr3'\?|enabled=0|g" \
      -e "s|enabled[ ]*=[ ]*'\?\$uek'\?|enabled=0|g"

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [C] CLEAN-CORE — (2-cleanup) logs / transient data (zero-fill preferred).  ║
# ║     OL6 is systemd-less (upstart): there is no journal; machine-id is a     ║
# ║     dbus concept. The rpmdb and directory structure are preserved.         ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[A->C] (2-cleanup) zero-filling logs / transient files"
: > "${DELIV}/etc/machine-id"
ZERO_FILL=(
  /etc/hostname
  /var/lib/dbus/machine-id
  /root/.bash_history
)
for rel in "${ZERO_FILL[@]}"; do
  if [ -f "${DELIV}${rel}" ]; then : > "${DELIV}${rel}"; fi
done
for f in "${DELIV}/root/.ssh/authorized_keys" "${DELIV}"/home/*/.ssh/authorized_keys \
         "${DELIV}"/var/lib/dhclient/* "${DELIV}"/home/*/.bash_history; do
  if [ -f "$f" ]; then : > "$f"; fi
done
find "${DELIV}/var/log" -type f -exec truncate -s 0 {} + 2>/dev/null || true

# REMOVE (an empty file here is broken, or it is pure cache/transient):
rm -f  "${DELIV}"/etc/ssh/ssh_host_* 2>/dev/null || true
rm -rf "${DELIV}"/var/lib/cloud/* \
       "${DELIV}"/var/cache/yum/* \
       "${DELIV}"/tmp/* "${DELIV}"/var/tmp/* 2>/dev/null || true

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [A] HOST — package the [C] clean-core as tar.gz                            ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[A] packing -> ${OUT_TARBALL}"
mkdir -p "$(dirname "${OUT_TARBALL}")"
tar --numeric-owner -C "${DELIV}" -czf "${OUT_TARBALL}" .

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [C] CLEAN-CORE — unpack the deliverable (runtime-style) and self-test       ║
# ║     The shipped artifact is the tar.gz, so the tests run against a FRESH     ║
# ║     unpack of it -- exactly what a container runtime does -- NOT the build   ║
# ║     tree. This also catches anything lost or corrupted during packing.      ║
# ╚════════════════════════════════════════════════════════════════════════╝
IMG="${WORK}/unpacked"
log "[A->C] unpacking the deliverable tar.gz (runtime-style) -> ${IMG}"
rm -rf "${IMG}"; mkdir -p "${IMG}"
tar -C "${IMG}" -xzf "${OUT_TARBALL}"
SIZE="$(du -sh "${IMG}" | cut -f1)"   # pristine size, before any test writes cache

# test-time chroot helper -- operates on the UNPACKED image, not the build tree.
t_run() { chroot "${IMG}" "$@"; }

log "[A->C] (self-test) evaluating the unpacked clean-core image"
ST_PASS=0; ST_FAIL=0; ST_SKIP=0
st() {   # st "<label>" <command...>  -> PASS if the command exits 0, else FAIL
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  PASS  %s\n' "${label}"; ST_PASS=$((ST_PASS + 1))
  else
    printf '  FAIL  %s\n' "${label}"; ST_FAIL=$((ST_FAIL + 1))
  fi
}
skip() { printf '  SKIP  %s\n' "$1"; ST_SKIP=$((ST_SKIP + 1)); }

# ───────────────────────────────────────────────────────────────────────────
# Section 1 — UNCONDITIONAL tests (no external prerequisites; ALWAYS run).
# ───────────────────────────────────────────────────────────────────────────
PKGS="$(t_run /bin/rpm -qa 2>/dev/null | wc -l)"
FW="$( { t_run /bin/rpm -qa 2>/dev/null || true; } | grep -ci firmware || true)"
MID_SIZE="$(stat -c%s "${IMG}/etc/machine-id" 2>/dev/null || echo -1)"
SSH_KEYS="$(find "${IMG}/etc/ssh" -name 'ssh_host_*' 2>/dev/null | wc -l)"
NONEMPTY_LOGS="$(find "${IMG}/var/log" -type f -size +0c 2>/dev/null | wc -l)"
OCI_LEFT="$( { grep -rl 'ociregion' "${IMG}/etc/yum.repos.d/" 2>/dev/null || true; } | wc -l)"
UEK_ON="$( { grep -rsE "enabled[ ]*=[ ]*'?\\\$uek" "${IMG}/etc/yum.repos.d/" 2>/dev/null || true; } | wc -l)"
if [ -f "${IMG}/etc/yum.repos.d/cleancore.repo" ]; then CC_REPO=1; else CC_REPO=0; fi

st "userland executes (/bin/bash runs in chroot)"   t_run /bin/bash -c true
st "rpmdb readable, >0 packages (${PKGS})"          test "${PKGS}" -gt 0
st "package manager runs (yum --version)"            t_run /usr/bin/yum --version
st "ssh daemon present (sshd)"                       test -x "${IMG}/usr/sbin/sshd"
st "OS is Oracle Linux 6"                            grep -q "release 6" "${IMG}/etc/oracle-release"
st "firmware excluded (0 packages)"                  test "${FW}" -eq 0
st "machine-id blanked (0 bytes)"                    test "${MID_SIZE}" -eq 0
st "ssh host keys absent (regenerate on boot)"       test "${SSH_KEYS}" -eq 0
st "logs zero-filled (no non-empty log files)"       test "${NONEMPTY_LOGS}" -eq 0
st "OCI yum variables rewritten (none remain)"       test "${OCI_LEFT}" -eq 0
st "UEK enable-vars disabled (none remain)"          test "${UEK_ON}" -eq 0
st "build-time repo dropped"                          test "${CC_REPO}" -eq 0
st "tar.gz is a valid gzip archive"                  gzip -t "${OUT_TARBALL}"

# ───────────────────────────────────────────────────────────────────────────
# Section 2 — PREREQUISITE-GATED readiness test (is the image ready for the
#   follow-on package work this test base exists for?). Prerequisites, split:
#     image-side  (must live IN the deliverable): enabled yum/dnf repos
#                 (oraclelinux-release*, checked above) + ca-certificates (TLS).
#     harness-side(NOT baked; supplied at test time, as a runtime would): repo
#                 network reachability + DNS, sslverify per ${SSL}, and either a
#                 container runtime or /dev + /proc for a chroot.
#   If a harness-side prerequisite is missing the readiness test is SKIPPED
#   (it never FAILs the build); Section 1 alone governs pass/fail.
# ───────────────────────────────────────────────────────────────────────────
# image-side prerequisite (always checkable, no network): ca-certificates in img
st "ca-certificates present (TLS trust base)"        t_run /bin/rpm -q ca-certificates

# readiness probe: import+run via a container runtime where possible, else
# unpack+chroot. The search proves the (rewritten) repo config + manager work
# end-to-end: config parse -> metadata download -> query. resolv.conf is supplied
# transiently (the tarball ships none); sslverify follows ${SSL} (transient
# --setopt; never baked into the deliverable's repos).
cc_search_ready() {
  local rt=""
  for c in podman docker; do command -v "$c" >/dev/null 2>&1 && { rt="$c"; break; }; done
  if [ -n "${rt}" ]; then
    local tag="cleancore-ol6-selftest:tmp" rc
    if "${rt}" import "${OUT_TARBALL}" "${tag}" >/dev/null 2>&1 \
       && "${rt}" run --rm "${tag}" /bin/bash -c true >/dev/null 2>&1; then
      "${rt}" run --rm "${tag}" /usr/bin/yum -q --setopt=sslverify=${SSL} --nogpgcheck \
        search oraclelinux-release >/dev/null 2>&1; rc=$?
      "${rt}" rmi -f "${tag}" >/dev/null 2>&1 || true
      return "${rc}"
    fi
    "${rt}" rmi -f "${tag}" >/dev/null 2>&1 || true
  fi
  # no runtime, or it cannot run here (e.g. the Claude sandbox) -> unpack+chroot
  cp -f /etc/resolv.conf "${IMG}/etc/resolv.conf" 2>/dev/null || true
  unshare --fork --pid --mount --uts --ipc bash -c "
    mount --bind /dev '${IMG}/dev'  2>/dev/null || true
    mount -t proc proc '${IMG}/proc' 2>/dev/null || true
    chroot '${IMG}' /usr/bin/yum -q --setopt=sslverify=${SSL} --nogpgcheck \
      search oraclelinux-release
  "
}

if curl -fsS --max-time 8 -o /dev/null "https://yum.oracle.com/" 2>/dev/null; then
  st "repo config + manager ready (search oraclelinux-release)" cc_search_ready
else
  skip "repo config + manager ready (search oraclelinux-release) -- no network/DNS/TLS"
fi

# ───────────────────────────────────────────────────────────────────────────
log "[A] clean-core OL6: ${PKGS} packages, ${SIZE} (unpacked)"
log "  tar.gz : ${OUT_TARBALL}"
rm -rf "${IMG}"   # drop the test unpack -- the deliverable is the tar.gz
log "[A->C] self-test: ${ST_PASS} passed, ${ST_FAIL} failed, ${ST_SKIP} skipped"
if [ "${ST_FAIL}" -ne 0 ]; then
  log "[A->C] SELF-TEST FAILED"
  exit 1
fi
log "[A->C] self-test PASSED"
