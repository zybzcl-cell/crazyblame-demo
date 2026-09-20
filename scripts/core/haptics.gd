extends Node
## 震动反馈（Autoload：Haptics）。
##
## 手机上用 Input.vibrate_handheld，桌面（macOS / Windows / Linux）静默不做事。
## 为了让自动化测试也能验证「该震的时候震了」，这里记了一个计数器。

var enabled := true
var vibration_count := 0
var last_duration_ms := 0


func _ready() -> void:
	var progress := get_tree().root.get_node_or_null("ProgressManager")
	if progress != null:
		enabled = bool(progress.vibration_enabled())


## 设置面板调用
func set_enabled(value: bool) -> void:
	enabled = value


## 轻触（抓锅、按钮）
func light() -> void:
	_vibrate(10)


## 命中
func medium() -> void:
	_vibrate(22)


## 重击 / 老板阶段变化
func heavy() -> void:
	_vibrate(40)


## 移动端才有真正的震动；桌面只记数
func _vibrate(duration_ms: int) -> void:
	if not enabled:
		return
	vibration_count += 1
	last_duration_ms = duration_ms
	if OS.has_feature("mobile") or OS.get_name() == "Android" or OS.get_name() == "iOS":
		Input.vibrate_handheld(duration_ms)
