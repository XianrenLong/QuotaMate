#!/usr/bin/env python3
"""Check the Git index before publishing; report paths, never secret values."""

from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
SECRET_PATTERNS = {
    "API key": re.compile(rb"(?:sk-ant-[A-Za-z0-9_-]{20,}|sk-proj-[A-Za-z0-9_-]{20,})"),
    "GitHub token": re.compile(rb"(?:gh[pousr]_[A-Za-z0-9]{24,}|github_pat_[A-Za-z0-9_]{24,})"),
    "private key": re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "JWT": re.compile(rb"eyJ[A-Za-z0-9_-]{18,}\.[A-Za-z0-9_-]{18,}\.[A-Za-z0-9_-]{12,}"),
    "personal absolute path": re.compile(rb"(?:/Users/[A-Za-z0-9._-]+/|/var/" rb"folders/)"),
}
PRIVATE_NAMES = {"auth.json", ".credentials.json", "credentials.json"}
PRIVATE_SUFFIXES = {
    ".db", ".sqlite", ".sqlite3", ".jsonl", ".csv", ".pem", ".key", ".p12", ".pfx",
    ".mobileprovision", ".provisionprofile", ".dmg", ".zip",
}
LOCAL_PREFIXES = ("design/", "build/", "dist/", "exports/", "diagnostics/", "local-data/")
LINK = re.compile(r"!?\[[^\]\n]*\]\(([^)\n]+)\)")


def indexed_files(root: Path) -> dict[str, tuple[str, str]]:
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "--stage", "-z"],
        check=True, capture_output=True,
    )
    files = {}
    for entry in result.stdout.split(b"\0"):
        if not entry:
            continue
        metadata, raw_path = entry.split(b"\t", 1)
        mode, oid, stage = metadata.decode().split()
        path = raw_path.decode("utf-8")
        if stage != "0":
            raise ValueError(f"Unresolved index entry: {path}")
        files[path] = mode, oid
    return files


def audit(root: Path) -> tuple[int, list[str]]:
    files = indexed_files(root)
    errors = []
    if not files:
        return 0, ["No indexed files. Stage the intended public files first."]
    for name, (mode, oid) in files.items():
        path = PurePosixPath(name)
        basename = path.name.lower()
        private = (
            basename in PRIVATE_NAMES
            or (basename.startswith(".env") and basename != ".env.example")
            or path.suffix.lower() in PRIVATE_SUFFIXES
            or basename.endswith((".db-wal", ".db-shm", ".sqlite-wal", ".sqlite-shm", ".sqlite3-wal", ".sqlite3-shm"))
            or name.startswith(LOCAL_PREFIXES)
            or name == "design-qa.md"
            or (name.startswith("screenshots/") and not name.startswith("screenshots/preview/"))
        )
        if private:
            errors.append(f"{name}: local/private or release-only file")
        if mode not in {"100644", "100755"}:
            errors.append(f"{name}: unsupported file type (symlink or submodule)")
            continue
        # Inspect staged bytes, so unstaged redaction cannot conceal a staged secret.
        data = subprocess.run(
            ["git", "-C", str(root), "cat-file", "blob", oid],
            check=True, capture_output=True,
        ).stdout
        if len(data) > 10 * 1024 * 1024:
            errors.append(f"{name}: file exceeds the 10 MiB public-source limit")
        if b"\0" in data:
            continue  # Binary previews require separate visual review.
        for label, pattern in SECRET_PATTERNS.items():
            if pattern.search(data):
                errors.append(f"{name}: possible {label}; value redacted")
        if path.suffix.lower() != ".md":
            continue
        for raw_target in LINK.findall(data.decode("utf-8")):
            target = raw_target.split(' "', 1)[0].strip("<>")
            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc or not parsed.path:
                continue
            destination = (root / path.parent / unquote(parsed.path)).resolve()
            try:
                relative = destination.relative_to(root.resolve()).as_posix()
            except ValueError:
                errors.append(f"{name}: Markdown link points outside this repository")
                continue
            if relative not in files and not any(v.startswith(relative.rstrip("/") + "/") for v in files):
                errors.append(f"{name}: Markdown link is not in the public index: {relative}")
    return len(files), errors


def main() -> None:
    count, errors = audit(ROOT)
    if errors:
        for error in errors:
            print(error)
        raise SystemExit(1)
    print(f"Public index check passed: {count} files; no matched secrets, private files or broken local Markdown links.")
    print("Pattern checks do not replace a security audit or visual review of screenshots.")


if __name__ == "__main__":
    main()
