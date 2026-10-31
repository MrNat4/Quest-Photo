# Z-Dim 0.3.1 — quality and shared exports

This is a **source-only update for your working 0.3.0 project**. No APK, builder,
PowerShell/CMD script, compiled plugin or model weights are included. No new
Android plugin is required. Continue using Godot 4.6.3 and your existing Android
configuration, QuestDepth/ONNX libraries and validated models.

## Apply using your existing Godot workflow

1. Close Godot. Extract `ZDim-0.3.1-source-update.zip` into your **existing working
   0.3.0 project folder**, allowing its source files to be replaced. The update
   does not contain `project.godot`, `export_presets.cfg`, credentials, Android
   build templates, models, or native libraries, so those working files stay put.
2. Open that project in Godot 4.6.3. In **Project Settings → Application → Config**,
   set **Version** to **0.3.1** (enable Advanced Settings if necessary). In your
   existing **Android export preset**, set **Version Name** to **0.3.1** and
   increase **Version Code** above the code of your currently installed APK.
   Keep the package identifier, signing fields, Gradle and OpenXR settings as-is.
3. Export and install with your normal Godot workflow. Help reads the configured
   application version; confirm it says **0.3.1** on the headset.

Do not run the historical 0.3.0 autobuilder for this update: it deliberately has
its own 0.3.0 version handling. No replacement build workflow is provided.
The repository's reference configuration is versioned 0.3.1/code 4, but **your
local code must exceed your own installed code**; don't overwrite your presets
with the repository's example. The update is applied to your existing project,
not opened as a second project.

## Quality choices

Use the existing **left grip + B** conversion menu. Activate **Quality** to cycle:

| Mode | Inference longest side | Reconstruction longest side, per eye | Processing |
|---|---:|---:|---|
| Balanced | 364 | 1024 | Retains the 0.3.0 baseline reconstruction |
| High Quality | 518 | 1536 | Image-guided depth upsampling, subpixel surface coverage, two-layer visibility and edge compositing |
| Maximum Quality | 518 | 2048 | High processing plus a depth/RGB-gated refinement pass and bounded background texture continuation |

Images smaller than these caps are not enlarged merely to reach the cap. The
original aspect ratio and rectified left/right geometry are retained. High and
Maximum use the same inference preprocessing and settings; changing between them
reuses the same immutable depth map. Balanced uses a different inference size,
so it has a separate raw result. Different models also remain separate.

0.3.0 raw depth and record files are read unchanged. Old previews remain in place;
new previews have revision/mode-specific filenames and metadata. Adjusting depth
or convergence uses cached depth. A cached preview is reused only when its
renderer revision, quality, strength and screen plane match. Reconstruction
failures/cancellation never replace the original photograph or raw model depth.

The status and displayed-result text show **AI, reconstruction and total time**
separately. `job_inference_ms` is zero when depth is reused; the original model's
`inference_ms` remains in metadata. Reconstruction timing covers refinement and
stereo rendering. Total includes preparation, inference where needed, raw-cache
handling, reconstruction and PNG preview encoding, measured before the final
small metadata write/UI presentation. A direct preview cache hit shows zero
reconstruction time and its actual loading duration. This is not frame rate or
motion-to-photon latency.

## Reconstruction changes

- Joint bilateral upsampling uses photograph colors to weight existing nearby
  depth samples; it does not derive fabricated depth from image brightness.
- Projected pixel footprints stretch/compress within a continuous surface, but
  stop at depth discontinuities. Fractional coverage reduces staircase edges.
- Foreground visibility and pixel coverage are tracked separately. A second
  visible depth layer supplies background color for fractional edge pixels,
  reducing opaque halos and foreground bleeding.
- Gaps prefer the farther surface; similar-depth gaps interpolate. Maximum can
  continue a short mirrored portion of visible background texture, gated by
  depth, rather than endlessly extending one border pixel.
- A collapsed percentile range no longer flattens sparse foreground objects
  occupying less than 2% of a map in the enhanced modes.
- Maximum adds a cross bilateral pass gated by both color and depth difference;
  it smooths small within-surface variations without joining distinct surfaces.

These operations cannot recover true hidden scenery or reliably separate hair
that the model never detected. Texture continuation can repeat patterns. Color
edges that do not correspond to depth can still influence refinement. Inspect
faces, jewelry, foliage and strong silhouettes on your headset before deciding
which mode is best for a photograph.

## Shared SBS export

On Android, full/half SBS PNG/JPEG exports use **MediaStore**, with
`RELATIVE_PATH=Pictures/Z-Dim/`. New images are inserted with `IS_PENDING=1`,
written in bounded chunks, closed, then published with `IS_PENDING=0`. Each
export gets a unique name retaining `.sbs` or `.half-sbs`. Existing media is never
looked up as an overwrite target. Failed transactions delete only their own new
row and report an error; there is no silent app-private finished-export fallback.

The temporary encoded image is private staging data, removed after publication
or a shared-publication failure. Original photographs and internal depth caches
remain separate. Desktop exports retain the existing desktop export location.

This uses the **built-in Godot AndroidRuntime/JavaClassWrapper bridge**, not a
new AAR or native build. Android 10+ is required for scoped MediaStore publishing;
Quest 3 meets the platform requirement. No broad storage permission is added.
Relevant Godot API: https://docs.godotengine.org/en/4.6/tutorials/platform/android/javaclasswrapper_and_androidruntimeplugin.html
Android storage API: https://developer.android.com/training/data-storage/shared/media

In File Manager+, look under **Internal storage → Pictures → Z-Dim**. Its own
media/access permissions and refresh behavior may affect visibility. The
MediaStore JNI path and File Manager+ visibility still require physical Quest
verification; desktop transaction mocks cannot establish that they work on your
firmware. If publication fails, the application reports the Android error.

## Verification and physical acceptance

High reconstruction measured 1.90–1.98× the old High runtime on the desktop
comparison cases; real Quest total conversion time remains unmeasured.

See `verification/0.3.1/` for actual comparison measurements, process memory,
logs and the visual contact sheet. Tests use exactly the same procedural depth
for old/new reconstruction, including sharp diagonal boundaries, thin wires,
rings and a public-domain NASA face photograph. This tests reconstruction, not
AI depth quality. No AI inference, APK compilation, Android deployment or Quest
benchmark was performed for 0.3.1.

On Quest, use the same cached photo/model and compare High versus Maximum:

- Inspect hair against the background, facial texture, jewelry, thin edges,
  halos and newly exposed background. Check stereo comfort and eye order.
- Confirm switching High ↔ Maximum reports cached depth and zero new AI time;
  check all three models and revisit results after restarting.
- Change depth and screen plane; cancel a reconstruction and start another.
- Export full and half SBS in PNG and JPEG. Find all four files in File Manager+
  under Pictures/Z-Dim, open them, and repeat an export to check distinct files.
- Confirm the original photograph, old cached results, gallery/import and
  controller positioning still behave correctly.

This remains a development update pending those visual and storage checks.
