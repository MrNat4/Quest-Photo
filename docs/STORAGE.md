# Local photo import

Choose **Import** in the in-app gallery to open the operating system's file
picker. Browse **Pictures** or **Downloads**, choose one or multiple locally
stored JPEG, PNG, WebP, or BMP photographs, and confirm. The system may ignore the
requested initial Pictures folder. Animated WebP is rejected; GIF/video import
is not part of this milestone.

On Quest the system owns this picker, so its appearance and controls depend on
the headset firmware. It may temporarily cover or suspend the VR viewer. Use the
system Back action to cancel the picker. Once copying starts, cancellation stops
after the current chunk/decode; previously completed imports remain available.
Open the gallery again after import to view the copied photographs.

## Android implementation

Godot 4.6.3 provides a native Storage Access Framework (SAF) picker through
`DisplayServer.file_dialog_show`. It requests `ACTION_OPEN_DOCUMENT`, allows
multiple selection, sets `CATEGORY_OPENABLE`, and requests local files only.
The returned `content://` document URIs are passed directly to Godot `FileAccess`
for reading. The app never treats them as `/sdcard` paths or passes them to
`Image.load`.

The importer reads the selected documents while their temporary selection
grants are available and copies them into `user://photos`. It does not retain
URI permissions or require a source document to remain in place after import.
There are no broad storage, Internet, media-library, or Google Play Services
permissions, and no new Android plugin. JPEG/PNG/WebP/BMP validation uses the
same decoder as the viewer. Import reads and decoding run on one worker thread;
signals and scene changes run on the main thread.

Each source is limited to **32 MiB / 32 megapixels**, with at most **64 files per
batch**. Reads are bounded even if a provider reports an unknown length. Images
are decoded once during import for validation, one at a time. Original source
bytes, including EXIF, are preserved in the private copy; orientation correction
happens during viewing. Partial files are not shown in the gallery.

The destination is `<sha256>.<detected extension>`, so repeated imports of the
same bytes reuse one library copy. Existing modified/damaged copies are reported
instead of overwritten. Imported display names are stored in
`<photo path>.import.cfg`, section `[photo]`, key `original_name`, and provide
filename hints for stereo layout detection. On Android the importer queries the
document provider's `_display_name` through Godot's built-in Java API bridge.
If a provider supplies no name, an intelligible URI basename is used when
available; otherwise the title is `Photo <short-id>`. Display names never become
filesystem paths. The first name is retained when identical image bytes are
imported from different filenames. Layout can be set manually in the gallery.

Imported copies survive application restarts and source-file moves/deletion.
They are removed by Android's Clear App Data or uninstall, so retain original
photos elsewhere. Updating with the same package and signing key preserves data.

## Native picker limitation requiring Quest testing

This implementation has automated desktop coverage for the import pipeline;
**the Android picker, document-provider reads, display-name lookup, cancellation
and return to VR have not been exercised on a physical headset** in this session.
The user's successful 0.1.0 headset viewer test does not cover this new feature.

Godot 4.6.3 reports native picker support on Android, but this does not prove that
every Quest firmware includes a working activity for `ACTION_OPEN_DOCUMENT`.
Its built-in launch path does not catch `ActivityNotFoundException`. If the
firmware has no handler, launch may fail at the platform level instead of
returning an error to GDScript. The app surfaces errors that the API returns and
uses the direct built-in launch; it deliberately does not hard-block based on
`PackageManager.resolveActivity`, which can return a false negative due to
Android package-visibility rules. No unverified replacement picker is bundled.

If Import does not open a chooser, capture `adb logcat -v time`, include the
headset OS version, and report whether the application crashed, stayed in VR,
or showed a system window. A small native bridge with caught activity-launch
errors and explicit intent queries is a possible follow-up if hardware evidence
requires it. It would require a tested Gradle build. Broad storage access is not
a prerequisite or an automatic workaround.

## Physical-headset acceptance checks

1. Copy a JPEG, a PNG and an EXIF-rotated JPEG to Pictures/Downloads using USB.
2. Launch the app offline; Import should open the system chooser with usable
   controller selection. Test one selection, then multiple selections.
3. Confirm progress and readable names, correct orientation, and visible photos.
4. Cancel from the system chooser; the viewer must remain usable. Start a batch
   and cancel copying; completed photos may remain, incomplete ones must not.
5. Close and reopen the application; all completed imports should remain. Move
   an original source elsewhere and confirm its imported copy still opens.
6. Re-import an unchanged photo; it should reuse the library entry. Select a
   malformed/oversized image alongside a valid one; report failures clearly and
   retain the valid import.
7. Verify returning from the picker restores stereo and controller interaction.

## Sources checked for the pinned engine

- [DisplayServer API and SAF URI behavior](https://docs.godotengine.org/en/4.6/classes/class_displayserver.html#class-displayserver-method-file-dialog-show)
- [Godot 4.6.3 Android file picker implementation](https://github.com/godotengine/godot/blob/4.6.3-stable/platform/android/java/lib/src/main/java/org/godotengine/godot/io/FilePicker.kt)
- [Godot 4.6.3 JNI launch wrapper](https://github.com/godotengine/godot/blob/4.6.3-stable/platform/android/java_godot_wrapper.cpp)
- [Godot built-in Android API bridge](https://docs.godotengine.org/en/4.6/tutorials/platform/android/javaclasswrapper_and_androidruntimeplugin.html)
