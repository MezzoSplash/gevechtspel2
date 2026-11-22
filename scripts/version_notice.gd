class_name VersionNotice
extends RefCounted
## Dutch text and a menu dialog for a join refused in the ENet auth step: the peer's NET_VERSION
## (the protocol) differs from ours, so its RPC ids and payloads do not line up. The build
## (`Game.build_version()`) is shown next to it so a player can see which download they need, but
## only the protocol decides whether a join is allowed (#356).

const RELEASES_URL := "https://github.com/MezzoSplash/gevechtspel2/releases"


## -1 when `a` is older than `b`, 1 when newer, 0 when equal. "0.5.3-dev" counts as before "0.5.3".
static func compare(a: String, b: String) -> int:
	var pa := _parts(a)
	var pb := _parts(b)
	for i in maxi(pa.size(), pb.size()):
		var x: int = pa[i] if i < pa.size() else 0
		var y: int = pb[i] if i < pb.size() else 0
		if x != y:
			return -1 if x < y else 1
	var da := a.contains("-")
	var db := b.contains("-")
	if da != db:
		return -1 if da else 1
	return 0


static func _parts(v: String) -> Array[int]:
	var out: Array[int] = []
	for s in v.trim_prefix("v").get_slice("-", 0).split("."):
		out.append(int(s))
	return out


## "protocol 0.5.20 · build 0.6.0"; the build is left out when it is not known.
static func side(protocol: String, build: String) -> String:
	var b := build.strip_edges().trim_prefix("v")
	if b.is_empty():
		return "protocol %s" % protocol
	return "protocol %s · build %s" % [protocol, b]


## The dialog text: what differs, whose side is older, what to do about it, and why it blocks a join.
static func message(mine: String, server: String, mine_build := "", server_build := "") -> String:
	var t := "De protocolversie verschilt, dus je kunt niet meespelen.\n"
	t += "Jij: %s\n" % side(mine, mine_build)
	t += "Server: %s\n" % side(server, server_build)
	t += "Elke protocolversie spreekt zijn eigen netwerkberichten; een andere versie kan niet meespelen."
	match compare(mine, server):
		-1:
			t += "\nDownload de nieuwste versie."
		1:
			t += "\nDe server draait een oudere versie; vraag de host om te updaten."
	return t


## Short form for a server list row.
static func row_text(mine: String, server: String, build := "") -> String:
	var b := build.strip_edges().trim_prefix("v")
	var tail := "" if b.is_empty() else " (build %s)" % b
	return "kan niet joinen: protocol v%s, jij v%s%s" % [server, mine, tail]


## Shows the dialog under `parent` (the menu). Returns it (checks read the text).
static func show(parent: Node, mine: String, server: String, mine_build := "", server_build := "") -> AcceptDialog:
	var old := parent.get_node_or_null("VersionDialog")
	if old:
		old.queue_free()
	var d := AcceptDialog.new()
	d.name = "VersionDialog"
	d.title = "Kan niet joinen: protocolversie"
	d.dialog_text = message(mine, server, mine_build, server_build)
	d.ok_button_text = "OK"
	d.add_button("Download", true, "download")
	d.custom_action.connect(func(action: StringName) -> void:
		if action == &"download":
			OS.shell_open(RELEASES_URL)
			d.hide()
	)
	parent.add_child(d)
	d.popup_centered()
	return d
