#!/usr/bin/env bash
# Rebuild the known-good Raspberry Pi 5 + Waveshare 9-DSI-TOUCH-B + Sway
# + custom Mixxx 2.5.6 environment from this repository.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SNAPSHOT="$SCRIPT_DIR/snapshot"
PACKAGES_DIR="$SCRIPT_DIR/packages"

DO_UPGRADE=1
DO_BUILD=1
DO_REBOOT=0
TARGET_USER_OVERRIDE=""

usage() {
    cat <<'USAGE'
Usage: sudo ./pi-setup/install.sh [options]

Options:
  --no-upgrade        Skip apt full-upgrade.
  --skip-build        Do not rebuild Mixxx; build/mixxx must already exist.
  --reboot            Reboot automatically after a successful install.
  --user USER         Install user configuration for USER instead of $SUDO_USER.
  -h, --help          Show this help.

Target:
  Raspberry Pi 5
  Raspberry Pi OS / Debian 12 Bookworm, 64-bit
  Waveshare 9-DSI-TOUCH-B (SKU 32772)
  Sway + XWayland
  custom Mixxx 2.5.6 with CDJDeere / CDJ 3Band renderer
USAGE
}

while (($#)); do
    case "$1" in
        --no-upgrade) DO_UPGRADE=0 ;;
        --skip-build) DO_BUILD=0 ;;
        --reboot) DO_REBOOT=1 ;;
        --user)
            shift
            [[ $# -gt 0 ]] || { echo "ERROR: --user requires a username." >&2; exit 2; }
            TARGET_USER_OVERRIDE="$1"
            ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run with sudo: sudo ./pi-setup/install.sh" >&2
    exit 1
fi

if [[ -n "$TARGET_USER_OVERRIDE" ]]; then
    TARGET_USER="$TARGET_USER_OVERRIDE"
elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    TARGET_USER="$SUDO_USER"
else
    echo "ERROR: Could not determine desktop user. Use --user USER." >&2
    exit 1
fi

id "$TARGET_USER" >/dev/null 2>&1 || { echo "ERROR: User '$TARGET_USER' does not exist." >&2; exit 1; }
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "$TARGET_USER")"
TARGET_UID="$(id -u "$TARGET_USER")"
[[ -n "$TARGET_HOME" && "$TARGET_HOME" != "/" ]] || { echo "ERROR: Invalid home for $TARGET_USER" >&2; exit 1; }

STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="/var/log/mixxx-pi-install-${STAMP}.log"
touch "$LOG" && chmod 0644 "$LOG"
exec > >(tee -a "$LOG") 2>&1
trap 'rc=$?; echo; echo "ERROR: install.sh failed at line $LINENO (exit $rc)."; echo "Log: '"$LOG"'"; exit $rc' ERR

info() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '    [OK] %s\n' "$*"; }
warn() { printf '    [WARN] %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
as_user() { sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" USER="$TARGET_USER" LOGNAME="$TARGET_USER" "$@"; }
require_file() { [[ -f "$1" ]] || die "Required file missing: $1"; }
require_dir()  { [[ -d "$1" ]] || die "Required directory missing: $1"; }

info "Target"
echo "Repository : $REPO_ROOT"
echo "User       : $TARGET_USER"
echo "Home       : $TARGET_HOME"
echo "Log        : $LOG"

# ---- Preflight ------------------------------------------------------------
info "Preflight checks"
MODEL="$(tr -d '\0' </proc/device-tree/model 2>/dev/null || true)"
ARCH="$(uname -m)"
OS_CODENAME="$(. /etc/os-release 2>/dev/null; printf '%s' "${VERSION_CODENAME:-unknown}")"
echo "Model      : ${MODEL:-unknown}"
echo "Arch       : $ARCH"
echo "OS codename: $OS_CODENAME"
[[ "$MODEL" == *"Raspberry Pi 5"* ]] || die "This installer is intended for Raspberry Pi 5."
[[ "$ARCH" == "aarch64" ]] || die "Expected aarch64; found $ARCH."
[[ "$OS_CODENAME" == "bookworm" ]] || warn "Snapshot came from Bookworm; current OS is $OS_CODENAME."
pgrep -x mixxx >/dev/null 2>&1 && die "Mixxx is running. Quit it normally first."

require_dir "$SNAPSHOT"
require_file "$SNAPSHOT/sway/config"
require_dir "$SNAPSHOT/waybar"
require_file "$SNAPSHOT/mixxx/mixxx.cfg"
require_file "$SNAPSHOT/mixxx/controllers/Pioneer-DDJ-FLX6.midi.xml"
require_file "$SNAPSHOT/mixxx/controllers/Pioneer-DDJ-FLX6-script.js"
require_file "$SNAPSHOT/system/lightdm/lightdm.conf"
require_dir "$REPO_ROOT/cdj-customizations/skins/CDJDeere"
require_file "$REPO_ROOT/src/waveform/renderers/allshader/waveformrenderercdj.cpp"
require_file "$REPO_ROOT/src/waveform/widgets/allshader/cdjwaveformwidget.cpp"

if [[ -f "$SNAPSHOT/system/boot-config.txt" ]]; then
    BOOT_SNAPSHOT="$SNAPSHOT/system/boot-config.txt"
elif [[ -f "$SNAPSHOT/boot/config.txt" ]]; then
    BOOT_SNAPSHOT="$SNAPSHOT/boot/config.txt"
else
    die "No saved Raspberry Pi boot config found."
fi

grep -qE '^display_auto_detect=0([[:space:]]|$)' "$BOOT_SNAPSHOT" || die "Saved boot config lacks display_auto_detect=0."
grep -qE '^dtoverlay=vc4-kms-v3d([,[:space:]]|$)' "$BOOT_SNAPSHOT" || die "Saved boot config lacks vc4-kms-v3d."
grep -qE '^dtoverlay=vc4-kms-dsi-waveshare-panel-v2,9_0_inch_b([,[:space:]]|$)' "$BOOT_SNAPSHOT" || die "Saved boot config lacks Waveshare 9_0_inch_b overlay."
grep -qE '^ResizableSkin[[:space:]]+CDJDeere[[:space:]]*$' "$SNAPSHOT/mixxx/mixxx.cfg" || warn "Snapshot is not explicitly set to CDJDeere."
grep -qE '^WaveformType[[:space:]]+26[[:space:]]*$' "$SNAPSHOT/mixxx/mixxx.cfg" || warn "Snapshot is not explicitly set to WaveformType 26."

if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Git commit : $(git -C "$REPO_ROOT" rev-parse --short HEAD)"
    echo "Git branch : $(git -C "$REPO_ROOT" branch --show-current || true)"
fi
ok "Snapshot and custom Mixxx sources are present."

# ---- Backups --------------------------------------------------------------
info "Backing up files that may be replaced"
SYSTEM_BACKUP="/var/backups/mixxx-pi-setup/$STAMP"
USER_BACKUP="$TARGET_HOME/.mixxx-pi-setup-backup-$STAMP"
mkdir -p "$SYSTEM_BACKUP"
install -d -o "$TARGET_USER" -g "$TARGET_GROUP" "$USER_BACKUP"

backup_system_file() {
    local src="$1"
    if [[ -e "$src" ]]; then
        local dst="$SYSTEM_BACKUP$src"
        mkdir -p "$(dirname "$dst")"
        cp -a "$src" "$dst"
    fi
}
backup_user_path() {
    local src="$1"
    if [[ -e "$src" ]]; then
        local rel="${src#$TARGET_HOME/}"
        local dst="$USER_BACKUP/$rel"
        mkdir -p "$(dirname "$dst")"
        cp -a "$src" "$dst"
    fi
}

backup_system_file /boot/firmware/config.txt
backup_system_file /boot/config.txt
backup_system_file /etc/lightdm/lightdm.conf
backup_user_path "$TARGET_HOME/.config/sway"
backup_user_path "$TARGET_HOME/.config/waybar"
backup_user_path "$TARGET_HOME/wallpaper/wallpaper.jpg"
for f in mixxx.cfg effects.xml samplers.xml sandbox.cfg soundconfig.xml mixxxdb.sqlite; do
    backup_user_path "$TARGET_HOME/.mixxx/$f"
done
backup_user_path "$TARGET_HOME/.mixxx/controllers"
chown -R "$TARGET_USER:$TARGET_GROUP" "$USER_BACKUP"
echo "System backup: $SYSTEM_BACKUP"
echo "User backup  : $USER_BACKUP"

# ---- Packages -------------------------------------------------------------
info "Updating package metadata"
export DEBIAN_FRONTEND=noninteractive
apt-get update
if ((DO_UPGRADE)); then
    info "Applying full Raspberry Pi OS upgrade"
    apt-get full-upgrade -y
else
    warn "Skipping apt full-upgrade (--no-upgrade)."
fi

info "Installing desktop, Mixxx runtime, and build dependencies"
RUNTIME_PACKAGES=(
    alsa-utils ca-certificates curl git lightdm libinput-tools mixxx python3
    raspberrypi-ui-mods raspi-utils rsync sway swaybg waybar wlr-randr wvkbd
    xwayland foot fuzzel i3status fonts-droid-fallback fonts-font-awesome
    fonts-liberation2 fonts-open-sans fonts-ubuntu udisks2 udiskie udevil
)
BUILD_PACKAGES=()
if [[ -s "$PACKAGES_DIR/required.txt" ]]; then
    mapfile -t BUILD_PACKAGES < <(sed 's/[[:space:]]*#.*$//' "$PACKAGES_DIR/required.txt" | awk 'NF {print $1}' | sort -u)
elif [[ -s "$PACKAGES_DIR/apt-manual-full.txt" ]]; then
    mapfile -t BUILD_PACKAGES < <(
        grep -E '(^build-essential$|^cmake$|^ccache$|^clang-tidy$|^clazy$|^mold$|^pkg-config$|^gcc($|-)|^g\+\+($|-)|^protobuf-compiler$|.*-dev$|^libqt|^qt6|^qml6|^qt5keychain-dev$|^qtdeclarative5-dev$|^qtscript5-dev$|^lua5\.1$|^luajit$|^ffmpeg$)' "$PACKAGES_DIR/apt-manual-full.txt" | sort -u
    )
else
    warn "No saved package inventory; using fallback build dependencies."
    BUILD_PACKAGES=(
        build-essential ccache cmake libasound2-dev libavcodec-dev libavformat-dev
        libbenchmark-dev libchromaprint-dev libebur128-dev libfaad-dev libfftw3-dev
        libflac-dev libgl1-mesa-dev libglu1-mesa-dev libgtest-dev libhidapi-dev
        libid3tag0-dev libjack-dev liblilv-dev libmad0-dev libmodplug-dev
        libmp3lame-dev libmsgsl-dev libopus-dev libopusfile-dev libportmidi-dev
        libprotobuf-dev librubberband-dev libshout-dev libshout-idjc-dev
        libsndfile1-dev libsoundtouch-dev libsqlite3-dev libssl-dev libtag1-dev
        libudev-dev libupower-glib-dev libusb-1.0-0-dev libwavpack-dev lv2-dev
        mold pkg-config portaudio19-dev protobuf-compiler qt6-5compat-dev
        qt6-base-dev qt6-base-private-dev qt6-declarative-dev
        qt6-declarative-private-dev qt6-shadertools-dev qt6-svg-dev
        qtkeychain-qt6-dev
    )
fi
mapfile -t ALL_PACKAGES < <(printf '%s\n' "${RUNTIME_PACKAGES[@]}" "${BUILD_PACKAGES[@]}" | awk 'NF' | sort -u)
apt-get install -y "${ALL_PACKAGES[@]}"
ok "Required packages installed."

if command -v dtoverlay >/dev/null 2>&1; then
    if dtoverlay -h vc4-kms-dsi-waveshare-panel-v2 2>/dev/null | grep -q '9_0_inch_b'; then
        ok "Waveshare overlay supports 9_0_inch_b."
    else
        die "Installed Waveshare overlay does not advertise 9_0_inch_b."
    fi
else
    warn "dtoverlay command not found; overlay capability could not be queried."
fi

# ---- Boot/display ---------------------------------------------------------
info "Restoring Raspberry Pi display configuration"
if [[ -d /boot/firmware ]]; then BOOT_CONFIG="/boot/firmware/config.txt"; else BOOT_CONFIG="/boot/config.txt"; fi
install -m 0644 "$BOOT_SNAPSHOT" "$BOOT_CONFIG"
grep -qE '^display_auto_detect=0([[:space:]]|$)' "$BOOT_CONFIG"
grep -qE '^dtoverlay=vc4-kms-v3d([,[:space:]]|$)' "$BOOT_CONFIG"
grep -qE '^dtoverlay=vc4-kms-dsi-waveshare-panel-v2,9_0_inch_b([,[:space:]]|$)' "$BOOT_CONFIG"
ok "Waveshare boot configuration restored."

# ---- Sway/LightDM/Waybar --------------------------------------------------
info "Restoring LightDM, Sway, Waybar, and wallpaper"
install -d -m 0755 "$TARGET_HOME/.config/sway" "$TARGET_HOME/.config/waybar" "$TARGET_HOME/wallpaper"
rsync -a "$SNAPSHOT/sway/" "$TARGET_HOME/.config/sway/"
rsync -a "$SNAPSHOT/waybar/" "$TARGET_HOME/.config/waybar/"
[[ -f "$SNAPSHOT/assets/wallpaper.jpg" ]] && install -m 0644 "$SNAPSHOT/assets/wallpaper.jpg" "$TARGET_HOME/wallpaper/wallpaper.jpg"
install -m 0644 "$SNAPSHOT/system/lightdm/lightdm.conf" /etc/lightdm/lightdm.conf
python3 - "$TARGET_USER" <<'PY'
from pathlib import Path
import re, sys
user = sys.argv[1]
p = Path('/etc/lightdm/lightdm.conf')
t = p.read_text()
t = re.sub(r'(?m)^autologin-user=.*$', f'autologin-user={user}', t)
t = re.sub(r'(?m)^user-session=.*$', 'user-session=sway', t)
t = re.sub(r'(?m)^autologin-session=.*$', 'autologin-session=sway', t)
p.write_text(t)
PY
grep -qE "^autologin-user=${TARGET_USER}$" /etc/lightdm/lightdm.conf
grep -qE '^user-session=sway$' /etc/lightdm/lightdm.conf
grep -qE '^autologin-session=sway$' /etc/lightdm/lightdm.conf
[[ -f /usr/share/wayland-sessions/sway.desktop ]] || die "Sway session file is missing."
systemctl set-default graphical.target
systemctl enable lightdm >/dev/null
for group in audio video input render; do getent group "$group" >/dev/null && usermod -aG "$group" "$TARGET_USER"; done

# ---- Mixxx state ----------------------------------------------------------
info "Restoring Mixxx preferences and FLX6 mappings"
install -d -m 0755 "$TARGET_HOME/.mixxx"
rsync -a "$SNAPSHOT/mixxx/" "$TARGET_HOME/.mixxx/"
if [[ -f "$SCRIPT_DIR/private/mixxxdb.sqlite" ]]; then
    install -m 0644 "$SCRIPT_DIR/private/mixxxdb.sqlite" "$TARGET_HOME/.mixxx/mixxxdb.sqlite"
    echo "Restored private mixxxdb.sqlite."
fi
install -d -m 0755 "$TARGET_HOME/Music/Mixxx/Recordings"

# Rewrite only installed copies; keep the Git snapshot exact.
export REPO_ROOT TARGET_HOME
python3 - "$TARGET_HOME/.config/sway" "$TARGET_HOME/.config/waybar" "$TARGET_HOME/.mixxx" <<'PY'
from pathlib import Path
import os, sys
repo = os.environ['REPO_ROOT']
home = os.environ['TARGET_HOME']
for arg in sys.argv[1:]:
    root = Path(arg)
    if not root.exists():
        continue
    paths = [root] if root.is_file() else root.rglob('*')
    for p in paths:
        if not p.is_file() or p.suffix.lower() in {'.sqlite','.db','.png','.jpg','.jpeg','.gif','.so'}:
            continue
        try:
            raw = p.read_bytes()
            if b'\0' in raw:
                continue
            text = raw.decode('utf-8')
        except (UnicodeDecodeError, OSError):
            continue
        new = text.replace('/home/pi/src/mixxx-cdj', repo).replace('/home/pi', home)
        if p.name == 'mixxx.sh' and p.parent.name == 'waybar':
            custom = f'env QT_QPA_PLATFORM=xcb {repo}/build/mixxx --resource-path /usr/share/mixxx'
            new = new.replace('/usr/bin/mixxx', custom)
        if new != text:
            p.write_text(new)
PY
chmod +x "$TARGET_HOME/.config/waybar/"*.sh 2>/dev/null || true
chown -R "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.config/sway" "$TARGET_HOME/.config/waybar" "$TARGET_HOME/wallpaper" "$TARGET_HOME/.mixxx" "$TARGET_HOME/Music/Mixxx"
require_file "$TARGET_HOME/.mixxx/controllers/Pioneer-DDJ-FLX6.midi.xml"
require_file "$TARGET_HOME/.mixxx/controllers/Pioneer-DDJ-FLX6-script.js"
ok "Mixxx preferences and Pioneer DDJ-FLX6 mappings restored."

# ---- Build custom Mixxx ---------------------------------------------------
apply_djinterop_workaround() {
    local flags
    flags="$(find "$REPO_ROOT/build/libdjinterop-0.24.3" -path '*/CMakeFiles/DjInterop.dir/flags.make' -print -quit 2>/dev/null || true)"
    if [[ -z "$flags" ]]; then
        warn "libdjinterop flags.make not found; workaround not applied."
        return 0
    fi
    if ! grep -q -- '-Wno-error=stringop-overflow' "$flags"; then
        as_user sed -i 's/-Werror/-Werror -Wno-error=stringop-overflow/' "$flags"
    fi
    grep -q -- '-Wno-error=stringop-overflow' "$flags" && ok "Applied libdjinterop GCC workaround." || warn "Could not confirm libdjinterop workaround."
}

if ((DO_BUILD)); then
    info "Configuring custom Mixxx 2.5.6"
    as_user cmake -S "$REPO_ROOT" -B "$REPO_ROOT/build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DBUILD_TESTING=ON \
        -DBUILD_BENCH=ON
    apply_djinterop_workaround
    info "Building custom Mixxx"
    if ! as_user cmake --build "$REPO_ROOT/build" --target mixxx -j2; then
        warn "First build failed; reapplying libdjinterop workaround and retrying once."
        apply_djinterop_workaround
        as_user cmake --build "$REPO_ROOT/build" --target mixxx -j2
    fi
else
    warn "Skipping build (--skip-build)."
fi

CUSTOM_MIXXX="$REPO_ROOT/build/mixxx"
[[ -x "$CUSTOM_MIXXX" ]] || die "Custom Mixxx binary not found: $CUSTOM_MIXXX"
strings "$CUSTOM_MIXXX" | grep -qF 'CDJ 3Band' || die "Custom binary lacks CDJ 3Band marker."
strings "$CUSTOM_MIXXX" | grep -qF 'PreviousWaveformType' || die "Custom binary lacks automatic renderer marker."
ok "Custom Mixxx contains CDJ 3Band and automatic renderer selection."

# ---- Skin/resources -------------------------------------------------------
info "Installing CDJDeere skin link"
[[ -d /usr/share/mixxx ]] || die "/usr/share/mixxx is missing."
[[ -d /usr/share/mixxx/skins/Deere ]] || die "Stock Deere skin is missing."
ln -sfn "$REPO_ROOT/cdj-customizations/skins/CDJDeere" /usr/share/mixxx/skins/CDJDeere
[[ -L /usr/share/mixxx/skins/CDJDeere ]] || die "CDJDeere symlink was not created."
[[ "$(readlink -f /usr/share/mixxx/skins/CDJDeere)" == "$(readlink -f "$REPO_ROOT/cdj-customizations/skins/CDJDeere")" ]] || die "CDJDeere symlink points to wrong location."
ok "Stock Deere preserved; CDJDeere linked to repository skin."

# ---- Validate launch/config ----------------------------------------------
info "Validating Sway and Waybar launch configuration"
SWAY_CONFIG="$TARGET_HOME/.config/sway/config"
require_file "$SWAY_CONFIG"
grep -qF 'output DSI-2 transform 270 scale 1' "$SWAY_CONFIG" || die "Sway config lacks DSI-2 transform 270."
grep -qF 'input type:touch map_to_output DSI-2' "$SWAY_CONFIG" || die "Sway config lacks touch mapping to DSI-2."
grep -qF 'QT_QPA_PLATFORM=xcb' "$SWAY_CONFIG" || die "Sway does not launch Mixxx with xcb."
grep -qF "$CUSTOM_MIXXX" "$SWAY_CONFIG" || die "Sway does not point to custom Mixxx."
grep -qF 'for_window [class="Mixxx" instance="mixxx"] fullscreen enable' "$SWAY_CONFIG" || die "Sway lacks XWayland fullscreen rule."
if [[ -f "$TARGET_HOME/.config/waybar/mixxx.sh" ]]; then
    grep -qF "$CUSTOM_MIXXX" "$TARGET_HOME/.config/waybar/mixxx.sh" || die "Waybar Mixxx launcher does not point to custom binary."
fi
grep -qE '^ResizableSkin[[:space:]]+CDJDeere[[:space:]]*$' "$TARGET_HOME/.mixxx/mixxx.cfg" || warn "Installed mixxx.cfg is not explicitly CDJDeere."
grep -qE '^WaveformType[[:space:]]+26[[:space:]]*$' "$TARGET_HOME/.mixxx/mixxx.cfg" || warn "Installed mixxx.cfg is not explicitly WaveformType 26."

if [[ "$TARGET_HOME" != "/home/pi" ]]; then
    if grep -RIl '/home/pi' "$TARGET_HOME/.config/sway" "$TARGET_HOME/.config/waybar" "$TARGET_HOME/.mixxx" --exclude='*.sqlite' 2>/dev/null | grep -q .; then
        warn "Some installed text configuration still contains /home/pi."
    else
        ok "Captured /home/pi paths were rewritten for $TARGET_HOME."
    fi
fi

# ---- Final/live validation ------------------------------------------------
info "Final validation"
echo "Stock Mixxx package:"
dpkg-query -W -f='  ${Package} ${Version}\n' mixxx 2>/dev/null || true
echo "Custom Mixxx: $CUSTOM_MIXXX"
echo "Skin        : /usr/share/mixxx/skins/CDJDeere -> $(readlink -f /usr/share/mixxx/skins/CDJDeere)"
echo "FLX6 mapping : $TARGET_HOME/.mixxx/controllers/Pioneer-DDJ-FLX6.midi.xml"

SWAYSOCK_PATH="$(ls -t "/run/user/$TARGET_UID"/sway-ipc.*.sock 2>/dev/null | head -1 || true)"
if [[ -n "$SWAYSOCK_PATH" ]]; then
    info "Running Sway session detected; checking current display"
    OUTPUTS="$(as_user env SWAYSOCK="$SWAYSOCK_PATH" swaymsg -t get_outputs 2>/dev/null || true)"
    if grep -q 'Output DSI-2' <<<"$OUTPUTS"; then
        ok "Sway currently sees DSI-2."
        grep -A12 'Output DSI-2' <<<"$OUTPUTS" | grep -q 'Current mode: 720x1280' && ok "DSI-2 native mode is 720x1280." || warn "Could not confirm DSI-2 mode 720x1280."
        grep -A15 'Output DSI-2' <<<"$OUTPUTS" | grep -q 'Transform: 270' && ok "DSI-2 Sway transform is 270." || warn "Could not confirm transform 270."
    else
        warn "Current Sway session does not report DSI-2; reboot may be required."
    fi
else
    echo "No running Sway IPC socket found; live display checks will occur after reboot/login."
fi

info "Installation complete"
cat <<EOF2

Expected boot chain:
  LightDM autologin
    -> Sway
    -> workspace 1:Mixxx
    -> QT_QPA_PLATFORM=xcb
    -> $CUSTOM_MIXXX
    -> fullscreen XWayland Mixxx

Expected display:
  Waveshare 9-DSI-TOUCH-B
  native 720x1280
  transform 270
  effective landscape 1280x720
  Goodix touch mapped to DSI-2

Backups:
  System: $SYSTEM_BACKUP
  User  : $USER_BACKUP

Log:
  $LOG

Not cloned by design:
  Wi-Fi credentials, SSH keys/host keys, hostname, /etc/machine-id,
  browser/account secrets.

Private Mixxx library DB is restored only if present at:
  $SCRIPT_DIR/private/mixxxdb.sqlite
EOF2

if ((DO_REBOOT)); then
    info "Rebooting"
    sync
    systemctl reboot
else
    echo
    echo "Reboot when ready:"
    echo "  sudo reboot"
fi
