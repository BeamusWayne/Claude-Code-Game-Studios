extends GdUnitTestSuite

## Tests for ClueConnectionManager — connection requests, insight generation,
## duplicate rejection, invalid connections, contextual unlocks, InsightGenerator.
## Covers GDD acceptance criteria from design/gdd/clue-connection-deduction.md.

const CCM_SCRIPT := "res://src/feature/clue_connection_manager.gd"

var _manager: Node
var _mock_db: Node

var _connection_made_events: Array
var _connection_requested_events: Array
var _insight_generated_events: Array


func before_test() -> void:
	_mock_db = Node.new()
	_mock_db.name = "ClueDatabase"
	_mock_db.set_script(_create_db_mock())
	add_child(_mock_db)

	var wrapper := GDScript.new()
	wrapper.source_code = (
		"extends \"%s\"\n" % CCM_SCRIPT
		+ "var _test_db: Node = null\n"
		+ "func _get_clue_database() -> Node:\n"
		+ "\treturn _test_db\n"
	)
	wrapper.reload()

	_manager = Node.new()
	_manager.set_script(wrapper)
	_manager._test_db = _mock_db
	_manager.name = "ClueConnectionManagerTest"
	add_child(_manager)

	_connection_made_events = []
	_connection_requested_events = []
	_insight_generated_events = []
	_mock_db.connection_made.connect(_on_connection_made)
	_manager.connection_requested.connect(_on_connection_requested)
	_mock_db.insight_generated.connect(_on_insight_generated)


func _on_connection_made(a: StringName, b: StringName, valid: bool) -> void:
	_connection_made_events.append({"a": a, "b": b, "valid": valid})


func _on_connection_requested(a: StringName, b: StringName, valid: bool) -> void:
	_connection_requested_events.append({"a": a, "b": b, "valid": valid})


func _on_insight_generated(id: StringName) -> void:
	_insight_generated_events.append(id)


func after_test() -> void:
	if _manager:
		_manager.queue_free()
	if _mock_db:
		_mock_db.queue_free()


# ---------------------------------------------------------------------------
# Mock Scripts
# ---------------------------------------------------------------------------


func _create_db_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal clue_discovered(clue_id: StringName)\n"
		+ "signal insight_generated(insight_id: StringName)\n"
		+ "signal connection_made(clue_a: StringName, clue_b: StringName, is_valid: bool)\n"
		+ "enum EntryType { CLUE, INSIGHT }\n"
		+ "var entries: Dictionary = {}\n"
		+ "var connections: Array[Dictionary] = []\n"
		+ "var _current_night: int = 1\n"
		+ "func has_clue(id: StringName) -> bool:\n"
		+ "\treturn entries.has(id) and entries[id][\"entry_type\"] == 0\n"
		+ "func has_insight(id: StringName) -> bool:\n"
		+ "\treturn entries.has(id) and entries[id][\"entry_type\"] == 1\n"
		+ "func get_all_insights() -> Array[StringName]:\n"
		+ "\tvar result: Array[StringName] = []\n"
		+ "\tfor eid: StringName in entries:\n"
		+ "\t\tif entries[eid][\"entry_type\"] == 1:\n"
		+ "\t\t\tresult.append(eid)\n"
		+ "\treturn result\n"
		+ "func add_entry(entry: Dictionary) -> bool:\n"
		+ "\tif entries.has(entry[\"id\"]):\n"
		+ "\t\treturn false\n"
		+ "\tentries[entry[\"id\"]] = entry\n"
		+ "\tif entry[\"entry_type\"] == 0:\n"
		+ "\t\tclue_discovered.emit(entry[\"id\"])\n"
		+ "\telse:\n"
		+ "\t\tinsight_generated.emit(entry[\"id\"])\n"
		+ "\t\t_cascade_unlocks(entry[\"id\"], entry.get(\"source_clues\", []))\n"
		+ "\treturn true\n"
		+ "func get_current_night() -> int:\n"
		+ "\treturn _current_night\n"
		+ "func _cascade_unlocks(insight_id: StringName, source_clues: Array) -> void:\n"
		+ "\tfor clue_id: StringName in source_clues:\n"
		+ "\t\tif entries.has(clue_id):\n"
		+ "\t\t\tvar unlocks: Array = entries[clue_id].get(\"contextual_unlocks\", [])\n"
		+ "\t\t\tif not insight_id in unlocks:\n"
		+ "\t\t\t\tunlocks.append(insight_id)\n"
		+ "\t\t\tentries[clue_id][\"contextual_unlocks\"] = unlocks\n"
	)
	script.reload()
	return script


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _add_clue(clue_id: StringName) -> void:
	_mock_db.entries[clue_id] = {
		"id": clue_id,
		"entry_type": 0,
		"title": "Test Clue",
		"description": "A test clue.",
		"source": &"test",
		"discovered_at_night": 1,
		"npc_affinity": &"",
		"tags": [],
		"contextual_unlocks": [],
		"metadata": {},
	}


