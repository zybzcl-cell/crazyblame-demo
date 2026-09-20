class_name BlameHud
extends Control
## 游戏内界面。
##
## 空间层级（和 scripts/core/layout_data.gd 的空间预算一一对应）：
##   顶部一行   ：返回 / 倒计时 / 连击 / 阶段        —— 只占屏幕最上面 6%
##   老板状态条 ：老板精神状态 + 阶段 + 数值 + 台词   —— 紧贴顶部，不压到老板
##   中间       ：全部让给「办公室 + 老板 + 甩锅操作区」，HUD 不出现
##   底部一行   ：总分 / 命中 / 失误 / 命中率         —— 辅助信息，不占操作区
##
## 倒计时、阶段横幅、连击台词、失误提示这些临时文字都画在**操作区内部**（会自己淡出），
## 并且带描边，保证压在锅或地板上也看得清。

signal restart_requested
signal menu_requested
signal quit_requested

const RESULT_SCENE := "res://scenes/result_card.tscn"

var _time_label: Label
var _time_value: Label
var _score_label: Label
var _score_value: Label
var _combo_label: Label
var _combo_value: Label
var _boss_bar: ProgressBar
var _boss_title: Label
var _boss_stage: Label
var _boss_hp: Label
var _boss_line: Label
var _phase_chip: Label
var _hint: Label
var _stats_line: Label
var _countdown: Label
var _banner: Label
var _shout: Label
var _toast: Label
var _quit_button: Button
var _result_card: ResultCard

var _banner_time := 0.0
var _shout_time := 0.0
var _toast_time := 0.0
var _countdown_time := 0.0
var _frenzy := false
var _size := Vector2(720.0, 1280.0)
var _layout: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()
	_layout_now(_size)


func _build() -> void:
	_time_label = UiKit.label("倒计时", UiKit.FONT_SMALL, Palette.UI_TEXT_DIM)
	_time_value = UiKit.centered_label("42.0", UiKit.FONT_H1, Palette.UI_TEXT)
	_score_label = UiKit.label("总分", UiKit.FONT_SMALL, Palette.UI_TEXT_DIM)
	_score_value = UiKit.label("0", 46, Palette.ACCENT)
	_combo_label = UiKit.centered_label("连击", UiKit.FONT_SMALL, Palette.UI_TEXT_DIM)
	_combo_value = UiKit.centered_label("0", UiKit.FONT_H1, Palette.COMBO_TEXT)
	_stats_line = UiKit.label("命中 0　失误 0　命中率 —", UiKit.FONT_TINY, Palette.UI_TEXT_DIM)
	_stats_line.name = "BottomStats"

	_boss_title = UiKit.label("老板精神状态", UiKit.FONT_TINY, Palette.UI_TEXT_DIM)
	_boss_bar = UiKit.progress_bar(Palette.OK)
	_boss_stage = UiKit.label("得意", UiKit.FONT_BODY, Palette.OK)
	_boss_hp = UiKit.centered_label("260 / 260", UiKit.FONT_SMALL, Palette.UI_TEXT)
	_boss_line = UiKit.centered_label("", UiKit.FONT_SMALL, Palette.ACCENT)
	_phase_chip = UiKit.centered_label("热身", UiKit.FONT_SMALL, Palette.UI_TEXT)
	_hint = UiKit.centered_label("", UiKit.FONT_BODY, Palette.UI_TEXT_DIM)

	_quit_button = UiKit.button("×", UiKit.FONT_H2, Palette.DANGER)
	_quit_button.tooltip_text = "返回主菜单"
	_quit_button.pressed.connect(func() -> void: quit_requested.emit())

	_countdown = UiKit.centered_label("", 150, Palette.ACCENT)
	_banner = UiKit.centered_label("", 46, Palette.ACCENT)
	_shout = UiKit.centered_label("", 58, Palette.COMBO_TEXT)
	_toast = UiKit.centered_label("", UiKit.FONT_BODY, Palette.UI_TEXT)

	var everything: Array = [_time_label, _time_value, _score_label, _score_value,
		_combo_label, _combo_value, _stats_line, _boss_title, _boss_bar, _boss_stage,
		_boss_hp, _boss_line, _phase_chip, _hint, _countdown, _banner, _shout, _toast,
		_quit_button]
	for node in everything:
		add_child(node)

	# 临时文字压在锅 / 地板上也要看得清，所以统一加描边
	for node in [_banner, _shout, _countdown, _toast]:
		node.add_theme_constant_override("outline_size", 8)
		node.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.09, 0.85))
	for node in [_banner, _shout, _countdown]:
		node.visible = false
	_hint.add_theme_color_override("font_color", Palette.UI_TEXT)
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.09, 0.8))
	_phase_chip.add_theme_stylebox_override("normal",
		UiKit.panel_style(Color(Palette.PANEL, 0.85), Palette.PANEL_EDGE, 14, 1))

	_result_card = (load(RESULT_SCENE) as PackedScene).instantiate() as ResultCard
	_result_card.visible = false
	add_child(_result_card)
	_result_card.restart_requested.connect(func() -> void: restart_requested.emit())
	_result_card.menu_requested.connect(func() -> void: menu_requested.emit())


