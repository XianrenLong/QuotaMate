"""Encode approved ImageGen artwork into platform icon sizes; no artwork is redrawn."""
import hashlib
import json
import struct
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = root / 'assets/branding/quotamate-hourglass-master.png'
branding = root / 'assets/branding'
target = root / 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
if not source.is_file():
    raise SystemExit(f'Missing approved master: {source}')

def export(size, output):
    subprocess.run(['/usr/bin/sips', '-z', str(size), str(size), str(source), '--out', str(output)], check=True, stdout=subprocess.DEVNULL)

export(1024, branding / 'quotamate-hourglass.png')
files = []
for size in (16, 32, 64, 128, 256, 512, 1024):
    output = target / f'app_icon_{size}.png'
    export(size, output)
    files.append({'path': str(output.relative_to(root)), 'width': size, 'height': size, 'sha256': hashlib.sha256(output.read_bytes()).hexdigest()})

# ICO supports PNG-encoded frames. Wrap existing resized PNGs without changing pixels.
frames = [(size, (target / f'app_icon_{size}.png').read_bytes()) for size in (16, 32, 64, 256)]
offset = 6 + 16 * len(frames)
entries = []
for size, data in frames:
    entries.append(struct.pack('<BBBBHHII', size % 256, size % 256, 0, 0, 1, 32, len(data), offset))
    offset += len(data)
ico = root / 'windows/runner/resources/app_icon.ico'
ico.write_bytes(struct.pack('<HHH', 0, 1, len(frames)) + b''.join(entries) + b''.join(data for _, data in frames))
files.append({'path': str(ico.relative_to(root)), 'sha256': hashlib.sha256(ico.read_bytes()).hexdigest()})

manifest = {
    'brand': 'QuotaMate', 'direction': '额度沙漏', 'selected_on': '2026-10-30',
    'master': str(source.relative_to(root)), 'master_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'artwork': 'Built-in ImageGen; selected concept with transparent-margin export',
    'encoding': 'macOS sips resizing; PNG-wrapped ICO frames; no design reconstruction',
    'exports': files,
}
(branding / 'export-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
print(f'Exported {len(files)} platform resources from the approved hourglass artwork.')
