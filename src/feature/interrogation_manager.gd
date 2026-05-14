extends Node

## InterrogationManager — autoload singleton for guest interrogation mode.
## Extends DialogueManager with pressure mechanics, NPC emotional state tracking,
## clue presentation, and breakdown/angry exit outcomes.
## GDD: design/gdd/guest-interrogation.md, extends ADR-0013

signal interrogation_started(npc_id: StringName)
signal interrogation_ended(npc_id: StringName, result: StringName)
signal pressure_changed(npc_id: StringName, old_pressure: float, new_pressure: float)
signal interrogation_emotional_state_changed(npc_id: StringName, old_state: StringName, new_state: StringName)

enum InterrogationResult {
	BREAKDOWN,
	ANGRY_EXIT,
	VOLUNTARY_END,
}

enum EmotionalState {
	NEUTRAL,
	ANXIOUS,
	FRIGHTENED,
	HOSTILE,
	EXIT,
}

const DEFAULT_INTERROGATION_MULTIPLIER: float = 1.5
const DEFAULT_PRESSURE_FAIL_THRESHOLD: float = 100.0
const DEFAULT_PRESSURE_SUCCESS_THRESHOLD: float = 60.0
const DEFAULT_PRESSURE_DECAY_PER_TURN: float = 2.0
const DEFAULT_CLUE_BONUS: float = 10.0
const DEFAULT_ANGRY_EXIT_TRUST_PENALTY: float = -10.0
const DEFAULT_ANGRY_EXIT_SUSPICION_PENALTY: float = 15.0
const DEFAULT_BREAKDOWN_TRUST_BONUS: float = 5.0
const DEFAULT_BREAKDOWN_SUSPICION_REDUCTION: float = -3.0
const DEFAULT_UNRELATED_CLUE_TRUST_PENALTY: float = -5.0
const DEFAULT_DIALOGUE_COOLDOWN_AFTER_ANGER: float = 120.0
const SUSPICION_HOSTILE_THRESHOLD: float = 80.0

## Pressure deltas and multipliers per option type.
const OPTION_CONFIGS: Dictionary = {
	"gentle_probe": {"pressure_delta": 5.0, "trust_mult": 0.8, "suspicion_mult": 0.8},
	"direct_question": {"pressure_delta": 10.0, "trust_mult": 1.0, "suspicion_mult": 1.0},
	"present_clue": {"pressure_delta": 15.0, "trust_mult": 1.2, "suspicion_mult": 0.6},
	"threaten": {"pressure_delta": 20.0, "trust_mult": 0.5, "suspicion_mult": 2.0},
	"comfort": {"pressure_delta": -5.0, "trust_mult": 1.5, "suspicion_mult": 0.5},
	"observe": {"pressure_delta": 0.0, "trust_mult": 1.0, "suspicion_mult": 0.5},
}

## Session state — not persisted.
var _active_npc: StringName = &""
var _pressure: float = 0.0
var _emotional_state: int = EmotionalState.NEUTRAL
var _config: Dictionary = {}
var _turns_count: int = 0
var _is_active: bool = false


func _ready() -> void:
	set_process(false)


## --- Public API ---


var is_active: bool:
	get:
		return _is_active


var current_npc: StringName:
	get:
		return _active_npc


var current_pressure: float:
	get:
		return _pressure


var current_emotional_state: int:
	get:
		return _emotional_state


var turns_count: int:
	get:
		return _turns_count


## Validates trigger conditions and starts an interrogation session.
## Returns a Dictionary: {ok: bool, reason: String}
func start_interrogation(npc_id: StringName, config: Dictionary = {}) -> Dictionary:
	if _is_active:
		return {"ok": false, "reason": "interrogation_already_active"}

	var dm: Node = _get_dialogue_manager()
	if dm and dm.is_active:
		return {"ok": false, "reason": "dialogue_already_active"}

	var mgr: Node = _get_npc_manager()
	if mgr == null or not mgr.is_dialogue_available(npc_id):
		return {"ok": false, "reason": "npc_not_available"}

	var suspicion: float = _safe_get_suspicion(npc_id)
	if suspicion >= SUSPICION_HOSTILE_THRESHOLD:
		return {"ok": false, "reason": "npc_suspicion_too_high"}

	if not _has_related_clues(npc_id):
		return {"ok": false, "reason": "no_related_clues"}

	var resolved_config: Dictionary = _resolve_config(config)
	if not _validate_config(resolved_config):
		resolved_config = _default_config()

	_active_npc = npc_id
	_pressure = 0.0
	_config = resolved_config
	_turns_count = 0
	_is_active = true

	var opening: int = _config.get("opening_emotional_state", EmotionalState.NEUTRAL)
	_emotional_state = opening

	if dm:
		dm._is_active = true

	interrogation_started.emit(npc_id)
	return {"ok": true, "reason": ""}


