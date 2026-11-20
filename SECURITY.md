# Security Policy

## Supported versions

| Version | Supported |
| --- | --- |
| `0.1.x` | Yes — latest release only |
| < `0.1.0` | No |

Use the latest [GitHub release](https://github.com/ayushnandi718-dev/Home_assistant/releases)
wherever possible.

## Reporting a vulnerability

Please **do not** open a public issue for a security problem.

Use GitHub's private vulnerability reporting:
**Security → Report a vulnerability** on this repository, or contact the
maintainer privately through their GitHub profile.

Include:

- Affected version and platform
- Steps to reproduce
- Impact
- Any redacted logs or screenshots needed to understand the issue

Never include real API keys, PINs, tokens, conversation content, or personal
data in a report.

## What to expect

- Acknowledgement: best effort within 7 days
- Status update: at least every 30 days while investigating
- Disclosure: coordinated with you after a fix or mitigation is available

## Scope

In scope:

- AURA Hub Flutter application code and packaged Windows build
- Local preference stores and per-profile isolation
- AYUSH PIN verifier and local session guard
- Integration token-store boundary and Windows Credential Manager usage
- Loopback telemetry API in `server/aura_api.py`
- AI provider adapters and endpoint/header handling
- Firmware preference and digest tooling

Out of scope for now:

- Features that are explicitly marked `Preview only`, `Not implemented`, or
  `Requires AURA hardware`
- The bundled telemetry API's lack of authentication when it is intentionally
  bound to loopback for local development
- Third-party services such as Groq, Ollama, or Windows itself
- Physical AURA hardware, which does not exist in this build

## Security boundaries to know

- The local telemetry API has **no authentication** and must stay bound to
  `127.0.0.1` until authentication is added.
- The AYUSH PIN is a local convenience lock backed by PBKDF2-HMAC-SHA256, not an
  OS credential vault or backend authenticator.
- Provider keys are resolved only at request time through the token-store seam
  and are never written to preferences, diagnostics, or logs.
- The Firmware page does not download, verify, or install anything. A local
  SHA-256 digest is not authenticity verification without a trusted signed
  manifest.
- No device transport exists. A reachable Windows telemetry API is not a paired
  AURA device.

## Safe disclosure

Do not publish exploit details until the maintainer confirms the issue is fixed
or agrees to public disclosure. Credit is available on request in
[ACKNOWLEDGMENTS.md](ACKNOWLEDGMENTS.md).
