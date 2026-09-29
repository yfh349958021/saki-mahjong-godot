extends Control
## 表现层入口:全部 UI 用 Control.new() 等纯代码动态构建。
## 布局采用真实日麻对局(天凤/雀魂式)的四方桌:
##   自家在下、下家在右、对家在上、上家在左;
##   各家牌河 6 枚一行,立直宣言牌横置,副露贴在手边;
##   中央为宝牌指示/余牌数/巡目,行动按钮浮于自家手牌上方。
## 本文件只做三件事:构建界面、把用户输入翻译成 MTable 的 API 调用、
## 把逻辑层状态绘制出来。所有规则/概率都在 logic/ 里。

const TILE_W := 52.0
const TILE_H := 72.0
const MINI_W := 30.0
const MINI_H := 42.0
const BACK_TOP_W := 40.0
const BACK_TOP_H := 56.0
const BACK_SIDE_W := 54.0
const BACK_SIDE_H := 36.0

const CHARACTER_IDS: Array[String] = [
	"saki", "hisa", "koromo", "nodoka", "teru", "kuro", "ako", "ryuuka",
]
const WIND_CHARS: Array[String] = ["東", "南", "西", "北"]
const SEAT_POS: Array[String] = ["bottom", "right", "top", "left"]

var table: MTable
var _log_label: Label
var _action_box: Control
var _badges := {}
var _river_grids := {}
var _hand_box: HBoxContainer
var _meld_boxes := {}
var _wall_labels := {}
var _info_label: Label
var _hint_label: Label
var _overlay: Control
var _game_root: Control

var _picked_skill := "none"
var _mode := ""  # "" | "riichi" | "saki_pick" | "saki_delta"
var _saki_index := -1
var _tick := 0
var _autotest := false
var _shots := false


func _ready() -> void:
	_autotest = OS.get_cmdline_user_args().has("--autotest")
	_shots = OS.get_cmdline_user_args().has("--shots")
	_build_background()
	if _autotest:
		_picked_skill = "saki"
		_start_game()
	elif _shots:
		_picked_skill = "saki"
		_build_select_screen()  # 先截选人界面,再自动进入对局
	else:
		_build_select_screen()


# ———————————————————— 开局选人 ————————————————————

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.name = "BG"
	bg.color = Color("123524")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)


func _clear_ui() -> void:
	for c in get_children():
		if c.name != "BG":
			c.queue_free()
	_overlay = null
	_game_root = null


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


# ———————————————————— 对局界面:四方桌布局 ————————————————————

