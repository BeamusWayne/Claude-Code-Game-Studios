extends GdUnitTestSuite

# Tests for ClueDatabase — unified clue/insight knowledge database.
# Covers ADR-0005 requirements: CRUD, contextual unlocks cascade,
# connection management, search, serialization, and edge cases.


const CLUE_DATABASE_SCRIPT := "res://src/core/clue_database.gd"

var _db: Node
var _signal_log: Dictionary


func before_test() -> void:
	_db = Node.new()
	_db.set_script(load(CLUE_DATABASE_SCRIPT))
	_db.name = "ClueDatabaseTest"
	add_child(_db)
	_signal_log = {}
	_connect_signals()


func after_test() -> void:
	if _db:
		_db.queue_free()


func _connect_signals() -> void:
	_db.clue_discovered.connect(func(id): _signal_log["clue_discovered"] = id)
	_db.insight_generated.connect(func(id): _signal_log["insight_generated"] = id)
	_db.connection_made.connect(func(a, b, valid): _signal_log["connection_made"] = {"a": a, "b": b, "valid": valid})


func _make_clue(id: StringName, source: StringName = &"room_hallway", tags: Array[StringName] = [], npc: StringName = &"red") -> Dictionary:
	return {
		"id": id,
		"entry_type": 0,
		"title": "Test Clue %s" % String(id),
		"description": "A test clue.",
		"source": source,
		"discovered_at_night": 1,
		"npc_affinity": npc,
		"tags": tags,
		"contextual_unlocks": [],
		"metadata": {},
	}


func _make_insight(id: StringName, source_clues: Array[StringName], reinterpretation: String = "New reading") -> Dictionary:
	return {
		"id": id,
		"entry_type": 1,
		"title": "Test Insight %s" % String(id),
		"description": "A test insight.",
		"source": &"connection",
		"discovered_at_night": 2,
		"npc_affinity": &"red",
		"tags": [],
		"contextual_unlocks": [],
		"metadata": {},
		"source_clues": source_clues,
		"reinterpretation": reinterpretation,
	}


func _add_two_clues() -> void:
	_db.add_entry(_make_clue(&"clue_a", &"room_hallway", [&"object", &"hallway"]))
	_db.add_entry(_make_clue(&"clue_b", &"room_kitchen", [&"document", &"kitchen"], &"blue"))
	_signal_log.clear()


# -- Initial State -------------------------------------------------------------

func test_initial_state_empty() -> void:
	assert_int(_db.entries.size()).is_equal(0)
	assert_int(_db.connections.size()).is_equal(0)
	assert_int(_db.get_current_night()).is_equal(0)


# -- CRUD: Add Entry -----------------------------------------------------------

func test_add_clue_returns_true() -> void:
	var result: bool = _db.add_entry(_make_clue(&"clue_1"))
	assert_bool(result).is_true()
	assert_int(_db.entries.size()).is_equal(1)


func test_add_clue_emits_signal() -> void:
	_db.add_entry(_make_clue(&"clue_1"))
	assert_dict(_signal_log).contains_keys("clue_discovered")
	assert_that(_signal_log["clue_discovered"]).is_equal(&"clue_1")


func test_add_clue_stores_entry() -> void:
	_db.add_entry(_make_clue(&"clue_1"))
	var entry: Dictionary = _db.get_entry(&"clue_1")
	assert_bool(entry.is_empty()).is_false()
	assert_that(entry["title"]).is_equal("Test Clue clue_1")
	assert_int(entry["entry_type"]).is_equal(0)


func test_add_insight_returns_true_when_sources_exist() -> void:
	_add_two_clues()
	var result: bool = _db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_b"]))
	assert_bool(result).is_true()
	assert_int(_db.entries.size()).is_equal(3)


func test_add_insight_emits_signal() -> void:
	_add_two_clues()
	_db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_b"]))
	assert_dict(_signal_log).contains_keys("insight_generated")
	assert_that(_signal_log["insight_generated"]).is_equal(&"insight_1")


func test_add_insight_fails_when_source_missing() -> void:
	_db.add_entry(_make_clue(&"clue_a"))
	var result: bool = _db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_nonexistent"]))
	assert_bool(result).is_false()
	assert_int(_db.entries.size()).is_equal(1)


