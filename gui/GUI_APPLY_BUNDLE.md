# Staging: parsed by `_apply_gui_redesign.py` — safe to delete after apply

## FILE: templates/base.html
```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{% block title %}BE200 Control Console{% endblock %}</title>
  <link
    href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css"
    rel="stylesheet"
  >
  <link href="{{ url_for('static', filename='style.css') }}" rel="stylesheet">
</head>
<body>
  <a href="#main-content" class="skip-link">Skip to main content</a>
  <nav class="navbar navbar-expand-lg navbar-dark app-navbar mb-0">
    <div class="container-fluid px-4 py-2">
      <a class="navbar-brand" href="{{ url_for('dashboard') }}">BE200 Control Console</a>
      <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#mainNav" aria-controls="mainNav" aria-expanded="false" aria-label="Toggle navigation">
        <span class="navbar-toggler-icon"></span>
      </button>
      <div class="collapse navbar-collapse" id="mainNav">
        <div class="navbar-nav ms-auto flex-wrap align-items-lg-center gap-lg-1 py-lg-0 py-2">
          <div class="nav-label d-none d-lg-block">Monitor</div>
          <a class="nav-link {% if request.endpoint == 'dashboard' %}active{% endif %}" href="{{ url_for('dashboard') }}">Dashboard</a>
          <a class="nav-link {% if request.endpoint == 'history' %}active{% endif %}" href="{{ url_for('history') }}">History</a>
          <div class="nav-label d-none d-lg-block">Configure</div>
          <a class="nav-link {% if request.endpoint == 'inventory' %}active{% endif %}" href="{{ url_for('inventory') }}">Inventory</a>
          <a class="nav-link {% if request.endpoint == 'current_settings' %}active{% endif %}" href="{{ url_for('current_settings') }}">Current Settings</a>
          <a class="nav-link {% if request.endpoint == 'editor' %}active{% endif %}" href="{{ url_for('editor') }}">Property Editor</a>
          <div class="nav-label d-none d-lg-block">Wi-Fi</div>
          <a class="nav-link {% if request.endpoint == 'wifi_connect' %}active{% endif %}" href="{{ url_for('wifi_connect') }}">Wi-Fi Connect</a>
          <a class="nav-link {% if request.endpoint == 'wifi_status' %}active{% endif %}" href="{{ url_for('wifi_status') }}">Wi-Fi Status</a>
        </div>
      </div>
    </div>
  </nav>

  <main id="main-content" class="container-fluid px-4 pb-5 pt-3 app-main" tabindex="-1">
    <div class="scope-strip" role="region" aria-label="Accepted operational scope">
      <span class="scope-strip-label">Fleet targets</span>
      <span><code>192.168.22.221</code> – <code>192.168.22.228</code></span>
      <span class="scope-strip-label ms-lg-3">Adapter policy</span>
      <span>Only allowlisted <strong>BE200</strong> adapters are in scope for changes; other NICs are never modified.</span>
    </div>

    {% with messages = get_flashed_messages(with_categories=true) %}
      {% if messages %}
        {% for category, message in messages %}
          <div class="alert alert-{{ category }} alert-dismissible fade show" role="alert">
            {{ message }}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
          </div>
        {% endfor %}
      {% endif %}
    {% endwith %}

    {% block content %}{% endblock %}
  </main>

  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
```

## FILE: templates/dashboard.html
```html
{% extends "base.html" %}

{% block title %}Dashboard - BE200 Control Console{% endblock %}

{% block content %}
<header class="app-page-header">
  <h1 class="app-page-title">Dashboard</h1>
  <p class="app-page-lead">Controller health, artifact locations, and recent jobs. Use the scope strip above to confirm fleet and adapter policy before any action.</p>
</header>

<div class="row g-4">
  <div class="col-lg-4">
    <div class="card card-be200 h-100 zone-readonly">
      <div class="card-header">Controller Status</div>
      <div class="card-body">
        <dl class="row mb-0">
          <dt class="col-sm-4">Host</dt>
          <dd class="col-sm-8">{{ controller.hostname }}</dd>
          <dt class="col-sm-4">User</dt>
          <dd class="col-sm-8">{{ controller.user }}</dd>
          <dt class="col-sm-4">Toolkit</dt>
          <dd class="col-sm-8 text-break">{{ toolkit_root }}</dd>
          <dt class="col-sm-4">Remoting</dt>
          <dd class="col-sm-8">
            {% if remoting_status.recent %}
              <span class="badge text-bg-success">Recent</span>
            {% else %}
              <span class="badge text-bg-secondary">Not Recent</span>
            {% endif %}
          </dd>
          <dt class="col-sm-4">Remoting CSV</dt>
          <dd class="col-sm-8 text-break small">{{ remoting_status.path or "None" }}</dd>
        </dl>
      </div>
    </div>
  </div>

  <div class="col-lg-4">
    <div class="card card-be200 h-100 zone-readonly">
      <div class="card-header">Latest Artifacts</div>
      <div class="card-body">
        <dl class="row mb-0">
          <dt class="col-sm-5">Discovery CSV</dt>
          <dd class="col-sm-7 small text-break">{{ artifacts.discovery_csv or "None" }}</dd>
          <dt class="col-sm-5">Discovery JSON</dt>
          <dd class="col-sm-7 small text-break">{{ artifacts.discovery_json or "None" }}</dd>
          <dt class="col-sm-5">Template</dt>
          <dd class="col-sm-7 small text-break">{{ artifacts.template_csv or "None" }}</dd>
          <dt class="col-sm-5">Property Matrix</dt>
          <dd class="col-sm-7 small text-break">{{ artifacts.property_matrix_csv or "None" }}</dd>
          <dt class="col-sm-5">Validated Config</dt>
          <dd class="col-sm-7 small text-break">{{ artifacts.validated_config_csv or "None" }}</dd>
          <dt class="col-sm-5">Latest Apply</dt>
          <dd class="col-sm-7 small text-break">{{ artifacts.apply_results_csv or "None" }}</dd>
        </dl>
      </div>
    </div>
  </div>

  <div class="col-lg-4">
    <div class="card card-be200 h-100 zone-action">
      <div class="card-header">Quick Links</div>
      <div class="card-body">
        <div class="d-grid gap-2">
          <a class="btn btn-primary" href="{{ url_for('inventory') }}">Open Inventory</a>
          <a class="btn btn-outline-primary" href="{{ url_for('editor') }}">Open Property Editor</a>
        </div>
      </div>
    </div>
  </div>
</div>

<div class="row g-4 mt-1">
  <div class="col-lg-12">
    <div class="card card-be200">
      <div class="card-header">Recent Jobs</div>
      <div class="card-body p-0">
        <div class="table-responsive">
          <table class="table table-striped table-sm mb-0 table-be200">
            <thead>
              <tr>
                <th>Started</th>
                <th>Type</th>
                <th>Title</th>
                <th>Status</th>
                <th>Summary</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {% for item in history %}
                <tr>
                  <td class="small">{{ item.started_at }}</td>
                  <td>{{ item.job_type }}</td>
                  <td>{{ item.title }}</td>
                  <td>
                    <span class="badge {% if item.status == 'success' %}text-bg-success{% else %}text-bg-danger{% endif %}">
                      {{ item.status }}
                    </span>
                  </td>
                  <td class="small">
                    {% if item.summary.property_label %}
                      {{ item.summary.property_label }}
                    {% elif item.summary.action %}
                      {{ item.summary.action }}
                    {% elif item.summary.property_total %}
                      {{ item.summary.property_total }} properties
                    {% endif %}
                  </td>
                  <td><a class="btn btn-sm btn-outline-secondary" href="{{ url_for('job_detail', job_id=item.id) }}">Open</a></td>
                </tr>
              {% else %}
                <tr><td colspan="6" class="text-center text-muted py-4">No GUI jobs recorded yet.</td></tr>
              {% endfor %}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </div>
</div>
{% endblock %}
```

