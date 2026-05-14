extends GdUnitTestSuite

## Tests for NotebookManager — notebook viewer, search, board state, connections.
## Covers GDD acceptance criteria from design/gdd/notebook-system.md.

const NM_SCRIPT := "res://src/feature/notebook_manager.gd"

var _manager: Node
var _mock_db: Node
var _mock_ccm: Node
var _mock_timer: Node
var _mock_bus: Node
var _mock_dialogue: Node

var _opened_count: int
var _closed_count: int
var _board_updated_count: int
var _selected_events: Array[StringName]
var _deselected_count: int
var _connection_events: Array[Dictionary]


func before_test() -> void:
	_mock_db = Node.new()
	_mock_db.name = "ClueDatabase"
	_mock_db.set_script(_create_db_mock())
	add_child(_mock_db)

	_mock_ccm = Node.new()
	_mock_ccm.name = "ClueConnectionManager"
	_mock_ccm.set_script(_create_ccm_mock())
	add_child(_mock_ccm)

	_mock_timer = Node.new()
	_mock_timer.name = "TimerService"
	_mock_timer.set_script(_create_timer_mock())
	add_child(_mock_timer)

	_mock_bus = Node.new()
	_mock_bus.name = "InteractionBus"
	_mock_bus.set_script(_create_bus_mock())
	add_child(_mock_bus)

	_mock_dialogue = Node.new()
	_mock_dialogue.name = "DialogueManager"
	_mock_dialogue.set_script(_create_dialogue_mock())
	add_child(_mock_dialogue)

	var wrapper := GDScript.new()
	wrapper.source_code = (
		"extends \"%s\"\n" % NM_SCRIPT
		+ "var _test_db: Node = null\n"
		+ "var _test_ccm: Node = null\n"
		+ "var _test_timer: Node = null\n"
		+ "var _test_bus: Node = null\n"
		+ "var _test_dialogue: Node = null\n"
		+ "func _get_clue_database() -> Node:\n"
		+ "\treturn _test_db\n"
		+ "func _get_connection_manager() -> Node:\n"
		+ "\treturn _test_ccm\n"
		+ "func _get_timer_service() -> Node:\n"
		+ "\treturn _test_timer\n"
		+ "func _get_interaction_bus() -> Node:\n"
		+ "\treturn _test_bus\n"
		+ "func _get_dialogue_manager() -> Node:\n"
		+ "\treturn _test_dialogue\n"
	)
	wrapper.reload()

	_manager = Node.new()
	_manager.set_script(wrapper)
	_manager._test_db = _mock_db
	_manager._test_ccm = _mock_ccm
	_manager._test_timer = _mock_timer
	_manager._test_bus = _mock_bus
	_manager._test_dialogue = _mock_dialogue
	_manager.name = "NotebookManagerTest"
	add_child(_manager)

	_opened_count = 0
	_closed_count = 0
	_board_updated_count = 0
	_selected_events = []
	_deselected_count = 0
	_connection_events = []

	_manager.notebook_opened.connect(func(): _opened_count += 1)
	_manager.notebook_closed.connect(func(): _closed_count += 1)
	_manager.board_updated.connect(func(): _board_updated_count += 1)
	_manager.entry_selected.connect(func(id): _selected_events.append(id))
	_manager.entry_deselected.connect(func(): _deselected_count += 1)
	_manager.connection_attempted.connect(func(a, b, s): _connection_events.append({"a": a, "b": b, "s": s}))


func after_test() -> void:
	if _manager:
		_manager.queue_free()
	for mock in [_mock_db, _mock_ccm, _mock_timer, _mock_bus, _mock_dialogue]:
		if mock:
			mock.queue_free()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _make_clue(id: StringName, title: String, desc: String, night: int = 1, npc: StringName = &"", tags: Array = []) -> Dictionary:
	return {
		"id": id,
		"entry_type": 0,
		"title": title,
		"description": desc,
		"source": &"test",
		"discovered_at_night": night,
		"npc_affinity": npc,
		"tags": tags,
		"contextual_unlocks": [],
		"metadata": {},
	}


