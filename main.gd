extends Control
## 表现层入口:全部 UI 用 Control.new() 等纯代码动态构建,
## 不包含任何编辑器拖拽的场景元素(scenes/main.tscn 只是一个空壳 root)。
## 本文件只做三件事:构建界面、把用户输入翻译成 MTable 的 API 调用、
## 把逻辑层状态绘制出来。所有规则/概率都在 logic/ 里。

const TILE_W := 52.0
const TILE_H := 72.0
const MINI_W := 26.0
const MINI_H := 36.0

const CHARACTER_IDS: Array[String] = [
	"saki", "hisa", "koromo", "nodoka", "teru", "kuro", "ako", "ryuuka",
]

var table: MTable
var _log_label: Label
var _hand_box: HBoxContainer
var _buttons_box: HBoxContainer
var _opp_box: HBoxContainer
var _river_box: HBoxContainer
var _info_label: Label
var _hint_label: Label
var _overlay: Control
var _root_box: VBoxContainer

var _picked_skill := "none"
var _mode := ""  # "" | "riichi" | "saki_pick" | "saki_delta"
var _saki_index := -1
var _tick := 0
var _autotest := false
var _shots := false


## 截一张当前画面到 PNG(--shots 模式)。不 await,直接取上一帧纹理,
## 避免窗口被遮挡时 frame_post_draw 信号暂停导致挂起。
func _save_shot(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "/tmp/saki_%s.png" % tag
	img.save_png(path)
	print("[shots] saved ", path)


func _ready() -> void:
	_autotest = OS.get_cmdline_user_args().has("--autotest")
	_shots = OS.get_cmdline_user_args().has("--shots")
	_build_background()
	if _autotest or _shots:
		_picked_skill = "saki"
		if _shots:
			_build_select_screen()  # 先截选人界面,再自动进入对局
		else:
			_start_game()
	else:
		_build_select_screen()


# ———————————————————— 开局选人 ————————————————————

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.name = "BG"
	bg.color = Color("1b4332")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)


func _clear_ui() -> void:
	for c in get_children():
		if c.name != "BG":
			c.queue_free()
	_overlay = null
	_root_box = null


func _build_select_screen() -> void:
	_clear_ui()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color("0f2e22ee"), 16, 28))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(_make_label("天才麻将少女 · 技能麻将", 30, Color("ffd166")))
	box.add_child(_make_label("选择你的角色(AI 将使用其余角色)", 15, Color("caf0f8")))

	var chars := GridContainer.new()
	chars.columns = 3
	chars.add_theme_constant_override("h_separation", 10)
	chars.add_theme_constant_override("v_separation", 10)
	box.add_child(chars)
	for cid in CHARACTER_IDS:
		chars.add_child(_make_char_card(MSkills.create(cid), cid))
	chars.add_child(_make_char_card(MSkill.new(), "none"))
	box.add_child(_make_label("抽牌概率由技能改写:咲的 ±1 改写、久的墙顶挑选、衣的河牌流向、和/照的精确制导、玄的聚宝、憧的背中感知、龙华的雨", 12, Color("95d5b2")))


func _on_pick_character(cid: String) -> void:
	_picked_skill = cid
	_start_game()


# ———————————————————— 对局界面(纯代码动态构建) ————————————————————

func _start_game() -> void:
	_clear_ui()
	_mode = ""
	# 人类选中的技能放座位 0,其余三个角色分给 AI
	var ids: Array[String] = [_picked_skill, "none", "none", "none"]
	var others := CHARACTER_IDS.duplicate()
	others.erase(_picked_skill)
	others.shuffle()
	for i in 3:
		ids[i + 1] = others[i]
	var seed_value := int(Time.get_unix_time_from_system()) % 1000000

	table = MTable.new()
	table.setup(ids, 0, seed_value)
	table.event_added.connect(_on_table_event)
	table.start_round(seed_value)
	_build_game_ui()
	_refresh()


