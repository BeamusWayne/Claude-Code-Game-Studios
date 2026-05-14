extends GdUnitTestSuite

# Tests for RoomManager — room lifecycle, transitions, fade overlay,
# interactable registration, and template reset.
# Covers ADR-0007 validation criteria 1-10.


const ROOM_MANAGER_SCRIPT := "res://src/core/room_manager.gd"

var _manager: Node
var _mock_loop_state: Node
var _mock_interaction_bus: Node
var _signal_log: Dictionary


func before_test() -> void:
	# Create mock LoopStateManager with required signals and methods
	_mock_loop_state = Node.new()
	_mock_loop_state.name = "LoopStateManager"
	_mock_loop_state.set_script(_create_loop_state_mock_script())
	add_child(_mock_loop_state)

	# Create mock InteractionBus with required methods
	_mock_interaction_bus = Node.new()
	_mock_interaction_bus.name = "InteractionBus"
	_mock_interaction_bus.set_script(_create_interaction_bus_mock_script())
	add_child(_mock_interaction_bus)

	# Create RoomManager with test wrapper that injects mocks via DI
	var test_wrapper := GDScript.new()
	test_wrapper.source_code = (
		"extends \"%s\"\n" % ROOM_MANAGER_SCRIPT
		+ "var _test_lsm: Node = null\n"
		+ "var _test_bus: Node = null\n"
		+ "func _get_loop_state_manager() -> Node:\n"
		+ "\treturn _test_lsm\n"
		+ "func _get_interaction_bus() -> Node:\n"
		+ "\treturn _test_bus\n"
	)
	test_wrapper.reload()

	_manager = Node.new()
	_manager.set_script(test_wrapper)
	_manager._test_lsm = _mock_loop_state
	_manager._test_bus = _mock_interaction_bus
	_manager.name = "RoomManagerTest"
	add_child(_manager)

	_signal_log = {}
	_connect_signals()


func after_test() -> void:
	if _manager:
		_manager.queue_free()
	if _mock_loop_state:
		_mock_loop_state.queue_free()
	if _mock_interaction_bus:
		_mock_interaction_bus.queue_free()


# --- Helper: Mock Scripts ---


func _create_loop_state_mock_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal night_ready(night: int)\n"
		+ "signal night_advanced(old_night: int, new_night: int)\n"
		+ "var _template_overrides: Dictionary = {}\n"
		+ "func get_template_override(entity_id: StringName, property: String) -> Variant:\n"
		+ "\tvar key: String = \"%s.%s\" % [entity_id, property]\n"
		+ "\treturn _template_overrides.get(key, null)\n"
		+ "func add_override(entity_id: StringName, property: String, value: Variant) -> void:\n"
		+ "\tvar key: String = \"%s.%s\" % [entity_id, property]\n"
		+ "\t_template_overrides[key] = value\n"
		+ "func clear_overrides() -> void:\n"
		+ "\t_template_overrides.clear()\n"
	)
	script.reload()
	return script


func _create_interaction_bus_mock_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var _registered: Dictionary = {}\n"
		+ "func register_interactable(id: StringName, info: Dictionary) -> void:\n"
		+ "\t_registered[id] = info\n"
		+ "func unregister_interactable(id: StringName) -> void:\n"
		+ "\t_registered.erase(id)\n"
		+ "func is_registered(id: StringName) -> bool:\n"
		+ "\treturn _registered.has(id)\n"
		+ "func get_registered_count() -> int:\n"
		+ "\treturn _registered.size()\n"
		+ "func clear_all() -> void:\n"
		+ "\t_registered.clear()\n"
	)
	script.reload()
	return script


func _connect_signals() -> void:
	_manager.room_transition_started.connect(
		func(from, to): _signal_log["room_transition_started"] = {"from": from, "to": to}
	)
	_manager.room_transition_completed.connect(
		func(room_id): _signal_log["room_transition_completed"] = room_id
	)
	_manager.room_loaded.connect(
		func(room_id):
			if not _signal_log.has("room_loaded"):
				_signal_log["room_loaded"] = []
			(_signal_log["room_loaded"] as Array).append(room_id)
	)
	_manager.room_unloaded.connect(
		func(room_id):
			if not _signal_log.has("room_unloaded"):
				_signal_log["room_unloaded"] = []
			(_signal_log["room_unloaded"] as Array).append(room_id)
	)
	_manager.room_changed.connect(
		func(room_id): _signal_log["room_changed"] = room_id
	)


# --- Helper: Scene Creation ---


