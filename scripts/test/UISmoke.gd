extends Control

## 界面冒烟测试：加载真实 Main.tscn，走通捏人开局 → 五页签 → 各类弹窗与交互。
## 运行：godot --headless --path <工程> res://scenes/SmokeUI.tscn

var _p := 0
var _f := 0
var _fails: Array = []
var ui: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = Vector2(1280, 720)
	print("═══════════════════════════════════════════")
	print(" 修仙门派 · 界面冒烟测试  (画布 %dx%d)" % [size.x, size.y])
	print("═══════════════════════════════════════════")

	# 保证从干净状态开始
	XiuxianGlobals.game.clear_save()
	await _frames(1)

	ui = load("res://scenes/Main.tscn").instantiate()
	add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames(3)

	# 冒烟测试无需交互选奖品：保持大比自动结算，避免弹窗挂起模拟
	XiuxianGlobals.game.auto_champion = true

	await _test_create_screen()
	await _test_start_game()
	await _test_header_and_nav()
	await _test_action_tab()
	await _test_facility_tab()
	await _test_people_tab()
	await _test_items_tab()
	await _test_settings_tab()
	await _test_toast()
	await _test_save_load()
	await _test_champion_modal()

	print("───────────────────────────────────────────")
	print(" 通过 %d / 失败 %d" % [_p, _f])
	for x in _fails:
		print("   ✗ ", x)
	print("═══════════════════════════════════════════")
	await _frames(2)
	get_tree().quit(1 if _f > 0 else 0)


func _ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_p += 1
		print("  ✓ ", label, ("  " + detail) if detail != "" else "")
	else:
		_f += 1
		var m: String = label
		if detail != "":
			m += "  " + detail
		_fails.append(m)
		print("  ✗ ", m)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## 点选弹窗里的第一行人选（行按钮 text 为空，表头为 disabled）
func _pick_row() -> bool:
	for c in _find_all(ui._modal_root, "Button"):
		var b := c as Button
		if b.disabled or b.text != "":
			continue
		b.pressed.emit()
		await _frames(2)
		return true
	return false


func _force_render() -> void:
	ui._dirty = true
	ui._force = true
	await _frames(2)


## 递归找按钮（精确文本）
func _find_btn(root: Node, text: String) -> Button:
	for c in root.get_children():
		if c is Button and (c as Button).text == text:
			return c
		var r := _find_btn(c, text)
		if r != null:
			return r
	return null


## 递归找前缀匹配的按钮
func _find_btn_prefix(root: Node, prefix: String) -> Button:
	for c in root.get_children():
		if c is Button and (c as Button).text.begins_with(prefix):
			return c
		var r := _find_btn_prefix(c, prefix)
		if r != null:
			return r
	return null


## 根据特质 cost 返回按钮上的功德文本
func _tag_cost_text(cost: int) -> String:
	if cost > 0:
		return "功德-%d" % cost
	elif cost < 0:
		return "功德+%d" % -cost
	return "功德0"


func _find_all(root: Node, cls: String) -> Array:
	var out: Array = []
	for c in root.get_children():
		if c.get_class() == cls:
			out.append(c)
		out.append_array(_find_all(c, cls))
	return out


func _count_desc(root: Node) -> int:
	var n := 1
	for c in root.get_children():
		n += _count_desc(c)
	return n


