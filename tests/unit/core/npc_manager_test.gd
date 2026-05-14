extends GdUnitTestSuite

# Tests for NPCManager -- NPC state machine, transition validation,
# template initialization, serialization, and signal emission.
# Covers ADR-0009 validation criteria 1-19.


const NPC_MANAGER_SCRIPT := "res://src/core/npc_manager.gd"

var _manager: Node
var _mock_loop_manager: Node
var _mock_bus: Node
var _state_changed_log: Array
var _dialogue_changed_log: Array
var _interaction_requested_log: Array


func before_test() -> void:
	# Create mock LoopStateManager with propose_delta support
	_mock_loop_manager = Node.new()
	_mock_loop_manager.name = "LoopStateManager"
	_mock_loop_manager.set_script(_create_mock_lsm_script())
	add_child(_mock_loop_manager)

	# Create mock InteractionBus
	_mock_bus = Node.new()
	_mock_bus.name = "InteractionBus"
	_mock_bus.set_script(_create_mock_bus_script())
	add_child(_mock_bus)

	# Create NPCManager with a test wrapper that injects mocks via DI
	var test_wrapper := GDScript.new()
	test_wrapper.source_code = (
		"extends \"%s\"\n" % NPC_MANAGER_SCRIPT
		+ "var _test_lsm: Node = null\n"
		+ "var _test_bus: Node = null\n"
		+ "func _get_loop_state_manager() -> Node:\n"
		+ "\treturn _test_lsm\n"
		+ "func _get_interaction_bus() -> Node:\n"
		+ "\treturn _test_bus\n"
	)
	test_wrapper.reload()

	_manager = Node.new()
	_manager.set_script(test_wrapper)
	_manager._test_lsm = _mock_loop_manager
	_manager._test_bus = _mock_bus
	_manager.name = "NPCManager"
	add_child(_manager)

	# Reset signal logs
	_state_changed_log = []
	_dialogue_changed_log = []
	_interaction_requested_log = []

	# Connect signals
	_manager.npc_state_changed.connect(func(nid, old_s, new_s): _state_changed_log.append({"npc_id": nid, "old": old_s, "new": new_s}))
	_manager.npc_dialogue_availability_changed.connect(func(nid, avail): _dialogue_changed_log.append({"npc_id": nid, "available": avail}))
	_manager.npc_interaction_requested.connect(func(nid, evt): _interaction_requested_log.append({"npc_id": nid, "event": evt}))

	# Reset mock delta log
	_mock_loop_manager._test_propose_delta_log = []


func after_test() -> void:
	if _manager:
		_manager.queue_free()
	if _mock_loop_manager:
		_mock_loop_manager.queue_free()
	if _mock_bus:
		_mock_bus.queue_free()


# --- Helper to create NPCTemplate with test data ---

func _make_template(npc_id: StringName, emotional_state: int = 0, location: StringName = &"", dialogue_available: bool = true, color_key: StringName = &"", per_night_overrides: Dictionary = {}) -> NPCTemplate:
	var t := NPCTemplate.new()
	t.npc_id = npc_id
	t.display_name = String(npc_id).replace("guest_", "").capitalize()
	t.initial_emotional_state = emotional_state
	t.initial_location = location
	t.is_dialogue_available = dialogue_available
	t.color_key = color_key
	t.per_night_overrides = per_night_overrides
	return t


# --- Mock scripts ---

func _create_mock_lsm_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node

signal night_ready(night: int)
signal night_advanced(old_night: int, new_night: int)

var current_night: int = 1
var _test_propose_delta_log: Array = []
var _test_registered_paths: Array = []
var _test_active_state: Dictionary = {}
var _test_propose_delta_result: bool = true

func register_state_paths(paths) -> void:
	_test_registered_paths = paths

func propose_delta(delta: Dictionary) -> bool:
	_test_propose_delta_log.append(delta)
	return _test_propose_delta_result

