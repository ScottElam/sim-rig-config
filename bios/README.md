# BIOS Configuration — MSI MAG X870E Tomahawk MAX WiFi

## Version

| Item | Value |
|---|---|
| BIOS version | _fill in_ |
| Release date | _fill in_ |
| Update method | MSI Center / M-Flash |

## Key Settings Changed from Default

| Setting | Value | Location in BIOS | Reason |
|---|---|---|---|
| XMP / EXPO | Enabled | OC / Memory | DDR5 rated speed |
| Resizable BAR | Enabled | PCIe settings | GPU performance |
| Secure Boot | Enabled | Security | — |
| TPM | Enabled | Security | Windows 11 requirement |
| Fan control | See iCUE | — | Managed via iCUE instead |
| CPU PPT/TDC/EDC | _fill in_ | OC | X3D thermal management |

## Screenshots

> Add BIOS screenshots here as `.png` files for key pages.
> Git is not ideal for large images — keep them small and few.

## Notes

- X3D chips benefit from PPT/TDC/EDC reduction to control heat
- Do not enable PBO curves aggressively on X3D — different behavior than non-X3D
