class_name MYaku
extends RefCounted
## 胡牌判定 / 役种 / 符数 / 点数:纯算法。
##
## 副露表示:Array[Dictionary]:
##   { "type": "pon"|"kan_open"|"kan_closed"|"kan_added", "kind": int }
##   { "type": "chi", "kind": 顺子最小 kind, "called": 0|1|2 (叫牌在顺子中的位置) }
##
## ctx(和牌上下文):
##   tsumo / riichi / rinshan / ippatsu: bool
##   seat_wind / round_wind: int
##   win_tile_kind: int          和牌张 kind(符数的听牌形判定用;自摸=摸到的牌)
##   dora_kinds: Array[int]      宝牌(表)
##   ura_dora_kinds: Array[int]  里宝(仅立直和牌时由 Table 传入)
##   dealer_seat / win_seat / loser_seat: int
## 返回:{ win, han, fu, yaku, yakuman, payments }

const YAKUMAN_HAN: int = 13


static func can_win(concealed_counts: Array[int], meld_count: int) -> bool:
	if meld_count == 0:
		if _chiitoi_ok(concealed_counts) or _kokushi_ok(concealed_counts):
			return true
	var counts := concealed_counts.duplicate()
	for pair_kind in MTile.KIND_COUNT:
		if counts[pair_kind] < 2:
			continue
		counts[pair_kind] -= 2
		var ok := _decompose_all(counts.duplicate(), 4 - meld_count).size() > 0
		counts[pair_kind] += 2
		if ok:
			return true
	return false


## 综合评估:枚举全部分解,按“翻数 → 符数”取最优组合。
static func evaluate(concealed_tiles: Array, melds: Array, ctx: Dictionary) -> Dictionary:
	var counts := MTile.to_counts(concealed_tiles)
	var meld_count := melds.size()
	var best := {"win": false, "han": -1, "fu": 0, "yaku": [], "yakuman": false}

	if meld_count == 0:
		if _chiitoi_ok(counts):
			_consider(best, 2, 25, ["七对子"], false)
		if _kokushi_ok(counts):
			_consider(best, YAKUMAN_HAN, 20, ["国士无双"], true)

	var need := 4 - meld_count
	var win_kind: int = ctx.get("win_tile_kind", -1)
	for pair_kind in MTile.KIND_COUNT:
		if counts[pair_kind] < 2:
			continue
		counts[pair_kind] -= 2
		for sets in _decompose_all(counts.duplicate(), need):
			var info := _score_sets(sets, pair_kind, melds, ctx)
			_consider(best, info.han, info.fu, info.yaku, info.yakuman)
		counts[pair_kind] += 2
	# 七对子的符数固定,若标准形翻数相同但未胜则保留七对结果(上面 _consider 已按翻数取优)。

	if not best.win:
		return best

	# —— 宝牌 / 里宝 / 红宝牌(役满不累计)——
	if not best.yakuman:
		for kind in ctx.get("dora_kinds", []):
			var n := _count_kind_in_hand(counts, melds, kind)
			if n > 0:
				best.han += n
				best.yaku.append("宝牌 ×%d" % n)
		if ctx.get("riichi", false):
			for kind in ctx.get("ura_dora_kinds", []):
				var n2 := _count_kind_in_hand(counts, melds, kind)
				if n2 > 0:
					best.han += n2
					best.yaku.append("里宝牌 ×%d" % n2)
		var red := 0
		for id in concealed_tiles:
			if MTile.is_red(id):
				red += 1
		if red > 0:
			best.yaku.append("红宝牌 ×%d" % red)
			best.han += red

	best.payments = _payments(best.han, best.fu, ctx)
	return best


static func _count_kind_in_hand(counts: Array[int], melds: Array, kind: int) -> int:
	var n: int = counts[kind]
	for m in melds:
		if m.type == "chi":
			continue
		if m.kind == kind:
			n += 4 if (m.type == "kan_open" or m.type == "kan_closed" or m.type == "kan_added") else 3
	return n


static func _consider(best: Dictionary, han: int, fu: int, yaku: Array, yakuman: bool) -> void:
	# 同翻数时取符数更高的分解(更接近真实记符)
	if han > best.han or (han == best.han and fu > best.fu and best.win):
		best.win = true
		best.han = han
		best.fu = fu
		best.yaku = yaku
		best.yakuman = yakuman


static func _chiitoi_ok(counts: Array[int]) -> bool:
	for kind in MTile.KIND_COUNT:
		if counts[kind] != 0 and counts[kind] != 2:
			return false
	return true


