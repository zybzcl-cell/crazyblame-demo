class_name WebPostprocess
extends Node
## Web 试玩版的页面补丁：给 Godot 导出的 index.html 加上「移动端能直接用」的那一层。
##
## 为什么要补：Godot 默认导出的 HTML 是能跑的最小页面，但手机上还需要——
##   - 视口与安全区：`viewport-fit=cover` + `env(safe-area-inset-*)`，避免被刘海 / 状态栏 / 地址栏裁掉；
##   - 禁止滚动、双击缩放、长按菜单、橡皮筋回弹；
##   - 一个「点击开始」的启动页（同时把浏览器的音频解锁交给这第一次点击）；
##   - 与游戏一致的深色底 + 加载进度样式。
##
## 补丁是幂等的：重复执行只会替换自己写进去的那一段，不会重复堆叠。

const STYLE_BEGIN := "<!-- crazy-blame-mobile:style:begin -->"
const STYLE_END := "<!-- crazy-blame-mobile:style:end -->"
const OVERLAY_BEGIN := "<!-- crazy-blame-mobile:overlay:begin -->"
const OVERLAY_END := "<!-- crazy-blame-mobile:overlay:end -->"
const MARKER := "crazy-blame-mobile"


## 命令行用法：Godot --headless --path . res://tools/web_postprocess.tscn -- <index.html>
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("用法：Godot --headless --path . res://tools/web_postprocess.tscn -- <index.html>")
		get_tree().quit(1)
		return
	var path := str(args[0])
	if not FileAccess.file_exists(path):
		print("找不到文件：%s" % path)
		get_tree().quit(1)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var html := file.get_as_text()
	file.close()
	var patched := patch(html)
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		print("写不进去：%s" % path)
		get_tree().quit(1)
		return
	out.store_string(patched)
	out.close()
	print("已应用移动端页面补丁：%s（%d → %d 字节）" % [path, html.length(), patched.length()])
	get_tree().quit(0)


## 纯函数：给定导出出来的 HTML，返回打过补丁的 HTML（测试直接调它）
static func patch(html: String) -> String:
	var result := _remove_block(html, STYLE_BEGIN, STYLE_END)
	result = _remove_block(result, OVERLAY_BEGIN, OVERLAY_END)
	result = _ensure_viewport_meta(result)
	result = _insert_before(result, "</head>", "%s\n%s\n%s" % [STYLE_BEGIN, STYLE, STYLE_END])
	result = _insert_before(result, "</body>",
		"%s\n%s\n%s" % [OVERLAY_BEGIN, OVERLAY, OVERLAY_END])
	return result


## 补丁里有没有该有的东西（测试与构建脚本自检用）
static func verify(html: String) -> Array:
	var problems: Array = []
	if not html.contains(STYLE_BEGIN) or not html.contains(OVERLAY_BEGIN):
		problems.append("缺少移动端补丁块")
	if not html.contains("viewport-fit=cover"):
		problems.append("缺少 viewport-fit=cover（安全区适配）")
	if not html.contains("env(safe-area-inset-top)"):
		problems.append("缺少安全区 padding")
	if not html.contains("id=\"cb-start\""):
		problems.append("缺少「点击开始」启动页")
	if not html.contains("touch-action"):
		problems.append("缺少触摸手势限制")
	if html.count(STYLE_BEGIN) > 1 or html.count(OVERLAY_BEGIN) > 1:
		problems.append("补丁块被重复插入")
	return problems


# ---------------------------------------------------------------- 注入内容

const STYLE := """<style>
	html, body {
		margin: 0; padding: 0; width: 100%; height: 100%;
		background: #1b1f27; color: #e9eef5; overflow: hidden;
		overscroll-behavior: none;
		-webkit-user-select: none; user-select: none;
		-webkit-tap-highlight-color: transparent;
		-webkit-touch-callout: none;
		touch-action: none;
		font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Noto Sans SC",
			"Microsoft YaHei", sans-serif;
	}
	#canvas {
		display: block; width: 100%; height: 100%; outline: none;
		/* 手机竖屏安全区：刘海 / 状态栏 / 底部小横条都不会裁掉画面 */
		padding: env(safe-area-inset-top) env(safe-area-inset-right)
			env(safe-area-inset-bottom) env(safe-area-inset-left);
		box-sizing: border-box;
		background: #1b1f27;
	}
	#status {
		position: absolute; left: 0; right: 0; bottom: 0; top: 0;
		display: flex; align-items: center; justify-content: center;
		background: #1b1f27; color: #e9eef5; font-size: 15px; letter-spacing: 1px;
	}
	#status-progress { color: #ffc857; font-weight: 600; }
	#cb-start {
		position: fixed; inset: 0; z-index: 30; display: flex;
		align-items: center; justify-content: center;
		background: radial-gradient(circle at 50% 35%, #2f3742 0%, #1b1f27 70%);
		transition: opacity .35s ease; pointer-events: none;
	}
	#cb-start.cb-hidden { opacity: 0; }
	#cb-start .cb-card { text-align: center; padding: 0 8vw; }
	#cb-start .cb-title {
		font-size: 13vw; font-weight: 700; letter-spacing: .06em; color: #ffc857;
		text-shadow: 0 6px 0 rgba(0, 0, 0, .35);
	}
	#cb-start .cb-sub { margin-top: 2.5vh; font-size: 4.2vw; color: #e9eef5; }
	#cb-start .cb-tap {
		margin-top: 7vh; font-size: 6vw; font-weight: 700; color: #e9eef5;
		animation: cb-pulse 1.4s ease-in-out infinite;
	}
	#cb-start .cb-tip { margin-top: 2vh; font-size: 3.4vw; color: #a9b4c2; }
	@keyframes cb-pulse { 0%, 100% { opacity: .55 } 50% { opacity: 1 } }
</style>"""

