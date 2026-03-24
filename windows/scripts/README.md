# Windows Scripts & Configuration

PowerShell scripts and notes for OS hardening, service trimming, and performance tuning.

## Scripts

| File | Purpose |
|---|---|
| `debloat.ps1` | Removes unnecessary inbox apps and components |
| `services-config.ps1` | Disables/sets-to-manual non-essential services |
| `privacy-tweaks.ps1` | Telemetry and tracking reduction |
| `performance-tweaks.ps1` | Power plan, timer resolution, scheduler tweaks |

## Run Order

1. `debloat.ps1`
2. `services-config.ps1`
3. `privacy-tweaks.ps1`
4. `performance-tweaks.ps1`
5. Reboot

## Notes

- All scripts require an elevated PowerShell prompt (Run as Administrator)
- Test each script on a snapshot/restore point before applying to bare metal
- Crew Chief dependency: Microsoft Server Speech Platform — **do not remove**