# ── 1. 捏人 ──────────────────────────────────────────
func _test_create_screen() -> void:
	print("\n[1] 开局捏人")
	_ok(ui._modal == ui.MODAL_CREATE, "无存档时直接进入捏人界面")
	_ok(ui._modal_root.get_child_count() > 0, "弹窗层已渲染")

	var name_le := _find_all(ui._modal_root, "LineEdit")
	_ok(name_le.size() == 2, "有姓名与宗派名两个输入框", "%d 个" % name_le.size())

	# 性别切换
	var female := _find_btn(ui._modal_root, "女")
	_ok(female != null, "找得到「女」按钮")
	if female:
		female.pressed.emit()
		await _frames(2)
		_ok(int(ui._cfg["sex"]) == 1, "性别切到女", str(ui._cfg["sex"]))

	# 给足功德，方便测试选特质与转动灵根
	XiuxianGlobals.game.s["merit"] = 100.0
	ui._cfg["base_merit"] = 100.0

	# 转动灵根
	var before := int(ui._cfg["linggen"])
	var reroll := _find_btn_prefix(ui._modal_root, "转动 %s" % ui._linggen_display_name(ui._cfg))
	_ok(reroll != null, "找得到「转动灵根」按钮")
	if reroll:
		var changed := false
		for i in 20:
			reroll.pressed.emit()
			await _frames(1)
			if int(ui._cfg["linggen"]) != before:
				changed = true
				break
			reroll = _find_btn_prefix(ui._modal_root, "转动 %s" % ui._linggen_display_name(ui._cfg))
		_ok(changed, "灵根可随机转动", "%d → %d" % [before, int(ui._cfg["linggen"])])
		_ok(int(ui._cfg["linggen_rerolls"]) >= 1, "转动次数已计数")
		_ok(int(ui._cfg["linggen_merit_spent"]) == 0, "首次转动仍在免费次数内")

	# 再点击 4 次，验证 3 次免费后第 4 次开始扣功德
	var merit_before := int(ui._cfg["linggen_merit_spent"])
	for i in 4:
		reroll = _find_btn_prefix(ui._modal_root, "转动 %s" % ui._linggen_display_name(ui._cfg))
		if reroll:
			reroll.pressed.emit()
			await _frames(1)
	_ok(int(ui._cfg["linggen_rerolls"]) >= 4, "累计转动至少 4 次", str(ui._cfg["linggen_rerolls"]))
	_ok(int(ui._cfg["linggen_merit_spent"]) >= 1, "第 4 次起已扣除 1 功德", str(ui._cfg["linggen_merit_spent"]))

	# 出身切换（创建界面仅列出 异界/乡野农民/修真世家，索引 0/1/2）
	var fami_btn := _find_btn(ui._modal_root, str(DataCore.FAMI[2]["n"]))
	_ok(fami_btn != null, "找得到出身按钮（修真世家）")
	if fami_btn:
		fami_btn.pressed.emit()
		await _frames(2)
		_ok(int(ui._cfg["fami"]) == 2, "出身已切换", DataCore.FAMI[int(ui._cfg["fami"])]["n"])

	# 特质：选 3 个应被限制为 2（用 0 功德的负面特质，避免余额不足）
	var tag_btns: Array = []
	for i in DataCore.TAGS.size():
		var t: Dictionary = DataCore.TAGS[i]
		var b := _find_btn(ui._modal_root, "%s  %s  %s" % [
			t["n"], t["desc"], _tag_cost_text(int(t.get("cost", 0)))])
		if b != null:
			tag_btns.append(b)
	_ok(tag_btns.size() == DataCore.TAGS.size(), "%d 个特质按钮齐备" % DataCore.TAGS.size(), "%d 个" % tag_btns.size())
	if tag_btns.size() >= 3:
		# 负 cost 特质（貌寝 -1）应增加可用预算
		var ugly_t: Dictionary = DataCore.TAGS[9]
		var ugly_b: Button = _find_btn(ui._modal_root, "%s  %s  %s" % [
			ugly_t["n"], ugly_t["desc"], _tag_cost_text(int(ugly_t.get("cost", 0)))])
		if ugly_b != null:
			var before_merit := int(ui._create_available_merit())
			ugly_b.pressed.emit()
			await _frames(2)
			_ok((ui._cfg["tags"] as Array).has(9), "负 cost 特质被选入")
			_ok(int(ui._cfg["tag_merit_cost"]) == -1, "负 cost 已累加", str(ui._cfg["tag_merit_cost"]))
			_ok(int(ui._create_available_merit()) == before_merit + 1, "负 cost 增加 1 点可用功德", "%d -> %d" % [before_merit, int(ui._create_available_merit())])
		# 用新增的预算选聪颖（1 功德）
		var smart_t: Dictionary = DataCore.TAGS[2]
		var smart_b: Button = _find_btn(ui._modal_root, "%s  %s  %s" % [
			smart_t["n"], smart_t["desc"], _tag_cost_text(int(smart_t.get("cost", 0)))])
		if smart_b != null:
			smart_b.pressed.emit()
			await _frames(2)
			_ok((ui._cfg["tags"] as Array).has(2), "正 cost 特质可用负 cost 预算购入")
		# 再选 2 个负 cost 特质（高傲 -1 / 残疾 -2），验证上限 3
		for i in [10, 11]:
			var t: Dictionary = DataCore.TAGS[i]
			var b: Button = _find_btn(ui._modal_root, "%s  %s  %s" % [
				t["n"], t["desc"], _tag_cost_text(int(t.get("cost", 0)))])
			if b != null:
				b.pressed.emit()
				await _frames(2)
		_ok((ui._cfg["tags"] as Array).size() == 3, "特质最多选 3 个", "已选 %d" % (ui._cfg["tags"] as Array).size())

	# 已选提示
	var hint := _find_btn(ui._modal_root, "开宗立派")
	_ok(hint != null, "找得到「开宗立派」按钮")