func _build_game_ui() -> void:
	_root_box = VBoxContainer.new()
	_root_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_box.set_offsets_preset(Control.PRESET_FULL_RECT)
	_root_box.add_theme_constant_override("separation", 4)
	var margin := MarginContainer.new()
	margin.name = "GameUI"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.set_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)
	margin.add_child(_root_box)

	# 顶部:三家对手
	_opp_box = HBoxContainer.new()
	_opp_box.add_theme_constant_override("separation", 10)
	_opp_box.custom_minimum_size = Vector2(0, 120)
	_root_box.add_child(_opp_box)

	# 中部:信息 + 牌河 + 提示 + 日志
	var center := VBoxContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 4)
	_root_box.add_child(center)
	_info_label = _make_label("", 14, Color("caf0f8"))
	center.add_child(_info_label)
	_river_box = HBoxContainer.new()
	_river_box.add_theme_constant_override("separation", 14)
	center.add_child(_river_box)
	_hint_label = _make_label("", 15, Color("ffd166"))
	center.add_child(_hint_label)
	_log_label = _make_label("", 13, Color("d8f3dc"))
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	center.add_child(_log_label)

	# 底部:操作按钮 + 手牌
	_buttons_box = HBoxContainer.new()
	_buttons_box.add_theme_constant_override("separation", 8)
	_buttons_box.custom_minimum_size = Vector2(0, 42)
	_root_box.add_child(_buttons_box)
	_hand_box = HBoxContainer.new()
	_hand_box.add_theme_constant_override("separation", 4)
	_hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_box.custom_minimum_size = Vector2(0, TILE_H + 10)
	_root_box.add_child(_hand_box)


func _on_table_event(text: String) -> void:
	if _log_label == null:
		return
	var lines := _log_label.text.split("\n")
	var keep := mini(lines.size(), 7)
	var arr: Array[String] = []
	for i in range(lines.size() - keep, lines.size()):
		arr.append(lines[i])
	arr.append(text)
	_log_label.text = "\n".join(arr)

# ———————————————————— 主循环节奏 ————————————————————

func _process(_delta: float) -> void:
	if _shots:
		_shots_step()
		return
	if table == null or table.phase == "idle":
		return
	if _autotest:
		_autotest_step()
		return
	if table.phase == "round_end":
		return
	_tick += 1
	if _tick % 18 != 0:  # 约 0.3 秒推进一步
		return
	# 人类决策点:不打断,等 UI 输入
	if table.phase == "await_discard" and table.current_seat == 0:
		return
	if table.phase == "await_peek":
		return
	if table.phase == "await_response" and _human_has_options():
		return
	table.advance_one_step()
	_refresh()


## 截图模式:选人界面 → 自动对局,关键节点存 PNG,局终退出。
func _shots_step() -> void:
	_tick += 1
	if _tick == 5:
		await _save_shot("select")
		_on_pick_character("saki")
		return
	if table == null or table.phase == "idle":
		return
	if _tick == 40 or _tick == 150 or _tick == 400:
		await _save_shot("game_%d" % _tick)
	if table.phase == "round_end":
		await _save_shot("result")
		print("[shots] 局终 result=%s" % table.result.get("type", "?"))
		get_tree().quit(0)
		return
	if _tick > 60000:
		printerr("[shots] 卡死保护触发")
		get_tree().quit(1)
		return
	_autotest_play()


## 自动出牌(AI 代打人类座位),autotest 与 shots 共用。
func _autotest_play() -> void:
	if table.phase == "await_discard" and table.current_seat == 0:
		var me := table.players[0]
		if _can_tsumo():
			table.human_tsumo()
		else:
			if me.skill.id == "ryuuka" and me.skill.uses_left > 0 and MAI.mulligan_worth(table, me):
				table.human_use_mulligan()
			if me.skill.id == "ako" and me.skill.uses_left > 0:
				table.human_use_ako()
			if me.skill.id == "hisa" and me.skill.uses_left > 0 and me.pending_peek == 0 and table.turn_count < 6:
				table.human_use_hisa()
			if not table.human_discard(MAI.choose_discard(table, me)):
				table.human_discard(me.hand.size() - 1)
	elif table.phase == "await_peek":
		table.human_choose_peek(MAI.choose_peek(table, table.players[0], table.peek_options))
	elif table.phase == "await_response" and _human_has_options():
		table.human_decline()
	table.advance_one_step()
	_refresh()


