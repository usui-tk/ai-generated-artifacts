#!/usr/bin/env bash
#
# install-ena-driver.sh
#
# Build and install a pinned Amazon ENA Linux kernel driver, so an OL image/
# instance is AWS-optimized (Nitro v4+ / ENAv3 capable). It is SELF-CONTAINED:
# it sets up the repos (EPEL) and installs every build dependency itself (gcc,
# make, dkms, and the matching kernel-uek-devel headers), so it can be run two
# ways:
#   1. Standalone, directly on a stock OL6/OL7 EC2 instance, to iterate on and
#      validate the driver build before any end-to-end image build.
#   2. From oracle-linux-image-tools provisioning, via a hook the wrapper
#      (build-ol-aws-ami.sh, Phase 3) appends to cloud/aws/provision.sh. It runs
#      by default; the wrapper's --skip-ena-driver switch removes the hook to
#      produce a pure (unmodified) OL AMI.
#
# Why a pinned version (not "latest"):
#   The ENA driver is a kernel module; newer releases progressively assume newer
#   kernels/toolchains. We pin the newest release that BUILDS on each target OS:
#     - OL6 -> ena_linux_2.9.1  (newest that builds on OL6/UEK4; >= 2.2.9 so
#              ENAv3 capable. The buildable window on the updated UEK4 kernel
#              4.1.12-124.48.6.el6uek is roughly [2.8.6, 2.9.1], validated on a
#              real Nitro instance: below ~2.8.6 the driver's kcompat redefines
#              page_ref_count (Oracle backported it into UEK4 >= 124.43.1; the
#              driver's guard is conditional on UEK detection -- see "Target
#              kernel"); at
#              2.10.0 the driver gained the ECC build-time API autodetect, which
#              false-positives on this old kernel + EL6 gcc 4.4.7 and pulls in
#              newer-kernel symbols absent here (pci_dev_id, irq_update_affinity_
#              hint, ethtool_puts, netif_napi_add_config), so 2.10.0+ fail to
#              compile. 2.9.1 is the last pre-ECC release -> the ceiling.)
#     - OL7 -> ena_linux_2.17.0 (newest release supporting RHEL7 confirmed as of
#              2026-06; RHEL7 remains in the driver's supported-distros list)
#   OL8+ ship a current in-distro ENA driver, so this script no-ops there.
#   Override per run with ENA_DRIVER_VERSION (single pin) for evaluation.
#
# Target kernel:
#   Standalone on a running instance -> the LIVE kernel (its /lib/modules dir
#   exists). Under a libguestfs appliance (provisioning) `uname -r` is the
#   APPLIANCE kernel with no modules dir in the guest, so we fall back to the
#   highest UEK under /lib/modules. The build always targets a specific kernel
#   via `dkms ... -k <kver>`. If the stock kernel's kernel-uek-devel has been
#   pruned from the repos, we install the latest kernel-uek + matching headers
#   and retarget to it (a guaranteed buildable pair).
#   The amzn-drivers Makefile ALSO derives IS_UEK / ENA_KERNEL_SUBVERSION_* from
#   `uname -r`; under the appliance that is the non-UEK appliance kernel, which
#   mis-fires the kcompat.h page_ref_count guard against a backported UEK4 kernel
#   (>= 124.43.1). For OL6 we patch that detection to read BUILD_KERNEL (the
#   DKMS target) -- see patch_ena_uek_detection() below.
#
# DKMS:
#   The driver is installed via DKMS (REMAKE_INITRD/AUTOINSTALL) so it is rebuilt
#   automatically across kernel upgrades. DKMS comes from EPEL:
#     - OL7 -> Oracle-provided EPEL (ol7_developer_EPEL)
#     - OL6 -> Fedora EPEL 6 archive (Oracle does not provide EPEL 6)
#   If DKMS is unavailable, fall back to a plain `make` build + depmod.
#
# Source: amzn/amzn-drivers (kernel/linux/ena). Apache-2.0 build instructions
# adapted; this script is original.
#
set -euo pipefail

# ---- pinned versions (overridable) -----------------------------------------
ENA_VERSION_OL6="${ENA_VERSION_OL6:-2.9.1}"
ENA_VERSION_OL7="${ENA_VERSION_OL7:-2.17.0}"
EPEL6_ARCHIVE_BASEURL="${EPEL6_ARCHIVE_BASEURL:-https://archives.fedoraproject.org/pub/archive/epel/6/x86_64/}"

