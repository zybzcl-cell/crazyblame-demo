extends Node
## 音效播放（Autoload：AudioManager）。
##
## 音效文件全部由 tools/generate_sfx.gd 本地合成（见 THIRD_PARTY.md），没有任何第三方素材。
## 播放策略：
##   - 固定的小池子（不每次新建 AudioStreamPlayer）；
##   - 同一音效有最小间隔与随机音高，连续命中不会糊成一片；
##   - 连击音效随连击数升调（play_combo），让「越连越爽」有听感；
##   - --headless（自动化测试）用的是 Dummy 音频驱动，直接跳过播放，
##     这样既听不到声音也不会在退出时留下播放中的资源。

const VOICE_COUNT := 12

## 同一音效的最小触发间隔（秒）
const THROTTLE := {
	"hit_light": 0.04,
	"hit_medium": 0.04,
	"combo": 0.05,
	"grab": 0.05,
	"miss": 0.10,
	"escape": 0.10,
	"slip": 0.12,
	"countdown": 0.10,
	"ui_click": 0.05,
}

## 随机音高幅度（±比例）
const PITCH_VARIATION := {
	"grab": 0.10,
	"throw_back": 0.08,
	"hit_light": 0.10,
	"hit_medium": 0.08,
	"hit_heavy": 0.06,
	"pot_escape": 0.06,
	"miss": 0.06,
	"combo": 0.03,
	"ui_click": 0.04,
}

var _players: Array[AudioStreamPlayer] = []
var _streams := {}
var _last_played := {}
var _rng := RandomNumberGenerator.new()
var _audio_available := true
## 已经播放过的音效次数（测试用：可以确认「命中真的有声音」）
var play_counts := {}


func _ready() -> void:
	_rng.randomize()
	_audio_available = AudioServer.get_driver_name() != "Dummy"
	for i in VOICE_COUNT:
		var player := AudioStreamPlayer.new()
		# 音效不受暂停影响：结算时音效照样放完，退出时也不会有残留
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_players.append(player)
	_load_streams()


func _load_streams() -> void:
	for key in GameConfig.SOUNDS.keys():
		var path := str(GameConfig.SOUNDS[key])
		if ResourceLoader.exists(path):
			_streams[key] = load(path)


## 玩家在设置里关掉声音之后，这里直接不播（headless 下同样跳过）
func is_muted() -> bool:
	var progress := get_tree().root.get_node_or_null("ProgressManager")
	if progress != null and not bool(progress.sound_enabled()):
		return true
	return false


func play(key: String, pitch: float = 1.0) -> void:
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		return
	play_counts[key] = int(play_counts.get(key, 0)) + 1
	if not _audio_available or is_muted():
		return
	var now := float(Time.get_ticks_msec()) / 1000.0
	var throttle := float(THROTTLE.get(key, 0.0))
	if throttle > 0.0 and now - float(_last_played.get(key, -999.0)) < throttle:
		return
	_last_played[key] = now
	for player in _players:
		if not player.playing:
			player.stream = stream
			var variation := float(PITCH_VARIATION.get(key, 0.0))
			player.pitch_scale = maxf(
				(1.0 + _rng.randf_range(-variation, variation)) * pitch, 0.05)
			player.play()
			return


## 连击音效：连击越高音越高（最高约 2 倍）
func play_combo(combo: int) -> void:
	var pitch := clampf(1.0 + float(maxi(combo, 0)) * 0.055, 1.0, 2.0)
	play("combo", pitch)


func has_sound(key: String) -> bool:
	return _streams.has(key)


func sound_count() -> int:
	return _streams.size()


func audio_available() -> bool:
	return _audio_available


func played_count(key: String) -> int:
	return int(play_counts.get(key, 0))


func reset_play_counts() -> void:
	play_counts.clear()


func stop_all() -> void:
	for player in _players:
		if player.playing:
			player.stop()


## 退出前把流引用松开：否则引擎会统计「退出时仍在使用的资源」并给出告警
func _exit_tree() -> void:
	stop_all()
	for player in _players:
		player.stream = null
	_streams.clear()
