extends RefCounted
## Worker-owned state: never binds a running thread to a scene Node.
const Store = preload("res://scripts/ai/conversion_store.gd")
const Library = preload("res://scripts/photo_library.gd")
const Reproject = preload("res://scripts/depth_reprojection.gd")
var backend_available := false
var _job: Dictionary = {}
var _record: Dictionary = {}
var _source: Image
var _key := ""
var _mutex := Mutex.new()
var _cancel := false
func request_cancel() -> void:
 _mutex.lock()
 _cancel = true
 _mutex.unlock()
func is_cancelled() -> bool:
 _mutex.lock()
 var value := _cancel
 _mutex.unlock()
 return value

func prepare(job: Dictionary) -> Dictionary:
 var hash := Store.source_hash(str(job.source_path))
 if hash.is_empty():
  return {"error": "Cannot read source photograph."}
 var key := Store.key_for(hash, str(job.model), str(job.quality))
 var cached := Store.load_record(key)
 var loader := Library.new()
 var image: Image = loader.load_image(job.entry, Reproject.max_side_for(Reproject.quality_index(job.quality)))
 if image == null:
  return {"error": loader.error_message}
 var result := {"hash": hash, "key": key, "source": image, "cached": cached}
 if not cached.is_empty():
  result["raw_path"] = str(cached.directory).path_join("raw.qpd")
  return result
 var model_path := "res://models/" + str(job.model) + ".onnx.bin"
 if not FileAccess.file_exists(model_path):
  return {"error": "Model not installed: " + str(job.model_name) + ". Rebuild the APK with all validated models included."}
 if not backend_available:
  return {"error": "QuestDepth Android inference plugin is unavailable. Existing viewer remains usable."}
 var work := "user://ai-work/" + key + "-" + str(Time.get_ticks_usec())
 var err := DirAccess.make_dir_recursive_absolute(work)
 if err != OK:
  return {"error": "Cannot create AI working directory: " + error_string(err)}
 result["work"] = work
 result["raw_path"] = work.path_join("raw.qpd")
 # Maximum changes reconstruction only; feed inference the identical High
 # source decode (1536 cap) instead of a differently resampled 2048 working copy.
 var inference_source: Image = loader.load_image(job.entry, 1536) if job.quality == "Maximum Quality" else image
 if inference_source == null:
  result["error"] = loader.error_message
  return result
 err = inference_source.save_png(work.path_join("input.png"))
 if err != OK:
  result["error"] = "Cannot save processing copy."
  return result
 # Only one extracted model is kept. Originals and completed conversions are untouched.
 var model_dir := "user://ai-model"
 DirAccess.make_dir_recursive_absolute(model_dir)
 var expected := str(job.model_info.get("onnx_sha256", ""))
 if expected.length() != 64 or not expected.is_valid_hex_number(false):
  result["error"] = "Missing validated model checksum in APK catalog."
  return result
 var target := model_dir.path_join(str(job.model) + "-" + expected + ".onnx")
 if FileAccess.file_exists(target) and FileAccess.get_sha256(target) != expected:
  DirAccess.remove_absolute(target)
 if not FileAccess.file_exists(target):
  for name in DirAccess.get_files_at(model_dir):
   DirAccess.remove_absolute(model_dir.path_join(name))
  var input := FileAccess.open(model_path, FileAccess.READ)
  var output := FileAccess.open(target + ".partial", FileAccess.WRITE)
  if input == null or output == null:
   result["error"] = "Cannot extract installed model."
   return result
  var hashing := HashingContext.new()
  hashing.start(HashingContext.HASH_SHA256)
  while input.get_position() < input.get_length():
   if is_cancelled():
    output.close()
    DirAccess.remove_absolute(target + ".partial")
    result["error"] = "Conversion cancelled during model extraction."
    return result
   var chunk := input.get_buffer(mini(1024 * 1024, input.get_length() - input.get_position()))
   if chunk.is_empty():
    output.close()
    DirAccess.remove_absolute(target + ".partial")
    result["error"] = "Cannot read installed model bytes."
    return result
   hashing.update(chunk)
   output.store_buffer(chunk)
  if hashing.finish().hex_encode() != expected or output.get_error() != OK:
   output.close()
   DirAccess.remove_absolute(target + ".partial")
   result["error"] = "Model extraction failed checksum or storage check."
   return result
  output.close()
  input.close()
  err = DirAccess.rename_absolute(target + ".partial", target)
  if err != OK:
   result["error"] = "Cannot finalize installed model."
   return result
 result["model_path"] = target
 return result

