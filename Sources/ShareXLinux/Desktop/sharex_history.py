import os
from datetime import datetime

from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, Pango

from sharex_widgets import button, column, header, icon_button, label, load_image, row, scrolled


THUMB, SMALL_THUMB, NAME, MODE, SIZE, DATE, CAPTION = range(7)
MODE_NAMES = {"fullscreen": "Full screen", "region": "Region", "window": "Window", "ocrRegion": "OCR region"}


def fit(pixbuf, max_width, max_height):
    scale = min(max_width / pixbuf.get_width(), max_height / pixbuf.get_height(), 1)
    if scale >= 1:
        return pixbuf
    return pixbuf.scale_simple(max(1, int(scale * pixbuf.get_width())),
                               max(1, int(scale * pixbuf.get_height())), GdkPixbuf.InterpType.BILINEAR)


class Preview(Gtk.ApplicationWindow):
    def __init__(self, app, record):
        title = os.path.basename(record["path"])
        super().__init__(application=app, title=title)
        self.set_default_size(820, 580)
        bar = header(self, title)
        bar.set_subtitle(f'{record["width"]} × {record["height"]}')
        self.image = Gtk.Image()
        self.image.get_accessible().set_name(title)
        self.scroll = scrolled(self.image)
        self.scroll.set_overlay_scrolling(False)
        self.stack = Gtk.Stack()
        self.message = label("Loading preview…")
        self.message.set_halign(Gtk.Align.CENTER)
        self.stack.add_named(self.message, "message")
        self.stack.add_named(self.scroll, "image")
        self.add(self.stack)
        self.original = None
        self.last_size = None
        self.request = Gio.Cancellable()
        self.scroll.connect("size-allocate", self.fit_image)
        self.connect("destroy", lambda window: self.request.cancel())
        self.connect("key-press-event", self.key_pressed)
        self.show_all()
        self.present()
        load_image(record["path"], 2400, 2400, self.request, self.loaded)

    def loaded(self, pixbuf, error):
        if self.request.is_cancelled():
            return
        if error:
            self.message.set_text(error)
            return
        self.original = pixbuf
        self.stack.set_visible_child_name("image")
        self.fit_image(self.scroll, self.scroll.get_allocation())

    def fit_image(self, unused, allocation):
        size = (max(1, allocation.width - 12), max(1, allocation.height - 12))
        if self.original is not None and size != self.last_size:
            self.last_size = size
            self.image.set_from_pixbuf(fit(self.original, *size))

    def key_pressed(self, unused, event):
        if event.keyval == Gdk.KEY_Escape:
            self.destroy()
            return True
        return False


