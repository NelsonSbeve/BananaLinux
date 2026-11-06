#!/bin/bash
set -euo pipefail

FLASH=/boot
DATA=/data
BACKUP="$FLASH/rgds-sd-boot-area-16MiB.img"
CONFIG="$FLASH/rgds-android-switch.conf"
READY="$FLASH/rgds-android-switch-ready"
TILE="$DATA/store/tiles/Switch to Android.sh"

fail() { echo "ERROR: $*" >&2; exit 1; }
BOOT_RW=0
boot_ro() {
    if [[ "$BOOT_RW" == 1 ]]; then
        mount -o remount,ro "$FLASH" || return 1
        BOOT_RW=0
    fi
}
trap 'boot_ro' EXIT
hash_of() { sha256sum "$1" | awk '{print $1}'; }
sector_hash() { dd if="$1" bs=512 skip="$2" count=1 2>/dev/null | sha256sum | awk '{print $1}'; }
magic() { dd if="$1" bs=512 skip="$2" count=1 2>/dev/null | od -An -tx1 -N4 | tr -d ' \n'; }

[[ "$(id -u)" == 0 ]] || fail "run this installer as root"
model="$(tr -d '\0' </proc/device-tree/model 2>/dev/null || true)"
[[ "$model" == "Anbernic RG DS" ]] || fail "unsupported model: $model"
[[ -s /run/banana/disk ]] || fail "BananaOS did not identify its boot SD card"
DEVICE="$(cat /run/banana/disk)"
[[ -b "$DEVICE" ]] || fail "boot device $DEVICE is missing"
BASE="${DEVICE##*/}"
[[ "$(cat "/sys/class/block/$BASE/device/type" 2>/dev/null)" == SD ]] || fail "$DEVICE is not an SD card"
PART="${DEVICE}p1"
[[ -b "$PART" ]] || fail "boot partition $PART is missing"
[[ "$(cat "/sys/class/block/${PART##*/}/start" 2>/dev/null)" == 32768 ]] || fail "boot partition does not start at LBA 32768"
[[ "$(awk '$2 == "/boot" {print $1}' /proc/mounts)" == "$PART" ]] || fail "/boot is not mounted from $PART"

mkdir -p "$DATA/store/tiles"
if [[ ! -f "$BACKUP" ]]; then
    mount -o remount,rw "$FLASH" || fail "could not remount /boot read-write"
    BOOT_RW=1
    dd if="$DEVICE" of="$BACKUP" bs=1M count=16 conv=fsync 2>/dev/null || fail "could not back up the SD boot area"
    sync
    boot_ro || fail "could not return /boot to read-only"
fi
[[ "$(wc -c <"$BACKUP" | tr -d ' ')" == 16777216 ]] || fail "backup is not exactly 16 MiB"
[[ "$(magic "$BACKUP" 64)" == 524b4e53 ]] || fail "backup has no RKNS marker at LBA 64"
[[ "$(magic "$BACKUP" 16384)" == d00dfeed ]] || fail "backup has no FIT header at LBA 16384"
for sector in 64 16384; do
    live="$(dd if="$DEVICE" bs=512 skip="$sector" count=1 2>/dev/null | sha256sum | awk '{print $1}')"
    saved="$(sector_hash "$BACKUP" "$sector")"
    [[ "$live" == "$saved" ]] || fail "live LBA $sector differs from the saved backup"
done

backup_hash="$(hash_of "$BACKUP")"
selector_hash="$(sector_hash "$BACKUP" 64)"
fit_hash="$(sector_hash "$BACKUP" 16384)"
zero_hash=076a27c79e5ace2a3d47f9dd2e83e4ff6ea8872b3c2218f66c92b89b55f36560
tmp="$CONFIG.new"
mount -o remount,rw "$FLASH" || fail "could not remount /boot read-write"
BOOT_RW=1
rm -f "$READY"
cat >"$tmp" <<EOF
EXPECTED_BACKUP_HASH=$backup_hash
EXPECTED_SELECTOR_HASH=$selector_hash
EXPECTED_FIT_HASH=$fit_hash
EXPECTED_ZERO_SECTOR_HASH=$zero_hash
EOF
mv -f "$tmp" "$CONFIG"
cp "$(dirname "$0")/banana/Switch to Android.sh" "$TILE"
chmod 755 "$TILE"
sync
boot_ro || fail "could not return /boot to read-only"
echo "BananaOS side installed. The tile stays locked until Android's restorer is installed."
echo "Backup: $BACKUP"
