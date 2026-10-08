# Needed initialization for batch jobs that have all variables
# from profile, but not the module function due to separate shell
# instance, plus setting of correct TMPDIR paths since the profile
# cannot set them for batch jobs (no access to SLURM_JOBID).
. /sw/profile/init.sh
# Also, prevent the vicious setting of SLURM_EXPORT_ENV.
unset SLURM_EXPORT_ENV
