class_name MTable
extends RefCounted
## 对局状态机:纯逻辑核心,零 UI 依赖。
## 完整规则支持:吃 / 碰 / 明杠 / 加杠 / 抢杠 / 暗杠 / 立直(含一发、里宝、立直后
## 听牌不变暗杠)/ 多响全符放铳 / 流局听牌费 / 食下减翻 / 真实符数。
## 驱动方式(两者皆可,同一套代码):
##   · 表现层:每次 advance_one_step() 走一个原子动作,人类决策点通过
##     phase + human_*() API 暴露给 UI;
##   · 无头模拟:循环 advance_one_step() 直到 round_end。
##
## phase 取值:
##   "turn_draw"      —— 当前座位该摸牌(advance_one_step 自动执行)
##   "await_discard"  —— 等待当前座位打牌(AI 自动 / 人类调 human_* 系列)
##   "await_peek"     —— 久技能:等待人类从墙顶挑选(peek_options)
##   "await_response" —— 有玩家可荣/碰/杠/吃;人类需 human_ron/pon/kan/chi/decline
##   "round_end"      —— 本局结束,result 中有结算

signal event_added(text: String)

const SEAT_NAMES: Array[String] = ["东家", "南家", "西家", "北家"]

var players: Array[MPlayer] = []
var wall := MWall.new()
var current_seat: int = 0
var dealer_seat: int = 0
var round_number: int = 1
var phase: String = "idle"
var turn_count: int = 0
var last_discard: Dictionary = {}   # {seat, tile_id, kind, kakan?(抢杠标记)}
var human_options: Dictionary = {}  # 人类可响应动作 {"ron":bool,"pon":bool,"kan":bool,"chi":Array}
var peek_options: Array[int] = []   # await_peek 时供人类挑选的墙顶牌
var result: Dictionary = {}
var events: Array[String] = []
var steps_taken: int = 0

var rules: Dictionary = MRules.merged()

var _human_seat: int = -1
var _resp: Dictionary = {}            # seat -> {"ron":bool,"pon":bool,"kan":bool,"chi":Array}
var _awaiting: Array[int] = []        # 尚未响应的(人类)座位
var _ron_chosen_seats: Array[int] = []# 已宣告荣和的座位
var _calls: Dictionary = {}           # seat -> 碰/杠/吃意向 {"action":"pon"/"kan"/"chi","combo":int}
var _pending_kakan: Dictionary = {}   # 待完成的加杠 {seat, kind, tile_id}


func setup(skill_ids: Array, human_seat: int, seed_value: int, dealer: int = 0, rules_cfg: Dictionary = {}) -> void:
	_human_seat = human_seat
	dealer_seat = dealer
	round_number = 1
	rules = MRules.merged(rules_cfg)
	players.clear()
	for i in 4:
		var p := MPlayer.new()
		var sid: String = skill_ids[i] if i < skill_ids.size() else "none"
		var pname: String = MSkills.create(sid).char_name if sid != "none" else "素人%d" % i
		p.setup(i, pname, i != human_seat, sid)
		players.append(p)
	wall.setup(seed_value, rules.red_dora)
	phase = "idle"


func start_round(seed_value: int) -> void:
	wall.setup(seed_value + round_number * 7919, rules.red_dora)
	for p in players:
		p.reset_for_round(p.seat == dealer_seat, rules.start_score)
	# 配牌:每人 13 张(按座位顺序)
	for r in 13:
		for i in 4:
			players[(dealer_seat + i) % 4].hand.append(wall.draw_top())
	current_seat = dealer_seat
	turn_count = 0
	steps_taken = 0
	last_discard = {}
	result = {}
	human_options = {}
	phase = "turn_draw"
	log_event("—— 第 %d 局开始,庄家:%s(%s)——" % [round_number, players[dealer_seat].display_name, SEAT_NAMES[dealer_seat]])


## 推进一个原子步骤。返回动作描述(UI 节奏用,无头模式可忽略)。
func advance_one_step() -> Dictionary:
	steps_taken += 1
	match phase:
		"turn_draw":
			_do_draw()
			return {"action": "draw", "seat": current_seat}
		"await_discard":
			var p := players[current_seat]
			if p.is_ai:
				_ai_discard_phase(p)
				return {"action": "ai_discard", "seat": p.seat}
			return {"action": "wait_human_discard", "seat": p.seat}
		"await_response":
			if _awaiting.size() > 0:
				return {"action": "wait_remote", "seat": current_seat}
			_resolve_responses()
			return {"action": "response", "seat": current_seat}
		_:
			return {"action": "noop"}


## 无头模式:一路推进到本局结束(全 AI 时有效;有人类时在决策点自动停住)。
func run_to_completion(max_steps: int = 20000) -> bool:
	var guard := 0
	while phase != "round_end" and guard < max_steps:
		advance_one_step()
		guard += 1
	return phase == "round_end"


# ———————————————————— 摸牌 ————————————————————

func _do_draw() -> void:
	if wall.is_exhausted():
		_end_draw()
		return
	var p := players[current_seat]
	# 竹井久「認識の改変」:从墙顶挑一张
	if p.pending_peek > 0:
		peek_options = wall.peek_top(p.pending_peek)
		p.pending_peek = 0
		if p.is_ai:
			_apply_peek(p, MAI.choose_peek(self, p, peek_options))
		else:
			phase = "await_peek"
		return
	var tile := _draw_with_skills(p)
	p.rinshan_flag = false
	p.just_drawn = tile
	p.hand.append(tile)
	_expire_ippatsu(p)
	phase = "await_discard"


