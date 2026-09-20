class_name BlameMainMenu
extends Control
## 主菜单：标题、开始按钮、最高分、锅图鉴、设置。
##
## 菜单上还有一个「吉祥物老板」：他没血条，但会随着你历史最好成绩换表情 ——
## 打得越好，他在菜单里就越蔫（最高评级 S 时会直接趴桌上）。

@onready var _background: OfficeBackground = $World/Background
@onready var _boss: BlameBoss = $World/Boss
@onready var _prop: MenuProp = $World/Prop

var _title: Label
var _subtitle: Label
var _stats: Label
var _hint: Label
var _start_button: Button
var _codex_button: Button
var _settings_button: Button
var _quit_button: Button
var _codex: PotCodex
var _settings: SettingsPanel
var _size := Vector2(720.0, 1280.0)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_layout(get_viewport_rect().size)
	get_viewport().size_changed.connect(_on_viewport_resized)
	_prop.impact.connect(_on_prop_impact)
	ProgressManager.progress_changed.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	_boss.tick(delta)
	_background.tick(delta)
	_prop.tick(delta)


func _build() -> void:
	_title = UiKit.centered_label("疯狂甩锅", 86, Palette.ACCENT)
	_subtitle = UiKit.centered_label("老板甩过来的锅，一口一口甩回去", UiKit.FONT_H2, Palette.UI_TEXT)
	_stats = UiKit.centered_label("", UiKit.FONT_BODY, Palette.UI_TEXT_DIM)
	_hint = UiKit.centered_label(
		"玩法：点住锅 → 拖到老板身上（或朝老板快速甩出去）\n45 秒一局　看谁先把老板的精神状态打空",
		UiKit.FONT_SMALL, Palette.UI_TEXT_DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_start_button = UiKit.button("开始甩锅", 40, Palette.ACCENT)
	_codex_button = UiKit.button("锅图鉴", UiKit.FONT_BODY, Palette.INFO)
	_settings_button = UiKit.button("设置", UiKit.FONT_BODY, Palette.INFO)
	_quit_button = UiKit.button("退出游戏", UiKit.FONT_SMALL, Palette.PANEL_EDGE)
	for node in [_title, _subtitle, _stats, _hint, _start_button, _codex_button,
			_settings_button, _quit_button]:
		add_child(node)
	_start_button.pressed.connect(_on_start)
	_codex_button.pressed.connect(_on_codex)
	_settings_button.pressed.connect(_on_settings)
	_quit_button.pressed.connect(_on_quit)

	_codex = PotCodex.new()
	add_child(_codex)
	_codex.closed.connect(_close_panels)
	_settings = SettingsPanel.new()
	add_child(_settings)
	_settings.closed.connect(_close_panels)


func _layout(size: Vector2) -> void:
	_size = size
	if _title == null:
		return
	# 菜单沿用游戏里同一套空间预算：标题在上、老板坐在办公室里、下半屏放按钮
	var layout := LayoutData.compute(size)
	var content: Rect2 = layout["content_rect"]
	var pad := content.size.x * 0.10
	var width := content.size.x - pad * 2.0
	var x := content.position.x + pad
	UiKit.rescale_ui(self, float(layout["ui_scale"]))
	_title.position = Vector2(x, size.y * 0.048)
	_title.size = Vector2(width, size.y * 0.095)
	_subtitle.position = Vector2(x, size.y * 0.140)
	_subtitle.size = Vector2(width, size.y * 0.040)
	_stats.position = Vector2(x, size.y * 0.592)
	_stats.size = Vector2(width, size.y * 0.048)
	_hint.position = Vector2(x, size.y * 0.640)
	_hint.size = Vector2(width, size.y * 0.085)
	_start_button.position = Vector2(x, size.y * 0.735)
	_start_button.size = Vector2(width, size.y * 0.072)
	var half := (width - content.size.x * 0.03) * 0.5
	_codex_button.position = Vector2(x, size.y * 0.824)
	_codex_button.size = Vector2(half, size.y * 0.056)
	_settings_button.position = Vector2(x + half + content.size.x * 0.03, size.y * 0.824)
	_settings_button.size = Vector2(half, size.y * 0.056)
	_quit_button.position = Vector2(x, size.y * 0.898)
	_quit_button.size = Vector2(width, size.y * 0.044)

	# 菜单里的老板比游戏里稍大一点（这里没有精神状态条占位置），但同样坐在桌后、桌腿压着地板
	var radius := float(layout["boss_radius"]) * 1.10
	var desk_bottom := float(layout["floor_y"]) + size.y * 0.004
	var boss_center := Vector2(size.x * 0.5, desk_bottom - radius * 1.85)
	_boss.configure_with_floor(radius / BlameBoss.BASE_RADIUS, radius * 1.3, boss_center,
		float(layout["floor_y"]))
	_background.configure(size, layout)
	_prop.configure(size, boss_center, float(layout["pot_scale"]))
	_codex.configure(size)
	_settings.configure(size)


func _on_viewport_resized() -> void:
	_layout(get_viewport_rect().size)


func _refresh() -> void:
	var summary := ProgressManager.summary()
	var grade := str(summary["best_grade"])
	var grade_text := "" if grade.is_empty() else "（%s 级）" % grade
	_stats.text = "最高分 %d%s　最高连击 %d　累计甩回 %d 口锅　命中率 %.0f%%" % [
		int(summary["best_score"]), grade_text, int(summary["best_combo"]),
		int(summary["returned"]), float(summary["accuracy"]) * 100.0]
	_boss.set_stage_silent(_menu_stage(int(summary["best_rating"])))
	_background.set_stress(1.0 - float(_menu_stage(int(summary["best_rating"]))) / 6.0)
	_codex.refresh()


## 历史成绩越好，菜单里的老板越惨
func _menu_stage(best_rating: int) -> int:
	if best_rating <= 0:
		return 0
	if best_rating >= 90:
		return 6
	if best_rating >= 78:
		return 5
	if best_rating >= 64:
		return 4
	if best_rating >= 48:
		return 3
	return 2


func _on_prop_impact() -> void:
	_boss.react_hit(PotData.get_pot("iron"), 0.5)


func _on_start() -> void:
	AudioManager.play("ui_start")
	get_tree().change_scene_to_file(GameConfig.GAME_SCENE)


func _on_codex() -> void:
	AudioManager.play("ui_click")
	_codex.refresh()
	_settings.visible = false
	_codex.visible = true


func _on_settings() -> void:
	AudioManager.play("ui_click")
	_settings.refresh()
	_codex.visible = false
	_settings.visible = true


func _close_panels() -> void:
	AudioManager.play("ui_click")
	_codex.visible = false
	_settings.visible = false


func _on_quit() -> void:
	get_tree().quit()


# ---------------------------------------------------------------- 测试接口

func start_button() -> Button:
	return _start_button


func codex() -> PotCodex:
	return _codex


func settings() -> SettingsPanel:
	return _settings


func boss_node() -> BlameBoss:
	return _boss


func menu_stage_for(rating: int) -> int:
	return _menu_stage(rating)
