#!/usr/bin/env bash
#==============================================================================
# tests/t025_ol5build.sh - OL5 AMI build target: synthesized-artifact +
# wiring conformance (test pyramid layer L1/L2, structural + function-level)
#
# The OL5 target is runtime-synthesized (distr/ol5-slim heredocs) and
# host-supplied ([OLAWS-OL5S1]); nothing of it exists on disk until Phase 3
# runs. This tier extracts the embedded templates from build-ol-aws-ami.sh
# and asserts the EL5 invariants that a modern-host gate CAN check:
#
#   (A) template extraction (env / image-scripts / kickstart / provision /
#       the OL5S1 executor body)
#   (B) kickstart shape: the measured EL5/anaconda-11.1 constraints (NO %end,
#       key --skip, cdrom, ext3, LABEL parts, no RHEL6+ tokens, ec2-user
#       creation, growroot one-shot, serial console, sysprep stubs)
#   (C) bash-3.2 safety of every GUEST-side block (no ${var,,}/${var^^},
#       mapfile/readarray, declare -A, |&) -- the mechanical guard that keeps
#       future edits from silently breaking the EL5 guest
#   (D) OL5S1 executor: load-bearing ORDER (modprobe aliases before the rpm
#       transaction before /usr/src staging) + the hard asserts
#   (E) provision.sh EL5 discipline (no common::distr_cleanup, sshd
#       without-password, rp_filter 0, DRACUT_CMD poisoned)
#   (F) HOST-supply manifests: the builder's toolchain list is BYTE-IDENTICAL
#       to the matrix's proven OL5_TOOLCHAIN_RPMS; the EPEL5 closure carries
#       the frozen cloud-init 0.6.3 NVR set + gdisk
#   (G) wrapper wiring: Enterprise-R ISO parse (behavioral), IMDSv2-only
#       rejection, SSM forced-off, NVM01 skip, awscli guard, disk-bus patch,
#       P3GATE OL5 branch (behavioral: the REAL extracted gate passes the
#       REAL extracted kickstart, and fails mutated ones)
#   (H) env.properties.aws-ol5 template invariants
#
# What this tier CANNOT prove (operator-side E2E): real EL5 anaconda accepting
# the kickstart, the rpm transaction inside virt-customize, Nitro boot.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
MAIN="${PROJ}/build-ol-aws-ami.sh"
ENVF="${PROJ}/env.properties.aws-ol5"
MTX="${PROJ}/tests/ena/run-ena-buildtest-matrix.sh"

WORK="$(mktemp -d /tmp/t025.XXXXXX)"
trap 'rm -rf "${WORK}"' EXIT

# extract_heredoc MARKER OUT -- literal body of a single-quoted heredoc
extract_heredoc() {
  awk -v m="$1" '
    $0 ~ ("<<\x27" m "\x27") { f=1; next }
    $0 == m                  { f=0 }
    f                        { print }
  ' "${MAIN}" > "$2"
}

# ---- (A) extraction ---------------------------------------------------------
extract_heredoc 'EOF_OL5_ENV'       "${WORK}/env"
extract_heredoc 'EOF_OL5_IMG'       "${WORK}/img"
extract_heredoc 'EOF_OL5_KS'        "${WORK}/ks"
extract_heredoc 'EOF_OL5_PROV'      "${WORK}/prov"
extract_heredoc 'OLAWS_OL5S1_BODY'  "${WORK}/s1"
for t in env img ks prov s1; do
  if [ -s "${WORK}/${t}" ]; then
    t_pass "extract: OL5 template '${t}' extracted ($(wc -l < "${WORK}/${t}") lines)"
  else
    t_fail "extract: OL5 template '${t}' is empty -- heredoc marker moved?"
  fi
done
ks="$(cat "${WORK}/ks")"
prov="$(cat "${WORK}/prov")"
s1="$(cat "${WORK}/s1")"
envt="$(cat "${WORK}/env")"
main="$(cat "${MAIN}")"
envf="$(cat "${ENVF}")"

