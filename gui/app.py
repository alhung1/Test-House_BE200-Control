from __future__ import annotations

from pathlib import Path

from flask import Flask, flash, redirect, render_template, request, url_for

from services import (
    controller_identity,
    current_settings_matrix,
    discovery_rows,
    ensure_runtime_dirs,
    flatten_artifact_paths,
    get_history,
    get_job,
    inventory_summary,
    latest_artifacts,
    load_app_config,
    load_flask_secret,
    load_csv,
    prepare_generated_config,
    prepare_multi_property_config,
    action_policy,
    property_catalog,
    property_policy,
    property_selection_details,
    recent_remoting_status,
    run_action_job,
    run_apply_job,
    run_discovery_refresh,
    run_remoting_test,
    run_validate_job,
    run_wifi_job,
    summarize_action_results,
    summarize_apply_results,
    summarize_property_catalog,
    summarize_validation_report,
    summarize_wifi_results,
    validate_restart_rdp_targets,
    run_restart_rdp_job,
    summarize_restart_rdp_rows,
    launch_mstsc_sequence,
    run_open_ncpa_job,
    summarize_open_ncpa_rows,
)
from view_models import (
    build_editor_prefill_query,
    build_preflight,
    current_settings_view,
    describe_result_overview,
    discovery_freshness,
    filter_history_items,
    filter_job_rows,
    status_tone,
)


GUI_ROOT = Path(__file__).resolve().parent
CONFIG = load_app_config(GUI_ROOT)
ensure_runtime_dirs(CONFIG)

app = Flask(__name__)
app.secret_key = load_flask_secret(CONFIG)


def current_config() -> dict[str, object]:
    return app.config.get("BE200_CONFIG", CONFIG)


@app.context_processor
def inject_globals() -> dict[str, object]:
    cfg = current_config()
    return {
        "allowed_targets": cfg["allowed_targets"],
        "default_username": cfg["defaults"]["username"],
        "toolkit_root": cfg["toolkit_root"],
        "status_tone": status_tone,
        "describe_result_overview": describe_result_overview,
        "build_editor_prefill_query": build_editor_prefill_query,
    }


def latest_discovery_path() -> str | None:
    return latest_artifacts(current_config())["discovery_csv"]


def job_flash_category(status: str) -> str:
    if status == "success":
        return "success"
    if status == "partial":
        return "warning"
    if status == "failed":
        return "danger"
    return "info"


def build_job_view(job: dict[str, object] | None) -> dict[str, object] | None:
    if not job:
        return None

    cfg = current_config()
    artifacts = job.get("artifacts", {})
    job_type = job.get("job_type")
    context: dict[str, object] = {"job": job, "rows": [], "summary_block": None}

    if job_type == "validation":
        rows = load_csv(artifacts.get("validation_report_csv", ""))
        context["rows"] = rows
        context["summary_block"] = summarize_validation_report(rows)
    elif job_type == "apply":
        rows = load_csv(artifacts.get("result_csv", ""))
        context["rows"] = rows
        context["summary_block"] = summarize_apply_results(rows)
    elif job_type == "discovery":
        rows = discovery_rows(cfg, artifacts.get("csv"))
        context["rows"] = rows[:100]
        context["summary_block"] = inventory_summary(cfg, rows)
    elif job_type == "remoting":
        rows = load_csv(artifacts.get("csv", ""))
        context["rows"] = rows
        context["summary_block"] = {
            "reachable": sum(str(row.get("Reachable", "")).lower() == "true" for row in rows),
            "be200_found": sum(str(row.get("BE200AdapterFound", "")).lower() == "true" for row in rows),
        }
    elif job_type == "action":
        rows = load_csv(artifacts.get("csv", ""))
        context["rows"] = rows
        context["summary_block"] = summarize_action_results(rows)
    elif job_type == "wifi":
        rows = load_csv(artifacts.get("csv", ""))
        context["rows"] = rows
        context["summary_block"] = summarize_wifi_results(rows)
    elif job_type == "restart_rdp":
        rows = load_csv(artifacts.get("csv", ""))
        context["rows"] = rows
        context["summary_block"] = summarize_restart_rdp_rows(rows)
    elif job_type == "open_ncpa":
        rows = load_csv(artifacts.get("csv", ""))
        context["rows"] = rows
        context["summary_block"] = summarize_open_ncpa_rows(rows)
    context["result_overview"] = describe_result_overview(job)
    return context


