extends CanvasLayer

## RoomNavigationUI — shows current room name and exit buttons on CanvasLayer 20.
## Listens to RoomManager signals for room changes and transition state.
## Depends on: RoomManager (#3), InteractionBus (#7), DialogueManager (#14).
## GDD: design/gdd/room-location-management.md (Rule 6, Section UI Requirements)

signal navigation_requested(room_id: StringName)

const NAV_LAYER: int = 20
const ROOM_NAME_FONT_SIZE: int = 14
const EXIT_FONT_SIZE: int = 14
const MIN_TOUCH_TARGET: int = 44
const BAR_PADDING: float = 12.0
const BAR_HEIGHT: float = 48.0
const SEAL_BORDER_COLOR: Color = Color(0.545, 0.0, 0.0)
const INK_TEXT_COLOR: Color = Color(0.172, 0.172, 0.172)
const BAR_BG_COLOR: Color = Color(1.0, 1.0, 1.0, 0.75)

## Room display labels. Data-driven — extracted to config in production.
var room_labels: Dictionary = {
	&"lobby": "大厅",
	&"corridor": "走廊",
	&"guest_room_a": "客房 A",
}

## Room exit connections: room_id -> Array[{id, label}].
var room_connections: Dictionary = {
	&"lobby": [{"id": &"corridor", "label": "走廊"}],
	&"corridor": [{"id": &"lobby", "label": "大厅"}, {"id": &"guest_room_a", "label": "客房 A"}],
	&"guest_room_a": [{"id": &"corridor", "label": "走廊"}],
}

var _current_room: StringName = &""
var _is_transitioning: bool = false
var _is_dialogue_active: bool = false
var _room_manager: Node = null
var _dialogue_manager: Node = null

var _room_name_label: Label
var _exit_bar: HBoxContainer
var _top_bar: Control
var _bottom_bar: Control


func _ready() -> void:
	layer = NAV_LAYER
	_build_ui()
	_connect_signals()


## Called when the room changes. Updates the room name and exit buttons.
func update_for_room(room_id: StringName) -> void:
	_current_room = room_id
	_update_room_name()
	_update_exit_buttons()


## Returns the currently displayed room ID.
func get_current_room() -> StringName:
	return _current_room


## Returns true if navigation buttons are interactive.
func is_navigation_enabled() -> bool:
	return not _is_transitioning and not _is_dialogue_active


## Override RoomManager reference (dependency injection for tests).
func set_room_manager(manager: Node) -> void:
	_room_manager = manager


## Override DialogueManager reference (dependency injection for tests).
func set_dialogue_manager(manager: Node) -> void:
	_dialogue_manager = manager


# ---------------------------------------------------------------------------
# Private — UI Construction
# ---------------------------------------------------------------------------


func _build_ui() -> void:
	_top_bar = _create_top_bar()
	add_child(_top_bar)

	_bottom_bar = _create_bottom_bar()
	add_child(_bottom_bar)


func _create_top_bar() -> Control:
	var bar := Control.new()
	bar.name = "TopBar"
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 0.0
	bar.offset_bottom = BAR_HEIGHT

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BAR_BG_COLOR
	bar.add_child(bg)

	_room_name_label = Label.new()
	_room_name_label.name = "RoomNameLabel"
	_room_name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_room_name_label.offset_left = BAR_PADDING
	_room_name_label.offset_right = -BAR_PADDING
	_room_name_label.offset_top = 0.0
	_room_name_label.offset_bottom = 0.0
	_room_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_room_name_label.add_theme_font_size_override("font_size", ROOM_NAME_FONT_SIZE)
	_room_name_label.add_theme_color_override("font_color", INK_TEXT_COLOR)
	_room_name_label.text = ""
	bar.add_child(_room_name_label)

	return bar


func _create_bottom_bar() -> Control:
	var bar := Control.new()
	bar.name = "BottomBar"
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -BAR_HEIGHT

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BAR_BG_COLOR
	bar.add_child(bg)

	_exit_bar = HBoxContainer.new()
	_exit_bar.name = "ExitBar"
	_exit_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_exit_bar.offset_left = BAR_PADDING
	_exit_bar.offset_right = -BAR_PADDING
	_exit_bar.offset_top = 0.0
	_exit_bar.offset_bottom = 0.0
	_exit_bar.add_theme_constant_override("separation", 8)
	_exit_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_child(_exit_bar)

	return bar


