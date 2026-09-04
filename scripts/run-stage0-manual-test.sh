#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
probe_binary="$project_root/.build/release/focus-break-probe"
probe_app="$project_root/.build/FocusBreakProbe.app"
scenario="${1:-help}"
duration="${2:-90}"
test_stamp="$(date +%Y%m%d-%H%M%S)"
results_dir="$project_root/artifacts/stage0-manual-$scenario-$test_stamp"

cd "$project_root"
swift build -c release >/dev/null
mkdir -p "$results_dir"

if ! command -v jq >/dev/null; then
    print -u2 -- "jq is required to summarize Stage 0 results"
    exit 2
fi

case "$scenario" in
    fullscreen)
        print "测试将在 $duration 秒内每秒记录一次窗口上下文。"
        print "请依次：切到目标 App → 进入原生全屏 → 等待 5 秒 → 退出全屏 → 等待 5 秒。"
        "$probe_binary" --watch-context "$duration" > "$results_dir/fullscreen.ndjson"
        jq -s '
            [.[] | select(has("focusedWindowFullScreen")) | .focusedWindowFullScreen]
            | reduce .[] as $state ([]; if length == 0 or .[-1] != $state then . + [$state] else . end)
        ' "$results_dir/fullscreen.ndjson" > "$results_dir/fullscreen-sequence.json"
        print -r -- "Observed sequence: $(jq -c . "$results_dir/fullscreen-sequence.json")"
        ;;
    lifecycle)
        print "测试将在 $duration 秒内记录会话切换、系统睡眠、显示器通知提示和轮询状态。"
        print "普通锁屏没有可靠的公开事件；系统睡眠应单独安排，不要在未保存工作时执行。"
        "$probe_binary" --watch "$duration" > "$results_dir/lifecycle.ndjson"
        jq -s '
            {
                events: [.[] | select(has("event")) | .event],
                displaySleepSequence: (
                    [.[] | select(has("displaySleepState")) | .displaySleepState]
                    | reduce .[] as $state ([]; if length == 0 or .[-1] != $state then . + [$state] else . end)
                )
            }
        ' "$results_dir/lifecycle.ndjson" > "$results_dir/lifecycle-summary.json"
        print -r -- "Observed events: $(jq -c '.events' "$results_dir/lifecycle-summary.json")"
        print -r -- "Display sleep sequence: $(jq -c '.displaySleepSequence' "$results_dir/lifecycle-summary.json")"
        ;;
    appearance)
        ./scripts/build-probe-app.sh >/dev/null
        output_file="$results_dir/appearance.json"
        open -n "$probe_app" --args --verify-bundled-overlay --output "$output_file"
        for _ in {1..100}; do
            [[ -s "$output_file" ]] && break
            sleep 0.1
        done
        jq -e . "$output_file" >/dev/null
        jq '{effectiveAppearance, reduceMotionEnabled, increaseContrastEnabled, reduceTransparencyEnabled, frontmostApplicationUnchanged, ignoresMouseEvents}' \
            "$output_file"
        ;;
    *)
        print "Usage:"
        print "  $0 fullscreen [seconds]"
        print "  $0 lifecycle [seconds]"
        print "  $0 appearance"
        exit 2
        ;;
esac

print -r -- "Results: $results_dir"
