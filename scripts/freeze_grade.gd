class_name FreezeGrade
extends CanvasLayer
## Greyscale over the 3D view while the round-start freeze/countdown runs; eases back to colour
## when the round goes live (#63). Sits under the HUD (layer 0 < HUD's 1), so the HUD stays in colour.

const SHADER := preload("res://shaders/greyscale.gdshader")
const TO_GREY := 0.25
const TO_COLOUR := 0.9

var _rect: ColorRect
var _mat: ShaderMaterial
var _tween: Tween


func _ready() -> void:
	layer = 0
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)
	Game.round_freeze_changed.connect(_on_freeze)


func amount() -> float:
	return float(_mat.get_shader_parameter("amount"))


func _on_freeze(frozen: bool) -> void:
	if Game.is_dedicated:
		return
	if frozen and (Game.menu_match or Game.in_lobby):
		return
	_go(1.0 if frozen else 0.0, TO_GREY if frozen else TO_COLOUR)


func _go(target: float, t: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	if target > 0.0:
		_rect.visible = true
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(func(v: float) -> void: _mat.set_shader_parameter("amount", v), amount(), target, t)
	if target <= 0.0:
		_tween.tween_callback(func() -> void: _rect.visible = false)


## Leave / reset: colour at once.
func clear() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_mat.set_shader_parameter("amount", 0.0)
	_rect.visible = false
