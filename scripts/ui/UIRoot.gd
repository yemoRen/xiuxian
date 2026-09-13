extends Control

## 界面主控：顶栏 / 五页签 / 弹窗 / toast。
## 由 web 版 ui.js + index.html 移植为原生 Control 树。

const TH := preload("res://scripts/ui/ThemeCore.gd")

const REBUILD_MS := 400

const TABS := [
	["action", "行动"], ["facility", "设施"], ["people", "门徒"],
	["items", "道具"], ["settings", "设置"],
]
const MODAL_NONE := 0
const MODAL_CREATE := 1
const MODAL_PICK := 2
const MODAL_PERSON := 3
const MODAL_CONFIRM := 4
const MODAL_CHAMPION := 5

var tab: String = "action"

var _log_len := 0
var _action_ready := false
var _log_box: VBoxContainer = null

var _dirty := true
var _force := true
var _last_rebuild_ms := 0
var _scroll_frames := 0
var _scroll_top_frames := 0

# 弹窗状态
var _modal := MODAL_NONE
var _champion_was_running := false   # 大比弹窗前是否在推进，结算后恢复
var _modal_title := ""
var _modal_pick: Array = []
var _modal_pick_cb: Callable = Callable()
var _modal_pick_any := false
var _modal_pick_ctx: Dictionary = {}
var _person_id = null
var _confirm_text := ""
var _confirm_cb: Callable = Callable()

# 捏人状态
var _cfg := {}


# 节点引用
var _sect_label: Label
var _date_label: RichTextLabel
var _stats_box: HBoxContainer
var _ctrl_box: HBoxContainer
var _nav_box: HBoxContainer
var _content: ScrollContainer
var _content_body: VBoxContainer
var _modal_root: Control
var _modal_body: VBoxContainer = null
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_timer := 0.0


func G() -> GameCore:
	return XiuxianGlobals.game


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_chrome()
	G().changed.connect(_on_changed)
	_boot()


func _boot() -> void:
	# 实机模式：大比挂起等玩家选奖品（headless/测试保持自动结算）
	G().auto_champion = false

	if XiuxianGlobals.has_save():
		_open_confirm("检测到存档，是否继续上次宗门？", func():
			XiuxianGlobals.load_saved()
			_log_len = 0
			_action_ready = false
			_force = true
			close_modal()
		, "继续", Callable(open_create))
	else:
		open_create()


func _on_changed() -> void:
	_dirty = true


# ═══════════════════════════════════════════════════════
# 骨架
# ═══════════════════════════════════════════════════════

func _build_chrome() -> void:
	var bg := ColorRect.new()
	bg.color = TH.PAPER
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var col := TH.vbox(0)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(col)

	# ── 顶栏
	var header := PanelContainer.new()
	var hs := StyleBoxFlat.new()
	hs.bg_color = TH.PAPER2
	hs.border_color = TH.LINE2
	hs.border_width_bottom = 2
	header.add_theme_stylebox_override("panel", hs)
	col.add_child(header)

	var hpad := MarginContainer.new()
	hpad.add_theme_constant_override("margin_left", 44)
	hpad.add_theme_constant_override("margin_right", 44)
	hpad.add_theme_constant_override("margin_top", 10)
	hpad.add_theme_constant_override("margin_bottom", 8)
	header.add_child(hpad)

	var hcol := TH.vbox(4)
	hpad.add_child(hcol)

	var row1 := TH.hbox(14)
	hcol.add_child(row1)
	_sect_label = TH.label("", TH.FS_TITLE, TH.INK, true)
	row1.add_child(_sect_label)
	_date_label = TH.rich(TH.FS_BASE, TH.INK2)
	_date_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_date_label.fit_content = true
	_date_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row1.add_child(_date_label)
	row1.add_child(TH.spacer(0, 0, true))
	_ctrl_box = TH.hbox(6)
	row1.add_child(_ctrl_box)

	var stats_holder := TH.hbox(18)
	hcol.add_child(stats_holder)
	_stats_box = stats_holder

	# ── 主体
	var body_margin := MarginContainer.new()
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_margin.add_theme_constant_override("margin_left", 44)
	body_margin.add_theme_constant_override("margin_right", 44)
	body_margin.add_theme_constant_override("margin_top", 8)
	body_margin.add_theme_constant_override("margin_bottom", 16)
	col.add_child(body_margin)

	var bcol := TH.vbox(0)
	body_margin.add_child(bcol)

	_nav_box = TH.hbox(2)
	bcol.add_child(_nav_box)

	_content = TH.scroll()
	bcol.add_child(_content)

	_content_body = TH.vbox(0)
	_content_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_content_body)

	# ── 弹窗层
	_modal_root = Control.new()
	_modal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_modal_root)

	# ── toast
	_toast_panel = PanelContainer.new()
	_toast_panel.add_theme_stylebox_override("panel", TH.sb_flat(TH.INK, 4, 18, 6))
	_toast_label = TH.label("", TH.FS_BASE, TH.PAPER2)
	_toast_panel.add_child(_toast_label)
	_toast_panel.visible = false
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	add_child(_toast_panel)


func _render_header() -> void:
	var s := G().s
	if s.is_empty():
		return
	_sect_label.text = str(s["sectName"])
	_date_label.text = "第 [b][color=#8c2f2f]%d[/color][/b] 年 %d 月 [b][color=#8c2f2f]%s[/color][/b] 旬" % [
		int(s["year"]), int(s["month"]), ["上", "中", "下"][int(s["xun"]) - 1]]

	_clear(_stats_box)
	_stats_box.add_child(_stat("灵石", GameCore.fmt_num(s["stone"]), TH.GOLD))
	_stats_box.add_child(_stat("宗门庇护人数", GameCore.fmt_num(s["protect"]), TH.GREEN))
	_stats_box.add_child(_stat("杂役", str(int(s["menial"])), TH.INK))
	_stats_box.add_child(_stat("门徒", "%d/%d" % [G().population(), G().capacity()], TH.INK))
	_stats_box.add_child(_stat("内门", str(G().inner_list().size()), TH.INK))
	_stats_box.add_child(_stat("距下次大比", "%d 旬" % int(s["championLeft"]), TH.GOLD))
	_stats_box.add_child(_stat("功法", str((s["books"] as Array).size()), TH.INK))
	_stats_box.add_child(_stat("功德", GameCore.fmt_num(s["merit"]), TH.INK))

	_clear(_ctrl_box)
	var pb := TH.button("暂停" if XiuxianGlobals.is_running() else "推进")
	pb.pressed.connect(func():
		XiuxianGlobals.toggle()
		_force = true
	)
	_ctrl_box.add_child(pb)
	for i in DataCore.SPEED.size():
		var spd: Dictionary = DataCore.SPEED[i]
		var b := TH.button(str(spd["n"]), "mini")
		if int(s["speed"]) == i:
			b.add_theme_stylebox_override("normal", TH.sb(TH.GOLD, TH.GOLD, 1, 4, 7, 3))
			b.add_theme_color_override("font_color", Color.WHITE)
			b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.pressed.connect(func():
			G().set_speed(i)
			_force = true
		)
		_ctrl_box.add_child(b)
	var sb := TH.button("存档", "mini")
	sb.pressed.connect(func():
		XiuxianGlobals.save_now()
		toast("已存档")
	)
	_ctrl_box.add_child(sb)


func _stat(name: String, value: String, color: Color) -> HBoxContainer:
	var h := TH.hbox(3)
	h.add_child(TH.label(name, TH.FS_SMALL, TH.INK2))
	h.add_child(TH.label(value, TH.FS_BASE, color, true))
	return h


func _render_nav() -> void:
	_clear(_nav_box)
	for t in TABS:
		var b := TH.button(str(t[1]), "nav_on" if tab == t[0] else "nav")
		b.pressed.connect(func():
			_goto_tab(str(t[0]))
		)
		_nav_box.add_child(b)


## 切页统一入口：标记重建，非纪事页把滚动复位到顶部
func _goto_tab(t: String) -> void:
	if tab == t:
		return
	tab = t
	_action_ready = false
	_force = true
	_dirty = true
	if t != "action":
		_scroll_top_frames = 2


func render_all() -> void:
	# 大比挂起态：自动弹出选奖品弹窗（仅实机模式，headless 已自动结算）
	if _modal == MODAL_NONE and not G().s.get("pending_champion", {}).is_empty():
		_open_champion_modal()

	_render_header()
	_render_nav()
	_render_tab()
	_render_modal()


# ═══════════════════════════════════════════════════════
# 页签分发
# ═══════════════════════════════════════════════════════

func _render_tab() -> void:
	if G().s.is_empty():
		return
	match tab:
		"action": _render_action()
		"facility":
			_action_ready = false
			_clear(_content_body)
			_render_facility()
		"people":
			_action_ready = false
			_clear(_content_body)
			_render_people()
		"items":
			_action_ready = false
			_clear(_content_body)
			_render_items()
		"settings":
			_action_ready = false
			_clear(_content_body)
			_render_settings()