func get_active_state_value(state_path: StringName) -> Variant:
	return _test_active_state.get(state_path, null)

func reset_test_state() -> void:
	_test_propose_delta_log.clear()
	_test_registered_paths.clear()
	_test_active_state.clear()
	_test_propose_delta_result = true
"""
	script.reload()
	return script


func _create_mock_bus_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node

signal interaction_detected(event: Dictionary)
"""
	script.reload()
	return script


# ============================================================
# Test: NPC Registration
# ============================================================

func test_register_npc_creates_entry() -> void:
	var template: NPCTemplate = _make_template(&"guest_indigo", 0, &"lobby", true, &"indigo")
	_manager.register_npc(&"guest_indigo", template)
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(0)
	assert_that(_manager.get_npc_location(&"guest_indigo")).is_equal(&"lobby")
	assert_bool(_manager.is_dialogue_available(&"guest_indigo")).is_true()


func test_register_npc_overwrites_existing() -> void:
	var t1: NPCTemplate = _make_template(&"guest_indigo", 0, &"lobby")
	var t2: NPCTemplate = _make_template(&"guest_indigo", 2, &"kitchen")
	_manager.register_npc(&"guest_indigo", t1)
	_manager.register_npc(&"guest_indigo", t2)
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(2)
	assert_that(_manager.get_npc_location(&"guest_indigo")).is_equal(&"kitchen")


# ============================================================
# Test: Default NPCs on _ready
# ============================================================

func test_all_five_npcs_registered_on_ready() -> void:
	var ids: Array = _manager.get_all_npc_ids()
	assert_int(ids.size()).is_equal(5)
	assert_bool(ids.has(&"guest_indigo")).is_true()
	assert_bool(ids.has(&"guest_ochre")).is_true()
	assert_bool(ids.has(&"guest_vermilion")).is_true()
	assert_bool(ids.has(&"guest_celadon")).is_true()
	assert_bool(ids.has(&"guest_plum")).is_true()


func test_default_emotional_state_is_neutral() -> void:
	for npc_id: StringName in _manager.get_all_npc_ids():
		assert_int(_manager.get_emotional_state(npc_id)).is_equal(0)


# ============================================================
# Test: get_emotional_state edge cases
# ============================================================

func test_get_emotional_state_unknown_returns_neutral() -> void:
	assert_int(_manager.get_emotional_state(&"unknown_npc")).is_equal(0)


# ============================================================
# Test: is_dialogue_available edge cases
# ============================================================

func test_is_dialogue_available_unknown_returns_false() -> void:
	assert_bool(_manager.is_dialogue_available(&"unknown_npc")).is_false()


# ============================================================
# Test: get_npc_location edge cases
# ============================================================

func test_get_npc_location_unknown_returns_empty() -> void:
	assert_that(_manager.get_npc_location(&"unknown_npc")).is_equal(&"")


# ============================================================
# Test: State path registration
# ============================================================

func test_state_paths_registered_with_loop_state_manager() -> void:
	var registered: Array = _mock_loop_manager._test_registered_paths
	# 5 NPCs x 3 properties = 15 paths
	assert_int(registered.size()).is_equal(15)
	assert_bool(registered.has(&"npcs.guest_indigo.emotional_state")).is_true()
	assert_bool(registered.has(&"npcs.guest_indigo.location")).is_true()
	assert_bool(registered.has(&"npcs.guest_indigo.dialogue_available")).is_true()
	assert_bool(registered.has(&"npcs.guest_plum.dialogue_available")).is_true()


# ============================================================
# Test: Valid state transitions
# ============================================================

func test_neutral_to_curious_accepted() -> void:
	var result: bool = _manager.request_state_transition(&"guest_indigo", 1)  # CURIOUS
	assert_bool(result).is_true()
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(1)


