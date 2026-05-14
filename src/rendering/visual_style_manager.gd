class_name VisualStyleManager
extends Node

## Scene-level visual orchestrator for the ink wash shader pipeline.
## Manages visual state transitions, per-room parameters, discovery animations,
## and night-end sequences. Coordinates InkWashDriver, ColorAccumulationManager,
## and TimerService into a cohesive visual experience.
## GDD: design/gdd/ink-wash-visual-style.md System #18

signal visual_state_changed(old_state: int, new_state: int)

enum VisualState {
	EXPLORATION,
	DIALOGUE,
	CLUE_CONNECTION,
	WHISPER,
	ROAR,
	NIGHT_END,
	DISCOVERY,
}

# -- Tuning knobs ---------------------------------------------------------------

var discovery_duration: float = 1.5
var discovery_knowledge_boost: float = 1.0
var night_end_flood_duration: float = 2.0
var night_end_hold_duration: float = 1.0
var night_end_drain_duration: float = 2.0
var roar_saturation_penalty: float = 0.2
var roar_vignette_tighten: float = 0.4
var room_transition_duration: float = 1.0
var transition_ease_curve: float = -2.0

# -- State ----------------------------------------------------------------------

var current_state: VisualState = VisualState.EXPLORATION
var current_room_id: StringName = &""
var is_discovery_animating: bool = false
var is_night_end_animating: bool = false

var _previous_state: VisualState = VisualState.EXPLORATION
var _transition_from: VisualParams = null
var _transition_to: VisualParams = null
var _transition_elapsed: float = 0.0
var _transition_duration: float = 1.0
var _is_transitioning: bool = false

# Discovery animation state
var _discovery_elapsed: float = 0.0
var _discovery_pending: bool = false

# Night-end animation state
var _night_end_phase: int = 0  # 0=flood, 1=hold, 2=drain
var _night_end_elapsed: float = 0.0

# Room config
var _room_temperature_offset: float = 0.0
var _room_rain_intensity: float = 0.5
var _room_ink_density_base: float = 0.5

# Current interpolated params (output of _process)
var _current_params: VisualParams = null

# -- DI seams (override in tests) -----------------------------------------------

var _color_accumulation_override: Node = null
var _timer_service_override: Node = null
var _ink_wash_driver_override: Node = null
var _room_manager_override: Node = null
var _night_transition_override: Node = null
var _clue_database_override: Node = null


func _ready() -> void:
	_current_params = VisualParams.exploration()
	_connect_signals()


func _process(delta: float) -> void:
	# Night-end animation takes priority over everything.
	if is_night_end_animating:
		_process_night_end(delta)
		return

	# Discovery animation runs on top of current state.
	if is_discovery_animating:
		_process_discovery(delta)
		return

	# Normal state transition interpolation.
	if _is_transitioning:
		_transition_elapsed += delta
		var progress: float = clampf(_transition_elapsed / _transition_duration, 0.0, 1.0)
		var eased: float = ease(progress, transition_ease_curve)
		_current_params = VisualParams.lerp_params(_transition_from, _transition_to, eased)
		if progress >= 1.0:
			_is_transitioning = false
			_current_params = _transition_to

	_apply_params_to_driver()


func request_state(new_state: VisualState) -> void:
	if new_state == current_state:
		return

	var old_state: VisualState = current_state
	_previous_state = current_state
	current_state = new_state

	_transition_from = _current_params
	_transition_to = _build_target_params(new_state)
	_transition_elapsed = 0.0
	_transition_duration = _transition_to.transition_duration
	_is_transitioning = true

	visual_state_changed.emit(old_state, new_state)


func set_room(room_id: StringName) -> void:
	if room_id == current_room_id:
		return
	current_room_id = room_id
	var config: Dictionary = _get_room_config(room_id)
	_room_temperature_offset = config.get("temperature", 0.0)
	_room_rain_intensity = config.get("rain", 0.5)
	_room_ink_density_base = config.get("density", 0.5)

	if _is_transitioning:
		_transition_to = _build_target_params(current_state)
	else:
		_transition_from = _current_params
		_transition_to = _build_target_params(current_state)
		_transition_elapsed = 0.0
		_transition_duration = room_transition_duration
		_is_transitioning = true


func trigger_discovery() -> void:
	if is_night_end_animating:
		_discovery_pending = true
		return
	_start_discovery_animation()


