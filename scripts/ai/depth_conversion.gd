extends Node
## One preparation/reconstruction worker and one native inference job. No mock backend.
signal status_changed(message: String)
signal result_ready(image: Image, record: Dictionary)
const Store = preload("res://scripts/ai/conversion_store.gd")
const Library = preload("res://scripts/photo_library.gd")
const Reproject = preload("res://scripts/depth_reprojection.gd")
const MODELS := ["v2_small", "v3_small", "v3_base"]
const NAMES := ["V2 Small", "V3 Small", "V3 Base"]
var selected_model := 0
var high_quality := false
var strength := 0.02
var screen_plane := 0.5
var busy := false
var message := ""
var backend: Object
var _thread: Thread
var _stage := ""
var _cancelled := false
var _job: Dictionary = {}
var _source: Image
var _depth: Image
var _record: Dictionary = {}
var _key := ""
var _work := ""
var _started := 0
var _poll := 0.0
var _completed_context: Dictionary = {}

func _ready() -> void:
 if Engine.has_singleton("QuestDepth"):
  backend = Engine.get_singleton("QuestDepth")

func model_name() -> String:
 return NAMES[selected_model]

func quality_name() -> String:
 return "High Quality" if high_quality else "Balanced"

func select_next_model() -> void:
 if busy:
  _status("Cancel or finish the current conversion before changing model.")
  return
 if backend != null:
  backend.release_model()
 selected_model = (selected_model + 1) % MODELS.size()
 _status("Selected " + model_name() + ". Saved results remain available.")

func _status(value: String) -> void:
 message = value
 status_changed.emit(value)

func start(entry: Dictionary) -> void:
 if busy:
  _status("One conversion at a time. Cancel or wait.")
  return
 if bool(entry.get("sbs", false)):
  _status("Select an ordinary 2D photo for AI conversion.")
  return
 var model_id: String = MODELS[selected_model]
 var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://models/catalog.json")) if FileAccess.file_exists("res://models/catalog.json") else {}
 var info: Dictionary = manifest.get(model_id, {}) if manifest is Dictionary else {}
 _job = {"entry": entry.duplicate(true), "model": model_id, "model_name": model_name(),
  "quality": quality_name(), "resolution": 518 if high_quality else 364,
  "inverse_depth": selected_model == 0, "model_info": info,
  "source_path": str(entry.get("path", ""))}
 _started = Time.get_ticks_msec()
 _cancelled = false
 busy = true
 _stage = "prepare"
 _start_worker(_prepare.bind(_job.duplicate(true)))
 _status("Checking saved conversion…")

func _start_worker(callable: Callable) -> void:
 _thread = Thread.new()
 var err := _thread.start(callable)
 if err != OK:
  _finish_error("Cannot start conversion worker: " + error_string(err))

func _prepare(job: Dictionary) -> Dictionary:
 var hash := Store.source_hash(str(job.source_path))
 if hash.is_empty():
  return {"error": "Cannot read source photograph."}
 var key := Store.key_for(hash, str(job.model), str(job.quality))
 var cached := Store.load_record(key)
 var loader := Library.new()
 var image: Image = loader.load_image(job.entry, 1536 if job.quality == "High Quality" else 1024)
 if image == null:
  return {"error": loader.error_message}
 var result := {"hash": hash, "key": key, "source": image, "cached": cached}
 if not cached.is_empty():
  result["raw_path"] = str(cached.directory).path_join("raw.qpd")
  return result
 var model_path := "res://models/" + str(job.model) + ".onnx.bin"
 if not FileAccess.file_exists(model_path):
  return {"error": "Model not installed: " + str(job.model_name) + ". See docs/AI_STATUS.md; no simulated inference is used."}
 if backend == null:
  return {"error": "QuestDepth Android inference plugin is unavailable. Existing viewer remains usable."}
 var work := "user://ai-work/" + key + "-" + str(Time.get_ticks_usec())
 var err := DirAccess.make_dir_recursive_absolute(work)
 if err != OK:
  return {"error": "Cannot create AI working directory: " + error_string(err)}
 result["work"] = work
 result["raw_path"] = work.path_join("raw.qpd")
 err = image.save_png(work.path_join("input.png"))
 if err != OK:
  result["error"] = "Cannot save processing copy."
  return result
 # Only one extracted model is kept. Originals and completed conversions are untouched.
 var model_dir := "user://ai-model"
 DirAccess.make_dir_recursive_absolute(model_dir)
 var target := model_dir.path_join(str(job.model) + ".onnx")
 if not FileAccess.file_exists(target):
  for name in DirAccess.get_files_at(model_dir):
   DirAccess.remove_absolute(model_dir.path_join(name))
  var input := FileAccess.open(model_path, FileAccess.READ)
  var output := FileAccess.open(target + ".partial", FileAccess.WRITE)
  if input == null or output == null:
   result["error"] = "Cannot extract installed model."
   return result
  while input.get_position() < input.get_length():
   output.store_buffer(input.get_buffer(mini(1024 * 1024, input.get_length() - input.get_position())))
  output.close()
  input.close()
  err = DirAccess.rename_absolute(target + ".partial", target)
  if err != OK:
   result["error"] = "Cannot finalize installed model."
   return result
 result["model_path"] = target
 return result

