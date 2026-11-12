#!/usr/bin/env bash
# Read-only snapshot of cluster load and of the current user's standing.
# Used to decide between `bulk` (when it can start now) and `normal`.
set -uo pipefail

me="$(id -un)"
partitions="cpu,debug,normal,bulk"

echo "== Partitions: availability, max time (%l), default time (%L), nodes, GPUs =="
sinfo -p "$partitions" -o "%12P %6a %12l %12L %6D %G"

echo
echo "== CPUs per partition (allocated/idle/other/total) =="
sinfo -p "$partitions" -o "%12P %C"

echo
echo "== GPUs per partition: configured vs in use =="
sinfo -p "$partitions" -O "Partition:12,Gres:40,GresUsed:50" 2>/dev/null \
    || echo "(this SLURM version cannot show GresUsed; compare 'squeue -p <part> -t R -o %b' with 'sinfo -o \"%P %G %D\"')"

echo
echo "== Queue depth (running / pending jobs) =="
for p in ${partitions//,/ }; do
    running="$(squeue -h -p "$p" -t R 2>/dev/null | wc -l)"
    pending="$(squeue -h -p "$p" -t PD 2>/dev/null | wc -l)"
    printf '%-8s running=%-5s pending=%s\n' "$p" "$running" "$pending"
done

echo
echo "== Preemption settings of bulk =="
scontrol show partition bulk 2>/dev/null | grep -Eio '(PreemptMode|PriorityTier|MaxTime|DefaultTime)=[^ ]+' | paste -sd' ' -

echo
echo "== Can bulk start now, and who could preempt it? =="
bash "$(dirname "$0")/bulk_availability.sh" || echo "(could not check bulk availability)"

echo
echo "== My fair share compared with the other users =="
bash "$(dirname "$0")/fairshare_rank.sh" || echo "(could not rank fair share)"

echo
echo "== My jobs =="
squeue -u "$me" -o "%.12i %.9P %.24j %.2t %.11M %.11l %.14b %R"
