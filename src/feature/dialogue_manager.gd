extends Node

## DialogueManager — autoload singleton for conditional dialogue trees.
## Coordinates dialogue sessions, evaluates conditions, applies consequences.
## GDD: design/gdd/conditional-dialogue-trees.md, ADR-0013

signal dialogue_started(npc_id: StringName)
signal dialogue_ended(npc_id: StringName)
signal dialogue_choice_made(npc_id: StringName, choice_id: StringName)
signal node_displayed(node_id: StringName, text: String)

const DEFAULT_TRUST_FALLBACK: float = 50.0
const DEFAULT_SUSPICION_FALLBACK: float = 0.0
const DIALOGUE_TIME_SCALE: float = 0.5

var _active_tree: Dictionary = {}
var _current_node: Dictionary = {}
var _active_npc: StringName = &""
var _is_active: bool = false
var _time_scale_applied: bool = false


func _ready() -> void:
	set_process(false)


var is_active: bool:
	get:
		return _is_active


func start_dialogue(npc_id: StringName, tree: Dictionary) -> bool:
	if _is_active:
		return false
	if tree.is_empty():
		return false

	var nodes: Array = tree.get("nodes", [])
	if nodes.is_empty():
		return false

	_active_npc = npc_id
	_active_tree = tree
	_is_active = true

	_set_dialogue_time_scale(DIALOGUE_TIME_SCALE)
	_time_scale_applied = true

	var start_node: Dictionary = _find_start_node(tree)
	if start_node.is_empty():
		end_dialogue()
		return false

	_current_node = start_node
	_display_node(_current_node)
	dialogue_started.emit(npc_id)
	return true


func advance() -> void:
	if not _is_active:
		return
	if not _current_node.get("choices", []).is_empty():
		return
	var next_id: StringName = _current_node.get("next_node_id", &"")
	if next_id == &"" or next_id == &"END":
		end_dialogue()
		return
	var node: Dictionary = _find_node_by_id(_active_tree, next_id)
	if node.is_empty():
		end_dialogue()
		return
	_current_node = node
	_display_node(_current_node)


func select_choice(choice_id: StringName) -> void:
	if not _is_active:
		return
	var choices: Array = _current_node.get("choices", [])
	var choice: Dictionary = _find_choice(choices, choice_id)
	if choice.is_empty():
		return

	dialogue_choice_made.emit(_active_npc, choice_id)

	var consequences: Array = choice.get("consequences", [])
	for consequence: Dictionary in consequences:
		_apply_consequence(consequence)

	var next_id: StringName = choice.get("next_node_id", &"")
	if next_id == &"" or next_id == &"END":
		end_dialogue()
		return
	var node: Dictionary = _find_node_by_id(_active_tree, next_id)
	if node.is_empty():
		end_dialogue()
		return
	_current_node = node
	_display_node(_current_node)


func end_dialogue() -> void:
	if not _is_active:
		return
	var npc_id: StringName = _active_npc
	_is_active = false
	_active_tree = {}
	_current_node = {}
	_active_npc = &""

	if _time_scale_applied:
		_set_dialogue_time_scale(1.0)
		_time_scale_applied = false

	dialogue_ended.emit(npc_id)


func get_available_choices() -> Array[Dictionary]:
	if not _is_active:
		return []
	var choices: Array = _current_node.get("choices", [])
	var result: Array[Dictionary] = []
	for choice: Dictionary in choices:
		if _evaluate_conditions(choice.get("conditions", [])):
			result.append(choice)
	return result


func get_current_text() -> String:
	if not _is_active:
		return ""
	return _current_node.get("text", "")


func get_current_node_id() -> StringName:
	if not _is_active:
		return &""
	return _current_node.get("id", &"")


func reset() -> void:
	if _time_scale_applied:
		_set_dialogue_time_scale(1.0)
	_is_active = false
	_active_tree = {}
	_current_node = {}
	_active_npc = &""
	_time_scale_applied = false


func serialize() -> Dictionary:
	return {"is_active": _is_active}


func deserialize(_data: Dictionary) -> void:
	pass


# ---------------------------------------------------------------------------
# Condition Evaluation
# ---------------------------------------------------------------------------


func _evaluate_conditions(conditions: Array) -> bool:
	for condition: Dictionary in conditions:
		if not _evaluate_single(condition):
			return false
	return true


func _evaluate_single(condition: Dictionary) -> bool:
	var actual: Variant = _get_condition_value(condition)
	var comparison: String = condition.get("comparison", "eq")
	var value: Variant = condition.get("value", null)
	match comparison:
		"eq":
			return actual == value
		"neq":
			return actual != value
		"gte":
			return float(actual) >= float(value)
		"lte":
			return float(actual) <= float(value)
		"gt":
			return float(actual) > float(value)
		"lt":
			return float(actual) < float(value)
		"exists":
			return actual != null
		"not_exists":
			return actual == null
	return false


