# Building & installing M-Cam (native iOS) from Windows — no Mac to own

A native iPhone app can only be *compiled* on macOS and *installed* with Apple's
signing. You don't own a Mac, but you don't have to buy one — you can rent a Mac
in the cloud for a few minutes, or let a free cloud service build it, then install
to your iPhone from Windows. Both routes below end with the app on your phone,
using the **full camera**: real RAW/ProRAW, up to **48MP**, true manual control.

Two honest facts up front:
- **You need an Apple ID** (free is fine). A free Apple ID means the app works for
  **7 days**, then you re-install it (one click in Sideloadly) to renew. A paid
  Apple Developer account ($99/yr) removes the 7-day limit.
- **Installing needs the iPhone plugged into the Windows PC by USB.**

---

## Route A — Codemagic (free cloud build) + Sideloadly (recommended, ~20 min once)

You never touch a Mac. A cloud service compiles it; you install from Windows.

### 1. Put the project on GitHub
- Make a free GitHub account if you don't have one.
- Create a new repository (e.g. `mcam-native`), **Add file → Upload files**, and
  upload the whole `LeicaStyleCam` folder's contents (including `codemagic.yaml`,
  the `Sources` folder, `Resources`, and `project.yml`). Commit.

### 2. Build the .ipa on Codemagic
- Go to **codemagic.io**, sign in with GitHub, and add your repository.
- It will detect `codemagic.yaml`. Start the **"M-Cam unsigned IPA"** workflow.
- When it finishes (a few minutes), download the **`MCam.ipa`** artifact to your PC.

### 3. Install to your iPhone from Windows with Sideloadly
- Install **iTunes** (the Apple version from apple.com, needed for the USB driver)
  and **Sideloadly** (sideloadly.io) on your Windows PC.
- Plug your iPhone in with a USB cable; trust the computer on the phone.
- Open Sideloadly, drag **`MCam.ipa`** onto it, enter your **Apple ID**, click
  **Start**. It signs the app with your Apple ID and installs it.
- On the phone: **Settings → General → VPN & Device Management** → tap your Apple
  ID → **Trust**. Also turn on **Developer Mode** (Settings → Privacy & Security
  → Developer Mode) and restart if asked.
- Launch M-Cam, allow camera + photo access, shoot.

To renew after 7 days: plug in, open Sideloadly, Start again.

---

## Route B — Rent a cloud Mac (if you'd rather use Xcode directly)

- Rent a Mac by the hour/month: **MacinCloud**, **MacStadium**, or **AWS EC2 Mac**
  (~$1–2/hr or ~$20–30/mo). You control it from Windows through a browser or
  Remote Desktop.
- On that Mac: install **Xcode** (free, Mac App Store), then either open the
  project with XcodeGen (`brew install xcodegen && xcodegen generate`) or create a
  new iOS App and add the `Sources` files (see README.md).
- Build an **.ipa** (Product → Archive → Distribute → Development/Ad-hoc, or the
  same `xcodebuild` command from `codemagic.yaml`), download it to Windows, and
  install with **Sideloadly** exactly as in Route A step 3.
- (The cloud Mac can't see your physically-connected iPhone, so you still install
  from Windows with Sideloadly rather than straight from Xcode.)

---

## What you get that the web version can't do

| Capability | Web app | This native app |
|---|---|---|
| Full-resolution stills (up to 48MP) | No (≤ ~4K) | **Yes** |
| RAW / ProRAW (DNG) | No | **Yes** |
| True manual ISO / shutter / focus / WB | Simulated | **Real sensor control** |
| Natural (de-sharpened) rendering | Approximate | Via RAW + your own processing |
| Film looks baked into the JPEG/HEIC | Yes | **Yes** (RAW kept clean) |

The look engine (`Sources/LeicaLook.swift`) already bakes the look into the
processed file while saving the RAW untouched, so you keep a full-quality
negative.

---

## If a build fails
Send me the exact error text from Codemagic (or Xcode) and I'll fix the code.
I can't compile Swift on my side, so the first build is where small SDK-version
tweaks sometimes surface — they're quick to fix once I see the message.
