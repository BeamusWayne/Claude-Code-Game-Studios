extends GdUnitTestSuite

## Tests for TimerHUDUI -- countdown display, pressure bar, phase indicator,
## knowledge color blend, visibility rules, and signal responses.
## Covers acceptance criteria from design/gdd/timer-hud.md and ADR-0008.

const HUD_SCRIPT := "res://src/ui/timer_hud_ui.gd"

var _hud: Node
var _mock_timer: Node
var _mock_color_accum: Node
var _mock_dialogue: Node
var _mock_notebook: Node

var _visibility_events: Array[bool]


func before_test() -> void:
	_mock_timer = Node.new()
	_mock_timer.name = "TimerService"
	_mock_timer.set_script(_create_timer_mock())
	add_child(_mock_timer)

	_mock_color_accum = Node.new()
	_mock_color_accum.name = "ColorAccumulationManager"
	_mock_color_accum.set_script(_create_color_accum_mock())
	add_child(_mock_color_accum)

	_mock_dialogue = Node.new()
	_mock_dialogue.name = "DialogueManager"
	_mock_dialogue.set_script(_create_dialogue_mock())
	add_child(_mock_dialogue)

	_mock_notebook = Node.new()
	_mock_notebook.name = "NotebookManager"
	_mock_notebook.set_script(_create_notebook_mock())
	add_child(_mock_notebook)

	_hud = auto_free(load(HUD_SCRIPT).new())
	_hud.set_timer_service(_mock_timer)
	_hud.set_color_accumulation(_mock_color_accum)
	_hud.set_dialogue_manager(_mock_dialogue)
	_hud.set_notebook_manager(_mock_notebook)
	add_child(_hud)

	_visibility_events = []
	_hud.hud_visibility_changed.connect(_on_visibility_changed)


func after_test() -> void:
	_mock_timer.queue_free()
	_mock_color_accum.queue_free()
	_mock_dialogue.queue_free()
	_mock_notebook.queue_free()


func _on_visibility_changed(is_visible: bool) -> void:
	_visibility_events.append(is_visible)


# ---------------------------------------------------------------------------
# Time Display -- Formatting
# ---------------------------------------------------------------------------


func test_format_time_zero_returns_0_00() -> void:
	assert_eq(_hud.format_time(0.0), "0:00")


func test_format_time_90_seconds_returns_1_30() -> void:
	assert_eq(_hud.format_time(90.0), "1:30")


func test_format_time_180_seconds_returns_3_00() -> void:
	assert_eq(_hud.format_time(180.0), "3:00")


func test_format_time_59_seconds_returns_0_59() -> void:
	assert_eq(_hud.format_time(59.0), "0:59")


func test_format_time_fractional_truncates() -> void:
	assert_eq(_hud.format_time(90.9), "1:30")


func test_format_time_300_seconds_returns_5_00() -> void:
	assert_eq(_hud.format_time(300.0), "5:00")


# ---------------------------------------------------------------------------
# Time Display -- Updates
# ---------------------------------------------------------------------------


func test_time_label_default_is_0_00() -> void:
	assert_eq(_hud._time_label.text, "0:00")


func test_update_display_shows_remaining_time() -> void:
	_mock_timer.remaining_time = 245.0
	_hud.update_display()
	assert_eq(_hud._time_label.text, "4:05")


func test_time_updates_on_night_timer_started() -> void:
	_mock_timer.remaining_time = 180.0
	_mock_timer.is_active = true
	_mock_timer.night_timer_started.emit(1, 180.0)
	assert_eq(_hud._time_label.text, "3:00")


func test_time_updates_on_night_timer_ended() -> void:
	_mock_timer.remaining_time = 0.0
	_mock_timer.is_active = false
	_mock_timer.night_timer_ended.emit(1)
	assert_eq(_hud._time_label.text, "0:00")


# ---------------------------------------------------------------------------
# Pressure Bar -- Fill Amount
# ---------------------------------------------------------------------------


