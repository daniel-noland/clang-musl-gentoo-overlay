# syntax=docker/dockerfile:1.4.1-labs
ARG upstream_snapshot="20220415"
ARG seed_image="gentoo/stage3:musl-${upstream_snapshot}"

FROM $seed_image as seed
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
; \
:;

COPY profiles/ /var/db/repos/gentoo/profiles/

COPY --from=seed / /tmp/seed

RUN \
mkdir --parent /var/tmp/catalyst/builds/musl/clang; \
tar \
  --create \
  --file /var/tmp/catalyst/builds/seed.tar \
  --directory=/run/seed \
  . \
;

RUN \
mkdir --parent /var/tmp/catalyst/snapshots; \
cd /var/db/repos/; \
mksquashfs gentoo /var/tmp/catalyst/snapshots/gentoo-snapshot.sqfs; \
:;

COPY ./_assets/000_catalyst/etc/portage/ /etc/portage/

RUN \
catalyst --file /etc/catalyst/specs/bootstrap/stage1.spec; \
:;
