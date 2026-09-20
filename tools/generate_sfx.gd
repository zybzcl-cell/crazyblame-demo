extends Node
## 音效生成工具：《疯狂甩锅》的全部音效都在这里**本地合成**，不下载任何第三方素材。
##
## 运行方式（会覆盖 assets/audio/ 下的同名文件）：
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path <项目目录> res://tools/generate_sfx.tscn
##
## 每个音效都是 16 bit / 44.1kHz / 单声道 WAV，0.05 ~ 1.0 秒，
## 结尾有 3 毫秒淡出，避免播放时爆音；噪声用固定种子，保证每次生成结果一致。

const SAMPLE_RATE := 44100
const OUT_DIR := "res://assets/audio"
## 统一峰值（留出余量，多个音效叠加时不削波）
const PEAK := 0.62
const NOISE_SEED := 20260916


func _ready() -> void:
	var root := DirAccess.open("res://")
	if root != null and not root.dir_exists("assets/audio"):
		root.make_dir_recursive("assets/audio")
	var sounds := {
		"ui_click": _ui_click(),
		"ui_start": _ui_start(),
		"countdown": _countdown(),
		"go": _go(),
		"grab": _grab(),
		"throw_back": _throw_back(),
		"hit_light": _hit_light(),
		"hit_medium": _hit_medium(),
		"hit_heavy": _hit_heavy(),
		"hit_crit": _hit_crit(),
		"combo": _combo(),
		"miss": _miss(),
		"slip": _slip(),
		"escape": _escape(),
		"boss_stage": _boss_stage(),
		"phase_up": _phase_up(),
		"boss_ko": _boss_ko(),
		"frenzy": _frenzy(),
		"result": _result(),
		"new_record": _new_record(),
		"unlock": _unlock(),
	}
	var failed := 0
	for key in sounds.keys():
		var path := "%s/%s.wav" % [OUT_DIR, key]
		var err: int = (sounds[key] as AudioStreamWAV).save_to_wav(path)
		if err != OK:
			failed += 1
		print("生成 %s → %s" % [path, "成功" if err == OK else "失败(%d)" % err])
	print("===== 音效生成：%d 个成功，%d 个失败 =====" % [sounds.size() - failed, failed])
	get_tree().quit(0 if failed == 0 else 1)


# ---------------------------------------------------------------- 音效设计

## 界面点击：短促清脆
func _ui_click() -> AudioStreamWAV:
	var buf := _buffer(0.07)
	_tone(buf, 0.0, 0.06, 1250.0, 720.0, 0.7, "square", 0.001, 2.6)
	_noise(buf, 0.0, 0.02, 0.25, 0.001, 3.0, 4000.0, 2000.0)
	return _to_stream(buf)


## 开始游戏：两音上行
func _ui_start() -> AudioStreamWAV:
	var buf := _buffer(0.45)
	_tone(buf, 0.0, 0.16, 523.25, 523.25, 0.6, "triangle", 0.006, 1.8)
	_tone(buf, 0.13, 0.28, 659.25, 880.0, 0.65, "triangle", 0.008, 1.6)
	_tone(buf, 0.13, 0.28, 329.63, 440.0, 0.30, "sine", 0.01, 1.4)
	return _to_stream(buf)


## 倒计时滴答
func _countdown() -> AudioStreamWAV:
	var buf := _buffer(0.18)
	_tone(buf, 0.0, 0.14, 880.0, 880.0, 0.55, "sine", 0.004, 2.2)
	_noise(buf, 0.0, 0.03, 0.25, 0.001, 2.8, 6000.0, 3000.0)
	return _to_stream(buf)


## 开甩：明亮的大三和弦
func _go() -> AudioStreamWAV:
	var buf := _buffer(0.5)
	for freq in [659.25, 830.61, 987.77]:
		_tone(buf, 0.0, 0.42, freq, freq * 1.02, 0.45, "triangle", 0.006, 1.6)
	_tone(buf, 0.0, 0.30, 220.0, 440.0, 0.28, "saw", 0.004, 1.4)
	_noise(buf, 0.0, 0.10, 0.20, 0.002, 2.4, 1200.0, 4000.0)
	return _to_stream(buf)


