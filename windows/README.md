# win11-gaming-hardening

Windows 11 optimisation and hardening scripts for a high-performance sim-racing and streaming PC.

## Build Target

| Component | Spec |
|---|---|
| CPU | AMD Ryzen 9850X3D |
| GPU | NVIDIA RTX 5070 |
| Motherboard | MSI MAG X870E Tomahawk MAX WiFi |
| Memory | 32 GB DDR5 |
| Case | Corsair Air 5400 |
| Displays | Triple 2K @ 180 Hz |

## Free Alternatives

| Site | Description |
|---|---|
| https://christitus.com/downloads/ | $10 - Chris Titus, performance, privacy, security, anti-bloat, custom iso, SW update, etc. |
| https://www.hellzerg.com/ | Suspicious: Gaming focus, with privacy |
| https://www.oo-software.com/en/shutup10/features | Privacy and Security focus |
| https://www.windowscentral.com/microsoft/windows-11/how-to-fine-tune-your-pc-with-the-sophia-script-for-windows-11 | |
| https://github.com/farag2/Sophia-Script-for-Windows | RU/UA: The most powerful PowerShell module for fine-tuning Windows on GitHub |
| https://winaero.com/the-list-of-winaero-tweaker-features/ | Recommended by Kevin |
| https://atlasos.net/ | |
| https://github.com/raphire/win11debloat | |



## Software Stack

Le Mans Ultimate · OBS · Crew Chief · TinyPedal · Fanatec ClubSport Formula V2.5 · Elgato Stream Deck · iCUE · Mosquitto MQTT · ProtonVPN · Proton Drive · Discord · 1Password · Git

---

## Prerequisites

- PowerShell 5.1 or later
- Run as **Administrator**
- Allow local scripts:
  ```powershell
  Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
  ```

---

## Order of Operations

Run scripts in this order. Each step builds on the last.

| Step | Folder | Script | Purpose |
|---|---|---|---|
| 1 | `1-SystemComponents` | `Invoke-SystemComponents.ps1` | Remove unused Windows features and AppX packages |
| 2 | `2-InstalledPrograms` | `Invoke-InstalledPrograms.ps1` | Disable NVIDIA telemetry; report software recommendations |
| 3 | `3-Services` | `Invoke-Services.ps1` | Disable and throttle unnecessary Windows services |
| 4 | **Check:** `4-PrivacySecurity` | `Invoke-PrivacySecurity.ps1` | Registry-based privacy and security hardening |
| 5 | **Check:** `5-Performance` | `Invoke-Performance.ps1` | Power plan and system performance tweaks |

---

## Usage

Every script accepts a `-Mode` parameter:

| Mode | Behaviour |
|---|---|
| `Check` | Audits current state vs target. **No changes made.** Exits with code 1 if drift found. |
| `Apply` | Makes changes, reports what was done, saves a backup for Revert. |
| `Revert` | Restores the previous state from the backup saved by Apply. |

Scripts **1, 3, 4, 5** support all three modes.
Script **2** supports `Check` and `Apply` only (uninstall is not reversible).

The Performance script also accepts `-PowerPlan`:

| Value | Effect |
|---|---|
| `Performance` | High Performance power plan (default, recommended for 9850X3D) |
| `Eco` | Balanced power plan |

### Example workflow

```powershell
# Audit — no changes
.\1-SystemComponents\Invoke-SystemComponents.ps1 -Mode Check

# Apply when satisfied
.\1-SystemComponents\Invoke-SystemComponents.ps1 -Mode Apply

# Roll back if needed
.\1-SystemComponents\Invoke-SystemComponents.ps1 -Mode Revert
```

```powershell
# Performance with plan selection
.\5-Performance\Invoke-Performance.ps1 -Mode Apply -PowerPlan Performance
.\5-Performance\Invoke-Performance.ps1 -Mode Apply -PowerPlan Eco
```

---

## Backups

Scripts 1, 3, 4, and 5 write a `backup.json` to their own folder when run with `-Mode Apply`. These files are machine-specific and are excluded from git (see `.gitignore`). Running `-Mode Apply` a second time safely overwrites the previous backup.

---

