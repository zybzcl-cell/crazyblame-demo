class_name ResultCard
extends Control
## 结算卡：本局总分、老板收到多少伤害、命中 / 失误、最高连击、各锅使用次数、评级。
##
## 评级不是「命中几次」决定的：命中率、连击、伤害、疯狂阶段表现、锅的难度五项加权算 0~100，
## 再换算成 S / A / B / C / D，所以稳健型和暴力型打法会看到不同的分数结构。

signal restart_requested
signal menu_requested

var _dim: ColorRect
var _panel: Panel
var _title: Label
var _grade: Label
var _grade_title: Label
var _score: Label
var _record: Label
var _boss_state: Label
var _stats: Label
var _pots: Label
var _unlock: Label
var _restart_button: Button
var _menu_button: Button
var _size := Vector2(720.0, 1280.0)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_layout(_size)
	visible = false


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.05, 0.06, 0.09, 0.72)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_panel = Panel.new()
	_panel.add_theme_stylebox_override("panel", UiKit.panel_style(
		Palette.PANEL, Palette.ACCENT.darkened(0.2), 24, 3))
	add_child(_panel)

	_grade = UiKit.centered_label("A", 96, Palette.ACCENT)
	_grade_title = UiKit.centered_label("甩锅高手", UiKit.FONT_H2, Palette.UI_TEXT)
	_title = UiKit.centered_label("本局结算", UiKit.FONT_SMALL, Palette.UI_TEXT_DIM)
	_score = UiKit.centered_label("0", 58, Palette.ACCENT)
	_record = UiKit.centered_label("", UiKit.FONT_BODY, Palette.OK)
	_boss_state = UiKit.centered_label("", UiKit.FONT_H2, Palette.DANGER)
	_stats = UiKit.centered_label("", UiKit.FONT_BODY, Palette.UI_TEXT)
	_pots = UiKit.centered_label("", UiKit.FONT_SMALL, Palette.UI_TEXT_DIM)
	_unlock = UiKit.centered_label("", UiKit.FONT_BODY, Palette.OK)
	_restart_button = UiKit.button("再甩一局", UiKit.FONT_H2, Palette.ACCENT)
	_menu_button = UiKit.button("返回菜单", UiKit.FONT_BODY, Palette.INFO)
	_restart_button.pressed.connect(func() -> void: restart_requested.emit())
	_menu_button.pressed.connect(func() -> void: menu_requested.emit())
	for node in [_grade, _grade_title, _title, _score, _record, _boss_state, _stats,
			_pots, _unlock, _restart_button, _menu_button]:
		_panel.add_child(node)


func configure(size: Vector2) -> void:
	_layout(size)


func _layout(size: Vector2) -> void:
	_size = size
	if _panel == null:
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.size = size
	_dim.position = Vector2.ZERO
	var panel_w := minf(size.x * 0.90, 620.0)
	var panel_h := minf(size.y * 0.86, 1000.0)
	var origin := Vector2((size.x - panel_w) * 0.5, (size.y - panel_h) * 0.5)
	_panel.position = origin
	_panel.size = Vector2(panel_w, panel_h)
	UiKit.rescale_ui(self, float(LayoutData.compute(size)["ui_scale"]))
	var pad := panel_w * 0.08
	var y := 18.0
	_place(_title, origin, pad, y, panel_w - pad * 2.0, 28.0)
	y += 30.0
	_place(_grade, origin, pad, y, panel_w - pad * 2.0, 110.0)
	y += 112.0
	_place(_grade_title, origin, pad, y, panel_w - pad * 2.0, 36.0)
	y += 42.0
	_place(_score, origin, pad, y, panel_w - pad * 2.0, 70.0)
	y += 72.0
	_place(_record, origin, pad, y, panel_w - pad * 2.0, 30.0)
	y += 38.0
	_place(_boss_state, origin, pad, y, panel_w - pad * 2.0, 38.0)
	y += 46.0
	_place(_stats, origin, pad, y, panel_w - pad * 2.0, panel_h * 0.26)
	y += panel_h * 0.27
	_place(_pots, origin, pad, y, panel_w - pad * 2.0, panel_h * 0.14)
	y += panel_h * 0.15
	_place(_unlock, origin, pad, y, panel_w - pad * 2.0, 32.0)
	_restart_button.position = origin + Vector2(pad, panel_h - 132.0)
	_restart_button.size = Vector2(panel_w - pad * 2.0, 62.0)
	_menu_button.position = origin + Vector2(pad, panel_h - 62.0)
	_menu_button.size = Vector2(panel_w - pad * 2.0, 46.0)


