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
const DRAWN_GAP := 20.0   # 摸牌与手牌的间隔

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
var _hand_box: Control
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

# 贴图 / 音频 / 设置
const RES_PRESETS := [[1280, 800], [1600, 1000], [1920, 1200], [2560, 1600], [3200, 2000], [3840, 2400]]
const RES_NAMES := ["1280×800", "1600×1000", "1920×1200", "2560×1600", "3200×2000", "3840×2400(4K)"]
const SETTINGS_PATH := "user://settings.cfg"
var _tile_tex_cache := {}
var _river_nodes_by_kind := {}   # kind -> Array[Control](自家牌河,悬停高亮用)
var _display_map: Array[int] = []  # 显示位置 -> 手牌实际下标
var _hover_kind := -1
var _selected_hand_idx := -1      # 点选浮起的手牌(实际下标)
var _drawn_gap := false           # 本次刷新:摸牌前是否有间隔
var _last_seen_drawn := -1        # 上次刷新时的摸牌 id(变化时清除点选)
var _press := {}                  # 手牌按住状态 {index,pos,moved,time,detached}
var _hand_gesture_active := false # 一次按放手势进行中(防多张连续拖出)
var _cfg_click_mode := 1          # 打牌方式:0 单击打出 / 1 双击打出
var _drag_control: Control        # 拖动中的牌控件(已从手牌行摘出)
var _drag_slot := -1              # 摘出前的显示槽位(松手还原用)
var _skill_popup: PanelContainer
var _settings_layer: CanvasLayer
var _settings_panel: PanelContainer
var _table_bg: TextureRect
var _bgm_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer
var _sfx_streams: Array[AudioStream] = []
var _cfg_res_idx := 0
var _cfg_bgm := 50
var _cfg_sfx := 70
var _cfg_bg_path := ""

# 联机
var net: MNet
var _screen := "menu"   # menu | select | room | game
const CHAR_THEME := {"saki": "d1495b", "hisa": "33658a", "koromo": "7768ae", "nodoka": "d8a31a",
	"teru": "8e3b8e", "kuro": "2a6f97", "ako": "2a9d8f", "ryuuka": "4c956c", "none": "6c757d"}
const CHAR_KANJI := {"saki": "咲", "hisa": "久", "koromo": "衣", "nodoka": "和",
	"teru": "照", "kuro": "玄", "ako": "憧", "ryuuka": "華", "none": "素"}


func _ready() -> void:
	_autotest = OS.get_cmdline_user_args().has("--autotest")
	_shots = OS.get_cmdline_user_args().has("--shots")
	_load_settings()
	net = MNet.new()
	net.name = "Net"
	add_child(net)
	net.lobby_changed.connect(_on_net_lobby)
	net.game_started.connect(_on_net_game_started)
	net.snapshot_received.connect(_on_net_snapshot)
	net.joined_ok.connect(func():
		_build_room()
		_refresh_room())
	net.join_failed.connect(func(reason): 
		_build_main_menu()
		_menu_error(reason))
	net.back_to_lobby.connect(func(): _build_room())
	_build_background()
	_build_table_bg()
	_setup_audio()
	_build_settings_ui()
	if _cfg_res_idx > 0:
		_apply_resolution(_cfg_res_idx, false)
	if _autotest:
		_picked_skill = "saki"
		_start_game()
	elif _shots:
		_picked_skill = "saki"
		_screen = "menu"
		_build_main_menu()  # 依次演示:主菜单 → 选人 → 房间 → 对局
	else:
		_build_main_menu()


# ———————————————————— 开局选人 ————————————————————

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.name = "BG"
	bg.color = Color("123524")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_table_bg = TextureRect.new()
	_table_bg.name = "TableBG"
	_table_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_table_bg.set_offsets_preset(Control.PRESET_FULL_RECT)
	_table_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_table_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_table_bg.visible = false
	add_child(_table_bg)


func _build_table_bg() -> void:
	if _cfg_bg_path != "" and FileAccess.file_exists(_cfg_bg_path):
		var img := Image.load_from_file(_cfg_bg_path)
		if img:
			_table_bg.texture = ImageTexture.create_from_image(img)
			_table_bg.visible = true


func _clear_ui() -> void:
	for c in get_children():
		if c.name != "BG" and c.name != "TableBG" and c.name != "Net" and not c is CanvasLayer:
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

	# 自家手牌 + 副露(手牌为绝对定位容器:支持点选浮起/拖拽)
	_hand_box = Control.new()
	_hand_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hand_box.set_offsets_preset(Control.PRESET_FULL_RECT)
	_hand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_root.add_child(_hand_box)
	_meld_boxes[0] = HBoxContainer.new()
	_meld_boxes[0].add_theme_constant_override("separation", 4)
	_game_root.add_child(_meld_boxes[0])

	# 行动面板(浮于手牌上方,靠右;绝对定位容器)
	_action_box = Control.new()
	_action_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_action_box.set_offsets_preset(Control.PRESET_FULL_RECT)
	_action_box.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 全屏容器不拦截事件,内部按钮仍可点
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
	var head_row := HBoxContainer.new()
	head_row.name = "HeadRow"
	head_row.add_theme_constant_override("separation", 8)
	v.add_child(head_row)
	var badge_avatar := _make_avatar(table.players[seat].skill.id, 40)
	badge_avatar.tooltip_text = "点击查看技能说明"
	badge_avatar.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_toggle_skill_popup(table.players[seat].skill, badge.get_global_rect().position + Vector2(0, -8)))
	head_row.add_child(badge_avatar)
	var wind_row := HBoxContainer.new()
	wind_row.name = "WindRow"
	wind_row.add_theme_constant_override("separation", 6)
	head_row.add_child(wind_row)
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
			badge.position = Vector2(1130, 700)
		"top":
			badge.position = Vector2(1090, 78)
		"left":
			badge.position = Vector2(100, 78)
	_game_root.add_child(badge)
	_badge_refs[seat] = {"name": name_l, "score": score_l, "riichi": riichi_l, "panel": badge}
	return badge