func test_neutral_to_anxious_accepted() -> void:
	assert_bool(_manager.request_state_transition(&"guest_indigo", 2)).is_true()
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(2)


func test_neutral_to_trusting_accepted() -> void:
	assert_bool(_manager.request_state_transition(&"guest_indigo", 4)).is_true()
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(4)


func test_curious_to_trusting_accepted() -> void:
	_manager.request_state_transition(&"guest_indigo", 1)  # NEUTRAL -> CURIOUS
	assert_bool(_manager.request_state_transition(&"guest_indigo", 4)).is_true()  # CURIOUS -> TRUSTING
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(4)


func test_anxious_to_hostile_accepted() -> void:
	_manager.request_state_transition(&"guest_indigo", 2)  # NEUTRAL -> ANXIOUS
	assert_bool(_manager.request_state_transition(&"guest_indigo", 3)).is_true()  # ANXIOUS -> HOSTILE


func test_hostile_to_neutral_accepted() -> void:
	_manager.request_state_transition(&"guest_indigo", 2)  # NEUTRAL -> ANXIOUS
	_manager.request_state_transition(&"guest_indigo", 3)  # ANXIOUS -> HOSTILE
	assert_bool(_manager.request_state_transition(&"guest_indigo", 0)).is_true()  # HOSTILE -> NEUTRAL


func test_trusting_to_curious_accepted() -> void:
	_manager.request_state_transition(&"guest_indigo", 4)  # NEUTRAL -> TRUSTING
	assert_bool(_manager.request_state_transition(&"guest_indigo", 1)).is_true()  # TRUSTING -> CURIOUS


func test_trusting_to_curious_round_trip() -> void:
	_manager.request_state_transition(&"guest_indigo", 1)  # NEUTRAL -> CURIOUS
	_manager.request_state_transition(&"guest_indigo", 4)  # CURIOUS -> TRUSTING
	assert_bool(_manager.request_state_transition(&"guest_indigo", 1)).is_true()  # TRUSTING -> CURIOUS


func test_trusting_to_neutral_accepted() -> void:
	_manager.request_state_transition(&"guest_indigo", 1)  # NEUTRAL -> CURIOUS
	_manager.request_state_transition(&"guest_indigo", 4)  # CURIOUS -> TRUSTING
	assert_bool(_manager.request_state_transition(&"guest_indigo", 0)).is_true()  # TRUSTING -> NEUTRAL


# ============================================================
# Test: Invalid state transitions
# ============================================================

func test_neutral_to_frightened_rejected() -> void:
	var result: bool = _manager.request_state_transition(&"guest_indigo", 5)  # FRIGHTENED
	assert_bool(result).is_false()
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(0)


func test_neutral_to_hostile_rejected() -> void:
	assert_bool(_manager.request_state_transition(&"guest_indigo", 3)).is_false()
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(0)


func test_hostile_to_curious_rejected() -> void:
	_manager.request_state_transition(&"guest_indigo", 2)  # ANXIOUS
	_manager.request_state_transition(&"guest_indigo", 3)  # HOSTILE
	assert_bool(_manager.request_state_transition(&"guest_indigo", 1)).is_false()  # HOSTILE -> CURIOUS invalid
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(3)


func test_same_state_transition_returns_false() -> void:
	var result: bool = _manager.request_state_transition(&"guest_indigo", 0)  # NEUTRAL -> NEUTRAL
	assert_bool(result).is_false()


func test_unknown_npc_transition_returns_false() -> void:
	assert_bool(_manager.request_state_transition(&"nonexistent", 1)).is_false()


# ============================================================
# Test: propose_delta integration
# ============================================================

func test_transition_calls_propose_delta() -> void:
	_manager.request_state_transition(&"guest_indigo", 1)  # NEUTRAL -> CURIOUS
	var log: Array = _mock_loop_manager._test_propose_delta_log
	assert_int(log.size()).is_equal(1)
	assert_that(log[0]["source_action"]).is_equal(&"npc_state_transition")
	assert_that(log[0]["target_path"]).is_equal(&"npcs.guest_indigo.emotional_state")
	assert_int(log[0]["override_value"]).is_equal(1)
	assert_int(log[0]["priority"]).is_equal(0)


