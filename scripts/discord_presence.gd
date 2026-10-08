extends Node
## One Discord status for as long as a game window is open.
## Friends see the application name from the Discord Developer Portal.
## Paste that application's id into APP_ID. An empty id leaves presence off.
## The editor and a dedicated server never connect.

## Discord Developer Portal → the Gevechtspel application → Application ID.
const APP_ID := "1557884046057410562"
## preload, not the class_name: autoloads parse before the global class cache is ready.
const _Presence := preload("res://addons/discord_rich_presence/discord_rich_presence.gd")

var _presence: Node


func _ready() -> void:
	if APP_ID.is_empty() or Engine.is_editor_hint():
		return
	# main.gd sets Game.is_dedicated only after autoloads are ready, so the
	# dedicated server is recognized from the same --server launch arg.
	if Game.display_headless() or _launched_as_server():
		return
	_presence = _Presence.new()
	_presence.app_id = APP_ID
	add_child(_presence)
	# Once. Discord rate-limits updates, and this status does not track the map.
	_presence.set_activity({
		"details": "Playing",
		"timestamps": {"start": int(Time.get_unix_time_from_system())},
	})


func _launched_as_server() -> bool:
	return OS.get_cmdline_user_args().has("--server")