## 一发机会只在“立直宣言后的下一次摸牌”有效:该次摸牌没有立刻和牌即过期。
func _expire_ippatsu(p: MPlayer) -> void:
	if p.riichi and p.riichi_discarded and p.ippatsu:
		p.ippatsu = false


## 技能钩子下的摸牌:被动加权(衣 / 和 / 玄)或普通摸牌。
func _draw_with_skills(p: MPlayer) -> int:
	if p.skill != null and p.skill.passive_weight and not p.riichi:
		var weights: Array = []
		weights.resize(MTile.KIND_COUNT)
		weights.fill(1.0)
		p.skill.modify_draw_weights(self, p, weights)
		return wall.draw_weighted(weights)
	return wall.draw_top()


## 人类在 await_peek 中做出选择。
func human_choose_peek(option_index: int) -> bool:
	return player_choose_peek(_human_seat, option_index)


func player_choose_peek(seat: int, option_index: int) -> bool:
	if phase != "await_peek" or current_seat != seat:
		return false
	_apply_peek(players[seat], clampi(option_index, 0, peek_options.size() - 1))
	return true


func _apply_peek(p: MPlayer, option_index: int) -> void:
	var chosen := peek_options[option_index]
	wall.take_id(chosen)
	peek_options = []
	p.hand.append(chosen)
	p.rinshan_flag = false
	p.just_drawn = chosen
	_expire_ippatsu(p)
	log_event("%s 发动「認識の改変」,从墙顶挑走了 %s" % [p.display_name, MTile.label_id(chosen)])
	phase = "await_discard"


# ———————————————————— 打牌 / 主要动作 ————————————————————

func _ai_discard_phase(p: MPlayer) -> void:
	# 0a) 龙华「恵みの雨」:刚摸的牌无用则放回重摸(雨也许带来同一张)
	if p.skill and p.skill.id == "ryuuka" and p.skill.uses_left > 0 \
			and p.just_drawn >= 0 and not _can_win_now(p):
		if MAI.mulligan_worth(self, p):
			_do_mulligan(p)
	# 0b) 久:1 向听且本回合不会立直时预约“認識の改変”
	if p.skill and p.skill.id == "hisa" and p.skill.uses_left > 0 and not p.riichi:
		if MShanten.for_tiles(p.hand, p.melds.size()) <= 1 and not MAI.wants_riichi(self, p):
			p.pending_peek = p.skill.peek_depth(self, p)
			p.skill.uses_left -= 1
			log_event("%s 发动「認識の改変」——下次摸牌从墙顶挑选" % p.display_name)
			return  # 本步只做发动,下一步正常打牌;预约在下次摸牌生效
	# 1) 自摸(含咲 ±1 改写后自摸)
	var res := _tsumo_result(p)
	if res.win:
		_apply_win(p, res, true)
		return
	if p.skill and p.skill.id == "saki" and p.skill.uses_left > 0:
		var move := MAI.find_pm_move(p)
		if not move.is_empty():
			apply_plusminus(p, move.index, move.delta)
			res = _tsumo_result(p)
			if res.win:
				_apply_win(p, res, true)
				return
	# 2) 加杠(有役牌碰 + 手中第 4 张)
	var kk := MAI.wants_kakan(self, p)
	if kk >= 0 and not p.riichi:
		_try_kakan(p, kk)
		return
	# 3) 暗杠(立直时须听牌不变)
	var an := MAI.wants_ankan(self, p)
	if an >= 0 and _ankan_allowed(p, an):
		_do_ankan(p, an)
		return
	# 4) 憧「牌の背中」:1 向听时把宝牌挪到自己下一次摸牌的位置
	#    (发动太早会被对手截胡,故只在最接近和牌时使用)
	if p.skill and p.skill.id == "ako" and p.skill.uses_left > 0 \
			and MShanten.for_tiles(p.hand, p.melds.size()) <= 1:
		_do_ako(p)
	# 5) 立直
	if MAI.wants_riichi(self, p):
		p.riichi = true
		p.riichi_discarded = false
		log_event("%s 宣告立直!" % p.display_name)
		p.ippatsu = bool(rules.ippatsu)
	# 6) 打牌:立直后强制摸切;立直宣言那手打出仍保持听牌的一张
	var idx: int
	if p.riichi and p.riichi_discarded:
		idx = p.hand.size() - 1
	else:
		idx = MAI.choose_discard(self, p)
	if p.riichi and not p.riichi_discarded:
		for i in p.hand.size():
			if MShanten.for_tiles(_hand_without(p, i), p.melds.size()) == 0:
				idx = i
				break
		p.riichi_discarded = true
	_execute_discard(p, idx)


func human_discard(hand_index: int) -> bool:
	return player_discard(_human_seat, hand_index)


func player_discard(seat: int, hand_index: int) -> bool:
	if phase != "await_discard" or current_seat != seat:
		return false
	var p := players[seat]
	var idx := hand_index
	if p.riichi and p.riichi_discarded:
		idx = p.hand.size() - 1  # 立直后强制摸切
	if idx < 0 or idx >= p.hand.size():
		return false
	if p.riichi and not p.riichi_discarded:
		if MShanten.for_tiles(_hand_without(p, idx), p.melds.size()) != 0:
			return false  # 立直宣言牌必须保持听牌
		p.riichi_discarded = true
	_execute_discard(p, idx)
	return true