func test_propose_delta_rejection_prevents_state_change() -> void:
	_mock_loop_manager._test_propose_delta_result = false
	var result: bool = _manager.request_state_transition(&"guest_indigo", 1)
	assert_bool(result).is_false()
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(0)
	assert_array(_state_changed_log).is_empty()


# ============================================================
# Test: Signal emission
# ============================================================

func test_npc_state_changed_emitted_on_valid_transition() -> void:
	_manager.request_state_transition(&"guest_indigo", 1)  # NEUTRAL -> CURIOUS
	assert_int(_state_changed_log.size()).is_equal(1)
	assert_that(_state_changed_log[0]["npc_id"]).is_equal(&"guest_indigo")
	assert_int(_state_changed_log[0]["old"]).is_equal(0)
	assert_int(_state_changed_log[0]["new"]).is_equal(1)


func test_signal_not_emitted_on_rejected_transition() -> void:
	_manager.request_state_transition(&"guest_indigo", 5)  # NEUTRAL -> FRIGHTENED (invalid)
	assert_array(_state_changed_log).is_empty()


func test_dialogue_availability_signal_emitted() -> void:
	_manager.set_dialogue_availability(&"guest_indigo", false)
	assert_int(_dialogue_changed_log.size()).is_equal(1)
	assert_that(_dialogue_changed_log[0]["npc_id"]).is_equal(&"guest_indigo")
	assert_bool(_dialogue_changed_log[0]["available"]).is_false()


func test_dialogue_availability_signal_not_emitted_on_unknown_npc() -> void:
	_manager.set_dialogue_availability(&"unknown_npc", false)
	assert_array(_dialogue_changed_log).is_empty()


# ============================================================
# Test: force_state_transition
# ============================================================

func test_force_transition_bypasses_validation() -> void:
	var result: bool = _manager.force_state_transition(&"guest_indigo", 5)  # NEUTRAL -> FRIGHTENED
	assert_bool(result).is_true()
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(5)


func test_force_transition_uses_elevated_priority() -> void:
	_manager.force_state_transition(&"guest_indigo", 5)
	var log: Array = _mock_loop_manager._test_propose_delta_log
	assert_int(log.size()).is_equal(1)
	assert_that(log[0]["source_action"]).is_equal(&"npc_narrative_override")
	assert_int(log[0]["priority"]).is_equal(10)


func test_force_transition_unknown_npc_returns_false() -> void:
	assert_bool(_manager.force_state_transition(&"unknown_npc", 1)).is_false()


func test_force_transition_custom_priority() -> void:
	_manager.force_state_transition(&"guest_indigo", 5, 20)
	var log: Array = _mock_loop_manager._test_propose_delta_log
	assert_int(log[0]["priority"]).is_equal(20)


# ============================================================
# Test: set_dialogue_availability
# ============================================================

func test_set_dialogue_availability_success() -> void:
	var result: bool = _manager.set_dialogue_availability(&"guest_indigo", false)
	assert_bool(result).is_true()
	assert_bool(_manager.is_dialogue_available(&"guest_indigo")).is_false()


func test_set_dialogue_availability_unknown_npc() -> void:
	assert_bool(_manager.set_dialogue_availability(&"unknown_npc", false)).is_false()


# ============================================================
# Test: Night initialization from template
# ============================================================

func test_initialize_npcs_from_template() -> void:
	var template: NPCTemplate = _make_template(&"guest_indigo", 1, &"library", true, &"indigo")
	_manager.register_npc(&"guest_indigo", template)
	_manager._initialize_npcs_from_template(1)
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(1)
	assert_that(_manager.get_npc_location(&"guest_indigo")).is_equal(&"library")


