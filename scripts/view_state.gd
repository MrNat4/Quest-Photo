class_name PhotoViewState
extends RefCounted

var zoom: float = 1.0
var pan: Vector2 = Vector2.ZERO
var panel_scale: float = 1.0
var roll: float = 0.0
var convergence: float = 0.0
var stereo_enabled: bool = true
var swap_eyes: bool = false

func constrain() -> void:
 zoom = clampf(zoom, 1.0, 6.0)
 var margin := (1.0 - 1.0 / zoom) * 0.5
 pan = pan.clamp(Vector2(-margin, -margin), Vector2(margin, margin))
 panel_scale = clampf(panel_scale, 0.25, 2.5)
 roll = wrapf(roll, -PI, PI)
 convergence = clampf(convergence, -0.02, 0.02)

func to_dictionary() -> Dictionary:
 constrain()
 return {"version": 1, "zoom": zoom, "pan_x": pan.x, "pan_y": pan.y,
  "panel_scale": panel_scale, "roll": roll, "convergence": convergence,
  "stereo_enabled": stereo_enabled, "swap_eyes": swap_eyes}

func from_dictionary(data: Dictionary) -> bool:
 if data.get("version") != 1:
  return false
 for key in ["zoom", "pan_x", "pan_y", "panel_scale", "roll", "convergence"]:
  var value: Variant = data.get(key)
  if not (value is float or value is int) or not is_finite(float(value)):
   return false
 for key in ["stereo_enabled", "swap_eyes"]:
  if not data.get(key) is bool:
   return false
 zoom = float(data.zoom)
 pan = Vector2(float(data.pan_x), float(data.pan_y))
 panel_scale = float(data.panel_scale)
 roll = float(data.roll)
 convergence = float(data.convergence)
 stereo_enabled = data.stereo_enabled
 swap_eyes = data.swap_eyes
 constrain()
 return true

func save_to(path: String) -> Error:
 var config := ConfigFile.new()
 config.set_value("view", "state", to_dictionary())
 return config.save(path)

func load_from(path: String) -> bool:
 var config := ConfigFile.new()
 if config.load(path) != OK:
  return false
 var value: Variant = config.get_value("view", "state")
 return value is Dictionary and from_dictionary(value)
