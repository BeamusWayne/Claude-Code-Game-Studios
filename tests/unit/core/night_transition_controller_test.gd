extends GdUnitTestSuite

## Tests for NightTransitionController -- transition sequence, blocking guards,
## error recovery, pending transitions, and timer connection.
## Covers ADR-0011 validation criteria.


const NTC_SCRIPT := "res://src/core/night_transition_controller.gd"

var _controller: Node
var _mock_timer: Node
var _mock_loop_state: Node
var _mock_room_manager: Node
var _mock_save_manager: Node
var _mock_ui_manager: Node

var _started_events: Array
var _completed_events: Array
var _failed_events: Array
var _game_ending_events: Array


func before_test() -> void:
	# Create mock autoloads
	_mock_timer = Node.new()
	_mock_timer.name = "TimerService"
	_mock_timer.set_script(_create_timer_mock_script())
	add_child(_mock_timer)

	_mock_loop_state = Node.new()
	_mock_loop_state.name = "LoopStateManager"
	_mock_loop_state.set_script(_create_loop_state_mock_script())
	add_child(_mock_loop_state)

	_mock_room_manager = Node.new()
	_mock_room_manager.name = "RoomManager"
	_mock_room_manager.set_script(_create_room_manager_mock_script())
	add_child(_mock_room_manager)

	_mock_save_manager = Node.new()
	_mock_save_manager.name = "SaveManager"
	_mock_save_manager.set_script(_create_save_manager_mock_script())
	add_child(_mock_save_manager)

	_mock_ui_manager = Node.new()
	_mock_ui_manager.name = "UIManager"
	_mock_ui_manager.set_script(_create_ui_manager_mock_script())
	add_child(_mock_ui_manager)

	# Create controller with test wrapper that injects mocks via DI
	var test_wrapper := GDScript.new()
	test_wrapper.source_code = (
		"extends \"%s\"\n" % NTC_SCRIPT
		+ "var _test_timer: Node = null\n"
		+ "var _test_loop_state: Node = null\n"
		+ "var _test_room_manager: Node = null\n"
		+ "var _test_save_manager: Node = null\n"
		+ "var _test_ui_manager: Node = null\n"
		+ "func _get_timer_service() -> Node:\n"
		+ "\treturn _test_timer\n"
		+ "func _get_loop_state_manager() -> Node:\n"
		+ "\treturn _test_loop_state\n"
		+ "func _get_room_manager() -> Node:\n"
		+ "\treturn _test_room_manager\n"
		+ "func _get_save_manager() -> Node:\n"
		+ "\treturn _test_save_manager\n"
		+ "func _get_ui_manager() -> Node:\n"
		+ "\treturn _test_ui_manager\n"
	)
	test_wrapper.reload()

	_controller = Node.new()
	_controller.set_script(test_wrapper)
	_controller._test_timer = _mock_timer
	_controller._test_loop_state = _mock_loop_state
	_controller._test_room_manager = _mock_room_manager
	_controller._test_save_manager = _mock_save_manager
	_controller._test_ui_manager = _mock_ui_manager
	_controller.name = "NightTransitionControllerTest"
	add_child(_controller)

	# Wire up signal logging (named methods — no lambdas for GDUnit4 safety)
	_started_events = []
	_completed_events = []
	_failed_events = []
	_game_ending_events = []
	_controller.night_transition_started.connect(_on_started)
	_controller.night_transition_completed.connect(_on_completed)
	_controller.night_transition_failed.connect(_on_failed)
	_controller.game_ending_triggered.connect(_on_game_ending)


func _on_started(night: int) -> void:
	_started_events.append(night)


func _on_completed(night: int) -> void:
	_completed_events.append(night)


func _on_failed(reason: String) -> void:
	_failed_events.append(reason)


func _on_game_ending(night: int) -> void:
	_game_ending_events.append(night)


func after_test() -> void:
	if _controller:
		_controller.queue_free()
	if _mock_timer:
		_mock_timer.queue_free()
	if _mock_loop_state:
		_mock_loop_state.queue_free()
	if _mock_room_manager:
		_mock_room_manager.queue_free()
	if _mock_save_manager:
		_mock_save_manager.queue_free()
	if _mock_ui_manager:
		_mock_ui_manager.queue_free()