func _make_definition(clue_a: StringName, clue_b: StringName, insight_id: StringName) -> Dictionary:
	return {
		"clue_a": clue_a,
		"clue_b": clue_b,
		"resulting_insight": {
			"id": insight_id,
			"title": "Test Insight",
			"description": "A generated insight.",
			"reinterpretation": "New context.",
			"npc_affinity": &"guest_indigo",
			"tags": [&"test"],
			"weight": 1.0,
		},
	}


# ---------------------------------------------------------------------------
# Tests: Basic Connection
# ---------------------------------------------------------------------------


func test_valid_connection_generates_insight() -> void:
	_add_clue(&"clue_a")
	_add_clue(&"clue_b")
	_manager.register_definition(_make_definition(&"clue_a", &"clue_b", &"insight_1"))
	var result: Dictionary = _manager.request_connection(&"clue_a", &"clue_b")
	assert_bool(result["ok"]).is_true()
	assert_bool(result["is_valid"]).is_true()
	assert_str(String(result["insight_id"])).is_equal("insight_1")


func test_invalid_connection_recorded() -> void:
	_add_clue(&"clue_a")
	_add_clue(&"clue_b")
	var result: Dictionary = _manager.request_connection(&"clue_a", &"clue_b")
	assert_bool(result["ok"]).is_true()
	assert_bool(result["is_valid"]).is_false()
	assert_str(String(result["insight_id"])).is_equal("")


func test_insight_added_to_database() -> void:
	_add_clue(&"clue_a")
	_add_clue(&"clue_b")
	_manager.register_definition(_make_definition(&"clue_a", &"clue_b", &"insight_1"))
	_manager.request_connection(&"clue_a", &"clue_b")
	assert_bool(_mock_db.has_insight(&"insight_1")).is_true()


func test_connection_record_in_database() -> void:
	_add_clue(&"clue_a")
	_add_clue(&"clue_b")
	_manager.register_definition(_make_definition(&"clue_a", &"clue_b", &"insight_1"))
	_manager.request_connection(&"clue_a", &"clue_b")
	assert_int(_mock_db.connections.size()).is_equal(1)
	assert_bool(_mock_db.connections[0]["is_valid"]).is_true()
	assert_str(String(_mock_db.connections[0]["insight_id"])).is_equal("insight_1")


# ---------------------------------------------------------------------------
# Tests: Rejection Cases
# ---------------------------------------------------------------------------


func test_reject_duplicate_connection() -> void:
	_add_clue(&"clue_a")
	_add_clue(&"clue_b")
	_manager.register_definition(_make_definition(&"clue_a", &"clue_b", &"insight_1"))
	_manager.request_connection(&"clue_a", &"clue_b")
	var result: Dictionary = _manager.request_connection(&"clue_a", &"clue_b")
	assert_bool(result["ok"]).is_false()
	assert_str(result["reason"]).is_equal("duplicate")


func test_reject_reverse_duplicate() -> void:
	_add_clue(&"clue_a")
	_add_clue(&"clue_b")
	_manager.register_definition(_make_definition(&"clue_a", &"clue_b", &"insight_1"))
	_manager.request_connection(&"clue_a", &"clue_b")
	var result: Dictionary = _manager.request_connection(&"clue_b", &"clue_a")
	assert_bool(result["ok"]).is_false()
	assert_str(result["reason"]).is_equal("duplicate")


func test_reject_self_connection() -> void:
	_add_clue(&"clue_a")
	var result: Dictionary = _manager.request_connection(&"clue_a", &"clue_a")
	assert_bool(result["ok"]).is_false()
	assert_str(result["reason"]).is_equal("duplicate")


func test_reject_undiscovered_clue() -> void:
	_add_clue(&"clue_a")
	var result: Dictionary = _manager.request_connection(&"clue_a", &"clue_unknown")
	assert_bool(result["ok"]).is_false()
	assert_str(result["reason"]).is_equal("clue_not_found")


