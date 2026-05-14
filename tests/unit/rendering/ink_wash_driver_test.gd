extends GdUnitTestSuite

## Tests for InkWashDriver — SubViewport pipeline, shader material setup,
## uniform updates, value clamping, and TimerService signal integration.
## Covers ADR-0001 requirements: shader parameter interface, pressure effects.
##
## Note: Shader parameter reads return null in headless mode (no GPU).
## Tests verify internal state, material existence, and pipeline structure.


const DRIVER_SCRIPT := "res://src/rendering/ink_wash_driver.gd"

var _driver: CanvasLayer


func before_test() -> void:
	_driver = CanvasLayer.new()
	_driver.set_script(load(DRIVER_SCRIPT))
	_driver.name = "InkWashDriverTest"
	add_child(_driver)
	_driver._build_pipeline()


func after_test() -> void:
	if _driver:
		_driver.queue_free()


func test_pipeline_builds_children() -> void:
	assert_int(_driver.get_child_count()).is_greater_equal(3)


func test_game_viewport_exists() -> void:
	var vp: SubViewport = _driver.get_game_viewport()
	assert_object(vp).is_not_null()
	assert_bool(vp is SubViewport).is_true()


func test_ink_material_exists() -> void:
	var ink_rect: Node = _driver.get_node_or_null("InkWashRect")
	assert_object(ink_rect).is_not_null()
	assert_bool(ink_rect.material is ShaderMaterial).is_true()


func test_rain_material_exists() -> void:
	var rain_rect: Node = _driver.get_node_or_null("RainRect")
	assert_object(rain_rect).is_not_null()
	assert_bool(rain_rect.material is ShaderMaterial).is_true()


func test_set_knowledge_level_clamped() -> void:
	_driver.set_knowledge_level(-0.5)
	assert_float(_driver._knowledge_level).is_equal_approx(0.0, 0.001)
	_driver.set_knowledge_level(1.5)
	assert_float(_driver._knowledge_level).is_equal_approx(1.0, 0.001)
	_driver.set_knowledge_level(0.6)
	assert_float(_driver._knowledge_level).is_equal_approx(0.6, 0.001)


func test_set_pressure_level_clamped() -> void:
	_driver.set_pressure_level(-1.0)
	assert_float(_driver._pressure_level).is_equal_approx(0.0, 0.001)
	_driver.set_pressure_level(2.0)
	assert_float(_driver._pressure_level).is_equal_approx(1.0, 0.001)


func test_set_rain_intensity_clamped() -> void:
	_driver.set_rain_intensity(-0.3)
	assert_float(_driver._rain_intensity).is_equal_approx(0.0, 0.001)
	_driver.set_rain_intensity(3.0)
	assert_float(_driver._rain_intensity).is_equal_approx(1.0, 0.001)


func test_process_updates_internal_time() -> void:
	_driver._process(0.016)
	assert_float(_driver._time_elapsed).is_greater(0.0)


func test_process_accumulates_time() -> void:
	_driver._process(0.016)
	_driver._process(0.016)
	_driver._process(0.016)
	assert_float(_driver._time_elapsed).is_equal_approx(0.048, 0.001)


func test_knowledge_level_drives_internal_state() -> void:
	_driver.set_knowledge_level(0.75)
	assert_float(_driver._knowledge_level).is_equal_approx(0.75, 0.001)


func test_pressure_level_drives_internal_state() -> void:
	_driver.set_pressure_level(0.5)
	assert_float(_driver._pressure_level).is_equal_approx(0.5, 0.001)


func test_rain_intensity_drives_internal_state() -> void:
	_driver.set_rain_intensity(0.8)
	assert_float(_driver._rain_intensity).is_equal_approx(0.8, 0.001)


func test_ink_material_has_shader_assigned() -> void:
	var ink_rect: Node = _driver.get_node("InkWashRect")
	var mat: ShaderMaterial = ink_rect.material
	assert_object(mat.shader).is_not_null()


