extends RefCounted
## Display-only normalization; never writes raw QPD or changes reconstruction.
static func render(raw: Image, inverse_depth: bool) -> Image:
 if raw == null or raw.is_empty(): return null
 var copy: Image = raw.duplicate()
 copy.convert(Image.FORMAT_RF)
 var scale := minf(1.0,512.0/maxi(copy.get_width(),copy.get_height()))
 if scale < 1: copy.resize(maxi(1,roundi(copy.get_width()*scale)),maxi(1,roundi(copy.get_height()*scale)),Image.INTERPOLATE_BILINEAR)
 var values := copy.get_data().to_float32_array()
 for i in values.size():
  if not is_finite(values[i]): return null
  if not inverse_depth: values[i]=1.0/maxf(values[i],0.000001)
 var sorted := values.duplicate();sorted.sort()
 var low := sorted[int((sorted.size()-1)*0.02)]
 var high := sorted[int((sorted.size()-1)*0.98)]
 if high <= low: low=sorted[0];high=sorted[-1]
 var pixels := PackedByteArray();pixels.resize(values.size())
 for i in values.size():
  pixels[i]=roundi(clampf((values[i]-low)/(high-low),0,1)*255) if high>low else 128
 return Image.create_from_data(copy.get_width(),copy.get_height(),false,Image.FORMAT_L8,pixels)
