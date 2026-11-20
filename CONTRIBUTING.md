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
- **Local first.** The loopback telemetry API has no authentication. Keep it
  bound to `127.0.0.1` unless a change explicitly adds authentication.
- **Be conservative with device features.** There is no BLE/Wi-Fi transport and
  no OTA service yet. New device code must be a contract or an honest
  unavailable state until real hardware exists.

## Ways to contribute

- Report a bug with a clear repro and environment details.
- Proposal a feature with the problem first, not just the solution.
- Improve docs, translations, tests, accessibility, or diagnostics.
- Review pull requests with attention to honesty and data isolation.

## Development setup

See the [Run it locally](README.md#-run-it-locally) section in the README. In
short:

```powershell
flutter pub get
flutter run -d windows
```

For telemetry, create `server\.venv` once and install
`server\requirements.txt`. A Python 3 runtime is still required for packaged
Windows builds.

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

Run all of these from the repository root:

```powershell
dart format .
flutter analyze
flutter test
flutter test --concurrency=1
flutter build windows
```

If you changed the Python telemetry API, also run:

```powershell
server\.venv\Scripts\python.exe -m unittest discover -s server -p "test_*.py" -v
```

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
