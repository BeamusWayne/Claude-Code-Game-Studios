extends GdUnitTestSuite

## Tests for VisualParams — default values, partial init, static factory presets,
## and lerp interpolation. VisualParams is a pure RefCounted data class.
## Covers ADR-0001 Ink Wash Shader Pipeline visual parameter interface.


const SCRIPT_PATH := "res://src/rendering/visual_params.gd"

# Tolerance for float comparisons (lerp midpoint checks).
const _EPS: float = 0.001


# ---------------------------------------------------------------------------
# Tests: Default Constructor
# ---------------------------------------------------------------------------


func test_default_knowledge_multiplier() -> void:
	var vp: RefCounted = load(SCRIPT_PATH).new()
	assert_float(vp.knowledge_multiplier).is_equal(1.0)


func test_default_pressure_multiplier() -> void:
	var vp: RefCounted = load(SCRIPT_PATH).new()
	assert_float(vp.pressure_multiplier).is_equal(1.0)


func test_default_vignette_radius() -> void:
	var vp: RefCounted = load(SCRIPT_PATH).new()
	assert_float(vp.vignette_radius).is_equal(1.4)


func test_default_vignette_tightness() -> void:
	var vp: RefCounted = load(SCRIPT_PATH).new()
	assert_float(vp.vignette_tightness).is_equal(0.7)


func test_default_temperature_offset() -> void:
	var vp: RefCounted = load(SCRIPT_PATH).new()
	assert_float(vp.temperature_offset).is_equal(0.0)


func test_default_rain_intensity() -> void:
	var vp: RefCounted = load(SCRIPT_PATH).new()
	assert_float(vp.rain_intensity).is_equal(0.5)


func test_default_ink_density_base() -> void:
	var vp: RefCounted = load(SCRIPT_PATH).new()
	assert_float(vp.ink_density_base).is_equal(0.5)


func test_default_saturation_penalty() -> void:
	var vp: RefCounted = load(SCRIPT_PATH).new()
	assert_float(vp.saturation_penalty).is_equal(0.0)


func test_default_edge_softness() -> void:
	var vp: RefCounted = load(SCRIPT_PATH).new()
	assert_float(vp.edge_softness).is_equal(0.0)


func test_default_transition_duration() -> void:
	var vp: RefCounted = load(SCRIPT_PATH).new()
	assert_float(vp.transition_duration).is_equal(1.0)


# ---------------------------------------------------------------------------
# Tests: _init with Empty Dictionary
# ---------------------------------------------------------------------------


func test_init_empty_dict_gives_defaults() -> void:
	var vp: RefCounted = load(SCRIPT_PATH).new({})
	assert_float(vp.knowledge_multiplier).is_equal(1.0)
	assert_float(vp.pressure_multiplier).is_equal(1.0)
	assert_float(vp.vignette_radius).is_equal(1.4)
	assert_float(vp.vignette_tightness).is_equal(0.7)
	assert_float(vp.temperature_offset).is_equal(0.0)
	assert_float(vp.rain_intensity).is_equal(0.5)
	assert_float(vp.ink_density_base).is_equal(0.5)
	assert_float(vp.saturation_penalty).is_equal(0.0)
	assert_float(vp.edge_softness).is_equal(0.0)
	assert_float(vp.transition_duration).is_equal(1.0)


# ---------------------------------------------------------------------------
# Tests: _init with Partial Dictionary
# ---------------------------------------------------------------------------


func test_init_partial_dict_sets_only_provided_keys() -> void:
	var vp: RefCounted = load(SCRIPT_PATH).new({
		"knowledge_multiplier": 0.5,
		"rain_intensity": 0.8,
		"edge_softness": 0.3,
	})
	assert_float(vp.knowledge_multiplier).is_equal(0.5)
	assert_float(vp.pressure_multiplier).is_equal(1.0)  # unchanged default
	assert_float(vp.rain_intensity).is_equal(0.8)
	assert_float(vp.edge_softness).is_equal(0.3)
	assert_float(vp.ink_density_base).is_equal(0.5)  # unchanged default