## 无头自测:自动打完一整局,结束即退出(供 CI / smoke test)。
func _autotest_step() -> void:
	if table.phase == "round_end":
		var summary: Array[String] = []
		for p in table.players:
			summary.append("%s:%d" % [p.display_name, p.score])
		print("[autotest] 局终 result=%s 分数 %s" % [table.result.get("type", "?"), " ".join(summary)])
		get_tree().quit(0)
		return
	if _tick > 60000:
		printerr("[autotest] 卡死保护触发")
		get_tree().quit(1)
		return
	_tick += 1
	_autotest_play()


func _human_has_options() -> bool:
	if table == null:
		return false
	var o: Dictionary = table.human_options
	return o.get("ron", false) or o.get("pon", false) or o.get("kan", false) \
		or (o.get("chi", []) as Array).size() > 0


# ———————————————————— 状态刷新(重绘动态区) ————————————————————

func _refresh() -> void:
	if table == null:
		return
	_refresh_opponents()
	_refresh_info()
	_refresh_rivers()
	_refresh_hand()
	_refresh_buttons()
	if table.phase == "round_end":
		_show_result()


func _refresh_opponents() -> void:
	for c in _opp_box.get_children():
		c.queue_free()
	for i in range(1, 4):
		var p := table.players[i]
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := _panel_style(Color("1d3a2f"), 8, 8)
		if table.current_seat == i and table.phase != "round_end":
			sb.border_color = Color("ffd166")
			sb.border_width_bottom = 2
		panel.add_theme_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		panel.add_child(v)
		var head := "%s(%s)  %d点" % [p.display_name, "立直!" if p.riichi else "AI", p.score]
		v.add_child(_make_label(head, 14, Color("ffd166") if p.riichi else Color("ffffff")))
		var skill_state := "被动" if p.skill.passive_weight else ("剩 %d 次" % p.skill.uses_left)
		v.add_child(_make_label("「%s」%s" % [p.skill.title, skill_state], 12, Color("b7e4c7")))
		v.add_child(_make_label("手牌 %d 张" % p.hand.size(), 12, Color("caf0f8")))
		_opp_box.add_child(panel)


func _refresh_info() -> void:
	var doras: Array[String] = []
	for k in table.wall.dora_kinds():
		doras.append(MTile.label(k))
	_info_label.text = "宝牌指示:%s   |   牌山剩余 %d 张   |   第 %d 巡   |   你的得分:%d" % [
		" ".join(doras) if doras.size() > 0 else "无",
		table.wall.tiles_left(), table.turn_count, table.players[0].score,
	]


func _refresh_rivers() -> void:
	for c in _river_box.get_children():
		c.queue_free()
	for i in 4:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		v.add_child(_make_label("%s" % table.players[i].display_name, 11, Color("95d5b2")))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 2)
		flow.add_theme_constant_override("v_separation", 2)
		flow.custom_minimum_size = Vector2(292, MINI_H * 2 + 10)
		for tile_id in table.players[i].river:
			flow.add_child(_make_tile(tile_id, false, true))
		v.add_child(flow)
		_river_box.add_child(v)


