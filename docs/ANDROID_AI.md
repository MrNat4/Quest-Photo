# QuestDepth Android inference integration (0.3.0 development)

This is native inference source, **not a verified Android binary**. This workspace
has a JRE but no Java compiler, Android SDK, Gradle, or ONNX Runtime AAR. Its shell
network cannot currently reach the configured proxy. No native compilation or
real model inference has been performed here. Model export/validation is a separate
release gate; do not describe this checkpoint as a complete offline AI release.

The native implementation calls ONNX Runtime 1.22.0 CPU directly. It uses one
executor, one model session, two intra-op threads and one inter-op thread. Switching
models closes the previous session before loading a replacement. Repeating the
same model path reuses the existing session. No NNAPI, Google service, internet
permission, Android account, or runtime download is involved.

## Build on the existing Windows toolchain

Keep your existing `android/build`, `export_presets.cfg`, package name, signing key,
SDK/JDK paths and OpenXR settings. Do not regenerate or replace that working setup.
Build the plugin independently with JDK 17+, Android SDK platform 35 and your
existing Gradle wrapper (Gradle 8.7 or compatible with Android Gradle Plugin 8.6.1).

1. Locate the Godot **4.6.3** Android template AAR already installed with your
   working Gradle template. Common locations are under `android/build/libs/debug`
   or `android/build/libs/release`; use the actual file on your laptop. Do not use
   a Godot 4.4/4.5 library merely because its name looks similar.
2. In PowerShell, from the Quest Photo project directory, run:

   ```powershell
   $godotAar = (Resolve-Path 'android\build\libs\debug\godot-lib.debug.aar').Path
   .\android\build\gradlew.bat -p .\android_ai "-PgodotAar=$godotAar" installPlugin
   ```

   Adjust only the AAR path to match your installed template. If Gradle cannot
   find the Android SDK, set `ANDROID_HOME` to your existing SDK path or create
   `android_ai/local.properties` with `sdk.dir=C:/your/existing/Android/Sdk`.
   The first plugin build downloads pinned AGP and ONNX Runtime dependencies on
   the laptop. These build-time downloads are not required on the headset.
3. `installPlugin` copies exactly these into `android/plugins`:
   `QuestDepth.gdap`, `QuestDepth.aar`, `onnxruntime-android-1.22.0.aar`.
4. In the existing Android export preset enable the **QuestDepth** plugin and keep
   Gradle and ARM64 enabled. Do not enable other architectures. The source ORT
   AAR contains multiple ABIs; the app's existing ARM64 filter selects ARM64.
5. Package the **validated** exported models as documented in `MODELS.md`. Merely
   installing the native plugin does not install model weights.
6. Build the APK using your existing process. Confirm the plugin singleton exists
   and all required models are bundled before offline testing.

An all-in-one release must include these built AARs and validated model assets.
The development checkpoint currently does not contain them. Do not publish it as
ready to build without these explicit preparation steps and verification.

## Contract

`Engine.get_singleton("QuestDepth")` exposes:

- `start(model_path, image_path, output_path, resolution, inverse_depth) -> bool`.
  Paths are absolute private-app paths. Input is a separate, orientation-corrected
  working PNG. The output must not exist. False means a job is already running or
  the worker has stopped. Validation failures are reported asynchronously.
- `get_status() -> String`: JSON `state` is `idle`, `loading`, `running`,
  `completed`, `cancelled`, or `error`. Includes `message`, `error`, `inference_ms`,
  `total_ms`, `width`, `height`, `output_path`, `inverse_depth`, and runtime name.
- `cancel()`: terminates ORT RunOptions as soon as the runtime permits. Session
  loading is not interruptible; cancellation is checked immediately afterwards.
- `release_model()`: requests cancellation and queues session release on the same
  worker. It does not race native close against inference.

The model contract is float32 RGB `image` with shape `[1,3,H,W]`, dimensions rounded
independently to multiples of 14, longest side selected by the preset. Pixel values
are divided by 255 and normalized by ImageNet mean `(0.485,0.456,0.406)` and standard
deviation `(0.229,0.224,0.225)`. The accepted resolution is 196–700 inclusive. Model
export must validate the dynamic shape contract at both intended presets; graph
export success alone does not prove this. Output `depth` has singleton leading
axes and its last two axes are H/W.

Output format `QPD1`: four ASCII bytes, little-endian uint32 width, uint32 height,
then width×height little-endian float32 samples. Samples are the **unaltered model
output**. `inverse_depth=true` means larger raw values are nearer (V2); false means
larger values are farther (V3). The viewer normalizes a separate working copy.
NaN/infinite outputs are rejected. Creating the output uses exclusive
`CREATE_NEW`, so an existing photo/result/symlink is never overwritten. Cancellation
or failure removes only this job's newly created partial file. Originals are only
read by the application; the native plugin reads a disposable PNG copy.

## Memory, diagnostics and limits

Input decoding checks 32 MiB/32 megapixel limits before allocation and samples
large working PNGs. A model file is limited to 1 GiB and a depth output to two
megapixels. Tensor/bitmap/RunOptions resources close after each job. Native memory
patterns and CPU arena reuse are disabled to reduce retained allocations; model
weights stay resident until switching or releasing. This trades speed for bounded
retained resources but does **not** guarantee a particular Quest RSS or thermal
budget. Large transformer activations may still exceed available device memory.

The status reports Java and native heap samples. These are **not peak RSS**, and
no Quest timing or memory measurements are claimed. `inference_ms` times only
`session.run`; `total_ms` also includes model load, preprocessing and raw output.
Godot separately measures reconstruction and saves per-conversion metadata.

## Required device checks

- Build the actual AAR against Godot 4.6.3, resolve any compilation/link errors,
  and inspect the APK for one `libonnxruntime.so` ARM64 copy and all model assets.
- Enable airplane mode before launch. Run the same two real photographs through
  all installed models and both presets. Record time, memory and visible quality.
- Switch models repeatedly; confirm previous native session memory is released.
- Cancel during loading, inference and output. A successful prior conversion must
  remain available. Retry after failure and after cancellation.
- Verify original hashes and pre-existing export hashes remain identical.
- Confirm the established stereo calibration, import, gallery, grip, zoom and
  controller interactions still behave correctly on the headset.

## Licensing and API verification

ONNX Runtime 1.22.0 is MIT licensed. Its exact upstream LICENSE and third-party
notices are retained in `android_ai/licenses`; redistribute these with built AARs.
Model licenses are separate. Godot remains MIT; the plugin compiles against the
user's engine AAR and does not redistribute a second engine binary.

API references checked against upstream source:

- [Godot 4.6.3 GodotPlugin](https://github.com/godotengine/godot/blob/4.6.3-stable/platform/android/java/lib/src/main/java/org/godotengine/godot/plugin/GodotPlugin.java)
- [Godot 4.6.3 plugin registry](https://github.com/godotengine/godot/blob/4.6.3-stable/platform/android/java/lib/src/main/java/org/godotengine/godot/plugin/GodotPluginRegistry.java)
- [ONNX Runtime 1.22.0 Java session](https://github.com/microsoft/onnxruntime/blob/v1.22.0/java/src/main/java/ai/onnxruntime/OrtSession.java)
- [ONNX Runtime 1.22.0 tensor](https://github.com/microsoft/onnxruntime/blob/v1.22.0/java/src/main/java/ai/onnxruntime/OnnxTensor.java)
