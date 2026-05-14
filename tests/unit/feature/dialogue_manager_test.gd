extends GdUnitTestSuite

## Tests for DialogueManager — dialogue flow, condition evaluation, consequences.
## Covers GDD acceptance criteria from design/gdd/conditional-dialogue-trees.md.

const DM_SCRIPT := "res://src/feature/dialogue_manager.gd"

var _manager: Node
var _mock_timer: Node
var _mock_npc: Node
var _mock_trust: Node
var _mock_db: Node
var _mock_lsm: Node
var _mock_event: Node

var _started_events: Array
var _ended_events: Array
var _choice_events: Array
var _node_displayed_events: Array


func before_test() -> void:
	_mock_timer = Node.new()
	_mock_timer.name = "TimerService"
	_mock_timer.set_script(_create_timer_mock())
	add_child(_mock_timer)

	_mock_npc = Node.new()
	_mock_npc.name = "NPCManager"
	_mock_npc.set_script(_create_npc_mock())
	add_child(_mock_npc)

	_mock_trust = Node.new()
	_mock_trust.name = "TrustSuspicionManager"
	_mock_trust.set_script(_create_trust_mock())
	add_child(_mock_trust)

	_mock_db = Node.new()
	_mock_db.name = "ClueDatabase"
	_mock_db.set_script(_create_db_mock())
	add_child(_mock_db)

	_mock_lsm = Node.new()
	_mock_lsm.name = "LoopStateManager"
	_mock_lsm.set_script(_create_lsm_mock())
	add_child(_mock_lsm)

	_mock_event = Node.new()
	_mock_event.name = "EventScheduler"
	_mock_event.set_script(_create_event_mock())
	add_child(_mock_event)

	var wrapper := GDScript.new()
	wrapper.source_code = (
		"extends \"%s\"\n" % DM_SCRIPT
		+ "var _test_timer: Node = null\n"
		+ "var _test_npc: Node = null\n"
		+ "var _test_trust: Node = null\n"
		+ "var _test_db: Node = null\n"
		+ "var _test_lsm: Node = null\n"
		+ "var _test_event: Node = null\n"
		+ "func _get_timer_service() -> Node:\n"
		+ "\treturn _test_timer\n"
		+ "func _get_npc_manager() -> Node:\n"
		+ "\treturn _test_npc\n"
		+ "func _get_trust_manager() -> Node:\n"
		+ "\treturn _test_trust\n"
		+ "func _get_clue_database() -> Node:\n"
		+ "\treturn _test_db\n"
		+ "func _get_loop_state_manager() -> Node:\n"
		+ "\treturn _test_lsm\n"
		+ "func _get_event_scheduler() -> Node:\n"
		+ "\treturn _test_event\n"
	)
	wrapper.reload()

	_manager = Node.new()
	_manager.set_script(wrapper)
	_manager._test_timer = _mock_timer
	_manager._test_npc = _mock_npc
	_manager._test_trust = _mock_trust
	_manager._test_db = _mock_db
	_manager._test_lsm = _mock_lsm
	_manager._test_event = _mock_event
	_manager.name = "DialogueManagerTest"
	add_child(_manager)

	_started_events = []
	_ended_events = []
	_choice_events = []
	_node_displayed_events = []
	_manager.dialogue_started.connect(_on_started)
	_manager.dialogue_ended.connect(_on_ended)
	_manager.dialogue_choice_made.connect(_on_choice)
	_manager.node_displayed.connect(_on_node_displayed)


func _on_started(npc_id: StringName) -> void:
	_started_events.append(npc_id)


func _on_ended(npc_id: StringName) -> void:
	_ended_events.append(npc_id)


func _on_choice(npc_id: StringName, choice_id: StringName) -> void:
	_choice_events.append({"npc": npc_id, "choice": choice_id})


func _on_node_displayed(node_id: StringName, text: String) -> void:
	_node_displayed_events.append({"id": node_id, "text": text})


func after_test() -> void:
	if _manager:
		_manager.queue_free()
	if _mock_timer:
		_mock_timer.queue_free()
	if _mock_npc:
		_mock_npc.queue_free()
	if _mock_trust:
		_mock_trust.queue_free()
	if _mock_db:
		_mock_db.queue_free()
	if _mock_lsm:
		_mock_lsm.queue_free()
	if _mock_event:
		_mock_event.queue_free()


