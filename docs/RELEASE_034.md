# Quest Photo 0.3.4 — export bridge and reconstruction refinement

Based on the complete 0.3.3 source on main (30567a2fcc2fd0fecea343198a2324d191a51dca).
Package identity remains **org.questphoto.viewer**. Godot **4.6.3 Standard**,
Java **17**, application/version name **0.3.4**, reference Android version code **7**.

## Export root cause and fix

The delivered 0.3.3 QuestDepth AAR was inspected, not assumed outdated. It contains
public `String export_image(String, String)` with the runtime `UsedByGodot`
annotation. Its SHA-256 still matches the recorded component manifest. The Godot
preset enables Gradle, ARM64 and QuestDepth; the manifest registers that plugin.

The actual defect is the GDScript capability guard: it used
`native.has_method("export_image")`. In Godot 4.6.3 a JNISingleton registers Java
methods in a separate `method_map`. Its bound **has_java_method()** checks that map;
Object.has_method does not. Thus the old guard can reject the correct plugin
before attempting MediaStore export, even while its inference calls work.

Evidence: [Godot 4.6.3 JNISingleton source](https://github.com/godotengine/godot/blob/4.6.3-stable/platform/android/api/jni_singleton.h)
and [plugin registration](https://github.com/godotengine/godot/blob/4.6.3-stable/platform/android/java/lib/src/main/java/org/godotengine/godot/plugin/GodotPlugin.java).
The 0.3.3 desktop mocks did not exercise this native capability-discovery behavior.

0.3.4 uses has_java_method for JNI objects and retains ordinary has_method for
non-JNI test adapters. Missing singleton and missing Java method are reported as
separate errors. A stale local plugin remains possible if an old AAR is copied
into the build; the user's installed APK was not available for inspection. The
included AAR is the verified existing binary and **does not require rebuilding**
to fix this guard. All its hashes and Java source hashes remain recorded.

The typed MediaStore transaction is preserved: unique new row in Pictures/Z-Dim/,
pending state, close/flush, byte count and SHA-256 read-back, finalization and
published destination query. Failure removes only that attempt's row; cleanup
errors remain descriptive. There is no private-storage fallback, source overwrite,
or reconstruction triggered by exporting an already displayed image.

## Reconstruction changes

High and Maximum retain the 0.3.3 renderer, depth normalization, guidance,
visibility layers, footprint-fold guards, disparity and convergence. Two narrowly
scoped changes address observed mechanisms:

1. Adjacent samples with both a strong RGB edge and a depth-layer change are not
   connected or cross-sampled. Pure texture edges on a continuous surface remain
   connected. Background eligibility now uses the same depth-layer threshold as
   visibility, avoiding opaque halos at close but distinct layers.
2. True disocclusion holes first look for visible source background at the same
   farther depth, in nearby rows. Source x is mapped using that background's
   disparity; foreground donors are rejected. No filled pixel becomes evidence.
   High searches up to two rows, Maximum four. When no eligible donor exists,
   the previous conservative horizontal fill remains the fallback.

No new global smoothing, artificial depth gain or flattening is introduced.
Balanced is byte-for-byte unchanged in the comparison test. Raw cached AI depth,
model settings and original photographs are not modified. New previews use the
0.3.4 renderer identity; compatible raw maps are reused without inference.

A small vertical search cannot recover genuinely hidden scenery. It can still
copy an inappropriate nearby pattern at a mistaken depth boundary. Fingers,
hair, ears, overlapping bodies and dissimilar hidden backgrounds need physical
visual assessment. Warped carpet/couch depth may originate in the AI estimate;
this release does not claim to correct semantic model errors or every artifact.

## Optional cached depth diagnostic

The existing AI menu now has **Depth map / return to photo**. After showing a
saved conversion, it loads the cached raw map on a worker: white means nearer,
black farther. V3 distance maps are inverted for display; percentile contrast is
for visualization only. It shows AI depth before image-guided reconstruction
refinement, not metric distances comparable across models. It never writes the
map, reruns inference or changes pending slider settings.

If the carpet/couch already looks wavy in this diagnostic, compare the model's
saved result against the other models. If the raw shape looks plausible but the
stereo edge tears, reprojection/refinement is a stronger suspect. This is a
qualitative diagnostic, not an automatic error classifier. Toggle back without
reconstruction. SBS export is explicitly blocked while viewing the diagnostic.

## Tests and measured comparisons

Full available Godot 4.6.3 headless regression suite passed. New export/edge tests:
**30 checks**, including Java registry lookup, stale/missing capability errors,
analytic subpixel edges, true background recovery, foreground rejection,
mirror-plus-eye-swap symmetry, unchanged raw depth, Balanced identity, facial
texture contrast, diagnostic direction/toggling/export guard and asynchronous
cached-QPD loading without an inference backend.

Python: **38 tests**, eight unchanged model-preparation tests skipped because the
standard interpreter lacks PyTorch. Native Java: **eight tests passed** using
JDK17 and the existing Godot 4.6.3 library. These include real encoded PNG/JPEG
full/half-SBS file round trips through a simulated provider, repeated exports,
failure cleanup/retry, public/annotated method reflection, and existing synthetic
ONNX Runtime inference/session/cancellation tests. They are not Quest tests or
new pretrained-depth-model validation.

Same input depths, output-channel errors in levels out of 255:

| Controlled case | 0.3.3 | 0.3.4 |
| --- | ---: | ---: |
| Analytic close-layer edge mean error | 0.5423 | 0.00385 |
| Narrow-gap stripe-background mean error (High/Maximum) | 64.5 | 0.5 |

The wider-gap case distinguishes presets: High remains at 64.5 because matching
background is beyond two rows; Maximum's four-row search gives 0.5. This is a
specific case, **not evidence that Maximum is always better**. The comparison
image was inspected on desktop. The test does not reconstruct unknown real scenery.

A NASA portrait with identical procedural continuous depth retains facial
horizontal detail contrast within 0.044% of 0.3.3; full-image mean RGB difference
is below 0.048 levels. Balanced is identical. The raw guided-depth arrays also
match. These protect detail and geometry without asserting exact color identity
where coverage/background handling changed.

One desktop regression run, reconstruction only (not Quest timings):

| 512 × 512 portrait | 0.3.3 | 0.3.4 |
| --- | ---: | ---: |
| Balanced | 0.463 s | 0.465 s |
| High | 2.063 s | 2.099 s |
| Maximum | 2.653 s | 2.716 s |

High is a useful comparison baseline; Maximum uses more work and up to 2048/eye
versus High's 1536/eye on larger sources. Both still share compatible 518-side
inference depth. Normal runtime records inference/reconstruction/total times.
The synthetic test is not a model-quality benchmark or thermal/memory prediction.

## Android build and remaining limits

The actual 0.3.4 project was exported through Godot/Gradle locally in this cloud
workspace, using JDK17 and the established toolchain. Packaging checks confirmed:

- org.questphoto.viewer, 0.3.4/code 7, SDK minimum 26, target 36;
- plugin manifest registration and ARM64 Godot/OpenXR/ONNX Runtime libraries;
- actual DEX definition of public export_image(String,String), its runtime
  UsedByGodot annotation and call into SharedImageExport;
- required license assets and a valid APK signature.

**No real model files or the user's Windows signing identity are available here.**
The model-free verification APK is not a usable AI release and is not delivered
as one. No fixture models were put into it. Build locally with your already
validated models/catalog and existing signing key. No model downloads/conversion,
new software or external compilation service is required.

Physical Quest MediaStore behavior, UI comfort, actual-model quality, speed,
thermal use and live controller behavior remain unverified. Existing automated
controller/gallery/export/original-hash regressions passed. Logs and DEX evidence
are in verification/0.3.4/.

## Headset checklist

1. Install with your existing identity; Help must show 0.3.4. Confirm gallery,
   grip controls, image position/tilt, zoom, eye swap and pending sliders/Apply.
2. Export full and half SBS in PNG and JPG several times without restarting.
   Confirm red success and distinct readable files in File Manager+ Pictures/Z-Dim/.
   If it fails, record the exact new error, which distinguishes registry failure
   from a specific MediaStore operation. Originals and earlier exports must remain.
3. Reconstruct the same cached maps at the same depth/plane as 0.3.3. Compare both
   eyes on hair, fingers, ears, silhouettes and backgrounds. Compare High and
   Maximum rather than assuming the slower preset wins.
4. Inspect the cached depth diagnostic on wavy carpet/couch cases; toggle back,
   verify no inference and unchanged pending settings. Confirm normal exports
   after returning from the diagnostic.

Use [BUILD_034.md](BUILD_034.md) for simple local updates and persistent signing.
All three models, quality presets, gallery/import, cache controls, saved
comparisons, original protection and red/white status behavior are preserved.
