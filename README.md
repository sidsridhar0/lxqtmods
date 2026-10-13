# LXQt Mods

A small, reproducible setup for a custom dark LXQt desktop on Fedora. It installs
Spotify and Helium, sets Helium as the default browser, applies the
Modern-Minimal-Dark theme and wallpaper, moves the panel to the left edge, and
adds live display-mode switching for Miriway. The left Quick Launch also pins
Helium, Visual Studio Code, Spotify, and a custom widgets dashboard.

Session extras are kept off the login and compositor critical path: the Fedora
SDDM greeter is left unchanged, displays default to the laptop screen, and the
desktop widget starts after the session is up.

## Deploy

From a fresh Fedora LXQt install with an active Miriway session:

```sh
git clone https://github.com/sidsridhar0/lxqtmods.git
cd lxqtmods
./deploy.sh
```

The script installs Spotify from Flathub and downloads the current stable
x86_64 Helium AppImage from Helium's official release metadata. Those app
installs are optional: a download failure does not roll back desktop settings.
User settings are installed in your home directory. Run it from a terminal with
sudo access to install GTK layer-shell, wtype, and Power Profiles, and to
enable touchpad gesture input.

If an earlier deploy selected the custom login theme and graphical login fails,
run `./deploy.sh` from a TTY with sudo access, or delete
`/etc/sddm.conf.d/90-lxqtmods.conf` and reboot.

Press **F7** after login to cycle from laptop-only to external-only, then
extended screens. Duplicate mode uses the same extended layout so it never
forces a guessed resolution onto a monitor. Deploy writes a display profile
from currently connected outputs and only enables one external display. The
login layout is the laptop screen. If connector probing fails, a laptop-only
fallback is installed.

## Applying changes

The F7 display-mode shortcut and monitor profiles apply live. Log out and back
in after deployment to apply the theme, wallpaper, and panel changes.

The theme adapts the reference dotfiles' rounded panels, bold outlines, mint
accents, and monospaced typography to a dark graphite palette. Main settings
live in `config/`; the custom Qt/GTK styles and wallpaper are under `assets/`.

The dashboard is pinned to the top-left desktop and starts from LXQt autostart
after the session is up, so a widget failure cannot take down Miriway. It waits
until a monitor is present, then uses the top layer so the desktop surface
cannot cover it; it can remain above application windows. It shows live CPU
and memory usage, an equalizer-style master-volume meter with a draggable
volume slider, battery charge and status, and a persistent checklist.
If PipeWire has not created a default audio sink yet at login, the dashboard
still opens and retries volume synchronization.
The battery action switches between Balanced and Power Saver profiles; the
deployment script installs and enables `power-profiles-daemon` for this feature.
Todo items are saved under `~/.local/state/lxqtmods/todos.json`. This is a
persistent, interactive desktop widget—not a sidebar app that must be opened.
The left-panel **Desktop widgets** shortcut is only a fallback to show it again
if it is closed.

The left panel groups open windows by application instead of showing a
separate task button for every window. Hover over a group to choose one of its
open windows. Miriway also provides the built-in <kbd>Alt</kbd>+<kbd>Tab</kbd>
application switcher and <kbd>Alt</kbd>+<kbd>Grave</kbd> window switcher.

The deploy script configures a three-finger swipe up to open Miriway's window
switcher. This needs `wtype`, a libinput gesture monitor, and access to
touchpad event nodes by adding the account to the `input` group. The monitor
opens only touchpad devices and starts with the graphical session, not at
user-login on a TTY. Log out and back in after deployment for the group
membership to take effect.

Mouse and touchpad scrolling are configured as reversed (natural) scrolling in
both axes.

Login uses the distro SDDM greeter. A custom theme is not selected, so a QML
error cannot block sign-in.

## Notes

- Helium is installed per-user at `~/Applications/helium.AppImage`.
- Spotify is installed per-user as the Flathub Flatpak `com.spotify.Client`.
- Existing LXQt and PCManFM settings are backed up before deployment.
- Helium, Visual Studio Code, Spotify, and Desktop widgets are pinned in the
  left Quick Launch.
- `~/.config/miriway-shell.display-config-layout` stores the active F7 profile.
- Run `./deploy.sh` again to reapply settings and update Helium.
