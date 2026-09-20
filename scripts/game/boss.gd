class_name BlameBoss
extends Node2D
## Q 版老板：整个游戏的情绪主角。
##
## 七个阶段（血量越高越得意），每个阶段都是**一整套**变化，不是换一张脸：
##   0 得意   翘着、眯眼笑、领带笔直、桌上咖啡冒着热气
##   1 疑惑   眉毛一高一低、歪头，眼镜开始往下滑
##   2 不爽   皱眉、抱手、抖腿，桌上的文件开始晃
##   3 愤怒   瞪眼 + 青筋 + 耳朵冒烟，一拳砸在桌上
##   4 暴怒   站起来挥拳头、领带歪掉、头发炸开、咖啡乱晃
##   5 疲惫   扶额、满头汗、眼睛转圈、身体往下塌
##   6 崩溃   直接趴桌上，眼镜歪掉、头发乱成鸡窝、桌上东西翻倒、头顶转星星
##
## 每次挨锅还会叠加：后仰震动、白光、被锅扣头（重锅）、桌面物品晃动、挨打表情（0.3 秒）。

const STAGES := [
	{"id": "smug", "name": "得意", "line": "嘿嘿，这锅你背。"},
	{"id": "puzzled", "name": "疑惑", "line": "嗯？你还真敢甩回来？"},
	{"id": "annoyed", "name": "不爽", "line": "差不多得了啊。"},
	{"id": "angry", "name": "愤怒", "line": "反了你了！"},
	{"id": "furious", "name": "暴怒", "line": "今天非开掉你不可！"},
	{"id": "weary", "name": "疲惫", "line": "别……别砸了……"},
	{"id": "ko", "name": "崩溃", "line": "……我错了。"},
]

## 各阶段的血量比例下限（剩余血量比例 <= 这个值就进入该阶段）
const STAGE_RATIOS := [1.0, 0.82, 0.64, 0.46, 0.28, 0.10, 0.0]

signal stage_changed(index: int)

## 身体基准尺寸（会乘上画面缩放）
const BASE_RADIUS := 92.0

var hp: int = GameConfig.BOSS_MAX_HP
var max_hp: int = GameConfig.BOSS_MAX_HP
var scale_factor: float = 1.0

var shake: float = 0.0
var tilt: float = 0.0
var wobble: float = 0.0

var _stage: int = 0
var _time: float = 0.0
var _hit_flash: float = 0.0
var _hit_face: float = 0.0
var _stage_flash: float = 0.0
var _stuck_time: float = 0.0
var _stuck_pot: PotType = null
var _speech: String = ""
var _speech_time: float = 0.0
var _rng := RandomNumberGenerator.new()
var _hit_radius: float = 160.0
## 地板线（全局坐标）。用来给办公桌 / 椅子画一层接触阴影，
## 让「坐在办公桌后面」这件事在地面上有交代，而不是人物贴在墙上。
var _floor_y: float = 0.0
## 当前这一帧「整体变换」（抖动 / 倾斜），局部绘制改过变换之后要用 _restore_transform() 还原
var _t_offset := Vector2.ZERO
var _t_lean := 0.0


func _ready() -> void:
	_rng.randomize()


## 由游戏主控在布局变化时调用
func configure(scale_value: float, hit_radius: float, hit_center: Vector2) -> void:
	scale_factor = scale_value
	_hit_radius = hit_radius
	position = hit_center
	queue_redraw()


## 布局变化时由游戏主控调用（比 configure 多一个地板线，用来画接触阴影）
func configure_with_floor(
	scale_value: float, hit_radius: float, hit_center: Vector2, floor_y: float
) -> void:
	_floor_y = floor_y
	configure(scale_value, hit_radius, hit_center)


## 老板受击判定圈（拖动到圈里就算甩中）
func hit_radius() -> float:
	return _hit_radius


## 判定圆心：脑袋 + 上半身，稍微偏上一点
func hit_center() -> Vector2:
	return global_position + Vector2(0.0, -BASE_RADIUS * 0.35 * scale_factor)


func body_radius() -> float:
	return BASE_RADIUS * scale_factor


# ---------------------------------------------------------------- 状态

func stage_index() -> int:
	return _stage


func stage_name() -> String:
	return str(STAGES[_stage]["name"])


## 阶段颜色：从「得意」的绿 → 「愤怒」的黄 → 「崩溃」的灰，用来给 HUD 上的阶段文字上色
func stage_color() -> Color:
	if is_ko():
		return Color(0.62, 0.66, 0.72)
	var t := clampf(float(_stage) / float(STAGES.size() - 2), 0.0, 1.0)
	return Palette.OK.lerp(Palette.DANGER, t)


func stage_id() -> String:
	return str(STAGES[_stage]["id"])