# ---------------------------------------------------------------------------
# Mock Scripts
# ---------------------------------------------------------------------------


func _create_timer_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var time_scale: float = 1.0\n"
		+ "var current_phase: int = 0\n"
		+ "func set_time_scale(s: float) -> void:\n"
		+ "\ttime_scale = s\n"
	)
	script.reload()
	return script


func _create_npc_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var _emotional_states: Dictionary = {}\n"
		+ "var _dialogue_available: Dictionary = {}\n"
		+ "var _state_transitions: Array = []\n"
		+ "func get_emotional_state(npc_id: StringName) -> int:\n"
		+ "\treturn _emotional_states.get(npc_id, 0)\n"
		+ "func is_dialogue_available(npc_id: StringName) -> bool:\n"
		+ "\treturn _dialogue_available.get(npc_id, true)\n"
		+ "func request_state_transition(npc_id: StringName, new_state: int) -> bool:\n"
		+ "\t_state_transitions.append({\"npc\": npc_id, \"state\": new_state})\n"
		+ "\t_emotional_states[npc_id] = new_state\n"
		+ "\treturn true\n"
	)
	script.reload()
	return script


func _create_trust_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var _trust: Dictionary = {}\n"
		+ "var _suspicion: Dictionary = {}\n"
		+ "var _trust_deltas: Array = []\n"
		+ "var _suspicion_deltas: Array = []\n"
		+ "func get_trust(npc_id: StringName) -> float:\n"
		+ "\treturn _trust.get(npc_id, 50.0)\n"
		+ "func get_suspicion(npc_id: StringName) -> float:\n"
		+ "\treturn _suspicion.get(npc_id, 0.0)\n"
		+ "func apply_trust_delta(npc_id: StringName, delta: float) -> float:\n"
		+ "\t_trust_deltas.append({\"npc\": npc_id, \"delta\": delta})\n"
		+ "\tvar cur: float = _trust.get(npc_id, 50.0)\n"
		+ "\t_trust[npc_id] = cur + delta\n"
		+ "\treturn _trust[npc_id]\n"
		+ "func apply_suspicion_delta(npc_id: StringName, delta: float) -> float:\n"
		+ "\t_suspicion_deltas.append({\"npc\": npc_id, \"delta\": delta})\n"
		+ "\tvar cur: float = _suspicion.get(npc_id, 0.0)\n"
		+ "\t_suspicion[npc_id] = cur + delta\n"
		+ "\treturn _suspicion[npc_id]\n"
	)
	script.reload()
	return script


func _create_db_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var _clues: Dictionary = {}\n"
		+ "var _insights: Dictionary = {}\n"
		+ "var _entries: Array = []\n"
		+ "func has_clue(id: StringName) -> bool:\n"
		+ "\treturn _clues.has(id)\n"
		+ "func has_insight(id: StringName) -> bool:\n"
		+ "\treturn _insights.has(id)\n"
		+ "func add_entry(entry: Dictionary) -> bool:\n"
		+ "\t_entries.append(entry)\n"
		+ "\treturn true\n"
	)
	script.reload()
	return script


func _create_lsm_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var current_night: int = 1\n"
		+ "var current_phase: int = 0\n"
		+ "var _state_values: Dictionary = {}\n"
		+ "var _consequences: Array = []\n"
		+ "func get_active_state_value(key: StringName) -> Variant:\n"
		+ "\treturn _state_values.get(key, null)\n"
		+ "func register_consequence(id: StringName, data: Dictionary) -> void:\n"
		+ "\t_consequences.append({\"id\": id, \"data\": data})\n"
	)
	script.reload()
	return script


func _create_event_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var _fired: Array = []\n"
		+ "func fire_event(event_id: StringName) -> void:\n"
		+ "\t_fired.append(event_id)\n"
	)
	script.reload()
	return script


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _make_tree(nodes: Array[Dictionary] = []) -> Dictionary:
	return {"tree_id": &"test_tree", "npc_id": &"npc_1", "nodes": nodes}


func _make_node(node_id: StringName, text: String, is_start: bool = false,
		next_id: StringName = &"", choices: Array = [],
		conditions: Array = [], priority: int = 0) -> Dictionary:
	return {
		"id": node_id,
		"text": text,
		"is_start": is_start,
		"next_node_id": next_id,
		"choices": choices,
		"conditions": conditions,
		"priority": priority,
	}


