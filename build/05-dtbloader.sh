#!/bin/bash
# Boot with the right device tree. This laptop has no usable ACPI for Linux: without its
# DTB the screen stays black. Fedora's answer is kernel-uki-dtbloader -- the same kernel
# with systemd-stub, its DTBs and a hardware-ID table (stubble, which knows the OmniBook
# X14) picking the right one at boot; it's what the official live ISO boots. It conflicts
# with kernel-core as a package and bootc/ostree only boot /usr/lib/modules/<kver>/vmlinuz,
# so take its Fedora-signed image (Secure Boot keeps working) and put it there.
# The installer ISO runs this hook too (installer-hooks.txt), so it boots the same way.
set -ouex pipefail

KVER=$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core)
NVR=$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' kernel-core)
WORK=$(mktemp -d)

dnf install -y cpio
# The repos only keep the newest kernel; Koji has every build.
dnf download --destdir "${WORK}" "kernel-uki-dtbloader-${NVR}" ||
    curl -fL --retry 3 -o "${WORK}/kernel-uki-dtbloader-${KVER}.rpm" \
        "https://kojipkgs.fedoraproject.org/packages/kernel/${NVR%-*}/${NVR##*-}/aarch64/kernel-uki-dtbloader-${KVER}.rpm"

(cd "${WORK}" && rpm2cpio kernel-uki-dtbloader-*.rpm | cpio -idm "./lib/modules/${KVER}/vmlinuz-dtbloader.efi")
install -m0755 "${WORK}/lib/modules/${KVER}/vmlinuz-dtbloader.efi" "/usr/lib/modules/${KVER}/vmlinuz"
rm -rf "${WORK}"
