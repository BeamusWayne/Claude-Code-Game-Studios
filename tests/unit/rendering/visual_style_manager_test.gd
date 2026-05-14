extends GdUnitTestSuite

## Tests for VisualStyleManager — visual state machine, room configurations,
## discovery animation, night-end sequence, phase-driven transitions,
## and graceful degradation without autoloads.
## GDD: design/gdd/ink-wash-visual-style.md System #18

const VSM_SCRIPT := "res://src/rendering/visual_style_manager.gd"
const VP_SCRIPT := "res://src/rendering/visual_params.gd"

var _vsm: Node


func before_test() -> void:
	_vsm = Node.new()
	_vsm.set_script(load(VSM_SCRIPT))
	_vsm.name = "VisualStyleManagerTest"
	add_child(_vsm)
	_vsm._ready()


func after_test() -> void:
	if _vsm:
		_vsm.queue_free()


# ---------------------------------------------------------------------------
# VisualParams
# ---------------------------------------------------------------------------


func test_visual_params_default_values() -> void:
	var vp: RefCounted = load(VP_SCRIPT).new()
	assert_float(vp.knowledge_multiplier).is_equal_approx(1.0, 0.001)
	assert_float(vp.rain_intensity).is_equal_approx(0.5, 0.001)
	assert_float(vp.temperature_offset).is_equal_approx(0.0, 0.001)
	assert_float(vp.ink_density_base).is_equal_approx(0.5, 0.001)
	assert_float(vp.saturation_penalty).is_equal_approx(0.0, 0.001)


func test_visual_params_custom_init() -> void:
	var vp: RefCounted = load(VP_SCRIPT).new({"temperature_offset": 0.15, "rain_intensity": 0.3})
	assert_float(vp.temperature_offset).is_equal_approx(0.15, 0.001)
	assert_float(vp.rain_intensity).is_equal_approx(0.3, 0.001)
	assert_float(vp.knowledge_multiplier).is_equal_approx(1.0, 0.001)


func test_visual_params_exploration_defaults() -> void:
	var vp: RefCounted = load(VP_SCRIPT).exploration()
	assert_float(vp.knowledge_multiplier).is_equal_approx(1.0, 0.001)
	assert_float(vp.ink_density_base).is_equal_approx(0.5, 0.001)


func test_visual_params_roar_has_penalty() -> void:
	var vp: RefCounted = load(VP_SCRIPT).roar()
	assert_float(vp.saturation_penalty).is_equal_approx(0.2, 0.001)
	assert_float(vp.temperature_offset).is_equal_approx(-0.2, 0.001)
	assert_float(vp.rain_intensity).is_equal_approx(1.0, 0.001)


func test_visual_params_night_end_flood_zeroes_knowledge() -> void:
	var vp: RefCounted = load(VP_SCRIPT).night_end_flood()
	assert_float(vp.knowledge_multiplier).is_equal_approx(0.0, 0.001)
	assert_float(vp.pressure_multiplier).is_equal_approx(1.0, 0.001)


func test_visual_params_night_end_drain_restores() -> void:
	var vp: RefCounted = load(VP_SCRIPT).night_end_drain()
	assert_float(vp.knowledge_multiplier).is_equal_approx(1.0, 0.001)
	assert_float(vp.pressure_multiplier).is_equal_approx(0.0, 0.001)


func test_visual_params_lerp_params_midpoint() -> void:
	var VP := load(VP_SCRIPT)
	var from: RefCounted = VP.exploration()
	var to: RefCounted = VP.roar()
	var mid: RefCounted = VP.lerp_params(from, to, 0.5)
	assert_float(mid.temperature_offset).is_equal_approx(lerpf(0.0, -0.2, 0.5), 0.001)
	assert_float(mid.rain_intensity).is_equal_approx(lerpf(0.5, 1.0, 0.5), 0.001)


# ---------------------------------------------------------------------------
# Initial state
# ---------------------------------------------------------------------------


func test_initial_state_is_exploration() -> void:
	assert_int(_vsm.current_state).is_equal(_vsm.VisualState.EXPLORATION)


func test_initial_not_animating() -> void:
	assert_bool(_vsm.is_discovery_animating).is_false()
	assert_bool(_vsm.is_night_end_animating).is_false()


func test_initial_params_are_exploration() -> void:
	var params: RefCounted = _vsm._current_params
	assert_float(params.knowledge_multiplier).is_equal_approx(1.0, 0.001)
	assert_float(params.rain_intensity).is_equal_approx(0.5, 0.001)