func _make_choice(choice_id: StringName, text: String,
		next_id: StringName = &"",
		consequences: Array = [],
		conditions: Array = []) -> Dictionary:
	return {
		"id": choice_id,
		"text": text,
		"next_node_id": next_id,
		"consequences": consequences,
		"conditions": conditions,
	}


func _make_condition(source: String, target_id: StringName = &"",
		comparison: String = "eq", value: Variant = null) -> Dictionary:
	return {
		"source": source,
		"target_id": target_id,
		"comparison": comparison,
		"value": value,
	}


func _make_consequence(type: String, target_id: StringName = &"",
		value: Variant = null) -> Dictionary:
	return {
		"type": type,
		"target_id": target_id,
		"value": value,
	}


# ---------------------------------------------------------------------------
# Tests: Basic Dialogue Flow
# ---------------------------------------------------------------------------


func test_start_dialogue_basic() -> void:
	var tree := _make_tree([_make_node(&"start", "Hello!", true)])
	var result: bool = _manager.start_dialogue(&"npc_1", tree)
	assert_bool(result).is_true()
	assert_bool(_manager.is_active).is_true()
	assert_int(_started_events.size()).is_equal(1)
	assert_str(String(_started_events[0])).is_equal("npc_1")


func test_start_dialogue_empty_tree() -> void:
	var result: bool = _manager.start_dialogue(&"npc_1", {})
	assert_bool(result).is_false()
	assert_bool(_manager.is_active).is_false()


func test_start_dialogue_empty_nodes() -> void:
	var result: bool = _manager.start_dialogue(&"npc_1", _make_tree([]))
	assert_bool(result).is_false()


func test_start_dialogue_while_active() -> void:
	var tree := _make_tree([_make_node(&"start", "Hello!", true)])
	_manager.start_dialogue(&"npc_1", tree)
	var result: bool = _manager.start_dialogue(&"npc_2", tree)
	assert_bool(result).is_false()


func test_end_dialogue_basic() -> void:
	var tree := _make_tree([_make_node(&"start", "Hello!", true)])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.end_dialogue()
	assert_bool(_manager.is_active).is_false()
	assert_int(_ended_events.size()).is_equal(1)
	assert_str(String(_ended_events[0])).is_equal("npc_1")


func test_end_dialogue_not_active() -> void:
	_manager.end_dialogue()
	assert_int(_ended_events.size()).is_equal(0)


func test_advance_to_next_node() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Hello!", true, &"second"),
		_make_node(&"second", "World!"),
	])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.advance()
	assert_str(String(_manager.get_current_node_id())).is_equal("second")
	assert_str(_manager.get_current_text()).is_equal("World!")


func test_advance_to_end() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Hello!", true, &""),
	])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.advance()
	assert_bool(_manager.is_active).is_false()
	assert_int(_ended_events.size()).is_equal(1)


func test_advance_end_keyword() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Hello!", true, &"END"),
	])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.advance()
	assert_bool(_manager.is_active).is_false()


func test_advance_ignored_with_choices() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Pick:", true, &"next", [
			_make_choice(&"c1", "Choice 1", &"next"),
		]),
		_make_node(&"next", "Next"),
	])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.advance()
	assert_str(String(_manager.get_current_node_id())).is_equal("start")


func test_advance_missing_node_ends_dialogue() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Hello!", true, &"nonexistent"),
	])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.advance()
	assert_bool(_manager.is_active).is_false()


# ---------------------------------------------------------------------------
# Tests: Choice Selection
# ---------------------------------------------------------------------------


func test_select_choice_basic() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Pick:", true, &"", [
			_make_choice(&"c1", "Go", &"second"),
		]),
		_make_node(&"second", "Done"),
	])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.select_choice(&"c1")
	assert_str(String(_manager.get_current_node_id())).is_equal("second")
	assert_int(_choice_events.size()).is_equal(1)
	assert_str(String(_choice_events[0]["choice"])).is_equal("c1")


func test_select_choice_ends_dialogue() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Pick:", true, &"", [
			_make_choice(&"c1", "End", &""),
		]),
	])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.select_choice(&"c1")
	assert_bool(_manager.is_active).is_false()
	assert_int(_ended_events.size()).is_equal(1)


func test_select_choice_end_keyword() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Pick:", true, &"", [
			_make_choice(&"c1", "End", &"END"),
		]),
	])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.select_choice(&"c1")
	assert_bool(_manager.is_active).is_false()


