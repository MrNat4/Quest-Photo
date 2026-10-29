> Version 2 maintenance: see [V2_MAINTENANCE.md](V2_MAINTENANCE.md). Preserve your working local Gradle setup; historical baseline instructions below do not supersede it.

# Version 0.2.0 build note

The user successfully built and tested 0.1.0 on Quest 3. Preserve that working
Godot 4.6.3 SDK/JDK configuration and signing key. This update keeps the same
package, OpenXR settings, ARM64 architecture and non-Gradle export. Version code
is now 2. No native plugins or additional storage permissions are required.
New native picker/gallery device testing is still pending. The Linux workspace
still lacks Android build dependencies; use the Windows instructions below.

# Build and install

The project targets **Godot 4.6.3 stable**, Android ARM64, and the Compatibility
renderer. There is no Google Play Services dependency and no network permission.
The app runs offline; a build machine initially needs downloaded tools.

## Current environment and device report (2026-10-28)

Godot 4.6.3 and a Java 21 runtime are present. Android SDK, Android export templates,
`javac`, and `jarsigner` are absent. A download attempt failed immediately with
`curl: (7) Failed to connect to proxy port 8080`. No APK has been generated in this
cloud environment. The user reports building 0.1.0 externally and successfully
viewing stereo on their Quest; the new gallery/import changes require a new build
and separate headset testing.
`tools/build_android.sh --check` reports every missing build dependency without
downloading anything or writing an incomplete APK.

A real `godot --headless --xr-mode off --export-debug 'Quest 3' ...` attempt
also failed with exit code 1: missing both matching APK templates, Java SDK path,
Android SDK directories, `adb`, and `apksigner`. The preset was recognized by
Godot. The cloud export pipeline remains unverified with an installed toolchain.

## Windows export using the existing working setup

Keep the same Godot 4.6.3 executable, export templates, package name and signing
key used for the successful 0.1.0 build. Import this project's `project.godot` in
Godot. In **Editor → Editor Settings → Export → Android**, set the full JDK path
and Android SDK path. In **Project → Export**, select **Quest 3**, retain ARM64
and OpenXR, and export a debug APK. The current project uses the standard APK
template, so **Use Gradle Build** remains disabled. Native SAF import uses Godot's
built-in Android bridge and does not require adding any permission or plugin.

With the editor paths already configured, the equivalent PowerShell command is:

```powershell
New-Item -ItemType Directory -Force .\build | Out-Null
& 'C:\Tools\Godot_v4.6.3-stable_win64.exe' --headless --xr-mode off --path . --export-debug 'Quest 3' '.\build\quest-photo-debug.apk'
& 'C:\Android\Sdk\platform-tools\adb.exe' install -r '.\build\quest-photo-debug.apk'
```

Replace executable/SDK paths with the existing local locations. If Godot reports
missing export templates, install **4.6.3 stable** templates from its template
manager. The Linux shell helper below is optional and is not required on Windows.
Do not uninstall the working APK to fix an update error until its local data has
been backed up. See [STORAGE.md](STORAGE.md) for native-picker testing and limits.

## Install dependencies on a Linux development machine

1. Install Godot **4.6.3 stable** and its matching export templates from
   [Godot's release](https://github.com/godotengine/godot-builds/releases/tag/4.6.3-stable).
   Extract the `.tpz` archive (a ZIP) and retain `templates/android_debug.apk` and
   `templates/android_release.apk`. Never mix engine and export-template versions.
2. Install a full OpenJDK 17 SDK, including `java`, `javac`, `keytool`, and
   `jarsigner`. A JRE alone is insufficient.
3. Install Android command-line tools from
   [Android Studio downloads](https://developer.android.com/studio#command-tools),
   then install `platform-tools` and `build-tools;35.0.1` with `sdkmanager`.
   Accept the SDK licenses using `sdkmanager --licenses`.

The standard APK template build does not compile native code or run Gradle.
NDK, CMake, and a Java compiler invocation are therefore not part of this build;
the full JDK satisfies Godot's Android SDK validation. If later adding Android
plugins, switch to Gradle and install the SDK/NDK versions required by that exact
Godot template. See the
[Godot Android export guide](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html).

Set paths to the downloaded tools, then run:

```bash
export GODOT_BIN=/path/to/Godot_v4.6.3-stable_linux.x86_64
export QUEST_JAVA_SDK=/path/to/jdk-17
export QUEST_ANDROID_SDK=/path/to/android-sdk
export QUEST_EXPORT_TEMPLATES=/path/to/extracted/templates
./tools/build_android.sh --check
./tools/build_android.sh
```

The script creates isolated Godot settings under `.build/`, makes a local debug
signing key, imports the project, exports `build/quest-photo-0.2.0-debug.apk`, checks
the APK signature, and rejects an unexpected Internet permission. It writes a
checksum, package metadata, and permission report into `build/`. Keep the debug
key to install later debug builds as updates; never use this key for production.
If Android rejects an update because a different key signed the previous build,
back up application data before uninstalling the previous build.

Godot 4.6 bundles the Khronos Android OpenXR loader. The vendor plugin is optional
for this basic sideloaded viewer; no vendor extension is used. See
[Godot's Android XR deployment guide](https://docs.godotengine.org/en/4.6/tutorials/xr/deploying_to_android.html).
Meta store distribution, vendor features, and compatibility with an actual Quest
runtime still need separate validation. The non-Gradle preset inherits min/target
SDK values from the matched Godot APK template; inspect `apk-badging.txt` after
export instead of assuming an overridden SDK value was used.

## Install on Quest 3

Enable developer mode on the headset, connect USB, and accept the USB debugging
prompt inside the headset. The application's offline use requires no account;
Meta's developer-mode/sideload setup may require Meta's own developer account.

```bash
adb devices
adb install -r build/quest-photo-0.2.0-debug.apk
adb shell monkey -p org.questphoto.viewer -c android.intent.category.LAUNCHER 1
```

Alternatively launch **Quest Photo** from the headset's Unknown Sources library.
Use `adb logcat -v time` to collect startup/controller problems. Package ID:
`org.questphoto.viewer`. Testing in a desktop window or successfully exporting an
APK does not establish headset rendering, controller mapping, or comfort.

## Desktop execution

```bash
godot --path . --xr-mode off
```

Use the project's test command documented in README for automated checks. A
headless Godot process can check parsing and logic, but uses a dummy rendering
backend and cannot validate the GLES shader or per-eye headset output.
