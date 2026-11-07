#!/bin/sh
set -eu

BOOT=/boot
DATA=/data
TILES="$DATA/store/tiles"
TILE="$TILES/Boot Android.sh"
LIST="$TILES/gamelist.xml"

fail() { echo "Boot Android install: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || fail "run this installer as root"
[ "$(cat /etc/banana/board 2>/dev/null)" = rgds ] || fail "this add-on is only for the RG DS image"
[ -f "$BOOT/rgds-android.env" ] || fail "the SD card does not have the Android-capable U-Boot files; install the prepared RG DS boot image first"
[ -d "$TILES" ] || fail "BananaOS Apps shelf not found at $TILES"
[ -f "$LIST" ] || printf '<gameList>\n</gameList>\n' > "$LIST"
grep -q '^</gameList>$' "$LIST" || fail "unexpected Apps shelf gamelist format; no files were changed"

cat > "$TILE" <<'EOF'
#!/bin/sh
set -eu
BOOT=/boot
FLAG="$BOOT/rgds-android.once"
mount -o remount,rw "$BOOT"
cleanup() { mount -o remount,ro "$BOOT" 2>/dev/null || true; }
trap cleanup EXIT HUP INT TERM
printf 'android\n' > "$FLAG"
sync
cleanup
trap - EXIT HUP INT TERM
reboot
EOF
chmod 755 "$TILE"

if ! grep -q '<path>./Boot Android.sh</path>' "$LIST"; then
    entry="$TILES/.boot-android-entry"
    tmp="$LIST.new"
    cat > "$entry" <<'EOF'
	<game>
		<path>./Boot Android.sh</path>
		<name>Boot Android</name>
		<desc>Restart into the Android system stored in the handheld. The next normal restart returns to BananaOS.</desc>
		<genre>System</genre>
	</game>
EOF
    awk -v entry="$entry" '/^<\/gameList>$/ { while ((getline line < entry) > 0) print line } { print }' "$LIST" > "$tmp"
    mv "$tmp" "$LIST"
    rm -f "$entry"
fi

echo "Boot Android tile installed on the Apps shelf."

