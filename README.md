# M-Cam — a minimal, Leica-inspired manual camera for iPhone

A clean, stripped-down camera app that shoots with the look baked in, so you
don't have to edit afterward. It gives you full manual control, captures the
sensor's **full resolution (up to 48MP) and RAW/ProRAW**, saves a processed file
alongside, and renders a filmic look live in the viewfinder (what you see is what
gets saved).

> **On Windows with no Mac?** You can still build and install this — see
> **BUILD-ON-WINDOWS.md**. A free cloud service compiles it and you install to
> your iPhone from Windows with Sideloadly. The guide below covers building on a
> Mac (or cloud Mac) directly.

This is original software. It does **not** use Leica's name, logo, red dot, or
any Leica profiles or assets. The "look" is built from scratch using color
theory associated with that style (filmic tone curve, warm-neutral balance,
restrained-but-rich color, micro-contrast). It is for your own personal use.

---

## What it does

- **Minimal interface** — full-bleed viewfinder with corner bright-lines, one
  readout row, one shutter button. Tap a readout to reveal its control.
- **Three looks** — Classic (warm, Kodachrome-leaning), Contemporary (cooler,
  modern), Monochrome (rich B&W). Tap the round look button to cycle.
- **Full manual control**
  - **A / M** modes. In **M** you set shutter and ISO directly.
  - In **A** you set exposure compensation (EV).
  - **Manual focus** with a near↔∞ slider, or tap the viewfinder to focus.
  - **Manual white balance** (temperature in Kelvin + tint), or auto.
- **RAW + processed capture** — `RAW+JPG` saves an untouched DNG *and* a
  look-baked HEIC/JPEG to the same photo. Toggle to `JPG` for processed only.
- **WYSIWYG preview** — the look is applied to the live feed via Metal, so the
  viewfinder matches the saved file.

The RAW file is always saved **clean** (no look applied), so you keep a full-
quality negative if you ever want to edit one.

---

## What you need

- A **Mac** with **Xcode** (free from the Mac App Store).
- An **Apple ID** (free — no paid developer account required for personal use).
- Your **iPhone** and a USB cable.
- iOS **16.0 or newer** on the phone.

> A camera app only runs on a real iPhone, not the Simulator (the Simulator has
> no camera).

---

## Setup — the foolproof way (about 5 minutes)

You don't need any extra tools for this path.

1. **Open Xcode → File → New → Project…**
   - Choose **iOS → App**, click Next.
   - Product Name: `M-Cam`
   - Interface: **SwiftUI**, Language: **Swift**.
   - Pick a Team (your Apple ID — add it under Xcode → Settings → Accounts if
     it isn't there yet). Click Next and save it somewhere.

2. **Add the source files.**
   - In Finder, open this project's `Sources` folder.
   - Select all the `.swift` files and drag them into the Xcode file list
     (the left sidebar), under the app's yellow folder.
   - In the dialog, tick **Copy items if needed** and make sure your app target
     is checked. Click Finish.
   - Xcode created a `ContentView.swift` and a `*App.swift` for you — delete
     those two (right-click → Delete → Move to Trash). Our
     `LeicaStyleCamApp.swift` is the real entry point.

3. **Add the permission strings.** Open the target's **Info** tab and add three
   rows (click the `+`):
   - `Privacy - Camera Usage Description` → `M-Cam uses the camera to take photos.`
   - `Privacy - Photo Library Additions Usage Description` → `M-Cam saves your photos to your library.`
   - (Optional) `Privacy - Microphone Usage Description` → any text.
   > These are also in `Resources/Info.plist` for reference. If a launch crash
   > mentions a missing usage description, it's one of these.

4. **Set the deployment target** (target → General → Minimum Deployments) to
   **iOS 16.0** or lower than your phone's version.

5. **Plug in your iPhone.** Pick it as the run destination at the top of Xcode.
   - On the phone: Settings → Privacy & Security → Developer Mode → **On**
     (iOS 16+), then restart the phone when asked.

6. **Press ▶ (Run).** The first build signs the app with your Apple ID.

7. **Trust the app on the phone.** The first launch shows "Untrusted Developer".
   Go to **Settings → General → VPN & Device Management**, tap your Apple ID,
   and **Trust**. Launch again.

That's it. Grant camera and photo access on first launch and shoot.

---

## Setup — the XcodeGen way (optional, for the technical)

If you'd rather not click through the wizard:

```bash
brew install xcodegen      # once
cd LeicaStyleCam
xcodegen generate
open LeicaStyleCam.xcodeproj
```

Then set your signing Team (target → Signing & Capabilities), plug in the
phone, and Run. The `project.yml` already wires up the sources, Info.plist,
and bundle settings.

---

## Free-Apple-ID limits (worth knowing)

- Apps signed with a free Apple ID **expire after 7 days**. When it stops
  opening, just plug in and press Run again to re-sign it.
- A paid Apple Developer account ($99/yr) removes the expiry and the 7-day
  re-sign chore. Not required.

---

## Tuning the look

All the color lives in `Sources/LeicaLook.swift`, and it's commented so you can
adjust it:

- **Warmth** — the `temperatureTint(...)` call at the top of each look.
- **Contrast / blacks / highlights** — the `filmicToneCurve(...)` points.
  Raise `toeLift` for softer, more "faded film" blacks; lower it for punch.
- **Saturation** — `colorGrade(... saturation:)` (global) and
  `vibranceWarmBias(...)` (protects skin/reds).
- **Split tone** — the `splitTone(...)` shadow/highlight RGB values.
- **Micro-contrast** — `clarity(... amount:)`.
- **Signature hue mapping** — `makeCubeFilter(for:)` builds a procedural color
  cube per look; edit the per-channel math there.

Change a number, re-run, shoot. The viewfinder updates live.

---

## Getting the best image quality from the sensor

Baked into the app's defaults, but worth knowing:

- Shoot **RAW+JPG** and keep the DNG if you ever want a clean negative.
- Keep **ISO low** (100 base) when light allows — less noise, more dynamic range.
- Expose so highlights just avoid clipping; the filmic curve protects them.
- The processed file is written in **Display P3** wide-gamut color.

---

## File map

| File | What it does |
|------|--------------|
| `LeicaStyleCamApp.swift` | App entry point + permission gate |
| `CameraView.swift` | The minimal shooting UI |
| `CameraViewModel.swift` | State bridge between UI and camera |
| `CameraController.swift` | AVFoundation engine: manual controls, RAW + processed capture |
| `CameraPreviewView.swift` | Metal live preview of the processed image |
| `LeicaLook.swift` | **The look engine** — tone, color, split-tone, cube |
| `PhotoSaver.swift` | Saves processed + RAW into Photos |
| `Resources/Info.plist` | Permission strings & app config |
| `project.yml` | Optional XcodeGen spec |

---

## Honest limitations

- The live preview applies the look through Core Image at preview resolution;
  the final still re-applies it at full resolution, so the saved file is sharper
  than the preview.
- AF speed is the iPhone's own system; this app chooses focus modes and points
  but doesn't replace Apple's focusing.
- This has been written to compile against iOS 16+ SDKs, but you may need to
  nudge a deployment setting or a permission string for your exact Xcode
  version — the README's crash notes cover the common ones.
