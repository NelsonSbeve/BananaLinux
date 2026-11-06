#!/bin/bash
set -euo pipefail

FLASH=/boot
DEVICE="$(cat /run/banana/disk 2>/dev/null || true)"
BACKUP="$FLASH/rgds-sd-boot-area-16MiB.img"
CONFIG="$FLASH/rgds-android-switch.conf"
READY="$FLASH/rgds-android-switch-ready"
LOG=/data/banana/logs/rgds-android-switch.log
SECTOR64=/run/banana-sd-sector64.bin
SECTOR16384=/run/banana-sd-sector16384.bin

mkdir -p "$(dirname "$LOG")"
stamp() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"; }
fail() { stamp "ABORT: $*"; exit 1; }
read_value() { sed -n "s/^$1=//p" "$CONFIG" | head -n 1; }
valid_hash() { [[ "$1" =~ ^[0-9a-f]{64}$ ]]; }
sector_hash() { dd if="$1" bs=512 skip="$2" count=1 2>/dev/null | sha256sum | awk '{print $1}'; }

stamp "switch requested"
[[ -f "$READY" ]] || fail "Android restore service is not installed"
[[ -f "$CONFIG" && -f "$BACKUP" ]] || fail "backup or configuration is missing"
model="$(tr -d '\0' </proc/device-tree/model 2>/dev/null || true)"
[[ "$model" == "Anbernic RG DS" ]] || fail "unsupported model: $model"
[[ -b "$DEVICE" && "$(cat "/sys/class/block/${DEVICE##*/}/device/type" 2>/dev/null)" == SD ]] || fail "boot SD check failed"
[[ "$(cat "/sys/class/block/${DEVICE##*/}p1/start" 2>/dev/null)" == 32768 ]] || fail "boot partition layout changed"
[[ "$(awk '$2 == "/boot" {print $1}' /proc/mounts)" == "${DEVICE}p1" ]] || fail "/boot is not mounted from the boot SD"
EXPECTED_BACKUP_HASH="$(read_value EXPECTED_BACKUP_HASH)"
EXPECTED_SELECTOR_HASH="$(read_value EXPECTED_SELECTOR_HASH)"
EXPECTED_FIT_HASH="$(read_value EXPECTED_FIT_HASH)"
EXPECTED_ZERO_SECTOR_HASH="$(read_value EXPECTED_ZERO_SECTOR_HASH)"
for value in "$EXPECTED_BACKUP_HASH" "$EXPECTED_SELECTOR_HASH" "$EXPECTED_FIT_HASH" "$EXPECTED_ZERO_SECTOR_HASH"; do
    valid_hash "$value" || fail "invalid hash configuration"
done
[[ "$(sha256sum "$BACKUP" | awk '{print $1}')" == "$EXPECTED_BACKUP_HASH" ]] || fail "backup hash mismatch"
dd if="$BACKUP" of="$SECTOR64" bs=512 skip=64 count=1 2>/dev/null
dd if="$BACKUP" of="$SECTOR16384" bs=512 skip=16384 count=1 2>/dev/null
[[ "$(sector_hash "$DEVICE" 64)" == "$EXPECTED_SELECTOR_HASH" ]] || fail "LBA 64 differs from backup"
[[ "$(sector_hash "$DEVICE" 16384)" == "$EXPECTED_FIT_HASH" ]] || fail "LBA 16384 differs from backup"

# Disable the ROM selector first. Restore in the opposite order on Android.
sync
dd if=/dev/zero of="$DEVICE" bs=512 seek=64 count=1 conv=notrunc,fsync 2>/dev/null || fail "could not disable LBA 64"
dd if=/dev/zero of="$DEVICE" bs=512 seek=16384 count=1 conv=notrunc,fsync 2>/dev/null || {
    dd if="$SECTOR64" of="$DEVICE" bs=512 seek=64 count=1 conv=notrunc,fsync 2>/dev/null || true
    fail "could not disable LBA 16384"
}
if [[ "$(sector_hash "$DEVICE" 64)" != "$EXPECTED_ZERO_SECTOR_HASH" || "$(sector_hash "$DEVICE" 16384)" != "$EXPECTED_ZERO_SECTOR_HASH" ]]; then
    stamp "ERROR: disabled-sector verification failed; restoring"
    dd if="$SECTOR16384" of="$DEVICE" bs=512 seek=16384 count=1 conv=notrunc,fsync 2>/dev/null || true
    dd if="$SECTOR64" of="$DEVICE" bs=512 seek=64 count=1 conv=notrunc,fsync 2>/dev/null || true
    sync
    exit 1
fi
sync
stamp "SD boot headers disabled; powering off"
poweroff
sleep 30
stamp "ERROR: poweroff returned; restoring SD boot headers"
dd if="$SECTOR16384" of="$DEVICE" bs=512 seek=16384 count=1 conv=notrunc,fsync 2>/dev/null || true
dd if="$SECTOR64" of="$DEVICE" bs=512 seek=64 count=1 conv=notrunc,fsync 2>/dev/null || true
sync
exit 1
