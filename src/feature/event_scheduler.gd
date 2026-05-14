extends Node

## EventScheduler — autoload singleton for per-night scripted event dispatching.
## Loads ScriptedEvent definitions, evaluates TIME/CONDITION/COMPOUND triggers,
## executes actions (move NPC, start dialogue, change room state, emit signal).
## GDD: design/gdd/event-scheduler.md

signal event_triggered(event_id: StringName)

enum TriggerType { TIME, CONDITION, COMPOUND }

const MAX_EVENTS_PER_FRAME: int = 5

var _pending_events: Array[Dictionary] = []
var _fired_events: Dictionary = {}  ## Dictionary[StringName, bool]
var _loaded_night: int = -1


func _ready() -> void:
	set_process(false)
	_connect_signals()


func _connect_signals() -> void:
	var loop_state: Node = _get_loop_state_manager()
	if loop_state:
		if loop_state.has_signal("night_ready"):
			loop_state.night_ready.connect(_on_night_ready)
		if loop_state.has_signal("night_advanced"):
			loop_state.night_advanced.connect(_on_night_advanced)


## Loads events for the given night from Resource files.
func load_night_events(night: int) -> void:
	_clear_state()
	_loaded_night = night
	var path: String = "res://assets/data/events/night_%d_events.tres" % night
	if not ResourceLoader.exists(path):
		return
	var resource: Resource = load(path)
	if resource == null:
		return
	if resource.has_method("get_events"):
		var events: Array = resource.get_events()
		for event_data: Dictionary in events:
			_pending_events.append(event_data)
	if not _pending_events.is_empty():
		set_process(true)


## Force-triggers an event by ID. Still respects fired_events dedup.
func force_trigger(event_id: StringName) -> bool:
	if _fired_events.has(event_id):
		return false
	for i in range(_pending_events.size()):
		var event: Dictionary = _pending_events[i]
		if event.get("event_id", &"") == event_id:
			_execute_event(event)
			return true
	return false


## Returns the set of fired event IDs for this night.
func get_fired_events() -> Dictionary:
	return _fired_events


## Returns the loaded night number (-1 if not loaded).
func get_loaded_night() -> int:
	return _loaded_night


func _process(_delta: float) -> void:
	var timer: Node = _get_timer_service()
	if timer == null:
		return
	var fired_this_frame: int = 0
	var to_fire: Array[Dictionary] = []
	for event: Dictionary in _pending_events:
		if fired_this_frame >= MAX_EVENTS_PER_FRAME:
			break
		var event_id: StringName = event.get("event_id", &"")
		if _fired_events.has(event_id):
			continue
		if _should_fire(event, timer):
			to_fire.append(event)
			fired_this_frame += 1
	to_fire.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.get("priority", 0) > b.get("priority", 0)
	)
	for event: Dictionary in to_fire:
		_execute_event(event)


func _should_fire(event: Dictionary, timer: Node) -> bool:
	var trigger_type: int = event.get("trigger_type", TriggerType.TIME)
	match trigger_type:
		TriggerType.TIME:
			return _check_time_trigger(event, timer)
		TriggerType.CONDITION:
			return _check_condition_trigger(event)
		TriggerType.COMPOUND:
			return _check_time_trigger(event, timer) and _check_condition_trigger(event)
	return false


func _check_time_trigger(event: Dictionary, timer: Node) -> bool:
	var trigger_time: float = event.get("trigger_time", 0.0)
	var total_duration: float = timer.total_duration if "total_duration" in timer else 0.0
	var remaining: float = timer.remaining_time if "remaining_time" in timer else 0.0
	if total_duration <= 0.0:
		return false
	var elapsed: float = total_duration - remaining
	return elapsed >= trigger_time


func _check_condition_trigger(event: Dictionary) -> bool:
	var conditions: Array = event.get("trigger_conditions", [])
	if conditions.is_empty():
		return true
	for condition: Dictionary in conditions:
		if not _evaluate_condition(condition):
			return false
	return true