func _make_insight(id: StringName, title: String, desc: String, source_clues: Array, night: int = 1, reinterpretation: String = "", npc: StringName = &"") -> Dictionary:
	return {
		"id": id,
		"entry_type": 1,
		"title": title,
		"description": desc,
		"source": &"connection",
		"discovered_at_night": night,
		"npc_affinity": npc,
		"tags": [],
		"contextual_unlocks": [],
		"metadata": {},
		"source_clues": source_clues,
		"reinterpretation": reinterpretation,
	}


func _add_clue(id: StringName, title: String, desc: String, night: int = 1, npc: StringName = &"", tags: Array = []) -> void:
	_mock_db.entries[id] = _make_clue(id, title, desc, night, npc, tags)


func _add_insight(id: StringName, title: String, desc: String, source_clues: Array, night: int = 1, reinterpretation: String = "", npc: StringName = &"") -> void:
	_mock_db.entries[id] = _make_insight(id, title, desc, source_clues, night, reinterpretation, npc)


func _add_connection(a: StringName, b: StringName, is_valid: bool, insight_id: StringName = &"") -> void:
	_mock_db.connections.append({
		"clue_a": a,
		"clue_b": b,
		"made_at_night": 1,
		"is_valid": is_valid,
		"insight_id": insight_id,
	})


# ---------------------------------------------------------------------------
# Open / Close — AC 12, 13, 14, 15
# ---------------------------------------------------------------------------


func test_open_notebook_sets_is_open() -> void:
	var result := _manager.open_notebook()
	assert_true(result)
	assert_true(_manager.is_open)


func test_open_notebook_pauses_timer() -> void:
	_mock_timer.time_scale = 1.0
	_manager.open_notebook()
	assert_eq(_mock_timer.time_scale, 0.0)


func test_open_notebook_disables_interaction_bus() -> void:
	assert_true(_mock_bus.is_accepting)
	_manager.open_notebook()
	assert_false(_mock_bus.is_accepting)


func test_open_notebook_blocks_during_dialogue() -> void:
	_mock_dialogue.is_active = true
	var result := _manager.open_notebook()
	assert_false(result)
	assert_false(_manager.is_open)


func test_open_notebook_returns_false_if_already_open() -> void:
	_manager.open_notebook()
	var result := _manager.open_notebook()
	assert_false(result)


func test_open_notebook_emits_signal() -> void:
	_manager.open_notebook()
	assert_eq(_opened_count, 1)


func test_close_notebook_restores_timer_scale() -> void:
	_mock_timer.time_scale = 0.75
	_manager.open_notebook()
	assert_eq(_mock_timer.time_scale, 0.0)
	_manager.close_notebook()
	assert_eq(_mock_timer.time_scale, 0.75)


func test_close_notebook_reenables_interaction_bus() -> void:
	_manager.open_notebook()
	assert_false(_mock_bus.is_accepting)
	_manager.close_notebook()
	assert_true(_mock_bus.is_accepting)


func test_close_notebook_clears_selection() -> void:
	_add_clue(&"c1", "Clue 1", "desc")
	_manager.select_entry(&"c1")
	_manager.open_notebook()
	_manager.close_notebook()
	assert_eq(_manager.get_selected().size(), 0)


func test_close_notebook_emits_signal() -> void:
	_manager.open_notebook()
	_manager.close_notebook()
	assert_eq(_closed_count, 1)


func test_close_notebook_noop_if_not_open() -> void:
	_manager.close_notebook()
	assert_eq(_closed_count, 0)


# ---------------------------------------------------------------------------
# Search — AC 5
# ---------------------------------------------------------------------------


func test_search_entries_title_match() -> void:
	_add_clue(&"c1", "Broken Lantern", "A shattered light")
	_add_clue(&"c2", "Old Letter", "A faded note")
	var result := _manager.search_entries("Lantern")
	assert_eq(result.size(), 1)
	assert_eq(result[0], &"c1")


func test_search_entries_description_match() -> void:
	_add_clue(&"c1", "Dark Hallway", "The lantern was broken here")
	_add_clue(&"c2", "Old Letter", "A faded note")
	var result := _manager.search_entries("lantern")
	assert_eq(result.size(), 1)
	assert_eq(result[0], &"c1")


func test_search_entries_tag_match() -> void:
	_add_clue(&"c1", "Item", "Something", 1, &"", [&"evidence", &"lantern"])
	_add_clue(&"c2", "Note", "Something else", 1, &"", [&"letter"])
	var result := _manager.search_entries("lantern")
	assert_eq(result.size(), 1)
	assert_eq(result[0], &"c1")


