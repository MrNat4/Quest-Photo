extends RefCounted
## CPU-only depth image based rendering. Call from a worker, with private inputs.
## Larger depth values mean NEARER. Convert distance to inverse distance upstream.
## Output is canonical full SBS (left eye first); x_left - x_right > 0 is near.
## Hidden surfaces cannot be recovered: disocclusions extend the visible background.

const BALANCED_MAX_SIDE := 1024
const HIGH_MAX_SIDE := 1536
const MAXIMUM_MAX_SIDE := 2048
const REVISION := "0.3.3-r1"
const MAX_INPUT_PIXELS := 32 * 1024 * 1024
const MAX_DISPARITY := 0.04
const DEPTH_LAYER_EPSILON := 0.015

static func reconstruct(source: Image, depth: Image, strength: float = 0.02,
  screen_plane: float = 0.5, quality: Variant = false,
  cancelled: Callable = Callable()) -> Image:
 if source == null or depth == null or source.is_empty() or depth.is_empty():
  return null
 if not is_finite(strength) or not is_finite(screen_plane):
  return null
 if source.get_width() * source.get_height() > MAX_INPUT_PIXELS or depth.get_width() * depth.get_height() > MAX_INPUT_PIXELS:
  return null
 if (cancelled.is_valid() and cancelled.call()) or source.is_compressed() or depth.is_compressed():
  return null
 var mode := quality_index(quality)
 var high_quality := mode > 0
 var picture: Image = source.duplicate()
 picture.convert(Image.FORMAT_RGB8)
 var max_side := max_side_for(mode)
 var ratio := minf(1.0, float(max_side) / maxi(picture.get_width(), picture.get_height()))
 var width := maxi(1, roundi(picture.get_width() * ratio))
 var height := maxi(1, roundi(picture.get_height() * ratio))
 if picture.get_size() != Vector2i(width, height):
  picture.resize(width, height, Image.INTERPOLATE_LANCZOS if high_quality else Image.INTERPOLATE_BILINEAR)
 var depth_copy: Image = depth.duplicate()
 depth_copy.convert(Image.FORMAT_RF)
 # Estimate robust limits before upsampling so the source distribution, rather
 # than upsampling artifacts, determines the disparity range.
 var raw := depth_copy.get_data().to_float32_array()
 var minimum := INF
 var maximum := -INF
 var samples := PackedFloat32Array()
 var stride := maxi(1, raw.size() / 65536)
 for i in raw.size():
  if i % 65536 == 0 and cancelled.is_valid() and cancelled.call():
   return null
  if not is_finite(raw[i]):
   return null
  if high_quality:
   minimum = minf(minimum, raw[i])
   maximum = maxf(maximum, raw[i])
  if i % stride == 0:
   samples.append(raw[i])
 samples.sort()
 var low := samples[int((samples.size() - 1) * 0.02)]
 var high := samples[int((samples.size() - 1) * 0.98)]
 # A tiny wire can occupy less than the trimmed 2%. Preserve it when the
 # robust range collapses, instead of flattening every pixel to screen plane.
 if high_quality and high <= low:
  low = minimum
  high = maximum
 depth_copy.resize(width, height, Image.INTERPOLATE_BILINEAR)
 var values := depth_copy.get_data().to_float32_array()
 var span := high - low
 for i in values.size():
  values[i] = clampf((values[i] - low) / span, 0.0, 1.0) if span > 0.0 else 0.5
 var input := picture.get_data()
 if high_quality and strength > 0.0 and span > 0.0:
  values = _guided_depth(picture, depth, low, span, cancelled)
  if values.is_empty():
   return null
  if mode == 2:
   values = _refine_cross(values, input, width, height, cancelled)
   if values.is_empty():
    return null
 if high_quality:
  return _surface_render(input, values, width, height, strength, screen_plane, mode, cancelled)
 var output := PackedByteArray()
 output.resize(width * height * 6)
 var separation := clampf(strength, 0.0, MAX_DISPARITY) * width
 var plane := clampf(screen_plane, 0.0, 1.0)
 # Row-local buffers bound memory and avoid allocating a full-resolution zbuffer
 # for both eyes. Input/output/depth are the only image-sized allocations.
 for y in height:
  if cancelled.is_valid() and cancelled.call():
   return null
  for eye in 2:
   var nearest := PackedFloat32Array()
   nearest.resize(width)
   nearest.fill(-1.0)
   var weights := PackedFloat32Array()
   weights.resize(width)
   var colors := PackedFloat32Array()
   colors.resize(width * 3)
   var sign_value := 0.5 if eye == 0 else -0.5
   for x in width:
    var near_value := values[y * width + x]
    var projected := x + (near_value - plane) * separation * sign_value
    var first := floori(projected) if high_quality else roundi(projected)
    var count := 2 if high_quality else 1
    for tap in count:
     var target := first + tap
     if target < 0 or target >= width:
      continue
     var weight := (1.0 - absf(projected - target)) if high_quality else 1.0
     if weight <= 0.00001:
      continue
     var difference := near_value - nearest[target]
     if difference < -DEPTH_LAYER_EPSILON:
      continue
     var out_offset := target * 3
     if difference > DEPTH_LAYER_EPSILON:
      weights[target] = 0.0
      colors[out_offset] = 0.0
      colors[out_offset + 1] = 0.0
      colors[out_offset + 2] = 0.0
     nearest[target] = maxf(nearest[target], near_value)
     weights[target] += weight
     var in_offset := (y * width + x) * 3
     for channel in 3:
      colors[out_offset + channel] += input[in_offset + channel] * weight
   for x in width:
    if weights[x] > 0.0:
     for channel in 3:
      colors[x * 3 + channel] /= weights[x]
   _fill_background_holes(colors, nearest, weights, width)
   var row_offset := (y * width * 2 + eye * width) * 3
   for i in width * 3:
    output[row_offset + i] = clampi(roundi(colors[i]), 0, 255)
 return Image.create_from_data(width * 2, height, false, Image.FORMAT_RGB8, output)

