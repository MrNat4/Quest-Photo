class_name PhotoLibrary
extends RefCounted

const PHOTO_DIR := "user://photos"
const SETTINGS_DIR := "user://views"
const MAX_FILE_BYTES := 32 * 1024 * 1024
const MAX_PIXELS := 32 * 1024 * 1024
var entries: Array[Dictionary] = []
var error_message := ""

func refresh() -> void:
 entries.clear()
 entries.append({"path": "res://assets/stereo_test_sbs.png", "title": "Stereo calibration", "sbs": true})
 if ResourceLoader.exists("res://assets/sample_photo.jpg"):
  entries.append({"path": "res://assets/sample_photo.jpg", "title": "Sample photograph · 2D", "sbs": false})
 DirAccess.make_dir_recursive_absolute(PHOTO_DIR)
 DirAccess.make_dir_recursive_absolute(SETTINGS_DIR)
 var directory := DirAccess.open(PHOTO_DIR)
 if directory == null:
  error_message = "Cannot open photo folder: " + error_string(DirAccess.get_open_error())
  return
 var names := directory.get_files()
 names.sort()
 for filename in names:
  if filename.get_extension().to_lower() in ["png", "jpg", "jpeg"]:
   entries.append({"path": PHOTO_DIR.path_join(filename), "title": filename,
    "sbs": filename.get_basename().to_lower().ends_with(".sbs")})

func settings_path(path: String) -> String:
 return SETTINGS_DIR.path_join(path.sha256_text() + ".cfg")

# Read dimensions before decoding so highly compressed giant files are rejected.
func inspect_dimensions(bytes: PackedByteArray) -> Vector2i:
 if bytes.size() >= 24 and bytes.slice(0, 8) == PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
  if _be32(bytes, 8) != 13 or bytes.slice(12, 16).get_string_from_ascii() != "IHDR":
   return Vector2i.ZERO
  return Vector2i(_be32(bytes, 16), _be32(bytes, 20))
 if bytes.size() < 4 or bytes[0] != 255 or bytes[1] != 216:
  return Vector2i.ZERO
 var offset := 2
 while offset + 3 < bytes.size():
  if bytes[offset] != 255:
   return Vector2i.ZERO
  while offset < bytes.size() and bytes[offset] == 255:
   offset += 1
  if offset >= bytes.size():
   break
  var marker := bytes[offset]
  offset += 1
  if marker == 217 or marker == 218:
   break
  if marker == 1 or (marker >= 208 and marker <= 215):
   continue
  if offset + 2 > bytes.size():
   break
  var length := int(bytes[offset]) * 256 + int(bytes[offset + 1])
  if length < 2 or offset + length > bytes.size():
   break
  if marker in [192, 193, 194, 195, 197, 198, 199, 201, 202, 203, 205, 206, 207] and length >= 8:
   return Vector2i(int(bytes[offset + 5]) * 256 + int(bytes[offset + 6]), int(bytes[offset + 3]) * 256 + int(bytes[offset + 4]))
  offset += length
 return Vector2i.ZERO

func _be32(bytes: PackedByteArray, start: int) -> int:
 return (int(bytes[start]) << 24) | (int(bytes[start + 1]) << 16) | (int(bytes[start + 2]) << 8) | int(bytes[start + 3])

func load_photo(entry: Dictionary) -> Texture2D:
 error_message = ""
 var path := str(entry.path)
 if path.begins_with("res://"):
  return load(path) as Texture2D
 var file := FileAccess.open(path, FileAccess.READ)
 if file == null:
  error_message = "Cannot read photograph: " + error_string(FileAccess.get_open_error())
  return null
 if file.get_length() > MAX_FILE_BYTES:
  error_message = "Photo exceeds the 32 MiB file limit. Resize before importing."
  return null
 var bytes := file.get_buffer(file.get_length())
 var size := inspect_dimensions(bytes)
 if size.x <= 0 or size.y <= 0 or size.x * size.y > MAX_PIXELS:
  error_message = "Invalid image or photo exceeds 32 megapixels."
  return null
 if bool(entry.sbs) and size.x % 2 != 0:
  error_message = "SBS images must have an even width."
  return null
 var photo := Image.new()
 var result := photo.load_png_from_buffer(bytes) if path.get_extension().to_lower() == "png" else photo.load_jpg_from_buffer(bytes)
 if result != OK:
  error_message = "Image decode failed: " + error_string(result)
  return null
 var max_width := 8192 if bool(entry.sbs) else 4096
 var ratio := minf(1.0, minf(float(max_width) / photo.get_width(), 4096.0 / photo.get_height()))
 if ratio < 1.0:
  var width := maxi(2, int(photo.get_width() * ratio))
  if bool(entry.sbs):
   width -= width % 2
  var height := maxi(1, int(photo.get_height() * ratio))
  if bool(entry.sbs):
   # Each eye must have an independent filter boundary, including at the seam.
   var eye_width := photo.get_width() / 2
   var left_eye := photo.get_region(Rect2i(0, 0, eye_width, photo.get_height()))
   var right_eye := photo.get_region(Rect2i(eye_width, 0, eye_width, photo.get_height()))
   left_eye.resize(width / 2, height, Image.INTERPOLATE_LANCZOS)
   right_eye.resize(width / 2, height, Image.INTERPOLATE_LANCZOS)
   photo = Image.create_empty(width, height, false, left_eye.get_format())
   photo.blit_rect(left_eye, Rect2i(0, 0, width / 2, height), Vector2i.ZERO)
   photo.blit_rect(right_eye, Rect2i(0, 0, width / 2, height), Vector2i(width / 2, 0))
  else:
   photo.resize(width, height, Image.INTERPOLATE_LANCZOS)
 return ImageTexture.create_from_image(photo)
