extends RefCounted
## Only known generated files under fixed app-private cache roots are eligible.
## Never recurse or follow links. Preview/depth settings are migrated, not lost.
const Store = preload("res://scripts/ai/conversion_store.gd")
const THUMBS := "user://thumbnails"
const WORK := "user://ai-work"

static func _linked(path: String) -> bool:
 var parent := DirAccess.open(path.get_base_dir())
 return parent != null and parent.is_link(path.get_file())

static func _match(pattern: String, text: String) -> bool:
 var regex := RegEx.new()
 regex.compile(pattern)
 return regex.search(text) != null

static func _category(name: String) -> String:
 if name == "raw.qpd": return "depth"
 if name == "record.json": return "metadata"
 if name == "adjustments.cfg": return "settings"
 if _match("^preview(-[0-9.]+-[0-2])?\\.(png|json)(\\.pending)?$", name): return "images"
 return ""

static func inventory(source_hash: String = "") -> Dictionary:
 var result := {"depth":0, "images":0, "thumbnails":0, "temporary":0, "metadata":0, "total":0, "records":[], "loose":[], "skipped":0}
 if DirAccess.dir_exists_absolute(Store.ROOT) and not _linked(Store.ROOT):
  for key in DirAccess.get_directories_at(Store.ROOT):
   var base := key.trim_suffix(".pending")
   if not Store.valid_key(base): continue
   var dir := Store.ROOT.path_join(key)
   if _linked(dir) or not DirAccess.get_directories_at(dir).is_empty():
    result.skipped += 1
    continue
   if not source_hash.is_empty():
    var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("record.json"))) if FileAccess.file_exists(dir.path_join("record.json")) else null
    if not data is Dictionary or data.get("source_sha256") != source_hash: continue
   var files: Array[String] = []
   var safe := true
   for name in DirAccess.get_files_at(dir):
    if _category(name).is_empty() or _linked(dir.path_join(name)): safe = false
    files.append(name)
   if not safe:
    result.skipped += 1
    continue
   result.records.append({"key":base,"dir":dir,"files":files})
   for name in files:
    var category := _category(name)
    if category == "settings": continue
    var f := FileAccess.open(dir.path_join(name),FileAccess.READ)
    if f != null: result[category] += f.get_length()
 # Current-photo results are content-addressed; thumbnails are path-addressed.
 # Leave thumbnails alone for current-photo clearing (all-cache handles them).
 if source_hash.is_empty() and DirAccess.dir_exists_absolute(THUMBS) and not _linked(THUMBS):
  for name in DirAccess.get_files_at(THUMBS):
   var path := THUMBS.path_join(name)
   if _match("^[0-9a-f]{64}_[0-9a-f]{64}\\.png$", name) and not _linked(path):
    var f := FileAccess.open(path,FileAccess.READ)
    if f != null:
     result.thumbnails += f.get_length()
     result.loose.append(path)
 if source_hash.is_empty() and DirAccess.dir_exists_absolute(WORK) and not _linked(WORK):
  for key in DirAccess.get_directories_at(WORK):
   if not _match("^[0-9a-f]{64}-[0-9]+$",key): continue
   var dir := WORK.path_join(key)
   if _linked(dir) or not DirAccess.get_directories_at(dir).is_empty(): continue
   var names := DirAccess.get_files_at(dir)
   var safe := true
   for name in names:
    if name not in ["input.png","raw.qpd"] or _linked(dir.path_join(name)): safe = false
   if not safe: continue
   result.records.append({"key":"","dir":dir,"files":Array(names)})
   for name in names:
    var f := FileAccess.open(dir.path_join(name),FileAccess.READ)
    if f != null: result.temporary += f.get_length()
 for key in ["depth","images","thumbnails","temporary","metadata"]: result.total += result[key]
 return result

static func clear(source_hash: String, confirmed: bool) -> Dictionary:
 if not confirmed: return {"error":"Cache deletion needs confirmation."}
 if not source_hash.is_empty() and not Store.valid_key(source_hash): return {"error":"Invalid photo identity; no cache deleted."}
 # Re-inventory at confirmation; never trust paths supplied by the UI.
 var plan := inventory(source_hash)
 var deleted := 0
 var errors: Array[String] = []
 for record: Dictionary in plan.records:
  if not record.key.is_empty() and "adjustments.cfg" in record.files:
   var err := Store.preserve_adjustments(record.key, record.dir.path_join("adjustments.cfg"))
   if err != OK:
    errors.append("Cannot preserve depth settings: " + error_string(err))
    continue
  for name: String in record.files:
   var path: String = record.dir.path_join(name)
   if _linked(path):
    errors.append("Cache link refused.")
    continue
   var err := DirAccess.remove_absolute(path)
   if err == OK: deleted += 1
   else: errors.append(error_string(err))
  if DirAccess.get_files_at(record.dir).is_empty(): DirAccess.remove_absolute(record.dir)
 for path: String in plan.loose:
  if not _linked(path):
   var err := DirAccess.remove_absolute(path)
   if err == OK: deleted += 1
   else: errors.append(error_string(err))
 return {"deleted":deleted,"errors":errors,"skipped":plan.skipped,"remaining":inventory(source_hash).total}

static func describe(info: Dictionary) -> String:
 return "Cache %.1f MiB · depth %.1f · images %.1f · thumbs %.1f · temp %.1f" % [float(info.total)/1048576.0,float(info.depth)/1048576.0,float(info.images)/1048576.0,float(info.thumbnails)/1048576.0,float(info.temporary)/1048576.0]