static func _fill_background_holes(colors: PackedFloat32Array, nearest: PackedFloat32Array,
  weights: PackedFloat32Array, width: int) -> void:
 var x := 0
 while x < width:
  if weights[x] > 0.0:
   x += 1
   continue
  var begin := x
  while x < width and weights[x] == 0.0:
   x += 1
  var left := begin - 1
  var right := x
  if left < 0 and right >= width:
   continue
  # Prefer the farther visible surface; interpolating foreground across a
  # disocclusion would create doubled silhouettes. Interpolate only within a
  # similar-depth surface. At outer borders extend the sole visible neighbour.
  var similar := left >= 0 and right < width and absf(nearest[left] - nearest[right]) < 0.04
  var chosen := right if left < 0 else left
  if right < width and left >= 0 and nearest[right] < nearest[left]:
   chosen = right
  for gap in range(begin, x):
   var fraction := float(gap - left) / (right - left) if similar else 0.0
   for channel in 3:
    colors[gap * 3 + channel] = lerpf(colors[left * 3 + channel], colors[right * 3 + channel], fraction) if similar else colors[chosen * 3 + channel]

static func quality_index(value: Variant) -> int:
 if value is bool:
  return 1 if value else 0 # Preserve existing callers and old regression fixtures.
 if value is String:
  return maxi(0, ["Balanced", "High Quality", "Maximum Quality"].find(value))
 return clampi(int(value), 0, 2)

static func max_side_for(mode: int) -> int:
 return [BALANCED_MAX_SIDE, HIGH_MAX_SIDE, MAXIMUM_MAX_SIDE][clampi(mode, 0, 2)]

static func _range_table(sigma: float) -> PackedFloat32Array:
 var table := PackedFloat32Array()
 table.resize(766)
 for i in table.size():
  table[i] = exp(-float(i * i) / (2.0 * sigma * sigma)) + 0.00001
 return table