func test_add_insight_fails_with_wrong_source_count() -> void:
	_add_two_clues()
	var insight := _make_insight(&"insight_1", [&"clue_a"])
	var result: bool = _db.add_entry(insight)
	assert_bool(result).is_false()


func test_add_insight_fails_when_source_is_insight() -> void:
	_add_two_clues()
	_db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_b"]))
	var result: bool = _db.add_entry(_make_insight(&"insight_2", [&"insight_1", &"clue_a"]))
	assert_bool(result).is_false()


func test_add_duplicate_id_returns_false() -> void:
	_db.add_entry(_make_clue(&"clue_1"))
	var result: bool = _db.add_entry(_make_clue(&"clue_1"))
	assert_bool(result).is_false()
	assert_int(_db.entries.size()).is_equal(1)


func test_add_entry_missing_field_returns_false() -> void:
	var entry := {
		"id": &"bad_entry",
		"entry_type": 0,
	}
	var result: bool = _db.add_entry(entry)
	assert_bool(result).is_false()


func test_add_insight_missing_source_clues_field() -> void:
	_db.add_entry(_make_clue(&"clue_a"))
	var entry := {
		"id": &"bad_insight",
		"entry_type": 1,
		"title": "Bad",
		"description": "Missing source_clues",
		"source": &"connection",
		"discovered_at_night": 1,
		"npc_affinity": &"red",
		"tags": [],
		"contextual_unlocks": [],
		"metadata": {},
		"reinterpretation": "Something",
	}
	var result: bool = _db.add_entry(entry)
	assert_bool(result).is_false()


func test_add_insight_missing_reinterpretation_field() -> void:
	_add_two_clues()
	var entry := {
		"id": &"bad_insight",
		"entry_type": 1,
		"title": "Bad",
		"description": "Missing reinterpretation",
		"source": &"connection",
		"discovered_at_night": 1,
		"npc_affinity": &"red",
		"tags": [],
		"contextual_unlocks": [],
		"metadata": {},
		"source_clues": [&"clue_a", &"clue_b"],
	}
	var result: bool = _db.add_entry(entry)
	assert_bool(result).is_false()


# -- CRUD: Get Entry -----------------------------------------------------------

func test_get_entry_returns_entry() -> void:
	_db.add_entry(_make_clue(&"clue_1"))
	var entry: Dictionary = _db.get_entry(&"clue_1")
	assert_that(entry["id"]).is_equal(&"clue_1")


func test_get_entry_returns_empty_for_missing() -> void:
	var entry: Dictionary = _db.get_entry(&"nonexistent")
	assert_bool(entry.is_empty()).is_true()


# -- CRUD: Update Entry --------------------------------------------------------

func test_update_entry_modifies_fields() -> void:
	_db.add_entry(_make_clue(&"clue_1"))
	var result: bool = _db.update_entry(&"clue_1", {"title": "Updated Title"})
	assert_bool(result).is_true()
	assert_that(_db.get_entry(&"clue_1")["title"]).is_equal("Updated Title")


func test_update_entry_preserves_id_and_type() -> void:
	_db.add_entry(_make_clue(&"clue_1"))
	_db.update_entry(&"clue_1", {"id": &"changed", "entry_type": 1, "title": "New"})
	var entry: Dictionary = _db.get_entry(&"clue_1")
	assert_that(entry["id"]).is_equal(&"clue_1")
	assert_int(entry["entry_type"]).is_equal(0)
	assert_that(entry["title"]).is_equal("New")


func test_update_entry_returns_false_for_missing() -> void:
	var result: bool = _db.update_entry(&"nonexistent", {"title": "X"})
	assert_bool(result).is_false()


# -- CRUD: Remove Entry --------------------------------------------------------

func test_remove_clue_returns_true() -> void:
	_db.add_entry(_make_clue(&"clue_1"))
	var result: bool = _db.remove_entry(&"clue_1")
	assert_bool(result).is_true()
	assert_int(_db.entries.size()).is_equal(0)


func test_remove_nonexistent_returns_false() -> void:
	var result: bool = _db.remove_entry(&"nonexistent")
	assert_bool(result).is_false()