func test_select_choice_invalid_id() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Pick:", true, &"", [
			_make_choice(&"c1", "Go", &"next"),
		]),
		_make_node(&"next", "Done"),
	])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.select_choice(&"nonexistent")
	assert_str(String(_manager.get_current_node_id())).is_equal("start")


func test_select_choice_not_active() -> void:
	_manager.select_choice(&"c1")
	assert_int(_choice_events.size()).is_equal(0)


func test_select_choice_missing_next_node() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Pick:", true, &"", [
			_make_choice(&"c1", "Go", &"missing"),
		]),
	])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.select_choice(&"c1")
	assert_bool(_manager.is_active).is_false()


# ---------------------------------------------------------------------------
# Tests: Signal Emission
# ---------------------------------------------------------------------------


func test_dialogue_started_signal() -> void:
	var tree := _make_tree([_make_node(&"start", "Hi", true)])
	_manager.start_dialogue(&"npc_1", tree)
	assert_int(_started_events.size()).is_equal(1)


func test_dialogue_ended_signal() -> void:
	var tree := _make_tree([_make_node(&"start", "Hi", true)])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.end_dialogue()
	assert_int(_ended_events.size()).is_equal(1)


func test_node_displayed_signal() -> void:
	var tree := _make_tree([_make_node(&"start", "Hello world", true)])
	_manager.start_dialogue(&"npc_1", tree)
	assert_int(_node_displayed_events.size()).is_equal(1)
	assert_str(String(_node_displayed_events[0]["id"])).is_equal("start")
	assert_str(_node_displayed_events[0]["text"]).is_equal("Hello world")


func test_choice_made_signal() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Pick:", true, &"", [
			_make_choice(&"c1", "End", &""),
		]),
	])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.select_choice(&"c1")
	assert_int(_choice_events.size()).is_equal(1)
	assert_str(String(_choice_events[0]["npc"])).is_equal("npc_1")
	assert_str(String(_choice_events[0]["choice"])).is_equal("c1")


# ---------------------------------------------------------------------------
# Tests: Timer Scale
# ---------------------------------------------------------------------------


func test_timer_slows_on_start() -> void:
	var tree := _make_tree([_make_node(&"start", "Hi", true)])
	_manager.start_dialogue(&"npc_1", tree)
	assert_float(_mock_timer.time_scale).is_equal(0.5)


func test_timer_restores_on_end() -> void:
	var tree := _make_tree([_make_node(&"start", "Hi", true)])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.end_dialogue()
	assert_float(_mock_timer.time_scale).is_equal(1.0)


func test_timer_restores_on_auto_end() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Hi", true, &""),
	])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.advance()
	assert_float(_mock_timer.time_scale).is_equal(1.0)


# ---------------------------------------------------------------------------
# Tests: Condition Evaluation — Comparisons
# ---------------------------------------------------------------------------


func test_condition_eq() -> void:
	assert_bool(_manager._evaluate_single(
		_make_condition("current_night", &"", "eq", 1)
	)).is_true()
	assert_bool(_manager._evaluate_single(
		_make_condition("current_night", &"", "eq", 2)
	)).is_false()


func test_condition_neq() -> void:
	assert_bool(_manager._evaluate_single(
		_make_condition("current_night", &"", "neq", 2)
	)).is_true()


func test_condition_gte() -> void:
	assert_bool(_manager._evaluate_single(
		_make_condition("current_night", &"", "gte", 1)
	)).is_true()
	assert_bool(_manager._evaluate_single(
		_make_condition("current_night", &"", "gte", 2)
	)).is_false()


func test_condition_lte() -> void:
	assert_bool(_manager._evaluate_single(
		_make_condition("current_night", &"", "lte", 1)
	)).is_true()
	assert_bool(_manager._evaluate_single(
		_make_condition("current_night", &"", "lte", 0)
	)).is_false()


func test_condition_gt() -> void:
	assert_bool(_manager._evaluate_single(
		_make_condition("current_night", &"", "gt", 0)
	)).is_true()


func test_condition_lt() -> void:
	assert_bool(_manager._evaluate_single(
		_make_condition("current_night", &"", "lt", 2)
	)).is_true()


func test_condition_exists() -> void:
	_mock_lsm._state_values[&"test_key"] = "value"
	assert_bool(_manager._evaluate_single(
		_make_condition("loop_state", &"test_key", "exists", null)
	)).is_true()


