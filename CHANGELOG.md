# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned

- Cross-platform scaffolding for platforms beyond Windows/Web.
- Real device transport, signed release service, and firmware OTA.
- App updates are intentionally not part of this project yet.

## [0.1.0] - 2026-11-20

### Added

- Live Windows host telemetry dashboard with bounded history and clear
  provenance banners.
- AYUSH/FAMILY workspaces with isolated preferences, notifications, and
  dashboard layouts.
- Dashboard Widget Studio with reorderable, resizable, hideable cards.
- Notification centre with real service-state transitions only.
- Diagnostics, structured logs, and redacted JSON export.
- AI provider registry with Groq-compatible and native local Ollama adapters,
  per-profile consent, and Windows Credential Manager token boundary.
- Display Studio with 8 wallpapers, 6 panel themes, 7 clock styles, 4 watch
  faces, a thumbnail wallpaper grid, and live Flutter-drawn analog time/date
  preview.
- Firmware & Updates workspace with per-profile saved preferences, honest
  unavailable states, readiness information, and a local SHA-256 digest tool.
- Windows x64 portable release build with checksum.
- MIT license, contributing guide, code of conduct, security policy, issue and
  pull-request templates.

### Changed

- Display Studio now uses `AuraClock`; the app uses device-local time while
  tests use a fixed clock.
- Firmware configuration is preloaded for every profile before the first frame.
- `main` is protected: force pushes and deletion are blocked, and changes are
  accepted only through pull requests.

### Fixed

- Avoided fake firmware progress, install, verification, and success states.
- Prevented repeated analog sweep animations for fixed test clocks.
- Kept corrupt or unknown stored preferences falling back to safe defaults.

[Unreleased]: https://github.com/ayushnandi718-dev/Home_assistant/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ayushnandi718-dev/Home_assistant/releases/tag/v0.1.0