## 抓住锅：软软的「啵」
func _grab() -> AudioStreamWAV:
	var buf := _buffer(0.10)
	_tone(buf, 0.0, 0.09, 260.0, 520.0, 0.55, "sine", 0.006, 2.0)
	_tone(buf, 0.0, 0.04, 900.0, 600.0, 0.18, "triangle", 0.002, 2.6)
	return _to_stream(buf)


## 甩出去：风声 + 上扬
func _throw_back() -> AudioStreamWAV:
	var buf := _buffer(0.28)
	_noise(buf, 0.0, 0.26, 0.65, 0.02, 1.6, 500.0, 3200.0)
	_tone(buf, 0.0, 0.20, 300.0, 900.0, 0.30, "triangle", 0.01, 1.8)
	return _to_stream(buf)


## 轻命中：小铁片「铛」
func _hit_light() -> AudioStreamWAV:
	var buf := _buffer(0.16)
	_tone(buf, 0.0, 0.14, 1480.0, 1200.0, 0.6, "triangle", 0.001, 2.6)
	_tone(buf, 0.0, 0.10, 2230.0, 1980.0, 0.35, "sine", 0.001, 3.0)
	_noise(buf, 0.0, 0.03, 0.30, 0.001, 3.0, 6000.0, 2500.0)
	return _to_stream(buf)


## 中命中：锅底闷响
func _hit_medium() -> AudioStreamWAV:
	var buf := _buffer(0.30)
	_tone(buf, 0.0, 0.26, 900.0, 620.0, 0.6, "triangle", 0.001, 2.2)
	_tone(buf, 0.0, 0.18, 1400.0, 900.0, 0.35, "square", 0.001, 2.6)
	_tone(buf, 0.0, 0.28, 180.0, 90.0, 0.5, "sine", 0.002, 1.6)
	_noise(buf, 0.0, 0.06, 0.35, 0.001, 2.6, 5000.0, 1200.0)
	return _to_stream(buf)


## 重命中（铁锅）：低频「咚」+ 金属余响
func _hit_heavy() -> AudioStreamWAV:
	var buf := _buffer(0.55)
	_tone(buf, 0.0, 0.50, 160.0, 70.0, 0.85, "sine", 0.003, 1.4)
	_tone(buf, 0.0, 0.30, 620.0, 380.0, 0.55, "square", 0.001, 2.2)
	_tone(buf, 0.02, 0.40, 1180.0, 900.0, 0.30, "triangle", 0.004, 2.6)
	_noise(buf, 0.0, 0.12, 0.45, 0.001, 2.2, 3000.0, 700.0)
	return _to_stream(buf)


## 蓄满爆击：重击 + 上升哨音 + 爆炸噪声
func _hit_crit() -> AudioStreamWAV:
	var buf := _buffer(0.80)
	_tone(buf, 0.0, 0.70, 140.0, 55.0, 0.90, "sine", 0.002, 1.3)
	_tone(buf, 0.06, 0.26, 1800.0, 2600.0, 0.30, "sine", 0.01, 2.0)
	_tone(buf, 0.0, 0.45, 520.0, 300.0, 0.45, "saw", 0.002, 2.0)
	_noise(buf, 0.0, 0.30, 0.55, 0.001, 1.8, 8000.0, 900.0)
	return _to_stream(buf)


## 连击：越连越高（音高由 AudioManager 再乘）
func _combo() -> AudioStreamWAV:
	var buf := _buffer(0.22)
	_tone(buf, 0.0, 0.18, 1180.0, 1180.0, 0.5, "triangle", 0.002, 2.4)
	_tone(buf, 0.03, 0.16, 2360.0, 2200.0, 0.25, "sine", 0.002, 3.0)
	return _to_stream(buf)


## 失误：往下掉的两音
func _miss() -> AudioStreamWAV:
	var buf := _buffer(0.34)
	_tone(buf, 0.0, 0.16, 420.0, 330.0, 0.5, "saw", 0.004, 1.8)
	_tone(buf, 0.14, 0.18, 300.0, 180.0, 0.45, "saw", 0.004, 1.8)
	return _to_stream(buf)


