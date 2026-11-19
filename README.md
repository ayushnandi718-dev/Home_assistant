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
> centre. It does not connect to AURA hardware or third-party accounts. AI
> replies need a user-configured provider: Groq through the OpenAI-compatible
> adapter, or a locally running Ollama on loopback. No key is stored in source.

## ✦ At a glance

|  |  |
| --- | --- |
| **Platform** | Windows 11 desktop |
| **App** | Flutter + Dart |
| **Telemetry** | Local Python API powered by `psutil` |
| **State** | Riverpod |
| **Navigation** | go_router |
| **AI providers** | Registry · Groq · native local Ollama |
| **Interface** | Layered glass desktop UI, reduced-motion aware |
| **Hardware target** | Waveshare ESP32-S3 Touch LCD 4.3B (not yet ordered) |

## ◉ What works today

```text
  LIVE WINDOWS TELEMETRY   WORKSPACES & STATE        HONEST STATUS
  ─────────────────────    ──────────────────        ─────────────
  CPU / memory / disk      AYUSH PIN + FAMILY open   No virtual device
  Network / uptime         Per-profile notifications No fake pairing
  Firewall tri-state       Dashboard customization   No cloud account
  Bounded history          Structured logs           No invented values
  Glass control centre     OS token store ready      No invented values
```

### Dashboard

The dashboard reads CPU, memory, storage, network throughput, uptime, firewall
state, and active processes from the host PC. It fetches from a loopback API,
keeps the last good snapshot during an outage, and labels stale data clearly.
Polling is tied to visibility. Provenance banners (live-data notice and source
health) always remain visible.

Use **Widget Studio** from the dashboard header to drag widgets into order,
choose compact/medium/full column spans, and hide or show cards. The editor
uses a responsive bento grid and saves an independent layout for each
workspace, so AYUSH and FAMILY never overwrite each other. Existing
single-layout files are migrated on first load.

### Interface

The desktop control centre uses a restrained glass language: frosted sidebar,
top bar, dialogs and floating panels, with more opaque cards for live telemetry
so numbers stay readable. Blue/violet/cyan ambient lighting sits behind the
shell; hover and transition motion honours the system "reduce animations"
setting. Narrow desktop and tablet widths use a compact sidebar or bottom
navigation. Android/iOS/macOS scaffolds are not part of this build.

### Two workspaces

| Workspace | Access | Data |
| --- | --- | --- |
| **FAMILY** | Opens directly | Shared notifications, household dashboard |
| **AYUSH** | 4–12 digit PIN | Private notifications and future private integrations / AI history |

- The app always starts in FAMILY. A private AYUSH session is never restored
  automatically after a restart.
- The PIN is stored as a salted PBKDF2-HMAC-SHA256 verifier (600,000 iterations)
  in local app data — never in plain text. Older SHA-256 verifiers are migrated
  transparently, but only after the correct PIN is entered. Five failed attempts
  trigger a one-minute in-memory lockout.
- Notification histories are stored in separate files per workspace, and
  private data reads are guarded in services (`ProfileAccess`), not only in UI.
- **This is a local convenience lock, not an OS credential vault or a backend
  authenticator.** The KDF makes offline guessing expensive, but a low-entropy
  PIN is still not strong security.

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

Integration metadata, permission scopes, provider/model configuration,
conversation models, tool contracts, and en/hi/bn language handling remain
bounded contracts. AI chat now has a real adapter seam: controllers keep
depending on the shared `AiClient`, while a registry selects a provider-specific
adapter. The OpenAI-compatible adapter serves user-configured endpoints such as
Groq; local Ollama uses a native adapter with its own protocol. Google Gemini
remains unsupported, and tool calls stay declaration-only.

The token-store boundary is real and backed by Windows Credential Manager:
provider keys are resolved only for a request and are never written to
`AiProviderConfig`, model metadata, diagnostics, or JSON. There is no OAuth
adapter yet, so every integration reports disconnected and readiness stays
`noAdapters`. These become functional one adapter at a time.

#### Local Ollama adapter

The native adapter defaults to `http://127.0.0.1:11434` and uses Ollama's own
`/api/version`, `/api/tags`, and `/api/chat` endpoints. It accepts only numeric
loopback IP addresses (`127.0.0.0/8` or `::1`); hostnames such as `localhost`,
URL credentials, query strings, fragments, and external addresses are rejected
before any request is sent, so DNS cannot redirect a saved configuration off
the device. No API key or `Authorization` header is sent to Ollama.

