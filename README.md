# Quest Photo 0.3.3

Offline stereoscopic photo viewer and AI depth converter for **Meta Quest 3**,
using **Godot 4.6.3 Standard** and **OpenJDK 17**. Continues the working **0.3.2**
viewer, gallery, controller and reconstruction foundation. No account, cloud
inference, Google Play Services or subscription is required by the application.

**[Download quest-photo-0.3.3-source.zip](https://github.com/MrNat4/Quest-Photo/releases/download/v0.3.3/quest-photo-0.3.3-source.zip)** ·
[Release and checksums](https://github.com/MrNat4/Quest-Photo/releases/tag/v0.3.3) ·
[Build / update instructions](docs/BUILD_033.md) ·
[Changes, tests and limitations](docs/RELEASE_033.md)

The release ZIP is a **complete source project**, including the compiled
QuestDepth and ONNX Runtime Android AARs and their source/licenses. It does not
need source files or native dependencies from an older release. Official Godot
export templates, private signing keys and your already-converted AI weights are
not redistributed in this archive. Keep your working project and signing key.

## Build with your existing Windows installation

1. Extract the complete ZIP into a **new folder**. Copy your existing validated
   `models` folder into it, including `catalog.json` and the three `.onnx.bin`
   files. No model reconversion or reinstallation.
2. Open `project.godot` in **Godot 4.6.3 Standard**. If needed, install its official
   templates through **Editor → Manage Export Templates → Download and Install**.
   Then use **Project → Install Android Build Template** in this new project.
3. Keep your existing Android SDK and JDK 17 paths in Editor Settings. In the
   **Quest 3** Android preset, verify **Use Gradle Build**, **QuestDepth plugin**,
   **ARM64**, minimum SDK **26**, version name **0.3.3** and APK output
   `build/quest-photo-0.3.3-debug.apk`. Reference version code is **6**; use a code
   higher than your installed APK if your local build counter is already higher.
4. Use the **same package ID and signing key as your working installation**.
   Default identity remains `org.questphoto.viewer`. Restore any custom package
   identity/signing fields through Godot's export UI. Export normally with Godot.
   Do not uninstall or clear application data when installing the update.

Detailed fresh-project and existing-project instructions: [BUILD_033.md](docs/BUILD_033.md).
Do not run the historical 0.3.0 autobuilder or model-preparation launchers for
this update. No new Windows builder is required.

## Current functionality

- Offline V2 Small, V3 Small and V3 Base selection; one inference session at a time.
- Balanced, High Quality and Maximum Quality; cached per-model comparisons and
  original 2D viewing. High and Maximum share compatible inference depth.
- Controller-friendly **pending depth and screen-plane sliders**, with fine taps,
  magnetic held movement and one **APPLY CHANGES** action. Moving sliders does
  not run inference or reconstruction. Depth: 0–4% in 0.05% steps; plane: 0–1 in
  0.01 steps. Current and pending values are shown separately.
- Depth-based left/right reconstruction, convergence and eye swapping; position,
  zoom, size, pan and rotation controls preserved.
- Local image import, six-thumbnail gallery and JPEG, PNG, static WebP and BMP;
  manual 2D, full/half SBS and top/bottom layout selection.
- Full/half SBS PNG/JPEG export to **Pictures/Z-Dim/** using a typed Android
  MediaStore transaction, verified byte-for-byte before success is reported.
- Red processing/export feedback; ordinary settings/instructions remain white.
- Confirmed per-photo/all-cache clearing with storage usage; originals, exports,
  models and settings protected. Raw AI depth stays separate from adjustments.

Open the gallery with **left grip + Y**, AI menu with **left grip + B**. In the
AI menu use up/down to select; on a slider use left/right to adjust. Tap for exact
fine steps, hold to move with snapping, then select **APPLY CHANGES**. A/right
trigger activates buttons; B closes. Help displays the installed app version and
existing viewer controls.

## Validation and limitations

See the release test report for desktop/native build evidence. **0.3.3 has not
been tested on a physical Quest 3.** Simulated-provider tests are not proof of
Quest MediaStore behavior. The exact failing dynamic-JNI call in the reported
0.3.2 export cannot be established from its empty error alone; the new typed
transaction removes that call chain and reports specific operation failures.

Reconstruction guards fix a demonstrated folded-footprint loss without global
depth smoothing. Fine facial depth from 0.3.2 is retained; hair, earrings, missing
background, distorted depth boundaries and flat faces are not universally solved.
Pending Apply can still take tens of seconds at Maximum Quality on your headset.
Plane-only changes also reconstruct, preserving borders and occlusion semantics.

Your real converted models remain local and must be copied with their matching
catalog. No new pretrained-model inference or Quest performance claim is made.
Animated images, video, depth painting and scene reconstruction remain deferred.

## Repository structure

- `scripts/`, `scenes/`, `shaders/`, `openxr_action_map.tres`: complete Godot viewer.
- `scripts/ai/`: inference orchestration, caches, pending controls and comparison.
- `android/plugins/`: required compiled AARs, plugin descriptor and checksums.
- `android_ai/`: project-specific Java/Gradle source, tests and runtime licenses.
- `models/`: model catalog template and official checkpoint license notices.
- `assets/`: sample photograph, stereo calibration and application icon.
- `tests/`, `verification/0.3.3/`: automated checks and recorded results.
- `docs/`: current build/release instructions plus historical project records.
- `tools/`: testing utilities and historical preparation/build tools (not needed
  for normal 0.3.3 Godot export).

Application source: MIT. Model checkpoints: the documented Apache-2.0 Small/Base
variants only. ONNX Runtime: MIT plus included third-party notices. See
[THIRD_PARTY.md](docs/THIRD_PARTY.md). Older branches/releases remain for rollback.
