"""AURA local telemetry API.

Exposes real Windows system readings to the AURA Hub Flutter app over REST.
No simulated values are produced here: every number comes from psutil or the
Windows firewall command line.
"""
from __future__ import annotations

import json
import os
import platform
import socket
import subprocess
import threading
import time
import traceback
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

import psutil

# Loopback by default: this API exposes host telemetry and has no
# authentication. Do not expose it on a LAN until an auth layer exists.
HOST = os.environ.get("AURA_API_HOST", "127.0.0.1")
PORT = int(os.environ.get("AURA_API_PORT", "8765"))

API_VERSION = "1.1.0"

PROCESS_CACHE_SECONDS = 5.0
FIREWALL_CACHE_SECONDS = 60.0
SAMPLE_INTERVAL_SECONDS = 1.0


class FirewallState:
    """Explicit firewall states. A failed probe is never 'disabled'."""

    ENABLED = "enabled"
    DISABLED = "disabled"
    UNAVAILABLE = "unavailable"


def _iso(timestamp: float) -> str:
    return datetime.fromtimestamp(timestamp, tz=timezone.utc).isoformat()


def _log(message: str) -> None:
    stamp = datetime.now(timezone.utc).isoformat(timespec="milliseconds")
    print(f"{stamp} {message}", flush=True)


def _top_processes(limit: int = 5) -> list[dict[str, object]]:
    """Expensive psutil walk; called by the sampler, never per request."""
    processes = []
    for process in psutil.process_iter(attrs=["pid", "name", "memory_percent"]):
        try:
            info = process.info
            processes.append(
                {
                    "pid": info["pid"],
                    "name": info["name"] or "unknown",
                    "memoryPercent": round(float(info["memory_percent"] or 0), 2),
                }
            )
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    processes.sort(key=lambda item: item["memoryPercent"], reverse=True)
    return processes[:limit]


def _probe_firewall_state() -> str:
    """Read Windows firewall profiles. Blocking, so cached by the sampler.

    Returns one of the FirewallState values. A failed, unreadable or
    non-zero probe is UNAVAILABLE - never DISABLED - so a broken command cannot
    be mistaken for a firewall that is actually turned off.
    """
    try:
        flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        result = subprocess.run(
            ["netsh", "advfirewall", "show", "allprofiles", "state"],
            capture_output=True,
            text=True,
            timeout=5,
            creationflags=flags,
        )
    except (OSError, subprocess.SubprocessError) as error:
        _log(f"FIREWALL probe unavailable: {type(error).__name__}")
        return FirewallState.UNAVAILABLE

    if result.returncode != 0:
        _log(f"FIREWALL probe unavailable: exit code {result.returncode}")
        return FirewallState.UNAVAILABLE

    states = []
    for line in result.stdout.splitlines():
        parts = line.strip().split()
        if len(parts) >= 2 and parts[0].lower() == "state":
            states.append(parts[-1].lower())
    if not states:
        _log("FIREWALL probe unavailable: no profile states reported")
        return FirewallState.UNAVAILABLE
    if all(state == "on" for state in states):
        return FirewallState.ENABLED
    return FirewallState.DISABLED


def _active_interface_count() -> int:
    try:
        stats = psutil.net_if_stats()
        addresses = psutil.net_if_addrs()
    except OSError:
        return 0
    count = 0
    for name, stat in stats.items():
        if not stat.isup:
            continue
        if any(
            address.family in (psutil.AF_LINK, socket.AF_INET)
            and not str(address.address).startswith("127.")
            for address in addresses.get(name, [])
        ):
            count += 1
    return count


