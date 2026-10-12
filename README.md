# LXQt Mods

A small, reproducible setup for a clean, dark LXQt desktop on Fedora. It installs
Spotify and Helium, sets Helium as the default browser, applies the
Modern-Minimal theme and wallpaper, moves the panel to the left edge, and saves
a side-by-side laptop/external-monitor layout for Miriway.

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

The display profile is for the laptop/display setup this was created on:
`eDP-1` at 1920x1080 with a `DP-2` monitor at 3440x1440 to its right. If your
connector names or resolutions differ, edit `config/miriway-shell.display-config`
before deploying.

## Applying changes

LXQt panel, wallpaper, and Miriway display configuration are read when their
components start. Log out and back in after deployment (or restart the relevant
desktop components) to apply all changes. The external display must be
connected when Miriway starts.

The theme uses a graphite background, high-contrast text, a muted teal accent,
Breeze Dark icons, and a restrained geometric wallpaper. Main settings live in
`config/`; the custom theme and wallpaper are under `assets/`.

## Notes

- Helium is installed per-user at `~/Applications/helium.AppImage`.
- Spotify is installed per-user as the Flathub Flatpak `com.spotify.Client`.
- Existing LXQt and PCManFM settings are backed up before deployment.
- Run `./deploy.sh` again to reapply settings and update Helium.