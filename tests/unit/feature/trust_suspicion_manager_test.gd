extends GdUnitTestSuite

## Tests for TrustSuspicionManager — per-NPC trust/suspicion tracking,
## tier classification, threshold signals, action application, serialization.
## Covers GDD acceptance criteria from design/gdd/npc-trust-suspicion.md.

const TSM_SCRIPT := "res://src/feature/trust_suspicion_manager.gd"

var _manager: Node
var _mock_loop: Node

var _trust_changed_events: Array
var _suspicion_changed_events: Array
var _trust_threshold_events: Array
var _suspicion_threshold_events: Array


func before_test() -> void:
	_mock_loop = Node.new()
	_mock_loop.name = "LoopStateManager"
	_mock_loop.set_script(_create_loop_mock())
	add_child(_mock_loop)

	var wrapper := GDScript.new()
	wrapper.source_code = (
		"extends \"%s\"\n" % TSM_SCRIPT
		+ "var _test_loop: Node = null\n"
		+ "func _get_loop_state_manager() -> Node:\n"
		+ "\treturn _test_loop\n"
	)
	wrapper.reload()

	_manager = Node.new()
	_manager.set_script(wrapper)
	_manager._test_loop = _mock_loop
	_manager.name = "TrustSuspicionManagerTest"
	add_child(_manager)

	_trust_changed_events = []
	_suspicion_changed_events = []
	_trust_threshold_events = []
	_suspicion_threshold_events = []
	_manager.trust_changed.connect(_on_trust_changed)
	_manager.suspicion_changed.connect(_on_suspicion_changed)
	_manager.trust_threshold_crossed.connect(_on_trust_threshold)
	_manager.suspicion_threshold_crossed.connect(_on_suspicion_threshold)


func _on_trust_changed(npc_id: StringName, old_val: float, new_val: float) -> void:
	_trust_changed_events.append({"npc": npc_id, "old": old_val, "new": new_val})


func _on_suspicion_changed(npc_id: StringName, old_val: float, new_val: float) -> void:
	_suspicion_changed_events.append({"npc": npc_id, "old": old_val, "new": new_val})


func _on_trust_threshold(npc_id: StringName, tier: StringName) -> void:
	_trust_threshold_events.append({"npc": npc_id, "tier": tier})


func _on_suspicion_threshold(npc_id: StringName, tier: StringName) -> void:
	_suspicion_threshold_events.append({"npc": npc_id, "tier": tier})


func after_test() -> void:
	if _manager:
		_manager.queue_free()
	if _mock_loop:
		_mock_loop.queue_free()


# ---------------------------------------------------------------------------
# Mock Scripts
# ---------------------------------------------------------------------------


func _create_loop_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal night_ready(night: int)\n"
		+ "signal night_advanced(old_night: int, new_night: int)\n"
		+ "var current_night: int = 1\n"
	)
	script.reload()
	return script


# ---------------------------------------------------------------------------
# Tests: Registration and Getters
# ---------------------------------------------------------------------------


func test_register_npc_defaults() -> void:
	_manager.register_npc(&"guest_indigo")
	assert_float(_manager.get_trust(&"guest_indigo")).is_equal(0.0)
	assert_float(_manager.get_suspicion(&"guest_indigo")).is_equal(0.0)


func test_register_npc_with_initial_values() -> void:
	_manager.register_npc(&"guest_indigo", 20.0, 10.0)
	assert_float(_manager.get_trust(&"guest_indigo")).is_equal(20.0)
	assert_float(_manager.get_suspicion(&"guest_indigo")).is_equal(10.0)


func test_get_unregistered_returns_zero() -> void:
	assert_float(_manager.get_trust(&"unknown")).is_equal(0.0)
	assert_float(_manager.get_suspicion(&"unknown")).is_equal(0.0)


# ---------------------------------------------------------------------------
# Tests: Trust Delta
# ---------------------------------------------------------------------------


func test_trust_delta_positive() -> void:
	_manager.register_npc(&"guest_indigo")
	_manager.apply_trust_delta(&"guest_indigo", 25.0)
	assert_float(_manager.get_trust(&"guest_indigo")).is_equal(25.0)


func test_trust_delta_negative() -> void:
	_manager.register_npc(&"guest_indigo", 50.0)
	_manager.apply_trust_delta(&"guest_indigo", -20.0)
	assert_float(_manager.get_trust(&"guest_indigo")).is_equal(30.0)


func test_trust_clamped_at_max() -> void:
	_manager.register_npc(&"guest_indigo", 90.0)
	_manager.apply_trust_delta(&"guest_indigo", 30.0)
	assert_float(_manager.get_trust(&"guest_indigo")).is_equal(100.0)


func test_trust_clamped_at_zero() -> void:
	_manager.register_npc(&"guest_indigo", 10.0)
	_manager.apply_trust_delta(&"guest_indigo", -30.0)
	assert_float(_manager.get_trust(&"guest_indigo")).is_equal(0.0)