## FILE: templates/history.html
```html
{% extends "base.html" %}

{% block title %}History - BE200 Control Console{% endblock %}

{% block content %}
<header class="app-page-header">
  <h1 class="app-page-title">Execution history</h1>
  <p class="app-page-lead">Full job list with property labels, modes, targets, and classifications preserved for audit.</p>
</header>

<div class="card card-be200">
  <div class="card-header">All jobs</div>
  <div class="card-body p-0">
    <div class="table-responsive">
      <table class="table table-striped table-sm mb-0 table-be200">
        <thead>
          <tr>
            <th>Started</th>
            <th>Type</th>
            <th>Title</th>
            <th>Status</th>
            <th>Summary</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {% for item in history %}
            <tr>
              <td class="small">{{ item.started_at }}</td>
              <td>{{ item.job_type }}</td>
              <td>{{ item.title }}</td>
              <td>
                <span class="badge {% if item.status == 'success' %}text-bg-success{% else %}text-bg-danger{% endif %}">
                  {{ item.status }}
                </span>
              </td>
              <td class="small">
                {% if item.summary.property_label %}
                  <div><strong>{{ item.summary.property_label }}</strong></div>
                {% endif %}
                {% if item.summary.registry_keyword %}
                  <div><code>{{ item.summary.registry_keyword }}</code></div>
                {% endif %}
                {% if item.summary.classification %}
                  <div>class: {{ item.summary.classification }}</div>
                {% endif %}
                {% if item.summary.mode %}
                  <div>mode: {{ item.summary.mode }}</div>
                {% endif %}
                {% if item.summary.targets is iterable and item.summary.targets is not string and item.summary.targets is not number %}
                  <div>targets: {{ item.summary.targets|join(", ") }}</div>
                {% elif item.summary.targets %}
                  <div>targets: {{ item.summary.targets }}</div>
                {% elif item.summary.action %}
                  <div>action: {{ item.summary.action }}</div>
                {% elif item.summary.property_total %}
                  <div>properties: {{ item.summary.property_total }}</div>
                {% else %}
                  <code>{{ item.summary }}</code>
                {% endif %}
              </td>
              <td><a class="btn btn-sm btn-outline-secondary" href="{{ url_for('job_detail', job_id=item.id) }}">Open</a></td>
            </tr>
          {% else %}
            <tr><td colspan="6" class="text-center text-muted py-4">No GUI jobs recorded yet.</td></tr>
          {% endfor %}
        </tbody>
      </table>
    </div>
  </div>
</div>
{% endblock %}
```

## FILE: templates/job_detail.html
```html
{% extends "base.html" %}

{% block title %}Job Detail - BE200 Control Console{% endblock %}

{% block content %}
{% if not view %}
  <div class="alert alert-warning">Job detail is unavailable.</div>
{% else %}
  <header class="app-page-header">
    <h1 class="app-page-title">Job detail</h1>
    <p class="app-page-lead"><strong>{{ view.job.title }}</strong> — {{ view.job.job_type }} — status <span class="text-body">{{ view.job.status }}</span></p>
  </header>

  <div class="row g-4">
    <div class="col-lg-4">
      <div class="card card-be200 zone-readonly">
        <div class="card-header">Job metadata</div>
        <div class="card-body">
          <dl class="row mb-0">
            <dt class="col-sm-4">Title</dt>
            <dd class="col-sm-8">{{ view.job.title }}</dd>
            <dt class="col-sm-4">Type</dt>
            <dd class="col-sm-8">{{ view.job.job_type }}</dd>
            <dt class="col-sm-4">Status</dt>
            <dd class="col-sm-8">{{ view.job.status }}</dd>
            <dt class="col-sm-4">Started</dt>
            <dd class="col-sm-8">{{ view.job.started_at }}</dd>
            <dt class="col-sm-4">Finished</dt>
            <dd class="col-sm-8">{{ view.job.finished_at }}</dd>
            <dt class="col-sm-4">Exit Code</dt>
            <dd class="col-sm-8">{{ view.job.returncode }}</dd>
          </dl>
        </div>
      </div>

      <div class="card card-be200 zone-readonly mt-4">
        <div class="card-header">Artifacts</div>
        <div class="card-body">
          <ul class="small mb-0 artifact-list">
            {% for path in artifact_paths %}
              <li><a href="file:///{{ path|replace('\\', '/') }}">{{ path }}</a></li>
            {% else %}
              <li>No artifact paths recorded.</li>
            {% endfor %}
          </ul>
        </div>
      </div>
    </div>

    <div class="col-lg-8">
      <div class="card card-be200 mb-4">
        <div class="card-header">Summary</div>
        <div class="card-body">
          <pre class="mb-0 summary-pre">{{ view.summary_block }}</pre>
        </div>
      </div>

      {% if view.rows %}
        <div class="card card-be200 mb-4">
          <div class="card-header">Result rows</div>
          <div class="card-body p-0">
            <div class="table-responsive">
              <table class="table table-striped table-sm mb-0 table-be200">
                <thead>
                  <tr>
                    {% for key in view.rows[0].keys() %}
                      <th>{{ key }}</th>
                    {% endfor %}
                  </tr>
                </thead>
                <tbody>
                  {% for row in view.rows %}
                    <tr>
                      {% for key, value in row.items() %}
                        <td class="small">{{ value }}</td>
                      {% endfor %}
                    </tr>
                  {% endfor %}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      {% endif %}

      <div class="card card-be200">
        <div class="card-header">Process output</div>
        <div class="card-body">
          <h6 class="fw-semibold">Command</h6>
          <pre class="summary-pre">{{ view.job.command }}</pre>
          <h6 class="fw-semibold mt-3">Stdout</h6>
          <pre class="job-output">{{ view.job.stdout }}</pre>
          {% if view.job.stderr %}
            <h6 class="fw-semibold mt-3">Stderr</h6>
            <pre class="job-output text-danger">{{ view.job.stderr }}</pre>
          {% endif %}
        </div>
      </div>
    </div>
  </div>
{% endif %}
{% endblock %}
```