@app.route("/")
def dashboard() -> str:
    cfg = current_config()
    artifacts = latest_artifacts(cfg)
    discovery_path = artifacts["discovery_csv"]
    discovery = discovery_rows(cfg, discovery_path)
    inventory = inventory_summary(cfg, discovery) if discovery else {"targets": [], "variants": []}
    property_data = property_catalog(discovery, config=cfg) if discovery else []
    history = get_history(cfg, int(cfg["defaults"]["history_limit"]))
    remoting = recent_remoting_status(cfg)
    return render_template(
        "dashboard.html",
        controller=controller_identity(),
        artifacts=artifacts,
        remoting_status=remoting,
        history=history,
        inventory=inventory,
        property_summary=summarize_property_catalog(cfg, property_data) if property_data else None,
        preflight=build_preflight(cfg, artifacts, history, remoting),
    )


@app.route("/inventory", methods=["GET", "POST"])
def inventory() -> str:
    cfg = current_config()
    if request.method == "POST":
        action = request.form.get("action")
        username = request.form.get("username", cfg["defaults"]["username"]).strip()
        password = request.form.get("password", "")

        if not password:
            flash("Password is required to run toolkit actions.", "danger")
            return redirect(url_for("inventory"))

        if action == "refresh_discovery":
            job = run_discovery_refresh(cfg, username, password)
            flash(f"Discovery refresh finished with status: {job['status']}.", job_flash_category(job["status"]))
            return redirect(url_for("job_detail", job_id=job["id"]))

        if action == "run_remoting":
            job = run_remoting_test(cfg, username, password, cfg["allowed_targets"])
            flash(f"Remoting test finished with status: {job['status']}.", job_flash_category(job["status"]))
            return redirect(url_for("job_detail", job_id=job["id"]))

        if action == "run_operational":
            operation = request.form.get("operation", "").strip()
            if not operation:
                operation = request.form.get("operation_mirror", "").strip()
            selected_targets = request.form.getlist("action_targets")
            policy = action_policy(cfg, operation)
            if operation not in {"Status", "Restart", "Disable", "Enable"} or not policy["accepted"]:
                flash(
                    f"Operational action '{operation or '(none)'}' is not accepted. "
                    "Select a valid operation (Status, Restart, Disable, or Enable) and between 1 and 8 targets.",
                    "danger",
                )
                return redirect(url_for("inventory"))
            if len(selected_targets) == 0 or len(selected_targets) > policy["max_targets"]:
                flash(f"Select between 1 and {policy['max_targets']} target(s) for the requested BE200 action.", "danger")
                return redirect(url_for("inventory"))
            if policy["accepted_targets"]:
                disallowed = [target for target in selected_targets if target not in policy["accepted_targets"]]
                if disallowed:
                    allowed = ", ".join(policy["accepted_targets"])
                    flash(f"The selected BE200 action is only accepted for these target(s): {allowed}.", "danger")
                    return redirect(url_for("inventory"))
            if policy["confirmation_required"] and request.form.get("confirm_operational") != "yes":
                flash(f"Explicit confirmation is required before a BE200 {operation} action.", "danger")
                return redirect(url_for("inventory"))

            job = run_action_job(
                cfg,
                operation,
                username,
                password,
                selected_targets,
                force=policy["confirmation_required"],
            )
            flash(f"{operation} action finished with status: {job['status']}.", job_flash_category(job["status"]))
            return redirect(url_for("job_detail", job_id=job["id"]))

    artifacts = latest_artifacts(cfg)
    discovery = discovery_rows(cfg, artifacts["discovery_csv"])
    inventory_data = inventory_summary(cfg, discovery)
    property_data = [item for item in property_catalog(discovery, config=cfg) if item["classification"] == "live-tested"]
    return render_template(
        "inventory.html",
        artifacts=artifacts,
        inventory=inventory_data,
        property_catalog=property_data,
        action_policies={name: action_policy(cfg, name) for name in ("Status", "Restart", "Disable", "Enable")},
        discovery_freshness=discovery_freshness(artifacts["discovery_csv"]),
    )


