extends Node3D

const State = preload("res://scripts/view_state.gd")
const Library = preload("res://scripts/photo_library.gd")
const STEREO_SHADER = preload("res://shaders/stereo.gdshader")
const Exporter = preload("res://scripts/stereo_export.gd")
const Gallery = preload("res://scripts/photo_gallery.gd")
const Importer = preload("res://scripts/photo_importer.gd")
const Loader = preload("res://scripts/photo_loader.gd")
const Layout = preload("res://scripts/stereo_layout.gd")
const RuntimeProbe = preload("res://scripts/runtime_image_probe.gd")
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
var gallery: Node3D
var importer: Node
var photo_loader: Node
var gallery_open := false
var gallery_stick_latched := false
var gallery_trigger_latched := false
var pending_photo_index := -1
var close_gallery_after_load := false
var decoder_summary := ""
var diagnostics: Array[Dictionary] = []
var diagnostic_timer := 0.0
var input_diagnostic_label: Label3D

func _ready() -> void:
 _build_scene()
 _initialize_xr()
 library.refresh()
 show_photo(0)
 recenter()
 _build_library_ui()
 _run_decoder_probe()
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
 help.text = "Left grip + Y: GALLERY / IMPORT   A: next   Left grip + A: previous\nX: 2D / stereo   Left grip + X: image layout   B: reset   Y: help\nRight stick: size / rotate   Left stick: pan\nLeft trigger + right stick: zoom / convergence   Right grip: grab\nLeft stick click: recenter   Right stick click: calibration\nRight/left trigger + right stick click: full/half SBS export\nBoth triggers + right stick click: PNG/JPG; + A: swap eyes"
 anchor.add_child(help)
 input_diagnostic_label = _label(20, 0.0012)
 help.add_child(input_diagnostic_label)
 input_diagnostic_label.position.y = -0.14
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

func _build_library_ui() -> void:
 gallery = Gallery.new()
 gallery.visible = false
 add_child(gallery)
 gallery.global_transform = anchor.global_transform
 gallery.set_entries(library.entries)
 gallery.photo_selected.connect(func(index: int): _navigate_photo(index, true))
 gallery.import_requested.connect(_request_import)
 gallery.refresh_requested.connect(_refresh_library)
 gallery.layout_requested.connect(func(): _cycle_layout(gallery.selected_entry_index()))
 gallery.diagnostic.connect(func(message: String): _record_diagnostic("gallery_failure", message))
 gallery.close_requested.connect(func(): _set_gallery_open(false))
 importer = Importer.new()
 add_child(importer)
 importer.progress.connect(_import_progress)
 importer.completed.connect(_import_completed)
 importer.cancelled.connect(func(): _notice("Import cancelled."))
 photo_loader = Loader.new()
 add_child(photo_loader)
 photo_loader.loaded.connect(_photo_loaded)

func _run_decoder_probe() -> void:
 var report: Dictionary = RuntimeProbe.run()
 report["engine"] = Engine.get_version_info().string
 report["platform"] = OS.get_name()
 report["xr_active"] = xr_active
 var file := FileAccess.open("user://runtime-image-report.json", FileAccess.WRITE)
 if file != null:
  file.store_string(JSON.stringify(report, "  "))
 # RuntimeProbe reports each codec independently; its embedded encoded bytes
 # exercise native decoders in the APK, without the editor's image importer.
 decoder_summary = "Decoders OK: JPEG / PNG / WebP / BMP" if report.get("all_ok", false) else "Image decoder failure: see runtime-image-report.json"
 print("Runtime image decoders: ", JSON.stringify(report))
 _update_labels()

func _set_gallery_open(value: bool) -> void:
 if gallery == null:
  return
 dragging = false
 gallery_open = value
 _record_diagnostic("gallery_open" if value else "gallery_closed")
 gallery_stick_latched = true
 gallery_trigger_latched = _trigger_held(right)
 gallery.visible = value
 anchor.visible = not value
 if value:
  recenter_gallery()
  gallery.set_entries(library.entries)
  gallery.select_index(current_index)
  gallery.set_status("Stick: choose · A/trigger: open · B: close · Layout: change selected photo")
 _update_labels()

