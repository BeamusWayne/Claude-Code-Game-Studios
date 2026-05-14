## NPCManager autoload singleton. Coordinates emotional state, location,
## and dialogue availability for all 5 NPC guests. All state mutations route
## through LoopStateManager's propose_delta() pipeline.
extends Node

signal npc_state_changed(npc_id: StringName, old_state: int, new_state: int)
signal npc_dialogue_availability_changed(npc_id: StringName, available: bool)
signal npc_interaction_requested(npc_id: StringName, event: Dictionary)

enum NPCEmotionalState {
	NEUTRAL,     ## Default calm state. Standard dialogue options.
	CURIOUS,     ## Attracted by player's new clues. Extra dialogue branches.
	ANXIOUS,     ## Feels threatened or uneasy. Avoids sensitive topics.
	HOSTILE,     ## Actively confrontational, refuses to cooperate. Limited dialogue.
	TRUSTING,    ## Has developed trust toward player. Shares hints proactively.
	FRIGHTENED,  ## Extreme fear. Short responses, may reveal critical info.
}

const _NPC_STATE_PATH_PREFIX: StringName = &"npcs"
const _NARRATIVE_DELTA_PRIORITY: int = 10

var _npc_registry: Dictionary = {}  ## Dictionary[StringName, Dictionary] (NPCInstance data)
var _is_initialized: bool = false
var _valid_transitions: Dictionary = {}
var _registered_state_paths: Array[StringName] = []


func _ready() -> void:
	_build_transition_table()
	_initialize_default_npcs()
	_register_state_paths()
	_connect_signals()


func _build_transition_table() -> void:
	_valid_transitions[NPCEmotionalState.NEUTRAL] = [
		NPCEmotionalState.CURIOUS,
		NPCEmotionalState.ANXIOUS,
		NPCEmotionalState.TRUSTING,
	]
	_valid_transitions[NPCEmotionalState.CURIOUS] = [
		NPCEmotionalState.NEUTRAL,
		NPCEmotionalState.TRUSTING,
		NPCEmotionalState.ANXIOUS,
	]
	_valid_transitions[NPCEmotionalState.ANXIOUS] = [
		NPCEmotionalState.HOSTILE,
		NPCEmotionalState.FRIGHTENED,
		NPCEmotionalState.NEUTRAL,
	]
	_valid_transitions[NPCEmotionalState.HOSTILE] = [
		NPCEmotionalState.ANXIOUS,
		NPCEmotionalState.NEUTRAL,
	]
	_valid_transitions[NPCEmotionalState.TRUSTING] = [
		NPCEmotionalState.NEUTRAL,
		NPCEmotionalState.CURIOUS,
		NPCEmotionalState.ANXIOUS,
	]
	_valid_transitions[NPCEmotionalState.FRIGHTENED] = [
		NPCEmotionalState.ANXIOUS,
		NPCEmotionalState.HOSTILE,
		NPCEmotionalState.NEUTRAL,
	]


## Creates placeholder NPCInstance entries for all 5 guests.
func _initialize_default_npcs() -> void:
	var npc_ids: Array[StringName] = _get_all_npc_ids()
	for npc_id: StringName in npc_ids:
		_npc_registry[npc_id] = {
			"npc_id": npc_id,
			"template": null,
			"current_emotional_state": NPCEmotionalState.NEUTRAL,
			"current_location": &"",
			"dialogue_available": true,
			"dialogue_id": &"",
			"metadata": {},
		}


## Registers NPC state paths with LoopStateManager if available.
func _register_state_paths() -> void:
	_registered_state_paths.clear()
	for npc_id: StringName in _get_all_npc_ids():
		_registered_state_paths.append(&"npcs.%s.emotional_state" % npc_id)
		_registered_state_paths.append(&"npcs.%s.location" % npc_id)
		_registered_state_paths.append(&"npcs.%s.dialogue_available" % npc_id)

	var loop_manager: Node = _get_loop_state_manager()
	if loop_manager and loop_manager.has_method("register_state_paths"):
		loop_manager.register_state_paths(_registered_state_paths)