# ---------------------------------------------------------------------------
# Mock Scripts
# ---------------------------------------------------------------------------


func _create_timer_mock_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal night_timer_ended(night: int)\n"
		+ "var is_active: bool = false\n"
		+ "var time_scale: float = 1.0\n"
		+ "var stop_count: int = 0\n"
		+ "var start_count: int = 0\n"
		+ "func stop_timer() -> void:\n"
		+ "\tis_active = false\n"
		+ "\tstop_count += 1\n"
		+ "func set_time_scale(s: float) -> void:\n"
		+ "\ttime_scale = s\n"
		+ "func start_night_timer() -> void:\n"
		+ "\tis_active = true\n"
		+ "\tstart_count += 1\n"
	)
	script.reload()
	return script


func _create_loop_state_mock_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal night_advanced(old_night: int, new_night: int)\n"
		+ "signal advance_failed(step: int, error: String)\n"
		+ "signal night_ready(night: int)\n"
		+ "var current_night: int = 1\n"
		+ "var is_transitioning: bool = false\n"
		+ "var advance_count: int = 0\n"
		+ "var should_fail: bool = false\n"
		+ "func get_current_night() -> int:\n"
		+ "\treturn current_night\n"
		+ "func advance_night() -> bool:\n"
		+ "\tadvance_count += 1\n"
		+ "\tif should_fail:\n"
		+ "\t\tadvance_failed.emit(1, \"mock failure\")\n"
		+ "\t\treturn false\n"
		+ "\tvar old := current_night\n"
		+ "\tcurrent_night += 1\n"
		+ "\tnight_advanced.emit(old, current_night)\n"
		+ "\tnight_ready.emit(current_night)\n"
		+ "\treturn true\n"
	)
	script.reload()
	return script


func _create_room_manager_mock_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal room_transition_completed(room_id: StringName)\n"
		+ "var _fade_alpha: float = 0.0\n"
		+ "var _is_transitioning: bool = false\n"
		+ "func set_fade_alpha(a: float) -> void:\n"
		+ "\t_fade_alpha = clampf(a, 0.0, 1.0)\n"
		+ "func get_fade_alpha() -> float:\n"
		+ "\treturn _fade_alpha\n"
		+ "func get_is_transitioning() -> bool:\n"
		+ "\treturn _is_transitioning\n"
	)
	script.reload()
	return script


func _create_save_manager_mock_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var current_slot: int = 1\n"
		+ "var save_should_fail: bool = false\n"
		+ "var save_count: int = 0\n"
		+ "func save_game(_slot: int) -> bool:\n"
		+ "\tsave_count += 1\n"
		+ "\treturn not save_should_fail\n"
	)
	script.reload()
	return script


func _create_ui_manager_mock_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal dialogue_ended()\n"
		+ "var _dialogue_active: bool = false\n"
		+ "func is_dialogue_active() -> bool:\n"
		+ "\treturn _dialogue_active\n"
	)
	script.reload()
	return script


# ---------------------------------------------------------------------------
# Helper: drive a full transition synchronously for testing
# ---------------------------------------------------------------------------


## Simulates the full transition by directly calling the callback chain
## instead of waiting for real Tweens to complete.
## The transition uses Tween-based callbacks, but in headless tests
## Tweens may not fire. We manually invoke the step callbacks.
func _drive_full_transition() -> void:
	_controller.request_night_transition()

	# _execute_transition was called. It synchronously runs save, stop, emit,
	# then creates a Tween for _fade_out. The Tween won't complete in headless,
	# so we simulate the fade-out-complete callback:
	_controller._on_fade_out_complete()

	# _on_fade_out_complete calls advance_night() which synchronously emits
	# night_advanced -> _on_night_advanced -> _fade_in (another Tween).
	# Simulate fade-in-complete:
	if _controller.is_transitioning:
		_controller._on_fade_in_complete()


## Simulates only the execute + fade_out_complete steps (no advance yet).
func _drive_to_advance() -> void:
	_controller.request_night_transition()
	_controller._on_fade_out_complete()


# ---------------------------------------------------------------------------
# Tests: Initial State
# ---------------------------------------------------------------------------


