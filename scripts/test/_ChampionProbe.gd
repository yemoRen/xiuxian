extends SceneTree

## 大比逻辑验证（headless）：
##   1) auto_champion=false 时，championLeft 到点应挂起 pending_champion（含 3 件候选法宝），不再推进
##   2) resolve_champion(idx) 落实：胜者入内门、心境+30、灵石+2000、获赐所选法宝、championLeft 重置、pending 清空
##   3) resolve_champion(-1) 走随机奖品分支不报错
##   4) 无外门候选时本届空手（eventt150）

var _p := 0
var _f := 0

func _ok(c: bool, msg: String) -> void:
	if c:
		_p += 1
		print("  ✓ ", msg)
	else:
		_f += 1
		print("  ✗ ", msg)

func _equip_slots(p: Dictionary) -> int:
	var n := 0
	for e in p.get("equip", []):
		if e != null:
			n += 1
	return n

func _run() -> void:
	var g := preload("res://scripts/core/GameCore.gd").new()
	g.auto_champion = false
	g.new_game({"name": "测试门派", "sex": 0, "linggen": 0, "fami": 0, "tags": []})

	# 先攒几名外门弟子
	for i in 6:
		g.add_disciple(true)

	# 强制大比临近
	g.s["championLeft"] = 1
	var guard := 0
	while g.s.get("pending_champion", {}).is_empty() and guard < 50:
		g.tick()
		guard += 1

	_ok(not g.s.get("pending_champion", {}).is_empty(), "大比到点挂起 pending_champion")
	var pc: Dictionary = g.s.get("pending_champion", {})
	_ok(pc.has("id") and pc.has("name"), "pending 含胜者 id/name")
	_ok(pc.get("prizes", []).size() == 3, "pending 含 3 件候选法宝（实际 %d）" % pc.get("prizes", []).size())

	# 挂起后 tick 应冻结（不再推进 tick 计数）
	var tick0 := int(g.s["tick"])
	g.tick()
	g.tick()
	_ok(int(g.s["tick"]) == tick0, "pending 期间模拟冻结（tick 不前进）")

	# 结算选第 1 件
	var win_id: int = int(pc["id"])
	var win_before: Dictionary = g.by_id(win_id)
	var stone0 := float(g.s["stone"])
	var eq0 := (g.s["equips"] as Array).size()
	var mood0 := float(win_before["mood"])
	var slot0 := _equip_slots(win_before)
	g.resolve_champion(1)
	var win_after: Dictionary = g.by_id(win_id)
	_ok(win_after["inner"] == true, "胜者拜入内门")
	_ok(float(win_after["mood"]) >= mood0 + 30.0 - 0.001, "心境 +30（%.0f→%.0f）" % [mood0, win_after["mood"]])
	_ok(float(g.s["stone"]) >= stone0 + 2000.0 - 0.001, "灵石 +2000")
	_ok(_equip_slots(win_after) == slot0 + 1, "胜者装备所选法宝（栏位 +1）")
	_ok((g.s["equips"] as Array).size() == eq0, "奖品直接赐予胜者，公库持平")
	_ok(g.s.get("pending_champion", {}).is_empty(), "结算后 pending 清空")
	_ok(int(g.s["championLeft"]) > 1, "championLeft 重置为下一届周期")

	# 随机奖品分支
	g.s["championLeft"] = 1
	guard = 0
	while g.s.get("pending_champion", {}).is_empty() and guard < 50:
		g.tick()
		guard += 1
	var pc2: Dictionary = g.s.get("pending_champion", {})
	var win2_id: int = int(pc2["id"])
	var slot1 := _equip_slots(g.by_id(win2_id))
	g.resolve_champion(-1)
	_ok(_equip_slots(g.by_id(win2_id)) == slot1 + 1, "resolve(-1) 随机奖品正常赐予胜者（栏位 +1）")

	# 无外门候选：本届空手
	var g2 := preload("res://scripts/core/GameCore.gd").new()
	g2.auto_champion = false
	g2.new_game({"name": "空门派", "sex": 0, "linggen": 0, "fami": 0, "tags": []})
	# 把所有人变内门，确保无外门候选
	for p in g2.s["people"]:
		p["inner"] = true
	var logn0 := (g2.s["log"] as Array).size()
	g2.s["championLeft"] = 1
	g2.tick()
	var empty := false
	for it in g2.s["log"]:
		if "未能选拔出杰出弟子" in str(it.get("t", "")):
			empty = true
	_ok(empty, "无外门候选时本届大比空手（eventt150）")
	_ok(g2.s.get("pending_champion", {}).is_empty(), "空手时仍无 pending 挂起")

	print("──────────────────────────────")
	print(" 大比逻辑：通过 %d / 失败 %d" % [_p, _f])
	quit(0 if _f == 0 else 1)


func _initialize() -> void:
	_run()
