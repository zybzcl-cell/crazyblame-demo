class_name BlameBoss
extends Node2D
## 老板：**gameplay 状态 + 动画时间轴 + 素材渲染**三层分离。
##
##   玩法状态（本文件）      HP / 七阶段 / 受击 / 甩锅时间轴 / 六方向 / 手部锚点
##        ↓
##   动画状态（本文件）      IDLE / THROW_NOTICE / THROW_WINDUP / THROW_RELEASE / THROW_RECOVER / KO
##        ↓
##   素材渲染（BossArt）     assets/characters/boss/*.png → AnimatedSprite2D(SpriteFrames)
##
## ---- 美术来自素材，不再由代码画
## 老板的长相（身体 / 头 / 眼镜 / 西装 / 五官 / 头发）**完全由 `assets/characters/boss/` 里的
## 透明 PNG 决定**（七个阶段表情 + 四个甩锅动作，缺图会自动回退）。
## 这个节点自己的 `_draw()` 不再画任何角色，只保留「锚点 debug 线」（默认关闭，
## `procedural_draw_primitives()` 在正常运行时应为 0）。
## 受击特效（星星 / 鼻血 / 头包 / 灰尘 / 眼镜裂纹 / 扣头锅）在独立的 `BossFx` 子节点里；
## 办公桌 / 椅子 / 桌上道具由 `BossDesk` 子节点绘制（属于办公场景道具，可用 manifest 关掉）。
##
## ---- 七阶段（名字与血量比例沿用原来的，不破坏既有玩法）
##   0 得意 / 1 疑惑 / 2 不爽 / 3 愤怒 / 4 暴怒 / 5 疲惫 / 6 崩溃
##
## ---- 甩锅动作时间轴（与锅的生成严格对齐）
##   0.00~0.10  THROW_NOTICE   注意目标 / 伸手（头顶冒「！」）
##   0.10~0.34  THROW_WINDUP   抬手蓄力（锅被攥在手里，玩家抓不到）
##   0.34       THROW_RELEASE  手臂前甩，锅从 throw_release_point() 脱手
##   0.34~0.64  THROW_RECOVER  收势（残影 / 速度线）

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
const THROW_NOTICE := 0.10
const THROW_RAISE := 0.24
const THROW_WINDUP := THROW_NOTICE + THROW_RAISE
const THROW_FOLLOW := 0.30
const THROW_TOTAL := THROW_WINDUP + THROW_FOLLOW

## 动画状态（视觉层）
enum VisualState { IDLE, THROW_NOTICE, THROW_WINDUP, THROW_RELEASE, THROW_RECOVER, KO }

var hp: int = GameConfig.BOSS_MAX_HP
var max_hp: int = GameConfig.BOSS_MAX_HP
var scale_factor: float = 1.0

var shake: float = 0.0
var tilt: float = 0.0
var wobble: float = 0.0

## 调试：打开后会在 Boss 位置上画锚点十字（默认关，正常运行不画任何东西）
var debug_draw_anchors := false

var _art: BossArt = null
var _sprite: AnimatedSprite2D = null
var _fx: BossFx = null
var _desk: BossDesk = null
var _visual := VisualState.IDLE
var _procedural_primitives := 0

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
var _floor_y: float = 0.0
var _t_offset := Vector2.ZERO
var _t_lean := 0.0
var _bob := 0.0
var _recoil := 0.0

## ---- 受击「战损」状态：本局内累积，越打越狼狈（但始终滑稽，不是写实受伤）
var _glasses_crack := false
var _nose_red := false
var _head_bump := false
var _face_soot := false
var _mess := 0.0
var _glasses_wobble := 0.0
var _nose_hit := 0.0
var _bump_pop := 0.0
var _impact_type := ""
var _impact_time := 0.0

## ---- 甩锅动作状态
var _throw_time := -1.0
var _throw_lane := ""
var _throw_dir := Vector2.DOWN
var _throw_side := 1.0
var _throw_vertical := 0.0
var _throw_count := 0


func _ready() -> void:
	_rng.randomize()
	_art = BossArt.new()
	_art.load_assets()
	# 视觉层：AnimatedSprite2D（SpriteFrames 由素材目录里的 PNG 组成）
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "BossSprite"
	_sprite.sprite_frames = _art.sprite_frames()
	_sprite.z_index = 0
	add_child(_sprite)
	# 场景道具：办公桌 / 椅子 / 桌上道具
	_desk = BossDesk.new()
	_desk.name = "BossDesk"
	_desk.z_index = 1
	add_child(_desk)
	_desk.configure(self)
	# 独立特效层：受击 / 阶段特效（不画角色本体）
	_fx = BossFx.new()
	_fx.name = "BossFx"
	_fx.z_index = 2
	add_child(_fx)
	_fx.configure(self)
	_art.report_status_once()
	_apply_visual()


