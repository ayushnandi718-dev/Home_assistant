## Summary

<!-- What changed and why? Link the related issue with "Closes #123". -->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Documentation
- [ ] Test or tooling
- [ ] Refactor / chore

## Honesty checklist

- [ ] No fake device pairing, firmware install, update progress, or verification success
- [ ] No API keys, PINs, tokens, conversation content, or personal data in the diff
- [ ] Per-profile AYUSH/FAMILY data remains isolated
- [ ] New states use the existing capability vocabulary where applicable
- [ ] Failure states are reported instead of silently swallowed

## Verification

CI runs these checks automatically. Confirm they pass locally before opening the
PR:

- [ ] `dart format --output=none --set-exit-if-changed .`
- [ ] `flutter analyze --fatal-infos --fatal-warnings`
- [ ] `flutter test`
- [ ] `python -m unittest discover -s server -p "test_*.py" -v`
- [ ] `flutter build windows --release`
- [ ] `flutter build apk --debug`

Live Groq tests remain opt-in and are disabled in CI.

## Screenshots

<!-- For UI changes: desktop, compact desktop, and mobile widths. Redact real data. -->

## Additional notes

<!-- Risks, follow-ups, or reviewer focus areas. -->
