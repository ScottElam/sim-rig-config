# OBS Setup Guide — Sim Racing
### Platform: RTX 5070 · Ryzen 9850X3D · Triple 1440p @ 180Hz · ClubSport Formula V2.5
### Simulator: Le Mans Ultimate (LMU) · Helper Apps: Crew Chief, TinyPedal

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
9. [CPU Optimization — 9850X3D](#9-cpu-optimization--9850x3d)
10. [Hotkeys & Scene Switching](#10-hotkeys--scene-switching)
11. [Source Management](#11-source-management)

---

## 1. Scenes

Create three scenes to cover your full broadcast:

| Scene | Purpose |
|---|---|
| **Pre-Race / Lobby** | Webcam large or full scale, "Starting Soon" graphic, optional background music via Media Source |
| **Racing (Main)** | Game capture full canvas, webcam corner, TinyPedal overlay on top |
| **Post-Race / Replay** | Game capture for highlights, larger webcam, text source with session results or social handles |

---

## 2. Sources — Racing Scene Stack

Add sources in this order. The Sources panel renders **bottom to top**, so the list below reflects the correct stacking order (TinyPedal on top, game at the bottom):

```
🔒 TinyPedal       (Window Capture)
🔒 Webcam          (Video Capture Device)
🔒 LMU             (Display Capture — center monitor)
```

---

## 3. Configuring Each Source

### Game Capture — Center Monitor

> **Note:** Game Capture (specific window mode) may capture all three monitors with LMU. Use **Display Capture** instead and select your center monitor specifically from the dropdown.

- Click **+** → **Display Capture**
- Select your **center monitor** from the display dropdown
- This captures only what is on that screen, ignoring the other two monitors

### Webcam (Video)

- Click **+** → **Video Capture Device**
- Select your webcam from the device list
- Leave resolution at default (or set to 1280×720 minimum if default is lower)
- **Audio Output Mode:** Set to **Output audio to OBS** *(see Section 5 for why this may not work and the workaround)*
- Position bottom-right corner of the canvas
- Hold **Alt** and drag source edges to crop non-destructively
- Right-click → **Filters** → add **Crop/Pad** to clean up dead space around frame edges
- Right-click → **Filters** → add **Color Correction** to tune brightness and contrast

### TinyPedal

> TinyPedal only fully renders its overlay window once it has a live data feed from LMU. Always launch LMU into a session first, confirm TinyPedal widgets are visible on screen, then add the capture source in OBS.

- Click **+** → **Window Capture**
- Window: Select **TinyPedal**
- Capture Method: **Windows Graphics Capture** *(not BitBlt — this is required for transparency)*
- Check **Allow Transparency** if the option appears
- If a black background appears, confirm Windows Graphics Capture is selected — switching to it removes the background

---

## 4. Scene Layout

```
┌─────────────────────────────────────┐
│                                     │
│        LMU — Display Capture        │
│           (full canvas)             │
│                                     │
│   [TinyPedal — transparent overlay] │
│                      ┌──────────┐   │
│                      │  WEBCAM  │   │
└──────────────────────┴──────────┘
```

- Game capture fills the entire 2560×1440 canvas
- TinyPedal sits on top, transparent background
- Webcam sits bottom-right at roughly 426×240 (1/6 scale of 1440p)

Once positioned, right-click each source → **Lock** to prevent accidental repositioning.

---

## 5. Audio Configuration

### Webcam as Microphone

The **Video Capture Device** source includes an **Audio Output Mode** option. In testing, "Output audio to OBS" mode may show on the meter but fail to record — the reliable method is to capture audio as a separate source.

**Step 1 — Add the audio source separately:**
- Click **+** → **Audio Input Capture**
- Name it `Webcam Mic`
- Device: Select your webcam from the dropdown — it appears as a separate audio device (e.g., *"Logitech BRIO Audio"*)
- If you enabled audio in the Video Capture Device source, disable it there to avoid duplicates: set Audio Output Mode to **Disabled**

**Step 2 — Add filters:**

Right-click `Webcam Mic` in the Audio Mixer → **Filters** → click **+** to add each filter in this order:

#### Noise Suppression
| OBS Label | Value |
|---|---|
| Method | RNNoise *(choose Speex if RNNoise is unavailable)* |

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

| Track | Content |
|---|---|
| Track 1 ✅ | Everything mixed (streaming / quick export) |
| Track 2 ✅ | Webcam Mic isolated (for post-edit voice control) |

Set **Desktop Audio** to Track 1 ✅ and Track 3 ✅.

**Step 4 — Verify track assignment is enabled in recording output:**

Go to **Settings → Output → Recording tab** → confirm **Track 1** checkbox is enabled. Both the source track assignment and the recording output must have the same track checked, or the audio will show on the meter but not be recorded.

**Step 5 — Set target levels:**

Watch the mixer while talking and adjust faders:

| Source | Target Level |
|---|---|
| Webcam Mic | Peaks around -12 dB |
| Desktop Audio (game) | -18 to -20 dB |

### Crew Chief Audio

Crew Chief outputs voice calls through the Windows default audio device and is captured automatically by Desktop Audio alongside LMU game sound. No additional configuration is needed. If you want Crew Chief on its own isolated track for editing, add an **Application Audio Capture** source pointed at Crew Chief and assign it to Track 4.

---

## 6. Fixing Game Audio Not Capturing

If game audio shows no activity in the OBS mixer, work through these steps in order:

**Step 1 — Check Windows default playback device**
- Open **Windows Sound Settings → Advanced → More sound settings → Playback tab**
- Confirm your headset or speakers are set as the **Default Device**
- OBS Desktop Audio captures whatever Windows routes as the default — if LMU is outputting to a different device, OBS won't hear it

**Step 2 — Set Desktop Audio explicitly in OBS**
- Go to **Settings → Audio**
- Change **Desktop Audio** from "Default" to your **specific playback device**
- Click Apply

**Step 3 — Check LMU's in-game audio settings**
- In LMU audio settings, confirm it is outputting to the same device OBS is monitoring

**Step 4 — Use Application Audio Capture as a fallback**
- Click **+** → **Application Audio Capture**
- Select Le Mans Ultimate from the application list
- This captures LMU audio directly regardless of Windows routing — the most reliable fix

---

## 7. Output & Encoding Settings

Go to **Settings → Output → Output Mode: Advanced**

> Your RTX 5070's Blackwell NVENC encodes AV1 on a dedicated chip separate from the render pipeline. P6 preset costs nothing in LMU framerate.

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

> CQP allocates more bits during busy traffic and less on clean straights — better quality than CBR for local recordings where bandwidth is not a constraint.

---

## 8. Video Settings

Go to **Settings → Video**

| Setting | Value |
|---|---|
| Base (Canvas) Resolution | 2560×1440 |
| Output (Scaled) Resolution | 2560×1440 for recording / 1920×1080 for streaming |
| Common FPS Values | 60 |

---

## 9. CPU Optimization — 9850X3D

The Ryzen 9850X3D's 3D V-Cache sits on the primary CCD (cores 0–7) and is optimized for gaming workloads. Pinning OBS to the secondary CCD keeps the V-Cache CCD fully available for LMU's physics engine.

- Open **Task Manager → Details tab**
- Find the OBS process → right-click → **Set Affinity**
- Uncheck cores 0–7, leave **cores 8–15** checked
- Click OK

This is optional but worthwhile if you experience any sim stuttering during a stream or recording session.

---

## 10. Hotkeys & Scene Switching

- Go to **Settings → Hotkeys** and assign each scene a dedicated key
- Map **Start/Stop Recording** and **Scene Switch** to buttons on the ClubSport Formula V2.5 via the Fanatec driver — all buttons and rotary encoders are exposed for mapping
- Use a combo that won't be hit accidentally mid-race (a rotary click + button combination works well)
- Enable **Studio Mode** (bottom-right of OBS) to preview scene switches before they go live

---

## 11. Source Management

- Name every source clearly: `LMU - Display Capture`, `Webcam - Video`, `Webcam Mic`, `TinyPedal`
- Right-click each source → **Lock** once the layout is finalized
- Group related sources: right-click → **Group Selected Items** to keep the Sources panel tidy
- For the Pre-Race scene, add a **Media Source** pointed at a music folder for background audio between sessions
- For text elements (stream title, "In the Pits…" messaging), use **Text (GDI+)** sources assigned only to the scenes where they are needed

---

*Last updated: May 2026*
