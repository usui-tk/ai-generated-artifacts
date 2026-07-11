#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   L1 unit tier for tests/collect-aws-rhui-facts.sh: the pure helpers (pm/repolist/
#   b64url/major-url/leapp-target/major-detect) and the NON-DESTRUCTIVE safety
#   invariant (the collector must never invoke `leapp upgrade`).
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; hermetic (no network, no podman); shellcheck only for t002.
# ----- Usage examples -------------------------------------------------------
#   bash tests/t025_awsrhuicollect.sh
#   bash tests/run-all.sh   # runs every tier
# ----- Known limitations ----------------------------------------------------
#   Covers the pure layer only; the side-effecting collectors and the tar.gz
#   packing are exercised on a real RHUI EC2 host (operator E2E), not here.
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Opus 4.8), claude.ai sessions
#   Generation date: 2026-07-08 (RHUI entitlement investigation collector)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/t025_awsrhuicollect.sh - unit tier for collect-aws-rhui-facts.sh
#
# Loads the collector with RHUI_COLLECT_SOURCED=1 (its main() is guarded, so
# sourcing only defines functions) and asserts the pure helpers. The last
# block is a STATIC MUTATION GUARD: if a future edit ever wired an actual
# `leapp upgrade` into the collector, this tier fails - the dry-run promise is
# machine-enforced, not just documented.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"

COLLECT="${PROJ}/tests/collect-aws-rhui-facts.sh"

# Load the pure layer (main() is guarded behind RHUI_COLLECT_SOURCED).
# shellcheck source=collect-aws-rhui-facts.sh disable=SC1090
RHUI_COLLECT_SOURCED=1 . "${COLLECT}"

if ! declare -F rc_rhui_major_url >/dev/null 2>&1; then
  t_fail "could not source collect-aws-rhui-facts.sh (pure layer)"
  t_done; exit
fi

# --- rc_pm_for_major ----------------------------------------------------------
assert_eq "dnf" "$(rc_pm_for_major 10)" "pm: RHEL 10 -> dnf"
assert_eq "dnf" "$(rc_pm_for_major 8)"  "pm: RHEL 8 -> dnf"
assert_eq "yum" "$(rc_pm_for_major 7)"  "pm: RHEL 7 -> yum"
assert_eq "yum" "$(rc_pm_for_major 6)"  "pm: RHEL 6 -> yum"
rc_pm_for_major 99 >/dev/null 2>&1; assert_eq 1 "$?" "pm: unknown major -> rc 1"

# --- rc_repolist_cmd ----------------------------------------------------------
assert_eq "dnf -q repolist --enabled" "$(rc_repolist_cmd 9 enabled)" "repolist: 9/enabled -> dnf"
assert_eq "yum -q repolist all"       "$(rc_repolist_cmd 7 all)"     "repolist: 7/all -> yum -q"
assert_eq "yum repolist enabled"      "$(rc_repolist_cmd 6 enabled)" "repolist: 6/enabled -> yum (no -q)"
rc_repolist_cmd 5 all >/dev/null 2>&1; assert_eq 1 "$?" "repolist: unknown major -> rc 1"

# --- rc_leapp_target (the cross-major applicability decision) ------------------
assert_eq "10" "$(rc_leapp_target 9)" "leapp target: 9 -> 10"
assert_eq "9"  "$(rc_leapp_target 8)" "leapp target: 8 -> 9"
assert_eq "8"  "$(rc_leapp_target 7)" "leapp target: 7 -> 8"
rc_leapp_target 10 >/dev/null 2>&1; assert_eq 1 "$?" "leapp target: 10 has no N+1 -> rc 1"
rc_leapp_target 6  >/dev/null 2>&1; assert_eq 1 "$?" "leapp target: 6 has no leapp -> rc 1"

# --- rc_chain_list (the r74 downstream acquire-chain) -------------------------
assert_eq "9 10" "$(rc_chain_list 8)" "chain: 8 -> '9 10' (two hops)"
assert_eq "10"   "$(rc_chain_list 9)" "chain: 9 -> '10' (one hop)"
assert_eq ""     "$(rc_chain_list 10)" "chain: 10 -> '' (no downstream)"
assert_eq "8 9 10" "$(rc_chain_list 7)" "chain: 7 -> '8 9 10' (three hops)"

