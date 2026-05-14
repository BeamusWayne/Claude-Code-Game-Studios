extends GdUnitTestSuite

## Tests for InterrogationManager — pressure mechanics, emotional states,
## clue presentation, breakdown/angry exit, trust/suspicion amplification.
## Covers GDD acceptance criteria from design/gdd/guest-interrogation.md.

const IM_SCRIPT := "res://src/feature/interrogation_manager.gd"

var _manager: Node
var _mock_dm: Node
var _mock_npc: Node
var _mock_trust: Node
var _mock_db: Node

var _started_events: Array
var _ended_events: Array
var _pressure_events: Array
var _emotion_events: Array


func before_test() -> void:
	_mock_dm = Node.new()
	_mock_dm.name = "DialogueManager"
	_mock_dm.set_script(_create_dm_mock())
	add_child(_mock_dm)

	_mock_npc = Node.new()
	_mock_npc.name = "NPCManager"
	_mock_npc.set_script(_create_npc_mock())
	add_child(_mock_npc)

	_mock_trust = Node.new()
	_mock_trust.name = "TrustSuspicionManager"
	_mock_trust.set_script(_create_trust_mock())
	add_child(_mock_trust)

	_mock_db = Node.new()
	_mock_db.name = "ClueDatabase"
	_mock_db.set_script(_create_db_mock())
	add_child(_mock_db)

	var wrapper := GDScript.new()
	wrapper.source_code = (
		"extends \"%s\"\n" % IM_SCRIPT
		+ "var _test_dm: Node = null\n"
		+ "var _test_npc: Node = null\n"
		+ "var _test_trust: Node = null\n"
		+ "var _test_db: Node = null\n"
		+ "func _get_dialogue_manager() -> Node:\n"
		+ "\treturn _test_dm\n"
		+ "func _get_npc_manager() -> Node:\n"
		+ "\treturn _test_npc\n"
		+ "func _get_trust_manager() -> Node:\n"
		+ "\treturn _test_trust\n"
		+ "func _get_clue_database() -> Node:\n"
		+ "\treturn _test_db\n"
	)
	wrapper.reload()

	_manager = Node.new()
	_manager.set_script(wrapper)
	_manager._test_dm = _mock_dm
	_manager._test_npc = _mock_npc
	_manager._test_trust = _mock_trust
	_manager._test_db = _mock_db
	_manager.name = "InterrogationManagerTest"
	add_child(_manager)

	_started_events = []
	_ended_events = []
	_pressure_events = []
	_emotion_events = []
	_manager.interrogation_started.connect(_on_started)
	_manager.interrogation_ended.connect(_on_ended)
	_manager.pressure_changed.connect(_on_pressure)
	_manager.interrogation_emotional_state_changed.connect(_on_emotion)


func _on_started(npc_id: StringName) -> void:
	_started_events.append(npc_id)

func _on_ended(npc_id: StringName, result: StringName) -> void:
	_ended_events.append({"npc": npc_id, "result": result})

func _on_pressure(npc_id: StringName, old_p: float, new_p: float) -> void:
	_pressure_events.append({"npc": npc_id, "old": old_p, "new": new_p})

func _on_emotion(npc_id: StringName, old_s: StringName, new_s: StringName) -> void:
	_emotion_events.append({"npc": npc_id, "old": old_s, "new": new_s})


func after_test() -> void:
	if _manager:
		_manager.queue_free()
	if _mock_dm:
		_mock_dm.queue_free()
	if _mock_npc:
		_mock_npc.queue_free()
	if _mock_trust:
		_mock_trust.queue_free()
	if _mock_db:
		_mock_db.queue_free()


# ---------------------------------------------------------------------------
# Mock Scripts
# ---------------------------------------------------------------------------


func _create_dm_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var _is_active: bool = false\n"
		+ "var is_active: bool:\n"
		+ "\tget:\n"
		+ "\t\treturn _is_active\n"
	)
	script.reload()
	return script


