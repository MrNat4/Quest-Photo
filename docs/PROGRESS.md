# Progress log

## 2026-10-27 — resumed inspection

The workspace contained no project files, source repository, APK or progress log.
The preceding attempt had inspected the toolchain and stalled at a dependency
network request. No existing application implementation was replaced.

Confirmed Godot 4.6.3 and a Java runtime; no full JDK, Android SDK, export templates,
working graphics display or headset. The managed network policy reports
unrestricted access, but shell downloads cannot connect to the configured proxy.
The earlier cancelled network permission request was not repeated.

## 2026-10-27 — first source milestone

Created `quest-photo` with a Godot/OpenXR scene, shader, explicit Touch action map,
sample photograph, labelled known stereo fixture, controller and keyboard
transforms, original/stereo switching, eye swapping, convergence and validated
per-photo view settings. Added local JPEG/PNG enumeration, desktop picker,
dimension/file limits, error reporting and corrupt-file navigation recovery.

Added bounded full/half SBS PNG/JPG export on a background thread, taking an
immutable view snapshot. Current crop/zoom/pan/convergence and eye order are
preserved. Physical screen transforms are excluded from image exports. Ordinary
photos still yield identical eye views; no depth is fabricated.

Added MIT application license, asset attribution, reproducible calibration and
XR-map generation, strict test runner, Android build/preset scripts, build/device
instructions, known issues, roadmap and this continuation log.

Validation: four asset tests and 185 Godot assertions (58 core, 30 export,
97 viewer) pass. Main scene starts for ten headless frames. Real Android export
attempt exits 1 due to absent dependencies. No APK exists. Shader output, physical
Quest controllers, performance and all headset acceptance remain unverified.
See TESTING.md for evidence scope and fixed defects.

## Next session

1. Read README, this log, KNOWN_ISSUES and TESTING; run `tools/test.sh`.
2. Restore build download connectivity or use a machine with the dependencies in
   BUILD.md. Run the build preflight and export; retain signing key and APK hash.
3. Run the stereo headset acceptance and fix deployment/rendering/controller
   issues before calling Milestone 1 complete.
4. Begin offline depth model/runtime integration in ROADMAP Milestone 2, measuring
   real Quest latency and peak memory. Do not substitute a synthetic depth image
   for successful on-device inference.
5. Add Android document picker and VR thumbnail browsing. The early export and
   settings work covers part of Milestone 3; full editing projects are still due.

Future editing, GIF/video and exploratory reconstruction remain unimplemented.
Maintain the working viewer and tests when adding those features.
