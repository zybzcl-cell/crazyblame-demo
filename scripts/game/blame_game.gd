class_name BlameGame
extends Node2D
## 《疯狂甩锅》的游戏主体。
##
## 一局 = 3 秒准备 + 42 秒正式游戏（约 45 秒），面板左上是老板的「精神状态」，
## 玩法流程：老板把锅甩过来 → 玩家点住锅拖到老板身上（或者朝老板甩出去）→ 老板挨锅。
##
## 这里只做「规则与判定」，画面交给三个独立的节点：
##   World/Boss      BlameBoss      老板（七个阶段的表演）
##   World/PotLayer  BlamePot       锅（对象池，开局一次建好，之后只复用）
##   World/FxLayer   FxLayer        伤害数字 / 冲击 / 连击台词 / 彩带
##   HUD/Root        BlameHud       所有界面（倒计时、分数、连击、老板血条、结算卡）
##
## 测试可以关掉 _process 自己调 tick(delta)，把 45 秒瞬间推完。

signal finished(result: Dictionary)
signal hit_landed(info: Dictionary)
signal missed(info: Dictionary)
signal phase_changed(index: int)

enum State { IDLE, COUNTDOWN, PLAYING, ENDING, RESULT }

## 锅池大小：同屏最多 5 口 + 结算动画里的几口，够用且一局里不会新建节点
const POT_POOL_SIZE := 12

@onready var _world: Node2D = $World
@onready var _background: OfficeBackground = $World/Background
@onready var _boss: BlameBoss = $World/Boss
@onready var _pot_layer: Node2D = $World/PotLayer
@onready var _fx: FxLayer = $World/FxLayer
@onready var _hud: BlameHud = $HUD/Root

var _state: State = State.IDLE
var _pots: Array[BlamePot] = []
var _held: BlamePot = null
var _enabled_pots: Array = []

var _field := Rect2(0.0, 0.0, 720.0, 600.0)
var _pot_scale := 1.0
## 当前这一屏的构图预算（顶部 HUD / 办公室 / 老板 / 操作区 / 底部信息）
var _layout_data: Dictionary = {}

var _countdown := 0.0
var _countdown_step := 99
var _elapsed := 0.0
var _time_left := 0.0
var _spawn_timer := 0.0
var _phase := 0

var _raw_score := 0.0
var _combo := 0
var _best_combo := 0
var _hits := 0
var _misses := 0
var _empty_clicks := 0
var _damage_dealt := 0
var _frenzy_hits := 0
var _throws := 0
var _pot_hits: Dictionary = {}
var _announced_combo: Array[int] = []

var _end_timer := 0.0
var _end_reason := ""
var _result: Dictionary = {}

var _pointer_down := false
var _pointer_id := -1
var _pointer_pos := Vector2.ZERO
var _last_pointer_pos := Vector2.ZERO
var _pointer_velocity := Vector2.ZERO
var _pointer_delta := 1.0 / 60.0

var _shake := 0.0
var _seed := 0
var _rng := RandomNumberGenerator.new()
## 收到过多少个输入事件（测试 / 调试用：确认鼠标与触摸真的走到这里）
var input_events := 0
## 最近一次输入事件的位置（测试 / 调试用）
var last_event_position := Vector2.ZERO


func _ready() -> void:
	_rng.randomize()
	_enabled_pots = ProgressManager.enabled_pots()
	for i in POT_POOL_SIZE:
		var pot := BlamePot.new()
		pot.z_index = 2
		_pot_layer.add_child(pot)
		_pots.append(pot)
	_hud.restart_requested.connect(restart)
	_hud.menu_requested.connect(go_to_menu)
	_hud.quit_requested.connect(go_to_menu)
	get_viewport().size_changed.connect(_on_viewport_resized)
	_layout()
	start()


func _process(delta: float) -> void:
	tick(delta)


# ---------------------------------------------------------------- 生命周期

