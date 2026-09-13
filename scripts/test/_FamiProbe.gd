extends SceneTree

var _fail := 0
var _pass := 0

func _init():
	var GameCore = load("res://scripts/core/GameCore.gd")
	var DataCore = load("res://scripts/core/DataCore.gd")
	var g: Object = GameCore.new()
	g.new_game({})  # 初始化 s，eff/make_person 会读取全局状态

	print("== 命名库 ==")
	_ok(DataCore.MING_M.size() == 100, "男名 %d 个" % DataCore.MING_M.size())
	_ok(DataCore.MING_F.size() == 100, "女名 %d 个" % DataCore.MING_F.size())
	var dm: Dictionary = {}
	for n in DataCore.MING_M:
		dm[n] = 1
	_ok(dm.size() == 100, "男名无重复 %d" % dm.size())
	var df: Dictionary = {}
	for n in DataCore.MING_F:
		df[n] = 1
	_ok(df.size() == 100, "女名无重复 %d" % df.size())

	print("== FAMI 数值 ==")
	var fami: Dictionary = {}
	for f in DataCore.FAMI:
		fami[f["n"]] = f
	_ok(float(fami["异界"]["qi"]) == 1.3, "异界 qi=1.3")
	_ok(float(fami["异界"]["atk"]) == 1.0, "异界 atk=1.0")
	_ok(float(fami["乡野农民"]["qi"]) == 1.0, "乡野农民 qi=1.0")
	_ok(float(fami["乡野农民"]["atk"]) == 1.0, "乡野农民 atk=1.0")
	_ok(float(fami["乡野农民"]["plant"]) == 0.2, "乡野农民 plant=0.2")
	_ok(float(fami["乡野农民"]["mine"]) == 0.2, "乡野农民 mine=0.2")
	_ok(float(fami["乡野农民"]["explore"]) == 0.2, "乡野农民 explore=0.2")
	_ok(float(fami["修真世家"]["qi"]) == 1.1, "修真世家 qi=1.1")
	_ok(float(fami["修真世家"]["atk"]) == 1.1, "修真世家 atk=1.1")
	_ok(float(fami["魔域"]["qi"]) == 1.3, "魔域 qi=1.3")
	_ok(float(fami["星机阁"]["forge"]) == 0.30, "星机阁 forge=0.3")
	_ok(float(fami["药王谷"]["refine"]) == 0.30, "药王谷 refine=0.3")
	_ok(float(fami["大自在殿"]["brk"]) == 0.10, "大自在殿 brk=0.1")
	_ok("身存魔种" in fami["魔域"].get("tags", []), "魔域自带 身存魔种")
	_ok("貌美" in fami["合欢宗"].get("tags", []), "合欢宗自带 貌美")

	print("== eff() 出身加成 ==")
	# 找出身索引
	var fi_yenong := 0
	var fi_xingji := 0
	var fi_yaowang := 0
	var fi_dazi := 0
	var fi_moyu := 0
	var fi_hehuan := 0
	var fi_yijie := 0
	for i in DataCore.FAMI.size():
		var nm: String = DataCore.FAMI[i]["n"]
		if nm == "乡野农民": fi_yenong = i
		elif nm == "星机阁": fi_xingji = i
		elif nm == "药王谷": fi_yaowang = i
		elif nm == "大自在殿": fi_dazi = i
		elif nm == "魔域": fi_moyu = i
		elif nm == "合欢宗": fi_hehuan = i
		elif nm == "异界": fi_yijie = i

	# 构造最小人物字典
	var ye: Dictionary = _mkp(fi_yenong)
	var pe: float = g.eff(ye, "plant")
	_ok(pe > 1.1, "乡野农民 plant 效率 >1.1", "%.3f" % pe)
	var xj: Dictionary = _mkp(fi_xingji)
	var fe: float = g.eff(xj, "forge")
	_ok(fe > 1.2, "星机阁 forge 效率 >1.2", "%.3f" % fe)
	var yg: Dictionary = _mkp(fi_yaowang)
	var re: float = g.eff(yg, "refine")
	_ok(re > 1.2, "药王谷 refine 效率 >1.2", "%.3f" % re)
	var dz: Dictionary = _mkp(fi_dazi)
	var br: float = g.brk_rate(dz)
	_ok(br > 0.1, "大自在殿 brk_rate 含出身 +0.1", "%.3f" % br)

	print("== make_person 出身特质 ==")
	var mp_mo: Dictionary = g.make_person({"famiIdx": fi_moyu, "name": "测魔"})
	_ok(_has_tag(mp_mo, DataCore, "身存魔种"), "魔域角色带 身存魔种")
	var mp_hh: Dictionary = g.make_person({"famiIdx": fi_hehuan, "name": "测欢"})
	_ok(_has_tag(mp_hh, DataCore, "貌美"), "合欢宗角色带 貌美")
	var mp_xy: Dictionary = g.make_person({"famiIdx": fi_yijie, "name": "测异"})
	_ok(not _has_tag(mp_xy, DataCore, "身存魔种") and not _has_tag(mp_xy, DataCore, "貌美"), "异界角色无出身特质")

	_report()

func _mkp(fidx: int) -> Dictionary:
	var p: Dictionary = {}
	p["linggenIdx"] = 3
	p["elements"] = []
	p["famiIdx"] = fidx
	p["tags"] = []
	p["realm"] = 0
	p["brkBonus"] = 0.0
	p["qiRateB"] = 0.0
	p["atkBonus"] = 1.0
	p["mood"] = 60.0
	p["job"] = "leader"
	p["equip"] = [null, null, null, null, null]
	p["books"] = []
	p["spouse"] = null
	return p

func _has_tag(p: Dictionary, DataCore, nm: String) -> bool:
	for t in p["tags"]:
		if DataCore.TAGS[int(t)]["n"] == nm:
			return true
	return false

func _ok(cond: bool, msg: String, extra: String = "") -> void:
	if cond:
		_pass += 1
		print("  ✓ %s%s" % [msg, ("  " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  ✗ %s%s" % [msg, ("  " + extra) if extra != "" else ""])

func _report() -> void:
	print("\n通过 %d / 失败 %d" % [_pass, _fail])
	if _fail > 0:
		push_error("fami probe failed")
		quit(1)
	else:
		quit(0)
