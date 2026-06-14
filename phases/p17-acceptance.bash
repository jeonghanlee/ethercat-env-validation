#!/usr/bin/env bash
#
# Phase 17: package/Ansible acceptance, pre-reboot (release-1.0.0 cycle
# M9). Builds the packages, provisions a fresh VM via site.yml
# (rt_host + ethercat_master) through a local apt repo, and asserts the
# operational end-state at parity with the p3-p7 source-build path.
# The reboot is host-driven AFTER this phase; p18 asserts post-reboot.
# Runs inside the validation VM.

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
run sudo -E apt-get install -y debhelper dh-dkms ansible "linux-headers-$(uname -r)" dkms dpkg-dev pkgconf autoconf automake libtool

# Build the packages (p10 route) and expose them as a local apt repo.
run make -C "${REPO}" init
run make -C "${REPO}" pkg.orig
orig="$(ls "${REPO}"/packaging/ethercat_*.orig.tar.gz)"
ver="$(basename "${orig}" .orig.tar.gz)"; ver="${ver#ethercat_}"
run rm -rf "${BUILD}"; run mkdir -p "${BUILD}"
run cp "${orig}" "${BUILD}/"
run tar -xzf "${orig}" -C "${BUILD}"
run cp -a "${REPO}/debian" "${BUILD}/ethercat-${ver}/"
( cd "${BUILD}/ethercat-${ver}" && dpkg-buildpackage -us -uc )
( cd "${BUILD}" && dpkg-scanpackages -m . /dev/null > Packages 2>/dev/null )
echo "deb [trusted=yes] file:${BUILD} ./" | sudo tee /etc/apt/sources.list.d/local-ethercat.list >/dev/null
run sudo -E apt-get update

# Provision via the operator route: site.yml (rt_host + ethercat_master).
nic="$(ip -o link | awk -F': ' '{print $2}' | grep -v '^lo$' | sed -n 2p)"
[[ -n "${nic}" ]] || { printf "FAIL: no second NIC found\n" >&2; exit 1; }
printf "isolated NIC: %s\n" "${nic}"
cd "${ANSIBLE_DIR}"
run ansible-playbook playbooks/site.yml -e "ethercat_master_device=${nic}"

# --- Parity assertions (operational end-state vs p3-p7) ---
# p3: ethercat CLI on PATH, self-contained (libethercat1 NOT installed).
command -v ethercat >/dev/null || { printf "FAIL: ethercat CLI missing\n" >&2; exit 1; }
if dpkg -l libethercat1 2>/dev/null | grep -q '^ii'; then printf "FAIL: libethercat1 installed (no in-cycle consumer)\n" >&2; exit 1; fi
printf "OK: p3 parity - ethercat CLI on PATH, libethercat1 not installed\n"
# p4: modules loaded.
for m in ec_master ec_generic; do lsmod | grep -q "^${m}" || { printf "FAIL: %s not loaded\n" "${m}" >&2; exit 1; }; done
run dkms status ethercat
printf "OK: p4 parity - ec_master + ec_generic loaded, dkms installed\n"
# p5: runtime config bound.
grep -q "^MASTER0_DEVICE=\"${nic}\"" /etc/ethercat.conf || { printf "FAIL: MASTER0_DEVICE not bound\n" >&2; exit 1; }
printf "OK: p5 parity - /etc/ethercat.conf bound\n"
# p6: service active, device node group.
systemctl is-active --quiet ethercat.service || { printf "FAIL: service not active\n" >&2; exit 1; }
sudo udevadm settle
[[ "$(stat -c '%G' /dev/EtherCAT0)" == "ethercat" ]] || { printf "FAIL: /dev/EtherCAT0 group\n" >&2; exit 1; }
printf "OK: p6 parity - service active, /dev/EtherCAT0 group ethercat\n"
# p7: RT host state.
dpkg -l linux-image-rt-amd64 2>/dev/null | grep -q '^ii' || { printf "FAIL: RT kernel not installed\n" >&2; exit 1; }
getent group realtime >/dev/null || { printf "FAIL: realtime group missing\n" >&2; exit 1; }
grep -q 'intel_pstate=disable' /etc/default/grub || { printf "FAIL: GRUB RT param missing\n" >&2; exit 1; }
[[ "$(systemctl is-enabled irqbalance.service 2>/dev/null || true)" == "masked" ]] || { printf "FAIL: irqbalance not masked\n" >&2; exit 1; }
run make -C "${REPO}" rt.status
printf "OK: p7 parity - RT kernel, realtime group, GRUB param, irqbalance masked\n"

# Pre-reboot persistence preconditions (RV1-F5): unit enabled, dkms built.
[[ "$(systemctl is-enabled ethercat.service 2>/dev/null || true)" == "enabled" ]] || { printf "FAIL: ethercat.service not enabled\n" >&2; exit 1; }
printf "OK: ethercat.service enabled (post-reboot auto-start precondition)\n"

# Master reachable via the group (RV1-F6): add the validator to it.
run sudo usermod -aG ethercat "$(id -un)"
run sg ethercat -c "/usr/bin/ethercat master"

printf "\nphase 17 complete\n"
