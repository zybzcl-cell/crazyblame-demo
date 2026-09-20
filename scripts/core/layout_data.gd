class_name LayoutData
## 竖屏构图的空间预算 —— 整个游戏唯一的「谁占哪一块」来源。
##
## 设计目标（720×1280 为基准，所有数值都是相对比例，屏幕比例不同也能自适应）：
##
##   0.030 ┃ 顶部 HUD：返回 / 倒计时 / 连击 / 阶段
##   0.096 ┃ 老板精神状态条 + 阶段名 + 数值
##   0.140 ┃ 老板台词
##   0.164 ┃ ┌ 办公室空间（墙）
##         ┃ │   窗户（左）、本月业绩白板（右）都挂在墙上
##         ┃ │   老板坐在办公桌后面，桌子下沿正好落在地板上
##   0.500 ┃ └ 墙 / 地板分界
##   0.510 ┃ 甩锅操作区（锅出现 / 飘移 / 抓取 / 拖动 / 甩回）
##   0.918 ┃
##   0.926 ┃ 底部辅助信息：总分 / 命中 / 失误 / 命中率
##
## 三条硬约束（测试里会逐条断言，改坏了会立刻报错）：
##   1. 老板整体（从头顶到桌沿）必须完整落在办公室空间里，不能压到顶部 HUD；
##   2. 办公桌下沿必须贴住地板线（看起来是「坐在桌后」，而不是悬浮在墙上）；
##   3. 甩锅操作区必须完全在桌沿下方，且高度不低于屏高的 40%。

# ---- 顶部 HUD
const SAFE_TOP := 0.026
const HUD_TOP := 0.030
const HUD_BOTTOM := 0.092
const BOSS_BAR_TOP := 0.096
const BOSS_BAR_BOTTOM := 0.138
const BOSS_LINE_TOP := 0.140
const BOSS_LINE_BOTTOM := 0.162

# ---- 办公室
const OFFICE_TOP := 0.164
const FLOOR_Y := 0.500

# ---- 甩锅操作区
const FIELD_TOP := 0.510
const FIELD_BOTTOM := 0.918

# ---- 底部辅助信息
const BOTTOM_TOP := 0.926
const BOTTOM_BOTTOM := 0.992

# ---- 宽度
## 内容列宽 / 屏幕高：竖屏 720×1280 时正好等于屏宽；桌面宽窗口会变成居中的一条竖屏游戏区
const CONTENT_RATIO := 0.625
## 场地左右留白（相对内容列宽）
const FIELD_MARGIN_X := 0.05
## 老板基准半径 = min(屏幕宽 × 0.152, 屏幕高 × 0.098)，并保证不小于屏高的 6.2%
const BOSS_RADIUS_W := 0.152
const BOSS_RADIUS_H_MAX := 0.098
const BOSS_RADIUS_H_MIN := 0.062
## 受击判定圈 = 老板半径 × 这个系数（跟着老板大小走，而不是跟着屏幕走）
const BOSS_HIT_RADIUS_FACTOR := 1.30
## 桌面上方至少要留给墙面挂件（窗户 / 白板）的高度比例
const DECOR_MIN_RATIO := 0.075


