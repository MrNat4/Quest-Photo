extends Node3D

const State = preload("res://scripts/view_state.gd")
const Library = preload("res://scripts/photo_library.gd")
const STEREO_SHADER = preload("res://shaders/stereo.gdshader")
const Exporter = preload("res://scripts/stereo_export.gd")
var state = State.new()
var library = Library.new()
var current_index := 0
var current_entry: Dictionary = {}
var xr: XRInterface
var xr_active := false
var session_focused := true
var origin: XROrigin3D
var camera: XRCamera3D
var left: XRController3D
var right: XRController3D
var anchor: Node3D
var panel: MeshInstance3D
var material: ShaderMaterial
var status: Label3D
var help: Label3D
var desktop_label: Label
var file_dialog: FileDialog
var help_visible := true
var preview_eye := 0
var dragging := false
var grab_offset := Transform3D.IDENTITY
var save_countdown := -1.0
var last_notice := ""
var notice_until := 0
var export_thread: Thread
var export_busy := false
var export_jpeg := false
var awaiting_head_pose := false

func _ready() -> void:
 _build_scene()
 _initialize_xr()
 library.refresh()
 show_photo(0)
 recenter()
 print("Quest Photo ready; XR active: ", xr_active, "; library items: ", library.entries.size())

func _build_scene() -> void:
 origin = XROrigin3D.new()
 add_child(origin)
 camera = XRCamera3D.new()
 camera.position.y = 1.6
 camera.near = 0.05
 origin.add_child(camera)
 camera.current = true
 left = _controller("left_hand", Color(0.18, 0.8, 0.9))
 right = _controller("right_hand", Color(1.0, 0.7, 0.2))
 left.button_pressed.connect(_left_button)
 right.button_pressed.connect(_right_button)
 anchor = Node3D.new()
 add_child(anchor)
 panel = MeshInstance3D.new()
 var quad := QuadMesh.new()
 quad.size = Vector2(2.0, 1.5)
 panel.mesh = quad
 material = ShaderMaterial.new()
 material.shader = STEREO_SHADER
 panel.material_override = material
 anchor.add_child(panel)
 status = _label(32, 0.0013)
 anchor.add_child(status)
 help = _label(24, 0.0012)
 help.text = "A: next photo   X: 2D / stereo   B: reset   Y: help\nRight stick: size / rotate   Left stick: pan\nHold left trigger + right stick: zoom / convergence\nRight grip: grab   Left stick click: recenter\nRight stick click: calibration; + right/left trigger: full/half SBS export\nBoth triggers + right stick click: PNG/JPG; + A: swap eyes"
 anchor.add_child(help)
 var layer := CanvasLayer.new()
 add_child(layer)
 desktop_label = Label.new()
 desktop_label.position = Vector2(20, 15)
 desktop_label.add_theme_font_size_override("font_size", 19)
 layer.add_child(desktop_label)
 file_dialog = FileDialog.new()
 file_dialog.access = FileDialog.ACCESS_FILESYSTEM
 file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
 file_dialog.filters = PackedStringArray(["*.jpg,*.jpeg,*.png ; Photographs"])
 file_dialog.file_selected.connect(_open_desktop_file)
 layer.add_child(file_dialog)

func _label(font_size: int, pixel_size: float) -> Label3D:
 var label := Label3D.new()
 label.font_size = font_size
 label.pixel_size = pixel_size
 label.no_depth_test = false
 label.outline_size = 5
 label.modulate = Color(0.84, 0.9, 0.98)
 return label

func _controller(tracker_name: String, color: Color) -> XRController3D:
 var controller := XRController3D.new()
 controller.tracker = tracker_name
 controller.pose = "grip"
 origin.add_child(controller)
 var mesh := MeshInstance3D.new()
 var shape := CapsuleMesh.new()
 shape.radius = 0.018
 shape.height = 0.09
 mesh.mesh = shape
 mesh.rotation_degrees.x = 65
 var surface := StandardMaterial3D.new()
 surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 surface.albedo_color = color
 mesh.material_override = surface
 controller.add_child(mesh)
 return controller

