# BE200 GUI Runbook

## Purpose
This local web GUI runs on the controller and wraps the existing validated PowerShell toolkit under `C:\Test House BE200 control`.

The GUI does not replace the toolkit logic. It orchestrates these scripts:
- `test-remoting.ps1`
- `discover-be200-advanced-properties.ps1`
- `export-be200-config-template.ps1`
- `validate-be200-config.ps1`
- `apply-be200-config.ps1`

`invoke-be200-action.ps1` is intentionally not wired into the v1 GUI.

## Python Requirements
Use Python 3 only:
- `py -3`
- `py -3 -m pip`

Do not use the plain `python` command on this machine.

## Install Dependencies
From `C:\Test House BE200 control\gui`:

```powershell
py -3 -m pip install -r requirements.txt
```

## Start The GUI
From `C:\Test House BE200 control\gui`:

```powershell
.\start-gui.ps1
```

Or directly:

```powershell
py -3 .\app.py
```

Default URL:

```text
http://127.0.0.1:5000
```

## GUI Structure
- `app.py`: Flask entrypoint and routes
- `services.py`: PowerShell orchestration, artifact discovery, inventory parsing, history storage
- `config.json`: local GUI settings and validated target scope
- `templates/`: HTML pages
- `static/`: local CSS
- `data/`: GUI job history and per-job JSON
- `work/configs/`: generated config CSVs used for validate/apply
- `logs/`: reserved for future local GUI logs

## Safety Model
- Only the validated target set `192.168.22.221` through `192.168.22.228` is exposed.
- The GUI never asks for arbitrary IP entry.
- The GUI reads discovery outputs to build property/value inventory.
- The GUI always validates before enabling real apply.
- Real apply requires explicit confirmation in the browser.
- The GUI uses the validated toolkit scripts rather than issuing raw adapter-changing commands.

## Page Mapping

### Dashboard
- shows toolkit root
- shows controller identity
- shows latest remoting/discovery/template/apply artifacts
- shows recent GUI jobs

### Inventory
- reads the latest discovery snapshot
- shows per-target adapter resolution and property counts
- highlights variant targets with missing keywords
- can run remoting test
- can run discovery refresh, then template export

### Property Editor
- selects one or more validated targets
- selects one property from latest discovery data
- accepts a target value
- supports `WriteOnly` and `RestartBE200`
- generates config CSV rows in `gui\work\configs`
- runs validation first
- shows validation output
- only then enables real apply

### History / Job Detail
- stores each GUI-triggered run as JSON in `gui\data\jobs`
- stores a summary index in `gui\data\history.json`
- shows command, stdout, stderr, artifact paths, and parsed result rows

## Artifact Usage
The GUI reuses the existing toolkit output folders under `C:\Test House BE200 control\output` for:
- remoting CSV
- discovery CSV/JSON/transcript
- validation report + validated config
- apply results CSV/JSON
- rollback CSV/JSON
- apply transcript

Generated GUI config CSVs are created under:
- `C:\Test House BE200 control\gui\work\configs`

## Notes
- The GUI expects credentials to be entered in the form for discovery, remoting, or apply actions.
- Passwords are not persisted in the GUI history.
- If discovery data is stale, refresh discovery before editing properties.
