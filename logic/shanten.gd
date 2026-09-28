class_name MShanten
extends RefCounted
## 向听数计算:纯算法,无任何状态依赖。
## 覆盖标准型(4 面子 + 雀头)、七对子、国士无双,取三者最小值。
## 约定:13 张手的向听数 0 = 听牌;胡牌形(14 张)返回 -1。
## 副露(碰/杠)作为已成的面子直接计入,只对暗牌部分递归拆解。
## 算法:经典递归拆解(枚举刻子/顺子/对子/搭子/弃张),配合 memo 缓存
## (计数表编码为两个 base-5 整数)以支撑 AI 每回合上百次的调用。

const _P5: Array[int] = [
	1, 5, 25, 125, 625, 3125, 15625, 78125, 390625, 1953125,
	9765625, 48828125, 244140625, 1220703125, 6103515625, 30517578125,
	152587890625,
]

static var _memo: Dictionary = {}


static func reset_memo() -> void:
	_memo.clear()


## 输入实体牌 id 数组(暗牌部分)+ 副露组数,返回综合向听数。
static func for_tiles(tiles: Array, meld_count: int = 0) -> int:
	return for_counts(MTile.to_counts(tiles), meld_count)


static func for_counts(counts: Array[int], meld_count: int = 0) -> int:
	if _memo.size() > 300000:
		_memo.clear()
	var a := 0
	var b := 0
	for k in 17:
		if counts[k]:
			a += counts[k] * _P5[k]
		if counts[17 + k]:
			b += counts[17 + k] * _P5[k]
	var key := "%d_%d_%d" % [a, b, meld_count]
	if _memo.has(key):
		return _memo[key]
	var result: int
	if meld_count == 0:
		result = mini(_standard(counts.duplicate(), 0), mini(_chiitoitsu(counts), _kokushi(counts)))
	else:
		# 副露后七对/国士不成立
		result = _standard(counts.duplicate(), meld_count)
	_memo[key] = result
	return result


## 七对子:6 - 对子数(不同 kind 才算)。
static func _chiitoitsu(counts: Array[int]) -> int:
	var pairs := 0
	for kind in MTile.KIND_COUNT:
		if counts[kind] >= 2:
			pairs += 1
	return 6 - pairs


## 国士无双:13 - 集齐的幺九种类数 - (有对子 ? 1 : 0)。
static func _kokushi(counts: Array[int]) -> int:
	var types := 0
	var has_pair := false
	for kind in MTile.TERMINAL_KINDS:
		if counts[kind] > 0:
			types += 1
			if counts[kind] >= 2:
				has_pair = true
	return 13 - types - (1 if has_pair else 0)


## 标准型:base_melds 为副露已成的面子数。
## 枚举“雀头变体”:无雀头(p=0)与以各 kind 为雀头(p=1),递归最大化
## 2*面子数 + 搭子数(搭子含“当作搭子的对子”),雀头单独计 1 分:
##   shanten = 8 - 2*melds - min(partials, 4-melds) - has_atama
static func _standard(counts: Array[int], base_melds: int) -> int:
	var best := _scan(counts, 0, base_melds, 0)  # p=0:尚无雀头
	for p in MTile.KIND_COUNT:
		if counts[p] >= 2:
			counts[p] -= 2
			best = mini(best, _scan(counts, 0, base_melds, 0) - 1)  # p=1:雀头成立
			counts[p] += 2
	return best


static func _scan(counts: Array[int], i: int, melds: int, partials: int) -> int:
	while i < MTile.KIND_COUNT and counts[i] == 0:
		i += 1
	var best := 8 - 2 * melds - mini(partials, 4 - melds)
	if i >= MTile.KIND_COUNT:
		return best

	# 刻子
	if counts[i] >= 3:
		counts[i] -= 3
		best = mini(best, _scan(counts, i, melds + 1, partials))
		counts[i] += 3
	# 顺子
	if i < 27 and i % 9 <= 6 and counts[i + 1] > 0 and counts[i + 2] > 0:
		counts[i] -= 1
		counts[i + 1] -= 1
		counts[i + 2] -= 1
		best = mini(best, _scan(counts, i, melds + 1, partials))
		counts[i] += 1
		counts[i + 1] += 1
		counts[i + 2] += 1
	# 对子(搭子)
	if counts[i] >= 2:
		counts[i] -= 2
		best = mini(best, _scan(counts, i, melds, partials + 1))
		counts[i] += 2
	# 两面/边张(相邻)
	if i < 27 and i % 9 <= 7 and counts[i + 1] > 0:
		counts[i] -= 1
		counts[i + 1] -= 1
		best = mini(best, _scan(counts, i, melds, partials + 1))
		counts[i] += 1
		counts[i + 1] += 1
	# 嵌张(隔一张)
	if i < 27 and i % 9 <= 5 and counts[i + 2] > 0:
		counts[i] -= 1
		counts[i + 2] -= 1
		best = mini(best, _scan(counts, i, melds, partials + 1))
		counts[i] += 1
		counts[i + 2] += 1
	# 当作孤张忽略
	counts[i] -= 1
	best = mini(best, _scan(counts, i, melds, partials))
	counts[i] += 1
	return best


## 13 张手牌的受入种类数(能向听的 kind 数)。AI 择牌 tie-break 用。
static func ukeire_kinds(tiles_13: Array, meld_count: int = 0) -> int:
	var counts := MTile.to_counts(tiles_13)
	var base := for_counts(counts, meld_count)
	var n := 0
	for kind in MTile.KIND_COUNT:
		if counts[kind] >= 4:
			continue
		counts[kind] += 1
		if for_counts(counts, meld_count) < base:
			n += 1
		counts[kind] -= 1
	return n
