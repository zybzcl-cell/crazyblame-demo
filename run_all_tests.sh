#!/bin/bash
# 运行《疯狂甩锅》的全部自动化测试。
#
#   ./run_all_tests.sh              # 全部（含真实窗口截图 + 截图自检）
#   ./run_all_tests.sh --no-window  # 跳过真实窗口部分（没有图形界面时用）
#   GODOT=/path/to/Godot ./run_all_tests.sh
#
# 每一项都是真的把游戏跑起来，全部通过时退出码为 0。
# 除了每套测试自己的「全部通过」，脚本还会检查输出里有没有
# SCRIPT ERROR / ERROR / WARNING，以及有没有卡死（每套都有超时保护）。

set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUITE_TIMEOUT=180
RUN_WINDOW=1
if [ "${1:-}" = "--no-window" ]; then
	RUN_WINDOW=0
fi

if [ ! -x "$GODOT" ]; then
	echo "找不到 Godot：$GODOT（可以用环境变量 GODOT 指定路径）"
	exit 1
fi

# 测试只写 res://tests/.tmp；但如果用户目录不可写（例如在受限沙箱里跑），
# Godot 会因为建不了 user:// 目录而刷错误。这种情况把 HOME 指到临时目录。
if [ ! -w "$HOME" ] || [ ! -d "$HOME/Library/Application Support/Godot" -a ! -w "$HOME/Library" ]; then
	export HOME="$(mktemp -d)"
	echo "（提示：用户目录不可写，本次测试的 user:// 指向临时目录 $HOME）"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SUITES=(
	"冒烟（项目 / 场景 / 音效 / 中文）|res://tests/smoke_test.tscn|"
	"锅与节奏（5 种锅 / 5 个阶段）|res://tests/pot_test.tscn|"
	"玩法与反馈（抓锅 / 拖动 / 伤害 / 阶段 / Combo / Miss）|res://tests/combat_test.tscn|"
	"完整流程（45 秒一局 / 结算 / 重开 / 菜单往返）|res://tests/flow_test.tscn|"
	"计分与评级（0~100 综合评级）|res://tests/score_test.tscn|"
	"存档与解锁（最高分 / 累计 / 解锁 / 坏存档）|res://tests/progress_test.tscn|"
	"输入（鼠标 + 触摸）|res://tests/input_test.tscn|"
	"构图与空间层级（老板 / 办公室 / 操作区 / HUD）|res://tests/composition_test.tscn|"
	"中文字体与文案（内嵌字体覆盖所有 UI 文字）|res://tests/font_test.tscn|"
	"老板甩锅 / 菜单层级 / 受击表现|res://tests/polish_test.tscn|"
)

# 这些是本机环境噪音，不是项目问题（沙箱 / 没有钥匙串访问时会打印）
IGNORE_PATTERN="get_system_ca_certificates|Condition \"ret != noErr\"|Unable to open the keychain"

find_errors() {
	local log="$1"
	grep -E "SCRIPT ERROR|Parse Error|Compile Error|^ERROR:|^WARNING:|WARNING:" "$log" \
		| grep -vE "$IGNORE_PATTERN" | head -5
}

## 带超时地跑一个 Godot 命令：卡住就杀掉，绝不让测试挂死
run_godot() {
	local log="$1"
	local timeout="$2"
	shift 2
	"$GODOT" "$@" >"$log" 2>&1 &
	local pid=$!
	local waited=0
	while kill -0 "$pid" 2>/dev/null; do
		sleep 0.2
		waited=$((waited + 1))
		if [ "$waited" -ge $((timeout * 5)) ]; then
			kill -9 "$pid" 2>/dev/null
			wait "$pid" 2>/dev/null
			return 124
		fi
	done
	wait "$pid"
	return $?
}

run_suite() {
	local name="$1"
	local scene="$2"
	local extra="${3:-}"
	local log="$TMP_DIR/$(echo "$scene" | tr '/.' '__').log"
	# shellcheck disable=SC2086
	run_godot "$log" "$SUITE_TIMEOUT" --headless --path "$PROJECT_DIR" "$scene" $extra
	local code=$?
	local summary
	summary="$(grep -E '^=====.*项通过' "$log" | tail -1)"
	local errors
	errors="$(find_errors "$log")"
	if [ $code -eq 124 ]; then
		printf '  [超时] %-44s %s\n' "$name" "$summary"
		return 1
	fi
	if [ $code -eq 0 ] && [ -z "$errors" ]; then
		printf '  [通过] %-44s %s\n' "$name" "$summary"
		return 0
	fi
	printf '  [失败] %-44s %s（退出码 %d）\n' "$name" "$summary" "$code"
	grep -E '^\[失败\]|失败项：' "$log" | head -8
	if [ -n "$errors" ]; then
		echo "$errors"
	fi
	return 1
}

