extends GdUnitTestSuite

## Tests for RoomNavigationUI — room name display, exit buttons, navigation flow.
## Covers acceptance criteria from design/gdd/room-location-management.md Rule 6.

const RNU_SCRIPT := "res://src/ui/room_navigation_ui.gd"

var _ui: Node
var _mock_room_mgr: Node
var _mock_dialogue_mgr: Node

var _navigation_events: Array[StringName]


func before_test() -> void:
	_mock_room_mgr = Node.new()
	_mock_room_mgr.name = "RoomManager"
	_mock_room_mgr.set_script(_create_room_mgr_mock())
	add_child(_mock_room_mgr)

	_mock_dialogue_mgr = Node.new()
	_mock_dialogue_mgr.name = "DialogueManager"
	_mock_dialogue_mgr.set_script(_create_dialogue_mgr_mock())
	add_child(_mock_dialogue_mgr)

	_ui = Node.new()
	_ui.set_script(load(RNU_SCRIPT))
	_ui.name = "RoomNavigationUITest"
	_ui.set_room_manager(_mock_room_mgr)
	_ui.set_dialogue_manager(_mock_dialogue_mgr)
	add_child(_ui)

	_navigation_events = []
	_ui.navigation_requested.connect(func(id): _navigation_events.append(id))


func after_test() -> void:
	if _ui:
		_ui.queue_free()
	if _mock_room_mgr:
		_mock_room_mgr.queue_free()
	if _mock_dialogue_mgr:
		_mock_dialogue_mgr.queue_free()


# ---------------------------------------------------------------------------
# Room Name Display
# ---------------------------------------------------------------------------


func test_update_for_room_shows_label() -> void:
	_ui.update_for_room(&"lobby")
	assert_eq(_ui._room_name_label.text, "大厅")


func test_update_for_room_shows_id_if_no_label() -> void:
	_ui.update_for_room(&"unknown_room")
	assert_eq(_ui._room_name_label.text, "unknown_room")


func test_update_for_room_corridor() -> void:
	_ui.update_for_room(&"corridor")
	assert_eq(_ui._room_name_label.text, "走廊")


func test_get_current_room() -> void:
	_ui.update_for_room(&"lobby")
	assert_eq(_ui.get_current_room(), &"lobby")


# ---------------------------------------------------------------------------
# Exit Buttons
# ---------------------------------------------------------------------------


func test_lobby_has_one_exit() -> void:
	_ui.update_for_room(&"lobby")
	var buttons := _get_exit_buttons()
	assert_eq(buttons.size(), 1)


func test_corridor_has_two_exits() -> void:
	_ui.update_for_room(&"corridor")
	var buttons := _get_exit_buttons()
	assert_eq(buttons.size(), 2)


func test_guest_room_a_has_one_exit() -> void:
	_ui.update_for_room(&"guest_room_a")
	var buttons := _get_exit_buttons()
	assert_eq(buttons.size(), 1)


func test_exit_button_text() -> void:
	_ui.update_for_room(&"lobby")
	var buttons := _get_exit_buttons()
	assert_eq(buttons[0].text, "走廊")


func test_exit_button_min_touch_target() -> void:
	_ui.update_for_room(&"lobby")
	var buttons := _get_exit_buttons()
	assert_eq(buttons[0].custom_minimum_size.x, 44.0)
	assert_eq(buttons[0].custom_minimum_size.y, 44.0)


func test_unknown_room_has_no_exits() -> void:
	_ui.update_for_room(&"unknown")
	var buttons := _get_exit_buttons()
	assert_eq(buttons.size(), 0)


func test_exit_buttons_update_on_room_change() -> void:
	_ui.update_for_room(&"lobby")
	assert_eq(_get_exit_buttons().size(), 1)
	_ui.update_for_room(&"corridor")
	assert_eq(_get_exit_buttons().size(), 2)


func test_exit_buttons_cleared_on_new_room() -> void:
	_ui.update_for_room(&"corridor")
	_ui.update_for_room(&"lobby")
	assert_eq(_get_exit_buttons().size(), 1)


# ---------------------------------------------------------------------------
# Navigation Enabled State
# ---------------------------------------------------------------------------


func test_navigation_enabled_by_default() -> void:
	assert_true(_ui.is_navigation_enabled())


func test_navigation_disabled_during_transition() -> void:
	_ui._is_transitioning = true
	assert_false(_ui.is_navigation_enabled())


func test_navigation_disabled_during_dialogue() -> void:
	_ui._is_dialogue_active = true
	assert_false(_ui.is_navigation_enabled())


func test_navigation_disabled_transition_and_dialogue() -> void:
	_ui._is_transitioning = true
	_ui._is_dialogue_active = true
	assert_false(_ui.is_navigation_enabled())


# ---------------------------------------------------------------------------
# Transition Signals
# ---------------------------------------------------------------------------


func test_transition_started_disables_buttons() -> void:
	_ui.update_for_room(&"lobby")
	assert_true(_ui.is_navigation_enabled())
	_mock_room_mgr.room_transition_started.emit(&"lobby", &"corridor")
	assert_false(_ui.is_navigation_enabled())


