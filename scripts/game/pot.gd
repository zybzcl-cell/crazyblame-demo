class_name BlamePot
extends Node2D
## 一口锅。
##
## 只负责「自己长什么样 + 自己怎么动」，不做任何判定（判定在 blame_game.gd 里）。
## 状态机：
##   HIDDEN  在池子里歇着（不会新建 / 销毁节点）
##   FLYING  老板甩出来，正在场地里飘（进了场地才能被抓住）
##   HELD    被玩家捏在手里，跟着手指走
##   THROWN  已经甩出去了，正朝老板飞
##   RESULT  命中 / 失手之后的一小段动画，播完自动回收
##
## 五种锅的**外形**也是分开画的：普通锅、铁锅（厚沿 + 铆钉）、平底锅（长柄）、
## 压力锅（阀 + 压力表）、破锅（缺口 + 裂纹），不是换颜色而已。

enum State { HIDDEN, FLYING, HELD, THROWN, RESULT }

## 拖动残影的最大点数
const TRAIL_MAX := 10

var type: PotType
var pot_id: String = ""
var blame: String = ""
var state: State = State.HIDDEN
var velocity: Vector2 = Vector2.ZERO
var scale_factor: float = 1.0
## 在场地上飘的速度（进场地之后会把「飞进来」的速度换成这个）
var drift_speed: float = 150.0
## 从甩出到现在的秒数（超时就当甩歪了）
var throw_time: float = 0.0

## 存活计时：life 到 0 就「锅凉了」（= 一次 Miss）
var life: float = 8.0
var max_life: float = 8.0
## 从出现到现在的总时间（结算「反应速度」奖励用，握着的时候也照常累加）
var age: float = 0.0
## 已经握了多久（超过 hold_window 会手滑）
var held_time: float = 0.0
## 蓄力比例 0~1（只有压力锅会用）
var charge: float = 0.0
## 命中时记录下来的蓄力比例（结算伤害用）
var hit_charge: float = 0.0
## 是否已经进入场地（老板手里往下飞的那一段不能抓）
var in_field: bool = false
## 在场地上飘的时候要不要「飘忽一点」（平底锅、破锅更飘）
var wander: float = 0.25

var _angle: float = 0.0
var _spin: float = 2.0
var _result_time: float = 0.0
var _result_hit: bool = false
var _jitter_timer: float = 1.0
var _trail: Array[Vector2] = []
var _pulse: float = 0.0
var _field: Rect2 = Rect2()
var _rng := RandomNumberGenerator.new()
var _tag_style: StyleBoxFlat
var _tag_width: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_tag_style = StyleBoxFlat.new()
	_tag_style.bg_color = Color(0.07, 0.08, 0.11, 0.82)
	_tag_style.border_width_bottom = 2
	_tag_style.corner_radius_top_left = 8
	_tag_style.corner_radius_top_right = 8
	_tag_style.corner_radius_bottom_left = 8
	_tag_style.corner_radius_bottom_right = 8
	_tag_style.content_margin_left = 8.0
	_tag_style.content_margin_right = 8.0
	_tag_style.content_margin_top = 3.0
	_tag_style.content_margin_bottom = 3.0
	visible = false


# ---------------------------------------------------------------- 生命周期

## 开始这一口锅：从老板那边飞向场地
func launch(
	pot: PotType, blame_text: String, field: Rect2, start_position: Vector2,
	direction: Vector2, speed: float, life_seconds: float, scale_value: float
) -> void:
	type = pot
	pot_id = pot.id
	blame = blame_text
	scale_factor = scale_value
	_field = field
	life = life_seconds
	max_life = life_seconds
	age = 0.0
	held_time = 0.0
	charge = 0.0
	hit_charge = 0.0
	throw_time = 0.0
	in_field = field.has_point(start_position)
	velocity = direction.normalized() * speed
	global_position = start_position
	scale = Vector2.ONE * scale_value
	modulate = Color.WHITE
	_angle = _rng.randf_range(-0.5, 0.5)
	_spin = _rng.randf_range(-3.2, 3.2)
	_jitter_timer = _rng.randf_range(0.5, 1.1)
	_trail.clear()
	_result_time = 0.0
	state = State.FLYING
	visible = true
	queue_redraw()