## 立即从容器摘除并释放所有孩子(queue_free 是延迟的,child_count 会虚增)。
func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _on_table_event(text: String) -> void:
	if text.contains("打出"):
		_play_sfx(0)
	elif text.contains("碰") or text.contains("杠") or text.contains("吃"):
		_play_sfx(1)
	elif text.contains("立直"):
		_play_sfx(2)
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
	if net.is_client():
		return  # 客户端由快照驱动,不自行推进
	if table.phase == "round_end":
		return
	_tick += 1
	if _tick % 18 != 0:  # 约 0.3 秒推进一步
		return
	# 人类决策点:不打断,等 UI 输入(联机时含远端人类)
	if table.phase == "await_discard" and table.current_seat == 0 and not net.is_host():
		return
	if table.phase == "await_discard" and net.is_host() and not table.players[table.current_seat].is_ai and table.current_seat != 0:
		return
	if table.phase == "await_peek" and not net.is_host():
		return
	if table.phase == "await_peek" and net.is_host() and not table.players[table.current_seat].is_ai:
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
		await _save_shot("menu")
		_build_select_screen()
		return
	if _tick == 10:
		await _save_shot("select")
		_on_pick_character("saki")
		return
	if _tick == 18:
		# 演示房间页(房主视角:建房 + 补两台电脑)
		net.my_name = "房主"
		net.host_game()
		net.my_char = "saki"
		net.host_set_char("saki")
		net.host_add_ai(1)
		net.host_add_ai(2)
		_build_room()
		return
	if _tick == 26:
		await _save_shot("room")
		net.leave()
		_start_game()
		return
	if table == null or table.phase == "idle":
		return
	if _tick == 50 or _tick == 110 or _tick == 260:
		await _save_shot("game_%d" % _tick)
	if _tick == 30:
		if _settings_panel:
			_settings_panel.visible = true
	if _tick == 45:
		# 演示:点选浮起第一张手牌
		if table and table.phase == "await_discard" and table.current_seat == 0:
			_selected_hand_idx = 0
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
	if o.has("awaiting") and table.human_seat() >= 0 and (o["awaiting"] as Array).has(table.human_seat()):
		return false  # 已响应过本轮(联机快照)
	if (o.get("chi", []) as Array).size() > 0 or o.get("ron", false) or o.get("pon", false) or o.get("kan", false):
		return not (o.has("awaiting") and (o["awaiting"] as Array).has(table.human_seat()))
	return false

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
	if net != null and net.is_host() and net.in_game:
		net.broadcast_snapshot_builder(table)


var _badge_refs := {}


func _refresh_badges() -> void:
	for seat in 4:
		var p := table.players[seat]
		var refs: Dictionary = _badge_refs[seat]
		var badge: PanelContainer = refs.panel
		var sb: StyleBoxFlat = badge.get_theme_stylebox("panel")
		var is_turn: bool = table.current_seat == seat and table.phase != "round_end"
		sb.border_color = Color("ffd166") if is_turn else Color("ffffff22")
		sb.border_width_bottom = 2 if is_turn else 0
		(refs.name as Label).text = p.display_name
		(refs.score as Label).text = "%d 点" % p.score
		(refs.riichi as Label).visible = p.riichi


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
		if seat == 0:
			_river_nodes_by_kind.clear()
		for tile_id in table.players[seat].river:
			var side := SEAT_POS[seat] == "right" or SEAT_POS[seat] == "left"
			var node := _make_rotated_tile(tile_id) if _is_riichi_discard(seat, tile_id) or side else _make_tile(tile_id, false, true)
			grid.add_child(node)
			if seat == 0:
				var kind := MTile.kind_of(tile_id)
				var arr: Array = _river_nodes_by_kind.get(kind, [])
				arr.append(node)
				_river_nodes_by_kind[kind] = arr
		if seat == 0 and _hover_kind >= 0:
			_apply_river_highlight(_hover_kind, true)
	# 自家牌河整体左右居中
		var n := table.players[seat].river.size()
		if seat == 0:
			var cols := mini(6, maxi(1, n))
			grid.position = Vector2(640 - cols * (MINI_W + 2) / 2.0, 560)


## 立直宣言牌(牌河中横置):立直后(含宣言牌)的第 1 张牌河牌。
func _is_riichi_discard(seat: int, tile_id: int) -> bool:
	var p := table.players[seat]
	if not p.riichi or p.discards_after_riichi == 0:
		return false
	return p.river.find(tile_id) == p.river.size() - p.discards_after_riichi


