extends SceneTree

## 诊断探针：验证秘境探索的新判定逻辑（境界门槛 / 成功率 / 战损 / 队伍构成）
## 运行：godot --headless --path <工程> --script res://scripts/test/_SecretProbe.gd

var _passed := 0
var _failed := 0

func _ok(cond: bool, msg: String, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("✓ %s %s" % [msg, detail])
	else:
		_failed += 1
		print("✗ %s %s" % [msg, detail])

func _initialize() -> void:
	var g := _setup(42)

	# 场景 A：队长境界不足（练气带队海蜃秘境 need=3）
	var leader: Dictionary = g.by_id(g.s["peaks"]["xunyou"]["leader"])
	leader["realm"] = 0
	leader["sub"] = 0
	leader["atkBonus"] = 1000.0
	g.s["peaks"]["xunyou"]["secret"] = 3  # 海蜃秘境 need=3 atk=3000
	g.s["peaks"]["xunyou"]["progress"] = 0.0

	for i in 60:
		g.tick()

	_ok(float(g.s["peaks"]["xunyou"]["progress"]) == 0.0,
		"队长境界不足时秘境进度不推进",
		"progress=%.1f%%" % float(g.s["peaks"]["xunyou"]["progress"]))

	# 场景 B：队长境界足够但武力不足（元婴 + 裸装）
	var g2 := _setup(42)
	var leader2: Dictionary = g2.by_id(g2.s["peaks"]["xunyou"]["leader"])
	leader2["realm"] = 3
	leader2["sub"] = 0
	leader2["atkBonus"] = 0.0
	g2.s["peaks"]["xunyou"]["secret"] = 3
	g2.s["peaks"]["xunyou"]["progress"] = 0.0

	for i in 60:
		g2.tick()

	var progress2 := float(g2.s["peaks"]["xunyou"]["progress"])
	_ok(progress2 > 0.0 and progress2 < 100.0,
		"境界够但武力不足时仍有缓慢推进（概率成功）",
		"progress=%.1f%%" % progress2)

	var wins2: int = g2.s["log"].filter(func(l): return "攻略了" in l.get("t", "")).size()
	var inj2: int = g2.s["log"].filter(func(l): return "负伤" in l.get("t", "")).size()
	print("  场景B：推进=%.1f%% 成功=%d 受伤=%d" % [progress2, wins2, inj2])

	# 场景 C：队长境界够、武力碾压（应能快速攻略）
	var g3 := _setup(42)
	var a3 := g3.alive_list()
	var leader3: Dictionary = g3.by_id(g3.s["peaks"]["xunyou"]["leader"])
	leader3["realm"] = 5
	leader3["sub"] = 0
	leader3["atkBonus"] = 1000.0
	if a3.size() > 1:
		g3.assign(a3[1], "xunyou", false, true)   # 副手提升探索效率
	g3.s["peaks"]["xunyou"]["secret"] = 3
	g3.s["peaks"]["xunyou"]["progress"] = 0.0
	g3.s["peaks"]["xunyou"]["outer"] = 5
	g3.fill_outer()

	for i in 120:
		g3.tick()

	var wins3: int = g3.s["log"].filter(func(l): return "攻略了" in l.get("t", "")).size()
	_ok(wins3 >= 1,
		"高境界高武力队伍能在120旬内攻略秘境",
		"成功=%d" % wins3)

	# 场景 D：在岗外门弟子计入队伍武力
	var g4 := _setup(42)
	var leader4: Dictionary = g4.by_id(g4.s["peaks"]["xunyou"]["leader"])
	leader4["realm"] = 3
	leader4["atkBonus"] = 0.0
	g4.s["peaks"]["xunyou"]["secret"] = 3
	g4.s["peaks"]["xunyou"]["outer"] = 5
	g4.fill_outer()
	var p_with_outer := g4.team_power("xunyou")

	var g5 := _setup(42)
	var leader5: Dictionary = g5.by_id(g5.s["peaks"]["xunyou"]["leader"])
	leader5["realm"] = 3
	leader5["atkBonus"] = 0.0
	g5.s["peaks"]["xunyou"]["secret"] = 3
	g5.s["peaks"]["xunyou"]["outer"] = 0
	g5.fill_outer()
	var p_no_outer := g5.team_power("xunyou")

	_ok(p_with_outer > p_no_outer,
		"在岗外门弟子计入秘境队伍武力",
		"有外门=%.0f 无外门=%.0f" % [p_with_outer, p_no_outer])

	# 场景 E：成功率曲线
	var r1: float = g.secret_risk(3000.0, 3000.0)
	var r2: float = g.secret_risk(3000.0, 6000.0)
	var r3: float = g.secret_risk(3000.0, 300.0)
	_ok(r1 > r2, "武力翻倍则风险下降", "parity=%.2f 2x=%.2f" % [r1, r2])
	_ok(r3 > r1, "武力极低则风险更高", "low=%.2f parity=%.2f" % [r3, r1])

	print("\nSECRET PROBE: %d passed, %d failed" % [_passed, _failed])
	quit(_failed)


func _setup(seed_v: int) -> GameCore:
	var g := GameCore.new(seed_v)
	g.new_game({"name": "龙傲天", "sectName": "凌霄宗", "sex": 0,
		"linggen": 0, "fami": 0, "tags": [6, 4]})
	g.auto_champion = true
	var a := g.alive_list()
	g.assign(a[0], "xunyou", true, false)
	return g
