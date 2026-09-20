extends BlameTestBase
## 锅的测试：五种锅真的不一样吗？相位节奏合理吗？生成 / 存活 / 手滑 / 超时都对吗？


func run_tests() -> void:
	suite_name = "锅与节奏"
	_test_catalog()
	_test_feel_differences()
	_test_phases()
	_test_phase_lookup()
	_test_spawn_flow()
	_test_lifetime_and_slip()
	_test_pool_is_fixed()
	free_game()


func _test_catalog() -> void:
	var catalog := PotData.catalog()
	_check("一共 5 种锅", catalog.size() == 5, str(catalog.size()))
	var ids := PotData.ids()
	_check("五种锅是普通 / 铁锅 / 平底锅 / 压力锅 / 破锅",
		ids == ["normal", "iron", "pan", "pressure", "broken"], str(ids))
	for pot in catalog:
		_check("%s：名称、说明、难度星级都齐全" % pot.display_name,
			not pot.display_name.is_empty() and not pot.tagline.is_empty()
			and pot.difficulty >= 1 and pot.difficulty <= 5)
		_check("%s：伤害与得分都是正数" % pot.display_name,
			pot.damage > 0 and pot.base_score > 0)
	_check("默认解锁 3 种（普通锅 / 平底锅 / 破锅），铁锅与压力锅要靠成绩解锁",
		PotData.get_pot("normal").is_default_unlocked()
		and PotData.get_pot("pan").is_default_unlocked()
		and PotData.get_pot("broken").is_default_unlocked()
		and not PotData.get_pot("iron").is_default_unlocked()
		and not PotData.get_pot("pressure").is_default_unlocked())
	_check("每种锅都有自己的「锅话」文案",
		PotData.blame_line("iron", RandomNumberGenerator.new()).length() > 0)


func _test_feel_differences() -> void:
	var normal := PotData.get_pot("normal")
	var iron := PotData.get_pot("iron")
	var pan := PotData.get_pot("pan")
	var pressure := PotData.get_pot("pressure")
	var broken := PotData.get_pot("broken")

	# 速度：破锅最快，铁锅最慢
	_check("飘移速度分档：破锅 > 平底锅 > 普通锅 > 压力锅 > 铁锅",
		broken.drift_speed > pan.drift_speed and pan.drift_speed > normal.drift_speed
		and normal.drift_speed > pressure.drift_speed
		and pressure.drift_speed > iron.drift_speed,
		"%.0f / %.0f / %.0f / %.0f / %.0f" % [broken.drift_speed, pan.drift_speed,
			normal.drift_speed, pressure.drift_speed, iron.drift_speed])
	# 跟手程度：破锅最跟手，铁锅最迟钝
	_check("拖动跟手程度：破锅 > 平底锅 > 普通锅 > 压力锅 > 铁锅（铁锅明显更沉）",
		broken.drag_follow > pan.drag_follow and pan.drag_follow > normal.drag_follow
		and normal.drag_follow > pressure.drag_follow
		and pressure.drag_follow > iron.drag_follow,
		"%.1f / %.1f / %.1f / %.1f / %.1f" % [broken.drag_follow, pan.drag_follow,
			normal.drag_follow, pressure.drag_follow, iron.drag_follow])
	_check("铁锅跟手不到破锅的 1/3（手感差距足够明显）",
		iron.drag_follow < broken.drag_follow / 3.0)
	# 抓取判定：压力锅最难抓，铁锅最好抓
	_check("抓取判定：铁锅最大、压力锅最小（压力锅明显更难抓）",
		iron.grab_radius > normal.grab_radius and iron.grab_radius > broken.grab_radius
		and pressure.grab_radius < normal.grab_radius
		and pressure.grab_radius < broken.grab_radius,
		"铁 %.0f / 普通 %.0f / 破 %.0f / 压力 %.0f" % [
			iron.grab_radius, normal.grab_radius, broken.grab_radius, pressure.grab_radius])
	# 伤害：铁锅 > 平底锅 > 普通锅 > 破锅；压力锅蓄满最高
	_check("伤害分档：破锅 3 < 普通 5 < 平底 8 < 铁锅 15",
		broken.damage < normal.damage and normal.damage < pan.damage
		and pan.damage < iron.damage,
		"%d / %d / %d / %d" % [broken.damage, normal.damage, pan.damage, iron.damage])
	_check("压力锅蓄满伤害 24，比铁锅还高（难抓难蓄，回报最高）",
		pressure.needs_charge and pressure.damage_for(1.0) == pressure.damage_charged
		and pressure.damage_for(1.0) > iron.damage,
		"没蓄力 %d → 蓄满 %d" % [pressure.damage_for(0.0), pressure.damage_for(1.0)])
	_check("压力锅蓄力是连续的：半蓄的伤害在两端之间",
		pressure.damage_for(0.5) > pressure.damage_for(0.0)
		and pressure.damage_for(0.5) < pressure.damage_for(1.0))
	_check("破锅一次涨 2 连击（快速连击的发动机）", broken.combo_step == 2
		and normal.combo_step == 1 and iron.combo_step == 1)
	_check("存活时间：铁锅最长、平底锅/破锅更短（逼你快点处理）",
		iron.life_seconds > normal.life_seconds
		and normal.life_seconds > pan.life_seconds
		and normal.life_seconds > broken.life_seconds)
	_check("握在手里的时间上限：破锅最短、压力锅最长（要留时间蓄力）",
		broken.hold_window < normal.hold_window
		and normal.hold_window < pressure.hold_window)


