extends BlameTestBase
## 截图自检：把 tests/visual_capture.tscn 拍到的画面读回来做定量检查。
##
## 自动化测试没法「用眼睛看」，所以这里用像素统计来判断画面是不是真的画出来了：
##   - 界面区域有没有亮色文字像素（字真的渲染了）
##   - 老板区域有没有肤色 / 西装色像素（老板真的画出来了）
##   - 场地里有没有深色锅 + 亮色锅标签
##   - 疯狂甩锅时间整屏是不是更红
##   - 老板七个阶段的截图两两不同（表情 / 姿态真的在变，不是换文字）

const SHOT_DIR := "res://tests/.tmp"
const SHOTS := [
	"shot_1_menu.png", "shot_2_start.png", "shot_3_mid.png", "shot_4_hurt.png",
	"shot_5_frenzy.png", "shot_6_result.png", "shot_7_codex.png", "shot_8_settings.png",
	"shot_9_boss_stages.png", "shot_10_pause.png",
]

## 区域都按新的空间预算取：HUD 0.03~0.10 / 老板 0.18~0.46 / 操作区 0.51~0.92 / 底部 0.93~0.99
const REGION_HUD := Rect2(0.02, 0.02, 0.96, 0.09)
const REGION_BOSS := Rect2(0.18, 0.185, 0.64, 0.25)
const REGION_FIELD := Rect2(0.06, 0.52, 0.88, 0.34)
const REGION_WALL := Rect2(0.004, 0.20, 0.03, 0.24)
const REGION_BOTTOM := Rect2(0.05, 0.925, 0.90, 0.06)
const REGION_PANEL := Rect2(0.12, 0.22, 0.76, 0.60)


func run_tests() -> void:
	suite_name = "画面自检（截图分析）"
	var missing: Array = []
	for name in SHOTS:
		if not FileAccess.file_exists("%s/%s" % [SHOT_DIR, name]):
			missing.append(name)
	_check("实机截图都在（如果这里失败，先跑一次实机截图测试）", missing.is_empty(), str(missing))
	if not missing.is_empty():
		return

	_test_text_and_colors()
	_test_boss_visible()
	_test_pots_visible()
	_test_frenzy_tint()
	_test_boss_stages_differ()
	_test_panels()
	_test_composition_pixels()


## 构图专项：用像素确认「办公室是一个整体空间」而不是人物贴在背景上
func _test_composition_pixels() -> void:
	var mid := _load("shot_3_mid.png")
	# 顶部 HUD 区域不该有老板的肤色像素（人物没有被 HUD 压住）
	_check("顶部 HUD 区域没有老板的像素（HUD 不压人物）",
		PixelTools.ratio(mid, Rect2(0.02, 0.03, 0.96, 0.07), PixelTools.is_skin, 3) < 0.002,
		"%.4f" % PixelTools.ratio(mid, Rect2(0.02, 0.03, 0.96, 0.07), PixelTools.is_skin, 3))
	# 老板下方（桌沿附近）应该是木色桌面，而不是墙色
	_check("老板下方能看到办公桌的木色桌面（人物与桌子有上下关系）",
		PixelTools.ratio(mid, Rect2(0.20, 0.375, 0.60, 0.09), PixelTools.is_wood, 3) > 0.10,
		"%.3f" % PixelTools.ratio(mid, Rect2(0.20, 0.375, 0.60, 0.09), PixelTools.is_wood, 3))
	# 桌面下沿与操作区之间不该再有老板的身体
	_check("桌沿下方没有老板的身体像素（人物没有侵占甩锅操作区）",
		PixelTools.ratio(mid, Rect2(0.10, 0.478, 0.80, 0.028), PixelTools.is_skin, 2) < 0.002,
		"%.4f" % PixelTools.ratio(mid, Rect2(0.10, 0.478, 0.80, 0.028), PixelTools.is_skin, 2))
	# 墙上挂着窗户（冷蓝玻璃）
	_check("办公室左上墙上挂着窗户（能看到冷蓝的玻璃像素）",
		PixelTools.ratio(mid, Rect2(0.05, 0.19, 0.26, 0.14), PixelTools.is_glass, 3) > 0.05,
		"%.3f" % PixelTools.ratio(mid, Rect2(0.05, 0.19, 0.26, 0.14), PixelTools.is_glass, 3))
	# 墙上挂着「本月业绩」白板（浅色板面）
	_check("右上墙上挂着本月业绩白板（浅色板面 + 墙面在它周围）",
		PixelTools.ratio(mid, Rect2(0.60, 0.17, 0.36, 0.16), PixelTools.is_paper, 3) > 0.08,
		"%.3f" % PixelTools.ratio(mid, Rect2(0.60, 0.17, 0.36, 0.16), PixelTools.is_paper, 3))
	# 甩锅操作区是地板上的一块区域（暖色木地板 + 地毯色块）
	_check("甩锅操作区落在地板上（暖色木地板像素）",
		PixelTools.ratio(mid, Rect2(0.05, 0.90, 0.90, 0.03), PixelTools.is_wood, 3) > 0.10,
		"%.3f" % PixelTools.ratio(mid, Rect2(0.05, 0.90, 0.90, 0.03), PixelTools.is_wood, 3))
	# 老板挨打之后：白板折线变红 / 桌面物品变乱 —— 用「老板区域颜色分布变化」间接确认
	var hurt := _load("shot_4_hurt.png")
	_check("老板挨打之后的画面与中期明显不同（表情 / 姿态 / 桌面都在变）",
		PixelTools.signature_distance(PixelTools.signature(mid, REGION_BOSS),
			PixelTools.signature(hurt, REGION_BOSS)) > 0.01,
		"差异 %.4f" % PixelTools.signature_distance(PixelTools.signature(mid, REGION_BOSS),
			PixelTools.signature(hurt, REGION_BOSS)))


