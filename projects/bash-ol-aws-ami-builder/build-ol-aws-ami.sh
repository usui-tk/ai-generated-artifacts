#!/usr/bin/env bash
#==============================================================================
# build-ol-aws-ami.sh
#
# ----- Purpose ----------------------------------------------------------------
# Wrapper script that builds an AWS AMI for Oracle Linux (x86_64) using the
# official Oracle oracle-linux-image-tools project. The full pipeline (host
# provisioning -> VM build -> S3 upload -> AMI registration) is automated.
#
# Supported Oracle Linux versions: 8 / 9 / 10 (x86_64).
# Experimental support: 7 (x86_64; deprecated upstream, verification use only).
# The actual version, ISO URL, and AMI naming are driven from the env
# properties file specified with --env. See env.properties.aws-ol10 (or
# env.properties.aws-ol9 / env.properties.aws-ol8 / env.properties.aws-ol7)
# for working examples.
#
# Note on OL7:
#   The upstream oracle-linux-image-tools project explicitly rejects OL7 for
#   the AWS cloud target via a hard-coded check in cloud/aws/image-scripts.sh.
#   This wrapper applies a runtime patch in Phase 3 (after cloning the
#   upstream repository) to allow OL7 builds. Use at your own risk; OL7
#   Premier Support ended on 2024-12-31.
#
# Upstream reference:
#   https://github.com/oracle/oracle-linux/tree/main/oracle-linux-image-tools
#
# ----- Prerequisites ----------------------------------------------------------
# Runtime:
#   * Bash 4+ (for `${var,,}`, associative arrays, etc.)
#   * Linux build host with CPU virtualization extensions exposed (vmx/svm).
#     Either bare metal, or an EC2 C8i / M8i / R8i instance with nested
#     virtualization enabled (see AWS docs link in the README).
#   * Architecture: x86_64 host required for x86_64 AMI builds.
#   * Free disk space: 20 GB minimum, 30 GB recommended at WORKSPACE.
#
# Permissions:
#   * Local: sudo privileges (for KVM/libvirt/setfacl in Phase 1 / Phase 2).
#     Running as root is supported but emits a warning.
#   * AWS:   s3:CreateBucket, s3:PutObject, s3:HeadBucket,
#            ec2:ImportSnapshot, ec2:DescribeImportSnapshotTasks,
#            ec2:RegisterImage, ec2:CreateTags, ec2:DescribeImages,
#            iam:CreateRole/PutRolePolicy (for the one-time vmimport setup).
#
# Required CLIs (installed automatically by Phase 1 if missing):
#   * libvirt / qemu-kvm / virt-install / libguestfs (guestfs-tools)
#   * osinfo-db / osinfo-db-tools, acl, git, curl, aws-cli v2
#
# ----- Usage examples ---------------------------------------------------------
#   # Oracle Linux 10 Update 1
#   cp env.properties.aws-ol10 env.properties.local
#   vi env.properties.local        # edit WORKSPACE / S3_BUCKET / AWS_REGION
#   ./build-ol-aws-ami.sh --env env.properties.local
#
#   # Oracle Linux 9 Update 7
#   cp env.properties.aws-ol9 env.properties.local
#   ./build-ol-aws-ami.sh --env env.properties.local
#
#   # Build the VMDK locally without uploading to AWS
#   ./build-ol-aws-ami.sh --env env.properties.local --build-only
#
# ----- Pipeline phases --------------------------------------------------------
#   Phase 0:   Preflight checks (KVM support, required commands, free disk)
#   Phase 1:   Provision the build host (KVM/libvirt/virt-install/libguestfs)
#   Phase 2:   Grant the qemu user traverse access to WORKSPACE (ACL)
#   Phase 3:   Clone the oracle/oracle-linux repository
#   Phase 4:   Resolve ISO checksum and generate env.properties
#   Phase 5:   Run oracle-linux-image-tools to produce a VMDK
#   Phase 6:   Upload the VMDK to S3
#   Phase 7:   Convert the VMDK to an EBS snapshot via import-snapshot
#   Phase 8:   Register the snapshot as an AMI
#
# ----- Options ----------------------------------------------------------------
#   --env <file>          : Path to the environment properties file (required)
#   --skip-prereq         : Skip Phase 1 when build host packages are present
#   --skip-aws-import     : Skip Phases 6-8 (build VMDK only)
#   --build-only          : Run through Phase 5 only
#   -h | --help           : Show this help
#
# ----- Known limitations ------------------------------------------------------
#   * aarch64 (Graviton) AMIs are NOT supported. oracle-linux-image-tools
#     only targets x86_64 for the AWS cloud, and AWS nested virtualization
#     is not available on Graviton instance types.
#   * Cross-architecture builds (e.g. building aarch64 on x86_64) are not
#     possible with libvirt-driven virt-install.
#   * Oracle's build-image.sh enforces BOOT_MODE=bios for AWS, so the AMI
#     is registered as legacy-bios. NitroTPM / UEFI Secure Boot cannot be
#     enabled on these AMIs. (Functional on every Nitro instance type.)
#   * AWS import-snapshot has a per-account concurrency limit (default 5).
#     For very high-volume CI usage, request a quota increase.
#
# ----- AI generation info -----------------------------------------------------
#   AI tool: Anthropic Claude (Sonnet 4.5) for OL8/9/10 base, Claude (Opus 4.7)
#            for the OL7 experimental support layer added in 2026-05.
#   Generated / iteratively refined: 2026-05
#   Verified by the author against real OL8 / OL9 / OL10 builds on AWS.
#   OL7 support has been verified only at the patch-mechanism level
#   (sed substitution, syntax integrity); end-to-end OL7 AMI builds
#   have NOT been validated by the author. Use at your own risk.
#==============================================================================

set -euo pipefail

readonly OL_REPO_URL="https://github.com/oracle/oracle-linux.git"
readonly OL_TOOLS_SUBDIR="oracle-linux-image-tools"

# Default ISO information.
# DEFAULT_ISO_URL is consumed in load_env() as the fallback when the user
# has not set ISO_URL in their env.properties. The default points to the
# latest OL10 release; users targeting OL9, OL8, or OL7 must set ISO_URL in
# their env file (see env.properties.aws-ol9 / env.properties.aws-ol8 /
# env.properties.aws-ol7).
readonly DEFAULT_ISO_URL="https://yum.oracle.com/ISOS/OracleLinux/OL10/u1/x86_64/OracleLinux-R10-U1-x86_64-dvd.iso"

# Execution mode flags
SKIP_PREREQ=0
SKIP_AWS_IMPORT=0
BUILD_ONLY=0
ENV_FILE=""

#------------------------------------------------------------------------------
# Logging helpers
#------------------------------------------------------------------------------
log_info()  { echo -e "\033[1;34m[INFO]\033[0m  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m  $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }
log_step()  { echo -e "\n\033[1;32m========== $* ==========\033[0m\n"; }

die() { log_error "$*"; exit 1; }

#------------------------------------------------------------------------------
# Argument parsing
#------------------------------------------------------------------------------
usage() {
  sed -n '/^# build-ol-aws-ami.sh/,/^#==============/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env)              ENV_FILE="$2";       shift 2 ;;
      --skip-prereq)      SKIP_PREREQ=1;       shift ;;
      --skip-aws-import)  SKIP_AWS_IMPORT=1;   shift ;;
      --build-only)       BUILD_ONLY=1;        shift ;;
      -h|--help)          usage 0 ;;
      *)                  log_error "Unknown option: $1"; usage 1 ;;
    esac
  done

  [[ -z "${ENV_FILE}" ]] && die "--env option is required"
  [[ ! -f "${ENV_FILE}" ]] && die "Environment properties file not found: ${ENV_FILE}"

  # Explicit return 0 to avoid the "&& die" pattern leaking a non-zero exit
  # status when both checks pass. With set -e in the caller, returning a
  # non-zero status from this function would silently abort the script.
  return 0
}

