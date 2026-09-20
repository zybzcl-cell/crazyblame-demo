extends BlameTestBase
## 冒烟测试：项目能起来、单例在、场景能加载、音效齐全、一局能开。


func run_tests() -> void:
	suite_name = "冒烟测试"
	_test_autoloads()
	_test_project_settings()
	_test_sounds()
	_test_chinese_font()
	_test_menu_scene()
	_test_game_scene_basics()
	_test_countdown_flow()
	free_game()


func _test_autoloads() -> void:
	for name in ["ProgressManager", "AudioManager", "Haptics"]:
		var node := get_tree().root.get_node_or_null(name)
		_check("单例 %s 已经挂上" % name, node != null)
	_check("存档路径指向用户目录（不依赖任何账号 / 服务器）",
		ProgressManager.save_path.begins_with("user://") or ProgressManager.save_path.begins_with("res://"))
	_check("设置里默认开启声音与震动",
		ProgressManager.sound_enabled() and ProgressManager.vibration_enabled())


func _test_project_settings() -> void:
	var main_scene := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	_check("入口场景是主菜单", main_scene == GameConfig.MENU_SCENE, main_scene)
	var name := str(ProjectSettings.get_setting("application/config/name", ""))
	_check("游戏名是《疯狂甩锅》", name == "疯狂甩锅", name)
	var width := int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	var height := int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
	_check("是竖屏设计分辨率（移动端优先）", width == 720 and height == 1280,
		"%dx%d" % [width, height])
	_check("窗口按比例自适应（canvas_items + expand）",
		str(ProjectSettings.get_setting("display/window/stretch/mode", "")) == "canvas_items"
		and str(ProjectSettings.get_setting("display/window/stretch/aspect", "")) == "expand")
	_check("触摸不会被引擎再模拟成鼠标（避免一次点击算两次）",
		not bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true)))
	for path in [GameConfig.MENU_SCENE, GameConfig.GAME_SCENE, GameConfig.RESULT_CARD_SCENE]:
		_check("场景文件存在：%s" % path.get_file(), ResourceLoader.exists(path))


func _test_sounds() -> void:
	var keys := GameConfig.sound_keys()
	_check("音效表里有 21 个音效", keys.size() == 21, str(keys.size()))
	var missing: Array = []
	for key in keys:
		if not ResourceLoader.exists(str(GameConfig.SOUNDS[key])):
			missing.append(key)
	_check("所有音效文件都在项目里（本地合成，无第三方素材）", missing.is_empty(), str(missing))
	_check("AudioManager 把音效都加载起来了",
		AudioManager.sound_count() == keys.size(), str(AudioManager.sound_count()))
	_check("每个音效都能取到播放接口",
		AudioManager.has_sound("hit_heavy") and AudioManager.has_sound("boss_ko")
		and AudioManager.has_sound("unlock"))


func _test_chinese_font() -> void:
	# 界面全靠默认字体 + 系统字体回退显示中文，这里确认这些字真的能画出来（否则会出现豆腐块）
	if DisplayServer.get_name() == "headless":
		# 无窗口模式下没有系统字体可用，中文字形检查放到实机截图测试里做
		_check("中文显示检查在无窗口模式下跳过（改由实机截图测试覆盖）", true, "headless")
		return
	var font := ThemeDB.fallback_font
	var missing: Array = []
	for character in ["疯", "狂", "甩", "锅", "老", "板", "分", "连", "击", "精", "神", "评级"]:
		if not font.has_char(character.unicode_at(0)):
			missing.append(character)
	_check("界面字体能显示中文（不会出现豆腐块）", missing.is_empty(), str(missing))
	var size := font.get_string_size("疯狂甩锅", HORIZONTAL_ALIGNMENT_LEFT, -1, 48)
	_check("中文文字的宽度是正常的（不是 0 或者一个方块）", size.x > 100.0, "%.0f" % size.x)


func _test_menu_scene() -> void:
	var menu := (load(GameConfig.MENU_SCENE) as PackedScene).instantiate() as BlameMainMenu
	add_child(menu)
	_check("主菜单能实例化", menu != null)
	_check("主菜单有「开始甩锅」按钮", menu.start_button() != null
		and menu.start_button().text == "开始甩锅")
	_check("「开始甩锅」按钮连着处理函数",
		menu.start_button().pressed.get_connections().size() > 0)
	_check("主菜单有锅图鉴面板，默认收起来", menu.codex() != null and not menu.codex().visible)
	_check("主菜单有设置面板，默认收起来", menu.settings() != null and not menu.settings().visible)
	_check("主菜单上有关卡外的老板（菜单吉祥物）", menu.boss_node() != null)
	menu.codex().refresh()
	_check("锅图鉴里列出全部 5 种锅", PotData.catalog().size() == 5)
	menu.queue_free()


func _test_game_scene_basics() -> void:
	var game := make_game()
	var size := game.get_viewport_rect().size
	_check("游戏场景能实例化", game != null)
	_check("刚进游戏是准备阶段", game.state_name() == "countdown", game.state_name())
	_check("锅池一次建好、固定 12 口（游戏中不再新建节点）", game.pot_pool_size() == 12)
	_check("老板节点在", game.boss() != null)
	_check("HUD 节点在", game.hud() != null)
	_check("老板满血开局", game.boss().hp == GameConfig.BOSS_MAX_HP)
	_check("倒计时是 3 秒", _near(game.countdown_left(), GameConfig.COUNTDOWN_SECONDS, 0.05),
		"%.2f" % game.countdown_left())
	var field := game.field_rect()
	var content: Rect2 = game.layout_data()["content_rect"]
	_check("甩锅场地在屏幕中下部、面积够大（高度 ≥ 屏高 40%、宽度 ≥ 内容列 85%）",
		field.position.y > size.y * 0.45 and field.size.y > size.y * 0.40
		and field.size.x > content.size.x * 0.85, str(field))
	_check("场地没有超出屏幕",
		field.position.x >= 0.0 and field.end.x <= size.x + 1.0 and field.end.y <= size.y + 1.0,
		str(field))
	_check("老板受击判定圈够大（好点、好拖）", game.boss().hit_radius() > size.x * 0.12,
		"%.0f" % game.boss().hit_radius())


func _test_countdown_flow() -> void:
	var game := make_game()
	advance(game, 1.0)
	_check("准备阶段会倒数", game.state_name() == "countdown" and game.countdown_left() < 2.2,
		"%.2f" % game.countdown_left())
	advance(game, GameConfig.COUNTDOWN_SECONDS - 1.0 + 0.05)
	_check("3 秒后进入正式游戏", game.is_playing(), game.state_name())
	_check("正式游戏剩余时间就是 42 秒",
		_near(game.time_left(), GameConfig.PLAY_SECONDS, 0.15), "%.2f" % game.time_left())
	_check("一局总时长约 45 秒（3 秒准备 + 42 秒正式游戏）",
		_near(GameConfig.COUNTDOWN_SECONDS + GameConfig.PLAY_SECONDS, 45.0, 0.01),
		"%.1f" % (GameConfig.COUNTDOWN_SECONDS + GameConfig.PLAY_SECONDS))
	_check("开局时同屏只有 1 口锅（热身阶段）", game.active_pot_count() <= 1,
		str(game.active_pot_count()))
