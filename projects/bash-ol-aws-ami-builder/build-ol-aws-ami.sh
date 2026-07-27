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
# Experimental support: 7 and 6 (x86_64; deprecated upstream, verification
# use only). OL7 is rejected upstream for the AWS target and re-enabled by a
# Phase 3 patch; OL6 is not shipped upstream at all (no distr/ol6-slim/) and is
# additionally synthesized at runtime. See the OL7 / OL6 notes below.
# The actual version, ISO URL, and AMI naming are driven from the env
# properties file specified with --env. See env.properties.aws-ol10 (or
# env.properties.aws-ol9 / env.properties.aws-ol8 / env.properties.aws-ol7 /
# env.properties.aws-ol6) for working examples.
#
# Note on OL7:
#   The upstream oracle-linux-image-tools project explicitly rejects OL7 for
#   the AWS cloud target via a hard-coded check in cloud/aws/image-scripts.sh.
#   This wrapper applies a runtime patch in Phase 3 (after cloning the
#   upstream repository) to allow OL7 builds. Use at your own risk; OL7
#   Premier Support ended on 2024-12-31.
#
# Note on OL6:
#   OL6 is supported as a deeper workaround than OL7. Upstream ships no
#   distr/ol6-slim/ at all, so Phase 3 synthesizes it at runtime and applies
#   two sed patches (the shared OL8+-guard removal plus an OL6-only
#   kernel-uek-modules skip). Use at your own risk; OL6 Premier Support ended
#   2021-03-31 and Extended Life Support ended in 2024. IMDS_SUPPORT=v2.0 is
#   rejected for OL6 (its cloud-init 0.7.5 cannot fetch metadata over IMDSv2).
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
#   Phase 6:   Nitro readiness pre-check (offline image inspection)
#   Phase 7:   Upload the VMDK to S3
#   Phase 8:   Convert the VMDK to an EBS snapshot via import-snapshot
#   Phase 9:   Register the snapshot as an AMI
#
# ----- Options ----------------------------------------------------------------
#   --env <file>          : Path to the environment properties file (required)
#   --skip-prereq         : Skip Phase 1 when build host packages are present
#   --skip-aws-import     : Skip the AWS import phases (Phases 7-9): run
#                           through the VMDK build and the Phase 6 Nitro
#                           readiness check, then exit. Equivalent to
#                           --build-only.
#   --build-only          : Run through Phase 6 (VMDK build + Nitro readiness
#                           check), then exit without the AWS import phases
#                           (Phases 7-9). Equivalent to --skip-aws-import.
#   --skip-ena-driver     : Do NOT build/install the Amazon ENA driver in the
#                           guest. Default is to build it on OL6-OL10 (AWS-
#                           optimized, ENA-Express-capable AMI); this switch
#                           produces a pure, unmodified OL AMI.
#   --skip-ssm-agent      : Do NOT install the Amazon SSM Agent in the guest.
#                           Default is to install + enable it for boot (OL6-OL10),
#                           so the AMI is SSM Run Command compliant out of the box;
#                           this switch leaves the agent out.
#   --skip-awscli         : Do NOT install AWS CLI v2 in the guest. Default is to
#                           install it on OL6/OL7/OL8 (the standard CLI, since
#                           AWS CLI v1 is increasingly unsupported); this switch
#                           leaves it out. OL9/OL10 are out of scope (use their
#                           default package manager) and unaffected by this switch.
#   --enable-amazon-time-sync : OPT-IN. Configure the link-local Amazon Time
#                           Sync Service (169.254.169.123) as the PREFERRED
#                           time source in the guest (chrony on OL7-OL10,
#                           ntpd on OL6), keeping the distribution pool as
#                           fallback. Default OFF: time configuration is
#                           left to the end user of the AMI. Equivalent to
#                           AMAZON_TIME_SYNC="yes" in the env file.
#   --imds-support <mode> : IMDS support baked into the AMI. 'default'
#                           (IMDSv1+v2; HttpTokens=optional) or 'v2.0'
#                           (IMDSv2-required, OL7+ only). Default: 'default'.
#   --log-file <path>     : Write the full run log here. Default:
#                           ${WORKSPACE}/build-ol-aws-ami-YYYYMMDD-hhmmss.log
#                           (console output is mirrored to the file either way).
#   --debug               : Also print [DEBUG] lines to the console (they are
#                           always written to the log file regardless).
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
#            for the OL7 and OL6 experimental support layers added in 2026-05.
#   Generated / iteratively refined: 2026-05
#   Verified by the author against real OL8 / OL9 / OL10 builds on AWS.
#   OL7 support has been verified only at the patch-mechanism level
#   (sed substitution, syntax integrity); end-to-end OL7 AMI builds
#   have NOT been validated by the author.
#   OL6 support has been verified at the static + boot-test level (Phase A:
#   osinfo-db / ISO checksum / repo / cloud-init checks; Phase B: virt-install
#   + Anaconda 13.x TUI boot test), and the two runtime patches plus the
#   synthesized distr/ol6-slim/ are syntax-validated; end-to-end OL6 AMI builds
#   (kickstart completion through AWS Nitro launch) have NOT been validated by
#   the author. Use at your own risk.
#==============================================================================

set -euo pipefail

readonly OL_REPO_URL="https://github.com/oracle/oracle-linux.git"
readonly OL_TOOLS_SUBDIR="oracle-linux-image-tools"
# Directory this wrapper lives in, so Phase 3 can locate sibling artifacts
# (e.g. install-ena-driver.sh) regardless of the caller's working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# NOTE on ISO selection: there is deliberately no built-in default ISO URL.
# ISO_URL is a required env-file key (validated in load_env). Embedding a
# concrete release URL here would go stale on every Oracle update release;
# the env templates are the single maintenance point instead.

# Execution mode flags
SKIP_PREREQ=0
AMAZON_TIME_SYNC_CLI=0
ENA_USER_PIN=0
SKIP_AWS_IMPORT=0
BUILD_ONLY=0
# ENA driver self-build (default ON -> AWS-optimized AMI; --skip-ena-driver
# turns it OFF -> pure, unmodified OL AMI).
ENA_DRIVER_BUILD=1
# Resolved ENA self-build pin (filled by load_env from install-ena-driver.sh when
# ENA_DRIVER_BUILD=1); stays empty for a pure OL AMI. Used in the AMI name/desc.
ENA_BUILD_VERSION=""
# SSM Agent install (default ON -> the AMI ships an enabled, AWS-compliant Amazon
# SSM Agent; --skip-ssm-agent turns it OFF). Wired for OL6-OL10. The pinned/latest
# version per OL lives in install-ssm-agent.sh (SSM_AGENT_VERSION_OL<major>).
SSM_AGENT_INSTALL=1
# Resolved SSM Agent version for THIS OL (filled when SSM_AGENT_INSTALL=1, from
# install-ssm-agent.sh's per-OL map); "latest" or a pin. Used in the AMI name/desc.
SSM_AGENT_RESOLVED=""
# AWS CLI v2 install (default ON -> the AMI ships AWS CLI v2 as the standard CLI,
# since AWS CLI v1 is increasingly unsupported; --skip-awscli turns it OFF). Wired
# for OL6/OL7/OL8 ONLY -- OL9/OL10 install AWS CLI v2 from their default package
# manager, so this wrapper leaves them out of scope. The pinned/latest version per
# OL lives in install-awscli.sh (AWSCLI_VERSION_OL<major>).
AWSCLI_INSTALL=1
# Resolved AWS CLI v2 version for THIS OL (filled when AWSCLI_INSTALL=1 and the OL
# is in scope, from install-awscli.sh's per-OL map; "latest" is resolved to a
# concrete version). Used in the AMI name/desc -- which always carries a concrete
# x.y.z, never the word "latest".
AWSCLI_RESOLVED=""
ENV_FILE=""
# Logging (N3/F4). DEBUG=1 (--debug) also mirrors [DEBUG] lines to the console;
# they are always written to the log file regardless. LOG_FILE empty -> default
# under WORKSPACE (set in setup_logging()); --log-file <path> overrides.
DEBUG=0
LOG_FILE=""
LOG_SETUP_DONE=""

#------------------------------------------------------------------------------
# Logging helpers
#------------------------------------------------------------------------------
log_info()  { echo -e "$(date '+%Y-%m-%d %H:%M:%S') \033[1;34m[INFO]\033[0m  $*"; }
log_warn()  { echo -e "$(date '+%Y-%m-%d %H:%M:%S') \033[1;33m[WARN]\033[0m  $*" >&2; }
log_error() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') \033[1;31m[ERROR]\033[0m $*" >&2; }
log_step()  { echo -e "\n\033[1;32m========== $* ==========\033[0m\n"; }
# Build-phase progress (heartbeat) -- our format, distinct [BUILD] tag.
# Timestamp unified to 'YYYY-MM-DD HH:MM:SS' and emitted first on every channel (N2).
log_progress() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') \033[1;36m[BUILD]\033[0m $*"; }
# [DEBUG] (F4 severity). Always written to the log file; mirrored to the console
# only when DEBUG=1 (--debug). When quiet it goes straight to fd 3 (the direct
# file handle opened in setup_logging), bypassing the console tee.
log_debug() {
  local line; line="$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] $*"
  if [[ "${DEBUG}" == "1" ]]; then
    printf '%s\n' "${line}"
  elif [[ -n "${LOG_SETUP_DONE}" ]]; then
    printf '%s\n' "${line}" >&3
  fi
}
# Re-emit external-tool output read on stdin, one attributed line at a time:
#   YYYY-MM-DD HH:MM:SS [EXTERNAL] [<script>] <original line>
# so output produced by the invoked external script (and its children) is
# unmistakably distinct from this wrapper's own [INFO]/[BUILD] lines. The
# timestamp is per-line (current time as each line arrives). $1 = script name.
log_external() {
  local script="$1" line
  while IFS= read -r line || [[ -n "${line}" ]]; do
    printf '%s \033[90m[EXTERNAL]\033[0m \033[90m[%s]\033[0m %s\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "${script}" "${line}"
    # Record the latest LIVE orchestrator line so the Phase-5 heartbeat can show
    # "what build-image.sh is doing now". NOTE: the in-guest provision.sh output
    # (install-ena-driver.sh's [ena-driver] lines) is swallowed by virt-customize
    # until/unless the guest script fails, so it is NOT a live signal -- only this
    # orchestrator stream is. Best-effort, single overwrite (latest wins).
    if [[ -n "${BUILD_STAGE_FILE:-}" ]]; then
      printf '%s\n' "[${script}] ${line}" > "${BUILD_STAGE_FILE}" 2>/dev/null || true
    fi
    line=""
  done
}

die() { log_error "$*"; exit 1; }

# N3: persist the whole run to a log file while keeping the console. By default
# the file is ${WORKSPACE}/build-ol-aws-ami-YYYYMMDD-hhmmss.log; --log-file
# <path> (LOG_FILE) overrides. Called once from load_env() after WORKSPACE is
# resolved+created, so it captures the env summary and every phase. fd 3 is a
# direct (un-tee'd) handle for [DEBUG] lines suppressed on the console; the tee
# branch strips ANSI colour so the file stays grep-friendly while the console
# keeps colour.
setup_logging() {
  [[ -n "${LOG_SETUP_DONE}" ]] && return 0
  : "${LOG_FILE:=${WORKSPACE}/build-ol-aws-ami-$(date '+%Y%m%d-%H%M%S').log}"
  local log_dir; log_dir="$(dirname "${LOG_FILE}")"
  mkdir -p "${log_dir}" 2>/dev/null || true
  exec 3>>"${LOG_FILE}"
  exec > >(tee >(sed -u 's/\x1b\[[0-9;]*m//g' >> "${LOG_FILE}")) 2>&1
  LOG_SETUP_DONE=1
  log_info "[OLAWS-LOG01] build log: ${LOG_FILE}$([[ "${DEBUG}" == "1" ]] && echo ' (debug console output ON)')"
}

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
      --skip-ena-driver)  ENA_DRIVER_BUILD=0;  shift ;;
      --skip-ssm-agent)   SSM_AGENT_INSTALL=0; shift ;;
      --skip-awscli)      AWSCLI_INSTALL=0; shift ;;
      --enable-amazon-time-sync) AMAZON_TIME_SYNC_CLI=1; shift ;;
      --imds-support)     IMDS_SUPPORT="$2";   shift 2 ;;
      --log-file)         LOG_FILE="$2";       shift 2 ;;
      --debug)            DEBUG=1;             shift ;;
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
  # OL5-era naming: the 5.x media predates the "OracleLinux-R*" convention and
  # ships as "Enterprise-R5-U11-Server-x86_64-dvd.iso" (Oracle's original
  # "Enterprise Linux" branding; the kernel.org mirror carries this exact
  # name). OS-separation: this branch can only ever match the legacy media.
  if [[ "${iso_filename}" =~ Enterprise-R([0-9]+)-U([0-9]+) ]]; then
    OL_MAJOR_VERSION="${BASH_REMATCH[1]}"
    OL_UPDATE_VERSION="${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

#------------------------------------------------------------------------------
# Load environment properties and validate required keys
#------------------------------------------------------------------------------
normalize_imds_support() {
  # AMI Instance Metadata Service (IMDS) support baked into the registered AMI.
  #   default : do NOT pass --imds-support -> instances allow IMDSv1+IMDSv2
  #             (HttpTokens=optional). Most compatible, and the only safe choice
  #             for OL6 (cloud-init 0.7.5 cannot fetch metadata via IMDSv2).
  #   v2.0    : register with --imds-support v2.0 -> instances default to
  #             IMDSv2-required (HttpTokens=required). OL7+ only.
  # Reads and normalises the IMDS_SUPPORT global, rejects unsupported values and
  # the OL6 + IMDSv2-only combination. Behaviour-identical to the former inline
  # block in load_env (extracted so it can be unit tested - see tests/t003_unit.sh).
  : "${IMDS_SUPPORT:=default}"
  IMDS_SUPPORT="${IMDS_SUPPORT,,}"
  case "${IMDS_SUPPORT}" in
    default|v1+v2|v1v2)      IMDS_SUPPORT="default" ;;
    v2|v2.0|v2only|v2-only)  IMDS_SUPPORT="v2.0" ;;
    *) die "Invalid IMDS_SUPPORT='${IMDS_SUPPORT}' (use 'default' for IMDSv1+v2, or 'v2.0' for IMDSv2-only)" ;;
  esac
  # OL6's cloud-init (0.7.5) cannot use IMDSv2, so an IMDSv2-only AMI would break
  # metadata-based SSH-key injection on first boot. Reject v2.0 for OL6 up front.
  if [[ "${OL_MAJOR_VERSION}" -eq 6 && "${IMDS_SUPPORT}" == "v2.0" ]]; then
    die "IMDS_SUPPORT=v2.0 is not supported for OL6: its cloud-init 0.7.5 cannot fetch instance metadata over IMDSv2, so an IMDSv2-only AMI would fail SSH-key injection. Use IMDS_SUPPORT=default (IMDSv1+v2) for OL6."
  fi
  # Same class of failure, older generation: OL5's cloud-init is EPEL5's 0.6.3
  # whose DataSourceEc2 speaks plain (token-less) IMDSv1 only, so an
  # IMDSv2-only AMI would fail SSH-key injection on first boot. Explicit OL5
  # branch (OS-separation; see the OL6 rationale above / SPEC D.27).
  if [[ "${OL_MAJOR_VERSION}" -eq 5 && "${IMDS_SUPPORT}" == "v2.0" ]]; then
    die "IMDS_SUPPORT=v2.0 is not supported for OL5: its cloud-init 0.6.3 (EPEL5) fetches instance metadata over plain IMDSv1 only, so an IMDSv2-only AMI would fail SSH-key injection. Use IMDS_SUPPORT=default (IMDSv1+v2) for OL5."
  fi
}

# validate_ami_name NAME
#   Enforce the AWS EC2 register-image --name constraints (see
#   https://docs.aws.amazon.com/cli/latest/reference/ec2/register-image.html):
#   length 3-128, and the allowed character set is alphanumerics plus the
#   literals ()[] space . / - ' @ _ . Returns 0 when valid; on a violation it
#   prints a one-line reason to stderr and returns 1 (it never exits, so the
#   caller decides how to fail). Pure (argument-only: no env, fs, or network),
#   so it is unit tested in isolation -- see tests/t020_register.sh.
validate_ami_name() {
  local name="$1"
  local n="${#name}"
  if (( n < 3 || n > 128 )); then
    printf 'AMI name length %d is out of range (must be 3-128 characters)\n' "${n}" >&2
    return 1
  fi
  # Match any character OUTSIDE the allowed set. In the bracket expression ']'
  # is listed first and '-' last so both are literal; the single quote is part
  # of the set. LC_ALL=C gives byte semantics so a multibyte character (which is
  # outside the ASCII allowed set) is correctly rejected.
  if printf '%s' "${name}" | LC_ALL=C grep -q "[^]A-Za-z0-9()[ ./'@_-]"; then
    printf "AMI name contains a character outside the allowed set (alphanumerics and these literals: ()[] space . / - ' @ _)\n" >&2
    return 1
  fi
  return 0
}

# validate_ami_description DESCRIPTION
#   Enforce the AWS EC2 register-image --description constraint: length 0-255
#   (any character; an empty description is allowed). Returns 0 when valid; on a
#   violation prints a one-line reason to stderr and returns 1. Pure; unit tested
#   in tests/t020_register.sh.
validate_ami_description() {
  local desc="$1"
  local n="${#desc}"
  if (( n > 255 )); then
    printf 'AMI description length %d exceeds the maximum of 255 characters\n' "${n}" >&2
    return 1
  fi
  return 0
}