#------------------------------------------------------------------------------
# Parse the OL major and update version from an ISO URL or filename.
#
# Examples:
#   OracleLinux-R10-U1-x86_64-dvd.iso         -> major=10, update=1
#   OracleLinux-R9-U7-x86_64-dvd.iso          -> major=9,  update=7
#   OracleLinux-R8-U10-x86_64-dvd.iso         -> major=8,  update=10
#   OracleLinux-R7-U9-Server-x86_64-dvd.iso   -> major=7,  update=9
#
# Sets the global variables OL_MAJOR_VERSION and OL_UPDATE_VERSION.
# Returns 1 if no match.
#------------------------------------------------------------------------------
parse_ol_version_from_iso() {
  local iso_ref="$1"
  local iso_filename
  iso_filename=$(basename "${iso_ref}")
  if [[ "${iso_filename}" =~ OracleLinux-R([0-9]+)-U([0-9]+) ]]; then
    OL_MAJOR_VERSION="${BASH_REMATCH[1]}"
    OL_UPDATE_VERSION="${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

#------------------------------------------------------------------------------
# Load environment properties and validate required keys
#------------------------------------------------------------------------------
load_env() {
  log_step "Loading environment properties: ${ENV_FILE}"

  # shellcheck source=/dev/null
  source "${ENV_FILE}"

  # Required parameters (build)
  : "${WORKSPACE:?WORKSPACE is not defined}"
  : "${ISO_URL:=${DEFAULT_ISO_URL}}"
  : "${CLOUD:=aws}"

  # Auto-detect Oracle Linux version from the ISO URL.
  # If the user supplied a custom ISO_URL that doesn't follow Oracle's naming
  # convention, they can override OL_MAJOR_VERSION / OL_UPDATE_VERSION in
  # env.properties.local explicitly.
  if [[ -z "${OL_MAJOR_VERSION:-}" || -z "${OL_UPDATE_VERSION:-}" ]]; then
    if parse_ol_version_from_iso "${ISO_URL}"; then
      log_info "Detected Oracle Linux version from ISO URL: ${OL_MAJOR_VERSION}.${OL_UPDATE_VERSION}"
    else
      die "Could not parse the Oracle Linux version from ISO_URL='${ISO_URL}'.
       Set OL_MAJOR_VERSION and OL_UPDATE_VERSION explicitly in your env file."
    fi
  fi

  # Emit a prominent advisory when the user targets OL7. OL7 is deprecated
  # upstream (cloud/aws/image-scripts.sh explicitly rejects it) and Premier
  # Support ended on 2024-12-31. This wrapper patches the upstream block in
  # Phase 3, but operators should understand the support implications before
  # putting the resulting AMI into production.
  if [[ "${OL_MAJOR_VERSION}" -eq 7 ]]; then
    log_warn "============================================================================"
    log_warn " Oracle Linux 7 target selected (OL${OL_MAJOR_VERSION}U${OL_UPDATE_VERSION})."
    log_warn ""
    log_warn "  * OL7 Premier Support ended on 2024-12-31."
    log_warn "  * Upstream oracle-linux-image-tools EXCLUDES OL7 from the AWS cloud"
    log_warn "    target; build-ol-aws-ami.sh applies a runtime patch in Phase 3."
    log_warn "  * OL7's UEK R6 bundles kernel modules (incl. amazon/ena) in"
    log_warn "    kernel-uek; the kernel-uek-modules install is skipped in Phase 3"
    log_warn "    (that separate package exists only from UEK R7 / OL8+)."
    log_warn "  * OL7 only supports x86_64 (no aarch64) and bios boot (no UEFI)."
    log_warn "  * Do NOT use the resulting AMI for production workloads requiring"
    log_warn "    Oracle Premier Support. Intended for verification, learning, or"
    log_warn "    legacy migration scenarios."
    log_warn "============================================================================"
  fi

  # Emit a prominent advisory when the user targets OL6. OL6 is even more
  # severely deprecated than OL7: upstream oracle-linux-image-tools does
  # NOT ship a distr/ol6-slim/ directory at all (the AWS cloud target's
  # OL8+ guard also rejects it), and Oracle's ELS for OL6 ended in 2024.
  # build-ol-aws-ami.sh works around both gaps in Phase 3 (generating
  # distr/ol6-slim/ at runtime and applying an extra patch to
  # cloud/aws/provision.sh).
  if [[ "${OL_MAJOR_VERSION}" -eq 6 ]]; then
    log_warn "============================================================================"
    log_warn " Oracle Linux 6 target selected (OL${OL_MAJOR_VERSION}U${OL_UPDATE_VERSION})."
    log_warn ""
    log_warn "  * OL6 Premier Support ended on 2021-03-31."
    log_warn "  * OL6 Extended Life Support (ELS) ended in 2024."
    log_warn "  * NO security updates have been published for OL6 since 2024."
    log_warn "  * Upstream oracle-linux-image-tools does NOT ship distr/ol6-slim/;"
    log_warn "    build-ol-aws-ami.sh generates this directory at runtime in Phase 3."
    log_warn "  * In addition to the OL7 image-scripts.sh patch, an extra patch"
    log_warn "    is applied to cloud/aws/provision.sh to skip kernel-uek-modules"
    log_warn "    installation (this package does not exist in OL6/UEKR4)."
    log_warn "  * OL6 only supports x86_64 (no aarch64), bios boot (no UEFI),"
    log_warn "    and UEK Release 4 (the only kernel with ENA/NVMe drivers)."
    log_warn "  * AWS VM Import/Export marks OL6 as EOL; this wrapper uses"
    log_warn "    import-snapshot + register-image to bypass that policy."
    log_warn ""
    log_warn "  This target is intended ONLY for verification, learning, or"
    log_warn "  legacy migration scenarios. NEVER use the resulting AMI for"
    log_warn "  production workloads."
    log_warn "============================================================================"
  fi

  # DISTR slug used by oracle-linux-image-tools.
  # Convention: ol{major}-slim (e.g. ol10-slim, ol9-slim, ol8-slim, ol7-slim).
  : "${DISTR:=ol${OL_MAJOR_VERSION}-slim}"

  # Resolve workspace to an absolute path
  WORKSPACE=$(realpath -m "${WORKSPACE}")
  mkdir -p "${WORKSPACE}"

  # Required parameters for AWS import (unless skipped)
  if [[ ${SKIP_AWS_IMPORT} -eq 0 && ${BUILD_ONLY} -eq 0 ]]; then
    : "${S3_BUCKET:?S3_BUCKET is not defined}"
    # Resolve AWS_REGION dynamically when the env file leaves it empty.
    # See resolve_aws_region() for the IMDSv2 -> IMDSv1 -> "ap-northeast-1"
    # fallback chain. Sets AWS_REGION_SOURCE for downstream logging.
    resolve_aws_region
    : "${AWS_REGION:?AWS_REGION could not be resolved (this should not happen)}"
    : "${AMI_NAME:=OracleLinux-${OL_MAJOR_VERSION}-U${OL_UPDATE_VERSION}-x86_64-$(date +%Y%m%d-%H%M)}"
    : "${AMI_DESCRIPTION:=Oracle Linux ${OL_MAJOR_VERSION} Update ${OL_UPDATE_VERSION} (x86_64) custom AMI built via oracle-linux-image-tools}"
    # AMI registration boot mode.
    # IMPORTANT: oracle-linux-image-tools currently produces BIOS-only images
    # for the AWS target (BOOT_MODE_BUILD must be 'bios'), so the AMI must
    # be registered as legacy-bios. uefi-preferred would require an ESP in
    # the disk image, which the upstream tool does not generate for AWS.
    : "${BOOT_MODE:=legacy-bios}"
    : "${VMIMPORT_ROLE_NAME:=vmimport}"
  fi

  # Defaults for optional parameters
  : "${WORK_REPO_DIR:=${WORKSPACE}/oracle-linux}"
  : "${BUILD_NUMBER:=0}"
  : "${SETUP_SWAP:=No}"
  : "${SELINUX:=enforcing}"
  : "${ROOT_FS:=xfs}"
  : "${DISK_SIZE_GB:=10}"
  : "${SERIAL_CONSOLE_RUNTIME:=Yes}"
  # Install-time serial console (upstream SERIAL_CONSOLE). Default "no"
  # (headless): upstream detects install completion via the domain lifecycle
  # and applies its own install timeout -- the historically reliable path.
  # When "yes", upstream instead waits on `virsh console`, which does NOT
  # cleanly return when the install VM ends (reboot/poweroff/teardown) and was
  # observed to hang build-image.sh until the watchdog even on otherwise
  # successful builds; it also only streams useful output on old anaconda
  # (OL6/7), not on OL8+ (tmux-based). Treat "yes" as a debug-only opt-in for
  # watching the OL6/7 install phase, and expect to kill the VM. DISTINCT from
  # SERIAL_CONSOLE_RUNTIME above (which configures the *generated image's*
  # console). See SPEC A.7 / D.18.
  : "${SERIAL_CONSOLE:=no}"
  # Phase-5 build watchdog, in minutes. An outer safety bound on the upstream
  # build-image.sh run (in addition to upstream's own install timeout). On
  # expiry the wrapper reaps the transient build VM and aborts. Generous
  # default so a normal 20-60 min build never trips it; raise for slow hosts.
  : "${BUILD_TIMEOUT_MIN:=120}"
  # Build-time boot mode.
  # IMPORTANT: Oracle's build-image.sh enforces BOOT_MODE=bios for AWS.
  # See cloud/aws/image-scripts.sh in oracle-linux-image-tools.
  : "${BOOT_MODE_BUILD:=bios}"

  log_info "OL version         = ${OL_MAJOR_VERSION}.${OL_UPDATE_VERSION}"
  log_info "WORKSPACE          = ${WORKSPACE}"
  log_info "DISTR              = ${DISTR}"
  log_info "CLOUD              = ${CLOUD}"
  log_info "ISO_URL            = ${ISO_URL}"
  log_info "WORK_REPO_DIR      = ${WORK_REPO_DIR}"
  if [[ ${SKIP_AWS_IMPORT} -eq 0 && ${BUILD_ONLY} -eq 0 ]]; then
    log_info "AWS_REGION         = ${AWS_REGION} (source: ${AWS_REGION_SOURCE:-unknown})"
    log_info "S3_BUCKET          = ${S3_BUCKET}"
    log_info "AMI_NAME           = ${AMI_NAME}"
    log_info "BOOT_MODE          = ${BOOT_MODE}"
  fi

  # Validate BOOT_MODE_BUILD: oracle-linux-image-tools restricts AWS to bios.
  if [[ "${CLOUD,,}" == "aws" && "${BOOT_MODE_BUILD,,}" != "bios" ]]; then
    log_error "BOOT_MODE_BUILD='${BOOT_MODE_BUILD}' is not supported for CLOUD=aws."
    log_error "  oracle-linux-image-tools only accepts BOOT_MODE=bios for AWS targets."
    log_error "  Set BOOT_MODE_BUILD=\"bios\" in env.properties.local (or remove the line"
    log_error "  to use the default)."
    die "Invalid BOOT_MODE_BUILD for AWS"
  fi

  # Cross-check the AMI registration boot mode.
  # When the build produces a BIOS-only image, registering with uefi or
  # uefi-preferred would fail at boot on UEFI-capable instances.
  if [[ ${SKIP_AWS_IMPORT} -eq 0 && ${BUILD_ONLY} -eq 0 ]]; then
    if [[ "${BOOT_MODE_BUILD,,}" == "bios" && "${BOOT_MODE,,}" != "legacy-bios" ]]; then
      log_warn "BOOT_MODE_BUILD=bios produces a BIOS-only image, but AMI BOOT_MODE='${BOOT_MODE}'."
      log_warn "  This will likely fail to boot on UEFI-capable instances."
      log_warn "  Recommended setting: BOOT_MODE=\"legacy-bios\""
    fi
  fi
}

#------------------------------------------------------------------------------
# Detect the runtime environment (EC2 instance type, ID, region)
#
# Uses IMDSv2 first (token-based; preferred). When IMDSv2 fails — typically
# on legacy instances where the IMDS service is configured with HttpTokens
# disabled, or in network-restricted setups where the PUT call cannot return
# a token — falls back to IMDSv1 (token-less GET) for the same metadata
# paths. Each curl call is capped at 2 seconds so non-EC2 hosts time out
# quickly.
#
# Idempotent: subsequent calls return the cached IS_EC2 / EC2_REGION values
# without re-querying the metadata service.
#
# Globals (set):
#   IS_EC2 (0/1), EC2_INSTANCE_TYPE, EC2_INSTANCE_ID, EC2_REGION,
#   EC2_IMDS_VERSION ("v2" / "v1" / "" when not on EC2)
#------------------------------------------------------------------------------
detect_ec2_environment() {
  # Idempotent guard: return cached result on repeat calls.
  if [[ "${EC2_IMDS_DETECTED:-0}" -eq 1 ]]; then
    return 0
  fi
  EC2_IMDS_DETECTED=1

  IS_EC2=0
  EC2_INSTANCE_TYPE=""
  EC2_INSTANCE_ID=""
  EC2_REGION=""
  EC2_IMDS_VERSION=""

  local token

  # ---- IMDSv2 attempt -----------------------------------------------------
  token=$(curl -fsS --max-time 2 \
    -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)

  if [[ -n "${token}" ]]; then
    IS_EC2=1
    EC2_IMDS_VERSION="v2"
    EC2_INSTANCE_TYPE=$(curl -fsS --max-time 2 \
      -H "X-aws-ec2-metadata-token: ${token}" \
      http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo "")
    EC2_INSTANCE_ID=$(curl -fsS --max-time 2 \
      -H "X-aws-ec2-metadata-token: ${token}" \
      http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "")
    EC2_REGION=$(curl -fsS --max-time 2 \
      -H "X-aws-ec2-metadata-token: ${token}" \
      http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "")
    return 0
  fi

  # ---- IMDSv1 fallback ----------------------------------------------------
  # Attempt a single token-less GET. This succeeds when the IMDS endpoint
  # is reachable AND the instance has HttpTokens=optional (the EC2 default
  # prior to mid-2024). When HttpTokens=required, IMDSv1 returns 401 and
  # this branch leaves IS_EC2=0.
  local v1_region
  v1_region=$(curl -fsS --max-time 2 \
    http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "")

  if [[ -n "${v1_region}" ]]; then
    IS_EC2=1
    EC2_IMDS_VERSION="v1"
    EC2_REGION="${v1_region}"
    EC2_INSTANCE_TYPE=$(curl -fsS --max-time 2 \
      http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo "")
    EC2_INSTANCE_ID=$(curl -fsS --max-time 2 \
      http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "")
  fi
}

#------------------------------------------------------------------------------
# Resolve AWS_REGION when the env file leaves it empty.
#
# Resolution order (matches the documented behaviour in env.properties.aws-ol*):
#   1. Explicit AWS_REGION value from the env file (no-op; returns immediately).
#   2. EC2 Instance Metadata Service:
#      a. IMDSv2 (token-based; preferred)
#      b. IMDSv1 (legacy token-less GET; used only when IMDSv2 fails)
#   3. Fallback constant "ap-northeast-1" (covers non-EC2 build hosts).
#
# Globals (read):  AWS_REGION  (may be empty)
# Globals (set):   AWS_REGION  (always non-empty on return)
#                  AWS_REGION_SOURCE  ("env" | "imdsv2" | "imdsv1" | "fallback")
#------------------------------------------------------------------------------
resolve_aws_region() {
  if [[ -n "${AWS_REGION:-}" ]]; then
    AWS_REGION_SOURCE="env"
    return 0
  fi

  detect_ec2_environment

  if [[ ${IS_EC2} -eq 1 && -n "${EC2_REGION}" ]]; then
    AWS_REGION="${EC2_REGION}"
    AWS_REGION_SOURCE="imds${EC2_IMDS_VERSION}"
    return 0
  fi

  AWS_REGION="ap-northeast-1"
  AWS_REGION_SOURCE="fallback"
}

#------------------------------------------------------------------------------
# Print detailed guidance when KVM is unavailable on an EC2 host, then exit.
#
# Three scenarios are handled:
#   (A) C8i / M8i / R8i family -> nested virtualization just needs to be enabled
#   (B) Other (legacy) Nitro family -> switch to C8i/M8i/R8i or use .metal
#   (C) .metal family -> likely a configuration issue (kvm module not loaded)
#------------------------------------------------------------------------------
guide_ec2_kvm_issue() {
  local instance_type="$1"

  echo
  log_error "=========================================="
  log_error "  CPU virtualization extensions are NOT exposed on this EC2 host"
  log_error "=========================================="
  log_info "  Detected instance type: ${instance_type:-unknown}"
  log_info "  Detected region:        ${EC2_REGION:-unknown}"
  echo

  # Resolve the instance family
  # e.g. m8i.xlarge -> m8i, c8i-flex.large -> c8i-flex
  local family
  family=$(echo "${instance_type}" | sed -E 's/\.[^.]+$//')

  # IMPORTANT: detect bare-metal instances against the FULL instance_type,
  # not against `family` — the family extraction strips the trailing
  # ".metal" suffix, so 'c5n.metal' becomes 'c5n' and would otherwise match
  # the catch-all "*) Case B" branch incorrectly.
  if [[ "${instance_type}" == *.metal || "${instance_type}" == *.metal-* ]]; then
    log_warn "[Case C] ${instance_type} is bare metal but /dev/kvm is unavailable."
    echo
    log_info "Action:"
    log_info "  1) Check whether the kvm module is loaded"
    log_info "       lsmod | grep kvm"
    log_info "  2) If not loaded, load it manually"
    log_info "       sudo modprobe kvm-intel    # for Intel CPUs"
    log_info "       sudo modprobe kvm-amd      # for AMD CPUs"
    log_info "  3) Verify /dev/kvm permissions"
    log_info "       ls -l /dev/kvm"
  else
    case "${family}" in
      c8i|c8i-flex|c8id|m8i|m8i-flex|m8id|r8i|r8i-flex|r8id)
        log_warn "[Case A] ${family} supports nested virtualization, but the feature is currently disabled."
        echo
        log_info "Action: enable nested virtualization on this instance."
        log_info ""
        log_info "  # 1) Stop the instance"
        log_info "  aws ec2 stop-instances --instance-ids ${EC2_INSTANCE_ID} --region ${EC2_REGION}"
        log_info "  aws ec2 wait instance-stopped --instance-ids ${EC2_INSTANCE_ID} --region ${EC2_REGION}"
        log_info ""
        log_info "  # 2) Enable nested virtualization"
        log_info "  aws ec2 modify-instance-cpu-options \\"
        log_info "    --instance-id ${EC2_INSTANCE_ID} --region ${EC2_REGION} \\"
        log_info "    --nested-virtualization enabled"
        log_info ""
        log_info "  # 3) Start the instance and re-run this script"
        log_info "  aws ec2 start-instances --instance-ids ${EC2_INSTANCE_ID} --region ${EC2_REGION}"
        log_info ""
        log_info "  Reference: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/amazon-ec2-nested-virtualization.html"
        ;;
      *)
        log_warn "[Case B] ${family} does NOT support nested virtualization."
        echo
        log_info "Action: switch to one of the following options."
        log_info ""
        log_info "  Option 1 (recommended): Use a nested-virtualization-capable C8i / M8i / R8i instance"
        log_info "    - Example: m8i.xlarge (4 vCPU / 16 GB / approx \$0.30/h)"
        log_info "    - Same price as the standard instance; no extra charge"
        log_info "    - Sufficient spec to host the build VM"
        log_info ""
        log_info "  Option 2: Switch to a bare-metal instance"
        log_info "    - Example: c5n.metal (approx \$5/h; acceptable for short builds)"
        log_info ""
        log_info "  List of nested-virt-capable instance types in this region:"
        log_info "    aws ec2 describe-instance-types \\"
        log_info "      --filters \"Name=processor-info.supported-features,Values=nested-virtualization\" \\"
        log_info "      --query \"sort(InstanceTypes[].InstanceType)\" \\"
        log_info "      --region ${EC2_REGION:-ap-northeast-1}"
        ;;
    esac
  fi

  echo
  log_error "Build cannot proceed. Apply the action above and re-run this script."
  exit 1
}

