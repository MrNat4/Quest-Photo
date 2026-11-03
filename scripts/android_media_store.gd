extends RefCounted
## Typed native transaction in the existing QuestDepth AAR, called on export worker.
static func publish_file(path: String, mime: String, native: Object = null) -> Dictionary:
 if native == null and Engine.has_singleton("QuestDepth"):
  native = Engine.get_singleton("QuestDepth")
 if native == null or not native.has_method("export_image"):
  return {"error":"QuestDepth 0.3.3 export bridge missing. Enable QuestDepth and rebuild with the included AAR."}
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
