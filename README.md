# LXQt Mods

A small, reproducible setup for a custom dark LXQt desktop on Fedora. It installs
Spotify and Helium, sets Helium as the default browser, applies the
Modern-Minimal-Dark theme and wallpaper, moves the panel to the left edge, and
adds live display-mode switching for Miriway. The left Quick Launch also pins
Helium, Visual Studio Code, Spotify, and a custom widgets dashboard.

## Deploy

From a fresh Fedora LXQt install with an active Miriway session:

```sh
git clone https://github.com/sidsridhar0/lxqtmods.git
cd lxqtmods
./deploy.sh
```

The script installs Spotify from Flathub and downloads the current stable
x86_64 Helium AppImage from Helium's official release metadata. User settings
are installed in your home directory. Run it from a terminal with sudo access
to install GTK layer-shell, wtype, Power Profiles, and the custom SDDM login
theme, and to enable touchpad gesture input.

Press **F7** to cycle from extended screens to laptop-only, external-only,
duplicated, then extended screens again. Miriway applies each mode live and
shows a notification. The saved display profile matches the setup this was
created on: `eDP-1` at 1920x1080 and an external DisplayPort monitor at
3440x1440. The profiles accept either `DisplayPort-1` or `DisplayPort-2`
(kernel `DP-1`/`DP-2`) for the external display. If your connector names or
resolutions differ, edit `config/miriway-shell.display-config` before deploying.

## Applying changes

The F7 display-mode shortcut and monitor profiles apply live. Log out and back
in after deployment to apply the theme, wallpaper, and panel changes.

The theme adapts the reference dotfiles' rounded panels, bold outlines, mint
accents, and monospaced typography to a dark graphite palette. Main settings
live in `config/`; the custom Qt/GTK styles and wallpaper are under `assets/`.

The dashboard is pinned to the top-left desktop and starts with Miriway. It
uses the top layer so the desktop surface cannot cover it; it can remain above
application windows. It shows live CPU and memory usage, an equalizer-style
master-volume meter with a draggable volume slider, battery charge and status,
and a persistent checklist.
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
switcher. This needs `wtype`, a libinput gesture monitor, and access to input
devices by adding the account to the `input` group. That permission covers all
input devices, not only the touchpad. Log out and back in after deployment for
the group membership to take effect.

Mouse and touchpad scrolling are configured as reversed (natural) scrolling in
both axes.

The optional SDDM theme uses a dark graphite surface and mint accents. It is
installed under `/usr/share/sddm/themes/Modern-Minimal` and selected by
`/etc/sddm.conf.d/90-lxqtmods.conf`; the change applies at the next greeter
start. These system-level steps are skipped with a clear message when deploy
is run non-interactively.

## Notes

- Helium is installed per-user at `~/Applications/helium.AppImage`.
- Spotify is installed per-user as the Flathub Flatpak `com.spotify.Client`.
- Existing LXQt and PCManFM settings are backed up before deployment.
- Helium, Visual Studio Code, Spotify, and Desktop widgets are pinned in the
  left Quick Launch.
- `~/.config/miriway-shell.display-config-layout` stores the active F7 profile.
- Run `./deploy.sh` again to reapply settings and update Helium.