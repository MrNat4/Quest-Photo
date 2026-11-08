extends RefCounted
## Typed native transaction in the existing QuestDepth AAR, called on export worker.
static func publish_file(path: String, mime: String, native: Object = null) -> Dictionary:
 if native == null and Engine.has_singleton("QuestDepth"):
  native = Engine.get_singleton("QuestDepth")
 if native == null:
  return {"error":"QuestDepth singleton is absent. Use Gradle Build and enable the QuestDepth plugin in the Android preset."}
 # Godot 4.6.3 JNISingleton registers Java methods in method_map, not ClassDB.
 # Object.has_method alone incorrectly rejects correctly registered Java methods.
 var available := bool(native.call("has_java_method", "export_image")) if native.has_method("has_java_method") else native.has_method("export_image")
 if not available:
  return {"error":"QuestDepth is registered but export_image is absent from its Java registry. Replace android/plugins/QuestDepth.aar with the included verified AAR and export again."}
 var parser := JSON.new()
 var parsed := parser.parse(str(native.export_image(ProjectSettings.globalize_path(path), mime)))
 var response: Variant = parser.data if parsed == OK else null
 if not response is Dictionary:
  return {"error":"Native export returned invalid JSON; no verified save."}
 if response.has("error"):
  if str(response.error).is_empty(): response.error = "Native export failed without a reason."
  return response
 if response.get("verified") != true or int(response.get("bytes", 0)) <= 0 or not str(response.get("uri", "")).begins_with("content://") or not str(response.get("destination", "")).begins_with("Pictures/Z-Dim/"):
  return {"error":"Native export response did not confirm a verified shared image."}
 return response
