extends CanvasLayer

## DialoguePanel — renders dialogue sessions on CanvasLayer 40.
## Connects to DialogueManager signals for dialogue flow.
## GDD: design/gdd/dialogue-ui.md, ADR-0003, ADR-0013

signal choice_selected(choice_id: StringName)
signal skip_typewriter_requested
signal end_dialogue_requested

const TYPEWRITER_SPEED: float = 30.0
const MAX_VISIBLE_CHOICES: int = 5
const DIMMER_ALPHA: float = 0.7
const ENTER_DURATION: float = 0.5
const EXIT_DURATION: float = 0.3
const CHOICE_FADE_DURATION: float = 0.2
const CHOICE_FADE_DELAY: float = 0.05
const MIN_TOUCH_TARGET: int = 44
const PANEL_HEIGHT_RATIO: float = 0.3
const TEXT_FONT_SIZE: int = 16
const NAME_FONT_SIZE: int = 14
const SEAL_BORDER_COLOR: Color = Color(0.545, 0.0, 0.0)
const DEFAULT_NPC_COLOR: Color = Color.WHITE

var _typewriter_tween: Tween = null
var _is_typing: bool = false
var _full_text: String = ""
var _animating: bool = false
var _dialogue_manager: Node = null

var _dimmer: ColorRect = null
var _panel: Control = null
var _name_label: Label = null
var _text_label: RichTextLabel = null
var _choices_container: VBoxContainer = null
var _end_button: Button = null


func _ready() -> void:
	layer = 40
	_build_ui()
	hide_panel_immediate()
	_connect_dialogue_manager()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_typing:
			skip_typewriter_requested.emit()
			_skip_typewriter()
	elif event is InputEventScreenTouch and event.pressed:
		if _is_typing:
			skip_typewriter_requested.emit()
			_skip_typewriter()


## Show the panel with enter animation and display the first node.
func show_panel(npc_id: StringName, speaker_name: String, text: String, choices: Array[Dictionary]) -> void:
	if _animating:
		return
	_set_npc_color(npc_id)
	_name_label.text = speaker_name
	_full_text = text
	_text_label.text = ""
	_clear_choices()

	_dimmer.visible = true
	_panel.visible = true
	visible = true

	_animating = true
	var tween: Tween = create_tween()
	tween.tween_property(_dimmer, "color:a", DIMMER_ALPHA, ENTER_DURATION)
	tween.parallel().tween_property(_panel, "position:y", 0.0, ENTER_DURATION).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		_animating = false
		_start_typewriter(text)
		_display_choices(choices)
	)


## Update the displayed node without re-animating the panel entrance.
func update_node(speaker_name: String, text: String, choices: Array[Dictionary], npc_color: Color) -> void:
	_name_label.text = speaker_name
	_name_label.add_theme_color_override("font_color", npc_color)
	_full_text = text
	_text_label.text = ""
	_clear_choices()
	_start_typewriter(text)
	_display_choices(choices)


## Hide the panel with exit animation.
func hide_panel() -> void:
	if _animating:
		return
	_kill_typewriter()

	_animating = true
	var tween: Tween = create_tween()
	tween.tween_property(_dimmer, "color:a", 0.0, EXIT_DURATION)
	tween.parallel().tween_property(_panel, "position:y", _panel_offscreen_y(), EXIT_DURATION).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		_animating = false
		hide_panel_immediate()
	)


## Immediately hide without animation (for cleanup / tests).
func hide_panel_immediate() -> void:
	visible = false
	_dimmer.visible = false
	_dimmer.color.a = 0.0
	_panel.visible = false
	_panel.position.y = _panel_offscreen_y()
	_clear_choices()
	_kill_typewriter()
	_animating = false


## Is the typewriter effect currently running?
var is_typing: bool:
	get:
		return _is_typing


## Override DialogueManager reference (dependency injection for tests).
func set_dialogue_manager(manager: Node) -> void:
	_dialogue_manager = manager


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

	_panel = Control.new()
	_panel.name = "Panel"
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0 - PANEL_HEIGHT_RATIO
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 0.0
	_panel.offset_right = 0.0
	_panel.offset_top = 0.0
	_panel.offset_bottom = 0.0
	add_child(_panel)

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(1.0, 1.0, 1.0, 0.85)
	_panel.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 24.0
	vbox.offset_right = -24.0
	vbox.offset_top = 16.0
	vbox.offset_bottom = -16.0
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(_name_label)

	_text_label = RichTextLabel.new()
	_text_label.name = "TextLabel"
	_text_label.bbcode_enabled = false
	_text_label.fit_content = true
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.add_theme_font_size_override("normal_font_size", TEXT_FONT_SIZE)
	_text_label.add_theme_color_override("default_color", Color(0.172, 0.172, 0.172))
	vbox.add_child(_text_label)

	_choices_container = VBoxContainer.new()
	_choices_container.name = "ChoicesContainer"
	_choices_container.add_theme_constant_override("separation", 8)
	vbox.add_child(_choices_container)

	_end_button = Button.new()
	_end_button.name = "EndButton"
	_end_button.text = "告辞"
	_end_button.custom_minimum_size = Vector2(MIN_TOUCH_TARGET, MIN_TOUCH_TARGET)
	_end_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_end_button.pressed.connect(_on_end_button_pressed)
	vbox.add_child(_end_button)