## Applies an interrogation option. Returns result dict with end state.
func apply_option(option_type: String, clue_id: StringName = &"",
	base_trust_delta: float = 0.0, base_suspicion_delta: float = 0.0) -> Dictionary:
	if not _is_active:
		return {"ok": false, "result": &"", "emotional_state": _emotional_state,
				"pressure": _pressure, "clue_bonus": 0.0}

	if not OPTION_CONFIGS.has(option_type):
		return {"ok": false, "result": &"", "emotional_state": _emotional_state,
				"pressure": _pressure, "clue_bonus": 0.0}

	var opt: Dictionary = OPTION_CONFIGS[option_type]
	var effective_clue_bonus: float = 0.0

	if option_type == "present_clue":
		effective_clue_bonus = _calculate_clue_bonus(clue_id)

	var pressure_delta: float = opt["pressure_delta"]
	if option_type == "present_clue":
		pressure_delta += effective_clue_bonus

	var old_pressure: float = _pressure
	_pressure = clampf(
		_pressure + pressure_delta - float(_config.get("pressure_decay_per_turn", DEFAULT_PRESSURE_DECAY_PER_TURN)),
		0.0, float(_config.get("pressure_fail_threshold", DEFAULT_PRESSURE_FAIL_THRESHOLD))
	)

	pressure_changed.emit(_active_npc, old_pressure, _pressure)

	var old_emotion: int = _emotional_state
	_emotional_state = _determine_emotional_state(_pressure)
	if old_emotion != _emotional_state:
		interrogation_emotional_state_changed.emit(
			_active_npc,
			EmotionalState.keys()[old_emotion],
			EmotionalState.keys()[_emotional_state]
		)

	var multiplier: float = float(_config.get("interrogation_multiplier", DEFAULT_INTERROGATION_MULTIPLIER))
	var trust_mult: float = opt["trust_mult"]
	var suspicion_mult: float = opt["suspicion_mult"]

	var amplified_trust: float = base_trust_delta * trust_mult * multiplier
	var amplified_suspicion: float = base_suspicion_delta * suspicion_mult * multiplier

	_apply_trust_suspicion(_active_npc, amplified_trust, amplified_suspicion)

	if option_type == "present_clue" and effective_clue_bonus == 0.0 and clue_id != &"":
		var unrelated_penalty: float = float(_config.get(
			"unrelated_clue_trust_penalty", DEFAULT_UNRELATED_CLUE_TRUST_PENALTY))
		_apply_trust_suspicion(_active_npc, unrelated_penalty * multiplier, 0.0)

	_turns_count += 1

	var result: StringName = &""
	var end_check: Dictionary = _check_end_conditions()
	if end_check["ended"]:
		result = end_check["result"]
		_end_interrogation(result)

	return {
		"ok": true,
		"result": result,
		"emotional_state": _emotional_state if not end_check["ended"] else EmotionalState.keys().find("NEUTRAL"),
		"pressure": _pressure if not end_check["ended"] else 0.0,
		"clue_bonus": effective_clue_bonus,
	}


## Ends the interrogation voluntarily.
func end_voluntary() -> void:
	if not _is_active:
		return
	_end_interrogation(&"VOLUNTARY_END")


## Returns presentable clues (all discovered CLUE entries).
func get_presentable_clues() -> Array[Dictionary]:
	if not _is_active:
		return []
	var db: Node = _get_clue_database()
	if db == null:
		return []
	var clues: Array[Dictionary] = []
	var all_clues: Array = db.get_all_clues()
	for clue_id: StringName in all_clues:
		var entry: Dictionary = db.get_entry(clue_id)
		if not entry.is_empty():
			clues.append(entry)
	return clues


## Resets session state.
func reset() -> void:
	_active_npc = &""
	_pressure = 0.0
	_emotional_state = EmotionalState.NEUTRAL
	_config = {}
	_turns_count = 0
	_is_active = false


