extends SceneTree
## 难度对照:同 seed 同座位,AI 困难(2) vs 普通(1),各 N 局比和牌率。
const GAMES := 30

func _initialize() -> void:
	var win_hard := 0
	var win_norm := 0
	for g in GAMES:
		var seat := g % 4
		var seed_v := 70000 + g * 97
		for diff in [2, 1]:
			var ids: Array[String] = ["none", "none", "none", "none"]
			ids[seat] = "none"
			var table := MTable.new()
			table.setup(ids, -1, seed_v)
			for p in table.players:
				p.ai_difficulty = diff if p.seat == seat else 1
			table.start_round(seed_v)
			table.run_to_completion()
			if table.result.get("type", "") == "win" and table.result.winner == seat:
				if diff == 2:
					win_hard += 1
				else:
					win_norm += 1
	print("困难座位和牌 %d/%d(%.0f%%)  vs  普通 %d/%d(%.0f%%)" % [
		win_hard, GAMES, win_hard * 100.0 / GAMES,
		win_norm, GAMES, win_norm * 100.0 / GAMES])
	quit(0)