## FILE: templates/current_settings.html
```html
{% extends "base.html" %}

{% block title %}Current Settings - BE200 Control Console{% endblock %}

{% block content %}
<header class="app-page-header">
  <h1 class="app-page-title">Current settings</h1>
  <p class="app-page-lead">Matrix of <strong>accepted</strong> properties per target. Column headers show each host suffix and <span class="font-monospace">driver version</span> (high-contrast) from discovery.</p>
</header>

<div class="row g-4 mb-4 align-items-end">
  <div class="col-auto">
    <form method="post" class="d-flex align-items-end gap-2 flex-wrap">
      <input type="hidden" name="action" value="refresh_discovery">
      <div>
        <label class="form-label form-label-sm mb-0">Username</label>
        <input class="form-control form-control-sm" type="text" name="username" value="{{ default_username }}" style="width:120px">
      </div>
      <div>
        <label class="form-label form-label-sm mb-0">Password</label>
        <input class="form-control form-control-sm" type="password" name="password" required style="width:140px">
      </div>
      <button class="btn btn-sm btn-outline-primary" type="submit">Refresh Discovery</button>
    </form>
  </div>
  <div class="col">
    <div class="small text-muted mt-2 mt-md-0">
      <strong>Source:</strong> {{ discovery_path or "No discovery data" }}
    </div>
  </div>
</div>

{% if matrix %}
<div class="card card-be200">
  <div class="card-header">
    BE200 current settings (accepted scope)
    <span class="badge text-bg-success ms-2">{{ matrix|length }} properties</span>
    <span class="badge text-bg-secondary ms-1">{{ allowed_targets|length }} targets</span>
  </div>
  <div class="card-body p-0">
    <div class="matrix-table-wrap">
      <table class="table table-bordered table-sm mb-0 matrix-table" style="font-size: 0.82rem;">
        <thead>
          <tr>
            <th style="min-width:180px">Property</th>
            <th style="min-width:70px">Status</th>
            {% for target in allowed_targets %}
              <th class="text-center matrix-col-target">
                .{{ target.split(".")[-1] }}
                {% for t in inventory.targets %}
                  {% if t.target_ip == target and t.driver_version %}
                    <span class="matrix-driver-ver">v{{ t.driver_version }}</span>
                  {% endif %}
                {% endfor %}
              </th>
            {% endfor %}
          </tr>
        </thead>
        <tbody>
          {% for prop in matrix %}
            <tr class="{% if not prop.uniform %}table-warning{% endif %}">
              <td>
                <strong>{{ prop.label }}</strong>
                <div class="text-muted" style="font-size:0.72rem;"><code>{{ prop.registry_keyword }}</code></div>
              </td>
              <td class="text-center">
                {% if prop.uniform %}
                  <span class="badge text-bg-success">Uniform</span>
                {% else %}
                  <span class="badge text-bg-warning">Mixed</span>
                {% endif %}
              </td>
              {% for target in allowed_targets %}
                {% set val = prop.target_values.get(target, "") %}
                <td class="text-center {% if not prop.uniform and val %}fw-semibold{% endif %}">
                  {% if val %}
                    {{ val }}
                  {% else %}
                    <span class="text-muted">--</span>
                  {% endif %}
                </td>
              {% endfor %}
            </tr>
          {% endfor %}
        </tbody>
      </table>
    </div>
  </div>
</div>
{% else %}
  <div class="card card-be200">
    <div class="card-body text-muted">
      No discovery data is available yet. Run a discovery refresh to populate current settings.
    </div>
  </div>
{% endif %}
{% endblock %}
```

