# Provenance: dkms-builddir-smoketest.log

Collected on the discovery VM (post-p9 state, RT kernel running) immediately
after the `abs_builddir` override fix, before the final fresh-VM acceptance
run. It proves the fixed `dkms.conf` builds matching-vermagic modules for
both the running RT kernel and the non-running cloud kernel.

It is discovery-stage evidence: the authoritative acceptance proof of the
cross-kernel DKMS path is `acceptance/p7-rt.log` (autoinstall for the rt
kernel while running the cloud kernel) combined with `acceptance/p8-post-reboot.log`
(module load and service start on the rt kernel after reboot).
