# AURA Hub

Companion and management console for the **AURA AI Desk Companion** ecosystem.

- Developer: Ayush Nandi
- Current target: Windows 11 (Flutter desktop)
- Framework: Flutter + Dart
- State: Riverpod
- Navigation: go_router
- Phase: **Phase 1 - Foundation**

## What exists today

- Dark-first premium design system with reusable tokens and widgets.
- Responsive application shell: persistent sidebar on desktop, compact rail on
  tablets and bottom navigation on narrow screens.
- Full router with all ten navigation destinations opening real pages.
- Fully implemented dashboard backed by an explicit **mock repository**.
- Honest "planned" pages for modules that are designed but not implemented.

No hardware communication, backend calls, OAuth, PIN verification, OTA updates
or fabricated telemetry are implemented. Demo values are labelled as such.

## Architecture

```text
lib/
  main.dart                  App entry point + ProviderScope
  app/                       App, shell, shell components, router, navigation
  core/
    constants/               Routes and product metadata
    theme/                   Colours, spacing, radii, breakpoints, ThemeData
    utilities/               Formatting helpers
  features/
    <feature>/
      data/                  Mock / future real repositories
      domain/                Models and repository interfaces
      presentation/          Pages and widgets
  shared/widgets/            Reusable design-system widgets
```

UI, state, models and data sources are separated. Swapping the mock repositories
for REST/WebSocket-backed implementations does not require rewriting the UI.

## Setup on your Windows laptop

The Flutter SDK is installed at `C:\Users\ayush\flutter\flutter\bin` and is on
the user PATH. On another machine, adjust the commands below accordingly:

```powershell
# 1. Generate the Windows runner once (this does not overwrite existing lib files)
flutter create --project-name aura_hub --org com.ayushnandi --platforms=windows .

# 2. Install dependencies
flutter pub get

# 3. Format and verify
dart format .
flutter analyze

# 4. Run on Windows
flutter run -d windows
```

A helper script is provided:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap_windows.ps1
```

## Roadmap

- **Phase 1 (current):** shell, responsive navigation, dashboard, mock data.
- **Phase 2:** devices, profiles and PIN interface.
- **Phase 3:** display studio, voice/audio, integrations.
- **Phase 4:** automations, diagnostics/logs, firmware.
- **Phase 5:** backend, real device communication, cross-platform testing.
