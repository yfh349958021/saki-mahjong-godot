class_name MSkills
extends RefCounted
## 25 位角色的技能实现(按学校分组),全部为真实机制(纯数据操作,无 UI):
##  —— 清澄高中 ——
##   宫永咲「岭上开花/杠精」: 杠后岭上自摸率极高;极易摸到形成刻子/杠子的牌
##   原村和「网络麻将(和仔)」: 摸牌效率×2.2;AI 强制满难度数理打法
##   片冈优希「东场无敌」: 进牌率×2、和牌率×2.5(单东风局常驻)
##   竹井久「愚听必中」: 听牌为坎张/边张/单骑等愚形时,自摸进张×8
##   染谷真子「记忆重现」: 危险牌透视 + AI 强防守(大幅降低放铳)
##  —— 龙门渕高中 ——
##   天江衣「海底捞月/满月支配」: 晚巡听牌自摸×50;压迫:他家进张×0.6
##   龙门渕透华「冷艳透华」: 对技能型对手时进张×1.8 + AI 强防守
##   井上纯「鸣牌破坏」: AI 积极鸣牌;鸣牌后 3 巡他家进张×0.45
##   国广一「起手向听推进」: 配牌自动向有效张置换两次,起手向听显著降低
##   泽村智纪「概率演算」: AI 强防守;UI 标记手牌危险/安全
##  —— 风越女子 & 鹤贺学园 ——
##   福路美穗子「开眼」: 透视各家花色分布(UI 显示)+ AI 避开多花色
##   加治木由美「狙击立直」: 立直后他家进张×0.8
##   东横桃子「隐形」: 立直/听牌时他家 AI 不再对她防守
##  —— 阿知贺女子学院 ——
##   高鸭稳乃「山深统治」: 牌山越少进张越强(最高×5);封印天江衣的晚巡能力
##   新子憧「鸣牌加速」: AI 积极鸣牌;自家进张×1.5
##   松实玄「宝牌召唤」: 宝牌 kind 摸牌权重×4;打宝牌后短暂失效
##   松实宥「红牌偏好」: 赤宝牌(红5)kind 摸牌权重×5
##   鹭森灼「保龄球瓶阵」: 听 1/2/4/5/7/8 数牌(愚形瓶阵)时自摸×6
##  —— 千里山女子高中 ——
##   园城寺怜「未来视」: UI 显示接下来 3 张牌墙牌 + AI 强防守
##   清水谷龙华「怜的加持」: 主动 ×2/局:5 巡内进张×4、听牌自摸×8
##   二条泉「安打流」: 进张×2;AI 积极鸣牌速攻低番
##  —— 白糸台高校 ——
##   宫永照「照魔镜/连续升登」: 透视他家听牌标记 + AI 强防守;连续和牌每局 +2 翻
##   涩谷尧深「第一打回溯」: 牌山剩 8 张时,第一打弃牌自动回手替换最无用一张
##   亦野诚子「三副露必和」: 3 副露后进张×5、自摸×10
##   弘世菫「精准射击」: 立直后他家摸牌向菫所听牌倾斜(×3 放铳)


## 学校分组(两级选人)
const SCHOOLS := [
	{"name": "清澄高中", "chars": ["saki", "nodoka", "yuuki", "hisa", "mako"]},
	{"name": "龙门渕高中", "chars": ["koromo", "toki", "jun", "kazue", "tomoki"]},
	{"name": "风越女子 & 鹤贺学园", "chars": ["mihoko", "kajiki", "touko"]},
	{"name": "阿知贺女子学院", "chars": ["shizuno", "ako", "kuro", "yuu", "atsushi"]},
	{"name": "千里山女子高中", "chars": ["rei", "ryuuka", "izumi"]},
	{"name": "白糸台高校", "chars": ["teru", "takakura", "yano", "kokaji"]},
]

const RED_KINDS := [4, 13, 22]          # 赤 5 万/筒/索
const BOWLING_RANKS := [1, 2, 4, 5, 7, 8]  # 鹭森灼:保龄球瓶阵数牌