## Joint bilateral upsampling: only existing depth samples contribute. RGB guides
## selection, never creates depth from texture/brightness. Immutable model depth.
static func _guided_depth(picture: Image, depth: Image, low: float, span: float,
  cancelled: Callable) -> PackedFloat32Array:
 var width := picture.get_width()
 var height := picture.get_height()
 var dw := depth.get_width()
 var dh := depth.get_height()
 var guide: Image = picture.duplicate()
 guide.resize(dw, dh, Image.INTERPOLATE_BILINEAR)
 var small := guide.get_data()
 var rgb := picture.get_data()
 var d: Image = depth.duplicate()
 d.convert(Image.FORMAT_RF)
 var raw := d.get_data().to_float32_array()
 var result := PackedFloat32Array()
 result.resize(width * height)
 var table := _range_table(65.0)
 # Cache horizontal coordinates; no per-pixel Vector/Array allocation.
 var x0 := PackedInt32Array()
 var x1 := PackedInt32Array()
 var fractions := PackedFloat32Array()
 x0.resize(width); x1.resize(width); fractions.resize(width)
 for x in width:
  var fx := clampf((x + 0.5) * dw / float(width) - 0.5, 0, dw - 1)
  x0[x] = floori(fx)
  x1[x] = mini(x0[x] + 1, dw - 1)
  fractions[x] = fx - x0[x]
 for y in height:
  if cancelled.is_valid() and cancelled.call():
   return PackedFloat32Array()
  var fy := clampf((y + 0.5) * dh / float(height) - 0.5, 0, dh - 1)
  var y0 := floori(fy)
  var y1 := mini(y0 + 1, dh - 1)
  var ty := fy - y0
  for x in width:
   var pixel := y * width + x
   var offset := pixel * 3
   var total := 0.0
   var sum_depth := 0.0
   for j in 2:
    var row := (y0 if j == 0 else y1) * dw
    var wy := 1.0 - ty if j == 0 else ty
    for i in 2:
     var index := row + (x0[x] if i == 0 else x1[x])
     var color := index * 3
     var difference := absi(int(rgb[offset]) - small[color]) + absi(int(rgb[offset + 1]) - small[color + 1]) + absi(int(rgb[offset + 2]) - small[color + 2])
     var weight := wy * (1.0 - fractions[x] if i == 0 else fractions[x]) * table[difference]
     total += weight
     sum_depth += raw[index] * weight
   result[pixel] = clampf((sum_depth / maxf(total, 0.00000001) - low) / span, 0, 1)
 return result

## Maximum-only cross bilateral pass. Gate both RGB and depth differences to
## suppress small within-surface noise without averaging distinct surfaces.
static func _refine_cross(values: PackedFloat32Array, rgb: PackedByteArray,
  width: int, height: int, cancelled: Callable) -> PackedFloat32Array:
 var result := values.duplicate()
 var table := _range_table(45.0)
 for y in height:
  if cancelled.is_valid() and cancelled.call():
   return PackedFloat32Array()
  for x in width:
   var p := y * width + x
   var c := p * 3
   var sum_depth := values[p] * 2.0
   var total := 2.0
   for direction in 4:
    var q := p
    match direction:
     0: q -= 1 if x > 0 else 0
     1: q += 1 if x < width - 1 else 0
     2: q -= width if y > 0 else 0
     3: q += width if y < height - 1 else 0
    var distance := absf(values[q] - values[p])
    if distance >= 0.06:
     continue
    var qc := q * 3
    var difference := absi(int(rgb[c]) - rgb[qc]) + absi(int(rgb[c + 1]) - rgb[qc + 1]) + absi(int(rgb[c + 2]) - rgb[qc + 2])
    var weight := table[difference] * (1.0 - distance / 0.06)
    sum_depth += values[q] * weight
    total += weight
   result[p] = sum_depth / total
 return result

