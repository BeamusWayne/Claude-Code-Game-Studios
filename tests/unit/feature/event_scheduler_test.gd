extends GdUnitTestSuite

## Tests for EventScheduler — per-night scripted event dispatching with
## TIME/CONDITION/COMPOUND triggers, action execution, dedup, serialization.
## Covers GDD acceptance criteria from design/gdd/event-scheduler.md.

const ES_SCRIPT := "res://src/feature/event_scheduler.gd"

var _scheduler: Node
var _mock_loop: Node
var _mock_timer: Node
var _mock_npc: Node
var _mock_db: Node
var _mock_room: Node
var _mock_bus: Node

var _triggered_events: Array


func before_test() -> void:
	_mock_loop = Node.new()
	_mock_loop.name = "LoopStateManager"
	_mock_loop.set_script(_create_loop_mock())
	add_child(_mock_loop)

	_mock_timer = Node.new()
	_mock_timer.name = "TimerService"
	_mock_timer.set_script(_create_timer_mock())
	add_child(_mock_timer)

	_mock_npc = Node.new()
	_mock_npc.name = "NPCManager"
	_mock_npc.set_script(_create_npc_mock())
	add_child(_mock_npc)

	_mock_db = Node.new()
	_mock_db.name = "ClueDatabase"
	_mock_db.set_script(_create_db_mock())
	add_child(_mock_db)

	_mock_room = Node.new()
	_mock_room.name = "RoomManager"
	_mock_room.set_script(_create_room_mock())
	add_child(_mock_room)

	_mock_bus = Node.new()
	_mock_bus.name = "InteractionBus"
	_mock_bus.set_script(_create_bus_mock())
	add_child(_mock_bus)

	var wrapper := GDScript.new()
	wrapper.source_code = (
		"extends \"%s\"\n" % ES_SCRIPT
		+ "var _test_loop: Node = null\n"
		+ "var _test_timer: Node = null\n"
		+ "var _test_npc: Node = null\n"
		+ "var _test_db: Node = null\n"
		+ "var _test_room: Node = null\n"
		+ "var _test_bus: Node = null\n"
		+ "func _get_loop_state_manager() -> Node:\n"
		+ "\treturn _test_loop\n"
		+ "func _get_timer_service() -> Node:\n"
		+ "\treturn _test_timer\n"
		+ "func _get_npc_manager() -> Node:\n"
		+ "\treturn _test_npc\n"
		+ "func _get_clue_database() -> Node:\n"
		+ "\treturn _test_db\n"
		+ "func _get_room_manager() -> Node:\n"
		+ "\treturn _test_room\n"
		+ "func _get_interaction_bus() -> Node:\n"
		+ "\treturn _test_bus\n"
	)
	wrapper.reload()

	_scheduler = Node.new()
	_scheduler.set_script(wrapper)
	_scheduler._test_loop = _mock_loop
	_scheduler._test_timer = _mock_timer
	_scheduler._test_npc = _mock_npc
	_scheduler._test_db = _mock_db
	_scheduler._test_room = _mock_room
	_scheduler._test_bus = _mock_bus
	_scheduler.name = "EventSchedulerTest"
	add_child(_scheduler)

	_triggered_events = []
	_scheduler.event_triggered.connect(_on_event_triggered)


func _on_event_triggered(event_id: StringName) -> void:
	_triggered_events.append(event_id)


func after_test() -> void:
	if _scheduler:
		_scheduler.queue_free()
	if _mock_loop:
		_mock_loop.queue_free()
	if _mock_timer:
		_mock_timer.queue_free()
	if _mock_npc:
		_mock_npc.queue_free()
	if _mock_db:
		_mock_db.queue_free()
	if _mock_room:
		_mock_room.queue_free()
	if _mock_bus:
		_mock_bus.queue_free()


# ---------------------------------------------------------------------------
# Mock Scripts
# ---------------------------------------------------------------------------


func _create_loop_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal night_ready(night: int)\n"
		+ "signal night_advanced(old_night: int, new_night: int)\n"
		+ "var current_night: int = 1\n"
	)
	script.reload()
	return script


func _create_timer_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal pressure_updated(pressure_level: float)\n"
		+ "var total_duration: float = 180.0\n"
		+ "var remaining_time: float = 180.0\n"
		+ "var current_phase: int = 0\n"
	)
	script.reload()
	return script