func _initialize_xr() -> void:
 # Headless and explicit desktop runs must never attempt runtime initialization.
 if DisplayServer.get_name() == "headless" or "--desktop" in OS.get_cmdline_user_args() or "off" in OS.get_cmdline_args():
  return
 xr = XRServer.find_interface("OpenXR")
 if xr != null and (xr.is_initialized() or xr.initialize()):
  xr_active = true
  get_viewport().use_xr = true
  DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
  camera.position = Vector3.ZERO
  if xr.has_signal("session_focussed"):
   xr.connect("session_focussed", _on_focus)
   xr.connect("session_visible", _on_unfocus)
   xr.connect("session_stopping", _on_unfocus)
  if xr.has_signal("pose_recentered"):
   xr.connect("pose_recentered", recenter)
  awaiting_head_pose = true
 elif OS.get_name() == "Android":
  _notice("OpenXR failed to initialize. See build and headset diagnostics.")
 desktop_label.visible = not xr_active

func _on_focus() -> void:
 session_focused = true

func _on_unfocus() -> void:
 session_focused = false
 dragging = false
 _save_view()

func recenter() -> void:
 dragging = false
 var forward := -camera.global_basis.z
 forward.y = 0.0
 if forward.length_squared() < 0.01:
  forward = Vector3.FORWARD
 forward = forward.normalized()
 anchor.global_position = camera.global_position + forward * 2.4
 anchor.look_at(camera.global_position, Vector3.UP, true)
 _apply_view()

func show_photo(index: int) -> void:
 if library.entries.is_empty():
  return
 var candidate_index := wrapi(index, 0, library.entries.size())
 var entry: Dictionary = library.entries[candidate_index]
 var texture: Texture2D = library.load_photo(entry)
 if texture == null:
  current_index = candidate_index
  _notice(library.error_message)
  return
 _save_view()
 current_index = candidate_index
 current_entry = entry
 state = State.new()
 state.load_from(library.settings_path(str(entry.path)))
 material.set_shader_parameter("photograph", texture)
 material.set_shader_parameter("is_sbs", bool(entry.sbs))
 var aspect := float(texture.get_width()) / texture.get_height()
 if bool(entry.sbs):
  aspect *= 0.5
 var width := minf(2.0, 1.5 * aspect)
 (panel.mesh as QuadMesh).size = Vector2(width, width / aspect)
 _apply_view()

func _apply_view() -> void:
 if panel == null:
  return
 state.constrain()
 panel.scale = Vector3.ONE * state.panel_scale
 panel.rotation.z = state.roll
 material.set_shader_parameter("zoom", state.zoom)
 material.set_shader_parameter("pan", state.pan)
 material.set_shader_parameter("stereo_enabled", state.stereo_enabled)
 material.set_shader_parameter("swap_eyes", state.swap_eyes)
 material.set_shader_parameter("convergence", state.convergence)
 material.set_shader_parameter("preview_eye", preview_eye)
 material.set_shader_parameter("xr_active", xr_active)
 var size := (panel.mesh as QuadMesh).size
 var half_height: float = (absf(sin(state.roll)) * size.x + absf(cos(state.roll)) * size.y) * state.panel_scale * 0.5
 status.position = Vector3(0, half_height + 0.11, 0)
 help.position = Vector3(0, -half_height - 0.22, 0)
 _update_labels()

func _update_labels() -> void:
 var title := str(current_entry.get("title", "Quest Photo"))
 var mode := "STEREO" if bool(current_entry.get("sbs", false)) and state.stereo_enabled else "2D"
 if not bool(current_entry.get("sbs", false)):
  mode += " · AI conversion pending"
 status.text = "%s\n%s  |  Zoom %.2fx  |  Size %.2fx" % [title, mode, state.zoom, state.panel_scale]
 if Time.get_ticks_msec() < notice_until:
  status.text += "\n" + last_notice
 help.visible = help_visible
 desktop_label.text = "QUEST PHOTO · desktop preview (%s eye)\n%s\n\nO: open photo   N/P: next/previous   T: calibration   Space: 2D/stereo\nW/S: size   Q/E: rotate   +/-: zoom   Arrows: pan\nI/J/K/L: position   U/D: distance   R: reset/recenter\n[/]: convergence   V: preview eye   F: swap eyes   H: help\nF5: refresh   F6/F7: full/half SBS export   F8: PNG/JPG   Esc: quit\n\nPhoto folder: %s" % ["left" if preview_eye == 0 else "right", status.text, ProjectSettings.globalize_path(Library.PHOTO_DIR)]

