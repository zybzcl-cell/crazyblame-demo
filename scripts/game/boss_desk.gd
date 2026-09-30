class_name BossDesk
extends Node2D
## 老板面前那张办公桌 + 椅子 + 桌上道具（**场景道具，不属于 Boss 角色本体**）。
##
## Boss 的长相由 `assets/characters/boss/` 的 PNG 负责；桌子仍然由这里程序绘制，
## 因为它属于「办公场景」。如果将来的 Boss 素材里自带桌子，
## 在 `manifest.json` 里把 `"draw_desk": false` 打开即可关掉这一层。

var host: BlameBoss = null


func configure(boss: BlameBoss) -> void:
	host = boss


func _draw() -> void:
	if host == null:
		return
	var r := host.body_radius()
	var stage := host.stage_index()
	var t := host.tick_time()
	var wobble := host.wobble_amount()
	var mess := host.mess_level()
	var ko := host.is_ko()

	var wobble_offset := Vector2(sin(t * 40.0) * wobble * 3.0, 0.0)
	# ---- 办公椅（在身体后面，比肚子窄）
	draw_rect(Rect2(Vector2(-r * 0.92, -r * 0.50), Vector2(r * 1.84, r * 0.94)),
		Color(0.20, 0.23, 0.30))
	# ---- 桌面 + 桌身
	var top := Rect2(Vector2(-r * 2.05, r * (0.72 if ko else 0.86)) + wobble_offset,
		Vector2(r * 4.10, r * 0.26))
	var body := Rect2(Vector2(-r * 2.05, top.end.y) + wobble_offset,
		Vector2(r * 4.10, r * (1.10 if ko else 0.72)))
	draw_rect(body, Palette.DESK)
	draw_rect(top, Palette.DESK_TOP)
	draw_rect(Rect2(top.position, Vector2(top.size.x, maxf(r * 0.03, 1.4))), Palette.DESK_DARK)
	draw_rect(Rect2(Vector2(-r * 2.05, top.end.y - r * 0.02) + wobble_offset,
		Vector2(r * 4.10, maxf(r * 0.04, 1.8))), Palette.DESK_DARK)
	# ---- 桌上的东西（咖啡 / 文件 / 铭牌 / 笔筒），被打得越惨越乱
	_draw_items(r, t, wobble, wobble_offset, stage, mess, ko)


func _draw_items(r: float, t: float, wobble: float, wobble_offset: Vector2, stage: int,
		mess: float, ko: bool) -> void:
	var base := 0.72 if ko else 0.94
	# 咖啡杯
	var cup := Vector2(-r * 1.48, r * base) + wobble_offset
	draw_rect(Rect2(cup, Vector2(r * 0.40, r * 0.42)), Color(0.95, 0.96, 0.99))
	draw_rect(Rect2(cup + Vector2(r * 0.34, r * 0.08), Vector2(r * 0.14, r * 0.20)),
		Color(0.95, 0.96, 0.99))
	draw_rect(Rect2(cup + Vector2(r * 0.06, r * 0.05), Vector2(r * 0.28, maxf(r * 0.07, 2.4))),
		Color(0.36, 0.22, 0.14))
	if stage <= 1 and not ko:
		for i in 3:
			var k := fmod(t * 0.7 + float(i) * 0.33, 1.0)
			draw_circle(cup + Vector2(r * 0.20, -r * 0.16 - k * r * 0.42), r * 0.07 * (1.0 - k),
				Color(1.0, 1.0, 1.0, 0.26 * (1.0 - k)))
	else:
		var spill := clampf(float(stage - 1) / 5.0, 0.0, 1.0)
		draw_colored_polygon(PackedVector2Array([
			cup + Vector2(r * 0.40, r * 0.30),
			cup + Vector2(r * (0.40 + 1.20 * spill), r * 0.44),
			cup + Vector2(r * 0.44, r * 0.46),
		]), Color(0.38, 0.24, 0.16, 0.85))
	# 文件
	for i in 3:
		var offset := Vector2(r * (0.86 + float(i) * 0.15), r * (base + 0.24 - float(i) * 0.03)) \
			+ wobble_offset * (0.6 + 0.2 * float(i))
		var angle := 0.10 * float(i) + (t * 0.4 if stage >= 3 else 0.0) + (0.5 if ko else 0.0)
		draw_set_transform(offset, angle, Vector2.ONE)
		draw_rect(Rect2(Vector2(-r * 0.42, -r * 0.28), Vector2(r * 0.84, r * 0.56)),
			Color(0.96, 0.96, 0.93))
		for line in 3:
			draw_line(Vector2(-r * 0.30, -r * 0.14 + float(line) * r * 0.14),
				Vector2(r * 0.30, -r * 0.14 + float(line) * r * 0.14),
				Color(0.62, 0.65, 0.71), maxf(r * 0.02, 1.2), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 铭牌
	draw_set_transform(Vector2(-r * 0.12, r * (base + 0.46)) + wobble_offset, -0.06, Vector2.ONE)
	draw_rect(Rect2(Vector2(-r * 0.62, -r * 0.14), Vector2(r * 1.24, r * 0.28)),
		Color(0.26, 0.21, 0.16))
	draw_rect(Rect2(Vector2(-r * 0.56, -r * 0.09), Vector2(r * 1.12, r * 0.18)),
		Color(0.88, 0.74, 0.44))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 笔筒 + 笔
	draw_rect(Rect2(Vector2(r * 1.30, r * (base + 0.06)) + wobble_offset,
		Vector2(r * 0.32, r * 0.62)), Color(0.32, 0.36, 0.45))
	for i in 3:
		var pen := Vector2(r * 1.36 + float(i) * r * 0.08, r * (base - 0.16)) + wobble_offset
		draw_line(pen, pen + Vector2(0.0, -r * 0.26), Color(0.86 - float(i) * 0.20, 0.42, 0.36),
			maxf(r * 0.045, 2.0), true)
