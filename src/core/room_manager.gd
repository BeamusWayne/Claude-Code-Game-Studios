extends Node

# RoomManager — autoload singleton for room lifecycle management.
# Loads/unloads room PackedScenes on demand, manages fade transitions,
# registers room interactables with InteractionBus, and resets template
# state on night_advanced (ADR-0007).

signal room_transition_started(from_room: StringName, to_room: StringName)
signal room_transition_completed(room_id: StringName)
signal room_loaded(room_id: StringName)
signal room_unloaded(room_id: StringName)
signal room_changed(room_id: StringName)

const FADE_DURATION: float = 0.3
const CANVAS_LAYER_ORDER: int = 100

var _room_registry: Dictionary = {}
var _active_room_id: StringName = &""
var _active_room_instance: Node2D = null
var _room_cache: Dictionary = {}
var _is_transitioning: bool = false
var _pending_reset: bool = false
var _room_container: Node2D = null
var _fade_canvas: CanvasLayer = null
var _fade_rect: ColorRect = null


func _ready() -> void:
	_setup_room_container()
	_setup_fade_overlay()
	_connect_loop_state_signals()


func _setup_room_container() -> void:
	_room_container = Node2D.new()
	_room_container.name = "RoomContainer"
	add_child(_room_container)


func _setup_fade_overlay() -> void:
	_fade_canvas = CanvasLayer.new()
	_fade_canvas.layer = CANVAS_LAYER_ORDER
	_fade_canvas.name = "FadeCanvas"
	add_child(_fade_canvas)

	_fade_rect = ColorRect.new()
	_fade_rect.name = "FadeRect"
	_fade_rect.color = Color.BLACK
	_fade_rect.modulate.a = 0.0
	_fade_rect.size = Vector2(1920.0, 1080.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_canvas.add_child(_fade_rect)


func _connect_loop_state_signals() -> void:
	var loop_state: Node = _get_loop_state_manager()
	if loop_state == null:
		return
	if loop_state.has_signal("night_ready"):
		loop_state.night_ready.connect(_on_night_ready)
	if loop_state.has_signal("night_advanced"):
		loop_state.night_advanced.connect(_on_night_advanced)


# --- Public API ---


## Registers a room_id to its scene path. Does not load the scene yet.
func register_room(room_id: StringName, scene_path: String) -> void:
	_room_registry[room_id] = scene_path


## Requests a transition to the given room. Guards against overlapping transitions.
func request_transition(room_id: StringName) -> void:
	if _is_transitioning:
		return
	if not _room_registry.has(room_id):
		push_error("RoomManager: unknown room_id '%s'" % room_id)
		return

	_is_transitioning = true
	var from_room: StringName = _active_room_id

	# PRE_UNLOAD: unregister interactables before removing the scene
	_unregister_room_interactables()

	# Signal that transition is starting (before fade covers the screen)
	room_transition_started.emit(from_room, room_id)

	# FADE_OUT
	await _fade_out()

	# UNLOAD
	if _active_room_instance != null:
		room_unloaded.emit(_active_room_id)
		_unload_current_room()

	# LOAD
	_load_room(room_id)
	room_loaded.emit(room_id)

	# APPLY_STATE: apply persistent mutations from LoopStateManager
	_apply_template_overrides()

	# POST_LOAD: register interactables in the new room
	_register_room_interactables()

	# FADE_IN
	await _fade_in()

	_active_room_id = room_id
	_is_transitioning = false

	room_transition_completed.emit(room_id)
	room_changed.emit(room_id)

	# Handle pending template reset that arrived during transition
	if _pending_reset:
		_pending_reset = false
		apply_template_reset()


## Returns the StringName id of the currently active room.
func get_current_room_id() -> StringName:
	return _active_room_id


## Returns true while a room transition is in progress.
func get_is_transitioning() -> bool:
	return _is_transitioning


## Sets the fade overlay alpha directly (for NightTransitionController, ADR-0011).
func set_fade_alpha(alpha: float) -> void:
	if _fade_rect != null:
		_fade_rect.modulate.a = clampf(alpha, 0.0, 1.0)


## Returns the current fade overlay alpha value.
func get_fade_alpha() -> float:
	if _fade_rect != null:
		return _fade_rect.modulate.a
	return 0.0


## Resets current room to its PackedScene default (template reset).
## Called on night_advanced. Defers if a transition is in progress.
func apply_template_reset() -> void:
	if _is_transitioning:
		_pending_reset = true
		return
	if _active_room_id == &"":
		return

	_unregister_room_interactables()
	room_unloaded.emit(_active_room_id)
	_unload_current_room()
	_load_room(_active_room_id)
	_apply_template_overrides()
	_register_room_interactables()
	room_loaded.emit(_active_room_id)


# --- Private ---


func _load_room(room_id: StringName) -> void:
	var scene_path: String = _room_registry[room_id]
	var packed: PackedScene = _get_or_load_scene(scene_path)
	if packed == null:
		push_error("RoomManager: failed to load scene '%s'" % scene_path)
		return

	var instance: Node2D = packed.instantiate() as Node2D
	if instance == null:
		push_error("RoomManager: scene root is not Node2D: '%s'" % scene_path)
		return

	_active_room_instance = instance
	_room_container.add_child(instance)


func _unload_current_room() -> void:
	if _active_room_instance == null:
		return
	_active_room_instance.queue_free()
	_active_room_instance = null


func _get_or_load_scene(scene_path: String) -> PackedScene:
	if _room_cache.has(scene_path):
		return _room_cache[scene_path]
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed != null:
		_room_cache[scene_path] = packed
	return packed


func _fade_out() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 1.0, FADE_DURATION)
	await tween.finished