func _create_npc_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var _dialogue_available: Dictionary = {}\n"
		+ "var _state_transitions: Array = []\n"
		+ "var _dialogue_set_calls: Array = []\n"
		+ "func is_dialogue_available(npc_id: StringName) -> bool:\n"
		+ "\treturn _dialogue_available.get(npc_id, true)\n"
		+ "func request_state_transition(npc_id: StringName, new_state: int) -> bool:\n"
		+ "\t_state_transitions.append({\"npc\": npc_id, \"state\": new_state})\n"
		+ "\treturn true\n"
		+ "func set_dialogue_availability(npc_id: StringName, available: bool) -> void:\n"
		+ "\t_dialogue_available[npc_id] = available\n"
		+ "\t_dialogue_set_calls.append({\"npc\": npc_id, \"available\": available})\n"
	)
	script.reload()
	return script


func _create_trust_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var _trust: Dictionary = {}\n"
		+ "var _suspicion: Dictionary = {}\n"
		+ "var _trust_deltas: Array = []\n"
		+ "var _suspicion_deltas: Array = []\n"
		+ "func get_trust(npc_id: StringName) -> float:\n"
		+ "\treturn _trust.get(npc_id, 50.0)\n"
		+ "func get_suspicion(npc_id: StringName) -> float:\n"
		+ "\treturn _suspicion.get(npc_id, 0.0)\n"
		+ "func apply_trust_delta(npc_id: StringName, delta: float) -> float:\n"
		+ "\tif not _trust.has(npc_id):\n"
		+ "\t\t_trust[npc_id] = 50.0\n"
		+ "\t_trust[npc_id] = clampf(_trust[npc_id] + delta, 0.0, 100.0)\n"
		+ "\t_trust_deltas.append({\"npc\": npc_id, \"delta\": delta})\n"
		+ "\treturn _trust[npc_id]\n"
		+ "func apply_suspicion_delta(npc_id: StringName, delta: float) -> float:\n"
		+ "\tif not _suspicion.has(npc_id):\n"
		+ "\t_suspicion[npc_id] = 0.0\n"
		+ "\t_suspicion[npc_id] = clampf(_suspicion[npc_id] + delta, 0.0, 100.0)\n"
		+ "\t_suspicion_deltas.append({\"npc\": npc_id, \"delta\": delta})\n"
		+ "\treturn _suspicion[npc_id]\n"
	)
	script.reload()
	return script


func _create_db_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var _entries: Dictionary = {}\n"
		+ "func get_all_clues() -> Array:\n"
		+ "\tvar result: Array = []\n"
		+ "\tfor id: StringName in _entries:\n"
		+ "\t\tif _entries[id].get(\"entry_type\", 0) == 0:\n"
		+ "\t\t\tresult.append(id)\n"
		+ "\treturn result\n"
		+ "func get_entry(id: StringName) -> Dictionary:\n"
		+ "\treturn _entries.get(id, {})\n"
		+ "func has_clue(id: StringName) -> bool:\n"
		+ "\treturn _entries.has(id) and _entries[id].get(\"entry_type\", 0) == 0\n"
		+ "func search_by_npc(npc_affinity: StringName) -> Array:\n"
		+ "\tvar result: Array = []\n"
		+ "\tfor id: StringName in _entries:\n"
		+ "\t\tif _entries[id].get(\"npc_affinity\", &\"\") == npc_affinity:\n"
		+ "\t\t\tresult.append(id)\n"
		+ "\treturn result\n"
		+ "func add_entry(entry: Dictionary) -> bool:\n"
		+ "\t_entries[entry[\"id\"]] = entry\n"
		+ "\treturn true\n"
	)
	script.reload()
	return script


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _add_clue(clue_id: String, npc_affinity: String, tags: Array = []) -> void:
	_mock_db._entries[StringName(clue_id)] = {
		"id": StringName(clue_id),
		"entry_type": 0,
		"title": clue_id,
		"description": "",
		"source": &"test",
		"discovered_at_night": 1,
		"npc_affinity": StringName(npc_affinity),
		"tags": tags,
		"contextual_unlocks": [],
		"metadata": {},
	}


func _start_interrogation(npc_id: String = "guest_indigo", config: Dictionary = {}) -> Dictionary:
	return _manager.start_interrogation(StringName(npc_id), config)


