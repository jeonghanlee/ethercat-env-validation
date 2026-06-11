#!/usr/bin/env bash
#
# Phase 9: removal flow for real - dry-run preview, stop and disable,
# uninstall, RT revert, purge, residue audit.
# Runs inside the validation VM.

set -euo pipefail

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

run make -C "${REPO}" remove.dryrun
run sudo make -C "${REPO}" remove.stop
run sudo make -C "${REPO}" remove.disable
run sudo make -C "${REPO}" remove.uninstall
run sudo make -C "${REPO}" remove.rt
run sudo make -C "${REPO}" remove.purge
run make -C "${REPO}" remove.audit
run make -C "${REPO}" verify.residue
record ls -la /opt/ethercat
record systemctl status --no-pager epics-ethercat
record ls -l /usr/bin/ethercat /etc/systemd/system/epics-ethercat.service /etc/udev/rules.d/99-EtherCAT.rules

printf "\nphase 9 complete\n"
