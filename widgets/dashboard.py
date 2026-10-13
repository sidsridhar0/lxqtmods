#!/usr/bin/env python3

import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk


ACCENT = (0.57, 0.84, 0.80)
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "lxqtmods"
TODO_FILE = STATE_DIR / "todos.json"


def run_checked(arguments):
    return subprocess.run(arguments, check=True, capture_output=True, text=True).stdout.strip()


def read_cpu_times():
    with open("/proc/stat", encoding="ascii") as stream:
        fields = stream.readline().split()
    if not fields or fields[0] != "cpu":
        raise RuntimeError("Could not read aggregate CPU counters from /proc/stat.")
    values = [int(value) for value in fields[1:]]
    idle = values[3] + (values[4] if len(values) > 4 else 0)
    return sum(values), idle


def read_memory():
    values = {}
    with open("/proc/meminfo", encoding="ascii") as stream:
        for line in stream:
            key, value = line.split(":", 1)
            values[key] = int(value.strip().split()[0])
    total = values["MemTotal"]
    available = values["MemAvailable"]
    return (total - available) / total, total, total - available


def read_battery():
    batteries = []
    for supply in Path("/sys/class/power_supply").glob("*"):
        type_file = supply / "type"
        if not type_file.is_file() or type_file.read_text(encoding="ascii").strip() != "Battery":
            continue
        capacity_file = supply / "capacity"
        if capacity_file.is_file():
            batteries.append(
                (int(capacity_file.read_text(encoding="ascii").strip()),
                 (supply / "status").read_text(encoding="ascii").strip()
                 if (supply / "status").is_file() else "Unknown")
            )
    if not batteries:
        return None
    return round(sum(item[0] for item in batteries) / len(batteries)), ", ".join(
        sorted({item[1] for item in batteries})
    )


