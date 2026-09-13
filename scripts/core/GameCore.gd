extends RefCounted
class_name GameCore

## 核心模拟逻辑 —— 由 web 版 game.js 移植。
##
## 与原版的差异（均为修正性改动，已在 README 记录）：
##   1. 原版 `p.demon` 同时当数值累加器和布尔标记用（JS 里能跑，GDScript 会类型报错），
##      拆成 `demon`（Float 累加）与 `is_demon`（Bool）。
##   2. 原版 `eff()` 里神兽苑（eff=atk）被两个分支各加一次，实际双倍生效；已去重。
##   3. 原版事件写入的 `qiRateB` / `atkBonus` 从未被 `eff()` 读取，"修炼速度+2%" 这类
##      事件其实是空转；这里接进 `eff()`，让文本承诺真正生效。
##   4. RNG 改为可播种的 RandomNumberGenerator，便于回归测试复现。

signal changed

## 运行态（Dictionary）。键名沿用原 JS 版命名以免移植歧义。
var s: Dictionary = {}
var rng := RandomNumberGenerator.new()

## 大比结算模式：true=自动结算（headless/测试），false=挂起并等 UI 弹窗选奖品（实机）。
var auto_champion := true

const RNG_SEED_DEFAULT := 20260912
# 镇邪峰（除魔地）单次缴获公式 —— 线性平滑版：
#   灵石 = 在岗外门数 × FUMO_BASE   × (除魔地难度+1) × 武力倍率pmult
#   庇护 = 在岗外门数 × FUMO_PROTECT × (除魔地难度+1) × 武力倍率pmult
# 难度按 tgt["need"]（0~9）线性递增；宗门周边(need=0, atk=0)在常规队伍下 ≤ 1万。
# 武力倍率 pmult（方案C 的对数衰减+封顶）：仅对有推荐武力的除魔地生效，
#   pmult = clamp(1 + ln(1+power/atk)/FUMO_K, 1, FUMO_CAP)；atk=0（宗门周边）时恒为 1。
# FUMO_BASE / FUMO_PROTECT 是整体产量的可调旋钮：想更高就调大、想更低就调小。
const FUMO_BASE := 800.0
const FUMO_PROTECT := 30.0
const FUMO_K := 1.0
const FUMO_CAP := 3.0

# 杂役弟子：每个杂役的基础劳动效率；额外对每个在岗峰的效率 +5%
const MENIAL_BASE := 1.0
const MENIAL_BONUS := 0.05
const MENIAL_GLOBAL_CAP := 1200    # 杂役弟子总人数上限
const MENIAL_PEAK_CAP := 200       # 单峰杂役目标上限


func _init(seed_value: int = -1) -> void:
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value


# ═══════════════════════════════════════════════════════
# RNG 工具
# ═══════════════════════════════════════════════════════

func _r() -> float:
	return rng.randf()


func _ri(a: int, b: int) -> int:
	return rng.randi_range(a, b)


func _pick(arr: Array):
	if arr.is_empty():
		return null
	return arr[rng.randi_range(0, arr.size() - 1)]


func _chance(p: float) -> bool:
	return rng.randf() < p


## 加权抽取：list 内每项需含 "w"
func _weight(list: Array) -> Dictionary:
	var total := 0.0
	for it in list:
		total += float((it as Dictionary).get("w", 1))
	var r := rng.randf() * total
	for it in list:
		r -= float((it as Dictionary).get("w", 1))
		if r <= 0.0:
			return it
	return list[list.size() - 1]


## 灵根品质：越靠前越稀有
func _roll_linggen() -> int:
	var r := rng.randf()
	if r < 0.010: return 0   # 变异天灵根 1%
	if r < 0.045: return 1   # 天灵根 3.5%
	if r < 0.105: return 2   # 变异灵根 6%
	if r < 0.305: return 3   # 单灵根 20%
	if r < 0.555: return 4   # 双灵根 25%
	if r < 0.755: return 5   # 三灵根 20%
	if r < 0.905: return 6   # 四灵根 15%
	return 7                 # 杂灵根 9.5%


## 为指定灵根品质随机生成属性组合（UI 转动用）
func roll_linggen_elements(idx: int) -> Array:
	var lg: Dictionary = DataCore.LINGGEN[idx]
	var pool := DataCore.ELEMENTS.duplicate()
	var out: Array = []
	for i in int(lg["count"]):
		out.append(pool.pop_at(_ri(0, pool.size() - 1)))
	return out


# ═══════════════════════════════════════════════════════
# 数字显示
# ═══════════════════════════════════════════════════════

static func fmt_num(v) -> String:
	var n := int(floor(float(v)))
	if n < 10000:
		return str(n)
	if n < 100000000:
		if n < 100000:
			return "%.2f万" % (n / 10000.0)
		return "%.1f万" % (n / 10000.0)
	if n < 1000000000000:
		return "%.2f亿" % (n / 100000000.0)
	return "%.2f兆" % (n / 1000000000000.0)


# ═══════════════════════════════════════════════════════
# 新开一局
# ═══════════════════════════════════════════════════════

## cfg: {name, sectName, sex, linggen, fami, tags}
func new_game(cfg: Dictionary) -> Dictionary:
	var old: Dictionary = s if not s.is_empty() else {}

	var gongde: Array = []
	for i in DataCore.GONGDE.size():
		gongde.append(0)
	if old.has("gongde"):
		# 功德建筑跨轮回保留
		var prev: Array = old["gongde"]
		for i in mini(prev.size(), gongde.size()):
			gongde[i] = int(prev[i])

	var peaks := {}
	for p in DataCore.PEAKS:
		peaks[p["id"]] = _new_peak_state()

	s = {
		"sectName": str(cfg.get("sectName", "无名宗")),
		"year": 1, "month": 1, "xun": 1, "tick": 0,
		"speed": 1,
		"stone": 3000.0,
		"protect": 0.0,
		"menial": 0,   # 杂役弟子总数（随庇护人数+时间增长）
		"merit": maxf(0.0, float(old.get("merit", 0.0)) - float(cfg.get("merit_cost", 0.0))),
		"cycle": int(old.get("cycle", 0)) + 1,
		"herbs": _fill_i(10, 0),
		"ores": _fill_i(10, 0),
		"pills": {},
		"equips": [],
		"books": [],
		"houseLv": 1,
		"arrayLv": 1,
		"gongde": gongde,
		"peaks": peaks,
		"people": [],
		"log": [],
		"nextId": 1,
		"tianti": 0,
		"championLeft": 36 * 3,   # 3 年后首次大比
		"fightTarget": 0,
		"pending_champion": {},   # 大比挂起态（UI 选奖品时暂存胜者与候选奖品）
	}

	# 掌门
	var master := make_person({
		"name": cfg.get("name", "无名"),
		"sex": int(cfg.get("sex", 0)),
		"linggenIdx": int(cfg.get("linggen", 0)),
		"elements": (cfg.get("linggen_elements", []) as Array).duplicate(),
		"famiIdx": int(cfg.get("fami", 0)),
		"tags": (cfg.get("tags", []) as Array).duplicate(),
		"age": 20,
	})
	master["job"] = "leader"
	master["inner"] = true
	master["realm"] = 1   # 开宗时宗主默认筑基初阶
	master["sub"] = 0
	s["people"].append(master)
	push_log("%s镇压了本地的邪祟，创建了%s，镇压邪祟获得功德。" % [master["name"], s["sectName"]], "good")
	push_log("提示：先在设施页把弟子分派到各峰，宗门才能运转起来。", "hint")

	# 初始 3 名弟子
	for i in 3:
		add_disciple(true)
	auto_assign()
	emit_signal("changed")
	return s


func _new_peak_state() -> Dictionary:
	return {
		"leader": null, "deputy": [], "outer": 0, "secret": 0,
		"progress": 0.0, "pill": 1, "equipLv": 0, "herbLv": 0, "oreLv": 0,
		"writer": null, "writeProgress": 0.0, "herbAcc": 0,
		"menial": 0, "menialOn": 0,   # 杂役目标/在岗数（玄元峰、撰书阁不占用）
	}


func _fill_i(n: int, v: int) -> Array:
	var a: Array = []
	a.resize(n)
	a.fill(v)
	return a


# ═══════════════════════════════════════════════════════
# 弟子生成
# ═══════════════════════════════════════════════════════

func make_person(o: Dictionary) -> Dictionary:
	var linggen_idx := int(o["linggenIdx"]) if o.has("linggenIdx") else _roll_linggen()
	var lg: Dictionary = DataCore.LINGGEN[linggen_idx]
	var fami_idx := int(o["famiIdx"]) if o.has("famiIdx") else _ri(0, DataCore.FAMI.size() - 1)
	var tags: Array = (o["tags"] as Array).duplicate() if o.has("tags") else roll_tags()
	# 出身自带特质（如魔域→身存魔种、合欢宗→貌美），并入去重
	var fami_d: Dictionary = DataCore.FAMI[fami_idx]
	for tn in fami_d.get("tags", []):
		var ti := _tag_index(tn)
		if ti >= 0 and not tags.has(ti):
			tags.append(ti)
	var sex := int(o["sex"]) if o.has("sex") else _ri(0, 1)

	var elements: Array = []
	if o.has("elements") and (o["elements"] as Array).size() >= int(lg["count"]):
		elements = (o["elements"] as Array).slice(0, int(lg["count"]))
	else:
		var pool := DataCore.ELEMENTS.duplicate()
		for i in int(lg["count"]):
			elements.append(pool.pop_at(_ri(0, pool.size() - 1)))

	var age := int(o["age"]) if o.has("age") else _ri(15, 40)

	var rebirth := false
	var modao := false
	for t in tags:
		var td: Dictionary = DataCore.TAGS[int(t)]
		if td.get("rebirth", false):
			rebirth = true
		if td["n"] == "修魔":
			modao = true

	var p := {
		"id": int(s["nextId"]) if not s.is_empty() else 1,
		"name": str(o["name"]) if o.has("name") else rand_name(sex),
		"sex": sex, "linggenIdx": linggen_idx, "elements": elements,
		"famiIdx": fami_idx, "tags": tags,
		"age": age,
		"realm": 0, "sub": 0,
		"qi": 0.0,
		"atkBonus": 1.0,
		"qiRateB": 0.0,
		"brkBonus": 0.0,
		"mood": 60.0,
		"lifespanBonus": 0.0,
		"job": null, "peak": null, "inner": false,
		"alive": true, "fly": false, "dormant": false,
		"master": null, "spouse": null, "parents": [], "apprentices": [],
		"equip": [null, null, null, null, null],
		"demon": 0.0,
		"is_demon": false,
		"demonDone": false,
		"is_modao": modao,
		"rebirth": rebirth,
	}
	p["lifespan"] = DataCore.REALM_LIFESPAN[0] + _ri(-10, 20)
	if not s.is_empty():
		s["nextId"] = int(s["nextId"]) + 1
	return p


func rand_name(sex: int) -> String:
	var x: String = _pick(DataCore.XING)
	var m: String = _pick(DataCore.MING_F if sex == 1 else DataCore.MING_M)
	return x + m