func _refresh_hand() -> void:
	for c in _hand_box.get_children():
		c.queue_free()
	var me := table.players[0]
	for i in me.hand.size():
		_hand_box.add_child(_make_tile(me.hand[i], true, false, i))
	var hint := ""
	match _mode:
		"riichi":
			hint = "立直:点击要打出的宣言牌(须保持听牌)"
		"saki_pick":
			hint = "咲「+1/-1」:点击要改写的手牌"
		"saki_delta":
			hint = "咲「+1/-1」:在下方选择 +1 或 -1"
		_:
			if table.phase == "await_discard" and table.current_seat == 0:
				hint = "轮到你:点击一张牌打出"
			elif table.phase == "await_peek":
				hint = "認識の改変:从墙顶 3 张中点选 1 张!"
			elif table.phase == "await_response" and _human_has_options():
				hint = "别家打牌:荣和 / 碰 / 杠 / 跳过?"
	_hint_label.text = hint


func _refresh_buttons() -> void:
	for c in _buttons_box.get_children():
		c.queue_free()
	if table.phase == "round_end":
		var again := Button.new()
		again.text = "再来一局(重新发牌)"
		again.custom_minimum_size = Vector2(0, 36)
		again.pressed.connect(_on_restart)
		_buttons_box.add_child(again)
		return
	if table.phase == "await_peek":
		for i in table.peek_options.size():
			var b := Button.new()
			b.text = "取 %s" % MTile.label_id(table.peek_options[i])
			b.custom_minimum_size = Vector2(0, 36)
			b.pressed.connect(_on_pick_peek.bind(i))
			_buttons_box.add_child(b)
		return
	if _human_has_options():
		var o: Dictionary = table.human_options
		if o.get("ron", false):
			_buttons_box.add_child(_make_action_button("荣和!", _on_human_ron))
		if o.get("pon", false):
			_buttons_box.add_child(_make_action_button("碰", _on_human_pon))
		if o.get("kan", false):
			_buttons_box.add_child(_make_action_button("杠", _on_human_kan))
		var combos: Array = o.get("chi", [])
		for ci in combos.size():
			var combo: Dictionary = combos[ci]
			_buttons_box.add_child(_make_action_button("吃 %s" % _chi_label(combo, table.last_discard.kind), _on_human_chi.bind(ci)))
		_buttons_box.add_child(_make_action_button("跳过", _on_human_decline))
		return
	var me := table.players[0]
	if not (table.phase == "await_discard" and table.current_seat == 0):
		return
	if _mode == "saki_delta":
		_buttons_box.add_child(_make_action_button("+1", _on_saki_plus))
		_buttons_box.add_child(_make_action_button("-1", _on_saki_minus))
		_buttons_box.add_child(_make_action_button("取消", _on_cancel_mode))
		return
	if me.skill.id == "saki" and me.skill.uses_left > 0:
		_buttons_box.add_child(_make_action_button("咲「+1/-1」×%d" % me.skill.uses_left, _on_mode_saki))
	if me.skill.id == "hisa" and me.skill.uses_left > 0 and me.pending_peek == 0:
		_buttons_box.add_child(_make_action_button("久「認識の改変」×%d" % me.skill.uses_left, _on_mode_hisa))
	if me.skill.id == "ryuuka" and me.skill.uses_left > 0 and me.just_drawn >= 0:
		_buttons_box.add_child(_make_action_button("龙华「恵みの雨」×%d" % me.skill.uses_left, _on_human_mulligan))
	if me.skill.id == "ako" and me.skill.uses_left > 0:
		_buttons_box.add_child(_make_action_button("憧「牌の背中」", _on_human_ako))
	if not me.riichi and me.is_menzen():
		_buttons_box.add_child(_make_action_button("立直", _on_mode_riichi))
	if _mode == "riichi":
		_buttons_box.add_child(_make_action_button("取消立直", _on_cancel_mode))
	# 加杠:明碰 + 手中第 4 张
	var pon_kinds := {}
	for m in me.melds:
		if m.type == "pon":
			pon_kinds[m.kind] = true
	for i in me.hand.size():
		var k2 := MTile.kind_of(me.hand[i])
		if pon_kinds.has(k2):
			_buttons_box.add_child(_make_action_button("加杠 %s" % MTile.label(k2), _on_human_kakan.bind(i)))
			break
	for i in me.hand.size():
		var kind := MTile.kind_of(me.hand[i])
		var n := 0
		for tid in me.hand:
			if MTile.kind_of(tid) == kind:
				n += 1
		if n == 4:
			_buttons_box.add_child(_make_action_button("暗杠 %s" % MTile.label(kind), _on_human_ankan.bind(i)))
			break
	if _can_tsumo():
		_buttons_box.add_child(_make_action_button("自摸!", _on_human_tsumo))


