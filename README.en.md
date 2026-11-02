# QuotaMate

[简体中文](README.md) · [Releases](https://github.com/liuzilong200049-bot/QuotaMate/releases) · [Issues](https://github.com/liuzilong200049-bot/QuotaMate/issues)

A local-first AI quota and usage dashboard, currently a **macOS Alpha**. View GPT / Codex and Claude separately, inspect local token records and projects, and estimate costs using configurable reference prices.

This is an independent community project, not affiliated with or endorsed by OpenAI, Anthropic, or FlClash.

![Claude statistics with synthetic data](screenshots/preview/statistics-claude-dark-en.png)

## Coverage

| Feature | GPT / Codex | Claude |
| --- | --- | --- |
| Local usage | Codex session logs | Terminal Claude Code logs |
| Subscription limits | The user's official local Codex App Server | Existing status line or identity-matched local desktop snapshots only |
| Account status | Selected Codex configuration | Official Claude Code local sign-in status |
| Quota reset | User-initiated, when a reset credit is available | Not available |
| Complete token ledger for regular web chat | Not available | Not available |

macOS development packages support Apple Silicon and Intel. Windows is a scaffold: native integration and packaging are unfinished. There is no usable Windows or Linux release.

Claude subscription polling is removed. QuotaMate does not extract subscription tokens, proxy model requests, or rotate accounts to bypass limits. Optional status line collection records metadata during normal terminal Claude Code use; signing in alone does not generate token history. Desktop Code, Cowork, remote sessions, and other devices are not fully covered.

Snapshots retain their original source and timestamp. Missing fields remain unknown; token counts, estimated timing, and API-equivalent prices are not an official bill. Local history is not automatically attributed to the currently signed-in account.

## Use

Download the latest Alpha from [Releases](https://github.com/liuzilong200049-bot/QuotaMate/releases). Quit the old version before replacing it. Packages use an ad-hoc development signature and are not Developer ID signed or notarized by Apple. You can also build from source.

Install Codex or Claude Code separately. Choose a provider and, if needed, its configuration directory and executable in Settings. Use the original client normally, then refresh QuotaMate. For Claude limit snapshots, explicitly enable status line collection in Settings; it targets terminal sessions and can restore your previous status line when disabled.

If statistics are empty, check the selected date range and whether that source has local logs. Regular web and desktop chat do not supply a complete local token ledger through this integration.

The interface supports Simplified Chinese and English, light/dark/system themes, a macOS menu bar item, optional low-quota alerts, project summaries, and CSV export. Previews use synthetic accounts, fictional paths, and fake usage, rendered with production Flutter components rather than captured from a real account.

## Build and test

Verified baseline: Flutter **3.47.7** / Dart **3.13.5**, macOS, and Xcode. Python 3 is used for development and release checks, not by the application at runtime.

```sh
git clone https://github.com/liuzilong200049-bot/QuotaMate.git
cd QuotaMate
flutter pub get --enforce-lockfile
flutter run -d macos
```

```sh
dart format --output=none --set-exit-if-changed lib test tool
dart analyze
flutter test
python3 -m unittest discover -s scripts -p 'test_*.py'
python3 scripts/check_public_files.py
bash scripts/package_macos.sh
```

The public-file check reads the Git index. Native relay tests and contributing instructions are in [CONTRIBUTING.md](CONTRIBUTING.md). CI uses temporary fixtures and never runs real-account diagnostics. The package script builds the standalone status line relay; it may be unavailable in a plain development run until built.

Installers and checksums are generated in `dist/`. After validating the new packages, the script moves older local installers to Trash, keeping only the latest version. Installers belong in Releases, not the source tree.

## Privacy and reporting

Local data is stored in `~/Library/Application Support/QuotaMate/usage.sqlite3` and may contain account display information and project paths. Do not publish it. The database does not store conversation bodies, tool arguments, attachments, or OAuth credentials. QuotaMate has no cloud backend or telemetry endpoint of its own; official CLIs may contact their providers.

Remove personal data from issue reports and screenshots. Report vulnerabilities through [private vulnerability reporting](https://github.com/liuzilong200049-bot/QuotaMate/security/advisories/new). See [SECURITY.md](SECURITY.md), [data sources](docs/data-sources.md), and [Claude connection details](docs/claude-connection.md).

## License

[MIT](LICENSE) for the project's own source and assets. Dependencies keep their original licenses; see [third-party notices](THIRD_PARTY_NOTICES.md). The UI style was inspired by FlClash without importing its UI source or proxy engine. Codex timing logic references CC Switch with its MIT notice retained. Artwork provenance is documented in [branding](docs/branding.md).