# ---- (B) kickstart: EL5/anaconda-11.1 shape --------------------------------
n_end="$(grep -cE '^%end$' "${WORK}/ks" || true)"
assert_eq 0 "${n_end}" "ks: contains NO '%end' (anaconda-11.1 would read it as a package name)"
n_sec="$(grep -cE '^%(packages|post)([[:space:]]|$)' "${WORK}/ks" || true)"
assert_eq 2 "${n_sec}" "ks: exactly 2 section openers (%packages + %post)"
assert_match "${ks}" '^install$'      "ks: 'install' present"
assert_match "${ks}" '^cdrom$'        "ks: 'cdrom' pins the package source (no stage2= boot arg)"
assert_match "${ks}" '^key --skip$'   "ks: 'key --skip' (EL5-only installation-number suppressor)"
assert_match "${ks}" "^rootpw --iscrypted \*$" "ks: locked no-valid-password rootpw (no RHEL6+ --lock)"
assert_match "${ks}" '^firewall --enabled --ssh$' "ks: firewall --enabled --ssh (VERIFIED against real pykickstart 0.43.9: --ssh is a port-map option, ssh->22:tcp -- D.32 grammar record)"
assert_match "${ks}" '^part /boot +--fstype=ext3 .*--label=/boot' "ks: /boot is ext3 + LABELed"
assert_match "${ks}" '^part / +--fstype=ext3 .*--label=root +--grow' "ks: / is ext3 + LABEL=root + --grow (growroot target)"
for tok in '^services ' '^cmdline$' '--only-use' '--ondisk' '^bootloader.*--timeout' '^rootpw --lock'; do
  if grep -Eq -- "${tok}" "${WORK}/ks"; then
    t_fail "ks: RHEL6+/forbidden token present: ${tok}"
  else
    t_pass "ks: RHEL6+ token absent: ${tok}"
  fi
done
assert_match "${ks}" '^%post --interpreter /bin/bash$' "ks: plain %post --interpreter form (logging via exec redirect by choice; the real 0.43 parser does accept --log -- D.32 grammar record)"
assert_match "${ks}" '^exec > /root/ks-post\.log 2>&1$' "ks: %post log captured via exec redirect (common::ks_log path)"
assert_match "${ks}" '/usr/sbin/useradd -m -s /bin/bash ec2-user' "ks: ec2-user pre-created (cloud-init 0.6.3 is getpwnam-only)"
assert_match "${ks}" "ec2-user ALL=\(ALL\) NOPASSWD:ALL" "ks: passwordless sudo for ec2-user (direct sudoers line)"
assert_match "${ks}" 'console=tty0 console=ttyS0,115200n8' "ks: serial console appended to GRUB Legacy cmdline (D.25)"
assert_match "${ks}" 'serial --unit=0 --speed=115200' "ks: GRUB-over-serial directives (interactive EC2 Serial Console)"
assert_match "${ks}" ': > /etc/machine-id' "ks: machine-id stub for virt-sysprep (D.20)"
assert_match "${ks}" '^sos$' "ks: sos baked into %packages (OL6-10 parity invariant)"
assert_match "${ks}" '^rsyslog$' "ks: rsyslog listed (cloud-init 0.6.3 hard Requires)"
for p in e4fsprogs libselinux-python iproute crontabs util-linux mkinitrd module-init-tools; do
  assert_match "${ks}" "^${p}\$" "ks: closure/tooling package listed: ${p}"
