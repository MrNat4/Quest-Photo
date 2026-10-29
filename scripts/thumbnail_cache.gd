class_name PhotoThumbnailCache
extends Node
## Demand-driven thumbnails: one CPU decoder worker, bounded RAM and disk caches.
## Textures are created only on the scene thread. No worker accesses scene nodes
## or shares decoded Images with the viewer. Exit joins the active worker.

signal texture_ready(key: String, texture: Texture2D, error: String)
const Library = preload("res://scripts/photo_library.gd")
const CACHE_VERSION := 1
const MAX_CACHE_BYTES := 2 * 1024 * 1024
var cache_dir := "user://thumbnails"
var thumbnail_side := 256
var memory_limit := 18
var disk_limit := 128
var _textures: Dictionary = {}
var _lru: Array[String] = []
var _queue: Array[Dictionary] = []
var _thread: Thread
var _active: Dictionary = {}
var _revision := 0
var decoded_count := 0

func _ready() -> void:
 if DirAccess.dir_exists_absolute(cache_dir):
  _trim_disk()

func key_for(entry: Dictionary) -> String:
 var path := str(entry.get("path", ""))
 var size := 0
 var file := FileAccess.open(path, FileAccess.READ)
 if file != null:
  size = file.get_length()
 var fingerprint := "%d:%d:%s:%s:%d:%d" % [FileAccess.get_modified_time(path), size,
  str(entry.get("layout", "")), str(entry.get("sbs", false)), clampi(thumbnail_side, 32, 512), CACHE_VERSION]
 return path.sha256_text() + "_" + fingerprint.sha256_text()

func has(entry: Dictionary) -> bool:
 return _textures.has(key_for(entry))

func get_texture(entry: Dictionary) -> Texture2D:
 var key := key_for(entry)
 if not _textures.has(key):
  return null
 _touch(key)
 return _textures[key] as Texture2D

func request(entry: Dictionary) -> void:
 var key := key_for(entry)
 if _textures.has(key):
  _touch(key)
  texture_ready.emit(key, _textures[key], "")
  return
 if not _active.is_empty() and _active.key == key and _active.revision == _revision:
  return
 for job in _queue:
  if job.key == key:
   return
 # Six current-page requests are normal. Bound misuse as well as gallery demand.
 if _queue.size() >= 24:
  _queue.pop_front()
 _queue.append({"key": key, "entry": entry.duplicate(true), "revision": _revision,
  "disk_path": cache_dir.path_join(key + ".png"), "side": clampi(thumbnail_side, 32, 512)})
 _pump()

func cancel_pending() -> void:
 _queue.clear()

func invalidate(path: String = "") -> void:
 _revision += 1
 cancel_pending()
 var prefix := path.sha256_text() + "_" if not path.is_empty() else ""
 for key: String in _textures.keys():
  if prefix.is_empty() or key.begins_with(prefix):
   _textures.erase(key)
   _lru.erase(key)
 if DirAccess.dir_exists_absolute(cache_dir):
  for name in DirAccess.get_files_at(cache_dir):
   if name.ends_with(".png") and (prefix.is_empty() or name.begins_with(prefix)):
    DirAccess.remove_absolute(cache_dir.path_join(name))

func in_memory_count() -> int:
 return _textures.size()

func pending_count() -> int:
 return _queue.size() + (0 if _active.is_empty() else 1)

func _touch(key: String) -> void:
 _lru.erase(key)
 _lru.append(key)

func _pump() -> void:
 if not _active.is_empty() or _queue.is_empty() or not is_inside_tree():
  return
 _active = _queue.pop_front()
 _thread = Thread.new()
 var result := _thread.start(_decode.bind(_active.duplicate(true)))
 if result != OK:
  var key: String = _active.key
  _active.clear()
  _thread = null
  texture_ready.emit(key, null, "Cannot start thumbnail decoder: " + error_string(result))

func _process(_delta: float) -> void:
 if _thread != null and not _thread.is_alive():
  var result: Dictionary = _thread.wait_to_finish()
  var job := _active
  _active = {}
  _thread = null
  if job.revision == _revision and key_for(job.entry) == job.key:
   var decoded: Image = result.get("image")
   if decoded == null:
    texture_ready.emit(job.key, null, str(result.get("error", "Thumbnail unavailable")))
   else:
    if not bool(result.get("disk_hit", false)):
     decoded_count += 1
    var texture := ImageTexture.create_from_image(decoded)
    _textures[job.key] = texture
    _touch(job.key)
    while _lru.size() > maxi(1, memory_limit):
     _textures.erase(_lru.pop_front())
    if disk_limit > 0 and DirAccess.make_dir_recursive_absolute(cache_dir) == OK:
     # Writing at most 512² pixels is bounded; never write a stale worker result.
     decoded.save_png(job.disk_path)
     _trim_disk()
    texture_ready.emit(job.key, texture, "")
 _pump()

func _decode(job: Dictionary) -> Dictionary:
 var library := Library.new()
 var disk_path: String = job.disk_path
 if FileAccess.file_exists(disk_path):
  var cached_file := FileAccess.open(disk_path, FileAccess.READ)
  if cached_file != null and cached_file.get_length() <= MAX_CACHE_BYTES:
   var bytes := cached_file.get_buffer(cached_file.get_length())
   var dimensions: Vector2i = library.inspect_dimensions(bytes)
   if dimensions.x > 0 and dimensions.y > 0 and dimensions.x <= job.side and dimensions.y <= job.side:
    var cached := Image.new()
    if cached.load_png_from_buffer(bytes) == OK:
     return {"image": cached, "disk_hit": true}
 var entry: Dictionary = job.entry.duplicate(true)
 var photo: Image = library.load_image(entry, job.side)
 if photo == null:
  return {"image": null, "error": library.error_message}
 if bool(entry.get("sbs", false)):
  photo = photo.get_region(Rect2i(0, 0, photo.get_width() / 2, photo.get_height()))
 var ratio := minf(1.0, float(job.side) / maxi(photo.get_width(), photo.get_height()))
 if ratio < 1.0:
  photo.resize(maxi(1, roundi(photo.get_width() * ratio)), maxi(1, roundi(photo.get_height() * ratio)), Image.INTERPOLATE_BILINEAR)
 return {"image": photo, "disk_hit": false}

func _trim_disk() -> void:
 var files: Array[Dictionary] = []
 for name in DirAccess.get_files_at(cache_dir):
  if name.ends_with(".png"):
   files.append({"name": name, "time": FileAccess.get_modified_time(cache_dir.path_join(name))})
 files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
  return a.name < b.name if a.time == b.time else a.time < b.time)
 while files.size() > maxi(0, disk_limit):
  DirAccess.remove_absolute(cache_dir.path_join(str(files.pop_front().name)))

func _exit_tree() -> void:
 cancel_pending()
 if _thread != null and _thread.is_started():
  _thread.wait_to_finish()
 _thread = null
 _active.clear()