## 玩家抓住了这口锅
func grab() -> void:
	if state != State.FLYING:
		return
	state = State.HELD
	velocity = Vector2.ZERO
	held_time = 0.0
	_trail.clear()
	queue_redraw()


## 图鉴 / 菜单里的静态预览（不参与玩法，也不会自己走时间）
func setup_preview(pot: PotType, scale_value: float) -> void:
	type = pot
	pot_id = pot.id
	blame = ""
	scale_factor = scale_value
	scale = Vector2.ONE * scale_value
	state = State.FLYING
	in_field = false
	life = 1.0
	max_life = 1.0
	angle_degrees(0.0)
	visible = true
	queue_redraw()


## 预览用：设置静态角度（度）
func angle_degrees(value: float) -> void:
	_angle = deg_to_rad(value)


## 被抓住时跟随手指：跟手程度由锅的类型决定（铁锅明显迟钝）
func follow(point: Vector2, delta: float) -> void:
	if state != State.HELD:
		return
	var weight := 1.0 - exp(-maxf(type.drag_follow, 0.5) * delta)
	global_position = global_position.lerp(point, weight)
	_trail.push_front(global_position)
	while _trail.size() > TRAIL_MAX:
		_trail.pop_back()
	queue_redraw()


## 轻轻放下：锅掉回场地继续飘，不算失误
func release_soft(pointer_velocity: Vector2) -> void:
	if state != State.HELD:
		return
	state = State.FLYING
	in_field = true
	var keep := pointer_velocity.length()
	if keep > 1.0:
		velocity = pointer_velocity.normalized() * clampf(keep, 40.0, 240.0)
	else:
		velocity = Vector2(_rng.randf_range(-60.0, 60.0), 90.0)
	held_time = 0.0
	queue_redraw()


## 甩出去：朝老板飞
func throw_back(throw_velocity: Vector2) -> void:
	if state != State.HELD:
		return
	hit_charge = charge
	state = State.THROWN
	in_field = true
	velocity = throw_velocity
	throw_time = 0.0
	_spin = _rng.randf_range(-9.0, 9.0)
	queue_redraw()


## 命中老板 / 没甩中，播一小段动画再回收
func resolve(hit: bool, boss_position: Vector2) -> void:
	if state == State.RESULT or state == State.HIDDEN:
		return
	if not hit:
		_resolve(false, velocity * 0.35 + Vector2(_rng.randf_range(-40.0, 40.0), 220.0))
		return
	var away := (global_position - boss_position)
	if away.length() < 1.0:
		away = Vector2(_rng.randf_range(-1.0, 1.0), -1.0)
	_resolve(true, away.normalized() * _rng.randf_range(240.0, 360.0))


func _resolve(hit: bool, exit_velocity: Vector2) -> void:
	state = State.RESULT
	_result_hit = hit
	_result_time = 0.0
	velocity = exit_velocity
	_trail.clear()
	queue_redraw()


## 回收（回到池子里等下次复用）
func hibernate() -> void:
	state = State.HIDDEN
	visible = false
	velocity = Vector2.ZERO
	_trail.clear()
	queue_redraw()


# ---------------------------------------------------------------- 每帧推进

func tick(delta: float) -> void:
	if state == State.HIDDEN:
		return
	age += delta
	_pulse += delta
	match state:
		State.FLYING:
			_tick_flying(delta)
		State.HELD:
			_tick_held(delta)
		State.THROWN:
			throw_time += delta
			global_position += velocity * delta
			_angle += _spin * delta
			_trail.push_front(global_position)
			while _trail.size() > TRAIL_MAX:
				_trail.pop_back()
		State.RESULT:
			_tick_result(delta)
	queue_redraw()


