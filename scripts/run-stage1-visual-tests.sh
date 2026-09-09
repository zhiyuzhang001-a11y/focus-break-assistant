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
"$probe" --verify-photo-library > "$results_dir/photo-library.json"
jq -e 'all(.[]; . == true)' "$results_dir/photo-library.json" >/dev/null

"$probe" --render-visual-matrix "$matrix_dir" > "$results_dir/matrix-manifest.json"
jq -e '.files | length == 18' "$results_dir/matrix-manifest.json" >/dev/null

for point_size in 32 36; do
    "$probe" --verify-overlay "$point_size" \
        --output "$results_dir/overlay-$point_size.json" >/dev/null
    jq -e --argjson point_size "$point_size" '
        .frontmostApplicationUnchanged == true and
        .ignoresMouseEvents == true and
        .canBecomeKey == false and
        .canBecomeMain == false and
        .isKeyWindow == false and
        .isMainWindow == false and
        .textPointSize >= 28 and .textPointSize <= 48
    ' "$results_dir/overlay-$point_size.json" >/dev/null
done

"$probe" --verify-preview-menu --output "$results_dir/preview-menu.json" >/dev/null
jq -e '
    .hasStatusItemButton == true and
    .hasTemplateIcon == true and
    .menuItemTitles[1:4] == ["暂停自动提醒", "预览下一张", "设置…"] and
    (.menuItemTitles | length) == 5 and
    .menuItemTitles[-1] == "退出 Focus Break Assistant" and
    .overlay.frontmostApplicationUnchanged == true and
    .overlay.ignoresMouseEvents == false and
    .overlay.canBecomeKey == true and
    .overlay.canBecomeMain == false
' "$results_dir/preview-menu.json" >/dev/null

"$project_root/scripts/build-probe-app.sh" >/dev/null
resource_bundle="$project_root/.build/FocusBreakProbe.app/Contents/Resources/FocusBreakAssistant_FocusBreakProbe.bundle"
test -f "$resource_bundle/Seascape.jpg"
/usr/bin/codesign --verify --deep --strict "$project_root/.build/FocusBreakProbe.app"

print -r -- "Stage 1 automated visual checks passed."
print -r -- "Results: $results_dir"
