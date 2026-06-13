#!/usr/bin/env bash
#
# Phase 12: userspace tools packages (release-1.0.0 cycle M4). Installs
# libethercat1, libethercat-dev, ethercat-tools from the p10 build;
# asserts command-on-PATH, loader resolution, dev pkg-config, and
# no-residue after purge. Requires p10 artifacts in ${HOME}/pkgbuild.
# Runs inside the validation VM.

set -euo pipefail

export PATH="/usr/sbin:/sbin:${PATH}"
readonly BUILD="${HOME}/pkgbuild"

function run {
    printf "\n=== RUN: %s ===\n" "$*"
    "$@"
}

export DEBIAN_FRONTEND=noninteractive
run sudo -E apt-get install -y pkgconf

lib="$(ls "${BUILD}"/libethercat1_*_*.deb)"
dev="$(ls "${BUILD}"/libethercat-dev_*_*.deb)"
tools="$(ls "${BUILD}"/ethercat-tools_*_*.deb)"
printf "packages:\n  %s\n  %s\n  %s\n" "${lib}" "${dev}" "${tools}"

run sudo -E apt-get install -y "${lib}" "${dev}" "${tools}"

# Command resolves on PATH and runs without a master (device-safe).
run command -v ethercat
out="$(ethercat version 2>err.txt)"; rc=$?
printf "ethercat version -> rc=%s out=%s\n" "${rc}" "${out}"
if [[ "${rc}" -ne 0 ]]; then printf "FAIL: ethercat version exit %s\n" "${rc}" >&2; cat err.txt >&2; exit 1; fi
if grep -qi "Failed to open master" err.txt; then printf "FAIL: ethercat version touched the master\n" >&2; exit 1; fi
printf "OK: ethercat version exit 0, no master access\n"

# Loader resolves the runtime library.
if ! ldconfig -p | grep -q "libethercat.so.1"; then
    printf "FAIL: libethercat.so.1 not in ldconfig cache\n" >&2; exit 1
fi
printf "OK: ldconfig resolves libethercat.so.1\n"

# Dev package: pkg-config resolves.
run pkg-config --modversion libethercat

# Record claimed paths for the residue check, then purge.
paths="/usr/bin/ethercat $(ls /usr/lib/*/libethercat.so.1* 2>/dev/null) $(ls /usr/include/ecrt.h 2>/dev/null)"
run sudo -E apt-get purge -y libethercat-dev ethercat-tools libethercat1

# No residue: known files gone, no ii/rc state, loader cache clean.
rc=0
for p in ${paths}; do
    if [[ -e "${p}" ]]; then printf "FAIL: residual file %s\n" "${p}" >&2; rc=1; fi
done
if dpkg -l 'libethercat*' 'ethercat-tools' 2>/dev/null | grep -E '^(ii|rc)'; then
    printf "FAIL: residual package state\n" >&2; rc=1
fi
if ldconfig -p | grep -q "libethercat.so.1"; then
    printf "FAIL: libethercat.so.1 still in ldconfig cache after purge\n" >&2; rc=1
fi
if [[ "${rc}" -ne 0 ]]; then exit 1; fi
printf "OK: no residue after purge\n"

printf "\nphase 12 complete\n"
