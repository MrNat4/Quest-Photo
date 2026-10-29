extends SceneTree
const Exporter = preload("res://scripts/stereo_export.gd")
var checks := 0
var failures := 0
var test_dir := ""

func _initialize() -> void:
 test_dir = "user://test-export-" + str(Time.get_ticks_usec())
 DirAccess.make_dir_recursive_absolute(test_dir)
 run_tests()
 for filename in DirAccess.get_files_at(test_dir):
  DirAccess.remove_absolute(test_dir.path_join(filename))
 DirAccess.remove_absolute(test_dir)
 print("EXPORT TESTS: %d checks, %d failures" % [checks, failures])
 quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
 checks += 1
 if not condition:
  failures += 1
  push_error("FAIL: " + message)

func render(source: Image, sbs: bool, view: Dictionary, half := false, filename := "output.png") -> Image:
 var path := test_dir.path_join(filename)
 var result: Error = Exporter.export_sbs(source, sbs, view, half, path)
 check(result == OK, "Export succeeds: " + filename)
 return Image.load_from_file(path) if result == OK else Image.new()

func run_tests() -> void:
 var source := Image.create(200, 50, false, Image.FORMAT_RGB8)
 source.fill_rect(Rect2i(0,0,100,50), Color.RED)
 source.fill_rect(Rect2i(100,0,100,50), Color.BLUE)
 var full := render(source, true, {})
 check(full.get_size() == Vector2i(200,50), "Full SBS dimensions")
 check(full.get_pixel(99,25) == Color.RED and full.get_pixel(100,25) == Color.BLUE, "Full SBS eye order and seam")
 var half := render(source, true, {}, true)
 check(half.get_size() == Vector2i(100,50), "Half SBS dimensions")
 check(half.get_pixel(49,25) == Color.RED and half.get_pixel(50,25) == Color.BLUE, "Half SBS eye order and seam")
 var swap := render(source, true, {"swap_eyes": true})
 check(swap.get_pixel(10,25) == Color.BLUE and swap.get_pixel(110,25) == Color.RED, "Swap eyes")
 var mono := render(source, true, {"stereo_enabled": false, "swap_eyes": true, "convergence": 0.02})
 check(mono.get_pixel(0,25) == Color.RED and mono.get_pixel(199,25) == Color.RED, "2D duplicates left, ignores swap/convergence")
 var ordinary := render(source.get_region(Rect2i(0,0,100,50)), false, {})
 check(ordinary.get_size() == Vector2i(200,50), "Ordinary photo exports two full-size copies")
 check(ordinary.get_pixel(199,25) == Color.RED, "Ordinary photo duplicated")

 var convergence := render(source, true, {"convergence": 0.02})
 check(convergence.get_pixel(0,25) == Color.BLACK and convergence.get_pixel(199,25) == Color.BLACK, "Convergence fills outside source with black")
 check(convergence.get_pixel(2,25) == Color.RED and convergence.get_pixel(197,25) == Color.BLUE, "Convergence preserves valid content")
 var stripes := Image.create(100, 100, false, Image.FORMAT_RGB8)
 stripes.fill(Color.RED)
 stripes.fill_rect(Rect2i(50,0,50,100), Color.GREEN)
 stripes.fill_rect(Rect2i(0,50,50,50), Color.BLUE)
 var crop := render(stripes, false, {"zoom": 2.0, "pan_x": 0.25, "pan_y": -0.25})
 check(crop.get_pixel(0,0) == Color.GREEN and crop.get_pixel(199,99) == Color.GREEN, "Zoom and pan preserve selected quadrant")
 var crop_lower := render(stripes, false, {"zoom": 2.0, "pan_x": -0.25, "pan_y": 0.25})
 check(crop_lower.get_pixel(0,0) == Color.BLUE and crop_lower.get_pixel(199,99) == Color.BLUE, "Vertical pan orientation")
 check(stripes.get_pixel(0,0) == Color.RED, "Source image unchanged")
 var large := Image.create(6000,3000,false,Image.FORMAT_RGB8)
 large.fill(Color.WHITE)
 var bounded := render(large, false, {}, true)
 check(bounded.get_size() == Vector2i(2048,1024), "Export bounded to 2048 per-eye side and preserves aspect")
 var jpg := render(source, true, {}, false, "output.jpg")
 check(jpg.get_size() == Vector2i(200,50), "JPEG decodes with correct dimensions")
 check(jpg.get_pixel(25,25).r > 0.95 and jpg.get_pixel(125,25).b > 0.95, "JPEG retains both views")
 var odd := Image.create(7,2,false,Image.FORMAT_RGB8)
 check(Exporter.export_sbs(odd,true,{},false,test_dir.path_join("invalid.png")) == ERR_INVALID_PARAMETER, "Odd SBS input rejected")
 check(Exporter.export_sbs(source,true,{"zoom": NAN},false,test_dir.path_join("invalid.png")) == ERR_INVALID_PARAMETER, "Nonfinite crop rejected")
 check(Exporter.export_sbs(source,true,{},false,test_dir.path_join("invalid.gif")) == ERR_INVALID_PARAMETER, "Unsupported extension rejected")
 check(Exporter.export_sbs(source,true,{},false,test_dir.path_join("missing/output.png")) != OK, "IO failure returned")
