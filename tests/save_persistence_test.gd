extends BlameTestBase
## 跨进程存档测试：一个进程写成绩，另一个进程读出来（验证「关掉游戏也不丢」）。
##
##   Godot --headless --path . res://tests/save_persistence_test.tscn -- write  <存档路径>
##   Godot --headless --path . res://tests/save_persistence_test.tscn -- verify <存档路径>

const DEFAULT_PATH := "res://tests/.tmp/cross_process.json"


func run_tests() -> void:
	suite_name = "跨进程存档"
	var args := OS.get_cmdline_user_args()
	var mode := str(args[0]) if args.size() > 0 else "write"
	var path := str(args[1]) if args.size() > 1 else DEFAULT_PATH
	if mode == "verify":
		_verify(path)
	else:
		_write(path)


func _write(path: String) -> void:
	SaveStore.delete_data(path)
	ProgressManager.reload(path)
	ProgressManager.reset_progress()
	ProgressManager.register_game({
		"score_points": 4321,
		"rating_score": 88,
		"rating_grade": "A",
		"best_combo": 11,
		"hits": 15,
		"misses": 3,
		"damage_dealt": 137,
		"throws": 15,
		"pot_counts": {"normal": 10, "pan": 5},
		"duration": GameConfig.PLAY_SECONDS,
		"end_reason": "time",
	})
	ProgressManager.set_sound_enabled(false)
	ProgressManager.set_vibration_enabled(true)
	_check("写入进程：最高分写进存档", ProgressManager.best_score() == 4321,
		str(ProgressManager.best_score()))
	_check("写入进程：铁锅因为累计命中 15 口而解锁",
		ProgressManager.is_pot_unlocked("iron"))
	_check("写入进程：存档文件确实出现在磁盘上", FileAccess.file_exists(path))
	_check("写入进程：存档是能看懂的 JSON",
		_file_text(path).contains("\"best_score\""))


func _verify(path: String) -> void:
	_check("读取进程：临时存档文件在（由上一个进程写入）", FileAccess.file_exists(path))
	ProgressManager.reload(path)
	_check("换一个进程重新读取：最高分还在（4321）",
		ProgressManager.best_score() == 4321, str(ProgressManager.best_score()))
	_check("最高连击还在（11）", ProgressManager.best_combo() == 11,
		str(ProgressManager.best_combo()))
	_check("最高评级还在（A / 88）",
		ProgressManager.best_grade() == "A" and ProgressManager.best_rating() == 88,
		"%s / %d" % [ProgressManager.best_grade(), ProgressManager.best_rating()])
	_check("累计局数 / 命中 / 失误都还在",
		ProgressManager.total_games() == 1 and ProgressManager.total_hits() == 15
		and ProgressManager.total_misses() == 3)
	_check("每种锅的累计次数也还在",
		ProgressManager.pot_hits("normal") == 10 and ProgressManager.pot_hits("pan") == 5)
	_check("解锁状态跟着存档一起过来",
		ProgressManager.is_pot_unlocked("iron") and ProgressManager.is_pot_unlocked("pressure"))
	_check("设置项（声音 / 震动）也保存了",
		not ProgressManager.sound_enabled() and ProgressManager.vibration_enabled())
	SaveStore.delete_data(path)
	_check("测试结束会清掉临时存档", not FileAccess.file_exists(path))