func test_search_entries_scores_title_higher() -> void:
	_add_clue(&"c1", "Lantern Shard", "A piece")
	_add_clue(&"c2", "Dark Corner", "The lantern was here")
	var result := _manager.search_entries("Lantern")
	assert_eq(result.size(), 2)
	assert_eq(result[0], &"c1")


func test_search_empty_query_returns_all() -> void:
	_add_clue(&"c1", "Clue 1", "desc 1")
	_add_clue(&"c2", "Clue 2", "desc 2")
	var result := _manager.search_entries("")
	assert_eq(result.size(), 2)


func test_search_no_results_returns_empty() -> void:
	_add_clue(&"c1", "Clue 1", "desc 1")
	var result := _manager.search_entries("xyz")
	assert_eq(result.size(), 0)


func test_search_case_insensitive() -> void:
	_add_clue(&"c1", "Broken Lantern", "desc")
	var result := _manager.search_entries("lantern")
	assert_eq(result.size(), 1)


# ---------------------------------------------------------------------------
# Filter — AC 6
# ---------------------------------------------------------------------------


func test_filter_by_tag() -> void:
	_add_clue(&"c1", "A", "a", 1, &"", [&"evidence"])
	_add_clue(&"c2", "B", "b", 1, &"", [&"letter"])
	var result := _manager.filter_by_tag(&"evidence")
	assert_eq(result.size(), 1)
	assert_eq(result[0], &"c1")


func test_filter_by_npc() -> void:
	_add_clue(&"c1", "A", "a", 1, &"guest_indigo")
	_add_clue(&"c2", "B", "b", 1, &"guest_jade")
	var result := _manager.filter_by_npc(&"guest_indigo")
	assert_eq(result.size(), 1)
	assert_eq(result[0], &"c1")


func test_filter_by_type_clue() -> void:
	_add_clue(&"c1", "Clue", "c")
	_add_insight(&"i1", "Insight", "i", [&"c1"])
	var result := _manager.filter_by_type(0)
	assert_eq(result.size(), 1)
	assert_eq(result[0], &"c1")


func test_filter_by_type_insight() -> void:
	_add_clue(&"c1", "Clue", "c")
	_add_insight(&"i1", "Insight", "i", [&"c1"])
	var result := _manager.filter_by_type(1)
	assert_eq(result.size(), 1)
	assert_eq(result[0], &"i1")


func test_filter_by_night() -> void:
	_add_clue(&"c1", "A", "a", 1)
	_add_clue(&"c2", "B", "b", 2)
	var result := _manager.filter_by_night(2)
	assert_eq(result.size(), 1)
	assert_eq(result[0], &"c2")


func test_get_all_visible() -> void:
	_add_clue(&"c1", "A", "a")
	_add_clue(&"c2", "B", "b")
	var result := _manager.get_all_visible()
	assert_eq(result.size(), 2)


# ---------------------------------------------------------------------------
# Detail View — AC 7
# ---------------------------------------------------------------------------


func test_get_entry_detail_basic() -> void:
	_add_clue(&"c1", "Lantern", "A broken light")
	var detail := _manager.get_entry_detail(&"c1")
	assert_false(detail.is_empty())
	assert_eq(detail["entry"]["title"], "Lantern")


func test_get_entry_detail_with_contextual_unlocks() -> void:
	_add_clue(&"c1", "Lantern", "Broken")
	_add_clue(&"c2", "Letter", "Old")
	_add_insight(&"i1", "Lantern Lie", "The lantern was moved", [&"c1", &"c2"], 2, "It was staged")
	_mock_db.entries[&"c1"]["contextual_unlocks"] = [&"i1"]

	var detail := _manager.get_entry_detail(&"c1")
	var unlocks: Array = detail["contextual_unlocks"]
	assert_eq(unlocks.size(), 1)
	assert_eq(unlocks[0]["title"], "Lantern Lie")
	assert_eq(unlocks[0]["reinterpretation"], "It was staged")


