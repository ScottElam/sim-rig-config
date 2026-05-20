# sim-rig-config

Configuration backups, scripts, and notes for my sim racing PC build and streaming setup.

## System Overview

| Component | Spec |
|---|---|
| CPU | AMD Ryzen 7 9850X3D 4.7ghz 8-core Single CCD |
| GPU | MSI Gaming Trio OC RTX 5080 |
| Motherboard | MSI MAG X870E Tomahawk MAX WiFi PZ |
| Memory | Corsair Vengance 32 GB DDR5-6000 CL36 (2x16) |
| Drives | Samsung 990 EVO Plus 2tb w/MB heatsink |
| | Samsung 0100 Pro 2tb w/heatsink |
| Power | Corsair HX1000i |
| Case | Corsair Air 5400 |
| Cooling | Corsair Titan AIO Liquid CPU Cooler |
| | 9 x Corsair LX-120 Fans |
| | Corsair iCue Software |
| Displays | MSI MAG 32CQ6F |
| | Triple 2K 1440p @ 180 Hz, 0.5ms, Curved 1500R |

## Sim Rig

| Component | Spec |
|---|---|
| Chassis | Advanced Sim Racing ASR 3 - Aluminum profile 3"/1.5" |
| Monitor Stand | Sim Lab Freestanding Vario™ Triple monitor mount |
| Wheel Base | GT DD Extreme / Clubsport DD+ |
| Wheel | GT DD Extreme |
| Wheel | Clubsport Formula v2.5 with Podium Advanced Paddle Module |
| Pedals | Clubsport Pedals V3 with throttle damper kit and brake performance kit |

## Repo Structure

```
sim-rig-config/
├── hardware/       Full parts list, firmware versions, cable notes
├── windows/        OS hardening scripts, service configs, tweaks
├── nvidia/         Driver settings, inspector profiles
├── obs/            Scene collections and streaming profiles
├── icue/           Fan curves and RGB profiles
├── crewchief/      Config and voice pack notes
├── tinypedal/      UI layout and widget config
├── lmu/            Game config and car setups
├── bios/           BIOS version notes and key settings
├── stream-deck/    Button profiles and layout exports
└── fanatec/        FFB profiles and button mapping notes
```

## Notes

- All configs are sanitized — no personal paths, license keys, or credentials
- See `.gitignore` for what is intentionally excluded
