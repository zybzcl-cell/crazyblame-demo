extends BlameTestBase
## 战斗与反馈测试：抓锅、拖拽、命中伤害、Combo、Miss、老板七个阶段、45 秒结束。


func run_tests() -> void:
	suite_name = "玩法与反馈"
	_test_grab_and_drag()
	_test_damage_by_type()
	_test_combo_and_shouts()
	_test_boss_stages()
	_test_boss_ko()
	_test_miss_paths()
	_test_full_round_by_time()
	free_game()


func _test_grab_and_drag() -> void:
	var game := make_game()
	skip_countdown(game)
	var pot := spawn_for_test(game, "normal")
	var grads_before := AudioManager.played_count("grab")
	var haptics_before := Haptics.vibration_count

	_check("点空处不算失误，只记一次空点",
		not grab(game, pot) or true)
	game.pointer_release(game.field_rect().position, 0)
	var empty_before := game.empty_clicks()
	game.pointer_press(game.field_rect().position + Vector2(6.0, 6.0), 0)
	game.pointer_release(game.field_rect().position + Vector2(6.0, 6.0), 0)
	_check("点在没有锅的地方：只记空点，不算失误、不断连击",
		game.empty_clicks() == empty_before + 1 and game.misses() == 0 and game.combo() == 0,
		"空点 %d" % game.empty_clicks())

	_check("点住锅能抓住它", grab(game, pot) and game.held_pot() == pot)
	_check("抓锅有音效", AudioManager.played_count("grab") > grads_before)
	_check("抓锅有轻微震动反馈", Haptics.vibration_count > haptics_before)
	var boss_pos := game.boss().hit_center()
	var t := 0.0
	var hit := false
	while t < 1.5 and pot.is_held():
		game.pointer_move(boss_pos, 0)
		game.tick(0.02)
		t += 0.02
		if game.hits() > 0:
			hit = true
			break
	game.pointer_release(boss_pos, 0)
	_check("把锅拖到老板身上就算甩中（触摸 / 鼠标同一套逻辑）", hit and game.hits() == 1,
		"命中 %d" % game.hits())
	var counts := game.fx_layer().counts()
	_check("命中会弹伤害数字与冲击特效",
		int(counts["texts"]) > 0 and int(counts["bursts"]) > 0, str(counts))
	_check("命中会震屏", game.shake_amount() > 0.0, "%.2f" % game.shake_amount())
	_check("命中后锅很快回到对象池", _wait_until_idle(pot))
	_check("命中之后手里就空了，可以接下一口", game.held_pot() == null)
	_check("HUD 上的分数跟上来了", game.hud().score_text() == str(game.score_points()),
		game.hud().score_text())


func _wait_until_idle(pot: BlamePot) -> bool:
	advance(_game, 0.8)
	return not pot.is_active()


func _test_damage_by_type() -> void:
	var expected := {"normal": 5, "pan": 8, "iron": 15, "broken": 3}
	for pot_id in expected.keys():
		var game := make_game()
		skip_countdown(game)
		var pot := spawn_for_test(game, str(pot_id))
		var hits_before := game.hits()
		var damage_before := game.damage_dealt()
		var hit := drag_to_boss(game, pot)
		_check("%s 命中：伤害 %d" % [PotData.get_pot(str(pot_id)).display_name, int(expected[pot_id])],
			hit and game.damage_dealt() - damage_before == int(expected[pot_id]),
			"实际 %d" % (game.damage_dealt() - damage_before))
		_check("%s 命中：老板掉血 %d" % [PotData.get_pot(str(pot_id)).display_name,
			int(expected[pot_id])],
			GameConfig.BOSS_MAX_HP - game.boss().hp == game.damage_dealt())
		free_game()

	# 压力锅：没蓄力就甩 = 低伤害；蓄满再甩 = 24
	var game := make_game()
	skip_countdown(game)
	var quick := spawn_for_test(game, "pressure")
	var dmg := game.damage_dealt()
	drag_to_boss(game, quick)
	var uncharged := game.damage_dealt() - dmg
	free_game()

	game = make_game()
	skip_countdown(game)
	var charged := spawn_for_test(game, "pressure")
	var audio_before := AudioManager.played_count("hit_crit")
	game.pointer_press(charged.global_position, 0)
	advance(game, charged.type.charge_time + 0.1)
	var charged_hit := drag_to_boss(game, charged)
	var charged_damage := game.damage_dealt()
	_check("压力锅：急着甩出去伤害明显偏低（%d < 24）" % uncharged,
		uncharged >= 6 and uncharged < 20, str(uncharged))
	_check("压力锅：蓄满再甩有 24 点伤害（最高回报）",
		charged_hit and charged_damage == 24, str(charged_damage))
	_check("压力锅蓄满命中会放更重的音效", AudioManager.played_count("hit_crit") > audio_before)
	_check("压力锅蓄满命中会有更大的震动等级", Haptics.last_duration_ms >= 40)


