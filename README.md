> **Windows local-model preparation (development revision 1):** Start with [these instructions](docs/WINDOWS_MODEL_PREPARATION.md). Double-click `Prepare-Models.cmd` in a separate checkout. No AI model has been validated here; this is not a completed 0.3.0 release. Keep your working 0.2.0 installation.

> Version 2 maintenance: see [application instructions and headset checks](docs/V2_MAINTENANCE.md). Preserve your working local Gradle setup; historical baseline instructions below do not supersede it.

# Quest Photo 0.2.0

Godot **4.6.3** offline OpenXR photo viewer for Meta Quest 3. This continues the
0.1.0 viewer: the user confirmed VR launch, per-eye rendering, calibration depth,
sample images and most controls on a physical Quest. The OpenXR configuration,
action map and stereo shader are preserved. **New 0.2.0 Android import/gallery
behavior still requires headset acceptance.** No AI conversion is included yet.

## Build

Open `project.godot` with your existing Godot 4.6.3 installation, install matching
Android templates, and use the **Quest 3** export preset. Keep your existing
Android SDK/JDK paths and signing key. Export `build/quest-photo-0.2.0-debug.apk`.
Package remains `org.questphoto.viewer`, version code is 2. Updating with the same
key preserves the library; uninstalling or clearing data deletes private copies.
No plugin, Gradle build, Google services or broad storage permission was added.
Detailed Windows instructions: [BUILD.md](docs/BUILD.md).

## Gallery and importing

1. **Hold left grip and press Y** to open/return to the gallery.
2. Move either thumbstick to highlight one of six photographs or a button.
   Release the stick between moves. Press **A** or the right trigger to activate.
3. Select **Import**. In Android's system chooser, select one or multiple local
   images from Pictures or Download. Use the system Back action to cancel.
4. Imported photos are copied into the app's private persistent library. The
   gallery refreshes automatically; restarting the app keeps completed imports.
5. Previous/Next buttons change gallery pages. **B** or Close returns to viewing.
   Refresh rescans the library. Layout changes the last highlighted photo's mode.

The system chooser uses Godot's built-in Android Storage Access Framework.
No ADB transfer is needed for importing. Whether a working chooser is present
and usable in VR depends on Quest firmware; see [STORAGE.md](docs/STORAGE.md)
for the precise native-picker limitation and troubleshooting. The pipeline
validates files, copies them in a worker, reports failures, and deduplicates by
content hash. Up to 64 images per batch, 32 MiB and 32 megapixels per source.
Cancel copying with B; completed imports remain. Originals are never modified.

Six thumbnails are requested per page. RAM cache holds 18 textures and disk cache
128 thumbnails; a single thumbnail worker avoids decoding the collection at once.
Selected user photographs decode off the scene thread in VR. Very large libraries
still require a directory/metadata scan at refresh; performance needs measurement
on Quest. Names longer than 28 characters are abbreviated on thumbnail tiles.

## Image formats and layouts

Runtime buffer decoders support JPEG/JPG, PNG, static WebP and BMP, with JPEG EXIF
orientation. Unsupported/corrupt/oversized files report errors. Animated WebP is
rejected explicitly. GIF, animated WebP playback and video remain deferred.

| Filename suffix before extension | Detected layout |
| --- | --- |
| ordinary name | 2D |
| `.sbs` | Full SBS, left eye first |
| `.half-sbs` | Half-width SBS |
| `.ou` | Full top/bottom, left eye above |
| `.half-ou` | Half-height top/bottom |

Use Layout repeatedly to cycle 2D → full SBS → half SBS → full top/bottom → half
top/bottom. Choices persist per photo. This is explicit filename detection, not
AI recognition. Half layouts restore the intended aspect; each eye is resized
independently and normalized to the existing full-SBS renderer. Top/bottom
requires even height and SBS even width. Manual layout selection does not infer
stereo depth from an ordinary photograph.

## Viewer controls

| Input | Action |
| --- | --- |
| Left grip + Y | Gallery / return |
| A / left grip + A | Next / previous photo |
| X / left grip + X | 2D-stereo toggle / cycle layout |
| B / Y | Reset / toggle help |
| Right stick | Size and roll |
| Left stick | Pan after zooming |
| Left trigger + right stick | Zoom and convergence |
| Right grip | Grab/position/rotate screen |
| Left stick click | Recenter |
| Right stick click | Calibration |
| Both triggers + A | Swap eyes |
| Right / left trigger + right stick click | Full / half SBS export |
| Both triggers + right stick click | PNG/JPG export format |

Desktop: G gallery, O import, M layout, N/P next/previous, T calibration,
Space 2D/stereo, W/S size, Q/E roll, +/- zoom, arrows pan, I/J/K/L position,
U/D distance, R reset, brackets convergence, V preview eye, F swap, H help,
F5 refresh, F6/F7 full/half export, F8 export codec. In gallery use arrows,
Enter and Escape. Desktop native import needs an available system file chooser.

View preferences and layout choices persist. World placement recenters each
launch. Exports save under `user://exports` and preserve crop, zoom, convergence
and eye order, with full-resolution eyes capped at 2048 pixels per side. Physical
screen size/roll/position are excluded. Exports in 2D duplicate the original view;
they are not AI conversions. Android destination-picker export remains future work.

## Verification and continuation

Run `./tools/test.sh` on Linux, or `python tools/run_checks.py` with Godot on PATH
and Pillow installed (Windows skips Bash-only syntax validation). The app itself
requires neither Python nor Pillow. Tests cover real image pixels, persistence,
layout normalization, cache bounds, import logic, synthetic controllers and
integrated asynchronous flows. A packaged PCK was also run on Linux.

Each launch runs tiny embedded codec checks and writes
`user://runtime-image-report.json`; desktop displays the result and startup logs
include it. These run inside the APK too, providing evidence on your device
without relying on editor texture imports.

See [TESTING.md](docs/TESTING.md), [KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md),
[ROADMAP.md](docs/ROADMAP.md), and [PROGRESS.md](docs/PROGRESS.md).
Code: MIT. Calibration artwork: CC0. Sample photograph: public domain;
[attribution](assets/ATTRIBUTION.md). The `.bin` sample copies retain original
encoded bytes for reliable CPU decoding in exported packages.
