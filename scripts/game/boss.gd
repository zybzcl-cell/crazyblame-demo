class_name BlameBoss
extends Node2D
## Q 版「很欠的老板」：整个游戏的情绪主角。
##
## ---- 造型（全部程序化绘制，没有任何外部美术资源）
## 大头 + 圆润肥胖的身体 + 滚圆的大肚子 + 短粗四肢；深色商务西装 / 白衬衫 / 红领带 /
## 黑皮带（肚腩下面那条），圆脸 + 大而有神的眼睛 + 又厚又大的黑框眼镜 + 圆圆的大鼻子 +
## 丰满的脸颊与一点点双下巴；半秃（只剩两侧与耳后一坨黑发 + 几缕夸张翘发）。
## 一眼看过去就是「这个老板一看就很欠，锅就该甩回他脸上」，而不是普通中年男。
##
## ---- 七个阶段（名字与血量比例沿用原来的，保证不破坏既有玩法）
##   0 得意   挑眉 + 咧嘴坏笑 + 竖大拇指
##   1 疑惑   眼睛瞪大 + 嘴巴张成小圆（惊讶）+ 手托下巴 + 一个问号
##   2 不爽   皱眉撇嘴 + 抱手
##   3 愤怒   眉毛压低 + 咬牙 + 青筋 + 耳朵冒烟
##   4 暴怒   张嘴大吼 + 双拳举起 + 头发炸开 + 领带甩飞
##   5 疲惫   眼神无力 + 松垮 + 委屈的八字眉 + 满头汗
##   6 崩溃   仰面瘫倒、双脚翘起露出黑皮鞋、眼镜歪掉、头发乱成鸡窝、头顶转星星
##
## ---- 甩锅动作（本次重点）
## 锅不再是「凭空出现在屏幕边缘」：`begin_throw()` 让老板先看向目标方向、抬手蓄力
## （`throw_hand_position()` 就是锅被托在手里的位置），到 `THROW_WINDUP` 那一刻手向前甩、
## 锅从手部脱手飞出（`throw_release_point()`），最后 `THROW_TOTAL` 回到正常姿态。
## 蓄力期间还会画一条指向目标方向的虚线箭头 —— 玩家能靠老板的动作预判锅会飞向哪边。

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

# ---- 甩锅动作时间轴（秒）
## 蓄力：看向目标 → 抬手 → 后仰。锅这一段一直被托在手里。
const THROW_WINDUP := 0.34
## 甩出：手臂快速前甩 + 残影，锅已经脱手飞走。
const THROW_FOLLOW := 0.30
const THROW_TOTAL := THROW_WINDUP + THROW_FOLLOW

# ---- 身体各部分的「r 单位」坐标（1.0 = body_radius），绘制与判定共用同一份数据
const HEAD_CENTER := Vector2(0.0, -0.58)
const HEAD_RADIUS := 0.86
const BELLY_CENTER := Vector2(0.0, 0.54)
const BELLY_RADIUS := 1.02

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
var _hit_kind: String = ""
var _stage_flash: float = 0.0
var _stuck_time: float = 0.0
var _stuck_pot: PotType = null
var _speech: String = ""
var _speech_time: float = 0.0
var _rng := RandomNumberGenerator.new()
var _hit_radius: float = 160.0
## 地板线（全局坐标）。用来给办公桌 / 椅子画一层接触阴影。
var _floor_y: float = 0.0
## 当前这一帧的整体变换（抖动 / 倾斜），局部绘制改过变换之后要用 _restore_transform() 还原
var _t_offset := Vector2.ZERO
var _t_lean := 0.0
var _bob := 0.0
var _recoil := 0.0

## ---- 受击「战损」状态：本局内累积，让老板越打越狼狈（但始终是滑稽，不是写实受伤）
var _glasses_crack := false      ## 铁锅砸出来的眼镜裂纹（保留）
var _nose_red := false           ## 平底锅打红的鼻子（保留）
var _head_bump := false          ## 高压锅砸出来的头顶大包（保留）
var _face_soot := false          ## 破锅糊上的锅底黑印（保留）
var _mess := 0.0                 ## 头发 / 衣服的凌乱程度（0~1，累积）
var _glasses_wobble := 0.0       ## 眼镜被砸得晃动（短暂）
var _nose_hit := 0.0             ## 卡通鼻血刚出来那一下（短暂）
var _bump_pop := 0.0             ## 头上的包刚肿起来那一下（短暂）
var _impact_type := ""           ## 这一次受击的锅型（画不同的冲击符号）
var _impact_time := 0.0

## ---- 甩锅动作状态
var _throw_time := -1.0          ## < 0 = 没在甩
var _throw_lane := ""
var _throw_dir := Vector2.DOWN
var _throw_side := 1.0
var _throw_vertical := 0.0       ## -1 上 / 0 中 / +1 下（决定抬手高度）
var _throw_count := 0


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


## ---- 受击战损状态（测试与「越来越狼狈」的演出都读它）
func has_glasses_crack() -> bool:
	return _glasses_crack


func has_red_nose() -> bool:
	return _nose_red


func has_head_bump() -> bool:
	return _head_bump


func has_face_soot() -> bool:
	return _face_soot


## 头发 / 衣服的凌乱程度（0 = 一丝不苟，1 = 乱成鸡窝）
func mess_level() -> float:
	return _mess


## 一次性拿到全部战损状态（方便测试比对五种锅的差异）
func damage_state() -> Dictionary:
	return {
		"glasses_crack": _glasses_crack,
		"nose_red": _nose_red,
		"head_bump": _head_bump,
		"face_soot": _face_soot,
		"mess": _mess,
	}


func is_battered() -> bool:
	return _glasses_crack or _nose_red or _head_bump or _face_soot


## 这个世界坐标点是不是落在老板的身体里（头 / 肚子）。
## 甩锅时锅要被托在**手**上，必须落在身体外面 —— 测试用它守住这条约束。
func contains_body_point(world_point: Vector2) -> bool:
	var local := to_local_point(world_point)
	if local.distance_to(HEAD_CENTER) < HEAD_RADIUS:
		return true
	if local.distance_to(BELLY_CENTER) < BELLY_RADIUS:
		return true
	return false


## 世界坐标 → 老板的「r 单位」本地坐标（含抖动 / 倾斜的还原）
func to_local_point(world_point: Vector2) -> Vector2:
	var r := maxf(body_radius(), 1.0)
	return ((world_point - global_position - _t_offset).rotated(-_t_lean)) / r


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
	var pot_id := "" if pot == null else pot.id
	_hit_flash = 0.24
	_hit_face = 0.38
	_hit_kind = pot_id
	shake = clampf(shake + 0.45 * strength, 0.0, 1.4)
	tilt = -0.10 * strength if not is_ko() else 0.0
	wobble = clampf(wobble + 0.5 * strength, 0.0, 1.5)
	# 身体后仰：被砸得往后一弹（纯位移，不改变任何数值）
	_recoil = clampf(_recoil + 0.45 * strength, 0.0, 1.2)
	_impact_type = pot_id
	_impact_time = 0.40
	# 眼镜每次挨锅都会晃一下；头发 / 衣服随着挨打越来越乱
	_glasses_wobble = maxf(_glasses_wobble, 0.34 + 0.22 * strength)
	_mess = clampf(_mess + 0.05 * strength + (0.22 if pot_id == "broken" else 0.0), 0.0, 1.0)
	# 不同类型的锅留下不同的「战损」
	match pot_id:
		"iron":
			_glasses_crack = true          # 铁锅：眼镜直接裂开
		"pan":
			_nose_red = true               # 平底锅：鼻子打红 + 卡通鼻血
			_nose_hit = 0.55
		"pressure":
			_head_bump = true              # 高压锅：头顶肿一个大包
			_bump_pop = 0.55
		"broken":
			_face_soot = true              # 破锅：脸上一块锅底黑印
		_:
			pass
	if pot != null and strength >= 0.8:
		# 重锅会「扣在头上」一小会儿
		_stuck_pot = pot
		_stuck_time = 0.75 if pot.id == "iron" else 0.55
	queue_redraw()


