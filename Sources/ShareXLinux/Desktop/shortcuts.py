"""Native desktop global shortcuts for ShareX Linux.

The module deliberately does not invoke a shell.  X11 uses the Keybinder3 GI
module, while Wayland uses org.freedesktop.portal.GlobalShortcuts.  Portal
configuration is only requested by :meth:`Shortcuts.configure`, which callers
should wire to an explicit user gesture.
"""
from __future__ import annotations

import os
import secrets
from typing import Any, Callable, Dict, Iterable, Mapping, Optional, Sequence, Tuple

ACTIONS = ("fullscreen", "region", "window", "ocrRegion", "history", "settings", "quit")
DEFAULT_HOTKEYS = {
    "region": [{"key": "p", "modifiers": ["alt"]}],
    "ocrRegion": [{"key": "p", "modifiers": ["shift"]}],
}
_MODIFIERS = {"alt", "control", "ctrl", "shift", "super", "meta", "logo"}
# The XKB names accepted by the freedesktop shortcuts specification.  GDK
# accelerator names use the same names for the common keys below.
_KEY_NAMES = {
    "space", "tab", "return", "enter", "escape", "esc", "backspace",
    "delete", "insert", "home", "end", "page_up", "page_down",
    "left", "right", "up", "down", "print", "menu", "pause", "break",
    "caps_lock", "num_lock", "scroll_lock", "f1", "f2", "f3", "f4",
    "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "f13",
    "f14", "f15", "f16", "f17", "f18", "f19", "f20", "f21", "f22",
    "f23", "f24",
}
_KEY_CANONICAL = {name: name for name in _KEY_NAMES}
_KEY_CANONICAL.update({name.lower(): name for name in _KEY_NAMES})
_KEY_CANONICAL.update({
    "esc": "Escape", "return": "Return", "enter": "Return",
    "space": "space", "tab": "Tab", "backspace": "BackSpace",
    "delete": "Delete", "page_up": "Page_Up", "page_down": "Page_Down",
    "left": "Left", "right": "Right", "up": "Up", "down": "Down",
    "print": "Print", "menu": "Menu",
    "xf86audiomute": "XF86AudioMute", "xf86audioraisevolume": "XF86AudioRaiseVolume",
    "xf86audiolowervolume": "XF86AudioLowerVolume", "xf86audioplay": "XF86AudioPlay",
})
for _function_key in tuple(f"f{index}" for index in range(1, 25)):
    _KEY_CANONICAL[_function_key] = _function_key.upper()


class BindingError(ValueError):
    """A single malformed or conflicting binding."""


def _text(value: Any) -> str:
    return str(value or "").strip()


def _normalize_modifier(value: Any) -> str:
    modifier = _text(value).lower()
    aliases = {"option": "alt", "cmd": "super", "command": "super",
               "win": "super", "windows": "super", "logo": "super",
               "ctrl": "control", "meta": "super"}
    return aliases.get(modifier, modifier)


def _normalize_binding(raw: Mapping[str, Any]) -> Tuple[str, Tuple[str, ...]]:
    if not isinstance(raw, Mapping):
        raise BindingError("shortcut must be an object with key and modifiers")
    key = _text(raw.get("key"))
    if not key:
        raise BindingError("key is required")
    key_lower = key.lower()
    if len(key_lower) > 1 and key_lower not in _KEY_NAMES and not (
        key_lower.startswith("xf86") or key_lower.startswith("kp_")
    ):
        raise BindingError(f"unsupported key '{key}'")
    if len(key_lower) == 1 and not (key_lower.isascii() and (key_lower.isalnum() or key_lower in "-=[]\\;',./`~")):
        raise BindingError(f"unsupported key '{key}'")
    modifiers_raw = raw.get("modifiers", [])
    if modifiers_raw is None:
        modifiers_raw = []
    if isinstance(modifiers_raw, (str, bytes)):
        modifiers_raw = [modifiers_raw]
    modifiers = tuple(_normalize_modifier(item) for item in modifiers_raw)
    if any(item not in _MODIFIERS for item in modifiers):
        bad = next(item for item in modifiers if item not in _MODIFIERS)
        raise BindingError(f"unsupported modifier '{bad}'")
    if len(set(modifiers)) != len(modifiers):
        raise BindingError("modifier is repeated")
    canonical_key = _KEY_CANONICAL.get(key_lower, key_lower)
    if key_lower.startswith("xf86"):
        canonical_key = _KEY_CANONICAL.get(key_lower, "XF86" + key_lower[4:])
    return canonical_key, modifiers


