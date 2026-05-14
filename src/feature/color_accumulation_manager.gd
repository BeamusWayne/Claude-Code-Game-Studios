extends Node

## ColorAccumulationManager — autoload singleton that tracks knowledge progress
## and drives ink wash shader color saturation. Reads insight data from
## ClueDatabase, computes knowledge_level and per-NPC saturations, applies
## pressure penalty from TimerService, and updates InkWashDriver.
## GDD: design/gdd/color-accumulation.md

signal knowledge_level_changed(new_level: float)

const MAX_INSIGHTS: int = 10
const PRESSURE_PENALTY: float = 0.3
const BASE_NPC_SATURATION: float = 0.10
const BASE_CONNECTION_INTENSITY: float = 0.40
const TRANSITION_SPEED: float = 2.0

var knowledge_level: float = 0.0
var effective_knowledge: float = 0.0
var npc_saturations: Dictionary = {}  ## Dictionary[StringName, float]
var connection_intensity: float = BASE_CONNECTION_INTENSITY
var _pressure_level: float = 0.0


func _ready() -> void:
	_connect_signals()
	_recompute()


func _connect_signals() -> void:
	var db: Node = _get_clue_database()
	if db:
		if db.has_signal("insight_generated"):
			db.insight_generated.connect(_on_insight_changed)
		if db.has_signal("clue_discovered"):
			db.clue_discovered.connect(_on_clue_changed)
	var timer: Node = _get_timer_service()
	if timer and timer.has_signal("pressure_updated"):
		Signal(timer, "pressure_updated").connect(_on_pressure_updated)


## Returns the effective knowledge level after pressure penalty.
func get_effective_knowledge() -> float:
	return effective_knowledge


## Returns the saturation for a given NPC.
func get_npc_saturation(npc_id: StringName) -> float:
	return npc_saturations.get(npc_id, BASE_NPC_SATURATION)


## Returns all NPC saturation values.
func get_all_npc_saturations() -> Dictionary:
	return npc_saturations


## Recomputes all derived values from ClueDatabase state.
func _recompute() -> void:
	var db: Node = _get_clue_database()
	if db == null or not db.has_method("get_all_insights"):
		_update_effective()
		return
	var insights: Array[StringName] = db.get_all_insights()
	var old_level: float = knowledge_level
	if MAX_INSIGHTS == 0:
		knowledge_level = 0.0
	else:
		knowledge_level = clampf(float(insights.size()) / float(MAX_INSIGHTS), 0.0, 1.0)
	_recompute_npc_saturations(db)
	_recompute_connection_intensity(db)
	if not is_equal_approx(old_level, knowledge_level):
		knowledge_level_changed.emit(knowledge_level)
	_update_effective()
	_apply_to_driver()


func _recompute_npc_saturations(db: Node) -> void:
	npc_saturations.clear()
	var npc_ids: Array[StringName] = _get_all_npc_ids()
	for npc_id: StringName in npc_ids:
		var npc_insights: Array[StringName] = []
		if db.has_method("search_by_npc"):
			npc_insights = db.search_by_npc(npc_id)
		var insight_count: int = 0
		for insight_id: StringName in npc_insights:
			var entry: Dictionary = db.get_entry(insight_id)
			if not entry.is_empty() and entry.get("entry_type", -1) == 1:  # INSIGHT
				insight_count += 1
		var npc_total: int = _get_npc_total_secrets(npc_id)
		if npc_total == 0:
			npc_saturations[npc_id] = BASE_NPC_SATURATION
		else:
			npc_saturations[npc_id] = clampf(
				BASE_NPC_SATURATION + (float(insight_count) / float(npc_total)) * (1.0 - BASE_NPC_SATURATION),
				BASE_NPC_SATURATION, 1.0
			)


func _recompute_connection_intensity(db: Node) -> void:
	if not db.has_method("get_valid_connections"):
		connection_intensity = BASE_CONNECTION_INTENSITY
		return
	var valid: Array[Dictionary] = db.get_valid_connections()
	var total_possible: int = _get_total_possible_connections()
	if total_possible == 0:
		connection_intensity = BASE_CONNECTION_INTENSITY
	else:
		connection_intensity = clampf(
			BASE_CONNECTION_INTENSITY + (float(valid.size()) / float(total_possible)) * (1.0 - BASE_CONNECTION_INTENSITY),
			BASE_CONNECTION_INTENSITY, 1.0
		)


func _update_effective() -> void:
	var penalty: float = 0.0
	if _is_pressure_active():
		penalty = PRESSURE_PENALTY * _pressure_level
	effective_knowledge = clampf(knowledge_level * (1.0 - penalty), 0.0, 1.0)


func _is_pressure_active() -> bool:
	var timer: Node = _get_timer_service()
	if timer == null:
		return false
	if not "current_phase" in timer:
		return false
	return timer.current_phase >= 1  # INTENSE or CRITICAL


func _apply_to_driver() -> void:
	var driver: Node = _get_ink_wash_driver()
	if driver and driver.has_method("set_knowledge_level"):
		driver.set_knowledge_level(effective_knowledge)


func _on_insight_changed(_insight_id: StringName) -> void:
	_recompute()


func _on_clue_changed(_clue_id: StringName) -> void:
	_recompute()


func _on_pressure_updated(pressure_level: float) -> void:
	_pressure_level = pressure_level
	_update_effective()
	_apply_to_driver()


## Returns all NPC IDs (from NPCManager if available).
func _get_all_npc_ids() -> Array[StringName]:
	var npc_manager: Node = _get_npc_manager()
	if npc_manager and npc_manager.has_method("get_all_npc_ids"):
		return npc_manager.get_all_npc_ids()
	return []


## Returns total secrets for a given NPC (config value, default 3).
func _get_npc_total_secrets(_npc_id: StringName) -> int:
	return 3


## Returns total possible connections (config value).
func _get_total_possible_connections() -> int:
	return 5


# -- Serialization -----------------------------------------------------------

func serialize() -> Dictionary:
	return {"pressure_level": _pressure_level}


func deserialize(data: Dictionary) -> bool:
	_pressure_level = data.get("pressure_level", 0.0)
	_recompute()
	return true


func reset() -> void:
	knowledge_level = 0.0
	effective_knowledge = 0.0
	npc_saturations.clear()
	connection_intensity = BASE_CONNECTION_INTENSITY
	_pressure_level = 0.0


# -- DI seams (override in tests) --------------------------------------------

func _get_clue_database() -> Node:
	return get_node_or_null("/root/ClueDatabase")


func _get_timer_service() -> Node:
	return get_node_or_null("/root/TimerService")


func _get_ink_wash_driver() -> Node:
	return get_node_or_null("/root/InkWashDriver")


func _get_npc_manager() -> Node:
	return get_node_or_null("/root/NPCManager")