func _evaluate_condition(condition: Dictionary) -> bool:
	var type: String = condition.get("type", "")
	match type:
		"npc_in_room":
			var npc_manager: Node = _get_npc_manager()
			if npc_manager == null or not npc_manager.has_method("get_npc_location"):
				return false
			return npc_manager.get_npc_location(condition.get("npc_id", &"")) == condition.get("room_id", &"")
		"npc_emotional_state":
			var npc_manager: Node = _get_npc_manager()
			if npc_manager == null or not npc_manager.has_method("get_emotional_state"):
				return false
			return npc_manager.get_emotional_state(condition.get("npc_id", &"")) == condition.get("state", 0)
		"clue_discovered":
			var db: Node = _get_clue_database()
			if db == null or not db.has_method("has_clue"):
				return false
			return db.has_clue(condition.get("clue_id", &""))
		"phase_is":
			var timer: Node = _get_timer_service()
			if timer == null or not "current_phase" in timer:
				return false
			return timer.current_phase == condition.get("phase", 0)
		"custom_flag":
			var loop_state: Node = _get_loop_state_manager()
			if loop_state == null or not loop_state.has_method("get_state"):
				return false
			return loop_state.get_state(condition.get("flag_path", &"")) == true
	return false


func _execute_event(event: Dictionary) -> void:
	var event_id: StringName = event.get("event_id", &"")
	_fired_events[event_id] = true
	var actions: Array = event.get("actions", [])
	for action: Dictionary in actions:
		_execute_action(action)
	event_triggered.emit(event_id)
	if _all_events_fired():
		set_process(false)


func _execute_action(action: Dictionary) -> void:
	var type: String = action.get("type", "")
	match type:
		"move_npc":
			var npc_manager: Node = _get_npc_manager()
			if npc_manager and npc_manager.has_method("set_npc_location"):
				npc_manager.set_npc_location(action.get("npc_id", &""), action.get("target_room", &""))
		"change_room_state":
			var room_manager: Node = _get_room_manager()
			if room_manager and room_manager.has_method("set_room_state"):
				room_manager.set_room_state(action.get("room_id", &""), action.get("state_key", &""), action.get("value"))
		"emit_custom_signal":
			var bus: Node = _get_interaction_bus()
			if bus and bus.has_signal("interaction_detected"):
				bus.emit_interaction({
					"target_id": action.get("signal_name", &""),
					"signal_args": action.get("args", {}),
					"priority": 0,
				})


func _all_events_fired() -> bool:
	for event: Dictionary in _pending_events:
		if not _fired_events.has(event.get("event_id", &"")):
			return false
	return true


func _on_night_ready(night: int) -> void:
	load_night_events(night)


func _on_night_advanced(_old_night: int, _new_night: int) -> void:
	_clear_state()


func _clear_state() -> void:
	_fired_events.clear()
	_pending_events.clear()
	_loaded_night = -1
	set_process(false)


# -- Serialization -----------------------------------------------------------

func serialize() -> Dictionary:
	var fired: Array = []
	for event_id: StringName in _fired_events:
		fired.append(String(event_id))
	return {"fired_events": fired, "loaded_night": _loaded_night}


func deserialize(data: Dictionary) -> bool:
	_clear_state()
	var saved_night: int = data.get("loaded_night", -1)
	if saved_night >= 1:
		load_night_events(saved_night)
	for event_id_str: String in data.get("fired_events", []):
		_fired_events[StringName(event_id_str)] = true
	return true


func reset() -> void:
	_clear_state()


# -- DI seams (override in tests) --------------------------------------------

func _get_loop_state_manager() -> Node:
	return get_node_or_null("/root/LoopStateManager")


func _get_timer_service() -> Node:
	return get_node_or_null("/root/TimerService")


func _get_npc_manager() -> Node:
	return get_node_or_null("/root/NPCManager")


func _get_clue_database() -> Node:
	return get_node_or_null("/root/ClueDatabase")


func _get_room_manager() -> Node:
	return get_node_or_null("/root/RoomManager")


func _get_interaction_bus() -> Node:
	return get_node_or_null("/root/InteractionBus")