func test_trust_auto_registers_unknown() -> void:
	_manager.apply_trust_delta(&"guest_indigo", 15.0)
	assert_float(_manager.get_trust(&"guest_indigo")).is_equal(15.0)


func test_trust_changed_signal() -> void:
	_manager.register_npc(&"guest_indigo", 10.0)
	_manager.apply_trust_delta(&"guest_indigo", 20.0)
	assert_int(_trust_changed_events.size()).is_equal(1)
	assert_float(_trust_changed_events[0]["old"]).is_equal(10.0)
	assert_float(_trust_changed_events[0]["new"]).is_equal(30.0)


# ---------------------------------------------------------------------------
# Tests: Suspicion Delta
# ---------------------------------------------------------------------------


func test_suspicion_delta_positive() -> void:
	_manager.register_npc(&"guest_indigo")
	_manager.apply_suspicion_delta(&"guest_indigo", 30.0)
	assert_float(_manager.get_suspicion(&"guest_indigo")).is_equal(30.0)


func test_suspicion_clamped_at_max() -> void:
	_manager.register_npc(&"guest_indigo", 0.0, 90.0)
	_manager.apply_suspicion_delta(&"guest_indigo", 30.0)
	assert_float(_manager.get_suspicion(&"guest_indigo")).is_equal(100.0)


func test_suspicion_clamped_at_zero() -> void:
	_manager.register_npc(&"guest_indigo", 5.0)
	_manager.apply_suspicion_delta(&"guest_indigo", -10.0)
	assert_float(_manager.get_suspicion(&"guest_indigo")).is_equal(0.0)


func test_suspicion_changed_signal() -> void:
	_manager.register_npc(&"guest_indigo", 0.0, 10.0)
	_manager.apply_suspicion_delta(&"guest_indigo", 15.0)
	assert_int(_suspicion_changed_events.size()).is_equal(1)
	assert_float(_suspicion_changed_events[0]["old"]).is_equal(10.0)
	assert_float(_suspicion_changed_events[0]["new"]).is_equal(25.0)


# ---------------------------------------------------------------------------
# Tests: Independent Axes
# ---------------------------------------------------------------------------


func test_trust_and_suspicion_independent() -> void:
	_manager.register_npc(&"guest_indigo")
	_manager.apply_trust_delta(&"guest_indigo", 80.0)
	_manager.apply_suspicion_delta(&"guest_indigo", 70.0)
	assert_float(_manager.get_trust(&"guest_indigo")).is_equal(80.0)
	assert_float(_manager.get_suspicion(&"guest_indigo")).is_equal(70.0)


func test_per_npc_independent() -> void:
	_manager.register_npc(&"guest_indigo")
	_manager.register_npc(&"guest_ochre")
	_manager.apply_trust_delta(&"guest_indigo", 50.0)
	assert_float(_manager.get_trust(&"guest_indigo")).is_equal(50.0)
	assert_float(_manager.get_trust(&"guest_ochre")).is_equal(0.0)


# ---------------------------------------------------------------------------
# Tests: Trust Tier Classification
# ---------------------------------------------------------------------------


func test_trust_tier_none() -> void:
	_manager.register_npc(&"guest_indigo")
	assert_str(String(_manager.get_trust_tier(&"guest_indigo"))).is_equal("NONE")


func test_trust_tier_low() -> void:
	_manager.register_npc(&"guest_indigo", 35.0)
	assert_str(String(_manager.get_trust_tier(&"guest_indigo"))).is_equal("LOW")


func test_trust_tier_medium() -> void:
	_manager.register_npc(&"guest_indigo", 65.0)
	assert_str(String(_manager.get_trust_tier(&"guest_indigo"))).is_equal("MEDIUM")


func test_trust_tier_high() -> void:
	_manager.register_npc(&"guest_indigo", 85.0)
	assert_str(String(_manager.get_trust_tier(&"guest_indigo"))).is_equal("HIGH")


func test_trust_tier_boundary() -> void:
	_manager.register_npc(&"guest_indigo", 30.0)
	assert_str(String(_manager.get_trust_tier(&"guest_indigo"))).is_equal("LOW")


# ---------------------------------------------------------------------------
# Tests: Suspicion Tier Classification
# ---------------------------------------------------------------------------


func test_suspicion_tier_calm() -> void:
	_manager.register_npc(&"guest_indigo")
	assert_str(String(_manager.get_suspicion_tier(&"guest_indigo"))).is_equal("CALM")


func test_suspicion_tier_watchful() -> void:
	_manager.register_npc(&"guest_indigo", 0.0, 25.0)
	assert_str(String(_manager.get_suspicion_tier(&"guest_indigo"))).is_equal("WATCHFUL")


func test_suspicion_tier_wary() -> void:
	_manager.register_npc(&"guest_indigo", 0.0, 45.0)
	assert_str(String(_manager.get_suspicion_tier(&"guest_indigo"))).is_equal("WARY")


func test_suspicion_tier_alarmed() -> void:
	_manager.register_npc(&"guest_indigo", 0.0, 65.0)
	assert_str(String(_manager.get_suspicion_tier(&"guest_indigo"))).is_equal("ALARMED")


