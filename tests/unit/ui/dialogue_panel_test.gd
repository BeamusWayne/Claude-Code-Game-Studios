extends GdUnitTestSuite

## Tests for DialoguePanel — UI rendering, typewriter, choices, animations.
## Covers GDD acceptance criteria from design/gdd/dialogue-ui.md.

const PANEL_SCRIPT := "res://src/ui/dialogue_panel.gd"

var _panel: Node
var _mock_dm: Node


func before_test() -> void:
	_panel = Node.new()
	_panel.set_script(load(PANEL_SCRIPT))
	add_child(_panel)

	_mock_dm = Node.new()
	_mock_dm.name = "DialogueManager"
	_mock_dm.set_script(_create_dm_mock())
	add_child(_mock_dm)

	_panel.set_dialogue_manager(_mock_dm)
	_panel.hide_panel_immediate()


func after_test() -> void:
	_panel.queue_free()
	_mock_dm.queue_free()


# ---------------------------------------------------------------------------
# Panel Visibility
# ---------------------------------------------------------------------------


func test_panel_hidden_by_default() -> void:
	assert_bool(_panel.visible).is_false()


func test_show_panel_makes_visible() -> void:
	_panel.show_panel(&"npc_01", "住客A", "你好", [])
	assert_bool(_panel.visible).is_true()


func test_hide_panel_immediate_hides() -> void:
	_panel.show_panel(&"npc_01", "住客A", "你好", [])
	_panel.hide_panel_immediate()
	assert_bool(_panel.visible).is_false()


# ---------------------------------------------------------------------------
# Speaker Name
# ---------------------------------------------------------------------------


func test_speaker_name_set_on_show() -> void:
	_panel.show_panel(&"npc_01", "靛蓝", "你好", [])
	var label: Node = _panel.get_node("Panel/VBox/NameLabel")
	assert_str(label.text).is_equal("靛蓝")


func test_speaker_name_player_shows_you() -> void:
	var name: String = _panel._get_speaker_name(&"player")
	assert_str(name).is_equal("你")


func test_speaker_name_unknown_npc_falls_back_to_id() -> void:
	var name: String = _panel._get_speaker_name(&"stranger")
	assert_str(name).is_equal("stranger")


# ---------------------------------------------------------------------------
# Typewriter
# ---------------------------------------------------------------------------


func test_typewriter_starts_on_show() -> void:
	_panel.show_panel(&"npc_01", "住客A", "你好世界", [])
	assert_bool(_panel.is_typing).is_true()


func test_typewriter_not_started_on_empty_text() -> void:
	_panel.show_panel(&"npc_01", "住客A", "", [])
	assert_bool(_panel.is_typing).is_false()


func test_skip_typewriter_shows_full_text() -> void:
	_panel.show_panel(&"npc_01", "住客A", "完整文本", [])
	_panel._skip_typewriter()
	assert_bool(_panel.is_typing).is_false()
	var label: Node = _panel.get_node("Panel/VBox/TextLabel")
	assert_str(label.text).is_equal("完整文本")


# ---------------------------------------------------------------------------
# Choices
# ---------------------------------------------------------------------------


func test_choices_displayed_in_container() -> void:
	var choices: Array[Dictionary] = [
		{"id": &"c1", "text": "选项一"},
		{"id": &"c2", "text": "选项二"},
	]
	_panel.show_panel(&"npc_01", "住客A", "你好", choices)
	_panel._skip_typewriter()

	var container: Node = _panel.get_node("Panel/VBox/ChoicesContainer")
	var children: Array = container.get_children()
	assert_int(children.size()).is_equal(2)


func test_max_five_choices_displayed() -> void:
	var choices: Array[Dictionary] = []
	for i: int in range(8):
		choices.append({"id": StringName("c%d" % i), "text": "选项%d" % i})
	_panel.show_panel(&"npc_01", "住客A", "你好", choices)

	var container: Node = _panel.get_node("Panel/VBox/ChoicesContainer")
	assert_int(container.get_children().size()).is_equal(5)