## Creates a minimal PackedScene with a Node2D root and optional children.
func _create_test_room_scene(room_name: String = "TestRoom") -> PackedScene:
	var root: Node2D = Node2D.new()
	root.name = room_name

	var background: Node2D = Node2D.new()
	background.name = "Background"
	background.z_index = -10
	root.add_child(background)
	background.set_owner(root)

	var interactables: Node2D = Node2D.new()
	interactables.name = "Interactables"
	interactables.z_index = 0
	root.add_child(interactables)
	interactables.set_owner(root)

	var npcs: Node2D = Node2D.new()
	npcs.name = "NPCs"
	npcs.z_index = 1
	root.add_child(npcs)
	npcs.set_owner(root)

	var exits: Node2D = Node2D.new()
	exits.name = "Exits"
	exits.z_index = 2
	root.add_child(exits)
	exits.set_owner(root)

	var scene := PackedScene.new()
	var err: int = scene.pack(root)
	root.queue_free()
	if err != OK:
		return null
	return scene


## Injects a PackedScene directly into the room cache under a fake path.
func _inject_cached_scene(room_id: StringName, scene: PackedScene) -> void:
	var fake_path: String = "res://test_rooms/%s.tscn" % room_id
	_manager.register_room(room_id, fake_path)
	# Access private _room_cache via reflection (test-only)
	var cache: Dictionary = _manager.get("_room_cache") as Dictionary
	cache[fake_path] = scene


## Performs a transition with an injected test scene, skipping the real await
## by advancing frames. Returns after transition completes.
func _do_test_transition(room_id: StringName, scene: PackedScene) -> void:
	_inject_cached_scene(room_id, scene)
	_manager.request_transition(room_id)
	# The transition uses await internally. In GDUnit4 we need to let the
	# tweens complete. We simulate by monitoring _is_transitioning.
	# For synchronous test execution, we directly manipulate the internal state.
	# NOTE: Because request_transition uses await, in unit tests we call it
	# and then manually drive the completion for testability.
	await _manager.room_transition_completed


# --- Tests: Initial State ---


func test_initial_state_defaults() -> void:
	assert_that(_manager.get_current_room_id()).is_equal(&"")
	assert_bool(_manager.get_is_transitioning()).is_false()
	assert_float(_manager.get_fade_alpha()).is_equal(0.0)


# --- Tests: Room Registry ---


func test_register_room_adds_to_registry() -> void:
	_manager.register_room(&"lobby", "res://scenes/rooms/lobby.tscn")
	_manager.register_room(&"corridor", "res://scenes/rooms/corridor.tscn")
	# Verify registry is populated (access internal for test)
	var registry: Dictionary = _manager.get("_room_registry") as Dictionary
	assert_int(registry.size()).is_equal(2)
	assert_bool(registry.has(&"lobby")).is_true()
	assert_bool(registry.has(&"corridor")).is_true()


func test_register_room_overwrites_existing() -> void:
	_manager.register_room(&"lobby", "res://old_path.tscn")
	_manager.register_room(&"lobby", "res://new_path.tscn")
	var registry: Dictionary = _manager.get("_room_registry") as Dictionary
	assert_that(registry[&"lobby"]).is_equal("res://new_path.tscn")


# --- Tests: Fade Overlay ---


func test_fade_overlay_created() -> void:
	assert_float(_manager.get_fade_alpha()).is_equal(0.0)
	# Fade rect should exist as child of canvas layer
	var canvas: CanvasLayer = _manager.get("_fade_canvas") as CanvasLayer
	assert_object(canvas).is_not_null()
	assert_int(canvas.layer).is_equal(100)
	var rect: ColorRect = _manager.get("_fade_rect") as ColorRect
	assert_object(rect).is_not_null()
	assert_that(rect.color).is_equal(Color.BLACK)


func test_set_fade_alpha_clamps_zero_to_one() -> void:
	_manager.set_fade_alpha(-0.5)
	assert_float(_manager.get_fade_alpha()).is_equal(0.0)

	_manager.set_fade_alpha(1.5)
	assert_float(_manager.get_fade_alpha()).is_equal(1.0)

	_manager.set_fade_alpha(0.7)
	assert_float(_manager.get_fade_alpha()).is_equal_approx(0.7, 0.001)


# --- Tests: Transition Guard ---


func test_request_transition_unknown_room_rejected() -> void:
	# Should not crash or transition for unregistered room
	_manager.request_transition(&"nonexistent")
	assert_bool(_manager.get_is_transitioning()).is_false()
	assert_bool(not _signal_log.has("room_transition_started")).is_true()


# --- Tests: Room Container Setup ---


func test_room_container_exists() -> void:
	var container: Node2D = _manager.get("_room_container") as Node2D
	assert_object(container).is_not_null()
	assert_that(container.name).is_equal("RoomContainer")


# --- Tests: Interactable Registration ---


