extends BlameTestBase
## 构图专项测试：把「谁占哪一块」这件事当成可验证的约束。
##
## 覆盖四种屏幕比例（设计尺寸 / iPhone 逻辑分辨率 / 高长屏 / 桌面宽窗口），逐一验证：
##   - 老板整体落在办公室空间内，头顶不压 HUD、桌沿贴着地板线；
##   - 窗户与白板挂在墙上、不被老板压住、白板与头不重叠；
##   - 甩锅操作区完全在桌沿下方、够大、不超出屏幕；
##   - 顶部 / 底部 HUD 不遮挡老板和操作区，文字不超出自己那一格、不超出屏幕；
##   - 五种锅都能在「握持时限」内从操作区拖到老板身上；
##   - 疯狂甩锅时间同屏 6 口锅时每一口都还能抓到。

## 设计尺寸 / iPhone 逻辑分辨率 / 高长屏（19.5:9）/ 桌面宽窗口
const SCREENS := [
	Vector2(720, 1280),
	Vector2(390, 844),
	Vector2(720, 1558),
	Vector2(2275, 1280),
]


func run_tests() -> void:
	suite_name = "构图与空间层级"
	for size in SCREENS:
		_test_layout_invariants(size)
		_test_hud_fits(size)
	_test_game_space_matches_layout()
	_test_all_pots_reachable()
	_test_frenzy_still_operable()
	free_game()


func _label_for(size: Vector2) -> String:
	return "%d×%d" % [int(size.x), int(size.y)]


func _test_layout_invariants(size: Vector2) -> void:
	var layout := LayoutData.compute(size)
	var invariants := LayoutData.invariants(layout)
	var failed: Array = []
	for entry in invariants:
		if not bool(entry["ok"]):
			failed.append(str(entry["name"]))
	_check("[%s] 空间关系全部成立（老板 / 桌子 / 地板 / 挂件 / 操作区 / HUD）" % _label_for(size),
		failed.is_empty(), str(failed))

	var field: Rect2 = layout["field"]
	var hud: Rect2 = layout["hud"]
	var bottom: Rect2 = layout["bottom"]
	var content: Rect2 = layout["content_rect"]
	_check("[%s] 内容列居中且不超出屏幕" % _label_for(size),
		content.position.x >= -0.5 and content.end.x <= size.x + 0.5,
		str(content))
	_check("[%s] 操作区高度不低于屏高的 40%%、宽度不低于内容列的 85%%" % _label_for(size),
		field.size.y >= size.y * 0.40 and field.size.x >= content.size.x * 0.85,
		"%.0f×%.0f" % [field.size.x, field.size.y])
	_check("[%s] 顶部 HUD 与底部信息条都不压操作区" % _label_for(size),
		hud.end.y < field.position.y and bottom.position.y >= field.end.y - 0.5,
		"HUD 到 %.0f，操作区从 %.0f 开始，操作区到 %.0f，底部从 %.0f 开始" % [
			hud.end.y, field.position.y, field.end.y, bottom.position.y])
	_check("[%s] 老板受击圈完全在操作区上方（拖上去就能命中，不会误触）" % _label_for(size),
		float(layout["boss_center"].y) + float(layout["hit_radius"]) < field.position.y,
		"受击圈下沿 %.0f / 操作区上沿 %.0f" % [
			float(layout["boss_center"].y) + float(layout["hit_radius"]), field.position.y])


func _test_hud_fits(size: Vector2) -> void:
	var layout := LayoutData.compute(size)
	var hud := BlameHud.new()
	add_child(hud)
	hud.configure(size, layout)
	# 填上真实内容（文字长度会影响是否超格）
	hud.set_time_left(42.0)
	hud.set_score(12345)
	hud.set_combo(23)
	hud.set_stats(41, 3)
	hud.set_boss(198, 260, "愤怒", Palette.DANGER)
	hud.set_boss_line("今天非开掉你不可！")
	hud.set_phase("疯狂甩锅")
	hud.set_hint(GameConfig.READY_HINT)
	hud.show_banner("疯狂甩锅时间！")
	hud.show_shout("老板开始慌了！")
	hud.show_toast("手滑了！")
	var outside: Array = []
	var overflowing: Array = []
	for node in hud.text_nodes():
		var control := node as Control
		if control == null:
			continue
		var rect := Rect2(control.position, control.size)
		if rect.position.x < -0.5 or rect.end.x > size.x + 0.5 \
				or rect.position.y < -0.5 or rect.end.y > size.y + 0.5:
			outside.append("%s(%s)" % [control.name, str(rect)])
		var text := _control_text(control)
		if text.is_empty():
			continue
		var font := control.get_theme_font("font")
		var font_size := control.get_theme_font_size("font_size")
		for line in text.split("\n"):
			if line.is_empty():
				continue
			var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			# 按钮有自己的内边距，放宽一点
			var limit := control.size.x + (18.0 if control is Button else 2.0)
			if width > limit:
				overflowing.append("%s「%s」%.0f>%.0f" % [control.name, line, width, limit])
	_check("[%s] HUD 所有文字控件都在屏幕内" % _label_for(size), outside.is_empty(), str(outside))
	_check("[%s] HUD 文字不会超出自己那一格（不会被裁切）" % _label_for(size),
		overflowing.is_empty(), str(overflowing))
	hud.queue_free()


