extends Node
## 平衡参考工具（不是测试，跑出来只做参考）：
## 用三种「模拟玩家」各打几局，看看 45 秒的节奏是否合理 —— 熟练玩家应该能把老板打崩，
## 手忙脚乱的玩家应该打不崩但也不至于 0 分，否则说明数值需要调。
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tools/balance_report.tscn

const ROUNDS_PER_PROFILE := 3
const STEP := 1.0 / 60.0

## 三种玩家：每处理一口锅要花多久（秒，含找锅 + 拖动 + 松手）
const PROFILES := [
	{"name": "熟练玩家", "handle_time": 0.55},
	{"name": "普通玩家", "handle_time": 0.95},
	{"name": "手忙脚乱", "handle_time": 1.70},
	{"name": "专挑硬锅", "handle_time": 0.75, "prefer_hard": true},
]

## 拖动一口锅到老板身上要花的时间（人做不到瞬移）
const AIM_TIME := 0.35

var _holder: Node2D
var _game: BlameGame


func _ready() -> void:
	ProgressManager.reload("res://tests/.tmp/balance_save.json")
	ProgressManager.reset_progress()
	_holder = Node2D.new()
	add_child(_holder)
	print("----- 《疯狂甩锅》平衡参考（每档 %d 局，自动打满）-----" % ROUNDS_PER_PROFILE)
	for profile in PROFILES:
		_run_profile(profile)
	get_tree().quit(0)


func _run_profile(profile: Dictionary) -> void:
	var totals := {"score": 0, "hits": 0, "misses": 0, "combo": 0, "damage": 0, "rating": 0,
		"ko": 0, "grade": {}}
	for round_index in ROUNDS_PER_PROFILE:
		var result := _play_round(profile)
		totals["score"] = int(totals["score"]) + int(result["score_points"])
		totals["hits"] = int(totals["hits"]) + int(result["hits"])
		totals["misses"] = int(totals["misses"]) + int(result["misses"])
		totals["combo"] = int(totals["combo"]) + int(result["best_combo"])
		totals["damage"] = int(totals["damage"]) + int(result["damage_dealt"])
		totals["rating"] = int(totals["rating"]) + int(result["rating_score"])
		if str(result["end_reason"]) == "ko":
			totals["ko"] = int(totals["ko"]) + 1
		var grades: Dictionary = totals["grade"]
		var grade := str(result["rating_grade"])
		grades[grade] = int(grades.get(grade, 0)) + 1
	print("\n【%s】" % str(profile["name"]))
	print("  平均总分 %d　评级 %d（%s）　命中 %.1f / 失误 %.1f　最高连击 %.1f" % [
		int(totals["score"]) / ROUNDS_PER_PROFILE,
		int(totals["rating"]) / ROUNDS_PER_PROFILE,
		str(totals["grade"]),
		float(totals["hits"]) / ROUNDS_PER_PROFILE,
		float(totals["misses"]) / ROUNDS_PER_PROFILE,
		float(totals["combo"]) / ROUNDS_PER_PROFILE])
	print("  平均打到老板 %d / %d 点伤害　打崩老板 %d / %d 局" % [
		int(totals["damage"]) / ROUNDS_PER_PROFILE, GameConfig.BOSS_MAX_HP,
		int(totals["ko"]), ROUNDS_PER_PROFILE])


func _play_round(profile: Dictionary) -> Dictionary:
	if _game != null and is_instance_valid(_game):
		_game.queue_free()
	_game = (load(GameConfig.GAME_SCENE) as PackedScene).instantiate() as BlameGame
	_holder.add_child(_game)
	_game.set_process(false)
	# 跳过准备阶段
	_tick_for(GameConfig.COUNTDOWN_SECONDS + 0.05)
	var total := GameConfig.PLAY_SECONDS + GameConfig.KO_RESULT_DELAY + 1.5
	var elapsed := 0.0
	var target: BlamePot = null
	var cooldown := 0.0
	var aim := 0.0
	while elapsed < total and not _game.is_finished():
		if target != null and _game.held_pot() == target and _game.is_playing():
			aim += STEP
			_game.pointer_move(_game.boss().hit_center(), 0)
			if aim >= AIM_TIME:
				_game.pointer_release(_game.boss().hit_center(), 0)
				target = null
				cooldown = float(profile["handle_time"])
		elif target != null:
			# 这一口已经解决（命中 / 失误 / 没抓住）：一定要把手松开，
			# 否则「同一时间只有一只手」会让后面的锅全都抓不到
			_game.pointer_release(_game.boss().hit_center(), 0)
			target = null
			cooldown = float(profile["handle_time"])
		elif cooldown > 0.0:
			# 手上忙着（或者刚甩完在喘口气）：这段时间不抓新的锅
			cooldown = maxf(cooldown - STEP, 0.0)
		else:
			target = _pick_target(profile)
			if target != null:
				_game.pointer_press(target.global_position, 0)
				aim = 0.0
		_tick_once()
		elapsed += STEP
	var result := _game.result()
	if result.is_empty():
		# 没打完（理论上不会发生）：退化成当前状态
		result = {"score_points": _game.score_points(), "hits": _game.hits(),
			"misses": _game.misses(), "best_combo": _game.best_combo(),
			"rating_score": 0, "rating_grade": "D", "damage_dealt": _game.damage_dealt(),
			"end_reason": "time", "accuracy": 0.0}
	return result


func _tick_once() -> void:
	_game.tick(STEP)


## 一般玩家优先处理「快凉了」的锅；「专挑硬锅」的玩家优先挑伤害高的锅
func _pick_target(profile: Dictionary) -> BlamePot:
	if bool(profile.get("prefer_hard", false)):
		var hardest: BlamePot = null
		var best_score := -1
		for pot in _game.active_pots():
			if not pot.can_grab():
				continue
			var weight := pot.type.damage_charged if pot.type.needs_charge else pot.type.damage
			if weight > best_score:
				hardest = pot
				best_score = weight
		return hardest
	var best: BlamePot = null
	var best_life := INF
	for pot in _game.active_pots():
		if pot.can_grab() and pot.life < best_life:
			best = pot
			best_life = pot.life
	return best


func _tick_for(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		_tick_once()
		elapsed += STEP
