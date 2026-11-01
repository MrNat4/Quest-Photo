extends SceneTree
const New = preload("res://scripts/depth_reprojection.gd")
const Old = preload("res://tests/reference/reprojection_031.gd")
const Cache = preload("res://scripts/ai/cache_manager.gd")
const Store = preload("res://scripts/ai/conversion_store.gd")
const Menu = preload("res://scripts/ai/conversion_panel.gd")
var checks := 0
var failures := 0
var report := {}
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error(label)
func _initialize() -> void: _run.call_deferred()
func _write(path: String, bytes: PackedByteArray) -> void:
 DirAccess.make_dir_recursive_absolute(path.get_base_dir())
 var f := FileAccess.open(path,FileAccess.WRITE)
 f.store_buffer(bytes); f.close()
func _symmetry() -> void:
 var width := 320
 var height := 90
 var rgb := Image.create(width,height,false,Image.FORMAT_RGB8)
 var depth := Image.create(width,height,false,Image.FORMAT_RF)
 for y in height:
  for x in width:
   var radius := Vector2((x-160.0)/70.0,(y-45.0)/80.0).length()
   var d := 0.18 + 0.025 * sin(x*0.4+y*0.2)
   var color := Color(0.05,0.2+0.1*sin(x*0.21),0.8)
   if radius < 1.0:
    d = 0.45+0.45*sqrt(1-radius*radius)
    color = Color(0.8+0.15*sin(x*0.6),0.25,0.1)
   if x>230 and (x+y/3)%13<2:
    d=0.75+0.08*sin(y*0.2)
    color=Color(0.95,0.8,0.1)
   rgb.set_pixel(x,y,color);depth.set_pixel(x,y,Color(d,0,0))
 var flip_rgb: Image = rgb.duplicate(); flip_rgb.flip_x()
 var flip_depth: Image = depth.duplicate(); flip_depth.flip_x()
 var original_hash := depth.get_data().hex_encode().sha256_text()
 DirAccess.make_dir_recursive_absolute("res://build/quality032")
 for model in [Old,New]:
  var label := "031" if model == Old else "032"
  var start := Time.get_ticks_usec()
  var result: Image = model.reconstruct(rgb,depth,0.04,0.5,2)
  report[label+"_ms"] = (Time.get_ticks_usec()-start)/1000.0
  var flipped: Image = model.reconstruct(flip_rgb,flip_depth,0.04,0.5,2)
  var error := 0.0
  var maximum := 0.0
  for eye in 2:
   for y in height:
    for x in width:
     var a := result.get_pixel(x+eye*width,y)
     var b := flipped.get_pixel((width-1-x)+(1-eye)*width,y)
     for channel in 3:
      var difference := absf(a[channel]-b[channel])*255
      error+=difference;maximum=maxf(maximum,difference)
  report[label+"_mirror_mae"] = error/(width*height*6)
  report[label+"_mirror_max"] = maximum
  result.save_png("res://build/quality032/rounded-hair-"+label+".png")
 check(report["032_mirror_mae"]<0.01,"Mirror plus eye swap preserves geometry/color symmetry")
 check(report["032_mirror_mae"]<report["031_mirror_mae"],"Removes measurable old scan-order asymmetry")
 check(depth.get_data().hex_encode().sha256_text()==original_hash,"Rounded surface input depth unchanged")
 # Analytic rounded object silhouette: opposite-eye widths must compensate.
 var image := Image.create(400,8,false,Image.FORMAT_RGB8);image.fill(Color.BLUE)
 var curved := Image.create(400,8,false,Image.FORMAT_RF);curved.fill(Color(0.1,0,0))
 for x in range(140,260):
  var t := (x-199.5)/60.0
  for y in 8:
   image.set_pixel(x,y,Color.RED)
   curved.set_pixel(x,y,Color(0.5+0.4*sqrt(1-t*t),0,0))
 var result := New.reconstruct(image,curved,0.04,0.5,1)
 var widths := Vector2.ZERO
 for eye in 2:
  var lo := 400;var hi := -1
  for x in 400:
   if result.get_pixel(x+eye*400,4).r>0.5:lo=mini(lo,x);hi=maxi(hi,x)
  widths[eye]=hi-lo+1
 check(absf((widths.x+widths.y)/2.0-120)<2,"Rounded object's mean binocular width stays within two pixels")
 report["rounded_eye_widths"]=[widths.x,widths.y]
