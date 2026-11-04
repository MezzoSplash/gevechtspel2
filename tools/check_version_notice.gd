extends Node
## NET_VERSION mismatch notice: version compare, the Dutch text (both versions, update hint only for
## the older side), the server-list row, and the menu dialog the refused join opens.
## Optional: -- shot=/path.png (needs a display).
##   godot --headless --path . res://tools/check_version_notice.tscn   → "VERSION NOTICE CHECK OK"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	_ok(VersionNotice.compare("0.5.2", "0.5.3-dev") == -1, "0.5.2 older than 0.5.3-dev")
	_ok(VersionNotice.compare("0.5.3-dev", "0.5.3") == -1, "dev before its release")
	_ok(VersionNotice.compare("0.10.0", "0.9.9") == 1, "numeric, not text")
	_ok(VersionNotice.compare("0.5.2", "0.5.2") == 0, "equal")
	var old := VersionNotice.message("0.5.2", "0.5.3-dev")
	_ok(old.contains("jij hebt 0.5.2") and old.contains("server heeft 0.5.3-dev") and old.contains("Download de nieuwste versie"), "older client: both versions + update hint")
	_ok(not VersionNotice.message("0.5.3", "0.5.2").contains("Download"), "newer client: no update hint")
	_ok(VersionNotice.row_text("0.5.3", "0.5.2").contains("v0.5.2"), "server list row shows the server version")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(0.5).timeout
	main._show_version_dialog("0.5.1")
	await get_tree().process_frame
	var d := main.menu.get_node_or_null("VersionDialog") as AcceptDialog
	_ok(d != null and d.visible and d.dialog_text.contains(Game.NET_VERSION) and d.dialog_text.contains("0.5.1"), "refused join opens the menu dialog")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shot="):
			await get_tree().create_timer(0.3).timeout
			get_viewport().get_texture().get_image().save_png(a.substr(5))
	print("VERSION NOTICE CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
