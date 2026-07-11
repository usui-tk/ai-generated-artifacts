#!/usr/bin/env bash
#==============================================================================
# tests/t003_unit.sh - B-T3 pure-function unit (test pyramid layer L1, hermetic)
#
# Source the wrapper (its tail `main` is guarded, so sourcing has no side
# effects) and exercise pure functions in isolated subshells. Dependency classes
# touched (Axis 2): arguments only - no external commands, filesystem, or
# network - so these are hermetic and deterministic on any host.
#
# Covered: parse_ol_version_from_iso (table-driven, Axis 3) and the parse_args
# contract (exit codes + error messages). The load_env IMDS `v2.0` OL6 rejection
# is planned for a later increment (it lives inside the large load_env; testing
# it needs either a small behaviour-neutral extraction or a fixture-driven run).
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
MAIN="${PROJ}/build-ol-aws-ami.sh"

# --- parse_ol_version_from_iso : table-driven (Axis 3 data variation) ---------
# row: iso_ref | expect_rc | expect_major | expect_update
while IFS='|' read -r iso erc emaj eupd; do
  [ -z "${iso}" ] && continue
  result="$(
    # shellcheck source=/dev/null
    . "${MAIN}" >/dev/null 2>&1
    if parse_ol_version_from_iso "${iso}"; then rc=0; else rc=$?; fi
    printf '%s|%s|%s' "${rc}" "${OL_MAJOR_VERSION:-}" "${OL_UPDATE_VERSION:-}"
  )"
  arc="${result%%|*}"; tmp="${result#*|}"; amaj="${tmp%%|*}"; aupd="${tmp##*|}"
  assert_eq "${erc}" "${arc}" "parse_ol_version_from_iso rc :: ${iso}"
  if [ "${erc}" = "0" ]; then
    assert_eq "${emaj}" "${amaj}" "  -> major :: ${iso}"
    assert_eq "${eupd}" "${aupd}" "  -> update :: ${iso}"
  fi
done <<'TABLE'
OracleLinux-R10-U2-x86_64-dvd.iso|0|10|2
OracleLinux-R9-U6-x86_64-dvd.iso|0|9|6
OracleLinux-R8-U10-x86_64-dvd.iso|0|8|10
OracleLinux-R7-U9-Server-x86_64-dvd.iso|0|7|9
OracleLinux-R6-U10-x86_64-dvd.iso|0|6|10
https://example.com/path/OracleLinux-R9-U6-x86_64-dvd.iso|0|9|6
not-an-ol-image.iso|1||
TABLE

# --- parse_args : contract (exit codes + messages; Axis 2 arguments) ----------

# unknown flag -> usage(1)
err="$(
  (
    # shellcheck source=/dev/null
    . "${MAIN}" >/dev/null 2>&1
    parse_args --bogus-flag
  ) 2>&1 >/dev/null
)"; rc=$?
assert_eq 1 "${rc}" "parse_args: unknown flag exits 1"
assert_match "${err}" "Unknown option" "parse_args: unknown flag logs an error"

# missing --env -> die
err="$(
  (
    # shellcheck source=/dev/null
    . "${MAIN}" >/dev/null 2>&1
    parse_args
  ) 2>&1 >/dev/null
)"; rc=$?
assert_eq 1 "${rc}" "parse_args: missing --env exits 1"
assert_match "${err}" "env option is required" "parse_args: missing --env message"

# valid --env (existing file) -> rc 0, ENV_FILE set
fix="$(mktemp)"; printf '# fixture env\n' > "${fix}"
out="$(
  (
    # shellcheck source=/dev/null
    . "${MAIN}" >/dev/null 2>&1
    if parse_args --env "${fix}"; then printf 'ENV_FILE=%s' "${ENV_FILE:-}"; else exit "$?"; fi
  ) 2>/dev/null
)"; rc=$?
rm -f "${fix}"
assert_eq 0 "${rc}" "parse_args: valid --env returns 0"
assert_match "${out}" "ENV_FILE=/" "parse_args: sets ENV_FILE"

