# Emulation of Hummel-2's /sw/profile/init.sh: storage variables and the
# batch/interactive temp-dir convention (rrz-global-tmpdir / rrz-local-tmpdir:
# global = /beegfs/scratch/<user>.<jobid>, local = /tmp).
_u=$(id -un)
_g=${HUMMEL_GROUP:-testgrp}
_G=$(printf '%s' "$_g" | tr '[:lower:]' '[:upper:]')
export USW="/usw/uu/$_u/$_u"
export SSD="/nfs/ssd2.0/uu/$_u/$_u"
export BEEGFS="/beegfs/uu/$_u/$_u"
export "USW_$_G=/usw/g/$_g/$_u"
export "SSD_$_G=/nfs/ssd2.0/g/$_g/$_u"
export "BEEGFS_$_G=/beegfs/g/$_g/$_u"
export RRZ_SW_PREFIX=/sw RRZ_SW_BINPREFIX=/sw RRZ_SW_INIT=1
if [ -n "${SLURM_JOB_ID:-}" ]; then
    export RRZ_GLOBAL_TMPDIR="/beegfs/scratch/$_u.$SLURM_JOB_ID"
    export RRZ_LOCAL_TMPDIR=/tmp
    export TMPDIR=/tmp
else
    export RRZ_GLOBAL_TMPDIR="/beegfs/tmp/$(hostname -s)/$_u/$$"
    export RRZ_LOCAL_TMPDIR="$RRZ_GLOBAL_TMPDIR"
    export TMPDIR="$RRZ_GLOBAL_TMPDIR"
    mkdir -p "$TMPDIR" 2>/dev/null || true
fi
unset _u _g _G
