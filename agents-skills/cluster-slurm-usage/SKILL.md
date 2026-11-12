---
name: cluster-slurm-usage
description: Operate the user's university HPC cluster through SLURM - inspect the queue and partitions, choose a partition, write and submit sbatch jobs, monitor them and cancel the user's own jobs. Use whenever the user mentions the cluster, HPC, SLURM, sbatch, srun, squeue, scancel, GPUs on the cluster, job arrays, partitions (cpu, debug, normal, bulk), idle GPUs, fair share or preemption, or asks to run, schedule, check or stop a job there.
---

# Cluster SLURM Usage

Act as the user's operator on a SLURM cluster. Run SLURM commands, decide on
partitions and resources, and keep the user's jobs healthy, while never
touching anyone else's jobs.

Commands run on a cluster login node. If you are not already on one, run them
over SSH (`ssh <host> '<command>'`). Find the host in this order:

1. the `AGENTS.md` of the repository you are working in, which should name
   the cluster host;
2. otherwise `hpc`, the name the user usually keeps in the computer's hosts
   file or SSH config (`ssh hpc '<command>'`);
3. if that does not resolve or connect, ask the user.

Never run heavy computation on the login node itself: anything beyond
inspecting files or compiling small things goes through `sbatch` or `srun`.

## How to take instructions

The user can drive you in three ways. Support all of them.

1. **Explicit commands** ("run squeue", "cancel 48213", "submit slurm/train.sbatch.sh"):
   execute them as given, subject only to the safety rules below.
2. **Goals** ("train this model for ~3 days on 2 GPUs"): pick the partition,
   resources and job structure yourself using the decision policy below, then
   state the choice in one or two sentences with the reason and submit.
3. **Questions** ("is the cluster busy?", "where is my job?"): answer from live
   command output, never from memory or from this file alone.

Ask a short question instead of guessing only when a missing fact would change
what you submit: the number of GPUs, the expected run time, the command to run,
or whether the program can resume from a checkpoint (required for chained
arrays and for `bulk`).

## Safety rules (non-negotiable)

Let `me` be the output of `id -un`.

1. **Only ever cancel, hold, release, requeue, signal or update jobs owned by
   `me`.** Before any `scancel`, `scontrol hold|release|requeue|update` or
   `scancel --signal`, verify ownership with
   `squeue -h -j <jobid> -o '%u' | sort -u` and proceed only if the sole value
   is `me`. Regular users usually cannot cancel other users' jobs anyway, but
   the user may hold coordinator or admin rights, so the check is mandatory.
2. **Every `scancel` call carries `--user="$(id -un)"`** in addition to the
   explicit job IDs, so SLURM itself filters out anything that is not the
   user's. Prefer the bundled helper, which does both checks:
   `bash scripts/scancel_mine.sh <jobid> [<jobid> ...]`
   (accepts `123` and `123_4`; refuses anything else). If the helper is not
   on the cluster, copy it there or reproduce its checks inline.
3. **Never use filter-only cancellation** (`scancel -p`, `--name`, `--state`,
   `-A`, `-w`, `--qos`) without explicit job IDs, and never `scancel` with no
   job ID. Cancelling all of the user's jobs (`scancel --user="$(id -un)"`)
   is allowed only when the user explicitly asks for exactly that.
4. Cancelling is irreversible. When the user named the job IDs, cancel them.
   When you decided on your own that a job should go (e.g. a broken run), list
   the job IDs, names and states and ask before cancelling.
5. Never use `sudo`, never edit SLURM configuration, and never change another
   user's files.

## Viewing jobs

- All jobs in partitions the user can see: `squeue`
- All jobs, including hidden partitions and partitions the user cannot use:
  `squeue -a`
- A readable format for either:
  `squeue -a -o "%.12i %.9P %.24j %.10u %.2t %.11M %.11l %.4D %.14b %R"`
  (`%b` shows requested GPUs, `%R` the reason a job is pending).