func roll_tags() -> Array:
	var n := 0
	if _chance(0.35):
		n = 2 if _chance(0.25) else 1
	var out: Array = []
	for i in n:
		var t := _ri(0, DataCore.TAGS.size() - 1)
		if not out.has(t):
			out.append(t)
	return out


## 按特质名找索引（出身自带特质用）
func _tag_index(name: String) -> int:
	for i in DataCore.TAGS.size():
		if DataCore.TAGS[i]["n"] == name:
			return i
	return -1


func add_disciple(silent: bool = false) -> Dictionary:
	var p := make_person({})
	# 日常投奔只入外门；内门仅由「宗门大比」提拔（对齐原 APK 设定）
	p["inner"] = false
	s["people"].append(p)
	if not silent:
		push_log("%s前来拜入宗门，成为%s弟子，时年%d岁。" % [
			p["name"], "内门" if p["inner"] else "外门", int(p["age"])], "good")
	return p


# ═══════════════════════════════════════════════════════
# 属性计算
# ═══════════════════════════════════════════════════════

## 综合效率倍率
## perm=true 时不含「心情」与「武力倍率(atkBonus)」等受事件影响的临时项，
## 用于计算武力上限（潜力峰值）；当前武力用 perm=false。
func eff(p: Dictionary, key: String, perm: bool = false) -> float:
	var v := 1.0
	var lg: Dictionary = DataCore.LINGGEN[int(p["linggenIdx"])]
	var fami: Dictionary = DataCore.FAMI[int(p["famiIdx"])]

	# 灵根品质
	if key == "cultivate":
		v *= float(lg["rate"])
	if key == "atk":
		v *= float(lg["atk"])

	# 灵根属性匹配工作
	if key in ["plant", "mine", "refine", "forge", "explore", "cultivate"]:
		var hit := 0
		for e in p["elements"]:
			if DataCore.ELEMENT_WORK.get(e, "") == key:
				hit += 1
		v *= 1.0 + hit * 0.12

	# 出身
	if key == "cultivate":
		v *= float(fami["qi"])
	if key == "atk":
		v *= float(fami["atk"])
	if key == "plant" and fami.has("plant"):
		v += float(fami["plant"])
	if key == "mine" and fami.has("mine"):
		v += float(fami["mine"])
	if key == "explore" and fami.has("explore"):
		v += float(fami["explore"])
	if key == "refine" and fami.has("refine"):
		v += float(fami["refine"])
	if key == "forge" and fami.has("forge"):
		v += float(fami["forge"])

	# 特质
	for ti in p["tags"]:
		var t: Dictionary = DataCore.TAGS[int(ti)]
		if key == "atk" and t.has("atk"):
			v += float(t["atk"])
		if key == "cultivate" and t.has("qi"):
			v += float(t["qi"])
		if key == "plant" and t.has("plant"):
			v += float(t["plant"])
		if key == "mine" and t.has("mine"):
			v += float(t["mine"])
		if key == "refine" and t.has("refine"):
			v += float(t["refine"])

	# 功德建筑（gongde[i] 为等级）
	for i in DataCore.GONGDE.size():
		var g: Dictionary = DataCore.GONGDE[i]
		if g["eff"] == key:
			v += float(g["v"]) * float(s["gongde"][i])

	# 装备
	for e in p["equip"]:
		if e is Dictionary and (e as Dictionary)["attrs"].has(key):
			v += float((e as Dictionary)["attrs"][key])

	# 功法
	for b in s["books"]:
		var bb: Dictionary = b
		if bb["attrs"].has(key) and _book_ratio(p, bb) > 0.0:
			v += float(bb["attrs"][key]) * _book_ratio(p, bb)

	# 师徒：徒弟受师尊教导，修炼效率随师尊境界提升（封顶 0.4）
	if key == "cultivate" and p["master"] != null:
		var mst: Dictionary = by_id(p["master"])
		if not mst.is_empty():
			v += minf(0.4, 0.05 * (float(mst["realm"]) + 1.0))

	# 事件累积加成（原版写入却未读取，这里接上）
	if key == "cultivate":
		v += float(p["qiRateB"])
	if key == "atk":
		v *= float(p["atkBonus"])

	# 心情影响（perm 模式跳过，用于武力上限）
	if not perm:
		var mood_k := 0.6 + (float(p["mood"]) / 100.0) * 0.6
		v *= mood_k

	# 灵石缺乏且无职务
	if float(s["stone"]) <= 0.0 and p["job"] == null:
		v *= 0.5

	return maxf(0.05, v)


## 功法对弟子的加成比例：书要求的灵根中，弟子拥有的个数 ÷ 弟子灵根总数。
## 例：火木水撰写人写「火」单属性书 → 杂灵根(5)得 1/5、火水双灵根得 1/2、火单灵根得 1/1(100%)。
## req 为空（旧书兼容）视为全员受益，返回 1.0。
func _book_ratio(p: Dictionary, b: Dictionary) -> float:
	var req: Array = b.get("req", [])
	if req.is_empty():
		return 1.0
	var pe: Array = p["elements"]
	var hit := 0
	for e in req:
		if (pe as Array).has(e):
			hit += 1
	if hit == 0:
		return 0.0
	return float(hit) / float((pe as Array).size())


func qi_max(p: Dictionary) -> float:
	return floor(100.0 * pow(2.6, float(p["realm"])) * (1.0 + float(p["sub"]) * 0.35))


func atk_of(p: Dictionary) -> float:
	var base := 12.0 * pow(4.2, float(p["realm"])) * (1.0 + float(p["sub"]) * 0.35)
	return floor(base * eff(p, "atk"))


## 武力上限（潜力峰值）：不含心情与 atkBonus 等受事件影响的临时项。
## 当前武力 atk_of 会因事件（心情/倍率）低于此值；此值即原游戏的「武力/上限」中的上限。
func atk_max(p: Dictionary) -> float:
	var base := 12.0 * pow(4.2, float(p["realm"])) * (1.0 + float(p["sub"]) * 0.35)
	return floor(base * eff(p, "atk", true))


## 法宝属性键 → 中文（用于大比选奖品弹窗展示）
static func attr_cn(k: String) -> String:
	match k:
		"cultivate": return "修炼"
		"atk": return "武力"
		"break": return "突破"
		"death": return "陨落"
		"explore": return "探索"
		"plant": return "灵植"
		"mine": return "采掘"
		"refine": return "炼丹"
		"forge": return "炼器"
		_: return k


func lifespan_of(p: Dictionary) -> int:
	return int(DataCore.REALM_LIFESPAN[int(p["realm"])] + float(p["lifespanBonus"]))


func brk_rate(p: Dictionary) -> float:
	var r := float(DataCore.REALM_BREAK[int(p["realm"])]) + float(p["brkBonus"])
	r += float(s["gongde"][6]) * 0.01   # 冥思阁
	for ti in p["tags"]:
		var t: Dictionary = DataCore.TAGS[int(ti)]
		if t.has("brk"):
			r += float(t["brk"])
	var fami_b: Dictionary = DataCore.FAMI[int(p["famiIdx"])]
	if fami_b.has("brk"):
		r += float(fami_b["brk"])
	for e in p["equip"]:
		if e is Dictionary and (e as Dictionary)["attrs"].has("break"):
			r += float((e as Dictionary)["attrs"]["break"])
	if p["spouse"] != null:
		r += 0.10   # 道侣
	# 功法：突破几率加成（按灵根比例）
	for b in s["books"]:
		var bb: Dictionary = b
		if bb["attrs"].has("break") and _book_ratio(p, bb) > 0.0:
			r += float(bb["attrs"]["break"]) * _book_ratio(p, bb)
	return clampf(r, 0.01, 0.99)


func death_rate(p: Dictionary) -> float:
	var r := float(DataCore.REALM_DEATH[mini(9, int(p["realm"]) + 1)])
	r += float(s["gongde"][7]) * (-0.0025)   # 洗孽池
	for ti in p["tags"]:
		var t: Dictionary = DataCore.TAGS[int(ti)]
		if t.has("death"):
			r += float(t["death"])
	for e in p["equip"]:
		if e is Dictionary and (e as Dictionary)["attrs"].has("death"):
			r += float((e as Dictionary)["attrs"]["death"])
	# 功法：渡劫死亡率降低（按灵根比例，负向加成）
	for b in s["books"]:
		var bb: Dictionary = b
		if bb["attrs"].has("death") and _book_ratio(p, bb) > 0.0:
			r += float(bb["attrs"]["death"]) * _book_ratio(p, bb)
	return maxf(0.0, r)


func realm_name(p: Dictionary) -> String:
	if p["fly"]:
		return "已飞升"
	if not p["alive"]:
		return "已陨落"
	if int(p["realm"]) >= 9:
		return "飞升"
	var sub_i := int(p["sub"])
	var nm: String
	if int(p["realm"]) >= 6:
		nm = str(DataCore.REALMS[int(p["realm"])]) + str(DataCore.SUB_ALT[mini(3, int(floor(sub_i / 2.5)))])
	else:
		nm = str(DataCore.REALMS[int(p["realm"])]) + str(DataCore.SUB[sub_i])
	# 魔修（修魔特质）或已彻底堕魔者，境界后标记「· 已堕魔」
	if bool(p.get("is_modao", false)) or bool(p.get("is_demon", false)):
		nm += " · 已堕魔"
	return nm


# ═══════════════════════════════════════════════════════
# 时间推进（一旬）
# ═══════════════════════════════════════════════════════

func tick() -> void:
	# 大比选奖品弹窗挂起时，冻结模拟直到玩家选定
	if not s.get("pending_champion", {}).is_empty():
		return

	s["tick"] = int(s["tick"]) + 1
	s["xun"] = int(s["xun"]) + 1
	if int(s["xun"]) > 3:
		s["xun"] = 1
		s["month"] = int(s["month"]) + 1
	if int(s["month"]) > 12:
		s["month"] = 1
		s["year"] = int(s["year"]) + 1
		on_year()

	fill_outer()
	production()
	cultivate()
	expenses()
	random_events()
	takeover_backlash()

	s["championLeft"] = int(s["championLeft"]) - 1
	if int(s["championLeft"]) <= 0:
		if auto_champion:
			champion()   # headless/测试：自动结算
		else:
			var cand := _champion_cand()
			if cand.is_empty():
				push_log("本届门派大比，未能选拔出杰出弟子。", "hint")
				s["championLeft"] = 36 * 5 + _ri(0, 36)
			else:
				# 实机：挂起并等 UI 弹窗选奖品
				s["pending_champion"] = {
					"id": int(cand["id"]), "name": cand["name"],
					"prizes": _champion_prizes(),
				}
				emit_signal("changed")
				return

	# 偶尔有新弟子投奔（与庇护人数相关）
	var chance := 0.02 + minf(0.12, float(s["protect"]) / 20000.0)
	if _chance(chance) and population() < capacity():
		add_disciple(false)

	# 无掌门则推举
	var has_leader := false
	for p in s["people"]:
		if p["alive"] and not p["fly"] and not p["dormant"] and p["job"] == "leader":
			has_leader = true
			break
	if not has_leader:
		auto_assign()

	emit_signal("changed")


