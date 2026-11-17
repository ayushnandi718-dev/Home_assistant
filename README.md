<div align="center">

# AURA Hub

### Your desk companion, understood.

Windows desktop control centre for the **AURA AI Desk Companion**.

`Flutter` &nbsp;•&nbsp; `Windows 11` &nbsp;•&nbsp; `Riverpod` &nbsp;•&nbsp; `Local-first telemetry`

</div>

<br />

> [!IMPORTANT]
> **AURA Hub is in its Foundation phase.** It presents real telemetry from the
> Windows PC running the app, with two local workspaces and a notification
> centre. It does not connect to AURA hardware, third-party accounts, or any
> paid AI service yet.

## ✦ At a glance

|  |  |
| --- | --- |
| **Platform** | Windows 11 desktop |
| **App** | Flutter + Dart |
| **Telemetry** | Local Python API powered by `psutil` |
| **State** | Riverpod |
| **Navigation** | go_router |
| **Hardware target** | Waveshare ESP32-S3 Touch LCD 4.3B (not yet ordered) |

## ◉ What works today

```text
  LIVE WINDOWS TELEMETRY   WORKSPACES & STATE        HONEST STATUS
  ─────────────────────    ──────────────────        ─────────────
  CPU / memory / disk      AYUSH PIN + FAMILY open   No virtual device
  Network / uptime         Per-profile notifications No fake pairing
  Firewall tri-state       Dashboard customization   No cloud account
  Bounded history          Structured logs           No invented values
```

### Dashboard

The dashboard reads CPU, memory, storage, network throughput, uptime, firewall
state, and active processes from the host PC. It fetches from a loopback API,
keeps the last good snapshot during an outage, and labels stale data clearly.
Polling is tied to visibility. Provenance banners (live-data notice and source
health) always remain visible.

You can reorder dashboard widgets and hide/show them from the **Customize**
button in the header. The layout is persisted per user.

### Two workspaces

| Workspace | Access | Data |
| --- | --- | --- |
| **FAMILY** | Opens directly | Shared notifications, household dashboard |
| **AYUSH** | 4–12 digit PIN | Private notifications and future private integrations / AI history |

- The app always starts in FAMILY. A private AYUSH session is never restored
  automatically after a restart.
- The PIN is stored as a salted SHA-256 hash in local app data — never in plain
  text. Five failed attempts trigger a one-minute in-memory lockout.
- Notification histories are stored in separate files per workspace, and
  private data reads are guarded in services (`ProfileAccess`), not only in UI.
- **This is a local convenience lock, not an OS credential vault or a backend
  authenticator.** A stolen PIN file is brute-forceable; do not treat it as
  strong security.

### Notifications

A central notification centre records real service transitions: local API
offline/online, sampler healthy/degraded, and profile changes. It supports unread
counts, mark-read, dismiss, clear, and per-workspace persistence. No sample
notifications are generated. OS/toast delivery is not implemented yet.

### Core services

- Global Flutter, platform and zone errors are captured into a bounded,
  redacted structured log shown in Diagnostics and included in JSON exports.
- An in-process service lifecycle manager starts/pauses/resumes the API health
  monitor with the app lifecycle. It never launches or stops the Python process.
- Service health transitions produce notifications only on real state changes.

### Settings & diagnostics

Settings are local to the PC: API endpoint, polling interval, history retention,
motion, and density. A non-loopback endpoint shows an explicit warning because
the bundled API has no authentication. Diagnostics records real API activity,
sampler health, structured logs, and exports a redacted JSON report.

### Devices

The Devices screen deliberately reports an empty state until real hardware and
a transport exist. Capability, event, command-queue and status **interfaces**
are being added as contracts only; none of them simulate a device or deliver a
command anywhere.

### Integration & AI foundations

Integration metadata, permission scopes, OAuth/token-store boundaries, AI
provider/model configuration, conversation models, tool contracts, streaming
interfaces, and en/hi/bn language handling are being added as **interfaces and
honest empty states only**. Nothing is connected, no key is stored in source,
and no AI response is generated. These become functional one adapter at a time.

## ⚑ A clear boundary

```text
Windows host telemetry  ───────►  AURA Hub dashboard
                                     │
                                     └── does not imply ──► AURA device / account
```

Still planned for future phases:

- BLE / Wi-Fi discovery, pairing, ownership, and real device transport
- ESP32 firmware communication and OTA
- Real OAuth adapters and secure token storage
- A real AI client adapter behind the existing interface
- OS notification delivery
- Display Studio, Voice & Audio, Automations, and Firmware tools

## ◌ Architecture

```text
┌──────────────────────────────────────────────────────────────────┐
│                            AURA Hub                               │
│  app shell · router · profiles · notifications · core services    │
└───────────────────────────────┬──────────────────────────────────┘
                                │
      ┌──────────────┬──────────┼──────────┬───────────────┐
      │              │          │          │               │
  Dashboard      Devices    Profiles  Diagnostics     Integrations
  layout +       contracts  PIN +     logs + export   AI foundations
  polling        (empty)    session
      │
  Local REST API · 127.0.0.1:8765
      │
  Python · psutil · Windows host
```

```text
lib/
├── app/                  Shell, router, navigation, top bar
├── core/                 Config, logging, errors, lifecycle, network, settings
├── features/
│   ├── dashboard/        Telemetry, history, polling, layout, widgets
│   ├── devices/          Device contracts and truthful empty state
│   ├── diagnostics/      Request records, structured logs, JSON export
│   ├── integrations/     Credential-free catalog and boundaries
│   ├── ai/               Provider/conversation/tool interfaces (in progress)
│   ├── notifications/    Per-workspace notification centre
│   ├── profiles/         AYUSH/FAMILY model, PIN store, session guard
│   ├── settings/         Persisted preferences interface
│   └── system/           App-wide service health monitor
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
| `GET /api/health` | Liveness plus sampler health and last successful sample time. |
| `GET /api/system` | Current Windows host metrics from `psutil`, with explicit not-ready states. |

Set `AURA_API_HOST` or `AURA_API_PORT` before starting the API to change its
address. Set `AURA_API_BASE_URL` at launch, or change the endpoint in Settings.

> [!WARNING]
> The local API has no authentication and sends permissive CORS headers. Keep it
> bound to loopback until authentication exists. A non-loopback endpoint in
> Settings shows a warning but is allowed for trusted-network development.

## ⌁ Local data

| Data | Location | Notes |
| --- | --- | --- |
| Preferences | `%APPDATA%\AURA Hub\app_settings.json` | Falls back to defaults if invalid |
| Dashboard layout | `%APPDATA%\AURA Hub\dashboard_layout.json` | Widget order/visibility |
| AYUSH PIN verifier | `%APPDATA%\AURA Hub\profile_pin.json` | Salted hash only, no raw PIN |
| Notifications | `%APPDATA%\AURA Hub\notifications_<profile>.json` | Separate per workspace |
| Diagnostics export | `Documents\aura_hub_diagnostics.json` | Manual, redacted |

Structured logs and telemetry history are bounded and in-memory only; they do
not survive a restart except through a manual diagnostics export.

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
NOW                          NEXT                       LATER
Foundation                   Hardware & security        Ecosystem
────────────                 ──────────────────         ─────────────────
Local telemetry              BLE / Wi-Fi transport      Real integrations
Workspaces + notifications   Capability negotiation     Real AI adapter
Dashboard customization      Secure token storage       Display / voice tools
Core lifecycle + logs        OS notification delivery   Firmware / OTA
```

<div align="center">

Built by **Ayush Nandi** &nbsp;·&nbsp; AURA Hub `v0.1.0+1`

</div>