## 手滑：往下滑的噪声
func _slip() -> AudioStreamWAV:
	var buf := _buffer(0.30)
	_noise(buf, 0.0, 0.28, 0.55, 0.01, 1.5, 2600.0, 260.0)
	_tone(buf, 0.0, 0.22, 700.0, 220.0, 0.22, "triangle", 0.01, 1.8)
	return _to_stream(buf)


## 锅凉了 / 掉地上：稀里哗啦的碰撞声
func _escape() -> AudioStreamWAV:
	var buf := _buffer(0.55)
	var rng := RandomNumberGenerator.new()
	rng.seed = NOISE_SEED
	for i in 5:
		var start := 0.02 + float(i) * 0.07 + rng.randf_range(0.0, 0.03)
		_tone(buf, start, 0.10, rng.randf_range(700.0, 1500.0), rng.randf_range(300.0, 700.0),
			0.35, "square", 0.001, 2.6)
	_noise(buf, 0.0, 0.10, 0.25, 0.001, 2.6, 4000.0, 800.0)
	return _to_stream(buf)


## 老板变脸：下行 + 一点滑稽的蜂鸣
func _boss_stage() -> AudioStreamWAV:
	var buf := _buffer(0.50)
	_tone(buf, 0.0, 0.22, 760.0, 520.0, 0.5, "square", 0.004, 1.8)
	_tone(buf, 0.16, 0.28, 480.0, 240.0, 0.5, "square", 0.004, 1.6)
	_tone(buf, 0.0, 0.40, 120.0, 90.0, 0.30, "sine", 0.02, 1.2)
	return _to_stream(buf)


## 老板崩溃：一路下滑 + 撞桌
func _phase_up() -> AudioStreamWAV:
	var buf := _buffer(0.34)
	_tone(buf, 0.0, 0.16, 392.0, 523.25, 0.5, "triangle", 0.004, 1.8)
	_tone(buf, 0.12, 0.20, 587.33, 783.99, 0.5, "triangle", 0.004, 1.6)
	return _to_stream(buf)


func _boss_ko() -> AudioStreamWAV:
	var buf := _buffer(1.0)
	_tone(buf, 0.0, 0.85, 900.0, 110.0, 0.55, "saw", 0.01, 1.2)
	_tone(buf, 0.55, 0.40, 200.0, 60.0, 0.75, "sine", 0.003, 1.5)
	_noise(buf, 0.55, 0.30, 0.45, 0.002, 1.8, 2600.0, 400.0)
	for i in 3:
		_tone(buf, 0.62 + float(i) * 0.09, 0.10, 420.0 - float(i) * 60.0, 260.0, 0.30,
			"triangle", 0.002, 2.4)
	return _to_stream(buf)


## 疯狂甩锅时间：上扬的警报
func _frenzy() -> AudioStreamWAV:
	var buf := _buffer(0.9)
	for i in 4:
		var start := float(i) * 0.14
		_tone(buf, start, 0.16, 520.0 + float(i) * 170.0, 640.0 + float(i) * 190.0, 0.45,
			"square", 0.006, 1.8)
	_tone(buf, 0.0, 0.70, 130.0, 260.0, 0.28, "saw", 0.02, 1.2)
	return _to_stream(buf)


## 结算：三音收尾
func _result() -> AudioStreamWAV:
	var buf := _buffer(0.9)
	var notes := [523.25, 659.25, 783.99]
	for i in notes.size():
		_tone(buf, 0.12 * float(i), 0.46, notes[i], notes[i] * 1.005, 0.5, "triangle", 0.01, 1.5)
	_tone(buf, 0.0, 0.60, 130.81, 196.0, 0.25, "sine", 0.02, 1.2)
	return _to_stream(buf)


