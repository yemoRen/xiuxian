extends SceneTree

var ok := true
var fails: Array = []

func _ok(cond: bool, msg: String, detail: String = "") -> void:
	if not cond:
		ok = false
		fails.append("%s (%s)" % [msg, detail] if detail else msg)

func _initialize() -> void:
	var g := GameCore.new(20260913)
	# 第一局：初始功德 10
	g.new_game({"name": "测", "sectName": "测", "sex": 0, "linggen": 0, "fami": 0, "tags": []})
	g.s["merit"] = 10.0
	
	# 重开时消耗 3 功德（特质）+ 2 功德（灵根转动）
	var new_merit := float(g.s["merit"])
	g.new_game({
		"name": "测2", "sectName": "测2", "sex": 0,
		"linggen": 0, "linggen_elements": ["火"],
		"fami": 0, "tags": [0], "merit_cost": 5,
	})
	
	_ok(int(g.s["merit"]) == 5, "重开扣功德后余额正确", "期望 5 实际 %d" % int(g.s["merit"]))
	_ok(int(g.s["merit"]) == int(new_merit) - 5, "扣减额等于总消耗", "%d - 5 = %d" % [int(new_merit), int(g.s["merit"])])
	
	# 验证传入的 elements 被掌门使用
	var leader = g.s["people"][0]
	_ok((leader["elements"] as Array).size() == 1, "掌门灵根属性按传入生成")
	_ok((leader["elements"] as Array)[0] == "火", "掌门灵根属性为火")
	
	g.clear_save()
	
	if ok:
		print("通过 4 / 失败 0")
		quit(0)
	else:
		print("通过 0 / 失败 %d" % fails.size())
		for f in fails:
			print("  ✗ %s" % f)
		quit(1)