static func create(skill_id: String) -> MSkill:
	match skill_id:
		"saki": return SkillSaki.new()
		"nodoka": return SkillNodoka.new()
		"yuuki": return SkillYuuki.new()
		"hisa": return SkillHisa.new()
		"mako": return SkillMako.new()
		"koromo": return SkillKoromo.new()
		"toki": return SkillToki.new()
		"jun": return SkillJun.new()
		"kazue": return SkillKazue.new()
		"tomoki": return SkillTomoki.new()
		"mihoko": return SkillMihoko.new()
		"kajiki": return SkillKajiki.new()
		"touko": return SkillTouko.new()
		"shizuno": return SkillShizuno.new()
		"ako": return SkillAko.new()
		"kuro": return SkillKuro.new()
		"yuu": return SkillYuu.new()
		"atsushi": return SkillAtsushi.new()
		"rei": return SkillRei.new()
		"ryuuka": return SkillRyuuka.new()
		"izumi": return SkillIzumi.new()
		"teru": return SkillTeru.new()
		"takakura": return SkillTakakura.new()
		"yano": return SkillYano.new()
		"kokaji": return SkillKokaji.new()
		_: return MSkill.new()


## —— 共用小工具 ——

## 听牌时,和牌张 w 是否两面听(好听);坎/边/单骑返回 false(愚形)
static func _is_yuukei_wait(counts: Array[int], w: int) -> bool:
	if w >= 27:
		return false
	var r := w % 9 + 1
	var low_in := counts[w - 1] > 0 if r >= 2 else false
	var low2_in := counts[w - 2] > 0 if r >= 3 else false
	var high_in := counts[w + 1] > 0 if r <= 8 else false
	var high2_in := counts[w + 2] > 0 if r <= 7 else false
	if low_in and high_in:
		return false  # 坎张
	if low_in and low2_in and r >= 3:
		return true   # 两面(低侧)
	if high_in and high2_in and r <= 7:
		return true   # 两面(高侧)
	return false        # 边张 / 单骑变体 = 愚形


## 摸到 w 是否为灼的保龄球瓶阵数牌
static func _is_bowling_rank(w: int) -> bool:
	var r := w % 9 + 1
	return r in BOWLING_RANKS


## —— 清澄高中 ——

class SkillSaki:
	extends MSkill
	func _init() -> void:
		id = "saki"
		char_name = "宫永咲"
		title = "岭上开花 / 杠精"
		desc = "被动:杠后岭上牌自摸率极高;且极易摸到形成刻子/杠子的牌。"
		passive_weight = true
		passive_rinshan = true
	func modify_draw_weights(_t, player, weights: Array) -> void:
		var counts: Array[int] = player.concealed_counts()
		for k in MTile.KIND_COUNT:
			if counts[k] >= 2:
				weights[k] *= 3.0
	func rinshan_weights(_t, player) -> Array:
		var w: Array = []
		w.resize(MTile.KIND_COUNT)
		w.fill(1.0)
		var counts: Array[int] = player.concealed_counts()
		var base := MShanten.for_counts(counts, player.melds.size())
		for k in MTile.KIND_COUNT:
			if counts[k] >= 4:
				continue
			counts[k] += 1
			var st := MShanten.for_counts(counts, player.melds.size())
			counts[k] -= 1
			if st < base:
				w[k] = 8.0
			if st < 0:
				w[k] = 15.0
		return w


class SkillNodoka:
	extends MSkill
	func _init() -> void:
		id = "nodoka"
		char_name = "原村和"
		title = "网络麻将模式(和仔)"
		desc = "被动:配牌与摸牌效率大幅提升(进张×2.2),失误率极低,AI 强制数理最佳打法。"
		passive_weight = true
	func modify_draw_weights(_t, player, weights: Array) -> void:
		if player.riichi:
			return
		var counts: Array[int] = player.concealed_counts()
		var base := MShanten.for_counts(counts, player.melds.size())
		for k in MTile.KIND_COUNT:
			if counts[k] >= 4:
				continue
			counts[k] += 1
			if MShanten.for_counts(counts, player.melds.size()) < base:
				weights[k] *= 2.2
			counts[k] -= 1


