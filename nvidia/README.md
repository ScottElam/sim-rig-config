# NVIDIA Configuration

Driver settings for the MSI Gaming Trio OC RTX 5080, optimised for triple 1440p 180Hz sim racing and simultaneous OBS streaming.

## Driver

| Item | Value |
|---|---|
| Driver version | 596.49 |
| Install type | Clean install (DDU first) (did not do) |
| NVIDIA App | Installed |
| GeForce Experience | Not installed |
| ShadowPlay / Telemetry | Disabled via scheduled tasks (see `Invoke-InstalledPrograms.ps1`) |
| NVIDIA Virtual Audio | Removed |
| Added FrameView | Will use for performance analysis |

---

## System → Display → Scaling

| Setting | Value | Notes |
|---|---|---|
| Mode | **No Scaling** | Running native 1440p — no scaling occurs; this is the cleanest default |
| Scaling Device | **GPU** | Irrelevant at native resolution, but GPU is the correct default |

---

## System → Display → Performance (GPU Tuning)

| Setting | Value | Notes |
|---|---|---|
| Automatic Tuning | **Off** | Auto-OC varies clock speeds dynamically, causing microstutter in sim racing. Stable clocks are preferred over variable peak clocks |
| Fan Speed Target | **Default (Auto)** | 5080 thermals are adequate on the auto curve. Revisit only if GPU temps climb during long endurance stints |

---

## System → Display → G-Sync / Variable Refresh Rate

| Setting | Value | Notes |
|---|---|---|
| G-Sync Compatible | **On — windowed and full screen** | Enable on all three MAG 32CQ6F displays |
| 4th monitor (HDMI) | Not applicable | G-Sync Compatible requires DisplayPort; HDMI display is excluded |

> **Prerequisite:** G-Sync Compatible only works over **DisplayPort**. Confirm the three gaming monitors are connected via DP cables, not HDMI. The 4th monitor on HDMI runs as a standard display.

---

## Windows — GPU Preference

In **Windows Settings → System → Display → Graphics**, set GPU preference for `LeMansUltimate.exe` to **High Performance (RTX 5080)**.

---

## Graphics → Global Settings

These are the baseline settings applied to all applications. LMU-specific overrides (if any) go in a per-game profile.

| Setting | Value | Notes |
|---|---|---|
| Low Latency Mode | **Ultra** | Just-in-time frame submission; critical for direct-drive wheel feel on the ClubSport Formula V2.5 |
| Power Management Mode | **Prefer Maximum Performance** | Prevents GPU downclocking on long straights and low-load track sections |
| Max Frame Rate | **175 fps** | Keeps frames inside the G-Sync operating range; 5 fps below 180Hz avoids VSync handoff stutter |
| Vertical Sync | **On** | Driver-level ceiling used *in combination with* G-Sync. Always set VSync to **Off** in-game |
| Anisotropic Filtering | **16x** | Negligible cost on a 5080; significantly sharpens track surface textures at racing speeds |
| Texture Filtering — Quality | **High Performance** | Removes extra filtering passes; in-game MSAA handles edge quality |
| Smooth Motion | **Off** | AI frame interpolation adds latency — directly harmful for sim racing input response |
| Image Scaling | **Off** | Running native 1440p on a 5080; upscaling is unnecessary |
| Antialiasing — Mode | **Application-Controlled** | Let LMU set MSAA 4x in-game |
| MFAA | **On** | Pairs with in-game MSAA 4x to deliver approximately 8x visual quality at near-zero extra cost |
| Background Application Performance | **Off (default)** | This is a frame rate cap for background apps. Off is correct — OBS encodes via dedicated NVENC and does not compete with the 3D pipeline, so capping background frame rates provides no benefit |
| Shader Cache Size | **Unlimited** | LMU compiles shaders frequently on the rFactor 2 engine; prevents first-lap hitches at a new track |

---

## G-Sync + VSync + Frame Cap (confirmed config)

| Layer | Setting |
|---|---|
| NVIDIA App — G-Sync | **On** (windowed and full screen, DP monitors only) |
| NVIDIA App — VSync | **On** (driver-level ceiling) |
| NVIDIA App — Max Frame Rate | **175 fps** |
| In-game LMU — VSync | **Off** |

The driver-level VSync acts as a ceiling: if frames burst above 175, the driver caps them cleanly without tearing. G-Sync handles all frame delivery below that ceiling. The in-game VSync being off prevents the game engine from adding its own queue on top of this.

---

## NVIDIA Reflex

NVIDIA Reflex is **not an NVIDIA App setting**. It is an **in-game option** inside LMU's graphics settings menu. See `lmu/` for in-game graphics settings.

Target value: **On + Boost**

---

## 4th Monitor (HDMI — Streaming / System)

- Used for OBS, Crew Chief, TinyPedal, and general system tasks during racing sessions
- Not G-Sync capable via HDMI — runs as a standard Windows display throughout
- LMU's native triple-screen mode spans the three DP monitors and leaves this display as an independent Windows desktop — no special configuration needed
- Set **Windows primary display** to one of the 180Hz DisplayPort monitors, not the HDMI display, to avoid the desktop compositor defaulting to the HDMI refresh rate

---

## NVIDIA Inspector Profiles

> Export profiles from NVIDIA Inspector and commit the `.nip` files here.

| Profile | Game | Notes |
|---|---|---|
| lmu-profile.nip | Le Mans Ultimate | See `lmu/` for in-game graphics settings |