load_env() {
  log_step "Loading environment properties: ${ENV_FILE}"

  # shellcheck source=/dev/null
  source "${ENV_FILE}"

  # Required parameters (build)
  : "${WORKSPACE:?WORKSPACE is not defined}"
  if [[ -z "${ISO_URL:-}" ]]; then
    die "ISO_URL is not defined. Set it in your env file to the Oracle Linux
     DVD ISO URL (see the SINGLE-TOUCH MAINTENANCE POINT marker in the
     env.properties.aws-ol* templates; latest releases:
     https://yum.oracle.com/oracle-linux-isos.html)."
  fi
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

  # Emit a prominent advisory when the user targets OL5, and enforce the OL5
  # measured invariants up front. OL5 is the deepest legacy target: upstream
  # ships no distr/ol5-slim/, EL5 userspace has NO TLS-1.2 path (openssl
  # 0.9.8e), bash is 3.2, dracut/systemd/grub2 do not exist, and the guest can
  # reach NO https repository -- every package beyond the ISO is pre-staged
  # from the HOST (the provision.d files channel). See SPEC B (OL5) and the
  # D-part investigation records.
  if [[ "${OL_MAJOR_VERSION}" -eq 5 ]]; then
    log_warn "============================================================================"
    log_warn " Oracle Linux 5 target selected (OL${OL_MAJOR_VERSION}U${OL_UPDATE_VERSION})."
    log_warn ""
    log_warn "  * OL5 Premier Support ended 2017; Extended Support ended 2021."
    log_warn "  * Upstream oracle-linux-image-tools does NOT ship distr/ol5-slim/;"
    log_warn "    build-ol-aws-ami.sh generates it at runtime in Phase 3."
    log_warn "  * ALL guest packages beyond the ISO are HOST-staged (EL5 has no"
    log_warn "    in-OS TLS 1.2 path): UEK R2 kernel, the frozen ENA build"
    log_warn "    toolchain, the EPEL5 cloud-init 0.6.3 closure, and gdisk."
    log_warn "  * The ENA driver is SELF-BUILT (UEK R2 has no in-box ena; the"
    log_warn "    in-box nvme IS present -- the Nitro boot precondition)."
    log_warn "  * The Amazon SSM Agent is a MEASURED EXCLUSION on OL5 (rpmlib +"
    log_warn "    kernel-floor walls; SPEC B.10/D.31) and is never wired."
    log_warn "  * x86_64 / BIOS / MBR + GRUB Legacy only. UEK Release 2 only."
    log_warn "  * Nitro boot is unproven until the real-instance E2E; Xen-"
    log_warn "    generation instances are the measured fallback path."
    log_warn ""
    log_warn "  This target is intended ONLY for verification, learning, or"
    log_warn "  legacy migration scenarios. NEVER use the resulting AMI for"
    log_warn "  production workloads."
    log_warn "============================================================================"

    # SSM Agent: measured exclusion (SPEC B.10/D.31 -- xz/sha256 rpmlib wall +
    # kernel 3.2 floor, all three empirically proven). Forced OFF regardless of
    # flags so the hook can never be wired and the AMI name never carries an
    # ssm marker on OL5.
    if [[ "${SSM_AGENT_INSTALL}" -eq 1 ]]; then
      log_info "[OLAWS-OL5] SSM Agent install FORCED OFF on OL5 (measured exclusion; SPEC B.10/D.31 -- not a --skip default)"
      SSM_AGENT_INSTALL=0
    fi

    # cloud-init 0.6.3 has no users-groups module: the key-injection target
    # user must ALREADY exist (setup_user_keys is getpwnam-only), and the
    # synthesized kickstart %post creates exactly 'ec2-user'. The upstream
    # cloud/aws default (CLOUD_USER=opc) therefore cannot work here; pin it.
    if [[ "${CLOUD_USER:-}" != "" && "${CLOUD_USER}" != "ec2-user" ]]; then
      log_warn "[OLAWS-OL5] CLOUD_USER='${CLOUD_USER}' overridden to 'ec2-user' on OL5 (cloud-init 0.6.3 cannot create users; the kickstart pre-creates ec2-user only)"
    fi
    CLOUD_USER="ec2-user"

    # Upstream common::retrieve_iso hard-requires a SHA1/SHA256 ISO_CHECKSUM.
    # The kernel.org mirror publishes MD5SUMS only, so the operator computes
    # the SHA256 once (cross-checking the documented mirror MD5) and bakes it
    # into the env file -- fail loudly here instead of deep inside upstream.
    if [[ -z "${ISO_CHECKSUM:-}" ]]; then
      die "ISO_CHECKSUM is empty. OL5 requires a SHA256 you compute once from the
     downloaded ISO (upstream accepts SHA1/SHA256 only; the kernel.org mirror
     publishes MD5SUMS). Steps (documented in env.properties.aws-ol5):
       1) curl -fL -o Enterprise-R5-U11-Server-x86_64-dvd.iso '<ISO_URL>'
       2) md5sum  <iso>   # MUST equal the mirror MD5SUMS value recorded in the env file
       3) sha256sum <iso> # paste into ISO_CHECKSUM"
    fi
  fi

  # DISTR slug used by oracle-linux-image-tools.
  # Convention: ol{major}-slim (e.g. ol10-slim, ol9-slim, ol8-slim, ol7-slim).
  : "${DISTR:=ol${OL_MAJOR_VERSION}-slim}"

  # Resolve workspace to an absolute path
  WORKSPACE=$(realpath -m "${WORKSPACE}")
  mkdir -p "${WORKSPACE}"

  # N3: start mirroring console output to the build log now that WORKSPACE
  # exists (so the env summary below and every phase are captured).
  setup_logging

  # Resolve the SSM Agent version for the persistent AMI identity + report.
  # SSM_AGENT_RESOLVED starts as the per-OL target (the /latest/ alias on
  # every OL major since 2026-07-13);
  # if it is "latest", resolve it to the concrete S3-published version so the AMI
  # name/description, the injection log, and the final report record a real
  # version instead of the word "latest" (unsuitable for a persistent artifact).
  # The guest install is UNCHANGED -- the hook still installs the /latest/ alias;
  # this is display/identity only. Runs for every build (incl. --build-only) so
  # the injection log is concrete too. Best-effort: an offline/failed resolution
  # falls back to "latest".
  if [[ "${SSM_AGENT_INSTALL}" -eq 1 ]]; then
    SSM_AGENT_RESOLVED="$(_ssm_pin_for_major "${OL_MAJOR_VERSION}")"
    if [[ -z "${SSM_AGENT_RESOLVED}" || "${SSM_AGENT_RESOLVED}" == "latest" ]]; then
      local _ssm_latest; _ssm_latest="$(_ssm_resolve_latest)"
      if [[ -n "${_ssm_latest}" ]]; then
        SSM_AGENT_RESOLVED="${_ssm_latest}"
        log_info "[OLAWS-SSM02] resolved SSM Agent 'latest' -> ${SSM_AGENT_RESOLVED} for the AMI identity/report (the guest still installs the /latest/ alias)"
      else
        SSM_AGENT_RESOLVED=""
        log_warn "[OLAWS-SSM02] could not resolve SSM Agent 'latest' to a concrete version; the AMI identity will omit the ssm marker (no non-concrete 'latest' in the AMI name)"
      fi
    fi
  fi

  # Resolve the AWS CLI v2 version for the persistent AMI identity + report.
  # Wired for OL5/OL6/OL7/OL8 ONLY (OL9/OL10 install v2 from their default package
  # manager -- out of scope here). AWSCLI_RESOLVED starts as the per-OL target
  # (OL5/OL6 pin 2.17.51, OL7/OL8 "latest"); if it is "latest", resolve it to the
  # concrete published version so the AMI name/description always carries a
  # concrete x.y.z, never the word "latest". The guest install is UNCHANGED --
  # the OL7/OL8 hook still installs the /latest/ bundle; this is display/identity
  # only. If resolution fails (e.g. offline --build-only), AWSCLI_RESOLVED is left
  # empty and the AMI identity simply omits the awscli marker (never "latest").
  if [[ "${AWSCLI_INSTALL}" -eq 1 && ( "${OL_MAJOR_VERSION}" == "5" || "${OL_MAJOR_VERSION}" == "6" || "${OL_MAJOR_VERSION}" == "7" || "${OL_MAJOR_VERSION}" == "8" ) ]]; then
    AWSCLI_RESOLVED="$(_awscli_pin_for_major "${OL_MAJOR_VERSION}")"
    if [[ -z "${AWSCLI_RESOLVED}" || "${AWSCLI_RESOLVED}" == "latest" ]]; then
      local _awscli_latest; _awscli_latest="$(_awscli_resolve_latest)"
      if [[ -n "${_awscli_latest}" ]]; then
        AWSCLI_RESOLVED="${_awscli_latest}"
        log_info "[OLAWS-AWSCLI02] resolved AWS CLI v2 'latest' -> ${AWSCLI_RESOLVED} for the AMI identity/report (the guest still installs the latest bundle)"
      else
        AWSCLI_RESOLVED=""
        log_warn "[OLAWS-AWSCLI02] could not resolve AWS CLI v2 'latest' to a concrete version; the AMI identity will omit the awscli marker (no non-concrete 'latest' in the AMI name)"
      fi
    fi
  fi

  # Resolve the ENA self-build target version for the AMI identity + the guest
  # hook. Runs for every build (incl. --build-only) when the self-build is on
  # (default, OL6-OL10; --skip-ena-driver leaves it empty -> pure OL AMI).
  # OL6/OL7 read the installer's concrete pins (_ena_pin_for_major -- the
  # single source of truth); OL8/9/10 have empty pins (latest-resolving), so
  # the host resolves amzn-drivers latest (_ena_resolve_latest_host) and, if
  # that fails (offline), falls back to the installer's concrete
  # ENA_LATEST_FALLBACK_PIN -- the AMI identity always carries a concrete
  # x.y.z, never the word "latest". For the latest-resolving majors the
  # resolved version is also PASSED INTO the guest hook (ENA_DRIVER_VERSION),
  # so the AMI name and the actually-built module can never drift.
  if [[ "${ENA_DRIVER_BUILD}" -eq 1 ]]; then
    if [[ -n "${ENA_DRIVER_VERSION:-}" ]]; then
      # USER PIN (highest priority; env-file key ENA_DRIVER_VERSION). Must be
      # a concrete x.y.z so the AMI identity invariant holds; the same value
      # is passed into the guest hook unconditionally (see the hook injection),
      # so name and artifact cannot drift on ANY major, pinned-installer
      # majors (OL6/OL7) included.
      if [[ ! "${ENA_DRIVER_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        die "ENA_DRIVER_VERSION must be a concrete x.y.z version (got '${ENA_DRIVER_VERSION}').
     Use e.g. ENA_DRIVER_VERSION=\"2.17.2\" in your env file, or leave it unset
     for the default chain (installer pin -> amzn-drivers latest -> fallback pin)."
      fi
      ENA_BUILD_VERSION="${ENA_DRIVER_VERSION}"
      ENA_USER_PIN=1
      log_info "[OLAWS-ENA02] user pin ENA_DRIVER_VERSION=${ENA_BUILD_VERSION} for OL${OL_MAJOR_VERSION} (AMI identity + guest hook target; overrides installer pin / latest resolution)"
    else
      ENA_BUILD_VERSION="$(_ena_pin_for_major "${OL_MAJOR_VERSION}")"
      if [[ -z "${ENA_BUILD_VERSION}" ]]; then
        local _ena_latest; _ena_latest="$(_ena_resolve_latest_host)"
        if [[ -n "${_ena_latest}" ]]; then
          ENA_BUILD_VERSION="${_ena_latest}"
          log_info "[OLAWS-ENA02] resolved amzn-drivers latest -> ${ENA_BUILD_VERSION} for OL${OL_MAJOR_VERSION} (AMI identity + guest hook target)"
        else
          ENA_BUILD_VERSION="$(_ena_fallback_pin)"
          log_warn "[OLAWS-ENA02] could not resolve amzn-drivers latest (host offline?); falling back to the installer's pin ${ENA_BUILD_VERSION:-<unknown>} for OL${OL_MAJOR_VERSION}"
        fi
      fi
    fi
  fi

  # Required parameters for AWS import (unless skipped)
  if [[ ${SKIP_AWS_IMPORT} -eq 0 && ${BUILD_ONLY} -eq 0 ]]; then
    : "${S3_BUCKET:?S3_BUCKET is not defined}"
    # Resolve AWS_REGION dynamically when the env file leaves it empty.
    # See resolve_aws_region() for the IMDSv2 -> IMDSv1 -> "ap-northeast-1"
    # fallback chain. Sets AWS_REGION_SOURCE for downstream logging.
    resolve_aws_region
    : "${AWS_REGION:?AWS_REGION could not be resolved (this should not happen)}"
    # ENA self-build identity, folded into the AMI name (brief) and description
    # (full) so a self-built-ENA AMI is distinguishable from a pure OL AMI BEFORE
    # launch. ENA_BUILD_VERSION was resolved above ([OLAWS-ENA02]: the
    # installer's pin for OL6/OL7, host-resolved amzn-drivers latest -- or the
    # installer's concrete fallback pin -- for OL8/9/10); it stays empty for
    # --skip-ena-driver. Wired for OL6-OL10 (ENA Express generation: the AMI
    # ships an express-capable driver by default). Only the AUTO defaults gain
    # the marker -- an explicitly set AMI_NAME/AMI_DESCRIPTION is left
    # untouched (:=).
    local _ena_name_sfx="" _ena_desc_sfx=" (pure OL; ENA self-build skipped)"
    if [[ "${ENA_DRIVER_BUILD}" -eq 1 ]]; then
      _ena_name_sfx="-ena${ENA_BUILD_VERSION:-}"
      # Build-kind truthfulness (run-9 review): OL5 self-builds via plain
      # make (no DKMS on EL5); OL6+ build via DKMS.
      local _ena_bk="DKMS"
      [[ "${OL_MAJOR_VERSION}" -eq 5 ]] && _ena_bk="plain make"
      _ena_desc_sfx=" with self-built Amazon ENA ${ENA_BUILD_VERSION:-driver} (${_ena_bk}, AWS-optimized for Nitro)"
    fi
    # SSM Agent identity, folded into the AMI name/desc the same way. Default ON
    # for OL6-OL10; --skip-ssm-agent leaves it empty. SSM_AGENT_RESOLVED is a
    # concrete x.y.z.w (resolved above; empty if resolution failed) -- so the
    # marker ALWAYS carries a concrete version and is omitted entirely rather
    # than ever printing the word "latest" (parity with the awscli marker;
    # regression pin: the 2026-07-18 OL9/OL10 E2E registered '-ssmlatest'
    # AMI names when the GitHub-first resolution failed). AUTO defaults only (:=).
    local _ssm_name_sfx="" _ssm_desc_sfx=""
    if [[ "${SSM_AGENT_INSTALL}" -eq 1 && -n "${SSM_AGENT_RESOLVED}" && "${SSM_AGENT_RESOLVED}" != "latest" ]]; then
      _ssm_name_sfx="-ssm${SSM_AGENT_RESOLVED}"
      _ssm_desc_sfx=", Amazon SSM Agent ${SSM_AGENT_RESOLVED}"
    fi
    # AWS CLI v2 identity, folded into the AMI name/desc the same way. Default ON
    # for OL6/OL7/OL8; --skip-awscli and OL9/OL10 (out of scope) leave it empty.
    # AWSCLI_RESOLVED is a concrete x.y.z (resolved above; empty if resolution
    # failed) -- so the marker ALWAYS carries a concrete version and is omitted
    # entirely rather than ever printing the word "latest". AUTO defaults only (:=).
    local _awscli_name_sfx="" _awscli_desc_sfx=""
    if [[ -n "${AWSCLI_RESOLVED}" ]]; then
      _awscli_name_sfx="-awscli${AWSCLI_RESOLVED}"
      _awscli_desc_sfx=", AWS CLI v2 ${AWSCLI_RESOLVED}"
    fi
    : "${AMI_NAME:=OracleLinux-${OL_MAJOR_VERSION}-U${OL_UPDATE_VERSION}-x86_64-$(date +%Y%m%d-%H%M)${_ena_name_sfx}${_ssm_name_sfx}${_awscli_name_sfx}}"
    : "${AMI_DESCRIPTION:=Oracle Linux ${OL_MAJOR_VERSION} Update ${OL_UPDATE_VERSION} (x86_64) custom AMI built via oracle-linux-image-tools${_ena_desc_sfx}${_ssm_desc_sfx}${_awscli_desc_sfx}}"
    # Validate the resolved AMI name/description against the AWS register-image
    # limits NOW, before Phases 1-8, so an out-of-range or mis-charactered value
    # (most likely an explicit override) fails fast instead of after a full
    # build. The same constraints are re-checked implicitly by the Phase-9
    # --dry-run pre-flight. See validate_ami_name / validate_ami_description.
    validate_ami_name "${AMI_NAME}" \
      || die "AMI_NAME is invalid for AWS register-image: '${AMI_NAME}'. It must be 3-128 characters from the allowed set [alphanumerics ()[] space . / - ' @ _]."
    validate_ami_description "${AMI_DESCRIPTION}" \
      || die "AMI_DESCRIPTION is invalid for AWS register-image (length ${#AMI_DESCRIPTION}): it must be at most 255 characters."
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
  : "${DISK_SIZE_GB:=7}"
  : "${AMAZON_TIME_SYNC:=no}"
  if [[ "${AMAZON_TIME_SYNC_CLI:-0}" -eq 1 ]]; then
    AMAZON_TIME_SYNC="yes"
  fi
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
  # Normalise IMDS_SUPPORT (and reject OL6 + IMDSv2-only); see
  # normalize_imds_support.
  normalize_imds_support
  # Phase-5 build watchdog, in minutes. An outer safety bound on the upstream
  # build-image.sh run (in addition to upstream's own install timeout). On
  # expiry the wrapper reaps the transient build VM and aborts. Generous
  # default so a normal 20-60 min build never trips it; raise for slow hosts.
  : "${BUILD_TIMEOUT_MIN:=120}"
  # Phase-5 progress heartbeat, in seconds (0 disables). Independent of the
  # install console, the wrapper logs an elapsed-time + build-disk growth line
  # every interval so a headless build's liveness/progress is visible even when
  # anaconda emits nothing to the serial line (OL8+ runs anaconda in tmux). The
  # default is short because this script is usually run interactively, not in
  # CI, where a long silent gap reads as a hang.
  : "${HEARTBEAT_INTERVAL_SEC:=10}"
  # Nitro readiness pre-check mode (Phase 6). Offline, read-only inspection of
  # the built image for the AWS Nitro boot essentials (NVMe host driver, ENA
  # driver, UUID/LABEL-based fstab and bootloader root=), run after the VMDK is
  # produced and before the upload/snapshot/register phases so a non-bootable
  # image is caught before those wasted steps.
  #   enforce (default) - die on a blocking finding
  #   warn              - inspect and report, but never die
  #   off               - skip the check entirely
  # Indeterminate results (inspection tools missing, initramfs not extractable)
  # are fail-open: warn and continue, never abort an otherwise-good build.
  : "${NITRO_PRECHECK:=enforce}"
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
  # [DEBUG] (F4): the resolved feature knobs -- file always, console with --debug.
  log_debug "[OLAWS-CFG01] knobs: ENA_DRIVER_BUILD=${ENA_DRIVER_BUILD} SSM_AGENT_INSTALL=${SSM_AGENT_INSTALL} AWSCLI_INSTALL=${AWSCLI_INSTALL} IMDS_SUPPORT=${IMDS_SUPPORT} SKIP_PREREQ=${SKIP_PREREQ} SKIP_AWS_IMPORT=${SKIP_AWS_IMPORT} BUILD_ONLY=${BUILD_ONLY}"

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
      # Best-effort: pykickstart provides ksvalidator for the Phase-3 exit
      # gate's ADVISORY pass. Its absence only degrades the gate to
      # structural-only (logged), never fails the build host provisioning.
      sudo dnf install -y pykickstart \
        || log_warn "pykickstart unavailable; the Phase-3 exit gate runs structural-only (no ksvalidator advisory)"
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
      sudo apt-get install -y pykickstart \
        || log_warn "pykickstart unavailable; the Phase-3 exit gate runs structural-only (no ksvalidator advisory)"
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
# _ks_add_sos_package <ks_file>
# Insert the 'sos' package (sosreport tooling) into the first %packages
# section of an upstream distr kickstart (OL7-OL10). The OL6 kickstart is
# synthesized by this wrapper (distr::kickstart heredoc) and lists sos
# directly, so it never comes through here. Idempotent via the wrapper
# marker; asserts before writing (missing file / missing %packages section
# both die, so a half-patched kickstart can never be produced).
_ks_add_sos_package() {
  local ks_file="$1"

  if [[ ! -f "${ks_file}" ]]; then
    die "Cannot add sos package: kickstart not found at ${ks_file}"
  fi
  if grep -Fq '[ol-aws-ami-builder PATCH sos-package]' "${ks_file}"; then
    log_info "  -> sos package already present in $(basename "${ks_file}") (idempotent skip)"
    return 0
  fi
  if ! grep -Eq '^%packages' "${ks_file}"; then
    die "Cannot add sos package: no %packages section in ${ks_file}"
  fi

  sed -i.sos-package.bak -e '0,/^%packages/{/^%packages/a\
# [ol-aws-ami-builder PATCH sos-package] sosreport tooling baked into every AMI\
sos
}' "${ks_file}"

  if grep -Fq '[ol-aws-ami-builder PATCH sos-package]' "${ks_file}"; then
    log_info "  [OLAWS-SOS01] sos package added to $(basename "${ks_file}") (backup at ${ks_file}.sos-package.bak)"
  else
    die "Failed to add sos package to ${ks_file}"
  fi
}

# ---- upstream provenance + Phase-3 exit gate ---------------------------------
# The pipeline tracks upstream oracle-linux at HEAD by design (user decision
# 2026-07-11: always latest, no pin). The compensating controls are:
#   (1) [OLAWS-UPSTREAM01] -- the upstream HEAD (full SHA, date, subject) is
#       logged on every build AND written to ${WORKSPACE}/upstream-provenance.txt
#       together with the applied wrapper patch markers and the sha256 of every
#       patched artifact, so ANY later failure is reproducible byte-for-byte.
# _ol5_stage_closure_gate DIR GLIBC_NVR RPM_FILE...
# Host-side dependency-closure gate over the EXACT staged RPM set, run after
# fetching and BEFORE the ~45-minute install (first-contact record #5: the
# guest rpm transaction failed on gdisk->libicu and on glibc-devel/-headers
# carrying exact `glibc = <newer errata>` requires against the U11 GA guest).
#
# Model: every requirement of every staged rpm must be satisfied by
#   (a) the staged set itself (provides, package names, or staged files --
#       file-requires like /usr/bin/python2.6 are satisfied by staged
#       python26's payload and are therefore listed in the baked table), or
#   (b) the BAKED guest-base capability table below -- the exact external
#       surface measured from the real staged set with `rpm -qp` and proven
#       satisfied by the real U11-guest transaction (record #5): only the 4
#       fixed lines ever failed, so every cap in this table resolved on the
#       real guest.
# Plus one exact rule: any `glibc = X` requirement in the staged set must
# equal the pinned guest base NVR (arg 2) -- the record-#5 failure class.
# Any gap dies loudly here, in seconds, with the full list. A future UEK
# live-resolution bump that introduces a new cap also dies loudly here --
# that is intended (verify, then extend the table deliberately).
# Skips with a warning when the build host has no rpm CLI.
_ol5_stage_closure_gate() {
  local dir="$1" guest_glibc_nvr="$2"; shift 2
  if ! command -v rpm >/dev/null 2>&1; then
    log_warn "  [OL5-CLOSURE] rpm CLI not available on the build host; SKIPPING the staged-set closure gate"
    return 0
  fi
  local tmpd f
  tmpd="$(mktemp -d)" || die "OL5 closure gate: mktemp failed"
  : > "${tmpd}/provides.raw"; : > "${tmpd}/requires.raw"
  for f in "$@"; do
    [[ -s "${dir}/${f}" ]] || die "OL5 closure gate: staged rpm missing: ${dir}/${f}"
    rpm -qp --provides "${dir}/${f}" >> "${tmpd}/provides.raw" 2>/dev/null \
      || die "OL5 closure gate: rpm --provides failed for ${f}"
    rpm -qp --requires "${dir}/${f}" >> "${tmpd}/requires.raw" 2>/dev/null \
      || die "OL5 closure gate: rpm --requires failed for ${f}"
    rpm -qp --qf '%{NAME}\n' "${dir}/${f}" >> "${tmpd}/provides.raw" 2>/dev/null \
      || die "OL5 closure gate: rpm --qf NAME failed for ${f}"
  done
  # provides: full strings AND bare names (before any comparison operator)
  sed -e 's/[[:space:]]*$//' "${tmpd}/provides.raw" > "${tmpd}/p1"
  sed -e 's/ [<>=].*$//' "${tmpd}/p1" > "${tmpd}/p2"
  sort -u "${tmpd}/p1" "${tmpd}/p2" > "${tmpd}/provides"
  # exact-glibc rule (record-#5 failure class)
  local bad_glibc
  bad_glibc="$(grep -E '^glibc = ' "${tmpd}/requires.raw" | grep -Fv "glibc = ${guest_glibc_nvr}" | sort -u || true)"
  if [[ -n "${bad_glibc}" ]]; then
    log_error "  [OL5-CLOSURE] staged set carries exact glibc requires that do NOT match the guest base (${guest_glibc_nvr}):"
    while IFS= read -r f; do log_error "    ${f}"; done <<< "${bad_glibc}"
    rm -rf "${tmpd}"
    die "OL5 staging: dependency-closure gate FAILED (glibc exact-NVR mismatch)"
  fi
  # external surface = requires - rpmlib() - staged provides/names
  local gaps
  gaps="$(
    sed -e 's/[[:space:]]*$//' "${tmpd}/requires.raw" \
    | grep -v '^rpmlib(' \
    | sort -u \
    | while IFS= read -r req; do
        name="${req%% *}"
        if ! grep -Fxq "${req}" "${tmpd}/provides" && ! grep -Fxq "${name}" "${tmpd}/provides"; then
          printf '%s\n' "${name}"
        fi
      done \
    | sort -u \
    | comm -23 - <(printf '%s\n' "${OL5_GUEST_BASE_CAPS}" | sort -u)
  )" || true
  if [[ -n "${gaps}" ]]; then
    log_error "  [OL5-CLOSURE] staged set has requirement(s) satisfied neither by the staged rpms nor by the measured guest-base table:"
    while IFS= read -r f; do log_error "    ${f}"; done <<< "${gaps}"
    rm -rf "${tmpd}"
    die "OL5 staging: dependency-closure gate FAILED (unsatisfied external requirement(s))"
  fi
  rm -rf "${tmpd}"
  log_info "  [OL5-CLOSURE] staged-set dependency closure verified ($# rpm(s); glibc pinned at ${guest_glibc_nvr})"
}

# Measured guest-base capability table for _ol5_stage_closure_gate (record
# #5): the exact external requirement surface of the staged set, computed
# with rpm -qp over the real artifacts and proven satisfied by the real
# U11-guest transaction. File paths satisfied by STAGED payloads (e.g.
# /usr/bin/python2.6) are listed here because `rpm -qp --provides` does not
# enumerate files. Keep sorted; extend only with verified entries.
readonly OL5_GUEST_BASE_CAPS="/bin/bash
/bin/sh
/sbin/install-info
/sbin/ldconfig
/sbin/new-kernel-pkg
/usr/bin/env
/usr/bin/find
/usr/bin/perl
/usr/bin/python2.6
/usr/bin/python26
/usr/bin/run-parts
aic94xx-firmware
atmel-firmware
bfa-firmware
binutils
chkconfig
device-mapper-multipath
e4fsprogs
fileutils
glibc
initscripts
iproute
ipw2100-firmware
ipw2200-firmware
ivtv-firmware
iwl1000-firmware
iwl3945-firmware
iwl4965-firmware
iwl5000-firmware
iwl5150-firmware
iwl6000-firmware
iwl6050-firmware
kexec-tools
libBrokenLocale.so.1()(64bit)
libanl.so.1()(64bit)
libbz2.so.1()(64bit)
libc.so.6()(64bit)
libc.so.6(GLIBC_2.2.5)(64bit)
libc.so.6(GLIBC_2.3)(64bit)
libc.so.6(GLIBC_2.3.2)(64bit)
libc.so.6(GLIBC_2.3.4)(64bit)
libc.so.6(GLIBC_2.4)(64bit)
libcidn.so.1()(64bit)
libcrypt.so.1()(64bit)
libcrypt.so.1(GLIBC_2.2.5)(64bit)
libcrypto.so.6()(64bit)
libdb-4.3.so()(64bit)
libdl.so.2()(64bit)
libdl.so.2(GLIBC_2.2.5)(64bit)
libertas-usb8388-firmware
libgcc
libgcc_s.so.1()(64bit)
libgcc_s.so.1(GCC_3.0)(64bit)
libgdbm.so.2()(64bit)
libm.so.6()(64bit)
libm.so.6(GLIBC_2.2.5)(64bit)
libncurses.so.5()(64bit)
libncursesw.so.5()(64bit)
libnsl.so.1()(64bit)
libnsl.so.1(GLIBC_2.2.5)(64bit)
libnss_compat.so.2()(64bit)
libnss_dns.so.2()(64bit)
libnss_files.so.2()(64bit)
libnss_hesiod.so.2()(64bit)
libnss_nis.so.2()(64bit)
libnss_nisplus.so.2()(64bit)
libpanelw.so.5()(64bit)
libpopt.so.0()(64bit)
libpthread.so.0()(64bit)
libpthread.so.0(GLIBC_2.2.5)(64bit)
libpthread.so.0(GLIBC_2.3.2)(64bit)
libpthread.so.0(GLIBC_2.3.4)(64bit)
libreadline.so.5()(64bit)
libresolv.so.2()(64bit)
librt.so.1()(64bit)
librt.so.1(GLIBC_2.2.5)(64bit)
libselinux-python
libsqlite3.so.0()(64bit)
libssl.so.6()(64bit)
libstdc++.so.6()(64bit)
libstdc++.so.6(CXXABI_1.3)(64bit)
libstdc++.so.6(GLIBCXX_3.4)(64bit)
libtermcap.so.2()(64bit)
libthread_db.so.1()(64bit)
libutil.so.1()(64bit)
libutil.so.1(GLIBC_2.2.5)(64bit)
libuuid.so.1()(64bit)
libz.so.1()(64bit)
mkinitrd
module-init-tools
net-tools
netxen-firmware
oraclelinux-release
procps
ql2xxx-firmware
rsyslog
rt61pci-firmware
rt73usb-firmware
rtld(GNU_HASH)
shadow-utils
zd1211-firmware"

# _ol5_scan_bash32_hostile FILE
# Scan one guest-bound env-concat member for bash-4-only constructs that
# would kill the EL5 guest's bash 3.2 at source time (declare -g/-A,
# mapfile/readarray, ${var,,}/${var^^}, |&) on non-comment lines.
#
# EXEMPTION (principled, not author-based): a line is exempt iff it has the
# version-guard safe shape
#     [ "${BASH_VERSINFO[0]}" -ge 4 ] && <anything> || true
# which is safe BY CONSTRUCTION on bash 3.2 -- the guard evaluates false, so
# the RHS never executes (bash-4 tokens are inert at parse time), and the
# trailing `|| true` keeps the AND-list from tripping `set -e`. This is
# exactly the shape the OL5 env-defaults patch writes; anything else
# carrying a hostile token still fails the scan (first-contact record #2:
# the 2026-07-20 gate correctly failed in seconds, but on the fix line
# itself -- the patch and the gate had never been run TOGETHER).
# Prints findings (line-numbered) on stdout; returns 1 iff any.
_ol5_scan_bash32_hostile() {
  local file="$1" hostile
  hostile="$(grep -nE 'declare -g|declare -A|mapfile|readarray|\$\{[A-Za-z_][A-Za-z_0-9]*(,,|\^\^)|\|&' "${file}" \
    | grep -vE '^[0-9]+:[[:space:]]*#' \
    | grep -vE '^[0-9]+:\[ "\$\{BASH_VERSINFO\[0\]\}" -ge 4 \] && .* \|\| true$' || true)"
  if [[ -n "${hostile}" ]]; then
    printf '%s\n' "${hostile}"
    return 1
  fi
  return 0
}

# _ol5_patch_env_defaults FILE
# Guard upstream's `declare -gA REPO` (bash 4.2+) for the EL5 guest: the
# env-concat channel carries this file verbatim into the guest, whose bash
# 3.2 sources it (first-contact record #1). Host-side semantics unchanged
# (modern bash still declares the associative array; REPO is host-only).
# Marker-guarded + idempotent; loud warn if upstream refactored the line.
_ol5_patch_env_defaults() {
  local file="$1"
  if [[ ! -f "${file}" ]]; then
    die "Cannot apply OL5 env-defaults patch: ${file} not found"
  fi
  if grep -Fq '[ol-aws-ami-builder OL5 env-defaults PATCH]' "${file}"; then
    log_info "  -> OL5 env-defaults patch already present (idempotent skip)"
  elif grep -q '^declare -gA REPO$' "${file}"; then
    # shellcheck disable=SC2016
    sed -i".ol5-envdefaults.bak" \
      -e 's~^declare -gA REPO$~# [ol-aws-ami-builder OL5 env-defaults PATCH] declare -gA is bash 4.2+; the EL5 guest (bash 3.2) sources this file via provision.d -- guard by bash major (REPO is host-side only)\n[ "${BASH_VERSINFO[0]}" -ge 4 ] \&\& declare -gA REPO || true~' \
      "${file}"
    if grep -q 'BASH_VERSINFO\[0\]' "${file}"; then
      log_info "  -> OL5 env-defaults patch applied (backup at ${file}.ol5-envdefaults.bak)"
    else
      die "Failed to apply OL5 env-defaults patch to ${file}"
    fi
  else
    log_warn "  Upstream 'declare -gA REPO' line not found in ${file}."
    log_warn "  Assuming upstream refactored it; the P3GATE guest-env scan remains the safety net."
  fi
}

#   (2) [OLAWS-P3GATE01] -- a pre-install exit gate validates the ACTUALLY
#       patched artifacts on the real build host at the end of Phase 3, so an
#       upstream shape change or a mis-applied patch fails in seconds with a
#       precise finding instead of ~30 minutes later with an opaque
#       "no operating systems were found" (the OL7 2026-07-11 failure mode
#       this machinery was commissioned from).

_upstream_provenance_file() { printf '%s/upstream-provenance.txt' "${WORKSPACE}"; }

_record_upstream_provenance_clone() {
  local sha cdate subj f
  sha="$(git -C "${WORK_REPO_DIR}" rev-parse HEAD 2>/dev/null || echo unknown)"
  cdate="$(git -C "${WORK_REPO_DIR}" show -s --format=%ci HEAD 2>/dev/null || echo unknown)"
  subj="$(git -C "${WORK_REPO_DIR}" show -s --format=%s HEAD 2>/dev/null || echo unknown)"
  log_info "[OLAWS-UPSTREAM01] oracle-linux @ ${sha} (${cdate}; \"${subj}\")"
  f="$(_upstream_provenance_file)"
  {
    echo "# upstream provenance -- written by build-ol-aws-ami.sh on every build"
    echo "# (reproducibility record: upstream is tracked at HEAD by design, so a"
    echo "#  failing build must always leave behind WHAT it actually built from)"
    echo "generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "ol_major=${OL_MAJOR_VERSION}"
    echo "upstream_url=${OL_REPO_URL}"
    echo "upstream_head=${sha}"
    echo "upstream_head_date=${cdate}"
    echo "upstream_head_subject=${subj}"
  } > "${f}"
  log_info "  provenance file: ${f}"
}

_record_upstream_provenance_patched() {
  local f base a
  f="$(_upstream_provenance_file)"
  base="${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}"
  {
    # Applied wrapper markers, gathered from exactly the files this wrapper
    # patches (regex kept '['-anchored after PATCH so the t007 marker census
    # cannot pick this source line up as a phantom marker).
    echo "applied_patch_markers=$(grep -hoE 'ol-aws-ami-builder[^]]* PATCH [a-z0-9-]+' \
      "${base}/cloud/aws/provision.sh" "${base}/cloud/aws/image-scripts.sh" \
      "${base}"/distr/ol"${OL_MAJOR_VERSION}"-slim/* 2>/dev/null | sort -u | tr '\n' ';' || true)"
    for a in "${base}/distr/ol${OL_MAJOR_VERSION}-slim/ol${OL_MAJOR_VERSION}-ks.cfg" \
             "${base}/cloud/aws/provision.sh" \
             "${base}/distr/ol${OL_MAJOR_VERSION}-slim/image-scripts.sh"; do
      [[ -f "${a}" ]] && echo "artifact_sha256 $(sha256sum "${a}" 2>/dev/null || echo "unreadable  ${a}")"
    done
  } >> "${f}"
}

# _p3_validate_ks <ks_file> <ol_major>
# Structural conformance of the FINAL (patched / synthesized) kickstart.
# Returns the number of findings (0 = pass); logs each finding. Never dies --
# the gate driver decides. Self-contained bash (ADR 0003 spirit): this is the
# always-on gate; ksvalidator (when present) is ADVISORY ONLY because it exits
# 1 even on the pristine upstream kickstart (the pre-existing '--nobase'
# deprecation is counted), so its rc cannot gate without failing every build.
_p3_validate_ks() {
  local ks="$1" major="$2" fails=0 n inc
  if [[ ! -s "${ks}" ]]; then
    log_error "  [P3GATE] kickstart missing or empty: ${ks}"
    return 1
  fi
  if [[ "$(tr -d '\0' < "${ks}" | wc -c)" -ne "$(wc -c < "${ks}")" ]]; then
    log_error "  [P3GATE] kickstart contains NUL bytes (corrupt): ${ks}"
    fails=$((fails+1))
  fi
  n="$(grep -cE '^%packages' "${ks}" || true)"
  if [[ "${n}" -ne 1 ]]; then
    log_error "  [P3GATE] expected exactly 1 '%packages' section, found ${n}: ${ks}"
    fails=$((fails+1))
  fi
  n="$(grep -cE '^sos$' "${ks}" || true)"
  if [[ "${n}" -ne 1 ]]; then
    log_error "  [P3GATE] expected exactly 1 'sos' package line, found ${n}: ${ks}"
    fails=$((fails+1))
  elif ! awk '/^%packages/{inp=1;next} /^%/{inp=0} inp && $0=="sos"{ok=1} END{exit !ok}' "${ks}"; then
    log_error "  [P3GATE] 'sos' line is OUTSIDE the %packages section: ${ks}"
    fails=$((fails+1))
  fi
  if [[ "${major}" -ge 7 ]]; then
    n="$(grep -cF '[ol-aws-ami-builder PATCH sos-package]' "${ks}" || true)"
    if [[ "${n}" -ne 1 ]]; then
      log_error "  [P3GATE] expected exactly 1 sos-package marker, found ${n} (patch mis-applied?): ${ks}"
      fails=$((fails+1))
    fi
  fi
  # Section balance. Openers are ALL pykickstart section keywords -- %pre,
  # %pre-install, %post, %packages, %addon, %anaconda, %onerror, %traceback
  # -- each closed by exactly one '%end'; '%include' / '%ksappend' are NOT
  # sections (no '%end') and must not be counted. The original opener list
  # (packages|pre|post) was modeled on the OL7-era kickstart shape and
  # missed the '%addon com_redhat_kdump --disable' section that OL8/9/10
  # upstream kickstarts carry, failing every sound EL8-family artifact
  # ("3 openers vs 4 '%end'", first fired on the 2026-07-13 OL8 E2E).
  local n_sec n_end
  n_sec="$(grep -cE '^%(packages|pre-install|pre|post|addon|anaconda|onerror|traceback)([[:space:]]|$)' "${ks}" || true)"
  n_end="$(grep -cE '^%end$' "${ks}" || true)"
  if [[ "${major}" -eq 5 ]]; then
    # EL5/anaconda-11.1 predates '%end' entirely: a literal '%end' inside
    # %packages would be consumed as a PACKAGE NAME and fail the install, so
    # the OL5 shape is ZERO '%end' with exactly the synthesized %packages +
    # %post openers. (OS-separation: the balanced-%end rule below keeps
    # guarding OL6-10 unchanged.)
    if [[ "${n_end}" -ne 0 ]]; then
      log_error "  [P3GATE] OL5 kickstart must contain NO '%end' (anaconda-11.1 reads it as a package name); found ${n_end}: ${ks}"
      fails=$((fails+1))
    fi
    if [[ "${n_sec}" -ne 2 ]]; then
      log_error "  [P3GATE] OL5 kickstart must have exactly 2 section openers (%packages + %post), found ${n_sec}: ${ks}"
      fails=$((fails+1))
    fi
  elif [[ "${n_sec}" -ne "${n_end}" ]]; then
    log_error "  [P3GATE] unbalanced kickstart sections: ${n_sec} openers vs ${n_end} '%end': ${ks}"
    fails=$((fails+1))
  fi
  n="$(grep -cE '^bootloader' "${ks}" || true)"
  if [[ "${n}" -ne 1 ]]; then
    log_error "  [P3GATE] expected exactly 1 'bootloader' line, found ${n}: ${ks}"
    fails=$((fails+1))
  fi
  # Partitioning presence. OL6 (synthesized) / OL7 kickstarts carry static
  # '^part ' lines; OL8/9/10 upstream kickstarts carry NONE by design: their
  # %pre partitions the disk with parted and writes the generated 'part'
  # commands to a file that a '%include' pulls in (observed shape at
  # upstream cb0a65d3, unchanged since dab64a5 2025-02-20:
  # '%include /tmp/partitions-ks.cfg', written at the end of %pre). Accept
  # the dynamic shape only when BOTH halves are present -- the %include
  # line AND its exact target path appearing inside a %pre body -- so an
  # injection that eats either half still fails the gate loudly.
  n="$(grep -cE '^part ' "${ks}" || true)"
  if [[ "${n}" -lt 1 ]]; then
    inc="$(grep -m1 -E '^%include[[:space:]]+[^[:space:]]+' "${ks}" | awk '{print $2}' || true)"
    if [[ -z "${inc}" ]] || ! awk -v p="${inc}" \
         '/^%pre/{inp=1; next} /^%end$/{inp=0} inp && index($0, p){f=1} END{exit !f}' \
         "${ks}"; then
      log_error "  [P3GATE] no partitioning found (no static 'part' lines and no %pre-generated '%include' partition file): ${ks}"
      fails=$((fails+1))
    fi
  fi
  return "${fails}"
}

