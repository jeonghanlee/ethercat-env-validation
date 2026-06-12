#!/usr/bin/env bash
#
# Phase 10: Debian packaging baseline (release-1.0.0 cycle M2).
# Regenerates the pinned orig inside the VM, verifies its content
# checksum, assembles the source tree from orig plus debian/, and runs
# the source and skeletal binary builds. Runs inside the validation VM.

set -euo pipefail

readonly REPO="${HOME}/ethercat-env"
readonly BUILD="${HOME}/pkgbuild"

function run {
    printf "\n=== RUN: %s ===\n" "$*"
    "$@"
}

export DEBIAN_FRONTEND=noninteractive
run sudo -E apt-get install -y debhelper pkgconf autoconf automake libtool

run make -C "${REPO}" init
run make -C "${REPO}" pkg.orig
run make -C "${REPO}" pkg.orig.verify
run make -C "${REPO}" pkg.series
run make -C "${REPO}" pkg.verify

orig="$(ls "${REPO}"/packaging/ethercat_*.orig.tar.gz)"
ver="$(basename "${orig}" .orig.tar.gz)"
ver="${ver#ethercat_}"

run rm -rf "${BUILD}"
run mkdir -p "${BUILD}"
run cp "${orig}" "${BUILD}/"
run tar -xzf "${orig}" -C "${BUILD}"
run cp -a "${REPO}/debian" "${BUILD}/ethercat-${ver}/"

cd "${BUILD}/ethercat-${ver}"
run dpkg-buildpackage -S -us -uc
run dpkg-buildpackage -b -us -uc

run ls -l "${BUILD}"
run dpkg -I "${BUILD}/ethercat-tools_${ver}-1_amd64.deb"
run dpkg -c "${BUILD}/ethercat-tools_${ver}-1_amd64.deb"

printf "\nphase 10 complete\n"