## Connects to LoopStateManager and InteractionBus signals if available.
func _connect_signals() -> void:
	var loop_manager: Node = _get_loop_state_manager()
	if loop_manager:
		if loop_manager.has_signal("night_ready"):
			loop_manager.night_ready.connect(_on_night_ready)
		if loop_manager.has_signal("night_advanced"):
			loop_manager.night_advanced.connect(_on_night_advanced)

	var bus: Node = _get_interaction_bus()
	if bus:
		if bus.has_signal("interaction_detected"):
			bus.interaction_detected.connect(_on_interaction_detected)


## Returns the NPCEmotionalState for the given NPC, or NEUTRAL if unknown.
func get_emotional_state(npc_id: StringName) -> int:
	if not _npc_registry.has(npc_id):
		push_warning("NPCManager: unknown npc_id '%s'" % npc_id)
		return NPCEmotionalState.NEUTRAL
	return _npc_registry[npc_id]["current_emotional_state"]


## Returns whether the NPC is available for dialogue.
func is_dialogue_available(npc_id: StringName) -> bool:
	if not _npc_registry.has(npc_id):
		return false
	return _npc_registry[npc_id]["dialogue_available"]


## Returns the current room location of the NPC.
func get_npc_location(npc_id: StringName) -> StringName:
	if not _npc_registry.has(npc_id):
		return &""
	return _npc_registry[npc_id]["current_location"]


## Returns all registered NPC IDs.
func get_all_npc_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for npc_id: StringName in _npc_registry:
		result.append(npc_id)
	return result


