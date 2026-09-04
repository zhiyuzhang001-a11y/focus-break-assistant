#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
duration="${1:-28800}"
sample_interval="${2:-60}"
label="com.zhiyu.focus-break-assistant.resource-test"
launch_stamp="$(date +%Y%m%d-%H%M%S)"
shared_root="/Users/Shared/FocusBreakAssistant-Test"
run_dir="$shared_root/stage0-resource-$launch_stamp"
stdout_log="$run_dir/launcher.log"
stderr_log="$run_dir/launcher.err"
plist="$run_dir/$label.plist"
domain="gui/$(id -u)"

if job_state="$(launchctl print "$domain/$label" 2>/dev/null)"; then
    if print -r -- "$job_state" | grep -q 'state = running'; then
        print -u2 -- "A detached resource test is already running: $label"
        exit 1
    fi
    launchctl remove "$label"
fi

cd "$project_root"
swift build -c release >/dev/null
mkdir -p "$run_dir"
install -m 755 "$project_root/.build/release/focus-break-probe" "$run_dir/focus-break-probe"
install -m 755 "$project_root/scripts/run-resource-probe-detached-worker.sh" "$run_dir/run-resource-probe-detached-worker.sh"

# Run under the user's launchd domain so the test survives the terminal or
# Codex task ending. The self-contained run directory is under /Users/Shared
# because background services cannot read the user's protected Documents tree.
# `caffeinate -i` prevents idle system sleep only while the probe runs; it does
# not prevent manual sleep or keep the display awake.
plutil -create xml1 "$plist"
plutil -insert Label -string "$label" "$plist"
plutil -insert RunAtLoad -bool true "$plist"
plutil -insert KeepAlive -bool false "$plist"
plutil -insert ProcessType -string Background "$plist"
plutil -insert StandardOutPath -string "$stdout_log" "$plist"
plutil -insert StandardErrorPath -string "$stderr_log" "$plist"
plutil -insert ProgramArguments -json "[\"/usr/bin/caffeinate\",\"-i\",\"/bin/zsh\",\"$run_dir/run-resource-probe-detached-worker.sh\",\"$duration\",\"$sample_interval\"]" "$plist"
launchctl bootstrap "$domain" "$plist"

print -r -- "label=$label"
print -r -- "results=$run_dir"
print -r -- "stdout=$stdout_log"
print -r -- "stderr=$stderr_log"
