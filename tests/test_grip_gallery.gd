extends SceneTree
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
 checks += 1
 if not value:
  failures += 1
  push_error(message)
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var map := load("res://openxr_action_map.tres") as OpenXRActionMap
 var actions := map.get_action_set(0).get_actions()
 var runtime_names: Array[String] = []
 var squeeze: OpenXRAction
 for action: OpenXRAction in actions:
  # Mirrors OpenXRInterface::create_action: check existing *renamed* names
  # before transforming a pose name. Old grip_pose -> grip then grip collided.
  check(str(action.resource_name) not in runtime_names, "Action must survive engine duplicate check: " + action.resource_name)
  var runtime_name := str(action.resource_name)
  if action.action_type == OpenXRAction.OPENXR_ACTION_POSE and runtime_name in ["aim_pose", "grip_pose", "default_pose"]:
   runtime_name = runtime_name.trim_suffix("_pose")
  runtime_names.append(runtime_name)
  if action.resource_name == "squeeze":
   squeeze = action
 check(squeeze != null and squeeze.action_type == OpenXRAction.OPENXR_ACTION_FLOAT, "squeeze is an independent float action")
 var squeeze_paths: Array[String] = []
 for binding: OpenXRIPBinding in map.get_interaction_profile(0).get_bindings():
  if binding.action == squeeze:
   squeeze_paths.append(binding.binding_path)
 check(squeeze_paths.has("/user/hand/left/input/squeeze/value") and squeeze_paths.has("/user/hand/right/input/squeeze/value"), "both physical squeeze axes bound")
 var app = load("res://scenes/main.tscn").instantiate()
 root.add_child(app)
 var left := XRControllerTracker.new()
 left.set_tracker_name("left_hand")
 left.set_tracker_type(XRServer.TRACKER_CONTROLLER)
 left.set_pose("grip",Transform3D(Basis.IDENTITY,Vector3(-0.3,1.3,-0.3)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
 left.set_input("squeeze",0.0)
 XRServer.add_tracker(left)
 var old_help: bool = app.help_visible
 left.set_input("secondary",true)
 left.set_input("secondary",false)
 check(app.help_visible != old_help and not app.gallery_open, "plain Y still toggles Help")
 left.set_input("squeeze",1.0)
 old_help = app.help_visible
 left.set_input("secondary",true)
 left.set_input("secondary",false)
 check(app.gallery_open and app.gallery.visible and not app.anchor.visible, "physical mapped squeeze + Y opens gallery")
 check(app.help_visible == old_help, "modified Y does not toggle Help")
 check(app.gallery._cells.size() == 6, "opened gallery contains six thumbnail slots")
 app._right_button("secondary")
 check(not app.gallery_open and app.anchor.visible, "B returns from gallery")
 var old_stereo: bool = app.state.stereo_enabled
 var old_layout: String = app.library.layout_for(app.current_entry)
 left.set_input("primary",true)
 left.set_input("primary",false)
 check(app.library.layout_for(app.current_entry) != old_layout, "squeeze + X changes layout")
 check(app.state.stereo_enabled == old_stereo, "modified X preserves stereo toggle")
 var old_index: int = app.current_index
 app._right_button("primary")
 check(app.current_index == wrapi(old_index-1,0,app.library.entries.size()), "left squeeze + A navigates previous")
 left.invalidate_pose("grip")
 check(not app._grip_held(app.left), "lost pose cannot retain modifier")
 app._on_unfocus()
 var help_before: bool = app.help_visible
 app._left_button("secondary")
 check(app.help_visible == help_before and not app.gallery_open, "unfocused input ignored")
 check(FileAccess.file_exists("user://controller-gallery-diagnostics.json"), "diagnostics persisted")
 var rows: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://controller-gallery-diagnostics.json"))
 check(rows is Array and rows.size() > 0 and rows.back().left.has("squeeze_present"), "diagnostics identify missing squeeze input")
 XRServer.remove_tracker(left)
 app.free()
 print("GRIP/GALLERY TESTS: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)
