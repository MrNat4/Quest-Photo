# Quest Photo

An offline Godot 4.6.3 / OpenXR photo viewer under active development for Meta
Quest 3. **Version 0.1.0 is an initial viewer implementation, not a completed
2D-to-3D converter. No APK or physical-headset verification is available yet.**

The current implementation starts directly in a known stereo calibration image.
It also includes a real public-domain sample photograph, JPEG/PNG loading, per-eye
SBS sampling, 2D/stereo switching, zoom, pan, physical scale, rotation, controller
positioning, convergence, eye swapping, and per-photo viewing preferences.
Ordinary photos remain 2D: no AI depth model is bundled or simulated.

## Run and test

Install Godot **4.6.3 stable**. From this directory:

```bash
godot --editor --path . --import --quit
godot --path . --xr-mode off
./tools/test.sh
```

The test script additionally needs Python 3 and Pillow for calibration pixel
checks. Pillow is a development dependency only. The application itself uses
Godot built-ins and has no Internet permission, network client, account system,
Google Play Services, or cloud processing.

For an OpenXR-capable desktop with a working runtime, omit `--xr-mode off`.
See [BUILD.md](docs/BUILD.md) for Android dependencies, build script, and sideload
instructions. Source import and headless tests work in the current environment;
Android builds are blocked by missing toolchain downloads.

## Controls

| Quest controller | Action |
| --- | --- |
| Right A | Next photograph |
| Left X | Toggle original left image / stereo |
| Right B | Reset settings and place screen in front of you |
| Left Y | Toggle control help |
| Right stick up/down | Physical screen size |
| Right stick left/right | Screen rotation |
| Left stick | Pan the image (zoom in first) |
| Hold left trigger + right stick up/down | Image zoom |
| Hold left trigger + right stick left/right | Stereo convergence |
| Hold right grip, move/rotate controller | Position/orient screen |
| Left stick click | Place screen in front of current headset direction |
| Right stick click | Open stereo calibration |
| Both triggers + A | Swap stereo eyes |
| Right trigger + right stick click | Export full SBS |
| Left trigger + right stick click | Export half SBS |
| Both triggers + right stick click | Switch PNG/JPG export format |

Controls remain subject to Quest hardware acceptance testing. A visible help
panel and status label describe current mode and settings. Unsupported ordinary
photo conversion is explicitly labelled `AI conversion pending`.

Desktop controls: O open, N/P next/previous, T calibration, Space 2D/stereo,
W/S physical size, Q/E rotation, +/- zoom, arrows pan, I/J/K/L position, U/D
distance, R reset, brackets convergence, V preview eye, F swap eyes, H help,
F5 refresh library, F6/F7 full/half SBS export, F8 PNG/JPG format, Escape quit.
Desktop preview displays one selected eye;
it does not establish correct headset output.

## Local photographs

The library reads `user://photos`. The absolute path is shown in desktop mode.
Use O to open any JPEG/PNG on desktop. A filename ending in `.sbs.png`, `.sbs.jpg`
or `.sbs.jpeg` is interpreted as **full SBS, left eye first**; other names are
ordinary 2D images. Half-SBS import/aspect detection is not implemented.

On Quest, the first app launch creates its private folder. Until an Android
Storage Access Framework picker is implemented, transfer photos to a debug
build with ADB (paths containing spaces should be quoted):

```bash
adb shell run-as org.questphoto.viewer mkdir -p files/photos
adb shell run-as org.questphoto.viewer sh -c '"cat > files/photos/example.jpg"' < /path/to/example.jpg
```

Restart the app after transfer. The expected Godot Android `user://` location is
`files/`; verify using `adb shell run-as org.questphoto.viewer ls files` on the
first real APK. This workflow requires a debuggable sideloaded build and has not
been exercised against a headset here. It is a developer import workflow, not
the final user-facing file browser.

Images over 32 MiB or 32 megapixels are rejected before decode. The viewer scales
to at most 4096 pixels on either dimension per eye. PNG/JPEG only; animated GIFs,
EXIF autorotation, color-profile management and half-SBS import are not yet
implemented. Loading is synchronous and may pause the viewer for large photos.

Viewing preferences save after changes and on pause/switch. They include zoom,
pan, size, roll, convergence, eye order and stereo mode. World position resets
in front of the user each launch; it is deliberately not restored across rooms.
Original photographs are never overwritten. These preferences are **not** yet
nondestructive depth-editing project files.

## Export

Exports run on a background worker and save to `user://exports`, with unique
filenames and completion/error messages. PNG is the default; JPG uses quality
95. Each full-resolution eye is capped at 2048 pixels per side, preserving aspect.
Full SBS places two full eyes side by side; half SBS halves each eye's horizontal
resolution. Select the corresponding mode in the receiving stereo player.

Zoom, pan, convergence and eye order are applied to exported pixels. Crop
boundaries round to source pixels, so subpixel edge placement may differ slightly
from the shader. Physical screen placement, size and roll are presentation
transforms and are excluded. Exporting an ordinary photo or 2D mode writes two
identical eye views; it does not create depth. Depth adjustments await Milestone 2.

For a debug APK, retrieve an export using its actual filename:

```bash
adb shell run-as org.questphoto.viewer ls files/exports
adb exec-out run-as org.questphoto.viewer cat files/exports/NAME.sbs.png > NAME.sbs.png
```

This retrieval path needs first-device verification. A user-facing Android
destination picker remains planned. Exported half-SBS files are not supported
as correctly proportioned imports by this version.

## Project layout and status

- `scripts/main.gd`: XR lifecycle, scene construction, controller/desktop input.
- `scripts/photo_library.gd`: bounded local loading and library enumeration.
- `scripts/view_state.gd`: validated per-photo settings and persistence.
- `scripts/stereo_export.gd`: bounded offline SBS image export.
- `shaders/stereo.gdshader`: per-eye texture selection and crop/convergence.
- `openxr_action_map.tres`: explicit Touch controller bindings.
- `assets/`: real sample photograph and deterministic stereo fixtures.
- `tests/`: behavioral and pixel tests; no simulated test is called hardware validation.
- [ROADMAP.md](docs/ROADMAP.md), [PROGRESS.md](docs/PROGRESS.md),
  [TESTING.md](docs/TESTING.md), [KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md).

Project code is MIT licensed; generated calibration artwork is CC0-1.0. Sample photo
attribution and third-party licensing are in [assets/ATTRIBUTION.md](assets/ATTRIBUTION.md)
and [THIRD_PARTY.md](docs/THIRD_PARTY.md).
