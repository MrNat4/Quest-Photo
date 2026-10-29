class_name PhotoGallery
extends Node3D
## Controller-first 3×2 gallery. Parent owns placement, visibility, and input repeat.
## move_focus uses discrete axes, with positive Y moving down. Toolbar focus keeps
## the last highlighted photograph available to Layout via selected_entry_index().

signal photo_selected(index: int)
signal import_requested
signal refresh_requested
signal layout_requested
signal diagnostic(message: String)
signal close_requested
const Cache = preload("res://scripts/thumbnail_cache.gd")
const PAGE_SIZE := 6
const BUTTONS := ["Import", "Refresh", "Layout", "Previous", "Next", "Close"]
var entries: Array[Dictionary] = []
var page_index := 0
var focus_index := 0
var selected_index := -1
var cache: Node
var _last_photo_index := -1
var _cells: Array[Dictionary] = []
var _buttons: Array[Dictionary] = []
var _keys: Array[String] = []
var _heading: Label3D
var _status: Label3D
var _status_text := "Thumbstick: choose   A / trigger: open   B: close"

func _ready() -> void:
 cache = Cache.new()
 add_child(cache)
 cache.texture_ready.connect(_thumbnail_ready)
 _build()
 visibility_changed.connect(_visibility_changed)
 _render_page()

func _quad(size: Vector2, color: Color, position_value: Vector3) -> MeshInstance3D:
 var mesh := MeshInstance3D.new()
 var quad := QuadMesh.new()
 quad.size = size
 mesh.mesh = quad
 var material := StandardMaterial3D.new()
 material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 material.cull_mode = BaseMaterial3D.CULL_DISABLED
 material.albedo_color = color
 mesh.material_override = material
 mesh.position = position_value
 add_child(mesh)
 return mesh

func _label(value: String, font_size: int, position_value: Vector3) -> Label3D:
 var label := Label3D.new()
 label.text = value
 label.font_size = font_size
 label.pixel_size = 0.0011
 label.outline_size = 3
 label.position = position_value
 add_child(label)
 return label

func _build() -> void:
 _quad(Vector2(2.22, 1.78), Color(0.025, 0.035, 0.055), Vector3(0, -0.04, -0.025))
 _heading = _label("Photos", 35, Vector3(0, 0.72, 0.006))
 _status = _label(_status_text, 20, Vector3(0, -0.84, 0.006))
 _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 _status.width = 1850.0
 for slot in PAGE_SIZE:
  var x := float(slot % 3 - 1) * 0.71
  var y := 0.37 - float(slot / 3) * 0.49
  var border := _quad(Vector2(0.67, 0.45), Color(0.16, 0.22, 0.3), Vector3(x, y, -0.005))
  _quad(Vector2(0.655, 0.435), Color(0.055, 0.075, 0.10), Vector3(x, y, -0.002))
  var image := _quad(Vector2(0.60, 0.32), Color.WHITE, Vector3(x, y + 0.04, 0.001))
  image.visible = false
  var label := _label("", 21, Vector3(x, y - 0.175, 0.006))
  var placeholder := _label("", 24, Vector3(x, y + 0.04, 0.006))
  _cells.append({"border": border, "image": image, "label": label, "placeholder": placeholder})
 for index in BUTTONS.size():
  var x := float(index % 3 - 1) * 0.71
  var y := -0.49 - float(index / 3) * 0.18
  var border := _quad(Vector2(0.67, 0.145), Color(0.16, 0.22, 0.3), Vector3(x, y, -0.005))
  _quad(Vector2(0.655, 0.13), Color(0.07, 0.10, 0.14), Vector3(x, y, -0.002))
  var label := _label(BUTTONS[index], 24, Vector3(x, y, 0.006))
  _buttons.append({"border": border, "label": label})

func page_count() -> int:
 return maxi(1, ceili(float(entries.size()) / PAGE_SIZE))

func set_entries(value: Array[Dictionary]) -> void:
 var selected_path := str(entries[selected_index].get("path", "")) if selected_index >= 0 and selected_index < entries.size() else ""
 var focus_path := str(entries[_last_photo_index].get("path", "")) if _last_photo_index >= 0 and _last_photo_index < entries.size() else ""
 entries = value.duplicate(true)
 selected_index = _find_path(selected_path)
 _last_photo_index = _find_path(focus_path)
 if _last_photo_index >= 0:
  page_index = _last_photo_index / PAGE_SIZE
  if focus_index < PAGE_SIZE:
   focus_index = _last_photo_index % PAGE_SIZE
 else:
  page_index = clampi(page_index, 0, page_count() - 1)
  focus_index = _first_valid_focus(focus_index)
  if focus_index < PAGE_SIZE:
   _last_photo_index = page_index * PAGE_SIZE + focus_index
 _render_page()

func _find_path(path: String) -> int:
 if path.is_empty():
  return -1
 for index in entries.size():
  if str(entries[index].get("path", "")) == path:
   return index
 return -1

