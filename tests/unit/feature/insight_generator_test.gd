extends GdUnitTestSuite

## Tests for InsightGenerator — definition registration, bidirectional lookup,
## insight generation, edge cases. InsightGenerator is a pure RefCounted utility.
## Covers ADR-0005 Clue/Insight Unified Schema.


var _gen: RefCounted


func before_test() -> void:
	_gen = load("res://src/feature/insight_generator.gd").new()


func after_test() -> void:
	_gen = null


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


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
			"tags": [&"test", &"core"],
			"weight": 1.5,
		},
	}


func _make_minimal_definition(clue_a: StringName, clue_b: StringName) -> Dictionary:
	return {
		"clue_a": clue_a,
		"clue_b": clue_b,
	}


# ---------------------------------------------------------------------------
# Tests: Default State
# ---------------------------------------------------------------------------


func test_initial_definition_count_is_zero() -> void:
	assert_int(_gen.get_definition_count()).is_equal(0)


func test_validate_connection_returns_empty_on_empty_lookup() -> void:
	var result: Dictionary = _gen.validate_connection(&"x", &"y")
	assert_bool(result.is_empty()).is_true()


# ---------------------------------------------------------------------------
# Tests: register_definition
# ---------------------------------------------------------------------------


func test_register_single_definition_increments_count() -> void:
	_gen.register_definition(_make_definition(&"clue_a", &"clue_b", &"insight_1"))
	assert_int(_gen.get_definition_count()).is_equal(1)


func test_register_multiple_definitions_increments_count() -> void:
	_gen.register_definition(_make_definition(&"a", &"b", &"i1"))
	_gen.register_definition(_make_definition(&"c", &"d", &"i2"))
	_gen.register_definition(_make_definition(&"e", &"f", &"i3"))
	assert_int(_gen.get_definition_count()).is_equal(3)


func test_register_definition_skips_empty_clue_a() -> void:
	var def: Dictionary = {"clue_a": &"", "clue_b": &"valid", "resulting_insight": {}}
	_gen.register_definition(def)
	assert_int(_gen.get_definition_count()).is_equal(0)


func test_register_definition_skips_empty_clue_b() -> void:
	var def: Dictionary = {"clue_a": &"valid", "clue_b": &"", "resulting_insight": {}}
	_gen.register_definition(def)
	assert_int(_gen.get_definition_count()).is_equal(0)


func test_register_definition_skips_both_empty() -> void:
	var def: Dictionary = {"clue_a": &"", "clue_b": &"", "resulting_insight": {}}
	_gen.register_definition(def)
	assert_int(_gen.get_definition_count()).is_equal(0)


func test_register_definition_skips_missing_clue_keys() -> void:
	# No clue_a or clue_b keys at all — get() returns &"" default
	var def: Dictionary = {"resulting_insight": {"id": &"orphan"}}
	_gen.register_definition(def)
	assert_int(_gen.get_definition_count()).is_equal(0)


func test_register_definition_accepts_minimal_definition() -> void:
	_gen.register_definition(_make_minimal_definition(&"x", &"y"))
	assert_int(_gen.get_definition_count()).is_equal(1)


# ---------------------------------------------------------------------------
# Tests: load_definitions (bulk)
# ---------------------------------------------------------------------------


func test_load_definitions_registers_all() -> void:
	var defs: Array[Dictionary] = [
		_make_definition(&"a", &"b", &"i1"),
		_make_definition(&"c", &"d", &"i2"),
	]
	_gen.load_definitions(defs)
	assert_int(_gen.get_definition_count()).is_equal(2)


func test_load_definitions_empty_array_no_error() -> void:
	var defs: Array[Dictionary] = []
	_gen.load_definitions(defs)
	assert_int(_gen.get_definition_count()).is_equal(0)


