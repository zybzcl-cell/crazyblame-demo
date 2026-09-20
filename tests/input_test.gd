extends BlameTestBase
## 输入测试：鼠标与触摸走同一套 Pointer 逻辑（移动端优先，但桌面也要顺手）。


func run_tests() -> void:
	suite_name = "输入（鼠标 / 触摸）"
	_test_press_before_playing()
	_test_mouse_grab_and_drag()
	_test_mouse_flick()
	_test_touch_grab_and_drag()
	_test_touch_flick()
	_test_slow_release_is_not_a_miss()
	_test_wrong_direction_release()
	_test_second_finger_ignored()
	_test_tap_empty_space()
	free_game()


func _ready_game() -> BlameGame:
	var game := make_game()
	skip_countdown(game)
	return game


func _test_press_before_playing() -> void:
	var game := make_game()
	var pot := game.place_pot("normal", game.field_rect().get_center())
	push_mouse_press(pot.global_position)
	push_mouse_release(pot.global_position)
	_check("准备阶段点锅不会生效（还没开始）", game.held_pot() == null and game.hits() == 0)


func _test_mouse_grab_and_drag() -> void:
	var game := _ready_game()
	var pot := spawn_for_test(game, "normal")
	game.clear_pots(pot)
	push_mouse_press(pot.global_position)
	_check("鼠标按下：抓住锅", game.held_pot() == pot,
		"事件位置 %s，锅在 %s，阶段 %s" % [
			str(game.last_event_position), str(pot.global_position), game.state_name()])
	var t := 0.0
	while t < 1.2 and pot.is_held():
		push_mouse_move(game.boss().hit_center())
		game.tick(0.02)
		t += 0.02
	push_mouse_release(game.boss().hit_center())
	_check("鼠标拖动到老板身上：命中", game.hits() == 1, "命中 %d" % game.hits())


func _test_mouse_flick() -> void:
	var game := _ready_game()
	var pot := spawn_for_test(game, "normal")
	game.clear_pots(pot)
	push_mouse_press(pot.global_position)
	game.tick(0.02)
	# 朝老板方向快速划过：40 像素 / 0.02 秒 = 2000 像素/秒，超过甩出去的阈值
	push_mouse_move(pot.global_position + Vector2(0.0, -40.0))
	push_mouse_release(pot.global_position + Vector2(0.0, -40.0))
	_check("鼠标快速朝老板甩：锅被甩出去（而不是掉回场地）",
		pot.state == BlamePot.State.THROWN, str(pot.state))
	advance(game, 0.6)
	_check("甩出去的锅会打到老板", game.hits() == 1, "命中 %d" % game.hits())


func _test_touch_grab_and_drag() -> void:
	var game := _ready_game()
	var pot := spawn_for_test(game, "iron")
	game.clear_pots(pot)
	touch_press(pot.global_position)
	_check("触摸按下：抓住锅（触摸是核心操作）", game.held_pot() == pot)
	var start := pot.global_position
	game.tick(0.05)
	touch_move(pot.global_position + Vector2(120.0, 0.0))
	game.tick(0.05)
	_check("触摸拖动：锅跟着手指走", pot.global_position.x > start.x,
		"%.0f → %.0f" % [start.x, pot.global_position.x])
	var moved := pot.global_position
	game.tick(0.05)
	touch_move(moved + Vector2(0.0, 120.0))
	game.tick(0.05)
	_check("继续拖动：锅继续跟手", pot.global_position.y > moved.y,
		"%.0f → %.0f" % [moved.y, pot.global_position.y])
	touch_release(pot.global_position)
	_check("松手之后锅不再被拿着", game.held_pot() == null and not pot.is_held())


func _test_touch_flick() -> void:
	var game := _ready_game()
	var pot := spawn_for_test(game, "normal")
	game.clear_pots(pot)
	touch_press(pot.global_position)
	game.tick(0.02)
	touch_move(pot.global_position + Vector2(0.0, -40.0))
	touch_release(pot.global_position + Vector2(0.0, -40.0))
	_check("触摸快速上滑：锅被甩回老板", pot.state == BlamePot.State.THROWN, str(pot.state))
	advance(game, 0.6)
	_check("触摸甩锅也能打到老板", game.hits() == 1, "命中 %d" % game.hits())


func _test_slow_release_is_not_a_miss() -> void:
	var game := _ready_game()
	var pot := spawn_for_test(game, "normal")
	game.clear_pots(pot)
	touch_press(pot.global_position)
	game.tick(0.02)
	touch_move(pot.global_position + Vector2(0.0, -4.0))
	touch_release(pot.global_position + Vector2(0.0, -4.0))
	_check("慢慢放下：不算失误（手机上手指抖一下不该被罚）",
		game.misses() == 0 and game.held_pot() == null)
	_check("慢慢放下的锅会回到场地里继续飘",
		pot.state == BlamePot.State.FLYING and pot.can_grab(), str(pot.state))


func _test_wrong_direction_release() -> void:
	var game := _ready_game()
	var pot := spawn_for_test(game, "normal")
	game.clear_pots(pot)
	touch_press(pot.global_position)
	game.tick(0.02)
	# 朝下（远离老板）快速划过：方向不对，不算甩锅
	touch_move(pot.global_position + Vector2(0.0, 40.0))
	touch_release(pot.global_position + Vector2(0.0, 40.0))
	_check("朝反方向快速甩：锅只是掉回场地，不算甩歪",
		game.misses() == 0 and pot.state == BlamePot.State.FLYING, str(pot.state))


func _test_second_finger_ignored() -> void:
	var game := _ready_game()
	var pot := spawn_for_test(game, "normal")
	var other := spawn_for_test(game, "broken")
	_check("测试场上同时有两口锅", pot != null and other != null)
	touch_press(pot.global_position, 0)
	_check("第一根手指抓住锅", game.held_pot() == pot)
	touch_press(other.global_position, 1)
	_check("第二根手指不会抢走手里的锅", game.held_pot() == pot)
	touch_move(other.global_position + Vector2(50.0, 0.0), 1)
	_check("第二根手指拖动也不会影响手中的锅", game.held_pot() == pot)
	touch_release(other.global_position, 1)
	_check("第二根手指松开也不影响手里的锅", game.held_pot() == pot)
	touch_release(pot.global_position, 0)
	_check("第一根手指松开才真正放手", game.held_pot() == null)


func _test_tap_empty_space() -> void:
	var game := _ready_game()
	var empty := game.field_rect().position + Vector2(8.0, 8.0)
	var before := game.empty_clicks()
	touch_press(empty)
	touch_release(empty)
	_check("点空地只记一次空点，不算失误",
		game.empty_clicks() == before + 1 and game.misses() == 0,
		"空点 %d / 失误 %d" % [game.empty_clicks(), game.misses()])
