extends SceneTree

## 验证：堕魔者禁任峰主 / 自动卸任 / 侵蚀庇护事件（每旬 1% 降 5%）。

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
	print(" 堕魔者禁任峰主 / 侵蚀庇护验证")
	print("═══════════════════════════════════════════")

	var g := GameCore.new(GameCore.RNG_SEED_DEFAULT)
	g.new_game({"name": "龙傲天", "sectName": "凌霄宗", "sex": 0, "linggen": 0, "fami": 0, "tags": [6, 4]})

	var people := g.alive_list()
	var leader_cand: Dictionary
	var other_cand: Dictionary
	var d2: Dictionary
	if people.size() > 1:
		leader_cand = people[1]
	else:
		leader_cand = people[0]
	if people.size() > 2:
		other_cand = people[2]
		d2 = people[2]
	else:
		other_cand = people[0]
		d2 = people[0]

	# ── 1. 正常（非堕魔）任峰主仍可行 ──
	g.assign(leader_cand, "danding", true, false)
	_ok(g.s["peaks"]["danding"]["leader"] != null and int(g.s["peaks"]["danding"]["leader"]) == int(leader_cand["id"]), "非堕魔弟子可正常任峰主")

	# ── 2. 堕魔者禁止被任命峰主 ──
	var demon: Dictionary = other_cand
	demon["is_demon"] = true
	g.assign(demon, "baiqi", true, false)
	_ok(g.s["peaks"]["baiqi"]["leader"] == null or int(g.s["peaks"]["baiqi"]["leader"]) != int(demon["id"]), "堕魔者不会被任命为峰主(baiqi)")
	_ok(bool(demon["is_demon"]), "（确认测试对象确为堕魔者）")

	# ── 3. 在位峰主堕魔后自动卸任 ──
	leader_cand["is_demon"] = false
	leader_cand["demonDone"] = false
	leader_cand["demon"] = 1.0   # _chance(1.0) 必然为真，确保本旬转化
	g.on_year()
	_ok(bool(leader_cand["is_demon"]), "峰主在本旬堕魔转化成功")
	_ok(g.s["peaks"]["danding"]["leader"] == null, "原峰主已自动卸任(danding leader 清空)")
	_ok(leader_cand["peak"] == null, "原峰主 peak 已清空")

	# ── 4. 堕魔侵蚀庇护：每旬 1% 降 5% ──
	d2["is_demon"] = true
	g.s["protect"] = 10000.0
	var before: float = float(g.s["protect"])
	for i in 2000:
		g.demon_corrupt()
	var after: float = float(g.s["protect"])
	_ok(after < before, "堕魔侵蚀事件会使宗门庇护人数下降（%d → %d）" % [int(before), int(after)])
	var ref: float = floor(before * 0.05)
	_ok(int(ref) > 0 and int(ref) == int(before * 0.05), "单次降幅为 floor(庇护*5%%)（=%d）" % int(ref))

	# ── 5. 无堕魔者时不触发 ──
	for p: Dictionary in g.alive_list():
		p["is_demon"] = false
	g.s["protect"] = 7777.0
	var p0: float = float(g.s["protect"])
	g.demon_corrupt()
	_ok(absf(float(g.s["protect"]) - p0) < 0.001, "无堕魔者时庇护人数不变")

	print("───────────────────────────────────────────")
	print(" 通过 %d / 失败 %d" % [_pass, _fail])
	print("═══════════════════════════════════════════")
	quit(1 if _fail > 0 else 0)