func test_rain_material_has_shader_assigned() -> void:
	var rain_rect: Node = _driver.get_node("RainRect")
	var mat: ShaderMaterial = rain_rect.material
	assert_object(mat.shader).is_not_null()


func test_scene_texture_assigned() -> void:
	var ink_rect: Node = _driver.get_node("InkWashRect")
	var mat: ShaderMaterial = ink_rect.material
	var tex: Variant = mat.get_shader_parameter("scene_texture")
	assert_object(tex).is_not_null()


func test_viewport_size_is_positive() -> void:
	var vp: SubViewport = _driver.get_game_viewport()
	assert_int(vp.size.x).is_greater(0)
	assert_int(vp.size.y).is_greater(0)


# ---------------------------------------------------------------------------
# TimerService signal integration
# ---------------------------------------------------------------------------


func test_on_pressure_updated_sets_internal_state() -> void:
	_driver._on_pressure_updated(0.75)
	assert_float(_driver._pressure_level).is_equal_approx(0.75, 0.001)


func test_on_pressure_updated_clamps_negative() -> void:
	_driver._on_pressure_updated(-0.5)
	assert_float(_driver._pressure_level).is_equal_approx(0.0, 0.001)


func test_on_pressure_updated_clamps_over_one() -> void:
	_driver._on_pressure_updated(1.5)
	assert_float(_driver._pressure_level).is_equal_approx(1.0, 0.001)


func test_connect_timer_service_updates_pressure_via_signal() -> void:
	# Create a mock TimerService with the pressure_updated signal.
	var mock_timer := Node.new()
	mock_timer.name = "TimerService"
	# Add the signal dynamically so has_signal("pressure_updated") returns true.
	mock_timer.add_user_signal("pressure_updated", [{"name": "pressure_level", "type": TYPE_FLOAT}])
	add_child(mock_timer)

	# Override the DI seam to return our mock.
	_driver._timer_service_override = mock_timer
	_driver._connect_timer_service()

	# Emit the signal and verify the driver receives it.
	mock_timer.pressure_updated.emit(0.6)
	assert_float(_driver._pressure_level).is_equal_approx(0.6, 0.001)

	mock_timer.queue_free()


func test_connect_timer_service_no_crash_when_missing() -> void:
	# No override set, and no /root/TimerService exists — _get_timer_service returns null.
	_driver._connect_timer_service()
	# Should not crash; pressure_level remains at default.
	assert_float(_driver._pressure_level).is_equal(0.0)


func test_connect_timer_service_no_crash_when_no_signal() -> void:
	# A node without the pressure_updated signal.
	var wrong_node := Node.new()
	wrong_node.name = "TimerService"
	add_child(wrong_node)

	_driver._timer_service_override = wrong_node
	_driver._connect_timer_service()
	# Should not crash; no connection made.
	assert_float(_driver._pressure_level).is_equal(0.0)

	wrong_node.queue_free()


func test_pressure_signal_sequence_updates_state() -> void:
	# Create a mock TimerService.
	var mock_timer := Node.new()
	mock_timer.name = "TimerService"
	mock_timer.add_user_signal("pressure_updated", [{"name": "pressure_level", "type": TYPE_FLOAT}])
	add_child(mock_timer)

	_driver._timer_service_override = mock_timer
	_driver._connect_timer_service()

	# Simulate a sequence of pressure changes from TimerService.
	mock_timer.pressure_updated.emit(0.1)
	assert_float(_driver._pressure_level).is_equal_approx(0.1, 0.001)

	mock_timer.pressure_updated.emit(0.5)
	assert_float(_driver._pressure_level).is_equal_approx(0.5, 0.001)

	mock_timer.pressure_updated.emit(0.95)
	assert_float(_driver._pressure_level).is_equal_approx(0.95, 0.001)

	mock_timer.queue_free()