# _p3_validate_provision <provision_sh>
# The injected hooks must leave provision.sh syntactically valid, every
# '>>> [marker] >>>' bracket paired with its '<<<' twin, and every OLAWS_*
# single-quoted heredoc terminated. Returns the finding count; never dies.
_p3_validate_provision() {
  local prov="$1" fails=0 id n_open n_close tok
  if [[ ! -s "${prov}" ]]; then
    log_error "  [P3GATE] provision.sh missing or empty: ${prov}"
    return 1
  fi
  if ! bash -n "${prov}" 2>/dev/null; then
    log_error "  [P3GATE] provision.sh fails bash -n after hook injection: ${prov}"
    fails=$((fails+1))
  fi
  while IFS= read -r id; do
    [[ -n "${id}" ]] || continue
    n_open="$(grep -cF ">>> [${id}] >>>" "${prov}" || true)"
    n_close="$(grep -cF "<<< [${id}] <<<" "${prov}" || true)"
    if [[ "${n_open}" -ne "${n_close}" ]]; then
      log_error "  [P3GATE] unpaired hook brackets for '${id}': ${n_open} openers vs ${n_close} closers: ${prov}"
      fails=$((fails+1))
    fi
  done < <(grep -oE '>>> \[ol-aws-ami-builder[^]]* PATCH [a-z0-9-]+\] >>>' "${prov}" 2>/dev/null \
             | sed -E 's/^>>> \[//; s/\] >>>$//' | sort -u || true)
  while IFS= read -r tok; do
    [[ -n "${tok}" ]] || continue
    if ! grep -qE "^${tok}\$" "${prov}"; then
      log_error "  [P3GATE] heredoc '${tok}' has no terminator line: ${prov}"
      fails=$((fails+1))
    fi
  done < <(grep -oE "<<'OLAWS_[A-Z0-9_]+'" "${prov}" 2>/dev/null | sed -E "s/^<<'//; s/'$//" | sort -u || true)
  return "${fails}"
}

# _p3_exit_gate -- run at the very end of Phase 3, BEFORE any install work.
# Dies on any structural finding (a wrong artifact must cost seconds, not the
# ~30 minutes an opaque anaconda death costs); the die message carries the
# provenance file so the failing input is fully reproducible.
_p3_exit_gate() {
  local base ks prov imgs fails=0 advisory="ksvalidator not installed (structural-only)"
  base="${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}"
  ks="${base}/distr/ol${OL_MAJOR_VERSION}-slim/ol${OL_MAJOR_VERSION}-ks.cfg"
  prov="${base}/cloud/aws/provision.sh"
  imgs="${base}/distr/ol${OL_MAJOR_VERSION}-slim/image-scripts.sh"
  log_info "[OLAWS-P3GATE01] validating patched build artifacts (pre-install exit gate)"

  _p3_validate_ks "${ks}" "${OL_MAJOR_VERSION}" || fails=$((fails+$?))
  _p3_validate_provision "${prov}" || fails=$((fails+$?))
  if [[ -f "${imgs}" ]] && ! bash -n "${imgs}" 2>/dev/null; then
    log_error "  [P3GATE] image-scripts.sh fails bash -n: ${imgs}"
    fails=$((fails+1))
  fi

  # OL5 ONLY: bash-3.2 hostility scan of the GUEST-BOUND env concatenation.
  # First-contact lesson (2026-07-20): build-image.sh concatenates the env
  # files VERBATIM into provision.d/env.properties, which the EL5 guest's
  # bash 3.2 sources -- `declare -gA REPO` in upstream env.properties.defaults
  # killed provisioning at source time. The per-script scans (t025) cover
  # OUR templates; this gate covers the CHANNEL, so any future upstream
  # reintroduction dies here in seconds, not ~20 minutes into the build.
  # (env.properties.local is wrapper-generated plain KEY=VALUE and is
  # scanned separately right after generation in Phase 4.)
  if [[ "${OL_MAJOR_VERSION}" -eq 5 ]]; then
    local _envm _hostile
    for _envm in \
      "${base}/env.properties.defaults" \
      "${base}/distr/ol5-slim/env.properties" \
      "${base}/cloud/aws/env.properties" \
      "${base}/cloud/aws/ol5-slim/env.properties"; do
      [[ -f "${_envm}" ]] || continue
      if ! _hostile="$(_ol5_scan_bash32_hostile "${_envm}")"; then
        log_error "  [P3GATE] guest-bound env member contains bash-4-only construct(s) (EL5 guest sources this): ${_envm}"
        while IFS= read -r _l; do log_error "    ${_l}"; done <<< "${_hostile}"
        fails=$((fails+1))
      fi
    done
  fi

  # ADVISORY ksvalidator pass (never gates -- see _p3_validate_ks rationale).
  if command -v ksvalidator >/dev/null 2>&1; then
    local prof out
    case "${OL_MAJOR_VERSION}" in
      5) prof="RHEL5" ;; 6) prof="RHEL6" ;; 7) prof="RHEL7" ;; 8) prof="RHEL8" ;; 9) prof="RHEL9" ;; 10) prof="RHEL10" ;;
    esac
    out="$(ksvalidator -v "${prof}" "${ks}" 2>&1 || true)"
    if printf '%s' "${out}" | grep -qiE 'unknown.*version|invalid.*version'; then
      prof="RHEL9"
      out="$(ksvalidator -v "${prof}" "${ks}" 2>&1 || true)"
    fi
    advisory="ksvalidator advisory @ ${prof}"
    if [[ -n "${out}" ]]; then
      log_info "  [P3GATE][ksvalidator ${prof}] $(printf '%s' "${out}" | grep -vE '^\s*$|^Checking kickstart' | head -3 | tr '\n' ' | ')"
    fi
  fi

  if [[ "${fails}" -gt 0 ]]; then
    die "Phase-3 exit gate FAILED with ${fails} finding(s) -- the patched build
     artifacts are not sound, so the install is not started (a wrong artifact
     must cost seconds here, not ~30 opaque minutes in anaconda).
     Reproducibility record: $(_upstream_provenance_file)"
  fi
  log_info "[OLAWS-P3GATE01] PASS (structural; ${advisory})"
}

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

  # Reproducibility record FIRST (upstream tracked at HEAD by design): even a
  # build that dies later must leave behind exactly what it built from.
  _record_upstream_provenance_clone

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
      # ${WORKSPACE}/${VM_NAME} inside the single-quoted sed program are kept
      # literal on purpose: they must expand at build-image.sh runtime (its own
      # env), not at sed-injection time; single-quoting also protects the sed
      # metacharacters $| \n \&. See TESTING.md / SPEC D.17.
      # shellcheck disable=SC2016
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

  # Resolver-cleanup EROFS tolerance patch (bin/provision-common.sh; ALL
  # majors). Record #9 (2026-07-27, EC2-nested first contact): newer
  # guestfs-tools (e.g. the Fedora 44 host) bind-mount the APPLIANCE's
  # /etc/resolv.conf READ-ONLY over the guest's during virt-customize (that
  # is precisely why in-guest DNS works during provisioning) -- so upstream's
  # cleanup truncate `: > /etc/resolv.conf` dies with EROFS and takes the
  # whole provisioning down (both OL5 and OL6 died on this exact line).
  # Nothing is lost by tolerating it: under the bind-mount the guest file
  # was never written (nothing to clean), on older hosts the truncate still
  # runs, and build-image.sh independently ships the file clean via the
  # guestfs-API-level `--truncate /etc/resolv.conf` argument, which is not
  # subject to the chroot bind-mount.
  local provision_common_sh="${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}/bin/provision-common.sh"
  if [[ -f "${provision_common_sh}" ]]; then
    if grep -Fq '[ol-aws-ami-builder PATCH resolver-cleanup-erofs]' "${provision_common_sh}"; then
      log_info "  Resolver-cleanup EROFS patch already applied to ${provision_common_sh}"
    elif grep -Eq '^  : > /etc/resolv\.conf$' "${provision_common_sh}"; then
      log_info "Applying resolver-cleanup EROFS tolerance patch to upstream bin/provision-common.sh"
      sed -i.resolver-erofs.bak \
        -e 's|^  : > /etc/resolv\.conf$|  { : > /etc/resolv.conf; } 2>/dev/null \|\| common::echo_message "  [ol-aws-ami-builder PATCH resolver-cleanup-erofs] resolv.conf write skipped (read-only bind-mount; guestfs --truncate ships it clean)"|' \
        "${provision_common_sh}"
      if grep -Fq '[ol-aws-ami-builder PATCH resolver-cleanup-erofs]' "${provision_common_sh}"; then
        log_info "  -> resolver-cleanup EROFS patch applied (backup at ${provision_common_sh}.resolver-erofs.bak)"
      else
        die "Failed to apply resolver-cleanup EROFS patch to ${provision_common_sh}"
      fi
    else
      log_warn "  Upstream resolver-cleanup truncate not found in ${provision_common_sh}."
      log_warn "  Assuming the upstream cleanup has been refactored; verify EROFS tolerance manually."
    fi
  fi

  # Serial-console non-interactive patch v2 (bin/build-image.sh; ALL majors).
  #
  # Record #3 (2026-07-20): upstream adds `--wait/--noautoconsole` ONLY in
  # the SERIAL_CONSOLE=no branch; with yes it ATTACHES the console, which
  # never exits under this wrapper's piped stdio -> dead-wait until the
  # watchdog. Record #4 (2026-07-20, same day): the v1 fix backed ttyS0
  # with a FILE inside ${WORKSPACE} -- but under qemu:///system that file
  # is opened by QEMU (the qemu user) / managed by the confined libvirt
  # daemon, neither of which may CREATE files in a root-owned arbitrary
  # directory (DAC: no w on the dir; SELinux: default_t on custom paths
  # like /data) -> domain creation failed instantly and even the rollback
  # deletion was denied. Disks never hit this because they are
  # storage-pool volumes (libvirt labels/owns them); chardev files are
  # outside that machinery.
  #
  # v2 uses libvirt's NATIVE chardev logging instead: the device stays
  # `pty` (upstream-equivalent; `virsh console` from a second terminal
  # works), and a <log file=.../> element makes VIRTLOGD -- the root
  # daemon whose policy-native log directory is /var/log/libvirt/qemu --
  # write the complete serial output to
  # /var/log/libvirt/qemu/${VM_NAME}-install-serial.log (append=on).
  # Verified against real virt-install 4.1 (--print-xml:
  # <serial type="pty"><log file=... append="on"/>); the failing v1 DAC
  # composition was also reproduced before this change. Behavior with
  # SERIAL_CONSOLE=no is untouched. Marker-guarded + idempotent, with
  # v1->v2 upgrade handling (stale v1 lines are removed first).
  local build_image_serial="${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}/bin/build-image.sh"
  log_info "Applying serial-noninteractive patch to upstream bin/build-image.sh (SERIAL_CONSOLE=yes: file-backed ttyS0 + --wait, no console attach)"
  if [[ ! -f "${build_image_serial}" ]]; then
    die "Cannot apply serial-noninteractive patch: ${build_image_serial} not found"
  fi
  # shellcheck disable=SC2016
  if grep -Fq 'log.file=/var/log/libvirt/qemu' "${build_image_serial}"; then
    log_info "  -> serial-noninteractive patch v2 already present (idempotent skip)"
  else
    if grep -Fq '[ol-aws-ami-builder PATCH serial-noninteractive]' "${build_image_serial}"; then
      log_info "  -> stale v1 serial patch found (workspace reuse across wrapper versions); removing before applying v2"
      sed -i \
        -e '/\[ol-aws-ami-builder PATCH serial-noninteractive\]/d' \
        -e '/-install-serial\.log")$/d' \
        "${build_image_serial}"
    fi
    if grep -q 'BOOT_COMMAND+=( "${BOOT_COMMAND_SERIAL_CONSOLE\[@\]}" )' "${build_image_serial}"; then
      # shellcheck disable=SC2016
      sed -i".serial-noninteractive.bak" \
        -e '/BOOT_COMMAND+=( "${BOOT_COMMAND_SERIAL_CONSOLE\[@\]}" )/a\    # [ol-aws-ami-builder PATCH serial-noninteractive] non-interactive wrapper drive: never attach a console (hangs when stdio is piped); keep pty + virtlogd-managed <log> capture (policy-native /var/log/libvirt/qemu) and return via --wait like the "no" branch\n    virt_install_args+=(--wait "${INSTALL_WAIT_TIME}" --noautoconsole --serial "pty,log.file=/var/log/libvirt/qemu/${VM_NAME}-install-serial.log,log.append=on")' \
        "${build_image_serial}"
      if grep -Fq 'log.file=/var/log/libvirt/qemu' "${build_image_serial}"; then
        log_info "  -> serial-noninteractive patch v2 applied (backup at ${build_image_serial}.serial-noninteractive.bak)"
      else
        die "Failed to apply serial-noninteractive patch v2 to ${build_image_serial}"
      fi
    else
      log_warn "  Upstream serial-console BOOT_COMMAND line not found in ${build_image_serial}."
      log_warn "  Assuming upstream refactored it; SERIAL_CONSOLE=yes may hang under this wrapper (attached console)."
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

  # OL5 virt-install disk-bus patch (bin/build-image.sh).
  #
  # Upstream pins the build VM disk to virtio-scsi (bus=scsi). The EL5
  # installer kernel (2.6.18) has NO virtio-scsi driver (mainline 3.4+), so
  # anaconda would see no disk at all. It DOES have plain virtio-blk
  # (RHEL 5.3+ KVM-guest support), and the F1 payload probe confirmed UEK R2
  # ships the virtio set too -- so the minimal, period-correct fix is
  # bus=scsi -> bus=virtio for OL5 only (the unused virtio-scsi controller
  # device is harmless; the installed image never boots under qemu again --
  # provisioning is offline virt-customize). Marker-guarded + idempotent.
  if [[ "${OL_MAJOR_VERSION}" -eq 5 ]]; then
    local build_image_ol5="${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}/bin/build-image.sh"
    log_info "Applying OL5 virt-install disk-bus patch to upstream bin/build-image.sh (bus=scsi -> bus=virtio)"
    if [[ ! -f "${build_image_ol5}" ]]; then
      die "Cannot apply OL5 disk-bus patch: ${build_image_ol5} not found"
    fi
    if grep -Fq '[ol-aws-ami-builder OL5 disk-bus PATCH]' "${build_image_ol5}"; then
      log_info "  -> OL5 disk-bus patch already present (idempotent skip)"
    elif grep -q 'bus=scsi,cache=unsafe' "${build_image_ol5}"; then
      sed -i".ol5-diskbus.bak" \
        -e 's|bus=scsi,cache=unsafe|bus=virtio,cache=unsafe|' \
        -e '1a # [ol-aws-ami-builder OL5 disk-bus PATCH] virt-install disk bus=scsi -> bus=virtio (EL5 installer has no virtio-scsi; see build-ol-aws-ami.sh phase3)' \
        "${build_image_ol5}"
      if grep -q 'bus=virtio,cache=unsafe' "${build_image_ol5}"; then
        log_info "  -> OL5 disk-bus patch applied (backup at ${build_image_ol5}.ol5-diskbus.bak)"
      else
        die "Failed to apply OL5 disk-bus patch to ${build_image_ol5}"
      fi
    else
      log_warn "  Upstream 'bus=scsi,cache=unsafe' disk spec not found in ${build_image_ol5}."
      log_warn "  Assuming the upstream disk spec has been refactored; OL5 install may not see its disk."
    fi
  fi

  # OL5 env-defaults bash-3.2 patch (env.properties.defaults).
  #
  # First-contact finding (2026-07-20, real KVM run): upstream's
  # env.properties.defaults carries `declare -gA REPO` (bash 4.2+: global +
  # associative). build-image.sh concatenates that file VERBATIM into
  # provision.d/env.properties, which the GUEST's bash sources at provision
  # start -- on EL5 (bash 3.2) it dies with "declare: -g: invalid option"
  # before any provisioning runs. Guest-side code never uses REPO (verified
  # across bin/provision*.sh and cloud/aws/provision.sh), so the fix guards
  # the declaration by bash major: modern HOST bash still declares it
  # (semantics unchanged for the host-side kickstart repo machinery), the
  # EL5 guest skips it. `|| true` keeps the AND-list from tripping set -e.
  if [[ "${OL_MAJOR_VERSION}" -eq 5 ]]; then
    log_info "Applying OL5 bash-3.2 guard to upstream env.properties.defaults (declare -gA REPO)"
    _ol5_patch_env_defaults "${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}/env.properties.defaults"
  fi

  # OL5 host-supply executor + cloud:: overrides ([OLAWS-OL5S1] / [OLAWS-OL5S2]).
  #
  # EL5 has NO in-OS TLS 1.2 path (openssl 0.9.8e), so unlike OL6-10 the guest
  # can fetch nothing: every package beyond the ISO is staged by the HOST into
  # the synthesized distr/ol5-slim/files/ tree, which upstream build-image.sh
  # copies into provision.d/distr/ and virt-customize copies into the guest at
  # /tmp/provision.d/ (the standard files channel -- no upstream changes).
  #
  # Execution model: hook blocks appended to cloud/aws/provision.sh run at
  # SOURCE time (bin/provision.sh load_env), in file order. This block is
  # appended BEFORE the ENA/awscli hooks, so by the time those hooks invoke
  # their installers the toolchain, kernel-uek(+devel), the cloud-init 0.6.3
  # closure, gdisk, and the /usr/src source artifacts are already in place.
  #
  # Ordering INSIDE the block is load-bearing:
  #   (1) /etc/modprobe.conf aliases FIRST (scsi_hostadapter nvme + xen-blkfront,
  #       eth0 ena) -- the kernel-uek RPM %post runs new-kernel-pkg -> mkinitrd,
  #       which reads scsi_hostadapter aliases, so nvme is baked into the initrd
  #       by the package's own install;
  #   (2) DEFAULTKERNEL=kernel-uek BEFORE the transaction (the %post makes the
  #       new kernel the grub default);
  #   (3) one rpm -Uvh transaction over ALL staged RPMs (toolchain closure +
  #       kernel + cloud-init closure + fdisk/gdisk tooling);
  #   (4) stage /usr/src source artifacts (ena tarball, awscli zip);
  #   (5) assert: UEK kernel present, its initrd exists AND contains nvme.ko
  #       (remediate once via mkinitrd --with, then hard-fail), grub default
  #       entry boots el5uek, cloud-init installed.
  # Guest side is EL5 bash 3.2: POSIX constructs only (no ${var,,}, no mapfile).
  #
  # [OLAWS-OL5S2] then REDEFINES cloud::install_aws_packages / cloud::cloud_init
  # (bash: the later definition wins) -- the upstream bodies are yum/dracut
  # based and would abort on EL5; the overrides make them verify-only. The
  # upstream definitions become dead code that is never executed (their
  # bash-4-only expansions are harmless at parse time).
  if [[ "${OL_MAJOR_VERSION}" -eq 5 ]]; then
    local aws_provision_ol5="${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}/cloud/aws/provision.sh"
    log_info "Injecting OL5 host-supply executor + cloud:: overrides into cloud/aws/provision.sh"
    if [[ ! -f "${aws_provision_ol5}" ]]; then
      die "Cannot inject OL5 host-supply block: ${aws_provision_ol5} not found"
    fi
    if grep -Fq '[ol-aws-ami-builder PATCH ol5-host-supply]' "${aws_provision_ol5}"; then
      log_info "  -> OL5 host-supply block already present (idempotent skip)"
    else
      local ol5s1_body
      ol5s1_body="$(cat <<'OLAWS_OL5S1_BODY'
#!/bin/sh
# [OLAWS-OL5S1] OL5 host-supply executor (EL5 bash 3.2 safe; POSIX only).
# Runs at provision source time, before the ENA/awscli hooks.
set -e
PDIR="${PROVISION_DIR:-/tmp/provision.d}"
RPMDIR="${PDIR}/distr/rpms"
SRCDIR="${PDIR}/distr/src"
echo "[ol5-host-supply] begin (rpms=${RPMDIR} src=${SRCDIR})"

# (1) modprobe aliases BEFORE any kernel install (mkinitrd reads these).
touch /etc/modprobe.conf
grep -q '^alias scsi_hostadapter nvme$' /etc/modprobe.conf 2>/dev/null \
  || echo 'alias scsi_hostadapter nvme' >> /etc/modprobe.conf
grep -q '^alias scsi_hostadapter1 xen-blkfront$' /etc/modprobe.conf 2>/dev/null \
  || echo 'alias scsi_hostadapter1 xen-blkfront' >> /etc/modprobe.conf
grep -q '^alias eth0 ena$' /etc/modprobe.conf 2>/dev/null \
  || echo 'alias eth0 ena' >> /etc/modprobe.conf

# (2) UEK becomes the default kernel via the package's own %post.
if [ -f /etc/sysconfig/kernel ]; then
  sed -i -e 's/^DEFAULTKERNEL=.*/DEFAULTKERNEL=kernel-uek/' /etc/sysconfig/kernel
else
  echo 'DEFAULTKERNEL=kernel-uek' > /etc/sysconfig/kernel
fi

# (3) one transaction over every staged RPM (assert-all-then-write: verify the
# stage is non-empty and every file has the RPM lead magic BEFORE installing).
[ -d "${RPMDIR}" ] || { echo "[ol5-host-supply] FATAL: staged RPM dir missing: ${RPMDIR}"; exit 1; }
count=0
for f in "${RPMDIR}"/*.rpm; do
  [ -f "$f" ] || { echo "[ol5-host-supply] FATAL: no staged RPMs under ${RPMDIR}"; exit 1; }
  magic="$(od -An -N4 -tx1 "$f" 2>/dev/null | tr -d ' \n')"
  [ "$magic" = "edabeedb" ] || { echo "[ol5-host-supply] FATAL: not an RPM (bad lead magic): $f"; exit 1; }
  count=$((count+1))
done
echo "[ol5-host-supply] installing ${count} staged RPM(s)"
rpm -Uvh --replacepkgs "${RPMDIR}"/*.rpm || { echo "[ol5-host-supply] FATAL: rpm transaction failed"; exit 1; }

# (4) stage source artifacts for the ENA / awscli installers (an EMPTY src
# dir is legitimate under --skip-ena-driver + --skip-awscli).
[ -d "${SRCDIR}" ] || { echo "[ol5-host-supply] FATAL: staged src dir missing: ${SRCDIR}"; exit 1; }
for f in "${SRCDIR}"/*; do
  [ -f "$f" ] || continue
  cp -f "$f" /usr/src/ || { echo "[ol5-host-supply] FATAL: staging $f into /usr/src failed"; exit 1; }
done

# (5) kernel identity, non-target kernel removal, grub ownership, asserts.
#
# Record #8: the U11 media ALSO installs kernel-uek (2.6.39-400.215.10) at
# anaconda time, and the staged kernel's %post grubby fails in the appliance
# ("unable to find a suitable template") -- so the MEDIA kernel kept the grub
# default while the old assert only checked the el5uek SUBSTRING. The target
# kver is therefore derived from the STAGED rpm (authoritative), every other
# kernel is removed (OL-parity: upstream removes non-target kernels), and
# grub.conf is owned EXPLICITLY with an exact-kver default assert.
OL5_BOOT_DIR="${OL5_BOOT_DIR:-/boot}"
OL5_GRUB_CONF="${OL5_GRUB_CONF:-/boot/grub/grub.conf}"
kv=""
for f in "${RPMDIR}"/kernel-uek-2*.rpm; do
  [ -f "$f" ] || continue
  case "$f" in *-devel-*|*-firmware-*) continue ;; esac
  kv="$(basename "$f" | sed -e 's/^kernel-uek-//' -e 's/\.x86_64\.rpm$//')"
done
[ -n "$kv" ] || { echo "[ol5-host-supply] FATAL: staged kernel-uek rpm not found under ${RPMDIR}"; exit 1; }
[ -d "/lib/modules/${kv}" ] || { echo "[ol5-host-supply] FATAL: /lib/modules/${kv} missing after install"; exit 1; }
echo "[ol5-host-supply] UEK R2 kernel installed: ${kv}"

# Remove every OTHER installed kernel (the RHCK and the media UEK): a second
# kernel is a second -- wrong -- boot path. %preun grubby noise is expected;
# --noscripts is the deterministic fallback (grub.conf is owned below).
for n in kernel kernel-uek; do
  for p in $(rpm -q "$n" 2>/dev/null | grep -v 'not installed'); do
    [ "$p" = "kernel-uek-${kv}" ] && continue
    echo "[ol5-host-supply] removing non-target kernel: $p"
    rpm -e "$p" 2>/dev/null || rpm -e --noscripts "$p" \
      || { echo "[ol5-host-supply] FATAL: could not remove non-target kernel $p"; exit 1; }
  done
done

initrd="${OL5_BOOT_DIR}/initrd-${kv}.img"
check_initrd() { zcat "$1" 2>/dev/null | cpio -it 2>/dev/null | grep -q 'nvme\.ko'; }
if [ ! -f "${initrd}" ] || ! check_initrd "${initrd}"; then
  echo "[ol5-host-supply] initrd missing or lacks nvme.ko; regenerating with mkinitrd --with"
  mkinitrd --with=nvme --with=xen-blkfront -f "${initrd}" "${kv}" \
    || { echo "[ol5-host-supply] FATAL: mkinitrd regen failed"; exit 1; }
  check_initrd "${initrd}" || { echo "[ol5-host-supply] FATAL: initrd still lacks nvme.ko after regen"; exit 1; }
fi
echo "[ol5-host-supply] initrd contains nvme.ko: ${initrd}"

# grub.conf ownership (GRUB Legacy):
#   1. ensure an entry for ${kv} exists -- if absent, CLONE the current
#      default entry (layout-resilient: keeps its root/args shape) and
#      rewrite the vmlinuz/initrd versions;
#   2. prune title blocks whose vmlinuz no longer exists under /boot
#      (the kernels removed above);
#   3. point default= at the ${kv} entry;
#   4. assert EXACT kver equality (substring matching is what let the media
#      kernel keep the default -- record #8).
[ -f "${OL5_GRUB_CONF}" ] || { echo "[ol5-host-supply] FATAL: ${OL5_GRUB_CONF} not found"; exit 1; }
if ! grep -q "vmlinuz-${kv}\( \|$\)" "${OL5_GRUB_CONF}"; then
  echo "[ol5-host-supply] grub: no entry for ${kv}; cloning the current default entry"
  defblk="$(awk '
    /^default=/ { def = substr($0, 9) + 0 }
    /^title/    { t++ }
    { if (t > 0 && t - 1 == def) print }
  ' "${OL5_GRUB_CONF}")"
  [ -n "$defblk" ] || { echo "[ol5-host-supply] FATAL: could not extract the current grub default entry"; exit 1; }
  {
    echo "$defblk" | sed \
      -e "s/^title .*/title Oracle Linux Server (${kv})/" \
      -e "s!vmlinuz-[^ ]*!vmlinuz-${kv}!" \
      -e "s!initrd-[^ ]*\.img!initrd-${kv}.img!"
  } >> "${OL5_GRUB_CONF}"
fi
# prune entries whose vmlinuz is gone, and set default= to the ${kv} entry.
awk -v kv="${kv}" -v bootdir="${OL5_BOOT_DIR}" '
  function flush() {
    if (nblk == 0) return
    ver = blkver; keep = 0
    if (ver != "") {
      f = bootdir "/vmlinuz-" ver
      if ((getline _ < f) >= 0) keep = 1
      close(f)
    }
    if (keep) { blocks[++nb] = blk; vers[nb] = ver }
    nblk = 0; blk = ""; blkver = ""
  }
  /^title/ { flush(); nblk = 1; blk = $0; next }
  nblk { blk = blk "\n" $0
         if ($0 ~ /^[ \t]*kernel/) { v = $0; sub(/.*vmlinuz-/, "", v); sub(/ .*/, "", v); blkver = v }
         next }
  { hdr[++nh] = $0 }
  END {
    flush()
    defidx = -1
    for (i = 1; i <= nb; i++) if (vers[i] == kv) defidx = i - 1
    for (i = 1; i <= nh; i++) {
      if (hdr[i] ~ /^default=/) print "default=" defidx
      else print hdr[i]
    }
    for (i = 1; i <= nb; i++) print blocks[i]
    exit (defidx < 0 ? 1 : 0)
  }
' "${OL5_GRUB_CONF}" > "${OL5_GRUB_CONF}.new" \
  || { echo "[ol5-host-supply] FATAL: grub rewrite could not place a ${kv} entry"; exit 1; }
mv "${OL5_GRUB_CONF}.new" "${OL5_GRUB_CONF}"
# exact-kver default assert (the record-#8 invariant).
defver="$(awk '
  /^default=/ { def = substr($0, 9) + 0 }
  /^title/    { t++ }
  /^[ \t]*kernel/ { if (t - 1 == def) { v = $0; sub(/.*vmlinuz-/, "", v); sub(/ .*/, "", v); print v; exit } }
' "${OL5_GRUB_CONF}")"
[ "$defver" = "$kv" ] \
  || { echo "[ol5-host-supply] FATAL: grub default boots ${defver:-<none>}, not the staged ${kv}"; exit 1; }
grep -q "initrd-${kv}\.img" "${OL5_GRUB_CONF}" \
  || { echo "[ol5-host-supply] FATAL: grub ${kv} entry has no initrd-${kv}.img line"; exit 1; }