func population() -> int:
	var n := 0
	for p in s["people"]:
		if p["alive"] and not p["fly"] and not p["dormant"]:
			n += 1
	return n


func capacity() -> int:
	return 6 + int(s["houseLv"]) * 4


func alive_list() -> Array:
	var out: Array = []
	for p in s["people"]:
		if p["alive"] and not p["fly"] and not p["dormant"]:
			out.append(p)
	return out


func on_year() -> void:
	_grow_menial()   # 杂役弟子随庇护人数与时间增长
	for p in alive_list():
		p["age"] = int(p["age"]) + 1
		# 堕魔判定
		for ti in p["tags"]:
			var t: Dictionary = DataCore.TAGS[int(ti)]
			if t.has("demon"):
				p["demon"] = float(p["demon"]) + float(t["demon"])
		if float(p["demon"]) > 0.0 and _chance(float(p["demon"])) and not p["demonDone"]:
			p["demonDone"] = true
			p["is_demon"] = true
			p["mood"] = 20.0
			p["brkBonus"] = float(p["brkBonus"]) - 0.05
			push_log("%s无法突破心魔，堕为魔修。" % p["name"], "bad")
			# 堕魔者若在位则自动卸任峰主
			for k in s["peaks"]:
				var pk2: Dictionary = s["peaks"][k]
				if pk2["leader"] == p["id"]:
					pk2["leader"] = null
					p["peak"] = null
					if p["job"] != "leader":
						p["job"] = null
					push_log("%s堕为魔修，自%s峰主之位退下。" % [p["name"], DataCore.peak_by_id(k).get("n", k)], "bad")

	# 子嗣：道侣每年有一定概率诞下后代，灵根取自双亲元素并集
	var newborns: Array = []
	var pair_seen: Dictionary = {}
	for p in alive_list():
		if p["spouse"] == null:
			continue
		var sp: Dictionary = by_id(p["spouse"])
		if sp.is_empty() or not sp["alive"]:
			continue
		if int(p["realm"]) < 1 or int(sp["realm"]) < 1:
			continue   # 至少筑基方为成年结缘生子
		var pk_key: String = "%d_%d" % [mini(int(p["id"]), int(sp["id"])), maxi(int(p["id"]), int(sp["id"]))]
		if pair_seen.has(pk_key):
			continue
		pair_seen[pk_key] = true
		if population() >= capacity():
			continue
		if _chance(0.06):
			var c := _make_child(p, sp)
			if not c.is_empty():
				newborns.append(c)
	for c in newborns:
		s["people"].append(c)
		var pa := by_id(c["parents"][0])
		var pb := by_id(c["parents"][1])
		push_log("%s与%s喜结连理，诞下子嗣%s，入了宗门。" % [
			pa["name"] if not pa.is_empty() else "？", pb["name"] if not pb.is_empty() else "？", c["name"]], "good")

	# 每年自动存档一次
	save()


## 道侣诞下的子嗣：灵根取自双亲元素并集，数量随机 1~并集大小（封顶 5）
func _make_child(a: Dictionary, b: Dictionary) -> Dictionary:
	var pool: Array = []
	for e in a["elements"]:
		if not (pool as Array).has(e):
			pool.append(e)
	for e in b["elements"]:
		if not (pool as Array).has(e):
			pool.append(e)
	if pool.is_empty():
		return {}
	var cnt := mini(pool.size(), _ri(1, 5))
	var els: Array = []
	for i in cnt:
		els.append(pool.pop_at(_ri(0, pool.size() - 1)))
	# 匹配灵根档位（按元素个数取对应档）
	var lg_idx := 4
	for i in DataCore.LINGGEN.size():
		if int(DataCore.LINGGEN[i]["count"]) == els.size():
			lg_idx = i
			break
	var child := make_person({"linggenIdx": lg_idx, "elements": els, "age": 0, "tags": []})
	child["parents"] = [int(a["id"]), int(b["id"])]
	child["name"] = rand_name(int(child["sex"]))
	return child


# ═══════════════════════════════════════════════════════
# 修炼与突破
# ═══════════════════════════════════════════════════════

func cultivate() -> void:
	for p in alive_list():
		if int(p["realm"]) >= 9:
			continue

		# 寿元判定
		if int(p["age"]) > lifespan_of(p):
			p["dormant"] = true
			p["qi"] = 0.0
			push_log("%s寿元已尽，进入休眠。" % p["name"], "bad")
			on_death(p)
			continue

		# 大圆满：每旬尝试破境，不再积攒灵气
		if int(p["sub"]) >= 9:
			if _chance(brk_rate(p) / 8.0):
				do_breakthrough(p)
			elif _chance(0.015):
				p["mood"] = maxf(0.0, float(p["mood"]) - 5.0)
				var nxt: String = str(DataCore.REALMS[int(p["realm"]) + 1]) if int(p["realm"]) + 1 < 10 else "飞升"
				push_log("%s冲击%s未成，暂且按下。" % [p["name"], nxt], "bad")
			continue

		var mx := qi_max(p)
		# 有职务者修炼较慢
		var job_pen := 1.0
		if p["job"] != null:
			job_pen = 0.5 if p["job"] == "leader" else 0.7
		var gain := (mx / (8.0 * (float(p["realm"]) + 1.0))) * eff(p, "cultivate") * job_pen
		p["qi"] = float(p["qi"]) + gain

		if float(p["qi"]) >= mx:
			p["qi"] = 0.0
			p["sub"] = int(p["sub"]) + 1


## 执行破境（已判定成功）
func do_breakthrough(p: Dictionary) -> void:
	var dr := death_rate(p)
	if dr > 0.0 and _chance(dr) and not p["rebirth"]:
		p["alive"] = false
		push_log("%s渡劫失败，不幸陨落。" % p["name"], "bad")
		on_death(p)
		return
	p["realm"] = int(p["realm"]) + 1
	p["sub"] = 0
	p["qi"] = 0.0
	p["mood"] = minf(100.0, float(p["mood"]) + 25.0)
	# 境界升入元婴：外门弟子自动收归内门（脱离原 XX 峰外门，无法宝赏赐）
	if int(p["realm"]) == 3 and not p["inner"]:
		p["inner"] = true
		var old_peak = p["peak"]
		p["peak"] = null
		var where := ""
		if old_peak != null:
			where = "（脱离%s外门）" % str(DataCore.peak_by_id(str(old_peak)).get("n", ""))
		push_log("%s突破至元婴，道行有成，正式收归内门%s。" % [p["name"], where], "good")
	if int(p["realm"]) >= 9:
		p["fly"] = true
		_repair_tianti()
		push_log("%s功德圆满，白日飞升，从此不在这片天地。" % p["name"], "good")
		on_death(p)
	else:
		push_log("%s闭关苦修，一朝破境，晋为%s。" % [p["name"], DataCore.REALMS[int(p["realm"])]], "good")


## 每有弟子飞升，修复天梯一层
func _repair_tianti() -> void:
	if int(s["tianti"]) >= 9:
		return
	var i := int(s["tianti"])
	s["tianti"] = i + 1
	s["merit"] = float(s["merit"]) + 50.0
	push_log("天梯第%d层「%s」修复完成，天道赐下%s，功德 +50。" % [
		i + 1, DataCore.TIANTI[i], DataCore.TIANTI_ITEM[i]], "good")


func on_death(p: Dictionary) -> void:
	# 卸任
	if p["job"] == "leader":
		push_log("掌门%s已不在，需在门徒页另立新掌门。" % p["name"], "hint")
	for k in s["peaks"]:
		var pk: Dictionary = s["peaks"][k]
		if pk["leader"] == p["id"]:
			pk["leader"] = null
		pk["deputy"] = (pk["deputy"] as Array).filter(func(id): return id != p["id"])
		if pk["writer"] == p["id"]:
			pk["writer"] = null
	# 法宝：有首徒则传首徒（填满空位），其余归公库；并清理徒弟的师尊引用
	var heir: Dictionary = {}
	if not p["apprentices"].is_empty():
		var hid = p["apprentices"][0]
		heir = by_id(hid)
	for e in p["equip"]:
		if e != null:
			var given := false
			if not heir.is_empty():
				for i in 5:
					if heir["equip"][i] == null:
						heir["equip"][i] = e
						given = true
						break
			if not given:
				s["equips"].append(e)
	p["equip"] = [null, null, null, null, null]
	if not p["apprentices"].is_empty():
		for aid in (p["apprentices"] as Array).duplicate():
			var ap := by_id(aid)
			if not ap.is_empty():
				ap["master"] = null
		push_log("%s坐化，法宝传于首徒%s。" % [p["name"], heir["name"]], "hint")
	p["apprentices"] = []
	if p["spouse"] != null:
		var sp := by_id(p["spouse"])
		if sp != null:
			sp["spouse"] = null
			sp["mood"] = maxf(0.0, float(sp["mood"]) - 30.0)
	auto_assign()


func by_id(id) -> Dictionary:
	for p in s["people"]:
		if p["id"] == id:
			return p
	return {}


# ═══════════════════════════════════════════════════════
# 外门弟子调度：按各峰目标人数自动补员
# ═══════════════════════════════════════════════════════

func fill_outer() -> void:
	# 先回收超编
	for pkd in DataCore.PEAKS:
		var st: Dictionary = s["peaks"][pkd["id"]]
		var cur := outer_of(pkd["id"])
		while cur.size() > int(st["outer"]):
			cur[cur.size() - 1]["peak"] = null
			cur = outer_of(pkd["id"])
	# 再补足缺员，优先补武力高的
	for pkd in DataCore.PEAKS:
		var st: Dictionary = s["peaks"][pkd["id"]]
		var cur_n := outer_of(pkd["id"]).size()
		while cur_n < int(st["outer"]):
			var pool := _idle_list()
			if pool.is_empty():
				break
			pool.sort_custom(func(a, b): return atk_of(a) > atk_of(b))
			pool[0]["peak"] = pkd["id"]
			cur_n += 1


func _idle_list() -> Array:
	var out: Array = []
	for p in alive_list():
		if p["peak"] == null and not p["inner"] and p["job"] != "leader":
			out.append(p)
	return out


# ═══════════════════════════════════════════════════════
# 生产结算
# ═══════════════════════════════════════════════════════

func _peak_open(peak_id: String, allow_menial: bool) -> bool:
	# 开工门槛（统一）：杂役在岗≥1 / 外门在岗≥1 / 有副手 / 有峰主，任一即开工
	var pk: Dictionary = s["peaks"][peak_id]
	if allow_menial and int(pk.get("menialOn", 0)) >= 1:
		return true
	if outer_of(peak_id).size() >= 1:
		return true
	if (pk["deputy"] as Array).size() > 0:
		return true
	return pk["leader"] != null


