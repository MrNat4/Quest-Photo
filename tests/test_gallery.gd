extends SceneTree
## Logical gallery navigation and real thumbnail file/cache tests.
## Headless checks do not verify text legibility, GPU rendering, or VR controllers.

var checks := 0
var failures := 0
var gallery: Node3D
var cache: Node
var test_dir := ""
var selected_events: Array[int] = []
var action_events: Array[String] = []
var thumbnail_events: Array[Dictionary] = []

func _initialize() -> void:
 call_deferred("_run")

func check(condition: bool, message: String) -> void:
 checks += 1
 if not condition:
  failures += 1
  push_error("FAIL: " + message)

func _run() -> void:
 test_dir = "user://gallery-tests-" + str(Time.get_ticks_usec())
 DirAccess.make_dir_recursive_absolute(test_dir)
 var gallery_script := load("res://scripts/photo_gallery.gd") as Script
 var cache_script := load("res://scripts/thumbnail_cache.gd") as Script
 if gallery_script == null or cache_script == null or not gallery_script.can_instantiate() or not cache_script.can_instantiate():
  check(false, "gallery and cache scripts compile")
  quit(1)
  return
 gallery = gallery_script.new()
 gallery.visible = false
 root.add_child(gallery)
 gallery.photo_selected.connect(func(index: int): selected_events.append(index))
 gallery.import_requested.connect(func(): action_events.append("import"))
 gallery.refresh_requested.connect(func(): action_events.append("refresh"))
 gallery.layout_requested.connect(func(): action_events.append("layout"))
 gallery.close_requested.connect(func(): action_events.append("close"))
 _test_navigation()
 gallery.free()
 cache = cache_script.new()
 cache.cache_dir = test_dir.path_join("cache")
 cache.memory_limit = 2
 cache.disk_limit = 3
 cache.thumbnail_side = 64
 root.add_child(cache)
 cache.texture_ready.connect(func(key: String, texture: Texture2D, error: String): thumbnail_events.append({"key": key, "texture": texture, "error": error}))
 await _test_cache()
 await _test_visible_page_demand()
 cache.free()
 _remove_tree(test_dir)
 print("GALLERY TESTS: %d checks, %d failures. Headless navigation/cache behavior only; VR presentation remains unverified." % [checks, failures])
 quit(1 if failures else 0)

func _entries(count: int) -> Array[Dictionary]:
 var entries: Array[Dictionary] = []
 for i in count:
  entries.append({"path": test_dir.path_join("photo-%04d.png" % i), "title": "Photo %04d" % i, "sbs": false})
 return entries

func _node_count(node: Node) -> int:
 var result := 1
 for child in node.get_children():
  result += _node_count(child)
 return result

