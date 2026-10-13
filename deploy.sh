#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$EUID" -eq 0 ]]; then
    if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then
        deploy_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
        exec sudo -u "$SUDO_USER" -- env -u SUDO_USER HOME="$deploy_home" \
            "$ROOT/deploy.sh" "$@"
    fi
    printf 'Do not run deploy.sh as root; run ./deploy.sh from your user account.\n' >&2
    exit 1
fi

DEPLOY_USER="$(id -un)"
APP_DIR="$HOME/Applications"
DATA_DIR="$HOME/.local/share"
CONFIG_DIR="$HOME/.config"

for command in curl flatpak gio python3; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "$command" >&2
        exit 1
    fi
done

python3 -c 'import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gtk' || {
    printf 'GTK 3 Python bindings are required (python3-gobject).\n' >&2
    exit 1
}

backup_once() {
    local file="$1"
    if [[ -f "$file" && ! -e "$file.lxqtmods.bak" ]]; then
        cp -a -- "$file" "$file.lxqtmods.bak"
    fi
}

merge_ini() {
    local target="$1"
    local source="$2"
    backup_once "$target"
    python3 - "$target" "$source" <<'PY'
import configparser
import os
import sys

target, source = sys.argv[1:]
config = configparser.ConfigParser(interpolation=None)
config.optionxform = str
config.read(target, encoding="utf-8")

incoming = configparser.ConfigParser(interpolation=None)
incoming.optionxform = str
with open(source, encoding="utf-8") as stream:
    incoming.read_file(stream)

for section in incoming.sections():
    if not config.has_section(section):
        config.add_section(section)
    for key, value in incoming.items(section):
        config.set(section, key, os.path.expandvars(value))

os.makedirs(os.path.dirname(target), exist_ok=True)
with open(target, "w", encoding="utf-8") as stream:
    config.write(stream, space_around_delimiters=False)
PY
}

merge_ini "$CONFIG_DIR/lxqt/lxqt.conf" "$ROOT/config/lxqt.conf"
merge_ini "$CONFIG_DIR/lxqt/panel.conf" "$ROOT/config/panel.conf"
merge_ini "$CONFIG_DIR/pcmanfm-qt/lxqt/settings.conf" "$ROOT/config/pcmanfm-settings.conf"
merge_ini "$CONFIG_DIR/gtk-3.0/settings.ini" "$ROOT/config/gtk-settings.ini"

install -d "$DATA_DIR/lxqt/themes/Modern-Minimal" "$DATA_DIR/backgrounds"
install -m 644 "$ROOT/assets/Modern-Minimal/lxqt-panel.qss" \
    "$DATA_DIR/lxqt/themes/Modern-Minimal/lxqt-panel.qss"
install -m 644 "$ROOT/assets/Modern-Minimal/lxqt-runner.qss" \
    "$DATA_DIR/lxqt/themes/Modern-Minimal/lxqt-runner.qss"
install -m 644 "$ROOT/assets/Modern-Minimal/lxqt-notificationd.qss" \
    "$DATA_DIR/lxqt/themes/Modern-Minimal/lxqt-notificationd.qss"
install -m 644 "$ROOT/assets/Modern-Minimal/lxqt-config.qss" \
    "$DATA_DIR/lxqt/themes/Modern-Minimal/lxqt-config.qss"
install -m 644 "$ROOT/assets/modern-minimal.svg" "$DATA_DIR/backgrounds/modern-minimal.svg"
install -D -m 644 "$ROOT/assets/Modern-Minimal-Dark/index.theme" \
    "$DATA_DIR/themes/Modern-Minimal-Dark/index.theme"
install -D -m 644 "$ROOT/assets/Modern-Minimal-Dark/gtk-3.0/gtk.css" \
    "$DATA_DIR/themes/Modern-Minimal-Dark/gtk-3.0/gtk.css"
install -D -m 755 "$ROOT/display-mode.sh" "$HOME/.local/bin/lxqtmods-display-mode"
install -D -m 755 "$ROOT/widgets/dashboard.py" "$DATA_DIR/lxqtmods/dashboard.py"
install -d "$DATA_DIR/applications"
cat > "$DATA_DIR/applications/lxqtmods-dashboard.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Desktop widgets
Comment=System meters, volume, battery profile, and todo list
Exec=python3 "$DATA_DIR/lxqtmods/dashboard.py" --desktop
Icon=utilities-system-monitor
Terminal=false
Categories=System;
StartupWMClass=lxqtmods-dashboard
EOF

display_config="$CONFIG_DIR/miriway-shell.display-config"
backup_once "$display_config"
install -D -m 644 "$ROOT/config/miriway-shell.display-config" "$display_config"

display_layout="$display_config-layout"
backup_once "$display_layout"
printf 'extended\n' > "$display_layout"

display_mode_script="$HOME/.local/bin/lxqtmods-display-mode"
settings_file="$CONFIG_DIR/lxqt/miriway-shell.settings"
backup_once "$settings_file"
python3 - "$settings_file" "$display_mode_script" <<'PY'
import os
import shlex
import sys
import tempfile

settings_file, script = sys.argv[1:]
os.makedirs(os.path.dirname(settings_file), exist_ok=True)
try:
    with open(settings_file, encoding="utf-8") as stream:
        lines = stream.read().splitlines()
except FileNotFoundError:
    lines = []

lines = [line for line in lines if not line.startswith("command_shell_plain=F7:")]
lines.append(f"command_shell_plain=F7:{shlex.quote(script)}")
for key in (
    "pointer_vertical_scroll_speed",
    "pointer_horizontal_scroll_speed",
    "touchpad_vertical_scroll_speed",
    "touchpad_horizontal_scroll_speed",
):
    lines = [line for line in lines if not line.lstrip("#").startswith(f"{key}=")]
    lines.append(f"{key}=-1")

