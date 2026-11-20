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

- [ ] `dart format .`
- [ ] `flutter analyze`
- [ ] `flutter test` / `flutter test --concurrency=1`
- [ ] `flutter build windows` (if app/native code changed)
- [ ] Python telemetry tests (if `server/` changed)

## Screenshots

<!-- For UI changes: desktop, compact desktop, and mobile widths. Redact real data. -->

## Additional notes

<!-- Risks, follow-ups, or reviewer focus areas. -->
