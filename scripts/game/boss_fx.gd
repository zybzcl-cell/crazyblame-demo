class_name BossFx
extends Node2D
## Boss 的**独立特效层**（受击 FX / 阶段特效）。
##
## 分工：Boss 本体长相 = 美术素材（`BossArt` + SpriteFrames）；
## 这里只负责「被打到的效果」——星星、痛感线、灰尘、鼻血、头包、眼镜裂纹、白光、扣头锅。
## 所有位置都来自 `BossArt` 的锚点（r 单位），所以换一张 Boss 贴图也不会跑偏。

var host: BlameBoss = null


func configure(boss: BlameBoss) -> void:
	host = boss


func _draw() -> void:
	if host == null:
		return
	var r := host.body_radius()
	var art := host.art()
	var head := art.anchor("head") * r
	var face := art.anchor("face") * r
	var stage := host.stage_index()

	# ---- 换阶段的冲击波
	var stage_flash := host.stage_flash()
	if stage_flash > 0.0:
		var t := 1.0 - stage_flash / 0.8
		draw_arc(head + Vector2(0.0, r * 0.10), r * (0.8 + t * 2.4), 0.0, TAU, 40,
			Color(Palette.DANGER, 0.5 * (1.0 - t)), 6.0)
	# ---- 受击白光
	var hit_flash := host.hit_flash()
	if hit_flash > 0.0:
		draw_circle(head, r * 1.05, Color(1.0, 1.0, 1.0, 0.30 * (hit_flash / 0.24)))
	# ---- 被锅扣在头上
	if host.stuck_pot() != null:
		_draw_stuck_pot(head + Vector2(0.0, -r * 0.74), r * 0.54, host.stuck_pot())
	# ---- 战损：头包 / 红鼻子 / 黑印 / 眼镜裂纹
	if host.has_head_bump():
		var at := head + Vector2(-r * 0.30, -r * 0.66)
		_circle(at, r * 0.26, host.skin_tint().lerp(Color("e0786a"), 0.42), maxf(r * 0.03, 1.6))
		draw_arc(at, r * 0.14, 0.0, TAU, 16, Color("cd5349", 0.55), maxf(r * 0.035, 1.8), true)
	if host.has_red_nose():
		var nose := face + Vector2(0.0, r * 0.52)
		_circle(nose, r * 0.20, Color("dd6459"), maxf(r * 0.026, 1.4))
		var drip := r * (0.30 + 0.34 * clampf(host.nose_hit() / 0.55, 0.0, 1.0))
		draw_line(nose + Vector2(r * 0.12, r * 0.16), nose + Vector2(r * 0.16, drip),
			Color("c2453f"), maxf(r * 0.05, 2.2), true)
		draw_circle(nose + Vector2(r * 0.16, drip + r * 0.06), r * 0.07, Color("c2453f"))
	if host.has_face_soot():
		var soot := Color(0.15, 0.14, 0.14, 0.55)
		for spot in [Vector2(-r * 0.40, r * 0.54), Vector2(r * 0.06, r * 0.70),
				Vector2(r * 0.44, r * 0.38), Vector2(-r * 0.14, r * 0.34)]:
			draw_circle(face + (spot as Vector2), r * 0.17, soot)
		draw_line(face + Vector2(-r * 0.50, r * 0.42), face + Vector2(-r * 0.22, r * 0.60),
			Color(0.18, 0.17, 0.16, 0.45), maxf(r * 0.05, 2.0), true)
	if host.has_glasses_crack():
		var lens := face + Vector2(r * 0.34, -r * 0.06)
		var crack := Color(0.04, 0.05, 0.07)
		var w := maxf(r * 0.04, 1.8)
		draw_line(lens + Vector2(-r * 0.22, -r * 0.06), lens + Vector2(r * 0.03, r * 0.05), crack, w, true)
		draw_line(lens + Vector2(r * 0.03, r * 0.05), lens + Vector2(r * 0.20, r * 0.17), crack, w, true)
		draw_line(lens + Vector2(r * 0.03, r * 0.05), lens + Vector2(r * 0.09, -r * 0.19), crack, w, true)
	# ---- 这一口锅的撞击符号
	var impact_time := host.impact_time()
	if impact_time > 0.0:
		_draw_impact(host.impact_type(), r, face, impact_time)
	# ---- 阶段特效（得意闪光 / 问号 / 生气 / 冒烟 / 汗 / 星星）
	_draw_stage_effects(stage, r, head)