func _process(delta: float) -> void:
 if xr_active and session_focused:
  if awaiting_head_pose:
   var head := XRServer.get_tracker("head") as XRPositionalTracker
   if head != null and head.has_pose("default") and head.get_pose("default").has_tracking_data:
    recenter()
    awaiting_head_pose = false
  _process_controllers(minf(delta, 0.05))
 if save_countdown >= 0:
  save_countdown -= delta
  if save_countdown < 0:
   _save_view()
 if notice_until > 0 and Time.get_ticks_msec() >= notice_until:
  notice_until = 0
  _update_labels()

func _axis(value: Vector2) -> Vector2:
 return Vector2(0 if absf(value.x) < 0.18 else value.x, 0 if absf(value.y) < 0.18 else value.y)

func _process_controllers(delta: float) -> void:
 var l := _axis(left.get_vector2("thumbstick")) if left.get_has_tracking_data() else Vector2.ZERO
 var r := _axis(right.get_vector2("thumbstick")) if right.get_has_tracking_data() else Vector2.ZERO
 if l != Vector2.ZERO or r != Vector2.ZERO:
  state.pan += Vector2(l.x, -l.y) * delta * 0.3 / state.zoom
  if _trigger_held(left):
   state.zoom *= exp(r.y * delta)
   state.convergence += r.x * delta * 0.008
  else:
   state.panel_scale *= exp(r.y * delta * 0.5)
   state.roll -= r.x * delta * 0.6
  _changed()
 var gripping := right.get_has_tracking_data() and right.get_float("grip") > 0.65
 if gripping and not dragging:
  grab_offset = right.global_transform.affine_inverse() * anchor.global_transform
  dragging = true
 elif not gripping:
  dragging = false
 if dragging:
  var proposed := right.global_transform * grab_offset
  var distance := proposed.origin.distance_to(camera.global_position)
  if distance >= 0.6 and distance <= 8.0:
   anchor.global_transform = proposed

func _left_button(action: StringName) -> void:
 if not session_focused:
  return
 match action:
  "primary":
   state.stereo_enabled = not state.stereo_enabled
   _changed()
  "secondary":
   help_visible = not help_visible
   _update_labels()
  "thumbstick_click": recenter()

func _right_button(action: StringName) -> void:
 if not session_focused:
  return
 match action:
  "primary":
   if _trigger_held(left) and _trigger_held(right):
    state.swap_eyes = not state.swap_eyes
    _changed()
   else:
    show_photo(current_index + 1)
  "secondary": _reset_view()
  "thumbstick_click":
   if _trigger_held(left) and _trigger_held(right):
    _toggle_export_format()
   elif _trigger_held(right):
    _export_view(false)
   elif _trigger_held(left):
    _export_view(true)
   else:
    show_photo(0)

func _trigger_held(controller: XRController3D) -> bool:
 return controller.get_has_tracking_data() and controller.get_float("trigger") > 0.6

func _toggle_export_format() -> void:
 export_jpeg = not export_jpeg
 _notice("Export format: " + ("JPG" if export_jpeg else "PNG"))

func _export_view(half_sbs: bool) -> void:
 if export_busy:
  _notice("An export is already running.")
  return
 if current_entry.is_empty():
  return
 var folder := "user://exports"
 var result := DirAccess.make_dir_recursive_absolute(folder)
 if result != OK:
  _notice("Cannot create export folder: " + error_string(result))
  return
 var texture: Texture2D = material.get_shader_parameter("photograph")
 var image := texture.get_image()
 if image == null:
  _notice("Cannot read current image for export.")
  return
 var filename := "%s_%d_%d.%s.%s" % [str(current_entry.path).get_file().get_basename(), int(Time.get_unix_time_from_system()), Time.get_ticks_msec(), "half-sbs" if half_sbs else "sbs", "jpg" if export_jpeg else "png"]
 var path := folder.path_join(filename)
 export_thread = Thread.new()
 export_busy = true
 result = export_thread.start(_write_export.bind(image, bool(current_entry.sbs), state.to_dictionary(), half_sbs, path))
 if result != OK:
  export_busy = false
  _notice("Could not start export: " + error_string(result))
 else:
  _notice("Exporting " + ("half SBS…" if half_sbs else "full SBS…"))