## 彻底崩溃：仰面瘫倒，双脚翘起
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
	_hit_kind = ""
	_stage_flash = 0.0
	_stuck_time = 0.0
	_stuck_pot = null
	_speech = ""
	_speech_time = 0.0
	_time = 0.0
	_recoil = 0.0
	_glasses_crack = false
	_nose_red = false
	_head_bump = false
	_face_soot = false
	_mess = 0.0
	_glasses_wobble = 0.0
	_nose_hit = 0.0
	_bump_pop = 0.0
	_impact_type = ""
	_impact_time = 0.0
	_throw_time = -1.0
	_throw_lane = ""
	_throw_count = 0
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
	_recoil = 0.0
	_glasses_crack = false
	_nose_red = false
	_head_bump = false
	_face_soot = false
	_mess = 0.0
	_glasses_wobble = 0.0
	_nose_hit = 0.0
	_bump_pop = 0.0
	_impact_type = ""
	_impact_time = 0.0
	_throw_time = -1.0
	queue_redraw()


# ---------------------------------------------------------------- 甩锅动作

## 开始一次甩锅：lane 决定往哪边、哪个高度甩，direction 是「锅飞出去的方向」（世界坐标）。
## 整个动作 = 看向目标 → 抬手蓄力 → 手臂前甩；锅在这段时间被托在手上。
func begin_throw(lane: String, direction: Vector2, vertical: float) -> void:
	_throw_lane = lane
	_throw_dir = direction.normalized() if direction.length() > 0.001 else Vector2.DOWN
	_throw_side = -1.0 if lane.begins_with("left") else 1.0
	_throw_vertical = clampf(vertical, -1.0, 1.0)
	_throw_time = 0.0
	_throw_count += 1
	queue_redraw()


func is_throwing() -> bool:
	return _throw_time >= 0.0


## 还在「蓄力」阶段（锅还在手上）吗
func is_winding_up() -> bool:
	return _throw_time >= 0.0 and _throw_time < THROW_WINDUP


## 蓄力进度 0~1（给外部的预判提示 / 测试用）
func windup_ratio() -> float:
	if _throw_time < 0.0:
		return 0.0
	return clampf(_throw_time / THROW_WINDUP, 0.0, 1.0)


func throw_lane() -> String:
	return _throw_lane


func throw_side() -> float:
	return _throw_side


func throw_count() -> int:
	return _throw_count


## 锅「脱手」的那个时刻（秒）。游戏主控用同一条时间轴，所以脱手永远发生在手臂前甩那一帧。
func throw_release_time() -> float:
	return THROW_WINDUP


func throw_total_time() -> float:
	return THROW_TOTAL


## 手在时间轴 t 的位置（本地 r 单位）：t=0 是抬手起点，t=THROW_WINDUP 是脱手点
func _throw_hand_units(t: float) -> Vector2:
	return _hand_units(_throw_side, _throw_vertical, t)


## 手在时间轴 t 的位置（纯函数：只由「哪一侧 / 哪个高度」和时间决定）
## 起点与终点都在身体轮廓之外，保证锅被托在手里时不会陷进老板的身体里。
func _hand_units(side: float, vertical: float, t: float) -> Vector2:
	var start := Vector2(side * 0.95, 0.10)
	var raised := Vector2(side * (1.08 + 0.06 * absf(vertical)),
		-0.30 - 0.36 * (1.0 - vertical) + 0.36 * vertical)
	var follow := Vector2(side * 1.24, raised.y + 0.52)
	if t <= THROW_WINDUP:
		var u := clampf(t / THROW_WINDUP, 0.0, 1.0)
		return start.lerp(raised, _ease_out(u))
	var v := clampf((t - THROW_WINDUP) / maxf(THROW_FOLLOW, 0.001), 0.0, 1.0)
	return raised.lerp(follow, _ease_in(v))


## 锅被托在手里的位置（世界坐标）—— 老板的手
func throw_hand_position() -> Vector2:
	return _units_to_world(_throw_hand_units(maxf(_throw_time, 0.0)))


## 锅脱手的位置（世界坐标）—— 就是蓄力结束时手的那个点
func throw_release_point() -> Vector2:
	return _units_to_world(_throw_hand_units(THROW_WINDUP))


## 某个方向在脱手瞬间的手部位置（游戏主控在生成锅时用它算飞行方向）
func release_point_for(side: float, vertical: float) -> Vector2:
	return _units_to_world(_hand_units(side, clampf(vertical, -1.0, 1.0), THROW_WINDUP))


func _units_to_world(units: Vector2) -> Vector2:
	return global_position + _t_offset + (units * body_radius()).rotated(_t_lean)


func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 2.0)


func _ease_in(t: float) -> float:
	return t * t


# ---------------------------------------------------------------- 每帧推进

func tick(delta: float) -> void:
	_time += delta
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	_hit_face = maxf(_hit_face - delta, 0.0)
	_stage_flash = maxf(_stage_flash - delta, 0.0)
	_stuck_time = maxf(_stuck_time - delta, 0.0)
	_speech_time = maxf(_speech_time - delta, 0.0)
	_glasses_wobble = maxf(_glasses_wobble - delta, 0.0)
	_nose_hit = maxf(_nose_hit - delta, 0.0)
	_bump_pop = maxf(_bump_pop - delta, 0.0)
	_impact_time = maxf(_impact_time - delta, 0.0)
	_recoil = maxf(_recoil - delta * 2.6, 0.0)
	if _speech_time <= 0.0:
		_speech = ""
	if _throw_time >= 0.0:
		_throw_time += delta
		if _throw_time >= THROW_TOTAL:
			_throw_time = -1.0
	var recover := 3.4 if not is_ko() else 6.0
	shake = maxf(shake - delta * 1.9, 0.0)
	tilt = move_toward(tilt, 0.0, delta * recover)
	wobble = maxf(wobble - delta * 1.4, 0.0)
	if _stuck_time <= 0.0:
		_stuck_pot = null
	_update_pose()
	queue_redraw()


## 每帧先把「整体变换」算好：绘制、以及外部读取手部位置都用它，保证手和锅不会差一帧
func _update_pose() -> void:
	var r := body_radius()
	var idle_speed := 1.6 + 0.35 * float(_stage)
	_bob = sin(_time * idle_speed) * (2.5 + 1.2 * float(_stage)) * scale_factor
	var jitter := 0.0
	if _stage >= 3:
		jitter = _rng.randf_range(-1.5, 1.5) * (_stage - 2)
	# 疲惫 / 崩溃时整个人往下塌一点
	if _stage >= 5:
		_bob += r * 0.05
	_t_offset = Vector2(sin(_time * 46.0) * shake * 13.0 * scale_factor, _bob + jitter)
	# 受击后仰：整体往上 / 往后弹一下
	if _recoil > 0.0:
		_t_offset += Vector2(0.0, -_recoil * r * 0.09)
	_t_lean = tilt + _stage_lean()


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	var r := body_radius()
	_restore_transform()
	_draw_floor_shadow(r)
	if is_ko():
		_draw_ko_pose(r)
	else:
		_draw_chair(r)
		_draw_body(r)
		_draw_arms_stage(r, false)
		_draw_head(r)
		_draw_desk(r)
		_draw_arms_stage(r, true)
		_draw_throw_arm(r)
		_draw_throw_cue(r)
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
			return 0.15
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


func _suit_color() -> Color:
	var suit := Palette.BOSS_SUIT
	if _stage >= 4:
		suit = suit.lerp(Palette.BOSS_TIE, 0.10)
	if _stage >= 6:
		suit = suit.lerp(Palette.BOSS_SUIT_DARK, 0.30)
	return suit