func _refresh_hands() -> void:
	# 自家:明牌(排序显示;刚摸的牌固定在最右,与手牌留一张牌宽的间隔)
	_clear_children(_hand_box)
	var me := table.players[0]
	var hand := me.hand
	_display_map.clear()
	for i in hand.size():
		_display_map.append(i)
	_display_map.sort_custom(func(a, b):
		var ka := MTile.kind_of(hand[a])
		var kb := MTile.kind_of(hand[b])
		if ka != kb:
			return ka < kb
		if MTile.is_red(hand[a]) != MTile.is_red(hand[b]):
			return MTile.is_red(hand[a])
		return a < b)
	var drawn_pos := hand.find(me.just_drawn) if me.just_drawn >= 0 else -1
	if drawn_pos >= 0:
		_display_map.erase(drawn_pos)
		_display_map.append(drawn_pos)
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
	var drawn_changed: bool = table.players[0].just_drawn != _last_seen_drawn
	_last_seen_drawn = table.players[0].just_drawn
	if drawn_changed:
		_selected_hand_idx = -1
	_drawn_gap = drawn_pos >= 0
	for pos_i in _display_map.size():
		var real_idx: int = _display_map[pos_i]
		if pos_i == _display_map.size() - 1 and drawn_pos >= 0:
			var gap := ColorRect.new()
			gap.color = Color(0, 0, 0, 0)
			gap.size = Vector2(DRAWN_GAP, 1)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_hand_box.add_child(gap)
		var tile := _make_hand_tile(hand[real_idx], real_idx)
		_wire_hover(tile, hand[real_idx])
		_hand_box.add_child(tile)
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
	var children := _hand_box.get_children()
	var total := 0.0
	var widths: Array[float] = []
	for i in children.size():
		var is_gap := _drawn_gap and i == children.size() - 1
		var w := DRAWN_GAP if is_gap else TILE_W
		widths.append(w)
		total += w + 3
	var x := 640 - (total - 3) / 2.0  # 末尾不留分隔
	for i in children.size():
		var c := children[i] as Control
		var y := 714.0
		# 孩子顺序即显示顺序:第 i 个孩子对应 _display_map[i](间隔槽除外)
		var real_idx: int = _display_map[i] if i < _display_map.size() else -1
		if real_idx == _selected_hand_idx:
			y -= 16  # 点选浮起
		c.position = Vector2(x, y)
		c.size = Vector2(widths[i], TILE_H)
		x += widths[i] + 3


## 自家手牌牌张:点选浮起;双击打出;按住拖入牌河范围松手 = 打出。
func _make_hand_tile(tile_id: int, real_idx: int) -> Control:
	var tile := _make_tile(tile_id, false, false)
	tile.set_meta("real_idx", real_idx)
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.gui_input.connect(func(event: InputEvent):
		_on_hand_gui_input(tile_id, real_idx, event))
	return tile


func _on_hand_gui_input(tile_id: int, real_idx: int, event: InputEvent) -> void:
	if table == null or table.phase != "await_discard" or table.current_seat != 0:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _hand_gesture_active:
				return  # 一次手势只允许一张牌
			_hand_gesture_active = true
			_press = {
				"index": real_idx, "tile_id": tile_id,
				"pos": event.global_position, "moved": false,
				"time": Time.get_ticks_msec(),
			}
		else:
			_handle_hand_release(event.global_position)
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if _press.get("index", -1) == real_idx \
				and event.global_position.distance_to(_press.get("pos", event.global_position)) > 24.0:
			_press["moved"] = true
			if not _press.get("detached", false):
				_press["detached"] = true
				_detach_hand_tile(real_idx)
			if _drag_control != null and is_instance_valid(_drag_control):
				_drag_control.position = event.global_position - Vector2(TILE_W / 2.0, TILE_H / 2.0)


func _handle_hand_release(mouse_pos: Vector2) -> void:
	var idx: int = _press.get("index", -1)
	var moved: bool = _press.get("moved", false)
	_hand_gesture_active = false
	if idx < 0:
		return
	if moved:
		# 拖拽:松手位置严格落在自家牌河矩形内 = 打出(牌控件随弃);否则放回原位
		var grid: GridContainer = _river_grids[0]
		var rect: Rect2 = grid.get_global_rect()
		if rect.has_point(mouse_pos):
			if _drag_control != null and is_instance_valid(_drag_control):
				_drag_control.queue_free()
				_drag_control = null
			_press = {}
			_do_discard(idx)
		else:
			_restore_hand_tile()
			_press = {}
			_layout_hand_row()
		return
	# 单击:模式优先(立直/咲选牌);之后按打牌方式设置
	if _mode == "riichi":
		_press = {}
		if _net_act("riichi", {"index": idx}):
			_mode = ""
			return
		if table.human_riichi(idx):
			_mode = ""
			_refresh()
		return
	if _mode == "saki_pick":
		_press = {}
		_saki_index = idx
		_mode = "saki_delta"
		_refresh()
		return
	if _cfg_click_mode == 0:
		# 单击打出模式
		_press = {}
		_do_discard(idx)
		return
	# 双击打出模式:点选浮起,再点同一张即打出
	if idx == _selected_hand_idx:
		_press = {}
		_do_discard(idx)
		return
	_press = {}
	_selected_hand_idx = idx
	_layout_hand_row()


func _do_discard(real_idx: int) -> void:
	if table == null or table.phase != "await_discard" or table.current_seat != 0:
		return  # 不在自己打牌阶段,拒绝打出
	_selected_hand_idx = -1
	if _net_act("discard", {"index": real_idx}):
		return
	table.human_discard(real_idx)
	_refresh()


## 拖拽开始:把牌控件从手牌行摘出(原位留空),挂到顶层跟手。
func _detach_hand_tile(real_idx: int) -> void:
	for c in _hand_box.get_children():
		if c is Control and int(c.get_meta("real_idx", -1)) == real_idx:
			_drag_slot = c.get_index()
			_hand_box.remove_child(c)
			_drag_control = c
			_drag_control.z_index = 60
			_drag_control.position = get_global_mouse_position() - Vector2(TILE_W / 2.0, TILE_H / 2.0)
			_game_root.add_child(_drag_control)
			return


## 拖拽未打出:牌控件放回手牌行原槽位。
func _restore_hand_tile() -> void:
	if _drag_control != null and is_instance_valid(_drag_control):
		_drag_control.z_index = 0
		_hand_box.add_child(_drag_control)
		_hand_box.move_child(_drag_control, clampi(_drag_slot, 0, _hand_box.get_child_count() - 1))
	_drag_control = null
	_drag_slot = -1


