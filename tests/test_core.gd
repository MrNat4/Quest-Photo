extends SceneTree
## Behavioral tests of persistence and image loading, without a headset/GPU.

const ViewStateScript = preload("res://scripts/view_state.gd")
const LibraryScript = preload("res://scripts/photo_library.gd")
var failures := 0
var checks := 0
var test_dir := ""

func _initialize() -> void:
 test_dir = "user://test-core-" + str(Time.get_ticks_usec())
 DirAccess.make_dir_recursive_absolute(test_dir)
 test_view_state()
 test_headers()
 test_image_loading()
 for filename in DirAccess.get_files_at(test_dir):
  DirAccess.remove_absolute(test_dir.path_join(filename))
 DirAccess.remove_absolute(test_dir)
 print("CORE TESTS: %d checks, %d failures" % [checks, failures])
 quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
 checks += 1
 if not condition:
  failures += 1
  push_error("FAIL: " + message)

func test_view_state() -> void:
 var state = ViewStateScript.new()
 state.zoom = 100.0
 state.pan = Vector2(9.0, -9.0)
 state.panel_scale = -1.0
 state.roll = 9.0 * PI
 state.convergence = 1.0
 state.constrain()
 check(state.zoom == 6.0, "Zoom capped at 6x")
 check(state.pan.is_equal_approx(Vector2(5.0 / 12.0, -5.0 / 12.0)), "Pan remains in cropped image")
 check(state.panel_scale == 0.25, "Panel cannot invert or shrink below minimum")
 check(state.roll >= -PI and state.roll < PI, "Rotation wraps")
 check(state.convergence == 0.02, "Convergence upper bound")
 state.zoom = -1.0
 state.panel_scale = 10.0
 state.convergence = -1.0
 state.constrain()
 check(state.zoom == 1.0 and state.pan == Vector2.ZERO, "Fit image resets out-of-bounds pan")
 check(state.panel_scale == 2.5 and state.convergence == -0.02, "Scale upper and convergence lower bounds")

 state.zoom = 2.0
 state.pan = Vector2(0.1, -0.15)
 state.roll = 0.3
 state.swap_eyes = true
 state.stereo_enabled = false
 var valid: Dictionary = state.to_dictionary()
 var path := test_dir.path_join("view.cfg")
 check(state.save_to(path) == OK, "View state written")
 var restored = ViewStateScript.new()
 check(restored.load_from(path), "View state read")
 check(restored.to_dictionary() == valid, "Persistence round trip preserves all fields")
 check(not restored.load_from(test_dir.path_join("missing.cfg")), "Missing settings rejected")
 check(restored.to_dictionary() == valid, "Missing settings preserve previous state")

 for mutation in [{"version": 2}, {"zoom": "2.0"}, {"zoom": NAN}, {"pan_x": INF},
                  {"roll": -INF}, {"stereo_enabled": 1}, {"swap_eyes": "false"}]:
  var invalid := valid.duplicate()
  invalid.merge(mutation, true)
  check(not restored.from_dictionary(invalid), "Malformed state rejected: " + str(mutation))
  check(restored.to_dictionary() == valid, "Invalid state does not partially apply")
 var missing := valid.duplicate()
 missing.erase("pan_y")
 check(not restored.from_dictionary(missing), "Missing required field rejected")
 var config := ConfigFile.new()
 config.set_value("view", "state", "invalid dictionary")
 config.save(path)
 check(not restored.load_from(path), "Wrong persisted type rejected")
 check(restored.to_dictionary() == valid, "Corrupt persistence preserves previous state")

func png_header(width: int, height: int) -> PackedByteArray:
 var result := PackedByteArray([137,80,78,71,13,10,26,10, 0,0,0,13, 73,72,68,82])
 for value in [width, height]:
  result.append_array(PackedByteArray([(value >> 24) & 255, (value >> 16) & 255,
      (value >> 8) & 255, value & 255]))
 return result