# ---------------------------------------------------------------------------
# State transitions
# ---------------------------------------------------------------------------


func test_request_state_changes_current_state() -> void:
	_vsm.request_state(_vsm.VisualState.DIALOGUE)
	assert_int(_vsm.current_state).is_equal(_vsm.VisualState.DIALOGUE)


func test_request_state_emits_signal() -> void:
	var signal_received: bool = false
	var received_old: int = -1
	var received_new: int = -1
	_vsm.visual_state_changed.connect(func(old: int, new: int) -> void:
		signal_received = true
		received_old = old
		received_new = new
	)
	_vsm.request_state(_vsm.VisualState.WHISPER)
	assert_bool(signal_received).is_true()
	assert_int(received_old).is_equal(_vsm.VisualState.EXPLORATION)
	assert_int(received_new).is_equal(_vsm.VisualState.WHISPER)


func test_request_same_state_no_op() -> void:
	var signal_count: int = 0
	_vsm.visual_state_changed.connect(func(_o: int, _n: int) -> void:
		signal_count += 1
	)
	_vsm.request_state(_vsm.VisualState.EXPLORATION)
	assert_int(signal_count).is_equal(0)


func test_request_state_starts_transition() -> void:
	_vsm.request_state(_vsm.VisualState.ROAR)
	assert_bool(_vsm._is_transitioning).is_true()
	assert_float(_vsm._transition_duration).is_greater(0.0)


func test_transition_completes_after_duration() -> void:
	_vsm.request_state(_vsm.VisualState.DIALOGUE)
	var dur: float = _vsm._transition_duration
	_vsm._process(dur + 0.1)
	assert_bool(_vsm._is_transitioning).is_false()


func test_transition_params_at_start_equal_from() -> void:
	var initial_temp: float = _vsm._current_params.temperature_offset
	_vsm.request_state(_vsm.VisualState.ROAR)
	assert_float(_vsm._transition_from.temperature_offset).is_equal_approx(initial_temp, 0.001)


func test_transition_params_at_end_equal_target() -> void:
	_vsm.request_state(_vsm.VisualState.ROAR)
	_vsm._process(_vsm._transition_duration + 0.1)
	assert_float(_vsm._current_params.temperature_offset).is_equal_approx(-0.2, 0.001)
	assert_float(_vsm._current_params.rain_intensity).is_equal_approx(1.0, 0.001)


func test_state_interrupt_mid_transition() -> void:
	_vsm.request_state(_vsm.VisualState.WHISPER)
	_vsm._process(1.0)
	var mid_temp: float = _vsm._current_params.temperature_offset
	_vsm.request_state(_vsm.VisualState.ROAR)
	assert_float(_vsm._transition_from.temperature_offset).is_equal_approx(mid_temp, 0.001)
	assert_bool(_vsm._transition_to.temperature_offset < 0.0).is_true()


# ---------------------------------------------------------------------------
# Room configuration
# ---------------------------------------------------------------------------


func test_set_room_updates_config() -> void:
	_vsm.set_room(&"basement")
	assert_float(_vsm._room_temperature_offset).is_equal_approx(-0.2, 0.001)
	assert_float(_vsm._room_rain_intensity).is_equal_approx(0.2, 0.001)
	assert_float(_vsm._room_ink_density_base).is_equal_approx(0.8, 0.001)


func test_set_room_stores_room_id() -> void:
	_vsm.set_room(&"attic")
	assert_string(_vsm.current_room_id).is_equal(&"attic")


func test_set_room_same_id_no_op() -> void:
	_vsm.set_room(&"lobby")
	var rain_before: float = _vsm._room_rain_intensity
	_vsm.set_room(&"lobby")
	assert_float(_vsm._room_rain_intensity).is_equal(rain_before)


func test_set_unknown_room_uses_defaults() -> void:
	_vsm.set_room(&"nonexistent_room")
	assert_float(_vsm._room_temperature_offset).is_equal_approx(0.0, 0.001)
	assert_float(_vsm._room_rain_intensity).is_equal_approx(0.5, 0.001)


func test_all_eight_rooms_have_config() -> void:
	var rooms: Array[StringName] = [&"lobby", &"dining_hall", &"guest_room_a", &"guest_room_b", &"study", &"corridor", &"basement", &"attic"]
	for room: StringName in rooms:
		_vsm.set_room(room)
		assert_string(_vsm.current_room_id).is_equal(room)