func test_condition_not_exists() -> void:
	assert_bool(_manager._evaluate_single(
		_make_condition("loop_state", &"missing_key", "not_exists", null)
	)).is_true()


func test_condition_empty_array_passes() -> void:
	assert_bool(_manager._evaluate_conditions([])).is_true()


func test_condition_unknown_source_returns_null() -> void:
	var result: Variant = _manager._get_condition_value(
		_make_condition("unknown_source", &"", "eq", null)
	)
	assert_bool(result == null).is_true()


# ---------------------------------------------------------------------------
# Tests: Condition Sources
# ---------------------------------------------------------------------------


func test_condition_npc_emotional_state() -> void:
	_mock_npc._emotional_states[&"npc_1"] = 2
	var result: Variant = _manager._get_condition_value(
		_make_condition("npc_emotional_state", &"npc_1")
	)
	assert_int(int(result)).is_equal(2)


func test_condition_trust_level() -> void:
	_mock_trust._trust[&"npc_1"] = 75.0
	var result: Variant = _manager._get_condition_value(
		_make_condition("trust_level", &"npc_1")
	)
	assert_float(float(result)).is_equal(75.0)


func test_condition_suspicion_level() -> void:
	_mock_trust._suspicion[&"npc_1"] = 30.0
	var result: Variant = _manager._get_condition_value(
		_make_condition("suspicion_level", &"npc_1")
	)
	assert_float(float(result)).is_equal(30.0)


func test_condition_has_clue_true() -> void:
	_mock_db._clues[&"clue_a"] = true
	var result: Variant = _manager._get_condition_value(
		_make_condition("has_clue", &"clue_a")
	)
	assert_bool(bool(result)).is_true()


func test_condition_has_clue_false() -> void:
	var result: Variant = _manager._get_condition_value(
		_make_condition("has_clue", &"nonexistent")
	)
	assert_bool(bool(result)).is_false()


func test_condition_has_insight_true() -> void:
	_mock_db._insights[&"insight_1"] = true
	var result: Variant = _manager._get_condition_value(
		_make_condition("has_insight", &"insight_1")
	)
	assert_bool(bool(result)).is_true()


func test_condition_loop_state() -> void:
	_mock_lsm._state_values[&"key_1"] = "active"
	var result: Variant = _manager._get_condition_value(
		_make_condition("loop_state", &"key_1")
	)
	assert_str(str(result)).is_equal("active")


func test_condition_current_night() -> void:
	_mock_lsm.current_night = 3
	var result: Variant = _manager._get_condition_value(
		_make_condition("current_night")
	)
	assert_int(int(result)).is_equal(3)


func test_condition_current_phase() -> void:
	_mock_timer.current_phase = 2
	var result: Variant = _manager._get_condition_value(
		_make_condition("current_phase")
	)
	assert_int(int(result)).is_equal(2)


# ---------------------------------------------------------------------------
# Tests: Graceful Degradation
# ---------------------------------------------------------------------------


func test_trust_fallback_when_no_manager() -> void:
	_manager._test_trust = null
	var result: Variant = _manager._get_condition_value(
		_make_condition("trust_level", &"npc_1")
	)
	assert_float(float(result)).is_equal(50.0)


func test_suspicion_fallback_when_no_manager() -> void:
	_manager._test_trust = null
	var result: Variant = _manager._get_condition_value(
		_make_condition("suspicion_level", &"npc_1")
	)
	assert_float(float(result)).is_equal(0.0)


func test_npc_emotional_state_fallback() -> void:
	_manager._test_npc = null
	var result: Variant = _manager._get_condition_value(
		_make_condition("npc_emotional_state", &"npc_1")
	)
	assert_int(int(result)).is_equal(0)


func test_has_clue_fallback_when_no_db() -> void:
	_manager._test_db = null
	var result: Variant = _manager._get_condition_value(
		_make_condition("has_clue", &"clue_a")
	)
	assert_bool(bool(result)).is_false()


func test_current_night_fallback() -> void:
	_manager._test_lsm = null
	var result: Variant = _manager._get_condition_value(
		_make_condition("current_night")
	)
	assert_int(int(result)).is_equal(1)


func test_current_phase_fallback() -> void:
	_manager._test_timer = null
	var result: Variant = _manager._get_condition_value(
		_make_condition("current_phase")
	)
	assert_int(int(result)).is_equal(0)