func _start_game() -> void:
	_clear_ui()
	_mode = ""
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
	_game_root = Control.new()
	_game_root.name = "GameUI"
	_game_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_root.set_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_game_root)

	# 牌桌面布(中央稍亮的圆角桌面)
	var felt := Panel.new()
	var felt_sb := _panel_style(Color("1e6244"), 60, 0)
	felt_sb.bg_color = Color("1e6244")
	felt.add_theme_stylebox_override("panel", felt_sb)
	felt.position = Vector2(90, 70)
	felt.size = Vector2(1100, 660)
	_game_root.add_child(felt)

	# 中央:宝牌指示 + 余牌 + 巡目
	var center := PanelContainer.new()
	var csb := _panel_style(Color("0f2e22cc"), 10, 10)
	center.add_theme_stylebox_override("panel", csb)
	center.position = Vector2(540, 330)
	center.size = Vector2(200, 120)
	_game_root.add_child(center)
	var cbox := VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 4)
	center.add_child(cbox)
	var dora_row := HBoxContainer.new()
	dora_row.add_theme_constant_override("separation", 3)
	dora_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cbox.add_child(dora_row)
	var dora_title := _make_label("Dr", 16, Color("ffd166"))
	dora_row.add_child(dora_title)
	var dora_slots := HBoxContainer.new()
	dora_slots.name = "DoraSlots"
	dora_slots.add_theme_constant_override("separation", 2)
	dora_row.add_child(dora_slots)
	_info_label = _make_label("", 12, Color("caf0f8"))
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cbox.add_child(_info_label)
	_hint_label = _make_label("", 13, Color("ffd166"))
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cbox.add_child(_hint_label)

	# 自家手牌 + 副露
	_hand_box = HBoxContainer.new()
	_hand_box.add_theme_constant_override("separation", 3)
	_game_root.add_child(_hand_box)
	_meld_boxes[0] = HBoxContainer.new()
	_meld_boxes[0].add_theme_constant_override("separation", 4)
	_game_root.add_child(_meld_boxes[0])

	# 行动面板(浮于手牌上方,靠右;绝对定位容器)
	_action_box = Control.new()
	_action_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_action_box.set_offsets_preset(Control.PRESET_FULL_RECT)
	_action_box.mouse_filter = Control.MOUSE_FILTER_PASS
	_game_root.add_child(_action_box)

	# 各家牌河(6 列)与牌墙/副露容器
	for seat in 4:
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 2)
		grid.add_theme_constant_override("v_separation", 1)
		_game_root.add_child(grid)
		_river_grids[seat] = grid
		if not _meld_boxes.has(seat):
			var mb := HBoxContainer.new()
			mb.add_theme_constant_override("separation", 3)
			_game_root.add_child(mb)
			_meld_boxes[seat] = mb
		var wl := Control.new()
		_game_root.add_child(wl)
		_wall_labels[seat] = wl

	_layout_seat(0)
	_layout_seat(1)
	_layout_seat(2)
	_layout_seat(3)

	# 座位徽章(风位/名字/分数/立直棒)
	for seat in 4:
		_badges[seat] = _build_badge(seat)

	# 日志(半透明小面板,左上角)
	var log_panel := PanelContainer.new()
	log_panel.add_theme_stylebox_override("panel", _panel_style(Color("0f2e2288"), 8, 8))
	log_panel.position = Vector2(295, 82)
	log_panel.size = Vector2(210, 130)
	_game_root.add_child(log_panel)
	_log_label = _make_label("", 10, Color("d8f3dcaa"))
	log_panel.add_child(_log_label)


## 摆放某一方位的牌河/牌墙/副露/手牌。
func _layout_seat(seat: int) -> void:
	match SEAT_POS[seat]:
		"bottom":
			_river_grids[seat].position = Vector2(700, 560)
			_meld_boxes[seat].position = Vector2(150, 716)
		"right":
			_river_grids[seat].position = Vector2(940, 300)
			_meld_boxes[seat].position = Vector2(1150, 430)
		"top":
			_river_grids[seat].position = Vector2(560, 150)
			_meld_boxes[seat].position = Vector2(920, 20)
		"left":
			_river_grids[seat].position = Vector2(190, 300)


## 座位徽章:风位 + 名字 + 分数 + 立直棒。
func _build_badge(seat: int) -> PanelContainer:
	var badge := PanelContainer.new()
	var sb := _panel_style(Color("0f2e22cc"), 8, 8)
	badge.add_theme_stylebox_override("panel", sb)
	badge.name = "Badge%d" % seat
	var v := VBoxContainer.new()
	v.name = "V"
	v.add_theme_constant_override("separation", 2)
	badge.add_child(v)
	var wind_row := HBoxContainer.new()
	wind_row.name = "WindRow"
	wind_row.add_theme_constant_override("separation", 6)
	v.add_child(wind_row)
	var wind_l := _make_label(WIND_CHARS[seat], 20, Color("ffd166"))
	wind_l.name = "Wind"
	wind_row.add_child(wind_l)
	var name_l := _make_label(table.players[seat].display_name, 13, Color("ffffff"))
	name_l.name = "PName"
	wind_row.add_child(name_l)
	var score_l := _make_label(str(table.players[seat].score), 15, Color("caf0f8"))
	score_l.name = "Score"
	v.add_child(score_l)
	var riichi_l := _make_label("◆ 立直", 11, Color("ff6b6b"))
	riichi_l.name = "Riichi"
	riichi_l.visible = false
	v.add_child(riichi_l)
	match SEAT_POS[seat]:
		"bottom":
			badge.position = Vector2(100, 700)
		"right":
			badge.position = Vector2(1140, 700)
		"top":
			badge.position = Vector2(1100, 78)
		"left":
			badge.position = Vector2(100, 78)
	_game_root.add_child(badge)
	return badge