## FILE: templates/inventory.html
```html
{% extends "base.html" %}

{% block title %}Inventory - BE200 Control Console{% endblock %}

{% block content %}
<header class="app-page-header">
  <h1 class="app-page-title">Inventory</h1>
  <p class="app-page-lead">Discovery, remoting, fleet table with <strong>driver versions</strong>, and the <strong>accepted property catalog</strong>. Operational actions require explicit confirmation below.</p>
</header>

<div class="row g-4">
  <div class="col-lg-3">
    <div class="card card-be200 zone-action">
      <div class="card-header">Toolkit actions</div>
      <div class="card-body">
        <form method="post" class="mb-3">
          <input type="hidden" name="action" value="refresh_discovery">
          <div class="mb-2">
            <label class="form-label">Username</label>
            <input class="form-control" type="text" name="username" value="{{ default_username }}">
          </div>
          <div class="mb-3">
            <label class="form-label">Password</label>
            <input class="form-control" type="password" name="password" required>
          </div>
          <button class="btn btn-primary w-100" type="submit">Run Discovery Refresh</button>
        </form>

        <form method="post">
          <input type="hidden" name="action" value="run_remoting">
          <div class="mb-2">
            <label class="form-label">Username</label>
            <input class="form-control" type="text" name="username" value="{{ default_username }}">
          </div>
          <div class="mb-3">
            <label class="form-label">Password</label>
            <input class="form-control" type="password" name="password" required>
          </div>
          <button class="btn btn-outline-primary w-100" type="submit">Run Remoting Test</button>
        </form>
      </div>
    </div>

    <div class="card card-be200 zone-risk mt-4">
      <div class="card-header">BE200 operational actions</div>
      <div class="card-body">
        <p class="small text-muted mb-3">Disable, Enable, and Restart affect live adapters. Read the <strong>live policy</strong> callout and check the confirmation box before submit.</p>
        <form method="post" id="operational-form">
          <input type="hidden" name="action" value="run_operational">
          <input type="hidden" name="operation_mirror" id="operation-mirror" value="Status">
          <div class="mb-2">
            <label class="form-label">Operation</label>
            <select class="form-select" name="operation" id="operation-select">
              <option value="Status">Status</option>
              <option value="Disable">Disable</option>
              <option value="Enable">Enable</option>
              <option value="Restart">Restart</option>
            </select>
          </div>
          <div class="mb-3">
            <label class="form-label">Current target scope</label>
            <div class="form-text mb-2">Select one or more targets (up to all 8). The GUI enforces per-action limits and disables unsafe combinations.</div>
            <div class="target-grid">
              {% for target in allowed_targets %}
                <div class="form-check">
                  <input class="form-check-input" type="checkbox" name="action_targets" value="{{ target }}" id="action-target-{{ loop.index }}">
                  <label class="form-check-label" for="action-target-{{ loop.index }}">{{ target }}</label>
                </div>
              {% endfor %}
            </div>
            <div id="action-policy-note" class="callout-scope callout-scope-live mt-2" role="status" aria-live="polite"></div>
          </div>
          <div class="mb-2">
            <label class="form-label">Username</label>
            <input class="form-control" type="text" name="username" value="{{ default_username }}">
          </div>
          <div class="mb-3">
            <label class="form-label">Password</label>
            <input class="form-control" type="password" name="password" required>
          </div>
          <div class="confirmation-box">
            <div class="form-check mb-0">
              <input class="form-check-input" type="checkbox" value="yes" id="confirm-operational" name="confirm_operational">
              <label class="form-check-label" for="confirm-operational">
                I confirm Disable, Enable, or Restart only when intended. Required for those operations. The GUI remains restricted to allowlisted BE200 adapters only.
              </label>
            </div>
          </div>
          <button class="btn btn-outline-danger w-100 mt-3" type="submit">Run selected action</button>
        </form>
      </div>
    </div>

    <div class="card card-be200 zone-readonly mt-4">
      <div class="card-header">Current files</div>
      <div class="card-body small">
        <div><strong>Discovery CSV</strong><br>{{ artifacts.discovery_csv or "None" }}</div>
        <hr>
        <div><strong>Discovery JSON</strong><br>{{ artifacts.discovery_json or "None" }}</div>
        <hr>
        <div><strong>Template CSV</strong><br>{{ artifacts.template_csv or "None" }}</div>
        <hr>
        <div><strong>Property Matrix CSV</strong><br>{{ artifacts.property_matrix_csv or "None" }}</div>
        <hr>
        <div><strong>Property Matrix JSON</strong><br>{{ artifacts.property_matrix_json or "None" }}</div>
      </div>
    </div>
  </div>

  <div class="col-lg-9">
    <div class="card card-be200 mb-4">
      <div class="card-header">Target fleet</div>
      <div class="card-body p-0">
        <div class="table-responsive">
          <table class="table table-sm mb-0 table-be200">
            <thead>
              <tr>
                <th>Target</th>
                <th>Computer</th>
                <th>BE200 adapter</th>
                <th>Driver version</th>
              </tr>
            </thead>
            <tbody>
              {% for target in inventory.targets %}
                <tr>
                  <td class="font-monospace">{{ target.target_ip }}</td>
                  <td>{{ target.computer_name }}</td>
                  <td class="small">{{ target.interface_description or "Not discovered" }}</td>
                  <td class="driver-cell">{{ target.driver_version or "Unknown" }}{% if target.driver_date %}<span class="driver-date">{{ target.driver_date }}</span>{% endif %}</td>
                </tr>
              {% endfor %}
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <div class="card card-be200">
      <div class="card-header">
        Accepted properties (catalog scope)
        <span class="badge text-bg-success ms-2">{{ property_catalog|length }} live-tested</span>
      </div>
      <div class="card-body p-0">
        <div class="table-responsive">
          <table class="table table-striped table-sm mb-0 table-be200">
            <thead>
              <tr>
                <th>Property</th>
                <th>Registry keyword</th>
                <th>Risk</th>
                <th>Coverage</th>
                <th>Current values</th>
                <th>Possible values</th>
              </tr>
            </thead>
            <tbody>
              {% for item in property_catalog %}
                <tr>
                  <td>{{ item.label }}</td>
                  <td><code>{{ item.registry_keyword }}</code></td>
                  <td>{{ item.risk }}</td>
                  <td>{{ item.coverage }}</td>
                  <td class="small">{{ item.current_values|join(", ") }}</td>
                  <td class="small">{{ item.possible_display_values|join(", ") }}</td>
                </tr>
              {% else %}
                <tr><td colspan="6" class="text-center text-muted py-4">No discovery data is available yet.</td></tr>
              {% endfor %}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </div>
</div>
<script id="action-policy-data" type="application/json">{{ action_policies|tojson }}</script>
<script>
  (() => {
    const policies = JSON.parse(document.getElementById("action-policy-data").textContent);
    const operationSelect = document.getElementById("operation-select");
    const operationMirror = document.getElementById("operation-mirror");
    const operationalForm = document.getElementById("operational-form");
    const targetBoxes = Array.from(document.querySelectorAll('input[name="action_targets"]'));
    const note = document.getElementById("action-policy-note");

    function selectedTargets() {
      return targetBoxes.filter((item) => item.checked).map((item) => item.value);
    }

    function isAllowed(action, targets) {
      const policy = policies[action];
      if (!policy || !policy.accepted) {
        return false;
      }
      if (targets.length && targets.length > policy.max_targets) {
        return false;
      }
      if (targets.length && policy.accepted_targets.length) {
        return targets.every((target) => policy.accepted_targets.includes(target));
      }
      return true;
    }

    function syncMirror() {
      operationMirror.value = operationSelect.value;
    }

    function refreshActionPolicies() {
      const targets = selectedTargets();
      Array.from(operationSelect.options).forEach((option) => {
        option.disabled = !isAllowed(option.value, targets);
      });

      if (operationSelect.selectedOptions[0]?.disabled) {
        const firstEnabled = Array.from(operationSelect.options).find((option) => !option.disabled);
        if (firstEnabled) {
          operationSelect.value = firstEnabled.value;
        }
      }

      syncMirror();

      const selectedPolicy = policies[operationSelect.value];
      const acceptedTargets = selectedPolicy.accepted_targets.length ? selectedPolicy.accepted_targets.join(", ") : "all allowlisted targets";
      const blockedTargets = selectedPolicy.blocked_targets.length ? ` Blocked targets: ${selectedPolicy.blocked_targets.join(", ")}.` : "";
      note.textContent = `${operationSelect.value}: ${selectedPolicy.rationale} Accepted targets: ${acceptedTargets}. Max targets per run: ${selectedPolicy.max_targets}.${blockedTargets}`;
    }

    operationalForm.addEventListener("submit", function (e) {
      syncMirror();
      const targets = selectedTargets();
      if (targets.length === 0) {
        e.preventDefault();
        alert("Select at least one target before running an operational action.");
        return;
      }
      if (!isAllowed(operationSelect.value, targets)) {
        e.preventDefault();
        alert("The selected operation is not accepted for the chosen target(s). Change your selection.");
        return;
      }
    });

    targetBoxes.forEach((box) => box.addEventListener("change", refreshActionPolicies));
    operationSelect.addEventListener("change", refreshActionPolicies);
    refreshActionPolicies();
  })();
</script>
{% endblock %}
```

