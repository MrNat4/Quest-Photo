extends RefCounted
## Integer ticks avoid floating point drift. A tap is always an exact fine step;
## held motion adds a small magnetic zone, with hysteresis to prevent jitter.
var depth_ticks := 40
var plane_ticks := 50
var depth_raw := 40
var plane_raw := 50
var depth_snap := -1
var plane_snap := -1
var current_depth := 0.02
var current_plane := 0.5
var context := ""

func sync(key: String, depth: float, plane: float, force: bool = false) -> void:
 if not force and context == key: return
 context = key
 current_depth = depth
 current_plane = plane
 depth_ticks = clampi(roundi(depth / 0.0005),0,80)
 plane_ticks = clampi(roundi(plane / 0.01),0,100)
 depth_raw = depth_ticks; plane_raw = plane_ticks
 depth_snap = -1; plane_snap = -1

func depth() -> float: return depth_ticks * 0.0005
func plane() -> float: return plane_ticks * 0.01
func changed() -> bool:
 return not is_equal_approx(depth(),current_depth) or not is_equal_approx(plane(),current_plane)

func nudge(is_depth: bool, direction: int, magnetic: bool = false) -> void:
 var raw := depth_raw if is_depth else plane_raw
 var selected := depth_ticks if is_depth else plane_ticks
 var snap := depth_snap if is_depth else plane_snap
 var interval := 20 if is_depth else 5
 var limit := 80 if is_depth else 100
 if not magnetic: raw = selected # A released/tapped stick gives precise control.
 raw = clampi(raw + direction,0,limit)
 if magnetic:
  if snap >= 0 and absi(raw - snap) > 2: snap = -1
  var nearest := roundi(float(raw) / interval) * interval
  if snap < 0 and absi(raw - nearest) <= 1: snap = nearest
  selected = snap if snap >= 0 else raw
 else:
  snap = -1
  selected = raw
 if is_depth:
  depth_raw = raw; depth_ticks = selected; depth_snap = snap
 else:
  plane_raw = raw; plane_ticks = selected; plane_snap = snap
