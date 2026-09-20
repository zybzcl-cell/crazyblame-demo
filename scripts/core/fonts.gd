class_name Fonts
## 项目内嵌字体（Noto Sans SC，SIL OFL 1.1，见 assets/fonts/OFL.txt）。
##
## 为什么要内嵌：桌面版靠系统字体回退显示中文没问题，但 **Web 版本没有系统字体可用**，
## 只靠引擎默认字体（Open Sans）会出现一堆「豆腐块」。所以整个游戏统一用这一个字体：
##   - Control 类界面：project.godot 里 gui/theme/custom_font 指向同一个文件；
##   - _draw 里手动画的字（锅话标签、伤害数字、白板上的「本月业绩」）：走 Fonts.ui()。

const FONT_PATH := "res://assets/fonts/NotoSansSC-Regular.otf"

static var _font: Font = null


## 统一取字体（取不到就退回引擎默认字体，保证不会因为缺字体崩掉）
static func ui() -> Font:
	if _font == null:
		if ResourceLoader.exists(FONT_PATH):
			var resource := load(FONT_PATH)
			if resource is Font:
				_font = resource
		if _font == null:
			_font = ThemeDB.fallback_font
	return _font


## 这个字能不能画出来
static func has_char(character: String) -> bool:
	if character.is_empty():
		return true
	return ui().has_char(character.unicode_at(0))


## 一段文字里有没有画不出来的字（返回缺字的列表）
static func missing_characters(text: String) -> Array:
	var missing: Array = []
	for i in text.length():
		var character := text.substr(i, 1)
		if character.strip_edges().is_empty():
			continue
		if not has_char(character) and not missing.has(character):
			missing.append(character)
	return missing


## 内嵌字体是否真的可用（测试用）
static func is_embedded() -> bool:
	if not ResourceLoader.exists(FONT_PATH):
		return false
	var font := ui()
	if font == null:
		return false
	# 内嵌字体是从项目路径加载的 FontFile；引擎默认字体不是
	return font is FontFile and font.resource_path == FONT_PATH