# ---------------------------------------------------------------------------
# AC 1: start_interrogation initializes correctly
# ---------------------------------------------------------------------------


func test_start_interrogation_initializes_session() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_mock_npc._dialogue_available[StringName(&"guest_indigo")] = true

	var result: Dictionary = _start_interrogation()

	assert_eq(result["ok"], true)
	assert_eq(_manager.current_npc, StringName(&"guest_indigo"))
	assert_eq(_manager.current_pressure, 0.0)
	assert_eq(_manager.current_emotional_state, 0)  # NEUTRAL
	assert_eq(_manager.turns_count, 0)
	assert_eq(_manager.is_active, true)
	assert_eq(_started_events.size(), 1)
	assert_eq(_started_events[0], StringName(&"guest_indigo"))


# ---------------------------------------------------------------------------
# AC 2: Trigger condition checks
# ---------------------------------------------------------------------------


func test_start_rejected_when_dialogue_active() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_mock_dm._is_active = true

	var result: Dictionary = _start_interrogation()
	assert_eq(result["ok"], false)
	assert_eq(result["reason"], "dialogue_already_active")


func test_start_rejected_when_npc_unavailable() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_mock_npc._dialogue_available[StringName(&"guest_indigo")] = false

	var result: Dictionary = _start_interrogation()
	assert_eq(result["ok"], false)
	assert_eq(result["reason"], "npc_not_available")


func test_start_rejected_when_suspicion_too_high() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_mock_trust._suspicion[StringName(&"guest_indigo")] = 85.0

	var result: Dictionary = _start_interrogation()
	assert_eq(result["ok"], false)
	assert_eq(result["reason"], "npc_suspicion_too_high")


func test_start_rejected_when_no_related_clues() -> void:
	var result: Dictionary = _start_interrogation()
	assert_eq(result["ok"], false)
	assert_eq(result["reason"], "no_related_clues")


func test_start_rejected_when_already_active() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation()

	var result: Dictionary = _start_interrogation()
	assert_eq(result["ok"], false)
	assert_eq(result["reason"], "interrogation_already_active")


# ---------------------------------------------------------------------------
# AC 3: Clear rejection reasons
# ---------------------------------------------------------------------------


func test_start_returns_clear_failure_reasons() -> void:
	_mock_trust._suspicion[StringName(&"guest_indigo")] = 90.0
	var result: Dictionary = _start_interrogation()
	assert_eq(result["ok"], false)
	assert_ne(result["reason"], "")


# ---------------------------------------------------------------------------
# AC 4: Pressure deltas applied per option type
# ---------------------------------------------------------------------------


func test_apply_option_gentle_probe_pressure() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation()

	var result: Dictionary = _manager.apply_option("gentle_probe")
	assert_eq(result["ok"], true)
	assert_eq(_manager.current_pressure, 3.0)  # 5.0 - 2.0 decay


func test_apply_option_threaten_pressure() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation()

	_manager.apply_option("threaten")
	assert_eq(_manager.current_pressure, 18.0)  # 20.0 - 2.0 decay


func test_apply_option_comfort_reduces_pressure() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation()
	_manager.apply_option("threaten")  # 18.0

	_manager.apply_option("comfort")
	assert_eq(_manager.current_pressure, 11.0)  # 18.0 + (-5.0) - 2.0


func test_apply_option_observe_no_pressure_change() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation()
	_manager.apply_option("direct_question")  # 8.0

	_manager.apply_option("observe")
	assert_eq(_manager.current_pressure, 6.0)  # 8.0 + 0.0 - 2.0


# ---------------------------------------------------------------------------
# AC 5: Emotional state transitions
# ---------------------------------------------------------------------------


func test_emotional_state_neutral_at_zero() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation()
	assert_eq(_manager.current_emotional_state, 0)  # NEUTRAL


func test_emotional_state_anxious_at_30() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation({"pressure_decay_per_turn": 0.0})

	_manager.apply_option("threaten")  # 20
	_manager.apply_option("direct_question")  # 30

	assert_eq(_manager.current_emotional_state, 1)  # ANXIOUS