# --- r74 collectors/helpers are wired ----------------------------------------
for fn in rc_collect_chain rc_curl_repo_enum rc_count_packages rc_run_long rc_curl_fetch_pkg rc_decompress rc_builddep_scan rc_rhui_config_url; do
  if declare -F "${fn}" >/dev/null 2>&1; then t_pass "defined: ${fn}"; else t_fail "missing: ${fn}"; fi
done

# --- rc_rhui_major_url (cross-major URL synthesis) ----------------------------
# shellcheck disable=SC2016  # $releasever/$basearch are literal template tokens the helper rewrites
TMPL='https://rhui.REGION.aws.ce.redhat.com/pulp/mirror/content/dist/rhel10/rhui/$releasever/$basearch/os'
assert_match "$(rc_rhui_major_url "${TMPL}" 8)" 'rhel8/rhui/8/x86_64/os' "url synth: rhel10 template -> major 8 path"
assert_match "$(rc_rhui_major_url "${TMPL}" 9)" 'rhel9/rhui/9/x86_64/os' "url synth: rhel10 template -> major 9 path"
# $releasever must be replaced, not left literal.
out="$(rc_rhui_major_url "${TMPL}" 8)"
# shellcheck disable=SC2016  # literal '$releasever' is the token we assert is absent
case "${out}" in *'$releasever'*) t_fail "url synth: \$releasever left unexpanded" ;; *) t_pass "url synth: \$releasever expanded" ;; esac

# --- rc_b64url (urlsafe alphabet) ---------------------------------------------
assert_eq "-_8=" "$(printf '\xfb\xff' | rc_b64url)" "b64url: +/ mapped to -_ (0xfbff -> -_8=)"

# --- rc_detect_major (fixture via RC_RELEASE_FILE seam) -----------------------
fix="$(mktemp)"
printf 'Red Hat Enterprise Linux release 8.10 (Ootpa)\n' > "${fix}"
assert_eq "8" "$(RC_RELEASE_FILE="${fix}" rc_detect_major)" "detect: 'release 8.10' -> 8"
printf 'Red Hat Enterprise Linux Server release 7.9 (Maipo)\n' > "${fix}"
assert_eq "7" "$(RC_RELEASE_FILE="${fix}" rc_detect_major)" "detect: 'Server release 7.9' -> 7"
printf 'Red Hat Enterprise Linux release 10.0 (Coughlan)\n' > "${fix}"
assert_eq "10" "$(RC_RELEASE_FILE="${fix}" rc_detect_major)" "detect: 'release 10.0' -> 10"
rm -f "${fix}"
RC_RELEASE_FILE="/nonexistent/redhat-release" rc_detect_major >/dev/null 2>&1
assert_eq 1 "$?" "detect: missing release file -> rc 1"

# --- STATIC SAFETY GUARD: the collector must never run `leapp upgrade` ---------
# Strip comments, then search for an actual `leapp upgrade` invocation. Only
# `leapp preupgrade` is permitted. This makes the dry-run promise executable.
hits="$(sed 's/#.*//' "${COLLECT}" | grep -Eqc 'leapp[[:space:]]+upgrade' && echo bad || echo ok)"
assert_eq "ok" "${hits}" "safety: no 'leapp upgrade' invocation in the collector (dry-run only)"
# And the dry-run call is present.
grep -Eq 'leapp preupgrade' "${COLLECT}"; assert_eq 0 "$?" "safety: 'leapp preupgrade' dry-run is present"

# --- r80: v1.4.0 collectors are wired -----------------------------------------
for fn in rc_collect_pkgs rc_fetch_build_materials; do
  if declare -F "${fn}" >/dev/null 2>&1; then t_pass "r80 defined: ${fn}"; else t_fail "r80 missing: ${fn}"; fi
done

