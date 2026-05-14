extends GdUnitTestSuite

## Tests for ColorAccumulationManager — knowledge level computation,
## per-NPC saturation, pressure penalty, and driver integration.
## Covers GDD acceptance criteria from design/gdd/color-accumulation.md.

const CAM_SCRIPT := "res://src/feature/color_accumulation_manager.gd"

var _manager: Node
var _mock_db: Node
var _mock_timer: Node
var _mock_driver: Node
var _mock_npc: Node

var _knowledge_events: Array


func before_test() -> void:
	_mock_db = Node.new()
	_mock_db.name = "ClueDatabase"
	_mock_db.set_script(_create_db_mock())
	add_child(_mock_db)

	_mock_timer = Node.new()
	_mock_timer.name = "TimerService"
	_mock_timer.set_script(_create_timer_mock())
	add_child(_mock_timer)

	_mock_driver = Node.new()
	_mock_driver.name = "InkWashDriver"
	_mock_driver.set_script(_create_driver_mock())
	add_child(_mock_driver)

	_mock_npc = Node.new()
	_mock_npc.name = "NPCManager"
	_mock_npc.set_script(_create_npc_mock())
	add_child(_mock_npc)

	var wrapper := GDScript.new()
	wrapper.source_code = (
		"extends \"%s\"\n" % CAM_SCRIPT
		+ "var _test_db: Node = null\n"
		+ "var _test_timer: Node = null\n"
		+ "var _test_driver: Node = null\n"
		+ "var _test_npc: Node = null\n"
		+ "func _get_clue_database() -> Node:\n"
		+ "\treturn _test_db\n"
		+ "func _get_timer_service() -> Node:\n"
		+ "\treturn _test_timer\n"
		+ "func _get_ink_wash_driver() -> Node:\n"
		+ "\treturn _test_driver\n"
		+ "func _get_npc_manager() -> Node:\n"
		+ "\treturn _test_npc\n"
	)
	wrapper.reload()

	_manager = Node.new()
	_manager.set_script(wrapper)
	_manager._test_db = _mock_db
	_manager._test_timer = _mock_timer
	_manager._test_driver = _mock_driver
	_manager._test_npc = _mock_npc
	_manager.name = "ColorAccumulationManagerTest"
	add_child(_manager)

	_knowledge_events = []
	_manager.knowledge_level_changed.connect(_on_knowledge_changed)


func _on_knowledge_changed(new_level: float) -> void:
	_knowledge_events.append(new_level)


func after_test() -> void:
	if _manager:
		_manager.queue_free()
	if _mock_db:
		_mock_db.queue_free()
	if _mock_timer:
		_mock_timer.queue_free()
	if _mock_driver:
		_mock_driver.queue_free()
	if _mock_npc:
		_mock_npc.queue_free()


# ---------------------------------------------------------------------------
# Mock Scripts
# ---------------------------------------------------------------------------


func _create_db_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal clue_discovered(clue_id: StringName)\n"
		+ "signal insight_generated(insight_id: StringName)\n"
		+ "var _insights: Array[StringName] = []\n"
		+ "var _entries: Dictionary = {}\n"
		+ "var _connections: Array[Dictionary] = []\n"
		+ "func get_all_insights() -> Array[StringName]:\n"
		+ "\treturn _insights\n"
		+ "func search_by_npc(npc_id: StringName) -> Array[StringName]:\n"
		+ "\tvar result: Array[StringName] = []\n"
		+ "\tfor id: StringName in _insights:\n"
		+ "\t\tif _entries.has(id) and _entries[id].get('npc_affinity', &'') == npc_id:\n"
		+ "\t\t\t\tresult.append(id)\n"
		+ "\treturn result\n"
		+ "func get_entry(id: StringName) -> Dictionary:\n"
		+ "\treturn _entries.get(id, {})\n"
		+ "func add_insight(insight_id: StringName, npc_affinity: StringName) -> void:\n"
		+ "\t_insights.append(insight_id)\n"
		+ "\t_entries[insight_id] = {'entry_type': 1, 'npc_affinity': npc_affinity}\n"
		+ "\tinsight_generated.emit(insight_id)\n"
		+ "func get_valid_connections() -> Array[Dictionary]:\n"
		+ "\treturn _connections\n"
	)
	script.reload()
	return script


func _create_timer_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal pressure_updated(pressure_level: float)\n"
		+ "var current_phase: int = 0\n"
		+ "var pressure_level: float = 0.0\n"
	)
	script.reload()
	return script


func _create_driver_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var knowledge_level: float = 0.0\n"
		+ "func set_knowledge_level(value: float) -> void:\n"
		+ "\tknowledge_level = value\n"
	)
	script.reload()
	return script


func _create_npc_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "func get_all_npc_ids() -> Array[StringName]:\n"
		+ "\treturn [&'guest_indigo', &'guest_ochre']\n"
	)
	script.reload()
	return script


# ---------------------------------------------------------------------------
# Tests: Knowledge Level
# ---------------------------------------------------------------------------


func test_knowledge_level_zero_with_no_insights() -> void:
	assert_float(_manager.knowledge_level).is_equal(0.0)


func test_knowledge_level_increases_with_insights() -> void:
	_mock_db.add_insight(&"insight_1", &"guest_indigo")
	assert_float(_manager.knowledge_level).is_equal_approx(0.1, 0.001)