func test_init_partial_dict_ignores_unknown_keys() -> void:
	# Passing a key that is not a property — should not crash
	var vp: RefCounted = load(SCRIPT_PATH).new({
		"knowledge_multiplier": 0.2,
		"nonexistent_param": 999.0,
	})
	assert_float(vp.knowledge_multiplier).is_equal(0.2)


# ---------------------------------------------------------------------------
# Tests: Static Factory Presets
# ---------------------------------------------------------------------------


func test_exploration_returns_default_values() -> void:
	var vp: RefCounted = load(SCRIPT_PATH).exploration()
	assert_float(vp.knowledge_multiplier).is_equal(1.0)
	assert_float(vp.pressure_multiplier).is_equal(1.0)
	assert_float(vp.vignette_radius).is_equal(1.4)
	assert_float(vp.vignette_tightness).is_equal(0.7)
	assert_float(vp.temperature_offset).is_equal(0.0)
	assert_float(vp.rain_intensity).is_equal(0.5)
	assert_float(vp.ink_density_base).is_equal(0.5)
	assert_float(vp.saturation_penalty).is_equal(0.0)
	assert_float(vp.edge_softness).is_equal(0.0)
	assert_float(vp.transition_duration).is_equal(1.0)


func test_dialogue_preset_values() -> void:
	var vp: RefCounted = load(SCRIPT_PATH).dialogue()
	assert_float(vp.vignette_radius).is_equal(1.2)
	assert_float(vp.temperature_offset).is_equal(0.05)
	assert_float(vp.ink_density_base).is_equal(0.35)
	assert_float(vp.edge_softness).is_equal(0.15)
	# Others should remain default
	assert_float(vp.knowledge_multiplier).is_equal(1.0)
	assert_float(vp.pressure_multiplier).is_equal(1.0)
	assert_float(vp.rain_intensity).is_equal(0.5)


func test_clue_connection_preset_values() -> void:
	var vp: RefCounted = load(SCRIPT_PATH).clue_connection()
	assert_float(vp.ink_density_base).is_equal(0.2)
	assert_float(vp.edge_softness).is_equal(0.0)
	assert_float(vp.rain_intensity).is_equal(0.2)
	# Others should remain default
	assert_float(vp.knowledge_multiplier).is_equal(1.0)
	assert_float(vp.temperature_offset).is_equal(0.0)


func test_whisper_preset_values() -> void:
	var vp: RefCounted = load(SCRIPT_PATH).whisper()
	assert_float(vp.temperature_offset).is_equal(-0.08)
	assert_float(vp.edge_softness).is_equal(0.25)
	assert_float(vp.rain_intensity).is_equal(0.7)
	# Others should remain default
	assert_float(vp.knowledge_multiplier).is_equal(1.0)
	assert_float(vp.ink_density_base).is_equal(0.5)


func test_roar_preset_values() -> void:
	var vp: RefCounted = load(SCRIPT_PATH).roar()
	assert_float(vp.pressure_multiplier).is_equal(1.0)
	assert_float(vp.vignette_radius).is_equal(1.0)
	assert_float(vp.vignette_tightness).is_equal(0.42)
	assert_float(vp.temperature_offset).is_equal(-0.2)
	assert_float(vp.rain_intensity).is_equal(1.0)
	assert_float(vp.ink_density_base).is_equal(0.8)
	assert_float(vp.saturation_penalty).is_equal(0.2)
	assert_float(vp.edge_softness).is_equal(0.5)


func test_night_end_flood_preset_values() -> void:
	var vp: RefCounted = load(SCRIPT_PATH).night_end_flood()
	assert_float(vp.knowledge_multiplier).is_equal(0.0)
	assert_float(vp.pressure_multiplier).is_equal(1.0)
	assert_float(vp.vignette_radius).is_equal(0.4)
	assert_float(vp.vignette_tightness).is_equal(1.0)
	assert_float(vp.ink_density_base).is_equal(1.0)
	assert_float(vp.rain_intensity).is_equal(1.0)
	assert_float(vp.edge_softness).is_equal(0.8)