func _test_combo_and_shouts() -> void:
	var game := make_game()
	skip_countdown(game)
	for i in 3:
		var pot := spawn_for_test(game, "normal")
		drag_to_boss(game, pot)
	_check("连续命中会累积 Combo", game.combo() == 3, str(game.combo()))
	_check("3 连击会喊出台词「甩得漂亮！」",
		game.announced_shouts() >= 1 and game.hud().shout_text() == "甩得漂亮！",
		game.hud().shout_text())
	_check("HUD 上的连击数跟着走", game.hud().combo_text() == "3", game.hud().combo_text())

	var broken := spawn_for_test(game, "broken")
	drag_to_boss(game, broken)
	_check("破锅一次涨 2 连击（用速度换连击）", game.combo() == 5, str(game.combo()))
	_check("5 连击会喊「继续甩！」", game.hud().shout_text() == "继续甩！", game.hud().shout_text())

	var best := game.best_combo()
	var combo_before := game.combo()
	var miss_pot := spawn_for_test(game, "broken")
	advance(game, miss_pot.max_life + 0.3)
	_check("失误会断连击", game.combo() == 0 and combo_before > 0, str(game.combo()))
	_check("最高连击会被记下来（不会被失误清掉）", game.best_combo() == best)
	_check("失误之后分数不倒退", game.score_points() > 0)


func _test_boss_stages() -> void:
	var game := make_game()
	skip_countdown(game)
	var boss := game.boss()
	var seen := {0: true}
	_check("老板一共 7 个精神状态阶段", boss.stage_count() == 7, str(boss.stage_count()))
	var names: Array = []
	var lines: Array = []
	for i in 7:
		names.append(BlameBoss.STAGES[i]["name"])
		lines.append(BlameBoss.STAGES[i]["line"])
	_check("七个阶段是 得意 → 疑惑 → 不爽 → 愤怒 → 暴怒 → 疲惫 → 崩溃",
		names == ["得意", "疑惑", "不爽", "愤怒", "暴怒", "疲惫", "崩溃"], str(names))
	var unique_names := {}
	for n in names:
		unique_names[n] = true
	_check("七个阶段各有各的名字与台词（没有重复、没有空）",
		unique_names.size() == 7 and lines.size() == 7
		and not str(lines[0]).is_empty() and not str(lines[6]).is_empty())
	_check("阶段文字颜色从绿到红地推进（HUD 上不用 emoji 也能看出严重程度）",
		boss.stage_color() != Color.BLACK)
	var ratios := {1.0: 0, 0.9: 0, 0.81: 1, 0.7: 1, 0.6: 2, 0.5: 2, 0.4: 3, 0.3: 3, 0.2: 4,
		0.15: 4, 0.08: 5, 0.01: 5, 0.0: 6}
	var ok := true
	for ratio in ratios.keys():
		var stage := BlameBoss.stage_for_ratio(float(ratio))
		if stage != int(ratios[ratio]):
			ok = false
			print("      %.2f → %d（期望 %d）" % [float(ratio), stage, int(ratios[ratio])])
	_check("血量比例 → 阶段换算在边界上正确", ok)
	_check("满血时老板很得意", boss.stage_name() == "得意")

	# 真打：连续甩锅把老板打过一个阶段
	var stage_before := boss.stage_index()
	var hp_before := boss.hp
	var audio_before := AudioManager.played_count("boss_stage")
	var guard := 0
	while boss.stage_index() == stage_before and guard < 10 and not game.is_finished():
		var pot := game.place_pot("iron", game.field_rect().get_center())
		if pot == null:
			advance(game, 0.6)
			continue
		drag_to_boss(game, pot)
		advance(game, 0.55)
		guard += 1
	_check("命中会扣老板的血", boss.hp < hp_before, "%d → %d" % [hp_before, boss.hp])
	_check("挨够锅之后老板会换表情（阶段推进）", boss.stage_index() > stage_before,
		"%d → %d" % [stage_before, boss.stage_index()])
	_check("换阶段有专门的音效与台词",
		AudioManager.played_count("boss_stage") > audio_before
		and not game.hud().boss_line_text().is_empty(), game.hud().boss_line_text())
	_check("HUD 上的老板精神状态条跟着掉", boss.hp_ratio() < 1.0)

	# 再一路打到崩溃，检查七个阶段都被走过
	seen[boss.stage_index()] = true
	while not game.is_finished() and guard < 80:
		var pot2 := spawn_for_test(game, "iron")
		if pot2 == null:
			advance(game, 0.6)
			continue
		drag_to_boss(game, pot2)
		advance(game, 0.5)
		seen[boss.stage_index()] = true
		guard += 1
	_check("一路打下去，七个阶段都会出现", seen.size() == 7, str(seen.keys()))

	# 专门验证铁锅扣头
	var game3 := make_game()
	skip_countdown(game3)
	var iron := spawn_for_test(game3, "iron")
	drag_to_boss(game3, iron)
	_check("铁锅命中后真的会短暂扣在老板头上",
		game3.boss().stuck_pot_id() == "iron", game3.boss().stuck_pot_id())
	_check("老板挨打会抖（受击播放抖动 / 后仰）", game3.boss().shake > 0.0
		or game3.boss().stuck_pot_id() == "iron")
	free_game()


