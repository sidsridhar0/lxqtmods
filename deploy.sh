#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$EUID" -eq 0 ]]; then
    if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then
        user_record="$(getent passwd "$SUDO_USER")"
        deploy_uid="$(cut -d: -f3 <<<"$user_record")"
        deploy_home="$(cut -d: -f6 <<<"$user_record")"
        runtime_dir="/run/user/$deploy_uid"
        if [[ ! -S "$runtime_dir/bus" ]]; then
            printf 'No user-session bus found at %s/bus. Log in as %s and retry.\n' \
                "$runtime_dir" "$SUDO_USER" >&2
            exit 1
        fi
        exec sudo -u "$SUDO_USER" -- env -u SUDO_USER \
            HOME="$deploy_home" \
            XDG_RUNTIME_DIR="$runtime_dir" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus" \
            "$ROOT/deploy.sh" "$@"
    fi
    printf 'Do not run deploy.sh as root; run ./deploy.sh from your user account.\n' >&2
    exit 1
fi

DEPLOY_USER="$(id -un)"
APP_DIR="$HOME/Applications"
DATA_DIR="$HOME/.local/share"
CONFIG_DIR="$HOME/.config"

if ! command -v python3 >/dev/null 2>&1; then
    printf 'Required command not found: python3\n' >&2
    exit 1
fi

warn() {
    printf '%s\n' "$*" >&2
}

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
install -d "$DATA_DIR/applications" "$CONFIG_DIR/autostart"
dashboard_desktop="$DATA_DIR/applications/lxqtmods-dashboard.desktop"
cat > "$dashboard_desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Desktop widgets
Comment=Desktop stats overlay, volume, battery profile, and todo list
Exec=python3 "$DATA_DIR/lxqtmods/dashboard.py" --desktop
Icon=utilities-system-monitor
Terminal=false
Categories=System;
StartupWMClass=lxqtmods-dashboard
OnlyShowIn=LXQt;
EOF
install -m 644 "$dashboard_desktop" "$CONFIG_DIR/autostart/lxqtmods-dashboard.desktop"

display_config="$CONFIG_DIR/miriway-shell.display-config"
backup_once "$display_config"
python3 "$ROOT/generate-display-config.py" "$display_config" \
    --fallback "$ROOT/config/miriway-shell.display-config" \
    || install -D -m 644 "$ROOT/config/miriway-shell.display-config" "$display_config"

display_layout="$display_config-layout"
backup_once "$display_layout"
if [[ ! -f "$display_layout" ]] \
        || grep -qxE 'extended|side_by_side|default' "$display_layout"; then
    printf 'first-screen\n' > "$display_layout"
fi

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
python3 - "$miriway_config" <<'PY'
import os
import sys
import tempfile

config_file = sys.argv[1]
try:
    with open(config_file, encoding="utf-8") as stream:
        lines = stream.read().splitlines()
except FileNotFoundError:
    raise SystemExit(0)

filtered = [
    line for line in lines
    if not (
        line.startswith("shell-component=")
        and "lxqtmods/dashboard.py" in line
    )
]
if filtered == lines:
    raise SystemExit(0)

fd, temporary_file = tempfile.mkstemp(dir=os.path.dirname(config_file))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        stream.write("\n".join(filtered) + "\n")
    os.replace(temporary_file, config_file)
except BaseException:
    os.unlink(temporary_file)
    raise
PY

install -D -m 755 "$ROOT/widgets/touchpad-gestures.py" \
    "$HOME/.local/bin/lxqtmods-touchpad-gestures"
install -D -m 644 "$ROOT/systemd/user/lxqtmods-gestures.service" \
    "$CONFIG_DIR/systemd/user/lxqtmods-gestures.service"

install_helium() {
    command -v curl >/dev/null 2>&1 || {
        warn "curl is not installed; skipping Helium."
        return 1
    }
    mkdir -p "$APP_DIR" || return 1
    local release_url temporary_app
    if ! release_url="$(
        curl -fsSL https://files.helium.computer/releases.json |
            python3 -c 'import json,sys; print(json.load(sys.stdin)["linux"]["stable"]["x86_64"])'
    )"; then
        return 1
    fi
    temporary_app="$(mktemp "$APP_DIR/helium.AppImage.XXXXXX")" || return 1
    if ! curl -fL --retry 2 "$release_url" -o "$temporary_app"; then
        rm -f -- "$temporary_app"
        return 1
    fi
    chmod 755 "$temporary_app" || { rm -f -- "$temporary_app"; return 1; }
    mv -f -- "$temporary_app" "$APP_DIR/helium.AppImage" || {
        rm -f -- "$temporary_app"
        return 1
    }
    python3 - "$HOME" <<'PY' || return 1