done
# growroot one-shot -- growpart decision model (adjudicated 2026-07-19):
# geometry PRIMARY, marker SECONDARY (loop breaker, self-healed on success)
assert_match "${ks}" '/etc/init.d/ol-aws-growroot' "ks: growroot one-shot init script baked"
assert_match "${ks}" '# chkconfig: 2345 08 92' "ks: growroot runs BEFORE cloud-init (S08 < S20)"
assert_match "${ks}" '/sbin/chkconfig --add ol-aws-growroot' "ks: growroot registered via chkconfig"
extract_heredoc_from() {
  awk -v m="$2" '
    $0 ~ ("<<\x27" m "\x27") { f=1; next }
    $0 == m                  { f=0 }
    f                        { print }
  ' "$1" > "$3"
}
extract_heredoc_from "${WORK}/ks" 'EOF_GROWROOT' "${WORK}/gr"
if [ -s "${WORK}/gr" ]; then
  t_pass "growroot: EOF_GROWROOT extracted from the kickstart ($(wc -l < "${WORK}/gr") lines)"
else
  t_fail "growroot: EOF_GROWROOT heredoc not extractable"
fi
gr="$(cat "${WORK}/gr")"
bash -n "${WORK}/gr" 2>/dev/null
assert_rc 0 $? "growroot: extracted script parses (bash -n)"
# structural pins of the adjudicated model
l_geo="$(grep -n 'PRIMARY criterion' "${WORK}/gr" | head -1 | cut -d: -f1)"
l_mk="$(grep -n 'SECONDARY criterion' "${WORK}/gr" | head -1 | cut -d: -f1)"
if [ -n "${l_geo}" ] && [ -n "${l_mk}" ] && [ "${l_geo}" -lt "${l_mk}" ]; then
  t_pass "growroot: geometry decision precedes the marker check (PRIMARY < SECONDARY by position)"
else
  t_fail "growroot: PRIMARY/SECONDARY ordering broken (geo=${l_geo:-?} marker=${l_mk:-?})"
fi
assert_match "${gr}" 'MARKER=/var/lib/ol-aws-growroot\.attempt' "growroot: marker is an ATTEMPT record (loop breaker), not the execution criterion"
assert_match "${gr}" 'FUDGE_SECTORS=2048' "growroot: growpart-style 1 MiB fudge on the NOCHANGE decision"
assert_match "${gr}" 'stale attempt marker cleared' "growroot: marker self-heals on success (re-armed for future volume growth)"
assert_match "${gr}" 'NOT retrying \(reboot-loop protection\)' "growroot: marker blocks only the retry-reboot, loudly"
assert_match "${gr}" 'sfdisk -d ' "growroot: reads the on-disk table via sfdisk dump (growpart model, not fdisk keystrokes)"
if grep -Eq 'printf .u.n' "${WORK}/gr"; then
  t_fail "growroot: legacy fdisk keystroke pipeline still present"
else
  t_pass "growroot: legacy fdisk keystroke pipeline removed"
fi
assert_match "${gr}" 'sfdisk --no-reread --force' "growroot: applies with --no-reread --force (busy-disk model; kernel re-read deferred to the reboot)"
assert_match "${gr}" 'start=\[ \]\*\$\{pstart\},' "growroot: table entry addressed by START SECTOR (util-linux 2.13 sfdisk misnames NVMe partitions)"
assert_match "${gr}" 'Id=\$\{pid\} \(only plain Linux 83' "growroot: partition-type guard (only Id=83 grown; ee=GPT refused)"
assert_match "${gr}" 'a partition starts after the root partition' "growroot: refuses when root is not the last partition"
assert_match "${gr}" 'ol-aws-growroot\.sfdisk-backup' "growroot: old dump saved as the restore vehicle before writing"
assert_match "${gr}" 'POST-WRITE VERIFY FAILED' "growroot: post-write verify by re-dump, with restore on mismatch"
assert_match "${gr}" 'BLKPG_RESIZE_PARTITION \(kernel 3\.6\+\)' "growroot: the one-reboot requirement is grounded (no online root resize below 3.6; UEK R2 = 3.0.36)"
assert_match "${gr}" '/sbin/reboot' "growroot: reboots once so the kernel re-reads the table"