func recenter_gallery() -> void:
 var forward := -camera.global_basis.z
 forward.y = 0.0
 if forward.length_squared() < 0.01:
  forward = Vector3.FORWARD
 gallery.global_position = camera.global_position + forward.normalized() * 2.4
 gallery.look_at(camera.global_position, Vector3.UP, true)

func _request_import() -> void:
 if importer.is_busy():
  return
 photo_loader.cancel()
 pending_photo_index = -1
 _set_gallery_open(true)
 var result: Error = importer.request_import(true)
 if result != OK:
  _notice(importer.error_message)

func _import_progress(message: String, fraction: float) -> void:
 _notice(message + ("  %d%%" % roundi(fraction * 100.0) if fraction > 0.0 else ""))

func _import_completed(imported: PackedStringArray, errors: PackedStringArray) -> void:
 _refresh_library()
 var message := "Imported %d photo(s)." % imported.size()
 if not errors.is_empty():
  message += " %d failed: %s" % [errors.size(), errors[0]]
  # Full errors remain available after an immersive dialog has closed.
  var file := FileAccess.open("user://last-import-errors.txt", FileAccess.WRITE)
  if file != null:
   file.store_string("\n".join(errors))
 if not imported.is_empty():
  for index in library.entries.size():
   if str(library.entries[index].path) == imported[0]:
    gallery.select_index(index)
    break
 _notice(message)

func _refresh_library() -> void:
 _save_view()
 photo_loader.cancel()
 pending_photo_index = -1
 var previous_path := str(current_entry.get("path", ""))
 library.refresh()
 for index in library.entries.size():
  if str(library.entries[index].path) == previous_path:
   current_index = index
   break
 if gallery != null:
  gallery.set_entries(library.entries)
 _notice("Library refreshed: %d images." % library.entries.size() if library.error_message.is_empty() else library.error_message)

func _cycle_layout(index: int) -> void:
 if index < 0 or index >= library.entries.size():
  return
 var entry: Dictionary = library.entries[index]
 var old: String = library.layout_for(entry)
 var next: String = Layout.VALUES[(Layout.VALUES.find(old) + 1) % Layout.VALUES.size()]
 var result: Error = library.set_layout(entry, next)
 if result != OK:
  _notice(library.error_message)
  return
 gallery.cache.invalidate(str(entry.path))
 gallery.set_entries(library.entries)
 if str(entry.path) == str(current_entry.get("path", "")):
  _navigate_photo(index)
 var names := {"mono": "2D", "sbs_full": "Full SBS", "sbs_half": "Half SBS", "ou_full": "Full top/bottom", "ou_half": "Half top/bottom"}
 _notice(str(entry.title) + " · Layout: " + str(names[next]))

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
 if gallery != null:
  gallery.global_transform = anchor.global_transform
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
 _display_photo(candidate_index, entry, texture)

func _display_photo(index: int, entry: Dictionary, texture: Texture2D) -> void:
 _save_view()
 current_index = index
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

func _navigate_photo(index: int, close_gallery: bool = false) -> void:
 if library.entries.is_empty():
  return
 var target := wrapi(index, 0, library.entries.size())
 var entry: Dictionary = library.entries[target]
 # Built-in resources are tiny and already imported. User photos decode off-thread
 # in VR, while the existing synchronous API remains usable for desktop/tests.
 if not xr_active or str(entry.path).begins_with("res://"):
  photo_loader.cancel()
  pending_photo_index = -1
  show_photo(target)
  if close_gallery and str(current_entry.get("path", "")) == str(entry.path):
   _set_gallery_open(false)
  return
 pending_photo_index = target
 close_gallery_after_load = close_gallery
 photo_loader.request(entry)
 _notice("Loading " + str(entry.title) + "…")