# --- normalize_imds_support : normalisation + OL6 rejection (Axis 2/3) ---------
# row: input_IMDS | ol_major | expect (value on success, or DIE:<needle>)
while IFS='|' read -r imds ol expect; do
  [ -z "${imds}${ol}${expect}" ] && continue
  case "${expect}" in
    DIE:*)
      needle="${expect#DIE:}"
      err="$(
        (
          # shellcheck source=/dev/null
          . "${MAIN}" >/dev/null 2>&1
          IMDS_SUPPORT="${imds}" OL_MAJOR_VERSION="${ol}" normalize_imds_support
        ) 2>&1 >/dev/null
      )"; rc=$?
      assert_eq 1 "${rc}" "normalize_imds_support: '${imds}' (OL${ol}) exits 1"
      assert_match "${err}" "${needle}" "normalize_imds_support: '${imds}' (OL${ol}) message"
      ;;
    *)
      val="$(
        (
          # shellcheck source=/dev/null
          . "${MAIN}" >/dev/null 2>&1
          IMDS_SUPPORT="${imds}"
          OL_MAJOR_VERSION="${ol}" normalize_imds_support
          printf '%s' "${IMDS_SUPPORT}"
        ) 2>/dev/null
      )"
      assert_eq "${expect}" "${val}" "normalize_imds_support: '${imds}' (OL${ol}) -> ${expect}"
      ;;
  esac
done <<'TABLE'
|9|default
v1+v2|9|default
V2.0|7|v2.0
v2only|7|v2.0
default|6|default
v2.0|7|v2.0
bogus|9|DIE:Invalid IMDS_SUPPORT
v2.0|6|DIE:not supported for OL6
TABLE

# --- parse_args : --enable-amazon-time-sync (opt-in flag, Axis 2) -------------
fix="$(mktemp)"; printf '# fixture env\n' > "${fix}"
out="$(
  (
    # shellcheck source=/dev/null
    . "${MAIN}" >/dev/null 2>&1
    if parse_args --env "${fix}" --enable-amazon-time-sync; then
      printf 'CLI=%s' "${AMAZON_TIME_SYNC_CLI:-unset}"
    else exit "$?"; fi
  ) 2>/dev/null
)"; rc=$?
rm -f "${fix}"
assert_eq 0 "${rc}" "parse_args: --enable-amazon-time-sync accepted (rc 0)"
assert_eq "CLI=1" "${out}" "parse_args: --enable-amazon-time-sync sets AMAZON_TIME_SYNC_CLI=1"

# --- _ks_add_sos_package : insertion / idempotency / assert-then-write --------
# Pure function over a file path; exercised on synthetic kickstarts shaped like
# the real upstream distr files (both '%packages' and '%packages --nobase').
kstmp="$(mktemp -d)"
printf 'install\n%%packages --nobase\nyum\n%%end\n' > "${kstmp}/ks.cfg"
(
  # shellcheck source=/dev/null
  . "${MAIN}" >/dev/null 2>&1
  _ks_add_sos_package "${kstmp}/ks.cfg" >/dev/null 2>&1
  _ks_add_sos_package "${kstmp}/ks.cfg" >/dev/null 2>&1   # second call: idempotent
) </dev/null
assert_eq 1 "$(grep -c '^sos$' "${kstmp}/ks.cfg")" "_ks_add_sos_package: exactly one sos line after two calls (idempotent)"
assert_eq 1 "$(grep -c 'ol-aws-ami-builder PATCH sos-package' "${kstmp}/ks.cfg")" "_ks_add_sos_package: wrapper marker present exactly once"
assert_eq "sos" "$(grep -A2 '^%packages' "${kstmp}/ks.cfg" | sed -n '3p')" "_ks_add_sos_package: sos inserted directly under %packages"