func test_remove_insight_cascade_contextual_unlocks() -> void:
	_add_two_clues()
	_db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_b"]))

	assert_bool(_db.has_insight_for(&"clue_a")).is_true()
	assert_bool(_db.has_insight_for(&"clue_b")).is_true()

	_db.remove_entry(&"insight_1")

	var unlocks_a: Array[StringName] = _db.get_contextual_unlocks(&"clue_a")
	var unlocks_b: Array[StringName] = _db.get_contextual_unlocks(&"clue_b")
	assert_int(unlocks_a.size()).is_equal(0)
	assert_int(unlocks_b.size()).is_equal(0)


func test_remove_insight_removes_associated_connection() -> void:
	_add_two_clues()
	_db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_b"]))
	_db.connect_clues(&"clue_a", &"clue_b")
	_db.connections[0]["insight_id"] = &"insight_1"

	_db.remove_entry(&"insight_1")
	assert_int(_db.connections.size()).is_equal(0)


# -- Contextual Unlocks --------------------------------------------------------

func test_contextual_unlocks_added_on_insight_create() -> void:
	_add_two_clues()
	_db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_b"]))

	var unlocks_a: Array[StringName] = _db.get_contextual_unlocks(&"clue_a")
	var unlocks_b: Array[StringName] = _db.get_contextual_unlocks(&"clue_b")
	assert_int(unlocks_a.size()).is_equal(1)
	assert_that(unlocks_a[0]).is_equal(&"insight_1")
	assert_int(unlocks_b.size()).is_equal(1)
	assert_that(unlocks_b[0]).is_equal(&"insight_1")


func test_has_insight_for_returns_true_after_insight() -> void:
	_add_two_clues()
	_db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_b"]))
	assert_bool(_db.has_insight_for(&"clue_a")).is_true()


func test_has_insight_for_returns_false_before_insight() -> void:
	_db.add_entry(_make_clue(&"clue_1"))
	assert_bool(_db.has_insight_for(&"clue_1")).is_false()


func test_has_insight_for_returns_false_for_missing() -> void:
	assert_bool(_db.has_insight_for(&"nonexistent")).is_false()


func test_get_contextual_unlocks_empty_for_missing() -> void:
	var result: Array[StringName] = _db.get_contextual_unlocks(&"nonexistent")
	assert_int(result.size()).is_equal(0)


func test_multiple_insights_on_same_clue() -> void:
	_db.add_entry(_make_clue(&"clue_a"))
	_db.add_entry(_make_clue(&"clue_b"))
	_db.add_entry(_make_clue(&"clue_c"))

	_db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_b"]))
	_db.add_entry(_make_insight(&"insight_2", [&"clue_a", &"clue_c"]))

	var unlocks: Array[StringName] = _db.get_contextual_unlocks(&"clue_a")
	assert_int(unlocks.size()).is_equal(2)


# -- Search: By Tag ------------------------------------------------------------

func test_search_by_tag_returns_matching() -> void:
	_db.add_entry(_make_clue(&"clue_1", &"room_a", [&"object", &"hallway"]))
	_db.add_entry(_make_clue(&"clue_2", &"room_b", [&"document"]))
	_db.add_entry(_make_clue(&"clue_3", &"room_c", [&"object", &"kitchen"]))

	var result: Array[StringName] = _db.search_by_tag(&"object")
	assert_int(result.size()).is_equal(2)
	assert_bool(&"clue_1" in result).is_true()
	assert_bool(&"clue_3" in result).is_true()


func test_search_by_tag_empty_when_no_match() -> void:
	_db.add_entry(_make_clue(&"clue_1", &"room_a", [&"object"]))
	var result: Array[StringName] = _db.search_by_tag(&"nonexistent")
	assert_int(result.size()).is_equal(0)


# -- Search: By Source ---------------------------------------------------------

func test_search_by_source_returns_matching() -> void:
	_db.add_entry(_make_clue(&"clue_1", &"room_hallway"))
	_db.add_entry(_make_clue(&"clue_2", &"room_kitchen"))
	_db.add_entry(_make_clue(&"clue_3", &"room_hallway"))

	var result: Array[StringName] = _db.search_by_source(&"room_hallway")
	assert_int(result.size()).is_equal(2)


