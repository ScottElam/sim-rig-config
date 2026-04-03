# LMU Configuration

Game config files for Le Mans Ultimate.

## Version

| Item | Value |
|---|---|
| LMU version | _fill in_ |
| 0.1 | Initial commit |
| 0.2 | Adding new monitor config changes, FOV, etc. |

## FOV and monitor setup
- Old monitors were Asus 24", 60hz, PB238Q
- Old vFOV was 44deg?
- New monitors will be triples (currently 1 defective)
- MSI 32", 1440p, 180hz, 0.5ms, HDR400, Curved 1500R, bezel 9mm
- Eye distance is 76cm (to 78cm)
- Tools say monitor angle should be 52deg, vFOV 29.4deg
- Set monitor mount arms at 60deg
- vFOV 33deg min in BMW to get the whole dash
- FOV tools
-   https://dinex86.github.io/FOV-Calculator/
-   https://simracingenthusiast.com/fov-calculator/

## Config Files

> Commit sanitized config files to `config/`. Exclude `player.json` and `PlayerCustomization.json` (personal account data).

| File | Purpose |
|---|---|
| controller.json | Wheel and button bindings |
| graphicOptions.json | Display and graphics settings |
| audioOptions.json | Audio settings |

## Notes

- Car setups live in `setups/` — see `setups/README.md` for naming convention
