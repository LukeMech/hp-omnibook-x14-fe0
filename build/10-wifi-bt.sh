#!/bin/bash
# WiFi + Bluetooth (WCN6855 / FastConnect 6900). The installer ISO runs this hook too
# (installer-hooks.txt), so the installer has network too.
set -ouex pipefail

# atheros-firmware: ath11k WCN6855 firmware and the HP Bluetooth firmware
# (qca/hpbtfw21.tlv, qca/hpnv21.*) -- Bluetooth needs nothing else.
dnf install -y atheros-firmware python3

# WiFi: linux-firmware's board-2.bin has no calibration for this card (105b:e108),
# so ath11k fails. Add it (see ath11k-omnibook-board.py); /usr/lib/firmware/updates
# takes precedence over the stock file, hw2.1 is where ath11k looks for this chip.
SRC=$(ls /usr/lib/firmware/ath11k/WCN6855/hw2.0/board-2.bin* | head -n1)
DST=/usr/lib/firmware/updates/ath11k/WCN6855
mkdir -p "${DST}/hw2.0" "${DST}/hw2.1"
python3 "$(dirname "$0")/ath11k-omnibook-board.py" "${SRC}" "${DST}/hw2.0/board-2.bin"
ln -sf ../hw2.0/board-2.bin "${DST}/hw2.1/board-2.bin"
