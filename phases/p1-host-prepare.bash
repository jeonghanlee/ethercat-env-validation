#!/usr/bin/env bash
#
# Phase 1: OS evidence, build dependencies, repository unpack, doctor.
# Runs inside the validation VM.

set -euo pipefail

readonly REPO="${HOME}/ethercat-env"
readonly TARBALL="/tmp/ethercat-env.tar.gz"

function run {
    printf "\n=== RUN: %s ===\n" "$*"
    "$@"
}

run cat /etc/os-release
run uname -a

export DEBIAN_FRONTEND=noninteractive
run sudo -E apt-get update
run sudo -E apt-get install -y git build-essential autoconf automake libtool pkg-config dkms "linux-headers-$(uname -r)"

[[ -s "${TARBALL}" ]] || { printf "ERROR: repo tarball missing: %s\n" "${TARBALL}" >&2; exit 1; }
rm -rf "${REPO}"
tar -xzf "${TARBALL}" -C "${HOME}"
run ls "${REPO}"

run make -C "${REPO}" host.debian13
run make -C "${REPO}" doctor

printf "\nphase 1 complete\n"