func _test_text_and_colors() -> void:
	var menu := _load("shot_1_menu.png")
	_check("主菜单截图能读出来", menu != null)
	if menu == null:
		return
	_check("主菜单上真的有字（标题区域有大量亮色像素）",
		_bright_ratio(menu, Rect2(0.10, 0.05, 0.80, 0.11)) > 0.02,
		"%.3f" % _bright_ratio(menu, Rect2(0.10, 0.05, 0.80, 0.11)))
	_check("主菜单标题是金色强调色（不是默认白字）",
		_gold_ratio(menu, Rect2(0.10, 0.05, 0.80, 0.11)) > 0.005,
		"%.4f" % _gold_ratio(menu, Rect2(0.10, 0.05, 0.80, 0.11)))
	_check("主菜单上的按钮画出来了（有大面积面板色）",
		_panel_ratio(menu, Rect2(0.10, 0.72, 0.80, 0.20)) > 0.15,
		"%.3f" % _panel_ratio(menu, Rect2(0.10, 0.72, 0.80, 0.20)))

	var mid := _load("shot_3_mid.png")
	_check("游戏界面顶部有文字（倒计时 / 连击 / 老板状态）",
		_bright_ratio(mid, REGION_HUD) > 0.003,
		"%.4f" % _bright_ratio(mid, REGION_HUD))
	_check("老板精神状态条画出来了（顶部有一条彩色血条）",
		PixelTools.ratio(mid, Rect2(0.02, 0.096, 0.96, 0.042), PixelTools.is_bar_fill, 3) > 0.05,
		"%.3f" % PixelTools.ratio(mid, Rect2(0.02, 0.096, 0.96, 0.042),
			PixelTools.is_bar_fill, 3))
	_check("底部辅助信息条也有文字（总分 / 命中 / 失误）",
		_bright_ratio(mid, REGION_BOTTOM) > 0.004,
		"%.4f" % _bright_ratio(mid, REGION_BOTTOM))


func _test_boss_visible() -> void:
	var playing := _load("shot_3_mid.png")
	_check("老板区域有肤色像素（Q 版老板真的画出来了）",
		_skin_ratio(playing, REGION_BOSS) > 0.01,
		"%.4f" % _skin_ratio(playing, REGION_BOSS))
	_check("老板穿着深蓝西装（不是一片色块）",
		_suit_ratio(playing, REGION_BOSS) > 0.02,
		"%.4f" % _suit_ratio(playing, REGION_BOSS))


func _test_pots_visible() -> void:
	var playing := _load("shot_3_mid.png")
	_check("场地里有锅（深色金属像素）",
		_dark_ratio(playing, REGION_FIELD) > 0.01,
		"%.4f" % _dark_ratio(playing, REGION_FIELD))
	_check("锅里 / 锅边上有亮色像素（锅话标签与高光）",
		_bright_ratio(playing, REGION_FIELD) > 0.0005,
		"%.5f" % _bright_ratio(playing, REGION_FIELD))
	var frenzy := _load("shot_5_frenzy.png")
	# 疯狂阶段整屏有红光，深色像素会被提亮，所以这里改用「锅话标签的亮色像素」判断锅还在
	_check("疯狂甩锅时间里画面里仍然有一堆锅（锅话标签亮着）",
		_bright_ratio(frenzy, REGION_FIELD) > 0.0002,
		"%.5f（普通阶段 %.5f）" % [_bright_ratio(frenzy, REGION_FIELD),
			_bright_ratio(playing, REGION_FIELD)])


func _test_frenzy_tint() -> void:
	var playing := _load("shot_3_mid.png")
	var frenzy := _load("shot_5_frenzy.png")
	var normal_tint := _redness(playing, REGION_WALL)
	var frenzy_tint := _redness(frenzy, REGION_WALL)
	_check("疯狂甩锅时间整屏泛红（背景明显更红）", frenzy_tint > normal_tint + 0.06,
		"%.3f → %.3f" % [normal_tint, frenzy_tint])
	_check("疯狂甩锅时间的背景不再是冷灰蓝（真的被红光照过）",
		frenzy_tint > -0.02 and normal_tint < -0.04,
		"普通 %.3f → 疯狂 %.3f" % [normal_tint, frenzy_tint])


