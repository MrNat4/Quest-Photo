# Third-party components — 0.3.3

- Application source: MIT, root LICENSE. No requirement to publish derivative
  application source is imposed by this project's license.
- Godot Engine 4.6.3 Standard: MIT; https://godotengine.org/license/ . Official
  export templates are installed locally, not bundled in the source ZIP. Preserve
  their engine/third-party license notices when distributing an APK.
- Khronos OpenXR loader supplied by Godot: Apache-2.0, with Godot template notices.
- ONNX Runtime Android **1.22.0**: MIT. Required AAR included in android/plugins/;
  license and dependency notices in android_ai/licenses/. Copies in assets/licenses/
  are included in exported APKs. Preserve both notices.
- **Depth Anything V2 Small**, official depth-anything/Depth-Anything-V2-Small:
  Apache-2.0. Official checkpoint notice in models/licenses/Depth-Anything-V2-LICENSE.txt.
- **Depth Anything 3 Small** and **Depth Anything 3 Base**, official
  depth-anything/DA3-SMALL and depth-anything/DA3-BASE: Apache-2.0. Notice in
  models/licenses/Depth-Anything-3-LICENSE.txt. Only these named variants are
  supported; do not assume licenses for other sizes are the same.
- Converted weights are user-supplied, not downloaded or changed in 0.3.3. Their
  exact checkpoint revisions/export hashes remain in the user's validated model
  catalog; the repository template intentionally does not invent those values.
- Sample Grace Hopper photograph: public-domain US Navy image; assets/ATTRIBUTION.md.
  NASA astronaut testing photo: tests/fixtures/quality/ATTRIBUTION.md.
- Python Pillow, PyTorch/ONNX exporter dependencies and Robolectric/JUnit are
  developer/test dependencies, not new APK runtime dependencies. Historical model
  preparation instructions remain available; reconversion is not required.

No noncommercial model variant is added. Keep license/attribution notices with
redistributed components. Android SDK, JDK and official templates remain external
build tools. A commercial distributor must retain the applicable notices.
