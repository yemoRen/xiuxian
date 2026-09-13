extends RefCounted

## 水墨风主题：调色板 + 控件工厂。对应 web 版 style.css。
## 所有 UI 脚本通过 `const TH := preload(...)` 后以 TH.xxx() 静态调用。

# ── 调色板 ────────────────────────────────────────────
const PAPER := Color("f6f2e9")
const PAPER2 := Color("fbf8f1")
const INK := Color("2b2b28")
const INK2 := Color("5a564c")
const INK3 := Color("8c877a")
const RED := Color("8c2f2f")
const RED_L := Color("f7ecea")
const GOLD := Color("9c7a2e")
const GOLD_L := Color("f8f1de")
const GREEN := Color("3f6b45")
const GREEN_L := Color("edf3ea")
const BLUE := Color("35566e")
const BLUE_L := Color("ecf1f4")
const LINE := Color("e0d9c8")
const LINE2 := Color("cfc6b0")
const MASK := Color(40.0 / 255.0, 36.0 / 255.0, 30.0 / 255.0, 0.45)

# 灵根品质配色（0 最稀有 → 7 最普通）
const LG_COLORS := [
	Color("b8860b"), Color("c0392b"), Color("8e44ad"), Color("16a085"),
	Color("2980b9"), Color("5a564c"), Color("8c877a"), Color("8c877a"),
]
# 境界配色（realm/2 归档）
const R_COLORS := [Color("8c877a"), Color("35566e"), Color("3f6b45"), Color("9c7a2e"), Color("8c2f2f")]

const FONT_PATH := "res://assets/fonts/FusionPixel-12px-Prop-zh_hans.ttf"
const FONT_BOLD_PATH := "res://assets/fonts/FusionPixel-12px-Prop-zh_hans-Bold.ttf"

# 字号（配合 12px 点阵字体，取整数倍附近的档位）
const FS_BASE := 13
const FS_SMALL := 12
const FS_H3 := 15
const FS_H4 := 14
const FS_NAV := 16
const FS_TITLE := 20
const FS_H2 := 18

static var _font_cache: Font = null
static var _font_bold_cache: Font = null


static func font() -> Font:
	if _font_cache == null:
		_font_cache = _load_font(FONT_PATH)
	return _font_cache


static func font_bold() -> Font:
	if _font_bold_cache == null:
		_font_bold_cache = _load_font(FONT_BOLD_PATH)
	return _font_bold_cache


