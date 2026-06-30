#!/usr/bin/env bash
#==============================================================================
# tests/t003_acquireunit.sh - L1 unit: acquisition pure helpers + curl-only path
#
# Sources lib/acquire-rootfs.sh (which also sources lib/ubi-pkgmgr.sh; both
# side-effect-free) and exercises the pure helpers - image/tag/ref maps, the
# amd64 digest selector, the OCI URL builders, init-mode args, secrets presence,
# and entitlement classification - plus one end-to-end run of the curl-only
# anonymous pull with curl/tar mocked (sequencing + spying). No real network.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
# shellcheck source=lib/mock.sh
. "${HERE}/lib/mock.sh"
LIB="${PROJ}/lib/acquire-rootfs.sh"
# shellcheck source=/dev/null
. "${LIB}"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# --- image / tag / ref maps --------------------------------------------------
assert_eq "ubi10/ubi-init" "$(acq_image_for_major 10)" "image: 10 -> ubi10/ubi-init"
assert_eq "ubi9/ubi-init"  "$(acq_image_for_major 9)"  "image: 9 -> ubi9/ubi-init"
assert_eq "ubi8/ubi-init"  "$(acq_image_for_major 8)"  "image: 8 -> ubi8/ubi-init"
assert_eq "ubi7/ubi-init"  "$(acq_image_for_major 7)"  "image: 7 -> ubi7/ubi-init"
assert_eq "rhel6/rhel"     "$(acq_image_for_major 6)"  "image: 6 -> rhel6/rhel (legacy non-UBI)"
acq_image_for_major 5 >/dev/null; assert_rc 1 "$?" "image: unknown major -> rc 1"

assert_eq "7.9-88" "$(acq_tag_for_major 7)" "tag: 7 -> fixed 7.9-88 (signature policy, sec 3.5)"
assert_eq "latest" "$(acq_tag_for_major 9)" "tag: 9 -> latest"
assert_eq "latest" "$(acq_tag_for_major 6)" "tag: 6 -> latest"

assert_eq "registry.access.redhat.com/ubi9/ubi-init:latest" "$(acq_ref_for_major 9)" \
  "ref: 9 -> registry/ubi9/ubi-init:latest"
assert_eq "registry.access.redhat.com/ubi7/ubi-init:7.9-88" "$(acq_ref_for_major 7)" \
  "ref: 7 -> fixed tag in the ref"
assert_eq "registry.access.redhat.com/ubi9/ubi-init@sha256:abc" "$(acq_ref_for_major 9 sha256:abc)" \
  "ref: digest pin overrides the tag"

# --- OCI v2 URL builders -----------------------------------------------------
assert_eq "https://registry.access.redhat.com/v2/ubi9/ubi-init/manifests/latest" \
  "$(acq_manifest_url ubi9/ubi-init latest)" "manifest url"
assert_eq "https://registry.access.redhat.com/v2/ubi9/ubi-init/blobs/sha256:dead" \
  "$(acq_blob_url ubi9/ubi-init sha256:dead)" "blob url"

# --- acq_select_amd64_digest: pretty + compact manifest list -----------------
PRETTY='{
  "manifests": [
    { "digest": "sha256:arm64plat", "platform": { "architecture": "arm64", "os": "linux" } },
    { "digest": "sha256:amd64plat", "platform": { "architecture": "amd64", "os": "linux" } }
  ]
}'
assert_eq "sha256:amd64plat" "$(acq_select_amd64_digest "${PRETTY}")" "digest: picks amd64 from pretty JSON"

COMPACT='{"manifests":[{"digest":"sha256:s390","platform":{"architecture":"s390x","os":"linux"}},{"digest":"sha256:amd64plat","platform":{"architecture":"amd64","os":"linux"}}]}'
assert_eq "sha256:amd64plat" "$(acq_select_amd64_digest "${COMPACT}")" "digest: picks amd64 from compact JSON"

assert_eq "" "$(acq_select_amd64_digest '{"manifests":[{"digest":"sha256:x","platform":{"architecture":"ppc64le","os":"linux"}}]}')" \
  "digest: no amd64 entry -> empty"

# --- init-mode invocation args -----------------------------------------------
assert_eq "run --rm registry.access.redhat.com/ubi9/ubi-init:latest aws --version" \
  "$(acq_init_run_args none registry.access.redhat.com/ubi9/ubi-init:latest aws --version)" \
  "init none: explicit command form"