## 立直宣告 + 立即打出该张(人类)。
func human_riichi(hand_index: int) -> bool:
	return player_riichi(_human_seat, hand_index)


func player_riichi(seat: int, hand_index: int) -> bool:
	if phase != "await_discard" or current_seat != seat:
		return false
	var p := players[seat]
	if p.riichi or not p.is_menzen() or p.is_furiten():
		return false
	if hand_index < 0 or hand_index >= p.hand.size():
		return false
	if MShanten.for_tiles(_hand_without(p, hand_index), p.melds.size()) != 0:
		return false
	p.riichi = true
	p.riichi_discarded = true
	log_event("%s 宣告立直!" % p.display_name)
	_execute_discard(p, hand_index)
	p.ippatsu = bool(rules.ippatsu)  # 一发机会自宣言牌打出后开始(规则可关)
	return true


func human_tsumo() -> bool:
	return player_tsumo(_human_seat)


func player_tsumo(seat: int) -> bool:
	if phase != "await_discard" or current_seat != seat:
		return false
	var res := _tsumo_result(players[seat])
	if not res.win:
		return false
	_apply_win(players[seat], res, true)
	return true


## 暗杠(人类):立直时须满足“听牌不变”。
func human_ankan(hand_index: int) -> bool:
	return player_ankan(_human_seat, hand_index)


func player_ankan(seat: int, hand_index: int) -> bool:
	if phase != "await_discard" or current_seat != seat:
		return false
	if not _ankan_allowed(players[seat], hand_index):
		return false
	_do_ankan(players[seat], hand_index)
	return true


## 加杠(人类):把第 4 张加到已有的明碰上,他家可抢杠。
func human_kakan(hand_index: int) -> bool:
	return player_kakan(_human_seat, hand_index)


func player_kakan(seat: int, hand_index: int) -> bool:
	if phase != "await_discard" or current_seat != seat:
		return false
	return _try_kakan(players[seat], hand_index)


## 主动技能:咲 ±1(人类)。
func human_use_saki(hand_index: int, delta: int) -> bool:
	return player_use_saki(_human_seat, hand_index, delta)


func player_use_saki(seat: int, hand_index: int, delta: int) -> bool:
	if phase != "await_discard" or current_seat != seat:
		return false
	return apply_plusminus(players[seat], hand_index, delta)


## 主动技能:久 预约挑选(人类;下一次摸牌生效)。
func human_use_hisa() -> bool:
	return player_use_hisa(_human_seat)


func player_use_hisa(seat: int) -> bool:
	if phase != "await_discard" or current_seat != seat:
		return false
	var p := players[seat]
	if p.skill == null or p.skill.id != "hisa" or p.skill.uses_left <= 0 or p.riichi:
		return false
	if p.pending_peek > 0:
		return false
	p.pending_peek = p.skill.peek_depth(self, p)
	p.skill.uses_left -= 1
	log_event("%s 发动「認識の改変」——下一次摸牌将从墙顶挑选" % p.display_name)
	return true


## 主动技能:龙华 换牌(人类;刚摸的牌放回重摸)。
func human_use_mulligan() -> bool:
	return player_use_mulligan(_human_seat)


func player_use_mulligan(seat: int) -> bool:
	if phase != "await_discard" or current_seat != seat:
		return false
	return _do_mulligan(players[seat])


## 主动技能:憧 呼唤宝牌(人类)。
func human_use_ako() -> bool:
	return player_use_ako(_human_seat)


func player_use_ako(seat: int) -> bool:
	if phase != "await_discard" or current_seat != seat:
		return false
	return _do_ako(players[seat])


## 咲的核心实现:把手牌数组中的一张实体牌改写为同花色 ±1 的 kind。
func apply_plusminus(p: MPlayer, hand_index: int, delta: int) -> bool:
	if p.skill == null or p.skill.id != "saki" or p.skill.uses_left <= 0:
		return false
	if hand_index < 0 or hand_index >= p.hand.size():
		return false
	var kind := MTile.kind_of(p.hand[hand_index])
	var target := MTile.shift_kind(kind, delta)
	if target < 0:
		return false
	var new_id := wall.take_kind(target)
	if new_id < 0:
		new_id = target * 4  # 幻影牌:改写现实(判定只依赖 kind)
	var old_id: int = p.hand[hand_index]
	p.hand[hand_index] = new_id
	if p.just_drawn == old_id:
		p.just_drawn = new_id
	p.skill.uses_left -= 1
	log_event("%s 发动「+1/-1」:%s 改写为 %s!" % [p.display_name, MTile.label(kind), MTile.label(target)])
	return true


# ———————————————————— 响应(荣 / 碰 / 杠 / 吃) ————————————————————

func _execute_discard(p: MPlayer, idx: int) -> void:
	var tile_id := p.hand[idx]
	p.hand.remove_at(idx)
	p.river.append(tile_id)
	p.just_drawn = -1
	if p.riichi and p.riichi_discarded:
		p.discards_after_riichi += 1
	last_discard = {"seat": p.seat, "tile_id": tile_id, "kind": MTile.kind_of(tile_id)}
	log_event("%s 打出 %s" % [p.display_name, MTile.label_id(tile_id)])
	_collect_responses()
	if phase != "await_response":
		_next_turn()