# behavioral: fake sysfs + mock df/sfdisk/reboot drive the real decision logic
GRT="${WORK}/grt"
mkdir -p "${GRT}/bin" "${GRT}/sys/block/xvda/xvda1" "${GRT}/sys/block/xvda/xvda2" "${GRT}/state" "${GRT}/varlib"
echo 20971520 > "${GRT}/sys/block/xvda/size"
echo 2048     > "${GRT}/sys/block/xvda/xvda1/start"
echo 409600   > "${GRT}/sys/block/xvda/xvda1/size"
echo 411648   > "${GRT}/sys/block/xvda/xvda2/start"
echo 8388608  > "${GRT}/sys/block/xvda/xvda2/size"
cat > "${GRT}/state/dump-old" <<'EOF_DUMP'
# partition table of /dev/xvda
unit: sectors

/dev/xvda1 : start=     2048, size=   409600, Id=83, bootable
/dev/xvda2 : start=   411648, size=  8388608, Id=83
/dev/xvda3 : start=        0, size=        0, Id= 0
/dev/xvda4 : start=        0, size=        0, Id= 0
EOF_DUMP
sed 's/size=  8388608/size= 20559872/' "${GRT}/state/dump-old" > "${GRT}/state/dump-new"
cat > "${GRT}/bin/df" <<EOF_DF
#!/bin/sh
echo "Filesystem 512-blocks Used Available Capacity Mounted on"
echo "/dev/xvda2 4194304 1000 4193304 1% /"
EOF_DF
cat > "${GRT}/bin/sfdisk" <<EOF_SF
#!/bin/sh
S="${GRT}/state"
if [ "\$1" = "-d" ]; then
  if [ -f "\$S/applied" ]; then cat "\$S/dump-new"; else cat "\$S/dump-old"; fi
  exit 0
fi
cat > "\$S/applied-input"
touch "\$S/applied"
exit 0
EOF_SF
cat > "${GRT}/bin/reboot" <<EOF_RB
#!/bin/sh
touch "${GRT}/state/rebooted"
EOF_RB
chmod +x "${GRT}/bin/"*
: > "${GRT}/dev-xvda"
# shellcheck disable=SC2016
sed -e "s|/sys/block|${GRT}/sys/block|g" \
    -e 's|\[ -b "\$disk" \]|[ -e "'"${GRT}"'/dev-xvda" ]|' \
    -e 's|/sbin/reboot|reboot|' \
    -e "s|MARKER=/var/lib/ol-aws-growroot.attempt|MARKER=${GRT}/varlib/attempt|" \
    -e "s|bak=/var/lib/ol-aws-growroot.sfdisk-backup|bak=${GRT}/varlib/backup|" \
    -e "s|LOG=/var/log/ol-aws-growroot.log|LOG=${GRT}/state/log|" \
    -e "s|mkdir -p /var/lib|mkdir -p ${GRT}/varlib|" \
    "${WORK}/gr" > "${GRT}/run.sh"
gr_run() { rm -f "${GRT}/state/log"; PATH="${GRT}/bin:${PATH}" sh "${GRT}/run.sh" start >/dev/null 2>&1; }
# case: grow path -- edit + apply + verify + reboot + marker
gr_run
if grep -q 'size= 20559872' "${GRT}/state/applied-input" 2>/dev/null \
   && [ -f "${GRT}/state/rebooted" ] && grep -q 'verified:' "${GRT}/varlib/attempt" 2>/dev/null; then
  t_pass "growroot(behavioral): grow path -- correct single-field edit applied, verified, one reboot, attempt recorded"
else
  t_fail "growroot(behavioral): grow path broken (edit/apply/verify/reboot/marker)"
fi
# case: post-reboot self-heal -- geometry grown => NOCHANGE + marker cleared
echo 20559872 > "${GRT}/sys/block/xvda/xvda2/size"
rm -f "${GRT}/state/rebooted"
gr_run
if grep -q 'NOCHANGE' "${GRT}/state/log" && [ ! -f "${GRT}/varlib/attempt" ] && [ ! -f "${GRT}/state/rebooted" ]; then
  t_pass "growroot(behavioral): post-grow boot -- NOCHANGE by geometry, marker self-healed, no reboot"
