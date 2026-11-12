#!/usr/bin/env bash
# Read-only check of whether a `bulk` job can start right now and how likely
# it is to be preempted afterwards.
#
# `bulk` jobs never preempt anything: they start only on GPUs that are idle
# now. `normal` and `debug` jobs preempt them. On `normal` a job only runs on
# the smallest GPU model matching its VRAM declaration (or the model pinned in
# --gres), so a bulk job is threatened only by normal/debug jobs that need its
# model. Users who already hold their full `normal` GPU allowance cannot start
# more normal jobs, so they are no threat until one of their jobs ends.
#
# Sections:
#   1. idle GPUs per node of `bulk` (with idle CPUs and free RAM);
#   2. pending normal/debug GPU jobs per model, split into
#        ready      - waiting only for priority/resources: may preempt soon;
#        dependency - will become ready when its dependency is satisfied;
#        capped     - blocked by a per-user/account limit (e.g. QOSMaxGRESPerUser);
#   3. per user: GPUs running on normal/debug QoS vs. the QoS limit
#      (MAXED users cannot start more normal jobs);
#   4. summary per GPU model.
#
# Usage: bulk_availability.sh
set -uo pipefail

me="$(id -un)"

# GPU model by VRAM declaration in GiB (smallest model whose range covers it).
model_for_vram='
function vram_gib(c,   v, n, u) {
    if (!match(c, /vram=[0-9]+[GM]/)) return -1
    v = substr(c, RSTART + 5, RLENGTH - 5)
    u = substr(v, length(v), 1); n = substr(v, 1, length(v) - 1) + 0
    return (u == "M") ? n / 1024 : n
}
function model_of(gres, comment,   g, parts, n) {
    # pinned model wins: gres/gpu:<model>:<n> or gpu:<model>:<n>
    g = gres; sub(/^gres\//, "", g)
    n = split(g, parts, ":")
    if (n >= 3) return parts[2]
    v = vram_gib(comment)
    if (v < 0)   return "?"
    if (v <= 22) return "l4"
    if (v <= 24) return "quadro_rtx_6000"
    if (v <= 47) return "nvidia_rtx_a6000"
    if (v <= 95) return "rtx_pro_6000"
    return "none"
}
function gpus_of(gres,   g, parts, n) {
    g = gres; sub(/^gres\//, "", g)
    n = split(g, parts, ":")
    return (g ~ /^gpu/) ? parts[n] + 0 : 0
}
'

echo "== 1. Idle resources per node of bulk (bulk jobs start only on idle GPUs) =="
sinfo -N -p bulk -h -O "NodeList:20,StateLong:20,CPUsState:24,Memory:12,AllocMem:12,Gres:50,GresUsed:60" \
| awk '
    {
        node = $1; state = $2; split($3, c, "/"); mem = $4; alloc = $5
        g = $6; sub(/\(.*/, "", g); n = split(g, p, ":"); model = p[2]; total = p[n] + 0
        u = $7; sub(/\(.*/, "", u); n = split(u, q, ":"); used = q[n] + 0
        ok = (state ~ /^(idle|mixed)/)
        printf "%-12s %-16s model=%-17s gpus idle=%d/%d  cpus idle=%-4s  ram free=%dG%s\n",
            node, state, model, ok ? total - used : 0, total, c[2], (mem - alloc) / 1024,
            ok ? "" : "  (not schedulable)"
    }'

# Pending normal/debug GPU jobs, by model and class.
echo
echo "== 2. Pending normal/debug GPU jobs that could claim a model (and preempt bulk there) =="
squeue -h -t PD -p normal,debug -o "%i|%P|%q|%u|%b|%k|%r" \
| awk -F'|' "$model_for_vram"'
    gpus_of($5) == 0 { next }
    {
        r = $7
        cls = (r ~ /Dependency/) ? "dependency" \
            : (r ~ /^(QOSMax|QOSGrp|AssocMax|AssocGrp|MaxGRES|MaxCpu|MaxMem|MaxJob)/) ? "capped" \
            : "ready"
        printf "%-10s %-8s %-12s %-18s gpus=%-2d %-11s %s\n", $1, $2, $4, model_of($5, $6), gpus_of($5), cls, r
    }' | sort -k4,4 -k6,6

# Per user: GPUs held on non-bulk QoS vs. that QoS GPU limit.
echo
echo "== 3. Users on normal/debug: GPUs running vs. per-user QoS limit =="
limits="$(sacctmgr -n -P show qos format=Name,MaxTRESPU 2>/dev/null)"
{ echo "$limits" | sed 's/^/L|/'; squeue -h -t R -p normal,debug -o "R|%q|%u|%b"; squeue -h -t PD -p normal,debug -o "P|%q|%u|%b|%r"; } \
| awk -F'|' "$model_for_vram"'
    $1 == "L" { if (match($3, /gres\/gpu=[0-9]+/)) lim[$2] = substr($3, RSTART + 9, RLENGTH - 9) + 0; next }
    $1 == "R" { k = $3 "|" $2; run[k] += gpus_of($4); seen[k] = 1; next }
    $1 == "P" { k = $3 "|" $2; seen[k] = 1; if (gpus_of($4) > 0) { pend[k]++; if ($5 !~ /^(QOSMax|AssocMax|QOSGrp|AssocGrp)/) free_pend[k]++ } }
    END {
        for (k in seen) {
            split(k, a, "|"); l = (a[2] in lim) ? lim[a[2]] : -1
            status = (l < 0) ? "no limit" : (run[k] >= l ? "MAXED" : "headroom " l - run[k])
            printf "%-12s qos=%-16s running gpus=%d limit=%s  pending gpu jobs=%d (not capped: %d)  %s\n",
                a[1], a[2], run[k], l < 0 ? "-" : l, pend[k], free_pend[k], status
        }
    }' | sort

# Summary per model.
echo
echo "== 4. Summary per GPU model =="
{
    sinfo -N -p bulk -h -O "StateLong:20,Gres:50,GresUsed:60" | awk '{print "N|" $0}'
    squeue -h -t PD -p normal,debug -o "P|%b|%k|%r"
    squeue -h -t R -p bulk -o "B|%u|%b|%k"
} | awk -F'|' -v me="$me" "$model_for_vram"'
    $1 == "N" {
        split($2, f, " +"); state = f[1]
        g = f[2]; sub(/\(.*/, "", g); n = split(g, p, ":"); m = p[2]
        u = f[3]; sub(/\(.*/, "", u); k = split(u, q, ":")
        models[m] = 1; total[m] += p[n]
        if (state ~ /^(idle|mixed)/) { idle[m] += p[n] - q[k]; if (p[n] - q[k] > best[m]) best[m] = p[n] - q[k] }
        next
    }
    $1 == "P" {
        if (gpus_of($2) == 0) next
        m = model_of($2, $3)
        if ($4 ~ /Dependency/) dep[m] += gpus_of($2)
        else if ($4 ~ /^(QOSMax|QOSGrp|AssocMax|AssocGrp)/) cap[m] += gpus_of($2)
        else ready[m] += gpus_of($2)
        next
    }
    $1 == "B" { m = model_of($3, $4); bulkrun[m] += gpus_of($3); if ($2 == me) mine[m] += gpus_of($3) }
    END {
        for (m in models)
            printf "%-17s idle=%d/%d (max on one node: %d)  normal/debug pending gpus: ready=%d dependency=%d capped=%d  bulk running gpus=%d (mine %d)\n",
                m, idle[m], total[m], best[m], ready[m], dep[m], cap[m], bulkrun[m], mine[m]
    }' | sort

echo
echo "Confirm a candidate with: sbatch --test-only -p bulk --gres=gpu:<model>:<N> --comment=vram=<size> --mem=<mem> --cpus-per-gpu=<c> --wrap=true"
echo "(--test-only submits nothing; a start time within a minute of now means the job would start immediately.)"
