class_name GameConfig
## 全局常量：节奏、老板血量、场景路径、音效表。
##
## 玩法数值刻意只放在这里 + pot_data.gd，测试可以对着这些常量写断言，
## 以后调平衡不用满项目找数字。

# ---- 场景
const MENU_SCENE := "res://scenes/main_menu.tscn"
const GAME_SCENE := "res://scenes/game.tscn"
const RESULT_CARD_SCENE := "res://scenes/result_card.tscn"

# ---- 存档
const SAVE_PATH := "user://crazy_blame_save.json"

# ---- 单局节奏：3 秒准备 + 42 秒正式游戏 ≈ 45 秒一局
const COUNTDOWN_SECONDS := 3.0
const PLAY_SECONDS := 42.0
## 时间到 / 老板崩溃之后，隔多久弹结算卡（留时间播动画与音效）
const RESULT_DELAY := 0.9
const KO_RESULT_DELAY := 1.6

# ---- 老板
## 老板的精神状态上限。
## 平衡参考（tools/balance_report.gd）：熟练的模拟玩家一局约 250 伤害，
## 也就是能打到「疲惫崩溃」但常常差一点打趴；只有又快、又敢接铁锅 / 压力锅、
## 连击不断的一局才能真的把老板打到趴桌（提前结束，拿到额外奖励）。
const BOSS_MAX_HP := 260
## 老板受击判定圈改成「跟着老板大小走」，具体比例写在 scripts/core/layout_data.gd

# ---- 操作
## 甩出去需要的最小滑动速度（像素 / 秒），低于这个值算「轻轻放下」
const FLICK_MIN_SPEED := 620.0
## 甩回老板时允许的方向误差（弧度，约 62°）
const FLICK_ANGLE_TOLERANCE := 1.08
## 甩出的锅飞向老板的速度倍率
const FLICK_SPEED_FACTOR := 1.35
## 甩出的锅最长飞行时间，超时算甩歪
const THROWN_LIFETIME := 1.2

# ---- 连击台词（连击数 → 台词），达到即播一次
const COMBO_SHOUTS := [
	{"combo": 3, "text": "甩得漂亮！"},
	{"combo": 5, "text": "继续甩！"},
	{"combo": 8, "text": "老板开始慌了！"},
	{"combo": 12, "text": "别给老板留锅！"},
	{"combo": 16, "text": "锅锅到肉！"},
	{"combo": 20, "text": "老板：我错了！"},
	{"combo": 26, "text": "甩锅之神！"},
]

# ---- 音效（全部由 tools/generate_sfx.gd 本地合成，无第三方素材）
const SOUNDS := {
	"ui_click": "res://assets/audio/ui_click.wav",
	"ui_start": "res://assets/audio/ui_start.wav",
	"countdown": "res://assets/audio/countdown.wav",
	"go": "res://assets/audio/go.wav",
	"grab": "res://assets/audio/grab.wav",
	"throw_back": "res://assets/audio/throw_back.wav",
	"hit_light": "res://assets/audio/hit_light.wav",
	"hit_medium": "res://assets/audio/hit_medium.wav",
	"hit_heavy": "res://assets/audio/hit_heavy.wav",
	"hit_crit": "res://assets/audio/hit_crit.wav",
	"combo": "res://assets/audio/combo.wav",
	"miss": "res://assets/audio/miss.wav",
	"slip": "res://assets/audio/slip.wav",
	"escape": "res://assets/audio/escape.wav",
	"boss_stage": "res://assets/audio/boss_stage.wav",
	"phase_up": "res://assets/audio/phase_up.wav",
	"boss_ko": "res://assets/audio/boss_ko.wav",
	"frenzy": "res://assets/audio/frenzy.wav",
	"result": "res://assets/audio/result.wav",
	"new_record": "res://assets/audio/new_record.wav",
	"unlock": "res://assets/audio/unlock.wav",
	# 老板受击「惨叫」：按锅的类型区分，全部是本地合成的卡通化人声占位
	# （不是真实人声素材，也永远不会从网络下载任何资源）。
	"voice_normal": "res://assets/audio/voice_normal.wav",
	"voice_iron": "res://assets/audio/voice_iron.wav",
	"voice_pan": "res://assets/audio/voice_pan.wav",
	"voice_pressure": "res://assets/audio/voice_pressure.wav",
	"voice_broken": "res://assets/audio/voice_broken.wav",
	"voice_panic": "res://assets/audio/voice_panic.wav",
}

# ---- 老板受击语音 -----------------------------------------------------------
## 不同锅 → 不同惨叫。文案只是「这句惨叫想表达什么」，实际播放的是同名的卡通合成音。
const POT_VOICES := {
	"normal": {"sound": "voice_normal", "text": "哎哟！"},
	"iron": {"sound": "voice_iron", "text": "啊——！"},
	"pan": {"sound": "voice_pan", "text": "疼疼疼！"},
	"pressure": {"sound": "voice_pressure", "text": "我的头！"},
	"broken": {"sound": "voice_broken", "text": "你干什么！"},
}

## 连击越高，老板越慌：到点播一次「慌乱惨叫」并在操作区打一行字
const BOSS_PANIC := [
	{"combo": 3, "sound": "voice_panic", "text": "等等！"},
	{"combo": 6, "sound": "voice_panic", "text": "别打了！"},
	{"combo": 10, "sound": "voice_panic", "text": "别甩了！"},
	{"combo": 15, "sound": "voice_panic", "text": "我错了！"},
]

# ---- 文案
const READY_HINT := "点击锅 → 拖到老板身上 → 甩回去！"
const READY_TITLE := "老板开始甩锅了"
const KO_BANNER := "老板崩溃了！"
const TIMEUP_BANNER := "时间到！"


## 音效文件根目录（测试检查资源是否齐全时用）
static func sound_keys() -> Array:
	var keys := SOUNDS.keys()
	keys.sort()
	return keys


## 这口锅对应的受击惨叫（找不到就退回普通锅的）
static func voice_for_pot(pot_id: String) -> Dictionary:
	return POT_VOICES.get(pot_id, POT_VOICES["normal"])
