#!/usr/bin/env bash
#
# Phase 7: RT host policy for real - RT kernel provision, limits,
# GRUB parameters, service policy, clock and tuned status.
# Runs inside the validation VM.

set -euo pipefail

readonly REPO="${HOME}/ethercat-env"

function run {
    printf "\n=== RUN: %s ===\n" "$*"
    "$@"
}

export DEBIAN_FRONTEND=noninteractive
run sudo -E make -C "${REPO}" rt.kernel.provision
run make -C "${REPO}" rt.kernel.select
run sudo make -C "${REPO}" rt.limits.install
run make -C "${REPO}" rt.limits.audit
run sudo make -C "${REPO}" rt.grub.apply
run make -C "${REPO}" rt.grub.audit
run sudo make -C "${REPO}" rt.service.apply
run make -C "${REPO}" rt.service.audit
run make -C "${REPO}" rt.clock.status
run make -C "${REPO}" rt.tuned.status
run make -C "${REPO}" rt.priority.show
run make -C "${REPO}" rt.latency.classify
run make -C "${REPO}" rt.status

printf "\nphase 7 complete\n"