func test_knowledge_level_full() -> void:
	for i in range(10):
		_mock_db.add_insight(StringName("insight_%d" % (i + 1)), &"guest_indigo")
	assert_float(_manager.knowledge_level).is_equal(1.0)


func test_knowledge_level_clamped_to_one() -> void:
	for i in range(15):
		_mock_db.add_insight(StringName("insight_%d" % (i + 1)), &"guest_indigo")
	assert_float(_manager.knowledge_level).is_equal(1.0)


func test_knowledge_level_changed_signal() -> void:
	_mock_db.add_insight(&"insight_1", &"guest_indigo")
	assert_int(_knowledge_events.size()).is_greater_equal(1)
	assert_float(_knowledge_events[_knowledge_events.size() - 1]).is_equal_approx(0.1, 0.001)


# ---------------------------------------------------------------------------
# Tests: NPC Saturation
# ---------------------------------------------------------------------------


func test_npc_saturation_base_with_no_insights() -> void:
	assert_float(_manager.get_npc_saturation(&"guest_indigo")).is_equal_approx(0.10, 0.001)


func test_npc_saturation_increases_with_insights() -> void:
	_mock_db.add_insight(&"insight_1", &"guest_indigo")
	assert_float(_manager.get_npc_saturation(&"guest_indigo")).is_greater(0.10)


func test_npc_saturation_independent_per_npc() -> void:
	_mock_db.add_insight(&"insight_1", &"guest_indigo")
	assert_float(_manager.get_npc_saturation(&"guest_indigo")).is_greater(0.10)
	assert_float(_manager.get_npc_saturation(&"guest_ochre")).is_equal_approx(0.10, 0.001)


func test_npc_saturation_unknown_returns_base() -> void:
	assert_float(_manager.get_npc_saturation(&"unknown")).is_equal_approx(0.10, 0.001)


# ---------------------------------------------------------------------------
# Tests: Pressure Penalty
# ---------------------------------------------------------------------------


func test_no_penalty_in_calm_phase() -> void:
	_mock_db.add_insight(&"insight_1", &"guest_indigo")
	var base_knowledge: float = _manager.knowledge_level
	_mock_timer.current_phase = 0  # CALM
	_mock_timer.pressure_level = 0.8
	_manager._on_pressure_updated(0.8)
	assert_float(_manager.effective_knowledge).is_equal_approx(base_knowledge, 0.001)


func test_penalty_in_intense_phase() -> void:
	_mock_db.add_insight(&"insight_1", &"guest_indigo")
	_mock_timer.current_phase = 1  # INTENSE
	_mock_timer.pressure_level = 0.5
	_manager._on_pressure_updated(0.5)
	var expected: float = _manager.knowledge_level * (1.0 - 0.3 * 0.5)
	assert_float(_manager.effective_knowledge).is_equal_approx(expected, 0.001)


func test_penalty_in_critical_phase() -> void:
	_mock_db.add_insight(&"insight_1", &"guest_indigo")
	_mock_timer.current_phase = 2  # CRITICAL
	_mock_timer.pressure_level = 1.0
	_manager._on_pressure_updated(1.0)
	var expected: float = _manager.knowledge_level * (1.0 - 0.3 * 1.0)
	assert_float(_manager.effective_knowledge).is_equal_approx(expected, 0.001)


func test_penalty_never_makes_negative() -> void:
	_mock_timer.current_phase = 2  # CRITICAL
	_manager._on_pressure_updated(2.0)  # Above 1.0 pressure
	assert_float(_manager.effective_knowledge).is_greater_equal(0.0)


# ---------------------------------------------------------------------------
# Tests: Driver Integration
# ---------------------------------------------------------------------------


func test_driver_receives_effective_knowledge() -> void:
	_mock_db.add_insight(&"insight_1", &"guest_indigo")
	assert_float(_mock_driver.knowledge_level).is_equal_approx(_manager.effective_knowledge, 0.001)


func test_driver_updates_on_pressure() -> void:
	_mock_db.add_insight(&"insight_1", &"guest_indigo")
	_mock_timer.current_phase = 1  # INTENSE
	_manager._on_pressure_updated(0.5)
	assert_float(_mock_driver.knowledge_level).is_equal_approx(_manager.effective_knowledge, 0.001)


# ---------------------------------------------------------------------------
# Tests: Serialize / Deserialize / Reset
# ---------------------------------------------------------------------------


func test_serialize_contains_pressure() -> void:
	_mock_timer.pressure_level = 0.5
	_manager._on_pressure_updated(0.5)
	var data: Dictionary = _manager.serialize()
	assert_float(data.get("pressure_level", 0.0)).is_equal(0.5)


func test_deserialize_restores_state() -> void:
	_mock_db.add_insight(&"insight_1", &"guest_indigo")
	var data: Dictionary = _manager.serialize()
	_manager.reset()
	_manager.deserialize(data)
	assert_float(_manager._pressure_level).is_equal(data.get("pressure_level", 0.0))


func test_reset_clears_all() -> void:
	_mock_db.add_insight(&"insight_1", &"guest_indigo")
	_manager.reset()
	assert_float(_manager.knowledge_level).is_equal(0.0)
	assert_float(_manager.effective_knowledge).is_equal(0.0)
	assert_dict(_manager.npc_saturations).is_empty()
