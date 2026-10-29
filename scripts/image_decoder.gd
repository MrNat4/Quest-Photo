class_name PhotoImageDecoder
extends RefCounted
## Runtime-only CPU image decoder. Each worker owns its decoder and Image.
const MAX_FILE_BYTES := 32 * 1024 * 1024
const MAX_PIXELS := 32 * 1024 * 1024
var error_message := ""

func inspect(bytes: PackedByteArray) -> Dictionary:
 var info := {"format": "", "width": 0, "height": 0, "orientation": 1, "animated": false, "error": ""}
 if bytes.size() > MAX_FILE_BYTES:
  info.error = "Photo exceeds the 32 MiB file limit. Resize before importing."
 elif bytes.size() >= 24 and bytes.slice(0,8) == PackedByteArray([137,80,78,71,13,10,26,10]):
  info.format = "png"
  if _u32(bytes,8,false) == 13 and bytes.slice(12,16).get_string_from_ascii() == "IHDR":
   info.width = _u32(bytes,16,false)
   info.height = _u32(bytes,20,false)
 elif bytes.size() >= 4 and bytes[0] == 255 and bytes[1] == 216:
  info.format = "jpeg"
  _jpeg(bytes,info)
 elif bytes.size() >= 12 and bytes.slice(0,4).get_string_from_ascii() == "RIFF" and bytes.slice(8,12).get_string_from_ascii() == "WEBP":
  info.format = "webp"
  _webp(bytes,info)
 elif bytes.size() >= 26 and bytes[0] == 66 and bytes[1] == 77:
  info.format = "bmp"
  var dib := _u32(bytes,14,true)
  if dib == 12:
   info.width = _u16(bytes,18,true)
   info.height = _u16(bytes,20,true)
  elif dib >= 40 and bytes.size() >= 54 and 14 + dib <= bytes.size():
   info.width = _signed32(_u32(bytes,18,true))
   info.height = absi(_signed32(_u32(bytes,22,true)))
 if info.animated:
  info.error = "Animated WebP is not supported yet. Import a still image."
 elif info.error.is_empty() and (info.width <= 0 or info.height <= 0 or info.width > MAX_PIXELS or info.height > MAX_PIXELS or info.width * info.height > MAX_PIXELS):
  info.error = "Invalid image or photo exceeds 32 megapixels. Supported: JPEG, PNG, static WebP and BMP."
 error_message = info.error
 return info

func inspect_dimensions(bytes: PackedByteArray) -> Vector2i:
 var info := inspect(bytes)
 return Vector2i(info.width,info.height) if info.error.is_empty() else Vector2i.ZERO

func decode_bytes(bytes: PackedByteArray) -> Image:
 var info := inspect(bytes)
 if not info.error.is_empty():
  return null
 var decoded := Image.new()
 var result := ERR_FILE_UNRECOGNIZED
 match info.format:
  "png": result = decoded.load_png_from_buffer(bytes)
  "jpeg": result = decoded.load_jpg_from_buffer(bytes)
  "webp": result = decoded.load_webp_from_buffer(bytes)
  "bmp":
   # Godot 4.6.3's BMP loader requires positive height. Normalize top-down
   # DIB headers on a private byte copy, then restore the raster direction.
   var top_down := bytes.size() >= 54 and _u32(bytes,14,true) >= 40 and _signed32(_u32(bytes,22,true)) < 0
   var bmp_bytes := bytes.duplicate() if top_down else bytes
   if top_down:
    bmp_bytes.encode_s32(22, int(info.height))
   result = decoded.load_bmp_from_buffer(bmp_bytes)
   if top_down and result == OK:
    decoded.flip_y()
 if result != OK:
  error_message = "Image decode failed: " + error_string(result)
  return null
 # Reject inconsistency rather than treating a different decoded raster as safe.
 if decoded.get_width() != info.width or decoded.get_height() != info.height:
  error_message = "Image dimensions disagree with its header."
  return null
 match int(info.orientation):
  2: decoded.flip_x()
  3:
   decoded.flip_x()
   decoded.flip_y()
  4: decoded.flip_y()
  5:
   decoded.rotate_90(CLOCKWISE)
   decoded.flip_x()
  6: decoded.rotate_90(CLOCKWISE)
  7:
   decoded.rotate_90(CLOCKWISE)
   decoded.flip_y()
  8: decoded.rotate_90(COUNTERCLOCKWISE)
 return decoded

func _u16(bytes: PackedByteArray, at: int, little: bool) -> int:
 return int(bytes[at]) | (int(bytes[at+1]) << 8) if little else (int(bytes[at]) << 8) | int(bytes[at+1])

