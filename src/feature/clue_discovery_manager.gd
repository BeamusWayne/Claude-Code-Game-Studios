extends Node

## ClueDiscoveryManager — autoload singleton that handles clue discovery from
## player interactions. Listens to InteractionBus, validates ClueDefinition
## conditions (prerequisite clues, NPC presence, night range), and registers
## discoveries to ClueDatabase. GDD: design/gdd/clue-discovery.md

signal clue_discovered(clue_id: StringName, clue_data: Dictionary)

var _clue_registry: Dictionary = {}  ## Dictionary[StringName, Dictionary] (ClueDefinition data)
var _room_index: Dictionary = {}  ## Dictionary[StringName, Array[StringName]] (room_id -> clue_ids)
var _interactable_index: Dictionary = {}  ## Dictionary[StringName, StringName] (interactable_id -> clue_id)


func _ready() -> void:
	_connect_signals()


func _connect_signals() -> void:
	var bus: Node = _get_interaction_bus()
	if bus and bus.has_signal("interaction_detected"):
		bus.interaction_detected.connect(_on_interaction_detected)


## Registers a ClueDefinition for discovery. Call during room setup.
func register_clue(clue_id: StringName, definition: Dictionary) -> void:
	_clue_registry[clue_id] = definition
	var room_id: StringName = definition.get("room_id", &"")
	if room_id != &"":
		if not _room_index.has(room_id):
			_room_index[room_id] = []
		if not clue_id in _room_index[room_id]:
			_room_index[room_id].append(clue_id)
	var interactable_id: StringName = definition.get("interactable_id", &"")
	if interactable_id != &"":
		_interactable_index[interactable_id] = clue_id


## Unregisters a ClueDefinition.
func unregister_clue(clue_id: StringName) -> void:
	if not _clue_registry.has(clue_id):
		return
	var definition: Dictionary = _clue_registry[clue_id]
	var room_id: StringName = definition.get("room_id", &"")
	if room_id != &"" and _room_index.has(room_id):
		_room_index[room_id].erase(clue_id)
		if _room_index[room_id].is_empty():
			_room_index.erase(room_id)
	var interactable_id: StringName = definition.get("interactable_id", &"")
	if interactable_id != &"" and _interactable_index.get(interactable_id, &"") == clue_id:
		_interactable_index.erase(interactable_id)
	_clue_registry.erase(clue_id)


## Returns true if a ClueDefinition is registered for the given clue_id.
func has_definition(clue_id: StringName) -> bool:
	return _clue_registry.has(clue_id)


## Returns the ClueDefinition for the given clue_id, or empty dict.
func get_definition(clue_id: StringName) -> Dictionary:
	return _clue_registry.get(clue_id, {})


