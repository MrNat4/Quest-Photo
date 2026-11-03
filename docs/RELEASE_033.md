# Quest Photo 0.3.3

Maintenance/refinement release based on the complete working 0.3.2 source, not
0.2.0. The repository main branch and the release package contain the full project.

## Changes

- **Pending depth and screen-plane sliders.** Depth remains 0–4%, now with exact
  0.05-percentage-point taps; plane remains 0–1 in 0.01 steps. Current/pending
  values are separate. Held input adds magnetic snapping at 1% / 0.05 intervals,
  with hysteresis; continuing to hold crosses the magnet. Single taps always
  allow precise values next to a magnet. Only **APPLY CHANGES** reconstructs,
  once for both values, from the current cached depth. No inference is requested
  by either slider or Apply. Failed/cancelled Apply restores displayed settings.
  Switching to a different completed result resets pending values to that result.
- **Typed Android shared exports.** The existing QuestDepth plugin now owns the
  complete MediaStore transaction with typed Java calls. It creates a new pending
  row, streams and closes output, reads it back and compares byte count/SHA-256,
  finalizes IS_PENDING, and verifies its visible name/folder. Errors include the
  operation and exception; failure removes only the row created by that attempt.
  Cleanup failures report the URI. Every attempt has fresh transaction state.
  Existing originals/exports are never opened for writing. Export reads the
  displayed image; it does not invoke AI or reconstruct the converted photograph.
- **Conservative reconstruction guard.** High/Maximum no longer join adjacent
  pixels when their projected interval reverses direction or magnifies beyond
  two pixels per source step. Such connections could invert/discard footprints
  on the right eye or stretch a fine contour. The same rule applies to both eyes.
  Existing subpixel coverage, visibility layers, background filling, normalization,
  disparity strength, eye order and guided refinement remain. No new global
  smoothing or artificial face-volume gain is applied. Balanced is unchanged.
- **Complete build configuration and dependencies.** Updated compiled QuestDepth
  AAR and existing ONNX Runtime Android 1.22.0 AAR are checked into the source tree
  with checksums and licenses. Gradle/plugin enablement, minimum SDK 26, mobile
  texture imports and an export icon are included. App/version name is 0.3.3,
  reference Android code 6, APK filename quest-photo-0.3.3-debug.apk.
- **Preserved:** three models, all quality levels, cached comparisons, gallery and
  import, original 2D, grips/controllers, eye swap/convergence, zoom/position/size/
  rotation, processing times, red processing/export status, white ordinary text,
  confirmed cache management, PNG/JPEG and full/half SBS exports.

## Export diagnosis and remaining uncertainty

The reported 0.3.2 message lacks the failing operation. It is not sufficient to
identify which Android call failed on that headset. Inspection found the export
transaction depended on dynamic JavaClassWrapper dispatch, overloaded methods,
return coercions and a descriptor size check that can return unknown (-1).
A GDScript call/type failure could return before the error field was populated;
the coordinator then displayed an empty reason. Previous mocked GDScript tests
could not validate this Java bridge on Android.

0.3.3 removes that fragile transaction from the production GDScript path and uses
explicit Java ContentResolver calls, correctly typed ContentValues/null selections,
try-with-resources, actual byte readback and structured errors. There is no silent
private-storage fallback. The matching new AAR is required; using an old plugin
produces a specific missing-export-bridge error. This repair is compiled and tested
against Android APIs, but **the actual Quest MediaStore provider remains untested**.
Do not read a passing provider simulation as confirmation on physical hardware.

## Why plane-only Apply still reconstructs

A plane change is a constant opposite horizontal translation for each eye in the
interior. Merely translating the saved SBS crops cannot recover border pixels
that fell outside its original frame; subpixel coverage and missing-background
fill also change at the new boundary. Repeated image shifts would resample detail.
The conservative implementation reconstructs once from the unchanged raw depth,
instead of degrading/reusing a cropped image or silently changing its field of
view. Pending movement has no cost from reconstruction; Apply still has that cost.

## Test report

- Full available **Godot 4.6.3 headless Linux** regression suite passed. Existing
  controllers, gallery, format decoders, original-image hashes, export protections,
  conversion flow, model comparison and cancellation tests remain enabled.
- **30 new refinement checks** passed: exact steps, pending/current separation,
  snapping/escape/hysteresis, bounds, no slider-triggered jobs, single Apply,
  repeated Apply guard, failure restoration, malformed native responses,
  mirror/eye symmetry, folded footprints, unchanged input depth and portrait detail.