func _u32(bytes: PackedByteArray, at: int, little: bool) -> int:
 return _u16(bytes,at,little) | (_u16(bytes,at+2,little) << 16) if little else (_u16(bytes,at,little) << 16) | _u16(bytes,at+2,little)

func _u24(bytes: PackedByteArray, at: int) -> int:
 return int(bytes[at]) | (int(bytes[at+1]) << 8) | (int(bytes[at+2]) << 16)

func _signed32(value: int) -> int:
 return value - 4294967296 if value >= 2147483648 else value

func _jpeg(bytes: PackedByteArray, info: Dictionary) -> void:
 var offset := 2
 while offset + 3 < bytes.size():
  if bytes[offset] != 255:
   return
  while offset < bytes.size() and bytes[offset] == 255:
   offset += 1
  if offset >= bytes.size():
   return
  var marker := bytes[offset]
  offset += 1
  if marker == 217 or marker == 218:
   return
  if marker == 1 or (marker >= 208 and marker <= 215):
   continue
  if offset + 2 > bytes.size():
   return
  var length := _u16(bytes,offset,false)
  if length < 2 or offset + length > bytes.size():
   return
  if marker == 225 and length >= 8 and bytes.slice(offset+2,offset+8) == PackedByteArray([69,120,105,102,0,0]):
   info.orientation = _exif_orientation(bytes,offset+2,offset+length)
  if marker in [192,193,194,195,197,198,199,201,202,203,205,206,207] and length >= 8:
   var width := _u16(bytes,offset+5,false)
   var height := _u16(bytes,offset+3,false)
   if info.width != 0 and (info.width != width or info.height != height):
    info.error = "Inconsistent JPEG frame dimensions."
    return
   info.width = width
   info.height = height
  offset += length

func _exif_orientation(bytes: PackedByteArray, start: int, end: int) -> int:
 if end - start < 14 or bytes.slice(start,start+6) != PackedByteArray([69,120,105,102,0,0]):
  return 1
 var tiff := start + 6
 var little := bytes[tiff] == 73 and bytes[tiff+1] == 73
 if not little and not (bytes[tiff] == 77 and bytes[tiff+1] == 77):
  return 1
 if _u16(bytes,tiff+2,little) != 42:
  return 1
 var ifd := tiff + _u32(bytes,tiff+4,little)
 if ifd < tiff+8 or ifd+2 > end:
  return 1
 var count := _u16(bytes,ifd,little)
 if ifd+2+12*count > end:
  return 1
 for index in count:
  var tag := ifd+2+index*12
  if _u16(bytes,tag,little) == 274 and _u16(bytes,tag+2,little) == 3 and _u32(bytes,tag+4,little) == 1:
   var value := _u16(bytes,tag+8,little)
   return value if value >= 1 and value <= 8 else 1
 return 1

func _webp(bytes: PackedByteArray, info: Dictionary) -> void:
 var end := _u32(bytes,4,true) + 8
 if end > bytes.size() or end < 20:
  info.error = "Truncated WebP container."
  return
 var offset := 12
 var canvas := Vector2i.ZERO
 var raster := Vector2i.ZERO
 while offset + 8 <= end:
  var kind := bytes.slice(offset,offset+4).get_string_from_ascii()
  var length := _u32(bytes,offset+4,true)
  var data := offset+8
  if data+length > end:
   info.error = "Truncated WebP chunk."
   return
  if kind in ["ANIM","ANMF"]:
   info.animated = true
  elif kind == "VP8X" and length >= 10:
   info.animated = info.animated or (bytes[data] & 2) != 0
   canvas = Vector2i(_u24(bytes,data+4)+1,_u24(bytes,data+7)+1)
  elif kind == "VP8 " and length >= 10 and bytes.slice(data+3,data+6) == PackedByteArray([157,1,42]):
   raster = Vector2i(_u16(bytes,data+6,true) & 16383,_u16(bytes,data+8,true) & 16383)
  elif kind == "VP8L" and length >= 5 and bytes[data] == 47:
   var packed := _u32(bytes,data+1,true)
   raster = Vector2i((packed & 16383)+1,((packed >> 14) & 16383)+1)
  if raster.x > 0 and (int(raster.x)*raster.y > MAX_PIXELS or raster.x > MAX_PIXELS or raster.y > MAX_PIXELS):
   info.error = "WebP raster exceeds 32 megapixels."
   return
  offset = data+length+(length % 2)
 if canvas != Vector2i.ZERO and raster != Vector2i.ZERO and canvas != raster:
  info.error = "Inconsistent WebP frame dimensions."
  return
 var dimensions := canvas if canvas != Vector2i.ZERO else raster
 info.width = dimensions.x
 info.height = dimensions.y