# ── 行动：宗门纪事 ─────────────────────────────────────
func _render_action() -> void:
	var s := G().s
	var log: Array = s["log"]

	# 需要整块重建的三种情况：首次 / 强制 / 日志被裁剪
	if not _action_ready or _log_len > log.size() or _content_body.get_child_count() == 0:
		_clear(_content_body)
		var body := TH.panel("宗门纪事")
		_content_body.add_child(TH.panel_of(body))
		_log_box = TH.vbox(0)
		_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(_log_box)
		_log_len = 0
		_action_ready = true

	if _log_len < log.size():
		for i in range(_log_len, log.size()):
			_log_box.add_child(_log_item(log[i]))
		_log_len = log.size()
		_scroll_frames = 2


func _log_item(it: Dictionary) -> Control:
	var cls := str(it["c"])
	var color := TH.INK
	if cls == "good": color = TH.GREEN
	elif cls == "bad": color = TH.RED
	elif cls == "hint": color = TH.BLUE

	var r := TH.rich(TH.FS_BASE, color)
	var d := _esc(str(it["d"]))
	var t := _esc(str(it["t"]))
	r.text = "[color=#8c877a][font_size=%d]%s[/font_size][/color]  %s" % [TH.FS_SMALL, d, t]
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_top", 1)
	wrap.add_theme_constant_override("margin_bottom", 1)
	wrap.add_child(r)
	return wrap


# ── 设施 ──────────────────────────────────────────────
func _render_facility() -> void:
	var s := G().s
	# 七峰面板统一三列栅格，工整对齐
	var g := TH.grid(3)
	_content_body.add_child(g)

	var idx := 0
	for pk in DataCore.PEAKS:
		var st: Dictionary = s["peaks"][pk["id"]]
		var body := TH.panel("")
		var pc := TH.panel_of(body)

		# 标题行
		var title := TH.hbox(8)
		title.add_child(TH.label(str(pk["n"]), TH.FS_H4, TH.INK, true))
		title.add_child(TH.chip(str(pk["work"])))
		body.add_child(title)
		body.add_child(TH.wrap_label(str(pk["desc"]), TH.FS_SMALL, TH.INK3))

		if pk["id"] == "zhuanzhu":
			_peak_writer(body, pk["id"], st)
		else:
			_peak_leader(body, pk["id"], st)
			_peak_deputy(body, pk["id"], st)
			_peak_outer(body, pk["id"], st)
			_peak_menial(body, pk["id"], st)

		match pk["id"]:
			"fumo": _peak_zhenxie(body, st)
			"xunyou": _peak_xunyou(body, st)
			"danding": _peak_danding(body, st)
			"baiqi": _peak_baiqi(body, st)
			"shenyao", "lingkuang": _peak_field(body, pk["id"], st)

		TH.grid_add(g, idx, pc)
		idx += 1

	# 玄元峰（宗门建设）作为第 7 个面板纳入同风格栅格
	var body2 := TH.panel("")
	var pc2 := TH.panel_of(body2)
	var title2 := TH.hbox(8)
	title2.add_child(TH.label("玄元峰", TH.FS_H4, TH.INK, true))
	title2.add_child(TH.chip("宗门建设"))
	body2.add_child(title2)
	body2.add_child(TH.wrap_label("扩建屋舍与护山大阵，提升宗门根基", TH.FS_SMALL, TH.INK3))

	var r_house := _peak_row("屋舍")
	r_house.add_child(TH.label("lv%d　门徒上限 %d" % [int(s["houseLv"]), G().capacity()], TH.FS_BASE, TH.INK))
	r_house.add_child(TH.label(""))
	var b_house := TH.button("升级（%s灵石）" % GameCore.fmt_num(int(s["houseLv"]) * 800), "mini")
	b_house.pressed.connect(func():
		if not G().upgrade_house(): toast("灵石不足")
		_force = true
	)
	r_house.add_child(b_house)
	body2.add_child(r_house)

	var r_array := _peak_row("大阵")
	r_array.add_child(TH.label("lv%d　抵御魔修袭击" % int(s["arrayLv"]), TH.FS_BASE, TH.INK))
	r_array.add_child(TH.label(""))
	var b_array := TH.button("升级（%s灵石）" % GameCore.fmt_num(int(s["arrayLv"]) * 1200), "mini")
	b_array.pressed.connect(func():
		if not G().upgrade_array(): toast("灵石不足")
		_force = true
	)
	r_array.add_child(b_array)
	body2.add_child(r_array)

	TH.grid_add(g, idx, pc2)


func _peak_leader(body: VBoxContainer, pid: String, st: Dictionary) -> void:
	var lead := G().by_id(st["leader"])
	var row := _peak_row("峰主")
	if lead.is_empty():
		row.add_child(TH.chip("未任命（产出停滞）", "empty"))
	else:
		row.add_child(TH.chip("%s %s" % [lead["name"], G().realm_name(lead)], "lead"))
	var b := TH.button("选择", "mini")
	b.pressed.connect(func():
		pick_person(func(p): G().assign(p, pid, true, false), "任命", _leader_pool(), false, {"peak_id": pid})
	)
	row.add_child(b)
	body.add_child(row)


func _leader_pool() -> Array:
	# 各峰峰主/副手只能由内门弟子担任
	return G().inner_list()


func _peak_writer(body: VBoxContainer, pid: String, st: Dictionary) -> void:
	var row := _peak_row("撰写人")
	var w := G().by_id(st["writer"])
	if w.is_empty():
		row.add_child(TH.chip("未指定", "empty"))
	else:
		row.add_child(TH.chip(str(w["name"]), "lead"))
	var b := TH.button("选择", "mini")
	b.pressed.connect(func():
		pick_person(func(p):
			G().unassign(p)
			G().s["peaks"][pid]["writer"] = p["id"]
			G().changed.emit()
		, "指定撰写人", G().inner_list(), false, {"peak_id": pid})
	)
	row.add_child(b)
	body.add_child(row)

	var pct := minf(100.0, float(st["writeProgress"]) / 360.0 * 100.0)
	var pr := _peak_row("进度")
	var bar := TH.progress_bar()
	bar.value = pct
	pr.add_child(bar)
	pr.add_child(TH.label("%d%%" % int(pct), TH.FS_SMALL, TH.INK2))
	body.add_child(pr)
	body.add_child(TH.wrap_label("撰写功法需十载（360旬）", TH.FS_SMALL, TH.INK3))


func _peak_deputy(body: VBoxContainer, pid: String, st: Dictionary) -> void:
	var row := _peak_row("副手")
	var dep: Array = st["deputy"]
	if dep.is_empty():
		row.add_child(TH.chip("无", "empty"))
	else:
		for id in dep:
			var d := G().by_id(id)
			if not d.is_empty():
				row.add_child(TH.chip(str(d["name"])))
	if dep.size() < 4:
		var add := TH.button("+", "mini")
		add.pressed.connect(func():
			pick_person(func(p): G().assign(p, pid, false, true), "添加副手", _leader_pool(), false, {"peak_id": pid})
		)
		row.add_child(add)
	else:
		row.add_child(TH.label("已满", TH.FS_SMALL, TH.INK3))
	if not dep.is_empty():
		var cl := TH.button("清空", "mini")
		cl.pressed.connect(func():
			var pk: Dictionary = G().s["peaks"][pid]
			for id in (pk["deputy"] as Array).duplicate():
				var p := G().by_id(id)
				if not p.is_empty():
					G().unassign(p)
			pk["deputy"] = []
			G().changed.emit()
			_force = true
		)
		row.add_child(cl)
	body.add_child(row)


func _peak_outer(body: VBoxContainer, pid: String, st: Dictionary) -> void:
	var row := _peak_row("外门")
	var minus := TH.button("-", "mini")
	minus.pressed.connect(func():
		var st2: Dictionary = G().s["peaks"][pid]
		st2["outer"] = maxi(0, int(st2["outer"]) - 1)
		G().changed.emit()
		_force = true
	)
	row.add_child(minus)
	row.add_child(TH.label(str(int(st["outer"])), TH.FS_BASE, TH.INK, true))
	var plus := TH.button("+", "mini")
	plus.pressed.connect(func():
		var st2: Dictionary = G().s["peaks"][pid]
		st2["outer"] = mini(999, int(st2["outer"]) + 1)
		G().changed.emit()
		_force = true
	)
	row.add_child(plus)
	row.add_child(TH.label("在岗 %d 人" % G().outer_of(pid).size(), TH.FS_SMALL, TH.INK3))
	body.add_child(row)


