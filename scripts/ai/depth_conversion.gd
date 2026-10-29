extends Node
## One preparation/reconstruction worker and one native inference job. No mock backend.
signal status_changed(message: String)
signal result_ready(image: Image, record: Dictionary)
const Store = preload("res://scripts/ai/conversion_store.gd")
const Library = preload("res://scripts/photo_library.gd")
const Reproject = preload("res://scripts/depth_reprojection.gd")
const Job = preload("res://scripts/ai/depth_job.gd")
var _worker: RefCounted
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
 _worker = Job.new()
 _worker.backend_available = backend != null
 _start_worker(_worker.prepare.bind(_job.duplicate(true)))
 _status("Checking saved conversion…")

func _start_worker(callable: Callable) -> void:
 _thread = Thread.new()
 var err := _thread.start(callable)
 if err != OK:
  _finish_error("Cannot start conversion worker: " + error_string(err))

func _process(delta: float) -> void:
 if not busy:
  return
 if _thread != null and _thread.is_started() and not _thread.is_alive():
  var result: Dictionary = _thread.wait_to_finish()
  _thread = null
  if result.has("work"):
   _work = result.work
  if _cancelled:
   _finish_error("Conversion cancelled. Completed results preserved.")
   return
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
   _record = result.record
   _job["raw_path"] = result.raw_path
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
   _finish_error(str(native.get("error", "")) if not str(native.get("error", "")).is_empty() else str(native.get("message", "Inference cancelled or failed.")))

func _start_reconstruction(save_raw: bool = false) -> void:
 _stage = "reconstruct"
 _status("Reconstructing separate left/right views…")
 _worker = Job.new()
 _worker._job = _job.duplicate(true)
 _worker._record = _record.duplicate(true)
 _worker._source = _source
 _worker._key = _key
 _start_worker(_worker.reconstruct.bind(save_raw, strength, screen_plane))

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
 if _worker != null:
  _worker.request_cancel()
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
