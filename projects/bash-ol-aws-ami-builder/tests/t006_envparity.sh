#!/usr/bin/env bash
#==============================================================================
# tests/t006_envparity.sh - B-T5 env-template parity (test pyramid layer L2)
#
# Static/data-driven checks over env.properties.aws-olN. The five templates
# share a common-core key set; only OL6/OL7 carry the documented extra UEK keys
# (KERNEL, UEK_RELEASE). Cross-file invariants (S3_BUCKET, AWS_REGION,
# UPDATE_TO_LATEST, CLOUD) must agree, while DISTR is per-OS (olN-slim).
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"

ENVS=(ol6 ol7 ol8 ol9 ol10)

keys_of() { grep -oE '^[A-Z_][A-Z0-9_]*=' "$1" | sed 's/=$//' | sort -u; }
val_of()  { grep -E "^$2=" "$1" | head -1 | cut -d= -f2-; }

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

for n in "${ENVS[@]}"; do
  keys_of "${PROJ}/env.properties.aws-${n}" > "${tmp}/${n}.keys"
done

# common core = keys present in every template (seed from ol8, then intersect)
cp "${tmp}/ol8.keys" "${tmp}/core"
for n in "${ENVS[@]}"; do
  comm -12 "${tmp}/core" "${tmp}/${n}.keys" > "${tmp}/core.next"
  mv "${tmp}/core.next" "${tmp}/core"
done
core_count="$(wc -l < "${tmp}/core" | tr -d ' ')"
assert_eq 21 "${core_count}" "env parity: 21 common-core keys across all templates (AMAZON_TIME_SYNC added)"

# extras beyond core: allowed only as {KERNEL, UEK_RELEASE} (OL6/OL7) and
# {LINUX_FIRMWARE} (OL8 -- the uncompressed EL8 firmware overflows the 7 GB
# root during UPDATE_TO_LATEST; SPEC B.3.4)
for n in "${ENVS[@]}"; do
  extras="$(comm -23 "${tmp}/${n}.keys" "${tmp}/core" | tr '\n' ' ' | sed 's/ *$//')"
  case "${n}" in
    ol6|ol7) assert_eq "KERNEL UEK_RELEASE" "${extras}" "env parity: ${n} extras are exactly KERNEL UEK_RELEASE" ;;
    ol8)     assert_eq "LINUX_FIRMWARE" "${extras}" "env parity: ol8 extras are exactly LINUX_FIRMWARE (firmware dropped; SPEC B.3.4)" ;;
    *)       assert_eq "" "${extras}" "env parity: ${n} has no orphan keys beyond the core" ;;
  esac
done
assert_eq '"no"' "$(val_of "${PROJ}/env.properties.aws-ol8" LINUX_FIRMWARE)" \
  "env parity: ol8 LINUX_FIRMWARE=no (EL8 uncompressed firmware vs 7 GB root; SPEC B.3.4)"

# cross-file invariants + per-OS DISTR
ref_bucket="$(val_of "${PROJ}/env.properties.aws-ol8" S3_BUCKET)"
for n in "${ENVS[@]}"; do
  f="${PROJ}/env.properties.aws-${n}"
  assert_eq "${ref_bucket}" "$(val_of "${f}" S3_BUCKET)" "env parity: ${n} S3_BUCKET matches the shared bucket"
  assert_eq '""'    "$(val_of "${f}" AWS_REGION)"       "env parity: ${n} AWS_REGION empty (runtime-resolved)"
  assert_eq '"yes"' "$(val_of "${f}" UPDATE_TO_LATEST)" "env parity: ${n} UPDATE_TO_LATEST=yes"
  assert_eq '"7"'   "$(val_of "${f}" DISK_SIZE_GB)"     "env parity: ${n} DISK_SIZE_GB=7 (uniform; SPEC B.3 Disk sizing)"
  assert_eq '"no"'  "$(val_of "${f}" AMAZON_TIME_SYNC)" "env parity: ${n} AMAZON_TIME_SYNC=no (opt-in feature, default OFF)"
  assert_eq '"aws"' "$(val_of "${f}" CLOUD)"            "env parity: ${n} CLOUD=aws"
  assert_eq "\"${n}-slim\"" "$(val_of "${f}" DISTR)"    "env parity: ${n} DISTR=${n}-slim (per-OS)"
