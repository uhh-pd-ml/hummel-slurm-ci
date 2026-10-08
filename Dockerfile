# Hummel-2 flavoured Slurm test cluster, layered on the unmodified slurm-docker
# image (git submodule).  Build through `make`, which builds the base first.
ARG BASE_IMAGE=slurm-docker-base:24.11.7-rl9
FROM ${BASE_IMAGE}

ARG SLURM_VERSION
ARG HUMMEL_USER=testuser
ARG HUMMEL_GROUP=testgrp
ARG HUMMEL_UID=1000

LABEL org.opencontainers.image.title="hummel-slurm-ci" \
      org.opencontainers.image.description="Slurm ${SLURM_VERSION} configured like the Hummel-2 cluster, for CI of batch submission tools" \
      org.opencontainers.image.source="https://github.com/uhh-pd-ml/hummel-slurm-ci"

# Python >= 3.11 for humsub; `python3` itself stays the system one (dnf needs it).
RUN dnf -y install python3.12 python3.12-pip rsync sudo \
    && dnf clean all && rm -rf /var/cache/dnf \
    && ln -s /usr/bin/python3.12 /usr/local/bin/python3

# Scheduler configuration (replaces slurm-docker's generic one)
COPY config/slurm.conf config/gres.conf config/job_submit.lua config/prolog.sh config/epilog.sh /etc/slurm/
RUN chown slurm:slurm /etc/slurm/slurm.conf /etc/slurm/gres.conf /etc/slurm/job_submit.lua \
    && chmod 644 /etc/slurm/slurm.conf /etc/slurm/gres.conf /etc/slurm/job_submit.lua \
    && chmod 755 /etc/slurm/prolog.sh /etc/slurm/epilog.sh \
    && test -e "$(rpm -ql slurm | grep -m1 'job_submit_lua.so')"

# Site software tree (/sw/...) as humsub's worker expects it
COPY sw/ /sw/

# Test user with Hummel's directory layout
RUN groupadd --gid 2000 ${HUMMEL_GROUP} \
    && useradd --uid ${HUMMEL_UID} --gid ${HUMMEL_GROUP} --create-home \
         --home-dir /home/uu/${HUMMEL_USER}/${HUMMEL_USER} ${HUMMEL_USER} \
    && for d in /usw/uu/${HUMMEL_USER}/${HUMMEL_USER} \
                /nfs/ssd2.0/uu/${HUMMEL_USER}/${HUMMEL_USER} \
                /beegfs/uu/${HUMMEL_USER}/${HUMMEL_USER} \
                /usw/g/${HUMMEL_GROUP}/${HUMMEL_USER} \
                /nfs/ssd2.0/g/${HUMMEL_GROUP}/${HUMMEL_USER} \
                /beegfs/g/${HUMMEL_GROUP}/${HUMMEL_USER}; do \
         mkdir -p "$d" && chown -R ${HUMMEL_USER}:${HUMMEL_GROUP} "$d"; \
       done \
    && mkdir -p /beegfs/scratch /beegfs/tmp && chmod 1777 /beegfs/scratch /beegfs/tmp \
    && printf '. /sw/profile/init.sh\n' > /etc/profile.d/hummel.sh \
    && printf 'HUMMEL_USER=%s\nHUMMEL_GROUP=%s\n' ${HUMMEL_USER} ${HUMMEL_GROUP} > /etc/hummel-ci.env

COPY bin/hummel-init /usr/local/bin/hummel-init
RUN chmod +x /usr/local/bin/hummel-init

# slurm-docker's entrypoint starts the daemons and then execs this command.
CMD ["/usr/local/bin/hummel-init"]
