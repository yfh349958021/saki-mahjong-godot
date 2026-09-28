class_name MAI
extends RefCounted
## 简单而合理的 AI(纯逻辑):
##   打牌:打出使暗牌向听数最小的牌;并列时比较受入种类数;再并列优先拆孤张字牌。
##   立直:门清听牌即立直。
##   鸣牌:仅当碰/杠能降低向听时进行(不做防守判断,保持简单)。
##   和牌:能和则和;持咲技能时先尝试 ±1 改写再和。
##   久技能:开局两次“認識の改変”主动预约。


## 返回应打出的手牌下标(打牌阶段,手牌为摸牌后的张数)。
## 性能:受入数计算(每候选 34 次 shanten)只在并列候选 ≤ 6 时进行,
## 其余情况用孤张度 tie-break,避免模拟大量对局时单步耗时失控。
static func choose_discard(table, player) -> int:
	var n: int = player.hand.size()
	# 第一遍:找最小向听与并列候选
	var shantens: Array[int] = []
	var best_shanten := 99
	var tied: Array[int] = []
	for i in n:
		var s := MShanten.for_tiles(_without(player.hand, i), player.melds.size())
		shantens.append(s)
		if s < best_shanten:
			best_shanten = s
			tied = [i]
		elif s == best_shanten:
			tied.append(i)
	# 第二遍:并列者比较受入种类数与孤张度
	var best_idx: int = tied[0]
	var best_ukeire := -1
	var best_float := 99
	var defend := _need_defense(table, player)
	var use_ukeire := tied.size() <= 6 and best_shanten <= 2
	for i in tied:
		var u := MShanten.ukeire_kinds(_without(player.hand, i), player.melds.size()) if use_ukeire else 0
		var float_score := _isolation(player.hand[i], player.hand)
		if defend and player.river_has(MTile.kind_of(player.hand[i])):
			float_score -= 10  # 对手立直时,现物(自己河中出现过的kind)安全加分
		if u > best_ukeire or (u == best_ukeire and float_score < best_float):
			best_ukeire = u
			best_float = float_score
			best_idx = i
	return best_idx


## 久:从墙顶若干张里挑一张(返回选项下标)。
static func choose_peek(table, player, options: Array[int]) -> int:
	var best_i := 0
	var best_s := 99
	var best_u := -1
	for i in options.size():
		var counts := MTile.to_counts(player.hand)
		counts[MTile.kind_of(options[i])] += 1
		var s := MShanten.for_counts(counts, player.melds.size())
		if s < best_s:
			best_s = s
			best_i = i
			best_u = -1
		elif s == best_s:
			counts[MTile.kind_of(options[i])] -= 1
			var u := 0
			for kind in MTile.KIND_COUNT:
				if counts[kind] >= 4:
					continue
				counts[kind] += 1
				if MShanten.for_counts(counts, player.melds.size()) < s:
					u += 1
				counts[kind] -= 1
			if u > best_u:
				best_u = u
				best_i = i
	return best_i


## 是否应该宣告立直(打牌前判定;若立直则强制摸切由 Table 处理)。
static func wants_riichi(table, player) -> bool:
	if player.riichi or not player.is_menzen() or not player.is_tenpai():
		return false
	# 立直后打出的那张必须仍是听牌(先试着打每张牌看是否听牌)
	for i in player.hand.size():
		if MShanten.for_tiles(_without(player.hand, i), player.melds.size()) == 0:
			return true
	return false


## 摸牌后是否直接自摸(含咲 ±1 改写;若需要改写则已由 Table 应用)。
static func wants_tsumo(table, player) -> bool:
	return _can_win_now(player)


## 咲 ±1:找到能改写出胡牌形的调整 {index, delta},找不到返回空字典。
static func find_pm_move(player) -> Dictionary:
	if player.skill == null or player.skill.id != "saki" or player.skill.uses_left <= 0:
		return {}
	var counts := MTile.to_counts(player.hand)
	for i in player.hand.size():
		var kind := MTile.kind_of(player.hand[i])
		for delta in [1, -1]:
			var target := MTile.shift_kind(kind, delta)
			if target < 0 or counts[target] >= 4:
				continue
			counts[kind] -= 1
			counts[target] += 1
			var win := MYaku.can_win(counts, player.melds.size())
			counts[kind] += 1
			counts[target] -= 1
			if win:
				return {"index": i, "delta": delta}
	return {}


## 碰:仅当降低向听。
static func wants_pon(table, player, kind: int) -> bool:
	var counts: Array[int] = player.concealed_counts()
	if counts[kind] < 2:
		return false
	var before := MShanten.for_tiles(player.hand, player.melds.size())
	var after_counts := counts.duplicate()
	after_counts[kind] -= 2
	var after := MShanten.for_counts(after_counts, player.melds.size() + 1)
	return after < before


## 吃:枚举全部组合,返回能降低向听的组合列表(供响应窗口与 AI 择优)。
static func chi_combos(player, kind: int) -> Array:
	if MTile.is_honor(kind):
		return []
	var counts: Array[int] = player.concealed_counts()
	var out: Array = []
	for called in 3:
		var low := kind - called
		if low < 0 or low > 6 or MTile.suit(low) != MTile.suit(kind):
			continue
		var others: Array[int] = []
		for k in [low, low + 1, low + 2]:
			if k != kind:
				others.append(k)
		if counts[others[0]] > 0 and counts[others[1]] > 0:
			out.append({"called": called, "tiles": others, "low": low})
	return out


