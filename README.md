# Quest Photo 0.3.4 — CLEAN Godot-only project

This branch is a minimal Godot 4.6.3 Standard project for Meta Quest 3. It contains **no legacy autobuilder, model converter, updater, tests, release archives, Java recompilation project, or cloud validation machinery**. It has the built QuestDepth and ONNX Android plugin AARs required for a regular Godot Gradle export.

## Build on your existing Windows laptop

1. Download this branch as a ZIP (GitHub **Code → Download ZIP**) and extract into a **new folder**. Keep the working 0.3.3 project untouched as your backup.
2. Copy the **entire** validated `models` folder from your working 0.3.3 project into this folder, replacing the small template `models/catalog.json`. It must contain the original matching `catalog.json` and `v2_small.onnx.bin`, `v3_small.onnx.bin`, `v3_base.onnx.bin`. **Do not reconvert any model.** Retain the model licenses already in the project.
3. Open `project.godot` in **Godot 4.6.3 Standard**. Keep your existing Android SDK and **JDK 17** settings. If not already installed, use **Editor → Manage Export Templates** to install matching 4.6.3 templates. In this new folder, use **Project → Install Android Build Template** to generate the official `android/build` directory. **Do not copy the old project's generated `android/build` or `.godot` directory.**
4. In **Project → Export → Quest 3**, confirm **Use Gradle Build** and **QuestDepth** are enabled, ARM64 only, minimum SDK 26, package ID `org.questphoto.viewer`, version **0.3.4**, code **7** (or higher than your installed APK).
5. Select **Export Project**, keep **Export With Debug checked**, and save `quest-photo-0.3.4-debug.apk`. For your standard debug workflow, leave the preset's **Keystore → Debug / Debug User / Debug Password** overrides empty. Godot passes your existing **Editor Settings → Export → Android → Debug Keystore** identity to Gradle. **No signing-file copying, old project folder, or `.godot/export_credentials.cfg` is required.** Keep using your existing editor profile; do not generate or replace its key.
6. **Once, before this update:** compare the new APK's signing certificate with your retained 0.3.3 APK using the two SDK commands in [SIGNING.md](SIGNING.md#one-time-check-on-your-windows-laptop). If they match, install over 0.3.3 normally. If they differ, keep the installed app and use the existing matching key as described there; do not uninstall. Check Help shows **0.3.4**, then test a PNG/JPEG shared export to `Pictures/Z-Dim/` and High/Maximum edge rendering.

Future releases use these same fresh-folder steps without copying signing credentials. If you previously used a custom **debug** key, it can be selected once in the editor's global Android settings and reused across fresh projects. A **release**-signed installation needs its original release key and release export mode; do not switch it to debug. The certificate comparison, not a filename or a successful signature verification alone, establishes compatibility.

## Included

- `scripts/`, `scenes/`, `shaders/`, `assets/`, `openxr_action_map.tres`, `project.godot`: application and stereo viewer
- `android/plugins/`: compiled QuestDepth, ONNX Runtime, descriptor and hashes
- `export_presets.cfg`: fresh version 0.3.4 Godot preset
- `models/`: placeholder catalog and license texts (your **actual model weights are not in this ZIP**)
- license/third-party notices

The v0.3.4 export fix uses `has_java_method` to discover `export_image` in the native Godot plugin. High/Maximum have targeted edge and hole-fill changes. This source has not been built or installed on your actual Quest from this cleaned branch; its application files and dependencies are copied without modifications from the tested v0.3.4 main branch.

Full development source, Java source, tests and prior delivery history are preserved on [archive/full-development-through-0.3.4](https://github.com/MrNat4/Quest-Photo/tree/archive/full-development-through-0.3.4), at commit `136952cb57a954b321b0e8cff6aa58bee8980b77`. This clean branch can become the future release foundation without bundling the old build/conversion machinery. Main has not been changed by this cleanup.

See [SIGNING.md](SIGNING.md) for the configuration comparison, Godot source references, verification results and the remaining local certificate check. Runtime files, export preset and compiled libraries are unchanged by this cleanup. No APK or new signing key was produced.
