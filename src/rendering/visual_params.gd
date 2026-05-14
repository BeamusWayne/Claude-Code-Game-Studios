class_name VisualParams
extends RefCounted

## Immutable visual parameter snapshot for the ink wash shader pipeline.
## GDD: design/gdd/ink-wash-visual-style.md System #18

var knowledge_multiplier: float = 1.0
var pressure_multiplier: float = 1.0
var vignette_radius: float = 1.4
var vignette_tightness: float = 0.7
var temperature_offset: float = 0.0
var rain_intensity: float = 0.5
var ink_density_base: float = 0.5
var saturation_penalty: float = 0.0
var edge_softness: float = 0.0
var transition_duration: float = 1.0


func _init(p: Dictionary = {}) -> void:
	if p.has("knowledge_multiplier"):
		knowledge_multiplier = p["knowledge_multiplier"]
	if p.has("pressure_multiplier"):
		pressure_multiplier = p["pressure_multiplier"]
	if p.has("vignette_radius"):
		vignette_radius = p["vignette_radius"]
	if p.has("vignette_tightness"):
		vignette_tightness = p["vignette_tightness"]
	if p.has("temperature_offset"):
		temperature_offset = p["temperature_offset"]
	if p.has("rain_intensity"):
		rain_intensity = p["rain_intensity"]
	if p.has("ink_density_base"):
		ink_density_base = p["ink_density_base"]
	if p.has("saturation_penalty"):
		saturation_penalty = p["saturation_penalty"]
	if p.has("edge_softness"):
		edge_softness = p["edge_softness"]
	if p.has("transition_duration"):
		transition_duration = p["transition_duration"]


static func exploration() -> VisualParams:
	return VisualParams.new()


static func dialogue() -> VisualParams:
	return VisualParams.new({
		"vignette_radius": 1.2,
		"temperature_offset": 0.05,
		"ink_density_base": 0.35,
		"edge_softness": 0.15,
	})


static func clue_connection() -> VisualParams:
	return VisualParams.new({
		"ink_density_base": 0.2,
		"edge_softness": 0.0,
		"rain_intensity": 0.2,
	})


static func whisper() -> VisualParams:
	return VisualParams.new({
		"temperature_offset": -0.08,
		"edge_softness": 0.25,
		"rain_intensity": 0.7,
	})


static func roar() -> VisualParams:
	return VisualParams.new({
		"pressure_multiplier": 1.0,
		"vignette_radius": 1.0,
		"vignette_tightness": 0.42,
		"temperature_offset": -0.2,
		"rain_intensity": 1.0,
		"ink_density_base": 0.8,
		"saturation_penalty": 0.2,
		"edge_softness": 0.5,
	})


static func night_end_flood() -> VisualParams:
	return VisualParams.new({
		"knowledge_multiplier": 0.0,
		"pressure_multiplier": 1.0,
		"vignette_radius": 0.4,
		"vignette_tightness": 1.0,
		"ink_density_base": 1.0,
		"rain_intensity": 1.0,
		"edge_softness": 0.8,
	})


static func night_end_drain() -> VisualParams:
	return VisualParams.new({
		"knowledge_multiplier": 1.0,
		"pressure_multiplier": 0.0,
		"vignette_radius": 1.4,
		"vignette_tightness": 0.7,
		"ink_density_base": 0.3,
		"rain_intensity": 0.3,
		"edge_softness": 0.1,
	})


## Create a lerped copy between two VisualParams.
static func lerp_params(from: VisualParams, to: VisualParams, weight: float) -> VisualParams:
	var result := VisualParams.new()
	result.knowledge_multiplier = lerpf(from.knowledge_multiplier, to.knowledge_multiplier, weight)
	result.pressure_multiplier = lerpf(from.pressure_multiplier, to.pressure_multiplier, weight)
	result.vignette_radius = lerpf(from.vignette_radius, to.vignette_radius, weight)
	result.vignette_tightness = lerpf(from.vignette_tightness, to.vignette_tightness, weight)
	result.temperature_offset = lerpf(from.temperature_offset, to.temperature_offset, weight)
	result.rain_intensity = lerpf(from.rain_intensity, to.rain_intensity, weight)
	result.ink_density_base = lerpf(from.ink_density_base, to.ink_density_base, weight)
	result.saturation_penalty = lerpf(from.saturation_penalty, to.saturation_penalty, weight)
	result.edge_softness = lerpf(from.edge_softness, to.edge_softness, weight)
	result.transition_duration = to.transition_duration
	return result
