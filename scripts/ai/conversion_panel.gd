extends Node3D
## Existing controller menu, paged to prevent settings/status text overlap.
signal action(command: String)
const COMMANDS := ["model", "quality", "convert", "original", "result", "less", "more", "plane_less", "plane_more", "cancel", "cache_usage", "cache_photo", "cache_all", "close"]
const LABELS := ["Model", "Quality", "Convert / show saved", "Original 2D", "Compare next saved model", "Less depth", "More depth", "Screen plane −", "Screen plane +", "Cancel processing", "Cache storage usage", "Clear Cached Results for Current Photo", "Clear All Cache", "Close"]
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
  lines.append(("▶ " if index == focus else "   ") + label)
 rows.text = "\n".join(lines)
 feedback.text = message.left(260) if confirmation.is_empty() else "Originals, exports, models and settings are kept."
 feedback.modulate = RED if message_red and confirmation.is_empty() else Color.WHITE
 instructions.text = "Stick: select · A/trigger: activate · B: close\nPage %d / %d" % [begin / PAGE_SIZE + 1, ceili(float(count)/PAGE_SIZE)]
 instructions.modulate = Color.WHITE

func move_focus(direction: Vector2) -> void:
 var count := COMMANDS.size() if confirmation.is_empty() else 2
 focus = wrapi(focus + (1 if direction.y > 0 or direction.x > 0 else -1),0,count)
 refresh()

func activate() -> void:
 action.emit(COMMANDS[focus] if confirmation.is_empty() else ("cache_cancel" if focus == 0 else "cache_confirm"))
