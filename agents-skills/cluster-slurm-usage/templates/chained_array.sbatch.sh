#!/bin/bash
# HINT for writing new job scripts, not a file to submit as-is. Copy it to
# <repo>/slurm/<name>.sbatch.sh, adapt it, and submit from the repository root:
#
#   sbatch slurm/<name>.sbatch.sh python train.py --resume latest ...
#
# The command to run is passed as arguments and executed as "$@".
#
# As written, this is a long run on `normal` without preemption: a job array
# whose tasks run one at a time (%1). Each task gets the partition's full
# 1-day limit and must resume from the checkpoint left by the previous task.
# 0-5%1 = up to 6 days. For a single job, drop --array and --open-mode and use
# %x-%j instead of %x-%A_%a in --output/--error.
#
# The program must:
#   - resume from its latest checkpoint when one exists;
#   - save checkpoints periodically and on SIGUSR1 (sent 10 min before the limit);
#   - when finished, create the file named by $DONE_FILE (if set), so that the
#     remaining array tasks exit at once. Pass it with
#     sbatch --export=ALL,DONE_FILE=runs/<name>/DONE ...
#
# No --time on purpose: the partition default, which equals its maximum, applies.
#
# GPU: --gres pins the model chosen for the job (here an RTX PRO 6000), and
# --comment=vram is at least the lower bound of that model's VRAM range, in
# whole G or M, so no smaller model can match. Keep #SBATCH lines free of
# trailing comments.

#SBATCH --job-name=gpu_job
#SBATCH --partition=normal
#SBATCH --array=0-5%1
#SBATCH --mem=32G
#SBATCH --output=./logs/slurm/%x-%A_%a.out
#SBATCH --error=./logs/slurm/%x-%A_%a.err
#SBATCH --open-mode=append
#SBATCH --gres=gpu:rtx_pro_6000:1
#SBATCH --comment=vram=80G
#SBATCH --cpus-per-gpu=16
#SBATCH --requeue
#SBATCH --signal=B:USR1@600
#SBATCH --mail-user=discord
#SBATCH --mail-type=BEGIN,END,FAIL,REQUEUE,TIME_LIMIT,TIME_LIMIT_50,TIME_LIMIT_80,TIME_LIMIT_90

set -euo pipefail

# Setup shared by several jobs lives in sourced helpers under slurm/.
# Ensure system libraries are available
source slurm/libraries_setup.sh

# Create the mappings for the datasets
source slurm/datasets_links.sh

echo "[${SLURM_CLUSTER_NAME}] ${SLURM_JOB_NAME} (${SLURM_JOB_ID}) task ${SLURM_ARRAY_TASK_ID:-none} on ${SLURMD_NODENAME} at $(date -Is)"

if [[ -n "${DONE_FILE:-}" && -f "$DONE_FILE" ]]; then
    echo "run already complete (${DONE_FILE} exists); exiting"
    exit 0
fi

"$@" &
child=$!

# Forward the pre-time-limit warning to the program so it can checkpoint,
# and stop it cleanly if the job is cancelled or preempted.
trap 'kill -USR1 "$child" 2>/dev/null || true' USR1
trap 'kill -TERM "$child" 2>/dev/null || true; exit 143' TERM

# A trapped signal interrupts `wait`; keep waiting until the program really exits.
status=0
while true; do
    wait "$child" && status=0 || status=$?
    kill -0 "$child" 2>/dev/null || break
done
exit "$status"