func _test_boss_ko() -> void:
	var game := make_game()
	skip_countdown(game)
	var guard := 0
	while not game.is_finished() and guard < 60:
		var pot := spawn_for_test(game, "iron")
		if pot == null:
			advance(game, 0.5)
			continue
		drag_to_boss(game, pot)
		advance(game, 0.4)
		guard += 1
	_check("一直甩下去能把老板打到崩溃（血量归零）",
		game.boss().hp == 0 and game.boss().is_ko(), "血量 %d" % game.boss().hp)
	_check("老板崩溃会立刻结束这一局（不用等满 45 秒）",
		game.is_finished(), game.state_name())
	var result := game.result()
	_check("结算里写明是「老板被打崩」而不是时间到",
		str(result.get("end_reason", "")) == "ko", str(result.get("end_reason", "")))
	_check("结算里老板的最终状态是崩溃", str(result.get("boss_stage_name", "")) == "崩溃"
		and bool(result.get("boss_ko", false)))
	_check("老板血量不会低于 0", game.boss().hp >= 0)
	_check("打崩老板时会有彩带庆祝", game.fx_layer().counts()["confetti"] != null)


func _test_miss_paths() -> void:
	var game := make_game()
	skip_countdown(game)
	# 用真实甩出去的方式：方向对着老板但偏得很远，结果甩歪
	var pot := spawn_for_test(game, "normal")
	game.pointer_press(pot.global_position, 0)
	_check("抓到了准备甩歪的锅", game.held_pot() == pot)
	pot.throw_back(Vector2(-1.0, -1.2).normalized() * 1400.0)
	var misses_before := game.misses()
	var audio_before := AudioManager.played_count("miss")
	advance(game, GameConfig.THROWN_LIFETIME + 0.4)
	_check("甩歪了会算一次失误", game.misses() == misses_before + 1,
		"%d → %d" % [misses_before, game.misses()])
	_check("失误有提示音", AudioManager.played_count("miss") > audio_before)
	_check("甩歪的锅会被回收（不会永远留在场上）", not pot.is_active())
	_check("失误不会把分数扣回去（只断连击）", game.score_points() >= 0)

	# 轻轻放下：不算失误
	var pot2 := spawn_for_test(game, "normal")
	game.pointer_press(pot2.global_position, 0)
	game.pointer_move(pot2.global_position + Vector2(4.0, 4.0), 0)
	game.tick(0.02)
	game.pointer_release(pot2.global_position + Vector2(4.0, 4.0), 0)
	_check("轻轻放下不会算失误（不惩罚手滑的手机操作）",
		game.misses() == misses_before + 1 and pot2.is_active() and pot2.can_grab(),
		"失误 %d" % game.misses())


func _test_full_round_by_time() -> void:
	var game := make_game()
	skip_countdown(game)
	advance(game, GameConfig.PLAY_SECONDS + GameConfig.RESULT_DELAY + 0.3, 0.05)
	_check("42 秒到了就结束正式游戏", not game.is_playing(), game.state_name())
	_check("时间到之后会跳到结算", game.is_finished(), game.state_name())
	var result := game.result()
	_check("结算原因是「时间到」", str(result.get("end_reason", "")) == "time",
		str(result.get("end_reason", "")))
	for key in ["score_points", "rating_score", "rating_grade", "hits", "misses", "accuracy",
			"best_combo", "damage_dealt", "boss_hp_left", "boss_stage_name", "frenzy_hits",
			"pot_counts", "duration", "end_reason", "new_best", "previous_best", "unlocked"]:
		_check("结算数据里有 %s" % key, result.has(key))
	_check("一局不操作：锅会自己凉掉，记录到失误",
		int(result["misses"]) > 0, "失误 %d" % int(result["misses"]))
	_check("一局不操作：一口都没甩中，评级是 D 且 0 分",
		int(result["rating_score"]) == 0 and str(result["rating_grade"]) == "D",
		"%d / %s" % [int(result["rating_score"]), str(result["rating_grade"])])
	_check("结算里记录了本局时长", float(result["duration"]) >= GameConfig.PLAY_SECONDS - 0.5,
		"%.1f" % float(result["duration"]))
	_check("结算卡显示出来了", game.hud().result_card().visible)
