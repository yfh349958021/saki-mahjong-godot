class_name MSkill
extends RefCounted
## 技能基类:纯逻辑,通过两类钩子影响摸牌,从而实现“抽牌取决于技能与概率”:
##   1. modify_draw_weights —— 概率加权抽牌(把摸牌从“均匀采样”改成“按技能意图的轮盘赌”);
##   2. 主动效果(activate)—— 对牌山数组做重排/挑选/改写。
## 所有技能只操作数据(牌山数组、手牌数组),不依赖任何 Node / UI。

var id: String = "none"
var char_name: String = "素人"
var title: String = "无能力"
var desc: String = "普通的高校生,一切凭实力。"
var uses_per_round: int = 0
var uses_left: int = 0
var passive_weight := false      # 普通摸牌有被动加权
var passive_rinshan := false     # 岭上摸牌有被动加权


func reset_for_round() -> void:
	uses_left = uses_per_round


## 被动钩子:在摸牌前改写 34 维权重数组(默认全 1 = 均匀概率)。
## wall.draw_weighted() 会把权重乘以墙内剩余张数后做轮盘赌。
func modify_draw_weights(_table, _player, _weights: Array) -> void:
	pass


## 被动钩子:岭上摸牌的权重数组(空数组 = 不干预)。
func rinshan_weights(_table, _player) -> Array:
	return []


## 主动技能是否可以发动(由 Table 校验时机)。
func can_activate(_table, _player) -> bool:
	return uses_left > 0


## 主动效果。args 由调用方(UI 按钮 / AI)提供,失败返回 false。
func activate(_table, _player, _args: Dictionary) -> bool:
	return false


## 竹井久:摸牌前预约“从墙顶 3 张里挑 1 张”。
func peek_depth(_table, _player) -> int:
	return 0


## 精确制导共用逻辑(和 / 照):对向听 <= max_shanten 的手,
## 进张 kind 权重 up、胡牌张权重 up_win。
func _apply_precision(weights: Array, player, max_shanten: int, up: float, up_win: float) -> void:
	var counts := MTile.to_counts(player.hand)
	var base := MShanten.for_counts(counts, player.melds.size())
	if base > max_shanten:
		return
	for kind in MTile.KIND_COUNT:
		if counts[kind] >= 4:
			continue
		counts[kind] += 1
		var s := MShanten.for_counts(counts, player.melds.size())
		counts[kind] -= 1
		if s < base:
			weights[kind] = maxf(weights[kind], up)
		if s < 0:
			weights[kind] = up_win


## 宫永咲:和牌判定允许 ±1 调整时由 Table 直接调用 uses_left。
## (调整本身是对手牌数组的改写,见 Table.apply_plusminus。)
