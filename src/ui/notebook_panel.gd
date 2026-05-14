extends CanvasLayer

## NotebookPanel — full-screen notebook overlay on CanvasLayer 50.
## Renders board/list/detail views from NotebookManager data.
## GDD: design/gdd/notebook-system.md, ADR-0003

signal connection_requested(clue_a: StringName, clue_b: StringName)

enum ViewMode { BOARD, LIST, DETAIL }

const LAYER_DEPTH: int = 50
const DIMMER_ALPHA: float = 0.8
const ENTER_DURATION: float = 0.3
const EXIT_DURATION: float = 0.2
const TOOLBAR_HEIGHT: float = 48.0
const MIN_TOUCH_TARGET: int = 44
const FONT_SIZE_TITLE: int = 20
const FONT_SIZE_NORMAL: int = 14
const FONT_SIZE_SMALL: int = 12
const CLUE_NODE_SIZE: float = 32.0
const INSIGHT_NODE_SIZE: float = 40.0
const MIN_ZOOM: float = 0.3
const MAX_ZOOM: float = 3.0
const ZOOM_STEP: float = 0.1
const PAN_SPEED: float = 8.0
const GOLD_OCHRE: Color = Color(0.8, 0.467, 0.133)
const INVALID_EDGE_COLOR: Color = Color(0.5, 0.5, 0.5, 0.3)
const SEAL_BORDER_COLOR: Color = Color(0.545, 0.0, 0.0)
const SEARCH_PLACEHOLDER: String = "搜索线索..."
const EMPTY_BOARD_TEXT: String = "探索世界，发现线索。"
const NO_RESULTS_TEXT: String = "没有找到相关条目"
const CONNECT_BUTTON_TEXT: String = "连接"
const CLOSE_BUTTON_TEXT: String = "关闭"
const BACK_BUTTON_TEXT: String = "返回"
const BOARD_BUTTON_TEXT: String = "板"
const LIST_BUTTON_TEXT: String = "列表"

var _view_mode: ViewMode = ViewMode.BOARD
var _notebook_manager: Node = null
var _board_nodes: Array[Dictionary] = []
var _board_edges: Array[Dictionary] = []
var _selected_node_ids: Array[StringName] = []
var _detail_entry_id: StringName = &""
var _search_query: String = ""
var _dragging_node_id: StringName = &""
var _is_panning: bool = false
var _pan_start: Vector2 = Vector2.ZERO
var _board_offset: Vector2 = Vector2.ZERO
var _board_zoom: float = 1.0
var _animating: bool = false

var _dimmer: ColorRect
var _main_container: Control
var _toolbar: HBoxContainer
var _search_bar: LineEdit
var _board_button: Button
var _list_button: Button
var _close_button: Button
var _content_area: Control
var _board_view: Control
var _list_view: ScrollContainer
var _list_container: VBoxContainer
var _detail_view: VBoxContainer
var _connection_bar: HBoxContainer
var _connect_button: Button
var _selection_label: Label
var _empty_label: Label


func _ready() -> void:
	layer = LAYER_DEPTH
	_build_ui()
	hide_panel_immediate()
	_connect_notebook_manager()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _view_mode == ViewMode.BOARD:
		_handle_board_input(event)


func _draw() -> void:
	if _view_mode != ViewMode.BOARD:
		return
	_draw_board()


## Show the panel with enter animation.
func show_panel() -> void:
	if _animating:
		return
	if _notebook_manager == null:
		return
	_notebook_manager.open_notebook()
	_refresh_data()

	_dimmer.visible = true
	_main_container.visible = true
	visible = true
	_view_mode = ViewMode.BOARD
	_selected_node_ids.clear()

	_animating = true
	var tween: Tween = create_tween()
	tween.tween_property(_dimmer, "color:a", DIMMER_ALPHA, ENTER_DURATION)
	tween.tween_callback(func() -> void:
		_animating = false
		_show_current_view()
	)


## Hide the panel with exit animation.
func hide_panel() -> void:
	if _animating:
		return
	_animating = true
	if _notebook_manager != null:
		_notebook_manager.close_notebook()

	var tween: Tween = create_tween()
	tween.tween_property(_dimmer, "color:a", 0.0, EXIT_DURATION)
	tween.tween_callback(func() -> void:
		_animating = false
		hide_panel_immediate()
	)


