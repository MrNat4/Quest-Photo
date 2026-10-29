# Updating your working Windows project

This 0.3.0 development source continues the headset-tested grip/gallery maintenance
version. **Read the release verification record before treating AI conversion as
ready:** source integration and synthetic tests do not establish actual Android
inference. The native plugin and three ONNX model assets must be built/obtained
as documented in [ANDROID_AI.md](ANDROID_AI.md) and [MODELS.md](MODELS.md).
The headset must not need network access after the APK is installed.

Keep your existing Godot 4.6.3 project and its working Android Gradle environment.
Extract the update into a separate directory beside that project. Close Godot,
then open PowerShell in the extracted update directory and run:

```powershell
py tools/update_project.py "C:\Projects\QuestPhoto"
py tools/update_project.py "C:\Projects\QuestPhoto" --apply
```

The first command previews every changed file and writes nothing. The second
backs up replaced files in a timestamped sibling directory, then applies the
update. `UPDATE-MANIFEST.txt` in the backup identifies both replaced and new files.
Retain this backup for rollback; to roll back, close Godot, copy the backed-up
files over the project, and remove only files listed as `ADDED` in that manifest.
No files are deleted automatically.

The updater preserves your package identifier, signing settings and keystores,
SDK/JDK configuration, custom Gradle templates in `android/build`, OpenXR project
settings and unrelated local files. It updates `config/version` to `0.3.0`, the
Android version name to `0.3.0`, and increments existing Android version codes
(minimum 3). Running the same update twice does not increment again. Existing
Android export include filters gain `*.bin,*.json` for model/metadata packaging;
existing exclusions remain unchanged and must not exclude `models/`.

The existing project.godot is preserved except its app version. Export presets
are preserved except these version/filter changes and `plugins/QuestDepth=true`
when all three compiled plugin descriptor/runtime/AAR files are present. The
updater never replaces a local export preset with the archive's generic preset.
It does not enable Gradle or change your already working Android configuration.

When the native plugin and models are available, the update copies
`android/plugins` and `models` assets. If you build those assets later in the
extracted source, rerun the updater to copy them. A missing runtime or model must
produce an unavailable/error message; it must not produce simulated AI depth.

Open your existing `project.godot` in Godot 4.6.3, inspect the **QuestDepth** plugin
checkbox in your existing Android export preset, then build with your usual
Gradle process and signing key. Do not uninstall the previous app or clear its
data if you want to retain imported photographs. Check the Help panel for the
installed version after updating. Additional revisions must increment the app
and Android versions; do not publish different binaries as the same release.

Exports now refuse to overwrite any existing file, including an original image
passed directly as the output path. The app serializes its exports; the Godot
filesystem API does not provide an atomic exclusive-create encoder, so this guard
is not a guarantee against a separate process deliberately racing to replace a
file at the exact save instant. Existing private app exports have no such
external writer in normal use.
