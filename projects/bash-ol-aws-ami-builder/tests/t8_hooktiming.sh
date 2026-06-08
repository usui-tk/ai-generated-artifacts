#!/usr/bin/env bash
#==============================================================================
# tests/t8_hooktiming.sh - B-T9 OL6 cloud-user hook execution-timing (L1/L2)
#
# Regression guard for the source-time-execution defect (SPEC D.26 "Wiring").
# The OL6 [ol-aws-ami-builder PATCH ol6-cloud-user] hook edits cloud-init's
# config (/etc/cloud/cloud.cfg + .../90_ol.cfg), which only exist AFTER
# cloud::cloud_init has installed cloud-init. bin/provision.sh SOURCES
# cloud/aws/provision.sh (executing any top-level statements) during load_env,
# BEFORE it calls cloud::provision -> cloud::cloud_init. So the hook must be
# wired by WRAPPING cloud::cloud_init -- never run as a top-level `sh <hook>`
# (which executed at source time, before the configs existed, and silently
# skipped, so neither edit ever applied).
#
# (a) STATIC: assert the wrapper wiring is present and the top-level-execution
#     antipattern is absent in build-ol-aws-ami.sh.
# (b) BEHAVIOURAL: build a mock provision.sh (stub cloud::cloud_init that writes
#     upstream-shaped configs + an order log, plus cloud::provision), apply the
#     wrap with the *extracted* hook body, run it the way bin/provision.sh does
#     (define+wrap, then call), and assert the hook fired AFTER cloud_init and
#     produced the corrected config (groups [adm]; default_user name -> ec2-user).
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
# shellcheck source=lib/heredoc.sh
. "${HERE}/lib/heredoc.sh"

MAIN="${PROJ}/build-ol-aws-ami.sh"

# ---- (a) static wiring guards on the actual wrapper -------------------------
inj="$(awk '
  /# >>> \[ol-aws-ami-builder PATCH ol6-cloud-user\] >>>/ { f = 1 }
  f { print }
  /# <<< \[ol-aws-ami-builder PATCH ol6-cloud-user\] <<</ { f = 0 }
' "${MAIN}")"

assert_match "${inj}" 'declare -f cloud::cloud_init' \
  "timing: ol6-cloud-user injection wraps cloud::cloud_init"
assert_match "${inj}" 'cloud::cloud_init\(\) \{ olaws::__orig_cloud_init' \
  "timing: hook runs inside the wrapped cloud::cloud_init (call time, not source time)"
# Antipattern: a top-level `sh <hook>` execution statement emitted by a printf
# (the old, broken form that ran at source time).
if printf '%s\n' "${inj}" | grep -Eq "printf 'sh /usr/local/sbin/ol-aws-ol6-cloud-user\.sh"; then
  t_fail "timing: no top-level 'sh <hook>' execution (source-time antipattern) in injection"
else
  t_pass "timing: no top-level 'sh <hook>' execution (source-time antipattern) in injection"
fi

# ---- (b) behavioural: the wrap defers the hook until after cloud_init -------
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
root="${work}/root"
mkdir -p "${root}/etc/cloud/cloud.cfg.d"
order="${work}/order.log"
: > "${order}"
echo "Oracle Linux Server release 6.10" > "${root}/etc/oracle-release"

# Extract the shipped hook body and redirect its absolute /etc paths into the
# temp root so the tier can run unprivileged.
body="$(extract_heredoc OLAWS_OL6_CLOUD_USER_BODY "${MAIN}")"
if [ -z "${body}" ]; then
  t_fail "timing: OL6 hook body extractable from build-ol-aws-ami.sh"
  t_done
  exit
fi
t_pass "timing: OL6 hook body extractable from build-ol-aws-ami.sh"
printf '%s\n' "${body}" \
  | sed -e "s#cat /etc/oracle-release#cat ${root}/etc/oracle-release#g" \
        -e "s# /etc/cloud/cloud.cfg /etc/cloud/cloud.cfg.d/90_ol.cfg# ${root}/etc/cloud/cloud.cfg ${root}/etc/cloud/cloud.cfg.d/90_ol.cfg#g" \
  > "${work}/hook.sh"

# Mock provision.sh: upstream-shaped cloud::cloud_init + cloud::provision, then
# the wrap (mirrors build-ol-aws-ami.sh's emitted form; `echo HOOK` is test-only
# order instrumentation, and the hook path / CLOUD_USER are pointed at the temp
# root). Written via an unquoted heredoc: ${order}/${root}/${work} expand here,
# while \$(...) and \"\$@\" are kept literal for the guest-side shell.
cat > "${work}/provision.sh" <<MOCK
#!/usr/bin/env bash
set -e
cloud::cloud_init() {
  echo INIT >> "${order}"
  printf 'system_info:\n  default_user:\n    name: cloud-user\n  ssh_svcname: sshd\n' > "${root}/etc/cloud/cloud.cfg"
  printf 'system_info:\n  default_user:\n    name: ec2-user\n    groups: [adm, systemd-journal]\n  distro: rhel\n' > "${root}/etc/cloud/cloud.cfg.d/90_ol.cfg"
}
cloud::provision() { cloud::cloud_init; echo CONFIG >> "${order}"; }
if declare -f cloud::cloud_init >/dev/null 2>&1; then
  eval "olaws::__orig_cloud_init() \$(declare -f cloud::cloud_init | tail -n +2)"
  cloud::cloud_init() { olaws::__orig_cloud_init "\$@"; echo HOOK >> "${order}"; CLOUD_USER=ec2-user sh "${work}/hook.sh"; }
fi
CLOUD_USER=ec2-user cloud::provision
MOCK

bash -n "${work}/provision.sh"
assert_rc 0 $? "timing: emitted mock provision.sh parses (bash -n)"

# Run it as bin/provision.sh would (define + wrap, then call cloud::provision).
bash "${work}/provision.sh" >/dev/null 2>&1 || true

ord="$(tr '\n' ',' < "${order}")"
assert_eq "INIT,HOOK,CONFIG," "${ord}" \
  "timing: hook fires AFTER cloud_init (observed order INIT -> HOOK -> CONFIG)"
assert_match "$(cat "${root}/etc/cloud/cloud.cfg.d/90_ol.cfg")" '^[[:space:]]+groups: \[adm\][[:space:]]*$' \
  "timing: deferred hook corrected 90_ol.cfg groups to [adm]"
assert_match "$(cat "${root}/etc/cloud/cloud.cfg")" '^[[:space:]]+name: ec2-user[[:space:]]*$' \
  "timing: deferred hook aligned cloud.cfg default_user name to ec2-user"

t_done