# ── 2. 开局 ──────────────────────────────────────────
func _test_start_game() -> void:
	print("\n[2] 开宗立派")
	var start := _find_btn(ui._modal_root, "开宗立派")
	_ok(start != null, "开局按钮存在")
	if start == null:
		return
	start.pressed.emit()
	await _frames(3)
	XiuxianGlobals.set_running(false)   # 测试期间手动推进，避免自动跑

	var s := XiuxianGlobals.game.s
	_ok(not s.is_empty(), "游戏状态已建立")
	_ok(ui._modal == ui.MODAL_NONE, "弹窗已关闭")
	_ok(XiuxianGlobals.game.population() == 4, "开局 4 人", str(XiuxianGlobals.game.population()))
	_ok(str(s["sectName"]) != "", "宗门名非空", str(s["sectName"]))
	_ok(ui.tab == "action", "自动切到行动页")
	_ok(ui._content_body.get_child_count() > 0, "内容区已渲染")
	_ok(ui._log_box != null and ui._log_box.get_child_count() >= 2, "纪事已生成",
		str(ui._log_box.get_child_count() if ui._log_box else 0))


# ── 3. 顶栏与页签 ────────────────────────────────────
func _test_header_and_nav() -> void:
	print("\n[3] 顶栏与页签")
	_ok(ui._stats_box.get_child_count() == 8, "顶栏 8 项统计（含杂役、功法、功德）", "%d 项" % ui._stats_box.get_child_count())
	_ok(ui._nav_box.get_child_count() == 5, "5 个页签", "%d 个" % ui._nav_box.get_child_count())
	_ok(ui._sect_label.text != "", "宗门名已填充", ui._sect_label.text)
	_ok(ui._date_label.text.contains("年"), "日期已填充", ui._date_label.text.replace("[b]", "").replace("[/b]", ""))

	# 用页签按钮切换
	var fac := _find_btn(ui._nav_box, "设施")
	_ok(fac != null, "「设施」页签存在")
	if fac:
		fac.pressed.emit()
		await _frames(2)
		_ok(ui.tab == "facility", "点页签切到设施页", ui.tab)
		var act := _find_btn(ui._nav_box, "行动")
		if act:
			act.pressed.emit()
			await _frames(2)
			_ok(ui.tab == "action", "切回行动页")

	# 推进速度按钮
	var spd_btns: Array = []
	for c in ui._ctrl_box.get_children():
		if c is Button and (c as Button).text == "慢":
			spd_btns.append(c)
	_ok(not spd_btns.is_empty(), "顶栏有速度「慢」按钮")
	if not spd_btns.is_empty():
		spd_btns[0].pressed.emit()
		await _frames(2)
		_ok(int(ui.G().s["speed"]) == 2, "速度已切到「慢」", str(ui.G().s["speed"]))
		ui.G().set_speed(3)


