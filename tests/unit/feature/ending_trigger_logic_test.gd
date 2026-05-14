extends GdUnitTestSuite

## Tests for EndingTriggerLogic -- trigger condition evaluation, priority ordering,
## one-shot locking, blocking conditions, pending mechanism, ending sequence phases.
## Covers GDD acceptance criteria from design/gdd/ending-trigger-logic.md (#23).

const ETL_SCRIPT := "res://src/feature/ending_trigger_logic.gd"

var _manager: Node
var _mock_db: Node
var _mock_knowledge: Node
var _mock_trust: Node
var _mock_timer: Node
var _mock_dialogue: Node
var _mock_notebook: Node
var _mock_interrogation: Node
var _mock_night_transition: Node
var _mock_interaction_bus: Node

# Event recorders
var _sequence_started_events: Array
var _phase_changed_events: Array
var _sequence_completed_events: Array
var _pulse_events: Array
var _narrative_events: Array
var _summary_events: Array
var _cleanup_events: Array
var _pending_set_events: Array
var _pending_cleared_events: Array


func before_test() -> void:
	_mock_db = Node.new()
	_mock_db.name = "ClueDatabase"
	_mock_db.set_script(_create_db_mock())
	add_child(_mock_db)

	_mock_knowledge = Node.new()
	_mock_knowledge.name = "ColorAccumulationManager"
	_mock_knowledge.set_script(_create_knowledge_mock())
	add_child(_mock_knowledge)

	_mock_trust = Node.new()
	_mock_trust.name = "TrustSuspicionManager"
	_mock_trust.set_script(_create_trust_mock())
	add_child(_mock_trust)

	_mock_timer = Node.new()
	_mock_timer.name = "TimerService"
	_mock_timer.set_script(_create_timer_mock())
	add_child(_mock_timer)

	_mock_dialogue = Node.new()
	_mock_dialogue.name = "DialogueManager"
	_mock_dialogue.set_script(_create_dialogue_mock())
	add_child(_mock_dialogue)

	_mock_notebook = Node.new()
	_mock_notebook.name = "NotebookManager"
	_mock_notebook.set_script(_create_notebook_mock())
	add_child(_mock_notebook)

	_mock_interrogation = Node.new()
	_mock_interrogation.name = "InterrogationManager"
	_mock_interrogation.set_script(_create_interrogation_mock())
	add_child(_mock_interrogation)

	_mock_night_transition = Node.new()
	_mock_night_transition.name = "NightTransitionController"
	_mock_night_transition.set_script(_create_night_transition_mock())
	add_child(_mock_night_transition)

	_mock_interaction_bus = Node.new()
	_mock_interaction_bus.name = "InteractionBus"
	_mock_interaction_bus.set_script(_create_interaction_bus_mock())
	add_child(_mock_interaction_bus)

	var wrapper := GDScript.new()
	wrapper.source_code = (
		"extends \"%s\"\n" % ETL_SCRIPT
		+ "var _test_db: Node = null\n"
		+ "var _test_knowledge: Node = null\n"
		+ "var _test_trust: Node = null\n"
		+ "var _test_timer: Node = null\n"
		+ "var _test_dialogue: Node = null\n"
		+ "var _test_notebook: Node = null\n"
		+ "var _test_interrogation: Node = null\n"
		+ "var _test_night_transition: Node = null\n"
		+ "var _test_interaction_bus: Node = null\n"
		+ "func _get_clue_database() -> Node:\n"
		+ "\treturn _test_db\n"
		+ "func _get_color_accumulation() -> Node:\n"
		+ "\treturn _test_knowledge\n"
		+ "func _get_trust_manager() -> Node:\n"
		+ "\treturn _test_trust\n"
		+ "func _get_timer_service() -> Node:\n"
		+ "\treturn _test_timer\n"
		+ "func _get_dialogue_manager() -> Node:\n"
		+ "\treturn _test_dialogue\n"
		+ "func _get_notebook_manager() -> Node:\n"
		+ "\treturn _test_notebook\n"
		+ "func _get_interrogation_manager() -> Node:\n"
		+ "\treturn _test_interrogation\n"
		+ "func _get_night_transition_controller() -> Node:\n"
		+ "\treturn _test_night_transition\n"
		+ "func _get_interaction_bus() -> Node:\n"
		+ "\treturn _test_interaction_bus\n"
	)
	wrapper.reload()

	_manager = Node.new()
	_manager.set_script(wrapper)
	_manager._test_db = _mock_db
	_manager._test_knowledge = _mock_knowledge
	_manager._test_trust = _mock_trust
	_manager._test_timer = _mock_timer
	_manager._test_dialogue = _mock_dialogue
	_manager._test_notebook = _mock_notebook
	_manager._test_interrogation = _mock_interrogation
	_manager._test_night_transition = _mock_night_transition
	_manager._test_interaction_bus = _mock_interaction_bus
	_manager.name = "EndingTriggerLogicTest"
	add_child(_manager)

	# Reset event recorders
	_sequence_started_events = []
	_phase_changed_events = []
	_sequence_completed_events = []
	_pulse_events = []
	_narrative_events = []
	_summary_events = []
	_cleanup_events = []
	_pending_set_events = []
	_pending_cleared_events = []

	_manager.ending_sequence_started.connect(_on_sequence_started)
	_manager.ending_phase_changed.connect(_on_phase_changed)
	_manager.ending_sequence_completed.connect(_on_sequence_completed)
	_manager.freeze_knowledge_pulse.connect(_on_pulse)
	_manager.narrative_requested.connect(_on_narrative)
	_manager.summary_requested.connect(_on_summary)
	_manager.cleanup_requested.connect(_on_cleanup)
	_manager.trigger_pending_set.connect(_on_pending_set)
	_manager.trigger_pending_cleared.connect(_on_pending_cleared)