## Returns NPC IDs whose current location matches the given room.
func get_npc_ids_in_room(room_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for npc_id: StringName in _npc_registry:
		if _npc_registry[npc_id]["current_location"] == room_id:
			result.append(npc_id)
	return result


## Registers an NPC with the given template. Overwrites existing entry.
func register_npc(npc_id: StringName, template: NPCTemplate) -> void:
	_npc_registry[npc_id] = {
		"npc_id": npc_id,
		"template": template,
		"current_emotional_state": template.initial_emotional_state,
		"current_location": template.initial_location,
		"dialogue_available": template.is_dialogue_available,
		"dialogue_id": template.dialogue_id,
		"metadata": {},
	}


## Validates and attempts a state transition via propose_delta. Returns true if accepted.
func request_state_transition(npc_id: StringName, new_state: int) -> bool:
	if not _npc_registry.has(npc_id):
		push_warning("NPCManager: transition requested for unknown npc_id '%s'" % npc_id)
		return false

	var instance: Dictionary = _npc_registry[npc_id]
	var current_state: int = instance["current_emotional_state"]

	if current_state == new_state:
		return false

	if not _is_valid_transition(current_state, new_state):
		push_warning("NPCManager: invalid transition %s -> %s for '%s'" % [
			NPCEmotionalState.keys()[current_state],
			NPCEmotionalState.keys()[new_state],
			npc_id,
		])
		return false

	return _apply_state_change(npc_id, new_state, &"npc_state_transition", 0)


## Bypasses transition validation for narrative overrides with elevated priority.
func force_state_transition(npc_id: StringName, new_state: int, narrative_priority: int = _NARRATIVE_DELTA_PRIORITY) -> bool:
	if not _npc_registry.has(npc_id):
		push_warning("NPCManager: force transition for unknown npc_id '%s'" % npc_id)
		return false

	return _apply_state_change(npc_id, new_state, &"npc_narrative_override", narrative_priority)


## Changes dialogue availability via propose_delta.
func set_dialogue_availability(npc_id: StringName, available: bool) -> bool:
	if not _npc_registry.has(npc_id):
		push_warning("NPCManager: dialogue toggle for unknown npc_id '%s'" % npc_id)
		return false

	var path: StringName = &"npcs.%s.dialogue_available" % npc_id
	var accepted: bool = _propose_delta(path, available, &"npc_dialogue_toggle", 0)

	if accepted:
		_npc_registry[npc_id]["dialogue_available"] = available
		npc_dialogue_availability_changed.emit(npc_id, available)

	return accepted


## Initializes NPC state from templates for the given night.
func _initialize_npcs_from_template(night: int) -> void:
	for npc_id: StringName in _get_all_npc_ids():
		var template: NPCTemplate = _load_npc_template(npc_id, night)

		# Apply per_night_overrides from the template if present
		if template and template.per_night_overrides.has(night):
			var override: Dictionary = template.per_night_overrides[night]
			if override.has("emotional_state"):
				template.initial_emotional_state = override["emotional_state"]
			if override.has("location"):
				template.initial_location = override["location"]
			if override.has("dialogue_available"):
				template.is_dialogue_available = override["dialogue_available"]

		var instance: Dictionary = _npc_registry[npc_id]
		instance["template"] = template
		instance["current_location"] = template.initial_location if template else &""
		instance["dialogue_available"] = template.is_dialogue_available if template else true
		instance["dialogue_id"] = template.dialogue_id if template else &""

		# Check LoopStateManager for persisted emotional state from DeltaAccumulator
		var state_path: StringName = &"npcs.%s.emotional_state" % npc_id
		var persisted: Variant = _get_active_state_value(state_path)
		if persisted != null:
			instance["current_emotional_state"] = persisted as int
		elif template:
			instance["current_emotional_state"] = template.initial_emotional_state

	_is_initialized = true


## Validates a state transition using the transition table.
func _is_valid_transition(from: int, to: int) -> bool:
	if not _valid_transitions.has(from):
		return false
	return to in _valid_transitions[from]


## Applies a state change through propose_delta and emits signal on success.
func _apply_state_change(npc_id: StringName, new_state: int, action: StringName, priority: int) -> bool:
	var instance: Dictionary = _npc_registry[npc_id]
	var old_state: int = instance["current_emotional_state"]

	var path: StringName = &"npcs.%s.emotional_state" % npc_id
	var source_night: int = _get_current_night()
	var accepted: bool = _propose_delta(path, new_state, action, priority)

	if accepted:
		instance["current_emotional_state"] = new_state
		npc_state_changed.emit(npc_id, old_state, new_state)

	return accepted


## Proposes a delta to LoopStateManager. Returns true if accepted or if LSM is unavailable.
func _propose_delta(target_path: StringName, value: Variant, action: StringName, priority: int) -> bool:
	var loop_manager: Node = _get_loop_state_manager()
	if loop_manager == null:
		# No LoopStateManager available; accept locally for graceful degradation.
		return true

	if not loop_manager.has_method("propose_delta"):
		# LoopStateManager does not yet implement propose_delta; accept locally.
		return true

	var delta: Dictionary = {
		"source_night": _get_current_night(),
		"source_action": action,
		"target_path": target_path,
		"override_value": value,
		"priority": priority,
	}
	return loop_manager.propose_delta(delta)


## Reads the current night from LoopStateManager, defaulting to 1.
func _get_current_night() -> int:
	var loop_manager: Node = _get_loop_state_manager()
	if loop_manager and "current_night" in loop_manager:
		return loop_manager.current_night
	return 1


## Reads an active state value from LoopStateManager, or null if unavailable.
func _get_active_state_value(state_path: StringName) -> Variant:
	var loop_manager: Node = _get_loop_state_manager()
	if loop_manager and loop_manager.has_method("get_active_state_value"):
		return loop_manager.get_active_state_value(state_path)
	return null


## Loads an NPCTemplate resource for the given NPC and night. Fallback chain:
## night_N -> night_1 -> registered template -> programmatic default.
func _load_npc_template(npc_id: StringName, night: int) -> NPCTemplate:
	var path: String = "res://assets/data/npcs/%s/night_%d.tres" % [npc_id, night]
	if ResourceLoader.exists(path):
		var loaded: Resource = load(path)
		if loaded is NPCTemplate:
			return loaded as NPCTemplate

	var fallback_path: String = "res://assets/data/npcs/%s/night_1.tres" % npc_id
	if ResourceLoader.exists(fallback_path):
		var loaded: Resource = load(fallback_path)
		if loaded is NPCTemplate:
			return loaded as NPCTemplate

	# Check registry for a pre-registered template before falling back to default
	if _npc_registry.has(npc_id) and _npc_registry[npc_id]["template"] != null:
		return _npc_registry[npc_id]["template"] as NPCTemplate

	push_warning("NPCManager: no template found for '%s' night %d, using default" % [npc_id, night])
	var default_template := NPCTemplate.new()
	default_template.npc_id = npc_id
	default_template.display_name = String(npc_id)
	default_template.initial_emotional_state = NPCEmotionalState.NEUTRAL
	default_template.is_dialogue_available = true
	return default_template


## Returns the canonical list of all 5 NPC IDs.
func _get_all_npc_ids() -> Array[StringName]:
	return [&"guest_indigo", &"guest_ochre", &"guest_vermilion",
			&"guest_celadon", &"guest_plum"]


## Returns the LoopStateManager autoload if available.
func _get_loop_state_manager() -> Node:
	return get_node_or_null("/root/LoopStateManager")


## Returns the InteractionBus autoload if available.
func _get_interaction_bus() -> Node:
	return get_node_or_null("/root/InteractionBus")


## Filters InteractionBus events for NPC targets and re-emits.
func _handle_npc_interaction(event: Dictionary) -> void:
	if event.get("target_type", &"") != &"npc":
		return
	var npc_id: StringName = event.get("target_id", &"")
	if not _npc_registry.has(npc_id):
		return
	npc_interaction_requested.emit(npc_id, event)


## Serializes all NPC state to a Dictionary for save/load.
func serialize() -> Dictionary:
	var npcs: Array = []
	for npc_id: StringName in _npc_registry:
		var instance: Dictionary = _npc_registry[npc_id]
		npcs.append({
			"npc_id": String(npc_id),
			"current_emotional_state": instance["current_emotional_state"],
			"current_location": String(instance["current_location"]),
			"dialogue_available": instance["dialogue_available"],
			"dialogue_id": String(instance["dialogue_id"]),
		})
	return {
		"schema_version": 1,
		"is_initialized": _is_initialized,
		"npcs": npcs,
	}


## Restores NPC state from a serialized Dictionary.
func deserialize(data: Dictionary) -> bool:
	if data.is_empty():
		return false

	var npcs: Array = data.get("npcs", [])
	_npc_registry.clear()

	for entry: Dictionary in npcs:
		var npc_id: StringName = StringName(entry.get("npc_id", ""))
		if npc_id == &"":
			continue

		var template: NPCTemplate = _load_npc_template(npc_id, _get_current_night())
		_npc_registry[npc_id] = {
			"npc_id": npc_id,
			"template": template,
			"current_emotional_state": int(entry.get("current_emotional_state", NPCEmotionalState.NEUTRAL)),
			"current_location": StringName(entry.get("current_location", "")),
			"dialogue_available": bool(entry.get("dialogue_available", true)),
			"dialogue_id": StringName(entry.get("dialogue_id", "")),
			"metadata": {},
		}

	_is_initialized = data.get("is_initialized", false)
	return true


## Resets all NPC state to defaults.
func reset() -> void:
	_npc_registry.clear()
	_is_initialized = false
	_initialize_default_npcs()


# --- Signal callbacks ---

func _on_night_ready(night: int) -> void:
	if _is_initialized:
		return
	_initialize_npcs_from_template(night)


func _on_night_advanced(old_night: int, new_night: int) -> void:
	_is_initialized = false
	_initialize_npcs_from_template(new_night)


func _on_interaction_detected(event: Dictionary) -> void:
	_handle_npc_interaction(event)
