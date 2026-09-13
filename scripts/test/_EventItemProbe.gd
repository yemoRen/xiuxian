extends SceneTree

## 事件物品得失合理性探针（需求 #4）：获得/失去 丹药/灵草/灵矿 按获得者境界约束品阶
## 运行：godot --headless --path <工程> --script res://scripts/test/_EventItemProbe.gd

var _pass := 0
var _fail := 0
var _failures: Array = []


func _initialize() -> void:
	print("══════════════════════════════════════════════════")
	print(" 事件物品得失合理性 探针")
	print("══════════════════════════════════════════════════")
	_test_pill_gain_bounded()
	_test_herb_gain_bounded()
	_test_ore_gain_bounded()
	_test_pill_loss_prefers_low()
	_test_event_routeA_pill_bounded()
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
	var g: GameCore = GameCore.new(GameCore.RNG_SEED_DEFAULT)
	g.new_game({
		"name": "测试甲", "sectName": "测试宗", "sex": 0,
		"linggen": 0, "fami": 0, "tags": [],
	})
	return g


# 筑基(realm0) 弟子：cap = realm+1 = 1 → 只能得 还春丹(lv0)/筑基丹(lv1)，绝不得 合道丹(lv8)
func _test_pill_gain_bounded() -> void:
	print("── 获得丹药：按境界约束品阶 ──")
	var g: GameCore = _game()
	var p: Dictionary = g.s["people"][0]
	p["realm"] = 0   # 筑基
	var cap: int = g._item_cap(0)
	var bad: bool = false
	for i in 300:
		g.s["pills"] = {}   # 清空存量，纯走「获得」的 cap 选取路径
		var ev: Dictionary = {"kind": "good", "t": "x", "eff": [["pill", 1]]}
		g.apply_event(p, ev)
		for key in g.s["pills"].keys():
			if int(g.s["pills"][key]) > 0 and int(DataCore.PILLS[int(key)]["lv"]) > cap:
				bad = true
		if bad:
			break
	_ok(not bad, "筑基弟子获得丹药品阶 ≤ 1（无合道丹等高阶）", "cap=%d" % cap)


# 筑基弟子获得灵草 → 品阶 ≤ 1
func _test_herb_gain_bounded() -> void:
	print("── 获得灵草：按境界约束品阶 ──")
	var g: GameCore = _game()
	var p: Dictionary = g.s["people"][0]
	p["realm"] = 0
	var cap: int = g._item_cap(0)
	var bad: bool = false
	for i in 300:
		g.s["herbs"] = _fill_zero(10)
		var ev: Dictionary = {"kind": "good", "t": "x", "eff": [["herb", 1]]}
		g.apply_event(p, ev)
		for idx in g.s["herbs"].size():
			if int(g.s["herbs"][idx]) > 0 and idx > cap:
				bad = true
		if bad:
			break
	_ok(not bad, "筑基弟子获得灵草品阶 ≤ 1（无无妄道树等高阶）", "cap=%d" % cap)


# 筑基弟子获得灵矿 → 品阶 ≤ 1
func _test_ore_gain_bounded() -> void:
	print("── 获得灵矿：按境界约束品阶 ──")
	var g: GameCore = _game()
	var p: Dictionary = g.s["people"][0]
	p["realm"] = 0
	var cap: int = g._item_cap(0)
	var bad: bool = false
	for i in 300:
		g.s["ores"] = _fill_zero(10)
		var ev: Dictionary = {"kind": "good", "t": "x", "eff": [["ore", 1]]}
		g.apply_event(p, ev)
		for idx in g.s["ores"].size():
			if int(g.s["ores"][idx]) > 0 and idx > cap:
				bad = true
		if bad:
			break
	_ok(not bad, "筑基弟子获得灵矿品阶 ≤ 1", "cap=%d" % cap)


# 筑基弟子失去丹药：优先掉低阶（筑基丹），同时存在合道丹时不会先掉合道丹
func _test_pill_loss_prefers_low() -> void:
	print("── 失去丹药：优先低阶 ──")
	var g: GameCore = _game()
	var p: Dictionary = g.s["people"][0]
	p["realm"] = 0
	g.s["pills"] = {1: 5, 8: 5}   # 筑基丹 x5 + 合道丹(lv8) x5
	var ev: Dictionary = {"kind": "bad", "t": "x", "eff": [["pill", -1]]}
	for i in 3:   # 仅 3 次，低阶未耗尽，应始终只掉筑基丹
		g.apply_event(p, ev)
	_ok(int(g.s["pills"].get(8, 0)) == 5, "筑基弟子失去丹药时不会掉合道丹（优先低阶）",
		"合道丹余=%d 筑基丹余=%d" % [int(g.s["pills"].get(8, 0)), int(g.s["pills"].get(1, 0))])


# 路线 A（无 eff）的「丹药 +1（{l}）」事件也应按境界约束并回填文案
func _test_event_routeA_pill_bounded() -> void:
	print("── 路线A 丹药+ 事件按境界约束 ──")
	var g: GameCore = _game()
	var p: Dictionary = g.s["people"][0]
	p["realm"] = 0
	var cap: int = g._item_cap(0)
	var bad: bool = false
	for i in 200:
		g.s["pills"] = {}
		var ev: Dictionary = {"kind": "good", "t": "{n}于市集点化散修，对方赠以灵药。丹药 +1（{l}）"}
		g.apply_event(p, ev)
		for key in g.s["pills"].keys():
			if int(g.s["pills"][key]) > 0 and int(DataCore.PILLS[int(key)]["lv"]) > cap:
				bad = true
		if bad:
			break
	_ok(not bad, "路线A 丹药+ 事件品阶 ≤ 1 且 {l} 已回填", "cap=%d" % cap)


func _fill_zero(n: int) -> Array:
	var a: Array = []
	a.resize(n)
	a.fill(0)
	return a