# --- r80: pkgs/ analyzes RPM FILES, never the install state -------------------
grep -q 'rpm -qip' "${COLLECT}";           assert_eq 0 "$?" "r80 pkgs: rpm -qip on downloaded files"
grep -q 'rpm -qp --triggers' "${COLLECT}"; assert_eq 0 "$?" "r80 pkgs: --triggers captured from files"
grep -q 'rpm -q --triggers' "${COLLECT}";  assert_eq 0 "$?" "r80 base: --triggers captured from installed pkgs"

# --- r80: certs/ coverage self-verification (origin manifest vs copies) --------
grep -q 'origin-sha256.txt' "${COLLECT}"; assert_eq 0 "$?" "r80 coverage: origin sha256 manifest exists"
grep -q 'COVERAGE.txt' "${COLLECT}";      assert_eq 0 "$?" "r80 coverage: COVERAGE.txt verdict file exists"
grep -q 'REPO-REF-UNCOLLECTED' "${COLLECT}"; assert_eq 0 "$?" "r80 coverage: .repo ssl* closure check exists"
# The cp rc must be RECORDED, not swallowed into /dev/null-only.
grep -q "printf 'COPY: %s rc=%s" "${COLLECT}"; assert_eq 0 "$?" "r80 coverage: cp exit status recorded"

# --- r80: chain discovers bundle certs by find, never a hardcoded path ---------
if grep -q 'bdir_default' "${COLLECT}"; then
  t_fail "r80 chain: hardcoded bundle path must be gone (find-based discovery)"
else
  t_pass "r80 chain: hardcoded bundle path removed (find-based discovery)"
fi
# shellcheck disable=SC2016  # the ${hd}/${t} tokens are asserted LITERALLY in the collector source
grep -q 'find "${hd}" -type f -name "content-rhel${t}.crt"' "${COLLECT}"
assert_eq 0 "$?" "r80 chain: content cert discovered via find in extracted payload"