func _on_sequence_started(reason: int) -> void:
	_sequence_started_events.append(reason)


func _on_phase_changed(old_phase: int, new_phase: int) -> void:
	_phase_changed_events.append({"old": old_phase, "new": new_phase})


func _on_sequence_completed() -> void:
	_sequence_completed_events.append(true)


func _on_pulse(value: float) -> void:
	_pulse_events.append(value)


func _on_narrative(variant: StringName) -> void:
	_narrative_events.append(variant)


func _on_summary() -> void:
	_summary_events.append(true)


func _on_cleanup() -> void:
	_cleanup_events.append(true)


func _on_pending_set() -> void:
	_pending_set_events.append(true)


func _on_pending_cleared() -> void:
	_pending_cleared_events.append(true)


func after_test() -> void:
	if _manager:
		_manager.queue_free()
	if _mock_db:
		_mock_db.queue_free()
	if _mock_knowledge:
		_mock_knowledge.queue_free()
	if _mock_trust:
		_mock_trust.queue_free()
	if _mock_timer:
		_mock_timer.queue_free()
	if _mock_dialogue:
		_mock_dialogue.queue_free()
	if _mock_notebook:
		_mock_notebook.queue_free()
	if _mock_interrogation:
		_mock_interrogation.queue_free()
	if _mock_night_transition:
		_mock_night_transition.queue_free()
	if _mock_interaction_bus:
		_mock_interaction_bus.queue_free()


# ---------------------------------------------------------------------------
# Mock Scripts
# ---------------------------------------------------------------------------


func _create_db_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal insight_generated(insight_id: StringName)\n"
		+ "var _entries: Dictionary = {}\n"
		+ "func has_entry(id: StringName) -> bool:\n"
		+ "\treturn _entries.has(id)\n"
		+ "func add_entry(id: StringName) -> void:\n"
		+ "\t_entries[id] = true\n"
		+ "\tinsight_generated.emit(id)\n"
	)
	script.reload()
	return script


func _create_knowledge_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal knowledge_level_changed(new_level: float)\n"
		+ "var knowledge_level: float = 0.0\n"
		+ "func set_knowledge_level(value: float) -> void:\n"
		+ "\tknowledge_level = value\n"
	)
	script.reload()
	return script


func _create_trust_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal trust_threshold_crossed(npc_id: StringName, tier: StringName)\n"
		+ "var _suspicion_values: Dictionary = {}\n"
		+ "func get_suspicion(npc_id: StringName) -> float:\n"
		+ "\treturn _suspicion_values.get(npc_id, 0.0)\n"
		+ "func set_suspicion(npc_id: StringName, value: float) -> void:\n"
		+ "\t_suspicion_values[npc_id] = value\n"
		+ "func simulate_threshold_crossed(npc_id: StringName, tier: StringName) -> void:\n"
		+ "\ttrust_threshold_crossed.emit(npc_id, tier)\n"
	)
	script.reload()
	return script