else
  t_fail "growroot(behavioral): post-grow self-heal broken"
fi
# case: marker is SECONDARY -- growth needed + marker => loud, no apply, no reboot
echo 8388608 > "${GRT}/sys/block/xvda/xvda2/size"
rm -f "${GRT}/state/applied" "${GRT}/state/applied-input" "${GRT}/state/rebooted"
echo "attempted: earlier" > "${GRT}/varlib/attempt"
gr_run
if grep -q 'NOT retrying' "${GRT}/state/log" && [ ! -f "${GRT}/state/applied" ] && [ ! -f "${GRT}/state/rebooted" ]; then
  t_pass "growroot(behavioral): marker as SECONDARY -- growth still needed is reported loudly, no write, no reboot"
else
  t_fail "growroot(behavioral): marker-secondary semantics broken"
fi
# case: fudge NOCHANGE (free tail 1024 < 2048)
rm -f "${GRT}/varlib/attempt"
echo 20558848 > "${GRT}/sys/block/xvda/xvda2/size"
gr_run
if grep -q 'NOCHANGE' "${GRT}/state/log" && [ ! -f "${GRT}/state/rebooted" ]; then
  t_pass "growroot(behavioral): sub-fudge free tail -> NOCHANGE (growpart semantics)"
else
  t_fail "growroot(behavioral): fudge NOCHANGE broken"
fi
# case: Id guard (root Id=8e in the table)
echo 8388608 > "${GRT}/sys/block/xvda/xvda2/size"
sed -i 's|size=  8388608, Id=83|size=  8388608, Id=8e|' "${GRT}/state/dump-old"
gr_run
if grep -q 'REFUSING: root entry has Id=8e' "${GRT}/state/log" && [ ! -f "${GRT}/state/applied" ]; then
  t_pass "growroot(behavioral): non-83 partition type is REFUSED before any write"
else
  t_fail "growroot(behavioral): Id guard broken"
fi

# ---- (C) bash-3.2 safety of guest-side blocks ------------------------------
b32_re='\$\{[A-Za-z_][A-Za-z_0-9]*(,,|\^\^)|mapfile|readarray|declare -A|\|&'
for t in ks prov s1; do
  grep -v '^[[:space:]]*#' "${WORK}/${t}" > "${WORK}/${t}.code"
  if grep -Eq "${b32_re}" "${WORK}/${t}.code"; then
    t_fail "bash3.2: guest-side '${t}' uses a bash-4-only construct: $(grep -Eo "${b32_re}" "${WORK}/${t}.code" | head -1)"
  else
    t_pass "bash3.2: guest-side '${t}' is free of bash-4-only constructs (comment lines excluded)"
  fi
done

# ---- (D) OL5S1 executor: order + hard asserts ------------------------------
l_alias="$(grep -n 'alias scsi_hostadapter nvme' "${WORK}/s1" | head -1 | cut -d: -f1)"
l_defk="$(grep -n 'DEFAULTKERNEL=kernel-uek' "${WORK}/s1" | head -1 | cut -d: -f1)"
l_rpm="$(grep -n 'rpm -Uvh --replacepkgs' "${WORK}/s1" | head -1 | cut -d: -f1)"
# shellcheck disable=SC2016
l_src="$(grep -n 'cp -f "\$f" /usr/src/' "${WORK}/s1" | head -1 | cut -d: -f1)"
if [ -n "${l_alias}" ] && [ -n "${l_defk}" ] && [ -n "${l_rpm}" ] && [ -n "${l_src}" ] \
   && [ "${l_alias}" -lt "${l_defk}" ] && [ "${l_defk}" -lt "${l_rpm}" ] && [ "${l_rpm}" -lt "${l_src}" ]; then
  t_pass "s1: load-bearing order holds (modprobe aliases < DEFAULTKERNEL < rpm transaction < /usr/src staging)"