#------------------------------------------------------------------------------
# Phase 0: Preflight checks
#------------------------------------------------------------------------------
phase0_preflight_checks() {
  log_step "Phase 0: Preflight checks"

  # Warn (but do not abort) if running as root.
  # The upstream oracle-linux-image-tools project recommends running as a
  # non-privileged user, but in environments such as freshly-launched EC2
  # instances where only root is available, allow execution to continue.
  if [[ $EUID -eq 0 ]]; then
    log_warn "Running as root. oracle-linux-image-tools is designed to run as an unprivileged user."
    log_warn "  Continuing anyway because the user explicitly opted in."
    log_warn "  If KVM or libvirt permission errors occur in later phases, switch to a regular user with sudo."
  fi

  # Detect EC2 vs. on-prem
  detect_ec2_environment
  if [[ ${IS_EC2} -eq 1 ]]; then
    log_info "EC2 environment detected: ${EC2_INSTANCE_TYPE} (${EC2_INSTANCE_ID}) in ${EC2_REGION}"
  else
    log_info "Non-EC2 environment (assuming on-premises KVM host or similar)"
  fi

  # Check for CPU virtualization extensions
  if ! grep -E -q '(vmx|svm)' /proc/cpuinfo; then
    if [[ ${IS_EC2} -eq 1 ]]; then
      # On EC2, give targeted guidance based on the instance type
      guide_ec2_kvm_issue "${EC2_INSTANCE_TYPE}"
    else
      die "CPU virtualization extensions (Intel VT-x / AMD-V) are not available. Run on a bare-metal host or an environment with nested virtualization enabled."
    fi
  fi
  log_info "CPU virtualization extensions: enabled (vmx/svm detected)"

  # Check /dev/kvm
  if [[ ! -e /dev/kvm ]]; then
    log_warn "/dev/kvm is missing. It is expected to be loaded by Phase 1."
    log_warn "  If it is still missing afterwards, run:"
    log_warn "    sudo modprobe kvm-intel    # for Intel CPUs"
    log_warn "    sudo modprobe kvm-amd      # for AMD CPUs"
  else
    log_info "/dev/kvm: available"
  fi

  # Check required commands (those installed in Phase 1 are excluded)
  local required_cmds=("git" "curl" "sudo" "realpath" "findmnt" "df")
  for cmd in "${required_cmds[@]}"; do
    command -v "${cmd}" >/dev/null 2>&1 || die "Required command not found: ${cmd}"
  done

  # Check AWS CLI (skipped if --skip-aws-import)
  if [[ ${SKIP_AWS_IMPORT} -eq 0 && ${BUILD_ONLY} -eq 0 ]]; then
    command -v aws >/dev/null 2>&1 || die "aws CLI not found. Install AWS CLI v2."
    aws sts get-caller-identity >/dev/null 2>&1 || die "AWS CLI authentication failed. Verify 'aws configure'."
  fi

  # Check workspace free space and underlying filesystem characteristics.
  # We read these via stat/findmnt because the WORKSPACE may live on tmpfs
  # (typical for /tmp on modern Linux) which has size and persistence
  # implications worth surfacing before the build starts.
  local avail_gb fstype mount_opts
  avail_gb=$(df -BG "${WORKSPACE}" | awk 'NR==2 {print $4}' | tr -d 'G')
  fstype=$(findmnt -n -o FSTYPE --target "${WORKSPACE}" 2>/dev/null || echo "unknown")
  mount_opts=$(findmnt -n -o OPTIONS --target "${WORKSPACE}" 2>/dev/null || echo "")

  log_info "Workspace path:       ${WORKSPACE}"
  log_info "Workspace filesystem: ${fstype}"
  log_info "Workspace free space: ${avail_gb}GB"

  # Warn about insufficient free space (build needs ~20GB; 30GB recommended).
  if [[ ${avail_gb} -lt 20 ]]; then
    log_error "Workspace has only ${avail_gb}GB free. The build needs at least 20GB."
    log_error "  Move WORKSPACE to a larger location, e.g. /var/tmp/ol10-build-ws"
    log_error "  (which is typically disk-backed and persistent across reboots)."
    die "Insufficient free space at WORKSPACE."
  elif [[ ${avail_gb} -lt 30 ]]; then
    log_warn "Workspace has only ${avail_gb}GB free. 30GB or more is recommended."
  fi

  # tmpfs caveats: RAM-backed, size-capped, cleared on reboot.
  if [[ "${fstype}" == "tmpfs" ]]; then
    log_warn "Workspace is on tmpfs (RAM-backed):"
    log_warn "  * Size is typically capped at 50% of system RAM. Verify ${avail_gb}GB is enough."
    log_warn "  * Contents are cleared on reboot. A reboot mid-build will lose all progress."
    log_warn "  * If you encounter ENOSPC errors during Phase 5, switch to /var/tmp:"
    log_warn "      WORKSPACE=\"/var/tmp/ol10-build-ws\""
  fi

  # noexec is fatal: oracle-linux-image-tools runs scripts inside WORKSPACE.
  if [[ ",${mount_opts}," == *",noexec,"* ]]; then
    log_error "The filesystem hosting ${WORKSPACE} is mounted with 'noexec'."
    log_error "  oracle-linux-image-tools executes scripts in the workspace; this will fail."
    log_error "  Move WORKSPACE to a filesystem without noexec, e.g. /var/tmp/ol10-build-ws"
    log_error "  Current mount options: ${mount_opts}"
    die "WORKSPACE filesystem has noexec; cannot proceed."
  fi

  log_info "Preflight checks completed"
}

#------------------------------------------------------------------------------
# Phase 1: Provision the build host
#------------------------------------------------------------------------------
phase1_install_prerequisites() {
  if [[ ${SKIP_PREREQ} -eq 1 ]]; then
    log_step "Phase 1: Skipping prerequisite package installation"
    return 0
  fi

  log_step "Phase 1: Provisioning build host (KVM / libvirt / virt-install / libguestfs)"

  # Detect the host distro id + version from /etc/os-release. ID/VERSION_ID
  # identify the concrete release; ID_LIKE is only a fallback used to produce a
  # clearer refusal message for unlisted derivatives.
  local host_id="" host_like="" host_ver=""
  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    host_id=$(. /etc/os-release && echo "${ID:-}")
    # shellcheck source=/dev/null
    host_like=$(. /etc/os-release && echo "${ID_LIKE:-}")
    # shellcheck source=/dev/null
    host_ver=$(. /etc/os-release && echo "${VERSION_ID:-}")
  fi
  # Major version: strip any minor component (24.04 -> 24, 9.5 -> 9, 10 -> 10).
  local host_major="${host_ver%%.*}"

  # This builder installs the KVM + libguestfs superset the whole pipeline
  # needs (not just the minimal "install KVM" set) and supports only the
  # latest TWO generations of each build host OS. Older releases are
  # reference-only and refused here. See SPEC B.6 "Build host package matrix".
  local pkg_mgr="" qemu_pkg="qemu-kvm"

  case "${host_id}" in
    ol|rhel|rocky|almalinux|centos)
      # RHEL family, including CentOS Stream. Supported: 10, 9.
      pkg_mgr="dnf"
      case "${host_major}" in
        10|9) : ;;
        *) die "Unsupported ${host_id} ${host_ver}: only the latest two generations (10, 9) are supported; older releases are reference-only (SPEC B.6)." ;;
      esac
      ;;
    fedora)
      pkg_mgr="dnf"
      case "${host_major}" in
        44|43) : ;;
        *) die "Unsupported Fedora ${host_ver}: only the latest two generations (44, 43) are supported (SPEC B.6)." ;;
      esac
      ;;
    ubuntu)
      pkg_mgr="apt"
      # Supported LTS: 26.04, 24.04. The qemu package was renamed: 26.04 drops
      # the qemu-kvm transitional package in favour of qemu-system.
      case "${host_ver}" in
        26.04) qemu_pkg="qemu-system" ;;
        24.04) qemu_pkg="qemu-kvm" ;;
        *) die "Unsupported Ubuntu ${host_ver}: only the latest two LTS generations (26.04, 24.04) are supported; 22.04 and older are reference-only (SPEC B.6)." ;;
      esac
      ;;
    debian)
      pkg_mgr="apt"
      case "${host_major}" in
        13|12) qemu_pkg="qemu-kvm" ;;
        *) die "Unsupported Debian ${host_ver}: only the latest two generations (13, 12) are supported; 11 and older are reference-only (SPEC B.6)." ;;
      esac
      ;;
    *)
      case "${host_like}" in
        *rhel*|*fedora*) die "Unsupported RHEL-family host (ID=${host_id}, ID_LIKE=${host_like}). Supported: OL/RHEL/Rocky/Alma/CentOS Stream 10 or 9, Fedora 44 or 43 (SPEC B.6)." ;;
        *debian*|*ubuntu*) die "Unsupported Debian-family host (ID=${host_id}, ID_LIKE=${host_like}). Supported: Ubuntu 26.04/24.04, Debian 13/12 (SPEC B.6)." ;;
        *) die "Unsupported build host OS (ID=${host_id}, ID_LIKE=${host_like}, VERSION_ID=${host_ver}); see SPEC B.6 for the supported matrix." ;;
      esac
      ;;
  esac

  case "${pkg_mgr}" in
    dnf)
      log_info "Build host: ${host_id} ${host_ver} (dnf family). Installing KVM/libguestfs packages."
      sudo dnf install -y \
        qemu-kvm libvirt libvirt-client \
        libvirt-daemon-config-network libvirt-daemon-driver-qemu \
        virt-install libguestfs guestfs-tools \
        edk2-ovmf \
        libosinfo osinfo-db osinfo-db-tools \
        acl \
        || die "Failed to install build host packages via dnf"
      ;;
    apt)
      log_info "Build host: ${host_id} ${host_ver} (apt family). Installing KVM/libguestfs packages (qemu: ${qemu_pkg})."
      sudo apt-get update -y
      sudo apt-get install -y \
        "${qemu_pkg}" libvirt-daemon-system libvirt-daemon libvirt-clients \
        virtinst libguestfs-tools \
        ovmf \
        libosinfo-bin osinfo-db osinfo-db-tools \
        acl \
        || die "Failed to install build host packages via apt"
      ;;
  esac

  # Enable and start the libvirt daemon.
  # Modern RHEL 9+ / Fedora 35+ / Debian 12+ ship modular libvirt daemons
  # (virtqemud, virtnetworkd, virtstoraged, ...) instead of monolithic
  # libvirtd. We try the legacy unit first (still present on most distros
  # as a compatibility wrapper), then fall back to modular daemons.
  if systemctl list-unit-files libvirtd.service >/dev/null 2>&1 \
     && systemctl list-unit-files libvirtd.service 2>/dev/null | grep -q '^libvirtd\.service'; then
    sudo systemctl enable --now libvirtd
    log_info "Enabled monolithic libvirtd.service"
  elif systemctl list-unit-files virtqemud.service 2>/dev/null | grep -q '^virtqemud\.service'; then
    sudo systemctl enable --now virtqemud.socket virtnetworkd.socket virtstoraged.socket 2>/dev/null \
      || log_warn "Some modular libvirt sockets could not be enabled (may not exist on this distro)"
    log_info "Enabled modular libvirt daemons (virtqemud / virtnetworkd / virtstoraged)"
  else
    log_warn "Neither libvirtd.service nor virtqemud.service was found."
    log_warn "  You may need to start the libvirt daemon manually before Phase 5."
  fi

  # Add the running user to libvirt and kvm groups (re-login may be required)
  if getent group libvirt >/dev/null 2>&1; then
    sudo usermod -aG libvirt "${USER}" || true
  fi
  if getent group kvm >/dev/null 2>&1; then
    sudo usermod -aG kvm "${USER}" || true
  fi

  log_info "Build host provisioning completed"
  log_warn "If you were just added to the libvirt group, log out and back in for it to take effect."
}

