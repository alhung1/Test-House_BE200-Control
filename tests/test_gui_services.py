from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from subprocess import TimeoutExpired
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]
GUI_ROOT = REPO_ROOT / "gui"
sys.path.insert(0, str(GUI_ROOT))

import app as gui_app  # noqa: E402
import services  # noqa: E402


class GuiServicesTests(unittest.TestCase):
    def make_config(self, root: Path) -> dict[str, object]:
        data_root = root / "data"
        jobs_root = data_root / "jobs"
        work_root = root / "work"
        configs_root = work_root / "configs"
        logs_root = root / "logs"
        output_root = root / "output"
        for path in (data_root, jobs_root, work_root, configs_root, logs_root, output_root / "csv", output_root / "json", output_root / "transcripts"):
            path.mkdir(parents=True, exist_ok=True)
        return {
            "toolkit_root": str(root),
            "output_root": str(output_root),
            "data_root": str(data_root),
            "jobs_root": str(jobs_root),
            "work_root": str(work_root),
            "configs_root": str(configs_root),
            "logs_root": str(logs_root),
            "history_index": str(data_root / "history.json"),
            "allowed_targets": ["192.168.22.221", "192.168.22.222"],
            "defaults": {
                "username": "admin",
                "run_timeout_seconds": 5,
                "recent_hours": 24,
                "history_limit": 20,
                "restart_rdp_ping_timeout_minutes": 10,
                "restart_rdp_mstsc_delay_seconds": 3,
                "open_ncpa_default_delay_seconds": 3,
                "open_ncpa_open_mstsc_default": True,
            },
            "app": {"secret_key": ""},
            "property_policy_overrides": {
                "RoamAggressiveness": {
                    "classification": "live-tested",
                    "risk": "low",
                    "accepted_modes": ["WriteOnly", "RestartBE200"],
                    "rationale": "Test-only accepted property",
                }
            },
            "action_policy_overrides": {
                "Status": {
                    "accepted": True,
                    "max_targets": 2,
                    "confirmation_required": False,
                    "rationale": "Read-only status",
                },
                "Restart": {
                    "accepted": True,
                    "max_targets": 2,
                    "confirmation_required": True,
                    "rationale": "Restart accepted with confirmation",
                },
                "Disable": {
                    "accepted": True,
                    "max_targets": 2,
                    "confirmation_required": True,
                    "rationale": "Disable accepted with confirmation",
                },
                "Enable": {
                    "accepted": True,
                    "max_targets": 2,
                    "confirmation_required": True,
                    "rationale": "Enable accepted with confirmation",
                },
            },
        }

    def write_discovery_fixture(self, config: dict[str, object], *, stale_hours: int | None = None) -> str:
        csv_root = Path(config["output_root"]) / "csv"
        discovery_path = csv_root / "gui-be200-discovery-20260101-010101.csv"
        services.write_csv(
            discovery_path,
            [
                "TargetIP",
                "ComputerName",
                "AdapterName",
                "InterfaceDescription",
                "RegistryKeyword",
                "PropertyDisplayName",
                "CurrentDisplayValue",
                "PossibleDisplayValues",
                "RegistryValue",
            ],
            [
                {
                    "TargetIP": "192.168.22.221",
                    "ComputerName": "BE200-221",
                    "AdapterName": "Wi-Fi",
                    "InterfaceDescription": "Intel(R) Wi-Fi 7 BE200 320MHz",
                    "RegistryKeyword": "DriverVersion",
                    "PropertyDisplayName": "DriverVersion",
                    "CurrentDisplayValue": "",
                    "PossibleDisplayValues": "",
                    "RegistryValue": "1.0.0.1",
                },
                {
                    "TargetIP": "192.168.22.222",
                    "ComputerName": "BE200-222",
                    "AdapterName": "Wi-Fi",
                    "InterfaceDescription": "Intel(R) Wi-Fi 7 BE200 320MHz",
                    "RegistryKeyword": "DriverVersion",
                    "PropertyDisplayName": "DriverVersion",
                    "CurrentDisplayValue": "",
                    "PossibleDisplayValues": "",
                    "RegistryValue": "1.0.0.2",
                },
                {
                    "TargetIP": "192.168.22.221",
                    "ComputerName": "BE200-221",
                    "AdapterName": "Wi-Fi",
                    "InterfaceDescription": "Intel(R) Wi-Fi 7 BE200 320MHz",
                    "RegistryKeyword": "RoamAggressiveness",
                    "PropertyDisplayName": "Roam Aggressiveness",
                    "CurrentDisplayValue": "Medium",
                    "PossibleDisplayValues": "Low;Medium;High",
                    "RegistryValue": "2",
                },
                {
                    "TargetIP": "192.168.22.222",
                    "ComputerName": "BE200-222",
                    "AdapterName": "Wi-Fi",
                    "InterfaceDescription": "Intel(R) Wi-Fi 7 BE200 320MHz",
                    "RegistryKeyword": "RoamAggressiveness",
                    "PropertyDisplayName": "Roam Aggressiveness",
                    "CurrentDisplayValue": "High",
                    "PossibleDisplayValues": "Low;Medium;High",
                    "RegistryValue": "3",
                },
            ],
        )
        if stale_hours is not None:
            stale_time = discovery_path.stat().st_mtime - stale_hours * 3600
            os.utime(discovery_path, (stale_time, stale_time))
        return str(discovery_path)

    def write_remoting_fixture(self, config: dict[str, object]) -> str:
        csv_root = Path(config["output_root"]) / "csv"
        remoting_path = csv_root / "gui-test-remoting-summary-20260101-010101.csv"
        services.write_csv(
            remoting_path,
            ["TargetIP", "Reachable", "BE200AdapterFound"],
            [
                {"TargetIP": "192.168.22.221", "Reachable": "True", "BE200AdapterFound": "True"},
                {"TargetIP": "192.168.22.222", "Reachable": "True", "BE200AdapterFound": "True"},
            ],
        )
        return str(remoting_path)

    def save_job_fixture(
        self,
        config: dict[str, object],
        *,
        job_id: str,
        job_type: str,
        title: str,
        status: str,
        artifacts: dict[str, str],
        summary: dict[str, object] | None = None,
        status_reason: str | None = None,
    ) -> dict[str, object]:
        job = {
            "id": job_id,
            "job_type": job_type,
            "title": title,
            "status": status,
            "status_reason": status_reason,
            "started_at": "2026-04-21T10:00:00",
            "finished_at": "2026-04-21T10:05:00",
            "returncode": 0,
            "command": ["powershell.exe", "-File", "dummy.ps1"],
            "stdout": "stdout",
            "stderr": "",
            "artifacts": artifacts,
            "summary": summary or {},
        }
        services.save_job(config, job)
        return job

    def test_load_history_index_recovers_from_corrupt_json(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            config = self.make_config(root)
            history_path = Path(config["history_index"])
            history_path.write_text("{not-json", encoding="utf-8")

            history = services.load_history_index(config)

            self.assertEqual(history, [])
            self.assertEqual(json.loads(history_path.read_text(encoding="utf-8")), [])
            backups = list(history_path.parent.glob("history.json.corrupt-*"))
            self.assertEqual(len(backups), 1)

    def test_load_flask_secret_generates_and_reuses_local_secret(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            config = self.make_config(root)

            first = services.load_flask_secret(config)
            second = services.load_flask_secret(config)

            self.assertTrue(first)
            self.assertEqual(first, second)
            secret_path = Path(config["data_root"]) / "flask-secret.key"
            self.assertTrue(secret_path.exists())
            self.assertEqual(secret_path.read_text(encoding="utf-8").strip(), first)

    def test_load_flask_secret_prefers_environment_override(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            config = self.make_config(root)

            with mock.patch.dict(os.environ, {"BE200_GUI_SECRET_KEY": "env-secret"}, clear=False):
                secret = services.load_flask_secret(config)

            self.assertEqual(secret, "env-secret")
            secret_path = Path(config["data_root"]) / "flask-secret.key"
            self.assertFalse(secret_path.exists())

    def test_apply_job_status_becomes_partial_when_any_row_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            csv_path = root / "apply.csv"
            services.write_csv(
                csv_path,
                ["ApplySucceeded", "VerificationSucceeded"],
                [
                    {"ApplySucceeded": "True", "VerificationSucceeded": "True"},
                    {"ApplySucceeded": "False", "VerificationSucceeded": "False"},
                ],
            )

            status, reason, overview = services.derive_job_status_from_artifacts(
                "apply",
                0,
                {"result_csv": str(csv_path)},
            )

            self.assertEqual(status, "partial")
            self.assertIn("1 of 2", reason or "")
            self.assertEqual(overview["verified_rows"], 1)

    def test_submit_guard_preserves_submitter_name_value(self) -> None:
        template = (GUI_ROOT / "templates" / "base.html").read_text(encoding="utf-8")

        self.assertIn("event.submitter", template)
        self.assertIn("data-submit-proxy", template)
        self.assertIn("proxy.name = submitter.name", template)
        self.assertIn("proxy.value = submitter.value", template)

    def test_run_script_job_persists_failed_timeout_record(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            config = self.make_config(root)

            with mock.patch.object(
                services.subprocess,
                "run",
                side_effect=TimeoutExpired(cmd=["powershell.exe"], timeout=5, output="partial output", stderr="timed out"),
            ):
                job = services.run_script_job(
                    config,
                    "apply",
                    "Apply validated config",
                    "apply-be200-config.ps1",
                    ["-ValidatedConfigPath", "dummy.csv"],
                    {"result_csv": str(root / "missing.csv")},
                    {"targets": ["192.168.22.221"]},
                    timeout_seconds=5,
                )

            self.assertEqual(job["status"], "failed")
            self.assertTrue(job["timed_out"])
            self.assertIn("Timed out after 5 seconds", job["status_reason"])
            self.assertIn("partial output", job["stdout"])

            history = json.loads(Path(config["history_index"]).read_text(encoding="utf-8"))
            self.assertEqual(len(history), 1)
            self.assertEqual(history[0]["id"], job["id"])


class GuiFrontendSmokeTests(GuiServicesTests):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.config = self.make_config(self.root)
        services.ensure_runtime_dirs(self.config)
        gui_app.app.config["TESTING"] = True
        gui_app.app.config["BE200_CONFIG"] = self.config
        self.client = gui_app.app.test_client()

    def tearDown(self) -> None:
        gui_app.app.config.pop("BE200_CONFIG", None)
        self.temp_dir.cleanup()

    def test_dashboard_renders_preflight_and_unresolved_jobs(self) -> None:
        self.write_discovery_fixture(self.config)
        self.write_remoting_fixture(self.config)
        result_csv = Path(self.config["output_root"]) / "csv" / "gui-be200-apply-results-20260101-010101.csv"
        services.write_csv(
            result_csv,
            ["TargetIP", "ApplySucceeded", "VerificationSucceeded"],
            [
                {"TargetIP": "192.168.22.221", "ApplySucceeded": "True", "VerificationSucceeded": "True"},
                {"TargetIP": "192.168.22.222", "ApplySucceeded": "False", "VerificationSucceeded": "False"},
            ],
        )
        self.save_job_fixture(
            self.config,
            job_id="apply-1",
            job_type="apply",
            title="Apply validated config",
            status="partial",
            status_reason="1 of 2 row(s) met the success criteria (verified_rows).",
            artifacts={"result_csv": str(result_csv)},
            summary={"result_overview": {"rows": 2, "verified_rows": 1}},
        )

        response = self.client.get("/")

        self.assertEqual(response.status_code, 200)
        body = response.get_data(as_text=True)
        self.assertIn("Preflight console", body)
        self.assertIn("Needs attention", body)
        self.assertIn("Apply validated config", body)

    def test_history_filters_render_partial_view(self) -> None:
        self.save_job_fixture(
            self.config,
            job_id="partial-job",
            job_type="apply",
            title="Partial apply",
            status="partial",
            status_reason="1 of 2 verified.",
            artifacts={},
            summary={"result_overview": {"rows": 2, "verified_rows": 1}},
        )
        self.save_job_fixture(
            self.config,
            job_id="success-job",
            job_type="validation",
            title="Validation job",
            status="success",
            artifacts={},
            summary={"property_label": "Roam Aggressiveness"},
        )

        response = self.client.get("/history?status=partial&actionable=1")

        self.assertEqual(response.status_code, 200)
        body = response.get_data(as_text=True)
        self.assertIn("Actionable view", body)
        self.assertIn("Partial apply", body)
        self.assertNotIn("Validation job", body)

    def test_job_detail_renders_status_reason_and_failure_filter(self) -> None:
        result_csv = Path(self.config["output_root"]) / "csv" / "gui-be200-apply-results-20260101-020202.csv"
        services.write_csv(
            result_csv,
            ["TargetIP", "ApplySucceeded", "VerificationSucceeded", "RestartSucceeded"],
            [
                {"TargetIP": "192.168.22.221", "ApplySucceeded": "True", "VerificationSucceeded": "True", "RestartSucceeded": "True"},
                {"TargetIP": "192.168.22.222", "ApplySucceeded": "False", "VerificationSucceeded": "False", "RestartSucceeded": "False"},
            ],
        )
        self.save_job_fixture(
            self.config,
            job_id="apply-detail",
            job_type="apply",
            title="Apply detail job",
            status="partial",
            status_reason="1 of 2 row(s) met the success criteria (verified_rows).",
            artifacts={"result_csv": str(result_csv)},
            summary={"result_overview": {"rows": 2, "verified_rows": 1}},
        )

        response = self.client.get("/jobs/apply-detail?rows=failures")

        self.assertEqual(response.status_code, 200)
        body = response.get_data(as_text=True)
        self.assertIn("Status reason", body)
        self.assertIn("<td class=\"small font-mono\">192.168.22.222</td>", body)
        self.assertNotIn("<td class=\"small font-mono\">192.168.22.221</td>", body)
        self.assertIn("Failures", body)

    def test_editor_shows_discovery_freshness_and_execution_summary(self) -> None:
        self.write_discovery_fixture(self.config, stale_hours=80)

        response = self.client.get("/editor")

        self.assertEqual(response.status_code, 200)
        body = response.get_data(as_text=True)
        self.assertIn("Discovery freshness", body)
        self.assertIn("Execution summary", body)
        self.assertIn("Run validation", body)

    def test_guarded_forms_render_on_operations_pages(self) -> None:
        for route in ("/system-restart-rdp", "/open-ncpa", "/wifi-connect", "/current-settings"):
            response = self.client.get(route)
            self.assertEqual(response.status_code, 200, route)
            body = response.get_data(as_text=True)
            self.assertIn("data-guarded-submit=\"true\"", body, route)


if __name__ == "__main__":
    unittest.main()