func test_no_choices_empty_container() -> void:
	_panel.show_panel(&"npc_01", "住客A", "你好", [])
	var container: Node = _panel.get_node("Panel/VBox/ChoicesContainer")
	assert_int(container.get_children().size()).is_equal(0)


func test_choices_cleared_on_new_node() -> void:
	var choices1: Array[Dictionary] = [
		{"id": &"c1", "text": "选项一"},
	]
	_panel.show_panel(&"npc_01", "住客A", "你好", choices1)

	var choices2: Array[Dictionary] = []
	_panel.update_node("住客A", "新文本", choices2, Color.WHITE)

	var container: Node = _panel.get_node("Panel/VBox/ChoicesContainer")
	assert_int(container.get_children().size()).is_equal(0)


# ---------------------------------------------------------------------------
# End Button
# ---------------------------------------------------------------------------


func test_end_button_always_visible() -> void:
	_panel.show_panel(&"npc_01", "住客A", "你好", [])
	var end_btn: Node = _panel.get_node("Panel/VBox/EndButton")
	assert_bool(end_btn.visible).is_true()


func test_end_button_text_is_farewell() -> void:
	var end_btn: Node = _panel.get_node("Panel/VBox/EndButton")
	assert_str(end_btn.text).is_equal("告辞")


func test_end_button_min_size() -> void:
	var end_btn: Node = _panel.get_node("Panel/VBox/EndButton")
	var min_size: Vector2 = end_btn.custom_minimum_size
	assert_bool(min_size.x >= 44.0).is_true()
	assert_bool(min_size.y >= 44.0).is_true()


# ---------------------------------------------------------------------------
# Touch Target Sizes
# ---------------------------------------------------------------------------


func test_choice_buttons_min_touch_target() -> void:
	var choices: Array[Dictionary] = [
		{"id": &"c1", "text": "短"},
		{"id": &"c2", "text": "较长的选项文本"},
	]
	_panel.show_panel(&"npc_01", "住客A", "你好", choices)

	var container: Node = _panel.get_node("Panel/VBox/ChoicesContainer")
	for child: Node in container.get_children():
		assert_bool(child.custom_minimum_size.x >= 44.0).is_true()
		assert_bool(child.custom_minimum_size.y >= 44.0).is_true()


# ---------------------------------------------------------------------------
# CanvasLayer
# ---------------------------------------------------------------------------


func test_canvas_layer_is_40() -> void:
	assert_int(_panel.layer).is_equal(40)


# ---------------------------------------------------------------------------
# Dimmer
# ---------------------------------------------------------------------------


func test_dimmer_zero_alpha_when_hidden() -> void:
	_panel.hide_panel_immediate()
	var dimmer: Node = _panel.get_node("Dimmer")
	assert_float(dimmer.color.a).is_equal(0.0)


func test_dimmer_exists() -> void:
	var dimmer: Node = _panel.get_node_or_null("Dimmer")
	assert_object(dimmer).is_not_null()


# ---------------------------------------------------------------------------
# NPC Color
# ---------------------------------------------------------------------------


func test_npc_color_defaults_to_white() -> void:
	var color: Color = _panel._get_npc_color(&"unknown_npc")
	assert_color(color).is_equal(Color.WHITE)


# ---------------------------------------------------------------------------
# Update Node
# ---------------------------------------------------------------------------


func test_update_node_changes_text() -> void:
	_panel.show_panel(&"npc_01", "住客A", "初始文本", [])
	_panel._skip_typewriter()

	_panel.update_node("住客A", "更新的文本", [], Color.WHITE)
	_panel._skip_typewriter()

	var label: Node = _panel.get_node("Panel/VBox/TextLabel")
	assert_str(label.text).is_equal("更新的文本")


