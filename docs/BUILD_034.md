# Quest Photo 0.3.4 — local build and repeatable updates

Godot **4.6.3 Standard**, Java **17**, your established Android SDK/Gradle setup.
The complete source ZIP includes every project-specific dependency: QuestDepth
AAR, ONNX Runtime Android 1.22.0 AAR, descriptor, Java/Gradle source, manifests,
assets and licenses. No previous source archive is required. Your real model
weights/catalog and private signing credentials remain local to your laptop.

## Recommended: update your working project

1. Back up the working project and its signing key. Copy **scripts**, **assets**,
   **scenes**, **shaders**, **android/plugins**, **project.godot** and
   **openxr_action_map.tres** from the new ZIP over the corresponding items.
   Keep your existing **models/** (including catalog), **export_presets.cfg**,
   **android/build/**, editor SDK/JDK paths and private export credentials.
2. In Godot's existing **Quest 3** Android export preset, verify **Use Gradle
   Build**, **QuestDepth enabled**, ARM64, minimum SDK 26, package ID
   **org.questphoto.viewer**. Set Version Name to **0.3.4**, Version Code to **7**
   or higher than your currently installed/local code, and output filename to
   **quest-photo-0.3.4-debug.apk** (or versioned release filename).
3. Export with the **same signing configuration and export mode** as your working
   installation and install as an update. Do not uninstall or clear app data.
   Help must display **Quest Photo — Version 0.3.4**.

The AAR in this release is the verified 0.3.3 binary: it already contains
export_image. The essential fix is the updated GDScript Java-capability lookup.
Copy android/plugins anyway to eliminate a genuinely stale local binary. Its
SHA-256 is recorded in components.json; no native rebuild is required on Windows.
Use this same stable working project and key for subsequent source updates.
Historical autobuilders and model converters are not needed.

## Or open a new complete project

Extract the complete ZIP into a new folder. Copy your entire validated **models/**
folder into it, including these unchanged files and their matching catalog:

- v2_small.onnx.bin
- v3_small.onnx.bin
- v3_base.onnx.bin
- catalog.json

Open project.godot in Godot 4.6.3 Standard. If absent, install official templates
with **Editor → Manage Export Templates**. Then **Project → Install Android
Build Template** in this new project. Official engine templates are intentionally
not bundled. Retain existing SDK/JDK paths; use the matching 4.6.3 Android packages.
The reference export preset already enables Gradle, QuestDepth and ARM64 and uses
0.3.4/code 7. Configure your **existing** signing identity before exporting; a new
folder alone must not become a reason to generate a different key.

## Persistent signing: avoid future uninstallations

An update must have the same package ID and signing certificate as the installed
app and an acceptable version code. Changing just the version name cannot fix a
signature mismatch. No signing credentials are invented or committed here.

- For an existing **debug** installation, retain the keystore shown in
  **Editor Settings → Export → Android → Debug Keystore**, unless your export
  preset has an explicit debug-keystore override. Keep its alias/password and
  export mode unchanged. Back up that exact file securely outside the repository.
- For an existing **release** installation, keep the export preset's release
  keystore, alias and password. Godot may store private preset credentials in
  `.godot/export_credentials.cfg`; keep this local file when updating your
  working project and never publish it or the key.
- Use a stable key location outside temporary extraction folders. Back up the
  file and credentials securely so future computer/project updates reuse them.
- If the original key is lost, a different key cannot update that installation.
  Recover the original key from your backup first. A clean install with a chosen
  persistent key is the remaining option, but it removes app-private library,
  cache and settings. The cloud test key cannot be assumed to match your key.

The cloud generated only a model-free validation APK. It is not attached because
it cannot provide your three real AI models and is not signed with a verified
copy of your installation's certificate. Build locally; no model reconversion or
key upload is needed.

## What to check if export still fails

- **Singleton absent**: enable Gradle and QuestDepth; retain the provided .gdap
  and both AARs in android/plugins/.
- **Java registry missing export_image**: an old plugin reached the installed
  APK. Replace QuestDepth.aar with the supplied copy and re-export. Do not replace
  the official Godot library with a different engine version.
- **MediaStore operation error**: keep the complete operation/exception message.
  There is no hidden private-directory fallback or false success.

Model compatibility, cached raw depth and settings keys remain unchanged.
Old 0.3.3 previews coexist with new 0.3.4 previews until cache clearing. The first
new preview reconstructs from cached depth; it should not rerun AI if the model
and inference settings match. Full details: [RELEASE_034.md](RELEASE_034.md).