func suit_sleeve() -> Color:
	return Palette.BOSS_SUIT_DARK


func _draw_chair(r: float) -> void:
	# 办公椅：靠背在身体后面（比肚子窄，不然体型读不出来）
	draw_rect(Rect2(Vector2(-r * 0.90, -r * 0.52), Vector2(r * 1.80, r * 0.95)),
		Color(0.16, 0.18, 0.23))
	draw_rect(Rect2(Vector2(-r * 0.80, -r * 0.47), Vector2(r * 1.60, r * 0.86)),
		Color(0.24, 0.26, 0.32))


## 身体：短粗圆润 + 滚圆的大肚子 + 西装 / 衬衫 / 领带 / 黑皮带
func _draw_body(r: float) -> void:
	var suit := _suit_color()
	var skin := _skin_color()
	# 躯干：肩膀窄，往下被大肚子撑开（水滴形，一眼就是「吃出来的」）
	draw_colored_polygon(PackedVector2Array([
		Vector2(-r * 1.04, r * 1.16),
		Vector2(-r * 0.74, -r * 0.02),
		Vector2(r * 0.74, -r * 0.02),
		Vector2(r * 1.04, r * 1.16),
	]), suit)
	# 滚圆的大肚子
	var belly := BELLY_CENTER * r
	draw_circle(belly, r * BELLY_RADIUS, suit)
	draw_arc(belly, r * BELLY_RADIUS, PI * 0.03, PI * 0.97, 28, Palette.BOSS_SUIT_DARK, 2.6)
	# 衬衫：从领口一路绷到肚子上
	draw_colored_polygon(PackedVector2Array([
		Vector2(-r * 0.36, -r * 0.02),
		Vector2(r * 0.36, -r * 0.02),
		Vector2(r * 0.62, r * 0.40),
		Vector2(r * 0.48, r * 0.74),
		Vector2(-r * 0.48, r * 0.74),
		Vector2(-r * 0.62, r * 0.40),
	]), Palette.BOSS_SHIRT)
	# 衬衫褶皱：越挨打越皱
	if _mess > 0.2:
		var wrinkles := 2 + int(round(_mess * 3.0))
		for i in wrinkles:
			var wy := r * (0.26 + 0.14 * float(i))
			draw_line(Vector2(-r * 0.40, wy), Vector2(r * 0.40, wy + r * 0.04),
				Palette.BOSS_SHIRT.darkened(0.18), 1.8, true)
	# 领口
	draw_colored_polygon(PackedVector2Array([
		Vector2(-r * 0.32, -r * 0.02), Vector2(0.0, r * 0.26), Vector2(r * 0.32, -r * 0.02),
	]), Palette.BOSS_SHIRT.darkened(0.10))
	# 领带（越往后越歪，甩锅时还会飞起来）
	var tie_angle := 0.10 * float(mini(_stage, 5)) + _mess * 0.30
	if _stage >= 6:
		tie_angle = 1.05
	if _throw_time >= THROW_WINDUP:
		tie_angle += _throw_side * 0.55
	draw_set_transform(Vector2(0.0, r * 0.14), tie_angle, Vector2.ONE)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-r * 0.11, 0.0), Vector2(r * 0.11, 0.0),
		Vector2(r * 0.08, r * 0.16), Vector2(-r * 0.08, r * 0.16),
	]), Palette.BOSS_TIE.darkened(0.18))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-r * 0.14, r * 0.16), Vector2(r * 0.14, r * 0.16), Vector2(0.0, r * 0.66),
	]), Palette.BOSS_TIE)
	_restore_transform()
	# 西装翻领
	for side in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([
			Vector2(side * r * 0.32, -r * 0.02),
			Vector2(side * r * 0.86, r * 0.14),
			Vector2(side * r * 0.62, r * 0.62),
		]), Palette.BOSS_SUIT_DARK)
	# 黑皮带 + 金色带扣（肚腩下面那一圈，正好压在桌沿上方，看得见）
	draw_colored_polygon(PackedVector2Array([
		Vector2(-r * 0.94, r * 0.70), Vector2(r * 0.94, r * 0.70),
		Vector2(r * 0.92, r * 0.82), Vector2(-r * 0.92, r * 0.82),
	]), Color(0.10, 0.10, 0.12))
	draw_rect(Rect2(Vector2(-r * 0.11, r * 0.70), Vector2(r * 0.22, r * 0.12)),
		Palette.ACCENT_DEEP)
	# 西装口袋巾（一点点精致感，衬托他有多欠）
	draw_colored_polygon(PackedVector2Array([
		Vector2(-r * 0.78, r * 0.24), Vector2(-r * 0.62, r * 0.22),
		Vector2(-r * 0.66, r * 0.34),
	]), Palette.BOSS_SHIRT)


## 阶段化的手臂姿势（front=false 画在身体后、head 之前；front=true 画在桌面之后）
func _draw_arms_stage(r: float, front: bool) -> void:
	var skin := _skin_color()
	var sleeve := maxf(r * 0.30, 4.0)
	if not front:
		match _stage:
			2, 3:
				# 抱手（把大肚子抱在怀里）
				if _arm_visible(-1.0):
					draw_line(Vector2(-r * 0.92, r * 0.30), Vector2(r * 0.30, r * 0.16),
						suit_sleeve(), sleeve, true)
				if _arm_visible(1.0):
					draw_line(Vector2(r * 0.92, r * 0.26), Vector2(-r * 0.26, r * 0.34),
						suit_sleeve(), sleeve, true)
			1:
				# 一只手托着胖下巴
				if _arm_visible(1.0):
					draw_line(Vector2(r * 0.86, r * 0.50), Vector2(r * 0.52, r * 0.10),
						suit_sleeve(), sleeve, true)
					draw_circle(Vector2(r * 0.50, r * 0.16), r * 0.23, skin)
			4:
				# 双拳举起（大吼）
				for side in [-1.0, 1.0]:
					if not _arm_visible(side):
						continue
					draw_line(Vector2(side * r * 0.80, r * 0.30),
						Vector2(side * r * 1.18, -r * 0.42), suit_sleeve(), sleeve, true)
					draw_circle(Vector2(side * r * 1.22, -r * 0.50), r * 0.25, skin)
			5:
				# 双手搭在肚子上（没力气）
				for side in [-1.0, 1.0]:
					if not _arm_visible(side):
						continue
					draw_line(Vector2(side * r * 0.90, r * 0.40),
						Vector2(side * r * 0.62, r * 0.62), suit_sleeve(), sleeve, true)
		return
	# ---- 前面的部分
	match _stage:
		0:
			# 竖大拇指（很欠的得意）
			if _arm_visible(1.0):
				draw_line(Vector2(r * 0.76, r * 0.34), Vector2(r * 0.52, -r * 0.02),
					suit_sleeve(), sleeve, true)
				_draw_thumbs_up(Vector2(r * 0.50, -r * 0.10), r * 0.26, skin)
			if _arm_visible(-1.0):
				draw_circle(Vector2(-r * 0.66, r * 0.34), r * 0.22, skin)
		1:
			if _arm_visible(-1.0):
				draw_circle(Vector2(-r * 0.68, r * 0.36), r * 0.22, skin)
		2, 3:
			for side in [-1.0, 1.0]:
				if not _arm_visible(side):
					continue
				draw_circle(Vector2(side * r * 0.60, r * 0.22 if _stage == 2 else 0.30),
					r * 0.22, skin)
		4:
			pass
		5:
			for side in [-1.0, 1.0]:
				if not _arm_visible(side):
					continue
				draw_circle(Vector2(side * r * 0.62, r * 0.64), r * 0.22, skin)