func test_update_node_changes_speaker_name() -> void:
	_panel.show_panel(&"npc_01", "住客A", "你好", [])
	_panel.update_node("你", "我的回应", [], Color.WHITE)

	var label: Node = _panel.get_node("Panel/VBox/NameLabel")
	assert_str(label.text).is_equal("你")


func test_update_node_applies_npc_color() -> void:
	_panel.show_panel(&"npc_01", "住客A", "你好", [])
	var indigo_color: Color = Color(0.294, 0.0, 0.51)
	_panel.update_node("靛蓝", "新文本", [], indigo_color)

	var label: Node = _panel.get_node("Panel/VBox/NameLabel")
	var font_color: Color = label.get_theme_color("font_color")
	assert_color(font_color).is_equal(indigo_color)


# ---------------------------------------------------------------------------
# Choice Selection Signal
# ---------------------------------------------------------------------------


func test_choice_selected_signal_emitted() -> void:
	var choices: Array[Dictionary] = [
		{"id": &"choice_a", "text": "选项A"},
	]
	_panel.show_panel(&"npc_01", "住客A", "你好", choices)

	var signal_monitor := monitor(_panel, "choice_selected")
	var container: Node = _panel.get_node("Panel/VBox/ChoicesContainer")
	var button: Button = container.get_child(0) as Button
	button.emit_signal("pressed")

	assert_signal(signal_monitor).is_emitted_with([&"choice_a"])


# ---------------------------------------------------------------------------
# End Dialogue Request
# ---------------------------------------------------------------------------


func test_end_dialogue_requested_signal_on_button() -> void:
	_panel.show_panel(&"npc_01", "住客A", "你好", [])
	var signal_monitor := monitor(_panel, "end_dialogue_requested")
	var end_btn: Button = _panel.get_node("Panel/VBox/EndButton") as Button
	end_btn.emit_signal("pressed")
	assert_signal(signal_monitor).is_emitted()


# ---------------------------------------------------------------------------
# Edge Cases
# ---------------------------------------------------------------------------


func test_empty_text_no_crash() -> void:
	_panel.show_panel(&"npc_01", "住客A", "", [])
	assert_bool(_panel.visible).is_true()


func test_show_panel_while_animating_ignored() -> void:
	_panel.show_panel(&"npc_01", "住客A", "你好", [])
	_panel._animating = true
	_panel.show_panel(&"npc_02", "住客B", "第二段", [])
	var label: Node = _panel.get_node("Panel/VBox/NameLabel")
	assert_str(label.text).is_equal("住客A")


func test_hide_panel_while_animating_ignored() -> void:
	_panel.show_panel(&"npc_01", "住客A", "你好", [])
	_panel._animating = true
	_panel.hide_panel()
	assert_bool(_panel.visible).is_true()


func test_typewriter_killed_on_hide_immediate() -> void:
	_panel.show_panel(&"npc_01", "住客A", "长文本在这里", [])
	_panel.hide_panel_immediate()
	assert_bool(_panel.is_typing).is_false()


# ---------------------------------------------------------------------------
# Mock Scripts
# ---------------------------------------------------------------------------


func _create_dm_mock() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends Node\n"
		+ "signal dialogue_started(npc_id: StringName)\n"
		+ "signal dialogue_ended(npc_id: StringName)\n"
		+ "signal node_displayed(node_id: StringName, text: String)\n"
		+ "var _active_npc: StringName = &\"\"\n"
		+ "var _is_active: bool = false\n"
		+ "var _current_text: String = \"\"\n"
		+ "var _choices: Array[Dictionary] = []\n"
		+ "func get_current_text() -> String:\n"
		+ "\treturn _current_text\n"
		+ "func get_available_choices() -> Array[Dictionary]:\n"
		+ "\treturn _choices\n"
		+ "func select_choice(_id: StringName) -> void:\n"
		+ "\tpass\n"
		+ "func end_dialogue() -> void:\n"
		+ "\tpass\n"
	)
	script.reload()
	return script