func production() -> void:
	_alloc_menial()   # 每旬按各峰目标从全局杂役池分配在岗数
	var pk: Dictionary = s["peaks"]

	# ── 镇邪峰：队伍除魔 → 灵石 + 庇护
	var fumo_st: Dictionary = pk["fumo"]
	var fumo_lead = by_id(fumo_st["leader"])
	if not fumo_lead.is_empty():
		var tgt: Dictionary = DataCore.FIGHT[int(s["fightTarget"])]
		var need_realm: int = int(tgt["need"])
		if int(fumo_lead["realm"]) < need_realm:
			if int(s["tick"]) % 36 == 0:
				push_log("%s境界不足，无法率领队伍前往%s（需%s以上）。" % [
					fumo_lead["name"], tgt["n"], DataCore.REALMS[need_realm]], "hint")
		else:
			var fumo_out := outer_of("fumo").size()
			var power := team_power("fumo")
			var risk := fight_risk()
			# 持续作战的伤亡（每旬都可能发生）
			if risk > 0.25 and _chance((risk - 0.2) * 0.06):
				var fpool := outer_of("fumo")
				if not fpool.is_empty():
					var victim: Dictionary = _pick(fpool)
					victim["alive"] = false
					push_log("%s在和魔修的战斗中受伤过重，不幸陨落。" % victim["name"], "bad")
					on_death(victim)

			# 攻略进度：每旬推进，满额攻破即得奖励（灵石+庇护），与寻幽峰一致
			var fp := float(s["peaks"]["fumo"]["progress"])
			fp += team_eff("fumo", "explore") * (1.0 - risk) * 1.5
			if fp >= 100.0:
				fp = 0.0
				# 线性平滑版：难度(need+1)线性递增；武力倍率 pmult 仅对有推荐武力的地生效
				var atk: float = float(tgt["atk"])
				var pmult: float = 1.0
				if atk > 0.0:
					pmult = clampf(1.0 + log(1.0 + power / atk) / FUMO_K, 1.0, FUMO_CAP)
				var dcoef: float = float(int(tgt["need"]) + 1)
				var gain := int(fumo_out * FUMO_BASE * dcoef * pmult)
				s["stone"] = float(s["stone"]) + gain
				var pr := int(fumo_out * FUMO_PROTECT * dcoef * pmult)
				s["protect"] = float(s["protect"]) + pr
				push_log("除魔队伍攻破%s，魔气为之一清，周边百姓得以安生。" % tgt["n"], "good")
				push_log("缴获灵石%s、宗门庇护人数%s。" % [fmt_num(gain), fmt_num(pr)], "good")
			s["peaks"]["fumo"]["progress"] = fp
	# ── 寻幽峰：秘境探索
	var xunyou: Dictionary = pk["xunyou"]
	var xy_lead = by_id(xunyou["leader"])
	if not xy_lead.is_empty():
		var sec: Dictionary = DataCore.SECRETS[int(xunyou["secret"])]
		var need_realm: int = int(sec["need"])
		if int(xy_lead["realm"]) < need_realm:
			if int(s["tick"]) % 36 == 0:
				push_log("%s境界不足，无法率领队伍探索%s（需%s以上）。" % [
					xy_lead["name"], sec["n"], DataCore.REALMS[need_realm]], "hint")
		else:
			var xy_power := team_power("xunyou")
			var risk := secret_risk(float(sec["atk"]), xy_power)
			if _chance(1.0 - risk):
				var spd := team_eff("xunyou", "explore") * 1.2
				xunyou["progress"] = float(xunyou["progress"]) + spd
				if float(xunyou["progress"]) >= 100.0:
					xunyou["progress"] = 0.0
					var lv := mini(9, int(floor(float(sec["need"]) * 0.9)) + _ri(0, 1))
					var h := _ri(3, 8)
					var o := _ri(3, 8)
					s["herbs"][lv] = int(s["herbs"][lv]) + h
					s["ores"][lv] = int(s["ores"][lv]) + o
					var st_gain := _ri(200, 600) * (1 + lv * 2)
					s["stone"] = float(s["stone"]) + st_gain
					push_log("探索队伍攻略了%s，带回灵草×%d、灵矿×%d、灵石%s。" % [
						sec["n"], h, o, fmt_num(st_gain)], "good")
					xy_lead["mood"] = minf(100.0, float(xy_lead["mood"]) + 10.0)
			else:
				# 失败：可能有人受伤，减少最大寿元
				if _chance(risk * 0.5):
					_secret_injury("xunyou")
				if int(s["tick"]) % 36 == 0:
					push_log("探索%s的队伍遭遇险阻，被迫撤回休整。" % sec["n"], "hint")

	# ── 其余各峰的外门弟子打杂，换些灵石
	for pid in pk:
		if pid == "fumo":
			continue
		s["stone"] = float(s["stone"]) + outer_of(pid).size() * 7

	# ── 青芜峰：种药（开工：杂役/外门在岗≥1 或 有副手 或 有峰主）
	var yao: Dictionary = pk["shenyao"]
	if _peak_open("shenyao", true):
		var lv := mini(9, realm_of_id(yao["leader"]) + int(floor(int(yao["herbLv"]) / 3.0)))
		var n := int(floor(peak_yield("shenyao", "plant") * 1.2))
		s["herbs"][lv] = int(s["herbs"][lv]) + n
		yao["herbAcc"] = int(yao.get("herbAcc", 0)) + n
		# 开辟进度（满额自动提升药田品阶，纯积累、不奖励额外产出）
		var yinc := mini(4.0, 0.8 + peak_yield("shenyao", "plant") * 0.5)
		yao["progress"] = float(yao["progress"]) + yinc
		if float(yao["progress"]) >= 100.0:
			yao["progress"] = 0.0
			if int(yao["herbLv"]) < 30:
				yao["herbLv"] = int(yao["herbLv"]) + 1
				push_log("青芜峰药田进一步开辟，可种植灵草品阶提升。", "good")

	# ── 玄矿峰：采掘（开工：杂役/外门在岗≥1 或 有副手 或 有峰主）
	var kuang: Dictionary = pk["lingkuang"]
	if _peak_open("lingkuang", true):
		var lv := mini(9, realm_of_id(kuang["leader"]) + int(floor(int(kuang["oreLv"]) / 3.0)))
		var n := int(floor(peak_yield("lingkuang", "mine") * 1.2))
		s["ores"][lv] = int(s["ores"][lv]) + n
		# 开辟进度（满额自动提升矿道品阶，纯积累、不奖励额外产出）
		var kinc := mini(4.0, 0.8 + peak_yield("lingkuang", "mine") * 0.5)
		kuang["progress"] = float(kuang["progress"]) + kinc
		if float(kuang["progress"]) >= 100.0:
			kuang["progress"] = 0.0
			if int(kuang["oreLv"]) < 30:
				kuang["oreLv"] = int(kuang["oreLv"]) + 1
				push_log("玄矿峰矿道进一步开辟，可采掘灵矿品阶提升。", "good")

	# ── 丹宸峰：炼丹（开工：外门在岗≥1 或 有副手 或 有峰主）
	var dan: Dictionary = pk["danding"]
	if _peak_open("danding", false):
		var pill: Dictionary = DataCore.PILLS[int(dan["pill"])]
		var lv := int(pill["lv"])
		if int(s["herbs"][lv]) >= 2:
			s["herbs"][lv] = int(s["herbs"][lv]) - 2
			dan["progress"] = float(dan["progress"]) + peak_yield("danding", "refine") * 1.5
			if float(dan["progress"]) >= 100.0:
				dan["progress"] = 0.0
				var key := int(dan["pill"])
				s["pills"][key] = int(s["pills"].get(key, 0)) + 1
				push_log("丹阁炼得%s一枚。" % pill["n"], "good")

	# ── 玄铸峰：炼器（开工：外门在岗≥1 或 有副手 或 有峰主）
	var qi2: Dictionary = pk["baiqi"]
	if _peak_open("baiqi", false):
		var lv := int(qi2["equipLv"])
		if int(s["ores"][lv]) >= 3:
			s["ores"][lv] = int(s["ores"][lv]) - 3
			qi2["progress"] = float(qi2["progress"]) + peak_yield("baiqi", "forge") * 1.2
			if float(qi2["progress"]) >= 100.0:
				qi2["progress"] = 0.0
				var e := make_equip(lv)
				s["equips"].append(e)
				push_log("器楼铸得%s%s一件。" % [DataCore.MLEVEL[lv], e["name"]], "good")

	# ── 撰书阁
	var zh: Dictionary = pk["zhuanzhu"]
	if zh["writer"] != null:
		var w := by_id(zh["writer"])
		if not w.is_empty():
			zh["writeProgress"] = float(zh["writeProgress"]) + eff(w, "cultivate") * (1.0 + float(s["gongde"][11]) * 0.06)
			if float(zh["writeProgress"]) >= 360.0:   # 10 年 = 360 旬
				zh["writeProgress"] = 0.0
				# 撰写数量随境界提升、封顶 5 本
				var cap := mini(5, int(w["realm"]) + 1)
				var cnt := 0
				for b in s["books"]:
					if int(b.get("author_id", -1)) == int(w["id"]):
						cnt += 1
				if cnt < cap:
					var b := make_book(w)
					s["books"].append(b)
					push_log("%s撰写了《%s》，宗门内符合条件的弟子皆受其益。" % [w["name"], b["name"]], "good")
					w["mood"] = minf(100.0, float(w["mood"]) + 30.0)
				else:
					push_log("%s功法已著满 %d 卷，搁笔休憩。" % [w["name"], cap], "hint")


func make_equip(lv: int) -> Dictionary:
	var slot := _ri(0, 4)
	var kind: String = _pick(DataCore.EQUIP_KIND[slot])
	var attrs := {}
	var keys := ["cultivate", "atk", "break", "death", "explore", "plant", "mine", "refine", "forge"]
	var n := _ri(1, 3)
	for i in n:
		var k: String = _pick(keys)
		var scale := 0.35 if (k == "atk" or k == "cultivate") else (0.04 if k == "break" else 0.12)
		attrs[k] = float(attrs.get(k, 0.0)) + (0.02 + lv * 0.02 + _r() * 0.05) * scale * 10.0
	# 「陨落」是负面属性（增加突破死亡率），若随机到且落单，则强制附带 1~2 条正面属性，
	# 让玩家在「强力但带陨落风险」与「稳妥」之间权衡取舍。
	var good_keys := ["cultivate", "atk", "break", "explore", "plant", "mine", "refine", "forge"]
	var has_good := false
	for k in attrs.keys():
		if k in good_keys:
			has_good = true
			break
	if attrs.has("death") and not has_good:
		var extra := _ri(1, 2)
		for i in extra:
			var k: String = _pick(good_keys)
			if attrs.has(k):
				continue
			var scale := 0.35 if (k == "atk" or k == "cultivate") else (0.04 if k == "break" else 0.12)
			attrs[k] = float(attrs.get(k, 0.0)) + (0.02 + lv * 0.02 + _r() * 0.05) * scale * 10.0
	var prefix: String = _pick(DataCore.SPIRITS) if _chance(0.12) else _pick(DataCore.ELEMENTS)
	return {
		"name": prefix + kind, "slot": slot, "lv": lv, "attrs": attrs,
		"spirit": _chance(0.15),
	}