## 收集各家对 last_discard 的响应并决定是否进入 await_response。
func _collect_responses() -> void:
	_resp = {}
	human_options = {}
	_awaiting = []
	_ron_chosen_seats = []
	_calls = {}
	for other in players:
		if other.seat == last_discard.seat:
			continue
		var opts := _options_for(other, last_discard.kind)
		_resp[other.seat] = opts
		if other.seat == _human_seat:
			human_options = opts
		if not other.is_ai and (opts.ron or opts.pon or opts.kan or (opts.chi as Array).size() > 0):
			_awaiting.append(other.seat)
	if _awaiting.size() > 0 or _has_ai_response():
		phase = "await_response"
	else:
		phase = "between"


func _has_ai_response() -> bool:
	for seat in _resp:
		if players[seat].is_ai:
			var opts: Dictionary = _resp[seat]
			if opts.ron or opts.pon or opts.kan or (opts.chi as Array).size() > 0:
				return true
	return false


func _options_for(p: MPlayer, kind: int) -> Dictionary:
	var opts := {
		"ron": _ronnable(p, kind),
		"pon": MAI.wants_pon(self, p, kind),
		"kan": MAI.wants_kan(self, p, kind),
		"chi": [],
	}
	# 吃:只有放铳者的下家
	var discarder: int = last_discard.get("seat", 0)
	if p.seat == (discarder + 1) % 4:
		opts.chi = chi_combos_for(p.hand, kind)
	return opts


## 能否荣和:形状可胡 + 有役 + 非振听(咲 ±1 一并考虑)。
func _ronnable(p: MPlayer, kind: int) -> bool:
	if p.is_furiten():
		return false
	var ctx := _ron_ctx(p, kind)
	var full := p.hand.duplicate()
	full.append(kind * 4 + 1)  # 检查用哑元 id(非红宝)
	if MYaku.evaluate(full, p.melds, ctx).win:
		return true
	if p.skill and p.skill.id == "saki" and p.skill.uses_left > 0:
		var move := _find_pm_with_extra(p, kind)
		if not move.is_empty():
			var full2 := full.duplicate()
			var shifted := MTile.shift_kind(MTile.kind_of(p.hand[move.index]), move.delta)
			full2[move.index] = shifted * 4 + 1
			return MYaku.evaluate(full2, p.melds, ctx).win
	return false


func _resolve_responses() -> void:
	# 1) 荣和(含多响):AI 荣 + 人类已宣告荣,各自满额由放铳/加杠者支付
	var ron_seats: Array[int] = []
	for seat in _resp:
		var opts: Dictionary = _resp[seat]
		if opts.get("ron", false) and (players[seat].is_ai or seat in _ron_chosen_seats):
			ron_seats.append(seat)
	if ron_seats.size() > 0:
		_apply_multi_ron(ron_seats)
		return
	# 抢杠:无荣和则完成加杠
	if not _pending_kakan.is_empty():
		_complete_kakan()
		return
	# 2) 人类的碰/杠/吃意向
	if _calls.size() > 0:
		var discarder0: int = last_discard.get("seat", 0)
		for k in 3:
			var seat := (discarder0 + 1 + k) % 4
			if _calls.has(seat):
				var me := players[seat]
				match _calls[seat].get("action", ""):
					"pon":
						_do_pon(me)
					"kan":
						_do_daiminkan(me)
					"chi":
						var combos: Array = _resp.get(seat, {}).get("chi", [])
						if _calls[seat].combo < combos.size():
							_do_chi(me, combos[_calls[seat].combo])
				_calls.erase(seat)
				return
	# 3) AI 响应:按离放铳者距离 杠 > 碰 > 吃(仅下家)
	var discarder: int = last_discard.get("seat", 0)
	for k in 3:
		var seat := (discarder + 1 + k) % 4
		var p := players[seat]
		if not p.is_ai:
			continue
		var opts: Dictionary = _resp.get(seat, {})
		if opts.get("kan", false):
			_do_daiminkan(p)
			return
		if opts.get("pon", false):
			_do_pon(p)
			return
		if k == 0 and (opts.chi as Array).size() > 0:
			var ci := MAI.choose_chi(self, p, opts.chi)
			if ci >= 0:
				_do_chi(p, opts.chi[ci])
				return
			# AI 判定吃不划算:放弃,继续下一回合
	_next_turn()


func human_ron() -> bool:
	return player_ron(_human_seat)


func player_ron(seat: int) -> bool:
	if phase != "await_response" or seat in _ron_chosen_seats or not seat in _awaiting:
		return false
	if not _resp.get(seat, {}).get("ron", false):
		return false
	_ron_chosen_seats.append(seat)
	_awaiting.erase(seat)
	return true


func human_pon() -> bool:
	return player_pon(_human_seat)


func player_pon(seat: int) -> bool:
	if phase != "await_response" or seat in _ron_chosen_seats or not seat in _awaiting:
		return false
	if not _resp.get(seat, {}).get("pon", false):
		return false
	_calls[seat] = {"action": "pon"}
	_awaiting.erase(seat)
	return true


func human_kan() -> bool:
	return player_kan(_human_seat)