static func _kokushi_ok(counts: Array[int]) -> bool:
	for kind in MTile.TERMINAL_KINDS:
		if counts[kind] == 0:
			return false
	for kind in MTile.KIND_COUNT:
		if not MTile.is_terminal(kind) and counts[kind] > 0:
			return false
	return true


## 枚举暗牌拆成恰好 need 组面子的所有方案。
static func _decompose_all(counts: Array[int], need: int) -> Array:
	var out: Array = []
	if need == 0:
		out.append([])
	else:
		_decompose_rec(counts, 0, need, [], out)
	return out


static func _decompose_rec(counts: Array[int], i: int, remaining: int, current: Array, out: Array) -> void:
	while i < MTile.KIND_COUNT and counts[i] == 0:
		i += 1
	if i >= MTile.KIND_COUNT:
		if remaining == 0:
			out.append(current.duplicate(true))
		return
	if remaining <= 0:
		return
	if counts[i] >= 3:
		counts[i] -= 3
		current.append({"type": "tri", "kind": i})
		_decompose_rec(counts, i, remaining - 1, current, out)
		current.pop_back()
		counts[i] += 3
	if i < 27 and i % 9 <= 6 and counts[i + 1] > 0 and counts[i + 2] > 0:
		counts[i] -= 1
		counts[i + 1] -= 1
		counts[i + 2] -= 1
		current.append({"type": "run", "kind": i})
		_decompose_rec(counts, i, remaining - 1, current, out)
		current.pop_back()
		counts[i] += 1
		counts[i + 1] += 1
		counts[i + 2] += 1


## 一组面子的全部实体 kind(chi 顺子取 k,k+1,k+2;pon 3 张;杠 4 张)。
static func _set_kinds(s: Dictionary) -> Array[int]:
	if s.type == "tri":
		return [s.kind, s.kind, s.kind]
	return [s.kind, s.kind + 1, s.kind + 2]


static func _meld_kinds(m: Dictionary) -> Array[int]:
	match m.type:
		"chi":
			return [m.kind, m.kind + 1, m.kind + 2]
		"kan_open", "kan_closed", "kan_added":
			return [m.kind, m.kind, m.kind, m.kind]
		_:
			return [m.kind, m.kind, m.kind]


