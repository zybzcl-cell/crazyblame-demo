class_name FxLayer
extends Node2D
## 特效层：伤害数字、命中冲击、扩散圆环、结算彩带。
##
## 全部自己推进时间（tick），不依赖 Tween —— 这样自动化测试能把时间直接推过去，
## 也能保证「暂停 / 结算」时特效不会卡在半路。

const MAX_TEXTS := 24
const MAX_BURSTS := 40
const MAX_CONFETTI := 120

var _texts: Array[Dictionary] = []
var _bursts: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _confetti: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
## 界面缩放（小屏的数字也相应收小）
var _ui_scale := 1.0


func _ready() -> void:
	_rng.randomize()


## 布局变化时由游戏主控调用
func configure(ui_scale: float) -> void:
	_ui_scale = clampf(ui_scale, 0.5, 2.2)


func clear() -> void:
	_texts.clear()
	_bursts.clear()
	_rings.clear()
	_confetti.clear()
	queue_redraw()


## 当前还有多少特效在播（测试用）
func counts() -> Dictionary:
	return {
		"texts": _texts.size(),
		"bursts": _bursts.size(),
		"rings": _rings.size(),
		"confetti": _confetti.size(),
	}


## 伤害数字（会往上飘 + 淡出，重击数字更大）
func spawn_damage(position: Vector2, text: String, color: Color, size: float = 34.0) -> void:
	if _texts.size() >= MAX_TEXTS:
		_texts.pop_front()
	_texts.append({
		"pos": position + Vector2(_rng.randf_range(-16.0, 16.0), _rng.randf_range(-8.0, 8.0)),
		"text": text,
		"color": color,
		"size": size * _ui_scale,
		"t": 0.0,
		"life": 0.95,
		"rise": _rng.randf_range(120.0, 170.0),
		"drift": _rng.randf_range(-40.0, 40.0),
	})
	queue_redraw()


## 命中冲击：中心闪光 + 四散碎片
func spawn_burst(position: Vector2, color: Color, power: float = 1.0) -> void:
	if _bursts.size() >= MAX_BURSTS:
		_bursts.pop_front()
	_bursts.append({
		"pos": position,
		"color": color,
		"t": 0.0,
		"life": 0.35,
		"power": power,
		"angle": _rng.randf_range(0.0, TAU),
	})
	var count := clampi(int(6.0 + 8.0 * power), 5, 20)
	for i in count:
		if _bursts.size() >= MAX_BURSTS:
			break
		var angle := TAU * float(i) / float(count) + _rng.randf_range(-0.2, 0.2)
		var speed := _rng.randf_range(140.0, 320.0) * (0.7 + 0.6 * power)
		_bursts.append({
			"pos": position,
			"color": color,
			"t": 0.0,
			"life": _rng.randf_range(0.28, 0.5),
			"power": power * 0.4,
			"angle": angle,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"shard": true,
		})
	queue_redraw()


## 扩散圆环（阶段变化 / KO 用）
func spawn_ring(position: Vector2, color: Color, radius: float, width: float = 6.0) -> void:
	_rings.append({
		"pos": position, "color": color, "radius": radius, "width": width, "t": 0.0, "life": 0.6,
	})
	queue_redraw()


## 结算 / 破纪录的彩带（width 是画面宽度）
func spawn_confetti(count: int = 60, width: float = 720.0) -> void:
	for i in count:
		if _confetti.size() >= MAX_CONFETTI:
			break
		_confetti.append({
			"pos": Vector2(_rng.randf_range(0.0, width), _rng.randf_range(-160.0, 0.0)),
			"vel": Vector2(_rng.randf_range(-40.0, 40.0), _rng.randf_range(120.0, 320.0)),
			"angle": _rng.randf_range(0.0, TAU),
			"spin": _rng.randf_range(-6.0, 6.0),
			"t": 0.0,
			"life": 0.0,
			"color": [Palette.ACCENT, Palette.OK, Palette.INFO, Palette.DANGER, Palette.COMBO_TEXT][
				_rng.randi_range(0, 4)],
			"size": _rng.randf_range(6.0, 14.0),
		})
	queue_redraw()


