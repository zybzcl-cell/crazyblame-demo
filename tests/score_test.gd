extends BlameTestBase
## 计分与评级测试：分数不是「命中次数 × 常数」，而是速度 / 连击 / 难度 / 阶段的综合结果。


func run_tests() -> void:
	suite_name = "计分与评级"
	_test_combo_multiplier()
	_test_hit_points()
	_test_rating_dimensions()
	_test_grades()
	_test_skill_comparison()
	_test_real_round_score()
	free_game()


func _test_combo_multiplier() -> void:
	_check("连击越高倍率越高", Score.combo_multiplier(0) < Score.combo_multiplier(5)
		and Score.combo_multiplier(5) < Score.combo_multiplier(12))
	_check("连击倍率有上限（不会无限膨胀）", Score.combo_multiplier(500) <= 4.0,
		"%.2f" % Score.combo_multiplier(500))
	_check("疯狂甩锅阶段连击倍率更高（×1.5）",
		Score.combo_multiplier(10, 1.5) > Score.combo_multiplier(10, 1.0))


func _test_hit_points() -> void:
	var normal := PotData.get_pot("normal")
	var iron := PotData.get_pot("iron")
	var pressure := PotData.get_pot("pressure")
	var slow := Score.hit_points(normal, 0, 3.0, false)
	var fast := Score.hit_points(normal, 0, 0.2, false)
	_check("普通锅、0 连击、慢吞吞地甩：100 分", slow == 100, str(slow))
	_check("反应越快分越高", fast > slow, "%d > %d" % [fast, slow])
	_check("连击越高同一口锅分越高",
		Score.hit_points(normal, 10, 1.0, false) > Score.hit_points(normal, 2, 1.0, false))
	_check("最后 5 秒（疯狂甩锅时间）单次得分更高",
		Score.hit_points(normal, 5, 1.0, true) > Score.hit_points(normal, 5, 1.0, false))
	_check("铁锅比普通锅值钱（难接的锅回报高）",
		Score.hit_points(iron, 3, 1.0, false) > Score.hit_points(normal, 3, 1.0, false))
	_check("压力锅蓄满额外加分（完美蓄力 ×1.2）",
		Score.hit_points(pressure, 3, 1.0, false, 1.0)
		> Score.hit_points(pressure, 3, 1.0, false, 0.5))
	_check("破锅单次分低，但一次涨 2 连击（分工不同）",
		Score.hit_points(PotData.get_pot("broken"), 0, 1.0, false)
		< Score.hit_points(normal, 0, 1.0, false)
		and PotData.get_pot("broken").combo_step == 2)


func _test_rating_dimensions() -> void:
	var perfect := Score.rating({
		"hits": 40, "misses": 0, "best_combo": 30, "damage_dealt": GameConfig.BOSS_MAX_HP,
		"frenzy_hits": 10, "pot_counts": {"pressure": 40},
	})
	_check("打得好可以拿到 100 分评级", int(perfect["score"]) == 100, str(perfect["score"]))
	_check("评级不会超过 100", int(perfect["score"]) <= 100)
	var mixed := Score.rating({
		"hits": 30, "misses": 1, "best_combo": 20, "damage_dealt": GameConfig.BOSS_MAX_HP,
		"frenzy_hits": 8,
		"pot_counts": {"pressure": 8, "iron": 8, "pan": 8, "broken": 6},
	})
	_check("各种锅混着打也能稳进 S 级", int(mixed["score"]) >= 90, str(mixed["score"]))
	var parts: Dictionary = perfect["parts"]
	_check("五个维度都有分：命中率 / 连击 / 伤害 / 疯狂阶段 / 锅的难度",
		parts.size() == 5 and int(parts["accuracy"]) > 0 and int(parts["difficulty"]) > 0,
		str(parts))

	var no_hits := Score.rating({"hits": 0, "misses": 12, "best_combo": 0, "damage_dealt": 0,
		"frenzy_hits": 0, "pot_counts": {}})
	_check("一口都没甩中就是 0 分 D 级",
		int(no_hits["score"]) == 0 and str(no_hits["grade"]) == "D")

	var accuracy_high := Score.rating({"hits": 20, "misses": 2, "best_combo": 6,
		"damage_dealt": 120, "frenzy_hits": 3, "pot_counts": {"normal": 20}})
	var accuracy_low := Score.rating({"hits": 20, "misses": 20, "best_combo": 6,
		"damage_dealt": 120, "frenzy_hits": 3, "pot_counts": {"normal": 20}})
	_check("同样命中 20 口锅，命中率高的评级更高",
		int(accuracy_high["score"]) > int(accuracy_low["score"]),
		"%d > %d" % [int(accuracy_high["score"]), int(accuracy_low["score"])])

	var hard := Score.rating({"hits": 20, "misses": 4, "best_combo": 6, "damage_dealt": 200,
		"frenzy_hits": 3, "pot_counts": {"iron": 10, "pressure": 10}})
	var easy := Score.rating({"hits": 20, "misses": 4, "best_combo": 6, "damage_dealt": 200,
		"frenzy_hits": 3, "pot_counts": {"normal": 20}})
	_check("敢接铁锅 / 压力锅的评级更高（难度构成算分）",
		int(hard["score"]) > int(easy["score"]),
		"%d > %d" % [int(hard["score"]), int(easy["score"])])
	_check("难度构成：全打普通锅拿不到难度分",
		_near(Score.difficulty_ratio({"normal": 30}), 0.0))
	_check("难度构成：全打压力锅拿满难度分",
		_near(Score.difficulty_ratio({"pressure": 10}), 1.0))