#------------------------------------------------------------------------------
# Detect the system's qemu/libvirt run-as username.
#
# When libvirt runs in system mode (qemu:///system, the default that Oracle's
# image-tools relies on), the spawned qemu process runs as a non-root user.
# Different distros use different names:
#   * RHEL / Fedora / Oracle Linux : "qemu"
#   * Debian / Ubuntu              : "libvirt-qemu"
#
# Returns the username on stdout, or 1 if neither user exists.
#------------------------------------------------------------------------------
detect_qemu_user() {
  local candidates=("qemu" "libvirt-qemu")
  local user
  for user in "${candidates[@]}"; do
    if id "${user}" >/dev/null 2>&1; then
      echo "${user}"
      return 0
    fi
  done
  return 1
}

#------------------------------------------------------------------------------
# Phase 2: Ensure the workspace path is reachable by the qemu user.
#
# libvirt in system mode launches QEMU as a non-root user. When WORKSPACE
# lives under /root (or any directory without world-execute bit), the qemu
# user cannot traverse the path and virt-install fails with:
#   "Cannot access storage file ... (as uid:107, gid:107): Permission denied"
#
# Fix: walk every parent directory from WORKSPACE up to '/' and grant the
# qemu user a traverse-only ACL (u:qemu:x). This is more granular and safer
# than chmod o+x on /root.
#------------------------------------------------------------------------------
phase2_grant_qemu_access() {
  log_step "Phase 2: Ensuring qemu user can access the workspace"

  local qemu_user
  qemu_user=$(detect_qemu_user) || {
    log_warn "Could not detect a qemu/libvirt-qemu user."
    log_warn "  Phase 1 may not have completed successfully, or libvirt is not installed."
    log_warn "  Skipping ACL setup. Phase 5 will likely fail."
    return 0
  }
  log_info "Detected qemu user: ${qemu_user}"

  if ! command -v setfacl >/dev/null 2>&1; then
    log_warn "setfacl not found. Install the 'acl' package:"
    log_warn "  sudo dnf install acl       # RHEL/OL/Fedora"
    log_warn "  sudo apt-get install acl   # Debian/Ubuntu"
    log_warn "Continuing without ACL setup; Phase 5 may fail."
    return 0
  fi

  log_info "Granting traverse-only ACL (u:${qemu_user}:x) to each parent of WORKSPACE."
  log_info "  This allows qemu to reach files under ${WORKSPACE} without exposing"
  log_info "  contents to the world. Existing permissions are preserved."

  # Walk up the path, applying setfacl to each existing directory.
  local path="${WORKSPACE}"
  local fixed_count=0
  local skipped_count=0
  while [[ "${path}" != "/" && -n "${path}" ]]; do
    if [[ -d "${path}" ]]; then
      # Test whether the qemu user can already traverse it
      if sudo -u "${qemu_user}" test -x "${path}" 2>/dev/null; then
        skipped_count=$((skipped_count + 1))
      else
        log_info "  -> setfacl -m u:${qemu_user}:x ${path}"
        if sudo setfacl -m "u:${qemu_user}:x" "${path}" 2>/dev/null; then
          fixed_count=$((fixed_count + 1))
        else
          log_warn "    failed (filesystem may not support ACLs)"
        fi
      fi
    fi
    path=$(dirname "${path}")
  done

  log_info "ACL setup: ${fixed_count} directories updated, ${skipped_count} already accessible"

  # Final verification: can the qemu user actually read a file in WORKSPACE?
  local probe="${WORKSPACE}/.qemu-access-probe"
  : > "${probe}"
  if sudo -u "${qemu_user}" test -r "${probe}" 2>/dev/null; then
    log_info "Verified: qemu user '${qemu_user}' can access ${WORKSPACE}"
    rm -f "${probe}"
  else
    rm -f "${probe}"
    log_error "Verification failed: qemu user '${qemu_user}' still cannot read ${WORKSPACE}"
    log_error "  Possible reasons:"
    log_error "    * The filesystem does not support POSIX ACLs (e.g. tmpfs without acl mount option)"
    log_error "    * SELinux is blocking access (check: sudo ausearch -m avc -ts recent)"
    log_error "  Workaround: relocate WORKSPACE to a path under /var/lib or /var/tmp:"
    log_error "    WORKSPACE=\"/var/lib/ol10-build-ws\""
    die "Workspace is not accessible by the qemu user."
  fi
}

