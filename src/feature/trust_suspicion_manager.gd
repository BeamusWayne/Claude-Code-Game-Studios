extends Node

## TrustSuspicionManager — autoload singleton for per-NPC trust/suspicion tracking.
## Maintains independent trust (0-100) and suspicion (0-100) axes for each NPC.
## Data-driven deltas via TrustAction definitions. Emits threshold signals.
## GDD: design/gdd/npc-trust-suspicion.md, ADR-0012

signal trust_changed(npc_id: StringName, old_value: float, new_value: float)
signal suspicion_changed(npc_id: StringName, old_value: float, new_value: float)
signal trust_threshold_crossed(npc_id: StringName, tier: StringName)
signal suspicion_threshold_crossed(npc_id: StringName, tier: StringName)

const MAX_TRUST: float = 100.0
const MAX_SUSPICION: float = 100.0
const TRUST_TIER_LOW: float = 30.0
const TRUST_TIER_MEDIUM: float = 60.0
const TRUST_TIER_HIGH: float = 80.0
const SUSPICION_TIER_WATCHFUL: float = 20.0
const SUSPICION_TIER_WARY: float = 40.0
const SUSPICION_TIER_ALARMED: float = 60.0
const SUSPICION_TIER_HOSTILE: float = 80.0
const NIGHT_DECAY_RATE: float = 0.0  # No decay in MVP

var _trust: Dictionary = {}  ## Dictionary[StringName, float]
var _suspicion: Dictionary = {}  ## Dictionary[StringName, float]
var _action_registry: Dictionary = {}  ## Dictionary[StringName, Dictionary]
var _night_decay_rate: float = NIGHT_DECAY_RATE


func _ready() -> void:
	_connect_signals()


func _connect_signals() -> void:
	var loop_state: Node = _get_loop_state_manager()
	if loop_state:
		if loop_state.has_signal("night_advanced"):
			loop_state.night_advanced.connect(_on_night_advanced)
		if loop_state.has_signal("night_ready"):
			loop_state.night_ready.connect(_on_night_ready)


## Initializes trust/suspicion for an NPC with starting values.
func register_npc(npc_id: StringName, initial_trust: float = 0.0, initial_suspicion: float = 0.0) -> void:
	_trust[npc_id] = clampf(initial_trust, 0.0, MAX_TRUST)
	_suspicion[npc_id] = clampf(initial_suspicion, 0.0, MAX_SUSPICION)


## Registers a TrustAction definition for use by apply_action.
func register_action(action_id: StringName, action: Dictionary) -> void:
	_action_registry[action_id] = action


## Returns the trust level for an NPC (0.0 if unregistered).
func get_trust(npc_id: StringName) -> float:
	return _trust.get(npc_id, 0.0)


## Returns the suspicion level for an NPC (0.0 if unregistered).
func get_suspicion(npc_id: StringName) -> float:
	return _suspicion.get(npc_id, 0.0)


## Returns the trust tier name for an NPC.
func get_trust_tier(npc_id: StringName) -> StringName:
	var trust: float = get_trust(npc_id)
	if trust >= TRUST_TIER_HIGH:
		return &"HIGH"
	if trust >= TRUST_TIER_MEDIUM:
		return &"MEDIUM"
	if trust >= TRUST_TIER_LOW:
		return &"LOW"
	return &"NONE"


## Returns the suspicion tier name for an NPC.
func get_suspicion_tier(npc_id: StringName) -> StringName:
	var suspicion: float = get_suspicion(npc_id)
	if suspicion >= SUSPICION_TIER_HOSTILE:
		return &"HOSTILE"
	if suspicion >= SUSPICION_TIER_ALARMED:
		return &"ALARMED"
	if suspicion >= SUSPICION_TIER_WARY:
		return &"WARY"
	if suspicion >= SUSPICION_TIER_WATCHFUL:
		return &"WATCHFUL"
	return &"CALM"


## Applies a raw delta to trust. Returns the new value.
func apply_trust_delta(npc_id: StringName, delta: float) -> float:
	if not _trust.has(npc_id):
		register_npc(npc_id)
	var old_value: float = _trust[npc_id]
	var new_value: float = clampf(old_value + delta, 0.0, MAX_TRUST)
	_trust[npc_id] = new_value
	trust_changed.emit(npc_id, old_value, new_value)
	_check_trust_threshold(npc_id, old_value, new_value)
	return new_value


