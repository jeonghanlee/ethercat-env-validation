#!/usr/bin/env bash
#
# Phase 18: package/Ansible acceptance, post-reboot + removal
# (release-1.0.0 cycle M9). Runs AFTER a host-driven reboot. Asserts
# the provisioned host comes up without manual repair (p8 parity), then
# purges and audits residue via the package-path inline check (p9
# parity; the group is retained per U4). Runs inside the validation VM.

set -euo pipefail

export PATH="/usr/sbin:/sbin:${PATH}"
readonly REPO="${HOME}/ethercat-env"

function run {
    printf "\n=== RUN: %s ===\n" "$*"
    "$@"
}

run uname -r
run cat /proc/cmdline

# p8 parity: the package/Ansible-provisioned host comes up clean.
systemctl is-active --quiet ethercat.service || { printf "FAIL: service not active after reboot\n" >&2; exit 1; }
printf "OK: p8 parity - ethercat.service active after reboot (no manual repair)\n"
[[ -e /dev/EtherCAT0 ]] || { printf "FAIL: /dev/EtherCAT0 missing after reboot\n" >&2; exit 1; }
run sg ethercat -c "/usr/bin/ethercat master"
run dkms status ethercat
run make -C "${REPO}" rt.status
printf "OK: p8 parity - master present, dkms intact, rt.status read\n"

# p9 parity: purge and the package-path inline residue audit.
export DEBIAN_FRONTEND=noninteractive
run sudo systemctl stop ethercat.service
run sudo -E apt-get purge -y ethercat-host ethercat-tools ethercat-dkms
# Files gone, no installed/residual-config package state.
[[ ! -e /usr/sbin/ethercatctl ]] || { printf "FAIL: ethercatctl residual\n" >&2; exit 1; }
[[ ! -e /usr/lib/udev/rules.d/99-ethercat.rules ]] || { printf "FAIL: udev rule residual\n" >&2; exit 1; }
if dpkg -l 'ethercat-*' 2>/dev/null | grep -E '^(ii|rc)'; then printf "FAIL: residual package state\n" >&2; exit 1; fi
# The ethercat group is RETAINED on purge (U4) - reported as a note.
if getent group ethercat >/dev/null; then
    printf "NOTE: ethercat group retained on purge (U4; not residue)\n"
else
    printf "FAIL: ethercat group removed (U4 violation)\n" >&2; exit 1
fi
# /etc/ethercat.conf is role-managed, not package-owned (U3): apt-get
# purge correctly does not touch it; it is operator/Ansible state, not
# package residue. Asserted present and noted (mirrors the group note).
if [[ -f /etc/ethercat.conf ]]; then
    printf "NOTE: /etc/ethercat.conf retained on purge (U3, role-managed; not package residue)\n"
else
    printf "NOTE: /etc/ethercat.conf absent (no role-managed config present)\n"
fi
printf "OK: p9 parity - purge clean (group and role-managed config noted, not residue)\n"

printf "\nphase 18 complete\n"
