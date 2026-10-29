extends SceneTree
const Layout = preload("res://scripts/stereo_layout.gd")
const Library = preload("res://scripts/photo_library.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
 run_tests()
 print("LAYOUT TESTS: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error("FAIL: " + label)

func run_tests() -> void:
 var normalizer = Layout.new()
 var cases := [
  ["mono",Vector2i(100,50),Vector2i(100,50)],
  ["sbs_full",Vector2i(200,50),Vector2i(200,50)],
  ["sbs_half",Vector2i(100,50),Vector2i(200,50)],
  ["ou_full",Vector2i(100,100),Vector2i(200,50)],
  ["ou_half",Vector2i(100,50),Vector2i(200,50)]]
 for data in cases:
  var source := Image.create(data[1].x,data[1].y,false,Image.FORMAT_RGB8)
  source.fill(Color.RED)
  if str(data[0]).begins_with("sbs"):
   source.fill_rect(Rect2i(source.get_width()/2,0,source.get_width()/2,source.get_height()),Color.BLUE)
  elif str(data[0]).begins_with("ou"):
   source.fill_rect(Rect2i(0,source.get_height()/2,source.get_width(),source.get_height()/2),Color.BLUE)
  var image: Image = normalizer.normalize(source,data[0])
  check(image != null,"Layout accepted: " + data[0])
  if image == null:
   continue
  check(image.get_size()==data[2],"Restored aspect and canonical dimensions: " + data[0])
  check(image.get_pixel(0,0)==Color.RED,"Left/top eye first: " + data[0])
  if data[0] != "mono":
   check(image.get_pixel(image.get_width()-1,0)==Color.BLUE,"Right/bottom eye second: " + data[0])
   check(image.get_pixel(image.get_width()/2-1,0)==Color.RED,"No seam contamination: " + data[0])
  var thumb: Image = normalizer.normalize(source,data[0],32)
  check(thumb.get_height() <= 32 and thumb.get_width() <= (32 if data[0]=="mono" else 64),"Thumbnail bound: " + data[0])
  check(source.get_pixel(0,0)==Color.RED,"Normalization preserves original: " + data[0])
 check(normalizer.normalize(Image.create(7,4,false,Image.FORMAT_RGB8),"sbs_full")==null,"Odd SBS width rejected")
 check(normalizer.normalize(Image.create(4,7,false,Image.FORMAT_RGB8),"ou_full")==null,"Odd OU height rejected")
 check(normalizer.normalize(Image.create(4,4,false,Image.FORMAT_RGB8),"unknown")==null,"Unknown layout rejected")
 for pair in [["foo.sbs.jpg","sbs_full"],["foo.half-sbs.PNG","sbs_half"],["foo.ou.webp","ou_full"],["foo.half-ou.bmp","ou_half"],["sbs_beach.jpg","mono"],["foo.sbs-edited.png","mono"],["foo.OU.JPG","ou_full"]]:
  check(Layout.detect(pair[0])==pair[1],"Unambiguous filename: " + pair[0])
 var library = Library.new()
 var path := "user://layout-test-%d.png" % Time.get_ticks_usec()
 var source := Image.create(100,100,false,Image.FORMAT_RGB8)
 source.fill(Color.RED)
 source.fill_rect(Rect2i(0,50,100,50),Color.BLUE)
 source.save_png(path)
 var entry := {"path":path,"sbs":false}
 check(library.set_layout(entry,"ou_full")==OK,"Manual layout persisted")
 var fresh = Library.new()
 var reloaded := {"path":path}
 check(fresh.layout_for(reloaded)=="ou_full","Override survives new library")
 var image: Image = fresh.load_image(reloaded,64)
 check(image!=null and image.get_size()==Vector2i(128,32),"Runtime load canonical normalized image")
 check(reloaded.sbs and reloaded.layout=="ou_full","Loaded entry exposes canonical stereo flag")
 check(library.set_layout(entry,"mono")==OK and fresh.layout_for({"path":path})=="mono","Explicit mono overrides stereo detection")
 var sidecar := ConfigFile.new()
 sidecar.set_value("photo","original_name","my-photo.half-sbs.png")
 sidecar.save(path+".import.cfg")
 DirAccess.remove_absolute(library.metadata_path(path))
 check(fresh.layout_for({"path":path})=="sbs_half","Imported original name controls detection")
 check(library.set_layout(entry,"unsupported")==ERR_INVALID_PARAMETER,"Invalid override rejected")
 DirAccess.remove_absolute(path)
 DirAccess.remove_absolute(path+".import.cfg")