func test_search_by_source_empty_when_no_match() -> void:
	_db.add_entry(_make_clue(&"clue_1", &"room_a"))
	var result: Array[StringName] = _db.search_by_source(&"room_z")
	assert_int(result.size()).is_equal(0)


# -- Search: By NPC ------------------------------------------------------------

func test_search_by_npc_returns_matching() -> void:
	_db.add_entry(_make_clue(&"clue_1", &"room_a", [], &"red"))
	_db.add_entry(_make_clue(&"clue_2", &"room_b", [], &"blue"))
	_db.add_entry(_make_clue(&"clue_3", &"room_c", [], &"red"))

	var result: Array[StringName] = _db.search_by_npc(&"red")
	assert_int(result.size()).is_equal(2)


func test_search_by_npc_empty_when_no_match() -> void:
	_db.add_entry(_make_clue(&"clue_1", &"room_a", [], &"red"))
	var result: Array[StringName] = _db.search_by_npc(&"green")
	assert_int(result.size()).is_equal(0)


# -- Search: Get All Clues/Insights --------------------------------------------

func test_get_all_clues_returns_only_clues() -> void:
	_add_two_clues()
	_db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_b"]))

	var result: Array[StringName] = _db.get_all_clues()
	assert_int(result.size()).is_equal(2)
	assert_bool(&"clue_a" in result).is_true()
	assert_bool(&"clue_b" in result).is_true()


func test_get_all_insights_returns_only_insights() -> void:
	_add_two_clues()
	_db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_b"]))

	var result: Array[StringName] = _db.get_all_insights()
	assert_int(result.size()).is_equal(1)
	assert_that(result[0]).is_equal(&"insight_1")


# -- Search: Has Clue/Insight --------------------------------------------------

func test_has_clue_true() -> void:
	_db.add_entry(_make_clue(&"clue_1"))
	assert_bool(_db.has_clue(&"clue_1")).is_true()


func test_has_clue_false_for_insight() -> void:
	_add_two_clues()
	_db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_b"]))
	assert_bool(_db.has_clue(&"insight_1")).is_false()


func test_has_clue_false_for_missing() -> void:
	assert_bool(_db.has_clue(&"nonexistent")).is_false()


func test_has_insight_true() -> void:
	_add_two_clues()
	_db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_b"]))
	assert_bool(_db.has_insight(&"insight_1")).is_true()


func test_has_insight_false_for_clue() -> void:
	_db.add_entry(_make_clue(&"clue_1"))
	assert_bool(_db.has_insight(&"clue_1")).is_false()


func test_has_insight_false_for_missing() -> void:
	assert_bool(_db.has_insight(&"nonexistent")).is_false()


# -- Search: Undiscovered Clues ------------------------------------------------

func test_get_undiscovered_clues_excludes_connected() -> void:
	_add_two_clues()
	_db.add_entry(_make_clue(&"clue_c"))
	_db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_b"]))

	var undiscovered: Array[StringName] = _db.get_undiscovered_clues()
	assert_int(undiscovered.size()).is_equal(1)
	assert_that(undiscovered[0]).is_equal(&"clue_c")


func test_get_undiscovered_clues_all_when_no_insights() -> void:
	_add_two_clues()
	var undiscovered: Array[StringName] = _db.get_undiscovered_clues()
	assert_int(undiscovered.size()).is_equal(2)


# -- Connections ---------------------------------------------------------------

func test_connect_clues_creates_connection() -> void:
	_add_two_clues()
	_db.set_current_night(3)

	var result: Dictionary = _db.connect_clues(&"clue_a", &"clue_b")
	assert_bool(result["ok"]).is_true()
	assert_bool(result["connection"].is_empty()).is_false()
	assert_int(_db.connections.size()).is_equal(1)


func test_connect_clues_emits_signal() -> void:
	_add_two_clues()
	_db.connect_clues(&"clue_a", &"clue_b")
	assert_dict(_signal_log).contains_keys("connection_made")


func test_connect_clues_normalizes_alphabetical_order() -> void:
	_add_two_clues()
	var result: Dictionary = _db.connect_clues(&"clue_b", &"clue_a")
	assert_bool(result["ok"]).is_true()
	assert_that(result["connection"]["clue_a"]).is_equal(&"clue_a")
	assert_that(result["connection"]["clue_b"]).is_equal(&"clue_b")


