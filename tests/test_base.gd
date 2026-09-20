class_name BlameTestBase
extends Node
## 测试基类：所有测试套件都继承它。
##
## 每个套件都是一个真的把游戏跑起来的场景（headless），逐项打印「[通过]/[失败]」，
## 最后打印 `===== 名称：x / y 项通过 =====`，并且失败时用非 0 退出码收尾。
## 辅助方法负责「造一局游戏 / 把时间推过去 / 模拟触摸与鼠标」这些重复动作。

const SAVE_PATH := "res://tests/.tmp/test_save.json"
const SAVE_PATH_B := "res://tests/.tmp/test_save_b.json"

var suite_name := "测试"
## 交给 scene_walker 收尾时设为 true（因为切场景会把测试节点自己释放掉）
var report_handed_off := false
## 兜底：套件万一卡住（例如某处抛出脚本错误），超时也要把已跑的结果打出来并退出
const WATCHDOG_SECONDS := 90.0
var _results: Array[Dictionary] = []
var _holder: Node2D = null
var _game: BlameGame = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_start_watchdog()
	await run_tests()
	if not report_handed_off:
		_report()


func _start_watchdog() -> void:
	var timer := get_tree().create_timer(WATCHDOG_SECONDS, true, false, true)
	timer.timeout.connect(func() -> void:
		print("[失败] 测试超时（%.0f 秒没有结束）" % WATCHDOG_SECONDS)
		_results.append({"name": "套件超时", "passed": false, "detail": "%.0f 秒" % WATCHDOG_SECONDS})
		_report())


## 子类覆盖这个方法写测试
func run_tests() -> void:
	pass


# ---------------------------------------------------------------- 断言与报告

func _check(name: String, passed: bool, detail: String = "") -> void:
	_results.append({"name": name, "passed": passed, "detail": detail})
	var suffix := "" if detail.is_empty() else "（%s）" % detail
	print("[%s] %s%s" % ["通过" if passed else "失败", name, suffix])


func _report() -> void:
	var passed := 0
	for result in _results:
		if bool(result["passed"]):
			passed += 1
	print("===== %s：%d / %d 项通过 =====" % [suite_name, passed, _results.size()])
	for result in _results:
		if not bool(result["passed"]):
			print("    失败项：%s %s" % [str(result["name"]), str(result["detail"])])
	print("===== 结论：%s =====" % ["全部通过" if passed == _results.size() else "存在失败项"])
	# 先停掉还在播的音效再退出：否则退出时音频播放对象还活着，引擎会报「实例泄漏」
	AudioManager.stop_all()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if passed == _results.size() else 1)


# ---------------------------------------------------------------- 造一局游戏

## 造一个跑在测试容器里的游戏场景（自己的 _process 关掉，时间由测试推进）
func make_game(reset_progress: bool = true) -> BlameGame:
	if _holder == null:
		_holder = Node2D.new()
		_holder.name = "Holder"
		add_child(_holder)
	if _game != null and is_instance_valid(_game):
		_game.get_parent().remove_child(_game)
		_game.queue_free()
	ProgressManager.reload(SAVE_PATH)
	if reset_progress:
		ProgressManager.reset_progress()
	ProgressManager.reload(SAVE_PATH)
	_game = (load(GameConfig.GAME_SCENE) as PackedScene).instantiate() as BlameGame
	_holder.add_child(_game)
	_game.set_process(false)
	return _game


func free_game() -> void:
	if _game != null and is_instance_valid(_game):
		_game.queue_free()
		_game = null


## 让游戏跳过 3 秒准备阶段
func skip_countdown(game: BlameGame) -> void:
	advance(game, GameConfig.COUNTDOWN_SECONDS + 0.05, 0.05)


## 一局的推进预算：42 秒正式游戏 + 结束动画（KO / 时间到）+ 结算弹出 + 余量
func round_budget() -> float:
	return GameConfig.PLAY_SECONDS + GameConfig.KO_RESULT_DELAY + 2.0


## 按固定步长推进游戏（step 越小越接近真实帧）
func advance(game: BlameGame, seconds: float, step: float = 1.0 / 60.0) -> void:
	var t := 0.0
	while t < seconds:
		var delta := minf(step, seconds - t)
		game.tick(delta)
		t += delta


## 只推进准备 / 结算这类不涉及场地的时间，不做任何输入
func advance_frames(game: BlameGame, frames: int) -> void:
	for i in frames:
		game.tick(1.0 / 60.0)


## 抓到一口锅（返回是否真的抓到了）
func grab(game: BlameGame, pot: BlamePot) -> bool:
	game.pointer_press(pot.global_position, 0)
	return game.held_pot() == pot


## 把锅拖到老板身上并松手（返回这一下是否命中）
func drag_to_boss(game: BlameGame, pot: BlamePot, max_seconds: float = 2.0) -> bool:
	if pot == null or not is_instance_valid(pot):
		return false
	var hits_before := game.hits()
	game.pointer_press(pot.global_position, 0)
	var t := 0.0
	while t < max_seconds and game.hits() == hits_before and pot.is_held():
		game.pointer_move(game.boss().hit_center(), 0)
		game.tick(0.02)
		t += 0.02
	game.pointer_release(game.boss().hit_center(), 0)
	game.tick(0.02)
	return game.hits() > hits_before


## 找到第一口可以抓的锅
func first_grabbable(game: BlameGame) -> BlamePot:
	for pot in game.active_pots():
		if pot.can_grab():
			return pot
	return null


## 测试用：生成一口锅（池子满时先把时间往前推一点再试）
func spawn_for_test(game: BlameGame, pot_id: String) -> BlamePot:
	for i in 12:
		var pot := game.place_pot(pot_id, game.field_rect().get_center())
		if pot != null:
			return pot
		advance(game, 0.4)
	return null


## 让游戏自己往前跑，同时自动把锅一个个拖回老板（模拟一个不失误的玩家）
func autoplay(game: BlameGame, seconds: float) -> void:
	var t := 0.0
	var step := 1.0 / 60.0
	while t < seconds and not game.is_finished():
		var target := first_grabbable(game)
		# 抓住最近的一口锅
		if target != null:
			game.pointer_press(target.global_position, 0)
		if target == null or game.held_pot() != target:
			# 没得抓（或者这一下没抓住）：照样往前推时间，绝不空转
			game.pointer_release(step_vector(), 0)
			game.tick(step)
			t += step
			continue
		var spent := 0.0
		while spent < 0.7 and target.is_held() and not game.is_finished():
			game.pointer_move(game.boss().hit_center(), 0)
			game.tick(step)
			spent += step
			t += step
		game.pointer_release(game.boss().hit_center(), 0)
		game.tick(step)
		t += step


func step_vector() -> Vector2:
	return Vector2.ZERO


# ---------------------------------------------------------------- 输入模拟

func push_mouse_press(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = point
	event.global_position = point
	get_tree().root.push_input(event, true)


func push_mouse_release(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = point
	event.global_position = point
	get_tree().root.push_input(event, true)


func push_mouse_move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_tree().root.push_input(event, true)


func touch_press(point: Vector2, index: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = true
	event.position = point
	get_tree().root.push_input(event, true)


func touch_move(point: Vector2, index: int = 0) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	get_tree().root.push_input(event, true)


func touch_release(point: Vector2, index: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = false
	event.position = point
	get_tree().root.push_input(event, true)


# ---------------------------------------------------------------- 小工具

func _near(a: float, b: float, tolerance: float = 0.001) -> bool:
	return absf(a - b) <= tolerance


func _file_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _write_text(path: String, text: String) -> void:
	var directory := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


func _count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total