printf 'install\nreboot\n' > "${kstmp}/bad.cfg"
err="$(
  (
    # shellcheck source=/dev/null
    . "${MAIN}" >/dev/null 2>&1
    _ks_add_sos_package "${kstmp}/bad.cfg"
  ) 2>&1 >/dev/null
)"; rc=$?
assert_eq 1 "${rc}" "_ks_add_sos_package: missing %packages section dies (rc 1)"
assert_match "${err}" "no %packages section" "_ks_add_sos_package: die message names the missing section"
assert_eq 0 "$(grep -c 'sos' "${kstmp}/bad.cfg")" "_ks_add_sos_package: assert-then-write leaves the file untouched on die"
rm -rf "${kstmp}"

# --- _ena_pin_for_major / _ena_fallback_pin : shape-guarded extraction ---------
# BUG HISTORY (2026-07-11, first real OL8-10 build): the original sed used
# '[^}"]+' which does not match the empty default of the latest-resolving
# majors' pins (NAME="${NAME:-}"), so the WHOLE assignment line passed through
# and leaked into the AMI name. The extractors are now shape-guarded: only a
# concrete x.y.z is ever emitted; empty defaults and unrecognized pin forms
# both yield "".
#
# (a) Fixture-driven: SCRIPT_DIR is readonly and derived from BASH_SOURCE, so
# the fixture installer is planted next to a SYMLINK of the wrapper and the
# symlink is sourced (SCRIPT_DIR then resolves to the fixture dir).
pintmp="$(mktemp -d)"
ln -s "${MAIN}" "${pintmp}/build-ol-aws-ami.sh"
cat > "${pintmp}/install-ena-driver.sh" <<'PIN_FIXTURE'
ENA_VERSION_OL6="${ENA_VERSION_OL6:-1.2.3}"
ENA_VERSION_OL8="${ENA_VERSION_OL8:-}"
ENA_VERSION_OL9="9.9.9"
ENA_VERSION_OL10=not-a-pin-form
ENA_LATEST_FALLBACK_PIN="${ENA_LATEST_FALLBACK_PIN:-}"
PIN_FIXTURE
out="$(
  (
    # shellcheck source=/dev/null
    . "${pintmp}/build-ol-aws-ami.sh" >/dev/null 2>&1
    printf '6=[%s] 8=[%s] 9=[%s] 10=[%s] fb=[%s]' \
      "$(_ena_pin_for_major 6)" "$(_ena_pin_for_major 8)" \
      "$(_ena_pin_for_major 9)" "$(_ena_pin_for_major 10)" \
      "$(_ena_fallback_pin)"
  ) 2>/dev/null
)"
assert_eq '6=[1.2.3] 8=[] 9=[] 10=[] fb=[]' "${out}" \
  "ena-pin: concrete pin extracted; empty default, non-:- form, garbage, empty fallback ALL yield '' (no raw-line leak)"
rm -rf "${pintmp}"

# (b) Real-file shape regression against the shipped installer: OL6/OL7 pins
# must be concrete x.y.z; the latest-resolving majors (OL8/9/10) must be
# EXACTLY empty (this is the line the AMI-name leak rode in on); the fallback
# pin must be concrete x.y.z. Shape-only (no hardcoded versions) so routine
# pin bumps do not break the tier.
out="$(
  (
    # shellcheck source=/dev/null
    . "${MAIN}" >/dev/null 2>&1
    for m in 6 7 8 9 10; do printf '%s|' "$(_ena_pin_for_major "${m}")"; done
    printf '%s' "$(_ena_fallback_pin)"
  ) 2>/dev/null
)"
IFS='|' read -r p6 p7 p8 p9 p10 pfb <<<"${out}"
assert_match "${p6}"  '^[0-9]+\.[0-9]+\.[0-9]+$' "ena-pin(real): OL6 pin is a concrete x.y.z"
assert_match "${p7}"  '^[0-9]+\.[0-9]+\.[0-9]+$' "ena-pin(real): OL7 pin is a concrete x.y.z"
assert_eq "" "${p8}"  "ena-pin(real): OL8 (latest-resolving) extracts to empty, not the raw line"
assert_eq "" "${p9}"  "ena-pin(real): OL9 (latest-resolving) extracts to empty, not the raw line"
assert_eq "" "${p10}" "ena-pin(real): OL10 (latest-resolving) extracts to empty, not the raw line"
assert_match "${pfb}" '^[0-9]+\.[0-9]+\.[0-9]+$' "ena-pin(real): fallback pin is a concrete x.y.z"