func test_register_interactables_finds_nodes() -> void:
	var scene: PackedScene = _create_test_room_scene()
	_inject_cached_scene(&"test_room", scene)

	var room_id: StringName = &"test_room"
	_manager.set("_active_room_id", room_id)
	_manager.call("_load_room", room_id)

	# Inject Interactable nodes directly onto the loaded room instance
	# (dynamic scripts don't survive PackedScene serialization)
	_inject_interactable_nodes()

	_manager.call("_register_room_interactables")

	assert_int(_mock_interaction_bus.get_registered_count()).is_equal(2)

	_manager.set("_active_room_id", &"")
	var inst: Node2D = _manager.get("_active_room_instance") as Node2D
	if inst:
		inst.queue_free()


func test_unregister_interactables_removes_all() -> void:
	var scene: PackedScene = _create_test_room_scene()
	_inject_cached_scene(&"test_room", scene)

	var room_id: StringName = &"test_room"
	_manager.set("_active_room_id", room_id)
	_manager.call("_load_room", room_id)
	_inject_interactable_nodes()

	_manager.call("_register_room_interactables")
	assert_int(_mock_interaction_bus.get_registered_count()).is_equal(2)

	_manager.call("_unregister_room_interactables")
	assert_int(_mock_interaction_bus.get_registered_count()).is_equal(0)

	_manager.set("_active_room_id", &"")
	var inst: Node2D = _manager.get("_active_room_instance") as Node2D
	if inst:
		inst.queue_free()


func test_get_active_interactables_empty_when_no_room() -> void:
	var result: Array[Node] = _manager.call("_get_active_interactables") as Array[Node]
	assert_array(result).is_empty()


# --- Tests: Template Reset ---


func test_apply_template_reset_no_op_when_no_room() -> void:
	# Should not crash when no room is active
	_manager.call("apply_template_reset")
	assert_bool(not _signal_log.has("room_unloaded")).is_true()


func test_pending_reset_deferred_during_transition() -> void:
	_manager.set("_is_transitioning", true)
	_manager.set("_active_room_id", &"lobby")

	_manager.call("apply_template_reset")

	# Should have set pending flag instead of actually resetting
	var pending: bool = _manager.get("_pending_reset") as bool
	assert_bool(pending).is_true()


func test_apply_template_reset_reloads_room() -> void:
	var scene: PackedScene = _create_test_room_scene("Lobby")
	_inject_cached_scene(&"lobby", scene)

	# Load a room first
	_manager.set("_active_room_id", &"lobby")
	_manager.call("_load_room", &"lobby")

	# Now reset
	_manager.call("apply_template_reset")

	# Should have unloaded and reloaded
	assert_array(_signal_log.get("room_unloaded", []) as Array).is_not_empty()
	assert_array(_signal_log.get("room_loaded", []) as Array).is_not_empty()


# --- Tests: Night Signal Callbacks ---


func test_on_night_ready_loads_lobby() -> void:
	var scene: PackedScene = _create_test_room_scene("Room_lobby")
	_manager.register_room(&"lobby", "res://test/lobby.tscn")
	# Inject into cache
	var cache: Dictionary = _manager.get("_room_cache") as Dictionary
	cache["res://test/lobby.tscn"] = scene

	_mock_loop_state.emit_signal("night_ready", 1)
	await _manager.room_transition_completed

	assert_that(_manager.get_current_room_id()).is_equal(&"lobby")


func test_on_night_advanced_triggers_reset() -> void:
	var scene: PackedScene = _create_test_room_scene("Lobby")
	_inject_cached_scene(&"lobby", scene)

	_manager.set("_active_room_id", &"lobby")
	_manager.call("_load_room", &"lobby")

	_mock_loop_state.emit_signal("night_advanced", 1, 2)
	# apply_template_reset is called synchronously (no transition active)
	assert_array(_signal_log.get("room_unloaded", []) as Array).is_not_empty()


# --- Tests: Load / Unload Internals ---


func test_load_room_creates_instance() -> void:
	var scene: PackedScene = _create_test_room_scene("TestRoom")
	_inject_cached_scene(&"test_room", scene)

	_manager.call("_load_room", &"test_room")

	var instance: Node2D = _manager.get("_active_room_instance") as Node2D
	assert_object(instance).is_not_null()
	assert_that(instance.name).is_equal("TestRoom")

	# Cleanup
	instance.queue_free()


func test_unload_current_room_clears_instance() -> void:
	var scene: PackedScene = _create_test_room_scene("TempRoom")
	_inject_cached_scene(&"temp", scene)

	_manager.call("_load_room", &"temp")
	assert_object(_manager.get("_active_room_instance")).is_not_null()

	_manager.call("_unload_current_room")
	assert_object(_manager.get("_active_room_instance")).is_null()