echo "[ol5-host-supply] grub default boots the staged kernel: ${kv}"
rpm -q cloud-init >/dev/null 2>&1 || { echo "[ol5-host-supply] FATAL: cloud-init not installed by the staged closure"; exit 1; }
echo "[ol5-host-supply] cloud-init installed: $(rpm -q cloud-init)"
echo "[ol5-host-supply] done"
OLAWS_OL5S1_BODY
)"
      {
        printf '\n# >>> [ol-aws-ami-builder PATCH ol5-host-supply] >>>\n'
        printf "cat > /usr/local/sbin/ol-aws-ol5-host-supply.sh <<'OLAWS_OL5S1_EOF'\n"
        printf '%s\n' "${ol5s1_body}"
        printf 'OLAWS_OL5S1_EOF\n'
        printf 'chmod +x /usr/local/sbin/ol-aws-ol5-host-supply.sh\n'
        printf 'sh /usr/local/sbin/ol-aws-ol5-host-supply.sh\n'
        printf '# [OLAWS-OL5S2] EL5-safe overrides: the LATER definition wins in bash, so\n'
        printf '# these replace the upstream yum/dracut-based bodies (never executed on OL5).\n'
        printf 'cloud::install_aws_packages() {\n'
        printf '  common::echo_message "OL5: kernel/driver packages are HOST-staged ([OLAWS-OL5S1]); upstream kernel-uek-modules/dracut path skipped"\n'
        printf '}\n'
        printf 'cloud::cloud_init() {\n'
        printf '  common::echo_message "OL5: cloud-init 0.6.3 (EPEL5) came from the host-staged closure ([OLAWS-OL5S1]); verify-only"\n'
        printf '  rpm -q cloud-init >/dev/null 2>&1 || { echo "FATAL: cloud-init missing at cloud::cloud_init"; exit 1; }\n'
        printf '  # Keep the 0.6.3 upstream defaults: user ec2-user / disable_root 1.\n'
        printf '  # (system_info/default_user + 90_ol.cfg are 0.7.x concepts -- not written.)\n'
        printf '}\n'
        printf '# <<< [ol-aws-ami-builder PATCH ol5-host-supply] <<<\n'
      } >> "${aws_provision_ol5}"
      if grep -Fq '[ol-aws-ami-builder PATCH ol5-host-supply]' "${aws_provision_ol5}"; then
        log_info "  [OLAWS-OL5S1] OL5 host-supply executor injected (modprobe aliases -> DEFAULTKERNEL -> rpm transaction -> /usr/src staging -> initrd/grub/cloud-init asserts)"
        log_info "  [OLAWS-OL5S2] cloud::install_aws_packages / cloud::cloud_init overridden with EL5-safe verify-only bodies"
      else
        die "Failed to inject OL5 host-supply block into ${aws_provision_ol5}"
      fi
    fi
  fi

  # cloud/aws/provision.sh Nitro initramfs-drivers hook (ALWAYS on).
  #
  # OL5 EXCEPTION (OS-separation): EL5 has no dracut at all -- initrd handling
  # on OL5 is owned end-to-end by the OL5 host-supply block ([OLAWS-OL5S1]:
  # modprobe.conf scsi_hostadapter aliases written BEFORE the kernel-uek RPM
  # install so its %post mkinitrd bakes nvme in, plus an explicit mkinitrd
  # regen + content assert). Injecting this dracut-based hook on OL5 would
  # only write an inert (or, worse, misleading) /etc/dracut.conf.d drop-in.
  #
  # Forcing nvme + ena into the initramfs is a Nitro BOOT requirement (the root
  # is NVMe-backed), independent of the ENA driver *version* and of
  # --skip-ena-driver: even a pure OL AMI must boot on Nitro. dracut runs in
  # hostonly mode on the non-NVMe build VM (root on virtio /dev/sda), so it
  # omits nvme from the initramfs -- observed on OL7 (UEK R6): nvme.ko was on
  # disk but absent from the initramfs, so the image could not mount its root on
  # Nitro (Phase 6 CHECK 1 correctly FAILed). We drop an /etc/dracut.conf.d
  # add_drivers file (persists across in-instance kernel updates) and regenerate
  # the initramfs for the installed kernel. Best-effort: it never aborts the
  # build (CHECK 1 verifies the result). Idempotent via the wrapper marker.
  local aws_provision="${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}/cloud/aws/provision.sh"
  local nitro_body
  nitro_body="$(cat <<'OLAWS_NITRO_BODY'
#!/bin/sh
# Ensure Nitro-essential drivers are present in the initramfs.
# Targets the installed kernel (highest UEK under /lib/modules); `uname -r` is
# the libguestfs appliance kernel during provisioning, so it is not used.
# PRESENCE-AWARE: only drivers whose .ko exists for the target kernel enter the
# dracut drop-in at this stage. On the slim OL8/9/10 builds the in-box ena is
# not on disk at this (source-time, pre-DKMS) stage -- observed in the
# 2026-07-13 build logs; it ships in kernel-uek-modules, which is not staged
# at this point -- so ena is legitimately absent here; the ENA self-build
# hook appends `ena` to the same drop-in after the DKMS install and its own
# dracut regen bakes it in. Forcing an absent driver instead made this hook's
# dracut FAIL ("Failed to find module 'ena'") and, on --skip-ena-driver
# builds, left a drop-in that breaks every future in-instance dracut run.
set -u
kver=""
for d in /lib/modules/*uek*/ ; do
  [ -d "$d" ] || continue
  b=${d%/}; b=${b##*/}
  if [ -z "$kver" ] || [ "$(printf '%s\n%s\n' "$kver" "$b" | sort -V | tail -1)" = "$b" ]; then
    kver="$b"
  fi
done
[ -n "$kver" ] || { echo "[nitro-initramfs] no UEK kernel under /lib/modules; skipping"; exit 0; }
present=""
deferred=""
for drv in nvme nvme-core ena; do
  if [ -n "$(find "/lib/modules/${kver}" -name "${drv}.ko*" -print 2>/dev/null | head -1)" ]; then
    present="${present} ${drv}"
  else
    deferred="${deferred} ${drv}"
  fi
done
mkdir -p /etc/dracut.conf.d
if [ -n "$present" ]; then
  printf 'add_drivers+="%s "\n' "${present}" > /etc/dracut.conf.d/02-ol-aws-nitro.conf
  echo "[nitro-initramfs] drop-in drivers:${present}"
else
  echo "[nitro-initramfs] no target drivers present for $kver; no drop-in written"
fi
if [ -n "$deferred" ]; then
  echo "[nitro-initramfs] not present for $kver, deferred:${deferred} (expected for ena on slim OL8/9/10 -- the ENA self-build hook appends it after the DKMS install)"
fi
if command -v dracut >/dev/null 2>&1; then
  echo "[nitro-initramfs] regenerating initramfs for $kver (force${present:-: nothing})"
  dracut -f "/boot/initramfs-${kver}.img" "$kver" || echo "[nitro-initramfs] WARNING: dracut -f failed for $kver"
else
  echo "[nitro-initramfs] dracut not found; wrote dracut.conf.d drop-in only"
fi
exit 0
OLAWS_NITRO_BODY
)"
  if [[ "${OL_MAJOR_VERSION}" -eq 5 ]]; then
    log_info "Nitro initramfs-drivers hook NOT injected on OL5 (no dracut on EL5; initrd/nvme handling is owned by the [OLAWS-OL5S1] host-supply block)"
  elif [[ -f "${aws_provision}" ]]; then
    if grep -Fq '[ol-aws-ami-builder PATCH nitro-initramfs]' "${aws_provision}"; then
      log_info "Nitro initramfs-drivers hook already present (idempotent skip)"
    else
      log_info "Injecting Nitro initramfs-drivers hook into cloud/aws/provision.sh (force nvme/ena; boot requirement)"
      {
        printf '\n# >>> [ol-aws-ami-builder PATCH nitro-initramfs] >>>\n'
        printf "cat > /usr/local/sbin/ol-aws-nitro-initramfs.sh <<'OLAWS_NITRO_INITRAMFS_EOF'\n"
        printf '%s\n' "${nitro_body}"
        printf 'OLAWS_NITRO_INITRAMFS_EOF\n'
        printf 'sh /usr/local/sbin/ol-aws-nitro-initramfs.sh\n'
        printf '# <<< [ol-aws-ami-builder PATCH nitro-initramfs] <<<\n'
      } >> "${aws_provision}"
      if grep -Fq '[ol-aws-ami-builder PATCH nitro-initramfs]' "${aws_provision}"; then
        log_info "  [OLAWS-NVM01] Nitro initramfs-drivers hook injected (presence-aware add_drivers + dracut -f; ena deferred to the ENA hook when not in-box)"
      else
        die "Failed to inject Nitro initramfs-drivers hook into ${aws_provision}"
      fi
    fi
  else
    log_warn "cloud/aws/provision.sh not found; skipping Nitro initramfs-drivers hook"
  fi

  # cloud/aws/provision.sh serial-console hook (GRUB2 / OL7+).
  #
  # AWS 'Get System Log' (the instance console) only captures output sent to the
  # serial port ttyS0; the interactive EC2 Serial Console additionally needs GRUB
  # and a login getty on that port. The upstream OL7+ config carries console=tty0
  # but NOT console=ttyS0, so a built AMI boots fine yet the console log is empty
  # -- which is exactly what made the OL6 SSH failure (D.24) so hard to debug.
  # This hook applies the AWS-recommended serial-console config in THREE layers:
  #   (1) kernel cmdline 'console=tty0 console=ttyS0,115200n8' on EVERY existing
  #       boot entry via `grubby --update-kernel=ALL` -- the BLS-aware, version-
  #       stable path. On OL8+ the kernel cmdline lives in /boot/loader/entries
  #       (BLS), which a plain grub2-mkconfig does NOT rewrite (this is why OL8/9/10
  #       previously came up without ttyS0); grubby updates those entries directly,
  #       so we avoid the grub2-mkconfig --update-bls-cmdline version matrix (flag
  #       needed on 8.x/9.0-9.1, dropped on 9.2+). GRUB_CMDLINE_LINUX is also set so
  #       future kernel installs inherit it.
  #   (2) GRUB-over-serial: GRUB_TERMINAL="console serial" + GRUB_SERIAL_COMMAND so
  #       the interactive EC2 Serial Console reaches the GRUB menu/prompt.
  #   (3) serial-getty@ttyS0 enabled (a login prompt on the serial console).
  # GUARDED on /etc/default/grub, which exists only on GRUB2 (OL7+); on OL6 (GRUB
  # Legacy) it is a no-op, so OL6's own kickstart handles its serial console
  # (per-OS isolation -- an OL7+ change cannot regress OL6, and vice-versa).
  # Idempotent via the marker and per-layer guards.
  local serial_body
  serial_body="$(cat <<'OLAWS_SERIAL_BODY'
#!/bin/sh
# AWS-optimized serial console for GRUB2 systems (OL7+). Three layers:
#   (1) kernel cmdline 'console=tty0 console=ttyS0,115200n8' on EVERY boot entry
#       (Get System Log + serial getty attach here) -- via grubby (BLS-aware).
#   (2) GRUB-over-serial (GRUB_TERMINAL/GRUB_SERIAL_COMMAND).
#   (3) serial-getty@ttyS0 enabled.
# GRUB2 only (guarded on /etc/default/grub); OL6 handles its own in the kickstart.
set -u
[ -f /etc/default/grub ] || { echo "[serial-console] no /etc/default/grub (GRUB Legacy?); skipping"; exit 0; }

# --- (1) kernel cmdline ----------------------------------------------------
# GRUB_CMDLINE_LINUX governs FUTURE kernel installs.
if grep -q 'console=ttyS0' /etc/default/grub; then
  echo "[serial-console] console=ttyS0 already present in /etc/default/grub"
else
  sed -i -e 's/\(GRUB_CMDLINE_LINUX="[^"]*\)"/\1 console=ttyS0,115200n8"/' /etc/default/grub
  grep -q 'console=tty0' /etc/default/grub || \
    sed -i -e 's/\(GRUB_CMDLINE_LINUX="\)/\1console=tty0 /' /etc/default/grub
  echo "[serial-console] added console=ttyS0,115200n8 to GRUB_CMDLINE_LINUX (future kernels)"
fi
# grubby updates EXISTING entries directly -- the part grub2-mkconfig does NOT do
# on BLS (OL8+: entries in /boot/loader/entries). Version-stable across OL7-10.
if command -v grubby >/dev/null 2>&1; then
  if grubby --update-kernel=ALL --args="console=tty0 console=ttyS0,115200n8"; then
    echo "[serial-console] grubby: applied console=ttyS0 to ALL existing kernels"
  else
    echo "[serial-console] WARNING: grubby --update-kernel=ALL failed"
  fi
else
  echo "[serial-console] WARNING: grubby not found; relying on GRUB_CMDLINE_LINUX + grub2-mkconfig"
fi

# --- (2) GRUB-over-serial (interactive EC2 Serial Console) -----------------
# GRUB_TERMINAL supersedes GRUB_TERMINAL_OUTPUT; drop the latter to avoid conflict.
sed -i -e '/^GRUB_TERMINAL_OUTPUT=/d' /etc/default/grub
if grep -q '^GRUB_TERMINAL=' /etc/default/grub; then
  sed -i -e 's/^GRUB_TERMINAL=.*/GRUB_TERMINAL="console serial"/' /etc/default/grub
else
  printf 'GRUB_TERMINAL="console serial"\n' >> /etc/default/grub
fi
if grep -q '^GRUB_SERIAL_COMMAND=' /etc/default/grub; then
  sed -i -e 's/^GRUB_SERIAL_COMMAND=.*/GRUB_SERIAL_COMMAND="serial --speed=115200"/' /etc/default/grub
else
  printf 'GRUB_SERIAL_COMMAND="serial --speed=115200"\n' >> /etc/default/grub
fi
echo "[serial-console] set GRUB_TERMINAL/GRUB_SERIAL_COMMAND (GRUB-over-serial)"

# --- regenerate grub.cfg (embeds (2); on non-BLS also re-embeds (1)) --------
if [ -d /sys/firmware/efi ] && [ -f /boot/efi/EFI/redhat/grub.cfg ]; then
  grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg || echo "[serial-console] WARNING: grub2-mkconfig (EFI) failed"
elif [ -f /boot/grub2/grub.cfg ]; then
  grub2-mkconfig -o /boot/grub2/grub.cfg || echo "[serial-console] WARNING: grub2-mkconfig failed"
else
  echo "[serial-console] WARNING: no grub2.cfg found to regenerate"
fi

# --- (3) serial getty (login prompt on ttyS0) ------------------------------
# systemd auto-spawns serial-getty for the console= device; enable it explicitly
# for determinism. Offline (virt-customize) 'systemctl enable' may no-op under
# chroot detection, so fall back to the symlink it would create.
if command -v systemctl >/dev/null 2>&1; then
  systemctl enable serial-getty@ttyS0.service >/dev/null 2>&1 || {
    mkdir -p /etc/systemd/system/getty.target.wants
    ln -sf /usr/lib/systemd/system/serial-getty@.service \
           /etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service
  }
  if [ -e /etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service ]; then
    echo "[serial-console] serial-getty@ttyS0 enabled"
  else
    echo "[serial-console] WARNING: could not enable serial-getty@ttyS0"
  fi
fi
exit 0
OLAWS_SERIAL_BODY
)"
  if [[ -f "${aws_provision}" ]]; then
    if grep -Fq '[ol-aws-ami-builder PATCH serial-console]' "${aws_provision}"; then
      log_info "Serial-console hook already present (idempotent skip)"
    else
      log_info "Injecting serial-console hook into cloud/aws/provision.sh (GRUB2/OL7+; ensures ttyS0 for Get System Log)"
      {
        printf '\n# >>> [ol-aws-ami-builder PATCH serial-console] >>>\n'
        printf "cat > /usr/local/sbin/ol-aws-serial-console.sh <<'OLAWS_SERIAL_CONSOLE_EOF'\n"
        printf '%s\n' "${serial_body}"
        printf 'OLAWS_SERIAL_CONSOLE_EOF\n'
        printf 'sh /usr/local/sbin/ol-aws-serial-console.sh\n'
        printf '# <<< [ol-aws-ami-builder PATCH serial-console] <<<\n'
      } >> "${aws_provision}"
      if grep -Fq '[ol-aws-ami-builder PATCH serial-console]' "${aws_provision}"; then
        log_info "  [OLAWS-CON01] serial-console hook injected (grubby --update-kernel=ALL console=ttyS0 + GRUB_TERMINAL/SERIAL + serial-getty@ttyS0)"
      else
        die "Failed to inject serial-console hook into ${aws_provision}"
      fi
    fi
  else
    log_warn "cloud/aws/provision.sh not found; skipping serial-console hook"
  fi

  # cloud/aws/provision.sh OL6 cloud-init default-user hook (OL6 only).
  #
  # Two actions on cloud-init's default_user configuration:
  #   (1) FIX (functional): drop the systemd-journal supplementary group. The
  #       upstream cloud/aws provisioning writes /etc/cloud/cloud.cfg.d/90_ol.cfg
  #       with default_user.groups = [adm, systemd-journal] for every OL version,
  #       and cloud-init 0.7.5 merges cloud.cfg.d over the main cloud.cfg with the
  #       drop-in winning, so 90_ol.cfg is the effective default_user on OL6. OL6
  #       has no systemd, so the systemd-journal group does not exist; cloud-init's
  #       `useradd --groups adm,systemd-journal ec2-user` then fails ("group
  #       'systemd-journal' does not exist"), the default user (ec2-user) is never
  #       created, and the EC2 SSH key is never applied -> no SSH access.
  #   (2) CLARITY (no functional effect): align default_user.name to CLOUD_USER
  #       (ec2-user) in the main /etc/cloud/cloud.cfg too. 90_ol.cfg already sets
  #       the name to ec2-user and wins the merge, so the created account is
  #       ec2-user regardless and 'cloud-user' is never instantiated; but the
  #       stock cloud.cfg still literally reads `name: cloud-user`, which misleads
  #       an operator inspecting the built image. Aligning it removes that
  #       confusion. Verified no-op (both files resolve to ec2-user).
  # OL7+ are untouched (their systemd-journal group exists -- per-OS isolation).
  # Self-guards on /etc/oracle-release; idempotent. TIMING: the hook MUST run after
  # cloud-init is installed and 90_ol.cfg is written. bin/provision.sh SOURCES
  # cloud/aws/provision.sh (executing any top-level code) during load_env, BEFORE it
  # calls cloud::provision -> cloud::cloud_init (which installs cloud-init and writes
  # the configs). So the hook is wired by WRAPPING cloud::cloud_init -- a top-level
  # "sh ..." appended here would run at source time, before the config files exist,
  # and silently skip ("no cloud-init config found"), which is why earlier revisions
  # of this hook never actually applied.
  if [[ "${OL_MAJOR_VERSION}" -eq 6 ]]; then
    local cloud_user_body
    cloud_user_body="$(cat <<'OLAWS_OL6_CLOUD_USER_BODY'
#!/bin/sh
# OL6 only: (1) drop the OL6-absent systemd-journal group from default_user.groups
# so useradd succeeds and ec2-user (with the EC2 SSH key) is created; (2) align
# default_user.name to ec2-user in the stock cloud.cfg too, so the shipped config
# does not show a misleading 'cloud-user' (90_ol.cfg already wins the merge -- (2)
# is clarity only, a verified no-op).
set -u
case "$(cat /etc/oracle-release 2>/dev/null)" in
  *"release 6"*) : ;;
  *) echo "[ol6-cloud-user] not OL6; skipping"; exit 0 ;;
esac
want="${CLOUD_USER:-ec2-user}"
found=0
for cfg in /etc/cloud/cloud.cfg /etc/cloud/cloud.cfg.d/90_ol.cfg; do
  [ -f "$cfg" ] || continue
  found=1
  # (2) clarity: align default_user.name to want, within the default_user: block.
  if grep -qE "^[[:space:]]+name:[[:space:]]*${want}[[:space:]]*\$" "$cfg"; then
    echo "[ol6-cloud-user] ${cfg}: default_user name already ${want}"
  else
    sed -i -E "/^[[:space:]]*default_user:[[:space:]]*\$/,/^[^[:space:]#]/ s/^([[:space:]]+name:)[[:space:]]*.*/\1 ${want}/" "$cfg"
    echo "[ol6-cloud-user] ${cfg}: aligned default_user name to ${want}"
  fi
  # (1) fix: drop the non-existent systemd-journal group (scoped to groups: line).
  if grep -qE '^[[:space:]]*groups:.*systemd-journal' "$cfg"; then
    sed -i -E '/^[[:space:]]*groups:/ { s/systemd-journal[[:space:]]*,[[:space:]]*//g; s/[[:space:]]*,[[:space:]]*systemd-journal//g; s/systemd-journal//g }' "$cfg"
    echo "[ol6-cloud-user] ${cfg}: removed non-existent group systemd-journal from default_user groups"
  fi
done
[ "$found" = 1 ] || echo "[ol6-cloud-user] no cloud-init config found; skipping"
exit 0
OLAWS_OL6_CLOUD_USER_BODY
)"
    if [[ -f "${aws_provision}" ]]; then
      if grep -Fq '[ol-aws-ami-builder PATCH ol6-cloud-user]' "${aws_provision}"; then
        log_info "OL6 cloud-init default-user hook already present (idempotent skip)"
      else
        log_info "Injecting OL6 cloud-init default-user hook into cloud/aws/provision.sh (drop systemd-journal group; align name to ec2-user)"
        # The $(...), ${...} and "$@" below are deliberately left literal: they
        # are emitted verbatim into cloud/aws/provision.sh, where they expand at
        # runtime (declare -f / wrap), not in this wrapper.
        # shellcheck disable=SC2016
        {
          printf '\n# >>> [ol-aws-ami-builder PATCH ol6-cloud-user] >>>\n'
          printf "cat > /usr/local/sbin/ol-aws-ol6-cloud-user.sh <<'OLAWS_OL6_CLOUD_USER_EOF'\n"
          printf '%s\n' "${cloud_user_body}"
          printf 'OLAWS_OL6_CLOUD_USER_EOF\n'
          # Wire the hook to run AFTER cloud-init is installed and 90_ol.cfg is
          # written, by wrapping cloud::cloud_init. bin/provision.sh sources this
          # file (running top-level code) before it calls cloud::cloud_init, so a
          # top-level "sh ..." would run too early and skip; wrapping defers it to
          # immediately after the original cloud_init writes the config.
          printf 'if declare -f cloud::cloud_init >/dev/null 2>&1; then\n'
          printf '  eval "olaws::__orig_cloud_init() $(declare -f cloud::cloud_init | tail -n +2)"\n'
          printf '  cloud::cloud_init() { olaws::__orig_cloud_init "$@"; CLOUD_USER="${CLOUD_USER:-ec2-user}" sh /usr/local/sbin/ol-aws-ol6-cloud-user.sh; }\n'
          printf 'else\n'
          printf '  echo "[ol6-cloud-user] ERROR: cloud::cloud_init not found; hook not wired" >&2\n'
          printf 'fi\n'
          printf '# <<< [ol-aws-ami-builder PATCH ol6-cloud-user] <<<\n'
        } >> "${aws_provision}"
        if grep -Fq '[ol-aws-ami-builder PATCH ol6-cloud-user]' "${aws_provision}"; then
          log_info "  [OLAWS-USR01] OL6 cloud-init default-user hook injected (drop systemd-journal group; align name to ec2-user)"
        else
          die "Failed to inject OL6 cloud-init default-user hook into ${aws_provision}"
        fi
      fi
    else
      log_warn "cloud/aws/provision.sh not found; skipping OL6 cloud-init default-user hook"
    fi
  fi

  # cloud/aws/provision.sh ENA driver self-build hook.
  #
  # Default ON: append a hook to the AWS-cloud provisioning script that builds
  # and installs a pinned Amazon ENA driver inside the guest (AWS-optimized
  # AMI). The wrapper's --skip-ena-driver switch leaves the hook out, producing
  # a pure, unmodified OL AMI -- the two distinct build purposes.
  #
  # The hook writes our install-ena-driver.sh verbatim into the guest and runs
  # it during provisioning. It is injected for OL6/OL7 only: OL8+ keep their
  # current in-distro ENA driver in the AMI (the standalone install-ena-driver.sh
  # can still build OL8 on demand, but the pipeline does not). The installer
  # detects the installed UEK kernel from /lib/modules (provisioning runs under a
  # libguestfs appliance, so `uname -r` is the appliance kernel), and builds via
  # DKMS against that kernel. The embedded heredoc is single-quoted, so the
  # installer's own text (including its '\${kernelver}') is written through
  # unmodified.
  #
  # Idempotent via the wrapper marker so a Phase 3 re-run does not double-append.
  if [[ "${ENA_DRIVER_BUILD}" -ne 1 ]]; then
    log_info "ENA driver self-build disabled (--skip-ena-driver); producing a pure OL AMI"
  else
    local aws_provision_ena="${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}/cloud/aws/provision.sh"
    local ena_installer="${SCRIPT_DIR}/install-ena-driver.sh"
    log_info "Injecting ENA driver self-build hook into cloud/aws/provision.sh (AWS-optimized AMI; --skip-ena-driver disables)"

    if [[ ! -f "${aws_provision_ena}" ]]; then
      die "Cannot inject ENA driver hook: ${aws_provision_ena} not found"
    fi
    if [[ ! -f "${ena_installer}" ]]; then
      die "Cannot inject ENA driver hook: installer not found at ${ena_installer}"
    fi

    if grep -Fq '[ol-aws-ami-builder PATCH ena-driver-build]' "${aws_provision_ena}"; then
      log_info "  -> ENA driver hook already present (idempotent skip)"
    else
      # On the latest-resolving majors (OL8/9/10 -- empty installer pin) the
      # host-resolved ENA_BUILD_VERSION ([OLAWS-ENA02]) is passed into the guest
      # as ENA_DRIVER_VERSION, so the guest builds exactly the version the AMI
      # name/description declares (no name<->artifact drift, and no second
      # in-guest latest resolution). The pinned majors (OL6/OL7) run the
      # installer bare -- its own pin IS the resolved version.
      local _ena_hook_invoke='/usr/local/sbin/ol-aws-install-ena-driver.sh'
      # A USER PIN (ENA_USER_PIN, load_env) is passed on EVERY major -- it
      # must override even the pinned installers on OL6/OL7, or the name
      # would carry the user pin while the guest built the installer pin.
      if [[ "${ENA_USER_PIN}" -eq 1 || ( -z "$(_ena_pin_for_major "${OL_MAJOR_VERSION}")" && -n "${ENA_BUILD_VERSION}" ) ]]; then
        _ena_hook_invoke="ENA_DRIVER_VERSION=${ENA_BUILD_VERSION} /usr/local/sbin/ol-aws-install-ena-driver.sh"
      fi
      {
        printf '\n# >>> [ol-aws-ami-builder PATCH ena-driver-build] >>>\n'
        printf '# Build & install a pinned Amazon ENA driver in the guest (AWS-optimized AMI).\n'
        printf '# Pure-OL builds omit this hook via the wrapper'"'"'s --skip-ena-driver switch.\n'
        printf "cat > /usr/local/sbin/ol-aws-install-ena-driver.sh <<'OLAWS_ENA_INSTALLER_EOF'\n"
        cat "${ena_installer}"
        printf 'OLAWS_ENA_INSTALLER_EOF\n'
        printf 'chmod +x /usr/local/sbin/ol-aws-install-ena-driver.sh\n'
        printf '# The presence-aware nitro-initramfs hook only forces drivers that exist at\n'
        printf '# its (earlier) stage; ena arrives via the DKMS build below. Add ena to the\n'
        printf '# shared drop-in NOW (idempotent) so the installer'"'"'s own dracut regen bakes\n'
        printf '# it into the initramfs and in-instance kernel updates keep it.\n'
        if [[ "${OL_MAJOR_VERSION}" -ne 5 ]]; then
          printf '%s\n' 'mkdir -p /etc/dracut.conf.d'
          printf '%s\n' 'grep -qsw ena /etc/dracut.conf.d/02-ol-aws-nitro.conf || printf '\''add_drivers+=" ena "\n'\'' >> /etc/dracut.conf.d/02-ol-aws-nitro.conf'
        else
          printf '%s\n' '# (OL5: no dracut on EL5 -- the drop-in is omitted; ena loads via the modprobe.conf alias written by [OLAWS-OL5S1], and nvme is baked into the initrd by mkinitrd)'
        fi
        printf '%s\n' "${_ena_hook_invoke}"
        printf '# <<< [ol-aws-ami-builder PATCH ena-driver-build] <<<\n'
      } >> "${aws_provision_ena}"

      if grep -Fq '[ol-aws-ami-builder PATCH ena-driver-build]' "${aws_provision_ena}"; then
        local ena_build_kind="in-guest DKMS build"
        [[ "${OL_MAJOR_VERSION}" -eq 5 ]] && ena_build_kind="in-guest plain-make build (no DKMS on EL5)"
        log_info "  [OLAWS-ENA01] ENA driver hook injected (target: OL${OL_MAJOR_VERSION} ${ENA_BUILD_VERSION:-$(_ena_pin_for_major "${OL_MAJOR_VERSION}")}; ${ena_build_kind})"
      else
        die "Failed to inject ENA driver hook into ${aws_provision_ena}"
      fi
    fi
  fi

  # distr/ol{N}-slim kickstart: bake sosreport tooling (sos) into %packages
  # (OL7-OL10; every AMI can produce a sosreport out of the box instead of
  # needing a manual install on each instance first). OL6 is skipped here:
  # its kickstart is synthesized by this wrapper and already lists sos.
  if [[ "${OL_MAJOR_VERSION}" -ge 7 ]]; then
    local distr_ks="${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}/distr/ol${OL_MAJOR_VERSION}-slim/ol${OL_MAJOR_VERSION}-ks.cfg"
    log_info "Adding sos package to upstream kickstart (OL${OL_MAJOR_VERSION})"
    _ks_add_sos_package "${distr_ks}"
  fi

  # cloud/aws/provision.sh SSM Agent install hook (default ON; OL6-OL10).
  #
  # Writes our install-ssm-agent.sh verbatim into the guest and runs it during
  # provisioning: it fetches the per-OL Amazon SSM Agent RPM (every OL major
  # follows the /latest/ alias) with a plain in-guest
  # `curl -fsSL` (the same fetch model as the ENA hook -- normal TLS trust, no
  # -k), installs it with `rpm -Uvh`, and enables it for boot per init system
  # (systemd on OL7+, SysV/upstart on OL6). The result is an AMI that is AWS SSM
  # Run Command compliant out of the box. --skip-ssm-agent leaves the hook out.
  #
  # NON-FATAL by design: unlike the ENA driver (Nitro network-critical -- no
  # driver, no eth0), the SSM Agent is management tooling; a transient fetch
  # failure should not abort an otherwise-good AMI, so the hook invocation traps
  # its own failure to a warning and provisioning continues. The embedded heredoc
  # is single-quoted, so the installer's own text (heredocs, '\$' refs) is written
  # through unmodified. Idempotent via the wrapper marker.
  #
  # NOTE: OL6-OL8 install+run is matrix-verified AND the OL6/OL7 pipeline is
  # boot-validated on real Nitro; OL9/OL10 install+run is matrix-verified but the
  # SSM-enabled AMI has not yet been boot-validated end to end on a real instance.
  if [[ "${SSM_AGENT_INSTALL}" -ne 1 ]]; then
    log_info "SSM Agent install disabled (--skip-ssm-agent); the AMI ships without the Amazon SSM Agent"
  else
    local aws_provision_ssm="${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}/cloud/aws/provision.sh"
    local ssm_installer="${SCRIPT_DIR}/install-ssm-agent.sh"
    log_info "Injecting SSM Agent install hook into cloud/aws/provision.sh (default ON; --skip-ssm-agent disables)"

    if [[ ! -f "${aws_provision_ssm}" ]]; then
      die "Cannot inject SSM Agent hook: ${aws_provision_ssm} not found"
    fi
    if [[ ! -f "${ssm_installer}" ]]; then
      die "Cannot inject SSM Agent hook: installer not found at ${ssm_installer}"
    fi

    if grep -Fq '[ol-aws-ami-builder PATCH ssm-agent-install]' "${aws_provision_ssm}"; then
      log_info "  -> SSM Agent hook already present (idempotent skip)"
    else
      {
        printf '\n# >>> [ol-aws-ami-builder PATCH ssm-agent-install] >>>\n'
        printf '# Install + boot-enable the per-OL Amazon SSM Agent in the guest (SSM Run Command compliant).\n'
        printf '# Omitted by the wrapper'"'"'s --skip-ssm-agent switch. Non-fatal: a failure warns and continues.\n'
        printf "cat > /usr/local/sbin/ol-aws-install-ssm-agent.sh <<'OLAWS_SSM_INSTALLER_EOF'\n"
        cat "${ssm_installer}"
        printf 'OLAWS_SSM_INSTALLER_EOF\n'
        printf 'chmod +x /usr/local/sbin/ol-aws-install-ssm-agent.sh\n'
        printf '/usr/local/sbin/ol-aws-install-ssm-agent.sh || echo "[ssm-agent] WARNING: SSM Agent install hook failed; AMI built without an installed SSM Agent (non-fatal: management tooling, not boot-critical)"\n'
        printf '# <<< [ol-aws-ami-builder PATCH ssm-agent-install] <<<\n'
      } >> "${aws_provision_ssm}"

      if grep -Fq '[ol-aws-ami-builder PATCH ssm-agent-install]' "${aws_provision_ssm}"; then
        log_info "  [OLAWS-SSM01] SSM Agent hook injected (version: OL${OL_MAJOR_VERSION} ${SSM_AGENT_RESOLVED:-latest}; install + boot-enable)"
      else
        die "Failed to inject SSM Agent hook into ${aws_provision_ssm}"
      fi
    fi
  fi

  # cloud/aws/provision.sh AWS CLI v2 install hook (default ON; OL6/OL7/OL8 ONLY).
  #
  # Writes our install-awscli.sh verbatim into the guest and runs it during
  # provisioning: it installs the per-OL AWS CLI v2 bundle (OL6 pinned to the
  # install+run-verified 2.17.51, OL7/OL8 the moving `latest`) and excludes the
  # OL-repo `awscli` (v1) via versionlock, so the AMI ships AWS CLI v2 as the
  # standard CLI (v1 is increasingly unsupported). Same in-guest fetch model as
  # the SSM/ENA hooks (plain `curl -fsSL`, normal TLS trust; `-k` is a test-only
  # INSECURE_TLS switch, never used in production). --skip-awscli leaves the hook
  # out. OL9/OL10 are OUT OF SCOPE -- they install AWS CLI v2 from their default
  # package manager -- so the hook is not injected there (an info line is logged).
  #
  # NON-FATAL by design: like the SSM Agent (and unlike the Nitro-network-critical
  # ENA driver), AWS CLI v2 is utility tooling; a transient install failure should
  # not abort an otherwise-good AMI, so the hook invocation traps its own failure
  # to a warning and provisioning continues. The embedded heredoc is single-quoted,
  # so the installer's own text is written through unmodified. Idempotent via the
  # wrapper marker.
  if [[ "${AWSCLI_INSTALL}" -ne 1 ]]; then
    log_info "AWS CLI v2 install disabled (--skip-awscli); the AMI ships without AWS CLI v2"
  elif [[ "${OL_MAJOR_VERSION}" != "5" && "${OL_MAJOR_VERSION}" != "6" && "${OL_MAJOR_VERSION}" != "7" && "${OL_MAJOR_VERSION}" != "8" ]]; then
    log_info "AWS CLI v2 install skipped on OL${OL_MAJOR_VERSION} (out of scope; OL9/OL10 install AWS CLI v2 from the default package manager)"
  else
    local aws_provision_cli="${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}/cloud/aws/provision.sh"
    local awscli_installer="${SCRIPT_DIR}/install-awscli.sh"
    log_info "Injecting AWS CLI v2 install hook into cloud/aws/provision.sh (default ON for OL5-OL8; --skip-awscli disables)"

    if [[ ! -f "${aws_provision_cli}" ]]; then
      die "Cannot inject AWS CLI v2 hook: ${aws_provision_cli} not found"
    fi
    if [[ ! -f "${awscli_installer}" ]]; then
      die "Cannot inject AWS CLI v2 hook: installer not found at ${awscli_installer}"
    fi

    if grep -Fq '[ol-aws-ami-builder PATCH awscli-install]' "${aws_provision_cli}"; then
      log_info "  -> AWS CLI v2 hook already present (idempotent skip)"
    else
      {
        printf '\n# >>> [ol-aws-ami-builder PATCH awscli-install] >>>\n'
        printf '# Install the per-OL AWS CLI v2 in the guest (standard CLI; v1 excluded via versionlock).\n'
        printf '# Omitted by the wrapper'"'"'s --skip-awscli switch. Non-fatal: a failure warns and continues.\n'
        printf "cat > /usr/local/sbin/ol-aws-install-awscli.sh <<'OLAWS_AWSCLI_INSTALLER_EOF'\n"
        cat "${awscli_installer}"
        printf 'OLAWS_AWSCLI_INSTALLER_EOF\n'
        printf 'chmod +x /usr/local/sbin/ol-aws-install-awscli.sh\n'
        printf '/usr/local/sbin/ol-aws-install-awscli.sh || echo "[awscli] WARNING: AWS CLI v2 install hook failed; AMI built without AWS CLI v2 (non-fatal: utility tooling, not boot-critical)"\n'
        printf '# <<< [ol-aws-ami-builder PATCH awscli-install] <<<\n'
      } >> "${aws_provision_cli}"

      if grep -Fq '[ol-aws-ami-builder PATCH awscli-install]' "${aws_provision_cli}"; then
        log_info "  [OLAWS-AWSCLI01] AWS CLI v2 hook injected (version: OL${OL_MAJOR_VERSION} ${AWSCLI_RESOLVED:-latest})"
      else
        die "Failed to inject AWS CLI v2 hook into ${aws_provision_cli}"
      fi
    fi
  fi

  # cloud/aws/provision.sh Amazon Time Sync hook (OPT-IN; default OFF).
  #
  # Enabled by AMAZON_TIME_SYNC="yes" in the env file or the
  # --enable-amazon-time-sync switch. The guest-side block appends the
  # link-local Amazon Time Sync Service (169.254.169.123) as the PREFERRED
  # time source -- /etc/chrony.conf on OL7-OL10, /etc/ntp.conf on OL6; the
  # block detects which file exists, so there is no per-OL branching here --
  # and keeps the distribution pool lines as fallback (minimal diff).
  # DEFAULT OFF by design: time configuration belongs to the end user of the
  # AMI, so the builder does not change the distribution default unless
  # explicitly asked. Idempotent via the wrapper marker (both wrapper-side
  # and guest-side: the guest block re-checks before appending).
  if [[ "${AMAZON_TIME_SYNC,,}" == "yes" ]]; then
    local aws_provision_ts="${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}/cloud/aws/provision.sh"
    log_info "Injecting Amazon Time Sync hook into cloud/aws/provision.sh (opt-in; --enable-amazon-time-sync / AMAZON_TIME_SYNC=yes)"

    if [[ ! -f "${aws_provision_ts}" ]]; then
      die "Cannot inject Amazon Time Sync hook: ${aws_provision_ts} not found"
    fi

    if grep -Fq '[ol-aws-ami-builder PATCH amazon-time-sync]' "${aws_provision_ts}"; then
      log_info "  -> Amazon Time Sync hook already present (idempotent skip)"
    else
      cat >> "${aws_provision_ts}" <<'OLAWS_TIMESYNC_EOF'

