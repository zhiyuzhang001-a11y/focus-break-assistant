#!/bin/zsh
set -euo pipefail

run_dir="${0:A:h}"
duration="${1:-28800}"
sample_interval="${2:-60}"
probe_binary="$run_dir/focus-break-probe"
samples_file="$run_dir/process-samples.csv"
activity_file="$run_dir/activity.ndjson"
summary_file="$run_dir/summary.txt"
started_at="$(date +%s)"
completed=false

print "elapsed_seconds,rss_kb,cpu_percent" > "$samples_file"
print -r -- "started_at_epoch=$started_at" > "$run_dir/run-status.txt"
print -r -- "duration_seconds=$duration" >> "$run_dir/run-status.txt"

"$probe_binary" --watch "$duration" > "$activity_file" &
probe_pid=$!
print -r -- "probe_pid=$probe_pid" >> "$run_dir/run-status.txt"

finish() {
    exit_code=$?
    if kill -0 "$probe_pid" 2>/dev/null; then
        kill "$probe_pid" 2>/dev/null || true
        wait "$probe_pid" 2>/dev/null || true
    fi

    awk -F, '
        NR == 2 { first=$2; min=$2; max=$2 }
        NR > 1 {
            count += 1; last=$2; cpu += $3
            if ($2 < min) min=$2
            if ($2 > max) max=$2
            elapsed=$1
        }
        END {
            printf "samples=%d\n", count
            if (count > 0) {
                printf "elapsed_seconds=%d\nfirst_rss_kb=%d\nlast_rss_kb=%d\nmin_rss_kb=%d\nmax_rss_kb=%d\nrss_delta_kb=%d\naverage_cpu_percent=%.6f\n", elapsed, first, last, min, max, last-first, cpu/count
            }
        }
    ' "$samples_file" > "$summary_file"

    if [[ "$completed" == true && "$exit_code" == 0 ]]; then
        print -r -- "status=complete" >> "$summary_file"
    else
        print -r -- "status=interrupted" >> "$summary_file"
    fi
    print -r -- "finished_at_epoch=$(date +%s)" >> "$run_dir/run-status.txt"
}
trap finish EXIT
trap 'exit 130' INT TERM

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
completed=true