import os
import sys

home = sys.argv[1]
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
    if command -v gio >/dev/null 2>&1; then
        gio mime text/html helium.desktop
        gio mime application/xhtml+xml helium.desktop
        gio mime x-scheme-handler/http helium.desktop
        gio mime x-scheme-handler/https helium.desktop
    fi
}

install_helium || warn "Helium install skipped; desktop session settings were still applied."

if command -v flatpak >/dev/null 2>&1; then
    flatpak remote-add --user --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo \
        || warn "Could not add the Flathub remote."
    flatpak install --user --noninteractive --assumeyes flathub com.spotify.Client \
        || warn "Spotify install skipped."
else
    warn "flatpak is not installed; skipping Spotify."
fi

restore_sddm_default() {
    local sddm_theme_dir=/usr/share/sddm/themes/Modern-Minimal
    local sddm_dropin=/etc/sddm.conf.d/90-lxqtmods.conf
    if sudo test -e "$sddm_dropin.lxqtmods.bak"; then
        sudo mv -- "$sddm_dropin.lxqtmods.bak" "$sddm_dropin"
    elif sudo test -f "$sddm_dropin"; then
        sudo rm -f -- "$sddm_dropin"
    fi
    if sudo test -e "$sddm_theme_dir.lxqtmods.bak"; then
        sudo rm -rf -- "$sddm_theme_dir"
        sudo mv -- "$sddm_theme_dir.lxqtmods.bak" "$sddm_theme_dir"
    elif sudo test -f "$sddm_theme_dir/metadata.desktop" \
            && sudo grep -q '^Theme-Id=Modern-Minimal$' "$sddm_theme_dir/metadata.desktop"; then
        sudo rm -rf -- "$sddm_theme_dir"
    fi
}

if command -v sudo >/dev/null 2>&1 && [[ -t 0 ]]; then
    sudo dnf install -y gtk-layer-shell power-profiles-daemon wtype \
        || warn "Optional package install failed; continuing with session settings."
    sudo systemctl enable --now power-profiles-daemon.service \
        || warn "Could not enable power-profiles-daemon."
    if ! getent group input | cut -d: -f4 | tr ',' '\n' | grep -Fxq "$DEPLOY_USER"; then
        sudo usermod --append --groups input "$DEPLOY_USER" \
            || warn "Could not add $DEPLOY_USER to the input group."
    fi
    restore_sddm_default || warn "Could not restore the distro SDDM greeter."
else
    warn "System setup was skipped: run deploy.sh from a terminal with sudo access to install"
    warn "Power Profiles, layer-shell, and touchpad gesture packages."
    warn "If graphical login is broken, remove /etc/sddm.conf.d/90-lxqtmods.conf from a TTY."
fi

systemctl --user disable --now lxqtmods-gestures.service >/dev/null 2>&1 || true
systemctl --user daemon-reload || warn "Could not reload user systemd units."
systemctl --user enable lxqtmods-gestures.service \
    || warn "Could not enable the gesture service."
if systemctl --user is-active --quiet graphical-session.target; then
    systemctl --user start lxqtmods-gestures.service || warn "Gesture service will start at the next login."
fi

printf '\nSetup installed. Log out and back in to apply panel settings and start the desktop widget.\n'
printf 'The Fedora SDDM greeter is left in place so a custom login theme cannot lock you out.\n'
printf 'Displays default to the laptop screen; press F7 after login to add a detected external monitor.\n'
printf 'Three-finger swipe up opens the window switcher. That service only watches touchpad devices\n'
printf 'and starts with the graphical session. Input-group membership takes effect after logging back in.\n'
printf 'The panel Desktop widgets shortcut opens volume, power, and todos; the wallpaper overlay stays on the desktop.\n'
