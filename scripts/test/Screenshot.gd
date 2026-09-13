extends Control

## 截图工具：驱动真实界面并把每一屏存成 PNG，用于人工核对视觉。
## 运行：godot --path <工程> res://scenes/Screenshot.tscn   （不要加 --headless）

var ui: Control
var _dir := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = Vector2(1280, 720)
	_dir = ProjectSettings.globalize_path("res://") + "_shots"
	DirAccess.make_dir_recursive_absolute(_dir)

	XiuxianGlobals.game.clear_save()
	XiuxianGlobals.set_seed(GameCore.RNG_SEED_DEFAULT)
	await _f(2)

	ui = load("res://scenes/Main.tscn").instantiate()
	add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	ui.size = Vector2(1280, 720)
	await _f(4)

	# 1. 捏人
	await _shot("01_捏人")

	# 开一局
	ui.close_modal()
	XiuxianGlobals.start_new({
		"name": "龙傲天", "sectName": "凌霄宗", "sex": 0,
		"linggen": 0, "fami": 0, "tags": [6, 4],
	})
	XiuxianGlobals.set_running(false)
	var g := XiuxianGlobals.game

	# 分派弟子到六峰
	var a := g.alive_list()
	g.assign(a[0], "fumo", true, false)
	if a.size() > 1: g.assign(a[1], "shenyao", true, false)
	if a.size() > 2: g.assign(a[2], "lingkuang", true, false)
	if a.size() > 3: g.assign(a[3], "danding", true, false)
	g.s["peaks"]["fumo"]["outer"] = 3
	g.s["peaks"]["shenyao"]["outer"] = 2
	g.s["peaks"]["lingkuang"]["outer"] = 2
	g.s["peaks"]["danding"]["outer"] = 2
	g.s["peaks"]["baiqi"]["outer"] = 2
	g.s["peaks"]["zhuanzhu"]["writer"] = (a[1] if a.size() > 1 else a[0])["id"]
	g.s["peaks"]["xunyou"]["secret"] = 2
	g.s["peaks"]["xunyou"]["progress"] = 62.0
	g.s["peaks"]["danding"]["progress"] = 44.0
	g.s["peaks"]["baiqi"]["progress"] = 78.0

	# 跑一段时间，攒出内容
	for i in 900:
		g.tick()
	XiuxianGlobals.set_running(false)
	g.s["herbs"][0] = 24
	g.s["herbs"][3] = 9
	g.s["ores"][1] = 17
	g.s["ores"][4] = 6
	g.s["pills"][1] = 5
	g.s["pills"][3] = 2
	g.s["pills"][10] = 1
	while g.s["equips"].size() < 5:
		g.s["equips"].append(g.make_equip(g._ri(1, 6)))
	g.s["merit"] = 640.0
	g.s["protect"] = 18400.0
	g.changed.emit()

	# 2. 行动
	ui.tab = "action"
	await _force()
	await _shot("02_行动_宗门纪事")

	# 3. 设施
	ui._goto_tab("facility")
	await _force()
	await _shot("03_设施_六峰")

	# 4. 门徒
	ui._goto_tab("people")
	await _force()
	await _shot("04_门徒_名册")

	# 5. 弟子详情
	ui.show_person(g.alive_list()[0]["id"])
	await _f(3)
	await _shot("05_弟子详情")
	ui.close_modal()
	await _f(2)

	# 6. 道具
	ui._goto_tab("items")
	await _force()
	await _shot("06_道具_灵草丹药法宝")

	# 7. 设置
	ui._goto_tab("settings")
	await _force()
	await _shot("07_设置_功德天梯")

	# 8. 选人弹窗
	ui.pick_person(func(p): pass, "任命", g.alive_list())
	await _f(3)
	await _shot("08_选人弹窗")

	print("SHOTS_DONE -> ", _dir)
	await _f(2)
	get_tree().quit(0)


func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _force() -> void:
	ui._dirty = true
	ui._force = true
	await _f(3)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := _dir + "/" + name + ".png"
	var err := img.save_png(path)
	print("  shot %s -> %s" % [name, "ok" if err == OK else str(err)])