func test_connect_clues_stores_night() -> void:
	_add_two_clues()
	_db.set_current_night(5)
	_db.connect_clues(&"clue_a", &"clue_b")
	assert_int(_db.connections[0]["made_at_night"]).is_equal(5)


func test_connect_clues_rejects_duplicate() -> void:
	_add_two_clues()
	_db.connect_clues(&"clue_a", &"clue_b")
	var result: Dictionary = _db.connect_clues(&"clue_a", &"clue_b")
	assert_bool(result["ok"]).is_false()
	assert_that(result["reason"]).is_equal("duplicate")


func test_connect_clues_rejects_reverse_duplicate() -> void:
	_add_two_clues()
	_db.connect_clues(&"clue_a", &"clue_b")
	var result: Dictionary = _db.connect_clues(&"clue_b", &"clue_a")
	assert_bool(result["ok"]).is_false()
	assert_that(result["reason"]).is_equal("duplicate")


func test_connect_clues_rejects_missing_clue() -> void:
	_db.add_entry(_make_clue(&"clue_a"))
	var result: Dictionary = _db.connect_clues(&"clue_a", &"nonexistent")
	assert_bool(result["ok"]).is_false()
	assert_that(result["reason"]).is_equal("clue_not_found")


func test_connect_clues_rejects_insight_ids() -> void:
	_add_two_clues()
	_db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_b"]))
	var result: Dictionary = _db.connect_clues(&"clue_a", &"insight_1")
	assert_bool(result["ok"]).is_false()
	assert_that(result["reason"]).is_equal("invalid_types")


func test_get_connections_for_returns_both_sides() -> void:
	_add_two_clues()
	_db.connect_clues(&"clue_a", &"clue_b")

	var conns_a: Array[Dictionary] = _db.get_connections_for(&"clue_a")
	var conns_b: Array[Dictionary] = _db.get_connections_for(&"clue_b")
	assert_int(conns_a.size()).is_equal(1)
	assert_int(conns_b.size()).is_equal(1)


func test_get_connections_for_empty_when_none() -> void:
	_db.add_entry(_make_clue(&"clue_1"))
	var result: Array[Dictionary] = _db.get_connections_for(&"clue_1")
	assert_int(result.size()).is_equal(0)


func test_get_valid_connections_filters() -> void:
	_add_two_clues()
	_db.add_entry(_make_clue(&"clue_c"))
	_db.connect_clues(&"clue_a", &"clue_b")
	_db.connect_clues(&"clue_a", &"clue_c")

	_db.connections[0]["is_valid"] = true
	_db.connections[0]["insight_id"] = &"insight_1"

	var valid: Array[Dictionary] = _db.get_valid_connections()
	var invalid: Array[Dictionary] = _db.get_invalid_connections()
	assert_int(valid.size()).is_equal(1)
	assert_int(invalid.size()).is_equal(1)


func test_get_invalid_connections_returns_all_when_none_valid() -> void:
	_add_two_clues()
	_db.connect_clues(&"clue_a", &"clue_b")
	assert_int(_db.get_invalid_connections().size()).is_equal(1)
	assert_int(_db.get_valid_connections().size()).is_equal(0)


# -- Serialization -------------------------------------------------------------

func test_serialize_produces_valid_schema() -> void:
	_add_two_clues()
	var data: Dictionary = _db.serialize()
	assert_int(data["schema_version"]).is_equal(1)
	assert_bool(data.has("entries")).is_true()
	assert_bool(data.has("connections")).is_true()


func test_serialize_deserialize_roundtrip_clues() -> void:
	_add_two_clues()
	var data: Dictionary = _db.serialize()

	var db2 := Node.new()
	db2.set_script(load(CLUE_DATABASE_SCRIPT))
	add_child(db2)
	var ok: bool = db2.deserialize(data)
	assert_bool(ok).is_true()
	assert_int(db2.entries.size()).is_equal(2)
	assert_bool(db2.has_clue(&"clue_a")).is_true()
	assert_bool(db2.has_clue(&"clue_b")).is_true()
	db2.queue_free()


