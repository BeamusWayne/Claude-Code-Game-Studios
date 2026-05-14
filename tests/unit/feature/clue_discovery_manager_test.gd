extends GdUnitTestSuite

## Tests for ClueDiscoveryManager — clue discovery from interactions,
## condition validation, registry management, serialization.
## Covers GDD acceptance criteria from design/gdd/clue-discovery.md.

const CDM_SCRIPT := "res://src/feature/clue_discovery_manager.gd"

var _manager: Node
var _mock_bus: Node
var _mock_db: Node
var _mock_npc: Node
var _mock_loop: Node
var _mock_room: Node

var _discovered_events: Array


func before_test() -> void:
	_mock_bus = Node.new()
	_mock_bus.name = "InteractionBus"
	_mock_bus.set_script(_create_bus_mock())
	add_child(_mock_bus)

	_mock_db = Node.new()
	_mock_db.name = "ClueDatabase"
	_mock_db.set_script(_create_db_mock())
	add_child(_mock_db)

	_mock_npc = Node.new()
	_mock_npc.name = "NPCManager"
	_mock_npc.set_script(_create_npc_mock())
	add_child(_mock_npc)

	_mock_loop = Node.new()
	_mock_loop.name = "LoopStateManager"
	_mock_loop.set_script(_create_loop_mock())
	add_child(_mock_loop)

	_mock_room = Node.new()
	_mock_room.name = "RoomManager"
	_mock_room.set_script(_create_room_mock())
	add_child(_mock_room)

	var wrapper := GDScript.new()
	wrapper.source_code = (
		"extends \"%s\"\n" % CDM_SCRIPT
		+ "var _test_bus: Node = null\n"
		+ "var _test_db: Node = null\n"
		+ "var _test_npc: Node = null\n"
		+ "var _test_loop: Node = null\n"
		+ "var _test_room: Node = null\n"
		+ "func _get_interaction_bus() -> Node:\n"
		+ "\treturn _test_bus\n"
		+ "func _get_clue_database() -> Node:\n"
		+ "\treturn _test_db\n"
		+ "func _get_npc_manager() -> Node:\n"
		+ "\treturn _test_npc\n"
		+ "func _get_loop_state_manager() -> Node:\n"
		+ "\treturn _test_loop\n"
		+ "func _get_current_room() -> StringName:\n"
		+ "\tvar rm: Node = _test_room\n"
		+ "\tif rm and rm.has_method('get_active_room_id'):\n"
		+ "\t\treturn rm.get_active_room_id()\n"
		+ "\treturn &''\n"
	)
	wrapper.reload()

	_manager = Node.new()
	_manager.set_script(wrapper)
	_manager._test_bus = _mock_bus
	_manager._test_db = _mock_db
	_manager._test_npc = _mock_npc
	_manager._test_loop = _mock_loop
	_manager._test_room = _mock_room
	_manager.name = "ClueDiscoveryManagerTest"
	add_child(_manager)

	_discovered_events = []
	_manager.clue_discovered.connect(_on_clue_discovered)


func _on_clue_discovered(clue_id: StringName, _data: Dictionary) -> void:
	_discovered_events.append(clue_id)


func after_test() -> void:
	if _manager:
		_manager.queue_free()
	if _mock_bus:
		_mock_bus.queue_free()
	if _mock_db:
		_mock_db.queue_free()
	if _mock_npc:
		_mock_npc.queue_free()
	if _mock_loop:
		_mock_loop.queue_free()
	if _mock_room:
		_mock_room.queue_free()


# ---------------------------------------------------------------------------
# Mock Scripts
# ---------------------------------------------------------------------------


func _create_bus_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal interaction_detected(event: Dictionary)\n"
	)
	script.reload()
	return script


func _create_db_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal clue_discovered(clue_id: StringName)\n"
		+ "signal insight_generated(insight_id: StringName)\n"
		+ "var _clues: Dictionary = {}\n"
		+ "var _entries: Dictionary = {}\n"
		+ "func has_clue(id: StringName) -> bool:\n"
		+ "\treturn _clues.has(id)\n"
		+ "func add_entry(entry: Dictionary) -> bool:\n"
		+ "\tvar eid: StringName = entry.get('id', &'')\n"
		+ "\tif eid == &'': return false\n"
		+ "\tif _entries.has(eid): return false\n"
		+ "\t_entries[eid] = entry\n"
		+ "\t_clues[eid] = true\n"
		+ "\treturn true\n"
		+ "func get_entry(id: StringName) -> Dictionary:\n"
		+ "\treturn _entries.get(id, {})\n"
	)
	script.reload()
	return script


func _create_npc_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var _locations: Dictionary = {}\n"
		+ "func get_npc_location(npc_id: StringName) -> StringName:\n"
		+ "\treturn _locations.get(npc_id, &'')\n"
		+ "func set_npc_location(npc_id: StringName, room: StringName) -> void:\n"
		+ "\t_locations[npc_id] = room\n"
	)
	script.reload()
	return script


