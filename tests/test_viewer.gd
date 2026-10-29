# Behavioral integration tests using a dummy renderer and synthetic XR trackers.
# These validate application wiring, NOT GPU output, an OpenXR runtime, or a headset.
extends SceneTree

var failures := 0
var checks := 0
var app: Node3D
var left_tracker: XRControllerTracker
var right_tracker: XRControllerTracker

func _initialize() -> void:
 call_deferred("_run")

func _check(condition: bool, message: String) -> void:
 checks += 1
 if not condition:
  failures += 1
  push_error("FAIL: " + message)

func _near(actual: float, expected: float, message: String) -> void:
 _check(is_equal_approx(actual, expected), "%s (got %f expected %f)" % [message, actual, expected])

func _key(code: Key) -> void:
 var event := InputEventKey.new()
 event.keycode = code
 event.pressed = true
 app._unhandled_key_input(event)

func _make_tracker(tracker_name: String, position: Vector3) -> XRControllerTracker:
 var tracker := XRControllerTracker.new()
 tracker.set_tracker_name(tracker_name)
 tracker.set_tracker_type(XRServer.TRACKER_CONTROLLER)
 tracker.set_pose("grip", Transform3D(Basis.IDENTITY, position), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
 tracker.set_input("thumbstick", Vector2.ZERO)
 tracker.set_input("trigger", 0.0)
 tracker.set_input("squeeze", 0.0)
 XRServer.add_tracker(tracker)
 return tracker

func _run() -> void:
 app = load("res://scenes/main.tscn").instantiate()
 if not app.has_method("_reset_view"):
  _check(false, "main scene script must compile")
  app.free()
  quit(1)
  return
 root.add_child(app)
 app.set_process(false)
 app.set_process_unhandled_key_input(false)
 app._reset_view()
 _check(not app.xr_active, "headless startup explicitly skips XR initialization")
 _check(app.current_index == 0 and app.current_entry.sbs, "startup opens stereo calibration")
 _check(app.material.get_shader_parameter("is_sbs"), "SBS texture layout is bound to shader")
 _check(app.material.get_shader_parameter("stereo_enabled"), "stereo shader mode starts enabled")
 var photograph: Texture2D = app.material.get_shader_parameter("photograph")
 _check(photograph != null and photograph.get_width() > photograph.get_height(), "calibration texture is loaded")
 _key(KEY_SPACE)
 _check(not app.material.get_shader_parameter("stereo_enabled"), "Space switches material to mono")
 _key(KEY_SPACE)
 _check(app.material.get_shader_parameter("stereo_enabled"), "Space restores stereo")
 _key(KEY_V)
 _check(app.material.get_shader_parameter("preview_eye") == 1, "V selects desktop right-eye preview")
 _key(KEY_F)
 _check(app.material.get_shader_parameter("swap_eyes"), "F updates eye swap uniform")
 _key(KEY_R)
 _key(KEY_EQUAL)
 _near(app.state.zoom, 1.1, "keyboard zoom")
 _near(app.material.get_shader_parameter("zoom"), 1.1, "zoom reaches shader")
 _key(KEY_W)
 _near(app.panel.scale.x, 1.05, "physical panel scale")
 _key(KEY_Q)
 _near(app.panel.rotation.z, 0.05, "panel roll")
 _key(KEY_RIGHT)
 _check(app.state.pan.x > 0, "pan moves crop after zoom")
 var prior_position: Vector3 = app.anchor.global_position
 _key(KEY_I)
 _near(app.anchor.global_position.y, prior_position.y + 0.05, "keyboard world positioning")
 _key(KEY_U)
 _near(app.anchor.global_position.z, prior_position.z + 0.1, "keyboard distance")
 _key(KEY_BRACKETRIGHT)
 _near(app.material.get_shader_parameter("convergence"), 0.001, "convergence reaches shader")
 _key(KEY_R)
 _near(app.state.zoom, 1.0, "reset restores zoom")
 _near(app.state.panel_scale, 1.0, "reset restores size")
 _check(app.anchor.global_position.is_equal_approx(prior_position), "reset recenters screen")
 app._left_button("primary")
 _check(not app.state.stereo_enabled, "X toggles stereo")
 var old_help: bool = app.help_visible
 app._left_button("secondary")
 _check(app.help_visible != old_help and app.help.visible == app.help_visible, "Y toggles visible help")
 var count: int = app.library.entries.size()
 app._right_button("primary")
 _check(app.current_index == 1 % count, "A advances library")
 app._right_button("thumbstick_click")
 _check(app.current_index == 0, "right stick click opens calibration")
 app.state.zoom = 2.0
 app._right_button("secondary")
 _near(app.state.zoom, 1.0, "B resets view")
 app.anchor.position.x += 1.0
 app._left_button("thumbstick_click")
 _check(app.anchor.global_position.is_equal_approx(prior_position), "left stick click recenters")
 app._on_unfocus()
 var focused_stereo: bool = app.state.stereo_enabled
 app._left_button("primary")
 _check(app.state.stereo_enabled == focused_stereo, "controller buttons ignored while session unfocused")
 app._on_focus()
 _test_corrupt_navigation()
 _test_trackers()
 await _test_async_export()
 XRServer.remove_tracker(left_tracker)
 XRServer.remove_tracker(right_tracker)
 await _test_exit_during_export()
 print("Viewer behavioral tests: %d checks, %d failures. Dummy renderer + synthetic trackers only; no rendered stereo/headset validation." % [checks, failures])
 quit(0 if failures == 0 else 1)

func _test_trackers() -> void:
 left_tracker = _make_tracker("left_hand", Vector3(-0.3, 1.3, -0.3))
 right_tracker = _make_tracker("right_hand", Vector3(0.3, 1.3, -0.3))
 _check(app.left.get_has_tracking_data() and app.right.get_has_tracking_data(), "synthetic trackers connect to XRController3D nodes")
 app._reset_view()
 right_tracker.set_input("thumbstick", Vector2(0.17, -0.17))
 app._process_controllers(0.05)
 _near(app.state.panel_scale, 1.0, "thumbstick deadzone suppresses size drift")
 _near(app.state.roll, 0.0, "thumbstick deadzone suppresses roll drift")
 right_tracker.set_input("thumbstick", Vector2(0.5, 1.0))
 app._process_controllers(0.05)
 _check(app.state.panel_scale > 1.0 and app.state.roll < 0.0, "right stick scales and rotates")
 app._reset_view()
 left_tracker.set_input("trigger", 0.8)
 app._process_controllers(0.05)
 _check(app.state.zoom > 1.0 and app.state.convergence > 0.0, "left trigger switches right stick to zoom/convergence")
 _near(app.state.panel_scale, 1.0, "zoom modifier preserves physical size")
 _near(app.state.roll, 0.0, "zoom modifier preserves roll")
 right_tracker.set_input("thumbstick", Vector2.ZERO)
 left_tracker.set_input("thumbstick", Vector2(1.0, 1.0))
 app._process_controllers(0.05)
 _check(app.state.pan.x > 0.0 and app.state.pan.y < 0.0, "left stick pans crop")
 left_tracker.set_input("thumbstick", Vector2.ZERO)
 right_tracker.set_input("trigger", 0.8)
 var old_swap: bool = app.state.swap_eyes
 var old_index: int = app.current_index
 right_tracker.set_input("primary", true)
 right_tracker.set_input("primary", false)
 _check(app.state.swap_eyes != old_swap and app.current_index == old_index, "both triggers plus A swaps eyes without advancing photo")
 left_tracker.set_input("trigger", 0.0)
 right_tracker.set_input("trigger", 0.0)
 right_tracker.set_input("squeeze", 0.8)
 app._process_controllers(0.05)
 _check(app.dragging, "right grip begins grab")
 app._on_unfocus()
 _check(not app.dragging and not app.session_focused, "focus loss immediately releases grab")
 var paused_anchor: Transform3D = app.anchor.global_transform
 var paused_scale: float = app.state.panel_scale
 right_tracker.set_input("thumbstick", Vector2(1.0, 1.0))
 app.xr_active = true
 app._process(0.05)
 _check(app.anchor.global_transform == paused_anchor and app.state.panel_scale == paused_scale, "unfocused process ignores held grip and stick input")
 app.xr_active = false
 right_tracker.set_input("thumbstick", Vector2.ZERO)
 app._on_focus()
 app._process_controllers(0.05)
 _check(app.dragging, "focused session can grab again")
 var old_anchor: Vector3 = app.anchor.global_position
 right_tracker.set_pose("grip", Transform3D(Basis.IDENTITY, Vector3(0.5, 1.3, -0.3)), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
 app._process_controllers(0.05)
 _near(app.anchor.global_position.x, old_anchor.x + 0.2, "tracked movement moves grabbed panel")
 right_tracker.invalidate_pose("grip")
 app._process_controllers(0.05)
 _check(not app.dragging, "tracking loss releases grab")
 var lost_anchor: Transform3D = app.anchor.global_transform
 right_tracker.set_input("thumbstick", Vector2(1.0, 1.0))
 var lost_zoom: float = app.state.zoom
 var lost_scale: float = app.state.panel_scale
 app._process_controllers(0.05)
 _check(app.anchor.global_transform == lost_anchor and app.state.zoom == lost_zoom and app.state.panel_scale == lost_scale, "untracked right controller cannot move or resize panel")
 right_tracker.set_pose("grip", Transform3D(Basis.IDENTITY, Vector3(0.3, 1.3, -0.3)), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
 right_tracker.set_input("squeeze", 0.0)
 left_tracker.set_input("trigger", 0.8)
 left_tracker.invalidate_pose("grip")
 app._reset_view()
 app._process_controllers(0.05)
 _check(app.state.zoom == 1.0 and app.state.panel_scale > 1.0, "stale left trigger after tracking loss cannot enable zoom modifier")
 right_tracker.set_input("trigger", 0.8)
 var old_stale_index: int = app.current_index
 app._right_button("primary")
 _check(app.current_index == (old_stale_index + 1) % app.library.entries.size(), "stale left trigger cannot enable eye-swap shortcut")
 left_tracker.set_pose("grip", Transform3D(Basis.IDENTITY, Vector3(-0.3, 1.3, -0.3)), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
 left_tracker.set_input("trigger", 0.0)
 right_tracker.set_input("trigger", 0.0)
 right_tracker.set_input("thumbstick", Vector2.ZERO)

func _test_corrupt_navigation() -> void:
 app.show_photo(0)
 app._reset_view()
 app.state.zoom = 1.7
 app._apply_view()
 var good_texture: Texture2D = app.material.get_shader_parameter("photograph")
 var good_path: String = app.current_entry.path
 var bad_path := "user://viewer-invalid-test.png"
 var file := FileAccess.open(bad_path, FileAccess.WRITE)
 file.store_string("This is not an image.")
 file.close()
 var bad_index: int = app.library.entries.size()
 app.library.entries.append({"path": bad_path, "title": "Corrupt test image", "sbs": false})
 app.show_photo(bad_index)
 _check(app.material.get_shader_parameter("photograph") == good_texture and app.current_entry.path == good_path, "corrupt photo keeps last visible texture and entry")
 _near(app.state.zoom, 1.7, "corrupt photo preserves current adjustments")
 _check(not app.last_notice.is_empty(), "corrupt photo reports load error")
 app._right_button("primary")
 _check(app.current_index == 0, "next skips past failed entry instead of getting stuck")
 app.library.entries.remove_at(bad_index)
 DirAccess.remove_absolute(bad_path)
 app._reset_view()

func _prepare_export_fixture() -> void:
 app.show_photo(0)
 app._reset_view()
 var image := Image.create(80, 40, false, Image.FORMAT_RGB8)
 image.fill(Color.RED)
 image.fill_rect(Rect2i(40, 0, 40, 40), Color.CYAN)
 app.material.set_shader_parameter("photograph", ImageTexture.create_from_image(image))
 app.current_entry = {"path": "viewer-async-test.sbs.png", "title": "Export fixture", "sbs": true}

func _new_exports(before: PackedStringArray) -> PackedStringArray:
 var result := PackedStringArray()
 for name in DirAccess.get_files_at("user://exports"):
  if name not in before:
   result.append(name)
 return result

func _wait_for_export() -> bool:
 var deadline := Time.get_ticks_msec() + 5000
 while app.export_busy and Time.get_ticks_msec() < deadline:
  await process_frame
 _check(not app.export_busy, "async export finishes within 5 seconds")
 return not app.export_busy

func _check_export_file(filename: String, width: int, jpeg: bool) -> void:
 var path := "user://exports".path_join(filename)
 _check(filename.ends_with(".jpg" if jpeg else ".png"), "export filename matches selected format")
 var data := FileAccess.get_file_as_bytes(path)
 _check(data.size() > 8, "export writes actual bytes")
 if data.size() > 8:
  _check((data[0] == 255 and data[1] == 216) if jpeg else data.slice(0, 8) == PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]), "export file signature matches selected codec")
 var image := Image.load_from_file(path)
 _check(image != null and not image.is_empty(), "exported image decodes")
 if image != null and not image.is_empty():
  _check(image.get_width() == width and image.get_height() == 40, "full/half SBS dimensions survive asynchronous UI path")
  var left_color := image.get_pixel(2, 20)
  var right_color := image.get_pixel(width - 3, 20)
  _check(left_color.r > 0.9 and left_color.g < 0.1 and right_color.g > 0.9 and right_color.b > 0.9, "export retains distinct left/right source pixels")
 DirAccess.remove_absolute(path)

func _test_async_export() -> void:
 _prepare_export_fixture()
 app.export_jpeg = false
 DirAccess.make_dir_recursive_absolute("user://exports")
 var before := DirAccess.get_files_at("user://exports")
 _key(KEY_F6)
 _check(app.export_busy, "F6 starts asynchronous export")
 var active_thread: Thread = app.export_thread
 _key(KEY_F7)
 _check(app.export_thread == active_thread and app.last_notice.contains("already running"), "busy guard rejects a second export without replacing thread")
 # Worker must use a snapshot, even when controls change before it completes.
 app.state.swap_eyes = true
 app._apply_view()
 if not await _wait_for_export():
  return
 var created := _new_exports(before)
 _check(created.size() == 1, "busy guard produces exactly one output")
 if created.size() == 1:
  _check_export_file(created[0], 80, false)
 _check(app.last_notice.begins_with("Saved to exports:"), "async completion reports saved result")
 app.state.swap_eyes = false
 app._apply_view()
 before = DirAccess.get_files_at("user://exports")
 left_tracker.set_input("trigger", 0.8)
 app._right_button("thumbstick_click")
 _check(app.export_busy, "left trigger plus right stick click starts half SBS")
 if not await _wait_for_export():
  return
 created = _new_exports(before)
 _check(created.size() == 1, "half PNG export creates one file")
 if created.size() == 1:
  _check_export_file(created[0], 40, false)
 right_tracker.set_input("trigger", 0.8)
 app._right_button("thumbstick_click")
 _check(app.export_jpeg and not app.export_busy, "both triggers plus right stick click selects JPG without exporting")
 left_tracker.set_input("trigger", 0.0)
 before = DirAccess.get_files_at("user://exports")
 app._right_button("thumbstick_click")
 _check(app.export_busy, "right trigger plus right stick click starts full SBS")
 if not await _wait_for_export():
  return
 created = _new_exports(before)
 _check(created.size() == 1, "full JPG export creates one file")
 if created.size() == 1:
  _check_export_file(created[0], 80, true)
 right_tracker.set_input("trigger", 0.0)
 before = DirAccess.get_files_at("user://exports")
 _key(KEY_F7)
 if not await _wait_for_export():
  return
 created = _new_exports(before)
 _check(created.size() == 1, "F7 half JPG export creates one file")
 if created.size() == 1:
  _check_export_file(created[0], 40, true)
 _key(KEY_F8)
 _check(not app.export_jpeg, "F8 switches format back to PNG")

func _test_exit_during_export() -> void:
 _prepare_export_fixture()
 var before := DirAccess.get_files_at("user://exports")
 app._export_view(false)
 _check(app.export_busy, "export is in progress before scene teardown")
 var worker: Thread = app.export_thread
 app.free()
 _check(not worker.is_started(), "scene teardown joins active export thread")
 await process_frame
 var created := _new_exports(before)
 _check(created.size() == 1, "scene teardown permits active export to finish")
 if created.size() == 1:
  _check_export_file(created[0], 80, false)