func _peak_menial(body: VBoxContainer, pid: String, st: Dictionary) -> void:
	var row := _peak_row("杂役")
	var minus := TH.button("-", "mini")
	minus.pressed.connect(func():
		var st2: Dictionary = G().s["peaks"][pid]
		st2["menial"] = maxi(0, int(st2["menial"]) - 1)
		G().changed.emit()
		_force = true
	)
	row.add_child(minus)
	row.add_child(TH.label(str(int(st["menial"])), TH.FS_BASE, TH.INK, true))
	var plus := TH.button("+", "mini")
	plus.pressed.connect(func():
		var st2: Dictionary = G().s["peaks"][pid]
		st2["menial"] = mini(200, int(st2["menial"]) + 1)
		G().changed.emit()
		_force = true
	)
	row.add_child(plus)
	row.add_child(TH.label("在岗 %d 人" % int(st["menialOn"]), TH.FS_SMALL, TH.INK3))
	body.add_child(row)


func _peak_zhenxie(body: VBoxContainer, st: Dictionary) -> void:
	var s := G().s
	var tgt: Dictionary = DataCore.FIGHT[int(s["fightTarget"])]
	var names: Array = []
	for f in DataCore.FIGHT:
		names.append("%s（需%s+）" % [f["n"], DataCore.REALMS[int(f["need"])]])
	var r1 := _peak_row("除魔地")
	r1.add_child(_option(names, int(s["fightTarget"]), func(i):
		G().s["fightTarget"] = i
		G().s["peaks"]["fumo"]["progress"] = 0.0
		G().changed.emit()
		_force = true
	))
	body.add_child(r1)

	var bar_row := _peak_row("攻略")
	var bar := TH.progress_bar()
	bar.value = float(st["progress"])
	bar_row.add_child(bar)
	bar_row.add_child(TH.label("%d%%" % int(float(st["progress"])), TH.FS_SMALL, TH.INK2))
	body.add_child(bar_row)

	var lead := G().by_id(st["leader"])
	var r2 := _peak_row("境界要求")
	if lead.is_empty():
		r2.add_child(TH.label("未任命峰主", TH.FS_BASE, TH.INK3))
	elif int(lead["realm"]) < int(tgt["need"]):
		r2.add_child(TH.label("%s 不足 %s" % [G().realm_name(lead), DataCore.REALMS[int(tgt["need"])]], TH.FS_BASE, TH.RED))
	else:
		r2.add_child(TH.label("%s 已满足" % DataCore.REALMS[int(tgt["need"])], TH.FS_BASE, TH.GREEN))
	body.add_child(r2)

	var risk := G().fight_risk()
	var rc := TH.GREEN
	var rt := "轻松获胜"
	if risk > 0.6:
		rc = TH.RED
		rt = "非常危险"
	elif risk > 0.3:
		rc = TH.GOLD
		rt = "普普通通"
	var r3 := _peak_row("危险度")
	r3.add_child(TH.label(rt, TH.FS_BASE, rc))
	r3.add_child(TH.label("预期胜率 %d%%" % int((1.0 - risk) * 100.0), TH.FS_SMALL, TH.INK3))
	body.add_child(r3)

	body.add_child(TH.wrap_label("队伍武力 %s / 推荐 %s　探索效率 %.2f" % [
		GameCore.fmt_num(G().team_power("fumo")), GameCore.fmt_num(tgt["atk"]),
		G().team_eff("fumo", "explore")],
		TH.FS_SMALL, TH.INK3))


func _peak_xunyou(body: VBoxContainer, st: Dictionary) -> void:
	var sec_names: Array = []
	for f in DataCore.SECRETS:
		sec_names.append(str(f["n"]))
	var r1 := _peak_row("秘境")
	r1.add_child(_option(sec_names, int(st["secret"]), func(i):
		G().s["peaks"]["xunyou"]["secret"] = i
		G().s["peaks"]["xunyou"]["progress"] = 0.0
		G().changed.emit()
		_force = true
	))
	body.add_child(r1)

	var sec: Dictionary = DataCore.SECRETS[int(st["secret"])]
	var lead := G().by_id(st["leader"])
	var r2 := _peak_row("攻略")
	var bar := TH.progress_bar()
	bar.value = float(st["progress"])
	r2.add_child(bar)
	r2.add_child(TH.label("%d%%" % int(float(st["progress"])), TH.FS_SMALL, TH.INK2))
	body.add_child(r2)

	var r3 := _peak_row("境界要求")
	if lead.is_empty():
		r3.add_child(TH.label("未任命峰主", TH.FS_BASE, TH.INK3))
	elif int(lead["realm"]) < int(sec["need"]):
		r3.add_child(TH.label("%s 不足 %s" % [G().realm_name(lead), DataCore.REALMS[int(sec["need"])]], TH.FS_BASE, TH.RED))
	else:
		r3.add_child(TH.label("%s 已满足" % DataCore.REALMS[int(sec["need"])], TH.FS_BASE, TH.GREEN))
	body.add_child(r3)

	var power := G().team_power("xunyou")
	var risk := G().secret_risk(float(sec["atk"]), power)
	var rc := TH.GREEN
	var rt := "轻松获胜"
	if risk > 0.6:
		rc = TH.RED
		rt = "非常危险"
	elif risk > 0.3:
		rc = TH.GOLD
		rt = "普普通通"
	var r4 := _peak_row("危险度")
	r4.add_child(TH.label(rt, TH.FS_BASE, rc))
	r4.add_child(TH.label("预期胜率 %d%%" % int((1.0 - risk) * 100.0), TH.FS_SMALL, TH.INK3))
	body.add_child(r4)

	body.add_child(TH.wrap_label("队伍武力 %s / 推荐 %s　探索效率 %.2f" % [
		GameCore.fmt_num(power), GameCore.fmt_num(sec["atk"]),
		G().team_eff("xunyou", "explore")], TH.FS_SMALL, TH.INK3))


func _peak_danding(body: VBoxContainer, st: Dictionary) -> void:
	var names: Array = []
	for f in DataCore.PILLS:
		names.append(str(f["n"]))
	var r1 := _peak_row("丹方")
	r1.add_child(_option(names, int(st["pill"]), func(i):
		G().s["peaks"]["danding"]["pill"] = i
		G().s["peaks"]["danding"]["progress"] = 0.0
		G().changed.emit()
		_force = true
	))
	body.add_child(r1)
	var r2 := _peak_row("火候")
	var bar := TH.progress_bar()
	bar.value = float(st["progress"])
	r2.add_child(bar)
	r2.add_child(TH.label("%d%%" % int(float(st["progress"])), TH.FS_SMALL, TH.INK2))
	body.add_child(r2)


func _peak_baiqi(body: VBoxContainer, st: Dictionary) -> void:
	var r1 := _peak_row("品阶")
	r1.add_child(_option(DataCore.MLEVEL.duplicate(), int(st["equipLv"]), func(i):
		G().s["peaks"]["baiqi"]["equipLv"] = i
		G().s["peaks"]["baiqi"]["progress"] = 0.0
		G().changed.emit()
		_force = true
	))
	body.add_child(r1)
	var r2 := _peak_row("炉火")
	var bar := TH.progress_bar()
	bar.value = float(st["progress"])
	r2.add_child(bar)
	r2.add_child(TH.label("%d%%" % int(float(st["progress"])), TH.FS_SMALL, TH.INK2))
	body.add_child(r2)


func _peak_field(body: VBoxContainer, pid: String, st: Dictionary) -> void:
	var key := "herbLv" if pid == "shenyao" else "oreLv"
	var row := _peak_row("开辟")
	var minus := TH.button("-", "mini")
	minus.pressed.connect(func():
		var st2: Dictionary = G().s["peaks"][pid]
		st2[key] = maxi(0, int(st2[key]) - 1)
		G().changed.emit()
		_force = true
	)
	row.add_child(minus)
	row.add_child(TH.label(str(int(st[key])), TH.FS_BASE, TH.INK, true))
	var plus := TH.button("+", "mini")
	plus.pressed.connect(func():
		var st2: Dictionary = G().s["peaks"][pid]
		st2[key] = mini(30, int(st2[key]) + 1)
		G().changed.emit()
		_force = true
	)
	row.add_child(plus)
	row.add_child(TH.label("当前%s等级 %d（等级越高，产出品阶越好；上限 30）" % [
		("药田" if pid == "shenyao" else "矿道"), int(st[key])], TH.FS_SMALL, TH.INK3))
	body.add_child(row)
	# 开辟进度（满额自动提升品阶）
	var r2 := _peak_row("开辟进度")
	var bar := TH.progress_bar()
	bar.value = float(st["progress"])
	r2.add_child(bar)
	r2.add_child(TH.label("%d%%" % int(float(st["progress"])), TH.FS_SMALL, TH.INK2))
	body.add_child(r2)


# ── 门徒 ──────────────────────────────────────────────
func _job_label(p: Dictionary) -> String:
	# 返回名册/弹窗中显示的职务文本：
	# 掌门 / XX峰峰主 / XX峰副手 / XX峰外门 / 玄元峰内门 / 闲置外门
	if p["job"] == "leader":
		return "掌门"
	var pk_name := ""
	if p["peak"] != null:
		pk_name = str(DataCore.peak_by_id(str(p["peak"])).get("n", ""))
	if p["job"] == "fushou":
		return pk_name + "副手"
	elif p["job"] != null:
		# 旧档的 lingdui/zongguan/gezhu/louzhu 与新档 fengzhu 统一显示为峰主
		return pk_name + "峰主"
	elif p["peak"] != null:
		return pk_name + "外门"
	else:
		return "玄元峰内门" if p["inner"] else "闲置外门"