# ---------------------------------------------------------------------------
# Tests: Node Condition Filtering
# ---------------------------------------------------------------------------


func test_start_node_with_condition_passes() -> void:
	_mock_trust._trust[&"npc_1"] = 80.0
	var tree := _make_tree([
		_make_node(&"start", "High trust!", true, &"", [], [
			_make_condition("trust_level", &"npc_1", "gte", 60.0),
		]),
	])
	var result: bool = _manager.start_dialogue(&"npc_1", tree)
	assert_bool(result).is_true()
	assert_str(String(_manager.get_current_node_id())).is_equal("start")


func test_start_node_condition_fails_falls_through() -> void:
	_mock_trust._trust[&"npc_1"] = 20.0
	var tree := _make_tree([
		_make_node(&"start", "High trust!", true, &"", [], [
			_make_condition("trust_level", &"npc_1", "gte", 60.0),
		]),
		_make_node(&"fallback", "Default greeting", false),
	])
	var result: bool = _manager.start_dialogue(&"npc_1", tree)
	assert_bool(result).is_true()
	assert_str(String(_manager.get_current_node_id())).is_equal("fallback")


func test_all_nodes_fail_uses_first_node() -> void:
	var tree := _make_tree([
		_make_node(&"n1", "First", true, &"", [], [
			_make_condition("trust_level", &"npc_1", "gte", 999.0),
		]),
	])
	var result: bool = _manager.start_dialogue(&"npc_1", tree)
	assert_bool(result).is_true()
	assert_str(String(_manager.get_current_node_id())).is_equal("n1")


# ---------------------------------------------------------------------------
# Tests: Choice Condition Filtering
# ---------------------------------------------------------------------------


func test_get_available_choices_filtered() -> void:
	_mock_trust._trust[&"npc_1"] = 30.0
	var tree := _make_tree([
		_make_node(&"start", "Pick:", true, &"", [
			_make_choice(&"c1", "Low", &"", [], [
				_make_condition("trust_level", &"npc_1", "lt", 50.0),
			]),
			_make_choice(&"c2", "High", &"", [], [
				_make_condition("trust_level", &"npc_1", "gte", 50.0),
			]),
		]),
	])
	_manager.start_dialogue(&"npc_1", tree)
	var visible: Array[Dictionary] = _manager.get_available_choices()
	assert_int(visible.size()).is_equal(1)
	assert_str(String(visible[0].get("id", &""))).is_equal("c1")


func test_get_available_choices_all_visible() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Pick:", true, &"", [
			_make_choice(&"c1", "A", &""),
			_make_choice(&"c2", "B", &""),
		]),
	])
	_manager.start_dialogue(&"npc_1", tree)
	var visible: Array[Dictionary] = _manager.get_available_choices()
	assert_int(visible.size()).is_equal(2)


func test_get_available_choices_not_active() -> void:
	var visible: Array[Dictionary] = _manager.get_available_choices()
	assert_int(visible.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Tests: Consequence Application
# ---------------------------------------------------------------------------


func test_consequence_modify_trust() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Pick:", true, &"", [
			_make_choice(&"c1", "Go", &"", [
				_make_consequence("modify_trust", &"npc_1", 10.0),
			]),
		]),
	])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.select_choice(&"c1")
	assert_int(_mock_trust._trust_deltas.size()).is_equal(1)
	assert_float(_mock_trust._trust_deltas[0]["delta"]).is_equal(10.0)


func test_consequence_modify_suspicion() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Pick:", true, &"", [
			_make_choice(&"c1", "Go", &"", [
				_make_consequence("modify_suspicion", &"npc_1", 15.0),
			]),
		]),
	])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.select_choice(&"c1")
	assert_int(_mock_trust._suspicion_deltas.size()).is_equal(1)
	assert_float(_mock_trust._suspicion_deltas[0]["delta"]).is_equal(15.0)


func test_consequence_change_emotional_state() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Pick:", true, &"", [
			_make_choice(&"c1", "Go", &"", [
				_make_consequence("change_emotional_state", &"npc_1", 3),
			]),
		]),
	])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.select_choice(&"c1")
	assert_int(_mock_npc._state_transitions.size()).is_equal(1)
	assert_int(_mock_npc._state_transitions[0]["state"]).is_equal(3)