class TelemetrySampler:
    """Samples changing counters in the background so requests stay fast.

    Construction and start() are deliberately cheap: expensive process and
    firewall probes happen on the background thread. Until the first complete
    sample, callers receive explicit 'not ready' / 'unavailable' states.
    """

    def __init__(
        self,
        *,
        probe_firewall=_probe_firewall_state,
        top_processes=_top_processes,
        sample_interval_seconds: float = SAMPLE_INTERVAL_SECONDS,
    ) -> None:
        self._lock = threading.Lock()
        self._stop_event = threading.Event()
        self._started = False
        self._probe_firewall = probe_firewall
        self._top_processes = top_processes
        self._sleep_seconds = max(0.01, sample_interval_seconds)

        # Cheap defaults only; real readings are filled by the sampler.
        self._cpu_percent = 0.0
        self._cpu_per_core: list[float] = []
        self._net = None
        self._net_time = time.monotonic()
        self._sent_rate = 0.0
        self._recv_rate = 0.0
        self._top: list[dict[str, object]] = []
        self._process_count = 0
        self._process_checked = 0.0
        self._process_ready = False
        self._firewall_state = FirewallState.UNAVAILABLE
        self._firewall_checked = 0.0
        self._firewall_ready = False

        # Sampler health, kept separate from HTTP request outcomes.
        self._ready = False
        self._healthy = False
        self._last_success_at: float | None = None
        self._last_failure_at: float | None = None
        self._last_error: str | None = None
        self._consecutive_failures = 0

        self._thread = threading.Thread(
            target=self._run,
            name="aura-telemetry-sampler",
            daemon=True,
        )

    def start(self) -> None:
        """Start background sampling without blocking the HTTP server."""
        if self._started:
            return
        self._started = True
        self._thread.start()

    def stop(self) -> None:
        """Request a clean shutdown (used on server exit and in tests)."""
        self._stop_event.set()

    def _record_failure(self, stage: str, error: BaseException) -> None:
        # Full detail is logged locally; only the exception type is exposed to
        # clients. Exception messages can contain paths or other private data.
        _log(f"SAMPLER FAILURE [{stage}] {type(error).__name__}: {error}")
        with self._lock:
            self._healthy = False
            self._last_failure_at = time.time()
            self._last_error = type(error).__name__
            self._consecutive_failures += 1

    def _mark_success(self) -> None:
        with self._lock:
            self._ready = True
            self._healthy = True
            self._last_success_at = time.time()
            self._last_error = None
            self._consecutive_failures = 0

    def sample_once(self) -> None:
        """Take one sample. Individual failures never stop later samples."""
        failed = False

        try:
            cpu = psutil.cpu_percent(interval=None)
            per_core = psutil.cpu_percent(interval=None, percpu=True) or []
            net = psutil.net_io_counters()
            now = time.monotonic()
            with self._lock:
                self._cpu_percent = cpu
                self._cpu_per_core = list(per_core)
                if net is not None and self._net is not None:
                    elapsed = max(now - self._net_time, 0.001)
                    self._sent_rate = max(
                        0.0, (net.bytes_sent - self._net.bytes_sent) / elapsed
                    )
                    self._recv_rate = max(
                        0.0, (net.bytes_recv - self._net.bytes_recv) / elapsed
                    )
                self._net = net
                self._net_time = now
        except Exception as error:  # noqa: BLE001 - sampler must never die
            failed = True
            self._record_failure("cpu-network", error)

        now = time.monotonic()
        with self._lock:
            need_processes = (
                not self._process_ready
                or now - self._process_checked >= PROCESS_CACHE_SECONDS
            )
            need_firewall = (
                not self._firewall_ready
                or now - self._firewall_checked >= FIREWALL_CACHE_SECONDS
            )

        if need_processes:
            try:
                top = self._top_processes()
                count = len(psutil.pids())
                with self._lock:
                    self._top = top
                    self._process_count = count
                    self._process_checked = now
                    self._process_ready = True
            except Exception as error:  # noqa: BLE001
                failed = True
                self._record_failure("processes", error)

        if need_firewall:
            try:
                state = self._probe_firewall()
                with self._lock:
                    self._firewall_state = state
                    self._firewall_checked = now
                    self._firewall_ready = True
            except Exception as error:  # noqa: BLE001
                failed = True
                self._record_failure("firewall", error)

        if not failed:
            self._mark_success()

    def _run(self) -> None:
        while not self._stop_event.is_set():
            try:
                self.sample_once()
            except Exception as error:  # noqa: BLE001 - last-resort guard
                self._record_failure("loop", error)
            self._stop_event.wait(self._sleep_seconds)

    def health(self) -> dict[str, object]:
        """Sampler-only health, safe to expose over REST."""
        with self._lock:
            return {
                "ready": self._ready,
                "healthy": self._healthy,
                "lastSuccessAt": (
                    _iso(self._last_success_at)
                    if self._last_success_at is not None
                    else None
                ),
                "lastFailureAt": (
                    _iso(self._last_failure_at)
                    if self._last_failure_at is not None
                    else None
                ),
                "lastError": self._last_error,
                "consecutiveFailures": self._consecutive_failures,
            }

    @property
    def cpu(self) -> tuple[float, list[float], float, float]:
        with self._lock:
            return (
                self._cpu_percent,
                list(self._cpu_per_core),
                self._sent_rate,
                self._recv_rate,
            )

    @property
    def processes(self) -> tuple[int, list[dict[str, object]]]:
        with self._lock:
            return self._process_count, [dict(item) for item in self._top]

    def firewall_state(self) -> str:
        with self._lock:
            return self._firewall_state

    def firewall_enabled(self) -> bool | None:
        """Backward-compatible boolean view; None means explicitly unavailable."""
        state = self.firewall_state()
        if state == FirewallState.ENABLED:
            return True
        if state == FirewallState.DISABLED:
            return False
        return None


