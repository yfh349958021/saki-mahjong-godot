extends SceneTree
## 联机烟雾测试(主机端):
##   godot --headless -s res://tests/net_host_smoke.gd

var net
var table: MTable
var frames := 0
var started := false
var steps := 0


func _initialize() -> void:
	net = load("res://logic/net.gd").new()
	root.add_child(net)
	net.my_name = "房主"
	net.lobby_changed.connect(_on_lobby)
	net.game_started.connect(_on_game_started)


func _on_lobby() -> void:
	var chars: Array = []
	for e in net.lobby:
		chars.append(e.char)
	print("[host] lobby=", net.lobby.size(), " chars=", chars)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3 and net.peer_type == "off":
		var code: String = net.host_game()
		print("[host] room code = ", code)
		var dec: Dictionary = net.decode_code(code)
		print("[host] decode = ", dec)
		if dec.is_empty() or int(dec.port) != MNet.PORT:
			print("[host] CODE-FAIL")
			quit(1)
			return true
	if frames > 3600:
		print("[host] TIMEOUT")
		quit(1)
		return true
	if not started and frames > 90 and net.lobby.size() == 2:
		started = true
		net.host_add_ai(1)
		net.host_add_ai(1)
		net.host_start_game()
	if table != null:
		if table.phase == "round_end":
			print("[host] ALL-OK steps=", steps)
			quit(0)
			return true
		if steps >= 60:
			print("[host] ALL-OK steps>=60")
			quit(0)
			return true
		if frames % 6 == 0 and not table.wall.is_exhausted():
			table.advance_one_step()
			steps += 1
			net.broadcast_snapshot_builder(table)
	return false


func _on_game_started(args: Dictionary) -> void:
	print("[host] game_started chars=", args.chars)
	table = MTable.new()
	table.setup(args.chars, 0, args.seed, 0, net.rules)
	for i in 4:
		table.players[i].is_ai = int(args.humans[i]) == 0
		table.players[i].ai_difficulty = int(args.diffs[i])
	net.bind_table(table)
	table.start_round(args.seed)
	print("[host] table running")
