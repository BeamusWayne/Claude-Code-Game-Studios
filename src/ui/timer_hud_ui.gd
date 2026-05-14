extends CanvasLayer

## TimerHUDUI -- displays countdown timer, pressure bar, and phase indicator.
## CanvasLayer 10, below room navigation (20) and dialogue (40).
## Listens to TimerService and ColorAccumulationManager signals.
## GDD: design/gdd/timer-hud.md, ADR-0001, ADR-0008

signal hud_visibility_changed(is_visible: bool)

const HUD_LAYER: int = 10
const BAR_WIDTH: float = 200.0
const BAR_HEIGHT: float = 8.0
const TIME_FONT_SIZE: int = 18
const PHASE_FONT_SIZE: int = 12
const FADE_DURATION: float = 0.2
const GOLD_OCHRE: Color = Color(0.8, 0.467, 0.133)
const SEAL_BORDER_COLOR: Color = Color(0.545, 0.0, 0.0)
const INK_TEXT_COLOR: Color = Color(0.172, 0.172, 0.172)
const BAR_BG_COLOR: Color = Color(1.0, 1.0, 1.0, 0.6)

## Phase display labels keyed by PressurePhase enum value (0=CALM, 1=INTENSE, 2=CRITICAL).
const PHASE_LABELS: Dictionary = {
	0: "平静",
	1: "紧张",
	2: "危急",
}

## Phase colors aligned with ADR-0001 shader pressure ranges.
const PHASE_CALM_COLOR: Color = Color(0.6, 0.6, 0.6, 0.8)
const PHASE_INTENSE_COLOR: Color = Color(0.545, 0.0, 0.0, 0.9)
const PHASE_CRITICAL_COLOR: Color = Color(0.0, 0.0, 0.0, 1.0)

var _timer_service: Node = null
var _color_accumulation: Node = null
var _dialogue_manager: Node = null
var _notebook_manager: Node = null

var _knowledge_level: float = 0.0
var _is_dialogue_active: bool = false
var _is_notebook_open: bool = false
var _target_visible: bool = false
var _fade_tween: Tween = null

var _root_container: Control
var _time_label: Label
var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _phase_label: Label


func _ready() -> void:
	layer = HUD_LAYER
	_build_ui()
	_connect_services()
	_update_visibility()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


## Refresh all HUD visuals from current service state.
func update_display() -> void:
	_update_time_text()
	_update_bar_fill()
	_update_bar_color()
	_update_phase_label()
	_update_visibility()


## Format seconds into M:SS display string.
static func format_time(seconds: float) -> String:
	var total_secs: int = int(seconds)
	var mins: int = total_secs / 60
	var secs: int = total_secs % 60
	return "%d:%02d" % [mins, secs]


## Returns true if the HUD is currently intended to be visible.
func is_hud_visible() -> bool:
	return _target_visible


## Returns the current bar fill color including knowledge blend.
func get_bar_color() -> Color:
	var phase_color: Color = _get_phase_color()
	return _apply_knowledge_tint(phase_color)


## Override TimerService reference (dependency injection for tests).
func set_timer_service(service: Node) -> void:
	_timer_service = service


## Override ColorAccumulationManager reference (dependency injection for tests).
func set_color_accumulation(manager: Node) -> void:
	_color_accumulation = manager


## Override DialogueManager reference (dependency injection for tests).
func set_dialogue_manager(manager: Node) -> void:
	_dialogue_manager = manager


## Override NotebookManager reference (dependency injection for tests).
func set_notebook_manager(manager: Node) -> void:
	_notebook_manager = manager


# ---------------------------------------------------------------------------
# Private -- UI Construction
# ---------------------------------------------------------------------------


func _build_ui() -> void:
	_root_container = Control.new()
	_root_container.name = "HUDContainer"
	_root_container.anchor_left = 0.5
	_root_container.anchor_right = 0.5
	_root_container.anchor_top = 0.0
	_root_container.anchor_bottom = 0.0
	_root_container.offset_left = -BAR_WIDTH / 2.0
	_root_container.offset_right = BAR_WIDTH / 2.0
	_root_container.offset_top = 8.0
	_root_container.offset_bottom = 60.0
	_root_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_container)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_container.add_child(vbox)

	_time_label = Label.new()
	_time_label.name = "TimeLabel"
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.add_theme_font_size_override("font_size", TIME_FONT_SIZE)
	_time_label.add_theme_color_override("font_color", INK_TEXT_COLOR)
	_time_label.text = "0:00"
	_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_time_label)

	var bar_container := Control.new()
	bar_container.name = "BarContainer"
	bar_container.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT + 4.0)
	bar_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(bar_container)

	_bar_bg = ColorRect.new()
	_bar_bg.name = "BarBackground"
	_bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar_bg.color = BAR_BG_COLOR
	bar_container.add_child(_bar_bg)

	_bar_fill = ColorRect.new()
	_bar_fill.name = "BarFill"
	_bar_fill.anchor_left = 0.0
	_bar_fill.anchor_right = 0.0
	_bar_fill.anchor_top = 0.0
	_bar_fill.anchor_bottom = 1.0
	_bar_fill.offset_top = 2.0
	_bar_fill.offset_bottom = -2.0
	_bar_fill.offset_left = 2.0
	_bar_fill.color = PHASE_CALM_COLOR
	bar_container.add_child(_bar_fill)

	_phase_label = Label.new()
	_phase_label.name = "PhaseLabel"
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.add_theme_font_size_override("font_size", PHASE_FONT_SIZE)
	_phase_label.add_theme_color_override("font_color", INK_TEXT_COLOR)
	_phase_label.text = PHASE_LABELS[0]
	_phase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_phase_label)

	_root_container.modulate.a = 0.0