## 由游戏主控在布局变化时调用
func configure(scale_value: float, hit_radius: float, hit_center: Vector2) -> void:
	scale_factor = scale_value
	_hit_radius = hit_radius
	position = hit_center
	_apply_visual()


## 布局变化时由游戏主控调用（比 configure 多一个地板线，用来画接触阴影 / 桌子位置）
func configure_with_floor(
	scale_value: float, hit_radius: float, hit_center: Vector2, floor_y: float
) -> void:
	_floor_y = floor_y
	configure(scale_value, hit_radius, hit_center)


func hit_radius() -> float:
	return _hit_radius


## 判定圆心：脑袋 + 上半身，稍微偏上一点
func hit_center() -> Vector2:
	return global_position + Vector2(0.0, -BASE_RADIUS * 0.35 * scale_factor)


func body_radius() -> float:
	return BASE_RADIUS * scale_factor


# ---------------------------------------------------------------- 素材 / 动画查询（测试与调试用）

func art() -> BossArt:
	return _art


func sprite_node() -> AnimatedSprite2D:
	return _sprite


## 有没有真正的 Boss 美术素材（占位图不算）
func has_boss_art() -> bool:
	return _art != null and _art.has_real_art()


func art_status_text() -> String:
	return _art.status_text() if _art != null else ""


func visual_state() -> VisualState:
	return _visual


func visual_state_name() -> String:
	match _visual:
		VisualState.THROW_NOTICE:
			return "throw_notice"
		VisualState.THROW_WINDUP:
			return "throw_windup"
		VisualState.THROW_RELEASE:
			return "throw_release"
		VisualState.THROW_RECOVER:
			return "throw_recover"
		VisualState.KO:
			return "ko"
	return "idle"


## 当前正在播放的动画名（= 素材里的 animation 名）
func current_animation() -> String:
	return _sprite.animation if _sprite != null else ""


## Boss 节点自己画了几个图元（正常运行必须是 0：角色由贴图负责）
func procedural_draw_primitives() -> int:
	return _procedural_primitives


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


## 被锅扣在头上的那口锅（没有就是 null）
func stuck_pot() -> PotType:
	if _stuck_pot == null or _stuck_time <= 0.0:
		return null
	return _stuck_pot


func stuck_pot_id() -> String:
	var pot := stuck_pot()
	return "" if pot == null else pot.id


## ---- 受击战损状态（测试与「越来越狼狈」的演出都读它）
func has_glasses_crack() -> bool:
	return _glasses_crack


func has_red_nose() -> bool:
	return _nose_red


func has_head_bump() -> bool:
	return _head_bump


func has_face_soot() -> bool:
	return _face_soot


func mess_level() -> float:
	return _mess


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


## FX 用的贴图 / 状态读数
func skin_tint() -> Color:
	match _stage:
		0, 1:
			return Palette.BOSS_SKIN
		2, 3:
			return Palette.BOSS_SKIN.lerp(Palette.BOSS_SKIN_HOT, 0.30)
		4:
			return Palette.BOSS_SKIN_HOT
		5:
			return Palette.BOSS_SKIN.lerp(Color(0.84, 0.87, 0.91), 0.35)
		_:
			return Palette.BOSS_SKIN.lerp(Color(0.80, 0.83, 0.87), 0.55)


func tick_time() -> float:
	return _time


func hit_flash() -> float:
	return _hit_flash


func stage_flash() -> float:
	return _stage_flash


func impact_time() -> float:
	return _impact_time


func impact_type() -> String:
	return _impact_type


func nose_hit() -> float:
	return _nose_hit


## 受击表情的剩余时间（0~0.38s）
func hit_face_ratio() -> float:
	return _hit_face


## 甩锅动作已经走了多少秒（<0 = 没在甩）
func tick_windup_time() -> float:
	return maxf(_throw_time, 0.0)


func wobble_amount() -> float:
	return wobble


func draw_offset() -> Vector2:
	return _t_offset


func draw_lean() -> float:
	return _t_lean


