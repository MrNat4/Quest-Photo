# 0.3.3 verification evidence

- `headless-tests.log`: full isolated Godot/Python regression suite.
- `native-build-tests.log`, `native-tests.json`: actual compiled Java plugin;
  Robolectric provider tests and synthetic ONNX bridge tests, not physical Android.
- `refinement-report.json`: identical-depth 0.3.2/0.3.3 comparisons. Folded-gradient
  right-eye loss is reproduced/fixed; portrait difference is zero. Procedural depths.
- `contour-comparison.png`: desktop-inspected stress case, old top/new bottom,
  left/right columns. It is a diagnostic, not a natural-photo quality guarantee.
- `godot-android-export.log`, `apk-verification.json`: actual 0.3.3 project exported
  with Godot 4.6.3/Gradle/JDK17. APK signature, version, plugin, ARM64 libs and notices
  checked. User model weights absent; no headset install/run or real AI inference.

Godot's log ends with a failed adb daemon connection because this environment has
no attached Android device. APK export/signature checks succeeded. The generic
headless runner's closing warning describes its own scope, not the separate APK
build verification above. No APK is part of the source release.
