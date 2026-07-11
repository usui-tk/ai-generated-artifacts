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
assert_eq 20 "${core_count}" "env parity: 20 common-core keys across all templates"

# extras beyond core: allowed only as {KERNEL, UEK_RELEASE} and only for OL6/OL7
for n in "${ENVS[@]}"; do
  extras="$(comm -23 "${tmp}/${n}.keys" "${tmp}/core" | tr '\n' ' ' | sed 's/ *$//')"
  case "${n}" in
    ol6|ol7) assert_eq "KERNEL UEK_RELEASE" "${extras}" "env parity: ${n} extras are exactly KERNEL UEK_RELEASE" ;;
    *)       assert_eq "" "${extras}" "env parity: ${n} has no orphan keys beyond the core" ;;
  esac
done

# cross-file invariants + per-OS DISTR
ref_bucket="$(val_of "${PROJ}/env.properties.aws-ol8" S3_BUCKET)"
for n in "${ENVS[@]}"; do
  f="${PROJ}/env.properties.aws-${n}"
  assert_eq "${ref_bucket}" "$(val_of "${f}" S3_BUCKET)" "env parity: ${n} S3_BUCKET matches the shared bucket"
  assert_eq '""'    "$(val_of "${f}" AWS_REGION)"       "env parity: ${n} AWS_REGION empty (runtime-resolved)"
  assert_eq '"yes"' "$(val_of "${f}" UPDATE_TO_LATEST)" "env parity: ${n} UPDATE_TO_LATEST=yes"
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

t_done
