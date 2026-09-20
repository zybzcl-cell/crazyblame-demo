#!/bin/bash
# 构建《疯狂甩锅》Web 试玩版。
#
#   ./tools/build_web.sh
#   GODOT=/path/to/Godot ./tools/build_web.sh
#
# 产物在项目根目录的 web_build/ 下，可以直接上传到任何静态网页服务器
# （GitHub Pages / Netlify / Vercel / 自己的 Nginx 都行）。
#
# 步骤：
#   1. 检查 Web 导出模板（没有就提示去哪下载）
#   2. Godot 导出 --export-release Web web_build/index.html
#   3. 给导出的 index.html 打上移动端补丁（安全区 / 禁缩放 / 点击开始启动页）
#   4. 打印产物清单与体积

set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$PROJECT_DIR/web_build"
TEMPLATE_DIR="$HOME/Library/Application Support/Godot/export_templates"
VERSION="$("$GODOT" --version 2>/dev/null | sed 's/\.stable.*/.stable/; s/\.official.*//')"

if [ ! -x "$GODOT" ]; then
	echo "找不到 Godot：$GODOT（可以用环境变量 GODOT 指定）"
	exit 1
fi

echo "===== 构建 Web 试玩版 ====="
if [ ! -d "$TEMPLATE_DIR" ] || ! ls "$TEMPLATE_DIR"/*/web_nothreads_release.zip >/dev/null 2>&1; then
	echo "缺少 Web 导出模板。请任选一种方式准备："
	echo "  A. 打开 Godot 编辑器 → 编辑器 → 管理导出模板 → 下载（会自动放到 ${TEMPLATE_DIR}）"
	echo "  B. 手动下载 Godot_v${VERSION}_export_templates.tpz 并解压出 templates/web_*.zip 与 version.txt，"
	echo "     放进 ${TEMPLATE_DIR}/<版本号>/"
	exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

## 带超时地跑一步（避免某个步骤卡住把构建挂死）
run_step() {
	local timeout="$1"
	shift
	"$@" &
	local pid=$!
	local waited=0
	while kill -0 "$pid" 2>/dev/null; do
		sleep 0.2
		waited=$((waited + 1))
		if [ "$waited" -ge $((timeout * 5)) ]; then
			kill -9 "$pid" 2>/dev/null
			echo "步骤超时（${timeout}s）：$*"
			return 124
		fi
	done
	wait "$pid"
}

echo "----- 1/2 导出 -----"
run_step 600 "$GODOT" --headless --path "$PROJECT_DIR" --export-release "Web" "$OUT_DIR/index.html"
STATUS=$?
if [ $STATUS -ne 0 ] || [ ! -f "$OUT_DIR/index.html" ]; then
	echo "导出失败（退出码 $STATUS）"
	exit 1
fi

echo "----- 2/2 移动端页面补丁 -----"
run_step 120 "$GODOT" --headless --path "$PROJECT_DIR" res://tools/web_postprocess.tscn -- "$OUT_DIR/index.html"
if ! grep -q "crazy-blame-mobile" "$OUT_DIR/index.html"; then
	echo "页面补丁没有生效（index.html 里找不到标记）"
	exit 1
fi

echo "----- 产物 -----"
ls -lh "$OUT_DIR" | tail -n +2 | awk '{ printf "  %-28s %s\n", $9, $5 }'
echo "总计：$(du -sh "$OUT_DIR" | cut -f1)"
echo "===== 完成：$OUT_DIR/index.html ====="
