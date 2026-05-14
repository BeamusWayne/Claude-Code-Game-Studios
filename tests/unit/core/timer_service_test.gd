extends GdUnitTestSuite

## Tests for TimerService — countdown, pressure curve, phase transitions,
## time_scale, serialization, and signal emission.
## Covers ADR-0008 validation criteria.


const TIMER_SERVICE_SCRIPT := "res://src/core/timer_service.gd"

var _timer: Node
var _started_events: Array
var _ended_events: Array
var _phase_events: Array
var _pressure_events: Array


func before_test() -> void:
	_timer = Node.new()
	_timer.set_script(load(TIMER_SERVICE_SCRIPT))
	_timer.name = "TimerServiceTest"
	add_child(_timer)
	_started_events = []
	_ended_events = []
	_phase_events = []
	_pressure_events = []
	_timer.night_timer_started.connect(func(n, d): _started_events.append({"night": n, "duration": d}))
	_timer.night_timer_ended.connect(func(n): _ended_events.append(n))
	_timer.phase_changed.connect(func(o, p): _phase_events.append({"old": o, "new": p}))
	_timer.pressure_updated.connect(func(p): _pressure_events.append(p))


func after_test() -> void:
	if _timer:
		_timer.queue_free()


# ---------------------------------------------------------------------------
# Default state & curve
# ---------------------------------------------------------------------------


func test_initial_state() -> void:
	assert_float(_timer.pressure_level).is_equal(0.0)
	assert_int(_timer.current_phase).is_equal(0)
	assert_float(_timer.remaining_time).is_equal(0.0)
	assert_float(_timer.total_duration).is_equal(0.0)
	assert_float(_timer.time_scale).is_equal(1.0)
	assert_bool(_timer.is_active).is_false()


func test_default_curve_created_when_null() -> void:
	assert_object(_timer.pressure_curve).is_not_null()
	assert_float(_timer.pressure_curve.sample(0.0)).is_equal_approx(0.0, 0.001)
	assert_float(_timer.pressure_curve.sample(0.5)).is_equal_approx(0.5, 0.001)
	assert_float(_timer.pressure_curve.sample(1.0)).is_equal_approx(1.0, 0.001)


# ---------------------------------------------------------------------------
# start_night_timer
# ---------------------------------------------------------------------------


func test_start_night_timer_sets_state() -> void:
	_timer.start_night_timer()
	assert_bool(_timer.is_active).is_true()
	assert_float(_timer.remaining_time).is_equal(300.0)
	assert_float(_timer.total_duration).is_equal(300.0)
	assert_float(_timer.pressure_level).is_equal(0.0)
	assert_int(_timer.current_phase).is_equal(0)
	assert_float(_timer.time_scale).is_equal(1.0)


func test_start_night_timer_emits_started_signal() -> void:
	_timer.start_night_timer()
	assert_int(_started_events.size()).is_equal(1)
	assert_int(_started_events[0]["night"]).is_equal(1)
	assert_float(_started_events[0]["duration"]).is_equal(300.0)


func test_start_night_timer_resets_previous_state() -> void:
	_timer.start_night_timer()
	_timer.remaining_time = 100.0
	_timer.pressure_level = 0.5
	_timer.current_phase = 1
	_timer.time_scale = 0.5
	_timer.start_night_timer()
	assert_float(_timer.remaining_time).is_equal(300.0)
	assert_float(_timer.pressure_level).is_equal(0.0)
	assert_int(_timer.current_phase).is_equal(0)
	assert_float(_timer.time_scale).is_equal(1.0)


func test_start_night_timer_clamps_duration_to_min() -> void:
	_timer.base_duration = 30.0
	_timer.min_night_duration = 60.0
	_timer.start_night_timer()
	assert_float(_timer.total_duration).is_equal(60.0)


# ---------------------------------------------------------------------------
# stop_timer
# ---------------------------------------------------------------------------


func test_stop_timer_deactivates() -> void:
	_timer.start_night_timer()
	_timer.stop_timer()
	assert_bool(_timer.is_active).is_false()


func test_stop_timer_does_not_clear_remaining_time() -> void:
	_timer.start_night_timer()
	_timer._process(10.0)
	_timer.stop_timer()
	assert_float(_timer.remaining_time).is_equal(290.0)
	assert_bool(_timer.is_active).is_false()


# ---------------------------------------------------------------------------
# set_time_scale
# ---------------------------------------------------------------------------


func test_set_time_scale_clamps_to_valid_range() -> void:
	_timer.set_time_scale(0.5)
	assert_float(_timer.time_scale).is_equal(0.5)
	_timer.set_time_scale(2.0)
	assert_float(_timer.time_scale).is_equal(1.0)
	_timer.set_time_scale(-0.5)
	assert_float(_timer.time_scale).is_equal(0.0)
	_timer.set_time_scale(0.0)
	assert_float(_timer.time_scale).is_equal(0.0)
	_timer.set_time_scale(1.0)
	assert_float(_timer.time_scale).is_equal(1.0)


