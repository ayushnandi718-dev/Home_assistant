# AURA Hub

Companion and management console for the **AURA AI Desk Companion** ecosystem.

- Developer: Ayush Nandi
- Current target: Windows 11 (Flutter desktop, Windows only)
- Stack: Flutter + Dart, Riverpod, go_router
- Phase: **Phase 1 - Foundation (product-level)** with real local Windows telemetry

## What exists today

- Dark-first design system with shared colour, spacing, radius and motion tokens.
- Responsive shell: persistent sidebar, compact rail and bottom navigation.
- All ten navigation destinations open real pages.
- Dashboard showing **real Windows host metrics** (CPU, memory, disk, network,
  uptime, firewall, process list) fetched from a local REST API every 3 seconds
  by default.
- Resilient sync: immediate fetch, no overlapping requests, polling cancelled
  when the dashboard is inactive, last good metrics retained and marked stale
  on failure, automatic recovery, and a separate local-API health indicator.
  Consecutive failures are counted and exposed to Diagnostics.
- Settings page with **persisted preferences**: API endpoint, refresh interval,
  reduce-motion override and display density. Stored on this PC in
  `%APPDATA%\AURA Hub\app_settings.json` (corrupt files fall back to defaults).
- Diagnostics page with **real request telemetry**: recent local API requests,
  success rate, average latency, connection state, and JSON export to the
  user's Documents folder. No invented log entries.
- Devices page with an honest empty state, discovery status and setup guide.
  No device is simulated or paired. Hardware-dependent pages show an explicit
  readiness card instead of placeholder functionality.
- Accessibility semantics on dashboard metric cards.

### Important boundary

**Windows telemetry is not AURA telemetry.** The local API measures this PC. It
does not mean an ESP32 AURA device is connected. The dashboard therefore shows
`Local telemetry API` and `AURA Core: Not linked` as separate statuses. No AURA
hardware, backend, PIN authentication, OAuth or push notifications are
implemented.

## Architecture

```text
lib/
  app/                       App, shell, shell components, router, navigation
  core/
    network/                 Local REST API client with request recorder
    settings/                Settings model, controller and local JSON store
    theme/                   Colours, spacing, radii, breakpoints, ThemeData
    utilities/               Formatting helpers and Windows-native paths
  features/dashboard/
    data/                    Live REST-backed repository
    domain/                  Snapshot, activity, connection-state and metrics
    presentation/            Page, providers, polling controller, widgets
  features/devices/
    data/                    Local (empty) device repository
    domain/                  Device model and repository contract
    presentation/            Honest empty-state page and providers
  features/diagnostics/
    presentation/            Real request log, stats and JSON export
  features/settings/
    presentation/            Persisted preferences page
  shared/widgets/            Reusable design-system widgets
server/
  aura_api.py                psutil telemetry API (stdlib http.server)
scripts/
  start_aura_api.ps1         Creates a venv, installs deps, starts the API
```

UI, state, models and data sources are separated. A future AURA device backend
can be introduced behind new repository implementations without rewriting the UI.
The app has **no third-party plugins**: settings persistence and file export use
`dart:io`, so a Windows build does not require Developer Mode symlink support.

## Setup on Windows

Flutter 3.50 is installed at `C:\Users\ayush\flutter\flutter\bin` (on the user
PATH). Python 3.9+ is required for the telemetry API.

```powershell
# 1. Install Flutter dependencies
flutter pub get

# 2. Start the local telemetry API (leave this window open)
powershell -ExecutionPolicy Bypass -File .\scripts\start_aura_api.ps1

# 3. In a second terminal, run the app
flutter run -d windows
```

The startup script creates `server\.venv`, installs `psutil` from
`server\requirements.txt`, then serves `http://127.0.0.1:8765`.

### API

| Endpoint        | Description                                   |
| --------------- | --------------------------------------------- |
| `GET /api/health` | Liveness check                              |
| `GET /api/system` | Real Windows host readings from `psutil`    |

Host and port can be overridden with `AURA_API_HOST` and `AURA_API_PORT`, and the
Flutter client with `AURA_API_BASE_URL` or, persistently, in Settings. The API
binds to loopback and has **no authentication** — do not expose it to a network
until an auth layer exists.

The dashboard polls every 3 seconds by default; the interval can be changed in
Settings (1/2/3/5/10s) or by overriding `dashboardPollingIntervalProvider` in
tests.

## Verification

```powershell
dart format .
flutter analyze
flutter test          # 24 tests
flutter build windows
```

## Roadmap

- **Phase 1 (current):** shell, navigation, resilient live Windows host
  telemetry, persisted settings, real diagnostics export, honest device state.
- **Phase 2:** real device discovery/pairing, Family/Ayush profiles and secure PIN.
- **Phase 3:** display studio, voice/audio, integrations.
- **Phase 4:** automations, firmware management.
- **Phase 5:** authenticated backend, real AURA device communication,
  cross-platform support.
