extends SceneTree
## 配对 A/B 因果实验:同一批 seed、同一座位,分别以“某技能”和“无技能”各跑一局,
## 比较该座位和牌率。配对设计消除座位/牌运差异,只剩技能本身的因果效应。
##   godot --headless -s res://tests/paired.gd

const GAMES := 60


func _initialize() -> void:
	var only := ""
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0:
		only = user_args[0]
	var t0 := Time.get_ticks_msec()
	for sid in ["saki", "hisa", "koromo", "nodoka", "teru", "kuro", "ako", "ryuuka"]:
		if only != "" and sid != only:
			continue
		var win_a := 0  # 有技能
		var win_b := 0  # 无技能(同 seed 同座位)
		for g in GAMES:
			var seat := g % 4
			var seed_v := 90000 + g * 77
			# A:技能座位
			var ids: Array[String] = ["none", "none", "none", "none"]
			ids[seat] = sid
			var ta := MTable.new()
			ta.setup(ids, -1, seed_v)
			ta.start_round(seed_v)
			ta.run_to_completion()
			if ta.result.get("type", "") == "win" and ta.result.winner == seat:
				win_a += 1
			# B:同 seed 全素人
			var tb := MTable.new()
			tb.setup(["none", "none", "none", "none"], -1, seed_v)
			tb.start_round(seed_v)
			tb.run_to_completion()
			if tb.result.get("type", "") == "win" and tb.result.winner == seat:
				win_b += 1
		print("%-8s 有技能 %2d/%d(%3d%%)  vs  无技能 %2d/%d(%3d%%)  差值 %+d" % [
			sid, win_a, GAMES, win_a * 100 / GAMES,
			win_b, GAMES, win_b * 100 / GAMES, win_a - win_b,
		])
	print("耗时 %d ms" % (Time.get_ticks_msec() - t0))
	quit(0)
