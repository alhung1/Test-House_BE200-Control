from __future__ import annotations

import csv
import json
import os
import re
import socket
import subprocess
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any


TIMESTAMP_RE = re.compile(r"(\d{8}-\d{6}(?:-\d{6})?)")


def load_app_config(gui_root: Path) -> dict[str, Any]:
    config_path = gui_root / "config.json"
    with config_path.open("r", encoding="utf-8") as handle:
        config = json.load(handle)

    config["gui_root"] = str(gui_root)
    config["data_root"] = str(gui_root / "data")
    config["jobs_root"] = str(gui_root / "data" / "jobs")
    config["work_root"] = str(gui_root / "work")
    config["configs_root"] = str(gui_root / "work" / "configs")
    config["logs_root"] = str(gui_root / "logs")
    config["history_index"] = str(gui_root / "data" / "history.json")
    return config


def ensure_runtime_dirs(config: dict[str, Any]) -> None:
    for key in ("data_root", "jobs_root", "work_root", "configs_root", "logs_root"):
        Path(config[key]).mkdir(parents=True, exist_ok=True)

    history_index = Path(config["history_index"])
    if not history_index.exists():
        history_index.write_text("[]\n", encoding="utf-8")


def now_timestamp() -> str:
    return datetime.now().strftime("%Y%m%d-%H%M%S-%f")


def parse_timestamp(value: str | None) -> str | None:
    if not value:
        return None
    match = TIMESTAMP_RE.search(value)
    if not match:
        return None
    return match.group(1)


def human_timestamp(value: str | None) -> str:
    if not value:
        return "N/A"
    for fmt in ("%Y%m%d-%H%M%S-%f", "%Y%m%d-%H%M%S"):
        try:
            parsed = datetime.strptime(value, fmt)
            return parsed.strftime("%Y-%m-%d %H:%M:%S")
        except ValueError:
            continue
    return value


def controller_identity() -> dict[str, str]:
    return {
        "hostname": socket.gethostname(),
        "user": os.environ.get("USERNAME", "unknown"),
    }


def output_path(config: dict[str, Any], category: str, base_name: str, extension: str) -> str:
    output_root = Path(config["output_root"]) / category
    output_root.mkdir(parents=True, exist_ok=True)
    return str(output_root / f"{base_name}-{now_timestamp()}.{extension}")


def work_config_path(config: dict[str, Any], base_name: str) -> str:
    work_root = Path(config["configs_root"])
    work_root.mkdir(parents=True, exist_ok=True)
    return str(work_root / f"{base_name}-{now_timestamp()}.csv")


def load_csv(path: str | Path) -> list[dict[str, str]]:
    csv_path = Path(path)
    if not csv_path.exists():
        return []
    with csv_path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        return [dict(row) for row in reader]