## 开始新的一局（准备阶段）。测试和「再甩一局」都走这里。
func start() -> void:
	if _seed == 0:
		_rng.randomize()
	else:
		_rng.seed = _seed
	_state = State.COUNTDOWN
	_countdown = GameConfig.COUNTDOWN_SECONDS
	_countdown_step = int(GameConfig.COUNTDOWN_SECONDS) + 1
	_elapsed = 0.0
	_time_left = GameConfig.PLAY_SECONDS
	_spawn_timer = 0.35
	_phase = 0
	_raw_score = 0.0
	_combo = 0
	_best_combo = 0
	_hits = 0
	_misses = 0
	_empty_clicks = 0
	_damage_dealt = 0
	_frenzy_hits = 0
	_throws = 0
	_pot_hits = {}
	_announced_combo.clear()
	_end_timer = 0.0
	_end_reason = ""
	_result = {}
	_held = null
	_pointer_down = false
	_pointer_id = -1
	_shake = 0.0
	position = Vector2.ZERO
	for pot in _pots:
		pot.hibernate()
	_boss.reset()
	_background.set_stress(1.0)
	_background.set_frenzy(false)
	_fx.clear()
	_enabled_pots = ProgressManager.enabled_pots()
	_hud.hide_result()
	_hud.reset_for_round()
	_hud.set_countdown(int(ceil(_countdown)))
	_hud.show_banner(GameConfig.READY_TITLE, Palette.ACCENT)
	_hud.set_hint(GameConfig.READY_HINT)
	_hud.set_phase(str(PotData.phase(0)["name"]))
	_refresh_hud()
	AudioManager.play("countdown")


func restart() -> void:
	start()


func go_to_menu() -> void:
	get_tree().change_scene_to_file(GameConfig.MENU_SCENE)


# ---------------------------------------------------------------- 主循环

## 推进一帧（测试直接调用它，不用真的等 45 秒）
func tick(delta: float) -> void:
	_pointer_delta = maxf(delta, 1.0 / 240.0)
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 3.2, 0.0)
		_world.position = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) \
			* _shake * 12.0
	elif _world.position != Vector2.ZERO:
		_world.position = Vector2.ZERO
	_background.tick(delta)
	_boss.tick(delta)
	_fx.tick(delta)
	_hud.tick(delta)
	match _state:
		State.COUNTDOWN:
			_tick_countdown(delta)
		State.PLAYING:
			_tick_playing(delta)
		State.ENDING:
			_tick_ending(delta)
		_:
			pass


func _tick_countdown(delta: float) -> void:
	_countdown -= delta
	var step := int(ceil(_countdown))
	if step != _countdown_step and step > 0:
		_countdown_step = step
		_hud.set_countdown(step)
		AudioManager.play("countdown")
	if _countdown <= 0.0:
		_hud.set_countdown(0)
		_state = State.PLAYING
		_spawn_timer = 0.3
		_hud.show_banner("甩！", Palette.ACCENT)
		_hud.set_hint("")
		AudioManager.play("go")
		Haptics.medium()
	_refresh_hud()


func _tick_playing(delta: float) -> void:
	_elapsed += delta
	_time_left = maxf(GameConfig.PLAY_SECONDS - _elapsed, 0.0)
	var next_phase := PotData.phase_index_at(_elapsed)
	if next_phase != _phase:
		_set_phase(next_phase)

	# 手里的锅跟着手指走
	if _held != null and is_instance_valid(_held) and _held.is_held() and _pointer_down:
		_held.follow(_pointer_pos, delta)

	# 生成新锅
	if _time_left > 0.0:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			if _actionable_count() < int(PotData.phase(_phase)["max_alive"]):
				_spawn_pot()
				_spawn_timer = float(PotData.phase(_phase)["interval"]) * _rng.randf_range(0.9, 1.12)
			else:
				_spawn_timer = 0.25

	# 锅的行为与判定
	for pot in _pots:
		if not pot.is_active():
			continue
		pot.tick(delta)
		_check_pot(pot, delta)

	if _time_left <= 0.0:
		_begin_end("time")
	_refresh_hud()


func _tick_ending(delta: float) -> void:
	_end_timer += delta
	for pot in _pots:
		if pot.is_active():
			pot.tick(delta)
	var wait := GameConfig.KO_RESULT_DELAY if _end_reason == "ko" else GameConfig.RESULT_DELAY
	if _end_timer >= wait:
		_begin_result()
	_refresh_hud()


func _check_pot(pot: BlamePot, delta: float) -> void:
	match pot.state:
		BlamePot.State.FLYING:
			if pot.in_field:
				pot.life -= delta
				if pot.life <= 0.0:
					_miss(pot, "锅凉了！")
		BlamePot.State.HELD:
			if pot.held_time > pot.type.hold_window:
				_miss(pot, "手滑了！")
			elif pot.global_position.distance_to(_boss.hit_center()) <= _boss.hit_radius():
				_hit(pot)
		BlamePot.State.THROWN:
			if pot.global_position.distance_to(_boss.hit_center()) <= _boss.hit_radius():
				_hit(pot)
			elif pot.throw_time > GameConfig.THROWN_LIFETIME \
					or absf(pot.global_position.x - _field.get_center().x) > _field.size.x \
					or pot.global_position.y < _boss.hit_center().y - _boss.hit_radius():
				_miss(pot, "甩歪了！")
		_:
			pass


