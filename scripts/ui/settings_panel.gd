class_name SettingsPanel
extends Control
## 设置面板：声音 / 震动开关、历史成绩、清除记录、存档位置。

signal closed

var _dim: ColorRect
var _panel: Panel
var _sound_button: Button
var _vibration_button: Button
var _reset_button: Button
var _stats: Label
var _save_path: Label
var _confirm_reset := false
var _size := Vector2(720.0, 1280.0)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_layout(_size)
	refresh()
	visible = false


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.05, 0.06, 0.09, 0.78)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	_panel = Panel.new()
	_panel.add_theme_stylebox_override("panel", UiKit.panel_style(
		Palette.PANEL, Palette.PANEL_EDGE, 24, 3))
	add_child(_panel)

	var title := UiKit.centered_label("设 置", UiKit.FONT_H1, Palette.UI_TEXT)
	title.name = "Title"
	_panel.add_child(title)
	_sound_button = UiKit.button("声音", UiKit.FONT_H2, Palette.ACCENT)
	_sound_button.name = "Sound"
	_sound_button.pressed.connect(func() -> void:
		ProgressManager.set_sound_enabled(not ProgressManager.sound_enabled())
		AudioManager.play("ui_click")
		refresh())
	_panel.add_child(_sound_button)
	_vibration_button = UiKit.button("震动", UiKit.FONT_H2, Palette.ACCENT)
	_vibration_button.name = "Vibration"
	_vibration_button.pressed.connect(func() -> void:
		ProgressManager.set_vibration_enabled(not ProgressManager.vibration_enabled())
		Haptics.set_enabled(ProgressManager.vibration_enabled())
		AudioManager.play("ui_click")
		refresh())
	_panel.add_child(_vibration_button)
	_stats = UiKit.centered_label("", UiKit.FONT_SMALL, Palette.UI_TEXT_DIM)
	_stats.name = "Stats"
	_panel.add_child(_stats)
	_reset_button = UiKit.button("清除全部记录", UiKit.FONT_BODY, Palette.DANGER)
	_reset_button.name = "Reset"
	_reset_button.pressed.connect(_on_reset)
	_panel.add_child(_reset_button)
	_save_path = UiKit.centered_label("", UiKit.FONT_TINY, Palette.UI_TEXT_DIM)
	_save_path.name = "SavePath"
	_panel.add_child(_save_path)
	var close := UiKit.button("返回", UiKit.FONT_BODY, Palette.INFO)
	close.name = "Close"
	close.pressed.connect(func() -> void: closed.emit())
	_panel.add_child(close)


func configure(size: Vector2) -> void:
	_layout(size)


func _layout(size: Vector2) -> void:
	_size = size
	if _panel == null:
		return
	_dim.size = size
	var panel_w := minf(size.x * 0.88, 600.0)
	var panel_h := minf(size.y * 0.64, 760.0)
	var origin := Vector2((size.x - panel_w) * 0.5, (size.y - panel_h) * 0.5)
	_panel.position = origin
	_panel.size = Vector2(panel_w, panel_h)
	UiKit.rescale_ui(self, float(LayoutData.compute(size)["ui_scale"]))
	var pad := panel_w * 0.08
	var width := panel_w - pad * 2.0
	_place(_panel.get_node("Title"), pad, 16.0, width, 56.0)
	_place(_sound_button, pad, 90.0, width, 62.0)
	_place(_vibration_button, pad, 164.0, width, 62.0)
	_place(_stats, pad, 244.0, width, 96.0)
	_place(_reset_button, pad, 352.0, width, 56.0)
	_place(_save_path, pad, 420.0, width, 60.0)
	_place(_panel.get_node("Close"), pad, panel_h - 70.0, width, 52.0)


func _place(node: Control, x: float, y: float, w: float, h: float) -> void:
	node.position = Vector2(x, y)
	node.size = Vector2(w, h)


func refresh() -> void:
	if _sound_button == null:
		return
	_sound_button.text = "声音：开" if ProgressManager.sound_enabled() else "声音：关"
	_vibration_button.text = "震动：开" if ProgressManager.vibration_enabled() else "震动：关"
	_stats.text = "\n".join([
		"最高分 %d　最高连击 %d" % [ProgressManager.best_score(), ProgressManager.best_combo()],
		"累计 %d 局　甩回 %d 口锅　命中率 %.0f%%" % [
			ProgressManager.total_games(), ProgressManager.total_returned(),
			ProgressManager.accuracy() * 100.0],
	])
	_save_path.text = "存档：%s" % ProgressManager.save_path
	_confirm_reset = false
	_reset_button.text = "清除全部记录"


func _on_reset() -> void:
	if not _confirm_reset:
		_confirm_reset = true
		_reset_button.text = "再点一次确认清除"
		AudioManager.play("ui_click")
		return
	ProgressManager.reset_progress()
	AudioManager.play("ui_click")
	refresh()


func sound_button() -> Button:
	return _sound_button


func vibration_button() -> Button:
	return _vibration_button


func reset_button() -> Button:
	return _reset_button


## 面板上所有会显示文字的控件（构图 / 字体测试用）
func text_nodes() -> Array:
	if _panel == null:
		return []
	return [_sound_button, _vibration_button, _stats, _reset_button, _save_path,
		_panel.get_node("Close")]