func _test_grades() -> void:
	var cases := {100: "S", 90: "S", 89: "A", 78: "A", 77: "B", 64: "B", 63: "C", 48: "C",
		47: "D", 0: "D"}
	var ok := true
	for value in cases.keys():
		if Score.grade_for(int(value)) != str(cases[value]):
			ok = false
	_check("评级门槛：S ≥ 90、A ≥ 78、B ≥ 64、C ≥ 48，其余 D", ok)
	_check("五个评级都有专属称号",
		Score.grade_title("S") == "甩锅之神" and Score.grade_title("D") != ""
		and Score.grade_title("A") != "" and Score.grade_title("B") != ""
		and Score.grade_title("C") != "")
	_check("评级颜色各不相同（结算一眼能看出好坏）",
		Score.grade_color("S") != Score.grade_color("B")
		and Score.grade_color("A") != Score.grade_color("D"))


func _test_skill_comparison() -> void:
	var careful := Score.rating({
		"hits": 30, "misses": 2, "best_combo": 20, "damage_dealt": 210,
		"frenzy_hits": 7,
		"pot_counts": {"normal": 6, "pan": 8, "iron": 10, "pressure": 6},
	})
	var spammer := Score.rating({
		"hits": 30, "misses": 30, "best_combo": 4, "damage_dealt": 150,
		"frenzy_hits": 2, "pot_counts": {"broken": 30},
	})
	_check("技术型玩家（高命中率 + 高连击）评级明显高于乱甩型",
		int(careful["score"]) - int(spammer["score"]) >= 15,
		"%d vs %d" % [int(careful["score"]), int(spammer["score"])])
	_check("技术型玩家能拿到 A 级以上（有明确的「打得更好」空间）",
		int(careful["score"]) >= int(Score.GRADE_THRESHOLDS["A"]),
		str(careful["score"]))


func _test_real_round_score() -> void:
	var game := make_game()
	skip_countdown(game)
	# 用字典接（GDScript 的 lambda 是「按值捕获」，字典本身是引用，能累加）
	var acc := {"points": 0}
	game.hit_landed.connect(func(info: Dictionary) -> void: acc["points"] += int(info["points"]))
	autoplay(game, round_budget())
	_check("一局真的能打满 42 秒并自动结算", game.is_finished(), game.state_name())
	var result := game.result()
	_check("总分 = 每一次命中得分之和（不是按命中次数算的）",
		int(result["score_points"]) == int(acc["points"]),
		"%d / %d" % [int(result["score_points"]), int(acc["points"])])
	_check("自动打一局能打出不少分（说明分数是能积累起来的）",
		int(result["score_points"]) > 500, str(result["score_points"]))
	_check("自动打一局命中率不错，评级不低于 C",
		int(result["rating_score"]) >= int(Score.GRADE_THRESHOLDS["C"]),
		"%d / %s" % [int(result["rating_score"]), str(result["rating_grade"])])
	_check("最高连击与分数都在结算里",
		int(result["best_combo"]) >= 3 and int(result["hits"]) >= 8,
		"连击 %d / 命中 %d" % [int(result["best_combo"]), int(result["hits"])])