func _create_timer_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal phase_changed(old_phase: int, new_phase: int)\n"
		+ "signal pressure_updated(pressure_level: float)\n"
		+ "var current_phase: int = 0\n"
		+ "var time_scale: float = 1.0\n"
		+ "func set_time_scale(scale: float) -> void:\n"
		+ "\ttime_scale = scale\n"
	)
	script.reload()
	return script


func _create_dialogue_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal dialogue_started(npc_id: StringName)\n"
		+ "signal dialogue_ended(npc_id: StringName)\n"
		+ "var is_active: bool = false\n"
	)
	script.reload()
	return script


func _create_notebook_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal notebook_opened\n"
		+ "signal notebook_closed\n"
		+ "var is_open: bool = false\n"
	)
	script.reload()
	return script


func _create_interrogation_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal interrogation_started(npc_id: StringName)\n"
		+ "signal interrogation_ended(npc_id: StringName, result: StringName)\n"
		+ "var is_active: bool = false\n"
	)
	script.reload()
	return script


func _create_night_transition_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal room_transition_started(from: StringName, to: StringName)\n"
		+ "signal room_transition_completed(room_id: StringName)\n"
		+ "var is_transitioning: bool = false\n"
	)
	script.reload()
	return script


func _create_interaction_bus_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var accepting: bool = true\n"
		+ "func set_accepting(value: bool) -> void:\n"
		+ "\taccepting = value\n"
	)
	script.reload()
	return script


# ===========================================================================
# Tests: Initial State
# ===========================================================================


func test_initial_phase_is_idle() -> void:
	assert_int(_manager.get_current_phase()).is_equal(0)  # SequencePhase.IDLE


func test_initial_no_trigger_met() -> void:
	assert_bool(_manager.is_trigger_met()).is_false()


func test_initial_not_pending() -> void:
	assert_bool(_manager.is_pending()).is_false()


func test_can_trigger_when_no_blockers() -> void:
	assert_bool(_manager.can_trigger()).is_true()


# ===========================================================================
# Tests: TRUTH_INSIGHT Trigger
# ===========================================================================


func test_truth_insight_triggers_on_insight_truth() -> void:
	_mock_db.add_entry(&"insight_truth")

	assert_bool(_manager._truth_insight_met).is_true()
	assert_int(_manager.get_trigger_reason()).is_equal(0)  # TRUTH_INSIGHT
	assert_int(_manager.get_current_phase()).is_equal(2)  # FREEZE (auto-advances)


func test_truth_insight_ignores_other_insights() -> void:
	_mock_db.add_entry(&"insight_other")

	assert_bool(_manager._truth_insight_met).is_false()
	assert_bool(_manager.is_trigger_met()).is_false()


func test_truth_insight_oneshot_no_retrigger() -> void:
	_mock_db.add_entry(&"insight_truth")
	var phase_before: int = _manager.get_current_phase()
	_manager._on_insight_generated(&"insight_truth")

	assert_int(_manager.get_current_phase()).is_equal(phase_before)


# ===========================================================================
# Tests: KNOWLEDGE_THRESHOLD Trigger
# ===========================================================================


func test_knowledge_threshold_triggers_at_threshold() -> void:
	_mock_knowledge.knowledge_level = 0.85
	_mock_knowledge.knowledge_level_changed.emit(0.85)

	assert_bool(_manager._knowledge_threshold_met).is_true()
	assert_int(_manager.get_trigger_reason()).is_equal(1)  # KNOWLEDGE_THRESHOLD


func test_knowledge_threshold_triggers_above_threshold() -> void:
	_mock_knowledge.knowledge_level = 0.95
	_mock_knowledge.knowledge_level_changed.emit(0.95)

	assert_bool(_manager._knowledge_threshold_met).is_true()


func test_knowledge_threshold_not_triggered_below_threshold() -> void:
	_mock_knowledge.knowledge_level = 0.50
	_mock_knowledge.knowledge_level_changed.emit(0.50)

	assert_bool(_manager._knowledge_threshold_met).is_false()


func test_knowledge_threshold_oneshot_stays_met() -> void:
	_mock_knowledge.knowledge_level = 0.90
	_mock_knowledge.knowledge_level_changed.emit(0.90)
	var phase_before: int = _manager.get_current_phase()

	# Level drops -- should NOT un-trigger
	_mock_knowledge.knowledge_level = 0.50
	_mock_knowledge.knowledge_level_changed.emit(0.50)

	assert_bool(_manager._knowledge_threshold_met).is_true()
	assert_int(_manager.get_current_phase()).is_equal(phase_before)


