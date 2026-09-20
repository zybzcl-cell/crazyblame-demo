class_name PotCodex
extends Control
## 锅图鉴：五种锅的差别（伤害 / 速度 / 难度）与解锁进度，外加「要不要让它上场」。
##
## 解锁之后可以停用某种锅 —— 这是玩法选择（比如不想被压力锅打乱节奏），不是数值养成。

signal closed

var _dim: ColorRect
var _panel: Panel
var _list: VBoxContainer
var _size := Vector2(720.0, 1280.0)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_layout(_size)
	visible = false


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.05, 0.06, 0.09, 0.78)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	_panel = Panel.new()
	_panel.add_theme_stylebox_override("panel", UiKit.panel_style(
		Palette.PANEL, Palette.INFO.darkened(0.2), 24, 3))
	add_child(_panel)
	var title := UiKit.centered_label("锅 图 鉴", UiKit.FONT_H1, Palette.INFO)
	title.name = "Title"
	_panel.add_child(title)
	var tip := UiKit.centered_label("五种锅手感真的不一样：伤害、速度、难度都不同", UiKit.FONT_SMALL,
		Palette.UI_TEXT_DIM)
	tip.name = "Tip"
	_panel.add_child(tip)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.add_theme_constant_override("separation", 12)
	_panel.add_child(_list)
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
	var panel_w := minf(size.x * 0.94, 660.0)
	var panel_h := minf(size.y * 0.90, 1060.0)
	var origin := Vector2((size.x - panel_w) * 0.5, (size.y - panel_h) * 0.5)
	_panel.position = origin
	_panel.size = Vector2(panel_w, panel_h)
	UiKit.rescale_ui(self, float(LayoutData.compute(size)["ui_scale"]))
	var pad := panel_w * 0.055
	_panel.get_node("Title").position = Vector2(pad, 14.0)
	_panel.get_node("Title").size = Vector2(panel_w - pad * 2.0, 56.0)
	_panel.get_node("Tip").position = Vector2(pad, 74.0)
	_panel.get_node("Tip").size = Vector2(panel_w - pad * 2.0, 28.0)
	_list.position = Vector2(pad, 110.0)
	_list.size = Vector2(panel_w - pad * 2.0, panel_h - 190.0)
	_panel.get_node("Close").position = Vector2(pad, panel_h - 62.0)
	_panel.get_node("Close").size = Vector2(panel_w - pad * 2.0, 48.0)


func refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	for pot in PotData.catalog():
		_list.add_child(_make_card(pot))


func _make_card(pot: PotType) -> Panel:
	var card := Panel.new()
	card.custom_minimum_size = Vector2(0.0, _size.y * 0.098)
	var unlocked := ProgressManager.is_pot_unlocked(pot.id)
	card.add_theme_stylebox_override("panel", UiKit.panel_style(
		Palette.PANEL_LIGHT if unlocked else Color(0.16, 0.18, 0.22),
		pot.tint if unlocked else Palette.PANEL_EDGE, 16, 2))

	var preview := BlamePot.new()
	preview.setup_preview(pot, 0.62)
	preview.position = Vector2(78.0, card.custom_minimum_size.y * 0.5)
	card.add_child(preview)

	var name_color := Palette.UI_TEXT if unlocked else Palette.UI_TEXT_DIM
	var title := UiKit.label("%s　%s" % [pot.display_name, pot.difficulty_stars()], UiKit.FONT_H2,
		name_color)
	title.position = Vector2(140.0, 8.0)
	title.size = Vector2(_size.x * 0.5, 34.0)
	card.add_child(title)

	var tagline := UiKit.label(pot.hint, UiKit.FONT_SMALL, Palette.UI_TEXT_DIM)
	tagline.position = Vector2(140.0, 44.0)
	tagline.size = Vector2(_size.x * 0.55, 26.0)
	card.add_child(tagline)

	var stats := UiKit.label("伤害 %d　飘移 %.0f　跟手 %.0f　存活 %.1fs" % [
		pot.damage_charged if pot.needs_charge else pot.damage,
		pot.drift_speed, pot.drag_follow, pot.life_seconds], UiKit.FONT_TINY,
		Palette.UI_TEXT_DIM)
	stats.position = Vector2(140.0, 72.0)
	stats.size = Vector2(_size.x * 0.6, 24.0)
	card.add_child(stats)

	var progress := ProgressManager.unlock_progress(pot.id)
	if not unlocked:
		var lock := UiKit.label("未解锁：%s（%d / %d）" % [
			str(progress["label"]), int(progress["current"]), int(progress["target"])],
			UiKit.FONT_TINY, Palette.ACCENT)
		lock.position = Vector2(140.0, 96.0)
		lock.size = Vector2(_size.x * 0.55, 24.0)
		card.add_child(lock)
	else:
		var toggle := UiKit.button("上场", UiKit.FONT_TINY,
			Palette.OK if ProgressManager.is_pot_enabled(pot.id) else Palette.PANEL_EDGE)
		toggle.toggle_mode = true
		toggle.button_pressed = ProgressManager.is_pot_enabled(pot.id)
		toggle.text = "上场：是" if toggle.button_pressed else "上场：否"
		toggle.position = Vector2(_size.x * 0.62, 74.0)
		toggle.size = Vector2(130.0, 44.0)
		toggle.toggled.connect(func(on: bool) -> void:
			ProgressManager.set_pot_enabled(pot.id, on)
			refresh())
		card.add_child(toggle)
	return card