else
  t_fail "s1: load-bearing order broken (alias=${l_alias:-?} defk=${l_defk:-?} rpm=${l_rpm:-?} src=${l_src:-?})"
fi
assert_match "${s1}" 'alias eth0 ena' "s1: eth0->ena modprobe alias written"
assert_match "${s1}" 'alias scsi_hostadapter1 xen-blkfront' "s1: xen-blkfront alias (Xen-generation fallback path)"
assert_match "${s1}" 'edabeedb' "s1: RPM lead-magic verified per staged file before the transaction"
assert_match "${s1}" 'FATAL: no staged RPMs' "s1: empty RPM stage is a loud FATAL"
assert_match "${s1}" 'cpio -it 2>/dev/null \| grep -q .nvme\\\.ko' "s1: initrd content assert looks for nvme.ko"
assert_match "${s1}" 'mkinitrd --with=nvme --with=xen-blkfront -f' "s1: single mkinitrd remediation retry before the hard FATAL"
assert_match "${s1}" 'grub default entry does not boot el5uek' "s1: grub default->el5uek assert present"
assert_match "${s1}" 'rpm -q cloud-init' "s1: cloud-init install asserted"
assert_match "${s1}" 'an EMPTY src' "s1: empty src dir tolerated (legitimate under --skip-ena-driver + --skip-awscli)"

# ---- (E) provision.sh EL5 discipline ---------------------------------------
if grep -v '^[[:space:]]*#' "${WORK}/prov" | grep -q 'common::distr_cleanup'; then
  t_fail "prov: calls common::distr_cleanup (systemctl / /etc/yum/vars / \${EXCLUDE_DOCS^^} all break on EL5)"
else
  t_pass "prov: does NOT call common::distr_cleanup (EL5-safe self-contained cleanup)"
fi
assert_match "${prov}" 'DRACUT_CMD="/bin/false' "prov: DRACUT_CMD poisoned (any stray dracut reference fails loudly)"
assert_match "${prov}" 'PermitRootLogin' "prov: sed rewrites the PermitRootLogin directive"
assert_match "${prov}" '1 without-password/' "prov: policy value is 'without-password' (OpenSSH 4.3 has no prohibit-password; OL6/5.3 lesson class)"
# shellcheck disable=SC2016
assert_match "${prov}" '"\$sshd_bin" -t -f /etc/ssh/sshd_config' "prov: sshd -t invoked against the generated config"
assert_match "${prov}" 'rp_filter = 0' "prov: rp_filter=0 (EL5 2.6.18 has no loose mode '2')"
assert_match "${prov}" 'for service in kudzu rhnsd sendmail kdump mcstrans' "prov: EL5-era service disable set (kudzu et al.)"

# ---- (F) host-supply manifests ---------------------------------------------
sed -n '/local ol5_toolchain_rpms="/,/^perl.*"$/p' "${MAIN}" \
  | sed -e 's/^.*ol5_toolchain_rpms="//' -e 's/"$//' | grep -E '\.rpm$' | sort > "${WORK}/tc-builder"
sed -n '/^OL5_TOOLCHAIN_RPMS="/,/"$/p' "${MTX}" \
  | sed -e 's/^OL5_TOOLCHAIN_RPMS="//' -e 's/"$//' | grep -E '\.rpm$' | sort > "${WORK}/tc-matrix"
if [ -s "${WORK}/tc-builder" ] && diff -q "${WORK}/tc-builder" "${WORK}/tc-matrix" >/dev/null 2>&1; then
  t_pass "manifest: builder toolchain list is BYTE-IDENTICAL to the matrix's proven OL5_TOOLCHAIN_RPMS ($(wc -l < "${WORK}/tc-builder") RPMs)"
else
  t_fail "manifest: builder toolchain list diverged from the matrix's OL5_TOOLCHAIN_RPMS (rsyslog5-class drift risk)"
