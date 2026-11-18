"""Reliability tests for the local telemetry API (stdlib unittest only).

Run with:
    server\\.venv\\Scripts\\python.exe -m unittest discover -s server -p "test_*.py" -v
"""
from __future__ import annotations

import json
import threading
import time
import unittest
import urllib.request
from types import SimpleNamespace
from unittest.mock import patch

import aura_api


class FirewallStateTests(unittest.TestCase):
    def _probe(self, stdout="", returncode=0, side_effect=None):
        with patch.object(aura_api.subprocess, "run") as run:
            if side_effect is not None:
                run.side_effect = side_effect
            else:
                run.return_value = SimpleNamespace(
                    returncode=returncode, stdout=stdout
                )
            return aura_api._probe_firewall_state()

    def test_enabled_when_all_profiles_are_on(self):
        state = self._probe(stdout="State    ON\nState    ON\n")
        self.assertEqual(state, aura_api.FirewallState.ENABLED)

    def test_disabled_when_a_profile_is_off(self):
        state = self._probe(stdout="State    ON\nState    OFF\n")
        self.assertEqual(state, aura_api.FirewallState.DISABLED)

    def test_failed_probe_is_unavailable_not_disabled(self):
        state = self._probe(side_effect=OSError("netsh missing"))
        self.assertEqual(state, aura_api.FirewallState.UNAVAILABLE)

    def test_nonzero_exit_is_unavailable_not_disabled(self):
        state = self._probe(returncode=1)
        self.assertEqual(state, aura_api.FirewallState.UNAVAILABLE)

    def test_no_reported_states_is_unavailable_not_disabled(self):
        state = self._probe(stdout="no profile information here\n")
        self.assertEqual(state, aura_api.FirewallState.UNAVAILABLE)


class SamplerHealthTests(unittest.TestCase):
    def test_failure_is_recorded_then_sampling_recovers(self):
        calls = {"count": 0}

        def flaky_probe():
            calls["count"] += 1
            if calls["count"] == 1:
                raise RuntimeError("transient probe failure")
            return aura_api.FirewallState.ENABLED

        sampler = aura_api.TelemetrySampler(
            probe_firewall=flaky_probe,
            top_processes=lambda: [],
        )

        sampler.sample_once()
        failed = sampler.health()
        self.assertFalse(failed["ready"], "no complete sample yet")
        self.assertFalse(failed["healthy"])
        self.assertEqual(failed["consecutiveFailures"], 1)
        self.assertEqual(failed["lastError"], "RuntimeError")
        self.assertIsNotNone(failed["lastFailureAt"])

        sampler.sample_once()
        recovered = sampler.health()
        self.assertTrue(recovered["ready"])
        self.assertTrue(recovered["healthy"])
        self.assertEqual(recovered["consecutiveFailures"], 0)
        self.assertIsNone(recovered["lastError"])
        self.assertIsNotNone(recovered["lastSuccessAt"])

    def test_exception_messages_are_not_exposed_to_clients(self):
        def bad_probe():
            raise RuntimeError("C:\\secret\\token=abc123")

        sampler = aura_api.TelemetrySampler(
            probe_firewall=bad_probe,
            top_processes=lambda: [],
        )
        sampler.sample_once()

        exposed = json.dumps(sampler.health())
        self.assertNotIn("secret", exposed)
        self.assertNotIn("token", exposed)
        self.assertIn("RuntimeError", exposed)

    def test_background_loop_continues_after_unexpected_error(self):
        sampler = aura_api.TelemetrySampler(
            probe_firewall=lambda: aura_api.FirewallState.ENABLED,
            top_processes=lambda: [],
            sample_interval_seconds=0.01,
        )
        original = sampler.sample_once
        calls = {"count": 0}

        def flaky_once():
            calls["count"] += 1
            if calls["count"] == 1:
                raise ValueError("unexpected loop error")
            original()

        sampler.sample_once = flaky_once
        sampler.start()
        try:
            deadline = time.monotonic() + 5
            while not sampler.health()["ready"] and time.monotonic() < deadline:
                time.sleep(0.02)
            health = sampler.health()
            self.assertTrue(health["ready"], "loop survived and sampled again")
            self.assertGreaterEqual(calls["count"], 2)
        finally:
            sampler.stop()
            sampler._thread.join(timeout=3)
            self.assertFalse(sampler._thread.is_alive())


