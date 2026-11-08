extends SceneTree
const Bridge=preload("res://scripts/android_media_store.gd")
const Old=preload("res://tests/reference/reprojection_033.gd")
const New=preload("res://scripts/depth_reprojection.gd")
var checks:=0
var failures:=0
var report:={}
class NativeRegistry extends RefCounted:
 var present:=true
 var lookups:=0
 var calls:=0
 func has_java_method(name:String) -> bool:
  lookups+=1
  return present and name=="export_image"
 func export_image(_path:String,_mime:String) -> String:
  calls+=1
  return '{"verified":true,"bytes":80,"uri":"content://media/1","destination":"Pictures/Z-Dim/new.png"}'
func check(ok:bool, message:String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
 if OS.get_environment("QUEST_PHOTO_TEST_ISOLATED") != "1":
  push_error("Run tools/run_checks.py; diagnostic file tests require isolated storage.")
  quit(1)
  return
 var native:=NativeRegistry.new()
 check(Bridge.publish_file("user://test.png","image/png",native).has("destination"),"Java registry capability permits export")
 check(native.lookups==1 and native.calls==1,"JNI capability lookup actually used")
 native.present=false
 var result:=Bridge.publish_file("user://test.png","image/png",native)
 check(result.get("error","").contains("Java registry") and native.calls==1,"Outdated AAR rejected without invoking absent method")
 check(Bridge.publish_file("user://test.png","image/png",RefCounted.new()).has("error"),"Missing export capability is descriptive")
 _edge();_holes();_preserve();await _diagnostic()
 report["checks"]=checks;report["failures"]=failures
 var f:=FileAccess.open("res://build/quality034/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
 print("EXPORT / EDGES 034: "+JSON.stringify(report))
 quit(1 if failures else 0)
func _edge() -> void:
 var w:=500;var h:=8
 var photo:=Image.create(w,h,false,Image.FORMAT_RGB8);photo.fill(Color(0.2,0.2,0.2))
 var depth:=PackedFloat32Array();depth.resize(w*h);depth.fill(0.5)
 for y in h:
  for x in range(100,200):
   photo.set_pixel(x,y,Color.WHITE);depth[y*w+x]=0.53
 DirAccess.make_dir_recursive_absolute("res://build/quality034")
 for renderer in [Old,New]:
  var tag:="033" if renderer==Old else "034"
  var image:Image=renderer._surface_render(photo.get_data(),depth,w,h,0.04,0.5,1,Callable())
  var mae:=0.0
  for eye in 2:
   var shift:=0.3 if eye==0 else -0.3
   for x in range(98,202):
    var alpha:=maxf(0,minf(x+0.5,199.5+shift)-maxf(x-0.5,99.5+shift))
    var expected:=0.2+0.8*alpha
    mae+=absf(image.get_pixel(x+eye*w,4).r-expected)*255
  report[tag+"_edge_mae"]=mae/(104*2)
  image.save_png("res://build/quality034/edge-"+tag+".png")
 check(report["034_edge_mae"]<0.02,"Analytic subpixel silhouette has correct coverage")
 check(report["034_edge_mae"]<report["033_edge_mae"]*0.1,"Joint color/depth boundary reduces measured halo")
func bg(x:int)->Color:
 return Color(0.05,0.25 if (x/4)%2==0 else 0.75,0.6)
func _holes() -> void:
 var w:=500;var h:=24
 var photo:=Image.create(w,h,false,Image.FORMAT_RGB8)
 var d:=PackedFloat32Array();d.resize(w*h);d.fill(0.1)
 for y in h:
  for x in w:
   photo.set_pixel(x,y,bg(x))
   if y>=10 and y<=12 and x>=100 and x<200:
    photo.set_pixel(x,y,Color.RED);d[y*w+x]=0.9
 var old_hash:=d.to_byte_array().hex_encode().sha256_text()
 var flip:Image=photo.duplicate();flip.flip_x()
 var fd:=d.duplicate()
 for y in h:
  for x in w:fd[y*w+x]=d[y*w+w-1-x]
 for renderer in [Old,New]:
  for mode in [1,2]:
   var tag:=("033" if renderer==Old else "034")+"_"+str(mode)
   var start:=Time.get_ticks_usec()
   var image:Image=renderer._surface_render(photo.get_data(),d,w,h,0.04,0.5,mode,Callable())
   report[tag+"_ms"]=(Time.get_ticks_usec()-start)/1000.0
   var error:=0.0
   for eye in 2:
    for x in range(96 if eye==0 else 196,104 if eye==0 else 204):
     var expected:=bg(x+(4 if eye==0 else -4))
     error+=absf(image.get_pixel(x+eye*w,11).g-expected.g)*255
   report[tag+"_hole_mae"]=error/16
   image.save_png("res://build/quality034/holes-"+tag+".png")
   if renderer==New:
    var mirrored:Image=renderer._surface_render(flip.get_data(),fd,w,h,0.04,0.5,mode,Callable())
    var mirror_error:=0.0
    for eye in 2:
     for y in h:
      for x in w:
       var a:=image.get_pixel(x+eye*w,y);var b:=mirrored.get_pixel(w-1-x+(1-eye)*w,y)
       for c in 3:mirror_error+=absf(a[c]-b[c])*255
    check(mirror_error/(w*h*6)<0.01,"Disocclusion / eye swap symmetry mode "+str(mode))
 for mode in [1,2]:
  check(report["034_"+str(mode)+"_hole_mae"]<0.5,"Nearby genuine background recovers known occluded stripes "+str(mode))
  check(report["034_"+str(mode)+"_hole_mae"]<report["033_"+str(mode)+"_hole_mae"]*0.1,"Hole fill improves against known background "+str(mode))
 # A wider obscurer requires Maximum's four-row search; High remains bounded.
 for y in range(8,15):
  for x in range(100,200):
   photo.set_pixel(x,y,Color.RED)
 var wide_depth:=d.duplicate()
 for y in range(8,15):
  for x in range(100,200):wide_depth[y*w+x]=0.9
 for mode in [1,2]:
  var wide:Image=New._surface_render(photo.get_data(),wide_depth,w,h,0.04,0.5,mode,Callable())
  var mae:=0.0
  for x in range(96,104):mae+=absf(wide.get_pixel(x,11).g-bg(x+4).g)*255
  report["034_wide_hole_mae_"+str(mode)]=mae/8
 check(report["034_wide_hole_mae_2"]<report["034_wide_hole_mae_1"]*0.1,"Maximum can reach valid background beyond High's bounded search")
 check(d.to_byte_array().hex_encode().sha256_text()==old_hash,"Raw depth never modified")
 # Nearby foreground in all directions must never become a background donor.
 var all_near:=d.duplicate();all_near.fill(0.9)
 check(New._background_donor(photo.get_data(),all_near,w,h,120,11,0.1,10,0.5,4)==Vector4.ZERO,"Foreground-only neighborhood cannot contaminate a hole")
func _preserve() -> void:
 var photo:=Image.load_from_file("res://tests/fixtures/quality/astronaut.png")
 var depth:=Image.create(128,128,false,Image.FORMAT_RF)
 for y in 128:
  for x in 128:
   depth.set_pixel(x,y,Color(0.5+0.1*sin(x*0.06)*cos(y*0.08),0,0))
 var original:=depth.get_data()
 for mode in 3:
  var begin:=Time.get_ticks_usec()
  var old:Image=Old.reconstruct(photo,depth,0.025,0.5,mode)
  report["033_portrait_ms_"+str(mode)]=(Time.get_ticks_usec()-begin)/1000.0
  begin=Time.get_ticks_usec()
  var current:Image=New.reconstruct(photo,depth,0.025,0.5,mode)
  report["034_portrait_ms_"+str(mode)]=(Time.get_ticks_usec()-begin)/1000.0
  var a:=old.get_data();var b:=current.get_data();var sum:=0.0
  for i in a.size():sum+=absi(a[i]-b[i])
  report["portrait_mae_"+str(mode)]=sum/a.size()
  var roi:=0.0
  for eye in 2:
   for y in range(50,230):
    for x in range(120,320):
     var index:=((y*1024)+x+eye*512)*3
     for c in 3:roi+=absi(a[index+c]-b[index+c])
  report["face_roi_error_"+str(mode)]=roi
  var old_detail:=0.0
  var new_detail:=0.0
  for eye in 2:
   for y in range(50,230):
    for x in range(121,320):
     var index:=((y*1024)+x+eye*512)*3
     for c in 3:
      old_detail+=absi(a[index+c]-a[index-3+c])
      new_detail+=absi(b[index+c]-b[index-3+c])
  report["face_detail_ratio_"+str(mode)]=new_detail/old_detail
  check(roi/(200*180*2*3)<0.1 and absf(new_detail/old_detail-1.0)<0.01,"Facial detail contrast retained within 1 percent, sub-level mean color change "+str(mode))
  if mode>0:
   var guided_old:=Old._guided_depth(photo,depth,0.0,1.0,Callable())
   var guided_new:=New._guided_depth(photo,depth,0.0,1.0,Callable())
   check(guided_old==guided_new,"Depth estimation/refinement unchanged on the same portrait")
  if mode==0: check(sum==0,"Balanced remains byte-identical across the whole image")
 check(depth.get_data()==original,"Portrait depth unchanged")

func _diagnostic() -> void:
 var raw:=Image.create(32,16,false,Image.FORMAT_RF)
 for y in 16:
  for x in 32:raw.set_pixel(x,y,Color(1+x,0,0))
 var bytes:=raw.get_data()
 var diagnostic=preload("res://scripts/ai/depth_diagnostic.gd")
 var inverse:Image=diagnostic.render(raw,true)
 var distance:Image=diagnostic.render(raw,false)
 check(inverse.get_pixel(31,8).r>inverse.get_pixel(0,8).r,"V2 inverse depth shows near as white")
 check(distance.get_pixel(0,8).r>distance.get_pixel(31,8).r,"V3 metric depth shows near as white")
 check(raw.get_data()==bytes,"Diagnostic never edits original depth")
 var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
 await process_frame
 app.displayed_conversion={"key":"test","source_path":app.original_entry.path}
 var texture=app.material.get_shader_parameter("photograph")
 app._depth_ready(inverse,app.displayed_conversion)
 check(app.diagnostic_texture==texture and not app.material.get_shader_parameter("is_sbs"),"Diagnostic retains original texture and uses mono viewing")
 app._export_view(false)
 check(not app.export_busy and app.last_notice.contains("diagnostic"),"Diagnostic cannot accidentally export as SBS")
 app._toggle_depth_map()
 check(app.diagnostic_texture==null and app.material.get_shader_parameter("photograph")==texture,"Diagnostic toggle restores image without reconstruction")
 app.free()
 var path:="user://diagnostic-034.qpd"
 var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer("QPD1".to_ascii_buffer());file.store_32(32);file.store_32(16);file.store_buffer(bytes);file.close()
 var original_hash:=FileAccess.get_sha256(path)
 var controller=preload("res://scripts/ai/depth_conversion.gd").new();root.add_child(controller)
 controller._completed_context={"job":{"raw_path":path,"inverse_depth":true},"record":{"key":"saved","source_path":"original"}}
 var seen:Array=[]
 controller.depth_ready.connect(func(image:Image,_record:Dictionary)->void:seen.append(image))
 controller.show_depth_map()
 var deadline:=Time.get_ticks_msec()+5000
 while controller.busy and Time.get_ticks_msec()<deadline:await create_timer(0.01).timeout
 check(not controller.busy and seen.size()==1,"Diagnostic loads asynchronously from cached QPD without inference backend")
 check(FileAccess.get_sha256(path)==original_hash,"Diagnostic worker preserves cached raw file hash")
 controller.free();DirAccess.remove_absolute(path)
