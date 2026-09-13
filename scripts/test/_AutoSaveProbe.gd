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
	var before_year := int(g.s["year"])
	
	# 推进一年（12 月 × 3 旬 = 36 旬）
	for i in 36:
		g.tick()
	
	_ok(int(g.s["year"]) == before_year + 1, "跨年后年份增加", "%d -> %d" % [before_year, int(g.s["year"])])
	
	# 存档文件应存在且 year 为 2
	var has_save := g.has_save()
	_ok(has_save, "跨年后自动存档文件存在")
	if has_save:
		g.load_save()
		_ok(int(g.s["year"]) == 2, "存档中 year 为 2", str(g.s["year"]))
	
	# 清除存档
	g.clear_save()
	
	if ok:
		print("通过 2 / 失败 0")
		quit(0)
	else:
		print("通过 0 / 失败 %d" % fails.size())
		for f in fails:
			print("  ✗ %s" % f)
		push_error("autosave probe failed")
		quit(1)