def _iter_bindings(hotkeys: Mapping[str, Sequence[Mapping[str, Any]]]):
    seen: Dict[Tuple[str, Tuple[str, ...]], str] = {}
    for action, values in hotkeys.items():
        if action not in ACTIONS:
            yield action, None, f"unknown action '{action}'"
            continue
        if values is None:
            continue
        if not isinstance(values, Sequence) or isinstance(values, (str, bytes)):
            yield action, None, "bindings must be a list"
            continue
        for raw in values:
            try:
                binding = _normalize_binding(raw)
            except BindingError as error:
                yield action, None, str(error)
                continue
            if binding in seen:
                yield action, None, f"shortcut is already assigned to {seen[binding]}"
                continue
            seen[binding] = action
            yield action, binding, None


def _accelerator(key: str, modifiers: Iterable[str]) -> str:
    tags = {"alt": "Alt", "control": "Control", "shift": "Shift", "super": "Super"}
    return "".join(f"<{tags[item]}>" for item in modifiers) + key


def _portal_trigger(key: str, modifiers: Iterable[str]) -> str:
    tags = {"alt": "ALT", "control": "CTRL", "shift": "SHIFT", "super": "LOGO"}
    modifier_text = "+".join(tags[item] for item in modifiers)
    # The specification uses XKB names without the XKB_KEY_ prefix.
    key_name = _KEY_CANONICAL.get(key.lower(), key)
    return "+".join(item for item in (modifier_text, key_name) if item)