func _test_navigation() -> void:
 gallery.set_entries(_entries(12))
 var small_tree_count := _node_count(gallery)
 gallery.set_entries(_entries(1000))
 check(_node_count(gallery) == small_tree_count, "gallery reuses fixed visual nodes for large collections")
 check(gallery._cells.size() == 6, "gallery allocates exactly six thumbnail tiles")
 check(gallery.cache.pending_count() == 0, "hidden gallery does not enqueue collection decoding")
 check(gallery.page_count() == 167, "1000 photographs paginate into 167 six-photo pages")
 check(gallery.page_index == 0, "new collection starts at first page")
 gallery.focus_index = 0
 gallery.activate()
 check(selected_events == [0], "first tile activates first photo")
 gallery.focus_index = 10
 gallery.activate()
 check(gallery.page_index == 1, "Next advances gallery page")
 gallery.focus_index = 2
 gallery.activate()
 check(selected_events.back() == 8, "page-local focus maps to absolute photo index")
 gallery.focus_index = 9
 gallery.activate()
 check(gallery.page_index == 0, "Previous returns to first page")
 gallery.activate()
 check(gallery.page_index == 0, "Previous at first page stays in range")
 gallery.select_index(999)
 check(gallery.page_index == 166, "select_index reveals photo on last page")
 check(gallery.selected_index == 999 and gallery.selected_entry_index() == 999, "selected photo is retained for highlight and layout action")
 gallery.focus_index = 3
 gallery.activate()
 check(selected_events.back() == 999, "last partial page maps populated tile")
 var event_count := selected_events.size()
 gallery.focus_index = 5
 gallery.activate()
 check(selected_events.size() == event_count, "empty final-page tile cannot select nonexistent photo")
 gallery.focus_index = 10
 gallery.activate()
 check(gallery.page_index == 166, "Next at final page stays in range")
 for pair in [[6, "import"], [7, "refresh"], [8, "layout"], [11, "close"]]:
  gallery.focus_index = pair[0]
  gallery.activate()
  check(action_events.back() == pair[1], "gallery action emits " + pair[1])
 gallery.set_status("Three photos imported")
 check(gallery._status.text == "Three photos imported", "status message reaches gallery label")
 gallery.set_entries(_entries(0))
 check(gallery.page_count() == 1 and gallery.page_index == 0, "empty library keeps one usable action page")
 gallery.focus_index = 0
 gallery.activate()
 check(selected_events.size() == event_count, "empty library cannot activate photo")
 gallery.focus_index = 6
 gallery.activate()
 check(action_events.back() == "import", "empty library still permits import")
 gallery.set_entries(_entries(12))
 gallery.select_index(0)
 gallery.move_focus(Vector2.RIGHT)
 check(gallery.focus_index == 1, "discrete right navigation advances tile focus")
 gallery.move_focus(Vector2.LEFT)
 check(gallery.focus_index == 0, "discrete left navigation restores tile focus")
 var previous: int = gallery.focus_index
 gallery.move_focus(Vector2.ZERO)
 check(gallery.focus_index == previous, "zero stick movement preserves focus")
 gallery.select_index(8)
 var reordered := _entries(12)
 reordered.reverse()
 gallery.set_entries(reordered)
 check(gallery.selected_index == 3 and gallery.selected_entry_index() == 3, "refresh preserves selected photo identity after reordering")
 gallery.move_focus(Vector2.DOWN)
 check(gallery.selected_entry_index() == 3, "moving onto toolbar retains photo target for Layout")

func _fixture(index: int, color: Color) -> Dictionary:
 var path := test_dir.path_join("fixture-%d.png" % index)
 var image := Image.create(320, 200, false, Image.FORMAT_RGB8)
 image.fill(color)
 check(image.save_png(path) == OK, "thumbnail source fixture saved")
 return {"path": path, "title": "Fixture %d" % index, "sbs": false}

func _wait_for_texture(entry: Dictionary) -> Texture2D:
 var deadline := Time.get_ticks_msec() + 5000
 var key: String = cache.key_for(entry)
 while Time.get_ticks_msec() < deadline:
  var texture: Texture2D = cache.get_texture(entry)
  if texture != null:
   return texture
  for event in thumbnail_events:
   if event.key == key and not event.error.is_empty():
    check(false, "thumbnail failed: " + str(event.error))
    return null
  await process_frame
 check(false, "thumbnail worker completes within five seconds")
 return null

