from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any
from urllib.parse import quote


def parse_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    for fmt in (
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%d %H:%M:%S",
        "%Y%m%d-%H%M%S-%f",
        "%Y%m%d-%H%M%S",
    ):
        try:
            return datetime.strptime(value, fmt)
        except ValueError:
            continue
    return None


def format_datetime(value: datetime | None) -> str:
    if not value:
        return "Unknown"
    return value.strftime("%Y-%m-%d %H:%M:%S")


def format_age(value: datetime | None) -> str:
    if not value:
        return "Unknown"
    delta = datetime.now() - value
    seconds = max(int(delta.total_seconds()), 0)
    if seconds < 60:
        return f"{seconds}s ago"
    minutes = seconds // 60
    if minutes < 60:
        return f"{minutes}m ago"
    hours = minutes // 60
    if hours < 48:
        return f"{hours}h ago"
    days = hours // 24
    return f"{days}d ago"


def file_health(
    path: str | None,
    *,
    warning_hours: int = 24,
    stale_hours: int = 72,
) -> dict[str, Any]:
    if not path:
        return {
            "exists": False,
            "path": None,
            "state": "danger",
            "label": "Missing",
            "detail": "No artifact found",
            "modified_at": None,
            "age_text": "Missing",
        }

    target = Path(path)
    if not target.exists():
        return {
            "exists": False,
            "path": str(target),
            "state": "danger",
            "label": "Missing",
            "detail": "Path is recorded but file is missing",
            "modified_at": None,
            "age_text": "Missing",
        }

    modified_at = datetime.fromtimestamp(target.stat().st_mtime)
    age = datetime.now() - modified_at
    if age <= timedelta(hours=warning_hours):
        state = "ok"
        label = "Fresh"
    elif age <= timedelta(hours=stale_hours):
        state = "warning"
        label = "Aging"
    else:
        state = "danger"
        label = "Stale"
    return {
        "exists": True,
        "path": str(target),
        "state": state,
        "label": label,
        "detail": f"Last updated {format_age(modified_at)}",
        "modified_at": modified_at,
        "modified_at_text": format_datetime(modified_at),
        "age_text": format_age(modified_at),
    }


def discovery_freshness(discovery_path: str | None) -> dict[str, Any]:
    snapshot = file_health(discovery_path, warning_hours=24, stale_hours=72)
    snapshot["banner"] = {
        "ok": "Discovery snapshot is fresh enough for validation and comparison.",
        "warning": "Discovery snapshot is older than 24 hours. Review target scope before applying changes.",
        "danger": "Discovery snapshot is stale or missing. Refresh discovery before relying on these values.",
    }.get(snapshot["state"], "Discovery snapshot status is unknown.")
    return snapshot


def status_tone(status: str | None) -> str:
    if status == "success":
        return "success"
    if status == "partial":
        return "warning"
    if status == "failed":
        return "danger"
    return "secondary"


def describe_result_overview(job_or_item: dict[str, Any]) -> str | None:
    summary = job_or_item.get("summary", {})
    overview = summary.get("result_overview", {})
    rows = int(overview.get("rows", 0) or 0)
    if rows:
        if "verified_rows" in overview:
            return f"{overview['verified_rows']}/{rows} verified"
        if "successful_rows" in overview:
            return f"{overview['successful_rows']}/{rows} succeeded"
        if "reachable_be200_rows" in overview:
            return f"{overview['reachable_be200_rows']}/{rows} reachable + BE200"
    if summary.get("action"):
        targets = summary.get("targets", [])
        if isinstance(targets, list):
            return f"{summary['action']} on {len(targets)} target(s)"
        return str(summary["action"])
    if summary.get("property_label"):
        count = int(summary.get("property_count", 1) or 1)
        return f"{count} property set(s)"
    if summary.get("property_total"):
        return f"{summary['property_total']} properties"
    return None


