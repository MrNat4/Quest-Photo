# Quest Photo 0.3.4 — CLEAN Godot-only project

This branch is a minimal Godot 4.6.3 Standard project for Meta Quest 3. It contains **no legacy autobuilder, model converter, updater, tests, release archives, Java recompilation project, or cloud validation machinery**. It has the built QuestDepth and ONNX Android plugin AARs required for a regular Godot Gradle export.

## Build on your existing Windows laptop

1. Download this branch as a ZIP (GitHub **Code → Download ZIP**) and extract into a **new folder**. Keep the working 0.3.3 project untouched as your backup.
2. Copy the **entire** validated `models` folder from your working 0.3.3 project into this folder, replacing the small template `models/catalog.json`. It must contain the original matching `catalog.json` and `v2_small.onnx.bin`, `v3_small.onnx.bin`, `v3_base.onnx.bin`. **Do not reconvert any model.** Retain the model licenses already in the project.
3. Open `project.godot` in **Godot 4.6.3 Standard**. Keep your existing Android SDK and **JDK 17** settings. If not already installed, use **Editor → Manage Export Templates** to install matching 4.6.3 templates. In this new folder, use **Project → Install Android Build Template** to generate the official `android/build` directory. **Do not copy the old project's generated `android/build` or `.godot` directory.**
4. In **Project → Export → Quest 3**, confirm **Use Gradle Build** and **QuestDepth** are enabled, ARM64 only, minimum SDK 26, package ID `org.questphoto.viewer`, version **0.3.4**, code **7** (or higher than your installed APK).
5. **Signing:** choose the **same export mode and exact signing key/certificate as the currently installed 0.3.3 APK**. If it used your existing Godot editor's standard debug keystore, that same editor usually keeps it. If you used a custom debug/release keystore, point the preset to that existing key and keep the alias/password. A different key prevents an update; **do not uninstall** just to bypass this until your data is safely preserved.
6. Select **Export Project**, save an APK, and install it over 0.3.3. Check the Help page shows **0.3.4**. Test a PNG/JPEG shared export to `Pictures/Z-Dim/` and compare High/Maximum edge rendering.

## Included

- `scripts/`, `scenes/`, `shaders/`, `assets/`, `openxr_action_map.tres`, `project.godot`: application and stereo viewer
- `android/plugins/`: compiled QuestDepth, ONNX Runtime, descriptor and hashes
- `export_presets.cfg`: fresh version 0.3.4 Godot preset
- `models/`: placeholder catalog and license texts (your **actual model weights are not in this ZIP**)
- license/third-party notices

The v0.3.4 export fix uses `has_java_method` to discover `export_image` in the native Godot plugin. High/Maximum have targeted edge and hole-fill changes. This source has not been built or installed on your actual Quest from this cleaned branch; its application files and dependencies are copied without modifications from the tested v0.3.4 main branch.

Keep the original full development repository on `main` for technical source/test history. This clean branch is a **build project**, not a replacement for that development history.
