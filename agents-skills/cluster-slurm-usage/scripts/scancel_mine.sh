#!/usr/bin/env bash
# Cancel SLURM jobs, but only if every one of them belongs to the current user.
# All-or-nothing: if any ID is malformed or owned by someone else, nothing is cancelled.
# Usage: scancel_mine.sh JOBID [JOBID ...]   (JOBID is 123 or 123_4)
set -euo pipefail

me="$(id -un)"

if [[ $# -lt 1 ]]; then
    echo "usage: $0 JOBID [JOBID ...]" >&2
    exit 2
fi

to_cancel=()
for id in "$@"; do
    if [[ ! "$id" =~ ^[0-9]+(_[0-9]+)?$ ]]; then
        echo "refusing: '$id' is not a plain job ID (use 123 or 123_4)" >&2
        exit 2
    fi

    owners="$(squeue -h -j "$id" -o '%u' 2>/dev/null | sort -u || true)"
    if [[ -z "$owners" ]]; then
        echo "skip $id: not in the queue (already finished or wrong ID)"
        continue
    fi
    if [[ "$owners" != "$me" ]]; then
        echo "refusing: job $id is owned by '$(echo "$owners" | paste -sd, -)', not '$me'; nothing was cancelled" >&2
        exit 3
    fi
    to_cancel+=("$id")
done

if [[ ${#to_cancel[@]} -eq 0 ]]; then
    echo "nothing to cancel"
    exit 0
fi

# --user makes SLURM itself ignore any job that is not ours, as a second guard.
scancel --user="$me" "${to_cancel[@]}"
echo "cancelled: ${to_cancel[*]}"
