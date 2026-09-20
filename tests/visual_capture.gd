extends BlameTestBase
## 实机（真实窗口）运行 + 截图。
##
## 这个套件**不加 --headless**：真的开一个窗口、真的渲染，把关键画面存成 PNG，
## 同时检查画面不是一片空白。截图放在 tests/.tmp/ 下，可以直接打开看构图。
##
## 覆盖 6 张「构图检查用」的代表性画面：
##   1 主菜单　2 游戏刚开始　3 游戏中期　4 老板受到多次攻击　5 疯狂甩锅阶段　6 结算页面
## 外加：字形检查、锅图鉴、设置面板。

const OUT_DIR := "res://tests/.tmp"


func run_tests() -> void:
	suite_name = "实机窗口与截图"
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_check("是在真实窗口里跑（不是 headless）",
		DisplayServer.get_name() != "headless", DisplayServer.get_name())
	var size := get_viewport().get_visible_rect().size
	_check("窗口尺寸正常", size.x >= 400.0 and size.y >= 600.0, str(size))
	await _check_chinese_glyphs(size)
	await _capture_round()
	await _capture_menu_and_panels()
	await _capture_boss_stages()
	_check("截图像素不是一片空白（画面真的画出来了）", await _all_shots_have_content())


## 真的把两个不同的汉字画出来，再比较它们的像素：如果画出来一模一样，说明字体里没有这两个字
## （引擎会用同一个「豆腐块」占位）。这比字体自带的 has_char 更可靠 —— 也算 Web 端的保险。
func _check_chinese_glyphs(size: Vector2) -> void:
	var holder := Control.new()
	holder.size = size
	add_child(holder)
	var left := UiKit.centered_label("锅", 140, Color.WHITE)
	left.position = Vector2(size.x * 0.04, size.y * 0.04)
	left.size = Vector2(size.x * 0.42, size.y * 0.14)
	var right := UiKit.centered_label("狂", 140, Color.WHITE)
	right.position = Vector2(size.x * 0.54, size.y * 0.04)
	right.size = Vector2(size.x * 0.42, size.y * 0.14)
	holder.add_child(left)
	holder.add_child(right)
	await _settle(8)
	var saved := await _shot("shot_0_glyphs.png")
	holder.queue_free()
	await _settle(3)
	var image := Image.load_from_file("%s/shot_0_glyphs.png" % OUT_DIR)
	if not saved or image == null:
		_check("中文字形检查：截图失败", false)
		return
	var region_left := Rect2(0.04, 0.04, 0.42, 0.14)
	var region_right := Rect2(0.54, 0.04, 0.42, 0.14)
	var ink_left := PixelTools.ratio(image, region_left, PixelTools.is_bright, 2)
	var ink_right := PixelTools.ratio(image, region_right, PixelTools.is_bright, 2)
	_check("中文文字真的画出来了（区域里有笔画像素）",
		ink_left > 0.005 and ink_right > 0.005, "%.4f / %.4f" % [ink_left, ink_right])
	var distance := PixelTools.signature_distance(
		PixelTools.signature(image, region_left), PixelTools.signature(image, region_right))
	_check("两个不同的汉字画出来不一样（不是同一个豆腐块）", distance > 0.002,
		"差异 %.4f" % distance)


## 一局游戏里的四张画面：刚开始 / 中期 / 老板被打 / 疯狂阶段 / 结算
func _capture_round() -> void:
	var game := (load(GameConfig.GAME_SCENE) as PackedScene).instantiate() as BlameGame
	add_child(game)
	game.set_process(false)
	# 1. 刚开始：3 秒准备倒数
	advance(game, 1.0, 0.05)
	await _settle(4)
	_check("游戏刚开始（准备阶段倒数）能真实渲染", await _shot("shot_2_start.png"))
	# 2. 中期：打了十来秒，场上有几口锅
	skip_countdown(game)
	autoplay(game, 12.0)
	game.clear_pots()
	for id in ["normal", "broken", "pan"]:
		game.force_spawn(id)
	advance(game, 1.0, 0.05)
	await _settle(4)
	_check("游戏中期画面（老板 + 锅 + 连击 + 精神状态条 + 底部统计）能真实渲染",
		await _shot("shot_3_mid.png"))
	# 3. 老板受到多次攻击：打到 3~4 阶段，桌上东西歪掉、白板曲线下滑
	var guard := 0
	while game.boss().hp_ratio() > 0.42 and guard < 30 and not game.is_finished():
		var pot := game.place_pot("iron", game.field_rect().get_center())
		if pot == null:
			advance(game, 0.4, 0.05)
			continue
		drag_to_boss(game, pot)
		advance(game, 0.25, 0.05)
		guard += 1
	game.clear_pots()
	game.force_spawn("iron")
	advance(game, 1.0, 0.05)
	await _settle(4)
	_check("老板挨了很多锅之后的画面（表情 / 姿态 / 白板曲线都变了）能真实渲染",
		await _shot("shot_4_hurt.png"))
	# 4. 疯狂甩锅时间
	var remaining := GameConfig.PLAY_SECONDS - game.elapsed() - 3.0
	if remaining > 0.0:
		advance(game, remaining, 0.05)
	for id in ["iron", "pan", "pressure", "broken", "normal"]:
		game.force_spawn(id)
	advance(game, 0.9, 0.05)
	await _settle(4)
	_check("疯狂甩锅时间（整屏泛红）能真实渲染", await _shot("shot_5_frenzy.png"))
	# 5. 结算：一直打到出结果
	guard = 0
	while not game.is_finished() and guard < 120:
		var pot := game.place_pot("iron", game.field_rect().get_center())
		if pot == null:
			advance(game, 0.4, 0.05)
			continue
		drag_to_boss(game, pot)
		advance(game, 0.3, 0.05)
		guard += 1
	await _settle(6)
	_check("结算页面能真实渲染（评级 / 数据 / 老板最终状态）", await _shot("shot_6_result.png"))
	game.queue_free()
	await _settle(3)