func test_get_entry_detail_unlocks_sorted_by_night() -> void:
	_add_clue(&"c1", "A", "a")
	_add_clue(&"c2", "B", "b")
	_add_insight(&"i2", "Late Insight", "Late", [&"c1", &"c2"], 3)
	_add_insight(&"i1", "Early Insight", "Early", [&"c1", &"c2"], 1)
	_mock_db.entries[&"c1"]["contextual_unlocks"] = [&"i2", &"i1"]

	var detail := _manager.get_entry_detail(&"c1")
	var unlocks: Array = detail["contextual_unlocks"]
	assert_eq(unlocks[0]["insight_id"], &"i1")
	assert_eq(unlocks[1]["insight_id"], &"i2")


func test_get_entry_detail_no_unlocks() -> void:
	_add_clue(&"c1", "Lantern", "Broken")
	var detail := _manager.get_entry_detail(&"c1")
	var unlocks: Array = detail["contextual_unlocks"]
	assert_eq(unlocks.size(), 0)


func test_get_entry_detail_includes_connections() -> void:
	_add_clue(&"c1", "A", "a")
	_add_clue(&"c2", "B", "b")
	_add_connection(&"c1", &"c2", true)
	var detail := _manager.get_entry_detail(&"c1")
	var connections: Array = detail["connections"]
	assert_eq(connections.size(), 1)


func test_get_entry_detail_nonexistent() -> void:
	var detail := _manager.get_entry_detail(&"nonexistent")
	assert_true(detail.is_empty())


# ---------------------------------------------------------------------------
# Board Nodes — AC 1, 2, 4
# ---------------------------------------------------------------------------


func test_get_board_nodes_returns_all_entries() -> void:
	_add_clue(&"c1", "A", "a")
	_add_insight(&"i1", "I", "i", [&"c1"])
	var nodes := _manager.get_board_nodes()
	assert_eq(nodes.size(), 2)


func test_get_board_nodes_clue_size() -> void:
	_add_clue(&"c1", "A", "a")
	var nodes := _manager.get_board_nodes()
	assert_eq(nodes[0]["size"], 32.0)


func test_get_board_nodes_insight_size_larger() -> void:
	_add_clue(&"c1", "A", "a")
	_add_insight(&"i1", "I", "i", [&"c1"])
	var nodes := _manager.get_board_nodes()
	var insight_node: Dictionary = {}
	for n: Dictionary in nodes:
		if n["entry_type"] == 1:
			insight_node = n
	assert_eq(insight_node["size"], 40.0)


func test_get_board_nodes_npc_color_indigo() -> void:
	_add_clue(&"c1", "A", "a", 1, &"guest_indigo")
	var nodes := _manager.get_board_nodes()
	assert_eq(nodes[0]["color"], Color(0.247, 0.318, 0.710))


func test_get_board_nodes_npc_color_global() -> void:
	_add_clue(&"c1", "A", "a", 1, &"")
	var nodes := _manager.get_board_nodes()
	assert_eq(nodes[0]["color"], Color(0.8, 0.7, 0.6))


func test_get_board_nodes_selected_state() -> void:
	_add_clue(&"c1", "A", "a")
	_manager.select_entry(&"c1")
	var nodes := _manager.get_board_nodes()
	assert_eq(nodes[0]["state"], "selected")


func test_get_board_nodes_normal_state() -> void:
	_add_clue(&"c1", "A", "a")
	var nodes := _manager.get_board_nodes()
	assert_eq(nodes[0]["state"], "normal")


func test_get_board_nodes_position_persisted() -> void:
	_add_clue(&"c1", "A", "a")
	_manager.update_node_position(&"c1", 100.0, 200.0)
	var nodes := _manager.get_board_nodes()
	assert_eq(nodes[0]["position"], Vector2(100.0, 200.0))


func test_get_board_nodes_empty_no_crash() -> void:
	var nodes := _manager.get_board_nodes()
	assert_eq(nodes.size(), 0)


func test_update_node_position_persists() -> void:
	_manager.update_node_position(&"c1", 50.0, 75.0)
	assert_eq(_manager._node_positions[&"c1"], Vector2(50.0, 75.0))


# ---------------------------------------------------------------------------
# Board Edges — AC 3
# ---------------------------------------------------------------------------


func test_get_board_edges_valid_gold_color() -> void:
	_add_clue(&"c1", "A", "a")
	_add_clue(&"c2", "B", "b")
	_add_connection(&"c1", &"c2", true)
	var edges := _manager.get_board_edges()
	assert_eq(edges.size(), 1)
	assert_true(edges[0]["is_valid"])
	var c: Color = edges[0]["color"]
	assert_eq(c.r, 0.8)
	assert_eq(c.g, 0.467)
	assert_eq(c.b, 0.133)


