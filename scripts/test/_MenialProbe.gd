extends SceneTree

## 杂役弟子 / 产出门槛 / 师徒 / 子嗣 / 撰书阁比例 回归探针
## 运行：godot --headless --path <工程> --script res://scripts/test/_MenialProbe.gd

var _pass := 0
var _fail := 0
var _failures: Array = []


func _initialize() -> void:
	print("══════════════════════════════════════════════════")
	print(" 杂役 / 产出门槛 / 师徒 / 子嗣 / 撰书阁比例 探针")
	print("══════════════════════════════════════════════════")
	_test_menial_bonus()
	_test_peak_yield_menial_only()
	_test_alloc_menial()
	_test_grow_menial()
	_test_shenyao_menial_produces()
	_test_lingkuang_menial_produces()
	_test_shenyao_deputy_produces()
	_test_danding_deputy_produces()
	_test_danding_outer_produces()
	_test_baiqi_outer_produces()
	_test_master_apprentice_bonus()
	_test_child_elements()
	_test_book_ratio()
	print("──────────────────────────────────────────────────")
	print(" 通过 %d / 失败 %d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("   ✗ ", f)
	print("══════════════════════════════════════════════════")
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


func _game() -> GameCore:
	var g := GameCore.new(GameCore.RNG_SEED_DEFAULT)
	g.new_game({
		"name": "测试甲", "sectName": "测试宗", "sex": 0,
		"linggen": 0, "fami": 0, "tags": [],
	})
	return g


# ── 需求 #3：每个杂役使在岗峰效率 +5% ──────────────────
func _test_menial_bonus() -> void:
	print("── 杂役 +5% 效率 ──")
	var g := _game()
	var lead: Dictionary = g.s["people"][0]
	g.s["peaks"]["shenyao"]["leader"] = lead["id"]
	g.s["peaks"]["shenyao"]["menialOn"] = 0
	var base := g.team_eff("shenyao", "plant")
	g.s["peaks"]["shenyao"]["menialOn"] = 2
	var boosted := g.team_eff("shenyao", "plant")
	_ok(absf(boosted - base * 1.10) < 1e-6, "2 杂役使队伍效率精确 +10%",
		"base=%.4f boosted=%.4f" % [base, boosted])


# ── 需求 #5：无领队仅杂役，peak_yield 仍为正 ───────────
func _test_peak_yield_menial_only() -> void:
	print("── peak_yield 杂役兜底 ──")
	var g := _game()
	g.s["peaks"]["shenyao"]["leader"] = null
	g.s["peaks"]["shenyao"]["menialOn"] = 1
	var y := g.peak_yield("shenyao", "plant")
	_ok(y > 0.0, "无领队仅 1 杂役，peak_yield 仍 > 0", "y=%.4f" % y)


# ── 全局池分配：需求=10 池=5 → 各峰取整半数 ────────────
func _test_alloc_menial() -> void:
	print("── 杂役池分配 ──")
	var g := _game()
	g.s["menial"] = 5
	g.s["peaks"]["shenyao"]["menial"] = 5
	g.s["peaks"]["lingkuang"]["menial"] = 5
	g._alloc_menial()
	var a := int(g.s["peaks"]["shenyao"]["menialOn"])
	var b := int(g.s["peaks"]["lingkuang"]["menialOn"])
	_ok(a == 2 and b == 2, "池=5/需求=10 → 两峰各在岗 2 人",
		"青芜=%d 玄矿=%d" % [a, b])
	# 池充足时全量满足
	g.s["menial"] = 10
	g._alloc_menial()
	_ok(int(g.s["peaks"]["shenyao"]["menialOn"]) == 5, "池=10 → 青芜满额 5 人",
		"青芜=%d" % int(g.s["peaks"]["shenyao"]["menialOn"]))


# ── 杂役随庇护/时间增长 ────────────────────────────────
func _test_grow_menial() -> void:
	print("── 杂役数量增长 ──")
	var g := _game()
	g.s["protect"] = 300.0   # target = 300/15 + 1/40 = 20
	var before := int(g.s["menial"])
	g.on_year()              # 触发 _grow_menial
	var after := int(g.s["menial"])
	_ok(after > before, "庇护充足时杂役总数增长", "before=%d after=%d" % [before, after])


# ── 需求 #5：青芜峰无领队、仅杂役 → 产出灵草 ───────────
func _test_shenyao_menial_produces() -> void:
	print("── 青芜峰杂役产灵草 ──")
	var g := _game()
	g.s["menial"] = 4
	g.s["peaks"]["shenyao"]["menial"] = 4
	g.s["peaks"]["shenyao"]["leader"] = null
	var before: Array = g.s["herbs"].duplicate()
	g.production()
	var gained := 0
	for i in 10:
		gained += int(g.s["herbs"][i]) - int(before[i])
	_ok(gained > 0, "青芜峰无领队、仅 4 杂役 → 产出灵草", "gained=%d" % gained)


# ── 需求 #5：玄矿峰无领队、仅杂役 → 产出灵矿 ───────────
func _test_lingkuang_menial_produces() -> void:
	print("── 玄矿峰杂役产灵矿 ──")
	var g := _game()
	g.s["menial"] = 4
	g.s["peaks"]["lingkuang"]["menial"] = 4
	g.s["peaks"]["lingkuang"]["leader"] = null
	var before: Array = g.s["ores"].duplicate()
	g.production()
	var gained := 0
	for i in 10:
		gained += int(g.s["ores"][i]) - int(before[i])
	_ok(gained > 0, "玄矿峰无领队、仅 4 杂役 → 产出灵矿", "gained=%d" % gained)


# ── 开工门槛：青芜峰仅副手（无领队/无杂役/无外门）→ 开门 ──
func _test_shenyao_deputy_produces() -> void:
	print("── 青芜峰副手开工门槛 ──")
	var g := _game()
	g.s["peaks"]["shenyao"]["leader"] = null
	g.s["peaks"]["shenyao"]["menial"] = 0
	g.s["peaks"]["shenyao"]["deputy"] = [g.s["people"][0]["id"]]
	_ok(g._peak_open("shenyao", true), "青芜峰仅副手 → 开工门槛开启")
	g.s["peaks"]["shenyao"]["deputy"] = []
	_ok(not g._peak_open("shenyao", true), "青芜峰无领队/杂役/外门/副手 → 不开工")


# ── 开工门槛：丹宸峰仅副手（无领队/无外门）→ 开门 ──
func _test_danding_deputy_produces() -> void:
	print("── 丹宸峰副手开工门槛 ──")
	var g := _game()
	g.s["peaks"]["danding"]["leader"] = null
	g.s["peaks"]["danding"]["deputy"] = [g.s["people"][0]["id"]]
	_ok(g._peak_open("danding", false), "丹宸峰仅副手 → 开工门槛开启")
	g.s["peaks"]["danding"]["deputy"] = []
	_ok(not g._peak_open("danding", false), "丹宸峰无领队/外门/副手 → 不开工")


# ── 需求 #6：丹宸峰无领队、仅外门 → 产出丹药 ───────────
func _test_danding_outer_produces() -> void:
	print("── 丹宸峰外门炼丹 ──")
	var g := _game()
	var outer := g.make_person({"name": "外门甲", "linggenIdx": 0, "famiIdx": 0})
	outer["inner"] = false
	outer["peak"] = "danding"
	g.s["people"].append(outer)
	g.s["peaks"]["danding"]["leader"] = null
	var pill: Dictionary = DataCore.PILLS[int(g.s["peaks"]["danding"]["pill"])]
	var lv := int(pill["lv"])
	g.s["herbs"][lv] = 5000   # 每旬消耗 2，需足够支撑到 progress 满 100
	var before: int = int(g.s["pills"].get(int(g.s["peaks"]["danding"]["pill"]), 0))
	# 外门效率按需求 #3 已调为 20%：1 外门无领队时进度 ≈0.288/旬，需 ~350 旬出一枚丹药
	for i in 1200:
		g.production()
	var after: int = int(g.s["pills"].get(int(g.s["peaks"]["danding"]["pill"]), 0))
	_ok(after > before, "丹宸峰无领队、仅 1 外门 → 炼出丹药", "before=%d after=%d" % [before, after])


# ── 需求 #6：玄铸峰无领队、仅外门 → 产出法宝 ───────────
func _test_baiqi_outer_produces() -> void:
	print("── 玄铸峰外门炼器 ──")
	var g := _game()
	var outer := g.make_person({"name": "外门乙", "linggenIdx": 0, "famiIdx": 0})
	outer["inner"] = false
	outer["peak"] = "baiqi"
	g.s["people"].append(outer)
	g.s["peaks"]["baiqi"]["leader"] = null
	var lv := int(g.s["peaks"]["baiqi"]["equipLv"])
	g.s["ores"][lv] = 5000   # 每旬消耗 3，需足够支撑到 progress 满 100
	var before: int = g.s["equips"].size()
	# 外门效率按需求 #3 已调为 20%：1 外门无领队时进度 ≈0.23/旬，需 ~440 旬铸一件法宝
	for i in 1200:
		g.production()
	var after: int = g.s["equips"].size()
	_ok(after > before, "玄铸峰无领队、仅 1 外门 → 铸出法宝", "before=%d after=%d" % [before, after])


# ── 需求 #1：师徒修炼加成（师傅 realm=3 → +0.2，封顶 0.4）
func _test_master_apprentice_bonus() -> void:
	print("── 师徒修炼加成 ──")
	var g := _game()
	var m := g.make_person({"name": "师尊", "linggenIdx": 0, "famiIdx": 0})
	m["realm"] = 3   # make_person 忽略传入的 realm，需手动设置
	var a := g.make_person({"name": "徒弟", "linggenIdx": 0, "famiIdx": 0})
	g.s["people"].append(m)
	g.s["people"].append(a)
	a["master"] = null
	# perm=true 排除心情缩放，使师徒加成(+0.2)可被精确断言
	var before_e := g.eff(a, "cultivate", true)
	g.set_master(a["id"], m["id"])
	var after_e := g.eff(a, "cultivate", true)
	_ok(absf(after_e - before_e - 0.2) < 1e-6, "师徒使徒弟修炼效率 +0.2（师傅 realm3）",
		"d=%.4f" % (after_e - before_e))


# ── 需求 #1：子嗣灵根取双亲元素并集（子集）──────────────
func _test_child_elements() -> void:
	print("── 子嗣灵根并集 ──")
	var g := _game()
	var fa := g.make_person({"elements": ["火", "水"]})
	var mo := g.make_person({"elements": ["木"]})
	var child := g._make_child(fa, mo)
	var union: Array = ["火", "水", "木"]
	var all_in := true
	for e in child["elements"]:
		if not (union as Array).has(e):
			all_in = false
			break
	_ok(all_in, "子嗣灵根取自双亲并集", str(child["elements"]))


# ── 需求 #2：撰书阁功法按「书 req 灵根 ÷ 弟子灵根数」比例生效
func _test_book_ratio() -> void:
	print("── 撰书阁比例加成 ──")
	var g := _game()
	var book := {"req": ["火"], "attrs": {"plant": 0.1}}
	# make_person 按灵根档位截取元素数：三灵根=idx5 / 双灵根=idx4 / 单灵根=idx3
	var d3 := g.make_person({"linggenIdx": 5, "elements": ["火", "木", "水"]})
	var d2 := g.make_person({"linggenIdx": 4, "elements": ["火", "水"]})
	var d1 := g.make_person({"linggenIdx": 3, "elements": ["火"]})
	var d0 := g.make_person({"linggenIdx": 3, "elements": ["木"]})
	_ok(absf(g._book_ratio(d3, book) - 1.0 / 3.0) < 1e-6, "三灵根弟子（火木水）对火单属性书加成 1/3",
		"r=%.4f" % g._book_ratio(d3, book))
	_ok(absf(g._book_ratio(d2, book) - 0.5) < 1e-6, "双灵根弟子（火水）加成 1/2",
		"r=%.4f" % g._book_ratio(d2, book))
	_ok(absf(g._book_ratio(d1, book) - 1.0) < 1e-6, "单灵根弟子（火）加成 100%",
		"r=%.4f" % g._book_ratio(d1, book))
	_ok(absf(g._book_ratio(d0, book) - 0.0) < 1e-6, "无匹配灵根弟子加成 0%",
		"r=%.4f" % g._book_ratio(d0, book))
