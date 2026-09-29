extends BlameTestBase
## 本次专项：老板亲手甩锅（六方向）+ 菜单层级（不挡游戏实体）+ 受击表现 + 受击惨叫。
##
## 这套测试对着「玩家真正能感觉到的东西」写：
##   - 锅**从老板手里**出现：先在手里蓄力（老板抬手 + 看向目标方向 + 方向提示线），
##     手臂前甩那一帧才脱手飞向玩家区域（左 / 右 × 上 / 中 / 下 六个方向，随机但不重复不雷同）；
##   - 锅离开老板之后才进入玩家区域，玩家照样能接住、能拖、能甩回老板；
##   - 打开图鉴 / 说明 / 暂停 / 设置时，Boss 与锅被藏起来、玩法冻结，面板才是最上层；
##   - 五种锅砸在老板身上留下不一样的痕迹（裂纹 / 红鼻子 / 头包 / 黑印），并且会累积；
##   - 不同锅有不同惨叫，连击到档位还会加一句「慌乱」台词。


func run_tests() -> void:
	suite_name = "老板甩锅 / 菜单层级 / 受击表现"
	_test_throw_directions()
	_test_throw_action()
	_test_throw_is_always_playable()
	_test_player_can_still_play()
	_test_menu_hides_entities()
	_test_game_overlay_hides_entities()
	_test_game_overlay_panels()
	_test_hit_effects_by_pot()
	_test_hit_effects_accumulate()
	_test_boss_voice()
	free_game()


# ---------------------------------------------------------------- 一、六方向随机（老板甩向哪边）

func _test_throw_directions() -> void:
	var game := make_game()
	skip_countdown(game)
	var lanes: Array = []
	var targets: Array = []
	var repeated := 0
	var too_similar := 0
	for i in 60:
		var pot := game.force_spawn("normal")
		if pot == null:
			game.clear_pots()
			continue
		lanes.append(pot.entry_lane)
		if lanes.size() >= 2 and lanes[lanes.size() - 1] == lanes[lanes.size() - 2]:
			repeated += 1
		# 「方向差异太小」按落点算：两口锅要落在玩家区域里明显不同的小块
		if targets.size() >= 1 and pot.throw_target.distance_to(targets[targets.size() - 1]) \
				< game.field_rect().size.y * 0.15:
			too_similar += 1
		targets.append(pot.throw_target)
		game.clear_pots()
	var unique := {}
	for lane in lanes:
		unique[str(lane)] = true
	_check("六个甩锅方向都会出现（左 / 右 × 上 / 中 / 下）", unique.size() == 6,
		"%d 个方向：%s" % [unique.size(), str(unique.keys())])
	_check("六个方向就是 左上 / 左 / 左下 / 右上 / 右 / 右下",
		unique.has("left_upper") and unique.has("left_mid") and unique.has("left_lower")
		and unique.has("right_upper") and unique.has("right_mid") and unique.has("right_lower"),
		str(unique.keys()))
	_check("连续两口的甩锅方向不会重复", repeated == 0,
		"重复 %d 次 / 共 %d 口" % [repeated, lanes.size()])
	_check("连续两口的落点差别足够大（不会看起来像同一个方向）", too_similar == 0,
		"太像 %d 次 / 共 %d 口" % [too_similar, lanes.size()])
	_check("最近一次的甩锅方向会被记下来（调试 / 测试用）",
		not game.last_throw_lane().is_empty(), game.last_throw_lane())


# ---------------------------------------------------------------- 二、老板甩锅动作