#------------------------------------------------------------------------------
#------------------------------------------------------------------------------
phase3_clone_repository() {
  log_step "Phase 3: Cloning oracle/oracle-linux repository"

  if [[ -d "${WORK_REPO_DIR}/.git" ]]; then
    log_info "Updating existing clone: ${WORK_REPO_DIR}"
    git -C "${WORK_REPO_DIR}" fetch --depth=1 origin main
    git -C "${WORK_REPO_DIR}" reset --hard origin/main
  else
    log_info "Cloning repository: ${OL_REPO_URL}"
    git clone --depth=1 "${OL_REPO_URL}" "${WORK_REPO_DIR}"
  fi

  [[ -d "${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}" ]] \
    || die "Directory ${OL_TOOLS_SUBDIR} not found in the clone"

  # SELinux relabel resilience patch (host-OS-independent; applies to every OL
  # target). See SPEC Part D "SELinux relabel fails on a non-SELinux build
  # host" and B.6.
  #
  # Background:
  #   In Phase 5, upstream bin/build-image.sh relabels the guest's non-root
  #   filesystems with an explicit loop:
  #       guestfish --remote selinux-relabel <file_contexts> <mount>
  #   That call needs the host libguestfs to provide the 'selinuxrelabel'
  #   optgroup. On Debian/Ubuntu build hosts the optgroup is COMPILED OUT of
  #   the libguestfs build (it is a build-time capability of guestfsd, NOT a
  #   runtime probe for setfiles -- installing policycoreutils/selinux-utils on
  #   the host does NOT enable it), so the call aborts the build with:
  #       libguestfs: error: selinuxrelabel: group not available
  #
  # Fix (libguestfs-recommended fallback; host-independent):
  #   Probe the optgroup with a STANDALONE guestfish (no --selinux, no
  #   --listen); when it is unavailable, touch /.autorelabel in the guest with
  #   another STANDALONE guestfish session and skip the entire upstream relabel
  #   block (the eval --selinux --listen + the per-filesystem loop). A
  #   SELINUX!=disabled guest carrying /.autorelabel relabels every filesystem
  #   on first boot (systemd selinux-autorelabel on OL7/8/9/10; rc.sysinit on
  #   OL6) and reboots once, yielding a correctly-labelled enforcing image. On
  #   SELinux-capable hosts (RHEL/OL/Fedora) the optgroup IS available, the
  #   probe passes, and the original host-side relabel runs unchanged -- so the
  #   patch is applied unconditionally and is a no-op there.
  #
  #   Why standalone sessions (and NOT the upstream --remote session): on an
  #   optgroup-less host the `guestfish ... --selinux --listen` daemon is torn
  #   down as soon as the missing group is exercised (the socket disappears and
  #   subsequent `guestfish --remote` calls fail with "server is not running"),
  #   so the fallback cannot reuse that session to touch /.autorelabel. Hence
  #   the fallback probes and writes with self-contained `guestfish -a ...`
  #   invocations and never enters the --selinux --listen path at all. The
  #   probe form `guestfish -a /dev/null run : available selinuxrelabel` is the
  #   exact, verified one-shot used to diagnose this (see SPEC D.17).
  #
  # Edit 1 inserts the optgroup probe + autorelabel branch right after the
  # "SELinux relabel non-root filesystems" message, wrapping the original
  # eval/loop as the else-branch; Edit 2 closes that branch just after the
  # original 'guestfish --remote quit'. The failing probe sits in an 'if !'
  # position, so it is exempt from the upstream script's 'set -e'.
  #
  # Caveat (same discipline as the OL6/7 patches): local to the cloned working
  # copy, re-applied on every clone, grep-guarded for idempotency, and a no-op
  # (with a warning) if upstream refactors the relabel block.
  local build_image_sh="${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}/bin/build-image.sh"
  if [[ -f "${build_image_sh}" ]]; then
    if grep -Fq '[ol-aws-ami-builder PATCH selinux-relabel-fallback]' "${build_image_sh}"; then
      log_info "  -> build-image.sh SELinux relabel fallback already applied (idempotent skip)"
    elif grep -Fq 'selinux-relabel /etc/selinux/targeted/contexts/files/file_contexts' "${build_image_sh}"; then
      log_info "Applying SELinux relabel resilience patch to upstream bin/build-image.sh"
      sed -i.selinux-relabel.bak \
        -e '/common::echo_message "SELinux relabel non-root filesystems"/ s|$|\n    if ! guestfish -a /dev/null run : available selinuxrelabel >/dev/null 2>\&1; then\n      common::echo_message "    [ol-aws-ami-builder PATCH selinux-relabel-fallback] host libguestfs lacks selinuxrelabel optgroup; scheduling first-boot autorelabel (/.autorelabel)"\n      guestfish --rw -a "${WORKSPACE}/${VM_NAME}/${VM_NAME}.qcow2" -i touch /.autorelabel\n    else|' \
        -e 's|^\(\s*\)guestfish --remote quit$|\1guestfish --remote quit\n\1fi|' \
        "${build_image_sh}"

      if grep -Fq '[ol-aws-ami-builder PATCH selinux-relabel-fallback]' "${build_image_sh}"; then
        log_info "  -> SELinux relabel resilience patch applied (backup at ${build_image_sh}.selinux-relabel.bak)"
      else
        die "Failed to apply SELinux relabel resilience patch to ${build_image_sh}"
      fi
    else
      log_warn "  Upstream selinux-relabel call not found in ${build_image_sh}."
      log_warn "  Assuming the upstream relabel block has been refactored; proceeding."
    fi
  fi

  # Guest package manager by OL generation (see SPEC B.7 "Guest OS
  # package-manager matrix"):
  #   * OL6, OL7  -> yum  (yum-config-manager comes from yum-utils;
  #                        yum-plugin-security drives --security updates)
  #   * OL8/9/10  -> dnf  (dnf config-manager from dnf-plugins-core;
  #                        built-in `dnf upgrade --security`)
  # OL6 is fully synthesized below (yum-based) because upstream ships no
  # distr/ol6-slim/; its kickstart %packages already pulls in yum-utils and
  # yum-plugin-security, so the OL6 provision relies on them without an extra
  # install step. OL7 is a thin patch over the upstream yum-based
  # distr/ol7-slim/; OL8-10 use the upstream dnf-based distr/<rel>-slim/
  # unchanged.

  # Apply the OL6/OL7 compatibility patch when targeting Oracle Linux 6 or 7.
  #
  # Background:
  #   The upstream cloud/aws/image-scripts.sh contains a hard validation
  #   that rejects any release below OL8:
  #     [[ ${ORACLE_RELEASE} -lt 8 ]] && common::error "AWS images builder only supports OL8 and above"
  #
  # Justification:
  #   OL7 is otherwise still a complete distribution in the upstream
  #   tooling (distr/ol7-slim/ remains present, and cloud/aws/provision.sh's
  #   logic for installing the ENA driver works on OL7's UEK6 kernel
  #   without modification).
  #
  #   OL6 is more severely unsupported upstream: distr/ol6-slim/ does NOT
  #   exist at all, so build-ol-aws-ami.sh generates it at runtime (see the
  #   "OL6 distr/ol6-slim/ runtime generation" block further below). The
  #   AWS image-scripts.sh guard removal here is shared with OL7 because
  #   the rejection mechanism is identical.
  #
  #   Removing only the AWS-specific validation guard lets the existing
  #   pipeline run end-to-end against OL6 and OL7.
  #
  # Caveat:
  #   The patch is intentionally local to the cloned working copy and
  #   does NOT touch the upstream repository. It must be re-applied on
  #   every clone, which is why this lives in Phase 3 (post-clone).
  #   If the upstream check is refactored, this patch will silently
  #   no-op (see the grep guard below) and the build will rely on
  #   whatever the new upstream validation does.
  if [[ "${OL_MAJOR_VERSION}" -le 7 ]]; then
    local aws_image_scripts="${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}/cloud/aws/image-scripts.sh"
    log_info "Applying OL${OL_MAJOR_VERSION} compatibility patch to upstream cloud/aws/image-scripts.sh"

    if [[ ! -f "${aws_image_scripts}" ]]; then
      die "Cannot apply OL${OL_MAJOR_VERSION} patch: ${aws_image_scripts} not found"
    fi

    if grep -Fq 'AWS images builder only supports OL8 and above' "${aws_image_scripts}"; then
      # Replace the entire OL8+-blocking line with a clearly-marked no-op,
      # using '|' as the sed delimiter to avoid clashing with '#' (which
      # is significant in the replacement text as a shell comment marker).
      sed -i".ol${OL_MAJOR_VERSION}-patch.bak" \
        -e "s|^.*ORACLE_RELEASE.*-lt 8.*AWS images builder only supports OL8 and above.*\$|  : # [ol-aws-ami-builder OL${OL_MAJOR_VERSION} PATCH] upstream OL6/7 block removed (see build-ol-aws-ami.sh phase3)|" \
        "${aws_image_scripts}"

      if grep -Fq "[ol-aws-ami-builder OL${OL_MAJOR_VERSION} PATCH]" "${aws_image_scripts}"; then
        log_info "  -> OL${OL_MAJOR_VERSION} patch applied (backup at ${aws_image_scripts}.ol${OL_MAJOR_VERSION}-patch.bak)"
      else
        die "Failed to apply OL${OL_MAJOR_VERSION} patch to ${aws_image_scripts}"
      fi
    else
      log_warn "  Upstream OL8+ restriction line not found in ${aws_image_scripts}."
      log_warn "  Assuming the upstream check has been removed/refactored; proceeding."
    fi
  fi

  # cloud/aws/provision.sh kernel-uek-modules guard (OL6 and OL7).
  #
  # Background:
  #   The upstream cloud/aws/provision.sh contains:
  #     if [[ "${KERNEL,,}" = "uek" ]]; then
  #       yum install -y "${YUM_VERBOSE}" kernel-uek-modules
  #     else
  #       yum install -y "${YUM_VERBOSE}" kernel-modules
  #     fi
  #
  #   The separate 'kernel-uek-modules' package exists only from UEK R7
  #   onward (OL8+). UEK before R7 - OL6/UEKR4 and OL7/UEKR6 - bundles ALL
  #   modules, including amazon/ena, directly inside the main 'kernel-uek'
  #   RPM (verified: ol6_UEKR4 has no kernel-uek-modules; the ol7_UEKR6
  #   kernel-uek RPM ships
  #   lib/modules/<ver>/kernel/drivers/net/ethernet/amazon/ena/). On those
  #   releases the package does not exist, so the upstream install aborts the
  #   build with 'Error: Nothing to do' - and no separate install is needed
  #   because ena.ko is already present from kernel-uek.
  #
  # Fix:
  #   Gate the install behind ORACLE_RELEASE >= 8. On OL8+ the original
  #   behavior is preserved (kernel-uek-modules installed); on OL6/OL7 the
  #   line becomes a no-op. Applied for OL6/OL7 only; the OL8+ build path is
  #   left untouched.
  #
  # Idempotency:
  #   A grep for the wrapper marker is performed before substitution to
  #   avoid double-patching when Phase 3 re-runs against an existing clone.
  if [[ "${OL_MAJOR_VERSION}" -le 7 ]]; then
    local aws_provision="${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}/cloud/aws/provision.sh"
    log_info "Applying kernel-uek-modules guard to upstream cloud/aws/provision.sh (OL${OL_MAJOR_VERSION})"

    if [[ ! -f "${aws_provision}" ]]; then
      die "Cannot apply kernel-uek-modules guard: ${aws_provision} not found"
    fi

    # In the grep and sed lines below, ${YUM_VERBOSE} and ${ORACLE_RELEASE}
    # are deliberately left literal: they match (grep) and produce (sed)
    # upstream shell code that expands them at runtime inside
    # cloud/aws/provision.sh, not in this wrapper.
    # shellcheck disable=SC2016
    if grep -Fq '[ol-aws-ami-builder PATCH kernel-uek-modules]' "${aws_provision}"; then
      log_info "  -> provision.sh kernel-uek-modules guard already applied (idempotent skip)"
    elif grep -Fq 'yum install -y "${YUM_VERBOSE}" kernel-uek-modules' "${aws_provision}"; then
      sed -i.uek-modules-guard.bak \
        -e 's|^\(\s*\)yum install -y "${YUM_VERBOSE}" kernel-uek-modules$|\1# [ol-aws-ami-builder PATCH kernel-uek-modules] separate kernel-uek-modules exists only from UEK R7 (OL8+); UEKR4/UEKR6 (OL6/OL7) bundle modules (incl. amazon/ena) in kernel-uek\n\1[[ "${ORACLE_RELEASE}" -ge 8 ]] \&\& yum install -y "${YUM_VERBOSE}" kernel-uek-modules|' \
        "${aws_provision}"

      if grep -Fq '[ol-aws-ami-builder PATCH kernel-uek-modules]' "${aws_provision}"; then
        log_info "  -> provision.sh kernel-uek-modules guard applied (backup at ${aws_provision}.uek-modules-guard.bak)"
      else
        die "Failed to apply kernel-uek-modules guard to ${aws_provision}"
      fi
    else
      log_warn "  kernel-uek-modules install line not found in ${aws_provision}."
      log_warn "  Assuming the upstream provision logic has been refactored; proceeding."
    fi
  fi

  # OL6 distr/ol6-slim/ runtime generation.
  #
  # Background:
  #   Unlike OL7+ which has a distr/ol7-slim/ (etc.) directory shipped
  #   in the upstream oracle-linux-image-tools repo, OL6 has NO such
  #   directory upstream. Without it, bin/build-image.sh has nothing to
  #   source for kickstart, image-scripts, and provision logic.
  #
  # Approach:
  #   Generate the four required files from heredoc templates embedded
  #   in this wrapper. The templates mirror distr/ol7-slim/'s structure
  #   with OL6-specific adjustments:
  #     - Upstart (service / chkconfig) instead of systemd
  #     - GRUB Legacy (/boot/grub/grub.conf) instead of GRUB2
  #     - Anaconda 13.x kickstart syntax (no 'inst.' prefix)
  #     - UEKR4 only (kernel-uek RPM contains all ENA/NVMe/virtio modules)
  #     - No 'kernel-uek-modules' install (does not exist on OL6/UEKR4)
  #     - ext4/xfs only (no lvm/btrfs at this layer)
  #
  # Idempotency:
  #   The files are always (re-)written, so a re-run of Phase 3 will
  #   refresh them to the canonical templates.
  if [[ "${OL_MAJOR_VERSION}" -eq 6 ]]; then
    local ol6_slim_dir="${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}/distr/ol6-slim"
    log_info "Generating distr/ol6-slim/ at runtime (upstream does not ship this directory)"
    mkdir -p "${ol6_slim_dir}"

    # ----- distr/ol6-slim/env.properties -----
    cat > "${ol6_slim_dir}/env.properties" <<'EOF_OL6_ENV'
# Default parameters for OL6 distribution.
# Do NOT change anything in this file; customisation must be done in a
# separate env file (e.g. env.properties.aws-ol6).
#
# This file is created at build time by ol-aws-ami-builder because the
# upstream oracle-linux-image-tools project does not ship a distr/ol6-slim/
# directory. See SPEC.md (Part D) for the rationale.

# Distribution name (auto-derived from ISO_URL by build-image.sh; this is fallback)
DISTR_NAME="OL6U10_x86_64"

# Distribution release
readonly ORACLE_RELEASE=6

# Setup swap? (Cloud images: no)
SETUP_SWAP="no"

# Root filesystem: ext4 or xfs
# Note: OL6 default is ext4. xfs is a tech preview in OL6.4+ and stable
# in OL6.6+. ext4 is the safer choice for AWS cloud images.
ROOT_FS="ext4"

# Location of kernel/initrd on the distribution image (relative to ISO root)
BOOT_LOCATION="isolinux"

# Boot mode - Must be "bios" for OL6 (no UEFI support in OL6 anaconda)
BOOT_MODE="bios"

# Boot command for OL6 anaconda (NOTE: NO 'inst.' prefix, unlike OL7+).
# Variables MUST be escaped as they are evaluated at build time.
BOOT_COMMAND=(
  'text'
  'ks=file:/${KS_FILE}'
  'stage2=hd:LABEL=${ISO_LABEL}'
  'net.ifnames=0'
)
# Additional parameters to enable serial console
BOOT_COMMAND_SERIAL_CONSOLE=(
  'console=tty0'
  'console=ttyS0'
)

# Kernel: uek or rhck
# For OL6 + AWS, UEK4 is required for Nitro compatibility (ENA/NVMe drivers).
# RHCK 2.6.32 does NOT have ENA driver.
KERNEL="uek"

# UEK release: 4 (only valid choice for OL6 + AWS Nitro)
# UEK2/3 do not have ENA driver. UEK5+ is not available for OL6.
UEK_RELEASE=4

# Update: yes, security, no
UPDATE_TO_LATEST="yes"

# Keep linux-firmware package? yes, no
# Note: kernel-uek has a hard install dependency on linux-firmware on OL6.
LINUX_FIRMWARE="yes"

# Strip locales to only keep en_US? yes, no
STRIP_LOCALES="no"

# Exclude documentation? yes, no, minimal
EXCLUDE_DOCS="no"

# Directory used to save build information
readonly BUILD_INFO="/.build-info"
EOF_OL6_ENV

    # ----- distr/ol6-slim/image-scripts.sh -----
    cat > "${ol6_slim_dir}/image-scripts.sh" <<'EOF_OL6_IMG'
#!/usr/bin/env bash
#
# image scripts for OL6
#
# Created by ol-aws-ami-builder (not part of upstream oracle-linux-image-tools).
# Mirrors the structure of distr/ol7-slim/image-scripts.sh with OL6-specific
# adjustments:
#   - UEK_RELEASE accepts only 4 (UEK2/3/5/6/7 not supported on OL6 for AWS)
#   - ROOT_FS must be ext4 (anaconda-13 refuses xfs/lvm/btrfs root on OL6)
#

#######################################
# Validate distribution parameters
#######################################
distr::validate() {
  [[ "${ROOT_FS,,}" == "ext4" ]] || common::error "ROOT_FS must be ext4 on OL6. The OL6.10 installer (anaconda-13) refuses an XFS (or lvm/btrfs) root partition and aborts at partitioning; set ROOT_FS=ext4 (see SPEC.md D.16/D.18)."
  [[ "${TMP_IN_TMPFS,,}" =~ ^((yes)|(no))$ ]] || common::error "TMP_IN_TMPFS must be yes or no"
  [[ "${UEK_RELEASE}" =~ ^4$ ]] || common::error "UEK_RELEASE must be 4 (OL6 + AWS Nitro requires UEK4; UEK2/3 lack ENA, UEK5+ not available)"
  [[ "${LINUX_FIRMWARE,,}" =~ ^((yes)|(no))$ ]] || common::error "LINUX_FIRMWARE must be yes or no"
  [[ "${STRIP_LOCALES,,}" =~ ^((yes)|(no))$ ]] || common::error "STRIP_LOCALES must be yes or no"
  [[ "${EXCLUDE_DOCS,,}" =~ ^((yes)|(no)|(minimal))$ ]] || common::error "EXCLUDE_DOCS must be yes, no or minimal"
  readonly ROOT_FS TMP_IN_TMPFS UEK_RELEASE LINUX_FIRMWARE STRIP_LOCALES EXCLUDE_DOCS
}

#######################################
# Kickstart fixup
#######################################
distr::kickstart() {
  local ks_file="$1"

  # OL6 root filesystem is ext4-only. The embedded kickstart template already
  # declares both '/boot' and '/' as ext4, and distr::validate() rejects any
  # other ROOT_FS during preflight, so no fstype rewrite is performed here.
  # (The OL6.10 installer refuses an XFS root partition outright -- see
  # SPEC.md D.16/D.18. A previous xfs-rewrite step lived here and only ever
  # produced an install-failing config, so it was removed.)

  # Pass kernel selection (always uek for OL6+AWS, but propagate for completeness)
  sed -i -e 's!^KERNEL=.*$!KERNEL='"${KERNEL}"'!' "${ks_file}"
  sed -i -e 's!^UEK_RELEASE=.*$!UEK_RELEASE='"${UEK_RELEASE}"'!' "${ks_file}"

  # Locale
  sed -i -e 's!^STRIP_LOCALES=.*$!STRIP_LOCALES='"${STRIP_LOCALES}"'!' "${ks_file}"

  # Docs
  sed -i -e 's!^EXCLUDE_DOCS=.*$!EXCLUDE_DOCS='"${EXCLUDE_DOCS}"'!' "${ks_file}"
  if [[ "${EXCLUDE_DOCS,,}" = "yes" ]]; then
    sed -i -e 's!^%packages !%packages --excludedocs !' "${ks_file}"
  fi

  # /tmp in tmpfs - OL6 anaconda does not natively support this; handled in %post via /etc/fstab edit
  sed -i -e "s!^TMP_IN_TMPFS=no!TMP_IN_TMPFS=${TMP_IN_TMPFS}!" "${ks_file}"
}
EOF_OL6_IMG

    # ----- distr/ol6-slim/ol6-ks.cfg -----
    cat > "${ol6_slim_dir}/ol6-ks.cfg" <<'EOF_OL6_KS'
# OL6 kickstart file (mirrors OL7's ol7-ks.cfg with OL6-specific differences)

# System authorization information
auth --enableshadow --passalgo=sha512

# Command line install
cmdline
text

firstboot --disable
ignoredisk --only-use=sda
keyboard us
lang en_US.UTF-8
reboot
timezone UTC --isUtc
network  --bootproto=dhcp --device=eth0 --onboot=yes --hostname=localhost.localdomain

# Root password -- will be overridden by the builder
# NOTE: RHEL6/anaconda-13 requires a password argument for rootpw; a bare
# "rootpw --lock" is a kickstart parse error there (it is valid only on
# RHEL7+/anaconda-19+). Supply a locked, no-valid-password account form that
# anaconda-13 accepts. See SPEC Part D pitfall D.18.
rootpw --lock --iscrypted '*'

# System services (OL6: no firewalld, no chronyd)
services --disabled="ip6tables,kdump,rhsmcertd" --enabled="iptables,network,sshd,rsyslog,ntpd"
selinux --enforcing
firewall --service=ssh

# Bootloader (OL6: GRUB Legacy, not GRUB2)
# NOTE: --boot-drive is RHEL7+/anaconda-19+ only and is an "unrecognized
# arguments" parse error on RHEL6/anaconda-13. The install disk is already
# constrained by "ignoredisk --only-use=sda", so it is redundant here.
# See SPEC Part D pitfall D.18.
bootloader --append="console=tty0" --location=mbr --timeout=10

# Partitioning
zerombr
clearpart --all --initlabel

part /boot    --fstype="ext4" --ondisk=sda --size=500  --label=/boot
part swap     --fstype="swap" --ondisk=sda --size=4096 --label=swap
part /        --fstype="ext4" --ondisk=sda --size=4096 --label=root  --grow

%packages --nobase
yum
initscripts
passwd
rsyslog
vim-minimal
openssh-server
openssh-clients
dhclient
chkconfig
rootfiles
policycoreutils
checkpolicy
selinux-policy
selinux-policy-targeted
libselinux
oraclelinux-release
oraclelinux-release-notes
yum-rhn-plugin
yum-plugin-security
yum-utils
device-mapper-libs
device-mapper
kpartx
net-tools
iptables
# NOTE: iptables-services is RHEL7+ and does NOT exist on OL6 (verified against
# ol6_latest: only the iptables package ships, e.g. iptables-1.4.7-19.0.1.el6,
# and it provides the /etc/init.d/iptables service). Listing iptables-services
# makes anaconda fail OL6 package selection. See SPEC Part D pitfall D.18.
ntp
acpid
cronie
cronie-anacron
crontabs
grub

## Packages to remove
-NetworkManager
-aic94xx-firmware
-alsa-firmware
-alsa-tools-firmware
-iprutils
-ivtv-firmware
-iwl*-firmware
-libertas-*-firmware
-plymouth
-biosdevname
-b43-openfwwf
-wireless-tools
-system-config-securitylevel-tui
-cyrus-sasl
-postfix
-lzo
-mysql-libs
-kexec-tools
-efibootmgr
-bc
-busybox
-elfutils-libs
-mdadm
-pciutils-libs
-snappy
-acl
-attr
-audit

%end

%post --interpreter /bin/bash --log=/root/ks-post.log

echo "Network fixes"
cat > /etc/sysconfig/network << EOF
NETWORKING=yes
NOZEROCONF=yes
EOF

# eth0 predictable naming
rm -f /etc/udev/rules.d/70*

cat > /etc/sysconfig/network-scripts/ifcfg-eth0 << EOF
DEVICE="eth0"
BOOTPROTO="dhcp"
ONBOOT="yes"
TYPE="Ethernet"
USERCTL="yes"
PEERDNS="yes"
IPV6INIT="no"
PERSISTENT_DHCLIENT="1"
NM_CONTROLLED="no"
EOF

cat > /etc/hosts << EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
EOF

echo "RUN_FIRSTBOOT=NO" > /etc/sysconfig/firstboot

# Remove serial console from default boot (re-enabled at runtime by builder)
# OL6: edit /boot/grub/grub.conf (GRUB Legacy)
sed -i -e 's/ console=ttyS0//' /boot/grub/grub.conf

EXCLUDE_DOCS="no"
echo "Exclude documentation: ${EXCLUDE_DOCS^^}"
if [[ "${EXCLUDE_DOCS,,}" = "yes" ]]; then
  echo "tsflags=nodocs" >> /etc/yum.conf
fi

STRIP_LOCALES="no"
echo "Strip locales: ${STRIP_LOCALES^^}"
if [[ "${STRIP_LOCALES,,}" = "yes" ]]; then
  localedef --list-archive | grep -E -v '^C|^en_US' | xargs localedef --delete-from-archive
  mv -f /usr/lib/locale/locale-archive /usr/lib/locale/locale-archive.tmpl
  build-locale-archive
  echo '%_install_langs C:en_US' >> /etc/rpm/macros.image-language-conf
fi

# Install UEK4 kernel as default (the install boots with RHCK; switch to UEK4 here)
KERNEL=uek
UEK_RELEASE=4
echo "Kernel update (${KERNEL^^})"

echo "Running kernel: $(uname -r)"
echo "Kernel(s) installed:"
rpm -qa | grep '^kernel' | sort

# OL6 repo config: ensure UEKR4 is enabled (yum-config-manager from yum-utils)
yum-config-manager --disable 'ol6_UEKR*' >/dev/null 2>&1 || true
yum-config-manager --enable ol6_UEKR4 >/dev/null 2>&1

yum upgrade -y oraclelinux-release-el6 2>/dev/null || true

if [[ "${KERNEL,,}" = "uek" ]]; then
  kernel="kernel-uek"
else
  kernel="kernel"
fi

sed -i -e 's/^DEFAULTKERNEL=.*/DEFAULTKERNEL='"${kernel}"'/' /etc/sysconfig/kernel
yum install -y ${kernel}

# /tmp in tmpfs - OL6: edit /etc/fstab
TMP_IN_TMPFS=no
if [[ "${TMP_IN_TMPFS,,}" == "yes" ]]; then
  echo "tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0" >> /etc/fstab
fi

%end
EOF_OL6_KS

    # ----- distr/ol6-slim/provision.sh -----
    cat > "${ol6_slim_dir}/provision.sh" <<'EOF_OL6_PROV'
#!/usr/bin/env bash
#
# Provisioning script for OL6
#
# Created by ol-aws-ami-builder (not part of upstream oracle-linux-image-tools).
# Mirrors distr/ol7-slim/provision.sh with OL6-specific adjustments.
#

# Constants
readonly DRACUT_CMD="dracut --no-early-microcode --force"

#######################################
# Remove packages via yum
#######################################
distr::remove_rpms() {
  yum -C -y "${YUM_VERBOSE}" remove "$@" --setopt="clean_requirements_on_remove=1"
}

#######################################
# Kernel configuration
#######################################
distr::kernel_config() {
  local target_kernel

  common::echo_message "Configure kernel: ${KERNEL^^}"

  # OL6 repo names: ol6_UEKR*
  yum-config-manager --disable 'ol6_UEKR*' >/dev/null 2>&1 || true

  if [[ "${KERNEL,,}" = "uek" ]]; then
    yum-config-manager --enable "ol6_UEKR${UEK_RELEASE}" >/dev/null 2>&1
    target_kernel=$(common::latest_kernel kernel-uek)
    common::echo_message "Target kernel: ${target_kernel}"
    # OL6: no kernel-transition; install kernel-uek directly
    yum install -y "${YUM_VERBOSE}" kernel-uek
    common::remove_kernels kernel
    common::remove_kernels kernel-uek "${target_kernel}"
  else
    target_kernel=$(common::latest_kernel kernel)
    common::echo_message "Target kernel: ${target_kernel}"
    common::remove_kernels kernel-uek
    common::remove_kernels kernel "${target_kernel}"
  fi

  # Add virtual drivers to initrd
  local virtio modules
  modules=$(find "/lib/modules/${target_kernel}" -name "virtio*.ko*" -printf '%f\n')
  while read -r module; do
    virtio="${virtio} ${module%.ko*}"
  done <<<"${modules}"

  cat > /etc/dracut.conf.d/01-dracut-vm.conf <<EOF
add_drivers+=" xen_netfront xen_blkfront "
add_drivers+=" ${virtio} "
add_drivers+=" hyperv_keyboard hv_netvsc hid_hyperv hv_utils hv_storvsc hyperv_fb "
add_drivers+=" ahci libahci "
EOF

  # Regenerate initrd
  ${DRACUT_CMD} -f "/boot/initramfs-${target_kernel}.img" "${target_kernel}"

  # OL6: GRUB Legacy (no grub2-mkconfig); grubby works for default-kernel
  grubby --set-default="/boot/vmlinuz-${target_kernel}" || true

  common::echo_message "Linux firmware: ${LINUX_FIRMWARE^^}"
  if [[ "${LINUX_FIRMWARE,,}" = "no" ]]; then
    # Note: kernel-uek has a hard dependency on linux-firmware on OL6
    yum remove -y linux-firmware || true
  fi
}

#######################################
# Common configuration
#######################################
distr::common_cfg() {
  local service tty

  mkdir -p "${BUILD_INFO}"

  yum-config-manager --disable ol6_ociyum_config >/dev/null 2>&1 || true

  common::echo_message "Update image: ${UPDATE_TO_LATEST^^}"
  if [[ "${UPDATE_TO_LATEST,,}" = "yes" ]]; then
    yum update -y "${YUM_VERBOSE}"
  elif [[ "${UPDATE_TO_LATEST,,}" = "security" ]]; then
    yum install -y "${YUM_VERBOSE}" yum-plugin-security
    yum update --security -y "${YUM_VERBOSE}"
  fi

  common::echo_message "sshd root login policy: ${PERMIT_ROOT_LOGIN}"
  ex -s /etc/ssh/sshd_config <<EOF
:%substitute/^#\?\(PermitRootLogin\) .*$/\1 ${PERMIT_ROOT_LOGIN,,}/
:update
:quit
EOF

  # OL6 uses /etc/ntp.conf, not chrony
  if [[ -f /etc/ntp.conf ]]; then
    sed -i -e '/^server .*/d' /etc/ntp.conf
    cat >> /etc/ntp.conf <<EOF
server 0.rhel.pool.ntp.org iburst
server 1.rhel.pool.ntp.org iburst
server 2.rhel.pool.ntp.org iburst
server 3.rhel.pool.ntp.org iburst
EOF
  fi

  common::echo_message "Setting default runlevel to 3 (multi-user text mode)"
  sed -i -e 's/^id:.*:initdefault:/id:3:initdefault:/' /etc/inittab

  # OL6: chkconfig, not systemctl
  common::echo_message "Disable services (chkconfig)"
  for service in kdump rhnsd sendmail NetworkManager
  do
    common::echo_message "    ${service}"
    chkconfig --del "${service}" 2>/dev/null || true
    service "${service}" stop 2>/dev/null || true
  done

  common::echo_message "Set rp_filter to loose mode"
  echo "net.ipv4.conf.default.rp_filter = 2" >> /etc/sysctl.conf

  common::echo_message "Set SELinux to ${SELINUX^^}"
  sed -i -e "s/^SELINUX[  ]*=.*/SELINUX=${SELINUX,,}/" /etc/selinux/config
  if [[ ${SELINUX,,} != "enforcing" ]]; then
    setenforce Permissive || true
  fi

  common::echo_message "Clear network persistent data"
  rm -f /etc/udev/rules.d/70-persistent-net.rules

  common::echo_message "Configure yum"
  echo "exclude=kernel-uek-headers" >> /etc/yum.conf
  echo "http_caching=none" >> /etc/yum.conf

  common::echo_message "Enable login on serial console ports"
  for tty in "hvc0" "ttyS0"
  do
    grep -q "${tty}" /etc/securetty ||  echo "${tty}" >>/etc/securetty
  done

  common::echo_message "Remove unneeded RPMs"
  distr::remove_rpms \
    NetworkManager \
    NetworkManager-glib \
    NetworkManager-gnome 2>/dev/null || true

  distr::remove_rpms \
    mozjs17 \
    polkit \
    polkit-pkla-compat \
    microcode_ctl 2>/dev/null || true
}

#######################################
# Provisioning
#######################################
distr::provision() {
  common::ks_log
  distr::kernel_config
  distr::common_cfg
}

#######################################
# Cleanup
#######################################
distr::cleanup() {
  # OL6-specific: stop services using SysV init before common cleanup
  # (common::distr_cleanup uses systemctl which fails silently on OL6)
  service rsyslog stop 2>/dev/null || true
  service auditd stop 2>/dev/null || true

  common::distr_cleanup

  common::echo_message "Strip locales: ${STRIP_LOCALES^^}"
  if [[ "${STRIP_LOCALES,,}" = "yes" ]]; then
    find /usr/share/locale -mindepth  1 -maxdepth 1 -type d \
      -not -name en_US -a -not -name C \
      -exec rm -rf {} +
  fi
}
EOF_OL6_PROV

    chmod +x "${ol6_slim_dir}/image-scripts.sh" "${ol6_slim_dir}/provision.sh"
    log_info "  -> Generated 4 files in ${ol6_slim_dir}/"
  fi

  log_info "Repository ready"
}