func _render_people() -> void:
	var list: Array = (G().s["people"] as Array).duplicate()
	list.sort_custom(_people_cmp)

	var body := TH.panel("门徒名册（%d）" % list.size())
	_content_body.add_child(TH.panel_of(body))

	var widths := [124.0, 110.0, 120.0, 92.0, 116.0, 64.0, 120.0, 108.0, 0.0]
	var heads := ["姓名", "境界", "灵根", "年龄/寿元", "武力/上限", "突破", "灵力/上限", "职务", "特质"]
	body.add_child(_table_row(heads, widths, null, true, false, Callable(), 12, [3, 4, 5, 6]))

	for p in list:
		var st_txt := ""
		if not p["alive"]:
			st_txt = "已陨落"
		elif p["fly"]:
			st_txt = "已飞升"
		elif p["dormant"]:
			st_txt = "休眠"

		var job := _job_label(p)

		var cells: Array = []
		cells.append(_cell("%s %s" % [p["name"], "女" if int(p["sex"]) == 1 else "男"], 124.0, TH.INK))
		cells.append(_cell(st_txt if st_txt != "" else G().realm_name(p), 110.0,
			TH.realm_color(int(p["realm"])) if st_txt == "" else TH.INK3))
		cells.append(_cell("%s%s" % [DataCore.LINGGEN[int(p["linggenIdx"])]["n"], "".join(p["elements"])],
			120.0, TH.lg_color(int(p["linggenIdx"]))))
		cells.append(_cell("%d/%d" % [int(p["age"]), G().lifespan_of(p)], 92.0, TH.INK2, true))
		cells.append(_cell("-" if st_txt != "" else "%s/%s" % [GameCore.fmt_num(G().atk_of(p)), GameCore.fmt_num(G().atk_max(p))], 116.0, TH.INK, true))
		cells.append(_cell("-" if st_txt != "" else "%d%%" % int(G().brk_rate(p) * 100.0), 64.0, TH.INK, true))
		cells.append(_cell("-" if st_txt != "" else "%s/%s" % [GameCore.fmt_num(float(p["qi"])), GameCore.fmt_num(G().qi_max(p))], 120.0, TH.INK, true))
		cells.append(_cell(job, 108.0, TH.INK2))
		var tg: Array = []
		for t in p["tags"]:
			tg.append(str(DataCore.TAGS[int(t)]["n"]))
		cells.append(_cell("、".join(tg) if not tg.is_empty() else "-", 0.0, TH.INK3))

		body.add_child(_table_row(cells, widths, p, false, st_txt != "", Callable(), 12, [3, 4, 5, 6]))


func _people_cmp(a: Dictionary, b: Dictionary) -> bool:
	if a["alive"] != b["alive"]:
		return a["alive"]
	var ja := 1000000000 if a["job"] == "leader" else 0
	var jb := 1000000000 if b["job"] == "leader" else 0
	return (jb + int(b["realm"]) * 100 + int(b["sub"])) < (ja + int(a["realm"]) * 100 + int(a["sub"]))


func _cell(text: String, w: float, color: Color, right: bool = false) -> Control:
	var l := TH.label(text, TH.FS_BASE, color)
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if w > 0.0:
		l.custom_minimum_size.x = w
		l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	else:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if right:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


