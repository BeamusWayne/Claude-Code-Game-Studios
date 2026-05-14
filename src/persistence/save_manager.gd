extends Node

signal save_completed(slot_id: int)
signal save_failed(slot_id: int, reason: String)
signal load_completed(slot_id: int)
signal load_failed(slot_id: int, reason: String)
signal auto_save_completed()

const SCHEMA_VERSION: int = 1
const SAVE_FILE_PREFIX: String = "save_"
const SAVE_FILE_EXTENSION: String = ".json"
const BACKUP_EXTENSION: String = ".bak"
const TEMP_EXTENSION: String = ".tmp"
const NUM_SLOTS: int = 3

var current_slot: int = -1
var _is_saving: bool = false
var _is_loading: bool = false
var _last_auto_save_time: float = 0.0
var _loop_state_ref: Node = null
const AUTO_SAVE_DEBOUNCE: float = 2.0


func _ready() -> void:
	_resolve_references()


func set_loop_state_manager(ref: Node) -> void:
	_loop_state_ref = ref
	if ref:
		ref.night_advanced.connect(_on_night_advanced)
		ref.consequence_registered.connect(_on_consequence_registered)


func _on_night_advanced(_old_night: int, _new_night: int) -> void:
	_auto_save()


func _on_consequence_registered(_id: StringName) -> void:
	_auto_save()


func _resolve_references() -> void:
	var tree := get_tree()
	if tree and tree.root:
		for child in tree.root.get_children():
			if child.name == "LoopStateManager":
				_loop_state_ref = child
				return


func save_game(slot_id: int) -> bool:
	if _is_saving or _is_loading:
		save_failed.emit(slot_id, "operation_in_progress")
		return false
	var loop_mgr = _get_loop_state_manager()
	if loop_mgr and loop_mgr.is_transitioning:
		save_failed.emit(slot_id, "loop_transitioning")
		return false
	_is_saving = true

	var systems := _collect_snapshots()
	var envelope := _build_save_envelope(slot_id, systems)
	var json_string := JSON.stringify(envelope, "\t")

	var ok := _atomic_write(slot_id, json_string)
	_is_saving = false

	if ok:
		save_completed.emit(slot_id)
	else:
		save_failed.emit(slot_id, "write_failed")
	return ok


func load_game(slot_id: int) -> bool:
	if _is_loading or _is_saving:
		load_failed.emit(slot_id, "operation_in_progress")
		return false
	_is_loading = true

	var data := _read_save_file(slot_id)
	if data.is_empty():
		_is_loading = false
		load_failed.emit(slot_id, "no_save_or_corrupt")
		return false

	data = _migrate_save(data)
	current_slot = slot_id
	_distribute_snapshots(data.get("systems", {}))
	_is_loading = false
	load_completed.emit(slot_id)
	return true


func new_game(slot_id: int) -> void:
	current_slot = slot_id
	var loop_mgr = _get_loop_state_manager()
	if loop_mgr:
		loop_mgr.reset()
	save_game(slot_id)


func delete_save(slot_id: int) -> bool:
	var paths := [_get_save_path(slot_id), _get_backup_path(slot_id)]
	var any_deleted := false
	for path in paths:
		if FileAccess.file_exists(path):
			var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			if err == OK:
				any_deleted = true
	return any_deleted


func has_save(slot_id: int) -> bool:
	return FileAccess.file_exists(_get_save_path(slot_id)) or FileAccess.file_exists(_get_backup_path(slot_id))


func get_save_metadata(slot_id: int) -> Dictionary:
	var data := _read_save_file(slot_id)
	if data.is_empty():
		return {"slot_id": slot_id, "exists": false}
	var systems: Dictionary = data.get("systems", {})
	var loop_data: Dictionary = systems.get("loop_state", {})
	return {
		"slot_id": slot_id,
		"exists": true,
		"timestamp": data.get("timestamp", ""),
		"game_version": data.get("game_version", ""),
		"current_night": loop_data.get("current_night", 1),
	}


func get_all_save_metadata() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(1, NUM_SLOTS + 1):
		result.append(get_save_metadata(i))
	return result


func _get_save_path(slot_id: int) -> String:
	return "user://%s%d%s" % [SAVE_FILE_PREFIX, slot_id, SAVE_FILE_EXTENSION]


func _get_backup_path(slot_id: int) -> String:
	return "user://%s%d%s" % [SAVE_FILE_PREFIX, slot_id, BACKUP_EXTENSION]


func _get_temp_path(slot_id: int) -> String:
	return "user://%s%d%s" % [SAVE_FILE_PREFIX, slot_id, TEMP_EXTENSION]


func _atomic_write(slot_id: int, json_string: String) -> bool:
	_rotate_backup(slot_id)

	var tmp_path := _get_temp_path(slot_id)
	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: failed to open '%s': %s" % [tmp_path, FileAccess.get_open_error()])
		return false
	file.store_string(json_string)
	file.close()

	var save_path := _get_save_path(slot_id)
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp_path), ProjectSettings.globalize_path(save_path))
	if err != OK:
		push_error("SaveManager: rename failed: %d" % err)
		return false
	return true


func _rotate_backup(slot_id: int) -> bool:
	var save_path := _get_save_path(slot_id)
	if not FileAccess.file_exists(save_path):
		return true
	var backup_path := _get_backup_path(slot_id)
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(backup_path))
	return err == OK


func _read_save_file(slot_id: int) -> Dictionary:
	var save_path := _get_save_path(slot_id)
	var data := _read_json_file(save_path)
	if not data.is_empty():
		return data
	return _read_json_file(_get_backup_path(slot_id))


func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var content := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(content) != OK:
		push_warning("SaveManager: failed to parse '%s'" % path)
		return {}
	return json.data if json.data is Dictionary else {}


func _migrate_save(data: Dictionary) -> Dictionary:
	var version: int = data.get("schema_version", 1)
	while version < SCHEMA_VERSION:
		var migrator_name: String = "_migrate_%d_to_%d" % [version, version + 1]
		if has_method(migrator_name):
			data = call(migrator_name, data)
		else:
			push_warning("SaveManager: no migration from schema %d to %d" % [version, version + 1])
			break
		version += 1
	data["schema_version"] = SCHEMA_VERSION
	return data


func _collect_snapshots() -> Dictionary:
	var systems: Dictionary = {}
	var loop_mgr = _get_loop_state_manager()
	if loop_mgr:
		systems["loop_state"] = loop_mgr.serialize()
	return systems


func _distribute_snapshots(systems: Dictionary) -> void:
	if systems.has("loop_state"):
		var loop_mgr = _get_loop_state_manager()
		if loop_mgr:
			loop_mgr.deserialize(systems["loop_state"])


func _get_loop_state_manager() -> Node:
	if _loop_state_ref and is_instance_valid(_loop_state_ref):
		return _loop_state_ref
	_resolve_references()
	return _loop_state_ref


func _build_save_envelope(slot_id: int, systems: Dictionary) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"timestamp": Time.get_datetime_string_from_system(),
		"unix_timestamp": Time.get_unix_time_from_system(),
		"slot_id": slot_id,
		"game_version": ProjectSettings.get_setting("application/config/version", "0.1.0"),
		"systems": systems,
	}


func _auto_save() -> void:
	if current_slot < 0 or _is_saving or _is_loading:
		return
	var now := Time.get_unix_time_from_system()
	if now - _last_auto_save_time < AUTO_SAVE_DEBOUNCE:
		return
	_last_auto_save_time = now
	save_game(current_slot)
	auto_save_completed.emit()
