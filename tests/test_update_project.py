"""Update safety checks use isolated fake Windows-style projects, no SDK required."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / "tools/update_project.py"
spec = importlib.util.spec_from_file_location("updater", MODULE)
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)
PROJECT = '[application]\nconfig/name="My Working Quest"\nconfig/version="0.2.0"\n\n[xr]\nopenxr/enabled=true\n'
EXPORT = '''[preset.0]
name="Working Quest"
platform="Android"
include_filter="*.custom"
exclude_filter="private/*"

[preset.0.options]
gradle_build/use_gradle_build=true
package/unique_name="my.existing.package"
keystore/release="C:/private/release.keystore"
version/code=41
version/name="0.2.0"

[preset.1]
platform="Windows Desktop"

[preset.1.options]
version/name="untouched"
'''


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / "source"
        self.target = self.root / "existing"
        self.source.mkdir()
        self.target.mkdir()
        (self.target / "project.godot").write_text(PROJECT)
        (self.target / "export_presets.cfg").write_text(EXPORT)

    def put(self, root, name, value=b"source"):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(value)
        return path

    def test_dry_plan_preserves_local_build_and_signing(self):
        self.put(self.source, "scripts/main.gd")
        self.put(self.source, "android/build/build.gradle", b"bad replacement")
        self.put(self.source, "android_ai/build/intermediates.bin")
        self.put(self.source, "assets/accidental.keystore")
        self.put(self.source, "export_presets.cfg", b"bad replacement")
        self.put(self.source, "project.godot", b"bad replacement")
        changes = updater.plan_update(self.source, self.target)
        self.assertEqual(set(changes), {Path("scripts/main.gd"), Path("project.godot"), Path("export_presets.cfg")})
        self.assertEqual((self.target / "project.godot").read_text(), PROJECT)
        self.assertFalse((self.target / "scripts/main.gd").exists())
        export = changes[Path("export_presets.cfg")].decode()
        self.assertIn('gradle_build/use_gradle_build=true', export)
        self.assertIn('package/unique_name="my.existing.package"', export)
        self.assertIn('keystore/release="C:/private/release.keystore"', export)
        self.assertIn('exclude_filter="private/*"', export)
        self.assertIn('include_filter="*.custom,*.bin,*.json"', export)
        self.assertIn('version/code=42', export)
        self.assertIn('version/name="0.3.0"', export)
        self.assertIn('version/name="untouched"', export)
        self.assertNotIn('plugins/QuestDepth', export)
        project = changes[Path("project.godot")].decode()
        self.assertIn('config/name="My Working Quest"', project)
        self.assertIn('openxr/enabled=true', project)

    def test_backup_apply_and_idempotence(self):
        original = self.put(self.target, "scripts/main.gd", b"working")
        self.put(self.source, "scripts/main.gd", b"updated")
        self.put(self.source, "scripts/new.gd", b"new")
        private = self.put(self.target, "android/build/private.keystore", b"private")
        changes = updater.plan_update(self.source, self.target)
        backup = updater.apply_update(self.target, changes)
        self.assertEqual((backup / "scripts/main.gd").read_bytes(), b"working")
        self.assertEqual((backup / "export_presets.cfg").read_text(), EXPORT)
        self.assertIn("ADDED scripts/new.gd", (backup / "UPDATE-MANIFEST.txt").read_text())
        self.assertEqual(original.read_bytes(), b"updated")
        self.assertEqual(private.read_bytes(), b"private")
        self.assertEqual(updater.plan_update(self.source, self.target), {})
        self.assertNotEqual(backup.parent, self.target)

    def test_missing_target_or_nested_copy_rejected(self):
        with self.assertRaises(ValueError):
            updater.plan_update(self.source, self.source)
        with self.assertRaises(ValueError):
            updater.plan_update(self.source, self.root / "missing")
        with self.assertRaises(ValueError):
            updater.plan_update(self.source, self.source / "nested")

    def test_enable_plugin_only_when_distributable_is_complete(self):
        self.put(self.source, "android/plugins/QuestDepth.gdap")
        changed = updater.plan_update(self.source, self.target)
        self.assertNotIn(b"plugins/QuestDepth=true", changed[Path("export_presets.cfg")])
        self.put(self.source, "android/plugins/QuestDepth.aar")
        self.put(self.source, "android/plugins/onnxruntime-android-1.22.0.aar")
        changed = updater.plan_update(self.source, self.target)
        self.assertIn(b"plugins/QuestDepth=true", changed[Path("export_presets.cfg")])

    def test_version_code_minimum_and_repeat(self):
        updated = updater.update_export_metadata(EXPORT.replace("version/code=41", "version/code=2"), False)
        self.assertIn("version/code=3", updated)
        self.assertEqual(updater.update_export_metadata(updated, False), updated)

    def test_symlink_target_rejected(self):
        external = self.root / "external"
        external.mkdir()
        try:
            (self.target / "scripts").symlink_to(external, target_is_directory=True)
        except OSError:
            self.skipTest("Symlinks unavailable")
        self.put(self.source, "scripts/main.gd")
        with self.assertRaises(ValueError):
            updater.plan_update(self.source, self.target)
        self.assertEqual(list(external.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
