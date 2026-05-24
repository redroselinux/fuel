#!/bin/bash
set -o pipefail

get_weight() {
    local pkg="$1"
    local f="fuelpkgs/$pkg/metadata"
    [ -f "$f" ] || return 1
    local w
    w=$(grep -oP 'CompilingWeight\s*=\s*"\K[^"]+' "$f") || return 1
    echo "$w"
}

max_concurrent() {
    case "$1" in
        tiny) echo 6 ;;
        small) echo 3 ;;
        small-to-medium) echo 2 ;;
        medium) echo 2 ;;
        medium-to-large) echo 1 ;;
        huge) echo 1 ;;
        *) echo 2 ;;
    esac
}

run_tier() {
    local max="$1"; shift
    local failed=0 pids=() i=0
    for pkg; do
        unbuffer ./fuel build "$pkg" 2>&1 | sed -u "s/^/[$pkg] /" &
        pids+=($!)
        i=$((i + 1))
        if [ "$i" -ge "$max" ]; then
            for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
            pids=(); i=0
        fi
    done
    for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
    return "$failed"
}

declare -A weight_of
all_pkgs=()
for d in fuelpkgs/*/; do
    pkg=$(basename "$d")
    w=$(get_weight "$pkg") || continue
    weight_of["$pkg"]="$w"
    all_pkgs+=("$pkg")
done

# Sort by weight priority
weight_order=(tiny small small-to-medium medium medium-to-large huge)
declare -A rank
for i in "${!weight_order[@]}"; do rank[${weight_order[$i]}]=$i; done

mapfile -t sorted < <(
    for pkg in "${all_pkgs[@]}"; do
        echo "${rank[${weight_of[$pkg]}]:-99} $pkg"
    done | sort -n | while read -r _ p; do echo "$p"; done
)

failed=0
current_weight=""
batch=()
flush_batch() {
    [ ${#batch[@]} -eq 0 ] && return
    local max
    max=$(max_concurrent "$current_weight")
    run_tier "$max" "${batch[@]}" || failed=1
    batch=()
}

for pkg in "${sorted[@]}"; do
    w="${weight_of[$pkg]}"
    if [ "$w" != "$current_weight" ] && [ -n "$current_weight" ]; then
        flush_batch
    fi
    current_weight="$w"
    batch+=("$pkg")
done
flush_batch

exit "$failed"