## 新纪录：小小号角
func _new_record() -> AudioStreamWAV:
	var buf := _buffer(1.1)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for i in notes.size():
		_tone(buf, 0.10 * float(i), 0.30, notes[i], notes[i], 0.55, "triangle", 0.008, 1.6)
	_tone(buf, 0.30, 0.70, 523.25, 1046.5, 0.30, "sine", 0.02, 1.0)
	_noise(buf, 0.30, 0.35, 0.20, 0.05, 1.6, 3000.0, 8000.0)
	return _to_stream(buf)


## 解锁新锅：亮晶晶
func _unlock() -> AudioStreamWAV:
	var buf := _buffer(0.7)
	var notes := [880.0, 1174.66, 1567.98, 2093.0]
	for i in notes.size():
		_tone(buf, 0.07 * float(i), 0.24, notes[i], notes[i], 0.42, "sine", 0.004, 1.8)
	_noise(buf, 0.0, 0.40, 0.18, 0.02, 1.4, 6000.0, 9000.0)
	return _to_stream(buf)


# ---------------------------------------------------------------- 合成工具

func _buffer(duration: float) -> Array:
	var count := int(duration * float(SAMPLE_RATE))
	var buf: Array = []
	buf.resize(count)
	buf.fill(0.0)
	return buf


## 叠加一段音：freq_from → freq_to 线性扫频，shape 是 sine / square / triangle / saw
func _tone(
	buf: Array, start: float, duration: float, freq_from: float, freq_to: float,
	amp: float, shape: String, attack: float, decay_power: float
) -> void:
	var start_index := int(start * float(SAMPLE_RATE))
	var count := int(duration * float(SAMPLE_RATE))
	var phase := 0.0
	for i in count:
		var index := start_index + i
		if index < 0:
			continue
		if index >= buf.size():
			break
		var progress := float(i) / float(maxi(count, 1))
		var freq := lerpf(freq_from, freq_to, progress)
		phase += TAU * freq / float(SAMPLE_RATE)
		var value := 0.0
		match shape:
			"square":
				value = 1.0 if sin(phase) >= 0.0 else -1.0
			"triangle":
				value = asin(sin(phase)) * (2.0 / PI)
			"saw":
				value = fposmod(phase, TAU) / TAU * 2.0 - 1.0
			_:
				value = sin(phase)
		var envelope := pow(1.0 - progress, decay_power)
		var t := float(i) / float(SAMPLE_RATE)
		if attack > 0.0 and t < attack:
			envelope *= t / attack
		buf[index] = float(buf[index]) + value * amp * envelope


## 叠加一段噪声：用一阶低通滤波扫出「材质」，lowpass 从 lowpass_from 扫到 lowpass_to
func _noise(
	buf: Array, start: float, duration: float, amp: float, attack: float, decay_power: float,
	lowpass_from: float = 4000.0, lowpass_to: float = 1000.0
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = NOISE_SEED
	var start_index := int(start * float(SAMPLE_RATE))
	var count := int(duration * float(SAMPLE_RATE))
	var prev := 0.0
	for i in count:
		var index := start_index + i
		if index < 0:
			continue
		if index >= buf.size():
			break
		var progress := float(i) / float(maxi(count, 1))
		var cutoff := lerpf(lowpass_from, lowpass_to, progress)
		var alpha := clampf(TAU * cutoff / float(SAMPLE_RATE), 0.0, 1.0)
		var white := rng.randf_range(-1.0, 1.0)
		prev = prev + alpha * (white - prev)
		var envelope := pow(1.0 - progress, decay_power)
		var t := float(i) / float(SAMPLE_RATE)
		if attack > 0.0 and t < attack:
			envelope *= t / attack
		buf[index] = float(buf[index]) + prev * amp * envelope


## 归一化到统一峰值并转成 16 bit WAV
func _to_stream(buf: Array) -> AudioStreamWAV:
	var peak := 0.0
	for value in buf:
		peak = maxf(peak, absf(float(value)))
	var gain := 0.0 if peak <= 0.0 else PEAK / peak
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		var remaining := buf.size() - i
		var tail := minf(float(remaining) / (0.003 * float(SAMPLE_RATE)), 1.0)
		var sample := clampf(float(buf[i]) * gain * tail, -1.0, 1.0)
		data.encode_s16(i * 2, int(round(sample * 32767.0)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