func test_emotional_state_frightened_at_60() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation({"pressure_decay_per_turn": 0.0})

	_manager.apply_option("threaten")  # 20
	_manager.apply_option("threaten")  # 40
	_manager.apply_option("threaten")  # 60

	assert_eq(_manager.current_emotional_state, 2)  # FRIGHTENED


func test_emotional_state_hostile_at_80() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation({"pressure_decay_per_turn": 0.0})

	for _i: int in range(4):
		_manager.apply_option("threaten")  # 80

	assert_eq(_manager.current_emotional_state, 3)  # HOSTILE


func test_emotional_state_exit_triggers_angry_exit() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation({"pressure_decay_per_turn": 0.0})

	for _i: int in range(5):
		_manager.apply_option("threaten")  # 100 -> EXIT

	assert_eq(_manager.is_active, false)
	assert_eq(_ended_events.size(), 1)
	assert_eq(_ended_events[0]["result"], &"ANGRY_EXIT")


# ---------------------------------------------------------------------------
# AC 6: Strong clue bonus (npc_affinity match)
# ---------------------------------------------------------------------------


func test_present_clue_strong_affinity_full_bonus() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation()

	var result: Dictionary = _manager.apply_option("present_clue", StringName(&"clue_lantern"))
	assert_eq(result["clue_bonus"], 10.0)
	assert_eq(_manager.current_pressure, 23.0)  # 15.0 + 10.0 - 2.0


# ---------------------------------------------------------------------------
# AC 7: Weak clue bonus (tags match)
# ---------------------------------------------------------------------------


func test_present_clue_weak_affinity_half_bonus() -> void:
	_add_clue("clue_lantern", "guest_ochre", [StringName(&"guest_indigo")])
	_start_interrogation()

	var result: Dictionary = _manager.apply_option("present_clue", StringName(&"clue_lantern"))
	assert_eq(result["clue_bonus"], 5.0)


# ---------------------------------------------------------------------------
# AC 8: Unrelated clue — no bonus + trust penalty
# ---------------------------------------------------------------------------


func test_present_unrelated_clue_no_bonus_trust_penalty() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_add_clue("clue_other", "guest_ochre", [StringName(&"guest_plum")])
	_start_interrogation()

	var result: Dictionary = _manager.apply_option("present_clue", StringName(&"clue_other"))
	assert_eq(result["clue_bonus"], 0.0)

	var trust_deltas: Array = _mock_trust._trust_deltas
	assert_true(trust_deltas.size() >= 1)
	var last_trust: Dictionary = trust_deltas[trust_deltas.size() - 1]
	assert_eq(last_trust["npc"], StringName(&"guest_indigo"))
	assert_eq(last_trust["delta"], -7.5)  # -5.0 * 1.5


# ---------------------------------------------------------------------------
# AC 9: Interrogation multiplier on trust/suspicion
# ---------------------------------------------------------------------------


func test_interrogation_multiplier_amplifies_deltas() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation()

	_manager.apply_option("threaten", &"", -8.0, 10.0)

	var trust_deltas: Array = _mock_trust._trust_deltas
	var susp_deltas: Array = _mock_trust._suspicion_deltas
	assert_eq(trust_deltas[0]["delta"], -6.0)  # -8.0 * 0.5 * 1.5
	assert_eq(susp_deltas[0]["delta"], 30.0)  # 10.0 * 2.0 * 1.5


# ---------------------------------------------------------------------------
# AC 10: Breakdown trigger
# ---------------------------------------------------------------------------


func test_breakdown_when_pressure_above_success_and_anxious() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation({
		"pressure_decay_per_turn": 0.0,
		"pressure_success_threshold": 35.0,
		"pressure_fail_threshold": 150.0,
	})

	_manager.apply_option("threaten")  # 20 -> NEUTRAL
	_manager.apply_option("direct_question")  # 30 -> ANXIOUS
	_manager.apply_option("direct_question")  # 40 -> ANXIOUS, >= 35 -> BREAKDOWN

	assert_eq(_manager.is_active, false)
	assert_eq(_ended_events.size(), 1)
	assert_eq(_ended_events[0]["result"], &"BREAKDOWN")