## 算出这一屏的所有区域
static func compute(size: Vector2) -> Dictionary:
	var w := size.x
	var h := size.y

	# 内容列：手机竖屏是整屏，桌面宽窗口是居中的一条竖屏游戏区
	var content_w := minf(w, h * CONTENT_RATIO)
	var content_x := (w - content_w) * 0.5

	var hud := Rect2(content_x, h * HUD_TOP, content_w, h * (HUD_BOTTOM - HUD_TOP))
	var boss_bar := Rect2(content_x, h * BOSS_BAR_TOP, content_w, h * (BOSS_BAR_BOTTOM - BOSS_BAR_TOP))
	var boss_line := Rect2(content_x, h * BOSS_LINE_TOP, content_w,
		h * (BOSS_LINE_BOTTOM - BOSS_LINE_TOP))
	var floor_y := h * FLOOR_Y
	var office := Rect2(0.0, h * OFFICE_TOP, w, floor_y - h * OFFICE_TOP)
	var field := Rect2(
		content_x + content_w * FIELD_MARGIN_X,
		h * FIELD_TOP,
		content_w * (1.0 - FIELD_MARGIN_X * 2.0),
		h * (FIELD_BOTTOM - FIELD_TOP))
	var bottom := Rect2(content_x, h * BOTTOM_TOP, content_w, h * (BOTTOM_BOTTOM - BOTTOM_TOP))

	# 老板：先按屏幕宽度定半径，再保证「桌沿落在地板上、头顶不撞 HUD、桌面上方留得下挂件」
	var radius := clampf(w * BOSS_RADIUS_W, h * BOSS_RADIUS_H_MIN, h * BOSS_RADIUS_H_MAX)
	var desk_bottom := floor_y + h * 0.004
	var head_min := h * OFFICE_TOP + h * 0.014
	var radius_max := (desk_bottom - h * OFFICE_TOP - h * DECOR_MIN_RATIO - h * 0.014) / 2.71
	radius = minf(radius, maxf(radius_max, h * 0.045))
	var center_y := desk_bottom - radius * 1.85
	if center_y - radius * 1.45 < head_min:
		radius = maxf((desk_bottom - head_min) / 3.30, h * 0.045)
		center_y = desk_bottom - radius * 1.85

	# 墙面挂件：贴在墙上（跟着墙带高度走），并保证落在桌面上沿之上
	var wall_top := h * OFFICE_TOP
	var wall_h := maxf(floor_y - wall_top, 1.0)
	var desk_top := center_y - radius * 0.86
	var fixture_top := wall_top + h * 0.010
	var fixture_h := maxf(desk_top - h * 0.012 - fixture_top, h * 0.045)
	# 本月业绩白板要挂在老板「头之外」的位置，不能压住人物
	var head_edge := w * 0.5 + radius * 0.80 + content_w * 0.02
	var board_right := content_x + content_w * 0.95
	var board_left := maxf(content_x + content_w * 0.60, head_edge)
	var board_w := clampf(board_right - board_left, content_w * 0.12, content_w * 0.335)
	var window_rect := Rect2(content_x + content_w * 0.045, fixture_top, content_w * 0.27, fixture_h)
	var board_rect := Rect2(board_left, fixture_top - h * 0.004, board_w, fixture_h)

	return {
		"size": size,
		"content_rect": Rect2(content_x, 0.0, content_w, h),
		"hud": hud,
		"boss_bar": boss_bar,
		"boss_line": boss_line,
		"office": office,
		"floor_y": floor_y,
		"field": field,
		"bottom": bottom,
		"boss_center": Vector2(w * 0.5, center_y),
		"boss_radius": radius,
		"boss_desk_bottom": desk_bottom,
		"boss_desk_top": desk_top,
		"boss_head_top": center_y - radius * 1.45,
		"hit_radius": radius * BOSS_HIT_RADIUS_FACTOR,
		"window": window_rect,
		"board": board_rect,
		# 锅的大小跟着内容列宽缩放（窄屏不会让锅挤在一起）
		"pot_scale": clampf(content_w / 720.0, 0.78, 2.0),
		# 界面文字 / 伤害数字的缩放：小屏收紧、大屏放大，保证文字不会超出各自那一格
		"ui_scale": clampf(minf(w / 720.0, h / 1280.0), 0.58, 1.8),
	}


## 测试与文档用：把关键约束写成一个列表，便于逐条断言
static func invariants(layout: Dictionary) -> Array:
	var field: Rect2 = layout["field"]
	var office: Rect2 = layout["office"]
	var boss_bar: Rect2 = layout["boss_bar"]
	var size: Vector2 = layout["size"]
	return [
		{
			"name": "老板整体落在办公室空间内（头顶不压 HUD、桌沿不出界）",
			"ok": float(layout["boss_head_top"]) >= boss_bar.end.y
			and float(layout["boss_desk_bottom"]) <= floorf(office.end.y) + size.y * 0.012,
		},
		{
			"name": "办公桌下沿贴着地板线（坐在桌后而不是浮在墙上）",
			"ok": absf(float(layout["boss_desk_bottom"]) - float(layout["floor_y"]))
				<= size.y * 0.02,
		},
		{
			"name": "甩锅操作区完全在桌沿下方，且高度不低于屏高的 40%",
			"ok": field.position.y > float(layout["boss_desk_bottom"])
			and field.size.y >= size.y * 0.40,
		},
		{
			"name": "甩锅操作区不超出屏幕",
			"ok": field.position.x >= 0.0 and field.end.x <= size.x + 0.5
			and field.end.y <= size.y,
		},
		{
			"name": "窗户与白板挂在墙上、且在老板头顶上方（不会被人物压住）",
			"ok": (layout["window"] as Rect2).end.y <= float(layout["boss_desk_top"]) + 1.0
			and (layout["board"] as Rect2).end.y <= float(layout["boss_desk_top"]) + 1.0
			and (layout["window"] as Rect2).position.y >= office.position.y - 1.0,
		},
		{
			"name": "白板与老板的头在横向上不重叠",
			"ok": (layout["board"] as Rect2).position.x
				>= layout["boss_center"].x + float(layout["boss_radius"]) * 0.74,
		},
		{
			"name": "顶部 HUD 与甩锅操作区不重叠",
			"ok": boss_bar.end.y < field.position.y,
		},
	]