func trigger_night_end_sequence() -> void:
	is_night_end_animating = true
	_night_end_phase = 0
	_night_end_elapsed = 0.0
	_transition_from = _current_params
	_transition_to = VisualParams.night_end_flood()
	_transition_elapsed = 0.0
	_transition_duration = night_end_flood_duration
	_is_transitioning = true


func get_target_params() -> VisualParams:
	if _is_transitioning:
		return _transition_to
	return _current_params


# -- Internal -------------------------------------------------------------------


func _process_night_end(delta: float) -> void:
	_night_end_elapsed += delta

	match _night_end_phase:
		0:  # Flood
			var progress: float = clampf(_night_end_elapsed / night_end_flood_duration, 0.0, 1.0)
			_current_params = VisualParams.lerp_params(_transition_from, VisualParams.night_end_flood(), ease(progress, transition_ease_curve))
			if progress >= 1.0:
				_night_end_phase = 1
				_night_end_elapsed = 0.0
				_current_params = VisualParams.night_end_flood()
		1:  # Hold
			if _night_end_elapsed >= night_end_hold_duration:
				_night_end_phase = 2
				_night_end_elapsed = 0.0
				_transition_from = VisualParams.night_end_flood()
		2:  # Drain
			var progress: float = clampf(_night_end_elapsed / night_end_drain_duration, 0.0, 1.0)
			_current_params = VisualParams.lerp_params(_transition_from, VisualParams.night_end_drain(), ease(progress, transition_ease_curve))
			if progress >= 1.0:
				is_night_end_animating = false
				_current_params = VisualParams.night_end_drain()
				if _discovery_pending:
					_discovery_pending = false
					_start_discovery_animation()

	_apply_params_to_driver()


func _process_discovery(delta: float) -> void:
	_discovery_elapsed += delta
	var progress: float = clampf(_discovery_elapsed / discovery_duration, 0.0, 1.0)
	var eased: float = ease(progress, transition_ease_curve)

	var base_knowledge: float = _get_knowledge_level()
	var boosted: float = lerpf(discovery_knowledge_boost, base_knowledge, eased)
	_current_params.knowledge_multiplier = boosted / maxf(base_knowledge, 0.001) if base_knowledge > 0.001 else 1.0
	_current_params.temperature_offset = lerpf(0.15, _room_temperature_offset, eased)

	if progress >= 1.0:
		is_discovery_animating = false
		_current_params = _build_target_params(current_state)

	_apply_params_to_driver()


func _start_discovery_animation() -> void:
	is_discovery_animating = true
	_discovery_elapsed = 0.0


func _build_target_params(state: VisualState) -> VisualParams:
	var base: VisualParams
	match state:
		VisualState.EXPLORATION:
			base = VisualParams.exploration()
		VisualState.DIALOGUE:
			base = VisualParams.dialogue()
			base.transition_duration = 1.0
		VisualState.CLUE_CONNECTION:
			base = VisualParams.clue_connection()
			base.transition_duration = 1.0
		VisualState.WHISPER:
			base = VisualParams.whisper()
			base.transition_duration = 4.0
		VisualState.ROAR:
			base = VisualParams.roar()
			base.transition_duration = 1.5
		VisualState.NIGHT_END:
			base = VisualParams.night_end_flood()
		VisualState.DISCOVERY:
			base = VisualParams.exploration()
		_:
			base = VisualParams.exploration()

	if state != VisualState.ROAR and state != VisualState.NIGHT_END:
		base.temperature_offset = _room_temperature_offset
		base.rain_intensity = _room_rain_intensity
		base.ink_density_base = _room_ink_density_base

	return base


func _apply_params_to_driver() -> void:
	var driver: Node = _get_ink_wash_driver()
	if driver == null:
		return

	var knowledge: float = _get_knowledge_level() * _current_params.knowledge_multiplier
	var pressure: float = _get_pressure_level() * _current_params.pressure_multiplier

	if driver.has_method("set_knowledge_level"):
		driver.set_knowledge_level(clampf(knowledge, 0.0, 1.0))
	if driver.has_method("set_pressure_level"):
		driver.set_pressure_level(clampf(pressure, 0.0, 1.0))
	if driver.has_method("set_rain_intensity"):
		driver.set_rain_intensity(clampf(_current_params.rain_intensity, 0.0, 1.0))