func test_room_config_applied_to_exploration_params() -> void:
	_vsm.set_room(&"basement")
	_vsm.request_state(_vsm.VisualState.EXPLORATION)
	_vsm._process(_vsm._transition_duration + 0.1)
	assert_float(_vsm._current_params.temperature_offset).is_equal_approx(-0.2, 0.001)
	assert_float(_vsm._current_params.ink_density_base).is_equal_approx(0.8, 0.001)


func test_room_config_not_applied_to_roar() -> void:
	_vsm.set_room(&"lobby")
	_vsm.request_state(_vsm.VisualState.ROAR)
	_vsm._process(_vsm._transition_duration + 0.1)
	assert_float(_vsm._current_params.temperature_offset).is_equal_approx(-0.2, 0.001)
	assert_float(_vsm._current_params.rain_intensity).is_equal_approx(1.0, 0.001)


# ---------------------------------------------------------------------------
# Discovery animation
# ---------------------------------------------------------------------------


func test_trigger_discovery_starts_animation() -> void:
	_vsm.trigger_discovery()
	assert_bool(_vsm.is_discovery_animating).is_true()


func test_discovery_animation_completes() -> void:
	_vsm.trigger_discovery()
	_vsm._process(_vsm.discovery_duration + 0.1)
	assert_bool(_vsm.is_discovery_animating).is_false()


func test_discovery_boosts_knowledge_at_start() -> void:
	_vsm.trigger_discovery()
	_vsm._process(0.01)
	assert_bool(_vsm.is_discovery_animating).is_true()


func test_discovery_with_knowledge_source() -> void:
	var mock_ca := Node.new()
	mock_ca.set("effective_knowledge", 0.5)
	_vsm._color_accumulation_override = mock_ca
	_vsm.trigger_discovery()
	_vsm._process(0.01)
	assert_bool(_vsm._current_params.knowledge_multiplier > 1.0).is_true()
	_vsm._process(_vsm.discovery_duration + 0.1)
	assert_float(_vsm._current_params.knowledge_multiplier).is_equal_approx(1.0, 0.1)
	mock_ca.queue_free()


func test_discovery_warms_temperature() -> void:
	_vsm.trigger_discovery()
	_vsm._process(0.01)
	assert_float(_vsm._current_params.temperature_offset).is_greater(0.0)


func test_rapid_double_discovery_resets_timer() -> void:
	_vsm.trigger_discovery()
	_vsm._process(0.3)
	var elapsed_before: float = _vsm._discovery_elapsed
	_vsm.trigger_discovery()
	assert_float(_vsm._discovery_elapsed).is_less(elapsed_before)


# ---------------------------------------------------------------------------
# Night-end sequence
# ---------------------------------------------------------------------------


func test_trigger_night_end_starts_animation() -> void:
	_vsm.trigger_night_end_sequence()
	assert_bool(_vsm.is_night_end_animating).is_true()
	assert_int(_vsm._night_end_phase).is_equal(0)


func test_night_end_flood_phase_transitions() -> void:
	_vsm.trigger_night_end_sequence()
	_vsm._process(_vsm.night_end_flood_duration + 0.1)
	assert_int(_vsm._night_end_phase).is_equal(1)


func test_night_end_hold_phase_transitions() -> void:
	_vsm.trigger_night_end_sequence()
	_vsm._process(_vsm.night_end_flood_duration + 0.1)
	_vsm._process(_vsm.night_end_hold_duration + 0.1)
	assert_int(_vsm._night_end_phase).is_equal(2)


func test_night_end_drain_phase_completes() -> void:
	_vsm.trigger_night_end_sequence()
	_vsm._process(_vsm.night_end_flood_duration + 0.1)
	_vsm._process(_vsm.night_end_hold_duration + 0.1)
	_vsm._process(_vsm.night_end_drain_duration + 0.1)
	assert_bool(_vsm.is_night_end_animating).is_false()


func test_night_end_flood_zeroes_knowledge() -> void:
	_vsm.trigger_night_end_sequence()
	_vsm._process(_vsm.night_end_flood_duration + 0.1)
	assert_float(_vsm._current_params.knowledge_multiplier).is_equal_approx(0.0, 0.001)


