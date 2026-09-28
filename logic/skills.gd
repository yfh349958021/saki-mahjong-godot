class_name MSkills
extends RefCounted
## 八位角色的技能实现(纯数据操作,无 UI)。机制原型参考 Saki 原作设定:
##   宫永咲「+1/-1」:       主动 ×2 —— 手中一张数牌同花色内 ±1 改写
##   竹井久「認識の改変」:   主动 ×2 —— 下次摸牌从墙顶 3 张里挑 1 张
##   天江衣「負の自律作用」: 被动 —— 需要的河牌主动流向自己,无用的河牌避开
##   原村和「大魔神の精算」: 被动 —— 听牌胡牌张 ×6,1 向听进张 ×2.5
##   宫永照「嶺上の絶対」:   被动 —— 岭上摸牌必然倒向进张/胡牌张(岭上开花之鬼)
##   松实玄「集まれドラ」:   被动 —— 宝牌聚集到玄面前(宝牌概率 ×4)
##   新子憧「牌の背中」:     主动 ×1 —— 感知牌山,把宝牌移到自己下一次摸牌的位置
##   清水谷龙华「恵みの雨」: 主动 ×2 —— 刚摸的牌放回墙顶重摸,雨也许带来同一张


## 工厂:按 id 构造技能(单向依赖,避免循环 preload)。
static func create(skill_id: String) -> MSkill:
	match skill_id:
		"saki":
			return SkillSaki.new()
		"hisa":
			return SkillHisa.new()
		"koromo":
			return SkillKoromo.new()
		"nodoka":
			return SkillNodoka.new()
		"teru":
			return SkillTeru.new()
		"kuro":
			return SkillKuro.new()
		"ako":
			return SkillAko.new()
		"ryuuka":
			return SkillRyuuka.new()
		_:
			return MSkill.new()


class SkillSaki:
	extends MSkill

	func _init() -> void:
		id = "saki"
		char_name = "宫永咲"
		title = "+1 / -1"
		desc = "主动(每局 2 次):把手中一张数牌在同花色内 +1 或 -1。和牌之路由自己改写。"
		uses_per_round = 2

	func can_activate(table, player) -> bool:
		return uses_left > 0 and table.current_seat == player.seat \
			and table.phase == "await_discard"


class SkillHisa:
	extends MSkill

	func _init() -> void:
		id = "hisa"
		char_name = "竹井久"
		title = "認識の改変"
		desc = "主动(每局 2 次):预约下一次摸牌 —— 从牌山顶部 3 张中任选 1 张。"
		uses_per_round = 2

	func can_activate(table, player) -> bool:
		return uses_left > 0 and table.current_seat == player.seat \
			and table.phase == "await_discard" and not player.riichi

	func peek_depth(_table, _player) -> int:
		return 3


class SkillKoromo:
	extends MSkill

	func _init() -> void:
		id = "koromo"
		char_name = "天江衣"
		title = "負の自律作用"
		desc = "被动:别人不要而流进牌河的牌,若正是自己需要的,会主动流向自己(河中越多越强);不需要的河牌则避开。"
		passive_weight = true

	func modify_draw_weights(table, player, weights: Array) -> void:
		var counts := MTile.to_counts(player.hand)
		var base := MShanten.for_counts(counts, player.melds.size())
		for kind in MTile.KIND_COUNT:
			var in_river := _river_count(table, kind)
			if in_river == 0 or counts[kind] >= 4:
				continue
			counts[kind] += 1
			var useful := MShanten.for_counts(counts, player.melds.size()) < base
			counts[kind] -= 1
			if useful:
				weights[kind] += 3.0 + 1.5 * mini(4, in_river)  # 需要的河牌:强吸引
			else:
				weights[kind] = maxf(0.4, weights[kind] - 0.15 * in_river)  # 无用的河牌:避开

	func _river_count(table, kind: int) -> int:
		var n := 0
		for p in table.players:
			for tile_id in p.river:
				if MTile.kind_of(tile_id) == kind:
					n += 1
		return n


class SkillNodoka:
	extends MSkill

	func _init() -> void:
		id = "nodoka"
		char_name = "原村和"
		title = "大魔神の精算"
		desc = "被动:摸牌永远倒向最优解 —— 听牌时胡牌张概率 ×6,1 向听时进张概率 ×2.5。"
		passive_weight = true

	func modify_draw_weights(_table, player, weights: Array) -> void:
		if player.riichi:
			return
		_apply_precision(weights, player, 2, 2.5, 6.0)


class SkillTeru:
	extends MSkill

	func _init() -> void:
		id = "teru"
		char_name = "宫永照"
		title = "嶺上の絶対"
		desc = "被动:岭上摸牌必然倒向进张与胡牌张 —— 岭上开花之鬼,杠得越多越强。"
		passive_rinshan = true

	func rinshan_weights(_table, player) -> Array:
		var weights: Array = []
		weights.resize(MTile.KIND_COUNT)
		weights.fill(1.0)
		_apply_precision(weights, player, 3, 6.0, 12.0)
		return weights


class SkillKuro:
	extends MSkill

	func _init() -> void:
		id = "kuro"
		char_name = "松实玄"
		title = "集まれドラ"
		desc = "被动:宝牌会聚集到玄的面前 —— 摸到宝牌的概率 ×4。"
		passive_weight = true

	func modify_draw_weights(table, _player, weights: Array) -> void:
		for kind in table.wall.dora_kinds():
			weights[kind] *= 4.0


class SkillAko:
	extends MSkill

	func _init() -> void:
		id = "ako"
		char_name = "新子憧"
		title = "牌の背中"
		desc = "主动(每局 1 次):感知牌山深处,把一张宝牌移到自己下一次摸牌的位置。"
		uses_per_round = 1

	func can_activate(table, player) -> bool:
		return uses_left > 0 and table.current_seat == player.seat \
			and table.phase == "await_discard"


class SkillRyuuka:
	extends MSkill

	func _init() -> void:
		id = "ryuuka"
		char_name = "清水谷龙华"
		title = "恵みの雨"
		desc = "主动(每局 2 次):把刚摸的牌放回墙顶重新摸一张 —— 雨,也许会带来同一张牌。"
		uses_per_round = 2

	func can_activate(table, player) -> bool:
		return uses_left > 0 and table.current_seat == player.seat \
			and table.phase == "await_discard" and player.just_drawn >= 0