func test_get_board_edges_invalid_gray_color() -> void:
	_add_clue(&"c1", "A", "a")
	_add_clue(&"c2", "B", "b")
	_add_connection(&"c1", &"c2", false)
	var edges := _manager.get_board_edges()
	assert_eq(edges.size(), 1)
	assert_false(edges[0]["is_valid"])
	var c: Color = edges[0]["color"]
	assert_eq(c.r, 0.5)
	assert_eq(c.g, 0.5)
	assert_eq(c.b, 0.5)
	assert_eq(c.a, 0.3)


func test_get_board_edges_valid_width() -> void:
	_add_clue(&"c1", "A", "a")
	_add_clue(&"c2", "B", "b")
	_add_connection(&"c1", &"c2", true)
	var edges := _manager.get_board_edges()
	assert_eq(edges[0]["width"], 2.0)


func test_get_board_edges_invalid_width() -> void:
	_add_clue(&"c1", "A", "a")
	_add_clue(&"c2", "B", "b")
	_add_connection(&"c1", &"c2", false)
	var edges := _manager.get_board_edges()
	assert_eq(edges[0]["width"], 1.0)


func test_get_board_edges_empty() -> void:
	var edges := _manager.get_board_edges()
	assert_eq(edges.size(), 0)


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------


func test_select_entry_adds_to_selected() -> void:
	_manager.select_entry(&"c1")
	assert_eq(_manager.get_selected().size(), 1)
	assert_eq(_manager.get_selected()[0], &"c1")


func test_select_entry_emits_signal() -> void:
	_manager.select_entry(&"c1")
	assert_eq(_selected_events.size(), 1)
	assert_eq(_selected_events[0], &"c1")


func test_select_entry_no_duplicate() -> void:
	_manager.select_entry(&"c1")
	_manager.select_entry(&"c1")
	assert_eq(_manager.get_selected().size(), 1)


func test_select_multiple_entries() -> void:
	_manager.select_entry(&"c1")
	_manager.select_entry(&"c2")
	assert_eq(_manager.get_selected().size(), 2)


func test_deselect_all() -> void:
	_manager.select_entry(&"c1")
	_manager.deselect_all()
	assert_eq(_manager.get_selected().size(), 0)
	assert_eq(_deselected_count, 1)


# ---------------------------------------------------------------------------
# Connection Delegation — AC 8
# ---------------------------------------------------------------------------


func test_request_connection_delegates_to_ccm() -> void:
	_mock_ccm._next_result = {"ok": true, "reason": "", "is_valid": true, "insight_id": &"i1"}
	var result := _manager.request_connection(&"c1", &"c2")
	assert_true(result["ok"])
	assert_eq(_mock_ccm._last_clue_a, &"c1")
	assert_eq(_mock_ccm._last_clue_b, &"c2")


func test_request_connection_emits_attempted() -> void:
	_mock_ccm._next_result = {"ok": true, "reason": "", "is_valid": false, "insight_id": &""}
	_manager.request_connection(&"c1", &"c2")
	assert_eq(_connection_events.size(), 1)
	assert_true(_connection_events[0]["s"])


func test_request_connection_ccm_unavailable() -> void:
	_manager._test_ccm = null
	var result := _manager.request_connection(&"c1", &"c2")
	assert_false(result["ok"])
	assert_eq(_connection_events.size(), 1)
	assert_false(_connection_events[0]["s"])


func test_request_connection_duplicate_rejected() -> void:
	_mock_ccm._next_result = {"ok": false, "reason": "duplicate", "is_valid": false, "insight_id": &""}
	var result := _manager.request_connection(&"c1", &"c2")
	assert_false(result["ok"])
	assert_eq(result["reason"], "duplicate")


# ---------------------------------------------------------------------------
# Signal-driven Board Updates — AC 16, 17
# ---------------------------------------------------------------------------


func test_clue_discovered_signal_updates_board() -> void:
	_manager.open_notebook()
	var prev_count := _board_updated_count
	_mock_db.clue_discovered.emit(&"c_new")
	assert_gt(_board_updated_count, prev_count)