#------------------------------------------------------------------------------
# Derive the official Oracle checksum file URL from an ISO URL.
#
# Oracle publishes per-release checksum files at
#   https://linux.oracle.com/security/gpg/checksum/
# with names of the form:
#   OracleLinux-R{major}-U{minor}-Server-{arch}.checksum
#
# Returns 0 with the URL on stdout when the ISO URL matches the expected
# Oracle naming convention, or 1 otherwise.
#------------------------------------------------------------------------------
derive_oracle_checksum_url() {
  local iso_url="$1"
  local iso_filename
  iso_filename=$(basename "${iso_url}")

  # Match patterns like:
  #   OracleLinux-R10-U1-x86_64-dvd.iso
  #   OracleLinux-R9-U7-x86_64-dvd.iso
  #   OracleLinux-R8-U1-Server-x86_64-dvd.iso  (older naming)
  #   OracleLinux-R7-U9-Server-x86_64-dvd.iso  (OL7 always uses Server infix)
  if [[ "${iso_filename}" =~ ^OracleLinux-R([0-9]+)-U([0-9]+)-(Server-)?([^-]+)-(dvd|boot)(-uek)?\.iso$ ]]; then
    local release="R${BASH_REMATCH[1]}"
    local update="U${BASH_REMATCH[2]}"
    local arch="${BASH_REMATCH[4]}"
    echo "https://linux.oracle.com/security/gpg/checksum/OracleLinux-${release}-${update}-Server-${arch}.checksum"
    return 0
  fi
  return 1
}