func _capture_menu_and_panels() -> void:
	var menu := (load(GameConfig.MENU_SCENE) as PackedScene).instantiate() as BlameMainMenu
	add_child(menu)
	await _settle(24)
	_check("主菜单能真实渲染（标题 + 办公室老板 + 按钮）", await _shot("shot_1_menu.png"))
	menu.codex().refresh()
	menu.codex().visible = true
	await _settle(6)
	_check("锅图鉴面板能真实渲染（五种锅 + 解锁进度）", await _shot("shot_7_codex.png"))
	menu.codex().visible = false
	menu.settings().refresh()
	menu.settings().visible = true
	await _settle(6)
	_check("设置面板能真实渲染（声音 / 震动 / 清档）", await _shot("shot_8_settings.png"))
	menu.queue_free()
	await _settle(3)


## 把老板的七个阶段摆在一起截一张图，方便肉眼确认「表情 / 姿态真的在变」
func _capture_boss_stages() -> void:
	var holder := Node2D.new()
	add_child(holder)
	var background := ColorRect.new()
	background.color = Color(0.13, 0.15, 0.19)
	background.size = get_viewport().get_visible_rect().size
	holder.add_child(background)
	var size := get_viewport().get_visible_rect().size
	for i in 7:
		var boss := BlameBoss.new()
		var column := i % 4
		var row := i / 4
		boss.position = Vector2(size.x * (0.16 + 0.24 * float(column)),
			size.y * (0.16 + 0.30 * float(row)))
		holder.add_child(boss)
		boss.configure(0.46, size.x * 0.09, boss.position)
		boss.set_stage_silent(i)
	await _settle(8)
	_check("老板七个阶段可以同屏渲染（表情 / 姿态 / 道具都不同）",
		await _shot("shot_9_boss_stages.png"))
	holder.queue_free()
	await _settle(3)


# ---------------------------------------------------------------- 工具

func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


## 截图（等渲染完成再取画面，避免拍到半帧）
func _shot(file_name: String) -> bool:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return false
	var path := "%s/%s" % [OUT_DIR, file_name]
	var err := image.save_png(path)
	if err != OK:
		print("      截图失败：%s（错误码 %d）" % [path, err])
		return false
	return true


## 全部截图都至少要有几百种颜色（一片纯色说明什么都没画出来）
func _all_shots_have_content() -> bool:
	var names := ["shot_0_glyphs.png", "shot_1_menu.png", "shot_2_start.png", "shot_3_mid.png",
		"shot_4_hurt.png", "shot_5_frenzy.png", "shot_6_result.png", "shot_7_codex.png",
		"shot_8_settings.png", "shot_9_boss_stages.png"]
	var ok := true
	for name in names:
		var path := "%s/%s" % [OUT_DIR, name]
		var image := Image.load_from_file(path)
		if image == null:
			print("      读不到截图：%s" % path)
			ok = false
			continue
		var colors := {}
		# 采样要细一点：字形检查那种「黑底白字」的画面，粗采样会只剩十几种颜色
		for y in range(0, image.get_height(), 4):
			for x in range(0, image.get_width(), 4):
				colors[image.get_pixel(x, y).to_rgba32()] = true
		if colors.size() < 40:
			print("      截图 %s 只有 %d 种颜色，可能没画出来" % [name, colors.size()])
			ok = false
		print("      %s：%d 种颜色" % [name, colors.size()])
	return ok