func test_serialize_deserialize_roundtrip_insights() -> void:
	_add_two_clues()
	_db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_b"], "They are connected."))

	var data: Dictionary = _db.serialize()

	var db2 := Node.new()
	db2.set_script(load(CLUE_DATABASE_SCRIPT))
	add_child(db2)
	db2.deserialize(data)

	assert_bool(db2.has_insight(&"insight_1")).is_true()
	var insight: Dictionary = db2.get_entry(&"insight_1")
	assert_that(insight["reinterpretation"]).is_equal("They are connected.")
	assert_int(insight["source_clues"].size()).is_equal(2)
	db2.queue_free()


func test_serialize_deserialize_roundtrip_connections() -> void:
	_add_two_clues()
	_db.set_current_night(3)
	_db.connect_clues(&"clue_a", &"clue_b")

	var data: Dictionary = _db.serialize()

	var db2 := Node.new()
	db2.set_script(load(CLUE_DATABASE_SCRIPT))
	add_child(db2)
	db2.deserialize(data)

	assert_int(db2.connections.size()).is_equal(1)
	assert_that(db2.connections[0]["clue_a"]).is_equal(&"clue_a")
	assert_that(db2.connections[0]["clue_b"]).is_equal(&"clue_b")
	assert_int(db2.connections[0]["made_at_night"]).is_equal(3)
	db2.queue_free()


func test_serialize_deserialize_roundtrip_full() -> void:
	_add_two_clues()
	_db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_b"]))
	_db.set_current_night(4)
	_db.connect_clues(&"clue_a", &"clue_b")

	var data: Dictionary = _db.serialize()

	var db2 := Node.new()
	db2.set_script(load(CLUE_DATABASE_SCRIPT))
	add_child(db2)
	db2.deserialize(data)

	var data2: Dictionary = db2.serialize()
	assert_int(data2["entries"].size()).is_equal(data["entries"].size())
	assert_int(data2["connections"].size()).is_equal(data["connections"].size())
	db2.queue_free()


func test_deserialize_empty_returns_false() -> void:
	var result: bool = _db.deserialize({})
	assert_bool(result).is_false()


func test_deserialize_wrong_schema_version_returns_false() -> void:
	var result: bool = _db.deserialize({"schema_version": 99, "entries": {}, "connections": []})
	assert_bool(result).is_false()


func test_serialize_preserves_tags_as_strings() -> void:
	_db.add_entry(_make_clue(&"clue_1", &"room_a", [&"object", &"hallway"]))
	var data: Dictionary = _db.serialize()
	var entry_data: Dictionary = data["entries"]["clue_1"]
	assert_int(entry_data["tags"].size()).is_equal(2)
	assert_that(entry_data["tags"][0]).is_equal("object")


func test_deserialize_converts_strings_to_stringnames() -> void:
	_db.add_entry(_make_clue(&"clue_1", &"room_a", [&"tag_a"]))
	var data: Dictionary = _db.serialize()

	var db2 := Node.new()
	db2.set_script(load(CLUE_DATABASE_SCRIPT))
	add_child(db2)
	db2.deserialize(data)

	var entry: Dictionary = db2.get_entry(&"clue_1")
	assert_int(entry["tags"].size()).is_equal(1)
	db2.queue_free()


func test_serialize_contextual_unlocks() -> void:
	_add_two_clues()
	_db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_b"]))

	var data: Dictionary = _db.serialize()
	var clue_a_data: Dictionary = data["entries"]["clue_a"]
	assert_int(clue_a_data["contextual_unlocks"].size()).is_equal(1)
	assert_that(clue_a_data["contextual_unlocks"][0]).is_equal("insight_1")


func test_deserialize_restores_contextual_unlocks() -> void:
	_add_two_clues()
	_db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_b"]))
	var data: Dictionary = _db.serialize()

	var db2 := Node.new()
	db2.set_script(load(CLUE_DATABASE_SCRIPT))
	add_child(db2)
	db2.deserialize(data)

	var unlocks: Array[StringName] = db2.get_contextual_unlocks(&"clue_a")
	assert_int(unlocks.size()).is_equal(1)
	db2.queue_free()