func stage_line() -> String:
	return _speech if not _speech.is_empty() else str(STAGES[_stage]["line"])


func stage_count() -> int:
	return STAGES.size()


## 被锅扣在头上的那口锅（没有就是空字符串）
func stuck_pot_id() -> String:
	if _stuck_pot == null or _stuck_time <= 0.0:
		return ""
	return _stuck_pot.id


func is_ko() -> bool:
	return _stage >= STAGES.size() - 1


func hp_ratio() -> float:
	if max_hp <= 0:
		return 0.0
	return clampf(float(hp) / float(max_hp), 0.0, 1.0)


## 血量比例 → 阶段序号
static func stage_for_ratio(ratio: float) -> int:
	var clamped := clampf(ratio, 0.0, 1.0)
	var stage := STAGES.size() - 1
	for i in range(STAGES.size() - 1):
		if clamped > float(STAGE_RATIOS[i + 1]):
			stage = i
			break
	return stage


## 设置血量（返回是否换了阶段，game 用它决定要不要播「老板变脸」反馈）
func set_hp(value: int) -> bool:
	hp = clampi(value, 0, max_hp)
	var next := stage_for_ratio(hp_ratio())
	if next == _stage:
		queue_redraw()
		return false
	var was_ko := is_ko()
	_stage = next
	_stage_flash = 0.55
	shake = maxf(shake, 0.7)
	tilt = 0.0
	set_speech(stage_line(), 2.0)
	if not was_ko and is_ko():
		ko()
	queue_redraw()
	stage_changed.emit(_stage)
	return true


## 挨了一口锅
func react_hit(pot: PotType, strength: float = 1.0) -> void:
	_hit_flash = 0.26
	_hit_face = 0.34
	shake = clampf(shake + 0.45 * strength, 0.0, 1.4)
	tilt = -0.10 * strength if not is_ko() else 0.0
	wobble = clampf(wobble + 0.5 * strength, 0.0, 1.5)
	if pot != null and strength >= 0.8:
		# 重锅会「扣在头上」一小会儿
		_stuck_pot = pot
		_stuck_time = 0.75 if pot.id == "iron" else 0.55
	queue_redraw()


## 彻底崩溃：趴桌上
func ko() -> void:
	_stage = STAGES.size() - 1
	_stage_flash = 0.8
	shake = 1.1
	tilt = 0.0
	set_speech(str(STAGES[_stage]["line"]), 3.0)
	queue_redraw()
	stage_changed.emit(_stage)


func set_speech(text: String, seconds: float = 2.0) -> void:
	_speech = text
	_speech_time = seconds
	queue_redraw()


func reset() -> void:
	hp = max_hp
	_stage = 0
	shake = 0.0
	tilt = 0.0
	wobble = 0.0
	_hit_flash = 0.0
	_hit_face = 0.0
	_stage_flash = 0.0
	_stuck_time = 0.0
	_stuck_pot = null
	_speech = ""
	_speech_time = 0.0
	_time = 0.0
	queue_redraw()


## 菜单上的“吉祥物”模式：直接摆到某个阶段，不播受击 / 换阶段反馈
func set_stage_silent(index: int) -> void:
	_stage = clampi(index, 0, STAGES.size() - 1)
	var lower := float(STAGE_RATIOS[_stage + 1]) if _stage + 1 < STAGE_RATIOS.size() else 0.0
	var upper := float(STAGE_RATIOS[_stage])
	var ratio := 0.0 if _stage >= STAGES.size() - 1 else (lower + upper) * 0.5
	hp = int(round(float(max_hp) * ratio))
	_speech = ""
	_speech_time = 0.0
	shake = 0.0
	tilt = 0.0
	_stage_flash = 0.0
	_stuck_time = 0.0
	_stuck_pot = null
	queue_redraw()


# ---------------------------------------------------------------- 每帧推进

func tick(delta: float) -> void:
	_time += delta
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	_hit_face = maxf(_hit_face - delta, 0.0)
	_stage_flash = maxf(_stage_flash - delta, 0.0)
	_stuck_time = maxf(_stuck_time - delta, 0.0)
	_speech_time = maxf(_speech_time - delta, 0.0)
	if _speech_time <= 0.0:
		_speech = ""
	var recover := 3.4 if not is_ko() else 6.0
	shake = maxf(shake - delta * 1.9, 0.0)
	tilt = move_toward(tilt, 0.0, delta * recover)
	wobble = maxf(wobble - delta * 1.4, 0.0)
	if _stuck_time <= 0.0:
		_stuck_pot = null
	queue_redraw()


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	var r := body_radius()
	var idle_speed := 1.6 + 0.35 * float(_stage)
	var bob := sin(_time * idle_speed) * (2.5 + 1.2 * float(_stage)) * scale_factor
	var jitter := 0.0
	if _stage >= 3:
		jitter = _rng.randf_range(-1.5, 1.5) * (_stage - 2)
	var offset := Vector2(sin(_time * 46.0) * shake * 13.0 * scale_factor, bob + jitter)
	var lean := tilt + _stage_lean()

	_t_offset = offset
	_t_lean = lean
	_restore_transform()
	_draw_floor_shadow(r)
	if is_ko():
		_draw_ko_pose(r)
	else:
		_draw_chair(r)
		_draw_body(r)
		_draw_arms_behind(r)
		_draw_head(r)
		_draw_desk(r)
		_draw_arms_front(r)
		_draw_desk_items(r)
	_draw_effects(r)
	_draw_hit_overlay(r)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 桌子压在地板上的一层软阴影（空间关系的锚点）
