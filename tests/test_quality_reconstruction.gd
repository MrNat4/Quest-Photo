extends SceneTree
const New = preload("res://scripts/depth_reprojection.gd")
const Old = preload("res://tests/reference/reprojection_030.gd")
var checks := 0
var failures := 0
var rows: Array = []
var output := "res://build/quality031"
func check(value: bool, message: String) -> void:
 checks += 1
 if not value:
  failures += 1
  push_error(message)
func fixture(width: int, height: int) -> Array:
 var rgb := Image.create(width,height,false,Image.FORMAT_RGB8)
 var depth := Image.create(width,height,false,Image.FORMAT_RF)
 for y in height:
  for x in width:
   var color := Color(0.1 + 0.1 * sin(x * 0.22),0.3 + 0.1 * cos(y * 0.15),0.7)
   var d := 0.15 + 0.1 * y / float(height)
   # Slanted silhouette, thin wires/hair, and ring (jewelry-like) geometry.
   var edge := x > width * 0.3 + y * 0.25 and x < width * 0.65
   var wire := (x + y / 3) % 43 < 2 and x > width * 0.72
   var distance := Vector2(x-width*0.2,y-height*0.5).length()
   var ring := absf(distance-height*0.2) < 1.6
   if edge or wire or ring:
    color = Color(0.9,0.7 + 0.15 * sin(y * 0.7),0.1)
    d = 0.85
   rgb.set_pixel(x,y,color)
   depth.set_pixel(x,y,Color(d,0,0))
 return [rgb,depth]
func mae(a: Image,b: Image) -> float:
 var x := a.get_data()
 var y := b.get_data()
 var total := 0.0
 for i in x.size(): total += absi(int(x[i])-y[i])
 return total / x.size()
func timed(label: String, source: Image, depth: Image, mode: int, old: bool = false) -> Image:
 var before := OS.get_static_memory_usage()
 var start := Time.get_ticks_usec()
 var image: Image = Old.reconstruct(source,depth,0.025,0.5,mode > 0) if old else New.reconstruct(source,depth,0.025,0.5,mode)
 var elapsed := (Time.get_ticks_usec()-start)/1000.0
 check(image != null, label+" reconstructs")
 var row := {"case":label,"mode":mode,"old_030":old,"reconstruction_ms":elapsed,"godot_static_before_bytes":before,"godot_static_after_bytes":OS.get_static_memory_usage(),"godot_static_peak_bytes":OS.get_static_memory_peak_usage(),"size":str(source.get_size()),"output":str(image.get_size()) if image else "null","inference_ms":0,"inference":"not run; identical procedural depth"}
 rows.append(row)
 print(JSON.stringify(row))
 if image:
  image.save_png(output.path_join(label+".png"))
 return image
func _initialize() -> void:
 DirAccess.make_dir_recursive_absolute(output)
 var f := fixture(400,240)
 var photo: Image = f[0]
 var truth: Image = f[1]
 var low: Image = truth.duplicate()
 low.resize(100,60,Image.INTERPOLATE_BILINEAR)
 var source_hash := photo.get_data().hex_encode().sha256_text()
 var depth_hash := low.get_data().hex_encode().sha256_text()
 var old := timed("edges-030-high",photo,low,1,true)
 var improved := timed("edges-031-high",photo,low,1)
 var maximum := timed("edges-031-maximum",photo,low,2)
 # Isolate refinement benefit using the same improved renderer at known depth.
 var reference := New.reconstruct(photo,truth,0.025,0.5,1)
 var refined := New._guided_depth(photo,low,0.0,1.0,Callable())
 var bilinear: Image = low.duplicate()
 bilinear.resize(400,240,Image.INTERPOLATE_BILINEAR)
 var old_error := 0.0
 var new_error := 0.0
 for y in 240:
  for x in 400:
   var expected := truth.get_pixel(x,y).r
   old_error += absf(bilinear.get_pixel(x,y).r-expected)
   new_error += absf(refined[y*400+x]-expected)
 check(new_error < old_error,"RGB-guided depth improves known silhouette/thin-structure error over bilinear")
 rows.append({"depth_mae_bilinear":old_error/96000,"depth_mae_guided":new_error/96000,"stereo_mae_old_vs_known_depth":mae(old,reference),"stereo_mae_new_vs_known_depth":mae(improved,reference)})
 check(mae(improved,reference) < mae(old,reference),"Improved reconstruction reduces error against known-depth render")
 check(maximum.get_size()==improved.get_size(),"Quality keeps geometry/aspect on small inputs")
 check(photo.get_data().hex_encode().sha256_text()==source_hash and low.get_data().hex_encode().sha256_text()==depth_hash,"Original RGB and cached depth unchanged")
 for mode in [1,2]:
  var zero := New.reconstruct(photo,low,0.0,0.5,mode)
  check(zero.get_region(Rect2i(0,0,400,240)).get_data()==photo.get_data(),"Zero strength exact in quality "+str(mode))
  check(New.reconstruct(photo,low,0.025,0.5,mode,func(): return true)==null,"Cancellation in quality "+str(mode))
 var portrait := Image.load_from_file("res://tests/fixtures/quality/astronaut.png")
 if portrait:
  var face_depth := Image.create(512,512,false,Image.FORMAT_RF)
  for y in 512:
   for x in 512:
    # Smooth ellipsoid face/body depth; no monocular inference is claimed.
    var radius := Vector2((x-222.0)/85.0,(y-125.0)/105.0).length()
    var value := 0.2
    if radius<1.0: value=0.65+0.3*sqrt(1.0-radius*radius)
    elif y>220 and x>80 and x<430: value=0.6
    face_depth.set_pixel(x,y,Color(value,0,0))
  face_depth.resize(128,128,Image.INTERPOLATE_BILINEAR)
  timed("portrait-030-high",portrait,face_depth,1,true)
  timed("portrait-031-high",portrait,face_depth,1)
  timed("portrait-031-maximum",portrait,face_depth,2)
 if "--benchmark" in OS.get_cmdline_user_args():
  var large := fixture(2048,1366)
  var benchmark_depth: Image = large[1]
  benchmark_depth.resize(518,350,Image.INTERPOLATE_BILINEAR)
  timed("large-030-balanced",large[0],benchmark_depth,0,true)
  timed("large-031-balanced",large[0],benchmark_depth,0)
  timed("large-030-high",large[0],benchmark_depth,1,true)
  timed("large-031-high",large[0],benchmark_depth,1)
  timed("large-031-maximum",large[0],benchmark_depth,2)
 var report := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
 report.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":rows},"  "))
 report.close()
 print("QUALITY COMPARISON: %d checks, %d failures; no AI inference or Quest measurements" % [checks,failures])
 quit(1 if failures else 0)
