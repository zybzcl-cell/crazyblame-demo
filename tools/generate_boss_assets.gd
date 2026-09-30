extends Node
## Boss 素材工具：生成「素材缺失占位图」以及素材目录的清单 / 说明文件。
##
## 运行（需要真实窗口渲染，headless 拿不到帧缓冲）：
##   /Applications/Godot.app/Contents/MacOS/Godot --path . --quit-after 240 res://tools/generate_boss_assets.tscn
##
## 只会写 assets/characters/boss/ 下的：
##   _placeholder_missing_art.png   素材缺失时的占位图（明确写着缺什么，不是最终美术）
##   manifest.json                  锚点 / pivot / 是否画办公桌（换素材时改这里）
##   README.md                      素材接入说明（文件名契约）
## **不会**生成任何 Boss 美术本体 —— Boss 长相必须由美术 PNG 提供。

const OUT_DIR := "res://assets/characters/boss"

const MANIFEST := {
	"version": 1,
	"note": "锚点单位 = r（1.0 = Boss 身体基准半径 BASE_RADIUS）。原点 (0,0) = Boss 身体中心。",
	"pivot": [0.5, 0.45],
	"sprite_height_r": 3.32,
	"draw_desk": true,
	"anchors": {
		"head": [0.0, -0.56],
		"face": [0.0, -0.30],
		"hand_left": [-1.12, 0.26],
		"hand_right": [1.12, 0.26],
		"throw_hand_upper": [1.20, -1.02],
		"throw_hand_mid": [1.26, -0.44],
		"throw_hand_lower": [1.18, 0.14],
		"body_center": [0.0, 0.56],
		"body_radius": [1.06, 1.06],
		"head_radius": [0.92, 0.92],
	},
}

const README := """# Boss 美术素材目录（assets/characters/boss/）

**Boss 的本体长相完全由这个目录里的 PNG 决定**（透明背景，建议 512×768 或同比例）。
代码只负责：状态（七阶段 / 受击 / 甩锅时间轴）、位置、锚点、以及独立 FX。

> 现在目录里只有 `_placeholder_missing_art.png`：那是**素材缺失占位图**，
> 明确写着缺什么，**不是**最终美术。把下面这些 PNG 放进来就会自动替换掉它。

## 一、必填（至少 1 张，建议 7 张）

| 文件名 | 用途 |
| --- | --- |
| `boss_stage_1.png` … `boss_stage_7.png` | 七个阶段的同一个老板（得意 / 疑惑 / 不爽 / 愤怒 / 暴怒 / 疲惫 / 崩溃） |

- 缺 `boss_stage_N.png` 时自动回退到 `boss_stage_1.png`；一张都没有就用占位图。
- 想要多帧动画：`boss_stage_3_1.png`、`boss_stage_3_2.png` …（数字后缀按顺序播放）。
- 动画名：`idle_stage_1` … `idle_stage_7`；崩溃阶段用 `ko`。

## 二、甩锅动作（可选，建议补上）

| 文件名 | 对应时间轴 |
| --- | --- |
| `boss_throw_notice.png` | 0.00~0.10s 注意目标 / 伸手（头顶会飘「！」） |
| `boss_throw_windup.png` | 0.10~0.34s 抬手蓄力（锅被攥在手里） |
| `boss_throw_release.png` | 0.34s 手臂前甩、锅脱手 |
| `boss_throw_recover.png` | 0.34~0.64s 收势 |

- 只画**右手甩锅**即可：向左甩时代码会水平镜像（含手部锚点）。
- 同样支持 `_1`、`_2` 多帧后缀。
- 缺这些图时自动回退到当前阶段的表情图（动作由代码的位移 / 旋转 / 残影表现）。

## 三、锚点（换素材时改 manifest.json）

`manifest.json` 里的锚点单位是 **r**（1.0 = `BlameBoss.BASE_RADIUS`，游戏里 Boss 身体基准半径），
原点 (0,0) = **Boss 身体中心**（也就是节点 position）。锅就是出现在 `hand_*` / `throw_hand_*` 上的，
所以换图以后如果锅的位置不对，只改这几个数字即可，不用动玩法代码：

```json
"pivot": [0.5, 0.45],          // 贴图里「身体中心」在图片上的位置（0~1，左上为原点）
"sprite_height_r": 3.32,       // 贴图整张高度对应多少 r（决定 Boss 在屏幕上的大小）
"draw_desk": true,             // 素材里自带办公桌时改成 false
"anchors": {
  "head":            [0.0, -0.56],
  "face":            [0.0, -0.30],
  "hand_left":       [-1.12, 0.26],
  "hand_right":      [1.12, 0.26],
  "throw_hand_upper":[1.20, -1.02],
  "throw_hand_mid":  [1.26, -0.44],
  "throw_hand_lower":[1.18, 0.14],
  "body_center":     [0.0, 0.56],
  "body_radius":     [1.06, 1.06],
  "head_radius":     [0.92, 0.92]
}
```

## 四、视觉标准（必须遵守）

高质量 Q 版：大头 / 圆脸 / 明显肥胖 / 大肚子 / 短粗四肢 / 半秃（两侧留黑发 + 几根翘发）/
粗黑框眼镜 / 大鼻子 / 鼓脸 / 双下巴 / 藏蓝西装 + 白衬衫 + 红领带 + 黑色皮鞋 / 表情夸张 /
明亮干净 / 搞笑欠揍的职场老板。
**不要**写实、不要帅哥、不要瘦老板、不要恐怖血腥、不要用几何图形拼。
"""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	await _write_placeholder()
	_write_text("%s/manifest.json" % OUT_DIR, JSON.stringify(MANIFEST, "\t"))
	_write_text("%s/README.md" % OUT_DIR, README)
	print("===== Boss 素材工具：已写出 %s/{_placeholder_missing_art.png, manifest.json, README.md} =====" % OUT_DIR)
	get_tree().quit(0)


## 用真实渲染的 SubViewport 画一张「素材缺失」占位图（明确标注，不是最终美术）
func _write_placeholder() -> void:
	var size := Vector2i(640, 360)
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var root := Control.new()
	root.size = Vector2(size)
	viewport.add_child(root)
	var panel := Panel.new()
	panel.position = Vector2(24, 24)
	panel.size = Vector2(size.x - 48, size.y - 48)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.15, 0.20, 0.94)
	style.border_color = Palette.ACCENT
	style.set_border_width_all(6)
	style.set_corner_radius_all(28)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	var title := Label.new()
	title.text = "BOSS 素材缺失"
	title.add_theme_font_override("font", Fonts.ui())
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Palette.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(40, 56)
	title.size = Vector2(size.x - 80, 64)
	root.add_child(title)
	var body := Label.new()
	body.text = "请把透明 PNG 放进：\nassets/characters/boss/\n\nboss_stage_1.png … boss_stage_7.png\nboss_throw_notice / windup / release / recover.png\n\n（本图只是占位，不是最终美术）"
	body.add_theme_font_override("font", Fonts.ui())
	body.add_theme_font_size_override("font_size", 24)
	body.add_theme_color_override("font_color", Palette.UI_TEXT)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.position = Vector2(48, 136)
	body.size = Vector2(size.x - 96, size.y - 180)
	root.add_child(body)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var path := "%s/_placeholder_missing_art.png" % OUT_DIR
	var err := image.save_png(path)
	print("  占位图 %s（%dx%d，err=%d）" % [path, image.get_width(), image.get_height(), err])


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("  写不进去：%s" % path)
		return
	file.store_string(text)
	file.close()
	print("  已写出 %s" % path)