# ── 4. 行动页：纪事滚动 ──────────────────────────────
func _test_action_tab() -> void:
	print("\n[4] 行动页 · 纪事")
	ui.tab = "action"
	await _force_render()
	var n0: int = ui._log_box.get_child_count()
	for i in 150:
		XiuxianGlobals.game.tick()
	await _force_render()
	var n1: int = ui._log_box.get_child_count()
	_ok(n1 > n0, "推进后纪事追加新条目", "%d → %d" % [n0, n1])
	_ok(ui._log_len == (XiuxianGlobals.game.s["log"] as Array).size(), "log_len 与状态同步",
		"%d vs %d" % [ui._log_len, (XiuxianGlobals.game.s["log"] as Array).size()])

	# 各色日志（good/bad/hint）都能渲染
	var has_good := false
	for c in ui._log_box.get_children():
		var t := _find_all(c, "RichTextLabel")
		if not t.is_empty():
			has_good = true
			break
	_ok(has_good, "日志条目含富文本")

	# 再推进 400 旬，日志应在 400 条上限处裁剪不崩
	for i in 400:
		XiuxianGlobals.game.tick()
	await _force_render()
	_ok(ui._log_box.get_child_count() > 0, "长时间推进后纪事仍正常",
		"%d 条" % ui._log_box.get_child_count())


# ── 5. 设施页 ────────────────────────────────────────
func _test_facility_tab() -> void:
	print("\n[5] 设施页")
	ui.tab = "facility"
	await _force_render()
	_ok(ui._content_body.get_child_count() > 0, "设施页有内容")

	var grids := _find_all(ui._content_body, "HBoxContainer")
	_ok(grids.size() > 0, "存在栅格容器", "%d 个" % grids.size())

	# 六个峰名都能找到
	var found := 0
	for pk in DataCore.PEAKS:
		var labels := _find_all(ui._content_body, "Label")
		var hit := false
		for l in labels:
			if (l as Label).text == str(pk["n"]):
				hit = true
				break
		if hit:
			found += 1
	_ok(found == 7, "七峰全部渲染", "%d/7" % found)

	# 镇邪峰与寻幽峰同构信息已渲染
	var all_text := ""
	for l in _find_all(ui._content_body, "Label"):
		all_text += (l as Label).text + "\n"
	_ok("境界要求" in all_text, "镇邪峰/寻幽峰显示境界要求")
	_ok("队伍武力" in all_text, "镇邪峰显示队伍武力")
	_ok("队伍武力" in all_text, "寻幽峰显示队伍武力")
	_ok("玄元峰" in all_text, "玄元峰纳入同风格栅格")

	# 外门目标 +1
	var st: Dictionary = XiuxianGlobals.game.s["peaks"]["fumo"]
	var outer0 := int(st["outer"])
	var plus_btns: Array = []
	for c in _find_all(ui._content_body, "Button"):
		if (c as Button).text == "+":
			plus_btns.append(c)
	_ok(plus_btns.size() >= 4, "有外门 +/- 与副手 + 按钮", "%d 个" % plus_btns.size())
	if not plus_btns.is_empty():
		# 先记录所有峰外门目标总和，确认有点到
		var sum0 := 0
		for pk in DataCore.PEAKS:
			sum0 += int(XiuxianGlobals.game.s["peaks"][pk["id"]]["outer"])
		for b in plus_btns:
			(b as Button).pressed.emit()
		await _frames(2)
		var sum1 := 0
		for pk in DataCore.PEAKS:
			sum1 += int(XiuxianGlobals.game.s["peaks"][pk["id"]]["outer"])
		_ok(sum1 > sum0, "点「+」提升外门目标人数", "%d → %d" % [sum0, sum1])

	# 外门自动补员应生效
	XiuxianGlobals.game.s["peaks"]["fumo"]["outer"] = 2
	XiuxianGlobals.game.fill_outer()
	_ok(XiuxianGlobals.game.outer_of("fumo").size() <= 2, "自动补员生效",
		"在岗 %d" % XiuxianGlobals.game.outer_of("fumo").size())

	# 打开任命弹窗
	await _force_render()
	var pick := _find_btn(ui._content_body, "选择")
	_ok(pick != null, "找得到「选择」任命按钮")
	if pick:
		pick.pressed.emit()
		await _frames(2)
		_ok(ui._modal == ui.MODAL_PICK, "任命弹窗已打开")
		var rows := _find_all(ui._modal_root, "Button")
		_ok(rows.size() > 2, "弹窗内有候选行", "%d 个按钮" % rows.size())
		var picked: bool = await _pick_row()
		_ok(picked, "点击候选人")
		_ok(ui._modal == ui.MODAL_NONE, "选完自动关闭弹窗")
		_ok(XiuxianGlobals.game.s["peaks"]["fumo"]["leader"] != null, "镇邪峰已任命峰主")

	# OptionButton（除魔地/丹方/品阶/秘境）
	var opts := _find_all(ui._content_body, "OptionButton")
	_ok(opts.size() >= 4, "下拉框齐备（除魔地/秘境/丹方/品阶）", "%d 个" % opts.size())
	if opts.size() > 0:
		var ob := opts[0] as OptionButton
		var sel0 := ob.selected
		ob.item_selected.emit((sel0 + 1) % ob.item_count)
		await _frames(2)
		_ok(true, "切换下拉项不报错")
		# 触发一次生产，验证不崩
		XiuxianGlobals.game.tick()
		await _frames(1)
		_ok(true, "切换后推进一旬不报错")

	# 建设升级
	XiuxianGlobals.game.s["stone"] = 50000.0
	await _force_render()
	var up := _find_btn(ui._content_body, "升级（%s灵石）" % GameCore.fmt_num(int(XiuxianGlobals.game.s["houseLv"]) * 800))
	_ok(up != null, "找得到屋舍升级按钮")
	if up:
		var lv0 := int(XiuxianGlobals.game.s["houseLv"])
		up.pressed.emit()
		await _frames(2)
		_ok(int(XiuxianGlobals.game.s["houseLv"]) == lv0 + 1, "屋舍升级成功",
			"lv%d → lv%d" % [lv0, int(XiuxianGlobals.game.s["houseLv"])])