class _PortalBackend:
    def __init__(self, application: Any, on_action: Callable[[str], None], on_status: Callable[[str], None]):
        self.application = application
        self.on_action = on_action
        self.on_status = on_status
        self.Gio = None
        self.GLib = None
        self.proxy = None
        self.bus = None
        self.session: Optional[str] = None
        self.signal_id = None
        self._bound = False
        self._requested: list[Tuple[str, Tuple[str, ...]]] = []
        self._load()

    def _load(self) -> None:
        try:
            import gi  # type: ignore
            gi.require_version("Gio", "2.0")
            gi.require_version("GLib", "2.0")
            from gi.repository import Gio, GLib  # type: ignore
            self.Gio, self.GLib = Gio, GLib
            self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            self.proxy = Gio.DBusProxy.new_sync(
                self.bus, Gio.DBusProxyFlags.NONE, None,
                "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
                "org.freedesktop.portal.GlobalShortcuts", None,
            )
            self.signal_id = self.proxy.connect("g-signal", self._signal)
        except Exception as error:
            self.proxy = None
            self.on_status(f"Wayland global shortcuts are unavailable ({error}). Configure compositor bindings for ShareXLinux --action …")

    def available(self) -> bool:
        if self.proxy is None:
            return False
        try:
            version = self.proxy.get_cached_property("version")
            return version is None or int(version.unpack()) >= 1
        except Exception:
            return True

    def _token(self, prefix: str) -> str:
        return prefix + secrets.token_hex(8)

    def _wait_response(self, request: str) -> Mapping[str, Any]:
        response: Dict[str, Any] = {}
        done = {"value": False}

        def signal(_connection: Any, _sender: str, _path: str, _interface: str,
                   _member: str, parameters: Any, _user_data: Any) -> None:
            values = parameters.unpack()
            if not values or int(values[0]) != 0:
                response["error"] = "The desktop shortcut request was cancelled."
            elif len(values) > 1:
                response.update(values[1])
            done["value"] = True

        subscription = self.bus.signal_subscribe(
            "org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request", "Response",
            request, None, self.Gio.DBusSignalFlags.NONE, signal, None,
        )
        try:
            context = self.GLib.MainContext.default()
            while not done["value"]:
                context.iteration(True)
        finally:
            self.bus.signal_unsubscribe(subscription)
        if "error" in response:
            raise RuntimeError(response["error"])
        return response

    def _call_request(self, method: str, parameters: Any) -> Mapping[str, Any]:
        result = self.proxy.call_sync(method, parameters, self.Gio.DBusCallFlags.NONE, -1, None)
        request = result.unpack()[0]
        return self._wait_response(request)

    def _application_id(self) -> str:
        if hasattr(self.application, "get_application_id"):
            value = self.application.get_application_id()
            if value:
                return str(value)
        return "io.github.PDGamerSG.ShareXLinux"

    def _register_application(self) -> None:
        # The host registry is optional and absent in older portal versions.
        try:
            self.bus.call_sync(
                "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
                "org.freedesktop.host.portal.Registry", "Register",
                self.GLib.Variant("(sa{sv})", (self._application_id(), {})),
                None, self.Gio.DBusCallFlags.NONE, 1500, None,
            )
        except Exception:
            pass

    def _ensure_session(self) -> None:
        if not self.available():
            return
        self._register_application()
        if self.session is None:
            options = {
                "handle_token": self.GLib.Variant("s", self._token("sharex")),
                "session_handle_token": self.GLib.Variant("s", self._token("session")),
            }
            values = self._call_request("CreateSession", self.GLib.Variant("(a{sv})", (options,)))
            self.session = values.get("session_handle")
            if not self.session:
                raise RuntimeError("The global shortcut portal did not return a session.")

    def _bind(self) -> None:
        if not self.available() or not self.session or self._bound:
            return
        descriptions = []
        for action, (key, modifiers) in self._requested:
            descriptions.append((action, {
                "description": self.GLib.Variant("s", f"ShareX {action} capture/action"),
                "preferred_trigger": self.GLib.Variant("s", _portal_trigger(key, modifiers)),
            }))
        options = {"handle_token": self.GLib.Variant("s", self._token("bind"))}
        response = self._call_request("BindShortcuts", self.GLib.Variant(
            "(oa(sa{sv})sa{sv})", (self.session, descriptions, "", options)
        ))
        bound = {str(item[0]) for item in response.get("shortcuts", [])}
        for action, _binding in self._requested:
            if action not in bound:
                self.on_status(f"Shortcut {action}: the desktop portal rejected this binding")
        self._bound = True

    def apply(self, bindings: Sequence[Tuple[str, Tuple[str, ...]]]) -> None:
        self._requested = list(bindings)
        if self.available():
            self._ensure_session()
            # ListShortcuts restores a previously consented session without
            # opening a portal dialog during application startup. A first-time
            # binding is deferred until configure() is called by the settings
            # button, which is an explicit user gesture.
            if self.session:
                values = self._call_request("ListShortcuts", self.GLib.Variant("(oa{sv})", (self.session, {})))
                self._bound = bool(values.get("shortcuts"))
                if not self._bound and self._requested:
                    self.on_status("Open Configure desktop shortcuts to authorize ShareX global shortcuts.")

    def configure(self) -> None:
        if self.available():
            self._ensure_session()
            self._bind()
        if self.available() and self.session:
            self.proxy.call_sync("ConfigureShortcuts", self.GLib.Variant("(osa{sv})", (self.session, "", {})),
                                 self.Gio.DBusCallFlags.NONE, -1, None)

    def close(self) -> None:
        if self.signal_id is not None and self.proxy is not None:
            try:
                self.proxy.disconnect(self.signal_id)
            except Exception:
                pass
            self.signal_id = None
        self.session = None
        self._bound = False

    def _signal(self, _proxy: Any, _sender: str, signal_name: str, parameters: Any) -> None:
        if signal_name != "Activated":
            return
        values = parameters.unpack()
        if len(values) >= 2 and (self.session is None or values[0] == self.session):
            self.on_action(str(values[1]))