func test_breakdown_when_frightened() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation({
		"pressure_decay_per_turn": 0.0,
		"pressure_success_threshold": 65.0,
		"pressure_fail_threshold": 150.0,
	})

	for _i: int in range(3):
		_manager.apply_option("threaten")  # 60 -> FRIGHTENED
	_manager.apply_option("direct_question")  # 70 -> FRIGHTENED, >= 65 -> BREAKDOWN

	assert_eq(_ended_events.size(), 1)
	assert_eq(_ended_events[0]["result"], &"BREAKDOWN")


# ---------------------------------------------------------------------------
# AC 11: Angry exit at fail threshold
# ---------------------------------------------------------------------------


func test_angry_exit_at_fail_threshold() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation({"pressure_decay_per_turn": 0.0})

	for _i: int in range(5):
		_manager.apply_option("threaten")  # 100 -> EXIT

	assert_eq(_manager.is_active, false)
	assert_eq(_ended_events[0]["result"], &"ANGRY_EXIT")


# ---------------------------------------------------------------------------
# AC 12: Breakdown consequences (trust +5, suspicion -3)
# ---------------------------------------------------------------------------


func test_breakdown_applies_trust_bonus_suspicion_reduction() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation({
		"pressure_decay_per_turn": 0.0,
		"pressure_success_threshold": 35.0,
		"pressure_fail_threshold": 150.0,
	})

	_manager.apply_option("threaten")  # 20
	_manager.apply_option("direct_question")  # 30
	_manager.apply_option("direct_question")  # 40 -> BREAKDOWN

	var trust_deltas: Array = _mock_trust._trust_deltas
	var last_trust: Dictionary = trust_deltas[trust_deltas.size() - 1]
	assert_eq(last_trust["delta"], 5.0)

	var susp_deltas: Array = _mock_trust._suspicion_deltas
	var last_susp: Dictionary = susp_deltas[susp_deltas.size() - 1]
	assert_eq(last_susp["delta"], -3.0)


# ---------------------------------------------------------------------------
# AC 13: Angry exit consequences
# ---------------------------------------------------------------------------


func test_angry_exit_applies_penalties() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation({"pressure_decay_per_turn": 0.0})

	for _i: int in range(5):
		_manager.apply_option("threaten")

	var trust_deltas: Array = _mock_trust._trust_deltas
	var last_trust: Dictionary = trust_deltas[trust_deltas.size() - 1]
	assert_eq(last_trust["delta"], -10.0)

	var susp_deltas: Array = _mock_trust._suspicion_deltas
	var last_susp: Dictionary = susp_deltas[susp_deltas.size() - 1]
	assert_eq(last_susp["delta"], 15.0)

	var transitions: Array = _mock_npc._state_transitions
	assert_true(transitions.size() >= 1)
	assert_eq(transitions[transitions.size() - 1]["state"], 3)  # HOSTILE

	assert_eq(_mock_npc._dialogue_set_calls.size(), 1)
	assert_eq(_mock_npc._dialogue_set_calls[0]["available"], false)


# ---------------------------------------------------------------------------
# AC 14: Voluntary end — no extra consequences
# ---------------------------------------------------------------------------


func test_voluntary_end_no_extra_consequences() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation()

	_manager.apply_option("gentle_probe")
	var trust_before: int = _mock_trust._trust_deltas.size()
	var susp_before: int = _mock_trust._suspicion_deltas.size()

	_manager.end_voluntary()

	assert_eq(_manager.is_active, false)
	assert_eq(_ended_events[0]["result"], &"VOLUNTARY_END")
	assert_eq(_mock_trust._trust_deltas.size(), trust_before)
	assert_eq(_mock_trust._suspicion_deltas.size(), susp_before)


# ---------------------------------------------------------------------------
# AC 15: NPC state sync after interrogation ends
# ---------------------------------------------------------------------------