## Rasterize projected pixel footprints. Continuous surfaces stretch/compress;
## discontinuities never connect across the missing background. Coverage is
## retained separately from visibility so a fractional foreground edge does not
## become a full opaque stair-step. All geometry remains horizontal/rectified.
static func _surface_render(rgb: PackedByteArray, values: PackedFloat32Array,
  width: int, height: int, strength: float, plane: float, mode: int,
  cancelled: Callable) -> Image:
 var output := PackedByteArray()
 output.resize(width * height * 6)
 var separation := clampf(strength, 0, MAX_DISPARITY) * width
 plane = clampf(plane, 0, 1)
 for y in height:
  if cancelled.is_valid() and cancelled.call():
   return null
  for eye in 2:
   var nearest := PackedFloat32Array()
   nearest.resize(width); nearest.fill(-1.0)
   var weights := PackedFloat32Array()
   weights.resize(width)
   var colors := PackedFloat32Array()
   colors.resize(width * 3)
   var back := PackedFloat32Array()
   back.resize(width * 3)
   var back_weights := PackedFloat32Array()
   back_weights.resize(width)
   var back_depth := PackedFloat32Array()
   back_depth.resize(width); back_depth.fill(-1.0)
   var sign_value := 0.5 if eye == 0 else -0.5
   var shift := separation * sign_value
   var row := y * width
   var footprints := PackedFloat32Array()
   footprints.resize(width * 3)
   for x in width:
    var d := values[row + x]
    var center := x + (d - plane) * shift
    var left := center - 0.5
    var right := center + 0.5
    if x > 0 and absf(d - values[row + x - 1]) < 0.06:
     var previous := x - 1 + (values[row + x - 1] - plane) * shift
     # Never connect a folded or highly magnified projected interval. Such
     # connections stretch contour colors or invert a thin object's footprint.
     if center > previous and center - previous <= 2.0:
      left = (center + previous) * 0.5
    if x + 1 < width and absf(d - values[row + x + 1]) < 0.06:
     var following := x + 1 + (values[row + x + 1] - plane) * shift
     if following > center and following - center <= 2.0:
      right = (center + following) * 0.5
    footprints[x * 3] = maxf(left, center - 2.0)
    footprints[x * 3 + 1] = minf(right, center + 2.0)
    footprints[x * 3 + 2] = center
   # Resolve immutable front and rear depth bands BEFORE accumulating color.
   # Incrementally resetting a z/color buffer made overlapping gradients depend
   # on left-to-right traversal, producing different artifacts in the two eyes.
   for phase in 3:
    for x in width:
     var d := values[row + x]
     var left := footprints[x * 3]
     var right := footprints[x * 3 + 1]
     var center := footprints[x * 3 + 2]
     if right <= left:
      continue
     for target in range(maxi(0, floori(left + 0.5)), mini(width - 1, ceili(right + 0.5) - 1) + 1):
      var weight := minf(right, target + 0.5) - maxf(left, target - 0.5)
      if weight <= 0.00001:
       continue
      if phase == 0:
       nearest[target] = maxf(nearest[target], d)
       continue
      if phase == 1:
       if d < nearest[target] - DEPTH_LAYER_EPSILON:
        back_depth[target] = maxf(back_depth[target], d)
       continue
      var front := d >= nearest[target] - DEPTH_LAYER_EPSILON
      if not front and d < back_depth[target] - DEPTH_LAYER_EPSILON:
       continue
      # Sample the covered source interval, not a stretched constant pixel.
      # Adjacent colors contribute only on the same continuous depth surface.
      var covered := (maxf(left, target - 0.5) + minf(right, target + 0.5)) * 0.5
      var side_width := center - left if covered < center else right - center
      var dx := clampf((covered - center) / maxf(2.0 * side_width, 0.00001), -0.5, 0.5)
      var neighbor := clampi(x + (-1 if dx < 0 else 1), 0, width - 1)
      var blend := absf(dx) if absf(values[row + neighbor] - d) < 0.06 else 0.0
      var source_c := (row + x) * 3
      var neighbor_c := (row + neighbor) * 3
      var c := target * 3
      if front:
       weights[target] += weight
       for channel in 3:
        colors[c + channel] += lerpf(rgb[source_c + channel], rgb[neighbor_c + channel], blend) * weight
      else:
       back_weights[target] += weight
       for channel in 3:
        back[c + channel] += lerpf(rgb[source_c + channel], rgb[neighbor_c + channel], blend) * weight
   for x in width:
    if weights[x] > 0.0:
     var inverse := 1.0 / weights[x]
     var c := x * 3
     colors[c] *= inverse
     colors[c + 1] *= inverse
     colors[c + 2] *= inverse
   # Fill only from the farther surface. Never mirror a hair/face texture.
   _fill_surface_holes(colors, nearest, weights, width, mode == 2)
   var offset := (y * width * 2 + eye * width) * 3
   for x in width:
    var c := x * 3
    var alpha := minf(1.0, weights[x])
    var donor := -1
    var donor_other := -1
    if alpha > 0.00001 and alpha < 0.999 and back_weights[x] <= 0.00001:
     # Only edge pixels need this search; bound to the disparity footprint.
     for radius in range(1, mini(width, ceili(absf(shift)) + 3)):
      var a := x - radius
      var b := x + radius
      if a >= 0 and weights[a] > 0 and nearest[a] < nearest[x] - 0.04:
       donor = a
      if b < width and weights[b] > 0 and nearest[b] < nearest[x] - 0.04:
       if donor >= 0 and is_equal_approx(nearest[b], nearest[donor]):
        donor_other = b
       elif donor < 0 or nearest[b] < nearest[donor]:
        donor = b
      if donor >= 0:
       break
    for channel in 3:
     var color := colors[c + channel]
     if alpha > 0.00001 and alpha < 0.999:
      if back_weights[x] > 0.00001:
       color = lerpf(back[c + channel] / back_weights[x], color, alpha)
      elif donor >= 0:
       var background := colors[donor * 3 + channel]
       if donor_other >= 0:
        background = (background + colors[donor_other * 3 + channel]) * 0.5
       color = lerpf(background, color, alpha)
     output[offset + c + channel] = clampi(roundi(color), 0, 255)
 return Image.create_from_data(width * 2, height, false, Image.FORMAT_RGB8, output)