func _get_knowledge_level() -> float:
	var ca: Node = _get_color_accumulation()
	if ca and "effective_knowledge" in ca:
		return ca.effective_knowledge
	return 0.0


func _get_pressure_level() -> float:
	var ts: Node = _get_timer_service()
	if ts and "pressure_level" in ts:
		return ts.pressure_level
	return 0.0


# -- Room configuration ---------------------------------------------------------


func _get_room_config(room_id: StringName) -> Dictionary:
	var configs: Dictionary = {
		&"lobby": {"temperature": 0.1, "rain": 0.4, "density": 0.5},
		&"dining_hall": {"temperature": 0.15, "rain": 0.3, "density": 0.4},
		&"guest_room_a": {"temperature": 0.0, "rain": 0.5, "density": 0.6},
		&"guest_room_b": {"temperature": 0.1, "rain": 0.5, "density": 0.5},
		&"study": {"temperature": -0.1, "rain": 0.3, "density": 0.7},
		&"corridor": {"temperature": -0.05, "rain": 0.6, "density": 0.6},
		&"basement": {"temperature": -0.2, "rain": 0.2, "density": 0.8},
		&"attic": {"temperature": -0.15, "rain": 0.7, "density": 0.5},
	}
	if configs.has(room_id):
		return configs[room_id]
	push_warning("VisualStyleManager: unknown room '%s', using defaults" % room_id)
	return {"temperature": 0.0, "rain": 0.5, "density": 0.5}


# -- Signal connections ---------------------------------------------------------


func _connect_signals() -> void:
	var ntc: Node = _get_night_transition()
	if ntc and ntc.has_signal("night_transition_started"):
		Signal(ntc, "night_transition_started").connect(_on_night_transition_started)

	var ts: Node = _get_timer_service()
	if ts and ts.has_signal("phase_changed"):
		Signal(ts, "phase_changed").connect(_on_phase_changed)

	var db: Node = _get_clue_database()
	if db and db.has_signal("insight_generated"):
		Signal(db, "insight_generated").connect(_on_insight_generated)


func _on_night_transition_started(_night: int) -> void:
	trigger_night_end_sequence()


func _on_phase_changed(_old_phase: int, new_phase: int) -> void:
	match new_phase:
		0:  # CALM
			if current_state == VisualState.WHISPER or current_state == VisualState.ROAR:
				request_state(VisualState.EXPLORATION)
		1:  # INTENSE
			if current_state != VisualState.ROAR:
				request_state(VisualState.WHISPER)
		2:  # CRITICAL
			request_state(VisualState.ROAR)


func _on_insight_generated(_insight_id: StringName) -> void:
	trigger_discovery()


# -- DI seam implementations ----------------------------------------------------


func _get_color_accumulation() -> Node:
	if _color_accumulation_override != null:
		return _color_accumulation_override
	return get_node_or_null("/root/ColorAccumulationManager")


func _get_timer_service() -> Node:
	if _timer_service_override != null:
		return _timer_service_override
	return get_node_or_null("/root/TimerService")


func _get_ink_wash_driver() -> Node:
	if _ink_wash_driver_override != null:
		return _ink_wash_driver_override
	return get_node_or_null("/root/InkWashDriver")


func _get_room_manager() -> Node:
	if _room_manager_override != null:
		return _room_manager_override
	return get_node_or_null("/root/RoomManager")


func _get_night_transition() -> Node:
	if _night_transition_override != null:
		return _night_transition_override
	return get_node_or_null("/root/NightTransitionController")


func _get_clue_database() -> Node:
	if _clue_database_override != null:
		return _clue_database_override
	return get_node_or_null("/root/ClueDatabase")


# -- Reset (for tests) ----------------------------------------------------------


func reset() -> void:
	current_state = VisualState.EXPLORATION
	_previous_state = VisualState.EXPLORATION
	_transition_from = null
	_transition_to = null
	_transition_elapsed = 0.0
	_is_transitioning = false
	is_discovery_animating = false
	is_night_end_animating = false
	_discovery_elapsed = 0.0
	_discovery_pending = false
	_night_end_phase = 0
	_night_end_elapsed = 0.0
	_room_temperature_offset = 0.0
	_room_rain_intensity = 0.5
	_room_ink_density_base = 0.5
	_current_params = VisualParams.exploration()