def build_system_payload(sampler: TelemetrySampler) -> dict[str, object]:
    cpu_percent, per_core, sent_rate, recv_rate = sampler.cpu
    process_count, top_processes = sampler.processes
    firewall_state = sampler.firewall_state()
    boot_time = psutil.boot_time()
    memory = psutil.virtual_memory()
    drive = os.environ.get("SystemDrive", "C:") + os.sep
    disk = psutil.disk_usage(drive)
    net = psutil.net_io_counters()
    battery = psutil.sensors_battery()
    try:
        frequency_value = psutil.cpu_freq()
        frequency_mhz = frequency_value.current if frequency_value else 0.0
    except (OSError, NotImplementedError):
        frequency_mhz = 0.0

    battery_payload = None
    if battery is not None:
        battery_payload = {
            "percent": round(battery.percent),
            "plugged": bool(battery.power_plugged),
            "secondsLeft": None
            if battery.secsleft
            in (psutil.POWER_TIME_UNLIMITED, psutil.POWER_TIME_UNKNOWN)
            else int(battery.secsleft),
        }

    return {
        "generatedAt": _iso(time.time()),
        "apiVersion": API_VERSION,
        "host": {
            "name": platform.node(),
            "os": platform.platform(),
            "bootTime": _iso(boot_time),
            "uptimeSeconds": int(max(0, time.time() - boot_time)),
        },
        "cpu": {
            "usagePercent": round(cpu_percent, 1),
            "perCore": [round(value, 1) for value in per_core],
            "cores": psutil.cpu_count(logical=True) or 0,
            "frequencyMHz": round(frequency_mhz),
        },
        "memory": {
            "totalBytes": memory.total,
            "usedBytes": memory.used,
            "availableBytes": memory.available,
            "usagePercent": round(memory.percent, 1),
        },
        "disk": {
            "path": drive,
            "totalBytes": disk.total,
            "usedBytes": disk.used,
            "freeBytes": disk.free,
            "usagePercent": round(disk.percent, 1),
        },
        "network": {
            "bytesSent": net.bytes_sent if net else 0,
            "bytesReceived": net.bytes_recv if net else 0,
            "sentBytesPerSecond": round(sent_rate, 1),
            "receivedBytesPerSecond": round(recv_rate, 1),
            "activeInterfaces": _active_interface_count(),
        },
        "battery": battery_payload,
        "processCount": process_count,
        "topProcesses": top_processes,
        "security": {
            "firewallEnabled": sampler.firewall_enabled(),
            "firewallState": firewall_state,
        },
        "sampler": sampler.health(),
    }


class AuraHandler(BaseHTTPRequestHandler):
    sampler: TelemetrySampler

    def _send_json(self, status: int, payload: dict[str, object]) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _finish(self, started: float, path: str, status: int) -> None:
        duration_ms = (time.monotonic() - started) * 1000
        _log(f"{self.command} {path} -> {status} ({duration_ms:.1f} ms)")

    def do_GET(self) -> None:  # noqa: N802
        started = time.monotonic()
        path = urlparse(self.path).path
        if path == "/api/health":
            self._send_json(
                200,
                {
                    "status": "ok",
                    "service": "aura-local-telemetry",
                    "version": API_VERSION,
                    "time": _iso(time.time()),
                    "sampler": self.sampler.health(),
                },
            )
            self._finish(started, path, 200)
            return
        if path == "/api/system":
            try:
                self._send_json(200, build_system_payload(self.sampler))
                self._finish(started, path, 200)
            except Exception as error:  # keep the listener alive on failure
                _log(f"ERROR collecting telemetry: {error!r}")
                traceback.print_exc()
                try:
                    self._send_json(500, {"error": "telemetry collection failed"})
                    self._finish(started, path, 500)
                except (OSError, ConnectionError):
                    _log("Client disconnected before error response was sent")
            return
        self._send_json(404, {"error": "Not found"})
        self._finish(started, path, 404)

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def log_message(self, format: str, *args: object) -> None:
        # Handled by _finish with a duration instead.
        return

    def log_error(self, format: str, *args: object) -> None:
        _log(f"HTTP ERROR {format % args}")


def main() -> None:
    sampler = TelemetrySampler()
    AuraHandler.sampler = sampler
    # Bind and serve immediately. Expensive telemetry work is asynchronous.
    server = ThreadingHTTPServer((HOST, PORT), AuraHandler)
    sampler.start()
    _log(f"AURA telemetry API listening on http://{HOST}:{PORT}")
    _log("GET /api/health  GET /api/system")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        sampler.stop()
        server.server_close()
        _log("AURA telemetry API stopped")


if __name__ == "__main__":
    main()
