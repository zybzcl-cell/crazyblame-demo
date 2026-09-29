class_name GameMenu
extends Control
## 游戏内的「暂停菜单」—— 一个非游戏界面。
##
## 打开它的时候，游戏主控会把 Boss / 锅层 / 特效层全部藏起来并冻结玩法（见 blame_game.gd），
## 所以这里只管面板本身：不需要靠「把背景调得更黑」来遮住 Boss，
## 也不会出现 Boss 穿透在文字或按钮后面的问题。
##
## 二级面板（操作说明 / 锅图鉴 / 设置）复用主菜单里同一套类，交互完全一致。

signal resume_requested
signal menu_requested

var _dim: ColorRect
var _panel: Panel
var _title: Label
var _tip: Label
var _resume_button: Button
var _help_button: Button
var _codex_button: Button
var _settings_button: Button
var _menu_button: Button
var _help: Panel
var _help_title: Label
var _help_body: Label
var _help_back: Button
var _codex: PotCodex
var _settings: SettingsPanel
var _size := Vector2(720.0, 1280.0)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_layout(_size)
	visible = false


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.05, 0.06, 0.09, 0.82)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_panel = Panel.new()
	_panel.add_theme_stylebox_override("panel", UiKit.panel_style(
		Palette.PANEL, Palette.ACCENT.darkened(0.25), 24, 3))
	add_child(_panel)
	_title = UiKit.centered_label("暂 停", UiKit.FONT_H1, Palette.ACCENT)
	_title.name = "Title"
	_panel.add_child(_title)
	_tip = UiKit.centered_label("老板和锅都先收起来了，喘口气再继续", UiKit.FONT_SMALL,
		Palette.UI_TEXT_DIM)
	_tip.name = "Tip"
	_panel.add_child(_tip)
	_resume_button = UiKit.button("继续游戏", UiKit.FONT_H2, Palette.OK)
	_resume_button.name = "Resume"
	_resume_button.pressed.connect(func() -> void: resume_requested.emit())
	_panel.add_child(_resume_button)
	_help_button = UiKit.button("操作说明", UiKit.FONT_BODY, Palette.INFO)
	_help_button.name = "Help"
	_help_button.pressed.connect(_show_help)
	_panel.add_child(_help_button)
	_codex_button = UiKit.button("锅图鉴", UiKit.FONT_BODY, Palette.INFO)
	_codex_button.name = "Codex"
	_codex_button.pressed.connect(_show_codex)
	_panel.add_child(_codex_button)
	_settings_button = UiKit.button("设置", UiKit.FONT_BODY, Palette.INFO)
	_settings_button.name = "Settings"
	_settings_button.pressed.connect(_show_settings)
	_panel.add_child(_settings_button)
	_menu_button = UiKit.button("返回主菜单", UiKit.FONT_BODY, Palette.DANGER)
	_menu_button.name = "Menu"
	_menu_button.pressed.connect(func() -> void: menu_requested.emit())
	_panel.add_child(_menu_button)

	_help = Panel.new()
	_help.add_theme_stylebox_override("panel", UiKit.panel_style(
		Palette.PANEL, Palette.INFO.darkened(0.2), 24, 3))
	add_child(_help)
	_help_title = UiKit.centered_label("操 作 说 明", UiKit.FONT_H1, Palette.INFO)
	_help_title.name = "HelpTitle"
	_help.add_child(_help_title)
	_help_body = UiKit.centered_label(
		"1. 点住锅 → 拖到老板身上松手，就能甩回去\n"
		+ "2. 也可以朝老板快速划一下，把锅甩出去\n"
		+ "3. 同一时间只能拿一口锅，先处理快凉的\n"
		+ "4. 锅放太久会凉了，算一次失误、断连击\n"
		+ "5. 连击越高，老板越狼狈，得分也越高",
		UiKit.FONT_BODY, Palette.UI_TEXT)
	_help_body.name = "HelpBody"
	_help_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.add_child(_help_body)
	_help_back = UiKit.button("返回", UiKit.FONT_BODY, Palette.INFO)
	_help_back.name = "HelpBack"
	_help_back.pressed.connect(_show_root)
	_help.add_child(_help_back)
	_help.visible = false

	_codex = PotCodex.new()
	add_child(_codex)
	_codex.closed.connect(_show_root)
	_settings = SettingsPanel.new()
	add_child(_settings)
	_settings.closed.connect(_show_root)