class SkillYuuki:
	extends MSkill
	func _init() -> void:
		id = "yuuki"
		char_name = "片冈优希"
		title = "东场无敌(墨西哥卷饼)"
		desc = "被动:东风场配牌极好、进牌率×2、和牌率×2.5 —— 本局即东风场,全程生效。"
		passive_weight = true
	func modify_draw_weights(_t, player, weights: Array) -> void:
		if player.riichi:
			return
		var counts: Array[int] = player.concealed_counts()
		var base := MShanten.for_counts(counts, player.melds.size())
		for k in MTile.KIND_COUNT:
			if counts[k] >= 4:
				continue
			counts[k] += 1
			var st := MShanten.for_counts(counts, player.melds.size())
			counts[k] -= 1
			if st < base:
				weights[k] *= 2.0
			if st < 0:
				weights[k] *= 2.5


class SkillHisa:
	extends MSkill
	func _init() -> void:
		id = "hisa"
		char_name = "竹井久"
		title = "愚听 / 愚形必中"
		desc = "被动:听牌为坎张/边张/单骑等愚形时,自摸进张×8 —— 愚听反而更好中。"
		passive_weight = true
	func modify_draw_weights(_t, player, weights: Array) -> void:
		if player.riichi or not player.is_tenpai():
			return
		var counts: Array[int] = player.concealed_counts()
		var winning: Array[int] = []
		var all_yakukei := true  # 全部听牌都是坎/边/单骑等愚形
		for k in MTile.KIND_COUNT:
			if counts[k] >= 4:
				continue
			counts[k] += 1
			var win := MYaku.can_win(counts, player.melds.size())
			if win:
				winning.append(k)
				if MSkills._is_yuukei_wait(counts, k):
					all_yakukei = false  # 存在两面好听则不发动
			counts[k] -= 1
		if winning.size() > 0 and all_yakukei:
			for w in winning:
				weights[w] *= 8.0


class SkillMako:
	extends MSkill
	func _init() -> void:
		id = "mako"
		char_name = "染谷真子"
		title = "记忆重现"
		desc = "被动:看穿危险牌 —— 手牌上标记会放铳的牌(红点),AI 大幅强化防守。"

## —— 龙门渕高中 ——

class SkillKoromo:
	extends MSkill
	func _init() -> void:
		id = "koromo"
		char_name = "天江衣"
		title = "海底捞月 / 满月支配"
		desc = "被动:晚巡(余牌≤5)听牌时自摸×50;满月支配 —— 其他玩家进张×0.6(被稳乃封印时无效)。"
		passive_weight = true
	func modify_draw_weights(t, player, weights: Array) -> void:
		if not player.is_tenpai() or t.wall.tiles_left() > 5 or t._shizuno_seal():
			return
		var counts: Array[int] = player.concealed_counts()
		for k in MTile.KIND_COUNT:
			if counts[k] >= 4:
				continue
			counts[k] += 1
			if MYaku.can_win(counts, player.melds.size()):
				weights[k] *= 50.0
			counts[k] -= 1


class SkillToki:
	extends MSkill
	func _init() -> void:
		id = "toki"
		char_name = "龙门渕透华"
		title = "冷艳透华模式"
		desc = "被动:场上有技能型对手时,进张×1.8 且 AI 攻防大幅增强。"
		passive_weight = true
	func modify_draw_weights(t, player, weights: Array) -> void:
		if player.riichi:
			return
		for other in t.players:
			if other.seat != player.seat and other.skill != null and other.skill.id != "none":
				var counts: Array[int] = player.concealed_counts()
				var base := MShanten.for_counts(counts, player.melds.size())
				for k in MTile.KIND_COUNT:
					if counts[k] >= 4:
						continue
					counts[k] += 1
					if MShanten.for_counts(counts, player.melds.size()) < base:
						weights[k] *= 1.8
					counts[k] -= 1
				return


class SkillJun:
	extends MSkill
	func _init() -> void:
		id = "jun"
		char_name = "井上纯"
		title = "鸣牌破坏"
		desc = "被动:AI 积极鸣牌;每次吃/碰后 3 巡内其他玩家进张×0.45(顺位破坏)。"


