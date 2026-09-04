#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
shared_root="/Users/Shared/FocusBreakAssistant-Test"
shared_app="$shared_root/FocusBreakProbe.app"
shared_runner="$shared_root/RUN_CLEAN_ACCOUNT_TEST.command"

cd "$project_root"
"$project_root/scripts/build-probe-app.sh" >/dev/null

mkdir -p "$shared_root/results"
ditto "$project_root/.build/FocusBreakProbe.app" "$shared_app"
cp "$project_root/Support/RUN_CLEAN_ACCOUNT_TEST.command" "$shared_runner"
chmod 755 "$shared_runner"
chmod 1777 "$shared_root/results"

print -r -- "$shared_root"