# ---- execution-environment switch (default = production) -------------------
# ENA_BUILDTEST=1 selects the container compile-test environment (kernel-less;
# dkms build only -- no install/boot). Default 0 = the production path (VM-build
# provisioning, or a standalone live OL instance), unchanged. The test-mode
# branches are added incrementally; see SPEC A.7 / handoff B.1.9 Part 3.
ENA_BUILDTEST="${ENA_BUILDTEST:-0}"
# INSECURE_TLS=1 drops TLS peer verification for the test-mode network commands
# only (MITM dev proxy / EL6 NSS trust gaps). Default 0 = verification on.
# Production never reads this beyond the default; it is consulted only inside the
# ENA_BUILDTEST branches.
INSECURE_TLS="${INSECURE_TLS:-0}"

# Execution-environment segment, computed once from the switch and injected by
# every [ena-driver] emitter below, so output is tagged by environment WITHOUT
# changing call sites. Production (ENA_BUILDTEST=0) -> empty -> the historical
# tags are emitted unchanged; the container compile-test (=1) inserts a
# [buildtest] segment after the script tag. The environment segment is
# orthogonal to the message-kind segment ([stage]/[ERROR]).
_env_tag() { if [[ "${ENA_BUILDTEST}" == "1" ]]; then printf '[buildtest]'; fi; }
log() { echo "[ena-driver]$(_env_tag) $*"; }
# Greppable build-stage breadcrumb. Distinct from log() so the host wrapper (and
# a human reading a failed build) can pick out the phase boundaries. NOTE: the
# guest provisioning output is swallowed by virt-customize on a SUCCESSFUL build
# (see dump_build_diag) -- these breadcrumbs surface on the failure path (where
# they pin which sub-step broke) and in the preserved make.log context, not as a
# live host signal. Live host-side progress comes from the wrapper heartbeat.
stage() { echo "[ena-driver]$(_env_tag)[stage] $*"; }
die() { echo "[ena-driver]$(_env_tag)[ERROR] $*" >&2; exit 1; }

# On a failed build, surface the DKMS diagnostics to stderr so the actual
# compiler error is captured in the parent build log. This matters because
# oracle-linux-image-tools (libguestfs virt-customize) only echoes a guest
# provisioning script's output to the host when the script FAILS; on success it
# is silent. Without this, a DKMS module-build failure leaves only the opaque
# "Bad return status for module build" line and an in-guest make.log path that
# the operator (or a downstream user filing a report) never gets to see. Emits
# `dkms status` and every make.log found under the module's DKMS tree, each line
# prefixed so it stays greppable. Best-effort: never the cause of a new failure.
dump_build_diag() {
  local ml pfx; pfx="[ena-driver]$(_env_tag)[ERROR]"
  echo "${pfx} ---- build diagnostics (ENA ${ena_version:-?}, kernel ${kver:-?}) ----" >&2
  if command -v dkms >/dev/null 2>&1; then
    echo "${pfx} dkms status:" >&2
    dkms status 2>&1 | sed "s/^/${pfx}   /" >&2 || true
  fi
  while IFS= read -r ml; do
    [[ -n "${ml}" ]] || continue
    echo "${pfx} ---- ${ml} ----" >&2
    sed "s/^/${pfx}   /" "${ml}" >&2 || true
  done < <(find "/var/lib/dkms/amzn-drivers/${ena_version:-}" -name 'make.log' 2>/dev/null || true)
  echo "${pfx} ---- end build diagnostics ----" >&2
}

# On a SUCCESSFUL build the guest provisioning output is swallowed by
# virt-customize (see dump_build_diag), so the DKMS make.log -- the only record
# of what the compile actually did -- would be lost. Copy it to a stable path
# that ships inside the produced AMI, so it can be inspected post-hoc on a
# launched instance. Best-effort: never the cause of a new failure. (On a FAILED
# build, dump_build_diag already surfaces the same make.log to the host log.)
record_make_log() {
  local dest="/var/log/ol-aws-ami-builder-ena-make.log" ml
  ml="$(find "/var/lib/dkms/amzn-drivers/${ena_version:-}" -name 'make.log' 2>/dev/null | head -1 || true)"
  if [[ -n "${ml}" && -f "${ml}" ]]; then
    mkdir -p "$(dirname "${dest}")" 2>/dev/null || true
    if cp -f "${ml}" "${dest}" 2>/dev/null; then
      stage "preserved DKMS make.log -> ${dest} (ships in the AMI for post-hoc inspection)"
    else
      log "[make.log] could not copy ${ml} -> ${dest}"
    fi
  else
    log "[make.log] no DKMS make.log under /var/lib/dkms/amzn-drivers/${ena_version:-} (nothing to preserve)"
  fi
}