class SkillKazue:
	extends MSkill
	func _init() -> void:
		id = "kazue"
		char_name = "国广一"
		title = "起手向听推进"
		desc = "被动:配牌自动向有效张置换两次,起手向听显著降低。"


class SkillTomoki:
	extends MSkill
	func _init() -> void:
		id = "tomoki"
		char_name = "泽村智纪"
		title = "概率演算"
		desc = "被动:手牌标记危险(红点)与安全(绿点),AI 强防守。"

## —— 风越女子 & 鹤贺学园 ——

class SkillMihoko:
	extends MSkill
	func _init() -> void:
		id = "mihoko"
		char_name = "福路美穗子"
		title = "开眼(看穿花色)"
		desc = "被动:开眼看穿各家牌的花色分布,UI 实时显示;AI 避开他家多的花色。"


class SkillKajiki:
	extends MSkill
	func _init() -> void:
		id = "kajiki"
		char_name = "加治木由美"
		title = "狙击立直"
		desc = "被动:立直后施加压制 —— 其他玩家进张×0.8;AI 擅长追立直。"


class SkillTouko:
	extends MSkill
	func _init() -> void:
		id = "touko"
		char_name = "东横桃子"
		title = "隐形(stealth)"
		desc = "被动:听牌/立直时存在感消失 —— 其他家 AI 不再对她防守,极易放铳。"

## —— 阿知贺女子学院 ——

class SkillShizuno:
	extends MSkill
	func _init() -> void:
		id = "shizuno"
		char_name = "高鸭稳乃"
		title = "山深统治(晚巡支配)"
		desc = "被动:牌山越少进张越强(最高×5)、自摸×8;封印天江衣的晚巡能力。"
		passive_weight = true
	func modify_draw_weights(t, player, weights: Array) -> void:
		if player.riichi:
			return
		var f := 1.0 - float(t.wall.tiles_left()) / 122.0
		var mult := 1.0 + 4.0 * f
		var counts: Array[int] = player.concealed_counts()
		var base := MShanten.for_counts(counts, player.melds.size())
		for k in MTile.KIND_COUNT:
			if counts[k] >= 4:
				continue
			counts[k] += 1
			var st := MShanten.for_counts(counts, player.melds.size())
			counts[k] -= 1
			if st < base:
				weights[k] *= mult
			if st < 0:
				weights[k] *= 1.6


class SkillAko:
	extends MSkill
	func _init() -> void:
		id = "ako"
		char_name = "新子憧"
		title = "鸣牌加速"
		desc = "被动:自家进张×1.5,AI 积极鸣牌速攻。"
		passive_weight = true
	func modify_draw_weights(_t, player, weights: Array) -> void:
		if player.riichi:
			return
		var counts: Array[int] = player.concealed_counts()
		var base := MShanten.for_counts(counts, player.melds.size())
		for k in MTile.KIND_COUNT:
			if counts[k] >= 4:
				continue
			counts[k] += 1
			if MShanten.for_counts(counts, player.melds.size()) < base:
				weights[k] *= 1.5
			counts[k] -= 1


class SkillKuro:
	extends MSkill
	func _init() -> void:
		id = "kuro"
		char_name = "松实玄"
		title = "宝牌召唤(Dora 领主)"
		desc = "被动:宝牌摸到概率×4;切出宝牌后短暂失效。"
		passive_weight = true
	func modify_draw_weights(t, player, weights: Array) -> void:
		if t.is_last_discard_dora(player):
			return  # 切出宝牌后短暂失效
		for kind in t.wall.dora_kinds():
			weights[kind] *= 4.0


class SkillYuu:
	extends MSkill
	func _init() -> void:
		id = "yuu"
		char_name = "松实宥"
		title = "红牌偏好(暖牌)"
		desc = "被动:赤宝牌(红5万/5筒/5索)会向宥集结,摸到概率×5,易凑高番。"
		passive_weight = true
	func modify_draw_weights(_t, _player, weights: Array) -> void:
		for kind in MSkills.RED_KINDS:
			weights[kind] *= 5.0


