class_name EndingTriggerLogic
extends Node

## EndingTriggerLogic -- autoload singleton that monitors upstream systems for
## ending conditions, evaluates trigger logic, manages blocking/pending state,
## and drives the ending sequence state machine (Freeze -> Narrative -> Summary -> Cleanup).
## GDD: design/gdd/ending-trigger-logic.md (System #23)

signal ending_sequence_started(trigger_reason: int)
signal ending_phase_changed(old_phase: int, new_phase: int)
signal ending_sequence_completed
signal freeze_knowledge_pulse(pulse_value: float)
signal narrative_requested(variant: StringName)
signal summary_requested
signal cleanup_requested
signal trigger_pending_set
signal trigger_pending_cleared

enum TriggerReason {
	TRUTH_INSIGHT,
	KNOWLEDGE_THRESHOLD,
	TRUST_ALLY,
}

enum SequencePhase {
	IDLE,
	TRIGGERED,
	FREEZE,
	NARRATIVE,
	SUMMARY,
	CLEANUP,
}

## Identifier used for truth insight check.
const TRUTH_INSIGHT_ID: StringName = &"insight_truth"

## Default values from GDD Section 7.
const DEFAULT_KNOWLEDGE_THRESHOLD: float = 0.85
const DEFAULT_TRUST_ALLY_THRESHOLD: float = 80.0
const DEFAULT_TRUST_ALLY_SUSPICION_CAP: float = 20.0
const DEFAULT_FREEZE_DURATION: float = 2.0
const DEFAULT_PULSE_DURATION: float = 2.0

## Tuning knobs -- GDD Section 7.
var ending_knowledge_threshold: float = DEFAULT_KNOWLEDGE_THRESHOLD
var trust_ally_trust_threshold: float = DEFAULT_TRUST_ALLY_THRESHOLD
var trust_ally_suspicion_cap: float = DEFAULT_TRUST_ALLY_SUSPICION_CAP
var freeze_duration: float = DEFAULT_FREEZE_DURATION
var pulse_duration: float = DEFAULT_PULSE_DURATION

## Trigger lock flags (one-shot -- once met, stays met).
var _truth_insight_met: bool = false
var _knowledge_threshold_met: bool = false
var _trust_ally_met: bool = false
var _trust_ally_npc: StringName = &""

## Pending state -- trigger condition met but blocked by timing constraints.
var _pending_trigger: bool = false
var _pending_reason: int = TriggerReason.TRUTH_INSIGHT

## The resolved trigger reason (highest priority among met conditions).
var _resolved_reason: int = TriggerReason.TRUTH_INSIGHT

## Ending sequence state.
var _current_phase: int = SequencePhase.IDLE
var _freeze_elapsed: float = 0.0
var _freeze_start_knowledge: float = 0.0


func _ready() -> void:
	_connect_signals()
	_evaluate_existing_conditions()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


## Returns the current ending sequence phase.
func get_current_phase() -> int:
	return _current_phase


## Returns true if any trigger condition has been met (one-shot locked).
func is_trigger_met() -> bool:
	return _truth_insight_met or _knowledge_threshold_met or _trust_ally_met


## Returns the current trigger reason (highest priority among met conditions).
func get_trigger_reason() -> int:
	return _resolved_reason


## Returns true if the ending trigger is pending (blocked by timing constraints).
func is_pending() -> bool:
	return _pending_trigger


## Returns true if the ending can trigger right now (no blockers active).
func can_trigger() -> bool:
	return not _is_blocked()


## Resets all trigger state for a fresh game session.
func reset() -> void:
	_truth_insight_met = false
	_knowledge_threshold_met = false
	_trust_ally_met = false
	_trust_ally_npc = &""
	_pending_trigger = false
	_pending_reason = TriggerReason.TRUTH_INSIGHT
	_resolved_reason = TriggerReason.TRUTH_INSIGHT
	_current_phase = SequencePhase.IDLE
	_freeze_elapsed = 0.0
	_freeze_start_knowledge = 0.0
	set_process(false)


