# syntax=docker/dockerfile:1.4.1-labs
ARG upstream_snapshot="20220504"
ARG seed_image="gentoo/stage3:musl-${upstream_snapshot}"

FROM $seed_image as seed_build
ARG upstream_snapshot
ARG seed_image

SHELL [ "/bin/bash", "-euxETo", "pipefail", "-c" ]

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
emerge --depclean; \
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

# Sanity rebuild.  If this fails then something way downstream of it is basically sure to fail.
# It takes time here but it saves time overall in the end.
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
emerge --depclean; \
env-update; \
:;

FROM seed_build as seed
RUN rm --force --recursive /var/db/repos/gentoo
RUN rm --force --recursive /var/tmp/*
RUN rm /etc/portage/make.profile

FROM seed_build as catalyst_run

COPY dev-util/catalyst/ /var/db/repos/gentoo/dev-util/catalyst/
RUN \
ebuild /var/db/repos/gentoo/dev-util/catalyst/catalyst-9999.ebuild manifest; \
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
; \
:;

COPY ./profiles/ /var/db/repos/gentoo/profiles/
COPY sys-apps/attr/ /var/db/repos/gentoo/sys-apps/attr/
COPY sys-libs/musl/ /var/db/repos/gentoo/sys-libs/musl/
RUN \
ebuild /var/db/repos/gentoo/sys-apps/attr/attr-2.5.1.ebuild manifest; \
ebuild /var/db/repos/gentoo/sys-libs/musl/musl-1.2.2-r7.ebuild manifest; \
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
catalyst --file /etc/catalyst/specs/bootstrap/stage3.spec; \
:;

RUN \
mkdir --parent /tmp/bootstrap-stage3; \
tar \
  --extract \
  --file /var/tmp/catalyst/builds/clang-musl-container-bootstrap/stage3-amd64-clang-musl-container-bootstrap.tar.gz \
  --directory=/tmp/bootstrap-stage3 \
; \
:;

FROM scratch as bootstrap_objective

COPY --from=catalyst_run /tmp/bootstrap-stage3 /

SHELL [ "/bin/bash", "-euxETo", "pipefail", "-c" ]

RUN \
env-update; \
:;

RUN \
find /usr/bin -xtype l -exec echo rm {} \; ; \
:;

RUN \
for binary in /usr/lib/llvm/14/bin/*; do \
  ln --symbolic --relative "${binary}" "/usr/bin/$(basename "${binary}")"; \
done; \
:;

RUN \
for library in /usr/lib/llvm/14/lib/*.{so,a} /usr/lib/llvm/14/lib/*.{so,a}.*; do \
  if [[ -e "/usr/lib/$(basename "${library}")" ]]; then \
    rm "/usr/lib/$(basename "${library}")"; \
  fi; \
  ln --symbolic --relative "${library}" "/usr/lib/$(basename "${library}")"; \
done; \
:;

RUN \
find /usr/bin -xtype l -exec rm {} \; ; \
ln --symbolic --relative "/usr/bin/clang" "/usr/bin/cc"; \
ln --symbolic --relative "/usr/bin/clang++" "/usr/bin/c++"; \
ln --symbolic --relative "/usr/bin/cc" "/usr/bin/x86_64-gentoo-linux-musl-gcc"; \
ln --symbolic --relative "/usr/bin/c++" "/usr/bin/x86_64-gentoo-linux-musl-g++"; \
:;

FROM catalyst_run as catalyst_run_2

COPY --from=bootstrap_objective / /tmp/bootstrap_objective

RUN \
tar \
 --create \
 --directory=/tmp/bootstrap_objective \
 --file /var/tmp/catalyst/builds/bootstrap.tar \
 . \
; \
:;

COPY ./_assets/001_catalyst/etc/catalyst/catalystrc /etc/catalyst/
COPY ./_assets/001_catalyst/etc/catalyst/specs/bootstrapped/stage1.spec /etc/catalyst/specs/bootstrapped/

RUN \
--security=insecure \
--mount=type=tmpfs,target=/run \
catalyst --file /etc/catalyst/specs/bootstrapped/stage1.spec; \
:;

COPY ./_assets/001_catalyst/etc/catalyst/specs/bootstrapped/stage2.spec /etc/catalyst/specs/bootstrapped/

RUN \
--security=insecure \
--mount=type=tmpfs,target=/run \
catalyst --file /etc/catalyst/specs/bootstrapped/stage2.spec; \
:;

COPY ./_assets/001_catalyst/etc/catalyst/specs/bootstrapped/stage3.spec /etc/catalyst/specs/bootstrapped/

RUN \
--security=insecure \
--mount=type=tmpfs,target=/run \
catalyst --file /etc/catalyst/specs/bootstrapped/stage3.spec; \
:;

RUN \
mkdir --parent /tmp/output; \
tar \
  --extract \
  --file /var/tmp/catalyst/builds/clang-musl-container-bootstrapped/stage3-amd64-clang-musl-container-bootstrapped.tar.gz \
  --directory=/tmp/output \
; \
:;

FROM scratch as output
COPY --from=catalyst_run_2 /tmp/output /
SHELL [ "/bin/bash", "-euxETo", "pipefail", "-c" ]

RUN \
for binary in /usr/lib/llvm/14/bin/*; do \
  ln --symbolic --relative "${binary}" "/usr/bin/$(basename "${binary}")"; \
done; \
:;

RUN \
for library in /usr/lib/llvm/14/lib/*.{so,a} /usr/lib/llvm/14/lib/*.{so,a}.*; do \
  if [[ -e "/usr/lib/$(basename "${library}")" ]]; then \
    rm "/usr/lib/$(basename "${library}")"; \
  fi; \
  ln --symbolic --relative "${library}" "/usr/lib/$(basename "${library}")"; \
done; \
:;

RUN \
find /usr/bin -xtype l -exec rm {} \; ; \
ln --symbolic --relative "/usr/bin/clang" "/usr/bin/cc"; \
ln --symbolic --relative "/usr/bin/clang++" "/usr/bin/c++"; \
:;