## Immediately hide without animation (for cleanup / tests).
func hide_panel_immediate() -> void:
	visible = false
	_dimmer.visible = false
	_dimmer.color.a = 0.0
	_main_container.visible = false
	_animating = false
	_selected_node_ids.clear()
	_dragging_node_id = &""
	_is_panning = false
	_detail_entry_id = &""


## Is the panel currently visible and not animating?
var is_panel_open: bool:
	get:
		return visible and not _animating


## Override NotebookManager reference (dependency injection for tests).
func set_notebook_manager(manager: Node) -> void:
	_notebook_manager = manager


## Switch to a specific view mode.
func set_view_mode(mode: ViewMode) -> void:
	_view_mode = mode
	if _board_button != null:
		_board_button.disabled = (mode == ViewMode.BOARD)
	if _list_button != null:
		_list_button.disabled = (mode == ViewMode.LIST)
	_show_current_view()


# ---------------------------------------------------------------------------
# Private — UI Construction
# ---------------------------------------------------------------------------


func _build_ui() -> void:
	_dimmer = ColorRect.new()
	_dimmer.name = "Dimmer"
	_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dimmer.color = Color(0.0, 0.0, 0.0, 0.0)
	_dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dimmer)

	_main_container = Control.new()
	_main_container.name = "MainContainer"
	_main_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_main_container)

	_build_toolbar()
	_build_content_area()
	_build_connection_bar()


func _build_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.name = "Toolbar"
	_toolbar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toolbar.offset_bottom = TOOLBAR_HEIGHT
	_toolbar.offset_left = 16.0
	_toolbar.offset_right = -16.0
	_toolbar.add_theme_constant_override("separation", 8)
	_main_container.add_child(_toolbar)

	_search_bar = LineEdit.new()
	_search_bar.name = "SearchBar"
	_search_bar.placeholder_text = SEARCH_PLACEHOLDER
	_search_bar.custom_minimum_size = Vector2(200, MIN_TOUCH_TARGET)
	_search_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_bar.text_changed.connect(_on_search_changed)
	_search_bar.text_submitted.connect(_on_search_submitted)
	_toolbar.add_child(_search_bar)

	_board_button = Button.new()
	_board_button.name = "BoardButton"
	_board_button.text = BOARD_BUTTON_TEXT
	_board_button.custom_minimum_size = Vector2(MIN_TOUCH_TARGET, MIN_TOUCH_TARGET)
	_board_button.pressed.connect(func() -> void: set_view_mode(ViewMode.BOARD))
	_toolbar.add_child(_board_button)

	_list_button = Button.new()
	_list_button.name = "ListButton"
	_list_button.text = LIST_BUTTON_TEXT
	_list_button.custom_minimum_size = Vector2(MIN_TOUCH_TARGET, MIN_TOUCH_TARGET)
	_list_button.pressed.connect(func() -> void: set_view_mode(ViewMode.LIST))
	_toolbar.add_child(_list_button)

	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.text = CLOSE_BUTTON_TEXT
	_close_button.custom_minimum_size = Vector2(MIN_TOUCH_TARGET, MIN_TOUCH_TARGET)
	_close_button.pressed.connect(func() -> void: hide_panel())
	_toolbar.add_child(_close_button)


func _build_content_area() -> void:
	_content_area = Control.new()
	_content_area.name = "ContentArea"
	_content_area.anchor_top = TOOLBAR_HEIGHT / get_viewport_size().y if get_viewport() else 0.0
	_content_area.anchor_bottom = 0.88
	_content_area.anchor_left = 0.0
	_content_area.anchor_right = 1.0
	_main_container.add_child(_content_area)

	_board_view = Control.new()
	_board_view.name = "BoardView"
	_board_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board_view.draw.connect(_on_board_draw)
	_content_area.add_child(_board_view)

	_empty_label = Label.new()
	_empty_label.name = "EmptyLabel"
	_empty_label.set_anchors_preset(Control.PRESET_CENTER)
	_empty_label.text = EMPTY_BOARD_TEXT
	_empty_label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_font_size_override("font_size", FONT_SIZE_NORMAL)
	_empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_content_area.add_child(_empty_label)

	_list_view = ScrollContainer.new()
	_list_view.name = "ListView"
	_list_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_list_view.visible = false
	_content_area.add_child(_list_view)

	_list_container = VBoxContainer.new()
	_list_container.name = "ListContainer"
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_container.add_theme_constant_override("separation", 4)
	_list_view.add_child(_list_container)

	_detail_view = VBoxContainer.new()
	_detail_view.name = "DetailView"
	_detail_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_detail_view.offset_left = 24.0
	_detail_view.offset_right = -24.0
	_detail_view.offset_top = 8.0
	_detail_view.offset_bottom = -8.0
	_detail_view.add_theme_constant_override("separation", 12)
	_detail_view.visible = false
	_content_area.add_child(_detail_view)


