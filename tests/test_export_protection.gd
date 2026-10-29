extends SceneTree
const Exporter = preload("res://scripts/stereo_export.gd")
var checks := 0
var failures := 0

func check(value: bool, description: String) -> void:
 checks += 1
 if not value:
  failures += 1
  push_error("FAIL: " + description)

func _initialize() -> void:
 var folder := "user://export-protection-" + str(Time.get_ticks_usec())
 DirAccess.make_dir_recursive_absolute(folder)
 var image := Image.create(64, 32, false, Image.FORMAT_RGB8)
 image.fill(Color.RED)
 var original := folder.path_join("original.png")
 check(image.save_png(original) == OK, "create original photograph fixture")
 var original_hash := FileAccess.get_sha256(original)
 check(Exporter.export_sbs(image, false, {}, false, original) == ERR_ALREADY_EXISTS, "reject original as export destination")
 check(FileAccess.get_sha256(original) == original_hash, "original file hash preserved")
 var output := folder.path_join("converted.sbs.png")
 check(Exporter.export_sbs(image, false, {}, false, output) == OK, "create distinct output")
 var exported_hash := FileAccess.get_sha256(output)
 check(Exporter.export_sbs(image, false, {"zoom": 2.0}, true, output) == ERR_ALREADY_EXISTS, "collision never overwrites export")
 check(FileAccess.get_sha256(output) == exported_hash, "first export hash unchanged")
 check(FileAccess.get_sha256(original) == original_hash, "source hash unchanged after export and collision")
 var reopened := Image.load_from_file(output)
 check(reopened.get_size() == Vector2i(128,32), "export remains valid full SBS")
 var jpg := folder.path_join("converted.half-sbs.jpg")
 check(Exporter.export_sbs(image, false, {}, true, jpg) == OK, "unique half-SBS JPEG export")
 check(Image.load_from_file(jpg).get_size() == Vector2i(64,32), "JPEG half-SBS dimensions")
 var jpeg_hash := FileAccess.get_sha256(jpg)
 check(Exporter.export_sbs(image, false, {}, false, jpg) == ERR_ALREADY_EXISTS, "JPEG collision rejected")
 check(FileAccess.get_sha256(jpg) == jpeg_hash, "JPEG original bytes remain")
 for name in DirAccess.get_files_at(folder):
  DirAccess.remove_absolute(folder.path_join(name))
 DirAccess.remove_absolute(folder)
 print("EXPORT PROTECTION: %d checks, %d failures" % [checks, failures])
 quit(1 if failures else 0)
