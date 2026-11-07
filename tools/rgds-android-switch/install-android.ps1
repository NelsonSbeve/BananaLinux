param([string]$Adb = "adb")
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Invoke-Adb {
    & $Adb @args
    if ($LASTEXITCODE -ne 0) { throw "adb failed with exit code $LASTEXITCODE" }
}

Invoke-Adb wait-for-device
Invoke-Adb root
Invoke-Adb wait-for-device
$Model = (& $Adb shell 'tr -d "\000" </proc/device-tree/model' 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or ($Model -ne "Anbernic RG DS" -and $Model -ne "Anbernic RG DS (rk3568)")) { throw "Unsupported Android device: $Model" }
$Uid = (& $Adb shell 'id -u' | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $Uid -ne "0") { throw "adb root did not provide a root shell" }
Invoke-Adb remount
Invoke-Adb push (Join-Path $Root "android/restore-banana-sd") /vendor/bin/restore-banana-sd
Invoke-Adb push (Join-Path $Root "android/restore-banana-sd.rc") /vendor/etc/init/restore-banana-sd.rc
Invoke-Adb shell 'chmod 0755 /vendor/bin/restore-banana-sd; chmod 0644 /vendor/etc/init/restore-banana-sd.rc; chown 0:0 /vendor/bin/restore-banana-sd /vendor/etc/init/restore-banana-sd.rc; sync'
Invoke-Adb shell 'mount_dir=$(dirname "$(find /mnt/media_rw -maxdepth 3 -name rgds-android-switch.conf 2>/dev/null | head -n 1)"); [ -f "$mount_dir/rgds-android-switch.conf" ] || { echo "BananaOS SD boot partition is not mounted; reinsert the card" >&2; exit 1; }; touch "$mount_dir/rgds-android-switch-ready"; sync; /system/bin/sh /vendor/bin/restore-banana-sd'
Invoke-Adb shell 'tail -30 /data/local/tmp/restore-banana-sd.log'
Write-Host "Android restorer installed and BananaOS boot sectors verified. Restart Android to return to BananaOS."
