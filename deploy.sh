#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$HOME/Applications"
DATA_DIR="$HOME/.local/share"
CONFIG_DIR="$HOME/.config"

for command in curl flatpak gio python3; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "$command" >&2
        exit 1
    fi
done

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

fd, temporary_file = tempfile.mkstemp(dir=os.path.dirname(settings_file))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        stream.write("\n".join(lines) + "\n")
    os.replace(temporary_file, settings_file)
except BaseException:
    os.unlink(temporary_file)
    raise
PY

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

printf '\nSetup installed. Log out and back in to apply the theme and panel changes.\n'
printf 'Press F7 to cycle display modes; the extended layout is active by default.\n'
