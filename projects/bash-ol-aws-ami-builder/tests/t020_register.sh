#!/usr/bin/env bash
#==============================================================================
# tests/t020_register.sh - AMI register-image input validation (test pyramid L1)
#
# Source the wrapper (its tail `main` is guarded by
# `[[ "${BASH_SOURCE[0]}" == "${0}" ]]`, so sourcing has no side effects) and
# exercise the two pure validators that guard the AWS EC2 register-image call:
#   validate_ami_name        --name  : length 3-128 + allowed character set
#                                       (alphanumerics and ()[] space . / - ' @ _)
#   validate_ami_description --description : length 0-255 (any character)
# Both are argument-only (Axis 2: no external commands beyond grep, no fs, no
# network), so these checks are hermetic and deterministic on any host. The
# Phase-9 `--dry-run` pre-flight that also gates the real registration is a live
# AWS interaction and is proved by B-T8 (E2E), not here.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
MAIN="${PROJ}/build-ol-aws-ami.sh"

# rc of validate_ami_name "$1" with the wrapper sourced in an isolated subshell.
name_rc() {
  (
    # shellcheck source=/dev/null
    . "${MAIN}" >/dev/null 2>&1
    if validate_ami_name "$1" 2>/dev/null; then echo 0; else echo $?; fi
  )
}
# rc of validate_ami_description "$1", same isolation.
desc_rc() {
  (
    # shellcheck source=/dev/null
    . "${MAIN}" >/dev/null 2>&1
    if validate_ami_description "$1" 2>/dev/null; then echo 0; else echo $?; fi
  )
}

# --- validate_ami_name : length boundaries (3..128) --------------------------
assert_eq 1 "$(name_rc "ab")"                            "name length 2 -> reject"
assert_eq 0 "$(name_rc "abc")"                           "name length 3 (min) -> accept"
assert_eq 0 "$(name_rc "$(printf 'a%.0s' {1..128})")"    "name length 128 (max) -> accept"
assert_eq 1 "$(name_rc "$(printf 'a%.0s' {1..129})")"    "name length 129 -> reject"
assert_eq 1 "$(name_rc "")"                              "name empty (length 0) -> reject"

# --- validate_ami_name : realistic auto-generated names accept ---------------
assert_eq 0 "$(name_rc "OracleLinux-9-U8-x86_64-20260718-0243-ena2.17.2-ssm3.3.4793.0")" \
  "auto name (ENA + SSM resolved-latest, the 2026-07-18 E2E shape) -> accept"
assert_eq 0 "$(name_rc "OracleLinux-6-U10-x86_64-20260617-1200-ena2.13.0-ssm3.3.1802.0")" \
  "auto name (ENA + SSM pinned) -> accept"

# --- validate_ami_name : the full allowed special set accepts ----------------
# alphanumerics plus ( ) [ ] space . / - ' @ _
assert_eq 0 "$(name_rc "Img (one) [two] a.b/c-d_e@f 'q'")" \
  "all allowed specials -> accept"

# --- validate_ami_name : disallowed characters reject ------------------------
while IFS='|' read -r nm label; do
  [ -z "${label}" ] && continue
  assert_eq 1 "$(name_rc "${nm}")" "reject disallowed char: ${label}"
done <<'TABLE'
bad#name|hash
bad*name|asterisk
bad,name|comma
bad:name|colon
bad+name|plus
bad=name|equals
bad%name|percent
bad!name|bang
bad{name}|braces
TABLE
assert_eq 1 "$(name_rc "bad$(printf '\t')name")" "reject disallowed char: tab (only space is allowed)"
assert_eq 1 "$(name_rc "$(printf 'cafe-\xc3\xa9-ami')")" "reject multibyte (outside ASCII allowed set)"

# --- validate_ami_description : length (0..255) ------------------------------
assert_eq 0 "$(desc_rc "")"                            "description length 0 (min) -> accept"
assert_eq 0 "$(desc_rc "$(printf 'd%.0s' {1..255})")" "description length 255 (max) -> accept"
assert_eq 1 "$(desc_rc "$(printf 'd%.0s' {1..256})")" "description length 256 -> reject"
assert_eq 0 "$(desc_rc "Oracle Linux 9 (x86_64) custom AMI built via oracle-linux-image-tools")" \
  "description realistic -> accept"

# --- AMI-identity concreteness invariant (never the word "latest") -----------
# The auto-generated AMI name/description must always carry concrete versions;
# a marker whose version cannot be resolved is OMITTED, never printed as
# "latest". Regression pins for the 2026-07-18 degradation (OL9/OL10 E2E
# registered '-ssmlatest' AMI names when the then-GitHub-first SSM resolution
# failed while the tag led S3 publication).
main_src="$(cat "${PROJ}/build-ol-aws-ami.sh")"
if grep -Eq '_ssm_name_sfx="-ssmlatest"' "${PROJ}/build-ol-aws-ami.sh"; then
  t_fail "identity invariant: the '-ssmlatest' name-suffix branch must never regrow"
else
  t_pass "identity invariant: the '-ssmlatest' name-suffix branch must never regrow"
fi
assert_match "${main_src}" 'SSM_AGENT_INSTALL.*-n "\$\{SSM_AGENT_RESOLVED\}"' \
  "identity invariant: the ssm marker is gated on a non-empty resolved version"
assert_match "${main_src}" 'SSMAgent/latest/VERSION|\$\{base\}/latest/VERSION' \
  "identity invariant: _ssm_resolve_latest reads the S3 latest/VERSION channel (layer 1)"
assert_match "${main_src}" 'SSM_AGENT_RESOLVED=""' \
  "identity invariant: resolution failure empties SSM_AGENT_RESOLVED (awscli parity), never stores 'latest'"

t_done
