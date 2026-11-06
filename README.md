<p align="center">
  <img src=".github/assets/wheel-convert.png" alt="Bergamote's conversion wheel" width="300">
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-3a6ea5?style=flat-square">
  <img alt="Windows 10+ (preview)" src="https://img.shields.io/badge/Windows-10%2B%20preview-3a6ea5?style=flat-square">
  <img alt="Shared Rust core" src="https://img.shields.io/badge/core-Rust-5e92cc?style=flat-square">
  <img alt="Menu bar app" src="https://img.shields.io/badge/menu%20bar-only-5e92cc?style=flat-square">
  <img alt="No network access" src="https://img.shields.io/badge/network-none-82b899?style=flat-square">
  <img alt="App Sandbox" src="https://img.shields.io/badge/App%20Sandbox-on-82b899?style=flat-square">
</p>

<p align="center"><b>Drag a file. Tap ⇧. Drop it on a slice.</b><br>A radial file converter that lives in your macOS menu bar, now on Windows too.</p>

<p align="center">
  <a href="https://loanallard.github.io/Bergamote/">Website</a> ·
  <a href="https://github.com/LoanALLARD/Bergamote/releases/latest">Download</a> ·
  <a href="#download-and-install">Install</a>
</p>

---

You have a scan to send as a PDF, an iPhone photo that has to be a JPEG, a contract whose author
and location data you would rather not share. Each of these means opening an app, hunting through
menus, exporting, renaming, and hoping nothing went to the cloud along the way.

**Bergamote** puts all of it under your cursor. Start dragging any file, tap a modifier key, and a
wheel of actions opens right where you are: convert, compress, anonymize, make searchable. Drop the
file on a slice and the result appears **next to the original**, in the same folder. There is no
window to manage and no Dock icon: Bergamote runs quietly in the menu bar.

Nothing leaves your computer. On the Mac, the app is sandboxed **without any network
entitlement**, so this is enforced by macOS, not just promised. A Windows version, built on the
same core, is in preview.

## What it looks like

<p align="center">
  <img src=".github/assets/wheel-convert.png" alt="Conversion wheel for three PNG files" width="300">
  &nbsp;&nbsp;
  <img src=".github/assets/wheel-tools.png" alt="Tools wheel for four PDF files" width="300">
</p>

<p align="center"><sub>The conversion wheel (⇧) for three PNG files, and the tools wheel (⌘) for four PDFs.</sub></p>

<p align="center">
  <img src=".github/assets/menu-bar-panel.png" alt="Bergamote's menu bar panel" width="320">
</p>

<p align="center"><sub>The menu bar panel: a reminder of the gesture, the last result, settings.</sub></p>

## Features

- 🎯 **Radial menu anywhere.** Drag files from Finder or any app, tap ⇧ or ⌘ (or hold it before you start dragging), drop on a slice.
- 🔄 **Conversions.** Images to PNG, JPEG, HEIC, AVIF, TIFF, GIF, BMP or PDF; PDF pages to images; Word, RTF and text to PDF and back.
- 🗜 **Compression.** Photos resized and re-encoded, PDF images optimized; nothing is written if there is nothing to gain.
- 🕶 **Anonymization.** Strips EXIF, GPS location and camera data from photos, author and title from PDFs, while keeping photos the right way up.
- 🔎 **Searchable PDFs and text.** Adds an invisible OCR text layer to scans, or extracts the text of any document, with Apple's on-device Vision OCR.
- 📁 **Results stay where you work.** Output is written next to the original, never over it (`photo 2.jpeg` if needed), without opening Finder.
- 🪶 **Menu bar only.** No window, no Dock icon. A soft click marks each slice as you move across the wheel.
- 🔒 **Private by design.** No account, no network access, no telemetry.

## The wheel

The slices adapt to the files you drag. A format macOS cannot write on your system is not offered.

| Wheel | Files | Slices |
|---|---|---|
| **Convert** (⇧) | Images | PNG · JPEG · HEIC · AVIF · TIFF · GIF · BMP · PDF |
| | PDF | Pages as PNG / JPEG / HEIC · TXT |
| | Word, RTF, text | PDF · DOCX · RTF · TXT |
| | Images and PDFs together | PDF (merged) · TXT |
| **Tools** (⌘) | Images, PDF | Compress · Anonymize · Searchable · Merge · Text |
| | Word, RTF, text | Text |

Keys can be changed in **Settings**, where you can also turn the click sound on or off.

On Windows the keys are **Shift** (convert) and **Ctrl** (tools), and the wheel offers what Windows
can do natively: images to PNG, JPEG, TIFF, GIF, BMP or PDF; PDF pages to images; compression and
anonymization of images; anonymization of PDFs; merging; text extraction with Windows OCR.
HEIC, WebP and AVIF files can be read when their Microsoft Store image extensions are installed.

## Download and install

**Requirements:** macOS 14 Sonoma or later, on Apple silicon or Intel; or Windows 10 (1809) or
later, x64. The interface is currently in French.

### Mac, from a release