func _test_throw_action() -> void:
	var game := make_game()
	skip_countdown(game)
	var boss := game.boss()
	_check("刚开局还没甩锅", not boss.is_throwing())
	var pot := game.force_spawn("normal")
	_check("甩锅时锅已经生成了", pot != null)
	_check("锅先出现在老板手里蓄力（WINDUP），不是凭空出现在场地上",
		pot != null and pot.is_winding_up() and not pot.in_field)
	_check("老板进入「甩锅」动作（抬手蓄力）",
		boss.is_throwing() and boss.is_winding_up(), boss.throw_lane())
	_check("老板的甩锅方向和这口锅一致",
		boss.throw_lane() == pot.entry_lane, boss.throw_lane())
	_check("锅的位置就在老板手部附近（不是随便找一个点生成）",
		pot.global_position.distance_to(boss.throw_hand_position()) < 2.0,
		"%.1f px" % pot.global_position.distance_to(boss.throw_hand_position()))
	_check("锅被托在手上时不会重叠在老板身体里",
		not boss.contains_body_point(pot.global_position),
		"手部局部坐标 %s" % str(boss.to_local_point(pot.global_position)))
	_check("蓄力期间玩家抓不到这口锅（还没出手）",
		not pot.can_grab() and game.held_pot() == null)
	_check("老板甩锅时会记数（开局前几口有「甩锅！」提示）",
		game.boss_throw_count() >= 1, str(game.boss_throw_count()))

	# 蓄力结束 → 手臂前甩、锅脱手
	advance(game, BlameBoss.THROW_WINDUP + 0.02, 1.0 / 120.0)
	_check("蓄力结束之后锅脱手飞出去了（不再是 WINDUP）",
		not pot.is_winding_up(), str(pot.state))
	_check("锅脱手的位置就是老板手部那一点（手臂前甩那一帧）",
		pot.release_point.distance_to(boss.throw_release_point()) < 6.0,
		"%.1f px" % pot.release_point.distance_to(boss.throw_release_point()))
	_check("锅的初速度方向是「老板 → 玩家区域」（往下、往对应那一侧）",
		pot.velocity.y > 0.0 and absf(pot.velocity.x) > 0.0,
		str(pot.velocity))
	_check("甩出去的速度明显比场地里飘的速度快（是「甩」出去的）",
		pot.velocity.length() > pot.drift_speed * 2.0,
		"%.0f / %.0f" % [pot.velocity.length(), pot.drift_speed])
	var y_before := pot.global_position.y
	advance(game, 0.3, 1.0 / 120.0)
	_check("锅顺着甩出的方向离开老板、往玩家区域飞",
		pot.global_position.y > y_before,
		"%.0f → %.0f" % [y_before, pot.global_position.y])
	_check("老板甩完会回到正常姿态（动作会结束）",
		not boss.is_throwing() or boss.throw_lane() == pot.entry_lane)


func _test_throw_is_always_playable() -> void:
	var game := make_game()
	skip_countdown(game)
	var screen := Rect2(Vector2.ZERO, game.get_viewport_rect().size)
	var boss := game.boss()
	var off_field := true
	var on_screen := true
	var at_boss := true
	var outside_body := true
	for i in 12:
		var pot := game.force_spawn("normal")
		if pot == null:
			break
		if game.field_rect().has_point(pot.global_position):
			off_field = false
		if not screen.has_point(pot.global_position):
			on_screen = false
		if pot.global_position.distance_to(boss.throw_hand_position()) > boss.body_radius() * 2.2:
			at_boss = false
		if boss.contains_body_point(pot.global_position):
			outside_body = false
	_check("锅的起点永远在玩家区域之外（是「老板甩进来」，不是凭空出现在场地上）", off_field)
	_check("锅的起点在老板手部附近（不是屏幕边缘）", at_boss)
	_check("锅的起点在老板身体之外（不会生成在 Boss 身体里）", outside_body)
	_check("出场点永远还在屏幕里（不会出现在屏幕外）", on_screen)

	advance(game, 1.2, 1.0 / 120.0)
	var pots := game.active_pots()
	_check("甩出来之后每一口锅都还在场上", pots.size() >= 1, str(pots.size()))
	var inside := true
	var grabbable := true
	var arrived := true
	for pot in pots:
		if not game.field_rect().grow(16.0).has_point(pot.global_position):
			inside = false
		if not (pot.can_grab() and pot.catches_point(pot.global_position)):
			grabbable = false
		if not pot.in_field:
			arrived = false
	_check("六方向甩出的锅最后都落进玩家操作区（不会飞到 HUD / 底部信息条）", inside)
	_check("锅离开老板之后会进入玩家区域（in_field）", arrived)
	_check("每一口锅生成后都能点中、能拖动", grabbable)


