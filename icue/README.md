# iCUE Configuration

Fan curves and RGB profiles for the Corsair build.

## Hardware Managed by iCUE

| Device | Role |
|---|---|
| Corsair Titan AIO | CPU cooling — pump + radiator fans |
| Corsair Air 5400 case fans | Case airflow |
| Corsair HX1000i PSU | Power monitoring (Zero RPM mode: enabled) |

## Fan Curve Strategy

- **Case fans** are controlled by **GPU temperature** (iCUE can read GPU temp natively)
  - Rationale: CPU is water-cooled; GPU is the primary heat source affecting case temps
- **AIO fans** are controlled by **coolant/liquid temperature**
- **HX1000i Zero RPM** mode left at default (fans off at low load)

> Export iCUE profiles as `.cueprofile` files and commit them here.

| Profile File | Purpose |
|---|---|
| _fill in_.cueprofile | Racing / full load |
| _fill in_.cueprofile | Idle / low load |

## AIO Thermal Thresholds

| Threshold | Value | Notes |
|---|---|---|
| Coolant temp — fan ramp start | _fill in_ °C | — |
| Coolant temp — fans at 100% | _fill in_ °C | — |
| ⚠️ Coolant shutdown threshold | **≥ 60°C** | Do NOT set below 45°C |

## Notes

- AIO coolant shutdown threshold must be set high enough to allow recovery, not trigger too early
- DDR5 module temps monitored separately via HWiNFO64 (SPD sensor is a proxy, not die temp)