## 撰写人著书：
## - 功法要求的灵根 = 撰写人灵根随机 1 种（单属性功法）
## - 效果键从七类随机：探索/种植/炼丹/采矿/炼器效率、突破几率、渡劫死亡率降低
## - 基础值随撰写人「实力」(境界) 与「灵根纯度」(单灵根越强) 提升，藏经楼再加成
## - 加成按「书 req 灵根占弟子灵根数比例」生效（见 _book_ratio / eff / brk_rate / death_rate）
func make_book(p: Dictionary) -> Dictionary:
	var req: Array = [_pick(p["elements"])]   # 单属性灵根要求
	var key: String = _pick(["explore", "plant", "refine", "mine", "forge", "break", "death"])
	var strength := 0.05 + float(p["realm"]) * 0.03          # 撰写人实力（境界越高越强）
	var purity := 2.0 / (1.0 + float((p["elements"] as Array).size()))  # 灵根越纯越强（单灵根=1.0，杂灵根≈0.33）
	var base := strength * purity * (1.0 + float(s["gongde"][11]) * 0.06)
	var name: String = str(req[0]) + str(_pick(DataCore.BOOK_KIND))
	if _chance(0.3):
		name += str(_pick(DataCore.BOOK_RANK))
	return {"name": name, "req": req, "attrs": {key: base}, "author": p["name"], "author_id": int(p["id"])}


## 队伍总效率：峰主 100% + 副手 50%，杂役在场时额外乘 (1 + 5%×杂役数)
## （玄元峰/撰书阁不分配杂役；外门 20% 计入 peak_yield）
func team_eff(peak_id: String, key: String) -> float:
	var pk: Dictionary = s["peaks"][peak_id]
	var lead := by_id(pk["leader"])
	var v := 0.0
	if not lead.is_empty():
		v = eff(lead, key) * 1.0
		for id in pk["deputy"]:
			var d := by_id(id)
			if not d.is_empty():
				v += eff(d, key) * 0.5
	var men := int(pk.get("menialOn", 0))
	v *= (1.0 + MENIAL_BONUS * men)
	return v


## 资源峰总劳动效率（青芜/玄矿/丹宸/玄铸）：
## 峰主 100% + 副手 50%（team_eff 内，含每杂役 +5% 乘子）+ 外门 20% + 杂役基础劳动
## 杂役基础劳动使「无领队但有杂役」也能开工（需求 #5/#6）
func peak_yield(peak_id: String, key: String) -> float:
	var v := team_eff(peak_id, key)            # 峰主 100% + 副手 50% + 杂役 5% 乘子
	for p in outer_of(peak_id):
		v += eff(p, key) * 0.2                  # 外门贡献 20%
	var men := int(s["peaks"][peak_id].get("menialOn", 0))
	v += men * MENIAL_BASE                      # 杂役基础劳动
	return v


## 杂役弟子随庇护人数+时间增长：target = 庇护/15 + 年/40，全局上限 1200
func _grow_menial() -> void:
	var target := int(float(s["protect"]) / 15.0) + int(float(s["year"]) / 40.0)
	target = mini(target, MENIAL_GLOBAL_CAP)
	if int(s["menial"]) < target:
		var grow := maxi(1, int((target - int(s["menial"])) / 3))
		s["menial"] = mini(target, int(s["menial"]) + grow)
	elif int(s["menial"]) > int(target * 1.5) and int(s["menial"]) > 0:
		s["menial"] = int(s["menial"]) - 1
	s["menial"] = mini(int(s["menial"]), MENIAL_GLOBAL_CAP)   # 硬上限，防止存档/迁移越界


## 每旬按各峰目标从全局杂役池分配在岗数（玄元峰/撰书阁不参与）
func _alloc_menial() -> void:
	var peaks: Dictionary = s["peaks"]
	var ids: Array = []
	var demand := 0
	for pid in peaks:
		if pid == "zhuanzhu":
			continue
		ids.append(pid)
		demand += int(peaks[pid].get("menial", 0))
	var pool := int(s["menial"])
	var scale := 1.0
	if demand > pool and demand > 0:
		scale = float(pool) / float(demand)
	for pid in ids:
		var want := mini(int(peaks[pid].get("menial", 0)), MENIAL_PEAK_CAP)
		peaks[pid]["menialOn"] = mini(int(floor(want * scale)), MENIAL_PEAK_CAP)


## 队伍总武力：峰主 + 副手 + 在岗外门弟子
func team_power(peak_id: String) -> float:
	var pk: Dictionary = s["peaks"][peak_id]
	var v := 0.0
	var lead := by_id(pk["leader"])
	if not lead.is_empty():
		v += atk_of(lead)
	for id in pk["deputy"]:
		var d := by_id(id)
		if not d.is_empty():
			v += atk_of(d)
	for p in outer_of(peak_id):
		v += atk_of(p)
	return v


func outer_of(peak_id: String) -> Array:
	var out: Array = []
	for p in alive_list():
		if p["peak"] == peak_id and not p["inner"]:
			out.append(p)
	return out


func inner_list() -> Array:
	var out: Array = []
	for p in alive_list():
		if p["inner"]:
			out.append(p)
	return out


func outer_list() -> Array:
	var out: Array = []
	for p in alive_list():
		if not p["inner"]:
			out.append(p)
	return out


func idle_list() -> Array:
	return _idle_list()


func realm_of_id(id) -> int:
	var p := by_id(id)
	return int(p["realm"]) if not p.is_empty() else 0


func fight_risk() -> float:
	var tgt: Dictionary = DataCore.FIGHT[int(s["fightTarget"])]
	var power := team_power("fumo")
	var atk := float(tgt.get("atk", pow(6.0, float(tgt["need"]))))
	if power <= 0.0:
		return 0.95
	# 除魔难度系数 0.4：队伍武力达到推荐 2.5 倍时胜率约 86%，
	# 比原公式更贴合"武力碾压则应高胜率"的直觉。
	var success := power / (power + atk * 0.4)
	return clampf(1.0 - success, 0.05, 0.95)


## 秘境失败风险（0.0~0.95）；成功率 = 1 - risk
func secret_risk(sec_atk: float, power: float) -> float:
	if power <= 0.0:
		return 0.95
	var success := power / (power + sec_atk * 0.6)
	return clampf(1.0 - success, 0.05, 0.95)


## 秘境失败受伤：随机一名参与人员减少最大寿元
func _secret_injury(peak_id: String) -> void:
	var pk: Dictionary = s["peaks"][peak_id]
	var pool: Array = []
	var lead := by_id(pk["leader"])
	if not lead.is_empty():
		pool.append(lead)
	for id in pk["deputy"]:
		var d := by_id(id)
		if not d.is_empty():
			pool.append(d)
	for p in outer_of(peak_id):
		pool.append(p)
	if pool.is_empty():
		return
	var victim: Dictionary = _pick(pool)
	var dmg := float(_ri(1, 5))
	victim["lifespanBonus"] = float(victim["lifespanBonus"]) - dmg
	push_log("%s在秘境探索中负伤，根基受损，寿元折损%d年。" % [victim["name"], int(dmg)], "bad")


# ═══════════════════════════════════════════════════════
# 开支
# ═══════════════════════════════════════════════════════

func expenses() -> void:
	# 受庇护民众的香火供奉
	s["stone"] = float(s["stone"]) + floor(float(s["protect"]) / 500.0)

	var cost := 0.0
	for p in alive_list():
		if p["inner"]:
			cost += floor(pow(2.2, float(p["realm"])) * 0.5)
		else:
			cost += 1.0
	cost += int(s["houseLv"]) * 2 + int(s["arrayLv"]) * 3
	s["stone"] = float(s["stone"]) - cost
	if float(s["stone"]) < 0.0:
		s["stone"] = 0.0


# ═══════════════════════════════════════════════════════
# 随机事件
# ═══════════════════════════════════════════════════════

func random_events() -> void:
	var list := alive_list()
	if list.is_empty():
		return
	if not _chance(0.28):
		return
	var p: Dictionary = _pick(list)

	# 气运之子更容易正面；魔修更容易堕魔；貌美/貌寝影响感情事件
	var lucky := false
	var love_k := 1.0
	for t in p["tags"]:
		var tag: Dictionary = DataCore.TAGS[int(t)]
		if tag.get("luck", 0):
			lucky = true
		if tag.has("love"):
			love_k *= float(tag["love"])
	var pool: Array = []
	for e in DataCore.EVENTS:
		var d: Dictionary = (e as Dictionary).duplicate()
		if lucky and d["kind"] == "good":
			d["w"] = float(d["w"]) * 3.0
		if (p["is_demon"] or p["is_modao"]) and d["kind"] == "demon":
			d["w"] = float(d["w"]) * 4.0
		if d["kind"] == "love":
			d["w"] = float(d["w"]) * love_k
		pool.append(d)

	apply_event(p, _weight(pool))


# 特质「被夺舍」的专属后续事件：体内老妖怪偶而夺舍反噬，偷袭同门。
# 每旬 0.5% 概率于每位带该特质的存活弟子身上触发；被偷袭同门寿命 -20。
func takeover_backlash() -> void:
	var hosts: Array = []
	for p in alive_list():
		for ti in p["tags"]:
			if DataCore.TAGS[int(ti)]["n"] == "被夺舍":
				hosts.append(p)
				break
	for h in hosts:
		if not _chance(0.005):
			continue
		# 被袭击者只能是「被夺舍」者同一个大境界（realm）及以下的角色
		var others: Array = []
		for p in alive_list():
			if int(p["id"]) != int(h["id"]) and int(p["realm"]) <= int(h["realm"]):
				others.append(p)
		if others.is_empty():
			break
		var victim: Dictionary = _pick(others)
		# 寿命 -20% 上限寿命（该境界基准寿元），文案显示具体年数
		var lose := int(float(DataCore.REALM_LIFESPAN[int(victim["realm"])]) * 0.2)
		victim["lifespanBonus"] = float(victim["lifespanBonus"]) - float(lose)
		victim["mood"] = maxf(0.0, float(victim["mood"]) - 15.0)
		h["mood"] = maxf(0.0, float(h["mood"]) - 10.0)
		push_log("%s体内老妖怪骤然夺舍反噬，性情大变、骤起偷袭同门%s！%s重伤垂危，寿命 -%d。" % [
			h["name"], victim["name"], victim["name"], lose], "bad")


# 堕魔者侵蚀宗门庇护：每旬每位堕魔弟子 1% 概率使宗门庇护人数下降 5%。
func demon_corrupt() -> void:
	var demons: Array = []
	for p in alive_list():
		if p["is_demon"]:
			demons.append(p)
	if demons.is_empty():
		return
	for d in demons:
		if not _chance(0.01):
			continue
		var before := float(s["protect"])
		var reduce := maxf(0.0, floor(before * 0.05))
		s["protect"] = maxf(0.0, before - reduce)
		push_log("宗门之中潜藏堕魔之人，丝丝缕缕的魔气悄然弥散，蔓延至山下凡尘，百姓心生惊惧，部分民众离开宗门庇护范围。", "bad")