func _chi_label(combo: Dictionary, called_kind: int) -> String:
	var parts: Array[String] = []
	for k in [combo.low, combo.low + 1, combo.low + 2]:
		parts.append(MTile.label(k) if k != called_kind else "[%s]" % MTile.label(k))
	return "".join(parts)


func _can_tsumo() -> bool:
	var me := table.players[0]
	return table.phase == "await_discard" and table.current_seat == 0 \
		and MYaku.evaluate(me.hand, me.melds, {
			"tsumo": true, "riichi": me.riichi, "rinshan": me.rinshan_flag,
			"seat_wind": MTile.EAST, "round_wind": MTile.EAST,
			"dora_kinds": table.wall.dora_kinds(), "dealer_seat": table.dealer_seat,
			"win_seat": 0,
		}).win

# ———————————————————— 输入处理 ————————————————————

func _on_tile_clicked(index: int) -> void:
	if table.phase != "await_discard" or table.current_seat != 0:
		return
	match _mode:
		"saki_pick":
			_saki_index = index
			_mode = "saki_delta"
		"riichi":
			if table.human_riichi(index):
				_mode = ""
		_:
			table.human_discard(index)
	_refresh()


func _on_mode_saki() -> void:
	_mode = "saki_pick"
	_refresh()


func _on_mode_hisa() -> void:
	table.human_use_hisa()
	_refresh()


func _on_mode_riichi() -> void:
	_mode = "riichi"
	_refresh()


func _on_cancel_mode() -> void:
	_mode = ""
	_refresh()


func _on_saki_plus() -> void:
	table.human_use_saki(_saki_index, 1)
	_mode = ""
	_refresh()


func _on_saki_minus() -> void:
	table.human_use_saki(_saki_index, -1)
	_mode = ""
	_refresh()


func _on_pick_peek(index: int) -> void:
	table.human_choose_peek(index)
	_refresh()


func _on_human_ron() -> void:
	table.human_ron()
	_mode = ""
	_refresh()


func _on_human_pon() -> void:
	table.human_pon()
	_refresh()


func _on_human_kan() -> void:
	table.human_kan()
	_refresh()


func _on_human_chi(combo_index: int) -> void:
	table.human_chi(combo_index)
	_refresh()


func _on_human_kakan(hand_index: int) -> void:
	table.human_kakan(hand_index)
	_refresh()


func _on_human_mulligan() -> void:
	table.human_use_mulligan()
	_refresh()


func _on_human_ako() -> void:
	table.human_use_ako()
	_refresh()


func _on_human_decline() -> void:
	table.human_decline()
	_refresh()


func _on_human_tsumo() -> void:
	table.human_tsumo()
	_refresh()


func _on_human_ankan(index: int) -> void:
	table.human_ankan(index)
	_refresh()


func _on_restart() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null
	_start_game()

# ———————————————————— 结算浮层 ————————————————————

