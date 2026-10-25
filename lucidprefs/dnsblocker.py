#!/usr/bin/env python3
"""Manage Lucid's opt-in DNS and YouTube host filtering."""

import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


STATE_HOME = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
STATE_PATH = STATE_HOME / "lucid/dns-blocker.json"
HOSTS_PATH = Path("/etc/hosts")
BEGIN = "# BEGIN LUCID DNS BLOCKER"
END = "# END LUCID DNS BLOCKER"
DNS4 = "94.140.14.15,94.140.15.16"
DNS6 = "2a10:50c0::bad1:ff,2a10:50c0::bad2:ff"
DOMAINS = (
    "youtube.com www.youtube.com m.youtube.com music.youtube.com "
    "youtu.be www.youtu.be youtube-nocookie.com www.youtube-nocookie.com "
    "youtubei.googleapis.com youtube.googleapis.com "
    "youtubeembeddedplayer.googleapis.com ytimg.com i.ytimg.com s.ytimg.com "
    "googlevideo.com"
)
UUID_RE = re.compile(r"^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$")
DEVICE_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,64}$")


class BlockerError(Exception):
    pass


def command(args, *, input_text=None, elevated=False):
    if elevated:
        if not Path("/usr/bin/pkexec").is_file():
            raise BlockerError("pkexec is not installed; system changes need authorization.")
        args = ["/usr/bin/pkexec"] + args
    try:
        result = subprocess.run(
            args, input=input_text, capture_output=True, text=True, timeout=120,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise BlockerError(f"Could not run {Path(args[0]).name}: {exc}") from exc
    if result.returncode != 0:
        detail = result.stderr.strip()
        if elevated and result.returncode in (126, 127):
            detail = detail or "Authorization was cancelled or denied."
        raise BlockerError(detail or f"{Path(args[0]).name} exited with status {result.returncode}.")
    return result.stdout


def nmcli(args):
    return command(["/usr/bin/nmcli"] + args)


def profiles():
    if not Path("/usr/bin/nmcli").is_file():
        raise BlockerError("NetworkManager's nmcli is not installed.")

    active = {}
    for line in nmcli(["-t", "--escape", "no", "-f", "UUID,DEVICE", "connection", "show", "--active"]).splitlines():
        fields = line.split(":", 1)
        if len(fields) == 2 and UUID_RE.fullmatch(fields[0]):
            active[fields[0]] = fields[1]

    result = []
    for line in nmcli(["-t", "--escape", "no", "-f", "UUID,TYPE", "connection", "show"]).splitlines():
        fields = line.split(":", 1)
        if len(fields) != 2 or not UUID_RE.fullmatch(fields[0]):
            continue
        uuid, kind = fields
        if kind not in ("802-11-wireless", "802-3-ethernet"):
            continue
        profile = {
            "uuid": uuid,
            "device": active.get(uuid, ""),
            "ipv4Dns": nmcli(["-g", "ipv4.dns", "connection", "show", uuid]).strip(),
            "ipv4IgnoreAutoDns": nmcli(["-g", "ipv4.ignore-auto-dns", "connection", "show", uuid]).strip() or "no",
            "ipv6Dns": nmcli(["-g", "ipv6.dns", "connection", "show", uuid]).strip(),
            "ipv6IgnoreAutoDns": nmcli(["-g", "ipv6.ignore-auto-dns", "connection", "show", uuid]).strip() or "no",
        }
        validate_profile(profile)
        result.append(profile)
    return result


def validate_profile(profile):
    if not isinstance(profile, dict) or not UUID_RE.fullmatch(str(profile.get("uuid", ""))):
        raise BlockerError("The saved DNS settings contain an invalid connection.")
    for key, version in (("ipv4Dns", 4), ("ipv6Dns", 6)):
        validate_dns(profile.get(key), version)
    for key in ("ipv4IgnoreAutoDns", "ipv6IgnoreAutoDns"):
        if profile.get(key) not in ("yes", "no"):
            raise BlockerError("The saved DNS settings contain an invalid option.")


def validate_dns(value, version):
    if not isinstance(value, str) or value == "":
        return
    for item in value.split(","):
        try:
            address = ipaddress.ip_address(item.strip())
        except ValueError as exc:
            raise BlockerError("Saved DNS settings are invalid; refusing to restore them.") from exc
        if address.version != version:
            raise BlockerError("Saved DNS settings do not match their address family.")


def read_state():
    try:
        state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    except (OSError, json.JSONDecodeError) as exc:
        raise BlockerError(f"Could not read the saved DNS settings: {exc}") from exc

    if not isinstance(state, dict) or state.get("version") != 1 or not isinstance(state.get("profiles"), list):
        raise BlockerError("The saved DNS settings are not valid; refusing to change system settings.")
    if not state["profiles"]:
        raise BlockerError("The saved DNS settings contain no connections to restore.")
    for profile in state["profiles"]:
        validate_profile(profile)
    return state


def save_state(state):
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".dns-blocker-", suffix=".tmp", dir=STATE_PATH.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(state, handle)
            handle.write("\n")
        os.replace(temporary, STATE_PATH)
    except OSError as exc:
        try:
            os.close(fd)
        except OSError:
            pass
        Path(temporary).unlink(missing_ok=True)
        raise BlockerError(f"Could not save the DNS backup: {exc}") from exc


def hosts_content():
    try:
        if HOSTS_PATH.is_symlink() or not HOSTS_PATH.is_file():
            raise BlockerError("/etc/hosts is not a regular file; refusing to modify it.")
        return HOSTS_PATH.read_text(encoding="utf-8")
    except OSError as exc:
        raise BlockerError(f"Could not read /etc/hosts: {exc}") from exc


def hosts_block():
    return (
        f"{BEGIN}\n"
        f"0.0.0.0 {DOMAINS}\n"
        f":: {DOMAINS}\n"
        f"{END}\n"
    )


def check_markers(text):
    if text.count(BEGIN) != text.count(END):
        raise BlockerError("/etc/hosts has an incomplete Lucid DNS blocker section.")
    if text.count(BEGIN) > 1:
        raise BlockerError("/etc/hosts has duplicate Lucid DNS blocker sections.")
    return text.count(BEGIN) == 1


def set_profile(profile, *, restore):
    uuid = profile["uuid"]
    if not UUID_RE.fullmatch(uuid):
        raise BlockerError("Refusing to modify an invalid NetworkManager connection.")
    if restore:
        ipv4_dns = profile["ipv4Dns"]
        ipv4_ignore = profile["ipv4IgnoreAutoDns"]
        ipv6_dns = profile["ipv6Dns"]
        ipv6_ignore = profile["ipv6IgnoreAutoDns"]
    else:
        ipv4_dns = DNS4
        ipv4_ignore = "yes"
        ipv6_dns = DNS6
        ipv6_ignore = "yes"
    command([
        "/usr/bin/nmcli", "connection", "modify", uuid,
        "ipv4.dns", ipv4_dns,
        "ipv4.ignore-auto-dns", ipv4_ignore,
        "ipv6.dns", ipv6_dns,
        "ipv6.ignore-auto-dns", ipv6_ignore,
    ], elevated=True)


def refresh_active(profile_list):
    warnings = []
    for profile in profile_list:
        device = profile.get("device", "")
        if not device:
            continue
        if not DEVICE_RE.fullmatch(device) or device.startswith("-"):
            warnings.append("Could not refresh DNS on the current network; reconnect to apply the filter.")
            break
        try:
            command(["/usr/bin/nmcli", "device", "reapply", device], elevated=True)
        except BlockerError:
            warnings.append("Reconnect to refresh DNS on the current network.")
            break
    return warnings


def enable():
    if read_state() is not None:
        raise BlockerError("The DNS blocker is already enabled or needs recovery; turn it off first.")
    current_hosts = hosts_content()
    if check_markers(current_hosts):
        raise BlockerError("/etc/hosts already has a Lucid DNS blocker section, but no backup was found.")
    saved_profiles = profiles()
    if not saved_profiles:
        raise BlockerError("No saved Wi-Fi or wired NetworkManager connections were found.")

    state = {"version": 1, "phase": "applying", "profiles": saved_profiles}
    save_state(state)
    changed = []
    try:
        for profile in saved_profiles:
            set_profile(profile, restore=False)
            changed.append(profile)
        block = hosts_block()
        if not current_hosts.endswith("\n"):
            block = "\n" + block
        command(["/usr/bin/tee", "--append", str(HOSTS_PATH)], input_text=block, elevated=True)
        state["phase"] = "active"
        save_state(state)
    except BlockerError as exc:
        rollback_errors = []
        for profile in reversed(changed):
            try:
                set_profile(profile, restore=True)
            except BlockerError as rollback_exc:
                rollback_errors.append(str(rollback_exc))
        if check_markers(hosts_content()):
            try:
                command([
                    "/usr/bin/sed", "-i",
                    r"/^# BEGIN LUCID DNS BLOCKER$/,/^# END LUCID DNS BLOCKER$/d",
                    str(HOSTS_PATH),
                ], elevated=True)
            except BlockerError as rollback_exc:
                rollback_errors.append(str(rollback_exc))
        if rollback_errors:
            state["phase"] = "partial"
            save_state(state)
            raise BlockerError(f"{exc} Rollback was incomplete: {'; '.join(rollback_errors)}") from exc
        STATE_PATH.unlink(missing_ok=True)
        raise
    warnings = refresh_active(saved_profiles)
    return {
        "enabled": True,
        "profiles": len(saved_profiles),
        "warning": " ".join(warnings),
    }


def disable():
    state = read_state()
    if state is None:
        raise BlockerError("No saved DNS backup was found; nothing can be restored.")
    available = {
        profile["uuid"]: profile for profile in profiles()
    }
    errors = []
    restored = []
    for saved in state["profiles"]:
        profile = available.get(saved["uuid"])
        if profile is None:
            continue
        try:
            set_profile(saved, restore=True)
            restored.append(profile)
        except BlockerError as exc:
            errors.append(str(exc))
    if errors:
        state["phase"] = "partial"
        save_state(state)
        raise BlockerError("Some saved connections could not be restored: " + "; ".join(errors))

    current_hosts = hosts_content()
    if check_markers(current_hosts):
        command([
            "/usr/bin/sed", "-i",
            r"/^# BEGIN LUCID DNS BLOCKER$/,/^# END LUCID DNS BLOCKER$/d",
            str(HOSTS_PATH),
        ], elevated=True)
    warnings = refresh_active(restored)
    STATE_PATH.unlink(missing_ok=True)
    return {
        "enabled": False,
        "profiles": len(restored),
        "warning": " ".join(warnings),
    }


def status():
    state = read_state()
    current_hosts = hosts_content()
    has_block = check_markers(current_hosts)
    available = Path("/usr/bin/nmcli").is_file() and Path("/usr/bin/pkexec").is_file()
    profile_count = len(state["profiles"]) if state else (len(profiles()) if Path("/usr/bin/nmcli").is_file() else 0)
    warning = ""
    if state and not has_block:
        warning = "DNS settings are backed up, but the YouTube hosts section is missing. Turn the filter off to restore DNS."
    return {
        "enabled": state is not None,
        "profiles": profile_count,
        "available": available,
        "warning": warning,
    }


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("status", "enable", "disable"):
        result = {"error": "Expected one action: status, enable, or disable."}
        code = 2
    else:
        try:
            action = sys.argv[1]
            result = status() if action == "status" else (enable() if action == "enable" else disable())
            code = 0
        except BlockerError as exc:
            result = {"error": str(exc)}
            if sys.argv[1] != "status":
                try:
                    state = read_state()
                    result.update({
                        "enabled": state is not None,
                        "profiles": len(state["profiles"]) if state else 0,
                        "available": Path("/usr/bin/nmcli").is_file() and Path("/usr/bin/pkexec").is_file(),
                    })
                except BlockerError:
                    pass
            code = 1
        except OSError as exc:
            result = {"error": f"System operation failed: {exc}"}
            code = 1
    print(json.dumps(result))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
