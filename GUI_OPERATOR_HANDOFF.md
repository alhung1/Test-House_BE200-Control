# GUI Operator Handoff

## Accepted Scope
The GUI/toolkit is accepted for controlled BE200 advanced-settings operations from `192.168.22.8` within the existing safeguards only.

Accepted target scope:
- `192.168.22.221` through `192.168.22.228`

Accepted adapter scope:
- `Intel(R) Wi-Fi 7 BE200 320MHz`
- `Intel(R) Wi-Fi 7 BE200 320MHz #6`

Accepted GUI/toolkit use:
- Discovery and inventory viewing
- Multi-property configuration: select one or more accepted properties with individual target values in a single run
- Validation before apply across the full multi-property config set
- Real apply only for properties and modes explicitly accepted below
- History, job detail, stdout/stderr, rollback artifacts, and artifact review
- GUI operational actions: `Status`, `Restart`, `Disable`, and `Enable`
- Wi-Fi Connect: connect BE200 adapters to a specified SSID (open or WPA2-Personal)
- Wi-Fi Status: view current Wi-Fi state, SSID, radio type, signal, and authentication across all targets
- Property editor selector shows only the 24 live-tested accepted properties; deferred and validation-only properties are not listed
- BE200 driver version and driver date are shown per target in the inventory summary
- One-click GUI launch via `C:\Test House BE200 control\launch-be200-gui.ps1`

## Final Property Acceptance
All 24 operator-visible BE200 advanced properties are now accepted in both `WriteOnly` and `RestartBE200`.

All accepted property rollout scope:
- `WriteOnly`: all 8 allowlisted targets
- `RestartBE200`: all 8 allowlisted targets
- Rollback: proven

Accepted properties:
- `Preferred Band` / `RoamingPreferredBandType`
- `Roaming Aggressiveness` / `RoamAggressiveness`
- `U-APSD support` / `uAPSDSupport`
- `Throughput Booster` / `ThroughputBoosterEnabled`
- `Fat Channel Intolerant` / `FatChannelIntolerant`
- `Channel-Load usage for AP Selection` / `EnableChLoad4ApSelection`
- `Mixed Mode Protection` / `CtsToItself`
- `Transmit Power` / `IbssTxPower`
- `Channel Width for 2.4GHz` / `ChannelWidth24`
- `Channel Width for 5GHz` / `ChannelWidth52`
- `Channel Width for 6GHz` / `ChannelWidth6`
- `MIMO Power Save Mode` / `MIMOPowerSaveMode`
- `802.11a/b/g Wireless Mode` / `WirelessMode`
- `802.11n/ac/ax/be Wireless Mode` / `IEEE11nMode`
- `Ultra High Band (6GHz)` / `Is6GhzBandSupported`
- `ARP offload for WoWLAN` / `*PMARPOffload`
- `GTK rekeying for WoWLAN` / `*PMWiFiRekeyOffload`
- `NS offload for WoWLAN` / `*PMNSOffload`
- `Packet Coalescing` / `*PacketCoalescing`
- `RSCv4` / `*RscIPv4`
- `RSCv6` / `*RscIPv6`
- `Sleep on WoWLAN Disconnect` / `*DeviceSleepOnDisconnect`
- `Wake on Magic Packet` / `*WakeOnMagicPacket`
- `Wake on Pattern Match` / `*WakeOnPattern`

## Deferred Properties
67 discovered properties remain deferred from operator apply scope.

Deferred scope:
- Registry-only or informational properties without a stable operator-facing display label
- Non-operator-visible entries not promoted into GUI apply scope

## Accepted GUI Operational Actions
Accepted operational-action scope:
- `Status`: up to all 8 targets per run across `192.168.22.221-228`
- `Restart`: up to all 8 targets per run across `192.168.22.221-228` (confirmation required)
- `Disable`: up to all 8 targets per run across `192.168.22.221-228` (confirmation required)
- `Enable`: up to all 8 targets per run across `192.168.22.221-228` (confirmation required)

Multi-target actions are accepted after staged live verification at 2-target, 4-target, and all-8 scope. The toolkit executes each target sequentially in a single run and records per-target results.