func test_bar_fill_zero_by_default() -> void:
	assert_float(_hud._bar_fill.anchor_right).is_equal(0.0)


func test_bar_fill_matches_pressure_level() -> void:
	_mock_timer.pressure_level = 0.5
	_mock_timer.pressure_updated.emit(0.5)
	assert_float(_hud._bar_fill.anchor_right).is_equal(0.5)


func test_bar_fill_clamped_to_one() -> void:
	_mock_timer.pressure_level = 1.5
	_mock_timer.pressure_updated.emit(1.5)
	assert_float(_hud._bar_fill.anchor_right).is_equal(1.0)


func test_bar_fill_clamped_to_zero() -> void:
	_mock_timer.pressure_level = -0.5
	_hud._on_pressure_updated(-0.5)
	assert_float(_hud._bar_fill.anchor_right).is_equal(0.0)


func test_bar_fill_full_at_max_pressure() -> void:
	_mock_timer.pressure_level = 1.0
	_mock_timer.pressure_updated.emit(1.0)
	assert_float(_hud._bar_fill.anchor_right).is_equal(1.0)


# ---------------------------------------------------------------------------
# Pressure Bar -- Phase Colors
# ---------------------------------------------------------------------------


func test_bar_color_calm_phase() -> void:
	_mock_timer.current_phase = 0
	_mock_timer.pressure_level = 0.1
	_mock_timer.pressure_updated.emit(0.1)
	assert_color(_hud._bar_fill.color).is_equal(_hud.PHASE_CALM_COLOR)


func test_bar_color_intense_phase() -> void:
	_mock_timer.current_phase = 1
	_mock_timer.pressure_level = 0.5
	_mock_timer.pressure_updated.emit(0.5)
	assert_color(_hud._bar_fill.color).is_equal(_hud.PHASE_INTENSE_COLOR)


func test_bar_color_critical_phase() -> void:
	_mock_timer.current_phase = 2
	_mock_timer.pressure_level = 0.9
	_mock_timer.pressure_updated.emit(0.9)
	assert_color(_hud._bar_fill.color).is_equal(_hud.PHASE_CRITICAL_COLOR)


func test_bar_color_changes_on_phase_change() -> void:
	_mock_timer.current_phase = 0
	_hud.update_display()
	assert_color(_hud._bar_fill.color).is_equal(_hud.PHASE_CALM_COLOR)

	_mock_timer.current_phase = 2
	_mock_timer.phase_changed.emit(0, 2)
	assert_color(_hud._bar_fill.color).is_equal(_hud.PHASE_CRITICAL_COLOR)


# ---------------------------------------------------------------------------
# Phase Indicator -- Text
# ---------------------------------------------------------------------------


func test_phase_label_default_is_calm() -> void:
	assert_eq(_hud._phase_label.text, "平静")


func test_phase_label_calm() -> void:
	_mock_timer.current_phase = 0
	_hud.update_display()
	assert_eq(_hud._phase_label.text, "平静")


func test_phase_label_intense() -> void:
	_mock_timer.current_phase = 1
	_hud.update_display()
	assert_eq(_hud._phase_label.text, "紧张")


func test_phase_label_critical() -> void:
	_mock_timer.current_phase = 2
	_hud.update_display()
	assert_eq(_hud._phase_label.text, "危急")


func test_phase_label_updates_on_phase_changed_signal() -> void:
	_mock_timer.current_phase = 1
	_mock_timer.phase_changed.emit(0, 1)
	assert_eq(_hud._phase_label.text, "紧张")


func test_phase_label_unknown_falls_back_to_calm() -> void:
	_mock_timer.current_phase = 99
	_hud.update_display()
	assert_eq(_hud._phase_label.text, "平静")


# ---------------------------------------------------------------------------
# Knowledge Color Blend
# ---------------------------------------------------------------------------


func test_knowledge_zero_no_tint() -> void:
	_mock_timer.current_phase = 0
	_hud._knowledge_level = 0.0
	var color: Color = _hud.get_bar_color()
	assert_color(color).is_equal(_hud.PHASE_CALM_COLOR)