## --- Private: Config ---


func _default_config() -> Dictionary:
	return {
		"pressure_success_threshold": DEFAULT_PRESSURE_SUCCESS_THRESHOLD,
		"pressure_fail_threshold": DEFAULT_PRESSURE_FAIL_THRESHOLD,
		"pressure_decay_per_turn": DEFAULT_PRESSURE_DECAY_PER_TURN,
		"clue_bonus": DEFAULT_CLUE_BONUS,
		"interrogation_multiplier": DEFAULT_INTERROGATION_MULTIPLIER,
		"opening_emotional_state": EmotionalState.NEUTRAL,
		"angry_exit_trust_penalty": DEFAULT_ANGRY_EXIT_TRUST_PENALTY,
		"angry_exit_suspicion_penalty": DEFAULT_ANGRY_EXIT_SUSPICION_PENALTY,
		"breakdown_trust_bonus": DEFAULT_BREAKDOWN_TRUST_BONUS,
		"breakdown_suspicion_reduction": DEFAULT_BREAKDOWN_SUSPICION_REDUCTION,
		"unrelated_clue_trust_penalty": DEFAULT_UNRELATED_CLUE_TRUST_PENALTY,
		"dialogue_cooldown_after_anger": DEFAULT_DIALOGUE_COOLDOWN_AFTER_ANGER,
	}


func _resolve_config(config: Dictionary) -> Dictionary:
	var defaults: Dictionary = _default_config()
	if config.is_empty():
		return defaults
	var resolved: Dictionary = defaults.duplicate()
	for key: String in config:
		resolved[key] = config[key]
	return resolved


func _validate_config(config: Dictionary) -> bool:
	var success: float = float(config.get("pressure_success_threshold", DEFAULT_PRESSURE_SUCCESS_THRESHOLD))
	var fail: float = float(config.get("pressure_fail_threshold", DEFAULT_PRESSURE_FAIL_THRESHOLD))
	return success < fail


## --- Private: Emotional State ---


func _determine_emotional_state(pressure: float) -> int:
	var fail_threshold: float = float(_config.get("pressure_fail_threshold", DEFAULT_PRESSURE_FAIL_THRESHOLD))
	if pressure >= fail_threshold:
		return EmotionalState.EXIT
	if pressure >= 80.0:
		return EmotionalState.HOSTILE
	if pressure >= 60.0:
		return EmotionalState.FRIGHTENED
	if pressure >= 30.0:
		return EmotionalState.ANXIOUS
	return EmotionalState.NEUTRAL


## --- Private: Clue Bonus ---


func _calculate_clue_bonus(clue_id: StringName) -> float:
	if clue_id == &"":
		return 0.0
	var db: Node = _get_clue_database()
	if db == null:
		return 0.0

	var entry: Dictionary = db.get_entry(clue_id)
	if entry.is_empty():
		return 0.0

	var clue_bonus: float = float(_config.get("clue_bonus", DEFAULT_CLUE_BONUS))
	var npc_affinity: StringName = entry.get("npc_affinity", &"")

	if npc_affinity == _active_npc:
		return clue_bonus

	var tags: Array = entry.get("tags", [])
	if _active_npc in tags:
		return clue_bonus * 0.5

	return 0.0


## --- Private: End Conditions ---


func _check_end_conditions() -> Dictionary:
	var fail_threshold: float = float(_config.get("pressure_fail_threshold", DEFAULT_PRESSURE_FAIL_THRESHOLD))

	if _pressure >= fail_threshold:
		return {"ended": true, "result": &"ANGRY_EXIT"}

	var success_threshold: float = float(_config.get("pressure_success_threshold", DEFAULT_PRESSURE_SUCCESS_THRESHOLD))
	if _pressure >= success_threshold:
		if _emotional_state == EmotionalState.ANXIOUS or _emotional_state == EmotionalState.FRIGHTENED:
			return {"ended": true, "result": &"BREAKDOWN"}

	return {"ended": false, "result": &""}


## --- Private: End Interrogation ---


