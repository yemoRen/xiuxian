extends SceneTree

var _pass := 0
var _fail := 0
var _fails: Array = []

func _ok(cond: bool, msg: String, detail: String = "") -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		_fails.append("%s%s" % [msg, " (%s)" % detail if detail != "" else ""])

func _abort(msg: String) -> void:
	push_error(msg)

func _init():
	var GameCore = load("res://scripts/core/GameCore.gd")
	var DataCore = load("res://scripts/core/DataCore.gd")
	var g = GameCore.new()
	g.rng.seed = 12345

	# 1. 负 cost 不转入游戏 merit
	g.s["merit"] = 5.0
	var cfg := {
		"name": "测", "sectName": "测", "sex": 0,
		"linggen": 0, "linggen_elements": ["火"], "linggen_rerolls": 0, "linggen_merit_spent": 0,
		"fami": 0, "tags": [9, 11],  # 貌寝 -1 + 残疾 -2 = -3
		"tag_merit_cost": -3,
		"merit_cost": 0,  # 应由 UI 层传入 max(0, -3) + 0 = 0
	}
	g.new_game(cfg)
	_ok(int(g.s["merit"]) == 5, "负 cost 不增加游戏内功德", "实际 %d" % int(g.s["merit"]))

	# 2. 正 cost 正常扣除
	g.s["merit"] = 5.0
	cfg["tags"] = [0]  # 貌美 3
	cfg["tag_merit_cost"] = 3
	cfg["merit_cost"] = 3
	g.new_game(cfg)
	_ok(int(g.s["merit"]) == 2, "正 cost 正常扣除", "实际 %d" % int(g.s["merit"]))

	# 3. 貌美增加感情事件权重；貌寝降低感情事件权重
	g.s["merit"] = 0.0
	g.new_game({"name": "基", "sectName": "基", "sex": 0,
		"linggen": 0, "linggen_elements": ["火"], "linggen_rerolls": 0, "linggen_merit_spent": 0,
		"fami": 0, "tags": [], "tag_merit_cost": 0, "merit_cost": 0})
	var base_love := 0.0
	var beauty_love := 0.0
	var ugly_love := 0.0
	for e in DataCore.EVENTS:
		if e["kind"] == "love":
			base_love += float(e["w"])
	# 貌美：love 权重 ×3
	g.s["people"][0]["tags"] = [0]
	beauty_love = _sample_love_weight(g, DataCore)
	# 貌寝：love 权重 ×0.3
	g.s["people"][0]["tags"] = [9]
	ugly_love = _sample_love_weight(g, DataCore)
	_ok(beauty_love > base_love * 2.5, "貌美提升感情事件权重", "%.1f vs %.1f" % [beauty_love, base_love])
	_ok(ugly_love < base_love * 0.5, "貌寝降低感情事件权重", "%.1f vs %.1f" % [ugly_love, base_love])

	# 4. 身存魔种修炼加成改为 10%
	var demon_seed_idx := -1
	for i in DataCore.TAGS.size():
		if DataCore.TAGS[i]["n"] == "身存魔种":
			demon_seed_idx = i
			break
	_ok(demon_seed_idx >= 0, "找得到身存魔种特质")
	if demon_seed_idx >= 0:
		var t: Dictionary = DataCore.TAGS[demon_seed_idx]
		_ok(int(t.get("cost", 0)) == -2, "身存魔种 cost 为 -2", str(t.get("cost", 0)))
		_ok(abs(float(t.get("qi", 0.0)) - 0.10) < 0.001, "身存魔种修炼 +10%", str(t.get("qi", 0.0)))

	print("通过 %d / 失败 %d" % [_pass, _fail])
	for f in _fails:
		print("  ✗ %s" % f)
	if _fail > 0:
		_abort("trait balance probe failed")
	quit()

func _sample_love_weight(g, DataCore) -> float:
	var pool: Array = []
	for e in DataCore.EVENTS:
		var d: Dictionary = (e as Dictionary).duplicate()
		if d["kind"] == "love":
			var love_k := 1.0
			for t in g.s["people"][0]["tags"]:
				var tag: Dictionary = DataCore.TAGS[int(t)]
				if tag.has("love"):
					love_k *= float(tag["love"])
			d["w"] = float(d["w"]) * love_k
		pool.append(d)
	var total := 0.0
	for d in pool:
		if d["kind"] == "love":
			total += float(d["w"])
	return total