# -- Reset ---------------------------------------------------------------------

func test_reset_clears_everything() -> void:
	_add_two_clues()
	_db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_b"]))
	_db.set_current_night(5)
	_db.connect_clues(&"clue_a", &"clue_b")

	_db.reset()
	assert_int(_db.entries.size()).is_equal(0)
	assert_int(_db.connections.size()).is_equal(0)
	assert_int(_db.get_current_night()).is_equal(0)


# -- Night Tracking ------------------------------------------------------------

func test_set_current_night() -> void:
	_db.set_current_night(7)
	assert_int(_db.get_current_night()).is_equal(7)


# -- Edge Cases ----------------------------------------------------------------

func test_add_entry_does_not_mutate_input() -> void:
	var clue := _make_clue(&"clue_1")
	clue["title"] = "Original"
	_db.add_entry(clue)
	clue["title"] = "Mutated"
	assert_that(_db.get_entry(&"clue_1")["title"]).is_equal("Original")


func test_update_entry_immutable_keys_ignored() -> void:
	_db.add_entry(_make_clue(&"clue_1"))
	_db.update_entry(&"clue_1", {"id": &"new_id", "entry_type": 1, "description": "changed"})
	var entry: Dictionary = _db.get_entry(&"clue_1")
	assert_that(entry["id"]).is_equal(&"clue_1")
	assert_int(entry["entry_type"]).is_equal(0)
	assert_that(entry["description"]).is_equal("changed")


func test_search_methods_work_with_mixed_entries() -> void:
	_db.add_entry(_make_clue(&"clue_1", &"room_hallway", [&"object"], &"red"))
	_db.add_entry(_make_clue(&"clue_2", &"room_kitchen", [&"document"], &"blue"))
	_add_two_clues()
	_db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_b"]))

	var by_source: Array[StringName] = _db.search_by_source(&"room_hallway")
	assert_int(by_source.size()).is_equal(2)

	var by_npc: Array[StringName] = _db.search_by_npc(&"red")
	assert_int(by_npc.size()).is_equal(3)

	var by_tag: Array[StringName] = _db.search_by_tag(&"object")
	assert_int(by_tag.size()).is_equal(2)


func test_connection_initial_state_is_invalid() -> void:
	_add_two_clues()
	_db.connect_clues(&"clue_a", &"clue_b")
	assert_bool(_db.connections[0]["is_valid"]).is_false()
	assert_that(_db.connections[0]["insight_id"]).is_equal(&"")


func test_large_dataset_serialization_roundtrip() -> void:
	for i in range(50):
		var id: StringName = StringName("clue_%03d" % i)
		var room_id: StringName = StringName("room_" + str(i % 5))
		var tag_id: StringName = StringName("tag_" + str(i % 10))
		_db.add_entry(_make_clue(id, room_id, [tag_id]))

	assert_int(_db.entries.size()).is_equal(50)
	var data: Dictionary = _db.serialize()
	assert_int(data["entries"].size()).is_equal(50)

	var db2 := Node.new()
	db2.set_script(load(CLUE_DATABASE_SCRIPT))
	add_child(db2)
	db2.deserialize(data)
	assert_int(db2.entries.size()).is_equal(50)
	db2.queue_free()


func test_remove_insight_partial_cascade() -> void:
	_db.add_entry(_make_clue(&"clue_a"))
	_db.add_entry(_make_clue(&"clue_b"))
	_db.add_entry(_make_clue(&"clue_c"))

	_db.add_entry(_make_insight(&"insight_1", [&"clue_a", &"clue_b"]))
	_db.add_entry(_make_insight(&"insight_2", [&"clue_a", &"clue_c"]))

	assert_int(_db.get_contextual_unlocks(&"clue_a").size()).is_equal(2)

	_db.remove_entry(&"insight_1")

	assert_int(_db.get_contextual_unlocks(&"clue_a").size()).is_equal(1)
	assert_that(_db.get_contextual_unlocks(&"clue_a")[0]).is_equal(&"insight_2")
	assert_int(_db.get_contextual_unlocks(&"clue_b").size()).is_equal(0)
	assert_int(_db.get_contextual_unlocks(&"clue_c").size()).is_equal(1)
