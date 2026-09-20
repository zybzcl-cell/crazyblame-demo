class_name OfficeBackground
extends Node2D
## 办公室背景：墙面、窗户、本月业绩白板、地板、绿植。
##
## 目标不是「画得花」，而是让老板看起来真的**坐在这个办公室里**：
##   - 墙面从屏幕顶部一直延伸到地板线，窗户与白板都**挂在墙上**（带挂件投影、边框、托板）；
##   - 地板线正好在办公桌下沿，桌子像压在地板与墙的交界上；
##   - 甩锅操作区画成地板上的一块办公区地毯，玩家一眼就知道锅会出现在哪；
##   - 背景整体压低对比度（冷灰蓝墙面 + 暖木地板），把视觉焦点让给老板和锅。
##
## 另外保留一个小叙事：白板上「本月业绩」的折线跟着老板的精神状态一起往下掉。

var _size := Vector2(720.0, 1280.0)
var _layout: Dictionary = {}
var _ratio := 1.0
var _frenzy := false
var _time := 0.0
var _flash := 0.0


func configure(size: Vector2, layout: Dictionary = {}) -> void:
	_size = size
	_layout = layout if not layout.is_empty() else LayoutData.compute(size)
	queue_redraw()


## 老板的精神状态（0~1，1 是满血得意）
func set_stress(ratio: float) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	queue_redraw()


func set_frenzy(on: bool) -> void:
	_frenzy = on
	queue_redraw()


func flash() -> void:
	_flash = 0.3
	queue_redraw()


func tick(delta: float) -> void:
	_time += delta
	if _flash > 0.0:
		_flash = maxf(_flash - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	if _layout.is_empty():
		_layout = LayoutData.compute(_size)
	var w := _size.x
	var h := _size.y
	var floor_y := float(_layout["floor_y"])
	var content: Rect2 = _layout["content_rect"]

	_draw_wall(w, floor_y)
	_draw_ceiling(w, h)
	_draw_window(_layout["window"])
	_draw_whiteboard(_layout["board"])
	_draw_floor(w, h, floor_y)
	_draw_field_mat(_layout["field"])
	_draw_plant(Vector2(content.position.x + content.size.x * 0.03, floor_y + h * 0.075))
	_draw_vignette(w, h)
	if _frenzy:
		_draw_frenzy(w, h)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, _size), Color(1.0, 1.0, 1.0, 0.18 * (_flash / 0.3)))


# ---------------------------------------------------------------- 空间

func _draw_wall(w: float, floor_y: float) -> void:
	# 墙面：上深下浅的竖向层次 + 淡淡的墙板缝
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, floor_y)), Palette.WALL)
	draw_rect(Rect2(Vector2(0.0, floor_y * 0.55), Vector2(w, floor_y * 0.45)),
		Palette.WALL_LIGHT)
	for i in 7:
		var x := w * float(i) / 6.0
		draw_line(Vector2(x, 0.0), Vector2(x, floor_y), Color(0.0, 0.0, 0.0, 0.06), 1.5, true)
	# 踢脚线
	draw_rect(Rect2(Vector2(0.0, floor_y - 5.0), Vector2(w, 5.0)), Palette.WALL_TRIM)


func _draw_ceiling(w: float, h: float) -> void:
	draw_rect(Rect2(Vector2(0.0, 0.0), Vector2(w, h * 0.012)), Color(0.16, 0.19, 0.24))
	draw_rect(Rect2(Vector2(w * 0.14, h * 0.014), Vector2(w * 0.72, h * 0.010)),
		Color(0.92, 0.94, 0.98, 0.28))


func _draw_floor(w: float, h: float, floor_y: float) -> void:
	# 地板：暖色木地板，比墙面亮一点，让深色的锅跳出来
	draw_rect(Rect2(Vector2(0.0, floor_y), Vector2(w, h - floor_y)), Palette.FLOOR)
	for i in 9:
		var t := float(i) / 8.0
		draw_line(Vector2(w * t - w * 0.10, floor_y), Vector2(w * t - w * 0.30, h),
			Color(0.0, 0.0, 0.0, 0.07), 2.0, true)
	for row in 5:
		var y := floor_y + (h - floor_y) * pow(float(row) / 5.0, 1.4)
		draw_line(Vector2(0.0, y), Vector2(w, y), Color(0.0, 0.0, 0.0, 0.05), 1.5, true)
	draw_rect(Rect2(Vector2(0.0, floor_y), Vector2(w, 3.0)), Palette.FLOOR_DARK)


