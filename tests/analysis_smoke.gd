extends SceneTree
## 牌效分析加权验证:不同角色技能下面板概率应反映技能影响。

var main
var frames := 0
var ran := false


func _process(_d: float) -> bool:
	if ran:
		return false
	ran = true
	main = load("res://main.gd").new()
	root.add_child(main)
	main._picked_skill = "kuro"  # 玄:宝牌 ×4
	main._start_game()
	main._analyze_on = true
	main._refresh_analysis()
	var txt: String = main._analyze_label.text
	var line1: String = txt.split("\n")[0]
	print("[a] 玄: ", line1)
	# 数值验证:直接计算权重分布下的宝牌概率
	var me = main.table.players[0]
	var weights: Array = main._skill_draw_weights(me)
	var p: Array = main._draw_distribution(weights, main.table.wall.tiles_left())
	var dora_p := 0.0
	for k in main.table.wall.dora_kinds():
		dora_p += p[k]
	var wall_left: int = main.table.wall.tiles_left()
	var uniform_dora := 0.0
	for k in main.table.wall.dora_kinds():
		uniform_dora += main.table.wall.remaining_count(k) * 1.0 / wall_left
	print("[a] 玄宝牌概率=%.1f%%  均匀=%.1f%%  加权比值≈%.1f" % [dora_p * 100, uniform_dora * 100, dora_p / maxf(uniform_dora, 0.01)])
	quit(0)
	return false