func _draw_floor_shadow(r: float) -> void:
	if _floor_y <= 0.0:
		return
	var local_y := _floor_y - global_position.y
	for i in 4:
		var alpha := 0.15 * (1.0 - float(i) * 0.22)
		draw_set_transform(Vector2(0.0, local_y + r * 0.03 * float(i)), 0.0, Vector2.ONE)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-r * (1.1 + 0.22 * float(i)), 0.0),
			Vector2(r * (1.1 + 0.22 * float(i)), 0.0),
			Vector2(r * (0.9 + 0.20 * float(i)), r * 0.12),
			Vector2(-r * (0.9 + 0.20 * float(i)), r * 0.12),
		]), Color(0.0, 0.0, 0.0, alpha))
	_restore_transform()


## 还原到本体变换（局部旋转绘制之后必须调用）
func _restore_transform() -> void:
	draw_set_transform(_t_offset, _t_lean, Vector2.ONE)


func _stage_lean() -> float:
	match _stage:
		0:
			return sin(_time * 1.5) * 0.03
		1:
			return -0.07
		2:
			return 0.02 + sin(_time * 6.0) * 0.012
		3:
			return -0.05 + sin(_time * 9.0) * 0.02
		4:
			return -0.10 + sin(_time * 12.0) * 0.03
		5:
			return 0.14
	return 0.0


func _skin_color() -> Color:
	match _stage:
		0, 1:
			return Palette.BOSS_SKIN
		2, 3:
			return Palette.BOSS_SKIN.lerp(Palette.BOSS_SKIN_HOT, 0.35)
		4:
			return Palette.BOSS_SKIN_HOT
		5:
			return Palette.BOSS_SKIN.lerp(Color(0.82, 0.86, 0.90), 0.45)
		_:
			return Palette.BOSS_SKIN.lerp(Color(0.78, 0.80, 0.84), 0.7)


func _draw_chair(r: float) -> void:
	# 办公椅：有点卡通，靠背在身体后面
	draw_rect(Rect2(Vector2(-r * 1.12, -r * 0.55), Vector2(r * 2.24, r * 0.95)),
		Color(0.16, 0.18, 0.23))
	draw_rect(Rect2(Vector2(-r * 1.0, -r * 0.5), Vector2(r * 2.0, r * 0.86)),
		Color(0.24, 0.26, 0.32))


func _draw_body(r: float) -> void:
	var suit := Palette.BOSS_SUIT
	if _stage >= 4:
		suit = Palette.BOSS_SUIT.lerp(Palette.BOSS_TIE, 0.10)
	# 躯干
	draw_colored_polygon(PackedVector2Array([
		Vector2(-r * 1.18, r * 1.10),
		Vector2(-r * 0.74, r * 0.02),
		Vector2(r * 0.74, r * 0.02),
		Vector2(r * 1.18, r * 1.10),
	]), suit)
	# 衬衫
	draw_colored_polygon(PackedVector2Array([
		Vector2(-r * 0.30, r * 0.05),
		Vector2(r * 0.30, r * 0.05),
		Vector2(r * 0.22, r * 1.10),
		Vector2(-r * 0.22, r * 1.10),
	]), Palette.BOSS_SHIRT)
	# 领带（越往后越歪）
	var tie_angle := 0.10 * float(mini(_stage, 5))
	if _stage >= 6:
		tie_angle = 0.85
	draw_set_transform(Vector2(0.0, r * 0.12), tie_angle, Vector2.ONE)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-r * 0.12, 0.0), Vector2(r * 0.12, 0.0), Vector2(0.0, r * 0.82),
	]), Palette.BOSS_TIE)
	_restore_transform()
	# 西装翻领
	for side in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([
			Vector2(side * r * 0.30, r * 0.05),
			Vector2(side * r * 0.78, r * 0.06),
			Vector2(side * r * 0.62, r * 0.75),
		]), Palette.BOSS_SUIT_DARK)