## Manually advance to the next ending sequence phase.
## Used by UI systems to drive the sequence forward after each phase completes.
func advance_sequence() -> void:
	var old_phase: int = _current_phase
	match _current_phase:
		SequencePhase.TRIGGERED:
			_enter_freeze_phase()
		SequencePhase.FREEZE:
			_enter_narrative_phase()
		SequencePhase.NARRATIVE:
			_enter_summary_phase()
		SequencePhase.SUMMARY:
			_enter_cleanup_phase()
		SequencePhase.CLEANUP:
			_current_phase = SequencePhase.IDLE
			set_process(false)
			ending_sequence_completed.emit()
	if old_phase != _current_phase:
		ending_phase_changed.emit(old_phase, _current_phase)


# ---------------------------------------------------------------------------
# Signal Callbacks -- Upstream System Monitors
# ---------------------------------------------------------------------------


func _on_insight_generated(insight_id: StringName) -> void:
	if insight_id == TRUTH_INSIGHT_ID and not _truth_insight_met:
		_truth_insight_met = true
		_update_resolved_reason()
		_attempt_trigger()


func _on_knowledge_level_changed(new_level: float) -> void:
	if not _knowledge_threshold_met and new_level >= ending_knowledge_threshold:
		_knowledge_threshold_met = true
		_update_resolved_reason()
		_attempt_trigger()


func _on_trust_threshold_crossed(npc_id: StringName, tier: StringName) -> void:
	# TrustSuspicionManager emits tier names. Check if HIGH (>= 80 by default)
	# and verify suspicion is below cap.
	if _trust_ally_met:
		return
	if tier != &"HIGH":
		return
	var trust_manager: Node = _get_trust_manager()
	if trust_manager == null:
		return
	var suspicion: float = 0.0
	if trust_manager.has_method("get_suspicion"):
		suspicion = trust_manager.get_suspicion(npc_id)
	if suspicion >= trust_ally_suspicion_cap:
		return
	_trust_ally_met = true
	_trust_ally_npc = npc_id
	_update_resolved_reason()
	_attempt_trigger()


# ---------------------------------------------------------------------------
# Signal Callbacks -- Blocker State Changes (for pending resolution)
# ---------------------------------------------------------------------------


func _on_dialogue_ended(_npc_id: StringName) -> void:
	_check_pending_trigger()


func _on_notebook_closed() -> void:
	_check_pending_trigger()


func _on_interrogation_ended(_npc_id: StringName, _result: StringName) -> void:
	_check_pending_trigger()


func _on_night_transition_completed(_room_id: StringName) -> void:
	_check_pending_trigger()


func _on_phase_changed(_old_phase: int, new_phase: int) -> void:
	# If we left CRITICAL phase, check pending trigger.
	# TimerService.PressurePhase.CRITICAL == 2
	if new_phase != 2:
		_check_pending_trigger()


# ---------------------------------------------------------------------------
# Private -- Trigger Evaluation
# ---------------------------------------------------------------------------


## Re-evaluate resolved reason with priority ordering:
## TRUTH_INSIGHT (1) > KNOWLEDGE_THRESHOLD (2) > TRUST_ALLY (3).
func _update_resolved_reason() -> void:
	if _truth_insight_met:
		_resolved_reason = TriggerReason.TRUTH_INSIGHT
	elif _knowledge_threshold_met:
		_resolved_reason = TriggerReason.KNOWLEDGE_THRESHOLD
	elif _trust_ally_met:
		_resolved_reason = TriggerReason.TRUST_ALLY


## Attempt to trigger the ending sequence. If blocked, mark as pending.
func _attempt_trigger() -> void:
	if _current_phase != SequencePhase.IDLE:
		return
	if _is_blocked():
		if not _pending_trigger:
			_pending_trigger = true
			_pending_reason = _resolved_reason
			trigger_pending_set.emit()
		return
	_trigger_ending()


