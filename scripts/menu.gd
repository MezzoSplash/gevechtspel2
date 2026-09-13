class_name MainMenu
extends Control

signal play_local_pressed
signal host_pressed
signal connect_pressed

@onready var status_label: Label = $Center/Col/Status
@onready var name_edit: LineEdit = $Center/Col/NameRow/NameEdit
@onready var ip_edit: LineEdit = $Center/Col/JoinRow/IpEdit
@onready var port_edit: LineEdit = $Center/Col/JoinRow/PortEdit


func _ready() -> void:
	$Center/Col/PlayButton.pressed.connect(func() -> void: play_local_pressed.emit())
	$Center/Col/HostButton.pressed.connect(func() -> void: host_pressed.emit())
	$Center/Col/JoinRow/JoinButton.pressed.connect(func() -> void: connect_pressed.emit())


func set_status(t: String) -> void:
	if status_label:
		status_label.text = t


func player_name() -> String:
	return name_edit.text.strip_edges() if name_edit else "Player"


func host_ip() -> String:
	return ip_edit.text.strip_edges() if ip_edit else "127.0.0.1"


func host_port() -> int:
	return int(port_edit.text) if port_edit else Game.DEFAULT_PORT


func set_player_name(n: String) -> void:
	if name_edit:
		name_edit.text = n


func set_host_ip(ip: String) -> void:
	if ip_edit:
		ip_edit.text = ip


func set_host_port(port: int) -> void:
	if port_edit:
		port_edit.text = str(port)
