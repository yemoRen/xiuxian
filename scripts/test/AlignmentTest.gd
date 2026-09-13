extends SceneTree

## 文案对齐验证：证明「改文案」没有改变任何实际效果。
##
## 事件效果是靠对渲染后的文案做子串匹配施加的（t.contains("武力 +") 之类），
## 所以改文案有静默改变效果的风险。本测试对每条被改的事件：
##   同一份初始状态快照 + 同一个随机种子，分别用旧文案与新文案调用 apply_event，
##   逐项比对 qi / mood / atkBonus / brkBonus / qiRateB / lifespanBonus /
##   stone / protect / pills / equip / 派生 atk 等状态增量是否完全一致。
##
## 运行：godot --headless --path <工程> --script res://scripts/test/AlignmentTest.gd

var _pass := 0
var _fail := 0
var _failures: Array = []

var _seed := 1

const SEED_LIST := [1, 42, 20260912, 987654321, 123456789]

# 与 GameCore.apply_event 内的匹配规则严格一致
const GOOD_TOKENS := ["+2%", "+3%", "+10%", "+20%", "修为 +", "武力 +",
	"灵石 +", "丹药 +", "庇护人数", "突破几率 +", "寿元 +"]
const BAD_TOKENS := ["修为 -", "寿元 -", "灵石 -", "突破几率 -", "心情 -", "法宝损坏"]
const LOVE_TOKENS := ["结为了道侣"]

const CASES: Array = [
	{"label": "斩一恶蛟", "kind": "good",
		"old": "{n}斩一恶蛟，取其筋为束带。武力 +一成（即 10%）",
		"new": "{n}斩一恶蛟，取其筋为束带。武力 +一成"},
	{"label": "误入前人洞府", "kind": "good",
		"old": "{n}误入前人洞府，得遗泽若干。灵石 +一笔（数目随缘）",
		"new": "{n}误入前人洞府，得遗泽若干。灵石 +{s}"},
	{"label": "点化散修", "kind": "good",
		"old": "{n}于市集以三言两语点化一散修，对方感激之余赠以灵药。丹药 +1（随机一味）",
		"new": "{n}于市集以三言两语点化一散修，对方感激之余赠以灵药。丹药 +1（{l}）"},
	{"label": "与剑修论剑", "kind": "good",
		"old": "{n}与路过剑修论剑三日，剑意大进。武力 +10%",
		"new": "{n}与路过剑修论剑三日，剑意大进。武力 +10%，剑意圆满再进 +10%"},
	{"label": "收灵兽为伴", "kind": "good",
		"old": "{n}收一灵兽为伴，日夜相伴不寂寞。心情 +20",
		"new": "{n}收一灵兽为伴，日夜相伴不寂寞。心情 +10"},
	{"label": "外出游历结怨", "kind": "bad",
		"old": "{n}外出游历时与人结怨，被追杀三百里。武力 -{a}",
		"new": "{n}外出游历时与人结怨，被追杀三百里，所幸最终脱身。"},
	{"label": "修炼岔了气息", "kind": "bad",
		"old": "{n}修炼时岔了气息，卧床半月。修为 -20%（按上限计）",
		"new": "{n}修炼时岔了气息，卧床半月。修为 -20%"},
	{"label": "秘境争斗负伤", "kind": "bad",
		"old": "{n}在秘境中为一株灵草与人争斗，负伤而归。心情 -20",
		"new": "{n}在秘境中为一株灵草与人争斗，负伤而归。心情 -30"},
	{"label": "借贷购置法宝", "kind": "bad",
		"old": "{n}借贷购置法宝，如今债主上门。灵石 -500~5000",
		"new": "{n}借贷购置法宝，如今债主上门。灵石 -{s}"},
]