class StartupTests(unittest.TestCase):
    def test_payload_before_first_sample_reports_unavailable(self):
        sampler = aura_api.TelemetrySampler(
            top_processes=lambda: [],
            probe_firewall=lambda: aura_api.FirewallState.ENABLED,
        )
        # Deliberately do not start the sampler: this is the startup window.
        payload = aura_api.build_system_payload(sampler)

        self.assertFalse(payload["sampler"]["ready"])
        self.assertIsNone(payload["sampler"]["lastSuccessAt"])
        self.assertEqual(payload["apiVersion"], aura_api.API_VERSION)
        self.assertEqual(payload["processCount"], 0)
        self.assertEqual(payload["topProcesses"], [])
        self.assertEqual(
            payload["security"]["firewallState"],
            aura_api.FirewallState.UNAVAILABLE,
        )
        self.assertIsNone(payload["security"]["firewallEnabled"])

    def test_health_endpoint_responds_while_sampler_is_pending(self):
        sampler = aura_api.TelemetrySampler(
            top_processes=lambda: [],
            probe_firewall=lambda: aura_api.FirewallState.ENABLED,
        )
        aura_api.AuraHandler.sampler = sampler
        server = aura_api.ThreadingHTTPServer(
            (aura_api.HOST, 0), aura_api.AuraHandler
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            url = f"http://127.0.0.1:{server.server_port}/api/health"
            with urllib.request.urlopen(url, timeout=3) as response:
                payload = json.loads(response.read().decode("utf-8"))
            self.assertEqual(payload["status"], "ok")
            self.assertEqual(payload["version"], aura_api.API_VERSION)
            self.assertIn("sampler", payload)
            self.assertFalse(payload["sampler"]["ready"])
            self.assertIsNone(payload["sampler"]["lastSuccessAt"])
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)

    def test_health_endpoint_separates_http_from_sampler_health(self):
        def bad_probe():
            raise RuntimeError("probe unavailable")

        sampler = aura_api.TelemetrySampler(
            top_processes=lambda: [],
            probe_firewall=bad_probe,
        )
        sampler.sample_once()
        self.assertFalse(sampler.health()["healthy"])

        aura_api.AuraHandler.sampler = sampler
        server = aura_api.ThreadingHTTPServer(
            (aura_api.HOST, 0), aura_api.AuraHandler
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            url = f"http://127.0.0.1:{server.server_port}/api/health"
            with urllib.request.urlopen(url, timeout=3) as response:
                self.assertEqual(response.status, 200)
                payload = json.loads(response.read().decode("utf-8"))
            # HTTP is healthy even though the background sampler is not.
            self.assertEqual(payload["status"], "ok")
            self.assertEqual(payload["version"], aura_api.API_VERSION)
            self.assertFalse(payload["sampler"]["ready"])
            self.assertFalse(payload["sampler"]["healthy"])
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)

    def test_shutdown_endpoint_stops_server_without_touching_health_contract(self):
        sampler = aura_api.TelemetrySampler(
            top_processes=lambda: [],
            probe_firewall=lambda: aura_api.FirewallState.ENABLED,
        )
        aura_api.AuraHandler.sampler = sampler
        server = aura_api.ThreadingHTTPServer(
            (aura_api.HOST, 0), aura_api.AuraHandler
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{server.server_port}"
        try:
            with urllib.request.urlopen(f"{base}/api/health", timeout=3) as response:
                health = json.loads(response.read().decode("utf-8"))
            self.assertEqual(response.status, 200)
            self.assertEqual(health["status"], "ok")
            self.assertEqual(health["service"], "aura-local-telemetry")

            request = urllib.request.Request(
                f"{base}/api/shutdown", data=b"", method="POST"
            )
            with urllib.request.urlopen(request, timeout=3) as response:
                payload = json.loads(response.read().decode("utf-8"))
            self.assertEqual(response.status, 202)
            self.assertEqual(payload["status"], "accepted")

            thread.join(timeout=3)
            self.assertFalse(thread.is_alive())
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)


if __name__ == "__main__":
    unittest.main()