# --- r80: chain proves OBTAINABILITY (build-material RPM downloads) ------------
# shellcheck disable=SC2016  # literal '${' distinguishes call sites from the definition line
n="$(grep -c 'rc_fetch_build_materials "\${' "${COLLECT}")"
assert_eq 2 "${n}" "r80 chain: build materials fetched for own major AND every hop (2 call sites)"
grep -q 'RC_KEEP_RPMS:-0' "${COLLECT}"; assert_eq 0 "$?" "r80 chain: RPM blobs deleted by default (--keep-rpms opt-in)"

# --- r80: rc_fetch_build_materials fixture (hermetic; no network) --------------
fbd="$(mktemp -d)"
printf 'kernel-devel: NOT-FOUND\ngcc: NOT-FOUND\n' > "${fbd}/builddep-scan.txt"
res="$(rc_fetch_build_materials "${fbd}" 9 /no/cert /no/key)"
assert_eq "ok=0 total=2" "${res}" "r80 fetch: NOT-FOUND scan -> ok=0 total=2, nothing fetched"
grep -q 'kernel-devel: SKIP' "${fbd}/build-materials.txt"
assert_eq 0 "$?" "r80 fetch: NOT-FOUND entries recorded as SKIP facts"
res="$(rc_fetch_build_materials "${fbd}/nodir" 9 u u c k 2>/dev/null)"
assert_eq "ok=0 total=0" "${res}" "r80 fetch: absent scan file -> recorded skip, rc 0"
rm -rf "${fbd}"

# --- r80: leapp preupgrade is OPT-IN (default off) ------------------------------
grep -q 'do_leapp=0 do_cross=1' "${COLLECT}"; assert_eq 0 "$?" "r80 leapp: default OFF in rc_main"
grep -q -- '--leapp)        do_leapp=1' "${COLLECT}"; assert_eq 0 "$?" "r80 leapp: --leapp opt-in flag present"

# --- r81: v1.5.0 helpers are wired ---------------------------------------------
for fn in rc_fetch_pkg_from_prim rc_slim_primary; do
  if declare -F "${fn}" >/dev/null 2>&1; then t_pass "r81 defined: ${fn}"; else t_fail "r81 missing: ${fn}"; fi
done

# --- r81 REGRESSION: the scan survives large streams (pipefail x SIGPIPE) ------
# grep -q exits at the first match and SIGPIPEs the decompressor; under
# pipefail the `if` sees FALSE even though the match EXISTS. Only large
# streams (>> the 64KB pipe buffer) open the window - which is why the -q
# form passed every small-fixture gate and failed on every real host (r80
# evidence: all 24 builddep cells NOT-FOUND with the packages present).
sig="$(mktemp -d)"
{ printf '<package type="rpm">\n  <name>kernel-devel</name>\n</package>\n'
  i=0; while [ "${i}" -lt 300000 ]; do printf '<package type="rpm"><name>filler</name></package>\n'; i=$((i+1)); done
} | gzip > "${sig}/curl-rhel9-baseos-fixture-primary.xml.gz"
# (a) MUTATION DEMO: the r79 -q form misses on this stream under pipefail.
if rc_decompress "${sig}/curl-rhel9-baseos-fixture-primary.xml.gz" | grep -qE '<name>kernel-devel</name>'; then
  old_form=matched
else
  old_form=missed
fi
assert_eq "missed" "${old_form}" "r81 sigpipe: the old grep -q form misses on a large stream (bug reproduced)"
# (b) the shipped scan finds it.
rc_builddep_scan "${sig}" 9 kernel-devel
grep -q '^kernel-devel: baseos$' "${sig}/builddep-scan.txt"
assert_eq 0 "$?" "r81 sigpipe: rc_builddep_scan (grep -c form) finds the match on the same stream"
rm -rf "${sig}"

# --- r81: boundary-safe location match (make must never fetch automake) --------
bnd="$(mktemp -d)"
printf '<package type="rpm"><name>automake</name><location href="Packages/a/automake-1.16.1-6.el8.noarch.rpm"/></package>\n<package type="rpm"><name>make</name><location href="Packages/m/make-4.2.1-11.el8.x86_64.rpm"/></package>\n' \
  | gzip > "${bnd}/prim.gz"
out="$(rc_fetch_pkg_from_prim "${bnd}" bt make "${bnd}/prim.gz" http://127.0.0.1:1 /no/c /no/k 2>/dev/null)" || true
grep -q '^location=Packages/m/make-4.2.1-11.el8.x86_64.rpm$' "${bnd}/bt-fetch.txt"
assert_eq 0 "$?" "r81 boundary: 'make' selects plain make, never automake (r79 pattern would have)"
printf '<package type="rpm"><name>automake</name><location href="Packages/a/automake-1.16.1-6.el8.noarch.rpm"/></package>\n' \
  | gzip > "${bnd}/prim2.gz"
rc_fetch_pkg_from_prim "${bnd}" bt2 make "${bnd}/prim2.gz" http://127.0.0.1:1 /no/c /no/k >/dev/null 2>&1
assert_eq 1 "$?" "r81 boundary: automake-only primary -> pkg-not-in-primary (rc 1)"
rm -rf "${bnd}"

# --- r81: primary slimming (real one-line-joined element format) ---------------
slm="$(mktemp -d)"
printf '<metadata packages="2"><package type="rpm">\n  <name>gcc</name>\n  <location href="Packages/g/gcc-8.2.1-3.5.el8.x86_64.rpm"/>\n</package><package type="rpm">\n  <name>filler</name>\n  <location href="Packages/f/filler-1-1.rpm"/>\n</package></metadata>\n' \
  | gzip > "${slm}/curl-rhel8-appstream-fx-primary.xml.gz"
rc_slim_primary "${slm}" "kernel-devel|gcc|make|elfutils-libelf-devel|leapp-rhui-aws" "${slm}/curl-rhel8-appstream-fx-primary.xml.gz"
if [ -e "${slm}/curl-rhel8-appstream-fx-primary.xml.gz" ]; then
  t_fail "r81 slim: blob must be deleted by default"
else
  t_pass "r81 slim: blob deleted by default"
fi
n="$(gzip -dc "${slm}/curl-rhel8-appstream-fx-primary-names.txt.gz" | wc -l)"
assert_eq 2 "${n}" "r81 slim: names list has both packages (sorted unique)"
grep -q '<name>gcc</name>' "${slm}/curl-rhel8-appstream-fx-primary-slices.xml"
assert_eq 0 "$?" "r81 slim: interest package slice survives ('</package><package' joined line handled)"
if grep -q '<name>filler</name>' "${slm}/curl-rhel8-appstream-fx-primary-slices.xml"; then
  t_fail "r81 slim: non-interest packages must not be sliced"
else
  t_pass "r81 slim: non-interest packages excluded from slices"
fi
[ -s "${slm}/curl-rhel8-appstream-fx-primary-primary.sha256" ]
assert_eq 0 "$?" "r81 slim: origin blob sha256 recorded"
printf 'x\n' | gzip > "${slm}/keep-primary.xml.gz"
RC_KEEP_METADATA=1 rc_slim_primary "${slm}" "gcc" "${slm}/keep-primary.xml.gz"
[ -e "${slm}/keep-primary.xml.gz" ]
assert_eq 0 "$?" "r81 slim: RC_KEEP_METADATA=1 keeps the raw blob (--keep-metadata)"
rm -rf "${slm}"

# --- r81: materials fetch reuses the on-disk primary (no re-download) ----------
# shellcheck disable=SC2016  # the ${hd} token is asserted LITERALLY in the collector source
grep -q 'rc_fetch_pkg_from_prim "\${hd}/materials"' "${COLLECT}"
assert_eq 0 "$?" "r81 reuse: build materials fetched via the already-downloaded primary"
grep -q -- '--keep-metadata) RC_KEEP_METADATA=1' "${COLLECT}"
assert_eq 0 "$?" "r81 reuse: --keep-metadata flag wired"

# --- r82: E0 probes are wired (authmatrix + containerprobe) --------------------
for fn in rc_synth_repo_file rc_authmatrix_cell rc_collect_authmatrix \
          rc_acquire_forward_certs rc_collect_containerprobe; do
  if declare -F "${fn}" >/dev/null 2>&1; then t_pass "r82 defined: ${fn}"; else t_fail "r82 missing: ${fn}"; fi
done

# --- r82: rc_synth_repo_file - both amazon-id plugin jobs done ahead of time ---
# shellcheck disable=SC2016  # the template tokens are literal inputs the helper rewrites
E0TMPL='https://rhui.REGION.aws.ce.redhat.com/pulp/mirror/content/dist/rhel8/rhui/$releasever/$basearch/baseos/os'
synth="$(rc_synth_repo_file 9 ap-northeast-1 "${E0TMPL}" /run/rhui-e0)"
case "${synth}" in *REGION*) t_fail "r82 synth: REGION literal must be substituted" ;; *) t_pass "r82 synth: REGION substituted (containers have no amazon-id plugin)" ;; esac
# shellcheck disable=SC2016  # asserting the literal token is ABSENT
case "${synth}" in *'$releasever'*) t_fail "r82 synth: \$releasever must be expanded" ;; *) t_pass "r82 synth: \$releasever expanded" ;; esac
printf '%s\n' "${synth}" | grep -q 'dist/rhel9/rhui/9/x86_64/baseos/os'
assert_eq 0 "$?" "r82 synth: target-major baseos path (rhel8 template -> rhel9)"
printf '%s\n' "${synth}" | grep -q 'dist/rhel9/rhui/9/x86_64/appstream/os'
assert_eq 0 "$?" "r82 synth: appstream section synthesized from the baseos template"
n="$(printf '%s\n' "${synth}" | grep -c '^\[rhui-e0-rhel9-')"
assert_eq 2 "${n}" "r82 synth: exactly two sections (baseos + appstream)"
printf '%s\n' "${synth}" | grep -q '^sslclientcert=/run/rhui-e0/content-rhel9.crt$'
assert_eq 0 "$?" "r82 synth: ssl paths point at the mounted bundle"
printf '%s\n' "${synth}" | grep -q '^gpgcheck=1$'
assert_eq 0 "$?" "r82 synth: gpgcheck stays ON (UBI ships the Red Hat GPG key)"