## FILE: templates/editor.html
```html
{% extends "base.html" %}

{% block title %}Property Editor - BE200 Control Console{% endblock %}

{% block content %}
<header class="app-page-header">
  <h1 class="app-page-title">Property editor</h1>
  <p class="app-page-lead">Build configs from the <strong>accepted</strong> catalog only. Validation shows modes and row status; <strong>real apply</strong> requires an explicit checkbox confirmation.</p>
</header>

<div class="row g-4">
  <div class="col-lg-5">
    <div class="card card-be200 zone-action">
      <div class="card-header">Multi-property config builder</div>
      <div class="card-body">
        {% if not discovery_available %}
          <div class="alert alert-warning mb-0">
            No discovery snapshot is available yet. Run a discovery refresh from the Inventory page first.
          </div>
        {% else %}
          <form method="post" id="editor-form">
            <input type="hidden" name="action" value="validate">
            <input type="hidden" name="discovery_path" value="{{ discovery_path }}">
            <input type="hidden" name="property_entries" id="property-entries-field" value="{{ property_entries_json }}">

            <div class="mb-3">
              <label class="form-label">Target scope</label>
              <div class="target-grid">
                {% for target in allowed_targets %}
                  <div class="form-check">
                    <input class="form-check-input" type="checkbox" name="targets" value="{{ target }}" id="target-{{ loop.index }}" {% if target in selected_targets %}checked{% endif %}>
                    <label class="form-check-label" for="target-{{ loop.index }}">{{ target }}</label>
                  </div>
                {% endfor %}
              </div>
            </div>

            <div class="mb-3">
              <label class="form-label">Mode</label>
              <select class="form-select" name="mode" id="mode-select">
                <option value="WriteOnly" {% if selected_mode == "WriteOnly" %}selected{% endif %}>WriteOnly</option>
                <option value="RestartBE200" {% if selected_mode == "RestartBE200" %}selected{% endif %}>RestartBE200</option>
              </select>
            </div>

            <hr>
            <div class="d-flex justify-content-between align-items-center mb-2">
              <label class="form-label mb-0">Property rows</label>
              <button type="button" class="btn btn-sm btn-outline-primary" id="add-property-btn">Add property</button>
            </div>
            <div class="form-text mb-2">{{ property_catalog|length }} accepted properties available. Add one or more rows below.</div>

            <div id="property-rows-container"></div>

            <button class="btn btn-primary w-100 mt-3" type="submit">Run validation</button>
          </form>
        {% endif %}
      </div>
    </div>
  </div>

  <div class="col-lg-7">
    {% if preview_rows %}
      <div class="card card-be200 mb-4 zone-readonly">
        <div class="card-header">Generated config preview <span class="badge text-bg-secondary ms-2">{{ preview_rows|length }} rows</span></div>
        <div class="card-body p-0">
          <div class="table-responsive">
            <table class="table table-sm mb-0 table-be200">
              <thead>
                <tr>
                  <th>Target</th>
                  <th>Property</th>
                  <th>Current value</th>
                  <th>Target value</th>
                </tr>
              </thead>
              <tbody>
                {% for row in preview_rows %}
                  <tr>
                    <td>{{ row.target_ip }}</td>
                    <td>{{ row.property_label }}</td>
                    <td>{{ row.current_value }}</td>
                    <td>{{ row.target_value }}</td>
                  </tr>
                {% endfor %}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    {% endif %}

    {% if validation_view %}
      <div class="card card-be200 mb-4 zone-readonly">
        <div class="card-header">Validation summary</div>
        <div class="card-body">
          <p class="mb-1"><strong>Status:</strong> {{ validation_view.job.status }}</p>
          <p class="mb-1"><strong>Properties:</strong> {{ validation_view.job.summary.property_label }}</p>
          <p class="mb-1"><strong>Property count:</strong> {{ validation_view.job.summary.property_count or 1 }}</p>
          <p class="mb-1"><strong>Mode:</strong> {{ validation_view.job.summary.mode }}</p>
          <p class="mb-1"><strong>Accepted modes:</strong> {{ validation_view.job.summary.accepted_modes|join(", ") if validation_view.job.summary.accepted_modes else "None" }}</p>
          <p class="mb-1"><strong>Valid rows:</strong> {{ validation_view.summary_block.Valid }}</p>
          <p class="mb-1"><strong>Skipped rows:</strong> {{ validation_view.summary_block.Skipped }}</p>
          <p class="mb-3"><strong>Invalid rows:</strong> {{ validation_view.summary_block.Invalid }}</p>
          <p class="small text-break mb-0">
            Validation report: {{ validation_view.job.artifacts.validation_report_csv }}<br>
            Validated config: {{ validation_view.job.artifacts.validated_config_csv }}
          </p>
        </div>
      </div>

      <div class="card card-be200 mb-4 zone-readonly">
        <div class="card-header">Validation rows</div>
        <div class="card-body p-0">
          <div class="table-responsive">
            <table class="table table-striped table-sm mb-0 table-be200">
              <thead>
                <tr>
                  <th>Status</th>
                  <th>Target</th>
                  <th>Property</th>
                  <th>Current value</th>
                  <th>Target value</th>
                  <th>Reason</th>
                </tr>
              </thead>
              <tbody>
                {% for row in validation_view.rows %}
                  <tr>
                    <td>{{ row.ValidationStatus }}</td>
                    <td>{{ row.EffectiveTargetIP }}</td>
                    <td>{{ row.PropertyDisplayName or row.RegistryKeyword }}</td>
                    <td>{{ row.CurrentValue }}</td>
                    <td>{{ row.TargetValue }}</td>
                    <td class="small">{{ row.Reason }}</td>
                  </tr>
                {% endfor %}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      {% if validation_view.job.summary.classification != "live-tested" %}
        <div class="card card-be200 zone-readonly">
          <div class="card-header">Real apply blocked</div>
          <div class="card-body">
            <p class="mb-0 text-muted">One or more properties are not classified as <strong>live-tested</strong>. Real apply is restricted to fully accepted property sets.</p>
          </div>
        </div>
      {% elif selected_mode not in validation_view.job.summary.accepted_modes %}
        <div class="card card-be200 zone-readonly">
          <div class="card-header">Real apply blocked</div>
          <div class="card-body">
            <p class="mb-0 text-muted">Mode <strong>{{ selected_mode }}</strong> is not accepted for all selected properties. Accepted modes: {{ validation_view.job.summary.accepted_modes|join(", ") }}.</p>
          </div>
        </div>
      {% elif validation_view.summary_block.Invalid > 0 or validation_view.summary_block.Skipped > 0 %}
        <div class="card card-be200 zone-readonly">
          <div class="card-header">Real apply blocked</div>
          <div class="card-body">
            <p class="mb-0 text-muted">Apply is blocked: {{ validation_view.summary_block.Invalid }} invalid and {{ validation_view.summary_block.Skipped }} skipped rows. All rows must be valid before apply is enabled.</p>
          </div>
        </div>
      {% elif validation_view.job.status == "success" and validation_view.summary_block.Valid > 0 %}
        <div class="card card-be200 zone-risk">
          <div class="card-header">Real apply — confirmation required</div>
          <div class="card-body">
            <form method="post">
              <input type="hidden" name="action" value="apply">
              <input type="hidden" name="validation_job_id" value="{{ validation_view.job.id }}">
              <input type="hidden" name="mode" value="{{ selected_mode }}">
              <div class="mb-2">
                <label class="form-label">Username</label>
                <input class="form-control" type="text" name="username" value="{{ default_username }}">
              </div>
              <div class="mb-3">
                <label class="form-label">Password</label>
                <input class="form-control" type="password" name="password" required>
              </div>
              <div class="confirmation-box">
                <div class="form-check mb-0">
                  <input class="form-check-input" type="checkbox" value="yes" id="confirm-apply" name="confirm_apply">
                  <label class="form-check-label" for="confirm-apply">
                    I confirm a real <strong>{{ selected_mode }}</strong> apply of <strong>{{ validation_view.summary_block.Valid }}</strong> validated row(s) should run on the selected targets.
                  </label>
                </div>
              </div>
              <button class="btn btn-danger mt-3" type="submit">Run real apply</button>
            </form>
          </div>
        </div>
      {% else %}
        <div class="card card-be200 zone-readonly">
          <div class="card-header">Real apply blocked</div>
          <div class="card-body">
            <p class="mb-0 text-muted">Real apply is only enabled when validation finishes successfully with at least one valid row and no skipped or invalid rows.</p>
          </div>
        </div>
      {% endif %}
    {% else %}
      <div class="card card-be200 zone-readonly">
        <div class="card-body text-muted">
          Add property rows and run validation to review the config before any real apply is enabled.
        </div>
      </div>
    {% endif %}
  </div>
</div>
<script id="property-catalog-data" type="application/json">{{ property_catalog|tojson }}</script>
<script>
  (() => {
    const catalog = JSON.parse(document.getElementById("property-catalog-data").textContent);
    const container = document.getElementById("property-rows-container");
    const addBtn = document.getElementById("add-property-btn");
    const hiddenField = document.getElementById("property-entries-field");
    const form = document.getElementById("editor-form");
    let rowIndex = 0;

    function buildOptionHtml() {
      let html = '<option value="">Select an accepted property</option>';
      catalog.forEach((item) => {
        html += `<option value="${item.key}">${item.label}</option>`;
      });
      return html;
    }

    function addRow(prefillKey, prefillValue) {
      const idx = rowIndex++;
      const div = document.createElement("div");
      div.className = "card card-body p-2 mb-2 property-row";
      div.dataset.rowIdx = idx;

      const propSelect = document.createElement("select");
      propSelect.className = "form-select form-select-sm mb-1";
      propSelect.innerHTML = buildOptionHtml();
      if (prefillKey) propSelect.value = prefillKey;

      const valSelect = document.createElement("select");
      valSelect.className = "form-select form-select-sm mb-1";
      valSelect.innerHTML = '<option value="">Select a discovered value</option>';

      const valInput = document.createElement("input");
      valInput.type = "text";
      valInput.className = "form-control form-control-sm mb-1";
      valInput.placeholder = "Target value";
      if (prefillValue) valInput.value = prefillValue;

      const removeBtn = document.createElement("button");
      removeBtn.type = "button";
      removeBtn.className = "btn btn-sm btn-outline-danger w-100";
      removeBtn.textContent = "Remove";
      removeBtn.addEventListener("click", () => { div.remove(); syncHidden(); });

      function refreshValues() {
        const item = catalog.find((c) => c.key === propSelect.value);
        const values = item ? item.possible_display_values : [];
        valSelect.innerHTML = "";
        const ph = document.createElement("option");
        ph.value = "";
        ph.textContent = values.length ? "Select a discovered value" : "No discovered values";
        valSelect.appendChild(ph);
        values.forEach((v) => {
          const opt = document.createElement("option");
          opt.value = v;
          opt.textContent = v;
          if (v === valInput.value) opt.selected = true;
          valSelect.appendChild(opt);
        });
        valSelect.disabled = values.length === 0;
        syncHidden();
      }

      propSelect.addEventListener("change", refreshValues);
      valSelect.addEventListener("change", () => { if (valSelect.value) valInput.value = valSelect.value; syncHidden(); });
      valInput.addEventListener("input", syncHidden);

      div.appendChild(propSelect);
      div.appendChild(valSelect);
      div.appendChild(valInput);
      div.appendChild(removeBtn);
      container.appendChild(div);
      refreshValues();
    }

    function syncHidden() {
      const entries = [];
      container.querySelectorAll(".property-row").forEach((row) => {
        const sel = row.querySelector("select");
        const inp = row.querySelector('input[type="text"]');
        if (sel && sel.value && inp && inp.value) {
          entries.push({ property_key: sel.value, target_value: inp.value });
        }
      });
      hiddenField.value = JSON.stringify(entries);
    }

    addBtn.addEventListener("click", () => addRow("", ""));

    form.addEventListener("submit", (e) => {
      syncHidden();
      let entries;
      try { entries = JSON.parse(hiddenField.value); } catch { entries = []; }
      if (!entries.length) {
        e.preventDefault();
        alert("Add at least one property row with a selected property and target value.");
      }
    });

    try {
      const saved = JSON.parse(hiddenField.value);
      if (Array.isArray(saved) && saved.length > 0) {
        saved.forEach((entry) => addRow(entry.property_key || "", entry.target_value || ""));
      }
    } catch {}
  })();
</script>
{% endblock %}
```