echo "===== 《疯狂甩锅》自动化测试 ====="
echo "----- 准备：Web 试玩版产物 -----"
if [ -f "$PROJECT_DIR/web_build/index.html" ]; then
	echo "  已有 web_build（要重新构建：./tools/build_web.sh）"
elif [ -x "$PROJECT_DIR/tools/build_web.sh" ]; then
	echo "  还没有 Web 产物，先构建一次"
	if ! "$PROJECT_DIR/tools/build_web.sh" >"$TMP_DIR/web_build.log" 2>&1; then
		echo "  Web 构建跳过（缺少导出模板等，细节见日志），相关检查会退化成只查配置"
	fi
fi
echo "----- 准备：导入资源（首次运行会生成 .godot 缓存）-----"
IMPORT_LOG="$TMP_DIR/import.log"
run_godot "$IMPORT_LOG" 120 --headless --path "$PROJECT_DIR" --import
IMPORT_ERRORS="$(find_errors "$IMPORT_LOG")"
if [ -n "$IMPORT_ERRORS" ]; then
	echo "  导入有问题："
	echo "$IMPORT_ERRORS"
	exit 1
fi
echo "  导入完成"

FAILED=0
for entry in "${SUITES[@]}"; do
	IFS='|' read -r name scene extra <<<"$entry"
	run_suite "$name" "$scene" "$extra" || FAILED=1
done

# 跨进程存档：同一个存档文件，先写入再读取（必须是两个进程）
PERSIST_SAVE="$PROJECT_DIR/tests/.tmp/cross_process.json"
for MODE in write verify; do
	LOG="$TMP_DIR/persist_$MODE.log"
	run_godot "$LOG" 120 --headless --path "$PROJECT_DIR" \
		res://tests/save_persistence_test.tscn -- "$MODE" "res://tests/.tmp/cross_process.json"
	CODE=$?
	SUMMARY="$(grep -E '^=====.*项通过' "$LOG" | tail -1)"
	ERRORS="$(find_errors "$LOG")"
	if [ $CODE -eq 0 ] && [ -z "$ERRORS" ]; then
		printf '  [通过] %-44s %s\n' "跨进程存档（${MODE}）" "$SUMMARY"
	else
		printf '  [失败] %-44s %s\n' "跨进程存档（${MODE}）" "$SUMMARY"
		grep -E '^\[失败\]|失败项：' "$LOG" | head -6
		[ -n "$ERRORS" ] && echo "$ERRORS"
		FAILED=1
	fi
done
rm -f "$PERSIST_SAVE"

if [ "$RUN_WINDOW" -eq 1 ]; then
	echo "----- 真实窗口（会开一个窗口、真的渲染并截图）-----"
	WINDOW_LOG="$TMP_DIR/window.log"
	# --quit-after 是硬保险：就算测试脚本出问题也不会让窗口一直挂着
	run_godot "$WINDOW_LOG" "$SUITE_TIMEOUT" --path "$PROJECT_DIR" --quit-after 4000 \
		res://tests/visual_capture.tscn
	CODE=$?
	SUMMARY="$(grep -E '^=====.*项通过' "$WINDOW_LOG" | tail -1)"
	ERRORS="$(find_errors "$WINDOW_LOG")"
	if [ $CODE -eq 0 ] && [ -z "$ERRORS" ]; then
		printf '  [通过] %-44s %s\n' "实机窗口 + 截图" "$SUMMARY"
	else
		printf '  [失败] %-44s %s（退出码 %d）\n' "实机窗口 + 截图" "$SUMMARY" "$CODE"
		grep -E '^\[失败\]|失败项：' "$WINDOW_LOG" | head -6
		[ -n "$ERRORS" ] && echo "$ERRORS"
		FAILED=1
	fi
	run_suite "截图自检（画面真的是画出来的）" "res://tests/visual_check_test.tscn" || FAILED=1
else
	echo "----- 已跳过真实窗口部分（--no-window）-----"
fi

echo "----- Web 试玩版 -----"
if [ -f "$PROJECT_DIR/web_build/index.html" ]; then
	run_suite "Web 试玩版（导出配置 / 页面补丁 / 产物）" "res://tests/web_test.tscn" || FAILED=1
else
	run_suite "Web 试玩版（只查配置与补丁逻辑）" "res://tests/web_test.tscn" "-- preset-only" || FAILED=1
fi

echo "===== 结论：$([ $FAILED -eq 0 ] && echo 全部通过 || echo 存在失败项) ====="
exit $FAILED