func _tick_flying(delta: float) -> void:
	global_position += velocity * delta
	_angle += _spin * delta
	_jitter_timer -= delta
	if _jitter_timer <= 0.0:
		_jitter_timer = _rng.randf_range(0.45, 1.0)
		var speed := velocity.length()
		velocity = velocity.rotated(_rng.randf_range(-wander, wander))
		velocity = velocity.normalized() * speed

	if not in_field and _field.has_point(global_position):
		in_field = true
		# 刚飞进场地：把「老板甩过来」的速度换成这口锅自己的飘移速度
		if velocity.length() > 1.0:
			velocity = velocity.normalized() * drift_speed
	if not in_field:
		return

	# 场地里弹来弹去（不会跑出可操作区域）
	var margin := type.grab_radius * 0.35 * scale_factor
	var min_x := _field.position.x + margin
	var max_x := _field.end.x - margin
	var min_y := _field.position.y + margin
	var max_y := _field.end.y - margin
	if global_position.x < min_x:
		global_position.x = min_x
		velocity.x = absf(velocity.x)
	elif global_position.x > max_x:
		global_position.x = max_x
		velocity.x = -absf(velocity.x)
	if global_position.y < min_y:
		global_position.y = min_y
		velocity.y = absf(velocity.y)
	elif global_position.y > max_y:
		global_position.y = max_y
		velocity.y = -absf(velocity.y)


func _tick_held(delta: float) -> void:
	held_time += delta
	_angle = lerp_angle(_angle, 0.0, minf(delta * 9.0, 1.0))
	if type.needs_charge:
		charge = clampf(charge + delta / maxf(type.charge_time, 0.05), 0.0, 1.0)


func _tick_result(delta: float) -> void:
	_result_time += delta
	global_position += velocity * delta
	if _result_hit:
		velocity *= 0.92
		scale = Vector2.ONE * scale_factor * maxf(1.0 - _result_time / 0.45, 0.15)
	else:
		velocity.y += 900.0 * delta
		_angle += 6.0 * delta
		scale = Vector2.ONE * scale_factor * maxf(1.0 - _result_time / 0.7, 0.1)
	modulate.a = clampf(1.0 - _result_time / (0.45 if _result_hit else 0.7), 0.0, 1.0)
	if _result_time >= (0.45 if _result_hit else 0.7):
		hibernate()


# ---------------------------------------------------------------- 查询

func is_active() -> bool:
	return state != State.HIDDEN


## 还在「等着被处理」的状态（同屏数量、超时判定都看它）
func is_actionable() -> bool:
	return state == State.FLYING or state == State.HELD or state == State.THROWN


func can_grab() -> bool:
	return state == State.FLYING and in_field


func is_held() -> bool:
	return state == State.HELD


## 这一口锅当前世界的判定半径（会跟着画面缩放一起放大）
func grab_radius() -> float:
	return type.grab_radius * scale_factor


func body_radius() -> float:
	return type.body_radius * scale_factor


## 手指 / 鼠标落在抓取圈里了吗
func catches_point(point: Vector2) -> bool:
	return can_grab() and global_position.distance_to(point) <= grab_radius()


func life_ratio() -> float:
	if max_life <= 0.0:
		return 0.0
	return clampf(life / max_life, 0.0, 1.0)


## 快凉了（画面上会闪红）
func is_expiring() -> bool:
	return state != State.HELD and life <= 1.2


func charge_ratio() -> float:
	return charge


## 结算动画已经播了多久（池子满了的时候按它挑最老的一个回收）
func result_age() -> float:
	return _result_time


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	if state == State.HIDDEN or type == null:
		return
	var r := type.body_radius * scale_factor

	# 拖动轨迹
	if state == State.HELD and _trail.size() > 1:
		for i in _trail.size():
			var t := 1.0 - float(i) / float(_trail.size())
			draw_circle(to_local(_trail[i]), (2.0 + 6.0 * t) * scale_factor,
				Color(Palette.ACCENT, 0.30 * t))

	_draw_shadow(r)
	match type.id:
		"iron":
			_draw_iron(r)
		"pan":
			_draw_pan(r)
		"pressure":
			_draw_pressure(r)
		"broken":
			_draw_broken(r)
		_:
			_draw_normal(r)

	_draw_state_overlays(r)
	_draw_tag(r)


func _draw_shadow(r: float) -> void:
	draw_circle(Vector2(3.0, 5.0) * scale_factor, r * 0.98, Color(0.0, 0.0, 0.0, 0.22))