func test_headers() -> void:
 var library = LibraryScript.new()
 check(library.inspect_dimensions(FileAccess.get_file_as_bytes("res://assets/sample_photo.jpg")) == Vector2i(512,600), "Real JPEG dimensions")
 check(library.inspect_dimensions(FileAccess.get_file_as_bytes("res://assets/stereo_test_sbs.png")) == Vector2i(2048,768), "Real PNG dimensions")
 check(library.inspect_dimensions(png_header(6000, 4000)) == Vector2i(6000,4000), "PNG big-endian dimensions")
 var bad_png_chunk := png_header(6000, 4000)
 bad_png_chunk[12] = 88
 check(library.inspect_dimensions(bad_png_chunk) == Vector2i.ZERO, "PNG first chunk must be IHDR")
 bad_png_chunk = png_header(6000, 4000)
 bad_png_chunk[11] = 12
 check(library.inspect_dimensions(bad_png_chunk) == Vector2i.ZERO, "PNG IHDR length must be 13")
 for malformed in [PackedByteArray(), PackedByteArray([255,216]),
   PackedByteArray([255,216,255,224,0,0]), PackedByteArray([255,216,255,224,255,255,1]),
   PackedByteArray([255,216,255,255,255,255]), PackedByteArray([255,216,1,2,3,4]),
   PackedByteArray([255,216,255,218,0,8,8,1,2,3,4,5]), "not an image".to_utf8_buffer()]:
  check(library.inspect_dimensions(malformed) == Vector2i.ZERO, "Truncated/invalid JPEG header rejected")
 var jpeg := PackedByteArray([255,216,255,224,0,4,0,0,255,194,0,11,8,1,44,2,88,1,1,17,0])
 check(library.inspect_dimensions(jpeg) == Vector2i(600,300), "JPEG skips APP segment and reads progressive SOF")

func write_bytes(filename: String, bytes: PackedByteArray) -> String:
 var path := test_dir.path_join(filename)
 var file := FileAccess.open(path, FileAccess.WRITE)
 file.store_buffer(bytes)
 file.close()
 return path

func test_image_loading() -> void:
 var library = LibraryScript.new()
 var photo_path := write_bytes("photo.jpg", FileAccess.get_file_as_bytes("res://assets/sample_photo.jpg"))
 var photo = library.load_photo({"path": photo_path, "sbs": false})
 check(photo != null and photo.get_size() == Vector2(512,600), "Local JPEG actually decodes to texture")
 var invalid_path := write_bytes("bad.png", PackedByteArray([1,2,3]))
 check(library.load_photo({"path": invalid_path, "sbs": false}) == null, "Bad image returns null")
 check(not library.error_message.is_empty(), "Bad image provides error")
 var giant_path := write_bytes("giant.png", png_header(100000, 100000))
 check(library.load_photo({"path": giant_path, "sbs": false}) == null, "Image pixel limit enforced before decode")
 var large_path := test_dir.path_join("too_many_bytes.png")
 var large_file := FileAccess.open(large_path, FileAccess.WRITE)
 large_file.seek(LibraryScript.MAX_FILE_BYTES)
 large_file.store_8(0)
 large_file.close()
 check(library.load_photo({"path": large_path, "sbs": false}) == null, "File size limit enforced before read/decode")
 check(library.error_message.contains("32 MiB"), "File size rejection identifies byte limit")
 check(library.load_photo({"path": test_dir.path_join("missing.png"), "sbs": false}) == null, "Missing local image fails gracefully")
 var odd := Image.create(7, 4, false, Image.FORMAT_RGB8)
 odd.fill(Color.WHITE)
 var odd_path := test_dir.path_join("odd.png")
 odd.save_png(odd_path)
 check(library.load_photo({"path": odd_path, "sbs": true}) == null, "Odd-width SBS rejected")
 check(library.load_photo({"path": odd_path, "sbs": false}) != null, "Odd-width ordinary photo accepted")
 check(library.error_message.is_empty(), "Successful load clears previous error")

 var wide := Image.create(16384, 4, false, Image.FORMAT_RGB8)
 wide.fill_rect(Rect2i(0,0,8192,4), Color.RED)
 wide.fill_rect(Rect2i(8192,0,8192,4), Color.BLUE)
 var wide_path := test_dir.path_join("wide.sbs.png")
 wide.save_png(wide_path)
 var resized = library.load_photo({"path": wide_path, "sbs": true})
 check(resized != null, "Oversized SBS decoded and resized")
 if resized != null:
  check(resized.get_width() == 8192, "SBS resize respects maximum width")
  var pixels: Image = resized.get_image()
  check(pixels.get_pixel(4095,0).is_equal_approx(Color.RED), "Left boundary does not contain right-eye pixels after resize")
  check(pixels.get_pixel(4096,0).is_equal_approx(Color.BLUE), "Right boundary does not contain left-eye pixels after resize")

 check(library.settings_path("user://photos/a.jpg") != library.settings_path("user://photos/b.jpg"), "Photos have separate settings keys")
