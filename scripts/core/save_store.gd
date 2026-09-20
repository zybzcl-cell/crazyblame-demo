class_name SaveStore
## 本地存档的读写与清洗：只做「数据 ↔ 文件」，不含任何玩法规则。
##
## 三个原则：
##   1. 只用 Godot 原生 FileAccess + JSON，存档是人能看懂的明文；
##   2. **存档坏了也绝不崩**：读不出来、类型不对、字段缺失一律退回安全值；
##   3. 字段只增不减，多出来的旧字段 / 新字段都忽略，方便以后加功能（联网、排行榜…）。

const SAVE_VERSION := 1

## 读存档遇到问题时是否 push_warning。
## 测试会故意制造坏存档，可以先把它关掉，避免「故意触发的告警」污染测试输出。
static var warn_on_error := true


static func _warn(message: String) -> void:
	if warn_on_error:
		push_warning(message)


## 全新存档
static func default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"best_score": 0,
		"best_rating": 0,
		"best_grade": "",
		"best_combo": 0,
		"total_games": 0,
		"total_hits": 0,
		"total_misses": 0,
		"total_returned": 0,
		"total_damage": 0,
		"total_play_seconds": 0.0,
		"unlocked_pots": [],
		"disabled_pots": [],
		"pot_hits": {},
		"sound_enabled": true,
		"vibration_enabled": true,
		"last_played_at": "",
	}


static func load_data(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return default_data()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_warn("存档打不开（%s），按新档处理。" % path)
		return default_data()
	var text := file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		_warn("存档是空的（%s），按新档处理。" % path)
		return default_data()
	# 用 JSON 实例解析：内容坏了只会返回错误码，不会像 JSON.parse_string 那样往控制台打引擎错误
	var json := JSON.new()
	var error := json.parse(text)
	if error != OK or typeof(json.data) != TYPE_DICTIONARY:
		_warn("存档不是 JSON 对象（%s），按新档处理。" % path)
		return default_data()
	return sanitize(json.data)


static func save_data(path: String, data: Dictionary) -> bool:
	var directory := path.get_base_dir()
	if not directory.is_empty() and not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_warn("存档写不进去（%s），这一局的成绩没有落盘。" % path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


static func delete_data(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(path) == OK


## 把任意读进来的数据整理成合法存档
static func sanitize(raw: Dictionary) -> Dictionary:
	var result := default_data()
	result["version"] = maxi(_as_int(raw.get("version"), 0), 0)
	result["best_score"] = maxi(_as_int(raw.get("best_score"), 0), 0)
	result["best_rating"] = clampi(_as_int(raw.get("best_rating"), 0), 0, 100)
	result["best_grade"] = _as_grade(raw.get("best_grade"))
	result["best_combo"] = maxi(_as_int(raw.get("best_combo"), 0), 0)
	result["total_games"] = maxi(_as_int(raw.get("total_games"), 0), 0)
	result["total_hits"] = maxi(_as_int(raw.get("total_hits"), 0), 0)
	result["total_misses"] = maxi(_as_int(raw.get("total_misses"), 0), 0)
	result["total_returned"] = maxi(_as_int(raw.get("total_returned"), 0), 0)
	result["total_damage"] = maxi(_as_int(raw.get("total_damage"), 0), 0)
	result["total_play_seconds"] = maxf(_as_float(raw.get("total_play_seconds"), 0.0), 0.0)
	result["unlocked_pots"] = _as_pot_array(raw.get("unlocked_pots"))
	result["disabled_pots"] = _as_pot_array(raw.get("disabled_pots"))
	result["pot_hits"] = _as_count_dictionary(raw.get("pot_hits"))
	result["sound_enabled"] = _as_bool(raw.get("sound_enabled"), true)
	result["vibration_enabled"] = _as_bool(raw.get("vibration_enabled"), true)
	result["last_played_at"] = str(raw.get("last_played_at", "")) \
		if typeof(raw.get("last_played_at", "")) == TYPE_STRING else ""
	return result


# ---------------------------------------------------------------- 内部：安全取值

static func _as_int(value: Variant, fallback: int) -> int:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return int(value)
		TYPE_STRING:
			var text := str(value)
			return int(text) if text.is_valid_int() else fallback
	return fallback


static func _as_float(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		TYPE_STRING:
			var text := str(value)
			return float(text) if text.is_valid_float() else fallback
	return fallback


static func _as_bool(value: Variant, fallback: bool) -> bool:
	match typeof(value):
		TYPE_BOOL:
			return bool(value)
		TYPE_INT, TYPE_FLOAT:
			return int(value) != 0
	return fallback


## 评级的字母只认 A~D 与 S（其它内容一律丢掉，避免脏存档把界面弄乱）
static func _as_grade(value: Variant) -> String:
	var text := str(value) if typeof(value) == TYPE_STRING else ""
	return text if ["S", "A", "B", "C", "D"].has(text) else ""


## 锅的 id 列表：去重 + 只保留图鉴里存在的锅
static func _as_pot_array(value: Variant) -> Array:
	var result: Array = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item in value:
		if typeof(item) != TYPE_STRING:
			continue
		var id := str(item)
		if result.has(id) or not PotData.has_pot(id):
			continue
		result.append(id)
	return result


## {"normal": 12, "iron": 3}
static func _as_count_dictionary(value: Variant) -> Dictionary:
	var result := {}
	if typeof(value) != TYPE_DICTIONARY:
		return result
	for key in (value as Dictionary).keys():
		if typeof(key) != TYPE_STRING or not PotData.has_pot(str(key)):
			continue
		var count := _as_int((value as Dictionary)[key], 0)
		if count <= 0:
			continue
		result[str(key)] = count
	return result