func _show_result() -> void:
	if _overlay:
		return
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.set_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	_overlay = overlay
	var res: Dictionary = table.result
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 10)
	overlay.add_child(box)
	if res.get("type", "") == "win":
		var w := table.players[res.winner]
		var winners_txt := ""
		if res.has("winners") and (res.winners as Array).size() > 1:
			var names: Array[String] = []
			for ws in res.winners:
				names.append(table.players[ws].display_name)
			winners_txt = "(双响:%s)" % " & ".join(names)
		box.add_child(_make_label("%s %s!%s" % [w.display_name, "自摸" if res.tsumo else "荣和", winners_txt], 30, Color("ffd166")))
		box.add_child(_make_label("%s —— %d 翻 %d 符" % [", ".join(res.yaku), res.han, res.fu], 20, Color("ffffff")))
	else:
		box.add_child(_make_label("荒牌流局", 32, Color("caf0f8")))
		if res.has("tenpai"):
			var lines: Array[String] = []
			for p in table.players:
				var d: int = res.payments.get(p.seat, 0)
				lines.append("%s  %s(%+d)" % [p.display_name, "听牌" if res.tenpai[p.seat] else "不听", d])
			box.add_child(_make_label("\n".join(lines), 16, Color("caf0f8")))
	var scores := ""
	for p in table.players:
		var d: int = res.payments.get(p.seat, 0) if res.has("payments") else 0
		scores += "%s:%d(%s%d)   " % [p.display_name, p.score, "+" if d >= 0 else "", d]
	box.add_child(_make_label(scores, 16, Color("caf0f8")))
	var btn := Button.new()
	btn.text = "再来一局"
	btn.custom_minimum_size = Vector2(0, 40)
	btn.pressed.connect(_on_restart)
	box.add_child(btn)

# ———————————————————— 控件工厂 ————————————————————

func _panel_style(bg: Color, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.8
	sb.content_margin_bottom = margin * 0.8
	return sb


func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _make_action_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 36)
	b.pressed.connect(action)
	return b


func _make_char_card(sk: MSkill, cid: String) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(190, 150)
	var sb := _panel_style(Color("1d3a2f"), 10, 8)
	btn.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate()
	sbh.bg_color = Color("2d6a4f")
	btn.add_theme_stylebox_override("hover", sbh)
	btn.add_theme_stylebox_override("pressed", sbh)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.set_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_l := _make_label(sk.char_name, 20, Color("ffffff"))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_l := _make_label("「%s」" % sk.title, 14, Color("ffd166"))
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var desc_l := _make_label(sk.desc, 11, Color("b7e4c7"))
	desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_l.custom_minimum_size = Vector2(170, 76)
	desc_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_l)
	v.add_child(title_l)
	v.add_child(desc_l)
	btn.add_child(v)
	btn.pressed.connect(_on_pick_character.bind(cid))
	return btn


## 麻将牌视觉:白底圆角 Panel + 数字/花色文字;红宝牌着红。
## clickable 时包一层 Button,点击带回手牌下标。
func _make_tile(tile_id: int, clickable: bool, mini: bool = false, hand_index: int = -1) -> Control:
	var kind := MTile.kind_of(tile_id)
	var red := MTile.is_red(tile_id)
	var w := MINI_W if mini else TILE_W
	var h := MINI_H if mini else TILE_H
	var main_font := 13 if mini else 18

	var holder: Control
	if clickable:
		holder = Button.new()
		(holder as Button).pressed.connect(_on_tile_clicked.bind(hand_index))
	else:
		holder = Panel.new()
	holder.custom_minimum_size = Vector2(w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("fff0f0") if red else Color("fffdf5")
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	sb.border_color = Color("c8c2b0")
	for side in ["border_width_bottom", "border_width_top", "border_width_left", "border_width_right"]:
		sb.set(side, 1)
	if clickable:
		(holder as Button).add_theme_stylebox_override("normal", sb)
		var sbh := sb.duplicate()
		sbh.bg_color = Color("ffe8a3")
		(holder as Button).add_theme_stylebox_override("hover", sbh)
		(holder as Button).add_theme_stylebox_override("pressed", sbh)
	else:
		(holder as Panel).add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.set_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.add_child(v)
	var color := Color("d00000") if red else Color("212529")
	var top := _make_label(MTile.label(kind), main_font, color)
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	return holder