@app.route("/editor", methods=["GET", "POST"])
def editor() -> str:
    import json as _json

    cfg = current_config()
    artifacts = latest_artifacts(cfg)
    discovery_path = request.values.get("discovery_path") or artifacts["discovery_csv"]
    rows = discovery_rows(cfg, discovery_path)
    selected_targets = request.values.getlist("targets")
    if request.method == "GET" and not selected_targets:
        selected_targets = cfg["allowed_targets"]
    full_catalog = property_catalog(rows, selected_targets, cfg)
    catalog = [item for item in full_catalog if item["classification"] == "live-tested"]
    catalog_by_key = {item["key"]: item for item in catalog}
    validation_view = None
    preview_rows: list[dict[str, object]] = []
    selected_mode = request.values.get("mode", "WriteOnly")
    property_entries_json = request.values.get("property_entries", "[]")
    try:
        property_entries: list[dict[str, str]] = _json.loads(property_entries_json)
    except (ValueError, TypeError):
        property_entries = []
    prefill_property_key = request.values.get("property_key", "").strip()
    if request.method == "GET" and prefill_property_key and not property_entries:
        property_entries = [{"property_key": prefill_property_key, "target_value": ""}]

    if request.method == "POST":
        action = request.form.get("action")

        if action == "validate":
            if not selected_targets:
                flash("Select at least one target before running validation.", "danger")
            elif not property_entries:
                flash("Add at least one property row before running validation.", "danger")
            else:
                entry_labels = []
                entry_keywords = []
                all_accepted_modes: list[set[str]] = []
                all_live_tested = True
                for entry in property_entries:
                    meta = catalog_by_key.get(entry.get("property_key", ""))
                    if meta:
                        entry_labels.append(meta["label"])
                        entry_keywords.append(meta["registry_keyword"])
                        all_accepted_modes.append(set(meta["accepted_modes"]))
                        if meta["classification"] != "live-tested":
                            all_live_tested = False
                    else:
                        entry_labels.append(entry.get("property_key", "(unknown)"))
                        entry_keywords.append("")
                        all_live_tested = False

                if not all_live_tested:
                    flash("All properties in a multi-property run must be live-tested and accepted.", "danger")
                else:
                    common_modes = set.intersection(*all_accepted_modes) if all_accepted_modes else set()
                    if selected_mode not in common_modes:
                        flash(
                            f"Mode '{selected_mode}' is not accepted for all selected properties. "
                            f"Accepted modes common to all: {', '.join(sorted(common_modes)) or 'none'}.",
                            "danger",
                        )
                    else:
                        config_path, errors, preview_rows = prepare_multi_property_config(
                            cfg, discovery_path, selected_targets, property_entries,
                        )
                        if errors:
                            for error in errors:
                                flash(error, "danger")
                        elif config_path:
                            validation_summary = {
                                "targets": selected_targets,
                                "property_count": len(property_entries),
                                "property_labels": entry_labels,
                                "registry_keywords": entry_keywords,
                                "property_label": "; ".join(entry_labels),
                                "registry_keyword": "; ".join(entry_keywords),
                                "mode": selected_mode,
                                "generated_config_path": config_path,
                                "discovery_path": discovery_path,
                                "classification": "live-tested",
                                "apply_allowed": True,
                                "accepted_modes": sorted(common_modes),
                                "blocked_modes": sorted({"WriteOnly", "RestartBE200"} - common_modes),
                                "accepted_rollout_scope": "All 8 allowlisted targets (192.168.22.221-228)",
                            }
                            job = run_validate_job(cfg, config_path, discovery_path, validation_summary)
                            validation_view = build_job_view(job)
                            flash(f"Validation finished with status: {job['status']}.", job_flash_category(job["status"]))

        elif action == "apply":
            if request.form.get("confirm_apply") != "yes":
                flash("Explicit confirmation is required before real apply.", "danger")
            else:
                validation_job_id = request.form.get("validation_job_id", "")
                username = request.form.get("username", cfg["defaults"]["username"]).strip()
                password = request.form.get("password", "")
                if not password:
                    flash("Password is required for apply.", "danger")
                else:
                    validation_job = get_job(cfg, validation_job_id)
                    if not validation_job:
                        flash("Validation job could not be found.", "danger")
                    elif validation_job["status"] != "success":
                        flash("Apply is only allowed after a successful validation.", "danger")
                    elif validation_job.get("summary", {}).get("classification") != "live-tested":
                        flash("Real apply is limited to properties classified as live-tested and accepted.", "danger")
                    elif request.form.get("mode", "WriteOnly") not in validation_job.get("summary", {}).get("accepted_modes", []):
                        flash("Real apply is blocked because the selected mode is outside the accepted scope for the selected properties.", "danger")
                    else:
                        validation_csv = load_csv(validation_job["artifacts"]["validation_report_csv"])
                        validation_counts = summarize_validation_report(validation_csv)
                        if validation_counts["Valid"] == 0:
                            flash("Apply is blocked because validation did not produce any valid rows.", "danger")
                            return redirect(url_for("job_detail", job_id=validation_job_id))
                        if validation_counts["Invalid"] > 0 or validation_counts["Skipped"] > 0:
                            flash(
                                f"Apply is blocked: {validation_counts['Invalid']} invalid and "
                                f"{validation_counts['Skipped']} skipped rows. All rows must be valid.",
                                "danger",
                            )
                            return redirect(url_for("job_detail", job_id=validation_job_id))
                        validated_config_path = validation_job["artifacts"]["validated_config_csv"]
                        apply_summary = dict(validation_job.get("summary", {}))
                        apply_summary["validation_job_id"] = validation_job_id
                        apply_job = run_apply_job(
                            cfg,
                            validated_config_path,
                            request.form.get("mode", "WriteOnly"),
                            username,
                            password,
                            apply_summary,
                        )
                        flash(f"Apply finished with status: {apply_job['status']}.", job_flash_category(apply_job["status"]))
                        return redirect(url_for("job_detail", job_id=apply_job["id"]))

    return render_template(
        "editor.html",
        discovery_path=discovery_path,
        discovery_available=bool(rows),
        property_catalog=catalog,
        selected_targets=selected_targets,
        selected_mode=selected_mode,
        property_entries_json=_json.dumps(property_entries) if property_entries else "[]",
        validation_view=validation_view,
        preview_rows=preview_rows,
        discovery_freshness=discovery_freshness(discovery_path),
    )