func _panel_offscreen_y() -> float:
	var vp := get_viewport()
	if vp == null:
		return 300.0
	return vp.get_visible_rect().size.y * PANEL_HEIGHT_RATIO


# ---------------------------------------------------------------------------
# Private — Typewriter
# ---------------------------------------------------------------------------


func _start_typewriter(text: String) -> void:
	_kill_typewriter()
	if text.is_empty():
		_is_typing = false
		return

	_is_typing = true
	_full_text = text
	_text_label.text = text
	_text_label.visible_characters = 0

	var duration: float = text.length() / TYPEWRITER_SPEED
	_typewriter_tween = create_tween()
	_typewriter_tween.tween_method(_set_visible_chars, 0, text.length(), duration)
	_typewriter_tween.tween_callback(func() -> void:
		_is_typing = false
		_text_label.visible_characters = -1
		_typewriter_tween = null
	)


func _skip_typewriter() -> void:
	_kill_typewriter()
	_text_label.visible_characters = -1
	_is_typing = false


func _set_visible_chars(count: int) -> void:
	_text_label.visible_characters = count


func _kill_typewriter() -> void:
	if _typewriter_tween != null and _typewriter_tween.is_valid():
		_typewriter_tween.kill()
	_typewriter_tween = null
	_is_typing = false


# ---------------------------------------------------------------------------
# Private — Choices
# ---------------------------------------------------------------------------


func _display_choices(choices: Array[Dictionary]) -> void:
	_clear_choices()
	var count: int = mini(choices.size(), MAX_VISIBLE_CHOICES)
	for i: int in range(count):
		var choice: Dictionary = choices[i]
		var button: Button = _create_choice_button(choice)
		button.modulate.a = 0.0
		_choices_container.add_child(button)

		var tween: Tween = create_tween()
		tween.tween_interval(CHOICE_FADE_DELAY * float(i))
		tween.tween_property(button, "modulate:a", 1.0, CHOICE_FADE_DURATION)


func _create_choice_button(choice: Dictionary) -> Button:
	var button := Button.new()
	button.text = choice.get("text", "")
	button.custom_minimum_size = Vector2(MIN_TOUCH_TARGET, MIN_TOUCH_TARGET)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var choice_id: StringName = choice.get("id", &"")
	button.pressed.connect(func() -> void:
		choice_selected.emit(choice_id)
		if _dialogue_manager != null:
			_dialogue_manager.select_choice(choice_id)
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
	button.add_theme_font_size_override("font_size", 14)

	return button


func _clear_choices() -> void:
	for child: Node in _choices_container.get_children():
		child.queue_free()


# ---------------------------------------------------------------------------
# Private — NPC Color
# ---------------------------------------------------------------------------


func _set_npc_color(npc_id: StringName) -> void:
	var color: Color = _get_npc_color(npc_id)
	_name_label.add_theme_color_override("font_color", color)


func _get_npc_color(_npc_id: StringName) -> Color:
	var ca: Node = get_node_or_null("/root/ColorAccumulation")
	if ca != null and ca.has_method("get_npc_color"):
		var c: Variant = ca.get_npc_color(_npc_id)
		if c is Color:
			return c
	return DEFAULT_NPC_COLOR


# ---------------------------------------------------------------------------
# Private — Signal Wiring
# ---------------------------------------------------------------------------


func _connect_dialogue_manager() -> void:
	_dialogue_manager = get_node_or_null("/root/DialogueManager")
	if _dialogue_manager == null:
		return
	if _dialogue_manager.has_signal("dialogue_started"):
		_dialogue_manager.dialogue_started.connect(_on_dialogue_started)
	if _dialogue_manager.has_signal("node_displayed"):
		_dialogue_manager.node_displayed.connect(_on_node_displayed)
	if _dialogue_manager.has_signal("dialogue_ended"):
		_dialogue_manager.dialogue_ended.connect(_on_dialogue_ended)


func _on_dialogue_started(npc_id: StringName) -> void:
	if _dialogue_manager == null:
		return
	var speaker_name: String = _get_speaker_name(npc_id)
	var text: String = _dialogue_manager.get_current_text()
	var choices: Array[Dictionary] = []
	if _dialogue_manager.has_method("get_available_choices"):
		choices = _dialogue_manager.get_available_choices()
	show_panel(npc_id, speaker_name, text, choices)


func _on_node_displayed(_node_id: StringName, _text: String) -> void:
	if _dialogue_manager == null:
		return
	var speaker_name: String = _get_speaker_name(_dialogue_manager._active_npc)
	var text: String = _dialogue_manager.get_current_text()
	var choices: Array[Dictionary] = []
	if _dialogue_manager.has_method("get_available_choices"):
		choices = _dialogue_manager.get_available_choices()
	var npc_color: Color = _get_npc_color(_dialogue_manager._active_npc)
	update_node(speaker_name, text, choices, npc_color)


func _on_dialogue_ended(_npc_id: StringName) -> void:
	hide_panel()


func _on_end_button_pressed() -> void:
	end_dialogue_requested.emit()
	if _dialogue_manager != null:
		_dialogue_manager.end_dialogue()


func _get_speaker_name(npc_id: StringName) -> String:
	if npc_id == &"player":
		return "你"
	var mgr: Node = get_node_or_null("/root/NPCManager")
	if mgr != null and mgr.has_method("get_display_name"):
		var n: Variant = mgr.get_display_name(npc_id)
		if n is String and n != "":
			return n
	return String(npc_id)
