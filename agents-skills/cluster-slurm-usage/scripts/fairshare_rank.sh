#!/usr/bin/env bash
# Rank the current user's fair share against the other users on the cluster.
#
#   comparison users = users with more RawUsage than me
#                      + users with jobs running right now (excluding me)
#   good       my FairShare beats all, or more than 70%, of the comparison
#              users: my jobs are likely to start, including on bulk;
#   very good  my FairShare beats more than 50% of all users on the cluster.
#
# FairShare already accounts for RawShares, which differ by role (e.g. PhD
# students), so only FairShare values are compared, never raw usage alone.
#
# Usage: fairshare_rank.sh [sshare-output-file [running-users-file]]
#   Without arguments it runs `sshare -a` and `squeue -t R` itself; the files
#   are for testing (sshare -a -n -P -o Account,User,RawShares,RawUsage,FairShare
#   output, and one user name per line).
set -euo pipefail

me="$(id -un)"

if [[ $# -ge 1 ]]; then
    shares="$(cat "$1")"
else
    shares="$(sshare -a -n -P -o Account,User,RawShares,RawUsage,FairShare)"
fi

if [[ $# -ge 2 ]]; then
    running="$(sort -u "$2")"
else
    running="$(squeue -h -t R -o '%u' | sort -u)"
fi

# Running users go first (lines without '|'), then the sshare rows.
{ echo "$running"; echo "$shares"; } | awk -F'|' -v me="$me" '
    NF == 1 { if ($1 != "") is_running[$1] = 1; next }
    $2 == "" { next }                               # account rows, not users
    {
        u = $2
        usage[u] += $4 + 0
        fs = $5 + 0
        if (!(u in share) || fs > share[u]) share[u] = fs
        rawshares[u] = $3
    }
    END {
        if (!(me in share)) {
            print "user " me " not found in sshare output"
            exit 1
        }
        myfs = share[me]; myuse = usage[me]
        total = 0; beaten_all = 0
        cmp = 0; beaten_cmp = 0; heavier = 0; running_n = 0
        for (u in share) {
            if (u == me) continue
            total++
            if (myfs > share[u]) beaten_all++
            h = (usage[u] > myuse); r = (u in is_running)
            heavier += h; running_n += r
            if (h || r) {
                cmp++
                if (myfs > share[u]) beaten_cmp++
            }
        }
        for (u in is_running)
            if (u != me && !(u in share))
                print "note: running user " u " has no sshare row; ignored"

        printf "me: %s  RawShares=%s  RawUsage=%d  FairShare=%.6f\n", me, rawshares[me], myuse, myfs
        printf "comparison users: %d (%d with more RawUsage than me, %d running now; overlaps counted once)\n", cmp, heavier, running_n
        printf "my FairShare beats %d of %d comparison users (%.0f%%)\n", beaten_cmp, cmp, cmp ? 100 * beaten_cmp / cmp : 100
        printf "my FairShare beats %d of %d other users on the cluster (%.0f%%)\n", beaten_all, total, total ? 100 * beaten_all / total : 0

        good = (beaten_cmp == cmp || beaten_cmp > 0.7 * cmp)
        very_good = (total > 0 && beaten_all > total / 2)
        printf "good (beats all or >70%% of comparison users): %s\n", good ? "yes" : "no"
        printf "very good (beats >50%% of all users): %s\n", very_good ? "yes" : "no"
        print "verdict: " (very_good ? "VERY GOOD" : (good ? "GOOD" : "NEITHER"))
    }'