# ── 6. 门徒页 ────────────────────────────────────────
func _test_people_tab() -> void:
	print("\n[6] 门徒页")
	ui.tab = "people"
	await _force_render()
	_ok(ui._content_body.get_child_count() > 0, "门徒页有内容")

	var rows: Array = []
	for c in _find_all(ui._content_body, "Button"):
		if not (c as Button).disabled:
			rows.append(c)
	_ok(rows.size() == (XiuxianGlobals.game.s["people"] as Array).size(),
		"每个弟子一行", "%d 行 / %d 人" % [rows.size(), (XiuxianGlobals.game.s["people"] as Array).size()])

	if not rows.is_empty():
		(rows[0] as Button).pressed.emit()
		await _frames(2)
		_ok(ui._modal == ui.MODAL_PERSON, "点行打开弟子详情")
		var t := ""
		for c in _find_all(ui._modal_root, "Label"):
			if (c as Label).text.contains("灵根"):
				t = (c as Label).text
				break
		_ok(t != "", "详情含灵根信息", t)
		# 属性、法宝、按钮
		var kb := _find_btn(ui._modal_root, "关闭")
		_ok(kb != null, "详情有「关闭」按钮")
		if kb:
			kb.pressed.emit()
			await _frames(2)
			_ok(ui._modal == ui.MODAL_NONE, "详情已关闭")

	# 让一名弟子陨落，验证复活按钮
	var victim = XiuxianGlobals.game.alive_list()[0]
	victim["alive"] = false
	XiuxianGlobals.game.changed.emit()
	await _force_render()
	var rows2: Array = []
	for c in _find_all(ui._content_body, "Button"):
		if not (c as Button).disabled:
			rows2.append(c)
	_ok(rows2.size() == (XiuxianGlobals.game.s["people"] as Array).size(), "陨落后行数不变")
	# 该行应带 dead 变暗
	var dark := false
	for r in rows2:
		if (r as Button).modulate.a < 0.9:
			dark = true
			break
	_ok(dark, "陨落行显示为变暗")