# ---------------------------------------------------------------- 生成

## 挑一口空闲的锅开始工作（池子里没有空闲的就这一帧不生成）
func _spawn_pot(forced_id: String = "") -> BlamePot:
	var pot := _free_pot()
	if pot == null:
		return null
	var phase := PotData.phase(_phase)
	var pot_id := forced_id
	if pot_id.is_empty():
		pot_id = PotData.pick_type(_phase, _enabled_pots, _rng)
	var type := PotData.get_pot(pot_id)
	if type == null:
		type = PotData.get_pot("normal")
	var speed_scale := float(phase["speed_scale"]) * _rng.randf_range(0.92, 1.12)
	var life := type.life_seconds * float(phase["life_scale"])
	var boss_pos := _boss.global_position
	var start := boss_pos + Vector2(
		_rng.randf_range(-_boss.body_radius() * 1.1, _boss.body_radius() * 1.1),
		_boss.body_radius() * 0.35)
	var target := Vector2(
		_rng.randf_range(_field.position.x + 90.0, _field.end.x - 90.0),
		_rng.randf_range(_field.position.y + 90.0, _field.end.y - 90.0))
	var direction := (target - start).normalized()
	pot.wander = 0.34 if pot_id == "pan" else (0.42 if pot_id == "broken" else 0.22)
	pot.launch(type, PotData.blame_line(pot_id, _rng), _field, start, direction,
		980.0, life, _pot_scale)
	pot.drift_speed = type.drift_speed * speed_scale
	return pot


func _free_pot() -> BlamePot:
	for pot in _pots:
		if not pot.is_active():
			return pot
	return null


func _actionable_count() -> int:
	var count := 0
	for pot in _pots:
		if pot.is_actionable():
			count += 1
	return count


func _set_phase(index: int) -> void:
	_phase = clampi(index, 0, PotData.phase_count() - 1)
	var phase := PotData.phase(_phase)
	_hud.set_phase(str(phase["name"]))
	_hud.show_banner(str(phase["banner"]), Palette.ACCENT if _phase < 4 else Palette.DANGER)
	_boss.set_speech(str(phase["line"]), 2.2)
	if _phase >= PotData.phase_count() - 1:
		_background.set_frenzy(true)
		_hud.set_frenzy(true)
		AudioManager.play("frenzy")
		_fx.spawn_ring(_boss.hit_center(), Palette.DANGER, _boss.hit_radius() * 1.6, 8.0)
		Haptics.medium()
	else:
		AudioManager.play("phase_up")
	phase_changed.emit(_phase)


# ---------------------------------------------------------------- 命中 / 失误

func _hit(pot: BlamePot) -> void:
	if pot == null or not pot.is_actionable():
		return
	var type := pot.type
	var charge := pot.charge_ratio() if pot.is_held() else pot.hit_charge
	var damage := type.damage_for(charge)
	var frenzy := _phase >= PotData.phase_count() - 1

	_combo += type.combo_step
	_best_combo = maxi(_best_combo, _combo)
	_hits += 1
	_throws += 1
	_damage_dealt += damage
	_pot_hits[type.id] = int(_pot_hits.get(type.id, 0)) + 1
	if frenzy:
		_frenzy_hits += 1
	var points := Score.hit_points(type, _combo, pot.age, frenzy, charge)
	_raw_score += float(points)

	if _held == pot:
		_held = null
	pot.resolve(true, _boss.hit_center())

	var strength := clampf(float(damage) / 15.0, 0.4, 1.6)
	var stage_changed := _boss.set_hp(_boss.hp - damage)
	_boss.react_hit(type, strength)
	_background.set_stress(_boss.hp_ratio())
	_shake = maxf(_shake, 0.35 + 0.55 * strength)

	var color := Palette.DAMAGE_TEXT
	var sound := "hit_light"
	if damage >= 20:
		color = Palette.CRIT_TEXT
		sound = "hit_crit"
	elif damage >= 15:
		color = Palette.HEAVY_TEXT
		sound = "hit_heavy"
	elif damage >= 8:
		color = Palette.COMBO_TEXT
		sound = "hit_medium"
	var huge := charge >= 0.95 and type.needs_charge
	_fx.spawn_damage(_boss.hit_center() + Vector2(0.0, -20.0),
		"-%d" % damage, color, 40.0 + 16.0 * strength)
	if type.needs_charge and charge >= 0.95:
		_fx.spawn_damage(_boss.hit_center() + Vector2(0.0, 26.0), "压力拉满！",
			Palette.CRIT_TEXT, 30.0)
	_fx.spawn_burst(_boss.hit_center(), Palette.CRIT_TEXT if huge else color, strength)
	_fx.spawn_ring(_boss.hit_center(), Color(color, 0.9),
		_boss.hit_radius() * (0.9 + 0.5 * strength), 6.0)
	AudioManager.play(sound)
	AudioManager.play_combo(_combo)
	if damage < 15:
		Haptics.medium()
	else:
		Haptics.heavy()
	if stage_changed and not _boss.is_ko():
		_on_boss_stage_changed()
	_announce_combo()
	hit_landed.emit({
		"pot_id": type.id, "damage": damage, "combo": _combo, "points": points,
		"charge": charge, "frenzy": frenzy,
	})
	if _boss.hp <= 0:
		_begin_end("ko")