static func _fill_surface_holes(colors: PackedFloat32Array, nearest: PackedFloat32Array,
  weights: PackedFloat32Array, width: int, texture_extension: bool) -> void:
 var x := 0
 while x < width:
  if weights[x] > 0.0:
   x += 1
   continue
  var begin := x
  while x < width and weights[x] == 0.0:
   x += 1
  var left := begin - 1
  var right := x
  if left < 0 and right >= width:
   continue
  var chosen := right if left < 0 else left
  if left >= 0 and right < width and nearest[right] < nearest[left]:
   chosen = right
  var similar := left >= 0 and right < width and absf(nearest[left] - nearest[right]) < 0.04
  var direction := -1 if chosen == left else 1
  for gap in range(begin, x):
   var interior := chosen + direction
   var gradient_ok := texture_extension and not similar and interior >= 0 and interior < width and weights[interior] > 0 and absf(nearest[interior] - nearest[chosen]) < 0.04
   for channel in 3:
    var value := colors[chosen * 3 + channel]
    if similar:
     value = lerpf(colors[left * 3 + channel], colors[right * 3 + channel], float(gap - left) / (right - left))
    elif gradient_ok:
     # Bounded background gradient; do not duplicate recognizable texture.
     var slope := clampf(value - colors[interior * 3 + channel], -3.0, 3.0)
     value = clampf(value + slope * mini(4, absi(gap - chosen)), 0, 255)
    colors[gap * 3 + channel] = value
