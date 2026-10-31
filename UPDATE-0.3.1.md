# Apply Z-Dim 0.3.1 to your working project

Extract this update into your **existing working 0.3.0 Godot project**, replacing
matching source files. It leaves your models, native libraries, Android template,
package identifier, signing and export settings untouched.

In Godot 4.6.3, set **Application → Config → Version** to **0.3.1**. In your current
Android export preset, set **Version Name** to **0.3.1** and increase **Version
Code** above your installed APK. Export normally using Godot.

No APK or builder is included or required. Do not use the old 0.3.0 autobuilder.

Use left grip + B → Quality for Balanced / High Quality / Maximum Quality.
High and Maximum share cached AI depth. Android SBS exports target **Pictures/Z-Dim/**
through MediaStore. Physical Quest quality and File Manager+ visibility remain
unverified. Full details and test results: **docs/QUALITY_EXPORT_031.md**.
