class_name MNet
extends Node
## 联机管理:Godot ENet 高层多人(主机权威模型)。
##   · 房主 create_room():本机开服,生成“房间邀请码”
##     (邀请码 = 房主 IPv4 + 端口的 Base32 编码,局域网即开即用;
##      跨网需要房主做端口转发,或把邀请码换成公网 IP 再拼端口)
##   · join_game(码或 IP):加入房间
##   · 大厅:名字/选角(唯一)/加 AI(难度)/规则,全部由主机权威广播
##   · 对局:主机运行 MTable(唯一真相),每步向各家下发“视角快照”;
##     客户端动作通过 rpc_action 上送,由主机校验执行。

const PORT := 37564
const CODE_PREFIX := "SMJ"
const B32 := "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

signal lobby_changed
signal game_started
signal snapshot_received
signal joined_ok
signal join_failed(reason: String)
signal back_to_lobby

var peer_type := "off"        # off | host | client
var my_name := "玩家"
var my_char := ""             # 自己在大厅里选的角色
var room_code := ""
var lobby: Array = []         # [{ "id":int, "name":String, "char":String, "ai":bool, "diff":int }]
var rules := {}               # 房主的规则设置
var in_game := false
var my_seat := -1


func is_host() -> bool:
	return peer_type == "host"


func is_client() -> bool:
	return peer_type == "client"


func is_online() -> bool:
	return peer_type != "off"


## —— 房间码:6 字节(IPv4×4 + 端口×2)→ Base32(8 字符,带 SMJ 前缀)——

func encode_code(ip: String, port: int) -> String:
	var parts := ip.split(".")
	if parts.size() != 4:
		return ""
	var bytes := PackedByteArray()
	for p in parts:
		bytes.append(clampi(int(p), 0, 255))
	bytes.append(port >> 8)
	bytes.append(port & 0xFF)
	var out := ""
	var bits := 0
	var acc := 0
	for b in bytes:
		acc = (acc << 8) | b
		bits += 8
		while bits >= 5:
			bits -= 5
			out += B32[(acc >> bits) & 31]
	if bits > 0:
		out += B32[(acc << (5 - bits)) & 31]  # 末尾不足 5 位补齐
	return CODE_PREFIX + out


func decode_code(code: String) -> Dictionary:
	code = code.strip_edges().to_upper().replace(" ", "").replace("-", "").replace(CODE_PREFIX, "")
	if code.length() != 10:
		return {}
	var acc := 0
	var bits := 0
	var bytes := PackedByteArray()
	for ch in code:
		var idx := B32.find(ch)
		if idx < 0:
			return {}
		acc = (acc << 5) | idx
		bits += 5
		if bits >= 8:
			bits -= 8
			bytes.append((acc >> bits) & 255)
	if bytes.size() != 6:
		return {}
	return {"ip": "%d.%d.%d.%d" % [bytes[0], bytes[1], bytes[2], bytes[3]], "port": bytes[4] * 256 + bytes[5]}


func _local_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			return ip
	return "127.0.0.1"


## —— 建房 / 加入 ——

func host_game() -> String:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, 3) != OK:
		return ""
	multiplayer.multiplayer_peer = peer
	peer_type = "host"
	in_game = false
	my_seat = 0
	lobby = [{"id": 1, "name": my_name, "char": my_char, "ai": false, "diff": 1}]
	room_code = encode_code(_local_ip(), PORT)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	lobby_changed.emit()
	return room_code


func join_game(code_or_ip: String) -> Error:
	var target := code_or_ip.strip_edges()
	if target.contains(CODE_PREFIX) or (target.length() == 8 and target.to_upper() == target and target.find(".") < 0):
		var dec := decode_code(target)
		if dec.is_empty():
			return ERR_INVALID_PARAMETER
		target = "%s:%d" % [dec.ip, dec.port]
	var ip := target
	var port := PORT
	if target.contains(":"):
		var seg := target.split(":")
		ip = seg[0]
		port = int(seg[1])
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	peer_type = "client"
	in_game = false
	multiplayer.connected_to_server.connect(func(): joined_ok.emit())
	multiplayer.connection_failed.connect(func(): join_failed.emit("连接失败:检查邀请码/端口"))
	multiplayer.server_disconnected.connect(func():
		peer_type = "off"
		in_game = false
		back_to_lobby.emit())
	return OK


## —— 主机本地操作(自改 + 权威广播)——

func host_set_char(char_id: String) -> void:
	if not is_host():
		return
	for entry in lobby:
		if entry.id == 1:
			for other in lobby:
				if other != entry and other.char == char_id:
					return
			entry.char = char_id
			break
	_host_broadcast_lobby()


func host_add_ai(diff: int) -> void:
	if not is_host():
		return
	rpc_add_ai(diff)