# --- r82: authmatrix covers the full credential square + the RPM-body layer ----
for cell in 'cert+headers' 'cert-only' 'headers-only' 'none'; do
  if grep -q "rc_authmatrix_cell \"\${am}\" \"${cell}" "${COLLECT}"; then
    t_pass "r82 authmatrix: cell '${cell}' measured"
  else
    t_fail "r82 authmatrix: cell '${cell}' missing"
  fi
done
grep -q 'rpm-body cert-only' "${COLLECT}"
assert_eq 0 "$?" "r82 authmatrix: RPM-body layer measured for the cert-only cell"

# --- r82: authmatrix cell record shape (hermetic: unreachable endpoint) --------
amx="$(mktemp -d)"
rc_authmatrix_cell "${amx}/o.txt" "cert-only" http://127.0.0.1:1/ml "" ""
grep -q '^cert-only: mirrorlist_http=000 repomd_http=no-mirror$' "${amx}/o.txt"
assert_eq 0 "$?" "r82 authmatrix: unreachable endpoint recorded as 000/no-mirror"
rm -rf "${amx}"

# --- r82: containerprobe measures ONLY the synthesized repos -------------------
grep -q -- '--disablerepo=\* --enablerepo=rhui-e0-\*' "${COLLECT}"
assert_eq 0 "$?" "r82 containerprobe: dnf scoped to the synthesized repos only"
grep -q 'latest/api/token' "${COLLECT}"
assert_eq 0 "$?" "r82 containerprobe: U2 in-container IMDS token PUT present"
grep -q 'kernel-devel gcc make elfutils-libelf-devel 2>&1' "${COLLECT}"
assert_eq 0 "$?" "r82 containerprobe: payload is the ENA build-dep set"

