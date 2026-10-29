class_name ConversionStore
extends RefCounted
## Originals are READ-only. Immutable raw depth + metadata live outside photos/.
const ROOT := "user://conversions"
const SCHEMA := 1

static func source_hash(path: String) -> String:
 var raw := path + ".bin" if path.begins_with("res://assets/") and FileAccess.file_exists(path + ".bin") else path
 return FileAccess.get_sha256(raw) if FileAccess.file_exists(raw) else ""

static func key_for(hash: String, model: String, quality: String) -> String:
 return (hash + ":" + model + ":" + quality + ":" + str(SCHEMA)).sha256_text()

static func load_record(key: String) -> Dictionary:
 if not valid_key(key):
  return {}
 var path := ROOT.path_join(key).path_join("record.json")
 if not FileAccess.file_exists(path):
  return {}
 var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
 if not value is Dictionary or value.get("schema") != SCHEMA:
  return {}
 var directory := ROOT.path_join(key)
 if not FileAccess.file_exists(directory.path_join("raw.qpd")):
  return {}
 value["directory"] = directory
 return value

static func read_depth(path: String) -> Image:
 var f := FileAccess.open(path, FileAccess.READ)
 if f == null or f.get_length() < 12 or f.get_buffer(4).get_string_from_ascii() != "QPD1":
  return null
 var w := f.get_32()
 var h := f.get_32()
 if w < 1 or h < 1 or w > 2048 or h > 2048 or f.get_length() != 12 + w * h * 4:
  return null
 var bytes := f.get_buffer(w * h * 4)
 var values := bytes.to_float32_array()
 for value in values:
  if not is_finite(value):
   return null
 return Image.create_from_data(w, h, false, Image.FORMAT_RF, bytes)

static func save_record(key: String, raw_path: String, record: Dictionary) -> Error:
 if not valid_key(key) or read_depth(raw_path) == null:
  return ERR_INVALID_DATA
 var make_error := DirAccess.make_dir_recursive_absolute(ROOT)
 if make_error != OK:
  return make_error
 if DirAccess.get_directories_at(ROOT).size() >= 128:
  return ERR_OUT_OF_MEMORY # Explicit quota; never delete completed work to make room.
 var destination := ROOT.path_join(key)
 if DirAccess.dir_exists_absolute(destination):
  return ERR_ALREADY_EXISTS
 var temporary := destination + ".pending"
 if DirAccess.dir_exists_absolute(temporary):
  for name in DirAccess.get_files_at(temporary):
   DirAccess.remove_absolute(temporary.path_join(name))
  DirAccess.remove_absolute(temporary)
 var err := DirAccess.make_dir_recursive_absolute(temporary)
 if err != OK:
  return err
 err = DirAccess.copy_absolute(raw_path, temporary.path_join("raw.qpd"))
 if err != OK:
  return err
 var f := FileAccess.open(temporary.path_join("record.json"), FileAccess.WRITE)
 if f == null:
  return FileAccess.get_open_error()
 var stored := record.duplicate(true)
 stored["schema"] = SCHEMA
 f.store_string(JSON.stringify(stored, "  "))
 f.close()
 return DirAccess.rename_absolute(temporary, destination)

static func save_adjustments(key: String, strength: float, plane: float) -> Error:
 if load_record(key).is_empty():
  return ERR_DOES_NOT_EXIST
 var c := ConfigFile.new()
 c.set_value("stereo", "strength", clampf(strength, 0, 0.04))
 c.set_value("stereo", "plane", clampf(plane, 0, 1))
 return c.save(ROOT.path_join(key).path_join("adjustments.cfg"))

static func adjustments(key: String) -> Dictionary:
 var c := ConfigFile.new()
 c.load(ROOT.path_join(key).path_join("adjustments.cfg"))
 return {"strength": clampf(float(c.get_value("stereo", "strength", 0.02)), 0, 0.04),
  "plane": clampf(float(c.get_value("stereo", "plane", 0.5)), 0, 1)}

static func valid_key(key: String) -> bool:
 return key.length() == 64 and key.is_valid_hex_number(false)