class Shortcuts:
    """Owns one process-wide set of global shortcut registrations."""

    def __init__(self, application: Any, on_action: Callable[[str], None], on_status: Callable[[str], None]):
        self.application = application
        self.on_action = on_action
        self.on_status = on_status
        self._keybinder = None
        self._portal: Optional[_PortalBackend] = None
        self._bindings: list[Tuple[str, Tuple[str, ...]]] = []
        self._callbacks: list[Tuple[str, Callable[..., None]]] = []
        self._session = "wayland" if os.environ.get("WAYLAND_DISPLAY") else "x11" if os.environ.get("DISPLAY") else "unknown"

    def apply(self, hotkeys: Mapping[str, Sequence[Mapping[str, Any]]]) -> None:
        self._close_backend()
        valid: list[Tuple[str, Tuple[str, ...]]] = []
        for action, binding, error in _iter_bindings(hotkeys or {}):
            if error:
                self.on_status(f"Shortcut {action}: {error}")
            elif binding:
                valid.append((action, binding))
        self._bindings = valid
        if self._session == "x11":
            self._apply_x11(valid)
        elif self._session == "wayland":
            self._apply_wayland(valid)
        else:
            self.on_status("Global shortcuts require an active X11 or Wayland desktop session.")

    def _apply_x11(self, bindings: Sequence[Tuple[str, Tuple[str, ...]]]) -> None:
        try:
            import gi  # type: ignore
            gi.require_version("Keybinder", "3.0")
            from gi.repository import Keybinder  # type: ignore
            self._keybinder = Keybinder
            Keybinder.init()
        except Exception as error:
            self.on_status(f"X11 global shortcuts need Keybinder3 ({error}).")
            return
        for action, (key, modifiers) in bindings:
            accelerator = _accelerator(key, modifiers)
            def callback(_keystring: str, _user_data: Any, action: str = action) -> None:
                self.on_action(action)
            try:
                if not bool(Keybinder.bind(accelerator, callback, None)):
                    self.on_status(f"Shortcut {action}: X11 rejected {accelerator}")
                    continue
                self._callbacks.append((accelerator, callback))
            except Exception as error:
                self.on_status(f"Shortcut {action}: {error}")

    def _apply_wayland(self, bindings: Sequence[Tuple[str, Tuple[str, ...]]]) -> None:
        try:
            self._portal = _PortalBackend(self.application, self.on_action, self.on_status)
            if self._portal.available():
                self._portal.apply(bindings)
            else:
                self._portal = None
        except Exception as error:
            self._portal = None
            self.on_status(f"Global shortcuts could not be registered ({error}). Configure compositor bindings for ShareXLinux --action …")

    def configure(self) -> None:
        """Open the desktop portal's shortcut editor after an explicit user gesture."""
        if self._portal is not None:
            try:
                self._portal.configure()
                return
            except Exception as error:
                self.on_status(f"Shortcut configuration failed ({error}).")
        else:
            self.on_status("Configure compositor shortcuts to run ShareXLinux --action <fullscreen|region|window|ocrRegion|history|settings>.")

    def set_recording(self, active: bool) -> None:
        """Temporarily release X11 grabs while GTK records a new shortcut."""
        if self._keybinder is None:
            return
        if active:
            for accelerator, callback in self._callbacks:
                try:
                    self._keybinder.unbind(accelerator, callback)
                except Exception:
                    pass
        else:
            old = list(self._bindings)
            self._callbacks.clear()
            self._apply_x11(old)

    def close(self) -> None:
        self._close_backend()
        self._bindings = []

    def _close_backend(self) -> None:
        if self._keybinder is not None:
            for accelerator, callback in self._callbacks:
                try:
                    self._keybinder.unbind(accelerator, callback)
                except Exception:
                    pass
            self._callbacks.clear()
            self._keybinder = None
        if self._portal is not None:
            self._portal.close()
            self._portal = None
