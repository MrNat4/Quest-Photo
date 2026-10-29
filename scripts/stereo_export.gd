class_name StereoExport
extends RefCounted
## Offline CPU SBS export; safe to call from a worker with a private Image copy.
## Mirrors shader zoom/pan/convergence and eye selection. Crop boundaries round
## independently to source pixels (at most 0.5 px each); a collapsed subpixel
## crop expands to one pixel. Physical panel scale/roll/position do not change
## image content and are intentionally excluded. No hidden-surface synthesis.

const MAX_EYE_SIDE := 2048
const MAX_INPUT_PIXELS := 32 * 1024 * 1024

static func export_sbs(image: Image, is_sbs: bool, view: Dictionary,
  half_sbs: bool, output_path: String) -> Error:
 if image == null or image.is_empty():
  return ERR_INVALID_PARAMETER
 var source_width := image.get_width()
 var source_height := image.get_height()
 if source_width * source_height > MAX_INPUT_PIXELS or (is_sbs and source_width % 2 != 0):
  return ERR_INVALID_PARAMETER
 var extension := output_path.get_extension().to_lower()
 if extension not in ["png", "jpg", "jpeg"]:
  return ERR_INVALID_PARAMETER
 var parent := output_path.get_base_dir()
 if not parent.is_empty() and not DirAccess.dir_exists_absolute(parent):
  return ERR_FILE_BAD_PATH
 var input := image
 if input.is_compressed():
  input = image.duplicate()
  var decompress_result := input.decompress()
  if decompress_result != OK:
   return decompress_result
 for key in ["zoom", "pan_x", "pan_y", "convergence"]:
  var value: Variant = view.get(key, 1.0 if key == "zoom" else 0.0)
  if not (value is float or value is int) or not is_finite(float(value)):
   return ERR_INVALID_PARAMETER
 for key in ["stereo_enabled", "swap_eyes"]:
  if view.has(key) and not view[key] is bool:
   return ERR_INVALID_PARAMETER
 var zoom := clampf(float(view.get("zoom", 1.0)), 1.0, 6.0)
 var margin := (1.0 - 1.0 / zoom) * 0.5
 var pan := Vector2(clampf(float(view.get("pan_x", 0.0)), -margin, margin),
  clampf(float(view.get("pan_y", 0.0)), -margin, margin))
 var convergence := clampf(float(view.get("convergence", 0.0)), -0.02, 0.02)
 var stereo := is_sbs and bool(view.get("stereo_enabled", true))
 var swap := bool(view.get("swap_eyes", false))
 var eye_width := source_width / 2 if is_sbs else source_width
 var ratio := minf(1.0, minf(float(MAX_EYE_SIDE) / eye_width, float(MAX_EYE_SIDE) / source_height))
 var width := maxi(1, roundi(eye_width * ratio))
 var height := maxi(1, roundi(source_height * ratio))
 # Half-SBS packs two equal horizontal halves; total width must be even.
 if half_sbs:
  width = maxi(2, width - width % 2)
 var destination_eye_width := width / 2 if half_sbs else width
 var output := Image.create(destination_eye_width * 2, height, false, Image.FORMAT_RGB8)
 output.fill(Color.BLACK)
 for display_eye in 2:
  var source_eye := 1 - display_eye if swap else display_eye
  if not stereo:
   source_eye = 0
  var source := input.get_region(Rect2i(source_eye * eye_width if is_sbs else 0,
    0, eye_width, source_height))
  source.convert(Image.FORMAT_RGB8)
  var shift := pan
  if stereo:
   shift.x += (-1.0 if source_eye == 0 else 1.0) * convergence
  var low := (Vector2.ONE * (0.5 - 0.5 / zoom) + shift) * Vector2(eye_width, source_height)
  var high := (Vector2.ONE * (0.5 + 0.5 / zoom) + shift) * Vector2(eye_width, source_height)
  var start := Vector2i(roundi(low.x), roundi(low.y))
  var finish := Vector2i(roundi(high.x), roundi(high.y))
  var crop_size := Vector2i(maxi(1, finish.x - start.x), maxi(1, finish.y - start.y))
  var crop_rect := Rect2i(start, crop_size)
  var valid_rect := crop_rect.intersection(Rect2i(0, 0, eye_width, source_height))
  var cropped := Image.create(crop_size.x, crop_size.y, false, Image.FORMAT_RGB8)
  cropped.fill(Color.BLACK)
  if valid_rect.has_area():
   cropped.blit_rect(source, valid_rect, valid_rect.position - start)
  # Eyes are resized independently, preventing filtering across the SBS seam.
  cropped.resize(destination_eye_width, height, Image.INTERPOLATE_BILINEAR)
  output.blit_rect(cropped, Rect2i(0, 0, destination_eye_width, height),
   Vector2i(display_eye * destination_eye_width, 0))
 if extension == "png":
  return output.save_png(output_path)
 return output.save_jpg(output_path, 0.95)
