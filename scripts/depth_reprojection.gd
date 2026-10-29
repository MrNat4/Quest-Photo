class_name DepthReprojection
extends RefCounted
## CPU-only depth image based rendering. Call from a worker, with private inputs.
## Larger depth values mean NEARER. Convert distance to inverse distance upstream.
## Output is canonical full SBS (left eye first); x_left - x_right > 0 is near.
## Hidden surfaces cannot be recovered: disocclusions extend the visible background.

const BALANCED_MAX_SIDE := 1024
const HIGH_MAX_SIDE := 1536
const MAX_INPUT_PIXELS := 32 * 1024 * 1024
const MAX_DISPARITY := 0.04
const DEPTH_LAYER_EPSILON := 0.015

static func reconstruct(source: Image, depth: Image, strength: float = 0.02,
  screen_plane: float = 0.5, high_quality: bool = false,
  cancelled: Callable = Callable()) -> Image:
 if source == null or depth == null or source.is_empty() or depth.is_empty():
  return null
 if not is_finite(strength) or not is_finite(screen_plane):
  return null
 if source.get_width() * source.get_height() > MAX_INPUT_PIXELS or depth.get_width() * depth.get_height() > MAX_INPUT_PIXELS:
  return null
 if (cancelled.is_valid() and cancelled.call()) or source.is_compressed() or depth.is_compressed():
  return null
 var picture: Image = source.duplicate()
 picture.convert(Image.FORMAT_RGB8)
 var max_side := HIGH_MAX_SIDE if high_quality else BALANCED_MAX_SIDE
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
 var samples := PackedFloat32Array()
 var stride := maxi(1, raw.size() / 65536)
 for i in raw.size():
  if i % 65536 == 0 and cancelled.is_valid() and cancelled.call():
   return null
  if not is_finite(raw[i]):
   return null
  if i % stride == 0:
   samples.append(raw[i])
 samples.sort()
 var low := samples[int((samples.size() - 1) * 0.02)]
 var high := samples[int((samples.size() - 1) * 0.98)]
 depth_copy.resize(width, height, Image.INTERPOLATE_BILINEAR)
 var values := depth_copy.get_data().to_float32_array()
 var span := high - low
 for i in values.size():
  values[i] = clampf((values[i] - low) / span, 0.0, 1.0) if span > 0.0 else 0.5
 var input := picture.get_data()
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
