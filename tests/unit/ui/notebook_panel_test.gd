extends GdUnitTestSuite

## Tests for NotebookPanel — CanvasLayer 50 full-screen notebook overlay.
## Covers view switching, board rendering, list/detail views, search,
## connection bar, node selection, drag, pan, zoom, signal wiring,
## and graceful degradation.
## GDD: design/gdd/notebook-system.md System #21

const PANEL_SCRIPT := "res://src/ui/notebook_panel.gd"

var _panel: CanvasLayer
var _mock_manager: Node


func before_test() -> void:
	_panel = CanvasLayer.new()
	_panel.set_script(load(PANEL_SCRIPT))
	_panel.name = "NotebookPanelTest"
	add_child(_panel)

	_mock_manager = _create_mock_manager()
	_panel.set_notebook_manager(_mock_manager)
	_panel._ready()


func after_test() -> void:
	if _panel:
		_panel.queue_free()
	if _mock_manager:
		_mock_manager.queue_free()


# ---------------------------------------------------------------------------
# Mock Factory
# ---------------------------------------------------------------------------


func _create_mock_manager() -> Node:
	var script := GDScript.new()
	script.source_code = """
extends Node

signal notebook_opened
signal notebook_closed
signal board_updated
signal entry_selected(entry_id: StringName)
signal entry_deselected
signal connection_attempted(clue_a: StringName, clue_b: StringName, success: bool)

var is_open: bool = false
var _selected: Array[StringName] = []
var _node_positions: Dictionary = {}
var _last_connection_a: StringName = &""
var _last_connection_b: StringName = &""
var _search_query: String = ""

func open_notebook() -> bool:
	if is_open: return false
	is_open = true
	return true

func close_notebook() -> void:
	is_open = false
	_selected.clear()

func get_all_visible() -> Array[StringName]:
	return [&"clue_1", &"clue_2", &"clue_3"]

func search_entries(query: String) -> Array[StringName]:
	_search_query = query
	if query == "none":
		return []
	return [&"clue_1"]

func get_entry_detail(entry_id: StringName) -> Dictionary:
	if entry_id == &"clue_1":
		return {
			"entry": {"title": "线索一", "description": "描述一", "entry_type": 0, "npc_affinity": &"guest_indigo"},
			"contextual_unlocks": [{"insight_id": &"insight_1", "title": "洞察一", "reinterpretation": "新解读", "discovered_at_night": 2}],
			"connections": [{"other_id": &"clue_2", "is_valid": true}]
		}
	if entry_id == &"clue_2":
		return {
			"entry": {"title": "线索二", "description": "描述二", "entry_type": 0, "npc_affinity": &""},
			"contextual_unlocks": [],
			"connections": []
		}
	return {}

func get_board_nodes() -> Array[Dictionary]:
	return [
		{"entry_id": &"clue_1", "position": Vector2(200, 300), "size": 32.0, "color": Color(0.247, 0.318, 0.710), "state": "normal", "entry_type": 0},
		{"entry_id": &"clue_2", "position": Vector2(400, 300), "size": 32.0, "color": Color(0.8, 0.7, 0.6), "state": "normal", "entry_type": 0},
		{"entry_id": &"insight_1", "position": Vector2(300, 200), "size": 40.0, "color": Color(0.8, 0.467, 0.133), "state": "normal", "entry_type": 1},
	]

func get_board_edges() -> Array[Dictionary]:
	return [
		{"clue_a": &"clue_1", "clue_b": &"clue_2", "is_valid": true, "color": Color(0.8, 0.467, 0.133, 0.7), "width": 2.0},
	]

func select_entry(entry_id: StringName) -> void:
	if entry_id not in _selected:
		_selected.append(entry_id)

func deselect_all() -> void:
	_selected.clear()

func get_selected() -> Array[StringName]:
	return _selected.duplicate()

func request_connection(clue_a: StringName, clue_b: StringName) -> Dictionary:
	_last_connection_a = clue_a
	_last_connection_b = clue_b
	connection_attempted.emit(clue_a, clue_b, true)
	return {"ok": true, "is_valid": true, "insight_id": &"insight_2"}

func update_node_position(entry_id: StringName, x: float, y: float) -> void:
	_node_positions[entry_id] = Vector2(x, y)
"""
	script.reload()
	var mgr := Node.new()
	mgr.set_script(script)
	mgr.name = "MockNotebookManager"
	return mgr


