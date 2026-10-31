extends RefCounted
## Transaction coordinator. Backend is injectable for failure/protection tests.
const AndroidStore = preload("res://scripts/android_media_store.gd")
const CHUNK_BYTES := 256 * 1024

static func publish(path: String, backend: RefCounted = null) -> Dictionary:
 var extension := path.get_extension().to_lower()
 if extension not in ["png", "jpg", "jpeg"]:
  return {"error": "Shared export only accepts PNG/JPEG."}
 var file := FileAccess.open(path, FileAccess.READ)
 if file == null or file.get_length() == 0:
  return {"error": "Cannot read the finished export."}
 var bridge: RefCounted = AndroidStore.new() if backend == null else backend
 # UUID-sized randomness plus timestamp; MediaStore additionally allocates a
 # unique filename if any collision exists. Source name is never a destination.
 var token := Crypto.new().generate_random_bytes(16).hex_encode()
 var layout := path.get_basename().get_extension()
 var marker := "." + layout if layout in ["sbs", "half-sbs"] else ""
 var name := "ZDim_%d_%s%s.%s" % [int(Time.get_unix_time_from_system()), token, marker, extension]
 var mime := "image/png" if extension == "png" else "image/jpeg"
 if not bridge.begin(name, mime):
  bridge.abort()
  return {"error": "Pictures/Z-Dim export failed: " + str(bridge.error)}
 while file.get_position() < file.get_length():
  var bytes := file.get_buffer(mini(CHUNK_BYTES, file.get_length() - file.get_position()))
  if bytes.is_empty() or not bridge.write(bytes):
   bridge.abort()
   return {"error": "Pictures/Z-Dim write failed: " + str(bridge.error)}
 file.close()
 var uri: String = bridge.publish()
 if uri.is_empty():
  bridge.abort()
  return {"error": "Pictures/Z-Dim publish failed: " + str(bridge.error)}
 return {"uri": uri, "destination": "Pictures/Z-Dim/" + name}