def load_json(path: str | Path) -> Any:
    json_path = Path(path)
    if not json_path.exists():
        return None
    with json_path.open("r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def write_csv(path: str | Path, fieldnames: list[str], rows: list[dict[str, Any]]) -> None:
    csv_path = Path(path)
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def latest_matching_file(root: str | Path, pattern: str) -> str | None:
    matches = list(Path(root).glob(pattern))
    if not matches:
        return None
    newest = max(matches, key=lambda item: item.stat().st_mtime)
    return str(newest)


def latest_matching_file_patterns(root: str | Path, patterns: list[str]) -> str | None:
    matches: list[Path] = []
    root_path = Path(root)
    for pattern in patterns:
        matches.extend(root_path.glob(pattern))
    if not matches:
        return None
    newest = max(matches, key=lambda item: item.stat().st_mtime)
    return str(newest)


def latest_artifacts(config: dict[str, Any]) -> dict[str, str | None]:
    output_root = Path(config["output_root"])
    return {
        "remoting_csv": latest_matching_file_patterns(
            output_root / "csv",
            ["test-remoting-summary-*.csv", "gui-test-remoting-summary-*.csv"],
        ),
        "discovery_csv": latest_matching_file_patterns(
            output_root / "csv",
            ["be200-discovery-*.csv", "gui-be200-discovery-*.csv"],
        ),
        "discovery_json": latest_matching_file_patterns(
            output_root / "json",
            ["be200-discovery-*.json", "gui-be200-discovery-*.json"],
        ),
        "discovery_transcript": latest_matching_file_patterns(
            output_root / "transcripts",
            ["discover-be200-advanced-properties-*.log", "gui-discover-be200-advanced-properties-*.log"],
        ),
        "template_csv": latest_matching_file_patterns(
            output_root / "csv",
            ["be200-config-template-*.csv", "gui-be200-config-template-*.csv"],
        ),
        "validation_report_csv": latest_matching_file_patterns(
            output_root / "csv",
            ["be200-validation-report-*.csv", "gui-be200-validation-report-*.csv"],
        ),
        "validated_config_csv": latest_matching_file_patterns(
            output_root / "csv",
            ["be200-validated-config-*.csv", "gui-be200-validated-config-*.csv"],
        ),
        "apply_results_csv": latest_matching_file_patterns(
            output_root / "csv",
            ["be200-apply-results-*.csv", "gui-be200-apply-results-*.csv"],
        ),
        "apply_results_json": latest_matching_file_patterns(
            output_root / "json",
            ["be200-apply-results-*.json", "gui-be200-apply-results-*.json"],
        ),
        "rollback_csv": latest_matching_file_patterns(
            output_root / "csv",
            ["be200-rollback-data-*.csv", "gui-be200-rollback-data-*.csv"],
        ),
        "rollback_json": latest_matching_file_patterns(
            output_root / "json",
            ["be200-rollback-data-*.json", "gui-be200-rollback-data-*.json"],
        ),
        "property_matrix_csv": latest_matching_file_patterns(
            output_root / "csv",
            ["be200-property-matrix-*.csv", "gui-be200-property-matrix-*.csv"],
        ),
        "property_matrix_json": latest_matching_file_patterns(
            output_root / "json",
            ["be200-property-matrix-*.json", "gui-be200-property-matrix-*.json"],
        ),
    }


def load_history_index(config: dict[str, Any]) -> list[dict[str, Any]]:
    history_index = Path(config["history_index"])
    with history_index.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def save_job(config: dict[str, Any], job: dict[str, Any]) -> None:
    jobs_root = Path(config["jobs_root"])
    jobs_root.mkdir(parents=True, exist_ok=True)

    detail_path = jobs_root / f"{job['id']}.json"
    with detail_path.open("w", encoding="utf-8") as handle:
        json.dump(job, handle, indent=2)

    history = load_history_index(config)
    history = [entry for entry in history if entry["id"] != job["id"]]
    history.insert(
        0,
        {
            "id": job["id"],
            "job_type": job["job_type"],
            "title": job["title"],
            "status": job["status"],
            "started_at": job["started_at"],
            "finished_at": job.get("finished_at"),
            "summary": job.get("summary", {}),
        },
    )
    with Path(config["history_index"]).open("w", encoding="utf-8") as handle:
        json.dump(history, handle, indent=2)


def get_job(config: dict[str, Any], job_id: str) -> dict[str, Any] | None:
    path = Path(config["jobs_root"]) / f"{job_id}.json"
    if not path.exists():
        return None
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def get_history(config: dict[str, Any], limit: int | None = None) -> list[dict[str, Any]]:
    history = load_history_index(config)
    if limit is None:
        return history
    return history[:limit]


def flatten_artifact_paths(job: dict[str, Any]) -> list[str]:
    paths = []
    for value in job.get("artifacts", {}).values():
        if value:
            paths.append(value)
    return paths


def powershell_command(script_path: str, arguments: list[str]) -> list[str]:
    return [
        "powershell.exe",
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        script_path,
        *arguments,
    ]


def redact_command(command: list[str]) -> list[str]:
    redacted = list(command)
    for index, token in enumerate(redacted[:-1]):
        if token in ("-Password", "-WiFiPassword"):
            redacted[index + 1] = "********"
    return redacted


def gui_subprocess_env() -> dict[str, str]:
    env = dict(os.environ)
    env["BE200_NONINTERACTIVE"] = "1"
    env["BE200_GUI"] = "1"
    return env




def summarize_restart_rdp_rows(rows: list[dict[str, str]]) -> str:
    if not rows:
        return "(no rows)"
    ping_yes = sum(1 for r in rows if str(r.get("PingReachable", "")).lower() == "yes")
    rdp_launch = sum(1 for r in rows if str(r.get("RdpLaunched", "")).lower() == "yes")
    rdp_port_yes = sum(1 for r in rows if str(r.get("RdpPortOpen", "")).lower() == "yes")
    lines = [
        f"Targets in report: {len(rows)}",
        f"Ping recovered (Yes): {ping_yes}",
        f"RDP port open (Yes, when checked): {rdp_port_yes}",
        f"RDP mstsc launched (Yes): {rdp_launch}",
    ]
    return "\n".join(lines)


def validate_restart_rdp_targets(
    selected: list[str],
    allowed: list[str],
    forbidden_controller: str,
) -> tuple[list[str] | None, str | None]:
    cleaned = [t.strip() for t in selected if t and str(t).strip()]
    if not cleaned:
        return None, "Select at least one target."
    seen: set[str] = set()
    ordered: list[str] = []
    for t in cleaned:
        if t in seen:
            continue
        seen.add(t)
        if t == forbidden_controller:
            return None, f"Controller address {forbidden_controller} must never be targeted."
        if t not in allowed:
            return None, f"Target {t} is outside the allowed fleet scope."
        ordered.append(t)
    return ordered, None


def run_restart_rdp_job(
    config: dict[str, Any],
    targets: list[str],
    username: str,
    password: str,
    *,
    ping_timeout_seconds: int,
    check_rdp_port: bool,
    auto_open_rdp: bool,
    rdp_delay_seconds: int,
) -> dict[str, Any]:
    csv_path = output_path(config, "csv", "gui-restart-rdp-results", "csv")
    transcript_path = output_path(config, "transcripts", "gui-orchestrate-restart-rdp", "log")
    arguments = [
        "-TargetIP",
        ",".join(targets),
        "-Username",
        username,
        "-Password",
        password,
        "-CsvPath",
        csv_path,
        "-TranscriptPath",
        transcript_path,
        "-PingTimeoutSeconds",
        str(ping_timeout_seconds),
        "-RdpDelaySeconds",
        str(rdp_delay_seconds),
    ]
    if check_rdp_port:
        arguments.append("-CheckRdpPort")
    if auto_open_rdp:
        arguments.append("-AutoOpenRdp")
    timeout = int(config["defaults"].get("restart_rdp_timeout_seconds", 7200))
    summary = {
        "targets": targets,
        "ping_timeout_seconds": ping_timeout_seconds,
        "check_rdp_port": check_rdp_port,
        "auto_open_rdp": auto_open_rdp,
    }
    return run_script_job(
        config,
        "restart_rdp",
        "Fleet OS restart, ping recovery, optional RDP",
        "orchestrate-restart-rdp.ps1",
        arguments,
        {"csv": csv_path, "transcript": transcript_path},
        summary,
        timeout_seconds=timeout,
    )


def launch_mstsc_sequence(ips: list[str], delay_seconds: float = 3.0) -> None:
    import time

    system_root = os.environ.get("SystemRoot", r"C:\Windows")
    mstsc = Path(system_root) / "System32" / "mstsc.exe"
    if not mstsc.is_file():
        raise FileNotFoundError(str(mstsc))
    for ip in ips:
        subprocess.Popen([str(mstsc), f"/v:{ip}"], cwd=system_root, env=gui_subprocess_env())
        if delay_seconds > 0:
            time.sleep(delay_seconds)

def run_script_job(
    config: dict[str, Any],
    job_type: str,
    title: str,
    script_name: str,
    arguments: list[str],
    artifacts: dict[str, str | None],
    summary: dict[str, Any] | None = None,
    timeout_seconds: int | None = None,
) -> dict[str, Any]:
    toolkit_root = Path(config["toolkit_root"])
    script_path = str(toolkit_root / script_name)
    job_id = f"{job_type}-{now_timestamp()}"
    command = powershell_command(script_path, arguments)
    display_command = redact_command(command)
    started_at = datetime.now().isoformat(timespec="seconds")
    timeout = int(timeout_seconds) if timeout_seconds is not None else int(config["defaults"]["run_timeout_seconds"])
    env = gui_subprocess_env()

    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        cwd=str(toolkit_root),
        timeout=timeout,
        encoding="utf-8",
        errors="replace",
        env=env,
    )
    launch_log = json.dumps(
        {
            "argv": display_command,
            "env_flags": {
                "BE200_NONINTERACTIVE": env["BE200_NONINTERACTIVE"],
                "BE200_GUI": env["BE200_GUI"],
            },
        }
    )
    stdout = f"GUI launch argv: {launch_log}\n\n{result.stdout}"

    job = {
        "id": job_id,
        "job_type": job_type,
        "title": title,
        "status": "success" if result.returncode == 0 else "failed",
        "started_at": started_at,
        "finished_at": datetime.now().isoformat(timespec="seconds"),
        "returncode": result.returncode,
        "command": display_command,
        "stdout": stdout,
        "stderr": result.stderr,
        "artifacts": artifacts,
        "summary": summary or {},
    }
    save_job(config, job)
    return job