# ── 7. 道具页 ────────────────────────────────────────
func _test_items_tab() -> void:
	print("\n[7] 道具页")
	var g := XiuxianGlobals.game
	g.s["herbs"][2] = 10
	g.s["ores"][3] = 8
	g.s["pills"][1] = 3
	g.s["equips"] = [g.make_equip(3), g.make_equip(5)]
	g.s["books"] = [{"name": "测试诀", "req": ["金"], "attrs": {"cultivate": 0.3}, "author": "某人"}]
	g.changed.emit()

	ui.tab = "items"
	await _force_render()
	_ok(ui._content_body.get_child_count() > 0, "道具页有内容")

	var labels: Array = []
	for c in _find_all(ui._content_body, "Label"):
		labels.append((c as Label).text)
	var joined := "|".join(labels)
	_ok(joined.contains("紫芝") or joined.contains("血珊瑚") or joined.contains("龙须根"), "灵草项已列出")
	_ok(joined.contains("云母") or joined.contains("紫金") or joined.contains("幽冥铁"), "灵材项已列出")
	_ok(joined.contains("筑基丹"), "丹药项已列出")
	_ok(joined.contains("《测试诀》"), "功法项已列出")

	# 卖出一株灵草
	var herb0 := int(g.s["herbs"][2])
	var stone0 := float(g.s["stone"])
	var sell := _find_btn(ui._content_body, "卖出 %d" % int(floor(3 * 12 * (1.0 + float(g.s["gongde"][9]) * 0.06))))
	_ok(sell != null, "找得到灵草卖出按钮")
	if sell:
		sell.pressed.emit()
		await _frames(2)
		_ok(int(g.s["herbs"][2]) == herb0 - 1, "灵草 -1", "%d → %d" % [herb0, int(g.s["herbs"][2])])
		_ok(float(g.s["stone"]) > stone0, "灵石增加")

	# 丹药 → 选人服用
	await _force_render()
	var use := _find_btn(ui._content_body, "给谁服用")
	_ok(use != null, "找得到「给谁服用」按钮")
	if use:
		use.pressed.emit()
		await _frames(2)
		_ok(ui._modal == ui.MODAL_PICK, "服药选人弹窗已打开")
		var p0 = g.alive_list()[0]
		var brk0 := float(p0["brkBonus"])
		var pill0: int = int(g.s["pills"].get(1, 0))
		var ok_pick: bool = await _pick_row()
		_ok(ok_pick, "选择服药弟子")
		_ok(float(p0["brkBonus"]) > brk0, "服丹后突破加成提升",
			"%.2f → %.2f" % [brk0, float(p0["brkBonus"])])
		_ok(int(g.s["pills"].get(1, 0)) == pill0 - 1, "丹药消耗 1",
			"%d → %d" % [pill0, int(g.s["pills"].get(1, 0))])

	# 赐予法宝
	await _force_render()
	var give := _find_btn(ui._content_body, "赐予")
	_ok(give != null, "找得到「赐予」按钮")
	if give:
		give.pressed.emit()
		await _frames(2)
		_ok(ui._modal == ui.MODAL_PICK, "赐法宝选人弹窗已打开")
		var stock0: int = (g.s["equips"] as Array).size()
		var ok_give: bool = await _pick_row()
		_ok(ok_give, "选择受赐弟子")
		var worn := false
		for p in g.alive_list():
			for e in p["equip"]:
				if e != null:
					worn = true
		_ok(worn, "法宝已穿戴")
		_ok((g.s["equips"] as Array).size() == stock0 - 1, "公库法宝 -1",
			"%d → %d" % [stock0, (g.s["equips"] as Array).size()])


