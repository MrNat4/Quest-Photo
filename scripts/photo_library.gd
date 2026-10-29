class_name PhotoLibrary
extends RefCounted

const Decoder = preload("res://scripts/image_decoder.gd")
const Layout = preload("res://scripts/stereo_layout.gd")
const PHOTO_DIR := "user://photos"
const SETTINGS_DIR := "user://views"
const METADATA_DIR := "user://metadata"
const MAX_FILE_BYTES := Decoder.MAX_FILE_BYTES
const MAX_PIXELS := Decoder.MAX_PIXELS
const EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp"]
var entries: Array[Dictionary] = []
var error_message := ""

func refresh() -> void:
 error_message = ""
 entries.clear()
 entries.append({"path": "res://assets/stereo_test_sbs.png", "title": "Stereo calibration", "sbs": true})
 entries.append({"path": "res://assets/sample_photo.jpg", "title": "Sample photograph · 2D", "sbs": false})
 DirAccess.make_dir_recursive_absolute(PHOTO_DIR)
 DirAccess.make_dir_recursive_absolute(SETTINGS_DIR)
 DirAccess.make_dir_recursive_absolute(METADATA_DIR)
 var directory := DirAccess.open(PHOTO_DIR)
 if directory == null:
  error_message = "Cannot open photo folder: " + error_string(DirAccess.get_open_error())
  return
 var names := directory.get_files()
 names.sort()
 for filename in names:
  if filename.get_extension().to_lower() in EXTENSIONS:
   var path := PHOTO_DIR.path_join(filename)
   var original := original_name(path)
   entries.append({"path": path, "title": original})
 for entry in entries:
  var layout := layout_for(entry)
  entry.layout = layout
  entry.sbs = layout != "mono"

func settings_path(path: String) -> String:
 return SETTINGS_DIR.path_join(path.sha256_text() + ".cfg")

func metadata_path(path: String) -> String:
 return METADATA_DIR.path_join(path.sha256_text() + ".cfg")

func original_name(path: String) -> String:
 var config := ConfigFile.new()
 if config.load(path + ".import.cfg") == OK:
  var value: Variant = config.get_value("photo", "original_name", "")
  if value is String and not value.is_empty():
   return value.get_file()
 return path.get_file()

func layout_for(entry: Dictionary) -> String:
 var config := ConfigFile.new()
 if config.load(metadata_path(str(entry.get("path", "")))) == OK:
  var saved: Variant = config.get_value("photo", "layout", "")
  if saved is String and saved in Layout.VALUES:
   return saved
 var explicit: Variant = entry.get("layout", "")
 if explicit is String and explicit in Layout.VALUES:
  return explicit
 var detected: String = Layout.detect(original_name(str(entry.get("path", ""))))
 if detected != "mono":
  return detected
 return "sbs_full" if bool(entry.get("sbs", false)) else "mono"

func set_layout(entry: Dictionary, layout: String) -> Error:
 error_message = ""
 if layout not in Layout.VALUES or str(entry.get("path", "")).is_empty():
  error_message = "Unknown stereo layout."
  return ERR_INVALID_PARAMETER
 var result := DirAccess.make_dir_recursive_absolute(METADATA_DIR)
 if result != OK:
  error_message = "Cannot create layout metadata folder: " + error_string(result)
  return result
 var config := ConfigFile.new()
 config.set_value("photo", "layout", layout)
 result = config.save(metadata_path(str(entry.path)))
 if result != OK:
  error_message = "Cannot save stereo layout: " + error_string(result)
  return result
 entry.layout = layout
 entry.sbs = layout != "mono"
 return OK

func inspect_dimensions(bytes: PackedByteArray) -> Vector2i:
 return Decoder.new().inspect_dimensions(bytes)

## CPU-only and worker-safe. Each worker owns its PhotoLibrary and entry copy.
## Returns mono or canonical full SBS after orientation/layout normalization.
func load_image(entry: Dictionary, max_side: int = 4096) -> Image:
 error_message = ""
 var path := str(entry.get("path", ""))
 var raw_path := path + ".bin" if path in ["res://assets/sample_photo.jpg", "res://assets/stereo_test_sbs.png"] else path
 var file := FileAccess.open(raw_path, FileAccess.READ)
 if file == null:
  error_message = "Cannot read photograph: " + error_string(FileAccess.get_open_error())
  return null
 if file.get_length() > MAX_FILE_BYTES:
  error_message = "Photo exceeds the 32 MiB file limit. Resize before importing."
  return null
 var bytes := file.get_buffer(file.get_length())
 file.close()
 var decoder = Decoder.new()
 var decoded: Image = decoder.decode_bytes(bytes)
 if decoded == null:
  error_message = decoder.error_message
  return null
 var layout := layout_for(entry)
 var normalizer = Layout.new()
 var image: Image = normalizer.normalize(decoded, layout, max_side)
 if image == null:
  error_message = normalizer.error_message
  return null
 entry.layout = layout
 entry.sbs = layout != "mono"
 return image

## Main-thread convenience wrapper. Worker consumers should use load_image.
func load_photo(entry: Dictionary) -> Texture2D:
 var image := load_image(entry)
 return ImageTexture.create_from_image(image) if image != null else null