func test_night_end_drain_preset_values() -> void:
	var vp: RefCounted = load(SCRIPT_PATH).night_end_drain()
	assert_float(vp.knowledge_multiplier).is_equal(1.0)
	assert_float(vp.pressure_multiplier).is_equal(0.0)
	assert_float(vp.vignette_radius).is_equal(1.4)
	assert_float(vp.vignette_tightness).is_equal(0.7)
	assert_float(vp.ink_density_base).is_equal(0.3)
	assert_float(vp.rain_intensity).is_equal(0.3)
	assert_float(vp.edge_softness).is_equal(0.1)


# ---------------------------------------------------------------------------
# Tests: All Presets Return Valid VisualParams
# ---------------------------------------------------------------------------


func test_all_presets_return_non_null() -> void:
	var VisualParams := load(SCRIPT_PATH)
	assert_object(VisualParams.exploration()).is_not_null()
	assert_object(VisualParams.dialogue()).is_not_null()
	assert_object(VisualParams.clue_connection()).is_not_null()
	assert_object(VisualParams.whisper()).is_not_null()
	assert_object(VisualParams.roar()).is_not_null()
	assert_object(VisualParams.night_end_flood()).is_not_null()
	assert_object(VisualParams.night_end_drain()).is_not_null()


# ---------------------------------------------------------------------------
# Tests: lerp_params
# ---------------------------------------------------------------------------


func test_lerp_params_weight_zero_returns_from() -> void:
	var VisualParams := load(SCRIPT_PATH)
	var from: RefCounted = VisualParams.new({"knowledge_multiplier": 0.0, "rain_intensity": 0.0})
	var to: RefCounted = VisualParams.new({"knowledge_multiplier": 1.0, "rain_intensity": 1.0})
	var result: RefCounted = VisualParams.lerp_params(from, to, 0.0)

	assert_float(result.knowledge_multiplier).is_equal_approx(0.0, _EPS)
	assert_float(result.rain_intensity).is_equal_approx(0.0, _EPS)


func test_lerp_params_weight_one_returns_to() -> void:
	var VisualParams := load(SCRIPT_PATH)
	var from: RefCounted = VisualParams.new({"knowledge_multiplier": 0.0, "rain_intensity": 0.0})
	var to: RefCounted = VisualParams.new({"knowledge_multiplier": 1.0, "rain_intensity": 1.0})
	var result: RefCounted = VisualParams.lerp_params(from, to, 1.0)

	assert_float(result.knowledge_multiplier).is_equal_approx(1.0, _EPS)
	assert_float(result.rain_intensity).is_equal_approx(1.0, _EPS)


func test_lerp_params_weight_half_returns_midpoint() -> void:
	var VisualParams := load(SCRIPT_PATH)
	var from: RefCounted = VisualParams.new({
		"knowledge_multiplier": 0.0,
		"pressure_multiplier": 0.0,
		"temperature_offset": -0.5,
	})
	var to: RefCounted = VisualParams.new({
		"knowledge_multiplier": 1.0,
		"pressure_multiplier": 2.0,
		"temperature_offset": 0.5,
	})
	var result: RefCounted = VisualParams.lerp_params(from, to, 0.5)

	assert_float(result.knowledge_multiplier).is_equal_approx(0.5, _EPS)
	assert_float(result.pressure_multiplier).is_equal_approx(1.0, _EPS)
	assert_float(result.temperature_offset).is_equal_approx(0.0, _EPS)