## 老板换表情：给他一点「变脸」的仪式感
func _on_boss_stage_changed() -> void:
	AudioManager.play("boss_stage")
	Haptics.heavy()
	_background.flash()
	_fx.spawn_ring(_boss.hit_center(), Palette.DANGER, _boss.hit_radius() * 1.5, 8.0)
	_hud.show_toast("老板：%s！" % _boss.stage_name(), Palette.DANGER)


func _miss(pot: BlamePot, reason: String) -> void:
	if pot == null or not pot.is_actionable():
		return
	if _held == pot:
		_held = null
	_misses += 1
	_combo = 0
	var slip := reason.begins_with("手滑")
	pot.resolve(false, _boss.hit_center())
	_fx.spawn_damage(pot.global_position, reason, Palette.MISS_TEXT, 26.0)
	AudioManager.play("slip" if slip else "miss")
	Haptics.light()
	missed.emit({"pot_id": pot.pot_id, "reason": reason})


func _announce_combo() -> void:
	for entry in GameConfig.COMBO_SHOUTS:
		var threshold := int(entry["combo"])
		if _combo < threshold or _announced_combo.has(threshold):
			continue
		_announced_combo.append(threshold)
		_hud.show_shout(str(entry["text"]))
		AudioManager.play("combo", 1.0 + 0.05 * float(threshold))


# ---------------------------------------------------------------- 结束与结算

func _begin_end(reason: String) -> void:
	if _state == State.ENDING or _state == State.RESULT:
		return
	_end_reason = reason
	_end_timer = 0.0
	_state = State.ENDING
	_pointer_down = false
	_held = null
	if reason == "ko":
		_boss.ko()
		_hud.show_banner(GameConfig.KO_BANNER, Palette.DANGER)
		_fx.spawn_ring(_boss.hit_center(), Palette.DANGER, _boss.hit_radius() * 2.2, 10.0)
		_fx.spawn_confetti(90, get_viewport_rect().size.x)
		AudioManager.play("boss_ko")
		Haptics.heavy()
	else:
		_hud.show_banner(GameConfig.TIMEUP_BANNER, Palette.ACCENT)
		_background.set_frenzy(false)
		AudioManager.play("result")
	_hud.set_frenzy(false)


func _begin_result() -> void:
	if _state == State.RESULT:
		return
	_state = State.RESULT
	_result = _build_result()
	var changes := ProgressManager.register_game(_result)
	_result["new_best"] = bool(changes["new_best"])
	_result["previous_best"] = int(changes["previous_best"])
	_result["unlocked"] = changes["unlocked"]
	if bool(changes["new_best"]) and int(changes["previous_best"]) > 0:
		_fx.spawn_confetti(60, get_viewport_rect().size.x)
		AudioManager.play("new_record")
	elif not (_result["unlocked"] as Array).is_empty():
		AudioManager.play("unlock")
	AudioManager.play("result")
	_hud.show_result(_result)
	finished.emit(_result)