- **38 Python tests ran; 8 skipped** because the standard test interpreter lacks
  PyTorch. Those unchanged checkpoint-preparation tests were not rerun with real
  weights. Three new source-delivery checks validate versions, compiled component
  and Java-source hashes, ARM64 libraries, plugin methods and required licenses.
- **Android native plugin compiled with JDK 17** against Godot 4.6.3. Six Java tests
  passed: two typed MediaStore transaction tests with a fault-injecting local
  provider (multiple success/failure/retry scenarios), plus four existing inference
  plugin tests using the small synthetic ONNX fixture. These exercise real desktop
  ONNX Runtime, not pretrained depth networks or Android ARM64 inference.
- **Actual Godot/Gradle Android project export succeeded.** APK manifest identifies
  org.questphoto.viewer, version 0.3.3/code 6, minimum SDK 26, target SDK 36.
  Packaging checks confirmed the plugin registration, export method in DEX,
  ARM64-only Godot/OpenXR/ORT libraries, runtime/model license notices and signature.
  This cloud verification APK contains **no user model weights** and is not the
  delivered headset APK. It was neither installed nor executed on Quest.
- The complete release ZIP is independently extracted and checked for source
  integrity, Android dependencies and headless Godot import before publication.

Logs and machine-readable reports: `verification/0.3.3/`. Older regression names
mention 0.3.1/0.3.2 for historical comparisons; `refinement-report.json` is the
specific 0.3.2-versus-0.3.3 comparison.

### Reconstruction measurements / visual limits

Same RGB/normalized depth in the 2048 × 32 repeating steep-gradient stress test:
0.3.2 loses every right-eye footprint; 0.3.3 retains visible samples. Both maintain
mirror-and-eye-swap symmetry, so eye symmetry alone was insufficient to catch
this bug. The footprint guard addresses a demonstrated failure mechanism.

A 512 × 512 NASA portrait with procedural curved depth has **zero RGB difference**
between 0.3.2 and 0.3.3 in this test. This deliberately protects existing facial
texture/depth rendering. It is not a real AI-depth benchmark. The stress image
comparison was inspected on desktop; headset perception remains unverified.
Single shared-cloud runs: stress reconstruction 342 ms → 562 ms; new portrait
2.61 s. These are reconstruction timings only, not inference or Quest estimates.
The extra guards may add cost; there is no promise of faster Maximum Quality.

Actual hair, earrings, fingers, body boundaries and flat-face cases still require
visual Quest testing. The change does not recover genuinely hidden backgrounds
or invent missing facial depth. Large depth discontinuities and model errors can
still produce artifacts. No blanket claim that all reported artifacts are fixed.

## Install and verify on Quest

Follow [BUILD_033.md](BUILD_033.md). Use your existing validated models/catalog,
Godot 4.6.3 templates, package identity and signing key; build locally and install
as an update. If your current version code is already 6+, choose a higher code.

1. Help must show 0.3.3. Verify existing grips, gallery, model comparison, original
   viewing and image-position controls.
2. Open a saved conversion. Move both sliders repeatedly, including 3.00% → 2.25%
   and plane 0.95 → 0.80. The photo must not reconstruct until Apply. Verify taps,
   held snapping, movement past magnets, exact displayed values and cancellation.
3. Compare challenging photos in both eyes at the same strength/plane as 0.3.2.
   Check facial wrinkles remain detailed and note any new contour artifacts.
4. Export PNG and JPEG, full/half SBS, repeatedly without restarting. Confirm red
   completion and distinct readable images in File Manager+ **Pictures/Z-Dim/**.
   If an error occurs, record its exact operation/exception text. Check originals
   and previous exports are unchanged. Sliders with unapplied values must export
   the currently displayed result, not unseen pending changes.
5. Verify saved comparisons, cache usage and cancelled/confirmed cache clearing.

## Delivery

Complete source: **quest-photo-0.3.3-source.zip**, with SHA-256 sidecar and per-file
source manifest. Published release: **Quest Photo 0.3.3**, tag **v0.3.3**.
GitHub main contains the same version's actual source and native dependencies.
No official Godot export templates, private signing credentials, generated caches,
APKs or large AI weights are included. All project-specific build dependencies are
included; copy your validated model folder as documented. Previous releases and
history remain available for rollback. GIF/video/scene reconstruction are deferred.