def target_argument_list(targets: list[str], config: dict[str, Any]) -> list[str]:
    allowed = config["allowed_targets"]
    if sorted(targets) == sorted(allowed):
        return []
    if not targets:
        return []
    return ["-TargetIP", ",".join(targets)]


def run_remoting_test(config: dict[str, Any], username: str, password: str, targets: list[str]) -> dict[str, Any]:
    csv_path = output_path(config, "csv", "gui-test-remoting-summary", "csv")
    arguments = target_argument_list(targets, config)
    arguments += ["-Username", username, "-Password", password, "-CsvPath", csv_path]
    return run_script_job(
        config,
        "remoting",
        "Run remoting test",
        "test-remoting.ps1",
        arguments,
        {"csv": csv_path},
        {"targets": targets},
    )


def run_discovery_refresh(config: dict[str, Any], username: str, password: str) -> dict[str, Any]:
    csv_path = output_path(config, "csv", "gui-be200-discovery", "csv")
    json_path = output_path(config, "json", "gui-be200-discovery", "json")
    transcript_path = output_path(config, "transcripts", "gui-discover-be200-advanced-properties", "log")
    arguments = [
        "-Username",
        username,
        "-Password",
        password,
        "-CsvPath",
        csv_path,
        "-JsonPath",
        json_path,
        "-TranscriptPath",
        transcript_path,
    ]
    job = run_script_job(
        config,
        "discovery",
        "Refresh discovery inventory",
        "discover-be200-advanced-properties.ps1",
        arguments,
        {"csv": csv_path, "json": json_path, "transcript": transcript_path},
    )

    if job["status"] == "success":
        template_path = output_path(config, "csv", "gui-be200-config-template", "csv")
        template_job = run_script_job(
            config,
            "template",
            "Export template from refreshed discovery",
            "export-be200-config-template.ps1",
            ["-DiscoveryPath", csv_path, "-TemplatePath", template_path],
            {"template_csv": template_path, "discovery_csv": csv_path},
        )
        matrix_artifacts = generate_property_matrix_artifacts(config, csv_path)
        job["template_job_id"] = template_job["id"]
        job["artifacts"]["template_csv"] = template_path
        job["artifacts"]["property_matrix_csv"] = matrix_artifacts["csv"]
        job["artifacts"]["property_matrix_json"] = matrix_artifacts["json"]
        job["summary"] = {
            "targets": len(config["allowed_targets"]),
            "property_total": matrix_artifacts["summary"]["total"],
            "live_tested": matrix_artifacts["summary"]["live_tested"],
            "validation_only": matrix_artifacts["summary"]["validation_only"],
            "deferred": matrix_artifacts["summary"]["deferred"],
        }
        save_job(config, job)
    return job


def run_validate_job(
    config: dict[str, Any],
    config_path: str,
    discovery_path: str,
    summary: dict[str, Any],
) -> dict[str, Any]:
    report_path = output_path(config, "csv", "gui-be200-validation-report", "csv")
    validated_path = output_path(config, "csv", "gui-be200-validated-config", "csv")
    arguments = [
        "-ConfigPath",
        config_path,
        "-DiscoveryPath",
        discovery_path,
        "-ValidationReportPath",
        report_path,
        "-ValidatedConfigPath",
        validated_path,
    ]
    return run_script_job(
        config,
        "validation",
        "Validate generated config",
        "validate-be200-config.ps1",
        arguments,
        {
            "config_csv": config_path,
            "discovery_csv": discovery_path,
            "validation_report_csv": report_path,
            "validated_config_csv": validated_path,
        },
        summary,
    )


