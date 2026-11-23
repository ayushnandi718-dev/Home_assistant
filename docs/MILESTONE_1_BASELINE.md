# Milestone 1 — Baseline record

This is a point-in-time baseline for Milestone 1 — Complete Stabilisation. It was
captured before Batch 1 documentation and CI changes were applied.

## Repository state

| Item | Value |
| --- | --- |
| Branch | `feat/android-scaffold` |
| HEAD | `8dff65810deaa10bfbe7d05e22bf13b1058add05` |
| Upstream | `origin/feat/android-scaffold` |
| Frozen branch | `phase5f/ui-smoothness` |
| Frozen commit | `04c292f892cc8428d433ae26709fa468ecbacb76` |
| Working tree before Batch 1 | Only untracked `AURA_HUB_READ_ONLY_AUDIT.md` |
| Staged/unstaged source diff | Empty |
| Git mutations | None |

`AURA_HUB_READ_ONLY_AUDIT.md` is user-owned baseline material and was not
modified.

## Toolchain

| Tool | Version |
| --- | --- |
| Flutter | 3.50.0 stable (`ab2912035e`) |
| Dart | 3.14.0 |
| Python | 3.11.9 |
| Java | OpenJDK 17.0.21.1 (Temurin) |

The installed SDK satisfies `pubspec.lock`, which requires Dart `>=3.14.0 <4.0.0`
and Flutter `>=3.50.0`. `pubspec.yaml` still declares lower bounds of Dart
`>=3.5.0` and Flutter `>=3.27.0`; CI pins the SDK to the lockfile-compatible
version.

## Dependency resolution

```powershell
flutter pub get --enforce-lockfile
git diff --exit-code -- pubspec.lock
```

Result: passed. `pubspec.lock` was unchanged. The resolver reported available
upgrades but none were applied.

## Verification results

| Check | Command | Result |
| --- | --- | --- |
| Formatting | `dart format --output=none --set-exit-if-changed .` | **Failed**: 4 files were already unformatted. The check did not modify them. |
| Static analysis | `flutter analyze --fatal-infos --fatal-warnings` | Passed: no issues found. |
| Flutter tests | `flutter test` | Passed: 686 passed, 2 skipped. Skips were the opt-in live Groq tests. |
| Python telemetry tests | `python -m unittest discover -s server -p 'test_*.py' -v` | Passed: 12 tests. |
| Windows release build | `flutter build windows --release` | Passed: `build\windows\x64\runner\Release\aura_hub.exe`. |
| Android debug build | `flutter build apk --debug` | Passed: `build\app\outputs\flutter-apk\app-debug.apk`. |

### Pre-existing formatting failures

```text
lib\features\firmware\presentation\firmware_providers.dart
test\phase3_display_test.dart
test\phase3_navigation_test.dart
test\phase4_firmware_test.dart
```

These are formatting-only issues. Batch 1 applies the formatter to exactly these
files so the new CI format gate starts green.

## Existing CI configuration

No `.github/workflows/` directory existed before Batch 1. `.github/` contained
only issue and pull-request templates.

## Known limitations

- No physical Android device or emulator was available; the debug APK result
  proves compilation and packaging only, not on-device behaviour.
- No Android release keystore or Play signing identity was available; release
  signing remains out of scope for Batch 1.
- No ESP32, camera, or other AURA hardware was available.
- Branch protection settings live in GitHub and cannot be enforced by a workflow
  file alone.
- Live Groq tests remain opt-in via `AURA_ENABLE_LIVE_GROQ_TESTS` and
  `AURA_CONFIRM_LIVE_GROQ_CHAT`; CI sets both to `false`.

## Baseline conclusion

The repository is a valid starting point for Batch 1. No unexpected working-tree
changes were present, the frozen branch was unchanged, the lockfile resolved
cleanly, and all behavioural/build checks passed. The only baseline defect was
four pre-existing formatting violations.