## 鼠标悬停手牌时,高亮自家牌河中的同种牌(振听/现物提示)。
func _wire_hover(tile: Control, tile_id: int) -> void:
	var kind := MTile.kind_of(tile_id)
	tile.mouse_entered.connect(func():
		_hover_kind = kind
		_apply_river_highlight(kind, true))
	tile.mouse_exited.connect(func():
		if _hover_kind == kind:
			_hover_kind = -1
		_apply_river_highlight(kind, false))


func _apply_river_highlight(kind: int, on: bool) -> void:
	var arr: Array = _river_nodes_by_kind.get(kind, [])
	for c in arr:
		if not is_instance_valid(c):
			continue
		c.modulate = Color(1.6, 1.4, 0.5) if on else Color(1, 1, 1)


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
		_place_rows(rows)
		return
	if table.phase == "await_peek":
		for i in table.peek_options.size():
			var b := Button.new()
			b.text = "取 %s" % MTile.label_id(table.peek_options[i])
			b.custom_minimum_size = Vector2(0, 40)
			b.pressed.connect(_on_pick_peek.bind(i))
			rows.add_child(b)
		_place_rows(rows)
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
		_place_rows(rows)
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
	if not me.riichi and me.is_menzen() and table.has_tenpai_discard(0):
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
	_place_rows(rows)


func _place_rows(rows: Control) -> void:
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


# ———————————————————— 设置 / 音频 ————————————————————

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		_cfg_res_idx = int(cf.get_value("video", "resolution", 0))
		_cfg_bgm = int(cf.get_value("audio", "bgm", 50))
		_cfg_sfx = int(cf.get_value("audio", "sfx", 70))
		_cfg_bg_path = str(cf.get_value("video", "table_bg", ""))
		_cfg_click_mode = int(cf.get_value("input", "click_mode", 1))
	_cfg_res_idx = clampi(_cfg_res_idx, 0, RES_PRESETS.size() - 1)
	_cfg_bgm = clampi(_cfg_bgm, 0, 100)
	_cfg_sfx = clampi(_cfg_sfx, 0, 100)
	_cfg_click_mode = clampi(_cfg_click_mode, 0, 1)


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("video", "resolution", _cfg_res_idx)
	cf.set_value("video", "table_bg", _cfg_bg_path)
	cf.set_value("input", "click_mode", _cfg_click_mode)
	cf.set_value("audio", "bgm", _cfg_bgm)
	cf.set_value("audio", "sfx", _cfg_sfx)
	cf.save(SETTINGS_PATH)


func _apply_resolution(idx: int, save := true) -> void:
	idx = clampi(idx, 0, RES_PRESETS.size() - 1)
	_cfg_res_idx = idx
	var preset: Array = RES_PRESETS[idx]
	get_window().size = Vector2i(preset[0], preset[1])
	if save:
		_save_settings()


func _apply_volumes() -> void:
	AudioServer.set_bus_volume_db(1, linear_to_db(_cfg_bgm / 100.0) if _cfg_bgm > 0 else -80.0)
	AudioServer.set_bus_volume_db(2, linear_to_db(_cfg_sfx / 100.0) if _cfg_sfx > 0 else -80.0)
	AudioServer.set_bus_mute(1, _cfg_bgm == 0)
	AudioServer.set_bus_mute(2, _cfg_sfx == 0)