# ---------------------------------------------------------------------------
# _process: countdown and pressure
# ---------------------------------------------------------------------------


func test_process_counts_down_with_delta() -> void:
	_timer.start_night_timer()
	_timer._process(10.0)
	assert_float(_timer.remaining_time).is_equal(290.0)


func test_process_applies_time_scale() -> void:
	_timer.start_night_timer()
	_timer.set_time_scale(0.5)
	_timer._process(10.0)
	assert_float(_timer.remaining_time).is_equal(295.0)


func test_process_time_scale_zero_freezes_countdown() -> void:
	_timer.start_night_timer()
	_timer.set_time_scale(0.0)
	_timer._process(10.0)
	assert_float(_timer.remaining_time).is_equal(300.0)


func test_process_pressure_at_midpoint() -> void:
	_timer.start_night_timer()
	_timer.remaining_time = 150.0
	_timer._process(0.001)
	assert_float(_timer.pressure_level).is_greater(0.49)
	assert_float(_timer.pressure_level).is_less(0.51)


func test_process_pressure_at_end() -> void:
	_timer.start_night_timer()
	_timer.remaining_time = 0.0
	_timer._process(0.0)
	assert_float(_timer.pressure_level).is_equal_approx(1.0, 0.001)


func test_process_pressure_clamps_output() -> void:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.5, 2.0))
	curve.add_point(Vector2(1.0, 1.0))
	_timer.pressure_curve = curve
	_timer.start_night_timer()
	_timer.remaining_time = 150.0
	_timer._process(0.001)
	assert_float(_timer.pressure_level).is_equal(1.0)


# ---------------------------------------------------------------------------
# Phase transitions
# ---------------------------------------------------------------------------


func test_phase_starts_calm() -> void:
	_timer.start_night_timer()
	assert_int(_timer.current_phase).is_equal(0)


func test_phase_transition_calm_to_intense() -> void:
	_timer.start_night_timer()
	_timer.remaining_time = 210.0
	_timer._process(0.001)
	assert_int(_timer.current_phase).is_equal(1)
	assert_int(_phase_events.size()).is_greater_equal(1)
	if _phase_events.size() > 0:
		assert_int(_phase_events[_phase_events.size() - 1]["old"]).is_equal(0)
		assert_int(_phase_events[_phase_events.size() - 1]["new"]).is_equal(1)


func test_phase_transition_intense_to_critical() -> void:
	_timer.start_night_timer()
	_timer.current_phase = 1
	_timer.remaining_time = 90.0
	_timer._process(0.001)
	assert_int(_timer.current_phase).is_equal(2)
	assert_int(_phase_events.size()).is_greater_equal(1)
	if _phase_events.size() > 0:
		var last: Dictionary = _phase_events[_phase_events.size() - 1]
		assert_int(last["old"]).is_equal(1)
		assert_int(last["new"]).is_equal(2)


func test_phase_no_transition_when_below_threshold() -> void:
	_timer.start_night_timer()
	_timer.remaining_time = 240.0
	var phases_before: int = _phase_events.size()
	_timer._process(0.001)
	assert_int(_timer.current_phase).is_equal(0)
	assert_int(_phase_events.size()).is_equal(phases_before)


func test_determine_phase_boundary_values() -> void:
	assert_int(_timer._determine_phase(0.3)).is_equal(1)
	assert_int(_timer._determine_phase(0.7)).is_equal(2)
	assert_int(_timer._determine_phase(0.299)).is_equal(0)
	assert_int(_timer._determine_phase(0.5)).is_equal(1)
	assert_int(_timer._determine_phase(0.99)).is_equal(2)


# ---------------------------------------------------------------------------
# Timer expiry
# ---------------------------------------------------------------------------


func test_timer_expiry_deactivates() -> void:
	_timer.start_night_timer()
	_timer.remaining_time = 1.0
	_timer._process(1.0)
	assert_bool(_timer.is_active).is_false()
	assert_float(_timer.remaining_time).is_equal(0.0)


func test_timer_expiry_emits_ended_signal() -> void:
	_timer.start_night_timer()
	_timer.remaining_time = 1.0
	_timer._process(1.0)
	assert_int(_ended_events.size()).is_greater_equal(1)


func test_timer_does_not_process_after_expiry() -> void:
	_timer.start_night_timer()
	_timer.remaining_time = 0.0
	_timer._process(1.0)
	var ended_count: int = _ended_events.size()
	var pressure_count: int = _pressure_events.size()
	_timer._process(1.0)
	assert_int(_ended_events.size()).is_equal(ended_count)
	assert_int(_pressure_events.size()).is_equal(pressure_count)