## 甩锅的那只手要不要按阶段姿势画（正在甩的那只手由 _draw_throw_arm 单独画）
func _arm_visible(side: float) -> bool:
	if not is_throwing():
		return true
	return signf(side) != signf(_throw_side)


func _draw_thumbs_up(at: Vector2, size: float, skin: Color) -> void:
	draw_circle(at, size, skin)
	draw_circle(at + Vector2(0.0, -size * 0.95), size * 0.42, skin)
	draw_arc(at, size, PI * 0.15, PI * 0.85, 12, skin.darkened(0.22), 2.0)


## 甩锅的手臂：蓄力抬高 → 前甩，带残影与速度感
func _draw_throw_arm(r: float) -> void:
	if not is_throwing():
		return
	var skin := _skin_color()
	var sleeve := maxf(r * 0.30, 4.0)
	var hand := _throw_hand_units(_throw_time) * r
	var shoulder := Vector2(_throw_side * 0.78, 0.06) * r
	# 残影：把前几帧的手臂位置淡着画出来
	for i in 3:
		var back_t := _throw_time - 0.045 * float(i + 1)
		if back_t < 0.0:
			continue
		var ghost := _throw_hand_units(back_t) * r
		var alpha := 0.26 - 0.07 * float(i)
		draw_line(shoulder, ghost, Color(Palette.BOSS_SUIT_DARK, alpha), sleeve * 0.9, true)
		draw_circle(ghost, r * 0.20, Color(skin, alpha + 0.10))
	# 真正的手臂
	draw_line(shoulder, hand, suit_sleeve(), sleeve, true)
	draw_circle(shoulder, r * 0.20, _suit_color())
	draw_circle(hand, r * 0.24, skin)
	draw_arc(hand, r * 0.24, PI * 0.10, PI * 0.90, 12, skin.darkened(0.22), 2.0)
	# 前甩那一下再加一串运动线
	if _throw_time >= THROW_WINDUP:
		var v := clampf((_throw_time - THROW_WINDUP) / maxf(THROW_FOLLOW, 0.001), 0.0, 1.0)
		for i in 3:
			var off := Vector2(0.0, -r * (0.10 + 0.12 * float(i)))
			draw_line(hand + Vector2(-_throw_side * r * 0.10, 0.0) + off,
				hand + Vector2(_throw_side * r * (0.46 + 0.16 * float(i)), 0.0) + off,
				Color(Palette.ACCENT, 0.55 * (1.0 - v)), maxf(r * 0.035, 2.0), true)


## 蓄力期间的「甩锅方向」提示线：玩家靠它预判锅会飞向哪边
func _draw_throw_cue(r: float) -> void:
	if not is_winding_up():
		return
	var progress := windup_ratio()
	var from := _throw_hand_units(_throw_time) * r
	var dir := (_throw_dir.rotated(-_t_lean)).normalized()
	var length := r * (1.6 + 1.1 * progress)
	var color := Color(Palette.DANGER, 0.20 + 0.55 * progress)
	var dashes := 5
	for i in dashes:
		var t0 := float(i) / float(dashes)
		var t1 := t0 + 0.55 / float(dashes)
		if t1 > 1.0:
			t1 = 1.0
		draw_line(from + dir * (length * t0), from + dir * (length * t1), color,
			maxf(r * 0.045, 2.5), true)
	var tip := from + dir * length
	var side := dir.orthogonal()
	draw_line(tip, tip - dir * r * 0.24 + side * r * 0.16, color, maxf(r * 0.05, 2.5), true)
	draw_line(tip, tip - dir * r * 0.24 - side * r * 0.16, color, maxf(r * 0.05, 2.5), true)


# ---------------------------------------------------------------- 头部

func _draw_head(r: float) -> void:
	var skin := _skin_color()
	var center := HEAD_CENTER * r
	# 粗脖子
	draw_rect(Rect2(Vector2(-r * 0.32, center.y + r * 0.40), Vector2(r * 0.64, r * 0.46)),
		skin.darkened(0.14))
	# 双下巴（不过度，只留一点点）
	draw_circle(center + Vector2(0.0, r * 0.50), r * 0.42, skin.darkened(0.05))
	# 耳朵
	for side in [-1.0, 1.0]:
		draw_circle(center + Vector2(side * r * 0.84, r * 0.02), r * 0.17, skin.darkened(0.08))
	# 圆脸（Q 版大头）
	draw_circle(center, r * HEAD_RADIUS, skin)
	draw_arc(center, r * HEAD_RADIUS, 0.0, TAU, 44, skin.darkened(0.26), 2.0)
	# 丰满的脸颊
	for side in [-1.0, 1.0]:
		draw_circle(center + Vector2(side * r * 0.54, r * 0.06), r * 0.20,
			skin.lerp(Palette.BOSS_SKIN_HOT, 0.35))
	# 半秃的头顶：光溜溜 + 反光
	draw_circle(center + Vector2(0.0, -r * 0.30), r * 0.46, skin.lightened(0.10))
	draw_arc(center + Vector2(0.0, -r * 0.26), r * 0.44, PI * 1.18, PI * 1.82, 16,
		Color(1.0, 1.0, 1.0, 0.26), 3.0)
	# 高压锅砸出来的大包（本局一直留着）
	if _head_bump:
		_draw_head_bump(r, center)
	_draw_hair(r, center)
	_draw_glasses(r, center)
	_draw_face(r, center)
	# 破锅糊在脸上的锅底黑印（本局一直留着）
	if _face_soot:
		_draw_soot(r, center)


## 高压锅在头顶砸出来的卡通大包
func _draw_head_bump(r: float, center: Vector2) -> void:
	var pop := 1.0 + 0.24 * clampf(_bump_pop / 0.55, 0.0, 1.0)
	var at := center + Vector2(-r * 0.28, -r * 0.66)
	var radius := r * 0.25 * pop
	var color := _skin_color().lerp(Color("e0786a"), 0.42)
	draw_circle(at, radius, color)
	draw_arc(at, radius, 0.0, TAU, 22, color.darkened(0.22), 2.2)
	draw_arc(at, radius * 0.52, 0.0, TAU, 16, Color("cd5349", 0.55), 2.0)


## 破锅糊在脸上的锅底黑印 + 灰痕
func _draw_soot(r: float, center: Vector2) -> void:
	var soot := Color(0.15, 0.14, 0.14, 0.55)
	var spots := [
		[Vector2(-r * 0.38, r * 0.16), r * 0.15],
		[Vector2(r * 0.04, r * 0.32), r * 0.19],
		[Vector2(r * 0.46, r * 0.02), r * 0.12],
		[Vector2(-r * 0.12, -r * 0.02), r * 0.10],
	]
	for spot in spots:
		var p: Vector2 = center + (spot[0] as Vector2)
		draw_circle(p, float(spot[1]), soot)
		draw_circle(p + Vector2(r * 0.05, -r * 0.04), float(spot[1]) * 0.5,
			Color(0.22, 0.21, 0.20, 0.45))
	draw_line(center + Vector2(-r * 0.48, r * 0.06), center + Vector2(-r * 0.20, r * 0.24),
		Color(0.18, 0.17, 0.16, 0.45), maxf(r * 0.05, 2.0), true)


