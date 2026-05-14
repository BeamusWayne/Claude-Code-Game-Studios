extends GdUnitTestSuite

# Tests for SaveManager — atomic file I/O, JSON schema, backup rotation.
# Covers ADR-0010 requirements: save/load cycle, backup fallback,
# multi-slot independence, schema versioning.


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
	_save_mgr.load_completed.connect(func(slot): _signal_log["load_completed"] = slot)
	_save_mgr.load_failed.connect(func(slot, reason): _signal_log["load_failed"] = {"slot": slot, "reason": reason})

	for i in range(1, 4):
		_save_mgr.delete_save(i)


func after_test() -> void:
	if _save_mgr:
		_save_mgr.queue_free()
	if _loop_mgr:
		_loop_mgr.queue_free()


func test_save_creates_json_file() -> void:
	var ok: bool = _save_mgr.save_game(1)
	assert_bool(ok).is_true()
	assert_dict(_signal_log).contains_keys("save_completed")
	assert_int(_signal_log["save_completed"]).is_equal(1)
	assert_bool(_save_mgr.has_save(1)).is_true()


func test_load_restores_state() -> void:
	_loop_mgr.advance_night()
	_loop_mgr.register_consequence(&"test_consequence", {
		"target": &"door_1", "property": "is_locked", "value": false, "affects_nights": [2, 3],
	})
	_save_mgr.save_game(1)

	_loop_mgr.reset()
	assert_int(_loop_mgr.current_night).is_equal(1)

	var loaded: bool = _save_mgr.load_game(1)
	assert_bool(loaded).is_true()
	assert_int(_loop_mgr.current_night).is_equal(2)


func test_atomic_write_backup_exists() -> void:
	_save_mgr.save_game(1)
	assert_bool(_save_mgr.has_save(1)).is_true()

	_loop_mgr.advance_night()
	_save_mgr.save_game(1)

	var backup_path: String = _save_mgr._get_backup_path(1)
	assert_bool(FileAccess.file_exists(backup_path)).is_true()


func test_corrupt_primary_falls_back_to_backup() -> void:
	_save_mgr.save_game(1)
	_loop_mgr.advance_night()
	_save_mgr.save_game(1)

	var save_path: String = _save_mgr._get_save_path(1)
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string("NOT VALID JSON {{{")
	file.close()

	var data: Dictionary = _save_mgr._read_save_file(1)
	assert_bool(not data.is_empty()).is_true()
	var systems: Dictionary = data.get("systems", {})
	var loop_data: Dictionary = systems.get("loop_state", {})
	assert_int(int(loop_data.get("current_night", 0))).is_equal(1)


func test_three_slots_independent() -> void:
	_loop_mgr.advance_night()
	_save_mgr.save_game(1)

	_loop_mgr.advance_night()
	_save_mgr.save_game(2)

	_loop_mgr.advance_night()
	_save_mgr.save_game(3)

	_save_mgr.load_game(1)
	assert_int(_loop_mgr.current_night).is_equal(2)

	_save_mgr.load_game(3)
	assert_int(_loop_mgr.current_night).is_equal(4)


func test_has_save_returns_false_when_empty() -> void:
	assert_bool(_save_mgr.has_save(1)).is_false()
	assert_bool(_save_mgr.has_save(2)).is_false()
	assert_bool(_save_mgr.has_save(3)).is_false()


func test_delete_save_removes_files() -> void:
	_save_mgr.save_game(1)
	assert_bool(_save_mgr.has_save(1)).is_true()
	_save_mgr.delete_save(1)
	assert_bool(_save_mgr.has_save(1)).is_false()


func test_save_blocked_during_saving() -> void:
	_save_mgr._is_saving = true
	var ok: bool = _save_mgr.save_game(1)
	assert_bool(ok).is_false()
	_save_mgr._is_saving = false


func test_load_blocked_during_loading() -> void:
	_save_mgr.save_game(1)
	_save_mgr._is_loading = true
	var ok: bool = _save_mgr.load_game(1)
	assert_bool(ok).is_false()
	_save_mgr._is_loading = false


func test_schema_version_in_save() -> void:
	_save_mgr.save_game(1)
	var data: Dictionary = _save_mgr._read_save_file(1)
	assert_dict(data).contains_keys("schema_version")
	assert_int(int(data["schema_version"])).is_equal(1)
	assert_dict(data).contains_keys("systems")
	assert_dict(data["systems"]).contains_keys("loop_state")