func test_initialize_npcs_from_template_uses_default_when_no_template() -> void:
	_manager._initialize_npcs_from_template(1)
	# No .tres files exist; falls back to programmatic default (NEUTRAL)
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(0)


func test_night_ready_signal_initializes_npcs() -> void:
	var template: NPCTemplate = _make_template(&"guest_indigo", 1, &"garden", true, &"indigo")
	_manager.register_npc(&"guest_indigo", template)
	_manager._is_initialized = false
	_mock_loop_manager.night_ready.emit(1)
	assert_bool(_manager._is_initialized).is_true()


func test_night_ready_skips_if_already_initialized() -> void:
	_manager._is_initialized = true
	_mock_loop_manager.night_ready.emit(2)
	# State should remain unchanged (no re-init)
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(0)


func test_night_advanced_reinitializes() -> void:
	_manager._is_initialized = true
	_mock_loop_manager.night_advanced.emit(1, 2)
	assert_bool(_manager._is_initialized).is_true()


# ============================================================
# Test: Per-night overrides from template
# ============================================================

func test_per_night_overrides_applied() -> void:
	var overrides: Dictionary = {
		2: {"emotional_state": 2, "location": &"kitchen", "dialogue_available": false},
	}
	var template: NPCTemplate = _make_template(&"guest_indigo", 0, &"lobby", true, &"indigo", overrides)
	_manager.register_npc(&"guest_indigo", template)
	_manager._initialize_npcs_from_template(2)
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(2)
	assert_that(_manager.get_npc_location(&"guest_indigo")).is_equal(&"kitchen")
	assert_bool(_manager.is_dialogue_available(&"guest_indigo")).is_false()


func test_per_night_overrides_not_applied_for_wrong_night() -> void:
	var overrides: Dictionary = {
		3: {"emotional_state": 2, "location": &"kitchen"},
	}
	var template: NPCTemplate = _make_template(&"guest_indigo", 0, &"lobby", true, &"indigo", overrides)
	_manager.register_npc(&"guest_indigo", template)
	_manager._initialize_npcs_from_template(1)
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(0)
	assert_that(_manager.get_npc_location(&"guest_indigo")).is_equal(&"lobby")


# ============================================================
# Test: Interaction handling
# ============================================================

func test_npc_interaction_emitted_for_npc_events() -> void:
	var event: Dictionary = {"target_type": &"npc", "target_id": &"guest_indigo"}
	_manager._handle_npc_interaction(event)
	assert_int(_interaction_requested_log.size()).is_equal(1)
	assert_that(_interaction_requested_log[0]["npc_id"]).is_equal(&"guest_indigo")


func test_non_npc_events_ignored() -> void:
	var event: Dictionary = {"target_type": &"item", "target_id": &"some_item"}
	_manager._handle_npc_interaction(event)
	assert_array(_interaction_requested_log).is_empty()


func test_unknown_npc_interaction_ignored() -> void:
	var event: Dictionary = {"target_type": &"npc", "target_id": &"unknown_npc"}
	_manager._handle_npc_interaction(event)
	assert_array(_interaction_requested_log).is_empty()


func test_interaction_bus_signal_connected() -> void:
	var event: Dictionary = {"target_type": &"npc", "target_id": &"guest_indigo"}
	_mock_bus.interaction_detected.emit(event)
	assert_int(_interaction_requested_log.size()).is_equal(1)


# ============================================================
# Test: get_npc_ids_in_room
# ============================================================