# ---------------------------------------------------------------- 布局

func configure(size: Vector2, layout: Dictionary = {}) -> void:
	_layout = layout if not layout.is_empty() else LayoutData.compute(size)
	_layout_now(size)


func _layout_now(size: Vector2) -> void:
	_size = size
	if _time_label == null:
		return
	if _layout.is_empty():
		_layout = LayoutData.compute(size)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var hud: Rect2 = _layout["hud"]
	var bar: Rect2 = _layout["boss_bar"]
	var line: Rect2 = _layout["boss_line"]
	var field: Rect2 = _layout["field"]
	var bottom: Rect2 = _layout["bottom"]
	var h := size.y
	var pad := hud.size.x * 0.035
	var col := hud.size.x

	# 先按屏幕比例调整字号（字号的「最小尺寸」会影响后面的控件尺寸，必须先做）
	UiKit.rescale_ui(self, float(_layout["ui_scale"]))

	# ---- 顶部一行：返回 / 倒计时 / 连击 / 阶段
	_quit_button.position = Vector2(hud.position.x + pad, hud.position.y + hud.size.y * 0.06)
	_quit_button.size = Vector2(col * 0.085, hud.size.y * 0.82)
	var time_x := hud.position.x + pad + col * 0.10
	_time_label.position = Vector2(time_x, hud.position.y + hud.size.y * 0.02)
	_time_label.size = Vector2(col * 0.24, hud.size.y * 0.34)
	_time_value.position = Vector2(time_x, hud.position.y + hud.size.y * 0.32)
	_time_value.size = Vector2(col * 0.24, hud.size.y * 0.68)
	var combo_x := hud.position.x + col * 0.36
	_combo_label.position = Vector2(combo_x, hud.position.y + hud.size.y * 0.02)
	_combo_label.size = Vector2(col * 0.28, hud.size.y * 0.34)
	_combo_value.position = Vector2(combo_x, hud.position.y + hud.size.y * 0.32)
	_combo_value.size = Vector2(col * 0.28, hud.size.y * 0.68)
	_phase_chip.position = Vector2(hud.position.x + col * 0.70, hud.position.y + hud.size.y * 0.18)
	_phase_chip.size = Vector2(col * 0.265, hud.size.y * 0.62)

	# ---- 老板精神状态
	_boss_title.position = Vector2(bar.position.x + pad, bar.position.y - h * 0.021)
	_boss_title.size = Vector2(bar.size.x * 0.6, h * 0.021)
	_boss_stage.position = Vector2(bar.position.x + pad, bar.position.y)
	_boss_stage.size = Vector2(bar.size.x * 0.5, h * 0.026)
	_boss_hp.position = Vector2(bar.end.x - pad - bar.size.x * 0.32, bar.position.y)
	_boss_hp.size = Vector2(bar.size.x * 0.32, h * 0.026)
	_boss_bar.position = Vector2(bar.position.x + pad, bar.position.y + h * 0.028)
	_boss_bar.size = Vector2(bar.size.x - pad * 2.0, h * 0.018)
	_boss_line.position = Vector2(line.position.x + pad, line.position.y)
	_boss_line.size = Vector2(line.size.x - pad * 2.0, line.size.y)

	# ---- 操作区里的临时文字
	_hint.position = Vector2(field.position.x, field.get_center().y + field.size.y * 0.10)
	_hint.size = Vector2(field.size.x, field.size.y * 0.07)
	_countdown.position = Vector2(field.position.x, field.position.y + field.size.y * 0.06)
	_countdown.size = Vector2(field.size.x, field.size.y * 0.42)
	_banner.position = Vector2(field.position.x, field.position.y + field.size.y * 0.02)
	_banner.size = Vector2(field.size.x, field.size.y * 0.14)
	_shout.position = Vector2(field.position.x, field.position.y + field.size.y * 0.30)
	_shout.size = Vector2(field.size.x, field.size.y * 0.14)
	_toast.position = Vector2(field.position.x, field.end.y - field.size.y * 0.11)
	_toast.size = Vector2(field.size.x, field.size.y * 0.08)

	# ---- 底部辅助信息：总分 / 命中 / 失误 / 命中率
	_score_label.position = Vector2(bottom.position.x + pad, bottom.position.y)
	_score_label.size = Vector2(bottom.size.x * 0.2, bottom.size.y * 0.34)
	_score_value.position = Vector2(bottom.position.x + pad, bottom.position.y + bottom.size.y * 0.26)
	_score_value.size = Vector2(bottom.size.x * 0.34, bottom.size.y * 0.72)
	_stats_line.position = Vector2(bottom.position.x + bottom.size.x * 0.40,
		bottom.position.y + bottom.size.y * 0.30)
	_stats_line.size = Vector2(bottom.size.x * 0.60 - pad, bottom.size.y * 0.5)
	_stats_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_result_card.configure(size)


