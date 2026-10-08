#!/bin/bash
# Self test, run inside the container as the test user.  Checks that the image
# behaves like Hummel for the rules humsub depends on.
fail=0
ok()  { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; fail=1; }
check() { local name=$1; shift; if "$@" >/tmp/st.out 2>&1; then ok "$name"; else bad "$name"; sed 's/^/       /' /tmp/st.out; fi; }
rejects() { local name=$1 pat=$2; shift 2; if "$@" >/tmp/st.out 2>&1; then bad "$name (accepted)"; elif grep -q "$pat" /tmp/st.out; then ok "$name"; else bad "$name (wrong message)"; sed 's/^/       /' /tmp/st.out; fi; }

. /sw/batch/init.sh
set -u
cd "$BEEGFS" || exit 1

echo "== environment"
check "version is 24.11" bash -c 'sbatch --version | grep -q "slurm 24.11"'
check "storage variables" bash -c '[ -n "$USW" ] && [ -n "$SSD" ] && [ -n "$BEEGFS" ] && env | grep -q "^BEEGFS_TESTGRP="'
check "partitions" bash -c 'test "$(sinfo -h -o %R | sort | tr "\n" " ")" = "big gpu gputest std "'

run_job() { # args... -> prints job id after completion, state in $STATE
    local id; id=$(sbatch --parsable "$@") || return 1
    for _ in $(seq 1 60); do
        STATE=$(squeue -h -j "$id" -o %T 2>/dev/null)
        [ -z "$STATE" ] && break
        sleep 1
    done
    echo "$id"
}

echo "== submit rules"
rejects "--mem rejected"          "no --mem/memory parameter allowed" sbatch --test-only --mem=1G --output=$BEEGFS/x.log --wrap=true
rejects "--mem-per-cpu rejected"  "no --mem/memory parameter allowed" sbatch --test-only --mem-per-cpu=1G --output=$BEEGFS/x.log --wrap=true
rejects "multi-node needs --exclusive" "must be --exclusive" sbatch --test-only -N2 --output=$BEEGFS/x.log --wrap=true
check   "multi-node --exclusive ok" sbatch --test-only -N2 --exclusive --output=$BEEGFS/x.log --wrap=true
rejects "log in \$HOME rejected"  "logfile is not writable" bash -c 'cd $HOME && sbatch --test-only --wrap=true'
check   "log on beegfs ok"        sbatch --test-only --output=$BEEGFS/x.log --wrap=true
rejects "unknown partition"       "invalid partition" sbatch --test-only -p nonsense --output=$BEEGFS/x.log --wrap=true
rejects "unknown account"         "" sbatch --test-only -A nonsense --output=$BEEGFS/x.log --wrap=true

echo "== running jobs"
cat > job.sh <<'JOB'
#!/bin/bash
source /sw/batch/init.sh
echo "job=$SLURM_JOB_ID user=$(id -un) scratch=$RRZ_GLOBAL_TMPDIR tmp=$TMPDIR"
test -d "$RRZ_GLOBAL_TMPDIR" || { echo "no global scratch"; exit 3; }
test -z "${HOME_FROM_SUBMIT:-}" || { echo "environment leaked"; exit 4; }
JOB
export HOME_FROM_SUBMIT=1
id=$(run_job --export=NONE -A testgrp_std -p std -t 5 --output=$BEEGFS/job_%j.log job.sh)
check "job ran to completion"   bash -c "sacct -n -X -j $id -o State | grep -q COMPLETED || (sleep 3; sacct -n -X -j $id -o State | grep -q COMPLETED)"
check "export=NONE honoured"    grep -q "scratch=/beegfs/scratch/testuser.$id" $BEEGFS/job_$id.log
check "scratch removed by epilog" bash -c "sleep 2; test ! -e /beegfs/scratch/testuser.$id"

id=$(run_job --export=NONE -A testgrp_gpu -p gpu --gpus=1 -t 5 --output=$BEEGFS/gpu_%j.log --wrap='echo gpus=$SLURM_GPUS_ON_NODE')
check "gpu job runs"            bash -c "sleep 3; sacct -n -X -j $id -o State | grep -q COMPLETED"

echo "== signal before timeout (humsub continuation)"
cat > sig.sh <<'JOB'
#!/bin/bash
trap 'echo got-USR1' USR1
for i in $(seq 1 100); do sleep 1 & wait $!; done
JOB
id=$(sbatch --parsable --export=NONE -A testgrp_std -p std -t 1 --signal=B:USR1@30 --output=$BEEGFS/sig_%j.log sig.sh)
for _ in $(seq 1 120); do [ -z "$(squeue -h -j $id)" ] && break; sleep 1; done
check "USR1 delivered before time limit" grep -q got-USR1 $BEEGFS/sig_$id.log
check "job ended by TIMEOUT"    bash -c "sleep 3; sacct -n -X -j $id -o State | grep -q TIMEOUT"

echo "== dependencies and cancel"
a=$(sbatch --parsable --export=NONE -A testgrp_std -p std -t 5 --output=$BEEGFS/a_%j.log --wrap='sleep 3')
b=$(sbatch --parsable --export=NONE -A testgrp_std -p std -t 5 --dependency=afterany:$a --output=$BEEGFS/b_%j.log --wrap='echo b')
check "dependent job pending"   bash -c "squeue -h -j $b -o %r | grep -q Dependency"
for _ in $(seq 1 60); do [ -z "$(squeue -h -j $b)" ] && break; sleep 1; done
check "dependent job ran after" test -s $BEEGFS/b_$b.log
c=$(sbatch --parsable --export=NONE -A testgrp_std -p std -t 5 --output=$BEEGFS/c_%j.log --wrap='sleep 60')
sleep 2; scancel $c; sleep 2
check "scancel works"           bash -c "sacct -n -X -j $c -o State | grep -q CANCELLED"

[ $fail -eq 0 ] && echo "ALL OK" || echo "SOME CHECKS FAILED"
exit $fail