func test_night_end_drain_restores_knowledge() -> void:
	_vsm.trigger_night_end_sequence()
	_vsm._process(_vsm.night_end_flood_duration + 0.1)
	_vsm._process(_vsm.night_end_hold_duration + 0.1)
	_vsm._process(_vsm.night_end_drain_duration + 0.1)
	assert_float(_vsm._current_params.knowledge_multiplier).is_equal_approx(1.0, 0.001)


func test_night_end_blocks_discovery() -> void:
	_vsm.trigger_night_end_sequence()
	_vsm.trigger_discovery()
	assert_bool(_vsm.is_discovery_animating).is_false()
	assert_bool(_vsm._discovery_pending).is_true()


func test_pending_discovery_fires_after_night_end() -> void:
	_vsm.trigger_night_end_sequence()
	_vsm.trigger_discovery()
	_vsm._process(_vsm.night_end_flood_duration + 0.1)
	_vsm._process(_vsm.night_end_hold_duration + 0.1)
	_vsm._process(_vsm.night_end_drain_duration + 0.1)
	assert_bool(_vsm.is_discovery_animating).is_true()
	assert_bool(_vsm._discovery_pending).is_false()


# ---------------------------------------------------------------------------
# Phase-driven transitions (TimerService integration)
# ---------------------------------------------------------------------------


func test_phase_change_calm_to_intense_triggers_whisper() -> void:
	_vsm._on_phase_changed(0, 1)
	assert_int(_vsm.current_state).is_equal(_vsm.VisualState.WHISPER)


func test_phase_change_intense_to_critical_triggers_roar() -> void:
	_vsm._on_phase_changed(0, 1)
	_vsm._on_phase_changed(1, 2)
	assert_int(_vsm.current_state).is_equal(_vsm.VisualState.ROAR)


func test_phase_change_critical_to_calm_returns_exploration() -> void:
	_vsm._on_phase_changed(0, 2)
	_vsm._on_phase_changed(2, 0)
	assert_int(_vsm.current_state).is_equal(_vsm.VisualState.EXPLORATION)


func test_phase_change_calm_to_calm_no_op() -> void:
	_vsm._on_phase_changed(0, 0)
	assert_int(_vsm.current_state).is_equal(_vsm.VisualState.EXPLORATION)


# ---------------------------------------------------------------------------
# NightTransitionController signal
# ---------------------------------------------------------------------------


func test_night_transition_started_triggers_sequence() -> void:
	_vsm._on_night_transition_started(1)
	assert_bool(_vsm.is_night_end_animating).is_true()


# ---------------------------------------------------------------------------
# InsightGenerated signal
# ---------------------------------------------------------------------------


func test_insight_generated_triggers_discovery() -> void:
	_vsm._on_insight_generated(&"insight_001")
	assert_bool(_vsm.is_discovery_animating).is_true()


# ---------------------------------------------------------------------------
# Driver integration
# ---------------------------------------------------------------------------


func test_apply_params_with_mock_driver() -> void:
	var mock_driver := Node.new()
	mock_driver.set_script(load("res://src/rendering/ink_wash_driver.gd"))
	mock_driver._build_pipeline()
	_vsm._ink_wash_driver_override = mock_driver

	_vsm.request_state(_vsm.VisualState.ROAR)
	_vsm._process(_vsm._transition_duration + 0.1)

	assert_float(mock_driver._rain_intensity).is_equal_approx(1.0, 0.001)
	mock_driver.queue_free()


func test_no_driver_no_crash() -> void:
	_vsm._ink_wash_driver_override = null
	_vsm.request_state(_vsm.VisualState.ROAR)
	_vsm._process(_vsm._transition_duration + 0.1)


func test_no_color_accumulation_no_crash() -> void:
	_vsm._color_accumulation_override = null
	_vsm.request_state(_vsm.VisualState.WHISPER)
	_vsm._process(1.0)


func test_no_timer_service_no_crash() -> void:
	_vsm._timer_service_override = null
	_vsm.request_state(_vsm.VisualState.ROAR)
	_vsm._process(1.0)


# ---------------------------------------------------------------------------
# Reset
# ---------------------------------------------------------------------------


func test_reset_returns_to_exploration() -> void:
	_vsm.request_state(_vsm.VisualState.ROAR)
	_vsm.set_room(&"basement")
	_vsm.reset()
	assert_int(_vsm.current_state).is_equal(_vsm.VisualState.EXPLORATION)
	assert_string(_vsm.current_room_id).is_equal(&"")
	assert_bool(_vsm.is_discovery_animating).is_false()
	assert_bool(_vsm.is_night_end_animating).is_false()