# >>> [ol-aws-ami-builder PATCH amazon-time-sync] >>>
# Prefer the link-local Amazon Time Sync Service (opt-in via --enable-amazon-time-sync).
if [ -f /etc/chrony.conf ]; then
  if ! grep -q '169\.254\.169\.123' /etc/chrony.conf; then
    {
      echo ''
      echo '# [ol-aws-ami-builder] Amazon Time Sync Service (opt-in via --enable-amazon-time-sync)'
      echo 'server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4'
    } >> /etc/chrony.conf
  fi
elif [ -f /etc/ntp.conf ]; then
  if ! grep -q '169\.254\.169\.123' /etc/ntp.conf; then
    {
      echo ''
      echo '# [ol-aws-ami-builder] Amazon Time Sync Service (opt-in via --enable-amazon-time-sync)'
      echo 'server 169.254.169.123 prefer iburst'
    } >> /etc/ntp.conf
  fi
fi
# <<< [ol-aws-ami-builder PATCH amazon-time-sync] <<<
OLAWS_TIMESYNC_EOF

      if grep -Fq '[ol-aws-ami-builder PATCH amazon-time-sync]' "${aws_provision_ts}"; then
        log_info "  [OLAWS-TIMESYNC01] Amazon Time Sync hook injected (169.254.169.123 preferred; distro pool kept as fallback)"
      else
        die "Failed to inject Amazon Time Sync hook into ${aws_provision_ts}"
      fi
    fi
  fi

  # env.properties.defaults 'declare -gA' guard (OL6 only).
  #
  # Background:
  #   Upstream env.properties.defaults ends with:
  #     declare -gA REPO
  #   The '-g' (global) flag for 'declare' was added in bash 4.2. This file is
  #   ENV_FILE_DEFAULTS -- the head of build-image.sh's ENV_FILES -- so it is
  #   concatenated FIRST into the in-guest provision.d/env.properties, which
  #   provision.sh then sources INSIDE the guest. OL6 ships bash 4.1, which
  #   rejects '-g' ("declare: -g: invalid option"), so guest provisioning
  #   aborts and build-image.sh exits 1 -- AFTER an otherwise successful
  #   install. OL7 (bash 4.2), OL8 (4.4) and OL10 (5.x) accept '-g', so this
  #   only bites OL6.
  #
  # Fix:
  #   Rewrite the line to try the original (host-preserving) form and fall back
  #   to a 4.1-compatible 'declare -A' when '-g' is unavailable:
  #     declare -gA REPO 2>/dev/null || declare -A REPO
  #   On the host (bash 5.x, sourced inside a build-image.sh function) the first
  #   form succeeds, so REPO stays a global associative array exactly as
  #   upstream intends. In the OL6 guest the first form fails quietly and the
  #   fallback runs; REPO is unused by guest provisioning, so its scope there is
  #   immaterial -- the point is only that sourcing no longer aborts. 'A || B'
  #   is safe under 'set -e' (it does not trip errexit).
  #
  # Idempotency: grep the wrapper marker before substituting.
  if [[ "${OL_MAJOR_VERSION}" -eq 6 ]]; then
    local ol_defaults="${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}/env.properties.defaults"
    log_info "Applying declare -gA bash-4.1 guard to upstream env.properties.defaults (OL${OL_MAJOR_VERSION})"

    if [[ ! -f "${ol_defaults}" ]]; then
      die "Cannot apply declare -gA guard: ${ol_defaults} not found"
    fi

    if grep -Fq '[ol-aws-ami-builder PATCH declare-g-ol6]' "${ol_defaults}"; then
      log_info "  -> declare -gA guard already applied (idempotent skip)"
    elif grep -Eq '^declare -gA REPO[[:space:]]*$' "${ol_defaults}"; then
      sed -i.declare-g-guard.bak \
        -e 's@^declare -gA REPO[[:space:]]*$@declare -gA REPO 2>/dev/null || declare -A REPO  # [ol-aws-ami-builder PATCH declare-g-ol6] bash 4.1 (OL6 guest) has no declare -g@' \
        "${ol_defaults}"

      if grep -Fq '[ol-aws-ami-builder PATCH declare-g-ol6]' "${ol_defaults}"; then
        log_info "  -> declare -gA guard applied (backup at ${ol_defaults}.declare-g-guard.bak)"
      else
        die "Failed to apply declare -gA guard to ${ol_defaults}"
      fi
    else
      log_warn "  'declare -gA REPO' line not found in ${ol_defaults}."
      log_warn "  Assuming upstream changed the env defaults; proceeding (verify OL6 provisioning)."
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
# sosreport tooling baked in (parity with the OL7-10 sos-package KS patch)
sos
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

# Ensure the AWS serial console (ttyS0) is on the kernel cmdline so 'Get System
# Log' captures boot output. OL6 uses GRUB Legacy (/boot/grub/grub.conf); the
# kickstart bootloader line sets console=tty0, so append ttyS0 after it.
# Idempotent: only add when console=ttyS0 is not already present.
# (Previously this line STRIPPED console=ttyS0, leaving the AWS console log
#  empty and OL6 boot failures undebuggable -- see SPEC D.25.)
if ! grep -q 'console=ttyS0' /boot/grub/grub.conf; then
  sed -i -e 's/console=tty0/console=tty0 console=ttyS0,115200n8/g' /boot/grub/grub.conf
fi

# (2) GRUB-over-serial for OL6 (GRUB Legacy): make GRUB itself talk to ttyS0 so
# the interactive EC2 Serial Console reaches the boot menu. This is the GRUB
# Legacy equivalent of GRUB2's GRUB_TERMINAL="console serial" +
# GRUB_SERIAL_COMMAND -- the 'serial'/'terminal' directives in grub.conf's global
# section (inserted before the first 'title' so they stay global). Idempotent.
# NOTE: 'terminal --timeout=10' makes GRUB wait up to 10s for a keypress to pick
# the active terminal; on a headless boot it then defaults to serial. This adds a
# small menu-selection delay -- acceptable for OL6 (verification/legacy only).
if ! grep -q '^serial ' /boot/grub/grub.conf; then
  sed -i '0,/^title/ s/^title/serial --unit=0 --speed=115200\nterminal --timeout=10 serial console\n&/' /boot/grub/grub.conf
fi

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

# virt-sysprep prerequisite (see SPEC D.20). The upstream image_cleanup() runs
#   virt-sysprep ... --truncate /etc/machine-id --truncate /etc/resolv.conf ...
# unconditionally. OL6 uses Upstart (no systemd), so /etc/machine-id does not
# exist and that --truncate aborts the entire build at the Cleanup stage. Create
# the file (empty) so OL6 reaches the same state the systemd distros (OL7+) are
# already in when virt-sysprep runs. An empty /etc/machine-id is also the
# standard "regenerate on first boot" marker, so this is harmless on OL6.
: > /etc/machine-id
# resolv.conf is the next --truncate target; create it only if absent so a real
# one written during install is left intact (virt-sysprep blanks it afterwards).
[[ -e /etc/resolv.conf ]] || : > /etc/resolv.conf

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

  # OpenSSH 5.3 (OL6) predates 'prohibit-password' (added in 6.7); its parser
  # accepts only yes|no|without-password|forced-commands-only and FATALs on any
  # other value, so sshd refuses to start -> port 22 closed -> the instance
  # pings but SSH gives 'Connection refused'. 'prohibit-password' is the modern
  # alias for 'without-password'; map it back so OL6 gets the identical policy in
  # 5.3-valid syntax. This is OL6-only (distr::common_cfg lives in the synthesized
  # OL6 provision.sh); OL7+ keep the modern value via their own upstream path.
  local ol6_root_login="${PERMIT_ROOT_LOGIN,,}"
  [ "${ol6_root_login}" = "prohibit-password" ] && ol6_root_login="without-password"
  common::echo_message "sshd root login policy (OL6/OpenSSH 5.3): ${ol6_root_login}"
  ex -s /etc/ssh/sshd_config <<EOF
:%substitute/^#\?\(PermitRootLogin\) .*$/\1 ${ol6_root_login}/
:update
:quit
EOF

  # Validate the generated sshd_config with sshd's own parser BEFORE the image
  # is sealed. 'sshd -t' exits non-zero on ANY unknown directive/value (the exact
  # prohibit-password-on-5.3 failure mode, and any future OL6/5.3 incompatibility),
  # turning a silent first-boot 'Connection refused' into a loud, deterministic
  # build-time abort. An ephemeral host key (-h) keeps the test independent of
  # whether real host keys exist yet at provision time, so only genuine CONFIG
  # errors fail it; missing tools degrade to a warning (never a false abort).
  local sshd_bin="" sshd_tkey
  command -v sshd >/dev/null 2>&1 && sshd_bin="$(command -v sshd)"
  [ -z "${sshd_bin}" ] && [ -x /usr/sbin/sshd ] && sshd_bin=/usr/sbin/sshd
  if [ -n "${sshd_bin}" ] && command -v ssh-keygen >/dev/null 2>&1; then
    sshd_tkey="$(mktemp -u /tmp/ol-aws-sshd-test.XXXXXX)"
    if ssh-keygen -q -t rsa -b 2048 -f "${sshd_tkey}" -N "" </dev/null 2>/dev/null && [ -f "${sshd_tkey}" ]; then
      if "${sshd_bin}" -t -f /etc/ssh/sshd_config -h "${sshd_tkey}" 2>/tmp/ol-aws-sshd-test.err; then
        common::echo_message "sshd_config validated by 'sshd -t' (PermitRootLogin=${ol6_root_login}; OK)"
      else
        common::echo_message "FATAL: 'sshd -t' rejected the generated sshd_config (PermitRootLogin=${ol6_root_login}):"
        cat /tmp/ol-aws-sshd-test.err 2>/dev/null || true
        rm -f "${sshd_tkey}" "${sshd_tkey}.pub" /tmp/ol-aws-sshd-test.err
        exit 1
      fi
      rm -f "${sshd_tkey}" "${sshd_tkey}.pub" /tmp/ol-aws-sshd-test.err
    else
      common::echo_message "WARNING: could not create an ephemeral test host key; skipped 'sshd -t' validation"
      rm -f "${sshd_tkey}" "${sshd_tkey}.pub" 2>/dev/null || true
    fi
  else
    common::echo_message "WARNING: sshd/ssh-keygen not found; skipped 'sshd -t' validation"
  fi

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

  # OL5 distr/ol5-slim/ runtime generation + host-supply artifact staging.
  #
  # Background:
  #   Like OL6, OL5 has NO distr directory upstream; unlike OL6, the guest can
  #   fetch NOTHING (EL5 = TLS 1.0 max), so this block also downloads every
  #   guest artifact on the HOST into distr/ol5-slim/files/ -- the standard
  #   upstream files channel (build-image.sh copies files/ into provision.d/,
  #   virt-customize copies it to /tmp/provision.d/ in the guest, and the
  #   [OLAWS-OL5S1] executor installs from there).
  #
  # Templates mirror distr/ol6-slim's structure with EL5 adjustments:
  #   - SysV init (no Upstart/systemd), GRUB Legacy, anaconda-11.1 kickstart
  #     syntax (NO %end; 'key --skip'; no services/cmdline/--only-use)
  #   - UEK Release 2 only (in-box nvme, F1-proven; ena self-built)
  #   - ext3 root (EL5 anaconda's solid choice; ext4 is a 5.6 tech preview)
  #   - guest-side provision code is EL5 bash 3.2 / POSIX safe
  #   - LABEL-based boot everywhere (hda/sda -> nvme device-name transitions)
  if [[ "${OL_MAJOR_VERSION}" -eq 5 ]]; then
    local ol5_slim_dir="${WORK_REPO_DIR}/${OL_TOOLS_SUBDIR}/distr/ol5-slim"
    log_info "Generating distr/ol5-slim/ at runtime (upstream does not ship this directory)"
    mkdir -p "${ol5_slim_dir}"

    # ----- distr/ol5-slim/env.properties -----
    cat > "${ol5_slim_dir}/env.properties" <<'EOF_OL5_ENV'
# Default parameters for OL5 distribution.
# Do NOT change anything in this file; customisation must be done in a
# separate env file (e.g. env.properties.aws-ol5).
#
# This file is created at build time by ol-aws-ami-builder because the
# upstream oracle-linux-image-tools project does not ship a distr/ol5-slim/
# directory. See SPEC.md (Part B/D) for the rationale.

# Distribution name (auto-derived from ISO_URL by build-image.sh; this is fallback)
DISTR_NAME="OL5U11_x86_64"

# Distribution release
readonly ORACLE_RELEASE=5

# Setup swap? (Cloud images: no)
SETUP_SWAP="no"

# Root filesystem: ext3 ONLY on OL5 (EL5 anaconda-11.1; ext4 is a 5.6 tech
# preview behind a boot flag and xfs/lvm/btrfs roots are unsupported).
ROOT_FS="ext3"

# Location of kernel/initrd on the distribution image (relative to ISO root)
BOOT_LOCATION="isolinux"

# Boot mode - Must be "bios" for OL5 (no UEFI support in EL5 anaconda)
BOOT_MODE="bios"

# Boot command for EL5 anaconda (NO 'inst.' prefix; NO stage2= -- the EL5
# loader auto-probes the attached install media, and the kickstart's 'cdrom'
# directive pins the package source). Variables MUST be escaped as they are
# evaluated at build time.
BOOT_COMMAND=(
  'text'
  'ks=file:/${KS_FILE}'
)
# Additional parameters to enable serial console
BOOT_COMMAND_SERIAL_CONSOLE=(
  'console=tty0'
  'console=ttyS0'
)

# Kernel: uek only on OL5 + AWS (UEK R2 carries the in-box nvme driver --
# the Nitro boot precondition; RHCK 2.6.18 has neither nvme nor ena).
KERNEL="uek"

# UEK release: 2 (the only UEK line published for OL5; terminal/frozen)
UEK_RELEASE=2

# Update: no ONLY on OL5 (the guest has no reachable repository -- EL5 has
# no TLS 1.2 path; every package is host-staged).
UPDATE_TO_LATEST="no"

# Keep linux-firmware package? EL5 has no linux-firmware package at all;
# kernel-uek-firmware is host-staged with the kernel. Fixed "no".
LINUX_FIRMWARE="no"

# Strip locales to only keep en_US? yes, no
STRIP_LOCALES="no"

# Exclude documentation? yes, no, minimal
EXCLUDE_DOCS="no"

# Directory used to save build information
readonly BUILD_INFO="/.build-info"
EOF_OL5_ENV

    # ----- distr/ol5-slim/image-scripts.sh (HOST side; modern bash OK) -----
    cat > "${ol5_slim_dir}/image-scripts.sh" <<'EOF_OL5_IMG'
#!/usr/bin/env bash
#
# image scripts for OL5
#
# Created by ol-aws-ami-builder (not part of upstream oracle-linux-image-tools).
# Mirrors distr/ol6-slim/image-scripts.sh with EL5-specific hard constraints:
#   - ROOT_FS must be ext3 (EL5 anaconda-11.1: ext4 is a 5.6 tech preview
#     behind a boot flag; xfs/lvm/btrfs roots are unsupported)
#   - UEK_RELEASE accepts only 2 (the only UEK line ever published for OL5)
#   - UPDATE_TO_LATEST must be no (no reachable in-guest repository on EL5)
#

#######################################
# Validate distribution parameters
#######################################
distr::validate() {
  [[ "${ROOT_FS,,}" == "ext3" ]] || common::error "ROOT_FS must be ext3 on OL5 (EL5 anaconda-11.1: ext4 is a 5.6 tech preview; xfs/lvm/btrfs roots unsupported)"
  [[ "${TMP_IN_TMPFS,,}" =~ ^((yes)|(no))$ ]] || common::error "TMP_IN_TMPFS must be yes or no"
  [[ "${UEK_RELEASE}" =~ ^2$ ]] || common::error "UEK_RELEASE must be 2 (the only UEK line published for OL5; it carries the in-box nvme driver)"
  [[ "${UPDATE_TO_LATEST,,}" == "no" ]] || common::error "UPDATE_TO_LATEST must be no on OL5 (EL5 has no TLS 1.2 path; there is no reachable in-guest repository -- packages are host-staged)"
  [[ "${LINUX_FIRMWARE,,}" =~ ^((yes)|(no))$ ]] || common::error "LINUX_FIRMWARE must be yes or no"
  [[ "${STRIP_LOCALES,,}" =~ ^((yes)|(no))$ ]] || common::error "STRIP_LOCALES must be yes or no"
  [[ "${EXCLUDE_DOCS,,}" =~ ^((yes)|(no)|(minimal))$ ]] || common::error "EXCLUDE_DOCS must be yes, no or minimal"
  readonly ROOT_FS TMP_IN_TMPFS UEK_RELEASE UPDATE_TO_LATEST LINUX_FIRMWARE STRIP_LOCALES EXCLUDE_DOCS
}

#######################################
# Kickstart fixup
#######################################
distr::kickstart() {
  local ks_file="$1"

  # The embedded kickstart already declares ext3 everywhere and
  # distr::validate() rejects any other ROOT_FS during preflight, so no
  # fstype rewrite is performed here (see the OL6 precedent).

  # Docs
  if [[ "${EXCLUDE_DOCS,,}" = "yes" ]]; then
    sed -i -e 's!^%packages !%packages --excludedocs !' "${ks_file}"
  fi
}
EOF_OL5_IMG

    # ----- distr/ol5-slim/ol5-ks.cfg -----
    # EL5 anaconda-11.1 shape. Deliberate differences from the OL6 template,
    # each a measured EL5 constraint:
    #   * NO %end anywhere (anaconda-11.1 predates it; a literal '%end' inside
    #     %packages would be read as a package name)
    #   * 'key --skip' (EL5-only installation-number prompt suppressor)
    #   * 'cdrom' pins the package source (no stage2= boot arg)
    #   * NO 'services'/'cmdline'/'ignoredisk --only-use'/'rootpw --lock'/
    #     'bootloader --timeout' (all RHEL6+/anaconda-13+); rootpw uses the
    #     no-valid-password crypted form; services are chkconfig'd in %post
    #   * NO --ondisk (single build disk; hda/sda naming varies by kernel) and
    #     LABEL-based everything (survives the hda/sda -> nvme transition)
    #   * %post logs via an exec redirect (chosen single mechanism -- it also
    #     captures set -x; the real 0.43 parser DOES accept --log, contrary
    #     to an earlier note here -- see the SPEC D.32 grammar record)
    cat > "${ol5_slim_dir}/ol5-ks.cfg" <<'EOF_OL5_KS'
# OL5 kickstart file (EL5 anaconda-11.1 syntax; no %end -- see SPEC Part B/D)

install
cdrom
text
key --skip

auth --enableshadow --enablemd5
keyboard us
lang en_US.UTF-8
reboot
timezone --utc UTC
network --bootproto=dhcp --device=eth0 --onboot=yes --hostname=localhost.localdomain

# Locked, no-valid-password root (anaconda-11.1 has no 'rootpw --lock')
rootpw --iscrypted *

selinux --permissive
firewall --enabled --ssh

# GRUB Legacy; console on tty0 (ttyS0 appended in %post -- see SPEC D.25)
bootloader --location=mbr --append="console=tty0"

zerombr
clearpart --all --initlabel

part /boot    --fstype=ext3 --size=200  --label=/boot --asprimary
part swap     --fstype=swap --size=1024 --label=swap
part /        --fstype=ext3 --size=4096 --label=root  --grow

%packages --nobase
openssh-server
openssh-clients
dhclient
chkconfig
initscripts
rootfiles
passwd
sudo
# cloud-init 0.6.3 hard-requires rsyslog (closure-verified against OL5 base)
rsyslog
# sosreport tooling baked in (parity with the OL6-10 sos-package invariant)
sos
# cloud-init closure members that are NOT in the minimal set (closure-verified)
crontabs
procps
net-tools
iproute
ethtool
e4fsprogs
libselinux-python
# unzip: the AWS CLI v2 bundle unpack tool (record #7 -- the EPEL5 container
# clean-core ships unzip, but the ISO minimal guest does NOT; U11 media
# carries unzip-5.52, so anaconda supplies it)
unzip
# kernel/initrd handling for the host-staged UEK R2 install
module-init-tools
mkinitrd
grub
# growroot one-shot (fdisk lives in util-linux on EL5)
util-linux
e2fsprogs
ntp
acpid
which
tar
gzip
findutils
sed
gawk
curl
-sendmail

%post --interpreter /bin/bash
# Log via exec redirect (single mechanism; also captures the set -x below --
# 0.43 does parse --log, but the redirect is used regardless).
# common::ks_log reads this exact path.
exec > /root/ks-post.log 2>&1
set -x

echo "Network fixes"
cat > /etc/sysconfig/network <<'EOF_NET'
NETWORKING=yes
NOZEROCONF=yes
EOF_NET

cat > /etc/sysconfig/network-scripts/ifcfg-eth0 <<'EOF_ETH0'
DEVICE="eth0"
BOOTPROTO="dhcp"
ONBOOT="yes"
TYPE="Ethernet"
USERCTL="yes"
PEERDNS="yes"
IPV6INIT="no"
PERSISTENT_DHCLIENT="1"
EOF_ETH0