func _fade_in() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 0.0, FADE_DURATION)
	await tween.finished


## Finds Interactable nodes in the active room and registers them with InteractionBus.
func _register_room_interactables() -> void:
	var interactables: Array[Node] = _get_active_interactables()
	var bus: Node = _get_interaction_bus()
	if bus == null:
		return
	for node in interactables:
		var interactable_id: StringName = _get_interactable_id(node)
		if interactable_id != &"":
			bus.register_interactable(interactable_id, _build_interactable_info(node))


## Unregisters all interactables from the current room via InteractionBus.
func _unregister_room_interactables() -> void:
	var interactables: Array[Node] = _get_active_interactables()
	var bus: Node = _get_interaction_bus()
	if bus == null:
		return
	for node in interactables:
		var interactable_id: StringName = _get_interactable_id(node)
		if interactable_id != &"":
			bus.unregister_interactable(interactable_id)


func _get_active_interactables() -> Array[Node]:
	if _active_room_instance == null:
		return []
	var result: Array[Node] = []
	_collect_interactables(_active_room_instance, result)
	return result


func _collect_interactables(node: Node, result: Array[Node]) -> void:
	for child in node.get_children():
		if child.has_method("get_interactable_id"):
			result.append(child)
		_collect_interactables(child, result)


func _get_interactable_id(node: Node) -> StringName:
	if node.has_method("get_interactable_id"):
		return node.get_interactable_id() as StringName
	# Fallback: use the node's name as id
	return StringName(node.name)


func _build_interactable_info(node: Node) -> Dictionary:
	if node.has_method("get_interactable_info"):
		return node.get_interactable_info() as Dictionary
	# Minimal default info
	return {
		"target_type": &"item",
		"priority": 0,
		"node_path": _active_room_instance.get_path_to(node),
	}


func _apply_template_overrides() -> void:
	var loop_state: Node = _get_loop_state_manager()
	if loop_state == null or _active_room_instance == null:
		return
	if not loop_state.has_method("get_template_override"):
		return
	_apply_overrides_to_children(_active_room_instance, loop_state)


func _apply_overrides_to_children(room_instance: Node2D, loop_state: Node) -> void:
	var children: Array[Node] = room_instance.find_children("*", "")
	for child in children:
		var entity_id: StringName = StringName(child.name)
		_try_apply_override(child, entity_id, "visible", loop_state)
		_try_apply_override(child, entity_id, "disabled", loop_state)
		_try_apply_override(child, entity_id, "is_locked", loop_state)
		_try_apply_override(child, entity_id, "is_open", loop_state)


func _try_apply_override(node: Node, entity_id: StringName, property: String, loop_state: Node) -> void:
	var value: Variant = loop_state.get_template_override(entity_id, property)
	if value == null:
		return
	match property:
		"visible":
			if "visible" in node:
				node.set("visible", value)
		"disabled":
			if "disabled" in node:
				node.set("disabled", value)
		"is_locked":
			if "is_locked" in node:
				node.set("is_locked", value)
		"is_open":
			if "is_open" in node:
				node.set("is_open", value)


func _get_loop_state_manager() -> Node:
	return get_node_or_null("/root/LoopStateManager")


func _get_interaction_bus() -> Node:
	return get_node_or_null("/root/InteractionBus")


# --- Signal Callbacks ---


func _on_night_ready(night: int) -> void:
	# Initial room load on game start — default to lobby
	if _active_room_id == &"":
		request_transition(&"lobby")


func _on_night_advanced(_old_night: int, _new_night: int) -> void:
	apply_template_reset()