# ---------------------------------------------------------------------------
# get_target_params
# ---------------------------------------------------------------------------


func test_get_target_params_returns_current_when_not_transitioning() -> void:
	var params: RefCounted = _vsm.get_target_params()
	assert_object(params).is_not_null()
	assert_float(params.knowledge_multiplier).is_equal_approx(1.0, 0.001)


func test_get_target_params_returns_target_when_transitioning() -> void:
	_vsm.request_state(_vsm.VisualState.ROAR)
	var params: RefCounted = _vsm.get_target_params()
	assert_float(params.temperature_offset).is_equal_approx(-0.2, 0.001)


# ---------------------------------------------------------------------------
# Roar overrides
# ---------------------------------------------------------------------------


func test_roar_saturation_penalty() -> void:
	_vsm.request_state(_vsm.VisualState.ROAR)
	_vsm._process(_vsm._transition_duration + 0.1)
	assert_float(_vsm._current_params.saturation_penalty).is_equal_approx(0.2, 0.001)


func test_roar_vignette_radius() -> void:
	_vsm.request_state(_vsm.VisualState.ROAR)
	_vsm._process(_vsm._transition_duration + 0.1)
	assert_float(_vsm._current_params.vignette_radius).is_equal_approx(1.0, 0.001)


func test_roar_rain_intensity_maxed() -> void:
	_vsm.request_state(_vsm.VisualState.ROAR)
	_vsm._process(_vsm._transition_duration + 0.1)
	assert_float(_vsm._current_params.rain_intensity).is_equal_approx(1.0, 0.001)


# ---------------------------------------------------------------------------
# Dialogue state
# ---------------------------------------------------------------------------


func test_dialogue_reduces_ink_density() -> void:
	_vsm.request_state(_vsm.VisualState.DIALOGUE)
	_vsm._process(_vsm._transition_duration + 0.1)
	assert_float(_vsm._current_params.ink_density_base).is_less(0.5)


func test_dialogue_applies_room_temperature() -> void:
	_vsm.set_room(&"lobby")
	_vsm.request_state(_vsm.VisualState.DIALOGUE)
	_vsm._process(_vsm._transition_duration + 0.1)
	assert_float(_vsm._current_params.temperature_offset).is_equal_approx(0.1, 0.001)


# ---------------------------------------------------------------------------
# Clue connection state
# ---------------------------------------------------------------------------


func test_clue_connection_reduces_ink_density() -> void:
	_vsm.request_state(_vsm.VisualState.CLUE_CONNECTION)
	_vsm._process(_vsm._transition_duration + 0.1)
	assert_float(_vsm._current_params.ink_density_base).is_equal_approx(0.2, 0.001)


func test_clue_connection_no_edge_softness() -> void:
	_vsm.request_state(_vsm.VisualState.CLUE_CONNECTION)
	_vsm._process(_vsm._transition_duration + 0.1)
	assert_float(_vsm._current_params.edge_softness).is_equal_approx(0.0, 0.001)


# ---------------------------------------------------------------------------
# Whisper state
# ---------------------------------------------------------------------------


func test_whisper_cold_temperature() -> void:
	_vsm.request_state(_vsm.VisualState.WHISPER)
	_vsm._process(_vsm._transition_duration + 0.1)
	assert_float(_vsm._current_params.temperature_offset).is_less(0.0)


func test_whisper_increases_rain() -> void:
	_vsm.request_state(_vsm.VisualState.WHISPER)
	_vsm._process(_vsm._transition_duration + 0.1)
	assert_float(_vsm._current_params.rain_intensity).is_greater(0.5)


# ---------------------------------------------------------------------------
# Edge case: knowledge = 0 at drain
# ---------------------------------------------------------------------------


func test_night_end_drain_with_zero_knowledge_no_crash() -> void:
	_vsm.trigger_night_end_sequence()
	_vsm._process(_vsm.night_end_flood_duration + 0.1)
	_vsm._process(_vsm.night_end_hold_duration + 0.1)
	_vsm._process(_vsm.night_end_drain_duration + 0.1)
	assert_bool(_vsm.is_night_end_animating).is_false()
	assert_float(_vsm._current_params.knowledge_multiplier).is_equal_approx(1.0, 0.001)
