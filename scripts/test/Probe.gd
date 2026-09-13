extends SceneTree

## 语法探针：验证移植中要用到的 GDScript 特性。

const NESTED := {
	"list": [1, 2, 3],
	"sub": {"a": 1.5, "b": "字"},
}

func _initialize() -> void:
	print("=== 1. 字典点访问 ===")
	var d := {"name": "龙傲天", "realm": 3, "sub": 7}
	print("  d.name = ", d.name)
	print("  d[\"name\"] = ", d["name"])
	d.realm += 1
	print("  d.realm 自增后 = ", d.realm)

	print("=== 2. 常量嵌套 ===")
	print("  NESTED.list = ", NESTED["list"])
	print("  NESTED.sub.a = ", NESTED["sub"]["a"])

	print("=== 3. 数值 ===")
	print("  pow(2.6, 3) = ", pow(2.6, 3))
	print("  2.6 ** 3 = ", 2.6 ** 3)
	print("  int(3.9) = ", int(3.9))
	print("  sqrt(100.0) = ", sqrt(100.0))
	print("  randf() = ", randf())

	print("=== 4. 字符串 ===")
	var n := "傲天"
	print("  %%s 插值 = ", "%s 拜入宗门，时年%d岁" % [n, 20])
	print("  fmt数 = ", _fmt(123456))

	print("=== 5. 数组操作 ===")
	var arr := [1, 2, 3]
	arr.remove_at(0)
	print("  remove_at 后 = ", arr)
	print("  pick = ", arr[randi() % arr.size()])
	print("  切片 = ", arr.slice(0, 2))

	print("=== 6. 类型判定 ===")
	var v = null
	print("  null is Dictionary? ", v is Dictionary)
	var dd := {}
	print("  空字典 is Dictionary? ", dd is Dictionary)
	print("  typeof string = ", typeof("x"), " (TYPE_STRING=", TYPE_STRING, ")")

	print("=== 7. 排序 ===")
	var ps := [{"a": 3}, {"a": 9}, {"a": 1}]
	ps.sort_custom(func(x, y): return x["a"] > y["a"])
	print("  降序 = ", ps.map(func(p): return p["a"]))

	print("PROBE_DONE")
	quit()

func _fmt(v: float) -> String:
	var n := int(floor(v))
	if n < 10000:
		return str(n)
	if n < 100000000:
		return "%.2f万" % (n / 10000.0)
	return "%.2f亿" % (n / 100000000.0)