func _build_settings_ui() -> void:
	_settings_layer = CanvasLayer.new()
	_settings_layer.name = "SettingsLayer"
	_settings_layer.layer = 10
	add_child(_settings_layer)

	var gear := Button.new()
	gear.text = "⚙ 设置"
	gear.position = Vector2(1160, 8)
	gear.size = Vector2(96, 30)
	gear.pressed.connect(func(): _settings_panel.visible = not _settings_panel.visible)
	_settings_layer.add_child(gear)

	_settings_panel = PanelContainer.new()
	_settings_panel.add_theme_stylebox_override("panel", _panel_style(Color("0f2e22f2"), 12, 14))
	_settings_panel.position = Vector2(830, 44)
	_settings_panel.custom_minimum_size = Vector2(426, 0)
	_settings_panel.visible = false
	_settings_layer.add_child(_settings_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_settings_panel.add_child(box)

	box.add_child(_make_label("分辨率", 14, Color("95d5b2")))
	var res_opt := OptionButton.new()
	for n in RES_NAMES:
		res_opt.add_item(n)
	res_opt.selected = _cfg_res_idx
	res_opt.item_selected.connect(func(i): _apply_resolution(i, true))
	box.add_child(res_opt)

	box.add_child(_make_label("背景音乐音量", 14, Color("95d5b2")))
	var bgm := HSlider.new()
	bgm.min_value = 0
	bgm.max_value = 100
	bgm.value = _cfg_bgm
	bgm.value_changed.connect(func(v):
		_cfg_bgm = int(v)
		_apply_volumes()
		_save_settings())
	box.add_child(bgm)

	box.add_child(_make_label("音效音量(吃 / 碰 / 杠 / 打牌 / 立直)", 14, Color("95d5b2")))
	var sfx := HSlider.new()
	sfx.min_value = 0
	sfx.max_value = 100
	sfx.value = _cfg_sfx
	sfx.value_changed.connect(func(v):
		_cfg_sfx = int(v)
		_apply_volumes()
		_save_settings())
	box.add_child(sfx)

	box.add_child(_make_label("打牌方式", 14, Color("95d5b2")))
	var click_opt := OptionButton.new()
	click_opt.add_item("双击打出(或拖入牌河)")
	click_opt.add_item("单击打出(或拖入牌河)")
	click_opt.selected = _cfg_click_mode
	click_opt.item_selected.connect(func(i):
		_cfg_click_mode = i
		_save_settings())
	box.add_child(click_opt)

	box.add_child(_make_label("牌桌背景图片", 14, Color("95d5b2")))
	var bg_row := HBoxContainer.new()
	bg_row.add_theme_constant_override("separation", 8)
	box.add_child(bg_row)
	var pick := Button.new()
	pick.text = "选择图片…"
	pick.pressed.connect(func(): _bg_dialog().popup_centered(Vector2i(720, 480)))
	bg_row.add_child(pick)
	var clear := Button.new()
	clear.text = "恢复默认绿色桌面"
	clear.pressed.connect(func():
		_cfg_bg_path = ""
		_table_bg.visible = false
		_save_settings())
	bg_row.add_child(clear)
	var path_l := _make_label(_cfg_bg_path if _cfg_bg_path != "" else "(默认)", 10, Color("caf0f8aa"))
	path_l.name = "BgPath"
	path_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	path_l.custom_minimum_size = Vector2(0, 14)
	box.add_child(path_l)


var _bg_dialog_ref: FileDialog


func _bg_dialog() -> FileDialog:
	if _bg_dialog_ref and is_instance_valid(_bg_dialog_ref):
		return _bg_dialog_ref
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray(["*.png ; PNG 图片", "*.jpg,*.jpeg ; JPEG 图片", "*.webp ; WebP 图片"])
	dlg.file_selected.connect(_on_bg_selected)
	_settings_layer.add_child(dlg)
	_bg_dialog_ref = dlg
	return dlg


func _on_bg_selected(path: String) -> void:
	_cfg_bg_path = path
	_build_table_bg()
	_save_settings()
	var path_l := _settings_panel.get_node("VBoxContainer/BgPath") as Label
	if path_l:
		path_l.text = path


## 技能说明弹窗:点头像显示,再点头像或点弹窗隐藏。
func _toggle_skill_popup(skill: MSkill, near: Vector2) -> void:
	if _skill_popup != null and is_instance_valid(_skill_popup):
		if _skill_popup.visible and _skill_popup.get_meta("char_id", "") == skill.id:
			_skill_popup.visible = false
			return
		_skill_popup.queue_free()
	_skill_popup = PanelContainer.new()
	_skill_popup.set_meta("char_id", skill.id)
	_skill_popup.add_theme_stylebox_override("panel", _panel_style(Color("0f2e22f5"), 12, 14))
	_skill_popup.custom_minimum_size = Vector2(300, 0)
	_skill_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_skill_popup.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_skill_popup.visible = false)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_skill_popup.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	head.add_child(_make_avatar(skill.id, 34))
	var t := _make_label("%s「%s」" % [skill.char_name, skill.title], 16, Color("ffd166"))
	head.add_child(t)
	var d := _make_label(skill.desc, 13, Color("ffffff"))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(280, 0)
	v.add_child(d)
	_skill_popup.position = Vector2(clampf(near.x, 8, 950), clampf(near.y - 40, 44, 700))
	_settings_layer.add_child(_skill_popup)


# —— 程序合成音频:无外部素材也能有 BGM 与打牌/鸣牌音效 ——

func _setup_audio() -> void:
	while AudioServer.bus_count < 3:
		AudioServer.add_bus(AudioServer.bus_count)
	AudioServer.set_bus_name(1, "BGM")
	AudioServer.set_bus_name(2, "SFX")
	_apply_volumes()
	_sfx_streams = [_make_clack(1.0), _make_clack(0.7), _make_ding()]
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "BGM"
	_bgm_player.stream = _make_bgm()
	add_child(_bgm_player)
	_bgm_player.play()
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.bus = "SFX"
	add_child(_sfx_player)


func _play_sfx(kind: int) -> void:
	if _sfx_player == null or kind < 0 or kind >= _sfx_streams.size():
		return
	_sfx_player.stream = _sfx_streams[kind]
	_sfx_player.play()


func _to_wav(samples: PackedFloat32Array, looped := false) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	wav.data = bytes
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


## 麻将牌撞击声:短促噪声 + 低频体腔音。
func _make_clack(pitch: float) -> AudioStreamWAV:
	var n := 1400
	var samples := PackedFloat32Array()
	samples.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t := float(i) / 22050.0
		var env := exp(-t * 90.0)
		var noise := (rng.randf() * 2.0 - 1.0) * 0.5
		var tone := sin(TAU * 900.0 * pitch * t) * 0.4
		samples[i] = (noise + tone) * env * 0.7
	return _to_wav(samples)


## 立直 / 和牌提示音:清脆双音。
func _make_ding() -> AudioStreamWAV:
	var n := 9000
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := float(i) / 22050.0
		var env := exp(-t * 4.0)
		var v := sin(TAU * 1318.5 * t) * 0.5
		if t > 0.12:
			v += sin(TAU * 1760.0 * (t - 0.12)) * 0.35 * exp(-(t - 0.12) * 5.0)
		samples[i] = v * env * 0.6
	return _to_wav(samples)


## 背景音乐:低音量和风弦音垫(8 秒无缝循环)。
func _make_bgm() -> AudioStreamWAV:
	var n := 22050 * 8
	var samples := PackedFloat32Array()
	samples.resize(n)
	var freqs := [220.0, 277.18, 329.63, 440.0]
	var amps := [0.5, 0.35, 0.3, 0.22]
	for i in n:
		var t := float(i) / 22050.0
		var v := 0.0
		for f in freqs.size():
			var lfo := 0.6 + 0.4 * sin(TAU * t / 8.0 + f * 1.7)
			v += sin(TAU * freqs[f] * t) * amps[f] * lfo
		var fade := minf(t / 1.5, minf((8.0 - t) / 1.5, 1.0))
		samples[i] = v * 0.16 * fade
	return _to_wav(samples, true)


func _chi_label(combo: Dictionary, called_kind: int) -> String:
	var parts: Array[String] = []
	for k in [combo.low, combo.low + 1, combo.low + 2]:
		parts.append(MTile.label(k) if k != called_kind else "[%s]" % MTile.label(k))
	return "".join(parts)


