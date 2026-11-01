extends RefCounted
## Godot 4.6.3's built-in JNI bridge; no extra plugin/AAR or storage permission.
## Android 10+ MediaStore transaction: create pending row, stream, publish.
var error := ""
var resolver: Object
var stream: Object
var uri: Object
var values_class: Object
var collection: Object
var bytes_written := 0
var actual_name := ""
var operation := ""

func _invoke(target: Object, method: StringName, arguments: Array = []) -> Variant:
 if target == null:
  error = "Android object unavailable: " + str(method)
  return null
 operation = str(method)
 var value: Variant = target.callv(method, arguments)
 var exception: Object = JavaClassWrapper.get_exception()
 if exception != null:
  error = operation + ": " + str(exception.toString())
 return value

func _wrap(name: String) -> Object:
 var value: Object = JavaClassWrapper.wrap(name)
 var exception: Object = JavaClassWrapper.get_exception()
 if exception != null:
  error = str(exception.toString())
 return value

func begin(name: String, mime: String) -> bool:
 if not Engine.has_singleton("AndroidRuntime"):
  error = "Godot AndroidRuntime is unavailable; shared export was not saved."
  return false
 var version := _wrap("android.os.Build$VERSION")
 if version == null or int(version.get("SDK_INT")) < 29:
  error = "Shared photo export requires Android 10 or newer."
  return false
 var runtime: Object = Engine.get_singleton("AndroidRuntime")
 var context: Object = runtime.getApplicationContext()
 resolver = _invoke(context, "getContentResolver")
 values_class = _wrap("android.content.ContentValues")
 var media := _wrap("android.provider.MediaStore$Images$Media")
 collection = _invoke(media, "getContentUri", ["external_primary"])
 if not error.is_empty() or resolver == null or collection == null:
  return false
 var values: Object = _invoke(values_class, "ContentValues")
 _invoke(values, "put", ["_display_name", name])
 _invoke(values, "put", ["mime_type", mime])
 _invoke(values, "put", ["relative_path", "Pictures/Z-Dim/"])
 _invoke(values, "put", ["is_pending", 1])
 if not error.is_empty():
  return false
 # Always INSERT a new row. Never locate/update an existing photograph by name.
 uri = _invoke(resolver, "insert", [collection, values])
 if uri == null or not error.is_empty():
  if error.is_empty(): error = "MediaStore refused to create a new image."
  return false
 stream = _invoke(resolver, "openOutputStream", [uri, "w"])
 if stream == null and error.is_empty(): error = "MediaStore could not open the new image."
 return stream != null and error.is_empty()

func write(bytes: PackedByteArray) -> bool:
 _invoke(stream, "write", [bytes])
 if error.is_empty(): bytes_written += bytes.size()
 return error.is_empty()

func publish() -> String:
 _invoke(stream, "flush")
 _invoke(stream, "close")
 stream = null
 if not error.is_empty():
  return ""
 var values: Object = _invoke(values_class, "ContentValues")
 _invoke(values, "put", ["is_pending", 0])
 if not error.is_empty():
  return ""
 var count: Variant = _invoke(resolver, "update", [uri, values, "", PackedStringArray()])
 if not error.is_empty() or count == null or int(count) != 1:
  if error.is_empty(): error = "MediaStore did not publish the image."
  return ""
 # Verify the new row is readable and contains the expected encoded byte count.
 # A successful insert/update alone does not establish that a file was saved.
 var descriptor: Object = _invoke(resolver, "openFileDescriptor", [uri, "r"])
 if descriptor == null:
  if error.is_empty(): error = "Published image cannot be reopened."
  return ""
 var size: Variant = _invoke(descriptor, "getStatSize")
 _invoke(descriptor, "close")
 if not error.is_empty() or size == null or int(size) != bytes_written or bytes_written == 0:
  if error.is_empty(): error = "Saved image size does not match the encoded export."
  return ""
 var cursor: Object = _invoke(resolver, "query", [uri, PackedStringArray(["_display_name", "relative_path", "is_pending"]), "", PackedStringArray(), ""])
 if cursor == null:
  if error.is_empty(): error = "Cannot verify the published MediaStore record."
  return ""
 var found: Variant = _invoke(cursor, "moveToFirst")
 if found == true:
  actual_name = str(_invoke(cursor, "getString", [0]))
  var folder := str(_invoke(cursor, "getString", [1]))
  var pending: Variant = _invoke(cursor, "getInt", [2])
  if folder.trim_suffix("/") != "Pictures/Z-Dim" or pending == null or int(pending) != 0 or actual_name.is_empty():
   error = "Image is not published in Pictures/Z-Dim."
 else:
  error = "Published MediaStore image was not found."
 _invoke(cursor, "close")
 if not error.is_empty(): return ""
 var location: Variant = _invoke(uri, "toString")
 return str(location) if error.is_empty() else ""

func abort() -> void:
 # Delete only the row created by THIS transaction, never a source/existing row.
 var original_error := error
 if stream != null:
  _invoke(stream, "close")
  stream = null
 if uri != null and resolver != null:
  _invoke(resolver, "delete", [uri, "", PackedStringArray()])
  uri = null
 error = original_error
