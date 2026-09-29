class_name MWall
extends RefCounted
## 牌山:一个纯数组 + 洗牌/抽牌/宝牌指示。
## “技能”通过三种纯数组操作影响抽牌:
##   1. 加权抽牌 draw_weighted() —— 按各 kind 权重做轮盘赌,再从剩余墙里抽该 kind 的实体牌;
##   2. 透视/挑选 peek_top() + take_id() —— 查看墙顶若干张并任选其一;
##   3. 重排 reorder_to_top() —— 把指定 kind 的实体牌移到墙顶(数组 Manipulation)。

var ids: Array[int] = []           # 牌山本体;数组尾部 = 下一张要摸的牌
var dead_wall: Array[int] = []     # 王牌 14 张(岭上牌从其头部取)
var dora_indicators: Array[int] = []  # 已翻开的宝牌指示牌 kind
var ura_indicators: Array[int] = []   # 里宝指示牌 kind(立直和牌时开示)
var forced_dora: Array[int] = []      # 联机副本:主机下发的宝牌 kind(非空时优先)
var forced_ura: Array[int] = []       # 联机副本:主机下发的里宝 kind
var rng := RandomNumberGenerator.new()


## seed 相同 => 牌山序列完全可复现(无头测试依赖这一点)。
func setup(seed_value: int, red_dora: int = 3) -> void:
	rng.seed = seed_value
	ids.clear()
	dead_wall.clear()
	dora_indicators.clear()
	ura_indicators.clear()
	for id in MTile.TOTAL_TILES:
		ids.append(id)
	# 红宝牌数量可配:超出部分按 id 从大到小移除(确定性)
	if red_dora < 3:
		var red_ids: Array[int] = []
		for id in ids:
			if MTile.is_red(id):
				red_ids.append(id)
		red_ids.sort()
		red_ids.reverse()
		for i in mini(3 - red_dora, red_ids.size()):
			ids.erase(red_ids[i])
	_shuffle(ids)
	# 标准:王牌 14 张置于墙尾之外。这里从洗好的数组尾部划出 14 张,
	# 其中翻 1 张宝牌指示牌(里宝指示牌同时定好但扣置)。
	for i in 14:
		dead_wall.append(ids.pop_back())
	_reveal_dora()


func tiles_left() -> int:
	return ids.size()


func is_exhausted() -> bool:
	return ids.is_empty()


## 普通摸牌:墙顶一张。
func draw_top() -> int:
	return ids.pop_back()


## 偷看接下来 depth 张(不取出)。“透视”类技能与表现层共用。
func peek_top(depth: int) -> Array[int]:
	var out: Array[int] = []
	var n := ids.size()
	for i in mini(depth, n):
		out.append(ids[n - 1 - i])
	return out


## 从墙中取走指定实体牌(技能“从若干张里挑一张抽”用)。
func take_id(tile_id: int) -> bool:
	var idx := ids.find(tile_id)
	if idx < 0:
		return false
	ids.remove_at(idx)
	return true


## 从墙中取出任意一张指定 kind 的实体牌;墙里没有则返回 -1。
## “宫永咲 ±1”改写手牌时优先从这里取,避免实体牌凭空重复。
func take_kind(kind: int) -> int:
	for i in ids.size():
		if MTile.kind_of(ids[i]) == kind:
			var id := ids[i]
			ids.remove_at(i)
			return id
	return -1


## 数组重排:把 kind 的全部实体牌移到墙顶(不改变相对顺序)。
func reorder_to_top(kind: int) -> int:
	return reorder_to_depth(kind, 0)


## 定点重排:把 kind 的实体牌移动到“从墙顶数第 depth 个摸牌位”,
## 保持其余牌相对顺序。depth=0 即墙顶(下一次摸牌就摸到)。
## 新子憧「牌の背中」用它把宝牌放到自己下一次摸牌的位置。
func reorder_to_depth(kind: int, depth: int) -> int:
	var moved: Array[int] = []
	var keep: Array[int] = []
	for id in ids:
		if MTile.kind_of(id) == kind:
			moved.append(id)
		else:
			keep.append(id)
	if moved.is_empty():
		return 0
	var k := keep.size()
	var split := clampi(k - depth, 0, k)
	ids = []
	for i in split:
		ids.append(keep[i])
	for id in moved:
		ids.append(id)
	for i in range(split, k):
		ids.append(keep[i])
	return moved.size()


