class_name BossArt
extends RefCounted
## Boss 美术素材（PNG / SpriteFrames）的加载、回退与锚点。
##
## 分工（本次重构的核心）：
##   - **这个文件 + assets/characters/boss/ 里的 PNG** 决定「老板长什么样」；
##   - `boss.gd` 只决定「老板怎么动」（状态、时间轴、甩锅、受击）。
##
## 素材缺失时不会退回程序绘制的 Boss，而是用一张**明确标注「素材缺失」的占位图**，
## 并在控制台打印缺哪些文件（见 `missing_files()` / `status_text()`）。

const DIR := "res://assets/characters/boss"
const PLACEHOLDER_PATH := DIR + "/_placeholder_missing_art.png"
const MANIFEST_PATH := DIR + "/manifest.json"

const STAGE_COUNT := 7
## 甩锅动作的四个阶段（与 boss.gd 的时间轴一一对应）
const THROW_PHASES := ["notice", "windup", "release", "recover"]
## 一个动画最多检查几帧（boss_stage_1_1.png / _2 …）
const MAX_FRAMES := 6

## 默认锚点（r 单位，原点 = Boss 身体中心）。换素材时改 manifest.json 覆盖这些值。
const DEFAULT_PIVOT := Vector2(0.5, 0.45)
const DEFAULT_SPRITE_HEIGHT_R := 3.32
const DEFAULT_MAX_WIDTH_R := 2.90
const DEFAULT_ANCHORS := {
	"head": Vector2(0.0, -0.56),
	"face": Vector2(0.0, -0.30),
	"hand_left": Vector2(-1.12, 0.26),
	"hand_right": Vector2(1.12, 0.26),
	"throw_hand_upper": Vector2(1.20, -1.02),
	"throw_hand_mid": Vector2(1.26, -0.44),
	"throw_hand_lower": Vector2(1.18, 0.14),
	"body_center": Vector2(0.0, 0.56),
	"body_radius": Vector2(1.06, 1.06),
	"head_radius": Vector2(0.92, 0.92),
}

var pivot := DEFAULT_PIVOT
var sprite_height_r := DEFAULT_SPRITE_HEIGHT_R
var max_width_r := DEFAULT_MAX_WIDTH_R
var draw_desk := true
var anchors: Dictionary = {}

var _placeholder: Texture2D = null
var _stage_frames: Array = []          ## Array[Array[Texture2D]]，长度 7
var _throw_frames: Dictionary = {}     ## phase -> Array[Texture2D]
var _frames_cache: SpriteFrames = null
var _missing: Array[String] = []
var _loaded := false
## 「素材缺失」提示每个进程只打印一次，避免刷屏
static var _status_printed := false


## 读取素材目录（幂等；缺素材时只记录，不报错刷屏）
func load_assets() -> void:
	if _loaded:
		return
	_loaded = true
	anchors = DEFAULT_ANCHORS.duplicate()
	_read_manifest()
	_placeholder = _load_texture(PLACEHOLDER_PATH)
	_stage_frames.clear()
	_throw_frames.clear()
	for i in STAGE_COUNT:
		var frames := _load_frames("boss_stage_%d" % (i + 1))
		_stage_frames.append(frames)
	for phase in THROW_PHASES:
		_throw_frames[phase] = _load_frames("boss_throw_%s" % phase)
	# 记录缺哪些素材（占位图不算「有素材」）
	if not has_real_art():
		_missing.append("boss_stage_1.png … boss_stage_7.png")
		for phase in THROW_PHASES:
			_missing.append("boss_throw_%s.png" % phase)
	if _placeholder == null:
		_missing.append("_placeholder_missing_art.png")


## 有没有真正的美术素材（占位图不算）
func has_real_art() -> bool:
	for frames in _stage_frames:
		if not (frames as Array).is_empty():
			return true
	for phase in _throw_frames.keys():
		if not (_throw_frames[phase] as Array).is_empty():
			return true
	return false


func missing_files() -> Array[String]:
	return _missing.duplicate()


func status_text() -> String:
	if has_real_art():
		return "Boss 素材：已加载 %s" % DIR
	return "Boss 素材缺失：请把透明 PNG 放进 %s（缺 %s）" % [DIR, ", ".join(_missing)]


## 素材缺失时在控制台留一条明确提示（每个进程只打一次，不刷屏、不当作引擎错误）
func report_status_once() -> void:
	if _status_printed:
		return
	_status_printed = true
	print("【Boss 素材】%s" % status_text())


func anchors_map() -> Dictionary:
	return anchors.duplicate()


## 锚点（r 单位，原点 = Boss 身体中心）
func anchor(name: String) -> Vector2:
	return anchors.get(name, Vector2.ZERO)


func placeholder_texture() -> Texture2D:
	load_assets()
	return _placeholder


