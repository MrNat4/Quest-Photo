# Verification record — 2026-10-27

Engine: Godot 4.6.3.stable.official.7d41c59c4, Linux x86_64.
Reproduce with `./tools/test.sh`; logs are written to `build/checks/`.
The script uses temporary user/config/cache directories and detects Godot script
errors even if the engine process exits 0. It leaves actual user photos/settings
untouched.

| Check | Result | What this establishes |
| --- | --- | --- |
| Godot project import | Pass | Resource import and GDScript loading |
| Calibration assets | 4 tests pass | Eye order, actual pixel disparity/vertical alignment, grid, JPEG decode |
| Core | 58 checks pass | State limits/validation/persistence, file headers, size caps, real loading, independent SBS resizing |
| SBS export | 30 checks pass | PNG/JPG readback pixels, eye order, crop/pan/zoom/convergence, dimensions, error handling |
| Viewer integration | 97 checks pass | Scene wiring, inputs, synthetic tracker controls, focus/tracking loss, corrupt-file navigation, async export and shutdown |
| Main-scene startup | Pass, 10 frames | No runtime script error with dummy renderer |
| Touch map generator | Pass | Eight actions and sixteen bindings survive resource serialization |
| Build script shell syntax | Pass | Bash syntax only |
| Android dependency preflight | Expected failure, exit 2 | Accurately identifies absent tools; no APK created |
| Godot Android export | Blocked, exit 1 | Missing matching templates, Java SDK, Android SDK/adb/apksigner |
| GLES shader / per-eye rendered pixels | Not tested | No graphics display/backend available |
| Quest installation and runtime | Not tested | No APK or headset available |

The editor reports blocked TCP debug listeners in this sandbox; the test runner
allows only those exact import-time infrastructure messages, while recording
them. Runtime tests finish without engine errors. Missing Android build-tools are
reported during editor import. Neither issue is hidden as an app test failure.

## Defects found and fixed

- Resizing a whole SBS bitmap mixed colors across the eye boundary. Eyes are now
  resized independently; pure-color boundary regressions pass.
- PNG dimension preflight now validates the IHDR marker and length.
- Corrupt next-photo navigation formerly retried the same item forever; navigation
  advances while retaining the last successfully displayed image.
- Left trigger values after tracking loss could incorrectly modify right-stick
  behavior; modifier and eye-swap actions now require tracked controllers.
- A GDScript inferred-type error in dynamic label layout was fixed during import.

## Headset acceptance once an APK exists

Follow [BUILD.md](BUILD.md), then [STEREO_TEST.md](STEREO_TEST.md). Those steps
are release gates, not checks claimed as passed here. Record:

- APK SHA-256, Quest OS, refresh rate and install/startup results.
- LEFT/RIGHT label isolation, green/yellow/blue depth ordering, 2D toggle and
  eye-swap behavior. Stop and resolve eye routing before integrating AI outputs.
- Every control in README; tracking loss while grabbing; system menu focus loss;
  suspend/resume; recenter standing and seated; restart with Wi-Fi disabled.
- Import a JPEG and PNG using the documented debug workflow, plus a corrupt image
  followed by a valid image. Confirm errors do not trap navigation.
- Export full/half PNG and JPG, retrieve files, verify crop and eye order in a
  conventional stereo viewer. Confirm switching photos during export does not
  change the file being written and quitting waits for the current write.
- Memory/frame time on largest accepted inputs, export latency, thermal behavior,
  readability and discomfort. Report exact source image dimensions and file size.

No desktop/synthetic check establishes hardware input compatibility, stereo
comfort, performance, or successful APK installation. No model inference tests
have run because no depth model/runtime is present.