## Returns all clue IDs registered for the given room.
func get_clues_for_room(room_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	if _room_index.has(room_id):
		for clue_id: StringName in _room_index[room_id]:
			result.append(clue_id)
	return result


## Returns the clue_id associated with the given interactable, or &"".
func get_clue_for_interactable(interactable_id: StringName) -> StringName:
	return _interactable_index.get(interactable_id, &"")


## Checks whether a clue can be discovered given current game state.
func can_discover(clue_id: StringName) -> bool:
	if not _clue_registry.has(clue_id):
		return false
	var db: Node = _get_clue_database()
	if db and db.has_method("has_clue") and db.has_clue(clue_id):
		return false
	var definition: Dictionary = _clue_registry[clue_id]
	return _check_conditions(definition)


## Force-discover a clue (e.g. for debugging). Returns true if successful.
func force_discover(clue_id: StringName) -> bool:
	if not _clue_registry.has(clue_id):
		return false
	var db: Node = _get_clue_database()
	if db and db.has_method("has_clue") and db.has_clue(clue_id):
		return false
	return _execute_discovery(clue_id)


## Called when InteractionBus.interaction_detected fires.
func _on_interaction_detected(event: Dictionary) -> void:
	var target_id: StringName = event.get("target_id", &"")
	if target_id == &"":
		return
	if not _interactable_index.has(target_id):
		return
	var clue_id: StringName = _interactable_index[target_id]
	if not _clue_registry.has(clue_id):
		return
	var db: Node = _get_clue_database()
	if db and db.has_method("has_clue") and db.has_clue(clue_id):
		return
	if not _check_conditions(_clue_registry[clue_id]):
		return
	_execute_discovery(clue_id)


## Validates all discovery conditions for a clue definition.
func _check_conditions(definition: Dictionary) -> bool:
	var conditions: Dictionary = definition.get("discovery_conditions", {})
	if conditions.is_empty():
		return true
	var db: Node = _get_clue_database()
	# must_have_clues
	var must_have: Array = conditions.get("must_have_clues", [])
	for required_clue: StringName in must_have:
		if db == null or not db.has_method("has_clue") or not db.has_clue(required_clue):
			return false
	# npc_in_room
	var required_npc: StringName = conditions.get("npc_in_room", &"")
	if required_npc != &"":
		var npc_manager: Node = _get_npc_manager()
		if npc_manager == null or not npc_manager.has_method("get_npc_location"):
			return false
		var current_room: StringName = _get_current_room()
		if npc_manager.get_npc_location(required_npc) != current_room:
			return false
	# night_range
	var night_range: Vector2i = conditions.get("night_range", Vector2i(0, 0))
	var current_night: int = _get_current_night()
	if night_range.x != 0 and current_night < night_range.x:
		return false
	if night_range.y != 0 and current_night > night_range.y:
		return false
	return true


## Executes the discovery: creates a ClueDatabase entry and emits signal.
func _execute_discovery(clue_id: StringName) -> bool:
	var definition: Dictionary = _clue_registry[clue_id]
	var db: Node = _get_clue_database()
	if db == null or not db.has_method("add_entry"):
		push_warning("ClueDiscoveryManager: ClueDatabase unavailable")
		return false
	var entry: Dictionary = {
		"id": clue_id,
		"entry_type": 0,  # ClueDatabase.EntryType.CLUE
		"title": definition.get("display_name", ""),
		"description": definition.get("description", ""),
		"source": definition.get("room_id", &""),
		"discovered_at_night": _get_current_night(),
		"npc_affinity": definition.get("npc_affinity", &""),
		"tags": definition.get("tags", []),
		"contextual_unlocks": [],
		"metadata": {
			"interactable_id": definition.get("interactable_id", &""),
			"associated_insight_ids": definition.get("associated_insight_ids", []),
			"weight": definition.get("weight", 1.0),
		},
	}
	if not db.add_entry(entry):
		return false
	clue_discovered.emit(clue_id, definition)
	return true


# -- Serialization -----------------------------------------------------------

func serialize() -> Dictionary:
	var serialized_registry: Dictionary = {}
	for clue_id: StringName in _clue_registry:
		serialized_registry[String(clue_id)] = _clue_registry[clue_id]
	return {"clue_registry": serialized_registry}


func deserialize(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	_clue_registry.clear()
	_room_index.clear()
	_interactable_index.clear()
	var raw: Dictionary = data.get("clue_registry", {})
	for key: String in raw:
		var clue_id: StringName = StringName(key)
		register_clue(clue_id, raw[key])
	return true


func reset() -> void:
	_clue_registry.clear()
	_room_index.clear()
	_interactable_index.clear()


# -- DI seams (override in tests) --------------------------------------------

func _get_interaction_bus() -> Node:
	return get_node_or_null("/root/InteractionBus")


func _get_clue_database() -> Node:
	return get_node_or_null("/root/ClueDatabase")


func _get_npc_manager() -> Node:
	return get_node_or_null("/root/NPCManager")


func _get_loop_state_manager() -> Node:
	return get_node_or_null("/root/LoopStateManager")


func _get_current_night() -> int:
	var loop_state: Node = _get_loop_state_manager()
	if loop_state and loop_state.has_method("get_current_night"):
		return loop_state.get_current_night()
	return 1


func _get_current_room() -> StringName:
	var room_manager: Node = get_node_or_null("/root/RoomManager")
	if room_manager and room_manager.has_method("get_active_room_id"):
		return room_manager.get_active_room_id()
	return &""