## 加权抽牌:weights[kind] 是各 kind 的期望权重(0 表示绝不抽该种),
## 实际权重再乘以墙内剩余张数后做轮盘赌。返回实体牌 id。
## “负の自律作用”一类“流向型”技能用它实现概率性控牌。
func draw_weighted(weights: Array) -> int:
	if ids.is_empty():
		return -1
	var total := 0.0
	for kind in MTile.KIND_COUNT:
		total += weights[kind]
	if total <= 0.0:
		return draw_top()
	var roll := rng.randf() * total
	var acc := 0.0
	var chosen_kind := -1
	for kind in MTile.KIND_COUNT:
		acc += weights[kind]
		if roll <= acc:
			chosen_kind = kind
			break
	if chosen_kind < 0:
		chosen_kind = MTile.KIND_COUNT - 1
	# 墙里该 kind 已被抽光则退化为普通摸牌
	for id in ids:
		if MTile.kind_of(id) == chosen_kind:
			ids.remove_at(ids.find(id))
			return id
	return draw_top()


## 岭上摸牌(杠后)。
func draw_rinshan() -> int:
	if dead_wall.is_empty():
		return -1
	return dead_wall.pop_back()


## 加权岭上摸牌(宫永照):对王牌做轮盘赌。
func draw_rinshan_weighted(weights: Array) -> int:
	if dead_wall.is_empty():
		return -1
	var total := 0.0
	for kind in MTile.KIND_COUNT:
		total += weights[kind]
	if total <= 0.0:
		return draw_rinshan()
	var roll := rng.randf() * total
	var acc := 0.0
	var chosen_kind := -1
	for kind in MTile.KIND_COUNT:
		acc += weights[kind]
		if roll <= acc:
			chosen_kind = kind
			break
	if chosen_kind < 0:
		chosen_kind = MTile.KIND_COUNT - 1
	for i in dead_wall.size():
		if MTile.kind_of(dead_wall[i]) == chosen_kind:
			var id := dead_wall[i]
			dead_wall.remove_at(i)
			return id
	return draw_rinshan()


## 杠后补翻一张宝牌指示。
func reveal_extra_dora() -> void:
	_reveal_dora()


func _reveal_dora() -> void:
	# 指示牌从王牌的“尾部倒退第 5、7、9…”位置取,里宝取其相邻位。
	# 摆法不追求 tournament 精确,只要“每杠多翻一张(里宝同步增加)”即可。
	var idx := dead_wall.size() - 5 - dora_indicators.size() * 2
	if idx >= 1:
		dora_indicators.append(MTile.kind_of(dead_wall[idx]))
		ura_indicators.append(MTile.kind_of(dead_wall[idx - 1]))


## 宝牌实体 kind 列表(指示牌的下一张);联机副本模式下由主机快照直接下发。
func dora_kinds() -> Array[int]:
	if forced_dora.size() > 0:
		return forced_dora.duplicate()
	var out: Array[int] = []
	for ind in dora_indicators:
		out.append(_next_kind(ind))
	return out


## 里宝 kind 列表(仅立直和牌时由 Table 传入役判定);联机副本由快照下发。
func ura_kinds() -> Array[int]:
	if forced_ura.size() > 0:
		return forced_ura.duplicate()
	var out: Array[int] = []
	for ind in ura_indicators:
		out.append(_next_kind(ind))
	return out


func _next_kind(kind: int) -> int:
	if MTile.is_honor(kind):
		return 27 + (kind - 27 + 1) % 7  # 東→南→…→北→東 / 白→發→中→白
	return MTile.suit(kind) * 9 + (MTile.rank(kind) % 9)  # 9 绕回 1


func _shuffle(arr: Array[int]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