func _table_row(cells: Array, widths: Array, person, header: bool, dead: bool = false,
		on_click: Callable = Callable(), sep: int = 8, right_cols: Array = []) -> Control:
	var row := Button.new()
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size.y = 26
	row.add_theme_stylebox_override("normal", TH.sb(TH.PAPER2 if header else Color(0, 0, 0, 0), TH.LINE, 0, 0, 4, 2))
	row.add_theme_stylebox_override("hover", TH.sb(TH.GOLD_L, TH.GOLD_L, 0, 0, 4, 2))
	row.add_theme_stylebox_override("pressed", TH.sb(TH.GOLD_L, TH.GOLD_L, 0, 0, 4, 2))
	row.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var h := TH.hbox(sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(h)

	if header:
		for i in cells.size():
			var l := TH.label(str(cells[i]), TH.FS_SMALL, TH.INK2, true)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if float(widths[i]) > 0.0:
				l.custom_minimum_size.x = float(widths[i])
				l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			else:
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if i in right_cols:
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			h.add_child(l)
		row.disabled = true
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		if dead:
			row.modulate = Color(1, 1, 1, 0.55)
		for c in cells:
			if c is Button:
				h.add_child(c)
			else:
				_ignore_mouse(c)
				h.add_child(c)
		if on_click.is_valid():
			# 选人弹窗：点整行直接触发回调
			row.pressed.connect(on_click.bind(person))
		elif person != null:
			var pid = person["id"]
			row.pressed.connect(func(): show_person(pid))
	return row


# ── 道具 ──────────────────────────────────────────────
func _render_items() -> void:
	var s := G().s
	var g := TH.grid(2)
	_content_body.add_child(g)

	# 灵草
	var hb := TH.panel("灵草")
	var hpc := TH.panel_of(hb)
	var any := false
	for i in DataCore.MLEVEL.size():
		if int(s["herbs"][i]) <= 0:
			continue
		any = true
		var price := int(floor((i + 1) * 12 * (1.0 + float(s["gongde"][9]) * 0.06)))
		var herb_names: String = " / ".join(DataCore.HERBS[i])
		hb.add_child(_item_row(herb_names, "×%d" % int(s["herbs"][i]),
			"卖出 %d" % price, func():
				G().sell_herb(i)
				_force = true
		))
	if not any:
		hb.add_child(TH.wrap_label("尚无存粮。在青芜峰任命峰主后每旬自动产出。", TH.FS_SMALL, TH.INK3))
	TH.grid_add(g, 0, hpc)

	# 灵矿
	var ob := TH.panel("灵矿")
	var opc := TH.panel_of(ob)
	any = false
	for i in DataCore.MLEVEL.size():
		if int(s["ores"][i]) <= 0:
			continue
		any = true
		var price := int(floor((i + 1) * 15 * (1.0 + float(s["gongde"][9]) * 0.06)))
		var ore_names: String = " / ".join(DataCore.ORES[i])
		ob.add_child(_item_row(ore_names, "×%d" % int(s["ores"][i]),
			"卖出 %d" % price, func():
				G().sell_ore(i)
				_force = true
		))
	if not any:
		ob.add_child(TH.wrap_label("尚无存料。在玄矿峰任命峰主后每旬自动产出。", TH.FS_SMALL, TH.INK3))
	TH.grid_add(g, 1, opc)

	# 丹药
	var pb := TH.panel("丹药")
	var ppc := TH.panel_of(pb)
	var keys: Array = (s["pills"] as Dictionary).keys()
	keys.sort()
	if keys.is_empty():
		pb.add_child(TH.wrap_label("尚无丹药。在丹宸峰任命峰主并选定丹方后炼制。", TH.FS_SMALL, TH.INK3))
	for k in keys:
		var pill: Dictionary = DataCore.PILLS[int(k)]
		var kk := int(k)
		pb.add_child(_item_row(str(pill["n"]), "×%d　%s" % [int(s["pills"][kk]), pill["desc"]],
			"给谁服用", func():
				pick_person(func(p): G().use_pill(kk, p["id"]), "选择服药弟子", G().alive_list())
		))
	TH.grid_add(g, 2, ppc)

	# 法宝
	var eb := TH.panel("法宝（公库 %d）" % (s["equips"] as Array).size())
	var epc := TH.panel_of(eb)
	if (s["equips"] as Array).is_empty():
		eb.add_child(TH.wrap_label("尚无法宝。在玄铸峰任命峰主后每旬铸造。", TH.FS_SMALL, TH.INK3))
	var shown := 0
	for i in (s["equips"] as Array).size():
		if shown >= 60:
			break
		shown += 1
		var e: Dictionary = s["equips"][i]
		var idx := i
		var attrs: Array = []
		for k in (e["attrs"] as Dictionary):
			attrs.append("%s+%d%%" % [DataCore.work_label(str(k)), int(float(e["attrs"][k]) * 100.0)])
		eb.add_child(_item_row(
			"%s%s%s" % [DataCore.MLEVEL[int(e["lv"])], e["name"], "（器灵）" if e["spirit"] else ""],
			"%s · %s" % [DataCore.EQUIP_SLOT[int(e["slot"])], " ".join(attrs)],
			"赐予", func():
				pick_person(func(p): G().equip_to(p["id"], idx), "赐予哪位弟子", G().alive_list())
		))
	TH.grid_add(g, 3, epc)

	# 功法
	var bb := TH.panel("功法（%d）" % (s["books"] as Array).size())
	_content_body.add_child(TH.panel_of(bb))
	if (s["books"] as Array).is_empty():
		bb.add_child(TH.wrap_label("尚无功法。在撰书阁指定撰写人，十年可成一卷。", TH.FS_SMALL, TH.INK3))
	for b in s["books"]:
		var attrs2: Array = []
		for k in (b["attrs"] as Dictionary):
			attrs2.append("%s +%d%%" % [DataCore.work_label(str(k)), int(float(b["attrs"][k]) * 100.0)])
		bb.add_child(_item_row("《%s》" % b["name"],
			"需灵根 %s · %s · 撰者 %s" % [
				("".join(b["req"]) if not (b["req"] as Array).is_empty() else "任意"),
				"、".join(attrs2), b["author"]],
			"", Callable()))


# ── 设置 ──────────────────────────────────────────────
func _render_settings() -> void:
	var s := G().s

	var gb := TH.panel("功德台")
	_content_body.add_child(TH.panel_of(gb))
	gb.add_child(TH.wrap_label("庇护民众 %s 人 · 当前功德 %s · 第 %d 轮回" % [
		GameCore.fmt_num(s["protect"]), GameCore.fmt_num(s["merit"]), int(s["cycle"])],
		TH.FS_SMALL, TH.INK3))
	gb.add_child(TH.wrap_label("功德建筑等级在新的轮回中也会保留。每级消耗随等级递增。", TH.FS_SMALL, TH.INK3))
	for i in DataCore.GONGDE.size():
		var gd: Dictionary = DataCore.GONGDE[i]
		var lv := int(s["gongde"][i])
		var cost := (lv + 1) * 10
		var btn := _item_row("%s lv%d" % [gd["n"], lv], str(gd["desc"]),
			"升级 %d 功德" % cost, func():
				if not G().upgrade_gongde(i): toast("功德不足")
				_force = true
		)
		gb.add_child(btn)
	var foot := TH.hbox(8)
	foot.add_child(TH.spacer(0, 0, true))
	var rein := TH.button("进入新的轮回", "danger")
	rein.pressed.connect(func():
		_open_confirm("进入新的轮回？宗门将重置，仅保留功德与功德建筑等级。", func():
			G().reincarnate()
			_log_len = 0
			_action_ready = false
			close_modal()
			_force = true
		, "确定")
	)
	foot.add_child(rein)
	gb.add_child(foot)

	# 天梯
	var tb := TH.panel("天梯")
	_content_body.add_child(TH.panel_of(tb))
	tb.add_child(TH.wrap_label("每有一名弟子飞升，天梯修复一层，赐下仙宝与功德。", TH.FS_SMALL, TH.INK3))
	for i in DataCore.TIANTI.size():
		var done := i < int(s["tianti"])
		tb.add_child(_item_row(
			"%d. %s%s" % [i + 1, DataCore.TIANTI[i], "  ✓" if done else ""],
			DataCore.TIANTI_ITEM[i] if done else "未修复", "", Callable(),
			TH.GOLD if done else TH.INK3))

	# 速度
	var spb := TH.panel("推进速度")
	_content_body.add_child(TH.panel_of(spb))
	var opts := TH.hbox(6)
	for i in DataCore.SPEED.size():
		var sp: Dictionary = DataCore.SPEED[i]
		var b := TH.button("%s（%dms/旬）" % [sp["n"], int(sp["ms"])], "on" if int(s["speed"]) == i else "")
		b.pressed.connect(func():
			G().set_speed(i)
			_force = true
		)
		opts.add_child(b)
	spb.add_child(opts)
	spb.add_child(TH.wrap_label("空格键可暂停/继续，数字键 1-5 切换页签。", TH.FS_SMALL, TH.INK3))

	# 存档
	var svb := TH.panel("存档")
	_content_body.add_child(TH.panel_of(svb))
	var row := TH.hbox(8)
	var b1 := TH.button("保存进度")
	b1.pressed.connect(func():
		XiuxianGlobals.save_now()
		toast("已存档")
	)
	row.add_child(b1)
	var b2 := TH.button("读取存档")
	b2.pressed.connect(func():
		if XiuxianGlobals.load_saved():
			_log_len = 0
			_action_ready = false
			_force = true
			toast("已读取")
		else:
			toast("没有存档")
	)
	row.add_child(b2)
	var b3 := TH.button("重开宗门", "danger")
	b3.pressed.connect(func():
		var gain := 0
		if not G().s.is_empty():
			gain = G().calc_reincarnate_merit()
		_open_confirm("重开宗门将结算功德（约 %d），当前宗门存档会被清除，确定吗？" % gain, func():
			XiuxianGlobals.set_running(false)
			if not G().s.is_empty():
				G().s["merit"] = float(G().s["merit"]) + G().calc_reincarnate_merit()
				G().save()
			G().clear_save()
			close_modal()
			_content_body.get_children().map(func(c): pass)
			_clear(_content_body)
			open_create()
		, "确定重开")
	)
	row.add_child(b3)
	svb.add_child(row)
	svb.add_child(TH.wrap_label("进度自动保存在本地，每年写入一次。", TH.FS_SMALL, TH.INK3))


# ═══════════════════════════════════════════════════════
# 通用小部件
# ═══════════════════════════════════════════════════════

func _peak_row(label_text: String) -> HBoxContainer:
	var h := TH.hbox(6)
	var l := TH.label(label_text, TH.FS_BASE, TH.INK2)
	l.custom_minimum_size.x = 54
	h.add_child(l)
	return h


func _item_row(name: String, note: String, btn_text: String, cb: Callable, name_color: Color = TH.INK) -> HBoxContainer:
	var h := TH.hbox(10)
	h.add_child(TH.divider())  # 占位会被替换
	h.remove_child(h.get_child(0))

	var nl := TH.label(name, TH.FS_BASE, name_color)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nl)
	if note != "":
		h.add_child(TH.label(note, TH.FS_SMALL, TH.INK3))
	if btn_text != "" and cb.is_valid():
		var b := TH.button(btn_text, "mini")
		b.pressed.connect(cb)
		h.add_child(b)
	var wrap := TH.hbox(10)
	return h


func _option(items: Array, sel: int, cb: Callable) -> OptionButton:
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.add_theme_font_override("font", TH.font())
	ob.add_theme_font_size_override("font_size", TH.FS_BASE)
	ob.add_theme_color_override("font_color", TH.INK)
	ob.add_theme_color_override("font_hover_color", TH.INK)
	ob.add_theme_color_override("font_pressed_color", TH.INK)
	ob.add_theme_stylebox_override("normal", TH.sb(TH.PAPER2, TH.LINE2, 1, 4, 10, 3))
	ob.add_theme_stylebox_override("hover", TH.sb(TH.GOLD_L, TH.GOLD, 1, 4, 10, 3))
	ob.add_theme_stylebox_override("pressed", TH.sb(TH.GOLD_L, TH.GOLD, 1, 4, 10, 3))
	ob.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for it in items:
		ob.add_item(str(it))
	ob.selected = clampi(sel, 0, maxi(0, items.size() - 1))
	ob.item_selected.connect(cb)
	var pop := ob.get_popup()
	pop.add_theme_font_override("font", TH.font())
	pop.add_theme_font_size_override("font_size", TH.FS_BASE)
	pop.add_theme_color_override("font_color", TH.INK)
	pop.add_theme_stylebox_override("panel", TH.sb(TH.PAPER2, TH.LINE2, 1, 4, 6, 6))
	pop.add_theme_stylebox_override("hover", TH.sb(TH.GOLD_L, TH.GOLD_L, 0, 3, 8, 3))
	return ob


func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)


func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


func _esc(t: String) -> String:
	return t.replace("[", "[lb]")


func toast(msg: String) -> void:
	_toast_label.text = msg
	_toast_panel.visible = true
	_toast_timer = 1.6
	# 顶端居中
	await get_tree().process_frame
	_toast_panel.position.x = (size.x - _toast_panel.size.x) * 0.5
	_toast_panel.position.y = 58


# ═══════════════════════════════════════════════════════
# 弹窗
# ═══════════════════════════════════════════════════════

func _render_modal() -> void:
	_clear(_modal_root)
	if _modal == MODAL_NONE:
		_modal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	_modal_root.mouse_filter = Control.MOUSE_FILTER_STOP

	var mask := ColorRect.new()
	mask.color = TH.MASK
	mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_root.add_child(mask)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_root.add_child(center)

	var holder := MarginContainer.new()
	holder.add_theme_constant_override("margin_top", 40)
	holder.add_theme_constant_override("margin_bottom", 40)
	center.add_child(holder)

	match _modal:
		MODAL_CREATE: holder.add_child(_build_create())
		MODAL_PICK: holder.add_child(_build_pick())
		MODAL_PERSON: holder.add_child(_build_person())
		MODAL_CONFIRM: holder.add_child(_build_confirm())
		MODAL_CHAMPION: holder.add_child(_build_champion())


