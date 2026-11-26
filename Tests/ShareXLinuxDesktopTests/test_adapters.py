import importlib.util
import os
import pathlib
import unittest

ROOT = pathlib.Path(__file__).parents[2]
DESKTOP = ROOT / "Sources" / "ShareXLinux" / "Desktop"


def load(name):
    spec = importlib.util.spec_from_file_location(name, DESKTOP / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ShortcutAdapterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.shortcuts = load("shortcuts")

    def test_default_triggers_use_portal_and_gdk_names(self):
        self.assertEqual(self.shortcuts._portal_trigger("p", ["alt"]), "ALT+p")
        self.assertEqual(self.shortcuts._accelerator("p", ["shift"]), "<Shift>p")

    def test_invalid_and_duplicate_entries_are_reported_independently(self):
        entries = list(self.shortcuts._iter_bindings({
            "region": [{"key": "p", "modifiers": ["alt"]}],
            "ocrRegion": [{"key": "p", "modifiers": ["alt"]}],
            "settings": [{"key": "definitely-not-a-key", "modifiers": []}],
        }))
        self.assertEqual(entries[0][1], ("p", ("alt",)))
        self.assertIn("already assigned", entries[1][2])
        self.assertIn("unsupported key", entries[2][2])

    def test_no_shell_or_process_launcher_is_used(self):
        source = (DESKTOP / "shortcuts.py").read_text()
        self.assertNotIn("subprocess", source)
        self.assertNotIn("os.system", source)


class PortalCaptureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.portal = load("portal_capture")

    def test_modes_map_to_consented_portal_targets(self):
        self.assertEqual(self.portal.TARGETS, {
            "fullscreen": 1, "window": 2, "region": 4, "ocrRegion": 4,
        })

    def test_helper_does_not_construct_shell_commands(self):
        source = (DESKTOP / "portal_capture.py").read_text()
        self.assertNotIn("subprocess", source)
        self.assertNotIn("os.system", source)


if __name__ == "__main__":
    unittest.main()