## 手臂（画在身体后面 / 头部下面的部分）
func _draw_arms_behind(r: float) -> void:
	var skin := _skin_color()
	match _stage:
		0:
			# 抱手，得意
			draw_line(Vector2(-r * 0.86, r * 0.52), Vector2(r * 0.86, r * 0.40), suit_sleeve(), r * 0.30, true)
			draw_line(Vector2(-r * 0.86, r * 0.40), Vector2(r * 0.86, r * 0.52), suit_sleeve(), r * 0.30, true)
		1:
			# 一只手托着下巴
			draw_line(Vector2(r * 0.80, r * 0.75), Vector2(r * 0.34, -r * 0.10), suit_sleeve(), r * 0.30, true)
			draw_circle(Vector2(r * 0.30, -r * 0.16), r * 0.20, skin)
		2:
			# 抱手 + 抖腿
			draw_line(Vector2(-r * 0.90, r * 0.55), Vector2(r * 0.90, r * 0.45), suit_sleeve(), r * 0.30, true)
		3, 4:
			# 举拳头
			for side in [-1.0, 1.0]:
				var raise := r * (0.95 if _stage == 4 else 0.55)
				draw_line(Vector2(side * r * 0.88, r * 0.55),
					Vector2(side * r * 1.30, r * 0.55 - raise), suit_sleeve(), r * 0.30, true)
				draw_circle(Vector2(side * r * 1.34, r * 0.50 - raise), r * 0.24, skin)
		5:
			# 抱头
			for side in [-1.0, 1.0]:
				draw_line(Vector2(side * r * 0.90, r * 0.60),
					Vector2(side * r * 1.05, -r * 0.55), suit_sleeve(), r * 0.30, true)
				draw_circle(Vector2(side * r * 1.08, -r * 0.62), r * 0.22, skin)
		_:
			pass


## 手臂（搭在桌子上的部分，画在桌面上方）
func _draw_arms_front(r: float) -> void:
	var skin := _skin_color()
	match _stage:
		0:
			draw_circle(Vector2(-r * 0.62, r * 0.62), r * 0.20, skin)
			draw_circle(Vector2(r * 0.62, r * 0.58), r * 0.20, skin)
		2, 3:
			# 手撑在桌上
			for side in [-1.0, 1.0]:
				draw_circle(Vector2(side * r * 0.92, r * 0.92), r * 0.22, skin)
		4:
			# 手举起来，桌上只剩拳头影子（用桌面小坑表现）
			pass
		5, 6:
			for side in [-1.0, 1.0]:
				draw_circle(Vector2(side * r * 0.98, r * 0.86), r * 0.20, skin)
		_:
			pass


func suit_sleeve() -> Color:
	return Palette.BOSS_SUIT_DARK


func _draw_head(r: float) -> void:
	var skin := _skin_color()
	var center := Vector2(0.0, -r * 0.66)
	# 耳朵
	for side in [-1.0, 1.0]:
		draw_circle(center + Vector2(side * r * 0.72, r * 0.06), r * 0.16, skin.darkened(0.06))
	# 脸
	draw_circle(center, r * 0.74, skin)
	draw_arc(center, r * 0.74, 0.0, TAU, 32, skin.darkened(0.28), 2.0)
	_draw_hair(r, center)
	_draw_glasses(r, center)
	_draw_face(r, center)
	if _stage >= 4:
		# 爆炸头的碎发
		for i in 6:
			var angle := PI * (1.0 + float(i) / 5.0)
			var base := center + Vector2(cos(angle), sin(angle)) * r * 0.70
			draw_line(base, base + Vector2(cos(angle), sin(angle)) * r * 0.26,
				Palette.BOSS_HAIR, 3.0, true)


func _draw_hair(r: float, center: Vector2) -> void:
	var mess := clampf(float(_stage) / 5.0, 0.0, 1.0)
	draw_arc(center + Vector2(0.0, -r * 0.06), r * 0.70, PI * 0.96, PI * 2.04, 24,
		Palette.BOSS_HAIR, r * 0.34 - r * 0.06 * mess)
	if mess > 0.35:
		# 越到后面越乱：几撮翘起来的头发
		for i in 3:
			var base := center + Vector2(-r * 0.45 + float(i) * r * 0.45, -r * 0.60)
			draw_line(base, base + Vector2(-r * 0.22 + float(i) * r * 0.20, -r * 0.42 * mess),
				Palette.BOSS_HAIR, 4.0, true)
	if _stage >= 6:
		for i in 4:
			var angle := PI * 1.15 + float(i) * 0.35
			draw_line(center + Vector2(cos(angle), sin(angle)) * r * 0.55,
				center + Vector2(cos(angle), sin(angle)) * r * 1.25,
				Palette.BOSS_HAIR, 3.0, true)