func _modal_shell(width: float) -> Array:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", TH.sb(TH.PAPER2, TH.LINE2, 1, 8, 22, 20))
	pc.custom_minimum_size.x = width
	var col := TH.vbox(6)
	pc.add_child(col)
	return [pc, col]


func _modal_footer(col: VBoxContainer, buttons: Array) -> void:
	var f := TH.hbox(8)
	f.add_child(TH.spacer(0, 0, true))
	for b in buttons:
		f.add_child(b)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 12)
	m.add_child(f)
	col.add_child(m)


func open_modal(kind: int) -> void:
	_modal = kind
	_render_modal()


func close_modal() -> void:
	_modal = MODAL_NONE
	_modal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clear(_modal_root)


func _open_confirm(text: String, cb: Callable, ok_text: String = "确定", cancel_cb: Callable = Callable()) -> void:
	_confirm_text = text
	_confirm_cb = cb
	_confirm_ok = ok_text
	_confirm_cancel_cb = cancel_cb
	open_modal(MODAL_CONFIRM)


var _confirm_ok := "确定"
var _confirm_cancel_cb: Callable = Callable()


func _build_confirm() -> Control:
	var sh := _modal_shell(420)
	var col: VBoxContainer = sh[1]
	col.add_child(TH.label("提示", TH.FS_H2, TH.INK, true))
	col.add_child(TH.wrap_label(_confirm_text, TH.FS_BASE, TH.INK2))
	var no := TH.button("取消")
	no.pressed.connect(func():
		close_modal()
		if _confirm_cancel_cb.is_valid():
			_confirm_cancel_cb.call()
	)
	var yes := TH.button(_confirm_ok, "primary")
	yes.pressed.connect(func():
		_modal = MODAL_NONE
		if _confirm_cb.is_valid():
			_confirm_cb.call()
		else:
			close_modal()
	)
	_modal_footer(col, [no, yes])
	return sh[0]


# ── 宗门大比 · 选奖品 ──────────────────────────────────
func _open_champion_modal() -> void:
	_champion_was_running = XiuxianGlobals.is_running()
	if _champion_was_running:
		XiuxianGlobals.set_running(false)   # 暂停推进，等玩家选奖品
	open_modal(MODAL_CHAMPION)


func _build_champion() -> Control:
	var sh := _modal_shell(700)
	var col: VBoxContainer = sh[1]
	var pc: Dictionary = G().s.get("pending_champion", {})
	var wname: String = str(pc.get("name", "弟子"))
	col.add_child(TH.label("宗门大比 · 择奖品", TH.FS_H2, TH.GOLD, true))
	col.add_child(TH.wrap_label(
		"%s在门派大比中脱颖而出，拜入内门。请为胜者择一件法宝：" % wname,
		TH.FS_SMALL, TH.INK2))

	var prizes: Array = pc.get("prizes", [])
	var widths := [240.0, 100.0, 220.0, 80.0]
	col.add_child(_table_row(["法宝", "品阶", "属性", ""], widths, null, true))
	for i in prizes.size():
		var e: Dictionary = prizes[i]
		var lv: int = int(e.get("lv", 0))
		var lvname: String = DataCore.MLEVEL[lv]
		var attr_txt: String = ""
		var attrs: Dictionary = e.get("attrs", {})
		for k in attrs:
			attr_txt += "%s +%.0f%%   " % [GameCore.attr_cn(str(k)), float(attrs[k]) * 100.0]
		if attr_txt == "":
			attr_txt = "无属性"
		var choose := TH.button("选择", "mini")
		choose.pressed.connect(_pick_prize.bind(i))
		var cells := [
			_cell(str(e.get("name", "")), 240.0, TH.INK),
			_cell("%s%s" % [lvname, " · 通灵" if e.get("spirit", false) else ""], 100.0, TH.realm_color(lv)),
			_cell(attr_txt, 220.0, TH.INK2),
			choose,
		]
		col.add_child(_table_row(cells, widths, null, false, false, Callable()))

	var cancel := TH.button("稍后（随机赐予）")
	cancel.pressed.connect(func():
		G().resolve_champion(-1)
		close_modal()
		if _champion_was_running:
			XiuxianGlobals.set_running(true)
		_champion_was_running = false
		_force = true
	)
	_modal_footer(col, [cancel])
	return sh[0]


func _pick_prize(idx: int, _ignored = null) -> void:
	G().resolve_champion(idx)
	close_modal()
	if _champion_was_running:
		XiuxianGlobals.set_running(true)
	_champion_was_running = false
	_force = true


# ── 选人 ──────────────────────────────────────────────
func pick_person(cb: Callable, title: String, list: Array, allow_none: bool = false, ctx: Dictionary = {}) -> void:
	var seen := {}
	var uniq: Array = []
	for p in list:
		if seen.has(p["id"]):
			continue
		seen[p["id"]] = true
		uniq.append(p)
	_modal_title = title
	_modal_pick = uniq
	_modal_pick_cb = cb
	_modal_pick_ctx = ctx
	open_modal(MODAL_PICK)


func _build_pick() -> Control:
	var sh := _modal_shell(760)
	var col: VBoxContainer = sh[1]
	col.add_child(TH.label(_modal_title, TH.FS_H2, TH.INK, true))
	col.add_child(TH.label("点击选择", TH.FS_SMALL, TH.INK3))

	var show_eff := false
	var eff_key := ""
	var eff_label := ""
	if _modal_pick_ctx.has("peak_id"):
		var pk: Dictionary = DataCore.peak_by_id(str(_modal_pick_ctx["peak_id"]))
		# 撰书阁选择撰写人不显示效率列
		if not pk.is_empty() and pk.has("eff") and pk["id"] != "zhuanzhu":
			show_eff = true
			eff_key = str(pk["eff"])
			eff_label = DataCore.work_label(eff_key) + "效率"

	var widths: Array
	var headers: Array
	var right_cols: Array
	if show_eff:
		widths = [130.0, 100.0, 110.0, 80.0, 120.0, 80.0]
		headers = ["姓名", "境界", "灵根", "武力", "职务", eff_label]
		right_cols = [3, 5]
	else:
		widths = [130.0, 100.0, 110.0, 80.0, 196.0]
		headers = ["姓名", "境界", "灵根", "武力", "职务"]
		right_cols = [3]

	# 人员列表包进滚动区，防止选项多时把底部「取消」挤出可视区
	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.custom_minimum_size.y = 360
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	list_scroll.mouse_filter = Control.MOUSE_FILTER_PASS

	var list_body := TH.vbox(0)
	list_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	list_scroll.add_child(list_body)
	col.add_child(list_scroll)

	list_body.add_child(_table_row(headers, widths, null, true, false, Callable(), 12, right_cols))
	if _modal_pick.is_empty():
		list_body.add_child(TH.wrap_label("（无可用人选）", TH.FS_SMALL, TH.INK3))
	for p in _modal_pick:
		var job := _job_label(p)
		var cells: Array = [
			_cell(str(p["name"]), widths[0], TH.INK),
			_cell(G().realm_name(p), widths[1], TH.realm_color(int(p["realm"]))),
			_cell("%s%s" % [DataCore.LINGGEN[int(p["linggenIdx"])]["n"], "".join(p["elements"])], widths[2], TH.lg_color(int(p["linggenIdx"]))),
			_cell(GameCore.fmt_num(G().atk_of(p)), widths[3], TH.INK, true),
			_cell(job, widths[4], TH.INK2),
		]
		if show_eff:
			cells.append(_cell("%.2f" % G().eff(p, eff_key), widths[5], TH.INK, true))
		list_body.add_child(_table_row(cells, widths, p, false, false, func(pp):
			_modal_pick_cb.call(pp)
			close_modal()
			_force = true
			_dirty = true
		, 12, right_cols))

	var cancel := TH.button("取消")
	cancel.pressed.connect(close_modal)
	_modal_footer(col, [cancel])
	return sh[0]


# ── 弟子详情 ──────────────────────────────────────────
func show_person(id) -> void:
	_person_id = id
	open_modal(MODAL_PERSON)


func _kv(col: VBoxContainer, key: String, value: String, val_color: Color = TH.INK) -> void:
	var h := TH.hbox(10)
	var k := TH.label(key, TH.FS_BASE, TH.INK2)
	k.custom_minimum_size.x = 66
	h.add_child(k)
	h.add_child(TH.wrap_label(value, TH.FS_BASE, val_color))
	col.add_child(h)