@app.route("/current-settings", methods=["GET", "POST"])
def current_settings() -> str:
    cfg = current_config()
    if request.method == "POST":
        action = request.form.get("action")
        username = request.form.get("username", cfg["defaults"]["username"]).strip()
        password = request.form.get("password", "")
        if action == "refresh_discovery" and password:
            job = run_discovery_refresh(cfg, username, password)
            flash(f"Discovery refresh finished with status: {job['status']}.", job_flash_category(job["status"]))
            return redirect(url_for("current_settings"))

    artifacts = latest_artifacts(cfg)
    discovery = discovery_rows(cfg, artifacts["discovery_csv"])
    matrix = current_settings_matrix(cfg, discovery)
    for item in matrix:
        item["all_targets"] = list(cfg["allowed_targets"])
    inv = inventory_summary(cfg, discovery)
    search = request.args.get("search", "").strip()
    mismatched_only = request.args.get("mismatched") == "1"
    sort_mode = request.args.get("sort", "label")
    filtered_matrix = current_settings_view(matrix, search=search, mismatched_only=mismatched_only, sort_mode=sort_mode)
    return render_template(
        "current_settings.html",
        matrix=filtered_matrix,
        total_matrix_count=len(matrix),
        inventory=inv,
        discovery_path=artifacts["discovery_csv"],
        discovery_freshness=discovery_freshness(artifacts["discovery_csv"]),
        matrix_filters={"search": search, "mismatched": mismatched_only, "sort": sort_mode},
    )


@app.route("/wifi-connect", methods=["GET", "POST"])
def wifi_connect() -> str:
    cfg = current_config()
    result_rows: list[dict[str, object]] = []
    summary: dict[str, object] | None = None
    last_ssid = ""
    selected_targets = cfg["allowed_targets"][:]

    if request.method == "POST":
        action = request.form.get("action", "")
        username = request.form.get("username", cfg["defaults"]["username"]).strip()
        password = request.form.get("password", "")
        ssid = request.form.get("ssid", "").strip()
        wifi_password = request.form.get("wifi_password", "")
        selected_targets = request.form.getlist("targets") or cfg["allowed_targets"][:]
        last_ssid = ssid

        if not password:
            flash("WinRM password is required.", "danger")
        elif not selected_targets:
            flash("Select at least one target.", "danger")
        elif not ssid:
            flash("SSID is required.", "danger")
        elif action in ("connect", "verify"):
            wifi_action = "Connect" if action == "connect" else "Verify"
            job = run_wifi_job(
                cfg, wifi_action, ssid,
                wifi_password if action == "connect" else "",
                username, password, selected_targets,
            )
            result_rows = load_csv(job["artifacts"]["csv"])
            summary = summarize_wifi_results(result_rows)
            flash(
                f"Wi-Fi {wifi_action} finished with status: {job['status']}. "
                f"Job ID: {job['id']}",
                job_flash_category(job["status"]),
            )
        else:
            flash("Unknown action.", "danger")

    return render_template(
        "wifi_connect.html",
        selected_targets=selected_targets,
        ssid=last_ssid,
        result_rows=result_rows,
        summary=summary,
    )


