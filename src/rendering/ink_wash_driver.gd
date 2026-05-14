extends CanvasLayer

## Ink Wash Driver — manages SubViewport texture pipeline and shader uniforms.
## ADR-0001: Ink Wash Shader Pipeline
##
## Scene tree layout (managed by this node):
##   SubViewportContainer > SubViewport > [game scene children]
##   ColorRect (ink_wash.gdshader, reads SubViewport texture)
##   ColorRect (rain.gdshader)
##
## Usage: Add as child of main scene root. Game content goes under the SubViewport.

var _time_elapsed: float = 0.0
var _knowledge_level: float = 0.0
var _pressure_level: float = 0.0
var _rain_intensity: float = 0.5

var _ink_material: ShaderMaterial = null
var _rain_material: ShaderMaterial = null
var _game_viewport: SubViewport = null

## Override in tests to inject a mock TimerService node (dependency injection).
var _timer_service_override: Node = null

const INK_WASH_SHADER_PATH: String = "res://src/rendering/ink_wash.gdshader"
const RAIN_SHADER_PATH: String = "res://src/rendering/rain.gdshader"


func _ready() -> void:
	_build_pipeline()
	_connect_timer_service()


## Return the TimerService autoload node, or null if unavailable.
## Uses _timer_service_override if set (dependency injection seam for tests).
func _get_timer_service() -> Node:
	if _timer_service_override != null:
		return _timer_service_override
	return get_node_or_null("/root/TimerService")


## Connect to TimerService.pressure_updated if the autoload is present.
func _connect_timer_service() -> void:
	var timer_service: Node = _get_timer_service()
	if timer_service != null and timer_service.has_signal("pressure_updated"):
		Signal(timer_service, "pressure_updated").connect(_on_pressure_updated)


## Callback for TimerService.pressure_updated signal.
func _on_pressure_updated(pressure_level: float) -> void:
	set_pressure_level(pressure_level)


func _process(delta: float) -> void:
	_time_elapsed += delta
	if _ink_material:
		_ink_material.set_shader_parameter("knowledge_level", _knowledge_level)
		_ink_material.set_shader_parameter("pressure_level", _pressure_level)
		_ink_material.set_shader_parameter("time_value", _time_elapsed)
	if _rain_material:
		_rain_material.set_shader_parameter("rain_intensity", _rain_intensity)
		_rain_material.set_shader_parameter("time_value", _time_elapsed)


## Set knowledge_level (0.0 monochrome → 1.0 full color).
func set_knowledge_level(value: float) -> void:
	_knowledge_level = clampf(value, 0.0, 1.0)


## Set pressure_level (0.0 whisper → 1.0 roar).
func set_pressure_level(value: float) -> void:
	_pressure_level = clampf(value, 0.0, 1.0)


## Set rain_intensity (0.0 clear → 1.0 storm).
func set_rain_intensity(value: float) -> void:
	_rain_intensity = clampf(value, 0.0, 1.0)


## Return the SubViewport that game content should be added to.
func get_game_viewport() -> SubViewport:
	return _game_viewport


func _build_pipeline() -> void:
	layer = 10

	# SubViewport setup
	var container: SubViewportContainer = SubViewportContainer.new()
	container.stretch = true
	container.name = "GameViewportContainer"
	add_child(container)

	_game_viewport = SubViewport.new()
	_game_viewport.name = "GameViewport"
	_game_viewport.size = Vector2(1280, 720)
	_game_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_game_viewport)

	# Ink wash post-process rect
	var ink_shader: Shader = load(INK_WASH_SHADER_PATH)
	_ink_material = ShaderMaterial.new()
	_ink_material.shader = ink_shader
	_ink_material.set_shader_parameter("scene_texture", _game_viewport.get_texture())

	var ink_rect: ColorRect = ColorRect.new()
	ink_rect.name = "InkWashRect"
	ink_rect.material = _ink_material
	ink_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	ink_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ink_rect)

	# Rain overlay on a higher sub-layer
	var rain_shader: Shader = load(RAIN_SHADER_PATH)
	_rain_material = ShaderMaterial.new()
	_rain_material.shader = rain_shader

	var rain_rect: ColorRect = ColorRect.new()
	rain_rect.name = "RainRect"
	rain_rect.material = _rain_material
	rain_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rain_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rain_rect)
