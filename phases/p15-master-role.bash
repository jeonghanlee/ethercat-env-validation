#!/usr/bin/env bash
#
# Phase 15: ethercat_master role end-to-end (release-1.0.0 cycle M7).
# Applies site.yml (rt_host + ethercat_master) via a local apt repo,
# then verifies a bound master device (F3), rendered UPDOWN (EC-8), an
# active service with the device module attached, idempotence, and a
# fail-closed empty-device negative. The site re-run re-asserts rt_host
# (M7.T3). First-class permanent M7 phase. Runs inside the validation VM.

set -euo pipefail

export PATH="/usr/sbin:/sbin:${PATH}"
readonly REPO="${HOME}/ethercat-env"
readonly ANSIBLE_DIR="${REPO}/ansible"
readonly BUILD="${HOME}/pkgbuild"

function run {
    printf "\n=== RUN: %s ===\n" "$*"
    "$@"
}

export DEBIAN_FRONTEND=noninteractive
run sudo -E apt-get install -y ansible "linux-headers-$(uname -r)" dkms dpkg-dev

# Local apt repo so the role's apt task resolves ethercat-host's Depends.
( cd "${BUILD}" && dpkg-scanpackages -m . /dev/null > Packages 2>/dev/null )
echo "deb [trusted=yes] file:${BUILD} ./" | sudo tee /etc/apt/sources.list.d/local-ethercat.list >/dev/null
run sudo -E apt-get update

# The isolated EtherCAT NIC (second virtio interface).
nic="$(ip -o link | awk -F': ' '{print $2}' | grep -v '^lo$' | sed -n 2p)"
[[ -n "${nic}" ]] || { printf "FAIL: no second NIC found\n" >&2; exit 1; }
printf "isolated NIC: %s\n" "${nic}"

cd "${ANSIBLE_DIR}"
export ANSIBLE_ROLES_PATH="${ANSIBLE_DIR}/roles"

# Apply the end-to-end deliverable (site.yml: rt_host + ethercat_master).
run ansible-playbook playbooks/site.yml -e "ethercat_master_device=${nic}"

# F3: a bound master device is rendered.
grep -q "^MASTER0_DEVICE=\"${nic}\"" /etc/ethercat.conf || { printf "FAIL: MASTER0_DEVICE not bound\n" >&2; exit 1; }
printf "OK: MASTER0_DEVICE bound to %s (F3)\n" "${nic}"
# EC-8: UPDOWN rendered.
grep -q "^UPDOWN_INTERFACES=\"${nic}\"" /etc/ethercat.conf || { printf "FAIL: UPDOWN_INTERFACES not rendered\n" >&2; exit 1; }
printf "OK: UPDOWN_INTERFACES rendered (EC-8)\n"

# Active service with the device node present and the generic module loaded.
systemctl is-active --quiet ethercat.service || { printf "FAIL: ethercat.service not active\n" >&2; exit 1; }
printf "OK: ethercat.service active\n"
[[ -e /dev/EtherCAT0 ]] || { printf "FAIL: /dev/EtherCAT0 missing\n" >&2; exit 1; }
if lsmod | grep -q '^ec_generic'; then
    printf "OK: ec_generic device module loaded (RV1-F1 class)\n"
else
    printf "FAIL: ec_generic not loaded - device driver skipped\n" >&2; lsmod | grep '^ec_' >&2; exit 1
fi

# Idempotence: a second site.yml apply reports zero changed (rt_host +
# ethercat_master, M7.T3 full re-run).
out="$(ansible-playbook playbooks/site.yml -e "ethercat_master_device=${nic}" 2>&1)"
printf "%s\n" "${out}" | tail -3
changed="$(printf "%s\n" "${out}" | sed -n 's/.*changed=\([0-9]*\).*/\1/p' | tail -1)"
if [[ "${changed}" != "0" ]]; then
    printf "FAIL: second site.yml apply not idempotent (changed=%s)\n" "${changed}" >&2; exit 1
fi
printf "OK: site.yml idempotent (rt_host + ethercat_master, M7.T3)\n"

# Fail-closed negative: empty device aborts the play before any /etc write.
if ansible-playbook playbooks/ethercat_master.yml -e "ethercat_master_device=" >/dev/null 2>&1; then
    printf "FAIL: empty device did not fail closed\n" >&2; exit 1
fi
printf "OK: empty device fails closed (F3 negative)\n"

printf "\nphase 15 complete\n"