#------------------------------------------------------------------------------
# Find a valid OS_VARIANT short-id available in the local osinfo-db.
#
#------------------------------------------------------------------------------
# Find a valid OS_VARIANT short-id available in the local osinfo-db.
#
# Oracle's build-image.sh validates OS_VARIANT against the local osinfo
# database via:
#   osinfo-query os --fields=short-id short-id="${OS_VARIANT}"
#
# When the host's osinfo-db package is older than the target OL release,
# auto-detection fails with:
#   "can't determine OS_VARIANT; you must define it in your environment file"
#
# This function builds a candidate list dynamically based on
# OL_MAJOR_VERSION / OL_UPDATE_VERSION and returns the first match.
# Priority order:
#   1. Native oraclelinux{N}.{U} (most specific)
#   2. oraclelinux{N}.{U-1}, ..., oraclelinux{N} (older updates of the same major)
#   3. rhel{N}.* / centos-stream{N} (binary-compatible stand-ins).
#      For OL7 also include classic 'centos7' (pre-Stream).
#   4. older oraclelinux majors / generic linuxYYYY (last resort)
#------------------------------------------------------------------------------
detect_os_variant() {
  local major="${OL_MAJOR_VERSION:-10}"
  local update="${OL_UPDATE_VERSION:-1}"

  local -a candidates=()

  # 0. Modern osinfo-db 'ol{N}.{U}' short-id (introduced in libosinfo 1.x).
  #    e.g. osinfo-db-20250606 uses 'ol6.10', 'ol7.9', 'ol8.10', 'ol9.7', 'ol10.1'.
  #    The legacy 'oraclelinux{N}.{U}' short-id is still present in older
  #    osinfo-db builds, so it remains in the chain below.
  local u
  candidates+=("ol${major}.${update}")
  for ((u = update - 1; u >= 0; u--)); do
    candidates+=("ol${major}.${u}")
  done
  candidates+=("ol${major}-unknown" "ol${major}")

  # 1. Exact OL match for this major + update, then walk backwards over updates
  candidates+=("oraclelinux${major}.${update}")
  for ((u = update - 1; u >= 0; u--)); do
    candidates+=("oraclelinux${major}.${u}")
  done
  candidates+=("oraclelinux${major}-unknown" "oraclelinux${major}")

  # 2. RHEL of the same major (binary compatible with OL)
  candidates+=("rhel${major}.${update}")
  for ((u = update - 1; u >= 0; u--)); do
    candidates+=("rhel${major}.${u}")
  done
  candidates+=("rhel${major}-unknown" "rhel${major}")

  # 3. CentOS Stream of the same major (modern OL8+ stand-ins).
  # For OL7, also add 'centos7' which is the classic (non-Stream) CentOS 7
  # short-id used in older osinfo-db packages.
  candidates+=("centos-stream${major}" "centos-stream-${major}")
  if [[ "${major}" -eq 7 ]]; then
    candidates+=("centos7.0" "centos7")
  fi

  # 4. Older OL majors (one step down) as a graceful degradation path
  if [[ "${major}" -gt 8 ]]; then
    local prev_major=$((major - 1))
    # Check the most-likely range of OL{prev_major} updates first
    local prev_u
    for prev_u in 10 9 8 7 6 5 4 3 2 1 0; do
      candidates+=("oraclelinux${prev_major}.${prev_u}")
    done
    candidates+=("oraclelinux${prev_major}")
  fi

  # 5. Generic linuxYYYY fallbacks (osinfo-db ships these as catch-alls)
  candidates+=("linux2024" "linux2023" "linux2022" "linux2020" "linux2018" "linux2016" "linux2014")

  if ! command -v osinfo-query >/dev/null 2>&1; then
    return 1
  fi

  # Build a single list of all known short-ids on the host (skip header rows)
  local available
  available=$(osinfo-query os --fields=short-id 2>/dev/null \
    | tail -n +3 | awk '{print $1}' | grep -v '^$')

  if [[ -z "${available}" ]]; then
    return 1
  fi

  local variant
  for variant in "${candidates[@]}"; do
    if echo "${available}" | grep -qx "${variant}"; then
      echo "${variant}"
      return 0
    fi
  done

  return 1
}

#------------------------------------------------------------------------------
# Phase 4: Resolve ISO checksum and OS_VARIANT, then generate
#          oracle-linux-image-tools' env.properties.local
#------------------------------------------------------------------------------
phase4_prepare_env_properties() {
  log_step "Phase 4: Resolving ISO checksum and generating env.properties"

  # If ISO_CHECKSUM is empty, fetch it from the published checksum file.
  if [[ -z "${ISO_CHECKSUM:-}" ]]; then
    local iso_filename
    iso_filename=$(basename "${ISO_URL}")
    local raw_sum=""
    local checksum_url=""

    # Build the list of candidate URLs in priority order:
    #   1. User-supplied ISO_CHECKSUM_URL (if any)
    #   2. Legacy "<iso_url>.sha256sum" (works for OL7/OL8 on some mirrors)
    #   3. Modern linux.oracle.com signed checksum file (OL9+)
    local -a candidate_urls=()
    [[ -n "${ISO_CHECKSUM_URL:-}" ]] && candidate_urls+=("${ISO_CHECKSUM_URL}")
    candidate_urls+=("${ISO_URL}.sha256sum")
    local oracle_url
    if oracle_url=$(derive_oracle_checksum_url "${ISO_URL}"); then
      candidate_urls+=("${oracle_url}")
    fi

    for checksum_url in "${candidate_urls[@]}"; do
      log_info "Attempting checksum fetch from: ${checksum_url}"
      raw_sum=$(curl -fsSL "${checksum_url}" 2>/dev/null || true)
      if [[ -n "${raw_sum}" ]]; then
        log_info "  -> success"
        break
      fi
      log_warn "  -> failed (HTTP error or empty response)"
    done

    if [[ -z "${raw_sum}" ]]; then
      log_error "Failed to fetch the ISO checksum from any of the candidate URLs."
      log_error "Manual workaround:"
      log_error "  1) Open the official checksum directory in a browser:"
      log_error "       https://linux.oracle.com/security/gpg/"
      log_error "  2) Locate the entry for your release (e.g. 'Oracle Linux ${OL_MAJOR_VERSION}.${OL_UPDATE_VERSION} x86_64 checksum file')."
      log_error "  3) Open the file and find the line for ${iso_filename}."
      log_error "  4) Set ISO_CHECKSUM=<sha256_hash> in your env.properties.local and re-run."
      die "Checksum auto-resolution failed."
    fi

    # Extract the SHA256 hash for our specific ISO filename.
    # The checksum file may be a plain ".sha256sum" (single line) or a
    # GPG clear-signed file with multiple hash entries; in both cases the
    # pattern "<hash>  <filename>" lets us grep+awk the right value.
    ISO_CHECKSUM=$(echo "${raw_sum}" | grep -F "${iso_filename}" | awk '{print $1}' | head -n 1)

    if [[ -z "${ISO_CHECKSUM}" ]]; then
      log_error "Checksum file was retrieved, but no entry was found for ${iso_filename}."
      log_error "Inspect the file at: ${checksum_url}"
      log_error "Then set ISO_CHECKSUM=<sha256_hash> in your env.properties.local and re-run."
      die "Could not extract a checksum entry for ${iso_filename}."
    fi

    # Sanity-check the result looks like a SHA-256 hex string (64 chars).
    if [[ ! "${ISO_CHECKSUM}" =~ ^[0-9a-fA-F]{64}$ ]]; then
      die "Extracted value does not look like a SHA-256 hash: '${ISO_CHECKSUM}'"
    fi

    log_info "ISO_CHECKSUM = ${ISO_CHECKSUM}"
    log_info "  (source: ${checksum_url})"
  fi

  # Resolve OS_VARIANT for virt-install / Oracle build-image.sh.
  # When the user did not provide it, try to find a working short-id in the
  # local osinfo-db. If nothing matches, fail with actionable guidance.
  if [[ -z "${OS_VARIANT:-}" ]]; then
    log_info "OS_VARIANT not set; auto-detecting from the local osinfo-db"
    if ! command -v osinfo-query >/dev/null 2>&1; then
      die "osinfo-query command not found. Install libosinfo / osinfo-db (Phase 1 should have done this)."
    fi

    OS_VARIANT=$(detect_os_variant) || true

    if [[ -z "${OS_VARIANT}" ]]; then
      log_error "No suitable OS_VARIANT short-id was found in the local osinfo-db."
      log_error "Workarounds:"
      log_error "  1) Update the database:"
      log_error "       sudo dnf upgrade osinfo-db libosinfo                 # RHEL/OL"
      log_error "       sudo apt-get install --only-upgrade osinfo-db        # Debian/Ubuntu"
      log_error "  2) Install the latest osinfo-db tarball from upstream:"
      log_error "       https://releases.pagure.org/libosinfo/"
      log_error "       (then 'sudo osinfo-db-import --system osinfo-db-XXXXXX.tar.xz')"
      log_error "  3) Set OS_VARIANT manually in env.properties.local, e.g."
      log_error "       OS_VARIANT=\"linux2022\""
      die "OS_VARIANT auto-detection failed."
    fi

    log_info "  -> selected: ${OS_VARIANT}"

    # Categorize the chosen variant and emit an appropriate notice.
    # Oracle Linux is binary-compatible with RHEL / CentOS Stream of the same
    # major version, so when one of those is selected the build is effectively
    # equivalent. Older or generic fallbacks deserve a stronger warning.
    local target_major="${OL_MAJOR_VERSION}"
    if [[ "${OS_VARIANT}" =~ ^oraclelinux${target_major}([.-]|$) ]]; then
      log_info "  Native Oracle Linux ${target_major} profile. Optimal."
    elif [[ "${OS_VARIANT}" =~ ^rhel${target_major}([.-]|$) ]] \
       || [[ "${OS_VARIANT}" =~ ^centos-stream-?${target_major}$ ]]; then
      log_info "  Note: '${OS_VARIANT}' is binary-compatible with Oracle Linux ${target_major}."
      log_info "  This is an excellent stand-in and produces an equivalent build."
      log_info "  (To get a native 'oraclelinux${target_major}' entry, update osinfo-db from upstream:"
      log_info "   https://releases.pagure.org/libosinfo/)"
    elif [[ "${OS_VARIANT}" =~ ^oraclelinux[0-9]+ ]]; then
      log_warn "  Note: the chosen variant is from a different OL major than ${target_major}."
      log_warn "  The build will still produce a working OL${target_major} image, but virt-install"
      log_warn "  may apply older hardware defaults. Consider updating osinfo-db:"
      log_warn "    sudo dnf upgrade osinfo-db libosinfo                 # RHEL/OL"
      log_warn "    sudo apt-get install --only-upgrade osinfo-db        # Debian/Ubuntu"
    elif [[ "${OS_VARIANT}" =~ ^linux ]]; then
      log_warn "  Note: a generic Linux profile was selected."
      log_warn "  The build will work, but virt-install will use minimal defaults."
      log_warn "  For a more accurate profile, update osinfo-db (see commands above)"
      log_warn "  or install the latest tarball from https://releases.pagure.org/libosinfo/"
    else
      log_warn "  Selected variant '${OS_VARIANT}' is unusual. Verify the build VM behavior."
    fi
  fi

  # Generate the env.properties file consumed by the build tool
  local tool_env="${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}/env.properties.local"
  cat > "${tool_env}" <<EOF
# Auto-generated: $(date)
# Source: ${ENV_FILE}

WORKSPACE=${WORKSPACE}
DISTR=${DISTR}
CLOUD=${CLOUD}
ISO_URL=${ISO_URL}
ISO_CHECKSUM=${ISO_CHECKSUM}
OS_VARIANT=${OS_VARIANT}

BUILD_NUMBER=${BUILD_NUMBER}
SETUP_SWAP=${SETUP_SWAP}
SELINUX=${SELINUX}
ROOT_FS=${ROOT_FS}
DISK_SIZE_GB=${DISK_SIZE_GB}
SERIAL_CONSOLE_RUNTIME=${SERIAL_CONSOLE_RUNTIME}
SERIAL_CONSOLE=${SERIAL_CONSOLE}
BOOT_MODE=${BOOT_MODE_BUILD}

# Kernel selection (uek or rhck) - falls back to distr default if unset
${KERNEL:+KERNEL=${KERNEL}}

# UEK release (relevant when KERNEL=uek; only meaningful for OL7 where the
# upstream default is UEK6). Pass through verbatim so the upstream tooling
# can pick the appropriate kernel-uek package.
${UEK_RELEASE:+UEK_RELEASE=${UEK_RELEASE}}

# RPM update policy.
# Propagates the wrapper-level UPDATE_TO_LATEST (yes / security / no) into
# the upstream distr/ol{N}-slim/provision.sh distr::configure routine. When
# unset, the distr-level default (currently "yes" for OL7/8/9/10 and for
# the runtime-generated ol6-slim template) is inherited.
${UPDATE_TO_LATEST:+UPDATE_TO_LATEST=${UPDATE_TO_LATEST}}

# linux-firmware retention - "No" recommended for cloud VMs (smaller image)
${LINUX_FIRMWARE:+LINUX_FIRMWARE=${LINUX_FIRMWARE}}

# Root password / SSH key (prefer cloud-init for production use)
${ROOT_PASSWORD:+ROOT_PASSWORD=${ROOT_PASSWORD}}
${ROOT_SSH_KEY:+ROOT_SSH_KEY=${ROOT_SSH_KEY}}

# cloud-init configuration
${CLOUD_INIT:+CLOUD_INIT=${CLOUD_INIT}}
${CLOUD_USER:+CLOUD_USER=${CLOUD_USER}}
EOF

  log_info "Generated env.properties.local: ${tool_env}"
  echo "----- env.properties.local -----"
  grep -v '^#' "${tool_env}" | grep -v '^$'
  echo "--------------------------------"
}