func _create_npc_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var _locations: Dictionary = {}\n"
		+ "var _emotional_states: Dictionary = {}\n"
		+ "func get_npc_location(npc_id: StringName) -> StringName:\n"
		+ "\treturn _locations.get(npc_id, &'')\n"
		+ "func set_npc_location(npc_id: StringName, room: StringName) -> void:\n"
		+ "\t_locations[npc_id] = room\n"
		+ "func get_emotional_state(npc_id: StringName) -> int:\n"
		+ "\treturn _emotional_states.get(npc_id, 0)\n"
	)
	script.reload()
	return script


func _create_db_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var _clues: Dictionary = {}\n"
		+ "func has_clue(id: StringName) -> bool:\n"
		+ "\treturn _clues.has(id)\n"
	)
	script.reload()
	return script


func _create_room_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var _states: Dictionary = {}\n"
		+ "func set_room_state(room_id: StringName, key: StringName, value: Variant) -> void:\n"
		+ "\tvar k: String = String(room_id) + '.' + String(key)\n"
		+ "\t_states[k] = value\n"
	)
	script.reload()
	return script


func _create_bus_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal interaction_detected(event: Dictionary)\n"
		+ "var emitted: Array = []\n"
		+ "func emit_interaction(event: Dictionary) -> void:\n"
		+ "\temitted.append(event)\n"
		+ "\tinteraction_detected.emit(event)\n"
	)
	script.reload()
	return script


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _make_time_event(event_id: StringName, trigger_time: float, priority: int = 0, actions: Array = []) -> Dictionary:
	return {
		"event_id": event_id,
		"trigger_type": 0,  # TIME
		"trigger_time": trigger_time,
		"trigger_conditions": [],
		"actions": actions,
		"priority": priority,
	}


func _make_condition_event(event_id: StringName, conditions: Array, priority: int = 0, actions: Array = []) -> Dictionary:
	return {
		"event_id": event_id,
		"trigger_type": 1,  # CONDITION
		"trigger_time": 0.0,
		"trigger_conditions": conditions,
		"actions": actions,
		"priority": priority,
	}


func _inject_events(events: Array[Dictionary]) -> void:
	_scheduler._pending_events = events
	_scheduler._loaded_night = 1
	_scheduler.set_process(true)


# ---------------------------------------------------------------------------
# Tests: Initial State
# ---------------------------------------------------------------------------