func _build_result() -> Dictionary:
	var stats := {
		"hits": _hits,
		"misses": _misses,
		"best_combo": _best_combo,
		"damage_dealt": _damage_dealt,
		"frenzy_hits": _frenzy_hits,
		"pot_counts": _pot_hits.duplicate(),
	}
	var rating := Score.rating(stats)
	return {
		"score_points": int(round(_raw_score)),
		"rating_score": int(rating["score"]),
		"rating_grade": str(rating["grade"]),
		"rating_title": Score.grade_title(str(rating["grade"])),
		"rating_parts": rating["parts"],
		"hits": _hits,
		"misses": _misses,
		"empty_clicks": _empty_clicks,
		"accuracy": float(rating["accuracy"]),
		"best_combo": _best_combo,
		"damage_dealt": _damage_dealt,
		"boss_hp_left": _boss.hp,
		"boss_hp_max": _boss.max_hp,
		"boss_stage": _boss.stage_index(),
		"boss_stage_name": _boss.stage_name(),
		"boss_stage_color": _boss.stage_color(),
		"boss_ko": _boss.is_ko(),
		"frenzy_hits": _frenzy_hits,
		"pot_counts": _pot_hits.duplicate(),
		"throws": _throws,
		"duration": _elapsed,
		"end_reason": _end_reason,
	}


func result() -> Dictionary:
	return _result.duplicate(true)


# ---------------------------------------------------------------- 输入（鼠标 / 触摸同一套）

func _unhandled_input(event: InputEvent) -> void:
	input_events += 1
	if event is InputEventScreenTouch:
		last_event_position = (event as InputEventScreenTouch).position
	elif event is InputEventScreenDrag:
		last_event_position = (event as InputEventScreenDrag).position
	elif event is InputEventMouse:
		last_event_position = (event as InputEventMouse).position
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.index != 0:
			return
		if touch.pressed:
			pointer_press(touch.position, 0)
		else:
			pointer_release(touch.position, 0)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index != 0:
			return
		pointer_move(drag.position, 0)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			pointer_press(button.position, 0)
		else:
			pointer_release(button.position, 0)
	elif event is InputEventMouseMotion and _pointer_down:
		pointer_move((event as InputEventMouseMotion).position, _pointer_id)


func pointer_press(point: Vector2, id: int = 0) -> void:
	if _state != State.PLAYING or _pointer_down:
		return
	_pointer_down = true
	_pointer_id = id
	_pointer_pos = point
	_last_pointer_pos = point
	_pointer_velocity = Vector2.ZERO
	var pot := _pot_at(point)
	if pot == null:
		_empty_clicks += 1
		return
	_held = pot
	pot.grab()
	AudioManager.play("grab")
	Haptics.light()


func pointer_move(point: Vector2, id: int = 0) -> void:
	if not _pointer_down or id != _pointer_id:
		return
	_last_pointer_pos = _pointer_pos
	_pointer_pos = point
	_pointer_velocity = (_pointer_pos - _last_pointer_pos) / _pointer_delta


func pointer_release(point: Vector2, id: int = 0) -> void:
	if not _pointer_down or id != _pointer_id:
		return
	_pointer_pos = point
	_pointer_velocity = (point - _last_pointer_pos) / _pointer_delta
	_pointer_down = false
	_pointer_id = -1
	if _held == null or not is_instance_valid(_held) or not _held.is_held():
		_held = null
		return
	if _is_flick_toward_boss(_pointer_velocity):
		var direction := _pointer_velocity.normalized()
		var speed := maxf(_pointer_velocity.length() * GameConfig.FLICK_SPEED_FACTOR, 1000.0)
		_held.throw_back(direction * speed)
		AudioManager.play("throw_back")
		Haptics.light()
	else:
		_held.release_soft(_pointer_velocity)
	_held = null


## 滑动是否是「朝老板甩」（速度够快 + 方向大致对着老板）
func _is_flick_toward_boss(velocity: Vector2) -> bool:
	if velocity.length() < GameConfig.FLICK_MIN_SPEED:
		return false
	var target := _boss.hit_center() - _pointer_pos
	if target.length() < 1.0:
		return true
	# 用点积比角度（不受 angle_to 正负号影响），方向偏差超过容差就不算甩锅
	return velocity.normalized().dot(target.normalized()) \
		>= cos(GameConfig.FLICK_ANGLE_TOLERANCE)


## 找到手指下面最近的那口能抓的锅（判定圈按锅的类型算）
func _pot_at(point: Vector2) -> BlamePot:
	var best: BlamePot = null
	var best_distance := INF
	for pot in _pots:
		if not pot.can_grab():
			continue
		var distance := pot.global_position.distance_to(point)
		if distance <= pot.grab_radius() and distance < best_distance:
			best = pot
			best_distance = distance
	return best


# ---------------------------------------------------------------- 布局与 HUD

