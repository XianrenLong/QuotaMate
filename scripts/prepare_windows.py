#!/usr/bin/env python3
"""Fetch the pinned official SQLite DLL for Windows builds (hash verified)."""
import hashlib
from io import BytesIO
from pathlib import Path
import urllib.request
import zipfile

SQLITE_URL = 'https://www.sqlite.org/2026/sqlite-dll-win-x64-3540100.zip'
# SHA3-256 published at https://www.sqlite.org/download.html (2026-11-03).
SQLITE_SHA3 = 'c2d09c8babb9399277055c057c97a53f1ffd7c5f11d0c1f2118ffdfa39f2daa4'
SQLITE_DLL_SHA256 = '4b59d3cded9dc1608544160f3b4b10ac974c6ac0d6ffc23064e5f4c8dbd05aea'
ROOT = Path(__file__).resolve().parents[1]


def prepare(destination: Path) -> Path:
    destination.mkdir(parents=True, exist_ok=True)
    target = destination / 'sqlite3.dll'
    if target.is_file() and hashlib.sha256(target.read_bytes()).hexdigest() == SQLITE_DLL_SHA256:
        return target
    request = urllib.request.Request(SQLITE_URL, headers={'User-Agent': 'QuotaMate-build/1'})
    with urllib.request.urlopen(request, timeout=60) as response:
        payload = response.read(5 * 1024 * 1024)
    if hashlib.sha3_256(payload).hexdigest() != SQLITE_SHA3:
        raise ValueError('SQLite archive checksum mismatch; refusing to use it')
    with zipfile.ZipFile(BytesIO(payload)) as archive:
        dll = archive.read('sqlite3.dll')
    if hashlib.sha256(dll).hexdigest() != SQLITE_DLL_SHA256:
        raise ValueError('SQLite DLL checksum mismatch')
    temporary = target.with_suffix('.tmp')
    temporary.write_bytes(dll)
    temporary.replace(target)
    return target


if __name__ == '__main__':
    print(prepare(ROOT / 'build/windows-dependencies'))
