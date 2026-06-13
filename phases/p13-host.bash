#!/usr/bin/env bash
#
# Phase 13: host integration package (release-1.0.0 cycle M5). Installs
# ethercat-host (resolving Depends ethercat-dkms, ethercat-tools,
# libethercat1), then verifies F2 (group via sysusers before udev rule;
# device-node group ownership), F3 (fail-closed without config; bound
# master with config), EC-8 (UPDOWN interface up at service start), and
# F5 (purge retains the group, audited as a note). Requires p10
# artifacts in ${HOME}/pkgbuild. Runs inside the validation VM.

set -euo pipefail

export PATH="/usr/sbin:/sbin:${PATH}"
readonly BUILD="${HOME}/pkgbuild"
readonly ECAT_NIC="enp0s3"   # placeholder; resolved below to the isolated NIC

function run {
    printf "\n=== RUN: %s ===\n" "$*"
    "$@"
}

export DEBIAN_FRONTEND=noninteractive

# Resolve the isolated EtherCAT NIC (the second virtio NIC, MAC 52:54:00:12:ec:02).
nic="$(ip -o link | awk -F': ' '{print $2}' | grep -v '^lo$' | sed -n 2p)"
[[ -n "${nic}" ]] || { printf "FAIL: no second NIC found\n" >&2; exit 1; }
printf "isolated NIC: %s\n" "${nic}"

# Build a local apt repo from the .deb set so apt resolves ethercat-host's
# declared Depends (ethercat-dkms, ethercat-tools, libethercat1) itself -
# installing ethercat-host alone proves the dependency graph, not a manual
# four-package install.
run sudo -E apt-get install -y "linux-headers-$(uname -r)" dkms dpkg-dev
( cd "${BUILD}" && dpkg-scanpackages -m . /dev/null > Packages 2>/dev/null )
echo "deb [trusted=yes] file:${BUILD} ./" | sudo tee /etc/apt/sources.list.d/local-ethercat.list >/dev/null
run sudo -E apt-get update
run sudo -E apt-get install -y ethercat-host

# Assert apt pulled the declared dependencies (not installed by hand).
# libethercat1 is intentionally NOT pulled: nothing in the host stack
# links it (the ethercat CLI is self-contained); it is the standalone
# library for external application authors (M4 finding).
for p in ethercat-dkms ethercat-tools; do
    dpkg -l "${p}" 2>/dev/null | grep -q '^ii' || { printf "FAIL: dependency %s not pulled by apt\n" "${p}" >&2; exit 1; }
done
if dpkg -l libethercat1 2>/dev/null | grep -q '^ii'; then
    printf "FAIL: libethercat1 pulled but has no host-stack consumer\n" >&2; exit 1
fi
printf "OK: apt resolved ethercat-host Depends (ethercat-dkms, ethercat-tools); libethercat1 correctly not pulled\n"

# F2 structural: the group exists (sysusers) and the udev rule is in place.
if ! getent group ethercat >/dev/null; then printf "FAIL: ethercat group missing\n" >&2; exit 1; fi
printf "OK: ethercat group present (sysusers)\n"
if [[ ! -f /usr/lib/udev/rules.d/99-ethercat.rules ]]; then printf "FAIL: udev rule missing\n" >&2; exit 1; fi
printf "OK: udev rule installed\n"

# Unit enabled, not started.
run systemctl is-enabled ethercat.service
if systemctl is-active --quiet ethercat.service; then printf "FAIL: unit started on install\n" >&2; exit 1; fi
printf "OK: unit enabled, not started\n"

# F3 fail-closed: no /etc/ethercat.conf -> start fails, no master.
if [[ -e /etc/ethercat.conf ]]; then printf "FAIL: package shipped /etc/ethercat.conf\n" >&2; exit 1; fi
printf "OK: no /etc/ethercat.conf shipped\n"
if sudo systemctl start ethercat.service 2>/dev/null; then
    printf "FAIL: service started without a config\n" >&2; exit 1
fi
printf "OK: service fails closed without a config\n"

# Provide a config bound to the isolated NIC with UPDOWN, then start.
sudo cp /usr/share/doc/ethercat-host/examples/ethercat.conf /etc/ethercat.conf
sudo sed -i "s|^MASTER0_DEVICE=.*|MASTER0_DEVICE=\"${nic}\"|" /etc/ethercat.conf
if grep -q '^UPDOWN_INTERFACES=' /etc/ethercat.conf; then
    sudo sed -i "s|^UPDOWN_INTERFACES=.*|UPDOWN_INTERFACES=\"${nic}\"|" /etc/ethercat.conf
else
    echo "UPDOWN_INTERFACES=\"${nic}\"" | sudo tee -a /etc/ethercat.conf >/dev/null
fi
run sudo systemctl start ethercat.service

# F2 device-node: /dev/EtherCAT0 owned by group ethercat. The kernel
# creates the devtmpfs node root:root immediately; udev applies the
# GROUP rule asynchronously on the add uevent, so settle before
# checking (this is a test-side race, not a packaging defect).
[[ -e /dev/EtherCAT0 ]] || { printf "FAIL: /dev/EtherCAT0 not created\n" >&2; exit 1; }
sudo udevadm settle
g=""
for _ in 1 2 3 4 5; do
    g="$(stat -c '%G' /dev/EtherCAT0)"
    [[ "${g}" == "ethercat" ]] && break
    sleep 1
done
[[ "${g}" == "ethercat" ]] || { printf "FAIL: /dev/EtherCAT0 group %s != ethercat\n" "${g}" >&2; exit 1; }
printf "OK: /dev/EtherCAT0 group ethercat (F2)\n"

# EC-8: the UPDOWN interface is up after service start.
state="$(cat /sys/class/net/${nic}/operstate 2>/dev/null || echo unknown)"
if ip link show "${nic}" | grep -q "state UP\|,UP\|UP,"; then
    printf "OK: UPDOWN interface %s is up (EC-8, operstate=%s)\n" "${nic}" "${state}"
else
    printf "FAIL: UPDOWN interface %s not up (operstate=%s)\n" "${nic}" "${state}" >&2; exit 1
fi

# M5.T3: dependents still intact after the host maintainer scripts.
run dkms status ethercat
command -v ethercat >/dev/null || { printf "FAIL: ethercat CLI gone\n" >&2; exit 1; }
printf "OK: M5.T3 - dkms and tools install state intact\n"

# F5: purge ethercat-host; group RETAINED, rule and unit gone.
run sudo systemctl stop ethercat.service
run sudo -E apt-get purge -y ethercat-host
if ! getent group ethercat >/dev/null; then printf "FAIL: group removed on purge (U4 violation)\n" >&2; exit 1; fi
printf "OK: ethercat group retained on purge (F5 note, not residue)\n"
[[ ! -f /usr/lib/udev/rules.d/99-ethercat.rules ]] || { printf "FAIL: udev rule residual\n" >&2; exit 1; }
[[ ! -f /usr/sbin/ethercatctl ]] || { printf "FAIL: ethercatctl residual\n" >&2; exit 1; }
printf "OK: package files removed on purge\n"

printf "\nphase 13 complete\n"