func _layout() -> void:
	var size := get_viewport_rect().size
	# 所有区域（顶部 HUD / 办公室 / 老板 / 操作区 / 底部信息）都来自同一份空间预算
	_layout_data = LayoutData.compute(size)
	_field = _layout_data["field"]
	_pot_scale = float(_layout_data["pot_scale"])
	_boss.configure_with_floor(
		float(_layout_data["boss_radius"]) / BlameBoss.BASE_RADIUS,
		float(_layout_data["hit_radius"]),
		_layout_data["boss_center"],
		float(_layout_data["floor_y"]))
	_background.configure(size, _layout_data)
	_fx.configure(float(_layout_data["ui_scale"]))
	_hud.configure(size, _layout_data)


func _on_viewport_resized() -> void:
	_layout()


func _refresh_hud() -> void:
	_hud.set_time_left(_time_left)
	_hud.set_score(int(round(_raw_score)))
	_hud.set_combo(_combo)
	_hud.set_stats(_hits, _misses)
	_hud.set_boss(_boss.hp, _boss.max_hp, _boss.stage_name(), _boss.stage_color())
	_hud.set_boss_line(_boss.stage_line())


# ---------------------------------------------------------------- 测试 / 调试接口

func state_name() -> String:
	match _state:
		State.IDLE:
			return "idle"
		State.COUNTDOWN:
			return "countdown"
		State.PLAYING:
			return "playing"
		State.ENDING:
			return "ending"
		_:
			return "result"


func is_playing() -> bool:
	return _state == State.PLAYING


func is_finished() -> bool:
	return _state == State.RESULT


func time_left() -> float:
	return _time_left


func countdown_left() -> float:
	return maxf(_countdown, 0.0)


func elapsed() -> float:
	return _elapsed


func combo() -> int:
	return _combo


func best_combo() -> int:
	return _best_combo


func hits() -> int:
	return _hits


func misses() -> int:
	return _misses


func empty_clicks() -> int:
	return _empty_clicks


func damage_dealt() -> int:
	return _damage_dealt


func score_points() -> int:
	return int(round(_raw_score))


func frenzy_hits() -> int:
	return _frenzy_hits


func phase_index() -> int:
	return _phase


func phase_name() -> String:
	return str(PotData.phase(_phase)["name"])


func field_rect() -> Rect2:
	return _field


## 当前这一屏的构图预算（测试与截图自检会读它验证空间关系）
func layout_data() -> Dictionary:
	return _layout_data


func boss() -> BlameBoss:
	return _boss


func hud() -> BlameHud:
	return _hud


func fx_layer() -> FxLayer:
	return _fx


func background() -> OfficeBackground:
	return _background


func shake_amount() -> float:
	return _shake


func announced_shouts() -> int:
	return _announced_combo.size()


func held_pot() -> BlamePot:
	return _held


func pot_pool_size() -> int:
	return _pots.size()


func active_pot_count() -> int:
	return _actionable_count()


func active_pots() -> Array[BlamePot]:
	var list: Array[BlamePot] = []
	for pot in _pots:
		if pot.is_active():
			list.append(pot)
	return list


## 测试用：固定随机种子
func set_seed(value: int) -> void:
	_seed = value


## 测试用：立刻生成一口指定品种的锅（返回它的落点，方便直接点上去）
func force_spawn(pot_id: String) -> BlamePot:
	return _spawn_pot(pot_id)


## 测试用：把一口锅直接放到场地上
func place_pot(pot_id: String, at: Vector2) -> BlamePot:
	var pot := _spawn_pot(pot_id)
	if pot == null:
		# 池子满的时候（比如连续快速测试），把已经播完结算动画的那口先回收，保证测试能拿到锅
		_recycle_oldest_result()
		pot = _spawn_pot(pot_id)
	if pot == null:
		return null
	pot.global_position = at
	pot.in_field = true
	return pot


## 把「结算动画播得最久」的那口锅强行回收（只给测试 / 调试用）
func _recycle_oldest_result() -> void:
	var oldest: BlamePot = null
	var oldest_time := -1.0
	for pot in _pots:
		if pot.state == BlamePot.State.RESULT and pot.result_age() > oldest_time:
			oldest = pot
			oldest_time = pot.result_age()
	if oldest != null:
		oldest.hibernate()


## 测试 / 调试用：清空场地（keep 传一口锅就把它留下），用来做确定性验证
func clear_pots(keep: BlamePot = null) -> void:
	for pot in _pots:
		if pot == keep or pot.is_held():
			continue
		pot.hibernate()