func _overlap_symmetry() -> void:
 var width := 2048
 var photo := Image.create(width,8,false,Image.FORMAT_RGB8)
 var d := Image.create(width,8,false,Image.FORMAT_RF)
 for y in 8:
  for x in width:
   photo.set_pixel(x,y,Color(float(x%7)/6.0,float(x%11)/10.0,float(x%3)/2.0))
   d.set_pixel(x,y,Color(0.4+0.014*(x%16),0,0))
 var flipped: Image = photo.duplicate();flipped.flip_x()
 var fd: Image = d.duplicate();fd.flip_x()
 for renderer in [Old,New]:
  var a: Image = renderer._surface_render(photo.get_data(),d.get_data().to_float32_array(),width,8,0.04,0.5,2,Callable())
  var b: Image = renderer._surface_render(flipped.get_data(),fd.get_data().to_float32_array(),width,8,0.04,0.5,2,Callable())
  var error:=0.0
  for eye in 2:
   for x in width:
    var p:=a.get_pixel(x+eye*width,4);var q:=b.get_pixel(width-1-x+(1-eye)*width,4)
    for c in 3:error+=absf(p[c]-q[c])*255.0
  report[("031" if renderer==Old else "032")+"_overlap_mae"]=error/(width*6)
  a.save_png("res://build/quality032/overlap-"+("031" if renderer==Old else "032")+".png")
 check(report["032_overlap_mae"]<0.01,"Order-independent overlapping depth layers are mirror symmetric")
 check(report["031_overlap_mae"]>0.5 and report["032_overlap_mae"]<report["031_overlap_mae"]*0.01,"Stress case reproduces and removes meaningful scan-order bias")

func _portrait() -> void:
 var source := Image.load_from_file("res://tests/fixtures/quality/astronaut.png")
 var d := Image.create(128,128,false,Image.FORMAT_RF)
 for y in 128:
  for x in 128:
   var radius := Vector2((x*4.0-222)/85,(y*4.0-125)/105).length()
   var value := 0.2
   if radius<1: value=0.65+0.3*sqrt(1-radius*radius)
   elif y*4>220 and x*4>80 and x*4<430: value=0.6
   d.set_pixel(x,y,Color(value,0,0))
 for renderer in [Old,New]:
  var label := "031" if renderer==Old else "032"
  var start := Time.get_ticks_usec()
  var image: Image = renderer.reconstruct(source,d,0.025,0.5,2)
  report[label+"_portrait_ms"]=(Time.get_ticks_usec()-start)/1000.0
  check(image!=null and image.get_size()==Vector2i(1024,512),"Portrait reconstruction dimensions "+label)
  image.save_png("res://build/quality032/portrait-"+label+".png")