func _get_condition_value(condition: Dictionary) -> Variant:
	var source: String = condition.get("source", "")
	var target_id: StringName = condition.get("target_id", &"")

	match source:
		"npc_emotional_state":
			var mgr: Node = _get_npc_manager()
			if mgr == null:
				return 0
			return mgr.get_emotional_state(target_id)
		"trust_level":
			return _safe_get_trust(target_id)
		"suspicion_level":
			return _safe_get_suspicion(target_id)
		"has_clue":
			var db: Node = _get_clue_database()
			if db == null:
				return false
			return db.has_clue(target_id)
		"has_insight":
			var db2: Node = _get_clue_database()
			if db2 == null:
				return false
			return db2.has_insight(target_id)
		"loop_state":
			var lsm: Node = _get_loop_state_manager()
			if lsm == null:
				return null
			return lsm.get_active_state_value(target_id)
		"current_night":
			var lsm2: Node = _get_loop_state_manager()
			if lsm2 == null:
				return 1
			return lsm2.current_night
		"current_phase":
			var ts: Node = _get_timer_service()
			if ts == null:
				return 0
			return int(ts.current_phase)
	return null


func _safe_get_trust(npc_id: StringName) -> float:
	var tm: Node = _get_trust_manager()
	if tm == null:
		return DEFAULT_TRUST_FALLBACK
	return tm.get_trust(npc_id)


func _safe_get_suspicion(npc_id: StringName) -> float:
	var tm: Node = _get_trust_manager()
	if tm == null:
		return DEFAULT_SUSPICION_FALLBACK
	return tm.get_suspicion(npc_id)


# ---------------------------------------------------------------------------
# Consequence Application
# ---------------------------------------------------------------------------


func _apply_consequence(consequence: Dictionary) -> void:
	var type: String = consequence.get("type", "")
	var target_id: StringName = consequence.get("target_id", &"")
	var value: Variant = consequence.get("value", null)

	match type:
		"modify_trust":
			var tm: Node = _get_trust_manager()
			if tm != null:
				tm.apply_trust_delta(target_id, float(value))
		"modify_suspicion":
			var tm2: Node = _get_trust_manager()
			if tm2 != null:
				tm2.apply_suspicion_delta(target_id, float(value))
		"change_emotional_state":
			var mgr: Node = _get_npc_manager()
			if mgr != null:
				mgr.request_state_transition(target_id, int(value))
		"reveal_clue":
			var db: Node = _get_clue_database()
			if db != null:
				db.add_entry({
					"id": target_id,
					"entry_type": 0,
					"title": "",
					"description": "",
					"source": &"dialogue",
					"discovered_at_night": _get_current_night(),
					"npc_affinity": &"",
					"tags": [],
					"contextual_unlocks": [],
					"metadata": {},
				})
		"register_consequence":
			var lsm: Node = _get_loop_state_manager()
			if lsm != null:
				lsm.register_consequence(target_id, {"value": value})
		"trigger_event":
			var es: Node = _get_event_scheduler()
			if es != null:
				es.fire_event(target_id)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _find_start_node(tree: Dictionary) -> Dictionary:
	var nodes: Array = tree.get("nodes", [])
	for node: Dictionary in nodes:
		if node.get("is_start", false):
			if _evaluate_conditions(node.get("conditions", [])):
				return node
	for node: Dictionary in nodes:
		if _evaluate_conditions(node.get("conditions", [])):
			return node
	if nodes.size() > 0:
		return nodes[0]
	return {}


func _find_node_by_id(tree: Dictionary, node_id: StringName) -> Dictionary:
	var nodes: Array = tree.get("nodes", [])
	for node: Dictionary in nodes:
		if node.get("id", &"") == node_id:
			return node
	return {}


func _find_choice(choices: Array, choice_id: StringName) -> Dictionary:
	for choice: Dictionary in choices:
		if choice.get("id", &"") == choice_id:
			return choice
	return {}


func _display_node(node: Dictionary) -> void:
	node_displayed.emit(node.get("id", &""), node.get("text", ""))


func _set_dialogue_time_scale(scale: float) -> void:
	var ts: Node = _get_timer_service()
	if ts != null:
		ts.set_time_scale(scale)


func _get_current_night() -> int:
	var lsm: Node = _get_loop_state_manager()
	if lsm == null:
		return 1
	return lsm.current_night


# ---------------------------------------------------------------------------
# Dependency Injection Points (override in tests)
# ---------------------------------------------------------------------------


func _get_npc_manager() -> Node:
	return get_node_or_null("/root/NPCManager")


func _get_trust_manager() -> Node:
	return get_node_or_null("/root/TrustSuspicionManager")


func _get_clue_database() -> Node:
	return get_node_or_null("/root/ClueDatabase")


func _get_loop_state_manager() -> Node:
	return get_node_or_null("/root/LoopStateManager")


func _get_timer_service() -> Node:
	return get_node_or_null("/root/TimerService")


func _get_event_scheduler() -> Node:
	return get_node_or_null("/root/EventScheduler")
