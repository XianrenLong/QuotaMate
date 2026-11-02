from pathlib import Path
import subprocess
import tempfile
import unittest

from check_public_files import audit


class PublicFilesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="quota-public-index-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)

    def stage(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        subprocess.run(["git", "-C", str(self.root), "add", "--", name], check=True)

    def test_clean_source_with_indexed_document_link(self):
        self.stage("README.md", "Read the [guide](docs/guide.md).\n")
        self.stage("docs/guide.md", "Use synthetic test data.\n")
        self.assertEqual(audit(self.root), (2, []))

    def test_secret_is_redacted_and_checked_in_index_not_worktree(self):
        secret = "sk-proj-" + "a" * 32
        self.stage("config.txt", secret)
        (self.root / "config.txt").write_text("redacted only in worktree")
        _, errors = audit(self.root)
        self.assertTrue(any("API key" in v for v in errors))
        self.assertNotIn(secret, "\n".join(errors))

    def test_private_data_is_rejected_even_when_git_staged_it(self):
        for name in [".env", "auth.json", "usage.sqlite3", "session.jsonl", "screenshots/old.png"]:
            self.stage(name, "synthetic data")
        _, errors = audit(self.root)
        self.assertEqual(len(errors), 5)

    def test_missing_and_external_local_links_are_rejected(self):
        self.stage("README.md", "[Missing](ignored.md) [Outside](../private.txt)")
        _, errors = audit(self.root)
        self.assertEqual(len(errors), 2)

    def test_personal_paths_are_rejected_without_echoing_the_path(self):
        private_path = "/Users/" + "private-user" + "/Documents/secret"
        self.stage("README.md", private_path)
        _, errors = audit(self.root)
        self.assertTrue(any("personal absolute path" in v for v in errors))
        self.assertNotIn(private_path, "\n".join(errors))

    def test_readme_html_images_and_picture_sources_are_checked(self):
        self.stage("README.md", '<picture><source srcset="missing.png 1x, other.png 2x"><img src="image.png"></picture><a href="https://example.com">Download</a>')
        self.stage("image.png", "synthetic image")
        _, errors = audit(self.root)
        self.assertEqual(len(errors), 2)
        self.assertTrue(any("missing.png" in value for value in errors))
        self.assertTrue(any("other.png" in value for value in errors))


if __name__ == "__main__":
    unittest.main()