- Only the user's jobs: `squeue --me` (older SLURM: `squeue -u "$(id -un)"`)
- Expected start times of pending jobs: `squeue --me --start`
- Finished or failed jobs:
  `sacct -u "$(id -un)" -S now-2days -X -o JobID,JobName%24,Partition,State,ExitCode,Elapsed,Timelimit,AllocTRES%40`
- Details of one job: `scontrol show job <jobid>`

Viewing other users' jobs is fine and is how you judge cluster load; only
acting on them is forbidden.

## Partitions

| Partition | GPUs per job | Default = maximum time | Preemptible |
| --- | --- | --- | --- |
| `cpu` | none (CPU only) | 5 days | no |
| `debug` | at most 1 | 2 hours | no |
| `normal` | at most 3 | 1 day | no |
| `bulk` | any number | 5 days | **yes**, by `normal` and `debug` jobs |

**Time limits: never pass `--time` / `-t`.** Each partition's default time is
already its maximum, so omitting it gives the job the full allowance. If
`sinfo -o "%P %l %L"` shows a default (`%L`) shorter than the maximum (`%l`),
tell the user rather than silently adding `--time`.

Treat this table as the expected configuration and confirm it against
`sinfo` / `scontrol show partition <name>` on first use in a session. If the
live values differ, follow the live values and tell the user.

Request GPUs as described in "Choosing the GPU" and "Cluster details".

## Decision policy

Apply the first rule that fits.

1. **CPU-only work** → `cpu`.
2. **Quick tests, debugging, interactive checks** (1 GPU, under 2 hours) →
   `debug`. For an interactive shell:
   `srun -p debug --gres=gpu:l4:1 --comment=vram=16G --mem=16G --cpus-per-gpu=4 --pty bash`
   (adapt the model and sizes as in "Choosing the GPU").
3. **Every other GPU job: first check whether `bulk` can start it right
   now.** If it can, **always prefer `bulk`** over rules 4–5. See "Starting
   on bulk right away" below. Runs up to 5 days are a single job. Longer runs
   are a chained array on `bulk` (`%1`, N = ceil(days / 5) + 1), whose later
   tasks may have to wait for idle GPUs.
4. **Bulk cannot start now, GPU runs up to 1 day with 1–3 GPUs** → `normal`,
   a single job.
5. **Bulk cannot start now, GPU runs longer than 1 day with 1–3 GPUs** → a
   **chained job array on `normal`**: `--array=0-<N-1>%1`, where
   N = ceil(expected days) + 1 for margin. The `%1` throttle lets only one
   task run at a time, so the tasks execute one after another, each with the
   full 1-day limit, and the run can go on for 5 days or longer without ever
   being preempted. This needs a program that saves checkpoints and resumes
   from the latest one; verify it in the code or ask. See "Job scripts"
   below for how to write it.
6. **More than 3 GPUs in one job** → only `bulk` allows it. If it cannot
   start now, it queues there behind the other `bulk` jobs, ranked by fair
   share. Say so explicitly, warn about preemption and make sure the program
   checkpoints. All GPUs of a job sit on one node, so the chosen model caps
   the count (see "Cluster details").

Jobs on `bulk` can be preempted at any time. Always submit them with
`--requeue` and `--open-mode=append`, check the preemption mode with
`scontrol show partition bulk | grep -i preempt` (`REQUEUE` restarts the
job; `CANCEL` kills it, in which case also use a chained array), and make
sure the program resumes from its last checkpoint.

### Starting on bulk right away