func player_kan(seat: int) -> bool:
	if phase != "await_response" or seat in _ron_chosen_seats or not seat in _awaiting:
		return false
	if not _resp.get(seat, {}).get("kan", false):
		return false
	_calls[seat] = {"action": "kan"}
	_awaiting.erase(seat)
	return true


## 人类吃:combo_index 为 human_options.chi 中的下标。
func human_chi(combo_index: int) -> bool:
	return player_chi(_human_seat, combo_index)


func player_chi(seat: int, combo_index: int) -> bool:
	if phase != "await_response" or seat in _ron_chosen_seats or not seat in _awaiting:
		return false
	var combos: Array = _resp.get(seat, {}).get("chi", [])
	if combo_index < 0 or combo_index >= combos.size():
		return false
	_calls[seat] = {"action": "chi", "combo": combo_index}
	_awaiting.erase(seat)
	return true


func human_decline() -> void:
	player_decline(_human_seat)


func player_decline(seat: int) -> void:
	if phase == "await_response":
		_awaiting.erase(seat)

# ———————————————————— 副露实现 ————————————————————

## 枚举手中能与 kind 组成顺子的两张牌组合:[{called:位置, tiles:[k1,k2], low:顺子最小kind}]
func chi_combos_for(hand: Array, kind: int) -> Array:
	if MTile.is_honor(kind):
		return []
	var counts := MTile.to_counts(hand)
	var out: Array = []
	for called in 3:
		var low := kind - called
		if low < 0 or low > 6 or MTile.suit(low) != MTile.suit(kind):
			continue
		var others := [low + 0, low + 1, low + 2]
		others.erase(kind)
		var need_a: int = others[0]
		var need_b: int = others[1]
		if counts[need_a] > 0 and counts[need_b] > 0:
			out.append({"called": called, "tiles": [need_a, need_b], "low": low})
	return out


func _do_pon(p: MPlayer) -> void:
	var kind: int = last_discard.kind
	_remove_kinds(p, kind, 2)
	p.melds.append({"type": "pon", "kind": kind})
	_break_ippatsu()
	log_event("%s 碰 %s" % [p.display_name, MTile.label(kind)])
	current_seat = p.seat
	phase = "await_discard"


func _do_chi(p: MPlayer, combo: Dictionary) -> void:
	var kind: int = last_discard.kind
	for k in combo.tiles:
		_remove_one_kind(p, k)
	p.melds.append({"type": "chi", "kind": combo.low, "called": combo.called})
	_break_ippatsu()
	log_event("%s 吃 %s(%s)" % [p.display_name, MTile.label(kind), _combo_text(combo, kind)])
	current_seat = p.seat
	phase = "await_discard"


func _do_daiminkan(p: MPlayer) -> void:
	var kind: int = last_discard.kind
	_remove_kinds(p, kind, 3)
	p.melds.append({"type": "kan_open", "kind": kind})
	wall.reveal_extra_dora()
	_break_ippatsu()
	log_event("%s 大明杠 %s(宝牌指示 +1)" % [p.display_name, MTile.label(kind)])
	current_seat = p.seat
	_draw_rinshan(p)


func _do_ankan(p: MPlayer, hand_index: int) -> void:
	var kind := MTile.kind_of(p.hand[hand_index])
	_remove_kinds(p, kind, 4)
	p.melds.append({"type": "kan_closed", "kind": kind})
	wall.reveal_extra_dora()
	log_event("%s 暗杠 %s" % [p.display_name, MTile.label(kind)])
	_draw_rinshan(p)


## 加杠:宣告后他家可抢杠;无抢杠才真正完成。
func _try_kakan(p: MPlayer, hand_index: int) -> bool:
	if hand_index < 0 or hand_index >= p.hand.size():
		return false
	var kind := MTile.kind_of(p.hand[hand_index])
	var has_pon := false
	for m in p.melds:
		if m.type == "pon" and m.kind == kind:
			has_pon = true
	if not has_pon:
		return false
	_pending_kakan = {"seat": p.seat, "kind": kind, "tile_id": p.hand[hand_index]}
	last_discard = {"seat": p.seat, "tile_id": p.hand[hand_index], "kind": kind, "kakan": true}
	# 抢杠响应:仅荣和
	_resp = {}
	human_options = {}
	_awaiting = []
	_ron_chosen_seats = []
	_calls = {}
	var any := false
	for other in players:
		if other.seat == p.seat:
			continue
		var opts := {"ron": _ronnable(other, kind), "pon": false, "kan": false, "chi": []}
		_resp[other.seat] = opts
		if other.seat == _human_seat:
			human_options = opts
		if opts.ron:
			any = true
			if not other.is_ai:
				_awaiting.append(other.seat)
	log_event("%s 宣告加杠 %s" % [p.display_name, MTile.label(kind)])
	if any:
		phase = "await_response"
	else:
		_complete_kakan()
	return true


func _complete_kakan() -> void:
	var seat: int = _pending_kakan.seat
	var kind: int = _pending_kakan.kind
	var tile_id: int = _pending_kakan.tile_id
	var p := players[seat]
	var idx := p.hand.find(tile_id)
	if idx >= 0:
		p.hand.remove_at(idx)
	for m in p.melds:
		if m.type == "pon" and m.kind == kind:
			m.type = "kan_added"
	wall.reveal_extra_dora()
	log_event("%s 加杠 %s(宝牌指示 +1)" % [p.display_name, MTile.label(kind)])
	_pending_kakan = {}
	_draw_rinshan(p)