func test_load_definitions_skips_invalid_entries() -> void:
	var defs: Array[Dictionary] = [
		_make_definition(&"a", &"b", &"i1"),
		{"clue_a": &"", "clue_b": &"z"},  # invalid — empty clue_a
		_make_definition(&"e", &"f", &"i3"),
	]
	_gen.load_definitions(defs)
	assert_int(_gen.get_definition_count()).is_equal(2)


# ---------------------------------------------------------------------------
# Tests: validate_connection
# ---------------------------------------------------------------------------


func test_validate_connection_returns_definition_for_valid_pair() -> void:
	_gen.register_definition(_make_definition(&"clue_a", &"clue_b", &"insight_1"))
	var result: Dictionary = _gen.validate_connection(&"clue_a", &"clue_b")
	assert_bool(result.is_empty()).is_false()
	assert_that(String(result.get("clue_a", &""))).is_equal("clue_a")
	assert_that(String(result.get("clue_b", &""))).is_equal("clue_b")


func test_validate_connection_returns_empty_for_unknown_pair() -> void:
	_gen.register_definition(_make_definition(&"a", &"b", &"i1"))
	var result: Dictionary = _gen.validate_connection(&"x", &"y")
	assert_bool(result.is_empty()).is_true()


func test_validate_connection_returns_empty_no_definitions_loaded() -> void:
	var result: Dictionary = _gen.validate_connection(&"anything", &"else")
	assert_bool(result.is_empty()).is_true()


# ---------------------------------------------------------------------------
# Tests: Bidirectional Lookup (A+B = B+A)
# ---------------------------------------------------------------------------


func test_bidirectional_lookup_forward() -> void:
	_gen.register_definition(_make_definition(&"alpha", &"beta", &"insight_ab"))
	var result: Dictionary = _gen.validate_connection(&"alpha", &"beta")
	assert_bool(result.is_empty()).is_false()
	assert_that(String(result.get("clue_a", &""))).is_equal("alpha")


func test_bidirectional_lookup_reverse() -> void:
	_gen.register_definition(_make_definition(&"alpha", &"beta", &"insight_ab"))
	var result: Dictionary = _gen.validate_connection(&"beta", &"alpha")
	assert_bool(result.is_empty()).is_false()
	assert_that(String(result.get("clue_a", &""))).is_equal("alpha")


func test_bidirectional_lookup_alphabetically_sorted_keys() -> void:
	# If clue names are "zeta" and "alpha", key should be "alpha+zeta"
	_gen.register_definition(_make_definition(&"zeta", &"alpha", &"insight_za"))
	var result: Dictionary = _gen.validate_connection(&"zeta", &"alpha")
	assert_bool(result.is_empty()).is_false()
	# Reverse lookup also works
	var result_rev: Dictionary = _gen.validate_connection(&"alpha", &"zeta")
	assert_bool(result_rev.is_empty()).is_false()


# ---------------------------------------------------------------------------
# Tests: generate_insight
# ---------------------------------------------------------------------------


func test_generate_insight_correct_schema() -> void:
	var def: Dictionary = _make_definition(&"clue_a", &"clue_b", &"insight_1")
	var insight: Dictionary = _gen.generate_insight(def, 3)

	assert_that(String(insight["id"])).is_equal("insight_1")
	assert_int(insight["entry_type"]).is_equal(1)
	assert_that(insight["title"]).is_equal("Test Insight")
	assert_that(insight["description"]).is_equal("A generated insight.")
	assert_that(String(insight["source"])).is_equal("connection")
	assert_int(insight["discovered_at_night"]).is_equal(3)
	assert_that(String(insight["npc_affinity"])).is_equal("guest_indigo")
	assert_that(insight["reinterpretation"]).is_equal("New context.")


func test_generate_insight_source_clues_populated() -> void:
	var def: Dictionary = _make_definition(&"clue_a", &"clue_b", &"insight_1")
	var insight: Dictionary = _gen.generate_insight(def, 1)

	var clues: Array = insight["source_clues"]
	assert_int(clues.size()).is_equal(2)
	assert_that(String(clues[0])).is_equal("clue_a")
	assert_that(String(clues[1])).is_equal("clue_b")