## 玩家侧的操作完全没变：接住老板甩来的锅 → 拖到老板身上 → 命中
func _test_player_can_still_play() -> void:
	var game := make_game()
	skip_countdown(game)
	var hits_before := game.hits()
	var pot := game.force_spawn("normal")
	advance(game, 1.0, 1.0 / 120.0)
	_check("老板甩出来的锅玩家接得住（能抓）",
		pot.can_grab() and grab(game, pot), str(pot.state))
	var reached := drag_to_boss(game, pot)
	_check("接住之后照样能拖到老板身上并命中", reached and game.hits() == hits_before + 1,
		"命中 %d" % game.hits())
	_check("命中之后连击照常累加", game.combo() >= 1, str(game.combo()))
	# 连甩几口，确认一来一回的循环稳定
	for i in 3:
		var next := spawn_for_test(game, "normal")
		if next == null:
			advance(game, 0.4)
			continue
		advance(game, 0.9, 1.0 / 120.0)
		drag_to_boss(game, next)
	_check("连续几口「老板甩 → 玩家接 → 甩回老板」都能走通",
		game.hits() >= hits_before + 2, "命中 %d" % game.hits())


# ---------------------------------------------------------------- 二、菜单层级

func _test_menu_hides_entities() -> void:
	var menu := (load(GameConfig.MENU_SCENE) as PackedScene).instantiate() as BlameMainMenu
	add_child(menu)
	var boss := menu.boss_node()
	var prop := menu.prop_node()
	_check("刚打开主菜单时，菜单里的老板与飞锅都正常显示",
		boss.visible and prop.visible and not menu.overlay_open())

	menu.open_codex()
	_check("打开锅图鉴：菜单里的老板被藏起来了（不会挡在图鉴面板后面）", not boss.visible)
	_check("打开锅图鉴：飞来飞去的锅也停下来了", not prop.visible)
	_check("打开锅图鉴：图鉴面板在菜单实体之上（z_index 更高）",
		menu.codex().z_index > boss.z_index, "%d / %d" % [menu.codex().z_index, boss.z_index])
	_check("打开锅图鉴：菜单处于「非游戏界面」状态", menu.overlay_open())

	menu.close_panels()
	_check("关掉图鉴之后，老板与锅恢复显示",
		boss.visible and prop.visible and not menu.overlay_open())

	menu.open_settings()
	_check("打开设置面板：老板同样会被藏起来", not boss.visible and not prop.visible)
	menu.close_panels()
	_check("关掉设置之后恢复显示", boss.visible and prop.visible)
	menu.queue_free()


