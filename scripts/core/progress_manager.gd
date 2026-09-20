extends Node
## 进度与存档规则（Autoload：ProgressManager）。
##
## 存档读写本身在 SaveStore 里，这里只管「规则」：
##   - 每局结束累加统计（局数 / 命中 / 失误 / 伤害 / 甩回的锅数 / 时长）；
##   - 刷新最高分、最高连击、最高评级；
##   - 按累计成绩解锁新的锅（铁锅、压力锅），解锁条件写在 PotData 里；
##   - 玩家可以把解锁过的锅临时停用（玩法选择，而不是数值养成）；
##   - 声音 / 震动开关。
##
## 测试可以把 save_path 指到临时文件再 reload()，不影响真实存档。

signal progress_changed

var save_path: String = GameConfig.SAVE_PATH
var last_error: String = ""

var _data: Dictionary = {}


func _ready() -> void:
	reload()


func reload(new_path: String = "") -> void:
	if not new_path.is_empty():
		save_path = new_path
	_data = SaveStore.load_data(save_path)
	last_error = ""
	refresh_unlocks()
	progress_changed.emit()


func save_now() -> bool:
	var ok := SaveStore.save_data(save_path, _data)
	last_error = "" if ok else "存档写入失败：%s" % save_path
	return ok


# ---------------------------------------------------------------- 读数据

func best_score() -> int:
	return int(_data["best_score"])


func best_rating() -> int:
	return int(_data["best_rating"])


func best_grade() -> String:
	return str(_data["best_grade"])


func best_combo() -> int:
	return int(_data["best_combo"])


func total_games() -> int:
	return int(_data["total_games"])


func total_hits() -> int:
	return int(_data["total_hits"])


func total_misses() -> int:
	return int(_data["total_misses"])


func total_returned() -> int:
	return int(_data["total_returned"])


func total_damage() -> int:
	return int(_data["total_damage"])


func total_play_seconds() -> float:
	return float(_data["total_play_seconds"])


func pot_hits(id: String) -> int:
	return int((_data["pot_hits"] as Dictionary).get(id, 0))


## 累计准确率（一次都没打过时返回 0）
func accuracy() -> float:
	var attempts := total_hits() + total_misses()
	if attempts <= 0:
		return 0.0
	return float(total_hits()) / float(attempts)


func last_played_at() -> String:
	return str(_data["last_played_at"])


## 某个统计的当前值（解锁条件用字符串引用统计，方便以后加新条件）
func stat_value(stat: String) -> int:
	match stat:
		"total_hits":
			return total_hits()
		"total_misses":
			return total_misses()
		"total_returned":
			return total_returned()
		"total_games":
			return total_games()
		"total_damage":
			return total_damage()
		"best_combo":
			return best_combo()
		"best_score":
			return best_score()
		"best_rating":
			return best_rating()
	return 0


# ---------------------------------------------------------------- 锅的解锁与启用

func is_pot_unlocked(id: String) -> bool:
	if not PotData.has_pot(id):
		return false
	var pot := PotData.get_pot(id)
	if pot.is_default_unlocked():
		return true
	if (_data["unlocked_pots"] as Array).has(id):
		return true
	return stat_value(pot.unlock_stat) >= pot.unlock_target


## 所有已解锁的锅（按图鉴顺序）
func unlocked_pots() -> Array:
	var result: Array = []
	for pot in PotData.catalog():
		if is_pot_unlocked(pot.id):
			result.append(pot.id)
	return result


func is_pot_enabled(id: String) -> bool:
	if not is_pot_unlocked(id):
		return false
	return not (_data["disabled_pots"] as Array).has(id)


## 实际会出现在游戏里的锅（已解锁且没被玩家停用）
func enabled_pots() -> Array:
	var result: Array = []
	for pot in PotData.catalog():
		if is_pot_enabled(pot.id):
			result.append(pot.id)
	if result.is_empty():
		result.append("normal")
	return result


func set_pot_enabled(id: String, enabled: bool) -> void:
	if not is_pot_unlocked(id):
		return
	var disabled: Array = _data["disabled_pots"]
	if enabled:
		disabled.erase(id)
	else:
		# 至少留一口锅，否则没法开局
		if enabled_pots().size() <= 1 and enabled_pots().has(id):
			return
		if not disabled.has(id):
			disabled.append(id)
	_data["disabled_pots"] = disabled
	save_now()
	progress_changed.emit()


