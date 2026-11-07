# RG DS: boot Android from BananaOS without ADB

This experimental add-on boots the stock Android system on the RG DS's internal eMMC from the BananaOS SD card. It does not write Android partitions. It needs an RG DS BananaOS image built with `uboot-rgds-android.fragment`; the RG DS Plus and universal images are intentionally excluded.

## How it works

The BananaOS menu tile writes a one-use marker to the SD card's FAT boot partition and restarts. The rebuilt SD U-Boot consumes and deletes the marker, reads Android's `boot` and `dtbo` partitions from eMMC, extracts the Android v2 DTB, applies the DTBO overlay, then starts the kernel. Since the marker was removed before Android starts, a normal Android restart follows the SD boot flow and returns to BananaOS.

The current stock image was inspected read-only over SSH: eMMC `boot` is Android image header v2, `dtbo` contains one overlay at index 0, and `misc` is blank. This assumes stock, non-A/B Android on the RG DS.

## Build and install

Build the `rgds` image from this branch with `make rgds`. Before replacing the SD bootloader, keep a computer copy of the original 16 MiB SD boot-area backup. The preparation artifact is `outputs/rgds-android-switch/sd-first-16MiB-20261107.img` (SHA-256 `feb2fc8418093a42163cd3c8c3c46630816e2c1d7f4dc0669e607a65c15fc2ce`).

Do not write the generated image's first 16 MiB over an existing, expanded card: that area includes its primary GPT, whose backup header is at the card's physical end. Install only the built `u-boot-rockchip.bin` at LBA 64 and copy `rgds-android.env` into the SD's FAT boot partition. The CI build uploads both files as `rgds-android-boot-files`. Keep the existing FIT at LBA 16384 and the current partition table intact. The first 16 MiB backup is for recovery, not the update payload.

After that, copy this directory to the handheld and run:

```sh
sh install-banana.sh
```

The tile is added to BananaOS's Apps shelf. The Android marker is consumed before the boot attempt, so a normal restart should still use BananaOS's default boot flow. If the SD no longer boots, restore the saved 16 MiB boot-area image to the start of that same SD card.

## Limits

This has not yet been tested by booting Android on the handheld. The build configuration and commands must compile and be reviewed before installing the rebuilt U-Boot. Keep the original boot-area backup. No sectors on the handheld have been changed by this preparation.
