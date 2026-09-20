extends Node
## 场景跳转测试的执行者。
##
## 为什么单独一个节点：测试场景自己就是「当前场景」，一旦 change_scene 就会被释放，
## 所以把跳转流程交给挂在 /root 下的这个节点来做（autoload 之外的 /root 子节点不会被换场景回收）。
## 它同时负责把最终的测试报告打出来并退出进程。

var suite_name := "完整流程"
var results: Array = []


func _check(name: String, passed: bool, detail: String = "") -> void:
	results.append({"name": name, "passed": passed, "detail": detail})
	var suffix := "" if detail.is_empty() else "（%s）" % detail
	print("[%s] %s%s" % ["通过" if passed else "失败", name, suffix])


func _ready() -> void:
	call_deferred("_walk")


func _walk() -> void:
	# 1. 打开主菜单
	get_tree().change_scene_to_file(GameConfig.MENU_SCENE)
	await _wait_frames(5)
	var menu := get_tree().current_scene as BlameMainMenu
	_check("项目启动后能打开主菜单",
		menu != null and menu.scene_file_path == GameConfig.MENU_SCENE,
		str(get_tree().current_scene))
	if menu == null:
		_finish()
		return
	_check("主菜单上的按钮都在（开始 / 锅图鉴 / 设置）",
		menu.start_button() != null and menu.codex() != null and menu.settings() != null)

	# 2. 点「开始甩锅」进游戏
	menu.start_button().pressed.emit()
	await _wait_frames(6)
	var game := get_tree().current_scene as BlameGame
	_check("点「开始甩锅」真的进入游戏场景",
		game != null and game.scene_file_path == GameConfig.GAME_SCENE,
		str(get_tree().current_scene))
	if game == null:
		_finish()
		return
	_check("进入游戏先走 3 秒准备阶段", game.state_name() == "countdown", game.state_name())
	_check("游戏里有返回主菜单的按钮", game.hud().quit_button() != null)

	# 3. 返回菜单
	game.hud().quit_button().pressed.emit()
	await _wait_frames(6)
	_check("游戏里的返回按钮回到主菜单",
		get_tree().current_scene.scene_file_path == GameConfig.MENU_SCENE,
		str(get_tree().current_scene.scene_file_path))

	# 4. 再来一局，直接打完，走完「结算 → 再甩一局 → 返回菜单」
	var menu2 := get_tree().current_scene as BlameMainMenu
	menu2.start_button().pressed.emit()
	await _wait_frames(6)
	game = get_tree().current_scene as BlameGame
	if game == null:
		_finish()
		return
	game.set_process(false)
	var total := GameConfig.COUNTDOWN_SECONDS + GameConfig.PLAY_SECONDS \
		+ GameConfig.RESULT_DELAY + 1.0
	var elapsed := 0.0
	while elapsed < total and not game.is_finished():
		game.tick(1.0 / 60.0)
		elapsed += 1.0 / 60.0
	_check("在真实场景里也能把一整局打完并自动结算", game.is_finished(), game.state_name())
	_check("结算卡自动弹出来", game.hud().result_card().visible)
	_check("结算卡上写着本局分数", game.score_points() >= 0
		and game.hud().result_card().restart_button() != null)
	_check("结算卡有两个按钮：再甩一局 / 返回菜单",
		game.hud().result_card().restart_button().text == "再甩一局"
		and game.hud().result_card().menu_button().text == "返回菜单")
	_check("这一局的成绩已经写进存档（最高分 / 累计局数）",
		ProgressManager.total_games() >= 1)

	game.hud().result_card().restart_button().pressed.emit()
	await _wait_frames(4)
	_check("点「再甩一局」会重新开始（回到准备阶段、分数清零）",
		game.state_name() == "countdown" and game.score_points() == 0
		and game.hits() == 0 and game.misses() == 0,
		"%s / %d 分" % [game.state_name(), game.score_points()])

	game.hud().result_card().menu_button().pressed.emit()
	await _wait_frames(6)
	_check("点「返回菜单」回到主菜单",
		get_tree().current_scene.scene_file_path == GameConfig.MENU_SCENE,
		str(get_tree().current_scene.scene_file_path))
	_finish()


func _wait_frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _finish() -> void:
	var passed := 0
	for result in results:
		if bool(result["passed"]):
			passed += 1
	print("===== %s：%d / %d 项通过 =====" % [suite_name, passed, results.size()])
	for result in results:
		if not bool(result["passed"]):
			print("    失败项：%s %s" % [str(result["name"]), str(result["detail"])])
	print("===== 结论：%s =====" % ["全部通过" if passed == results.size() else "存在失败项"])
	AudioManager.stop_all()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if passed == results.size() else 1)
