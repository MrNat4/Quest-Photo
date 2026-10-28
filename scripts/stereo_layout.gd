class_name StereoLayout
extends RefCounted
## Layout normalization keeps shader/export inputs canonical: full SBS, left first.
const VALUES := ["mono", "sbs_full", "sbs_half", "ou_full", "ou_half"]
var error_message := ""

static func detect(filename: String) -> String:
 var stem := filename.get_file().get_basename().to_lower()
 if stem.ends_with(".half-sbs"):
  return "sbs_half"
 if stem.ends_with(".sbs"):
  return "sbs_full"
 if stem.ends_with(".half-ou"):
  return "ou_half"
 if stem.ends_with(".ou"):
  return "ou_full"
 return "mono"

func normalize(image: Image, layout: String, max_side: int = 4096) -> Image:
 error_message = ""
 if image == null or image.is_empty() or layout not in VALUES:
  error_message = "Invalid image or stereo layout."
  return null
 max_side = clampi(max_side,1,4096)
 var width := image.get_width()
 var height := image.get_height()
 var stereo := layout != "mono"
 var vertical := layout.begins_with("ou_")
 if stereo and ((vertical and height % 2 != 0) or (not vertical and width % 2 != 0)):
  error_message = "Over-under images require even height; SBS images require even width."
  return null
 var eye_size := Vector2i(width,height)
 if stereo:
  if vertical:
   eye_size.y /= 2
  else:
   eye_size.x /= 2
 var restored := Vector2(eye_size)
 if layout == "sbs_half":
  restored.x *= 2.0
 elif layout == "ou_half":
  restored.y *= 2.0
 var ratio := minf(1.0,minf(float(max_side)/restored.x,float(max_side)/restored.y))
 var output_eye := Vector2i(maxi(1,roundi(restored.x*ratio)),maxi(1,roundi(restored.y*ratio)))
 if (layout == "mono" or layout == "sbs_full") and output_eye == eye_size:
  return image
 # Max4096 each eye guarantees <=32Mi pixels in a canonical stereo pair.
 var result := Image.create(output_eye.x*(2 if stereo else 1),output_eye.y,false,image.get_format())
 for eye in (2 if stereo else 1):
  var origin := Vector2i(0,eye_size.y*eye) if vertical else Vector2i(eye_size.x*eye,0)
  var piece := image.get_region(Rect2i(origin,eye_size))
  if piece.get_size() != output_eye:
   piece.resize(output_eye.x,output_eye.y,Image.INTERPOLATE_LANCZOS)
  result.blit_rect(piece,Rect2i(Vector2i.ZERO,output_eye),Vector2i(eye*output_eye.x,0))
 return result
