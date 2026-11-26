# ShareX Linux desktop adapters

`shortcuts.py` is loaded by the GTK process. It uses Keybinder3 through GObject
Introspection for X11. On Wayland it uses
`org.freedesktop.portal.GlobalShortcuts` when the portal advertises the
interface. Portal binding and configuration are user-consented. The settings
button calls `Shortcuts.configure()` explicitly. Existing portal grants are
restored without opening a dialog during startup. If the portal is unavailable,
the status callback gives the compositor binding command, for example
`ShareXLinux --action region`.

`portal_capture.py` is launched with `/usr/bin/python3` and an argument array
by `LinuxCaptureService`. It uses the freedesktop Screenshot portal, requests
an explicit screen, window, or area target, and copies the consented URI to the
worker's private temporary PNG. A denied or cancelled request exits 130 and
never leaves a temporary file.

Runtime dependencies for the native adapters are `python3-gi` and
`gir1.2-gtk-3.0`. X11 shortcut registration additionally needs
`gir1.2-keybinder-3.0`. A GNOME or KDE Wayland desktop should provide
`xdg-desktop-portal` and its GTK or KDE backend.