## 半秃发型：两侧留一坨黑发 + 几缕夸张翘发，头顶是光的
func _draw_hair(r: float, center: Vector2) -> void:
	var mess := clampf(maxf(_mess, float(_stage) / 5.0), 0.0, 1.0)
	var hair := Palette.BOSS_HAIR
	var band := maxf(r * 0.21, 3.0)
	# 耳后 / 两侧的「地方包围中央」
	for side in [-1.0, 1.0]:
		draw_circle(center + Vector2(side * r * 0.80, -r * 0.20), r * 0.24, hair)
		draw_circle(center + Vector2(side * r * 0.86, r * 0.02), r * 0.22, hair)
		draw_circle(center + Vector2(side * r * 0.82, r * 0.22), r * 0.18, hair)
	# 后脑勺那一圈（从头的两侧后面透出来）
	draw_arc(center + Vector2(0.0, r * 0.06), r * (HEAD_RADIUS - 0.04), PI * 0.62, PI * 1.06,
		12, hair, band)
	draw_arc(center + Vector2(0.0, r * 0.06), r * (HEAD_RADIUS - 0.04), -PI * 0.06, PI * 0.38,
		12, hair, band)
	# 几缕夸张的翘发（中年老板那种「地方支援中央」）
	var strands := 3 + int(round(mess * 3.0))
	for i in strands:
		var t := float(i) / float(maxi(strands - 1, 1))
		var x := -r * 0.40 + t * r * 0.80
		var lift := r * (0.30 + 0.16 * mess)
		var wob := sin(_time * 2.2 + float(i) * 1.7) * r * 0.04
		draw_line(center + Vector2(x, -r * 0.52),
			center + Vector2(x + r * 0.18 + wob, -r * 0.52 - lift), hair,
			maxf(r * 0.045, 2.0), true)


func _draw_glasses(r: float, center: Vector2) -> void:
	# 招牌：一副又大又厚的黑框眼镜
	var frame := Color(0.13, 0.14, 0.17)
	if _stage >= 4:
		frame = Color(0.07, 0.08, 0.10)
	var drop := 0.0
	var tilt_angle := 0.0
	match _stage:
		1:
			drop = r * 0.03
		2:
			drop = r * 0.06
		3:
			tilt_angle = 0.10
		4:
			tilt_angle = 0.26
			drop = r * 0.08
		5:
			tilt_angle = 0.44
			drop = r * 0.14
		6:
			tilt_angle = 0.85
			drop = r * 0.22
	# 挨锅时眼镜会晃
	var wobble_rot := 0.0
	var wobble_y := 0.0
	if _glasses_wobble > 0.0:
		var w := clampf(_glasses_wobble / 0.55, 0.0, 1.0)
		wobble_rot = sin(_time * 52.0) * 0.20 * w
		wobble_y = sin(_time * 40.0) * r * 0.07 * w
	var lens_r := r * 0.34
	draw_set_transform(center + Vector2(0.0, drop + wobble_y), tilt_angle + wobble_rot,
		Vector2.ONE)
	# 眼镜腿
	draw_line(Vector2(-r * 0.92, -r * 0.06), Vector2(-r * 0.42, -r * 0.10), frame,
		maxf(r * 0.055, 2.2), true)
	draw_line(Vector2(r * 0.92, -r * 0.06), Vector2(r * 0.42, -r * 0.10), frame,
		maxf(r * 0.055, 2.2), true)
	for side in [-1.0, 1.0]:
		var lens := Vector2(side * r * 0.44, -r * 0.08)
		draw_circle(lens, lens_r, Color(1.0, 1.0, 1.0, 0.16))
		draw_arc(lens, lens_r, 0.0, TAU, 28, frame, maxf(r * 0.075, 2.8))
	# 粗镜梁
	draw_line(Vector2(-r * 0.14, -r * 0.10), Vector2(r * 0.14, -r * 0.10), frame,
		maxf(r * 0.06, 2.4), true)
	# 疲惫之后眼镜滑到鼻尖 + 反光
	if _stage >= 5:
		draw_line(Vector2(-r * 0.62, -r * 0.26), Vector2(-r * 0.28, r * 0.02),
			Color(1.0, 1.0, 1.0, 0.42), maxf(r * 0.05, 2.4), true)
	if _glasses_crack:
		_draw_glasses_crack(r, lens_r)
	_restore_transform()


## 眼镜上的裂纹（画在眼镜自身的变换里，会跟着镜框一起晃 / 一起歪）
func _draw_glasses_crack(r: float, lens_r: float) -> void:
	var c := Vector2(r * 0.44, -r * 0.08)
	var crack := Color(0.04, 0.05, 0.07)
	var w := maxf(r * 0.04, 1.8)
	draw_line(c + Vector2(-lens_r * 0.72, -lens_r * 0.18),
		c + Vector2(lens_r * 0.10, lens_r * 0.16), crack, w, true)
	draw_line(c + Vector2(lens_r * 0.10, lens_r * 0.16),
		c + Vector2(lens_r * 0.66, lens_r * 0.52), crack, w, true)
	draw_line(c + Vector2(lens_r * 0.10, lens_r * 0.16),
		c + Vector2(lens_r * 0.24, -lens_r * 0.60), crack, w, true)
	draw_line(c + Vector2(lens_r * 0.10, lens_r * 0.16),
		c + Vector2(-lens_r * 0.28, lens_r * 0.62), crack, w, true)


# ---------------------------------------------------------------- 表情

func _draw_face(r: float, center: Vector2) -> void:
	var ink := Palette.BOSS_INK
	var eye_y := center.y - r * 0.06
	var brow_y := eye_y - r * 0.46
	if _hit_face > 0.0:
		_draw_hit_face(r, center, eye_y)
		return
	# ---- 眉毛（夸张、有戏）
	match _stage:
		0:
			# 一高一低：得意的挑眉
			draw_line(Vector2(-r * 0.68, brow_y + r * 0.08), Vector2(-r * 0.20, brow_y - r * 0.02),
				ink, 4.4, true)
			draw_line(Vector2(r * 0.20, brow_y - r * 0.22), Vector2(r * 0.68, brow_y - r * 0.06),
				ink, 4.4, true)
		1:
			# 惊讶：两条都往上挑
			for side in [-1.0, 1.0]:
				draw_line(Vector2(side * r * 0.68, brow_y - r * 0.02),
					Vector2(side * r * 0.20, brow_y - r * 0.20), ink, 4.4, true)
		2:
			for side in [-1.0, 1.0]:
				draw_line(Vector2(side * r * 0.68, brow_y + r * 0.12),
					Vector2(side * r * 0.20, brow_y - r * 0.04), ink, 4.6, true)
		3, 4:
			# 愤怒：眉毛压到眼睛上
			for side in [-1.0, 1.0]:
				draw_line(Vector2(side * r * 0.72, brow_y - r * 0.10),
					Vector2(side * r * 0.16, brow_y + r * 0.16), ink, 5.2, true)
		5:
			# 委屈：八字眉
			for side in [-1.0, 1.0]:
				draw_line(Vector2(side * r * 0.64, brow_y + r * 0.06),
					Vector2(side * r * 0.18, brow_y + r * 0.20), ink, 4.4, true)
		_:
			for side in [-1.0, 1.0]:
				draw_line(Vector2(side * r * 0.60, brow_y + r * 0.10),
					Vector2(side * r * 0.20, brow_y + r * 0.06), ink, 4.4, true)
	# ---- 眼睛（Q 版：大眼白 + 小瞳孔 + 高光）
	_draw_eyes(r, center, eye_y)
	_draw_nose(r, center)
	# ---- 嘴巴
	_draw_mouth(r, center)
	# 双下巴的褶线
	draw_arc(center + Vector2(0.0, r * 0.22), r * 0.40, PI * 0.26, PI * 0.74, 14,
		ink.darkened(0.10), 2.0)


