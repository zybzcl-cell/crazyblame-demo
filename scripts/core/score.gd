class_name Score
## 计分与评级。
##
## 两条线分开算，避免「光看命中次数」：
##   - score_points：本局总分（几千分级别），命中越快、连击越高、锅越难、疯狂阶段越猛，分越高；
##   - rating_score：0~100 的综合评级分，由命中率 / 最高连击 / 伤害 / 疯狂阶段表现 / 锅的难度构成
##     五个维度加权得到，最后换算成 S/A/B/C/D。
## 所以「稳健高命中」和「狂甩低命中」不会拿到一样的分数，技术型玩家有明确的提升空间。

## 评级门槛（>= 就拿到该评级）
const GRADE_THRESHOLDS := {"S": 90, "A": 78, "B": 64, "C": 48}

## 各维度的满分（加起来 100）
const WEIGHT_ACCURACY := 34.0
const WEIGHT_COMBO := 18.0
const WEIGHT_DAMAGE := 22.0
const WEIGHT_FRENZY := 14.0
const WEIGHT_DIFFICULTY := 12.0

## 连击满分参考值与疯狂阶段命中参考值（用于把「越多越好」映射到 0~1）
const COMBO_REFERENCE := 24.0
const FRENZY_REFERENCE := 8.0


## 连击倍率：1 + 8% × 连击，上限 3.0，再乘相位倍率（疯狂甩锅时间 ×1.5），总上限 4.0
static func combo_multiplier(combo: int, combo_scale: float = 1.0) -> float:
	var base := minf(1.0 + 0.08 * float(maxi(combo, 0)), 3.0)
	return minf(base * maxf(combo_scale, 0.1), 4.0)


## 单次命中的总分。
##   pot           锅的类型
##   combo         命中之后的连击数（含这一次）
##   react_time    从这口锅出现到命中的秒数（越快越加分）
##   frenzy        是否处于「疯狂甩锅时间」
##   charge_ratio  蓄力比例（不需要蓄力的锅传 0 即可）
static func hit_points(
	pot: PotType, combo: int, react_time: float, frenzy: bool, charge_ratio: float = 0.0
) -> int:
	if pot == null:
		return 0
	var base := pot.score_base_for(charge_ratio)
	# 反应速度：2.5 秒内命中线性加分，最高 +35%
	var speed_bonus := 1.0 + clampf(1.0 - react_time / 2.5, 0.0, 1.0) * 0.35
	var combo_bonus := combo_multiplier(combo, 1.0)
	var phase_bonus := 1.5 if frenzy else 1.0
	var perfect := 1.2 if pot.needs_charge and pot.is_charge_ready(charge_ratio) else 1.0
	return int(round(base * speed_bonus * combo_bonus * phase_bonus * perfect))


## 综合评级。stats 至少包含：
##   hits / misses / best_combo / damage_dealt / frenzy_hits / pot_counts
static func rating(stats: Dictionary) -> Dictionary:
	var hits := maxi(int(stats.get("hits", 0)), 0)
	var misses := maxi(int(stats.get("misses", 0)), 0)
	var best_combo := maxi(int(stats.get("best_combo", 0)), 0)
	var damage := maxi(int(stats.get("damage_dealt", 0)), 0)
	var frenzy_hits := maxi(int(stats.get("frenzy_hits", 0)), 0)
	var attempts := hits + misses
	var accuracy := 0.0 if attempts <= 0 else float(hits) / float(attempts)

	var accuracy_part := accuracy * WEIGHT_ACCURACY
	var combo_part := minf(float(best_combo) / COMBO_REFERENCE, 1.0) * WEIGHT_COMBO
	var damage_part := minf(
		float(damage) / float(GameConfig.BOSS_MAX_HP), 1.0) * WEIGHT_DAMAGE
	var frenzy_part := minf(float(frenzy_hits) / FRENZY_REFERENCE, 1.0) * WEIGHT_FRENZY
	var difficulty_part := difficulty_ratio(stats.get("pot_counts", {})) * WEIGHT_DIFFICULTY

	var total := accuracy_part + combo_part + damage_part + frenzy_part + difficulty_part
	# 一口都没甩中：再怎么算也不该有分
	if hits <= 0:
		total = 0.0
	var score := clampi(int(round(total)), 0, 100)
	return {
		"score": score,
		"grade": grade_for(score),
		"accuracy": accuracy,
		"parts": {
			"accuracy": roundf(accuracy_part),
			"combo": roundf(combo_part),
			"damage": roundf(damage_part),
			"frenzy": roundf(frenzy_part),
			"difficulty": roundf(difficulty_part),
		},
	}


## 锅的难度构成：全打普通锅拿不满，敢接铁锅 / 压力锅才有这部分的满分
static func difficulty_ratio(pot_counts: Dictionary) -> float:
	var hits := 0
	var weight := 0.0
	for id in pot_counts.keys():
		var pot := PotData.get_pot(str(id))
		if pot == null:
			continue
		var count := maxi(int(pot_counts[id]), 0)
		hits += count
		weight += float(count) * float(pot.difficulty)
	if hits <= 0:
		return 0.0
	var average := weight / float(hits)
	# 难度 1（普通锅）→ 0 分，难度 5（压力锅）→ 满分
	return clampf((average - 1.0) / 4.0, 0.0, 1.0)


static func grade_for(score: int) -> String:
	if score >= int(GRADE_THRESHOLDS["S"]):
		return "S"
	if score >= int(GRADE_THRESHOLDS["A"]):
		return "A"
	if score >= int(GRADE_THRESHOLDS["B"]):
		return "B"
	if score >= int(GRADE_THRESHOLDS["C"]):
		return "C"
	return "D"


static func grade_color(grade: String) -> Color:
	match grade:
		"S":
			return Palette.ACCENT
		"A":
			return Palette.OK
		"B":
			return Palette.INFO
		"C":
			return Palette.UI_TEXT_DIM
		_:
			return Palette.DANGER


static func grade_title(grade: String) -> String:
	match grade:
		"S":
			return "甩锅之神"
		"A":
			return "甩锅高手"
		"B":
			return "熟练背锅侠"
		"C":
			return "手忙脚乱"
		_:
			return "被锅甩了一脸"