func tick(delta: float) -> void:
	for text in _texts:
		text["t"] = float(text["t"]) + delta
	for burst in _bursts:
		burst["t"] = float(burst["t"]) + delta
		if burst.has("vel"):
			var vel: Vector2 = Vector2(burst["vel"]) * (1.0 - 2.0 * delta) \
				+ Vector2(0.0, 320.0 * delta)
			burst["vel"] = vel
			burst["pos"] = Vector2(burst["pos"]) + vel * delta
	for ring in _rings:
		ring["t"] = float(ring["t"]) + delta
	for piece in _confetti:
		piece["t"] = float(piece["t"]) + delta
		piece["pos"] = Vector2(piece["pos"]) + Vector2(piece["vel"]) * delta
		piece["vel"] = Vector2(piece["vel"]) + Vector2(0.0, 420.0 * delta)
		piece["angle"] = float(piece["angle"]) + float(piece["spin"]) * delta
	_prune(_texts)
	_prune(_bursts)
	_prune(_rings)
	_prune(_confetti, 3.2)
	var alive := not (_texts.is_empty() and _bursts.is_empty() and _rings.is_empty()
		and _confetti.is_empty())
	if alive:
		queue_redraw()


## 清掉过期的条目，返回是否还有内容
func _prune(list: Array, extra_life: float = 0.0) -> bool:
	var i := 0
	while i < list.size():
		var item: Dictionary = list[i]
		if float(item["t"]) >= float(item["life"]) + extra_life:
			list.remove_at(i)
		else:
			i += 1
	return not list.is_empty()


func _draw() -> void:
	# 冲击碎片
	for burst in _bursts:
		var t := float(burst["t"]) / float(burst["life"])
		var color: Color = burst["color"]
		if burst.get("shard", false):
			draw_circle(Vector2(burst["pos"]), (2.0 + 3.0 * float(burst["power"])) * (1.0 - t),
				Color(color, color.a * (1.0 - t)))
		else:
			var power := float(burst["power"])
			draw_circle(Vector2(burst["pos"]), (26.0 + 60.0 * power) * (0.4 + t),
				Color(1.0, 1.0, 1.0, 0.35 * (1.0 - t)))
			draw_arc(Vector2(burst["pos"]), (30.0 + 70.0 * power) * (0.4 + t), 0.0, TAU, 26,
				Color(color, 0.8 * (1.0 - t)), 5.0 * (1.0 - t) + 1.0)

	# 扩散圆环
	for ring in _rings:
		var t := float(ring["t"]) / float(ring["life"])
		var color: Color = ring["color"]
		draw_arc(Vector2(ring["pos"]), float(ring["radius"]) * (0.3 + t), 0.0, TAU, 40,
			Color(color, 0.7 * (1.0 - t)), float(ring["width"]) * (1.0 - t) + 1.0)

	# 彩带
	for piece in _confetti:
		draw_set_transform(Vector2(piece["pos"]), float(piece["angle"]), Vector2.ONE)
		draw_rect(Rect2(Vector2(-float(piece["size"]) * 0.5, -3.0),
			Vector2(float(piece["size"]), 6.0)), piece["color"])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 伤害数字
	var font := Fonts.ui()
	for text in _texts:
		var t := float(text["t"]) / float(text["life"])
		var pos := Vector2(text["pos"]) + Vector2(float(text["drift"]) * t,
			-float(text["rise"]) * t)
		var size := int(round(float(text["size"]) * (1.0 + 0.25 * (1.0 - minf(t * 3.0, 1.0)))))
		var color: Color = text["color"]
		var alpha := 1.0 - maxf(0.0, t - 0.6) / 0.4
		var content := str(text["text"])
		var width := font.get_string_size(content, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string_outline(font, pos - Vector2(width * 0.5, 0.0), content,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0.0, 0.0, 0.0, 0.65 * alpha))
		draw_string(font, pos - Vector2(width * 0.5, 0.0), content,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(color, color.a * alpha))