@app.route("/wifi-status", methods=["GET", "POST"])
def wifi_status() -> str:
    cfg = current_config()
    status_rows: list[dict[str, object]] = []
    summary: dict[str, object] | None = None

    if request.method == "POST":
        action = request.form.get("action", "")
        username = request.form.get("username", cfg["defaults"]["username"]).strip()
        password = request.form.get("password", "")

        if not password:
            flash("WinRM password is required.", "danger")
        elif action == "check_status":
            job = run_wifi_job(
                cfg, "Status", "", "", username, password,
                cfg["allowed_targets"],
            )
            if job["status"] == "success":
                status_rows = load_csv(job["artifacts"]["csv"])
                summary = summarize_wifi_results(status_rows)
            else:
                flash(
                    f"Wi-Fi status check failed (job {job['id']}). "
                    "Check job detail for errors.",
                    "danger",
                )
        else:
            flash("Unknown action.", "danger")

    return render_template(
        "wifi_status.html",
        status_rows=status_rows,
        summary=summary,
    )




FORBIDDEN_CONTROLLER = "192.168.22.8"


@app.route("/open-ncpa", methods=["GET", "POST"])
def open_ncpa() -> str:
    cfg = current_config()
    delay_sec = int(cfg["defaults"].get("open_ncpa_default_delay_seconds", 3))
    open_mstsc = bool(cfg["defaults"].get("open_ncpa_open_mstsc_default", True))
    selected = cfg["allowed_targets"][:]

    if request.method == "POST":
        action = request.form.get("action", "")
        selected = request.form.getlist("targets")
        open_mstsc = request.form.get("open_mstsc") == "yes"
        try:
            delay_sec = int(request.form.get("delay_seconds", delay_sec))
        except ValueError:
            delay_sec = 3
        delay_sec = max(0, min(120, delay_sec))

        if action == "run":
            username = request.form.get("username", cfg["defaults"]["username"]).strip()
            password = request.form.get("password", "")
            if not password:
                flash("Password is required.", "danger")
            else:
                ordered, err = validate_restart_rdp_targets(selected, cfg["allowed_targets"], FORBIDDEN_CONTROLLER)
                if err:
                    flash(err, "danger")
                else:
                    assert ordered is not None
                    job = run_open_ncpa_job(
                        cfg,
                        ordered,
                        username,
                        password,
                        delay_seconds=delay_sec,
                        open_mstsc=open_mstsc,
                    )
                    flash(
                        f"Open NCPA job finished with status: {job['status']}. Job ID: {job['id']}",
                        job_flash_category(job["status"]),
                    )
                    return redirect(url_for("job_detail", job_id=job["id"]))

    return render_template(
        "open_ncpa.html",
        selected_targets=selected,
        delay_seconds=delay_sec,
        open_mstsc=open_mstsc,
    )