func reconstruct(save_raw: bool, intensity: float, plane: float) -> Dictionary:
 if Store.source_hash(str(_job.source_path)) != str(_job.source_sha256):
  return {"error": "Source changed during conversion."}
 var preview := Store.preview_path(_key, _job.quality)
 var cached_image := preview + ".png"
 var previous := Store.load_preview_info(_key, _job.quality)
 if not save_raw and previous.get("renderer") == Reproject.REVISION and is_equal_approx(float(previous.get("strength", -1)), intensity) and is_equal_approx(float(previous.get("plane", -1)), plane) and FileAccess.file_exists(cached_image):
  var decoded := Image.new()
  if decoded.load_png_from_buffer(FileAccess.get_file_as_bytes(cached_image)) == OK:
   _record["reconstruction_ms"] = 0
   _record["total_ms"] = Time.get_ticks_msec() - int(_job.get("started_ms", Time.get_ticks_msec()))
   _record["preview_reused"] = true
   return {"image": decoded, "record": _record, "raw_path": _job.raw_path}
 var raw_path := str(_job.raw_path)
 var raw := Store.read_depth(raw_path)
 if raw == null:
  return {"error": "Invalid model depth output. Completed conversions were preserved."}
 if is_cancelled():
  return {"error": "Conversion cancelled."}
 if save_raw:
  var err := Store.save_record(_key, raw_path, _record)
  if err != OK:
   return {"error": "Cannot persist original AI depth: " + error_string(err)}
  _job["raw_path"] = Store.ROOT.path_join(_key).path_join("raw.qpd")
 var depth := raw
 if not bool(_job.inverse_depth):
  depth = raw.duplicate()
  # DA3 camera depth: reciprocal makes closer points larger without altering raw.qpd.
  for y in depth.get_height():
   for x in depth.get_width():
    var v := raw.get_pixel(x, y).r
    depth.set_pixel(x, y, Color(1.0 / maxf(v, 0.000001), 0, 0))
 var begin := Time.get_ticks_msec()
 var image: Image = Reproject.reconstruct(_source, depth, intensity, plane, _job.quality, func() -> bool: return is_cancelled())
 _record["reconstruction_ms"] = Time.get_ticks_msec() - begin
 _record["preview_reused"] = false
 if image == null:
  return {"error": "Stereo reconstruction failed: invalid image or depth data."}
 if is_cancelled():
  return {"error": "Conversion cancelled."}
 var saved := image.save_png(cached_image + ".pending")
 if saved == OK:
  saved = DirAccess.rename_absolute(cached_image + ".pending", cached_image)
 if saved != OK:
  return {"error": "Cannot cache finished stereo image."}
 if Store.save_adjustments(_key, intensity, plane) != OK:
  return {"error": "Cannot persist stereo adjustments."}
 _record["total_ms"] = Time.get_ticks_msec() - int(_job.get("started_ms", begin))
 var info := _record.duplicate(true)
 info.merge({"strength": intensity, "plane": plane, "renderer": Reproject.REVISION}, true)
 var metadata := FileAccess.open(preview + ".json.pending", FileAccess.WRITE)
 if metadata == null:
  return {"error": "Cannot save reconstruction timing/quality metadata."}
 metadata.store_string(JSON.stringify(info))
 var write_error := metadata.get_error()
 metadata.close()
 if write_error != OK or DirAccess.rename_absolute(preview + ".json.pending", preview + ".json") != OK:
  return {"error": "Cannot finalize reconstruction metadata."}
 return {"image": image, "record": _record, "raw_path": _job.raw_path}

