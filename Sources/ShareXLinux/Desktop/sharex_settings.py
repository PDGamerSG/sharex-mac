import os
from copy import deepcopy

from gi.repository import Gdk, Gtk

from sharex_widgets import ACTION_TITLES, button, column, header, icon_button, label, row, scrolled


MODIFIERS = (
    ("control", "Ctrl", Gdk.ModifierType.CONTROL_MASK),
    ("alt", "Alt", Gdk.ModifierType.MOD1_MASK),
    ("shift", "Shift", Gdk.ModifierType.SHIFT_MASK),
    ("super", "Super", Gdk.ModifierType.SUPER_MASK | Gdk.ModifierType.MOD4_MASK),
)
MODIFIER_NAMES = {
    "control": "control", "ctrl": "control", "alt": "alt", "option": "alt",
    "shift": "shift", "super": "super", "win": "super", "meta": "super",
    "cmd": "super", "command": "super",
}
MODIFIER_KEYS = {
    "Shift_L", "Shift_R", "Control_L", "Control_R", "Alt_L", "Alt_R", "Meta_L",
    "Meta_R", "Super_L", "Super_R", "Hyper_L", "Hyper_R", "ISO_Level3_Shift",
}
KEY_NAMES = {name[4:].lower(): name[4:] for name in dir(Gdk) if name.startswith("KEY_")}


def key_name(value):
    if len(value) == 1:
        code = Gdk.unicode_to_keyval(ord(value))
    else:
        value = value.lower()
        code = Gdk.keyval_from_name(KEY_NAMES.get(value, value))
    if code in (0, Gdk.KEY_VoidSymbol):
        return None
    return Gdk.keyval_name(Gdk.keyval_to_lower(code))


def binding_title(binding):
    modifiers = {MODIFIER_NAMES.get(name.lower(), name) for name in binding["modifiers"]}
    parts = [title for name, title, _ in MODIFIERS if name in modifiers]
    key = key_name(binding["key"]) or binding["key"]
    parts.append(key.upper() if len(key) == 1 else key)
    return "+".join(parts)


def parse_binding(value):
    value = value.strip()
    if value.endswith("+"):
        value = value[:-1] + "plus"
    *prefix, key = [part.strip() for part in value.split("+")]
    modifiers = []
    for part in prefix:
        modifier = MODIFIER_NAMES.get(part.lower())
        if modifier is None or modifier in modifiers:
            raise ValueError("Use Ctrl, Alt, Shift or Super once before the key name.")
        modifiers.append(modifier)
    name = key_name(key)
    if not name or name in MODIFIER_KEYS:
        raise ValueError("Enter a key such as P, Print, F8 or Page_Up.")
    return {"key": name, "modifiers": [m for m, _, _ in MODIFIERS if m in modifiers]}


def binding_conflict(hotkeys):
    assigned = {}
    for action, bindings in hotkeys.items():
        for binding in bindings:
            title = binding_title(binding)
            if title in assigned:
                other = assigned[title]
                if other == action:
                    return f"{title} is assigned twice to {ACTION_TITLES.get(action, action)}."
                return f"{title} is assigned to both {ACTION_TITLES.get(other, other)} and {ACTION_TITLES.get(action, action)}."
            assigned[title] = action
    return None


class ShortcutEditor(Gtk.Dialog):
    def __init__(self, preferences, action, index):
        super().__init__(title=ACTION_TITLES[action] + " shortcut", transient_for=preferences,
                         modal=True, destroy_with_parent=True, application=preferences.app)
        self.preferences = preferences
        self.action_name = action
        self.index = index
        self.add_button("Cancel", Gtk.ResponseType.CANCEL)
        self.add_button("Set Shortcut", Gtk.ResponseType.OK)
        self.set_default_response(Gtk.ResponseType.OK)
        body = self.get_content_area()
        body.set_spacing(10)
        body.set_border_width(16)
        body.add(label("Enter a shortcut, or select Record Keys and press the combination."))
        controls = row()
        body.add(controls)
        self.entry = Gtk.Entry(placeholder_text="Ctrl+Shift+P", activates_default=True)
        self.entry.get_accessible().set_name("Shortcut")
        if index is not None:
            self.entry.set_text(binding_title(preferences.hotkeys[action][index]))
        controls.pack_start(self.entry, True, True, 0)
        self.record = Gtk.ToggleButton(label="Record Keys")
        controls.add(self.record)
        self.record.connect("toggled", self.recording_changed)
        self.message = label()
        body.add(self.message)
        self.connect("key-press-event", self.key_pressed)
        self.connect("response", self.respond)
        self.connect("destroy", lambda unused: preferences.app.shortcuts.set_recording(False))
        self.show_all()
        self.entry.grab_focus()

    def recording_changed(self, unused):
        active = self.record.get_active()
        self.preferences.app.shortcuts.set_recording(active)
        self.message.set_text("Press the shortcut now. Escape cancels recording." if active else "")

    def key_pressed(self, unused, event):
        if not self.record.get_active():
            return False
        if event.keyval == Gdk.KEY_Escape:
            self.record.set_active(False)
            return True
        if Gdk.keyval_name(event.keyval) in MODIFIER_KEYS:
            return True
        # Read the unshifted key so Shift+1 is recorded identically to typing it.
        keymap = Gdk.Keymap.get_for_display(self.get_display())
        translated = keymap.translate_keyboard_state(event.hardware_keycode, Gdk.ModifierType(0), event.group)
        key = translated[1] if translated[0] else event.keyval
        name = Gdk.keyval_name(Gdk.keyval_to_lower(key))
        if name:
            modifiers = [name for name, _, mask in MODIFIERS if event.state & mask]
            self.entry.set_text(binding_title({"key": name, "modifiers": modifiers}))
            self.record.set_active(False)
            self.get_widget_for_response(Gtk.ResponseType.OK).grab_focus()
        return True

    def respond(self, unused, response):
        if response == Gtk.ResponseType.OK:
            try:
                binding = parse_binding(self.entry.get_text())
            except ValueError as error:
                self.message.set_text(str(error))
                return
            candidate = deepcopy(self.preferences.hotkeys)
            bindings = candidate.setdefault(self.action_name, [])
            if self.index is None:
                bindings.append(binding)
            else:
                bindings[self.index] = binding
            conflict = binding_conflict(candidate)
            if conflict:
                self.message.set_text(conflict)
                return
            self.preferences.hotkeys = candidate
            self.preferences.build_shortcuts()
        self.destroy()


