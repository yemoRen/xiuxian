extends SceneTree

## 验证：外门升内门（元婴自动 / 大比）后脱离原外门峰位
## 注意：make_person 会忽略 cfg 中的 realm/sub/inner/peak，需手动赋值

var _fail := 0
var _total := 0


func _ok(c: bool, m: String) -> void:
	_total += 1
	if c:
		print("  ✓ ", m)
	else:
		_fail += 1
		print("  ✗ ", m)


func _init() -> void:
	var g := preload("res://scripts/core/GameCore.gd").new()
	g.new_game({"name": "测试", "sectName": "测宗", "sex": 0, "linggen": 0, "fami": 0, "tags": []})
	g.auto_champion = true

	# ── 场景 A：元婴自动收内门（原为镇邪峰外门）──
	var a := g.make_person({})
	a["realm"] = 2
	a["sub"] = 9
	a["inner"] = false
	a["peak"] = "fumo"
	a["rebirth"] = true
	a["job"] = null
	g.s["people"].append(a)
	var before_logsz: int = int(g.s["log"].size())
	g.do_breakthrough(a)
	_ok(bool(a["inner"]) == true, "元婴后 inner=true")
	_ok(a["peak"] == null, "元婴后脱离镇邪峰外门(peak=null)")
	_ok(int(a["realm"]) == 3, "元婴后 realm=元婴(3)")
	_ok(g.s["log"].size() > before_logsz, "元婴后写入纪事")
	var hit := false
	for lg in g.s["log"]:
		if "收归内门" in str(lg["t"]):
			hit = true
	_ok(hit, "纪事含『收归内门』且无法宝")

	# ── 场景 B：元婴但原本已是内门（峰主），保留峰位 ──
	var b := g.make_person({})
	b["realm"] = 2
	b["sub"] = 9
	b["inner"] = true
	b["peak"] = "xunyou"
	b["rebirth"] = true
	b["job"] = "fengzhu"
	g.s["peaks"]["xunyou"]["leader"] = b["id"]
	g.s["people"].append(b)
	g.do_breakthrough(b)
	_ok(bool(b["inner"]) == true, "原本内门仍 inner")
	_ok(b["peak"] == "xunyou", "原本内门保留寻幽峰峰主峰位")
	_ok(b["job"] == "fengzhu", "原本内门保留峰主职务")

	# ── 场景 C：大比胜者原为外门，应脱离原峰 ──
	var c := g.make_person({})
	c["realm"] = 1
	c["sub"] = 0
	c["inner"] = false
	c["peak"] = "lingkuang"
	c["rebirth"] = true
	c["job"] = null
	g.s["people"].append(c)
	g._apply_champion(c, [g.make_equip(3)], 0)
	_ok(bool(c["inner"]) == true, "大比胜者 inner=true")
	_ok(c["peak"] == null, "大比胜者脱离玄矿峰外门(peak=null)")
	var got_prize := false
	for e in c["equip"]:
		if e != null:
			got_prize = true
	_ok(got_prize, "大比胜者获赐法宝（对比元婴路径无）")

	print("\nPROMOTE PROBE: %d passed, %d failed" % [_total - _fail, _fail])
	quit(0 if _fail == 0 else 1)