func test_lerp_params_all_nine_properties_lerped() -> void:
	var VisualParams := load(SCRIPT_PATH)
	var from: RefCounted = VisualParams.new({
		"knowledge_multiplier": 0.0,
		"pressure_multiplier": 0.0,
		"vignette_radius": 0.0,
		"vignette_tightness": 0.0,
		"temperature_offset": 0.0,
		"rain_intensity": 0.0,
		"ink_density_base": 0.0,
		"saturation_penalty": 0.0,
		"edge_softness": 0.0,
	})
	var to: RefCounted = VisualParams.new({
		"knowledge_multiplier": 2.0,
		"pressure_multiplier": 2.0,
		"vignette_radius": 2.0,
		"vignette_tightness": 2.0,
		"temperature_offset": 2.0,
		"rain_intensity": 2.0,
		"ink_density_base": 2.0,
		"saturation_penalty": 2.0,
		"edge_softness": 2.0,
	})
	var result: RefCounted = VisualParams.lerp_params(from, to, 0.5)

	assert_float(result.knowledge_multiplier).is_equal_approx(1.0, _EPS)
	assert_float(result.pressure_multiplier).is_equal_approx(1.0, _EPS)
	assert_float(result.vignette_radius).is_equal_approx(1.0, _EPS)
	assert_float(result.vignette_tightness).is_equal_approx(1.0, _EPS)
	assert_float(result.temperature_offset).is_equal_approx(1.0, _EPS)
	assert_float(result.rain_intensity).is_equal_approx(1.0, _EPS)
	assert_float(result.ink_density_base).is_equal_approx(1.0, _EPS)
	assert_float(result.saturation_penalty).is_equal_approx(1.0, _EPS)
	assert_float(result.edge_softness).is_equal_approx(1.0, _EPS)


func test_lerp_params_transition_duration_from_to() -> void:
	var VisualParams := load(SCRIPT_PATH)
	var from: RefCounted = VisualParams.new({"transition_duration": 0.5})
	var to: RefCounted = VisualParams.new({"transition_duration": 2.0})
	var result: RefCounted = VisualParams.lerp_params(from, to, 0.0)

	# transition_duration always takes from 'to', not lerped
	assert_float(result.transition_duration).is_equal(2.0)


func test_lerp_params_transition_duration_unchanged_at_weight_one() -> void:
	var VisualParams := load(SCRIPT_PATH)
	var from: RefCounted = VisualParams.new({"transition_duration": 3.0})
	var to: RefCounted = VisualParams.new({"transition_duration": 0.5})
	var result: RefCounted = VisualParams.lerp_params(from, to, 1.0)

	assert_float(result.transition_duration).is_equal(0.5)


func test_lerp_params_preserves_negative_values() -> void:
	var VisualParams := load(SCRIPT_PATH)
	var from: RefCounted = VisualParams.new({"temperature_offset": -0.2})
	var to: RefCounted = VisualParams.new({"temperature_offset": 0.2})
	var result: RefCounted = VisualParams.lerp_params(from, to, 0.25)

	assert_float(result.temperature_offset).is_equal_approx(-0.1, _EPS)


func test_lerp_params_between_presets() -> void:
	var VisualParams := load(SCRIPT_PATH)
	var from: RefCounted = VisualParams.exploration()
	var to: RefCounted = VisualParams.roar()
	var result: RefCounted = VisualParams.lerp_params(from, to, 0.5)

	# exploration vignette_radius=1.4, roar vignette_radius=1.0 -> midpoint 1.2
	assert_float(result.vignette_radius).is_equal_approx(1.2, _EPS)
	# exploration temperature_offset=0.0, roar temperature_offset=-0.2 -> midpoint -0.1
	assert_float(result.temperature_offset).is_equal_approx(-0.1, _EPS)
	# transition_duration from roar (1.0 default)
	assert_float(result.transition_duration).is_equal(1.0)


func test_lerp_params_does_not_mutate_inputs() -> void:
	var VisualParams := load(SCRIPT_PATH)
	var from: RefCounted = VisualParams.new({"knowledge_multiplier": 0.3, "rain_intensity": 0.7})
	var to: RefCounted = VisualParams.new({"knowledge_multiplier": 0.9, "rain_intensity": 0.1})
	VisualParams.lerp_params(from, to, 0.5)

	# Originals should be unchanged
	assert_float(from.knowledge_multiplier).is_equal(0.3)
	assert_float(from.rain_intensity).is_equal(0.7)
	assert_float(to.knowledge_multiplier).is_equal(0.9)
	assert_float(to.rain_intensity).is_equal(0.1)