func test_knowledge_half_tints_toward_gold() -> void:
	_mock_timer.current_phase = 0
	_hud._knowledge_level = 0.5
	var color: Color = _hud.get_bar_color()
	var expected: Color = _hud.PHASE_CALM_COLOR.lerp(_hud.GOLD_OCHRE, 0.15)
	assert_float(color.r).is_equal_approx(expected.r, 0.001)
	assert_float(color.g).is_equal_approx(expected.g, 0.001)
	assert_float(color.b).is_equal_approx(expected.b, 0.001)


func test_knowledge_full_tints_toward_gold() -> void:
	_mock_timer.current_phase = 0
	_hud._knowledge_level = 1.0
	var color: Color = _hud.get_bar_color()
	var expected: Color = _hud.PHASE_CALM_COLOR.lerp(_hud.GOLD_OCHRE, 0.3)
	assert_float(color.r).is_equal_approx(expected.r, 0.001)
	assert_float(color.g).is_equal_approx(expected.g, 0.001)
	assert_float(color.b).is_equal_approx(expected.b, 0.001)


func test_knowledge_signal_updates_bar_color() -> void:
	_mock_timer.current_phase = 1
	_hud.update_display()
	var before: Color = _hud._bar_fill.color

	_mock_color_accum.knowledge_level_changed.emit(1.0)
	var after: Color = _hud._bar_fill.color
	assert_bool(before != after).is_true()


func test_knowledge_level_clamped_to_one() -> void:
	_mock_timer.current_phase = 0
	_mock_color_accum.knowledge_level_changed.emit(2.0)
	assert_float(_hud._knowledge_level).is_equal(1.0)


func test_knowledge_level_clamped_to_zero() -> void:
	_mock_color_accum.knowledge_level_changed.emit(-1.0)
	assert_float(_hud._knowledge_level).is_equal(0.0)


# ---------------------------------------------------------------------------
# Visibility -- Timer Active
# ---------------------------------------------------------------------------


func test_hud_hidden_when_timer_inactive() -> void:
	_mock_timer.is_active = false
	_hud.update_display()
	assert_bool(_hud.is_hud_visible()).is_false()


func test_hud_visible_when_timer_active() -> void:
	_mock_timer.is_active = true
	_hud.update_display()
	assert_bool(_hud.is_hud_visible()).is_true()


func test_hud_hidden_when_no_timer_service() -> void:
	_hud.set_timer_service(null)
	_hud.update_display()
	assert_bool(_hud.is_hud_visible()).is_false()


# ---------------------------------------------------------------------------
# Visibility -- Dialogue
# ---------------------------------------------------------------------------


func test_hud_hidden_during_dialogue() -> void:
	_mock_timer.is_active = true
	_hud.update_display()
	assert_bool(_hud.is_hud_visible()).is_true()

	_mock_dialogue.dialogue_started.emit(&"npc_01")
	assert_bool(_hud.is_hud_visible()).is_false()


func test_hud_shown_after_dialogue_ends() -> void:
	_mock_timer.is_active = true
	_mock_dialogue.dialogue_started.emit(&"npc_01")
	assert_bool(_hud.is_hud_visible()).is_false()

	_mock_dialogue.dialogue_ended.emit(&"npc_01")
	assert_bool(_hud.is_hud_visible()).is_true()


# ---------------------------------------------------------------------------
# Visibility -- Notebook
# ---------------------------------------------------------------------------


func test_hud_hidden_when_notebook_open() -> void:
	_mock_timer.is_active = true
	_hud.update_display()
	assert_bool(_hud.is_hud_visible()).is_true()

	_mock_notebook.notebook_opened.emit()
	assert_bool(_hud.is_hud_visible()).is_false()


func test_hud_shown_after_notebook_closed() -> void:
	_mock_timer.is_active = true
	_mock_notebook.notebook_opened.emit()
	assert_bool(_hud.is_hud_visible()).is_false()

	_mock_notebook.notebook_closed.emit()
	assert_bool(_hud.is_hud_visible()).is_true()


