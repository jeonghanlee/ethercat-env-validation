#!/usr/bin/env bash
#
# Phase 4: DKMS lifecycle for real - conf generation, add, install,
# module load and unload on the running kernel.
# Runs inside the validation VM.

set -euo pipefail

# Non-root Debian sessions do not carry sbin on PATH; dkms and rmmod need it.
export PATH="${PATH}:/usr/sbin:/sbin"

readonly REPO="${HOME}/ethercat-env"

function run {
    printf "\n=== RUN: %s ===\n" "$*"
    "$@"
}

run make -C "${REPO}" module.lifecycle
run make -C "${REPO}" dkms.conf
run sudo make -C "${REPO}" add.dkms
run sudo make -C "${REPO}" install.dkms
run dkms status
run modinfo ec_master
run sudo modprobe ec_master
run sudo modprobe ec_generic
run lsmod
run sudo rmmod ec_generic ec_master

printf "\nphase 4 complete\n"
