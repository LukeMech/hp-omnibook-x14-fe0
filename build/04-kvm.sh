#!/bin/bash
# KVM (opt-in, omnibook-kvm): slbounce, plus the plain kernel and the EL2 device tree
# for the "(KVM)" boot entries. Runs before 05-dtbloader.sh replaces vmlinuz: Fedora's
# dtbloader stub would swap the EL2 device tree for the normal one, so these entries
# boot kernel-core's own image instead.
set -ouex pipefail

KVER=$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core)

# systemd-boot + efibootmgr: the boot chain that loads slbounce before GRUB.
# dtc: fdtput/fdtget, for the device tree below.
dnf install -y /rpms/*/slbounce-*.rpm systemd-boot-unsigned efibootmgr dtc
ls -l /usr/lib/systemd/boot/efi/systemd-bootaa64.efi
install -Dm0644 "/usr/lib/modules/${KVER}/vmlinuz" /usr/lib/omnibook-kvm/vmlinuz

# The EL2 device tree: kernel-core's (upstream x1e80100-hp-omnibook-x14 + the x1-el2
# overlay), minus the ADSP/CDSP remoteproc iommus the overlay gained in 7.1 (commit
# 47c88db49f6c): on X1E laptops booted through slbounce they make the apps SMMU fault
# endlessly until a hard lockup. Reverted the same way in the aarch64-laptops trees.
DTB=/usr/lib/omnibook-kvm/kvm.dtb
install -m0644 "/usr/lib/modules/${KVER}/dtb/qcom/x1e80100-hp-omnibook-x14-el2.dtb" "${DTB}"
for node in /soc@0/remoteproc@6800000 /soc@0/remoteproc@32300000; do
    fdtget -t s "${DTB}" "${node}" compatible
    if fdtget "${DTB}" "${node}" iommus >/dev/null 2>&1; then
        fdtput -d "${DTB}" "${node}" iommus
    fi
done
# slbounce only switches with the zap shader disabled -- still true after the edit.
fdtget -t s "${DTB}" "$(fdtget -t s "${DTB}" /__symbols__ gpu 2>/dev/null || echo /soc@0/gpu@3d00000)/zap-shader" status |
    grep -qx disabled