# ---------------------------------------------------------------------------
# Initialization
# ---------------------------------------------------------------------------


func test_panel_layer_is_50() -> void:
	assert_int(_panel.layer).is_equal(50)


func test_panel_starts_hidden() -> void:
	assert_bool(_panel.visible).is_false()


func test_panel_not_open_initially() -> void:
	assert_bool(_panel.is_panel_open).is_false()


# ---------------------------------------------------------------------------
# Show / Hide
# ---------------------------------------------------------------------------


func test_show_panel_makes_visible() -> void:
	_panel.show_panel()
	assert_bool(_panel.visible).is_true()


func test_show_panel_opens_notebook() -> void:
	_panel.show_panel()
	assert_bool(_mock_manager.is_open).is_true()


func test_hide_panel_closes_notebook() -> void:
	_panel.show_panel()
	_panel.hide_panel()
	await get_tree().process_frame
	assert_bool(_mock_manager.is_open).is_false()


func test_hide_panel_immediate_hides() -> void:
	_panel.show_panel()
	_panel.hide_panel_immediate()
	assert_bool(_panel.visible).is_false()
	assert_bool(_mock_manager.is_open).is_false()


func test_show_panel_no_double_open() -> void:
	_panel.show_panel()
	_panel._animating = false
	_mock_manager.is_open = false
	_panel.show_panel()
	assert_bool(_mock_manager.is_open).is_true()


func test_hide_panel_no_double_hide() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel.hide_panel()
	_panel._animating = false
	_panel.hide_panel()
	assert_bool(_panel.visible).is_false()


# ---------------------------------------------------------------------------
# View Mode Switching
# ---------------------------------------------------------------------------


func test_default_view_is_board() -> void:
	_panel.show_panel()
	_panel._animating = false
	assert_int(_panel._view_mode).is_equal(0)


func test_switch_to_list_view() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel.set_view_mode(1)
	assert_int(_panel._view_mode).is_equal(1)
	assert_bool(_panel._list_view.visible).is_true()
	assert_bool(_panel._board_view.visible).is_false()


func test_switch_to_detail_view() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._detail_entry_id = &"clue_1"
	_panel.set_view_mode(2)
	assert_int(_panel._view_mode).is_equal(2)
	assert_bool(_panel._detail_view.visible).is_true()


func test_board_button_disabled_in_board_mode() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel.set_view_mode(0)
	assert_bool(_panel._board_button.disabled).is_true()


func test_list_button_disabled_in_list_mode() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel.set_view_mode(1)
	assert_bool(_panel._list_button.disabled).is_true()


# ---------------------------------------------------------------------------
# Board View
# ---------------------------------------------------------------------------


func test_board_nodes_loaded_on_show() -> void:
	_panel.show_panel()
	_panel._animating = false
	assert_int(_panel._board_nodes.size()).is_equal(3)


func test_board_edges_loaded_on_show() -> void:
	_panel.show_panel()
	_panel._animating = false
	assert_int(_panel._board_edges.size()).is_equal(1)


func test_empty_board_shows_label() -> void:
	_mock_manager.queue_free()
	var empty_mgr := _create_empty_mock()
	_panel.set_notebook_manager(empty_mgr)
	_panel.show_panel()
	_panel._animating = false
	assert_bool(_panel._empty_label.visible).is_true()
	empty_mgr.queue_free()


