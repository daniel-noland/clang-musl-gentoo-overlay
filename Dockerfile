# syntax=docker/dockerfile:1.4.1-labs
ARG upstream_snapshot="20220415"
ARG seed_image="gentoo/stage3:musl-${upstream_snapshot}"

FROM $seed_image as seed_0
ARG seed_image

FROM $seed_image as catalyst
ARG upstream_snapshot
ARG seed_image

SHELL [ \
  "/usr/bin/nice", \
  "--adjustment=15", \
  "/bin/bash", \
  "-euxETo", \
  "pipefail", \
  "-c" \
]

RUN \
--mount=type=tmpfs,target=/run \
emerge-webrsync --revert="${upstream_snapshot}"; \
:;

COPY ./_assets/000_catalyst/etc/portage/ /etc/portage/

RUN \
--mount=type=tmpfs,target=/run \
emerge \
  --complete-graph \
  --deep \
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
  --newuse \
  --update \
  --verbose \
  --with-bdeps=y \
  @world \
; \
:;

RUN \
--mount=type=tmpfs,target=/run \
emerge \
  --complete-graph \
  --deep \
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
  --newuse \
  --update \
  --verbose \
  --with-bdeps=y \
  app-eselect/eselect-repository \
  dev-vcs/git \
; \
:;

FROM catalyst as seed
RUN rm --force --recursive /var/db/repos/gentoo
RUN rm --force --recursive /var/tmp/*

FROM catalyst as catalyst_run

COPY dev-util/catalyst/ /var/db/repos/gentoo/dev-util/catalyst/

RUN \
cd /var/db/repos/gentoo/dev-util/catalyst/; \
ebuild catalyst-9999.ebuild manifest; \
:;

RUN \
--mount=type=tmpfs,target=/run \
emerge \
  --autounmask-write \
  --complete-graph \
  --deep \
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
  --newuse \
  --update \
  --verbose \
  --with-bdeps=y \
  =dev-util/catalyst-9999::gentoo \
  sys-fs/squashfs-tools \
; \
:;

COPY --from=seed / /tmp/seed

RUN \
mkdir --parent /var/tmp/catalyst/builds/; \
tar \
  --create \
  --directory=/tmp/seed \
  --file /var/tmp/catalyst/builds/seed.tar \
  . \
;

COPY ./profiles/ /var/db/repos/gentoo/profiles/
COPY sys-apps/attr/ /var/db/repos/gentoo/sys-apps/attr/
COPY sys-libs/musl/ /var/db/repos/gentoo/sys-libs/musl/
COPY ./dev-lang/python/ /var/db/repos/gentoo/dev-lang/python/
RUN \
ebuild /var/db/repos/gentoo/sys-apps/attr/attr-2.5.1.ebuild manifest; \
ebuild /var/db/repos/gentoo/sys-libs/musl/musl-1.2.2-r7.ebuild manifest; \
ebuild /var/db/repos/gentoo/dev-lang/python/python-3.10.3.ebuild manifest; \
:;

RUN \
mkdir --parent /var/tmp/catalyst/snapshots; \
cd /var/db/repos/; \
mksquashfs gentoo /var/tmp/catalyst/snapshots/gentoo-snapshot.sqfs; \
:;

COPY ./_assets/000_catalyst/etc/portage/ /etc/portage/

COPY ./_assets/000_catalyst/etc/catalyst/catalyst.conf /etc/catalyst/
COPY ./_assets/000_catalyst/etc/catalyst/catalystrc /etc/catalyst
COPY ./_assets/000_catalyst/etc/catalyst/specs/bootstrap/stage1.spec /etc/catalyst/specs/bootstrap/stage1.spec

RUN \
--security=insecure \
--mount=type=tmpfs,target=/run \
catalyst --file /etc/catalyst/specs/bootstrap/stage1.spec; \
:;

## TODO: more properly add in LDFLAGS to catalystrc somehow
RUN \
echo 'export LDFLAGS="${LDFLAGS} -Wl,-O2 -Wl,--as-needed -Wl,-z,relro,-z,now -pie -fuse-ld=lld -rtlib=compiler-rt -unwindlib=libunwind"' >> /etc/catalyst/catalystrc; \
:;

COPY ./_assets/000_catalyst/etc/catalyst/specs/bootstrap/stage2.spec /etc/catalyst/specs/bootstrap/stage2.spec
RUN \
--security=insecure \
--mount=type=tmpfs,target=/run \
catalyst --file /etc/catalyst/specs/bootstrap/stage2.spec; \
:;

COPY ./_assets/000_catalyst/etc/catalyst/specs/bootstrap/stage3.spec /etc/catalyst/specs/bootstrap/stage3.spec

RUN \
--security=insecure \
--mount=type=tmpfs,target=/run \
catalyst --file /etc/catalyst/specs/bootstrap/stage3.spec || true; \
:;

#COPY ./_assets/001_catalyst/etc/catalyst/catalystrc /etc/catalyst/
#COPY ./_assets/001_catalyst/etc/catalyst/specs/bootstrapped/stage1.spec /etc/catalyst/specs/bootstrapped/
#
#RUN \
#--security=insecure \
#--mount=type=tmpfs,target=/run \
#catalyst --file /etc/catalyst/specs/optimized/stage1.spec; \
#:;
#
#COPY ./_assets/001_catalyst/etc/catalyst/specs/bootstrapped/stage2.spec /etc/catalyst/specs/bootstrapped/
#
#RUN \
#--security=insecure \
#--mount=type=tmpfs,target=/run \
#catalyst --file /etc/catalyst/specs/optimized/stage2.spec; \
#:;
#
#COPY ./_assets/001_catalyst/etc/catalyst/specs/bootstrapped/stage3.spec /etc/catalyst/specs/bootstrapped/
#
#RUN \
#--security=insecure \
#--mount=type=tmpfs,target=/run \
#catalyst --file /etc/catalyst/specs/optimized/stage3.spec; \
#:;
