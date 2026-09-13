extends SceneTree

## 诊断探针：统计「每旬普通招人」与「宗门大比」的真实发生速率。
## 计数用 ΔnextId（make_person 每造一人 +1；每旬唯一造人路径＝add_disciple）。
## 运行：godot --headless --path <工程> --script res://scripts/test/_RecruitProbe.gd -- <seed> <ticks> [houseLv]
##   houseLv > 0 时抬高房舍等级，用来消除「人口 < 容量」这道闸门、测裸速率。

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_v: int = int(args[0]) if args.size() > 0 else 1
	var ticks: int = int(args[1]) if args.size() > 1 else 3000
	var hl: int = int(args[2]) if args.size() > 2 else 0

	var g := GameCore.new(seed_v)
	g.new_game({"name": "龙傲天", "sectName": "凌霄宗", "sex": 0,
		"linggen": 0, "fami": 0, "tags": [6, 4]})
	var a := g.alive_list()
	g.assign(a[0], "fumo", true, false)
	if a.size() > 1: g.assign(a[1], "shenyao", true, false)
	if a.size() > 2: g.assign(a[2], "lingkuang", true, false)
	if a.size() > 3: g.assign(a[3], "danding", true, false)
	g.s["peaks"]["fumo"]["outer"] = 5
	g.s["peaks"]["shenyao"]["outer"] = 5
	g.s["peaks"]["lingkuang"]["outer"] = 2
	if hl > 0:
		g.s["houseLv"] = hl

	var id0 := int(g.s["nextId"])
	var room_ticks := 0
	var lines: Array = []

	for w in int(ceil(ticks / 100.0)):
		var idw := int(g.s["nextId"])
		var roomw := 0
		var n := mini(100, ticks - w * 100)
		for j in n:
			g.tick()
			if g.population() < g.capacity():
				roomw += 1
				room_ticks += 1
		lines.append("  window %4d-%4d 招人=%2d  有容量=%d/%d"
			% [w * 100 + 1, w * 100 + n, int(g.s["nextId"]) - idw, roomw, n])

	var total := int(g.s["nextId"]) - id0
	print("RECRUIT seed=%d ticks=%d 招人=%d (%.2f%%/旬) 有容量旬=%d(%.0f%%) protect=%.0f houseLv=%d pop=%d cap=%d"
		% [seed_v, ticks, total, 100.0 * total / ticks, room_ticks,
			100.0 * room_ticks / ticks, float(g.s["protect"]),
			int(g.s["houseLv"]), g.population(), g.capacity()])
	if ticks <= 600:
		for l in lines:
			print(l)
	quit(0)