# Highest /lib/modules entry matching a shell glob (by version sort), or "".
highest_modules_dir() {
  local pattern="$1" best="" d bn
  for d in ${pattern}; do
    [[ -d "${d}" ]] || continue
    bn="$(basename "${d}")"
    if [[ -z "${best}" || "$(printf '%s\n%s\n' "${best}" "${bn}" | sort -V | tail -n1)" == "${bn}" ]]; then
      best="${bn}"
    fi
  done
  printf '%s' "${best}"
}

# ---- detect Oracle Linux major version -------------------------------------
osmajor=""
if [[ -r /etc/oracle-release ]]; then
  osmajor="$(grep -oE 'release [0-9]+' /etc/oracle-release 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)"
fi
if [[ -z "${osmajor}" && -r /etc/os-release ]]; then
  # /etc/os-release exists only at runtime on the target host; treat as empty
  # for the static lint (deterministic regardless of the lint host).
  # shellcheck source=/dev/null
  osmajor="$(. /etc/os-release 2>/dev/null; echo "${VERSION_ID%%.*}")"
fi
[[ -n "${osmajor}" ]] || die "cannot determine Oracle Linux major version"
log "Oracle Linux major version: ${osmajor}"

case "${osmajor}" in
  6) ena_version="${ENA_DRIVER_VERSION:-${ENA_VERSION_OL6}}" ;;
  7) ena_version="${ENA_DRIVER_VERSION:-${ENA_VERSION_OL7}}" ;;
  *) log "OL${osmajor} ships a current in-distro ENA driver; no rebuild needed. Skipping."; exit 0 ;;
esac
log "Target ENA driver version: ${ena_version}"

# ---- ENA_BUILDTEST: provision a kernel into the disposable container -------
# A container is kernel-less (no running kernel, no /lib/modules tree), so the
# production kernel detection below cannot work. The test container is throwaway,
# so install a full kernel-uek + its headers up front: that creates
# /lib/modules/<kver>/ (+ the build symlink), after which the production path
# (kver detection, header check, dkms build/install, verify) runs unchanged.
# Plain test commands; sslverify is dropped only at INSECURE_TLS=1 (e.g. a MITM
# dev proxy). Production never enters this block.
if [[ "${ENA_BUILDTEST}" == "1" ]]; then
  log "provisioning kernel-uek + build deps into the container (disposable)"
  # Enable the shipped (disabled) EPEL so the production setup_epel below finds
  # it already enabled and early-returns (no second epel-archive repo), and the
  # build's dkms resolves from it.
  sed -i '/^\[epel\]/,/^\[/ s/^enabled=0/enabled=1/' /etc/yum.repos.d/epel.repo
  if [[ "${INSECURE_TLS}" == "1" ]]; then
    yum -y --setopt=sslverify=false --enablerepo=ol6_UEKR4 \
      install kernel-uek kernel-uek-devel gcc make tar findutils dkms \
      || die "ENA_BUILDTEST: failed to provision kernel-uek + build deps"
  else
    yum -y --enablerepo=ol6_UEKR4 \
      install kernel-uek kernel-uek-devel gcc make tar findutils dkms \
      || die "ENA_BUILDTEST: failed to provision kernel-uek + build deps"
  fi
fi

# ---- detect target kernel --------------------------------------------------
# Standalone on a running OL instance: target the LIVE kernel (its modules dir
# exists), so the freshly built module can be loaded/validated immediately.
# In oracle-linux-image-tools provisioning the script runs under a libguestfs
# appliance whose `uname -r` is NOT the guest's kernel and has no modules dir in
# the guest fs, so we fall back to the highest UEK under /lib/modules.
kver="${ENA_DRIVER_KVER:-}"
if [[ -z "${kver}" ]]; then
  runk="$(uname -r 2>/dev/null || true)"
  if [[ -n "${runk}" && -d "/lib/modules/${runk}/kernel" ]]; then
    kver="${runk}"
  fi
fi
if [[ -z "${kver}" ]]; then
  kver="$(highest_modules_dir '/lib/modules/*uek*/')"
fi
if [[ -z "${kver}" ]]; then
  kver="$(highest_modules_dir '/lib/modules/*/')"