func _remove_kinds(p: MPlayer, kind: int, count: int) -> void:
	for i in count:
		_remove_one_kind(p, kind)


func _remove_one_kind(p: MPlayer, kind: int) -> void:
	for i in p.hand.size():
		if MTile.kind_of(p.hand[i]) == kind:
			p.hand.remove_at(i)
			return


func _combo_text(combo: Dictionary, called_kind: int) -> String:
	var parts: Array[String] = []
	for k in [combo.low, combo.low + 1, combo.low + 2]:
		parts.append(MTile.label(k) if k != called_kind else "[%s]" % MTile.label(k))
	return "".join(parts)


func _draw_rinshan(p: MPlayer) -> void:
	if wall.is_exhausted():
		_end_draw()
		return
	var tile := wall.draw_rinshan()
	if p.skill != null and p.skill.passive_rinshan:
		var weights: Array = p.skill.rinshan_weights(self, p)
		if weights.size() == MTile.KIND_COUNT:
			tile = wall.draw_rinshan_weighted(weights)
	p.rinshan_flag = true
	p.just_drawn = tile
	p.hand.append(tile)
	_expire_ippatsu(p)
	phase = "await_discard"


## 龙华「恵みの雨」:刚摸的牌放回墙顶,重摸一张(可能仍是同一张)。
func _do_mulligan(p: MPlayer) -> bool:
	if p.skill == null or p.skill.id != "ryuuka" or p.skill.uses_left <= 0:
		return false
	if p.just_drawn < 0 or p.hand.is_empty():
		return false
	var idx := p.hand.find(p.just_drawn)
	if idx < 0:
		return false
	p.hand.remove_at(idx)
	wall.ids.append(p.just_drawn)
	p.skill.uses_left -= 1
	log_event("%s 发动「恵みの雨」:%s 回到墙顶,再摸一张" % [p.display_name, MTile.label_id(p.just_drawn)])
	var tile := wall.draw_top()
	p.just_drawn = tile
	p.hand.append(tile)
	log_event("%s 重摸 %s" % [p.display_name, MTile.label_id(tile)])
	return true


## 憧「牌の背中」:把手中最多的一张宝牌移到自己下一次摸的位置(3 家摸牌之后)。
func _do_ako(p: MPlayer) -> bool:
	if p.skill == null or p.skill.id != "ako" or p.skill.uses_left <= 0:
		return false
	var dora_kinds := wall.dora_kinds()
	var best_kind := -1
	var best_n := 0
	var counts := p.concealed_counts()
	for kind in dora_kinds:
		if counts[kind] > best_n:
			best_n = counts[kind]
			best_kind = kind
	if best_kind < 0:
		# 手中没有宝牌:挑墙里剩余最多的一门宝牌
		for kind in dora_kinds:
			var n := 0
			for id in wall.ids:
				if MTile.kind_of(id) == kind:
					n += 1
			if n > best_n:
				best_n = n
				best_kind = kind
	if best_kind < 0:
		return false
	wall.reorder_to_depth(best_kind, 3)
	p.skill.uses_left -= 1
	log_event("%s 发动「牌の背中」:感知到 %s 正在牌山深处沉睡" % [p.display_name, MTile.label(best_kind)])
	return true


## 暗杠是否被允许:非立直恒可;立直时要求“原来的每一张听牌,
## 在暗杠后(把暗杠视为已完成的杠、并留出岭上换牌的余地)仍然是听牌”。
func _ankan_allowed(p: MPlayer, hand_index: int) -> bool:
	if hand_index < 0 or hand_index >= p.hand.size():
		return false
	var n := 0
	var kind := MTile.kind_of(p.hand[hand_index])
	for tile_id in p.hand:
		if MTile.kind_of(tile_id) == kind:
			n += 1
	if n < 4:
		return false
	if not p.riichi:
		return true
	if p.just_drawn < 0:
		return false
	var before := _waits_of_hand_without(p, p.just_drawn)
	if before.is_empty():
		return false
	var after := p.concealed_counts()
	after[kind] -= 4
	var waits_after: Array[int] = []
	for kind2 in MTile.KIND_COUNT:
		if after[kind2] >= 4:
			continue
		after[kind2] += 1
		if MYaku.can_win(after, p.melds.size() + 1):
			waits_after.append(kind2)
		after[kind2] -= 1
	for w in before:
		if not waits_after.has(w):
			return false
	return true


func _waits_of_hand_without(p: MPlayer, drawn_id: int) -> Array[int]:
	var counts := MTile.to_counts(_hand_without_id(p, drawn_id))
	var waits: Array[int] = []
	for kind in MTile.KIND_COUNT:
		if counts[kind] >= 4:
			continue
		counts[kind] += 1
		if MYaku.can_win(counts, p.melds.size()):
			waits.append(kind)
		counts[kind] -= 1
	return waits


func _hand_without_id(p: MPlayer, tile_id: int) -> Array[int]:
	var out: Array[int] = []
	var removed := false
	for id in p.hand:
		if not removed and id == tile_id:
			removed = true
			continue
		out.append(id)
	return out


func _same_kinds(a: Array[int], b: Array[int]) -> bool:
	if a.size() != b.size():
		return false
	for x in a:
		if not b.has(x):
			return false
	return true


