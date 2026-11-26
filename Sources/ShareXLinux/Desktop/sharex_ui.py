#!/usr/bin/python3
"""Native GTK 3 desktop for ShareX Linux.

The Swift executable remains the source of truth for settings, capture,
history and clipboard state.  This process owns only GTK objects and the
countdown/selector lifecycle, so each action can be forwarded to one running
application instance by Gio.
"""

import json
import os
import signal
import subprocess
import sys
import threading
import time
from copy import deepcopy

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gio", "2.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango

try:
    from shortcuts import Shortcuts
except ImportError:  # Allows importing the UI in a documentation/build environment.
    class Shortcuts:
        def __init__(self, application, on_action, on_status):
            self.on_status = on_status

        def apply(self, hotkeys):
            return None

        def close(self):
            return None

        def configure(self):
            self.on_status("Desktop shortcut configuration is unavailable.")

        def set_recording(self, active):
            return None

from sharex_history import History
from sharex_settings import Preferences
from sharex_widgets import ACTION_TITLES, button, column, header, label, row


APP_ID = "io.github.PDGamerSG.ShareXLinux"


class Job:
    def __init__(self, process):
        self.process = process
        self.cancelled = False

    def cancel(self):
        if self.cancelled:
            return
        self.cancelled = True
        if self.process is not None and self.process.poll() is None:
            try:
                os.killpg(self.process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                self.process.wait(timeout=0.7)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(self.process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass


class BackendWorker:
    """Run one Swift backend request per thread, never blocking GTK."""

    def __init__(self, executable):
        self.executable = executable
        self.jobs = set()
        self.lock = threading.Lock()

    def run(self, operation, *arguments, json_input=None, text=None, success=None, failure=None):
        argv = [self.executable, "--backend", operation, *[str(argument) for argument in arguments]]
        try:
            process = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, text=False, start_new_session=True)
        except OSError as error:
            if failure:
                GLib.idle_add(failure, str(error))
            return Job(None)
        job = Job(process)
        with self.lock:
            self.jobs.add(job)
        if json_input is not None:
            data = json.dumps(json_input, separators=(",", ":")).encode("utf-8")
        elif text is not None:
            data = text.encode("utf-8")
        else:
            data = b""

        def execute():
            try:
                stdout, stderr = process.communicate(data)
                code = process.returncode
                if job.cancelled:
                    return
                if code == 0:
                    try:
                        value = json.loads(stdout.decode("utf-8")) if stdout.strip() else True
                    except (ValueError, UnicodeDecodeError) as error:
                        self.finish(job, failure, f"ShareX returned invalid data: {error}")
                    else:
                        self.finish(job, success, value)
                else:
                    message = stderr.decode("utf-8", "replace").strip()
                    self.finish(job, failure, message or f"ShareX backend exited with status {code}.")
            except Exception as error:
                if not job.cancelled:
                    self.finish(job, failure, str(error))
            finally:
                with self.lock:
                    self.jobs.discard(job)

        threading.Thread(target=execute, daemon=True).start()
        return job

    def finish(self, job, callback, value):
        if callback:
            GLib.idle_add(self.deliver, callback, value)

    @staticmethod
    def deliver(callback, value):
        try:
            callback(value)
        except Exception as error:
            # A closed window may have discarded its callback. Keep GTK alive.
            GLib.log_structured("ShareX", GLib.LogLevelFlags.LEVEL_WARNING,
                                "MESSAGE", f"UI callback failed: {error}")
        return GLib.SOURCE_REMOVE

    def cancel_all(self):
        with self.lock:
            jobs = list(self.jobs)
        for job in jobs:
            job.cancel()


class Countdown(Gtk.Window):
    def __init__(self, parent, seconds, cancelled, completed):
        super().__init__(transient_for=parent, modal=False, title="Screenshot Delay")
        self.set_decorated(True)
        self.set_resizable(False)
        self.set_keep_above(True)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.cancelled = cancelled
        self.completed = completed
        self.started = time.monotonic()
        self.duration = max(0.0, min(60.0, float(seconds)))
        body = column(14, 18)
        self.add(body)
        self.status = label()
        self.status.set_halign(Gtk.Align.CENTER)
        body.add(self.status)
        body.add(button("Cancel", self.cancel))
        self.timeout = GLib.timeout_add(50, self.tick)
        self.connect("delete-event", lambda *unused: self.cancel())
        self.show_all()

    def tick(self):
        remaining = self.duration - (time.monotonic() - self.started)
        if remaining <= 0:
            self.timeout = None
            self.completed()
            self.destroy()
            return GLib.SOURCE_REMOVE
        self.status.set_text(f"Capturing in {remaining:.1f}…")
        return GLib.SOURCE_CONTINUE

    def cancel(self):
        if self.timeout:
            GLib.source_remove(self.timeout)
            self.timeout = None
        self.cancelled()
        self.destroy()

    def close(self):
        if self.get_visible():
            self.destroy()


class CaptureNotice(Gtk.Window):
    def __init__(self, app, record, warning=None):
        name = os.path.basename(record["path"])
        super().__init__(application=app, title="Screenshot saved", transient_for=app.main_window)
        self.set_decorated(True)
        self.set_resizable(False)
        self.set_keep_above(True)
        self.set_position(Gtk.WindowPosition.CENTER)
        body = column(8, 16)
        self.add(body)
        body.add(label("Screenshot saved"))
        detail = label(name, dim=True)
        detail.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
        body.add(detail)
        if warning:
            body.add(label(warning, dim=True))
        actions = row(8)
        actions.pack_end(button("Open Folder", lambda: app.open_path(os.path.dirname(record["path"]), self)), False, False, 0)
        actions.pack_end(button("Close", self.destroy), False, False, 0)
        body.add(actions)
        self.show_all()
        self.timeout = GLib.timeout_add_seconds(5, self.destroy_later)
        self.connect("destroy", self.stopped)

    def destroy_later(self):
        self.destroy()
        return GLib.SOURCE_REMOVE

    def stopped(self, unused):
        if self.timeout:
            GLib.source_remove(self.timeout)
            self.timeout = None


class OCRWindow(Gtk.ApplicationWindow):
    def __init__(self, app, path):
        super().__init__(application=app, title="Recognized Text")
        self.app = app
        self.path = path
        self.generation = 0
        self.copied_generation = None
        self.set_default_size(700, 470)
        bar = header(self, "Recognized Text")
        self.retry = button("Try Again", self.recognize)
        bar.pack_end(self.retry)
        body = column(10, 12)
        self.add(body)
        self.message = label("Recognizing text…", dim=True)
        body.add(self.message)
        self.text = Gtk.TextView()
        self.text.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        self.text.set_monospace(False)
        self.text.get_accessible().set_name("Recognized text")
        body.pack_start(Gtk.ScrolledWindow(), True, True, 0)
        scroll = body.get_children()[-1]
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroll.add(self.text)
        actions = row(10)
        self.single_line = Gtk.CheckButton.new_with_label("Single line")
        self.single_line.connect("toggled", lambda unused: self.apply_single_line())
        actions.pack_start(self.single_line, False, False, 0)
        actions.pack_end(button("Copy", self.copy), False, False, 0)
        body.add(actions)
        self.buffer = self.text.get_buffer()
        self.connect("destroy", lambda unused: self.job.cancel() if getattr(self, "job", None) else None)
        self.show_all()
        self.recognize()

    def recognize(self):
        self.generation += 1
        generation = self.generation
        if getattr(self, "job", None):
            self.job.cancel()
        self.retry.set_sensitive(False)
        self.text.set_sensitive(False)
        self.message.set_text("Recognizing text…")
        self.job = self.app.worker.run("ocr", self.path, success=lambda text: self.recognized(generation, text),
                                       failure=lambda error: self.failed(generation, error))

    def recognized(self, generation, text):
        if generation != self.generation:
            return
        self.retry.set_sensitive(True)
        self.text.set_sensitive(True)
        self.buffer.set_text(text or "")
        self.message.set_text("No text was found. Try Again with a clearer region." if not text else "")
        if text and self.copied_generation != generation:
            self.copied_generation = generation
            self.app.worker.run("copyText", text=self.displayed_text(), success=lambda _: None,
                                failure=lambda error: self.message.set_text(f"Text recognized, but copying failed. {error}"))

    def failed(self, generation, error):
        if generation != self.generation:
            return
        self.retry.set_sensitive(True)
        self.text.set_sensitive(True)
        self.message.set_text(error)

    def displayed_text(self):
        start, end = self.buffer.get_bounds()
        text = self.buffer.get_text(start, end, True)
        return " ".join(text.split()) if self.single_line.get_active() else text

    def apply_single_line(self):
        if not self.single_line.get_active():
            return
        start, end = self.buffer.get_bounds()
        self.buffer.set_text(" ".join(self.buffer.get_text(start, end, True).split()))

    def copy(self):
        text = self.displayed_text()
        if not text:
            return
        self.app.worker.run("copyText", text=text, success=lambda _: self.message.set_text("Copied."),
                            failure=lambda error: self.message.set_text(f"Copy failed. {error}"))


class MainWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="ShareX Linux")
        self.app = app
        self.set_default_size(500, 420)
        header(self, "ShareX Linux")
        body = column(10, 18)
        self.add(body)
        intro = label("Capture screenshots, recognize text, and manage your image history.")
        intro.set_margin_bottom(4)
        body.add(intro)
        actions = [
            ("fullscreen", "Full Screen", "camera-photo-symbolic"),
            ("region", "Capture Region", "edit-select-symbolic"),
            ("window", "Capture Window", "window-new-symbolic"),
            ("ocrRegion", "Recognize Text in Region", "insert-text-symbolic"),
        ]
        for action, title, icon in actions:
            action_button = Gtk.Button()
            action_button.set_image(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.BUTTON))
            action_button.set_always_show_image(True)
            action_button.set_label(title)
            action_button.set_halign(Gtk.Align.FILL)
            action_button.connect("clicked", lambda unused, name=action: app.perform(name))
            body.add(action_button)
        separator = Gtk.Separator()
        body.add(separator)
        nav = row(8)
        nav.pack_start(button("Image History", lambda: app.perform("history")), True, True, 0)
        nav.pack_start(button("Settings", lambda: app.perform("settings")), True, True, 0)
        body.add(nav)
        self.status = label("", dim=True)
        body.add(self.status)
        self.connect("delete-event", lambda *unused: self.hide_on_delete())
        self.show_all()


