extends SceneTree

const Importer = preload("res://scripts/photo_importer.gd")
var failures := 0
var importer: Node
var results: Array[Dictionary] = []
var progress_count := 0
var cancel_count := 0
var root_dir := "user://storage-tests-" + str(Time.get_ticks_usec())

func _initialize() -> void:
 call_deferred("_run")

func check(condition: bool, message: String) -> void:
 if not condition:
  failures += 1
  printerr("FAIL storage: " + message)

func _run() -> void:
 DirAccess.make_dir_recursive_absolute(root_dir)
 importer = Importer.new()
 importer.destination_dir = root_dir.path_join("library")
 root.add_child(importer)
 importer.completed.connect(func(paths: PackedStringArray, errors: PackedStringArray): results.append({"paths": paths, "errors": errors}))
 importer.progress.connect(func(_message: String, _fraction: float): progress_count += 1)
 importer.cancelled.connect(func(): cancel_count += 1)
 var source := root_dir.path_join("holiday.sbs.PNG")
 var image := Image.create_empty(16, 8, false, Image.FORMAT_RGB8)
 image.fill(Color.CORAL)
 check(image.save_png(source) == OK, "create fixture")
 var initial_hash := FileAccess.get_sha256(source)
 check(importer.import_paths(PackedStringArray([source])) == OK, "start asynchronous import")
 check(importer.is_busy(), "busy until worker is joined")
 check(importer.import_paths(PackedStringArray([source])) == ERR_BUSY, "reject overlapping worker")
 await _wait_for_import()
 check(results.size() == 1 and results[0].errors.is_empty(), "successful import result")
 check(progress_count > 0, "progress delivered")
 var target := ""
 if results.size() > 0 and not results[0].paths.is_empty():
  target = results[0].paths[0]
  check(FileAccess.get_sha256(target) == initial_hash, "original bytes preserved in copy")
  check(target.ends_with(".png"), "sniffed extension normalized")
  var metadata := ConfigFile.new()
  check(metadata.load(target + ".import.cfg") == OK, "metadata saved")
  check(metadata.get_value("photo", "original_name", "") == "holiday.sbs.PNG", "display/layout filename retained")
  check(not FileAccess.file_exists(target + ".part"), "no incomplete copy remains")
 check(FileAccess.get_sha256(source) == initial_hash, "source unchanged")
 results.clear()
 importer.import_paths(PackedStringArray([source, source]))
 await _wait_for_import()
 check(results.size() == 1 and results[0].paths.size() == 1, "deduplicate same bytes")
 if not target.is_empty():
  check(results[0].paths[0] == target, "stable library path across imports")

 var bad := root_dir.path_join("broken.jpg")
 var bad_file := FileAccess.open(bad, FileAccess.WRITE)
 bad_file.store_string("not an image")
 bad_file.close()
 results.clear()
 importer.import_paths(PackedStringArray([bad, root_dir.path_join("missing.png"), source]))
 await _wait_for_import()
 check(results.size() == 1 and results[0].errors.size() == 2 and results[0].paths.size() == 1, "mixed batch isolates failures and imports valid photo")

 var oversized := root_dir.path_join("too-large.png")
 var huge := FileAccess.open(oversized, FileAccess.WRITE)
 huge.seek(Importer.MAX_FILE_BYTES)
 huge.store_8(0)
 huge.close()
 results.clear()
 importer.import_paths(PackedStringArray([oversized]))
 await _wait_for_import()
 check(results.size() == 1 and results[0].errors.size() == 1 and results[0].paths.is_empty(), "oversized source rejected")

 results.clear()
 var many := PackedStringArray()
 many.resize(Importer.MAX_BATCH + 1)
 check(importer.import_paths(many) == ERR_PARAMETER_RANGE_ERROR, "batch bound enforced")
 check(not importer.is_busy(), "failed start does not leave busy state")
 check(importer.original_name("content://provider/document/primary%3APictures%2Fname.sbs.jpg") == "name.sbs.jpg", "URI display fallback decodes path")
 check(importer.original_name("content://media/document/image%3A123").begins_with("Photo "), "opaque URI fallback does not pretend to be filename")
 check(not importer.original_name("a\nname.jpg").contains("\n"), "display text sanitized")

 results.clear()
 importer.import_paths(PackedStringArray([source, source, source]))
 importer.cancel_import()
 await _wait_for_import()
 check(cancel_count == 1, "worker cancellation reported")
 check(results.size() == 1, "cancelled worker joined and completed")
 # Native picker callbacks are driven directly only to exercise cancellation;
 # this does not claim Android URI/provider or native UI execution coverage.
 importer._picker_pending = true
 importer._set_cancelled(false)
 importer.cancel_import()
 importer._picker_result(true, PackedStringArray([source]), 0)
 check(cancel_count == 2 and not importer.is_busy(), "cancelled native selection is ignored")

 importer.queue_free()
 await process_frame
 _remove_tree(root_dir)
 print("Storage import tests: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
 quit(0 if failures == 0 else 1)

func _wait_for_import() -> void:
 var deadline := Time.get_ticks_msec() + 10000
 while importer.is_busy() and Time.get_ticks_msec() < deadline:
  await process_frame
 check(not importer.is_busy(), "worker completes within test timeout")

func _remove_tree(path: String) -> void:
 var directory := DirAccess.open(path)
 if directory == null:
  return
 for child in directory.get_directories():
  _remove_tree(path.path_join(child))
 for filename in directory.get_files():
  DirAccess.remove_absolute(path.path_join(filename))
 DirAccess.remove_absolute(path)