func _test_game_space_matches_layout() -> void:
	var game := make_game()
	var layout := game.layout_data()
	var field := game.field_rect()
	_check("游戏场景用的就是同一份空间预算",
		not layout.is_empty() and field.is_equal_approx(layout["field"]), str(field))
	_check("老板位置来自空间预算（不是硬编码）",
		game.boss().position.is_equal_approx(layout["boss_center"]),
		"%s / %s" % [str(game.boss().position), str(layout["boss_center"])])
	_check("老板受击圈大小跟着老板走（不是跟着屏幕短边走）",
		_near(game.boss().hit_radius(), float(layout["hit_radius"]), 0.5),
		"%.0f / %.0f" % [game.boss().hit_radius(), float(layout["hit_radius"])])
	_check("老板头顶在老板状态条下面（HUD 不压人物）",
		game.boss().position.y - BlameBoss.BASE_RADIUS * 0.0 - game.boss().body_radius() * 1.45
		>= (layout["boss_bar"] as Rect2).end.y,
		"头顶 %.0f / 状态条下沿 %.0f" % [
			game.boss().position.y - game.boss().body_radius() * 1.45,
			(layout["boss_bar"] as Rect2).end.y])
	_check("办公桌下沿贴着地板线",
		absf((game.boss().position.y + game.boss().body_radius() * 1.85)
			- float(layout["floor_y"])) <= 12.0,
		"桌沿 %.0f / 地板 %.0f" % [
			game.boss().position.y + game.boss().body_radius() * 1.85, float(layout["floor_y"])])


func _test_all_pots_reachable() -> void:
	var game := make_game()
	skip_countdown(game)
	var layout := game.layout_data()
	var field: Rect2 = layout["field"]
	var hit_center := game.boss().hit_center()
	var hit_radius := game.boss().hit_radius()
	var problems: Array = []
	for pot in PotData.catalog():
		# 从操作区里离老板最远的那个角开始拖：需要多少秒才进入受击圈
		var corner := Vector2(field.position.x + field.size.x * 0.5, field.end.y - 8.0)
		var distance := corner.distance_to(hit_center)
		var reach := log(maxf(distance / maxf(hit_radius, 1.0), 1.001)) / maxf(pot.drag_follow, 0.5)
		if reach > pot.hold_window * 0.55:
			problems.append("%s 需要 %.2fs（握持上限 %.1fs）" % [pot.display_name, reach,
				pot.hold_window])
		# 抓取判定圈必须比锅本身大（手指点在锅上就能抓到）
		if pot.grab_radius < pot.body_radius:
			problems.append("%s 判定圈比锅还小" % pot.display_name)
	_check("五种锅都能在握持时限内从操作区拖到老板身上（最慢的铁锅也只要不到一半时限）",
		problems.is_empty(), str(problems))

	# 真的抓一次：在操作区最远的角放一口锅，点一下必须能抓住
	var pot := game.place_pot("iron", Vector2(field.position.x + field.size.x * 0.5,
		field.end.y - 8.0))
	game.pointer_press(pot.global_position, 0)
	_check("操作区最下方的锅也能一次点中", game.held_pot() == pot)
	game.pointer_release(pot.global_position, 0)


func _test_frenzy_still_operable() -> void:
	var game := make_game()
	skip_countdown(game)
	advance(game, 38.0, 0.1)
	_check("已经进入疯狂甩锅时间", game.phase_name() == "疯狂甩锅", game.phase_name())
	game.clear_pots()
	var spawned: Array[BlamePot] = []
	for id in ["normal", "iron", "pan", "pressure", "broken", "normal"]:
		var pot := game.place_pot(id, game.field_rect().get_center()
			+ Vector2(randf_range(-120.0, 120.0), randf_range(-120.0, 120.0)))
		if pot != null:
			spawned.append(pot)
	_check("疯狂阶段能同屏放下 6 口锅", spawned.size() == 6, str(spawned.size()))
	var inside := true
	for pot in spawned:
		if not game.field_rect().grow(20.0).has_point(pot.global_position):
			inside = false
	_check("疯狂阶段的锅都在操作区内（没有跑到 HUD 或底部信息条里）", inside)
	var grabbed := 0
	for pot in spawned:
		if pot.can_grab() and pot.catches_point(pot.global_position):
			grabbed += 1
	_check("疯狂阶段每一口锅都还能点中", grabbed == spawned.size(),
		"%d / %d" % [grabbed, spawned.size()])


# ---------------------------------------------------------------- 工具

func _control_text(control: Control) -> String:
	if control is Label:
		return (control as Label).text
	if control is Button:
		return (control as Button).text
	return ""