func _draw_glasses(r: float, center: Vector2) -> void:
	var frame := Color(0.20, 0.22, 0.26)
	if _stage >= 4:
		frame = Color(0.10, 0.11, 0.13)
	var tilt_angle := 0.0
	var drop := 0.0
	if _stage == 1:
		drop = r * 0.05
	elif _stage == 2:
		drop = r * 0.08
	elif _stage == 3:
		tilt_angle = 0.12
	elif _stage == 4:
		tilt_angle = 0.28
		drop = r * 0.10
	elif _stage == 5:
		tilt_angle = 0.45
		drop = r * 0.16
	draw_set_transform(center + Vector2(0.0, drop), tilt_angle, Vector2.ONE)
	# 眼镜腿
	draw_line(Vector2(-r * 0.74, -r * 0.02), Vector2(-r * 0.36, -r * 0.06), frame, 2.5, true)
	draw_line(Vector2(r * 0.74, -r * 0.02), Vector2(r * 0.36, -r * 0.06), frame, 2.5, true)
	for side in [-1.0, 1.0]:
		var lens := Vector2(side * r * 0.32, -r * 0.06)
		draw_circle(lens, r * 0.20, Color(1.0, 1.0, 1.0, 0.16))
		draw_arc(lens, r * 0.20, 0.0, TAU, 20, frame, 2.6)
	draw_line(Vector2(-r * 0.12, -r * 0.06), Vector2(r * 0.12, -r * 0.06), frame, 2.4, true)
	# 疲惫时眼镜滑到鼻尖，还要反光
	if _stage >= 5:
		draw_line(Vector2(-r * 0.50, -r * 0.18), Vector2(-r * 0.20, r * 0.04),
			Color(1.0, 1.0, 1.0, 0.45), 3.0, true)
	_restore_transform()


func _draw_face(r: float, center: Vector2) -> void:
	var ink := Palette.BOSS_INK
	var eye_y := center.y - r * 0.02
	var hit := _hit_face > 0.0
	if hit:
		# 被砸中的表情：X 眼 + 张嘴（不管哪个阶段都先懵一下）
		for side in [-1.0, 1.0]:
			var e := Vector2(side * r * 0.32, eye_y)
			draw_line(e + Vector2(-r * 0.09, -r * 0.09), e + Vector2(r * 0.09, r * 0.09),
				ink, 3.2, true)
			draw_line(e + Vector2(r * 0.09, -r * 0.09), e + Vector2(-r * 0.09, r * 0.09),
				ink, 3.2, true)
		draw_circle(Vector2(0.0, center.y + r * 0.32), r * 0.16, Color(0.42, 0.16, 0.16))
		return

	match _stage:
		0:
			# 眯眼笑 + 嘴角上扬
			for side in [-1.0, 1.0]:
				draw_arc(Vector2(side * r * 0.32, eye_y), r * 0.14, PI * 1.05, PI * 1.95, 14,
					ink, 3.0)
			draw_arc(Vector2(0.0, center.y + r * 0.18), r * 0.24, 0.30, PI - 0.30, 16, ink, 3.2)
		1:
			# 一挑眉
			draw_line(Vector2(-r * 0.50, eye_y - r * 0.26), Vector2(-r * 0.16, eye_y - r * 0.18),
				ink, 3.0, true)
			draw_line(Vector2(r * 0.18, eye_y - r * 0.34), Vector2(r * 0.50, eye_y - r * 0.22),
				ink, 3.0, true)
			for side in [-1.0, 1.0]:
				draw_circle(Vector2(side * r * 0.32, eye_y), r * 0.075, ink)
			draw_line(Vector2(-r * 0.16, center.y + r * 0.30), Vector2(r * 0.16, center.y + r * 0.30),
				ink, 3.0, true)
		2:
			# 皱眉 + 撇嘴
			for side in [-1.0, 1.0]:
				draw_line(Vector2(side * r * 0.50, eye_y - r * 0.22),
					Vector2(side * r * 0.18, eye_y - r * 0.14), ink, 3.0, true)
				draw_circle(Vector2(side * r * 0.32, eye_y), r * 0.075, ink)
			draw_arc(Vector2(0.0, center.y + r * 0.38), r * 0.20, PI * 1.15, PI * 1.85, 14, ink, 3.0)
		3, 4:
			# 瞪眼 + 倒八字眉 + 呲牙
			for side in [-1.0, 1.0]:
				draw_line(Vector2(side * r * 0.54, eye_y - r * 0.30),
					Vector2(side * r * 0.14, eye_y - r * 0.12), ink, 3.4, true)
				draw_circle(Vector2(side * r * 0.32, eye_y + r * 0.02), r * 0.11, Color.WHITE)
				draw_circle(Vector2(side * r * 0.34, eye_y + r * 0.02), r * 0.055, ink)
			var mouth_y := center.y + r * 0.30
			draw_rect(Rect2(Vector2(-r * 0.26, mouth_y), Vector2(r * 0.52, r * 0.22)),
				Color(0.42, 0.16, 0.16))
			for i in 3:
				draw_rect(Rect2(Vector2(-r * 0.22 + float(i) * r * 0.16, mouth_y),
					Vector2(r * 0.08, r * 0.10)), Color(0.98, 0.96, 0.94))
		5:
			# 眼睛转圈 + 大叹气
			for side in [-1.0, 1.0]:
				var e := Vector2(side * r * 0.32, eye_y)
				draw_circle(e, r * 0.14, Color.WHITE)
				draw_arc(e, r * 0.07, _time * 6.0, _time * 6.0 + PI * 1.4, 12, ink, 2.6)
			draw_circle(Vector2(0.0, center.y + r * 0.32), r * 0.15, Color(0.30, 0.12, 0.12))
		_:
			# KO：@_@
			for side in [-1.0, 1.0]:
				var e := Vector2(side * r * 0.32, eye_y)
				draw_arc(e, r * 0.12, 0.0, TAU, 16, ink, 2.4)
				draw_circle(e + Vector2(r * 0.10, -r * 0.04), r * 0.035, ink)
			draw_arc(Vector2(0.0, center.y + r * 0.34), r * 0.14, 0.1, PI - 0.1, 12, ink, 2.8)


