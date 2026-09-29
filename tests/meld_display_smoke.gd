extends SceneTree
## 鸣牌副露显示测试:直接驱动碰/吃,验证副露控件渲染与位置。

var main


func _initialize() -> void:
	main = load("res://main.gd").new()
	root.add_child(main)
	main._picked_skill = "saki"
	main._start_game()
	var table: MTable = main.table
	# AI(座位1)碰 白
	table.last_discard = {"seat": 0, "tile_id": MTile.parse("白")[0], "kind": MTile.HAKU}
	table._do_pon(table.players[1])
	main._refresh()
	var b1: Control = main._meld_boxes[1]
	print("[m1] 座位1碰后 melds=", table.players[1].melds.size(), " 控件=", b1.get_child_count(), " 位置=", b1.get_child(0).get_global_rect().position if b1.get_child_count() > 0 else "无")
	# 上家(座位3)吃 一筒二筒三筒 中的 3m
	table.last_discard = {"seat": 0, "tile_id": MTile.parse("3m")[0], "kind": 2}
	table.players[3].hand = MTile.parse("1m2m456p789s白白")
	table._do_chi(table.players[3], {"called": 2, "tiles": [MTile.parse("1m")[0], MTile.parse("2m")[0]], "low": 0})
	main._refresh()
	var b3: Control = main._meld_boxes[3]
	print("[m2] 座位3吃后 melds=", table.players[3].melds.size(), " 控件=", b3.get_child_count())
	for c in b3.get_children():
		var cc := c as Control
		print("   [m2] tile global=", cc.get_global_rect().position, " size=", cc.size)
	# 下家(座位1)明杠 中
	table.last_discard = {"seat": 0, "tile_id": MTile.parse("中")[0], "kind": MTile.CHUN}
	table._do_daiminkan(table.players[1])
	main._refresh()
	var b1b: Control = main._meld_boxes[1]
	print("[m3] 座位1杠后 melds=", table.players[1].melds.size(), " 控件=", b1b.get_child_count())
	quit(0)