# ===========================================================================
# Tests: TRUST_ALLY Trigger
# ===========================================================================


func test_trust_ally_triggers_on_high_trust_low_suspicion() -> void:
	_mock_trust.set_suspicion(&"guest_indigo", 10.0)
	_mock_trust.simulate_threshold_crossed(&"guest_indigo", &"HIGH")

	assert_bool(_manager._trust_ally_met).is_true()
	assert_int(_manager.get_trigger_reason()).is_equal(2)  # TRUST_ALLY


func test_trust_ally_not_triggered_with_high_suspicion() -> void:
	_mock_trust.set_suspicion(&"guest_indigo", 25.0)
	_mock_trust.simulate_threshold_crossed(&"guest_indigo", &"HIGH")

	assert_bool(_manager._trust_ally_met).is_false()


func test_trust_ally_not_triggered_on_medium_tier() -> void:
	_mock_trust.simulate_threshold_crossed(&"guest_indigo", &"MEDIUM")

	assert_bool(_manager._trust_ally_met).is_false()


func test_trust_ally_not_triggered_on_low_tier() -> void:
	_mock_trust.simulate_threshold_crossed(&"guest_indigo", &"LOW")

	assert_bool(_manager._trust_ally_met).is_false()


func test_trust_ally_suspicion_at_cap_not_triggered() -> void:
	_mock_trust.set_suspicion(&"guest_indigo", 20.0)
	_mock_trust.simulate_threshold_crossed(&"guest_indigo", &"HIGH")

	assert_bool(_manager._trust_ally_met).is_false()


func test_trust_ally_suspicion_just_below_cap_triggered() -> void:
	_mock_trust.set_suspicion(&"guest_indigo", 19.9)
	_mock_trust.simulate_threshold_crossed(&"guest_indigo", &"HIGH")

	assert_bool(_manager._trust_ally_met).is_true()


func test_trust_ally_oneshot_no_retrigger() -> void:
	_mock_trust.set_suspicion(&"guest_indigo", 5.0)
	_mock_trust.simulate_threshold_crossed(&"guest_indigo", &"HIGH")
	var phase_before: int = _manager.get_current_phase()

	_mock_trust.simulate_threshold_crossed(&"guest_indigo", &"HIGH")

	assert_bool(_manager._trust_ally_met).is_true()
	assert_int(_manager.get_current_phase()).is_equal(phase_before)


# ===========================================================================
# Tests: Priority Ordering
# ===========================================================================


func test_priority_truth_over_knowledge() -> void:
	_mock_knowledge.knowledge_level = 0.90
	_mock_knowledge.knowledge_level_changed.emit(0.90)

	_manager.reset()
	_mock_knowledge.knowledge_level = 0.90

	_mock_knowledge.knowledge_level_changed.emit(0.90)
	_mock_db.add_entry(&"insight_truth")

	assert_int(_manager.get_trigger_reason()).is_equal(0)  # TRUTH_INSIGHT


func test_priority_knowledge_over_trust() -> void:
	_mock_knowledge.knowledge_level = 0.88
	_mock_knowledge.knowledge_level_changed.emit(0.88)

	_manager.reset()
	_mock_knowledge.knowledge_level = 0.88

	_mock_knowledge.knowledge_level_changed.emit(0.88)
	_mock_trust.set_suspicion(&"guest_indigo", 5.0)
	_mock_trust.simulate_threshold_crossed(&"guest_indigo", &"HIGH")

	assert_bool(_manager._knowledge_threshold_met).is_true()
	assert_bool(_manager._trust_ally_met).is_true()


func test_priority_truth_highest_even_if_all_met() -> void:
	_mock_knowledge.knowledge_level = 0.90
	_mock_knowledge.knowledge_level_changed.emit(0.90)

	_mock_trust.set_suspicion(&"guest_indigo", 5.0)
	_mock_trust.simulate_threshold_crossed(&"guest_indigo", &"HIGH")

	_mock_db.add_entry(&"insight_truth")

	assert_int(_manager.get_trigger_reason()).is_equal(0)  # TRUTH_INSIGHT


# ===========================================================================
# Tests: Blocking Conditions
# ===========================================================================