done

# --- release-agnostic maintenance invariants ---------------------------------
# ISO_URL is a required env key (no wrapper-side default), so every template
# must set it non-empty; the living majors (OL9/OL10, which still receive
# update releases) must carry the SINGLE-TOUCH MAINTENANCE POINT marker and
# must not carry release-pinned "Verified-good SHA256" comments; the wrapper
# must not regrow a hard-coded DEFAULT_ISO_URL fallback.
for n in "${ENVS[@]}"; do
  iso="$(val_of "${PROJ}/env.properties.aws-${n}" ISO_URL)"
  assert_match "${iso}" '^"https://.+\.iso"$' "env parity: ${n} ISO_URL set (required key, no wrapper default)"
done
for n in ol9 ol10; do
  f="${PROJ}/env.properties.aws-${n}"
  if grep -Fq '>>> SINGLE-TOUCH MAINTENANCE POINT <<<' "${f}"; then
    t_pass "release-agnostic: ${n} carries the single-touch ISO_URL marker"
  else
    t_fail "release-agnostic: ${n} carries the single-touch ISO_URL marker"
  fi
  if grep -Fq 'Verified-good SHA256' "${f}"; then
    t_fail "release-agnostic: ${n} has no release-pinned checksum comment"
  else
    t_pass "release-agnostic: ${n} has no release-pinned checksum comment"
  fi
done
if grep -Fq 'DEFAULT_ISO_URL' "${PROJ}/build-ol-aws-ami.sh"; then
  t_fail "release-agnostic: wrapper carries no DEFAULT_ISO_URL fallback"
else
  t_pass "release-agnostic: wrapper carries no DEFAULT_ISO_URL fallback"
fi
if grep -Fq 'ISO_URL is not defined' "${PROJ}/build-ol-aws-ami.sh"; then
  t_pass "release-agnostic: load_env rejects an unset ISO_URL explicitly"
else
  t_fail "release-agnostic: load_env rejects an unset ISO_URL explicitly"
fi

# --- sos-in-every-kickstart invariants ----------------------------------------
# OL6: the wrapper-synthesized kickstart heredoc must list sos directly.
# OL7-10: covered at build time by _ks_add_sos_package (unit-tested in t003);
# here we pin the wrapper-side wiring so neither half can silently regress.
# NOTE: single awk process on purpose. An `awk ... | grep -q` pipe here is the
# documented SIGPIPE/pipefail race (see tests/lib/assert.sh, assert_match):
# grep -q exits at the first match while awk is still writing the large
# haystack, awk takes SIGPIPE (141), and pipefail misreads a genuine match as
# failure. awk matching + `exit !found` has no downstream reader at all.
if awk '/EOF_OL6_KS/,/^EOF_OL6_KS$/ { if ($0 == "sos") found = 1 } END { exit !found }' "${PROJ}/build-ol-aws-ami.sh"; then
  t_pass "sos baked in: OL6 synthesized kickstart %packages lists sos"
else
  t_fail "sos baked in: OL6 synthesized kickstart %packages lists sos"
fi
# The single-quoted '${distr_ks}' is deliberate: we are literally matching the
# wrapper's own source text, not expanding a variable here.
# shellcheck disable=SC2016
if grep -Fq '_ks_add_sos_package "${distr_ks}"' "${PROJ}/build-ol-aws-ami.sh"; then
  t_pass "sos baked in: phase3 wires _ks_add_sos_package for the upstream (OL7-10) kickstarts"
else
  t_fail "sos baked in: phase3 wires _ks_add_sos_package for the upstream (OL7-10) kickstarts"
fi

t_done