def build_preflight(
    config: dict[str, Any],
    artifacts: dict[str, str | None],
    history: list[dict[str, Any]],
    remoting_status: dict[str, Any],
) -> dict[str, Any]:
    toolkit_root = Path(config["toolkit_root"])
    output_root = Path(config["output_root"])
    history_index = Path(config["history_index"])
    discovery = discovery_freshness(artifacts.get("discovery_csv"))
    remoting = file_health(
        remoting_status.get("path"),
        warning_hours=int(config.get("defaults", {}).get("recent_hours", 24)),
        stale_hours=max(int(config.get("defaults", {}).get("recent_hours", 24)) * 3, 72),
    )
    validation_job = next((item for item in history if item.get("job_type") == "validation"), None)
    apply_job = next((item for item in history if item.get("job_type") == "apply"), None)
    unresolved_jobs = [item for item in history if item.get("status") in {"partial", "failed"}]

    local_issues: list[str] = []
    if not toolkit_root.exists():
        local_issues.append("Toolkit root missing")
    if not output_root.exists():
        local_issues.append("Output root missing")
    elif not os.access(output_root, os.W_OK):
        local_issues.append("Output root not writable")
    if not history_index.exists():
        local_issues.append("History index missing")
    elif not os.access(history_index, os.R_OK):
        local_issues.append("History index unreadable")
    if not sys.executable or not Path(sys.executable).exists():
        local_issues.append("Python runtime unavailable")

    local_state = "ok" if not local_issues else "danger"
    latest_validation = validation_job.get("status", "none") if validation_job else "none"
    latest_apply = apply_job.get("status", "none") if apply_job else "none"

    tiles = [
        {
            "label": "Remoting freshness",
            "value": remoting["label"],
            "detail": remoting["detail"],
            "tone": remoting["state"],
        },
        {
            "label": "Discovery age",
            "value": discovery["label"],
            "detail": discovery["detail"],
            "tone": discovery["state"],
        },
        {
            "label": "Latest validation",
            "value": latest_validation.title() if latest_validation != "none" else "Not run",
            "detail": validation_job.get("started_at", "No validation job yet") if validation_job else "No validation job yet",
            "tone": status_tone(validation_job.get("status")) if validation_job else "secondary",
        },
        {
            "label": "Latest apply",
            "value": latest_apply.title() if latest_apply != "none" else "Not run",
            "detail": apply_job.get("started_at", "No apply job yet") if apply_job else "No apply job yet",
            "tone": status_tone(apply_job.get("status")) if apply_job else "secondary",
        },
        {
            "label": "Unresolved jobs",
            "value": str(len(unresolved_jobs)),
            "detail": "Partial or failed jobs still present in history",
            "tone": "warning" if unresolved_jobs else "ok",
        },
        {
            "label": "GUI local health",
            "value": "Healthy" if not local_issues else "Needs attention",
            "detail": "; ".join(local_issues) if local_issues else f"Python host OK: {sys.executable}",
            "tone": local_state,
        },
    ]

    return {
        "tiles": tiles,
        "discovery": discovery,
        "remoting": remoting,
        "unresolved_jobs": unresolved_jobs[:5],
        "local_issues": local_issues,
    }


def history_search_blob(item: dict[str, Any]) -> str:
    summary = item.get("summary", {})
    fields: list[str] = [
        str(item.get("job_type", "")),
        str(item.get("title", "")),
        str(item.get("status", "")),
    ]
    if isinstance(summary, dict):
        for key, value in summary.items():
            if isinstance(value, list):
                fields.extend(str(part) for part in value)
            else:
                fields.append(str(value))
    return " ".join(fields).lower()


def filter_history_items(
    history: list[dict[str, Any]],
    *,
    status: str = "",
    job_type: str = "",
    search: str = "",
    actionable_only: bool = False,
) -> list[dict[str, Any]]:
    filtered = history
    if actionable_only:
        filtered = [item for item in filtered if item.get("status") in {"partial", "failed"}]
    if status:
        filtered = [item for item in filtered if item.get("status") == status]
    if job_type:
        filtered = [item for item in filtered if item.get("job_type") == job_type]
    if search:
        needle = search.lower()
        filtered = [item for item in filtered if needle in history_search_blob(item)]
    return filtered