# --- r82: flags wired, off by default ------------------------------------------
grep -q 'do_authmx=0 do_ctr=0' "${COLLECT}"; assert_eq 0 "$?" "r82 flags: E0 probes OFF by default"
grep -q -- '--authmatrix)    do_authmx=1' "${COLLECT}"; assert_eq 0 "$?" "r82 flags: --authmatrix wired"
grep -q -- '--containerprobe) do_ctr=1' "${COLLECT}"; assert_eq 0 "$?" "r82 flags: --containerprobe wired"

# --- r83: E0-follow probes wired (hostvscontainer + sigttl) --------------------
for fn in rc_collect_hostvscontainer rc_hvc_container_cell rc_collect_sigttl; do
  if declare -F "${fn}" >/dev/null 2>&1; then t_pass "r83 defined: ${fn}"; else t_fail "r83 missing: ${fn}"; fi
done

# --- r83: hostvscontainer measures the SAME four cells on BOTH sides ----------
for cell in 'cert+headers' 'cert-only' 'headers-only' 'none'; do
  if grep -q "rc_authmatrix_cell \"\${paired}\" \"host ${cell}" "${COLLECT}"; then
    t_pass "r83 hvc: host '${cell}' cell present"
  else
    t_fail "r83 hvc: host '${cell}' cell missing"
  fi
  if grep -q "rc_hvc_container_cell \"\${img}\" \"\${paired}\" \"${cell}" "${COLLECT}"; then
    t_pass "r83 hvc: container '${cell}' cell present"
  else
    t_fail "r83 hvc: container '${cell}' cell missing"
  fi
done

# --- r83: chain-reachable majors are STILL measured (no simplification) --------
# shellcheck disable=SC2016  # the loop expression is asserted LITERALLY in the source
grep -q 'for t in ${major} $(rc_chain_list "${major}")' "${COLLECT}"
assert_eq 0 "$?" "r83 hvc: own major AND every chain major measured (network not simplified)"

# --- r83: B" static header injection - headers generated on HOST, fed by file --
grep -q 'headers.curl' "${COLLECT}"; assert_eq 0 "$?" "r83 hvc: static header file (host-generated, container-consumed)"
grep -q 'X-RHUI-ID' "${COLLECT}";   assert_eq 0 "$?" "r83 hvc: identity headers assembled"

