#!/usr/bin/env python3

import logging
import re
import subprocess
import time


logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
SWIPE_BEGIN = re.compile(r"GESTURE_SWIPE_BEGIN\b.*?\s(\d+)\s*$")
SWIPE_UPDATE = re.compile(
    r"GESTURE_SWIPE_UPDATE\b.*?\s(\d+)\s+(-?\d+(?:\.\d+)?)/(-?\d+(?:\.\d+)?)\s*$"
)
SWIPE_END = re.compile(r"GESTURE_SWIPE_END\b.*?\s(\d+)(?:\s+\S+)?\s*$")
UP_THRESHOLD = -35.0
MAX_SWIPE_DURATION = 2.0
SWITCHER_HOLD_MS = 8000


def window_switcher_command():
    return [
        "/usr/bin/wtype",
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


def monitor():
    logging.info("Listening for three-finger touchpad swipes.")
    process = subprocess.Popen(
        ["/usr/bin/libinput", "debug-events"],
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
    try:
        monitor()
    except (OSError, subprocess.CalledProcessError, RuntimeError) as error:
        logging.error("Touchpad gesture monitor stopped: %s", error)
        raise SystemExit(1) from error