## 甩锅操作区：地板上的一块办公区地毯（给玩家「锅会在这里出现」的边界感）
func _draw_field_mat(field: Rect2) -> void:
	var mat := field.grow(6.0)
	draw_rect(mat, Color(0.20, 0.24, 0.31, 0.35))
	draw_rect(mat.grow(-4.0), Color(0.26, 0.31, 0.39, 0.30))
	for i in 4:
		var inset := 10.0 + float(i) * 14.0
		draw_rect(Rect2(mat.position + Vector2(inset, inset),
			mat.size - Vector2(inset * 2.0, inset * 2.0)), Color(Palette.INFO, 0.05), false, 1.5)


func _draw_vignette(w: float, h: float) -> void:
	# 四角压暗，把注意力留给中间（老板 + 锅）
	var step := 26.0
	for i in 10:
		var t := float(i) / 10.0
		var alpha := 0.035 * (1.0 - t)
		var band := step * float(i)
		draw_rect(Rect2(0.0, band, w, step), Color(0.0, 0.0, 0.0, alpha))
		draw_rect(Rect2(0.0, h - band - step, w, step), Color(0.0, 0.0, 0.0, alpha * 1.4))
		draw_rect(Rect2(band, 0.0, step, h), Color(0.0, 0.0, 0.0, alpha * 0.8))
		draw_rect(Rect2(w - band - step, 0.0, step, h), Color(0.0, 0.0, 0.0, alpha * 0.8))


func _draw_frenzy(w: float, h: float) -> void:
	# 疯狂甩锅时间：整屏泛红 + 边缘速度线
	var pulse := 0.16 + 0.06 * sin(_time * 8.0)
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Color(Palette.DANGER, pulse))
	for i in 14:
		var y := fmod(float(i) * h / 14.0 + _time * 260.0, h)
		draw_line(Vector2(0.0, y), Vector2(w * 0.10, y - h * 0.05),
			Color(1.0, 1.0, 1.0, 0.05), 3.0, true)
		draw_line(Vector2(w, y), Vector2(w * 0.90, y - h * 0.05),
			Color(1.0, 1.0, 1.0, 0.05), 3.0, true)


# ---------------------------------------------------------------- 墙上的挂件

func _draw_window(rect: Rect2) -> void:
	# 挂件阴影：让窗户「贴」在墙上，而不是浮在画面前
	draw_rect(Rect2(rect.position + Vector2(6.0, 7.0), rect.size), Color(0.0, 0.0, 0.0, 0.22))
	draw_rect(rect.grow(7.0), Palette.WINDOW_FRAME)
	draw_rect(rect, Palette.WINDOW_GLASS)
	# 窗外的楼
	for i in 4:
		var bw := rect.size.x * 0.20
		var bh := rect.size.y * (0.35 + 0.16 * float(i % 3))
		var bx := rect.position.x + rect.size.x * (0.06 + 0.24 * float(i))
		draw_rect(Rect2(Vector2(bx, rect.end.y - bh), Vector2(bw, bh)),
			Color(0.20, 0.26, 0.34))
		for row in 3:
			draw_rect(Rect2(Vector2(bx + bw * 0.18, rect.end.y - bh + float(row) * bh * 0.3),
				Vector2(bw * 0.24, bh * 0.12)), Color(1.0, 0.92, 0.62, 0.45))
	# 百叶帘
	for i in 5:
		var y := rect.position.y + rect.size.y * (0.06 + 0.13 * float(i))
		draw_line(Vector2(rect.position.x + 4.0, y), Vector2(rect.end.x - 4.0, y),
			Color(0.0, 0.0, 0.0, 0.10), 3.0, true)
	# 窗框十字 + 窗台
	draw_line(Vector2(rect.get_center().x, rect.position.y),
		Vector2(rect.get_center().x, rect.end.y), Palette.WINDOW_FRAME, 4.0)
	draw_line(Vector2(rect.position.x, rect.get_center().y),
		Vector2(rect.end.x, rect.get_center().y), Palette.WINDOW_FRAME, 4.0)
	draw_rect(Rect2(Vector2(rect.position.x - 8.0, rect.end.y), Vector2(rect.size.x + 16.0, 7.0)),
		Palette.WINDOW_FRAME.darkened(0.15))
	# 窗光洒下来（很淡，只做空间暗示）
	draw_colored_polygon(PackedVector2Array([
		rect.position + Vector2(rect.size.x * 0.1, rect.size.y + 8.0),
		rect.position + Vector2(rect.size.x * 0.9, rect.size.y + 8.0),
		rect.position + Vector2(rect.size.x * 2.0, rect.size.y + rect.size.y * 1.4),
		rect.position + Vector2(-rect.size.x * 0.3, rect.size.y + rect.size.y * 1.4),
	]), Color(1.0, 0.95, 0.80, 0.05))