func test_transition_completed_enables_buttons() -> void:
	_ui._is_transitioning = true
	_mock_room_mgr.room_transition_completed.emit(&"corridor")
	assert_true(_ui.is_navigation_enabled())


func test_room_changed_updates_display() -> void:
	_mock_room_mgr.room_changed.emit(&"corridor")
	assert_eq(_ui.get_current_room(), &"corridor")
	assert_eq(_ui._room_name_label.text, "走廊")


func test_room_changed_clears_transitioning() -> void:
	_ui._is_transitioning = true
	_mock_room_mgr.room_changed.emit(&"corridor")
	assert_false(_ui._is_transitioning)


# ---------------------------------------------------------------------------
# Dialogue Signals
# ---------------------------------------------------------------------------


func test_dialogue_started_disables_navigation() -> void:
	_mock_dialogue_mgr.dialogue_started.emit(&"guest_indigo")
	assert_true(_ui._is_dialogue_active)
	assert_false(_ui.is_navigation_enabled())


func test_dialogue_ended_enables_navigation() -> void:
	_ui._is_dialogue_active = true
	_mock_dialogue_mgr.dialogue_ended.emit(&"guest_indigo")
	assert_false(_ui._is_dialogue_active)
	assert_true(_ui.is_navigation_enabled())


func test_dialogue_dims_top_bar() -> void:
	_ui.update_for_room(&"lobby")
	_mock_dialogue_mgr.dialogue_started.emit(&"guest_indigo")
	assert_eq(_ui._top_bar.modulate.a, 0.3)


func test_dialogue_end_restores_top_bar() -> void:
	_ui._is_dialogue_active = true
	_mock_dialogue_mgr.dialogue_ended.emit(&"guest_indigo")
	assert_eq(_ui._top_bar.modulate.a, 1.0)


# ---------------------------------------------------------------------------
# Navigation Request
# ---------------------------------------------------------------------------


func test_exit_button_emits_navigation_requested() -> void:
	_ui.update_for_room(&"lobby")
	var buttons := _get_exit_buttons()
	buttons[0].pressed.emit()
	assert_eq(_navigation_events.size(), 1)
	assert_eq(_navigation_events[0], &"corridor")


func test_navigation_request_calls_room_manager() -> void:
	_ui.update_for_room(&"lobby")
	_ui._request_room_transition(&"corridor")
	assert_eq(_mock_room_mgr._last_transition_request, &"corridor")


func test_navigation_request_blocked_during_transition() -> void:
	_ui._is_transitioning = true
	_ui._request_room_transition(&"corridor")
	assert_eq(_mock_room_mgr._transition_call_count, 0)


func test_navigation_request_blocked_during_dialogue() -> void:
	_ui._is_dialogue_active = true
	_ui._request_room_transition(&"corridor")
	assert_eq(_mock_room_mgr._transition_call_count, 0)


# ---------------------------------------------------------------------------
# UI State Visuals
# ---------------------------------------------------------------------------


func test_exit_bar_dimmed_during_transition() -> void:
	_ui.update_for_room(&"lobby")
	_ui._is_transitioning = true
	_ui._update_navigation_state()
	assert_eq(_ui._exit_bar.modulate.a, 0.4)


func test_exit_bar_normal_when_enabled() -> void:
	_ui.update_for_room(&"lobby")
	assert_eq(_ui._exit_bar.modulate.a, 1.0)


func test_buttons_disabled_during_transition() -> void:
	_ui.update_for_room(&"lobby")
	_ui._is_transitioning = true
	_ui._update_navigation_state()
	var buttons := _get_exit_buttons()
	for btn: Button in buttons:
		assert_true(btn.disabled)


func test_buttons_enabled_by_default() -> void:
	_ui.update_for_room(&"lobby")
	var buttons := _get_exit_buttons()
	for btn: Button in buttons:
		assert_false(btn.disabled)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _get_exit_buttons() -> Array[Button]:
	var result: Array[Button] = []
	if _ui._exit_bar == null:
		return result
	for child: Node in _ui._exit_bar.get_children():
		if child is Button:
			result.append(child)
	return result


# ---------------------------------------------------------------------------
# Mock Scripts
# ---------------------------------------------------------------------------


func _create_room_mgr_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal room_changed(room_id: StringName)\n"
		+ "signal room_transition_started(from_room: StringName, to_room: StringName)\n"
		+ "signal room_transition_completed(room_id: StringName)\n"
		+ "var _last_transition_request: StringName = &\"\"\n"
		+ "var _transition_call_count: int = 0\n"
		+ "func request_transition(room_id: StringName) -> void:\n"
		+ "\t_last_transition_request = room_id\n"
		+ "\t_transition_call_count += 1\n"
	)
	script.reload()
	return script


func _create_dialogue_mgr_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal dialogue_started(npc_id: StringName)\n"
		+ "signal dialogue_ended(npc_id: StringName)\n"
		+ "var is_active: bool = false\n"
	)
	script.reload()
	return script