func _build_connection_bar() -> void:
	_connection_bar = HBoxContainer.new()
	_connection_bar.name = "ConnectionBar"
	_connection_bar.anchor_top = 0.88
	_connection_bar.anchor_bottom = 1.0
	_connection_bar.anchor_left = 0.0
	_connection_bar.anchor_right = 1.0
	_connection_bar.offset_left = 24.0
	_connection_bar.offset_right = -24.0
	_connection_bar.add_theme_constant_override("separation", 12)
	_connection_bar.visible = false
	_main_container.add_child(_connection_bar)

	_selection_label = Label.new()
	_selection_label.name = "SelectionLabel"
	_selection_label.add_theme_font_size_override("font_size", FONT_SIZE_NORMAL)
	_selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_connection_bar.add_child(_selection_label)

	_connect_button = Button.new()
	_connect_button.name = "ConnectButton"
	_connect_button.text = CONNECT_BUTTON_TEXT
	_connect_button.custom_minimum_size = Vector2(MIN_TOUCH_TARGET * 2, MIN_TOUCH_TARGET)
	_connect_button.pressed.connect(_on_connect_pressed)
	_connection_bar.add_child(_connect_button)


func get_viewport_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2(1280, 720)
	return vp.get_visible_rect().size


# ---------------------------------------------------------------------------
# Private — View Switching
# ---------------------------------------------------------------------------


func _show_current_view() -> void:
	_board_view.visible = (_view_mode == ViewMode.BOARD)
	_list_view.visible = (_view_mode == ViewMode.LIST)
	_detail_view.visible = (_view_mode == ViewMode.DETAIL)

	match _view_mode:
		ViewMode.BOARD:
			_refresh_board_view()
		ViewMode.LIST:
			_refresh_list_view()
		ViewMode.DETAIL:
			_refresh_detail_view()

	_update_connection_bar()


func _refresh_board_view() -> void:
	_empty_label.visible = _board_nodes.is_empty()
	_board_view.queue_redraw()


func _refresh_list_view() -> void:
	for child: Node in _list_container.get_children():
		child.queue_free()

	var entries: Array[StringName]
	if _search_query.is_empty():
		if _notebook_manager != null and _notebook_manager.has_method("get_all_visible"):
			entries = _notebook_manager.get_all_visible()
	else:
		if _notebook_manager != null and _notebook_manager.has_method("search_entries"):
			entries = _notebook_manager.search_entries(_search_query)

	if entries.is_empty() and not _search_query.is_empty():
		var no_result := Label.new()
		no_result.text = NO_RESULTS_TEXT
		no_result.add_theme_font_size_override("font_size", FONT_SIZE_NORMAL)
		no_result.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_list_container.add_child(no_result)
		return

	for entry_id: StringName in entries:
		var detail: Dictionary = {}
		if _notebook_manager != null and _notebook_manager.has_method("get_entry_detail"):
			detail = _notebook_manager.get_entry_detail(entry_id)

		var entry_data: Dictionary = detail.get("entry", {})
		var button := Button.new()
		button.text = entry_data.get("title", String(entry_id))
		button.custom_minimum_size = Vector2(0, MIN_TOUCH_TARGET)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", FONT_SIZE_NORMAL)

		var captured_id: StringName = entry_id
		button.pressed.connect(func() -> void:
			_detail_entry_id = captured_id
			set_view_mode(ViewMode.DETAIL)
		)
		_list_container.add_child(button)