def run_apply_job(
    config: dict[str, Any],
    validated_config_path: str,
    mode: str,
    username: str,
    password: str,
    summary: dict[str, Any],
) -> dict[str, Any]:
    result_csv = output_path(config, "csv", "gui-be200-apply-results", "csv")
    result_json = output_path(config, "json", "gui-be200-apply-results", "json")
    rollback_csv = output_path(config, "csv", "gui-be200-rollback-data", "csv")
    rollback_json = output_path(config, "json", "gui-be200-rollback-data", "json")
    transcript = output_path(config, "transcripts", "gui-apply-be200-config", "log")
    arguments = [
        "-ValidatedConfigPath",
        validated_config_path,
        "-Mode",
        mode,
        "-Username",
        username,
        "-Password",
        password,
        "-ResultCsvPath",
        result_csv,
        "-ResultJsonPath",
        result_json,
        "-RollbackCsvPath",
        rollback_csv,
        "-RollbackJsonPath",
        rollback_json,
        "-TranscriptPath",
        transcript,
    ]
    return run_script_job(
        config,
        "apply",
        f"Apply validated config ({mode})",
        "apply-be200-config.ps1",
        arguments,
        {
            "validated_config_csv": validated_config_path,
            "result_csv": result_csv,
            "result_json": result_json,
            "rollback_csv": rollback_csv,
            "rollback_json": rollback_json,
            "transcript": transcript,
        },
        summary,
    )


def run_action_job(
    config: dict[str, Any],
    action: str,
    username: str,
    password: str,
    targets: list[str],
    force: bool = False,
) -> dict[str, Any]:
    csv_path = output_path(config, "csv", f"gui-be200-action-{action.lower()}", "csv")
    transcript = output_path(config, "transcripts", f"gui-invoke-be200-action-{action.lower()}", "log")
    arguments = ["-Action", action]
    arguments += target_argument_list(targets, config)
    arguments += [
        "-Username",
        username,
        "-Password",
        password,
        "-CsvPath",
        csv_path,
        "-TranscriptPath",
        transcript,
    ]
    if force:
        arguments.append("-Force")

    return run_script_job(
        config,
        "action",
        f"Run BE200 action ({action})",
        "invoke-be200-action.ps1",
        arguments,
        {"csv": csv_path, "transcript": transcript},
        {"targets": targets, "action": action},
    )


def run_wifi_job(
    config: dict[str, Any],
    action: str,
    ssid: str,
    wifi_password: str,
    username: str,
    password: str,
    targets: list[str],
) -> dict[str, Any]:
    csv_path = output_path(config, "csv", f"gui-be200-wifi-{action.lower()}", "csv")
    transcript = output_path(config, "transcripts", f"gui-invoke-be200-wifi-{action.lower()}", "log")
    arguments = ["-Action", action]
    arguments += target_argument_list(targets, config)
    arguments += ["-Username", username, "-Password", password]
    if ssid:
        arguments += ["-SSID", ssid]
    if wifi_password:
        arguments += ["-WiFiPassword", wifi_password]
    arguments += ["-CsvPath", csv_path, "-TranscriptPath", transcript]

    return run_script_job(
        config,
        "wifi",
        f"Run BE200 Wi-Fi ({action})",
        "invoke-be200-wifi.ps1",
        arguments,
        {"csv": csv_path, "transcript": transcript},
        {"targets": targets, "action": action, "ssid": ssid or ""},
    )


def summarize_wifi_results(rows: list[dict[str, Any]]) -> dict[str, Any]:
    total = len(rows)
    connected = sum(1 for r in rows if str(r.get("State", "")).lower() == "connected")
    success = sum(1 for r in rows if str(r.get("Success", "")).lower() == "true")
    return {
        "total": total,
        "connected": connected,
        "disconnected": total - connected,
        "success": success,
        "failed": total - success,
    }


def discovery_rows(config: dict[str, Any], discovery_path: str | None = None) -> list[dict[str, Any]]:
    path = discovery_path or latest_artifacts(config)["discovery_csv"]
    if not path:
        return []
    return load_csv(path)


def remoting_rows(config: dict[str, Any], remoting_path: str | None = None) -> list[dict[str, Any]]:
    path = remoting_path or latest_artifacts(config)["remoting_csv"]
    if not path:
        return []
    return load_csv(path)


def property_policy(config: dict[str, Any], registry_keyword: str, display_name: str) -> dict[str, Any]:
    overrides = config.get("property_policy_overrides", {})
    override = overrides.get(registry_keyword, {})
    classification = override.get("classification")
    risk = override.get("risk")
    accepted_modes = list(override.get("accepted_modes", []))
    accepted_rollout_scope = override.get("accepted_rollout_scope", "").strip()
    rationale = override.get("rationale", "").strip()

    if not classification:
        if not display_name:
            classification = "deferred"
            risk = risk or "high"
            rationale = rationale or "Registry-only or informational property without a stable operator-facing label."
        elif registry_keyword.startswith("*"):
            classification = "deferred"
            risk = risk or "high"
            rationale = rationale or "Driver, WoWLAN, or offload-oriented property deferred from operator apply scope."
        else:
            classification = "validation-only"
            risk = risk or "medium"
            rationale = rationale or "Operator-facing property is discovery-backed, but live apply has not been accepted in this pass."

    if not risk:
        risk = "medium"

    if not accepted_rollout_scope:
        accepted_rollout_scope = (
            "All 8 allowlisted targets (192.168.22.221-228)"
            if classification == "live-tested"
            else "No accepted live rollout scope"
        )

    blocked_modes = [mode for mode in ("WriteOnly", "RestartBE200") if mode not in accepted_modes]

    return {
        "classification": classification,
        "risk": risk,
        "accepted_modes": accepted_modes,
        "blocked_modes": blocked_modes,
        "accepted_rollout_scope": accepted_rollout_scope,
        "apply_allowed": classification == "live-tested",
        "rationale": rationale,
    }


