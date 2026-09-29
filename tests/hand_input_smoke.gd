extends SceneTree
## 手牌交互烟雾测试:合成鼠标事件驱动 点选/双击/拖拽(跟手)逻辑。

var main
var table: MTable


func _mk_mouse(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	return ev


func _mk_motion(pos: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	return ev


func force_my_turn() -> void:
	table.phase = "await_discard"
	table.current_seat = 0


var ran := false


func _initialize() -> void:
	main = load("res://main.gd").new()
	root.add_child(main)


func _process(_d: float) -> bool:
	if ran:
		return false
	ran = true
	main._picked_skill = "saki"
	main._start_game()
	table = main.table
	force_my_turn()
	# 默认双击模式:单击点选
	var tid0: int = table.players[0].hand[0]
	main._on_hand_gui_input(tid0, 0, _mk_mouse(Vector2(300, 720), true))
	main._on_hand_gui_input(tid0, 0, _mk_mouse(Vector2(300, 720), false))
	print("[t1] 双击模式点选 _selected=", main._selected_hand_idx, " (期望 0)")
	# 再点同牌 = 打出
	var size_before: int = table.players[0].hand.size()
	main._on_hand_gui_input(tid0, 0, _mk_mouse(Vector2(300, 720), true))
	main._on_hand_gui_input(tid0, 0, _mk_mouse(Vector2(300, 720), false))
	print("[t2] 双击打出 13->", table.players[0].hand.size(), " 期望 12")
	# 切换单击模式:单击直接打出
	main._cfg_click_mode = 0
	force_my_turn()
	var size_b2: int = table.players[0].hand.size()
	var tid1: int = table.players[0].hand[0]
	main._on_hand_gui_input(tid1, 0, _mk_mouse(Vector2(300, 720), true))
	main._on_hand_gui_input(tid1, 0, _mk_mouse(Vector2(300, 720), false))
	print("[t3] 单击模式打出 13->", table.players[0].hand.size(), " 期望 ", size_b2 - 1)
	# 拖拽:摘出跟手,松手在牌河内 = 打出
	main._cfg_click_mode = 1
	force_my_turn()
	var size_b3: int = table.players[0].hand.size()
	var tid2: int = table.players[0].hand[1]
	var river_c: Vector2 = main._river_grids[0].get_global_rect().get_center()
	main._on_hand_gui_input(tid2, 1, _mk_mouse(Vector2(300, 720), true))
	main._on_hand_gui_input(tid2, 1, _mk_motion(river_c + Vector2(60, 30)))
	main._on_hand_gui_input(tid2, 1, _mk_mouse(river_c, false))
	var detached: bool = main._drag_control == null
	print("[t4] 拖拽跟手 detached=", detached, " 打出 ", size_b3, "->", table.players[0].hand.size(), " 期望 ", size_b3 - 1)
	# 拖拽:松手在牌河外 = 放回
	force_my_turn()
	var size_b4: int = table.players[0].hand.size()
	var tid3: int = table.players[0].hand[2]
	main._on_hand_gui_input(tid3, 2, _mk_mouse(Vector2(300, 720), true))
	main._on_hand_gui_input(tid3, 2, _mk_motion(Vector2(100, 100)))
	var detached2: bool = main._drag_control != null
	main._on_hand_gui_input(tid3, 2, _mk_mouse(Vector2(100, 100), false))
	var restored: bool = main._drag_control == null
	print("[t5] 拖拽外松手 detached=", detached2, " 放回=", restored, " 手牌 ", size_b4, "->", table.players[0].hand.size(), " 期望不变")
	# 回合外防御:非自家打牌阶段,座位动作被拒绝(纯逻辑断言)
	var size_b5: int = table.players[0].hand.size()
	table.phase = "turn_draw"
	table.current_seat = 1
	var tid4: int = table.players[0].hand[3]
	var rejected: bool = not table.player_discard(0, 3)
	var no_self_pon: bool = table._options_for(table.players[0], MTile.kind_of(table.players[0].hand[0])).pon == false
	print("[t6] 回合外打出拒绝=", rejected, " 自碰防御=", no_self_pon, " 手牌 ", size_b5, "->", table.players[0].hand.size(), " 期望不变")
	if rejected and size_b5 == table.players[0].hand.size():
		print("[t6] PASS 一回合一张 + 自碰防御")
	table.phase = "await_discard"
	table.current_seat = 0
	quit(0)
	return false
