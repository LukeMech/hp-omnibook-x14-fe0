# HP OmniBook X 14-fe0 on Linux

Notes, files and procedures for running Linux on the **HP OmniBook X 14-fe0** (Snapdragon X Elite X1E-78-100), collected while building [lm-desktop-config](https://github.com/LukeMech/lm-desktop-config): a Fedora 44 bootc GNOME image whose `hp` variant carried everything below. That project is archived; this repo keeps the fixes so they can be reused with any distribution.

Tested with Fedora 44, kernel 7.2.8, in October 2026.

| | |
|---|---|
| SoC | Qualcomm Snapdragon X Elite X1E-78-100 (`x1e80100`, "hamoa") |
| Device tree | `qcom/x1e80100-hp-omnibook-x14.dtb` (upstream since Linux 6.14), `-el2.dtb` for EL2 |
| HP platform IDs | `0x8CBE`, `0x8CCF`; same platform as the HP EliteBook Ultra G1q (ODM: Wistron) |
| WiFi/BT | Qualcomm WCN6855 ("FastConnect 6900"), PCI `17cb:1103` subsystem `105b:e108`, ath11k |
| HP driver pack | [sp171528.exe](https://ftp.hp.com/pub/softpaq/sp171501-172000/sp171528.exe), sha256 `3937fa23b6cf28fae5161d1aa717043b4fcb119300e7478a76405a6617460978` |

## Status

| Feature | State | Section |
|---|---|---|
| Boot, display | works, needs the device tree and kernel args | [Boot](#boot-device-tree-and-kernel-args) |
| WiFi | works with a board-data alias | [WiFi](#wifi) |
| Bluetooth | works (linux-firmware) | [Bluetooth](#bluetooth) |
| Battery status | works with HP's ADSP firmware | [ADSP firmware](#adsp-and-gpu-firmware-from-hps-driver-pack), [Battery](#battery) |
| GPU acceleration | works with HP's zap shader | [ADSP firmware](#adsp-and-gpu-firmware-from-hps-driver-pack) |
| Panel colours | need a mutter workaround | [Colours](#display-colours) |
| Speakers, headphones | work (T14s UCM profile) | [Sound](#sound) |
| Internal microphones | work with a UCM workaround | [Sound](#sound) |
| KVM (EL2) | works through slbounce; no battery/sound in that mode | [KVM](#kvm-el2-with-slbounce) |
| Keyboard backlight, Fn keys | no | [Not working](#not-working) |
| Autorotate | n/a (clamshell; sensors are on the ADSP, unsupported) | [Not working](#not-working) |

## Layout

```
rootfs/   files installed as-is (paths as on the target system)
build/    build-time steps, written as Fedora bootc Containerfile hooks (dnf, /ctx and
          /rpms are that build's); the logic carries over to any distribution
rpm/      slbounce.spec (EFI driver for KVM)
```

## Boot: device tree and kernel args

The laptop has no usable ACPI for Linux: without its DTB the screen stays black. The official Fedora installer ISO also hangs on a black screen ("Test this media & start") on this machine, while a kernel with the right DTB boots.

- **DTB**: Fedora ships `kernel-uki-dtbloader`, the same kernel with systemd-stub and a hardware-ID table ([stubble](https://github.com/ubuntu/stubble) hwids, which include the OmniBook) that picks the DTB at boot. It conflicts with `kernel-core` as a package, so [build/05-dtbloader.sh](build/05-dtbloader.sh) extracts its Fedora-signed `vmlinuz-dtbloader.efi` (rpm2cpio) and installs it as `/usr/lib/modules/<kver>/vmlinuz`. Secure Boot keeps working. Elsewhere: GRUB `devicetree /path/x1e80100-hp-omnibook-x14.dtb`, or systemd-boot `devicetree`.
- **Kernel args** ([rootfs/usr/lib/bootc/kargs.d/10-snapdragon-x1e.toml](rootfs/usr/lib/bootc/kargs.d/10-snapdragon-x1e.toml)), as in [Fedora's Snapdragon guide](https://fedoraproject.org/wiki/Snapdragon_WoA_Laptop_Install):
  - `clk_ignore_unused pd_ignore_unused`: without them, unused clocks/power domains are switched off and the display dies;
  - `systemd.tpm2_wait=0`: no TPM driver, so don't wait for it;
  - `firmware_class.path=/var/lib/omnibook-firmware`: where the ADSP/GPU firmware below goes (an immutable `/usr` can't hold it).

## WiFi

linux-firmware's `ath11k/WCN6855/hw2.0/board-2.bin` has no calibration data for HP's card (subsystem `105b:e108`, board id `0xff`), so ath11k fails to start. The card is the same as one linux-firmware already knows; only HP's IDs are missing. The same board file was [submitted to the ath11k list](http://lists.infradead.org/pipermail/ath11k/2024-December/006726.html) but never merged ([LP#2084960](https://bugs.launchpad.net/ubuntu-concept/+bug/2084960)).

[build/ath11k-omnibook-board.py](build/ath11k-omnibook-board.py) parses `board-2.bin` (ath11k IE format: board IEs with NAME/DATA sub-IEs, plus REGDB) and appends aliases for `bus=pci,vendor=17cb,device=1103,subsystem-vendor=105b,subsystem-device=e108,qmi-chip-id={2,18},qmi-board-id=255` pointing at the existing `e0c4` / `variant=HP_G8_Lancia14` calibration, plus a matching regdb entry. It's idempotent and reads plain, `.xz` or `.zst` input. [build/10-wifi-bt.sh](build/10-wifi-bt.sh) writes the result to `/usr/lib/firmware/updates/ath11k/WCN6855/hw2.0/board-2.bin` (takes precedence over the stock file) and links `hw2.1` to it.

```sh
python3 build/ath11k-omnibook-board.py /usr/lib/firmware/ath11k/WCN6855/hw2.0/board-2.bin.xz board-2.bin
```

## Bluetooth

Works out of the box with linux-firmware's `qca/hpbtfw21.tlv` and `qca/hpnv21.*` (Fedora: `atheros-firmware`).

## ADSP and GPU firmware from HP's driver pack

Battery status, sound and the GPU need firmware signed for HP that linux-firmware can't ship. It's in HP's Windows driver pack sp171528.exe (the same files Fedora's `qcom-firmware-extract` copies from a Windows partition), so no Windows install is needed. [rootfs/usr/libexec/omnibook-adsp-firmware](rootfs/usr/libexec/omnibook-adsp-firmware) downloads it, checks the SHA-256, extracts it with 7-Zip and installs into `/var/lib/omnibook-firmware/qcom/x1e80100/hp/omnibook-x14/`. A stamp file stores the softpaq hash and file list, so it refetches only when either changes. Offline: `omnibook-adsp-firmware /path/to/sp171528.exe`.

| File | What it is |
|---|---|
| `qcadsp8380.mbn` | ADSP firmware (Hexagon DSP: audio, battery/charger, sensors) |
| `adsp_dtbs.elf` | the ADSP's own device tree, loaded with it |
| `adspr.jsn` | protection-domain map for the ADSP root PD (read by `pd-mapper`) |
| `adsps.jsn` | the same for the sensors PD |
| `adspua.jsn` | the same for the audio PD |
| `battmgr.jsn` | the same for the battery manager; without it `qcom_battmgr` finds no battery |
| `qcdxkmsuc8380.mbn` | Adreno zap shader: takes the GPU out of secure mode (hardware acceleration) |

The firmware lives in `/var`, which is mounted after the initramfs, so the ADSP must start late:

- [omnibook-adsp.conf](rootfs/usr/lib/modprobe.d/omnibook-adsp.conf) blacklists `qcom_q6v5_pas`, and [90-omnibook.conf](rootfs/usr/lib/dracut/dracut.conf.d/90-omnibook.conf) keeps it (and `ath11k_pci`) out of the initramfs;
- [omnibook-adsp.service](rootfs/usr/lib/systemd/system/omnibook-adsp.service) runs `modprobe qcom_q6v5_pas` once the firmware exists;
- [omnibook-adsp-firmware.service](rootfs/usr/lib/systemd/system/omnibook-adsp-firmware.service) fetches after `network-online.target`, retries every 5 minutes, then starts the ADSP;
- the NetworkManager dispatcher [90-omnibook-adsp-firmware](rootfs/usr/lib/NetworkManager/dispatcher.d/90-omnibook-adsp-firmware) triggers the fetch as soon as a connection comes up.

The GPU uses the zap shader from the next login. Fedora's `qcom-firmware` has the Adreno X1-85 firmware itself (`gen70500_*`).

## Battery

Right after the ADSP starts, `qcom_battmgr` briefly reports placeholder capacities (`energy_full` ≈ the current energy, `energy_full_design` 0). UPower reads `energy_full` only once, so it showed ~100% after every boot, drifting to the real value. [omnibook-battery-settle](rootfs/usr/libexec/omnibook-battery-settle) waits for `energy_full_design > 0` (plus 5 s), and UPower is ordered after it ([10-omnibook-battery.conf](rootfs/usr/lib/systemd/system/upower.service.d/10-omnibook-battery.conf)). When the firmware arrives later (first boot), UPower is restarted once instead.

## Display colours

With GPU acceleration, the internal panel shows a green/blue tint while screenshots look right: the display controller misreads the GPU's compressed (UBWC) buffers. [50-mutter-no-kms-modifiers.conf](rootfs/usr/lib/environment.d/50-mutter-no-kms-modifiers.conf) sets `MUTTER_DEBUG_USE_KMS_MODIFIERS=0`, so mutter scans out plain linear buffers. `environment.d` reaches GNOME Shell and the GDM greeter.

Only one resolution (2240×1400) is offered: the eDP panel has no scaling mode. Use GNOME's (fractional) scaling.

## Sound

- alsa-ucm-conf maps "HP Omnibook X" to the **ThinkPad T14s** profile, and Fedora's `qcom-firmware` ships `X1E80100-HP-OMNIBOOK-X14-tplg.bin` (a link to the T14s topology). Needed: PipeWire + WirePlumber, `alsa-ucm`, `qcom-firmware`, the ADSP firmware above ([build/30-gpu-audio.sh](build/30-gpu-audio.sh)).
- That profile has headphones and HDMI/DP 0/1/2 on one PCM, so GNOME lists several output configurations. Speakers and headphones work.
- **Microphones**: the T14s profile enables DMIC0/1, but the OmniBook device tree (copied from the CRD) ties DMIC0/1 to MIC BIAS3 instead of MIC BIAS1, so the mics record silence. [HP-Omnibook-X14-MicBias.conf](rootfs/usr/share/alsa/ucm2/Qualcomm/x1e80100/HP-Omnibook-X14-MicBias.conf) also captures the unconnected DMIC2 on a third decimator, so DAPM powers MIC BIAS1; the stream stays two channels. It also raises VA_DEC0/1 from 100 (+16 dB) to 106 (+22 dB). It's included into the profile's "Mic" device after `vadm1d`:
  ```sh
  sed -i '/Include.vadm1d.File/a\	Include.hpmicb.File "/Qualcomm/x1e80100/HP-Omnibook-X14-MicBias.conf"' \
      /usr/share/alsa/ucm2/Qualcomm/x1e80100/T14s-HiFi.conf
  ```
- The speakers are WSA884x amplifiers without Linux speaker protection: don't run them at maximum volume for long.

## KVM (EL2) with slbounce

Snapdragon X firmware starts Linux in EL1 under Qualcomm's hypervisor (Gunyah/QHEE), so there is no `/dev/kvm` and VMs run emulated (QEMU TCG). [slbounce](https://github.com/TravMurav/slbounce) uses Qualcomm's Secure Launch with Windows' Microsoft-signed `tcblaunch.exe` to take EL2 over instead. **This works on this laptop** with the setup below.

**tcblaunch.exe version matters.** Microsoft removed the error handling slbounce relies on from some builds, and older ones don't support X1E. On this OmniBook:

| Version | Result |
|---|---|
| 26100.4351 | **works** (also confirmed on other X1E laptops) |
| 26100.1742 | resets at `== Launch:` in sltest (works on a Yoga Slim 7x) |

Microsoft's symbol server serves the plain signed file: `https://msdl.microsoft.com/download/symbols/tcblaunch.exe/66A7C7F3100000/tcblaunch.exe` (26100.4351, sha256 `463520e19581da964834b4f07b19303665dc701de31c6ad748ef8cbd1333e548`). More versions with their IDs and hashes are in `TCB_VERSIONS` in [omnibook-kvm](rootfs/usr/bin/omnibook-kvm).

**Boot chain** (Secure Boot off: slbounce and systemd-boot are unsigned):

1. `tcblaunch.exe` at the root of the ESP (slbounce opens it from the volume it was loaded from).
2. Fedora's GRUB can't load EFI drivers (no `chainloader`), so systemd-boot goes first: a firmware boot entry starts `\EFI\lm-kvm\systemd-bootaa64.efi`, which loads `\EFI\systemd\drivers\slbounceaa64.efi` and starts `\EFI\fedora\grubaa64.efi` (`timeout 0`). slbounce hooks `ExitBootServices` and only switches when the loaded DTB has the GPU zap shader disabled (an `-el2` DTB), so normal entries boot unchanged.
3. A GRUB entry boots `kernel-core`'s plain image (not the dtbloader UKI: its stub would swap in the non-EL2 DTB) with `devicetree` = the EL2 DTB and the extra args below.

**EL2 device tree**: upstream's `x1e80100-hp-omnibook-x14-el2.dtb` (Linux 6.16+), **minus** the ADSP/CDSP remoteproc `iommus` the x1-el2 overlay gained in 7.1 (commit 47c88db49f6c): on X1E laptops booted through slbounce they cause an apps-SMMU fault storm and a hard lockup (black screen, nothing in the journal). [build/04-kvm.sh](build/04-kvm.sh):
```sh
fdtput -d kvm.dtb /soc@0/remoteproc@6800000 iommus
fdtput -d kvm.dtb /soc@0/remoteproc@32300000 iommus
```

**Kernel args** for the EL2 entry: `id_aa64mmfr0.ecv=1` (the firmware resets on CNTPOFF_EL2 access) and `cpuidle.off=1`: in EL2 the deeper CPU idle states make the touchscreen and touchpad lag. Windows shows the same lag, as it runs in EL2 too (Hyper-V); there, `powercfg -setacvalueindex scheme_current sub_processor IDLEDISABLE 1` (and `-setdcvalueindex`, then `powercfg -setactive scheme_current`) is the equivalent.

**Limits in EL2**: Linux can't start the ADSP without Qualcomm's hypervisor (TrustZone rejects it), so there is **no battery status and no sound**. GPU and WiFi work. The way forward is [qebspil](https://github.com/stephan-gh/qebspil), an EFI driver that boots the DSPs before the switch, plus kernel patches that attach to the running DSPs (not upstream). EFI variable changes may not persist at EL2 or across a failed Secure Launch, so don't use one-shot boot entries (`LoaderEntryOneShot`) to test: a reset loops on them.

[omnibook-kvm](rootfs/usr/bin/omnibook-kvm) (`enable | version <v> | disable | status | update`) automates all of this for a bootc/ostree system: fetches and checks `tcblaunch.exe`, installs systemd-boot + slbounce on the ESP, creates the firmware entry (`efibootmgr`), and writes the GRUB entry to `/boot/grub2/custom.cfg`; [omnibook-kvm.service](rootfs/usr/lib/systemd/system/omnibook-kvm.service) refreshes it at every boot. slbounce is built from source by [rpm/slbounce.spec](rpm/slbounce.spec) (v5, native aarch64 build, without its boot banner). To test the switch alone, run slbounce's `sltest.efi \tcblaunch.exe` from systemd-boot or an EFI shell, after a full power-off: a green line means it works.

## Not working

- **Keyboard backlight, Fn keys**: handled by HP's embedded controller, which has no Linux driver (`qcom-hamoa-ec` covers only fans and thermals on other machines).
- **Autorotate**: a clamshell laptop; the sensors sit on the ADSP's sensor PD, which Linux doesn't use.
- **GNOME "Processor" field** is empty: arm64 `/proc/cpuinfo` has no model name.
- **Official Fedora ISO**: hangs on a black screen (no DTB); boot an image with the dtbloader kernel instead.

## Credits

Upstream device tree: Xilin Wu. HP OmniBook UCM mapping: Jens Glathe. slbounce: Nikita Travkin. Board-data and version reports from the [#aarch64-laptops](https://oftc.catirclogs.org/aarch64-laptops/) community.