## AI 吃:选使向听最低的组合;向听下降,或已在 1 向听内(食断速攻)时吃。
static func choose_chi(table, player, combos: Array) -> int:
	var kind: int = table.last_discard.kind
	var before := MShanten.for_tiles(player.hand, player.melds.size())
	var best_i := -1
	var best_s := before
	var best_u := -1
	for i in combos.size():
		var counts: Array[int] = player.concealed_counts()
		for k in combos[i].tiles:
			counts[k] -= 1
		var s := MShanten.for_counts(counts, player.melds.size() + 1)
		var improves := s < best_s or (s == best_s and s <= 1 and best_i == -1)
		if improves:
			best_s = mini(best_s, s)
			best_i = i
			best_u = -1
		elif s == best_s and best_i >= 0:
			counts[combos[i].tiles[0]] -= 1
			counts[combos[i].tiles[1]] -= 1
			var u := MShanten.ukeire_kinds(_counts_to_tiles(counts), player.melds.size() + 1)
			if u > best_u:
				best_u = u
				best_i = i
	return best_i


## 加杠:手中第 4 张与已有明碰同种,且向听不劣化(注意抢杠风险由响应窗口处理)。
static func wants_kakan(table, player) -> int:
	var pon_kinds := {}
	for m in player.melds:
		if m.type == "pon":
			pon_kinds[m.kind] = true
	if pon_kinds.is_empty():
		return -1
	var counts: Array[int] = player.concealed_counts()
	var before := MShanten.for_tiles(player.hand, player.melds.size())
	for kind in pon_kinds:
		if counts[kind] < 1:
			continue
		var after_counts := counts.duplicate()
		after_counts[kind] -= 1
		var after := MShanten.for_counts(after_counts, player.melds.size() + 1)
		if after <= before and before <= 2:
			for i in player.hand.size():
				if MTile.kind_of(player.hand[i]) == kind:
					return i
	return -1


## 龙华:刚摸的牌是否值得换掉(打出去也不掉向听 = 孤张)。
static func mulligan_worth(table, player) -> bool:
	if MShanten.for_tiles(player.hand, player.melds.size()) <= 0:
		return false  # 听牌/和牌形不换
	var without := MShanten.for_tiles(_without(player.hand, _index_of(player, player.just_drawn)), player.melds.size())
	var with_tile := MShanten.for_tiles(player.hand, player.melds.size())
	return without >= with_tile


static func _index_of(player, tile_id: int) -> int:
	return player.hand.find(tile_id)


## 把计数表还原成“手牌 id 列表”形状(供 ukeire 接口)。
static func _counts_to_tiles(counts: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for kind in MTile.KIND_COUNT:
		for j in counts[kind]:
			out.append(kind * 4 + 1)
	return out


## 大明杠:手牌已有 3 张时接杠。
static func wants_kan(table, player, kind: int) -> bool:
	var counts: Array[int] = player.concealed_counts()
	if counts[kind] < 3:
		return false
	var before := MShanten.for_tiles(player.hand, player.melds.size())
	var after_counts := counts.duplicate()
	after_counts[kind] -= 3
	var after := MShanten.for_counts(after_counts, player.melds.size() + 1)
	return after <= before


## 暗杠:手牌 4 张同种且不劣化。
static func wants_ankan(table, player) -> int:
	var counts: Array[int] = player.concealed_counts()
	var before := MShanten.for_tiles(player.hand, player.melds.size())
	for kind in MTile.KIND_COUNT:
		if counts[kind] < 4:
			continue
		var after_counts := counts.duplicate()
		after_counts[kind] -= 4
		var after := MShanten.for_counts(after_counts, player.melds.size() + 1)
		if after <= before:
			# 返回手牌中该 kind 第一张的下标
			for i in player.hand.size():
				if MTile.kind_of(player.hand[i]) == kind:
					return i
	return -1


static func _can_win_now(player) -> bool:
	return MYaku.can_win(player.concealed_counts(), player.melds.size())


static func _need_defense(table, player) -> bool:
	for p in table.players:
		if p.seat != player.seat and p.riichi:
			return true
	return false


static func _without(arr: Array[int], idx: int) -> Array[int]:
	var out: Array[int] = []
	for i in arr.size():
		if i != idx:
			out.append(arr[i])
	return out


## 孤张度:与手牌中其他牌的联系越少越该先打。
static func _isolation(tile_id: int, hand: Array[int]) -> int:
	var kind := MTile.kind_of(tile_id)
	var score := 0
	if MTile.is_honor(kind):
		return 8
	for other_id in hand:
		var ok := MTile.kind_of(other_id)
		if ok == kind:
			continue
		if MTile.suit(ok) == MTile.suit(kind):
			var d: int = absi(ok - kind)
			if d == 1:
				score += 2
			elif d == 2:
				score += 1
	return score