## Check if pending trigger can now proceed.
func _check_pending_trigger() -> void:
	if not _pending_trigger:
		return
	if _current_phase != SequencePhase.IDLE:
		return
	if _is_blocked():
		return
	_pending_trigger = false
	trigger_pending_cleared.emit()
	_trigger_ending()


## Execute the ending trigger -- enter TRIGGERED phase.
func _trigger_ending() -> void:
	_current_phase = SequencePhase.TRIGGERED
	ending_sequence_started.emit(_resolved_reason)
	ending_phase_changed.emit(SequencePhase.IDLE, SequencePhase.TRIGGERED)
	advance_sequence()


## Check all blocking conditions (GDD Section 3.4).
func _is_blocked() -> bool:
	var dialogue: Node = _get_dialogue_manager()
	if dialogue != null and "is_active" in dialogue and dialogue.is_active:
		return true

	var notebook: Node = _get_notebook_manager()
	if notebook != null and "is_open" in notebook and notebook.is_open:
		return true

	var interrogation: Node = _get_interrogation_manager()
	if interrogation != null and "is_active" in interrogation and interrogation.is_active:
		return true

	var night_transition: Node = _get_night_transition_controller()
	if night_transition != null and "is_transitioning" in night_transition and night_transition.is_transitioning:
		return true

	var timer: Node = _get_timer_service()
	# TimerService.PressurePhase.CRITICAL == 2
	if timer != null and "current_phase" in timer and timer.current_phase == 2:
		return true

	return false


## Evaluate conditions that may already be met at load time (GDD Section 5).
func _evaluate_existing_conditions() -> void:
	var db: Node = _get_clue_database()
	if db != null and db.has_method("has_entry"):
		if db.has_entry(TRUTH_INSIGHT_ID):
			_truth_insight_met = true

	var knowledge: Node = _get_color_accumulation()
	if knowledge != null and "knowledge_level" in knowledge:
		if knowledge.knowledge_level >= ending_knowledge_threshold:
			_knowledge_threshold_met = true

	# Trust ally requires scanning all NPCs -- skip at load time.
	# This is intentionally conservative: trust_ally is only triggered via signal.
	if _truth_insight_met or _knowledge_threshold_met:
		_update_resolved_reason()
		_attempt_trigger()


# ---------------------------------------------------------------------------
# Private -- Ending Sequence Phases
# ---------------------------------------------------------------------------


## Phase 1: Freeze -- stop timer, disable interactions, pulse knowledge to 1.0.
func _enter_freeze_phase() -> void:
	_current_phase = SequencePhase.FREEZE
	_freeze_elapsed = 0.0

	var knowledge: Node = _get_color_accumulation()
	if knowledge != null and "knowledge_level" in knowledge:
		_freeze_start_knowledge = knowledge.knowledge_level
	else:
		_freeze_start_knowledge = 0.0

	var timer: Node = _get_timer_service()
	if timer != null and timer.has_method("set_time_scale"):
		timer.set_time_scale(0.0)

	var interaction_bus: Node = _get_interaction_bus()
	if interaction_bus != null and interaction_bus.has_method("set_accepting"):
		interaction_bus.set_accepting(false)

	set_process(true)


func _process(delta: float) -> void:
	if _current_phase == SequencePhase.FREEZE:
		_process_freeze(delta)


func _process_freeze(delta: float) -> void:
	_freeze_elapsed += delta
	var progress: float = clampf(_freeze_elapsed / pulse_duration, 0.0, 1.0)
	var pulse_value: float = lerpf(_freeze_start_knowledge, 1.0, progress)
	freeze_knowledge_pulse.emit(pulse_value)

	# Apply pulse to knowledge manager for visual feedback.
	var knowledge: Node = _get_color_accumulation()
	if knowledge != null and "knowledge_level" in knowledge:
		knowledge.knowledge_level = pulse_value

	if _freeze_elapsed >= freeze_duration:
		set_process(false)
		freeze_knowledge_pulse.emit(1.0)
		advance_sequence()


