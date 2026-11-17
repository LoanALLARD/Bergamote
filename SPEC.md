# Bergamote: cross-platform specification

Working specification for the Mac, Windows and Linux versions. It states what each part must do
and how it is verified; the README stays the user-facing document.

## 1. Product

Drag files, tap a modifier key (or hold it before dragging), drop them on a slice of the wheel that
opens under the cursor. The result is written next to the original, never over it. The app has no
main window: it lives in the menu bar (Mac), the notification area (Windows) or the tray (Linux).

The three apps must behave the same wherever the platform allows it: same gesture, same slices
for the same files, same output names, same texts, same click sound.

## 2. Architecture

```
core/      Rust library. Everything that decides what the wheel does.
mac/       Swift app. Links the core as a static library (XCFramework).
windows/   C# app (WPF). Calls the core as a DLL (P/Invoke).
linux/     Rust app (GTK 4, X11). Uses the core as a crate. Conversions in pure Rust.
```

Rule: a decision that must be identical on the three systems belongs to the core. Anything that
touches the operating system (input, windows, file conversion engines, settings storage, login
items) stays in the app, written with the platform's native tools.

### 2.1 Core (Rust)

| Module | Responsibility |
|---|---|
| `detector` | Gesture state machine fed with samples (button, drag generation, modifiers). |
| `geometry` | Slice under a point, centre angle of a slice. |
| `catalog` | Slices for a wheel, a set of files and what the platform can do. |
| `naming` | `name.ext`, then `name 2.ext`…: never overwrites. |
| `summary` | Centre texts: files summary, result message, byte counts. |
| `i18n` | Languages (French, English), language resolution, every shared text. |
| `sound` | The click, synthesised as a WAV. |
| `ffi` | C ABI (`core/include/bergamote_core.h`): strings in UTF-8, rich values in JSON. |

Platform abilities, declared by each app in the catalog request:

- `writable`: image formats the app can write.
- `readable` (optional): image formats the app can read. An image the app cannot read gets no wheel.
- `capabilities` (optional, all when absent): `convert_images`, `render_pages`, `text_to_pdf`,
  `convert_text`, `extract_text`, `ocr`, `make_searchable`, `compress`, `compress_pdf`,
  `strip_metadata`, `merge_pdf`.
  - Extracting text from images needs `ocr`.
  - Compressing a PDF needs `compress_pdf`.

Languages:

- `fr` and `en`. The stored preference is `system`, `fr` or `en`.
- `system` resolves from the OS locale: French when it starts with `fr`, English otherwise.
- The core holds the current language. Slice titles, centre texts and every shared interface text
  (`bgm_text(key)`) follow it. Byte counts follow it too (`39,7 Mo` / `39.7 MB`).
- Pure functions take the language as a parameter; only the C ABI reads the global.

### 2.2 Apps

| | Mac | Windows | Linux |
|---|---|---|---|
| Presence | Menu bar extra | Notification area icon | Tray icon (StatusNotifierItem) and settings window |
| Convert key / tools key | ⇧ / ⌘ | Shift / Ctrl | Shift / Ctrl |
| Gesture source | Drag pasteboard change count | Cursor beyond drag threshold | Cursor beyond drag threshold (X11) |
| Files known | At open (pasteboard) | When the drag enters the wheel | When the drag enters the wheel |
| Images | ImageIO | WIC | `image` crate |
| PDF render / text | PDFKit | Windows.Data.Pdf / PdfPig | `hayro` / `pdf-extract` |
| PDF write | PDFKit | PDFsharp | `lopdf` |
| OCR | Vision | Windows.Media.Ocr | Tesseract, when installed |
| Settings | UserDefaults | `%APPDATA%\Bergamote\settings.json` | `~/.config/bergamote/settings.json` |
| Start at login | `SMAppService.mainApp` | `HKCU\…\Run` | `~/.config/autostart/bergamote.desktop` |

On Windows and Linux the wheel opens invisible under the cursor and appears once a drag carrying
files enters it; a drag without files never shows it. Drops are always copies.

Linux specifics:

- X11 sessions. Under Wayland the app runs through XWayland and says in its settings window that
  the gesture needs an X11 session: Wayland does not let an app watch the pointer globally.
- Launching the app again opens the settings window; `--background` starts without it (login);
  `--autostart on|off` sets start at login from a script.
- The wheel is an override-redirect window positioned through X11; without a compositor it is
  shown directly with the common slices.

## 3. Settings (all platforms)

| Setting | Values | Default |
|---|---|---|
| Wheel enabled | on / off | on |
| Conversion key | platform modifiers | Shift |
| Tools key | platform modifiers | ⌘ on Mac, Ctrl elsewhere |
| Click sound | on / off | on |
| Start at login | on / off | off |
| Language | System / Français / English | System |

Changing the language applies immediately, without restarting.

## 4. Build pipelines

- `ci.yml`, on every push and pull request:
  - **core**: tests and clippy (Linux).
  - **mac**: universal core, Swift tests, a drag and drop on the runner's desktop, universal `.zip`.
  - **windows**: .NET tests (core wrapper and conversions), self-contained `Bergamote.exe`, then
    a drag and drop on the runner's desktop (`windows/scripts/smoke-test.ps1`).
  - **linux**: tests, clippy, drags and drops under Xvfb (`linux/scripts/smoke-test.sh`), release
    build, `.deb` and `.tar.gz`.
- `release.yml`, on a `v*` tag: the same builds, then a GitHub release carrying the three packages.
- A failing step repeats its telling lines as an annotation (`.github/scripts/run.sh`).

## 5. Verification

| What | How |
|---|---|
| Core behaviour | `cargo test` in `core/` |
| Same behaviour through each binding | Swift tests, .NET tests |
| Mac conversions and rendering | Swift tests, snapshot tests |
| Windows conversions | .NET tests on a Windows runner |
| Windows app | On a Windows runner: start-up, simulated drag, Shift, drop on a slice, converted file; settings through UI Automation, start at login (Run entry written, then executed as a sign-in would), language switch |
| Linux conversions | `cargo test` in `linux/` (pure Rust, any OS) |
| Linux app | Docker with Xvfb: gesture, both wheels, drops from a test source and from a real file manager, settings, start at login, language switch (`smoke-test.sh`); and in a full XFCE session: opening the session starts the app from its autostart entry, drag from Thunar, tray icon registered with the panel (`desktop-test.sh`) |
| Mac app | Swift tests, snapshots of every screen in both languages, and on the macOS runner a simulated drag, Shift, drop on a slice and converted file (`mac/scripts/smoke-test.swift`; it needs the accessibility permission) |

## 6. Out of scope for now

Signed and notarised packages, PDF compression and searchable PDFs on Windows, text-to-PDF outside
the Mac, a native Wayland gesture.