## 解锁进度（图鉴上的进度条用）
func unlock_progress(id: String) -> Dictionary:
	var pot := PotData.get_pot(id)
	if pot == null:
		return {"label": "", "current": 0, "target": 0, "unlocked": false, "ratio": 1.0}
	var target := pot.unlock_target
	var current := stat_value(pot.unlock_stat) if target > 0 else 0
	var unlocked := is_pot_unlocked(id)
	var ratio := 1.0 if unlocked or target <= 0 else clampf(float(current) / float(target), 0.0, 1.0)
	return {
		"label": pot.unlock_label,
		"current": current,
		"target": target,
		"unlocked": unlocked,
		"ratio": ratio,
	}


## 依照当前统计刷新解锁名单，返回这次**新**解锁的锅（结算页要弹提示）
func refresh_unlocks() -> Array:
	var fresh: Array = []
	for pot in PotData.catalog():
		if pot.is_default_unlocked():
			continue
		if (_data["unlocked_pots"] as Array).has(pot.id):
			continue
		if stat_value(pot.unlock_stat) >= pot.unlock_target and pot.unlock_target > 0:
			(_data["unlocked_pots"] as Array).append(pot.id)
			fresh.append(pot.id)
	if not fresh.is_empty():
		save_now()
	return fresh


# ---------------------------------------------------------------- 设置

func sound_enabled() -> bool:
	return bool(_data["sound_enabled"])


func set_sound_enabled(enabled: bool) -> void:
	_data["sound_enabled"] = enabled
	save_now()
	progress_changed.emit()


func vibration_enabled() -> bool:
	return bool(_data["vibration_enabled"])


func set_vibration_enabled(enabled: bool) -> void:
	_data["vibration_enabled"] = enabled
	save_now()
	progress_changed.emit()


# ---------------------------------------------------------------- 一局结束后登记成绩

## 登记一局结果，返回这一局带来的变化：
##   {"new_best": bool, "previous_best": int, "unlocked": [id], "improved_rating": bool}
func register_game(result: Dictionary) -> Dictionary:
	var previous_best := best_score()
	var previous_combo := best_combo()
	var previous_rating := best_rating()
	var score := maxi(int(result.get("score_points", 0)), 0)
	var combo := maxi(int(result.get("best_combo", 0)), 0)
	var rating := clampi(int(result.get("rating_score", 0)), 0, 100)
	var grade := str(result.get("rating_grade", ""))
	var hits := maxi(int(result.get("hits", 0)), 0)
	var misses := maxi(int(result.get("misses", 0)), 0)
	var damage := maxi(int(result.get("damage_dealt", 0)), 0)
	var duration := maxf(float(result.get("duration", 0.0)), 0.0)

	_data["total_games"] = total_games() + 1
	_data["total_hits"] = total_hits() + hits
	_data["total_misses"] = total_misses() + misses
	_data["total_returned"] = total_returned() + int(result.get("throws", hits))
	_data["total_damage"] = total_damage() + damage
	_data["total_play_seconds"] = total_play_seconds() + duration
	_data["best_score"] = maxi(previous_best, score)
	_data["best_combo"] = maxi(previous_combo, combo)
	_data["best_rating"] = maxi(previous_rating, rating)
	if rating > previous_rating and grade != "":
		_data["best_grade"] = grade
	var per_type: Dictionary = result.get("pot_counts", {})
	var hits_by_type: Dictionary = _data["pot_hits"]
	for id in per_type.keys():
		var pot_id := str(id)
		if not PotData.has_pot(pot_id):
			continue
		hits_by_type[pot_id] = int(hits_by_type.get(pot_id, 0)) + maxi(int(per_type[id]), 0)
	_data["pot_hits"] = hits_by_type
	_data["last_played_at"] = Time.get_datetime_string_from_system(false, true)

	var unlocked := refresh_unlocks()
	save_now()
	progress_changed.emit()
	return {
		"new_best": score > previous_best,
		"previous_best": previous_best,
		"unlocked": unlocked,
		"improved_rating": rating > previous_rating,
	}


## 清空全部进度（设置里的「清除记录」）
func reset_progress() -> void:
	_data = SaveStore.default_data()
	save_now()
	progress_changed.emit()


## 菜单上要显示的一行摘要
func summary() -> Dictionary:
	return {
		"best_score": best_score(),
		"best_grade": best_grade(),
		"best_combo": best_combo(),
		"best_rating": best_rating(),
		"games": total_games(),
		"hits": total_hits(),
		"returned": total_returned(),
		"accuracy": accuracy(),
	}