fd, temporary_file = tempfile.mkstemp(dir=os.path.dirname(settings_file))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        stream.write("\n".join(lines) + "\n")
    os.replace(temporary_file, settings_file)
except BaseException:
    os.unlink(temporary_file)
    raise
PY

miriway_config="$CONFIG_DIR/lxqt/miriway-shell.config"
backup_once "$miriway_config"
python3 - "$miriway_config" "$DATA_DIR/lxqtmods/dashboard.py" <<'PY'
import os
import shlex
import sys
import tempfile

config_file, dashboard = sys.argv[1:]
os.makedirs(os.path.dirname(config_file), exist_ok=True)
try:
    with open(config_file, encoding="utf-8") as stream:
        lines = stream.read().splitlines()
except FileNotFoundError:
    lines = []

lines = [
    line for line in lines
    if not (
        line.startswith("shell-component=")
        and "lxqtmods/dashboard.py" in line
    )
]
lines.append(
    "shell-component="
    + shlex.join(["python3", dashboard, "--desktop"])
)

fd, temporary_file = tempfile.mkstemp(dir=os.path.dirname(config_file))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        stream.write("\n".join(lines) + "\n")
    os.replace(temporary_file, config_file)
except BaseException:
    os.unlink(temporary_file)
    raise
PY

install -D -m 755 "$ROOT/widgets/touchpad-gestures.py" \
    "$HOME/.local/bin/lxqtmods-touchpad-gestures"
install -D -m 644 "$ROOT/systemd/user/lxqtmods-gestures.service" \
    "$CONFIG_DIR/systemd/user/lxqtmods-gestures.service"

mkdir -p "$APP_DIR"
release_url="$(
    curl -fsSL https://files.helium.computer/releases.json |
        python3 -c 'import json,sys; print(json.load(sys.stdin)["linux"]["stable"]["x86_64"])'
)"
temporary_app="$(mktemp "$APP_DIR/helium.AppImage.XXXXXX")"
trap 'rm -f -- "$temporary_app"' EXIT
curl -fL --retry 2 "$release_url" -o "$temporary_app"
chmod 755 "$temporary_app"
mv -f -- "$temporary_app" "$APP_DIR/helium.AppImage"
trap - EXIT

python3 - "$HOME" "$DATA_DIR" <<'PY'
import os
import sys

home, data_dir = sys.argv[1:]
applications = os.path.join(home, ".local", "share", "applications")
os.makedirs(applications, exist_ok=True)
app = os.path.join(home, "Applications", "helium.AppImage")
exec_path = app.replace("\\", "\\\\").replace('"', '\\"')
entry = f"""[Desktop Entry]
Version=1.0
Type=Application
Name=Helium
Comment=Browse the web
Exec="{exec_path}" %U
Icon=web-browser
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupWMClass=helium
"""
with open(os.path.join(applications, "helium.desktop"), "w", encoding="utf-8") as stream:
    stream.write(entry)
PY

gio mime text/html helium.desktop
gio mime application/xhtml+xml helium.desktop
gio mime x-scheme-handler/http helium.desktop
gio mime x-scheme-handler/https helium.desktop

flatpak remote-add --user --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user --noninteractive --assumeyes flathub com.spotify.Client

if command -v sudo >/dev/null 2>&1 && [[ -t 0 ]]; then
    sudo dnf install -y gtk-layer-shell power-profiles-daemon wtype
    sudo systemctl enable --now power-profiles-daemon.service
    if ! getent group input | cut -d: -f4 | tr ',' '\n' | grep -Fxq "$DEPLOY_USER"; then
        sudo usermod --append --groups input "$DEPLOY_USER"
    fi
    sddm_theme_dir=/usr/share/sddm/themes/Modern-Minimal
    sddm_dropin=/etc/sddm.conf.d/90-lxqtmods.conf
    if sudo test -d "$sddm_theme_dir" && ! sudo test -e "$sddm_theme_dir.lxqtmods.bak"; then
        sudo cp -a -- "$sddm_theme_dir" "$sddm_theme_dir.lxqtmods.bak"
    fi
    if sudo test -f "$sddm_dropin" && ! sudo test -e "$sddm_dropin.lxqtmods.bak"; then
        sudo cp -a -- "$sddm_dropin" "$sddm_dropin.lxqtmods.bak"
    fi
    sudo install -d "$sddm_theme_dir"
    sudo install -m 644 "$ROOT/assets/sddm/Modern-Minimal/Main.qml" \
        "$sddm_theme_dir/Main.qml"
    sudo install -m 644 "$ROOT/assets/sddm/Modern-Minimal/theme.conf" \
        "$sddm_theme_dir/theme.conf"
    sudo install -D -m 644 "$ROOT/config/sddm.conf" \
        "$sddm_dropin"
else
    printf '\nSystem setup was skipped: run deploy.sh from a terminal with sudo access to install\n' >&2
    printf 'the Power Profiles and layer-shell packages, enable touchpad gestures, and apply\n' >&2
    printf 'the custom SDDM login theme.\n' >&2
fi

systemctl --user daemon-reload
systemctl --user enable lxqtmods-gestures.service

printf '\nSetup installed. Log out and back in to show the desktop widget, apply panel settings,\n'
printf 'and activate three-finger gestures. Gesture support reads input events from all devices;\n'
printf 'the account must be in the input group, and that access takes effect after logging back in.\n'
printf 'Press F7 to cycle display modes; the extended layout is active by default.\n'
printf 'Open Desktop widgets from the left sidebar for CPU/RAM, volume, battery, and todos.\n'
