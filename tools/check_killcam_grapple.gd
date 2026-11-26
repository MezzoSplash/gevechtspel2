extends Node
## #381: the grapple's rope in the killcam. Synthetic frames carry `grappling` and the anchor (indexes 11
## and 12); the replay draws the same GrappleRope the live game does, from the ghost's hand to that
## anchor, and hides it again when the pawn lets go. Frames from before the field have no rope.
##   ./run.sh --headless res://tools/check_killcam_grapple.tscn   → "KILLCAM GRAPPLE CHECK OK"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _frame(t: float, grappling: bool, anchor: Vector3, fields := 13) -> Array:
	var pawn := [Vector3(0, 0, 0), 0.0, 0.0, 0.0, 0, true, 0, 0.0, 0.0, 0.0, 0.0, grappling, anchor]
	while pawn.size() > fields:
		pawn.remove_at(pawn.size() - 1)
	return [t, {1: pawn}, PackedVector3Array(), []]


func _play(frames: Array) -> Killcam:
	var kc := Killcam.new()
	add_child(kc)
	kc._clips[1] = {"t_kill": float(frames[1][0]), "frames": frames, "events": [], "meta": {1: ["K", 0]}}
	kc.play_final({"k": 1, "v": 1, "kt": 0, "vt": 0, "kn": "K", "vn": "V", "w": "rifle"})
	return kc


func _rope(kc: Killcam) -> GrappleRope:
	return kc._ghosts[1].root.get_node_or_null("GrappleRope") as GrappleRope


func _ready() -> void:
	var anchor := Vector3(8.0, 3.0, -12.0)
	var kc := _play([_frame(1.0, true, anchor), _frame(1.1, true, anchor), _frame(1.2, true, anchor)])
	_ok(kc.is_playing(), "the replay plays")
	KillcamPuppets.apply_frames(kc, 1.1)
	var rope := _rope(kc)
	_ok(rope != null, "the ghost has a rope node")
	if rope != null:
		_ok(rope.visible, "the rope is drawn while the pawn grapples")
		var beam := rope.get_child(0) as Node3D
		var at := beam.global_position
		# The beam is placed on the middle of hand -> anchor, so its distance to the anchor is about
		# half the rope: it exists, it is out in the world, and it reaches toward the anchor.
		var mid := at.distance_to(anchor)
		_ok(mid > 0.5 and mid < anchor.length(), "the rope runs from the hand toward the anchor (%.1f m)" % mid)
		var spark := rope.get_child(1) as Node3D
		_ok(spark.global_position.distance_to(anchor) < 0.01, "and the spark sits on the anchor")
	kc._end_playback()

	# Letting go: the rope goes away again on a frame without it.
	var kc2 := _play([_frame(1.0, true, anchor), _frame(1.1, false, anchor), _frame(1.2, false, anchor)])
	KillcamPuppets.apply_frames(kc2, 1.0)
	var rope2 := _rope(kc2)
	_ok(rope2 != null and rope2.visible, "the rope is there before the release")
	KillcamPuppets.apply_frames(kc2, 1.2)
	_ok(rope2 != null and not rope2.visible, "the rope is gone after it")
	kc2._end_playback()

	# A frame from before the field: no rope at all, and nothing breaks.
	var kc3 := _play([_frame(1.0, true, anchor, 10), _frame(1.1, true, anchor, 10), _frame(1.2, true, anchor, 10)])
	KillcamPuppets.apply_frames(kc3, 1.1)
	var rope3 := _rope(kc3)
	_ok(rope3 == null or not rope3.visible, "a frame from before #381 draws no rope")
	kc3._end_playback()

	print("KILLCAM GRAPPLE CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