`bulk` jobs never preempt `normal` or `debug` jobs: they start only on GPUs
that are idle at that moment, and `normal` and `debug` jobs preempt them
later. (The one exception among `bulk` jobs is described in "Scheduling and
preemption".) A `bulk` job
that starts immediately is still the better deal: it runs now, costs less fair
share per GPU-hour, may run for 5 days, and leaves the user's 3-GPU `normal`
allowance free. Its only drawback is the chance of being preempted, and that
chance is low when the users who could preempt it are already capped.

1. **Snapshot.** Run `bash scripts/bulk_availability.sh` (it is also part of
   `scripts/cluster_status.sh`). It is self-contained, so from a machine
   other than the cluster it can run as
   `ssh <host> 'bash -s' < scripts/bulk_availability.sh`. It prints:
   - idle GPUs, idle CPUs and free RAM per node of `bulk`;
   - pending `normal`/`debug` GPU jobs per model, classed as `ready`
     (waiting only for priority or resources, so it can preempt soon),
     `dependency` (it becomes ready once its dependency is met) or `capped`
     (blocked by a per-user limit such as `QOSMaxGRESPerUser`);
   - every user active on `normal`/`debug`, with their running GPUs against
     their QoS limit: `MAXED` users cannot start another `normal` job until
     one of theirs ends;
   - a summary per GPU model.
2. **Candidates.** A model is a candidate if a single node has at least N
   idle GPUs, its VRAM range covers the estimated peak (see "Choosing the
   GPU"), and that node has enough idle CPUs and free RAM for the request.
   If the user already holds 3 GPUs on `normal`, any new `normal` job would
   be capped, which makes `bulk` all the more attractive.
3. **Preemption risk per candidate.** A `normal`/`debug` job only runs on
   the smallest model that matches its VRAM declaration (or on the model
   pinned in its `--gres`), so only demand for the same model can preempt
   the `bulk` job.
   - **Low:** no `ready` or `dependency` GPUs pending for that model, and
     every other user active on `normal` is `MAXED` (or nobody is active).
   - **Medium:** no `ready` or `dependency` demand for that model, but some
     users still have headroom and could submit new `normal` jobs at any
     time.
   - **High:** `ready` or `dependency` GPUs are pending for that model.
     When those jobs become startable they claim GPUs on that model, and
     with no free GPUs left they preempt `bulk` jobs.

   `capped` jobs are no immediate threat. When one of that user's jobs ends,
   the capped job usually takes over the GPUs it freed.
4. **Pick.** Prefer the candidate with the lowest risk, and among equal
   risks the cheapest model (see the cost column in "Cluster details"). Pin
   it with `--gres=gpu:<model>:N` and set `vram` to at least that model's
   lower bound (see "Choosing the GPU").
5. **Confirm** with a dry run, which submits nothing but passes the
   submission checks:
   `sbatch --test-only -p bulk --gres=gpu:<model>:N --comment=vram=<size> --mem=<mem> --cpus-per-gpu=<c> --wrap=true`.
   It prints `Job … to start at <time> … on nodes <node>`. If the time is
   within a minute or so of now, the job starts immediately. If it is later,
   `bulk` cannot start now: go back to rules 4–6.
6. **Exception.** If the program cannot resume from checkpoints, a
   preemption restarts it from scratch. Use `bulk` for such a program only
   when the risk is low or the run takes at most a few hours; otherwise use
   `normal` and say why.

The snapshot is only valid for a short time. Submit right after confirming
the start, and check that the job is `R` with `squeue --me`.

## Judging fair share

Many accounts on the cluster belong to people who never use it or used it
once or twice. They keep a high `FairShare` without competing for anything,
so an absolute threshold is meaningless. RawShares also differ by role and
the user is a PhD student, so compare `FairShare` values (which already
account for shares), never raw usage alone. Run
`bash scripts/fairshare_rank.sh`, which reads `sshare -a` and applies the
rules below. On this cluster `sshare -a` shows the fair share of every user
and every role (account), so the comparison is always possible.

- **Comparison users:** the users whose `RawUsage` is greater than the
  user's, plus the users with jobs running right now (`squeue -t R`),
  each counted once. These are the people the user actually competes with
  at this moment.
- **Good:** the user's `FairShare` is higher than that of all, or more than
  70%, of the comparison users. A good fair share means the user's jobs are
  likely to start soon, including on `bulk`. With no comparison users the
  cluster is idle and the verdict is good.
- **Very good:** the user's `FairShare` is higher than that of more than 50%
  of all users on the cluster.

The script prints both checks and a verdict: `VERY GOOD`, `GOOD` or
`NEITHER`. Run it before every submission, because the final report must
include it. It does not matter for a `bulk` job that starts right away on
idle GPUs. It does matter for jobs that wait in a queue, including `bulk`
jobs that cannot start now.

## Choosing the GPU

Decide the GPU model yourself for every GPU job, then pin it:

1. **Estimate the peak VRAM** per GPU. Use, in order of reliability: the
   peak from an earlier run of the same job (logs,
   `torch.cuda.max_memory_allocated()`, `nvidia-smi` output), a short `debug`
   run that measures it, or an estimate from model size, batch size and
   precision. Add a safety margin of about 10–15%.
2. **Pick the model** that suits the job best (models and ranges in
   "Cluster details"). Default to the smallest model whose range covers the
   peak: it costs the least fair share. Choose a larger one only with a
   reason you state to the user, such as markedly faster training on a long
   run, or the smaller model's queue being long. On `bulk`, the choice is
   limited to the models that have idle GPUs now and that carry the lowest
   preemption risk (see "Starting on bulk right away"). A larger idle model
   that lets the job start now beats waiting for the smallest one.
3. **Pin the hardware** with `--gres=gpu:<model>:N`, so the logs and
   `sacct` show exactly which hardware ran the job.
4. **Set `--comment=vram=<size>`** to the larger of the estimated peak and
   the lower bound of the chosen model's range, so no smaller model could
   ever match. It must stay within the chosen model's range. Example: a
   15G peak run on an RTX A6000 gets
   `--gres=gpu:nvidia_rtx_a6000:1 --comment=vram=25G`. On `bulk` this
   matters even more: with a declaration below the model's lower bound, the
   job only borrows that GPU, and a `bulk` job that really needs the model
   can preempt it (see "Scheduling and preemption").

## Job scripts

Every SLURM job script lives in a folder called `slurm/` at the root of the
repository it belongs to, and its name ends in `.sbatch.sh`
(e.g. `slurm/train_resnet.sbatch.sh`). Write them as files instead of long
`--wrap` strings, so they can be inspected and resubmitted.

- **Look first.** If the repository already has `slurm/*.sbatch.sh` files,
  reuse or adapt one and follow its conventions.
- **The template is a hint.** `templates/chained_array.sbatch.sh` shows how to
  write new scripts when none fits: it is the user's own job script plus the
  chained-array settings. Copy what applies; do not submit it as-is.
- **Generic scripts take the command as arguments.** The script runs `"$@"`,
  so one script serves many runs:
  `sbatch slurm/gpu_job.sbatch.sh python train.py --config cfg.yaml`.
- **Shared setup goes into sourced helpers.** Put anything several jobs need
  into `.sh` files under `slurm/` and `source` them from each job script.
  Prefer this to copying the same lines into many scripts. Typical helpers
  are `slurm/libraries_setup.sh`, which makes system libraries available,
  and `slurm/datasets_links.sh`, which creates symlinks in the repository's
  datasets folder pointing to where the data lives on the cluster. Because
  the paths are relative, submit from the repository root.
- **Keep the user's directives:**
  - `--output=./logs/slurm/%x-%j.out` and `--error=./logs/slurm/%x-%j.err`,
    or `%x-%A_%a` for arrays. Create `logs/slurm/` before submitting.
  - `--mem`, `--cpus-per-gpu`, and the GPU pair from "Choosing the GPU":
    `--gres=gpu:<model>:N` and `--comment=vram=<size>`.
  - `--requeue`.
  - `--mail-user=discord` with the `--mail-type` list from the template.
- Set `--job-name` and `--partition` for every job, and never `--time`.
- Size CPUs and memory to the job; if unsure, look at what a similar past
  job used: `seff <jobid>` or `sacct -j <jobid> -o MaxRSS,TotalCPU,Elapsed`.
- `--signal=B:USR1@600` together with the template's trap forwards SIGUSR1 to
  the program ten minutes before the time limit, so it can write a final
  checkpoint. Periodic checkpoints remain the primary safeguard.
- Submit with `sbatch --parsable slurm/<name>.sbatch.sh ...` and report the
  job ID back. For dependent stages use `--dependency=afterok:<jobid>`.

## Monitoring and troubleshooting

- Pending reason (`%R` in `squeue`): `Priority` and `Resources` mean waiting
  in line; `QOSMaxGRESPerUser`, `AssocGrpGRES` and similar mean the user hit
  a limit; `PartitionTimeLimit` means a `--time` was set too high (remove it).
- Priority breakdown of a pending job: `sprio -j <jobid>`.
- Follow logs with `tail -n 50 <logfile>`; do not leave `tail -f` running.
- In a chained array, if a task fails for a reason that will repeat (a crash,
  not a time-out), the next task will fail the same way. Report it and,
  following safety rule 4, offer to cancel the remaining tasks of that array.
- Show `sacct` state and exit code when a job ends unexpectedly. `TIMEOUT`
  is expected for every task of a chained array except the last one.

## Reporting

After each action, tell the user briefly what you ran, the job IDs involved
and the relevant outcome (state, pending reason, start estimate, errors).
Quote command output when it matters; do not paraphrase numbers.

Whenever you submitted jobs, your final message must also state:

- **Fair share:** the verdict you saw (`VERY GOOD`, `GOOD` or `NEITHER`)
  with the numbers behind it, e.g. "GOOD: beats 9 of 12 comparison users
  (75%), 18 of 40 users overall (45%)".
- **What you decided to run:** partition, single job or chained array (with
  the number of tasks), GPU model and count, `vram`, CPUs and memory, the
  job script used, the job IDs, and one sentence on why, linking the choice
  to the fair-share verdict and the cluster load.
- **Bulk check:** whether `bulk` could start the job now (idle GPUs on the
  chosen node, the `--test-only` start time) and, for a `bulk` job, the
  preemption risk (low, medium or high) with its reason, e.g. "low: no
  pending normal/debug demand for l4; 3 of the 4 users active on normal are
  MAXED".

## Cluster details

Facts about this cluster that the sections above do not cover. They exist to
make submissions pass the cluster's checks. Where they seem to touch a rule
above, the rule above decides how you behave.

### GPU models

| Model | `--gres` name | VRAM declaration range | Node | GPUs per job | Fair-share per GPU-hour (normal / debug, bulk) |
| --- | --- | --- | --- | --- | --- |
| NVIDIA L4 | `l4` | up to 22G | caladan | up to 8 | 25 / 20 |
| Quadro RTX 6000 | `quadro_rtx_6000` | 23G – 24G | magrathea | up to 8 | 25 / 20 |
| NVIDIA RTX A6000 | `nvidia_rtx_a6000` | 25G – 47G | akira | up to 6 | 35 / 28 |
| NVIDIA RTX PRO 6000 | `rtx_pro_6000` | 48G – 95G | arrakis | up to 6 | 60 / 48 |

For comparison, 16 CPUs cost about 5 per hour. Every role can use every model.

- The VRAM declaration is required on every GPU job and selects the model:
  `vram=48G` already needs an RTX PRO 6000, and `vram=96G` fits no GPU.
- The declaration is per GPU: with `--gres=gpu:2`, each GPU must offer it.
- It neither resizes nor reserves part of a GPU. VRAM and host RAM (`--mem`)
  are separate and both must be declared.
- Write whole numbers with `G` or `M`, where 1G = 1024M: `vram=1536M`, never
  `vram=1.5G`. Near a range boundary, write the value in `M`.
- The comment holds `vram=…` and nothing else.
- On `normal` a job runs only on the smallest model matching its VRAM
  declaration and waits while that model is busy, even if larger GPUs are
  free. A `bulk` job can borrow a larger free GPU, and loses it when a
  `normal` or `debug` job needs it.
- Never set `CUDA_VISIBLE_DEVICES`: Slurm already exposes only the job's
  GPUs. For multi-GPU jobs, check that the code uses all of them (e.g.
  `torch.cuda.device_count()`).

### Submission checks

Every submission is validated, and a request that breaks these rules is
rejected with an explanation.

| Allowed | Rejected |
| --- | --- |
| `--gres=gpu:N`, `--gres=gpu:MODEL:N`, `--gpus-per-node` | `--gpus`, `--gpus-per-task`, `--gpus-per-socket`, mixed GPU lists |
| `--comment=vram=…` on every GPU job, nothing else in the comment | GPU jobs without a VRAM declaration; decimal values such as `1.5G` |
| One node | Multi-node (`-N` > 1) and heterogeneous jobs, also for CPU-only work |
| `--ntasks` + `--cpus-per-task`, or `--cpus-per-gpu` | `--ntasks-per-socket`, `-per-core`, `-per-board`, `-per-gpu` layouts |
| Exactly one of `--mem`, `--mem-per-cpu` (at most 4000M), `--mem-per-gpu` | `--mem=0` on GPU jobs; several memory options together |
| A specific GPU model through `--gres` | `--constraint` on GPU jobs; `--prefer` |
| Up to 16 CPUs and 48G of RAM per GPU | More CPUs or RAM per GPU |
| Only the CPUs, RAM and GPUs needed | `--exclusive` (all variants), `--core-spec`, `--thread-spec` |

- Never set `--qos`: QoS is assigned automatically.
- `bulk` jobs are always requeueable; `--no-requeue` is rejected there.

### Scheduling and preemption

- When jobs wait for the same resources, the highest priority starts first.
  Queues are considered in the order `debug` ▸ `normal` ▸ `cpu` ▸ `bulk`.
  Within a queue, jobs are ranked by account type, fair share and waiting
  time.
- Usage is resources × time, weighted per queue and model as in the table
  above. Allocated CPUs and GPUs count even when idle, so do not request
  more than the job uses. Recorded usage halves every 7 days.
- A preempted `bulk` job is requeued and **restarts from the first line of
  the script**. Job scripts must therefore be safe to run again: resume from
  checkpoints, and avoid setup steps that fail when repeated.
- QoS limits (`sacctmgr show qos format=Name,MaxTRESPU,MaxJobsPU,Preempt`):
  `normal` allows 3 GPUs per user and `debug` 1 GPU and 1 job per user.
  Jobs over the limit stay pending as `QOSMaxGRESPerUser`. The `msc_*` and
  `external_*` QoS have their own limits. `bulk` has no per-user GPU limit.
- Who preempts whom: the `normal` and `debug` QoS (including `msc_*` and
  `external_*`) preempt every `bulk` QoS. A plain `bulk` job preempts
  nobody. The tiered `bulk_<size>` QoS (`bulk_24g`, `bulk_47g`,
  `bulk_95g`), which follow the VRAM declaration, preempt `bulk` jobs of
  lower tiers that are borrowing a larger GPU. A `bulk` job whose `vram`
  is at least its model's lower bound is therefore safe from other `bulk`
  jobs.
- `sbatch --test-only` runs the submission checks and reports the partition
  as `bulk_base`. That name is internal; still submit with `-p bulk`.

## When the cluster disagrees with this skill

Cluster rules change from time to time. If a command fails, a submission is
rejected, or the cluster otherwise behaves differently from what this skill
describes (partitions, limits, GPU models, accepted options, fair-share
visibility), report the difference to the user: quote what the skill says
and what the cluster actually did. Follow the cluster's actual behaviour for
the task at hand, and do not invent workarounds that break the rules above.