# --- r83: sigttl freezes ONE generation and re-tests over offsets -------------
grep -q 'RC_SIGTTL_OFFSETS:-0 300 900 1800 3600' "${COLLECT}"
assert_eq 0 "$?" "r83 sigttl: default offset schedule 0/5/15/30/60m"
grep -q 'frozen_at=' "${COLLECT}"; assert_eq 0 "$?" "r83 sigttl: single frozen generation re-tested (TTL measurement)"

# --- r83: hvc/sigttl on a non-RHUI host skip cleanly (hermetic) ---------------
hvcd="$(mktemp -d)"
rc_collect_hostvscontainer "${hvcd}" 8 2>/dev/null
grep -q 'redhat-rhui.repo absent' "${hvcd}/hostvscontainer/SKIPPED.txt"
assert_eq 0 "$?" "r83 hvc: clean skip when not an RHUI host"
rc_collect_sigttl "${hvcd}" 8 2>/dev/null
grep -q 'redhat-rhui.repo absent' "${hvcd}/sigttl/SKIPPED.txt"
assert_eq 0 "$?" "r83 sigttl: clean skip when not an RHUI host"
rm -rf "${hvcd}"

# --- r83: flags wired, off by default -----------------------------------------
grep -q 'do_hvc=0 do_sigttl=0' "${COLLECT}"; assert_eq 0 "$?" "r83 flags: E0-follow probes OFF by default"
grep -q -- '--hostvscontainer) do_hvc=1' "${COLLECT}"; assert_eq 0 "$?" "r83 flags: --hostvscontainer wired"
grep -q -- '--sigttl)        do_sigttl=1' "${COLLECT}"; assert_eq 0 "$?" "r83 flags: --sigttl wired"

# --- r83: the emitted archive path is ABSOLUTE (operator request) -------------
# shellcheck disable=SC2016  # asserting the literal source line, not expanding here
grep -q 'abs_archive="$(cd "$(dirname "${archive}")"' "${COLLECT}"
assert_eq 0 "$?" "r83 emit: archive path resolved to absolute"
grep -q 'abs_archive}"$' "${COLLECT}"
assert_eq 0 "$?" "r83 emit: absolute path is what's printed to stdout"

# --- r84: measurement-bug fix - --cacert is INDEPENDENT of the client cert ----
# r83 put --cacert inside the send_cert branch, so headers-only/none couldn't
# complete TLS in the container (000 instead of the true 403). This regression
# guard pins that the CA is always present and lives OUTSIDE any cert branch.
sedblk="$(sed -n '/^rc_hvc_container_cell/,/^}/p' "${COLLECT}")"
# shellcheck disable=SC2016
case "${sedblk}" in
  *'[ "${send_cert}" = 1 ] && cargs='*'--cacert'*) t_fail "r84 cacert: still inside the cert branch (r83 bug)" ;;
  *) t_pass "r84 cacert: not gated by the cert branch" ;;
esac
printf '%s\n' "${sedblk}" | grep -q 'cacert /run/rhui-e0/cdn.redhat.com-chain.crt'
assert_eq 0 "$?" "r84 cacert: CA passed to the container curl (all cells)"

# --- r84: credentials travel as ENV VARS, not string-spliced into the script --
# String-splicing broke on header values with shell metacharacters; env vars
# don't. Assert the podman invocation passes -e URL/LBL/HDRS and the script
# reads them, and that HDRS is eval'd (trusted host-generated -H string).
# shellcheck disable=SC2016
printf '%s\n' "${sedblk}" | grep -q -- '-e "URL=${url}"'
assert_eq 0 "$?" "r84 envpass: URL passed as env, not spliced"
# shellcheck disable=SC2016
printf '%s\n' "${sedblk}" | grep -q -- '-e "HDRS=${hdrs}"'
assert_eq 0 "$?" "r84 envpass: HDRS passed as env, not spliced"

