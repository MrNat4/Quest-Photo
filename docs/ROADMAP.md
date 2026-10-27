# Roadmap

## Milestone 1 — viewer (implemented, acceptance incomplete)

- [x] Godot 4.6.3 project and OpenXR configuration.
- [x] Known stereo target with eye-specific labels and signed disparities.
- [x] Per-eye shader, mono toggle, eye swap, convergence and desktop eye preview.
- [x] Sample real photograph, zoom/pan/physical size/roll/position.
- [x] Explicit Touch bindings, recenter, focus and tracking-loss handling.
- [x] Headless parser/runtime, core and synthetic input tests.
- [x] Android export preset/build script and actual export attempt.
- [ ] Install missing Android toolchain and produce signed APK.
- [ ] Verify shader rendering on a graphics backend.
- [ ] Quest 3 acceptance: eye isolation, depth direction, controls, lifecycle, comfort.

## Milestone 2 — automatic depth conversion (not implemented)

1. First complete known-stereo headset acceptance; never use an AI output to
   diagnose eye-routing errors.
2. Evaluate **Depth Anything V2 Small** (Apache-2.0 model variant) against
   **MiDaS v2.1 Small**; verify exact code and weights licenses before bundling.
   A model family name does not establish the license of a third-party export.
3. Prototype a pinned ONNX export on desktop, then a native Android ARM64 inference
   adapter (ONNX Runtime CPU first). Assess 256/384/518 input resolutions,
   latency, peak resident memory and thermal behavior on Quest. No benchmark or
   performance promise exists yet; NNAPI/GPU support must be measured.
4. Package weights and runtime in the APK; no first-run downloads. Expose honest
   progress/cancellation and serialize background jobs to bound memory.
5. Normalize inverse depth with robust percentiles; preserve a float/16-bit
   source depth map and model metadata separately from later edits.
6. Generate L/R via depth-aware forward reprojection with visibility handling,
   disparity limits and background-aware hole filling. A single uniform shift
   is not a 2D-to-3D conversion. Test occlusion edges and zero-depth invariants.
7. Provide depth strength and zero-disparity convergence with immediate preview.

Why retain Godot: OpenXR, texture/shader rendering, controller input and Android
export already fit the viewer. AI inference belongs behind a narrow native
adapter; replacing the entire framework is not justified at this point.

## Milestone 3 — files and exports (partial)

- [x] Local app-private JPEG/PNG library and desktop picker.
- [x] Validated per-image viewing settings.
- [ ] VR browser with thumbnails and controller pointer interaction.
- [ ] Android Storage Access Framework import/export adapter.
- [x] Full/half SBS PNG/JPEG export with current crop/convergence; CPU pixel
      tests pass, controller export on hardware remains unverified.
- [ ] Versioned project container preserving original reference, depth, masks,
      edits and view/export settings; atomic saves and recovery.

## Milestone 4 — depth editing

Grayscale preview; undoable selection mask brush/eraser; tolerance-based wand;
feathering/smoothing; selected depth offset and contrast/variation adjustment.
Keep immutable model depth separate from edit layers. Test undo/redo, project
round trips and edge behavior. Object segmentation is optional after this works.

## Milestone 5 — GIFs

Add a licensed frame decoder that handles GIF disposal/timing correctly. Process
one frame at a time on disk, preserve frame times and use temporal depth smoothing.
Show progress and permit cancellation. Loop preprocessed stereo frames. Evaluate
Android MediaCodec MP4 export with codec availability and dimension checks.
Conversion can be slow; realtime inference is not required.

## Milestone 6 — refinement

Profile actual Quest frame time, memory, decode/inference/export latency, thermal
behavior and crash recovery. Add caches and texture budgets based on measurement.
Then investigate approximately ten-second videos using the frame pipeline.

## Research only

Object-region masks and project metadata may later support independent meshes,
transforms and reconstructed backgrounds. Generative hidden surfaces, deformable
hair/clothing, hand physics and training from corrections are aspirational, with
no implementation or delivery promise. Do not add those dependencies to the
initial stereoscopic photo application.
