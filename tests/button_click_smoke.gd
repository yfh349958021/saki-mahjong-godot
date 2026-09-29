extends SceneTree
## 响应按钮点击测试:用 Viewport.push_input 在按钮全局坐标处合成真实点击,
## 验证 GUI 拾取不再被全屏层拦截,且点击产生实际牌局效果。

var main
var table: MTable
var frames := 0
var stage := 0
var clicks := 0


func _initialize() -> void:
	main = load("res://main.gd").new()
	root.add_child(main)


func _press_at(pos: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	root.push_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	root.push_input(up)


func force_response_window() -> void:
	# 构造:AI 打出 5m,自家有两张 5m → 可碰
	table.phase = "await_discard"
	table.current_seat = 1
	var ai := table.players[1]
	ai.hand = MTile.parse("123m456m789m11s白白5m")
	ai.just_drawn = MTile.parse("5m")[0]
	var meld_tile: int = MTile.parse("5m")[0]
	table.players[0].hand = MTile.parse("234p567p234s白白55m")
	table.players[0].just_drawn = meld_tile
	table.players[2].hand = MTile.parse("1199m1199p1199s白")
	table.players[3].hand = MTile.parse("1199m1199p1199s白")
	table.advance_one_step()  # AI 打出 5m → 收集响应(自家可碰)
	main._refresh()
	print("[b] phase=", table.phase, " awaiting=", table._awaiting, " pon=", table.human_options.get("pon", false))


func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		main._picked_skill = "saki"
		main._start_game()
		table = main.table
		force_response_window()
		return false
	if frames < 6:
		return false
	if stage == 0:
		# 找到「碰」按钮并真实点击
		var found: Button = null
		var stack: Array[Node] = [main]
		while stack.size() > 0 and found == null:
			var n: Node = stack.pop_back()
			if n is Button and (n as Button).text == "碰":
				found = n
			for c in n.get_children():
				stack.append(c)
		if found == null:
			print("[b] FAIL 未找到碰按钮")
			quit(1)
			return true
		print("[b] 碰按钮位于 ", found.get_global_rect())
		clicks += 1
		var hover_ev := InputEventMouseMotion.new()
		hover_ev.position = found.get_global_rect().get_center()
		hover_ev.global_position = hover_ev.position
		root.push_input(hover_ev)
		var hovered := root.gui_get_hovered_control()
		print("[b] hovered = ", hovered.name if hovered else "(null)", " class=", hovered.get_class() if hovered else "-")
		_press_at(found.get_global_rect().get_center())
		await process_frame
		print("[b] 点击后 awaiting=", table._awaiting, " calls=", table._calls.keys(), " melds=", table.players[0].melds.size())
		stage = 1
		return false
	if stage == 1:
		# 碰应已生效:副露 +1,按钮消失
		var melds: int = table.players[0].melds.size()
		print("[b] 点击碰后 melds=", melds, " (期望 1)")
		if melds == 1:
			print("[b] PON-CLICK-OK")
			# 打出一张,让牌局继续
			force_my_turn_discard()
			stage = 2
			frames = 6
			return false
		print("[b] FAIL 碰无反应")
		quit(1)
		return true
	if stage == 2:
		# 构造无役可和但能碰的窗口,点「跳过」后牌局应继续推进
		if table.phase == "await_discard" and table.current_seat == 0:
			table.phase = "await_discard"
			var ai2 := table.players[1]
			ai2.hand = MTile.parse("123m456m789m11s白白5m")
			ai2.just_drawn = MTile.parse("5m")[0]
			table.players[0].hand = MTile.parse("234p567p234s白白55m")
			table.players[0].just_drawn = MTile.parse("5m")[0]
			table.advance_one_step()
			main._refresh()
			stage = 3
			clicks = 0
		return false
	if stage == 3:
		var skip: Button = null
		var stack: Array[Node] = [main]
		while stack.size() > 0 and skip == null:
			var n: Node = stack.pop_back()
			if n is Button and (n as Button).text == "跳过":
				skip = n
			for c in n.get_children():
				stack.append(c)
		if skip == null:
			if frames > 200:
				print("[b] SKIP-FAIL")
				quit(1)
			return false
		print("[b] 跳过按钮位于 ", skip.get_global_rect())
		clicks += 1
		_press_at(skip.get_global_rect().get_center())
		stage = 4
		frames = 6
		return false
	if stage == 4:
		# 跳过后:AI 继续行动,牌局推进(步骤增长即视为有反应)
		if table.steps_taken > 0 and table.phase != "await_response":
			print("[b] SKIP-CLICK-OK steps=", table.steps_taken)
			print("[b] ALL-OK")
			quit(0)
			return true
		if frames > 300:
			print("[b] SKIP-FAIL 无推进")
			quit(1)
			return true
	return false


func force_my_turn_discard() -> void:
	table.phase = "await_discard"
	table.current_seat = 0
	table.players[0].hand.append(table.wall.draw_top())
	table.players[0].just_drawn = table.players[0].hand[table.players[0].hand.size() - 1]
	table.human_discard(table.players[0].hand.size() - 1)