func _build_person() -> Control:
	var p := G().by_id(_person_id)
	if p.is_empty():
		var sh0 := _modal_shell(420)
		var c0: VBoxContainer = sh0[1]
		c0.add_child(TH.label("该弟子已不在名册", TH.FS_H2, TH.INK, true))
		var cl0 := TH.button("关闭")
		cl0.pressed.connect(close_modal)
		_modal_footer(c0, [cl0])
		return sh0[0]

	var sh := _modal_shell(680)
	var col: VBoxContainer = sh[1]

	var st_txt := ""
	if not p["alive"]:
		st_txt = "已陨落"
	elif p["fly"]:
		st_txt = "已飞升"
	elif p["dormant"]:
		st_txt = "休眠中"

	var title := TH.hbox(10)
	title.add_child(TH.label(str(p["name"]), TH.FS_H2, TH.INK, true))
	title.add_child(TH.label("%s · %s" % ["女" if int(p["sex"]) == 1 else "男",
		DataCore.FAMI[int(p["famiIdx"])]["n"]], TH.FS_SMALL, TH.INK3))
	col.add_child(title)

	var sub := "%s · %d岁 / 寿元 %d" % [
		st_txt if st_txt != "" else G().realm_name(p), int(p["age"]), G().lifespan_of(p)]
	col.add_child(TH.label(sub, TH.FS_SMALL, TH.INK3))

	col.add_child(TH.divider())
	_kv(col, "灵根", "%s（%s）" % [DataCore.LINGGEN[int(p["linggenIdx"])]["n"],
		"、".join(p["elements"])], TH.lg_color(int(p["linggenIdx"])))
	_kv(col, "出身", "%s — %s" % [DataCore.FAMI[int(p["famiIdx"])]["n"],
		DataCore.FAMI[int(p["famiIdx"])]["desc"]])
	var tg: Array = []
	for t in p["tags"]:
		var td: Dictionary = DataCore.TAGS[int(t)]
		tg.append("%s（%s）" % [td["n"], td["desc"]])
	_kv(col, "特质", "　".join(tg) if not tg.is_empty() else "无")
	var job := _job_label(p)
	_kv(col, "职务", job)
	var rel: Array = []
	if p["master"] != null:
		var m := G().by_id(p["master"])
		if not m.is_empty():
			rel.append("师尊 %s" % m["name"])
	if p["spouse"] != null:
		var sp := G().by_id(p["spouse"])
		if not sp.is_empty():
			rel.append("道侣 %s" % sp["name"])
	_kv(col, "亲缘", "　".join(rel) if not rel.is_empty() else "无")

	# 师徒 / 子嗣
	var apps: Array = []
	for aid in p["apprentices"]:
		var ap := G().by_id(aid)
		if not ap.is_empty():
			apps.append(ap["name"])
	if not apps.is_empty():
		_kv(col, "徒弟", "　".join(apps))
	var kids: Array = []
	for q in G().s["people"]:
		if q["alive"] and not q["fly"] and (q["parents"] as Array).has(p["id"]):
			kids.append(q["name"])
	if not kids.is_empty():
		_kv(col, "子嗣", "　".join(kids))
	if p["alive"] and not p["fly"] and not p["dormant"]:
		var rel_row := TH.hbox(8)
		if p["master"] == null:
			var ba := TH.button("拜师", "mini")
			ba.pressed.connect(func():
				pick_person(func(m): G().set_master(p["id"], m["id"]), "选择师尊",
					G().alive_list().filter(func(x): return int(x["id"]) != int(p["id"])), false)
			)
			rel_row.add_child(ba)
		else:
			var ub := TH.button("解除师徒", "mini")
			ub.pressed.connect(func():
				G().set_master(p["id"], null)
				_force = true
			)
			rel_row.add_child(ub)
		var ta := TH.button("收徒", "mini")
		ta.pressed.connect(func():
			pick_person(func(m): G().set_master(m["id"], p["id"]), "选择徒弟",
				G().alive_list().filter(func(x): return int(x["id"]) != int(p["id"])), false)
		)
		rel_row.add_child(ta)
		col.add_child(rel_row)

	# 属性栅格
	col.add_child(TH.divider())
	var attrs := [
		["灵力", "%s / %s" % [GameCore.fmt_num(float(p["qi"])), GameCore.fmt_num(G().qi_max(p))]],
		["修炼效率", "%.2f" % G().eff(p, "cultivate")],
		["武力", "%s / %s" % [GameCore.fmt_num(G().atk_of(p)), GameCore.fmt_num(G().atk_max(p))]],
		["突破几率", "%d%%" % int(G().brk_rate(p) * 100.0)],
		["渡劫死亡率", "%d%%" % int(G().death_rate(p) * 100.0)],
		["探索速度", "%.2f" % G().eff(p, "explore")],
		["种植效率", "%.2f" % G().eff(p, "plant")],
		["采矿效率", "%.2f" % G().eff(p, "mine")],
		["炼丹速度", "%.2f" % G().eff(p, "refine")],
		["炼器效率", "%.2f" % G().eff(p, "forge")],
		["心情", "%d/100" % int(p["mood"])],
	]
	var grid := TH.hbox(24)
	for c in 2:
		var colv := TH.vbox(2)
		colv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(colv)
	for i in attrs.size():
		var h := TH.hbox(10)
		h.add_child(TH.label(str(attrs[i][0]), TH.FS_SMALL, TH.INK3))
		h.add_child(TH.spacer(0, 0, true))
		h.add_child(TH.label(str(attrs[i][1]), TH.FS_BASE, TH.INK, true))
		(grid.get_child(i % 2) as Node).add_child(h)
	col.add_child(grid)

	# 法宝
	col.add_child(TH.divider())
	col.add_child(TH.label("法宝", TH.FS_H4, TH.INK, true))
	for i in 5:
		var row := TH.hbox(10)
		var nl := TH.label(str(DataCore.EQUIP_SLOT[i]), TH.FS_BASE, TH.INK2)
		nl.custom_minimum_size.x = 66
		row.add_child(nl)
		var e = p["equip"][i]
		if e != null:
			var attrs3: Array = []
			for k in (e["attrs"] as Dictionary):
				attrs3.append("%s+%d%%" % [DataCore.work_label(str(k)), int(float(e["attrs"][k]) * 100.0)])
			row.add_child(TH.label("%s%s  %s" % [DataCore.MLEVEL[int(e["lv"])], e["name"], " ".join(attrs3)],
				TH.FS_SMALL, TH.INK))
			var ub := TH.button("卸下", "mini")
			var slot := i
			ub.pressed.connect(func():
				G().unequip(_person_id, slot)
				_force = true
			)
			row.add_child(ub)
		else:
			row.add_child(TH.label("—", TH.FS_BASE, TH.INK3))
		col.add_child(row)

	# 底部操作
	var btns: Array = []
	if not p["alive"] or p["dormant"]:
		var r0 := TH.button("九转还魂丹复活")
		r0.pressed.connect(func():
			G().revive(_person_id, 0)
			_force = true
		)
		btns.append(r0)
		var r1 := TH.button("仙灵延寿丹续命")
		r1.pressed.connect(func():
			G().revive(_person_id, 1)
			_force = true
		)
		btns.append(r1)
	if p["alive"] and not p["fly"] and not p["dormant"] and p["job"] != "leader":
		var ml := TH.button("立为掌门")
		ml.pressed.connect(func():
			G().set_leader(_person_id)
			close_modal()
			_force = true
		)
		btns.append(ml)
	if p["alive"] and not p["fly"] and p["job"] != "leader":
		var ua := TH.button("解除职务")
		ua.pressed.connect(func():
			G().unassign(p)
			close_modal()
			_force = true
		)
		btns.append(ua)
	var cl := TH.button("关闭")
	cl.pressed.connect(close_modal)
	btns.append(cl)
	_modal_footer(col, btns)
	return sh[0]


# ── 捏人开局 ──────────────────────────────────────────
## 根据 _cfg 返回灵根显示名（如「火水木三灵根」「变异雷天灵根」）
func _linggen_display_name(cfg: Dictionary) -> String:
	var idx := int(cfg.get("linggen", 0))
	var lg: Dictionary = DataCore.LINGGEN[idx]
	var name: String = lg["n"]
	if name == "杂灵根":
		return name
	var elements: Array = cfg.get("linggen_elements", [])
	var es := ""
	for e in elements:
		es += str(e)
	if name.begins_with("变异"):
		# 变异天灵根 -> 变异{属性}天灵根；变异灵根 -> 变异{属性}灵根
		if name == "变异天灵根":
			return "变异%s天灵根" % es
		return "变异%s灵根" % es
	return "%s%s" % [es, name]


## 建宗界面当前可用功德
func _create_available_merit() -> float:
	var base := float(_cfg.get("base_merit", 0.0))
	var tag := int(_cfg.get("tag_merit_cost", 0))
	var lg := int(_cfg.get("linggen_merit_spent", 0))
	return maxf(0.0, base - tag - lg)


func open_create() -> void:
	if _cfg.is_empty():
		var g := G()
		var linggen := g._roll_linggen()
		_cfg = {
			"name": "龙傲天", "sectName": "凌霄宗", "sex": 0,
			"linggen": linggen,
			"linggen_elements": g.roll_linggen_elements(linggen),
			"linggen_rerolls": 0,
			"linggen_merit_spent": 0,
			"fami": g._ri(0, 2),
			"tags": [],
			"tag_merit_cost": 0,
			"base_merit": maxf(0.0, float(G().s.get("merit", 0.0))),
		}
	open_modal(MODAL_CREATE)