func apply_event(p: Dictionary, ev: Dictionary) -> void:
	var t: String = str(ev["t"])
	t = t.replace("{n}", str(p["name"]))
	t = t.replace("{m}", rand_name(1 - int(p["sex"])))

	var kind := str(ev["kind"])
	var cls := ""
	if kind == "good":
		cls = "good"
	elif kind == "bad":
		cls = "bad"

	# 路线 B：带 eff 字段的事件走结构化施加，不再进入下面的字面匹配分支
	if ev.has("eff"):
		var sub := {
			"q": fmt_num(qi_max(p) * 0.3),
			"a": fmt_num(atk_of(p) * 0.1),
			"p": str(_ri(20, 200)),
		}
		_apply_eff(p, ev["eff"] as Array, sub)
		for k in sub.keys():
			t = t.replace("{" + k + "}", str(sub[k]))
		push_log(t, cls)
		return

	# 路线 A：无 eff 的事件按文案子串匹配，并提前算出具体数值填入文案
	var actuals := {}
	if t.contains("修为 +"):
		actuals["q"] = qi_max(p) * 0.3
	if t.contains("修为 -"):
		actuals["q"] = qi_max(p) * 0.2
	if t.contains("灵石 +"):
		actuals["s"] = _ri(500, 5000) * (1 + int(p["realm"]) * 2)
	if t.contains("灵石 -"):
		actuals["s"] = _ri(500, 5000)
	if t.contains("庇护人数"):
		actuals["p"] = _ri(20, 200)
	if t.contains("武力 +"):
		actuals["a"] = atk_of(p) * 0.1

	# 兜底：若文案里还有未替换的占位符，用默认值补上
	if t.contains("{q}"):
		actuals["q"] = actuals.get("q", qi_max(p) * 0.3)
	if t.contains("{s}"):
		actuals["s"] = actuals.get("s", _ri(500, 5000) * (1 + int(p["realm"]) * 2))
	if t.contains("{p}"):
		actuals["p"] = actuals.get("p", _ri(20, 200))
	if t.contains("{a}"):
		actuals["a"] = actuals.get("a", atk_of(p) * 0.1)
	for k in actuals.keys():
		var rep := fmt_num(actuals[k]) if k != "p" else str(actuals[k])
		t = t.replace("{" + k + "}", rep)

	if kind == "good":
		p["mood"] = minf(100.0, float(p["mood"]) + 10.0)
		if t.contains("+2%"):
			p["qiRateB"] = float(p["qiRateB"]) + 0.02
		if t.contains("+3%"):
			p["qiRateB"] = float(p["qiRateB"]) + 0.03
		if t.contains("+10%"):
			p["atkBonus"] = float(p["atkBonus"]) + 0.10
		if t.contains("+20%"):
			p["qiRateB"] = float(p["qiRateB"]) + 0.20
		if t.contains("修为 +"):
			p["qi"] = float(p["qi"]) + actuals.get("q", qi_max(p) * 0.3)
		if t.contains("武力 +"):
			p["atkBonus"] = float(p["atkBonus"]) + 0.10
		if t.contains("灵石 +"):
			s["stone"] = float(s["stone"]) + actuals.get("s", _ri(500, 5000) * (1 + int(p["realm"]) * 2))
		if t.contains("丹药 +"):
			var k := _eff_pill(1, _item_cap(int(p["realm"])))
			if k >= 0 and k < DataCore.PILLS.size():
				t = t.replace("{l}", str(DataCore.PILLS[k]["n"]))   # 按境界约束品阶并回填文案
		if t.contains("庇护人数"):
			s["protect"] = float(s["protect"]) + float(actuals.get("p", _ri(20, 200)))
		if t.contains("突破几率 +"):
			p["brkBonus"] = float(p["brkBonus"]) + 0.05
		if t.contains("寿元 +"):
			p["lifespanBonus"] = float(p["lifespanBonus"]) + 30.0
	elif kind == "bad":
		p["mood"] = maxf(0.0, float(p["mood"]) - 10.0)
		if t.contains("修为 -"):
			p["qi"] = maxf(0.0, float(p["qi"]) - actuals.get("q", qi_max(p) * 0.2))
		if t.contains("寿元 -"):
			p["lifespanBonus"] = float(p["lifespanBonus"]) - 20.0
		if t.contains("灵石 -"):
			s["stone"] = maxf(0.0, float(s["stone"]) - actuals.get("s", _ri(500, 5000)))
		if t.contains("突破几率 -"):
			p["brkBonus"] = float(p["brkBonus"]) - 0.03
		if t.contains("心情 -"):
			p["mood"] = maxf(0.0, float(p["mood"]) - 20.0)
		if t.contains("法宝损坏"):
			for i in 5:
				if p["equip"][i] != null:
					p["equip"][i] = null
					break
	elif kind == "love":
		if t.contains("结为了道侣"):
			for x in alive_list():
				if x["id"] != p["id"] and x["spouse"] == null and int(x["sex"]) != int(p["sex"]):
					p["spouse"] = x["id"]
					x["spouse"] = p["id"]
					p["brkBonus"] = float(p["brkBonus"]) + 0.10
					x["brkBonus"] = float(x["brkBonus"]) + 0.10
					break
		p["mood"] = minf(100.0, float(p["mood"]) + 15.0)
	elif kind == "demon":
		p["is_demon"] = true
		p["mood"] = 20.0
		p["brkBonus"] = float(p["brkBonus"]) - 0.05

	push_log(t, cls)


# ═══════════════════════════════════════════════════════
# 结构化效果施加（带 eff 字段的事件）
# 约定：eff 模式「完全接管」—— 不再附加任何通用心情，
#       文案里写的即为实际发生的，做到文案与效果一一对应
# ═══════════════════════════════════════════════════════

func _apply_eff(p: Dictionary, eff: Array, sub: Dictionary = {}) -> void:
	for item in eff:
		var pair: Array = item
		var key := str(pair[0])
		var v := 0.0
		if pair.size() > 1:
			v = float(pair[1])
		match key:
			"qiRate":
				p["qiRateB"] = float(p["qiRateB"]) + v
			"atk":
				p["atkBonus"] = float(p["atkBonus"]) + v
			"brk":
				p["brkBonus"] = float(p["brkBonus"]) + v
			"qi":
				p["qi"] = maxf(0.0, float(p["qi"]) + qi_max(p) * v)
			"mood":
				p["mood"] = clampf(float(p["mood"]) + v, 0.0, 100.0)
			"stone":
				if v > 0.0:
					var st_amt := _ri(500, 5000) * (1 + int(p["realm"]) * 2)
					s["stone"] = float(s["stone"]) + st_amt
					sub["s"] = fmt_num(st_amt)
				else:
					var st_amt2 := _ri(500, 5000)
					s["stone"] = maxf(0.0, float(s["stone"]) - st_amt2)
					sub["s"] = fmt_num(st_amt2)
			"pill":
				var pk := _eff_pill(int(v), _item_cap(int(p["realm"])))
				if pk >= 0 and pk < DataCore.PILLS.size():
					sub["l"] = str(DataCore.PILLS[pk]["n"])
			"herb":
				var hi := _eff_res(s["herbs"], int(v), _item_cap(int(p["realm"])))
				if hi >= 0:
					var names: Array = DataCore.HERBS[hi]
					sub["h"] = str(names[_ri(0, names.size() - 1)])
			"ore":
				var oi := _eff_res(s["ores"], int(v), _item_cap(int(p["realm"])))
				if oi >= 0:
					var names2: Array = DataCore.ORES[oi]
					sub["o"] = str(names2[_ri(0, names2.size() - 1)])
			"equips":
				for _k in int(v):
					s["equips"].append(make_equip(mini(7, maxi(1, 1 + int(p["realm"]) / 2))))
			"marry":
				_eff_marry(p)
			_:
				push_log("（未知效果键：%s）" % key, "hint")


## 事件获得物品时，按获得者境界约束最高品阶：realm+1（略放宽体现机缘），封顶 9
func _item_cap(realm: int) -> int:
	return mini(9, int(realm) + 1)


## 随机增减一味丹药；扣减时只在有存量的丹药里挑，避免空扣。
## 获得(delta>0)时只在「品阶 ≤ cap」的丹药里挑，避免低境界弟子获得高阶丹（如筑基得合道丹）。
## 失去(delta<0)时优先挑「品阶 ≤ cap」的已有丹药；若没有则退而任取已有（避免文案占位符泄漏）。
## 返回实际操作的 pill key（未操作返回 -1）
func _eff_pill(delta: int, cap: int = 9) -> int:
	if delta == 0:
		return -1
	if delta < 0:
		var owned: Array = []
		for key in s["pills"].keys():
			if int(s["pills"][key]) > 0 and int(DataCore.PILLS[key]["lv"]) <= cap:
				owned.append(int(key))
		if owned.is_empty():   # 没有符合境界的低阶丹可失，退而求其次任取已有
			for key in s["pills"].keys():
				if int(s["pills"][key]) > 0:
					owned.append(int(key))
		if owned.is_empty():
			return -1
		var k := int(owned[_ri(0, owned.size() - 1)])
		s["pills"][k] = maxi(0, int(s["pills"].get(k, 0)) + delta)
		return k
	# 获得：只在品阶 ≤ cap 的丹药里挑
	var cand: Array = []
	for i in DataCore.PILLS.size():
		if int(DataCore.PILLS[i]["lv"]) <= cap:
			cand.append(i)
	if cand.is_empty():
		cand.append(1)   # 兜底：筑基丹
	var k := int(cand[_ri(0, cand.size() - 1)])
	s["pills"][k] = maxi(0, int(s["pills"].get(k, 0)) + delta)
	return k


## 随机增减一种灵草 / 矿石；扣减时只在有存量的品类里挑。
## 获得(delta>0)时只在「品阶 ≤ cap」里挑，避免低境界弟子获得高阶物（如筑基得无妄道树）。
## 失去(delta<0)时优先挑「品阶 ≤ cap」的已有品类；没有则退而任取已有。
## 返回实际操作的 index（未操作返回 -1）
func _eff_res(arr: Array, delta: int, cap: int = 9) -> int:
	if delta == 0 or arr.is_empty():
		return -1
	if delta < 0:
		var owned: Array = []
		for i in arr.size():
			if int(arr[i]) > 0 and i <= cap:
				owned.append(i)
		if owned.is_empty():
			for i in arr.size():
				if int(arr[i]) > 0:
					owned.append(i)
		if owned.is_empty():
			return -1
		var idx := int(owned[_ri(0, owned.size() - 1)])
		arr[idx] = maxi(0, int(arr[idx]) + delta)
		return idx
	# 获得：品阶 ≤ cap
	var idx := _ri(0, mini(cap, arr.size() - 1))
	arr[idx] = maxi(0, int(arr[idx]) + delta)
	return idx


## 结为道侣（与字面匹配分支里「结为了道侣」的逻辑保持一致）
func _eff_marry(p: Dictionary) -> void:
	for x in alive_list():
		if x["id"] != p["id"] and x["spouse"] == null and int(x["sex"]) != int(p["sex"]):
			p["spouse"] = x["id"]
			x["spouse"] = p["id"]
			p["brkBonus"] = float(p["brkBonus"]) + 0.10
			x["brkBonus"] = float(x["brkBonus"]) + 0.10
			break