## 立即从容器摘除并释放所有孩子(queue_free 是延迟的,child_count 会虚增)。
func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _on_table_event(text: String) -> void:
	if _log_label == null:
		return
	var lines := _log_label.text.split("\n")
	var keep := mini(lines.size(), 5)
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


## 截图模式:选人界面 → 自动对局,关键节点存 PNG,局终退出。
func _shots_step() -> void:
	_tick += 1
	if _tick == 5:
		await _save_shot("select")
		_on_pick_character("saki")
		return
	if table == null or table.phase == "idle":
		return
	if _tick == 50 or _tick == 110 or _tick == 260:
		await _save_shot("game_%d" % _tick)
	if _tick == 70:
		# 演示:让对家立直,验证牌河横置宣言牌与立直棒
		var rp := table.players[2]
		if rp.river.size() > 0:
			rp.riichi = true
			rp.riichi_discarded = true
			rp.discards_after_riichi = 1
	if _tick % 2 == 0:
		return  # 放慢一倍,便于观察与截图
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


## 截一张当前画面到 PNG(--shots 模式)。不 await,直接取上一帧纹理,
## 避免窗口被遮挡时 frame_post_draw 信号暂停导致挂起。
func _save_shot(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "/tmp/saki_%s.png" % tag
	img.save_png(path)
	print("[shots] saved ", path)


func _human_has_options() -> bool:
	if table == null:
		return false
	var o: Dictionary = table.human_options
	return o.get("ron", false) or o.get("pon", false) or o.get("kan", false) \
		or (o.get("chi", []) as Array).size() > 0

# ———————————————————— 状态刷新 ————————————————————

func _refresh() -> void:
	if table == null:
		return
	_refresh_badges()
	_refresh_center()
	_refresh_rivers()
	_refresh_hands()
	_refresh_melds()
	_refresh_buttons()
	if table.phase == "round_end":
		_show_result()


func _refresh_badges() -> void:
	for seat in 4:
		var p := table.players[seat]
		var badge: PanelContainer = _badges[seat]
		var sb: StyleBoxFlat = badge.get_theme_stylebox("panel")
		var is_turn: bool = table.current_seat == seat and table.phase != "round_end"
		sb.border_color = Color("ffd166") if is_turn else Color("ffffff22")
		sb.border_width_bottom = 2 if is_turn else 0
		(badge.get_node("V/WindRow/PName") as Label).text = p.display_name
		(badge.get_node("V/Score") as Label).text = "%d 点" % p.score
		(badge.get_node("V/Riichi") as Label).visible = p.riichi


func _refresh_center() -> void:
	var slots: HBoxContainer = _game_root.get_node("PanelContainer/DoraSlots") if _game_root.has_node("PanelContainer/DoraSlots") else _find_dora_slots()
	if slots == null:
		return
	_clear_children(slots)
	for kind in table.wall.dora_kinds():
		slots.add_child(_make_tile(kind * 4 + 1, false, true))
	var open := table.wall.dora_kinds().size()
	for i in range(open, 5):
		var back := ColorRect.new()
		back.color = Color("17402e")
		back.custom_minimum_size = Vector2(MINI_W * 0.66, MINI_H * 0.66)
		slots.add_child(back)
	_info_label.text = "巡目 %d · 余牌 %d" % [table.turn_count, table.wall.tiles_left()]


func _find_dora_slots() -> HBoxContainer:
	if _game_root == null:
		return null
	var stack: Array[Node] = [_game_root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n.name == "DoraSlots":
			return n as HBoxContainer
		for c in n.get_children():
			stack.append(c)
	return null


func _refresh_rivers() -> void:
	for seat in 4:
		var grid: GridContainer = _river_grids[seat]
		_clear_children(grid)
		for tile_id in table.players[seat].river:
			if _is_riichi_discard(seat, tile_id):
				grid.add_child(_make_rotated_tile(tile_id))
			else:
				grid.add_child(_make_tile(tile_id, false, true))


## 立直宣言牌(牌河中横置):立直后(含宣言牌)的第 1 张牌河牌。
func _is_riichi_discard(seat: int, tile_id: int) -> bool:
	var p := table.players[seat]
	if not p.riichi or p.discards_after_riichi == 0:
		return false
	return p.river.find(tile_id) == p.river.size() - p.discards_after_riichi


func _refresh_hands() -> void:
	# 自家:明牌
	_clear_children(_hand_box)
	var me := table.players[0]
	var hint := ""
	match _mode:
		"riichi":
			hint = "立直:点击要打出的宣言牌"
		"saki_pick":
			hint = "咲「+1/-1」:点击要改写的手牌"
		"saki_delta":
			hint = "咲「+1/-1」:选择 +1 或 -1"
		_:
			if table.phase == "await_discard" and table.current_seat == 0:
				hint = "轮到你:点击一张牌打出"
			elif table.phase == "await_peek":
				hint = "認識の改変:从墙顶 3 张中点选 1 张!"
			elif table.phase == "await_response" and _human_has_options():
				hint = "别家打牌:荣 / 碰 / 杠 / 吃?"
	_hint_label.text = hint
	for i in me.hand.size():
		_hand_box.add_child(_make_tile(me.hand[i], true, false, i))
	_layout_hand_row()

	# 其他三家:牌背 + 数量
	for seat in range(1, 4):
		var p := table.players[seat]
		var holder: Control = _wall_labels[seat]
		if holder == null or not is_instance_valid(holder):
			holder = Control.new()
			_game_root.add_child(holder)
			_wall_labels[seat] = holder
		_clear_children(holder)
		match SEAT_POS[seat]:
			"right":
				holder.position = Vector2(1206, 120)
			"top":
				holder.position = Vector2(388, 24)
			"left":
				holder.position = Vector2(30, 120)
		for i in p.hand.size():
			var back := _make_back(seat)
			back.position = _back_offset(seat, i)
			holder.add_child(back)


func _layout_hand_row() -> void:
	var n := _hand_box.get_child_count()
	var w := n * (TILE_W + 3)
	_hand_box.position = Vector2(640 - w / 2.0 + 40, 714)


func _back_offset(seat: int, index: int) -> Vector2:
	match SEAT_POS[seat]:
		"right":
			return Vector2(0, index * (BACK_SIDE_H + 2))
		"top":
			return Vector2(index * (BACK_TOP_W + 2), 0)
		_:
			return Vector2(0, index * (BACK_SIDE_H + 2))


func _refresh_buttons() -> void:
	_clear_children(_action_box)
	var rows := HBoxContainer.new()
	rows.alignment = BoxContainer.ALIGNMENT_END
	rows.add_theme_constant_override("separation", 6)
	_action_box.add_child(rows)
	if table.phase == "round_end":
		var again := Button.new()
		again.text = "再来一局(重新发牌)"
		again.custom_minimum_size = Vector2(0, 36)
		again.pressed.connect(_on_restart)
		rows.add_child(again)
		return
	if table.phase == "await_peek":
		for i in table.peek_options.size():
			var b := Button.new()
			b.text = "取 %s" % MTile.label_id(table.peek_options[i])
			b.custom_minimum_size = Vector2(0, 40)
			b.pressed.connect(_on_pick_peek.bind(i))
			rows.add_child(b)
		return
	if _human_has_options():
		var o: Dictionary = table.human_options
		if o.get("ron", false):
			rows.add_child(_make_action_button("荣", _on_human_ron, Color("c1121f")))
		if o.get("pon", false):
			rows.add_child(_make_action_button("碰", _on_human_pon, Color("2a6f97")))
		if o.get("kan", false):
			rows.add_child(_make_action_button("杠", _on_human_kan, Color("2a6f97")))
		var combos: Array = o.get("chi", [])
		for ci in combos.size():
			var combo: Dictionary = combos[ci]
			rows.add_child(_make_action_button("吃 %s" % _chi_label(combo, table.last_discard.kind), _on_human_chi.bind(ci), Color("2a6f97")))
		rows.add_child(_make_action_button("跳过", _on_human_decline, Color("495057")))
		return
	var me := table.players[0]
	if not (table.phase == "await_discard" and table.current_seat == 0):
		return
	if _mode == "saki_delta":
		rows.add_child(_make_action_button("+1", _on_saki_plus, Color("b5179e")))
		rows.add_child(_make_action_button("-1", _on_saki_minus, Color("b5179e")))
		rows.add_child(_make_action_button("取消", _on_cancel_mode, Color("495057")))
		return
	if me.skill.id == "saki" and me.skill.uses_left > 0:
		rows.add_child(_make_action_button("咲「+1/-1」×%d" % me.skill.uses_left, _on_mode_saki, Color("b5179e")))
	if me.skill.id == "hisa" and me.skill.uses_left > 0 and me.pending_peek == 0:
		rows.add_child(_make_action_button("久「改変」×%d" % me.skill.uses_left, _on_mode_hisa, Color("b5179e")))
	if me.skill.id == "ryuuka" and me.skill.uses_left > 0 and me.just_drawn >= 0:
		rows.add_child(_make_action_button("龙华「雨」×%d" % me.skill.uses_left, _on_human_mulligan, Color("b5179e")))
	if me.skill.id == "ako" and me.skill.uses_left > 0:
		rows.add_child(_make_action_button("憧「背中」", _on_human_ako, Color("b5179e")))
	if not me.riichi and me.is_menzen():
		rows.add_child(_make_action_button("立直", _on_mode_riichi, Color("c1121f")))
	if _mode == "riichi":
		rows.add_child(_make_action_button("取消", _on_cancel_mode, Color("495057")))
	var pon_kinds := {}
	for m in me.melds:
		if m.type == "pon":
			pon_kinds[m.kind] = true
	for i in me.hand.size():
		var k2 := MTile.kind_of(me.hand[i])
		if pon_kinds.has(k2):
			rows.add_child(_make_action_button("加杠 %s" % MTile.label(k2), _on_human_kakan.bind(i), Color("2a6f97")))
			break
	for i in me.hand.size():
		var kind := MTile.kind_of(me.hand[i])
		var n := 0
		for tid in me.hand:
			if MTile.kind_of(tid) == kind:
				n += 1
		if n == 4:
			rows.add_child(_make_action_button("暗杠 %s" % MTile.label(kind), _on_human_ankan.bind(i), Color("2a6f97")))
			break
	if _can_tsumo():
		rows.add_child(_make_action_button("自摸!", _on_human_tsumo, Color("c1121f")))
	# 浮动面板定位:手牌上方右侧
	var min_size := rows.get_combined_minimum_size()
	rows.position = Vector2(1020 - min_size.x, 700 - min_size.y - 8)

	_refresh_melds()


func _meld_tile_ids(m: Dictionary) -> Array[int]:
	var out: Array[int] = []
	match m.type:
		"chi":
			for k in [m.kind, m.kind + 1, m.kind + 2]:
				out.append(k * 4 + 1)
		"kan_open", "kan_closed", "kan_added":
			for j in 4:
				out.append(m.kind * 4 + 1)
		_:
			for j in 3:
				out.append(m.kind * 4 + 1)
	return out


func _layout_melds() -> void:
	for seat in 4:
		var mb: HBoxContainer = _meld_boxes[seat]
		var n := mb.get_child_count()
		match SEAT_POS[seat]:
			"bottom":
				mb.position = Vector2(120, 716)
			"right":
				mb.position = Vector2(924, 620)
			"top":
				mb.position = Vector2(952, 26)
			"left":
				mb.position = Vector2(100, 620)


func _refresh_melds() -> void:
	var me := table.players[0]
	var meld_box: HBoxContainer = _meld_boxes[0]
	_clear_children(meld_box)
	for m in me.melds:
		for tile_id in _meld_tile_ids(m):
			meld_box.add_child(_make_tile(tile_id, false, true))
	for seat in range(1, 4):
		var mb: HBoxContainer = _meld_boxes[seat]
		_clear_children(mb)
		for m in table.players[seat].melds:
			for tile_id in _meld_tile_ids(m):
				mb.add_child(_make_tile(tile_id, false, true))
	_layout_melds()


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
	overlay.color = Color(0, 0, 0, 0.6)
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
	var title := ""
	if res.get("type", "") == "win":
		var w := table.players[res.winner]
		var winners_txt := ""
		if res.has("winners") and (res.winners as Array).size() > 1:
			var names: Array[String] = []
			for ws in res.winners:
				names.append(table.players[ws].display_name)
			winners_txt = "(双响:%s)" % " & ".join(names)
		title = "%s %s!%s" % [w.display_name, "自摸" if res.tsumo else "荣和", winners_txt]
		box.add_child(_make_label(title, 30, Color("ffd166")))
		box.add_child(_make_label("%s —— %d 翻 %d 符" % [", ".join(res.yaku), res.han, res.fu], 18, Color("ffffff")))
	else:
		box.add_child(_make_label("荒牌流局", 30, Color("caf0f8")))
	# 点数表:风位 | 名字 | 分数 | 增减
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for head in ["风位", "玩家", "分数", "增减"]:
		grid.add_child(_make_label(head, 14, Color("95d5b2")))
	for p in table.players:
		var d: int = res.payments.get(p.seat, 0) if res.has("payments") else 0
		grid.add_child(_make_label(WIND_CHARS[p.seat], 15, Color("ffd166")))
		grid.add_child(_make_label(p.display_name, 15, Color("ffffff")))
		grid.add_child(_make_label(str(p.score), 15, Color("caf0f8")))
		grid.add_child(_make_label("%+d" % d, 15, Color("ff6b6b") if d < 0 else Color("95d5b2")))
	var btn := Button.new()
	btn.text = "再来一局"
	btn.custom_minimum_size = Vector2(0, 40)
	btn.pressed.connect(_on_restart)
	box.add_child(btn)

# ———————————————————— 截图模式步骤 ————————————————————

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


func _make_action_button(text: String, action: Callable, accent: Color = Color("2d6a4f")) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 42)
	var sb := _panel_style(accent, 8, 8)
	b.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate()
	sbh.bg_color = sb.bg_color.lightened(0.15)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbh)
	b.add_theme_color_override("font_color", Color("ffffff"))
	b.add_theme_font_size_override("font_size", 16)
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