func _draw_normal(r: float) -> void:
	draw_set_transform(Vector2.ZERO, _angle, Vector2.ONE)
	draw_circle(Vector2.ZERO, r, type.tint)
	draw_circle(Vector2.ZERO, r * 0.78, Palette.POT_METAL_DARK)
	draw_circle(Vector2(0.0, -r * 0.06), r * 0.68, Palette.SOUP)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 30, type.tint_dark, 3.0)
	# 盖子 + 盖钮
	draw_arc(Vector2(0.0, -r * 0.30), r * 0.92, PI, TAU, 22,
		Color(0.78, 0.81, 0.86), 4.0)
	draw_circle(Vector2(0.0, -r * 0.98), r * 0.18, Palette.ACCENT)
	# 两个耳朵
	for side in [-1.0, 1.0]:
		draw_arc(Vector2(side * r * 1.02, 0.0), r * 0.30,
			PI * 0.5 if side > 0.0 else -PI * 0.5,
			PI * 1.5 if side > 0.0 else PI * 0.5, 10, type.tint_dark, 4.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_iron(r: float) -> void:
	draw_set_transform(Vector2.ZERO, _angle, Vector2.ONE)
	# 厚底铁锅：外圈更厚、颜色更深，还有铆钉
	draw_circle(Vector2.ZERO, r, type.tint)
	draw_circle(Vector2(0.0, r * 0.06), r * 0.86, Palette.POT_IRON_RIM)
	draw_circle(Vector2(0.0, 0.0), r * 0.70, Color(0.14, 0.15, 0.18))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 36, Color(0.10, 0.11, 0.13), 5.0)
	for i in 8:
		var angle := TAU * float(i) / 8.0
		draw_circle(Vector2(cos(angle), sin(angle)) * r * 0.86, r * 0.07,
			Color(0.62, 0.66, 0.72))
	# 沉重的双耳（比普通锅更方）
	for side in [-1.0, 1.0]:
		draw_rect(Rect2(Vector2(side * r * 0.92 - (r * 0.30 if side < 0.0 else 0.0),
			-r * 0.20), Vector2(r * 0.30, r * 0.40)), Color(0.55, 0.58, 0.64))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_pan(r: float) -> void:
	draw_set_transform(Vector2.ZERO, _angle, Vector2.ONE)
	# 长柄（会跟着旋转，飞来飞去特别显眼）
	draw_line(Vector2(r * 0.4, 0.0), Vector2(r * 2.2, 0.0), Color(0.25, 0.22, 0.21),
		r * 0.34, true)
	draw_line(Vector2(r * 0.4, -r * 0.06), Vector2(r * 2.1, -r * 0.06),
		Color(0.42, 0.38, 0.36), r * 0.12, true)
	# 平底锅身：扁圆 + 亮边
	draw_circle(Vector2.ZERO, r, type.tint_dark)
	draw_circle(Vector2.ZERO, r * 0.94, type.tint)
	draw_circle(Vector2(0.0, r * 0.05), r * 0.72, Color(0.22, 0.23, 0.26))
	draw_arc(Vector2.ZERO, r * 0.96, PI * 1.1, PI * 1.9, 18,
		Color(0.96, 0.98, 1.0, 0.75), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_pressure(r: float) -> void:
	draw_set_transform(Vector2.ZERO, _angle, Vector2.ONE)
	# 压力锅：圆柱形锅身 + 顶上的阀 + 警示条纹
	draw_rect(Rect2(Vector2(-r * 0.86, -r * 0.70), Vector2(r * 1.72, r * 1.50)),
		type.tint_dark)
	draw_rect(Rect2(Vector2(-r * 0.78, -r * 0.62), Vector2(r * 1.56, r * 1.30)), type.tint)
	draw_rect(Rect2(Vector2(-r * 0.78, r * 0.28), Vector2(r * 1.56, r * 0.20)),
		Color(0.92, 0.62, 0.24))
	# 盖子 + 阀
	draw_rect(Rect2(Vector2(-r * 0.92, -r * 0.86), Vector2(r * 1.84, r * 0.26)),
		Color(0.72, 0.76, 0.82))
	var valve_color := Palette.OK if charge >= 0.95 else Color(0.60, 0.64, 0.70)
	draw_circle(Vector2(0.0, -r * 1.02), r * 0.20, valve_color)
	if charge > 0.02:
		draw_arc(Vector2.ZERO, r * 0.62, -PI * 0.5, -PI * 0.5 + TAU * charge, 26,
			Palette.CRIT_TEXT, 4.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_broken(r: float) -> void:
	draw_set_transform(Vector2.ZERO, _angle, Vector2.ONE)
	# 破锅：缺了一角，锅身上有裂纹
	var points := PackedVector2Array([
		Vector2(-r, -r * 0.15), Vector2(-r * 0.55, -r * 0.95),
		Vector2(r * 0.35, -r * 1.0), Vector2(r * 0.62, -r * 0.62),
		Vector2(r * 1.0, -r * 0.35), Vector2(r * 0.86, r * 0.32),
		Vector2(r * 0.25, r * 0.95), Vector2(-r * 0.5, r * 0.92),
	])
	draw_colored_polygon(points, type.tint)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, type.tint_dark, 2.5, true)
	draw_line(Vector2(-r * 0.25, -r * 0.55), Vector2(r * 0.05, r * 0.1),
		type.tint_dark, 2.5, true)
	draw_line(Vector2(r * 0.05, r * 0.1), Vector2(-r * 0.15, r * 0.6),
		type.tint_dark, 2.5, true)
	draw_circle(Vector2(-r * 0.15, r * 0.05), r * 0.30, Color(0.35, 0.24, 0.17))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_state_overlays(r: float) -> void:
	# 手里捏着：高亮圈 + 指向老板的虚线，第一次玩也能一眼看懂往哪甩
	if state == State.HELD:
		draw_arc(Vector2.ZERO, r * 1.5, 0.0, TAU, 30, Color(Palette.ACCENT, 0.75), 3.0)
		draw_arc(Vector2.ZERO, r * 1.5 + 6.0 * scale_factor,
			_pulse * 2.0, _pulse * 2.0 + 1.6, 18, Color(Palette.ACCENT, 0.35), 2.0)
		if type.needs_charge:
			var ready := charge >= 0.95
			var color := Palette.OK if ready else Palette.CRIT_TEXT
			draw_arc(Vector2.ZERO, r * 1.9, -PI * 0.5, -PI * 0.5 + TAU * charge, 30,
				color, 5.0)
			if ready:
				draw_arc(Vector2.ZERO, r * 2.1, 0.0, TAU, 30,
					Color(Palette.OK, 0.5), 2.0)

	# 存活时间环：快凉了会闪红
	if state == State.FLYING and in_field:
		var ratio := life_ratio()
		if ratio < 0.999:
			var color := Palette.DANGER if is_expiring() else Color(1.0, 1.0, 1.0, 0.35)
			if is_expiring():
				color.a = 0.45 + 0.55 * absf(sin(_pulse * 9.0))
			draw_arc(Vector2.ZERO, r * 1.35, -PI * 0.5, -PI * 0.5 + TAU * ratio, 26,
				color, 3.0)
	if is_expiring():
		for i in 3:
			var angle := _pulse * 3.0 + TAU * float(i) / 3.0
			draw_circle(Vector2.RIGHT.rotated(angle) * r * 1.8, 3.0 * scale_factor,
				Color(Palette.DANGER, 0.75))


func _draw_tag(r: float) -> void:
	if blame.is_empty() or _tag_style == null:
		return
	var font := Fonts.ui()
	var font_size := int(round(15.0 * scale_factor))
	var text_size := font.get_string_size(blame, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var box := Rect2(
		Vector2(-text_size.x * 0.5 - 8.0 * scale_factor, r * 1.35),
		Vector2(text_size.x + 16.0 * scale_factor, text_size.y + 6.0 * scale_factor))
	_tag_style.border_color = type.tint
	draw_style_box(_tag_style, box)
	draw_string(font, Vector2(-text_size.x * 0.5, box.position.y + text_size.y * 0.95),
		blame, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Palette.UI_TEXT)