# ———————————————————— 主菜单 ————————————————————

var _menu_error_label: Label
var _name_edit: LineEdit
var _code_edit: LineEdit


func _build_main_menu() -> void:
	_clear_ui()
	_screen = "menu"
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color("0f2e22ee"), 16, 28))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(_make_label("天才麻将少女 · 技能麻将", 32, Color("ffd166")))
	box.add_child(_make_label("八位角色的超能力日麻 · 支持单人 / 联机(最多 4 人)", 14, Color("caf0f8")))

	box.add_child(_make_label("你的名字", 13, Color("95d5b2")))
	_name_edit = LineEdit.new()
	_name_edit.text = net.my_name
	_name_edit.placeholder_text = "玩家"
	_name_edit.custom_minimum_size = Vector2(0, 36)
	box.add_child(_name_edit)

	var b_single := Button.new()
	b_single.text = "单人游玩(vs AI)"
	b_single.custom_minimum_size = Vector2(0, 44)
	b_single.pressed.connect(func():
		net.my_name = _name_edit.text
		_build_select_screen())
	box.add_child(b_single)

	box.add_child(_make_label("—— 联机(同一局域网,或房主端口转发后用公网 IP)——", 12, Color("95d5b2aa")))
	var b_host := Button.new()
	b_host.text = "创建房间(获得邀请码)"
	b_host.custom_minimum_size = Vector2(0, 44)
	b_host.pressed.connect(func():
		net.my_name = _name_edit.text if _name_edit.text != "" else "房主"
		net.my_char = ""
		var code := net.host_game()
		if code != "":
			_build_room()
		else:
			_menu_error("创建失败:端口被占用?"))
	box.add_child(b_host)

	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "输入邀请码(SMJ…)或 IP:端口"
	_code_edit.custom_minimum_size = Vector2(0, 36)
	box.add_child(_code_edit)
	var b_join := Button.new()
	b_join.text = "加入房间"
	b_join.custom_minimum_size = Vector2(0, 40)
	b_join.pressed.connect(func():
		net.my_name = _name_edit.text if _name_edit.text != "" else "玩家"
		var err := net.join_game(_code_edit.text)
		if err != OK:
			_menu_error("加入失败:邀请码格式错误"))
	box.add_child(b_join)
	_menu_error_label = _make_label("", 12, Color("ff6b6b"))
	box.add_child(_menu_error_label)


func _menu_error(text: String) -> void:
	if _menu_error_label:
		_menu_error_label.text = text

# ———————————————————— 房间页 ————————————————————

var _room_list_box: VBoxContainer
var _room_code_label: Label


func _build_room() -> void:
	_clear_ui()
	_screen = "room"
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color("0f2e22ee"), 16, 20))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(_make_label("房间大厅", 26, Color("ffd166")))
	_room_code_label = _make_label("", 20, Color("caf0f8"))
	box.add_child(_room_code_label)
	box.add_child(_make_label("把邀请码发给朋友(局域网直接可用;跨网请端口转发后改用 公网IP:端口)", 11, Color("95d5b2aa")))

	_room_list_box = VBoxContainer.new()
	_room_list_box.add_theme_constant_override("separation", 6)
	box.add_child(_room_list_box)

	box.add_child(_make_label("选择你的角色(不能与其他人相同)", 13, Color("95d5b2")))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 6)
	box.add_child(grid)
	for cid in CHARACTER_IDS:
		var taken := false
		for entry in net.lobby:
			if entry.char == cid and entry.id != multiplayer.get_unique_id() and not entry.ai:
				taken = true
		var slot := VBoxContainer.new()
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(56, 56)
		var av := _make_avatar(cid, 52)
		av.set_anchors_preset(Control.PRESET_FULL_RECT)
		av.set_offsets_preset(Control.PRESET_FULL_RECT)
		av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(av)
		if taken:
			btn.disabled = true
			btn.tooltip_text = "已被选择"
		if net.my_char == cid:
			btn.custom_minimum_size = Vector2(62, 62)
		btn.pressed.connect(func(): _pick_room_char(cid))
		slot.add_child(btn)
		grid.add_child(slot)

	if net.is_host():
		box.add_child(_make_label("—— 规则设置(房主)——", 13, Color("95d5b2")))
		var rules_grid := GridContainer.new()
		rules_grid.columns = 2
		rules_grid.add_theme_constant_override("h_separation", 16)
		box.add_child(rules_grid)
		rules_grid.add_child(_make_label("初始点数", 13, Color("caf0f8")))
		var score_opt := OptionButton.new()
		for item in ["25000", "35000"]:
			score_opt.add_item(item)
		score_opt.selected = 0 if int(net.rules.get("start_score", 25000)) == 25000 else 1
		score_opt.item_selected.connect(func(i): 
			var r := net.rules.duplicate()
			r.start_score = 25000 if i == 0 else 35000
			net.host_set_rules(r))
		rules_grid.add_child(score_opt)
		rules_grid.add_child(_make_label("红宝牌", 13, Color("caf0f8")))
		var red_opt := OptionButton.new()
		for item in ["0", "3(标准)"]:
			red_opt.add_item(item)
		red_opt.selected = 0 if int(net.rules.get("red_dora", 3)) == 0 else 1
		red_opt.item_selected.connect(func(i):
			var r := net.rules.duplicate()
			r.red_dora = 0 if i == 0 else 3
			net.host_set_rules(r))
		rules_grid.add_child(red_opt)
		for rule_key in [["kuitan", "食断(副露断幺)"], ["ippatsu", "一发"], ["ura", "里宝"]]:
			var cb := CheckBox.new()
			cb.text = rule_key[1]
			cb.button_pressed = bool(net.rules.get(rule_key[0], true))
			cb.toggled.connect(func(on):
				var r := net.rules.duplicate()
				r[rule_key[0]] = on
				net.host_set_rules(r))
			rules_grid.add_child(cb)
		rules_grid.add_child(_make_label("加入电脑的默认难度", 13, Color("caf0f8")))
		var diff_opt := OptionButton.new()
		for item in ["简单", "普通", "困难"]:
			diff_opt.add_item(item)
		diff_opt.selected = int(net.rules.get("ai_difficulty", 1))
		diff_opt.item_selected.connect(func(i):
			var r := net.rules.duplicate()
			r.ai_difficulty = i
			net.host_set_rules(r))
		rules_grid.add_child(diff_opt)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	box.add_child(btn_row)
	if net.is_host():
		var add_ai := Button.new()
		add_ai.text = "添加电脑"
		add_ai.custom_minimum_size = Vector2(0, 40)
		add_ai.pressed.connect(func(): net.host_add_ai(int(net.rules.get("ai_difficulty", 1))))
		btn_row.add_child(add_ai)
		var start := Button.new()
		start.text = "开始游戏"
		start.custom_minimum_size = Vector2(0, 40)
		start.pressed.connect(func(): net.host_start_game())
		btn_row.add_child(start)
	else:
		btn_row.add_child(_make_label("等待房主开始…", 14, Color("caf0f8")))
	var leave := Button.new()
	leave.text = "退出房间"
	leave.custom_minimum_size = Vector2(0, 40)
	leave.pressed.connect(func():
		net.leave()
		_build_main_menu())
	btn_row.add_child(leave)
	_refresh_room()