func host_remove_ai(slot: int) -> void:
	if not is_host():
		return
	rpc_remove_ai(slot)


func host_set_diff(slot: int, diff: int) -> void:
	if not is_host():
		return
	rpc_set_diff(slot, diff)


func host_set_rules(rules_data: Dictionary) -> void:
	if not is_host():
		return
	rpc_set_rules(rules_data)


func host_back_to_lobby() -> void:
	if not is_host():
		return
	in_game = false
	rpc_back_lobby.rpc()


@rpc("authority", "call_remote", "reliable")
func rpc_back_lobby() -> void:
	in_game = false
	back_to_lobby.emit()


func _on_peer_connected(pid: int) -> void:
	if not is_host():
		return
	if lobby.size() >= 4:
		multiplayer.multiplayer_peer.disconnect_peer(pid)
		return
	lobby.append({"id": pid, "name": "玩家%d" % lobby.size(), "char": "", "ai": false, "diff": 1})
	_host_broadcast_lobby()


func _on_peer_disconnected(pid: int) -> void:
	if not is_host():
		return
	for entry in lobby:
		if entry.id == pid:
			lobby.erase(entry)
			break
	_host_broadcast_lobby()


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	peer_type = "off"
	in_game = false
	lobby = []
	my_seat = -1


## —— 大厅:注册 / 选角 / 加 AI / 改难度 / 改规则(客户端改自家选角,主机权威裁决)——

func send_register() -> void:
	rpc_register.rpc(my_name)


func send_set_char(char_id: String) -> void:
	rpc_set_char.rpc(char_id)


func send_add_ai(diff: int) -> void:
	rpc_add_ai.rpc(diff)


func send_remove_ai(slot: int) -> void:
	rpc_remove_ai.rpc(slot)


func send_set_diff(slot: int, diff: int) -> void:
	rpc_set_diff.rpc(slot, diff)


func send_set_rules(rules: Dictionary) -> void:
	rpc_set_rules.rpc(rules)


func send_start(seed_value: int) -> void:
	rpc_start.rpc(seed_value)


func send_snapshot(snap: Dictionary, peer_id: int) -> void:
	rpc_snapshot.rpc_id(peer_id, snap)


func broadcast_snapshot_builder(table: MTable) -> void:
	if not is_host():
		return
	for p in multiplayer.get_peers():
		# 找到该 peer 对应座位
		var seat := _seat_of_peer(p)
		if seat >= 0:
			rpc_snapshot.rpc_id(p, table.snapshot_for(seat))


func _seat_of_peer(peer_id: int) -> int:
	for entry in lobby:
		if entry.id == peer_id and not entry.ai:
			return lobby.find(entry)
	return -1


func send_action(action: Dictionary) -> void:
	rpc_action.rpc(action)


@rpc("any_peer", "call_remote", "reliable")
func rpc_register(name: String) -> void:
	if not is_host():
		return
	var pid := multiplayer.get_remote_sender_id()
	for entry in lobby:
		if entry.id == pid:
			entry.name = name
	_host_broadcast_lobby()


@rpc("any_peer", "call_remote", "reliable")
func rpc_set_char(char_id: String) -> void:
	if not is_host():
		return
	var pid := multiplayer.get_remote_sender_id()
	for entry in lobby:
		if entry.id == pid:
			# 唯一性:角色不能与已选角色重复
			for other in lobby:
				if other != entry and other.char == char_id:
					return
			entry.char = char_id
	_host_broadcast_lobby()


@rpc("any_peer", "call_remote", "reliable")
func rpc_add_ai(diff: int) -> void:
	if not is_host():
		return
	if lobby.size() < 4:
		lobby.append({"id": -(lobby.size()), "name": "电脑", "char": "", "ai": true, "diff": diff})
	_host_broadcast_lobby()


@rpc("any_peer", "call_remote", "reliable")
func rpc_remove_ai(slot: int) -> void:
	if not is_host():
		return
	if slot >= 0 and slot < lobby.size() and lobby[slot].ai:
		lobby.remove_at(slot)
	_host_broadcast_lobby()


@rpc("any_peer", "call_remote", "reliable")
func rpc_set_diff(slot: int, diff: int) -> void:
	if not is_host():
		return
	if slot >= 0 and slot < lobby.size() and lobby[slot].ai:
		lobby[slot].diff = diff
	_host_broadcast_lobby()


@rpc("any_peer", "call_remote", "reliable")
func rpc_set_rules(rules: Dictionary) -> void:
	if not is_host():
		return
	self.rules = rules
	_host_broadcast_lobby()


func _host_broadcast_lobby() -> void:
	if not is_host():
		return
	# 主机自动为空缺位补默认角色
	_fill_chars()
	rpc_lobby.rpc(lobby.duplicate(true), rules.duplicate(true))
	_apply_lobby(lobby.duplicate(true), rules.duplicate(true))


