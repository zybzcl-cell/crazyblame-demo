class_name MenuProp
extends Node2D
## 主菜单上的小演出：一口锅在「老板 ↔ 桌面」之间来回飞。
##
## 飞回老板时会发 impact 信号，菜单让老板抖一下、换个表情 —— 让人一眼看懂这个游戏在干嘛。

signal impact

var _size := Vector2(720.0, 1280.0)
var _boss_pos := Vector2(360.0, 345.0)
var _field := Rect2(40.0, 520.0, 640.0, 640.0)
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _control := Vector2.ZERO
var _progress := 0.0
var _duration := 1.0
var _stage := 0
var _rest := 0.0
var _angle := 0.0
var _spin := 0.0
var _pot_scale := 1.0
var _trail: Array[Vector2] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_begin_player_throw()


func configure(size: Vector2, boss_position: Vector2, pot_scale: float) -> void:
	_size = size
	_boss_pos = boss_position
	_pot_scale = pot_scale
	# 只用下半屏操作区的上半部分：按钮不会被飞来飞去的锅挡住
	var layout := LayoutData.compute(size)
	var field: Rect2 = layout["field"]
	_field = Rect2(field.position.x, field.position.y, field.size.x, field.size.y * 0.60)
	if _stage >= 2:
		_begin_player_throw()


func tick(delta: float) -> void:
	if _rest > 0.0:
		_rest = maxf(_rest - delta, 0.0)
		if _rest <= 0.0:
			if _stage == 1:
				_begin_boss_throw()
			else:
				_begin_player_throw()
		return
	_progress = minf(_progress + delta / maxf(_duration, 0.05), 1.0)
	var t := _ease(_progress)
	global_position = _bezier(_from, _control, _to, t)
	_angle += _spin * delta
	_trail.push_front(global_position)
	while _trail.size() > 8:
		_trail.pop_back()
	if _progress >= 1.0:
		if _stage == 0:
			impact.emit()
			_stage = 1
			_rest = 0.45
		else:
			_stage = 2
			_rest = 0.35
	queue_redraw()


func _begin_player_throw() -> void:
	_stage = 0
	_from = Vector2(_rng.randf_range(_field.position.x + 80.0, _field.end.x - 80.0),
		_rng.randf_range(_field.position.y + 120.0, _field.end.y - 60.0))
	_to = _boss_pos + Vector2(0.0, -40.0 * _pot_scale)
	_control = (_from + _to) * 0.5 + Vector2(_rng.randf_range(-260.0, 260.0), -120.0)
	_progress = 0.0
	_duration = _rng.randf_range(0.75, 0.95)
	_spin = _rng.randf_range(-8.0, 8.0)
	_trail.clear()


func _begin_boss_throw() -> void:
	_stage = 2
	_from = _boss_pos + Vector2(_rng.randf_range(-70.0, 70.0), 20.0)
	_to = Vector2(_rng.randf_range(_field.position.x + 80.0, _field.end.x - 80.0),
		_rng.randf_range(_field.position.y + 140.0, _field.end.y - 60.0))
	_control = (_from + _to) * 0.5 + Vector2(_rng.randf_range(-200.0, 200.0), 60.0)
	_progress = 0.0
	_duration = _rng.randf_range(0.6, 0.8)
	_spin = _rng.randf_range(-6.0, 6.0)
	_trail.clear()


func _ease(value: float) -> float:
	return 1.0 - pow(1.0 - value, 2.0)


func _bezier(a: Vector2, control: Vector2, b: Vector2, t: float) -> Vector2:
	var ab := a.lerp(control, t)
	var bc := control.lerp(b, t)
	return ab.lerp(bc, t)


func _draw() -> void:
	var r := 30.0 * _pot_scale
	for i in _trail.size():
		var t := 1.0 - float(i) / float(maxi(_trail.size(), 1))
		draw_circle(to_local(_trail[i]), (3.0 + 8.0 * t) * _pot_scale,
			Color(Palette.BLAIM, 0.16 * t))
	draw_set_transform(Vector2.ZERO, _angle, Vector2.ONE)
	draw_circle(Vector2(3.0, 5.0), r * 0.98, Color(0.0, 0.0, 0.0, 0.22))
	draw_circle(Vector2.ZERO, r, Palette.POT_METAL)
	draw_circle(Vector2.ZERO, r * 0.76, Palette.POT_METAL_DARK)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, Palette.POT_METAL_DARK, 3.0)
	draw_arc(Vector2(0.0, -r * 0.30), r * 0.92, PI, TAU, 20, Color(0.80, 0.83, 0.88), 4.0)
	draw_circle(Vector2(0.0, -r * 0.98), r * 0.18, Palette.ACCENT)
	for side in [-1.0, 1.0]:
		draw_arc(Vector2(side * r * 1.02, 0.0), r * 0.30,
			PI * 0.5 if side > 0.0 else -PI * 0.5,
			PI * 1.5 if side > 0.0 else PI * 0.5, 10, Palette.POT_METAL_DARK, 4.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