func test_insight_generated_signal_updates_board() -> void:
	_manager.open_notebook()
	var prev_count := _board_updated_count
	_mock_db.insight_generated.emit(&"i_new")
	assert_gt(_board_updated_count, prev_count)


func test_connection_made_signal_updates_board() -> void:
	_manager.open_notebook()
	var prev_count := _board_updated_count
	_mock_db.connection_made.emit(&"c1", &"c2", true)
	assert_gt(_board_updated_count, prev_count)


func test_signal_does_not_update_closed_notebook() -> void:
	var prev_count := _board_updated_count
	_mock_db.clue_discovered.emit(&"c_new")
	assert_eq(_board_updated_count, prev_count)


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------


func test_serialize_deserialize_node_positions() -> void:
	_manager.update_node_position(&"c1", 100.0, 200.0)
	_manager.update_node_position(&"c2", 300.0, 400.0)

	var data := _manager.serialize()
	_manager._node_positions.clear()
	_manager.deserialize(data)

	assert_eq(_manager._node_positions[&"c1"], Vector2(100.0, 200.0))
	assert_eq(_manager._node_positions[&"c2"], Vector2(300.0, 400.0))


func test_serialize_empty_positions() -> void:
	var data := _manager.serialize()
	assert_true(data["node_positions"].is_empty())


func test_deserialize_empty_data() -> void:
	var result := _manager.deserialize({})
	assert_true(result)


# ---------------------------------------------------------------------------
# Reset
# ---------------------------------------------------------------------------


func test_reset_clears_state() -> void:
	_manager.open_notebook()
	_manager.select_entry(&"c1")
	_manager.update_node_position(&"c1", 50.0, 75.0)
	_manager.reset()
	assert_false(_manager.is_open)
	assert_eq(_manager.get_selected().size(), 0)
	assert_true(_manager._node_positions.is_empty())


# ---------------------------------------------------------------------------
# Database Unavailable — Edge case
# ---------------------------------------------------------------------------


func test_operations_with_no_database() -> void:
	_manager._test_db = null
	assert_eq(_manager.search_entries("test").size(), 0)
	assert_eq(_manager.filter_by_tag(&"x").size(), 0)
	assert_eq(_manager.filter_by_npc(&"x").size(), 0)
	assert_eq(_manager.filter_by_type(0).size(), 0)
	assert_eq(_manager.filter_by_night(1).size(), 0)
	assert_eq(_manager.get_all_visible().size(), 0)
	assert_true(_manager.get_entry_detail(&"c1").is_empty())
	assert_eq(_manager.get_board_nodes().size(), 0)
	assert_eq(_manager.get_board_edges().size(), 0)


# ---------------------------------------------------------------------------
# NPC Color Map — AC 4 full coverage
# ---------------------------------------------------------------------------


func test_node_color_vermillion() -> void:
	_add_clue(&"c1", "A", "a", 1, &"guest_vermillion")
	var nodes := _manager.get_board_nodes()
	assert_eq(nodes[0]["color"], Color(0.827, 0.255, 0.212))


func test_node_color_jade() -> void:
	_add_clue(&"c1", "A", "a", 1, &"guest_jade")
	var nodes := _manager.get_board_nodes()
	assert_eq(nodes[0]["color"], Color(0.180, 0.545, 0.341))


func test_node_color_amber() -> void:
	_add_clue(&"c1", "A", "a", 1, &"guest_amber")
	var nodes := _manager.get_board_nodes()
	assert_eq(nodes[0]["color"], Color(0.878, 0.678, 0.157))


func test_node_color_azure() -> void:
	_add_clue(&"c1", "A", "a", 1, &"guest_azure")
	var nodes := _manager.get_board_nodes()
	assert_eq(nodes[0]["color"], Color(0.255, 0.627, 0.843))


func test_node_color_unknown_npc_uses_global() -> void:
	_add_clue(&"c1", "A", "a", 1, &"some_unknown_npc")
	var nodes := _manager.get_board_nodes()
	assert_eq(nodes[0]["color"], Color(0.8, 0.7, 0.6))


# ---------------------------------------------------------------------------
# Mock Scripts
# ---------------------------------------------------------------------------


