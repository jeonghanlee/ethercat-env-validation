# ethercat-env VM Validation

VM real-execution validation environment for the
[ethercat-env](https://github.com/jeonghanlee/ethercat-env) repository.
A disposable Debian 13 VM executes the root-affecting work for real -
install, kernel module, systemd, udev, GRUB, service policy, removal -
and every phase records evidence under `evidence/`.

Two acceptance vehicles reach the same operational end-state:

- **Source-build vehicle** (`p1`-`p9`): build from the pinned upstream
  source under the `/opt/ethercat` prefix (the Revision 2 R2-12
  baseline).
- **Package/Ansible vehicle** (`p10`-`p18`): build the Debian package
  set and provision with the Ansible roles (the release-1.0.0 cycle).

A host uses one vehicle, not both - they collide on shared host state
(`/usr/bin/ethercat`, the `ethercat` group, the DKMS-installed modules).
Each vehicle therefore runs on its own fresh VM.

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
| `evidence/r2-12/` | Revision 2 R2-12 source-build evidence: `discovery/` (defect-finding) and `acceptance/` (authoritative) |
| `evidence/release-1.0.0/` | Release 1.0.0 cycle evidence per milestone (`m2`-`m9`), and the release-gate run (`m11/source`, `m11/package`) |
| `work/` | Images, overlay, seed ISO, keys, pidfile, run orchestrators (gitignored) |

## Execution Model

The repository under test enters the VM as a tarball of its working
tree (`git archive HEAD`, or `tar --exclude=.git`); the closure commit
in `ethercat-env` captures the validated content. Each phase is copied
into the VM and executed via ssh; the caller captures stdout and stderr
into one log per phase. Reboots are host-driven (a phase is one blocking
ssh session): after `p7` (source vehicle) and after `p17` (package
vehicle), into the RT kernel.

### Source-build vehicle

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

### Package/Ansible vehicle

| Phase | Scope |
| :--- | :--- |
| p10-packaging | Source package build, orig verify, `dpkg-buildpackage` (source + binary) |
| p11-dkms | `ethercat-dkms` install, cross-kernel vermagic |
| p12-tools | `ethercat-tools` command path, loader resolution, uninstall residue |
| p13-host | `ethercat-host`: sysusers group, udev rule, fail-closed config, purge |
| p14-rt-role | `rt_host` Ansible role: idempotent apply, check-mode, `rt.status` parity |
| p15-master-role | `ethercat_master` via `site.yml`: bound device, active service |
| p16-verify | `verify.all` umbrella with every lint/check member real (clean host) |
| p17-acceptance | Self-contained end-to-end: build, provision via `site.yml`, pre-reboot parity |
| p18-acceptance-post | Post-reboot parity and `apt purge` residue audit |

`p16` is the lint/check gate, run on a clean host (its `verify.residue`
member requires no residue). `p17`/`p18` are the self-contained
acceptance run and do not depend on `p10`-`p16`.

## Usage

One vehicle per fresh VM. Source-build vehicle:

```bash
scripts/vm.bash provision
scripts/vm.bash start
scripts/vm.bash wait-ssh
scripts/vm.bash push work/ethercat-env.tar.gz /tmp/ethercat-env.tar.gz
scripts/vm.bash run phases/p1-host-prepare.bash 2>&1 | tee evidence/release-1.0.0/m11/source/p1-host-prepare.log
```

Package/Ansible acceptance (separate fresh VM): run `p1` then `p17`,
reboot, then `p18`:

```bash
scripts/vm.bash run phases/p17-acceptance.bash 2>&1 | tee evidence/release-1.0.0/m11/package/p17-acceptance.log
scripts/vm.bash reboot
scripts/vm.bash run phases/p18-acceptance-post.bash 2>&1 | tee evidence/release-1.0.0/m11/package/p18-acceptance-post.log
```

## Related Repositories

| Repository | Role |
| :--- | :--- |
| [ethercat-env](https://github.com/jeonghanlee/ethercat-env) | Repository under test: Debian 13 EtherCAT master and RT host environment |

Milestone status and the findings absorbed from these validation runs
live in `docs/milestone.md` of the `ethercat-env` repository.
