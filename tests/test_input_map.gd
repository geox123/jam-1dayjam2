extends SceneTree

var failures := 0


func _init() -> void:
	_assert_action_has_key("move_left", KEY_LEFT, "Left arrow action")
	_assert_action_has_key("move_right", KEY_RIGHT, "Right arrow action")
	_assert_action_has_key("move_up", KEY_UP, "Up arrow action")
	_assert_action_has_key("move_down", KEY_DOWN, "Down arrow action")
	if failures > 0:
		quit(1)
	else:
		print("Airebound input map: all arrow bindings passed")
		quit(0)


func _assert_action_has_key(action: String, expected_key: Key, label: String) -> void:
	var matched := false
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event.keycode == expected_key or event.physical_keycode == expected_key):
			matched = true
	if not matched:
		failures += 1
		push_error("FAIL: %s is missing key code %d" % [label, expected_key])
