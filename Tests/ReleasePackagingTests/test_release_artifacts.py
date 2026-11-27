import os
import re
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class ReleasePackagingTests(unittest.TestCase):
    def test_linux_deb_contains_the_staged_runtime(self):
        if not shutil_which("dpkg-deb"):
            self.skipTest("dpkg-deb is required for Debian package integration tests")

        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "bundle"
            output = Path(temporary) / "ShareXLinux.deb"
            desktop = source / "ShareXLinux_ShareXLinux.resources" / "Desktop"
            (source / "packaging").mkdir(parents=True)
            desktop.mkdir(parents=True)
            binary = source / "ShareXLinux"
            binary.write_bytes(b"#!/bin/sh\nexit 0\n")
            binary.chmod(binary.stat().st_mode | stat.S_IXUSR)
            (desktop / "sharex_ui.py").write_text("# test desktop resource\n")
            (source / "packaging" / "sharex.desktop").write_text(
                "[Desktop Entry]\nName=ShareX Linux\nExec=@EXEC@\n"
            )

            subprocess.run(
                [
                    "bash",
                    str(ROOT / "scripts" / "package-linux-deb.sh"),
                    "--source",
                    str(source),
                    "--output",
                    str(output),
                    "--version",
                    "1.2.3",
                ],
                check=True,
                cwd=ROOT,
            )

            control = subprocess.check_output(
                ["dpkg-deb", "-f", str(output), "Package", "Version", "Architecture"],
                text=True,
            )
            contents = subprocess.check_output(["dpkg-deb", "-c", str(output)], text=True)
            self.assertIn("Package: sharex-linux", control)
            self.assertIn("Version: 1.2.3", control)
            self.assertIn("usr/lib/sharex-linux/ShareXLinux", contents)
            self.assertIn("usr/share/applications/io.github.PDGamerSG.ShareXLinux.desktop", contents)

    def test_release_scripts_have_one_named_artifact_each(self):
        mac_script = (ROOT / "scripts" / "build-release.sh").read_text()
        linux_script = (ROOT / "scripts" / "build-linux.sh").read_text()
        workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text()
        self.assertIn('dmg="$output_dir/ShareXMac.dmg"', mac_script)
        self.assertIn('deb="$output_dir/ShareXLinux.deb"', linux_script)
        self.assertIn("hdiutil verify", mac_script)
        self.assertIn("package-linux-deb.sh", linux_script)
        self.assertIn("ShareXMac.dmg", workflow)
        self.assertIn("ShareXLinux.deb", workflow)
        release_assets = re.findall(r"^\s+release/(\S+)$", workflow, re.MULTILINE)
        self.assertEqual(sorted(Path(asset).suffix for asset in release_assets), [".deb", ".dmg", ".exe"])


def shutil_which(command):
    for directory in os.environ.get("PATH", "").split(os.pathsep):
        candidate = Path(directory) / command
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


if __name__ == "__main__":
    unittest.main()