func test_blocked_by_dialogue_active() -> void:
	_mock_dialogue.is_active = true
	_mock_db.add_entry(&"insight_truth")

	assert_bool(_manager.is_pending()).is_true()
	assert_int(_manager.get_current_phase()).is_equal(0)  # IDLE


func test_blocked_by_notebook_open() -> void:
	_mock_notebook.is_open = true
	_mock_db.add_entry(&"insight_truth")

	assert_bool(_manager.is_pending()).is_true()
	assert_int(_manager.get_current_phase()).is_equal(0)


func test_blocked_by_interrogation_active() -> void:
	_mock_interrogation.is_active = true
	_mock_db.add_entry(&"insight_truth")

	assert_bool(_manager.is_pending()).is_true()
	assert_int(_manager.get_current_phase()).is_equal(0)


func test_blocked_by_night_transition() -> void:
	_mock_night_transition.is_transitioning = true
	_mock_db.add_entry(&"insight_truth")

	assert_bool(_manager.is_pending()).is_true()
	assert_int(_manager.get_current_phase()).is_equal(0)


func test_blocked_by_critical_phase() -> void:
	_mock_timer.current_phase = 2  # CRITICAL
	_mock_db.add_entry(&"insight_truth")

	assert_bool(_manager.is_pending()).is_true()
	assert_int(_manager.get_current_phase()).is_equal(0)


func test_not_blocked_when_all_clear() -> void:
	assert_bool(_manager.can_trigger()).is_true()
	assert_bool(_manager._is_blocked()).is_false()


func test_blocked_by_first_blocker_wins() -> void:
	_mock_dialogue.is_active = true
	_mock_notebook.is_open = true
	_mock_db.add_entry(&"insight_truth")

	assert_bool(_manager.is_pending()).is_true()


# ===========================================================================
# Tests: Pending Mechanism
# ===========================================================================


func test_pending_resumed_on_dialogue_end() -> void:
	_mock_dialogue.is_active = true
	_mock_db.add_entry(&"insight_truth")
	assert_bool(_manager.is_pending()).is_true()

	_mock_dialogue.is_active = false
	_mock_dialogue.dialogue_ended.emit(&"guest_indigo")

	assert_bool(_manager.is_pending()).is_false()
	assert_int(_manager.get_current_phase()).is_equal(2)  # FREEZE


func test_pending_resumed_on_notebook_close() -> void:
	_mock_notebook.is_open = true
	_mock_db.add_entry(&"insight_truth")
	assert_bool(_manager.is_pending()).is_true()

	_mock_notebook.is_open = false
	_mock_notebook.notebook_closed.emit()

	assert_bool(_manager.is_pending()).is_false()
	assert_int(_manager.get_current_phase()).is_equal(2)


func test_pending_resumed_on_interrogation_end() -> void:
	_mock_interrogation.is_active = true
	_mock_db.add_entry(&"insight_truth")
	assert_bool(_manager.is_pending()).is_true()

	_mock_interrogation.is_active = false
	_mock_interrogation.interrogation_ended.emit(&"guest_indigo", &"VOLUNTARY_END")

	assert_bool(_manager.is_pending()).is_false()
	assert_int(_manager.get_current_phase()).is_equal(2)


func test_pending_resumed_on_night_transition_complete() -> void:
	_mock_night_transition.is_transitioning = true
	_mock_db.add_entry(&"insight_truth")
	assert_bool(_manager.is_pending()).is_true()

	_mock_night_transition.is_transitioning = false
	_mock_night_transition.room_transition_completed.emit(&"lobby")

	assert_bool(_manager.is_pending()).is_false()
	assert_int(_manager.get_current_phase()).is_equal(2)


func test_pending_resumed_on_phase_leave_critical() -> void:
	_mock_timer.current_phase = 2
	_mock_db.add_entry(&"insight_truth")
	assert_bool(_manager.is_pending()).is_true()

	_mock_timer.current_phase = 1
	_mock_timer.phase_changed.emit(2, 1)

	assert_bool(_manager.is_pending()).is_false()
	assert_int(_manager.get_current_phase()).is_equal(2)


func test_pending_stays_if_new_blocker_appears() -> void:
	_mock_dialogue.is_active = true
	_mock_db.add_entry(&"insight_truth")

	_mock_notebook.is_open = true
	_mock_dialogue.is_active = false
	_mock_dialogue.dialogue_ended.emit(&"guest_indigo")

	assert_bool(_manager.is_pending()).is_true()
	assert_int(_manager.get_current_phase()).is_equal(0)


