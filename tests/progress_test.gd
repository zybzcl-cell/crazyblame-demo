extends BlameTestBase
## 存档与进度测试：最高分 / 最高连击 / 累计统计 / 解锁 / 设置 / 坏存档兜底。


const BAD_JSON := "res://tests/.tmp/broken.json"
const MULTI_PROCESS := "res://tests/.tmp/persist_target.json"


func run_tests() -> void:
	suite_name = "存档与解锁"
	SaveStore.delete_data(SAVE_PATH)
	SaveStore.delete_data(SAVE_PATH_B)
	SaveStore.delete_data(BAD_JSON)
	ProgressManager.reload(SAVE_PATH)
	ProgressManager.reset_progress()
	_test_defaults()
	_test_register_game()
	_test_best_kept()
	_test_unlocks()
	_test_pot_toggles()
	_test_settings()
	_test_broken_saves()
	_test_reset()
	SaveStore.delete_data(SAVE_PATH)
	SaveStore.delete_data(SAVE_PATH_B)
	SaveStore.delete_data(BAD_JSON)


func _sample_result(points: int, combo: int, hits: int, misses: int) -> Dictionary:
	return {
		"score_points": points,
		"rating_score": mini(100, points / 40),
		"rating_grade": Score.grade_for(mini(100, points / 40)),
		"best_combo": combo,
		"hits": hits,
		"misses": misses,
		"damage_dealt": hits * 8,
		"throws": hits,
		"pot_counts": {"normal": hits},
		"duration": GameConfig.PLAY_SECONDS,
		"end_reason": "time",
	}


func _test_defaults() -> void:
	var data := SaveStore.default_data()
	_check("新档的最高分 / 最高连击都是 0",
		int(data["best_score"]) == 0 and int(data["best_combo"]) == 0)
	_check("新档的累计统计都是 0",
		int(data["total_games"]) == 0 and int(data["total_hits"]) == 0
		and int(data["total_misses"]) == 0 and int(data["total_returned"]) == 0)
	_check("新档默认开启声音与震动",
		bool(data["sound_enabled"]) and bool(data["vibration_enabled"]))
	_check("新档没有解锁额外的锅", (data["unlocked_pots"] as Array).is_empty())
	_check("存档格式带版本号（方便以后升级 / 迁移）", int(data["version"]) >= 1)
	_check("存档文件写在用户目录（本地存档，不需要账号）",
		GameConfig.SAVE_PATH.begins_with("user://"), GameConfig.SAVE_PATH)


func _test_register_game() -> void:
	var changes := ProgressManager.register_game(_sample_result(1200, 9, 10, 4))
	_check("第一局就是新纪录", bool(changes["new_best"]) and int(changes["previous_best"]) == 0)
	_check("最高分写进存档", ProgressManager.best_score() == 1200,
		str(ProgressManager.best_score()))
	_check("最高连击写进存档", ProgressManager.best_combo() == 9)
	_check("累计局数 +1", ProgressManager.total_games() == 1)
	_check("累计命中 / 失误 / 甩回的口数都累加",
		ProgressManager.total_hits() == 10 and ProgressManager.total_misses() == 4
		and ProgressManager.total_returned() == 10)
	_check("累计伤害累加", ProgressManager.total_damage() == 80,
		str(ProgressManager.total_damage()))
	_check("累计准确率 = 命中 /（命中 + 失误）",
		_near(ProgressManager.accuracy(), 10.0 / 14.0, 0.001),
		"%.3f" % ProgressManager.accuracy())
	_check("每种锅的累计次数分开记", ProgressManager.pot_hits("normal") == 10)
	_check("记录了最后一次游玩时间", not ProgressManager.last_played_at().is_empty())
	_check("存档真的落盘了（FileAccess 能读到）",
		_file_text(SAVE_PATH).contains("best_score"))


