# Z-Dim 0.3.0 — Android development build

Your three converted models are ready. **Do not run model preparation again.**

1. Download the **ZDim-0.3.0-Android-Dev[number].zip** attached to this development release and extract it into a new folder beside your working project.
2. Double-click **Build-ZDim.cmd**. Select your existing working Godot project, then your completed **models** folder (containing the three `.onnx.bin` files and `catalog.json`). Select your Godot 4.6.3 executable if it is not found automatically.
3. Wait for **SUCCESS — APK compiled, signed, and verified**. The launcher opens the output folder. Install the reported APK with your existing installation method. Nothing is installed automatically.

The launcher uses your existing Python 3.11, Godot, SDK, JDK and Gradle setup. It does not convert models, install Python packages, replace your project, modify model originals, or generate a replacement signing key. Normal Gradle dependency downloads may occur during the build; the installed app needs no network connection.

The build copy and logs are under `%LOCALAPPDATA%\ZDimBuilds`. Each build receives an increasing Android version code and a visible version such as **0.3.0-dev.4**, also shown in Help. Existing package identity, app name, signing configuration, Android template, OpenXR settings and local plugins are retained. Only the copy receives updated application code, QuestDepth, model assets, ARM64 configuration, required API 26 minimum, Android texture import support and the new version. The original project and editor profile remain untouched. Building does not change your installed 0.2.0 application; installing an APK with the same package identity updates that installation.

Before reporting success, the builder verifies all three recorded model hashes, the packaged copies, ARM64 Godot/ONNX libraries, plugin DEX and manifest registration, package/version, and APK signature. `verification.json`, `APK.sha256`, `import.log` and `export.log` accompany the APK. On failure it keeps the build copy and prints the exact log location; no manual code edits are required.

## First Quest test

- Confirm the version in Help, then check gallery/import and existing controls.
- Open an ordinary photo; **left grip + B** opens AI conversion. Use stick to select and A/trigger to activate.
- Select **V2 Small**, **Balanced**, then **Convert / show saved**. Check foreground depth and edges. Test depth strength, screen plane, original 2D, zoom and positioning.
- Repeat with **V3 Small** and **V3 Base**, then **Compare next saved model**. Saved results are separate per photo/model/quality. Restart and verify they reload.
- Try **High Quality**: inference longest side increases from 364 to 518, reconstruction cap from 1024 to 1536, with additional smoothing/reconstruction processing. This can be slow, especially Base.
- Cancel a conversion; verify a subsequent job succeeds and prior results remain. Export full/half SBS in PNG/JPEG; check the saved image and unchanged original.

## Verified here and remaining limits

The actual native plugin compiles against Godot 4.6.3 and ONNX Runtime 1.22.0. Four Robolectric tests execute the Java bridge with real desktop ONNX Runtime using an explicitly synthetic arithmetic network, plus 16 direct Java depth-file protection checks. Godot headless regressions and builder preservation/hash tests pass. A signed Android ARM64 APK was built with the official 4.6.3 Gradle template and inspected for models, native libraries, plugin, identity, version and signature.

That APK used a tiny test graph solely to validate packaging; it is **not** offered as a converted-photo app. The package uses your locally validated real models. **Real-model Android inference, Quest memory/thermal behavior, stereo quality and the Windows GUI launch still require your test.** No Quest timings or peak-memory claims are made. The interface reports stages and actual inference time; it cannot provide percent-complete inside an ONNX run. Cancellation can wait for model loading or a runtime operation to finish. At most one native model/session and one conversion job are active.

Model preprocessing is RGB/ImageNet normalization, batch-one NCHW, dimensions divisible by 14. V2 inverse depth and V3 camera-depth conventions are handled separately. Unmodified float depth remains in the private conversion cache; normalization, reciprocal conversion, depth-dependent reprojection and adjustments use working copies. Originals are read-only. Completed results are retained, with a 128-result quota rather than silently deleting them. Export destination UI, animation and video remain deferred. Headset export visibility/location still needs checking.

This is a development release on `development/0.3.0-android-integration`; main is unchanged. The ZIP includes source, compiled QuestDepth AAR, ONNX Runtime Android AAR and license notices. Model weights remain on your laptop and are copied into the build, with their licenses and catalog.