func _process(delta: float) -> void:
 if not busy:
  return
 if _thread != null and _thread.is_started() and not _thread.is_alive():
  var result: Dictionary = _thread.wait_to_finish()
  _thread = null
  if _cancelled:
   _finish_error("Conversion cancelled. Completed results preserved.")
   return
  if result.has("work"):
   _work = result.work
  if result.has("error"):
   _finish_error(result.error)
   return
  if _stage == "prepare":
   _key = result.key
   _source = result.source
   _job["source_sha256"] = result.hash
   _job["raw_path"] = result.raw_path
   if not result.cached.is_empty():
    _record = result.cached
    _record["source_path"] = _job.source_path
    var adjustment := Store.adjustments(_key)
    strength = adjustment.strength
    screen_plane = adjustment.plane
    _start_reconstruction()
   else:
    _stage = "inference"
    _status("Running " + str(_job.model_name) + " locally…")
    if not backend.start(ProjectSettings.globalize_path(result.model_path), ProjectSettings.globalize_path(_work.path_join("input.png")), ProjectSettings.globalize_path(result.raw_path), int(_job.resolution), bool(_job.inverse_depth)):
     _finish_error("Native inference refused the job; inspect QuestDepth status.")
  elif _stage == "reconstruct":
   if Store.source_hash(str(_job.source_path)) != str(_job.source_sha256):
    _finish_error("Source changed during conversion. Result was not displayed.")
    return
   busy = false
   _record["key"] = _key
   _record["strength"] = strength
   _record["screen_plane"] = screen_plane
   _completed_context = {"job": _job.duplicate(true), "source": _source, "record": _record.duplicate(true), "key": _key}
   result_ready.emit(result.image, _record.duplicate(true))
   _cleanup()
   _status("Showing " + str(_record.model_name) + " · " + str(_record.quality) + " · %.1f s" % (float(_record.get("inference_ms", 0)) / 1000.0))
 if _stage == "inference" and busy:
  _poll += delta
  if _poll < 0.2:
   return
  _poll = 0
  var native: Variant = JSON.parse_string(str(backend.get_status()))
  if not native is Dictionary:
   return
  if native.get("state") == "completed":
   if _cancelled:
    _finish_error("Conversion cancelled. Completed results preserved.")
    return
   _record = _job.duplicate(true)
   _record.erase("entry")
   _record.erase("raw_path")
   _record["inference_ms"] = native.get("inference_ms", Time.get_ticks_msec() - _started)
   _record["created_utc"] = Time.get_datetime_string_from_system(true)
   _start_reconstruction(true)
  elif native.get("state") in ["error", "cancelled"]:
   _finish_error(str(native.get("error", native.get("message", "Inference cancelled or failed."))))

func _start_reconstruction(save_raw: bool = false) -> void:
 _stage = "reconstruct"
 _status("Reconstructing separate left/right views…")
 _start_worker(_reconstruct.bind(save_raw, strength, screen_plane))

func _reconstruct(save_raw: bool, intensity: float, plane: float) -> Dictionary:
 var cached_image := Store.ROOT.path_join(_key).path_join("preview.png")
 var previous := Store.adjustments(_key)
 if not save_raw and FileAccess.file_exists(cached_image) and is_equal_approx(float(previous.strength), intensity) and is_equal_approx(float(previous.plane), plane):
  var decoded := Image.new()
  if decoded.load_png_from_buffer(FileAccess.get_file_as_bytes(cached_image)) == OK:
   return {"image": decoded}
 var raw_path := str(_job.raw_path)
 var raw := Store.read_depth(raw_path)
 if raw == null:
  return {"error": "Invalid model depth output. Completed conversions were preserved."}
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
 var image: Image = Reproject.reconstruct(_source, depth, intensity, plane, _job.quality == "High Quality", func() -> bool: return _cancelled)
 if image == null:
  return {"error": "Stereo reconstruction failed: invalid image or depth data."}
 if _cancelled:
  return {"error": "Conversion cancelled."}
 var saved := image.save_png(cached_image + ".pending")
 if saved == OK:
  saved = DirAccess.rename_absolute(cached_image + ".pending", cached_image)
 if saved != OK:
  return {"error": "Cannot cache finished stereo image."}
 Store.save_adjustments(_key, intensity, plane)
 _record["reconstruction_ms"] = Time.get_ticks_msec() - begin
 return {"image": image}

func adjust(delta_strength: float, delta_plane: float) -> void:
 if busy or _completed_context.is_empty():
  _status("Show a saved conversion before adjusting its depth.")
  return
 _job = _completed_context.job.duplicate(true)
 _source = _completed_context.source
 _record = _completed_context.record.duplicate(true)
 _key = _completed_context.key
 strength = clampf(strength + delta_strength, 0, 0.04)
 screen_plane = clampf(screen_plane + delta_plane, 0, 1)
 busy = true
 _cancelled = false
 _start_reconstruction()

func cancel() -> void:
 if not busy:
  return
 _cancelled = true
 if _stage == "inference" and backend != null:
  backend.cancel()
 _status("Cancelling; waiting for the current operation to release resources…")

func _finish_error(value: String) -> void:
 busy = false
 _stage = ""
 _cleanup()
 _status(value)

func _cleanup() -> void:
 if not _work.is_empty():
  for name in DirAccess.get_files_at(_work):
   DirAccess.remove_absolute(_work.path_join(name))
  DirAccess.remove_absolute(_work)
  _work = ""

func _exit_tree() -> void:
 cancel()
 if _thread != null and _thread.is_started():
  _thread.wait_to_finish()
 # Native cancellation may still be finishing; never delete its active input here.
 if backend != null:
  backend.release_model()
