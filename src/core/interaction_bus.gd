extends Node

signal interaction_detected(event: Dictionary)

enum InteractionType { CLICK, LONG_PRESS }
enum InputMethod { MOUSE, TOUCH }

var _frame_buffer: Array[Dictionary] = []
var _registered: Dictionary = {}


func register_interactable(id: StringName, info: Dictionary) -> void:
	_registered[id] = info


func unregister_interactable(id: StringName) -> void:
	_registered.erase(id)


func emit_interaction(event: Dictionary) -> void:
	_frame_buffer.append(event)


func _process(_delta: float) -> void:
	if _frame_buffer.is_empty():
		return
	var resolved := _resolve_by_priority(_frame_buffer)
	interaction_detected.emit(resolved)
	_frame_buffer.clear()


func _resolve_by_priority(events: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = events[0]
	for event in events:
		if event.get("priority", 0) > best.get("priority", 0):
			best = event
	return best


func get_registered_count() -> int:
	return _registered.size()


func is_registered(id: StringName) -> bool:
	return _registered.has(id)


func clear_all() -> void:
	_registered.clear()
	_frame_buffer.clear()