`Disable` and `Enable` are accepted on all 8 targets because the toolkit persists the exact BE200 adapter identity from the `Disable` step and reuses it during `Enable`, even when multiple hosts are disabled in the same run.

Primary identity fields used for safe reversal:
- `Name`
- `InterfaceDescription`
- `MacAddress`
- `ifIndex`
- `PnPDeviceID`

## Not Accepted Scope
The following are not accepted for operator use in the current handoff scope:
- Any raw or arbitrary command execution
- Any target outside `192.168.22.221-228`
- Any adapter outside the allowlisted BE200 interface descriptions
- Any browser automation workflows
- Any network layer-3 changes, including IP, gateway, DNS, routes, metrics, proxy, or Ethernet configuration
- Any property outside the 24 operator-visible live-tested entries

## Known Residual Risks
- `RestartBE200` briefly disrupts the BE200 adapter and can leave discovery lagging for a short interval immediately afterward.
- `Disable` intentionally removes the active BE200 adapter from discovery until the follow-up `Enable` step completes. When disabling multiple targets in one run, all affected targets need re-enabling before their BE200 adapters return to discovery.
- Host `.226` still has a known discovery variance around `SwRadioState`; treat that as known variance, not a generic GUI failure.
- Deferred properties are no longer shown in the property editor selector but remain visible in the inventory catalog for audit purposes.
- Driver version and date shown in the inventory come from the `DriverVersion` and `DriverDate` registry keywords in the current discovery snapshot. If a target has no discovery data, the version shows as "Unknown".

## Resolved Issues
- A previous GUI bug caused accepted one-target operational actions (`Status`, `Restart`, `Disable`, `Enable`) to incorrectly show "This BE200 operational action is not accepted in the current GUI scope." This was caused by the browser not submitting the operation value when the selected `<option>` was disabled by JavaScript policy logic. The fix added a hidden mirror input field, a client-side submission guard, and a server-side fallback so the operation value is always received. All four accepted one-target actions now work correctly.

## Exact Boundaries Operators Must Not Exceed
Operators must not:
- Target any machine outside `192.168.22.221-228`
- Operate on any adapter other than the allowlisted BE200 interface descriptions
- Skip validation before apply
- Force real apply on deferred properties
- Attempt Ethernet changes
- Attempt IP, gateway, DNS, route, metric, or proxy changes

## Multi-Property Support
The property editor supports selecting multiple accepted properties in a single run.

Behavior:
- click `Add Property` to add rows; each row has its own property selector and target value
- all rows share the same target set and mode
- the GUI blocks validation if any selected property is not live-tested
- the GUI blocks validation if the selected mode is not accepted for all chosen properties
- validation produces per-property, per-target result rows
- real apply is blocked unless all validation rows are valid (no invalid or skipped rows)
- rollback artifacts cover all properties in the run
- no property combinations have been found to be unsafe; all 24 accepted properties can be freely combined

Live-verified multi-property scenarios:
- 1 target, 2 properties, WriteOnly
- 1 target, 3 properties, WriteOnly
- 2 targets, 2 properties, WriteOnly
- 1 target, 2 properties, RestartBE200

## Wi-Fi Connect and Status

### Wi-Fi Connect (`/wifi-connect`)
Connects BE200 adapters on selected targets to a specified SSID.

Usage:
1. Select one or more targets (all pre-checked by default).
2. Enter the SSID.
3. If the network uses WPA2-Personal, enter the Wi-Fi password. Leave empty for open networks.
4. Enter WinRM credentials.
5. Click `Connect` to connect, or `Verify` to check whether selected targets are already on the expected SSID.

How Connect works:
- Creates a Wi-Fi profile (WPA2-Personal if a password is provided, Open if not) on each target using `netsh wlan add profile`.
- Issues `netsh wlan connect` for the specified SSID on the BE200 interface.
- Waits 5 seconds, then reads `netsh wlan show interfaces` to report the result.
- The temp profile XML is deleted immediately after the profile is added.
- Only the allowlisted BE200 adapter interface is targeted; Ethernet is never touched.

How Verify works:
- Reads the current connection state from `netsh wlan show interfaces` on each target.
- Compares the actual connected SSID to the expected SSID.
- Reports match/mismatch per target.