func _initialize() -> void:
	print("═══════════════════════════════════════════")
	print(" 修仙门派 · 事件文案对齐验证（改前 / 改后效果零变更）")
	print("═══════════════════════════════════════════")

	# 构造一份初始状态快照：修为不为 0（否则扣修为看不出差别）、灵石充足（避免 0 截断）
	var g := GameCore.new(1)
	g.new_game({"sectName": "测试宗", "name": "云中君", "sex": 0, "linggen": 0})
	var basep: Dictionary = g.s["people"][0]
	basep["qi"] = g.qi_max(basep) * 0.8
	g.s["stone"] = 500000.0
	var snapshot: Dictionary = g.s.duplicate(true)
	print("基准弟子：%s  修为 %.1f / 上限 %.1f  灵石 %.0f" % [
		basep["name"], float(basep["qi"]), g.qi_max(basep), float(g.s["stone"])])
	print("种子集合：%s   （每种子下新旧文案各跑一次）" % str(SEED_LIST))
	print("───────────────────────────────────────────")

	var idx := 0
	for c in CASES:
		idx += 1
		var label: String = str(c["label"])
		var kind: String = str(c["kind"])
		var old_t: String = str(c["old"])
		var new_t: String = str(c["new"])

		print("\n[%d] %s · kind=%s" % [idx, label, kind])

		# 0) 源文件里确实已经换成了新文案
		var in_source := false
		for e in DataCore.EVENTS:
			if str((e as Dictionary)["t"]) == new_t:
				in_source = true
				break
		_ok(in_source, "%s：DataCore.EVENTS 已采用新文案" % label)
		var old_gone := true
		for e in DataCore.EVENTS:
			if str((e as Dictionary)["t"]) == old_t:
				old_gone = false
				break
		_ok(old_gone, "%s：旧文案已从 EVENTS 中移除" % label)

		# 1) 逐种子比对状态增量
		var all_same := true
		var changed := false
		var shown_old := ""
		var shown_new := ""
		var d_old: Dictionary = {}
		var d_new: Dictionary = {}
		var first := true
		for sd in SEED_LIST:
			_seed = int(sd)
			var ra: Dictionary = _apply_once(g, snapshot, kind, old_t)
			var rb: Dictionary = _apply_once(g, snapshot, kind, new_t)
			var same_seed: bool = (ra["after"] as Dictionary) == (rb["after"] as Dictionary)
			if not same_seed:
				all_same = false
				print("      ✗ 种子 %d 出现差异" % int(sd))
				_print_diff(ra["before"], ra["after"], rb["after"])
			if (ra["before"] as Dictionary) != (ra["after"] as Dictionary):
				changed = true
			if first:
				first = false
				shown_old = str(ra["rendered"])
				shown_new = str(rb["rendered"])
				d_old = _delta(ra["before"], ra["after"])
				d_new = _delta(rb["before"], rb["after"])

		_ok(all_same, "%s：%d 个种子下新旧效果完全一致" % [label, SEED_LIST.size()])
		_ok(changed, "%s：事件确实产生了状态变化（比对非空）" % label)

		var h_old: Array = _hits(shown_old, kind)
		var h_new: Array = _hits(shown_new, kind)
		_ok(h_old == h_new, "%s：命中的匹配关键字串一致" % label,
			"旧 %s ／ 新 %s" % [str(h_old), str(h_new)])

		print("      旧文案：%s" % shown_old)
		print("      新文案：%s" % shown_new)
		print("      命中规则：%s" % (str(h_old) if not h_old.is_empty() else "（无）"))
		print("      实际增量：%s" % (str(d_new) if not d_new.is_empty() else "（无）"))
		if d_old != d_new:
			print("      ✗ 增量不一致：旧 %s" % str(d_old))

	print("\n───────────────────────────────────────────")
	print(" 通过 %d / 失败 %d" % [_pass, _fail])
	if _fail > 0:
		for f in _failures:
			print("   ✗ ", f)
	print("ALIGN_%s" % ("PASS" if _fail == 0 else "FAIL"))
	print("═══════════════════════════════════════════")
	quit(1 if _fail > 0 else 0)


## 在指定种子下把某条文案施加到快照副本上，返回改前 / 改后状态与渲染后的文案
func _apply_once(g: GameCore, snap: Dictionary, kind: String, tpl: String) -> Dictionary:
	g.s = snap.duplicate(true)
	g.rng.seed = _seed
	var p: Dictionary = g.s["people"][0]
	var before := _metrics(p, g)
	g.apply_event(p, {"kind": kind, "t": tpl})
	var after := _metrics(p, g)
	var rendered := ""
	var lg: Array = g.s["log"]
	if not lg.is_empty():
		rendered = str((lg[lg.size() - 1] as Dictionary)["t"])
	return {"before": before, "after": after, "rendered": rendered}


## 需要比对的状态量（含由加成派生的武力 / 修为上限）
func _metrics(p: Dictionary, g: GameCore) -> Dictionary:
	var eq_null := 0
	for e in p["equip"]:
		if e == null:
			eq_null += 1
	return {
		"qi": snappedf(float(p["qi"]), 0.001),
		"mood": snappedf(float(p["mood"]), 0.001),
		"atkBonus": snappedf(float(p["atkBonus"]), 0.000001),
		"brkBonus": snappedf(float(p["brkBonus"]), 0.000001),
		"qiRateB": snappedf(float(p["qiRateB"]), 0.000001),
		"lifespanBonus": snappedf(float(p["lifespanBonus"]), 0.001),
		"is_demon": bool(p["is_demon"]),
		"spouse": p["spouse"],
		"equip_null": eq_null,
		"atk": snappedf(g.atk_of(p), 0.001),
		"qiMax": snappedf(g.qi_max(p), 0.001),
		"stone": snappedf(float(g.s["stone"]), 0.001),
		"protect": snappedf(float(g.s["protect"]), 0.001),
		"pills": (g.s["pills"] as Dictionary).duplicate(true),
		"n_people": (g.s["people"] as Array).size(),
	}


func _delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var out := {}
	for k in after.keys():
		if before.get(k) != after.get(k):
			out[k] = "%s → %s" % [str(before.get(k)), str(after.get(k))]
	return out


func _print_diff(before: Dictionary, after_a: Dictionary, after_b: Dictionary) -> void:
	for k in after_a.keys():
		if after_a.get(k) != after_b.get(k):
			print("        · %s：旧=%s  新=%s" % [k, str(after_a.get(k)), str(after_b.get(k))])


func _hits(rendered: String, kind: String) -> Array:
	var toks: Array = GOOD_TOKENS
	if kind == "bad":
		toks = BAD_TOKENS
	elif kind == "love":
		toks = LOVE_TOKENS
	var out: Array = []
	for t in toks:
		if rendered.contains(str(t)):
			out.append(t)
	return out


func _ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("   ✓ %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		var msg: String = label
		if detail != "":
			msg += "  " + detail
		_failures.append(msg)
		print("   ✗ %s" % msg)
