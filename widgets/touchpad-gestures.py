#!/usr/bin/env python3

import logging
import re
import shutil
import subprocess
import time
from pathlib import Path


logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
SWIPE_BEGIN = re.compile(r"GESTURE_SWIPE_BEGIN\b.*?\s(\d+)\s*$")
SWIPE_UPDATE = re.compile(
    r"GESTURE_SWIPE_UPDATE\b.*?\s(\d+)\s+(-?\d+(?:\.\d+)?)/(-?\d+(?:\.\d+)?)(?:\s|$)"
)
SWIPE_END = re.compile(r"GESTURE_SWIPE_END\b.*?\s(\d+)(?:\s+\S+)?\s*$")
UP_THRESHOLD = -35.0
MAX_SWIPE_DURATION = 2.0
SWITCHER_HOLD_MS = 8000
DEVICES_FILE = Path("/proc/bus/input/devices")


def window_switcher_command():
    wtype = shutil.which("wtype") or "/usr/bin/wtype"
    return [
        wtype,
        "-M",
        "alt",
        "-P",
        "grave",
        "-p",
        "grave",
        "-s",
        str(SWITCHER_HOLD_MS),
        "-m",
        "alt",
    ]


def touchpad_event_paths():
    try:
        text = DEVICES_FILE.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []

    paths = []
    name = ""
    for line in text.splitlines():
        if line.startswith("N: Name="):
            name = line.split("=", 1)[1].strip().strip('"').lower()
            continue
        if not line.startswith("H: Handlers="):
            continue
        is_touchpad = (
            "touchpad" in name or "trackpad" in name or "synaptics" in name
        ) and "touchscreen" not in name
        if is_touchpad:
            for token in line.split(":", 1)[-1].split():
                if token.startswith("event"):
                    paths.append(Path("/dev/input") / token)
        name = ""
    return [path for path in paths if path.exists()]


def libinput_command(devices):
    command = ["/usr/bin/libinput", "debug-events"]
    for device in devices:
        command.extend(["--device", str(device)])
    return command


def monitor(devices):
    logging.info(
        "Listening for three-finger swipes on %s.",
        ", ".join(str(device) for device in devices),
    )
    process = subprocess.Popen(
        libinput_command(devices),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    assert process.stdout is not None
    fingers = 0
    swipe_start = 0.0
    vertical_distance = 0.0
    last_switcher = 0.0
    switcher_process = None

    try:
        for line in process.stdout:
            if switcher_process is not None and switcher_process.poll() is not None:
                if switcher_process.returncode:
                    logging.error(
                        "wtype failed to open the window switcher (exit %d).",
                        switcher_process.returncode,
                    )
                switcher_process = None

            begin = SWIPE_BEGIN.search(line)
            if begin:
                fingers = int(begin.group(1))
                swipe_start = time.monotonic()
                vertical_distance = 0.0
                continue

            update = SWIPE_UPDATE.search(line)
            if update and fingers == 3 and int(update.group(1)) == 3:
                vertical_distance += float(update.group(3))
                continue

            end = SWIPE_END.search(line)
            if not end or fingers == 0:
                if "error" in line.lower() or "failed" in line.lower():
                    logging.error("%s", line.rstrip())
                continue

            elapsed = time.monotonic() - swipe_start
            is_three_finger_up = (
                fingers == 3
                and int(end.group(1)) == 3
                and elapsed <= MAX_SWIPE_DURATION
                and vertical_distance <= UP_THRESHOLD
            )
            fingers = 0
            if (
                is_three_finger_up
                and switcher_process is None
                and time.monotonic() - last_switcher >= SWITCHER_HOLD_MS / 1000
            ):
                logging.info("Three-finger swipe up detected; opening Miriway's window switcher.")
                try:
                    switcher_process = subprocess.Popen(window_switcher_command())
                except FileNotFoundError:
                    logging.error("wtype is required to open Miriway's window switcher.")
                last_switcher = time.monotonic()

        return_code = process.wait()
        if return_code:
            raise subprocess.CalledProcessError(return_code, process.args)
        raise RuntimeError("libinput debug-events stopped unexpectedly.")
    finally:
        if switcher_process is not None and switcher_process.poll() is None:
            switcher_process.terminate()
            switcher_process.wait()
        if process.poll() is None:
            process.terminate()
            process.wait()


if __name__ == "__main__":
    devices = touchpad_event_paths()
    if not devices:
        logging.info("No touchpad event device found; gesture monitor will stay idle.")
        raise SystemExit(0)
    try:
        monitor(devices)
    except (OSError, subprocess.CalledProcessError, RuntimeError) as error:
        logging.error("Touchpad gesture monitor stopped: %s", error)
        raise SystemExit(1) from error