func _fill_chars() -> void:
	var used: Array[String] = []
	for entry in lobby:
		if entry.char != "":
			used.append(entry.char)
	for entry in lobby:
		if entry.char == "":
			for cid in ["saki", "hisa", "koromo", "nodoka", "teru", "kuro", "ako", "ryuuka"]:
				if not used.has(cid):
					entry.char = cid
					used.append(cid)
					break


@rpc("authority", "call_remote", "reliable")
func rpc_lobby(lobby_data: Array, rules_data: Dictionary) -> void:
	_apply_lobby(lobby_data, rules_data)


func _apply_lobby(lobby_data: Array, rules_data: Dictionary) -> void:
	lobby = lobby_data
	rules = rules_data
	for entry in lobby:
		if not entry.ai and entry.id == multiplayer.get_unique_id():
			my_char = entry.char
	lobby_changed.emit()


## —— 开局:主机分派座位(人类在前,其余 AI),广播种子/角色/规则 ——

func host_start_game() -> void:
	if not is_host():
		return
	_fill_chars()
	# 座位:房主固定 0(东),其余按大厅顺序
	var chars: Array[String] = ["", "", "", ""]
	var diffs: Array[int] = [1, 1, 1, 1]
	var humans: Array[int] = []   # peer_id(0 = AI)
	var idx := 1                  # 座位 0 固定给房主
	for entry in lobby:
		if entry.id == 1:
			chars[0] = entry.char
			break
	diffs[0] = 1
	humans.append(1)              # 房主 peer id = 1
	for entry in lobby:
		if entry.id == 1 or idx >= 4:
			continue
		chars[idx] = entry.char
		diffs[idx] = entry.diff
		humans.append(0 if entry.ai else entry.id)
		idx += 1
	while idx < 4:
		# 人数不足:自动补 AI
		var used: Array[String] = []
		for c in chars:
			if c != "":
				used.append(c)
		for cid in ["saki", "hisa", "koromo", "nodoka", "teru", "kuro", "ako", "ryuuka"]:
			if not used.has(cid):
				chars[idx] = cid
				used.append(cid)
				break
		diffs[idx] = rules.ai_difficulty
		humans.append(0)
		idx += 1
	var seed_value := int(Time.get_unix_time_from_system()) % 100000000
	rpc_start.rpc(seed_value, chars, diffs, humans, rules)
	_apply_start(seed_value, chars, diffs, humans, rules)


@rpc("authority", "call_remote", "reliable")
func rpc_start(seed_value: int, chars: Array, diffs: Array, humans: Array, rules_data: Dictionary) -> void:
	_apply_start(seed_value, chars, diffs, humans, rules_data)


func _apply_start(seed_value: int, chars: Array, diffs: Array, humans: Array, rules_data: Dictionary) -> void:
	rules = rules_data
	my_seat = -1
	for i in 4:
		if not humans[i] == 0 and humans[i] == multiplayer.get_unique_id():
			my_seat = i
	if is_host():
		my_seat = 0
	in_game = true
	game_started.emit({"seed": seed_value, "chars": chars, "diffs": diffs, "humans": humans})


## —— 对局内:快照下发 / 动作上送 ——

@rpc("authority", "call_remote", "reliable")
func rpc_snapshot(snap: Dictionary) -> void:
	snapshot_received.emit(snap)


@rpc("any_peer", "call_remote", "reliable")
func rpc_action(action: Dictionary) -> void:
	if not is_host():
		return
	var pid := multiplayer.get_remote_sender_id()
	var seat := _seat_of_peer(pid)
	if seat < 0:
		return
	apply_action(seat, action)


## 主机:把远端动作落到本地 MTable(校验在 Table 内完成)。
func apply_action(seat: int, action: Dictionary) -> void:
	var table := _cached_table
	if table == null:
		return
	match action.get("kind", ""):
		"discard":
			table.player_discard(seat, action.index)
		"riichi":
			table.player_riichi(seat, action.index)
		"tsumo":
			table.player_tsumo(seat)
		"ankan":
			table.player_ankan(seat, action.index)
		"kakan":
			table.player_kakan(seat, action.index)
		"saki":
			table.player_use_saki(seat, action.index, action.delta)
		"hisa":
			table.player_use_hisa(seat)
		"mulligan":
			table.player_use_mulligan(seat)
		"ako":
			table.player_use_ako(seat)
		"peek":
			table.player_choose_peek(seat, action.index)
		"ron":
			table.player_ron(seat)
		"pon":
			table.player_pon(seat)
		"kan":
			table.player_kan(seat)
		"chi":
			table.player_chi(seat, action.combo)
		"decline":
			table.player_decline(seat)


var _cached_table: MTable


func bind_table(t: MTable) -> void:
	_cached_table = t


func _find_table() -> MTable:
	return _cached_table