def load_todos():
    try:
        data = json.loads(TODO_FILE.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return []
    if not isinstance(data, list) or any(
        not isinstance(item, dict)
        or not isinstance(item.get("text"), str)
        or not isinstance(item.get("done"), bool)
        for item in data
    ):
        raise ValueError(f"Todo data has an invalid format: {TODO_FILE}")
    return data


def save_todos(items):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="todos.", dir=STATE_DIR, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(items, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, TODO_FILE)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


class Dashboard(Gtk.ApplicationWindow):
    def __init__(self, application):
        super().__init__(application=application, title="Desktop widgets")
        self.set_name("lxqtmods-dashboard")
        self.set_default_size(380, 740)
        self.set_resizable(False)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_icon_name("utilities-system-monitor")
        self._cpu_previous = read_cpu_times()
        self._volume_write_timeout = 0
        self._volume_is_dragging = False
        self._todos = load_todos()

        self._install_css()
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.add(scroll)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        content.set_margin_top(18)
        content.set_margin_bottom(18)
        content.set_margin_start(18)
        content.set_margin_end(18)
        scroll.add(content)

        heading = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        content.pack_start(heading, False, False, 0)
        titles = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        heading.pack_start(titles, True, True, 0)
        title = Gtk.Label(label="DESKTOP CONTROL")
        title.set_xalign(0)
        title.get_style_context().add_class("eyebrow")
        titles.pack_start(title, False, False, 0)
        subtitle = Gtk.Label(label="System overview")
        subtitle.set_xalign(0)
        subtitle.get_style_context().add_class("heading")
        titles.pack_start(subtitle, False, False, 0)
        close_button = Gtk.Button.new_from_icon_name("window-close-symbolic", Gtk.IconSize.BUTTON)
        close_button.connect("clicked", lambda *_: self.close())
        heading.pack_end(close_button, False, False, 0)

        self.message = Gtk.Label()
        self.message.set_xalign(0)
        self.message.set_line_wrap(True)
        self.message.get_style_context().add_class("error")
        content.pack_start(self.message, False, False, 0)

        self.cpu_bar, self.cpu_value = self._meter_card(content, "CPU")
        self.ram_bar, self.ram_value = self._meter_card(content, "MEMORY")

        _, volume_body = self._card(content, "MASTER VOLUME")
        self.equalizer = Gtk.DrawingArea()
        self.equalizer.set_size_request(0, 54)
        self.equalizer.connect("draw", self._draw_equalizer)
        volume_body.pack_start(self.equalizer, False, False, 0)
        self.volume_value = Gtk.Label(label="--%")
        self.volume_value.set_xalign(0)
        self.volume_scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1)
        self.volume_scale.set_draw_value(False)
        self.volume_scale.set_hexpand(True)
        self.volume_scale.connect("button-press-event", self._volume_drag_start)
        self.volume_scale.connect("button-release-event", self._volume_drag_end)
        self.volume_scale.connect("value-changed", self._volume_changed)
        volume_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        volume_body.pack_start(volume_row, False, False, 0)
        volume_row.pack_start(self.volume_scale, True, True, 0)
        volume_row.pack_end(self.volume_value, False, False, 0)
        self._volume_sync()

        battery_card, battery_body = self._card(content, "BATTERY")
        battery_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        battery_body.pack_start(battery_row, False, False, 0)
        self.battery_value = Gtk.Label(label="Reading battery…")
        self.battery_value.set_xalign(0)
        self.battery_value.set_hexpand(True)
        battery_row.pack_start(self.battery_value, True, True, 0)
        self.power_button = Gtk.Button(label="Switch profile")
        self.power_button.connect("clicked", self._toggle_power_profile)
        battery_row.pack_end(self.power_button, False, False, 0)
        self.power_profile_value = Gtk.Label()
        self.power_profile_value.set_xalign(0)
        self.power_profile_value.get_style_context().add_class("muted")
        battery_body.pack_start(self.power_profile_value, False, False, 0)

        todo_card, todo_body = self._card(content, "TODO")
        self.todo_list = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        todo_body.pack_start(self.todo_list, False, False, 0)
        self._render_todos()
        todo_entry_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        todo_body.pack_start(todo_entry_row, False, False, 0)
        self.todo_entry = Gtk.Entry()
        self.todo_entry.set_placeholder_text("Add a task…")
        self.todo_entry.connect("activate", self._add_todo)
        todo_entry_row.pack_start(self.todo_entry, True, True, 0)
        add_button = Gtk.Button(label="Add")
        add_button.connect("clicked", self._add_todo)
        todo_entry_row.pack_end(add_button, False, False, 0)
        clear_button = Gtk.Button(label="Clear completed")
        clear_button.connect("clicked", self._clear_completed)
        todo_body.pack_start(clear_button, False, False, 0)

        self._refresh()
        self._refresh_source = GLib.timeout_add_seconds(2, self._refresh)
        self.connect("destroy", self._on_destroy)

    def _install_css(self):
        css = b"""
        window#lxqtmods-dashboard, window#lxqtmods-dashboard > * {
            background: #171a1a;
            color: #eee9dc;
        }
        .card {
            background: #222727;
            border: 2px solid #343b39;
            border-radius: 14px;
            padding: 13px;
        }
        .eyebrow {
            color: #91d7cc;
            font-family: monospace;
            font-size: 10px;
            font-weight: bold;
        }
        .heading {
            color: #eee9dc;
            font-size: 19px;
            font-weight: bold;
        }
        .card-title {
            color: #91d7cc;
            font-family: monospace;
            font-size: 10px;
            font-weight: bold;
        }
        .muted { color: #9baba7; }
        .error { color: #e9a28f; }
        progressbar trough {
            min-height: 8px;
            background: #121515;
            border-radius: 4px;
        }
        progressbar progress {
            min-height: 8px;
            background: #91d7cc;
            border-radius: 4px;
        }
        scale trough {
            min-height: 8px;
            background: #121515;
            border-radius: 4px;
        }
        scale highlight {
            background: #91d7cc;
            border-radius: 4px;
        }
        scale slider {
            min-width: 18px;
            min-height: 18px;
            background: #eee9dc;
            border: 2px solid #111515;
            border-radius: 10px;
        }
        button {
            color: #eee9dc;
            background: #292f2e;
            border: 2px solid #414947;
            border-radius: 9px;
            padding: 5px 9px;
        }
        button:hover { background: #353e3b; border-color: #91d7cc; }
        entry {
            color: #eee9dc;
            background: #171b1b;
            border: 2px solid #414947;
            border-radius: 9px;
            padding: 7px;
        }
        checkbutton { color: #eee9dc; padding: 5px 1px; }
        checkbutton:checked { color: #9baba7; }
        """
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_screen(
            self.get_screen(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def _card(self, parent, heading):
        frame = Gtk.Frame()
        frame.get_style_context().add_class("card")
        frame.set_shadow_type(Gtk.ShadowType.NONE)
        parent.pack_start(frame, False, False, 0)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=9)
        frame.add(box)
        label = Gtk.Label(label=heading)
        label.set_xalign(0)
        label.get_style_context().add_class("card-title")
        box.pack_start(label, False, False, 0)
        return frame, box

    def _meter_card(self, parent, heading):
        _, body = self._card(parent, heading)
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        body.pack_start(row, False, False, 0)
        value = Gtk.Label(label="--%")
        value.set_xalign(0)
        value.set_width_chars(5)
        row.pack_start(value, False, False, 0)
        bar = Gtk.ProgressBar()
        bar.set_hexpand(True)
        row.pack_start(bar, True, True, 0)
        return bar, value

    def _draw_equalizer(self, _widget, context):
        allocation = self.equalizer.get_allocation()
        bar_count = 16
        gap = 4
        bar_width = max(4, (allocation.width - gap * (bar_count - 1)) / bar_count)
        steps = 5
        segment_gap = 2
        segment_height = (allocation.height - segment_gap * (steps - 1)) / steps
        level = int(round(self.volume_scale.get_value() / 100 * steps))
        for index in range(bar_count):
            height_steps = 1 + ((index * 3 + 2) % steps)
            x = index * (bar_width + gap)
            active = max(0, min(height_steps, level + (index % 3 == 0)))
            for step in range(height_steps):
                y = allocation.height - (step + 1) * (segment_height + segment_gap)
                if step < active:
                    context.set_source_rgb(*ACCENT)
                else:
                    context.set_source_rgb(0.18, 0.22, 0.21)
                context.rectangle(x, y, bar_width, segment_height)
                context.fill()
        return False

    def _volume_drag_start(self, *_args):
        self._volume_is_dragging = True
        return False

    def _volume_drag_end(self, *_args):
        self._volume_is_dragging = False
        return False

    def _volume_changed(self, scale):
        percent = round(scale.get_value())
        self.volume_value.set_text(f"{percent}%")
        self.equalizer.queue_draw()
        if self._volume_write_timeout:
            GLib.source_remove(self._volume_write_timeout)
        self._volume_write_timeout = GLib.timeout_add(120, self._apply_volume)

    def _apply_volume(self):
        self._volume_write_timeout = 0
        try:
            run_checked(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{self.volume_scale.get_value() / 100:.2f}"])
            self.message.set_text("")
        except (OSError, subprocess.CalledProcessError) as error:
            detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) else str(error)
            self.message.set_text(f"Could not change master volume: {detail}")
        return GLib.SOURCE_REMOVE

    def _volume_sync(self):
        output = run_checked(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"])
        match = re.search(r"Volume:\s*([0-9]+(?:\.[0-9]+)?)", output)
        if not match:
            raise RuntimeError(f"Unexpected wpctl volume response: {output}")
        percent = min(100, max(0, round(float(match.group(1)) * 100)))
        self.volume_scale.set_value(percent)
        self.volume_value.set_text(f"{percent}%")

    def _toggle_power_profile(self, *_args):
        try:
            active = run_checked(["powerprofilesctl", "get"])
            target = "balanced" if active == "power-saver" else "power-saver"
            run_checked(["powerprofilesctl", "set", target])
            self._update_power_profile()
            self.message.set_text("")
        except (OSError, subprocess.CalledProcessError) as error:
            detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) else str(error)
            self.message.set_text(f"Could not switch power profile: {detail}")

    def _update_power_profile(self):
        try:
            active = run_checked(["powerprofilesctl", "get"])
        except (OSError, subprocess.CalledProcessError) as error:
            self.power_profile_value.set_text("Power profiles unavailable — run deploy.sh with sudo.")
            self.power_button.set_sensitive(False)
            return
        self.power_button.set_sensitive(True)
        if active == "power-saver":
            self.power_profile_value.set_text("Power Saver is active")
            self.power_button.set_label("Switch to Balanced")
        else:
            self.power_profile_value.set_text(f"{active.capitalize()} profile is active")
            self.power_button.set_label("Switch to Power Saver")

    def _render_todos(self):
        for child in self.todo_list.get_children():
            self.todo_list.remove(child)
        if not self._todos:
            empty = Gtk.Label(label="No tasks yet — add one below.")
            empty.set_xalign(0)
            empty.get_style_context().add_class("muted")
            self.todo_list.pack_start(empty, False, False, 0)
        for index, item in enumerate(self._todos):
            check = Gtk.CheckButton(label=item["text"])
            check.set_active(item["done"])
            check.connect("toggled", self._toggle_todo, index)
            self.todo_list.pack_start(check, False, False, 0)
        self.todo_list.show_all()

    def _toggle_todo(self, check, index):
        previous = [item.copy() for item in self._todos]
        self._todos[index]["done"] = check.get_active()
        self._persist_todos(previous)

    def _add_todo(self, *_args):
        text = self.todo_entry.get_text().strip()
        if not text:
            self.todo_entry.grab_focus()
            return
        previous = [item.copy() for item in self._todos]
        self._todos.append({"text": text, "done": False})
        if not self._persist_todos(previous):
            return
        self.todo_entry.set_text("")
        self._render_todos()

    def _clear_completed(self, *_args):
        previous = [item.copy() for item in self._todos]
        self._todos = [item for item in self._todos if not item["done"]]
        if self._persist_todos(previous):
            self._render_todos()

    def _persist_todos(self, previous):
        try:
            save_todos(self._todos)
        except OSError as error:
            self._todos = previous
            self.message.set_text(f"Could not save todo list: {error}")
            self._render_todos()
            return False
        self.message.set_text("")
        return True

    def _refresh(self):
        try:
            total, idle = read_cpu_times()
            previous_total, previous_idle = self._cpu_previous
            delta_total = total - previous_total
            cpu = 0 if delta_total <= 0 else 1 - (idle - previous_idle) / delta_total
            self._cpu_previous = total, idle
            ram, _, _ = read_memory()
            self.cpu_bar.set_fraction(min(1, max(0, cpu)))
            self.cpu_value.set_text(f"{round(cpu * 100)}%")
            self.ram_bar.set_fraction(min(1, max(0, ram)))
            self.ram_value.set_text(f"{round(ram * 100)}%")
            self.battery_value.set_text(self._battery_text())
            self._update_power_profile()
        except (OSError, KeyError, ValueError, RuntimeError) as error:
            self.message.set_text(f"Could not refresh system meters: {error}")
        if not self._volume_is_dragging:
            try:
                self._volume_sync()
            except (OSError, subprocess.CalledProcessError, RuntimeError) as error:
                self.message.set_text(f"Could not read master volume: {error}")
        return GLib.SOURCE_CONTINUE

    @staticmethod
    def _battery_text():
        battery = read_battery()
        if battery is None:
            return "No battery detected"
        capacity, status = battery
        return f"{capacity}%  ·  {status}"

    def _on_destroy(self, *_args):
        if self._refresh_source:
            GLib.source_remove(self._refresh_source)
        if self._volume_write_timeout:
            GLib.source_remove(self._volume_write_timeout)


class DashboardApplication(Gtk.Application):
    def __init__(self):
        super().__init__(
            application_id="io.github.sidsridhar0.lxqtmods.dashboard",
            flags=Gio.ApplicationFlags(0),
        )
        self.window = None

    def do_activate(self):
        if self.window is None:
            self.window = Dashboard(self)
            self.window.connect("destroy", self._window_closed)
        self.window.present()

    def _window_closed(self, *_args):
        self.window = None


if __name__ == "__main__":
    raise SystemExit(DashboardApplication().run(None))