func test_timer_remaining_never_goes_negative() -> void:
	_timer.start_night_timer()
	_timer.remaining_time = 5.0
	_timer._process(10.0)
	assert_float(_timer.remaining_time).is_equal(0.0)


# ---------------------------------------------------------------------------
# Pressure updated signal
# ---------------------------------------------------------------------------


func test_pressure_updated_emitted_on_change() -> void:
	_timer.start_night_timer()
	_timer._process(10.0)
	assert_int(_pressure_events.size()).is_greater(0)
	assert_float(_pressure_events[_pressure_events.size() - 1]).is_greater(0.03)
	assert_float(_pressure_events[_pressure_events.size() - 1]).is_less(0.04)


func test_pressure_not_emitted_when_unchanged() -> void:
	_timer.start_night_timer()
	_timer._process(0.0)
	var count_before: int = _pressure_events.size()
	_timer._process(0.0)
	assert_int(_pressure_events.size()).is_equal(count_before)


# ---------------------------------------------------------------------------
# Serialization round-trip
# ---------------------------------------------------------------------------


func test_serialize_deserialize_roundtrip() -> void:
	_timer.start_night_timer()
	_timer._process(50.0)
	_timer.set_time_scale(0.75)

	var data: Dictionary = _timer.serialize()
	assert_float(data["remaining_time"]).is_equal(250.0)
	assert_float(data["total_duration"]).is_equal(300.0)
	assert_float(data["pressure_level"]).is_greater(0.0)
	assert_float(data["time_scale"]).is_equal(0.75)
	assert_bool(data["is_active"]).is_true()

	var fresh := Node.new()
	fresh.set_script(load(TIMER_SERVICE_SCRIPT))
	add_child(fresh)
	fresh.deserialize(data)

	assert_float(fresh.remaining_time).is_equal(250.0)
	assert_float(fresh.total_duration).is_equal(300.0)
	assert_float(fresh.pressure_level).is_equal(data["pressure_level"])
	assert_int(fresh.current_phase).is_equal(data["current_phase"])
	assert_float(fresh.time_scale).is_equal(0.75)
	assert_bool(fresh.is_active).is_true()

	fresh.queue_free()


func test_deserialize_defaults_for_missing_keys() -> void:
	var fresh := Node.new()
	fresh.set_script(load(TIMER_SERVICE_SCRIPT))
	add_child(fresh)
	fresh.deserialize({})
	assert_float(fresh.remaining_time).is_equal(0.0)
	assert_float(fresh.total_duration).is_equal(0.0)
	assert_float(fresh.pressure_level).is_equal(0.0)
	assert_int(fresh.current_phase).is_equal(0)
	assert_float(fresh.time_scale).is_equal(1.0)
	assert_bool(fresh.is_active).is_false()
	fresh.queue_free()


func test_serialize_captures_inactive_state() -> void:
	_timer.start_night_timer()
	_timer.stop_timer()
	var data: Dictionary = _timer.serialize()
	assert_bool(data["is_active"]).is_false()


func test_deserialize_restores_inactive_timer_without_processing() -> void:
	_timer.start_night_timer()
	_timer.stop_timer()
	var data: Dictionary = _timer.serialize()
	var fresh := Node.new()
	fresh.set_script(load(TIMER_SERVICE_SCRIPT))
	add_child(fresh)
	fresh.deserialize(data)
	assert_bool(fresh.is_active).is_false()
	fresh.queue_free()


# ---------------------------------------------------------------------------
# _create_default_curve
# ---------------------------------------------------------------------------


func test_create_default_curve_is_linear() -> void:
	var curve: Curve = _timer._create_default_curve()
	assert_object(curve).is_not_null()
	assert_int(curve.get_point_count()).is_equal(2)
	assert_float(curve.sample(0.0)).is_equal_approx(0.0, 0.001)
	assert_float(curve.sample(0.25)).is_equal_approx(0.25, 0.001)
	assert_float(curve.sample(0.5)).is_equal_approx(0.5, 0.001)
	assert_float(curve.sample(0.75)).is_equal_approx(0.75, 0.001)
	assert_float(curve.sample(1.0)).is_equal_approx(1.0, 0.001)


# ---------------------------------------------------------------------------
# Night ready auto-start
# ---------------------------------------------------------------------------


func test_on_night_ready_starts_timer() -> void:
	_timer._on_night_ready(3)
	assert_bool(_timer.is_active).is_true()
	assert_int(_started_events.size()).is_greater_equal(1)


func test_night_ready_callback_restarts_timer() -> void:
	_timer.start_night_timer()
	_timer._process(100.0)
	assert_float(_timer.remaining_time).is_less(300.0)
	_timer._on_night_ready(2)
	assert_float(_timer.remaining_time).is_equal(300.0)
	assert_bool(_timer.is_active).is_true()