func test_suspicion_tier_hostile() -> void:
	_manager.register_npc(&"guest_indigo", 0.0, 85.0)
	assert_str(String(_manager.get_suspicion_tier(&"guest_indigo"))).is_equal("HOSTILE")


# ---------------------------------------------------------------------------
# Tests: Threshold Signals
# ---------------------------------------------------------------------------


func test_trust_threshold_crossed() -> void:
	_manager.register_npc(&"guest_indigo", 25.0)
	_manager.apply_trust_delta(&"guest_indigo", 10.0)  # 25 -> 35, NONE -> LOW
	assert_int(_trust_threshold_events.size()).is_equal(1)
	assert_str(String(_trust_threshold_events[0]["tier"])).is_equal("LOW")


func test_no_threshold_event_when_same_tier() -> void:
	_manager.register_npc(&"guest_indigo", 35.0)  # LOW tier
	_manager.apply_trust_delta(&"guest_indigo", 5.0)  # 35 -> 40, still LOW
	assert_int(_trust_threshold_events.size()).is_equal(0)


func test_suspicion_threshold_crossed() -> void:
	_manager.register_npc(&"guest_indigo", 0.0, 15.0)
	_manager.apply_suspicion_delta(&"guest_indigo", 10.0)  # 15 -> 25, CALM -> WATCHFUL
	assert_int(_suspicion_threshold_events.size()).is_equal(1)
	assert_str(String(_suspicion_threshold_events[0]["tier"])).is_equal("WATCHFUL")


# ---------------------------------------------------------------------------
# Tests: Action Application
# ---------------------------------------------------------------------------


func test_apply_action() -> void:
	_manager.register_npc(&"guest_indigo")
	_manager.register_action(&"show_knowledge", {"trust_delta": 15.0, "suspicion_delta": -5.0})
	_manager.apply_action(&"guest_indigo", &"show_knowledge")
	assert_float(_manager.get_trust(&"guest_indigo")).is_equal(15.0)
	assert_float(_manager.get_suspicion(&"guest_indigo")).is_equal(0.0)  # clamped from -5


func test_apply_unknown_action_fails() -> void:
	_manager.register_npc(&"guest_indigo")
	assert_bool(_manager.apply_action(&"guest_indigo", &"nonexistent")).is_false()


func test_apply_action_only_trust() -> void:
	_manager.register_npc(&"guest_indigo")
	_manager.register_action(&"helpful_action", {"trust_delta": 20.0})
	_manager.apply_action(&"guest_indigo", &"helpful_action")
	assert_float(_manager.get_trust(&"guest_indigo")).is_equal(20.0)
	assert_float(_manager.get_suspicion(&"guest_indigo")).is_equal(0.0)


# ---------------------------------------------------------------------------
# Tests: Serialize / Deserialize / Reset
# ---------------------------------------------------------------------------


func test_serialize_roundtrip() -> void:
	_manager.register_npc(&"guest_indigo", 45.0, 30.0)
	_manager.register_npc(&"guest_ochre", 20.0, 60.0)
	var data: Dictionary = _manager.serialize()
	_manager.reset()
	_manager.deserialize(data)
	assert_float(_manager.get_trust(&"guest_indigo")).is_equal(45.0)
	assert_float(_manager.get_suspicion(&"guest_indigo")).is_equal(30.0)
	assert_float(_manager.get_trust(&"guest_ochre")).is_equal(20.0)
	assert_float(_manager.get_suspicion(&"guest_ochre")).is_equal(60.0)


func test_reset_clears_all() -> void:
	_manager.register_npc(&"guest_indigo", 50.0, 50.0)
	_manager.reset()
	assert_float(_manager.get_trust(&"guest_indigo")).is_equal(0.0)
	assert_float(_manager.get_suspicion(&"guest_indigo")).is_equal(0.0)


func test_deserialize_empty_data() -> void:
	_manager.register_npc(&"guest_indigo", 50.0, 50.0)
	_manager.deserialize({})
	assert_float(_manager.get_trust(&"guest_indigo")).is_equal(0.0)


# ---------------------------------------------------------------------------
# Tests: Signal Connection
# ---------------------------------------------------------------------------


func test_loop_state_signals_connected() -> void:
	var advanced_conns: Array = _mock_loop.get_signal_connection_list("night_advanced")
	var found: bool = false
	for conn: Dictionary in advanced_conns:
		var callable: Callable = conn["callable"]
		if callable.get_object() == _manager:
			found = true
	assert_bool(found).is_true()


# ---------------------------------------------------------------------------
# Tests: get_registered_npc_ids
# ---------------------------------------------------------------------------


func test_get_registered_npc_ids() -> void:
	_manager.register_npc(&"guest_indigo", 10.0, 5.0)
	_manager.register_npc(&"guest_ochre", 20.0, 10.0)
	var ids: Array[StringName] = _manager.get_registered_npc_ids()
	assert_int(ids.size()).is_equal(2)
