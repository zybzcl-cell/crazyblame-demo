class_name PotData
## 锅的图鉴与相位节奏表。
##
## 这里是整个游戏唯一的「数值真相」：
##   - POT_TYPES：五种锅的全部手感 / 伤害 / 解锁参数；
##   - PHASES：0~42 秒分成的五个阶段（热身 → 加速 → 混合 → 高压 → 疯狂甩锅时间），
##     每个阶段控制生成间隔、同屏数量、锅的存活时间、飘移速度、连击倍率与出哪种锅。

const PHASES := [
	{
		"name": "热身",
		"until": 10.0,
		"interval": 1.50,
		"max_alive": 1,
		"life_scale": 1.0,
		"speed_scale": 1.0,
		"combo_scale": 1.0,
		"weights": {"normal": 6, "broken": 2},
		"banner": "老板开始甩锅了",
		"line": "嘿嘿，这锅你背。",
	},
	{
		"name": "加速",
		"until": 20.0,
		"interval": 1.15,
		"max_alive": 3,
		"life_scale": 0.85,
		"speed_scale": 1.10,
		"combo_scale": 1.0,
		"weights": {"normal": 5, "broken": 3, "pan": 3},
		"banner": "锅开始多了",
		"line": "手快点，别掉地上。",
	},
	{
		"name": "混合",
		"until": 30.0,
		"interval": 0.95,
		"max_alive": 4,
		"life_scale": 0.72,
		"speed_scale": 1.22,
		"combo_scale": 1.0,
		"weights": {"normal": 4, "broken": 3, "pan": 3, "iron": 2, "pressure": 2},
		"banner": "各种锅一起上",
		"line": "这口也不小，你也接着。",
	},
	{
		"name": "高压",
		"until": 37.0,
		"interval": 0.78,
		"max_alive": 5,
		"life_scale": 0.60,
		"speed_scale": 1.34,
		"combo_scale": 1.15,
		"weights": {"normal": 3, "broken": 3, "pan": 3, "iron": 2, "pressure": 3},
		"banner": "压力拉满",
		"line": "今天谁也别想走。",
	},
	{
		"name": "疯狂甩锅",
		"until": 42.0,
		"interval": 0.55,
		"max_alive": 6,
		"life_scale": 0.50,
		"speed_scale": 1.50,
		"combo_scale": 1.5,
		"weights": {"normal": 3, "broken": 4, "pan": 3, "iron": 2, "pressure": 3},
		"banner": "疯狂甩锅时间！",
		"line": "别给老板留锅！",
	},
]

## 锅上的「锅话」（纯文案，甩起来更有代入感）
const BLAME_LINES := {
	"normal": ["这个你负责", "PPT 改一下", "先这样吧", "你看着办"],
	"iron": ["紧急需求", "今天上线", "通宵搞定"],
	"pan": ["客户又改了", "这个很简单", "五分钟的事"],
	"pressure": ["季度目标", "OKR 加一条", "成本砍一半"],
	"broken": ["顺手做了吧", "顺便加个功能", "很小的改动"],
}

