class_name UiKit
## 界面小工具：统一样式的面板 / 按钮 / 文字。
##
## 界面全部用代码搭（而不是在编辑器里拖），好处是：布局逻辑（竖屏自适应、字号随屏幕缩放）
## 和视觉样式都在一个文件里，改一处就整体一致；场景文件只保留节点结构。

const FONT_TITLE := 52
const FONT_H1 := 38
const FONT_H2 := 28
const FONT_BODY := 22
const FONT_SMALL := 18
const FONT_TINY := 15


static func panel_style(
	bg: Color = Palette.PANEL, edge: Color = Palette.PANEL_EDGE,
	radius: int = 18, border: int = 2
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = edge
	style.set_border_width_all(border)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	return style


static func label(text: String, size: int = FONT_BODY, color: Color = Palette.UI_TEXT) -> Label:
	var node := Label.new()
	node.text = text
	tag_font(node, size)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## 记下这个控件的「基准字号」，并按当前比例套用。
## 小屏（手机浏览器 390×844）文字会自动收紧、大屏自动放大，
## 这样界面文字永远不会超出分配给它那一格。
static func tag_font(node: Control, base_size: int) -> void:
	node.set_meta("ui_base_font", base_size)
	node.add_theme_font_size_override("font_size", base_size)


## 按比例刷新一棵界面子树里的所有文字字号（布局变化时调用）
static func rescale_ui(root: Node, scale: float) -> void:
	var clamped := clampf(scale, 0.45, 2.2)
	if root is Control and root.has_meta("ui_base_font"):
		var base := float(root.get_meta("ui_base_font"))
		(root as Control).add_theme_font_size_override("font_size",
			maxi(int(round(base * clamped)), 9))
	for child in root.get_children():
		rescale_ui(child, clamped)


static func centered_label(text: String, size: int = FONT_BODY, color: Color = Palette.UI_TEXT) -> Label:
	var node := label(text, size, color)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return node


static func button(text: String, size: int = FONT_H2, accent: Color = Palette.ACCENT) -> Button:
	var node := Button.new()
	node.text = text
	tag_font(node, size)
	node.add_theme_color_override("font_color", Palette.UI_TEXT)
	node.add_theme_color_override("font_hover_color", Color.WHITE)
	node.add_theme_color_override("font_pressed_color", Palette.UI_TEXT)
	node.add_theme_color_override("font_focus_color", Palette.UI_TEXT)
	node.add_theme_stylebox_override("normal", panel_style(Palette.PANEL_LIGHT, accent.darkened(0.25), 16, 2))
	node.add_theme_stylebox_override("hover", panel_style(accent.darkened(0.55), accent, 16, 2))
	node.add_theme_stylebox_override("pressed", panel_style(accent.darkened(0.30), accent, 16, 2))
	node.add_theme_stylebox_override("focus", panel_style(Color(0, 0, 0, 0), accent, 16, 2))
	node.add_theme_stylebox_override("disabled", panel_style(Palette.PANEL, Palette.PANEL_EDGE, 16, 2))
	node.add_theme_color_override("font_disabled_color", Palette.UI_TEXT_DIM)
	return node


## 开关按钮（设置面板用）：开启时是强调色，关闭时是灰的
static func toggle_button(text: String, on: bool, size: int = FONT_BODY) -> Button:
	var accent := Palette.OK if on else Palette.PANEL_EDGE
	var node := button(text, size, accent)
	node.text = ("%s：开" % text) if on else ("%s：关" % text)
	return node


static func progress_bar(fill: Color, bg: Color = Palette.PANEL) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	var background := StyleBoxFlat.new()
	background.bg_color = bg
	background.set_corner_radius_all(10)
	background.border_color = Palette.PANEL_EDGE
	background.set_border_width_all(2)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill
	fill_style.set_corner_radius_all(10)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill_style)
	return bar