func test_generate_insight_tags_populated() -> void:
	var def: Dictionary = _make_definition(&"a", &"b", &"i1")
	var insight: Dictionary = _gen.generate_insight(def, 1)

	var tags: Array = insight["tags"]
	assert_int(tags.size()).is_equal(2)
	assert_that(String(tags[0])).is_equal("test")
	assert_that(String(tags[1])).is_equal("core")


func test_generate_insight_metadata_weight() -> void:
	var def: Dictionary = _make_definition(&"a", &"b", &"i1")
	var insight: Dictionary = _gen.generate_insight(def, 1)

	var metadata: Dictionary = insight["metadata"]
	assert_float(metadata["weight"]).is_equal(1.5)


func test_generate_insight_contextual_unlocks_empty() -> void:
	var def: Dictionary = _make_definition(&"a", &"b", &"i1")
	var insight: Dictionary = _gen.generate_insight(def, 1)

	var unlocks: Array = insight["contextual_unlocks"]
	assert_int(unlocks.size()).is_equal(0)


func test_generate_insight_missing_nested_keys_graceful() -> void:
	var def: Dictionary = {"clue_a": &"x", "clue_b": &"y"}
	var insight: Dictionary = _gen.generate_insight(def, 5)

	assert_that(String(insight["id"])).is_equal("")
	assert_that(insight["title"]).is_equal("")
	assert_that(insight["description"]).is_equal("")
	assert_that(String(insight["npc_affinity"])).is_equal("")
	assert_that(insight["reinterpretation"]).is_equal("")
	assert_int(insight["entry_type"]).is_equal(1)
	assert_int(insight["discovered_at_night"]).is_equal(5)
	var tags: Array = insight["tags"]
	assert_int(tags.size()).is_equal(0)
	var metadata: Dictionary = insight["metadata"]
	assert_float(metadata["weight"]).is_equal(1.0)  # default weight


func test_generate_insight_missing_resulting_insight_key() -> void:
	var def: Dictionary = {"clue_a": &"p", "clue_b": &"q"}
	# No "resulting_insight" key at all
	var insight: Dictionary = _gen.generate_insight(def, 2)

	assert_that(String(insight["id"])).is_equal("")
	assert_int(insight["entry_type"]).is_equal(1)
	assert_int(insight["discovered_at_night"]).is_equal(2)
	var clues: Array = insight["source_clues"]
	assert_that(String(clues[0])).is_equal("p")
	assert_that(String(clues[1])).is_equal("q")


func test_generate_insight_different_night_values() -> void:
	var def: Dictionary = _make_definition(&"a", &"b", &"i1")
	for night: int in range(1, 8):
		var insight: Dictionary = _gen.generate_insight(def, night)
		assert_int(insight["discovered_at_night"]).is_equal(night)


# ---------------------------------------------------------------------------
# Tests: Duplicate Registration
# ---------------------------------------------------------------------------


func test_duplicate_registration_overwrites() -> void:
	_gen.register_definition(_make_definition(&"a", &"b", &"insight_v1"))
	_gen.register_definition(_make_definition(&"a", &"b", &"insight_v2"))
	assert_int(_gen.get_definition_count()).is_equal(1)

	var result: Dictionary = _gen.validate_connection(&"a", &"b")
	var insight_data: Dictionary = result["resulting_insight"]
	assert_that(String(insight_data["id"])).is_equal("insight_v2")


func test_duplicate_registration_reverse_order() -> void:
	_gen.register_definition(_make_definition(&"a", &"b", &"v1"))
	# Registering b+a is the same key as a+b
	_gen.register_definition(_make_definition(&"b", &"a", &"v2"))
	assert_int(_gen.get_definition_count()).is_equal(1)

	var result: Dictionary = _gen.validate_connection(&"a", &"b")
	assert_that(String(result["resulting_insight"]["id"])).is_equal("v2")