func _draw_eyes(r: float, center: Vector2, eye_y: float) -> void:
	var ink := Palette.BOSS_INK
	for side in [-1.0, 1.0]:
		var e := Vector2(side * r * 0.44, eye_y)
		match _stage:
			0:
				# 眯着眼坏笑（下半个眼白 + 一条上眼线）
				draw_circle(e, r * 0.20, Color.WHITE)
				draw_rect(Rect2(e + Vector2(-r * 0.22, -r * 0.22), Vector2(r * 0.44, r * 0.20)),
					_skin_color())
				draw_arc(e, r * 0.20, PI * 1.05, PI * 1.95, 14, ink, 3.0)
				draw_circle(e + Vector2(side * r * 0.05, r * 0.02), r * 0.085, ink)
			1:
				# 惊讶：瞪大的眼睛
				draw_circle(e, r * 0.22, Color.WHITE)
				draw_circle(e, r * 0.10, ink)
				draw_circle(e + Vector2(r * 0.06, -r * 0.07), r * 0.045, Color.WHITE)
			2:
				draw_circle(e, r * 0.19, Color.WHITE)
				draw_circle(e + Vector2(side * r * 0.03, 0.0), r * 0.09, ink)
			3, 4:
				draw_circle(e, r * 0.20, Color.WHITE)
				draw_circle(e + Vector2(side * r * 0.03, r * 0.02), r * 0.095, ink)
				draw_arc(e, r * 0.20, 0.0, TAU, 20, ink, 2.0)
			5:
				# 没精神：眼睛只剩一条缝
				draw_circle(e, r * 0.19, Color.WHITE)
				draw_circle(e + Vector2(0.0, r * 0.07), r * 0.085, ink)
				draw_rect(Rect2(e + Vector2(-r * 0.22, -r * 0.24), Vector2(r * 0.44, r * 0.18)),
					_skin_color())
			_:
				# 崩溃：转圈眼
				draw_circle(e, r * 0.20, Color.WHITE)
				draw_arc(e, r * 0.10, _time * 6.0, _time * 6.0 + PI * 1.5, 14, ink, 2.6)


## 受击瞬间的表情：五种锅各不相同
func _draw_hit_face(r: float, center: Vector2, eye_y: float) -> void:
	var ink := Palette.BOSS_INK
	match _hit_kind:
		"pan":
			# 平底锅砸鼻子：眼睛挤成 ><，嘴巴咧成一条大嘴
			for side in [-1.0, 1.0]:
				var e := Vector2(side * r * 0.44, eye_y)
				draw_line(e + Vector2(-r * 0.18, -r * 0.12), e, ink, 3.2, true)
				draw_line(e, e + Vector2(-r * 0.18, r * 0.12), ink, 3.2, true)
				draw_line(e + Vector2(r * 0.18, -r * 0.12), e, ink, 3.2, true)
				draw_line(e, e + Vector2(r * 0.18, r * 0.12), ink, 3.2, true)
			_draw_nose(r, center)
			draw_arc(Vector2(0.0, center.y + r * 0.30), r * 0.26, PI * 0.10, PI * 0.90, 14,
				Color(0.42, 0.16, 0.16), 4.0)
			return
		"pressure":
			# 高压锅砸头：转圈眼 + 张大嘴
			for side in [-1.0, 1.0]:
				var e := Vector2(side * r * 0.44, eye_y)
				draw_circle(e, r * 0.20, Color.WHITE)
				draw_arc(e, r * 0.10, _time * 9.0, _time * 9.0 + PI * 1.5, 14, ink, 2.6)
			_draw_nose(r, center)
			draw_circle(Vector2(0.0, center.y + r * 0.30), r * 0.20, Color(0.42, 0.16, 0.16))
			return
		"broken":
			# 破锅糊脸：一只眼眯着、一只眼瞪圆，舌头都吐出来了
			draw_circle(Vector2(-r * 0.44, eye_y), r * 0.20, Color.WHITE)
			draw_circle(Vector2(-r * 0.42, eye_y), r * 0.095, ink)
			var e2 := Vector2(r * 0.44, eye_y)
			draw_line(e2 + Vector2(-r * 0.18, 0.0), e2 + Vector2(r * 0.18, 0.0), ink, 3.2, true)
			draw_line(e2 + Vector2(-r * 0.12, -r * 0.14), e2 + Vector2(r * 0.12, -r * 0.14),
				ink, 3.0, true)
			_draw_nose(r, center)
			draw_arc(Vector2(0.0, center.y + r * 0.26), r * 0.22, PI * 0.08, PI * 0.92, 14, ink, 3.4)
			draw_rect(Rect2(Vector2(-r * 0.09, center.y + r * 0.36), Vector2(r * 0.18, r * 0.20)),
				Color("e0655a"))
			return
		_:
			# 普通锅 / 铁锅：X 眼 + 张嘴（铁锅再加咬牙）
			for side in [-1.0, 1.0]:
				var e := Vector2(side * r * 0.44, eye_y)
				draw_line(e + Vector2(-r * 0.12, -r * 0.12), e + Vector2(r * 0.12, r * 0.12),
					ink, 3.6, true)
				draw_line(e + Vector2(r * 0.12, -r * 0.12), e + Vector2(-r * 0.12, r * 0.12),
					ink, 3.6, true)
			_draw_nose(r, center)
			if _hit_kind == "iron":
				var mouth_y := center.y + r * 0.26
				draw_rect(Rect2(Vector2(-r * 0.26, mouth_y), Vector2(r * 0.52, r * 0.20)),
					Color(0.42, 0.16, 0.16))
				for i in 3:
					draw_rect(Rect2(Vector2(-r * 0.22 + float(i) * r * 0.16, mouth_y),
						Vector2(r * 0.08, r * 0.09)), Color(0.98, 0.96, 0.94))
			else:
				draw_circle(Vector2(0.0, center.y + r * 0.30), r * 0.17, Color(0.42, 0.16, 0.16))


## 大鼻子：平底锅砸过之后会变红，还挂一点卡通鼻血
func _draw_nose(r: float, center: Vector2) -> void:
	var nose := Vector2(0.0, center.y + r * 0.14)
	var color := Palette.BOSS_SKIN.darkened(0.12)
	if _nose_red:
		color = Color("dd6459")
	draw_circle(nose, r * 0.21, color)
	draw_arc(nose, r * 0.21, PI * 0.18, PI * 0.82, 12, color.darkened(0.20), 2.2)
	if _nose_red:
		var drip := r * (0.34 + 0.30 * clampf(_nose_hit / 0.55, 0.0, 1.0))
		draw_line(nose + Vector2(r * 0.13, r * 0.14), nose + Vector2(r * 0.17, drip),
			Color("c2453f"), maxf(r * 0.045, 2.0), true)
		draw_circle(nose + Vector2(r * 0.17, drip + r * 0.06), r * 0.07, Color("c2453f"))


func _draw_mouth(r: float, center: Vector2) -> void:
	var ink := Palette.BOSS_INK
	var y := center.y + r * 0.30
	match _stage:
		0:
			# 咧嘴坏笑：一边嘴角挑起来
			draw_arc(Vector2(0.0, y - r * 0.06), r * 0.30, 0.18, PI * 0.86, 18, ink, 3.8)
			draw_circle(Vector2(r * 0.30, y - r * 0.06), r * 0.05, ink)
		1:
			# 惊讶的小圆嘴
			draw_circle(Vector2(0.0, y + r * 0.02), r * 0.14, Color(0.42, 0.16, 0.16))
			draw_arc(Vector2(0.0, y + r * 0.02), r * 0.14, 0.0, TAU, 16, ink, 2.4)
		2:
			# 撇嘴
			draw_arc(Vector2(r * 0.06, y + r * 0.10), r * 0.24, PI * 1.12, PI * 1.88, 14, ink, 3.4)
		3:
			# 咬牙
			draw_rect(Rect2(Vector2(-r * 0.28, y - r * 0.02), Vector2(r * 0.56, r * 0.22)),
				Color(0.42, 0.16, 0.16))
			for i in 3:
				draw_rect(Rect2(Vector2(-r * 0.24 + float(i) * r * 0.17, y - r * 0.02),
					Vector2(r * 0.08, r * 0.10)), Color(0.98, 0.96, 0.94))
		4:
			# 张嘴大吼
			draw_circle(Vector2(0.0, y + r * 0.04), r * 0.24, Color(0.35, 0.12, 0.12))
			draw_arc(Vector2(0.0, y + r * 0.04), r * 0.24, 0.0, TAU, 20, ink, 3.0)
			draw_circle(Vector2(0.0, y + r * 0.16), r * 0.10, Color("d4675f"))
		5:
			# 叹气 / 委屈
			draw_arc(Vector2(0.0, y + r * 0.14), r * 0.20, 0.14, PI * 0.86, 14, ink, 3.2)
			draw_circle(Vector2(0.0, y + r * 0.08), r * 0.12, Color(0.34, 0.14, 0.14))
		_:
			# 崩溃：张嘴惨叫
			draw_circle(Vector2(0.0, y + r * 0.06), r * 0.22, Color(0.34, 0.12, 0.12))
			draw_arc(Vector2(0.0, y + r * 0.06), r * 0.22, 0.0, TAU, 20, ink, 3.0)