func test_npc_state_synced_after_interrogation() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation()
	_manager.apply_option("gentle_probe")

	_manager.end_voluntary()

	var transitions: Array = _mock_npc._state_transitions
	assert_true(transitions.size() >= 1)
	assert_eq(transitions[0]["npc"], StringName(&"guest_indigo"))


# ---------------------------------------------------------------------------
# AC 16: DialogueManager.is_active during interrogation
# ---------------------------------------------------------------------------


func test_dialogue_manager_active_during_interrogation() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation()

	assert_eq(_mock_dm._is_active, true)

	_manager.end_voluntary()

	assert_eq(_mock_dm._is_active, false)


# ---------------------------------------------------------------------------
# AC 17: Graceful degradation without TrustManager
# ---------------------------------------------------------------------------


func test_works_without_trust_manager() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_manager._test_trust = null

	var result: Dictionary = _start_interrogation()
	assert_eq(result["ok"], true)

	var opt_result: Dictionary = _manager.apply_option("gentle_probe")
	assert_eq(opt_result["ok"], true)


func test_suspicion_defaults_zero_without_trust_manager() -> void:
	_manager._test_trust = null
	_add_clue("clue_lantern", "guest_indigo")

	var result: Dictionary = _start_interrogation()
	assert_eq(result["ok"], true)


# ---------------------------------------------------------------------------
# AC 18: ClueDatabase unavailable — present disabled
# ---------------------------------------------------------------------------


func test_clue_presentation_disabled_without_database() -> void:
	_manager._test_db = null

	var result: Dictionary = _start_interrogation()
	assert_eq(result["ok"], false)
	assert_eq(result["reason"], "no_related_clues")


# ---------------------------------------------------------------------------
# AC 19: interrogation_ended signal carries correct data
# ---------------------------------------------------------------------------


func test_interrogation_ended_signal_npc_id_and_result() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation()

	_manager.end_voluntary()

	assert_eq(_ended_events.size(), 1)
	assert_eq(_ended_events[0]["npc"], StringName(&"guest_indigo"))
	assert_eq(_ended_events[0]["result"], &"VOLUNTARY_END")


# ---------------------------------------------------------------------------
# AC 20: Multiple interrogations same NPC accumulate trust/suspicion
# ---------------------------------------------------------------------------


func test_multiple_interrogations_same_npc_accumulate() -> void:
	_add_clue("clue_lantern", "guest_indigo")

	_start_interrogation()
	_manager.apply_option("gentle_probe", &"", 5.0, 2.0)
	_manager.end_voluntary()

	assert_eq(_manager.is_active, false)

	var result: Dictionary = _start_interrogation()
	assert_eq(result["ok"], true)

	_manager.apply_option("direct_question", &"", -3.0, 5.0)
	_manager.end_voluntary()

	var trust_deltas: Array = _mock_trust._trust_deltas
	assert_true(trust_deltas.size() >= 2)


# ---------------------------------------------------------------------------
# Additional: Config validation fallback
# ---------------------------------------------------------------------------


func test_invalid_config_falls_back_to_defaults() -> void:
	_add_clue("clue_lantern", "guest_indigo")

	var result: Dictionary = _start_interrogation({
		"pressure_success_threshold": 120.0,
		"pressure_fail_threshold": 100.0,
	})

	assert_eq(result["ok"], true)


# ---------------------------------------------------------------------------
# Additional: Pressure clamping
# ---------------------------------------------------------------------------


func test_pressure_clamped_at_zero() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation({"pressure_decay_per_turn": 10.0})

	_manager.apply_option("comfort")
	assert_eq(_manager.current_pressure, 0.0)


func test_pressure_clamped_at_fail_threshold() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation({"pressure_decay_per_turn": 0.0, "pressure_fail_threshold": 25.0})

	_manager.apply_option("threaten")  # 20
	_manager.apply_option("threaten")  # 40 -> clamped at 25 -> EXIT -> ANGRY_EXIT

	assert_eq(_manager.is_active, false)
	assert_eq(_ended_events[0]["result"], &"ANGRY_EXIT")


# ---------------------------------------------------------------------------
# Additional: Breakdown NOT triggered from HOSTILE state
# ---------------------------------------------------------------------------


