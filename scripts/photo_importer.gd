class_name PhotoImporter
extends Node
## Native SAF / desktop import. Source photos are read only; copies are committed
## into the private library only after validation. No persistent URI grant needed.

signal progress(message: String, fraction: float)
signal completed(imported: PackedStringArray, errors: PackedStringArray)
signal cancelled

const Decoder = preload("res://scripts/image_decoder.gd")
const MAX_FILE_BYTES := 32 * 1024 * 1024
const MAX_BATCH := 64
const CHUNK_BYTES := 256 * 1024
const FILTERS := [
 "*.jpg,*.jpeg,*.png,*.webp,*.bmp;Photographs;image/jpeg,image/png,image/webp,image/bmp"
]

var destination_dir := "user://photos"
var error_message := ""
var _picker_pending := false
var _thread: Thread
var _cancel_mutex := Mutex.new()
var _cancel_requested := false

func _ready() -> void:
 process_mode = Node.PROCESS_MODE_ALWAYS

func is_busy() -> bool:
 return _picker_pending or (_thread != null and _thread.is_started())

func request_import(multiple: bool = true) -> Error:
 if is_busy():
  return ERR_BUSY
 error_message = ""
 if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
  return _start_error("A system file picker is unavailable on this device.", ERR_UNAVAILABLE)
 _set_cancelled(false)
 _picker_pending = true
 progress.emit("Choose photographs in Pictures or Downloads. Use the system Back action to cancel.", 0.0)
 var mode := DisplayServer.FILE_DIALOG_MODE_OPEN_FILES if multiple else DisplayServer.FILE_DIALOG_MODE_OPEN_FILE
 var result := DisplayServer.file_dialog_show("Import photographs", OS.get_system_dir(OS.SYSTEM_DIR_PICTURES), "", false, mode, PackedStringArray(FILTERS), _picker_result)
 if result != OK:
  _picker_pending = false
  return _start_error("Could not open the system picker: " + error_string(result), result)
 return OK

func _start_error(message: String, code: Error) -> Error:
 error_message = message
 completed.emit(PackedStringArray(), PackedStringArray([message]))
 return code

func _picker_result(accepted: bool, paths: PackedStringArray, _filter: int) -> void:
 if not _picker_pending:
  return
 _picker_pending = false
 if not accepted or paths.is_empty() or _is_cancelled():
  cancelled.emit()
  return
 import_paths(paths)

func import_paths(paths: PackedStringArray) -> Error:
 if is_busy():
  return ERR_BUSY
 error_message = ""
 if paths.is_empty():
  cancelled.emit()
  return OK
 if paths.size() > MAX_BATCH:
  return _start_error("Choose up to %d photographs per import." % MAX_BATCH, ERR_PARAMETER_RANGE_ERROR)
 var directory_error := DirAccess.make_dir_recursive_absolute(destination_dir)
 if directory_error != OK:
  return _start_error("Cannot create the photo library: " + error_string(directory_error), directory_error)
 _set_cancelled(false)
 _thread = Thread.new()
 var result := _thread.start(_import_worker.bind(paths.duplicate(), destination_dir))
 if result != OK:
  _thread = null
  return _start_error("Cannot start import: " + error_string(result), result)
 progress.emit("Importing %d photograph(s)…" % paths.size(), 0.0)
 return OK

func cancel_import() -> void:
 # Godot cannot dismiss a native dialog. Keep its callback registered until Back
 # or a selection returns; cancelling prevents any returned selection being read.
 _set_cancelled(true)
 if _picker_pending:
  progress.emit("Close the system picker with Back to cancel.", 0.0)

func _set_cancelled(value: bool) -> void:
 _cancel_mutex.lock()
 _cancel_requested = value
 _cancel_mutex.unlock()

func _is_cancelled() -> bool:
 _cancel_mutex.lock()
 var value := _cancel_requested
 _cancel_mutex.unlock()
 return value

func _process(_delta: float) -> void:
 if _thread == null or not _thread.is_started() or _thread.is_alive():
  return
 var result: Dictionary = _thread.wait_to_finish()
 _thread = null
 completed.emit(result.imported, result.errors)
 if bool(result.cancelled):
  cancelled.emit()

func _exit_tree() -> void:
 _set_cancelled(true)
 if _thread != null and _thread.is_started():
  _thread.wait_to_finish()
 _thread = null

func _report(message: String, fraction: float) -> void:
 if is_inside_tree() and is_busy():
  progress.emit(message, fraction)

func _import_worker(paths: PackedStringArray, destination: String) -> Dictionary:
 var imported := PackedStringArray()
 var errors := PackedStringArray()
 for index in paths.size():
  if _is_cancelled():
   break
  var source := paths[index]
  var display_name := original_name(source)
  _report.call_deferred("Importing %d/%d · %s" % [index + 1, paths.size(), display_name], float(index) / paths.size())
  var result := _copy_one(source, display_name, destination)
  if not str(result.get("error", "")).is_empty():
   errors.append(display_name + ": " + str(result.error))
  elif result.has("path") and not imported.has(str(result.path)):
   imported.append(str(result.path))
  _report.call_deferred("Processed %d/%d photograph(s)" % [index + 1, paths.size()], float(index + 1) / paths.size())
 return {"imported": imported, "errors": errors, "cancelled": _is_cancelled()}