# ---------------------------------------------------------------------------
# Visibility -- Combined
# ---------------------------------------------------------------------------


func test_hud_hidden_dialogue_and_notebook() -> void:
	_mock_timer.is_active = true
	_mock_dialogue.dialogue_started.emit(&"npc_01")
	_mock_notebook.notebook_opened.emit()
	assert_bool(_hud.is_hud_visible()).is_false()

	# Close dialogue only -- still hidden
	_mock_dialogue.dialogue_ended.emit(&"npc_01")
	assert_bool(_hud.is_hud_visible()).is_false()

	# Close notebook -- now visible
	_mock_notebook.notebook_closed.emit()
	assert_bool(_hud.is_hud_visible()).is_true()


# ---------------------------------------------------------------------------
# Visibility -- Fade Signal
# ---------------------------------------------------------------------------


func test_visibility_changed_signal_emitted_on_show() -> void:
	_mock_timer.is_active = true
	_hud.update_display()
	assert_int(_visibility_events.size()).is_equal(1)
	assert_bool(_visibility_events[0]).is_true()


func test_visibility_changed_signal_emitted_on_hide() -> void:
	_mock_timer.is_active = true
	_hud.update_display()
	_mock_dialogue.dialogue_started.emit(&"npc_01")
	assert_int(_visibility_events.size()).is_equal(2)
	assert_bool(_visibility_events[1]).is_false()


func test_no_signal_when_visibility_unchanged() -> void:
	_mock_timer.is_active = false
	_hud.update_display()
	# Already hidden (default), no transition
	assert_int(_visibility_events.size()).is_equal(0)


# ---------------------------------------------------------------------------
# CanvasLayer
# ---------------------------------------------------------------------------


func test_canvas_layer_is_10() -> void:
	assert_int(_hud.layer).is_equal(10)


# ---------------------------------------------------------------------------
# UI Node Structure
# ---------------------------------------------------------------------------


func test_root_container_exists() -> void:
	assert_object(_hud._root_container).is_not_null()


func test_time_label_exists() -> void:
	assert_object(_hud._time_label).is_not_null()


func test_bar_fill_exists() -> void:
	assert_object(_hud._bar_fill).is_not_null()


func test_bar_bg_exists() -> void:
	assert_object(_hud._bar_bg).is_not_null()


func test_phase_label_exists() -> void:
	assert_object(_hud._phase_label).is_not_null()


func test_root_container_starts_transparent() -> void:
	assert_float(_hud._root_container.modulate.a).is_equal(0.0)


func test_time_label_font_size() -> void:
	assert_int(_hud._time_label.get_theme_font_size("font_size")).is_equal(18)


func test_phase_label_font_size() -> void:
	assert_int(_hud._phase_label.get_theme_font_size("font_size")).is_equal(12)


# ---------------------------------------------------------------------------
# Mock Scripts
# ---------------------------------------------------------------------------


func _create_timer_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal pressure_updated(pressure_level: float)\n"
		+ "signal phase_changed(old_phase: int, new_phase: int)\n"
		+ "signal night_timer_started(night: int, duration: float)\n"
		+ "signal night_timer_ended(night: int)\n"
		+ "var remaining_time: float = 0.0\n"
		+ "var pressure_level: float = 0.0\n"
		+ "var current_phase: int = 0\n"
		+ "var is_active: bool = false\n"
	)
	script.reload()
	return script


func _create_color_accum_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal knowledge_level_changed(new_level: float)\n"
		+ "var knowledge_level: float = 0.0\n"
	)
	script.reload()
	return script


func _create_dialogue_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal dialogue_started(npc_id: StringName)\n"
		+ "signal dialogue_ended(npc_id: StringName)\n"
		+ "var is_active: bool = false\n"
	)
	script.reload()
	return script


func _create_notebook_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal notebook_opened\n"
		+ "signal notebook_closed\n"
		+ "var is_open: bool = false\n"
	)
	script.reload()
	return script