func _draw_desk(r: float) -> void:
	var wobble_offset := Vector2(sin(_time * 40.0) * wobble * 3.0, 0.0)
	# 桌面
	draw_rect(Rect2(Vector2(-r * 2.05, r * 0.86) + wobble_offset,
		Vector2(r * 4.10, r * 0.26)), Palette.DESK_TOP)
	draw_rect(Rect2(Vector2(-r * 2.05, r * 1.12) + wobble_offset,
		Vector2(r * 4.10, r * 0.72)), Palette.DESK)
	draw_rect(Rect2(Vector2(-r * 2.05, r * 1.12) + wobble_offset,
		Vector2(r * 4.10, r * 0.06)), Palette.DESK_DARK)


func _draw_desk_items(r: float) -> void:
	var wobble_offset := Vector2(sin(_time * 40.0) * wobble * 5.0,
		cos(_time * 33.0) * wobble * 2.0)
	# 咖啡杯
	var cup := Vector2(-r * 1.45, r * 0.72) + wobble_offset
	draw_rect(Rect2(cup, Vector2(r * 0.42, r * 0.42)), Color(0.93, 0.94, 0.97))
	draw_rect(Rect2(cup + Vector2(-r * 0.07, r * 0.06), Vector2(r * 0.07, r * 0.24)),
		Color(0.93, 0.94, 0.97))
	draw_rect(Rect2(cup + Vector2(r * 0.06, r * 0.04), Vector2(r * 0.30, r * 0.06)),
		Color(0.36, 0.22, 0.14))
	if _stage <= 1:
		# 还热着
		for i in 3:
			var t := fmod(_time * 0.7 + float(i) * 0.33, 1.0)
			draw_circle(cup + Vector2(0.0, -r * 0.20 - t * r * 0.40), r * 0.06 * (1.0 - t),
				Color(1.0, 1.0, 1.0, 0.22 * (1.0 - t)))
	else:
		# 越到后面泼得越开
		var spill := clampf(float(_stage - 1) / 5.0, 0.0, 1.0)
		draw_colored_polygon(PackedVector2Array([
			cup + Vector2(r * 0.42, r * 0.30),
			cup + Vector2(r * (0.42 + 1.2 * spill), r * 0.44),
			cup + Vector2(r * 0.46, r * 0.46),
		]), Color(0.38, 0.24, 0.16, 0.85))
	# 文件
	for i in 3:
		var offset := Vector2(r * (0.85 + float(i) * 0.16), r * (0.62 - float(i) * 0.05)) \
			+ wobble_offset * (0.6 + 0.2 * float(i))
		var angle := 0.10 * float(i) + (_time * 0.4 if _stage >= 3 else 0.0)
		draw_set_transform(offset, angle, Vector2.ONE)
		draw_rect(Rect2(Vector2(-r * 0.42, -r * 0.28), Vector2(r * 0.84, r * 0.56)),
			Color(0.94, 0.94, 0.90))
		for line in 3:
			draw_line(Vector2(-r * 0.30, -r * 0.14 + float(line) * r * 0.14),
				Vector2(r * 0.30, -r * 0.14 + float(line) * r * 0.14),
				Color(0.55, 0.58, 0.64), 2.0, true)
		_restore_transform()
	# 铭牌
	draw_set_transform(Vector2(-r * 0.10, r * 1.34) + wobble_offset, -0.06, Vector2.ONE)
	draw_rect(Rect2(Vector2(-r * 0.62, -r * 0.14), Vector2(r * 1.24, r * 0.28)),
		Color(0.24, 0.20, 0.16))
	draw_rect(Rect2(Vector2(-r * 0.58, -r * 0.10), Vector2(r * 1.16, r * 0.20)),
		Color(0.86, 0.72, 0.42))
	_restore_transform()
	# 笔记本 / 笔筒
	draw_rect(Rect2(Vector2(r * 1.42, r * 0.62) + wobble_offset, Vector2(r * 0.30, r * 0.62)),
		Color(0.30, 0.34, 0.42))
	for i in 3:
		var pen := Vector2(r * 1.48 + float(i) * r * 0.09, r * 0.42) + wobble_offset
		draw_line(pen, pen + Vector2(0.0, -r * 0.24), Color(0.85 - float(i) * 0.2, 0.4, 0.35),
			3.0, true)