# ---------------------------------------------------------------- 每帧推进

func tick(delta: float) -> void:
	_banner_time = maxf(_banner_time - delta, 0.0)
	_shout_time = maxf(_shout_time - delta, 0.0)
	_toast_time = maxf(_toast_time - delta, 0.0)
	_countdown_time = maxf(_countdown_time - delta, 0.0)
	_apply_pop(_banner, _banner_time, 0.35)
	_apply_pop(_shout, _shout_time, 0.5)
	_apply_pop(_countdown, _countdown_time, 0.7)
	_banner.visible = _banner_time > 0.0
	_shout.visible = _shout_time > 0.0
	_countdown.visible = _countdown_time > 0.0
	_toast.visible = _toast_time > 0.0
	if _toast_time > 0.0:
		_toast.modulate.a = clampf(_toast_time / 0.35, 0.0, 1.0)


## 弹出效果：刚出现时放大，然后回落到正常大小
func _apply_pop(node: Control, time_left: float, life: float) -> void:
	if time_left <= 0.0:
		return
	var progress := 1.0 - clampf(time_left / life, 0.0, 1.0)
	var pop := 1.0 + 0.45 * maxf(0.0, 1.0 - progress * 4.0)
	node.scale = Vector2.ONE * pop
	node.pivot_offset = node.size * 0.5
	node.modulate.a = clampf(time_left / (life * 0.35), 0.0, 1.0)


# ---------------------------------------------------------------- 供游戏主控调用

func reset_for_round() -> void:
	_frenzy = false
	_banner_time = 0.0
	_shout_time = 0.0
	_toast_time = 0.0
	_countdown_time = 0.0
	_countdown.visible = false
	_banner.visible = false
	_shout.visible = false
	_toast.visible = false
	_boss_bar.value = 100.0
	_boss_bar.add_theme_stylebox_override("fill", _fill_style(Palette.OK))
	_combo_value.text = "0"
	_score_value.text = "0"
	_stats_line.text = "命中 0　失误 0　命中率 —"
	_time_value.text = "%.1f" % GameConfig.PLAY_SECONDS


func set_time_left(seconds: float) -> void:
	var text := "%.1f" % maxf(seconds, 0.0)
	if _time_value.text != text:
		_time_value.text = text
	var color := Palette.UI_TEXT
	if seconds <= 5.0:
		color = Palette.DANGER
	elif seconds <= 10.0:
		color = Palette.ACCENT
	_time_value.add_theme_color_override("font_color", color)


