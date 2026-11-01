# Quest Photo / Z-Dim 0.3.2 maintenance update

Source-only update from 0.3.1. No APK, native plugin rebuild, model conversion,
new dependency or alternate build workflow. Existing OpenXR actions, AI models,
quality presets, package identity and signing configuration are retained.

## Reconstruction changes

High Quality and Maximum Quality now resolve the front and rear depth layers
before accumulating pixel colors. Previously, resetting the color accumulator
while traversing overlapping depth samples made visibility depend on scan order.
That can make the right and left eye behave differently on detailed gradients.
The new visibility bands are independent of traversal direction.

Projected pixels sample within their source footprint on continuous surfaces,
instead of stretching one constant color across the footprint. Sampling stops at
depth discontinuities. Equally valid background donors are averaged symmetrically.
Maximum Quality's missing-background fill uses a bounded background gradient
instead of mirrored texture, avoiding duplicated hair/face patterns.

Disparity, screen plane, the comfort limit, and eye ordering are unchanged. No
extra volume or depth gain is fabricated. Rounded surfaces keep their existing
continuous depth gradients; the test silhouette retains its binocular width.
Balanced remains the practical previous baseline. High and Maximum still share
cached High inference depth; changing reconstruction quality does not repeat AI
when the depth key matches. Raw QPD maps remain unmodified. New previews use a
0.3.2 cache filename; old previews are retained until explicitly cleared. Select
Convert / show saved to reconstruct the new preview from existing depth.

This is an incremental repair, not a claim that every reported face/body
proportion or hair artifact is solved. Incorrect depth boundaries, large hidden
regions, flat object depth, and foreground fine structures can still produce
stretching, holes or cutout appearance. A single photo contains no true hidden
background. Strength and screen plane remain available to tune each photo.

## Exports

All export starts, completions and failures appear bright red. PNG/JPEG encoding
must produce the expected file signature. Android inserts a NEW MediaStore row
in Pictures/Z-Dim/, streams the file, closes it, publishes it, then reopens it to
verify byte count and queries its actual name, folder and published state. A
failed transaction reports an error and removes only its own new row. There is
no fallback to an inaccessible private-folder export and no overwrite of an
existing photo/export. If Android changes the filename, feedback shows that name.

This adds evidence beyond a successful save call. The actual Quest MediaStore
provider and File Manager+ visibility still require device testing. A Java bridge
or provider failure now reports the failing operation where available. Keep the
exact message if an export fails.

## Cache controls and menu

Open the existing AI menu (left grip + B). Use the stick through the six-row pages
for Cache storage usage, Clear Cached Results for Current Photo, or Clear All
Cache. Confirmation defaults to Cancel; explicitly activate Confirm deletion.
Clearing is blocked while conversion, export, import, image loading or thumbnail
work is active.

Usage separates raw depth maps, reconstructed images, thumbnails and temporary
conversion data (plus record metadata in the total). Current-photo clearing uses
the original content hash and removes all its model/quality results; identical
source copies share this scope. It retains path-based thumbnails. Clear All
also removes recognized thumbnails and abandoned AI working files. Unknown files,
nested directories and symbolic links are skipped. Usage therefore describes
managed, recognizable cache, not all storage used by the application.

Original/imported photos, exports, ONNX files (including extracted model copies),
view settings and application settings are excluded. Legacy depth/screen-plane
adjustments migrate to user://conversion-settings before removing their cache.
If migration fails, that result is kept. Regenerating deleted depth requires AI
again; clearing is irreversible after confirmation. The viewer returns to the
original and drops completed in-memory result/thumbnail references.

White settings, instructions and ordinary messages are separated from bright red
active AI/reconstruction/export feedback. Export completion and failure are red
as requested. Help is hidden while a menu is open. Menu layout stays controller
based; there is no gallery redesign.

## Validation performed

Godot 4.6.3 headless Linux tests, with temporary isolated user storage. See
verification/0.3.2/checks.txt and report.json. No APK was built; no Quest inference,
headset visual assessment or Android MediaStore runtime test was performed.

New maintenance tests cover mirrored source plus eye swapping, signed geometry,
rounded silhouette width, unchanged depth input, old/new portrait reconstruction,
cache confirmation/scope/settings migration, protected photo/export/model/view
contents, symbolic links, white ordinary text, red processing/export text, and
menu confirmation defaults. The Android verification tests mock JNI calls through
the actual MediaStore implementation: publication, reopen/size/query failures,
wrong folder, pending records and cleanup. Existing controller, gallery, decoder,
export, cancellation, original-hash and conversion-flow tests also run.

Same RGB/depth inputs, Maximum Quality, desktop measurements (single runs):

| Case | 0.3.1 reconstruction | 0.3.2 reconstruction |
| --- | ---: | ---: |
| 320 × 90 rounded surface / thin strands | 224 ms | 323 ms |
| 512 × 512 photograph with procedural curved depth | 1,818 ms | 2,497 ms |

These comparison runs cost about 1.4 times the old reconstruction time. They are
not inference timings or Quest performance estimates. Peak process RSS was
98.2 MiB for the combined Linux maintenance test harness, including both renderers,
image comparisons and UI/cache tests; this is not isolated algorithm or VR memory.
The exported report from the full suite may have different single-run timings.

An intentionally overlapping 2048 × 8 depth-gradient stress case reproduced the
old directional error: mirror/eye-swap RGB mean absolute error 1.0458 levels (out
of 255), versus 0.0 in 0.3.2. The rounded-object silhouette stayed 120 pixels wide
in both eyes. Typical input symmetry differences are much smaller; do not read
the stress figure as a percentage improvement across real photographs.

The portrait comparison was visually inspected on desktop. It shows subtle
sampling/fill differences, not proof of a dramatic overall improvement. Its
depth is procedural, not AI-estimated; it deliberately separates reconstruction
from inference. Source photo: the existing NASA astronaut fixture (attribution in
tests/fixtures/quality). No new real-checkpoint inference was run. The unchanged
model-export Python tests skip when PyTorch is unavailable in the test interpreter.

## Headset acceptance

1. Verify Help shows 0.3.2; confirm existing gallery, grips, pan/zoom/position,
   stereo toggle, convergence, eye swap and model selection still behave normally.
2. Open saved photos with faces, hair, jewelry and layered backgrounds. Reconstruct
   High / Maximum from cached depth; compare both eyes with 0.3.1 at identical
   strength/plane. Check facial proportions, thin details and foreground depth.
3. Export full/half SBS in PNG/JPEG twice. Confirm red completion, distinct files
   in File Manager+ Pictures/Z-Dim, correct contents, and unchanged originals.
   Exercise a real failure (e.g. full storage) only if convenient; retain errors.
4. Check cache usage. Cancel a deletion first, then clear one photo. Confirm other
   photos/results survive, originals/exports remain, and regenerated results keep
   your depth settings. Clear All only when willing to recompute all AI depth.
5. Check red status stays visible during long work and ordinary white text remains
   readable without menu/help overlap. Note timings and any display overlap.

## Apply / rollback

Follow UPDATE-0.3.2.md in the source-update ZIP. It omits project.godot and
export_presets.cfg so your working Android setup cannot be overwritten. Set both
application version and Android version name in Godot to 0.3.2; increase your own
Android version code above the installed build. The repository reference code is
not a substitute for that check. Keep a copy of your working 0.3.1 project for
source rollback. Old source packages and depth maps are retained. After using
cache clearing, a 0.3.1 rollback cannot read the newly separated adjustment files;
0.3.2 retains them for reapplication. Do not uninstall or clear Android app data.