func select_index(index: int) -> void:
 if index < 0 or index >= entries.size():
  return
 selected_index = index
 _last_photo_index = index
 page_index = index / PAGE_SIZE
 focus_index = index % PAGE_SIZE
 _render_page()

func selected_entry_index() -> int:
 return _last_photo_index

func set_status(value: String) -> void:
 _status_text = value
 if _status != null:
  _status.text = value

func _first_valid_focus(preferred: int) -> int:
 if preferred >= PAGE_SIZE:
  return clampi(preferred, PAGE_SIZE, PAGE_SIZE + BUTTONS.size() - 1)
 var page_items := mini(PAGE_SIZE, entries.size() - page_index * PAGE_SIZE)
 return clampi(preferred, 0, page_items - 1) if page_items > 0 else PAGE_SIZE

func move_focus(direction: Vector2) -> void:
 if direction == Vector2.ZERO:
  return
 var step := 0
 if absf(direction.x) > absf(direction.y):
  step = 1 if direction.x > 0 else -1
 else:
  step = 3 if direction.y > 0 else -3
 var candidate := clampi(focus_index + step, 0, 11)
 # Skip empty slots on the last page while keeping all actions reachable.
 while candidate < PAGE_SIZE and page_index * PAGE_SIZE + candidate >= entries.size():
  candidate += 1 if step > 0 else -1
  if candidate < 0:
   candidate = PAGE_SIZE
   break
 focus_index = candidate
 if focus_index < PAGE_SIZE:
  _last_photo_index = page_index * PAGE_SIZE + focus_index
 _update_focus()

func activate() -> void:
 if focus_index < PAGE_SIZE:
  var index := page_index * PAGE_SIZE + focus_index
  if index < entries.size():
   selected_index = index
   _last_photo_index = index
   _update_focus()
   photo_selected.emit(index)
  return
 match focus_index - PAGE_SIZE:
  0: import_requested.emit()
  1: refresh_requested.emit()
  2: layout_requested.emit()
  3: _change_page(-1)
  4: _change_page(1)
  5: close_requested.emit()

func _change_page(step: int) -> void:
 var next := clampi(page_index + step, 0, page_count() - 1)
 if next == page_index:
  return
 page_index = next
 _last_photo_index = page_index * PAGE_SIZE
 _render_page()

func _render_page() -> void:
 if _cells.is_empty():
  return
 cache.cancel_pending()
 _keys.clear()
 _heading.text = "Photos   %d–%d of %d   ·   Page %d / %d" % [page_index * PAGE_SIZE + 1 if not entries.is_empty() else 0, mini((page_index + 1) * PAGE_SIZE, entries.size()), entries.size(), page_index + 1, page_count()]
 for slot in PAGE_SIZE:
  var cell: Dictionary = _cells[slot]
  var index := page_index * PAGE_SIZE + slot
  cell.image.visible = false
  (cell.image.material_override as StandardMaterial3D).albedo_texture = null
  if index >= entries.size():
   cell.label.text = ""
   cell.placeholder.text = ""
   _keys.append("")
   continue
  var entry := entries[index]
  var title := str(entry.get("title", str(entry.get("path", "Photo")).get_file()))
  cell.label.text = title if title.length() <= 28 else title.left(25) + "…"
  cell.placeholder.text = "Loading…" if is_visible_in_tree() else ""
  _keys.append(cache.key_for(entry))
 _update_focus()
 if is_visible_in_tree():
  _request_page()

func _request_page() -> void:
 for slot in PAGE_SIZE:
  var index := page_index * PAGE_SIZE + slot
  if index < entries.size():
   cache.request(entries[index])

func _thumbnail_ready(key: String, texture: Texture2D, error: String) -> void:
 if texture == null:
  diagnostic.emit("Thumbnail " + key.left(12) + ": " + error)
 # A worker from the previous page may complete after a page turn.
 for slot in _keys.size():
  if _keys[slot] != key:
   continue
  var cell: Dictionary = _cells[slot]
  cell.placeholder.text = "Unavailable" if texture == null else ""
  cell.image.visible = texture != null
  if texture != null:
   var aspect := float(texture.get_width()) / texture.get_height()
   var width := minf(0.60, 0.32 * aspect)
   (cell.image.mesh as QuadMesh).size = Vector2(width, width / aspect)
   (cell.image.material_override as StandardMaterial3D).albedo_texture = texture
  elif not error.is_empty():
   cell.label.text = str(cell.label.text) + " · !"

func _update_focus() -> void:
 for slot in _cells.size():
  var color := Color(0.16, 0.22, 0.3)
  if page_index * PAGE_SIZE + slot == selected_index:
   color = Color(0.15, 0.75, 0.85)
  if slot == focus_index:
   color = Color(1.0, 0.72, 0.24)
  (_cells[slot].border.material_override as StandardMaterial3D).albedo_color = color
 for index in _buttons.size():
  (_buttons[index].border.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.72, 0.24) if index + PAGE_SIZE == focus_index else Color(0.16, 0.22, 0.3)

func _visibility_changed() -> void:
 if cache == null:
  return
 if is_visible_in_tree():
  _render_page()
 else:
  cache.cancel_pending()
