#!/bin/bash
# Mirrors the per-job global scratch directory the Hummel prolog creates
# (rrz-global-tmpdir: /beegfs/scratch/<user>.<jobid>).
d="/beegfs/scratch/${SLURM_JOB_USER}.${SLURM_JOB_ID}"
mkdir -p "$d" && chown "${SLURM_JOB_USER}" "$d" && chmod 700 "$d"
exit 0