Model discovery keeps only bounded id/label/size/time/digest metadata and
rejects malformed or oversized entries. Streaming handles arbitrary NDJSON
chunk boundaries, treats `done: true` as terminal, stops cleanly on
cancellation, and reports incomplete streams instead of inventing completion.
Failures use the shared safe `AiException` taxonomy: prompts, transcripts,
response bodies, and credentials are never echoed to the UI or diagnostics.

Automated coverage uses in-process mock HTTP and raw-socket servers. A real
Ollama installation is not available in this repository, so no live-Ollama
testing is claimed. Remote Ollama endpoints remain out of scope.

## ⚑ A clear boundary

```text
Windows host telemetry  ───────►  AURA Hub dashboard
                                     │
                                     └── does not imply ──► AURA device / account
```

Still planned for future phases:

- BLE / Wi-Fi discovery, pairing, ownership, and real device transport
- ESP32 firmware communication and OTA
- Real OAuth adapters (OS-backed token storage is already in place)
- Provider-management UI and tool execution behind the adapter seam
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
│   ├── integrations/     Catalog + Windows Credential Manager token store
│   ├── ai/               Provider registry, Groq/Ollama adapters, chat seams
│   ├── notifications/    Per-workspace notification centre
│   ├── profiles/         AYUSH/FAMILY model, PIN store, session guard
│   ├── settings/         Persisted preferences interface
│   └── system/           App-wide service health monitor
├── shared/widgets/       Reusable glass design-system components
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

### 2 — Launch AURA Hub

```powershell
flutter run -d windows
```

AURA Hub now starts the local telemetry API automatically in a hidden process.
It reuses a healthy API if one is already running, waits for
`GET /api/health`, and shuts down only the process it started. The legacy
`scripts\start_aura_api.ps1` script remains available for manual debugging, but
no terminal needs to stay open.

On first local run, create `server\.venv` once if it does not already exist:

```powershell
python -m venv server\.venv
server\.venv\Scripts\python.exe -m pip install -r server\requirements.txt
```

### Packaged Windows builds

`flutter build windows` copies `server\aura_api.py` and its requirements next to
`aura_hub.exe`. A Python 3 runtime is still required: AURA Hub searches for
`server\.venv`, an optional bundled `runtime\python`, then Python on `PATH`.
A fully self-contained installer needs a bundled embedded Python runtime; that
runtime is not included in this repository. Set `AURA_TELEMETRY_PYTHON` to use
a specific interpreter.

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
| Dashboard layouts | `%APPDATA%\AURA Hub\dashboard_layout_<profile>.json` | Independent order/size/visibility per workspace; legacy `dashboard_layout.json` migrated on first load |
| AYUSH PIN verifier | `%APPDATA%\AURA Hub\profile_pin.json` | Salted PBKDF2 verifier (v2), legacy v1 migrated after a correct PIN; no raw PIN |
| Integration tokens | Windows Credential Manager | Target names only contain service/scope; no tokens are written until a real adapter exists |
| Notifications | `%APPDATA%\AURA Hub\notifications_<profile>.json` | Separate per workspace |
| Diagnostics export | `Documents\aura_hub_diagnostics.json` | Manual, redacted |

Structured logs and telemetry history are bounded and in-memory only; they do
not survive a restart except through a manual diagnostics export.

## ✓ Verify changes

```powershell
dart format .
flutter analyze
flutter test
flutter test test/ai_provider_abstraction_test.dart test/ollama_provider_test.dart --concurrency=1
server\.venv\Scripts\python.exe -m unittest discover -s server -p "test_*.py" -v
flutter build windows
```

## Roadmap

```text
NOW                          NEXT                       LATER
Foundation                   Hardware & security        Ecosystem
────────────                 ──────────────────         ─────────────────
Local telemetry              BLE / Wi-Fi transport      Real integrations
Workspaces + notifications   Capability negotiation     AI provider UI
Dashboard customization      OAuth adapters             Display / voice tools
Core lifecycle + logs        OS notification delivery   Firmware / OTA
```

<div align="center">

Built by **Ayush Nandi** &nbsp;·&nbsp; AURA Hub `v0.1.0+1`

</div>