# ———————————————————— 和牌 / 结算 ————————————————————

func _apply_multi_ron(win_seats: Array[int]) -> void:
	var is_kakan: bool = last_discard.get("kakan", false)
	var loser: int = last_discard.get("seat", 0)
	var summed := {}
	for seat in 4:
		summed[seat] = 0
	var primary := {}
	var winners: Array[String] = []
	for ws in win_seats:
		var p := players[ws]
		var full := p.hand.duplicate()
		full.append(last_discard.tile_id)
		var res := MYaku.evaluate(full, p.melds, _ron_ctx(p, last_discard.kind))
		# 咲:形状差一点时先尝试 ±1 改写
		if not res.win and p.skill and p.skill.id == "saki":
			var move := _find_pm_with_extra(p, last_discard.kind)
			if not move.is_empty() and apply_plusminus(p, move.index, move.delta):
				full = p.hand.duplicate()
				full.append(last_discard.tile_id)
				res = MYaku.evaluate(full, p.melds, _ron_ctx(p, last_discard.kind))
		if not res.win:
			continue
		for seat in res.payments:
			summed[seat] += res.payments[seat]
		winners.append(p.display_name)
		if primary.is_empty():
			primary = res
	for seat in summed:
		players[seat].score += summed[seat]
	if winners.is_empty():
		# 理论不可达:全部荣和失败则回退为过
		_next_turn()
		return
	if is_kakan:
		log_event("★ 抢杠!%s 荣和 %s" % [", ".join(winners), MTile.label_id(last_discard.tile_id)])
	result = {
		"type": "win", "winners": win_seats, "winner": win_seats[0],
		"tsumo": false, "double": win_seats.size() > 1,
		"han": primary.get("han", 0), "fu": primary.get("fu", 0), "yaku": primary.get("yaku", []),
		"payments": summed, "hand": players[win_seats[0]].hand.duplicate(),
		"melds": players[win_seats[0]].melds.duplicate(),
	}
	log_event("★ %s 荣和 %s!%s —— %d 翻 %d 符%s" % [
		", ".join(winners), MTile.label_id(last_discard.tile_id),
		", ".join(primary.get("yaku", [])), primary.get("han", 0), primary.get("fu", 0),
		("(双响)" if win_seats.size() > 1 else ""),
	])
	_pending_kakan = {}
	phase = "round_end"


func _tsumo_result(p: MPlayer) -> Dictionary:
	var ctx := {
		"tsumo": true,
		"kuitan": bool(rules.kuitan),
		"riichi": p.riichi,
		"ippatsu": p.ippatsu,
		"rinshan": p.rinshan_flag,
		"seat_wind": MTile.EAST + p.seat,
		"round_wind": MTile.EAST,
		"win_tile_kind": MTile.kind_of(p.just_drawn) if p.just_drawn >= 0 else -1,
		"dora_kinds": wall.dora_kinds(),
		"ura_dora_kinds": wall.ura_kinds() if (p.riichi and bool(rules.ura)) else [],
		"dealer_seat": dealer_seat,
		"win_seat": p.seat,
	}
	return MYaku.evaluate(p.hand, p.melds, ctx)


func _ron_ctx(p: MPlayer, kind: int) -> Dictionary:
	return {
		"tsumo": false,
		"kuitan": bool(rules.kuitan),
		"riichi": p.riichi,
		"ippatsu": p.ippatsu,
		"rinshan": false,
		"seat_wind": MTile.EAST + p.seat,
		"round_wind": MTile.EAST,
		"win_tile_kind": kind,
		"dora_kinds": wall.dora_kinds(),
		"ura_dora_kinds": wall.ura_kinds() if (p.riichi and bool(rules.ura)) else [],
		"dealer_seat": dealer_seat,
		"win_seat": p.seat,
		"loser_seat": last_discard.get("seat", (p.seat + 1) % 4),
	}


func _apply_win(p: MPlayer, res: Dictionary, tsumo: bool) -> void:
	for seat in res.payments:
		players[seat].score += res.payments[seat]
	result = {
		"type": "win", "winners": [p.seat], "winner": p.seat, "tsumo": tsumo,
		"han": res.han, "fu": res.fu, "yaku": res.yaku,
		"payments": res.payments, "hand": p.hand.duplicate(), "melds": p.melds.duplicate(),
	}
	var action := "自摸" if tsumo else "荣和 %s" % MTile.label_id(last_discard.tile_id)
	log_event("★ %s %s!%s —— %d 翻 %d 符" % [p.display_name, action, ", ".join(res.yaku), res.han, res.fu])
	phase = "round_end"


## 荒牌流局:听牌者分得 3000 点(不听牌者支付)。
func _end_draw() -> void:
	var tenpai_flags := {}
	var noten_seats: Array[int] = []
	var tenpai_seats: Array[int] = []
	for p in players:
		var standing: bool = p.hand.size() == 13 - 3 * p.melds.size()
		var t: bool = standing and p.is_tenpai()
		tenpai_flags[p.seat] = t
		if t:
			tenpai_seats.append(p.seat)
		else:
			noten_seats.append(p.seat)
	var payments := {}
	for seat in 4:
		payments[seat] = 0
	if noten_seats.size() > 0 and tenpai_seats.size() > 0:
		var pay := 3000 / noten_seats.size()
		var recv := 3000 / tenpai_seats.size()
		for s in noten_seats:
			payments[s] -= pay
		for s in tenpai_seats:
			payments[s] += recv
	for seat in payments:
		players[seat].score += payments[seat]
	result = {"type": "draw", "reason": "wall_exhausted", "tenpai": tenpai_flags, "payments": payments}
	var desc := ""
	for p in players:
		desc += "%s:%s " % [p.display_name, "听牌" if tenpai_flags[p.seat] else "不听"]
	log_event("—— 荒牌流局(%s)——" % desc.strip_edges())
	phase = "round_end"