## 大比候选：武力最高的外门弟子
func _champion_cand() -> Dictionary:
	var cands: Array = []
	for p in alive_list():
		if not p["inner"]:
			cands.append(p)
	if cands.is_empty():
		return {}
	cands.sort_custom(func(a, b): return atk_of(a) > atk_of(b))
	return cands[0]


## 生成 3 件候选法宝供玩家挑选（对齐原 APK「选择大比奖品」）
func _champion_prizes() -> Array:
	var out: Array = []
	for i in 3:
		out.append(make_equip(_ri(1, 7)))
	return out


## 落实大比结果：提拔内门 + 心境 + 灵石 + 赐法宝
func _apply_champion(cand: Dictionary, prizes: Array, idx: int) -> void:
	var was_inner := bool(cand["inner"])
	cand["inner"] = true
	# 原为外门者：脱离原 XX 峰外门岗位，归入玄元峰内门
	if not was_inner and cand["peak"] != null:
		cand["peak"] = null
	cand["mood"] = minf(100.0, float(cand["mood"]) + 30.0)
	s["stone"] = float(s["stone"]) + 2000.0
	var e: Dictionary
	if not prizes.is_empty() and idx >= 0 and idx < prizes.size():
		e = prizes[idx]
	else:
		e = prizes[0] if not prizes.is_empty() else make_equip(mini(7, _ri(1, 4)))
	var ei: int = (s["equips"] as Array).size()
	s["equips"].append(e)
	# 直接为胜者穿戴（若槽位已有则退换仓库）
	equip_to(int(cand["id"]), ei)
	push_log("宗门大比，%s脱颖而出，拜入内门，获赐%s%s。" % [
		cand["name"], DataCore.MLEVEL[int(e["lv"])], e["name"]], "good")
	s["championLeft"] = 36 * 5 + _ri(0, 36)


## UI 选定奖品后调用，结算大比并清除挂起态
func resolve_champion(idx: int) -> void:
	var pc: Dictionary = s.get("pending_champion", {})
	if pc.is_empty():
		return
	var cand: Dictionary = by_id(int(pc.get("id", -1)))
	if cand.is_empty() or not cand["alive"]:
		push_log("宗门大比，胜者已离宗门，本届作罢。", "hint")
	else:
		_apply_champion(cand, pc.get("prizes", []), idx)
	s["pending_champion"] = {}
	emit_signal("changed")


## 大比（headless/自动结算入口）：无候选则本届空手
func champion() -> void:
	var cand := _champion_cand()
	if cand.is_empty():
		push_log("本届门派大比，未能选拔出杰出弟子。", "hint")
		s["championLeft"] = 36 * 5 + _ri(0, 36)
		return
	_apply_champion(cand, _champion_prizes(), -1)


# ═══════════════════════════════════════════════════════
# 玩家操作
# ═══════════════════════════════════════════════════════

func assign(p: Dictionary, peak_id, as_leader: bool, as_deputy: bool) -> void:
	unassign(p)
	if peak_id == null:
		emit_signal("changed")
		return
	var pk: Dictionary = s["peaks"][peak_id]
	var p2 := by_id(p["id"])
	if p2.is_empty():
		return
	if as_leader:
		if p2["is_demon"]:
			push_log("%s已堕为魔修，不可再担任峰主。" % p2["name"], "hint")
			emit_signal("changed")
			return
		if pk["leader"] != null and pk["leader"] != p["id"]:
			var old := by_id(pk["leader"])
			if not old.is_empty():
				unassign(old)
		pk["leader"] = p["id"]
		# 掌门兼任时保留掌门身份，不改为峰职头衔
		if p2["job"] != "leader":
			p2["job"] = _leader_job_title(str(peak_id))
		p2["peak"] = peak_id
		p2["inner"] = true
	elif as_deputy:
		if (pk["deputy"] as Array).size() >= 4:
			push_log("%s副手已达上限（4人），无法继续任命。" % DataCore.peak_by_id(peak_id).get("n", peak_id), "hint")
			emit_signal("changed")
			return
		(pk["deputy"] as Array).append(p["id"])
		if p2["job"] != "leader":
			p2["job"] = "fushou"
		p2["peak"] = peak_id
		p2["inner"] = true
	else:
		# 外门岗位：内门弟子与掌门不得担任
		if p2["inner"]:
			push_log("%s已是内门弟子，无法调往外门岗位。" % p2["name"], "hint")
			emit_signal("changed")
			return
		if p2["job"] == "leader":
			push_log("掌门不能调往外门岗位。", "hint")
			emit_signal("changed")
			return
		p2["peak"] = peak_id
		p2["inner"] = false
		if p2["job"] != "leader":
			p2["job"] = null
	emit_signal("changed")


func _leader_job_title(peak_id: String) -> String:
	# 各峰负责人统一称为「峰主」
	return "fengzhu"


func unassign(p: Dictionary) -> void:
	for k in s["peaks"]:
		var pk: Dictionary = s["peaks"][k]
		if pk["leader"] == p["id"]:
			pk["leader"] = null
		pk["deputy"] = (pk["deputy"] as Array).filter(func(id): return id != p["id"])
		if pk["writer"] == p["id"]:
			pk["writer"] = null
	if p["job"] != "leader":
		p["job"] = null
	p["peak"] = null
	emit_signal("changed")


func auto_assign() -> void:
	var has := false
	for p in s["people"]:
		if p["alive"] and not p["fly"] and p["job"] == "leader":
			has = true
			break
	if has:
		return
	var c := alive_list()
	if c.is_empty():
		return
	c.sort_custom(func(a, b): return (int(a["realm"]) * 10 + int(a["sub"])) > (int(b["realm"]) * 10 + int(b["sub"])))
	c[0]["job"] = "leader"
	push_log("%s被推举为新任掌门。" % c[0]["name"], "hint")


func set_leader(id) -> void:
	for p in s["people"]:
		if p["job"] == "leader":
			p["job"] = null
	var p := by_id(id)
	if not p.is_empty():
		p["job"] = "leader"
		p["inner"] = true
		push_log("%s继任掌门。" % p["name"], "hint")
	emit_signal("changed")


## 建立/解除师徒关系（双向维护 apprentices / master）。mid=null 表示解除。
func set_master(did: int, mid) -> void:
	var d := by_id(did)
	if d.is_empty():
		return
	# 先解除旧师尊
	if d["master"] != null:
		var oldm := by_id(d["master"])
		if not oldm.is_empty():
			oldm["apprentices"] = (oldm["apprentices"] as Array).filter(func(x): return int(x) != int(did))
		d["master"] = null
	if mid != null:
		var m := by_id(mid)
		if not m.is_empty() and int(m["id"]) != int(did):
			d["master"] = int(mid)
			if not (m["apprentices"] as Array).has(int(did)):
				m["apprentices"].append(int(did))
			push_log("%s拜入%s门下为徒。" % [d["name"], m["name"]], "hint")
	emit_signal("changed")


func use_pill(idx: int, person_id) -> void:
	if int(s["pills"].get(idx, 0)) <= 0:
		return
	var pill: Dictionary = DataCore.PILLS[idx]
	var p := by_id(person_id)
	if p.is_empty():
		return
	if pill.get("heal", false):
		p["hpRestore"] = true
		push_log("%s服下%s，略作调息。" % [p["name"], pill["n"]], "")
	elif pill.get("wash", false):
		if (p["elements"] as Array).size() <= 1:
			push_log("%s是单灵根，无法洗髓。" % p["name"], "hint")
			return
		(p["elements"] as Array).pop_back()
		p["linggenIdx"] = maxi(0, int(p["linggenIdx"]) - 1)
		push_log("%s服下洗髓丹，洗去末位灵根，灵根晋升为%s。" % [
			p["name"], DataCore.LINGGEN[int(p["linggenIdx"])]["n"]], "good")
	else:
		p["brkBonus"] = float(p["brkBonus"]) + float(pill["brk"])
		push_log("%s服下%s，突破几率提升。" % [p["name"], pill["n"]], "good")
	s["pills"][idx] = int(s["pills"][idx]) - 1
	if int(s["pills"][idx]) <= 0:
		s["pills"].erase(idx)
	emit_signal("changed")


func revive(id, type: int) -> void:
	var p := by_id(id)
	if p.is_empty():
		return
	if type == 0:   # 九转还魂丹
		p["alive"] = true
		p["fly"] = false
		p["dormant"] = false
		p["lifespanBonus"] = float(p["lifespanBonus"]) + floor(float(DataCore.REALM_LIFESPAN[int(p["realm"])]) * 0.3)
		push_log("%s服下九转还魂丹，自鬼门关折返。" % p["name"], "good")
	else:
		p["dormant"] = false
		p["alive"] = true
		p["lifespanBonus"] = float(p["lifespanBonus"]) + float(DataCore.REALM_LIFESPAN[int(p["realm"])])
		push_log("%s服下仙灵延寿丹，续得寿元。" % p["name"], "good")
	p["qi"] = 0.0
	emit_signal("changed")


func equip_to(person_id, ei: int) -> void:
	var p := by_id(person_id)
	if p.is_empty():
		return
	if ei < 0 or ei >= (s["equips"] as Array).size():
		return
	var e: Dictionary = s["equips"][ei]
	var slot := int(e["slot"])
	var old = p["equip"][slot]
	p["equip"][slot] = e
	(s["equips"] as Array).remove_at(ei)
	if old != null:
		s["equips"].append(old)
	emit_signal("changed")


func unequip(person_id, slot: int) -> void:
	var p := by_id(person_id)
	if p.is_empty() or p["equip"][slot] == null:
		return
	s["equips"].append(p["equip"][slot])
	p["equip"][slot] = null
	emit_signal("changed")


func upgrade_gongde(i: int) -> bool:
	var cost := (int(s["gongde"][i]) + 1) * 10
	if float(s["merit"]) < cost:
		return false
	s["merit"] = float(s["merit"]) - cost
	s["gongde"][i] = int(s["gongde"][i]) + 1
	push_log("%s升至%d级。" % [DataCore.GONGDE[i]["n"], int(s["gongde"][i])], "good")
	emit_signal("changed")
	return true


func upgrade_house() -> bool:
	var cost := int(s["houseLv"]) * 800
	if float(s["stone"]) < cost:
		return false
	s["stone"] = float(s["stone"]) - cost
	s["houseLv"] = int(s["houseLv"]) + 1
	push_log("屋舍升至%d级，门徒上限提升。" % int(s["houseLv"]), "good")
	emit_signal("changed")
	return true


func upgrade_array() -> bool:
	var cost := int(s["arrayLv"]) * 1200
	if float(s["stone"]) < cost:
		return false
	s["stone"] = float(s["stone"]) - cost
	s["arrayLv"] = int(s["arrayLv"]) + 1
	push_log("护山大阵升至%d级" % int(s["arrayLv"]), "good")
	emit_signal("changed")
	return true


func sell_herb(lv: int) -> void:
	if int(s["herbs"][lv]) <= 0:
		return
	var price := int(floor((lv + 1) * 12 * (1.0 + float(s["gongde"][9]) * 0.06)))
	s["stone"] = float(s["stone"]) + price
	s["herbs"][lv] = int(s["herbs"][lv]) - 1
	emit_signal("changed")