## 对一种分解计算役种/翻/符。
static func _score_sets(sets: Array, pair_kind: int, melds: Array, ctx: Dictionary) -> Dictionary:
	var menzen := _is_menzen(melds)
	var tsumo: bool = ctx.get("tsumo", false)
	var win_kind: int = ctx.get("win_tile_kind", -1)

	var kinds: Array[int] = [pair_kind, pair_kind]
	for s in sets:
		for k in _set_kinds(s):
			kinds.append(k)
	for m in melds:
		for k in _meld_kinds(m):
			kinds.append(k)

	# —— 听牌形符(需要先于平和判定)。和牌张所在的面子决定待形:
	#    单一顺子内 = 嵌张/边张/两面;单一暗刻 = 双碰刻子;雀头 = 单骑;
	#    两组顺子都含和牌张 = 双碰两面(0 符,平和可)。
	var win_runs: Array = []
	var win_tri_count := 0
	var win_in_pair: bool = pair_kind == win_kind
	for s in sets:
		if s.type == "run" and win_kind >= s.kind and win_kind <= s.kind + 2:
			win_runs.append(s)
		if s.type == "tri" and win_kind == s.kind:
			win_tri_count += 1
	var win_run_count := win_runs.size()
	var wait_fu := 0
	if win_run_count == 1:
		var s: Dictionary = win_runs[0]
		if win_kind == s.kind + 1:
			wait_fu = 2  # 嵌张
		elif win_kind == s.kind and s.kind + 2 == 9:
			wait_fu = 2  # 边张(8-9 等 7)
		elif win_kind == s.kind + 2 and s.kind == 1:
			wait_fu = 2  # 边张(1-2 等 3)
		# 其余 = 两面,0 符

	# —— 役满 ——
	var concealed_tris := 0
	var all_tris := true
	for s in sets:
		if s.type == "tri":
			concealed_tris += 1
		else:
			all_tris = false
	for m in melds:
		if m.type == "kan_closed":
			concealed_tris += 1  # 暗杠视作暗刻
		elif m.type != "pon":
			all_tris = false
	if all_tris and concealed_tris == 4:
		return {"han": YAKUMAN_HAN, "fu": 20, "yaku": ["四暗刻"], "yakuman": true}
	var dragons := 0
	for d in [MTile.HAKU, MTile.HATSU, MTile.CHUN]:
		if _owns(d, pair_kind, sets, melds):
			dragons += 1
	if dragons == 3:
		return {"han": YAKUMAN_HAN, "fu": 20, "yaku": ["大三元"], "yakuman": true}
	if _all_kind(kinds, func(k): return MTile.is_honor(k)):
		return {"han": YAKUMAN_HAN, "fu": 20, "yaku": ["字一色"], "yakuman": true}
	if _all_kind(kinds, func(k): return MTile.is_terminal(k)):
		return {"han": YAKUMAN_HAN, "fu": 20, "yaku": ["清老头"], "yakuman": true}

	# —— 常规役 ——
	var yaku: Array = []
	var han := 0
	if ctx.get("riichi", false):
		yaku.append("立直")
		han += 1
	if ctx.get("ippatsu", false):
		yaku.append("一发")
		han += 1
	if menzen and tsumo:
		yaku.append("门前自摸")
		han += 1
	if ctx.get("rinshan", false):
		yaku.append("岭上开花")
		han += 1

	var pinfu := false
	var toitoi := true
	for s in sets:
		if s.type != "tri":
			toitoi = false
	for m in melds:
		if m.type == "chi":
			toitoi = false

	var all_runs := melds.is_empty()
	for s in sets:
		if s.type != "run":
			all_runs = false
	var has_wait := win_tri_count == 1 or win_in_pair or (win_run_count == 1 and wait_fu > 0)
	pinfu = all_runs and menzen and not MTile.is_honor(pair_kind) and not has_wait

	var all_simple := not MTile.is_terminal(pair_kind)
	for k in kinds:
		if k != pair_kind and MTile.is_terminal(k):
			all_simple = false
			break
	if all_simple:
		yaku.append("断幺九")
		han += 1

	if pinfu:
		yaku.append("平和")
		han += 1

	# 役牌(雀头 / 面子)
	for d in [MTile.HAKU, MTile.HATSU, MTile.CHUN]:
		if _owns(d, pair_kind, sets, melds):
			yaku.append(["白", "發", "中"][d - MTile.HAKU])
			han += 1
	for wind in [ctx.get("round_wind", -1), ctx.get("seat_wind", -1)]:
		if wind >= MTile.EAST and _owns(wind, pair_kind, sets, melds):
			yaku.append("役牌风")
			han += 1

	# 一杯口 / 二杯口(门前)
	if menzen:
		var run_sig := {}
		for s in sets:
			if s.type == "run":
				run_sig[s.kind] = run_sig.get(s.kind, 0) + 1
		var cups := 0
		for sig in run_sig:
			if run_sig[sig] >= 2:
				cups += 1
		if cups >= 1:
			yaku.append("一杯口")
			han += 1
		if cups >= 2:
			yaku.append("二杯口")
			han += 2

	# 三色同顺 / 一气通贯(鸣牌含叫牌张时食下减 1 翻)
	var suit_runs := [{}, {}, {}]
	for s in sets:
		if s.type == "run":
			var su: int = MTile.suit(s.kind)
			suit_runs[su][s.kind % 9] = true
	for m in melds:
		if m.type == "chi":
			suit_runs[MTile.suit(m.kind)][m.kind % 9] = true
	for r in 7:
		if suit_runs[0].get(r, false) and suit_runs[1].get(r, false) and suit_runs[2].get(r, false):
			var called := _group_has_called(melds, r)
			yaku.append("三色同顺")
			han += 1 if called else 2
			break
	for su in 3:
		var straight := true
		for r in 9:
			if suit_runs[su].get(r, false) == false:
				straight = false
		if straight:
			var called2 := false
			for m in melds:
				if m.type == "chi" and MTile.suit(m.kind) == su:
					called2 = true
			yaku.append("一气通贯")
			han += 1 if called2 else 2
			break

	if toitoi:
		yaku.append("对对和")
		han += 2
	if concealed_tris >= 3:
		yaku.append("三暗刻")
		han += 2

	# 混一色 / 清一色 / 混老头
	var number_suits := {}
	var has_honor := MTile.is_honor(pair_kind)
	for k in kinds:
		if MTile.is_honor(k):
			has_honor = true
		else:
			number_suits[MTile.suit(k)] = true
	if number_suits.size() == 1:
		if has_honor:
			yaku.append("混一色")
			han += 3
			if _all_kind(kinds, func(k): return MTile.is_terminal(k)):
				yaku.append("混老头")
				han += 3
		else:
			yaku.append("清一色")
			han += 6

	if yaku.is_empty():
		return {"han": -1, "fu": 0, "yaku": [], "yakuman": false}

	var fu := _fu(sets, pair_kind, melds, ctx, pinfu, win_run_count, win_tri_count, win_in_pair, wait_fu)
	return {"han": han, "fu": fu, "yaku": yaku, "yakuman": false}