# --- r84: hermetic - cell script carries CA for a no-cert cell ----------------
RC_HVC_BUNDLE="$(mktemp -d)"
printf -- '-H "X-RHUI-ID: A&B" -H "X-RHUI-SIGNATURE: C%%D"' > "${RC_HVC_BUNDLE}/headers.curl"
podman() { printf 'PODMAN: %s\n' "$*"; }
rc_hvc_container_cell fake/img "${RC_HVC_BUNDLE}/cell.txt" "headers-only" "https://x/ml" 0 "${RC_HVC_BUNDLE}/headers.curl"
grep -q 'cacert /run/rhui-e0/cdn.redhat.com-chain.crt' "${RC_HVC_BUNDLE}/cell.txt"
assert_eq 0 "$?" "r84 hermetic: headers-only cell still carries --cacert"
grep -q 'HDRS=-H "X-RHUI-ID: A&B"' "${RC_HVC_BUNDLE}/cell.txt"
assert_eq 0 "$?" "r84 hermetic: header metacharacters survive via env (not spliced)"
unset -f podman
rm -rf "${RC_HVC_BUNDLE}"; unset RC_HVC_BUNDLE

# --- r84: paired flow now measures the RPM-body + real dnf makecache layers ----
for fn in rc_hvc_container_rpmbody rc_hvc_container_makecache; do
  if declare -F "${fn}" >/dev/null 2>&1; then t_pass "r84 defined: ${fn}"; else t_fail "r84 missing: ${fn}"; fi
done
# shellcheck disable=SC2016
grep -q 'rc_hvc_container_rpmbody "${img}"' "${COLLECT}"
assert_eq 0 "$?" "r84 paired: RPM-body layer measured in-container"
# shellcheck disable=SC2016
grep -q 'rc_hvc_container_makecache "${img}"' "${COLLECT}"
assert_eq 0 "$?" "r84 paired: real dnf makecache measured in-container (B\" end to end)"

# --- r84: the static-header dnf plugin is valid and scoped ---------------------
RC_HVC_BUNDLE="$(mktemp -d)"
printf -- '-H "X-RHUI-ID: DOCVAL" -H "X-RHUI-SIGNATURE: SIGVAL"' > "${RC_HVC_BUNDLE}/headers.curl"
podman() { cp "${RC_HVC_BUNDLE}/e0inject.py" "${RC_HVC_BUNDLE}/captured.py" 2>/dev/null; :; }
rc_hvc_container_makecache fake/img /dev/null 9 "${RC_HVC_BUNDLE}/headers.curl"
unset -f podman
python3 -c "import ast,sys; ast.parse(open('${RC_HVC_BUNDLE}/captured.py').read())" 2>/dev/null
assert_eq 0 "$?" "r84 plugin: generated dnf plugin is valid python"
grep -q 'X-RHUI-ID: DOCVAL' "${RC_HVC_BUNDLE}/captured.py"
assert_eq 0 "$?" "r84 plugin: host-generated header value embedded"
grep -q 'startswith("rhui-e0-")' "${RC_HVC_BUNDLE}/captured.py"
assert_eq 0 "$?" "r84 plugin: injection scoped to the synthesized rhui-e0 repos"
rm -rf "${RC_HVC_BUNDLE}"; unset RC_HVC_BUNDLE

# --- REGRESSION GUARD (r78): the chain probe is curl-native (no dnf) ----------
# The chain must acquire/measure via curl only. If a future edit reintroduces a
# dnf-driven chain step, cross-major breaks again (dnf failed three ways: 403,
# already-installed, modular platform). Assert the chain's acquisition uses the
# curl fetch helper and writes no /etc/yum.repos.d chain repo file.
grep -q '"leapp-rhui-aws"' "${COLLECT}"; assert_eq 0 "$?" "r79: chain fetches leapp-rhui-aws via curl (rc_curl_fetch_pkg)"
grep -q 'rc_rhui_config_url' "${COLLECT}"; assert_eq 0 "$?" "r79: chain reaches the client-config repo (config-cert path, non-circular)"
if grep -Eq '/etc/yum\.repos\.d/chain-' "${COLLECT}"; then t_fail "r79: chain must not write dnf repo files (curl-native)"; else t_pass "r79: chain writes no dnf repo files (curl-native)"; fi

t_done
