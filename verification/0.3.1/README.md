# 0.3.1 verification — desktop only

No APK or Android plugin was built, no models downloaded/converted, and no new
build workflow was created. Quest and MediaStore behavior remain unverified.

## Measured comparison

Godot 4.6.3, Linux x86-64 CPU, headless. Same source and exact same procedural
depth inputs for old/new algorithms. Timings below measure reconstruction only;
**AI inference was not run**, so total real conversion time is not benchmarked.

| Case | 0.3.0 High | 0.3.1 High | 0.3.1 Maximum |
|---|---:|---:|---:|
| 400×240 edges/wires/ring | 0.254 s | 0.494 s | 0.671 s |
| 512×512 NASA portrait | 0.697 s | 1.326 s | 1.813 s |
| 2048×1366 input | 4.124 s | 8.165 s | 19.822 s |

The large High result is 3072×1025 full-SBS (1536 pixels per eye). Maximum is
4096×1366 (2048 per eye). Balanced measured 1.282 s versus 1.295 s previously,
with the same 1024-per-eye cap. High is 1.90–1.98× the previous reconstruction
runtime in these cases. Actual total inference+render timing and thermal effects
must be measured on Quest; the application now records them separately.

Peak process RSS for the complete benchmark was **117,329,920 bytes (~112 MiB)**.
Godot tracked static-allocation peak was approximately **72.5 MiB**. These include
the test process and fixtures, and **exclude neural-model memory and VR rendering**.
See memory.json and reconstruction-benchmark.json for scope and exact readings.

On the generated boundary fixture, depth MAE against known depth fell from
0.01978 (bilinear) to 0.00359 (guided). Render MAE against the same renderer using
known full-resolution depth fell from 6.82 to 2.58 RGB levels out of 255. This is
controlled synthetic evidence, not a general perceptual score or AI benchmark.
The comparison image was inspected: the diagonal and ring edges are visibly
cleaner; portrait texture is preserved. Fine hair and unobserved backgrounds
still require real-photo stereo evaluation.

## Automated checks

- Existing Godot core, image formats/layouts, gallery, controllers, viewer,
  export and original-protection regressions pass (headless/synthetic inputs).
- 59 cache/conversion checks cover model/quality comparisons, raw-depth hashes,
  adjustment, cancellation, original restoration, High/Maximum cache sharing
  and separate timing fields. Native inference is not performed by this suite.
- 26 geometry checks include signed disparity, convergence, exact zero-depth
  output, fractional translation, sparse thin foreground, resolution and limits.
- 19 MediaStore transaction-mock checks cover bounded streaming, unique names,
  PNG/JPEG metadata, layout markers, failures/rollback and source preservation.
  They do NOT exercise Android JNI, the real media provider or File Manager+.
- Complete old/new visual/benchmark run: 19 checks, zero failures.

The archived full headless log precedes the final arithmetic-loop optimization
and the four extra geometry/one JPEG transaction assertions. Final benchmark,
geometry and shared-media logs test those final changes. No unrelated full
model/exporter validation was repeated. Python regression log records any
optional-library skips explicitly.