def classify_result_row(job_type: str, row: dict[str, Any]) -> str:
    if job_type == "validation":
        state = str(row.get("ValidationStatus", "")).strip().lower()
        if state == "valid":
            return "success"
        if state == "skipped":
            return "warning"
        return "danger"
    if job_type == "apply":
        if str(row.get("ApplySucceeded", "")).lower() != "true":
            return "danger"
        if str(row.get("VerificationSucceeded", "")).lower() != "true":
            return "danger"
        restart = str(row.get("RestartSucceeded", "")).strip()
        if restart and restart.lower() != "true":
            return "warning"
        return "success"
    if job_type == "action":
        if str(row.get("ActionSucceeded", "")).lower() == "true":
            return "success"
        if str(row.get("ActionAttempted", "")).lower() == "true":
            return "danger"
        return "warning"
    if job_type == "wifi":
        if str(row.get("Success", "")).lower() == "true":
            return "success"
        state = str(row.get("State", "")).lower()
        return "danger" if state in {"error", "disabled"} else "warning"
    if job_type == "restart_rdp":
        final_status = str(row.get("FinalStatus", "")).strip().lower()
        if final_status in {"success", "simulated"}:
            return "success"
        if str(row.get("PingReachable", "")).lower() == "yes":
            return "warning"
        return "danger"
    if job_type == "open_ncpa":
        if str(row.get("Success", "")).lower() in {"yes", "true", "simulated"}:
            return "success"
        if str(row.get("NcpaSuccess", "")).lower() in {"yes", "simulated"}:
            return "warning"
        return "danger"
    if job_type == "remoting":
        reachable = str(row.get("Reachable", "")).lower() in {"yes", "true"}
        be200 = str(row.get("BE200AdapterFound", "")).lower() in {"yes", "true"}
        if reachable and be200:
            return "success"
        if reachable:
            return "warning"
        return "danger"
    return "success"


def filter_job_rows(
    job_type: str,
    rows: list[dict[str, Any]],
    row_filter: str,
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    decorated: list[dict[str, Any]] = []
    counts = {"success": 0, "warning": 0, "danger": 0}
    for row in rows:
        state = classify_result_row(job_type, row)
        counts[state] += 1
        decorated.append({**row, "__row_state": state})

    if row_filter == "failures":
        decorated = [row for row in decorated if row["__row_state"] == "danger"]
    elif row_filter == "warnings":
        decorated = [row for row in decorated if row["__row_state"] == "warning"]
    elif row_filter == "success":
        decorated = [row for row in decorated if row["__row_state"] == "success"]
    return decorated, counts


def current_settings_view(
    matrix: list[dict[str, Any]],
    *,
    search: str = "",
    mismatched_only: bool = False,
    sort_mode: str = "label",
) -> list[dict[str, Any]]:
    filtered = list(matrix)
    if mismatched_only:
        filtered = [item for item in filtered if not item.get("uniform")]
    if search:
        needle = search.lower()
        filtered = [
            item
            for item in filtered
            if needle in item.get("label", "").lower()
            or needle in item.get("registry_keyword", "").lower()
            or any(needle in str(value).lower() for value in item.get("target_values", {}).values())
        ]
    for item in filtered:
        values = list(item.get("target_values", {}).values())
        item["variance_count"] = len(set(values))
        item["missing_count"] = max(0, len(item.get("all_targets", [])) - len(item.get("target_values", {})))
    if sort_mode == "variance":
        filtered.sort(key=lambda item: (-int(item["variance_count"]), item["label"].lower()))
    else:
        filtered.sort(key=lambda item: item["label"].lower())
    return filtered


def build_editor_prefill_query(property_key: str, targets: list[str]) -> str:
    payload = json.dumps([{"property_key": property_key, "target_value": ""}])
    query_parts = [f"property_entries={quote(payload)}"]
    query_parts.extend(f"targets={quote(target)}" for target in targets)
    return "&".join(query_parts)