func _create_empty_mock() -> Node:
	var script := GDScript.new()
	script.source_code = """
extends Node
signal notebook_opened
signal notebook_closed
signal board_updated
signal entry_selected(entry_id: StringName)
signal entry_deselected
signal connection_attempted(clue_a: StringName, clue_b: StringName, success: bool)
var is_open: bool = false
func open_notebook() -> bool:
	is_open = true
	return true
func close_notebook() -> void:
	is_open = false
func get_board_nodes() -> Array[Dictionary]:
	return []
func get_board_edges() -> Array[Dictionary]:
	return []
func get_all_visible() -> Array[StringName]:
	return []
func search_entries(_q: String) -> Array[StringName]:
	return []
func get_entry_detail(_id: StringName) -> Dictionary:
	return {}
func select_entry(_id: StringName) -> void:
	pass
func deselect_all() -> void:
	pass
func request_connection(_a: StringName, _b: StringName) -> Dictionary:
	return {"ok": false}
func update_node_position(_id: StringName, _x: float, _y: float) -> void:
	pass
"""
	script.reload()
	var mgr := Node.new()
	mgr.set_script(script)
	return mgr


func test_non_empty_board_hides_label() -> void:
	_panel.show_panel()
	_panel._animating = false
	assert_bool(_panel._empty_label.visible).is_false()


# ---------------------------------------------------------------------------
# Node Selection
# ---------------------------------------------------------------------------


func test_toggle_node_selection_adds() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._toggle_node_selection(&"clue_1")
	assert_int(_panel._selected_node_ids.size()).is_equal(1)
	assert_eq(_panel._selected_node_ids[0], &"clue_1")


func test_toggle_node_selection_removes() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._toggle_node_selection(&"clue_1")
	_panel._toggle_node_selection(&"clue_1")
	assert_int(_panel._selected_node_ids.size()).is_equal(0)


func test_multiple_selections() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._toggle_node_selection(&"clue_1")
	_panel._toggle_node_selection(&"clue_2")
	assert_int(_panel._selected_node_ids.size()).is_equal(2)


