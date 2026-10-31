extends SceneTree
const Shared = preload("res://scripts/shared_media_export.gd")
var failures := 0
var checks := 0
class FakeStore extends RefCounted:
 var error := "injected storage failure"
 var fail_at := ""
 var bytes := PackedByteArray()
 var published := false
 var removed := false
 var name := ""
 var mime_type := ""
 var calls: Array[String] = []
 func begin(filename: String, mime: String) -> bool:
  calls.append("insert_pending")
  name = filename
  mime_type = mime
  return fail_at != "begin" and mime in ["image/png", "image/jpeg"]
 func write(data: PackedByteArray) -> bool:
  calls.append("write")
  bytes.append_array(data)
  return fail_at != "write"
 func publish() -> String:
  calls.append("publish")
  published = fail_at != "publish"
  return "content://media/external_primary/images/media/123" if published else ""
 func abort() -> void:
  calls.append("abort_own_row")
  removed = true
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error(message)
func _initialize() -> void:
 var path := "user://shared-export-test.png"
 var bytes := PackedByteArray()
 bytes.resize(Shared.CHUNK_BYTES * 2 + 7)
 for i in bytes.size(): bytes[i] = i % 251
 var file := FileAccess.open(path, FileAccess.WRITE)
 file.store_buffer(bytes); file.close()
 var hash := FileAccess.get_sha256(path)
 var backend := FakeStore.new()
 var result := Shared.publish(path, backend)
 check(result.has("uri") and result.destination.begins_with("Pictures/Z-Dim/"), "Success reports shared MediaStore destination")
 check(backend.bytes == bytes and backend.calls.count("write") == 3, "Bounded streaming preserves all encoded bytes")
 check(backend.calls[0] == "insert_pending" and backend.calls[-1] == "publish", "Image published only after streaming")
 check(backend.published and not backend.removed, "Successful new export retained")
 var second := FakeStore.new()
 Shared.publish(path, second)
 check(backend.name != second.name, "Repeated export allocates a unique new name")
 var jpeg_path := "user://shared-export-test.half-sbs.jpg"
 DirAccess.copy_absolute(path, jpeg_path)
 var jpeg_backend := FakeStore.new()
 Shared.publish(jpeg_path, jpeg_backend)
 check(jpeg_backend.mime_type == "image/jpeg" and jpeg_backend.name.ends_with(".half-sbs.jpg"), "JPEG MIME and half-SBS layout marker preserved")
 DirAccess.remove_absolute(jpeg_path)
 for stage in ["begin", "write", "publish"]:
  var failure := FakeStore.new()
  failure.fail_at = stage
  var failed := Shared.publish(path, failure)
  check(failed.has("error") and not failed.has("destination"), "No false success or private fallback after " + stage)
  check(failure.removed, "Rollback only owned row after " + stage)
  check(FileAccess.get_sha256(path) == hash, "Source unchanged after " + stage)
 check(FileAccess.get_sha256(path) == hash, "Success preserves staging input")
 check(Shared.publish("user://missing.jpg", FakeStore.new()).has("error"), "Missing encoded input rejected")
 check(Shared.publish("user://invalid.mp4", FakeStore.new()).has("error"), "Unsupported encoded format rejected")
 if OS.get_name() != "Android":
  check(Shared.publish(path).has("error"), "Unavailable Android runtime returns explicit error")
 DirAccess.remove_absolute(path)
 print("SHARED MEDIA: %d checks, %d failures (transaction mocks; Android JNI/MediaStore requires Quest)" % [checks, failures])
 quit(1 if failures else 0)
