# REFERENCE — Oracle Linux official container images

> **Research memo (static snapshot).** This file records the *official* Oracle
> Linux container images that the `tests/cleancore/build-cleancore-ol{N}.sh`
> scripts use as their build baseline, together with the exact upstream sources
> (sites, URLs, pinned commits) and the official image's RPM manifest
> (name + version). It exists so the self-build clean-core can be understood
> against its reference footprint. It is captured by hand and refreshed when the
> pin or the upstream image changes; it is **not** a drift-checked gate. The
> clean-core images' own package sets are recorded separately, names-only, in
> `tests/cleancore/cleancore-ol<N>.sbom.json`.

## Oracle Linux 10 (`ol10-slim`)

**Upstream sources** (from the build script's PRIMARY SOURCES):

- Slim container image (rootfs): <https://github.com/oracle/container-images/tree/0218ab4ba2f820b1b978dcc5a76435040397a472/10-slim>
- Rootfs tarball (pinned): <https://github.com/oracle/container-images/raw/0218ab4ba2f820b1b978dcc5a76435040397a472/10-slim/oraclelinux-10-slim-amd64-rootfs.tar.xz>
- Slim kickstart (`ol10-ks.cfg`): <https://github.com/oracle/oracle-linux/blob/main/oracle-linux-image-tools/distr/ol10-slim/ol10-ks.cfg>
- Package repositories (BaseOS + AppStream): <https://yum.oracle.com/>
- Pinned `container-images` commit: `0218ab4ba2f820b1b978dcc5a76435040397a472`

**Official `ol10-slim` RPM manifest** (96 packages, name-version-release.arch).
This is the systemd-less reference footprint (full `dnf` is replaced by
`microdnf` + `dnf-data`, and there is no `pam`/`sudo`), which is why the slim
image carries no `systemd`. The `cleancore-ol10` image keeps this slim philosophy
(no `@core`, hence no kernel/boot/firewall/cron/syslog) but adds the explicit
test-base essentials, which transitively pull `systemd` back in via full
`dnf`/`pam`/`sudo`.

```text
alternatives-1.30-2.0.1.el10.x86_64
audit-libs-4.0.3-4.0.1.el10.x86_64
basesystem-11-22.0.1.el10.noarch
bash-5.2.26-6.el10.x86_64
bzip2-libs-1.0.8-25.el10.x86_64
ca-certificates-2025.2.80_v9.0.305-102.el10_1.noarch
coreutils-single-9.5-6.0.1.el10.x86_64
crypto-policies-20250905-2.gitc7eb7b2.el10_1.1.noarch
curl-8.12.1-2.el10_1.2.x86_64
cyrus-sasl-lib-2.1.28-29.el10.x86_64
dnf-data-4.20.0-18.0.1.el10.noarch
filesystem-3.18-17.el10.x86_64
findutils-4.10.0-5.el10.x86_64
gawk-5.3.0-6.el10.x86_64
gdbm-libs-1.23-12.el10_0.x86_64
glib2-2.80.4-10.el10_1.13.x86_64
glibc-2.39-58.0.1.el10_1.7.x86_64
glibc-common-2.39-58.0.1.el10_1.7.x86_64
glibc-minimal-langpack-2.39-58.0.1.el10_1.7.x86_64
gmp-6.2.1-12.el10.x86_64
gnutls-3.8.10-3.el10_1.x86_64
gobject-introspection-1.79.1-6.el10.x86_64
gpg-pubkey-8b4efbe6-61e77439
gpg-pubkey-8d8b756f-61e772ef
grep-3.11-10.el10.x86_64
json-c-0.18-3.el10.x86_64
keyutils-libs-1.6.3-5.el10.x86_64
krb5-libs-1.21.3-9.el10_1.x86_64
libacl-2.3.2-4.el10.x86_64
libarchive-3.7.7-8.el10_1.x86_64
libattr-2.5.2-5.el10.x86_64
libblkid-2.40.2-16.el10_1.x86_64
libbrotli-1.1.0-7.el10_1.x86_64
libcap-2.69-7.el10_1.1.x86_64
libcap-ng-0.8.4-6.el10.x86_64
libcom_err-1.47.1-4.el10.x86_64
libcurl-8.12.1-2.el10_1.2.x86_64
libdnf-0.73.1-12.0.1.el10_1.1.x86_64
libeconf-0.6.2-4.el10.x86_64
libevent-2.1.12-16.el10.x86_64
libffi-3.4.4-10.el10.x86_64
libgcc-14.3.1-2.1.el10.x86_64
libidn2-2.3.7-3.el10.x86_64
libmodulemd-2.15.0-12.el10.x86_64
libmount-2.40.2-16.el10_1.x86_64
libnghttp2-1.64.0-2.el10_1.1.x86_64
libpeas1-1.36.0-8.el10.x86_64
libpsl-0.21.5-6.el10.x86_64
librepo-1.18.0-6.el10_1.x86_64
libselinux-3.9-1.el10.x86_64
libsemanage-3.9-1.el10.x86_64
libsepol-3.9-1.el10.x86_64
libsmartcols-2.40.2-16.el10_1.x86_64
libsolv-0.7.29-8.el10.x86_64
libssh-0.11.1-5.el10_1.x86_64
libssh-config-0.11.1-5.el10_1.noarch
libstdc++-14.3.1-2.1.el10.x86_64
libtasn1-4.20.0-1.el10.x86_64
libunistring-1.1-10.el10.x86_64
libuuid-2.40.2-16.el10_1.x86_64
libverto-0.3.2-10.el10.x86_64
libxcrypt-4.4.36-10.el10.x86_64
libxml2-2.12.5-9.el10_0.x86_64
libyaml-0.2.5-16.el10.x86_64
libzstd-1.5.5-9.el10.x86_64
lua-libs-5.4.6-7.el10.x86_64
lz4-libs-1.9.4-8.el10.x86_64
microdnf-3.10.1-1.el10.x86_64
mpfr-4.2.1-5.el10.x86_64
ncurses-base-6.4-15.20240127.el10_1.noarch
ncurses-libs-6.4-15.20240127.el10_1.x86_64
openldap-2.6.9-1.el10.x86_64
openssl-fips-provider-3.0.7-8.0.1.el10.x86_64
openssl-fips-provider-so-3.0.7-8.0.1.el10.x86_64
openssl-libs-3.5.1-7.0.1.el10_1.x86_64
oraclelinux-release-10.1-1.0.6.el10.x86_64
oraclelinux-release-el10-1.0-17.el10.x86_64
p11-kit-0.25.5-7.el10.x86_64
p11-kit-trust-0.25.5-7.el10.x86_64
pam-libs-1.6.1-8.el10.x86_64
pcre2-10.44-1.0.1.el10.3.x86_64
pcre2-syntax-10.44-1.0.1.el10.3.noarch
popt-1.19-8.el10.x86_64
publicsuffix-list-dafsa-20240107-5.el10.noarch
readline-8.2-11.el10.x86_64
redhat-release-10.1-16.0.1.el10.x86_64
rpm-4.19.1.1-20.0.1.el10.x86_64
rpm-libs-4.19.1.1-20.0.1.el10.x86_64
rpm-sequoia-1.9.0.3-1.0.1.el10_1.x86_64
sed-4.9-3.el10.x86_64
setup-2.14.5-7.el10.noarch
shadow-utils-4.15.0-10.el10_1.x86_64
sqlite-libs-3.46.1-5.el10_1.x86_64
tar-1.35-9.el10_1.x86_64
xz-libs-5.6.2-4.el10_0.x86_64
zlib-ng-compat-2.2.3-3.el10_1.x86_64
```

## Oracle Linux 9 (`ol9-slim`)

**Upstream sources** (from the build script's PRIMARY SOURCES):

- Slim container image (rootfs): <https://github.com/oracle/container-images/tree/0218ab4ba2f820b1b978dcc5a76435040397a472/9-slim>
- Rootfs tarball (pinned): <https://github.com/oracle/container-images/raw/0218ab4ba2f820b1b978dcc5a76435040397a472/9-slim/oraclelinux-9-slim-amd64-rootfs.tar.xz>
- Slim kickstart (`ol9-ks.cfg`): <https://github.com/oracle/oracle-linux/blob/main/oracle-linux-image-tools/distr/ol9-slim/ol9-ks.cfg>
- Package repositories (BaseOS + AppStream): <https://yum.oracle.com/>
- Pinned `container-images` commit: `0218ab4ba2f820b1b978dcc5a76435040397a472`

**Official `ol9-slim` RPM manifest** (107 packages, name-version-release.arch).
Like ol10-slim this is the systemd-less reference footprint (`microdnf` + `dnf-data`,
no full `dnf`/`pam`/`sudo`), hence no `systemd`. The `cleancore-ol9` image keeps
this slim philosophy (no `@core`) but adds the explicit test-base essentials, which
transitively pull `systemd` back in via full `dnf`.

```text
alternatives-1.24-2.0.1.el9.x86_64
audit-libs-3.1.5-7.0.1.el9.x86_64
basesystem-11-13.el9.noarch
bash-5.1.8-9.el9.x86_64
bzip2-libs-1.0.8-10.el9_5.x86_64
ca-certificates-2025.2.80_v9.0.305-91.el9.noarch
coreutils-single-8.32-39.0.1.el9.x86_64
crypto-policies-20250905-1.git377cc42.el9_7.noarch
curl-7.76.1-35.el9_7.3.x86_64
cyrus-sasl-lib-2.1.27-22.el9.x86_64
dnf-data-4.14.0-31.0.1.el9.noarch
file-libs-5.39-16.el9.x86_64
filesystem-3.16-5.el9.x86_64
findutils-4.8.0-7.el9.x86_64
gawk-5.1.0-6.el9.x86_64
gdbm-libs-1.23-1.el9.x86_64
glib2-2.68.4-18.el9_7.2.x86_64
glibc-2.34-231.0.1.el9_7.10.x86_64
glibc-common-2.34-231.0.1.el9_7.10.x86_64
glibc-minimal-langpack-2.34-231.0.1.el9_7.10.x86_64
gmp-6.2.0-13.el9.x86_64
gnupg2-2.3.3-5.el9_7.x86_64
gnutls-3.8.3-10.el9_7.x86_64
gobject-introspection-1.68.0-11.el9.x86_64
gpg-pubkey-8b4efbe6-629ec292
gpg-pubkey-8d8b756f-629e59ec
gpgme-1.15.1-6.el9.x86_64
grep-3.6-5.el9.x86_64
json-c-0.14-11.el9.x86_64
keyutils-libs-1.6.3-1.el9.x86_64
krb5-libs-1.21.1-9.0.1.el9_7.x86_64
libacl-2.3.1-4.el9.x86_64
libarchive-3.5.3-9.el9_7.x86_64
libassuan-2.5.5-3.el9.x86_64
libattr-2.5.1-3.el9.x86_64
libblkid-2.37.4-21.0.1.el9_7.x86_64
libbrotli-1.0.9-9.el9_7.x86_64
libcap-2.48-10.el9_7.1.x86_64
libcap-ng-0.8.2-7.el9.x86_64
libcom_err-1.46.5-8.el9.x86_64
libcurl-7.76.1-35.el9_7.3.x86_64
libdnf-0.69.0-17.0.1.el9_7.x86_64
libevent-2.1.12-8.el9_4.x86_64
libffi-3.4.2-8.el9.x86_64
libgcc-11.5.0-11.0.2.el9.x86_64
libgcrypt-1.10.0-11.el9.x86_64
libgpg-error-1.42-5.el9.x86_64
libidn2-2.3.0-7.el9.x86_64
libksba-1.5.1-7.el9.x86_64
libmodulemd-2.13.0-2.el9.x86_64
libmount-2.37.4-21.0.1.el9_7.x86_64
libnghttp2-1.43.0-6.el9_7.1.x86_64
libpeas-1.30.0-4.el9.x86_64
libpsl-0.21.1-5.el9.x86_64
librepo-1.14.5-3.el9.x86_64
libreport-filesystem-2.15.2-6.0.3.el9.noarch
libselinux-3.6-3.el9.x86_64
libsemanage-3.6-5.el9_6.x86_64
libsepol-3.6-3.el9.x86_64
libsigsegv-2.13-4.el9.x86_64
libsmartcols-2.37.4-21.0.1.el9_7.x86_64
libsolv-0.7.24-3.el9.x86_64
libssh-0.10.4-17.el9_7.x86_64
libssh-config-0.10.4-17.el9_7.noarch
libstdc++-11.5.0-11.0.2.el9.x86_64
libtasn1-4.16.0-9.el9.x86_64
libtool-ltdl-2.4.6-46.el9.x86_64
libunistring-0.9.10-15.el9.x86_64
libuuid-2.37.4-21.0.1.el9_7.x86_64
libverto-0.3.2-3.el9.x86_64
libxcrypt-4.4.18-3.el9.x86_64
libxml2-2.9.13-14.el9_7.x86_64
libyaml-0.2.5-7.el9.x86_64
libzstd-1.5.5-1.el9.x86_64
lua-libs-5.4.4-4.el9.x86_64
lz4-libs-1.9.3-5.el9.x86_64
microdnf-3.9.1-3.el9.x86_64
mpfr-4.1.0-7.el9.x86_64
ncurses-base-6.2-12.20210508.el9.noarch
ncurses-libs-6.2-12.20210508.el9.x86_64
nettle-3.10.1-1.el9.x86_64
npth-1.6-8.el9.x86_64
openldap-2.6.8-4.el9.x86_64
openssl-fips-provider-3.0.7-8.0.1.el9.x86_64
openssl-fips-provider-so-3.0.7-8.0.1.el9.x86_64
openssl-libs-3.5.1-7.0.1.el9_7.x86_64
oraclelinux-release-9.7-1.0.6.el9.x86_64
oraclelinux-release-el9-1.0-26.el9.x86_64
p11-kit-0.25.3-3.el9_5.x86_64
p11-kit-trust-0.25.3-3.el9_5.x86_64
pcre-8.44-4.el9.x86_64
pcre2-10.40-6.0.1.el9.x86_64
pcre2-syntax-10.40-6.0.1.el9.noarch
popt-1.18-8.el9.x86_64
publicsuffix-list-dafsa-20210518-3.el9.noarch
readline-8.1-4.el9.x86_64
redhat-release-9.7-0.6.0.1.el9.x86_64
rpm-4.16.1.3-39.el9.x86_64
rpm-libs-4.16.1.3-39.el9.x86_64
sed-4.8-9.el9.x86_64
setup-2.13.7-10.el9.noarch
shadow-utils-4.9-15.el9.x86_64
sqlite-libs-3.34.1-9.el9_7.x86_64
tar-1.34-9.el9_7.x86_64
tzdata-2026a-1.el9.noarch
xz-libs-5.2.5-8.el9_0.x86_64
zlib-1.2.11-40.el9.x86_64
```
## Oracle Linux 8 (`ol8-slim`)

**Upstream sources** (from the build script's PRIMARY SOURCES):

- Slim container image (rootfs): <https://github.com/oracle/container-images/tree/0218ab4ba2f820b1b978dcc5a76435040397a472/8-slim>
- Rootfs tarball (pinned): <https://github.com/oracle/container-images/raw/0218ab4ba2f820b1b978dcc5a76435040397a472/8-slim/oraclelinux-8-slim-amd64-rootfs.tar.xz>
- Slim kickstart (`ol8-ks.cfg`): <https://github.com/oracle/oracle-linux/blob/main/oracle-linux-image-tools/distr/ol8-slim/ol8-ks.cfg>
- Package repositories (BaseOS + AppStream): <https://yum.oracle.com/>
- Pinned `container-images` commit: `0218ab4ba2f820b1b978dcc5a76435040397a472`

**Official `ol8-slim` RPM manifest** (103 packages, name-version-release.arch).
Like ol9-slim/ol10-slim this is the microdnf-based reference footprint
(`systemd-libs` only -- no full `systemd`/`dnf`/`pam`/`sudo`). It ships
`glibc-minimal-langpack` (en_US only), NOT `glibc-all-langpacks`. The
`cleancore-ol8` image keeps this slim philosophy (no `@core`) but adds the
explicit test-base essentials, which transitively pull full `dnf` (and with it
`systemd`, `pam`, `sudo`) back in. EL8 dnf would otherwise default to
`glibc-all-langpacks` (~416 MB), so the builder pins `glibc-minimal-langpack`
and excludes `glibc-all-langpacks` to match this slim reference.

```text
audit-libs-3.1.2-1.0.1.el8_10.1.x86_64
basesystem-11-5.el8.noarch
bash-4.4.20-6.el8_10.x86_64
brotli-1.0.6-4.el8_10.x86_64
bzip2-libs-1.0.6-28.el8_10.x86_64
ca-certificates-2025.2.80_v9.0.304-80.2.el8_10.noarch
chkconfig-1.19.2-1.0.2.el8.x86_64
coreutils-single-8.30-17.0.1.el8_10.x86_64
crypto-policies-20230731-1.git3177e06.el8.noarch
curl-7.61.1-34.el8_10.11.x86_64
cyrus-sasl-lib-2.1.27-6.el8_5.x86_64
elfutils-libelf-0.190-2.el8.x86_64
file-libs-5.33-27.el8_10.x86_64
filesystem-3.8-6.el8.x86_64
gawk-4.2.1-4.el8.x86_64
glib2-2.56.4-169.el8_10.x86_64
glibc-2.28-251.0.4.el8_10.34.x86_64
glibc-common-2.28-251.0.4.el8_10.34.x86_64
glibc-minimal-langpack-2.28-251.0.4.el8_10.34.x86_64
gmp-6.1.2-11.el8.x86_64
gnupg2-2.2.20-4.el8_10.x86_64
gnutls-3.6.16-8.el8_10.5.x86_64
gobject-introspection-1.56.1-1.el8.x86_64
gpg-pubkey-ad986da3-5cabf60d.(none)
gpgme-1.13.1-12.el8.x86_64
grep-3.1-6.el8.x86_64
info-6.5-7.el8.x86_64
json-c-0.13.1-3.el8.x86_64
keyutils-libs-1.5.10-9.0.1.el8.x86_64
krb5-libs-1.18.2-34.0.1.el8_10.x86_64
libacl-2.2.53-3.el8.x86_64
libarchive-3.3.3-7.el8_10.x86_64
libassuan-2.5.1-3.el8.x86_64
libattr-2.4.48-3.el8.x86_64
libblkid-2.32.1-48.0.2.el8_10.x86_64
libcap-2.48-6.el8_10.1.x86_64
libcap-ng-0.7.11-1.el8.x86_64
libcom_err-1.45.6-7.el8_10.x86_64
libcurl-7.61.1-34.el8_10.11.x86_64
libdb-5.3.28-42.0.1.el8_4.x86_64
libdb-utils-5.3.28-42.0.1.el8_4.x86_64
libdnf-0.63.0-21.0.1.el8_10.x86_64
libffi-3.1-24.el8.x86_64
libgcc-8.5.0-28.0.1.el8_10.x86_64
libgcrypt-1.8.5-7.el8_6.x86_64
libgpg-error-1.31-1.el8.x86_64
libidn2-2.2.0-1.el8.x86_64
libksba-1.3.5-9.el8_7.x86_64
libmodulemd-2.13.0-1.el8.x86_64
libmount-2.32.1-48.0.2.el8_10.x86_64
libnghttp2-1.33.0-6.el8_10.2.x86_64
libpeas-1.22.0-6.el8.x86_64
libpsl-0.20.2-6.el8.x86_64
librepo-1.14.2-5.el8.x86_64
libselinux-2.9-11.el8_10.x86_64
libsemanage-2.9-12.el8_10.x86_64
libsepol-2.9-3.el8.x86_64
libsigsegv-2.11-5.el8.x86_64
libsmartcols-2.32.1-48.0.2.el8_10.x86_64
libsolv-0.7.20-6.el8.x86_64
libssh-0.9.6-16.el8_10.x86_64
libssh-config-0.9.6-16.el8_10.noarch
libstdc++-8.5.0-28.0.1.el8_10.x86_64
libtasn1-4.13-5.el8_10.x86_64
libunistring-0.9.9-3.el8.x86_64
libusbx-1.0.23-4.el8.x86_64
libuuid-2.32.1-48.0.2.el8_10.x86_64
libverto-0.3.2-2.el8.x86_64
libxcrypt-4.1.1-6.el8.x86_64
libxml2-2.9.7-21.el8_10.4.x86_64
libyaml-0.1.7-5.el8.x86_64
libzstd-1.4.4-1.0.1.el8.x86_64
lua-libs-5.3.4-12.el8.x86_64
lz4-libs-1.8.3-5.el8_10.x86_64
microdnf-3.8.0-2.el8.x86_64
mpfr-3.1.6-1.el8.x86_64
ncurses-base-6.1-10.20180224.el8.noarch
ncurses-libs-6.1-10.20180224.el8.x86_64
nettle-3.4.1-7.el8.x86_64
npth-1.5-4.el8.x86_64
openldap-2.4.46-21.el8_10.x86_64
openssl-libs-1.1.1k-15.el8_6.x86_64
oraclelinux-release-8.10-1.0.7.el8.x86_64
oraclelinux-release-el8-1.0-38.el8.x86_64
p11-kit-0.23.22-2.el8.x86_64
p11-kit-trust-0.23.22-2.el8.x86_64
pcre-8.42-6.el8.x86_64
pcre2-10.32-3.el8_6.x86_64
popt-1.18-1.el8.x86_64
publicsuffix-list-dafsa-20180723-1.el8.noarch
readline-7.0-10.el8.x86_64
redhat-release-8.10-0.2.0.1.el8.x86_64
rpm-4.14.3-32.0.1.el8_10.x86_64
rpm-libs-4.14.3-32.0.1.el8_10.x86_64
sed-4.5-5.el8_10.x86_64
setup-2.12.2-9.el8.noarch
shadow-utils-4.6-23.el8_10.x86_64
sqlite-libs-3.26.0-20.el8_10.x86_64
systemd-libs-239-82.0.11.el8_10.16.x86_64
tar-1.30-11.el8_10.x86_64
tzdata-2026a-1.0.1.el8.noarch
xz-libs-5.2.4-4.el8_6.x86_64
zlib-1.2.11-25.el8.x86_64
```
## Oracle Linux 7 (`ol7-slim`)

**Upstream sources** (from the build script's PRIMARY SOURCES):

- Slim container image (rootfs): <https://github.com/oracle/container-images/tree/0218ab4ba2f820b1b978dcc5a76435040397a472/7-slim>
- Rootfs tarball (pinned): <https://github.com/oracle/container-images/raw/0218ab4ba2f820b1b978dcc5a76435040397a472/7-slim/oraclelinux-7-slim-amd64-rootfs.tar.xz>
- Slim kickstart (`ol7-ks.cfg`): <https://github.com/oracle/oracle-linux/blob/main/oracle-linux-image-tools/distr/ol7-slim/ol7-ks.cfg>
- Package repositories (latest + UEKR6): <https://yum.oracle.com/>
- Pinned `container-images` commit: `0218ab4ba2f820b1b978dcc5a76435040397a472`

**Official `ol7-slim` RPM manifest** (108 packages, name-version-release.arch).
The pristine ol7-slim is systemd-less and uses `yum` (EL7 has no `dnf`). EL7 also
has no `glibc` langpack split, so no `glibc-all-langpacks`/`-minimal-langpack`
distinction applies. The `cleancore-ol7` image keeps the slim philosophy (no
`@core`) but adds explicit test-base essentials; `systemd` returns transitively
(pulled by `iputils`/`procps-ng` on EL7, not by a package manager). EL7-specific
package notes: `git` is plain `git` (no `git-core` split on EL7; it pulls
~30 `perl-*` packages), and `git-lfs`/`zstd` are EPEL-only/absent in the EL7
base repos so they are not in the clean-core (installable on demand from the
shipped-disabled Oracle EPEL repo).

```text
audit-libs-2.8.5-4.el7.x86_64
basesystem-10.0-7.0.1.el7.noarch
bash-4.2.46-35.el7_9.x86_64
bzip2-libs-1.0.6-13.el7.x86_64
ca-certificates-2024.2.69_v8.0.303-71.0.1.el7_9.noarch
chkconfig-1.7.6-1.0.3.el7.x86_64
coreutils-8.22-24.0.1.el7_9.2.x86_64
cpio-2.11-28.el7.x86_64
curl-7.29.0-59.0.3.el7_9.2.x86_64
cyrus-sasl-lib-2.1.26-24.0.1.el7_9.x86_64
diffutils-3.3-6.el7_9.x86_64
elfutils-libelf-0.176-5.el7.x86_64
expat-2.1.0-15.0.1.el7_9.x86_64
file-libs-5.11-37.el7.x86_64
filesystem-3.2-25.el7.x86_64
findutils-4.5.11-6.el7.x86_64
gawk-4.0.2-4.el7_3.1.x86_64
gdbm-1.10-8.el7.x86_64
glib2-2.56.1-9.el7_9.x86_64
glibc-2.17-326.0.9.el7_9.3.x86_64
glibc-common-2.17-326.0.9.el7_9.3.x86_64
gmp-6.0.0-15.el7.x86_64
gnupg2-2.0.22-5.el7_5.x86_64
gpg-pubkey-ec551f03-53619141.(none)
gpgme-1.3.2-5.el7.x86_64
grep-2.20-3.el7.x86_64
info-5.1-5.el7.x86_64
kernel-container-3.10.0-0.0.0.2.el7.x86_64
keyutils-libs-1.5.8-3.el7.x86_64
krb5-libs-1.15.1-55.0.7.el7_9.x86_64
libacl-2.2.51-15.el7.x86_64
libassuan-2.1.0-3.el7.x86_64
libattr-2.4.46-13.el7.x86_64
libblkid-2.23.2-65.0.4.el7_9.1.x86_64
libcap-2.22-11.el7.x86_64
libcap-ng-0.7.5-4.el7.x86_64
libcom_err-1.45.4-3.0.7.el7.x86_64
libcurl-7.29.0-59.0.3.el7_9.2.x86_64
libdb-5.3.21-25.el7.x86_64
libdb-utils-5.3.21-25.el7.x86_64
libffi-3.0.13-19.el7.x86_64
libgcc-4.8.5-44.0.3.el7.x86_64
libgcrypt-1.5.3-14.el7.x86_64
libgpg-error-1.12-3.el7.x86_64
libidn-1.28-4.el7.x86_64
libmount-2.23.2-65.0.4.el7_9.1.x86_64
libselinux-2.5-15.el7.x86_64
libsemanage-2.5-14.el7.x86_64
libsepol-2.5-10.el7.x86_64
libssh2-1.8.0-4.el7_9.1.x86_64
libstdc++-4.8.5-44.0.3.el7.x86_64
libtasn1-4.10-1.el7.x86_64
libuuid-2.23.2-65.0.4.el7_9.1.x86_64
libverto-0.2.5-4.el7.x86_64
libxml2-2.9.1-6.0.3.el7_9.6.x86_64
libxml2-python-2.9.1-6.0.3.el7_9.6.x86_64
lua-5.1.4-15.el7.x86_64
ncurses-5.9-14.20130511.el7_4.x86_64
ncurses-base-5.9-14.20130511.el7_4.noarch
ncurses-libs-5.9-14.20130511.el7_4.x86_64
nspr-4.35.0-1.el7_9.x86_64
nss-3.90.0-2.el7_9.x86_64
nss-pem-1.0.3-7.el7_9.1.x86_64
nss-softokn-3.90.0-6.0.1.el7_9.x86_64
nss-softokn-freebl-3.90.0-6.0.1.el7_9.x86_64
nss-sysinit-3.90.0-2.el7_9.x86_64
nss-tools-3.90.0-2.el7_9.x86_64
nss-util-3.90.0-1.el7_9.x86_64
openldap-2.4.44-25.el7_9.x86_64
openssl-libs-1.0.2k-26.el7_9.x86_64
oraclelinux-release-7.9-1.0.13.el7.x86_64
oraclelinux-release-el7-1.0-17.el7.x86_64
p11-kit-0.23.5-3.el7.x86_64
p11-kit-trust-0.23.5-3.el7.x86_64
pcre-8.32-17.el7.x86_64
pinentry-0.8.1-17.el7.x86_64
popt-1.13-16.el7.x86_64
pth-2.0.7-23.el7.x86_64
pygpgme-0.3-9.el7.x86_64
pyliblzma-0.5.3-11.el7.x86_64
python-2.7.5-94.0.1.el7_9.x86_64
python-chardet-2.2.1-3.el7.noarch
python-iniparse-0.4-9.el7.noarch
python-kitchen-1.1.1-5.el7.noarch
python-libs-2.7.5-94.0.1.el7_9.x86_64
python-pycurl-7.19.0-19.el7.x86_64
python-urlgrabber-3.10-10.el7.noarch
pyxattr-0.5.1-5.el7.x86_64
readline-6.2-11.el7.x86_64
redhat-release-server-7.9-6.0.1.el7_9.x86_64
rpm-4.11.3-48.0.3.el7_9.x86_64
rpm-build-libs-4.11.3-48.0.3.el7_9.x86_64
rpm-libs-4.11.3-48.0.3.el7_9.x86_64
rpm-python-4.11.3-48.0.3.el7_9.x86_64
sed-4.2.2-7.el7.x86_64
setup-2.8.71-11.el7.noarch
shadow-utils-4.6-5.0.1.el7.x86_64
shared-mime-info-1.8-5.el7.x86_64
sqlite-3.7.17-8.el7_7.1.x86_64
tar-1.26-35.el7.x86_64
tzdata-2024b-2.el7.noarch
ustr-1.0.4-16.el7.x86_64
xz-libs-5.2.2-2.el7_9.x86_64
yum-3.4.3-168.0.5.el7.noarch
yum-metadata-parser-1.1.4-10.el7.x86_64
yum-plugin-ovl-1.1.31-54.0.1.el7_8.noarch
yum-utils-1.1.31-54.0.1.el7_8.noarch
zlib-1.2.7-21.el7_9.x86_64
```

## Oracle Linux 6 (`6-slim` = OL6.10, primary; `oraclelinux:6.6` image, fallback)

**Upstream sources** (from the build script's PRIMARY SOURCES):

- **PRIMARY** "6-slim" container rootfs (**OL6.10**), Oracle official, pinned in
  `oracle/container-images` at the **same commit** the OL7/OL8 builders use
  (`0218ab4ba2f820b1b978dcc5a76435040397a472`):
  <https://github.com/oracle/container-images/raw/0218ab4ba2f820b1b978dcc5a76435040397a472/6-slim/oraclelinux-6-slim-amd64-rootfs.tar.xz>
  (a plain `FROM scratch + ADD rootfs.tar.xz` image; equivalent to
  `ghcr.io/oracle/oraclelinux:6-slim`, which is built FROM this rootfs).
- **FALLBACK** legacy OL6.6 container image (rpm 4.8 / db4), Oracle public-yum:
  <https://public-yum.oracle.com/docker-images/OracleLinux/OL6/oraclelinux-6.6.tar.xz>
- Package repositories (OL6/latest + UEKR4): <https://yum.oracle.com/>
- EPEL 6 release RPM (EOL; Oracle does not host EPEL 6), Fedora community archive:
  <https://archives.fedoraproject.org/pub/archive/epel/6/x86_64/epel-release-6-8.noarch.rpm>

### Availability investigation (verified 2026-06-17)

An `ol6-slim` *does* exist — the earlier assumption that "Oracle never produced
one" was wrong. Both OL6 official images are still published and pullable:

| Image | Channel | Tag / pin | Version | Digest | Status |
|-------|---------|-----------|---------|--------|--------|
| `oraclelinux:6` | GHCR | `6` = `6.10` | OL6.10 | `sha256:f4f7375d3a220de1158f57719eb1df7a7438cad9e33c3a8b8ce88907684b656b` | published; still pulled |
| `oraclelinux:6-slim` | GHCR | `6-slim` | OL6.10 | `sha256:dbae3e4779d5b412d13d8b06e5ed8bf2a6a9a5a82414646ee76505b10f2fb173` | published; still pulled |
| `6-slim/...rootfs.tar.xz` | git raw (container-images) | `@0218ab4` | OL6.10 | (git blob) | **HTTP 200** at the pinned commit |
| `oraclelinux-6.6.tar.xz` | public-yum | (n/a) | OL6.6 | (n/a) | **HTTP 200**, Last-Modified 2014-11-10 |

Notes on permanence: the GHCR `6`/`6-slim` tags are the **current** OL6.10 images
(published "over 5 years ago", still showing download activity — the content is
static). The **git-raw rootfs** is gone from the repo's `main` branch (OL6 was
removed in an EOL cleanup, like `7-slim`), **but it is permanent at the pinned
commit** `0218ab4` — exactly the durability guarantee the OL7/OL8 builders
already rely on (a git blob at a fixed SHA never changes). The legacy 6.6
public-yum tarball is also still served, so the fallback remains valid.

The builder therefore prefers the **6-slim rootfs at `0218ab4`** (same channel +
pin as OL7/OL8; a plain `curl` of a `tar.xz`, no OCI token/manifest dance) and
falls back to the 6.6 public-yum docker image only if that fetch fails. The GHCR
image is the same OL6.10 content via a different (registry-API) channel; the
git-raw channel is chosen for alignment, dependency-lightness, and because it is
reachable from the same allow-list the OL7/OL8 builders use.

### OL6 optimization (enabled by the 6.10-slim base)

Starting from `6-slim` (OL6.10) instead of the 6.6 image removes the single most
fragile part of the OL6 path:

- **TLS modernization is no longer needed (primary path).** The 6.6 image carried
  a 2014-era NSS that cannot TLS-handshake modern `yum.oracle.com`, so the builder
  host-fetched the `el6_10` NSS/curl/ca-certificates/openssl RPMs and rpm-installed
  them with the builder's own rpm 4.8 before it could resolve packages. The
  6.10-slim rootfs **already ships that stack** — verified in the rootfs: OpenSSL
  `1.0.1e` (TLS 1.2-capable), NSS (OL6.10 = 3.36 line), `libcurl.so.4.1.1`, plus
  `usr/bin/yum` and `bin/rpm`. So on the primary path the whole `el6_10` fetch +
  `rpm -Uvh` modernization is **skipped**; it runs only on the 6.6 fallback.
- **Channel + format alignment with OL7/OL8.** 6-slim is a plain rootfs `tar.xz`
  (extracted directly), not a docker `manifest.json` + `layer.tar` image, so the
  primary path no longer parses a docker manifest. The acquisition now mirrors the
  OL7/OL8 builders (same repo, same pinned commit, same extraction shape).
- **Newer + smaller base.** OL6.10 vs OL6.6 (4 years of EL6 updates already in the
  builder); the slim rootfs is ~24.9 MB (vs the 7-slim ~29.2 MB).
- **Clean-core output is unchanged in *name* set.** The deliverable is still a
  fresh `yum --installroot` install from OL6/latest with the **same `INCLUDE`**, so
  `cleancore-ol6.sbom.json` (names-only) is unaffected by the builder-image switch;
  only package *versions* in the finalized image move forward (re-confirmed on the
  next clean-core rebuild).

`build-cleancore-ol6.sh` uses the builder image only as the EL6-native *builder*
(its rpm writes/reads a db4 rpmdb), then performs a fresh curated
`yum --installroot` install from OL6/latest -- so `cleancore-ol6` is NOT a trim of
the builder image but an independently composed set (recorded names-only in
`cleancore-ol6.sbom.json`). EL6-specific notes: `procps` (not `procps-ng`), `nc`
(not `nmap-ncat`), plain `git` (no `git-core` split; pulls ~`perl-*`), and
`net-tools` is included because EL6 has no standalone `hostname` package (the
command ships in `net-tools`). EPEL 6 is wired in via the Fedora archive (Oracle
hosts no EPEL 6): the clean-core enables its NSS dynamic CA trust, fetches the
release RPM with its own curl and installs it with its own rpm, and ships the
repo repointed to the archive and `enabled=0`. `systemd` does not apply (EL6 is
upstart).

**Legacy fallback `oraclelinux:6.6` RPM manifest** (165 packages, name-version-release.arch):

```text
MAKEDEV-3.24-6.el6.x86_64
audit-libs-2.3.7-5.el6.x86_64
basesystem-10.0-4.0.1.el6.noarch
bash-4.1.2-29.el6.x86_64
binutils-2.20.51.0.2-5.42.el6.x86_64
bzip2-libs-1.0.5-7.el6_0.x86_64
ca-certificates-2014.1.98-65.1.el6.noarch
checkpolicy-2.0.22-1.el6.x86_64
chkconfig-1.3.49.3-2.el6_4.1.x86_64
coreutils-8.4-37.0.1.el6.x86_64
coreutils-libs-8.4-37.0.1.el6.x86_64
cpio-2.10-12.el6_5.x86_64
cracklib-2.8.16-4.el6.x86_64
cracklib-dicts-2.8.16-4.el6.x86_64
curl-7.19.7-37.el6_5.3.x86_64
cyrus-sasl-lib-2.1.23-15.el6.x86_64
db4-4.7.25-18.el6_4.x86_64
db4-utils-4.7.25-18.el6_4.x86_64
dbus-glib-0.86-6.el6_4.x86_64
dbus-libs-1.2.24-7.0.1.el6_3.x86_64
dbus-python-0.83.0-6.1.el6.x86_64
dhclient-4.1.1-43.P1.0.1.el6.x86_64
dhcp-common-4.1.1-43.P1.0.1.el6.x86_64
diffutils-2.8.1-28.el6.x86_64
elfutils-libelf-0.158-3.2.el6.x86_64
ethtool-3.5-5.el6.x86_64
expat-2.0.1-11.el6_2.x86_64
file-libs-5.04-21.el6.x86_64
filesystem-2.4.30-3.el6.x86_64
findutils-4.4.2-6.el6.x86_64
fipscheck-1.2.0-7.el6.x86_64
fipscheck-lib-1.2.0-7.el6.x86_64
gamin-0.1.10-9.el6.x86_64
gawk-3.1.7-10.el6.x86_64
gdbm-1.8.0-36.el6.x86_64
glib2-2.28.8-4.el6.x86_64
glibc-2.12-1.149.el6.x86_64
glibc-common-2.12-1.149.el6.x86_64
gmp-4.3.1-7.el6_2.2.x86_64
gnupg2-2.0.14-8.el6.x86_64
gpg-pubkey-ec551f03-53619141.(none)
gpgme-1.1.8-3.el6.x86_64
grep-2.6.3-6.el6.x86_64
groff-1.18.1.4-21.el6.x86_64
gzip-1.3.12-22.el6.x86_64
hwdata-0.233-11.1.el6.noarch
info-4.13a-8.el6.x86_64
initscripts-9.03.46-1.0.2.el6.x86_64
iproute-2.6.32-32.el6_5.x86_64
iptables-1.4.7-14.0.1.el6.x86_64
iputils-20071127-17.el6_4.2.x86_64
keyutils-libs-1.4-5.el6.x86_64
krb5-libs-1.10.3-33.el6.x86_64
less-436-13.el6.x86_64
libacl-2.2.49-6.el6.x86_64
libattr-2.4.44-7.el6.x86_64
libblkid-2.17.2-12.18.0.1.el6.x86_64
libcap-2.16-5.5.el6.x86_64
libcap-ng-0.6.4-3.el6_0.1.x86_64
libcom_err-1.42.8-1.0.1.el6.x86_64
libcurl-7.19.7-37.el6_5.3.x86_64
libedit-2.11-4.20080712cvs.1.el6.x86_64
libffi-3.0.5-3.2.el6.x86_64
libgcc-4.4.7-11.el6.x86_64
libgcrypt-1.4.5-11.el6_4.x86_64
libgpg-error-1.7-4.el6.x86_64
libgudev1-147-2.57.0.2.el6.x86_64
libidn-1.18-2.el6.x86_64
libnih-1.0.1-7.el6.x86_64
libnl-1.1.4-2.el6.x86_64
libselinux-2.0.94-5.8.el6.x86_64
libselinux-utils-2.0.94-5.8.el6.x86_64
libsemanage-2.0.43-4.2.el6.x86_64
libsepol-2.0.41-4.el6.x86_64
libssh2-1.4.2-1.el6.x86_64
libstdc++-4.4.7-11.el6.x86_64
libtasn1-2.3-6.el6_5.x86_64
libudev-147-2.57.0.2.el6.x86_64
libusb-0.1.12-23.el6.x86_64
libuser-0.56.13-5.el6.x86_64
libutempter-1.1.5-4.1.el6.x86_64
libuuid-2.17.2-12.18.0.1.el6.x86_64
libxml2-2.7.6-14.0.1.el6_5.2.x86_64
libxml2-python-2.7.6-14.0.1.el6_5.2.x86_64
logrotate-3.7.8-17.el6.x86_64
lua-5.1.4-4.1.el6.x86_64
m2crypto-0.20.2-9.el6.x86_64
make-3.81-20.el6.x86_64
mingetty-1.08-5.el6.x86_64
module-init-tools-3.9-24.0.1.el6.x86_64
ncurses-5.7-3.20090208.el6.x86_64
ncurses-base-5.7-3.20090208.el6.x86_64
ncurses-libs-5.7-3.20090208.el6.x86_64
net-tools-1.60-110.el6_2.x86_64
newt-0.52.11-3.el6.x86_64
newt-python-0.52.11-3.el6.x86_64
nspr-4.10.6-1.el6_5.x86_64
nss-3.16.1-14.0.1.el6.x86_64
nss-softokn-3.14.3-17.el6.x86_64
nss-softokn-freebl-3.14.3-17.el6.x86_64
nss-sysinit-3.16.1-14.0.1.el6.x86_64
nss-tools-3.16.1-14.0.1.el6.x86_64
nss-util-3.16.1-3.el6.x86_64
openldap-2.4.39-8.el6.x86_64
openssh-5.3p1-104.el6.x86_64
openssh-clients-5.3p1-104.el6.x86_64
openssh-server-5.3p1-104.el6.x86_64
openssl-1.0.1e-30.el6_6.2.x86_64
oracle-logos-60.0.14-1.0.2.el6.noarch
oraclelinux-release-6Server-6.0.2.x86_64
p11-kit-0.18.5-2.el6_5.2.x86_64
p11-kit-trust-0.18.5-2.el6_5.2.x86_64
pam-1.1.1-20.el6.x86_64
passwd-0.77-4.el6_2.2.x86_64
pcre-7.8-6.el6.x86_64
pinentry-0.7.6-6.el6.x86_64
pkgconfig-0.23-9.1.el6.x86_64
policycoreutils-2.0.83-19.47.0.1.el6.x86_64
popt-1.13-7.el6.x86_64
procps-3.2.8-30.0.1.el6.x86_64
psmisc-22.6-19.el6_5.x86_64
pth-2.0.7-9.3.el6.x86_64
pyOpenSSL-0.10-2.el6.x86_64
pygobject2-2.20.0-5.el6.x86_64
pygpgme-0.1-18.20090824bzr68.el6.x86_64
python-2.6.6-52.el6.x86_64
python-dmidecode-3.10.13-3.el6_4.x86_64
python-ethtool-0.6-5.el6.x86_64
python-gudev-147.1-4.el6_0.1.x86_64
python-iniparse-0.3.1-2.1.el6.noarch
python-libs-2.6.6-52.el6.x86_64
python-pycurl-7.19.0-8.el6.x86_64
python-urlgrabber-3.9.1-9.0.1.el6.noarch
readline-6.0-4.el6.x86_64
redhat-release-server-6Server-6.6.0.2.0.1.el6.x86_64
rhn-check-1.0.0.1-18.0.2.el6.noarch
rhn-client-tools-1.0.0.1-18.0.2.el6.noarch
rhn-setup-1.0.0.1-18.0.2.el6.noarch
rhnlib-2.5.22-15.0.1.el6.noarch
rhnsd-4.9.3-2.0.1.el6.x86_64
rootfiles-8.1-6.1.el6.noarch
rpm-4.8.0-37.el6.x86_64
rpm-libs-4.8.0-37.el6.x86_64
rpm-python-4.8.0-37.el6.x86_64
rsyslog-5.8.10-8.0.1.el6.x86_64
sed-4.2.1-10.el6.x86_64
setup-2.8.14-20.el6_4.1.noarch
shadow-utils-4.1.4.2-19.el6.x86_64
shared-mime-info-0.70-6.el6.x86_64
slang-2.2.1-1.el6.x86_64
sqlite-3.6.20-1.el6.x86_64
sysvinit-tools-2.87-5.dsf.el6.x86_64
tcp_wrappers-libs-7.6-57.el6.x86_64
tzdata-2014g-1.el6.noarch
udev-147-2.57.0.2.el6.x86_64
upstart-0.6.5-13.el6_5.3.x86_64
usermode-1.102-3.el6.x86_64
ustr-1.0.4-9.1.el6.x86_64
util-linux-ng-2.17.2-12.18.0.1.el6.x86_64
vim-minimal-7.2.411-1.8.el6.x86_64
xz-libs-4.999.9-0.5.beta.20091007git.el6.x86_64
yum-3.2.29-60.0.1.el6.noarch
yum-metadata-parser-1.1.2-16.el6.x86_64
yum-rhn-plugin-0.9.1-50.0.1.el6.noarch
zlib-1.2.3-29.el6.x86_64
```

## Oracle Linux 5 (`oraclelinux:5` = `5.11`) — FEASIBILITY INVESTIGATION (build PROVEN)

> **Status: feasibility proven; no builder authored yet.** Unlike the OL6-OL10
> sections (each documents a live `build-cleancore-ol<N>.sh`), this section records
> a feasibility study for an OL5 clean-core. OL5 is EOL (the channels persist as
> sustaining/archived), which is exactly its value: a faithful OL5 clean-core gives
> a quasi-validation environment for the legacy OL5 systems still running in the
> Japanese market. **Conclusion: an OL5 clean-core is feasible and was
> proof-of-concept-verified in-sandbox**, by bootstrapping an EL5-native rpm from
> the OL5 RPMs themselves and installing from a local mirror over `file://` - so it
> needs neither GHCR nor any in-OS TLS.

### (1) Image availability (verified 2026-06-18)

| Image / source | Channel | Tag / pin | Version | Status |
|----------------|---------|-----------|---------|--------|
| `oraclelinux:5` = `oraclelinux:5.11` | GHCR | `5` = `5.11` (aliases of one version `127976`) | OL5.11 | published; amd64-only `manifest.v2`; ~82 MB layer; digest `sha256:a3575cba...`; EOL/frozen; still pulled |
| `5/`, `5-slim/` rootfs.tar.xz | git raw (container-images) | `@0218ab4` | - | **HTTP 404** (no OL5 rootfs in the git tree) |
| OL5 docker image | public-yum | - | - | **HTTP 404** (none) |
| OL5/latest, OL5/UEK R2, EL5/addons, EL5/unsupported (x86_64) | yum.oracle.com | - | - | **HTTP 200** (OL5/latest = 15734 pkgs) |

OL5 predates `*-slim`, so there is one full `oraclelinux:5` image (also `5.11`) and
no `5-slim`; the manifest is single-arch (amd64). There is **no git-raw rootfs and
no public-yum docker image** for OL5. The GHCR image is therefore the only
*pre-built* EL5-native rootfs - but, per (3), the builder does **not** need it.

**Sandbox note (2026-06-18):** bare `ghcr.io` returns `x-deny-reason:
host_not_allowed` in the Claude egress proxy (the allow-list carries `*.ghcr.io`
but not the apex that serves the registry token + `/v2/` API), so the GHCR image
cannot be pulled in-sandbox. This does **not** block the build, because the
EL5-native userland is bootstrapped from the OL5 RPMs (below), all of which are on
the allow-listed `yum.oracle.com`.

### (2) OL5 base facts + the "why do the repos exist if OL5 can't fetch them" question

From `OracleLinux/OL5/latest/x86_64` (verified 2026-06-18):

| Component | OL5 | OL6.10 (contrast) | Note |
|-----------|-----|--------------------|------|
| `rpm` / BerkeleyDB | **4.4.2.3 / db4 4.3.29** | 4.8 / db4 4.7.25 | rpmdb format |
| `glibc` | **2.5** | 2.12 | runtime floor |
| `openssl` | **0.9.8e** (TLS 1.0 ceiling) | 1.0.1e (TLS 1.2) | the TLS problem |
| `nss` / `curl` | 3.21.3 / 7.15.5 (openssl-linked) | 3.36 / 7.19 (NSS-linked) | in-OS HTTPS client |
| `yum` / `python` | 3.2.22 / 2.4.3 | 3.2.29 / 2.6.6 | package manager |
| kernel / UEK | 2.6.18 / **UEK R2** 2.6.32 | 2.6.32 / UEK R4 | - |
| `ca-certificates` | **no separate package** (ships with openssl) | present | trust store |
| `jq` | **absent** (EPEL 5 EOL/archived) | EPEL-transient | test-base essential |

**The repos are fully usable - by modern clients/mirrors, not by OL5's own TLS
stack.** `yum.oracle.com` requires **TLS 1.2** (a forced `--tls-max 1.0` handshake
is refused) and redirects `http` -> `https`, so there is **no plain-HTTP path**.
OL5's in-OS client (`curl 7.15.5` + `openssl 0.9.8e`) tops out at **TLS 1.0**, so a
legacy OL5 box can no longer fetch directly. That is expected and is **not** a
contradiction: the OL5 channels exist as the authoritative *source* that **modern
tooling mirrors from** - the standard way to service EOL systems today is to
`reposync`/mirror on a modern host and serve the legacy boxes from that mirror
(over a LAN, `file://`, or NFS). This is exactly the pattern the OL5 clean-core
builder uses.

### (3) Feasibility - PROVEN by in-sandbox proof-of-concept (2026-06-18)

The two OL5 blockers - (i) no in-OS TLS 1.2, (ii) needing an EL5-native rpm so the
rpmdb is db4.3-native - are both solved **without GHCR** by bootstrapping the
EL5 userland from the OL5 RPMs and installing from a local mirror. Verified
end-to-end in-sandbox:

1. **Host fetches OL5 packages over TLS 1.2** (the modern host / build container is
   the TLS-1.2 client). 38 base RPMs pulled from `yum.oracle.com/.../OL5/latest`
   (rpm, rpm-libs, popt, db4, beecrypt, elfutils-libelf, glibc, glibc-common,
   bash, coreutils, libselinux, libsepol, nss, openssl, ... ~41 MB) - all HTTP 200.
2. **Extract the EL5 `rpm` 4.4 binary + its libs from those RPMs** with `bsdtar`
   (libarchive; preserves symlinks/modes) - no rpm needed on the host.
3. **Run EL5 `rpm` 4.4 inside an `unshare -m` + `chroot`** of a minimal EL5 rootfs
   (consistent EL5 loader + libs): `rpm --version` -> `RPM version 4.4.2.3`.
4. **`rpm --initdb`** creates a **native db4.3 rpmdb** (`Packages` + `__db.00*`).
5. **`rpm -Uvh` installs the staged LOCAL RPMs** (the local mirror, no network/TLS
   in the install path), and **`rpm -qa` reads back all 38** (glibc-2.5,
   openssl-0.9.8e, nss-3.21.3, rpm-4.4.2.3, ...) - the EL5 rpm writes AND reads its
   own db4.3, so the **rpmdb-compat question is moot for this path** (no cross-rpm
   db is ever written).

So a real OL5 clean-core does not need GHCR and does not need the OL6.6-style
in-builder TLS modernization (which is impossible on OL5 anyway, since no OL5
openssl speaks TLS 1.2). The TLS-1.2 fetch is the **host's** job; the EL5-native
rpm only ever touches `file://` local paths.

**Resulting builder design (`build-cleancore-ol5.sh`, to author next):**

- **[A] HOST** mirrors the curated OL5 package closure from `yum.oracle.com/OL5/
  latest` over TLS 1.2 (a `curl`/`reposync`-style fetch into a local dir;
  `createrepo` for a `file://` repo, or a resolved RPM list for `rpm -Uvh`). This is
  the analog of the OL6.6 fallback's host-fetch, generalized from "just the TLS
  stack" to "the package set".
- **[B] BUILDER = EL5-native, bootstrapped from the OL5 RPMs** (extract rpm 4.4 +
  deps with `bsdtar`), not the GHCR image - removing the only GHCR dependency. (If
  GHCR is later allow-listed, pulling `oraclelinux:5` is an equivalent shortcut.)
- **[C] CLEAN-CORE** = a fresh `yum --installroot` (or staged `rpm -Uvh`) from the
  **`file://` local mirror**, so the install path needs no TLS; the deliverable's
  own rpm is EL5 4.4 and its rpmdb is native db4.3. Finalize + self-test mirror the
  OL6 builder.

**Remaining work / caveats (for the build, a long-running [C]3 task):** curate the
OL5 INCLUDE (older names: `procps`, `SysVinit`, no `git-core`; **`jq` decision** -
EPEL 5 is archived, so either pull from the EPEL-5 archive or omit on OL5); decide
EL5 `yum` vs direct `rpm -Uvh` for the install transaction (yum needs python 2.4 +
yum + deps staged in the builder); and run the full build under the
long-running-execution protocol. The PoC proves the mechanism; the full curated
build is the next unit of work.