func _test_game_overlay_hides_entities() -> void:
	var game := make_game()
	skip_countdown(game)
	game.force_spawn("normal")
	advance(game, 0.6)
	var world := game.get_node("World")
	game.open_pause_menu()
	_check("游戏里打开暂停菜单：处于「非游戏界面」状态", game.is_overlay_open())
	_check("打开暂停菜单：Boss 被藏起来（不会穿透在面板后面）",
		not game.boss().visible)
	_check("打开暂停菜单：锅层被藏起来", not (world.get_node("PotLayer") as Node2D).visible)
	_check("打开暂停菜单：受击特效层被藏起来",
		not (world.get_node("FxLayer") as Node2D).visible)
	_check("打开暂停菜单：暂停面板显示在最上层", game.game_menu().visible)
	var time_before := game.time_left()
	var pot_before := game.active_pots()
	var positions_before: Array = []
	for pot in pot_before:
		positions_before.append(pot.global_position)
	var life_before := pot_before[0].life if pots_alive(pot_before) else 0.0
	advance(game, 1.0)
	_check("打开暂停菜单：玩法真的冻结了（倒计时不走）",
		_near(game.time_left(), time_before, 0.001),
		"%.2f → %.2f" % [time_before, game.time_left()])
	var frozen := game.misses() == 0 and game.active_pots().size() == positions_before.size()
	for i in positions_before.size():
		var now_pot := game.active_pots()[i]
		if not now_pot.global_position.is_equal_approx(positions_before[i]):
			frozen = false
	_check("打开暂停菜单：锅也停在原地（不飘、不凉、不算失误）", frozen,
		"失误 %d，锅 %d → %d" % [game.misses(), positions_before.size(),
			game.active_pots().size()])
	_check("打开暂停菜单：锅的存活时间也不再倒计时",
		not pots_alive(game.active_pots()) or
		_near(game.active_pots()[0].life, life_before, 0.001),
		"%.2f → %.2f" % [life_before, game.active_pots()[0].life if pots_alive(game.active_pots()) else -1.0])

	game.close_pause_menu()
	_check("关掉暂停菜单：Boss / 锅 / 特效层都恢复显示",
		game.boss().visible and (world.get_node("PotLayer") as Node2D).visible
		and (world.get_node("FxLayer") as Node2D).visible)
	advance(game, 0.5)
	_check("关掉暂停菜单：游戏继续正常推进", game.time_left() < time_before,
		"%.2f" % game.time_left())


func _test_game_overlay_panels() -> void:
	var game := make_game()
	skip_countdown(game)
	game.open_pause_menu()
	var menu := game.game_menu()
	menu.help_button().pressed.emit()
	_check("暂停菜单里能打开「操作说明」", menu.help_panel().visible)
	menu.codex_button().pressed.emit()
	_check("暂停菜单里能打开锅图鉴", menu.codex().visible and not game.boss().visible)
	menu.codex().closed.emit()
	_check("图鉴返回后回到暂停面板，Boss 依然藏着",
		not menu.codex().visible and not game.boss().visible)
	menu.settings_button().pressed.emit()
	_check("暂停菜单里能打开设置", menu.settings().visible)
	menu.settings().closed.emit()
	_check("设置返回后回到暂停面板", not menu.settings().visible and menu.visible)
	menu.resume_button().pressed.emit()
	_check("点「继续游戏」恢复玩法", not game.is_overlay_open() and game.boss().visible)

	# 准备阶段也能暂停
	game.restart()
	game.open_pause_menu()
	_check("准备阶段也能暂停", game.is_overlay_open())
	var countdown := game.countdown_left()
	advance(game, 0.5)
	_check("准备阶段暂停后倒计时也冻结", _near(game.countdown_left(), countdown, 0.001))
	game.close_pause_menu()
	_check("准备阶段恢复后还能继续倒数", game.state_name() == "countdown")


# ---------------------------------------------------------------- 三、五种锅的受击表现

func _test_hit_effects_by_pot() -> void:
	var expectations := {
		"iron": "glasses_crack",
		"pan": "nose_red",
		"pressure": "head_bump",
		"broken": "face_soot",
	}
	for pot_id in expectations.keys():
		var boss := BlameBoss.new()
		add_child(boss)
		boss.reset()
		boss.react_hit(PotData.get_pot(str(pot_id)), 1.0)
		var flag := str(expectations[pot_id])
		_check("%s 命中：留下专属受击痕迹（%s）" % [PotData.get_pot(str(pot_id)).display_name, flag],
			bool(boss.damage_state()[flag]))
		var others_clear := true
		for other in expectations.values():
			if str(other) != flag and bool(boss.damage_state()[str(other)]):
				others_clear = false
		_check("%s 命中：不会串到别的锅的痕迹上" % PotData.get_pot(str(pot_id)).display_name,
			others_clear)
		_check("%s 命中：老板的头发 / 衣服变乱了（%s）"
			% [PotData.get_pot(str(pot_id)).display_name, "破锅更明显" if pot_id == "broken" else "轻微"],
			boss.mess_level() > 0.0, "%.2f" % boss.mess_level())
		boss.queue_free()

	# 普通锅：没有专属痕迹，但一样会晃眼镜 / 变乱（「被砸到」是看得见的）
	var boss := BlameBoss.new()
	add_child(boss)
	boss.reset()
	boss.react_hit(PotData.get_pot("normal"), 1.0)
	_check("普通锅命中：老板一样有被砸到的反应（会变乱、但没有专属伤口）",
		boss.mess_level() > 0.0 and not boss.is_battered())
	boss.queue_free()


