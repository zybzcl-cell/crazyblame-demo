extends BlameTestBase
## 中文字体与文案测试（Web 版本能不能正确显示中文，靠这套守住）。
##
## 三件事：
##   1. 项目真的内嵌了一个中文子集字体，并且 project.godot 里设成了默认字体；
##   2. **静态扫描**：scripts/ 下所有源码里出现的非 ASCII 字符（中文、标点、★、× …）都能被这个字体画出来；
##   3. **运行时扫描**：把主菜单 / 游戏 HUD / 结算卡真的建出来，遍历所有 Label / Button 的文字逐字检查。
##
## 另外检查界面文案里没有 emoji —— Web 端没有 emoji 字体，emoji 会变成方框，
## 所以老板的表情改成「画出来的脸 + 阶段文字」，文案里不留 emoji。

const SCAN_DIRS := ["res://scripts", "res://tools"]


func run_tests() -> void:
	suite_name = "中文字体与文案"
	_test_embedded_font()
	_test_source_coverage()
	_test_no_emoji()
	await _test_runtime_text_coverage()


func _test_embedded_font() -> void:
	_check("项目内嵌了中文字体（Noto Sans SC，OFL 授权）",
		FileAccess.file_exists(Fonts.FONT_PATH), Fonts.FONT_PATH)
	_check("内嵌字体真的被用上了（不是退回引擎默认字体）", Fonts.is_embedded())
	_check("项目设置把内嵌字体设成默认界面字体",
		str(ProjectSettings.get_setting("gui/theme/custom_font", "")) == Fonts.FONT_PATH,
		str(ProjectSettings.get_setting("gui/theme/custom_font", "")))
	_check("字体许可证随项目一起分发（assets/fonts/OFL.txt）",
		FileAccess.file_exists("res://assets/fonts/OFL.txt"))
	_check("字体能画出中文（抽查）",
		Fonts.has_char("疯") and Fonts.has_char("锅") and Fonts.has_char("板")
		and Fonts.has_char("崩") and Fonts.has_char("溃"))
	_check("字体能画出界面里用到的符号",
		Fonts.has_char("×") and Fonts.has_char("★") and Fonts.has_char("·")
		and Fonts.has_char("—") and Fonts.has_char("％"))


## 把 scripts/ 与 tools/ 下所有源码里出现的非 ASCII 字符都收集起来，逐个确认字体能画
func _test_source_coverage() -> void:
	var characters := {}
	var files: Array = []
	for dir in SCAN_DIRS:
		_collect_gd_files(dir, files)
	_check("能读到项目源码（用于静态字形扫描）", files.size() >= 15, "%d 个文件" % files.size())
	for path in files:
		var text := _read_text(str(path))
		for i in text.length():
			var code := text.unicode_at(i)
			if code >= 0x2000:
				characters[code] = true
	var missing: Array = []
	for code in characters.keys():
		if not Fonts.has_char(String.chr(int(code))):
			missing.append(String.chr(int(code)) + "（U+%04X）" % int(code))
	_check("源码里出现的每个非 ASCII 字符都能被字体画出来（共 %d 种）" % characters.size(),
		missing.is_empty(), "缺字：%s" % str(missing))


func _test_no_emoji() -> void:
	var files: Array = []
	for dir in SCAN_DIRS:
		_collect_gd_files(dir, files)
	var offenders: Array = []
	for path in files:
		var text := _read_text(str(path))
		for i in text.length():
			var code := text.unicode_at(i)
			# 常见 emoji / 图形符号区段
			var is_emoji := (code >= 0x1F300 and code <= 0x1FAFF) \
				or (code >= 0x1F000 and code <= 0x1F2FF) \
				or (code >= 0x2600 and code <= 0x27BF and code != 0x2605 and code != 0x2606) \
				or code == 0xFE0F
			if is_emoji:
				offenders.append("%s：U+%04X" % [str(path).get_file(), code])
				break
	_check("界面文案里没有 emoji（Web 端没有 emoji 字体会变方框）",
		offenders.is_empty(), str(offenders))


## 真的把界面建出来，遍历所有文字控件逐字检查
func _test_runtime_text_coverage() -> void:
	var collected := {}
	var menu := (load(GameConfig.MENU_SCENE) as PackedScene).instantiate() as BlameMainMenu
	add_child(menu)
	menu.codex().refresh()
	menu.settings().refresh()
	_collect_control_text(menu, collected)
	_collect_control_text(menu.codex(), collected)
	_collect_control_text(menu.settings(), collected)
	menu.queue_free()

	var game := make_game()
	skip_countdown(game)
	autoplay(game, 6.0)
	_collect_control_text(game.hud(), collected)
	_collect_control_text(game.hud().result_card(), collected)
	free_game()

	var missing: Array = []
	for character in collected.keys():
		if not Fonts.has_char(str(character)):
			missing.append("%s（U+%04X）" % [str(character), str(character).unicode_at(0)])
	_check("主菜单 / HUD / 结算卡上实际显示的文字都能画出来（共 %d 种字符）" % collected.size(),
		missing.is_empty(), "缺字：%s" % str(missing))


# ---------------------------------------------------------------- 工具

func _collect_gd_files(dir: String, out: Array) -> void:
	var handle := DirAccess.open(dir)
	if handle == null:
		return
	handle.list_dir_begin()
	var entry := handle.get_next()
	while not entry.is_empty():
		var path := "%s/%s" % [dir, entry]
		if handle.current_is_dir():
			_collect_gd_files(path, out)
		elif entry.ends_with(".gd") and not entry.begins_with("."):
			out.append(path)
		entry = handle.get_next()
	handle.list_dir_end()


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


## 遍历一个 Control 子树，收集 Label / Button 上的文字
func _collect_control_text(node: Node, out: Dictionary) -> void:
	if node is Label:
		_add_characters((node as Label).text, out)
	elif node is Button:
		_add_characters((node as Button).text, out)
	for child in node.get_children():
		_collect_control_text(child, out)


func _add_characters(text: String, out: Dictionary) -> void:
	for i in text.length():
		var character := text.substr(i, 1)
		if character.strip_edges().is_empty():
			continue
		out[character] = true
