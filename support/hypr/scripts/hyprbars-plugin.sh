#!/usr/bin/env bash
set -euo pipefail

URL=https://github.com/hyprwm/hyprland-plugins.git
NAME=hyprbars
DIR="${XDG_DATA_HOME:-$HOME/.local/share}/lucid/plugins"
SO="$DIR/$NAME.so"
STAMP="$DIR/$NAME.abi"
TMP_DIR=""

say()  { printf '%s\n' "$*"; }
die()  { printf 'hyprbars-plugin: %s\n' "$*" >&2; exit 1; }

version_h() {
    local flag dir file
    for flag in $(pkg-config --cflags-only-I hyprland 2>/dev/null); do
        dir="${flag#-I}"
        for file in "$dir/version.h" "$dir/src/version.h" "$dir/hyprland/src/version.h"; do
            [[ -f "$file" ]] && { printf '%s\n' "$file"; return 0; }
        done
    done
    return 1
}

header_abi() {
    local header
    header=$(version_h) || return 1
    awk -F'"' '
        function mm(v) { sub(/\.[^.]*$/, "", v); return v }
        /define GIT_COMMIT_HASH/      { c = $2 }
        /define AQUAMARINE_VERSION /  { aq = mm($2) }
        /define HYPRUTILS_VERSION/    { hu = mm($2) }
        /define HYPRGRAPHICS_VERSION/ { hg = mm($2) }
        /define HYPRCURSOR_VERSION/   { hc = mm($2) }
        /define HYPRLANG_VERSION/     { hlg = mm($2) }
        END { print c "_aq_" aq "_hu_" hu "_hg_" hg "_hc_" hc "_hlg_" hlg }' "$header"
}

running_abi() {
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 0
    hyprctl version 2>/dev/null | sed -n 's/^Version ABI string: //p' || true
}

is_loaded() {
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 1
    hyprctl plugin list 2>/dev/null | grep -F "Plugin hyprbars" >/dev/null
}

notify() {
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 0
    hyprctl notify 3 9000 "rgb(ff6666)" "$1" >/dev/null 2>&1 || true
}

build() {
    local command version tag missing=()
    for command in git make g++ pkg-config; do
        command -v "$command" >/dev/null 2>&1 || missing+=("$command")
    done
    (( ${#missing[@]} == 0 )) || die "needs ${missing[*]} (pacman -S --needed base-devel git)"
    pkg-config --exists hyprland pixman-1 libdrm libinput libudev wayland-server xkbcommon || die "Hyprland plugin headers and libraries are missing"
    version_h >/dev/null || die "could not find Hyprland's version.h"

    version=$(pkg-config --modversion hyprland)
    tag="v${version%.*}.0"
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    say "fetching hyprbars $tag"
    git clone -q --depth 1 --branch "$tag" "$URL" "$TMP_DIR/src" || die "could not fetch the matching Hyprland plugin release"
    make -C "$TMP_DIR/src/hyprbars" CXX="${CXX:-g++}" -j"$(nproc)" || die "hyprbars did not build for this Hyprland"
    install -Dm755 "$TMP_DIR/src/hyprbars/hyprbars.so" "$SO" || die "could not install $SO"
    header_abi > "$STAMP" || die "could not write the plugin ABI stamp"
    say "built -> $SO"
}

load() {
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || die "not inside Hyprland — it will load on the next login"
    [[ -f "$SO" ]] || die "not built yet (hyprbars-plugin.sh build)"
    is_loaded && { say "already loaded"; return 0; }

    local run out
    run=$(running_abi)
    if [[ -n "$run" && -f "$STAMP" && "$(cat "$STAMP")" != "$run" ]]; then
        die "built for a different Hyprland; run hyprbars-plugin.sh build"
    fi

    out=$(hyprctl plugin load "$SO" 2>&1) || die "Hyprland would not load it: ${out:-no reason given}"
    is_loaded || die "Hyprland did not register the plugin"
    hyprctl reload >/dev/null || die "plugin loaded but Hyprland config did not reload"
    say "loaded"
}

ensure() {
    [[ -f "$SO" ]] || return 0
    local want
    want=$(header_abi) || return 0
    if [[ ! -f "$STAMP" || "$(cat "$STAMP")" != "$want" ]]; then
        build || {
            notify "Lucid: hyprbars could not be rebuilt for this Hyprland"
            return 1
        }
    fi
    load || {
        notify "Lucid: titlebar controls could not be loaded (hyprbars-plugin.sh status)"
        return 1
    }
}

status() {
    [[ -f "$SO" ]] && say "built for : $(cat "$STAMP" 2>/dev/null || echo unknown)" || say "built for : not built"
    say "installed : $(header_abi 2>/dev/null || echo unavailable)"
    say "running   : $(running_abi)"
    if is_loaded; then say "loaded    : yes"; else say "loaded    : no"; fi
}

case "${1:-}" in
    build)  build ;;
    load)   load ;;
    ensure) ensure ;;
    status) status ;;
    *) die "usage: hyprbars-plugin.sh build | load | ensure | status" ;;
esac