#!/usr/bin/env bash
#
# VM lifecycle driver for the ethercat-env R2-12 real-execution validation.
#
# Subcommands:
#   provision        Verify base image checksum, create ssh key, seed ISO, overlay disk
#   start            Boot the VM (KVM, daemonized, ssh forwarded to 127.0.0.1:10022)
#   wait-ssh         Block until ssh answers (timeout 300 s)
#   ssh CMD...       Run a command inside the VM
#   push SRC DST     Copy a file into the VM
#   run SCRIPT       Copy a phase script into the VM and execute it with bash
#   reboot           Reboot the VM and wait for ssh
#   stop             Power the VM off and wait for the process to exit
#   snapshot NAME    Copy the overlay disk (VM must be stopped)
#   restore NAME     Restore a named overlay copy (VM must be stopped)
#   status           Report VM process and ssh state

set -euo pipefail

TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TOP
readonly WORK="${TOP}/work"
readonly IMAGE="${WORK}/images/debian-13-genericcloud-amd64.qcow2"
readonly SUMS="${WORK}/images/SHA512SUMS"
readonly OVERLAY="${WORK}/vm-r2-12.qcow2"
readonly SEED_ISO="${WORK}/seed.iso"
readonly SSH_KEY="${WORK}/keys/id_ed25519"
readonly PID_FILE="${WORK}/vm.pid"
readonly SERIAL_LOG="${WORK}/serial.log"
readonly KNOWN_HOSTS="${WORK}/known_hosts"
readonly SSH_PORT="10022"
readonly SSH_USER="validator"
readonly MAC_ADMIN="52:54:00:12:ec:01"
readonly MAC_ECAT="52:54:00:12:ec:02"
readonly VM_MEM="8192"
readonly VM_SMP="4"
readonly OVERLAY_SIZE="40G"

function die {
    printf "ERROR: %s\n" "$*" >&2
    exit 1
}

function ssh_cmd {
    ssh -i "${SSH_KEY}" -p "${SSH_PORT}" -o StrictHostKeyChecking=no -o UserKnownHostsFile="${KNOWN_HOSTS}" -o ConnectTimeout=5 -o LogLevel=ERROR "${SSH_USER}@127.0.0.1" "$@"
}

function scp_cmd {
    scp -i "${SSH_KEY}" -P "${SSH_PORT}" -o StrictHostKeyChecking=no -o UserKnownHostsFile="${KNOWN_HOSTS}" -o LogLevel=ERROR "$@"
}

function vm_pid {
    local pid
    if [[ ! -s "${PID_FILE}" ]]; then
        return 1
    fi
    pid="$(<"${PID_FILE}")"
    if kill -0 "${pid}" 2>/dev/null; then
        printf "%s" "${pid}"
        return 0
    fi
    return 1
}

function cmd_provision {
    local pubkey
    [[ -s "${IMAGE}" ]] || die "base image missing: ${IMAGE}"
    [[ -s "${SUMS}" ]] || die "checksum file missing: ${SUMS}"
    (cd "${WORK}/images" && grep " debian-13-genericcloud-amd64.qcow2\$" SHA512SUMS | sha512sum --check -)
    mkdir -p "${WORK}/keys" "${WORK}/seed"
    if [[ ! -s "${SSH_KEY}" ]]; then
        ssh-keygen -t ed25519 -N "" -C "ethercat-vm-validator" -f "${SSH_KEY}"
    fi
    pubkey="$(<"${SSH_KEY}.pub")"
    sed "s|@SSH_PUBKEY@|${pubkey}|" "${TOP}/cloud-init/user-data.in" > "${WORK}/seed/user-data"
    cp "${TOP}/cloud-init/meta-data" "${WORK}/seed/meta-data"
    genisoimage -quiet -output "${SEED_ISO}" -volid cidata -joliet -rock "${WORK}/seed/user-data" "${WORK}/seed/meta-data"
    qemu-img create -f qcow2 -F qcow2 -b "${IMAGE}" "${OVERLAY}" "${OVERLAY_SIZE}"
    printf "provisioned: overlay=%s seed=%s\n" "${OVERLAY}" "${SEED_ISO}"
}

