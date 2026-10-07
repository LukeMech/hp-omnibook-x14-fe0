#!/bin/bash
# Battery: reported by the ADSP (pmic_glink), whose firmware is HP's and can't be
# shipped -- omnibook-adsp-firmware.service fetches it on first boot (needs 7-Zip).
set -ouex pipefail

dnf install -y 7zip
systemctl enable omnibook-adsp.service omnibook-adsp-firmware.service NetworkManager-dispatcher.service
