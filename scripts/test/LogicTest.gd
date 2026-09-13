extends SceneTree

## 无头逻辑回归测试：验证移植后的模拟核心与 web 版行为一致。
## 运行：godot --headless --path <工程> --script res://scripts/test/LogicTest.gd

var _pass := 0
var _fail := 0
var _failures: Array = []


func _initialize() -> void:
	print("═══════════════════════════════════════════")
	print(" 修仙门派 · 逻辑回归测试")
	print("═══════════════════════════════════════════")

	_test_new_game()
	_test_attributes()
	_test_long_run()
	_test_operations()
	_test_pills_and_equips()
	_test_reincarnate()
	_test_save_load()

	print("───────────────────────────────────────────")
	print(" 通过 %d / 失败 %d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("   ✗ ", f)
	print("═══════════════════════════════════════════")
	quit(1 if _fail > 0 else 0)


func _ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  ✓ ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		var msg: String = label
		if detail != "":
			msg += "  " + detail
		_failures.append(msg)
		print("  ✗ ", msg)


func _new_game() -> GameCore:
	var g := GameCore.new(GameCore.RNG_SEED_DEFAULT)
	g.new_game({
		"name": "龙傲天", "sectName": "凌霄宗", "sex": 0,
		"linggen": 0, "fami": 0, "tags": [6, 4],
	})
	return g


# ── 1. 开局 ──────────────────────────────────────────
func _test_new_game() -> void:
	print("\n[1] 开宗立派")
	var g := _new_game()
	var s := g.s
	_ok(s["sectName"] == "凌霄宗", "宗门名写入", str(s["sectName"]))
	_ok(int(s["year"]) == 1 and int(s["month"]) == 1 and int(s["xun"]) == 1, "时间从 1年1月上旬 起")
	_ok(is_equal_approx(float(s["stone"]), 3000.0), "初始灵石 3000", str(s["stone"]))
	_ok(g.population() == 4, "掌门 + 3 名初始弟子", "%d 人" % g.population())
	_ok(g.capacity() == 10, "初始容量 6+1*4=10", str(g.capacity()))

	var master := g.by_id(1)
	_ok(not master.is_empty() and master["job"] == "leader", "1 号弟子是掌门")
	_ok(master["inner"] == true, "掌门为内门")
	_ok(int(master["realm"]) == 1 and int(master["sub"]) == 0, "掌门筑基初阶")
	_ok((master["equip"] as Array).size() == 5, "5 个法宝栏位")
	_ok((s["herbs"] as Array).size() == 10 and (s["ores"] as Array).size() == 10, "灵草/灵材各 10 档")
	_ok((s["gongde"] as Array).size() == 12, "功德建筑 12 座")
	_ok((s["peaks"] as Dictionary).size() == 7, "七峰齐备")
	_ok((s["log"] as Array).size() >= 2, "开局有纪事", "%d 条" % (s["log"] as Array).size())


# ── 2. 属性计算 ──────────────────────────────────────
func _test_attributes() -> void:
	print("\n[2] 属性与公式")
	var g := _new_game()
	var p := g.by_id(1)

	# 变异天灵根：rate 3.6 / atk 1.5，异界出身 qi 1.3 atk 1.0
	# 心情 60 → mood_k = 0.6 + 0.6*0.6 = 0.96
	var cult := g.eff(p, "cultivate")
	# 天赋「无垢灵体」不在 tags 里（tags=[6,4]），期望 = 3.6 * 1.3(异界qi) * 1.0 * 0.96
	var expect := 3.6 * 1.3 * 0.96
	_ok(absf(cult - expect) < 0.05, "修炼效率 = 灵根×出身×心情", "%.4f ≈ %.4f" % [cult, expect])

	var atk_eff := g.eff(p, "atk")
	# 顺序即为原版语义：先乘灵根/出身，特质「天生剑骨 atk+1.0」是**加法**，最后乘心情
	# (1.5 * 1.0 + 1.0) * 0.96 = 2.400
	var atk_expect := (1.5 * 1.0 + 1.0) * 0.96
	_ok(absf(atk_eff - atk_expect) < 0.05, "武力倍率含天生剑骨（加法叠加）", "%.4f ≈ %.4f" % [atk_eff, atk_expect])

	_ok(g.qi_max(p) == 260.0, "筑基初阶灵气上限 260", str(g.qi_max(p)))
	_ok(g.atk_of(p) > 0.0, "武力为正", str(g.atk_of(p)))
	_ok(g.lifespan_of(p) == 200, "筑基期寿元 200", str(g.lifespan_of(p)))
	_ok(g.realm_name(p) == "筑基初阶", "境界名", g.realm_name(p))

	# 把 sub 推到 9 → 大圆满 → realm 6 起改用「前期/中期/后期/大圆满」
	p["sub"] = 9
	_ok(g.realm_name(p) == "筑基大圆满", "大圆满显示", g.realm_name(p))
	p["realm"] = 7
	p["sub"] = 3
	_ok(g.realm_name(p) == "渡劫中期", "分神期以后用 前/中/后/大圆满", g.realm_name(p))

	# 突破率随境界递减
	var r0 := g.brk_rate(g.by_id(1))
	p["realm"] = 8
	var r8 := g.brk_rate(p)
	_ok(r8 < 1.0 and r8 > 0.0, "突破率在 (0,1) 区间", "渡劫 %.3f" % r8)

	# 无量纲校验：0 级功德时冥思阁不加成
	p["realm"] = 0
	p["job"] = null
	var base := g.brk_rate(p)
	g.s["gongde"][6] = 10   # 冥思阁 10 级 → +10%
	_ok(absf(g.brk_rate(p) - minf(0.99, base + 0.10)) < 0.001, "冥思阁每级 +1% 突破率",
		"%.3f → %.3f" % [base, g.brk_rate(p)])


# ── 3. 长时间推进 ────────────────────────────────────
func _test_long_run() -> void:
	print("\n[3] 4000 旬长跑（经济与飞升）")
	var g := _new_game()
	var a := g.alive_list()
	g.assign(a[0], "fumo", true, false)
	if a.size() > 1: g.assign(a[1], "shenyao", true, false)
	if a.size() > 2: g.assign(a[2], "lingkuang", true, false)
	if a.size() > 3: g.assign(a[3], "danding", true, false)
	g.s["peaks"]["fumo"]["outer"] = 3
	g.s["peaks"]["danding"]["outer"] = 2
	g.s["peaks"]["baiqi"]["outer"] = 2
	var writer_id = (a[1] if a.size() > 1 else a[0])["id"]
	g.s["peaks"]["zhuanzhu"]["writer"] = writer_id

	var s := g.s
	var zero_ticks := 0
	var checkpoints := [360, 1080, 1800, 2520, 3600, 4000]
	var best_realm := 0

	for i in range(1, 4001):
		# 模拟玩家经营：镇邪峰主空缺时从存活内门补一人；外门不足 6 人时从闲置弟子补员；
		# 并随宗门最强境界提升除魔目标（玩家会去打更高级的除魔地），验证新「仅攻略成功给灵石」
		# 模型下持续经营（镇邪峰满编、目标随境界升级）的宗门仍可维生
		var br := 0
		for p in g.alive_list():
			br = maxi(br, int(p["realm"]))
		var best_t := 0
		for fi in range(DataCore.FIGHT.size()):
			if int(DataCore.FIGHT[fi]["need"]) <= br:
				best_t = fi
		s["fightTarget"] = best_t
		if g.s["peaks"]["fumo"]["leader"] == null:
			for p in g.alive_list():
				if p["inner"]:
					g.assign(p, "fumo", true, false)
					break
		if g.outer_of("fumo").size() < 6:
			for p in g.alive_list():
				if p["peak"] == null and not p["inner"] and p["job"] != "leader" and not p["is_demon"]:
					g.assign(p, "fumo", false, false)
					break
		g.tick()
		if float(s["stone"]) <= 0.0:
			zero_ticks += 1
		for p in g.alive_list():
			best_realm = maxi(best_realm, int(p["realm"]))
		if checkpoints.has(i):
			var alive := g.alive_list()
			print("    [%4d旬 %3d年] 灵石 %-8s 庇护 %-8s 门徒 %2d 功法 %d 法宝 %2d" % [
				i, int(s["year"]), GameCore.fmt_num(s["stone"]), GameCore.fmt_num(s["protect"]),
				g.population(), (s["books"] as Array).size(), (s["equips"] as Array).size()])

	var flown := 0
	var dead := 0
	for p in s["people"]:
		if p["fly"]: flown += 1
		if not p["alive"] or p["dormant"]: dead += 1

	# 用户明确要求「不要考虑宗门枯竭」，故灵石枯竭不再作为硬性断言，仅作信息输出
	print("    灵石枯竭旬数（信息，不计入断言）：%d" % zero_ticks)
	_ok(flown >= 1, "有弟子飞升", "%d 人飞升" % flown)
	_ok(g.population() > 0, "宗门未绝嗣", "%d 人存续" % g.population())
	_ok(best_realm >= 3, "境界推进到金丹以上", "最高 realm=%d" % best_realm)
	_ok(int(s["tianti"]) >= 1, "天梯已修复", "%d/9 层" % int(s["tianti"]))
	_ok(float(s["protect"]) > 0.0, "产出庇护人数", GameCore.fmt_num(s["protect"]))
	_ok((s["log"] as Array).size() <= 400, "纪事上限 400 条", "%d" % (s["log"] as Array).size())
	print("    已故/休眠 %d 人，累计门徒 %d 人" % [dead, (s["people"] as Array).size()])


# ── 4. 玩家操作 ──────────────────────────────────────
func _test_operations() -> void:
	print("\n[4] 玩家操作")
	var g := _new_game()
	var s := g.s
	var a := g.alive_list()

	# 任命峰主（使用非掌门弟子）
	g.assign(a[1], "fumo", true, false)
	_ok(s["peaks"]["fumo"]["leader"] == a[1]["id"], "任命镇邪峰峰主")
	_ok(a[1]["job"] == "fengzhu", "职位为峰主", str(a[1]["job"]))
	_ok(a[1]["inner"] == true, "任命后转内门")

	# 换人应自动卸任旧的
	g.assign(a[2], "fumo", true, false)
	_ok(s["peaks"]["fumo"]["leader"] == a[2]["id"], "换人后 leader 更新")
	_ok(a[1]["job"] == null, "旧峰主已卸任", str(a[1]["job"]))

	# 副手
	g.assign(a[1], "shenyao", false, true)
	_ok((s["peaks"]["shenyao"]["deputy"] as Array).has(a[1]["id"]), "添加副手")
	_ok(a[1]["job"] == "fushou", "职位为副手")

	# 掌门可兼任峰主且不卸任
	g.assign(a[0], "xunyou", true, false)
	_ok(s["peaks"]["xunyou"]["leader"] == a[0]["id"], "掌门兼任寻幽峰峰主")
	_ok(a[0]["job"] == "leader", "掌门身份保留")

	# 外门挂靠（用真正的外门弟子）
	var od := g.add_disciple(false)
	_ok(od["inner"] == false, "新收弟子为外门")
	g.assign(od, "lingkuang", false, false)
	_ok(od["peak"] == "lingkuang" and od["inner"] == false, "外门弟子挂靠玄矿峰")

	# 解除
	g.unassign(od)
	_ok(od["peak"] == null, "解除职务后清空峰位")

	# 守卫：内门弟子不得调往外门岗位（a[1] 已是内门副手）
	g.assign(a[1], "lingkuang", false, false)
	_ok(a[1]["peak"] != "lingkuang", "内门弟子不能调往外门岗位", str(a[1]["peak"]))

	# 守卫：掌门不得调往外门岗位（a[0] 为掌门）
	g.assign(a[0], "lingkuang", false, false)
	_ok(a[0]["peak"] != "lingkuang", "掌门不能调往外门岗位", str(a[0]["peak"]))

	# 外门自动补员
	s["peaks"]["baiqi"]["outer"] = 2
	g.fill_outer()
	_ok(g.outer_of("baiqi").size() <= 2, "自动补员不超过目标人数",
		"%d/2" % g.outer_of("baiqi").size())
	s["peaks"]["baiqi"]["outer"] = 0
	g.fill_outer()
	_ok(g.outer_of("baiqi").size() == 0, "目标归零后回收外门")

	# 掌门更替
	g.set_leader(a[1]["id"])
	_ok(a[1]["job"] == "leader", "立新掌门")
	_ok(a[0]["job"] != "leader", "旧掌门已卸任")

	# 建设升级
	s["stone"] = 100000.0
	var lv := int(s["houseLv"])
	_ok(g.upgrade_house() == true, "升级屋舍")
	_ok(int(s["houseLv"]) == lv + 1, "屋舍等级 +1", str(s["houseLv"]))
	var cap_before := g.capacity()
	_ok(cap_before == 6 + int(s["houseLv"]) * 4, "容量随屋舍提升", str(cap_before))
	var al := int(s["arrayLv"])
	_ok(g.upgrade_array() == true, "升级护山大阵")
	_ok(int(s["arrayLv"]) == al + 1, "护山大阵等级 +1")

	# 灵石不足时应失败
	s["stone"] = 0.0
	_ok(g.upgrade_house() == false, "灵石不足时升级失败")

	# 功德建筑（跨轮回保留的字段）
	s["merit"] = 100.0
	_ok(g.upgrade_gongde(0) == true, "升级灵泉")
	_ok(int(s["gongde"][0]) == 1, "灵泉 lv1")
	_ok(is_equal_approx(float(s["merit"]), 90.0), "消耗 10 功德", str(s["merit"]))
	s["merit"] = 0.0
	_ok(g.upgrade_gongde(0) == false, "功德不足时升级失败")

	# 卖素材
	s["herbs"][3] = 5
	var stone0 := float(s["stone"])
	g.sell_herb(3)
	_ok(float(s["stone"]) > stone0, "卖出灵草换灵石", "+%d" % int(float(s["stone"]) - stone0))
	_ok(int(s["herbs"][3]) == 4, "灵草 -1")
	s["ores"][2] = 5
	stone0 = float(s["stone"])
	g.sell_ore(2)
	_ok(float(s["stone"]) > stone0, "卖出灵材换灵石")
	_ok(int(s["ores"][2]) == 4, "灵材 -1")

	# 速度档位
	g.set_speed(3)
	_ok(g.speed_ms() == 3200, "速度档位映射到毫秒", str(g.speed_ms()))
	g.set_speed(99)
	_ok(g.speed_ms() == 3200, "越界速度被钳制", str(g.speed_ms()))


# ── 5. 丹药与法宝 ────────────────────────────────────
func _test_pills_and_equips() -> void:
	print("\n[5] 丹药与法宝")
	var g := _new_game()
	var s := g.s
	var a := g.alive_list()

	# 突破丹
	s["pills"][1] = 2
	var brk0 := float(a[0]["brkBonus"])
	g.use_pill(1, a[0]["id"])
	_ok(float(a[0]["brkBonus"]) > brk0, "服筑基丹提升突破率",
		"%.3f → %.3f" % [brk0, float(a[0]["brkBonus"])])
	_ok(int(s["pills"][1]) == 1, "丹药数量 -1")

	# 洗髓丹：洗掉末位灵根
	var p: Dictionary = a[0]
	p["elements"] = ["金", "水", "木"]
	p["linggenIdx"] = 5
	s["pills"][10] = 1
	g.use_pill(10, p["id"])
	_ok((p["elements"] as Array).size() == 2, "洗髓后灵根-1", str(p["elements"]))
	_ok(int(p["linggenIdx"]) == 4, "灵根品质晋升一档", str(p["linggenIdx"]))

	# 单灵根不能洗
	var q: Dictionary = a[1]
	q["elements"] = ["金"]
	s["pills"][10] = 1
	var before := (q["elements"] as Array).size()
	g.use_pill(10, q["id"])
	_ok((q["elements"] as Array).size() == before, "单灵根无法洗髓")
	_ok(int(s["pills"].get(10, 0)) == 1, "失败时丹药未消耗")

	# 炼制法宝 + 赐予 + 卸下
	var e := g.make_equip(5)
	_ok(e.has("name") and e.has("slot") and e.has("attrs"), "法宝结构完整", str(e["name"]))
	_ok(int(e["slot"]) >= 0 and int(e["slot"]) <= 4, "部位在 0-4")
	_ok((e["attrs"] as Dictionary).size() >= 1, "至少 1 条词条", str(e["attrs"].keys()))

	s["equips"] = [e]
	var target: Dictionary = a[2]
	g.equip_to(target["id"], 0)
	_ok(target["equip"][int(e["slot"])] != null, "法宝已穿戴到正确部位")
	_ok((s["equips"] as Array).is_empty(), "公库已移除该法宝")

	g.unequip(target["id"], int(e["slot"]))
	_ok(target["equip"][int(e["slot"])] == null, "卸下后栏位空出")
	_ok((s["equips"] as Array).size() == 1, "法宝回到公库")

	# 法宝加成应体现在属性上
	s["equips"] = []
	var e2 := {"name": "测试剑", "slot": 4, "lv": 7, "attrs": {"atk": 1.0}, "spirit": false}
	var t2: Dictionary = a[3]
	var atk_before := g.atk_of(t2)
	t2["equip"][4] = e2
	_ok(g.atk_of(t2) > atk_before, "佩戴法宝后武力提升",
		"%.0f → %.0f" % [atk_before, g.atk_of(t2)])

	# 复活
	var r: Dictionary = a[3]
	r["alive"] = false
	r["lifespanBonus"] = 0.0
	g.revive(r["id"], 0)
	_ok(r["alive"] == true, "九转还魂丹复活")
	_ok(float(r["lifespanBonus"]) > 0.0, "复活附赠寿元", str(r["lifespanBonus"]))

	# 功法：撰写 10 年后入库
	var w: Dictionary = a[0]
	var b := g.make_book(w)
	_ok(b.has("name") and b.has("req") and b.has("attrs"), "功法结构完整", str(b["name"]))
	_ok((b["req"] as Array).size() >= 1, "功法有灵根要求", str(b["req"]))
	var atk_b := g.atk_of(w)
	var cult_b := g.eff(w, "cultivate")
	s["books"] = [{"name": "测试诀", "req": [], "attrs": {"cultivate": 0.5}, "author": "测试"}]
	_ok(g.eff(w, "cultivate") > cult_b, "研习功法后修炼效率提升",
		"%.3f → %.3f" % [cult_b, g.eff(w, "cultivate")])
	_ok(is_equal_approx(g.atk_of(w), atk_b), "不匹配属性的功法不加武力")


# ── 6. 轮回 ──────────────────────────────────────────
func _test_reincarnate() -> void:
	print("\n[6] 轮回")
	var g := _new_game()
	var s := g.s
	s["protect"] = 10000.0
	s["tick"] = 400
	s["merit"] = 0.0
	s["gongde"][0] = 3
	s["herbs"][2] = 50
	s["houseLv"] = 4
	var lead_id = s["people"][0]["id"]

	g.reincarnate()
	_ok(int(s["cycle"]) == 2, "轮回数 +1", str(s["cycle"]))
	_ok(is_equal_approx(float(s["protect"]), 0.0), "庇护清零")
	_ok(int(s["year"]) == 1 and int(s["tick"]) == 0, "时间重置")
	_ok(is_equal_approx(float(s["stone"]), 3000.0), "灵石重置为 3000")
	_ok((s["herbs"] as Array).all(func(v): return int(v) == 0), "素材清空")
	_ok((s["equips"] as Array).is_empty() and (s["books"] as Array).is_empty(), "法宝/功法清空")
	_ok(int(s["houseLv"]) == 1 and int(s["arrayLv"]) == 1, "建设等级重置")
	_ok(int(s["gongde"][0]) == 3, "功德建筑等级跨轮回保留", "灵泉 lv%d" % int(s["gongde"][0]))
	_ok(float(s["merit"]) > 0.0, "结算功德", "+%d" % int(s["merit"]))
	_ok(g.population() == 4, "轮回后 1 掌门 + 3 弟子", "%d 人" % g.population())

	var lead := g.by_id(lead_id)
	_ok(not lead.is_empty() and lead["job"] == "leader", "原掌门留任")
	_ok(int(lead["realm"]) == 0 and int(lead["age"]) == 20, "掌门重修，年岁归 20")

	# 跨轮回再开一局，功德与建筑应沿用
	var g2 := g
	g2.new_game({"name": "新掌门", "sectName": "新宗", "sex": 1, "linggen": 2, "fami": 3, "tags": []})
	_ok(int(g2.s["cycle"]) == 3, "再开一局 cycle 累加", str(g2.s["cycle"]))
	_ok(int(g2.s["gongde"][0]) == 3, "功德建筑沿用旧档")


# ── 7. 存档往返 ──────────────────────────────────────
func _test_save_load() -> void:
	print("\n[7] 存档往返")
	var g := _new_game()
	var a := g.alive_list()
	g.assign(a[0], "fumo", true, false)
	g.s["peaks"]["fumo"]["outer"] = 3
	g.s["gongde"][2] = 5
	g.s["pills"][3] = 4
	for i in 200:
		g.tick()

	var y := int(g.s["year"])
	var pop := g.population()
	var stone := float(g.s["stone"])
	var tianti := int(g.s["tianti"])
	var equip_n := (g.s["equips"] as Array).size()
	var book_n := (g.s["books"] as Array).size()
	var log_n := (g.s["log"] as Array).size()
	# 存档前的丹药数（会被 200 旬内的随机事件改动，故必须在存档时刻取值，
	# 不能硬编码——事件权重一旦调整，RNG 轨迹变化会让常量期望失效）
	var pill3 := int(g.s["pills"].get(3, 0))
	var top_name: String = g.alive_list()[0]["name"] if not g.alive_list().is_empty() else ""
	var top_realm: String = g.realm_name(g.alive_list()[0]) if not g.alive_list().is_empty() else ""

	var ok := g.save()
	_ok(ok and g.has_save(), "存档写入成功")

	# 新实例读档
	var g2 := GameCore.new(1)
	var ok2 := g2.load_save()
	_ok(ok2, "读档成功")
	_ok(int(g2.s["year"]) == y, "年份一致", "%d vs %d" % [int(g2.s["year"]), y])
	_ok(g2.population() == pop, "人口一致", "%d vs %d" % [g2.population(), pop])
	_ok(absf(float(g2.s["stone"]) - stone) < 1.0, "灵石一致", "%.0f vs %.0f" % [float(g2.s["stone"]), stone])
	_ok(int(g2.s["tianti"]) == tianti, "天梯一致")
	_ok((g2.s["equips"] as Array).size() == equip_n, "法宝数一致")
	_ok((g2.s["books"] as Array).size() == book_n, "功法数一致")
	_ok((g2.s["log"] as Array).size() == log_n, "纪事数一致")
	_ok(int(g2.s["gongde"][2]) == 5, "功德建筑等级保留")
	_ok(int(g2.s["pills"].get(3, 0)) == pill3, "丹药数量保留", "%d vs %d" % [int(g2.s["pills"].get(3, 0)), pill3])

	# 类型校准：JSON 往返后仍是 int，能直接当数组下标
	var p2 := g2.by_id(1)
	_ok(typeof(p2["realm"]) == TYPE_INT, "realm 载入后仍为 int", str(typeof(p2["realm"])))
	_ok(typeof(p2["sub"]) == TYPE_INT, "sub 载入后仍为 int")
	_ok(typeof(g2.s["herbs"][0]) == TYPE_INT, "herbs 元素为 int")
	_ok(typeof(g2.s["peaks"]["fumo"]["pill"]) == TYPE_INT, "peak.pill 为 int")
	var _rn := g2.realm_name(p2)   # 下标访问不应报错
	_ok(typeof(DataCore.REALMS[int(p2["realm"])]) == TYPE_STRING, "境界下标可用")
	var top2: Dictionary = g2.alive_list()[0]
	_ok(str(top2["name"]) == top_name, "首位弟子姓名一致", "%s vs %s" % [top2["name"], top_name])

	# 读档后还能继续推进
	var y0 := int(g2.s["year"])
	for i in 100:
		g2.tick()
	_ok(int(g2.s["year"]) > y0, "读档后可继续推进", "%d → %d" % [y0, int(g2.s["year"])])
	g2.clear_save()
	_ok(not g2.has_save(), "清档成功")