## Phase 2: Narrative -- emit signal for UI to show narrative text.
func _enter_narrative_phase() -> void:
	_current_phase = SequencePhase.NARRATIVE
	var variant: StringName = _get_narrative_variant()
	narrative_requested.emit(variant)


## Phase 3: Summary -- emit signal for UI to show game stats.
func _enter_summary_phase() -> void:
	_current_phase = SequencePhase.SUMMARY
	summary_requested.emit()


## Phase 4: Cleanup -- emit signal, mark save, return to title.
func _enter_cleanup_phase() -> void:
	_current_phase = SequencePhase.CLEANUP
	cleanup_requested.emit()


## Map trigger reason to narrative variant string.
func _get_narrative_variant() -> StringName:
	match _resolved_reason:
		TriggerReason.TRUTH_INSIGHT:
			return &"truth"
		TriggerReason.KNOWLEDGE_THRESHOLD:
			return &"knowledge"
		TriggerReason.TRUST_ALLY:
			return &"ally"
	return &"truth"


# ---------------------------------------------------------------------------
# Private -- Signal Wiring
# ---------------------------------------------------------------------------


func _connect_signals() -> void:
	var db: Node = _get_clue_database()
	if db != null:
		if db.has_signal("insight_generated"):
			db.insight_generated.connect(_on_insight_generated)

	var knowledge: Node = _get_color_accumulation()
	if knowledge != null:
		if knowledge.has_signal("knowledge_level_changed"):
			knowledge.knowledge_level_changed.connect(_on_knowledge_level_changed)

	var trust: Node = _get_trust_manager()
	if trust != null:
		if trust.has_signal("trust_threshold_crossed"):
			trust.trust_threshold_crossed.connect(_on_trust_threshold_crossed)

	_connect_blocker_signals()


func _connect_blocker_signals() -> void:
	var dialogue: Node = _get_dialogue_manager()
	if dialogue != null:
		if dialogue.has_signal("dialogue_ended"):
			dialogue.dialogue_ended.connect(_on_dialogue_ended)

	var notebook: Node = _get_notebook_manager()
	if notebook != null:
		if notebook.has_signal("notebook_closed"):
			notebook.notebook_closed.connect(_on_notebook_closed)

	var interrogation: Node = _get_interrogation_manager()
	if interrogation != null:
		if interrogation.has_signal("interrogation_ended"):
			interrogation.interrogation_ended.connect(_on_interrogation_ended)

	var night_transition: Node = _get_night_transition_controller()
	if night_transition != null:
		if night_transition.has_signal("room_transition_completed"):
			night_transition.room_transition_completed.connect(_on_night_transition_completed)

	var timer: Node = _get_timer_service()
	if timer != null:
		if timer.has_signal("phase_changed"):
			timer.phase_changed.connect(_on_phase_changed)


# ---------------------------------------------------------------------------
# DI Seams -- override in tests via wrapper script
# ---------------------------------------------------------------------------


func _get_clue_database() -> Node:
	return get_node_or_null("/root/ClueDatabase")


func _get_color_accumulation() -> Node:
	return get_node_or_null("/root/ColorAccumulationManager")


func _get_trust_manager() -> Node:
	return get_node_or_null("/root/TrustSuspicionManager")


func _get_timer_service() -> Node:
	return get_node_or_null("/root/TimerService")


func _get_dialogue_manager() -> Node:
	return get_node_or_null("/root/DialogueManager")


func _get_notebook_manager() -> Node:
	return get_node_or_null("/root/NotebookManager")


func _get_interrogation_manager() -> Node:
	return get_node_or_null("/root/InterrogationManager")


func _get_night_transition_controller() -> Node:
	return get_node_or_null("/root/NightTransitionController")


func _get_interaction_bus() -> Node:
	return get_node_or_null("/root/InteractionBus")
