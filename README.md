<div align="center">

# AURA Hub

### Your desk companion, understood.

Windows desktop control centre for the **AURA AI Desk Companion**.

`Flutter` &nbsp;•&nbsp; `Windows 11` &nbsp;•&nbsp; `Riverpod` &nbsp;•&nbsp; `Local-first telemetry`

</div>

<br />

> [!IMPORTANT]
> **AURA Hub is in its Foundation phase.** It presents real telemetry from the
> Windows PC running the app. It does not currently connect to AURA hardware.

## ✦ At a glance

|  |  |
| --- | --- |
| **Platform** | Windows 11 desktop |
| **App** | Flutter + Dart |
| **Telemetry** | Local Python API powered by `psutil` |
| **State** | Riverpod |
| **Navigation** | go_router |
| **Hardware target** | Waveshare ESP32-S3 Touch LCD 4.3B |

## ◉ What works today

```text
  LIVE WINDOWS TELEMETRY        LOCAL CONTROL              HONEST STATUS
  ─────────────────────         ─────────────              ─────────────
  CPU and memory                Persisted settings         No virtual device
  Disk and network              Adjustable polling         No fake pairing
  Uptime and firewall           Motion and density         No cloud backend
  Active processes              Request diagnostics        No hidden sync
```

### Dashboard

The dashboard reads CPU, memory, storage, network throughput, uptime, firewall
state, and active processes from the host PC. It fetches data from a loopback
API, keeps the most recent valid snapshot during an outage, and marks stale
data clearly. Polling is tied to visibility: leaving the dashboard disposes the
sync controller and cancels its timer; returning starts one fresh immediate
synchronisation. The firewall is reported as enabled, disabled, or unavailable
— a failed probe is never shown as disabled.

### Settings & diagnostics

Settings are local to the PC. You can change the API address, polling interval,
motion preference, and UI density. Diagnostics records real API activity,
shows connection health and latency, and exports a JSON report. The Python
background sampler's health and last successful sample time are tracked
separately from HTTP request outcomes, and exports redact URLs and local paths.

### Devices

The Devices screen deliberately reports an empty state until a real AURA
transport exists. It never turns Windows telemetry into a fictitious ESP32
connection.

## ⚑ A clear boundary

```text
Windows host telemetry  ───────►  AURA Hub dashboard
                                    │
                                    └── does not imply ──► AURA device pairing
```

The following are planned for future phases:

- BLE and Wi-Fi discovery, pairing, and device transport
- ESP32 firmware communication
- Device identity, authentication, PINs, OAuth, and notifications
- Display Studio, Voice & Audio, Integrations, Automations, and Firmware tools

## ◌ Architecture

```text
┌──────────────────────────────────────────────────────────────────┐
│                            AURA Hub                               │
│  app shell · router · navigation · responsive desktop experience  │
└───────────────────────────────┬──────────────────────────────────┘
                                │
          ┌─────────────────────┼─────────────────────┐
          │                     │                     │
     Dashboard               Devices           Settings / Diagnostics
     polling + UI          repository          local JSON + request log
          │                     │                     │
          └──────────────┬──────┴─────────────────────┘
                         │
              Local REST API · 127.0.0.1:8765
                         │
              Python · psutil · Windows host
```

```text
lib/
├── app/                  Application shell, routes, navigation
├── core/                 Network, settings, theme, utilities
├── features/
│   ├── dashboard/        Live telemetry models, repository, polling, UI
│   ├── devices/          Device contracts and truthful empty state
│   ├── diagnostics/      Request records, statistics, JSON export
│   └── settings/         Persisted preferences interface
├── shared/widgets/       Reusable design-system components
server/
└── aura_api.py           Loopback telemetry API
scripts/
├── start_aura_api.ps1    API environment and startup
└── bootstrap_windows.ps1 Development bootstrap
test/                     Unit and widget tests
```

## ◈ Run it locally

### Prerequisites

- Windows 11
- Flutter SDK compatible with `pubspec.yaml`
- Python 3.9+
- Visual Studio with **Desktop development with C++** for Windows builds

### 1 — Install dependencies

```powershell
flutter pub get
```

### 2 — Start local telemetry

Keep this terminal open. On first run, the script creates `server\.venv` and
installs `psutil`.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start_aura_api.ps1
```

### 3 — Launch AURA Hub

In another terminal:

```powershell
flutter run -d windows
```

Or use the complete local bootstrap script:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap_windows.ps1
```

## ⇄ Local API

The API listens on `http://127.0.0.1:8765` by default and is intended only for
the computer running AURA Hub.

| Endpoint | Response |
| --- | --- |
| `GET /api/health` | Liveness confirmation plus sampler health and last successful sample time. |
| `GET /api/system` | Current Windows host metrics from `psutil`, with explicit not-ready states until the first background sample completes. |

Set `AURA_API_HOST` or `AURA_API_PORT` before starting the API to change its
address. Set `AURA_API_BASE_URL` at launch, or change the endpoint in Settings.

> [!WARNING]
> The local API has no authentication. Keep it bound to loopback until an
> authentication layer is implemented.

## ⌁ Local data

| Data | Location |
| --- | --- |
| Preferences | `%APPDATA%\AURA Hub\app_settings.json` |
| Diagnostics export | `Documents\aura_hub_diagnostics.json` |

Invalid or unreadable preferences safely fall back to the defaults.

## ✓ Verify changes

```powershell
dart format .
flutter analyze
flutter test
server\.venv\Scripts\python.exe -m unittest discover -s server -p "test_*.py" -v
flutter build windows
```

## Roadmap

```text
NOW                 NEXT                     LATER
Foundation          Device connection        Companion ecosystem
──────────          ─────────────────        ───────────────────
Local telemetry     BLE / Wi-Fi discovery    Display and voice tools
Settings            Pairing and ownership    Integrations and automations
Diagnostics         Secure device state      Firmware and cloud services
```

<div align="center">

Built by **Ayush Nandi** &nbsp;·&nbsp; AURA Hub `v0.1.0+1`

</div>