## KO：趴在桌上，眼镜歪、头发炸、东西翻倒、头顶转星星
func _draw_ko_pose(r: float) -> void:
	# 瘫掉的肩膀
	draw_colored_polygon(PackedVector2Array([
		Vector2(-r * 1.30, r * 1.05), Vector2(-r * 0.80, r * 0.30),
		Vector2(r * 0.80, r * 0.30), Vector2(r * 1.30, r * 1.05),
	]), Palette.BOSS_SUIT)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-r * 0.28, r * 0.34), Vector2(r * 0.28, r * 0.34),
		Vector2(r * 0.20, r * 1.05), Vector2(-r * 0.20, r * 1.05),
	]), Palette.BOSS_SHIRT)
	# 桌面
	draw_rect(Rect2(Vector2(-r * 2.05, r * 0.74), Vector2(r * 4.10, r * 0.26)), Palette.DESK_TOP)
	draw_rect(Rect2(Vector2(-r * 2.05, r * 1.00), Vector2(r * 4.10, r * 0.84)), Palette.DESK)
	draw_rect(Rect2(Vector2(-r * 2.05, r * 1.00), Vector2(r * 4.10, r * 0.06)), Palette.DESK_DARK)
	# 趴在桌上的脑袋（侧脸贴着桌面）
	var head := Vector2(r * 0.10, r * 0.62)
	var skin := _skin_color()
	draw_circle(head, r * 0.72, skin)
	draw_arc(head, r * 0.72, 0.0, TAU, 30, skin.darkened(0.3), 2.0)
	# 乱发
	draw_arc(head + Vector2(0.0, -r * 0.10), r * 0.68, PI * 0.98, PI * 2.02, 20,
		Palette.BOSS_HAIR, r * 0.30)
	for i in 5:
		var angle := PI * 1.05 + float(i) * 0.28
		draw_line(head + Vector2(cos(angle), sin(angle)) * r * 0.5,
			head + Vector2(cos(angle), sin(angle)) * r * 1.15, Palette.BOSS_HAIR, 3.0, true)
	# @_@ 眼睛
	for side in [-1.0, 1.0]:
		var e := head + Vector2(side * r * 0.30, -r * 0.02)
		draw_arc(e, r * 0.13, 0.0, TAU, 14, Palette.BOSS_INK, 2.4)
		draw_circle(e + Vector2(r * 0.10, -r * 0.05), r * 0.04, Palette.BOSS_INK)
	# 歪掉的眼镜（一只镜片压在脸上）
	var lens := head + Vector2(r * 0.34, r * 0.30)
	draw_arc(lens, r * 0.20, 0.0, TAU, 18, Color(0.16, 0.17, 0.20), 2.6)
	draw_line(lens + Vector2(-r * 0.20, 0.0), head + Vector2(r * 0.05, r * 0.16),
		Color(0.16, 0.17, 0.20), 2.4, true)
	draw_line(lens + Vector2(r * 0.20, 0.0), lens + Vector2(r * 0.75, -r * 0.10),
		Color(0.16, 0.17, 0.20), 2.4, true)
	# 摊开的手
	for side in [-1.0, 1.0]:
		var hand := Vector2(side * r * 1.12, r * 0.86)
		draw_line(Vector2(side * r * 0.86, r * 0.74), hand, Palette.BOSS_SUIT_DARK, r * 0.28, true)
		draw_circle(hand, r * 0.22, skin)
	# 翻倒的咖啡 + 散落文件
	draw_circle(Vector2(-r * 1.55, r * 0.90), r * 0.26, Color(0.93, 0.94, 0.97))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-r * 1.30, r * 0.94), Vector2(-r * 0.20, r * 1.06), Vector2(-r * 0.90, r * 1.20),
	]), Color(0.38, 0.24, 0.16, 0.9))
	for i in 3:
		var offset := Vector2(r * (0.90 + float(i) * 0.12), r * (0.86 + float(i) * 0.06))
		draw_set_transform(offset, 0.4 + 0.3 * float(i), Vector2.ONE)
		draw_rect(Rect2(Vector2(-r * 0.40, -r * 0.26), Vector2(r * 0.80, r * 0.52)),
			Color(0.92, 0.92, 0.88))
		_restore_transform()


