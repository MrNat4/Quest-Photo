# Distributable component notices

- QuestDepth and the application source retain this repository's LICENSE.
- ONNX Runtime Android 1.22.0 is distributed unchanged from Microsoft's Maven Central artifact `com.microsoft.onnxruntime:onnxruntime-android:1.22.0`. Its MIT license and upstream third-party notices are in `android_ai/licenses/` and copied into the APK's `third_party/licenses/` directory by the builder.
- Godot 4.6.3 uses the MIT license and its bundled third-party notices. The build uses the owner's existing official editor/export templates; Godot is not duplicated inside QuestDepth. See https://godotengine.org/license/ .
- The owner's V2 Small, V3 Small and V3 Base weights are supplied locally. The exact converted-model hashes and checkpoint metadata are retained in `models/catalog.json`; bundled model license files under `models/licenses/` accompany the APK. All three selected checkpoints are Apache-2.0; larger/noncommercial V2 checkpoints are not supported by this distribution.
- Robolectric, JUnit and desktop ONNX Runtime are test-only dependencies; they are not packaged as application dependencies. The tiny arithmetic ONNX graph under `android_ai/src/test/resources/` is solely a test fixture and never installed as an application model by the Windows builder.
