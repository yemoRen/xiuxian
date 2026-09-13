extends SceneTree

var ok := 0
var fail := 0

func _ok(c: bool, m: String) -> void:
	if c:
		print("  ✓ ", m); ok += 1
	else:
		print("  ✗ ", m); fail += 1

func _initialize() -> void:
	var G := GameCore.new(GameCore.RNG_SEED_DEFAULT)
	G.new_game({"name": "测试", "sectName": "测试宗", "sex": 0, "linggen": 0, "fami": 0, "tags": []})

	# 给青芜峰任命一个峰主（内门弟子）
	var lead = G.make_person({"inner": true, "peak": null, "realm": 2, "rebirth": true})
	lead["job"] = null
	G.s["people"].append(lead)
	G.assign(lead, "shenyao", true, false)
	_ok(G.s["peaks"]["shenyao"]["leader"] == lead["id"], "青芜峰已任命峰主")
	_ok(float(G.s["peaks"]["shenyao"]["progress"]) == 0.0, "初始开辟进度为 0")

	# 跑 200 旬，进度应累积并触发自动升级
	var lv0 := int(G.s["peaks"]["shenyao"]["herbLv"])
	for i in 200:
		G.s["tick"] = i
		G.production()
	var lv1 := int(G.s["peaks"]["shenyao"]["herbLv"])
	_ok(lv1 > lv0, "开辟进度满额触发自动提升药田品阶 (lv %d→%d)" % [lv0, lv1])
	_ok(0.0 <= float(G.s["peaks"]["shenyao"]["progress"]) and float(G.s["peaks"]["shenyao"]["progress"]) < 100.0,
		"进度在 [0,100) 区间 (%.1f)" % float(G.s["peaks"]["shenyao"]["progress"]))
	_ok(int(G.s["peaks"]["shenyao"]["herbAcc"]) > 0, "持续产出灵草 (累计 %d)" % int(G.s["peaks"]["shenyao"]["herbAcc"]))

	# 玄矿峰同样
	var lead2 = G.make_person({"inner": true, "peak": null, "realm": 2, "rebirth": true})
	lead2["job"] = null
	G.s["people"].append(lead2)
	G.assign(lead2, "lingkuang", true, false)
	var olv0 := int(G.s["peaks"]["lingkuang"]["oreLv"])
	for i in 200:
		G.s["tick"] = 1000 + i
		G.production()
	var olv1 := int(G.s["peaks"]["lingkuang"]["oreLv"])
	_ok(olv1 > olv0, "玄矿峰开辟进度触发自动提升矿道品阶 (lv %d→%d)" % [olv0, olv1])

	print("\n_FieldProbe: %d ok / %d fail" % [ok, fail])
	quit(0 if fail == 0 else 1)