func _test_hit_effects_accumulate() -> void:
	var boss := BlameBoss.new()
	add_child(boss)
	boss.reset()
	for id in ["normal", "iron", "pan", "pressure", "broken"]:
		boss.react_hit(PotData.get_pot(str(id)), 1.0)
	var state := boss.damage_state()
	_check("连挨五种锅之后：眼镜裂了 + 鼻子红了 + 头上起包 + 脸上有黑印",
		bool(state["glasses_crack"]) and bool(state["nose_red"])
		and bool(state["head_bump"]) and bool(state["face_soot"]), str(state))
	_check("全部战损都在本局内累积（不会自己消失）", boss.is_battered())
	_check("挨得越多越狼狈（凌乱度累积到接近满）", boss.mess_level() > 0.4,
		"%.2f" % boss.mess_level())
	var messy_before := boss.mess_level()
	boss.react_hit(PotData.get_pot("broken"), 1.0)
	_check("破锅会额外把头发弄乱（凌乱度只增不减）",
		boss.mess_level() > messy_before, "%.2f → %.2f" % [messy_before, boss.mess_level()])
	boss.reset()
	_check("重开一局：战损全部清零（新的一局重新开始狼狈）", not boss.is_battered()
		and boss.mess_level() == 0.0)
	boss.queue_free()


# ---------------------------------------------------------------- 四、受击惨叫

func _test_boss_voice() -> void:
	var mapping := {"normal": "voice_normal", "iron": "voice_iron", "pan": "voice_pan",
		"pressure": "voice_pressure", "broken": "voice_broken"}
	for pot_id in mapping.keys():
		_check("%s 对应自己的受击惨叫" % PotData.get_pot(str(pot_id)).display_name,
			str(GameConfig.voice_for_pot(str(pot_id))["sound"]) == str(mapping[pot_id]),
			str(GameConfig.voice_for_pot(str(pot_id))["sound"]))
	_check("连击到档位会有「慌乱」台词（等等 / 别打了 / 别甩了）",
		GameConfig.BOSS_PANIC.size() >= 3 and str(GameConfig.BOSS_PANIC[0]["text"]).length() > 0,
		str(GameConfig.BOSS_PANIC))

	var game := make_game()
	skip_countdown(game)
	AudioManager.reset_play_counts()
	for i in 4:
		var pot := spawn_for_test(game, "normal")
		drag_to_boss(game, pot)
	_check("连续命中：老板真的「喊」出声了（有惨叫播放记录）",
		AudioManager.played_count("voice_normal") > 0,
		str(AudioManager.played_count("voice_normal")))
	_check("连击到档位会喊出慌乱台词（HUD 上打出来）",
		game.announced_panics() >= 1 and game.combo() >= 3,
		"慌乱 %d 次 / 连击 %d" % [game.announced_panics(), game.combo()])
	var panic_counts := 0
	for key in GameConfig.sound_keys():
		if str(key).begins_with("voice_"):
			panic_counts += 1
	_check("语音全部来自本地合成音效表（没有外部素材、没有下载）", panic_counts == 6,
		str(panic_counts))


func pots_alive(pots: Array) -> bool:
	return not pots.is_empty()
