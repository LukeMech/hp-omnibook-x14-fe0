#!/usr/bin/python3
"""Add the HP OmniBook X 14 WiFi card to ath11k's board-2.bin.

The OmniBook's WCN6855 (FastConnect 6900, PCI subsystem 105b:e108, board id 0xff) has no
entry in linux-firmware's board-2.bin, so ath11k fails to load board data and WiFi never
comes up. This does what Jens Glathe's board file does (submitted to the ath11k list in
Dec 2024, never merged; https://bugs.launchpad.net/ubuntu-concept/+bug/2084960): reuse
the HP_G8_Lancia14 calibration and the regdb of the other HP WCN6855 cards, which users
report working at full speed. Everything here comes from linux-firmware itself, so the
result can ship in the image.

Format: drivers/net/wireless/ath/ath11k/hw.h (struct ath11k_fw_ie).

Usage: ath11k-omnibook-board.py IN_BOARD_2_BIN OUT_BOARD_2_BIN
  IN may be plain, .xz or .zst (Fedora ships compressed firmware).
"""

import lzma
import shutil
import struct
import subprocess
import sys

MAGIC = b"QCA-ATH11K-BOARD\0"
IE_BOARD = 0
IE_REGDB = 1
SUB_IE_NAME = 0
SUB_IE_DATA = 1

BASE = "bus=pci,vendor=17cb,device=1103"
OMNIBOOK = BASE + ",subsystem-vendor=105b,subsystem-device=e108,qmi-chip-id={chip},qmi-board-id=255"
# Same source entries as the Launchpad/ath11k-list board file (HP card 105b:e0c4).
DONOR = BASE + ",subsystem-vendor=105b,subsystem-device=e0c4,qmi-chip-id={chip},qmi-board-id=255"
CALIBRATION = DONOR + ",variant=HP_G8_Lancia14"
REGDB_SOURCE = DONOR.format(chip=2)
CHIP_IDS = (2, 18)


def read(path: str) -> bytes:
    if path.endswith(".xz"):
        with lzma.open(path) as f:
            return f.read()
    if path.endswith(".zst"):
        zstd = shutil.which("zstd") or sys.exit("zstd is needed to read " + path)
        return subprocess.run([zstd, "-dc", path], check=True, capture_output=True).stdout
    with open(path, "rb") as f:
        return f.read()


def align(n: int) -> int:
    return (n + 3) & ~3


def parse(blob: bytes) -> list[tuple[int, list[str], bytes]]:
    if not blob.startswith(MAGIC):
        sys.exit("not an ath11k board-2.bin")
    entries = []
    off = align(len(MAGIC))
    while off + 8 <= len(blob):
        ie_id, length = struct.unpack_from("<II", blob, off)
        body = blob[off + 8 : off + 8 + length]
        off += 8 + align(length)
        names, data, o = [], b"", 0
        while o + 8 <= len(body):
            sub_id, sub_len = struct.unpack_from("<II", body, o)
            value = body[o + 8 : o + 8 + sub_len]
            o += 8 + align(sub_len)
            if sub_id == SUB_IE_NAME:
                names.append(value.decode())
            elif sub_id == SUB_IE_DATA:
                data = value
        entries.append((ie_id, names, data))
    return entries


def ie(ie_id: int, data: bytes) -> bytes:
    return struct.pack("<II", ie_id, len(data)) + data + b"\0" * (align(len(data)) - len(data))


def container(ie_id: int, names: list[str], data: bytes) -> bytes:
    body = b"".join(ie(SUB_IE_NAME, n.encode()) for n in names) + ie(SUB_IE_DATA, data)
    return ie(ie_id, body)


def find(entries, ie_id: int, predicate) -> bytes:
    for entry_ie, names, data in entries:
        if entry_ie == ie_id and any(predicate(n) for n in names):
            return data
    sys.exit("no matching entry in upstream board-2.bin")


def main() -> None:
    src, dst = sys.argv[1:3]
    blob = read(src)
    entries = parse(blob)

    if any(OMNIBOOK.format(chip=2) in n for _, names, _ in entries for n in names):
        print("upstream board-2.bin already knows the OmniBook, copying unchanged")
        extra = b""
    else:
        extra = b""
        for chip in CHIP_IDS:
            calibration = find(
                entries, IE_BOARD,
                lambda n, chip=chip: n == CALIBRATION.format(chip=chip),
            )
            extra += container(IE_BOARD, [OMNIBOOK.format(chip=chip)], calibration)
        regdb = find(entries, IE_REGDB, lambda n: n == REGDB_SOURCE)
        extra += container(IE_REGDB, [OMNIBOOK.format(chip=chip) for chip in CHIP_IDS], regdb)

    # Upstream entries are kept, so the file still works for every other WCN6855 card.
    with open(dst, "wb") as f:
        f.write(blob + extra)


if __name__ == "__main__":
    main()
