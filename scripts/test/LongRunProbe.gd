extends SceneTree

## 长跑采样探针（A/B 归因用）：单随机种子跑 N 旬，输出一行机器可解析的结果。
## 运行：
##   godot --headless --path <工程> --script res://scripts/test/LongRunProbe.gd -- <seed> <tick>
##
## 输出格式（每行一条）：
##   RESULT seed=<s> tick=<n> flown=<飞升数> tianti=<天梯> best=<最高境界> zero=<灵石枯竭旬数>
##          stone=<末期灵石> protect=<庇护> pop=<存续人数> total=<累计门徒> sumrealm=<境界总和> mood=<平均心情>

const DEFAULT_TICK := 4000


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_v: int = int(args[0]) if args.size() > 0 else GameCore.RNG_SEED_DEFAULT
	var tick_n: int = int(args[1]) if args.size() > 1 else DEFAULT_TICK

	var g := GameCore.new(seed_v)
	g.new_game({
		"name": "龙傲天", "sectName": "凌霄宗", "sex": 0,
		"linggen": 0, "fami": 0, "tags": [6, 4],
	})

	# 与 LogicTest 的 4000 旬长跑完全相同的开局布置，保证可比
	var a := g.alive_list()
	g.assign(a[0], "fumo", true, false)
	if a.size() > 1: g.assign(a[1], "shenyao", true, false)
	if a.size() > 2: g.assign(a[2], "lingkuang", true, false)
	if a.size() > 3: g.assign(a[3], "danding", true, false)
	g.s["peaks"]["fumo"]["outer"] = 3
	g.s["peaks"]["danding"]["outer"] = 2
	g.s["peaks"]["baiqi"]["outer"] = 2
	g.s["peaks"]["zhuanzhu"]["writer"] = (a[1] if a.size() > 1 else a[0])["id"]

	var s := g.s
	var zero_ticks := 0
	var best_realm := 0
	for i in range(1, tick_n + 1):
		g.tick()
		if float(s["stone"]) <= 0.0:
			zero_ticks += 1
		for p in g.alive_list():
			best_realm = maxi(best_realm, int(p["realm"]))

	var flown := 0
	for p in s["people"]:
		if p["fly"]: flown += 1

	var alive := g.alive_list()
	var sum_realm := 0
	var mood_sum := 0.0
	for p in alive:
		sum_realm += int(p["realm"])
		mood_sum += float(p["mood"])
	var avg_mood := (mood_sum / float(alive.size())) if alive.size() > 0 else 0.0

	print("RESULT seed=%d tick=%d flown=%d tianti=%d best=%d zero=%d stone=%.0f protect=%.0f pop=%d total=%d sumrealm=%d mood=%.1f poolsize=%d"
		% [seed_v, tick_n, flown, int(s["tianti"]), best_realm, zero_ticks,
			float(s["stone"]), float(s["protect"]), g.population(),
			(s["people"] as Array).size(), sum_realm, avg_mood,
			DataCore.EVENTS.size()])
	quit(0)