class History(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Image History")
        self.app = app
        self.set_default_size(790, 520)
        bar = header(self, "Image History")
        bar.pack_start(icon_button("view-refresh-symbolic", "Refresh history", self.reload))
        self.layout = Gtk.ComboBoxText()
        self.layout.append("grid", "Thumbnails")
        self.layout.append("list", "List")
        self.layout.set_active_id("grid")
        self.layout.get_accessible().set_name("History layout")
        bar.pack_end(self.layout)
        outer = column(10, 12)
        self.add(outer)
        self.search = Gtk.SearchEntry(placeholder_text="Search filenames")
        self.search.get_accessible().set_name("Search screenshot filenames")
        self.search.connect("search-changed", lambda unused: self.reload())
        outer.add(self.search)
        self.model = Gtk.ListStore(GdkPixbuf.Pixbuf, GdkPixbuf.Pixbuf, str, str, str, str, str)
        self.entries = []
        self.query_job = None
        self.closed = False
        self.wanted = range(0)
        self.pending_images = {}
        self.loaded_images = set()
        self.update_source = 0
        self.placeholder = self.theme_icon("image-x-generic", 32)
        self.missing = self.theme_icon("image-missing", 32)
        self.stack = Gtk.Stack()
        self.empty = label("Loading history…", dim=True)
        self.empty.set_halign(Gtk.Align.CENTER)
        self.stack.add_named(self.empty, "empty")
        self.grid = self.make_grid()
        self.table = self.make_table()
        for name, view in [("grid", self.grid), ("list", self.table)]:
            pane = scrolled(view)
            pane.get_vadjustment().connect("value-changed", self.queue_thumbnails)
            pane.connect("size-allocate", self.queue_thumbnails)
            self.stack.add_named(pane, name)
            view.connect("key-press-event", self.key_pressed)
        outer.pack_start(self.stack, True, True, 0)

        footer = row()
        self.status = label("", dim=True)
        footer.pack_start(self.status, True, True, 0)
        self.controls = {}
        for action in ["Preview", "Copy Image"]:
            self.controls[action] = button(action, lambda name=action: self.perform(name))
            footer.add(self.controls[action])
        self.menu_button = Gtk.MenuButton(label="Actions ▾")
        menu = Gtk.Menu()
        for action in ["Open", "Open Folder", "Copy Path", "Recognize Text", "Delete…"]:
            if action == "Delete…":
                menu.append(Gtk.SeparatorMenuItem())
            item = Gtk.MenuItem.new_with_label(action)
            item.connect("activate", lambda unused, name=action: self.perform(name))
            self.controls[action] = item
            menu.append(item)
        menu.show_all()
        self.menu_button.set_popup(menu)
        footer.add(self.menu_button)
        outer.add(footer)
        self.grid.connect("selection-changed", self.update_controls)
        self.table.get_selection().connect("changed", self.update_controls)
        self.layout.connect("changed", self.change_view)
        self.connect("map", self.queue_thumbnails)
        self.connect("destroy", self.on_destroy)
        self.update_controls()
        self.show_all()
        self.reload()

    def theme_icon(self, name, size):
        try:
            screen = self.get_screen()
            theme = Gtk.IconTheme.get_for_screen(screen) if screen else Gtk.IconTheme.get_default()
            return theme.load_icon(name, size, 0)
        except GLib.Error:
            return None

    def make_grid(self):
        view = Gtk.IconView.new_with_model(self.model)
        view.set_item_width(158)
        view.set_item_padding(6)
        view.set_margin(6)
        view.set_row_spacing(8)
        view.set_column_spacing(8)
        view.set_selection_mode(Gtk.SelectionMode.SINGLE)
        picture = Gtk.CellRendererPixbuf()
        picture.set_fixed_size(148, 88)
        view.pack_start(picture, False)
        view.add_attribute(picture, "pixbuf", THUMB)
        caption = Gtk.CellRendererText(ellipsize=Pango.EllipsizeMode.MIDDLE, alignment=Pango.Alignment.CENTER,
                                       xalign=0.5, width=148)
        view.pack_start(caption, False)
        view.add_attribute(caption, "markup", CAPTION)
        view.connect("item-activated", lambda *unused: self.perform("Preview"))
        return view

    def make_table(self):
        view = Gtk.TreeView.new_with_model(self.model)
        view.set_search_column(NAME)
        name = Gtk.TreeViewColumn("Filename")
        thumb = Gtk.CellRendererPixbuf()
        thumb.set_fixed_size(48, 36)
        name.pack_start(thumb, False)
        name.add_attribute(thumb, "pixbuf", SMALL_THUMB)
        text = Gtk.CellRendererText(ellipsize=Pango.EllipsizeMode.MIDDLE)
        name.pack_start(text, True)
        name.add_attribute(text, "text", NAME)
        name.set_expand(True)
        name.set_min_width(100)
        view.append_column(name)
        for title, index in [("Capture", MODE), ("Size", SIZE), ("Date", DATE)]:
            view.append_column(Gtk.TreeViewColumn(title, Gtk.CellRendererText(), text=index))
        view.connect("row-activated", lambda *unused: self.perform("Preview"))
        return view

    def reload(self):
        if self.query_job:
            self.query_job.cancel()
        self.status.set_text("Loading…")
        self.query_job = self.app.worker.run("history", self.search.get_text(), success=self.got_entries,
                                             failure=self.history_error)

    def history_error(self, message):
        if not self.entries:
            self.empty.set_text("History could not be loaded.")
        self.status.set_text(message)

    def got_entries(self, entries):
        selected = self.selected()
        self.reset_thumbnails()
        self.model.clear()
        self.entries = entries
        selected_path = None
        for i, entry in enumerate(entries):
            name = os.path.basename(entry["path"])
            date = datetime.fromtimestamp(entry["timestamp"]).strftime("%x %H:%M")
            size = "File missing" if entry["isMissing"] else f'{entry["width"]} × {entry["height"]}'
            caption = f"{GLib.markup_escape_text(name)}\n<small>{size}\n{GLib.markup_escape_text(date)}</small>"
            icon = self.missing if entry["isMissing"] else self.placeholder
            self.model.append((icon, icon, name, MODE_NAMES.get(entry["mode"], entry["mode"]), size, date, caption))
            if selected and entry["id"] == selected["id"]:
                selected_path = Gtk.TreePath.new_from_indices([i])
        self.empty.set_text("No matching screenshots" if self.search.get_text() else "No screenshots yet")
        self.stack.set_visible_child_name(self.layout.get_active_id() if entries else "empty")
        if selected_path is not None:
            self.select_path(selected_path)
        self.status.set_text(f"{len(entries)} screenshot" + ("" if len(entries) == 1 else "s"))
        self.update_controls()
        self.queue_thumbnails()

    def selected_path(self, name):
        if name == "list":
            model, iterator = self.table.get_selection().get_selected()
            return model.get_path(iterator) if iterator is not None else None
        paths = self.grid.get_selected_items()
        return paths[0] if paths else None

    def select_path(self, path):
        self.grid.select_path(path)
        self.table.get_selection().select_path(path)

    def selected(self):
        path = self.selected_path(self.layout.get_active_id())
        if path is not None:
            index = path.get_indices()[0]
            if index < len(self.entries):
                return self.entries[index]
        return None

    def change_view(self, unused):
        if not self.entries:
            return
        old = self.stack.get_visible_child_name()
        path = self.selected_path(old)
        self.stack.set_visible_child_name(self.layout.get_active_id())
        if path is None:
            self.grid.unselect_all()
            self.table.get_selection().unselect_all()
        else:
            self.select_path(path)
        self.update_controls()
        self.queue_thumbnails()

    def update_controls(self, *unused):
        entry = self.selected()
        self.menu_button.set_sensitive(entry is not None)
        for action, widget in self.controls.items():
            widget.set_sensitive(bool(entry and (not entry["isMissing"] or action in ("Copy Path", "Delete…"))))

    def key_pressed(self, unused, event):
        if event.keyval in (Gdk.KEY_Delete, Gdk.KEY_KP_Delete):
            self.perform("Delete…")
            return True
        if event.keyval == Gdk.KEY_space:
            self.perform("Preview")
            return True
        return False

    def perform(self, action):
        entry = self.selected()
        if not entry or not self.controls[action].get_sensitive():
            return
        path = entry["path"]
        if action == "Preview":
            Preview(self.app, entry)
        elif action in ("Open", "Open Folder"):
            self.app.open_path(os.path.dirname(path) if action == "Open Folder" else path, self)
        elif action == "Recognize Text":
            self.app.open_ocr(path)
        elif action == "Delete…":
            self.confirm_delete(entry)
        else:
            if action == "Copy Image":
                self.app.worker.run("copyImage", path, success=lambda _: self.status.set_text("Image copied."),
                                    failure=self.status.set_text)
            else:
                self.app.worker.run("copyText", text=path, success=lambda _: self.status.set_text("Path copied."),
                                    failure=self.status.set_text)

    def confirm_delete(self, entry):
        name = os.path.basename(entry["path"])
        dialog = Gtk.MessageDialog(transient_for=self, application=self.app, modal=True, destroy_with_parent=True,
                                   message_type=Gtk.MessageType.QUESTION, text="Delete screenshot?")
        dialog.format_secondary_text(f"Remove {name} from history?" if entry["isMissing"]
                                     else f"Delete {name} from disk and history? This cannot be undone.")
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        delete = dialog.add_button("Delete", Gtk.ResponseType.OK)
        delete.get_style_context().add_class("destructive-action")
        dialog.set_default_response(Gtk.ResponseType.CANCEL)

        def respond(unused, response):
            dialog.destroy()
            if response == Gtk.ResponseType.OK:
                self.app.worker.run("delete", entry["id"], success=lambda _: self.reload() if not self.closed else None,
                                    failure=lambda error: self.app.show_error("Could not delete screenshot", error))

        dialog.connect("response", respond)
        dialog.show()

    def reset_thumbnails(self):
        for request in self.pending_images.values():
            request.cancel()
        self.pending_images.clear()
        self.loaded_images.clear()
        self.wanted = range(0)

    def queue_thumbnails(self, *unused):
        if not self.closed and not self.update_source:
            self.update_source = GLib.idle_add(self.load_visible)

    def load_visible(self):
        self.update_source = 0
        if not self.entries or not self.get_mapped():
            return False
        view = self.grid if self.layout.get_active_id() == "grid" else self.table
        visible = view.get_visible_range()
        if visible and visible[-2] is not None and visible[-1] is not None:
            first, last = (path.get_indices()[0] for path in visible[-2:])
        else:
            first, last = 0, 12
        self.wanted = range(max(0, first - 4), min(len(self.entries), last + 5))
        for index in self.loaded_images.difference(self.wanted):
            icon = self.missing if self.entries[index]["isMissing"] else self.placeholder
            self.model[index][THUMB] = icon
            self.model[index][SMALL_THUMB] = icon
            self.loaded_images.remove(index)
        for index in list(self.pending_images):
            if index not in self.wanted:
                self.pending_images.pop(index).cancel()
        self.load_next()
        return False

    def load_next(self):
        # Limit both the number of open files and thumbnail memory when scrolling through a large history.
        for index in self.wanted:
            if len(self.pending_images) >= 4:
                break
            if index in self.loaded_images or index in self.pending_images or self.entries[index]["isMissing"]:
                continue
            request = Gio.Cancellable()
            self.pending_images[index] = request
            load_image(self.entries[index]["path"], 146, 88, request,
                       lambda pixbuf, error, i=index, r=request: self.thumbnail_loaded(i, r, pixbuf))

    def thumbnail_loaded(self, index, request, pixbuf):
        if self.pending_images.get(index) is not request:
            return
        del self.pending_images[index]
        self.loaded_images.add(index)
        if pixbuf is not None:
            self.model[index][THUMB] = pixbuf
            self.model[index][SMALL_THUMB] = fit(pixbuf, 44, 32)
        self.load_next()

    def on_destroy(self, unused):
        self.closed = True
        if self.query_job:
            self.query_job.cancel()
        if self.update_source:
            GLib.source_remove(self.update_source)
        self.reset_thumbnails()