static func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f = load(path)
		if f is Font:
			return f
	# 兜底：系统宋体/雅黑
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["SimSun", "宋体", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	sf.allow_system_fallback = true
	return sf


static func lg_color(idx: int) -> Color:
	return LG_COLORS[clampi(idx, 0, LG_COLORS.size() - 1)]


static func realm_color(realm: int) -> Color:
	return R_COLORS[clampi(int(floor(realm / 2.0)), 0, R_COLORS.size() - 1)]


# ── StyleBox 工厂 ─────────────────────────────────────
static func sb(bg: Color, border: Color, bw: int = 1, radius: int = 6,
		pad_h: int = 12, pad_v: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	return s


static func sb_flat(bg: Color, radius: int = 4, pad_h: int = 10, pad_v: int = 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	return s


# ── 控件工厂 ──────────────────────────────────────────

static func label(text: String, size: int = FS_BASE, color: Color = INK, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_bold() if bold else font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## 自动换行的正文标签
static func wrap_label(text: String, size: int = FS_BASE, color: Color = INK) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## 支持 BBCode 的富文本（用于纪事行内混排）
static func rich(size: int = FS_BASE, color: Color = INK) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_override("normal_font", font())
	r.add_theme_font_override("bold_font", font_bold())
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", color)
	r.add_theme_constant_override("line_separation", 2)
	return r


## kind: "" 默认 | mini | nav | nav_on | danger | primary | on | ghost
static func button(text: String, kind: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", FS_SMALL if kind == "mini" else FS_BASE)

	var bg := PAPER
	var bd := LINE2
	var fg := INK
	var hover_bg := GOLD_L
	var hover_bd := GOLD
	var radius := 4

	match kind:
		"nav":
			bg = PAPER
			fg = INK3
			radius = 4
			b.add_theme_font_size_override("font_size", FS_NAV)
		"nav_on":
			bg = INK
			bd = INK
			fg = PAPER2
			hover_bg = INK
			hover_bd = INK
			b.add_theme_font_size_override("font_size", FS_NAV)
		"danger":
			hover_bg = RED_L
			hover_bd = RED
		"primary":
			bg = INK
			bd = INK
			fg = PAPER2
			hover_bg = INK2
			hover_bd = INK2
		"on":
			bg = GOLD
			bd = GOLD
			fg = Color.WHITE
			hover_bg = GOLD
			hover_bd = GOLD
		"ghost":
			bg = Color(0, 0, 0, 0)
			bd = LINE
			fg = INK3

	var ph := 7 if kind == "mini" else 11
	var pv := 3 if kind == "mini" else 5

	b.add_theme_stylebox_override("normal", sb(bg, bd, 1, radius, ph, pv))
	b.add_theme_stylebox_override("hover", sb(hover_bg, hover_bd, 1, radius, ph, pv))
	b.add_theme_stylebox_override("pressed", sb(hover_bg.darkened(0.06), hover_bd, 1, radius, ph, pv))
	var dis := sb(bg, bd, 1, radius, ph, pv)
	dis.bg_color = bg.lerp(PAPER, 0.6)
	dis.border_color = bd.lerp(PAPER, 0.6)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg if kind == "nav_on" else INK)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", INK3)

	if kind != "danger":
		b.add_theme_color_override("font_hover_color", fg)
	return b


## 一个空的控制件，用于撑开间距
static func spacer(w: float = 0.0, h: float = 0.0, expand: bool = false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func hbox(sep: int = 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


## 面板：PanelContainer > MarginContainer > VBoxContainer，返回内层 VBox
static func panel(title: String = "") -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", sb(PAPER2, LINE, 1, 6, 16, 14))

	var inner := vbox(4)
	pc.add_child(inner)
	if title != "":
		inner.add_child(label(title, FS_H3, INK, true))
	# 调用方把内容加到返回的 VBox
	pc.set_meta("body", inner)
	return inner


## 从 panel() 返回的 VBox 取回外层 PanelContainer（用于挂到父节点）
static func panel_of(body: VBoxContainer) -> PanelContainer:
	return body.get_parent() as PanelContainer


## 进度条：返回一个 HBox[ 底槽 ]
static func progress_bar(width: float = 160.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(width, 7)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.show_percentage = false
	pb.min_value = 0.0
	pb.max_value = 100.0

	var bg := StyleBoxFlat.new()
	bg.bg_color = LINE
	bg.set_corner_radius_all(4)
	pb.add_theme_stylebox_override("background", bg)
	var fg := StyleBoxFlat.new()
	fg.bg_color = GOLD
	fg.set_corner_radius_all(4)
	pb.add_theme_stylebox_override("fill", fg)
	return pb


## 圆形小标签（person-chip）
static func chip(text: String, kind: String = "") -> PanelContainer:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var bg := GOLD_L
	var bd := LINE2
	var fg := INK
	match kind:
		"lead":
			bg = RED_L
			bd = Color("e0b8b8")
			fg = RED
		"empty":
			bg = Color(0, 0, 0, 0)
			fg = INK3
	var s := sb(bg, bd, 1, 10, 8, 1)
	if kind == "empty":
		s.border_width_left = 1
		s.border_width_right = 1
		s.border_width_top = 1
		s.border_width_bottom = 1
	pc.add_theme_stylebox_override("panel", s)
	pc.add_child(label(text, FS_SMALL, fg))
	return pc


## 分隔虚线（用一条细 ColorRect 近似）
static func divider() -> Control:
	var c := ColorRect.new()
	c.color = LINE
	c.custom_minimum_size = Vector2(0, 1)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func scroll() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return sc


## 两列/三列栅格（用 HBox 近似 CSS grid 1fr 1fr）
static func grid(cols: int) -> HBoxContainer:
	var h := hbox(12)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in cols:
		var col := vbox(12)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.set_meta("col", i)
		h.add_child(col)
	return h


## 把 panel 挂到栅格的第 i 列
static func grid_add(g: HBoxContainer, index: int, pc: Control) -> void:
	g.get_child(index % g.get_child_count()).add_child(pc)
