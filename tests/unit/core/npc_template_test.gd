extends GdUnitTestSuite

## Tests for NPCTemplate — default values, property read/write, dictionary fields.
## NPCTemplate is a Resource data class with no logic methods.
## Covers ADR-0009 NPC State Machine data definitions.


var _template: Resource


func before_test() -> void:
	_template = Resource.new()
	_template.set_script(load("res://src/core/npc_template.gd"))


func after_test() -> void:
	_template = null


# ---------------------------------------------------------------------------
# Tests: Default Values
# ---------------------------------------------------------------------------


func test_defaults_npc_id_is_empty_stringname() -> void:
	assert_that(String(_template.npc_id)).is_equal("")


func test_defaults_display_name_is_empty_string() -> void:
	assert_that(_template.display_name).is_equal("")


func test_defaults_initial_emotional_state_is_neutral() -> void:
	assert_int(_template.initial_emotional_state).is_equal(0)


func test_defaults_initial_location_is_empty_stringname() -> void:
	assert_that(String(_template.initial_location)).is_equal("")


func test_defaults_is_dialogue_available_is_true() -> void:
	assert_bool(_template.is_dialogue_available).is_true()


func test_defaults_dialogue_id_is_empty_stringname() -> void:
	assert_that(String(_template.dialogue_id)).is_equal("")


func test_defaults_portrait_is_null() -> void:
	assert_object(_template.portrait).is_null()


func test_defaults_color_key_is_empty_stringname() -> void:
	assert_that(String(_template.color_key)).is_equal("")


func test_defaults_per_night_overrides_is_empty_dict() -> void:
	assert_dict(_template.per_night_overrides).is_empty()


func test_defaults_conditions_is_empty_dict() -> void:
	assert_dict(_template.conditions).is_empty()


# ---------------------------------------------------------------------------
# Tests: Property Read/Write
# ---------------------------------------------------------------------------


func test_set_and_read_npc_id() -> void:
	_template.npc_id = &"guest_indigo"
	assert_that(String(_template.npc_id)).is_equal("guest_indigo")


func test_set_and_read_display_name() -> void:
	_template.display_name = "The Indigo Guest"
	assert_that(_template.display_name).is_equal("The Indigo Guest")


func test_set_and_read_initial_emotional_state() -> void:
	_template.initial_emotional_state = 3
	assert_int(_template.initial_emotional_state).is_equal(3)


func test_set_and_read_initial_location() -> void:
	_template.initial_location = &"study"
	assert_that(String(_template.initial_location)).is_equal("study")


func test_set_and_read_is_dialogue_available() -> void:
	_template.is_dialogue_available = false
	assert_bool(_template.is_dialogue_available).is_false()


func test_set_and_read_dialogue_id() -> void:
	_template.dialogue_id = &"night_3_indigo"
	assert_that(String(_template.dialogue_id)).is_equal("night_3_indigo")


func test_set_and_read_color_key() -> void:
	_template.color_key = &"ochre"
	assert_that(String(_template.color_key)).is_equal("ochre")


# ---------------------------------------------------------------------------
# Tests: Dictionary Fields
# ---------------------------------------------------------------------------


func test_per_night_overrides_accepts_night_data() -> void:
	var overrides: Dictionary = {
		2: {"emotional_state": 1, "location": &"kitchen"},
		5: {"emotional_state": 2, "dialogue_available": false},
	}
	_template.per_night_overrides = overrides
	assert_int(_template.per_night_overrides.size()).is_equal(2)
	assert_int(_template.per_night_overrides[2]["emotional_state"]).is_equal(1)
	assert_bool(_template.per_night_overrides[5]["dialogue_available"]).is_false()


func test_conditions_accepts_arbitrary_keys() -> void:
	var conds: Dictionary = {
		"has_met_indigo": true,
		"night_greater_than": 3,
	}
	_template.conditions = conds
	assert_bool(_template.conditions["has_met_indigo"]).is_true()
	assert_int(_template.conditions["night_greater_than"]).is_equal(3)


func test_per_night_overrides_replacement() -> void:
	_template.per_night_overrides = {1: {"emotional_state": 0}}
	assert_int(_template.per_night_overrides.size()).is_equal(1)
	_template.per_night_overrides = {2: {"emotional_state": 1}, 3: {"emotional_state": 2}}
	assert_int(_template.per_night_overrides.size()).is_equal(2)


func test_conditions_replacement() -> void:
	_template.conditions = {"a": true}
	assert_int(_template.conditions.size()).is_equal(1)
	_template.conditions = {}
	assert_dict(_template.conditions).is_empty()