fi
n_epel="$(sed -n '/local ol5_epel_rpms="/,/^python26-libs.*"$/p' "${MAIN}" | grep -cE '\.rpm"?$' || true)"
assert_eq 10 "${n_epel}" "manifest: EPEL5 closure list carries exactly 10 frozen NVRs (9-RPM cloud-init closure + gdisk)"
assert_match "${main}" 'cloud-init-0\.6\.3-0\.12\.bzr532\.el5\.noarch\.rpm' "manifest: cloud-init 0.6.3 bzr532 NVR frozen"
assert_match "${main}" 'gdisk-0\.8\.4-1\.el5\.x86_64\.rpm' "manifest: gdisk staged as a TOOL (adjudicated; implementation uses fdisk)"
assert_match "${main}" 'kernel-uek-firmware' "manifest: kernel-uek-firmware staged with the kernel set"

# ---- (G) wrapper wiring -----------------------------------------------------
# parse_ol_version_from_iso: behavioral (extract the real function)
sed -n '/^parse_ol_version_from_iso() {/,/^}/p' "${MAIN}" > "${WORK}/parse.fn"
# shellcheck disable=SC1091
. "${WORK}/parse.fn"
OL_MAJOR_VERSION=""; OL_UPDATE_VERSION=""
if parse_ol_version_from_iso "https://mirrors.kernel.org/oracle/EL5/U11/x86_64/Enterprise-R5-U11-Server-x86_64-dvd.iso"; then
  assert_eq "5"  "${OL_MAJOR_VERSION}"  "parse: Enterprise-R5-U11 ISO -> major 5"
  assert_eq "11" "${OL_UPDATE_VERSION}" "parse: Enterprise-R5-U11 ISO -> update 11"
else
  t_fail "parse: Enterprise-R5-U11 ISO name not recognized"
  t_fail "parse: (update unreachable)"
fi
OL_MAJOR_VERSION=""; OL_UPDATE_VERSION=""
if parse_ol_version_from_iso "https://example.com/OracleLinux-R9-U5-x86_64-dvd.iso"; then
  assert_eq "9" "${OL_MAJOR_VERSION}" "parse: modern OracleLinux-R naming still parses (no OL5 regression)"
else
  t_fail "parse: modern OracleLinux-R naming broken by the OL5 branch"
fi
assert_match "${main}" 'IMDS_SUPPORT=v2\.0 is not supported for OL5' "wiring: IMDSv2-only rejected on OL5 (plain-IMDSv1 cloud-init 0.6.3)"
assert_match "${main}" 'SSM Agent install FORCED OFF on OL5' "wiring: SSM measured exclusion enforced (B.10/D.31; not a --skip default)"
assert_match "${main}" 'Nitro initramfs-drivers hook NOT injected on OL5' "wiring: NVM01 (dracut) explicitly skipped on OL5"
assert_match "${main}" '"\$\{OL_MAJOR_VERSION\}" != "5" && "\$\{OL_MAJOR_VERSION\}" != "6"' "wiring: awscli hook guard admits OL5 (pre-staged zip contract)"
assert_match "${main}" 'ol-aws-ami-builder OL5 disk-bus PATCH' "wiring: virt-install disk-bus patch (bus=virtio; EL5 has no virtio-scsi)"
assert_match "${main}" 'OL5 kickstart must contain NO .%end' "wiring: P3GATE OL5 zero-%end branch present"
assert_match "${main}" '5\) prof="RHEL5" ;;' "wiring: ksvalidator advisory maps OL5 -> RHEL5 profile"
vks="$(cat "${PROJ}/tests/validate-kickstart.sh")"
assert_match "${vks}" 'KNOWN MODERN-TOOL DIVERGENCE' "B-T4: the single modern-ksvalidator divergence (--nobase, valid in real 0.43.9) is normalized WITH its rationale"
assert_match "${vks}" 'nobase..%packages' "B-T4: exactly the --nobase construct is normalized before the RHEL5 validation (everything else verbatim)"
assert_match "${main}" "CLOUD_USER=\"ec2-user\"" "wiring: CLOUD_USER pinned to ec2-user on OL5"

