# BE200 Compact Operator Summary

## Accepted Properties
All accepted properties below are operator-visible, live-tested, rollback-proven, and accepted on `192.168.22.221-228`.

- `Preferred Band` / `RoamingPreferredBandType`: `WriteOnly`, `RestartBE200`
- `Roaming Aggressiveness` / `RoamAggressiveness`: `WriteOnly`, `RestartBE200`
- `U-APSD support` / `uAPSDSupport`: `WriteOnly`, `RestartBE200`
- `Throughput Booster` / `ThroughputBoosterEnabled`: `WriteOnly`, `RestartBE200`
- `Fat Channel Intolerant` / `FatChannelIntolerant`: `WriteOnly`, `RestartBE200`
- `Channel-Load usage for AP Selection` / `EnableChLoad4ApSelection`: `WriteOnly`, `RestartBE200`
- `Mixed Mode Protection` / `CtsToItself`: `WriteOnly`, `RestartBE200`
- `Transmit Power` / `IbssTxPower`: `WriteOnly`, `RestartBE200`
- `Channel Width for 2.4GHz` / `ChannelWidth24`: `WriteOnly`, `RestartBE200`
- `Channel Width for 5GHz` / `ChannelWidth52`: `WriteOnly`, `RestartBE200`
- `Channel Width for 6GHz` / `ChannelWidth6`: `WriteOnly`, `RestartBE200`
- `MIMO Power Save Mode` / `MIMOPowerSaveMode`: `WriteOnly`, `RestartBE200`
- `802.11a/b/g Wireless Mode` / `WirelessMode`: `WriteOnly`, `RestartBE200`
- `802.11n/ac/ax/be Wireless Mode` / `IEEE11nMode`: `WriteOnly`, `RestartBE200`
- `Ultra High Band (6GHz)` / `Is6GhzBandSupported`: `WriteOnly`, `RestartBE200`
- `ARP offload for WoWLAN` / `*PMARPOffload`: `WriteOnly`, `RestartBE200`
- `GTK rekeying for WoWLAN` / `*PMWiFiRekeyOffload`: `WriteOnly`, `RestartBE200`
- `NS offload for WoWLAN` / `*PMNSOffload`: `WriteOnly`, `RestartBE200`
- `Packet Coalescing` / `*PacketCoalescing`: `WriteOnly`, `RestartBE200`
- `RSCv4` / `*RscIPv4`: `WriteOnly`, `RestartBE200`
- `RSCv6` / `*RscIPv6`: `WriteOnly`, `RestartBE200`
- `Sleep on WoWLAN Disconnect` / `*DeviceSleepOnDisconnect`: `WriteOnly`, `RestartBE200`
- `Wake on Magic Packet` / `*WakeOnMagicPacket`: `WriteOnly`, `RestartBE200`
- `Wake on Pattern Match` / `*WakeOnPattern`: `WriteOnly`, `RestartBE200`

## Operational Actions
- `Status`: accepted on `192.168.22.221-228`, up to all 8 per run
- `Restart`: accepted on `192.168.22.221-228`, up to all 8 per run (confirmation required)
- `Disable`: accepted on `192.168.22.221-228`, up to all 8 per run (confirmation required)
- `Enable`: accepted on `192.168.22.221-228`, up to all 8 per run (confirmation required)
- Multi-target actions are live-verified at 2-target, 4-target, and all-8 scope.

## Wi-Fi Connect / Verify / Status
GUI pages: `/wifi-connect`, `/wifi-status`

Accepted scope:
- Targets: `192.168.22.221-228`, up to all 8 per run
- Adapter: allowlisted BE200 interface descriptions only
- Auth types: Open (no password) and WPA2-Personal (SSID + password)
- Actions: `Connect`, `Verify`, `Status`

Success criteria:
- **Connect**: `State` = `connected` and `SSID` matches the requested SSID. No deeper connectivity check (no ping/DNS); success is determined solely by the adapter's `netsh wlan show interfaces` state.
- **Verify**: `State` = `connected` and actual SSID matches the expected SSID.
- **Status**: per-target row returned with adapter name, state, SSID, radio type, signal, authentication, and channel. `Success` = `True` when the status was retrieved without error.

Wi-Fi caveats:
- The requested SSID must be visible on the target's scan. Out-of-range networks result in a completed request but the adapter stays disconnected.
- Password is optional; leave empty for open networks.
- Wi-Fi passwords are redacted in all job records and logs. The temp profile XML is deleted immediately after use.
- Enterprise auth (802.1X / EAP / RADIUS) is not supported.
- The feature does not delete, forget, or reprioritize existing Wi-Fi profiles.

## Key Caveats
- `.226` has known discovery variance around `SwRadioState`.
- Immediate post-`RestartBE200` discovery can lag briefly before the adapter state settles.
- Immediate post-`Disable` discovery will temporarily show the BE200 adapter absent until `Enable` completes.

## Go / No-Go
Go:
- Use only `192.168.22.221-228`.
- Use only the allowlisted BE200 adapters.
- Validate before every real apply.
- Use `WriteOnly` or `RestartBE200` only on the 24 accepted properties above.
- Operational actions can run on 1 to 8 targets per run.
- For `Disable`, always follow with a matching `Enable` on the same targets.
- Wi-Fi Connect / Verify / Status can run on 1 to 8 targets per run using Open or WPA2-Personal auth.

No-Go:
- No targets outside `192.168.22.221-228`.
- No non-BE200 adapters.
- No deferred properties.
- No Ethernet, IP, gateway, DNS, route, metric, or proxy changes.
- No enterprise Wi-Fi auth (802.1X / EAP / RADIUS).
- No Wi-Fi profile deletion or priority management.

## Existing Workflows
All existing advanced-property apply workflows (validation, apply, rollback), operational actions (Status, Restart, Disable, Enable), discovery, inventory, current-settings, and history/job-detail remain fully intact and are not affected by the Wi-Fi feature addition.
