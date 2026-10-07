#!/bin/bash
# GPU and sound. Both also need the GPU zap shader / ADSP firmware from HP's softpaq
# (omnibook-adsp-firmware), fetched on first boot.
set -ouex pipefail

# qcom-firmware: Adreno X1-85 firmware (gen70500_*) and the X1E audio topologies.
# The audio stack isn't pulled in by GNOME without weak deps; pipewire-pulseaudio is
# what GNOME's volume control talks to, alsa-ucm maps this laptop's card (it knows
# "HP Omnibook X"); alsa-utils (amixer, arecord...) for checking this young sound
# support on the laptop itself.
dnf install -y \
    qcom-firmware \
    mesa-dri-drivers \
    pipewire \
    pipewire-alsa \
    pipewire-pulseaudio \
    wireplumber \
    alsa-ucm \
    alsa-utils

# Audio topology: the kernel loads qcom/x1e80100/<sound card model>-tplg.bin, i.e.
# X1E80100-HP-OMNIBOOK-X14-tplg.bin. qcom-firmware ships it (a link to the ThinkPad
# T14s' one -- audioreach-topology builds both from the same source); make sure.
ls -l /usr/lib/firmware/qcom/x1e80100/X1E80100-HP-OMNIBOOK-X14-tplg.bin*

# Internal microphones: alsa-ucm gives this laptop the T14s' profile, but its device tree
# powers the wrong mic bias, so the mics capture silence. HP-Omnibook-X14-MicBias.conf
# (in system_files) works around it; hook it into the profile's "Mic" device. Fails the
# build if alsa-ucm's file changes shape.
UCM=/usr/share/alsa/ucm2/Qualcomm/x1e80100
grep -q 'HP.\*Omnibook X' "${UCM}/x1e80100.conf"
grep -q 'Include.vadm1d.File' "${UCM}/T14s-HiFi.conf"
sed -i '/Include.vadm1d.File/a\	Include.hpmicb.File "/Qualcomm/x1e80100/HP-Omnibook-X14-MicBias.conf"' \
    "${UCM}/T14s-HiFi.conf"
grep -q 'HP-Omnibook-X14-MicBias.conf' "${UCM}/T14s-HiFi.conf"