class ShareXApplication(Gtk.Application):
    def __init__(self, executable):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        self.executable = executable
        self.worker = BackendWorker(executable)
        self.settings = {}
        self.main_window = None
        self.preferences = None
        self.history = None
        self.countdown = None
        self.capture_job = None
        self.capture_mode = None
        self.notice = None
        self.ocr_windows = []
        self.shortcut_status = ""
        self.shortcuts = Shortcuts(self, self.perform, self.shortcut_message)
        self.settings_job = None
        self._after_settings = []
        self.connect("command-line", self.command_line)
        self.connect("activate", self.activate)
        self.connect("shutdown", self.shutdown)

    def command_line(self, unused, command_line):
        argv = command_line.get_arguments()
        actions = []
        for index, value in enumerate(argv):
            if value == "--action" and index + 1 < len(argv):
                actions.append(argv[index + 1])
            elif value == "--autostart":
                actions.append("--autostart")
        if actions:
            self.ensure_settings(lambda: self.handle_actions(actions))
        else:
            self.present_main()
        command_line.set_exit_status(0)
        return True

    def do_startup(self):
        Gtk.Application.do_startup(self)
        self.ensure_settings()

    def activate(self, unused=None):
        self.present_main()

    def ensure_settings(self, finished=None):
        if self.settings_job:
            self._after_settings.append(finished) if finished else None
            return
        self._after_settings = [finished] if finished else []
        self.settings_job = self.worker.run("settings", success=self.got_settings,
                                            failure=self.settings_failed)

    def got_settings(self, settings):
        self.settings_job = None
        self.settings = settings or {}
        self.settings.setdefault("hotkeys", {})
        self.settings.setdefault("capture", {})
        self.settings.setdefault("ocr", {})
        self.settings.setdefault("startHidden", False)
        self.settings.setdefault("launchAtLogin", False)
        self.shortcuts.apply(self.settings["hotkeys"])
        callbacks = self._after_settings
        self._after_settings = []
        for callback in callbacks:
            if callback:
                callback()

    def settings_failed(self, error):
        self.settings_job = None
        self.shortcut_message(error)
        callbacks = self._after_settings
        self._after_settings = []
        for callback in callbacks:
            if callback:
                callback()

    def settings_saved(self, settings):
        self.settings = settings
        self.shortcuts.apply(settings.get("hotkeys", {}))

    def shortcut_message(self, message):
        self.shortcut_status = message
        if self.main_window:
            self.main_window.status.set_text(message)
        if self.preferences and hasattr(self.preferences, "registration_status"):
            self.preferences.registration_status.set_text(message)

    def present_main(self):
        if self.main_window is None:
            self.main_window = MainWindow(self)
        self.main_window.show_all()
        self.main_window.present()

    def handle_actions(self, actions):
        for action in actions:
            if action == "--autostart":
                if not self.settings.get("startHidden", False):
                    self.present_main()
            else:
                self.perform(action)

    def perform(self, action):
        if action == "quit":
            self.quit()
        elif action in ("fullscreen", "region", "window", "ocrRegion"):
            self.capture(action)
        elif action == "history":
            self.open_history()
        elif action == "settings":
            self.open_settings()

    def capture(self, mode):
        if self.capture_job or self.countdown:
            return
        self.capture_mode = mode
        if self.main_window:
            self.main_window.hide()
        if self.preferences:
            self.preferences.hide()
        if self.history:
            self.history.hide()
        seconds = self.settings.get("capture", {}).get("delaySeconds", 0)
        if seconds:
            self.countdown = Countdown(self.main_window, seconds, self.cancel_capture, self.start_capture_worker)
        else:
            self.start_capture_worker()

    def cancel_capture(self):
        if self.countdown:
            self.countdown.close()
            self.countdown = None
        if self.capture_job:
            self.capture_job.cancel()
            self.capture_job = None
        self.capture_mode = None
        self.present_main()

    def start_capture_worker(self):
        mode = self.capture_mode
        self.countdown = None
        self.capture_job = self.worker.run("capture", mode, success=lambda result: self.capture_done(mode, result),
                                           failure=self.capture_failed)

    def tick_capture(self):
        if self.countdown is None and self.capture_mode and self.capture_job is None:
            self.start_capture_worker()
        return GLib.SOURCE_REMOVE

    def capture_done(self, mode, record):
        self.capture_job = None
        self.capture_mode = None
        if mode == "ocrRegion":
            window = OCRWindow(self, record["path"])
            self.ocr_windows.append(window)
            return
        if self.main_window:
            self.main_window.status.set_text("Screenshot saved.")
        self.notice = CaptureNotice(self, record, record.get("warning"))

    def capture_failed(self, error):
        self.capture_job = None
        self.capture_mode = None
        if error and "cancel" not in error.lower():
            self.show_error("Screenshot could not be completed", error)
        self.present_main()

    def open_history(self):
        if self.history is None:
            self.history = History(self)
        else:
            self.history.present()

    def open_settings(self):
        if self.preferences is None:
            self.preferences = Preferences(self)
        else:
            self.preferences.present()

    def open_ocr(self, path):
        window = OCRWindow(self, path)
        self.ocr_windows.append(window)

    def open_path(self, path, parent=None):
        file = Gio.File.new_for_path(path)
        try:
            if os.path.isdir(path):
                launcher = Gio.AppInfo.launch_default_for_uri(file.get_uri(), None)
            else:
                launcher = Gio.AppInfo.launch_default_for_uri(file.get_uri(), None)
            if not launcher:
                raise RuntimeError("No application is registered for this path.")
        except GLib.Error as error:
            self.show_error("Could not open path", error.message, parent)

    def show_error(self, title, message, parent=None):
        dialog = Gtk.MessageDialog(transient_for=parent or self.main_window, application=self, modal=True,
                                   message_type=Gtk.MessageType.ERROR, buttons=Gtk.ButtonsType.CLOSE, text=title)
        dialog.format_secondary_text(message)
        dialog.connect("response", lambda *unused: dialog.destroy())
        dialog.show()

    def shutdown(self, unused=None):
        if self.countdown:
            self.countdown.close()
        if self.capture_job:
            self.capture_job.cancel()
        self.worker.cancel_all()
        self.shortcuts.close()


def main():
    if len(sys.argv) < 2:
        print("Usage: sharex_ui.py <absolute Swift executable> [--action ...]", file=sys.stderr)
        return 2
    executable = os.path.abspath(sys.argv[1])
    app = ShareXApplication(executable)
    return app.run(sys.argv)


if __name__ == "__main__":
    raise SystemExit(main())
