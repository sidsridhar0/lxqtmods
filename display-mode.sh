#!/usr/bin/env bash
set -euo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
layout_file="$config_dir/miriway-shell.display-config-layout"
current="default"

if [[ -f "$layout_file" ]]; then
    IFS= read -r current < "$layout_file" || true
fi

case "${1:-cycle}" in
    cycle)
        case "$current" in
            default|side_by_side|extended) next="first-screen" ;;
            first-screen) next="second-screen" ;;
            second-screen) next="duplicate" ;;
            duplicate) next="extended" ;;
            *)
                printf 'Unknown active display profile: %s\n' "$current" >&2
                exit 1
                ;;
        esac
        ;;
    first-screen|second-screen|duplicate|extended)
        next="$1"
        ;;
    *)
        printf 'Usage: %s [first-screen|second-screen|duplicate|extended]\n' "$0" >&2
        exit 2
        ;;
esac

if ! pgrep -u "$(id -u)" -x miriway-shell >/dev/null; then
    printf 'Cannot switch display mode: Miriway is not running.\n' >&2
    exit 1
fi

mkdir -p "$config_dir"
printf '%s\n' "$next" > "$layout_file"

case "$next" in
    first-screen) label="Laptop screen only" ;;
    second-screen) label="External screen only" ;;
    duplicate) label="Duplicated screens" ;;
    extended) label="Extended screens" ;;
esac

if command -v notify-send >/dev/null 2>&1; then
    notify-send --app-name="Display mode" --icon=video-display "$label"
else
    printf '%s\n' "$label"
fi