func _end_interrogation(result: StringName) -> void:
	if not _is_active:
		return

	var npc_id: StringName = _active_npc
	var final_emotion: int = _emotional_state

	match result:
		&"BREAKDOWN":
			_apply_breakdown_consequences(npc_id)
			final_emotion = EmotionalState.FRIGHTENED
		&"ANGRY_EXIT":
			_apply_angry_exit_consequences(npc_id)
			final_emotion = EmotionalState.HOSTILE
		&"VOLUNTARY_END":
			pass

	_sync_npc_emotional_state(npc_id, final_emotion)

	var dm: Node = _get_dialogue_manager()
	if dm:
		dm._is_active = false

	_is_active = false
	_active_npc = &""
	_pressure = 0.0
	_emotional_state = EmotionalState.NEUTRAL
	_config = {}
	_turns_count = 0

	interrogation_ended.emit(npc_id, result)


func _apply_breakdown_consequences(npc_id: StringName) -> void:
	var trust_bonus: float = float(_config.get("breakdown_trust_bonus", DEFAULT_BREAKDOWN_TRUST_BONUS))
	var suspicion_reduction: float = float(_config.get("breakdown_suspicion_reduction", DEFAULT_BREAKDOWN_SUSPICION_REDUCTION))
	_apply_trust_suspicion(npc_id, trust_bonus, suspicion_reduction)


func _apply_angry_exit_consequences(npc_id: StringName) -> void:
	var trust_penalty: float = float(_config.get("angry_exit_trust_penalty", DEFAULT_ANGRY_EXIT_TRUST_PENALTY))
	var suspicion_penalty: float = float(_config.get("angry_exit_suspicion_penalty", DEFAULT_ANGRY_EXIT_SUSPICION_PENALTY))
	_apply_trust_suspicion(npc_id, trust_penalty, suspicion_penalty)

	var mgr: Node = _get_npc_manager()
	if mgr:
		mgr.request_state_transition(npc_id, 3)  # HOSTILE = 3
		mgr.set_dialogue_availability(npc_id, false)


## --- Private: Trust/Suspicion ---


func _apply_trust_suspicion(npc_id: StringName, trust_delta: float, suspicion_delta: float) -> void:
	var tm: Node = _get_trust_manager()
	if tm == null:
		if trust_delta != 0.0 or suspicion_delta != 0.0:
			push_warning("InterrogationManager: TrustManager unavailable, skipping delta")
		return
	if trust_delta != 0.0:
		tm.apply_trust_delta(npc_id, trust_delta)
	if suspicion_delta != 0.0:
		tm.apply_suspicion_delta(npc_id, suspicion_delta)


func _safe_get_suspicion(npc_id: StringName) -> float:
	var tm: Node = _get_trust_manager()
	if tm == null:
		return 0.0
	return tm.get_suspicion(npc_id)


## --- Private: NPC State Sync ---


func _sync_npc_emotional_state(npc_id: StringName, interrogation_emotion: int) -> void:
	var mgr: Node = _get_npc_manager()
	if mgr == null:
		return
	var npc_emotion: int = _interrogation_to_npc_emotion(interrogation_emotion)
	mgr.request_state_transition(npc_id, npc_emotion)


func _interrogation_to_npc_emotion(ie: int) -> int:
	# Map interrogation EmotionalState to NPCManager.NPCEmotionalState
	# NPCEmotionalState: NEUTRAL=0, CURIOUS=1, ANXIOUS=2, HOSTILE=3, TRUSTING=4, FRIGHTENED=5
	match ie:
		EmotionalState.NEUTRAL:
			return 0
		EmotionalState.ANXIOUS:
			return 2
		EmotionalState.FRIGHTENED:
			return 5
		EmotionalState.HOSTILE:
			return 3
		_:
			return 0


## --- Private: Clue Helpers ---


func _has_related_clues(npc_id: StringName) -> bool:
	var db: Node = _get_clue_database()
	if db == null:
		return false
	var by_npc: Array = db.search_by_npc(npc_id)
	if not by_npc.is_empty():
		return true
	var all_clues: Array = db.get_all_clues()
	for clue_id: StringName in all_clues:
		var entry: Dictionary = db.get_entry(clue_id)
		var tags: Array = entry.get("tags", [])
		if npc_id in tags:
			return true
	return false


## --- DI Seams (override in tests) ---


func _get_dialogue_manager() -> Node:
	return get_node_or_null("/root/DialogueManager")


func _get_npc_manager() -> Node:
	return get_node_or_null("/root/NPCManager")


func _get_trust_manager() -> Node:
	return get_node_or_null("/root/TrustSuspicionManager")


func _get_clue_database() -> Node:
	return get_node_or_null("/root/ClueDatabase")