## 阶段特效：青筋 / 冒烟 / 汗 / 星星
func _draw_effects(r: float) -> void:
	var head_top := Vector2(0.0, -r * 1.45)
	match _stage:
		0:
			# 得意的闪光
			for i in 2:
				var p := Vector2(-r * 1.05 + float(i) * r * 2.1, -r * 1.15)
				var s := r * 0.16 * (0.7 + 0.3 * sin(_time * 3.0 + float(i)))
				draw_line(p - Vector2(s, 0.0), p + Vector2(s, 0.0), Palette.ACCENT, 2.5, true)
				draw_line(p - Vector2(0.0, s), p + Vector2(0.0, s), Palette.ACCENT, 2.5, true)
		2:
			draw_line(head_top + Vector2(r * 0.55, r * 0.10), head_top + Vector2(r * 0.75, r * 0.30),
				Palette.DANGER, 3.0, true)
		3, 4:
			_draw_anger_mark(head_top + Vector2(r * 0.80, r * 0.12), r * 0.22)
			_draw_smoke(Vector2(-r * 1.05, -r * 1.10), r)
			_draw_smoke(Vector2(r * 1.05, -r * 1.10), r)
		5:
			for i in 4:
				var t := fmod(_time * 1.6 + float(i) * 0.25, 1.0)
				var p := head_top + Vector2(-r * 0.9 + float(i) * r * 0.6, t * r * 0.7)
				draw_colored_polygon(PackedVector2Array([
					p, p + Vector2(r * 0.10, r * 0.16), p + Vector2(-r * 0.10, r * 0.16),
				]), Color(0.55, 0.80, 1.0, 0.85 * (1.0 - t)))
		6:
			for i in 3:
				var angle := _time * 2.6 + TAU * float(i) / 3.0
				var p := Vector2(cos(angle) * r * 1.15, -r * 1.35 + sin(angle) * r * 0.30)
				_draw_star(p, r * 0.17, Palette.ACCENT)


func _draw_anger_mark(center: Vector2, size: float) -> void:
	# 生气符号：两条交叉的短杠
	for i in 2:
		var a := center + Vector2(-size * 0.5, -size * 0.5 + float(i) * size * 0.5)
		draw_line(a, a + Vector2(size, size * 0.5), Palette.DANGER, 3.5, true)


func _draw_smoke(origin: Vector2, r: float) -> void:
	for i in 3:
		var t := fmod(_time * 1.1 + float(i) * 0.33, 1.0)
		draw_circle(origin + Vector2(sin(t * 6.0) * r * 0.10, -t * r * 0.55),
			r * (0.10 + 0.10 * t), Color(0.75, 0.78, 0.82, 0.45 * (1.0 - t)))


func _draw_star(center: Vector2, size: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var angle := -PI * 0.5 + TAU * float(i) / 10.0
		var radius := size if i % 2 == 0 else size * 0.45
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)


## 受击白光 + 被锅扣头 + 换阶段的冲击波
func _draw_hit_overlay(r: float) -> void:
	if _hit_flash > 0.0:
		draw_circle(Vector2(0.0, -r * 0.5), r * 1.15,
			Color(1.0, 1.0, 1.0, 0.30 * (_hit_flash / 0.26)))
	if _stuck_time > 0.0 and _stuck_pot != null:
		_draw_stuck_pot(r)
	if _stage_flash > 0.0:
		var t := 1.0 - _stage_flash / 0.8
		draw_arc(Vector2(0.0, -r * 0.4), r * (0.8 + t * 2.4), 0.0, TAU, 40,
			Color(Palette.DANGER, 0.5 * (1.0 - t)), 6.0)


func _draw_stuck_pot(r: float) -> void:
	var pot := _stuck_pot
	var center := Vector2(0.0, -r * 1.30)
	var size := r * 0.52
	draw_circle(center, size, pot.tint)
	draw_circle(center, size * 0.72, pot.tint_dark)
	draw_arc(center, size, 0.0, TAU, 24, pot.tint_dark, 3.0)
	for side in [-1.0, 1.0]:
		draw_arc(center + Vector2(side * size * 1.0, 0.0), size * 0.30,
			PI * 0.5 if side > 0.0 else -PI * 0.5,
			PI * 1.5 if side > 0.0 else PI * 0.5, 10, pot.tint_dark, 3.5)
	draw_circle(center + Vector2(0.0, -size * 0.95), size * 0.18, Palette.ACCENT)
