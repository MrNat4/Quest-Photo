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