const POT_TYPES := {
	"normal": {
		"id": "normal",
		"display_name": "普通锅",
		"tagline": "基础目标，最好抓也最好甩",
		"hint": "伤害低、速度普通，用来练手感与连击",
		"tint": Color("5b6472"),
		"tint_dark": Color("343a44"),
		"damage": 5,
		"base_score": 100,
		"difficulty": 1,
		"body_radius": 34.0,
		"grab_radius": 62.0,
		"drift_speed": 130.0,
		"drag_follow": 11.0,
		"hold_window": 3.2,
		"life_seconds": 8.5,
		"min_phase": 0,
	},
	"iron": {
		"id": "iron",
		"display_name": "铁锅",
		"tagline": "死沉，但砸下去最疼",
		"hint": "又大又慢很好抓，拖起来却明显迟钝，伤害 15",
		"tint": Color("2b2f36"),
		"tint_dark": Color("191c21"),
		"damage": 15,
		"base_score": 330,
		"difficulty": 3,
		"body_radius": 44.0,
		"grab_radius": 74.0,
		"drift_speed": 82.0,
		"drag_follow": 4.6,
		"hold_window": 3.6,
		"life_seconds": 10.5,
		"min_phase": 1,
		"unlock_stat": "total_hits",
		"unlock_target": 12,
		"unlock_label": "累计命中 12 口锅",
	},
	"pan": {
		"id": "pan",
		"display_name": "平底锅",
		"tagline": "飞得快，考验反应",
		"hint": "飘得快、存活短，跟手也快，伤害 8",
		"tint": Color("8d97a6"),
		"tint_dark": Color("5f6874"),
		"damage": 8,
		"base_score": 190,
		"difficulty": 3,
		"body_radius": 32.0,
		"grab_radius": 52.0,
		"drift_speed": 215.0,
		"drag_follow": 14.0,
		"hold_window": 2.4,
		"life_seconds": 6.5,
		"min_phase": 1,
	},
	"pressure": {
		"id": "pressure",
		"display_name": "压力锅",
		"tagline": "难抓，蓄满一次顶四口普通锅",
		"hint": "判定圈最小；握在手里蓄力，蓄满伤害 24",
		"tint": Color("77828f"),
		"tint_dark": Color("4b545f"),
		"damage": 6,
		"damage_charged": 24,
		"base_score": 210,
		"difficulty": 5,
		"body_radius": 36.0,
		"grab_radius": 46.0,
		"drift_speed": 112.0,
		"drag_follow": 8.5,
		"hold_window": 4.2,
		"life_seconds": 8.5,
		"min_phase": 2,
		"needs_charge": true,
		"charge_time": 1.15,
		"unlock_stat": "best_combo",
		"unlock_target": 10,
		"unlock_label": "一局打出 10 连击",
	},
	"broken": {
		"id": "broken",
		"display_name": "破锅",
		"tagline": "又小又快，连击发动机",
		"hint": "特别小、特别快，单次只 3 点伤害但一次涨 2 连击",
		"tint": Color("7d5a44"),
		"tint_dark": Color("55402f"),
		"damage": 3,
		"base_score": 95,
		"combo_step": 2,
		"difficulty": 2,
		"body_radius": 22.0,
		"grab_radius": 54.0,
		"drift_speed": 265.0,
		"drag_follow": 19.0,
		"hold_window": 1.9,
		"life_seconds": 6.0,
		"min_phase": 0,
	},
}

static var _catalog: Array[PotType] = []
static var _catalog_by_id: Dictionary = {}


## 五种锅的完整目录（顺序固定：普通 → 铁 → 平底 → 压力 → 破锅）
static func catalog() -> Array[PotType]:
	if _catalog.is_empty():
		for id in ["normal", "iron", "pan", "pressure", "broken"]:
			var pot := PotType.new(POT_TYPES[id])
			_catalog.append(pot)
			_catalog_by_id[id] = pot
	return _catalog


static func ids() -> Array:
	var list: Array = []
	for pot in catalog():
		list.append(pot.id)
	return list


static func get_pot(id: String) -> PotType:
	catalog()
	return _catalog_by_id.get(id, null)


static func has_pot(id: String) -> bool:
	catalog()
	return _catalog_by_id.has(id)


static func phase_count() -> int:
	return PHASES.size()


static func phase(index: int) -> Dictionary:
	return PHASES[clampi(index, 0, PHASES.size() - 1)]


## 第 elapsed 秒处于哪个相位（0 起）
static func phase_index_at(elapsed: float) -> int:
	for i in PHASES.size():
		if elapsed < float(PHASES[i]["until"]):
			return i
	return PHASES.size() - 1


## 某个相位里允许出现的锅（按解锁状态过滤），返回 id → 权重
static func spawn_weights(index: int, unlocked: Array) -> Dictionary:
	var result := {}
	var weights: Dictionary = phase(index)["weights"]
	for id in weights.keys():
		var pot_id := str(id)
		# 相位门槛 + 玩家自己的解锁进度，两个条件都要满足
		if index < get_pot(pot_id).min_phase:
			continue
		if not unlocked.is_empty() and not unlocked.has(pot_id):
			continue
		result[pot_id] = int(weights[id])
	if result.is_empty():
		result["normal"] = 1
	return result


## 按权重随机挑一口锅（rng 传入是为了测试可复现）
static func pick_type(index: int, unlocked: Array, rng: RandomNumberGenerator) -> String:
	var weights := spawn_weights(index, unlocked)
	var total := 0.0
	for id in weights.keys():
		total += float(weights[id])
	var roll := rng.randf() * total
	var picked := "normal"
	var keys := weights.keys()
	keys.sort()
	for id in keys:
		picked = str(id)
		roll -= float(weights[id])
		if roll <= 0.0:
			break
	return picked


## 给这口锅配一句「锅话」
static func blame_line(id: String, rng: RandomNumberGenerator) -> String:
	var lines: Array = BLAME_LINES.get(id, BLAME_LINES["normal"])
	return str(lines[rng.randi_range(0, lines.size() - 1)])
