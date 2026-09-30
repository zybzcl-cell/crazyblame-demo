extends BlameTestBase
## Web 试玩版测试：导出配置、页面补丁、产物是否齐全、字体有没有真的打进包里。
##
## 用法：
##   Godot --headless --path . res://tests/web_test.tscn                # 完整检查（需要先构建）
##   Godot --headless --path . res://tests/web_test.tscn -- preset-only # 只检查配置与补丁逻辑

const OUT_DIR := "res://web_build"


func run_tests() -> void:
	suite_name = "Web 试玩版"
	var args := OS.get_cmdline_user_args()
	var preset_only := args.has("preset-only")
	_test_export_preset()
	_test_page_patch()
	if preset_only and not FileAccess.file_exists("%s/index.html" % OUT_DIR):
		_check("Web 产物检查：跳过（还没构建，先跑 tools/build_web.sh）", true, "preset-only")
		return
	_test_build_output()


func _test_export_preset() -> void:
	_check("项目里有 Web 导出配置（export_presets.cfg）",
		FileAccess.file_exists("res://export_presets.cfg"))
	var config := ConfigFile.new()
	var err := config.load("res://export_presets.cfg")
	_check("导出配置能读出来", err == OK, "err=%d" % err)
	if err != OK:
		return
	_check("有一个叫 Web 的预设，平台是 Web 并且可以直接运行",
		str(config.get_value("preset.0", "name", "")) == "Web"
		and str(config.get_value("preset.0", "platform", "")) == "Web"
		and bool(config.get_value("preset.0", "runnable", false)))
	_check("导出到 web_build/index.html",
		str(config.get_value("preset.0", "export_path", "")) == "web_build/index.html",
		str(config.get_value("preset.0", "export_path", "")))
	_check("关掉线程支持（这样任何静态服务器都能托管，不需要 COOP/COEP 响应头）",
		not bool(config.get_value("preset.0.options", "variant/thread_support", true)))
	_check("画布自适应窗口大小（手机旋转 / 地址栏变化不会变形）",
		int(config.get_value("preset.0.options", "html/canvas_resize_policy", 0)) == 2)
	_check("导出时会生成网站图标", bool(config.get_value("preset.0.options", "html/export_icon", false)))
	_check("导出时自动聚焦画布（手机点一下就能操作）",
		bool(config.get_value("preset.0.options", "html/focus_canvas_on_start", false)))


func _test_page_patch() -> void:
	# 用一份「像 Godot 默认导出的」假 HTML 验证补丁函数
	var sample := "<html><head><meta name=\"viewport\" content=\"width=device-width\">" \
		+ "</head><body><canvas id=\"canvas\"></canvas></body></html>"
	var once := WebPostprocess.patch(sample)
	var twice := WebPostprocess.patch(once)
	_check("补丁函数能给导出页面加上移动端适配", WebPostprocess.verify(once).is_empty(),
		str(WebPostprocess.verify(once)))
	_check("补丁是幂等的（重复执行不会重复插入）", once == twice)
	_check("补丁保留原有内容（没有把 canvas 弄丢）", twice.contains("id=\"canvas\""))
	_check("补丁带上安全区适配（viewport-fit=cover + env(safe-area-inset-*)）",
		once.contains("viewport-fit=cover") and once.contains("env(safe-area-inset-top)"))
	_check("补丁禁用页面滚动 / 双击缩放 / 长按菜单",
		once.contains("touch-action") and once.contains("user-scalable=no")
		and once.contains("contextmenu"))
	_check("补丁带「点击开始」启动页（同时解决浏览器音频解锁）",
		once.contains("id=\"cb-start\"") and once.contains("点击开始"))
	_check("启动页不会吃掉点击（pointer-events:none，点一下就能进游戏）",
		once.contains("pointer-events: none") and once.contains("pointerdown"))
	_check("断网 / 本地文件场景下也不会缺字：页面里引用的资源都在项目里",
		FileAccess.file_exists(Fonts.FONT_PATH))


func _test_build_output() -> void:
	var files := ["index.html", "index.js", "index.wasm", "index.pck", "index.icon.png"]
	var missing: Array = []
	for name in files:
		if not FileAccess.file_exists("%s/%s" % [OUT_DIR, name]):
			missing.append(name)
	_check("Web 产物齐全（html / js / wasm / pck / 图标）", missing.is_empty(), str(missing))
	if not missing.is_empty():
		return
	var html := _read("%s/index.html" % OUT_DIR)
	_check("导出的页面已经打过移动端补丁", WebPostprocess.verify(html).is_empty(),
		str(WebPostprocess.verify(html)))
	_check("页面标题是游戏名（不是 Godot 默认标题）", html.contains("疯狂甩锅"))
	_check("页面里没有开发用调试信息（不会出现 test/debug 字样）",
		not html.to_lower().contains("debug_") and not html.contains("测试按钮"))
	var wasm_size := _size("%s/index.wasm" % OUT_DIR)
	var pck_size := _size("%s/index.pck" % OUT_DIR)
	_check("wasm 体积正常（>5MB）", wasm_size > 5 * 1024 * 1024, "%.1fMB" % (wasm_size / 1048576.0))
	_check("资源包体积正常（含内嵌中文字体，>6MB）", pck_size > 6 * 1024 * 1024,
		"%.1fMB" % (pck_size / 1048576.0))
	_check("中文子集字体真的打进了资源包（Web 端不会缺字）",
		_pck_contains("index.pck", "assets/fonts/NotoSansSC-Regular.otf"))
	_check("主菜单场景也在资源包里", _pck_contains("index.pck", "scenes/main_menu.tscn"))
	_check("Boss 素材目录（贴图 + manifest.json）也打进了资源包",
		_pck_contains("index.pck", "assets/characters/boss/_placeholder_missing_art.png")
		and _pck_contains("index.pck", "assets/characters/boss/manifest.json"))


# ---------------------------------------------------------------- 工具

func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length := file.get_length()
	file.close()
	return length


## 在 pck 里搜一段字符串（pck 的文件表是明文路径，能直接搜到）
func _pck_contains(pck_name: String, needle: String) -> bool:
	var file := FileAccess.open("%s/%s" % [OUT_DIR, pck_name], FileAccess.READ)
	if file == null:
		return false
	# 资源包的文件表（明文路径）在文件末尾，读最后 3MB 做字节查找
	var size := file.get_length()
	var from := maxi(size - 3 * 1024 * 1024, 0)
	file.seek(from)
	var data := file.get_buffer(size - from)
	file.close()
	return _find_bytes(data, needle.to_utf8_buffer()) >= 0


## 在字节数组里找一段字节（PackedByteArray.find 只支持单个字节，所以先找首字节再比整段）
func _find_bytes(haystack: PackedByteArray, needle: PackedByteArray) -> int:
	if needle.is_empty() or haystack.size() < needle.size():
		return -1
	var limit := haystack.size() - needle.size()
	var index := haystack.find(needle[0])
	while index >= 0 and index <= limit:
		if haystack.slice(index, index + needle.size()) == needle:
			return index
		index = haystack.find(needle[0], index + 1)
	return -1
