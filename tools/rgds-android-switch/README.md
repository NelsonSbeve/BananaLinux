# RG DS BananaOS ↔ Android switch

This experimental add-on adds a **Switch to Android** tile to BananaOS and boots
the stock Android system on the internal eMMC without removing the SD card.
Android restores BananaOS's SD boot sectors during startup, so restarting
Android normally returns to BananaOS.

It is for the **Anbernic RG DS only**, with stock internal Android and a
BananaOS card using the layout in this repository. It has not been tested on
hardware. Do not install it on the RG DS Plus or another image. A wrong boot
sector can leave the card unable to boot; keep a second copy of the generated
16 MiB backup on a computer before enabling the Android restorer.

The design adapts the reversible RG DS boot-sector switch by thegraxisreal:
[rgds-rocknix-android-switch](https://github.com/thegraxisreal/rgds-rocknix-android-switch).
The BananaOS-specific layout checks and integration are in this directory.

## Why the ROCKNIX switch cannot be installed unchanged

BananaOS identifies the SD card dynamically and mounts its first FAT partition
at `/boot`. Its image reserves the first 16 MiB for Rockchip boot data; the
first partition starts at LBA 32768. The add-on checks those facts, checks
`RKNS` at LBA 64 and a FIT header at LBA 16384, and hashes the exact sectors
from your card before it will offer to switch. It does not assume the ROCKNIX
device name or write sectors based only on the model name.

## Install

1. Put your SSH public key in `banana/ssh/authorized_keys` on the SD data
   partition, enable SSH in Settings → Network, then connect as `root` (BananaOS
   SSH uses keys and does not provide password login).
2. Copy this directory to `/data/banana/rgds-android-switch` with `scp -r`,
   then run `bash /data/banana/rgds-android-switch/install-banana.sh` over SSH.
   It makes a 16 MiB boot-area backup on the FAT boot partition and installs a
   guarded tile under BananaOS's Apps shelf.
3. Copy `/boot/rgds-sd-boot-area-16MiB.img` to a computer and keep it safe.
4. Shut down BananaOS, start Android once with the SD card inserted, and
   connect the device to a computer with ADB. USB debugging and `adb root`
   must work. On Windows, run `install-android.ps1` from this directory.
   The script installs Android's restore service, marks the switch ready, and
   immediately verifies that the sectors are intact.
5. Restart Android. It should boot back to BananaOS.

The Apps shelf tile appears after step 2 but refuses to alter boot sectors
until step 4 has created the ready marker. To switch, launch it, let BananaOS
power off, wait about ten seconds, then press Power again with the SD card
still inserted. The first start after power-off is a separate press because
the internal boot chain is selected only after the SD headers are blanked.

## Recovery

If Android does not restore BananaOS boot, boot Android, insert the SD after
Android is ready, and use root ADB. Restore the FIT sector first and the
selector sector last from the backup on the mounted SD partition:

```sh
adb root
adb shell
backup=$(find /mnt/media_rw -maxdepth 3 -name rgds-sd-boot-area-16MiB.img | head -n 1)
dd if="$backup" of=/dev/block/mmcblk0 bs=512 skip=16384 seek=16384 count=1 conv=fsync
dd if="$backup" of=/dev/block/mmcblk0 bs=512 skip=64 seek=64 count=1 conv=fsync
sync
```

If the sectors do not match the generated backup, stop and do not write guessed
values. The backup is specific to that SD card and BananaOS image.

## What it changes

- SD card: creates `/rgds-sd-boot-area-16MiB.img`, its hash configuration and
  a readiness marker on the FAT boot partition; installs the app script under
  `/data/store/tiles/`.
- Android: installs `/vendor/bin/restore-banana-sd` and
  `/vendor/etc/init/restore-banana-sd.rc`.
- Switching blanks only LBA 64 and LBA 16384, after checking both sectors
  against the backup; Android restores FIT first and selector last.

The add-on does not modify the internal bootloader, Android partitions, or
BananaOS system image. Android root ADB is required; without it this switching
method cannot be completed.
