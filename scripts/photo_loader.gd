class_name PhotoLoader
extends Node
## One decode at a time. New requests replace the pending request; stale results
## never replace the displayed image. ImageTexture creation stays on the main thread.
signal loaded(request_id: int, entry: Dictionary, image: Image, message: String)
const Library = preload("res://scripts/photo_library.gd")
var _thread: Thread
var _pending: Dictionary = {}
var _generation := 0

func request(entry: Dictionary) -> int:
 _generation += 1
 _pending = {"id": _generation, "entry": entry.duplicate(true)}
 _start_pending()
 return _generation

func cancel() -> void:
 _generation += 1
 _pending.clear()

func is_busy() -> bool:
 return (_thread != null and _thread.is_started()) or not _pending.is_empty()

func _start_pending() -> void:
 if _pending.is_empty() or (_thread != null and _thread.is_started()):
  return
 var job := _pending
 _pending = {}
 _thread = Thread.new()
 var result := _thread.start(_decode.bind(job))
 if result != OK:
  loaded.emit(job.id, job.entry, null, "Cannot start image decoder: " + error_string(result))

func _decode(job: Dictionary) -> Dictionary:
 var source := Library.new()
 var image: Image = source.load_image(job.entry)
 return {"id": job.id, "entry": job.entry, "image": image, "error": source.error_message}

func _process(_delta: float) -> void:
 if _thread != null and _thread.is_started() and not _thread.is_alive():
  var result: Dictionary = _thread.wait_to_finish()
  if result.id == _generation:
   loaded.emit(result.id, result.entry, result.image, result.error)
  _start_pending()

func _exit_tree() -> void:
 cancel()
 if _thread != null and _thread.is_started():
  _thread.wait_to_finish()
