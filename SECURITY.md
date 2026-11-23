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
- Unsupported-platform secure storage, which is reported as unavailable rather
  than emulated with plaintext
- Third-party services such as Groq, Ollama, or Windows itself
- Physical AURA hardware, which does not exist in this build

## Security boundaries to know

- The local telemetry API generates a random bearer token per app launch.
  `/api/health` is public and non-sensitive; `/api/system` and `/api/shutdown`
  require `Authorization: Bearer <token>`, compared in constant time. The token
  reaches the child only through `AURA_API_TOKEN`; it is never a CLI argument,
  settings value, log field, URL, diagnostics export, or request record. CORS is
  not open, and there is no unauthenticated compatibility mode.
- The server refuses a non-loopback bind without a token, and AURA Settings
  rejects plain HTTP on a non-loopback host instead of rewriting the address.
- Every AI controller requires an explicit `ProfileAccessReader`. Locked AYUSH
  reads return safe empty or idle state, while writes and secret resolution
  throw `AuraProfileAccessDenied` before any HTTP, vault, config, or secret side
  effect.
- The AYUSH PIN is a local convenience lock backed by PBKDF2-HMAC-SHA256, not an
  OS credential vault or backend authenticator. Verifier replacement is atomic,
  lockout state persists across restarts, and corrupt state fails closed with a
  fixed temporary lockout and a visible recovery path.
- AYUSH also locks shortly after the app leaves the foreground, with a short
  configurable grace period independent of the inactivity timeout. A `Never`
  inactivity setting does not disable background lock.
- Windows Credential Manager and DPAPI are Windows-only. Android and Web fail
  closed rather than using a plaintext substitute; Android Keystore-backed
  private storage is not implemented in this build. Unsupported platforms show
  an unavailable-storage state, refuse API-key writes, and keep Groq visible and
  selectable.
- Native zeroization follows allocator ownership: DPAPI output is zeroized
  before `LocalFree`, vault allocations before `HeapFree`, and `CredReadW`
  output via `CredFree` only. Runtime and OS-owned memory that AURA does not
  allocate cannot be guaranteed zeroized.
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
