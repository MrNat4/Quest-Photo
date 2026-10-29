extends SceneTree
const Decoder = preload("res://scripts/image_decoder.gd")
const Probe = preload("res://scripts/runtime_image_probe.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
 run_tests()
 print("FORMAT TESTS: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error("FAIL: " + label)

func fixture(name: String) -> PackedByteArray:
 return FileAccess.get_file_as_bytes("res://tests/fixtures/" + name)

func close_color(actual: Color, expected: Color) -> bool:
 return absf(actual.r-expected.r)<0.12 and absf(actual.g-expected.g)<0.12 and absf(actual.b-expected.b)<0.12

func run_tests() -> void:
 var probe: Dictionary = Probe.run()
 check(probe.all_ok,"Embedded runtime codec probe")
 for format: String in probe.formats:
  check(probe.formats[format].ok,"Embedded " + format + " color/dimension decode")
 var decoder = Decoder.new()
 for name in ["grid.png","grid.jpg","grid.webp","grid_lossy.webp","grid.bmp"]:
  var bytes := fixture(name)
  var metadata: Dictionary = decoder.inspect(bytes)
  check(metadata.error.is_empty(),"Header valid: " + name)
  check(metadata.width == 32 and metadata.height == 24,"Header dimensions: " + name)
  var image: Image = decoder.decode_bytes(bytes)
  check(image != null,"Runtime buffer decode: " + name)
  if image != null:
   check(close_color(image.get_pixel(4,4),Color.RED) and close_color(image.get_pixel(27,19),Color.YELLOW),"Runtime color correctness: " + name)
 var animated: Dictionary = decoder.inspect(fixture("animated.webp"))
 check(animated.animated and animated.error.contains("Animated WebP"),"Animated WebP explained")
 check(decoder.decode_bytes(fixture("animated.webp")) == null,"Animated WebP rejected before decode")
 # Expected top-left quadrant after the eight EXIF transforms.
 var first_colors := [Color.RED,Color.GREEN,Color.YELLOW,Color.BLUE,Color.RED,Color.BLUE,Color.YELLOW,Color.GREEN]
 for orientation in range(1,9):
  var bytes := fixture("exif_%d.jpg" % orientation)
  var metadata: Dictionary = decoder.inspect(bytes)
  check(metadata.orientation == orientation,"EXIF metadata orientation %d" % orientation)
  var image: Image = decoder.decode_bytes(bytes)
  check(image != null,"EXIF image decoded %d" % orientation)
  if image != null:
   check(image.get_size() == (Vector2i(32,24) if orientation <= 4 else Vector2i(24,32)),"EXIF dimensions %d" % orientation)
   check(close_color(image.get_pixel(4,4),first_colors[orientation-1]),"EXIF transformed pixels %d" % orientation)
 # A subsequent non-EXIF APP1 segment must not reset an earlier orientation.
 var exif := fixture("exif_6.jpg")
 var insert := exif.size()-2
 # Place non-EXIF APP1 immediately after SOI, then original EXIF follows.
 var with_app := exif.slice(0,2)
 with_app.append_array(PackedByteArray([255,225,0,8,120,109,112,0,0,0]))
 with_app.append_array(exif.slice(2))
 check(decoder.inspect(with_app).orientation == 6,"Other APP1 metadata tolerated")
 var bmp := fixture("grid.bmp")
 var top_down := bmp.duplicate()
 # Flip storage rows and use negative DIB height; output stays upright.
 top_down[22]=232
 top_down[23]=255
 top_down[24]=255
 top_down[25]=255
 for row in 24:
  for column in 96:
   top_down[54+row*96+column]=bmp[54+(23-row)*96+column]
 var top_image: Image = decoder.decode_bytes(top_down)
 check(top_image != null and close_color(top_image.get_pixel(4,4),Color.RED),"Top-down BMP signed height")
 for bytes in [PackedByteArray(),"GIF89a".to_utf8_buffer(),fixture("grid.bmp").slice(0,30),fixture("grid.webp").slice(0,20)]:
  check(not decoder.inspect(bytes).error.is_empty(),"Malformed/unsupported input rejected")
 var giant := fixture("grid.png").duplicate()
 giant[16]=127
 giant[17]=255
 giant[18]=255
 giant[19]=255
 check(decoder.decode_bytes(giant)==null,"Oversized PNG rejected before native allocation")
 var giant_bmp := fixture("grid.bmp").duplicate()
 giant_bmp[18]=255
 giant_bmp[19]=255
 giant_bmp[20]=255
 giant_bmp[21]=127
 check(decoder.decode_bytes(giant_bmp)==null,"Oversized BMP rejected before native allocation")
 var wrong_chunk := fixture("grid.webp").duplicate()
 wrong_chunk[16]=255
 wrong_chunk[17]=255
 wrong_chunk[18]=255
 wrong_chunk[19]=127
 check(decoder.decode_bytes(wrong_chunk)==null,"Invalid WebP chunk length rejected")
 var large_bytes := PackedByteArray()
 large_bytes.resize(Decoder.MAX_FILE_BYTES+1)
 check(decoder.decode_bytes(large_bytes)==null and decoder.error_message.contains("32 MiB"),"Byte limit enforced")
