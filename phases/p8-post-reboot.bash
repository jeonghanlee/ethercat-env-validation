#!/usr/bin/env bash
#
# Phase 8: post-reboot evidence - running kernel (D2: boot default not
# forced to RT), RT status, service persistence, DKMS module state.
# Runs inside the validation VM after a reboot.

set -euo pipefail

# Non-root Debian sessions do not carry sbin on PATH; dkms needs it.
export PATH="${PATH}:/usr/sbin:/sbin"

readonly REPO="${HOME}/ethercat-env"

function run {
    printf "\n=== RUN: %s ===\n" "$*"
    "$@"
}

function record {
    local ec=0
    printf "\n=== RECORD (failure tolerated): %s ===\n" "$*"
    "$@" || ec=$?
    printf "=== exit code: %s ===\n" "${ec}"
}

run uname -a
run cat /proc/cmdline
run make -C "${REPO}" rt.status
run systemctl is-enabled epics-ethercat
run systemctl is-active epics-ethercat
record systemctl status --no-pager --full epics-ethercat
run sg ethercat -c "/usr/bin/ethercat master"
run dkms status
run make -C "${REPO}" runtime.status

printf "\nphase 8 complete\n"