const OVERLAY := """<div id="cb-start">
	<div class="cb-card">
		<div class="cb-title">疯狂甩锅</div>
		<div class="cb-sub">老板甩过来的锅，一口一口甩回去</div>
		<div class="cb-tap">点击开始</div>
		<div class="cb-tip">竖屏游玩 · 支持触摸与鼠标</div>
	</div>
</div>
<script>
	// 启动页只是「第一次点击」的提示：它不吃任何触摸事件（pointer-events:none），
	// 所以这一下点击会直接落到游戏画布上 —— 既解锁了浏览器音频，也能直接点「开始甩锅」。
	(function () {
		var overlay = document.getElementById('cb-start');
		var canvas = document.getElementById('canvas');
		function dismiss() {
			if (!overlay) { return; }
			overlay.classList.add('cb-hidden');
			setTimeout(function () { if (overlay && overlay.parentNode) { overlay.parentNode.removeChild(overlay); } }, 400);
			if (canvas && canvas.focus) { try { canvas.focus(); } catch (e) {} }
			['pointerdown', 'mousedown', 'touchstart', 'click', 'keydown'].forEach(function (type) {
				document.removeEventListener(type, dismiss, true);
			});
		}
		['pointerdown', 'mousedown', 'touchstart', 'click', 'keydown'].forEach(function (type) {
			document.addEventListener(type, dismiss, true);
		});
		document.addEventListener('contextmenu', function (e) { e.preventDefault(); });
		document.addEventListener('dblclick', function (e) { e.preventDefault(); });
		document.addEventListener('gesturestart', function (e) { e.preventDefault(); });
		// 手机地址栏收起 / 展开时重新量一次画布，避免画面被挤扁
		function refit() { window.dispatchEvent(new Event('resize')); }
		window.addEventListener('orientationchange', function () { setTimeout(refit, 250); });
	})();
</script>"""


# ---------------------------------------------------------------- 内部工具

static func _remove_block(html: String, begin: String, end: String) -> String:
	var from := html.find(begin)
	if from < 0:
		return html
	var to := html.find(end, from)
	if to < 0:
		return html
	to += end.length()
	# 连同标记前后的空白一起去掉，保证「重复打补丁」得到一模一样的结果
	while from > 0 and _is_space(html.substr(from - 1, 1)):
		from -= 1
	while to < html.length() and _is_space(html.substr(to, 1)):
		to += 1
	return html.substr(0, from) + html.substr(to)


static func _is_space(character: String) -> bool:
	return character == "\n" or character == "\t" or character == " "


static func _insert_before(html: String, needle: String, content: String) -> String:
	var index := html.find(needle)
	if index < 0:
		return html + "\n" + content
	return html.substr(0, index) + content + "\n" + html.substr(index)


## 保证 viewport meta 带 viewport-fit=cover（否则安全区算不出来）
static func _ensure_viewport_meta(html: String) -> String:
	var marker := "name=\"viewport\""
	if not html.contains(marker):
		return _insert_before(html, "</head>", CANONICAL_VIEWPORT)
	var start := html.find("<meta", html.find(marker) - 200 if html.find(marker) > 200 else 0)
	if start < 0:
		return html
	var end := html.find(">", start)
	if end < 0:
		return html
	var tag := html.substr(start, end - start + 1)
	var fixed := tag
	if fixed.contains("content=\"") and fixed.contains("viewport-fit") \
			and fixed.contains("user-scalable"):
		pass
	elif fixed.contains("content=\""):
		fixed = fixed.replace("content=\"", "content=\"viewport-fit=cover, ")
		if not fixed.contains("user-scalable"):
			fixed = fixed.replace(">", ", maximum-scale=1, user-scalable=no>")
	else:
		fixed = CANONICAL_VIEWPORT
	return html.substr(0, start) + fixed + html.substr(end + 1)


const CANONICAL_VIEWPORT := "<meta name=\"viewport\" content=\"viewport-fit=cover, width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no\">"