func _draw_impact(kind: String, r: float, face: Vector2, time_left: float) -> void:
	var t := clampf(time_left / 0.40, 0.0, 1.0)
	var alpha := 0.85 * t
	match kind:
		"pan":
			var at := face + Vector2(0.0, r * 0.52)
			for i in 6:
				var angle := TAU * float(i) / 6.0
				draw_line(at + Vector2(cos(angle), sin(angle)) * r * 0.30,
					at + Vector2(cos(angle), sin(angle)) * r * (0.44 + 0.20 * (1.0 - t)),
					Color("ff7d6b", alpha), maxf(r * 0.055, 2.4), true)
		"pressure":
			_star(face + Vector2(-r * 0.30, -r * 1.10), r * 0.36, Color("ffe08a", alpha))
			_star(face + Vector2(r * 0.26, -r * 1.26), r * 0.26, Color("ffd166", alpha))
		"broken":
			for i in 6:
				var angle := TAU * float(i) / 6.0 + host.tick_time()
				draw_circle(face + Vector2(cos(angle), sin(angle)) * r * (0.72 + 0.36 * (1.0 - t)),
					maxf(r * 0.08, 2.2) * t, Color(0.22, 0.20, 0.18, alpha))
		"iron":
			_star(face + Vector2(0.0, -r * 0.80), r * 0.40, Color("ffd166", alpha))
			_star(face + Vector2(-r * 0.42, -r * 0.64), r * 0.22, Color(1.0, 1.0, 1.0, alpha))
		_:
			for i in 4:
				var angle := -PI * 0.5 + (float(i) - 1.5) * 0.5
				draw_line(face + Vector2(cos(angle), sin(angle)) * r * 0.94,
					face + Vector2(cos(angle), sin(angle)) * r * (1.10 + 0.14 * (1.0 - t)),
					Color("ffe08a", alpha), maxf(r * 0.05, 2.2), true)


func _draw_stage_effects(stage: int, r: float, head: Vector2) -> void:
	var t := host.tick_time()
	match stage:
		0:
			for i in 2:
				var p := head + Vector2(-r * 1.20 + float(i) * r * 2.40, -r * 0.70)
				var s := r * 0.17 * (0.7 + 0.3 * sin(t * 3.0 + float(i)))
				draw_line(p - Vector2(s, 0.0), p + Vector2(s, 0.0), Palette.ACCENT,
					maxf(r * 0.03, 1.6), true)
				draw_line(p - Vector2(0.0, s), p + Vector2(0.0, s), Palette.ACCENT,
					maxf(r * 0.03, 1.6), true)
		1:
			var q := head + Vector2(r * 0.96, -r * 1.05)
			var size := r * 0.32
			draw_line(q + Vector2(-size * 0.36, -size * 0.56), q + Vector2(size * 0.36, -size * 0.10),
				Palette.INFO, maxf(size * 0.16, 2.4), true)
			draw_line(q + Vector2(size * 0.36, -size * 0.10), q, Palette.INFO,
				maxf(size * 0.16, 2.4), true)
			draw_circle(q + Vector2(0.0, size * 0.42), size * 0.12, Palette.INFO)
		2:
			draw_line(head + Vector2(r * 0.60, -r * 1.30), head + Vector2(r * 0.86, -r * 1.02),
				Palette.DANGER, maxf(r * 0.03, 1.6), true)
		3, 4:
			var mark := head + Vector2(r * 0.86, -r * 1.28)
			for i in 2:
				var a := mark + Vector2(-r * 0.12, -r * 0.12 + float(i) * r * 0.12)
				draw_line(a, a + Vector2(r * 0.24, r * 0.12), Palette.DANGER, maxf(r * 0.035, 2.0), true)
			_smoke(head + Vector2(-r * 1.10, -r * 0.60), r)
			_smoke(head + Vector2(r * 1.10, -r * 0.60), r)
		5:
			for i in 4:
				var k := fmod(t * 1.6 + float(i) * 0.25, 1.0)
				var p := head + Vector2(-r * 0.92 + float(i) * r * 0.62, -r * 0.40 + k * r * 0.72)
				draw_colored_polygon(PackedVector2Array([
					p, p + Vector2(r * 0.10, r * 0.17), p + Vector2(-r * 0.10, r * 0.17),
				]), Color(0.55, 0.80, 1.0, 0.85 * (1.0 - k)))
		6:
			for i in 3:
				var angle := t * 2.6 + TAU * float(i) / 3.0
				var p := head + Vector2(cos(angle) * r * 1.10, -r * 0.90 + sin(angle) * r * 0.32)
				_star(p, r * 0.18, Palette.ACCENT)


func _smoke(origin: Vector2, r: float) -> void:
	for i in 3:
		var t := fmod(host.tick_time() * 1.1 + float(i) * 0.33, 1.0)
		draw_circle(origin + Vector2(sin(t * 6.0) * r * 0.10, -t * r * 0.55),
			r * (0.10 + 0.10 * t), Color(0.78, 0.81, 0.85, 0.45 * (1.0 - t)))


func _star(center: Vector2, size: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var angle := -PI * 0.5 + TAU * float(i) / 10.0
		var radius := size if i % 2 == 0 else size * 0.45
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)


func _circle(pos: Vector2, radius: float, fill: Color, width: float) -> void:
	draw_circle(pos, radius, fill)
	if width > 0.0:
		draw_arc(pos, radius - width * 0.5, 0.0, TAU, 32, Color(0.11, 0.10, 0.14), width, true)


func _draw_stuck_pot(center: Vector2, size: float, pot: PotType) -> void:
	draw_circle(center, size, pot.tint)
	draw_circle(center, size * 0.72, pot.tint_dark)
	draw_arc(center, size, 0.0, TAU, 24, pot.tint_dark, 3.0)
	for side in [-1.0, 1.0]:
		draw_arc(center + Vector2(side * size * 1.0, 0.0), size * 0.30,
			PI * 0.5 if side > 0.0 else -PI * 0.5,
			PI * 1.5 if side > 0.0 else PI * 0.5, 10, pot.tint_dark, 3.5)
	draw_circle(center + Vector2(0.0, -size * 0.95), size * 0.18, Palette.ACCENT)