function cmd_start {
    if vm_pid >/dev/null; then
        die "VM already running"
    fi
    [[ -s "${OVERLAY}" ]] || die "overlay missing: run provision first"
    [[ -s "${SEED_ISO}" ]] || die "seed ISO missing: run provision first"
    qemu-system-x86_64 -name ethercat-vm-r2-12 \
        -machine q35,accel=kvm -cpu host -smp "${VM_SMP}" -m "${VM_MEM}" \
        -drive "file=${OVERLAY},if=virtio,format=qcow2" \
        -drive "file=${SEED_ISO},if=virtio,format=raw,readonly=on" \
        -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22" \
        -device "virtio-net-pci,netdev=net0,mac=${MAC_ADMIN}" \
        -netdev "user,id=net1,restrict=on" \
        -device "virtio-net-pci,netdev=net1,mac=${MAC_ECAT}" \
        -display none -daemonize -pidfile "${PID_FILE}" -serial "file:${SERIAL_LOG}"
    printf "VM started (pid %s)\n" "$(<"${PID_FILE}")"
}

function cmd_wait_ssh {
    local deadline
    deadline=$((SECONDS + 300))
    while (( SECONDS < deadline )); do
        if ssh_cmd true 2>/dev/null; then
            printf "ssh ready\n"
            return 0
        fi
        sleep 3
    done
    die "ssh not reachable within 300 s"
}

function cmd_run {
    local script="$1"
    local base
    [[ -s "${script}" ]] || die "phase script missing: ${script}"
    base="$(basename "${script}")"
    scp_cmd "${script}" "${SSH_USER}@127.0.0.1:/tmp/${base}"
    ssh_cmd "bash /tmp/${base}"
}

function cmd_reboot {
    ssh_cmd "sudo systemctl reboot" || true
    sleep 10
    cmd_wait_ssh
}

function cmd_stop {
    local pid
    local waited=0
    if ! pid="$(vm_pid)"; then
        printf "VM not running\n"
        return 0
    fi
    ssh_cmd "sudo systemctl poweroff" 2>/dev/null || true
    while kill -0 "${pid}" 2>/dev/null && (( waited < 90 )); do
        sleep 3
        waited=$((waited + 3))
    done
    if kill -0 "${pid}" 2>/dev/null; then
        printf "graceful poweroff timed out: killing pid %s\n" "${pid}"
        kill "${pid}"
    fi
    rm -f "${PID_FILE}"
    printf "VM stopped\n"
}

function cmd_snapshot {
    local name="$1"
    if vm_pid >/dev/null; then
        die "stop the VM before snapshot"
    fi
    cp --reflink=auto "${OVERLAY}" "${WORK}/snap-${name}.qcow2"
    printf "snapshot saved: %s\n" "${WORK}/snap-${name}.qcow2"
}

function cmd_restore {
    local name="$1"
    if vm_pid >/dev/null; then
        die "stop the VM before restore"
    fi
    [[ -s "${WORK}/snap-${name}.qcow2" ]] || die "snapshot missing: ${name}"
    cp --reflink=auto "${WORK}/snap-${name}.qcow2" "${OVERLAY}"
    printf "snapshot restored: %s\n" "${name}"
}

function cmd_status {
    local pid
    if pid="$(vm_pid)"; then
        printf "process: running (pid %s)\n" "${pid}"
    else
        printf "process: not running\n"
    fi
    if ssh_cmd true 2>/dev/null; then
        printf "ssh: reachable on 127.0.0.1:%s\n" "${SSH_PORT}"
    else
        printf "ssh: not reachable\n"
    fi
}

function main {
    local cmd="${1:-}"
    [[ -n "${cmd}" ]] || die "usage: vm.bash {provision|start|wait-ssh|ssh|push|run|reboot|stop|snapshot|restore|status}"
    shift || true
    case "${cmd}" in
        provision) cmd_provision ;;
        start)     cmd_start ;;
        wait-ssh)  cmd_wait_ssh ;;
        ssh)       ssh_cmd "$@" ;;
        push)      scp_cmd "$1" "${SSH_USER}@127.0.0.1:$2" ;;
        run)       cmd_run "$1" ;;
        reboot)    cmd_reboot ;;
        stop)      cmd_stop ;;
        snapshot)  cmd_snapshot "$1" ;;
        restore)   cmd_restore "$1" ;;
        status)    cmd_status ;;
        *)         die "unknown subcommand: ${cmd}" ;;
    esac
}

main "$@"