func _create_loop_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var current_night: int = 1\n"
		+ "func get_current_night() -> int:\n"
		+ "\treturn current_night\n"
	)
	script.reload()
	return script


func _create_room_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var active_room: StringName = &'study'\n"
		+ "func get_active_room_id() -> StringName:\n"
		+ "\treturn active_room\n"
	)
	script.reload()
	return script


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _make_definition(clue_id: StringName, interactable_id: StringName, room_id: StringName = &"study", conditions: Dictionary = {}) -> Dictionary:
	return {
		"clue_id": clue_id,
		"display_name": "Test Clue",
		"description": "A test clue.",
		"room_id": room_id,
		"interactable_id": interactable_id,
		"discovery_conditions": conditions,
		"associated_insight_ids": [],
		"weight": 1.0,
		"npc_affinity": &"",
		"tags": [],
	}


# ---------------------------------------------------------------------------
# Tests: Registry
# ---------------------------------------------------------------------------


func test_register_clue() -> void:
	var def := _make_definition(&"clue_1", &"desk")
	_manager.register_clue(&"clue_1", def)
	assert_bool(_manager.has_definition(&"clue_1")).is_true()
	assert_dict(_manager.get_definition(&"clue_1")).is_not_empty()


func test_unregister_clue() -> void:
	var def := _make_definition(&"clue_1", &"desk")
	_manager.register_clue(&"clue_1", def)
	_manager.unregister_clue(&"clue_1")
	assert_bool(_manager.has_definition(&"clue_1")).is_false()


func test_get_clues_for_room() -> void:
	_manager.register_clue(&"clue_1", _make_definition(&"clue_1", &"desk", &"study"))
	_manager.register_clue(&"clue_2", _make_definition(&"clue_2", &"shelf", &"study"))
	_manager.register_clue(&"clue_3", _make_definition(&"clue_3", &"bed", &"bedroom"))
	var study_clues: Array[StringName] = _manager.get_clues_for_room(&"study")
	assert_int(study_clues.size()).is_equal(2)


func test_get_clue_for_interactable() -> void:
	_manager.register_clue(&"clue_1", _make_definition(&"clue_1", &"desk"))
	assert_str(String(_manager.get_clue_for_interactable(&"desk"))).is_equal("clue_1")
	assert_str(String(_manager.get_clue_for_interactable(&"unknown"))).is_equal("")


# ---------------------------------------------------------------------------
# Tests: Discovery (unconditional)
# ---------------------------------------------------------------------------


func test_unconditional_discovery() -> void:
	_manager.register_clue(&"clue_1", _make_definition(&"clue_1", &"desk"))
	var event := {"target_id": &"desk"}
	_manager._on_interaction_detected(event)
	assert_int(_discovered_events.size()).is_equal(1)
	assert_str(String(_discovered_events[0])).is_equal("clue_1")


func test_duplicate_discovery_prevented() -> void:
	_manager.register_clue(&"clue_1", _make_definition(&"clue_1", &"desk"))
	_manager._on_interaction_detected({"target_id": &"desk"})
	_manager._on_interaction_detected({"target_id": &"desk"})
	assert_int(_discovered_events.size()).is_equal(1)


func test_no_clue_for_interactable() -> void:
	_manager._on_interaction_detected({"target_id": &"unknown"})
	assert_int(_discovered_events.size()).is_equal(0)


