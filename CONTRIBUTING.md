# Contributing to AURA Hub

Thanks for helping improve AURA Hub. This project is intentionally honest about
what is real, what is a preview, and what is not implemented. Please keep that
standard intact in code, tests, docs, screenshots, and release notes.

## Ground rules

- **Never simulate success.** Do not invent device links, firmware installs, AI
  replies, update progress, or verification results.
- **Respect the capability vocabulary.** `Configured`, `Preview only`,
  `Available on this computer`, `Requires AURA hardware`, and `Not implemented`
  mean specific things. Reuse `CapabilityStatusKey` rather than inventing new
  claims.
- **Keep workspaces isolated.** AYUSH and FAMILY preferences and histories must
  remain in separate files and must not leak across profiles.
- **Never commit secrets.** API keys, PINs, tokens, diagnostics exports, and real
  user data do not belong in the repository, tests, logs, or screenshots.
- **Local first and token-protected.** The telemetry API uses a fresh per-launch
  bearer token passed only through the child environment. Keep it on loopback
  by default, never log or persist the token, and never send it as a CLI
  argument. Plain HTTP to a non-loopback host is rejected.
- **Keep the authorization seams explicit.** New AI controllers and data paths
  must take `ProfileAccessReader`; AYUSH denials must be safe and side-effect
  free. Do not introduce implicit FAMILY or open access defaults.
- **Be conservative with device features.** There is no BLE/Wi-Fi transport and
  no OTA service yet. New device code must be a contract or an honest
  unavailable state until real hardware exists.

## Ways to contribute

- Report a bug with a clear repro and environment details.
- Proposal a feature with the problem first, not just the solution.
- Improve docs, translations, tests, accessibility, or diagnostics.
- Review pull requests with attention to honesty and data isolation.

## Development setup

See the [Run it locally](README.md#-run-it-locally) section in the README. Use
the Flutter SDK version compatible with `pubspec.lock`; CI pins Flutter 3.50.0
and Dart 3.14.0. In short:

```powershell
flutter pub get --enforce-lockfile
flutter run -d windows
```

For telemetry, create `server\.venv` once and install
`server\requirements.txt`. A Python 3 runtime is still required for packaged
Windows builds. Android debug builds additionally require JDK 17 and the Android
SDK; no release signing credentials are needed.

## Workflow

1. Open or find an issue before starting non-trivial work.
2. Fork the repository and create a focused branch:
   - `feat/<short-name>`
   - `fix/<short-name>`
   - `docs/<short-name>`
   - `test/<short-name>`
   - `chore/<short-name>`
3. Make small, reviewable commits. Use conventional prefixes such as `feat:`,
   `fix:`, `docs:`, `test:`, `refactor:`, or `chore:`.
4. Open a pull request against `main`. `main` is protected and accepts changes
   only through PRs.
5. Link the related issue and fill in the PR template completely.

## Before opening a PR

Run all of these from the repository root. They match the CI checks:

```powershell
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos --fatal-warnings
flutter test
python -m unittest discover -s server -p "test_*.py" -v
flutter build windows --release
flutter build apk --debug
```

Use check-mode formatting in verification. Running `dart format .` is a local
editing command, not a verification check.

For raw-socket AI tests that can be timing-sensitive on a shared machine, also
run:

```powershell
flutter test test/ai_provider_abstraction_test.dart test/ollama_provider_test.dart --concurrency=1
```

## CI checks

Pull requests run `format`, `analyze`, `test`, `python-telemetry`,
`windows-build`, and `android-debug-apk` jobs, followed by a `pr-gate` job. CI
uses the committed lockfile, requires no secrets, and explicitly disables the
opt-in live Groq tests. Configure those job names as required checks in GitHub
branch protection; the workflow file alone cannot enforce that setting.

For UI changes, include before/after screenshots and confirm the layout at
desktop, compact desktop, and mobile widths. Never include real tokens, PINs,
conversation content, or diagnostics data in screenshots.

## Code expectations

- Follow the existing `lib/` feature-first structure.
- Use shared widgets from `lib/shared/widgets/` and tokens from
  `lib/core/theme/aura_tokens.dart` instead of hard-coded spacing or colors.
- Declare return types, use single quotes, and keep `sort_child_properties_last`
  in mind; `analysis_options.yaml` is the source of truth.
- Persist new preferences through a profile-scoped store with a safe fallback
  for corrupt or missing JSON.
- Add tests for new domain logic, persistence, and UI honesty states. A test
  that only checks that a widget renders is usually not enough.

## Review checklist

Reviewers will look for:

- No fake or implied hardware, firmware, AI, or update success.
- No secrets or personal data in the diff.
- Per-profile data remains isolated.
- Failure states are reported instead of swallowed.
- Tests cover the new behavior and the full suite remains green.
- README, CHANGELOG, and other docs are updated when behavior changes.

## Security issues

Do **not** open a public issue for a vulnerability. Follow [SECURITY.md](SECURITY.md)
and use GitHub's private vulnerability reporting.

## License

By contributing, you agree that your contribution is licensed under the
[MIT License](LICENSE).