func sell_ore(lv: int) -> void:
	if int(s["ores"][lv]) <= 0:
		return
	var price := int(floor((lv + 1) * 15 * (1.0 + float(s["gongde"][9]) * 0.06)))
	s["stone"] = float(s["stone"]) + price
	s["ores"][lv] = int(s["ores"][lv]) - 1
	emit_signal("changed")


## 结算轮回/重开宗门可获得的功德
func calc_reincarnate_merit() -> int:
	return int(floor(sqrt(float(s["protect"])) / 2.0)) + int(floor(int(s["tick"]) / 200.0))


## 轮回
func reincarnate() -> void:
	var gain := calc_reincarnate_merit()
	# 原版 reincarnate 不推进 cycle，"第 N 轮回" 标签会永远停在第 1 —— 此处修正
	s["cycle"] = int(s["cycle"]) + 1
	push_log("进入新的轮回，天道感念宗门庇护民众%s人，结算功德 +%d。" % [fmt_num(s["protect"]), gain], "good")
	s["merit"] = float(s["merit"]) + gain
	s["protect"] = 0.0
	s["year"] = 1
	s["month"] = 1
	s["xun"] = 1
	s["tick"] = 0
	s["stone"] = 3000.0
	s["herbs"] = _fill_i(10, 0)
	s["ores"] = _fill_i(10, 0)
	s["pills"] = {}
	s["equips"] = []
	s["books"] = []
	s["houseLv"] = 1
	s["arrayLv"] = 1
	for pkd in DataCore.PEAKS:
		s["peaks"][pkd["id"]] = _new_peak_state()

	# 只留掌门，其余重新生成
	var lead := {}
	for p in s["people"]:
		if p["alive"] and not p["fly"] and p["job"] == "leader":
			lead = p
			break
	s["people"] = [lead] if not lead.is_empty() else []
	if not lead.is_empty():
		lead["realm"] = 0
		lead["sub"] = 0
		lead["qi"] = 0.0
		lead["age"] = 20
		lead["spouse"] = null
		lead["is_demon"] = false
		lead["demon"] = 0.0
		lead["demonDone"] = false
		lead["mood"] = 70.0
		lead["qiRateB"] = 0.0
		lead["atkBonus"] = 1.0
		lead["brkBonus"] = 0.0
		lead["equip"] = [null, null, null, null, null]
		lead["peak"] = null
	else:
		var nm := make_person({"age": 20})
		nm["job"] = "leader"
		nm["inner"] = true
		s["people"].append(nm)
	for i in 3:
		add_disciple(true)
	auto_assign()
	emit_signal("changed")


func push_log(text: String, cls: String = "") -> void:
	var xun_label: String = ["上", "中", "下"][int(s["xun"]) - 1]
	s["log"].append({
		"t": text, "c": cls,
		"d": "%d年%d月%s旬" % [int(s["year"]), int(s["month"]), xun_label],
	})
	if (s["log"] as Array).size() > 400:
		(s["log"] as Array).pop_front()


# ═══════════════════════════════════════════════════════
# 速度 / 存档
# ═══════════════════════════════════════════════════════

func speed_ms() -> int:
	var i := clampi(int(s.get("speed", 1)), 0, DataCore.SPEED.size() - 1)
	return int(DataCore.SPEED[i]["ms"])


func set_speed(i: int) -> void:
	s["speed"] = clampi(i, 0, DataCore.SPEED.size() - 1)
	emit_signal("changed")


func save() -> bool:
	if s.is_empty():
		return false
	var f := FileAccess.open(DataCore.SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(s))
	f.close()
	return true


func has_save() -> bool:
	return FileAccess.file_exists(DataCore.SAVE_PATH)


func load_save() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(DataCore.SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return false
	s = normalize_state(parsed)
	emit_signal("changed")
	return true


func clear_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DataCore.SAVE_PATH))


## JSON 往返会把所有数字变成 float，也会丢掉 null 语义；这里统一校准类型。
func normalize_state(raw: Dictionary) -> Dictionary:
	var st := raw
	st["year"] = int(st.get("year", 1))
	st["month"] = int(st.get("month", 1))
	st["xun"] = int(st.get("xun", 1))
	st["tick"] = int(st.get("tick", 0))
	st["speed"] = int(st.get("speed", 1))
	st["stone"] = float(st.get("stone", 0.0))
	st["protect"] = float(st.get("protect", 0.0))
	st["menial"] = int(st.get("menial", 0))   # 杂役总数
	st["merit"] = float(st.get("merit", 0.0))
	st["cycle"] = int(st.get("cycle", 1))
	st["houseLv"] = int(st.get("houseLv", 1))
	st["arrayLv"] = int(st.get("arrayLv", 1))
	st["nextId"] = int(st.get("nextId", 1))
	st["tianti"] = int(st.get("tianti", 0))
	st["championLeft"] = int(st.get("championLeft", 1))
	st["pending_champion"] = st.get("pending_champion", {})
	st["fightTarget"] = int(st.get("fightTarget", 0))

	var herbs: Array = []
	for v in st.get("herbs", []):
		herbs.append(int(v))
	while herbs.size() < 10:
		herbs.append(0)
	st["herbs"] = herbs
	var ores: Array = []
	for v in st.get("ores", []):
		ores.append(int(v))
	while ores.size() < 10:
		ores.append(0)
	st["ores"] = ores

	var gongde: Array = []
	for v in st.get("gongde", []):
		gongde.append(int(v))
	st["gongde"] = gongde

	var pills := {}
	for k in st.get("pills", {}):
		pills[int(k)] = int(st["pills"][k])
	st["pills"] = pills

	# 法宝
	var equips: Array = []
	for e in st.get("equips", []):
		equips.append(_normalize_equip(e))
	st["equips"] = equips

	# 七峰（含寻幽峰）
	var peaks := {}
	for pkd in DataCore.PEAKS:
		var pid: String = pkd["id"]
		var src: Dictionary = st.get("peaks", {}).get(pid, {})
		var npk := _new_peak_state()
		npk["leader"] = _nz_int(src.get("leader", null))
		npk["writer"] = _nz_int(src.get("writer", null))
		var dep: Array = []
		for d in src.get("deputy", []):
			dep.append(int(d))
		npk["deputy"] = dep
		npk["outer"] = int(src.get("outer", 0))
		npk["secret"] = int(src.get("secret", 0))
		npk["progress"] = float(src.get("progress", 0.0))
		npk["pill"] = int(src.get("pill", 1))
		npk["equipLv"] = int(src.get("equipLv", 0))
		npk["herbLv"] = int(src.get("herbLv", 0))
		npk["oreLv"] = int(src.get("oreLv", 0))
		npk["writeProgress"] = float(src.get("writeProgress", 0.0))
		npk["herbAcc"] = int(src.get("herbAcc", 0))
		npk["menial"] = int(src.get("menial", 0))
		npk["menialOn"] = int(src.get("menialOn", 0))
		peaks[pid] = npk
	st["peaks"] = peaks

	# 旧存档迁移：镇邪峰承担的秘境探索拆分到寻幽峰
	var fumo_st: Dictionary = st["peaks"]["fumo"]
	var xunyou_st: Dictionary = st["peaks"]["xunyou"]
	if int(xunyou_st["secret"]) == 0 and float(xunyou_st["progress"]) <= 0.0:
		if int(fumo_st["secret"]) != 0 or float(fumo_st["progress"]) > 0.0:
			xunyou_st["secret"] = int(fumo_st["secret"])
			xunyou_st["progress"] = float(fumo_st["progress"])
			fumo_st["secret"] = 0
			fumo_st["progress"] = 0.0

	# 弟子
	var people: Array = []
	for p in st.get("people", []):
		people.append(_normalize_person(p))
	st["people"] = people

	var logs: Array = []
	for l in st.get("log", []):
		logs.append({"t": str(l.get("t", "")), "c": str(l.get("c", "")), "d": str(l.get("d", ""))})
	st["log"] = logs

	return st


func _nz_int(v):
	if v == null:
		return null
	return int(v)


func _normalize_equip(e) -> Dictionary:
	if not (e is Dictionary):
		return {}
	var attrs := {}
	for k in e.get("attrs", {}):
		attrs[k] = float(e["attrs"][k])
	return {
		"name": str(e.get("name", "")), "slot": int(e.get("slot", 0)),
		"lv": int(e.get("lv", 0)), "attrs": attrs,
		"spirit": bool(e.get("spirit", false)),
	}


func _normalize_person(p: Dictionary) -> Dictionary:
	var out := p
	out["id"] = int(p.get("id", 0))
	out["sex"] = int(p.get("sex", 0))
	out["linggenIdx"] = clampi(int(p.get("linggenIdx", 7)), 0, DataCore.LINGGEN.size() - 1)
	out["famiIdx"] = clampi(int(p.get("famiIdx", 1)), 0, DataCore.FAMI.size() - 1)
	out["age"] = int(p.get("age", 20))
	out["realm"] = clampi(int(p.get("realm", 0)), 0, 9)
	out["sub"] = clampi(int(p.get("sub", 0)), 0, 9)
	out["qi"] = float(p.get("qi", 0.0))
	out["mood"] = float(p.get("mood", 60.0))
	out["atkBonus"] = float(p.get("atkBonus", 1.0))
	out["qiRateB"] = float(p.get("qiRateB", 0.0))
	out["brkBonus"] = float(p.get("brkBonus", 0.0))
	out["lifespanBonus"] = float(p.get("lifespanBonus", 0.0))
	out["demon"] = float(p.get("demon", 0.0))
	out["is_demon"] = bool(p.get("is_demon", false))
	out["demonDone"] = bool(p.get("demonDone", false))
	out["is_modao"] = bool(p.get("is_modao", false))
	out["alive"] = bool(p.get("alive", true))
	out["fly"] = bool(p.get("fly", false))
	out["dormant"] = bool(p.get("dormant", false))
	out["inner"] = bool(p.get("inner", false))
	out["rebirth"] = bool(p.get("rebirth", false))
	out["job"] = p.get("job", null)
	out["peak"] = p.get("peak", null)
	out["master"] = _nz_int(p.get("master", null))
	out["spouse"] = _nz_int(p.get("spouse", null))
	out["hpRestore"] = bool(p.get("hpRestore", false))

	var els: Array = []
	for e in p.get("elements", []):
		els.append(str(e))
	out["elements"] = els

	var tags: Array = []
	for t in p.get("tags", []):
		tags.append(int(t))
	out["tags"] = tags

	var eq: Array = []
	var eqs: Array = p.get("equip", [])
	for i in 5:
		if i < eqs.size() and eqs[i] != null and eqs[i] is Dictionary and not (eqs[i] as Dictionary).is_empty():
			eq.append(_normalize_equip(eqs[i]))
		else:
			eq.append(null)
	out["equip"] = eq

	var parents: Array = []
	for x in p.get("parents", []):
		parents.append(int(x))
	out["parents"] = parents

	var apps: Array = []
	for x in p.get("apprentices", []):
		apps.append(int(x))
	out["apprentices"] = apps

	if not out.has("lifespan"):
		out["lifespan"] = DataCore.REALM_LIFESPAN[0]
	return out
