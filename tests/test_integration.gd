extends SceneTree
var app: Node
var failures := 0
var checks := 0
func check(value: bool, label: String) -> void:
 checks += 1
 if not value:
  failures += 1
  push_error(label)
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 app = load("res://scenes/main.tscn").instantiate()
 root.add_child(app)
 check(not app.gallery_open, "viewer launches unchanged")
 app._set_gallery_open(true)
 check(app.gallery.visible and not app.anchor.visible, "gallery replaces visible photo")
 app.gallery.select_index(1)
 app.gallery.activate()
 check(not app.gallery_open and app.current_index == 1, "gallery selection opens photo")
 app._set_gallery_open(true)
 var input := InputEventKey.new()
 input.pressed = true
 input.keycode = KEY_ESCAPE
 app._unhandled_key_input(input)
 check(not app.gallery_open, "Escape returns to viewer")
 var paths := PackedStringArray()
 for extension in ["png", "webp", "bmp", "jpg"]:
  var path: String = "user://integration." + extension
  var file := FileAccess.open(path,FileAccess.WRITE)
  file.store_buffer(FileAccess.get_file_as_bytes("res://tests/fixtures/grid." + extension))
  file.close()
  paths.append(path)
 app._set_gallery_open(true)
 check(app.importer.import_paths(paths) == OK, "batch starts")
 var deadline := Time.get_ticks_msec()+10000
 while app.importer.is_busy() and Time.get_ticks_msec() < deadline:
  await process_frame
 check(not app.importer.is_busy(), "batch completes")
 check(app.library.entries.size() == 6, "import completion refreshes four photos")
 check(app.gallery.entries.size() == 6, "gallery receives refreshed library")
 var persisted = load("res://scripts/photo_library.gd").new()
 persisted.refresh()
 check(persisted.entries.size() == 6, "new library instance discovers imports")
 app.xr_active = true
 app._navigate_photo(2,true)
 deadline = Time.get_ticks_msec()+10000
 while app.photo_loader.is_busy() and Time.get_ticks_msec() < deadline:
  await process_frame
 check(app.current_index == 2 and not app.gallery_open, "VR asynchronous photo selection completes")
 check(app.pending_photo_index == -1, "request cleared")
 var path: String = app.current_entry.path
 app._cycle_layout(2)
 deadline = Time.get_ticks_msec()+10000
 while app.photo_loader.is_busy() and Time.get_ticks_msec() < deadline:
  await process_frame
 check(app.current_entry.sbs, "manual layout reaches renderer")
 check(persisted.layout_for({"path":path}) == "sbs_full", "layout survives library recreation")
 check(app.material.get_shader_parameter("is_sbs"), "canonical stereo shader enabled")
 app._navigate_photo(3)
 app._navigate_photo(4)
 deadline = Time.get_ticks_msec()+10000
 while app.photo_loader.is_busy() and Time.get_ticks_msec() < deadline:
  await process_frame
 check(app.current_index == 4, "latest queued selection wins")
 app.free()
 print("INTEGRATION TESTS: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)
