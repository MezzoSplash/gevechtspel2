class_name SpeedMeter
extends Control
## Speed meter (crystal restyle step 4, docs/ui-crystal/HANDOFF.md): one smoke shard in the HUD's
## bottom stack, right above the HP row. The big number is the local pawn's horizontal speed in m/s,
## and the shard's bottom seam is the meter: its lit length is the speed, with a notch at sprint
## speed so you can see at a glance whether a carry, dive or surf is paying off. A pale chip on the
## left names the move you are in (WALLRUN / DIVE / GRAPPLE / SLIDE / SURF, in that priority).
##
## Local pawn only, and only while it is alive and not in the killcam; the HUD decides that and
## feeds `show_speed` every frame. The helpers are static so tools/check_speed_meter tests them
## without a match.

## m/s at which the seam is fully lit. Above carry (18) on purpose: a good surf should still climb.
const FULL_SPEED := 24.0
## The number turns ice from here on: just past sprint (the speed a carry starts at) is "going fast".
const FAST_SPEED := Player.CARRY_ENTER_SPEED
## Exp rate the seam eases toward the speed. The number itself is never smoothed.
const SEAM_EASE := 14.0
const SIZE := Vector2(300, 60)
## Empty strip under the shard: the armour bar hangs 9 px above the HP row, into this row.
const FOOT := 10.0
const NUMBER_FONT := 34
const UNIT_FONT := 12
const STATE_FONT := 11
const STATE_CHIP := Vector2(88, 24)
const TEXT := Color(0.9, 0.93, 0.96)
const INK := Color(0.07, 0.08, 0.10) # dark text on the pale shell
const NOTCH := Color(1, 1, 1, 0.55)

var speed := 0.0 # m/s, as last shown
var state := ""
var _lit := 0.0
var _shard: CrystalStyle
var _chip: CrystalStyle


func _init() -> void:
	name = "Speed"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_shard = CrystalStyle.new()
	_shard.cuts = Vector4(16, 16, 6, 6)
	_shard.variant = 41
	_shard.seam_side = CrystalStyle.Side.BOTTOM
	_shard.seam_color = CrystalStyle.ICE
	_shard.seam_lit = 0.0
	_chip = CrystalStyle.new()
	_chip.fill = CrystalStyle.SHELL
	_chip.pale = true
	_chip.edge_alpha = 0.0
	_chip.cuts = Vector4(6, 3, 6, 3)
	_chip.variant = 44


## Horizontal speed: the vertical part of a fall or a jump is not "going fast".
static func flat_speed(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


## Lit share of the seam for a speed, 0..1.
static func fill_of(s: float) -> float:
	return clampf(s / FULL_SPEED, 0.0, 1.0)


## The move label, highest priority first. Empty when you are only running or flying.
static func state_name(wallrun: bool, dive: bool, slide: bool, surf: bool, grapple := false) -> String:
	if wallrun:
		return "WALLRUN"
	if dive:
		return "DIVE"
	if grapple:
		return "GRAPPLE"
	if slide:
		return "SLIDE"
	if surf:
		return "SURF"
	return ""


static func state_of(p: Player) -> String:
	if p == null:
		return ""
	return state_name(p.is_wallrunning(), p.is_diving(), p.is_sliding(), p.is_surfing(), p.is_grappling())


## One frame of the local pawn. The seam eases (frame-rate independent); the number does not.
func show_speed(s: float, move_state: String, delta: float) -> void:
	var lit := lerpf(_lit, fill_of(s), 1.0 - exp(-SEAM_EASE * maxf(delta, 0.0)))
	var same := roundi(s) == roundi(speed) and move_state == state and absf(lit - _lit) < 0.001
	speed = s
	state = move_state
	_lit = lit
	if not same:
		queue_redraw()


func lit() -> float:
	return _lit


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(size.x, size.y - FOOT))
	_shard.seam_lit = _lit
	draw_style_box(_shard, r)
	# Sprint notch on the seam: below it you are at running pace, past it you are moving.
	var nx := lerpf(_shard.cuts.w, size.x - _shard.cuts.z, fill_of(Player.SPRINT_SPEED))
	draw_line(Vector2(nx, r.end.y - 9.0), Vector2(nx, r.end.y - 1.0), NOTCH, 1.5)
	var font := get_theme_default_font()
	var num := str(roundi(speed))
	var unit := "M/S"
	var nw := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, NUMBER_FONT).x
	var uw := font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, UNIT_FONT).x
	# Number + unit sit right of centre so the state chip has the left third to itself.
	var x0 := size.x * 0.62 - (nw + 6.0 + uw) * 0.5
	var base := r.size.y * 0.5 + NUMBER_FONT * 0.36
	var col := CrystalStyle.ICE if speed >= FAST_SPEED else TEXT
	draw_string_outline(font, Vector2(x0, base), num, HORIZONTAL_ALIGNMENT_LEFT, -1, NUMBER_FONT, 6, Color(0, 0, 0, 0.55))
	draw_string(font, Vector2(x0, base), num, HORIZONTAL_ALIGNMENT_LEFT, -1, NUMBER_FONT, col)
	draw_string(font, Vector2(x0 + nw + 6.0, base), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, UNIT_FONT, CrystalStyle.ICE)
	if state != "":
		var chip := Rect2(Vector2(14.0, (r.size.y - STATE_CHIP.y) * 0.5 - 2.0), STATE_CHIP)
		draw_style_box(_chip, chip)
		var sw := font.get_string_size(state, HORIZONTAL_ALIGNMENT_LEFT, -1, STATE_FONT).x
		var sp := chip.position + Vector2((chip.size.x - sw) * 0.5, chip.size.y * 0.5 + STATE_FONT * 0.36)
		draw_string(font, sp, state, HORIZONTAL_ALIGNMENT_LEFT, -1, STATE_FONT, INK)