func _write_export(image: Image, is_sbs: bool, view: Dictionary, half_sbs: bool, path: String) -> void:
 var result: Error = Exporter.export_sbs(image, is_sbs, view, half_sbs, path)
 _export_finished.call_deferred(result, path)

func _export_finished(result: Error, path: String) -> void:
 if export_thread != null and export_thread.is_started():
  export_thread.wait_to_finish()
 export_busy = false
 _notice("Saved to exports: " + path.get_file() if result == OK else "Export failed: " + error_string(result))

func _exit_tree() -> void:
 if export_thread != null and export_thread.is_started():
  export_thread.wait_to_finish()

func _reset_view() -> void:
 state = State.new()
 recenter()
 _changed()

func _changed() -> void:
 _apply_view()
 save_countdown = 0.7

func _save_view() -> void:
 if current_entry.is_empty():
  return
 var result: Error = state.save_to(library.settings_path(str(current_entry.path)))
 if result != OK:
  _notice("Cannot save viewing settings: " + error_string(result))

func _notice(message: String) -> void:
 last_notice = message
 notice_until = Time.get_ticks_msec() + 6000
 if status != null:
  _update_labels()

func _open_desktop_file(path: String) -> void:
 var entry := {"path": path, "title": path.get_file(), "sbs": path.get_basename().to_lower().ends_with(".sbs")}
 library.entries.append(entry)
 show_photo(library.entries.size() - 1)

func _unhandled_key_input(event: InputEvent) -> void:
 if not event is InputEventKey or not event.pressed or file_dialog.visible:
  return
 match event.keycode:
  KEY_ESCAPE:
   _save_view()
   get_tree().quit()
  KEY_O:
   if not xr_active:
    file_dialog.popup_centered_ratio(0.8)
  KEY_N: show_photo(current_index + 1)
  KEY_P: show_photo(current_index - 1)
  KEY_T: show_photo(0)
  KEY_SPACE: state.stereo_enabled = not state.stereo_enabled
  KEY_W: state.panel_scale *= 1.05
  KEY_S: state.panel_scale /= 1.05
  KEY_Q: state.roll += 0.05
  KEY_E: state.roll -= 0.05
  KEY_EQUAL, KEY_PLUS: state.zoom *= 1.1
  KEY_MINUS: state.zoom /= 1.1
  KEY_LEFT: state.pan.x -= 0.025 / state.zoom
  KEY_RIGHT: state.pan.x += 0.025 / state.zoom
  KEY_UP: state.pan.y -= 0.025 / state.zoom
  KEY_DOWN: state.pan.y += 0.025 / state.zoom
  KEY_I: anchor.position.y += 0.05
  KEY_K: anchor.position.y -= 0.05
  KEY_J: anchor.position.x -= 0.05
  KEY_L: anchor.position.x += 0.05
  KEY_U: anchor.position.z = minf(anchor.position.z + 0.1, camera.position.z - 0.6)
  KEY_D: anchor.position.z = maxf(anchor.position.z - 0.1, camera.position.z - 8.0)
  KEY_R: _reset_view()
  KEY_BRACKETLEFT: state.convergence -= 0.001
  KEY_BRACKETRIGHT: state.convergence += 0.001
  KEY_V: preview_eye = 1 - preview_eye
  KEY_F: state.swap_eyes = not state.swap_eyes
  KEY_H: help_visible = not help_visible
  KEY_F5:
   _save_view()
   library.refresh()
   show_photo(0)
  KEY_F6: _export_view(false)
  KEY_F7: _export_view(true)
  KEY_F8: _toggle_export_format()
  _: return
 _changed()

func _notification(what: int) -> void:
 if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
  _save_view()
