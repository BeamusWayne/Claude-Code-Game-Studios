extends Node

signal night_advanced(old_night: int, new_night: int)
signal night_advanced_failed(reason: String)
signal night_ready(night: int)
signal advance_failed(step: int, error: String)
signal consequence_registered(consequence_id: StringName)
signal consequence_replayed(consequence_id: StringName)

enum NightPhase { WHISPER, ROAR, TRANSITION }

const MAX_NIGHTS: int = 7

var current_night: int = 1
var current_phase: NightPhase = NightPhase.WHISPER
var is_transitioning: bool = false

var _consequences: Array[Dictionary] = []
var _template_overrides: Dictionary = {}


func get_current_night() -> int:
	return current_night


func get_night_phase_duration() -> float:
	match current_phase:
		NightPhase.WHISPER:
			return 180.0
		NightPhase.ROAR:
			return 120.0
		NightPhase.TRANSITION:
			return 0.0
	return 0.0


func set_phase(phase: NightPhase) -> void:
	current_phase = phase


func register_consequence(consequence_id: StringName, mutation: Dictionary) -> void:
	# Immutable: build new array instead of mutating in-place.
	# Callers may still hold references to the old array/dictionaries
	# and must not see them silently change.
	for i: int in _consequences.size():
		if _consequences[i]["id"] == consequence_id:
			push_warning("LoopStateManager: consequence '%s' already registered, updating" % consequence_id)
			var updated: Array[Dictionary] = []
			for j: int in _consequences.size():
				if j == i:
					updated.append({
						"id": _consequences[i]["id"],
						"mutation": mutation.duplicate(true),
					})
				else:
					updated.append(_consequences[j])
			_consequences = updated
			return
	var new_consequences: Array[Dictionary] = []
	for entry: Dictionary in _consequences:
		new_consequences.append(entry)
	new_consequences.append({
		"id": consequence_id,
		"mutation": mutation.duplicate(true),
	})
	_consequences = new_consequences
	consequence_registered.emit(consequence_id)


func get_template_override(entity_id: StringName, property: String) -> Variant:
	var key: String = "%s.%s" % [entity_id, property]
	if _template_overrides.has(key):
		return _template_overrides[key]
	return null


func advance_night() -> bool:
	if current_night >= MAX_NIGHTS:
		night_advanced_failed.emit("already_at_max_night")
		advance_failed.emit(1, "Cannot advance past night %d" % MAX_NIGHTS)
		return false
	if is_transitioning:
		night_advanced_failed.emit("transition_in_progress")
		advance_failed.emit(1, "advance_night already in progress")
		return false

	is_transitioning = true

	var _snapshot_night := current_night
	var _snapshot_phase := current_phase
	var _snapshot_consequences := _consequences.duplicate(true)
	var _snapshot_overrides := _template_overrides.duplicate(true)

	_apply_consequences()

	var old_night := current_night
	current_night += 1

	current_phase = NightPhase.WHISPER
	is_transitioning = false
	night_advanced.emit(old_night, current_night)
	night_ready.emit(current_night)
	return true


func rollback(snapshot: Dictionary) -> void:
	current_night = snapshot["night"]
	current_phase = snapshot["phase"]
	_consequences.assign(snapshot["consequences"])
	_template_overrides = snapshot["overrides"]
	is_transitioning = false


func _apply_consequences() -> void:
	_template_overrides.clear()
	for entry in _consequences:
		var mutation: Dictionary = entry["mutation"]
		var target: StringName = mutation.get("target", &"")
		var property: String = mutation.get("property", "")
		var value: Variant = mutation.get("value", null)
		var affects_nights: Array = mutation.get("affects_nights", [])
		if affects_nights.is_empty() or current_night + 1 in affects_nights:
			var key: String = "%s.%s" % [target, property]
			_template_overrides[key] = value
		consequence_replayed.emit(entry["id"])


func serialize() -> Dictionary:
	var serialized_consequences: Array = []
	for entry in _consequences:
		serialized_consequences.append({
			"id": String(entry["id"]),
			"mutation": entry["mutation"],
		})
	return {
		"schema_version": 1,
		"current_night": current_night,
		"current_phase": "WHISPER" if current_phase == NightPhase.WHISPER else "ROAR" if current_phase == NightPhase.ROAR else "TRANSITION",
		"consequences": serialized_consequences,
		"template_overrides": _template_overrides,
		"delta_accumulator": {"deltas": []},
	}


func deserialize(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	current_night = data.get("current_night", 1)
	var phase_str: String = data.get("current_phase", "WHISPER")
	match phase_str:
		"WHISPER":
			current_phase = NightPhase.WHISPER
		"ROAR":
			current_phase = NightPhase.ROAR
		"TRANSITION":
			current_phase = NightPhase.TRANSITION
	_consequences.clear()
	for entry in data.get("consequences", []):
		_consequences.append({
			"id": StringName(entry["id"]),
			"mutation": entry["mutation"],
		})
	_template_overrides = data.get("template_overrides", {})
	return true


func reset() -> void:
	current_night = 1
	current_phase = NightPhase.WHISPER
	is_transitioning = false
	_consequences.clear()
	_template_overrides.clear()
	night_ready.emit(1)
