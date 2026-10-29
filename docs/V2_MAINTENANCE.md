# Version 2 maintenance: grip modifiers and gallery access

## Apply to the working Gradle project

This is a 0.2.0 maintenance patch, not a Version 3 feature release. Keep your
working Gradle export preset, Android build directory, signing key, SDK settings,
OpenXR renderer and package ID. Those user-local Gradle changes are not present
in the cloud snapshot and have not been recreated or overwritten.

Copy these runtime files into the existing project, preserving relative paths:

- `openxr_action_map.tres`
- `scripts/main.gd`
- `scripts/photo_gallery.gd`

The other changed files are tests, action-map generator and documentation. Do not
replace your working `export_presets.cfg` with the baseline non-Gradle preset in
the complete source tree. Re-import with Godot 4.6.3, rebuild with your existing
Gradle procedure and install as an update with the same key. Fully restart the
application: OpenXR actions are loaded when the session initializes.

## Root cause and correction

Godot 4.6.3 OpenXRInterface::create_action checks duplicate names against names
already registered internally. The earlier `grip_pose` action is internally
renamed `grip`; the later float action named `grip` is consequently skipped.
This accounts for working controller poses/face buttons but zero grip input.
The analog action is now `squeeze`, still bound to both hands' `input/squeeze/value`.
The pose remains `grip_pose`, and XRController3D.pose remains `grip`. All modifier
and grab reads use `squeeze`. No thresholds, face-button mappings, stereo shader,
OpenXR initialization or image transforms changed.

Source: Godot 4.6.3 modules/openxr/openxr_interface.cpp, create_action lines
363–395: https://github.com/godotengine/godot/blob/4.6.3-stable/modules/openxr/openxr_interface.cpp

## Diagnostics

Help now shows L/R squeeze values and pose-tracking status, refreshed twice a
second. Fully squeeze the left grip: its value should rise above 0.65. Event
snapshots log input presence, value, interaction profile, focus and gallery state.
The latest 100 events are saved in `user://controller-gallery-diagnostics.json`
and printed with `QuestPhoto diagnostic` in Godot/logcat. Notices include import,
load and export errors; thumbnail failures are recorded separately. This diagnostic
file can contain displayed filenames/error messages; review it before sharing.
No network telemetry exists. The ring file is written on events, not each frame.

## Tests and device checklist

Run `tools/test.sh` / `python tools/run_checks.py`. The new regression test models
the engine's pose-name rewrite and duplicate check, validates both squeeze
bindings and uses synthetic tracker signals to exercise modifier dispatch into
the actual six-cell gallery. Existing import, caching, format/layout, image
selection/persistence and export suites continue to run. Headless tests do not
establish physical control behavior or Android document-picker availability.

When the Quest is available:

1. Check that Y alone still toggles Help; X alone still toggles 2D/stereo.
2. In Help check left squeeze rises above 0.65, then hold it and press Y. The
   six-thumbnail gallery should replace the viewer without toggling Help.
3. Verify thumbstick focus, A/right-trigger selection, B return. Grip+X changes
   layout; grip+A goes to the previous image; right grip still grabs the screen.
4. Open Import, select actual photos, verify thumbnails, select a photo, restart
   and confirm persistence. Check native picker cancel and return-to-VR.
5. Recheck zoom, roll, convergence and stereo calibration. Lose/reacquire tracking
   and open/close the system menu to test focus guards.
6. If failure remains, capture the squeeze display and diagnostic JSON/logcat.

No headset test or new APK is claimed here. Android toolchain is still absent
in this workspace. GIF, animated WebP, video and AI conversion remain deferred.

Automated result for this commit: 4 asset tests, 415 Godot assertions, storage
import suite, scene startup and Bash syntax pass. `git diff --check` passes.
Action-map generator validates 8 actions and 16 bindings.
