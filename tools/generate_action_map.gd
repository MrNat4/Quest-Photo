# Run: godot --headless --xr-mode off --path . --script tools/generate_action_map.gd
# Quest Touch Plus controllers expose the backwards-compatible Oculus Touch profile.
# The OpenXR action names are part of the application's input API; do not rename
# them without updating viewer input code and tests.
# XRController3D: tracker="left_hand"/"right_hand", pose="aim"/"grip".
# Godot maps aim_pose/grip_pose to these shorter tracker pose names.
# IMPORTANT: do not name a float action grip: grip_pose is renamed to grip
# before duplicate-action detection in Godot 4.6.3.
# Primary: X (left), A (right). Secondary: Y (left), B (right).
# Verified against Godot 4.6.3 modules/openxr/openxr_interface.cpp:
# https://github.com/godotengine/godot/blob/4.6.3-stable/modules/openxr/openxr_interface.cpp
extends SceneTree

const HANDS := ["/user/hand/left", "/user/hand/right"]
const PROFILE := "/interaction_profiles/oculus/touch_controller"
const DEFINITIONS := {
	"aim_pose": [OpenXRAction.OPENXR_ACTION_POSE, "Aim pose", "aim/pose"],
	"grip_pose": [OpenXRAction.OPENXR_ACTION_POSE, "Grip pose", "grip/pose"],
	"trigger": [OpenXRAction.OPENXR_ACTION_FLOAT, "Trigger", "trigger/value"],
	"squeeze": [OpenXRAction.OPENXR_ACTION_FLOAT, "Grip", "squeeze/value"],
	"thumbstick": [OpenXRAction.OPENXR_ACTION_VECTOR2, "Thumbstick", "thumbstick"],
	"primary": [OpenXRAction.OPENXR_ACTION_BOOL, "Primary A or X", ""],
	"secondary": [OpenXRAction.OPENXR_ACTION_BOOL, "Secondary B or Y", ""],
	"thumbstick_click": [OpenXRAction.OPENXR_ACTION_BOOL, "Thumbstick click", "thumbstick/click"],
}

func _initialize() -> void:
	var action_map := OpenXRActionMap.new()
	var action_set := OpenXRActionSet.new()
	action_set.resource_name = "viewer"
	action_set.resource_scene_unique_id = "ViewerActions"
	action_set.localized_name = "Photo viewer"
	action_set.priority = 0
	var profile := OpenXRInteractionProfile.new()
	profile.interaction_profile_path = PROFILE
	profile.resource_scene_unique_id = "TouchProfile"
	var bindings: Array[OpenXRIPBinding] = []
	for action_name: String in DEFINITIONS:
		var definition: Array = DEFINITIONS[action_name]
		var action := OpenXRAction.new()
		action.resource_name = action_name
		action.resource_scene_unique_id = "Action_" + action_name
		action.localized_name = definition[1]
		action.action_type = definition[0]
		action.toplevel_paths = PackedStringArray(HANDS)
		action_set.add_action(action)
		for hand: String in HANDS:
			var component: String = definition[2]
			if action_name == "primary":
				component = "x/click" if hand.ends_with("left") else "a/click"
			elif action_name == "secondary":
				component = "y/click" if hand.ends_with("left") else "b/click"
			var binding := OpenXRIPBinding.new()
			binding.action = action
			binding.resource_scene_unique_id = "Binding_" + action_name + "_" + hand.get_file()
			binding.binding_path = hand + "/input/" + component
			bindings.append(binding)
	profile.bindings = bindings
	action_map.add_action_set(action_set)
	action_map.add_interaction_profile(profile)
	var output: String = get_script().resource_path.get_base_dir().get_base_dir().path_join("openxr_action_map.tres")
	var error := ResourceSaver.save(action_map, output)
	if error != OK:
		push_error("Cannot save action map: " + error_string(error))
		quit(1)
		return
	var loaded := ResourceLoader.load(output, "OpenXRActionMap", ResourceLoader.CACHE_MODE_IGNORE) as OpenXRActionMap
	if loaded == null or loaded.get_action_set_count() != 1 or loaded.get_interaction_profile_count() != 1:
		push_error("Action map round-trip failed")
		quit(1)
		return
	var loaded_set := loaded.get_action_set(0)
	var loaded_profile := loaded.get_interaction_profile(0)
	if loaded_set.get_action_count() != DEFINITIONS.size() or loaded_profile.get_binding_count() != DEFINITIONS.size() * 2:
		push_error("Action/binding count mismatch")
		quit(1)
		return
	for i in loaded_set.get_action_count():
		var action: OpenXRAction = loaded_set.get_actions()[i]
		if action.action_type != DEFINITIONS[action.resource_name][0] or action.toplevel_paths != PackedStringArray(HANDS):
			push_error("Action round-trip mismatch: " + action.resource_name)
			quit(1)
			return
	print("Validated 8 actions and 16 Touch bindings: ", output)
	quit(0)
