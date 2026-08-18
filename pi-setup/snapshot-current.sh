#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAP="$REPO/pi-setup/snapshot"

if pgrep -x mixxx >/dev/null; then
    echo "ERROR: Mixxx is running."
    echo "Quit Mixxx normally with Ctrl+Q first so mixxx.cfg is saved."
    exit 1
fi

echo "Snapshotting current Pi configuration..."

mkdir -p \
    "$SNAP/mixxx" \
    "$SNAP/sway" \
    "$SNAP/waybar" \
    "$SNAP/assets" \
    "$SNAP/system/lightdm" \
    "$REPO/pi-setup/packages"

cp "$HOME/.config/sway/config" \
   "$SNAP/sway/config"

rm -rf "$SNAP/waybar"
mkdir -p "$SNAP/waybar"
cp -a "$HOME/.config/waybar/." \
   "$SNAP/waybar/"

cp "$HOME/wallpaper/wallpaper.jpg" \
   "$SNAP/assets/wallpaper.jpg"

for f in \
    mixxx.cfg \
    effects.xml \
    samplers.xml \
    sandbox.cfg \
    soundconfig.xml \
    mixxxdb.sqlite
do
    if [ -f "$HOME/.mixxx/$f" ]; then
        cp "$HOME/.mixxx/$f" "$SNAP/mixxx/$f"
    fi
done

rm -rf "$SNAP/mixxx/controllers"
cp -a "$HOME/.mixxx/controllers" \
   "$SNAP/mixxx/controllers"

sudo cp /etc/lightdm/lightdm.conf \
    "$SNAP/system/lightdm/lightdm.conf"

sudo chown "$USER:$USER" \
    "$SNAP/system/lightdm/lightdm.conf"

cp /boot/firmware/config.txt \
   "$SNAP/system/boot-config.txt"

apt-mark showmanual | sort \
    > "$REPO/pi-setup/packages/apt-manual-full.txt"

dpkg-query -W -f='${binary:Package}\t${Version}\n' | sort \
    > "$REPO/pi-setup/packages/dpkg-versions.txt"

cat /etc/os-release \
    > "$SNAP/system/os-release.txt"

uname -a \
    > "$SNAP/system/uname.txt"

echo
echo "Snapshot complete."
echo "Review with:"
echo "  git status"
echo "  git diff"