func _pick_room_char(cid: String) -> void:
	net.my_char = cid
	if net.is_host():
		net.host_set_char(cid)
	else:
		net.send_set_char(cid)
	_refresh_room()


func _refresh_room() -> void:
	if _screen != "room" or _room_list_box == null:
		return
	if _room_code_label:
		var code_txt: String = net.room_code if net.is_host() else "(加入的房间)"
		_room_code_label.text = "邀请码:%s" % code_txt
	_clear_children(_room_list_box)
	for i in 4:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		if i < net.lobby.size():
			var entry: Dictionary = net.lobby[i]
			var room_avatar := _make_avatar(entry.char, 40)
			if entry.char != "":
				var sk := MSkills.create(entry.char)
				room_avatar.tooltip_text = "点击查看技能说明"
				room_avatar.gui_input.connect(func(event: InputEvent):
					if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
						_toggle_skill_popup(sk, Vector2(360, 200)))
			row.add_child(room_avatar)
			var tag: String = ("AI · %s" % ["简单", "普通", "困难"][clampi(int(entry.diff), 0, 2)]) if entry.ai else entry.name
			row.add_child(_make_label(tag, 15, Color("ffffff")))
			if entry.char != "":
				row.add_child(_make_label("→ %s(%s)" % [CHAR_KANJI.get(entry.char, ""), MSkills.create(entry.char).title], 13, Color("ffd166")))
			if entry.id == 1:
				row.add_child(_make_label("房主", 13, Color("95d5b2")))
			if net.is_host() and entry.ai:
				var diff_opt := OptionButton.new()
				for item in ["简单", "普通", "困难"]:
					diff_opt.add_item(item)
				diff_opt.selected = clampi(int(entry.diff), 0, 2)
				var slot := i
				diff_opt.item_selected.connect(func(sel): net.host_set_diff(slot, sel))
				row.add_child(diff_opt)
				var rm := Button.new()
				rm.text = "移除"
				rm.pressed.connect(func(): net.host_remove_ai(slot))
				row.add_child(rm)
		else:
			row.add_child(_make_label("(空位:开始时自动补充电脑)", 13, Color("6c757d")))
		_room_list_box.add_child(row)


func _on_net_lobby() -> void:
	_refresh_room()


# ———————————————————— 联机对局接线 ————————————————————

func _on_net_game_started(args: Dictionary) -> void:
	_start_net_game(args)


func _on_net_snapshot(snap: Dictionary) -> void:
	if table:
		table.apply_snapshot(snap)
		_refresh()


func _start_net_game(args: Dictionary) -> void:
	_clear_ui()
	_mode = ""
	_screen = "game"
	var chars: Array = args.chars
	table = MTable.new()
	table.setup(chars, net.my_seat if net.is_client() else 0, args.seed, 0, net.rules)
	for i in 4:
		table.players[i].is_ai = int(args.humans[i]) == 0
		table.players[i].ai_difficulty = int(args.diffs[i])
	for entry in net.lobby:
		if entry.ai:
			continue
		for i in 4:
			if int(args.humans[i]) == int(entry.id):
				table.players[i].display_name = entry.name
	net.bind_table(table)
	table.start_round(args.seed)
	_build_game_ui()
	_refresh()


func _net_act(kind: String, args: Dictionary = {}) -> bool:
	## 联机时动作改走网络;离线返回 false 走本地逻辑。
	if not net.is_online():
		return false
	var payload := {"kind": kind}
	for k in args:
		payload[k] = args[k]
	if net.is_host():
		net.apply_action(net.my_seat, payload)
		_refresh()
	else:
		net.send_action(payload)
	return true


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
			if _net_act("riichi", {"index": index}):
				_mode = ""
				return
			if table.human_riichi(index):
				_mode = ""
		_:
			if _net_act("discard", {"index": index}):
				return
			table.human_discard(index)
	_refresh()


func _on_mode_saki() -> void:
	_mode = "saki_pick"
	_refresh()


func _on_mode_hisa() -> void:
	if _net_act("hisa"):
		return
	table.human_use_hisa()
	_refresh()


func _on_mode_riichi() -> void:
	_mode = "riichi"
	_refresh()


func _on_cancel_mode() -> void:
	_mode = ""
	_refresh()