func test_empty_target_id_ignored() -> void:
	_manager._on_interaction_detected({})
	assert_int(_discovered_events.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Tests: must_have_clues condition
# ---------------------------------------------------------------------------


func test_must_have_clues_blocks_discovery() -> void:
	var conditions := {"must_have_clues": [&"prerequisite_clue"]}
	_manager.register_clue(&"clue_2", _make_definition(&"clue_2", &"shelf", &"study", conditions))
	_manager._on_interaction_detected({"target_id": &"shelf"})
	assert_int(_discovered_events.size()).is_equal(0)


func test_must_have_clues_allows_discovery_when_met() -> void:
	_mock_db._clues[&"prerequisite_clue"] = true
	var conditions := {"must_have_clues": [&"prerequisite_clue"]}
	_manager.register_clue(&"clue_2", _make_definition(&"clue_2", &"shelf", &"study", conditions))
	_manager._on_interaction_detected({"target_id": &"shelf"})
	assert_int(_discovered_events.size()).is_equal(1)


# ---------------------------------------------------------------------------
# Tests: npc_in_room condition
# ---------------------------------------------------------------------------


func test_npc_in_room_blocks_when_absent() -> void:
	var conditions := {"npc_in_room": &"guest_indigo"}
	_manager.register_clue(&"clue_3", _make_definition(&"clue_3", &"desk", &"study", conditions))
	_mock_npc.set_npc_location(&"guest_indigo", &"garden")
	_manager._on_interaction_detected({"target_id": &"desk"})
	assert_int(_discovered_events.size()).is_equal(0)


func test_npc_in_room_allows_when_present() -> void:
	var conditions := {"npc_in_room": &"guest_indigo"}
	_manager.register_clue(&"clue_3", _make_definition(&"clue_3", &"desk", &"study", conditions))
	_mock_npc.set_npc_location(&"guest_indigo", &"study")
	_manager._on_interaction_detected({"target_id": &"desk"})
	assert_int(_discovered_events.size()).is_equal(1)


# ---------------------------------------------------------------------------
# Tests: night_range condition
# ---------------------------------------------------------------------------


func test_night_range_blocks_when_too_early() -> void:
	_mock_loop.current_night = 1
	var conditions := {"night_range": Vector2i(3, 5)}
	_manager.register_clue(&"clue_4", _make_definition(&"clue_4", &"desk", &"study", conditions))
	_manager._on_interaction_detected({"target_id": &"desk"})
	assert_int(_discovered_events.size()).is_equal(0)


func test_night_range_allows_when_in_range() -> void:
	_mock_loop.current_night = 4
	var conditions := {"night_range": Vector2i(3, 5)}
	_manager.register_clue(&"clue_4", _make_definition(&"clue_4", &"desk", &"study", conditions))
	_manager._on_interaction_detected({"target_id": &"desk"})
	assert_int(_discovered_events.size()).is_equal(1)


func test_night_range_blocks_when_past_range() -> void:
	_mock_loop.current_night = 6
	var conditions := {"night_range": Vector2i(3, 5)}
	_manager.register_clue(&"clue_4", _make_definition(&"clue_4", &"desk", &"study", conditions))
	_manager._on_interaction_detected({"target_id": &"desk"})
	assert_int(_discovered_events.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Tests: can_discover
# ---------------------------------------------------------------------------


func test_can_discover_returns_true_for_valid() -> void:
	_manager.register_clue(&"clue_1", _make_definition(&"clue_1", &"desk"))
	assert_bool(_manager.can_discover(&"clue_1")).is_true()


func test_can_discover_returns_false_for_unknown() -> void:
	assert_bool(_manager.can_discover(&"unknown")).is_false()


func test_can_discover_returns_false_if_already_discovered() -> void:
	_manager.register_clue(&"clue_1", _make_definition(&"clue_1", &"desk"))
	_manager._on_interaction_detected({"target_id": &"desk"})
	assert_bool(_manager.can_discover(&"clue_1")).is_false()


# ---------------------------------------------------------------------------
# Tests: force_discover
# ---------------------------------------------------------------------------


func test_force_discover_succeeds() -> void:
	_manager.register_clue(&"clue_1", _make_definition(&"clue_1", &"desk"))
	assert_bool(_manager.force_discover(&"clue_1")).is_true()
	assert_int(_discovered_events.size()).is_equal(1)


func test_force_discover_fails_for_unknown() -> void:
	assert_bool(_manager.force_discover(&"unknown")).is_false()


func test_force_discover_fails_if_already_discovered() -> void:
	_manager.register_clue(&"clue_1", _make_definition(&"clue_1", &"desk"))
	_manager.force_discover(&"clue_1")
	assert_bool(_manager.force_discover(&"clue_1")).is_false()


# ---------------------------------------------------------------------------
# Tests: Serialize / Deserialize / Reset
# ---------------------------------------------------------------------------


func test_serialize_roundtrip() -> void:
	_manager.register_clue(&"clue_1", _make_definition(&"clue_1", &"desk"))
	var data: Dictionary = _manager.serialize()
	assert_bool(data.has("clue_registry")).is_true()

	var new_manager: Node = Node.new()
	var wrapper := GDScript.new()
	wrapper.source_code = "extends \"%s\"" % CDM_SCRIPT
	wrapper.reload()
	new_manager.set_script(wrapper)
	add_child(new_manager)

	new_manager.deserialize(data)
	assert_bool(new_manager.has_definition(&"clue_1")).is_true()
	new_manager.queue_free()


func test_reset_clears_registry() -> void:
	_manager.register_clue(&"clue_1", _make_definition(&"clue_1", &"desk"))
	_manager.reset()
	assert_bool(_manager.has_definition(&"clue_1")).is_false()
	assert_int(_manager.get_clues_for_room(&"study").size()).is_equal(0)


func test_deserialize_empty_returns_false() -> void:
	assert_bool(_manager.deserialize({})).is_false()


# ---------------------------------------------------------------------------
# Tests: Signal integration
# ---------------------------------------------------------------------------


func test_clue_discovered_signal_emitted() -> void:
	_manager.register_clue(&"clue_1", _make_definition(&"clue_1", &"desk"))
	_manager._on_interaction_detected({"target_id": &"desk"})
	assert_int(_discovered_events.size()).is_equal(1)
	assert_str(String(_discovered_events[0])).is_equal("clue_1")


func test_bus_signal_connected() -> void:
	var connections: Array = _mock_bus.get_signal_connection_list("interaction_detected")
	var found: bool = false
	for conn: Dictionary in connections:
		var callable: Callable = conn["callable"]
		if callable.get_object() == _manager:
			found = true
	assert_bool(found).is_true()