func _test_best_kept() -> void:
	var changes := ProgressManager.register_game(_sample_result(800, 4, 6, 9))
	_check("分数更低的一局不会覆盖最高分",
		ProgressManager.best_score() == 1200 and not bool(changes["new_best"]),
		str(ProgressManager.best_score()))
	_check("最高连击取历史最大值", ProgressManager.best_combo() == 9)
	_check("累计局数继续增加", ProgressManager.total_games() == 2)
	_check("累计命中继续累加", ProgressManager.total_hits() == 16, str(ProgressManager.total_hits()))

	var better := ProgressManager.register_game(_sample_result(2400, 15, 12, 3))
	_check("分数更高的一局会刷新最高分",
		ProgressManager.best_score() == 2400 and bool(better["new_best"]))
	_check("刷新时会把旧纪录一起返回（结算卡要显示）", int(better["previous_best"]) == 1200)
	_check("最高评级也跟着刷新（S/A/B/C/D）",
		ProgressManager.best_grade() == Score.grade_for(mini(100, 2400 / 40)),
		ProgressManager.best_grade())
	_check("重新读一次存档，纪录还在（不丢数据）", _reload_and_read() == 2400,
		str(_reload_and_read()))


func _reload_and_read() -> int:
	ProgressManager.reload(SAVE_PATH)
	return ProgressManager.best_score()


func _test_unlocks() -> void:
	ProgressManager.reset_progress()
	ProgressManager.reload(SAVE_PATH)
	_check("铁锅一开始是锁着的", not ProgressManager.is_pot_unlocked("iron"))
	_check("压力锅一开始是锁着的", not ProgressManager.is_pot_unlocked("pressure"))
	_check("默认解锁三种锅（普通 / 平底 / 破锅）",
		ProgressManager.unlocked_pots() == ["normal", "pan", "broken"],
		str(ProgressManager.unlocked_pots()))
	var progress := ProgressManager.unlock_progress("iron")
	_check("图鉴能看到铁锅的解锁进度与条件",
		int(progress["target"]) == 12 and not str(progress["label"]).is_empty()
		and not bool(progress["unlocked"]), str(progress))
	_check("一开始的解锁进度是 0", _near(float(progress["ratio"]), 0.0))

	# 累计命中 12 口锅 → 解锁铁锅
	var changes := ProgressManager.register_game(_sample_result(500, 3, 12, 2))
	_check("累计命中达到 12 口，铁锅自动解锁",
		ProgressManager.is_pot_unlocked("iron") and (changes["unlocked"] as Array).has("iron"),
		str(changes["unlocked"]))
	_check("解锁之后会出现在可选锅列表里", ProgressManager.enabled_pots().has("iron"))
	_check("压力锅还没达到条件（最高连击不够）",
		not ProgressManager.is_pot_unlocked("pressure"), str(ProgressManager.best_combo()))

	ProgressManager.register_game(_sample_result(700, 10, 5, 1))
	_check("最高连击打到 10，压力锅解锁",
		ProgressManager.is_pot_unlocked("pressure"), str(ProgressManager.best_combo()))
	_check("五种锅全部解锁",
		ProgressManager.unlocked_pots().size() == 5, str(ProgressManager.unlocked_pots()))
	var iron_progress := ProgressManager.unlock_progress("iron")
	_check("解锁之后进度条是满的", bool(iron_progress["unlocked"])
		and _near(float(iron_progress["ratio"]), 1.0))
	ProgressManager.reload(SAVE_PATH)
	_check("解锁状态写进了存档（重开也不会掉回去）",
		ProgressManager.is_pot_unlocked("iron") and ProgressManager.is_pot_unlocked("pressure"))


func _test_pot_toggles() -> void:
	ProgressManager.set_pot_enabled("pressure", false)
	_check("可以把解锁过的锅停用（玩法选择）", not ProgressManager.is_pot_enabled("pressure"))
	_check("停用的锅不会再出现在生成表里",
		not ProgressManager.enabled_pots().has("pressure"), str(ProgressManager.enabled_pots()))
	ProgressManager.reload(SAVE_PATH)
	_check("停用状态会保存", not ProgressManager.is_pot_enabled("pressure"))
	ProgressManager.set_pot_enabled("pressure", true)
	_check("可以重新启用", ProgressManager.is_pot_enabled("pressure"))
	ProgressManager.set_pot_enabled("normal", false)
	ProgressManager.set_pot_enabled("pan", false)
	ProgressManager.set_pot_enabled("broken", false)
	ProgressManager.set_pot_enabled("iron", false)
	ProgressManager.set_pot_enabled("pressure", false)
	_check("至少会留下一种锅（不会把玩家关在门外）",
		ProgressManager.enabled_pots().size() >= 1, str(ProgressManager.enabled_pots()))


