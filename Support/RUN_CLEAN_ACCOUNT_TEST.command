#!/bin/zsh
set -euo pipefail

test_root="/Users/Shared/FocusBreakAssistant-Test"
probe_app="$test_root/FocusBreakProbe.app"
results_dir="$test_root/results"
test_user="$(id -un)"
test_stamp="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$results_dir"

open -W -n "$probe_app" --args \
  --snapshot \
  --output "$results_dir/snapshot-$test_user-$test_stamp.json"

open -W -n "$probe_app" --args \
  --snapshot-no-accessibility \
  --output "$results_dir/fallback-$test_user-$test_stamp.json"

open -W -n "$probe_app" --args \
  --verify-idle-signal \
  --output "$results_dir/idle-$test_user-$test_stamp.json"

print ""
print "测试完成。结果已保存到："
print "$results_dir"
print ""
print "请切换回原账户并告诉 Codex：干净账户测试已完成。"
print "按任意键关闭此窗口。"
read -k 1