func test_breakdown_not_triggered_from_hostile() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation({
		"pressure_decay_per_turn": 0.0,
		"pressure_success_threshold": 75.0,
		"pressure_fail_threshold": 150.0,
	})

	for _i: int in range(4):
		_manager.apply_option("threaten")  # 80 -> HOSTILE

	assert_eq(_manager.is_active, true)


# ---------------------------------------------------------------------------
# Additional: Signals
# ---------------------------------------------------------------------------


func test_pressure_changed_signal_emitted() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation()

	_manager.apply_option("gentle_probe")

	assert_eq(_pressure_events.size(), 1)
	assert_eq(_pressure_events[0]["old"], 0.0)
	assert_eq(_pressure_events[0]["new"], 3.0)


func test_emotional_state_changed_signal_emitted() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation({"pressure_decay_per_turn": 0.0})

	_manager.apply_option("threaten")  # 20 -> NEUTRAL
	_manager.apply_option("direct_question")  # 30 -> ANXIOUS

	assert_true(_emotion_events.size() >= 1)
	assert_eq(_emotion_events[_emotion_events.size() - 1]["old"], &"NEUTRAL")
	assert_eq(_emotion_events[_emotion_events.size() - 1]["new"], &"ANXIOUS")


# ---------------------------------------------------------------------------
# Additional: Turns count
# ---------------------------------------------------------------------------


func test_turns_count_increments() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation()

	_manager.apply_option("gentle_probe")
	assert_eq(_manager.turns_count, 1)

	_manager.apply_option("observe")
	assert_eq(_manager.turns_count, 2)


# ---------------------------------------------------------------------------
# Additional: Reset
# ---------------------------------------------------------------------------


func test_reset_clears_all_state() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation()
	_manager.apply_option("threaten")

	_manager.reset()

	assert_eq(_manager.is_active, false)
	assert_eq(_manager.current_npc, StringName(&""))
	assert_eq(_manager.current_pressure, 0.0)
	assert_eq(_manager.current_emotional_state, 0)
	assert_eq(_manager.turns_count, 0)


# ---------------------------------------------------------------------------
# Additional: Custom interrogation_multiplier
# ---------------------------------------------------------------------------


func test_custom_multiplier_applied() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation({"interrogation_multiplier": 2.0})

	_manager.apply_option("direct_question", &"", 5.0, 3.0)

	# trust: 5.0 * 1.0 * 2.0 = 10.0
	# suspicion: 3.0 * 1.0 * 2.0 = 6.0
	assert_eq(_mock_trust._trust_deltas[0]["delta"], 10.0)
	assert_eq(_mock_trust._suspicion_deltas[0]["delta"], 6.0)


# ---------------------------------------------------------------------------
# Additional: Breakdown sets NPC to FRIGHTENED
# ---------------------------------------------------------------------------


func test_breakdown_sets_npc_frightened() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation({
		"pressure_decay_per_turn": 0.0,
		"pressure_success_threshold": 35.0,
		"pressure_fail_threshold": 150.0,
	})

	_manager.apply_option("threaten")  # 20
	_manager.apply_option("direct_question")  # 30
	_manager.apply_option("direct_question")  # 40 -> BREAKDOWN

	var transitions: Array = _mock_npc._state_transitions
	var last: Dictionary = transitions[transitions.size() - 1]
	assert_eq(last["state"], 5)  # NPCEmotionalState.FRIGHTENED


# ---------------------------------------------------------------------------
# Additional: Angry exit disables dialogue
# ---------------------------------------------------------------------------


func test_angry_exit_disables_dialogue() -> void:
	_add_clue("clue_lantern", "guest_indigo")
	_start_interrogation({"pressure_decay_per_turn": 0.0})

	for _i: int in range(5):
		_manager.apply_option("threaten")

	assert_eq(_mock_npc._dialogue_set_calls.size(), 1)
	assert_eq(_mock_npc._dialogue_set_calls[0]["npc"], StringName(&"guest_indigo"))
	assert_eq(_mock_npc._dialogue_set_calls[0]["available"], false)