## Applies a raw delta to suspicion. Returns the new value.
func apply_suspicion_delta(npc_id: StringName, delta: float) -> float:
	if not _suspicion.has(npc_id):
		register_npc(npc_id)
	var old_value: float = _suspicion[npc_id]
	var new_value: float = clampf(old_value + delta, 0.0, MAX_SUSPICION)
	_suspicion[npc_id] = new_value
	suspicion_changed.emit(npc_id, old_value, new_value)
	_check_suspicion_threshold(npc_id, old_value, new_value)
	return new_value


## Applies a named TrustAction to an NPC. Returns true if action exists.
func apply_action(npc_id: StringName, action_id: StringName) -> bool:
	if not _action_registry.has(action_id):
		return false
	var action: Dictionary = _action_registry[action_id]
	if action.has("trust_delta"):
		apply_trust_delta(npc_id, action["trust_delta"])
	if action.has("suspicion_delta"):
		apply_suspicion_delta(npc_id, action["suspicion_delta"])
	return true


## Returns all registered NPC IDs.
func get_registered_npc_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for npc_id: StringName in _trust:
		result.append(npc_id)
	return result


func _check_trust_threshold(npc_id: StringName, old_value: float, new_value: float) -> void:
	var old_tier: StringName = _trust_tier_for_value(old_value)
	var new_tier: StringName = _trust_tier_for_value(new_value)
	if old_tier != new_tier:
		trust_threshold_crossed.emit(npc_id, new_tier)


func _check_suspicion_threshold(npc_id: StringName, old_value: float, new_value: float) -> void:
	var old_tier: StringName = _suspicion_tier_for_value(old_value)
	var new_tier: StringName = _suspicion_tier_for_value(new_value)
	if old_tier != new_tier:
		suspicion_threshold_crossed.emit(npc_id, new_tier)


func _trust_tier_for_value(value: float) -> StringName:
	if value >= TRUST_TIER_HIGH:
		return &"HIGH"
	if value >= TRUST_TIER_MEDIUM:
		return &"MEDIUM"
	if value >= TRUST_TIER_LOW:
		return &"LOW"
	return &"NONE"


func _suspicion_tier_for_value(value: float) -> StringName:
	if value >= SUSPICION_TIER_HOSTILE:
		return &"HOSTILE"
	if value >= SUSPICION_TIER_ALARMED:
		return &"ALARMED"
	if value >= SUSPICION_TIER_WARY:
		return &"WARY"
	if value >= SUSPICION_TIER_WATCHFUL:
		return &"WATCHFUL"
	return &"CALM"


func _on_night_advanced(_old_night: int, _new_night: int) -> void:
	if _night_decay_rate <= 0.0:
		return
	for npc_id: StringName in _trust:
		apply_trust_delta(npc_id, -_night_decay_rate)
		apply_suspicion_delta(npc_id, -_night_decay_rate)


func _on_night_ready(_night: int) -> void:
	pass


# -- Serialization -----------------------------------------------------------

func serialize() -> Dictionary:
	var trust_data: Dictionary = {}
	for npc_id: StringName in _trust:
		trust_data[String(npc_id)] = _trust[npc_id]
	var suspicion_data: Dictionary = {}
	for npc_id: StringName in _suspicion:
		suspicion_data[String(npc_id)] = _suspicion[npc_id]
	return {"trust": trust_data, "suspicion": suspicion_data}


func deserialize(data: Dictionary) -> bool:
	_trust.clear()
	_suspicion.clear()
	var trust_data: Dictionary = data.get("trust", {})
	for key: String in trust_data:
		_trust[StringName(key)] = trust_data[key]
	var suspicion_data: Dictionary = data.get("suspicion", {})
	for key: String in suspicion_data:
		_suspicion[StringName(key)] = suspicion_data[key]
	return true


func reset() -> void:
	_trust.clear()
	_suspicion.clear()
	_action_registry.clear()


# -- DI seams (override in tests) --------------------------------------------

func _get_loop_state_manager() -> Node:
	return get_node_or_null("/root/LoopStateManager")