func test_reject_both_undiscovered() -> void:
	var result: Dictionary = _manager.request_connection(&"clue_x", &"clue_y")
	assert_bool(result["ok"]).is_false()
	assert_str(result["reason"]).is_equal("clue_not_found")


# ---------------------------------------------------------------------------
# Tests: Signal Emission
# ---------------------------------------------------------------------------


func test_connection_made_signal_valid() -> void:
	_add_clue(&"clue_a")
	_add_clue(&"clue_b")
	_manager.register_definition(_make_definition(&"clue_a", &"clue_b", &"insight_1"))
	_manager.request_connection(&"clue_a", &"clue_b")
	assert_int(_connection_made_events.size()).is_equal(1)
	assert_bool(_connection_made_events[0]["valid"]).is_true()


func test_connection_made_signal_invalid() -> void:
	_add_clue(&"clue_a")
	_add_clue(&"clue_b")
	_manager.request_connection(&"clue_a", &"clue_b")
	assert_int(_connection_made_events.size()).is_equal(1)
	assert_bool(_connection_made_events[0]["valid"]).is_false()


func test_insight_generated_signal() -> void:
	_add_clue(&"clue_a")
	_add_clue(&"clue_b")
	_manager.register_definition(_make_definition(&"clue_a", &"clue_b", &"insight_1"))
	_manager.request_connection(&"clue_a", &"clue_b")
	assert_int(_insight_generated_events.size()).is_equal(1)
	assert_str(String(_insight_generated_events[0])).is_equal("insight_1")


func test_no_insight_signal_on_invalid() -> void:
	_add_clue(&"clue_a")
	_add_clue(&"clue_b")
	_manager.request_connection(&"clue_a", &"clue_b")
	assert_int(_insight_generated_events.size()).is_equal(0)


func test_connection_requested_signal() -> void:
	_add_clue(&"clue_a")
	_add_clue(&"clue_b")
	_manager.request_connection(&"clue_a", &"clue_b")
	assert_int(_connection_requested_events.size()).is_equal(1)


# ---------------------------------------------------------------------------
# Tests: Contextual Unlocks
# ---------------------------------------------------------------------------


func test_contextual_unlocks_updated() -> void:
	_add_clue(&"clue_a")
	_add_clue(&"clue_b")
	_manager.register_definition(_make_definition(&"clue_a", &"clue_b", &"insight_1"))
	_manager.request_connection(&"clue_a", &"clue_b")
	var unlocks_a: Array = _mock_db.entries[&"clue_a"]["contextual_unlocks"]
	assert_bool(unlocks_a.has(&"insight_1")).is_true()
	var unlocks_b: Array = _mock_db.entries[&"clue_b"]["contextual_unlocks"]
	assert_bool(unlocks_b.has(&"insight_1")).is_true()


# ---------------------------------------------------------------------------
# Tests: Lookup Key Symmetry (A+B = B+A)
# ---------------------------------------------------------------------------


func test_lookup_key_symmetry() -> void:
	_add_clue(&"clue_a")
	_add_clue(&"clue_b")
	_manager.register_definition(_make_definition(&"clue_a", &"clue_b", &"insight_1"))
	var gen: RefCounted = _manager.get_generator()
	var def_fwd: Dictionary = gen.validate_connection(&"clue_a", &"clue_b")
	var def_rev: Dictionary = gen.validate_connection(&"clue_b", &"clue_a")
	assert_bool(not def_fwd.is_empty()).is_true()
	assert_bool(not def_rev.is_empty()).is_true()


func test_connection_sorted_alphabetically() -> void:
	_add_clue(&"clue_a")
	_add_clue(&"clue_b")
	_manager.register_definition(_make_definition(&"clue_a", &"clue_b", &"insight_1"))
	_manager.request_connection(&"clue_b", &"clue_a")
	assert_str(String(_mock_db.connections[0]["clue_a"])).is_equal("clue_a")
	assert_str(String(_mock_db.connections[0]["clue_b"])).is_equal("clue_b")


# ---------------------------------------------------------------------------
# Tests: InsightGenerator
# ---------------------------------------------------------------------------


func test_generator_validate_no_match() -> void:
	var gen: RefCounted = _manager.get_generator()
	var result: Dictionary = gen.validate_connection(&"x", &"y")
	assert_bool(result.is_empty()).is_true()


