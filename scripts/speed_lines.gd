class_name SpeedLines
extends CanvasLayer
## Screen-space speed lines while the local player moves fast (Game.speed_fx). Sits under the HUD
## (layer 0 < HUD's 1), the same slot FreezeGrade uses. Entirely local: only the local pawn writes
## an intensity, so remote pawns, a dedicated server and the menus never draw anything.

const SHADER := preload("res://shaders/speed_lines.gdshader")

var _rect: ColorRect
var _mat: ShaderMaterial
var _intensity := 0.0


func _ready() -> void:
	layer = 0
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("intensity", 0.0)
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)


## The intensity the shader holds right now (0..1). For the headless check.
func intensity() -> float:
	return _intensity


## Draws this frame? False at (near) zero, so a standing player costs nothing.
func is_drawing() -> bool:
	return _rect != null and _rect.visible


## Eases toward `target` (0..1) at `rate` 1/s, the way the rest of the feel code smooths.
func set_intensity_smooth(target: float, delta: float, rate: float) -> void:
	set_intensity(lerpf(_intensity, clampf(target, 0.0, 1.0), 1.0 - exp(-maxf(rate, 0.0) * delta)))


## Jumps straight to `v` (toggle off, death, leaving a match).
func set_intensity(v: float) -> void:
	_intensity = clampf(v, 0.0, 1.0)
	if _mat == null:
		return
	_mat.set_shader_parameter("intensity", _intensity)
	_rect.visible = _intensity > 0.001