func set_score(points: int) -> void:
	var text := str(points)
	if _score_value.text != text:
		_score_value.text = text


func set_combo(combo: int) -> void:
	_combo_value.text = str(combo)
	if combo >= 10:
		_combo_value.add_theme_color_override("font_color", Palette.DANGER)
	elif combo >= 5:
		_combo_value.add_theme_color_override("font_color", Palette.ACCENT)
	else:
		_combo_value.add_theme_color_override("font_color", Palette.COMBO_TEXT)
	var mult := Score.combo_multiplier(combo, 1.0)
	_combo_label.text = "连击 ×%.1f" % mult if combo > 0 else "连击"


## 底部辅助统计：命中 / 失误 / 命中率
func set_stats(hits: int, misses: int) -> void:
	var attempts := hits + misses
	var accuracy := "—" if attempts <= 0 else "%d%%" % int(round(float(hits) / float(attempts) * 100.0))
	var text := "命中 %d　失误 %d　命中率 %s" % [hits, misses, accuracy]
	if _stats_line.text != text:
		_stats_line.text = text


func set_boss(hp: int, max_hp: int, stage_name: String,
		stage_color: Color = Palette.OK) -> void:
	var ratio := 0.0 if max_hp <= 0 else clampf(float(hp) / float(max_hp), 0.0, 1.0)
	_boss_bar.value = ratio * 100.0
	_boss_bar.add_theme_stylebox_override("fill", _fill_style(Palette.health_color(ratio)))
	_boss_stage.text = stage_name
	_boss_stage.add_theme_color_override("font_color", stage_color)
	_boss_hp.text = "%d / %d" % [maxi(hp, 0), max_hp]


func set_boss_line(text: String) -> void:
	if _boss_line.text != text:
		_boss_line.text = text


func set_phase(name: String) -> void:
	_phase_chip.text = name


func set_hint(text: String) -> void:
	_hint.text = text


func set_frenzy(on: bool) -> void:
	_frenzy = on
	if on:
		_phase_chip.add_theme_color_override("font_color", Palette.DANGER)
	else:
		_phase_chip.add_theme_color_override("font_color", Palette.UI_TEXT)


func is_frenzy() -> bool:
	return _frenzy


func set_countdown(value: int) -> void:
	if value <= 0:
		_countdown_time = 0.0
		_countdown.visible = false
		return
	_countdown.text = str(value)
	_countdown_time = 0.7
	_countdown.visible = true


func show_banner(text: String, color: Color = Palette.ACCENT) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner_time = 1.1
	_banner.visible = true


func show_shout(text: String) -> void:
	_shout.text = text
	_shout_time = 1.0
	_shout.visible = true


func show_toast(text: String, color: Color = Palette.UI_TEXT) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast_time = 1.0
	_toast.visible = true


func show_result(result: Dictionary) -> void:
	_result_card.show_result(result)


func hide_result() -> void:
	_result_card.visible = false


func result_card() -> ResultCard:
	return _result_card


func quit_button() -> Button:
	return _quit_button


func _fill_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(10)
	return style


# ---------------------------------------------------------------- 测试用读取接口

func shout_text() -> String:
	return _shout.text


func banner_text() -> String:
	return _banner.text


func hint_text() -> String:
	return _hint.text


func boss_line_text() -> String:
	return _boss_line.text


func boss_stage_text() -> String:
	return _boss_stage.text


func combo_text() -> String:
	return _combo_value.text


func score_text() -> String:
	return _score_value.text


func time_text() -> String:
	return _time_value.text


func stats_text() -> String:
	return _stats_line.text


## 所有会显示文字的控件（构图 / 字体测试会遍历它们，确认没有超出屏幕、没有缺字）
func text_nodes() -> Array:
	var list: Array = [_time_label, _time_value, _score_label, _score_value, _combo_label,
		_combo_value, _stats_line, _boss_title, _boss_stage, _boss_hp, _boss_line,
		_phase_chip, _hint, _countdown, _banner, _shout, _toast]
	if _result_card != null:
		list.append_array(_result_card.text_nodes())
	return list
