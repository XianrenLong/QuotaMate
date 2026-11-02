#!/usr/bin/env python3
"""Keep the verified macOS release and move earlier installers to Trash."""

import argparse
import hashlib
from pathlib import Path
import re
import shutil
import tempfile


PACKAGE = re.compile(r"QuotaMate-(\d+)\.(\d+)\.(\d+)-macos-universal\.(dmg|zip)$")


def clean_old_packages(dist: Path, version: str, trash: Path) -> int:
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError(f"Invalid release version: {version}")
    current = tuple(map(int, version.split(".")))
    keep = {f"QuotaMate-{version}-macos-universal.{ext}" for ext in ("dmg", "zip")}
    checksums = {}
    for line in (dist / "SHA256SUMS").read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        if name in checksums:
            raise ValueError(f"Duplicate checksum entry: {name}")
        checksums[name] = digest
    if set(checksums) != keep:
        raise ValueError("Checksums must cover both current release packages")
    for name, digest in checksums.items():
        package = dist / name
        if package.is_symlink() or not package.is_file():
            raise ValueError(f"Current package is missing or unsafe: {name}")
        if hashlib.sha256(package.read_bytes()).hexdigest() != digest:
            raise ValueError(f"Current package failed checksum verification: {name}")

    old = []
    for package in dist.rglob("*"):
        match = PACKAGE.fullmatch(package.name)
        if not match or package.is_symlink() or not package.is_file():
            continue
        package_version = tuple(map(int, match.group(1, 2, 3)))
        if package_version > current:
            raise ValueError(f"A newer release exists; keeping all packages: {package.name}")
        if package_version < current:
            old.append(package)
    if not old:
        return 0

    trash.mkdir(parents=True, exist_ok=True)
    destination = Path(tempfile.mkdtemp(prefix="QuotaMate-旧版安装包-", dir=trash))
    parents = set()
    for package in old:
        target = destination / package.relative_to(dist)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(package), str(target))
        parent = package.parent
        while parent != dist:
            parents.add(parent)
            parent = parent.parent
    for parent in sorted(parents, key=lambda path: len(path.parts), reverse=True):
        try:
            parent.rmdir()  # Only remove archive folders that are now empty.
        except OSError:
            pass
    return len(old)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dist", type=Path)
    parser.add_argument("version")
    args = parser.parse_args()
    count = clean_old_packages(args.dist.resolve(), args.version, Path.home() / ".Trash")
    print(f"最新安装包校验通过；已将 {count} 个旧版安装包移到废纸篓。")


if __name__ == "__main__":
    main()
