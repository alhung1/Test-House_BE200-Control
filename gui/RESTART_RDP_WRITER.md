Run once from `gui` folder:

`py -3 -c "import re,pathlib; t=pathlib.Path('RESTART_RDP_WRITER.md').read_text(encoding='utf-8'); exec(re.search(r'```python\n(.*)\n```',t,re.S).group(1))"`

```python
import json
import re
from pathlib import Path

GUI = Path(r"c:\Test House BE200 control\gui").resolve()
ROOT = GUI.parent

PS1 = r'''<#
.SYNOPSIS
  OS restart selected fleet hosts, wait for ping (and optional RDP port), optionally launch mstsc sequentially.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetIP,
    [Parameter(Mandatory = $true)]
    [string]$Username,
    [Parameter(Mandatory = $true)]
    [string]$Password,
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,
    [Parameter(Mandatory = $true)]
    [string]$TranscriptPath,
    [Parameter()][int]$PingTimeoutSeconds = 600,
    [Parameter()][int]$PingIntervalSeconds = 5,
    [Parameter()][int]$PostRestartGraceSeconds = 15,
    [Parameter()][int]$RdpDelaySeconds = 3,
    [Parameter()][string]$ForbiddenControllerIp = '192.168.22.8',
    [switch]$CheckRdpPort,
    [switch]$AutoOpenRdp,
    [switch]$DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'internal\BE200Toolkit.Common.psm1') -Force
if ($env:BE200_NONINTERACTIVE -eq '1') { $ConfirmPreference = 'None' }
$cred = Resolve-BE200Credential -Username $Username -Password $Password
$parts = @($TargetIP -split '[,;|\s]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$ordered = @(Resolve-BE200TargetIPs -TargetIP $parts)
if ($ordered -contains $ForbiddenControllerIp) {
    throw "Refusing to run: controller address $ForbiddenControllerIp must never be targeted."
}
$dir = Split-Path -Path $TranscriptPath -Parent
if ($dir -and -not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
Start-Transcript -Path $TranscriptPath -Force | Out-Null
$rows = New-Object System.Collections.Generic.List[object]
try {
    Write-BE200Section "Orchestrated OS restart + recovery for: $($ordered -join ', ')"
    foreach ($t in $ordered) {
        $row = [ordered]@{
            TargetIP = $t; RestartRequested = 'Yes'; RestartIssued = 'No'; RestartError = ''
            PingReachable = 'No'; RecoverySeconds = ''
            RdpPortOpen = $(if ($CheckRdpPort) { 'Pending' } else { 'Skipped' })
            RdpLaunched = 'No'; FinalStatus = 'Pending'; Message = ''
        }
        if ($DryRun) {
            $row.RestartIssued = 'Simulated'; $row.PingReachable = 'Simulated'; $row.RecoverySeconds = '0'
            $row.RdpPortOpen = if ($CheckRdpPort) { 'Simulated' } else { 'Skipped' }
            $row.RdpLaunched = if ($AutoOpenRdp) { 'Simulated' } else { 'No' }
            $row.FinalStatus = 'Simulated'; $row.Message = 'DryRun: no network actions.'
            [void]$rows.Add([pscustomobject]$row); continue
        }
        $issuedAt = Get-Date
        try {
            Invoke-Command -ComputerName $t -Credential $cred -ScriptBlock {
                Restart-Computer -Force -ErrorAction Stop
            } -ErrorAction Stop
            $row.RestartIssued = 'Yes'
        } catch {
            $row.RestartIssued = 'No'; $row.RestartError = $_.Exception.Message
            $row.PingReachable = 'N/A'; $row.RdpPortOpen = 'N/A'; $row.FinalStatus = 'Failed'
            $row.Message = 'Restart failed; skipped wait/RDP.'
            [void]$rows.Add([pscustomobject]$row); continue
        }
        $row | Add-Member -NotePropertyName '_IssuedAt' -NotePropertyValue $issuedAt -Force
        $row | Add-Member -NotePropertyName '_PingDeadline' -NotePropertyValue ($issuedAt.AddSeconds($PingTimeoutSeconds)) -Force
        [void]$rows.Add([pscustomobject]$row)
        Start-Sleep -Seconds 2
    }
    if (-not $DryRun) {
        $any = @($rows | Where-Object { $_.RestartIssued -eq 'Yes' })
        if ($any.Count -gt 0) {
            Write-BE200Section "Grace period ${PostRestartGraceSeconds}s after restart commands"
            Start-Sleep -Seconds $PostRestartGraceSeconds
        }
        Write-BE200Section 'Ping polling'
        while ($true) {
            $pending = @($rows | Where-Object { $_.RestartIssued -eq 'Yes' -and $_.PingReachable -eq 'No' })
            if ($pending.Count -eq 0) { break }
            $now = Get-Date; $still = $false
            foreach ($r in $pending) {
                if ($now -gt $r._PingDeadline) {
                    $r.PingReachable = 'Timeout'
                    $r.Message = "No ping within ${PingTimeoutSeconds}s."
                    continue
                }
                if (Test-Connection -ComputerName $r.TargetIP -Count 1 -Quiet -TimeoutSeconds 3) {
                    $sec = [int](($now - $r._IssuedAt).TotalSeconds)
                    if ($sec -lt 0) { $sec = 0 }
                    $r.PingReachable = 'Yes'; $r.RecoverySeconds = "$sec"
                } else { $still = $true }
            }
            if (-not $still) { break }
            Start-Sleep -Seconds $PingIntervalSeconds
        }
        foreach ($r in $rows) {
            if ($r.RestartIssued -ne 'Yes') { continue }
            if ($r.PingReachable -eq 'No') {
                $r.PingReachable = 'Timeout'
                if (-not $r.Message) { $r.Message = 'Ping timeout.' }
            }
        }
        if ($CheckRdpPort) {
            foreach ($r in $rows) {
                if ($r.PingReachable -ne 'Yes') {
                    $r.RdpPortOpen = if ($r.PingReachable -in @('N/A', 'Timeout', 'Simulated')) { 'N/A' } else { 'Skipped' }
                    continue
                }
                try {
                    $tn = Test-NetConnection -ComputerName $r.TargetIP -Port 3389 -WarningAction SilentlyContinue -ErrorAction Stop
                    $r.RdpPortOpen = if ($tn.TcpTestSucceeded) { 'Yes' } else { 'No' }
                } catch { $r.RdpPortOpen = 'No' }
            }
        }
        foreach ($r in $rows) {
            if ($r.RestartIssued -eq 'No' -and $r.FinalStatus -eq 'Failed') { continue }
            if ($r.PingReachable -eq 'Yes') {
                $r.FinalStatus = 'Success'
                if (-not $r.Message) { $r.Message = 'Ping recovered.' }
            } else { $r.FinalStatus = 'Partial' }
        }
        $mstsc = Join-Path $env:SystemRoot 'System32\mstsc.exe'
        if ($AutoOpenRdp) {
            foreach ($t in $ordered) {
                $r = $rows | Where-Object { $_.TargetIP -eq $t } | Select-Object -First 1
                if (-not $r -or $r.PingReachable -ne 'Yes') { continue }
                if (-not (Test-Path -LiteralPath $mstsc)) { continue }
                Start-Process -FilePath $mstsc -ArgumentList @('/v', $r.TargetIP) -WindowStyle Normal
                $r.RdpLaunched = 'Yes'
                Start-Sleep -Seconds $RdpDelaySeconds
            }
        } else {
            foreach ($r in $rows) {
                if ($r.PingReachable -eq 'Yes') {
                    $r.Message = ($r.Message + ' Manual: use job Launch RDP or re-run with auto-open.').Trim()
                }
            }
        }
        foreach ($r in $rows) {
            $r.PSObject.Properties.Remove('_IssuedAt')
            $r.PSObject.Properties.Remove('_PingDeadline')
        }
    }
    $rowArray = foreach ($x in $rows) { $x }
    Export-BE200Csv -InputObject $rowArray -Path $CsvPath
} finally { try { Stop-Transcript } catch {} }
$failAll = @($rows | Where-Object { $_.FinalStatus -eq 'Failed' }).Count
if ($failAll -eq $rows.Count -and $rows.Count -gt 0) { exit 1 }
exit 0
'''

(ROOT / "orchestrate-restart-rdp.ps1").write_text(PS1 + "\n", encoding="utf-8")

HTML = """{% extends \"base.html\" %}

{% block title %}Restart + RDP - BE200 Control Console{% endblock %}

{% block content %}
<header class=\"app-page-header\">
  <h1 class=\"app-page-title\">Fleet restart and RDP</h1>
  <p class=\"app-page-lead\">
    <strong>OS restart</strong> on selected hosts (<code>192.168.22.221</code>–<code>228</code> only). Controller
    <code>192.168.22.8</code> is never targeted. After restart, the job waits for <strong>ping</strong> recovery;
    optional TCP 3389 check does not guarantee RDP logon. RDP sessions open from this PC via <code>mstsc</code> (sequential).
  </p>
</header>

<div class=\"card card-be200 zone-risk mb-4\">
  <div class=\"card-header\">Run workflow</div>
  <div class=\"card-body\">
    <form method=\"post\" id=\"restart-rdp-form\">
      <input type=\"hidden\" name=\"action\" value=\"run\">
      <div class=\"mb-3\">
        <label class=\"form-label fw-semibold\">Targets</label>
        <div class=\"mb-1\">
          <button type=\"button\" class=\"btn btn-sm btn-outline-secondary\" id=\"select-all-btn\">Select all</button>
          <button type=\"button\" class=\"btn btn-sm btn-outline-secondary\" id=\"clear-all-btn\">Clear all</button>
        </div>
        <div class=\"target-grid\">
          {% for target in allowed_targets %}
            <div class=\"form-check\">
              <input class=\"form-check-input tgt\" type=\"checkbox\" name=\"targets\" value=\"{{ target }}\" id=\"t-{{ loop.index }}\"
                {% if target in selected_targets %}checked{% endif %}>
              <label class=\"form-check-label\" for=\"t-{{ loop.index }}\">{{ target }}</label>
            </div>
          {% endfor %}
        </div>
      </div>
      <div class=\"row g-3 mb-3\">
        <div class=\"col-md-4\">
          <label class=\"form-label\">Ping timeout (minutes)</label>
          <input class=\"form-control\" type=\"number\" name=\"ping_timeout_minutes\" value=\"{{ ping_timeout_minutes }}\" min=\"1\" max=\"120\">
        </div>
        <div class=\"col-md-4\">
          <label class=\"form-label\">Seconds between RDP launches</label>
          <input class=\"form-control\" type=\"number\" name=\"rdp_delay_seconds\" value=\"{{ rdp_delay_seconds }}\" min=\"1\" max=\"60\">
        </div>
      </div>
      <div class=\"form-check mb-2\">
        <input class=\"form-check-input\" type=\"checkbox\" name=\"check_rdp_port\" value=\"yes\" id=\"chk-rdp\" {% if check_rdp_port %}checked{% endif %}>
        <label class=\"form-check-label\" for=\"chk-rdp\">After ping, test TCP port 3389 (RDP listener — not logon test)</label>
      </div>
      <div class=\"form-check mb-3\">
        <input class=\"form-check-input\" type=\"checkbox\" name=\"auto_open_rdp\" value=\"yes\" id=\"chk-auto\" {% if auto_open_rdp %}checked{% endif %}>
        <label class=\"form-check-label\" for=\"chk-auto\">Automatically open RDP (<code>mstsc</code>) for hosts with ping recovery, in selection order</label>
      </div>
      <div class=\"mb-2\">
        <label class=\"form-label\">Username</label>
        <input class=\"form-control\" type=\"text\" name=\"username\" value=\"{{ default_username }}\">
      </div>
      <div class=\"mb-3\">
        <label class=\"form-label\">Password</label>
        <input class=\"form-control\" type=\"password\" name=\"password\" required>
      </div>
      <div class=\"confirmation-box\">
        <div class=\"form-check mb-0\">
          <input class=\"form-check-input\" type=\"checkbox\" value=\"yes\" name=\"confirm_restart_rdp\" id=\"confirm-r\">
          <label class=\"form-check-label\" for=\"confirm-r\">
            I confirm an <strong>operating system restart</strong> on the selected hosts. I understand brief outages and that success means ping (and optional port) recovery, not guaranteed desktop readiness.
          </label>
        </div>
      </div>
      <button class=\"btn btn-danger mt-3\" type=\"submit\">Start restart + recovery job</button>
    </form>
  </div>
</div>

<p class=\"small text-muted\">Dry-run CLI (no restarts): <code>orchestrate-restart-rdp.ps1 -DryRun ...</code>. Documentation: <code>docs/RESTART_RDP_WORKFLOW.md</code>.</p>

<script>
(() => {
  const boxes = () => Array.from(document.querySelectorAll('.tgt'));
  document.getElementById('select-all-btn').addEventListener('click', () => boxes().forEach(c => c.checked = true));
  document.getElementById('clear-all-btn').addEventListener('click', () => boxes().forEach(c => c.checked = false));
  document.getElementById('restart-rdp-form').addEventListener('submit', (e) => {
    if (!boxes().some(c => c.checked)) { e.preventDefault(); alert('Select at least one target.'); return; }
    if (!document.getElementById('confirm-r').checked) { e.preventDefault(); alert('Confirm the restart to proceed.'); return; }
  });
})();
</script>
{% endblock %}
"""
(GUI / "templates" / "system_restart_rdp.html").write_text(HTML, encoding="utf-8")

DOC = """# Restart + RDP workflow

## Route

- GUI path: `/system-restart-rdp`
- Nav: **System** → **Restart + RDP**

## Accepted scope

- **In scope:** `192.168.22.221`–`192.168.22.228` only (same allowlist as the rest of the console).
- **Never targeted:** `192.168.22.8` (controller). Requests including it are rejected in the GUI and in `orchestrate-restart-rdp.ps1`.

## What it does

1. **OS restart:** WinRM `Invoke-Command` runs `Restart-Computer -Force` on each selected host (sequential issuance, 2 s apart).
2. **Wait:** Grace period (default 15 s), then **ICMP ping** until each host responds or per-host timeout (default 10 minutes).
3. **Optional:** TCP **3389** check via `Test-NetConnection` when enabled — confirms a listener, **not** successful RDP authentication.
4. **RDP:** If **Automatically open RDP** is checked, `mstsc.exe /v:<ip>` runs **in order of target selection**, with a delay between launches. Otherwise use **Launch RDP** on the job detail page for ping-recovered hosts.

## Success meaning

- **Ping recovered:** Host answered ICMP within the timeout (firewall may still block RDP).
- **RDP port Yes:** TCP connect to 3389 succeeded (optional).
- **RDP launched:** `mstsc` was started from the controller session (automatic or manual from job detail).

Partial success is normal if some hosts fail restart or miss the ping window.

## Artifacts

- CSV result grid and PowerShell transcript paths are stored on the job record (see **Job detail**).

## Caveats

- Ping can return before services (including RDP) are fully ready.
- `mstsc` runs **on the machine where the Flask GUI process runs** (typically `192.168.22.8`); it does not run inside remote sessions.
- Long runs may require `restart_rdp_timeout_seconds` in `gui/config.json` (default 7200).
"""
(ROOT / "docs").mkdir(exist_ok=True)
(ROOT / "docs" / "RESTART_RDP_WORKFLOW.md").write_text(DOC, encoding="utf-8")

# --- Patch services.py ---
svc = (GUI / "services.py").read_text(encoding="utf-8")
if "timeout_seconds: int | None = None" not in svc:
    svc = svc.replace(
        "    summary: dict[str, Any] | None = None,\n) -> dict[str, Any]:",
        "    summary: dict[str, Any] | None = None,\n    timeout_seconds: int | None = None,\n) -> dict[str, Any]:",
        1,
    )
    svc = svc.replace(
        "    timeout = int(config[\"defaults\"][\"run_timeout_seconds\"])",
        "    timeout = int(timeout_seconds) if timeout_seconds is not None else int(config[\"defaults\"][\"run_timeout_seconds\"])",
        1,
    )
if "def summarize_restart_rdp_rows" not in svc:
    insert_after = "def run_script_job(\n"
    idx = svc.find(insert_after)
    if idx == -1:
        raise SystemExit("services.py: run_script_job not found")
    new_funcs = '''

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
    return "\\n".join(lines)


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

    system_root = os.environ.get("SystemRoot", r"C:\\Windows")
    mstsc = Path(system_root) / "System32" / "mstsc.exe"
    if not mstsc.is_file():
        raise FileNotFoundError(str(mstsc))
    for ip in ips:
        subprocess.Popen([str(mstsc), f"/v:{ip}"], cwd=system_root, env=gui_subprocess_env())
        if delay_seconds > 0:
            time.sleep(delay_seconds)

'''
    svc = svc.replace(insert_after, new_funcs + insert_after, 1)

(GUI / "services.py").write_text(svc, encoding="utf-8")

# --- Patch app.py ---
app_py = (GUI / "app.py").read_text(encoding="utf-8")
if "system_restart_rdp" not in app_py:
    app_py = app_py.replace(
        "    summarize_wifi_results,\n)",
        "    summarize_wifi_results,\n    validate_restart_rdp_targets,\n    run_restart_rdp_job,\n    summarize_restart_rdp_rows,\n    launch_mstsc_sequence,\n)",
        1,
    )
    app_py = app_py.replace(
        """    elif job_type == "wifi":
        rows = load_csv(artifacts.get("csv", ""))
        context["rows"] = rows
        context["summary_block"] = summarize_wifi_results(rows)
    return context""",
        """    elif job_type == "wifi":
        rows = load_csv(artifacts.get("csv", ""))
        context["rows"] = rows
        context["summary_block"] = summarize_wifi_results(rows)
    elif job_type == "restart_rdp":
        rows = load_csv(artifacts.get("csv", ""))
        context["rows"] = rows
        context["summary_block"] = summarize_restart_rdp_rows(rows)
    return context""",
        1,
    )
    route_block = '''

FORBIDDEN_CONTROLLER = "192.168.22.8"


@app.route("/system-restart-rdp", methods=["GET", "POST"])
def system_restart_rdp() -> str:
    ping_minutes = int(CONFIG["defaults"].get("restart_rdp_ping_timeout_minutes", 10))
    rdp_delay = int(CONFIG["defaults"].get("restart_rdp_mstsc_delay_seconds", 3))
    check_port = False
    auto_rdp = False
    selected = CONFIG["allowed_targets"][:]

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
            username = request.form.get("username", CONFIG["defaults"]["username"]).strip()
            password = request.form.get("password", "")

            if not password:
                flash("Password is required.", "danger")
            elif request.form.get("confirm_restart_rdp") != "yes":
                flash("Confirm the OS restart before running this workflow.", "danger")
            else:
                ordered, err = validate_restart_rdp_targets(selected, CONFIG["allowed_targets"], FORBIDDEN_CONTROLLER)
                if err:
                    flash(err, "danger")
                else:
                    assert ordered is not None
                    job = run_restart_rdp_job(
                        CONFIG,
                        ordered,
                        username,
                        password,
                        ping_timeout_seconds=ping_minutes * 60,
                        check_rdp_port=check_port,
                        auto_open_rdp=auto_rdp,
                        rdp_delay_seconds=rdp_delay,
                    )
                    flash(f"Restart+RDP job finished with status: {job['status']}. Job ID: {job['id']}", "info")
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
    job = get_job(CONFIG, job_id)
    if not job or job.get("job_type") != "restart_rdp":
        flash("Job not found or not a Restart+RDP job.", "danger")
        return redirect(url_for("history"))
    rows = load_csv(job.get("artifacts", {}).get("csv", ""))
    ips = [
        str(r.get("TargetIP", "")).strip()
        for r in rows
        if str(r.get("PingReachable", "")).lower() == "yes"
    ]
    ordered, err = validate_restart_rdp_targets(ips, CONFIG["allowed_targets"], FORBIDDEN_CONTROLLER)
    if err or not ordered:
        flash(err or "No ping-recovered targets to connect.", "warning")
        return redirect(url_for("job_detail", job_id=job_id))
    try:
        delay = float(CONFIG["defaults"].get("restart_rdp_mstsc_delay_seconds", 3))
        launch_mstsc_sequence(ordered, delay_seconds=delay)
        flash(f"Launched {len(ordered)} RDP session(s) sequentially.", "info")
    except Exception as exc:
        flash(f"RDP launch failed: {exc}", "danger")
    return redirect(url_for("job_detail", job_id=job_id))

'''
    app_py = app_py.replace(
        '@app.route("/history")\ndef history() -> str:',
        route_block + '\n\n@app.route("/history")\ndef history() -> str:',
        1,
    )

(GUI / "app.py").write_text(app_py, encoding="utf-8")

# --- base.html nav ---
base = (GUI / "templates" / "base.html").read_text(encoding="utf-8")
nav_snip = """          <div class=\"nav-label d-none d-lg-block\">Wi-Fi</div>
          <a class=\"nav-link"""
if "system_restart_rdp" not in base:
    base = base.replace(
        """          <a class=\"nav-link {% if request.endpoint == 'wifi_status' %}active{% endif %}\" href=\"{{ url_for('wifi_status') }}\">Wi-Fi Status</a>
        </div>""",
        """          <a class=\"nav-link {% if request.endpoint == 'wifi_status' %}active{% endif %}\" href=\"{{ url_for('wifi_status') }}\">Wi-Fi Status</a>
          <div class=\"nav-label d-none d-lg-block\">System</div>
          <a class=\"nav-link {% if request.endpoint == 'system_restart_rdp' %}active{% endif %}\" href=\"{{ url_for('system_restart_rdp') }}\">Restart + RDP</a>
        </div>""",
        1,
    )
    (GUI / "templates" / "base.html").write_text(base, encoding="utf-8")

# --- job_detail.html ---
jd = (GUI / "templates" / "job_detail.html").read_text(encoding="utf-8")
if "launch-rdp" not in jd:
    jd = jd.replace(
        """      {% endif %}

      <div class=\"card card-be200\">
        <div class=\"card-header\">Process output</div>""",
        """      {% endif %}

      {% if view.job.job_type == 'restart_rdp' and view.rows %}
      <div class=\"card card-be200 zone-action mb-4\">
        <div class=\"card-header\">Manual RDP launch</div>
        <div class=\"card-body\">
          <p class=\"small mb-2\">Opens <code>mstsc</code> for each host with <strong>PingReachable = Yes</strong>, in CSV order, with the configured delay between windows.</p>
          <form method=\"post\" action=\"{{ url_for('restart_rdp_launch', job_id=view.job.id) }}\">
            <button type=\"submit\" class=\"btn btn-primary\">Launch RDP (sequential)</button>
          </form>
        </div>
      </div>
      {% endif %}

      <div class=\"card card-be200\">
        <div class=\"card-header\">Process output</div>""",
        1,
    )
    (GUI / "templates" / "job_detail.html").write_text(jd, encoding="utf-8")

# --- config.json ---
cfgp = GUI / "config.json"
cfg = json.loads(cfgp.read_text(encoding="utf-8"))
cfg["defaults"]["restart_rdp_timeout_seconds"] = cfg["defaults"].get("restart_rdp_timeout_seconds", 7200)
cfg["defaults"]["restart_rdp_ping_timeout_minutes"] = cfg["defaults"].get("restart_rdp_ping_timeout_minutes", 10)
cfg["defaults"]["restart_rdp_mstsc_delay_seconds"] = cfg["defaults"].get("restart_rdp_mstsc_delay_seconds", 3)
cfgp.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")

print("RESTART+RDP patch applied.")
```

