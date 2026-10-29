extends SceneTree
## Synthetic stored-depth fixtures exercise integration only. This suite does NOT
## claim neural inference/model quality or Android/Quest validation.
const Conversion = preload("res://scripts/ai/depth_conversion.gd")
const Store = preload("res://scripts/ai/conversion_store.gd")
const Export = preload("res://scripts/stereo_export.gd")
var checks := 0
var failures := 0
var service: Node
var emitted := 0
var last_image: Image
var last_record: Dictionary = {}
var folder := ""
var keys: Array[String] = []

func _initialize() -> void:
 _run.call_deferred()

func check(condition: bool, message: String) -> void:
 checks += 1
 if not condition:
  failures += 1
  push_error("FAIL: " + message)

func _settle() -> bool:
 for step in 1000:
  if not service.busy:
   return true
  await create_timer(0.005).timeout
 check(false, "Conversion completes within five seconds for tiny synthetic fixture")
 return false

func _write_depth(path: String) -> void:
 var file := FileAccess.open(path, FileAccess.WRITE)
 file.store_buffer("QPD1".to_ascii_buffer())
 file.store_32(40)
 file.store_32(10)
 for y in 10:
  for x in 40:
   file.store_float(float(x) / 39.0)
 file.close()

func _remove_directory(path: String) -> void:
 for name in DirAccess.get_files_at(path):
  DirAccess.remove_absolute(path.path_join(name))
 for name in DirAccess.get_directories_at(path):
  _remove_directory(path.path_join(name))
 DirAccess.remove_absolute(path)

func _run() -> void:
 folder = "user://test-ai-" + str(Time.get_ticks_usec())
 DirAccess.make_dir_recursive_absolute(folder)
 var source := Image.create(40,10,false,Image.FORMAT_RGB8)
 source.fill(Color(0.2,0.3,0.4))
 source.fill_rect(Rect2i(10,0,10,10), Color.RED)
 var path := folder.path_join("original.png")
 source.save_png(path)
 var entry := {"path":path,"title":"synthetic service fixture", "sbs":false,"layout":"mono"}
 var hash := Store.source_hash(path)
 var key := Store.key_for(hash,"v2_small","Balanced")
 keys.append(key)
 var raw_path := folder.path_join("fixture.qpd")
 _write_depth(raw_path)
 var raw_hash := FileAccess.get_sha256(raw_path)
 var record := {"source_path":path,"source_sha256":hash,"model":"v2_small", "model_name":"V2 Small", "quality":"Balanced", "inverse_depth":true,"inference_ms":1234,"test_fixture":true}
 check(Store.read_depth(raw_path) != null, "Synthetic raw depth format decodes")
 check(Store.save_record(key,raw_path,record) == OK, "Save immutable synthetic depth fixture")
 check(Store.save_record(key,raw_path,record) == ERR_ALREADY_EXISTS, "Existing conversion record cannot be overwritten")
 check(Store.load_record(key).get("test_fixture",false), "Saved metadata persists")
 check(Store.key_for(hash,"v3_small","Balanced") != key and Store.key_for(hash,"v2_small","High Quality") != key, "Model and quality outputs have independent identities")
 check(Store.load_record("../../photos").is_empty(), "Invalid cache path refused")
 service = Conversion.new()
 root.add_child(service)
 service.result_ready.connect(func(image: Image, value: Dictionary):
  emitted += 1
  last_image = image
  last_record = value)
 service.start(entry)
 check(service.busy, "Cached reconstruction starts asynchronously")
 service.start(entry)
 check(service.message.contains("One conversion"), "Second simultaneous job is refused")
 if not await _settle():
  quit(1)
  return
 check(emitted == 1 and last_image != null, "Stored synthetic depth reconstructs without an inference backend")
 check(last_image.get_size() == Vector2i(80,10), "Stored result displays canonical full SBS")
 check(last_record.get("model_name") == "V2 Small" and last_record.get("inference_ms") == 1234, "Displayed model identity and recorded inference time survive caching")
 service.adjust(0.005,-0.05)
 await _settle()
 check(emitted == 2, "Depth adjustment reconstructs stored depth without inference")
 var adjustments := Store.adjustments(key)
 check(is_equal_approx(adjustments.strength,0.025) and is_equal_approx(adjustments.plane,0.45), "Depth adjustments persist separately")
 check(FileAccess.get_sha256(Store.ROOT.path_join(key).path_join("raw.qpd")) == raw_hash, "Original AI depth hash preserved after adjustment")
 check(Store.source_hash(path) == hash, "Original photo hash preserved after cached reconstruction and adjustment")
 var exported := folder.path_join("finished.sbs.png")
 check(Export.export_sbs(last_image,true,{},false,exported) == OK, "Reconstructed stereo exports a valid PNG")
 check(Image.load_from_file(exported).get_size() == Vector2i(80,10), "Reconstructed export dimensions verified by decoding")
 check(Store.source_hash(path) == hash, "Original photo hash preserved after export")
 var prior_count := emitted
 service.start(entry)
 service.cancel()
 await _settle()
 check(emitted == prior_count and service.message.to_lower().contains("cancel"), "Cancelled cached job emits no partial image")
 check(not Store.load_record(key).is_empty(), "Cancellation preserves completed conversion")
 service.start({"path":folder.path_join("missing.png"),"sbs":false})
 await _settle()
 check(not service.busy and service.message.contains("Cannot read"), "Missing source fails gracefully")
 check(Store.source_hash(path) == hash, "Failed job preserves original photo")
 service.start({"path":path,"sbs":true})
 check(not service.busy and service.message.contains("ordinary 2D"), "Existing stereo source is rejected for inference")
 # A byte-identical source in another location shares depth but must identify
 # the current source path when emitted to the viewer.
 var second_path := folder.path_join("same-content.png")
 DirAccess.copy_absolute(path,second_path)
 var second_entry: Dictionary = entry.duplicate(true)
 second_entry.path = second_path
 service.start(second_entry)
 await _settle()
 check(last_record.get("source_path") == second_path, "Cache hit is rebound to the currently requested source path")
 # Each model/quality has a separately retained depth result. These are explicitly
 # stored synthetic fixtures; native runtime testing is in the Java suite.
 for model_index in 3:
  for quality_index in 2:
   service.selected_model = model_index
   service.high_quality = quality_index == 1
   var comparison_key := Store.key_for(hash,service.MODELS[model_index],service.quality_name())
   if comparison_key != key:
    keys.append(comparison_key)
    var comparison := record.duplicate(true)
    comparison.model = service.MODELS[model_index]
    comparison.model_name = service.model_name()
    comparison.quality = service.quality_name()
    comparison.inverse_depth = model_index == 0
    check(Store.save_record(comparison_key,raw_path,comparison) == OK, "Separate model/quality depth persists")
   service.start(entry)
   await _settle()
   check(last_record.model_name == service.model_name() and last_record.quality == service.quality_name(), "All three models and both quality modes restore the correct saved result")
   check(FileAccess.get_sha256(Store.ROOT.path_join(comparison_key).path_join("raw.qpd")) == raw_hash, "V3 reciprocal normalization preserves raw depth bytes")
 check(Store.source_hash(path) == hash, "All comparisons preserve original image hash")
 await _test_viewer(entry,source)
 # Teardown while preparation is active must join a RefCounted worker, not lock
 # a scene Node that Godot is simultaneously deleting.
 service.start(entry)
 service.free()
 check(Store.source_hash(path) == hash, "Active worker teardown leaves original unchanged")
 for saved_key in keys:
  _remove_directory(Store.ROOT.path_join(saved_key))
 _remove_directory(folder)
 print("AI CONVERSION INTEGRATION: %d checks, %d failures (synthetic depth; NO neural inference claim)" % [checks,failures])
 quit(1 if failures else 0)