assert_eq "run --rm registry.access.redhat.com/ubi9/ubi-init:latest /bin/bash -lc true" \
  "$(acq_init_run_args none registry.access.redhat.com/ubi9/ubi-init:latest)" \
  "init none: default no-op command"
assert_eq "run -d registry.access.redhat.com/ubi9/ubi-init:latest" \
  "$(acq_init_run_args systemd registry.access.redhat.com/ubi9/ubi-init:latest)" \
  "init systemd: detached boot (image Cmd is /sbin/init)"
acq_init_run_args bogus ref >/dev/null; assert_rc 1 "$?" "init: unknown mode -> rc 1"

# --- acq_secrets_present: present vs absent ----------------------------------
sd="${WORK}/secrets"; mkdir -p "${sd}"
acq_secrets_present "${sd}"; assert_rc 1 "$?" "secrets: empty dir -> rc 1 (absent)"
: > "${sd}/entitlement.pem"
acq_secrets_present "${sd}"; assert_rc 0 "$?" "secrets: a .pem present -> rc 0"
acq_secrets_present "${WORK}/nope"; assert_rc 1 "$?" "secrets: missing dir -> rc 1"

# --- acq_classify_entitlement ------------------------------------------------
ENT_REPOS='rhel-9-for-x86_64-baseos-rpms
rhel-9-for-x86_64-appstream-rpms'
ANON_REPOS='ubi-9-baseos-rpms
ubi-9-appstream-rpms
ubi-9-codeready-builder-rpms'
assert_eq "entitled"  "$(acq_classify_entitlement "${ENT_REPOS}" 0)"  "classify: rhel-* repos + kernel-devel -> entitled"
assert_eq "anonymous" "$(acq_classify_entitlement "${ENT_REPOS}" 1)"  "classify: rhel-* repos but kernel-devel unresolved -> anonymous"
assert_eq "anonymous" "$(acq_classify_entitlement "${ANON_REPOS}" 0)" "classify: only ubi-* repos -> anonymous"
assert_eq "anonymous" "$(acq_classify_entitlement "" 1)"              "classify: empty repo list -> anonymous"

# --- curl-only anonymous pull: full sequence with curl/tar mocked ------------
FIX="${WORK}/fix"; mkdir -p "${FIX}"
cat > "${FIX}/index.json" <<'JSON'
{"manifests":[{"digest":"sha256:amd64plat","platform":{"architecture":"amd64","os":"linux"}},{"digest":"sha256:arm","platform":{"architecture":"arm64","os":"linux"}}]}
JSON
cat > "${FIX}/platform.json" <<'JSON'
{"config":{"digest":"sha256:cfg"},"layers":[{"digest":"sha256:layer1"},{"digest":"sha256:layer2"}]}
JSON
export FIX
td="${WORK}/pull"; mkdir -p "${td}"
dest="${WORK}/rootfs"
out="$(
  (
    # shellcheck source=/dev/null
    . "${LIB}"
    mock_setup "${td}"
    # curl: last arg is the URL (acq_curl puts the URL last). Branch on it.
    # shellcheck disable=SC2016
    mock_cmd curl 'for a in "$@"; do url="$a"; done
      case "$url" in
        */manifests/latest)        cat "$FIX/index.json" ;;
        */manifests/sha256:amd64plat) cat "$FIX/platform.json" ;;
        */blobs/*)                 printf "TGZBYTES" ;;
        *) exit 22 ;;
      esac'
    # tar: consume stdin, succeed (records argv for spying)
    mock_cmd tar 'cat >/dev/null 2>&1; exit 0'
    if acq_pull_curl 9 "$dest"; then printf 'OK'; else printf 'FAIL(%s)' "$?"; fi
  )
)"
assert_eq "OK" "${out}" "curl-only pull: completes for a 2-layer amd64 image"
calls="$(cat "${td}/calls")"
assert_match "${calls}" "/v2/ubi9/ubi-init/manifests/latest" "curl-only pull: spy - fetched the manifest list (no token step)"
assert_match "${calls}" "/v2/ubi9/ubi-init/manifests/sha256:amd64plat" "curl-only pull: spy - fetched the amd64 platform manifest"
assert_eq "2" "$(grep -c '/blobs/' <<<"${calls}")" "curl-only pull: spy - fetched exactly 2 layer blobs"
assert_eq "2" "$(grep -c '^tar ' <<<"${calls}")" "curl-only pull: spy - extracted 2 layers via tar"

t_done
