#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
probe_app="$project_root/.build/FocusBreakProbe.app"

cd "$project_root"
"$project_root/scripts/build-probe-app.sh" >/dev/null
open -n "$probe_app" --args --preview-menu

print -r -- "Focus Break Assistant preview menu is running."
