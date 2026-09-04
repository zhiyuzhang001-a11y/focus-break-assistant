#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
duration="${1:-28800}"
sample_interval="${2:-60}"
test_stamp="$(date +%Y%m%d-%H%M%S)"
results_dir="$project_root/artifacts/stage0-resource-$test_stamp"
probe_binary="$project_root/.build/release/focus-break-probe"
samples_file="$results_dir/process-samples.csv"

if (( duration < 10 || sample_interval < 1 )); then
    print -u2 -- "duration must be >= 10 seconds and sample interval >= 1 second"
    exit 2
fi

cd "$project_root"
swift build -c release >/dev/null
mkdir -p "$results_dir"
print "elapsed_seconds,rss_kb,cpu_percent" > "$samples_file"

"$probe_binary" --watch "$duration" > "$results_dir/activity.ndjson" &
probe_pid=$!
started_at="$(date +%s)"

cleanup() {
    if kill -0 "$probe_pid" 2>/dev/null; then
        kill "$probe_pid" 2>/dev/null || true
        wait "$probe_pid" 2>/dev/null || true
    fi
}
trap cleanup INT TERM EXIT

# Let dyld and the Swift runtime finish their initial page-in before recording the
# first resident-set sample. Startup is still present in activity.ndjson, while
# the RSS trend now begins from a meaningful steady-process value.
sleep 1

while kill -0 "$probe_pid" 2>/dev/null; do
    now="$(date +%s)"
    elapsed=$(( now - started_at ))
    process_sample="$(ps -o rss=,%cpu= -p "$probe_pid" | awk '{$1=$1; print}')"
    if [[ -n "$process_sample" ]]; then
        rss_kb="${process_sample%% *}"
        cpu_percent="${process_sample##* }"
        print "$elapsed,$rss_kb,$cpu_percent" >> "$samples_file"
    fi
    sleep "$sample_interval"
done
wait "$probe_pid"
trap - INT TERM EXIT

awk -F, '
    NR == 2 { first=$2; max=$2; last=$2 }
    NR > 1 { if ($2 > max) max=$2; last=$2; cpu += $3; count += 1 }
    END {
        if (count == 0) {
            print "samples=0"
            exit 1
        }
        printf "samples=%d\nfirst_rss_kb=%d\nlast_rss_kb=%d\nmax_rss_kb=%d\naverage_cpu_percent=%.4f\n", count, first, last, max, cpu/count
    }
' "$samples_file" | tee "$results_dir/summary.txt"

print -r -- "Results: $results_dir"