cat > /etc/hosts <<'EOF_HOSTS'
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
EOF_HOSTS

echo "RUN_FIRSTBOOT=NO" > /etc/sysconfig/firstboot

# Serial console on GRUB Legacy (same two layers as the OL6 template; D.25):
# (1) kernel cmdline ttyS0 so 'Get System Log' captures boot output
if ! grep -q 'console=ttyS0' /boot/grub/grub.conf; then
  sed -i -e 's/console=tty0/console=tty0 console=ttyS0,115200n8/g' /boot/grub/grub.conf
fi
# (2) GRUB-over-serial so the interactive EC2 Serial Console reaches the menu
if ! grep -q '^serial ' /boot/grub/grub.conf; then
  sed -i '0,/^title/ s/^title/serial --unit=0 --speed=115200\nterminal --timeout=10 serial console\n&/' /boot/grub/grub.conf
fi

# ec2-user: MUST exist at build time -- cloud-init 0.6.3's setup_user_keys is
# getpwnam-only (no users-groups module in 0.6.x); key injection would fail
# silently without this account. Passwordless sudo via a direct sudoers line
# (EL5 sudo predates a stock #includedir /etc/sudoers.d).
/usr/sbin/useradd -m -s /bin/bash ec2-user
passwd -l ec2-user
if ! grep -q '^ec2-user ' /etc/sudoers; then
  echo 'ec2-user ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
fi

# One-shot root grow (fdisk delete/recreate pattern -- the MBR adaptation of
# the RHEL6-HVM gdisk workaround; gdisk itself is staged as a TOOL but never
# used here: writing GPT to this MBR disk would break GRUB Legacy).
# Runs before cloud-init (S08 < S20).
# DECISION MODEL (adjudicated): the PRIMARY execution criterion is the REAL
# disk/partition geometry -- grow whenever sysfs shows the root partition can
# actually be extended (this also re-fires naturally after a later EBS volume
# resize). The state file is a SECONDARY condition only: it records the disk
# size of the last attempt so a grow that did not take effect at the SAME
# size is not retried forever (reboot-loop guard); a LARGER disk than the
# recorded attempt proceeds again. After a grow: record + one reboot;
# cloud-init's resizefs then grows the ext3 filesystem on the next boot.
# Every skip/failure path exits 0 (never blocks boot).
cat > /etc/init.d/ol-aws-growroot <<'EOF_GROWROOT'
#!/bin/sh
# chkconfig: 2345 08 92
# description: grow the root partition to the disk end when the ON-DISK
#              geometry says growth is needed and possible (growpart model)
### BEGIN INIT INFO
# Provides: ol-aws-growroot
### END INIT INFO
#
# DECISION MODEL (adjudicated 2026-07-19): the PRIMARY execution criterion is
# the actual disk/partition state -- growth needed AND possible, decided from
# sysfs geometry + the on-disk table every boot. The attempt marker is
# SECONDARY: a reboot-loop breaker only, consulted AFTER the geometry
# decision and self-healed on success (so a later EBS enlargement grows
# again, matching real growpart semantics).
#
# MECHANISM mirrors cloud-utils growpart: sfdisk dump -> edit ONLY the size
# field of the root entry -> apply with --no-reread --force, with the old
# dump saved as the restore vehicle and a post-write verify re-dump. Adapted
# to EL5 util-linux 2.13; NOTE: 2.13 sfdisk composes NVMe partition NAMES
# wrongly (no 'p' separator), so the root entry is addressed by its START
# SECTOR (unique, name-independent), never by device name.
#
# A reboot IS required on this kernel line: online resize of a mounted root
# partition needs BLKPG_RESIZE_PARTITION (kernel 3.6+); UEK R2 is 3.0.36 --
# the same reason the RHEL6 era used initramfs-time growroot.
MARKER=/var/lib/ol-aws-growroot.attempt
LOG=/var/log/ol-aws-growroot.log
FUDGE_SECTORS=2048
case "$1" in
  start|"") ;;
  *) exit 0 ;;
esac
mkdir -p /var/lib
exec >> "$LOG" 2>&1
echo "[growroot] start: $(date)"

# --- resolve root device -> disk ---
rootdev=$(df -P / | awk 'NR==2{print $1}')
case "$rootdev" in
  /dev/nvme*) disk=$(echo "$rootdev" | sed 's/p[0-9][0-9]*$//') ;;
  /dev/*)     disk=$(echo "$rootdev" | sed 's/[0-9][0-9]*$//') ;;
  *) echo "[growroot] unrecognized root device '$rootdev'; nothing to do"; exit 0 ;;
esac
dbase=$(basename "$disk"); pbase=$(basename "$rootdev")
[ -b "$disk" ] || { echo "[growroot] no block device ${disk}; nothing to do"; exit 0; }

# --- PRIMARY criterion: on-disk / sysfs geometry ---
dsz=$(cat "/sys/block/${dbase}/size" 2>/dev/null)
pstart=$(cat "/sys/block/${dbase}/${pbase}/start" 2>/dev/null)
psize=$(cat "/sys/block/${dbase}/${pbase}/size" 2>/dev/null)
if [ -z "$dsz" ] || [ -z "$pstart" ] || [ -z "$psize" ]; then
  echo "[growroot] sysfs geometry unavailable; skipping (re-evaluated next boot)"; exit 0
fi
# root must be the LAST partition on the disk (name-independent sysfs walk)
for p in /sys/block/${dbase}/${dbase}*; do
  [ -d "$p" ] || continue
  os=$(cat "$p/start" 2>/dev/null)
  if [ -n "$os" ] && [ "$os" -gt "$pstart" ]; then
    echo "[growroot] REFUSING: a partition starts after the root partition"; exit 0
  fi
done
pend=$((pstart + psize))
free=$((dsz - pend))
if [ "$free" -le "$FUDGE_SECTORS" ]; then
  echo "[growroot] NOCHANGE: root already spans the disk (free tail ${free} <= fudge ${FUDGE_SECTORS} sectors)"
  if [ -f "$MARKER" ]; then
    rm -f "$MARKER"
    echo "[growroot] stale attempt marker cleared (re-armed for future volume growth)"
  fi
  exit 0
fi

# --- read the on-disk table; guard the entry type ---
dump=$(mktemp /tmp/growroot-dump.XXXXXX) || exit 0
if ! sfdisk -d "$disk" > "$dump" 2>/dev/null; then
  echo "[growroot] sfdisk -d failed on ${disk}; skipping"; rm -f "$dump"; exit 0
fi
line=$(grep "start=[ ]*${pstart}," "$dump" | head -1)
if [ -z "$line" ]; then
  echo "[growroot] no table entry with start=${pstart}; skipping"; rm -f "$dump"; exit 0
fi
pid=$(echo "$line" | sed 's/.*Id=[ ]*\([0-9a-fA-F][0-9a-fA-F]*\).*/\1/')
if [ "$pid" != "83" ]; then
  echo "[growroot] REFUSING: root entry has Id=${pid} (only plain Linux 83 is grown; ee would mean GPT)"
  rm -f "$dump"; exit 0
fi
if grep "Id=[ ]*5" "$dump" >/dev/null 2>&1 || grep "Id=[ ]*f" "$dump" >/dev/null 2>&1 || grep "Id=[ ]*85" "$dump" >/dev/null 2>&1; then
  echo "[growroot] REFUSING: extended partition present (not a builder layout)"
  rm -f "$dump"; exit 0
fi

# --- SECONDARY criterion: attempt marker (reboot-loop breaker ONLY) ---
if [ -f "$MARKER" ]; then
  echo "[growroot] GROWTH STILL NEEDED (free tail ${free} sectors) but a previous attempt is recorded:"
  cat "$MARKER"
  echo "[growroot] NOT retrying (reboot-loop protection). Inspect ${LOG}; remove ${MARKER} to re-arm."
  rm -f "$dump"; exit 0
fi

# --- grow: dump -> single size-field edit -> apply -> verify (growpart model) ---
newsize=$((dsz - pstart))
echo "[growroot] growing root: start=${pstart} size ${psize} -> ${newsize} (disk ${dsz} sectors)"
bak=/var/lib/ol-aws-growroot.sfdisk-backup
cp -f "$dump" "$bak"
new=$(mktemp /tmp/growroot-new.XXXXXX) || { rm -f "$dump"; exit 0; }
sed "/start=[ ]*${pstart},/s/size=[ ]*[0-9][0-9]*/size= ${newsize}/" "$dump" > "$new"
if ! grep "start=[ ]*${pstart}," "$new" | grep "size= ${newsize}" >/dev/null; then
  echo "[growroot] FAILED to edit the dump; aborting without writing"
  rm -f "$dump" "$new"; exit 0
fi
{
  echo "attempted: $(date)"
  echo "geometry: start=${pstart} old_size=${psize} new_size=${newsize} disk=${dsz}"
} > "$MARKER"
sync
if ! sfdisk --no-reread --force "$disk" < "$new" >> "$LOG" 2>&1; then
  echo "[growroot] sfdisk apply FAILED; restoring from the backup dump"
  if sfdisk --no-reread --force "$disk" < "$bak" >> "$LOG" 2>&1; then
    echo "[growroot] restore applied"
  else
    echo "[growroot] RESTORE ALSO FAILED -- inspect ${bak} manually"
  fi
  rm -f "$dump" "$new"; exit 0
fi
if sfdisk -d "$disk" 2>/dev/null | grep "start=[ ]*${pstart}," | grep "size=[ ]*${newsize}," >/dev/null; then
  echo "[growroot] on-disk table verified (size=${newsize}); rebooting once so the kernel re-reads it"
  echo "verified: $(date)" >> "$MARKER"
  rm -f "$dump" "$new"
  sync
  /sbin/reboot
  exit 0
fi
echo "[growroot] POST-WRITE VERIFY FAILED; restoring from the backup dump"
if sfdisk --no-reread --force "$disk" < "$bak" >> "$LOG" 2>&1; then
  echo "[growroot] restore applied"
else
  echo "[growroot] restore failed -- inspect ${bak} manually"
fi
rm -f "$dump" "$new"
exit 0
EOF_GROWROOT
chmod 755 /etc/init.d/ol-aws-growroot
/sbin/chkconfig --add ol-aws-growroot
/sbin/chkconfig ol-aws-growroot on

# virt-sysprep prerequisites (see SPEC D.20; same rationale as OL6 -- EL5 has
# no systemd, so /etc/machine-id does not exist and the upstream --truncate
# would abort the Cleanup stage).
: > /etc/machine-id
[ -e /etc/resolv.conf ] || : > /etc/resolv.conf
EOF_OL5_KS

    # SELinux directive from the adjudicated env (record #10, run-9 sosreport
    # finding): the heredoc hardcoded `selinux --permissive` -- a leftover
    # from the pre-2026-07-20 adjudication -- and silently overrode
    # SELINUX=enforcing: on EL5, anaconda's `selinux` directive IS what
    # writes /etc/selinux/config, and the OL5 path has no later
    # provisioning-time application (upstream applies ${SELINUX} in
    # distr provision for OL6-10; OL5's EL5-safe cleanup never did).
    local _ol5_sel_lc
    _ol5_sel_lc="$(printf '%s' "${SELINUX:-enforcing}" | tr '[:upper:]' '[:lower:]')"
    case "${_ol5_sel_lc}" in
      enforcing|permissive|disabled) ;;
      *) die "SELINUX must be enforcing|permissive|disabled for the OL5 kickstart (got '${SELINUX}')" ;;
    esac
    sed -i -e "s/^selinux --permissive\$/selinux --${_ol5_sel_lc}/" "${ol5_slim_dir}/ol5-ks.cfg"
    grep -q "^selinux --${_ol5_sel_lc}\$" "${ol5_slim_dir}/ol5-ks.cfg" \
      || die "OL5 kickstart selinux templating failed (expected 'selinux --${_ol5_sel_lc}')"

    # ----- distr/ol5-slim/provision.sh (GUEST side; EL5 bash 3.2 / POSIX) -----
    cat > "${ol5_slim_dir}/provision.sh" <<'EOF_OL5_PROV'
#!/usr/bin/env bash
#
# Provisioning script for OL5
#
# Created by ol-aws-ami-builder (not part of upstream oracle-linux-image-tools).
# GUEST-SIDE code: EL5 ships bash 3.2 -- POSIX constructs only in every
# EXECUTED path (no ${var,,}/${var^^}, no mapfile, no |& etc.).
# Package installation is NOT done here: the [OLAWS-OL5S1] host-supply
# executor (appended to cloud/aws/provision.sh, source-time) has already
# installed the staged UEK R2 kernel, toolchain, cloud-init closure, and
# gdisk before any provision function runs.
#

# Never used on OL5 (no dracut on EL5); defined so any stray upstream
# reference fails loudly instead of resolving to an unrelated binary.
readonly DRACUT_CMD="/bin/false # dracut does not exist on EL5"

#######################################
# Remove packages (plain rpm; no usable yum repository on EL5)
#######################################
distr::remove_rpms() {
  rpm -e "$@" 2>/dev/null || true
}

#######################################
# Kernel configuration (verify-only -- [OLAWS-OL5S1] owns the install)
#######################################
distr::kernel_config() {
  common::echo_message "Verify kernel: UEK R2 (host-staged by [OLAWS-OL5S1])"
  kv=""
  for d in /lib/modules/*el5uek*; do
    [ -d "$d" ] && kv=$(basename "$d")
  done
  if [ -z "$kv" ]; then
    common::echo_message "FATAL: no el5uek kernel present -- [OLAWS-OL5S1] did not run?"
    exit 1
  fi
  common::echo_message "UEK R2 kernel present: ${kv}"
  if ! grep -q '^alias scsi_hostadapter nvme$' /etc/modprobe.conf; then
    common::echo_message "FATAL: modprobe.conf nvme alias missing"
    exit 1
  fi
}

#######################################
# Common configuration (EL5-safe)
#######################################
distr::common_cfg() {
  mkdir -p "${BUILD_INFO}"

  common::echo_message "Update image: NO (OL5 has no reachable in-guest repository)"

  # sshd root policy: cloud-init 0.6.3 (disable_root: 1) installs a
  # command-prefixed root key that prints the ec2-user hint -- that hint only
  # works when key-based root login is allowed. EL5 OpenSSH 4.3 accepts
  # 'without-password' (the modern 'prohibit-password' is unknown to it --
  # same class as the OL6/5.3 lesson).
  common::echo_message "sshd root login policy (OL5/OpenSSH 4.3): without-password"
  sed -i -e 's/^#\{0,1\}\(PermitRootLogin\) .*$/\1 without-password/' /etc/ssh/sshd_config
  # Validate with sshd's own parser before sealing (loud build-time abort
  # instead of a silent first-boot 'Connection refused'; OL6 precedent).
  sshd_bin=""
  [ -x /usr/sbin/sshd ] && sshd_bin=/usr/sbin/sshd
  if [ -n "$sshd_bin" ] && command -v ssh-keygen >/dev/null 2>&1; then
    tkey=/tmp/ol-aws-sshd-test.key
    rm -f "$tkey" "$tkey.pub"
    if ssh-keygen -q -t rsa -b 2048 -f "$tkey" -N "" </dev/null 2>/dev/null && [ -f "$tkey" ]; then
      if "$sshd_bin" -t -f /etc/ssh/sshd_config -h "$tkey" 2>/tmp/ol-aws-sshd-test.err; then
        common::echo_message "sshd_config validated by 'sshd -t' (OK)"
      else
        common::echo_message "FATAL: 'sshd -t' rejected the generated sshd_config:"
        cat /tmp/ol-aws-sshd-test.err 2>/dev/null || true
        rm -f "$tkey" "$tkey.pub" /tmp/ol-aws-sshd-test.err
        exit 1
      fi
      rm -f "$tkey" "$tkey.pub" /tmp/ol-aws-sshd-test.err
    else
      common::echo_message "WARNING: could not create an ephemeral test host key; skipped 'sshd -t'"
    fi
  else
    common::echo_message "WARNING: sshd/ssh-keygen not found; skipped 'sshd -t'"
  fi

  # ntp (EL5: /etc/ntp.conf; no chrony)
  if [ -f /etc/ntp.conf ]; then
    sed -i -e '/^server .*/d' /etc/ntp.conf
    cat >> /etc/ntp.conf <<'EOF_NTP'
server 0.rhel.pool.ntp.org iburst
server 1.rhel.pool.ntp.org iburst
server 2.rhel.pool.ntp.org iburst
server 3.rhel.pool.ntp.org iburst
EOF_NTP
  fi

  common::echo_message "Setting default runlevel to 3 (multi-user text mode)"
  sed -i -e 's/^id:.*:initdefault:/id:3:initdefault:/' /etc/inittab

  common::echo_message "Disable services (chkconfig)"
  for service in kudzu rhnsd sendmail kdump mcstrans; do
    common::echo_message "    ${service}"
    /sbin/chkconfig --del "${service}" 2>/dev/null || true
    /sbin/service "${service}" stop 2>/dev/null || true
  done
  common::echo_message "Enable services (chkconfig)"
  for service in rsyslog sshd network ntpd acpid; do
    /sbin/chkconfig "${service}" on 2>/dev/null || true
  done

  # rp_filter: EL5 (2.6.18) knows 0/1 only (loose mode '2' is 2.6.32+); the
  # cloud-friendly choice on this kernel is 0.
  echo "net.ipv4.conf.default.rp_filter = 0" >> /etc/sysctl.conf

  common::echo_message "Clear network persistent data"
  rm -f /etc/udev/rules.d/70-persistent-net.rules

  common::echo_message "Enable login on serial console ports"
  for tty in hvc0 ttyS0; do
    grep -q "${tty}" /etc/securetty || echo "${tty}" >> /etc/securetty
  done
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
# build-info contract (first-contact record #6): upstream build-image.sh
# unconditionally does `mv ${VM_DIR}/.build-info/* ${VM_DIR}/` after
# provisioning, so an EMPTY /.build-info fails the build even when
# provisioning fully succeeded. On OL6+ the files are written by
# common::distr_cleanup, which is EL5-unsafe -- so OL5 writes the same
# four files itself, EL5-safe. The path variables are overridable ONLY so
# the conformance tier can execute this function against fixtures; in the
# guest they always resolve to the defaults.
#######################################
distr::write_build_info() {
  : "${OL5_GRUB_CONF:=/boot/grub/grub.conf}"
  : "${OL5_MODULES_DIR:=/lib/modules}"
  mkdir -p "${BUILD_INFO}"

  echo "no reachable repositories on EL5 (host-supply model; see SPEC B.15)" \
    > "${BUILD_INFO}/repolist.txt"
  rpm -qa --qf "%{name}.%{arch}\n" | sort -u > "${BUILD_INFO}/pkglist.txt"
  # EL5 rpm 4.4 has no %{EPOCHNUM}; %{EPOCH} prints (none) for unset epochs.
  rpm -qa --qf '"%{NAME}","%{EPOCH}","%{VERSION}","%{RELEASE}","%{ARCH}"\n' \
    | sort > "${BUILD_INFO}/pkglist.csv"

  # kernel.txt: the DEFAULT kernel (upstream uses grubby, absent on EL5) --
  # parse grub.conf's default= entry; fall back to the newest el5uek under
  # /lib/modules; FATAL if neither yields a value (an empty kernel.txt would
  # silently break the build-info contract downstream).
  kv=""
  if [ -r "${OL5_GRUB_CONF}" ]; then
    idx=$(sed -n 's/^default=\([0-9][0-9]*\).*/\1/p' "${OL5_GRUB_CONF}" | head -1)
    [ -n "$idx" ] || idx=0
    kv=$(grep -E '^[[:space:]]*kernel[[:space:]]' "${OL5_GRUB_CONF}" \
         | sed -n "$((idx+1))p" \
         | sed -e 's!.*vmlinuz-!!' -e 's![[:space:]].*$!!')
  fi
  if [ -z "$kv" ]; then
    kv=$( (cd "${OL5_MODULES_DIR}" 2>/dev/null && ls -1 | grep el5uek | sort | tail -1) || true )
  fi
  [ -n "$kv" ] || { echo "[ol5-build-info] FATAL: cannot determine the default kernel for kernel.txt"; exit 1; }
  echo "$kv" > "${BUILD_INFO}/kernel.txt"
  common::echo_message "build-info written (kernel ${kv})"
}

#######################################
# Cleanup (EL5-safe, self-contained -- common::distr_cleanup is NOT called:
# its systemctl / /etc/yum/vars / ${EXCLUDE_DOCS^^} paths all break on EL5;
# its BUILD_INFO outputs are replaced by distr::write_build_info above)
#######################################
distr::cleanup() {
  /sbin/service rsyslog stop 2>/dev/null || true
  /sbin/service auditd stop 2>/dev/null || true

  common::echo_message "Package manager cleanup (rpmdb only; no usable yum on EL5)"
  rm -rf /var/cache/yum/* 2>/dev/null || true
  rpm --rebuilddb

  distr::write_build_info

  common::echo_message "Cleanup resolver files"
  # Record #9: newer guestfs-tools bind-mount the appliance resolv.conf
  # READ-ONLY over the guest file during virt-customize; tolerate EROFS
  # (the guest file was never written; build-image.sh --truncate ships it
  # clean at the guestfs API level).
  ( : > /etc/resolv.conf ) 2>/dev/null \
    || common::echo_message "  resolv.conf write skipped (read-only bind-mount; guestfs --truncate ships it clean)"
  rm -f /etc/resolv.conf.* 2>/dev/null || true

  common::echo_message "Misc cleanup"
  rm -f /root/.viminfo
  rm -f /etc/udev/rules.d/70-persistent-cd.rules
  find /etc/ -name "*.old" -exec rm -f {} \; 2>/dev/null || true
}
EOF_OL5_PROV

    chmod +x "${ol5_slim_dir}/image-scripts.sh" "${ol5_slim_dir}/provision.sh"
    log_info "  -> Generated 4 files in ${ol5_slim_dir}/"

    # ----- host-supply artifact staging: distr/ol5-slim/files/ -----
    #
    # Downloaded on the HOST (cached under WORKSPACE/ol5-stage across runs),
    # verified (RPM lead magic / gzip magic / zip magic), then staged into the
    # files channel. assert-all-then-write: everything is fetched and verified
    # in the cache first; the stage directory is (re)built only after ALL
    # artifacts pass.
    #   rpms/ : frozen ENA build-toolchain closure (11 RPMs, OL5/latest --
    #           byte-identical to the matrix's proven OL5_TOOLCHAIN_RPMS list),
    #           kernel-uek + -devel + -firmware (UEK/latest, live-resolved with
    #           a frozen fallback), the EPEL5 cloud-init 0.6.3 closure (9 RPMs)
    #           and gdisk (frozen NVRs, archives.fedoraproject.org)
    #   src/  : ena_linux_<ver>.tar.gz (the installer's /usr/src pre-stage
    #           contract) and awscli-exe-linux-x86_64-<ver>.zip
    local ol5_stage_cache="${WORKSPACE}/ol5-stage"
    local ol5_files_rpms="${ol5_slim_dir}/files/rpms"
    local ol5_files_src="${ol5_slim_dir}/files/src"
    local ol5_tool_base="https://yum.oracle.com/repo/OracleLinux/OL5/latest/x86_64/getPackage"
    local ol5_uek_base="https://yum.oracle.com/repo/OracleLinux/OL5/UEK/latest/x86_64"
    local ol5_epel_base="https://archives.fedoraproject.org/pub/archive/epel/5/x86_64"
    # Frozen toolchain closure (OL5 repos are terminal/immutable; a future 404
    # is a loud failure, not silent drift). 9 of 11 entries are byte-identical
    # to the matrix's OL5_TOOLCHAIN_RPMS (tests/ena/run-ena-buildtest-matrix.sh);
    # glibc-devel/glibc-headers INTENTIONALLY diverge (first-contact record #5):
    # they carry exact `glibc = NVR` requires, so they must match the RUNTIME
    # TARGET's base glibc -- the matrix container base is the latest errata
    # (123.0.2.el5_11.3) while the ISO guest base is U11 GA (123.0.1). The ENA
    # 2.12.3 build boundary is insensitive to this glibc-devel errata step
    # (kernel-module compile against kernel-uek-devel; gcc44 unchanged).
    local ol5_guest_glibc_nvr="2.5-123.0.1"
    local ol5_toolchain_rpms="binutils220-2.20.51.0.2-5.29.el5.x86_64.rpm
cpp-4.1.2-55.el5.x86_64.rpm
gcc-4.1.2-55.el5.x86_64.rpm
gcc44-4.4.7-11.el5_11.x86_64.rpm
glibc-devel-${ol5_guest_glibc_nvr}.x86_64.rpm
glibc-headers-${ol5_guest_glibc_nvr}.x86_64.rpm
gmp-4.1.4-10.el5.x86_64.rpm
kernel-headers-2.6.18-419.0.0.0.2.el5.x86_64.rpm
libgomp-4.4.7-11.el5_11.x86_64.rpm
libicu-3.6-5.16.1.x86_64.rpm
make-3.81-3.el5.x86_64.rpm
perl-5.8.8-43.el5_11.x86_64.rpm"
    # Frozen EPEL5 closure (archive is immutable; NVRs are the full dependency
    # closure of cloud-init 0.6.3 against OL5 base, machine-resolved from the
    # repo primary metadata -- see SPEC Part D) + gdisk (staged as a TOOL per
    # adjudication; the growroot implementation itself uses fdisk). gdisk
    # links ICU (record #5) -- its libicu*.so.36 requires are satisfied by
    # the libicu entry staged in the toolchain list above.
    local ol5_epel_rpms="cloud-init-0.6.3-0.12.bzr532.el5.noarch.rpm
gdisk-0.8.4-1.el5.x86_64.rpm
libffi-3.0.5-1.el5.x86_64.rpm
libyaml-0.1.2-8.el5.x86_64.rpm
python26-2.6.8-2.el5.x86_64.rpm
python26-PyYAML-3.08-4.el5.x86_64.rpm
python26-boto-2.27.0-1.el5.noarch.rpm
python26-cheetah-2.4.4-3.el5.x86_64.rpm
python26-configobj-4.7.2-5.el5.noarch.rpm
python26-libs-2.6.8-2.el5.x86_64.rpm"
    local ol5_uek_fallback_kver="2.6.39-400.297.3.el5uek"

    log_info "Staging OL5 host-supply artifacts (cache: ${ol5_stage_cache})"
    mkdir -p "${ol5_stage_cache}"

    _ol5_fetch() {
      # _ol5_fetch URL DEST MAGIC-HEX-PREFIX  (cache-aware; loud fail)
      local url="$1" dest="$2" magic="$3" got
      if [[ ! -s "${dest}" ]]; then
        log_info "  fetch: ${url##*/}"
        curl -fsSL --max-time 900 -o "${dest}.part" "${url}" \
          || die "OL5 staging: download failed: ${url}"
        mv -f "${dest}.part" "${dest}"
      fi
      got="$(od -An -N4 -tx1 "${dest}" 2>/dev/null | tr -d ' \n')"
      [[ "${got}" == ${magic}* ]] \
        || die "OL5 staging: magic mismatch for ${dest##*/} (got ${got}, want ${magic}*) -- corrupt download?"
    }

    # (1) toolchain closure
    local _rpm
    for _rpm in ${ol5_toolchain_rpms}; do
      _ol5_fetch "${ol5_tool_base}/${_rpm}" "${ol5_stage_cache}/${_rpm}" "edabeedb"
    done
    # (2) UEK R2 kernel set: live-resolve the newest NVRs from the (frozen)
    # UEK/latest channel; fall back to the pinned terminal kver offline.
    local ol5_uek_primary="${ol5_stage_cache}/uek-primary.xml.gz"
    local _uek_pkgs="" _n
    if curl -fsSL --max-time 120 -o "${ol5_uek_primary}" "${ol5_uek_base}/repodata/primary.xml.gz" 2>/dev/null; then
      for _n in kernel-uek kernel-uek-devel kernel-uek-firmware; do
        _rpm="$(zcat "${ol5_uek_primary}" \
                 | grep -oE "getPackage/${_n}-2[^\"]*\.rpm" \
                 | sed 's!^getPackage/!!' | sort -V | tail -1 || true)"
        [[ -n "${_rpm}" ]] || die "OL5 staging: could not resolve ${_n} from ${ol5_uek_base} repodata"
        _uek_pkgs="${_uek_pkgs} ${_rpm}"
      done
    else
      log_warn "  UEK/latest repodata unreachable; using the frozen fallback kver ${ol5_uek_fallback_kver}"
      _uek_pkgs="kernel-uek-${ol5_uek_fallback_kver}.x86_64.rpm kernel-uek-devel-${ol5_uek_fallback_kver}.x86_64.rpm kernel-uek-firmware-${ol5_uek_fallback_kver}.noarch.rpm"
    fi
    for _rpm in ${_uek_pkgs}; do
      _ol5_fetch "${ol5_uek_base}/getPackage/${_rpm}" "${ol5_stage_cache}/${_rpm}" "edabeedb"
    done
    # (3) EPEL5 closure + gdisk
    for _rpm in ${ol5_epel_rpms}; do
      _ol5_fetch "${ol5_epel_base}/${_rpm}" "${ol5_stage_cache}/${_rpm}" "edabeedb"
    done
    # (4) source artifacts (per-feature: skipped with the feature)
    local ol5_src_files=""
    if [[ "${ENA_DRIVER_BUILD}" -eq 1 ]]; then
      local _ena_v="${ENA_BUILD_VERSION:-$(_ena_pin_for_major 5)}"
      [[ -n "${_ena_v}" ]] || die "OL5 staging: could not determine the ENA build version"
      _ol5_fetch "https://github.com/amzn/amzn-drivers/archive/refs/tags/ena_linux_${_ena_v}.tar.gz" \
        "${ol5_stage_cache}/ena_linux_${_ena_v}.tar.gz" "1f8b"
      ol5_src_files="${ol5_src_files} ena_linux_${_ena_v}.tar.gz"
    fi
    if [[ "${AWSCLI_INSTALL}" -eq 1 ]]; then
      local _cli_v="${AWSCLI_RESOLVED:-$(_awscli_pin_for_major 5)}"
      [[ -n "${_cli_v}" && "${_cli_v}" != "latest" ]] || die "OL5 staging: could not determine the AWS CLI v2 version"
      _ol5_fetch "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${_cli_v}.zip" \
        "${ol5_stage_cache}/awscli-exe-linux-x86_64-${_cli_v}.zip" "504b0304"
      ol5_src_files="${ol5_src_files} awscli-exe-linux-x86_64-${_cli_v}.zip"
    fi
    # (4.5) dependency-closure gate over the EXACT staged set (record #5) --
    # dies in seconds here instead of ~45 minutes into the guest install.
    # shellcheck disable=SC2086
    _ol5_stage_closure_gate "${ol5_stage_cache}" "${ol5_guest_glibc_nvr}" \
      ${ol5_toolchain_rpms} ${_uek_pkgs} ${ol5_epel_rpms}

    # (5) everything verified -- (re)build the stage tree
    rm -rf "${ol5_slim_dir}/files"
    mkdir -p "${ol5_files_rpms}" "${ol5_files_src}"
    for _rpm in ${ol5_toolchain_rpms} ${_uek_pkgs} ${ol5_epel_rpms}; do
      cp -f "${ol5_stage_cache}/${_rpm}" "${ol5_files_rpms}/"
    done
    local _src
    for _src in ${ol5_src_files}; do
      cp -f "${ol5_stage_cache}/${_src}" "${ol5_files_src}/"
    done
    # src/ must exist even when empty (the [OLAWS-OL5S1] guest assert requires
    # the directory; per-feature files are legitimately absent under --skip-*).
    log_info "  -> Staged $(find "${ol5_files_rpms}" -name '*.rpm' | wc -l) RPM(s) + $(find "${ol5_files_src}" -type f | wc -l) source artifact(s) into ${ol5_slim_dir}/files/"
    unset -f _ol5_fetch
  fi

  # Finalize the reproducibility record with the applied markers + artifact
  # hashes, THEN gate: a gate failure references a complete provenance file.
  _record_upstream_provenance_patched
  _p3_exit_gate

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
  # OL5 ONLY: this file joins the guest-bound env concatenation (see the
  # Phase-3 P3GATE channel scan) -- verify the wrapper's own output too.
  if [[ "${OL_MAJOR_VERSION}" -eq 5 ]]; then
    local _lhostile
    if ! _lhostile="$(_ol5_scan_bash32_hostile "${tool_env}")"; then
      die "env.properties.local contains bash-4-only construct(s) but the EL5 guest sources it:
${_lhostile}"
    fi
  fi
  echo "----- env.properties.local -----"
  grep -v '^#' "${tool_env}" | grep -v '^$'
  echo "--------------------------------"
}

#------------------------------------------------------------------------------
# Phase-5 progress heartbeat (runs in the background during the build)
#------------------------------------------------------------------------------
# Visibility independent of the install console. Every ${interval} seconds it
# logs elapsed time and the build VM disk's ACTUAL on-disk growth (du -k, i.e.
# real clusters written, not the preallocated apparent size), plus best-effort
# domain state. This is generation-independent: OL6/anaconda-13 streams text to
# the serial console, but OL8+ anaconda runs in tmux and is near-silent there,
# so this is the reliable way to confirm a headless build is alive/progressing.
# Args: $1 = WORKSPACE, $2 = interval (seconds). Loops until killed.
#------------------------------------------------------------------------------
phase5_progress_heartbeat() {
  local ws="$1" interval="$2"
  local start prev_kb=0
  start=$(date +%s)
  # A: runs as a background job on its OWN timer, independent of the build pipe,
  # so it keeps reporting even while build-image.sh is blocked in a long, quiet
  # in-guest step. Each tick is assembled into one string and emitted as a SINGLE
  # log_progress write (atomic under PIPE_BUF), so it never interleaves mid-line
  # with the [EXTERNAL] stream that shares stdout.
  while :; do
    sleep "${interval}"
    local img elapsed used_kb used_h name state delta_mb stage msg
    img=$(find "${ws}" -maxdepth 3 -name '*.qcow2' 2>/dev/null | head -n 1)
    elapsed=$(( ($(date +%s) - start) / 60 ))
    # B: append the latest LIVE orchestrator stage (recorded by log_external),
    # truncated so the heartbeat line stays readable. During a long quiet in-guest
    # compile this holds the last build-image.sh line (e.g. the customize step),
    # which is exactly what "looks idle but is alive" should show.
    stage=""
    if [[ -n "${BUILD_STAGE_FILE:-}" && -r "${BUILD_STAGE_FILE}" ]]; then
      stage=$(tail -n 1 "${BUILD_STAGE_FILE}" 2>/dev/null | cut -c1-70)
      [[ -n "${stage}" ]] && stage=" | stage: ${stage}"
    fi
    if [[ -n "${img}" && -f "${img}" ]]; then
      used_kb=$(du -k "${img}" 2>/dev/null | awk '{print $1}')
      used_h=$(du -h "${img}" 2>/dev/null | awk '{print $1}')
      name=$(basename "${img}" .qcow2)
      state=$(virsh --connect qemu:///system domstate "${name}" 2>/dev/null | head -n 1 || true)
      [[ -z "${state}" ]] && state="(no domain)"
      delta_mb=$(( (${used_kb:-0} - prev_kb) / 1024 ))
      msg="elapsed ${elapsed}m | disk ${used_h} ($(printf '%+d' "${delta_mb}")MB) | vm ${state}${stage}"
      prev_kb=${used_kb:-0}
    else
      msg="elapsed ${elapsed}m | build image not yet allocated${stage}"
    fi
    log_progress "${msg}"
  done
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
  log_info "Build watchdog: ${BUILD_TIMEOUT_MIN} min outer bound (SERIAL_CONSOLE=${SERIAL_CONSOLE})"
  if [[ "${SERIAL_CONSOLE,,}" == "yes" ]]; then
    log_info "SERIAL_CONSOLE=yes under this wrapper is NON-INTERACTIVE (serial-noninteractive patch v2):"
    log_info "  the full anaconda serial output is virtlogd-captured to /var/log/libvirt/qemu/<vm-name>-install-serial.log"
    log_info "  (watch live from another terminal: tail -f /var/log/libvirt/qemu/*-install-serial.log"
    log_info "   or attach interactively there with: virsh console <vm-name>  -- the device stays pty)"
  fi

  # Snapshot running libvirt domains BEFORE the build so a watchdog timeout can
  # reap the transient install VM. virt-install --transient domains are managed
  # by libvirtd and survive a killed build-image.sh, so they would otherwise
  # keep running (and hold the workspace disk) after we abort.
  local doms_before
  doms_before=$(virsh list --name 2>/dev/null | sed '/^$/d' | sort || true)

  local build_rc=0
  # B: shared stage file the heartbeat reads and log_external writes (latest
  # live orchestrator line). Lives in WORKSPACE; reset now, removed after.
  BUILD_STAGE_FILE="${WORKSPACE}/.build-stage"
  : > "${BUILD_STAGE_FILE}" 2>/dev/null || BUILD_STAGE_FILE=""
  # Start the progress heartbeat (visibility independent of the install
  # console). Stopped right after the build returns, so it covers the success,
  # failure, and watchdog-timeout paths below.
  local hb_pid=""
  if [[ "${HEARTBEAT_INTERVAL_SEC}" -gt 0 ]] 2>/dev/null; then
    phase5_progress_heartbeat "${WORKSPACE}" "${HEARTBEAT_INTERVAL_SEC}" &
    hb_pid=$!
    log_info "Progress heartbeat: every ${HEARTBEAT_INTERVAL_SEC}s (set HEARTBEAT_INTERVAL_SEC=0 to disable)"
  fi

  # Attribute every line of the external oracle-linux-image-tools output (the
  # build-image.sh orchestrator plus the libguestfs / virt-* sub-tools it runs)
  # as "[EXTERNAL] HH:MM:SS [build-image.sh] <line>", clearly separating it from
  # this wrapper's own [INFO]/[BUILD] lines. 2>&1 folds external stderr into the
  # attributed stream; 'set -o pipefail' (top of file) propagates the
  # timeout/build exit status through the pipe so build_rc reflects the result.
  # The single-quoted `bash -c '...$1...$2...'` is the intended secure idiom:
  # the qcow2 dir and env path are passed as positional parameters ($1/$2) and
  # must NOT be expanded by the outer shell (injection-safe). SC2016 is a false
  # positive here.
  # shellcheck disable=SC2016
  timeout --signal=TERM --kill-after=60s "${BUILD_TIMEOUT_MIN}m" \
    bash -c 'cd "$1" && ./bin/build-image.sh --env "$2"' _ "${tool_dir}" "${tool_env}" 2>&1 \
    | log_external "build-image.sh" || build_rc=$?

  if [[ -n "${hb_pid}" ]]; then
    kill "${hb_pid}" 2>/dev/null || true
    wait "${hb_pid}" 2>/dev/null || true
  fi
  if [[ -n "${BUILD_STAGE_FILE:-}" ]]; then
    rm -f "${BUILD_STAGE_FILE}" 2>/dev/null || true
  fi

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
# Phase 6: Nitro readiness pre-check (offline image inspection)
#------------------------------------------------------------------------------

# modinfo the ENA module version out of the built image. Args:
#   $1 img  $2 kver  $3 work-dir  $4 module path relative to /lib/modules/<kver>
# Echoes the version string, or "" if the module is absent/unreadable. Each call
# copies into its own temp subdir so the stock /kernel copy and the self-built
# /extra|/updates copy (same basename) do not collide. Used by the Phase-6
# assurance report to show the in-box and self-built ENA versions side by side.
_ena_module_version() {
  local img="$1" kver="$2" work="$3" rel="$4" d f
  [[ -n "${rel}" ]] || return 0
  d="$(mktemp -d "${work}/ena.XXXXXX")" || return 0
  virt-copy-out -a "${img}" "/lib/modules/${kver}${rel}" "${d}/" 2>/dev/null || true
  f="${d}/$(basename "${rel}")"
  [[ -r "${f}" ]] || return 0
  case "${f}" in
    *.xz)  xz   -df "${f}" 2>/dev/null || true; f="${f%.xz}";;
    *.gz)  gzip -df "${f}" 2>/dev/null || true; f="${f%.gz}";;
    *.zst) zstd -df "${f}" 2>/dev/null || true; f="${f%.zst}";;
  esac
  command -v modinfo >/dev/null 2>&1 || return 0
  modinfo -F version "${f}" 2>/dev/null | head -1 || true
}

