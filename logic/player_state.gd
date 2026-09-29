class_name MPlayer
extends RefCounted
## 玩家状态:手牌 / 河 / 副露 / 立直 / 技能,全部是纯数据(RefCounted)。

var seat: int = 0
var display_name: String = "Player"
var is_ai: bool = true
var hand: Array[int] = []            # 暗牌(实体 id)
var melds: Array[Dictionary] = []    # {type: pon/kan_open/kan_closed/kan_added, kind: int}
var river: Array[int] = []           # 打出的牌(id 序)
var riichi: bool = false
var riichi_discarded: bool = false   # 立直宣言牌是否已打出
var ippatsu: bool = false            # 一发:立直后未有任何鸣牌 intervening 时的一次性机会
var rinshan_flag: bool = false       # 最近一次摸牌是否来自岭上(岭上开花判定)
var skill: MSkill = null
var score: int = 25000
var ai_difficulty: int = 1          # AI 难度:0 简单 / 1 普通 / 2 困难
var pending_peek: int = 0            # 竹井久:下一次摸牌的挑选张数
var just_drawn: int = -1             # 最近一次摸到的实体牌 id(立直后暗杠的听牌不变判定用)
var discards_after_riichi: int = 0   # 立直宣言后(含宣言牌)的打牌数(牌河横置牌定位用)


func setup(seat_index: int, name_: String, ai: bool, skill_id: String) -> void:
	seat = seat_index
	display_name = name_
	is_ai = ai
	skill = MSkills.create(skill_id)


func reset_for_round(dealer: bool, start_score: int = 25000) -> void:
	hand.clear()
	melds.clear()
	river.clear()
	riichi = false
	riichi_discarded = false
	ippatsu = false
	rinshan_flag = false
	pending_peek = 0
	just_drawn = -1
	discards_after_riichi = 0
	score = start_score
	if skill:
		skill.reset_for_round()


func concealed_counts() -> Array[int]:
	return MTile.to_counts(hand)


func meld_count() -> int:
	return melds.size()


func is_menzen() -> bool:
	for m in melds:
		if m.type != "kan_closed":
			return false
	return true


func is_tenpai() -> bool:
	return MShanten.for_tiles(hand, melds.size()) == 0


## 摸牌后手牌应有多少张(决定打牌阶段)。
func expected_hand_size() -> int:
	return 14 - 3 * melds.size()


## 河里是否含有 kind(振听判定用)。
func river_has(kind: int) -> bool:
	for tile_id in river:
		if MTile.kind_of(tile_id) == kind:
			return true
	return false


## 当前 14(或更少)张暗牌能直接胡的 kind 列表。
func winning_kinds() -> Array[int]:
	var counts := concealed_counts()
	var out: Array[int] = []
	for kind in MTile.KIND_COUNT:
		if counts[kind] >= 4:
			continue
		counts[kind] += 1
		if MYaku.can_win(counts, melds.size()):
			out.append(kind)
		counts[kind] -= 1
	return out


## 振听(简化规则):河中含有所听 kind 即无法荣和。
func is_furiten() -> bool:
	for kind in winning_kinds():
		if river_has(kind):
			return true
	return false
