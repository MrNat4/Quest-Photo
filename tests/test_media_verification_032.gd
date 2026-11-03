extends SceneTree
const Android = preload("res://tests/reference/android_media_store_032.gd")
var checks := 0
var failures := 0
class MockAndroid extends "res://tests/reference/android_media_store_032.gd":
 var failure := ""
 var calls: Array[String] = []
 func _init() -> void:
  resolver=RefCounted.new();stream=RefCounted.new();uri=RefCounted.new();values_class=RefCounted.new();bytes_written=1234
 func _invoke(_target: Object, method: StringName, _args: Array = []) -> Variant:
  calls.append(str(method))
  match str(method):
   "ContentValues", "openFileDescriptor", "query":
    if failure==str(method): error="Injected "+str(method);return null
    return RefCounted.new()
   "update": return 0 if failure=="update" else 1
   "getStatSize": return 9 if failure=="size" else bytes_written
   "moveToFirst": return failure!="missing"
   "getString": return ("renamed.sbs.png" if _args[0]==0 else ("Wrong/" if failure=="folder" else "Pictures/Z-Dim/"))
   "getInt": return 1 if failure=="pending" else 0
   "toString": return "content://media/external_primary/images/media/42"
  return null
func check(ok: bool,label: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize() -> void:
 var bridge := MockAndroid.new()
 check(not bridge.publish().is_empty(),"Success requires completed readback and row checks")
 check(bridge.actual_name=="renamed.sbs.png","Report actual provider-assigned filename")
 check(bridge.calls.find("close")<bridge.calls.find("openFileDescriptor"),"Close output before readback")
 for reason in ["update","openFileDescriptor","size","query","missing","folder","pending"]:
  var failed:=MockAndroid.new();failed.failure=reason
  check(failed.publish().is_empty() and not failed.error.is_empty(),"Failure is visible for "+reason)
  failed.abort()
  check("delete" in failed.calls,"Rollback own row after "+reason)
 print("MEDIA VERIFICATION 032: %d checks, %d failures; simulated Android calls" % [checks,failures])
 quit(1 if failures else 0)
