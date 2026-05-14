extends GdUnitTestSuite

# Integration tests for SaveManager + LoopStateManager coordination.
# Covers S1-7 requirements: auto-save on signals, transition blocking.


const SAVE_MANAGER_SCRIPT := "res://src/persistence/save_manager.gd"
const LOOP_STATE_MANAGER_SCRIPT := "res://src/core/loop_state_manager.gd"

var _save_mgr: Node
var _loop_mgr: Node
var _signal_log: Dictionary


func before_test() -> void:
	_loop_mgr = Node.new()
	_loop_mgr.set_script(load(LOOP_STATE_MANAGER_SCRIPT))
	_loop_mgr.name = "LoopStateManager"
	add_child(_loop_mgr)

	_save_mgr = Node.new()
	_save_mgr.set_script(load(SAVE_MANAGER_SCRIPT))
	_save_mgr.name = "SaveManager"
	add_child(_save_mgr)
	_save_mgr.set_loop_state_manager(_loop_mgr)

	_signal_log = {}
	_save_mgr.save_completed.connect(func(slot): _signal_log["save_completed"] = slot)
	_save_mgr.save_failed.connect(func(slot, reason): _signal_log["save_failed"] = {"slot": slot, "reason": reason})
	_save_mgr.auto_save_completed.connect(func(): _signal_log["auto_save_completed"] = true)

	for i in range(1, 4):
		_save_mgr.delete_save(i)


func after_test() -> void:
	if _save_mgr:
		_save_mgr.queue_free()
	if _loop_mgr:
		_loop_mgr.queue_free()


func test_save_load_roundtrip_preserves_night() -> void:
	_loop_mgr.advance_night()
	_loop_mgr.advance_night()
	assert_int(_loop_mgr.current_night).is_equal(3)

	_save_mgr.save_game(1)
	_loop_mgr.reset()
	assert_int(_loop_mgr.current_night).is_equal(1)

	_save_mgr.load_game(1)
	assert_int(_loop_mgr.current_night).is_equal(3)


func test_save_load_roundtrip_preserves_consequences() -> void:
	_loop_mgr.register_consequence(&"unlock_door", {
		"target": &"door_1", "property": "is_locked", "value": false, "affects_nights": [2, 3],
	})
	_loop_mgr.advance_night()
	_save_mgr.save_game(1)

	_loop_mgr.reset()
	_save_mgr.load_game(1)

	var data: Dictionary = _loop_mgr.serialize()
	assert_int(data["consequences"].size()).is_equal(1)
	assert_that(data["consequences"][0]["id"]).is_equal("unlock_door")


func test_save_blocked_during_loop_transition() -> void:
	_loop_mgr.is_transitioning = true
	var ok: bool = _save_mgr.save_game(1)
	assert_bool(ok).is_false()
	assert_dict(_signal_log).contains_keys("save_failed")
	assert_that(_signal_log["save_failed"]["reason"]).is_equal("loop_transitioning")
	_loop_mgr.is_transitioning = false


func test_auto_save_triggers_on_night_advance() -> void:
	_save_mgr.current_slot = 1
	_loop_mgr.advance_night()
	assert_dict(_signal_log).contains_keys("auto_save_completed")
	assert_bool(_save_mgr.has_save(1)).is_true()
	var data: Dictionary = _save_mgr._read_save_file(1)
	assert_int(int(data.get("systems", {}).get("loop_state", {}).get("current_night", 0))).is_equal(2)


func test_auto_save_triggers_on_consequence_registered() -> void:
	_save_mgr.current_slot = 1
	_loop_mgr.register_consequence(&"test", {
		"target": &"a", "property": "b", "value": 1, "affects_nights": [],
	})
	assert_dict(_signal_log).contains_keys("auto_save_completed")


func test_auto_save_skipped_when_no_slot() -> void:
	assert_int(_save_mgr.current_slot).is_equal(-1)
	_loop_mgr.advance_night()
	assert_bool(not _signal_log.has("auto_save_completed")).is_true()