## FILE: templates/wifi_connect.html
```html
{% extends "base.html" %}

{% block title %}Wi-Fi Connect - BE200 Control Console{% endblock %}

{% block content %}
<header class="app-page-header">
  <h1 class="app-page-title">Wi-Fi connect</h1>
  <p class="app-page-lead">Changes wireless profiles on selected fleet targets. Confirm <strong>target scope</strong> and SSID before Connect; only allowlisted BE200 adapters are affected.</p>
</header>

<div class="row g-4">
  <div class="col-lg-4">
    <div class="card card-be200 zone-risk">
      <div class="card-header">Wi-Fi connect / verify</div>
      <div class="card-body">
        <form method="post" id="wifi-connect-form">
          <div class="mb-3">
            <label class="form-label fw-semibold">Target scope</label>
            <div class="mb-1">
              <button type="button" class="btn btn-sm btn-outline-secondary" id="select-all-btn">Select all</button>
              <button type="button" class="btn btn-sm btn-outline-secondary" id="clear-all-btn">Clear all</button>
            </div>
            <div class="target-grid">
              {% for target in allowed_targets %}
                <div class="form-check">
                  <input class="form-check-input target-check" type="checkbox" name="targets" value="{{ target }}" id="target-{{ loop.index }}"
                    {% if target in selected_targets %}checked{% endif %}>
                  <label class="form-check-label" for="target-{{ loop.index }}">{{ target }}</label>
                </div>
              {% endfor %}
            </div>
          </div>

          <div class="mb-3">
            <label class="form-label fw-semibold">SSID</label>
            <input class="form-control" type="text" name="ssid" value="{{ ssid }}" required placeholder="Wi-Fi network name">
          </div>

          <div class="mb-3">
            <label class="form-label fw-semibold">Wi-Fi password</label>
            <input class="form-control" type="password" name="wifi_password" placeholder="Wi-Fi network password">
            <div class="form-text">Required for WPA2/password-protected networks. Leave empty for open networks. Not needed for Verify.</div>
          </div>

          <hr>

          <div class="mb-2">
            <label class="form-label">WinRM username</label>
            <input class="form-control form-control-sm" type="text" name="username" value="{{ default_username }}">
          </div>
          <div class="mb-3">
            <label class="form-label">WinRM password</label>
            <input class="form-control form-control-sm" type="password" name="password" required placeholder="Remote management password">
          </div>

          <div class="d-flex gap-2 flex-wrap">
            <button class="btn btn-primary" type="submit" name="action" value="connect">Connect</button>
            <button class="btn btn-outline-info" type="submit" name="action" value="verify">Verify</button>
          </div>
        </form>
      </div>
    </div>

    <div class="card card-be200 zone-readonly mt-4">
      <div class="card-header">How it works</div>
      <div class="card-body small">
        <p class="mb-2"><strong>Connect</strong> creates a Wi-Fi profile on each selected target and connects the BE200 adapter to the specified SSID. If a Wi-Fi password is provided, WPA2-Personal authentication is used; otherwise, an open-network profile is created.</p>
        <p class="mb-2"><strong>Verify</strong> checks whether each target's BE200 adapter is currently connected to the expected SSID.</p>
        <p class="mb-0 text-muted">Only the allowlisted BE200 adapter is targeted. Ethernet and other adapters are never modified.</p>
      </div>
    </div>
  </div>

  <div class="col-lg-8">
    {% if result_rows %}
    <div class="card card-be200">
      <div class="card-header">
        Results
        {% if summary %}
          <span class="badge text-bg-secondary ms-2">{{ summary.total }} targets</span>
          <span class="badge text-bg-success ms-1">{{ summary.success }} succeeded</span>
          {% if summary.failed > 0 %}
            <span class="badge text-bg-danger ms-1">{{ summary.failed }} failed</span>
          {% endif %}
          <span class="badge text-bg-info ms-1">{{ summary.connected }} connected</span>
        {% endif %}
      </div>
      <div class="card-body p-0">
        <div class="table-responsive">
          <table class="table table-bordered table-sm mb-0 table-be200" style="font-size: 0.85rem;">
            <thead>
              <tr>
                <th>Target</th>
                <th>Adapter</th>
                <th>Requested SSID</th>
                <th>State</th>
                <th>Actual SSID</th>
                <th>Radio type</th>
                <th>Success</th>
                <th>Message</th>
              </tr>
            </thead>
            <tbody>
              {% for row in result_rows %}
                <tr class="{% if row.Success|lower == 'true' %}table-success{% elif row.State|lower == 'error' %}table-danger{% else %}table-warning{% endif %}">
                  <td>{{ row.TargetIP }}</td>
                  <td>{{ row.AdapterName or '--' }}</td>
                  <td>{{ row.RequestedSSID or '--' }}</td>
                  <td>
                    {% if row.State|lower == 'connected' %}
                      <span class="badge text-bg-success">{{ row.State }}</span>
                    {% elif row.State|lower == 'error' or row.State|lower == 'disabled' %}
                      <span class="badge text-bg-danger">{{ row.State }}</span>
                    {% else %}
                      <span class="badge text-bg-warning">{{ row.State }}</span>
                    {% endif %}
                  </td>
                  <td>{{ row.SSID or '--' }}</td>
                  <td>{{ row.RadioType or '--' }}</td>
                  <td>
                    {% if row.Success|lower == 'true' %}
                      <span class="badge text-bg-success">Yes</span>
                    {% else %}
                      <span class="badge text-bg-danger">No</span>
                    {% endif %}
                  </td>
                  <td class="small">{{ row.Message or '--' }}</td>
                </tr>
              {% endfor %}
            </tbody>
          </table>
        </div>
      </div>
    </div>
    {% else %}
    <div class="card card-be200 zone-readonly">
      <div class="card-body text-muted">
        Select targets, enter the SSID and password, then click <strong>Connect</strong> to join a Wi-Fi network or <strong>Verify</strong> to check current connection status against an expected SSID.
      </div>
    </div>
    {% endif %}
  </div>
</div>

<script>
  (() => {
    const checks = Array.from(document.querySelectorAll('.target-check'));
    document.getElementById('select-all-btn').addEventListener('click', () => {
      checks.forEach(c => c.checked = true);
    });
    document.getElementById('clear-all-btn').addEventListener('click', () => {
      checks.forEach(c => c.checked = false);
    });

    document.getElementById('wifi-connect-form').addEventListener('submit', (e) => {
      const selected = checks.filter(c => c.checked);
      if (selected.length === 0) {
        e.preventDefault();
        alert('Select at least one target.');
        return;
      }
      const ssid = document.querySelector('input[name="ssid"]').value.trim();
      if (!ssid) {
        e.preventDefault();
        alert('Enter an SSID.');
        return;
      }
    });
  })();
</script>
{% endblock %}
```

