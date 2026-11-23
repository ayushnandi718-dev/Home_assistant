# Bundled test font attribution

- **Family:** Inter
- **Version:** 4.1
- **Source:** https://github.com/rsms/inter/releases/tag/v4.1
- **Downloaded asset:** https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip
- **Files used:** `Inter-Regular.ttf`, `Inter-Medium.ttf`, `Inter-SemiBold.ttf` (from `extras/ttf/` in the release archive)
- **Copyright:** Copyright (c) 2016 The Inter Project Authors (https://github.com/rsms/inter)
- **Licence:** SIL Open Font License, Version 1.1 — full text in `OFL.txt`

These files are loaded only by `test/mobile_preview_golden_test.dart` via Flutter's
`FontLoader` so golden text rendering is deterministic on Windows and Linux. They
are not declared in `pubspec.yaml` and are not used by production typography.
