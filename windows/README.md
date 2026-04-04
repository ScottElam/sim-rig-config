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

## Important Notes

- **Mosquitto MQTT** is kept at Automatic start. Fanatec uses MQTT for wheel telemetry; it also serves the home automation stack.
- **Crew Chief** requires the Microsoft Server Speech Platform — that package is not touched.
- **EasyAntiCheat** (`EasyAntiCheat_EOS`) is left at Manual — required by Le Mans Ultimate.
- **AMD 3D V-Cache Optimizer** (`amd3dvcacheSvc`) is left at Automatic — critical for 9850X3D cache partitioning behaviour.
- **Fanatec Wheel Service** (`FWPnpService`) is left at Automatic.
- **All Corsair services** (iCUE, CpuId, DeviceControl, DeviceLister) are left untouched.
- **Discord** and **1Password** processes and services are not modified.
- Scripts do **not** disable Windows Defender, SmartScreen, or UAC. These remain fully active.