func _refresh_detail_view() -> void:
	for child: Node in _detail_view.get_children():
		child.queue_free()

	if _detail_entry_id == &"":
		return

	var detail: Dictionary = {}
	if _notebook_manager != null and _notebook_manager.has_method("get_entry_detail"):
		detail = _notebook_manager.get_entry_detail(_detail_entry_id)

	var entry_data: Dictionary = detail.get("entry", {})
	if entry_data.is_empty():
		return

	var title := Label.new()
	title.text = entry_data.get("title", "")
	title.add_theme_font_size_override("font_size", FONT_SIZE_TITLE)
	_detail_view.add_child(title)

	var desc := RichTextLabel.new()
	desc.bbcode_enabled = false
	desc.text = entry_data.get("description", "")
	desc.fit_content = true
	desc.add_theme_font_size_override("normal_font_size", FONT_SIZE_NORMAL)
	_detail_view.add_child(desc)

	var unlocks: Array = detail.get("contextual_unlocks", [])
	for unlock: Dictionary in unlocks:
		var unlock_label := RichTextLabel.new()
		unlock_label.bbcode_enabled = true
		var reinterpretation: String = unlock.get("reinterpretation", "")
		unlock_label.text = "[i]" + reinterpretation + "[/i]"
		unlock_label.fit_content = true
		unlock_label.add_theme_font_size_override("normal_font_size", FONT_SIZE_SMALL)
		unlock_label.add_theme_color_override("default_color", GOLD_OCHRE)
		_detail_view.add_child(unlock_label)

	var connections: Array = detail.get("connections", [])
	if not connections.is_empty():
		var conn_header := Label.new()
		conn_header.text = "连接"
		conn_header.add_theme_font_size_override("font_size", FONT_SIZE_NORMAL)
		_detail_view.add_child(conn_header)

		for conn: Dictionary in connections:
			var conn_label := Label.new()
			var other_id: StringName = conn.get("other_id", &"")
			var is_valid: bool = conn.get("is_valid", false)
			var prefix: String = "● " if is_valid else "○ "
			conn_label.text = prefix + String(other_id)
			conn_label.add_theme_font_size_override("font_size", FONT_SIZE_SMALL)
			conn_label.add_theme_color_override("font_color", GOLD_OCHRE if is_valid else Color(0.5, 0.5, 0.5))
			_detail_view.add_child(conn_label)

	var back_button := Button.new()
	back_button.text = BACK_BUTTON_TEXT
	back_button.custom_minimum_size = Vector2(MIN_TOUCH_TARGET, MIN_TOUCH_TARGET)
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back_button.pressed.connect(func() -> void:
		set_view_mode(ViewMode.LIST)
	)
	_detail_view.add_child(back_button)


# ---------------------------------------------------------------------------
# Private — Board Drawing
# ---------------------------------------------------------------------------


func _on_board_draw() -> void:
	_draw_board()


func _draw_board() -> void:
	if _board_view == null:
		return
	_board_view.draw_set_transform(_board_offset, 0.0, Vector2(_board_zoom, _board_zoom))

	for edge: Dictionary in _board_edges:
		var pos_a: Vector2 = _get_node_pos_for_edge(edge["clue_a"])
		var pos_b: Vector2 = _get_node_pos_for_edge(edge["clue_b"])
		var color: Color = edge.get("color", INVALID_EDGE_COLOR)
		var width: float = edge.get("width", 1.0)
		if edge.get("is_valid", false):
			_board_view.draw_line(pos_a, pos_b, color, width, true)
		else:
			_draw_dashed_line(pos_a, pos_b, color, width)

	for node: Dictionary in _board_nodes:
		var pos: Vector2 = node.get("position", Vector2.ZERO)
		var color: Color = node.get("color", Color.WHITE)
		var size: float = node.get("size", CLUE_NODE_SIZE)
		var state: String = node.get("state", "normal")
		var entry_type: int = node.get("entry_type", 0)

		var draw_color: Color = color
		if state == "selected":
			draw_color = Color(color.r + 0.2, color.g + 0.2, color.b + 0.2)

		if entry_type == 1:
			_draw_diamond(pos, size, draw_color)
		else:
			_board_view.draw_circle(pos, size * 0.5, draw_color)

		if state == "selected":
			if entry_type == 1:
				_draw_diamond_outline(pos, size + 4.0, GOLD_OCHRE)
			else:
				_board_view.draw_circle(pos, (size * 0.5) + 2.0, GOLD_OCHRE, false, 2.0)

	_board_view.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _get_node_pos_for_edge(node_id: StringName) -> Vector2:
	for node: Dictionary in _board_nodes:
		if node.get("entry_id", &"") == node_id:
			return node.get("position", Vector2.ZERO)
	return Vector2.ZERO