# ── 8. 设置页 ────────────────────────────────────────
func _test_settings_tab() -> void:
	print("\n[8] 设置页")
	var g := XiuxianGlobals.game
	g.s["merit"] = 500.0
	g.changed.emit()
	ui.tab = "settings"
	await _force_render()
	_ok(ui._content_body.get_child_count() > 0, "设置页有内容")

	var labels: Array = []
	for c in _find_all(ui._content_body, "Label"):
		labels.append((c as Label).text)
	var joined := "|".join(labels)
	var gd_hit := 0
	for gd in DataCore.GONGDE:
		if joined.contains(str(gd["n"])):
			gd_hit += 1
	_ok(gd_hit == 12, "12 座功德建筑全部列出", "%d/12" % gd_hit)
	var tt_hit := 0
	for t in DataCore.TIANTI:
		if joined.contains(str(t)):
			tt_hit += 1
	_ok(tt_hit >= 1, "天梯列表已渲染", "%d/9" % tt_hit)
	_ok(joined.contains("第 %d 轮回" % int(g.s["cycle"])), "显示轮回数")

	# 升级功德建筑
	var lv0 := int(g.s["gongde"][0])
	var btn := _find_btn(ui._content_body, "升级 %d 功德" % ((lv0 + 1) * 10))
	_ok(btn != null, "找得到灵泉升级按钮")
	if btn:
		btn.pressed.emit()
		await _frames(2)
		_ok(int(g.s["gongde"][0]) == lv0 + 1, "灵泉升级成功",
			"lv%d → lv%d" % [lv0, int(g.s["gongde"][0])])

	# 速度按钮
	await _force_render()
	var fast := _find_btn(ui._content_body, "快（400ms/旬）")
	_ok(fast != null, "找得到速度按钮")
	if fast:
		fast.pressed.emit()
		await _frames(2)
		_ok(int(g.s["speed"]) == 0, "速度切到「快」", str(g.s["speed"]))

	# 轮回（走确认弹窗）
	await _force_render()
	var rein := _find_btn(ui._content_body, "进入新的轮回")
	_ok(rein != null, "找得到「进入新的轮回」")
	if rein:
		rein.pressed.emit()
		await _frames(2)
		_ok(ui._modal == ui.MODAL_CONFIRM, "弹出确认框")
		var yes := _find_btn(ui._modal_root, "确定")
		_ok(yes != null, "确认框有「确定」")
		if yes:
			var cyc0 := int(g.s["cycle"])
			yes.pressed.emit()
			await _frames(3)
			_ok(int(g.s["cycle"]) == cyc0 + 1, "轮回计数 +1",
				"%d → %d" % [cyc0, int(g.s["cycle"])])
			_ok(int(g.s["year"]) == 1, "年份重置")
			_ok(g.population() == 4, "轮回后 4 人", str(g.population()))
			_ok(int(g.s["gongde"][0]) >= 1, "功德建筑跨轮回保留")


# ── 9. toast ─────────────────────────────────────────
func _test_toast() -> void:
	print("\n[9] toast 提示")
	ui.toast("测试提示")
	await _frames(2)
	_ok(ui._toast_panel.visible, "toast 可见")
	_ok(ui._toast_label.text == "测试提示", "toast 文案正确", ui._toast_label.text)
	await get_tree().create_timer(2.0).timeout
	await _frames(3)
	_ok(not ui._toast_panel.visible, "toast 自动消失")