## 第 index（0~6）阶段的表情帧；缺图时回退到第 1 阶段，再回退到占位图
func stage_frames(index: int) -> Array:
	load_assets()
	var clamped := clampi(index, 0, STAGE_COUNT - 1)
	var frames: Array = _stage_frames[clamped]
	if not frames.is_empty():
		return frames
	var first: Array = _stage_frames[0] if not _stage_frames.is_empty() else []
	if not first.is_empty():
		return first
	return _placeholder_frames()


## 甩锅动作某个阶段的帧；缺图时回退到「当前阶段表情」（动作由代码位移/旋转表现）
func throw_frames(phase: String, stage_index: int) -> Array:
	load_assets()
	var frames: Array = _throw_frames.get(phase, [])
	if not frames.is_empty():
		return frames
	return stage_frames(stage_index)


func animation_name_for_stage(index: int) -> String:
	load_assets()
	if clampi(index, 0, STAGE_COUNT - 1) >= STAGE_COUNT - 1:
		return "ko"
	return "idle_stage_%d" % (clampi(index, 0, STAGE_COUNT - 1) + 1)


func animation_name_for_throw(phase: String) -> String:
	return "throw_%s" % phase


## 组装 SpriteFrames（AnimatedSprite2D 用）。七阶段 + 四个甩锅阶段。
func sprite_frames() -> SpriteFrames:
	load_assets()
	if _frames_cache != null:
		return _frames_cache
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for i in STAGE_COUNT:
		var name := "idle_stage_%d" % (i + 1)
		frames.add_animation(name)
		frames.set_animation_loop(name, true)
		frames.set_animation_speed(name, 6.0)
		for texture in stage_frames(i):
			frames.add_frame(name, texture)
	# 崩溃：用第 7 阶段的表情，循环放慢
	frames.add_animation("ko")
	frames.set_animation_loop("ko", true)
	frames.set_animation_speed("ko", 3.0)
	for texture in stage_frames(STAGE_COUNT - 1):
		frames.add_frame("ko", texture)
	for phase in THROW_PHASES:
		var name := animation_name_for_throw(phase)
		var loop: bool = str(phase) == "notice" or str(phase) == "windup"
		frames.add_animation(name)
		frames.set_animation_loop(name, loop)
		frames.set_animation_speed(name, 12.0)
		for texture in throw_frames(phase, 0):
			frames.add_frame(name, texture)
	_frames_cache = frames
	return frames


## 贴图缩放：整张图的高度对应 sprite_height_r 个 r，同时限制最大宽度
func sprite_scale(texture: Texture2D, body_radius: float) -> float:
	if texture == null:
		return 1.0
	var tex_size := texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return 1.0
	var by_height := sprite_height_r * body_radius / tex_size.y
	var by_width := max_width_r * body_radius / tex_size.x
	return maxf(minf(by_height, by_width), 0.01)


## AnimatedSprite2D 的 offset：让贴图的 pivot 那个点正好落在 Boss 节点原点上
func sprite_offset(texture: Texture2D) -> Vector2:
	if texture == null:
		return Vector2.ZERO
	var tex_size := texture.get_size()
	return Vector2((0.5 - pivot.x) * tex_size.x, (0.5 - pivot.y) * tex_size.y)


# ---------------------------------------------------------------- 内部

func _placeholder_frames() -> Array:
	var texture := placeholder_texture()
	if texture == null:
		return []
	return [texture]


func _load_frames(base: String) -> Array:
	var frames: Array = []
	for i in range(1, MAX_FRAMES + 1):
		var texture := _load_texture("%s/%s_%d.png" % [DIR, base, i])
		if texture == null:
			break
		frames.append(texture)
	if frames.is_empty():
		var single := _load_texture("%s/%s.png" % [DIR, base])
		if single != null:
			frames.append(single)
	return frames


func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var resource := load(path)
	return resource as Texture2D


func _read_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		print("【Boss 素材】manifest.json 解析失败，使用默认锚点")
		return
	var data: Dictionary = parsed
	pivot = _as_vector2(data.get("pivot"), pivot)
	sprite_height_r = float(data.get("sprite_height_r", sprite_height_r))
	max_width_r = float(data.get("max_width_r", max_width_r))
	draw_desk = bool(data.get("draw_desk", draw_desk))
	var custom: Variant = data.get("anchors", {})
	if typeof(custom) == TYPE_DICTIONARY:
		for key in (custom as Dictionary).keys():
			anchors[str(key)] = _as_vector2((custom as Dictionary)[key], anchors.get(str(key), Vector2.ZERO))


func _as_vector2(value: Variant, fallback: Vector2) -> Vector2:
	if typeof(value) == TYPE_ARRAY:
		var list: Array = value
		if list.size() >= 2:
			return Vector2(float(list[0]), float(list[1]))
	return fallback
