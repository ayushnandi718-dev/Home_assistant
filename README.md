# AURA Hub

Companion and management console for the **AURA AI Desk Companion** ecosystem.

- Developer: Ayush Nandi
- Current target: Windows 11 (Flutter desktop)
- Stack: Flutter + Dart, Riverpod, go_router
- Phase: **Phase 1 - Foundation** with a local Windows telemetry prototype

## What exists today

- Dark-first design system with shared colour, spacing, radius and motion tokens.
- Responsive shell: persistent sidebar, compact rail and bottom navigation.
- All ten navigation destinations open real pages; unfinished modules are
  clearly labelled as planned.
- Dashboard showing **real Windows host metrics** (CPU, memory, disk, network,
  uptime, firewall, process list) fetched from a local REST API every 3 seconds.
- Manual refresh, automatic retry, and stale-data retention when the API is down.

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
    network/                 Local REST API client
    theme/                   Colours, spacing, radii, breakpoints, ThemeData
    utilities/               Formatting helpers
  features/dashboard/
    data/                    Live REST-backed repository
    domain/                  Snapshot, activity and SystemMetrics models
    presentation/            Page, providers, polling controller, widgets
  shared/widgets/            Reusable design-system widgets
server/
  aura_api.py                psutil telemetry API (stdlib http.server)
scripts/
  start_aura_api.ps1         Creates a venv, installs deps, starts the API
```

UI, state, models and data sources are separated. A future AURA device backend
can be introduced behind new repository implementations without rewriting the UI.

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
Flutter client with `AURA_API_BASE_URL`. The API binds to loopback and has **no
authentication** — do not expose it to a network until an auth layer exists.

The dashboard polls every 3 seconds. To change this, override
`dashboardPollingIntervalProvider` in `lib/features/dashboard/presentation/dashboard_providers.dart`.

## Verification

```powershell
dart format .
flutter analyze
flutter test
flutter build windows
```

## Roadmap

- **Phase 1 (current):** shell, navigation, live Windows host telemetry.
- **Phase 2:** device management, Family/Ayush profiles and PIN prototype.
- **Phase 3:** display studio, voice/audio, integrations.
- **Phase 4:** automations, diagnostics/logs, firmware.
- **Phase 5:** authenticated backend, real AURA device communication,
  cross-platform support.
