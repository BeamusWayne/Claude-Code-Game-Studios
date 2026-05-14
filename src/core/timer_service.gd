extends Node

## Autoload singleton that owns the countdown timer and pressure_level state.
## Produces pressure_level each frame for the ink wash shader (ADR-0001).
## Phase thresholds align with ADR-0001 shader pressure ranges.

signal night_timer_started(night: int, duration: float)
signal night_timer_ended(night: int)
signal phase_changed(old_phase: int, new_phase: int)
signal pressure_updated(pressure_level: float)

enum PressurePhase { CALM, INTENSE, CRITICAL }

## Phase thresholds aligned with ADR-0001 shader pressure ranges.
const CALM_MAX: float = 0.3
const INTENSE_MAX: float = 0.7

@export var pressure_curve: Curve
@export var base_duration: float = 180.0
@export var min_night_duration: float = 60.0

var pressure_level: float = 0.0
var current_phase: PressurePhase = PressurePhase.CALM
var remaining_time: float = 0.0
var total_duration: float = 0.0
var time_scale: float = 1.0
var is_active: bool = false


func _ready() -> void:
	set_process(false)
	if pressure_curve == null:
		pressure_curve = _create_default_curve()
	_connect_loop_state_manager()


## Start the countdown for the current night. Resets all timer state.
func start_night_timer() -> void:
	var night: int = _get_current_night()
	var duration: float = _calculate_night_duration(night)
	remaining_time = duration
	total_duration = duration
	pressure_level = 0.0
	current_phase = PressurePhase.CALM
	time_scale = 1.0
	is_active = true
	set_process(true)
	night_timer_started.emit(night, duration)


## Stop the timer and disable per-frame processing.
func stop_timer() -> void:
	is_active = false
	set_process(false)


## Set the time scale for countdown speed modulation (0.0 = paused, 1.0 = normal).
func set_time_scale(scale: float) -> void:
	time_scale = clampf(scale, 0.0, 1.0)


func _process(delta: float) -> void:
	if not is_active:
		return

	var scaled_delta: float = delta * time_scale
	remaining_time = maxf(0.0, remaining_time - scaled_delta)

	var progress: float = 1.0 - (remaining_time / total_duration) if total_duration > 0.0 else 1.0
	var new_pressure: float = pressure_curve.sample(clampf(progress, 0.0, 1.0))
	new_pressure = clampf(new_pressure, 0.0, 1.0)

	if not is_equal_approx(new_pressure, pressure_level):
		pressure_level = new_pressure
		pressure_updated.emit(pressure_level)

	var new_phase: PressurePhase = _determine_phase(pressure_level)
	if new_phase != current_phase:
		var old: PressurePhase = current_phase
		current_phase = new_phase
		phase_changed.emit(old, new_phase)

	if remaining_time <= 0.0 and is_active:
		is_active = false
		set_process(false)
		night_timer_ended.emit(_get_current_night())


## Serialize timer state for save/load persistence (ADR-0010).
func serialize() -> Dictionary:
	return {
		"remaining_time": remaining_time,
		"total_duration": total_duration,
		"pressure_level": pressure_level,
		"current_phase": current_phase,
		"time_scale": time_scale,
		"is_active": is_active,
	}


## Restore timer state from serialized data.
func deserialize(data: Dictionary) -> void:
	remaining_time = data.get("remaining_time", 0.0)
	total_duration = data.get("total_duration", 0.0)
	pressure_level = data.get("pressure_level", 0.0)
	current_phase = data.get("current_phase", PressurePhase.CALM) as PressurePhase
	time_scale = data.get("time_scale", 1.0)
	is_active = data.get("is_active", false)
	set_process(is_active)


# ---------------------------------------------------------------------------
# Private methods
# ---------------------------------------------------------------------------


## Connect to LoopStateManager.night_ready if the autoload is present.
## Guarded so tests without the real autoload do not crash.
func _connect_loop_state_manager() -> void:
	var loop_state: Node = get_node_or_null("/root/LoopStateManager")
	if loop_state != null and loop_state.has_signal("night_ready"):
		loop_state.night_ready.connect(_on_night_ready)


## Get the current night number from LoopStateManager.
## Returns 1 as default when the autoload is not available (e.g. in tests).
func _get_current_night() -> int:
	var loop_state: Node = get_node_or_null("/root/LoopStateManager")
	if loop_state != null and loop_state.has_method("get_current_night"):
		return loop_state.get_current_night()
	return 1


## Calculate night duration. Currently constant (base_duration).
## Future: RHYTHM_TABLE will provide per-night variation.
func _calculate_night_duration(_night: int) -> float:
	return maxf(min_night_duration, base_duration)


## Determine the pressure phase from a pressure level value.
func _determine_phase(pressure: float) -> PressurePhase:
	if pressure >= INTENSE_MAX:
		return PressurePhase.CRITICAL
	if pressure >= CALM_MAX:
		return PressurePhase.INTENSE
	return PressurePhase.CALM


## Callback for LoopStateManager.night_ready signal.
func _on_night_ready(_night: int) -> void:
	start_night_timer()


## Create a default linear curve from (0,0) to (1,1).
func _create_default_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0), Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(1.0, 1.0), Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return curve
