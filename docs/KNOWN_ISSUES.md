# 0.3.2 remaining verification

See [0.3.2 maintenance notes](MAINTENANCE_032.md) for reconstruction, export verification, protected cache clearing, UI colors, tests and limitations. Quest visual quality and the actual Android MediaStore provider remain unverified. No APK was built.

# Current limitations — 0.2.0

- User verified the 0.1.0 VR/stereo foundation on Quest. New gallery, native picker,
  document URI reading, name lookup and returning to VR require device testing.
- Some Quest firmware may lack an ACTION_OPEN_DOCUMENT activity. Godot 4.6.3's
  built-in launch does not catch that failure; see STORAGE.md. No custom plugin
  or broad-permission fallback is bundled. This is the primary release gate.
- No new APK built here: Android SDK/full JDK/export templates unavailable.
  Packaged resource startup was verified on Linux, not Android.
- No AI depth conversion/editing yet. GIF, animated WebP and video deferred.
- Six thumbnails per page; directory and metadata enumeration are synchronous.
  Source decode can use significant memory up to the 32-megapixel cap; practical
  latency, memory, thermals and gallery readability need headset measurements.
- Native multi-select is capped at 64 photos per batch. Cancellation is between
  file-read chunks/files; an active image decode is allowed to finish.
- PNG alpha displays on an opaque plane. Color profiles are not managed. Some
  BMP encodings unsupported by Godot can fail decode with a readable error.
- Layout detection uses filename suffixes; manual choices are persistent. Files
  with incompatible odd stereo dimensions need correction or a different mode.
- Imports live in private app storage. Clearing app data/uninstall deletes them.
  No library deletion UI, folder tree or export destination picker yet.
- Pixel exports omit physical screen roll/scale/position and quantize crop edges.
  Viewing preferences are not a full nondestructive depth-editing project format.

## 0.3.1 quality/export update — 2026-10-31

Three quality modes, image-guided depth refinement, subpixel surface coverage,
separate raw/preview caches, processing timings and MediaStore Pictures/Z-Dim
exports are implemented in GDScript. No new native dependency or APK build.
See [the 0.3.1 notes](QUALITY_EXPORT_031.md) for source-update steps and measured
desktop comparisons. Headset visual quality, JNI/MediaStore operation and
File Manager+ visibility require physical testing; no on-device result is claimed.