# --- _p3_validate_ks / _p3_validate_provision : Phase-3 exit-gate validators ---
# Structural conformance of the FINAL patched artifacts, on fixtures shaped
# like the real ones. The validators RETURN a finding count (never die), so
# they are directly unit-testable; the gate driver owns the die.
p3tmp="$(mktemp -d)"
cat > "${p3tmp}/good.cfg" <<'GOODKS'
bootloader --append="console=tty0" --location=mbr
part /boot --fstype="xfs" --size=500
part / --fstype="xfs" --grow --size=4096
%packages --nobase
# [ol-aws-ami-builder PATCH sos-package] sosreport tooling baked into every AMI
sos
yum
%end
%post --log=/root/ks-post.log
echo done
%end
GOODKS
sed 's/^%packages --nobase/#gone/'      "${p3tmp}/good.cfg" > "${p3tmp}/nopkg.cfg"
sed 's/^yum$/sos/'                      "${p3tmp}/good.cfg" > "${p3tmp}/dupsos.cfg"
cat > "${p3tmp}/good-prov.sh" <<'GOODPROV'
#!/usr/bin/env bash
echo provisioning
# >>> [ol-aws-ami-builder PATCH demo-hook] >>>
cat > /usr/local/sbin/demo.sh <<'OLAWS_DEMO_EOF'
echo demo
OLAWS_DEMO_EOF
# <<< [ol-aws-ami-builder PATCH demo-hook] <<<
GOODPROV
grep -v '^# <<<' "${p3tmp}/good-prov.sh" > "${p3tmp}/broken-prov.sh"

run_p3() { # <fn> <args...> -> echoes rc
  (
    # shellcheck source=/dev/null
    . "${MAIN}" >/dev/null 2>&1
    if "$@" >/dev/null 2>&1; then echo 0; else echo "$?"; fi
  ) </dev/null
}
assert_eq 0 "$(run_p3 _p3_validate_ks "${p3tmp}/good.cfg" 7)"        "p3-gate: sound patched ks passes (0 findings)"
rc="$(run_p3 _p3_validate_ks "${p3tmp}/nopkg.cfg" 7)"
if [ "${rc}" -ge 1 ]; then t_pass "p3-gate: missing %packages is caught (${rc} findings)"; else t_fail "p3-gate: missing %packages is caught"; fi
rc="$(run_p3 _p3_validate_ks "${p3tmp}/dupsos.cfg" 7)"
if [ "${rc}" -ge 1 ]; then t_pass "p3-gate: duplicated sos line is caught (${rc} findings)"; else t_fail "p3-gate: duplicated sos line is caught"; fi
assert_eq 0 "$(run_p3 _p3_validate_provision "${p3tmp}/good-prov.sh")" "p3-gate: sound provision.sh passes (paired markers + terminated heredoc)"
rc="$(run_p3 _p3_validate_provision "${p3tmp}/broken-prov.sh")"
if [ "${rc}" -ge 1 ]; then t_pass "p3-gate: unpaired hook bracket is caught (${rc} findings)"; else t_fail "p3-gate: unpaired hook bracket is caught"; fi
rm -rf "${p3tmp}"

t_done
