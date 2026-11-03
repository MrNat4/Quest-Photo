extends SceneTree
const Pending = preload("res://scripts/ai/pending_adjustments.gd")
const Menu = preload("res://scripts/ai/conversion_panel.gd")
const Bridge = preload("res://scripts/android_media_store.gd")
const New = preload("res://scripts/depth_reprojection.gd")
const Old = preload("res://tests/reference/reprojection_032.gd")
const Conversion = preload("res://scripts/ai/depth_conversion.gd")
var checks := 0
var failures := 0
var report := {}
class Native extends RefCounted:
 var response := ""
 var calls := 0
 func export_image(_path: String,_mime: String) -> String:
  calls += 1
  return response
class ConversionSpy extends "res://scripts/ai/depth_conversion.gd":
 var reconstructions := 0
 func _start_reconstruction(_save_raw: bool = false) -> void:
  reconstructions += 1
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok: failures += 1;push_error(label)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
 var pending := Pending.new()
 pending.sync("photo",0.03,0.95)
 for n in 15: pending.nudge(true,-1)
 for n in 15: pending.nudge(false,-1)
 check(is_equal_approx(pending.depth(),0.0225) and is_equal_approx(pending.plane(),0.8),"Exact 0.05 percent / 0.01 increments")
 check(pending.current_depth==0.03 and pending.current_plane==0.95,"Pending edits retain current values")
 pending.sync("photo",0.03,0.95)
 check(is_equal_approx(pending.depth(),0.0225),"Routine menu refresh preserves pending edits")
 pending.sync("other",0.02,0.5)
 check(not pending.changed(),"Changing result resets pending controls")
 pending.nudge(true,-1,true)
 check(pending.depth_ticks==40,"Held motion softly snaps at whole percentages")
 pending.nudge(true,1,true);pending.nudge(true,-1,true)
 check(pending.depth_ticks==40,"Magnet hysteresis avoids jitter")
 for n in 4: pending.nudge(true,-1,true)
 check(pending.depth_ticks<40,"Sustained input moves past magnet")
 pending.sync("test",0.02,0.5,true);pending.nudge(true,-1)
 check(pending.depth_ticks==39,"Single taps reach fine values beside magnet")
 for n in 150:pending.nudge(true,1);pending.nudge(false,1)
 check(pending.depth_ticks==80 and pending.plane_ticks==100,"Supported maxima retained")
 for n in 150:pending.nudge(true,-1);pending.nudge(false,-1)
 check(pending.depth_ticks==0 and pending.plane_ticks==0,"Supported minima retained")
 var native := Native.new()
 for response in ["", "{}", '{"error":""}', '{"uri":"content://a","destination":"Pictures/Z-Dim/a.png","bytes":9}', '{"verified":true,"bytes":8,"uri":"file://a","destination":"Pictures/Z-Dim/a.png"}']:
  native.response=response
  check(not str(Bridge.publish_file("user://test.png","image/png",native).get("error","")).is_empty(),"Invalid native completion cannot silently succeed")
 native.response='{"verified":true,"bytes":123,"uri":"content://media/1","destination":"Pictures/Z-Dim/a.png"}'
 check(Bridge.publish_file("user://test.png","image/png",native).has("destination"),"Verified native response accepted")
 native.response='{"error":"verify stored bytes: IOException — mismatch"}'
 check(Bridge.publish_file("user://test.png","image/png",native).error.contains("mismatch"),"Native failure detail retained")
 var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
 await process_frame
 var original_conversion=app.conversion
 var spy:=ConversionSpy.new()
 app.add_child(spy);app.conversion=spy
 spy._completed_context={"job":{},"source":null,"record":{"strength":0.02,"screen_plane":0.5},"key":"a".repeat(64)}
 app.displayed_conversion={"key":"a".repeat(64),"quality":"High Quality"}
 app._set_conversion_open(true)
 var panel:Node3D=app.conversion_panel
 panel.focus=Menu.COMMANDS.find("depth_slider")
 for n in 15:panel.nudge_slider(1)
 panel.focus=Menu.COMMANDS.find("plane_slider")
 for n in 15:panel.nudge_slider(-1)
 check(spy.reconstructions==0 and not spy.busy,"Repeated slider motion never reconstructs")
 check(is_equal_approx(spy.strength,0.02) and is_equal_approx(spy.screen_plane,0.5),"Displayed settings unchanged until Apply")
 app._conversion_action("apply")
 check(spy.reconstructions==1 and spy.busy,"Apply starts exactly one reconstruction for both settings")
 check(is_equal_approx(spy.strength,0.0275) and is_equal_approx(spy.screen_plane,0.35),"Apply commits both pending values")
 app._conversion_action("apply")
 check(spy.reconstructions==1,"Repeated Apply cannot queue extra reconstructions")
 spy._stage="reconstruct";spy._finish_error("Injected cancellation")
 check(is_equal_approx(spy.strength,0.02) and is_equal_approx(spy.screen_plane,0.5),"Failed Apply restores displayed conversion values")
 app.conversion=original_conversion
 app.free()
 _geometry()
 _portrait()
 report["checks"]=checks;report["failures"]=failures
 DirAccess.make_dir_recursive_absolute("res://build/quality033")
 var f:=FileAccess.open("res://build/quality033/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
 print("REFINEMENT 033: "+JSON.stringify(report))
 quit(1 if failures else 0)
func _geometry() -> void:
 # Strong, continuous depth gradients can fold pixel intervals in one eye.
 # Tiny rings and vertical strands use identical unmodified normalized depths.
 var w:=2048;var h:=32
 var photo:=Image.create(w,h,false,Image.FORMAT_RGB8)
 var depth:=PackedFloat32Array();depth.resize(w*h)
 for y in h:
  for x in w:
   var t:=x%12
   depth[y*w+x]=0.3+float(t)*0.055
   photo.set_pixel(x,y,Color(float(x%7)/6,float(y%5)/4,1.0 if t%4==0 else 0.0))
 var before:=depth.to_byte_array().hex_encode().sha256_text()
 var flipped:Image=photo.duplicate();flipped.flip_x()
 var reversed:=depth.duplicate()
 for y in h:
  for x in w:reversed[y*w+x]=depth[y*w+w-1-x]
 DirAccess.make_dir_recursive_absolute("res://build/quality033")
 for renderer in [Old,New]:
  var label:="032" if renderer==Old else "033"
  var start:=Time.get_ticks_usec()
  var a:Image=renderer._surface_render(photo.get_data(),depth,w,h,0.04,0.5,2,Callable())
  report[label+"_ms"]=(Time.get_ticks_usec()-start)/1000.0
  var b:Image=renderer._surface_render(flipped.get_data(),reversed,w,h,0.04,0.5,2,Callable())
  var error:=0.0
  for y in h:
   for eye in 2:
    for x in w:
     var p:=a.get_pixel(x+eye*w,y);var q:=b.get_pixel(w-1-x+(1-eye)*w,y)
     for c in 3:error+=absf(p[c]-q[c])*255
  report[label+"_mirror_mae"]=error/(w*h*6)
  var right_energy:=0.0
  for y in h:
   for x in w:
    var pixel:=a.get_pixel(x+w,y)
    right_energy+=pixel.r+pixel.g+pixel.b
  report[label+"_right_energy"]=right_energy
  a.save_png("res://build/quality033/contours-"+label+".png")
 check(report["032_right_energy"]==0 and report["033_right_energy"]>1000,"Folded-interval regression: right eye no longer loses every source footprint")
 check(report["033_mirror_mae"]<0.01,"Fold protection remains symmetric between eyes")
 check(before==depth.to_byte_array().hex_encode().sha256_text(),"Refinement never smooths or changes input depth")
 # Flat/low-gradient surface colors and all Balanced output remain unchanged.
 var flat:=Image.create(80,16,false,Image.FORMAT_RF);flat.fill(Color(0.5,0,0))
 var small:Image=photo.duplicate();small.resize(80,16)
 check(New.reconstruct(small,flat,0.03,0.5,0).get_data()==Old.reconstruct(small,flat,0.03,0.5,0).get_data(),"Balanced output remains byte-identical")
 check(New.reconstruct(small,flat,0,0.5,2).get_data()==Old.reconstruct(small,flat,0,0.5,2).get_data(),"Zero-depth detail remains byte-identical")

func _portrait() -> void:
 var source:=Image.load_from_file("res://tests/fixtures/quality/astronaut.png")
 var depth:=Image.create(128,128,false,Image.FORMAT_RF)
 for y in 128:
  for x in 128:
   var r:=Vector2((x*4.0-222)/85,(y*4.0-125)/105).length()
   depth.set_pixel(x,y,Color(0.65+0.3*sqrt(1-r*r) if r<1 else 0.2,0,0))
 var before:=depth.get_data()
 var old:Image=Old.reconstruct(source,depth,0.025,0.5,2)
 var start:=Time.get_ticks_usec()
 var current:Image=New.reconstruct(source,depth,0.025,0.5,2)
 report["033_portrait_ms"]=(Time.get_ticks_usec()-start)/1000.0
 var a:=old.get_data();var b:=current.get_data();var difference:=0.0
 for i in a.size():difference+=absi(a[i]-b[i])
 report["portrait_mae"]=difference/a.size()
 check(report["portrait_mae"]<0.01,"Conservative fix preserves ordinary portrait detail with identical depth")
 check(depth.get_data()==before,"Portrait raw depth remains unchanged")
 current.save_png("res://build/quality033/portrait-033.png")
