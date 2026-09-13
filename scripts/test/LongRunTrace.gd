extends SceneTree

## 长跑时间序列探针：每 CHECK 旬输出一次状态快照，用于定位两个事件池
## 从哪个时间点开始分叉、以及是哪个中间变量先在跑偏。
## 运行：godot --headless --path <工程> --script res://scripts/test/LongRunTrace.gd -- <seed> <tick>

const DEFAULT_TICK := 4000
const CHECK := 250


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_v: int = int(args[0]) if args.size() > 0 else GameCore.RNG_SEED_DEFAULT
	var tick_n: int = int(args[1]) if args.size() > 1 else DEFAULT_TICK

	var g := GameCore.new(seed_v)
	g.new_game({
		"name": "龙傲天", "sectName": "凌霄宗", "sex": 0,
		"linggen": 0, "fami": 0, "tags": [6, 4],
	})
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
	for i in range(1, tick_n + 1):
		g.tick()
		if i % CHECK == 0:
			_emit(seed_v, i, g)

	# 末行汇总
	g_alive(g)


func _stats(g: GameCore) -> Dictionary:
	var alive := g.alive_list()
	var n := alive.size()
	var sumrealm := 0
	var sumqi := 0.0
	var mood := 0.0
	var brk := 0.0
	var qi_ratio := 0.0
	for p in alive:
		sumrealm += int(p["realm"])
		sumqi += float(p["qi"])
		mood += float(p["mood"])
		brk += float(p["brkBonus"])
		var mx: float = g.qi_max(p)
		qi_ratio += (float(p["qi"]) / mx) if mx > 0.0 else 0.0
	return {"n": n, "sumrealm": sumrealm, "sumqi": sumqi,
			"mood": mood / max(1, n), "brk": brk / max(1, n),
			"qiratio": qi_ratio / max(1, n)}


func _emit(seed_v: int, tick: int, g: GameCore) -> void:
	var st: Dictionary = _stats(g)
	var s := g.s
	var fly := 0
	for p in s["people"]:
		if p["fly"]: fly += 1
	print("TRACE seed=%d tick=%d year=%d alive=%d sumrealm=%d sumqi=%.0f mood=%.1f brk=%.3f qiratio=%.3f stone=%.0f protect=%.0f total=%d fly=%d"
		% [seed_v, tick, int(s["year"]), st["n"], st["sumrealm"], st["sumqi"],
		   st["mood"], st["brk"], st["qiratio"], float(s["stone"]), float(s["protect"]),
		   (s["people"] as Array).size(), fly])


func g_alive(g: GameCore) -> void:
	quit(0)
