# 0.3.4 signing findings and repeatable Godot exports

The normal debug-export workflow needs **no per-project signing-file transfer**.
Use the existing Godot 4.6.3 editor profile, leave the project debug-keystore
overrides empty, and keep **Export With Debug** checked in the export dialog.
The APK filename ending in `-debug.apk` does not select the export mode.

## What the comparison established

| Tracked setting | 0.3.2 (`9ecebac`) | 0.3.3 (`30567a2`) | Clean 0.3.4 |
| --- | --- | --- | --- |
| Package ID | `org.questphoto.viewer` | same | same |
| Signed | true | true | true |
| Explicit signing key/alias/password | none | none | none |
| Gradle enabled | false in reference preset | true | true |
| QuestDepth explicitly enabled | absent | true | true |
| Android version code | 5 | 6 | 7 |

The archived **0.3.2 source-update ZIP does not contain an export preset**. It
preserved the user's working local preset, so its reference preset is not evidence
of the actual settings used on the laptop. The **0.3.3 complete source ZIP does
contain a fresh export preset**. Neither archive contains a keystore or
`export_credentials.cfg`. No source-controlled replacement signing identity was
found. Package identity and signing enablement did not change.

The 0.3.3 instructions discussed private signing fields/files without clearly
separating custom-key setups from standard debug exports. That guidance was too
broad. A fresh preset could omit a previously used private override, but whether
one existed on this laptop is **unknown**. A different editor profile/key, an
environment override, or a change between debug and release export could also
change the certificate. These are possibilities, not established causes.

**The exact 0.3.3 mismatch cannot be established from repository source.** The
local APK certificates and editor configuration were not supplied. There is no
evidence that merely enabling Gradle or extracting into a new project directory
changes the signer when Godot's existing debug identity is used. The previous
0.3.2 APK would additionally be needed to prove which certificate changed during
that historical transition; it is not needed to compare the next update to 0.3.3.

## Godot 4.6.3 behavior, verified against engine source

1. A nonempty `GODOT_ANDROID_KEYSTORE_DEBUG_PATH` environment override takes
   precedence over the preset's debug-keystore path. Without either, the exporter
   uses **Editor Settings → Export → Android → Debug Keystore**, including the
   editor's corresponding user/alias and password. The related environment names
   are `GODOT_ANDROID_KEYSTORE_DEBUG_USER` and
   `GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD`. No overrides are supplied here.
2. The Gradle export explicitly passes that selected path, alias and password as
   Gradle properties. The official template uses them in `signingConfigs.debug`.
   It does not choose a new key based on the fresh project directory. Running
   Gradle independently without those properties can use different defaults;
   that is not the documented Godot workflow.
3. The editor retains its existing configured key if the file exists. Its normal
   Windows default lives under `%APPDATA%\Godot\keystores\debug.keystore`.
   Self-contained Godot uses `editor_data\keystores\debug.keystore` beside its
   executable instead. The editor setting is authoritative. Godot can create a
   key if neither its configured key nor default key exists; do not delete or
   replace your existing key/profile when updating this project.
4. `.godot/export_credentials.cfg` stores private **preset** properties, not the
   editor's persistent default identity. Godot explicitly accepts its absence.
   It may create this file while saving settings even when no custom signing key
   is used. Its existence alone does not mean it must be copied to future releases.

Official 4.6.3 source references:

- [Android exporter](https://github.com/godotengine/godot/blob/4.6.3-stable/platform/android/export/export_plugin.cpp): `_get_keystore_path`, `_create_editor_debug_keystore_if_needed`, `export_project_helper` signing properties.
- [Export preset](https://github.com/godotengine/godot/blob/4.6.3-stable/editor/export/editor_export_preset.cpp): `get_or_env`.
- [Credential persistence](https://github.com/godotengine/godot/blob/4.6.3-stable/editor/export/editor_export.cpp): `_save` and `load_config`.
- [Editor data paths](https://github.com/godotengine/godot/blob/4.6.3-stable/editor/file_system/editor_paths.cpp): `get_debug_keystore_path` and self-contained paths.
- [Official Gradle template](https://github.com/godotengine/godot/blob/4.6.3-stable/platform/android/java/app/build.gradle): `signingConfigs`; [property helpers](https://github.com/godotengine/godot/blob/4.6.3-stable/platform/android/java/app/config.gradle).

## One-time check on your Windows laptop

Use the retained **0.3.3 APK you installed**, and your newly exported **0.3.4 APK**.
No APK or private key needs uploading. In File Explorer, open your existing SDK's
`build-tools` folder and an installed version subfolder containing `apksigner.bat`.
Open PowerShell there. Run these two read-only commands, replacing the example
APK paths (Copy as path in File Explorer avoids typing them):

```powershell
.\apksigner.bat verify --print-certs "C:\path\quest-photo-0.3.3-debug.apk"
.\apksigner.bat verify --print-certs "C:\path\quest-photo-0.3.4-debug.apk"
```

Both commands must succeed. Compare **Signer #1 certificate SHA-256 digest**
exactly (and every signer if more than one is listed). This is the certificate
fingerprint, **not the APK file checksum**, the certificate subject name, or a
source-stamp certificate. Signature verification alone does not compare keys.
Use your already configured JDK 17; if this shell lacks `JAVA_HOME`, set it for
this shell to the existing **Java SDK Path** shown in Godot before these commands.
No Java installation is needed.

Matching certificates establish matching signing identity. Also retain package
ID `org.questphoto.viewer` and a non-downgraded version code (this preset uses 7).
The actual installation/update still requires the headset; matching certificates
are not a test of every possible Android installation failure.

If they differ, **keep the installed app and do not generate a new key**. Select
the existing key that signed 0.3.3. For a custom **debug** key, select it once in
the editor's global Android Debug Keystore settings, with its existing alias and
password, leaving the project overrides empty. Future fresh projects then reuse
it. These global settings also affect other projects using the default debug key.
A **release**-signed APK instead requires the original release key and release
mode; the standard debug workflow cannot replace that identity. If the matching
key cannot be located, compatible updates cannot be promised or repaired by a
source-preset change. An APK contains the public certificate, not the private key.

## Cleanup and verification

Only README, this report and Git ignore rules were changed. The export preset
already correctly inherits the editor's debug identity and was left unchanged.
Ignore rules now also protect `.jks`/`.p12`/`.pfx` keys and credential files.
The existing `build/` rule already excludes generated `android/build` templates
and is retained. Obsolete builder-specific ignore entries were removed. No
builders or converters were added.

The audit passed: **73 project/runtime/dependency files** are byte-identical to
full 0.3.4; **45 literal resource references** resolve. Version/package/Gradle
settings, plugin descriptor, all three component SHA-256 hashes, both AAR archive
integrity checks, manifest registration, compiled public Java `export_image`
method and ARM64 ONNX libraries passed inspection. Private/generated-file ignore
checks and `git diff --check` also passed. Required project-specific files are present;
the three real models plus matching catalog, official Godot Android templates,
and existing local SDK/JDK/signing configuration remain laptop-supplied. Normal
Gradle dependency resolution still uses the user's established environment.

No APK was built, no key was generated or changed, and no real-model inference or
Quest test was run for this documentation/ignore-only cleanup. Certificate
compatibility with the installed 0.3.3 remains unverified until the local check.
The clean source is suitable as the future release foundation; full development
history remains on `archive/full-development-through-0.3.4`. Main was not changed.