## 这个世界坐标点是不是落在老板的身体里（头 / 肚子的椭圆）。
## 甩锅时锅要被托在**手**上，必须落在身体外面 —— 测试用它守住这条约束。
func contains_body_point(world_point: Vector2) -> bool:
	var local := to_local_point(world_point)
	var head := _art.anchor("head")
	var head_r: Vector2 = _art.anchor("head_radius")
	if _in_ellipse(local, head, head_r):
		return true
	var belly := _art.anchor("body_center")
	var belly_r: Vector2 = _art.anchor("body_radius")
	return _in_ellipse(local, belly, belly_r)


func _in_ellipse(point: Vector2, center: Vector2, radii: Vector2) -> bool:
	var rx := maxf(radii.x, 0.01)
	var ry := maxf(radii.y, 0.01)
	var dx := (point.x - center.x) / rx
	var dy := (point.y - center.y) / ry
	return dx * dx + dy * dy < 1.0


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


static func stage_for_ratio(ratio: float) -> int:
	var clamped := clampf(ratio, 0.0, 1.0)
	var stage := STAGES.size() - 1
	for i in range(STAGES.size() - 1):
		if clamped > float(STAGE_RATIOS[i + 1]):
			stage = i
			break
	return stage


func set_hp(value: int) -> bool:
	hp = clampi(value, 0, max_hp)
	var next := stage_for_ratio(hp_ratio())
	if next == _stage:
		_apply_visual()
		return false
	var was_ko := is_ko()
	_stage = next
	_stage_flash = 0.55
	shake = maxf(shake, 0.7)
	tilt = 0.0
	set_speech(stage_line(), 2.0)
	if not was_ko and is_ko():
		ko()
	_apply_visual()
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
	_recoil = clampf(_recoil + 0.45 * strength, 0.0, 1.2)
	_impact_type = pot_id
	_impact_time = 0.40
	_glasses_wobble = maxf(_glasses_wobble, 0.34 + 0.22 * strength)
	_mess = clampf(_mess + 0.05 * strength + (0.22 if pot_id == "broken" else 0.0), 0.0, 1.0)
	match pot_id:
		"iron":
			_glasses_crack = true
		"pan":
			_nose_red = true
			_nose_hit = 0.55
		"pressure":
			_head_bump = true
			_bump_pop = 0.55
		"broken":
			_face_soot = true
		_:
			pass
	if pot != null and strength >= 0.8:
		_stuck_pot = pot
		_stuck_time = 0.75 if pot.id == "iron" else 0.55
	_apply_visual()


func ko() -> void:
	_stage = STAGES.size() - 1
	_stage_flash = 0.8
	shake = 1.1
	tilt = 0.0
	set_speech(str(STAGES[_stage]["line"]), 3.0)
	_apply_visual()
	stage_changed.emit(_stage)


func set_speech(text: String, seconds: float = 2.0) -> void:
	_speech = text
	_speech_time = seconds


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
	_apply_visual()


## 菜单上的「吉祥物」模式：直接摆到某个阶段，不播受击 / 换阶段反馈
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
	_apply_visual()


# ---------------------------------------------------------------- 甩锅动作

## 开始一次甩锅：lane 决定往哪边、哪个高度甩，direction 是「锅飞出去的方向」（世界坐标）。
func begin_throw(lane: String, direction: Vector2, vertical: float) -> void:
	_throw_lane = lane
	_throw_dir = direction.normalized() if direction.length() > 0.001 else Vector2.DOWN
	_throw_side = -1.0 if lane.begins_with("left") else 1.0
	_throw_vertical = clampf(vertical, -1.0, 1.0)
	_throw_time = 0.0
	_throw_count += 1
	_apply_visual()


func is_throwing() -> bool:
	return _throw_time >= 0.0


func is_winding_up() -> bool:
	return _throw_time >= 0.0 and _throw_time < THROW_WINDUP


func is_noticing() -> bool:
	return _throw_time >= 0.0 and _throw_time < THROW_NOTICE


func windup_ratio() -> float:
	if _throw_time < 0.0:
		return 0.0
	return clampf(_throw_time / THROW_WINDUP, 0.0, 1.0)


func throw_lane() -> String:
	return _throw_lane


func throw_side() -> float:
	return _throw_side


## 这一口锅飞出去的方向（世界坐标单位向量）
func throw_direction() -> Vector2:
	return _throw_dir


## 方向提示线用的本地方向（把整体倾斜还原掉）
func throw_cue_dir_local() -> Vector2:
	return _throw_dir.rotated(-_t_lean).normalized()