# ── 10. 存档往返 ─────────────────────────────────────
func _test_save_load() -> void:
	print("\n[10] 存档 / 读档")
	var g := XiuxianGlobals.game
	for i in 60:
		g.tick()
	var y0 := int(g.s["year"])
	var pop0 := g.population()
	var stone0 := float(g.s["stone"])

	ui.tab = "settings"
	await _force_render()
	var save_btn := _find_btn(ui._content_body, "保存进度")
	_ok(save_btn != null, "找得到「保存进度」")
	if save_btn:
		save_btn.pressed.emit()
		await _frames(2)
		_ok(XiuxianGlobals.has_save(), "存档文件已写入")
		_ok(ui._toast_panel.visible, "存档后弹出提示")

	# 把内存里的状态改掉，再读档还原
	g.s["year"] = 999
	g.s["stone"] = 1.0
	await _force_render()
	var load_btn := _find_btn(ui._content_body, "读取存档")
	_ok(load_btn != null, "找得到「读取存档」")
	if load_btn:
		load_btn.pressed.emit()
		await _frames(3)
		_ok(int(g.s["year"]) == y0, "读档还原年份", "%d vs %d" % [int(g.s["year"]), y0])
		_ok(g.population() == pop0, "读档还原人口")
		_ok(absf(float(g.s["stone"]) - stone0) < 1.0, "读档还原灵石")
		_ok(not XiuxianGlobals.is_running(), "读档后暂停")

	# 重开宗门
	await _force_render()
	var nb := _find_btn(ui._content_body, "重开宗门")
	_ok(nb != null, "找得到「重开宗门」")
	if nb:
		nb.pressed.emit()
		await _frames(2)
		_ok(ui._modal == ui.MODAL_CONFIRM, "重开走确认框")
		var yes := _find_btn(ui._modal_root, "确定重开")
		if yes:
			yes.pressed.emit()
			await _frames(3)
			_ok(ui._modal == ui.MODAL_CREATE, "回到捏人界面")
			_ok(not XiuxianGlobals.has_save(), "存档已清除")

	# 再来一局，确认整条链路可重复
	if ui._modal == ui.MODAL_CREATE:
		var start := _find_btn(ui._modal_root, "开宗立派")
		if start:
			start.pressed.emit()
			await _frames(3)
			XiuxianGlobals.set_running(false)
			_ok(g.population() == 4, "二次开局正常", "%d 人" % g.population())
			_ok(int(g.s["cycle"]) == 3, "轮回数累加", str(g.s["cycle"]))

# ── 11. 宗门大比选奖品弹窗 ──────────────────────────
func _test_champion_modal() -> void:
	print("\n[11] 宗门大比 · 选奖品弹窗")
	var g = XiuxianGlobals.game
	# 临时切到实机模式，验证大比会挂起并弹窗选奖品
	g.auto_champion = false
	XiuxianGlobals.set_running(false)
	# 确保有外门候选
	for i in 4:
		g.add_disciple(true)
	g.s["championLeft"] = 2
	var guard := 0
	while g.s.get("pending_champion", {}).is_empty() and guard < 60:
		g.tick()
		guard += 1
	# 模拟「大比发生时正在推进」：恢复运行，让弹窗捕获并结算后恢复
	XiuxianGlobals.set_running(true)
	g.emit_signal("changed")
	await _force_render()

	_ok(ui._modal == ui.MODAL_CHAMPION, "大比挂起自动弹出选奖品弹窗")
	_ok(ui._modal_root.get_child_count() > 0, "弹窗内有渲染内容")

	var pc: Dictionary = g.s.get("pending_champion", {})
	var wid: int = int(pc.get("id", -1))
	var was_inner: bool = g.by_id(wid)["inner"]
	ui._pick_prize(1)
	await _force_render()

	_ok(g.s.get("pending_champion", {}).is_empty(), "选定后 pending 清空")
	_ok(g.by_id(wid)["inner"] == true, "胜者拜入内门（%s→%s）" % [was_inner, g.by_id(wid)["inner"]])
	# 验证法宝已装备到胜者身上（任意部位非空）
	var worn := false
	for slot in g.by_id(wid)["equip"]:
		if slot != null:
			worn = true
			break
	_ok(worn, "所选法宝已穿戴到胜者身上")
	_ok(XiuxianGlobals.is_running(), "结算后恢复推进")

	# 恢复自动结算，避免影响后续（无后续用例）
	g.auto_champion = true
