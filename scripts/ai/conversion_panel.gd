extends Node3D
## Small controller-driven text menu; leaves existing gallery and viewer intact.
signal action(command: String)
const COMMANDS := ["model", "quality", "convert", "original", "result", "less", "more", "plane_less", "plane_more", "cancel", "close"]
const LABELS := ["Model", "Quality", "Convert / show saved", "Original 2D", "Compare next saved model", "Less depth", "More depth", "Screen plane −", "Screen plane +", "Cancel processing", "Close"]
var focus := 0
var heading: Label3D
var rows: Label3D
var summary := ""

func _ready() -> void:
 var mesh := MeshInstance3D.new()
 var quad := QuadMesh.new()
 quad.size = Vector2(2.25, 1.55)
 mesh.mesh = quad
 var material := StandardMaterial3D.new()
 material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 material.albedo_color = Color(0.025, 0.035, 0.055)
 mesh.material_override = material
 mesh.position.z = -0.01
 add_child(mesh)
 heading = Label3D.new()
 heading.font_size = 24
 heading.pixel_size = 0.0013
 heading.position.y = 0.56
 add_child(heading)
 rows = Label3D.new()
 rows.font_size = 25
 rows.pixel_size = 0.0013
 rows.position.y = -0.12
 add_child(rows)
 refresh()

func refresh() -> void:
 if rows == null:
  return
 heading.text = summary + "\nStick: select · A/trigger: activate · B: close"
 var lines := PackedStringArray()
 for index in COMMANDS.size():
  lines.append(("▶ " if index == focus else "   ") + LABELS[index])
 rows.text = "\n".join(lines)

func move_focus(direction: Vector2) -> void:
 focus = wrapi(focus + (1 if direction.y > 0 or direction.x > 0 else -1), 0, COMMANDS.size())
 refresh()

func activate() -> void:
 action.emit(COMMANDS[focus])