func throw_count() -> int:
	return _throw_count


func throw_release_time() -> float:
	return THROW_WINDUP


func throw_total_time() -> float:
	return THROW_TOTAL


## 手在时间轴 t 的位置（本地 r 单位）—— 位置来自素材锚点，换图不用改玩法代码
func _throw_hand_units(t: float) -> Vector2:
	return _hand_units(_throw_side, _throw_vertical, t)


func _hand_units(side: float, vertical: float, t: float) -> Vector2:
	var rest: Vector2 = _art.anchor("hand_right") if side > 0.0 else _art.anchor("hand_left")
	rest.x = absf(rest.x) * side
	var reach := Vector2(rest.x + side * 0.02, rest.y - 0.16)
	var key := "throw_hand_mid"
	if vertical < -0.34:
		key = "throw_hand_upper"
	elif vertical > 0.34:
		key = "throw_hand_lower"
	var raised: Vector2 = _art.anchor(key)
	raised.x = absf(raised.x) * side
	var follow := Vector2(raised.x + side * 0.42, raised.y + 0.62)
	if t <= THROW_NOTICE:
		var n := clampf(t / THROW_NOTICE, 0.0, 1.0)
		return rest.lerp(reach, _ease_out(n))
	if t <= THROW_WINDUP:
		var u := clampf((t - THROW_NOTICE) / maxf(THROW_RAISE, 0.001), 0.0, 1.0)
		return reach.lerp(raised, _ease_out(u))
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
	_apply_visual()


## 每帧先把「整体变换」算好：贴图、桌子、FX、以及外部读取手部位置都用它
func _update_pose() -> void:
	var r := body_radius()
	var idle_speed := 1.6 + 0.35 * float(_stage)
	_bob = sin(_time * idle_speed) * (2.5 + 1.2 * float(_stage)) * scale_factor
	var jitter := 0.0
	if _stage >= 3:
		jitter = _rng.randf_range(-1.5, 1.5) * (_stage - 2)
	if _stage >= 5:
		_bob += r * 0.05
	_t_offset = Vector2(sin(_time * 46.0) * shake * 13.0 * scale_factor, _bob + jitter)
	if _recoil > 0.0:
		_t_offset += Vector2(0.0, -_recoil * r * 0.09)
	var lean := tilt + _stage_lean()
	if _throw_time >= 0.0:
		if _throw_time <= THROW_WINDUP:
			lean += -_throw_side * 0.06 * windup_ratio()
		else:
			var f := clampf((_throw_time - THROW_WINDUP) / maxf(THROW_FOLLOW, 0.001), 0.0, 1.0)
			lean += -_throw_side * 0.06 + _throw_side * 0.16 * f
	_t_lean = lean


func _stage_lean() -> float:
	match _stage:
		0:
			return sin(_time * 1.5) * 0.03
		1:
			return -0.07
		2:
			return 0.02 + sin(_time * 6.0) * 0.012
		3:
			return -0.04 + sin(_time * 9.0) * 0.02
		4:
			return -0.09 + sin(_time * 12.0) * 0.03
		5:
			return 0.14
	return 0.0


# ---------------------------------------------------------------- 视觉层：驱动 Sprite