func _place(node: Control, origin: Vector2, x: float, y: float, w: float, h: float) -> void:
	node.position = origin + Vector2(x, y)
	node.size = Vector2(w, h)


func show_result(result: Dictionary) -> void:
	var grade := str(result.get("rating_grade", "D"))
	var rating := int(result.get("rating_score", 0))
	_grade.text = grade
	_grade.add_theme_color_override("font_color", Score.grade_color(grade))
	_grade_title.text = "%s　综合评级 %d / 100" % [
		str(result.get("rating_title", "")), rating]
	_score.text = "%d 分" % int(result.get("score_points", 0))
	var new_best := bool(result.get("new_best", false))
	if new_best:
		_record.text = "新纪录！上一局最好成绩 %d 分" % int(result.get("previous_best", 0))
		_record.add_theme_color_override("font_color", Palette.ACCENT)
	else:
		_record.text = "历史最高 %d 分" % maxi(
			int(result.get("previous_best", 0)), int(result.get("score_points", 0)))
		_record.add_theme_color_override("font_color", Palette.UI_TEXT_DIM)
	_boss_state.text = "老板最终状态：%s" % str(result.get("boss_stage_name", ""))
	var hits := int(result.get("hits", 0))
	var misses := int(result.get("misses", 0))
	var accuracy := float(result.get("accuracy", 0.0)) * 100.0
	var seconds := float(result.get("duration", 0.0))
	var end_text := "老板被打到崩溃" if str(result.get("end_reason", "")) == "ko" else "45 秒时间到"
	_stats.text = "\n".join([
		"老板受到伤害：%d（剩余精神 %d / %d）" % [
			int(result.get("damage_dealt", 0)), int(result.get("boss_hp_left", 0)),
			int(result.get("boss_hp_max", 1))],
		"命中 %d 　　失误 %d 　　命中率 %.0f%%" % [hits, misses, accuracy],
		"最高连击 %d 　　疯狂阶段命中 %d" % [
			int(result.get("best_combo", 0)), int(result.get("frenzy_hits", 0))],
		"本局时长 %.1f 秒　（%s）" % [seconds, end_text],
	])
	_pots.text = _pot_breakdown(result)
	var unlocked: Array = result.get("unlocked", [])
	if unlocked.is_empty():
		_unlock.text = ""
	else:
		var names: Array = []
		for id in unlocked:
			var pot := PotData.get_pot(str(id))
			if pot != null:
				names.append(pot.display_name)
		_unlock.text = "解锁新锅：%s" % "、".join(names)
	visible = true


func _pot_breakdown(result: Dictionary) -> String:
	var counts: Dictionary = result.get("pot_counts", {})
	var parts: Array = []
	for pot in PotData.catalog():
		var count := int(counts.get(pot.id, 0))
		if count > 0:
			parts.append("%s ×%d" % [pot.display_name, count])
	if parts.is_empty():
		return "一口锅都没甩回去……再试一次？"
	return "甩回的锅：" + "　".join(parts)


func restart_button() -> Button:
	return _restart_button


func menu_button() -> Button:
	return _menu_button


## 结算卡上所有会显示文字的控件（构图 / 字体测试用）
func text_nodes() -> Array:
	return [_title, _grade, _grade_title, _score, _record, _boss_state, _stats, _pots,
		_unlock, _restart_button, _menu_button]
