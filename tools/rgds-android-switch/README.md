# RG DS: switch between BananaOS and stock Android

This experimental add-on adds a **Switch to Android** tile to BananaOS. It
boots the stock Android installation on the RG DS's internal eMMC while the
BananaOS SD card stays inserted. Android restores the SD boot headers, so a
normal Android restart returns to BananaOS.

## Tested status

Tested end-to-end on one Anbernic RG DS running BananaOS 0.5.2.2 from the SD
card and its stock Android installation from eMMC (7 November 2026). The
switch booted Android and returned to BananaOS. This is community software,
not an official BananaOS feature. It has not been tested on the RG DS Plus or
other storage layouts.

## Requirements

- An **Anbernic RG DS** (not RG DS Plus) with the stock Android installation
  still present on eMMC.
- BananaOS on the SD card, using the RG DS layout in this repository: the FAT
  boot partition starts at LBA 32768 and the SD boot markers are `RKNS` at
  LBA 64 and a FIT header at LBA 16384.
- Root SSH access in BananaOS and a computer with SSH/SCP.
- Android USB debugging and **root ADB**. `adb root` must work and
  `adb shell id` must report `uid=0(root)`. USB debugging alone is not enough.
- A computer backup of the SD boot area. The installer checks and creates a
  card-specific backup before it enables the switch.

If `adb root` is refused, stop. This method depends on root ADB to install the
Android restore service; it does not unlock or root Android for you.

## How it works

The BananaOS tile checks the model, SD layout, backup, and saved hashes. When
selected, it temporarily zeros two 512-byte sectors on the SD: LBA 64 and LBA
16384. The Rockchip boot ROM then falls through to the RG DS's original eMMC
boot chain and Android starts normally. The SD's filesystems and Android's
bootloader are not written by the switch.

An init service installed in Android's `/vendor` restores the two saved SD
sectors from the verified backup. It restores the FIT sector first and the
RKNS selector last. The BananaOS tile refuses to switch until this Android
service has been installed and verified.

The reversible boot-sector design adapts
[thegraxisreal's RG DS ROCKNIX ↔ Android switch](https://github.com/thegraxisreal/rgds-rocknix-android-switch)
to BananaOS's SD layout and Apps menu.

## Install

Use a working copy of this repository's `codex/rgds-android-switch` branch.
The steps below show Windows PowerShell; replace `<IP>` with the handheld's
BananaOS address and use the SSH key that is authorized on the device.

### 1. Install the BananaOS side

With BananaOS running and SSH enabled, copy this add-on directory to the
handheld. Open PowerShell in the repository root:

```powershell
scp -O -r .\tools\rgds-android-switch root@<IP>:/data/banana/
ssh root@<IP> 'bash /data/banana/rgds-android-switch/install-banana.sh'
```

`-O` selects legacy SCP, which works with BananaOS's SSH server. The installer
checks the RG DS model, SD device type, partition start, and both boot markers.
It saves a 16 MiB backup at `/boot/rgds-sd-boot-area-16MiB.img`, writes its
hash configuration, installs the **Switch to Android** tile, and returns
`/boot` to read-only. It does not change either boot sector.

Copy the backup to the computer and keep it safe:

```powershell
scp -O root@<IP>:/boot/rgds-sd-boot-area-16MiB.img .\rgds-sd-boot-area-16MiB.img
```

Do not continue if the installer reports a model, layout, marker, or hash
mismatch. Do not use a backup from another SD card.

### 2. Prepare Android and install its restore service

For this one-time setup, boot Android by its normal route: shut down BananaOS,
remove the SD card, and power on. After Android has fully loaded, insert the SD
card and connect the console to the computer by USB. Enable Developer options
and USB debugging, then accept the computer's RSA authorization prompt.

In PowerShell, check the connection and root access:

```powershell
adb devices
adb root
adb shell id
```

Continue only if the device is listed as `device`, `adb root` succeeds, and
the shell reports `uid=0(root)`. From the repository directory, run:

```powershell
.\tools\rgds-android-switch\install-android.ps1
```

The script checks the RG DS model and root access, remounts Android partitions
for the install, copies the restore service to `/vendor/bin/` and its init
configuration to `/vendor/etc/init/`, creates the ready marker on the SD, then
runs the service once. The final log should say that the FIT and selector are
already active. This step **does modify Android's `/vendor` partition**.

Restart Android with the SD inserted. With the boot headers still active, the
console should return to BananaOS. The Switch to Android tile is now enabled.

### 3. Use the switch

In BananaOS, open **Apps → Switch to Android**. Do not use any separate
experimental direct-boot tile. The console powers off after checking the SD.
Wait about ten seconds, then press Power once with the SD still inserted.
Android should start and restore the SD headers automatically. Restart Android
normally to boot BananaOS again.

## Recovery

If Android starts but does not restore the SD headers, leave the SD inserted,
connect root ADB, and run the guarded restore service manually:

```powershell
adb root
adb shell '/system/bin/sh /vendor/bin/restore-banana-sd; cat /data/local/tmp/restore-banana-sd.log'
```

The service verifies the saved backup and hashes, and only writes a header if
that sector is all zero. If it reports an unexpected sector value, a missing
backup, or a hash mismatch, stop. Do not guess a block device or run `dd` with
values from another card. The backup is card-specific.

## Updates and reinstalling

Normal in-place BananaOS updates through **Settings → System → Updates** use
the other system slot and update the kernel/device tree under `/boot`; they
preserve the data partition. The add-on's tile and boot files are outside the
slot update, so this switch should remain available after a normal update.
The Android restore service is separate from BananaOS updates. See the
[BananaOS update documentation](https://github.com/JorreFog/BananaLinux/blob/main/docs/FIRST-BOOT.md#updating-later).

Reflashing a complete SD image, replacing the SD card, or restoring a whole
card image can remove the tile/configuration and replace the SD boot headers.
After that, reinstall the BananaOS side and Android restorer using a fresh,
matching backup. Do not apply an old card's backup to a new card.

## Files installed

- SD `/boot`: `rgds-sd-boot-area-16MiB.img`, `rgds-android-switch.conf`, and
  `rgds-android-switch-ready`.
- BananaOS data: `/data/store/tiles/Switch to Android.sh` and its log at
  `/data/banana/logs/rgds-android-switch.log`.
- Android `/vendor`: `/vendor/bin/restore-banana-sd` and
  `/vendor/etc/init/restore-banana-sd.rc`.

The add-on does not change the BananaOS root filesystem or the internal
Android bootloader. Keep the SD backup on a computer before using it.
