# hummel-slurm-ci

A real Slurm, configured like the **Hummel-2** cluster (Universität Hamburg), as
a Docker image for the CI of batch-submission tools.  It layers a small Hummel
configuration on top of [giovtorres/slurm-docker](https://github.com/giovtorres/slurm-docker)
(included unmodified as a git submodule, pinned to a commit).

```
make          # build the upstream image from the submodule, then the Hummel layer
make test     # start the cluster, run tests/selftest.sh as the test user, stop it
make up       # start (privileged container "hummel-slurm"), wait until ready
make shell    # shell as the test user;  make down  to stop
```

`make` needs Docker and takes a while on the first run (Slurm is compiled from
source in the upstream Dockerfile).

## Using the image in another repository's CI

The CI of this repository pushes `ghcr.io/uhh-pd-ml/hummel-slurm-ci:<slurm-version>`
and `:latest`.  Start it as a service, wait for readiness, then run your tests in it:

```yaml
jobs:
  e2e:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Start Hummel Slurm
        run: |
          docker run -d --privileged --init --name hummel -h slurmctl \
            -v "$PWD:/src:ro" ghcr.io/uhh-pd-ml/hummel-slurm-ci:latest
          for i in $(seq 1 180); do docker exec hummel test -e /run/hummel-ready && break; sleep 1; done
      - name: Test
        run: docker exec -u testuser -w /beegfs/uu/testuser/testuser hummel bash -lc \
               'python3.12 -m venv v && v/bin/pip install /src && /src/tests/e2e.sh'
```

Notes: the container must run `--privileged` (slurm-docker requirement); free
GitHub-hosted runners allow this.  The first start takes ~20-40 s.  Jobs are
submitted as `testuser` (account `testgrp_std|_big|_gpu`, home
`/home/uu/testuser/testuser`); run the build with `HUMMEL_GROUP`/`HUMMEL_USER`
build args if you need other names (the default accounts of your tool, e.g.
`kasieczka_gpu`, are then `<group>_gpu`).

## What is emulated (observed on the real login nodes, 2026-10)

| Aspect | Hummel-2 | here |
|---|---|---|
| Slurm | 24.11.4 | 24.11.7 (closest upstream release) |
| Partitions | `std`, `big`, `gpu`, `gputest` | same names, `DefaultTime`, `DefMemPerCPU`/`MaxMemPerCPU`, `OverSubscribe=EXCLUSIVE` on `big`, `MaxCPUsPerNode` on `gputest` |
| Accounting | slurmdbd, `AccountingStorageEnforce=associations,limits`, accounts `<group>_std/_big/_gpu` (gpu account also on `gputest`) | same, created at start by `hummel-init` |
| Submit filter (`rrz5`) | rejects `--mem`/`--mem-per-cpu`; multi-node jobs must be `--exclusive`; log dir must be writable | re-implemented in `config/job_submit.lua` with the same messages |
| Batch init | `source /sw/batch/init.sh` (provides profile, unsets `SLURM_EXPORT_ENV`) | stub in `sw/batch/init.sh` + `sw/profile/init.sh` |
| Storage variables | `$USW`, `$SSD`, `$BEEGFS`, `$<FS>_<GROUP>` | same names and path layout (`/usw/uu/u/u`, `/nfs/ssd2.0/...`, `/beegfs/...`) |
| Temp dirs | batch: `RRZ_GLOBAL_TMPDIR=/beegfs/scratch/<user>.<job>`, local `/tmp` | same; created by prolog, removed by epilog |
| GPUs | 8x H100 per node | `Gres=gpu:h100:2` on one node, backed by `/dev/null` and `/dev/zero` |
| apptainer | `/sw/env/system-gcc/apptainer/1.4.5/bin/apptainer` | stub that runs the command directly (no isolation) |
| Signals/time | `--time`, `--signal=B:USR1@N` | real Slurm behaviour; time limits have 1-minute granularity, so a timeout test takes 1-2 minutes |

## Known differences (do not rely on these)

* **Hardware**: three 8-CPU "nodes" (`node1..3`) in one container.  Partitions
  share them (`std`=node1-2, `big`=node2, `gpu`=node3, `gputest`=node1), because
  slurm-docker starts exactly `node1..node3`.  No cgroup constraints
  (`ProctrackType=linuxproc`), so CPU/memory/GPU limits are not enforced.
* **Read-only `/home` and `/usw` on compute nodes** is only checked at submit
  time (log directory), not enforced at run time.
* **Submit filter**: only rules observed with `sbatch --test-only` are
  reproduced; Hummel's `rrz5` plugin may do more (e.g. virtual-node rounding of
  `--ntasks`).  `TMPDIR` inside batch jobs is an assumption (`/tmp`).
* **OS**: Rocky 9 here, Debian 13 on Hummel.
* **Site specifics** such as the real queue state, fair share and node names
  are not modelled.

Keep a smoke test against the real cluster for releases; this image catches
logic errors, not site surprises.

## License

Restricted: use is limited to members of or persons affiliated with Universitaet
Hamburg, for developing software that facilitates the operation of the Hummel-2
cluster.  Verbatim copies may be used; **modification and relicensing are not
permitted**.  See [LICENSE](LICENSE).  Third-party components (the
`slurm-docker` submodule, Slurm, OS packages) keep their own licenses.

## Updating

* Slurm version: `make SLURM_VERSION=25.05.7` (must be a version the submodule
  supports) and the `SLURM_VERSION` in `.github/workflows/image.yml`.
* Upstream: `git -C slurm-docker fetch && git -C slurm-docker checkout <tag>`,
  commit the new submodule pointer, run `make test`.  The overlay depends on
  upstream's entrypoint starting `node1..node3` and calling the command it is
  given.
* Hummel changes: re-run `scontrol show config`, `scontrol show partition` and
  `sbatch --test-only` probes on a login node and adjust `config/`.