func test_pending_signal_emitted_on_block() -> void:
	_mock_dialogue.is_active = true
	_mock_db.add_entry(&"insight_truth")

	assert_int(_pending_set_events.size()).is_equal(1)


func test_pending_cleared_signal_emitted_on_resume() -> void:
	_mock_dialogue.is_active = true
	_mock_db.add_entry(&"insight_truth")

	_mock_dialogue.is_active = false
	_mock_dialogue.dialogue_ended.emit(&"guest_indigo")

	assert_int(_pending_cleared_events.size()).is_equal(1)


func test_pending_reason_preserved_when_new_condition_met() -> void:
	_mock_dialogue.is_active = true
	_mock_db.add_entry(&"insight_truth")
	assert_int(_manager._pending_reason).is_equal(0)  # TRUTH_INSIGHT

	_mock_knowledge.knowledge_level = 0.90
	_mock_knowledge.knowledge_level_changed.emit(0.90)

	assert_int(_manager.get_trigger_reason()).is_equal(0)


# ===========================================================================
# Tests: Ending Sequence State Machine
# ===========================================================================


func test_sequence_starts_at_triggered_then_freeze() -> void:
	_mock_db.add_entry(&"insight_truth")

	assert_int(_manager.get_current_phase()).is_equal(2)  # FREEZE


func test_sequence_full_lifecycle_completes() -> void:
	_mock_db.add_entry(&"insight_truth")
	assert_int(_manager.get_current_phase()).is_equal(2)  # FREEZE

	_manager.advance_sequence()  # FREEZE -> NARRATIVE
	assert_int(_manager.get_current_phase()).is_equal(3)

	_manager.advance_sequence()  # NARRATIVE -> SUMMARY
	assert_int(_manager.get_current_phase()).is_equal(4)

	_manager.advance_sequence()  # SUMMARY -> CLEANUP
	assert_int(_manager.get_current_phase()).is_equal(5)

	_manager.advance_sequence()  # CLEANUP -> IDLE
	assert_int(_manager.get_current_phase()).is_equal(0)

	assert_int(_sequence_completed_events.size()).is_equal(1)


func test_phase_changed_events_emitted() -> void:
	_mock_db.add_entry(&"insight_truth")

	assert_int(_phase_changed_events.size()).is_greater_equal(2)
	assert_int(_phase_changed_events[0]["old"]).is_equal(0)  # IDLE
	assert_int(_phase_changed_events[0]["new"]).is_equal(1)  # TRIGGERED
	assert_int(_phase_changed_events[1]["old"]).is_equal(1)  # TRIGGERED
	assert_int(_phase_changed_events[1]["new"]).is_equal(2)  # FREEZE


func test_freeze_calls_timer_set_time_scale_zero() -> void:
	_mock_db.add_entry(&"insight_truth")

	assert_float(_mock_timer.time_scale).is_equal(0.0)


func test_freeze_calls_interaction_bus_set_accepting_false() -> void:
	_mock_db.add_entry(&"insight_truth")

	assert_bool(_mock_interaction_bus.accepting).is_false()


func test_narrative_variant_truth() -> void:
	_mock_db.add_entry(&"insight_truth")
	_manager.advance_sequence()  # FREEZE -> NARRATIVE

	assert_int(_narrative_events.size()).is_greater_equal(1)
	assert_str(String(_narrative_events[_narrative_events.size() - 1])).is_equal("truth")


func test_narrative_variant_knowledge() -> void:
	_mock_knowledge.knowledge_level = 0.90
	_mock_knowledge.knowledge_level_changed.emit(0.90)
	_manager.advance_sequence()  # FREEZE -> NARRATIVE

	assert_int(_narrative_events.size()).is_greater_equal(1)
	assert_str(String(_narrative_events[_narrative_events.size() - 1])).is_equal("knowledge")


func test_narrative_variant_ally() -> void:
	_mock_trust.set_suspicion(&"guest_indigo", 5.0)
	_mock_trust.simulate_threshold_crossed(&"guest_indigo", &"HIGH")
	_manager.advance_sequence()  # FREEZE -> NARRATIVE

	assert_int(_narrative_events.size()).is_greater_equal(1)
	assert_str(String(_narrative_events[_narrative_events.size() - 1])).is_equal("ally")