func _copy_one(source: String, display_name: String, destination: String) -> Dictionary:
 if source.begins_with("http://") or source.begins_with("https://"):
  return {"error": "Only locally stored photographs can be imported."}
 var file := FileAccess.open(source, FileAccess.READ)
 if file == null:
  return {"error": "Cannot read this file; select it again in the system picker. " + error_string(FileAccess.get_open_error())}
 if file.get_length() > MAX_FILE_BYTES:
  return {"error": "File exceeds 32 MiB. Resize it before importing."}
 # Some document providers report an unknown/zero length. Bound actual reads too.
 var bytes := PackedByteArray()
 while true:
  if _is_cancelled():
   return {}
  var chunk := file.get_buffer(mini(CHUNK_BYTES, MAX_FILE_BYTES + 1 - bytes.size()))
  if file.get_error() not in [OK, ERR_FILE_EOF]:
   return {"error": "Read failed: " + error_string(file.get_error())}
  if chunk.is_empty():
   break
  bytes.append_array(chunk)
  if bytes.size() > MAX_FILE_BYTES:
   return {"error": "File exceeds 32 MiB. Resize it before importing."}
 file.close()
 var decoder := Decoder.new()
 var info: Dictionary = decoder.inspect(bytes)
 if not str(info.get("error", "")).is_empty():
  return {"error": str(info.error)}
 var decoded: Image = decoder.decode_bytes(bytes)
 if decoded == null:
  return {"error": decoder.error_message}
 decoded = null
 if _is_cancelled():
  return {}
 var hasher := HashingContext.new()
 hasher.start(HashingContext.HASH_SHA256)
 hasher.update(bytes)
 var digest := hasher.finish().hex_encode()
 var extension := "jpg" if str(info.format) == "jpeg" else str(info.format)
 var target := destination.path_join(digest + "." + extension)
 if FileAccess.file_exists(target):
  if FileAccess.get_sha256(target) == digest:
   return {"path": target}
  return {"error": "An existing library copy is damaged; it was not overwritten."}
 var temporary := target + ".part"
 var output := FileAccess.open(temporary, FileAccess.WRITE)
 if output == null:
  return {"error": "Cannot write the library copy: " + error_string(FileAccess.get_open_error())}
 output.store_buffer(bytes)
 output.flush()
 var write_error := output.get_error()
 output.close()
 if write_error != OK or FileAccess.get_sha256(temporary) != digest:
  DirAccess.remove_absolute(temporary)
  return {"error": "Could not save the entire photograph. Check free storage."}
 var metadata := ConfigFile.new()
 metadata.set_value("photo", "original_name", display_name)
 metadata.set_value("photo", "imported_unix", Time.get_unix_time_from_system())
 metadata.set_value("photo", "sha256", digest)
 var sidecar := target + ".import.cfg"
 var metadata_error := metadata.save(sidecar + ".part")
 if metadata_error != OK or _is_cancelled():
  DirAccess.remove_absolute(temporary)
  if FileAccess.file_exists(sidecar + ".part"):
   DirAccess.remove_absolute(sidecar + ".part")
  return {} if _is_cancelled() else {"error": "Cannot save import metadata: " + error_string(metadata_error)}
 var commit_error := DirAccess.rename_absolute(temporary, target)
 if commit_error == OK:
  commit_error = DirAccess.rename_absolute(sidecar + ".part", sidecar)
 if commit_error != OK:
  for cleanup in [temporary, target, sidecar + ".part"]:
   if FileAccess.file_exists(cleanup):
    DirAccess.remove_absolute(cleanup)
  return {"error": "Cannot finish import: " + error_string(commit_error)}
 return {"path": target}

func original_name(source: String) -> String:
 var name_value := ""
 if source.begins_with("content://") and OS.get_name() == "Android":
  name_value = _android_display_name(source)
 if name_value.is_empty():
  name_value = source.uri_decode().get_file()
  if source.begins_with("content://") and name_value.get_extension().to_lower() not in ["jpg", "jpeg", "png", "webp", "bmp"]:
   name_value = "Photo " + source.sha256_text().substr(0, 8)
 # Display text only; never use provider-controlled names as a destination path.
 name_value = name_value.replace("/", "_").replace("\\", "_").replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges()
 return name_value.left(180) if not name_value.is_empty() else "Photograph"

func _android_display_name(source: String) -> String:
 if not Engine.has_singleton("AndroidRuntime") or not Engine.has_singleton("JavaClassWrapper"):
  return ""
 var runtime: Object = Engine.get_singleton("AndroidRuntime")
 var bridge: Object = Engine.get_singleton("JavaClassWrapper")
 var context: Object = runtime.getApplicationContext()
 var uri_class: Object = bridge.wrap("android.net.Uri")
 if context == null or uri_class == null:
  return ""
 var resolver: Object = context.getContentResolver()
 var uri: Object = uri_class.parse(source)
 if resolver == null or uri == null:
  return ""
 var cursor: Object = resolver.query(uri, PackedStringArray(["_display_name"]), null, null, null)
 if cursor == null:
  return ""
 var result := ""
 if cursor.moveToFirst():
  var column: int = cursor.getColumnIndex("_display_name")
  if column >= 0:
   result = str(cursor.getString(column))
 cursor.close()
 return result
