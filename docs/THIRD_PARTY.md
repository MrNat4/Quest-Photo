# Third-party components

- Godot Engine 4.6.3: MIT; https://godotengine.org/license/ . Exported Godot engine
  carries additional third-party notices. Preserve the notices distributed with
  the exact official templates when distributing the APK.
- Khronos OpenXR loader bundled by Godot: Apache-2.0; included by Godot's Android
  template. No vendor extensions or external XR tools package is used.
- Grace Hopper photograph: public domain US Navy image, details and provenance
  in `assets/ATTRIBUTION.md`.
- Python Pillow is only used to regenerate/test calibration assets, not shipped
  in the app. Pillow license: https://python-pillow.github.io/pillow-perf/#license
  (authoritative source: https://github.com/python-pillow/Pillow/blob/main/LICENSE).
- No AI weights or inference runtime are currently included. Exact redistributed
  weights, converter and native runtime must be pinned and licensed before M2.

Application code is covered by the root MIT LICENSE. Generated calibration
artwork is dedicated under CC0-1.0 as stated in assets/ATTRIBUTION.md. Build SDK/JDK tools are external developer dependencies, not app code.