1. Download the latest `Bergamote-x.y.z.zip` from the [Releases](https://github.com/LoanALLARD/Bergamote/releases/latest) page.
2. Unzip it and move **Bergamote.app** to your **Applications** folder.
3. Open it. Release builds are not notarized yet, so the first time macOS may refuse to open the
   app: right-click it and choose **Open**, or go to **System Settings › Privacy & Security** and
   click **Open Anyway**.
4. A pie icon appears in the menu bar. The first time the wheel saves a result, macOS asks you to
   allow a folder: choose your **home folder** once and every folder inside it is covered. You can
   revoke it in Settings.

To start Bergamote with your Mac, add it in **System Settings › General › Login Items**.

### Windows (preview)

Each build of the `main` branch produces a self-contained `Bergamote.exe` (no .NET install needed),
available from the **Bergamote-windows-x64** artifact of the latest
[CI run](https://github.com/LoanALLARD/Bergamote/actions/workflows/ci.yml). Run it: a pie icon
appears in the notification area. The executable is not signed yet, so SmartScreen may ask you to
confirm with **More info › Run anyway**. Starting with Windows can be turned on in Settings.

### From source

Both apps need [Rust](https://rustup.rs) to build the shared core.

**Mac** (Xcode 16 or later):

```bash
git clone https://github.com/LoanALLARD/Bergamote.git
cd Bergamote
rustup target add aarch64-apple-darwin x86_64-apple-darwin
mac/scripts/make-app.sh      # builds the core, then mac/build/Bergamote.app (sandboxed, ad hoc signed)
open mac/build/Bergamote.app
```

For development, `swift run --package-path mac Bergamote` runs the app outside the sandbox, and
`mac/Package.swift` opens directly in Xcode. Run `mac/scripts/build-core.sh` again after changing
the core.

**Windows** (.NET 8 SDK):

```powershell
git clone https://github.com/LoanALLARD/Bergamote.git
cd Bergamote
dotnet run --project windows/Bergamote.Windows   # cargo builds the core automatically
```

## Quick start

1. Launch Bergamote. Its pie icon appears in the menu bar.
2. In Finder, start dragging an image or a PDF and keep the mouse button down.
3. Tap **⇧** for the conversion wheel or **⌘** for the tools wheel. You can also hold the key before you start dragging.
4. Drop the file on a slice. The result appears next to the original.

## How it works

```
core/      Rust: gesture state machine, wheel geometry, slice catalog, file naming,
           centre texts, click sound. Exposed through a small C ABI (core/include).
mac/       Swift 6 menu bar app. Links the core as an XCFramework; conversions with
           ImageIO, PDFKit, CoreText and Vision.
windows/   C# / .NET 8 notification-area app (WPF). Calls the core with P/Invoke;
           conversions with WIC, Windows.Data.Pdf, Windows OCR, PDFsharp and PdfPig.
docs/      The website.
```

- **One behaviour, two native apps.** Everything that decides *what* the wheel does lives in the
  shared core, so both apps open on the same gesture, offer the same slices, name files the same
  way and play the same click. Each app declares what its platform can convert, and the core
  hides the slices it could not run. File conversion itself stays native on each system.
- **Gesture detection.** A small state machine watches the mouse button, the drag and the
  modifier keys 20 times per second: the drag pasteboard on the Mac, the system drag threshold on
  Windows. On the Mac, App Nap is disabled while it runs so that detection stays instant when
  Bergamote is in the background. On Windows, the wheel opens invisible under the cursor and only
  appears once the drag brings files over it, so dragging text or a window never shows it.
- **Sandbox-friendly file access.** Dropping files on the wheel grants the sandboxed app access to
  exactly those files. Writing the result next to them needs one folder permission, asked once and
  stored as a security-scoped bookmark.
- **System frameworks only.** Conversions use ImageIO, PDFKit, CoreText and AppKit, and OCR uses
  Vision: no bundled converters, no external services, a small universal binary.

## Privacy

Bergamote has no network entitlement: macOS blocks every connection, whatever the code does. The
only files it writes are the results you ask for, next to their originals. Its settings, including
folder permissions, live in `~/Library/Containers/com.example.bergamote/` and can be reviewed and
revoked in Settings.

## Development

```bash
cargo test --manifest-path core/Cargo.toml                       # shared core
swift test --package-path mac                                    # Mac: gesture, catalog and conversion tests
dotnet test windows/Bergamote.Core.Tests                         # .NET wrapper of the core (runs on Mac too)
dotnet test windows/Bergamote.sln                                # everything Windows, on Windows
```

Mac extras, from the `mac/` folder:

```bash
BERGAMOTE_SNAPSHOT_DIR=build/snapshots swift test     # also renders the wheels and the menu bar panel
swift scripts/make-samples.swift SampleDocs           # fictitious PDFs, scan, image, .docx and .txt to try
scripts/package-release.sh                            # universal .zip for GitHub Releases
```

[CI](.github/workflows/ci.yml) runs the core tests and lint on Linux, builds and tests the Mac app
on macOS, and tests and publishes the Windows app on Windows.

The website is a single static page in [`docs/`](docs/), published with GitHub Pages from the
`main` branch. Preview it locally with `python3 -m http.server --directory docs`.

To debug the gesture on the Mac, launch with `open mac/build/Bergamote.app --args -wheel.debug YES` and follow
`/usr/bin/log stream --predicate 'subsystem == "com.example.bergamote"'`. With
`-wheel.demo conversion`, the wheel opens on its own after two seconds to test the display.

## Roadmap

- Notarized, signed releases, and a signed Windows installer
- Option panels for tools (compression level, output format)
- Start at login from Settings on the Mac
- PDF compression and searchable PDFs on Windows
- English interface

## License

No license has been chosen yet. Until one is added, all rights are reserved by the author.
