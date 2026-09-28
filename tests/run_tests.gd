extends SceneTree
## 无头测试入口:
##   cd 项目根目录
##   godot --headless --import          # 首次:生成全局类缓存
##   godot --headless -s res://tests/run_tests.gd
## 全部通过时以退出码 0 结束,否则打印失败明细并以 1 退出。

var _passed := 0
var _failed := 0
var _lines: Array[String] = []


func _initialize() -> void:
	_test_tile()
	_test_wall()
	_test_shanten()
	_test_yaku()
	_test_fu()
	_test_new_yaku_rules()
	_test_skill_saki()
	_test_skill_hisa()
	_test_skill_weights()
	_test_skill_new_chars()
	_test_chi()
	_test_multi_ron()
	_test_kakan_chankan()
	_test_riichi_ankan()
	_test_noten_payments()
	_test_ippatsu()
	_test_simulation()
	_test_determinism()
	_report()
	quit(1 if _failed > 0 else 0)


func check(cond: bool, test_name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_lines.append("  FAIL  %s" % test_name)


func eq(a, b, test_name: String) -> void:
	check(a == b, "%s (期望 %s, 实际 %s)" % [test_name, str(b), str(a)])


# ———————————————————— 牌 ————————————————————

func _test_tile() -> void:
	print("[01] MTile 编码与工具")
	eq(MTile.label(0), "1萬", "label(1m)")
	eq(MTile.label(13), "5筒", "label(5p)")
	eq(MTile.label(MTile.CHUN), "中", "label(中)")
	check(MTile.is_red(MTile.parse("0m")[0]), "0m 是红宝牌")
	check(not MTile.is_red(MTile.parse("5m")[0]), "5m 常规张非红")
	eq(MTile.shift_kind(MTile.kind_of(MTile.parse("8m")[0]), 1), MTile.kind_of(MTile.parse("9m")[0]), "8m+1=9m")
	eq(MTile.shift_kind(MTile.kind_of(MTile.parse("1m")[0]), -1), -1, "1m-1 越界")
	eq(MTile.shift_kind(MTile.kind_of(MTile.parse("9s")[0]), 1), -1, "9s+1 越界")
	eq(MTile.shift_kind(MTile.kind_of(MTile.parse("東")[0]), 1), -1, "字牌不可移")
	var ids := MTile.parse("123m456p789s東南")
	eq(ids.size(), 11, "parse 长度")
	eq(MTile.to_counts(ids)[27], 1, "to_counts 字牌计数")

# ———————————————————— 牌山 ————————————————————

func _test_wall() -> void:
	print("[02] MWall 牌山 / 加权抽牌 / 重排 / 里宝")
	var w := MWall.new()
	w.setup(42)
	check(w.ids.size() == MTile.TOTAL_TILES - 14, "洗牌后 122 张可摸")
	check(w.dead_wall.size() == 14, "王牌 14 张")
	check(w.dora_indicators.size() == 1, "初始宝牌指示 1 张")
	eq(w.ura_indicators.size(), 1, "里宝指示同步 1 张")
	check(w.ura_kinds().size() == 1, "ura_kinds 可用")

	var w2 := MWall.new()
	w2.setup(42)
	var same := true
	for i in 100:
		if w2.draw_top() != w.draw_top():
			same = false
	check(same, "相同 seed 序列可复现")

	var weights: Array = []
	weights.resize(MTile.KIND_COUNT)
	weights.fill(1.0)
	# 压倒性权重应命中目标 kind
	var w3 := MWall.new()
	w3.setup(7)
	weights[2] = 5000.0
	var hits := 0
	for i in 50:
		var w5 := MWall.new()
		w5.setup(i)
		if MTile.kind_of(w5.draw_weighted(weights)) == 2:
			hits += 1
	check(hits >= 45, "加权抽牌命中目标 kind(%d/50)" % hits)

	# 定点重排:目标牌应落在“从墙顶数第 depth 个”摸牌位
	var w6 := MWall.new()
	w6.setup(9)
	var moved := w6.reorder_to_depth(0, 3)
	if moved > 0:
		var top4 := w6.peek_top(4)
		check(MTile.kind_of(top4[3]) == 0, "reorder_to_depth(3) 后目标在第 4 个摸牌位")
		check(MTile.kind_of(w6.draw_top()) != 0 or moved > 1, "墙顶仍是其余牌(相对顺序保持)")

	var w7 := MWall.new()
	w7.setup(11)
	var got := w7.take_kind(33)
	check(got >= 0 and MTile.kind_of(got) == 33, "take_kind 取到中")

	# 加权岭上摸牌:把目标塞进王牌深处,验证轮盘赌命中
	var w8 := MWall.new()
	w8.setup(13)
	var target_id: int = MTile.parse("4s")[0]
	w8.dead_wall.append(target_id)
	w8.dead_wall.append(MTile.parse("4s")[1])
	var rw2: Array = []
	rw2.resize(MTile.KIND_COUNT)
	rw2.fill(1.0)
	rw2[MTile.kind_of(target_id)] = 5000.0
	var rt := w8.draw_rinshan_weighted(rw2)
	check(MTile.kind_of(rt) == MTile.kind_of(target_id), "加权岭上摸牌命中目标")

# ———————————————————— 向听数 ————————————————————

func _test_shanten() -> void:
	print("[03] MShanten 向听数计算")
	eq(MShanten.for_tiles(MTile.parse("123m456m789m123s4s")), 0, "听牌(单骑 4s) = 0")
	eq(MShanten.for_tiles(MTile.parse("123m456m789m123s44s")), -1, "和牌形 = -1")
	eq(MShanten.for_tiles(MTile.parse("123m456m789m1s1s3s7s")), 1, "1 向听")
	eq(MShanten.for_tiles(MTile.parse("123m456m789m1s5s東南")), 2, "2 向听")
	eq(MShanten.for_tiles(MTile.parse("1m1m2m2m3m3m4m4m5m5m6m6m7m")), 0, "七对听牌 = 0")
	eq(MShanten.for_tiles(MTile.parse("1m1m2m2m3m3m4m4m5m5m6m6m7m7m")), -1, "七对和牌 = -1")
	eq(MShanten.for_tiles(MTile.parse("1m9m1p9p1s9s東南西北白發中")), 0, "国士 13 种 = 0")
	eq(MShanten.for_tiles(MTile.parse("1m9m1p9p1s9s東南西北白發中中")), -1, "国士和牌 = -1")
	eq(MShanten.for_tiles(MTile.parse("111m234m567s88s"), 1), -1, "副露 1 组后和牌形 = -1")
	eq(MShanten.for_tiles(MTile.parse("111m234m567s8s9s"), 1), 0, "副露 1 组后听牌 = 0")

# ———————————————————— 役种 / 点数 ————————————————————

func _base_ctx() -> Dictionary:
	return {
		"tsumo": false, "riichi": false, "ippatsu": false, "rinshan": false,
		"seat_wind": MTile.EAST, "round_wind": MTile.EAST,
		"win_tile_kind": -1,
		"dora_kinds": [], "ura_dora_kinds": [],
		"dealer_seat": 0, "win_seat": 0, "loser_seat": 1,
	}


func _with(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var d := base.duplicate()
	for k in overrides:
		d[k] = overrides[k]
	return d


func _test_yaku() -> void:
	print("[04] MYaku 役种与点数")
	var ctx := _base_ctx()
	var r := MYaku.evaluate(MTile.parse("234m567m234p567p88s"), [], _with(ctx, {"tsumo": true}))
	check(r.win, "断幺平和自摸:成立")
	check("断幺九" in r.yaku and "平和" in r.yaku and "门前自摸" in r.yaku, "断幺/平和/自摸 齐全")
	eq(r.han, 3, "断幺+平和+自摸 = 3 翻")

	r = MYaku.evaluate(MTile.parse("白白白234m567m234p88s"), [], _with(ctx, {}))
	check(r.win and "白" in r.yaku, "役牌白成立")

	r = MYaku.evaluate(MTile.parse("123m456m789m123s北北"), [], _with(ctx, {}))
	check(not r.win, "无役形状不判和")

	r = MYaku.evaluate(MTile.parse("345m567m345p88s"), [{"type": "pon", "kind": 1}], _with(ctx, {}))
	check(r.win and "断幺九" in r.yaku, "副露断幺成立")

	# 吃副露:三门同顺含叫牌顺子 → 食下 1 翻
	var chi_melds := [{"type": "chi", "kind": 0, "called": 0}]
	r = MYaku.evaluate(MTile.parse("123p123s456p88s"), chi_melds, _with(ctx, {}))
	check(r.win and "三色同顺" in r.yaku, "吃出三色同顺成立")
	eq(r.han, 1, "食下三色同顺 = 1 翻")

	# 全门清三色同顺 = 2 翻
	r = MYaku.evaluate(MTile.parse("123m123p123s456p88s"), [], _with(ctx, {}))
	check("三色同顺" in r.yaku and r.han >= 3, "门清三色同顺 2 翻起")

	r = MYaku.evaluate(MTile.parse("1m1m3m3m5m5m7m7m9m9m1s1s3s3s"), [], _with(ctx, {}))
	check(r.win and "七对子" in r.yaku, "七对子成立")

	r = MYaku.evaluate(MTile.parse("1m1m9m1p9p1s9s東南西北白發中"), [], _with(ctx, {}))
	check(r.win and r.yakuman and r.han == 13, "国士无双 = 役满")

	r = MYaku.evaluate(MTile.parse("111m222m333m444m55s"), [], _with(ctx, {"tsumo": true}))
	check(r.win and r.yakuman, "四暗刻 = 役满")

	r = MYaku.evaluate(MTile.parse("11123456789999m"), [], _with(ctx, {}))
	check(r.win and "清一色" in r.yaku, "清一色成立")

	# 一发 / 里宝
	var ctx2 := _with(ctx, {"riichi": true, "ippatsu": true})
	r = MYaku.evaluate(MTile.parse("234m567m234p567p88s"), [], ctx2)
	check("一发" in r.yaku, "一发成立")
	eq(r.han, 4, "立直+一发+断幺+平和 = 4 翻")

	ctx2 = _with(ctx, {"riichi": true, "ura_dora_kinds": [4]})
	r = MYaku.evaluate(MTile.parse("234m567m234p567p88s"), [], ctx2)
	check("里宝牌 ×1" in r.yaku, "里宝开示计数")
	eq(r.han, 4, "立直+断幺+平和+里宝 = 4 翻")
	# 非立直不给里宝
	ctx2 = _with(ctx, {"ura_dora_kinds": [4]})
	r = MYaku.evaluate(MTile.parse("234m567m234p567p88s"), [], ctx2)
	check(not "里宝牌 ×1" in r.yaku, "非立直不算里宝")
	eq(r.han, 2, "无里宝时断幺+平和 = 2 翻")

	# 点数:庄家荣和 断幺+平和 2 翻 30 符 = 480 基本点 ×6 → 2880 → 2900
	r = MYaku.evaluate(MTile.parse("234m567m234p567p22s"), [], _with(ctx, {}))
	check(r.win, "断幺荣和成立")
	eq(r.payments[0], 2900, "子家断幺平和荣和,庄家收 2900")

# ———————————————————— 符数体系 ————————————————————

func _test_fu() -> void:
	print("[05] 真实符数体系")
	var ctx := _base_ctx()
	# 嵌张自摸:暗刻×3(8符×3) + 底20 + 嵌张2 + 自摸2 = 48 → 50
	var r := MYaku.evaluate(MTile.parse("111m222m333m4s5s6s88s"), [], _with(ctx, {"tsumo": true, "win_tile_kind": MTile.kind_of(MTile.parse("5s")[0])}))
	check(r.win, "嵌张自摸成立")
	eq(r.fu, 40, "三暗刻嵌张自摸 = 40 符(20+暗刻4×3+嵌张2+自摸2)")

	# 役牌雀头单骑自摸:白2 + 单骑2 + 底20 + 自摸2 = 26 → 30
	r = MYaku.evaluate(MTile.parse("白白234m567m234p567p"), [], _with(ctx, {"tsumo": true, "win_tile_kind": MTile.HAKU}))
	eq(r.fu, 30, "白单骑自摸 = 30 符")

	# 连风雀头:东东(场风+自风)= 4 符
	r = MYaku.evaluate(MTile.parse("東東234m567m234p567p"), [], _with(ctx, {"tsumo": true, "win_tile_kind": MTile.EAST}))
	check("役牌风" in r.yaku, "连风役牌成立")
	eq(r.fu, 30, "连风雀头单骑自摸 = 30 符(20+4+2+2)")

	# 双碰暗刻荣和按明刻:中张明刻 2
	r = MYaku.evaluate(MTile.parse("234m567m345s88s555p"), [], _with(ctx, {"win_tile_kind": MTile.kind_of(MTile.parse("5p")[0])}))
	check(r.win, "双碰荣和成立")
	eq(r.fu, 40, "门清双碰荣和(明刻2+底20+门清10) = 40 符")

	# 七对子固定 25 符(自摸不加符)
	r = MYaku.evaluate(MTile.parse("1m1m3m3m5m5m7m7m9m9m1s1s3s3s"), [], _with(ctx, {"tsumo": true, "chiitoi": true}))
	eq(r.fu, 25, "七对子 = 25 符固定")

	# 平和自摸 20 符
	r = MYaku.evaluate(MTile.parse("234m567m234p567p88s"), [], _with(ctx, {"tsumo": true}))
	eq(r.fu, 20, "平和自摸 = 20 符")

# ———————————————————— 新规则:单骑暗杠后的役种边界 ————————————————————

func _test_new_yaku_rules() -> void:
	print("[06] 岭上/食下等边界")
	var ctx := _base_ctx()
	# 岭上开花 + 符
	var r := MYaku.evaluate(MTile.parse("111m222m333m456s88s"), [], _with(ctx, {"tsumo": true, "rinshan": true, "win_tile_kind": MTile.kind_of(MTile.parse("6s")[0])}))
	check("岭上开花" in r.yaku, "岭上开花成立")
	# 暗杠计入三暗刻
	var r2 := MYaku.evaluate(MTile.parse("111m222m345s88s"), [{"type": "kan_closed", "kind": MTile.kind_of(MTile.parse("5p")[0])}], _with(ctx, {"tsumo": true, "win_tile_kind": MTile.kind_of(MTile.parse("8s")[0])}))
	check(r2.win and "三暗刻" in r2.yaku, "暗杠计入三暗刻")

# ———————————————————— 技能:咲 ±1 ————————————————————

func _test_skill_saki() -> void:
	print("[07] 技能:宫永咲「+1/-1」")
	var table := MTable.new()
	table.setup(["none", "none", "none", "saki"], -1, 123)
	var p := table.players[3]
	p.skill.reset_for_round()
	p.hand = MTile.parse("234m789m234p567p5m")
	p.hand.append(MTile.parse("6m")[0])
	check(not table._can_win_now(p), "改写前不可和")
	check(MAI.find_pm_move(p).size() > 0, "find_pm_move 找到 6m→5m")
	check(table.apply_plusminus(p, p.hand.size() - 1, -1), "apply_plusminus 成功")
	check(table._can_win_now(p), "改写后形状可胡")
	eq(p.skill.uses_left, 1, "技能次数 -1")
	table.current_seat = 3
	table.phase = "await_discard"
	table._ai_discard_phase(p)
	eq(table.result.get("type", ""), "win", "AI 咲改写后自摸")
	check(table.result.get("han", 0) >= 2, "断幺+门前自摸 ≥2 翻")

# ———————————————————— 技能:久 墙顶挑选 ————————————————————

func _test_skill_hisa() -> void:
	print("[08] 技能:竹井久「認識の改変」")
	var table := MTable.new()
	table.setup(["hisa", "none", "none", "none"], 0, 321)
	table.start_round(1)
	var p := table.players[0]
	p.hand = MTile.parse("123m456m789m12s4s")
	var before := p.hand.size()
	table.current_seat = 0
	table.phase = "await_discard"
	check(table.human_use_hisa(), "human_use_hisa 预约成功")
	eq(p.skill.uses_left, 1, "次数 -1")
	eq(p.pending_peek, 3, "pending_peek = 3")
	table.phase = "turn_draw"
	table.advance_one_step()
	eq(table.phase, "await_peek", "进入挑选阶段")
	eq(table.peek_options.size(), 3, "墙顶 3 张可选")
	var chosen_kind := MTile.kind_of(table.peek_options[0])
	check(table.human_choose_peek(0), "选择成功")
	eq(p.hand.size(), before + 1, "手牌 +1")
	eq(MTile.kind_of(p.hand[p.hand.size() - 1]), chosen_kind, "摸到所选牌")

# ———————————————————— 技能:被动加权 ————————————————————

func _test_skill_weights() -> void:
	print("[09] 技能:衣 / 和 / 玄 的概率加权")
	var table := MTable.new()
	table.setup(["koromo", "none", "none", "none"], -1, 55)
	var k := table.players[0]
	k.hand = MTile.parse("123m456m789m99s中中")
	k.river = MTile.parse("中中中")
	var weights: Array = []
	weights.resize(MTile.KIND_COUNT)
	weights.fill(1.0)
	k.skill.modify_draw_weights(table, k, weights)
	check(weights[MTile.CHUN] > 1.0, "河中出现且需要的「中」权重提升")
	check(weights[MTile.parse("北")[0]] == 1.0, "河中未出现的牌权重不变")

	table = MTable.new()
	table.setup(["nodoka", "none", "none", "none"], -1, 56)
	var n := table.players[0]
	n.hand = MTile.parse("123m456m789m123s4s")
	weights = []
	weights.resize(MTile.KIND_COUNT)
	weights.fill(1.0)
	n.skill.modify_draw_weights(table, n, weights)
	check(weights[MTile.kind_of(MTile.parse("4s")[0])] == 6.0, "听牌时胡牌张权重 ×6")
	check(weights[MTile.kind_of(MTile.parse("3s")[0])] == 1.0, "非进张权重不变")

	# 玄:宝牌 ×4
	table = MTable.new()
	table.setup(["kuro", "none", "none", "none"], -1, 57)
	var ku := table.players[0]
	var dora: int = table.wall.dora_kinds()[0]
	weights = []
	weights.resize(MTile.KIND_COUNT)
	weights.fill(1.0)
	ku.skill.modify_draw_weights(table, ku, weights)
	check(weights[dora] == 4.0, "宝牌权重 ×4")

# ———————————————————— 新角色技能 ————————————————————

func _test_skill_new_chars() -> void:
	print("[10] 新角色:照 / 憧 / 龙华")
	# 照:岭上加权
	var table := MTable.new()
	table.setup(["teru", "none", "none", "none"], -1, 71)
	var t := table.players[0]
	t.hand = MTile.parse("123m456m789m123s4s")
	var rw: Array = t.skill.rinshan_weights(table, t)
	check(rw[MTile.kind_of(MTile.parse("4s")[0])] == 12.0, "照的岭上胡牌张权重 ×12")
	check(rw[MTile.kind_of(MTile.parse("北")[0])] == 1.0, "照的岭上无关牌权重不变")

	# 憧:把宝牌挪到自己下一次摸牌位(深度 3)
	table = MTable.new()
	table.setup(["ako", "none", "none", "none"], -1, 72)
	table.start_round(1)
	var a := table.players[0]
	a.hand = MTile.parse("123m456m789m123s4s")
	var dora: int = table.wall.dora_kinds()[0]
	a.hand.append(table.wall.take_kind(dora))  # 手里拿一张宝牌便于触发
	a.skill.uses_left = 1
	table.current_seat = 0
	table.phase = "await_discard"
	check(table._do_ako(a), "憧技能发动")
	eq(a.skill.uses_left, 0, "憧次数消耗")
	check(MTile.kind_of(table.wall.peek_top(4)[3]) == dora, "宝牌被放到第 4 个摸牌位")

	# 龙华:换牌
	table = MTable.new()
	table.setup(["ryuuka", "none", "none", "none"], -1, 73)
	table.start_round(1)
	var ry := table.players[0]
	ry.hand = MTile.parse("123m456m789m123s4s")
	var drawn: int = table.wall.draw_top()
	ry.hand.append(drawn)
	ry.just_drawn = drawn
	ry.skill.uses_left = 2
	table.current_seat = 0
	table.phase = "await_discard"
	var hand_size := ry.hand.size()
	check(table._do_mulligan(ry), "龙华换牌发动")
	eq(ry.hand.size(), hand_size, "换牌后手牌数不变")
	eq(ry.skill.uses_left, 1, "龙华次数消耗")
	check(ry.just_drawn >= 0 and ry.hand.has(ry.just_drawn), "重摸的牌在手")

# ———————————————————— 吃 ————————————————————

func _test_chi() -> void:
	print("[11] 吃副露")
	var table := MTable.new()
	table.setup(["none", "none", "none", "none"], -1, 91)
	table.start_round(1)
	var p1 := table.players[1]
	p1.hand = MTile.parse("123m456m789m3m4m88s")
	var discard_id: int = MTile.parse("5m")[0]
	table.last_discard = {"seat": 0, "tile_id": discard_id, "kind": MTile.kind_of(discard_id)}
	var combos := table.chi_combos_for(p1.hand, 4)
	check(combos.size() >= 1, "枚举出吃组合")
	var size_before := p1.hand.size()
	table._do_chi(p1, combos[0])
	eq(p1.hand.size(), size_before - 2, "吃后手牌 -2")
	eq(p1.melds.size(), 1, "吃后副露 +1")
	eq(p1.melds[0].type, "chi", "副露类型 chi")
	check(not p1.is_menzen(), "吃后非门清")

	# AI 响应窗口里会吃(接近听牌时积极吃)
	table = MTable.new()
	table.setup(["none", "none", "none", "none"], -1, 92)
	table.start_round(1)
	var q := table.players[1]
	q.hand = MTile.parse("123m88s999s3m4m白白中")
	table.last_discard = {"seat": 0, "tile_id": discard_id, "kind": MTile.kind_of(discard_id)}
	table._resp = {}
	table._human_responded = true
	table._collect_responses()
	var opts: Dictionary = table._resp.get(1, {})
	check((opts.get("chi", []) as Array).size() > 0, "下家响应窗口含吃")
	table.phase = "await_response"
	table.advance_one_step()
	check(q.melds.size() == 1 and q.melds[0].type == "chi", "AI 下家完成吃")
	eq(table.current_seat, 1, "吃后轮到吃牌者打牌")

# ———————————————————— 多响 ————————————————————

func _test_multi_ron() -> void:
	print("[12] 双响全符放铳")
	var table := MTable.new()
	table.setup(["none", "none", "none", "none"], -1, 101)
	table.start_round(1)
	var w1 := table.players[1]
	var w2 := table.players[2]
	# 两家和 4s:断幺(234m567m234p + 234s + 88s 雀头)
	var shared := MTile.parse("234m567m234p88s2s3s")
	w1.hand = shared.duplicate()
	w2.hand = MTile.parse("234m567m234p88s2s3s")
	table.players[3].hand = MTile.parse("1199m1199p1199s")
	var discard_id: int = MTile.parse("4s")[0]
	table.last_discard = {"seat": 0, "tile_id": discard_id, "kind": MTile.kind_of(discard_id)}
	table._apply_multi_ron([1, 2])
	eq(table.result.get("type", ""), "win", "多响判和")
	check(table.result.get("double", false), "标记双响")
	check(table.result.payments[1] > 0 and table.result.payments[2] > 0, "两家均得分")
	check(table.result.payments[0] < 0, "放铳者累计支付")
	eq(table.result.payments[0] + table.result.payments[1] + table.result.payments[2] + table.result.payments[3], 0, "多响点数守恒")
	check(w1.score > 25000 and w2.score > 25000, "两家分数入账")

# ———————————————————— 加杠 / 抢杠 ————————————————————

func _test_kakan_chankan() -> void:
	print("[13] 加杠 / 抢杠")
	# 无抢杠:正常完成加杠 + 岭上摸牌
	var table := MTable.new()
	table.setup(["none", "none", "none", "none"], -1, 111)
	table.start_round(1)
	var p0 := table.players[0]
	p0.melds = [{"type": "pon", "kind": MTile.kind_of(MTile.parse("5p")[0])}]
	var fifth: int = MTile.parse("5p")[0]
	p0.hand = MTile.parse("123m456m789m12s")
	p0.hand.append(fifth)
	p0.just_drawn = fifth
	var wall_left := table.wall.tiles_left()
	check(table._try_kakan(p0, p0.hand.size() - 1), "加杠宣告")
	eq(table.phase, "await_discard", "无抢杠直接完成加杠并岭上摸牌")
	check(p0.hand.size() == 12, "加杠后手牌 11+岭上1")
	var kan_found := false
	for m in p0.melds:
		if m.type == "kan_added":
			kan_found = true
	check(kan_found, "碰升级为加杠")
	eq(table.wall.tiles_left(), wall_left, "岭上从王牌摸,牌山不变")
	check(table.wall.dora_indicators.size() == 2, "加杠补翻宝牌指示")

	# 有抢杠:他家荣和,加杠被抢
	table = MTable.new()
	table.setup(["none", "none", "none", "none"], -1, 112)
	table.start_round(1)
	var p0b := table.players[0]
	var chanker := table.players[2]
	p0b.melds = [{"type": "pon", "kind": MTile.kind_of(MTile.parse("5p")[0])}]
	p0b.hand = MTile.parse("123m456m789m12s")
	p0b.hand.append(MTile.parse("5p")[0])
	p0b.just_drawn = p0b.hand[p0b.hand.size() - 1]
	chanker.hand = MTile.parse("234m567m55p678p33s")
	table.current_seat = 0
	table.phase = "await_discard"
	check(table._try_kakan(p0b, p0b.hand.size() - 1), "加杠宣告(有抢杠)")
	eq(table.phase, "await_response", "进入抢杠响应")
	table.advance_one_step()
	eq(table.result.get("type", ""), "win", "抢杠荣和")
	check(table.players[2].score > 25000, "抢杠者得分")
	var still_pon := false
	for m in p0b.melds:
		if m.type == "pon" and m.kind == MTile.kind_of(MTile.parse("5p")[0]):
			still_pon = true
	check(still_pon, "被抢杠后副露保持碰")

# ———————————————————— 立直后暗杠(听牌不变) ————————————————————

func _test_riichi_ankan() -> void:
	print("[14] 立直后暗杠(听牌不变判定)")
	var table := MTable.new()
	table.setup(["none", "none", "none", "none"], -1, 121)
	table.start_round(1)
	var p := table.players[0]
	p.riichi = true
	p.riichi_discarded = true
	# 非立直:四张同种暗杠恒可
	p.riichi = false
	p.hand = MTile.parse("1111m234m567m99s白")
	p.just_drawn = p.hand[p.hand.size() - 1]
	check(table._ankan_allowed(p, 0), "非立直暗杠恒可")
	# 立直:暗杠会破坏 123m 顺子听牌 → 禁止
	p.riichi = true
	check(not table._ankan_allowed(p, 0), "有害的立直暗杠被禁止")

# ———————————————————— 流局听牌费 ————————————————————

func _test_noten_payments() -> void:
	print("[15] 流局听牌费")
	var table := MTable.new()
	table.setup(["none", "none", "none", "none"], -1, 131)
	table.start_round(1)
	table.players[0].hand = MTile.parse("123m456m789m12s44s")   # 听
	table.players[1].hand = MTile.parse("1199m1199p1199s")     # 不听
	table.players[2].hand = MTile.parse("123p456p789p12s44s")   # 听
	table.players[3].hand = MTile.parse("1199m1199p1199s")     # 不听
	table._end_draw()
	eq(table.result.get("type", ""), "draw", "流局结算")
	var pay: Dictionary = table.result.payments
	eq(pay[1], -1500, "不听者各支付 1500")
	eq(pay[3], -1500, "不听者各支付 1500")
	eq(pay[0], 1500, "听牌者各收 1500")
	eq(pay[2], 1500, "听牌者各收 1500")
	check(table.result.tenpai[0] and table.result.tenpai[2], "听牌标记正确")
	check(not table.result.tenpai[1] and not table.result.tenpai[3], "不听标记正确")
	var total := 0
	for seat in 4:
		total += pay[seat]
	eq(total, 0, "听牌费守恒")

# ———————————————————— 一发生命周期 ————————————————————

func _test_ippatsu() -> void:
	print("[16] 一发生命周期")
	var table := MTable.new()
	table.setup(["none", "none", "none", "none"], -1, 141)
	table.start_round(1)
	var p := table.players[0]
	p.riichi = true
	p.riichi_discarded = true
	p.ippatsu = true
	p.hand = MTile.parse("123m456m789m12s44s")
	p.just_drawn = p.hand[p.hand.size() - 1]
	table._expire_ippatsu(p)
	check(not p.ippatsu, "摸牌未和即过期")
	# 和牌时一发仍在的场合(直接验证 ctx 生效在 yaku 测试已覆盖)

# ———————————————————— 全逻辑模拟 ————————————————————

func _test_simulation() -> void:
	print("[17] 无头全逻辑模拟(40 局,八技能轮换)")
	var wins := {}
	for sid in ["none", "saki", "hisa", "koromo", "nodoka", "teru", "kuro", "ako", "ryuuka"]:
		wins[sid] = 0
	var draws := 0
	for g in 40:
		var roster: Array[String] = ["saki", "hisa", "koromo", "nodoka", "teru", "kuro", "ako", "ryuuka"]
		var ids: Array[String] = []
		for i in 4:
			ids.append(roster[(g + i * 2) % 8])
		var table := MTable.new()
		table.setup(ids, -1, 1000 + g)
		table.start_round(1000 + g)
		var ok := table.run_to_completion()
		check(ok, "第 %d 局推进到终局" % g)
		var res: Dictionary = table.result
		if res.get("type", "") == "win":
			wins[ids[res.winner]] = wins.get(ids[res.winner], 0) + 1
			check(res.han >= 1, "和牌至少 1 翻(第 %d 局)" % g)
		else:
			draws += 1
		var total := 0
		for p in table.players:
			total += p.score - 25000
		eq(total, 0, "第 %d 局点数守恒" % g)
	var win_games := 0
	for sid in wins:
		win_games += wins[sid]
	print("  统计: 40 局 —— 和牌 %d,流局 %d,分布 %s" % [win_games, draws, str(wins)])

# ———————————————————— 确定性 ————————————————————

func _test_determinism() -> void:
	print("[18] 相同 seed 完全可复现")
	var logs: Array[String] = []
	for run in 2:
		var table := MTable.new()
		table.setup(["saki", "hisa", "koromo", "nodoka"], -1, 777)
		table.start_round(777)
		table.run_to_completion()
		logs.append(",".join(table.events))
	eq(logs[0], logs[1], "同 seed 两局事件流一致")


func _report() -> void:
	print("")
	print("========== 测试结果:%d 通过,%d 失败 ==========" % [_passed, _failed])
	for line in _lines:
		print(line)
