# Build or update Quest Photo 0.3.3

Use Godot **4.6.3 Standard**, OpenJDK **17**, your existing Android SDK/Gradle
setup, and the three validated ONNX files. No converter, external build service,
new Windows launcher or software reinstallation is needed.

## Recommended: a separate complete project

Extract `quest-photo-0.3.3-source.zip` into a new directory. All runtime GDScript,
assets, OpenXR inputs, plugin source, required AARs and license notices are present.
Copy the **entire existing validated models folder**, preserving its catalog and
hashes, into `models/`. Required paths:

- `models/v2_small.onnx.bin`
- `models/v3_small.onnx.bin`
- `models/v3_base.onnx.bin`
- `models/catalog.json` from your validated working project, not the unconfigured
  template supplied in a fresh checkout.

Do not reconvert the models. Do not modify their original copies. The build embeds
these files offline; the existing app verifies its model hashes during extraction.
No additional model preparation is part of 0.3.3.

Open the extracted `project.godot`. In Godot:

1. **Editor → Manage Export Templates**: install the official **4.6.3 Standard**
   templates if absent. **Project → Install Android Build Template**: install the
   Android Gradle template into this project. Godot's official engine AAR/templates
   are intentionally not duplicated in the source archive.
2. **Editor Settings → Export → Android**: retain your existing Android SDK and
   JDK 17 paths. Godot's 4.6.3 template defaults to Android SDK platform 36; use
   the SDK packages required by your working 4.6.3 configuration. No source code
   edit to the generated official template is needed.
3. **Project → Export → Quest 3**: use Gradle, enable **QuestDepth**, ARM64 only,
   minimum SDK **26**, APK format. These values are included in the reference
   preset. Android texture imports are enabled in project settings.
4. Preserve the **package ID** and **signing identity** of your installed app.
   Reference package is `org.questphoto.viewer`. Set any private signing paths,
   alias and passwords in Godot locally; none are included in the public source.
   A different key cannot update your installed app. Do not uninstall to bypass
   a signature mismatch if you want to preserve your private library/caches.
5. Version name/application version: **0.3.3**. Reference Android version code:
   **6**. If your existing preset uses 6 or higher, choose a higher local code.
   Save the APK as **quest-photo-0.3.3-debug.apk** (or
   **quest-photo-0.3.3-release.apk** for a signed release export).
6. Export with your usual Godot workflow. Install as an update. Check Help shows
   **Quest Photo — Version 0.3.3** before testing.

## Updating an existing working project instead

Back it up first. Copy the new source/assets and `android/plugins/` from this
complete package into it, replacing matching files. **Keep your own
`export_presets.cfg`, signing files, validated `models/`, generated `android/build/`
and private local settings.** Apply the version, output filename, plugin and
minimum-SDK values above through Godot. In Project Settings set Application →
Config → Version to 0.3.3 and Rendering → Textures → VRAM Compression → Import
ETC2 ASTC to enabled. The updated QuestDepth AAR is essential: an older AAR will
produce an explicit missing-export-bridge error. No native compilation is needed
on your laptop because the matching compiled AAR is supplied.

## Project-specific Android dependencies

`android/plugins/QuestDepth.gdap` references **QuestDepth.aar** and
**onnxruntime-android-1.22.0.aar** in the same directory. `components.json` records
SHA-256 hashes and Java source hashes. Both AARs are included, not Git LFS pointers.
The plugin declares itself through its manifest; no extra broad storage permission
or Google dependency is needed. The AAR includes Java export/inference code;
ONNX Runtime includes ARM64 `libonnxruntime.so` and `libonnxruntime4j_jni.so`.

For developers rebuilding only the plugin, `android_ai/build.gradle` uses Java 17,
Android Gradle plugin 8.6.1, compile SDK 35, and the matching official Godot 4.6.3
AAR as a **compile-only** dependency. It does not bundle another Godot engine.
`testReleaseUnitTest` runs Robolectric tests, `installPlugin` builds/copies the AAR.
Pass `-PgodotAar=<matching official godot-lib AAR>` to your Gradle installation.
This is optional; normal Godot users should use the included compiled components.

## Cache and update compatibility

Raw QPD keys/model catalog hashes and adjustment files are unchanged from 0.3.2.
New previews are versioned 0.3.3, so an old raw depth map can be reconstructed
without repeating inference. Older previews remain until explicitly cleared.
All photos, exports, settings, controller mappings and model choices are retained
when the same package/signature is installed without clearing app data.