fi
[[ -n "${kver}" ]] || die "cannot determine target kernel under /lib/modules"
[[ -d "/lib/modules/${kver}" ]] || die "kernel modules dir /lib/modules/${kver} not found"
log "Target kernel: ${kver}"

# ---- idempotency: skip if the pinned version is already installed ----------
existing_ko="$(find "/lib/modules/${kver}" -type f -name 'ena.ko*' 2>/dev/null | grep -E '/updates/|/extra/' | head -1 || true)"
if [[ -n "${existing_ko}" ]]; then
  cur="$(modinfo -F version "${existing_ko}" 2>/dev/null | head -1 || true)"
  if [[ -n "${cur}" && "${cur}" == "${ena_version}"* ]]; then
    log "ENA ${cur} already installed for ${kver}; nothing to do."
    exit 0
  fi
fi

# ---- kernel devel package (UEK vs RHCK) ------------------------------------
develpkg="kernel-uek-devel-${kver}"
if [[ "${kver}" != *uek* ]]; then
  develpkg="kernel-devel-${kver}"
fi

# ---- enable EPEL so dkms is installable ------------------------------------
setup_epel() {
  if yum repolist enabled 2>/dev/null | grep -qiE 'epel'; then
    log "EPEL already enabled"
    return 0
  fi
  case "${osmajor}" in
    7)
      # Oracle-provided EPEL for OL7
      yum install -y oracle-epel-release-el7 2>/dev/null || true
      if command -v yum-config-manager >/dev/null 2>&1; then
        yum-config-manager --enable ol7_developer_EPEL >/dev/null 2>&1 || true
      fi
      ;;
    6)
      # Oracle does NOT provide EPEL 6; point at the Fedora archive directly.
      cat > /etc/yum.repos.d/epel-archive.repo <<EOF
[epel-archive]
name=Extra Packages for Enterprise Linux 6 (archive)
baseurl=${EPEL6_ARCHIVE_BASEURL}
enabled=1
gpgcheck=0
EOF
      ;;
  esac
}

# ---- install build prerequisites -------------------------------------------
# Ensure kernel-uek-devel headers exist for the target kernel. The stock OL ISO
# ships an older kernel-uek whose -devel may have been pruned from the repos
# ("No package kernel-uek-devel-<ver> available"); yum does not fail on a missing
# package, so DKMS then aborts with "kernel headers ... cannot be found". We (1)
# enable the UEK repo and try the exact -devel; (2) if the headers still are not
# present, install the latest kernel-uek + matching -devel and retarget to it
# (always a matched, buildable pair). Self-contained: no external pre-setup.
ensure_kernel_devel() {
  local -a yk=(-y)
  case "${osmajor}" in
    6) yk+=("--enablerepo=*UEKR4*") ;;
    7) yk+=("--enablerepo=*UEKR6*") ;;
  esac
  yum "${yk[@]}" install "kernel-uek-devel-${kver}" 2>/dev/null || true
  if [[ -e "/lib/modules/${kver}/build" ]]; then
    return 0
  fi
  log "kernel-uek-devel for ${kver} not available; installing the latest kernel-uek + headers and retargeting"
  yum "${yk[@]}" install kernel-uek kernel-uek-devel 2>/dev/null \
    || yum "${yk[@]}" update kernel-uek kernel-uek-devel 2>/dev/null || true
  local newk; newk="$(highest_modules_dir '/lib/modules/*uek*/')"
  if [[ -n "${newk}" && "${newk}" != "${kver}" ]]; then
    log "retargeting kernel: ${kver} -> ${newk}"
    kver="${newk}"; develpkg="kernel-uek-devel-${kver}"
  fi
  yum "${yk[@]}" install "kernel-uek-devel-${kver}" 2>/dev/null || true
  [[ -e "/lib/modules/${kver}/build" ]]
}

stage "installing build prerequisites (gcc, make, kernel headers)"
log "Installing build prerequisites (gcc, make, kernel headers)"
yum install -y gcc make tar findutils || die "failed to install gcc/make/tar"
if [[ "${kver}" == *uek* ]]; then
  stage "resolving kernel-uek-devel headers for ${kver}"
  ensure_kernel_devel || die "could not obtain kernel-uek-devel headers for ${kver} (enable the UEK repo / update the kernel and retry)"
else
  yum install -y "${develpkg}" || die "failed to install ${develpkg}"
  [[ -e "/lib/modules/${kver}/build" ]] || die "kernel headers for ${kver} not present after install"
fi