class SkillAtsushi:
	extends MSkill
	func _init() -> void:
		id = "atsushi"
		char_name = "鹭森灼"
		title = "保龄球瓶阵"
		desc = "被动:听牌数牌为 1/2/4/5/7/8(瓶阵)时,自摸进张×6。"
		passive_weight = true
	func modify_draw_weights(_t, player, weights: Array) -> void:
		if player.riichi or not player.is_tenpai():
			return
		var counts: Array[int] = player.concealed_counts()
		for k in MTile.KIND_COUNT:
			if counts[k] >= 4 or MTile.is_honor(k):
				continue
			if not MSkills._is_bowling_rank(k):
				continue
			counts[k] += 1
			var win := MYaku.can_win(counts, player.melds.size())
			counts[k] -= 1
			if win:
				weights[k] *= 6.0

## —— 千里山女子高中 ——

class SkillRei:
	extends MSkill
	func _init() -> void:
		id = "rei"
		char_name = "园城寺怜"
		title = "未来视"
		desc = "被动:看穿之后 3 张牌墙牌;AI 强防守,规避放铳。"


class SkillRyuuka:
	extends MSkill
	func _init() -> void:
		id = "ryuuka"
		char_name = "清水谷龙华"
		title = "怜的加持(充能)"
		desc = "主动 ×2/局:发动后 5 巡内进张×4、听牌自摸×8,运气极高。"
		uses_per_round = 2
	func can_activate(t, player) -> bool:
		return uses_left > 0 and t.current_seat == player.seat \
			and t.phase == "await_discard" and player.charge_turns == 0

## —— 白糸台高校 ——

class SkillIzumi:
	extends MSkill
	func _init() -> void:
		id = "izumi"
		char_name = "二条泉"
		title = "安打流"
		desc = "被动:进张×2,AI 积极鸣牌,速攻低番听牌型。"
		passive_weight = true
	func modify_draw_weights(_t, player, weights: Array) -> void:
		if player.riichi:
			return
		var counts: Array[int] = player.concealed_counts()
		var base := MShanten.for_counts(counts, player.melds.size())
		for k in MTile.KIND_COUNT:
			if counts[k] >= 4:
				continue
			counts[k] += 1
			if MShanten.for_counts(counts, player.melds.size()) < base:
				weights[k] *= 2.0
			counts[k] -= 1


class SkillTeru:
	extends MSkill
	func _init() -> void:
		id = "teru"
		char_name = "宫永照"
		title = "照魔镜 / 连续升登"
		desc = "被动:看穿他家听牌(徽章标记);连续和牌每局 +2 翻,指数暴击。"


class SkillTakakura:
	extends MSkill
	func _init() -> void:
		id = "takakura"
		char_name = "涩谷尧深"
		title = "第一打回溯(收获季)"
		desc = "被动:牌山剩 8 张时,本局第一打弃牌自动回到手中,替换最无用的一张。"


class SkillYano:
	extends MSkill
	func _init() -> void:
		id = "yano"
		char_name = "亦野诚子"
		title = "三副露必定和牌"
		desc = "被动:完成 3 副露后进张×5、自摸×10;AI 积极鸣牌凑副露。"
		passive_weight = true
	func modify_draw_weights(_t, player, weights: Array) -> void:
		if player.melds.size() < 3:
			return
		var counts: Array[int] = player.concealed_counts()
		var base := MShanten.for_counts(counts, player.melds.size())
		for k in MTile.KIND_COUNT:
			if counts[k] >= 4:
				continue
			counts[k] += 1
			var st := MShanten.for_counts(counts, player.melds.size())
			counts[k] -= 1
			if st < base:
				weights[k] *= 5.0
			if st < 0:
				weights[k] *= 10.0


class SkillKokaji:
	extends MSkill
	func _init() -> void:
		id = "kokaji"
		char_name = "弘世菫"
		title = "精准射击"
		desc = "被动:立直后精准射击 —— 其他玩家摸牌向菫所听的牌倾斜,放铳率大增。"