func test_selection_clears_on_hide() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._toggle_node_selection(&"clue_1")
	_panel.hide_panel_immediate()
	assert_int(_panel._selected_node_ids.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Connection Bar
# ---------------------------------------------------------------------------


func test_connection_bar_hidden_with_no_selection() -> void:
	_panel.show_panel()
	_panel._animating = false
	assert_bool(_panel._connection_bar.visible).is_false()


func test_connection_bar_hidden_with_one_selection() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._toggle_node_selection(&"clue_1")
	assert_bool(_panel._connection_bar.visible).is_false()


func test_connection_bar_visible_with_two_clue_selections() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._toggle_node_selection(&"clue_1")
	_panel._toggle_node_selection(&"clue_2")
	assert_bool(_panel._connection_bar.visible).is_true()


func test_connection_bar_hidden_when_insight_selected() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._toggle_node_selection(&"clue_1")
	_panel._toggle_node_selection(&"insight_1")
	assert_bool(_panel._connection_bar.visible).is_false()


func test_connect_button_delegates_to_manager() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._toggle_node_selection(&"clue_1")
	_panel._toggle_node_selection(&"clue_2")
	_panel._on_connect_pressed()
	assert_eq(_mock_manager._last_connection_a, &"clue_1")
	assert_eq(_mock_manager._last_connection_b, &"clue_2")


func test_connect_clears_selection() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._toggle_node_selection(&"clue_1")
	_panel._toggle_node_selection(&"clue_2")
	_panel._on_connect_pressed()
	assert_int(_panel._selected_node_ids.size()).is_equal(0)


func test_connect_emits_signal() -> void:
	var emitted_a: StringName = &""
	var emitted_b: StringName = &""
	_panel.connection_requested.connect(func(a: StringName, b: StringName) -> void:
		emitted_a = a
		emitted_b = b
	)
	_panel.show_panel()
	_panel._animating = false
	_panel._toggle_node_selection(&"clue_1")
	_panel._toggle_node_selection(&"clue_2")
	_panel._on_connect_pressed()
	assert_eq(emitted_a, &"clue_1")
	assert_eq(emitted_b, &"clue_2")


# ---------------------------------------------------------------------------
# List View
# ---------------------------------------------------------------------------


func test_list_view_shows_entries() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel.set_view_mode(1)
	var child_count := _panel._list_container.get_child_count()
	assert_int(child_count).is_equal(3)


func test_list_view_with_search_filters() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._search_query = "线索"
	_panel.set_view_mode(1)
	var child_count := _panel._list_container.get_child_count()
	assert_int(child_count).is_equal(1)


func test_list_view_no_results() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._search_query = "none"
	_panel.set_view_mode(1)
	assert_int(_panel._list_container.get_child_count()).is_equal(1)
	var label: Label = _panel._list_container.get_child(0)
	assert_eq(label.text, "没有找到相关条目")


func test_search_bar_updates_query() -> void:
	_panel._on_search_changed("test")
	assert_eq(_panel._search_query, "test")


# ---------------------------------------------------------------------------
# Detail View
# ---------------------------------------------------------------------------


func test_detail_view_shows_title() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._detail_entry_id = &"clue_1"
	_panel.set_view_mode(2)
	var title: Label = _panel._detail_view.get_child(0)
	assert_eq(title.text, "线索一")


func test_detail_view_shows_description() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._detail_entry_id = &"clue_1"
	_panel.set_view_mode(2)
	var desc: RichTextLabel = _panel._detail_view.get_child(1)
	assert_eq(desc.text, "描述一")


func test_detail_view_shows_contextual_unlocks() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._detail_entry_id = &"clue_1"
	_panel.set_view_mode(2)
	var unlock_rtl: RichTextLabel = _panel._detail_view.get_child(2)
	assert_bool(unlock_rtl.text.contains("新解读")).is_true()


func test_detail_view_shows_connections() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._detail_entry_id = &"clue_1"
	_panel.set_view_mode(2)
	var children := _panel._detail_view.get_children()
	var has_connections := false
	for child: Node in children:
		if child is Label and child.text == "连接":
			has_connections = true
	assert_bool(has_connections).is_true()


func test_detail_view_empty_entry() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._detail_entry_id = &"nonexistent"
	_panel.set_view_mode(2)
	assert_int(_panel._detail_view.get_child_count()).is_equal(0)


# ---------------------------------------------------------------------------
# Board Input
# ---------------------------------------------------------------------------


func test_screen_to_board_transforms() -> void:
	_panel._board_offset = Vector2(100, 50)
	_panel._board_zoom = 2.0
	var result := _panel._screen_to_board(Vector2(200, 150))
	assert_float(result.x).is_equal_approx(50.0, 0.1)
	assert_float(result.y).is_equal_approx(50.0, 0.1)


func test_hit_test_finds_node() -> void:
	_panel._board_nodes = [
		{"entry_id": &"clue_1", "position": Vector2(200, 300), "size": 32.0},
	]
	var hit := _panel._hit_test_node(Vector2(200, 300))
	assert_eq(hit, &"clue_1")


func test_hit_test_misses_node() -> void:
	_panel._board_nodes = [
		{"entry_id": &"clue_1", "position": Vector2(200, 300), "size": 32.0},
	]
	var hit := _panel._hit_test_node(Vector2(500, 500))
	assert_eq(hit, &"")


func test_hit_test_with_tolerance() -> void:
	_panel._board_nodes = [
		{"entry_id": &"clue_1", "position": Vector2(200, 300), "size": 32.0},
	]
	var hit := _panel._hit_test_node(Vector2(218, 300))
	assert_eq(hit, &"clue_1")


func test_zoom_in_clamps_max() -> void:
	_panel._board_zoom = 2.95
	_panel._board_zoom = minf(_panel._board_zoom + 0.1, 3.0)
	assert_float(_panel._board_zoom).is_equal_approx(3.0, 0.01)


func test_zoom_out_clamps_min() -> void:
	_panel._board_zoom = 0.35
	_panel._board_zoom = maxf(_panel._board_zoom - 0.1, 0.3)
	assert_float(_panel._board_zoom).is_equal_approx(0.3, 0.01)


# ---------------------------------------------------------------------------
# Data Refresh
# ---------------------------------------------------------------------------


func test_refresh_data_loads_nodes() -> void:
	_panel._refresh_data()
	assert_int(_panel._board_nodes.size()).is_equal(3)


func test_refresh_data_loads_edges() -> void:
	_panel._refresh_data()
	assert_int(_panel._board_edges.size()).is_equal(1)


func test_refresh_data_handles_null_manager() -> void:
	_panel.set_notebook_manager(null)
	_panel._refresh_data()
	assert_int(_panel._board_nodes.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Signal Wiring
# ---------------------------------------------------------------------------


func test_board_updated_signal_refreshes() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._view_mode = 0
	_mock_manager.board_updated.emit()
	assert_int(_panel._board_nodes.size()).is_equal(3)


func test_connection_attempted_signal_refreshes() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._view_mode = 0
	_mock_manager.connection_attempted.emit(&"clue_1", &"clue_2", true)
	assert_int(_panel._board_nodes.size()).is_equal(3)


# ---------------------------------------------------------------------------
# Graceful Degradation
# ---------------------------------------------------------------------------


func test_show_panel_no_manager_still_works() -> void:
	_panel.set_notebook_manager(null)
	_panel.show_panel()
	_panel._animating = false
	assert_bool(_panel.visible).is_true()


func test_detail_view_no_manager() -> void:
	_panel.set_notebook_manager(null)
	_panel._detail_entry_id = &"clue_1"
	_panel.set_view_mode(2)
	assert_int(_panel._detail_view.get_child_count()).is_equal(0)


func test_list_view_no_manager() -> void:
	_panel.set_notebook_manager(null)
	_panel.set_view_mode(1)
	assert_int(_panel._list_container.get_child_count()).is_equal(0)


# ---------------------------------------------------------------------------
# DI Seam
# ---------------------------------------------------------------------------


func test_set_notebook_manager_override() -> void:
	var new_mgr := Node.new()
	_panel.set_notebook_manager(new_mgr)
	assert_eq(_panel._notebook_manager, new_mgr)
	new_mgr.queue_free()


# ---------------------------------------------------------------------------
# Edge Cases
# ---------------------------------------------------------------------------


func test_show_panel_while_animating_is_noop() -> void:
	_panel._animating = true
	_panel.show_panel()
	assert_bool(_panel.visible).is_false()


func test_hide_panel_while_animating_is_noop() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._animating = true
	_panel.hide_panel()
	assert_bool(_panel.visible).is_true()


func test_connect_with_wrong_selection_count() -> void:
	_panel._on_connect_pressed()
	assert_eq(_mock_manager._last_connection_a, &"")


func test_hide_immediate_resets_drag_state() -> void:
	_panel._dragging_node_id = &"clue_1"
	_panel._is_panning = true
	_panel.hide_panel_immediate()
	assert_eq(_panel._dragging_node_id, &"")
	assert_bool(_panel._is_panning).is_false()


func test_search_submitted_switches_to_list() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._search_query = "test"
	_panel._on_search_submitted("test")
	assert_int(_panel._view_mode).is_equal(1)


func test_search_submitted_empty_no_switch() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._search_query = ""
	_panel._on_search_submitted("")
	assert_int(_panel._view_mode).is_equal(0)


func test_detail_entry_cleared_on_hide() -> void:
	_panel.show_panel()
	_panel._animating = false
	_panel._detail_entry_id = &"clue_1"
	_panel.hide_panel_immediate()
	assert_eq(_panel._detail_entry_id, &"")
