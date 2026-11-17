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

PROCESS_CACHE_SECONDS = 5.0
FIREWALL_CACHE_SECONDS = 60.0


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


def _probe_firewall_state() -> bool:
    """Read Windows firewall profiles. Blocking, so cached by the sampler."""
    try:
        flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        result = subprocess.run(
            ["netsh", "advfirewall", "show", "allprofiles", "state"],
            capture_output=True,
            text=True,
            timeout=5,
            creationflags=flags,
        )
        states = []
        for line in result.stdout.splitlines():
            parts = line.strip().split()
            if len(parts) >= 2 and parts[0].lower() == "state":
                states.append(parts[-1].lower())
        return bool(states) and all(state == "on" for state in states)
    except (OSError, subprocess.SubprocessError):
        return False


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
    """Samples changing counters in the background so requests stay fast."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._cpu_percent = psutil.cpu_percent(interval=None)
        self._cpu_per_core = psutil.cpu_percent(interval=None, percpu=True) or []
        self._net = psutil.net_io_counters()
        self._net_time = time.monotonic()
        self._sent_rate = 0.0
        self._recv_rate = 0.0
        self._top = list[dict[str, object]]()
        self._process_count = len(psutil.pids())
        self._process_checked = 0.0
        self._firewall_enabled: bool | None = None
        self._firewall_checked = 0.0
        self._thread = threading.Thread(target=self._run, daemon=True)

    def start(self) -> None:
        # Prime expensive caches before accepting requests.
        self._refresh_processes()
        with self._lock:
            self._firewall_enabled = _probe_firewall_state()
            self._firewall_checked = time.monotonic()
        self._thread.start()

    def _refresh_processes(self) -> None:
        try:
            top = _top_processes()
            count = len(psutil.pids())
        except (OSError, psutil.Error):
            return
        with self._lock:
            self._top = top
            self._process_count = count
            self._process_checked = time.monotonic()

    def _refresh_firewall(self) -> None:
        enabled = _probe_firewall_state()
        with self._lock:
            self._firewall_enabled = enabled
            self._firewall_checked = time.monotonic()

    def _run(self) -> None:
        while True:
            time.sleep(1.0)
            cpu = psutil.cpu_percent(interval=None)
            per_core = psutil.cpu_percent(interval=None, percpu=True) or []
            net = psutil.net_io_counters()
            now = time.monotonic()
            elapsed = max(now - self._net_time, 0.001)
            with self._lock:
                self._cpu_percent = cpu
                self._cpu_per_core = per_core
                if net is not None and self._net is not None:
                    self._sent_rate = max(
                        0.0, (net.bytes_sent - self._net.bytes_sent) / elapsed
                    )
                    self._recv_rate = max(
                        0.0, (net.bytes_recv - self._net.bytes_recv) / elapsed
                    )
                self._net = net
                self._net_time = now
                need_processes = (
                    now - self._process_checked >= PROCESS_CACHE_SECONDS
                )
                need_firewall = (
                    now - self._firewall_checked >= FIREWALL_CACHE_SECONDS
                )

            if need_processes:
                self._refresh_processes()
            if need_firewall:
                self._refresh_firewall()

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

    def firewall_enabled(self) -> bool | None:
        with self._lock:
            return self._firewall_enabled


def build_system_payload(sampler: TelemetrySampler) -> dict[str, object]:
    cpu_percent, per_core, sent_rate, recv_rate = sampler.cpu
    process_count, top_processes = sampler.processes
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
        "security": {"firewallEnabled": sampler.firewall_enabled()},
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
                    "time": _iso(time.time()),
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
    sampler.start()
    server = ThreadingHTTPServer((HOST, PORT), AuraHandler)
    _log(f"AURA telemetry API listening on http://{HOST}:{PORT}")
    _log("GET /api/health  GET /api/system")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        _log("AURA telemetry API stopped")


if __name__ == "__main__":
    main()
