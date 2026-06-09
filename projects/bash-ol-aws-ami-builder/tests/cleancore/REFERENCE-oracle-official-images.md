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

## Oracle Linux 6 (no `ol6-slim`; base = `oraclelinux:6.6` image)

**Upstream sources** (from the build script's PRIMARY SOURCES):

- Official OL6 container image (rpm 4.8 / db4), Oracle public-yum:
  <https://public-yum.oracle.com/docker-images/OracleLinux/OL6/oraclelinux-6.6.tar.xz>
- Package repositories (OL6/latest + UEKR4): <https://yum.oracle.com/>
- EPEL 6 release RPM (EOL; Oracle does not host EPEL 6), Fedora community archive:
  <https://archives.fedoraproject.org/pub/archive/epel/6/x86_64/epel-release-6-8.noarch.rpm>

Unlike OL7-OL10, Oracle never produced an `ol6-slim` container image or a slim
kickstart for EL6, so there is no upstream slim manifest to diff against. The
official `oraclelinux:6.6` image (manifest below, 165 packages) is a fuller base;
`build-cleancore-ol6.sh` uses it only as the EL6-native *builder* (its rpm 4.8
writes a db4 rpmdb the in-guest EL6 rpm can read), then performs a fresh curated
`yum --installroot` install from OL6/latest -- so `cleancore-ol6` is NOT a trim
of this image but an independently composed set (recorded names-only in
`cleancore-ol6.sbom.json`). EL6-specific notes: `procps` (not `procps-ng`), `nc`
(not `nmap-ncat`), plain `git` (no `git-core` split; pulls ~`perl-*`), and
`net-tools` is included because EL6 has no standalone `hostname` package (the
command ships in `net-tools`). EPEL 6 is wired in via the Fedora archive (Oracle
hosts no EPEL 6): the clean-core enables its NSS dynamic CA trust, fetches the
release RPM with its own curl and installs it with its own rpm, and ships the
repo repointed to the archive and `enabled=0`. `systemd` does not apply (EL6 is
upstart).

**Official `oraclelinux:6.6` RPM manifest** (165 packages, name-version-release.arch):

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
