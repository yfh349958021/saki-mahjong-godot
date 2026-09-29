extends SceneTree
## 联机烟雾测试(客户端端):
##   godot --headless -s res://tests/net_client_smoke.gd

var net
var frames := 0
var snaps := 0


func _initialize() -> void:
	net = load("res://logic/net.gd").new()
	root.add_child(net)
	net.my_name = "客人"
	net.my_char = "nodoka"
	net.joined_ok.connect(func():
		print("[client] joined")
		net.send_register()
		net.send_set_char("nodoka"))
	net.lobby_changed.connect(func():
		print("[client] lobby=", net.lobby.size()))
	net.game_started.connect(func(args):
		print("[client] game_started seat=", net.my_seat, " chars=", args.chars))
	net.snapshot_received.connect(func(_snap):
		snaps += 1
		if snaps == 5:
			print("[client] CLIENT-ALL-OK snaps>=5")
			quit(0))



func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3 and net.peer_type == "off":
		var err = net.join_game("127.0.0.1:%d" % MNet.PORT)
		print("[client] join err=", err)
	if frames > 3600:
		print("[client] TIMEOUT")
		quit(1)
		return true
	return false