func test_consequence_reveal_clue() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Pick:", true, &"", [
			_make_choice(&"c1", "Go", &"", [
				_make_consequence("reveal_clue", &"new_clue_1"),
			]),
		]),
	])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.select_choice(&"c1")
	assert_int(_mock_db._entries.size()).is_equal(1)
	assert_str(String(_mock_db._entries[0]["id"])).is_equal("new_clue_1")


func test_consequence_register_consequence() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Pick:", true, &"", [
			_make_choice(&"c1", "Go", &"", [
				_make_consequence("register_consequence", &"visited_attic", true),
			]),
		]),
	])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.select_choice(&"c1")
	assert_int(_mock_lsm._consequences.size()).is_equal(1)
	assert_str(String(_mock_lsm._consequences[0]["id"])).is_equal("visited_attic")


func test_consequence_trigger_event() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Pick:", true, &"", [
			_make_choice(&"c1", "Go", &"", [
				_make_consequence("trigger_event", &"alarm_triggered"),
			]),
		]),
	])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.select_choice(&"c1")
	assert_int(_mock_event._fired.size()).is_equal(1)
	assert_str(String(_mock_event._fired[0])).is_equal("alarm_triggered")


func test_consequence_modify_trust_no_manager() -> void:
	_manager._test_trust = null
	var tree := _make_tree([
		_make_node(&"start", "Pick:", true, &"", [
			_make_choice(&"c1", "Go", &"", [
				_make_consequence("modify_trust", &"npc_1", 10.0),
			]),
		]),
	])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.select_choice(&"c1")


func test_multiple_consequences() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Pick:", true, &"", [
			_make_choice(&"c1", "Go", &"", [
				_make_consequence("modify_trust", &"npc_1", 10.0),
				_make_consequence("modify_suspicion", &"npc_1", 5.0),
				_make_consequence("trigger_event", &"event_1"),
			]),
		]),
	])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.select_choice(&"c1")
	assert_int(_mock_trust._trust_deltas.size()).is_equal(1)
	assert_int(_mock_trust._suspicion_deltas.size()).is_equal(1)
	assert_int(_mock_event._fired.size()).is_equal(1)


# ---------------------------------------------------------------------------
# Tests: Multi-node Dialogue Path
# ---------------------------------------------------------------------------


func test_full_dialogue_branching_path() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Welcome", true, &"", [
			_make_choice(&"ask", "Ask", &"response_a"),
			_make_choice(&"leave", "Leave", &""),
		]),
		_make_node(&"response_a", "Answer", false, &"", [
			_make_choice(&"thanks", "Thanks", &""),
		]),
	])
	_manager.start_dialogue(&"npc_1", tree)
	assert_str(_manager.get_current_text()).is_equal("Welcome")
	assert_int(_node_displayed_events.size()).is_equal(1)

	_manager.select_choice(&"ask")
	assert_str(_manager.get_current_text()).is_equal("Answer")
	assert_int(_node_displayed_events.size()).is_equal(2)

	_manager.select_choice(&"thanks")
	assert_bool(_manager.is_active).is_false()
	assert_int(_node_displayed_events.size()).is_equal(2)


func test_linear_auto_advance_path() -> void:
	var tree := _make_tree([
		_make_node(&"start", "Line 1", true, &"mid"),
		_make_node(&"mid", "Line 2", false, &"end"),
		_make_node(&"end", "Line 3", false, &""),
	])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.advance()
	assert_str(_manager.get_current_text()).is_equal("Line 2")
	_manager.advance()
	assert_str(_manager.get_current_text()).is_equal("Line 3")
	_manager.advance()
	assert_bool(_manager.is_active).is_false()


# ---------------------------------------------------------------------------
# Tests: Reset and Serialize
# ---------------------------------------------------------------------------


func test_reset_clears_state() -> void:
	var tree := _make_tree([_make_node(&"start", "Hi", true)])
	_manager.start_dialogue(&"npc_1", tree)
	_manager.reset()
	assert_bool(_manager.is_active).is_false()
	assert_float(_mock_timer.time_scale).is_equal(1.0)


func test_serialize_returns_data() -> void:
	var data: Dictionary = _manager.serialize()
	assert_bool(data.has("is_active")).is_true()


func test_get_current_text_not_active() -> void:
	assert_str(_manager.get_current_text()).is_equal("")


func test_get_current_node_id_not_active() -> void:
	assert_str(String(_manager.get_current_node_id())).is_equal("")
