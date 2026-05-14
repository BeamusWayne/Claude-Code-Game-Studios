extends GdUnitTestSuite

# Tests for InteractionBus — event bus + interactable registration.
# Covers ADR-0006 requirements: event emission, priority resolution,
# single-event-per-frame constraint, input method tagging, and timestamps.


const INTERACTION_BUS_SCRIPT := "res://src/core/interaction_bus.gd"

var _bus: Node
var _detected_events: Array


func before_test() -> void:
	_bus = Node.new()
	_bus.set_script(load(INTERACTION_BUS_SCRIPT))
	_bus.name = "InteractionBusTest"
	add_child(_bus)
	_detected_events = []
	_bus.interaction_detected.connect(func(event): _detected_events.append(event))


func after_test() -> void:
	if _bus:
		_bus.queue_free()


func _make_event(type_val: int, target_id: StringName, target_type: StringName, priority: int = 0, input_method: int = 0, ts: int = 0) -> Dictionary:
	return {
		"type": type_val,
		"target_id": target_id,
		"target_type": target_type,
		"position": Vector2.ZERO,
		"input_method": input_method,
		"timestamp": ts,
		"priority": priority,
		"metadata": {},
	}


func test_register_interactable() -> void:
	_bus.register_interactable(&"item_1", {"target_type": &"item", "priority": 0})
	assert_bool(_bus.is_registered(&"item_1")).is_true()
	assert_int(_bus.get_registered_count()).is_equal(1)


func test_unregister_interactable() -> void:
	_bus.register_interactable(&"item_1", {"target_type": &"item", "priority": 0})
	_bus.unregister_interactable(&"item_1")
	assert_bool(_bus.is_registered(&"item_1")).is_false()
	assert_int(_bus.get_registered_count()).is_equal(0)


func test_emit_click_event() -> void:
	_bus.emit_interaction({
		"type": 0,
		"target_id": &"test_item",
		"target_type": &"item",
		"position": Vector2(100, 200),
		"input_method": 0,
		"timestamp": Time.get_ticks_msec(),
		"priority": 0,
		"metadata": {},
	})
	_bus._process(0.016)
	assert_int(_detected_events.size()).is_equal(1)
	assert_int(_detected_events[0]["type"]).is_equal(0)


func test_emit_long_press_event() -> void:
	_bus.emit_interaction({
		"type": 1,
		"target_id": &"test_npc",
		"target_type": &"npc",
		"position": Vector2(300, 400),
		"input_method": 0,
		"timestamp": Time.get_ticks_msec(),
		"priority": 0,
		"metadata": {},
	})
	_bus._process(0.016)
	assert_int(_detected_events.size()).is_equal(1)
	assert_int(_detected_events[0]["type"]).is_equal(1)


func test_priority_resolution() -> void:
	_bus.emit_interaction(_make_event(0, &"low", &"item", 1))
	_bus.emit_interaction(_make_event(0, &"high", &"npc", 5))
	_bus.emit_interaction(_make_event(0, &"mid", &"exit", 3))
	_bus._process(0.016)
	assert_int(_detected_events.size()).is_equal(1)
	assert_that(_detected_events[0]["target_id"]).is_equal(&"high")


func test_single_event_per_frame() -> void:
	for i in range(5):
		_bus.emit_interaction(_make_event(0, StringName("item_%d" % i), &"item", i))
	_bus._process(0.016)
	assert_int(_detected_events.size()).is_equal(1)


func test_input_method_mouse_tagged() -> void:
	_bus.emit_interaction(_make_event(0, &"test", &"item", 0, 0))
	_bus._process(0.016)
	assert_int(_detected_events[0]["input_method"]).is_equal(0)


func test_input_method_touch_tagged() -> void:
	_bus.emit_interaction(_make_event(0, &"test", &"item", 0, 1))
	_bus._process(0.016)
	assert_int(_detected_events[0]["input_method"]).is_equal(1)


func test_timestamp_populated() -> void:
	var ts := Time.get_ticks_msec()
	_bus.emit_interaction({
		"type": 0, "target_id": &"test", "target_type": &"item",
		"position": Vector2.ZERO, "input_method": 0, "timestamp": ts,
		"priority": 0, "metadata": {},
	})
	_bus._process(0.016)
	assert_int(_detected_events[0]["timestamp"]).is_equal(ts)


func test_target_id_and_type_populated() -> void:
	_bus.emit_interaction({
		"type": 0, "target_id": &"clue_diary", "target_type": &"item",
		"position": Vector2(50, 60), "input_method": 0, "timestamp": 0,
		"priority": 0, "metadata": {},
	})
	_bus._process(0.016)
	assert_that(_detected_events[0]["target_id"]).is_equal(&"clue_diary")
	assert_that(_detected_events[0]["target_type"]).is_equal(&"item")


func test_empty_buffer_no_emit() -> void:
	_bus._process(0.016)
	assert_array(_detected_events).is_empty()


func test_unregister_prevents_stale() -> void:
	_bus.register_interactable(&"door_1", {"target_type": &"exit", "priority": 0})
	_bus.unregister_interactable(&"door_1")
	assert_bool(_bus.is_registered(&"door_1")).is_false()
	_bus.emit_interaction({
		"type": 0, "target_id": &"door_1", "target_type": &"exit",
		"position": Vector2.ZERO, "input_method": 0, "timestamp": 0,
		"priority": 0, "metadata": {},
	})
	_bus._process(0.016)
	assert_int(_detected_events.size()).is_equal(1)