func _cache() -> void:
 var first := "a".repeat(64);var second := "b".repeat(64)
 var hash := "c".repeat(64)
 for key in [first,second]:
  var folder := Store.ROOT.path_join(key)
  _write(folder.path_join("raw.qpd"),PackedByteArray([1,2,3]))
  _write(folder.path_join("preview-0.3.1-1.png"),PackedByteArray([4,5]))
  _write(folder.path_join("record.json"),JSON.stringify({"schema":1,"source_sha256":hash if key==first else "d".repeat(64)}).to_utf8_buffer())
 var settings := ConfigFile.new();settings.set_value("stereo","strength",0.03);settings.set_value("stereo","plane",0.4)
 settings.save(Store.ROOT.path_join(first).path_join("adjustments.cfg"))
 var originals := {"user://photos/protected.png":"photo","user://exports/protected.sbs.png":"export","user://models/protected.onnx":"model","user://ai-model/protected.onnx":"extracted model","user://views/protected.cfg":"settings"}
 for path in originals:_write(path,str(originals[path]).to_utf8_buffer())
 var info := Cache.inventory(hash)
 check(info.depth==3 and info.images==2,"Cache reports depth and preview bytes separately")
 check(Cache.clear(hash,false).has("error") and FileAccess.file_exists(Store.ROOT.path_join(first).path_join("raw.qpd")),"No deletion without confirmation")
 var result := Cache.clear(hash,true)
 check(result.errors.is_empty() and not DirAccess.dir_exists_absolute(Store.ROOT.path_join(first)),"Current-photo clearing removes only its cache")
 check(FileAccess.file_exists(Store.ROOT.path_join(second).path_join("raw.qpd")),"Another photo's cache is retained")
 check(is_equal_approx(Store.adjustments(first).strength,0.03),"Legacy depth settings migrate without loss")
 # Unknown files and symlinks are never traversed or deleted.
 var unsafe := Store.ROOT.path_join("e".repeat(64))
 _write(unsafe.path_join("original.jpg"),"do not delete".to_utf8_buffer())
 var link_key := "f".repeat(64)
 var cache_directory := DirAccess.open(Store.ROOT)
 var linked := cache_directory.create_link(ProjectSettings.globalize_path("user://photos"),link_key)==OK
 result=Cache.clear("",true)
 if linked:
  check(FileAccess.file_exists("user://photos/protected.png"),"Cache links cannot delete originals")
  DirAccess.remove_absolute(Store.ROOT.path_join(link_key))
 check(result.errors.is_empty() and result.skipped>0,"All-cache deletion reports and skips unrecognized contents")
 check(FileAccess.file_exists(unsafe.path_join("original.jpg")),"Unknown image in cache root protected")
 for path in originals:
  check(FileAccess.get_file_as_string(path)==originals[path],"Original/export/model/settings protected: "+path)
  DirAccess.remove_absolute(path)
 DirAccess.remove_absolute(unsafe.path_join("original.jpg"));DirAccess.remove_absolute(unsafe)
 DirAccess.remove_absolute(Store.SETTINGS_ROOT.path_join(first+".cfg"))
func _ui() -> void:
 var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
 await process_frame
 app._set_conversion_open(true)
 app._notice("Export completed",true)
 check(app.notification.modulate==Menu.RED and app.conversion_panel.feedback.modulate==Menu.RED,"Export feedback is bright red in both VR locations")
 check(app.status.modulate==Color.WHITE and app.help.modulate==Color.WHITE and app.conversion_panel.heading.modulate==Color.WHITE and app.conversion_panel.rows.modulate==Color.WHITE and app.conversion_panel.instructions.modulate==Color.WHITE,"Settings and controller text remain white")
 app._notice("Quality selected")
 check(app.conversion_panel.feedback.modulate==Color.WHITE,"Ordinary messages reset to white")
 app.conversion.busy=true;app.conversion._status("Reconstructing")
 check(app.conversion_panel.feedback.modulate==Menu.RED,"Active reconstruction is red")
 app._request_cache_clear("cache_all")
 check(app.cache_confirmation.is_empty(),"Cache deletion blocked during processing")
 app.conversion.busy=false
 app.conversion_panel.confirmation="Clear cache?";app.conversion_panel.focus=0;app.conversion_panel.refresh()
 check(app.conversion_panel.rows.text.begins_with("▶ Cancel"),"Cache confirmation defaults to Cancel")
 check(not app.help.visible,"Help is hidden while conversion menu is open")
 app.free()
func _run() -> void:
 if OS.get_environment("QUEST_PHOTO_TEST_ISOLATED") != "1":
  push_error("Use the isolated test runner; refusing cache deletion tests in a normal profile.")
  quit(1)
  return
 _symmetry();_overlap_symmetry();_portrait();_cache();await _ui()
 report["checks"]=checks;report["failures"]=failures
 var f:=FileAccess.open("res://build/quality032/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
 print("MAINTENANCE 032: "+JSON.stringify(report))
 quit(1 if failures else 0)
