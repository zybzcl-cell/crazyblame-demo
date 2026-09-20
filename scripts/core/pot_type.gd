class_name PotType
## 一口锅的「品种」：数值 + 手感参数 + 解锁条件。
##
## 五种锅不是换贴图，而是从**抓取难度 / 拖动速度 / 存活时间 / 伤害 / 得分**五个维度上真的不同，
## 所以玩法上的取舍是：
##   - 好抓的（铁锅）拖起来死沉，握着它就没手接别的锅；
##   - 好甩的（破锅 / 平底锅）跑得快、掉得快，单次伤害低但连击涨得快；
##   - 难抓又难甩的（压力锅）要蓄力，蓄满一次能顶四口普通锅。

var id: String = ""
var display_name: String = ""
var tagline: String = ""
var hint: String = ""
var tint: Color = Color.WHITE
var tint_dark: Color = Color.BLACK

## 伤害与得分
var damage: int = 0
## 蓄满之后的伤害（不需要蓄力的锅与 damage 相同）
var damage_charged: int = 0
var base_score: int = 0
## 每次命中涨多少连击（破锅涨 2，让「快速连击」真的更快）
var combo_step: int = 1
## 难度（1 最容易，5 最难），用于结算里统计「难度构成」
var difficulty: int = 1

## 手感：半径越大越好抓；grab_radius 是实际判定圈，故意可以和身体不一样大
var body_radius: float = 34.0
var grab_radius: float = 60.0
## 在场地里飘的基准速度（像素 / 秒，相位会再乘一个倍率）
var drift_speed: float = 130.0
## 被抓住之后跟随手指的「跟手程度」：越大越跟手，铁锅明显迟钝
var drag_follow: float = 11.0
## 手里握多久会滑掉（握太久要断连击，逼玩家快点甩）
var hold_window: float = 3.0
## 在场地里能待多久（不甩回去就「锅凉了」）
var life_seconds: float = 8.0
## 从第几个相位开始出现
var min_phase: int = 0
## 是否需要蓄力（压力锅）
var needs_charge: bool = false
var charge_time: float = 1.15

## 解锁条件：累计统计达到 unlock_target 就自动解锁（target 为 0 表示默认就有）
var unlock_stat: String = ""
var unlock_target: int = 0
var unlock_label: String = "默认解锁"


func _init(props: Dictionary) -> void:
	id = str(props.get("id", ""))
	display_name = str(props.get("display_name", id))
	tagline = str(props.get("tagline", ""))
	hint = str(props.get("hint", ""))
	tint = props.get("tint", Color.WHITE)
	tint_dark = props.get("tint_dark", tint.darkened(0.35))
	damage = int(props.get("damage", 0))
	damage_charged = int(props.get("damage_charged", damage))
	base_score = int(props.get("base_score", 100))
	combo_step = int(props.get("combo_step", 1))
	difficulty = int(props.get("difficulty", 1))
	body_radius = float(props.get("body_radius", 34.0))
	grab_radius = float(props.get("grab_radius", 60.0))
	drift_speed = float(props.get("drift_speed", 130.0))
	drag_follow = float(props.get("drag_follow", 11.0))
	hold_window = float(props.get("hold_window", 3.0))
	life_seconds = float(props.get("life_seconds", 8.0))
	min_phase = int(props.get("min_phase", 0))
	needs_charge = bool(props.get("needs_charge", false))
	charge_time = float(props.get("charge_time", 1.15))
	unlock_stat = str(props.get("unlock_stat", ""))
	unlock_target = int(props.get("unlock_target", 0))
	unlock_label = str(props.get("unlock_label", "默认解锁"))


## 默认解锁（不需要任何成绩）
func is_default_unlocked() -> bool:
	return unlock_target <= 0


## 这一口锅在当前蓄力比例下的伤害。不需要蓄力的锅直接返回固定伤害。
func damage_for(charge_ratio: float) -> int:
	if not needs_charge:
		return damage
	var ratio := clampf(charge_ratio, 0.0, 1.0)
	return int(round(lerpf(float(damage), float(damage_charged), ratio)))


## 蓄力是否已经「够用」（蓄满到 95% 以上算完美）
func is_charge_ready(charge_ratio: float) -> bool:
	return charge_ratio >= 0.95


## 得分基数：需要蓄力的锅按蓄力比例放大（没蓄力也能拿分，但差距明显）
func score_base_for(charge_ratio: float) -> float:
	if not needs_charge:
		return float(base_score)
	var ratio := clampf(charge_ratio, 0.0, 1.0)
	return float(base_score) * (0.7 + 0.9 * ratio)


## 结算 / 图鉴上显示的难度星星
func difficulty_stars() -> String:
	return "★".repeat(clampi(difficulty, 1, 5))