func _test_viewer(entry: Dictionary, source: Image) -> void:
 var app = load("res://scenes/main.tscn").instantiate()
 root.add_child(app)
 await process_frame
 app._display_photo(0,entry,ImageTexture.create_from_image(source))
 app.state.zoom = 1.5
 app.state.panel_scale = 1.2
 app.state.roll = 0.2
 app._apply_view()
 var pose: Transform3D = app.anchor.transform
 var record := {"source_path":entry.path,"model_name":"V2 Small","quality":"Balanced","inference_ms":1234}
 app._conversion_ready(last_image,record)
 check(app.current_entry.sbs and app.displayed_conversion.model_name == "V2 Small", "Viewer marks actual converted image as stereo with model identity")
 check(app.status.text.contains("V2 Small"), "Displayed model is identified onscreen")
 app._show_original()
 check(not app.current_entry.sbs and app.displayed_conversion.is_empty(), "Original action clears converted identity and stereo layout")
 check(app.material.get_shader_parameter("photograph").get_image().get_data() == source.get_data(), "Original action restores original pixels, not one reprojected eye")
 check(app.state.zoom == 1.5 and app.state.panel_scale == 1.2 and app.state.roll == 0.2 and app.anchor.transform == pose, "Switching original/result preserves zoom scale rotation and position")
 var before: Texture2D = app.material.get_shader_parameter("photograph")
 record.source_path = "user://unrelated.png"
 app._conversion_ready(last_image,record)
 check(app.material.get_shader_parameter("photograph") == before, "Stale completed job cannot replace another source photograph")
 app.free()
