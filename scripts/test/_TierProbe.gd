extends SceneTree

## 验证天阶之上的穹极/昊苍两档（lv 8/9）已接上且无越界崩溃。
## 重点：丹宸炼丹 lv8/9、玄铸炼器 lv8/9、事件随机抽到 8/9 档灵草/灵材。

var _pass := 0
var _fail := 0

func _ok(c: bool, label: String) -> void:
	if c:
		_pass += 1
		print("  ✓ ", label)
	else:
		_fail += 1
		print("  ✗ ", label)

func _initialize() -> void:
	print("═══════════════════════════════════════════")
	print(" 天阶之上（穹极/昊苍）接入验证")
	print("═══════════════════════════════════════════")

	var g := GameCore.new(GameCore.RNG_SEED_DEFAULT)
	g.new_game({"name": "龙傲天", "sectName": "凌霄宗", "sex": 0, "linggen": 0, "fami": 0, "tags": [6, 4]})

	# 数据表一致性
	_ok(DataCore.HERBS.size() == 10, "HERBS 共 10 档（荒..天,穹极,昊苍）")
	_ok(DataCore.ORES.size() == 10, "ORES 共 10 档")
	_ok(DataCore.MLEVEL.size() == 10, "MLVEL 共 10 档")
	_ok(g.s["herbs"].size() == 10, "状态 herbs 数组长度 10")
	_ok(g.s["ores"].size() == 10, "状态 ores 数组长度 10")
	_ok(DataCore.HERBS[8][0] == "万墟神藤", "穹极阶灵草[0] = 万墟神藤")
	_ok(DataCore.HERBS[9][1] == "无妄道树", "昊苍阶灵草[1] = 无妄道树")
	_ok(DataCore.HERBS[0][0] == "砂蔓草", "荒阶灵草改名 = 砂蔓草")
	_ok(DataCore.HERBS[1][2] == "七星草", "七星还魂改名 = 七星草")
	_ok(DataCore.ORES[8][0] == "穹极星髓", "穹极阶灵材[0] = 穹极星髓")
	_ok(DataCore.ORES[9][2] == "鸿蒙母金", "昊苍阶灵材[2] = 鸿蒙母金")

	# 任命峰主
	var a := g.alive_list()
	g.assign(a[0], "danding", true, false)
	g.assign(a[1] if a.size() > 1 else a[0], "baiqi", true, false)
	# 隔离：丹宸测试期间让玄铸无主，避免互相干扰
	g.s["peaks"]["baiqi"]["leader"] = null

	# 找丹方下标
	var idx_hedao := -1
	var idx_tongtian := -1
	for i in DataCore.PILLS.size():
		if DataCore.PILLS[i]["n"] == "合道丹": idx_hedao = i
		if DataCore.PILLS[i]["n"] == "通天丹": idx_tongtian = i
	_ok(idx_hedao >= 0 and idx_tongtian >= 0, "能找到合道丹/通天丹丹方")

	# ── 丹宸 lv8（穹极）：进度置满，production 一次必产 ──
	g.s["peaks"]["danding"]["pill"] = idx_hedao
	g.s["herbs"][8] = 200
	g.s["peaks"]["danding"]["progress"] = 1000.0
	var p8_before := int(g.s["pills"].get(idx_hedao, 0))
	g.production()
	var made_hedao := int(g.s["pills"].get(idx_hedao, 0)) > p8_before
	_ok(made_hedao, "丹宸炼合道丹(lv8/穹极) 成功且不崩溃")

	# ── 丹宸 lv9（昊苍）──
	g.s["peaks"]["danding"]["pill"] = idx_tongtian
	g.s["herbs"][9] = 200
	g.s["peaks"]["danding"]["progress"] = 1000.0
	var p9_before := int(g.s["pills"].get(idx_tongtian, 0))
	g.production()
	var made_tongtian := int(g.s["pills"].get(idx_tongtian, 0)) > p9_before
	_ok(made_tongtian, "丹宸炼通天丹(lv9/昊苍) 成功且不崩溃")

	# ── 玄铸 lv8（穹极）──
	g.assign(a[1] if a.size() > 1 else a[0], "baiqi", true, false)
	g.s["peaks"]["baiqi"]["equipLv"] = 8
	g.s["ores"][8] = 200
	g.s["peaks"]["baiqi"]["progress"] = 1000.0
	var eq_before := (g.s["equips"] as Array).size()
	g.production()
	var made_qi8 := false
	for e in g.s["equips"]:
		if int(e["lv"]) == 8:
			made_qi8 = true
			break
	_ok(made_qi8 and (g.s["equips"] as Array).size() > eq_before, "玄铸 lv8(穹极) 炼器成功且不崩溃")

	# ── 玄铸 lv9（昊苍）──
	g.s["peaks"]["baiqi"]["equipLv"] = 9
	g.s["ores"][9] = 200
	g.s["peaks"]["baiqi"]["progress"] = 1000.0
	g.production()
	var made_qi9 := false
	for e in g.s["equips"]:
		if int(e["lv"]) == 9:
			made_qi9 = true
			break
	_ok(made_qi9, "玄铸 lv9(昊苍) 炼器成功且不崩溃")

	# ── 事件随机抽到 0..9 各档灵草/灵材（验证 HERBS/ORES 数据全可达、无越界）──
	var event_ok := true
	for t in 10:
		for k in 10:
			g.s["herbs"][k] = 0
			g.s["ores"][k] = 0
		g.s["herbs"][t] = 5
		g.s["ores"][t] = 5
		var hi: int = g._eff_res(g.s["herbs"], -1)
		var oi: int = g._eff_res(g.s["ores"], -1)
		if hi != t or oi != t:
			event_ok = false
		if DataCore.HERBS[hi].size() != 3 or DataCore.ORES[oi].size() != 3:
			event_ok = false
	_ok(event_ok, "事件可抽到 0..9 各档灵草/灵材，且无越界")

	print("───────────────────────────────────────────")
	print(" 通过 %d / 失败 %d" % [_pass, _fail])
	print("═══════════════════════════════════════════")
	quit(1 if _fail > 0 else 0)