func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var direction := to - from
	var length := direction.length()
	if length < 1.0:
		return
	var dir_norm := direction.normalized()
	var dash_len := 6.0
	var gap_len := 4.0
	var drawn := 0.0
	while drawn < length:
		var seg_start := from + dir_norm * drawn
		var seg_end := from + dir_norm * minf(drawn + dash_len, length)
		_board_view.draw_line(seg_start, seg_end, color, width, true)
		drawn += dash_len + gap_len


func _draw_diamond(center: Vector2, size: float, color: Color) -> void:
	var half := size * 0.5
	var points := PackedVector2Array([
		center + Vector2(0, -half),
		center + Vector2(half, 0),
		center + Vector2(0, half),
		center + Vector2(-half, 0),
	])
	_board_view.draw_polygon(points, PackedColorArray([color]))


func _draw_diamond_outline(center: Vector2, size: float, color: Color) -> void:
	var half := size * 0.5
	var points := PackedVector2Array([
		center + Vector2(0, -half),
		center + Vector2(half, 0),
		center + Vector2(0, half),
		center + Vector2(-half, 0),
	])
	_board_view.draw_polyline(points, color, 2.0, true)


# ---------------------------------------------------------------------------
# Private — Board Input
# ---------------------------------------------------------------------------


func _handle_board_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventPanGesture:
		_board_offset += event.delta * PAN_SPEED
		_board_view.queue_redraw()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	var board_pos := _screen_to_board(event.position)

	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var clicked_id := _hit_test_node(board_pos)
		if clicked_id != &"":
			_toggle_node_selection(clicked_id)
		else:
			if _selected_node_ids.size() > 0:
				_selected_node_ids.clear()
				_update_connection_bar()
				_refresh_data()
				_board_view.queue_redraw()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_is_panning = true
			_pan_start = event.position
		else:
			_is_panning = false
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_board_zoom = minf(_board_zoom + ZOOM_STEP, MAX_ZOOM)
		_board_view.queue_redraw()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_board_zoom = maxf(_board_zoom - ZOOM_STEP, MIN_ZOOM)
		_board_view.queue_redraw()


func _handle_touch(event: InputEventScreenTouch) -> void:
	if not event.pressed:
		_is_panning = false
		if _dragging_node_id != &"":
			_dragging_node_id = &""
		return

	var board_pos := _screen_to_board(event.position)
	var clicked_id := _hit_test_node(board_pos)
	if clicked_id != &"":
		_dragging_node_id = clicked_id
		_toggle_node_selection(clicked_id)
	else:
		_is_panning = true
		_pan_start = event.position


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _is_panning:
		_board_offset += event.relative
		_board_view.queue_redraw()
	elif _dragging_node_id != &"" and event.button_mask & MOUSE_BUTTON_LEFT:
		var board_pos := _screen_to_board(event.position)
		if _notebook_manager != null and _notebook_manager.has_method("update_node_position"):
			_notebook_manager.update_node_position(_dragging_node_id, board_pos.x, board_pos.y)
		for node: Dictionary in _board_nodes:
			if node.get("entry_id", &"") == _dragging_node_id:
				node["position"] = board_pos
		_board_view.queue_redraw()


func _screen_to_board(screen_pos: Vector2) -> Vector2:
	var local := screen_pos - _board_view.global_position
	return (local - _board_offset) / _board_zoom


func _hit_test_node(board_pos: Vector2) -> StringName:
	for i: int in range(_board_nodes.size() - 1, -1, -1):
		var node: Dictionary = _board_nodes[i]
		var pos: Vector2 = node.get("position", Vector2.ZERO)
		var size: float = node.get("size", CLUE_NODE_SIZE)
		var dist := board_pos.distance_to(pos)
		if dist <= size * 0.5 + 4.0:
			return node.get("entry_id", &"")
	return &""


