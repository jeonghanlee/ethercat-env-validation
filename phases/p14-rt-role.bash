#!/usr/bin/env bash
#
# Phase 14: rt_host Ansible role (release-1.0.0 cycle M6). Lints the
# role, predicts with --check, applies, asserts idempotence (zero
# changed on re-run), confirms the GRUB boot default is unchanged (D2),
# and checks outcomes against `make rt.status`. First Ansible-
# provisioning phase (M9.T4 class). Runs inside the validation VM.

set -euo pipefail

export PATH="/usr/sbin:/sbin:${PATH}"
readonly REPO="${HOME}/ethercat-env"
readonly ANSIBLE_DIR="${REPO}/ansible"

function run {
    printf "\n=== RUN: %s ===\n" "$*"
    "$@"
}

export DEBIAN_FRONTEND=noninteractive
run sudo -E apt-get install -y ansible ansible-lint

cd "${ANSIBLE_DIR}"

# M6.T2: ansible-lint (profile basic) clean.
run ansible-lint playbooks/rt_host.yml

# D2 evidence: capture the GRUB default before the apply.
grub_default_before="$(grep -E '^GRUB_DEFAULT=' /etc/default/grub || echo 'GRUB_DEFAULT=unset')"
printf "GRUB_DEFAULT before: %s\n" "${grub_default_before}"

# Check-mode predicts the apply (must report changed > 0 on a clean host).
run ansible-playbook playbooks/rt_host.yml --check --diff
printf "OK: check-mode ran (prediction)\n"

# Apply for real.
run ansible-playbook playbooks/rt_host.yml

# Idempotence: a second apply must report zero changed.
out="$(ansible-playbook playbooks/rt_host.yml 2>&1)"
printf "%s\n" "${out}" | tail -3
changed="$(printf "%s\n" "${out}" | sed -n 's/.*changed=\([0-9]*\).*/\1/p' | tail -1)"
if [[ "${changed}" != "0" ]]; then
    printf "FAIL: second apply not idempotent (changed=%s)\n" "${changed}" >&2; exit 1
fi
printf "OK: idempotent second apply (changed=0)\n"

# D2: the GRUB boot default is unchanged by the role.
grub_default_after="$(grep -E '^GRUB_DEFAULT=' /etc/default/grub || echo 'GRUB_DEFAULT=unset')"
printf "GRUB_DEFAULT after: %s\n" "${grub_default_after}"
[[ "${grub_default_before}" == "${grub_default_after}" ]] || { printf "FAIL: role changed GRUB_DEFAULT (D2)\n" >&2; exit 1; }
printf "OK: GRUB_DEFAULT unchanged (D2)\n"

# Outcome parity against rt.status expectations.
getent group realtime >/dev/null || { printf "FAIL: realtime group missing\n" >&2; exit 1; }
printf "OK: realtime group present\n"
[[ -f /etc/security/limits.d/99-realtime.conf ]] || { printf "FAIL: limits file missing\n" >&2; exit 1; }
grep -q '@realtime' /etc/security/limits.d/99-realtime.conf || { printf "FAIL: limits content wrong\n" >&2; exit 1; }
printf "OK: realtime limits installed\n"
grep -q 'intel_pstate=disable' /etc/default/grub || { printf "FAIL: GRUB RT param missing\n" >&2; exit 1; }
printf "OK: GRUB RT parameter applied\n"
[[ -f /etc/default/grub.ethercat-rt.bak ]] || { printf "FAIL: GRUB backup missing (RT-4)\n" >&2; exit 1; }
printf "OK: GRUB backup present\n"
# systemctl is-enabled prints "masked" but exits non-zero for a masked
# unit; capture the string (|| true) so set -o pipefail does not read the
# exit code as a failure.
irq_state="$(systemctl is-enabled irqbalance.service 2>/dev/null || true)"
if [[ "${irq_state}" == "masked" ]]; then
    printf "OK: irqbalance.service masked\n"
else
    printf "FAIL: irqbalance.service not masked (state=%s)\n" "${irq_state}" >&2; exit 1
fi

# rt.status oracle (RT-2, RT-8 coverage): runs read-only, must succeed.
run make -C "${REPO}" rt.status

printf "\nphase 14 complete\n"