func test_summary_signal_emitted() -> void:
	_mock_db.add_entry(&"insight_truth")
	_manager.advance_sequence()  # FREEZE -> NARRATIVE
	_manager.advance_sequence()  # NARRATIVE -> SUMMARY

	assert_int(_summary_events.size()).is_greater_equal(1)


func test_cleanup_signal_emitted() -> void:
	_mock_db.add_entry(&"insight_truth")
	_manager.advance_sequence()  # FREEZE -> NARRATIVE
	_manager.advance_sequence()  # NARRATIVE -> SUMMARY
	_manager.advance_sequence()  # SUMMARY -> CLEANUP

	assert_int(_cleanup_events.size()).is_greater_equal(1)


func test_sequence_started_signal_carries_reason() -> void:
	_mock_db.add_entry(&"insight_truth")

	assert_int(_sequence_started_events.size()).is_equal(1)
	assert_int(_sequence_started_events[0]).is_equal(0)  # TRUTH_INSIGHT


# ===========================================================================
# Tests: Freeze Phase Knowledge Pulse
# ===========================================================================


func test_freeze_pulse_starts_at_current_knowledge() -> void:
	_mock_knowledge.knowledge_level = 0.65
	_mock_db.add_entry(&"insight_truth")

	_manager._process_freeze(0.0)

	assert_int(_pulse_events.size()).is_greater_equal(1)
	assert_float(_pulse_events[0]).is_greater_equal(0.65 - 0.01)


func test_freeze_pulse_ends_at_one() -> void:
	_mock_knowledge.knowledge_level = 0.50
	_mock_db.add_entry(&"insight_truth")

	_manager._process_freeze(2.0)

	if _pulse_events.size() > 0:
		assert_float(_pulse_events[_pulse_events.size() - 1]).is_equal(1.0)


func test_freeze_pulse_interpolates_linearly() -> void:
	_mock_knowledge.knowledge_level = 0.0
	_manager.freeze_duration = 2.0
	_mock_db.add_entry(&"insight_truth")

	_manager._freeze_elapsed = 0.0
	_manager._process_freeze(1.0)

	if _pulse_events.size() > 0:
		assert_float(_pulse_events[_pulse_events.size() - 1]).is_equal_approx(0.5, 0.01)


func test_freeze_auto_advances_after_duration() -> void:
	_mock_db.add_entry(&"insight_truth")
	assert_int(_manager.get_current_phase()).is_equal(2)  # FREEZE

	_manager._process_freeze(2.0)

	assert_int(_manager.get_current_phase()).is_equal(3)  # NARRATIVE


func test_freeze_records_start_knowledge() -> void:
	_mock_knowledge.knowledge_level = 0.72
	_mock_db.add_entry(&"insight_truth")

	assert_float(_manager._freeze_start_knowledge).is_equal(0.72)


# ===========================================================================
# Tests: Evaluate Existing Conditions at Load Time
# ===========================================================================


func test_load_with_truth_insight_already_present() -> void:
	_mock_db._entries[&"insight_truth"] = true

	var wrapper := GDScript.new()
	wrapper.source_code = (
		"extends \"%s\"\n" % ETL_SCRIPT
		+ "var _test_db: Node = null\n"
		+ "var _test_knowledge: Node = null\n"
		+ "var _test_trust: Node = null\n"
		+ "var _test_timer: Node = null\n"
		+ "var _test_dialogue: Node = null\n"
		+ "var _test_notebook: Node = null\n"
		+ "var _test_interrogation: Node = null\n"
		+ "var _test_night_transition: Node = null\n"
		+ "var _test_interaction_bus: Node = null\n"
		+ "func _get_clue_database() -> Node:\n"
		+ "\treturn _test_db\n"
		+ "func _get_color_accumulation() -> Node:\n"
		+ "\treturn _test_knowledge\n"
		+ "func _get_trust_manager() -> Node:\n"
		+ "\treturn _test_trust\n"
		+ "func _get_timer_service() -> Node:\n"
		+ "\treturn _test_timer\n"
		+ "func _get_dialogue_manager() -> Node:\n"
		+ "\treturn _test_dialogue\n"
		+ "func _get_notebook_manager() -> Node:\n"
		+ "\treturn _test_notebook\n"
		+ "func _get_interrogation_manager() -> Node:\n"
		+ "\treturn _test_interrogation\n"
		+ "func _get_night_transition_controller() -> Node:\n"
		+ "\treturn _test_night_transition\n"
		+ "func _get_interaction_bus() -> Node:\n"
		+ "\treturn _test_interaction_bus\n"
	)
	wrapper.reload()
	var fresh_manager := Node.new()
	fresh_manager.set_script(wrapper)
	fresh_manager._test_db = _mock_db
	fresh_manager._test_knowledge = _mock_knowledge
	fresh_manager._test_trust = _mock_trust
	fresh_manager._test_timer = _mock_timer
	fresh_manager._test_dialogue = _mock_dialogue
	fresh_manager._test_notebook = _mock_notebook
	fresh_manager._test_interrogation = _mock_interrogation
	fresh_manager._test_night_transition = _mock_night_transition
	fresh_manager._test_interaction_bus = _mock_interaction_bus
	add_child(fresh_manager)

	assert_bool(fresh_manager._truth_insight_met).is_true()

	fresh_manager.queue_free()