func configure(size: Vector2) -> void:
	_layout(size)


func _layout(size: Vector2) -> void:
	_size = size
	if _panel == null:
		return
	_dim.size = size
	_dim.position = Vector2.ZERO
	UiKit.rescale_ui(self, float(LayoutData.compute(size)["ui_scale"]))
	var panel_w := minf(size.x * 0.86, 640.0)
	var panel_h := minf(size.y * 0.70, 820.0)
	_place_centered(_panel, size, panel_w, panel_h)
	var pad := panel_w * 0.08
	var width := panel_w - pad * 2.0
	_local(_title, pad, 18.0, width, 54.0)
	_local(_tip, pad, 74.0, width, 30.0)
	var y := 118.0
	var step := (panel_h - y - 92.0) / 5.0
	for node in [_resume_button, _help_button, _codex_button, _settings_button, _menu_button]:
		_local(node, pad, y + step * 0.16, width, minf(step * 0.70, 66.0))
		y += step

	var help_w := minf(size.x * 0.86, 640.0)
	var help_h := minf(size.y * 0.66, 720.0)
	_place_centered(_help, size, help_w, help_h)
	var hpad := help_w * 0.08
	var hwidth := help_w - hpad * 2.0
	_local(_help_title, hpad, 20.0, hwidth, 54.0)
	_local(_help_body, hpad, 84.0, hwidth, help_h - 190.0)
	_local(_help_back, hpad, help_h - 76.0, hwidth, 52.0)

	_codex.configure(size)
	_settings.configure(size)


func _place_centered(node: Control, size: Vector2, width: float, height: float) -> void:
	node.position = Vector2((size.x - width) * 0.5, (size.y - height) * 0.5)
	node.size = Vector2(width, height)


func _local(node: Control, x: float, y: float, w: float, h: float) -> void:
	node.position = Vector2(x, y)
	node.size = Vector2(w, h)


# ---------------------------------------------------------------- 开关

func open() -> void:
	visible = true
	_show_root()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _show_root() -> void:
	_panel.visible = true
	_help.visible = false
	_codex.visible = false
	_settings.visible = false


func _show_help() -> void:
	AudioManager.play("ui_click")
	_panel.visible = false
	_help.visible = true
	_codex.visible = false
	_settings.visible = false


func _show_codex() -> void:
	AudioManager.play("ui_click")
	_codex.refresh()
	_panel.visible = false
	_help.visible = false
	_codex.visible = true
	_settings.visible = false


func _show_settings() -> void:
	AudioManager.play("ui_click")
	_settings.refresh()
	_panel.visible = false
	_help.visible = false
	_codex.visible = false
	_settings.visible = true


# ---------------------------------------------------------------- 测试接口

func resume_button() -> Button:
	return _resume_button


func menu_button() -> Button:
	return _menu_button


func help_button() -> Button:
	return _help_button


func codex_button() -> Button:
	return _codex_button


func settings_button() -> Button:
	return _settings_button


func codex() -> PotCodex:
	return _codex


func settings() -> SettingsPanel:
	return _settings


func help_panel() -> Panel:
	return _help


## 面板上所有会显示文字的控件（构图 / 字体测试用）
func text_nodes() -> Array:
	var list: Array = [_title, _tip, _resume_button, _help_button, _codex_button,
		_settings_button, _menu_button, _help_title, _help_body, _help_back]
	list.append_array(_codex.text_nodes())
	list.append_array(_settings.text_nodes())
	return list