use_dkms=1
stage "enabling EPEL + installing dkms"
setup_epel
if ! yum install -y dkms; then
  log "DKMS not installable; falling back to a plain make build (no auto-rebuild on kernel upgrade)"
  use_dkms=0
fi

# ---- fetch the pinned amzn-drivers source tarball --------------------------
src_tgz="/usr/src/ena_linux_${ena_version}.tar.gz"
src_dir="/usr/src/amzn-drivers-${ena_version}"
url="https://github.com/amzn/amzn-drivers/archive/refs/tags/ena_linux_${ena_version}.tar.gz"
stage "downloading amzn-drivers ${ena_version} source"
log "Downloading ${url}"
rm -rf "${src_dir}"
if command -v curl >/dev/null 2>&1; then
  if [[ "${ENA_BUILDTEST}" == "1" && "${INSECURE_TLS}" == "1" ]]; then
    curl -fsSL -k "${url}" -o "${src_tgz}" || die "download failed: ${url}"
  else
    curl -fsSL "${url}" -o "${src_tgz}" || die "download failed: ${url}"
  fi
elif command -v wget >/dev/null 2>&1; then
  wget -q -O "${src_tgz}" "${url}" || die "download failed: ${url}"
else
  die "neither curl nor wget is available to download the driver source"
fi
tar -xzf "${src_tgz}" -C /usr/src || die "failed to extract ${src_tgz}"
rm -f "${src_tgz}"
[[ -d "/usr/src/amzn-drivers-ena_linux_${ena_version}" ]] \
  || die "unexpected archive layout for ena_linux_${ena_version}"
mv "/usr/src/amzn-drivers-ena_linux_${ena_version}" "${src_dir}"

# ---- retarget the amzn-drivers Makefile's UEK detection (OL6 cross-kernel) --
# The ENA Makefile derives IS_UEK and ENA_KERNEL_SUBVERSION_* from `uname -r`
# (the RUNNING kernel). Under the libguestfs provisioning appliance `uname -r`
# is the non-UEK appliance kernel, not the DKMS target, so neither macro is set;
# the kcompat.h page_ref_count guard then mis-fires and redefines a symbol the
# backported UEK4 kernel (>= 4.1.12-124.43.1, e.g. -124.48.6) already provides
# -> "redefinition of 'page_ref_count'". The build already passes the target
# kernel as BUILD_KERNEL, so point the detection at it instead. OL6-only
# (per-OS isolation): OL7/UEKR6 is a >= 4.6 kernel, so the page_ref_count block
# is compiled out regardless and its Makefile is left untouched.
patch_ena_uek_detection() {
  local mk="${src_dir}/kernel/linux/ena/Makefile" S='$' sentinel
  sentinel="echo \"${S}(BUILD_KERNEL)\" | grep uek"
  [[ -f "${mk}" ]] || die "amzn-drivers Makefile not found at ${mk}"
  if grep -Fq "${sentinel}" "${mk}"; then
    log "[ena-uek-detect] Makefile UEK detection already retargeted to BUILD_KERNEL; skipping"
    return 0
  fi
  cp -f "${mk}" "${mk}.uek-detect.bak"
  # Read the DKMS target kernel (BUILD_KERNEL), not the running kernel. The
  # `BUILD_KERNEL ?= $(shell uname -r)` default line carries no pipe, so the
  # two pipe-anchored substitutions below leave it untouched.
  sed -i \
    -e "s#uname -r | grep uek#echo \"${S}(BUILD_KERNEL)\" | grep uek#" \
    -e "s#uname -r | sed#echo \"${S}(BUILD_KERNEL)\" | sed#" \
    "${mk}"
  grep -Fq "${sentinel}" "${mk}" \
    || die "[ena-uek-detect] Makefile UEK-detection patch did not apply (upstream layout changed?)"
  log "[ena-uek-detect] retargeted ENA Makefile UEK detection to the DKMS target kernel (backup ${mk}.uek-detect.bak)"
}
if [[ "${osmajor}" == "6" ]]; then
  patch_ena_uek_detection
fi

