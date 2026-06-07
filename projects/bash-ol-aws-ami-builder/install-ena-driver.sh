#!/usr/bin/env bash
#
# install-ena-driver.sh
#
# Build and install a pinned Amazon ENA Linux kernel driver INSIDE the guest
# image, so the produced AMI is AWS-optimized (Nitro v4+ / ENAv3 capable). It is
# invoked from the AWS-cloud provisioning step of oracle-linux-image-tools by a
# hook that the wrapper (build-ol-aws-ami.sh, Phase 3) appends to
# cloud/aws/provision.sh. It runs by default; the wrapper's --skip-ena-driver
# switch removes the hook entirely to produce a pure (unmodified) OL AMI.
#
# Why a pinned version (not "latest"):
#   The ENA driver is a kernel module; newer releases progressively assume newer
#   kernels/toolchains. We pin the newest release that supports each target OS:
#     - OL6 -> ena_linux_2.5.0  (validated on EL6 userland; >= 2.2.9 so ENAv3
#              capable; "supports older kernels correctly")
#     - OL7 -> ena_linux_2.17.0 (newest release supporting RHEL7 confirmed as of
#              2026-06; RHEL7 remains in the driver's supported-distros list)
#   OL8+ ship a current in-distro ENA driver, so this script no-ops there.
#   Override per run with ENA_DRIVER_VERSION (single pin) for evaluation.
#
# Target kernel:
#   Provisioning runs under a libguestfs appliance, so `uname -r` is the
#   APPLIANCE kernel, not the image's installed UEK. We therefore detect the
#   target kernel from /lib/modules (the installed UEK) and build explicitly
#   against it with `dkms ... -k <kver>`.
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
ENA_VERSION_OL6="${ENA_VERSION_OL6:-2.5.0}"
ENA_VERSION_OL7="${ENA_VERSION_OL7:-2.17.0}"
EPEL6_ARCHIVE_BASEURL="${EPEL6_ARCHIVE_BASEURL:-https://archives.fedoraproject.org/pub/archive/epel/6/x86_64/}"

log() { echo "[ena-driver] $*"; }
die() { echo "[ena-driver][ERROR] $*" >&2; exit 1; }

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

# ---- detect target kernel (installed UEK, not the appliance's uname -r) -----
kver="${ENA_DRIVER_KVER:-}"
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
log "Installing build prerequisites (${develpkg}, gcc, make)"
yum install -y gcc make tar findutils "${develpkg}" \
  || die "failed to install build prerequisites (${develpkg})"

use_dkms=1
setup_epel
if ! yum install -y dkms; then
  log "DKMS not installable; falling back to a plain make build (no auto-rebuild on kernel upgrade)"
  use_dkms=0
fi

# ---- fetch the pinned amzn-drivers source tarball --------------------------
src_tgz="/usr/src/ena_linux_${ena_version}.tar.gz"
src_dir="/usr/src/amzn-drivers-${ena_version}"
url="https://github.com/amzn/amzn-drivers/archive/refs/tags/ena_linux_${ena_version}.tar.gz"
log "Downloading ${url}"
rm -rf "${src_dir}"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "${url}" -o "${src_tgz}" || die "download failed: ${url}"
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
  dkms add     -m amzn-drivers -v "${ena_version}"
  dkms build   -m amzn-drivers -v "${ena_version}" -k "${kver}"
  dkms install -m amzn-drivers -v "${ena_version}" -k "${kver}" --force
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
  build_install_dkms || die "DKMS build/install failed"
else
  log "Building & installing ENA ${ena_version} via plain make for ${kver}"
  build_install_plain || die "plain make build/install failed"
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
