extends SceneTree
## 技能强度统计模拟(无头):
##   godot --headless -s res://tests/stats.gd
## 每个技能各 N 局:该技能角色 + 三个素人同桌,分别统计
## 「技能座位和牌率」与「整局和牌率 / 流局率」,验证“抽牌取决于技能与概率”。

const GAMES_PER_SKILL := 60

var _skills: Array[String] = ["none", "saki", "hisa", "koromo", "nodoka"]


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var ron_total := 0
	var tsumo_total := 0
	for sid in _skills:
		var seat_wins := 0
		var any_wins := 0
		var draws := 0
		var steps_sum := 0
		for g in GAMES_PER_SKILL:
			var ids: Array[String] = ["none", "none", "none", "none"]
			var seat := g % 4
			ids[seat] = sid
			var seed_v := 50000 + g * 131 + sid.hash() % 997
			var table := MTable.new()
			table.setup(ids, -1, seed_v)
			table.start_round(seed_v)
			table.run_to_completion()
			var res: Dictionary = table.result
			steps_sum += table.steps_taken
			if res.get("type", "") == "win":
				any_wins += 1
				if res.tsumo:
					tsumo_total += 1
				else:
					ron_total += 1
				if res.winner == seat:
					seat_wins += 1
			else:
				draws += 1
		print("%-8s 技能座位和牌 %2d/%d(%3d%%)  整局和牌率 %3d%%  流局 %2d  平均步数 %3d" % [
			sid, seat_wins, GAMES_PER_SKILL, seat_wins * 100 / GAMES_PER_SKILL,
			any_wins * 100 / GAMES_PER_SKILL, draws, steps_sum / GAMES_PER_SKILL,
		])
	print("全部对局中:荣和 %d / 自摸 %d" % [ron_total, tsumo_total])
	print("耗时 %d ms" % (Time.get_ticks_msec() - t0))
	quit(0)
