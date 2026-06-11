#!/usr/bin/env bash
#
# Phase 6: systemd unit and udev rule install, runtime config install,
# service enable and start, live master state, consolidated runtime status.
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

run make -C "${REPO}" systemd.render
run sudo make -C "${REPO}" systemd.install
run make -C "${REPO}" udev.render
run sudo make -C "${REPO}" udev.install
run getent group ethercat
run sudo make -C "${REPO}" runtime.install
run cmp /opt/ethercat/etc/ethercat.conf "${REPO}/build/ethercat.conf"
run sudo make -C "${REPO}" iface.prepare
run sudo make -C "${REPO}" systemd.enable
run sudo make -C "${REPO}" systemd.start
run systemctl status --no-pager --full epics-ethercat
run ls -l /dev/EtherCAT0

# Operator step from docs/install.md: device-group membership for unprivileged
# tool access. sg applies the new group without waiting for a fresh login.
run sudo usermod -aG ethercat validator
run sg ethercat -c "/usr/bin/ethercat master"
record sg ethercat -c "/usr/bin/ethercat slaves"

run make -C "${REPO}" runtime.status

printf "\nphase 6 complete\n"