func _photo_loaded(_request_id: int, entry: Dictionary, image: Image, message: String) -> void:
 var target := pending_photo_index
 pending_photo_index = -1
 if target < 0:
  return
 current_index = target
 if image == null:
  _notice(str(entry.title) + ": " + message)
  return
 _display_photo(target, entry, ImageTexture.create_from_image(image))
 if close_gallery_after_load:
  _set_gallery_open(false)

func _navigation_index() -> int:
 return pending_photo_index if pending_photo_index >= 0 else current_index

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
 desktop_label.text = "QUEST PHOTO · desktop preview (%s eye)\n%s\n\nG: gallery   O: import   N/P: next/previous   M: image layout\nT: calibration   Space: 2D/stereo   W/S: size   Q/E: rotate\n+/-: zoom   Arrows: pan   I/J/K/L: position   U/D: distance\nR: reset   [/]: convergence   V: preview eye   F: swap eyes   H: help\nF5: refresh   F6/F7: full/half export   F8: PNG/JPG   Esc: quit\n\n%s" % ["left" if preview_eye == 0 else "right", status.text, decoder_summary]
 if gallery_open:
  desktop_label.text = "GALLERY · Arrows: select   Enter: open   G/Esc: return\nO: import   F5: refresh   M: selected image layout\n" + decoder_summary

func _process(delta: float) -> void:
 diagnostic_timer += delta
 if diagnostic_timer >= 0.5:
  diagnostic_timer = 0.0
  if input_diagnostic_label != null and help_visible:
   input_diagnostic_label.text = "Squeeze L %.2f / R %.2f · Tracked L %s / R %s" % [left.get_float("squeeze"), right.get_float("squeeze"), left.get_has_tracking_data(), right.get_has_tracking_data()]
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
 if importer != null and importer.is_busy():
  dragging = false
  return
 var l := _axis(left.get_vector2("thumbstick")) if left.get_has_tracking_data() else Vector2.ZERO
 var r := _axis(right.get_vector2("thumbstick")) if right.get_has_tracking_data() else Vector2.ZERO
 if gallery_open:
  dragging = false
  var axis := r if r.length() > l.length() else l
  if axis.length() < 0.25:
   gallery_stick_latched = false
  elif axis.length() > 0.65 and not gallery_stick_latched:
   gallery_stick_latched = true
   gallery.move_focus(Vector2(axis.x, -axis.y))
  var pressed := _trigger_held(right)
  if pressed and not gallery_trigger_latched:
   gallery.activate()
  gallery_trigger_latched = pressed
  return
 if l != Vector2.ZERO or r != Vector2.ZERO:
  state.pan += Vector2(l.x, -l.y) * delta * 0.3 / state.zoom
  if _trigger_held(left):
   state.zoom *= exp(r.y * delta)
   state.convergence += r.x * delta * 0.008
  else:
   state.panel_scale *= exp(r.y * delta * 0.5)
   state.roll -= r.x * delta * 0.6
  _changed()
 var gripping := right.get_has_tracking_data() and right.get_float("squeeze") > 0.65
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
 _record_diagnostic("left:" + str(action))
 if not session_focused:
  return
 if importer != null and importer.is_busy():
  return
 if action == "secondary" and _grip_held(left):
  _set_gallery_open(not gallery_open)
  return
 if gallery_open:
  if action == "thumbstick_click":
   recenter()
  return
 match action:
  "primary":
   if _grip_held(left):
    _cycle_layout(current_index)
    return
   state.stereo_enabled = not state.stereo_enabled
   _changed()
  "secondary":
   help_visible = not help_visible
   _update_labels()
  "thumbstick_click": recenter()