func _build_create() -> Control:
	var sh := _modal_shell(660)
	var col: VBoxContainer = sh[1]

	col.add_child(TH.label("建立宗门", TH.FS_H2, TH.INK, true))
	col.add_child(TH.label("设定掌门与宗门名，之后不可更改姓名", TH.FS_SMALL, TH.INK3))

	# 姓名 / 宗派名
	var names := TH.hbox(12)
	for cfg_key in [["name", "掌门姓名"], ["sectName", "宗派名"]]:
		var fv := TH.vbox(3)
		fv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fv.add_child(TH.label(str(cfg_key[1]), TH.FS_SMALL, TH.INK2))
		var le := LineEdit.new()
		le.text = str(_cfg[cfg_key[0]])
		le.max_length = 6
		le.add_theme_font_override("font", TH.font())
		le.add_theme_font_size_override("font_size", TH.FS_BASE)
		le.add_theme_color_override("font_color", TH.INK)
		le.add_theme_color_override("caret_color", TH.INK)
		le.add_theme_stylebox_override("normal", TH.sb(TH.PAPER2, TH.LINE2, 1, 4, 8, 5))
		le.add_theme_stylebox_override("focus", TH.sb(TH.PAPER2, TH.GOLD, 1, 4, 8, 5))
		var kk := str(cfg_key[0])
		le.text_changed.connect(func(t):
			_cfg[kk] = t.strip_edges()
		)
		fv.add_child(le)
		names.add_child(fv)
	col.add_child(names)

	# 性别
	col.add_child(TH.label("性别", TH.FS_SMALL, TH.INK2))
	var sex_row := TH.hbox(6)
	for pair in [["男", 0], ["女", 1]]:
		var b := TH.button(str(pair[0]), "on" if int(_cfg["sex"]) == int(pair[1]) else "")
		var v := int(pair[1])
		b.pressed.connect(func():
			_cfg["sex"] = v
			_refresh_create()
		)
		sex_row.add_child(b)
	col.add_child(sex_row)

	# 灵根
	var lg: Dictionary = DataCore.LINGGEN[int(_cfg["linggen"])]
	col.add_child(TH.label("灵根（影响修炼效率与武力，可点击转动）", TH.FS_SMALL, TH.INK2))
	var lg_row := TH.hbox(10)
	var free_remaining := maxi(0, 3 - int(_cfg.get("linggen_rerolls", 0)))
	var rr_text := "转动 %s" % _linggen_display_name(_cfg)
	if free_remaining > 0:
		rr_text += "（免费%d/3）" % (3 - int(_cfg.get("linggen_rerolls", 0)))
	else:
		rr_text += "（消耗1功德）"
	var rr := TH.button(rr_text)
	rr.pressed.connect(func():
		var rerolls := int(_cfg.get("linggen_rerolls", 0))
		if rerolls >= 3:
			if _create_available_merit() < 1.0:
				toast("功德不足")
				return
			_cfg["linggen_merit_spent"] = int(_cfg.get("linggen_merit_spent", 0)) + 1
		_cfg["linggen_rerolls"] = rerolls + 1
		_cfg["linggen"] = G()._roll_linggen()
		_cfg["linggen_elements"] = G().roll_linggen_elements(int(_cfg["linggen"]))
		_refresh_create()
	)
	lg_row.add_child(rr)
	lg_row.add_child(TH.label("修炼效率 ×%.2f　武力 ×%.2f" % [
		float(lg["rate"]), float(lg["atk"])], TH.FS_SMALL, TH.INK3))
	col.add_child(lg_row)

	# 出身（建立宗门仅可于 异界 / 乡野农民 / 修真世家 三者中选）
	col.add_child(TH.label("出身", TH.FS_SMALL, TH.INK2))
	var fami_grid := _flow()
	for fi in [0, 1, 2]:
		var f: Dictionary = DataCore.FAMI[fi]
		var b := TH.button(str(f["n"]), "on" if int(_cfg["fami"]) == fi else "")
		b.tooltip_text = str(f["desc"])
		b.pressed.connect(func():
			_cfg["fami"] = fi
			_refresh_create()
		)
		fami_grid.add_child(b)
	col.add_child(fami_grid)
	col.add_child(TH.label(str(DataCore.FAMI[int(_cfg["fami"])]["desc"]), TH.FS_SMALL, TH.INK3))

	# 功德余额提示
	col.add_child(TH.label("可用功德 %d" % int(_create_available_merit()), TH.FS_SMALL, TH.INK2))

	# 特质
	col.add_child(TH.label("特质（可选至多 3 个，可不选）", TH.FS_SMALL, TH.INK2))
	var tag_scroll := TH.scroll()
	tag_scroll.custom_minimum_size.y = 150
	var tag_grid := _flow()
	tag_scroll.add_child(tag_grid)
	for i in DataCore.TAGS.size():
		var t: Dictionary = DataCore.TAGS[i]
		var tags: Array = _cfg["tags"]
		var sel: bool = tags.has(i)
		var cost := int(t.get("cost", 0))
		var cost_txt: String
		if cost > 0:
			cost_txt = "功德-%d" % cost
		elif cost < 0:
			cost_txt = "功德+%d" % -cost
		else:
			cost_txt = "功德0"
		var b := TH.button("%s  %s  %s" % [t["n"], t["desc"], cost_txt], "on" if sel else "mini")
		var ti := i
		b.pressed.connect(func():
			var arr: Array = _cfg["tags"]
			if arr.has(ti):
				arr.erase(ti)
			elif arr.size() < 3:
				if cost > _create_available_merit():
					toast("功德不足")
					return
				arr.append(ti)
			var total := 0
			for ti2 in arr:
				total += int(DataCore.TAGS[int(ti2)].get("cost", 0))
			_cfg["tag_merit_cost"] = total
			_refresh_create()
		)
		tag_grid.add_child(b)
	col.add_child(tag_scroll)
	var selected: Array = _cfg["tags"]
	var tag_total := int(_cfg.get("tag_merit_cost", 0))
	var avail := int(_create_available_merit())
	var hint_txt: String
	if tag_total >= 0:
		hint_txt = "已选 %d/3，消耗功德 %d，可用功德 %d" % [selected.size(), tag_total, avail]
	else:
		hint_txt = "已选 %d/3，额外功德 %d，可用功德 %d" % [selected.size(), -tag_total, avail]
	col.add_child(TH.label(hint_txt, TH.FS_SMALL, TH.INK3))

	var start := TH.button("开宗立派", "primary")
	start.pressed.connect(func():
		var tag_cost := int(_cfg.get("tag_merit_cost", 0))
		_cfg["merit_cost"] = max(0, tag_cost) + int(_cfg.get("linggen_merit_spent", 0))
		XiuxianGlobals.start_new(_cfg)
		_log_len = 0
		_action_ready = false
		tab = "action"
		close_modal()
		_force = true
		_dirty = true
	)
	_modal_footer(col, [start])
	return sh[0]


func _refresh_create() -> void:
	_clear(_modal_root)
	_render_modal()


## 自动换行的横向流式容器（对应 CSS flex-wrap）
func _flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return f


# ═══════════════════════════════════════════════════════
# 帧循环
# ═══════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast_panel.visible = false
			_toast_panel.position.x = (size.x - _toast_panel.size.x) * 0.5

	if _scroll_frames > 0:
		var vb := _content.get_v_scroll_bar()
		_content.scroll_vertical = int(maxf(0.0, vb.max_value))
		_scroll_frames -= 1

	if _scroll_top_frames > 0 and not _dirty:
		_content.scroll_vertical = 0
		_scroll_top_frames -= 1

	if _dirty and _can_rebuild():
		var now := Time.get_ticks_msec()
		if _force or now - _last_rebuild_ms >= REBUILD_MS:
			_last_rebuild_ms = now
			_dirty = false
			_force = false
			render_all()


## 鼠标按下时不要重建，否则会在 mouse-down 与 mouse-up 之间销毁按钮、吞掉这次点击
func _can_rebuild() -> bool:
	if _modal == MODAL_CREATE:
		return false   # 捏人界面含输入框，重建会丢焦点
	return not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_SPACE:
			if _modal == MODAL_NONE:
				XiuxianGlobals.toggle()
				_force = true
				get_viewport().set_input_as_handled()
		elif k.keycode >= KEY_1 and k.keycode <= KEY_5:
			if _modal == MODAL_NONE:
				_goto_tab(str(TABS[k.keycode - KEY_1][0]))
				get_viewport().set_input_as_handled()
		elif k.keycode == KEY_ESCAPE:
			if _modal == MODAL_PERSON or _modal == MODAL_PICK or _modal == MODAL_CONFIRM:
				close_modal()
				get_viewport().set_input_as_handled()
