# 0.3.4 evidence

- headless-tests.log: full isolated Godot 4.6.3 suite; 38 Python tests (8 skipped
  without PyTorch), new export/edge/diagnostic checks and existing regressions.
- native-tests.log/json: eight passing Java tests, JDK17/Godot 4.6.3, simulated
  Android provider plus actual desktop ONNX Runtime on a synthetic fixture.
- godot-export.log: actual application exported through the local Gradle setup.
- apk-verification.json: version, signature, plugin, native libs and license checks.
- export_image.dex.txt: actual method definition disassembled from that APK,
  including public access, signature and runtime UsedByGodot annotation.
- quality-report.json: 0.3.3/0.3.4 comparisons on identical procedural depth maps.
- comparison.png: inspected desktop diagnostic, 0.3.3 above / 0.3.4 below, left
  and right eyes. Known stripe background behind a narrow foreground structure.

The APK contains NO real model weights and was not run on a headset. Its cloud
verification key is not known to match the Windows installation. It is not the
source deliverable or an AI-ready installation. The generic headless-runner warning
reflects that runner's scope, separately from the recorded APK build checks.
The adb connection warning indicates no attached device, not a failed APK export.

The original 0.3.3 AAR is reused unchanged after bytecode/hash inspection. See
RELEASE_034.md for the verified Godot has_java_method versus has_method distinction.
No external build service, new runtime dependency or model conversion was used.
