extends SceneTree

## 结构化效果（eff）回归测试 —— 路线 B
## 运行：godot --headless --path <工程> --script res://scripts/test/EffTest.gd
##
## 覆盖：
##  [1] 11 个 eff 键逐个单测（同一状态快照，断言增量）
##  [2] 16 条带 eff 的新事件逐条施加，断言实际增量 == eff 声明
##  [3] 16 条新事件的「文案写的」== 「eff 声明的」（防止再出现文案与实现不符）
##  [4] eff 模式完全接管：不再附加通用 ±10 心情
##  [5] 旧路径零回归：无 eff 的 34 条仍走字面匹配，行为不变
##  [6] 越界保护：扣减不会出现负数、心情上下限钳制

const REALM := 3          # 测试当事人境界，决定灵石倍率 (1+3*2)=7
const STONE_MUL := 7.0

var _pass := 0
var _fail := 0
var _failures: Array = []


func _initialize() -> void:
	print("═══════════════════════════════════════════")
	print(" 修仙门派 · eff 结构化效果测试")
	print("═══════════════════════════════════════════")
	_test_key_dispatch()
	_test_new_events()
	_test_text_matches_eff()
	_test_no_common_mood()
	_test_legacy_unchanged()
	_test_floor_guards()
	print("───────────────────────────────────────────")
	print(" 通过 %d / 失败 %d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("   ✗ ", f)
	print("═══════════════════════════════════════════")
	quit(1 if _fail > 0 else 0)


# ═══════════════════════════════════════════════════════
# 基础设施
# ═══════════════════════════════════════════════════════

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


## 造一个可控的当事人：全部加清零、心情给 60，便于断言精确增量
func _subj(g: GameCore, sex: int = 0) -> Dictionary:
	var p := g.make_person({
		"name": "被试者", "sex": sex, "linggenIdx": 0, "famiIdx": 0,
		"tags": [], "age": 30,
	})
	p["realm"] = REALM
	p["qi"] = 500.0
	p["mood"] = 60.0
	p["atkBonus"] = 1.0
	p["qiRateB"] = 0.0
	p["brkBonus"] = 0.0
	g.s["people"].append(p)
	return p


## 给足存量，保证扣减类事件不会因为"空库存"而变成 no-op
func _seed(g: GameCore) -> void:
	for k in range(1, 10):
		g.s["pills"][k] = 5
	for i in 10:
		g.s["herbs"][i] = 5
		g.s["ores"][i] = 5
	g.s["stone"] = 100000.0


func _snap(g: GameCore, p: Dictionary) -> Dictionary:
	return {
		"mood": float(p["mood"]),
		"qi": float(p["qi"]),
		"atkBonus": float(p["atkBonus"]),
		"qiRateB": float(p["qiRateB"]),
		"brkBonus": float(p["brkBonus"]),
		"stone": float(g.s["stone"]),
		"pills": float(_sum_dict(g.s["pills"])),
		"herbs": float(_sum_arr(g.s["herbs"])),
		"ores": float(_sum_arr(g.s["ores"])),
		"equips": float((g.s["equips"] as Array).size()),
	}


func _sum_dict(d: Dictionary) -> int:
	var t := 0
	for k in d.keys():
		t += int(d[k])
	return t


func _sum_arr(a: Array) -> int:
	var t := 0
	for v in a:
		t += int(v)
	return t


func _delta(g: GameCore, p: Dictionary, kind: String, eff: Array) -> Dictionary:
	var before := _snap(g, p)
	g.apply_event(p, {"w": 1, "kind": kind, "t": "（测试用事件）", "eff": eff})
	var after := _snap(g, p)
	var d := {}
	for k in before.keys():
		d[k] = after[k] - before[k]
	return d


func _find_ev(sub: String) -> Dictionary:
	for e in DataCore.EVENTS:
		var d: Dictionary = e
		if str(d["t"]).contains(sub):
			return d
	return {}


func _eff_events() -> Array:
	var out: Array = []
	for e in DataCore.EVENTS:
		var d: Dictionary = e
		if d.has("eff"):
			out.append(d)
	return out


# ═══════════════════════════════════════════════════════
# [1] 11 个 eff 键逐个单测
# ═══════════════════════════════════════════════════════
func _test_key_dispatch() -> void:
	print("\n[1] eff 键派发")
	# qiRate / atk / brk / mood / qi —— 精确值
	for spec in [["qiRate", 0.05, "qiRateB"], ["atk", 0.15, "atkBonus"], ["brk", -0.05, "brkBonus"]]:
		var g := _game()
		var p := _subj(g)
		var d := _delta(g, p, "good", [[str(spec[0]), float(spec[1])]])
		_ok(is_equal_approx(float(d[str(spec[2])]), float(spec[1])),
			"键 %s：±%.2f" % [spec[0], spec[1]], "实际 %+.4f" % d[str(spec[2])])

	var g2 := _game()
	var p2 := _subj(g2)
	var d2 := _delta(g2, p2, "good", [["mood", 30.0]])
	_ok(is_equal_approx(float(d2["mood"]), 30.0), "键 mood：+30", "实际 %+.1f" % d2["mood"])

	var g3 := _game()
	var p3 := _subj(g3)
	var qmax := g3.qi_max(p3)
	var d3 := _delta(g3, p3, "bad", [["qi", -0.2]])
	_ok(is_equal_approx(float(d3["qi"]), -qmax * 0.2), "键 qi：-上限×20%",
		"实际 %+.1f / 预期 %+.1f" % [d3["qi"], -qmax * 0.2])

	# stone —— 区间值
	var g4 := _game()
	var p4 := _subj(g4)
	var d4 := _delta(g4, p4, "good", [["stone", 1.0]])
	_ok(d4["stone"] > 0.0 and d4["stone"] >= 500.0 * STONE_MUL and d4["stone"] <= 5000.0 * STONE_MUL,
		"键 stone：获得一笔（500~5000 ×7）", "实际 %+.0f" % d4["stone"])

	var g5 := _game()
	var p5 := _subj(g5)
	var d5 := _delta(g5, p5, "bad", [["stone", -1.0]])
	_ok(d5["stone"] < 0.0 and d5["stone"] <= -500.0 and d5["stone"] >= -5000.0,
		"键 stone：损失一笔（500~5000，不带倍率）", "实际 %+.0f" % d5["stone"])

	# pill / herb / ore / equips —— 计数
	for spec2 in [["pill", "pills"], ["herb", "herbs"], ["ore", "ores"], ["equips", "equips"]]:
		var g6 := _game()
		var p6 := _subj(g6)
		_seed(g6)
		var d6 := _delta(g6, p6, "good", [[str(spec2[0]), 1.0]])
		_ok(is_equal_approx(float(d6[str(spec2[1])]), 1.0),
			"键 %s：+1" % spec2[0], "实际 %+.0f" % d6[str(spec2[1])])

	# marry
	var g7 := _game()
	var p7 := _subj(g7, 0)
	var mate := g7.make_person({"name": "道侣候选", "sex": 1, "linggenIdx": 0, "famiIdx": 0, "tags": [], "age": 25})
	g7.s["people"].append(mate)
	var brk_before := float(p7["brkBonus"])
	var d7 := _delta(g7, p7, "love", [["marry"]])
	_ok(p7["spouse"] != null, "键 marry：结为道侣", "spouse=%s" % str(p7["spouse"]))
	var mate_ok := false
	if p7["spouse"] != null:
		var sp := g7.by_id(p7["spouse"])
		mate_ok = not sp.is_empty() and sp["spouse"] == p7["id"]
	_ok(mate_ok, "键 marry：双向绑定")
	_ok(is_equal_approx(float(d7["brkBonus"]), 0.10), "键 marry：本人突破 +10%",
		"实际 %+.3f（原 %+.3f）" % [d7["brkBonus"], brk_before])

	# 未知键不崩、不静默
	var g8 := _game()
	var p8 := _subj(g8)
	var d8 := _delta(g8, p8, "good", [["不存在的键", 1.0]])
	var warned := false
	for rec in g8.s["log"]:
		if str(rec["t"]).contains("未知效果键"):
			warned = true
	_ok(warned and is_equal_approx(float(d8["mood"]), 0.0),
		"未知键：写日志告警且不施加任何效果")


# ═══════════════════════════════════════════════════════
# [2] 16 条带 eff 的事件逐条施加
# ═══════════════════════════════════════════════════════
func _test_new_events() -> void:
	print("\n[2] 带 eff 的事件逐条施加（实际增量 == eff 声明）")
	var evs := _eff_events()
	_ok(evs.size() == 16, "带 eff 的事件共 16 条", "实际 %d 条" % evs.size())
	for e in evs:
		var ev: Dictionary = e
		var g := _game()
		var p := _subj(g)
		_seed(g)
		var t := str(ev["t"]).replace("{n}", "被试者")
		_check_delta("「%s…」" % t.substr(0, 12), g, p, ev["eff"] as Array)


func _check_delta(label: String, g: GameCore, p: Dictionary, eff: Array) -> void:
	var kind := str(_kind_of(eff))
	for item in eff:
		var pair: Array = item
		var key := str(pair[0])
		var v := 0.0
		if pair.size() > 1:
			v = float(pair[1])
		var d := _delta(g, p, kind, [pair])
		match key:
			"mood":
				_ok(is_equal_approx(d["mood"], v), label + " 心情 %+.0f" % v, "实际 %+.1f" % d["mood"])
			"qiRate":
				_ok(is_equal_approx(d["qiRateB"], v), label + " 修炼速度 %+.0f%%" % (v * 100.0),
					"实际 %+.4f" % d["qiRateB"])
			"atk":
				_ok(is_equal_approx(d["atkBonus"], v), label + " 武力 %+.0f%%" % (v * 100.0),
					"实际 %+.4f" % d["atkBonus"])
			"brk":
				_ok(is_equal_approx(d["brkBonus"], v), label + " 突破 %+.0f%%" % (v * 100.0),
					"实际 %+.4f" % d["brkBonus"])
			"qi":
				var qmax := g.qi_max(p)
				_ok(is_equal_approx(d["qi"], qmax * v), label + " 修为 %+.0f%%上限" % (v * 100.0),
					"实际 %+.1f" % d["qi"])
			"stone":
				if v > 0.0:
					_ok(d["stone"] > 0.0 and d["stone"] >= 500.0 * STONE_MUL, label + " 灵石 +一笔",
						"实际 %+.0f" % d["stone"])
				else:
					_ok(d["stone"] < 0.0 and d["stone"] <= -500.0, label + " 灵石 -一笔",
						"实际 %+.0f" % d["stone"])
			"pill":
				_ok(is_equal_approx(d["pills"], v), label + " 丹药 %+.0f" % v, "实际 %+.0f" % d["pills"])
			"herb":
				_ok(is_equal_approx(d["herbs"], v), label + " 灵草 %+.0f" % v, "实际 %+.0f" % d["herbs"])
			"ore":
				_ok(is_equal_approx(d["ores"], v), label + " 矿石 %+.0f" % v, "实际 %+.0f" % d["ores"])
			"equips":
				_ok(is_equal_approx(d["equips"], v), label + " 法宝 %+.0f" % v, "实际 %+.0f" % d["equips"])
			"marry":
				_ok(p["spouse"] != null, label + " 结为道侣")


## 从 eff 推断事件类别（mood 为负 → bad，marry → love，其余 good）
func _kind_of(eff: Array) -> String:
	for item in eff:
		var pair: Array = item
		if str(pair[0]) == "marry":
			return "love"
	for item in eff:
		var pair2: Array = item
		if str(pair2[0]) == "mood" and pair2.size() > 1 and float(pair2[1]) < 0.0:
			return "bad"
	return "good"


# ═══════════════════════════════════════════════════════
# [3] 文案写的 == eff 声明的
# ═══════════════════════════════════════════════════════
func _test_text_matches_eff() -> void:
	print("\n[3] 文案声明 == eff 声明")
	var bad := 0
	for e in _eff_events():
		var ev: Dictionary = e
		var msg := _declared_vs_eff(str(ev["t"]), ev["eff"] as Array)
		if msg != "":
			bad += 1
			_ok(false, "「%s…」" % str(ev["t"]).substr(0, 14), msg)
	_ok(bad == 0, "16 条新事件的文案与 eff 一一对应", "不符 %d 条" % bad)


func _declared_vs_eff(t: String, eff: Array) -> String:
	for item in eff:
		var pair: Array = item
		var key := str(pair[0])
		var v := 0.0
		if pair.size() > 1:
			v = float(pair[1])
		var iv := int(round(absf(v)))            # 绝对数值（心情等）
		var pc := int(round(absf(v) * 100.0))    # 百分比数值（突破/修为）
		match key:
			"mood":
				var want: String = ("心情 +%d" % iv) if v >= 0.0 else ("心情 -%d" % iv)
				if not t.contains(want):
					return "eff mood %+.0f 但文案缺「%s」" % [v, want]
			"qiRate":
				if not t.contains("修炼速度 +%d%%" % int(round(v * 100.0))):
					return "eff qiRate 但文案缺「修炼速度 +%d%%」" % int(round(v * 100.0))
			"atk":
				if not t.contains("武力 +%d%%" % int(round(v * 100.0))):
					return "eff atk 但文案缺「武力 +%d%%」" % int(round(v * 100.0))
			"brk":
				var want2: String = ("突破几率 +%d%%" % pc) if v >= 0.0 else ("突破几率 -%d%%" % pc)
				if not t.contains(want2):
					return "eff brk 但文案缺「%s」" % want2
			"qi":
				if not t.contains("修为 -%d%%" % pc):
					return "eff qi 但文案缺「修为 -%d%%」" % pc
			"stone":
				var want3: String = "灵石 +{s}" if v > 0.0 else "灵石 -{s}"
				if not t.contains(want3):
					return "eff stone 但文案缺「%s」" % want3
			"pill":
				var want4: String = "丹药 +1（{l}）" if v > 0.0 else "丹药 -1（{l}）"
				if not t.contains(want4):
					return "eff pill 但文案缺「%s」" % want4
			"herb":
				var want5: String = "灵草 +1（{h}）" if v > 0.0 else "灵草 -1（{h}）"
				if not t.contains(want5):
					return "eff herb 但文案缺「%s」" % want5
			"ore":
				var want6: String = "矿石 +1（{o}）" if v > 0.0 else "矿石 -1（{o}）"
				if not t.contains(want6):
					return "eff ore 但文案缺「%s」" % want6
			"equips":
				if not t.contains("法宝 +%d" % iv):
					return "eff equips 但文案缺「法宝 +%d」" % iv
			"marry":
				if not t.contains("成眷属"):
					return "eff marry 但文案未提成亲"
	return ""


# ═══════════════════════════════════════════════════════
# [4] eff 模式完全接管
# ═══════════════════════════════════════════════════════
func _test_no_common_mood() -> void:
	print("\n[4] eff 模式完全接管（不附加通用 ±10 心情）")
	var g1 := _game()
	var p1 := _subj(g1)
	var d1 := _delta(g1, p1, "good", [["mood", 30.0]])
	_ok(is_equal_approx(d1["mood"], 30.0), "吉事件声明 +30 → 就是 +30（不是 +40）", "实际 %+.1f" % d1["mood"])

	var g2 := _game()
	var p2 := _subj(g2)
	var d2 := _delta(g2, p2, "bad", [["mood", -30.0]])
	_ok(is_equal_approx(d2["mood"], -30.0), "凶事件声明 -30 → 就是 -30（不是 -40）", "实际 %+.1f" % d2["mood"])

	# 只声明属性的吉事件，不应额外送 10 点心情
	var g3 := _game()
	var p3 := _subj(g3)
	var d3 := _delta(g3, p3, "good", [["qiRate", 0.05]])
	_ok(is_equal_approx(d3["mood"], 0.0), "未声明心情 → 心情不变", "实际 %+.1f" % d3["mood"])


# ═══════════════════════════════════════════════════════
# [5] 旧路径零回归
# ═══════════════════════════════════════════════════════
func _test_legacy_unchanged() -> void:
	print("\n[5] 旧路径（无 eff）零回归")
	var total := DataCore.EVENTS.size()
	var eff_n := _eff_events().size()
	_ok(total == 50, "事件总数 50", "实际 %d" % total)
	_ok(eff_n == 16 and total - eff_n == 34, "16 条走 eff / 34 条走字面匹配",
		"%d / %d" % [eff_n, total - eff_n])

	# 吉：武力 +（斩一恶蛟）→ 心情 +10（通用）、武力 +10%
	var g1 := _game()
	var p1 := _subj(g1)
	var ev1 := _find_ev("斩一恶蛟")
	_ok(not ev1.is_empty() and not ev1.has("eff"), "「斩一恶蛟」仍走字面匹配")
	var g1b := _game()
	var p1b := _subj(g1b)
	var b1 := _snap(g1b, p1b)
	g1b.apply_event(p1b, ev1)
	var a1 := _snap(g1b, p1b)
	_ok(is_equal_approx(a1["mood"] - b1["mood"], 10.0) and is_equal_approx(a1["atkBonus"] - b1["atkBonus"], 0.10),
		"「斩一恶蛟」→ 心情 +10、武力 +10%",
		"心情 %+.1f / 武力 %+.3f" % [a1["mood"] - b1["mood"], a1["atkBonus"] - b1["atkBonus"]])

	# 凶：修为 -（修炼岔了气息）→ 心情 -10、修为 -上限×20%
	var g2 := _game()
	var p2 := _subj(g2)
	var ev2 := _find_ev("修炼时岔了气息")
	var b2 := _snap(g2, p2)
	g2.apply_event(p2, ev2)
	var a2 := _snap(g2, p2)
	var qmax := g2.qi_max(p2)
	_ok(is_equal_approx(a2["mood"] - b2["mood"], -10.0) and is_equal_approx(a2["qi"] - b2["qi"], -qmax * 0.2),
		"「修炼岔了气息」→ 心情 -10、修为 -上限×20%",
		"心情 %+.1f / 修为 %+.1f" % [a2["mood"] - b2["mood"], a2["qi"] - b2["qi"]])

	# 平常：完全无副作用
	var g3 := _game()
	var p3 := _subj(g3)
	var ev3 := _find_ev("茶摊")
	var b3 := _snap(g3, p3)
	g3.apply_event(p3, ev3)
	var a3 := _snap(g3, p3)
	var same := true
	for k in b3.keys():
		if not is_equal_approx(float(a3[k]), float(b3[k])):
			same = false
	_ok(same, "平常事件（茶摊）→ 状态零变化")

	# 情缘：结为了道侣 → 心情 +15、双向绑定
	var g4 := _game()
	var p4 := _subj(g4, 0)
	g4.s["people"].append(g4.make_person({"name": "道侣候选", "sex": 1, "linggenIdx": 0, "famiIdx": 0, "tags": [], "age": 25}))
	var ev4 := _find_ev("结为了道侣")
	var b4 := _snap(g4, p4)
	g4.apply_event(p4, ev4)
	var a4 := _snap(g4, p4)
	_ok(is_equal_approx(a4["mood"] - b4["mood"], 15.0) and p4["spouse"] != null,
		"「结为了道侣」→ 心情 +15、结为道侣", "心情 %+.1f" % (a4["mood"] - b4["mood"]))


# ═══════════════════════════════════════════════════════
# [6] 越界保护
# ═══════════════════════════════════════════════════════
func _test_floor_guards() -> void:
	print("\n[6] 越界保护")
	var g1 := _game()
	var p1 := _subj(g1)
	g1.s["pills"] = {}
	for i in 10:
		g1.s["herbs"][i] = 0
		g1.s["ores"][i] = 0
	g1.s["stone"] = 100.0
	var d1 := _delta(g1, p1, "bad", [["pill", -1.0], ["herb", -1.0], ["ore", -1.0]])
	_ok(is_equal_approx(d1["pills"], 0.0) and is_equal_approx(d1["herbs"], 0.0) and is_equal_approx(d1["ores"], 0.0),
		"空库存扣减 → 不产生负数、不报错")
	var d1b := _delta(g1, p1, "bad", [["stone", -1.0]])
	_ok(float(g1.s["stone"]) >= 0.0, "灵石扣减 → 不低于 0", "实际 %.1f" % g1.s["stone"])
	_ok(d1b["stone"] <= 0.0, "灵石确实被扣（有库存时）", "%+.0f" % d1b["stone"])

	var g2 := _game()
	var p2 := _subj(g2)
	p2["mood"] = 5.0
	var d2 := _delta(g2, p2, "bad", [["mood", -30.0]])
	_ok(is_equal_approx(float(p2["mood"]), 0.0), "心情下限 0", "实际 %.1f" % p2["mood"])

	var g3 := _game()
	var p3 := _subj(g3)
	p3["mood"] = 95.0
	_delta(g3, p3, "good", [["mood", 30.0]])
	_ok(is_equal_approx(float(p3["mood"]), 100.0), "心情上限 100", "实际 %.1f" % p3["mood"])

	var g4 := _game()
	var p4 := _subj(g4)
	p4["qi"] = 10.0
	var d4 := _delta(g4, p4, "bad", [["qi", -0.2]])
	_ok(float(p4["qi"]) >= 0.0, "修为扣减不低于 0", "实际 %.1f" % p4["qi"])
	_ok(d4["qi"] <= 0.0, "修为确实被扣", "%+.1f" % d4["qi"])
