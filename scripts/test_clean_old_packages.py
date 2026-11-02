import hashlib
from pathlib import Path
import tempfile
import unittest

from clean_old_packages import clean_old_packages


class PackageCleanupTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.dist = self.root / "dist"
        self.dist.mkdir()
        self.trash = self.root / "trash"
        self.current = []
        manifest = []
        for ext in ("dmg", "zip"):
            path = self.dist / f"QuotaMate-0.1.12-macos-universal.{ext}"
            path.write_bytes(f"latest {ext}".encode())
            self.current.append(path)
            manifest.append(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n")
        (self.dist / "SHA256SUMS").write_text("".join(manifest))
        self.old = self.dist / "QuotaMate-0.1.9-macos-universal.dmg"
        self.old.write_bytes(b"previous release")

    def clean(self):
        return clean_old_packages(self.dist, "0.1.12", self.trash)

    def test_preserves_latest_and_unrelated_files_and_cleans_archives(self):
        archive = self.dist / "canceled-0.1.11"
        archive.mkdir()
        (archive / "QuotaMate-0.1.11-macos-universal.zip").write_bytes(b"canceled")
        unrelated = self.dist / "source.zip"
        unrelated.write_bytes(b"source")
        self.assertEqual(self.clean(), 2)
        self.assertTrue(all(path.exists() for path in self.current))
        self.assertTrue(unrelated.exists())
        self.assertFalse(self.old.exists())
        self.assertFalse(archive.exists())
        self.assertEqual(len(list(self.trash.rglob("*.dmg"))), 1)
        self.assertEqual(len(list(self.trash.rglob("*.zip"))), 1)
        self.assertEqual(self.clean(), 0)
        self.assertEqual(len(list(self.trash.iterdir())), 1)

    def test_corrupt_new_package_keeps_previous_release(self):
        self.current[0].write_bytes(b"incomplete download")
        with self.assertRaises(ValueError):
            self.clean()
        self.assertTrue(self.old.exists())
        self.assertFalse(self.trash.exists())

    def test_missing_new_package_keeps_previous_release(self):
        self.current[1].unlink()
        with self.assertRaises(ValueError):
            self.clean()
        self.assertTrue(self.old.exists())
        self.assertFalse(self.trash.exists())

    def test_older_build_does_not_remove_newer_release(self):
        newer = self.dist / "QuotaMate-0.1.13-macos-universal.dmg"
        newer.write_bytes(b"newer")
        with self.assertRaises(ValueError):
            self.clean()
        self.assertTrue(newer.exists())
        self.assertTrue(self.old.exists())
        self.assertFalse(self.trash.exists())

    def test_symlinks_are_not_followed(self):
        outside = self.root / "unrelated-data"
        outside.mkdir()
        package = outside / "QuotaMate-0.1.1-macos-universal.dmg"
        package.write_bytes(b"outside dist")
        (self.dist / "linked-directory").symlink_to(outside, target_is_directory=True)
        (self.dist / "QuotaMate-0.1.2-macos-universal.dmg").symlink_to(package)
        self.assertEqual(self.clean(), 1)
        self.assertTrue(package.exists())


if __name__ == "__main__":
    unittest.main()
