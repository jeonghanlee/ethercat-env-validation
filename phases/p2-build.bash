#!/usr/bin/env bash
#
# Phase 2: source acquisition, pinned-revision verification, real build,
# kernel module artifacts, repository-local verification harness.
# Runs inside the validation VM.

set -euo pipefail

readonly REPO="${HOME}/ethercat-env"

function run {
    printf "\n=== RUN: %s ===\n" "$*"
    "$@"
}

run make -C "${REPO}" init
run make -C "${REPO}" src.revision
run make -C "${REPO}" src.verify
run make -C "${REPO}" patch.status
run make -C "${REPO}" build.baseline
run find "${REPO}" -name "*.ko" -type f
run make -C "${REPO}" verify.all

printf "\nphase 2 complete\n"
