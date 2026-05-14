extends GdUnitTestSuite

# Tests for LoopStateManager — core state model, signals, and night transitions.
# Covers ADR-0004 requirements: night advancement, consequence registration,
# template overrides, serialization, rollback, and reset.


const LOOP_STATE_MANAGER_SCRIPT := "res://src/core/loop_state_manager.gd"

var _manager: Node
var _signal_log: Dictionary


func before_test() -> void:
	_manager = Node.new()
	_manager.set_script(load(LOOP_STATE_MANAGER_SCRIPT))
	_manager.name = "LoopStateManagerTest"
	add_child(_manager)
	_signal_log = {}
	_connect_signals()


func after_test() -> void:
	if _manager:
		_manager.queue_free()


func _connect_signals() -> void:
	_manager.night_advanced.connect(func(old, new): _signal_log["night_advanced"] = {"old": old, "new": new})
	_manager.night_advanced_failed.connect(func(reason): _signal_log["night_advanced_failed"] = reason)
	_manager.night_ready.connect(func(night): _signal_log["night_ready"] = night)
	_manager.advance_failed.connect(func(step, error): _signal_log["advance_failed"] = {"step": step, "error": error})
	_manager.consequence_registered.connect(func(id): _signal_log["consequence_registered"] = id)
	_manager.consequence_replayed.connect(_on_consequence_replayed)


func _on_consequence_replayed(id: StringName) -> void:
	if not _signal_log.has("consequence_replayed"):
		_signal_log["consequence_replayed"] = []
	(_signal_log["consequence_replayed"] as Array).append(id)


func test_initial_state() -> void:
	assert_int(_manager.current_night).is_equal(1)
	assert_int(_manager.current_phase).is_equal(0)
	assert_bool(_manager.is_transitioning).is_false()


func test_advance_night_increments() -> void:
	var result: bool = _manager.advance_night()
	assert_bool(result).is_true()
	assert_int(_manager.current_night).is_equal(2)
	assert_dict(_signal_log).contains_keys("night_advanced")
	assert_int(_signal_log["night_advanced"]["old"]).is_equal(1)
	assert_int(_signal_log["night_advanced"]["new"]).is_equal(2)


func test_advance_night_at_max_fails() -> void:
	_manager.current_night = 7
	var result: bool = _manager.advance_night()
	assert_bool(result).is_false()
	assert_int(_manager.current_night).is_equal(7)
	assert_dict(_signal_log).contains_keys("night_advanced_failed")


func test_advance_night_blocks_during_transition() -> void:
	_manager.is_transitioning = true
	var result: bool = _manager.advance_night()
	assert_bool(result).is_false()
	assert_that(_signal_log.get("night_advanced_failed", "")).is_equal("transition_in_progress")


func test_night_phase_transitions() -> void:
	assert_float(_manager.get_night_phase_duration()).is_equal(180.0)
	_manager.set_phase(1)
	assert_int(_manager.current_phase).is_equal(1)
	assert_float(_manager.get_night_phase_duration()).is_equal(120.0)
	_manager.set_phase(2)
	assert_float(_manager.get_night_phase_duration()).is_equal(0.0)


func test_night_ready_signal_on_advance() -> void:
	_manager.advance_night()
	assert_dict(_signal_log).contains_keys("night_ready")
	assert_int(_signal_log["night_ready"]).is_equal(2)


func test_advance_failed_signal_on_max_night() -> void:
	_manager.current_night = 7
	_manager.advance_night()
	assert_dict(_signal_log).contains_keys("advance_failed")
	assert_int(_signal_log["advance_failed"]["step"]).is_equal(1)


func test_consequence_registration() -> void:
	_manager.register_consequence(&"test_consequence", {
		"target": &"door_1",
		"property": "is_locked",
		"value": false,
		"affects_nights": [2, 3, 4],
	})
	assert_dict(_signal_log).contains_keys("consequence_registered")
	assert_that(_signal_log["consequence_registered"]).is_equal(&"test_consequence")


func test_consequences_survive_advance() -> void:
	_manager.register_consequence(&"my_consequence", {
		"target": &"door_1",
		"property": "is_locked",
		"value": false,
		"affects_nights": [2, 3],
	})
	_manager.advance_night()
	var data: Dictionary = _manager.serialize()
	assert_int(data["consequences"].size()).is_equal(1)
	assert_that(data["consequences"][0]["id"]).is_equal("my_consequence")


func test_consequence_affects_nights_filter() -> void:
	_manager.register_consequence(&"night2_only", {
		"target": &"item_a",
		"property": "visible",
		"value": true,
		"affects_nights": [2],
	})
	_manager.current_night = 1
	_manager.advance_night()
	var override: Variant = _manager.get_template_override(&"item_a", "visible")
	assert_that(override).is_equal(true)


func test_template_override_applied() -> void:
	_manager.register_consequence(&"unlock", {
		"target": &"secret_door",
		"property": "is_locked",
		"value": false,
		"affects_nights": [],
	})
	_manager.advance_night()
	var val: Variant = _manager.get_template_override(&"secret_door", "is_locked")
	assert_that(val).is_equal(false)


func test_serialize_deserialize_roundtrip() -> void:
	_manager.register_consequence(&"test_id", {
		"target": &"obj_1",
		"property": "state",
		"value": "open",
		"affects_nights": [3],
	})
	_manager.advance_night()
	_manager.set_phase(1)
	var data: Dictionary = _manager.serialize()

	var new_mgr := Node.new()
	new_mgr.set_script(load(LOOP_STATE_MANAGER_SCRIPT))
	add_child(new_mgr)
	var ok: bool = new_mgr.deserialize(data)
	assert_bool(ok).is_true()
	assert_int(new_mgr.current_night).is_equal(2)
	assert_int(new_mgr.current_phase).is_equal(1)
	var new_data: Dictionary = new_mgr.serialize()
	assert_int(new_data["consequences"].size()).is_equal(1)
	new_mgr.queue_free()


func test_deserialize_empty_returns_false() -> void:
	var result: bool = _manager.deserialize({})
	assert_bool(result).is_false()


func test_reset_restores_initial_state() -> void:
	_manager.advance_night()
	_manager.register_consequence(&"x", {"target": &"a", "property": "b", "value": 1, "affects_nights": []})
	_manager.reset()
	assert_int(_manager.current_night).is_equal(1)
	assert_int(_manager.current_phase).is_equal(0)
	assert_bool(_manager.is_transitioning).is_false()


func test_rollback_restores_state() -> void:
	_manager.current_night = 3
	_manager.set_phase(1)
	_manager.register_consequence(&"test", {"target": &"a", "property": "b", "value": 1, "affects_nights": []})
	var snapshot := {
		"night": 1,
		"phase": 0,
		"consequences": [],
		"overrides": {},
	}
	_manager.rollback(snapshot)
	assert_int(_manager.current_night).is_equal(1)
	assert_int(_manager.current_phase).is_equal(0)
	assert_bool(_manager.is_transitioning).is_false()


func test_duplicate_consequence_updates() -> void:
	_manager.register_consequence(&"dup_test", {"target": &"a", "property": "b", "value": 1, "affects_nights": []})
	_manager.register_consequence(&"dup_test", {"target": &"a", "property": "b", "value": 2, "affects_nights": []})
	var data: Dictionary = _manager.serialize()
	assert_int(data["consequences"].size()).is_equal(1)
	assert_int(data["consequences"][0]["mutation"]["value"]).is_equal(2)
