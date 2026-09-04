#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
test_stamp="$(date +%Y%m%d-%H%M%S)"
results_dir="$project_root/artifacts/stage1-visual-$test_stamp"
matrix_dir="$results_dir/matrix"
probe="$project_root/.build/debug/focus-break-probe"

mkdir -p "$results_dir"
cd "$project_root"
swift test

"$probe" --render-visual-matrix "$matrix_dir" > "$results_dir/matrix-manifest.json"
jq -e '.files | length == 10' "$results_dir/matrix-manifest.json" >/dev/null

for point_size in 13 14; do
    "$probe" --verify-overlay "$point_size" \
        --output "$results_dir/overlay-$point_size.json" >/dev/null
    jq -e --argjson point_size "$point_size" '
        .frontmostApplicationUnchanged == true and
        .ignoresMouseEvents == true and
        .canBecomeKey == false and
        .canBecomeMain == false and
        .isKeyWindow == false and
        .isMainWindow == false and
        .textPointSize == $point_size
    ' "$results_dir/overlay-$point_size.json" >/dev/null
done

"$probe" --verify-preview-menu --output "$results_dir/preview-menu.json" >/dev/null
jq -e '
    .hasStatusItemButton == true and
    .hasTemplateIcon == true and
    .menuItemTitles == ["预览一次提醒", "退出预览"] and
    .overlay.frontmostApplicationUnchanged == true and
    .overlay.ignoresMouseEvents == true and
    .overlay.canBecomeKey == false and
    .overlay.canBecomeMain == false
' "$results_dir/preview-menu.json" >/dev/null

print -r -- "Stage 1 automated visual checks passed."
print -r -- "Results: $results_dir"
