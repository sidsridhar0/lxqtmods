#!/usr/bin/env python3

"""Build a Miriway display-config that only mentions connected outputs."""

import argparse
import re
import sys
from pathlib import Path


DRM_ROOT = Path("/sys/class/drm")
CONNECTOR_DIR = re.compile(r"^card(\d+)-(.+)$")


def miriway_name(kernel_name):
    if kernel_name.startswith("DP-"):
        return f"DisplayPort-{kernel_name[3:]}"
    return kernel_name


def connector_kind(kernel_name):
    name = kernel_name.upper()
    if name.startswith(("EDP", "LVDS", "DSI")):
        return "internal"
    if name.startswith(("DP-", "DISPLAYPORT", "HDMI", "VGA", "DVI", "USB")):
        return "external"
    return "other"


def preferred_mode(connector_dir):
    modes_file = connector_dir / "modes"
    try:
        lines = [
            line.strip()
            for line in modes_file.read_text(encoding="ascii", errors="replace").splitlines()
            if line.strip()
        ]
    except OSError:
        return None
    if not lines:
        return None
    mode = lines[0]
    if re.fullmatch(r"\d+x\d+", mode):
        return f"{mode}@60.0"
    return mode


def mode_width(mode):
    match = re.match(r"(\d+)x", mode)
    if not match:
        return 1920
    return int(match.group(1))


def connected_outputs():
    outputs = []
    if not DRM_ROOT.is_dir():
        return outputs
    for connector_dir in sorted(DRM_ROOT.iterdir()):
        match = CONNECTOR_DIR.match(connector_dir.name)
        if not match:
            continue
        status_file = connector_dir / "status"
        try:
            status = status_file.read_text(encoding="ascii").strip()
        except OSError:
            continue
        if status != "connected":
            continue
        mode = preferred_mode(connector_dir)
        if mode is None:
            continue
        outputs.append(
            {
                "card_id": int(match.group(1)),
                "kernel": match.group(2),
                "name": miriway_name(match.group(2)),
                "kind": connector_kind(match.group(2)),
                "mode": mode,
                "width": mode_width(mode),
            }
        )
    return outputs


def choose_displays(outputs):
    intern = next((item for item in outputs if item["kind"] == "internal"), None)
    if intern is None and outputs:
        intern = outputs[0]
    if intern is None:
        return None, None
    external = next(
        (
            item
            for item in outputs
            if item["kind"] == "external"
            and item["name"] != intern["name"]
            and item["card_id"] == intern["card_id"]
        ),
        None,
    )
    return intern, external


def enabled(output, position, group):
    return (
        f"        {output['name']}:\n"
        f"          state: enabled\n"
        f"          mode: {output['mode']}\n"
        f"          position: [{position[0]}, {position[1]}]\n"
        f"          orientation: normal\n"
        f"          scale: 1\n"
        f"          group: {group}\n"
    )


def disabled(output):
    return f"        {output['name']}:\n          state: disabled\n"


def card(intern, extra_block):
    return (
        "    cards:\n"
        f"    - card-id: {intern['card_id']}\n"
        f"{extra_block}"
    )


def render(intern, external):
    laptop = enabled(intern, (0, 0), 0)
    if external is None:
        body = card(intern, laptop)
        return (
            "layouts:\n"
            "  default: &laptop\n"
            f"{body}\n"
            "  first-screen: *laptop\n"
            "  side_by_side: *laptop\n"
            "  extended: *laptop\n"
            "  second-screen: *laptop\n"
            "  duplicate: *laptop\n"
        )

    laptop_with_external_off = card(intern, laptop + disabled(external))
    external_only = card(intern, disabled(intern) + enabled(external, (0, 0), 0))
    extended = card(
        intern,
        enabled(intern, (0, 0), 0) + enabled(external, (intern["width"], 0), 0),
    )
    return (
        "layouts:\n"
        "  default: &laptop\n"
        f"{laptop_with_external_off}\n"
        "  first-screen: *laptop\n"
        "  second-screen:\n"
        f"{external_only}\n"
        "  extended: &extended\n"
        f"{extended}\n"
        "  side_by_side: *extended\n"
        "  duplicate: *extended\n"
    )


def write_config(path, intern, external):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(render(intern, external), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--fallback", type=Path)
    args = parser.parse_args()

    intern, external = choose_displays(connected_outputs())
    if intern is not None:
        write_config(args.destination, intern, external)
        extra = f" and {external['name']} ({external['mode']})" if external else ""
        print(
            f"Display profiles use {intern['name']} ({intern['mode']}){extra}; "
            "login defaults to the laptop screen.",
            file=sys.stderr,
        )
        return 0

    if args.fallback is not None and args.fallback.is_file():
        args.destination.parent.mkdir(parents=True, exist_ok=True)
        args.destination.write_text(args.fallback.read_text(encoding="utf-8"), encoding="utf-8")
        print(
            "No connected DRM outputs found; installed the laptop-only display fallback.",
            file=sys.stderr,
        )
        return 0

    print("Could not generate a display configuration.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
