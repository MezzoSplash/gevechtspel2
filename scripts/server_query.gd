class_name ServerQuery
extends Node
## Lightweight server info over plain UDP on game port + 1 (7778 for 7777), next to ENet.
## Server: answers "GVQ1" with a small JSON (version, map, mode, players, bots). Never touches ENet.
## Client: asks saved servers directly and the LAN by broadcast; ping is the round trip of that packet.
## No master server: only addresses the player saved or that answer on the LAN.

signal server_info(address: String, info: Dictionary, ping_ms: int, lan: bool)

const MAGIC := "GVQ1"
const MAX_REPLY := 512

var _server: UDPServer
var _server_port := 0
var _sock: PacketPeerUDP
var _sent := {} # "ip:qport" -> [{address, t}] (two saved names can resolve to the same ip)
var _resolving := {} # queue id -> {address, port}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	_tick_server()
	_tick_client()


# --- server side ---

func _tick_server() -> void:
	var want := Game.hosted_port > 0 and Game.is_networked() and multiplayer.is_server()
	var port := Game.hosted_port + Game.QUERY_PORT_OFFSET
	if not want or port != _server_port:
		if _server:
			_server.stop()
			_server = null
			_server_port = 0
	if not want:
		return
	if _server == null:
		_server = UDPServer.new()
		if _server.listen(port) != OK:
			push_warning("ServerQuery: could not listen on UDP %d" % port)
			_server = null
			Game.hosted_port = 0 # do not retry every frame
			return
		_server_port = port
		print("SERVER: info query on UDP port %d" % port)
	_server.poll()
	while _server.is_connection_available():
		var peer := _server.take_connection()
		var pkt := peer.get_packet()
		if pkt.get_string_from_utf8() == MAGIC:
			peer.put_packet(JSON.stringify(info()).to_utf8_buffer())


static func info() -> Dictionary:
	var humans := 0
	var bots := 0
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		for n in tree.get_nodes_in_group("player"):
			var p := n as Player
			if p == null or p.is_queued_for_deletion():
				continue
			if p.is_bot:
				bots += 1
			elif not (Game.is_dedicated and p.peer_id == 1):
				humans += 1
	return {
		"v": Game.NET_VERSION,
		"map": Maps.display_name(Game.map_id),
		"mode": Game.mode_name(),
		"players": humans,
		"max": 10,
		"bots": bots,
		"port": Game.hosted_port,
		"name": "Gevechtspel" if Game.is_dedicated else Game.player_name,
	}


# --- client side ---

func _ensure_sock() -> bool:
	if _sock:
		return true
	_sock = PacketPeerUDP.new()
	_sock.set_broadcast_enabled(true)
	if _sock.bind(0) != OK:
		_sock = null
		return false
	return true


## `address` is "host:port" (the game port). Hostnames resolve without blocking the menu.
func query(address: String) -> void:
	var cut := address.rfind(":")
	if cut <= 0 or not _ensure_sock():
		return
	var host := address.substr(0, cut)
	var port := int(address.substr(cut + 1))
	if port <= 0:
		return
	if host.is_valid_ip_address():
		_send(host, port, address, false)
		return
	var id := IP.resolve_hostname_queue_item(host, IP.TYPE_IPV4)
	if id != IP.RESOLVER_INVALID_ID:
		_resolving[id] = {"address": address, "port": port}


## Broadcast on this network; every LAN server on the default port answers.
func scan_lan(port: int = Game.DEFAULT_PORT) -> void:
	if _ensure_sock():
		_send("255.255.255.255", port, "", true)


func _send(ip: String, game_port: int, address: String, lan: bool) -> void:
	var qport := game_port + Game.QUERY_PORT_OFFSET
	_sock.set_dest_address(ip, qport)
	_sock.put_packet(MAGIC.to_utf8_buffer())
	var job := {"address": address, "t": Time.get_ticks_msec()}
	if lan:
		_sent["lan"] = [job]
		return
	var key := "%s:%d" % [ip, qport]
	var jobs: Array = _sent.get(key, [])
	for j in jobs:
		if j.address == address:
			j.t = job.t
			return
	jobs.append(job)
	_sent[key] = jobs


func _tick_client() -> void:
	for id in _resolving.keys():
		var st := IP.get_resolve_item_status(id)
		if st == IP.RESOLVER_STATUS_WAITING:
			continue
		var job: Dictionary = _resolving[id]
		_resolving.erase(id)
		if st == IP.RESOLVER_STATUS_DONE:
			var ip := IP.get_resolve_item_address(id)
			if ip != "":
				_send(ip, int(job.port), str(job.address), false)
		IP.erase_resolve_item(id)
	if _sock == null:
		return
	while _sock.get_available_packet_count() > 0:
		var pkt := _sock.get_packet()
		var ip := _sock.get_packet_ip()
		var from_port := _sock.get_packet_port()
		if pkt.size() > MAX_REPLY:
			continue
		var data = JSON.parse_string(pkt.get_string_from_utf8())
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var key := "%s:%d" % [ip, from_port]
		var lan := not _sent.has(key)
		var jobs: Array = _sent.get(key, _sent.get("lan", []))
		for job in jobs:
			var address := str(job.address)
			if lan:
				address = "%s:%d" % [ip, int(data.get("port", from_port - Game.QUERY_PORT_OFFSET))]
			server_info.emit(address, data, Time.get_ticks_msec() - int(job.t), lan)
