# LXQt Mods

A small, reproducible setup for a custom dark LXQt desktop on Fedora. It installs
Spotify and Helium, sets Helium as the default browser, applies the
Modern-Minimal-Dark theme and wallpaper, moves the panel to the left edge, and
adds live display-mode switching for Miriway.

## Deploy

From a fresh Fedora LXQt install with an active Miriway session:

```sh
git clone https://github.com/sidsridhar0/lxqtmods.git
cd lxqtmods
./deploy.sh
```

The script installs Spotify from Flathub and downloads the current stable
x86_64 Helium AppImage from Helium's official release metadata. It changes
settings in your home directory and does not require root access.

Press **F7** to cycle from extended screens to laptop-only, external-only,
duplicated, then extended screens again. Miriway applies each mode live and
shows a notification. The saved display profile matches the setup this was
created on: `eDP-1` at 1920x1080 and `DisplayPort-1` (the kernel's `DP-1`
connector) at 3440x1440. If your connector names or resolutions differ, edit
`config/miriway-shell.display-config` before deploying.

## Applying changes

The F7 display-mode shortcut and monitor profiles apply live. Log out and back
in after deployment to apply the theme, wallpaper, and panel changes.

The theme adapts the reference dotfiles' rounded panels, bold outlines, mint
accents, and monospaced typography to a dark graphite palette. Main settings
live in `config/`; the custom Qt/GTK styles and wallpaper are under `assets/`.

## Notes

- Helium is installed per-user at `~/Applications/helium.AppImage`.
- Spotify is installed per-user as the Flathub Flatpak `com.spotify.Client`.
- Existing LXQt and PCManFM settings are backed up before deployment.
- `~/.config/miriway-shell.display-config-layout` stores the active F7 profile.
- Run `./deploy.sh` again to reapply settings and update Helium.