func _draw_whiteboard(rect: Rect2) -> void:
	# 挂件阴影 + 挂条 + 边框 + 板面
	draw_rect(Rect2(rect.position + Vector2(5.0, 6.0), rect.size), Color(0.0, 0.0, 0.0, 0.22))
	draw_rect(Rect2(Vector2(rect.position.x - 6.0, rect.position.y - 9.0),
		Vector2(rect.size.x + 12.0, 5.0)), Color(0.55, 0.60, 0.68))
	draw_rect(rect.grow(6.0), Palette.WINDOW_FRAME.darkened(0.05))
	draw_rect(rect, Color(0.94, 0.96, 0.97))
	# 笔托与两支笔
	draw_rect(Rect2(Vector2(rect.position.x + 10.0, rect.end.y + 2.0),
		Vector2(rect.size.x * 0.42, 5.0)), Color(0.62, 0.66, 0.72))
	draw_line(Vector2(rect.position.x + 18.0, rect.end.y + 2.0),
		Vector2(rect.position.x + 34.0, rect.end.y + 2.0), Palette.DANGER, 4.0, true)
	draw_line(Vector2(rect.position.x + 40.0, rect.end.y + 2.0),
		Vector2(rect.position.x + 56.0, rect.end.y + 2.0), Palette.INFO, 4.0, true)

	var font := Fonts.ui()
	var title_size := int(clampf(rect.size.y * 0.15, 12.0, 22.0))
	draw_string(font, rect.position + Vector2(12.0, float(title_size) + 6.0), "本月业绩",
		HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color(0.30, 0.34, 0.40))

	# 折线：老板精神越好，曲线越往上；被打崩了就一路向下
	var chart := Rect2(rect.position + Vector2(rect.size.x * 0.08, rect.size.y * 0.34),
		Vector2(rect.size.x * 0.84, rect.size.y * 0.54))
	draw_line(Vector2(chart.position.x - 4.0, chart.end.y),
		Vector2(chart.end.x + 4.0, chart.end.y), Color(0.72, 0.76, 0.82), 2.0, true)
	draw_line(Vector2(chart.position.x - 4.0, chart.position.y),
		Vector2(chart.position.x - 4.0, chart.end.y), Color(0.72, 0.76, 0.82), 2.0, true)
	var points := PackedVector2Array()
	var steps := 6
	for i in steps + 1:
		var t := float(i) / float(steps)
		var drop := (1.0 - _ratio) * (0.15 + 0.85 * t)
		points.append(Vector2(chart.position.x + chart.size.x * t,
			chart.position.y + chart.size.y * (0.16 + drop * 0.80)))
	var line_color := Palette.OK if _ratio > 0.5 else (
		Palette.ACCENT if _ratio > 0.2 else Palette.DANGER)
	draw_polyline(points, line_color, 3.0, true)
	for p in points:
		draw_circle(p, 3.0, line_color)
	if _ratio <= 0.02:
		draw_string(font, Vector2(chart.position.x + chart.size.x * 0.18,
			chart.position.y + chart.size.y * 0.72), "完蛋",
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(clampf(rect.size.y * 0.22, 14.0, 30.0)),
			Palette.DANGER)


func _draw_plant(origin: Vector2) -> void:
	# 地板上的绿植（在画面左侧、场地之外，不会挡锅）
	draw_rect(Rect2(origin + Vector2(-20.0, -18.0), Vector2(40.0, 34.0)), Color(0.48, 0.33, 0.25))
	draw_rect(Rect2(origin + Vector2(-24.0, -22.0), Vector2(48.0, 8.0)), Color(0.56, 0.39, 0.29))
	for i in 5:
		var angle := -PI * 0.5 + (float(i) - 2.0) * 0.34
		var tip := origin + Vector2(cos(angle), sin(angle)) * 66.0
		draw_line(origin + Vector2(0.0, -20.0), tip, Color(0.26, 0.46, 0.30), 5.0, true)
		draw_circle(tip, 10.0, Palette.PLANT)