func test_generator_validate_with_match() -> void:
	var gen: RefCounted = _manager.get_generator()
	_manager.register_definition(_make_definition(&"clue_a", &"clue_b", &"insight_1"))
	var result: Dictionary = gen.validate_connection(&"clue_a", &"clue_b")
	assert_bool(not result.is_empty()).is_true()
	assert_str(String(result.get("clue_a", &""))).is_equal("clue_a")


func test_generator_generate_insight() -> void:
	var gen: RefCounted = _manager.get_generator()
	var def: Dictionary = _make_definition(&"clue_a", &"clue_b", &"insight_1")
	var insight: Dictionary = gen.generate_insight(def, 3)
	assert_str(String(insight["id"])).is_equal("insight_1")
	assert_int(insight["entry_type"]).is_equal(1)
	assert_str(String(insight["reinterpretation"])).is_equal("New context.")
	assert_int(insight["discovered_at_night"]).is_equal(3)


func test_generator_definition_count() -> void:
	_manager.register_definition(_make_definition(&"a", &"b", &"i1"))
	_manager.register_definition(_make_definition(&"c", &"d", &"i2"))
	assert_int(_manager.get_generator().get_definition_count()).is_equal(2)


func test_generator_load_definitions_bulk() -> void:
	var defs: Array[Dictionary] = [
		_make_definition(&"a", &"b", &"i1"),
		_make_definition(&"c", &"d", &"i2"),
	]
	_manager.load_definitions(defs)
	assert_int(_manager.get_generator().get_definition_count()).is_equal(2)


# ---------------------------------------------------------------------------
# Tests: can_connect
# ---------------------------------------------------------------------------


func test_can_connect_valid_pair() -> void:
	_add_clue(&"clue_a")
	_add_clue(&"clue_b")
	_manager.register_definition(_make_definition(&"clue_a", &"clue_b", &"insight_1"))
	assert_bool(_manager.can_connect(&"clue_a", &"clue_b")).is_true()


func test_can_connect_no_definition() -> void:
	_add_clue(&"clue_a")
	_add_clue(&"clue_b")
	assert_bool(_manager.can_connect(&"clue_a", &"clue_b")).is_false()


func test_can_connect_missing_clue() -> void:
	_add_clue(&"clue_a")
	assert_bool(_manager.can_connect(&"clue_a", &"clue_unknown")).is_false()


func test_can_connect_already_connected() -> void:
	_add_clue(&"clue_a")
	_add_clue(&"clue_b")
	_manager.register_definition(_make_definition(&"clue_a", &"clue_b", &"insight_1"))
	_manager.request_connection(&"clue_a", &"clue_b")
	assert_bool(_manager.can_connect(&"clue_a", &"clue_b")).is_false()


# ---------------------------------------------------------------------------
# Tests: Serialize / Reset
# ---------------------------------------------------------------------------


func test_serialize_returns_data() -> void:
	_manager.register_definition(_make_definition(&"a", &"b", &"i1"))
	var data: Dictionary = _manager.serialize()
	assert_int(data.get("definition_count", 0)).is_equal(1)


func test_reset_clears_definitions() -> void:
	_manager.register_definition(_make_definition(&"a", &"b", &"i1"))
	_manager.reset()
	assert_int(_manager.get_generator().get_definition_count()).is_equal(0)


# ---------------------------------------------------------------------------
# Tests: Invalid connection behavior
# ---------------------------------------------------------------------------


func test_invalid_connection_no_insight_entry() -> void:
	_add_clue(&"clue_a")
	_add_clue(&"clue_b")
	_manager.request_connection(&"clue_a", &"clue_b")
	assert_bool(_mock_db.has_insight(&"insight_1")).is_false()


func test_invalid_connection_no_contextual_unlocks() -> void:
	_add_clue(&"clue_a")
	_add_clue(&"clue_b")
	_manager.request_connection(&"clue_a", &"clue_b")
	assert_bool(_mock_db.entries[&"clue_a"]["contextual_unlocks"].is_empty()).is_true()


func test_multiple_connections_mixed() -> void:
	_add_clue(&"clue_a")
	_add_clue(&"clue_b")
	_add_clue(&"clue_c")
	_manager.register_definition(_make_definition(&"clue_a", &"clue_b", &"insight_1"))
	_manager.request_connection(&"clue_a", &"clue_b")
	_manager.request_connection(&"clue_a", &"clue_c")
	_manager.request_connection(&"clue_b", &"clue_c")
	assert_int(_mock_db.connections.size()).is_equal(3)
	assert_int(_mock_db.get_all_insights().size()).is_equal(1)