## 三色同顺中 rank r 的三组顺子是否含叫牌顺子(食下)。
static func _group_has_called(melds: Array, r: int) -> bool:
	for m in melds:
		if m.type == "chi" and m.kind % 9 == r:
			return true
	return false


static func _owns(kind: int, pair_kind: int, sets: Array, melds: Array) -> bool:
	if pair_kind == kind:
		return true
	for s in sets:
		if s.type == "tri" and s.kind == kind:
			return true
	for m in melds:
		if m.kind == kind:
			return true
	return false


static func _is_menzen(melds: Array) -> bool:
	for m in melds:
		if m.type != "kan_closed":
			return false
	return true


static func _all_kind(kinds: Array, pred: Callable) -> bool:
	for k in kinds:
		if not pred.call(k):
			return false
	return true


## 真实符数:底符 20 + 雀头符 + 面子符 + 听牌形符 + 门前荣和 10 / 自摸 2;
## 平和荣和 30 / 平和自摸 20;七对子固定 25;双碰暗刻荣和按明刻计。
static func _fu(sets: Array, pair_kind: int, melds: Array, ctx: Dictionary, pinfu: bool,
		win_run_count: int, win_tri_count: int, win_in_pair: bool, wait_fu: int) -> int:
	if ctx.get("chiitoi", false):
		return 25
	if pinfu:
		return 30 if not ctx.get("tsumo", false) else 20
	var fu := 20
	# 雀头符:三元 2;自风/场风各 2,连风共 4
	if pair_kind >= MTile.HAKU and pair_kind <= MTile.CHUN:
		fu += 2
	else:
		if ctx.get("seat_wind", -1) == pair_kind:
			fu += 2
		if ctx.get("round_wind", -1) == pair_kind:
			fu += 2
	# 面子符:中张 明刻2 暗刻4 明杠8 暗杠16;幺九 翻倍
	for s in sets:
		if s.type == "tri":
			var open_by_ron: bool = win_tri_count == 1 \
				and ctx.get("win_tile_kind", -1) == s.kind and not ctx.get("tsumo", false)
			fu += _triplet_fu(s.kind, not open_by_ron, false)
	for m in melds:
		match m.type:
			"pon":
				fu += _triplet_fu(m.kind, false, false)
			"kan_open", "kan_added":
				fu += _triplet_fu(m.kind, false, true)
			"kan_closed":
				fu += _triplet_fu(m.kind, true, true)
			"chi":
				pass
	# 听牌形符:嵌张/边张 +2;单骑 +2(役牌雀头单骑可与雀头符叠加)
	var win_kind: int = ctx.get("win_tile_kind", -1)
	if win_in_pair:
		fu += 2
	else:
		fu += wait_fu
	if ctx.get("tsumo", false):
		fu += 2
	elif _is_menzen(melds):
		fu += 10
	return maxi(20, int(ceil(fu / 10.0)) * 10)


## 刻/杠符:中张 明2 暗4;幺九 明4 暗8;杠 ×4。
static func _triplet_fu(kind: int, concealed: bool, kan: bool) -> int:
	var base := 8 if MTile.is_terminal(kind) else 4
	if not concealed:
		base /= 2
	return base * 4 if kan else base


## 点数分配:荣和=放铳者支付;多响时各自满额由放铳者累计支付(不采用头跳)。
static func _payments(han: int, fu: int, ctx: Dictionary) -> Dictionary:
	var base := _base_points(han, fu)
	var tsumo: bool = ctx.get("tsumo", false)
	var win_seat: int = ctx.get("win_seat", 0)
	var dealer: int = ctx.get("dealer_seat", 0)
	var is_dealer := win_seat == dealer
	var payments := {}
	for seat in 4:
		payments[seat] = 0
	if tsumo:
		for seat in 4:
			if seat == win_seat:
				continue
			var amt: int = base * 2 if (seat == dealer or is_dealer) else base
			payments[seat] -= _round100(amt)
			payments[win_seat] += _round100(amt)
	else:
		var amt: int = base * 6 if is_dealer else base * 4
		var loser: int = ctx.get("loser_seat", (dealer + 1) % 4)
		payments[loser] -= _round100(amt)
		payments[win_seat] += _round100(amt)
	return payments


## 基础点:满贯以上按段位封顶,役满 8000。
static func _base_points(han: int, fu: int) -> int:
	if han >= YAKUMAN_HAN:
		return 8000
	var limit := 0
	if han >= 11:
		limit = 6000
	elif han >= 8:
		limit = 4000
	elif han >= 6:
		limit = 3000
	elif han >= 5:
		limit = 2000
	var base := fu * int(pow(2.0, 2 + han))
	if limit > 0:
		base = mini(base, limit)
	return base


static func _round100(v: int) -> int:
	return int(ceil(v / 100.0)) * 100