class Preferences(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Settings")
        self.app = app
        self.settings = deepcopy(app.settings)
        self.hotkeys = self.settings["hotkeys"]
        self.selected_languages = list(self.settings["ocr"]["languages"])
        self.folder = self.settings["capture"]["screenshotFolderPath"]
        self.saving = False
        self.set_default_size(640, 525)
        bar = header(self, "Settings")
        self.save_button = button("Save", self.save)
        self.save_button.get_style_context().add_class("suggested-action")
        bar.pack_end(self.save_button)
        self.notebook = Gtk.Notebook()
        self.notebook.set_border_width(12)
        self.notebook.set_scrollable(True)
        outer = column(0)
        self.add(outer)
        outer.pack_start(self.notebook, True, True, 0)
        self.message = label()
        self.message.set_margin_start(16)
        self.message.set_margin_end(16)
        self.message.set_margin_bottom(8)
        outer.add(self.message)
        self.capture_tab()
        self.ocr_tab()
        self.shortcuts_tab()
        self.general_tab()
        self.connect("delete-event", lambda *unused: self.saving)
        self.connect("destroy", self.closed)
        self.show_all()
        self.language_job = app.worker.run("languages", success=self.got_languages,
                                           failure=self.language_status.set_text)

    def page(self, title):
        body = column(12, 16)
        self.notebook.append_page(scrolled(body), Gtk.Label(label=title))
        return body

    @staticmethod
    def check(body, title, active):
        widget = Gtk.CheckButton.new_with_label(title)
        widget.set_active(active)
        body.add(widget)
        return widget

    @staticmethod
    def field(body, title, widget):
        line = row(16)
        name = label(title)
        name.set_mnemonic_widget(widget)
        line.pack_start(name, True, True, 0)
        line.add(widget)
        body.add(line)
        widget.get_accessible().set_name(title)

    def capture_tab(self):
        body = self.page("Capture")
        settings = self.settings["capture"]
        self.cursor = self.check(body, "Include cursor in screenshots", settings.get("showCursor", False))
        self.clipboard = self.check(body, "Copy screenshots to clipboard", settings.get("copyToClipboard", True))
        self.delay = Gtk.SpinButton.new_with_range(0, 60, 0.5)
        self.delay.set_digits(1)
        self.delay.set_value(settings.get("delaySeconds", 0))
        self.field(body, "Capture delay (seconds)", self.delay)
        self.resolution = Gtk.ComboBoxText()
        for value, name in [("full", "Full (100%)"), ("threeQuarter", "75%"), ("half", "50%")]:
            self.resolution.append(value, name)
        self.resolution.set_active_id(settings.get("screenshotResolution", "full"))
        self.field(body, "Screenshot resolution", self.resolution)
        body.add(label("Text recognition captures always use full resolution.", dim=True))
        body.add(Gtk.Separator())
        self.field(body, "Screenshot folder", button("Choose Folder…", self.choose_folder))
        self.folder_label = label(self.folder, dim=True)
        self.folder_label.set_selectable(True)
        body.add(self.folder_label)

    def choose_folder(self):
        dialog = Gtk.FileChooserDialog(title="Choose Screenshot Folder", transient_for=self, modal=True,
                                       destroy_with_parent=True, application=self.app,
                                       action=Gtk.FileChooserAction.SELECT_FOLDER)
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Select", Gtk.ResponseType.OK)
        folder = self.folder
        while folder and not os.path.isdir(folder):
            parent = os.path.dirname(folder)
            if parent == folder:
                break
            folder = parent
        if folder:
            dialog.set_current_folder(folder)

        def chosen(unused, response):
            if response == Gtk.ResponseType.OK and dialog.get_filename():
                self.folder = dialog.get_filename()
                self.folder_label.set_text(self.folder)
            dialog.destroy()

        dialog.connect("response", chosen)
        dialog.show()

    def ocr_tab(self):
        body = self.page("Text Recognition")
        settings = self.settings["ocr"]
        self.scale = Gtk.SpinButton.new_with_range(1, 4, 1)
        self.scale.set_value(settings.get("recognitionScale", 1))
        self.field(body, "Recognition scale (×)", self.scale)
        self.correction = self.check(body, "Use language correction", settings.get("usesLanguageCorrection", True))
        body.add(Gtk.Separator())
        body.add(label("Recognition languages"))
        self.language_status = label("Loading installed languages…", dim=True)
        body.add(self.language_status)
        self.languages_box = column(4)
        body.add(self.languages_box)
        self.build_languages([], loaded=False)

    def build_languages(self, languages, loaded):
        for child in self.languages_box.get_children():
            child.destroy()
        for name in sorted(set(languages) | set(self.selected_languages)):
            title = name + " (unavailable)" if loaded and name not in languages else name
            check = self.check(self.languages_box, title, name in self.selected_languages)
            check.connect("toggled", self.toggle_language, name)
        self.languages_box.show_all()

    def toggle_language(self, widget, name):
        if widget.get_active() and name not in self.selected_languages:
            self.selected_languages.append(name)
        elif not widget.get_active() and name in self.selected_languages:
            self.selected_languages.remove(name)

    def got_languages(self, languages):
        self.language_status.set_text("Leave all languages unchecked to use Tesseract’s default."
                                      if languages else "No Tesseract languages are installed.")
        self.build_languages(languages, loaded=True)

    def shortcuts_tab(self):
        body = self.page("Shortcuts")
        self.registration_status = label(self.app.shortcut_status, dim=True)
        self.registration_status.set_selectable(True)
        body.add(self.registration_status)
        configure = button("Configure Desktop Shortcuts…", lambda: self.save(configure=True))
        configure.set_halign(Gtk.Align.START)
        body.add(configure)
        self.shortcuts_box = column(8)
        body.add(self.shortcuts_box)
        self.build_shortcuts()

    def build_shortcuts(self):
        for child in self.shortcuts_box.get_children():
            child.destroy()
        for action, title in ACTION_TITLES.items():
            self.shortcuts_box.add(Gtk.Separator())
            line = row()
            line.pack_start(label(title), True, True, 0)
            line.add(button("Add Shortcut…", lambda action=action: self.edit_shortcut(action, None)))
            self.shortcuts_box.add(line)
            for index, binding in enumerate(self.hotkeys.get(action, [])):
                binding_row = row()
                name = binding_title(binding)
                edit = button(name, lambda a=action, i=index: self.edit_shortcut(a, i))
                edit.set_tooltip_text("Change " + title + " shortcut")
                binding_row.add(edit)
                binding_row.add(icon_button("list-remove-symbolic", "Remove " + name + " from " + title,
                                            lambda a=action, i=index: self.remove_shortcut(a, i)))
                self.shortcuts_box.add(binding_row)
        self.shortcuts_box.show_all()
        self.message.set_text(binding_conflict(self.hotkeys) or "")

    def edit_shortcut(self, action, index):
        editor = ShortcutEditor(self, action, index)
        self.shortcut_editor = editor
        editor.present()

    def remove_shortcut(self, action, index):
        self.hotkeys[action].pop(index)
        self.build_shortcuts()

    def general_tab(self):
        body = self.page("General")
        self.autostart = self.check(body, "Launch at login", self.settings["launchAtLogin"])
        self.hidden = self.check(body, "Start hidden at login", self.settings["startHidden"])
        body.add(label("Open ShareX from the applications menu to show the capture window.", dim=True))

    def save(self, configure=False):
        if self.saving:
            return
        conflict = binding_conflict(self.hotkeys)
        if conflict:
            self.notebook.set_current_page(2)
            self.message.set_text(conflict)
            return
        self.delay.update()
        self.scale.update()
        self.settings["capture"].update(showCursor=self.cursor.get_active(),
                                        copyToClipboard=self.clipboard.get_active(),
                                        delaySeconds=self.delay.get_value(),
                                        screenshotResolution=self.resolution.get_active_id(),
                                        screenshotFolderPath=self.folder)
        self.settings["ocr"].update(recognitionScale=self.scale.get_value(),
                                    usesLanguageCorrection=self.correction.get_active(),
                                    languages=list(self.selected_languages))
        self.settings.update(hotkeys=self.hotkeys, launchAtLogin=self.autostart.get_active(),
                             startHidden=self.hidden.get_active())
        self.saving = True
        self.set_sensitive(False)
        self.message.set_text("Saving settings…")

        def saved(settings):
            self.app.settings_saved(settings)
            self.saving = False
            self.set_sensitive(True)
            if configure:
                self.message.set_text("")
                self.app.shortcuts.configure()
            else:
                self.destroy()

        def failed(message):
            self.saving = False
            self.set_sensitive(True)
            self.message.set_text(message)

        self.app.worker.run("saveSettings", json_input=self.settings, success=saved, failure=failed)

    def closed(self, unused):
        self.language_job.cancel()