## Utilities

Runtime tools kept in the `Utilities` folder. These are not part of the hardening pipeline and can be run at any time independently. All require **Administrator**.

| Script | Purpose |
|---|---|
| `Launch-LeMansUltimate.ps1` | Launch Le Mans Ultimate via Steam with a custom process priority and CPU affinity mask |
| `Get-ProcessAffinityReport.ps1` | Snapshot every running process and report its priority class and CPU affinity |

### `Launch-LeMansUltimate.ps1`

Fires the Steam `applaunch` command for Le Mans Ultimate, waits up to 90 seconds for the game process to appear, then applies the configured priority and affinity. If the game is already running the settings are applied to the existing process immediately.

Key variables at the top of the script:

| Variable | Default | Notes |
|---|---|---|
| `$SteamExe` | `C:\Program Files (x86)\Steam\steam.exe` | Update if Steam is installed to a non-default path |
| `$SteamAppId` | `1537430` | Le Mans Ultimate Steam App ID |
| `$ProcessName` | `LeMansUltimate` | Game executable name without `.exe` |
| `$TargetPriority` | `High` | `Idle \| BelowNormal \| Normal \| AboveNormal \| High \| RealTime` — avoid `RealTime` |
| `$AffinityMask` | `0xFFFE` | Bitmask of allowed cores. `$null` = OS default (all cores) |
| `$WaitTimeoutSec` | `90` | Seconds to wait for the process before giving up |

**Affinity mask quick reference** (adjust upper bound to your logical core count):

| Mask | Cores assigned |
|---|---|
| `0xFFFE` | Cores 1–15 — skips Core 0, leaving it free for Windows/background (recommended for 9850X3D) |
| `0xFFFF` | Cores 0–15 (all 16 cores) |
| `0x00FF` | Cores 0–7 (P-cores only on a hybrid layout) |
| `$null` | OS default — no affinity change applied |

```powershell
.\Utilities\Launch-LeMansUltimate.ps1
```

### `Get-ProcessAffinityReport.ps1`

Queries every running process and prints a colour-coded table of priority class and CPU affinity, followed by a summary count and a priority legend. Useful for verifying that the launcher applied its settings correctly, or for auditing any other process on the system.

Key variables at the top of the script:

| Variable | Default | Notes |
|---|---|---|
| `$FilterName` | `""` | Partial name filter — e.g. `"LeMans"` to show only matching processes. Empty = all |
| `$HideNormal` | `$false` | Set to `$true` to suppress processes running at Normal priority on all cores |
| `$SortBy` | `Name` | `Name \| PID \| Priority \| Affinity` |

```powershell
# Full system report
.\Utilities\Get-ProcessAffinityReport.ps1

# Verify Le Mans Ultimate specifically
# (edit $FilterName = "LeMans" in the script, or run as-is and scan the output)
.\Utilities\Get-ProcessAffinityReport.ps1
```

Output columns:

| Column | Description |
|---|---|
| Process Name | Executable name |
| PID | Process ID |
| Priority | Windows priority class (colour-coded: Red = RealTime, Yellow = High, Cyan = AboveNormal, Grey = Normal/lower) |
| Affinity | Hex bitmask of allowed logical cores |
| Cores Assigned | Human-readable core list or `ALL (n)` if using every core |

---

## Important Notes

- **Mosquitto MQTT** is kept at Automatic start. Fanatec uses MQTT for wheel telemetry; it also serves the home automation stack.
- **Crew Chief** requires the Microsoft Server Speech Platform — that package is not touched.
- **EasyAntiCheat** (`EasyAntiCheat_EOS`) is left at Manual — required by Le Mans Ultimate.
- **AMD 3D V-Cache Optimizer** (`amd3dvcacheSvc`) is left at Automatic — critical for 9850X3D cache partitioning behaviour.
- **Fanatec Wheel Service** (`FWPnpService`) is left at Automatic.
- **All Corsair services** (iCUE, CpuId, DeviceControl, DeviceLister) are left untouched.
- **Discord** and **1Password** processes and services are not modified.
- Scripts do **not** disable Windows Defender, SmartScreen, or UAC. These remain fully active.