func _test_phases() -> void:
	_check("一整局分成 5 个阶段", PotData.phase_count() == 5)
	_check("最后一个阶段在 42 秒结束（正好是正式游戏时长）",
		_near(float(PotData.phase(PotData.phase_count() - 1)["until"]), GameConfig.PLAY_SECONDS))
	var names: Array = []
	for i in PotData.phase_count():
		names.append(str(PotData.phase(i)["name"]))
	_check("阶段名字是 热身 → 加速 → 混合 → 高压 → 疯狂甩锅",
		names == ["热身", "加速", "混合", "高压", "疯狂甩锅"], str(names))
	var last := PotData.phase_count() - 1
	_check("生成间隔越来越短（越到后面锅越多）",
		float(PotData.phase(0)["interval"]) > float(PotData.phase(1)["interval"])
		and float(PotData.phase(1)["interval"]) > float(PotData.phase(2)["interval"])
		and float(PotData.phase(2)["interval"]) > float(PotData.phase(3)["interval"])
		and float(PotData.phase(3)["interval"]) > float(PotData.phase(last)["interval"]))
	_check("同屏上限逐步提高",
		int(PotData.phase(0)["max_alive"]) == 1
		and int(PotData.phase(1)["max_alive"]) > int(PotData.phase(0)["max_alive"])
		and int(PotData.phase(2)["max_alive"]) > int(PotData.phase(1)["max_alive"])
		and int(PotData.phase(3)["max_alive"]) > int(PotData.phase(2)["max_alive"])
		and int(PotData.phase(last)["max_alive"]) > int(PotData.phase(3)["max_alive"]))
	_check("锅的飘移速度逐阶段变快",
		float(PotData.phase(1)["speed_scale"]) > float(PotData.phase(0)["speed_scale"])
		and float(PotData.phase(3)["speed_scale"]) > float(PotData.phase(1)["speed_scale"])
		and float(PotData.phase(last)["speed_scale"]) > float(PotData.phase(3)["speed_scale"]))
	_check("锅的存活时间逐阶段变短（压力感来自这里）",
		float(PotData.phase(1)["life_scale"]) < float(PotData.phase(0)["life_scale"])
		and float(PotData.phase(last)["life_scale"]) < float(PotData.phase(3)["life_scale"]))
	_check("只有最后 5 秒是疯狂甩锅时间（连击倍率 1.5 倍）",
		_near(float(PotData.phase(last)["until"] - float(PotData.phase(last - 1)["until"])), 5.0)
		and _near(float(PotData.phase(last)["combo_scale"]), 1.5)
		and float(PotData.phase(0)["combo_scale"]) == 1.0)
	_check("疯狂阶段的生成最快、同屏最多（最后 5 秒最爽）",
		float(PotData.phase(last)["interval"]) < 0.8
		and int(PotData.phase(last)["max_alive"]) >= 5)
	_check("热身阶段只有普通锅（先熟悉手感）",
		PotData.spawn_weights(0, ["normal"]).keys() == ["normal"])
	var all_pots := PotData.ids()
	_check("10 秒后开始出现不同锅（平底锅加入）",
		not PotData.spawn_weights(0, all_pots).has("pan")
		and PotData.spawn_weights(1, all_pots).has("pan"))
	_check("铁锅与压力锅到「混合」阶段（20 秒后）才上场",
		not PotData.spawn_weights(1, all_pots).has("iron")
		and not PotData.spawn_weights(1, all_pots).has("pressure")
		and PotData.spawn_weights(2, all_pots).has("iron")
		and PotData.spawn_weights(2, all_pots).has("pressure"))
	var consistent := true
	for i in PotData.phase_count():
		for id in PotData.spawn_weights(i, all_pots).keys():
			if i < PotData.get_pot(str(id)).min_phase:
				consistent = false
	_check("每种锅的 min_phase 与各阶段权重表一致（不会自相矛盾）", consistent)
	_check("「高压」阶段（30 秒后）五种锅会一起上",
		PotData.spawn_weights(3, all_pots).size() == 5,
		str(PotData.spawn_weights(3, all_pots).keys()))
	_check("锁定中的锅不会出现在生成表里",
		not PotData.spawn_weights(4, ["normal", "broken"]).has("iron"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var seen := {}
	for i in 400:
		seen[PotData.pick_type(4, PotData.ids(), rng)] = true
	_check("按权重抽样能抽到全部 5 种锅", seen.size() == 5, str(seen.keys()))


func _test_phase_lookup() -> void:
	var cases := {0.0: 0, 5.0: 0, 9.99: 0, 10.0: 1, 19.9: 1, 20.0: 2, 30.0: 3, 36.9: 3,
		37.0: 4, 41.9: 4, 42.0: 4, 99.0: 4}
	var ok := true
	var detail: Array = []
	for elapsed in cases.keys():
		var index := PotData.phase_index_at(float(elapsed))
		detail.append("%.1fs→%d" % [float(elapsed), index])
		if index != int(cases[elapsed]):
			ok = false
	_check("相位查表在边界上正确（10 / 20 / 30 / 37 秒换阶段）", ok, "、".join(detail))


func _test_spawn_flow() -> void:
	var game := make_game()
	skip_countdown(game)
	var pot := game.force_spawn("normal")
	_check("能生成一口锅", pot != null and pot.pot_id == "normal")
	_check("锅从老板那边飞出来（一开始不在场地里、也抓不到）",
		not pot.in_field and not pot.can_grab())
	advance(game, 1.2)
	_check("飞进场地后就可以抓了", pot.in_field and pot.can_grab())
	_check("场地里飘的速度换成了这口锅自己的飘移速度",
		absf(pot.velocity.length() - pot.drift_speed) < 1.0,
		"%.1f / %.1f" % [pot.velocity.length(), pot.drift_speed])
	var inside := true
	for i in 240:
		game.tick(1.0 / 60.0)
		if pot.is_active() and not game.field_rect().grow(12.0).has_point(pot.global_position):
			inside = false
			break
	_check("锅会在场地里弹来弹去，不会飞出可操作区域", inside)
	_check("场地里的锅带一句「锅话」", not pot.blame.is_empty(), pot.blame)
	_check("锅上的文字来自当前锅型",
		PotData.BLAME_LINES["normal"].has(pot.blame), pot.blame)


func _test_lifetime_and_slip() -> void:
	var game := make_game()
	skip_countdown(game)
	var broken := game.place_pot("broken", game.field_rect().get_center())
	_check("破锅的存活时间比普通锅短",
		broken.max_life < PotData.get_pot("normal").life_seconds,
		"%.1fs" % broken.max_life)
	var misses_before := game.misses()
	advance(game, broken.max_life + 0.4)
	_check("锅在场地里待太久会「凉了」，算一次失误",
		game.misses() == misses_before + 1 and game.combo() == 0,
		"失误 %d" % (game.misses() - misses_before))

	var iron := game.place_pot("iron", game.field_rect().get_center() + Vector2(0.0, 90.0))
	var small := game.place_pot("broken", game.field_rect().get_center() + Vector2(120.0, 90.0))
	_check("两口锅可以同时在场（新版本不再是「一次只有一口」）",
		game.active_pot_count() >= 2, str(game.active_pot_count()))
	game.pointer_press(small.global_position, 0)
	_check("一次只能拿一口锅", game.held_pot() == small)
	game.pointer_press(iron.global_position, 0)
	_check("手里有锅时点别的锅不会换手", game.held_pot() == small)
	var misses_before_slip := game.misses()
	advance(game, small.type.hold_window + 0.2)
	_check("破锅握久了会手滑（断连击、算失误）",
		game.misses() == misses_before_slip + 1, "失误 %d" % game.misses())
	game.pointer_release(game.field_rect().get_center(), 0)

	var pressure := game.place_pot("pressure", game.field_rect().get_center())
	game.pointer_press(pressure.global_position, 0)
	_check("压力锅刚拿到手时蓄力是 0", _near(pressure.charge_ratio(), 0.0, 0.02),
		"%.2f" % pressure.charge_ratio())
	advance(game, pressure.type.charge_time * 0.5)
	var half := pressure.charge_ratio()
	_check("握着压力锅时蓄力会涨", half > 0.3 and half < 0.8, "%.2f" % half)
	advance(game, pressure.type.charge_time * 0.55)
	_check("继续握下去会蓄满", pressure.charge_ratio() > 0.95,
		"%.2f" % pressure.charge_ratio())
	game.pointer_release(game.field_rect().get_center(), 0)


func _test_pool_is_fixed() -> void:
	var game := make_game()
	skip_countdown(game)
	var before := _count_nodes(game.get_node("World"))
	autoplay(game, 12.0)
	var after := _count_nodes(game.get_node("World"))
	_check("连着打 12 秒，世界节点数不变（锅全部复用对象池）", before == after,
		"%d → %d" % [before, after])
	_check("锅池永远是 12 口", game.pot_pool_size() == 12)
	_check("同屏锅数不会超过当前阶段上限",
		game.active_pot_count() <= int(PotData.phase(game.phase_index())["max_alive"]),
		"%d / %d" % [game.active_pot_count(), int(PotData.phase(game.phase_index())["max_alive"])])