func _on_saki_plus() -> void:
	if _net_act("saki", {"index": _saki_index, "delta": 1}):
		_mode = ""
		return
	table.human_use_saki(_saki_index, 1)
	_mode = ""
	_refresh()


func _on_saki_minus() -> void:
	if _net_act("saki", {"index": _saki_index, "delta": -1}):
		_mode = ""
		return
	table.human_use_saki(_saki_index, -1)
	_mode = ""
	_refresh()


func _on_pick_peek(index: int) -> void:
	if _net_act("peek", {"index": index}):
		return
	table.human_choose_peek(index)
	_refresh()


func _on_human_ron() -> void:
	if _net_act("ron"):
		return
	table.human_ron()
	_mode = ""
	_refresh()


func _on_human_pon() -> void:
	if _net_act("pon"):
		return
	table.human_pon()
	_refresh()


func _on_human_kan() -> void:
	if _net_act("kan"):
		return
	table.human_kan()
	_refresh()


func _on_human_chi(combo_index: int) -> void:
	if _net_act("chi", {"combo": combo_index}):
		return
	table.human_chi(combo_index)
	_refresh()


func _on_human_kakan(hand_index: int) -> void:
	if _net_act("kakan", {"index": hand_index}):
		return
	table.human_kakan(hand_index)
	_refresh()


func _on_human_mulligan() -> void:
	if _net_act("mulligan"):
		return
	table.human_use_mulligan()
	_refresh()


func _on_human_ako() -> void:
	if _net_act("ako"):
		return
	table.human_use_ako()
	_refresh()


func _on_human_decline() -> void:
	if _net_act("decline"):
		return
	table.human_decline()
	_refresh()


func _on_human_tsumo() -> void:
	if _net_act("tsumo"):
		return
	table.human_tsumo()
	_refresh()


func _on_human_ankan(index: int) -> void:
	if _net_act("ankan", {"index": index}):
		return
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
	if net.is_online():
		if net.is_host():
			var back := Button.new()
			back.text = "返回房间"
			back.custom_minimum_size = Vector2(0, 40)
			back.pressed.connect(func():
				net.host_back_to_lobby()
				_build_room())
			box.add_child(back)
		else:
			box.add_child(_make_label("等待房主返回房间…", 14, Color("caf0f8")))
	else:
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
	var name_l := _make_label(sk.char_name, 18, Color("ffffff"))
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_l := _make_label("「%s」" % sk.title, 14, Color("ffd166"))
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var desc_l := _make_label(sk.desc, 11, Color("b7e4c7"))
	desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_l.custom_minimum_size = Vector2(170, 76)
	desc_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_make_avatar(cid, 30))
	head.add_child(name_l)
	v.add_child(head)
	v.add_child(title_l)
	v.add_child(desc_l)
	btn.add_child(v)
	btn.pressed.connect(_on_pick_character.bind(cid))
	return btn


## 角色头像:主题色圆 + 角色首字(程序绘制,无需美术素材)。
func _make_avatar(char_id: String, size: float) -> Control:
	var avatar := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(CHAR_THEME.get(char_id, "6c757d"))
	for side in ["corner_radius_top_left", "corner_radius_top_right", "corner_radius_bottom_left", "corner_radius_bottom_right"]:
		sb.set(side, int(size / 2.0))
	avatar.add_theme_stylebox_override("panel", sb)
	avatar.custom_minimum_size = Vector2(size, size)
	avatar.size = Vector2(size, size)
	var l := _make_label(CHAR_KANJI.get(char_id, "素"), int(size * 0.5), Color("ffffff"))
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.set_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.add_child(l)
	return avatar


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

	# CC0 贴图(FluffyStuff/riichi-mahjong-tiles):存在则优先贴图渲染
	var tex := _tile_tex(tile_id)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.set_offsets_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tr)
		return holder
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


## tile_id → 贴图路径(FluffyStuff 命名),带缓存。
func _tile_tex(tile_id: int) -> Texture2D:
	var kind := MTile.kind_of(tile_id)
	var name: String
	if MTile.is_red(tile_id):
		name = ["man5-dora", "pin5-dora", "sou5-dora"][MTile.suit(kind)]
	elif kind < 27:
		name = ["man", "pin", "sou"][MTile.suit(kind)] + str(MTile.rank(kind))
	else:
		name = ["ton", "nan", "shaa", "pei", "haku", "hatsu", "chun"][kind - 27]
	var path := "res://assets/tiles/%s.svg" % name
	if _tile_tex_cache.has(path):
		return _tile_tex_cache[path]
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_tile_tex_cache[path] = tex
	return tex


func _back_tex() -> Texture2D:
	var path := "res://assets/tiles/back.svg"
	if not _tile_tex_cache.has(path):
		_tile_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tile_tex_cache[path]


## 牌背(对手手牌):CC0 牌背贴图;侧位玩家横躺 90°,对家竖立。
func _make_back(seat: int) -> Control:
	var back := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("12332e")
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	back.add_theme_stylebox_override("panel", sb)
	var side := SEAT_POS[seat] != "top"
	var w := BACK_SIDE_W if side else BACK_TOP_W
	var h := BACK_SIDE_H if side else BACK_TOP_H
	back.custom_minimum_size = Vector2(w, h)
	var tex := _back_tex()
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if side:
			# 横躺:竖版贴图旋转 90°,视觉为 54×36
			tr.size = Vector2(h, w)
			tr.rotation = PI / 2.0
			tr.pivot_offset = tr.size / 2.0
			tr.position = Vector2((w - h) / 2.0, (h - w) / 2.0)
		else:
			tr.set_anchors_preset(Control.PRESET_FULL_RECT)
			tr.set_offsets_preset(Control.PRESET_FULL_RECT)
		back.add_child(tr)
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
