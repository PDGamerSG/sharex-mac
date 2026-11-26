from gi.repository import GdkPixbuf, Gio, GLib, Gtk, Pango


ACTION_TITLES = {
    "fullscreen": "Full Screen",
    "region": "Capture Region",
    "window": "Capture Window",
    "ocrRegion": "Recognize Text in Region",
    "history": "Image History",
    "settings": "Settings",
    "quit": "Quit ShareX",
}


def column(spacing=12, border=0):
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=spacing)
    box.set_border_width(border)
    return box


def row(spacing=8):
    return Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=spacing)


def label(text="", dim=False):
    widget = Gtk.Label(label=text, xalign=0)
    widget.set_line_wrap(True)
    widget.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
    if dim:
        widget.get_style_context().add_class("dim-label")
    return widget


def button(title, clicked, icon=None):
    widget = Gtk.Button.new_with_label(title)
    if icon:
        widget.set_image(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.BUTTON))
        widget.set_always_show_image(True)
    widget.connect("clicked", lambda unused: clicked())
    return widget


def icon_button(icon, title, clicked):
    widget = Gtk.Button.new_from_icon_name(icon, Gtk.IconSize.BUTTON)
    widget.set_tooltip_text(title)
    widget.get_accessible().set_name(title)
    widget.connect("clicked", lambda unused: clicked())
    return widget


def header(window, title):
    bar = Gtk.HeaderBar(title=title, show_close_button=True)
    window.set_titlebar(bar)
    return bar


def scrolled(child):
    scroll = Gtk.ScrolledWindow()
    scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
    scroll.add(child)
    return scroll


def load_image(path, width, height, cancellable, finished):
    """Decode at the requested size off the GTK thread."""
    def opened(file, result, *unused):
        try:
            stream = file.read_finish(result)
        except GLib.Error as error:
            finished(None, error.message)
            return

        def decoded(unused, result, *extra):
            try:
                pixbuf = GdkPixbuf.Pixbuf.new_from_stream_finish(result)
            except GLib.Error as error:
                finished(None, error.message)
            else:
                finished(pixbuf, None)
            finally:
                stream.close_async(GLib.PRIORITY_DEFAULT, None, None)

        GdkPixbuf.Pixbuf.new_from_stream_at_scale_async(
            stream, width, height, True, cancellable, decoded
        )

    Gio.File.new_for_path(path).read_async(GLib.PRIORITY_DEFAULT, cancellable, opened)
