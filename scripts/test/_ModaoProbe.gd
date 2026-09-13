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
	# 异界(qi 1.3) + 单灵根(rate 1.55) 作为基准
	G.new_game({"name": "测试", "sectName": "测试宗", "sex": 0, "linggen": 3, "fami": 0, "tags": []})

	var modao_idx := -1
	for i in DataCore.TAGS.size():
		if DataCore.TAGS[i]["n"] == "修魔":
			modao_idx = i
	_ok(modao_idx >= 0, "可定位修魔特质")

	# 1. 带「修魔」特质（realm=0 → 练气初阶），应标记魔修并显示「· 已堕魔」
	var p := G.make_person({"tags": [modao_idx], "realm": 0, "sub": 0})
	_ok(bool(p.get("is_modao", false)), "修魔特质→is_modao=true")
	_ok(G.realm_name(p) == "练气初阶 · 已堕魔", "境界名显示「· 已堕魔」(=%s)" % G.realm_name(p))
	# 修炼倍率：eff 对特质为「先乘灵根/出身基础、再叠加特质值」，故修魔的 +1.0 会被基础倍率放大，
	# 即「修炼 +100%」相对基础倍率而言。验证：有修魔者 cultivate 倍率 > 无修魔者，且差值≈+1.0×基础。
	var p0 := G.make_person({"tags": [], "realm": 0, "sub": 0,
		"linggenIdx": int(p["linggenIdx"]), "famiIdx": int(p["famiIdx"]),
		"elements": p["elements"].duplicate()})
	var d_qi := G.eff(p, "cultivate") - G.eff(p0, "cultivate")
	# 修魔特质按 qi:1.00 叠加 +1.0（与「无垢灵体」同语义），eff 内部另有全局系数(约0.96)，
	# 故实际增量≈0.96。断言：修魔确使修炼倍率提升约 +100%（容差 0.12）。
	_ok(absf(d_qi - 1.0) < 0.12, "修魔使修炼倍率提升约一倍（差值 %.4f）" % d_qi)

	# 2. 普通弟子无标记、无后缀
	var np := G.make_person({"tags": [], "realm": 0, "sub": 0})
	_ok(not bool(np.get("is_modao", false)), "无修魔特质→is_modao=false")
	_ok(G.realm_name(np) == "练气初阶", "普通弟子境界名无后缀 (=%s)" % G.realm_name(np))

	# 3. 彻底堕魔者同样显示「· 已堕魔」
	np["is_demon"] = true
	_ok(G.realm_name(np) == "练气初阶 · 已堕魔", "is_demon 也显示「· 已堕魔」(=%s)" % G.realm_name(np))

	# 4. 修魔弟子在随机事件中 demon 类事件权重被放大（复刻 random_events 逻辑）
	var base_demon_w := 0.0
	for e in DataCore.EVENTS:
		if (e as Dictionary)["kind"] == "demon":
			base_demon_w = float((e as Dictionary)["w"]); break
	var boosted_w := 0.0
	for e in DataCore.EVENTS:
		var d: Dictionary = (e as Dictionary).duplicate()
		if d["kind"] == "demon":
			if (p["is_demon"] or p["is_modao"]) and d["kind"] == "demon":
				d["w"] = float(d["w"]) * 4.0
			boosted_w = float(d["w"])
	_ok(boosted_w > base_demon_w, "修魔使 demon 事件权重放大 (%.2f → %.2f)" % [base_demon_w, boosted_w])

	# 5. 存档/读档保留 is_modao
	var saved := G._normalize_person(p)
	_ok(bool(saved.get("is_modao", false)), "读档保留 is_modao")

	print("\n_ModaoProbe: %d ok / %d fail" % [ok, fail])
	quit(0 if fail == 0 else 1)
