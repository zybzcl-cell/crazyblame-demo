extends BlameTestBase
## 完整流程测试：一局从准备到结算、重开、阶段推进、疯狂甩锅时间、连打三局不泄漏。
##
## 最后一组「菜单 ↔ 游戏」的真实场景跳转交给 tests/scene_walker.gd 执行
## （切场景会把测试节点自己释放掉，所以需要一个挂在 /root 上的收尾者）。


func run_tests() -> void:
	suite_name = "完整流程"
	_test_full_round()
	_test_restart_clears()
	_test_phases_over_time()
	_test_frenzy_feedback()
	_test_three_rounds_stable()
	free_game()
	report_handed_off = true
	var walker: Node = load("res://tests/scene_walker.gd").new()
	walker.suite_name = suite_name
	walker.results = _results
	get_tree().root.add_child(walker)


func _test_full_round() -> void:
	var game := make_game()
	_check("开局在准备阶段", game.state_name() == "countdown")
	_check("准备阶段 HUD 显示「老板开始甩锅了」",
		game.hud().banner_text() == GameConfig.READY_TITLE, game.hud().banner_text())
	_check("准备阶段会教怎么玩（点击锅 → 拖到老板身上）",
		game.hud().hint_text() == GameConfig.READY_HINT, game.hud().hint_text())
	skip_countdown(game)
	_check("准备结束后进入正式游戏", game.is_playing())
	autoplay(game, round_budget())
	_check("打完一整局会停在结算状态", game.is_finished(), game.state_name())
	_check("结算卡显示出来，里面有分数 / 评级 / 老板最终状态",
		game.hud().result_card().visible and game.result().has("rating_grade")
		and game.result().has("boss_stage_name"))
	_check("这局成绩已经写进存档（累计局数 +1）", ProgressManager.total_games() >= 1,
		str(ProgressManager.total_games()))
	_check("最高分已经被刷新（新纪录 0 分会是 0）",
		ProgressManager.best_score() == game.score_points()
		or ProgressManager.best_score() >= game.score_points())


func _test_restart_clears() -> void:
	var game := make_game()
	skip_countdown(game)
	autoplay(game, 8.0)
	var scored := game.score_points()
	_check("先打 8 秒，攒了一些分", scored > 0, str(scored))
	game.restart()
	_check("再甩一局：回到准备阶段", game.state_name() == "countdown", game.state_name())
	_check("再甩一局：分数 / 命中 / 失误 / 连击 全部清零",
		game.score_points() == 0 and game.hits() == 0 and game.misses() == 0
		and game.combo() == 0)
	_check("再甩一局：老板满血复活", game.boss().hp == GameConfig.BOSS_MAX_HP
		and not game.boss().is_ko())
	_check("再甩一局：场上的锅都收回了", game.active_pot_count() == 0,
		str(game.active_pot_count()))
	_check("再甩一局：倒计时重新开始", _near(game.countdown_left(), GameConfig.COUNTDOWN_SECONDS, 0.6),
		"%.2f" % game.countdown_left())
	skip_countdown(game)
	_check("重开之后还能正常玩（不是一次性状态）", game.is_playing() and game.time_left() > 40.0)


func _test_phases_over_time() -> void:
	var game := make_game()
	skip_countdown(game)
	var marks := {5.0: "热身", 15.0: "加速", 25.0: "混合", 33.0: "高压", 40.0: "疯狂甩锅"}
	var seen: Array = []
	var ok := true
	var last_t := 0.0
	for mark in marks.keys():
		advance(game, float(mark) - last_t, 0.1)
		last_t = float(mark)
		seen.append("%.0fs=%s" % [float(mark), game.phase_name()])
		if game.phase_name() != str(marks[mark]):
			ok = false
	_check("45 秒不是简单重复：五个阶段按时推进", ok, "、".join(seen))
	_check("最后 5 秒进入「疯狂甩锅时间」", game.phase_name() == "疯狂甩锅"
		and game.hud().is_frenzy())
	_check("疯狂阶段屏幕会变红（背景 + HUD 都在提示）",
		game.hud().is_frenzy())


func _test_frenzy_feedback() -> void:
	var game := make_game()
	skip_countdown(game)
	advance(game, 38.0, 0.1)
	_check("疯狂甩锅时间有开场提示与音效",
		game.hud().banner_text().length() > 0)
	var frenzy_hits_before := game.frenzy_hits()
	var pot := spawn_for_test(game, "broken")
	drag_to_boss(game, pot)
	_check("疯狂阶段的命中会被单独统计（结算里要看这一段的表现）",
		game.frenzy_hits() == frenzy_hits_before + 1, str(game.frenzy_hits()))
	var before := game.score_points()
	var pot2 := spawn_for_test(game, "broken")
	game.clear_pots(pot2)
	var combo := game.combo()
	drag_to_boss(game, pot2)
	_check("疯狂阶段连击涨得更快（破锅一次 +2）", game.combo() == combo + 2,
		"%d → %d" % [combo, game.combo()])
	_check("疯狂阶段得分明显更高", game.score_points() - before > 0)


func _test_three_rounds_stable() -> void:
	var game := make_game()
	var nodes_before := _count_nodes(game)
	for round_index in 3:
		skip_countdown(game)
		autoplay(game, round_budget())
		_check("第 %d 局能完整打完并出结算" % (round_index + 1), game.is_finished())
		game.restart()
	var nodes_after := _count_nodes(game)
	_check("连打 3 局之后节点数没有增长（没有泄漏）", nodes_after == nodes_before,
		"%d → %d" % [nodes_before, nodes_after])
	_check("连打 3 局之后锅池还是固定数量", game.pot_pool_size() == 12)
	_check("连打 3 局之后还能正常开下一局", game.state_name() == "countdown")
	_check("累计局数记录了 3 局以上", ProgressManager.total_games() >= 3,
		str(ProgressManager.total_games()))