## 由 gameplay 状态推导出动画状态，并把结果应用到 AnimatedSprite2D / BossFx / BossDesk
func _apply_visual() -> void:
	if _sprite == null:
		return
	_visual = _resolve_visual_state()
	var animation := _animation_for(_visual)
	if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(animation):
		if _sprite.animation != animation or not _sprite.is_playing():
			_sprite.play(animation)
	# 贴图缩放 / pivot：让素材里的「身体中心」正好落在节点原点上
	var texture := _current_texture()
	if texture != null:
		_sprite.scale = Vector2.ONE * _art.sprite_scale(texture, body_radius())
		_sprite.offset = _art.sprite_offset(texture)
	# 甩锅 / 受击的镜头级小位移与镜像（代码负责「怎么动」）
	var offset := Vector2.ZERO
	var rot := 0.0
	match _visual:
		VisualState.THROW_NOTICE:
			offset = Vector2(-_throw_side * body_radius() * 0.03, -body_radius() * 0.01)
			rot = -_throw_side * 0.04
		VisualState.THROW_WINDUP:
			var u := clampf((_throw_time - THROW_NOTICE) / maxf(THROW_RAISE, 0.001), 0.0, 1.0)
			offset = Vector2(-_throw_side * body_radius() * 0.05 * u, -body_radius() * 0.03 * u)
			rot = -_throw_side * 0.10 * u
		VisualState.THROW_RELEASE, VisualState.THROW_RECOVER:
			var f := clampf((_throw_time - THROW_WINDUP) / maxf(THROW_FOLLOW, 0.001), 0.0, 1.0)
			offset = Vector2(_throw_side * body_radius() * 0.06 * (1.0 - f), -body_radius() * 0.02)
			rot = _throw_side * 0.12 * (1.0 - f)
		_:
			pass
	if shake > 0.0 and not is_throwing():
		offset += Vector2(sin(_time * 52.0) * shake * 5.0 * scale_factor, 0.0)
		rot += sin(_time * 46.0) * shake * 0.05
	# 贴图镜像：素材只画右手甩锅，向左甩时水平翻转（手部锚点同步镜像）
	_sprite.flip_h = _throw_side < 0.0 and is_throwing()
	_sprite.position = offset
	_sprite.rotation = rot
	# 受击闪白 / 阶段色调（贴图级，不画角色本体）
	var tint := Color.WHITE
	match _stage:
		4:
			tint = tint.lerp(Color(1.0, 0.92, 0.88), 0.35)
		5:
			tint = tint.lerp(Color(0.94, 0.96, 1.0), 0.35)
		6:
			tint = tint.lerp(Color(0.90, 0.93, 0.98), 0.45)
	if _hit_flash > 0.0:
		tint = tint.lerp(Color(1.0, 0.97, 0.94),
			clampf(_hit_flash / 0.24, 0.0, 1.0) * 0.40)
	_sprite.modulate = tint
	# 子节点：桌子 / FX 跟随同一套整体变换
	if _desk != null:
		_desk.transform = Transform2D(_t_lean, _t_offset)
		_desk.visible = _art.draw_desk
		_desk.queue_redraw()
	if _fx != null:
		_fx.transform = Transform2D(_t_lean, _t_offset)
		_fx.queue_redraw()


func _resolve_visual_state() -> VisualState:
	if is_ko():
		return VisualState.KO
	if _throw_time >= 0.0:
		if _throw_time < THROW_NOTICE:
			return VisualState.THROW_NOTICE
		if _throw_time < THROW_WINDUP:
			return VisualState.THROW_WINDUP
		if _throw_time < THROW_WINDUP + THROW_FOLLOW * 0.35:
			return VisualState.THROW_RELEASE
		return VisualState.THROW_RECOVER
	return VisualState.IDLE


func _animation_for(state: VisualState) -> String:
	match state:
		VisualState.KO:
			return "ko"
		VisualState.THROW_NOTICE:
			return _art.animation_name_for_throw("notice")
		VisualState.THROW_WINDUP:
			return _art.animation_name_for_throw("windup")
		VisualState.THROW_RELEASE:
			return _art.animation_name_for_throw("release")
		VisualState.THROW_RECOVER:
			return _art.animation_name_for_throw("recover")
	return _art.animation_name_for_stage(_stage)


func _current_texture() -> Texture2D:
	if _sprite == null or _sprite.sprite_frames == null:
		return null
	var animation := _sprite.animation
	var frames := _sprite.sprite_frames.get_frame_count(animation)
	if frames <= 0:
		return null
	return _sprite.sprite_frames.get_frame_texture(animation, clampi(_sprite.frame, 0, frames - 1))


# ---------------------------------------------------------------- 只保留 debug 的 _draw

## 正常运行：Boss 节点自己不画任何角色（角色由贴图负责），这里只统计图元数量。
## 打开 `debug_draw_anchors` 时才会画锚点十字，方便换素材时校准。
func _draw() -> void:
	_procedural_primitives = 0
	if not debug_draw_anchors or _art == null:
		return
	var r := body_radius()
	for key in ["head", "face", "hand_left", "hand_right", "throw_hand_upper",
			"throw_hand_mid", "throw_hand_lower"]:
		var at: Vector2 = _art.anchor(str(key)) * r
		draw_line(at - Vector2(r * 0.16, 0.0), at + Vector2(r * 0.16, 0.0),
			Color(1.0, 0.3, 0.3, 0.9), 2.0)
		draw_line(at - Vector2(0.0, r * 0.16), at + Vector2(0.0, r * 0.16),
			Color(1.0, 0.3, 0.3, 0.9), 2.0)
		_procedural_primitives += 2
