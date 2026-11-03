extends Node3D
## Existing controller menu, paged to prevent settings/status text overlap.
signal action(command: String)
const COMMANDS := ["model", "quality", "convert", "original", "result", "cancel", "depth_slider", "plane_slider", "apply", "cache_usage", "cache_photo", "cache_all", "close"]
const LABELS := ["Model", "Quality", "Convert / show saved", "Original 2D", "Compare next saved model", "Cancel processing", "Depth", "Screen plane", "APPLY CHANGES", "Cache storage usage", "Clear Cached Results for Current Photo", "Clear All Cache", "Close"]
const RED := Color(1.0, 0.22, 0.22)
const PAGE_SIZE := 6
var focus := 0
var heading: Label3D
var rows: Label3D
var feedback: Label3D
var instructions: Label3D
var summary := ""
var message := ""
var message_red := false
var confirmation := ""
const Pending = preload("res://scripts/ai/pending_adjustments.gd")
var pending := Pending.new()
var hold_direction := 0
var hold_time := 0.0
var repeat_time := 0.0
var editing_allowed := true

func slider_selected() -> bool:
 return confirmation.is_empty() and COMMANDS[focus] in ["depth_slider", "plane_slider"]

func _bar(value: float) -> String:
 var filled := clampi(roundi(value * 16),0,16)
 return "[" + "━".repeat(filled) + "│" + "─".repeat(16-filled) + "]"

func nudge_slider(direction: int, magnetic: bool = false) -> void:
 if not slider_selected() or not editing_allowed: return
 pending.nudge(COMMANDS[focus] == "depth_slider", direction, magnetic)
 refresh()

func slider_input(axis: Vector2, delta: float) -> bool:
 if not slider_selected() or absf(axis.x) < 0.65 or absf(axis.x) <= absf(axis.y):
  hold_direction = 0; hold_time = 0; repeat_time = 0
  return false
 var direction := 1 if axis.x > 0 else -1
 if direction != hold_direction:
  hold_direction = direction; hold_time = 0; repeat_time = 0
  nudge_slider(direction)
 else:
  hold_time += delta
  if hold_time > 0.4:
   repeat_time += minf(delta,0.1)
   if repeat_time >= 0.075:
    repeat_time = 0
    nudge_slider(direction,true)
 return true

func _label(y: float, size: int) -> Label3D:
 var label := Label3D.new()
 label.font_size = size
 label.pixel_size = 0.0013
 label.modulate = Color.WHITE
 label.outline_size = 4
 label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
 label.position = Vector3(0,y,0.005)
 label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 label.width = 1750
 add_child(label)
 return label

func _ready() -> void:
 var mesh := MeshInstance3D.new()
 var quad := QuadMesh.new()
 quad.size = Vector2(2.5, 1.65)
 mesh.mesh = quad
 var material := StandardMaterial3D.new()
 material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 material.albedo_color = Color(0.025, 0.035, 0.055)
 mesh.material_override = material
 mesh.position.z = -0.01
 add_child(mesh)
 heading = _label(0.72,23)
 rows = _label(0.37,27)
 rows.line_spacing = 10
 feedback = _label(-0.22,24)
 instructions = _label(-0.64,22)
 refresh()

func refresh() -> void:
 if rows == null: return
 heading.text = summary if confirmation.is_empty() else confirmation
 heading.modulate = Color.WHITE
 rows.modulate = Color.WHITE
 var count := COMMANDS.size() if confirmation.is_empty() else 2
 focus = clampi(focus,0,count-1)
 var begin := (focus / PAGE_SIZE) * PAGE_SIZE
 var lines := PackedStringArray()
 for index in range(begin,mini(begin+PAGE_SIZE,count)):
  var label: String = LABELS[index] if confirmation.is_empty() else ["Cancel — keep cache", "Confirm deletion"][index]
  if confirmation.is_empty():
   if COMMANDS[index] == "depth_slider": label = "Depth %.2f%% → %.2f%% %s" % [pending.current_depth*100,pending.depth()*100,_bar(pending.depth()/0.04)]
   if COMMANDS[index] == "plane_slider": label = "Plane %.2f → %.2f %s" % [pending.current_plane,pending.plane(),_bar(pending.plane())]
   if COMMANDS[index] == "apply": label += " (pending)" if pending.changed() else " (unchanged)"
  lines.append(("▶ " if index == focus else "   ") + label)
 rows.text = "\n".join(lines)
 feedback.text = message.left(260) if confirmation.is_empty() else "Originals, exports, models and settings are kept."
 feedback.modulate = RED if message_red and confirmation.is_empty() else Color.WHITE
 instructions.text = "↑↓: select · ←→: slider · A/trigger: activate · B: close\nPage %d / %d" % [begin / PAGE_SIZE + 1, ceili(float(count)/PAGE_SIZE)]
 instructions.modulate = Color.WHITE

func move_focus(direction: Vector2) -> void:
 if slider_selected() and absf(direction.x) > absf(direction.y):
  nudge_slider(1 if direction.x > 0 else -1)
  return
 var count := COMMANDS.size() if confirmation.is_empty() else 2
 focus = wrapi(focus + (1 if direction.y > 0 or direction.x > 0 else -1),0,count)
 refresh()

func activate() -> void:
 if slider_selected(): return
 action.emit(COMMANDS[focus] if confirmation.is_empty() else ("cache_cancel" if focus == 0 else "cache_confirm"))