func test_get_npc_ids_in_room_returns_matching() -> void:
	var t1: NPCTemplate = _make_template(&"guest_indigo", 0, &"lobby")
	var t2: NPCTemplate = _make_template(&"guest_ochre", 0, &"kitchen")
	var t3: NPCTemplate = _make_template(&"guest_vermilion", 0, &"lobby")
	_manager.register_npc(&"guest_indigo", t1)
	_manager.register_npc(&"guest_ochre", t2)
	_manager.register_npc(&"guest_vermilion", t3)
	var in_lobby: Array = _manager.get_npc_ids_in_room(&"lobby")
	assert_int(in_lobby.size()).is_equal(2)
	assert_bool(in_lobby.has(&"guest_indigo")).is_true()
	assert_bool(in_lobby.has(&"guest_vermilion")).is_true()


func test_get_npc_ids_in_room_empty_when_none() -> void:
	var result: Array = _manager.get_npc_ids_in_room(&"nonexistent_room")
	assert_array(result).is_empty()


# ============================================================
# Test: Serialization
# ============================================================

func test_serialize_contains_all_npcs() -> void:
	var data: Dictionary = _manager.serialize()
	assert_int(data["npcs"].size()).is_equal(5)
	assert_int(data["schema_version"]).is_equal(1)


func test_serialize_deserialize_roundtrip() -> void:
	var t: NPCTemplate = _make_template(&"guest_indigo", 1, &"library", true, &"indigo")
	_manager.register_npc(&"guest_indigo", t)
	_manager.request_state_transition(&"guest_indigo", 1)  # NEUTRAL -> CURIOUS

	var data: Dictionary = _manager.serialize()
	assert_bool(_manager.deserialize(data)).is_true()
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(1)
	assert_that(_manager.get_npc_location(&"guest_indigo")).is_equal(&"library")
	assert_bool(_manager.is_dialogue_available(&"guest_indigo")).is_true()


func test_deserialize_empty_returns_false() -> void:
	assert_bool(_manager.deserialize({})).is_false()


func test_deserialize_restores_all_npcs() -> void:
	var data: Dictionary = _manager.serialize()
	_manager._npc_registry.clear()
	assert_bool(_manager.deserialize(data)).is_true()
	var ids: Array = _manager.get_all_npc_ids()
	assert_int(ids.size()).is_equal(5)


# ============================================================
# Test: Reset
# ============================================================

func test_reset_restores_defaults() -> void:
	_manager.request_state_transition(&"guest_indigo", 1)
	_manager.reset()
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(0)
	assert_bool(_manager._is_initialized).is_false()
	var ids: Array = _manager.get_all_npc_ids()
	assert_int(ids.size()).is_equal(5)


# ============================================================
# Test: Propose delta graceful degradation (no LSM)
# ============================================================

func test_transition_succeeds_without_loop_state_manager() -> void:
	# Remove mock LSM
	remove_child(_mock_loop_manager)
	_mock_loop_manager.queue_free()
	_mock_loop_manager = null

	# Transition should still succeed (graceful degradation)
	assert_bool(_manager.request_state_transition(&"guest_indigo", 1)).is_true()
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(1)


# ============================================================
# Test: Transition validation completeness
# ============================================================

func test_all_valid_transitions_from_neutral() -> void:
	var valid_targets: Array[int] = [1, 2, 4]  # CURIOUS, ANXIOUS, TRUSTING
	for target: int in valid_targets:
		assert_bool(_manager._is_valid_transition(0, target)).is_true()
	# Invalid from NEUTRAL
	assert_bool(_manager._is_valid_transition(0, 3)).is_false()  # HOSTILE
	assert_bool(_manager._is_valid_transition(0, 5)).is_false()  # FRIGHTENED


func test_all_valid_transitions_from_curious() -> void:
	var valid_targets: Array[int] = [0, 4, 2]  # NEUTRAL, TRUSTING, ANXIOUS
	for target: int in valid_targets:
		assert_bool(_manager._is_valid_transition(1, target)).is_true()
	assert_bool(_manager._is_valid_transition(1, 3)).is_false()  # HOSTILE
	assert_bool(_manager._is_valid_transition(1, 5)).is_false()  # FRIGHTENED


