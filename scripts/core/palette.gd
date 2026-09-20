class_name Palette
## 全局配色。
##
## 集中在一个文件里是为了让「办公室」这套视觉语言统一：墙面是冷灰蓝、木桌是暖棕、
## 老板是深蓝西装 + 金色强调、锅按类型用不同金属色，反馈色（伤害 / 连击 / 警示）单独一套。
## 以后换成正式美术时，先改这里就能整体变色。

# ---- 办公室
const WALL := Color("2f3742")
const WALL_LIGHT := Color("3b4552")
const WALL_TRIM := Color("232a33")
## 地板：暖色木地板，比墙面亮，让深色的锅在操作区里更清楚
const FLOOR := Color("8a6a4a")
const FLOOR_DARK := Color("6d5238")
const DESK := Color("7a5a3c")
const DESK_DARK := Color("5f452d")
const DESK_TOP := Color("8d6a48")
const WINDOW_GLASS := Color("3d5a78")
const WINDOW_FRAME := Color("cfd8e3")
const PLANT := Color("4e8a52")

# ---- 老板
const BOSS_SUIT := Color("2c3a55")
const BOSS_SUIT_DARK := Color("212b40")
const BOSS_SHIRT := Color("e8edf5")
const BOSS_TIE := Color("c8443c")
const BOSS_SKIN := Color("f6d3b4")
const BOSS_SKIN_HOT := Color("f7bfa0")
const BOSS_HAIR := Color("26232a")
const BOSS_INK := Color("211f24")

# ---- 界面
const UI_TEXT := Color("e9eef5")
const UI_TEXT_DIM := Color("a9b4c2")
const ACCENT := Color("ffc857")
const ACCENT_DEEP := Color("e2a02c")
const PANEL := Color("222833")
const PANEL_LIGHT := Color("2c333f")
const PANEL_EDGE := Color("3e4856")
const OK := Color("58c46a")
const DANGER := Color("e2574c")
const INFO := Color("6ec1e4")

# ---- 锅 / 反馈
const POT_METAL := Color("525a66")
const POT_METAL_DARK := Color("343a44")
const POT_IRON := Color("2b2f36")
const POT_IRON_RIM := Color("4a515c")
const POT_STEEL := Color("8d97a6")
const POT_RUST := Color("7d5a44")
const SOUP := Color("c9762f")
const BLAIM := Color("ff8a5b")
const DAMAGE_TEXT := Color("ffe08a")
const COMBO_TEXT := Color("ffc857")
const HEAVY_TEXT := Color("ff6b6b")
const CRIT_TEXT := Color("ff9f43")
const MISS_TEXT := Color("9aa6b5")


## 血量条颜色：绿 → 黄 → 红（老板精神状态越差越红）
static func health_color(ratio: float) -> Color:
	if ratio > 0.6:
		return OK
	if ratio > 0.3:
		return ACCENT
	return DANGER
