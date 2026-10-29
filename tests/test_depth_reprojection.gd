extends SceneTree
const Reprojection = preload("res://scripts/depth_reprojection.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
 run_tests()
 print("DEPTH REPROJECTION TESTS: %d checks, %d failures" % [checks, failures])
 quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
 checks += 1
 if not condition:
  failures += 1
  push_error("FAIL: " + message)

func centroid(image: Image, eye: int, channel: int) -> float:
 var width := image.get_width() / 2
 var sum_value := 0.0
 var count := 0
 for x in width:
  var color := image.get_pixel(x + eye * width, image.get_height() / 2)
  if color[channel] > 0.8 and color[(channel + 1) % 3] < 0.2:
   sum_value += x
   count += 1
 return sum_value / count if count else -1.0

func run_tests() -> void:
 var source := Image.create(400, 20, false, Image.FORMAT_RGB8)
 source.fill(Color(0.2, 0.2, 0.2))
 source.fill_rect(Rect2i(70, 0, 30, 20), Color.RED)
 source.fill_rect(Rect2i(190, 0, 30, 20), Color.GREEN)
 source.fill_rect(Rect2i(310, 0, 30, 20), Color.BLUE)
 var depth := Image.create(400, 20, false, Image.FORMAT_RF)
 depth.fill(Color(0.5, 0, 0))
 depth.fill_rect(Rect2i(60, 0, 50, 20), Color(1, 0, 0))
 depth.fill_rect(Rect2i(300, 0, 50, 20), Color(0, 0, 0))
 var original_bytes := source.get_data()
 var original_depth := depth.get_data()
 var stereo: Image = Reprojection.reconstruct(source, depth, 0.04)
 check(stereo != null and stereo.get_size() == Vector2i(800,20), "Canonical full SBS dimensions")
 check(centroid(stereo,0,0) - centroid(stereo,1,0) == 8.0, "Near object has positive disparity, left first")
 check(centroid(stereo,0,1) - centroid(stereo,1,1) == 0.0, "Screen-plane object remains fusible at zero disparity")
 check(centroid(stereo,0,2) - centroid(stereo,1,2) == -8.0, "Far object has negative disparity")
 var weak: Image = Reprojection.reconstruct(source, depth, 0.02)
 check(centroid(weak,0,0) - centroid(weak,1,0) == 4.0, "Depth strength halves disparity without inference")
 var shifted: Image = Reprojection.reconstruct(source, depth, 0.04, 0.0)
 check(centroid(shifted,0,0) - centroid(shifted,1,0) == 16.0, "Convergence changes zero depth plane")
 var flat: Image = Reprojection.reconstruct(source, depth, 0.0)
 check(flat.get_region(Rect2i(0,0,400,20)).get_data() == original_bytes, "Zero depth preserves original left eye exactly")
 check(flat.get_region(Rect2i(400,0,400,20)).get_data() == original_bytes, "Zero depth preserves original right eye exactly")
 var capped: Image = Reprojection.reconstruct(source, depth, 1.0)
 check(capped.get_data() == stereo.get_data(), "Comfort disparity limit enforced")
 var high: Image = Reprojection.reconstruct(source, depth, 0.023, 0.5, true)
 check(high != null and high.get_data() != Reprojection.reconstruct(source,depth,0.023).get_data(), "HQ actually uses subpixel splatting")
 check(source.get_data() == original_bytes and depth.get_data() == original_depth, "Source photo and original AI depth bytes unchanged")
 var tiny_depth: Image = depth.duplicate()
 for y in tiny_depth.get_height():
  for x in tiny_depth.get_width():
   tiny_depth.set_pixel(x,y,Color(depth.get_pixel(x,y).r * 0.00000001,0,0))
 check(Reprojection.reconstruct(source,tiny_depth,0.04).get_data() == stereo.get_data(), "Normalization is invariant to small arbitrary AI depth units")
 var hole_depth := PackedFloat32Array([0.2, -1, -1, 0.9])
 var colors := PackedFloat32Array([0,0,255,0,0,0,0,0,0,255,0,0])
 Reprojection._fill_background_holes(colors, hole_depth, PackedFloat32Array([1,0,0,1]),4)
 check(colors[5] == 255 and colors[8] == 255 and colors[3] == 0, "Holes extend background, not foreground silhouette")
 check(Reprojection.reconstruct(source, depth, NAN) == null, "NaN strength rejected")
 check(Reprojection.reconstruct(source, depth, 0.02, INF) == null, "Infinite convergence rejected")
 check(Reprojection.reconstruct(null, depth) == null, "Missing source rejected")
 check(Reprojection.reconstruct(source, Image.new()) == null, "Empty depth rejected")
 check(Reprojection.reconstruct(source, depth, 0.02, 0.5, false, func(): return true) == null, "Cancellation returns no incomplete output")
 depth.set_pixel(0,0,Color(NAN,0,0))
 check(Reprojection.reconstruct(source, depth) == null, "Nonfinite AI depth rejected")
 var huge := Image.create(2048, 16, false, Image.FORMAT_RGB8)
 huge.fill(Color.WHITE)
 var constant := Image.create(2,2,false,Image.FORMAT_RF)
 constant.fill(Color(2,0,0))
 var bounded: Image = Reprojection.reconstruct(huge,constant)
 check(bounded.get_size() == Vector2i(2048,8), "Balanced bound and aspect preserved")
 check(bounded.get_pixel(0,0) == Color.WHITE, "Constant depth safe and border holes filled")
 var bounded_high: Image = Reprojection.reconstruct(huge,constant,0.02,0.5,true)
 check(bounded_high.get_size() == Vector2i(3072,12), "HQ raises actual reconstruction resolution")