def action_policy(config: dict[str, Any], action: str) -> dict[str, Any]:
    overrides = config.get("action_policy_overrides", {})
    override = overrides.get(action, {})
    accepted_targets = list(override.get("accepted_targets", []))
    all_targets = list(config.get("allowed_targets", []))
    return {
        "accepted": bool(override.get("accepted", action in {"Status", "Restart"})),
        "max_targets": int(override.get("max_targets", 1)),
        "accepted_targets": accepted_targets,
        "blocked_targets": [target for target in all_targets if accepted_targets and target not in accepted_targets],
        "confirmation_required": bool(override.get("confirmation_required", action != "Status")),
        "rationale": override.get("rationale", "").strip(),
    }


def current_settings_matrix(
    config: dict[str, Any],
    rows: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    targets = config.get("allowed_targets", [])
    overrides = config.get("property_policy_overrides", {})
    accepted_keywords = {kw for kw, ov in overrides.items() if ov.get("classification") == "live-tested"}

    groups: dict[str, dict[str, Any]] = {}
    for row in rows:
        keyword = (row.get("RegistryKeyword") or "").strip()
        display = (row.get("PropertyDisplayName") or "").strip()
        if not keyword or keyword not in accepted_keywords:
            continue
        tip = row.get("TargetIP", "")
        value = (row.get("CurrentDisplayValue") or row.get("RegistryValue") or "").strip()
        key = keyword
        if key not in groups:
            groups[key] = {"label": display or keyword, "registry_keyword": keyword, "target_values": {}}
        if tip and value:
            groups[key]["target_values"][tip] = value

    result = []
    for key in sorted(groups, key=lambda k: groups[k]["label"].lower()):
        g = groups[key]
        vals = g["target_values"]
        present_values = set(vals.values())
        uniform = len(present_values) == 1 and len(vals) == len(targets)
        common_value = next(iter(present_values)) if uniform else None
        result.append({
            "label": g["label"],
            "registry_keyword": g["registry_keyword"],
            "target_values": vals,
            "uniform": uniform,
            "common_value": common_value,
        })
    return result


def classification_sort_key(classification: str) -> int:
    order = {"live-tested": 0, "validation-only": 1, "deferred": 2}
    return order.get(classification, 99)


def inventory_summary(config: dict[str, Any], rows: list[dict[str, Any]]) -> dict[str, Any]:
    per_target: dict[str, dict[str, Any]] = {
        target: {
            "target_ip": target,
            "computer_name": "",
            "adapter_name": "",
            "interface_description": "",
            "driver_version": "",
            "driver_date": "",
            "property_count": 0,
            "registry_keywords": set(),
            "missing_keywords": set(),
            "variant": False,
        }
        for target in config["allowed_targets"]
    }

    property_counts = Counter()
    coverage: dict[str, set[str]] = defaultdict(set)

    for row in rows:
        target = row.get("TargetIP", "")
        if target not in per_target:
            continue
        target_info = per_target[target]
        target_info["computer_name"] = row.get("ComputerName", "")
        target_info["adapter_name"] = target_info["adapter_name"] or row.get("AdapterName", "")
        target_info["interface_description"] = target_info["interface_description"] or row.get("InterfaceDescription", "")
        target_info["property_count"] += 1
        keyword = row.get("RegistryKeyword") or row.get("PropertyDisplayName") or ""
        if keyword == "DriverVersion" and not target_info["driver_version"]:
            target_info["driver_version"] = (row.get("RegistryValue") or "").strip()
        if keyword == "DriverDate" and not target_info["driver_date"]:
            target_info["driver_date"] = (row.get("RegistryValue") or "").strip()
        if keyword:
            target_info["registry_keywords"].add(keyword)
            coverage[keyword].add(target)
            property_counts[keyword] += 1

    majority_keywords = {
        keyword
        for keyword, count in property_counts.items()
        if count >= max(2, len(config["allowed_targets"]) // 2)
    }

    for target_info in per_target.values():
        target_info["missing_keywords"] = sorted(majority_keywords - target_info["registry_keywords"])
        target_info["variant"] = len(target_info["missing_keywords"]) > 0 or target_info["property_count"] == 0
        target_info["missing_count"] = len(target_info["missing_keywords"])
        target_info["registry_keywords"] = sorted(target_info["registry_keywords"])

    variants = [
        target_info
        for target_info in per_target.values()
        if target_info["variant"]
    ]
    return {
        "targets": list(per_target.values()),
        "variants": variants,
        "majority_keywords": sorted(majority_keywords),
    }


def property_catalog(
    rows: list[dict[str, Any]],
    selected_targets: list[str] | None = None,
    config: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    filtered = rows
    if selected_targets:
        selected_set = set(selected_targets)
        filtered = [row for row in rows if row.get("TargetIP") in selected_set]

    groups: dict[str, dict[str, Any]] = {}
    for row in filtered:
        registry_keyword = row.get("RegistryKeyword", "").strip()
        display_name = row.get("PropertyDisplayName", "").strip()
        key = f"{registry_keyword}||{display_name}"
        if key not in groups:
            groups[key] = {
                "key": key,
                "registry_keyword": registry_keyword,
                "property_display_name": display_name,
                "label": display_name or registry_keyword,
                "targets": set(),
                "interface_descriptions": set(),
                "possible_display_values": set(),
                "current_values": set(),
            }
        group = groups[key]
        group["targets"].add(row.get("TargetIP", ""))
        interface_description = (row.get("InterfaceDescription") or "").strip()
        if interface_description:
            group["interface_descriptions"].add(interface_description)
        current_value = (row.get("CurrentDisplayValue") or "").strip()
        if current_value:
            group["current_values"].add(current_value)
        possible_display = (row.get("PossibleDisplayValues") or "").strip()
        if possible_display:
            for item in possible_display.split(";"):
                text = item.strip()
                if text:
                    group["possible_display_values"].add(text)

    catalog = []
    allowed_targets = list(config.get("allowed_targets", [])) if config else []
    for group in groups.values():
        policy = property_policy(
            config or {},
            group["registry_keyword"],
            group["property_display_name"],
        )
        present_targets = sorted(item for item in group["targets"] if item)
        missing_targets = [target for target in allowed_targets if target not in present_targets] if allowed_targets else []
        catalog.append(
            {
                "key": group["key"],
                "registry_keyword": group["registry_keyword"],
                "property_display_name": group["property_display_name"],
                "label": group["label"],
                "coverage": len(present_targets),
                "present_targets": present_targets,
                "missing_targets": missing_targets,
                "interface_descriptions": sorted(group["interface_descriptions"]),
                "operator_visible": bool(group["property_display_name"]),
                "possible_display_values": sorted(group["possible_display_values"]),
                "current_values": sorted(group["current_values"]),
                **policy,
            }
        )
    return sorted(
        catalog,
        key=lambda item: (
            classification_sort_key(item["classification"]),
            item["label"].lower(),
            item["registry_keyword"].lower(),
        ),
    )


def property_selection_details(
    config: dict[str, Any],
    rows: list[dict[str, Any]],
    selected_targets: list[str],
    property_key: str,
) -> dict[str, Any] | None:
    if not property_key:
        return None

    registry_keyword, property_display_name = property_key.split("||", 1)
    selected_set = set(selected_targets)
    matched_rows = [
        row
        for row in rows
        if row.get("TargetIP") in selected_set
        and row.get("RegistryKeyword", "") == registry_keyword
        and (row.get("PropertyDisplayName", "") or "") == property_display_name
    ]
    if not matched_rows and selected_targets:
        policy = property_policy(config, registry_keyword, property_display_name)
        return {
            "property_key": property_key,
            "label": property_display_name or registry_keyword,
            "selected_targets": selected_targets,
            "covered_targets": [],
            "missing_targets": selected_targets,
            "targets_without_values": [],
            "possible_display_values": [],
            "current_values": [],
            **policy,
        }

    covered_targets = sorted({row.get("TargetIP", "") for row in matched_rows if row.get("TargetIP")})
    possible_display_values = sorted(
        {
            item.strip()
            for row in matched_rows
            for item in (row.get("PossibleDisplayValues") or "").split(";")
            if item.strip()
        }
    )
    targets_with_values = {
        row.get("TargetIP", "")
        for row in matched_rows
        if (row.get("PossibleDisplayValues") or "").strip()
    }
    current_values = sorted(
        {
            (row.get("CurrentDisplayValue") or row.get("RegistryValue") or "").strip()
            for row in matched_rows
            if (row.get("CurrentDisplayValue") or row.get("RegistryValue") or "").strip()
        }
    )
    policy = property_policy(config, registry_keyword, property_display_name)
    return {
        "property_key": property_key,
        "label": property_display_name or registry_keyword,
        "selected_targets": selected_targets,
        "covered_targets": covered_targets,
        "missing_targets": [target for target in selected_targets if target not in covered_targets],
        "targets_without_values": [target for target in covered_targets if target not in targets_with_values],
        "possible_display_values": possible_display_values,
        "current_values": current_values,
        **policy,
    }


def summarize_property_catalog(config: dict[str, Any], catalog: list[dict[str, Any]]) -> dict[str, int]:
    all_targets = len(config["allowed_targets"])
    summary = {
        "total": len(catalog),
        "operator_visible": 0,
        "live_tested": 0,
        "validation_only": 0,
        "deferred": 0,
        "common_all_targets": 0,
        "missing_some_targets": 0,
        "mixed_current_values": 0,
    }
    for item in catalog:
        if item.get("operator_visible"):
            summary["operator_visible"] += 1
        classification = item.get("classification")
        if classification == "live-tested":
            summary["live_tested"] += 1
        elif classification == "validation-only":
            summary["validation_only"] += 1
        elif classification == "deferred":
            summary["deferred"] += 1
        if item.get("coverage", 0) == all_targets:
            summary["common_all_targets"] += 1
        if item.get("coverage", 0) < all_targets:
            summary["missing_some_targets"] += 1
        if len(item.get("current_values", [])) > 1:
            summary["mixed_current_values"] += 1
    return summary


def property_matrix_rows(config: dict[str, Any], discovery_path: str) -> list[dict[str, Any]]:
    rows = discovery_rows(config, discovery_path)
    catalog = property_catalog(rows, config=config)
    matrix_rows: list[dict[str, Any]] = []
    allowed_count = len(config["allowed_targets"])
    for item in catalog:
        variant = bool(item["missing_targets"]) or len(item["current_values"]) > 1
        proposed_mode = "; ".join(item["accepted_modes"]) if item["accepted_modes"] else (
            "ValidationOnly" if item["classification"] == "validation-only" else "Deferred"
        )
        if item["classification"] == "live-tested" and item["operator_visible"]:
            targets_used_for_testing = "192.168.22.221; 192.168.22.222; 192.168.22.223; 192.168.22.224; 192.168.22.225; 192.168.22.226; 192.168.22.227; 192.168.22.228"
            readback_result = "Pass"
            rollback_result = "Pass"
            modes_attempted = "; ".join(item["accepted_modes"])
            highest_rollout_scope = item.get("accepted_rollout_scope", "All 8 allowlisted targets (192.168.22.221-228)")
        elif item["classification"] == "validation-only":
            targets_used_for_testing = ""
            readback_result = "Not attempted"
            rollback_result = "Not attempted"
            modes_attempted = "ValidationOnly"
            highest_rollout_scope = "ValidationOnly"
        else:
            targets_used_for_testing = ""
            readback_result = "Not attempted"
            rollback_result = "Not attempted"
            modes_attempted = "Deferred"
            highest_rollout_scope = "Deferred"
        matrix_rows.append(
            {
                "PropertyDisplayName": item["label"],
                "RegistryKeyword": item["registry_keyword"],
                "TargetPresencePattern": (
                    f"present={'; '.join(item['present_targets']) or 'none'}"
                    f" | missing={'; '.join(item['missing_targets']) or 'none'}"
                ),
                "CommonAcrossTargets": "TRUE" if item["coverage"] == allowed_count else "FALSE",
                "VariantAcrossTargets": "TRUE" if variant else "FALSE",
                "DiscoveredValues": "; ".join(item["possible_display_values"]),
                "CurrentValuesAcrossTargets": "; ".join(item["current_values"]),
                "ProposedRiskClass": item["risk"],
                "ProposedTestMode": proposed_mode,
                "ModesAttempted": modes_attempted,
                "TargetsUsedForTesting": targets_used_for_testing,
                "HighestAcceptedRolloutScope": highest_rollout_scope,
                "ReadBackResult": readback_result,
                "RollbackResult": rollback_result,
                "AcceptanceStatus": item["classification"],
                "ExactReason": item["rationale"],
                "Notes": item["rationale"],
                "ApplyAllowed": "TRUE" if item["apply_allowed"] else "FALSE",
                "AcceptedModes": "; ".join(item["accepted_modes"]),
                "OperatorVisible": "TRUE" if item["operator_visible"] else "FALSE",
                "Coverage": item["coverage"],
                "PresentTargets": "; ".join(item["present_targets"]),
                "MissingTargets": "; ".join(item["missing_targets"]),
                "InterfaceDescriptions": "; ".join(item["interface_descriptions"]),
                "CurrentValuesSeen": "; ".join(item["current_values"]),
                "PossibleDisplayValues": "; ".join(item["possible_display_values"]),
            }
        )
    return matrix_rows


def generate_property_matrix_artifacts(config: dict[str, Any], discovery_path: str) -> dict[str, Any]:
    csv_path = output_path(config, "csv", "gui-be200-property-matrix", "csv")
    json_path = output_path(config, "json", "gui-be200-property-matrix", "json")
    matrix_rows = property_matrix_rows(config, discovery_path)
    fieldnames = [
        "PropertyDisplayName",
        "RegistryKeyword",
        "TargetPresencePattern",
        "CommonAcrossTargets",
        "VariantAcrossTargets",
        "DiscoveredValues",
        "CurrentValuesAcrossTargets",
        "ProposedRiskClass",
        "ProposedTestMode",
        "ModesAttempted",
        "TargetsUsedForTesting",
        "HighestAcceptedRolloutScope",
        "ReadBackResult",
        "RollbackResult",
        "AcceptanceStatus",
        "ExactReason",
        "Notes",
        "ApplyAllowed",
        "AcceptedModes",
        "OperatorVisible",
        "Coverage",
        "PresentTargets",
        "MissingTargets",
        "InterfaceDescriptions",
        "CurrentValuesSeen",
        "PossibleDisplayValues",
        "Rationale",
    ]
    write_csv(csv_path, fieldnames, matrix_rows)
    with Path(json_path).open("w", encoding="utf-8") as handle:
        json.dump(matrix_rows, handle, indent=2)
    summary = summarize_property_catalog(
        config,
        property_catalog(discovery_rows(config, discovery_path), config=config),
    )
    return {
        "csv": csv_path,
        "json": json_path,
        "rows": matrix_rows,
        "summary": summary,
    }


def build_config_rows(
    config: dict[str, Any],
    rows: list[dict[str, Any]],
    targets: list[str],
    property_key: str,
    target_value: str,
) -> tuple[list[dict[str, Any]], list[str], dict[str, Any]]:
    registry_keyword, property_display_name = property_key.split("||", 1)
    selected_set = set(targets)
    errors: list[str] = []
    config_rows: list[dict[str, Any]] = []
    preview: dict[str, Any] = {
        "targets": [],
        "registry_keyword": registry_keyword,
        "property_display_name": property_display_name,
        "target_value": target_value,
    }

    for target in config["allowed_targets"]:
        if target not in selected_set:
            continue
        matches = [
            row
            for row in rows
            if row.get("TargetIP") == target
            and (row.get("RegistryKeyword", "") == registry_keyword)
            and ((row.get("PropertyDisplayName", "") or "") == property_display_name)
        ]
        if not matches:
            errors.append(f"{target}: property was not found in the latest discovery snapshot.")
            continue

        match = matches[0]
        current_value = (match.get("CurrentDisplayValue") or match.get("RegistryValue") or "").strip()
        config_rows.append(
            {
                "Scope": "TARGET",
                "TargetIP": target,
                "AdapterMatch": match.get("InterfaceDescription", ""),
                "PropertyDisplayName": property_display_name,
                "RegistryKeyword": registry_keyword,
                "CurrentValue": current_value,
                "TargetValue": target_value,
                "Apply": "TRUE",
                "Notes": "Generated by the local GUI. Uses the validated PowerShell toolkit for execution.",
            }
        )
        preview["targets"].append(
            {
                "target_ip": target,
                "adapter_match": match.get("InterfaceDescription", ""),
                "current_value": current_value,
            }
        )

    return config_rows, errors, preview


def prepare_generated_config(
    config: dict[str, Any],
    discovery_path: str,
    targets: list[str],
    property_key: str,
    target_value: str,
) -> tuple[str | None, list[str], dict[str, Any]]:
    rows = discovery_rows(config, discovery_path)
    config_rows, errors, preview = build_config_rows(config, rows, targets, property_key, target_value)
    if errors:
        return None, errors, preview

    path = work_config_path(config, "gui-generated-config")
    fieldnames = [
        "Scope",
        "TargetIP",
        "AdapterMatch",
        "PropertyDisplayName",
        "RegistryKeyword",
        "CurrentValue",
        "TargetValue",
        "Apply",
        "Notes",
    ]
    write_csv(path, fieldnames, config_rows)
    return path, [], preview


def prepare_multi_property_config(
    config: dict[str, Any],
    discovery_path: str,
    targets: list[str],
    property_entries: list[dict[str, str]],
) -> tuple[str | None, list[str], list[dict[str, Any]]]:
    disc = discovery_rows(config, discovery_path)
    all_config_rows: list[dict[str, Any]] = []
    all_preview_rows: list[dict[str, Any]] = []
    all_errors: list[str] = []

    for entry in property_entries:
        pkey = entry.get("property_key", "")
        pval = entry.get("target_value", "")
        if not pkey or not pval:
            all_errors.append("Each property row must have a property and a target value.")
            continue
        config_rows, errors, preview = build_config_rows(config, disc, targets, pkey, pval)
        all_errors.extend(errors)
        all_config_rows.extend(config_rows)
        registry_keyword, display_name = pkey.split("||", 1)
        for pr in preview.get("targets", []):
            all_preview_rows.append({
                "target_ip": pr["target_ip"],
                "adapter_match": pr["adapter_match"],
                "property_label": display_name or registry_keyword,
                "registry_keyword": registry_keyword,
                "current_value": pr["current_value"],
                "target_value": pval,
            })

    if all_errors:
        return None, all_errors, all_preview_rows

    path = work_config_path(config, "gui-generated-config")
    fieldnames = [
        "Scope",
        "TargetIP",
        "AdapterMatch",
        "PropertyDisplayName",
        "RegistryKeyword",
        "CurrentValue",
        "TargetValue",
        "Apply",
        "Notes",
    ]
    write_csv(path, fieldnames, all_config_rows)
    return path, [], all_preview_rows


def summarize_validation_report(rows: list[dict[str, Any]]) -> dict[str, int]:
    summary = {"Valid": 0, "Skipped": 0, "Invalid": 0}
    for row in rows:
        status = row.get("ValidationStatus")
        if status in summary:
            summary[status] += 1
    return summary


def summarize_apply_results(rows: list[dict[str, Any]]) -> dict[str, int]:
    summary = {
        "rows": len(rows),
        "apply_succeeded": 0,
        "verification_succeeded": 0,
        "restart_succeeded": 0,
    }
    for row in rows:
        if str(row.get("ApplySucceeded", "")).lower() == "true":
            summary["apply_succeeded"] += 1
        if str(row.get("VerificationSucceeded", "")).lower() == "true":
            summary["verification_succeeded"] += 1
        if str(row.get("RestartSucceeded", "")).lower() == "true":
            summary["restart_succeeded"] += 1
    return summary


def summarize_action_results(rows: list[dict[str, Any]]) -> dict[str, int]:
    summary = {
        "rows": len(rows),
        "attempted": 0,
        "succeeded": 0,
        "targets": len({row.get("TargetIP", "") for row in rows if row.get("TargetIP", "")}),
    }
    for row in rows:
        if str(row.get("ActionAttempted", "")).lower() == "true":
            summary["attempted"] += 1
        if str(row.get("ActionSucceeded", "")).lower() == "true":
            summary["succeeded"] += 1
    return summary


def recent_remoting_status(config: dict[str, Any]) -> dict[str, Any]:
    latest = latest_artifacts(config)["remoting_csv"]
    if not latest:
        return {"recent": False, "timestamp": None, "path": None}
    timestamp = parse_timestamp(latest)
    recent = False
    if timestamp:
        for fmt in ("%Y%m%d-%H%M%S-%f", "%Y%m%d-%H%M%S"):
            try:
                recent_time = datetime.strptime(timestamp, fmt)
                recent = recent_time >= (datetime.now() - timedelta(hours=int(config["defaults"]["recent_hours"])))
                break
            except ValueError:
                continue
    return {"recent": recent, "timestamp": timestamp, "path": latest}