# ---- report the in-box ENA driver BEFORE the self-build replaces it --------
# The self-build is otherwise silent about what it supersedes. Capture the stock
# in-tree ENA module's identity for the TARGET kernel now, so the before/after
# delta is on record. modinfo's `version` field is frequently empty for an
# in-tree module (e.g. OL7/OL8); fall back to srcversion and always show the
# module file so the line is never uninformative.
report_inbox_ena() {
  command -v modinfo >/dev/null 2>&1 || { log "[in-box ENA] modinfo unavailable; skipping pre-build report"; return 0; }
  local ver src fn
  ver="$(modinfo -k "${kver}" -F version ena 2>/dev/null | head -1)"
  src="$(modinfo -k "${kver}" -F srcversion ena 2>/dev/null | head -1)"
  fn="$(modinfo -k "${kver}" -F filename ena 2>/dev/null | head -1)"
  log "[in-box ENA] before self-build: version=${ver:-<none; in-tree, no version field>} srcversion=${src:-?} file=${fn:-<not found>}"
}

# ---- build & install --------------------------------------------------------
build_install_dkms() {
  cat > "${src_dir}/dkms.conf" <<EOF
PACKAGE_NAME="ena"
PACKAGE_VERSION="${ena_version}"
CLEAN="make -C kernel/linux/ena clean"
MAKE="make -C kernel/linux/ena/ BUILD_KERNEL=\${kernelver}"
BUILT_MODULE_NAME[0]="ena"
BUILT_MODULE_LOCATION="kernel/linux/ena"
DEST_MODULE_LOCATION[0]="/updates"
DEST_MODULE_NAME[0]="ena"
REMAKE_INITRD="yes"
AUTOINSTALL="yes"
EOF
  dkms remove  -m amzn-drivers -v "${ena_version}" --all 2>/dev/null || true
  stage "dkms add (amzn-drivers ${ena_version})"
  dkms add     -m amzn-drivers -v "${ena_version}"
  stage "dkms build for ${kver} -- long, quiet in-guest compile (typically a few minutes)"
  dkms build   -m amzn-drivers -v "${ena_version}" -k "${kver}"
  stage "dkms install for ${kver}"
  dkms install -m amzn-drivers -v "${ena_version}" -k "${kver}" --force
  stage "dkms build + install complete for ${kver}"
}

build_install_plain() {
  make -C "${src_dir}/kernel/linux/ena" BUILD_KERNEL="${kver}"
  local dest="/lib/modules/${kver}/updates"
  mkdir -p "${dest}"
  cp -f "${src_dir}/kernel/linux/ena/ena.ko" "${dest}/ena.ko"
  depmod -a "${kver}"
}

if [[ "${use_dkms}" -eq 1 ]]; then
  log "Building & installing ENA ${ena_version} via DKMS for ${kver}"
  report_inbox_ena
  build_install_dkms || { dump_build_diag; die "DKMS build/install failed (compiler output dumped above; in-guest make.log)"; }
  record_make_log
else
  log "Building & installing ENA ${ena_version} via plain make for ${kver}"
  report_inbox_ena
  build_install_plain || { dump_build_diag; die "plain make build/install failed (build output above)"; }
fi

# ---- regenerate initramfs for the target kernel ----------------------------
if command -v dracut >/dev/null 2>&1; then
  log "Regenerating initramfs for ${kver}"
  dracut -f "/boot/initramfs-${kver}.img" "${kver}" || die "dracut failed for ${kver}"
elif command -v mkinitrd >/dev/null 2>&1; then
  log "Regenerating initrd for ${kver}"
  mkinitrd -f "/boot/initramfs-${kver}.img" "${kver}" || die "mkinitrd failed for ${kver}"
else
  log "WARNING: no dracut/mkinitrd found; initramfs not regenerated"
fi

# ---- verify -----------------------------------------------------------------
ko="$(find "/lib/modules/${kver}" -type f -name 'ena.ko*' 2>/dev/null | grep -E '/updates/|/extra/' | head -1 || true)"
[[ -n "${ko}" ]] || ko="$(find "/lib/modules/${kver}" -type f -name 'ena.ko*' 2>/dev/null | head -1 || true)"
[[ -n "${ko}" ]] || die "ena.ko not found under /lib/modules/${kver} after install"
newver="$(modinfo -F version "${ko}" 2>/dev/null | head -1 || true)"
log "Installed ENA driver: ${ko} (version ${newver:-unknown})"
if [[ "${newver}" != "${ena_version}"* ]]; then
  log "WARNING: installed version '${newver}' does not match pinned '${ena_version}'"
fi

# ---- AMI hygiene: drop stale persistent-net rules --------------------------
rm -f /etc/udev/rules.d/70-persistent-net.rules 2>/dev/null || true

log "ENA driver build complete (OL${osmajor}, kernel ${kver}, version ${ena_version})"