func _next_turn() -> void:
	if wall.is_exhausted():
		_end_draw()
		return
	current_seat = (current_seat + 1) % 4
	turn_count += 1
	phase = "turn_draw"


# ———————————————————— 工具 ————————————————————

func _can_win_now(p: MPlayer) -> bool:
	return MYaku.can_win(p.concealed_counts(), p.melds.size())


func _hand_without(p: MPlayer, idx: int) -> Array[int]:
	var out: Array[int] = []
	for i in p.hand.size():
		if i != idx:
			out.append(p.hand[i])
	return out


## 13 张手 + 即将到手的 kind,寻找 ±1 改写使形状可胡(咲)。
func _find_pm_with_extra(p: MPlayer, extra_kind: int) -> Dictionary:
	if p.skill == null or p.skill.id != "saki" or p.skill.uses_left <= 0:
		return {}
	var counts := p.concealed_counts()
	for i in p.hand.size():
		var kind := MTile.kind_of(p.hand[i])
		for delta in [1, -1]:
			var target := MTile.shift_kind(kind, delta)
			if target < 0 or target == extra_kind or counts[target] >= 4:
				continue
			counts[kind] -= 1
			counts[target] += 1
			counts[extra_kind] += 1
			var win := MYaku.can_win(counts, p.melds.size())
			counts[extra_kind] -= 1
			counts[kind] += 1
			counts[target] -= 1
			if win:
				return {"index": i, "delta": delta}
	return {}


func human_seat() -> int:
	return _human_seat


# ———————————————————— 联机快照:主机权威 → 客户端副本 ————————————————————

## 为指定座位构建“视角快照”:自家手牌为真实 id,其余座位只有牌数。
func snapshot_for(seat: int) -> Dictionary:
	var snap := {
		"phase": phase, "current_seat": current_seat, "turn_count": turn_count,
		"dealer_seat": dealer_seat,
		"scores": {}, "riichi": {}, "disc_riichi": {}, "rivers": {}, "melds": {}, "hand_sizes": {},
		"dora": wall.dora_kinds(), "ura": wall.ura_kinds(),
		"wall_left": wall.tiles_left(),
		"last_discard": last_discard, "peek_options": peek_options.duplicate(),
		"options": (_resp.get(seat, {}) if players[seat].is_ai == false else {}),
		"awaiting": _awaiting.duplicate(),
		"just_drawn": players[seat].just_drawn,
		"hand": players[seat].hand.duplicate(),
		"result": (result.duplicate(true) if phase == "round_end" else {}),
		"pending_peek": players[seat].pending_peek,
		"human_seat": seat,
	}
	for p in players:
		snap.scores[p.seat] = p.score
		snap.riichi[p.seat] = p.riichi
		snap.disc_riichi[p.seat] = p.discards_after_riichi
		snap.rivers[p.seat] = p.river.duplicate()
		snap.melds[p.seat] = p.melds.duplicate(true)
		snap.hand_sizes[p.seat] = p.hand.size()
	return snap


## 客户端:把快照应用到本地副本(用于纯显示;动作通过 RPC 发给主机)。
func apply_snapshot(snap: Dictionary) -> void:
	phase = snap.phase
	current_seat = snap.current_seat
	turn_count = snap.turn_count
	dealer_seat = snap.dealer_seat
	last_discard = snap.last_discard
	peek_options = []
	for id in snap.peek_options:
		peek_options.append(id)
	result = snap.result
	wall.forced_dora = []
	for k in snap.dora:
		wall.forced_dora.append(k)
	wall.forced_ura = []
	for k in snap.ura:
		wall.forced_ura.append(k)
	human_options = snap.options
	human_options["awaiting"] = snap.awaiting
	_awaiting = []
	for seat in snap.awaiting:
		_awaiting.append(seat)
	for p in players:
		p.score = snap.scores[p.seat]
		p.riichi = snap.riichi[p.seat]
		p.discards_after_riichi = snap.disc_riichi[p.seat]
		p.river = []
		for id in snap.rivers[p.seat]:
			p.river.append(id)
		p.melds.clear()
		for m in snap.melds[p.seat]:
			p.melds.append(m)
		var size: int = snap.hand_sizes[p.seat]
		p.hand.clear()
		if p.seat == snap.human_seat:
			for id in snap.hand:
				p.hand.append(id)
			p.just_drawn = snap.just_drawn
		else:
			for i in size:
				p.hand.append(i + 1)  # 占位 id:对手手牌仅用于显示张数


## 每有鸣牌(碰/杠/吃)即打断全部一发机会。
func _break_ippatsu() -> void:
	for p in players:
		p.ippatsu = false


func log_event(text: String) -> void:
	events.append(text)
	event_added.emit(text)
