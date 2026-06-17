# OBS Setup Guide — Sim Racing

**Rig:** RTX 5070 · Ryzen 9850X3D · Triple 2560×1440 @ 180Hz · ClubSport Formula V2.5
**Simulator:** Le Mans Ultimate (LMU)
**Helper Apps:** Crew Chief, TinyPedal (overlay only — not captured in OBS)
**Control Surface:** Elgato Stream Deck

---

## Table of Contents
1. [Scenes](#1-scenes)
2. [Sources — Racing Scene Stack](#2-sources--racing-scene-stack)
3. [Configuring Each Source](#3-configuring-each-source)
4. [Scene Layout](#4-scene-layout)
5. [Audio Configuration](#5-audio-configuration)
6. [Fixing Game Audio Not Capturing](#6-fixing-game-audio-not-capturing)
7. [Output & Encoding Settings](#7-output--encoding-settings)
8. [Video Settings](#8-video-settings)
9. [Stream Deck Hotkeys](#9-stream-deck-hotkeys)
10. [Source Management](#10-source-management)

---

## 1. Scenes

| Scene | Purpose |
|---|---|
| **Pre-Race / Lobby** | Webcam large or full scale, "Starting Soon" graphic, optional background music via Media Source |
| **Racing (Main)** | Game capture full canvas, webcam in corner |
| **Post-Race / Replay** | Game capture for highlights, larger webcam, text source with session results or social handles |

---

## 2. Sources — Racing Scene Stack

The Sources panel renders **bottom to top**. Add in this order:

```
🔒 Webcam          (Video Capture Device)
🔒 LMU             (Display Capture — center monitor)
```

> **Crew Chief and TinyPedal** run as on-screen overlays but are not captured as OBS sources. They are visible to the driver only.

---

## 3. Configuring Each Source

### Game Capture — Center Monitor

> Game Capture in "Capture specific window" mode may capture all three monitors with LMU. Use **Display Capture** instead.

- Click **+** → **Display Capture**
- Select your **center monitor** from the display dropdown
- This captures only that screen, ignoring the side monitors

### Webcam (Video)

- Click **+** → **Video Capture Device**
- Select your webcam from the device list
- Leave resolution at default
- **Audio Output Mode:** Set to **Disabled** — audio is captured separately (see Section 5)
- Position in the bottom-right corner of the canvas
- Hold **Alt** and drag source edges to crop non-destructively
- Right-click → **Filters** → add **Crop/Pad** to clean up dead space around the frame
- Right-click → **Filters** → add **Color Correction** to tune brightness and contrast

---

## 4. Scene Layout

```
┌─────────────────────────────────────┐
│                                     │
│        LMU — Display Capture        │
│           (full canvas)             │
│                                     │
│                      ┌──────────┐   │
│                      │  WEBCAM  │   │
└──────────────────────┴──────────┘
```

- Game capture fills the entire 2560×1440 canvas
- Webcam sits bottom-right at roughly 426×240 (1/6 scale)

Once positioned, right-click each source → **Lock** to prevent accidental repositioning.

---

## 5. Audio Configuration

### Webcam as Microphone

The **Video Capture Device** source includes an audio mode option, but in testing this fails to record reliably. Capture audio as a separate source instead.

**Step 1 — Add the audio source:**
- Click **+** → **Audio Input Capture**
- Name it `Webcam Mic`
- Device: Select your webcam from the dropdown — it appears as a separate audio device (e.g., *"Logitech BRIO Audio"*)
- Confirm the Video Capture Device source has **Audio Output Mode set to Disabled** to avoid duplicates

**Step 2 — Add filters:**

Right-click `Webcam Mic` in the Audio Mixer → **Filters** → click **+** to add each in this order:

#### Noise Suppression
| OBS Label | Value |
|---|---|
| Method | RNNoise *(use Speex if RNNoise is unavailable)* |

#### Noise Gate
| OBS Label | Value |
|---|---|
| Close Threshold | -40 dB |
| Open Threshold | -26 dB |
| Attack Time | 25 ms |
| Hold Time | 200 ms |
| Release Time | 150 ms |

#### Compressor
| OBS Label | Value |
|---|---|
| Ratio | 4:1 |
| Threshold | -18 dB |
| Attack | 6 ms |
| Release | 60 ms |
| Output Gain | 0 dB |
| Sidechain Source | None |

#### Limiter
| OBS Label | Value |
|---|---|
| Threshold | -1 dB |
| Release | 60 ms |

**Step 3 — Assign audio tracks:**

Right-click `Webcam Mic` in the Audio Mixer → **Advanced Audio Settings:**

| Track | Assignment | Content |
|---|---|---|
| Track 1 | ✅ | Everything mixed (streaming / quick export) |
| Track 2 | ✅ | Webcam Mic isolated (for post-edit voice control) |

Set **Desktop Audio** to Track 1 ✅ and Track 3 ✅.

**Step 4 — Verify recording output tracks:**

Go to **Settings → Output → Recording tab** → confirm **Track 1** is checked.

> Both the source track assignment (Step 3) and the recording output must have matching tracks enabled. If only one is set, the audio will appear on the meter but will not be recorded.

**Step 5 — Set target levels:**

| Source | Target Level |
|---|---|
| Webcam Mic | Peaks around -12 dB |
| Desktop Audio (game) | -18 to -20 dB |

### Crew Chief Audio

Crew Chief outputs voice calls through the Windows default audio device and is captured automatically by Desktop Audio alongside LMU game sound. No additional configuration is needed.

---

## 6. Fixing Game Audio Not Capturing

If game audio shows no meter activity in OBS, work through these steps in order:

**Step 1 — Check Windows default playback device**
- Open **Sound Settings → Advanced → More sound settings → Playback tab**
- Confirm your headset or speakers are set as the **Default Device**
- OBS Desktop Audio captures whatever Windows routes as default — if LMU outputs to a different device, OBS won't hear it

**Step 2 — Set Desktop Audio explicitly in OBS**
- Go to **Settings → Audio**
- Change **Desktop Audio** from "Default" to your specific playback device
- Click Apply

**Step 3 — Check LMU's in-game audio settings**
- Confirm LMU is outputting to the same device OBS is monitoring

**Step 4 — Use Application Audio Capture as a fallback**
- Click **+** → **Application Audio Capture**
- Select Le Mans Ultimate from the application list
- This captures LMU audio directly regardless of Windows routing

---

## 7. Output & Encoding Settings

Go to **Settings → Output → Output Mode: Advanced**

> The RTX 5070's Blackwell NVENC encodes AV1 on a dedicated chip separate from the render pipeline. P6 preset has no impact on LMU framerate.

### Streaming

| Setting | Value |
|---|---|
| Encoder | NVENC AV1 |
| Rate Control | CBR |
| Bitrate | 8,000–10,000 Kbps |
| Keyframe Interval | 2 seconds |
| Preset | P6 (Quality) |

### Local Recording

| Setting | Value |
|---|---|
| Encoder | NVENC AV1 |
| Rate Control | CQP |
| CQ Value | 18–22 |
| Preset | P6 (Quality) |

> CQP allocates more bits during busy traffic and fewer on clean straights — better quality than CBR for local recordings where bandwidth is not a constraint.

---

## 8. Video Settings

Go to **Settings → Video**

| Setting | Value |
|---|---|
| Base (Canvas) Resolution | 2560×1440 |
| Output (Scaled) Resolution | 2560×1440 for recording / 1920×1080 for streaming |
| Common FPS Values | 60 |

---

## 9. Stream Deck Hotkeys

All scene switching and recording/streaming controls are mapped to the Elgato Stream Deck.

**Recommended mappings:**

| Stream Deck Button | OBS Action |
|---|---|
| Button 1 | Switch to Pre-Race scene |
| Button 2 | Switch to Racing scene |
| Button 3 | Switch to Post-Race scene |
| Button 4 | Start / Stop Recording |
| Button 5 | Start / Stop Streaming |
| Button 6 | Studio Mode toggle (preview before switching) |

Configure via the **Elgato Stream Deck app → OBS Studio plugin** — install the plugin from within the Stream Deck app's store if not already present.

> Enable **Studio Mode** in OBS (bottom-right of the main window) to preview scene switches on the Stream Deck's screen before they go live.

---

## 10. Source Management

- Name every source clearly: `LMU - Display Capture`, `Webcam - Video`, `Webcam Mic`
- Right-click each source → **Lock** once layout is finalized
- Group related sources: right-click → **Group Selected Items** to keep the Sources panel tidy
- For the Pre-Race scene, add a **Media Source** pointed at a music folder for background audio between sessions
- For text elements ("Starting Soon", "In the Pits…"), use **Text (GDI+)** sources assigned only to the scenes where they are needed

---

## Notes

- **AMD CPPC:** The 9850X3D is an 8-core single-CCD chip. AMD does not use efficiency cores — all cores are identical Zen 5 cores with 3D V-Cache. Thread scheduling is handled automatically by AMD CPPC (Collaborative Power and Performance Control). No manual affinity pinning is needed or recommended.
- **LMU focus loss:** Clicking away from the center monitor during a session triggers LMU's background throttle. Use Stream Deck buttons rather than mouse clicks to switch OBS scenes mid-race.
- **TinyPedal:** Requires LMU to be running and in a session before its overlay window initializes. If capturing TinyPedal ever becomes necessary, use Window Capture with Windows Graphics Capture method and Allow Transparency enabled.

---

*Repository: sim-rig-config/obs*
*Last updated: June 2026*