## 麻将牌(正面):白底圆角 + 数字/花色文字;红宝牌着红。clickable 包 Button。
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
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.border_color = Color("b8b2a0")
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


## 牌背(对手手牌):深绿底 + 浅色脊线。侧位玩家横躺(宽>高),对家竖立。
func _make_back(seat: int) -> Control:
	var back := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("2e6b5f")
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.border_color = Color("12332e")
	for side in ["border_width_bottom", "border_width_top", "border_width_left", "border_width_right"]:
		sb.set(side, 1)
	back.add_theme_stylebox_override("panel", sb)
	var line := ColorRect.new()
	line.color = Color("49897c")
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(line)
	if SEAT_POS[seat] == "top":
		back.custom_minimum_size = Vector2(BACK_TOP_W, BACK_TOP_H)
		line.position = Vector2(2, BACK_TOP_H / 2 - 1)
		line.size = Vector2(BACK_TOP_W - 4, 2)
	else:
		back.custom_minimum_size = Vector2(BACK_SIDE_W, BACK_SIDE_H)
		line.position = Vector2(BACK_SIDE_W / 2 - 1, 2)
		line.size = Vector2(2, BACK_SIDE_H - 4)
	return back


## 立直宣言牌:横置 90°。
func _make_rotated_tile(tile_id: int) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(MINI_H, MINI_W)
	slot.size = Vector2(MINI_H, MINI_W)
	var tile := _make_tile(tile_id, false, true)
	tile.position = Vector2((MINI_H - MINI_W) / 2.0, (MINI_W - MINI_H) / 2.0)
	tile.rotation = PI / 2.0
	tile.pivot_offset = Vector2(MINI_W / 2.0, MINI_H / 2.0)
	slot.add_child(tile)
	return slot
