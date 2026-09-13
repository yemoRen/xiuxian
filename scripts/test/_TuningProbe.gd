extends SceneTree

## 调参回归探针：#1 杂役上限 / #2 四峰门槛守门 / #3 各峰效率比例
## 运行：godot --headless --path <工程> --script res://scripts/test/_TuningProbe.gd

var _pass := 0
var _fail := 0
var _failures: Array = []


func _initialize() -> void:
	print("══════════════════════════════════════════════════")
	print(" 杂役上限 / 四峰门槛 / 效率比例 探针")
	print("══════════════════════════════════════════════════")
	_test_global_cap()
	_test_peak_cap()
	_test_gate_no_production()
	_test_leader_100pct()
	_test_deputy_50pct()
	_test_outer_20pct()
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


# ── #1：杂役总人数上限 1200 ──────────────────────────────
func _test_global_cap() -> void:
	print("── 杂役总人数上限 1200 ──")
	var g: GameCore = _game()
	# 直接越界注入（模拟旧存档/异常），硬上限应夹回 1200
	g.s["menial"] = 99999
	g.s["protect"] = 99999.0
	g.s["year"] = 0
	g._grow_menial()
	_ok(int(g.s["menial"]) <= 1200, "越界注入后杂役总数被夹到 ≤ 1200", "menial=%d" % int(g.s["menial"]))
	_ok(int(g.s["menial"]) == 1200, "越界注入后恰好为上限 1200", "menial=%d" % int(g.s["menial"]))
	# 长年高庇护增长也应停在 1200
	g.s["menial"] = 0
	g.s["protect"] = 99999.0
	g.s["year"] = 0
	for i in 50:
		g.on_year()
	_ok(int(g.s["menial"]) == 1200, "长年高庇护后稳定在 1200", "menial=%d" % int(g.s["menial"]))


# ── #1：单峰杂役目标/在岗上限 200 ───────────────────────
func _test_peak_cap() -> void:
	print("── 单峰杂役上限 200 ──")
	var g: GameCore = _game()
	g.s["menial"] = 999999
	g.s["peaks"]["shenyao"]["menial"] = 999
	g.s["peaks"]["lingkuang"]["menial"] = 999
	g._alloc_menial()
	_ok(int(g.s["peaks"]["shenyao"]["menialOn"]) <= 200, "青芜峰在岗杂役 ≤ 200", "%d" % int(g.s["peaks"]["shenyao"]["menialOn"]))
	_ok(int(g.s["peaks"]["lingkuang"]["menialOn"]) <= 200, "玄矿峰在岗杂役 ≤ 200", "%d" % int(g.s["peaks"]["lingkuang"]["menialOn"]))


# ── #2：四峰未达门槛不产生任何收益 ──────────────────────
func _close_peak(g: GameCore, pid: String) -> void:
	var pk: Dictionary = g.s["peaks"][pid]
	pk["leader"] = null
	pk["deputy"] = []
	pk["menial"] = 0
	pk["menialOn"] = 0
	for p in g.s["people"]:
		if str(p.get("peak", "")) == pid and str(p.get("job", "")) == "outer":
			p["peak"] = ""
			p["job"] = ""


func _sum_herbs(g: GameCore) -> int:
	var s := 0
	for v in g.s["herbs"]:
		s += int(v)
	return s


func _sum_ores(g: GameCore) -> int:
	var s := 0
	for v in g.s["ores"]:
		s += int(v)
	return s


func _test_gate_no_production() -> void:
	print("── 四峰未达门槛不产生收益 ──")
	var g: GameCore = _game()
	for pid in ["shenyao", "lingkuang", "danding", "baiqi"]:
		_close_peak(g, pid)
	var h0: int = _sum_herbs(g)
	var o0: int = _sum_ores(g)
	var p0: int = g.s["pills"].size()
	var e0: int = g.s["equips"].size()
	for i in 5:
		g.production()
	var h1: int = _sum_herbs(g)
	var o1: int = _sum_ores(g)
	var p1: int = g.s["pills"].size()
	var e1: int = g.s["equips"].size()
	_ok(h1 == h0, "青芜/玄矿未达门槛 → 灵草总量不变", "%d→%d" % [h0, h1])
	_ok(o1 == o0, "玄矿未达门槛 → 灵矿总量不变", "%d→%d" % [o0, o1])
	_ok(p1 == p0, "丹宸未达门槛 → 丹药种类不变", "%d→%d" % [p0, p1])
	_ok(e1 == e0, "玄铸未达门槛 → 法宝数不变", "%d→%d" % [e0, e1])


# ── #3：峰主 100% ────────────────────────────────────────
func _test_leader_100pct() -> void:
	print("── 峰主效率 100% ──")
	var g: GameCore = _game()
	var lead: Dictionary = g.s["people"][0]
	g.s["peaks"]["shenyao"]["leader"] = lead["id"]
	g.s["peaks"]["shenyao"]["deputy"] = []
	g.s["peaks"]["shenyao"]["menialOn"] = 0
	var le: float = g.eff(lead, "plant")
	var y: float = g.peak_yield("shenyao", "plant")
	_ok(absf(y - le * 1.0) < 1e-6, "峰主贡献 100%（无副手/外门/杂役）", "y=%.4f 期望=%.4f" % [y, le])


# ── #3：副手 50% ─────────────────────────────────────────
func _test_deputy_50pct() -> void:
	print("── 副手效率 50% ──")
	var g: GameCore = _game()
	var lead: Dictionary = g.s["people"][0]
	var dep: Dictionary = g.make_person({"name": "副手", "linggenIdx": 0, "famiIdx": 0})
	dep["inner"] = true
	g.s["people"].append(dep)
	g.s["peaks"]["shenyao"]["leader"] = lead["id"]
	g.s["peaks"]["shenyao"]["deputy"] = [dep["id"]]
	g.s["peaks"]["shenyao"]["menialOn"] = 0
	var le: float = g.eff(lead, "plant")
	var de: float = g.eff(dep, "plant")
	var y: float = g.peak_yield("shenyao", "plant")
	var expect: float = le * 1.0 + de * 0.5
	_ok(absf(y - expect) < 1e-6, "副手贡献 50%（峰主100%+副手50%）", "y=%.4f 期望=%.4f" % [y, expect])


# ── #3：外门 20% ────────────────────────────────────────
func _test_outer_20pct() -> void:
	print("── 外门效率 20% ──")
	var g: GameCore = _game()
	var lead: Dictionary = g.s["people"][0]
	var outer: Dictionary = g.make_person({"name": "外门", "linggenIdx": 0, "famiIdx": 0})
	outer["inner"] = false
	outer["peak"] = "shenyao"
	outer["job"] = "outer"
	g.s["people"].append(outer)
	g.s["peaks"]["shenyao"]["leader"] = lead["id"]
	g.s["peaks"]["shenyao"]["deputy"] = []
	g.s["peaks"]["shenyao"]["menialOn"] = 0
	var le: float = g.eff(lead, "plant")
	var oe: float = g.eff(outer, "plant")
	var y: float = g.peak_yield("shenyao", "plant")
	var expect: float = le * 1.0 + oe * 0.2
	_ok(absf(y - expect) < 1e-6, "外门贡献 20%（峰主100%+外门20%）", "y=%.4f 期望=%.4f" % [y, expect])
	# 反证：不应是旧的 50% 模型
	var old_expect: float = le + oe * 0.5
	_ok(absf(y - old_expect) >= 1e-6 or oe <= 0.0, "外门非 50%（已调为 20%）", "y=%.4f 旧模型=%.4f" % [y, old_expect])