# ---------------------------------------------------------------- 桌子

func _draw_desk(r: float) -> void:
	var wobble_offset := Vector2(sin(_time * 40.0) * wobble * 3.0, 0.0)
	draw_rect(Rect2(Vector2(-r * 2.05, r * 0.86) + wobble_offset,
		Vector2(r * 4.10, r * 0.26)), Palette.DESK_TOP)
	draw_rect(Rect2(Vector2(-r * 2.05, r * 1.12) + wobble_offset,
		Vector2(r * 4.10, r * 0.72)), Palette.DESK)
	draw_rect(Rect2(Vector2(-r * 2.05, r * 1.12) + wobble_offset,
		Vector2(r * 4.10, r * 0.06)), Palette.DESK_DARK)


func _draw_desk_items(r: float) -> void:
	var wobble_offset := Vector2(sin(_time * 40.0) * wobble * 5.0,
		cos(_time * 33.0) * wobble * 2.0)
	# 咖啡杯（摆在桌面边缘）
	var cup := Vector2(-r * 1.45, r * 0.92) + wobble_offset
	draw_rect(Rect2(cup, Vector2(r * 0.42, r * 0.42)), Color(0.93, 0.94, 0.97))
	draw_rect(Rect2(cup + Vector2(-r * 0.07, r * 0.06), Vector2(r * 0.07, r * 0.24)),
		Color(0.93, 0.94, 0.97))
	draw_rect(Rect2(cup + Vector2(r * 0.06, r * 0.04), Vector2(r * 0.30, r * 0.06)),
		Color(0.36, 0.22, 0.14))
	if _stage <= 1:
		for i in 3:
			var t := fmod(_time * 0.7 + float(i) * 0.33, 1.0)
			draw_circle(cup + Vector2(0.0, -r * 0.20 - t * r * 0.40), r * 0.06 * (1.0 - t),
				Color(1.0, 1.0, 1.0, 0.22 * (1.0 - t)))
	else:
		var spill := clampf(float(_stage - 1) / 5.0, 0.0, 1.0)
		draw_colored_polygon(PackedVector2Array([
			cup + Vector2(r * 0.42, r * 0.30),
			cup + Vector2(r * (0.42 + 1.2 * spill), r * 0.44),
			cup + Vector2(r * 0.46, r * 0.46),
		]), Color(0.38, 0.24, 0.16, 0.85))
	# 文件（摊在桌面上，别糊在老板的肚子 / 皮带上）
	for i in 3:
		var offset := Vector2(r * (0.85 + float(i) * 0.16), r * (1.18 - float(i) * 0.03)) \
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
	draw_rect(Rect2(Vector2(r * 1.42, r * 0.92) + wobble_offset, Vector2(r * 0.30, r * 0.62)),
		Color(0.30, 0.34, 0.42))
	for i in 3:
		var pen := Vector2(r * 1.48 + float(i) * r * 0.09, r * 0.72) + wobble_offset
		draw_line(pen, pen + Vector2(0.0, -r * 0.24), Color(0.85 - float(i) * 0.2, 0.4, 0.35),
			3.0, true)


# ---------------------------------------------------------------- 崩溃姿势

## KO：仰面瘫在椅子上，双脚翘起露出黑皮鞋，眼镜歪、头发乱、头顶转星星
func _draw_ko_pose(r: float) -> void:
	var skin := _skin_color()
	var suit := _suit_color()
	# 瘫掉的身体 + 大肚子
	draw_colored_polygon(PackedVector2Array([
		Vector2(-r * 1.24, r * 1.05), Vector2(-r * 0.84, r * 0.30),
		Vector2(r * 0.84, r * 0.30), Vector2(r * 1.24, r * 1.05),
	]), suit)
	draw_circle(Vector2(0.0, r * 0.80), r * 1.00, suit)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-r * 0.30, r * 0.34), Vector2(r * 0.30, r * 0.34),
		Vector2(r * 0.44, r * 0.70), Vector2(r * 0.26, r * 1.02),
		Vector2(-r * 0.26, r * 1.02), Vector2(-r * 0.44, r * 0.70),
	]), Palette.BOSS_SHIRT)
	# 松掉的黑皮带
	draw_colored_polygon(PackedVector2Array([
		Vector2(-r * 0.90, r * 0.66), Vector2(r * 0.90, r * 0.66),
		Vector2(r * 0.88, r * 0.78), Vector2(-r * 0.88, r * 0.78),
	]), Color(0.10, 0.10, 0.12))
	# 两条短腿翘在桌上（露出黑皮鞋）
	for side in [-1.0, 1.0]:
		var knee := Vector2(side * r * 0.52, r * 0.28)
		var ankle := Vector2(side * r * 0.78, -r * 0.30)
		draw_line(Vector2(side * r * 0.30, r * 0.86), knee, suit, maxf(r * 0.34, 4.0), true)
		draw_line(knee, ankle, suit, maxf(r * 0.30, 4.0), true)
		draw_circle(ankle + Vector2(side * r * 0.06, -r * 0.10), r * 0.20,
			Color(0.11, 0.11, 0.13))
		draw_circle(ankle + Vector2(side * r * 0.20, -r * 0.04), r * 0.13,
			Color(0.16, 0.16, 0.19))
	# 摊开的手
	for side in [-1.0, 1.0]:
		var hand := Vector2(side * r * 1.14, r * 0.86)
		draw_line(Vector2(side * r * 0.90, r * 0.72), hand, Palette.BOSS_SUIT_DARK,
			maxf(r * 0.28, 4.0), true)
		draw_circle(hand, r * 0.23, skin)
	# 桌面
	draw_rect(Rect2(Vector2(-r * 2.05, r * 0.74), Vector2(r * 4.10, r * 0.26)), Palette.DESK_TOP)
	draw_rect(Rect2(Vector2(-r * 2.05, r * 1.00), Vector2(r * 4.10, r * 0.84)), Palette.DESK)
	draw_rect(Rect2(Vector2(-r * 2.05, r * 1.00), Vector2(r * 4.10, r * 0.06)), Palette.DESK_DARK)
	# 歪在桌上的脑袋
	var head := Vector2(r * 0.16, r * 0.46)
	draw_circle(head, r * 0.78, skin)
	draw_arc(head, r * 0.78, 0.0, TAU, 36, skin.darkened(0.30), 2.0)
	draw_circle(head + Vector2(-r * 0.08, -r * 0.34), r * 0.42, skin.lightened(0.10))
	# 乱成鸡窝的「地方包围中央」
	for side in [-1.0, 1.0]:
		draw_circle(head + Vector2(side * r * 0.74, -r * 0.16), r * 0.22, Palette.BOSS_HAIR)
		draw_circle(head + Vector2(side * r * 0.80, r * 0.06), r * 0.20, Palette.BOSS_HAIR)
	for i in 6:
		var angle := PI * 1.02 + float(i) * 0.20
		draw_line(head + Vector2(cos(angle), sin(angle)) * r * 0.52,
			head + Vector2(cos(angle), sin(angle)) * r * 1.30, Palette.BOSS_HAIR,
			maxf(r * 0.05, 2.0), true)
	if _head_bump:
		draw_circle(head + Vector2(-r * 0.22, -r * 0.68), r * 0.24,
			skin.lerp(Color("e0786a"), 0.42))
	# 转圈眼 + 张嘴惨叫
	for side in [-1.0, 1.0]:
		var e := head + Vector2(side * r * 0.34, -r * 0.04)
		draw_circle(e, r * 0.20, Color.WHITE)
		draw_arc(e, r * 0.10, _time * 6.0, _time * 6.0 + PI * 1.5, 14, Palette.BOSS_INK, 2.6)
	draw_circle(head + Vector2(-r * 0.30, r * 0.26), r * 0.16, Color(0.34, 0.12, 0.12))
	draw_circle(head + Vector2(-r * 0.02, r * 0.22), r * 0.18, Color(0.34, 0.12, 0.12))
	# 歪掉的眼镜（一只镜片压在脸上）
	var lens := head + Vector2(r * 0.38, r * 0.28)
	var frame := Color(0.13, 0.14, 0.17)
	draw_arc(lens, r * 0.24, 0.0, TAU, 22, frame, maxf(r * 0.06, 2.4))
	draw_line(lens + Vector2(-r * 0.24, 0.0), head + Vector2(r * 0.06, r * 0.14),
		frame, maxf(r * 0.055, 2.2), true)
	draw_line(lens + Vector2(r * 0.24, 0.0), lens + Vector2(r * 0.82, -r * 0.16),
		frame, maxf(r * 0.055, 2.2), true)
	if _glasses_crack:
		draw_line(lens + Vector2(-r * 0.14, -r * 0.10), lens + Vector2(r * 0.06, r * 0.06),
			Color(0.04, 0.05, 0.07), maxf(r * 0.04, 1.8), true)
		draw_line(lens + Vector2(r * 0.06, r * 0.06), lens + Vector2(r * 0.18, r * 0.22),
			Color(0.04, 0.05, 0.07), maxf(r * 0.04, 1.8), true)
	if _nose_red:
		draw_circle(head + Vector2(-r * 0.30, r * 0.10), r * 0.15, Color("dd6459"))
	if _face_soot:
		draw_circle(head + Vector2(-r * 0.08, r * 0.30), r * 0.18,
			Color(0.15, 0.14, 0.14, 0.55))
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