func _test_settings() -> void:
	ProgressManager.set_sound_enabled(false)
	ProgressManager.set_vibration_enabled(false)
	ProgressManager.reload(SAVE_PATH)
	_check("声音 / 震动开关会保存",
		not ProgressManager.sound_enabled() and not ProgressManager.vibration_enabled())
	ProgressManager.set_sound_enabled(true)
	ProgressManager.set_vibration_enabled(true)
	ProgressManager.reload(SAVE_PATH)
	_check("关掉再打开也能正确保存",
		ProgressManager.sound_enabled() and ProgressManager.vibration_enabled())


func _test_broken_saves() -> void:
	SaveStore.warn_on_error = false
	_check("文件不存在时按新档处理，不报错",
		int(SaveStore.load_data("res://tests/.tmp/not_there.json")["best_score"]) == 0)
	_write_text(BAD_JSON, "{ 这不是 JSON")
	_check("存档不是 JSON：安全退回新档",
		int(SaveStore.load_data(BAD_JSON)["best_score"]) == 0)
	_write_text(BAD_JSON, "[1, 2, 3]")
	_check("存档不是对象：安全退回新档",
		int(SaveStore.load_data(BAD_JSON)["best_score"]) == 0)
	_write_text(BAD_JSON, "   ")
	_check("存档是空文件：安全退回新档",
		int(SaveStore.load_data(BAD_JSON)["best_score"]) == 0)
	_write_text(BAD_JSON, JSON.stringify({
		"best_score": "很多分",
		"best_rating": 900,
		"best_grade": "Z",
		"total_games": -5,
		"total_play_seconds": "abc",
		"unlocked_pots": ["iron", "iron", 42, "不存在的锅"],
		"disabled_pots": "不是数组",
		"pot_hits": {"normal": -3, "iron": 2, "假的": 9},
		"sound_enabled": "是的",
		"last_played_at": 12345,
	}))
	var cleaned := SaveStore.load_data(BAD_JSON)
	_check("坏掉的数字字段退回安全值",
		int(cleaned["best_score"]) == 0 and int(cleaned["total_games"]) == 0
		and _near(float(cleaned["total_play_seconds"]), 0.0))
	_check("评级被收进 0~100，非法评级字母丢掉",
		int(cleaned["best_rating"]) == 100 and str(cleaned["best_grade"]) == "")
	_check("解锁列表去重、丢掉不存在的锅",
		cleaned["unlocked_pots"] == ["iron"], str(cleaned["unlocked_pots"]))
	_check("类型不对的列表退回空数组", (cleaned["disabled_pots"] as Array).is_empty())
	_check("每种锅的累计次数只保留合法值",
		cleaned["pot_hits"] == {"iron": 2}, str(cleaned["pot_hits"]))
	_check("布尔字段类型不对时用默认值", bool(cleaned["sound_enabled"]))
	_check("字符串字段类型不对时退回空串", str(cleaned["last_played_at"]) == "")
	SaveStore.warn_on_error = true
	SaveStore.delete_data(BAD_JSON)


func _test_reset() -> void:
	ProgressManager.register_game(_sample_result(3000, 20, 20, 2))
	_check("清空之前存档里是有成绩的", ProgressManager.best_score() > 0)
	ProgressManager.reset_progress()
	_check("清空记录之后最高分归零", ProgressManager.best_score() == 0)
	_check("清空记录之后累计统计归零",
		ProgressManager.total_games() == 0 and ProgressManager.total_hits() == 0)
	_check("清空记录之后锅的解锁回到初始状态",
		ProgressManager.unlocked_pots() == ["normal", "pan", "broken"],
		str(ProgressManager.unlocked_pots()))
	var file := _file_text(SAVE_PATH)
	_check("清空之后磁盘上的存档也是干净的", file.contains("\"best_score\": 0"), file.substr(0, 60))
