extends SceneTree

var ok := true
var fails: Array = []

func _ok(cond: bool, msg: String, detail: String = "") -> void:
	if not cond:
		ok = false
		fails.append("%s (%s)" % [msg, detail] if detail else msg)

func _initialize() -> void:
	var g := GameCore.new(20260913)
	g.new_game({"name": "测", "sectName": "测", "sex": 0, "linggen": 0, "fami": 0, "tags": []})
	g.s["protect"] = 10000.0
	g.s["tick"] = 200
	g.s["merit"] = 10.0
	
	# 模拟重开宗门的功德结算
	var gain := g.calc_reincarnate_merit()
	g.s["merit"] = float(g.s["merit"]) + gain
	
	_ok(gain == 51, "重开宗门功德计算公式", "期望 51 实际 %d" % gain)
	_ok(int(g.s["merit"]) == 61, "重开后功德余额", "期望 61 实际 %d" % int(g.s["merit"]))
	
	# 验证重开后 new_game 会保留功德并继续扣消耗
	g.new_game({
		"name": "测2", "sectName": "测2", "sex": 0,
		"linggen": 0, "fami": 0, "tags": [], "merit_cost": 0,
	})
	_ok(int(g.s["merit"]) == 61, "新宗门继承结算后的功德", "期望 61 实际 %d" % int(g.s["merit"]))
	_ok(int(g.s["cycle"]) == 2, "新宗门轮回数递增", "期望 2 实际 %d" % int(g.s["cycle"]))
	
	g.clear_save()
	
	if ok:
		print("通过 4 / 失败 0")
		quit(0)
	else:
		print("通过 0 / 失败 %d" % fails.size())
		for f in fails:
			print("  ✗ %s" % f)
		quit(1)