func test_all_valid_transitions_from_anxious() -> void:
	var valid_targets: Array[int] = [3, 5, 0]  # HOSTILE, FRIGHTENED, NEUTRAL
	for target: int in valid_targets:
		assert_bool(_manager._is_valid_transition(2, target)).is_true()
	assert_bool(_manager._is_valid_transition(2, 1)).is_false()  # CURIOUS
	assert_bool(_manager._is_valid_transition(2, 4)).is_false()  # TRUSTING


func test_all_valid_transitions_from_hostile() -> void:
	var valid_targets: Array[int] = [2, 0]  # ANXIOUS, NEUTRAL
	for target: int in valid_targets:
		assert_bool(_manager._is_valid_transition(3, target)).is_true()
	assert_bool(_manager._is_valid_transition(3, 1)).is_false()  # CURIOUS
	assert_bool(_manager._is_valid_transition(3, 4)).is_false()  # TRUSTING
	assert_bool(_manager._is_valid_transition(3, 5)).is_false()  # FRIGHTENED


func test_all_valid_transitions_from_trusting() -> void:
	var valid_targets: Array[int] = [0, 1, 2]  # NEUTRAL, CURIOUS, ANXIOUS
	for target: int in valid_targets:
		assert_bool(_manager._is_valid_transition(4, target)).is_true()
	assert_bool(_manager._is_valid_transition(4, 3)).is_false()  # HOSTILE
	assert_bool(_manager._is_valid_transition(4, 5)).is_false()  # FRIGHTENED


func test_all_valid_transitions_from_frightened() -> void:
	var valid_targets: Array[int] = [2, 3, 0]  # ANXIOUS, HOSTILE, NEUTRAL
	for target: int in valid_targets:
		assert_bool(_manager._is_valid_transition(5, target)).is_true()
	assert_bool(_manager._is_valid_transition(5, 1)).is_false()  # CURIOUS
	assert_bool(_manager._is_valid_transition(5, 4)).is_false()  # TRUSTING


# ============================================================
# Test: Persisted state from LoopStateManager takes precedence
# ============================================================

func test_persisted_state_takes_precedence_over_template() -> void:
	var template: NPCTemplate = _make_template(&"guest_indigo", 0, &"lobby")
	_manager.register_npc(&"guest_indigo", template)
	# Set a persisted state value via mock LSM
	_mock_loop_manager._test_active_state[&"npcs.guest_indigo.emotional_state"] = 3  # HOSTILE
	_manager._initialize_npcs_from_template(1)
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(3)


func test_template_used_when_no_persisted_state() -> void:
	var template: NPCTemplate = _make_template(&"guest_indigo", 1, &"garden")
	_manager.register_npc(&"guest_indigo", template)
	_manager._initialize_npcs_from_template(1)
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(1)


# ============================================================
# Test: Multi-step transition path (NEUTRAL -> ... -> FRIGHTENED)
# ============================================================

func test_neutral_to_frightened_via_multi_step() -> void:
	# NEUTRAL -> CURIOUS -> ANXIOUS -> FRIGHTENED
	assert_bool(_manager.request_state_transition(&"guest_indigo", 1)).is_true()  # CURIOUS
	assert_bool(_manager.request_state_transition(&"guest_indigo", 2)).is_true()  # ANXIOUS
	assert_bool(_manager.request_state_transition(&"guest_indigo", 5)).is_true()  # FRIGHTENED
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(5)


func test_neutral_to_frightened_via_anxious() -> void:
	# NEUTRAL -> ANXIOUS -> FRIGHTENED
	assert_bool(_manager.request_state_transition(&"guest_indigo", 2)).is_true()  # ANXIOUS
	assert_bool(_manager.request_state_transition(&"guest_indigo", 5)).is_true()  # FRIGHTENED
	assert_int(_manager.get_emotional_state(&"guest_indigo")).is_equal(5)