func _toggle_node_selection(entry_id: StringName) -> void:
	var idx := _selected_node_ids.find(entry_id)
	if idx >= 0:
		_selected_node_ids.remove_at(idx)
	else:
		_selected_node_ids.append(entry_id)
	if _notebook_manager != null and _notebook_manager.has_method("deselect_all"):
		_notebook_manager.deselect_all()
	for id: StringName in _selected_node_ids:
		if _notebook_manager != null and _notebook_manager.has_method("select_entry"):
			_notebook_manager.select_entry(id)
	_update_connection_bar()
	_refresh_data()
	_board_view.queue_redraw()


# ---------------------------------------------------------------------------
# Private — Connection Bar
# ---------------------------------------------------------------------------


func _update_connection_bar() -> void:
	var show_bar: bool = _view_mode == ViewMode.BOARD and _selected_node_ids.size() == 2
	if show_bar:
		var both_clues := true
		for node: Dictionary in _board_nodes:
			if node.get("entry_id", &"") in _selected_node_ids:
				if node.get("entry_type", 0) != 0:
					both_clues = false
					break
		show_bar = both_clues

	_connection_bar.visible = show_bar
	if show_bar and _selection_label != null:
		_selection_label.text = "已选择: %s + %s" % [String(_selected_node_ids[0]), String(_selected_node_ids[1])]


func _on_connect_pressed() -> void:
	if _selected_node_ids.size() != 2:
		return
	connection_requested.emit(_selected_node_ids[0], _selected_node_ids[1])
	if _notebook_manager != null and _notebook_manager.has_method("request_connection"):
		_notebook_manager.request_connection(_selected_node_ids[0], _selected_node_ids[1])
	_selected_node_ids.clear()
	_update_connection_bar()
	_refresh_data()
	_board_view.queue_redraw()


# ---------------------------------------------------------------------------
# Private — Search
# ---------------------------------------------------------------------------


func _on_search_changed(new_text: String) -> void:
	_search_query = new_text
	if _view_mode == ViewMode.LIST:
		_refresh_list_view()


func _on_search_submitted(_text: String) -> void:
	if _search_query.is_empty():
		return
	if _view_mode != ViewMode.LIST:
		set_view_mode(ViewMode.LIST)
	else:
		_refresh_list_view()


# ---------------------------------------------------------------------------
# Private — Data Refresh
# ---------------------------------------------------------------------------


func _refresh_data() -> void:
	_board_nodes.clear()
	_board_edges.clear()
	if _notebook_manager == null:
		return
	if _notebook_manager.has_method("get_board_nodes"):
		_board_nodes = _notebook_manager.get_board_nodes()
	if _notebook_manager.has_method("get_board_edges"):
		_board_edges = _notebook_manager.get_board_edges()


# ---------------------------------------------------------------------------
# Private — Signal Wiring
# ---------------------------------------------------------------------------


func _connect_notebook_manager() -> void:
	_notebook_manager = get_node_or_null("/root/NotebookManager")
	if _notebook_manager == null:
		return
	if _notebook_manager.has_signal("notebook_opened"):
		_notebook_manager.notebook_opened.connect(_on_notebook_opened)
	if _notebook_manager.has_signal("notebook_closed"):
		_notebook_manager.notebook_closed.connect(_on_notebook_closed)
	if _notebook_manager.has_signal("board_updated"):
		_notebook_manager.board_updated.connect(_on_board_updated)
	if _notebook_manager.has_signal("entry_selected"):
		_notebook_manager.entry_selected.connect(_on_manager_entry_selected)
	if _notebook_manager.has_signal("connection_attempted"):
		_notebook_manager.connection_attempted.connect(_on_connection_attempted)


func _on_notebook_opened() -> void:
	_refresh_data()
	_show_current_view()


func _on_notebook_closed() -> void:
	pass


func _on_board_updated() -> void:
	_refresh_data()
	if _view_mode == ViewMode.BOARD:
		_board_view.queue_redraw()


func _on_manager_entry_selected(_entry_id: StringName) -> void:
	if _view_mode == ViewMode.BOARD:
		_refresh_data()
		_board_view.queue_redraw()


func _on_connection_attempted(_a: StringName, _b: StringName, _success: bool) -> void:
	_refresh_data()
	if _view_mode == ViewMode.BOARD:
		_board_view.queue_redraw()