func test_initial_state() -> void:
	assert_int(_scheduler.get_loaded_night()).is_equal(-1)
	assert_dict(_scheduler.get_fired_events()).is_empty()
	assert_int(_scheduler._pending_events.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Tests: TIME triggers
# ---------------------------------------------------------------------------


func test_time_trigger_fires_when_elapsed_reached() -> void:
	_inject_events([_make_time_event(&"evt_1", 60.0)])
	_mock_timer.remaining_time = 119.0  # elapsed = 61s >= 60s
	_scheduler._process(0.016)
	assert_int(_triggered_events.size()).is_equal(1)
	assert_str(String(_triggered_events[0])).is_equal("evt_1")


func test_time_trigger_does_not_fire_before_elapsed() -> void:
	_inject_events([_make_time_event(&"evt_1", 60.0)])
	_mock_timer.remaining_time = 150.0  # elapsed = 30s < 60s
	_scheduler._process(0.016)
	assert_int(_triggered_events.size()).is_equal(0)


func test_time_trigger_zero_fires_immediately() -> void:
	_inject_events([_make_time_event(&"evt_1", 0.0)])
	_mock_timer.remaining_time = 180.0
	_scheduler._process(0.016)
	assert_int(_triggered_events.size()).is_equal(1)


func test_time_trigger_past_duration_never_fires() -> void:
	_inject_events([_make_time_event(&"evt_1", 200.0)])
	_mock_timer.remaining_time = 0.0  # elapsed = 180s < 200s
	_scheduler._process(0.016)
	assert_int(_triggered_events.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Tests: Dedup
# ---------------------------------------------------------------------------


func test_dedup_prevents_double_fire() -> void:
	_inject_events([_make_time_event(&"evt_1", 0.0)])
	_scheduler._process(0.016)
	_scheduler._process(0.016)
	assert_int(_triggered_events.size()).is_equal(1)


# ---------------------------------------------------------------------------
# Tests: CONDITION triggers
# ---------------------------------------------------------------------------


func test_condition_npc_in_room_satisfied() -> void:
	_mock_npc.set_npc_location(&"guest_indigo", &"study")
	var conditions := [{"type": "npc_in_room", "npc_id": &"guest_indigo", "room_id": &"study"}]
	_inject_events([_make_condition_event(&"evt_1", conditions)])
	_scheduler._process(0.016)
	assert_int(_triggered_events.size()).is_equal(1)


func test_condition_npc_in_room_not_satisfied() -> void:
	_mock_npc.set_npc_location(&"guest_indigo", &"garden")
	var conditions := [{"type": "npc_in_room", "npc_id": &"guest_indigo", "room_id": &"study"}]
	_inject_events([_make_condition_event(&"evt_1", conditions)])
	_scheduler._process(0.016)
	assert_int(_triggered_events.size()).is_equal(0)


func test_condition_clue_discovered_satisfied() -> void:
	_mock_db._clues[&"clue_1"] = true
	var conditions := [{"type": "clue_discovered", "clue_id": &"clue_1"}]
	_inject_events([_make_condition_event(&"evt_1", conditions)])
	_scheduler._process(0.016)
	assert_int(_triggered_events.size()).is_equal(1)


func test_condition_clue_not_discovered() -> void:
	var conditions := [{"type": "clue_discovered", "clue_id": &"clue_1"}]
	_inject_events([_make_condition_event(&"evt_1", conditions)])
	_scheduler._process(0.016)
	assert_int(_triggered_events.size()).is_equal(0)


func test_condition_phase_is_satisfied() -> void:
	_mock_timer.current_phase = 2  # CRITICAL
	var conditions := [{"type": "phase_is", "phase": 2}]
	_inject_events([_make_condition_event(&"evt_1", conditions)])
	_scheduler._process(0.016)
	assert_int(_triggered_events.size()).is_equal(1)


func test_condition_empty_always_satisfied() -> void:
	_inject_events([_make_condition_event(&"evt_1", [])])
	_scheduler._process(0.016)
	assert_int(_triggered_events.size()).is_equal(1)


# ---------------------------------------------------------------------------
# Tests: COMPOUND triggers
# ---------------------------------------------------------------------------


func test_compound_both_satisfied() -> void:
	_mock_db._clues[&"clue_1"] = true
	_mock_timer.remaining_time = 80.0  # elapsed = 100s >= 90s
	var event: Dictionary = {
		"event_id": &"evt_1",
		"trigger_type": 2,  # COMPOUND
		"trigger_time": 90.0,
		"trigger_conditions": [{"type": "clue_discovered", "clue_id": &"clue_1"}],
		"actions": [],
		"priority": 0,
	}
	_inject_events([event])
	_scheduler._process(0.016)
	assert_int(_triggered_events.size()).is_equal(1)


func test_compound_time_not_met() -> void:
	_mock_db._clues[&"clue_1"] = true
	_mock_timer.remaining_time = 150.0  # elapsed = 30s < 90s
	var event: Dictionary = {
		"event_id": &"evt_1",
		"trigger_type": 2,
		"trigger_time": 90.0,
		"trigger_conditions": [{"type": "clue_discovered", "clue_id": &"clue_1"}],
		"actions": [],
		"priority": 0,
	}
	_inject_events([event])
	_scheduler._process(0.016)
	assert_int(_triggered_events.size()).is_equal(0)


func test_compound_condition_not_met() -> void:
	_mock_timer.remaining_time = 80.0  # elapsed = 100s >= 90s
	var event: Dictionary = {
		"event_id": &"evt_1",
		"trigger_type": 2,
		"trigger_time": 90.0,
		"trigger_conditions": [{"type": "clue_discovered", "clue_id": &"clue_1"}],
		"actions": [],
		"priority": 0,
	}
	_inject_events([event])
	_scheduler._process(0.016)
	assert_int(_triggered_events.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Tests: Priority ordering
# ---------------------------------------------------------------------------


func test_priority_ordering() -> void:
	_inject_events([
		_make_time_event(&"low", 0.0, 1),
		_make_time_event(&"high", 0.0, 10),
		_make_time_event(&"mid", 0.0, 5),
	])
	_scheduler._process(0.016)
	assert_int(_triggered_events.size()).is_equal(3)
	assert_str(String(_triggered_events[0])).is_equal("high")
	assert_str(String(_triggered_events[1])).is_equal("mid")
	assert_str(String(_triggered_events[2])).is_equal("low")


# ---------------------------------------------------------------------------
# Tests: Actions
# ---------------------------------------------------------------------------


func test_move_npc_action() -> void:
	var actions := [{"type": "move_npc", "npc_id": &"guest_indigo", "target_room": &"garden"}]
	_inject_events([_make_time_event(&"evt_1", 0.0, 0, actions)])
	_scheduler._process(0.016)
	assert_str(String(_mock_npc.get_npc_location(&"guest_indigo"))).is_equal("garden")


func test_emit_signal_action() -> void:
	var actions := [{"type": "emit_custom_signal", "signal_name": &"test_signal", "args": {"key": "val"}}]
	_inject_events([_make_time_event(&"evt_1", 0.0, 0, actions)])
	_scheduler._process(0.016)
	assert_int(_mock_bus.emitted.size()).is_equal(1)


func test_change_room_state_action() -> void:
	var actions := [{"type": "change_room_state", "room_id": &"study", "state_key": &"light", "value": false}]
	_inject_events([_make_time_event(&"evt_1", 0.0, 0, actions)])
	_scheduler._process(0.016)
	assert_bool(_mock_room._states.has("study.light")).is_true()


# ---------------------------------------------------------------------------
# Tests: force_trigger
# ---------------------------------------------------------------------------


func test_force_trigger_succeeds() -> void:
	_inject_events([_make_time_event(&"evt_1", 999.0)])
	assert_bool(_scheduler.force_trigger(&"evt_1")).is_true()
	assert_int(_triggered_events.size()).is_equal(1)


func test_force_trigger_fails_if_already_fired() -> void:
	_inject_events([_make_time_event(&"evt_1", 0.0)])
	_scheduler._process(0.016)
	assert_bool(_scheduler.force_trigger(&"evt_1")).is_false()


func test_force_trigger_fails_for_unknown() -> void:
	_inject_events([])
	assert_bool(_scheduler.force_trigger(&"unknown")).is_false()


# ---------------------------------------------------------------------------
# Tests: Night lifecycle
# ---------------------------------------------------------------------------


func test_night_ready_loads_events() -> void:
	_mock_loop.night_ready.emit(1)
	assert_int(_scheduler._pending_events.size()).is_equal(0)
	assert_int(_scheduler.get_loaded_night()).is_equal(1)


func test_night_advanced_clears_state() -> void:
	_inject_events([_make_time_event(&"evt_1", 0.0)])
	_scheduler._process(0.016)
	_mock_loop.night_advanced.emit(1, 2)
	assert_dict(_scheduler.get_fired_events()).is_empty()
	assert_int(_scheduler._pending_events.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Tests: Missing event file
# ---------------------------------------------------------------------------


func test_load_night_events_missing_file() -> void:
	_scheduler.load_night_events(99)
	assert_int(_scheduler._pending_events.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Tests: Serialize / Deserialize / Reset
# ---------------------------------------------------------------------------


func test_serialize_roundtrip() -> void:
	_inject_events([_make_time_event(&"evt_1", 0.0)])
	_scheduler._process(0.016)
	var data: Dictionary = _scheduler.serialize()
	assert_int(data.get("loaded_night", -1)).is_equal(1)
	var fired: Array = data.get("fired_events", [])
	assert_bool("evt_1" in fired).is_true()


func test_reset_clears_all() -> void:
	_inject_events([_make_time_event(&"evt_1", 0.0)])
	_scheduler._process(0.016)
	_scheduler.reset()
	assert_dict(_scheduler.get_fired_events()).is_empty()
	assert_int(_scheduler._pending_events.size()).is_equal(0)
	assert_int(_scheduler.get_loaded_night()).is_equal(-1)


func test_deserialize_restores_fired() -> void:
	_inject_events([_make_time_event(&"evt_1", 0.0)])
	_scheduler._process(0.016)
	var data: Dictionary = _scheduler.serialize()
	_scheduler.reset()
	_scheduler.deserialize(data)
	assert_bool(_scheduler.get_fired_events().has(&"evt_1")).is_true()
