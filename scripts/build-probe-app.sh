#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
bundle_path="$project_root/.build/FocusBreakProbe.app"
contents_path="$bundle_path/Contents"

cd "$project_root"
swift build -c release

mkdir -p "$contents_path/MacOS"
cp "$project_root/.build/release/focus-break-probe" "$contents_path/MacOS/focus-break-probe"
cp "$project_root/Support/FocusBreakProbe-Info.plist" "$contents_path/Info.plist"
/usr/bin/codesign --force --sign - "$bundle_path"

print -r -- "$bundle_path"