func test_initial_state() -> void:
	assert_bool(_controller.is_transitioning).is_false()
	assert_bool(_controller._pending_transition).is_false()


# ---------------------------------------------------------------------------
# Tests: Blocking Guards
# ---------------------------------------------------------------------------


func test_request_transition_blocked_when_transitioning() -> void:
	_controller.is_transitioning = true
	_controller.request_night_transition()
	assert_int(_started_events.size()).is_equal(0)
	assert_int(_mock_loop_state.advance_count).is_equal(0)


func test_request_transition_queues_when_dialogue_active() -> void:
	_mock_ui_manager._dialogue_active = true
	_controller.request_night_transition()
	assert_bool(_controller._pending_transition).is_true()
	assert_int(_started_events.size()).is_equal(0)


func test_request_transition_blocked_when_room_transitioning() -> void:
	_mock_room_manager._is_transitioning = true
	_controller.request_night_transition()
	assert_bool(_controller._pending_transition).is_true()
	assert_int(_started_events.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Tests: Night 7 Game Ending
# ---------------------------------------------------------------------------


func test_night_7_triggers_game_ending() -> void:
	_mock_loop_state.current_night = 7
	_controller.request_night_transition()
	assert_int(_game_ending_events.size()).is_equal(1)
	assert_int(_game_ending_events[0]).is_equal(7)
	assert_int(_started_events.size()).is_equal(0)
	assert_bool(_controller.is_transitioning).is_false()


func test_night_6_proceeds_normally() -> void:
	_mock_loop_state.current_night = 6
	_controller.request_night_transition()
	assert_int(_game_ending_events.size()).is_equal(0)
	assert_bool(_controller.is_transitioning).is_true()


# ---------------------------------------------------------------------------
# Tests: Full Transition Sequence
# ---------------------------------------------------------------------------


func test_full_transition_sequence() -> void:
	_mock_loop_state.current_night = 1
	_mock_save_manager.current_slot = 1

	_drive_full_transition()

	# Verify save was called
	assert_int(_mock_save_manager.save_count).is_equal(1)

	# Verify timer was stopped
	assert_int(_mock_timer.stop_count).is_equal(1)

	# Verify started signal with old night
	assert_int(_started_events.size()).is_greater_equal(1)
	assert_int(_started_events[0]).is_equal(1)

	# Verify advance_night was called
	assert_int(_mock_loop_state.advance_count).is_equal(1)

	# Verify completion
	assert_int(_completed_events.size()).is_equal(1)
	assert_int(_completed_events[0]).is_equal(2)
	assert_bool(_controller.is_transitioning).is_false()
	assert_bool(_mock_loop_state.is_transitioning).is_false()

	# Verify time scale restored
	assert_float(_mock_timer.time_scale).is_equal(1.0)


# ---------------------------------------------------------------------------
# Tests: Save Failure Aborts Transition
# ---------------------------------------------------------------------------


func test_save_failure_aborts_transition() -> void:
	_mock_save_manager.current_slot = 1
	_mock_save_manager.save_should_fail = true

	_controller.request_night_transition()

	# Should have aborted
	assert_int(_failed_events.size()).is_equal(1)
	assert_bool(_controller.is_transitioning).is_false()
	assert_bool(_mock_loop_state.is_transitioning).is_false()

	# advance_night should NOT have been called
	assert_int(_mock_loop_state.advance_count).is_equal(0)

	# Time scale should be restored
	assert_float(_mock_timer.time_scale).is_equal(1.0)


func test_no_save_when_slot_is_negative() -> void:
	_mock_save_manager.current_slot = -1
	_mock_loop_state.current_night = 1

	_drive_full_transition()

	# Should complete without attempting save
	assert_int(_mock_save_manager.save_count).is_equal(0)
	assert_int(_completed_events.size()).is_equal(1)


# ---------------------------------------------------------------------------
# Tests: Advance Failure Recovery
# ---------------------------------------------------------------------------


func test_advance_failure_triggers_error_recovery() -> void:
	_mock_loop_state.current_night = 1
	_mock_loop_state.should_fail = true

	_drive_to_advance()

	# The advance_failed signal is emitted by the mock, which is connected
	# to _on_advance_failed. This should:
	# - set is_transitioning = false
	# - set loop_state.is_transitioning = false
	assert_bool(_controller.is_transitioning).is_false()
	assert_bool(_mock_loop_state.is_transitioning).is_false()


# ---------------------------------------------------------------------------
# Tests: Pending Transition Fires After Block Cleared
# ---------------------------------------------------------------------------


func test_pending_transition_fires_after_dialogue_cleared() -> void:
	_mock_ui_manager._dialogue_active = true
	_controller.request_night_transition()
	assert_bool(_controller._pending_transition).is_true()

	# Dialogue ends -- _on_blocking_cleared is called
	_mock_ui_manager._dialogue_active = false
	_controller._on_blocking_cleared()

	# Pending should have been cleared (call_deferred won't fire in test,
	# but we verify the flag was reset)
	assert_bool(_controller._pending_transition).is_false()


func test_pending_transition_not_fired_when_still_transitioning() -> void:
	_controller.is_transitioning = true
	_controller._pending_transition = true

	_controller._on_blocking_cleared()

	# Should NOT clear pending because we are still transitioning
	assert_bool(_controller._pending_transition).is_true()


func test_pending_transition_fires_after_room_transition_cleared() -> void:
	_mock_room_manager._is_transitioning = true
	_controller.request_night_transition()
	assert_bool(_controller._pending_transition).is_true()

	# Room transition completes
	_mock_room_manager._is_transitioning = false
	_controller._on_blocking_cleared(&"test_room")

	assert_bool(_controller._pending_transition).is_false()


# ---------------------------------------------------------------------------
# Tests: Timer Connection
# ---------------------------------------------------------------------------


func test_night_timer_ended_connected() -> void:
	# Verify the controller connected to the mock timer's signal
	var connections: Array = _mock_timer.get_signal_connection_list("night_timer_ended")
	var found: bool = false
	for conn: Dictionary in connections:
		var callable: Callable = conn["callable"]
		if callable.get_object() == _controller:
			found = true
	assert_bool(found).is_true()


# ---------------------------------------------------------------------------
# Tests: Serialize / Deserialize / Reset
# ---------------------------------------------------------------------------


func test_serialize_returns_empty() -> void:
	var data: Dictionary = _controller.serialize()
	assert_dict(data).is_empty()


func test_deserialize_is_noop() -> void:
	# Should not crash
	_controller.deserialize({"some": "data"})


func test_reset_clears_transition_state() -> void:
	_controller.is_transitioning = true
	_controller._pending_transition = true
	_controller.reset()
	assert_bool(_controller.is_transitioning).is_false()
	assert_bool(_controller._pending_transition).is_false()


# ---------------------------------------------------------------------------
# Tests: Signal Connections
# ---------------------------------------------------------------------------


func test_loop_state_signals_connected() -> void:
	# Verify night_advanced is connected
	var advanced_conns: Array = _mock_loop_state.get_signal_connection_list("night_advanced")
	var found_advanced: bool = false
	for conn: Dictionary in advanced_conns:
		var callable: Callable = conn["callable"]
		if callable.get_object() == _controller:
			found_advanced = true
	assert_bool(found_advanced).is_true()

	# Verify advance_failed is connected
	var failed_conns: Array = _mock_loop_state.get_signal_connection_list("advance_failed")
	var found_failed: bool = false
	for conn: Dictionary in failed_conns:
		var callable: Callable = conn["callable"]
		if callable.get_object() == _controller:
			found_failed = true
	assert_bool(found_failed).is_true()


# ---------------------------------------------------------------------------
# Tests: LoopStateManager.is_transitioning management
# ---------------------------------------------------------------------------


func test_execute_sets_loop_state_transitioning() -> void:
	_mock_loop_state.current_night = 1
	_controller.request_night_transition()
	assert_bool(_mock_loop_state.is_transitioning).is_true()


func test_complete_clears_loop_state_transitioning() -> void:
	_mock_loop_state.current_night = 1
	_drive_full_transition()
	assert_bool(_mock_loop_state.is_transitioning).is_false()


func test_abort_clears_loop_state_transitioning() -> void:
	_mock_save_manager.current_slot = 1
	_mock_save_manager.save_should_fail = true
	_controller.request_night_transition()
	assert_bool(_mock_loop_state.is_transitioning).is_false()