# ---------------------------------------------------------------------------
# Private -- Signal Wiring
# ---------------------------------------------------------------------------


func _connect_services() -> void:
	_timer_service = _get_timer_service()
	if _timer_service != null:
		if _timer_service.has_signal("pressure_updated"):
			_timer_service.pressure_updated.connect(_on_pressure_updated)
		if _timer_service.has_signal("phase_changed"):
			_timer_service.phase_changed.connect(_on_phase_changed)
		if _timer_service.has_signal("night_timer_started"):
			_timer_service.night_timer_started.connect(_on_night_timer_started)
		if _timer_service.has_signal("night_timer_ended"):
			_timer_service.night_timer_ended.connect(_on_night_timer_ended)

	_color_accumulation = _get_color_accumulation()
	if _color_accumulation != null:
		if _color_accumulation.has_signal("knowledge_level_changed"):
			_color_accumulation.knowledge_level_changed.connect(_on_knowledge_level_changed)

	_dialogue_manager = _get_dialogue_manager()
	if _dialogue_manager != null:
		if _dialogue_manager.has_signal("dialogue_started"):
			_dialogue_manager.dialogue_started.connect(_on_dialogue_started)
		if _dialogue_manager.has_signal("dialogue_ended"):
			_dialogue_manager.dialogue_ended.connect(_on_dialogue_ended)

	_notebook_manager = _get_notebook_manager()
	if _notebook_manager != null:
		if _notebook_manager.has_signal("notebook_opened"):
			_notebook_manager.notebook_opened.connect(_on_notebook_opened)
		if _notebook_manager.has_signal("notebook_closed"):
			_notebook_manager.notebook_closed.connect(_on_notebook_closed)


# ---------------------------------------------------------------------------
# Private -- Display Updates
# ---------------------------------------------------------------------------


func _update_time_text() -> void:
	if _time_label == null or _timer_service == null:
		return
	if not "remaining_time" in _timer_service:
		return
	_time_label.text = format_time(_timer_service.remaining_time)


func _update_bar_fill() -> void:
	if _bar_fill == null or _timer_service == null:
		return
	var pressure: float = 0.0
	if "pressure_level" in _timer_service:
		pressure = _timer_service.pressure_level
	_bar_fill.anchor_right = clampf(pressure, 0.0, 1.0)


func _update_bar_color() -> void:
	if _bar_fill == null:
		return
	_bar_fill.color = get_bar_color()


func _update_phase_label() -> void:
	if _phase_label == null or _timer_service == null:
		return
	var phase: int = 0
	if "current_phase" in _timer_service:
		phase = _timer_service.current_phase
	_phase_label.text = PHASE_LABELS.get(phase, PHASE_LABELS[0])


func _get_phase_color() -> Color:
	if _timer_service == null or not "current_phase" in _timer_service:
		return PHASE_CALM_COLOR
	var phase: int = _timer_service.current_phase
	match phase:
		0:
			return PHASE_CALM_COLOR
		1:
			return PHASE_INTENSE_COLOR
		2:
			return PHASE_CRITICAL_COLOR
		_:
			return PHASE_CALM_COLOR


func _apply_knowledge_tint(phase_color: Color) -> Color:
	var tint_amount: float = _knowledge_level * 0.3
	return phase_color.lerp(GOLD_OCHRE, tint_amount)


# ---------------------------------------------------------------------------
# Private -- Visibility
# ---------------------------------------------------------------------------


func _compute_should_be_visible() -> bool:
	if _timer_service == null or not "is_active" in _timer_service:
		return false
	if not _timer_service.is_active:
		return false
	if _is_dialogue_active:
		return false
	if _is_notebook_open:
		return false
	return true


func _update_visibility() -> void:
	var should_show: bool = _compute_should_be_visible()
	if should_show == _target_visible:
		return
	_target_visible = should_show
	_fade_to(1.0 if should_show else 0.0)
	hud_visibility_changed.emit(should_show)


func _fade_to(target_alpha: float) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_root_container, "modulate:a", target_alpha, FADE_DURATION)


# ---------------------------------------------------------------------------
# Private -- Signal Callbacks
# ---------------------------------------------------------------------------


func _on_pressure_updated(_pressure_level: float) -> void:
	_update_bar_fill()
	_update_bar_color()


func _on_phase_changed(_old_phase: int, _new_phase: int) -> void:
	_update_phase_label()
	_update_bar_color()


func _on_knowledge_level_changed(new_level: float) -> void:
	_knowledge_level = clampf(new_level, 0.0, 1.0)
	_update_bar_color()


func _on_night_timer_started(_night: int, _duration: float) -> void:
	update_display()


func _on_night_timer_ended(_night: int) -> void:
	_update_time_text()
	_update_visibility()


func _on_dialogue_started(_npc_id: StringName) -> void:
	_is_dialogue_active = true
	_update_visibility()


func _on_dialogue_ended(_npc_id: StringName) -> void:
	_is_dialogue_active = false
	_update_visibility()


func _on_notebook_opened() -> void:
	_is_notebook_open = true
	_update_visibility()


func _on_notebook_closed() -> void:
	_is_notebook_open = false
	_update_visibility()


# ---------------------------------------------------------------------------
# Private -- DI Seams (override in tests)
# ---------------------------------------------------------------------------


func _get_timer_service() -> Node:
	return get_node_or_null("/root/TimerService")


func _get_color_accumulation() -> Node:
	return get_node_or_null("/root/ColorAccumulationManager")


func _get_dialogue_manager() -> Node:
	return get_node_or_null("/root/DialogueManager")


func _get_notebook_manager() -> Node:
	return get_node_or_null("/root/NotebookManager")