# Resolve the ENA self-build pin for an OL major by reading the single source of
# truth -- install-ena-driver.sh's ENA_VERSION_OL<major> default -- so wrapper-side
# messages, the AMI name/description, and the hook log never drift from the
# installer's actual pins. Echoes empty if it cannot be determined.
_ena_pin_for_major() {
  local major="$1" inst="${SCRIPT_DIR}/install-ena-driver.sh" pin
  [[ -f "${inst}" ]] || return 0
  # The installer's canonical pin form is NAME="${NAME:-<pin>}" where <pin> is
  # empty on the latest-resolving majors (OL8/9/10). '[^}"]*' (zero-or-more)
  # matches that empty default; 'sed -n ... p' prints nothing when the line
  # does not have the ':-...}' shape at all. BUG HISTORY: the original
  # '[^}"]+' (one-or-more) did not match the empty default, so sed passed the
  # whole assignment line through and the raw text leaked into the AMI name
  # (caught by the first real OL8-10 build, 2026-07-11).
  pin="$(grep -E "^ENA_VERSION_OL${major}=" "${inst}" | head -1 \
           | sed -nE 's/.*:-([^}"]*)\}.*/\1/p')"
  # Emit only a concrete x.y.z. Empty (latest-resolving majors) and any
  # unrecognized pin form both yield "": callers treat "" as "resolve latest /
  # use fallback", so a parser miss can never reach the AMI identity again.
  if [[ "${pin}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' "${pin}"
  fi
}

# Resolve the amzn-drivers "latest" ENA tag to a concrete, published version --
# for the persistent AMI name/description + the guest hook's target on the
# latest-resolving majors (OL8/9/10, whose installer pins are empty). Mirrors
# _awscli_resolve_latest (git ls-remote tags newest-first, then HEAD-verify the
# artifact -- here the source tarball -- so a tag that leads archive publication
# is never selected) and the installer's own _ena_resolve_latest ground-truth
# method. Echoes the concrete version, or "" on any failure (the caller then
# falls back to the installer's ENA_LATEST_FALLBACK_PIN -- the AMI identity
# always carries a concrete x.y.z, never the word "latest"). git + curl are
# already build-host dependencies.
_ena_resolve_latest_host() {
  local repo="https://github.com/amzn/amzn-drivers"
  local tags v i=0
  tags="$(git ls-remote --tags "${repo}" 'ena_linux_*' 2>/dev/null \
            | sed -E 's#.*refs/tags/ena_linux_##; s/\^\{\}$//' \
            | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+$' \
            | sort -t. -k1,1n -k2,2n -k3,3n -u | tac)"
  [[ -n "${tags}" ]] || return 0
  while IFS= read -r v; do
    [[ -n "${v}" ]] || continue
    i=$((i+1)); [[ ${i} -gt 12 ]] && break   # bounded probe window (archive lag is small)
    if curl -fsIL --max-time 15 "${repo}/archive/refs/tags/ena_linux_${v}.tar.gz" >/dev/null 2>&1; then
      printf '%s' "${v}"; return 0
    fi
  done <<< "${tags}"
  return 0
}

# Read the installer's ENA_LATEST_FALLBACK_PIN default (a concrete x.y.z) --
# the single source of truth for the offline fallback, so the AMI identity and
# the guest build agree even when the host cannot reach GitHub. Mirrors
# _ena_pin_for_major.
_ena_fallback_pin() {
  local inst="${SCRIPT_DIR}/install-ena-driver.sh" pin
  [[ -f "${inst}" ]] || return 0
  # Same shape-guarded parser as _ena_pin_for_major (see the BUG HISTORY
  # note there): only a concrete x.y.z is ever emitted.
  pin="$(grep -E "^ENA_LATEST_FALLBACK_PIN=" "${inst}" | head -1 \
           | sed -nE 's/.*:-([^}"]*)\}.*/\1/p')"
  if [[ "${pin}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' "${pin}"
  fi
}

# Resolve the SSM Agent version for an OL major from install-ssm-agent.sh's
# per-OL map (SSM_AGENT_VERSION_OL<major>); echoes "latest" or a pin. Mirrors
# _ena_pin_for_major. Used only for the AMI name/description marker.
_ssm_pin_for_major() {
  local major="$1" inst="${SCRIPT_DIR}/install-ssm-agent.sh"
  [[ -f "${inst}" ]] || return 0
  grep -E "^SSM_AGENT_VERSION_OL${major}=" "${inst}" \
    | sed -E 's/.*:-([^}"]+)\}.*/\1/' | head -1
}

# Resolve the SSM Agent "/latest/" alias to a concrete, S3-published version --
# for the persistent AMI name/description + the final report only ("latest" is
# unsuitable for a persistent artifact). The guest install is UNCHANGED: the hook
# still installs the per-OL target (the /latest/ alias for OL7-OL10). Strategy,
# Resolve the SSM Agent "latest" to a concrete, S3-published version -- for the
# persistent AMI name/description + the final report only (the AMI identity
# always carries a concrete x.y.z.w and NEVER the word "latest"; parity with
# the awscli marker). curl-only (no rpm dependency on the build host).
# Layer 1 (primary): read the S3 release channel's own latest/VERSION file --
# this is the exact content of the /latest/ alias the guest installs, so it can
# neither lead nor lag the install. (Root cause of the 2026-07-18 '-ssmlatest'
# AMI-name degradation: the previous GitHub-first strategy failed closed
# precisely when the GitHub tag led S3 publication -- 3.3.4851.0 was tagged
# with its RPM still 403 on S3 while latest/VERSION answered 3.3.4793.0.)
# Layer 2 (fallback, e.g. if the VERSION file scheme ever disappears): GitHub's
# releases/latest tag, VERIFIED against S3 with a HEAD (tags can lead S3 --
# e.g. 3.3.3883.0 / 3.3.4364.0 / 3.3.4851.0). Echoes the concrete version, or
# "" on total failure (the caller then OMITS the ssm marker entirely).
_ssm_resolve_latest() {
  local base="https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent" arch="linux_amd64"
  local loc ver
  ver="$(curl -fsSL --max-time 15 "${base}/latest/VERSION" 2>/dev/null | tr -d '[:space:]' || true)"
  if [[ "${ver}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s' "${ver}"
    return 0
  fi
  loc="$(curl -fsSL -o /dev/null -w '%{url_effective}' --max-time 15 \
         https://github.com/aws/amazon-ssm-agent/releases/latest 2>/dev/null || true)"
  ver="$(printf '%s' "${loc}" | sed -nE 's#.*/tag/([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+).*#\1#p')"
  [[ -n "${ver}" ]] || return 0
  curl -fsI --max-time 15 "${base}/${ver}/${arch}/amazon-ssm-agent.rpm" >/dev/null 2>&1 || return 0
  printf '%s' "${ver}"
}

# Resolve the AWS CLI v2 version for an OL major from install-awscli.sh's per-OL
# map (AWSCLI_VERSION_OL<major>); echoes "latest" or a pin (OL6 -> 2.17.51,
# OL7/OL8 -> latest). Mirrors _ssm_pin_for_major. Used only for the AMI
# name/description marker + report (OL6/OL7/OL8 only).
_awscli_pin_for_major() {
  local major="$1" inst="${SCRIPT_DIR}/install-awscli.sh"
  [[ -f "${inst}" ]] || return 0
  grep -E "^AWSCLI_VERSION_OL${major}=" "${inst}" \
    | sed -E 's/.*:-([^}"]+)\}.*/\1/' | head -1
}

# Resolve the AWS CLI v2 "latest" to a concrete, CDN-published version -- for the
# persistent AMI name/description + the final report only (the AMI identity always
# carries a concrete x.y.z, never the word "latest"). The guest install is
# UNCHANGED: the OL7/OL8 hook still installs the latest bundle. Strategy, mirroring
# _ssm_resolve_latest but adapted to aws-cli (which does NOT publish GitHub
# "releases", so the releases/latest redirect does not work): enumerate the v2 tags
# with `git ls-remote --tags` (the same auth-free method as list-awscli-releases.sh),
# walk them newest-first, and return the highest whose bundle zip is actually
# published on the CDN (a HEAD) -- the newest tag can lead CDN publication, so a
# plain "take the max tag" would point at an unpublished version. Echoes the
# concrete version, or "" on any failure (the caller then omits the awscli marker
# rather than printing "latest"). git + curl are already build-host dependencies.
_awscli_resolve_latest() {
  local repo="https://github.com/aws/aws-cli"
  local zbase="https://awscli.amazonaws.com/awscli-exe-linux-x86_64"
  local tags v i=0
  tags="$(git ls-remote --tags "${repo}" 2>/dev/null \
            | sed -E 's#.*refs/tags/v?##; s/\^\{\}$//' \
            | grep -oE '^2\.[0-9]+\.[0-9]+$' \
            | sort -t. -k1,1n -k2,2n -k3,3n -u | tac)"
  [[ -n "${tags}" ]] || return 0
  while IFS= read -r v; do
    [[ -n "${v}" ]] || continue
    i=$((i+1)); [[ ${i} -gt 12 ]] && break   # bounded probe window (CDN lag is small)
    if curl -fsI --max-time 15 "${zbase}-${v}.zip" >/dev/null 2>&1; then
      printf '%s' "${v}"; return 0
    fi
  done <<< "${tags}"
  return 0
}

# CHECK 2 provenance verdict: is the effective ena.ko acceptable for THIS build?
# When a self-build was performed (ENA_BUILD_VERSION is non-empty -- set for
# OL5/OL6/OL7 with the default self-build on), the in-guest self-build (DKMS on
# OL6/OL7; plain make on OL5 -- no DKMS on EL5) MUST have
# produced the module in /updates or /extra; the stock in-tree /kernel copy alone
# means the self-build did not take effect and the AMI would ship the stock
# driver instead of the requested pin. When no self-build was requested
# (--skip-ena-driver, OL8+ in-distro, OL9+ no-op -> ENA_BUILD_VERSION empty) any
# present module is the expected, correct outcome. Pure (args only) -> unit-tested.
#   _ena_check2_ok <ena_build_version> <ena_mod_path>
# returns 0 if acceptable; 1 if a self-build was requested but only the stock
# module is present.
_ena_check2_ok() {
  local want="$1" mod="$2"
  [[ -z "${want}" ]] && return 0   # no self-build requested -> any module is fine
  case "${mod}" in
    */updates/*|*/extra/*) return 0 ;;   # self-built module present -> ok
  esac
  return 1                                # self-build requested but only stock present
}

phase6_nitro_readiness_check() {
  # Offline, read-only Nitro boot-readiness gate. Adapts the logic of AWS's
  # NitroInstanceChecks to inspect the BUILT IMAGE (no EC2 launch) via
  # libguestfs, targeting the UEK kernel. Blocking findings abort the run
  # before the wasted upload/snapshot/register phases. Detection only -- no
  # remediation. See SPEC A.7 (NITRO_PRECHECK) and Part C.
  local mode="${NITRO_PRECHECK,,}"

  if [[ "${mode}" == "off" ]]; then
    log_info "Nitro readiness pre-check: skipped (NITRO_PRECHECK=off)"
    return 0
  fi

  log_step "Phase 6: Nitro readiness pre-check (offline image inspection)"

  local img="${VMDK_PATH:-}"
  if [[ -z "${img}" || ! -f "${img}" ]]; then
    log_warn "No VMDK to inspect (VMDK_PATH unset); skipping Nitro pre-check"
    return 0
  fi

  # Dependency preflight (fail-open: a missing tool must not abort a good build).
  local missing=() t
  for t in virt-ls virt-cat virt-copy-out; do
    command -v "${t}" >/dev/null 2>&1 || missing+=("${t}")
  done
  if ! command -v unmkinitramfs >/dev/null 2>&1 && ! command -v lsinitrd >/dev/null 2>&1; then
    missing+=("unmkinitramfs|lsinitrd")
  fi
  if [[ "${#missing[@]}" -gt 0 ]]; then
    log_warn "Nitro pre-check inspection tools missing: ${missing[*]}"
    log_warn "  Install with: sudo apt-get install -y libguestfs-tools  (unmkinitramfs ships in initramfs-tools-core)"
    log_warn "  Skipping the pre-check (fail-open); the built image was NOT verified for Nitro readiness."
    return 0
  fi

  export LIBGUESTFS_BACKEND=direct
  local work; work="$(mktemp -d "${TMPDIR:-/tmp}/nitro-precheck.XXXXXX")"

  local fail=0 indeterminate=0

  # --- target the UEK kernel (mandated for OL on Nitro) ----------------------
  local kvers kver
  kvers="$(virt-ls -a "${img}" /lib/modules 2>/dev/null | sort -V || true)"
  kver="$(printf '%s\n' "${kvers}" | grep -i uek | sort -V | tail -1 || true)"
  if [[ -z "${kver}" ]]; then
    log_error "  No UEK kernel found under /lib/modules (UEK is mandated for OL on Nitro)."
    kver="$(printf '%s\n' "${kvers}" | sort -V | tail -1 || true)"
    fail=1
  fi
  log_info "  Target kernel: ${kver:-<none>}"

  # kernel config + module tree (read once)
  local cfg=""
  virt-copy-out -a "${img}" "/boot/config-${kver}" "${work}/" 2>/dev/null || true
  [[ -r "${work}/config-${kver}" ]] && cfg="${work}/config-${kver}"
  # Scan the FULL module tree under /lib/modules/<kver> -- not just /kernel.
  # DKMS (the in-guest ENA self-build) installs the built ena.ko into /extra
  # (or /updates/dkms), which depmod ranks ABOVE the stock /kernel copy;
  # scanning only /kernel missed the self-built driver and made CHECK 2
  # falsely FAIL on default (ENA-self-build) builds. virt-ls -R returns paths
  # relative to this dir (e.g. /kernel/.../nvme.ko.xz, /extra/ena.ko.xz).
  local tree
  tree="$(virt-ls -R -a "${img}" "/lib/modules/${kver}" 2>/dev/null || true)"

  local nvme_cfg="" core_cfg="" ena_cfg=""
  if [[ -n "${cfg}" ]]; then
    nvme_cfg="$(grep -E '^CONFIG_BLK_DEV_NVME=' "${cfg}" | head -1 | cut -d= -f2 || true)"
    core_cfg="$(grep -E '^CONFIG_NVME_CORE='   "${cfg}" | head -1 | cut -d= -f2 || true)"
    ena_cfg="$(grep -E '^CONFIG_ENA_ETHERNET=' "${cfg}" | head -1 | cut -d= -f2 || true)"
  fi

  # --- CHECK 1: NVMe host driver (find the EBS/NVMe root at boot) -------------
  # nvme.ko must be built into the kernel or present in the initramfs so Nitro
  # can mount the NVMe-backed EBS root. We confirm (a) the module exists in the
  # on-disk module tree and (b) it is in the initramfs. dracut initramfs images
  # vary by compression (gzip/xz/zstd/lz4) and may carry a leading uncompressed
  # microcode cpio, so a single extractor can fail to read one format while
  # succeeding on another (observed: OL6's image inspectable on an Ubuntu host,
  # OL7's not). We therefore try several listing methods; and crucially, if the
  # initramfs exists but NONE of them can read it, we report INDETERMINATE
  # (fail-open) instead of FAIL, so a host-side extraction gap never blocks an
  # otherwise-good build. A hard FAIL is reserved for the case where nvme.ko is
  # genuinely absent from both the kernel and an inspectable initramfs.
  local nvme_mod nvme_initrd="" initrd initrd_inspected=0
  nvme_mod="$(printf '%s\n' "${tree}" | grep -E '(^|/)nvme\.ko(\.[a-z0-9]+)?$' | head -1 || true)"
  initrd="$(virt-ls -a "${img}" /boot 2>/dev/null | grep -E "^initramfs-${kver}\.img$" | head -1 || true)"
  [[ -z "${initrd}" ]] && initrd="$(virt-ls -a "${img}" /boot 2>/dev/null | grep -E "initramfs.*${kver}|initrd.*${kver}" | head -1 || true)"
  if [[ -n "${initrd}" ]]; then
    virt-copy-out -a "${img}" "/boot/${initrd}" "${work}/" 2>/dev/null || true
    if [[ -r "${work}/${initrd}" ]]; then
      local listing="${work}/initrd-listing.txt"; : > "${listing}"
      # Method 1: unmkinitramfs extraction (handles concatenated early-cpio).
      mkdir -p "${work}/initrd"
      if unmkinitramfs "${work}/${initrd}" "${work}/initrd" 2>/dev/null; then
        find "${work}/initrd" -name '*.ko*' 2>/dev/null >> "${listing}" || true
      fi
      # Method 2: dracut's own lister, if present on the host.
      if ! grep -qE '\.ko' "${listing}" 2>/dev/null && command -v lsinitrd >/dev/null 2>&1; then
        lsinitrd "${work}/${initrd}" 2>/dev/null >> "${listing}" || true
      fi
      # Method 3: initramfs-tools lister, if present.
      if ! grep -qE '\.ko' "${listing}" 2>/dev/null && command -v lsinitramfs >/dev/null 2>&1; then
        lsinitramfs "${work}/${initrd}" 2>/dev/null >> "${listing}" || true
      fi
      # Method 4: best-effort manual decompress + cpio table of contents
      # (covers single-stream images that the above could not read).
      if ! grep -qE '\.ko' "${listing}" 2>/dev/null; then
        local dc
        for dc in zstdcat xzcat zcat lz4cat; do
          command -v "${dc}" >/dev/null 2>&1 || continue
          if "${dc}" < "${work}/${initrd}" 2>/dev/null | cpio -t 2>/dev/null > "${work}/cpio-t.txt" && [[ -s "${work}/cpio-t.txt" ]]; then
            cat "${work}/cpio-t.txt" >> "${listing}"; break
          fi
        done
      fi
      if [[ -s "${listing}" ]]; then
        initrd_inspected=1
        nvme_initrd="$(grep -E '(^|/)nvme\.ko(\.[a-z0-9]+)?$' "${listing}" | head -1 || true)"
      fi
    fi
  fi
  if [[ "${nvme_cfg}" == "y" && "${core_cfg}" == "y" ]]; then
    log_info "  [OLAWS-CHK01] [CHECK 1] NVMe host driver: PASS (built into the kernel)"
  elif [[ -n "${nvme_initrd}" ]]; then
    log_info "  [OLAWS-CHK01] [CHECK 1] NVMe host driver: PASS (module present in the initramfs)"
  elif [[ -n "${nvme_mod}" && "${initrd_inspected}" -eq 0 ]]; then
    log_warn "  [OLAWS-CHK01] [CHECK 1] NVMe host driver: INDETERMINATE (module present on disk; initramfs could not be inspected on this host -- verify the target boots)"
    indeterminate=1
  elif [[ -n "${nvme_mod}" && -z "${initrd}" ]]; then
    log_warn "  [OLAWS-CHK01] [CHECK 1] NVMe host driver: INDETERMINATE (module exists; no initramfs found to inspect)"
    indeterminate=1
  else
    log_error "  [OLAWS-CHK01] [CHECK 1] NVMe host driver: FAIL (not built-in and not in an inspectable initramfs -- Nitro cannot mount the root)"
    fail=1
  fi

  # --- CHECK 2: ENA network driver (Nitro networking) ------------------------
  # Pick the EFFECTIVE ena.ko by depmod precedence (updates > extra > kernel),
  # so a DKMS self-built module (in /extra or /updates) wins over the stock
  # in-tree copy -- which is also what the running kernel would load. Classify
  # its provenance so the report can state whether the in-guest self-build took
  # effect (F2) without depending on the wrapper's own --skip-ena-driver flag.
  local ena_mod ena_loc="" ena_all
  ena_all="$(printf '%s\n' "${tree}" | grep -E '(^|/)ena\.ko(\.[a-z0-9]+)?$' || true)"
  ena_mod="$(printf '%s\n' "${ena_all}" | grep -E '(^|/)updates/' | head -1 || true)"
  [[ -z "${ena_mod}" ]] && ena_mod="$(printf '%s\n' "${ena_all}" | grep -E '(^|/)extra/' | head -1 || true)"
  [[ -z "${ena_mod}" ]] && ena_mod="$(printf '%s\n' "${ena_all}" | grep -E '\S' | head -1 || true)"
  # Build-kind truthfulness: OL5 self-builds via plain make (no DKMS on EL5);
  # OL6+ self-build via DKMS. /updates|/extra placement is shared.
  local ena_bk="DKMS"
  [[ "${OL_MAJOR_VERSION}" -eq 5 ]] && ena_bk="plain-make"
  case "${ena_mod}" in
    */updates/*) ena_loc="self-built, ${ena_bk} /updates" ;;
    */extra/*)   ena_loc="self-built, ${ena_bk} /extra" ;;
    ?*)          ena_loc="stock in-tree /kernel" ;;
  esac
  if [[ "${ena_cfg}" == "y" ]]; then
    log_info "  [OLAWS-CHK02] [CHECK 2] ENA driver: PASS (built into the kernel)"
  elif [[ -n "${ena_mod}" ]]; then
    if _ena_check2_ok "${ENA_BUILD_VERSION:-}" "${ena_mod}"; then
      log_info "  [OLAWS-CHK02] [CHECK 2] ENA driver: PASS (module present -- ${ena_loc})"
    else
      # A self-build was requested (pin set) but the effective module is the
      # stock in-tree copy: the in-guest DKMS self-build did not take effect, so
      # the AMI would carry the stock driver, not the requested pin. (install-ena-
      # driver.sh now aborts on a failed build, so this should not occur via the
      # wrapper; the image check guards manual builds / regressions regardless.)
      log_error "  [OLAWS-CHK02] [CHECK 2] ENA driver: FAIL (self-build requested (pin ${ENA_BUILD_VERSION}) but only the ${ena_loc} module is present -- the in-guest self-build did not take effect)"
      fail=1
    fi
  else
    log_error "  [OLAWS-CHK02] [CHECK 2] ENA driver: FAIL (no ENA driver -- Nitro requires ENA for networking)"
    fail=1
  fi

  # --- CHECK 3: fstab uses UUID/LABEL (Nitro renames disks to /dev/nvme*) -----
  local fstab bad_fstab
  fstab="$(virt-cat -a "${img}" /etc/fstab 2>/dev/null | grep -vE '^[[:space:]]*#' | grep -vE '^[[:space:]]*$' || true)"
  bad_fstab="$(printf '%s\n' "${fstab}" | awk '{print $1}' | grep -E '^/dev/(sd|xvd|hd)[a-z]' | tr '\n' ' ' || true)"
  if [[ -n "${bad_fstab// /}" ]]; then
    log_error "  [OLAWS-CHK03] [CHECK 3] fstab: FAIL (kernel device-name mounts: ${bad_fstab}-- use UUID=/LABEL=)"
    fail=1
  else
    log_info "  [OLAWS-CHK03] [CHECK 3] fstab: PASS (no /dev/sd*|/dev/xvd*|/dev/hd* device-name mounts)"
  fi

  # --- CHECK 4: bootloader root= uses UUID/LABEL -----------------------------
  # Covers GRUB2 (linux/linuxefi), OL6 GRUB-legacy (grub.conf / menu.lst,
  # 'kernel'), AND BLS (OL8+): on BLS the kernel cmdline -- including root= --
  # lives in /boot/loader/entries/*.conf 'options'. On OL8 that line is commonly
  # 'options $kernelopts', a reference resolved at boot from /boot/grub2/grubenv
  # ('kernelopts='), with grub.cfg carrying a 'set kernelopts=' fallback -- so we
  # also read grubenv (then the grub.cfg fallback). "no root= anywhere" is
  # reported INDETERMINATE, not a vacuous PASS.
  local grubcfg="" g d b roots bad_root bls_entries _e bls_roots kopts kopts_root
  for g in /boot/grub2/grub.cfg /boot/grub/grub.cfg /boot/grub/grub.conf /boot/grub/menu.lst; do
    d="$(dirname "${g}")"; b="$(basename "${g}")"
    if virt-ls -a "${img}" "${d}" 2>/dev/null | grep -qx "${b}"; then grubcfg="${g}"; break; fi
  done
  roots=""
  if [[ -n "${grubcfg}" ]]; then
    roots="$(virt-cat -a "${img}" "${grubcfg}" 2>/dev/null | grep -E '^[[:space:]]*(linux|linux16|linuxefi|kernel)[[:space:]]' | grep -oE 'root=[^[:space:]]+' || true)"
  fi
  bls_entries="$(virt-ls -a "${img}" /boot/loader/entries 2>/dev/null | grep '\.conf$' || true)"
  if [[ -n "${bls_entries}" ]]; then
    while IFS= read -r _e; do
      [[ -z "${_e}" ]] && continue
      bls_roots="$(virt-cat -a "${img}" "/boot/loader/entries/${_e}" 2>/dev/null | grep -E '^[[:space:]]*options[[:space:]]' | grep -oE 'root=[^[:space:]]+' || true)"
      [[ -n "${bls_roots}" ]] && roots="$(printf '%s\n%s' "${roots}" "${bls_roots}")"
    done <<< "${bls_entries}"
  fi
  # grubenv kernelopts resolves the BLS 'options $kernelopts' indirection (OL8);
  # fall back to the grub.cfg 'set kernelopts=' default if grubenv has none.
  kopts="$(virt-cat -a "${img}" /boot/grub2/grubenv 2>/dev/null | grep -E '^kernelopts=' || true)"
  [[ -z "${kopts}" && -n "${grubcfg}" ]] && kopts="$(virt-cat -a "${img}" "${grubcfg}" 2>/dev/null | grep -E '^[[:space:]]*set kernelopts=' || true)"
  kopts_root="$(printf '%s\n' "${kopts}" | grep -oE 'root=[^[:space:]]+' || true)"
  [[ -n "${kopts_root}" ]] && roots="$(printf '%s\n%s' "${roots}" "${kopts_root}")"
  roots="$(printf '%s\n' "${roots}" | grep -E 'root=' | sort -u || true)"
  if [[ -n "${grubcfg}" || -n "${bls_entries}" || -n "${kopts}" ]]; then
    if [[ -z "${roots}" ]]; then
      log_warn "  [OLAWS-CHK04] [CHECK 4] bootloader: INDETERMINATE (no root= in grub.cfg menuentries, /boot/loader/entries/*.conf, or grubenv kernelopts)"
      indeterminate=1
    else
      bad_root="$(printf '%s\n' "${roots}" | grep -E 'root=/dev/(sd|xvd|hd)[a-z]' | tr '\n' ' ' || true)"
      if [[ -n "${bad_root// /}" ]]; then
        log_error "  [OLAWS-CHK04] [CHECK 4] bootloader: FAIL (kernel device-name root=: ${bad_root})"
        fail=1
      else
        log_info "  [OLAWS-CHK04] [CHECK 4] bootloader: PASS (root= is UUID/LABEL/LVM based)"
      fi
    fi
  else
    log_warn "  [OLAWS-CHK04] [CHECK 4] bootloader: INDETERMINATE (no grub.cfg/grub.conf/menu.lst or BLS entries found)"
    indeterminate=1
  fi

  # --- CHECK 5: serial console on the kernel cmdline (advisory) --------------
  # AWS 'Get System Log' only captures output on ttyS0. B4 sets
  # 'console=tty0 console=ttyS0,115200n8' deterministically and this check
  # verifies the result IN THE SAME BUILD. BLS-aware: on OL8+ the kernel cmdline
  # lives in /boot/loader/entries/*.conf 'options' (NOT grub.cfg) -- and that line
  # is commonly 'options $kernelopts', resolved from /boot/grub2/grubenv at boot,
  # so we inspect the menuentries (OL6 'kernel', OL7 'linux16'), the BLS entries,
  # AND grubenv 'kernelopts=' (then the grub.cfg 'set kernelopts=' fallback).
  # ADVISORY (warn only, never fails the gate): missing ttyS0 costs the console
  # log, not the boot. If this warns, B4 did not take effect.
  local serial_lines=0 bls_serial=0 kopts_serial=0 serial_src="" bls_entries _e kopts
  if [[ -n "${grubcfg}" ]]; then
    serial_lines="$(virt-cat -a "${img}" "${grubcfg}" 2>/dev/null | grep -E '^[[:space:]]*(linux|linux16|linuxefi|kernel)[[:space:]]' | grep -c 'console=ttyS0' || true)"
    [[ "${serial_lines}" -gt 0 ]] && serial_src="${grubcfg}"
  fi
  bls_entries="$(virt-ls -a "${img}" /boot/loader/entries 2>/dev/null | grep '\.conf$' || true)"
  if [[ -n "${bls_entries}" ]]; then
    while IFS= read -r _e; do
      [[ -z "${_e}" ]] && continue
      if virt-cat -a "${img}" "/boot/loader/entries/${_e}" 2>/dev/null | grep -E '^[[:space:]]*options[[:space:]]' | grep -q 'console=ttyS0'; then
        bls_serial=$((bls_serial + 1))
      fi
    done <<< "${bls_entries}"
    [[ "${bls_serial}" -gt 0 && -z "${serial_src}" ]] && serial_src="/boot/loader/entries/*.conf (BLS)"
  fi
  # grubenv kernelopts resolves the BLS 'options $kernelopts' indirection (OL8);
  # fall back to the grub.cfg 'set kernelopts=' default if grubenv has none.
  kopts="$(virt-cat -a "${img}" /boot/grub2/grubenv 2>/dev/null | grep -E '^kernelopts=' || true)"
  [[ -z "${kopts}" && -n "${grubcfg}" ]] && kopts="$(virt-cat -a "${img}" "${grubcfg}" 2>/dev/null | grep -E '^[[:space:]]*set kernelopts=' || true)"
  if printf '%s\n' "${kopts}" | grep -q 'console=ttyS0'; then
    kopts_serial=1
    [[ -z "${serial_src}" ]] && serial_src="/boot/grub2/grubenv (kernelopts)"
  fi
  if [[ "${serial_lines}" -gt 0 || "${bls_serial}" -gt 0 || "${kopts_serial}" -gt 0 ]]; then
    log_info "  [OLAWS-CHK05] [CHECK 5] serial console: PASS (console=ttyS0 on the kernel cmdline in ${serial_src})"
  elif [[ -n "${grubcfg}" || -n "${bls_entries}" || -n "${kopts}" ]]; then
    log_warn "  [OLAWS-CHK05] [CHECK 5] serial console: ADVISORY (no console=ttyS0 on the kernel cmdline in grub.cfg, /boot/loader/entries/*.conf, or grubenv kernelopts; AWS 'Get System Log' will be empty -- B4 should have set it)"
  else
    log_warn "  [OLAWS-CHK05] [CHECK 5] serial console: ADVISORY (no bootloader config located to inspect)"
  fi

  # --- CHECK 6 (GRUB Legacy majors, OL5/OL6): the BOOT PATH kernel is the ---
  # --- target ---------------------------------------------------------------
  # Record #8 (OL5): the U11 media also installs kernel-uek 400.215.10, and
  # the earlier validators verified the TARGET-named artifacts while grub's
  # default= still pointed at the media kernel. OL6 shares the same shape
  # without an active bug: anaconda installs the RHCK, the kickstart %post
  # switches the default to UEK4 via the kernel's own %post grubby, and
  # `yum install -y` returns 0 EVEN IF that grubby scriptlet fails -- so a
  # silent failure would ship an RHCK-default AMI (and the appliance-side
  # %preun on RHCK removal could leave a default entry pointing at a removed
  # kernel) with zero detection. This check resolves the DEFAULT entry of
  # /boot/grub/grub.conf and requires its vmlinuz version to equal the
  # target kver EXACTLY -- validating the boot path itself, not the intended
  # artifacts. HARD FAIL: a wrong default kernel means no nvme initrd and no
  # ena module at boot.
  if [[ "${OL_MAJOR_VERSION}" -le 6 ]]; then
    local grub_default_kver
    grub_default_kver="$(virt-cat -a "${img}" /boot/grub/grub.conf 2>/dev/null | awk '
      /^default=/ { def = substr($0, 9) + 0 }
      /^title/    { t++ }
      /^[ \t]*kernel/ { if (t - 1 == def) { v = $0; sub(/.*vmlinuz-/, "", v); sub(/ .*/, "", v); print v; exit } }
    ')"
    if [[ -n "${kver}" && "${grub_default_kver}" == "${kver}" ]]; then
      log_info "  [OLAWS-CHK06] [CHECK 6] grub default kernel: PASS (boot path = staged ${kver})"
    else
      log_error "  [OLAWS-CHK06] [CHECK 6] grub default kernel: FAIL (default boots '${grub_default_kver:-<none>}', target is '${kver:-<none>}' -- a non-target kernel kept the boot path?)"
      fail=1
    fi
  fi

  # --- Nitro instance assurance report (advisory) ----------------------------
  # ENA is required for every Nitro generation (gated by CHECK 2). What varies by
  # generation is ENAv3 support: ENAv3 is the device generation on the majority
  # of Nitro v4+ instance types (Nitro v2/v3 use ENAv1/ENAv2). Per the amzn ENA
  # driver docs (kernel/linux/ena/ENA_Linux_Best_Practices.rst):
  #   - ENA driver < 1.2.0     -> ENAv3 ENI attachment FAILS (a real failure).
  #   - 1.2.0 <= driver < 2.2.9 -> ENAv3 works but with performance DEGRADATION.
  #   - driver >= 2.2.9        -> full ENAv3 support.
  # The driver itself supports kernels >= 3.10, so ENAv1/v2 (Nitro v2/v3) work on
  # much older kernels regardless. UEK ships ENA in-tree with NO MODULE_VERSION,
  # so when the version is not exposed we fall back to the kernel version vs the
  # kernel where ENAv3 support was introduced for OL/RHEL (RHEL 8.3,
  # 4.18.0-240). That kernel check is a conservative proxy -- UEK may backport
  # ENAv3 below it, and the in-tree driver still attaches in ENAv2 mode -- so a
  # sub-proxy kernel is reported SUPPORTED (verify with 'ethtool -i'), never as a
  # failure. These generation tiers are PURELY ADVISORY and never abort the
  # build -- only the four boot-readiness checks (CHECK 1-4) feed the gate
  # verdict. In particular a driver < 1.2.0 (e.g. OL6's default ENA 1.1.2) is
  # reported as a Nitro v4+ ENAv3 attach risk but does NOT fail the build, so the
  # AMI can still be registered; refresh the ENA driver in the guest for Nitro
  # v4+ targets. Source: amzn/amzn-drivers ENA Linux driver
  # (ENA_Linux_Best_Practices.rst, RELEASENOTES.md).
  if [[ "${ena_cfg}" == "y" || -n "${ena_mod}" ]]; then
    # Example instance families per Nitro generation. This builder produces
    # x86-64 AMIs, so ARM/Graviton (e.g. *6g/*7g/*8g, C7gn) and Trainium/
    # Inferentia (Trn*/Inf*, Graviton-hosted) types are intentionally excluded --
    # an x86-64 AMI cannot launch on them.
    local fam_v2="M5 C5 R5 T3"
    local fam_v3="M5n C5n R5n I3en P4d G4dn"
    local fam_v4="M6i M7i C6i C7i R6i R7i I4i"
    local fam_v5="I7ie P5en"
    local fam_v6="M8i C8i R8i M8a C8a R8a"
    local v2_tier="ASSURED" v3_tier="ASSURED" v4_tier="ASSURED" v5_tier="ASSURED" v6_tier="ASSURED"
    local ena_ver="" signal=""

    if [[ -n "${ena_mod}" ]]; then
      # ena_mod is relative to /lib/modules/<kver> (it may live under /kernel,
      # /extra or /updates); prepend that base only -- NOT a hardcoded /kernel,
      # or the modinfo copy-out of a DKMS-installed module would silently miss.
      virt-copy-out -a "${img}" "/lib/modules/${kver}${ena_mod}" "${work}/" 2>/dev/null || true
      local enako; enako="${work}/$(basename "${ena_mod}")"
      if [[ -r "${enako}" ]]; then
        case "${enako}" in
          *.xz)  xz   -df "${enako}" 2>/dev/null || true; enako="${enako%.xz}";;
          *.gz)  gzip -df "${enako}" 2>/dev/null || true; enako="${enako%.gz}";;
          *.zst) zstd -df "${enako}" 2>/dev/null || true; enako="${enako%.zst}";;
        esac
        if command -v modinfo >/dev/null 2>&1; then
          ena_ver="$(modinfo -F version "${enako}" 2>/dev/null | head -1 || true)"
        fi
      fi
    fi

    if [[ -n "${ena_ver}" ]]; then
      local vnum; vnum="$(printf '%s' "${ena_ver}" | grep -oE '^[0-9]+(\.[0-9]+){1,2}' || true)"
      signal="ENA driver ${ena_ver} (modinfo, ${ena_loc}); ENAv3 thresholds per amzn-drivers"
      if [[ -z "${vnum}" ]]; then
        signal="ENA driver '${ena_ver}' (unparseable; verify with ethtool -i)"
      elif [[ "$(printf '1.2.0\n%s\n' "${vnum}" | sort -V | head -1)" != "1.2.0" ]]; then
        # driver < 1.2.0: ENAv3 ENI attach fails on Nitro v4+ (ENAv1/v2 on Nitro
        # v2/v3 still attach). ADVISORY ONLY -- this does NOT abort the build, so
        # images with an old default driver (e.g. OL6's ENA 1.1.2) still reach
        # AMI registration. Refresh the ENA driver in the guest for v4+ targets.
        v4_tier="NOT-ASSURED (driver <1.2.0: ENAv3 ENI attach fails; refresh driver)"; v5_tier="${v4_tier}"; v6_tier="${v4_tier}"
        log_warn "  ENA driver ${ena_ver} < 1.2.0: ENAv3 ENI attach fails on Nitro v4+ (advisory, not aborting). Nitro v2/v3 unaffected; refresh the ENA driver for v4+ targets."
      elif [[ "$(printf '2.2.9\n%s\n' "${vnum}" | sort -V | head -1)" != "2.2.9" ]]; then
        # 1.2.0 <= driver < 2.2.9: ENAv3 performance DEGRADATION (not a failure).
        v4_tier="DEGRADED (driver <2.2.9: ENAv3 perf degradation)"; v5_tier="${v4_tier}"; v6_tier="${v4_tier}"
        log_warn "  ENA driver ${ena_ver} < 2.2.9: ENAv3 devices (Nitro v4+) run with reduced performance (not a failure)."
      fi
    else
      # In-tree ENA (no MODULE_VERSION): proxy on the kernel where ENAv3 support
      # was introduced for OL/RHEL (RHEL 8.3, 4.18.0-240); driver supports >=3.10.
      signal="kernel ${kver}; ENAv3 introduced ~RHEL8.3/4.18.0-240 (ENA in-tree, no module version; driver supports kernels >=3.10)"
      local mm="${kver%%-*}"
      if [[ -z "${mm}" || "$(printf '4.18\n%s\n' "${mm}" | sort -V | head -1)" != "4.18" ]]; then
        v4_tier="SUPPORTED (kernel < ENAv3 proxy 4.18; ENAv2 mode, UEK may backport -- verify ethtool -i)"
        v5_tier="${v4_tier}"; v6_tier="${v4_tier}"
      fi
    fi

    case "${ena_loc}" in
      self-built*) log_info "  ENA driver provenance: ${ena_loc} -- the in-guest self-build replaced the stock in-tree driver; CHECK 1-4 above confirm boot-readiness is preserved (no regression)." ;;
      ?*)          log_info "  ENA driver provenance: ${ena_loc}." ;;
    esac
    # Explicit before/after view: report the stock in-box ENA version and the
    # self-built (DKMS) version on SEPARATE lines, so the operator can confirm
    # the added in-guest self-build actually ran -- successful provisioning is
    # otherwise silent in the build log (libguestfs echoes a guest script only on
    # failure). OS-independent: applies to OL6 and OL7+ alike. ena_all (CHECK 2)
    # already holds every ena.ko path relative to /lib/modules/<kver>.
    local ena_inbox_mod ena_self_mod inbox_ver self_ver self_loc
    ena_inbox_mod="$(printf '%s\n' "${ena_all}" | grep -E '(^|/)kernel/' | head -1 || true)"
    ena_self_mod="$(printf '%s\n' "${ena_all}" | grep -E '(^|/)(updates|extra)/' | head -1 || true)"
    inbox_ver="$(_ena_module_version "${img}" "${kver}" "${work}" "${ena_inbox_mod}")"
    self_ver="$(_ena_module_version "${img}" "${kver}" "${work}" "${ena_self_mod}")"
    local self_bk="DKMS"
    [[ "${OL_MAJOR_VERSION}" -eq 5 ]] && self_bk="plain-make"
    self_loc="${self_bk}"
    case "${ena_self_mod}" in
      */updates/*) self_loc="${self_bk} /updates" ;;
      */extra/*)   self_loc="${self_bk} /extra" ;;
    esac
    local inbox_disp self_disp
    if [[ "${ena_cfg}" == "y" ]]; then
      inbox_disp="built into the kernel (=y; no separate module)"
    elif [[ -n "${inbox_ver}" ]]; then
      inbox_disp="${inbox_ver} (stock in-tree /kernel)"
    elif [[ -n "${ena_inbox_mod}" ]]; then
      inbox_disp="in-tree, no version field (kernel-bundled) (stock in-tree /kernel)"
    else
      inbox_disp="none found"
    fi
    if [[ -n "${ena_self_mod}" ]]; then
      self_disp="${self_ver:-unknown} (${self_loc}; in-guest self-build active)"
    else
      self_disp="not present (--skip-ena-driver / pure OL AMI)"
    fi
    # Aligned, fixed-width labels so the operator can eyeball the in-box vs
    # self-built ENA version delta at a glance (feedback: header alignment). The
    # in-box line falls back to an explicit in-tree note when the kernel module
    # carries no modinfo version field (true for OL7/OL8 in-tree ENA).
    log_info "  ENA Driver (Kernel in-box) - ${inbox_disp}"
    log_info "  ENA Driver (Self-Build)    - ${self_disp}"
    log_info "  --- Nitro instance assurance (advisory) ---"
    log_info "    signal : ${signal}"
    log_info "    Nitro v2  ${v2_tier}  e.g. ${fam_v2}"
    log_info "    Nitro v3  ${v3_tier}  e.g. ${fam_v3}"
    log_info "    Nitro v4  ${v4_tier}  e.g. ${fam_v4}"
    log_info "    Nitro v5  ${v5_tier}  e.g. ${fam_v5}"
    log_info "    Nitro v6  ${v6_tier}  e.g. ${fam_v6}"
    log_info "    note: advisory tiers; confirm on the target instance with 'ethtool -i eth0'."
  fi

  rm -rf "${work}"

  # --- verdict ---------------------------------------------------------------
  if [[ "${fail}" -gt 0 ]]; then
    if [[ "${mode}" == "enforce" ]]; then
      die "Nitro readiness pre-check FAILED (see the [CHECK 1-4] boot-readiness lines above; the Nitro assurance report is advisory and does not fail the build). Aborting before the upload/snapshot/register phases. Re-run with NITRO_PRECHECK=warn to proceed anyway, or =off to skip the check."
    fi
    log_warn "Nitro readiness pre-check found blocking issue(s) (NITRO_PRECHECK=warn; continuing despite the failure(s) above)."
  elif [[ "${indeterminate}" -gt 0 ]]; then
    log_warn "Nitro readiness pre-check: no failures, but some checks were INDETERMINATE (see above). Verify manually if in doubt."
  else
    log_info "Nitro readiness pre-check PASSED (NVMe host, ENA, fstab, bootloader all Nitro-ready)."
  fi
}

# Phase 7: Upload the VMDK to S3
phase7_upload_to_s3() {
  log_step "Phase 7: Uploading VMDK to S3"

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
# Phase 8: Convert the VMDK to an EBS snapshot via import-snapshot
#------------------------------------------------------------------------------
phase8_import_snapshot() {
  log_step "Phase 8: Creating EBS snapshot via import-snapshot"

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
# Phase 9: Register the snapshot as an AMI
#------------------------------------------------------------------------------
phase9_register_ami() {
  log_step "Phase 9: Registering AMI via register-image"

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
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={SnapshotId=${SNAPSHOT_ID},VolumeSize=${DISK_SIZE_GB},VolumeType=gp3,DeleteOnTermination=true}"
  )

  # IMDS support (F1): the default OMITS --imds-support so instances allow both
  # IMDSv1 and IMDSv2 (HttpTokens=optional) -- the compatible default and the
  # only one that works for OL6's cloud-init 0.7.5. 'v2.0' bakes in
  # IMDSv2-required (OL7+; OL6+v2.0 is rejected during env validation).
  if [[ "${IMDS_SUPPORT}" == "v2.0" ]]; then
    register_args+=(--imds-support v2.0)
    log_info "[OLAWS-IMD01] AMI IMDS support: v2.0 (instances default to IMDSv2-required)"
  else
    log_info "[OLAWS-IMD01] AMI IMDS support: default (IMDSv1+v2 allowed; HttpTokens=optional)"
  fi

  # NitroTPM is only valid for UEFI-bootable AMIs
  if [[ "${BOOT_MODE,,}" == "uefi" || "${BOOT_MODE,,}" == "uefi-preferred" ]]; then
    register_args+=(--tpm-support v2.0)
    log_info "Boot mode supports UEFI; enabling NitroTPM (--tpm-support v2.0)"
  else
    log_info "Boot mode is legacy-bios; NitroTPM (--tpm-support) is omitted (UEFI-only feature)"
  fi

  local ami_id
  # Pre-flight: a register-image --dry-run checks IAM permissions and the
  # parameter set WITHOUT creating an AMI. Per the AWS API, a dry run that WOULD
  # succeed returns the error "DryRunOperation" (and a non-zero exit); anything
  # else -- "UnauthorizedOperation", a parameter/validation error, etc. -- means
  # the real call would fail. Gate the real registration on seeing
  # "DryRunOperation", so a doomed registration is caught before it runs.
  log_info "register-image --dry-run pre-flight (validates permissions/parameters; no AMI is created)"
  local dry_out
  dry_out="$(aws ec2 register-image "${register_args[@]}" --dry-run 2>&1)" || true
  if printf '%s' "${dry_out}" | grep -q 'DryRunOperation'; then
    log_info "  dry-run OK (DryRunOperation): proceeding with the real registration"
  else
    log_error "register-image --dry-run did not return DryRunOperation; the real call would fail:"
    log_error "  ${dry_out}"
    die "register-image dry-run pre-flight failed; aborting before the real registration"
  fi

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
  local ena_summary
  # Mirror the AMI-description gate: the self-build hook is injected for
  # OL6-OL10 whenever ENA_DRIVER_BUILD=1 (--skip-ena-driver produces pure OL).
  if [[ "${ENA_DRIVER_BUILD}" -eq 1 ]]; then
    local ena_sum_bk="DKMS"
    [[ "${OL_MAJOR_VERSION}" -eq 5 ]] && ena_sum_bk="plain make"
    ena_summary="self-built ${ENA_BUILD_VERSION:-driver} (${ena_sum_bk}, AWS-optimized)"
  else
    ena_summary="stock in-box (pure OL AMI)"
  fi
  log_info "  AMI ID:          ${ami_id}"
  log_info "  AMI Name:        ${AMI_NAME}"
  log_info "  AMI Description: ${AMI_DESCRIPTION}"
  log_info "  Region:          ${AWS_REGION}"
  log_info "  Snapshot ID:     ${SNAPSHOT_ID}"
  log_info "  Boot Mode:       ${BOOT_MODE}"
  log_info "  ENA driver:      ${ena_summary}"
  log_info "  ENA Support:     enabled"
  local ssm_summary
  if [[ "${SSM_AGENT_INSTALL}" -eq 1 ]]; then
    if [[ -n "${SSM_AGENT_RESOLVED}" && "${SSM_AGENT_RESOLVED}" != "latest" ]]; then
      ssm_summary="${SSM_AGENT_RESOLVED} (installed + enabled for boot)"
    else
      ssm_summary="installed + enabled for boot (/latest/ alias; concrete version unresolved at build time)"
    fi
  else
    ssm_summary="not installed (--skip-ssm-agent)"
  fi
  log_info "  SSM Agent:       ${ssm_summary}"
  local awscli_summary
  if [[ "${AWSCLI_INSTALL}" -ne 1 ]]; then
    awscli_summary="not installed (--skip-awscli)"
  elif [[ "${OL_MAJOR_VERSION}" != "5" && "${OL_MAJOR_VERSION}" != "6" && "${OL_MAJOR_VERSION}" != "7" && "${OL_MAJOR_VERSION}" != "8" ]]; then
    awscli_summary="not installed (out of scope; OL${OL_MAJOR_VERSION} uses the default package manager)"
  elif [[ -n "${AWSCLI_RESOLVED}" ]]; then
    awscli_summary="v2 ${AWSCLI_RESOLVED} (installed)"
  else
    awscli_summary="v2 installed (version unresolved -- host offline)"
  fi
  log_info "  AWS CLI:         ${awscli_summary}"
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
  phase6_nitro_readiness_check

  if [[ ${BUILD_ONLY} -eq 1 || ${SKIP_AWS_IMPORT} -eq 1 ]]; then
    log_info "Build-only mode. Skipping AWS import phases."
    log_info "VMDK file: ${VMDK_PATH}"
    exit 0
  fi

  phase7_upload_to_s3
  phase8_import_snapshot
  phase9_register_ami
}

# Run the pipeline only when executed directly. When the script is sourced
# (e.g. by the B-T3 unit tests in tests/t003_unit.sh) this guard keeps main from
# running, so individual functions can be exercised without side effects.
# Behaviour when executed directly is unchanged.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
