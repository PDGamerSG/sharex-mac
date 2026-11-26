#!/usr/bin/env python3
"""Capture one screenshot through the freedesktop Screenshot portal.

This helper is intentionally a small, unsandboxed GTK/GLib program.  It is
launched directly by Swift with an argument array and never evaluates a shell
command.  A portal request is consented by the desktop, and a cancelled
request exits with status 130.
"""
from __future__ import annotations

import os
import secrets
import sys
from typing import Any, Mapping

APP_ID = "io.github.PDGamerSG.ShareXLinux"
TARGETS = {"fullscreen": 1, "window": 2, "region": 4, "ocrRegion": 4}


class PortalCancelled(Exception):
    pass


class PortalError(RuntimeError):
    pass


def _load_gi():
    try:
        import gi  # type: ignore
        gi.require_version("Gio", "2.0")
        gi.require_version("GLib", "2.0")
        from gi.repository import Gio, GLib  # type: ignore
        return Gio, GLib
    except Exception as error:
        raise PortalError(f"GTK portal support is unavailable: {error}") from error


def _wait_response(Gio: Any, GLib: Any, bus: Any, request: str) -> Mapping[str, Any]:
    done = {"value": False}
    result: dict[str, Any] = {}

    def response(_connection: Any, _sender: str, _path: str, _interface: str,
                 _member: str, parameters: Any, _data: Any) -> None:
        values = parameters.unpack()
        if not values or int(values[0]) == 1:
            result["cancelled"] = True
        elif int(values[0]) != 0:
            result["error"] = f"The desktop screenshot portal denied the request (response {values[0]})."
        elif len(values) > 1:
            result.update(values[1])
        done["value"] = True

    subscription = bus.signal_subscribe(
        "org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request", "Response",
        request, None, Gio.DBusSignalFlags.NONE, response, None,
    )
    try:
        context = GLib.MainContext.default()
        while not done["value"]:
            context.iteration(True)
    finally:
        bus.signal_unsubscribe(subscription)
    if result.pop("cancelled", False):
        raise PortalCancelled()
    if "error" in result:
        raise PortalError(result["error"])
    return result


def _request(Gio: Any, GLib: Any, bus: Any, method: str, parameters: Any) -> Mapping[str, Any]:
    result = bus.call_sync(
        "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.Screenshot", method, parameters, None,
        Gio.DBusCallFlags.NONE, -1, None,
    )
    request = result.unpack()[0]
    return _wait_response(Gio, GLib, bus, request)


def _register_application(Gio: Any, GLib: Any, bus: Any) -> None:
    try:
        bus.call_sync(
            "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
            "org.freedesktop.host.portal.Registry", "Register",
            GLib.Variant("(sa{sv})", (APP_ID, {})), None,
            Gio.DBusCallFlags.NONE, 1500, None,
        )
    except Exception:
        # The host registry is optional for unsandboxed applications and old
        # portal releases.  Screenshot itself remains fully consented.
        pass


def capture(mode: str, output: str, include_cursor: bool = False) -> None:
    if mode not in TARGETS:
        raise PortalError(f"Unsupported screenshot mode '{mode}'")
    Gio, GLib = _load_gi()
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    _register_application(Gio, GLib, bus)
    proxy = Gio.DBusProxy.new_sync(
        bus, Gio.DBusProxyFlags.NONE, None, "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop", "org.freedesktop.portal.Screenshot", None,
    )
    available = proxy.get_cached_property("AvailableTargets")
    if available is not None and (int(available.unpack()) & TARGETS[mode]) == 0:
        raise PortalError(f"The desktop screenshot portal does not support {mode} capture")
    options = {
        "handle_token": GLib.Variant("s", "sharex" + secrets.token_hex(8)),
        "modal": GLib.Variant("b", True),
        "interactive": GLib.Variant("b", mode != "fullscreen"),
        "target": GLib.Variant("u", TARGETS[mode]),
    }
    # Screenshot portal v3 does not expose a cursor option. Backends such as
    # grim and gnome-screenshot include it directly, while consented portal
    # captures use the desktop's own cursor policy.
    values = _request(Gio, GLib, bus, "Screenshot", GLib.Variant("(sa{sv})", ("", options)))
    uri = values.get("uri")
    if not uri:
        raise PortalError("The desktop screenshot portal returned no image URI")
    source = Gio.File.new_for_uri(str(uri))
    destination = Gio.File.new_for_path(os.path.abspath(output))
    parent = destination.get_parent()
    if parent is not None and not parent.query_exists(None):
        parent.make_directory_with_parents(None)
    if destination.query_exists(None):
        destination.delete(None)
    source.copy(destination, Gio.FileCopyFlags.OVERWRITE, None, None, None)


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(f"usage: {argv[0]} MODE OUTPUT [--cursor]", file=sys.stderr)
        return 2
    try:
        capture(argv[1], argv[2], "--cursor" in argv[3:])
    except (PortalCancelled, KeyboardInterrupt):
        return 130
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