Results show: target IP, adapter name, requested SSID, state (connected/disconnected), actual SSID, radio type, success/failure, and a message.

### Wi-Fi Status (`/wifi-status`)
Read-only view of the current Wi-Fi state across all managed targets.

Usage:
1. Enter WinRM credentials and click `Check Status`.

Displays per target: adapter name, connection state, SSID, radio type, signal, authentication type, and channel.

Radio type is retrieved from `netsh wlan show interfaces` on the remote target and reflects the negotiated 802.11 standard (e.g., `802.11be` for Wi-Fi 7).

### Supported authentication types
- **Open**: no password required; leave the Wi-Fi Password field empty
- **WPA2-Personal**: standard SSID + password; enter the Wi-Fi password in the form

Enterprise authentication (802.1X, EAP, RADIUS) is not supported in this version.

### Success criteria
- **Connect success**: the per-target result row shows `State` = `connected` and `SSID` matches the requested SSID. No deeper connectivity check (ping, DNS resolution, HTTP) is performed; success is determined solely by the adapter's reported state in `netsh wlan show interfaces` after the 5-second post-connect wait.
- **Connect failure**: `State` is not `connected`, or the actual SSID does not match the requested SSID. The `Message` column provides the reason (e.g., SSID not visible, auth mismatch, adapter disabled).
- **Verify success**: `State` = `connected` and the actual SSID matches the expected SSID passed to the Verify action.
- **Verify failure**: the adapter is not connected, or the connected SSID does not match the expected SSID.
- **Status success**: the per-target row was returned without error. The `State`, `SSID`, `RadioType`, `Signal`, `Authentication`, and `Channel` fields are populated from `netsh wlan show interfaces`.

### Caveats
- The SSID must be visible on the target's Wi-Fi scan for Connect to succeed. If the network is out of range or the radio band doesn't cover it, the connection request completes but the adapter remains disconnected.
- The script matches the BE200 adapter in `netsh wlan` output by `Description` (matching `InterfaceDescription` from `Get-NetAdapter`). On targets with ghost adapters, the interface names in `Get-NetAdapter` and `netsh wlan` may differ; the description-based matching handles this correctly.
- Wi-Fi passwords are passed over encrypted WinRM and stored only in a temporary profile XML that is deleted immediately. They are redacted in all job records and logs.
- The Wi-Fi Connect page does not delete or manage existing Wi-Fi profiles; it only adds and connects.

## Concise GUI Run / Use Instructions
From `192.168.22.8`:

1. Launch the GUI with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Test House BE200 control\launch-be200-gui.ps1"`.
2. Open `http://127.0.0.1:5000/` if it does not open automatically.
3. Use `Inventory` to confirm discovery data is present, the intended target appears in the allowed range, and the driver version is shown.
4. Open `Property Editor`.
5. Select allowed target(s) and a mode.
6. Click `Add Property` to add one or more property rows. For each row, select an accepted property and choose a target value.
7. Run `Validation` and confirm it succeeds with all rows valid.
8. Only after successful validation, run real apply.
9. Review job detail for per-property, per-target result rows, stdout/stderr, and rollback artifacts.
10. For operational actions, use `Inventory` and select one or more targets (up to all 8).
11. For `Disable` and `Enable`, always follow a multi-target `Disable` with a matching `Enable` on the same targets and verify all per-target results before proceeding.
12. To connect BE200 adapters to a Wi-Fi network, open `Wi-Fi Connect`, select targets, enter the SSID (and password if WPA2), then click `Connect`. Use `Verify` to confirm the connection.
13. To view the current Wi-Fi state across all targets, open `Wi-Fi Status`, enter WinRM credentials, and click `Check Status`.

## Existing Workflow Integrity
The Wi-Fi Connect / Verify / Status feature is a separate workflow from the advanced-property apply path. All existing accepted workflows remain fully intact and unmodified:
- Discovery, inventory, and current-settings viewing
- Multi-property validation, apply, and rollback
- Operational actions (Status, Restart, Disable, Enable)
- History, job detail, and artifact review
- GUI enforcement of accepted property/action boundaries

This handoff is limited to the current validated GUI/toolkit scope only.