func _create_db_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal clue_discovered(clue_id: StringName)\n"
		+ "signal insight_generated(insight_id: StringName)\n"
		+ "signal connection_made(clue_a: StringName, clue_b: StringName, is_valid: bool)\n"
		+ "var entries: Dictionary = {}\n"
		+ "var connections: Array[Dictionary] = []\n"
		+ "func get_entry(id: StringName) -> Dictionary:\n"
		+ "\treturn entries.get(id, {})\n"
		+ "func search_by_tag(tag: StringName) -> Array[StringName]:\n"
		+ "\tvar result: Array[StringName] = []\n"
		+ "\tfor id: StringName in entries:\n"
		+ "\t\tif tag in entries[id].get(\"tags\", []):\n"
		+ "\t\t\tresult.append(id)\n"
		+ "\treturn result\n"
		+ "func search_by_npc(npc: StringName) -> Array[StringName]:\n"
		+ "\tvar result: Array[StringName] = []\n"
		+ "\tfor id: StringName in entries:\n"
		+ "\t\tif entries[id].get(\"npc_affinity\", &\"\") == npc:\n"
		+ "\t\t\tresult.append(id)\n"
		+ "\treturn result\n"
		+ "func get_all_clues() -> Array[StringName]:\n"
		+ "\tvar result: Array[StringName] = []\n"
		+ "\tfor id: StringName in entries:\n"
		+ "\t\tif entries[id][\"entry_type\"] == 0:\n"
		+ "\t\t\tresult.append(id)\n"
		+ "\treturn result\n"
		+ "func get_all_insights() -> Array[StringName]:\n"
		+ "\tvar result: Array[StringName] = []\n"
		+ "\tfor id: StringName in entries:\n"
		+ "\t\tif entries[id][\"entry_type\"] == 1:\n"
		+ "\t\t\tresult.append(id)\n"
		+ "\treturn result\n"
		+ "func get_contextual_unlocks(clue_id: StringName) -> Array[StringName]:\n"
		+ "\tif not entries.has(clue_id):\n"
		+ "\t\treturn []\n"
		+ "\tvar result: Array[StringName] = []\n"
		+ "\tfor uid in entries[clue_id].get(\"contextual_unlocks\", []):\n"
		+ "\t\tresult.append(uid)\n"
		+ "\treturn result\n"
		+ "func get_connections_for(clue_id: StringName) -> Array[Dictionary]:\n"
		+ "\tvar result: Array[Dictionary] = []\n"
		+ "\tfor c: Dictionary in connections:\n"
		+ "\t\tif c[\"clue_a\"] == clue_id or c[\"clue_b\"] == clue_id:\n"
		+ "\t\t\tresult.append(c)\n"
		+ "\treturn result\n"
		+ "func get_valid_connections() -> Array[Dictionary]:\n"
		+ "\tvar result: Array[Dictionary] = []\n"
		+ "\tfor c: Dictionary in connections:\n"
		+ "\t\tif c[\"is_valid\"]:\n"
		+ "\t\t\tresult.append(c)\n"
		+ "\treturn result\n"
		+ "func has_clue(id: StringName) -> bool:\n"
		+ "\treturn entries.has(id) and entries[id][\"entry_type\"] == 0\n"
		+ "func has_insight(id: StringName) -> bool:\n"
		+ "\treturn entries.has(id) and entries[id][\"entry_type\"] == 1\n"
	)
	script.reload()
	return script


func _create_ccm_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var _next_result: Dictionary = {\"ok\": false, \"reason\": \"\", \"is_valid\": false, \"insight_id\": &\"\"}\n"
		+ "var _last_clue_a: StringName = &\"\"\n"
		+ "var _last_clue_b: StringName = &\"\"\n"
		+ "func request_connection(a: StringName, b: StringName) -> Dictionary:\n"
		+ "\t_last_clue_a = a\n"
		+ "\t_last_clue_b = b\n"
		+ "\treturn _next_result\n"
	)
	script.reload()
	return script


func _create_timer_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var time_scale: float = 1.0\n"
		+ "func set_time_scale(s: float) -> void:\n"
		+ "\ttime_scale = s\n"
	)
	script.reload()
	return script


func _create_bus_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var is_accepting: bool = true\n"
		+ "func set_accepting(value: bool) -> void:\n"
		+ "\tis_accepting = value\n"
	)
	script.reload()
	return script


func _create_dialogue_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "var is_active: bool = false\n"
	)
	script.reload()
	return script