func test_get_or_load_scene_caches_result() -> void:
	var scene: PackedScene = _create_test_room_scene("Cached")
	var fake_path: String = "res://test/cached.tscn"
	_manager.register_room(&"cached", fake_path)

	# Inject into cache directly
	var cache: Dictionary = _manager.get("_room_cache") as Dictionary
	cache[fake_path] = scene

	var result: PackedScene = _manager.call("_get_or_load_scene", fake_path) as PackedScene
	assert_object(result).is_not_null()
	assert_that(result).is_equal(scene)


# --- Helper: Room Scene with Interactables ---


## Creates a scene with mock Interactable nodes for testing registration.
func _create_test_room_scene_with_interactables() -> PackedScene:
	var root: Node2D = Node2D.new()
	root.name = "RoomWithInteractables"

	var interactables: Node2D = Node2D.new()
	interactables.name = "Interactables"
	root.add_child(interactables)
	interactables.set_owner(root)

	# Create mock Interactable nodes (class_name Interactable is required
	# for find_children to find them, so we use a script with that class_name)
	var interactable_script := GDScript.new()
	interactable_script.source_code = (
		"class_name Interactable\n"
		+ "extends Node2D\n"
		+ "func get_interactable_id() -> StringName:\n"
		+ "\treturn StringName(name)\n"
		+ "func get_interactable_info() -> Dictionary:\n"
		+ "\treturn {\"target_type\": &\"item\", \"priority\": 0}\n"
	)
	interactable_script.reload()

	var item1: Node2D = Node2D.new()
	item1.set_script(interactable_script)
	item1.name = "Item_Diary"
	interactables.add_child(item1)
	item1.set_owner(root)

	var item2: Node2D = Node2D.new()
	item2.set_script(interactable_script)
	item2.name = "Item_Key"
	interactables.add_child(item2)
	item2.set_owner(root)

	var scene := PackedScene.new()
	var err: int = scene.pack(root)
	root.queue_free()
	if err != OK:
		return null
	return scene


## Adds Interactable nodes directly to the active room instance.
## Dynamic scripts don't survive PackedScene round-trip, so this must
## be called after _load_room to inject test interactables.
func _inject_interactable_nodes() -> void:
	var instance: Node2D = _manager.get("_active_room_instance") as Node2D
	if instance == null:
		return

	var interactables_parent: Node = instance.find_child("Interactables", true, false)
	if interactables_parent == null:
		interactables_parent = Node2D.new()
		interactables_parent.name = "Interactables"
		instance.add_child(interactables_parent)

	var interactable_script := GDScript.new()
	interactable_script.source_code = (
		"class_name Interactable\n"
		+ "extends Node2D\n"
		+ "func get_interactable_id() -> StringName:\n"
		+ "\treturn StringName(name)\n"
		+ "func get_interactable_info() -> Dictionary:\n"
		+ "\treturn {\"target_type\": &\"item\", \"priority\": 0}\n"
	)
	interactable_script.reload()

	var item1: Node2D = Node2D.new()
	item1.set_script(interactable_script)
	item1.name = "Item_Diary"
	interactables_parent.add_child(item1)

	var item2: Node2D = Node2D.new()
	item2.set_script(interactable_script)
	item2.name = "Item_Key"
	interactables_parent.add_child(item2)


# --- Tests: Template Override Application ---


func test_apply_template_overrides_sets_visible() -> void:
	var scene: PackedScene = _create_test_room_scene_with_visible_child()
	_inject_cached_scene(&"override_room", scene)

	_manager.set("_active_room_id", &"override_room")
	_manager.call("_load_room", &"override_room")

	# Set up an override: make "SecretDoor" invisible
	_mock_loop_state.call("add_override", &"SecretDoor", "visible", false)

	_manager.call("_apply_template_overrides")

	# Verify the child node's visible property was changed
	var instance: Node2D = _manager.get("_active_room_instance") as Node2D
	var door: Node = instance.find_child("SecretDoor", true, false)
	assert_object(door).is_not_null()
	assert_bool(door.visible).is_false()

	# Cleanup
	instance.queue_free()


func _create_test_room_scene_with_visible_child() -> PackedScene:
	var root: Node2D = Node2D.new()
	root.name = "OverrideTestRoom"

	var interactables: Node2D = Node2D.new()
	interactables.name = "Interactables"
	root.add_child(interactables)
	interactables.set_owner(root)

	var door: Node2D = Node2D.new()
	door.name = "SecretDoor"
	door.visible = true
	interactables.add_child(door)
	door.set_owner(root)

	var scene := PackedScene.new()
	var err: int = scene.pack(root)
	root.queue_free()
	if err != OK:
		return null
	return scene