# ---------------------------------------------------------------- 阶段特效 / 受击叠加

func _draw_effects(r: float) -> void:
	var head_top := Vector2(0.0, -r * 1.42)
	match _stage:
		0:
			# 得意的闪光
			for i in 2:
				var p := Vector2(-r * 1.05 + float(i) * r * 2.1, -r * 1.15)
				var s := r * 0.16 * (0.7 + 0.3 * sin(_time * 3.0 + float(i)))
				draw_line(p - Vector2(s, 0.0), p + Vector2(s, 0.0), Palette.ACCENT, 2.5, true)
				draw_line(p - Vector2(0.0, s), p + Vector2(0.0, s), Palette.ACCENT, 2.5, true)
		1:
			_draw_question_mark(head_top + Vector2(r * 0.90, r * 0.10), r * 0.30)
		2:
			draw_line(head_top + Vector2(r * 0.55, r * 0.10),
				head_top + Vector2(r * 0.75, r * 0.30), Palette.DANGER, 3.0, true)
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
		_:
			for i in 3:
				var angle := _time * 2.6 + TAU * float(i) / 3.0
				var p := Vector2(cos(angle) * r * 1.15, -r * 1.35 + sin(angle) * r * 0.30)
				_draw_star(p, r * 0.17, Palette.ACCENT)


func _draw_question_mark(center: Vector2, size: float) -> void:
	draw_line(center + Vector2(-size * 0.35, -size * 0.55),
		center + Vector2(size * 0.35, -size * 0.10), Palette.INFO, 4.0, true)
	draw_line(center + Vector2(size * 0.35, -size * 0.10), center + Vector2(0.0, size * 0.30),
		Palette.INFO, 4.0, true)
	draw_circle(center + Vector2(0.0, size * 0.78), size * 0.11, Palette.INFO)


func _draw_anger_mark(center: Vector2, size: float) -> void:
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


## 受击白光 + 被锅扣头 + 换阶段的冲击波 + 这一口锅的撞击符号
func _draw_hit_overlay(r: float) -> void:
	if _hit_flash > 0.0:
		draw_circle(Vector2(0.0, -r * 0.5), r * 1.15,
			Color(1.0, 1.0, 1.0, 0.30 * (_hit_flash / 0.24)))
	if _stuck_time > 0.0 and _stuck_pot != null:
		_draw_stuck_pot(r)
	if _stage_flash > 0.0:
		var t := 1.0 - _stage_flash / 0.8
		draw_arc(Vector2(0.0, -r * 0.4), r * (0.8 + t * 2.4), 0.0, TAU, 40,
			Color(Palette.DANGER, 0.5 * (1.0 - t)), 6.0)
	if _impact_time > 0.0:
		_draw_impact_mark(r, Vector2(0.0, -r * 0.58))


## 受击瞬间的撞击符号（按锅型区分，短促播放）
func _draw_impact_mark(r: float, center: Vector2) -> void:
	var t := clampf(_impact_time / 0.40, 0.0, 1.0)
	var alpha := 0.85 * t
	match _impact_type:
		"pan":
			var at := center + Vector2(0.0, r * 0.14)
			for i in 6:
				var angle := TAU * float(i) / 6.0
				draw_line(at + Vector2(cos(angle), sin(angle)) * r * 0.30,
					at + Vector2(cos(angle), sin(angle)) * r * (0.44 + 0.20 * (1.0 - t)),
					Color("ff7d6b", alpha), maxf(r * 0.05, 2.2), true)
		"pressure":
			_draw_star(center + Vector2(-r * 0.28, -r * 0.72), r * 0.34,
				Color("ffe08a", alpha))
			_draw_star(center + Vector2(r * 0.24, -r * 0.88), r * 0.24,
				Color("ffd166", alpha))
		"broken":
			for i in 6:
				var angle := TAU * float(i) / 6.0 + _time
				draw_circle(center + Vector2(cos(angle), sin(angle))
					* r * (0.70 + 0.34 * (1.0 - t)), maxf(r * 0.075, 2.0) * t,
					Color(0.22, 0.20, 0.18, alpha))
		"iron":
			_draw_star(center + Vector2(0.0, -r * 0.44), r * 0.38, Color("ffd166", alpha))
			_draw_star(center + Vector2(-r * 0.40, -r * 0.30), r * 0.20,
				Color(1.0, 1.0, 1.0, alpha))
		_:
			for i in 4:
				var angle := -PI * 0.5 + (float(i) - 1.5) * 0.5
				draw_line(center + Vector2(cos(angle), sin(angle)) * r * 0.90,
					center + Vector2(cos(angle), sin(angle)) * r * (1.06 + 0.14 * (1.0 - t)),
					Color("ffe08a", alpha), maxf(r * 0.045, 2.0), true)


func _draw_stuck_pot(r: float) -> void:
	var pot := _stuck_pot
	var center := Vector2(0.0, -r * 1.24)
	var size := r * 0.52
	draw_circle(center, size, pot.tint)
	draw_circle(center, size * 0.72, pot.tint_dark)
	draw_arc(center, size, 0.0, TAU, 24, pot.tint_dark, 3.0)
	for side in [-1.0, 1.0]:
		draw_arc(center + Vector2(side * size * 1.0, 0.0), size * 0.30,
			PI * 0.5 if side > 0.0 else -PI * 0.5,
			PI * 1.5 if side > 0.0 else PI * 0.5, 10, pot.tint_dark, 3.5)
	draw_circle(center + Vector2(0.0, -size * 0.95), size * 0.18, Palette.ACCENT)