# _p3_validate_ks: behavioral (the REAL extracted gate against the REAL ks)
sed -n '/^_p3_validate_ks() {/,/^}/p' "${MAIN}" > "${WORK}/gate.fn"
log_error() { :; }
# shellcheck disable=SC1091
. "${WORK}/gate.fn"
_p3_validate_ks "${WORK}/ks" 5; rc=$?
assert_eq 0 "${rc}" "p3gate(behavioral): the synthesized OL5 kickstart PASSES the real gate"
{ cat "${WORK}/ks"; printf '%%end\n'; } > "${WORK}/ks-mut1"
_p3_validate_ks "${WORK}/ks-mut1" 5; rc=$?
if [ "${rc}" -ne 0 ]; then
  t_pass "p3gate(behavioral): an injected '%end' FAILS the OL5 gate"
else
  t_fail "p3gate(behavioral): an injected '%end' slipped through the OL5 gate"
fi
grep -v '^sos$' "${WORK}/ks" > "${WORK}/ks-mut2"
_p3_validate_ks "${WORK}/ks-mut2" 5; rc=$?
if [ "${rc}" -ne 0 ]; then
  t_pass "p3gate(behavioral): a dropped 'sos' package FAILS the OL5 gate"
else
  t_fail "p3gate(behavioral): a dropped 'sos' package slipped through the OL5 gate"
fi

# ---- (H) env.properties.aws-ol5 --------------------------------------------
assert_match "${envf}" '^DISTR="ol5-slim"$' "env: DISTR=ol5-slim"
assert_match "${envf}" 'Enterprise-R5-U11-Server-x86_64-dvd\.iso' "env: kernel.org mirror ISO_URL (frozen terminal update)"
assert_match "${envf}" '8af2121088c7e6f5ebdb6d5900403240' "env: mirror MD5 recorded as the operator cross-check"
assert_match "${envf}" '^ISO_CHECKSUM="b098bda92990134ea3bc8052a43b314eaffe93790a4bf872ae555b5cb467d421"$' "env: the operator-measured SHA256 is baked (2026-07-19; mirror-MD5 cross-checked -- the wrapper's fail-fast on empty stays as the safety net)"
assert_match "${envf}" '^ROOT_FS="ext3"$' "env: ROOT_FS=ext3 (EL5 anaconda constraint)"
assert_match "${envf}" '^UPDATE_TO_LATEST="no"$' "env: UPDATE_TO_LATEST=no (no reachable in-guest repository)"
assert_match "${envf}" '^UEK_RELEASE="2"$' "env: UEK_RELEASE=2 (the only OL5 UEK line; in-box nvme)"
assert_match "${envf}" '^CLOUD_USER="ec2-user"$' "env: CLOUD_USER=ec2-user (0.6.3 cannot create users)"
assert_match "${envf}" '^SELINUX="permissive"$' "env: SELinux permissive with recorded rationale"
assert_match "${envf}" '^DISK_SIZE_GB="10"$' "env: 10 GB floor (host-staged set; growroot makes it a floor, not a ceiling)"

# env template vs synthesized distr env: the constraints must agree
assert_match "${envt}" '^ROOT_FS="ext3"$' "distr-env: ROOT_FS=ext3 matches the template"
assert_match "${envt}" '^UPDATE_TO_LATEST="no"$' "distr-env: UPDATE_TO_LATEST=no matches the template"
assert_match "${envt}" '^UEK_RELEASE=2$' "distr-env: UEK_RELEASE=2 matches the template"
assert_match "${envt}" 'readonly ORACLE_RELEASE=5' "distr-env: ORACLE_RELEASE=5"
assert_match "${envt}" "BOOT_LOCATION=\"isolinux\"" "distr-env: BOOT_LOCATION=isolinux (EL5 DVD layout)"

t_done
