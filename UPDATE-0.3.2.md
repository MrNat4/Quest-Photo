# Apply Quest Photo / Z-Dim 0.3.2

1. Keep a backup of your working 0.3.1 project. Extract this source update into
   that project, replacing matching source files.
2. Open it in your existing Godot 4.6.3. Set Application → Config → Version to
   **0.3.2**. In your existing Android export preset, set Version Name to
   **0.3.2** and increase Version Code above the version already installed.
3. Export normally through Godot using your existing package name, signing key,
   Android/Gradle settings and model files. Install as an update, without
   uninstalling or clearing app data. Help should show 0.3.2.

This ZIP deliberately does not replace project.godot, export_presets.cfg, Android
build templates, compiled plugins, models or installed tools. No APK or new build
launcher is included. Do not use historical autobuilder scripts for this update.

Use left grip + B for the existing AI menu. Reconstruct High / Maximum using saved
AI depth to get the new renderer. Later menu pages contain cache usage and confirmed
clear controls. Exports continue to Pictures/Z-Dim/ with additional verification.

Read docs/MAINTENANCE_032.md for test results, known limitations and the short
headset checklist. Physical Quest visuals and MediaStore verification are pending.
