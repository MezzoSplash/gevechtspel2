class_name VersionNotice
extends RefCounted
## Dutch text and a menu dialog for a NET_VERSION mismatch (join refused in the ENet auth step).
## Pure helpers plus one `show` that adds an AcceptDialog with a button to the releases page.

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


## The dialog text for our version `mine` against the server's `server`.
static func message(mine: String, server: String) -> String:
	var t := "Verkeerde versie: jij hebt %s, server heeft %s." % [mine, server]
	match compare(mine, server):
		-1:
			t += "\nDownload de nieuwste versie."
		1:
			t += "\nDe server draait een oudere versie; vraag de host om te updaten."
	return t


## Short form for a server list row.
static func row_text(mine: String, server: String) -> String:
	return "Andere versie: server v%s, jij v%s" % [server, mine]


## Shows the dialog under `parent` (the menu). Returns it (checks read the text).
static func show(parent: Node, mine: String, server: String) -> AcceptDialog:
	var old := parent.get_node_or_null("VersionDialog")
	if old:
		old.queue_free()
	var d := AcceptDialog.new()
	d.name = "VersionDialog"
	d.title = "Verkeerde versie"
	d.dialog_text = message(mine, server)
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