## FILE: templates/wifi_status.html
```html
{% extends "base.html" %}

{% block title %}Wi-Fi Status - BE200 Control Console{% endblock %}

{% block content %}
<header class="app-page-header">
  <h1 class="app-page-title">Wi-Fi status</h1>
  <p class="app-page-lead">Read-only check across fleet targets <code class="small">192.168.22.221</code>–<code class="small">228</code> (see scope strip). No configuration changes.</p>
</header>

<div class="row g-4 mb-4">
  <div class="col-auto">
    <form method="post" class="d-flex align-items-end gap-2 flex-wrap">
      <input type="hidden" name="action" value="check_status">
      <div>
        <label class="form-label form-label-sm mb-0">Username</label>
        <input class="form-control form-control-sm" type="text" name="username" value="{{ default_username }}" style="width:120px">
      </div>
      <div>
        <label class="form-label form-label-sm mb-0">Password</label>
        <input class="form-control form-control-sm" type="password" name="password" required style="width:140px">
      </div>
      <button class="btn btn-sm btn-primary" type="submit">Check status</button>
    </form>
  </div>
</div>

{% if status_rows %}
<div class="card card-be200">
  <div class="card-header">
    BE200 Wi-Fi status
    <span class="badge text-bg-secondary ms-2">{{ status_rows|length }} targets</span>
    {% if summary %}
      <span class="badge text-bg-success ms-1">{{ summary.connected }} connected</span>
      {% if summary.disconnected > 0 %}
        <span class="badge text-bg-warning ms-1">{{ summary.disconnected }} not connected</span>
      {% endif %}
    {% endif %}
  </div>
  <div class="card-body p-0">
    <div class="table-responsive">
      <table class="table table-bordered table-sm mb-0 table-be200" style="font-size: 0.85rem;">
        <thead>
          <tr>
            <th>Target</th>
            <th>Adapter</th>
            <th>State</th>
            <th>SSID</th>
            <th>Radio type</th>
            <th>Signal</th>
            <th>Auth</th>
            <th>Channel</th>
            <th>Message</th>
          </tr>
        </thead>
        <tbody>
          {% for row in status_rows %}
            <tr class="{% if row.State|lower == 'connected' %}table-success{% elif row.State|lower == 'error' or row.State|lower == 'disabled' %}table-danger{% else %}table-warning{% endif %}">
              <td>{{ row.TargetIP }}</td>
              <td>{{ row.AdapterName or '--' }}</td>
              <td>
                {% if row.State|lower == 'connected' %}
                  <span class="badge text-bg-success">{{ row.State }}</span>
                {% elif row.State|lower == 'error' or row.State|lower == 'disabled' %}
                  <span class="badge text-bg-danger">{{ row.State }}</span>
                {% else %}
                  <span class="badge text-bg-warning">{{ row.State }}</span>
                {% endif %}
              </td>
              <td>{{ row.SSID or '--' }}</td>
              <td>{{ row.RadioType or '--' }}</td>
              <td>{{ row.Signal or '--' }}</td>
              <td>{{ row.Authentication or '--' }}</td>
              <td>{{ row.Channel or '--' }}</td>
              <td class="small">{{ row.Message or '--' }}</td>
            </tr>
          {% endfor %}
        </tbody>
      </table>
    </div>
  </div>
</div>
{% else %}
  <div class="card card-be200 zone-readonly">
    <div class="card-body text-muted">
      Enter credentials and click <strong>Check status</strong> to view the current Wi-Fi state across all managed BE200 targets (192.168.22.221–228).
    </div>
  </div>
{% endif %}
{% endblock %}
```