func test_load_with_knowledge_above_threshold() -> void:
	_mock_knowledge.knowledge_level = 0.90
	_manager._evaluate_existing_conditions()

	assert_bool(_manager._knowledge_threshold_met).is_true()


func test_load_with_no_conditions_met_stays_idle() -> void:
	_manager._evaluate_existing_conditions()

	assert_bool(_manager.is_trigger_met()).is_false()
	assert_int(_manager.get_current_phase()).is_equal(0)


# ===========================================================================
# Tests: Reset
# ===========================================================================


func test_reset_clears_all_state() -> void:
	_mock_db.add_entry(&"insight_truth")
	_manager.reset()

	assert_bool(_manager._truth_insight_met).is_false()
	assert_bool(_manager._knowledge_threshold_met).is_false()
	assert_bool(_manager._trust_ally_met).is_false()
	assert_bool(_manager.is_pending()).is_false()
	assert_int(_manager.get_current_phase()).is_equal(0)


func test_reset_allows_retrigger() -> void:
	_mock_db.add_entry(&"insight_truth")
	_manager.reset()

	_mock_db.add_entry(&"insight_truth")

	assert_bool(_manager._truth_insight_met).is_true()


# ===========================================================================
# Tests: Edge Cases from GDD Section 5
# ===========================================================================


func test_no_double_trigger_when_sequence_running() -> void:
	_mock_db.add_entry(&"insight_truth")
	assert_int(_manager.get_current_phase()).is_equal(2)  # FREEZE

	_mock_knowledge.knowledge_level = 0.90
	_mock_knowledge.knowledge_level_changed.emit(0.90)

	assert_int(_manager.get_current_phase()).is_equal(2)


func test_multiple_conditions_same_frame_priority_order() -> void:
	_mock_knowledge.knowledge_level = 0.90
	_mock_knowledge.knowledge_level_changed.emit(0.90)
	_mock_trust.set_suspicion(&"guest_indigo", 5.0)
	_mock_trust.simulate_threshold_crossed(&"guest_indigo", &"HIGH")
	_mock_db.add_entry(&"insight_truth")

	assert_int(_manager.get_trigger_reason()).is_equal(0)
	assert_bool(_manager._truth_insight_met).is_true()
	assert_bool(_manager._knowledge_threshold_met).is_true()
	assert_bool(_manager._trust_ally_met).is_true()


func test_no_trigger_from_nonexistent_insight() -> void:
	_mock_db.add_entry(&"insight_something_else")

	assert_bool(_manager.is_trigger_met()).is_false()


func test_knowledge_at_exactly_threshold_triggers() -> void:
	_mock_knowledge.knowledge_level = 0.85
	_mock_knowledge.knowledge_level_changed.emit(0.85)

	assert_bool(_manager._knowledge_threshold_met).is_true()


func test_advance_from_idle_does_nothing() -> void:
	_manager.advance_sequence()

	assert_int(_manager.get_current_phase()).is_equal(0)


func test_pending_not_set_when_not_blocked() -> void:
	_mock_db.add_entry(&"insight_truth")

	assert_bool(_manager.is_pending()).is_false()


func test_critical_phase_stays_blocked() -> void:
	assert_bool(_manager.can_trigger()).is_true()

	_mock_timer.current_phase = 2

	assert_bool(_manager.can_trigger()).is_false()


func test_interaction_bus_called_during_freeze() -> void:
	_mock_db.add_entry(&"insight_truth")

	assert_bool(_mock_interaction_bus.accepting).is_false()
