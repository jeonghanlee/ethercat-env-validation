# ethercat-env VM Validation

R2-12 real-execution validation environment for the
[ethercat-env](https://github.com/jeonghanlee/ethercat-env) repository.
A disposable Debian 13 VM executes the root-affecting target graph
(install, kernel module, systemd, udev, GRUB, service policy, removal)
for real, and every phase records evidence under `evidence/`.

## Architecture

| Component | Implementation |
| :--- | :--- |
| Hypervisor | `qemu-system-x86_64` with KVM acceleration, daemonized, no display |
| Guest image | Debian 13 genericcloud qcow2 (overlay disk, base image untouched) |
| Guest init | cloud-init NoCloud seed ISO (`cidata` volume) |
| Guest access | ssh key pair, user `validator` (NOPASSWD sudo), `127.0.0.1:10022` |
| Admin NIC | `net0` virtio, user-mode NAT, MAC `52:54:00:12:ec:01` |
| EtherCAT NIC | `net1` virtio, isolated (`restrict=on`), MAC `52:54:00:12:ec:02` |

The EtherCAT NIC carries no host traffic; it exists so the generic
driver can bind a dedicated interface and the master can start without
disturbing the ssh path.

## Layout

| Path | Role |
| :--- | :--- |
| `scripts/vm.bash` | VM lifecycle driver (provision, start, run, reboot, stop, snapshot) |
| `cloud-init/` | NoCloud seed sources (`user-data.in` is rendered with the generated public key) |
| `phases/` | Phase scripts executed inside the VM in dependency order |
| `evidence/r2-12/` | Captured phase logs: `discovery/` (defect-finding run) and `acceptance/` (clean rerun, authoritative) |
| `work/` | Images, overlay, seed ISO, keys, pidfile (gitignored) |

## Execution Model

The repository under test enters the VM as a tarball of its working
tree (`tar --exclude=.git`); the closure commit in `ethercat-env`
captures the validated content. Each phase is copied into the VM and
executed via ssh; the driver captures stdout and stderr into one log
per phase.

| Phase | Scope |
| :--- | :--- |
| p1-host-prepare | OS evidence, build dependencies, repository unpack, `doctor` |
| p2-build | `init`, `src.verify`, `build.baseline`, module artifacts, `verify.all` |
| p3-install | `install`, `build.install`, command path, loader integration |
| p4-dkms | `dkms.conf`, `add.dkms`, `install.dkms`, module load and unload |
| p5-runtime | Master interface selection, `runtime.generate`, `runtime.lint` |
| p6-systemd-udev | Unit and rule install, enable, start, master state, `runtime.status` |
| p7-rt | RT kernel provision, limits, GRUB apply, service policy, `rt.status` |
| p8-post-reboot | Post-reboot kernel, `rt.status`, service persistence, DKMS state |
| p9-removal | `remove.dryrun`, uninstall, RT revert, purge, residue audit |

## Usage

```bash
scripts/vm.bash provision
scripts/vm.bash start
scripts/vm.bash wait-ssh
scripts/vm.bash push work/ethercat-env.tar.gz /tmp/ethercat-env.tar.gz
scripts/vm.bash run phases/p1-host-prepare.bash
scripts/vm.bash reboot
scripts/vm.bash stop
```

Phase output is captured by the caller, for example:

```bash
scripts/vm.bash run phases/p2-build.bash 2>&1 | tee evidence/r2-12/acceptance/p2-build.log
```

## Related Repositories

| Repository | Role |
| :--- | :--- |
| [ethercat-env](https://github.com/jeonghanlee/ethercat-env) | Repository under test: Debian 13 EtherCAT master and RT host environment |

Milestone status and the R2-12 findings absorbed from this validation run
live in `docs/milestone.md` of the `ethercat-env` repository.