# ---------------------------------------------------------------------------
# Private — Display Updates
# ---------------------------------------------------------------------------


func _update_room_name() -> void:
	if _room_name_label == null:
		return
	_room_name_label.text = room_labels.get(_current_room, String(_current_room))


func _update_exit_buttons() -> void:
	_clear_exit_buttons()

	var exits: Array = room_connections.get(_current_room, [])
	for exit_info: Dictionary in exits:
		var button := _create_exit_button(exit_info)
		_exit_bar.add_child(button)

	_update_navigation_state()


func _create_exit_button(exit_info: Dictionary) -> Button:
	var button := Button.new()
	button.name = "ExitButton_" + String(exit_info.get("id", &""))
	button.text = exit_info.get("label", String(exit_info.get("id", &"")))
	button.custom_minimum_size = Vector2(MIN_TOUCH_TARGET, MIN_TOUCH_TARGET)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var target_id: StringName = exit_info.get("id", &"")
	button.pressed.connect(func() -> void:
		navigation_requested.emit(target_id)
		_request_room_transition(target_id)
	)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1.0, 1.0, 1.0, 0.6)
	normal.border_color = SEAL_BORDER_COLOR
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(4)
	normal.set_content_margin_all(8)

	var hover := StyleBoxFlat.new()
	hover.bg_color = SEAL_BORDER_COLOR
	hover.border_color = SEAL_BORDER_COLOR
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(4)
	hover.set_content_margin_all(8)

	var pressed_sb := normal.duplicate()
	pressed_sb.bg_color = Color(SEAL_BORDER_COLOR.r, SEAL_BORDER_COLOR.g, SEAL_BORDER_COLOR.b, 0.8)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed_sb)
	button.add_theme_stylebox_override("focus", hover)

	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", EXIT_FONT_SIZE)

	return button


func _clear_exit_buttons() -> void:
	if _exit_bar == null:
		return
	for child: Node in _exit_bar.get_children():
		child.queue_free()


func _update_navigation_state() -> void:
	var enabled := is_navigation_enabled()
	if _exit_bar != null:
		_exit_bar.modulate.a = 1.0 if enabled else 0.4
		for child: Node in _exit_bar.get_children():
			if child is Button:
				child.disabled = not enabled
	if _top_bar != null:
		_top_bar.modulate.a = 1.0 if not _is_dialogue_active else 0.3


# ---------------------------------------------------------------------------
# Private — Signal Wiring
# ---------------------------------------------------------------------------


func _connect_signals() -> void:
	_room_manager = get_node_or_null("/root/RoomManager")
	if _room_manager != null:
		if _room_manager.has_signal("room_changed"):
			_room_manager.room_changed.connect(_on_room_changed)
		if _room_manager.has_signal("room_transition_started"):
			_room_manager.room_transition_started.connect(_on_transition_started)
		if _room_manager.has_signal("room_transition_completed"):
			_room_manager.room_transition_completed.connect(_on_transition_completed)

	_dialogue_manager = get_node_or_null("/root/DialogueManager")
	if _dialogue_manager != null:
		if _dialogue_manager.has_signal("dialogue_started"):
			_dialogue_manager.dialogue_started.connect(_on_dialogue_started)
		if _dialogue_manager.has_signal("dialogue_ended"):
			_dialogue_manager.dialogue_ended.connect(_on_dialogue_ended)


func _on_room_changed(room_id: StringName) -> void:
	_is_transitioning = false
	update_for_room(room_id)


func _on_transition_started(_from: StringName, _to: StringName) -> void:
	_is_transitioning = true
	_update_navigation_state()


func _on_transition_completed(_room_id: StringName) -> void:
	_is_transitioning = false
	_update_navigation_state()


func _on_dialogue_started(_npc_id: StringName) -> void:
	_is_dialogue_active = true
	_update_navigation_state()


func _on_dialogue_ended(_npc_id: StringName) -> void:
	_is_dialogue_active = false
	_update_navigation_state()


# ---------------------------------------------------------------------------
# Private — Navigation
# ---------------------------------------------------------------------------


func _request_room_transition(room_id: StringName) -> void:
	if not is_navigation_enabled():
		return
	if _room_manager != null and _room_manager.has_method("request_transition"):
		_room_manager.request_transition(room_id)