func _test_boss_stages_differ() -> void:
	var image := _load("shot_9_boss_stages.png")
	var signatures: Array = []
	for i in 7:
		var column := i % 4
		var row := i / 4
		var rect := Rect2(0.16 + 0.24 * float(column) - 0.07, 0.16 + 0.30 * float(row) - 0.055,
			0.14, 0.11)
		signatures.append(_signature(image, rect))
	var distinct := 0
	for i in 7:
		for j in range(i + 1, 7):
			if _signature_distance(signatures[i], signatures[j]) > 0.02:
				distinct += 1
	_check("老板七个阶段的画面两两不同（表情 / 姿态 / 道具真的在变）",
		distinct >= 18, "%d / 21 组不同" % distinct)
	var skin_counts: Array = []
	for i in 7:
		skin_counts.append(int(_skin_ratio(image,
			Rect2(0.16 + 0.24 * float(i % 4) - 0.07, 0.16 + 0.30 * float(i / 4) - 0.055,
				0.14, 0.11)) * 10000.0))
	var unique_counts := {}
	for count in skin_counts:
		unique_counts[count] = true
	_check("七个阶段里，老板的「露脸面积」也不一样（趴桌 / 抱头 / 站起来的姿态差异）",
		unique_counts.size() >= 4, str(skin_counts))


func _test_panels() -> void:
	var result := _load("shot_6_result.png")
	_check("结算卡面板画出来了（大面积面板底色）",
		_panel_ratio(result, REGION_PANEL) > 0.3, "%.3f" % _panel_ratio(result, REGION_PANEL))
	_check("结算卡上有大字（评级 / 分数）",
		_bright_ratio(result, Rect2(0.25, 0.28, 0.50, 0.20)) > 0.01,
		"%.4f" % _bright_ratio(result, Rect2(0.25, 0.28, 0.50, 0.20)))
	var codex := _load("shot_7_codex.png")
	_check("锅图鉴里能看到多张卡片（面板 + 卡片色块）",
		_panel_ratio(codex, Rect2(0.08, 0.15, 0.84, 0.70)) > 0.25,
		"%.3f" % _panel_ratio(codex, Rect2(0.08, 0.15, 0.84, 0.70)))
	var settings := _load("shot_8_settings.png")
	# 面板本身 + 「按钮文字那一列」都要有东西。
	# （按钮文字是居中排的，所以按文字所在的窄列来看，而不是把整片背景一起平均，
	#   否则「老板透出来」也会被算成文字亮度。）
	_check("设置面板画出来了（大面积面板底色）",
		_panel_ratio(settings, Rect2(0.20, 0.20, 0.60, 0.60)) > 0.3,
		"%.3f" % _panel_ratio(settings, Rect2(0.20, 0.20, 0.60, 0.60)))
	_check("设置面板上的按钮 / 文字真的画出来了（居中那一列有亮色文字）",
		_bright_ratio(settings, Rect2(0.42, 0.20, 0.16, 0.45)) > 0.003,
		"%.4f" % _bright_ratio(settings, Rect2(0.42, 0.20, 0.16, 0.45)))
	var pause := _load("shot_10_pause.png")
	_check("游戏内暂停菜单画出来了（面板 + 居中那列有按钮文字）",
		_panel_ratio(pause, Rect2(0.20, 0.20, 0.60, 0.60)) > 0.3
		and _bright_ratio(pause, Rect2(0.42, 0.20, 0.16, 0.50)) > 0.002,
		"面板 %.3f / 文字 %.4f" % [_panel_ratio(pause, Rect2(0.20, 0.20, 0.60, 0.60)),
			_bright_ratio(pause, Rect2(0.42, 0.20, 0.16, 0.50))])


# ---------------------------------------------------------------- 像素统计
# 具体实现放在 tests/pixel_tools.gd（实机截图测试用的是同一套，避免两份实现慢慢跑偏）

func _load(name: String) -> Image:
	return Image.load_from_file("%s/%s" % [SHOT_DIR, name])


func _redness(image: Image, region: Rect2) -> float:
	return PixelTools.redness(image, region)


func _signature(image: Image, region: Rect2) -> Array:
	return PixelTools.signature(image, region)


func _signature_distance(a: Array, b: Array) -> float:
	return PixelTools.signature_distance(a, b)


func _bright_ratio(image: Image, region: Rect2) -> float:
	return PixelTools.ratio(image, region, PixelTools.is_bright)


func _gold_ratio(image: Image, region: Rect2) -> float:
	return PixelTools.ratio(image, region, PixelTools.is_gold)


func _skin_ratio(image: Image, region: Rect2) -> float:
	return PixelTools.ratio(image, region, PixelTools.is_skin)


func _suit_ratio(image: Image, region: Rect2) -> float:
	return PixelTools.ratio(image, region, PixelTools.is_suit)


func _dark_ratio(image: Image, region: Rect2) -> float:
	return PixelTools.ratio(image, region, PixelTools.is_dark)


func _panel_ratio(image: Image, region: Rect2) -> float:
	return PixelTools.ratio(image, region, PixelTools.is_panel)