@app.route("/system-restart-rdp", methods=["GET", "POST"])
def system_restart_rdp() -> str:
    cfg = current_config()
    ping_minutes = int(cfg["defaults"].get("restart_rdp_ping_timeout_minutes", 10))
    rdp_delay = int(cfg["defaults"].get("restart_rdp_mstsc_delay_seconds", 3))
    check_port = False
    auto_rdp = False
    selected = cfg["allowed_targets"][:]

    if request.method == "POST":
        action = request.form.get("action", "")
        selected = request.form.getlist("targets")
        check_port = request.form.get("check_rdp_port") == "yes"
        auto_rdp = request.form.get("auto_open_rdp") == "yes"
        try:
            ping_minutes = int(request.form.get("ping_timeout_minutes", ping_minutes))
        except ValueError:
            ping_minutes = 10
        ping_minutes = max(1, min(120, ping_minutes))
        try:
            rdp_delay = int(request.form.get("rdp_delay_seconds", rdp_delay))
        except ValueError:
            rdp_delay = 3
        rdp_delay = max(1, min(60, rdp_delay))

        if action == "run":
            username = request.form.get("username", cfg["defaults"]["username"]).strip()
            password = request.form.get("password", "")

            if not password:
                flash("Password is required.", "danger")
            elif request.form.get("confirm_restart_rdp") != "yes":
                flash("Confirm the OS restart before running this workflow.", "danger")
            else:
                ordered, err = validate_restart_rdp_targets(selected, cfg["allowed_targets"], FORBIDDEN_CONTROLLER)
                if err:
                    flash(err, "danger")
                else:
                    assert ordered is not None
                    job = run_restart_rdp_job(
                        cfg,
                        ordered,
                        username,
                        password,
                        ping_timeout_seconds=ping_minutes * 60,
                        check_rdp_port=check_port,
                        auto_open_rdp=auto_rdp,
                        rdp_delay_seconds=rdp_delay,
                    )
                    flash(
                        f"Restart+RDP job finished with status: {job['status']}. Job ID: {job['id']}",
                        job_flash_category(job["status"]),
                    )
                    return redirect(url_for("job_detail", job_id=job["id"]))

    return render_template(
        "system_restart_rdp.html",
        selected_targets=selected,
        ping_timeout_minutes=ping_minutes,
        rdp_delay_seconds=rdp_delay,
        check_rdp_port=check_port,
        auto_open_rdp=auto_rdp,
    )


@app.route("/jobs/<job_id>/launch-rdp", methods=["POST"])
def restart_rdp_launch(job_id: str) -> str:
    cfg = current_config()
    job = get_job(cfg, job_id)
    if not job or job.get("job_type") != "restart_rdp":
        flash("Job not found or not a Restart+RDP job.", "danger")
        return redirect(url_for("history"))
    rows = load_csv(job.get("artifacts", {}).get("csv", ""))
    ips = [
        str(r.get("TargetIP", "")).strip()
        for r in rows
        if str(r.get("PingReachable", "")).lower() == "yes"
    ]
    ordered, err = validate_restart_rdp_targets(ips, cfg["allowed_targets"], FORBIDDEN_CONTROLLER)
    if err or not ordered:
        flash(err or "No ping-recovered targets to connect.", "warning")
        return redirect(url_for("job_detail", job_id=job_id))
    try:
        delay = float(cfg["defaults"].get("restart_rdp_mstsc_delay_seconds", 3))
        launch_mstsc_sequence(ordered, delay_seconds=delay)
        flash(f"Launched {len(ordered)} RDP session(s) sequentially.", "info")
    except Exception as exc:
        flash(f"RDP launch failed: {exc}", "danger")
    return redirect(url_for("job_detail", job_id=job_id))



@app.route("/history")
def history() -> str:
    cfg = current_config()
    all_history = get_history(cfg, None)
    filters = {
        "status": request.args.get("status", "").strip(),
        "job_type": request.args.get("job_type", "").strip(),
        "search": request.args.get("search", "").strip(),
        "actionable_only": request.args.get("actionable") == "1",
    }
    filtered = filter_history_items(all_history, **filters)
    job_types = sorted({item.get("job_type", "") for item in all_history if item.get("job_type")})
    return render_template(
        "history.html",
        history=filtered,
        total_history_count=len(all_history),
        filters=filters,
        job_types=job_types,
    )


@app.route("/jobs/<job_id>")
def job_detail(job_id: str) -> str:
    cfg = current_config()
    job = get_job(cfg, job_id)
    if not job:
        flash("Job was not found.", "warning")
        return redirect(url_for("history"))
    row_filter = request.args.get("rows", "all")
    view = build_job_view(job)
    row_counts = {"success": 0, "warning": 0, "danger": 0}
    if view and view.get("rows"):
        filtered_rows, row_counts = filter_job_rows(str(view["job"]["job_type"]), list(view["rows"]), row_filter)
        view["rows"] = filtered_rows
    return render_template(
        "job_detail.html",
        view=view,
        artifact_paths=flatten_artifact_paths(job),
        row_filter=row_filter,
        row_counts=row_counts,
    )


if __name__ == "__main__":
    app.run(
        host=CONFIG["app"]["host"],
        port=int(CONFIG["app"]["port"]),
        debug=bool(CONFIG["app"]["debug"]),
    )
