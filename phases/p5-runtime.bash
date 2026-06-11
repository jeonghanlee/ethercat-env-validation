#!/usr/bin/env bash
#
# Phase 5: master interface selection on the dedicated EtherCAT NIC,
# runtime configuration generation and lint.
# Runs inside the validation VM.

set -euo pipefail

readonly REPO="${HOME}/ethercat-env"
readonly ECAT_MAC="52:54:00:12:ec:02"

function run {
    printf "\n=== RUN: %s ===\n" "$*"
    "$@"
}

iface="$(ip -o link | grep -i "${ECAT_MAC}" | awk -F': ' '{print $2}')"
[[ -n "${iface}" ]] || { printf "ERROR: no interface with MAC %s\n" "${ECAT_MAC}" >&2; exit 1; }
printf "selected EtherCAT interface: %s\n" "${iface}"

printf 'ETHERCAT_MASTER0="%s"\n' "${iface}" > "${REPO}/ethercatmaster.local"
run cat "${REPO}/ethercatmaster.local"

run make -C "${REPO}" runtime.generate
run make -C "${REPO}" runtime.lint
run make -C "${REPO}" runtime.config.show
run make -C "${REPO}" iface.status

printf "\nphase 5 complete\n"