func _right_button(action: StringName) -> void:
 _record_diagnostic("right:" + str(action))
 if not session_focused:
  return
 if importer != null and importer.is_busy():
  if action == "secondary":
   importer.cancel_import()
  return
 if gallery_open:
  if action == "primary":
   gallery.activate()
  elif action == "secondary":
   _set_gallery_open(false)
  return
 match action:
  "primary":
   if _trigger_held(left) and _trigger_held(right):
    state.swap_eyes = not state.swap_eyes
    _changed()
   else:
    _navigate_photo(_navigation_index() + (-1 if _grip_held(left) else 1))
  "secondary": _reset_view()
  "thumbstick_click":
   if _trigger_held(left) and _trigger_held(right):
    _toggle_export_format()
   elif _trigger_held(right):
    _export_view(false)
   elif _trigger_held(left):
    _export_view(true)
   else:
    _navigate_photo(0)

func _grip_held(controller: XRController3D) -> bool:
 return controller.get_has_tracking_data() and controller.get_float("squeeze") > 0.65

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
 _record_diagnostic("notice", message)
 last_notice = message
 notice_until = Time.get_ticks_msec() + 6000
 if status != null:
  _update_labels()
 if gallery != null and gallery_open:
  gallery.set_status(message.left(150))

func _open_desktop_file(path: String) -> void:
 var entry := {"path": path, "title": path.get_file(), "sbs": path.get_basename().to_lower().ends_with(".sbs")}
 library.entries.append(entry)
 show_photo(library.entries.size() - 1)

func _unhandled_key_input(event: InputEvent) -> void:
 if not event is InputEventKey or not event.pressed or file_dialog.visible:
  return
 if importer != null and importer.is_busy():
  if event.keycode == KEY_ESCAPE:
   importer.cancel_import()
  return
 if event.keycode == KEY_G:
  _set_gallery_open(not gallery_open)
  return
 if gallery_open:
  match event.keycode:
   KEY_LEFT: gallery.move_focus(Vector2.LEFT)
   KEY_RIGHT: gallery.move_focus(Vector2.RIGHT)
   KEY_UP: gallery.move_focus(Vector2.UP)
   KEY_DOWN: gallery.move_focus(Vector2.DOWN)
   KEY_ENTER, KEY_KP_ENTER: gallery.activate()
   KEY_ESCAPE: _set_gallery_open(false)
   KEY_O: _request_import()
   KEY_F5: _refresh_library()
   KEY_M: _cycle_layout(gallery.selected_entry_index())
  return
 match event.keycode:
  KEY_ESCAPE:
   _save_view()
   get_tree().quit()
  KEY_O: _request_import()
  KEY_M: _cycle_layout(current_index)
  KEY_N: _navigate_photo(_navigation_index() + 1)
  KEY_P: _navigate_photo(_navigation_index() - 1)
  KEY_T: _navigate_photo(0)
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
  KEY_F5: _refresh_library()
  KEY_F6: _export_view(false)
  KEY_F7: _export_view(true)
  KEY_F8: _toggle_export_format()
  _: return
 _changed()

func _notification(what: int) -> void:
 if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
  _save_view()

func _input_snapshot(controller: XRController3D) -> Dictionary:
 var tracker := XRServer.get_tracker(controller.tracker) as XRControllerTracker
 return {"tracked": controller.get_has_tracking_data(), "squeeze": controller.get_float("squeeze"),
  "trigger": controller.get_float("trigger"), "squeeze_present": tracker != null and tracker.get_input("squeeze") != null,
  "profile": str(tracker.get_tracker_profile()) if tracker != null else "unavailable"}

func _record_diagnostic(event: String, message: String = "") -> void:
 if left == null or right == null:
  return
 var row := {"time_ms": Time.get_ticks_msec(), "event": event, "message": message.left(200),
  "left": _input_snapshot(left), "right": _input_snapshot(right),
  "focused": session_focused, "gallery_open": gallery_open,
  "import_busy": importer != null and importer.is_busy()}
 diagnostics.append(row)
 if diagnostics.size() > 100:
  diagnostics.pop_front()
 print("QuestPhoto diagnostic: ", JSON.stringify(row))
 var file := FileAccess.open("user://controller-gallery-diagnostics.json", FileAccess.WRITE)
 if file != null:
  file.store_string(JSON.stringify(diagnostics, "  "))