func _test_cache() -> void:
 var entries: Array[Dictionary] = []
 for i in 5:
  entries.append(_fixture(i, Color(float(i + 1) / 5.0, 0.25, 0.5)))
 for entry in entries:
  cache.request(entry)
  var texture := await _wait_for_texture(entry)
  check(texture != null, "worker supplies requested thumbnail")
  if texture != null:
   check(maxi(texture.get_width(), texture.get_height()) <= 64, "thumbnail respects configured pixel bound")
  check(cache.in_memory_count() <= 2, "LRU memory cache stays bounded")
 check(DirAccess.get_files_at(cache.cache_dir).size() <= 3, "disk cache stays bounded")
 var disk_entry: Dictionary = {}
 for entry in entries:
  if FileAccess.file_exists(cache.cache_dir.path_join(cache.key_for(entry) + ".png")):
   disk_entry = entry
   break
 check(not disk_entry.is_empty(), "thumbnail cache persists at least one generated image")
 if not disk_entry.is_empty():
  _restart_cache()
  cache.request(disk_entry)
  check(await _wait_for_texture(disk_entry) != null, "fresh cache instance reloads persisted thumbnail")
  check(cache.decoded_count == 0, "persisted thumbnail avoids source decoding")
  var disk_path: String = cache.cache_dir.path_join(cache.key_for(disk_entry) + ".png")
  _restart_cache()
  var corrupt := FileAccess.open(disk_path, FileAccess.WRITE)
  corrupt.store_string("corrupt thumbnail cache")
  corrupt.close()
  cache.request(disk_entry)
  check(await _wait_for_texture(disk_entry) != null, "malformed disk cache falls back to source")
  check(cache.decoded_count == 1, "malformed cached thumbnail is regenerated")
 cache.request(entries.back())
 await _wait_for_texture(entries.back())
 var last: Dictionary = entries.back()
 check(cache.get_texture(last) != null, "most recent thumbnail remains cached")
 cache.invalidate(str(last.path))
 check(cache.get_texture(last) == null, "invalidation removes in-memory thumbnail")
 var image := Image.create(320, 200, false, Image.FORMAT_RGB8)
 image.fill(Color.GREEN)
 image.save_png(str(last.path))
 cache.request(last)
 var refreshed := await _wait_for_texture(last)
 check(refreshed != null, "invalidated source can be requested again")
 if refreshed != null:
  var pixels := refreshed.get_image()
  check(pixels != null and pixels.get_pixel(1, 1).g > 0.9 and pixels.get_pixel(1, 1).r < 0.1, "invalidation refreshes content rather than serving stale pixels")
 for entry in entries:
  cache.request(entry)
 cache.cancel_pending()
 check(cache.pending_count() <= 1, "cancelling pending requests retains at most active worker")
 var bad_entry := {"path": test_dir.path_join("missing-image.png"), "title": "Missing", "sbs": false}
 var bad_key: String = cache.key_for(bad_entry)
 cache.request(bad_entry)
 var deadline := Time.get_ticks_msec() + 5000
 var failed_event := false
 while Time.get_ticks_msec() < deadline and not failed_event:
  for event in thumbnail_events:
   if event.key == bad_key and event.texture == null and not event.error.is_empty():
    failed_event = true
  if not failed_event:
   await process_frame
 check(failed_event, "unreadable thumbnail emits a useful failure result")
 check(cache.get_texture(bad_entry) == null, "failed thumbnails are not cached as successful images")

func _remove_tree(path: String) -> void:
 for directory in DirAccess.get_directories_at(path):
  _remove_tree(path.path_join(directory))
 for filename in DirAccess.get_files_at(path):
  DirAccess.remove_absolute(path.path_join(filename))
 DirAccess.remove_absolute(path)

func _restart_cache() -> void:
 var cache_script: Script = cache.get_script()
 cache.free()
 cache = cache_script.new()
 cache.cache_dir = test_dir.path_join("cache")
 cache.memory_limit = 2
 cache.disk_limit = 3
 cache.thumbnail_side = 64
 root.add_child(cache)
 cache.texture_ready.connect(func(key: String, texture: Texture2D, error: String): thumbnail_events.append({"key": key, "texture": texture, "error": error}))

func _test_visible_page_demand() -> void:
 var demand_gallery: Node3D = load("res://scripts/photo_gallery.gd").new()
 demand_gallery.visible = false
 root.add_child(demand_gallery)
 demand_gallery.cache.cache_dir = test_dir.path_join("demand-cache")
 demand_gallery.cache.thumbnail_side = 64
 var entries := _entries(1000)
 for index in 6:
  entries[index] = _fixture(index + 20, Color(0.2, 0.5, float(index + 1) / 6.0))
 demand_gallery.set_entries(entries)
 check(demand_gallery.cache.pending_count() == 0, "hidden large collection queues no thumbnails")
 demand_gallery.visible = true
 check(demand_gallery.cache.pending_count() <= 6, "showing gallery schedules only its six visible photos")
 var deadline := Time.get_ticks_msec() + 5000
 while demand_gallery.cache.pending_count() > 0 and Time.get_ticks_msec() < deadline:
  await process_frame
 check(demand_gallery.cache.pending_count() == 0, "visible-page thumbnail work completes")
 check(demand_gallery.cache.decoded_count == 6, "large gallery decodes exactly current-page photos")
 var visible_images := 0
 for cell in demand_gallery._cells:
  if cell.image.visible:
   visible_images += 1
 check(visible_images == 6, "completed thumbnails populate all visible gallery tiles")
 demand_gallery.focus_index = 10
 demand_gallery.activate()
 check(demand_gallery.cache.pending_count() <= 6, "page turn replaces demand with at most six requests")
 demand_gallery.visible = false
 check(demand_gallery.cache.pending_count() <= 1, "hiding gallery cancels queued work")
 demand_gallery.free()