#------------------------------------------------------------------------------
# Phase 5: Run oracle-linux-image-tools to produce the VMDK
#------------------------------------------------------------------------------
phase5_run_build() {
  log_step "Phase 5: Running oracle-linux-image-tools to build the VMDK"

  local tool_dir="${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}"
  local tool_env="${tool_dir}/env.properties.local"

  # Force libguestfs to run qemu directly instead of via libvirt.
  #
  # Why: virt-sparsify (called by oracle-linux-image-tools at the very end
  # of the build) creates a temporary overlay subdirectory under the disk's
  # own directory using mkdtemp(3), which always sets mode 0700. That mode
  # cannot be relaxed by POSIX default ACLs (the auto-computed mask masks
  # the qemu user's permission bits to 0). The libvirt 'qemu' user (uid
  # 107) therefore fails to traverse the temp dir and the build aborts:
  #
  #   virt-sparsify: error: libguestfs error: could not create appliance
  #     through libvirt. Cannot access storage file '...tmp.XXXX/...qcow2'
  #     (as uid:107, gid:107): Permission denied
  #
  # The "direct" backend bypasses libvirt entirely and runs qemu as the
  # current user, which (when the script runs as root) can access every
  # directory regardless of mode.
  #
  # This affects ONLY libguestfs-based tools (virt-customize, virt-sysprep,
  # virt-sparsify). virt-install in this phase still goes through libvirt,
  # which is why Phase 2 grants the qemu user traverse ACLs on the parent
  # path of WORKSPACE — both fixes are needed.
  #
  # User can override by setting LIBGUESTFS_BACKEND in env.properties.local.
  export LIBGUESTFS_BACKEND="${LIBGUESTFS_BACKEND:-direct}"
  log_info "LIBGUESTFS_BACKEND = ${LIBGUESTFS_BACKEND}"

  log_info "Starting build (this typically takes 20-60 minutes)"
  log_info "Build watchdog: ${BUILD_TIMEOUT_MIN} min (SERIAL_CONSOLE=${SERIAL_CONSOLE}; upstream applies no install timeout when the serial console is enabled)"

  # Snapshot running libvirt domains BEFORE the build so a watchdog timeout can
  # reap the transient install VM. virt-install --transient domains are managed
  # by libvirtd and survive a killed build-image.sh, so they would otherwise
  # keep running (and hold the workspace disk) after we abort.
  local doms_before
  doms_before=$(virsh list --name 2>/dev/null | sed '/^$/d' | sort || true)

  local build_rc=0
  timeout --signal=TERM --kill-after=60s "${BUILD_TIMEOUT_MIN}m" \
    bash -c 'cd "$1" && ./bin/build-image.sh --env "$2"' _ "${tool_dir}" "${tool_env}" || build_rc=$?

  if [[ ${build_rc} -eq 124 ]]; then
    log_error "build-image.sh exceeded the ${BUILD_TIMEOUT_MIN}-minute watchdog and was terminated."
    local doms_after dom
    doms_after=$(virsh list --name 2>/dev/null | sed '/^$/d' | sort || true)
    while IFS= read -r dom; do
      [[ -z "${dom}" ]] && continue
      log_warn "Reaping leftover transient build VM: ${dom}"
      virsh destroy "${dom}" >/dev/null 2>&1 || true
    done < <(comm -13 <(printf '%s\n' "${doms_before}") <(printf '%s\n' "${doms_after}"))
    die "build-image.sh timed out after ${BUILD_TIMEOUT_MIN} minutes (raise BUILD_TIMEOUT_MIN for slow hosts/links, or set SERIAL_CONSOLE=no for a bounded headless install)"
  elif [[ ${build_rc} -ne 0 ]]; then
    die "build-image.sh failed (exit ${build_rc})"
  fi

  # Locate the produced VMDK file
  # Naming convention: OL{N}U{M}_x86_64-aws-b<BUILD_NUMBER>.vmdk
  # (e.g. OL10U1_x86_64-aws-b0.vmdk, OL9U7_x86_64-aws-b0.vmdk)
  VMDK_PATH=$(find "${WORKSPACE}" -maxdepth 3 -name '*.vmdk' -newer "${tool_env}" 2>/dev/null | head -n 1)

  if [[ -z "${VMDK_PATH}" || ! -f "${VMDK_PATH}" ]]; then
    die "Built VMDK file was not found under ${WORKSPACE}"
  fi

  log_info "VMDK file: ${VMDK_PATH}"
  log_info "Size:      $(du -h "${VMDK_PATH}" | awk '{print $1}')"
}

#------------------------------------------------------------------------------
# Phase 6: Upload the VMDK to S3
#------------------------------------------------------------------------------
phase6_upload_to_s3() {
  log_step "Phase 6: Uploading VMDK to S3"

  local vmdk_filename
  vmdk_filename=$(basename "${VMDK_PATH}")
  S3_KEY="${S3_KEY_PREFIX:-ol10-ami-import}/${vmdk_filename}"

  # Create the S3 bucket if it does not exist
  if ! aws s3api head-bucket --bucket "${S3_BUCKET}" --region "${AWS_REGION}" 2>/dev/null; then
    log_info "S3 bucket ${S3_BUCKET} does not exist; creating it"
    if [[ "${AWS_REGION}" == "us-east-1" ]]; then
      aws s3api create-bucket --bucket "${S3_BUCKET}" --region "${AWS_REGION}"
    else
      aws s3api create-bucket --bucket "${S3_BUCKET}" --region "${AWS_REGION}" \
        --create-bucket-configuration LocationConstraint="${AWS_REGION}"
    fi
    # Block all public access on the new bucket
    aws s3api put-public-access-block --bucket "${S3_BUCKET}" \
      --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
  fi

  log_info "Uploading: s3://${S3_BUCKET}/${S3_KEY}"
  aws s3 cp "${VMDK_PATH}" "s3://${S3_BUCKET}/${S3_KEY}" --region "${AWS_REGION}"
  log_info "Upload completed"
}

#------------------------------------------------------------------------------
# Phase 7: Convert the VMDK to an EBS snapshot via import-snapshot
#------------------------------------------------------------------------------
phase7_import_snapshot() {
  log_step "Phase 7: Creating EBS snapshot via import-snapshot"

  # Confirm that the vmimport role exists
  if ! aws iam get-role --role-name "${VMIMPORT_ROLE_NAME}" >/dev/null 2>&1; then
    die "IAM role '${VMIMPORT_ROLE_NAME}' does not exist. Run setup-vmimport-role.sh first."
  fi

  local import_task
  import_task=$(aws ec2 import-snapshot \
    --region "${AWS_REGION}" \
    --description "${AMI_NAME} - import" \
    --disk-container "Format=VMDK,UserBucket={S3Bucket=${S3_BUCKET},S3Key=${S3_KEY}}" \
    --role-name "${VMIMPORT_ROLE_NAME}" \
    --query 'ImportTaskId' --output text)

  log_info "import-snapshot task ID: ${import_task}"
  log_info "Polling until completion (typically 10-30 minutes)"

  # Poll loop with hard timeout (90 minutes) and graceful handling of
  # transient AWS API failures (network blips, throttling). A failed
  # describe-import-snapshot-tasks call should not abort the build —
  # we retry on the next iteration.
  local -i poll_interval=60
  local -i max_iterations=$((90 * 60 / poll_interval))   # 90 minutes
  local -i iteration=0
  local status="" progress="" query_output=""

  while :; do
    iteration=$((iteration + 1))
    if (( iteration > max_iterations )); then
      die "import-snapshot did not complete within $((max_iterations * poll_interval / 60)) minutes (task: ${import_task})"
    fi

    if ! query_output=$(aws ec2 describe-import-snapshot-tasks \
        --region "${AWS_REGION}" \
        --import-task-ids "${import_task}" \
        --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.[Status,Progress]' \
        --output text 2>/dev/null); then
      log_warn "  describe-import-snapshot-tasks API call failed (transient); retrying in ${poll_interval}s"
      sleep "${poll_interval}"
      continue
    fi

    read -r status progress <<< "${query_output}"

    # Empty status means the API returned successfully but with no data
    # for our task (extremely unlikely; treat as transient and retry).
    if [[ -z "${status}" ]]; then
      log_warn "  Empty status returned by AWS API; retrying"
      sleep "${poll_interval}"
      continue
    fi

    log_info "  Status: ${status} (${progress:-0}%)"

    case "${status}" in
      completed)
        break
        ;;
      deleted|cancelled|deleting)
        die "import-snapshot task failed: ${status}"
        ;;
      active|pending)
        # in progress — keep polling
        ;;
      *)
        # Unknown status code — log and continue (AWS may add new states)
        log_warn "  Unrecognized status '${status}'; continuing to poll"
        ;;
    esac
    sleep "${poll_interval}"
  done

  SNAPSHOT_ID=$(aws ec2 describe-import-snapshot-tasks \
    --region "${AWS_REGION}" \
    --import-task-ids "${import_task}" \
    --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.SnapshotId' \
    --output text)

  log_info "Snapshot ready: ${SNAPSHOT_ID}"

  # Tag the snapshot
  aws ec2 create-tags \
    --region "${AWS_REGION}" \
    --resources "${SNAPSHOT_ID}" \
    --tags "Key=Name,Value=${AMI_NAME}" \
           "Key=BuiltBy,Value=oracle-linux-image-tools" \
           "Key=Distr,Value=${DISTR}"
}

#------------------------------------------------------------------------------
# Phase 8: Register the snapshot as an AMI
#------------------------------------------------------------------------------
phase8_register_ami() {
  log_step "Phase 8: Registering AMI via register-image"

  # Build the register-image argument list.
  # NitroTPM (--tpm-support) requires UEFI boot; it is incompatible with
  # legacy-bios AMIs and must be omitted in that case.
  local -a register_args=(
    --region "${AWS_REGION}"
    --name "${AMI_NAME}"
    --description "${AMI_DESCRIPTION}"
    --architecture x86_64
    --root-device-name /dev/sda1
    --virtualization-type hvm
    --ena-support
    --boot-mode "${BOOT_MODE}"
    --imds-support v2.0
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={SnapshotId=${SNAPSHOT_ID},VolumeSize=${DISK_SIZE_GB},VolumeType=gp3,DeleteOnTermination=true}"
  )

  # NitroTPM is only valid for UEFI-bootable AMIs
  if [[ "${BOOT_MODE,,}" == "uefi" || "${BOOT_MODE,,}" == "uefi-preferred" ]]; then
    register_args+=(--tpm-support v2.0)
    log_info "Boot mode supports UEFI; enabling NitroTPM (--tpm-support v2.0)"
  else
    log_info "Boot mode is legacy-bios; NitroTPM (--tpm-support) is omitted (UEFI-only feature)"
  fi

  local ami_id
  ami_id=$(aws ec2 register-image "${register_args[@]}" --query 'ImageId' --output text) \
    || die "register-image failed"

  log_info "AMI registered: ${ami_id}"

  # Tag the AMI
  aws ec2 create-tags \
    --region "${AWS_REGION}" \
    --resources "${ami_id}" \
    --tags "Key=Name,Value=${AMI_NAME}" \
           "Key=OS,Value=OracleLinux${OL_MAJOR_VERSION}U${OL_UPDATE_VERSION}" \
           "Key=Architecture,Value=x86_64" \
           "Key=BuiltBy,Value=oracle-linux-image-tools" \
           "Key=BuildDate,Value=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  echo
  log_info "=========================================="
  log_info "  AMI build completed successfully"
  log_info "=========================================="
  log_info "  AMI ID:       ${ami_id}"
  log_info "  AMI Name:     ${AMI_NAME}"
  log_info "  Region:       ${AWS_REGION}"
  log_info "  Snapshot ID:  ${SNAPSHOT_ID}"
  log_info "  Boot Mode:    ${BOOT_MODE}"
  log_info "  ENA Support:  enabled"
  log_info "=========================================="
}

#------------------------------------------------------------------------------
# Main entrypoint
#------------------------------------------------------------------------------
main() {
  parse_args "$@"
  load_env

  phase0_preflight_checks
  phase1_install_prerequisites
  phase2_grant_qemu_access
  phase3_clone_repository
  phase4_prepare_env_properties
  phase5_run_build

  if [[ ${BUILD_ONLY} -eq 1 || ${SKIP_AWS_IMPORT} -eq 1 ]]; then
    log_info "Build-only mode. Skipping AWS import phases."
    log_info "VMDK file: ${VMDK_PATH}"
    exit 0
  fi

  phase6_upload_to_s3
  phase7_import_snapshot
  phase8_register_ami
}

main "$@"
