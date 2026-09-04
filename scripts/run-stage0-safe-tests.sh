#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
test_stamp="$(date +%Y%m%d-%H%M%S)"
results_dir="$project_root/artifacts/stage0-safe-$test_stamp"
probe_app="$project_root/.build/FocusBreakProbe.app"

mkdir -p "$results_dir"

if ! command -v jq >/dev/null; then
    print -u2 -- "jq is required to validate Stage 0 JSON results"
    exit 2
fi

launch_and_wait_for_json() {
    local output_file="$1"
    shift

    open -n "$probe_app" --args "$@" --output "$output_file"
    for _ in {1..100}; do
        if [[ -s "$output_file" ]]; then
            jq -e . "$output_file" >/dev/null
            return 0
        fi
        sleep 0.1
    done

    print -u2 -r -- "Timed out waiting for $output_file"
    return 1
}

cd "$project_root"
swift test
./scripts/build-probe-app.sh >/dev/null
codesign --verify --deep --strict "$probe_app"

launch_and_wait_for_json "$results_dir/snapshot.json" --snapshot
launch_and_wait_for_json "$results_dir/fallback.json" --snapshot-no-accessibility
launch_and_wait_for_json "$results_dir/idle.json" --verify-idle-signal
"$probe_app/Contents/MacOS/focus-break-probe" \
    --verify-synthetic-transitions \
    --output "$results_dir/synthetic-transitions.json" >/dev/null

jq -e '.displays | length >= 1' "$results_dir/snapshot.json" >/dev/null
jq -e '.displays | length >= 1' "$results_dir/fallback.json" >/dev/null
jq -e '.hidAndCombinedAgree == true' "$results_dir/idle.json" >/dev/null
jq -e '
    .sessionTransitionPassed == true and
    .systemSleepTransitionPassed == true and
    .displayNotificationHintsObserved == true and
    .finalStateRestored == true
' "$results_dir/synthetic-transitions.json" >/dev/null

print -r -- "Stage 0 safe tests passed."
print -r -- "Results: $results_dir"
