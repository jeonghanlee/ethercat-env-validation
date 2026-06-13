#!/usr/bin/env bash
#
# Phase 11: ethercat-dkms package install and cross-kernel vermagic
# (release-1.0.0 cycle M3, F4 regression). Permanent regression check
# (M3.T2). Requires p10 artifacts in ${HOME}/pkgbuild. Runs inside the
# validation VM.

set -euo pipefail

# dkms and modinfo live in sbin, which the non-root validator PATH lacks.
export PATH="/usr/sbin:/sbin:${PATH}"

readonly BUILD="${HOME}/pkgbuild"

function run {
    printf "\n=== RUN: %s ===\n" "$*"
    "$@"
}

function assert_modules {
    # assert_modules KERNELVER - per-module presence, vermagic, and
    # exactly-the-generic-set negative check at the dkms INSTALL
    # location for one kernel (dkms 3 moves modules out of the tree
    # into /lib/modules/<kver>/updates/dkms, xz-compressed).
    local kver="$1" mdir m ko vm count
    mdir="/lib/modules/${kver}/updates/dkms"
    for m in ec_master ec_generic; do
        ko="$(ls "${mdir}/${m}".ko* 2>/dev/null | head -1 || true)"
        if [[ -z "${ko}" ]]; then
            printf "FAIL: missing %s.ko* under %s\n" "${m}" "${mdir}" >&2; exit 1
        fi
        vm="$(modinfo -F vermagic "${ko}" | awk '{print $1}')"
        if [[ "${vm}" != "${kver}" ]]; then
            printf "FAIL: %s vermagic %s does not match %s\n" "${m}" "${vm}" "${kver}" >&2; exit 1
        fi
        printf "OK: %s vermagic matches %s\n" "${m}" "${kver}"
    done
    count="$(find "${mdir}" -name "ec_*.ko*" | wc -l)"
    if [[ "${count}" -ne 2 ]]; then
        printf "FAIL: expected exactly 2 ec_* modules (generic set), found %s\n" "${count}" >&2
        find "${mdir}" -name "ec_*.ko*" >&2; exit 1
    fi
    printf "OK: exactly the generic module set on %s\n" "${kver}"
}

export DEBIAN_FRONTEND=noninteractive
running="$(uname -r)"

run sudo -E apt-get install -y "linux-headers-${running}" dkms

deb="$(ls "${BUILD}"/ethercat-dkms_*_all.deb)"
ver="$(basename "${deb}")"; ver="${ver#ethercat-dkms_}"; ver="${ver%-1_all.deb}"
printf "package: %s  module version: %s\n" "${deb}" "${ver}"

run sudo -E apt-get install -y "${deb}"
run dkms status ethercat
assert_modules "${running}"

# Second, non-running kernel: RT (R2-12 precedent). The kernel postinst
# dkms hook may already build for it; already-built is a pass.
run sudo -E apt-get install -y linux-image-rt-amd64 linux-headers-rt-amd64
rt="$(ls /lib/modules | grep -- -rt-amd64 | head -1 || true)"
if [[ -z "${rt}" || "${rt}" == "${running}" ]]; then
    printf "FAIL: no non-running RT kernel found\n" >&2; exit 1
fi
printf "target kernel: %s (running: %s)\n" "${rt}" "${running}"

if ! dkms status "ethercat/${ver}" -k "${rt}" | grep -Eq "built|installed"; then
    run sudo dkms build "ethercat/${ver}" -k "${rt}"
fi
if ! dkms status "ethercat/${ver}" -k "${rt}" | grep -q "installed"; then
    run sudo dkms install "ethercat/${ver}" -k "${rt}"
fi
run dkms status ethercat
assert_modules "${rt}"

printf "\nphase 11 complete\n"
