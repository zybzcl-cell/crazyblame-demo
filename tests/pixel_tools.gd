class_name PixelTools
## 截图分析工具（给 tests/visual_check_test.gd 与 tests/visual_capture.gd 共用）。
##
## 自动化测试没法「用眼睛看」，所以用像素统计来判断画面：某个区域有没有肤色 / 金色 / 面板色，
## 两张图是不是一样（用来确认七个老板阶段真的画得不同、两个不同的汉字不是同一个豆腐块）。

## 在归一化矩形里按谓词统计像素比例
static func ratio(image: Image, region: Rect2, predicate: Callable, step: int = 3) -> float:
	var x0 := int(region.position.x * float(image.get_width()))
	var y0 := int(region.position.y * float(image.get_height()))
	var x1 := int((region.position.x + region.size.x) * float(image.get_width()))
	var y1 := int((region.position.y + region.size.y) * float(image.get_height()))
	var total := 0
	var hit := 0
	for y in range(maxi(y0, 0), mini(y1, image.get_height()), step):
		for x in range(maxi(x0, 0), mini(x1, image.get_width()), step):
			total += 1
			if bool(predicate.call(image.get_pixel(x, y))):
				hit += 1
	return 0.0 if total == 0 else float(hit) / float(total)


## 区域平均「红 − 蓝」，用来判断整屏是不是泛红
static func redness(image: Image, region: Rect2, step: int = 4) -> float:
	var x0 := int(region.position.x * float(image.get_width()))
	var y0 := int(region.position.y * float(image.get_height()))
	var x1 := int((region.position.x + region.size.x) * float(image.get_width()))
	var y1 := int((region.position.y + region.size.y) * float(image.get_height()))
	var total := 0
	var sum := 0.0
	for y in range(maxi(y0, 0), mini(y1, image.get_height()), step):
		for x in range(maxi(x0, 0), mini(x1, image.get_width()), step):
			var color := image.get_pixel(x, y)
			sum += color.r - color.b
			total += 1
	return 0.0 if total == 0 else sum / float(total)


## 区域的 grid×grid 亮度指纹
static func signature(image: Image, region: Rect2, grid: int = 12) -> Array:
	var values: Array = []
	var x0 := int(region.position.x * float(image.get_width()))
	var y0 := int(region.position.y * float(image.get_height()))
	var w := int(region.size.x * float(image.get_width()))
	var h := int(region.size.y * float(image.get_height()))
	for gy in grid:
		for gx in grid:
			var px := clampi(x0 + int((float(gx) + 0.5) * float(w) / float(grid)), 0,
				image.get_width() - 1)
			var py := clampi(y0 + int((float(gy) + 0.5) * float(h) / float(grid)), 0,
				image.get_height() - 1)
			values.append(image.get_pixel(px, py).get_luminance())
	return values


## 两个指纹的平均差异（0 表示一模一样）
static func signature_distance(a: Array, b: Array) -> float:
	var total := 0.0
	for i in mini(a.size(), b.size()):
		total += absf(float(a[i]) - float(b[i]))
	return total / float(maxi(a.size(), 1))


# ---------------------------------------------------------------- 常用谓词

static func is_bright(color: Color) -> bool:
	return color.get_luminance() > 0.72


static func is_gold(color: Color) -> bool:
	return color.r > 0.78 and color.g > 0.60 and color.g < 0.90 and color.b < 0.58


static func is_skin(color: Color) -> bool:
	return color.r > 0.70 and color.g > 0.50 and color.b < 0.80 and color.r > color.b + 0.10


static func is_suit(color: Color) -> bool:
	return color.b > color.r and color.b < 0.55 and color.get_luminance() < 0.40


static func is_dark(color: Color) -> bool:
	return color.get_luminance() < 0.28


static func is_panel(color: Color) -> bool:
	# 面板 / 卡片底色：中低亮度的冷灰蓝
	return color.get_luminance() > 0.06 and color.get_luminance() < 0.30 and color.b >= color.r


static func is_reddish(color: Color) -> bool:
	return color.r > color.b + 0.06


## 木色（办公桌、地板）
static func is_wood(color: Color) -> bool:
	return color.r > 0.30 and color.g > 0.20 and color.b < 0.50 and color.r > color.b + 0.08


## 窗户玻璃的冷蓝色
static func is_glass(color: Color) -> bool:
	return color.b > color.r + 0.04 and color.b > 0.22 and color.get_luminance() < 0.62


## 白板 / 纸张的浅色
static func is_paper(color: Color) -> bool:
	return color.get_luminance() > 0.72 and absf(color.r - color.b) < 0.18


## 血条填充色（绿 / 黄 / 红这类高饱和色块）
static func is_bar_fill(color: Color) -> bool:
	return color.s > 0.35 and color.v > 0.45
