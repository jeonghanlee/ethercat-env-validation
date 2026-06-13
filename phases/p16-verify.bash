#!/usr/bin/env bash
#
# Phase 16: repository-local verification umbrella (release-1.0.0 cycle
# M8). Installs the full toolchain, builds the packages, runs lintian
# --fail-on error over the .changes (authoritative), and runs
# make verify.all with every lint/check member REAL. The M8.T1
# evidence. Runs inside the validation VM.

set -euo pipefail

export PATH="/usr/sbin:/sbin:${PATH}"
readonly REPO="${HOME}/ethercat-env"
readonly BUILD="${HOME}/pkgbuild"

function run {
    printf "\n=== RUN: %s ===\n" "$*"
    "$@"
}

export DEBIAN_FRONTEND=noninteractive
run sudo -E apt-get install -y debhelper dh-dkms lintian ansible ansible-lint pkgconf autoconf automake libtool

# Build the source + binary packages (produces a .changes).
run make -C "${REPO}" init
run make -C "${REPO}" pkg.orig
orig="$(ls "${REPO}"/packaging/ethercat_*.orig.tar.gz)"
ver="$(basename "${orig}" .orig.tar.gz)"; ver="${ver#ethercat_}"
run rm -rf "${BUILD}"
run mkdir -p "${BUILD}"
run cp "${orig}" "${BUILD}/"
run tar -xzf "${orig}" -C "${BUILD}"
run cp -a "${REPO}/debian" "${BUILD}/ethercat-${ver}/"
( cd "${BUILD}/ethercat-${ver}" && dpkg-buildpackage -us -uc )

changes="$(ls "${BUILD}"/ethercat_*_*.changes)"
printf "changes: %s\n" "${changes}"

# Authoritative lintian: fail on error-level tags (overrides excepted).
run lintian --fail-on error "${changes}"
printf "OK: lintian --fail-on error clean\n"

# The full umbrella, every lint/check member REAL (toolchain present),
# with lintian pointed at the freshly built .changes.
run make -C "${REPO}" verify.all LINTIAN_CHANGES="${changes}"

printf "\nphase 16 complete\n"
