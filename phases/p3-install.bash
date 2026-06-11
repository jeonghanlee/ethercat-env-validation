#!/usr/bin/env bash
#
# Phase 3: prefix metadata install, upstream userspace install,
# command path and loader integration.
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

run sudo make -C "${REPO}" install
run sudo make -C "${REPO}" build.install
record ls -la /opt/ethercat
record ls -la /opt/ethercat/bin /opt/ethercat/sbin
record ls -la /opt/ethercat/etc
run make -C "${REPO}" command.audit
run sudo make -C "${REPO}" command.install
run make -C "${REPO}" command.audit
run make -C "${REPO}" loader.render
run sudo make -C "${REPO}" loader.install
run make -C "${REPO}" loader.audit
run /usr/bin/ethercat version

printf "\nphase 3 complete\n"
